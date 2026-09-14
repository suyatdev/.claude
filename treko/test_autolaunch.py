"""Tests for auto-launch — acceptance criteria 6, 7, 8, 9, 15 and 16.

`docs/features/treko-rename.md` §Acceptance criteria and §"Auto-launch must start the
server the way the docs tell a human to" are authoritative.

**How "did a browser open?" is proven.** `BROWSER` is honoured by the stdlib
`webbrowser` module, so every launch here points it at a recorder script and asserts on
what that script was handed. That is real behaviour, not a mock: the server calls
`webbrowser.open()` and the recorder is what the module actually execs.

**Two criteria cannot be red on their own, and are asserted as conjunctions.** Criterion
7 ("the analyzer does *not* run") and criterion 16's process-tree half are both trivially
true today, because auto-launch does not exist and therefore nothing runs and nothing
reparents. A test that passes for the absence of the feature is not a test of the
feature. Each is therefore paired with the half that *is* absent — the browser opening —
so the assertion can only pass once auto-launch exists and behaves.

**Wording the spec left open is pinned here.** The spec requires the busy-port message to
state whether a Treko page answered the probe, and the no-repo message to name that
reason, without fixing the words. The regexes below are that contract; the implementation
conforms to them rather than the reverse.

**A note recorded during task 1:** criterion 7 says the store's `generated_at` must be
unchanged. The store's real key is `generatedAt` (`store.py`, `new_store`). The tests use
the real key. A guessed field name fails closed, and a check that fails closed is
indistinguishable from a check that was switched off.

**What the red run of task 1 did and did not establish.** Every test here except the
skill-command one failed at the same upstream hurdle — `server.py` has no `--open`, so the
process dies in argparse before reaching any behaviour under test. That proves the feature
is absent; it does **not** yet prove each test can fail for its *own* reason. Eight tests
agreeing can be one cause repeated. Task 8 is where that gets settled: as `--open` lands,
each of these must be observed failing individually before it is made to pass, or it is a
test whose specific claim was never exercised.
"""

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import server  # noqa: E402  (path shim above must run first)
import server_harness as harness  # noqa: E402
import store  # noqa: E402


EXIT_ABORT = 2
LAUNCH_TIMEOUT_SECS = 30

# Recorded per invocation so a test can prove a browser was opened, and with what.
FAKE_BROWSER = '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_BROWSER_LOG"], "a") as fh:
    fh.write(json.dumps(sys.argv[1:]) + "\\n")
    fh.flush()
'''

# The wording contract for the two abort messages the spec describes but does not fix.
NO_REPO_RE = re.compile(r"not (a|inside a) git repository", re.I)
PROBE_RE = re.compile(r"probe.*(answered|did not answer)|" r"(answered|did not answer).*probe", re.I)


# ----------------------------------------------------------------- fixtures


@pytest.fixture
def browser_log(tmp_path):
    """A recorder on `BROWSER`, plus the path its invocations land in."""
    script = tmp_path / "fake-browser"
    script.write_text(FAKE_BROWSER)
    script.chmod(0o755)
    log = tmp_path / "browser-opens.jsonl"
    return _BrowserRecorder(script, log)


class _BrowserRecorder:
    def __init__(self, script, log):
        self.script = script
        self.log = log

    @property
    def opens(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines() if line.strip()]

    def env(self):
        return {"BROWSER": str(self.script), "FAKE_BROWSER_LOG": str(self.log)}


@pytest.fixture
def git_repo(tmp_path):
    """A real repository with one feature card, so the analyzer has something to find."""
    root = tmp_path / "worktree-under-test"
    (root / "docs" / "features").mkdir(parents=True)
    (root / "docs" / "features" / "sample.md").write_text(
        "---\nphase: planning\nmodel_tier: low\nbranch: none\n---\n\n"
        "# Sample\n\n## Tasks\n\n- [ ] 1. Something.\n"
    )
    for args in (["init", "-q"], ["add", "-A"],
                 ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "seed"]):
        subprocess.run(["git", *args], cwd=str(root), check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    nested = root / "docs" / "features"
    return _Repo(root, nested)


class _Repo:
    def __init__(self, root, nested):
        self.root = root
        self.nested = nested  # a subdirectory, so repo resolution is actually exercised


# ----------------------------------------------------------------- launching


def launch(tmp_path, browser, *, cwd, surface=harness.FAKE_SURFACE, port=None,
           overrides=None, open_browser=True):
    """Start `server.py` WITHOUT `--repo`, which is what auto-launch has to resolve.

    Returns the Popen and the path its stderr was captured to. Nothing here waits for the
    server to serve: half these cases are aborts, and `await_ready` would turn an expected
    exit into a 20s timeout with a worse message.
    """
    tree = harness.build_tree(tmp_path)
    cmux_bin = harness.install_fake_cmux(tmp_path)
    cmux_log = tmp_path / "cmux-calls.jsonl"
    port = port if port is not None else harness.free_port()

    env = harness.server_env(tmp_path, tree, cmux_bin, cmux_log, surface=surface,
                             overrides=overrides)
    env["TREKO_PORT"] = str(port)
    env.update(browser.env())

    argv = [sys.executable, str(tree / "server.py")]
    if open_browser:
        argv.append("--open")

    stderr_path = tmp_path / "server-stderr.log"
    handle = open(stderr_path, "ab", buffering=0)
    try:
        proc = subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=handle,
                                env=env, cwd=str(cwd))
    finally:
        handle.close()
    return _Launch(proc, port, tree, stderr_path)


class _Launch:
    def __init__(self, proc, port, tree, stderr_path):
        self.proc = proc
        self.port = port
        self.tree = tree
        self.stderr_path = stderr_path

    @property
    def stderr(self):
        return self.stderr_path.read_text(errors="replace")

    @property
    def store_path(self):
        return self.tree / "tracker-data.js"

    def read_store(self):
        return store.read_store(self.store_path)

    def wait(self, timeout=LAUNCH_TIMEOUT_SECS):
        try:
            return self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            return None

    def await_serving(self, timeout=LAUNCH_TIMEOUT_SECS):
        deadline = time.monotonic() + timeout
        probe = harness.Server(self.proc, self.port, self.tree, self.stderr_path, None, None)
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise AssertionError("server exited %d before serving:\n%s"
                                     % (self.proc.returncode, self.stderr))
            try:
                probe.get("/", timeout=2)
                return probe
            except OSError:
                time.sleep(0.05)
        raise AssertionError("server did not serve within %ds:\n%s" % (timeout, self.stderr))

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=10)


def seed_store(tmp_path, runs=()):
    """Write the store BEFORE the server starts.

    Seeding after launch would race the startup read this feature is entirely about, and a
    race that usually loses looks exactly like a feature that works.
    """
    tree = harness.build_tree(tmp_path)
    path = tree / "tracker-data.js"
    store.write_store(path, store.new_store())
    for run in runs:
        store.emit_run(path, run)
    return path


# --------------------------------------------------------------------------
# criterion 8 — outside a repository, auto-launch aborts and opens nothing
# --------------------------------------------------------------------------


def test_outside_a_git_repository_the_server_aborts(tmp_path, browser_log):
    outside = tmp_path / "not-a-repo"
    outside.mkdir()
    run = launch(tmp_path, browser_log, cwd=outside)
    try:
        assert run.wait() == EXIT_ABORT
        assert NO_REPO_RE.search(run.stderr), run.stderr
    finally:
        run.stop()


def test_outside_a_git_repository_no_browser_opens(tmp_path, browser_log):
    """The reason is re-asserted here on purpose.

    Without it this passes vacuously: any abort at all — an argparse usage error, say —
    also opens no browser, so the test would go green while proving nothing.
    """
    outside = tmp_path / "not-a-repo"
    outside.mkdir()
    run = launch(tmp_path, browser_log, cwd=outside)
    try:
        run.wait()
        assert NO_REPO_RE.search(run.stderr), run.stderr
        assert browser_log.opens == []
    finally:
        run.stop()


# --------------------------------------------------------------------------
# criterion 6 — a repo with no run is analyzed once, then shown
# --------------------------------------------------------------------------


def test_no_path_launch_analyzes_the_repo_root_once(tmp_path, browser_log, git_repo):
    """Launched from a subdirectory: the survey is of the repo, not of the subdirectory."""
    seed_store(tmp_path)
    run = launch(tmp_path, browser_log, cwd=git_repo.nested)
    try:
        run.await_serving()
        runs = run.read_store()["runs"]
        assert len(runs) == 1
    finally:
        run.stop()


def test_no_path_launch_opens_the_browser_at_the_bound_url(tmp_path, browser_log, git_repo):
    run = launch(tmp_path, browser_log, cwd=git_repo.nested)
    try:
        run.await_serving()
        opens = browser_log.opens
        assert len(opens) == 1, opens
        assert "127.0.0.1:%d" % run.port in opens[0][0]
    finally:
        run.stop()


# --------------------------------------------------------------------------
# criterion 7 — a repo that already has a run is NOT re-analyzed
# --------------------------------------------------------------------------


def test_existing_run_is_not_reanalyzed_on_launch(tmp_path, browser_log, git_repo):
    """Conjoined deliberately: "did not re-analyze" is vacuously true without the feature.

    The browser half is what makes this red before auto-launch exists, so a pass can only
    mean the server launched, showed the survey, and left the store alone — never that
    nothing happened at all.
    """
    path = seed_store(tmp_path, [{"id": "seeded", "name": "seeded"}])
    before = store.read_store(path)["generatedAt"]

    run = launch(tmp_path, browser_log, cwd=git_repo.nested)
    try:
        run.await_serving()

        after = run.read_store()
        assert browser_log.opens, "no browser opened, so this proves nothing about the store"
        assert after["generatedAt"] == before
        assert [r["id"] for r in after["runs"]] == ["seeded"]
    finally:
        run.stop()


# --------------------------------------------------------------------------
# criterion 9 — a held port aborts, says what it found, and opens nothing
# --------------------------------------------------------------------------


def test_busy_port_aborts_and_reports_the_probe(tmp_path, browser_log, git_repo):
    import socket

    holder = socket.socket()
    holder.bind(("127.0.0.1", 0))
    holder.listen(1)
    held = holder.getsockname()[1]
    try:
        run = launch(tmp_path, browser_log, cwd=git_repo.nested, port=held)
        try:
            assert run.wait() == EXIT_ABORT
            assert PROBE_RE.search(run.stderr), run.stderr
        finally:
            run.stop()
    finally:
        holder.close()


def test_busy_port_opens_no_browser(tmp_path, browser_log, git_repo):
    """Never route a user to a server another session owns — its buttons type into that
    session, not this one."""
    import socket

    holder = socket.socket()
    holder.bind(("127.0.0.1", 0))
    holder.listen(1)
    held = holder.getsockname()[1]
    try:
        run = launch(tmp_path, browser_log, cwd=git_repo.nested, port=held)
        try:
            run.wait()
            assert PROBE_RE.search(run.stderr), run.stderr
            assert browser_log.opens == []
        finally:
            run.stop()
    finally:
        holder.close()


# --------------------------------------------------------------------------
# criterion 15 — no cmux surface is still a refusal. GREEN today, pinned.
# --------------------------------------------------------------------------


def test_without_a_cmux_surface_the_server_still_refuses(tmp_path, browser_log, git_repo):
    """Pre-existing behaviour, asserted rather than assumed.

    §Deferred proposes changing this to a degraded no-control-channel page. Pinning it now
    means that change flips a test rather than filling a gap.
    """
    run = launch(tmp_path, browser_log, cwd=git_repo.nested, surface="",
                 open_browser=False)
    try:
        assert run.wait() == EXIT_ABORT
        assert "CMUX_SURFACE_ID" in run.stderr
        assert browser_log.opens == []
    finally:
        run.stop()


# --------------------------------------------------------------------------
# criterion 16 — auto-launch obeys the contract the docs impose on a human
# --------------------------------------------------------------------------


def test_opening_the_browser_does_not_reparent_the_server(tmp_path, browser_log, git_repo):
    """Conjoined: without auto-launch nothing reparents anything, so the ppid half alone
    would pass on an empty feature.

    `webbrowser.open()` must be called from inside the already-running server process. A
    fork that becomes the server's new parent silently disables the parent-pid watchdog —
    `os.getppid()` never changes again, so the check never fires and the control channel
    outlives the session that owned it.
    """
    run = launch(tmp_path, browser_log, cwd=git_repo.nested)
    try:
        run.await_serving()
        assert browser_log.opens, "no browser opened, so the reparent claim is untested"
        assert _parent_pid(run.proc.pid) == os.getpid()
    finally:
        run.stop()


def _parent_pid(pid):
    out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                         capture_output=True, text=True, check=True)
    return int(out.stdout.strip())


def test_the_skill_documents_a_launch_command_that_does_not_detach():
    """The two warnings in the skill are load-bearing and both fail silently.

    A detached server is reparented immediately, so the watchdog never fires. A redirected
    stderr discards the only record of where keystrokes went. Auto-launch makes this a
    command the code issues rather than one a human types, so the documented form is
    asserted here rather than left to a reader.
    """
    skill = harness.REPO_ROOT / "skills" / "treko" / "SKILL.md"
    assert skill.is_file(), "skills/treko/SKILL.md does not exist"
    text = skill.read_text()
    launch_lines = [ln for ln in text.splitlines() if "server.py" in ln]
    assert launch_lines, "the skill documents no launch command"
    for line in launch_lines:
        assert "nohup" not in line, line
        assert "setsid" not in line, line
        assert not re.search(r"2\s*>", line), line
        assert not re.search(r"&\s*$", line), line
