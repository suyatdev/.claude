"""Launch-shape tests for server.py — how it starts, refuses to start, and stops.

Split from `test_server.py`, which covers the wire contract, for two reasons. The first
is size: one file carrying both was past this repo's 800-line ceiling. The second is
that the seam is the spec's own — §Tasks 9 calls bind failure "a launch property rather
than a wire property", and every test here is that kind: nothing below asserts a status
code for a well-formed request.

**Criterion 14 lives here, not in `test_server.py`** — noted because §Tasks 9 names that
file for it, and a reader following the spec should not conclude the clause went
unwritten. What is here:

* criterion 14, all three clauses — parent death, idle shutdown, audit-to-parent stderr;
* the three surface-binding startup aborts (§Tasks 9's "seven of them");
* the unmapped-extension abort, which keeps the manifest and the type map in lockstep;
* the `<head>` abort, without which the page silently loads unauthenticated;
* bind failure, which §Tasks 9 pins here because no criterion owns it.

Every abort is asserted the same three ways: exit non-zero, name its cause, and serve
**nothing** — the last proven by a connection the port refuses. A control that aborts
but serves anyway, or serves nothing but exits 0, is the failure shape these exist for.

Runtime is dominated by the idle clause: §Security floors `TREKO_IDLE_SECS` at 60s
and forbids disabling it, so this file costs at least a minute. Lowering the floor to
make it quick deletes the control the test exists to prove.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import server  # noqa: E402  (path shim above must run first)
import server_harness as harness  # noqa: E402


SHUTDOWN_SLACK_SECS = 2  # scheduler jitter on top of the spec's poll+1 bound


def assert_aborted(srv, *, expect):
    """The three clauses every startup abort must satisfy, asserted together."""
    code = srv.wait_for_exit(timeout=harness.STARTUP_TIMEOUT_SECS)
    assert code is not None, "server did not exit"
    assert code != 0, "a misconfiguration exited 0"
    assert expect in srv.stderr, "stderr did not name the cause:\n%s" % srv.stderr
    assert harness.refuses_connection(srv.port), "aborted server served anyway"


# --------------------------------------------------------------------------
# the three surface-binding aborts
# --------------------------------------------------------------------------


def test_an_unset_surface_id_aborts_before_serving(launcher):
    """The UUID is inherited, never deduced: a send with no target defaults to whatever
    surface it inherits, which is how task 1's spike reached a different live session."""
    srv = launcher(surface="", wait=False)
    assert_aborted(srv, expect="CMUX_SURFACE_ID is unset or empty")


def test_a_failing_read_screen_probe_aborts_before_serving(launcher):
    srv = launcher(overrides={"FAKE_READ_SCREEN": "fail"}, wait=False)
    assert_aborted(srv, expect="read-screen")


def test_a_hanging_read_screen_probe_aborts_before_serving(launcher):
    """An unbounded probe is a server that neither starts nor reports why."""
    srv = launcher(overrides={"FAKE_READ_SCREEN": "hang"}, wait=False)
    assert_aborted(srv, expect="exceeded 5s probing the surface")


# --------------------------------------------------------------------------
# the two configuration aborts
# --------------------------------------------------------------------------


def test_a_manifest_row_with_an_unmapped_extension_aborts_before_serving(launcher, tree):
    """The control that keeps the manifest and the type map in lockstep. Unasserted, the
    two drift and the first symptom is a stylesheet served as the wrong type."""
    source = tree / "server.py"
    original = source.read_text()
    patched = original.replace(
        "STATIC_MANIFEST = (\n", 'STATIC_MANIFEST = (\n    "notes.txt",\n', 1)
    assert patched != original, "could not insert a manifest row"
    source.write_text(patched)
    # Present on disk, so the abort is unambiguously about the type map, not the file.
    (tree / "notes.txt").write_text("present\n")

    srv = launcher(tree=tree, wait=False)
    assert_aborted(srv, expect="extensions absent from EXTENSION_TYPES: .txt")


def test_an_index_with_no_head_aborts_before_serving(launcher, tree):
    """No <head>, no token — surfaced at startup rather than as a silently
    unauthenticated UI on the user's first load."""
    index = tree / server.INDEX_FILE
    index.write_text(index.read_text().replace("<head>", "<nohead>", 1))
    srv = launcher(tree=tree, wait=False)
    assert_aborted(srv, expect="no <head>")


def test_a_disabled_timeout_is_refused_at_startup(launcher):
    """§Security forbids a value meaning "never"; an unspecified timeout is no timeout."""
    srv = launcher(overrides={"TREKO_IDLE_SECS": "0"}, wait=False)
    assert_aborted(srv, expect="may not be disabled")


# --------------------------------------------------------------------------
# bind failure — no criterion owns it, so §Tasks 9 pins it here
# --------------------------------------------------------------------------


def test_a_second_server_on_the_same_port_aborts_and_leaves_the_first_intact(launcher):
    """A second server on a *different* port would leave the browser talking to the
    first, which holds a different token — so every button returns the deliberately
    collapsed 403 and the operator reads a stale token as a broken feature."""
    first = launcher()
    token = first.token

    second = launcher(port=first.port, wait=False,
                      stderr_path=first.tree.parent / "second-stderr.log")
    code = second.wait_for_exit(timeout=harness.STARTUP_TIMEOUT_SECS)

    assert code is not None and code != 0
    assert "port %d is already in use" % first.port in second.stderr
    assert "Not probing for a free port" in second.stderr

    still_serving = first.get("/")
    assert still_serving.status == 200
    assert token in still_serving.body.decode(), "the survivor rotated its token"


# --------------------------------------------------------------------------
# criterion 14 — bounded lifetime, all three clauses
# --------------------------------------------------------------------------


ORPHAN_PARENT = """
import json, os, subprocess, sys, time
cfg = json.loads(sys.argv[1])
handle = open(cfg["stderr"], "ab", buffering=0)
proc = subprocess.Popen(cfg["argv"], stdout=subprocess.DEVNULL, stderr=handle,
                        env=cfg["env"], cwd=cfg["cwd"])
open(cfg["pidfile"], "w").write(str(proc.pid))
time.sleep(cfg["linger"])
os._exit(0)
"""


def test_the_server_exits_when_its_parent_does(tmp_path, tree):
    """A real parent exit, not a mocked getppid(): the mock proves the branch compiles,
    not that the server dies. prctl(PR_SET_PDEATHSIG) does not exist on macOS, the
    binding platform, so the portable check is getppid() changing on reparenting.
    """
    poll_secs = 1
    port = harness.free_port()
    stderr_path = tmp_path / "orphan-stderr.log"
    pidfile = tmp_path / "server.pid"
    cmux_bin = harness.install_fake_cmux(tmp_path)
    env = harness.server_env(tmp_path, tree, cmux_bin, tmp_path / "cmux-calls.jsonl",
                             overrides={"TREKO_PORT": str(port),
                                        "TREKO_POLL_SECS": str(poll_secs)})
    config = {
        "argv": [sys.executable, str(tree / "server.py"), "--repo", str(harness.REPO_ROOT)],
        "env": env, "cwd": str(tmp_path), "stderr": str(stderr_path),
        "pidfile": str(pidfile), "linger": 3,
    }

    started = time.monotonic()
    subprocess.run([sys.executable, "-c", ORPHAN_PARENT, json.dumps(config)],
                   check=True, timeout=30)
    parent_gone = time.monotonic()
    # The parent lingered long enough for the server to come up, so a port that is free
    # at the end cannot be explained by a server that never started.
    assert parent_gone - started >= config["linger"]
    assert stderr_path.read_text(), "server produced no stderr while its parent lived"

    assert harness.port_free(port, poll_secs + 1 + SHUTDOWN_SLACK_SECS), \
        "port still held %.1fs after the parent exited:\n%s" % (
            time.monotonic() - parent_gone, stderr_path.read_text())
    assert "parent session ended; exiting" in stderr_path.read_text()

    pid = int(pidfile.read_text())
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)


def test_an_idle_server_exits_and_its_audit_reaches_the_parents_stderr(launcher):
    """Two clauses at once, because they share a minute of wall clock.

    §Security floors the idle timeout at 60s and forbids disabling it, so "short
    overrides" buys nothing here — it is the parent-death clause above that gets fast.
    """
    floor = server.IDLE_SECS[1]
    srv = launcher(overrides={"TREKO_IDLE_SECS": "1", "TREKO_POLL_SECS": "1"})

    assert "TREKO_IDLE_SECS=1 raised to the %ds minimum" % floor in srv.stderr

    # The third clause: a line written to the audit log reaches the stderr the parent
    # captured. `await_ready` has already served one GET /, so one line must be there.
    assert srv.audit(status="200"), "no audit line reached the parent:\n%s" % srv.stderr

    code = srv.wait_for_exit(timeout=floor + 30)
    assert code is not None, "still running %ds after going idle" % (floor + 30)
    assert "idle for %ds; exiting" % floor in srv.stderr
    assert harness.refuses_connection(srv.port)
