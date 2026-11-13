"""Start every scan and analyzer one safe way (docs/features/treko-ledger.spec.md sections 2 default 3, 4, 5.4).

Five parts, all in the standard library:
  * `build_child_env(base)`: the environment every child gets. It reads only the base it is given, never the
    process environment, so the one place that reads the real environment is the server's `main()`.
  * `ChildRegistry`: the set of running children, under its own lock (never the ledger lock). Its one `launch`
    checks `closed`, starts the child in a process group of its own with `env=` the builder's output, and
    registers it, all before the lock is released. Once closed, a launch starts nothing.
  * `kill_process_group` and the bounded reap (`REAP_WAIT_SECS`): a reap that expires writes the reap-timeout
    line and leaves the process registered, so shutdown's sweep kills its group again.
  * `run_scan`: the scan launcher. The request goes in as JSON on stdin, the bound is passed in, and at the
    bound the whole process group is killed.
  * `JobRunner`: one job at a time, section 5.4 steps 1 to 6, on a thread of its own, and the in-memory stage
    record the status route reads (section 6.2).

The builder is the only protection a child gets, so every process this package starts goes through `launch`.
"""

import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from collections import namedtuple
from pathlib import Path

import ledger_state
import store

REAP_WAIT_SECS = 5  # section 5.4: the longest any one reap waits after a group kill
SCAN_OK = "ok"
SCAN_TIMEOUT = "scan_timeout"
SCAN_PROGRAM = Path(__file__).resolve().with_name("ledger_scan.py")
ANALYZE_PROGRAM = Path(__file__).resolve().with_name("analyze.py")
SHUTDOWN_LABEL = "shutdown"  # names the sweep's reap-timeout lines: `server: shutdown reap timeout <pid>`

# Sections 5.4 and 6.2: a job over N families has 4N + 3 stages (the scan, 4 per family, the merge, the write).
RUN_KEYS = frozenset({"id", "name", "dir", "analyzedAt", "features", "waves", "constraints", "branches", "graph",
                      "kanban", "questions"})  # ADR 0023's schema; test_analyze.py pins the same set
STAGE_LABELS = ("reading worktrees", "reading branches", "reading cards", "deriving merge order")  # section 6.1
MERGE_LABEL, WRITE_LABEL = "merging the runs", "writing the store"
PROGRESS_PREFIX = "treko-progress "
ANALYSIS_FAILED = "analysis_failed"
SCAN_FAILED = "scan_failed"

# Section 2 default 3's table. The variables of the git config family the builder owns end to end: the base's
# own values for any of these are dropped, whatever the number in KEY_<n> / VALUE_<n>.
_CONFIG_FAMILY = re.compile(r"^GIT_CONFIG_(COUNT|PARAMETERS|KEY_\d+|VALUE_\d+)$")
_PROTECTIVE_CONFIG = (("core.fsmonitor", "false"), ("core.hooksPath", "/dev/null"), ("log.showSignature", "false"))
_PROTECTIVE_VARIABLES = {"GIT_OPTIONAL_LOCKS": "0", "GIT_NO_LAZY_FETCH": "1"}

ScanResult = namedtuple("ScanResult", "code stdout stderr returncode")


class RegistryClosed(Exception):
    """The registry is closed (the server is stopping): the launch started nothing."""


def build_child_env(base):
    """A new environment: `base` without its git config family, plus exactly the table's rows. `base` is not
    changed. GIT_CONFIG_GLOBAL and every other variable pass through."""
    env = {name: value for name, value in base.items() if not _CONFIG_FAMILY.match(name)}
    env["GIT_CONFIG_COUNT"] = str(len(_PROTECTIVE_CONFIG))
    for number, (key, value) in enumerate(_PROTECTIVE_CONFIG):
        env["GIT_CONFIG_KEY_%d" % number] = key
        env["GIT_CONFIG_VALUE_%d" % number] = value
    env.update(_PROTECTIVE_VARIABLES)
    return env


def kill_process_group(proc):
    """SIGKILL the process group `proc` leads, without waiting. Only a group this module started (so `proc.pid`
    is its id), and only while `proc` has not been reaped, since a reaped pid may belong to someone else now."""
    if proc.returncode is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        return  # already gone: the goal
    except PermissionError:
        return  # macOS answers EPERM for a group that holds only a zombie: also already dead


def _wait(proc, timeout):
    return proc.wait(timeout=timeout)


def _stderr_line(line):
    sys.stderr.write(line + "\n")
    sys.stderr.flush()


class ChildRegistry:
    """The running children. `base_env` is the environment the builder starts from (read by the caller, passed in);
    `build_env` is the builder, a parameter so a test can run without the protection; `reap_wait(proc, timeout)`
    raises subprocess.TimeoutExpired when `proc` is not reaped in time; `log(line)` takes one diagnostic line."""

    def __init__(self, base_env, build_env=build_child_env, reap_wait=None, log=None):
        self._base_env = base_env
        self._build_env = build_env
        self._reap_wait = reap_wait if reap_wait is not None else _wait
        self._log = log if log is not None else _stderr_line
        self._children = set()
        self.lock = threading.Lock()
        self.closed = False

    def launch(self, argv, **popen_kwargs):
        """Start `argv` in a session of its own with the builder's environment and register it, under the lock.
        Raises RegistryClosed, having started nothing, once the registry is closed. An OSError from the start
        propagates and registers nothing."""
        with self.lock:
            if self.closed:
                raise RegistryClosed("the child registry is closed")
            proc = subprocess.Popen(argv, start_new_session=True, env=self._build_env(self._base_env),
                                    **popen_kwargs)
            self._children.add(proc)
            return proc

    def children(self):
        with self.lock:
            return frozenset(self._children)

    def close(self):
        """No launch succeeds after this. Shutdown calls it first, then `kill_all`."""
        with self.lock:
            self.closed = True

    def release(self, proc):
        """Forget a process that has been reaped."""
        with self.lock:
            self._children.discard(proc)

    def kill_and_reap(self, proc, label):
        """Kill `proc`'s group, then wait at most REAP_WAIT_SECS for `proc`. True: reaped and unregistered. False:
        the wait expired, `server: <label> reap timeout <pid>` was logged, and `proc` stays registered."""
        kill_process_group(proc)
        try:
            self._reap_wait(proc, REAP_WAIT_SECS)
        except subprocess.TimeoutExpired:
            self._log("server: %s reap timeout %d" % (label, proc.pid))
            return False
        self.release(proc)
        return True

    def kill_all(self):
        """Kill every registered group, then reap each. The groups are signalled first so no reap delays a kill."""
        procs = self.children()
        for proc in procs:
            kill_process_group(proc)
        for proc in procs:
            self.kill_and_reap(proc, SHUTDOWN_LABEL)


def _close_streams(proc):
    for stream in (proc.stdin, proc.stdout, proc.stderr):
        if stream is None:
            continue
        try:
            stream.close()
        except OSError:
            pass  # closing flushes: a broken pipe to a child we just killed is the expected state, not a fault


def run_scan(registry, request, scan_secs, *, label="scan", program=None):
    """Run the scan program on `request` (JSON on stdin) for at most `scan_secs` seconds. Returns a ScanResult:
    code SCAN_OK with the program's stdout, stderr and exit status when it finished in time, or SCAN_TIMEOUT
    when the bound passed and the whole group was killed. The timeout answer holds even when the reap after the
    kill expires (the process then stays registered). Raises RegistryClosed when the registry refuses the launch,
    and OSError when the program cannot be started."""
    script = SCAN_PROGRAM if program is None else Path(program)
    proc = registry.launch([sys.executable, str(script)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
    try:
        try:
            stdout, stderr = proc.communicate(json.dumps(request), timeout=scan_secs)
        except subprocess.TimeoutExpired:
            registry.kill_and_reap(proc, label)
            return ScanResult(SCAN_TIMEOUT, "", "", None)
        registry.release(proc)
        return ScanResult(SCAN_OK, stdout, stderr, proc.returncode)
    except BaseException:
        registry.kill_and_reap(proc, label)  # an interrupt must not leave the scan running
        raise
    finally:
        _close_streams(proc)


# ------------------------------------------------------------------------------------------ the job runner

def _scan_error(result):
    """(error code or None, the scan's object or None) for a finished scan process."""
    if result.code != SCAN_OK:
        return result.code, None
    try:
        scan = json.loads(result.stdout)
        outcome = scan["outcome"]
        scan["families"], scan["questions"]
    except (ValueError, KeyError, TypeError):
        return SCAN_FAILED, None
    if result.returncode != 0:
        return SCAN_FAILED, None
    return (None if outcome == SCAN_OK else outcome), scan


def _read_run(stdout):
    """The analyzer's run, or None when stdout is not a JSON object holding every run key."""
    try:
        run = json.loads(stdout)
    except ValueError:
        return None
    return run if isinstance(run, dict) and RUN_KEYS <= set(run) else None


class JobRunner:
    """Runs the oldest waiting item, one at a time (section 5.4). `report(stage)` receives each analyzer
    `treko-progress <stage>` line; the default moves the stage record on. `progress()` is that record: None when
    nothing runs, else {"done", "total" (None until the scan ends), "label"}. `last_job_end` is `time.monotonic()`
    at the last job end, the clock the idle watchdog uses. `scan_program` and `analyze_program` swap the scripts."""

    def __init__(self, ledger, registry, store_path, analyze_secs, scan_secs, report=None, scan_program=None,
                 analyze_program=None):
        self._ledger, self._registry, self._store_path = ledger, registry, store_path
        self._analyze_secs, self._scan_secs = analyze_secs, scan_secs
        self._scan_program = scan_program
        self._analyze_program = str(ANALYZE_PROGRAM if analyze_program is None else analyze_program)
        self.report = report if report is not None else self._record
        self.last_job_end = None
        self._lock = threading.Lock()  # guards the stage record and last_job_end; never held across a call out
        self._stage = None
        self._labels = []  # the families' labels, known once the scan has ended
        self._wake = threading.Event()

    # ------------------------------------------------------------------------------ stage record (section 6.2)

    def progress(self):
        with self._lock:
            return None if self._stage is None else dict(self._stage)

    def _label_for(self, done):
        """The stage now running: the one after `done - 1` finished ones, which the fixed order names."""
        finished, count = done - 1, len(self._labels)
        if finished >= 4 * count:
            return MERGE_LABEL if finished == 4 * count else WRITE_LABEL
        index, stage = divmod(finished, len(STAGE_LABELS))
        who = self._labels[index] if count == 1 else "%s (%d of %d)" % (self._labels[index], index + 1, count)
        return "%s: %s" % (who, STAGE_LABELS[stage])

    def _set_done(self, done):
        with self._lock:
            self._stage = {"done": done, "total": 4 * len(self._labels) + 3, "label": self._label_for(done)}

    def _record(self, stage):
        """The default report handler: one more stage is done, whatever its name."""
        with self._lock:
            if self._stage is None:
                return
            done = min(self._stage["done"] + 1, 4 * len(self._labels) + 1)  # a stray line cannot pass the families
            self._stage = {"done": done, "total": self._stage["total"], "label": self._label_for(done)}

    # ------------------------------------------------------------------------------------------- the thread

    def start(self):
        threading.Thread(target=self._loop, name="treko-job-runner", daemon=True).start()

    def wake(self):
        self._wake.set()

    def _loop(self):
        while self._wake.wait():
            self._wake.clear()  # before the work, so a wake that arrives during a job is not lost
            if self._registry.closed:
                return
            try:
                while self.run_next() is not None:
                    pass
            except Exception as error:  # noqa: BLE001 - one bad job must not end the thread
                _stderr_line("server: runner error %s" % type(error).__name__)

    # ----------------------------------------------------------------------------------------------- one job

    def run_next(self):
        """Section 5.4, steps 1 to 6, for the oldest waiting item; its id, or None when none ran."""
        if self._registry.closed:
            return None
        item = self._claim()
        if item is None:
            return None
        item_id, request = item["item"], item["request"]
        with self._lock:
            self._labels = []
            self._stage = {"done": 0, "total": None, "label": "scanning " + ledger_state.run_dir(request["directory"])}
        result = run_scan(self._registry, request, self._scan_secs, label="job " + item_id,
                          program=self._scan_program)
        error, scan = _scan_error(result)
        if error is not None:
            self._settle(item_id, error)
            return item_id
        families = scan["families"]
        self._labels = [family["label"] for family in families]
        self._set_done(1)
        parts = [self._analyze(number, family) for number, family in enumerate(families)]
        if all("run" not in part for part in parts):
            self._settle(item_id, ANALYSIS_FAILED)
            return item_id
        import ledger_merge  # late: it imports analyze, and the server must start without importing the analyzer
        run = ledger_merge.merge(request, parts, scan["questions"])
        self._set_done(4 * len(parts) + 2)
        store.emit_run(self._store_path, run)
        self._settle(item_id, None)
        return item_id

    def _claim(self):
        """Mark the oldest waiting item `running` (saved to ledger.json before this returns); a copy, or None."""
        claimed = []

        def change(state):
            waiting = [item for item in state["queue"] if item["state"] == "waiting"]
            if waiting:
                oldest = min(waiting, key=lambda item: item["queuedAt"])
                oldest["state"] = "running"
                claimed.append(dict(oldest))
            return state

        if any(item["state"] == "waiting" for item in self._ledger.snapshot()["queue"]):
            self._ledger.update(change)  # the choice is made inside the change, so it cannot go stale
        return claimed[0] if claimed else None

    def _settle(self, item_id, error):
        """The job's last ledger write: the item leaves the queue (`error` None) or fails with `error`."""
        def change(state):
            if error is None:
                state["queue"] = [item for item in state["queue"] if item["item"] != item_id]
            for item in state["queue"]:
                if item["item"] == item_id:
                    item.update(state="failed", error=error, detail=None)
            return state

        self._ledger.update(change)
        with self._lock:
            self.last_job_end = time.monotonic()
            self._stage = None

    def _analyze(self, number, family):
        """One family's part for `ledger_merge.merge`: its run, or the failure the run gets a question for."""
        argv = [sys.executable, self._analyze_program, family["root"], "--progress"]
        for card in family["cards"]:
            argv += ["--card", card]
        proc = self._registry.launch(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
        out, last, expired = [], "", threading.Event()  # `last`: the final stderr line that is not progress

        def expire():
            expired.set()
            kill_process_group(proc)

        drain = threading.Thread(target=lambda: out.append(proc.stdout.read()), daemon=True)
        timer = threading.Timer(self._analyze_secs, expire)
        timer.daemon = True
        try:
            drain.start()
            timer.start()
            for line in proc.stderr:
                line = line.rstrip("\n")
                if line.startswith(PROGRESS_PREFIX):
                    self.report(line[len(PROGRESS_PREFIX):].strip())
                elif line.strip():
                    last = line
            timer.cancel()
            drain.join()
            try:
                proc.wait(timeout=REAP_WAIT_SECS)
                self._registry.release(proc)
            except subprocess.TimeoutExpired:
                expired.set()  # it closed its output but did not exit: the same as running past the bound
                self._registry.kill_and_reap(proc, "job analyzer")
        except BaseException:
            timer.cancel()
            self._registry.kill_and_reap(proc, "job analyzer")  # an interrupt must not leave it running
            raise
        finally:
            _close_streams(proc)
        self._set_done(1 + 4 * (number + 1))  # the stages a failed family never reported count as done
        part = {"root": family["root"], "label": family["label"], "questions": family["questions"]}
        run = None if expired.is_set() or proc.returncode != 0 else _read_run(out[0] if out else "")
        if run is not None:
            return dict(part, run=run)
        return dict(part, failure={"exit": proc.returncode, "timedOut": expired.is_set(), "stderr": last})
