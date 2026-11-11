"""Task 13 (docs/features/treko-ledger.spec.md, section 4, 5.4 and 2 default 3): `ledger_jobs.py` starts every
scan and analyzer one safe way. Owns C7, adds C8's unit row.

Four things are pinned here, each through the module's public names (see the `API ASSUMED` block below):
  * the child-environment builder `build_child_env(base)`: the base's git config variables are dropped, the
    table's rows are set exactly, everything else passes through, the base is not touched (C8's unit row, with
    its falsifier: the same assertion function must reject builders that keep the base's variables);
  * the child registry `ChildRegistry`: one launch method that checks `closed`, starts the process in its own
    session with `env=` the builder's output and registers it, all under the registry's own lock;
  * killing a process group, and the reap bounded by `REAP_WAIT_SECS = 5`;
  * the scan launcher `run_scan` (C7): request on stdin, the bound passed in, the whole group killed at the bound.

`ledger_jobs` is imported inside each test, never at module top, so a missing module fails each test on its own
instead of hiding all of them behind one collection error. Each test names the wrong shortcut it catches.

PROCESS SAFETY. The tests start real processes and kill process groups. Only pids the tests themselves spawned
(a Popen they hold, or a pid a fake child wrote into a file the test owns) are ever signalled, never by name,
and a group is signalled only when it is a group of its own that is not the test's. Every wait is bounded, the
calls that could block run in a daemon thread under `call_bounded`, and the `cleanup` fixture kills what is left
even when an assertion failed. The children print only the `GIT_` variables and one sentinel, never the
environment.
"""

import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

# API ASSUMED (the spec names the behaviour, not the identifiers; the green step must provide these):
#   ledger_jobs.REAP_WAIT_SECS == 5
#   ledger_jobs.RegistryClosed                      exception a refused launch raises
#   ledger_jobs.build_child_env(base) -> dict       a new dict; `base` is read, never changed
#   ledger_jobs.ChildRegistry(base_env, build_env=build_child_env, reap_wait=None, log=None)
#       .lock                                       the registry's own lock (acquire/release)
#       .closed -> bool                             False at first
#       .launch(argv, **popen_kwargs) -> Popen      under .lock: refuse if closed, else start with
#                                                   start_new_session=True and env=build_env(base_env), register
#       .children() -> frozenset of Popen           the registered processes
#       .close()                                    sets .closed
#       .kill_all()                                 SIGKILLs every registered group and reaps each
#       .kill_and_reap(proc, label) -> bool         kill proc's group, then reap_wait(proc, REAP_WAIT_SECS);
#                                                   True = reaped and unregistered; False = wait raised
#                                                   subprocess.TimeoutExpired: log("server: <label> reap timeout
#                                                   <pid>") and proc stays registered
#       reap_wait(proc, timeout) default is proc.wait(timeout=timeout); log(line) default writes line to stderr
#   ledger_jobs.kill_process_group(proc)            kills the whole group proc leads, no wait
#   ledger_jobs.run_scan(registry, request, scan_secs, *, label="scan", program=None) -> result
#       result.code is "ok" or "scan_timeout"; result.stdout is the scan's stdout text; the request goes to the
#       program as JSON on stdin; `program` (a script path run with sys.executable) defaults to ledger_scan.py

HANG_LIMIT_SECS = 20  # the longest any one call in these tests may take before the test calls it hung
POLL_SECS = 0.02
DEAD_WAIT_SECS = 5
BASE_ENV = {"PATH": "/usr/bin:/bin", "HOME": "/nonexistent-home", "LANG": "C"}
SLEEPER_ARGV = [sys.executable, "-c", "import time; time.sleep(300)"]
QUIET = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}

# The rows of section 2 default 3's table, written out here and not read from the module under test.
TABLE_ROWS = {
    "GIT_CONFIG_COUNT": "3",
    "GIT_CONFIG_KEY_0": "core.fsmonitor", "GIT_CONFIG_VALUE_0": "false",
    "GIT_CONFIG_KEY_1": "core.hooksPath", "GIT_CONFIG_VALUE_1": "/dev/null",
    "GIT_CONFIG_KEY_2": "log.showSignature", "GIT_CONFIG_VALUE_2": "false",
    "GIT_OPTIONAL_LOCKS": "0",
    "GIT_NO_LAZY_FETCH": "1",
}
FAMILY = re.compile(r"^GIT_CONFIG_(COUNT|PARAMETERS|KEY_\d+|VALUE_\d+)$")

# C8's unit row: GIT_CONFIG_COUNT=5 with pairs _0.._4, so the result's 3 differs from the base's and pairs _3 and
# _4 sit above the builder's own count, where only a drop removes them. Every base value is distinctive.
UNIT_BASE = {
    "PATH": "/usr/bin:/bin", "HOME": "/base-home", "LANG": "C", "UNRELATED": "kept",
    "GIT_CONFIG_GLOBAL": "/base/gitconfig",
    "GIT_CONFIG_PARAMETERS": "'core.fsmonitor=/base/marker.sh'",
    "GIT_CONFIG_COUNT": "5",
    "GIT_OPTIONAL_LOCKS": "1", "GIT_NO_LAZY_FETCH": "0",
    **{"GIT_CONFIG_KEY_%d" % n: "base.key%d" % n for n in range(5)},
    **{"GIT_CONFIG_VALUE_%d" % n: "base-value-%d" % n for n in range(5)},
}

# stdout is inherited by a grandchild, so a kill that spares the group leaves the pipe open: the failure shows
# as a hang, which `call_bounded` turns into a failure.
HANG_DEF = '''
import json, os, subprocess, sys, time

def hang(pidfile):
    grandchild = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(300)"], stdin=subprocess.DEVNULL)
    tmp = pidfile + ".tmp"
    with open(tmp, "w") as handle:
        json.dump({"child": os.getpid(), "grandchild": grandchild.pid}, handle)
    os.replace(tmp, pidfile)
    time.sleep(300)
'''
HANG_CODE = HANG_DEF + "\nhang(sys.argv[1])\n"
FAKE_SCAN = HANG_DEF + '''
request = json.load(sys.stdin)
mode = request.get("mode")
if mode == "hang":
    hang(request["pidfile"])
if mode == "slow":
    time.sleep(request["secs"])
seen = {k: v for k, v in os.environ.items() if k.startswith("GIT_") or k == "TREKO_TEST_LEAK"}
print(json.dumps({"request": request, "pid": os.getpid(), "pgid": os.getpgrp(), "sid": os.getsid(0), "env": seen}))
'''


def jobs():
    """The module under test, imported at call time so each test fails on its own while it does not exist."""
    import ledger_jobs
    return ledger_jobs


# ------------------------------------------------------------------------------------ safety helpers

def kill_group(pid):
    """SIGKILL the group `pid` leads, only when it is a group of its own that is not this test's."""
    try:
        pgid = os.getpgid(pid)
    except ProcessLookupError:
        return
    if pgid != pid or pgid == os.getpgrp():
        return
    try:
        os.killpg(pgid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):  # macOS answers EPERM for a group that is only a zombie
        pass


def kill_pid(pid):
    try:
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


class Cleanup:
    """What the test spawned, found again at teardown: Popen objects, registries, fake-child pid files."""

    def __init__(self):
        self.procs = []
        self.registries = []
        self.pidfiles = []

    def run(self):
        procs = list(self.procs)
        for registry in self.registries:
            try:
                procs.extend(registry.children())
            except Exception:  # noqa: BLE001 — teardown must still reach the pid files when the registry is broken
                pass
        procs = list(dict.fromkeys(procs))  # a process the test tracked and the registry holds is killed once
        for proc in procs:
            kill_group(proc.pid)
            proc.kill()
        for pidfile in self.pidfiles:
            if pidfile.exists():
                for pid in json.loads(pidfile.read_text()).values():
                    kill_pid(pid)
        for proc in procs:
            try:
                proc.wait(timeout=DEAD_WAIT_SECS)
            except subprocess.TimeoutExpired:
                pass
            for stream in (proc.stdin, proc.stdout, proc.stderr):
                if stream:
                    stream.close()


@pytest.fixture
def cleanup():
    cleaner = Cleanup()
    yield cleaner
    cleaner.run()


@pytest.fixture
def make_registry(cleanup):
    """`make(base_env=None, **kwargs) -> (registry, lines)`; `lines` collects what the registry logs."""
    def make(base_env=None, **kwargs):
        lines = []
        kwargs.setdefault("log", lines.append)
        registry = jobs().ChildRegistry(dict(BASE_ENV) if base_env is None else base_env, **kwargs)
        cleanup.registries.append(registry)
        return registry, lines
    return make


def call_bounded(fn, limit=HANG_LIMIT_SECS):
    """fn() in a daemon thread; a call still running at `limit` fails the test instead of hanging it."""
    box = {}

    def target():
        try:
            box["value"] = fn()
        except BaseException as error:  # noqa: BLE001 — handed back to the test thread below
            box["error"] = error

    thread = threading.Thread(target=target, daemon=True)
    thread.start()
    thread.join(limit)
    if thread.is_alive():
        pytest.fail("the call was still running after %d s: a kill that spared a process holding the pipe?" % limit)
    if "error" in box:
        raise box["error"]
    return box["value"]


def wait_for_file(path, limit=HANG_LIMIT_SECS):
    deadline = time.monotonic() + limit
    while time.monotonic() < deadline:
        if path.exists():
            return json.loads(path.read_text())
        time.sleep(POLL_SECS)
    pytest.fail("%s was never written: the fake child did not start" % path.name)


def is_dead(pid, limit=DEAD_WAIT_SECS):
    """True once `pid` no longer exists. For a process the test did not parent; a child of the test needs wait()."""
    deadline = time.monotonic() + limit
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        time.sleep(POLL_SECS)
    return False


def fake_scan(tmp_path):
    path = tmp_path / "fake_scan.py"
    path.write_text(FAKE_SCAN, encoding="utf-8")
    return path


def launch_hanger(registry, cleanup, tmp_path, name):
    """A registered child that has a grandchild in its group. Returns (proc, pids from its pid file)."""
    pidfile = tmp_path / (name + ".json")
    cleanup.pidfiles.append(pidfile)
    proc = registry.launch([sys.executable, "-c", HANG_CODE, str(pidfile)], **QUIET)
    return proc, wait_for_file(pidfile)


# ------------------------------------------------------------------------------------ C8 unit row

def check_unit_row(builder):
    """C8's unit row, as one assertion function so the falsifier can run the very same checks on a bad builder."""
    base = dict(UNIT_BASE)
    result = builder(base)
    assert base == UNIT_BASE, "the builder changed the base it was given"
    assert result is not base, "the builder returned the base itself, not a copy"
    assert "GIT_CONFIG_PARAMETERS" not in result, "GIT_CONFIG_PARAMETERS survived: probe 3 writes the marker"
    base_family = {name: value for name, value in UNIT_BASE.items() if FAMILY.match(name)}
    leaked = {name for name, value in result.items() if value in base_family.values()}
    assert not leaked, "the result holds the base's values for %s" % sorted(leaked)
    family = {name: value for name, value in result.items() if FAMILY.match(name)}
    assert family == {name: value for name, value in TABLE_ROWS.items() if FAMILY.match(name)}, family
    assert result["GIT_OPTIONAL_LOCKS"] == TABLE_ROWS["GIT_OPTIONAL_LOCKS"]
    assert result["GIT_NO_LAZY_FETCH"] == TABLE_ROWS["GIT_NO_LAZY_FETCH"]
    untouched = {name: value for name, value in UNIT_BASE.items()
                 if not FAMILY.match(name) and name not in ("GIT_OPTIONAL_LOCKS", "GIT_NO_LAZY_FETCH")}
    assert result == {**untouched, **TABLE_ROWS}, "every other base key must pass through unchanged, and nothing else added"


def test_builder_meets_c8s_unit_row():
    """The row as the spec words it. Catches a builder that copies the base and adds the table on top (it keeps
    GIT_CONFIG_PARAMETERS and the base's pairs _3 and _4), or one that sets some table row only when absent."""
    check_unit_row(jobs().build_child_env)


def keeps_the_whole_family(base):
    env = dict(base)
    env.update(TABLE_ROWS)
    return env


def drops_the_pairs_but_keeps_parameters(base):
    env = {name: value for name, value in base.items() if not re.match(r"^GIT_CONFIG_(COUNT|KEY_\d+|VALUE_\d+)$", name)}
    env.update(TABLE_ROWS)
    return env


def overwrites_zero_to_two_but_keeps_the_high_pairs(base):
    env = {name: value for name, value in base.items() if name != "GIT_CONFIG_PARAMETERS"}
    env.update(TABLE_ROWS)  # the round-3 row: _0.._2 are overwritten by the table anyway, _3 and _4 are not
    return env


def mutates_the_base(base):
    for name in [name for name in base if FAMILY.match(name)]:
        del base[name]
    return {**base, **TABLE_ROWS}


@pytest.mark.parametrize("stand_in", [keeps_the_whole_family, drops_the_pairs_but_keeps_parameters,
                                      overwrites_zero_to_two_but_keeps_the_high_pairs, mutates_the_base])
def test_unit_row_rejects_a_builder_that_keeps_the_base_family(stand_in):
    """C8's falsifier. The same assertion function accepts the real builder and fails each stand-in, so the row can
    fail: a row that passes whatever the builder does (pairs _0.._2 are overwritten either way) proves nothing."""
    check_unit_row(jobs().build_child_env)
    with pytest.raises(AssertionError):
        check_unit_row(stand_in)


def test_builder_drops_every_numbered_pair_whatever_the_number_and_keeps_the_config_file_variable():
    """Section 2 default 3: every GIT_CONFIG_KEY_<n>/VALUE_<n> goes, "whatever <n>"; GIT_CONFIG_GLOBAL is not part of
    the family and passes through (C8's GIT_CONFIG_GLOBAL row relies on the pairs overriding the file)."""
    base = {"PATH": "/usr/bin", "GIT_CONFIG_GLOBAL": "/base/gitconfig", "GIT_CONFIG_KEY_17": "x.y", "GIT_CONFIG_VALUE_17": "/boom",
            "GIT_CONFIG_KEY_100": "x.z", "GIT_CONFIG_VALUE_100": "/boom"}
    result = jobs().build_child_env(base)
    assert result == {"PATH": "/usr/bin", "GIT_CONFIG_GLOBAL": "/base/gitconfig", **TABLE_ROWS}


def test_builder_reads_only_the_base_it_is_given(monkeypatch):
    """Section 2 default 3 and C8's AST check: the base is passed in. A builder that starts from os.environ.copy()
    would carry the test process's variables into a child built from an empty base."""
    monkeypatch.setenv("GIT_CONFIG_PARAMETERS", "'core.fsmonitor=/process/marker.sh'")
    monkeypatch.setenv("TREKO_TEST_LEAK", "leaked")
    assert jobs().build_child_env({}) == TABLE_ROWS


# ------------------------------------------------------------------------------------ the registry

def test_reap_wait_is_five_seconds():
    """Section 5.4: REAP_WAIT_SECS = 5, a constant in ledger_jobs.py."""
    assert jobs().REAP_WAIT_SECS == 5


def test_launch_registers_the_process_in_a_session_of_its_own(make_registry, cleanup):
    """Section 4: every child starts in its own process group so a kill can take the group. Catches a launch that
    leaves the child in the server's group (a group kill would then take the server) or does not register it."""
    registry, _ = make_registry()
    assert registry.closed is False
    proc = registry.launch(SLEEPER_ARGV, **QUIET)
    cleanup.procs.append(proc)
    assert proc in registry.children()
    assert os.getpgid(proc.pid) == proc.pid != os.getpgrp(), "the child is not the leader of a group of its own"
    assert os.getsid(proc.pid) != os.getsid(0), "the child shares the test's session"


def test_launch_gives_the_child_the_builders_output_and_nothing_inherited(make_registry, cleanup, monkeypatch):
    """Section 4: `env=` is the builder's output. Catches a launch with no `env=` (the child inherits the whole
    server environment, GIT_CONFIG_PARAMETERS included) and one that merges the process environment in."""
    monkeypatch.setenv("TREKO_TEST_LEAK", "leaked")
    registry, _ = make_registry(base_env={**BASE_ENV, "GIT_CONFIG_PARAMETERS": "'core.fsmonitor=/base/marker.sh'",
                                          "GIT_CONFIG_COUNT": "5", "GIT_CONFIG_KEY_4": "base.key4", "GIT_CONFIG_VALUE_4": "v"})
    code = ("import json, os; print(json.dumps({k: v for k, v in os.environ.items() "
            "if k.startswith('GIT_') or k == 'TREKO_TEST_LEAK'}))")
    proc = registry.launch([sys.executable, "-c", code], stdout=subprocess.PIPE, text=True)
    cleanup.procs.append(proc)
    out, _unused = proc.communicate(timeout=HANG_LIMIT_SECS)
    assert json.loads(out) == TABLE_ROWS


def test_launch_uses_the_builder_passed_in(make_registry, cleanup):
    """C8's in-process hook: a different builder passed as a parameter in code is the only way to run without the
    protection. Catches a registry that calls the module's builder directly and ignores the parameter."""
    registry, _ = make_registry(build_env=lambda base: {**base, "TREKO_TEST_LEAK": "stand-in"})
    proc = registry.launch([sys.executable, "-c", "import os; print(os.environ['TREKO_TEST_LEAK'])"],
                           stdout=subprocess.PIPE, text=True)
    cleanup.procs.append(proc)
    assert proc.communicate(timeout=HANG_LIMIT_SECS)[0].strip() == "stand-in"


def test_a_closed_registry_starts_nothing(make_registry, cleanup, monkeypatch, tmp_path):
    """Section 4 and D-criteria for shutdown: a launch the closed registry refuses starts nothing. Catches a
    registry with no `closed` check (the falsifier of the spec): a family would start after the sweep. Proved three
    ways, because one alone can be fooled: no Popen call, no marker from the would-be child, nothing registered."""
    mod = jobs()
    registry, _ = make_registry()
    registry.close()
    assert registry.closed is True
    spawned = []
    real_popen = subprocess.Popen

    class SpyPopen(real_popen):
        def __init__(self, *args, **kwargs):
            spawned.append(args)
            super().__init__(*args, **kwargs)

    monkeypatch.setattr(subprocess, "Popen", SpyPopen)
    marker = tmp_path / "started"
    with pytest.raises(mod.RegistryClosed):
        registry.launch([sys.executable, "-c", "open(%r, 'w').write('x')" % str(marker)], **QUIET)
    time.sleep(0.5)  # a child that was started would have written by now
    assert spawned == [] and not marker.exists()
    assert registry.children() == frozenset()


def test_a_scan_asked_of_a_closed_registry_starts_nothing(make_registry, tmp_path):
    """Section 4 and 5.4 step 2: the scan launcher goes through the registry's launch, so a closed registry refuses
    it too. Catches a scan launcher that starts its own Popen."""
    mod = jobs()
    registry, _ = make_registry()
    registry.close()
    marker = tmp_path / "started"
    program = tmp_path / "marker_scan.py"
    program.write_text("open(%r, 'w').write('x')\n" % str(marker), encoding="utf-8")
    with pytest.raises(mod.RegistryClosed):
        call_bounded(lambda: mod.run_scan(registry, {"mode": "echo"}, 5, program=program))
    time.sleep(0.5)
    assert not marker.exists()


def test_closing_then_killing_all_kills_every_registered_group(make_registry, cleanup, tmp_path):
    """Section 5.3 shutdown: set `closed`, then kill every registered group. Catches a sweep that kills only the
    pids (the grandchildren live on) or only the first process."""
    registry, _ = make_registry()
    started = [launch_hanger(registry, cleanup, tmp_path, name) for name in ("one", "two")]
    registry.close()
    call_bounded(registry.kill_all)
    for proc, pids in started:
        assert proc.wait(timeout=DEAD_WAIT_SECS) is not None
        assert is_dead(pids["grandchild"]), "the grandchild in the group survived the sweep"
    with pytest.raises(jobs().RegistryClosed):
        registry.launch(SLEEPER_ARGV, **QUIET)


def test_kill_process_group_takes_the_grandchild_too(make_registry, cleanup, tmp_path):
    """Section 4: the group is killed, not the pid. Catches os.kill(pid) / Popen.kill(), which leave the grandchild
    (an analyzer's git child) running beside the next job."""
    registry, _ = make_registry()
    proc, pids = launch_hanger(registry, cleanup, tmp_path, "group")
    jobs().kill_process_group(proc)
    assert proc.wait(timeout=DEAD_WAIT_SECS) is not None
    assert is_dead(pids["grandchild"]), "the grandchild is still alive: only the leader was killed"


def test_registry_lock_is_its_own_and_the_ledger_lock_never_blocks_it(make_registry, cleanup):
    """Section 4: "a set guarded by its own lock, never the ledger lock, so a shutdown kill never waits on a slow
    ledger write." With a stand-in ledger lock held by the test, launch, close and kill_all still finish, and the
    registry's lock is a different object. Catches a registry built on the ledger's lock."""
    registry, _ = make_registry()
    ledger_lock = threading.Lock()
    assert registry.lock is not ledger_lock
    with ledger_lock:
        proc = call_bounded(lambda: registry.launch(SLEEPER_ARGV, **QUIET))
        cleanup.procs.append(proc)
        call_bounded(lambda: (registry.close(), registry.kill_all()))
    assert proc.wait(timeout=DEAD_WAIT_SECS) is not None


def test_launch_checks_starts_and_registers_under_the_registry_lock(make_registry, cleanup):
    """Section 4: the check, the start and the registration all happen before the lock is released. While the test
    holds the registry's lock a launch must wait; catches a launch that checks `closed` outside the lock (it could
    start after the sweep) or never takes it."""
    registry, _ = make_registry()
    box = {}
    thread = threading.Thread(target=lambda: box.setdefault("proc", registry.launch(SLEEPER_ARGV, **QUIET)), daemon=True)
    registry.lock.acquire()
    try:
        thread.start()
        thread.join(0.5)
        blocked = thread.is_alive()
    finally:
        registry.lock.release()
    thread.join(HANG_LIMIT_SECS)
    assert not thread.is_alive()
    cleanup.procs.append(box["proc"])
    assert blocked, "launch ran while the registry's lock was held by someone else"


def test_a_reap_that_never_sees_the_end_writes_the_line_and_leaves_the_process_registered(make_registry, cleanup):
    """Section 5.4 step 1 / D14: the wait is given REAP_WAIT_SECS, its expiry writes
    `server: <label> reap timeout <pid>`, and the process stays registered for shutdown's sweep. Catches a wait with
    no limit (it would be handed None), a wrong or missing line, and a process dropped from the registry on expiry.
    The kill itself still lands: the real process is dead even though the injected wait never saw it."""
    given = []

    def never_sees_the_end(proc, timeout):
        given.append(timeout)
        raise subprocess.TimeoutExpired(proc.args, timeout)

    registry, lines = make_registry(reap_wait=never_sees_the_end)
    proc = registry.launch(SLEEPER_ARGV, **QUIET)
    cleanup.procs.append(proc)
    assert call_bounded(lambda: registry.kill_and_reap(proc, "job item-7")) is False
    assert given == [5]
    assert lines == ["server: job item-7 reap timeout %d" % proc.pid]
    assert proc in registry.children()
    assert proc.wait(timeout=DEAD_WAIT_SECS) < 0, "the group was never signalled"


def test_a_reap_that_succeeds_unregisters_the_process_and_writes_no_line(make_registry, cleanup):
    """Section 4: a process is removed from the registry when it is reaped. Catches a registry that never forgets a
    process, and a reap that logs even on success."""
    registry, lines = make_registry()
    proc = registry.launch(SLEEPER_ARGV, **QUIET)
    cleanup.procs.append(proc)
    assert call_bounded(lambda: registry.kill_and_reap(proc, "scan")) is True
    assert proc.returncode is not None
    assert proc not in registry.children()
    assert lines == []


# ------------------------------------------------------------------------------------ the scan launcher (C7)

def test_a_scan_that_hangs_is_killed_at_the_bound_with_its_whole_group(make_registry, cleanup, tmp_path):
    """C7. A fake scan hangs and has a grandchild in its group that holds the stdout pipe. At a 2 second bound the
    result is `scan_timeout`, the scan and the grandchild are both dead, and the registry is empty again. Catches a
    bound that is ignored (the call hangs), a kill of the pid alone (the grandchild lives and the pipe never closes)
    and a reap that leaves the process registered."""
    mod = jobs()
    registry, lines = make_registry()
    pidfile = tmp_path / "scan.json"
    cleanup.pidfiles.append(pidfile)
    request = {"mode": "hang", "pidfile": str(pidfile)}
    started = time.monotonic()
    result = call_bounded(lambda: mod.run_scan(registry, request, 2, program=fake_scan(tmp_path)))
    elapsed = time.monotonic() - started
    assert result.code == "scan_timeout"
    assert 1.5 <= elapsed < 12, "the bound is the value passed in (2 s), not a timer of the module's own: %.1f s" % elapsed
    pids = json.loads(pidfile.read_text())
    assert is_dead(pids["child"]) and is_dead(pids["grandchild"]), "the scan or its grandchild survived the kill"
    assert registry.children() == frozenset() and lines == []


def test_the_bound_is_the_value_passed_in(make_registry, cleanup, tmp_path):
    """C7 / section 4: TREKO_SCAN_SECS is passed in. The same 2.5 second scan is cut at a 1 second bound and
    finishes under a 6 second one. Catches a launcher with a bound of its own (30 s or any other constant)."""
    mod = jobs()
    program = fake_scan(tmp_path)
    request = {"mode": "slow", "secs": 2.5}
    registry, _ = make_registry()
    started = time.monotonic()
    short = call_bounded(lambda: mod.run_scan(registry, request, 1, program=program))
    assert short.code == "scan_timeout" and time.monotonic() - started < 2.4
    long_ = call_bounded(lambda: mod.run_scan(registry, request, 6, program=program))
    assert long_.code == "ok"


def test_a_scan_that_finishes_in_time_returns_its_output_and_gets_the_request_on_stdin(make_registry, tmp_path):
    """C7 / section 4: the request is JSON on stdin and stdout comes back. Catches a launcher that passes the request
    as an argument, loses stdout, or reports a clean scan as a timeout."""
    mod = jobs()
    registry, lines = make_registry()
    request = {"mode": "echo", "directory": "/some/dir", "repo": "", "branch": "", "worktree": ""}
    result = call_bounded(lambda: mod.run_scan(registry, request, 20, program=fake_scan(tmp_path)))
    assert result.code == "ok"
    assert json.loads(result.stdout)["request"] == request
    assert registry.children() == frozenset() and lines == []


def test_the_scan_starts_with_the_built_environment_in_a_group_of_its_own(make_registry, monkeypatch, tmp_path):
    """Section 4 and 2 default 3: the scan is a registry launch. Its child sees the builder's rows, none of the
    base's git config variables and none of the test process's environment, and leads its own group and session.
    Catches a scan launcher that calls Popen itself with the inherited environment."""
    mod = jobs()
    monkeypatch.setenv("TREKO_TEST_LEAK", "leaked")
    registry, _ = make_registry(base_env={**BASE_ENV, "GIT_CONFIG_PARAMETERS": "'core.fsmonitor=/base/marker.sh'",
                                          "GIT_CONFIG_COUNT": "5", "GIT_CONFIG_KEY_4": "base.key4", "GIT_CONFIG_VALUE_4": "v"})
    result = call_bounded(lambda: mod.run_scan(registry, {"mode": "echo"}, 20, program=fake_scan(tmp_path)))
    seen = json.loads(result.stdout)
    assert seen["env"] == TABLE_ROWS
    assert seen["pgid"] == seen["pid"] != os.getpgrp()
    assert seen["sid"] != os.getsid(0)


@pytest.mark.parametrize("label", ["scan", "job item-7"])
def test_a_timed_out_scan_whose_reap_never_ends_still_answers_scan_timeout(make_registry, cleanup, tmp_path, label):
    """Section 4 / D15: when the reap wait after the time-limit kill expires, the answer is the one the scan would
    have had, `scan_timeout`, with exactly one reap-timeout line naming the killed pid (`server: scan reap timeout`
    at submit, `server: job <item> reap timeout` at job time) and the process left in the registry. Catches a
    launcher that waits without a limit, raises, or forgets the process."""
    mod = jobs()
    given = []

    def never_sees_the_end(proc, timeout):
        given.append(timeout)
        raise subprocess.TimeoutExpired(proc.args, timeout)

    registry, lines = make_registry(reap_wait=never_sees_the_end)
    pidfile = tmp_path / "scan.json"
    cleanup.pidfiles.append(pidfile)
    request = {"mode": "hang", "pidfile": str(pidfile)}
    result = call_bounded(lambda: mod.run_scan(registry, request, 2, label=label, program=fake_scan(tmp_path)))
    assert result.code == "scan_timeout"
    pid = json.loads(pidfile.read_text())["child"]
    assert given == [5]
    assert lines == ["server: %s reap timeout %d" % (label, pid)]
    assert [proc.pid for proc in registry.children()] == [pid]
