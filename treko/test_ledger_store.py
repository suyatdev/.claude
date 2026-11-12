"""Task 15 (docs/features/treko-ledger.spec.md, sections 5.1 and 5.6; decision D44): the queue lives in
`<store dir>/ledger.json`, survives a restart, and one server owns a store folder. Owns D5.

Two layers are pinned here, each through public names only (see the `API ASSUMED` block below):
  * `ledger_state` units: loading, the atomic write and its failure rules, the store lock, and the
    all-or-nothing `Ledger.update` with a store folder;
  * server level: a bad ledger file, or a store folder another server holds, aborts startup with exit 2
    naming the cause and serving nothing; the lock is taken only after the bind.

`ledger_state` is imported inside each test, never at module top, so a missing name fails each test on its
own instead of hiding all of them behind one collection error. Each test names the wrong shortcut it
catches. Task 14 and later (routes, the runner, queue operations) are not tested here.

SAFETY. Everything lives under pytest's tmp_path; no real store folder or ledger is touched. The one
process killed is the child a test spawned (it SIGKILLs itself). Every wait is bounded, a launched server is
stopped by the `launcher` fixture, and every chmod is undone by `chmod_guard` even when an assertion failed.
"""

import contextlib
import copy
import errno
import json
import os
import signal
import stat
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import server_harness as harness  # noqa: E402

# API ASSUMED (decision D44; the spec names the behaviour, D44 names these identifiers). All in ledger_state:
#   load_ledger(store_dir) -> dict      absent file -> the empty ledger; unparseable, unreadable (OSError other
#                                       than absence), version != 1 or a broken rule -> LedgerStartupError whose
#                                       message names the file and, for an OS error, the errno symbolic name
#   write_ledger(store_dir, state)      temp file in store_dir, fsync, os.replace, final mode 0o600; on failure the
#                                       old file stays whole, the temp file is removed, stderr gets
#                                       "server: ledger write failed: <errno name>" (never a field value) and
#                                       LedgerWriteError is raised
#   acquire_store_lock(store_dir)       flock(LOCK_EX | LOCK_NB) on <store_dir>/.treko-server.lock (0o600, never
#                                       deleted); returns the open file; held -> LedgerStartupError "another Treko
#                                       server is using <store dir>"; unopenable -> LedgerStartupError naming the
#                                       errno symbolic name
#   LedgerStartupError, LedgerWriteError
#   Ledger(state=None, store_dir=None)  with a store_dir, update() calls the module-level write_ledger(store_dir,
#                                       new_state) BEFORE the in-memory state is replaced; a failed write makes
#                                       update raise LedgerWriteError; without one, nothing is written
# store_dir is passed as a pathlib.Path (the server holds one); update(change) keeps today's contract:
# the new state is `change(copy of state)`'s return value.

TREKO_DIR = Path(__file__).resolve().parent
LEDGER_FILE = "ledger.json"
LOCK_FILE = ".treko-server.lock"
OWNER_ONLY = 0o600
LOCK_MESSAGE = "another Treko server is using"
WRITE_FAILED = "server: ledger write failed: %s"
SERVE_FAILED_EXIT = 2
CHILD_WAIT_SECS = 20
ABORT_WAIT_SECS = 8

EMPTY = {"version": 1, "queue": [], "hidden": [], "requests": {}}
RUN = "r3fa9c2d17b40e815"
SECRET_DIR = "/SECRET-FIELD-VALUE-8c1f2d"  # must never reach stderr from a failed write

NOT_ROOT = pytest.mark.skipif(os.geteuid() == 0, reason="root ignores file modes")


def ls():
    """The module under test, imported at call time so each test fails on its own while a name is missing."""
    import ledger_state
    return ledger_state


def populated_state(directory="/Users/x/dev"):
    """Section 5.1's example: one waiting item, one hidden run id, one requests entry."""
    request = {"directory": directory, "repo": "memsearch", "branch": "", "worktree": ""}
    return {
        "version": 1,
        "queue": [{"item": "9f2c4a1b7d3e5f60", "state": "waiting", "queuedAt": "2026-11-03T09:12:44Z",
                   "request": dict(request), "run": RUN, "error": None, "detail": None}],
        "hidden": ["r0c4d1e2f3a4b5c6d"],
        "requests": {RUN: dict(request)},
    }


def write_raw(folder, text):
    path = Path(folder) / LEDGER_FILE
    path.write_text(text)
    return path


def mode_of(path):
    return stat.S_IMODE(os.stat(str(path)).st_mode)


@contextlib.contextmanager
def open_umask():
    """umask 0, so a file made without an explicit 0o600 comes out 0o666 and shows it."""
    previous = os.umask(0)
    try:
        yield
    finally:
        os.umask(previous)


@pytest.fixture
def chmod_guard():
    """chmod(path, mode) that is always undone, so tmp_path can be cleaned up."""
    saved = []

    def chmod(path, mode):
        saved.append((str(path), mode_of(path)))
        os.chmod(str(path), mode)

    yield chmod
    for path, mode in reversed(saved):
        try:
            os.chmod(path, mode)
        except OSError:
            pass


# ----------------------------------------------------------------------------------- loading

def test_an_absent_ledger_file_loads_as_the_empty_ledger(tmp_path):
    # Wrong shortcut: treating a missing file as an error (a first run could never start) or returning None.
    assert ls().load_ledger(tmp_path) == EMPTY


def test_write_then_load_round_trips_and_the_file_is_owner_only(tmp_path):
    # Wrong shortcut: a plain open(path, "w") gives 0o666 under umask 0, and keeps an old file's wider mode.
    mod = ls()
    state = populated_state()
    with open_umask():
        mod.write_ledger(tmp_path, state)
    path = tmp_path / LEDGER_FILE
    assert json.loads(path.read_text()) == state
    assert mod.load_ledger(tmp_path) == state
    assert mode_of(path) == OWNER_ONLY

    os.chmod(str(path), 0o644)  # an existing file with a wider mode must not carry it over
    newer = populated_state()
    newer["hidden"] = []
    with open_umask():
        mod.write_ledger(tmp_path, newer)
    assert mod.load_ledger(tmp_path) == newer
    assert mode_of(path) == OWNER_ONLY
    assert os.listdir(str(tmp_path)) == [LEDGER_FILE], "a successful write left a temp file behind"


def broken(**changes):
    state = populated_state()
    state.update(changes)
    return json.dumps(state)


def missing_key():
    state = populated_state()
    del state["hidden"]
    return json.dumps(state)


def bad_item_state():
    state = populated_state()
    state["queue"][0]["state"] = "paused"
    return json.dumps(state)


BAD_FILES = {
    "invalid-json": "{not json",
    "empty-file": "",
    "not-an-object": "[]",
    "version-2": broken(version=2),
    "queue-not-a-list": broken(queue={"item": "x"}),
    "item-state-not-allowed": bad_item_state(),
    "missing-top-level-key": missing_key(),
    "hidden-not-a-list": broken(hidden="r0c4d"),
    "requests-not-an-object": broken(requests=[]),
}


@pytest.mark.parametrize("text", list(BAD_FILES.values()), ids=list(BAD_FILES))
def test_a_bad_ledger_file_refuses_to_load_and_names_the_file(tmp_path, text):
    # Wrong shortcut: falling back to an empty ledger, which would drop waiting work and un-hide every run.
    mod = ls()
    path = write_raw(tmp_path, text)
    with pytest.raises(mod.LedgerStartupError) as caught:
        mod.load_ledger(tmp_path)
    assert str(path) in str(caught.value)


@NOT_ROOT
def test_an_unreadable_ledger_file_refuses_to_load_naming_file_and_errno(tmp_path, chmod_guard):
    # Wrong shortcut: catching only absence and parse errors, so EACCES escapes as a raw OSError.
    mod = ls()
    path = write_raw(tmp_path, json.dumps(EMPTY))
    chmod_guard(path, 0)
    with pytest.raises(mod.LedgerStartupError) as caught:
        mod.load_ledger(tmp_path)
    assert str(path) in str(caught.value)
    assert errno.errorcode[errno.EACCES] in str(caught.value)


# ----------------------------------------------------------------------------- write failures

@pytest.mark.parametrize("had_old_file", [True, False], ids=["old-file", "first-write"])
@pytest.mark.parametrize("failing_call", ["replace", "fsync"])
def test_a_failed_write_leaves_the_old_file_whole_and_names_only_the_errno(
        tmp_path, monkeypatch, capfd, failing_call, had_old_file):
    # Wrong shortcuts: writing in place (a failure truncates the file), leaving the temp file, naming
    # the field values in the message, or swallowing the failure instead of raising.
    mod = ls()
    old_bytes = json.dumps(populated_state()).encode()
    if had_old_file:
        (tmp_path / LEDGER_FILE).write_bytes(old_bytes)
    seen = {}

    def fail(*args, **kwargs):
        if args and isinstance(args[0], (str, bytes, os.PathLike)):
            seen["source"] = os.fsdecode(args[0])
        raise OSError(errno.ENOSPC, "No space left on device")

    monkeypatch.setattr(os, failing_call, fail)
    new_state = populated_state(directory=SECRET_DIR)
    with pytest.raises(mod.LedgerWriteError):
        mod.write_ledger(tmp_path, new_state)
    monkeypatch.undo()

    if had_old_file:
        assert (tmp_path / LEDGER_FILE).read_bytes() == old_bytes
        assert os.listdir(str(tmp_path)) == [LEDGER_FILE], "the temp file was left in the store folder"
    else:
        assert os.listdir(str(tmp_path)) == [], "a failed first write left a file behind"
    if failing_call == "replace":  # the temp file must sit beside the target, or the rename is not atomic
        assert os.path.dirname(seen["source"]) == str(tmp_path)
    captured = capfd.readouterr()
    assert (WRITE_FAILED % "ENOSPC") in captured.err.splitlines()
    assert SECRET_DIR not in captured.err and SECRET_DIR not in captured.out


KILL_CHILD = """
import json, os, signal, sys
sys.path.insert(0, sys.argv[1])
import ledger_state
store, point, new_state = sys.argv[2], sys.argv[3], json.loads(sys.argv[4])

def die(*args, **kwargs):
    os.kill(os.getpid(), signal.SIGKILL)

if point != "none":
    setattr(os, point, die)
ledger_state.write_ledger(store, new_state)
"""


@pytest.mark.parametrize("point", ["fsync", "replace"])
def test_a_kill_in_the_middle_of_a_write_leaves_the_old_content(tmp_path, point):
    # Wrong shortcut: an in-place write truncates the file first, so a kill leaves it empty or partial.
    mod = ls()
    old = populated_state()
    new = populated_state(directory="/Users/y/other")
    write_raw(tmp_path, json.dumps(old))

    done = subprocess.run([sys.executable, "-c", KILL_CHILD, str(TREKO_DIR), str(tmp_path), point,
                           json.dumps(new)], capture_output=True, text=True, timeout=CHILD_WAIT_SECS)
    assert done.returncode == -signal.SIGKILL, "the child was not killed mid-write (%r):\n%s" % (
        done.returncode, done.stderr)
    assert json.loads((tmp_path / LEDGER_FILE).read_text()) == old
    assert mod.load_ledger(tmp_path) == old, "the next start would not load the old content"


def test_the_kill_harness_lets_an_unpatched_write_through(tmp_path):
    # The control for the test above: with nothing patched the same child finishes and the NEW content lands,
    # so "old content" there cannot be explained by a child that never wrote.
    mod = ls()
    new = populated_state(directory="/Users/y/other")
    write_raw(tmp_path, json.dumps(populated_state()))
    done = subprocess.run([sys.executable, "-c", KILL_CHILD, str(TREKO_DIR), str(tmp_path), "none",
                           json.dumps(new)], capture_output=True, text=True, timeout=CHILD_WAIT_SECS)
    assert done.returncode == 0, done.stderr
    assert mod.load_ledger(tmp_path) == new


# ------------------------------------------------------------------------------- the store lock

def test_the_store_lock_is_a_private_file_the_caller_holds_open(tmp_path):
    # Wrong shortcut: a lock file opened with the default mode (0o666 under umask 0), or one the function
    # closes before returning (which drops the flock the instant it is taken).
    with open_umask():
        held = ls().acquire_store_lock(tmp_path)
    try:
        assert not held.closed
        assert mode_of(tmp_path / LOCK_FILE) == OWNER_ONLY
    finally:
        held.close()


def test_a_held_store_lock_refuses_a_second_taker_naming_the_folder(tmp_path):
    # Wrong shortcut: no lock at all, or a lock that only checks the file exists.
    mod = ls()
    held = mod.acquire_store_lock(tmp_path)
    try:
        with pytest.raises(mod.LedgerStartupError) as caught:
            mod.acquire_store_lock(tmp_path)
        assert "%s %s" % (LOCK_MESSAGE, tmp_path) in str(caught.value)
    finally:
        held.close()


def test_a_released_store_lock_can_be_taken_again_and_its_file_stays(tmp_path):
    # Wrong shortcuts: an exclusive-create lock file (never reusable) or deleting the file on release.
    mod = ls()
    mod.acquire_store_lock(tmp_path).close()
    assert (tmp_path / LOCK_FILE).exists(), "the lock file was deleted on release"
    again = mod.acquire_store_lock(tmp_path)
    again.close()
    assert (tmp_path / LOCK_FILE).exists()


def test_a_lock_file_that_cannot_be_opened_aborts_naming_the_errno(tmp_path):
    # Wrong shortcut: letting the raw OSError escape, or reading it as "lock held".
    mod = ls()
    (tmp_path / LOCK_FILE).mkdir()
    with pytest.raises(mod.LedgerStartupError) as caught:
        mod.acquire_store_lock(tmp_path)
    assert errno.errorcode[errno.EISDIR] in str(caught.value)
    assert LOCK_MESSAGE not in str(caught.value)


@NOT_ROOT
def test_a_read_only_store_folder_aborts_naming_the_errno(tmp_path, chmod_guard):
    mod = ls()
    chmod_guard(tmp_path, 0o500)
    with pytest.raises(mod.LedgerStartupError) as caught:
        mod.acquire_store_lock(tmp_path)
    assert errno.errorcode[errno.EACCES] in str(caught.value)
    assert LOCK_MESSAGE not in str(caught.value)


# --------------------------------------------------------------------- Ledger with a store folder

def add_hidden(state):
    state["hidden"].append("r1111111111111111")
    return state


def fail_midway(state):
    state["hidden"].append("r2222222222222222")
    raise RuntimeError("the change failed")


def test_update_persists_the_whole_new_state(tmp_path):
    # Wrong shortcut: writing only the changed part, or only on shutdown.
    mod = ls()
    ledger = mod.Ledger(state=populated_state(), store_dir=tmp_path)
    returned = ledger.update(add_hidden)
    assert returned["hidden"][-1] == "r1111111111111111"
    assert mod.load_ledger(tmp_path) == ledger.snapshot() == returned


def test_a_change_that_raises_leaves_memory_and_file_as_they_were(tmp_path):
    # Wrong shortcut: writing before the change finishes, or leaving the half-changed state in memory.
    mod = ls()
    old = populated_state()
    path = write_raw(tmp_path, json.dumps(old))
    before = path.read_bytes()
    ledger = mod.Ledger(state=old, store_dir=tmp_path)
    with pytest.raises(RuntimeError):
        ledger.update(fail_midway)
    assert ledger.snapshot() == old
    assert path.read_bytes() == before


def test_a_failed_write_makes_update_raise_and_changes_nothing(tmp_path, monkeypatch):
    # Wrong shortcut: replacing the in-memory state first and writing after, or swallowing the failure.
    mod = ls()
    old = populated_state()
    path = write_raw(tmp_path, json.dumps(old))
    before = path.read_bytes()
    ledger = mod.Ledger(state=old, store_dir=tmp_path)
    calls = []

    def refuse(store_dir, state):
        calls.append(copy.deepcopy(state))
        raise mod.LedgerWriteError("ENOSPC")

    monkeypatch.setattr(mod, "write_ledger", refuse)
    with pytest.raises(mod.LedgerWriteError):
        ledger.update(add_hidden)
    assert [state["hidden"][-1] for state in calls] == ["r1111111111111111"], "no write of the new state"
    assert ledger.snapshot() == old
    assert path.read_bytes() == before


def test_a_ledger_without_a_store_folder_writes_nothing(tmp_path, monkeypatch):
    # Regression guard (may already pass): the in-memory Ledger of task 9 must stay file-free.
    monkeypatch.chdir(tmp_path)
    ledger = ls().Ledger()
    assert ledger.snapshot() == EMPTY
    assert ledger.update(add_hidden)["hidden"] == ["r1111111111111111"]
    assert ledger.snapshot()["hidden"] == ["r1111111111111111"]
    assert os.listdir(str(tmp_path)) == []


# ------------------------------------------------------------------------------ server level

def store_env(store):
    return {"TREKO_STORE_DIR": str(store)}


@pytest.fixture
def store(tmp_path):
    folder = tmp_path / "ledger-store"
    folder.mkdir()
    return folder.resolve()


def assert_ledger_abort(srv, *expected):
    """The three clauses of a startup abort (non-zero exit, names the cause, serves nothing), exit exactly 2."""
    code = srv.wait_for_exit(timeout=ABORT_WAIT_SECS)
    assert code is not None, "the server did not exit:\n%s" % srv.stderr
    assert code == SERVE_FAILED_EXIT, "exit %d, wanted %d:\n%s" % (code, SERVE_FAILED_EXIT, srv.stderr)
    for text in expected:
        assert text in srv.stderr, "stderr did not name %r:\n%s" % (text, srv.stderr)
    assert harness.refuses_connection(srv.port), "the aborted server served anyway"


SERVER_BAD_FILES = {
    "corrupt": "{not json",
    "wrong-version": json.dumps(dict(EMPTY, version=2)),
    "rule-broken": json.dumps(dict(EMPTY, queue="not a list")),
}


@pytest.mark.parametrize("text", list(SERVER_BAD_FILES.values()), ids=list(SERVER_BAD_FILES))
def test_a_bad_ledger_file_aborts_startup_naming_it(launcher, store, text):
    # Wrong shortcut: the server never reads the file, or starts empty and un-hides every deleted run.
    path = write_raw(store, text)
    srv = launcher(overrides=store_env(store), wait=False)
    assert_ledger_abort(srv, str(path))


@NOT_ROOT
def test_an_unreadable_ledger_file_aborts_startup_naming_it_and_the_errno(launcher, store, chmod_guard):
    path = write_raw(store, json.dumps(EMPTY))
    chmod_guard(path, 0)
    srv = launcher(overrides=store_env(store), wait=False)
    assert_ledger_abort(srv, str(path), errno.errorcode[errno.EACCES])


def test_a_second_server_on_another_port_aborts_naming_the_lock_and_the_first_keeps_serving(launcher, store, tmp_path):
    # Wrong shortcut: no lock, so both servers start the same waiting item at launch.
    first = launcher(overrides=store_env(store))
    token = first.token
    second = launcher(overrides=store_env(store), wait=False, stderr_path=tmp_path / "second-stderr.log")
    assert second.port != first.port
    assert_ledger_abort(second, "%s %s" % (LOCK_MESSAGE, store))
    still = first.get("/")
    assert still.status == 200
    assert token in still.body.decode(), "the survivor rotated its token"


def test_a_started_server_holds_a_private_lock_file_in_its_store_folder(launcher, store):
    # Wrong shortcut: no lock file, or one made with the umask's default mode.
    launcher(overrides=store_env(store))
    lock = store / LOCK_FILE
    assert lock.exists(), "no %s in the store folder" % LOCK_FILE
    assert mode_of(lock) == OWNER_ONLY


def test_a_busy_port_still_gets_todays_message_not_the_lock_message(launcher, store, tmp_path):
    # The lock is taken only after the bind, so the busy-port wording is unchanged. Regression guard (may
    # already pass): it fails if the lock is moved ahead of the bind.
    first = launcher(overrides=store_env(store))
    second = launcher(port=first.port, overrides=store_env(store), wait=False,
                      stderr_path=tmp_path / "second-stderr.log")
    code = second.wait_for_exit(timeout=ABORT_WAIT_SECS)
    assert code is not None and code != 0
    assert "port %d is already in use" % first.port in second.stderr
    assert "Not probing for a free port" in second.stderr
    assert LOCK_MESSAGE not in second.stderr


def test_an_absent_ledger_file_starts_normally(launcher, store):
    # Regression guard (may already pass): absent means an empty ledger, not an abort.
    srv = launcher(overrides=store_env(store))
    assert srv.get("/").status == 200
    assert srv.proc.poll() is None
