"""Start every scan and analyzer one safe way (docs/features/treko-ledger.spec.md sections 2 default 3, 4, 5.4).

Four parts, all in the standard library:
  * `build_child_env(base)`: the environment every child gets. It reads only the base it is given, never the
    process environment, so the one place that reads the real environment is the server's `main()`.
  * `ChildRegistry`: the set of running children, under its own lock (never the ledger lock). Its one `launch`
    checks `closed`, starts the child in a process group of its own with `env=` the builder's output, and
    registers it, all before the lock is released. Once closed, a launch starts nothing.
  * `kill_process_group` and the bounded reap (`REAP_WAIT_SECS`): a reap that expires writes the reap-timeout
    line and leaves the process registered, so shutdown's sweep kills its group again.
  * `run_scan`: the scan launcher. The request goes in as JSON on stdin, the bound is passed in, and at the
    bound the whole process group is killed.

The builder is the only protection a child gets, so every process this package starts goes through `launch`.
"""

import json
import os
import re
import signal
import subprocess
import sys
import threading
from collections import namedtuple
from pathlib import Path

REAP_WAIT_SECS = 5  # section 5.4: the longest any one reap waits after a group kill
SCAN_OK = "ok"
SCAN_TIMEOUT = "scan_timeout"
SCAN_PROGRAM = Path(__file__).resolve().with_name("ledger_scan.py")
SHUTDOWN_LABEL = "shutdown"  # names the sweep's reap-timeout lines: `server: shutdown reap timeout <pid>`

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
