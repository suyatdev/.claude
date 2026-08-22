"""Fixtures and probes for test_server.py — the harness, kept out of the assertions.

Split from `test_server.py` purely for size: that file is one test file by the card's
§Tasks 9, and holding both the launch machinery and ~30 assertions put it past this
repo's 400-line target. Nothing here asserts anything; every `assert` lives next to the
criterion it serves.

Two rules govern this module:

* **The real `treko/` is never touched.** Every server runs against a per-test
  copy under `tmp_path`, laid out as `<tmp>/treko/` with `<tmp>/hooks/lib`
  alongside it, because `analyze.py` resolves that path as `__file__/../../hooks/lib`
  (`grep -n 'hooks.*lib' treko/analyze.py`). Reproducing the layout is what lets
  `reanalyze` run unmodified — a `PYTHONPATH` override would test a launch shape the
  feature does not use.
* **`cmux` is faked, and the fake records what it was handed.** A fake proves the
  server's decision and never that keystrokes arrived; §Tasks 9 says so at length. It
  records its full argv *and* its environment, because criterion 10 asks whether the
  token reaches a child process and every child here inherits the server's environment
  verbatim (`server.py` passes no `env=` to any `subprocess.run` — asserted in
  `test_server.py`, not assumed here).
"""

import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REAL_TREE = REPO_ROOT / "treko"

# The surface the fake `cmux tree` reports present. Criterion 12 asserts the ref handed to
# `send` is byte-identical to this, which is the whole identity claim a fake can carry.
FAKE_SURFACE = "11111111-2222-3333-4444-555555555555"

# `cmux tree` reports this one instead when the session is meant to have ended.
OTHER_SURFACE = "99999999-8888-7777-6666-555555555555"

# Longer than CMUX_TIMEOUT_SECS (5s, pinned in server.py) and than any analyzer override,
# so a "hang" mode is always killed by the server's own bound rather than outliving it.
HANG_SECS = 45

STARTUP_TIMEOUT_SECS = 20

# A fake `cmux`, and a hanging `analyze.py`, both driven entirely by the environment so a
# test changes behaviour without rewriting a file mid-run.
FAKE_CMUX = '''#!/usr/bin/env python3
"""Records every invocation, then behaves as FAKE_<VERB> in the environment says."""
import json, os, sys, time

verb = sys.argv[1] if len(sys.argv) > 1 else ""
log = os.environ.get("FAKE_CMUX_LOG")
if log:
    with open(log, "a") as fh:
        fh.write(json.dumps({"argv": sys.argv[1:], "env": dict(os.environ)}) + "\\n")
        fh.flush()

mode = os.environ.get("FAKE_" + verb.replace("-", "_").upper(), "ok")
if mode == "hang":
    time.sleep(float(os.environ["FAKE_HANG_SECS"]))
    sys.exit(0)
if mode == "fail":
    sys.stderr.write("fake cmux: " + verb + " refused\\n")
    sys.exit(1)
if verb == "tree":
    sys.stdout.write("surface:1 [terminal] " + os.environ["FAKE_TREE_SURFACE"] + "\\n")
sys.exit(0)
'''

HANGING_ANALYZER = '''#!/usr/bin/env python3
import os, time
time.sleep(float(os.environ["FAKE_HANG_SECS"]))
'''


# ----------------------------------------------------------------- tree fixture


def build_tree(tmp_path):
    """A private copy of `treko/` in the layout `analyze.py` expects.

    `test_*.py` is copied in deliberately: criterion 11 asserts `/test_server.py` is a
    `404`, and that only proves the manifest is what refuses if the file is really there.
    """
    tree = tmp_path / "treko"
    if tree.exists():
        return tree  # idempotent: a test launching a second server reuses the first's tree
    shutil.copytree(REAL_TREE, tree, ignore=shutil.ignore_patterns("__pycache__"))
    hooks = tmp_path / "hooks"
    hooks.mkdir()
    (hooks / "lib").symlink_to(REPO_ROOT / "hooks" / "lib", target_is_directory=True)
    return tree


def install_fake_cmux(tmp_path):
    path = tmp_path / "fake-cmux"
    path.write_text(FAKE_CMUX)
    path.chmod(0o755)
    return path


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


# ----------------------------------------------------------------- the server process


class Server:
    """A launched `server.py`, its stderr on disk, and the fake's invocation log."""

    def __init__(self, proc, port, tree, stderr_path, cmux_log, surface):
        self.proc = proc
        self.port = port
        self.tree = tree
        self.stderr_path = stderr_path
        self.cmux_log = cmux_log
        self.surface = surface
        self._token = None

    # -- lifecycle ---------------------------------------------------

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=10)

    def wait_for_exit(self, timeout):
        try:
            return self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            return None

    # -- observation -------------------------------------------------

    @property
    def stderr(self):
        return self.stderr_path.read_text(errors="replace")

    @property
    def token(self):
        """Read once from the served page, which is the only place it is published."""
        if self._token is None:
            body = self.get("/").body.decode()
            match = re.search(r'<meta name="tracker-token" content="([^"]+)">', body)
            assert match, "GET / served no token meta tag"
            self._token = match.group(1)
        return self._token

    def cmux_calls(self, verb=None):
        if not self.cmux_log.exists():
            return []
        calls = [json.loads(line) for line in
                 self.cmux_log.read_text().splitlines() if line.strip()]
        if verb is None:
            return calls
        return [c for c in calls if c["argv"] and c["argv"][0] == verb]

    def audit(self, **match):
        """Audit lines from the captured stderr, newest last, optionally filtered."""
        lines = [parse_audit(line) for line in self.stderr.splitlines()]
        lines = [line for line in lines if line]
        for key, value in match.items():
            lines = [line for line in lines if line.get(key) == value]
        return lines

    def last_audit(self, **match):
        lines = self.audit(**match)
        assert lines, "no audit line matched %r in:\n%s" % (match, self.stderr)
        return lines[-1]

    # -- requests ----------------------------------------------------

    def request(self, method, path, *, headers=None, body=None, host=None, timeout=30):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=timeout)
        sent = dict(headers or {})
        sent.setdefault("Host", host if host is not None else "127.0.0.1:%d" % self.port)
        try:
            conn.request(method, path, body=body, headers=sent)
            raw = conn.getresponse()
            return Response(raw.status, dict(raw.getheaders()), raw.read())
        finally:
            conn.close()

    def get(self, path, **kwargs):
        return self.request("GET", path, **kwargs)

    def command(self, command_id, *, token=None, origin=None, extra=None, body=None,
                content_type="application/json", timeout=30):
        """POST /command with the real token and same-origin headers unless overridden."""
        headers = {"Content-Type": content_type} if content_type else {}
        headers["Origin"] = origin if origin is not None else "http://127.0.0.1:%d" % self.port
        chosen = self.token if token is None else token
        if chosen is not False:
            headers["X-Tracker-Token"] = chosen
        if body is None:
            body = json.dumps({"id": command_id})
        headers.update(extra or {})
        return self.request("POST", "/command", headers=headers, body=body, timeout=timeout)


class Response:
    def __init__(self, status, headers, body):
        self.status = status
        self.headers = headers
        self.body = body

    def json(self):
        return json.loads(self.body.decode())

    def header(self, name):
        for key, value in self.headers.items():
            if key.lower() == name.lower():
                return value
        return None


AUDIT_RE = re.compile(
    r"^(?P<stamp>\S+) (?P<outcome>accepted|refused|failed) id=(?P<id>\S+) "
    r"surface=(?P<surface>\S+) sent=(?P<sent>\S+) status=(?P<status>\d+) "
    r"reason=(?P<reason>\S+) path=(?P<path>\S+) errno=(?P<errno>\S+)$")


def parse_audit(line):
    match = AUDIT_RE.match(line.strip())
    return match.groupdict() if match else None


# ----------------------------------------------------------------- launching


def server_env(tmp_path, tree, cmux_bin, cmux_log, *, surface=FAKE_SURFACE,
               tree_surface=None, overrides=None):
    env = dict(os.environ)
    env.update({
        "CMUX_BIN": str(cmux_bin),
        "CMUX_SURFACE_ID": surface,
        "FAKE_CMUX_LOG": str(cmux_log),
        "FAKE_TREE_SURFACE": tree_surface if tree_surface is not None else surface,
        "FAKE_HANG_SECS": str(HANG_SECS),
        # Pointed at the per-test tree, never left to the default or to the developer's
        # own value. Two things depend on it. A launch that resolved the store to the
        # real `$XDG_STATE_HOME/treko` would read -- and `reanalyze` would rewrite --
        # the machine's live survey, which is the same class of harm as touching the
        # real `treko/` and is why every server here already runs against a copy. And
        # naming the tree keeps the store exactly where every test written before this
        # feature expects it, `<tree>/tracker-data.js`, so those tests assert what they
        # always did; the store-location tests override it explicitly to prove the
        # configured directory is what is served.
        "TREKO_STORE_DIR": str(tree),
    })
    # Inherited overrides would leak a developer's own tuning into every test.
    for key in ("TREKO_PORT", "TREKO_IDLE_SECS", "TREKO_POLL_SECS",
                "TREKO_ANALYZE_SECS"):
        env.pop(key, None)
    env.update(overrides or {})
    return env


def launch(tmp_path, *, tree=None, overrides=None, surface=FAKE_SURFACE,
           tree_surface=None, port=None, repo=None, wait=True, stderr_path=None):
    """Start `server.py` as a direct child with stderr on disk, as §Security specifies."""
    tree = tree if tree is not None else build_tree(tmp_path)
    cmux_bin = install_fake_cmux(tmp_path)
    cmux_log = tmp_path / "cmux-calls.jsonl"
    port = port if port is not None else free_port()
    stderr_path = stderr_path or (tmp_path / "server-stderr.log")

    env = server_env(tmp_path, tree, cmux_bin, cmux_log, surface=surface,
                     tree_surface=tree_surface, overrides=overrides)
    env["TREKO_PORT"] = str(port)

    handle = open(stderr_path, "ab", buffering=0)
    try:
        proc = subprocess.Popen(
            [sys.executable, str(tree / "server.py"), "--repo",
             str(repo if repo is not None else REPO_ROOT)],
            stdout=subprocess.DEVNULL, stderr=handle, env=env, cwd=str(tmp_path),
        )
    finally:
        handle.close()

    server = Server(proc, port, tree, stderr_path, cmux_log, surface)
    if wait:
        await_ready(server)
    return server


def await_ready(server, timeout=STARTUP_TIMEOUT_SECS):
    """Block until GET / answers, or fail naming the server's own stderr."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if server.proc.poll() is not None:
            raise AssertionError("server exited %d before serving:\n%s"
                                 % (server.proc.returncode, server.stderr))
        try:
            server.get("/", timeout=2)
            return server
        except (OSError, http.client.HTTPException):
            time.sleep(0.05)
    raise AssertionError("server did not answer within %ds:\n%s" % (timeout, server.stderr))


def refuses_connection(port, timeout=2):
    """True when nothing is listening — how "served nothing" is proven."""
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout):
            return False
    except OSError:
        return True


def port_free(port, deadline_secs):
    end = time.monotonic() + deadline_secs
    while time.monotonic() < end:
        if refuses_connection(port, timeout=1):
            return True
        time.sleep(0.2)
    return refuses_connection(port, timeout=1)
