#!/usr/bin/env python3
"""Control server for the Treko UI — the whole of this feature's trust boundary.

The wire contract (routes, status codes, audit-line format) is §Design 3 of
`docs/features/tracking-feature-state.spec.md`; the posture (token, surface binding,
bounded lifetime) is §Security. Both are authoritative: this module implements them and
decides nothing on its own. Where a constant appears here it is because the spec pins a
number, and the spec's reason is quoted next to it rather than restated from memory.

Launched as a direct, non-detached child of the Claude session with stderr inherited
(§Security). Detaching it silently disables the parent-death check; redirecting stderr
silently discards the audit log. Both failures leave the controls present in the code and
inert, which is why the launch shape is a contract and not a convenience.
"""

import argparse
import errno
import hmac
import http.client
import http.server
import json
import os
import secrets
import subprocess
import sys
import threading
import time
import urllib.parse
import webbrowser
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import store  # noqa: E402  (sibling module; the path insert above is what makes it importable)
import store_location  # noqa: E402  (D1, D2 and D4 live there; see D5 for why)
from store_location import StartupAbort  # noqa: E402  (moved out per D5, both modules import it)

# ----------------------------------------------------------------- pinned constants

HOST = "127.0.0.1"  # never 0.0.0.0, never a resolvable hostname (§Security)
DEFAULT_PORT = 8422  # PORTS.md owns this number; it is read here, not re-decided
PORT_ENV = "TREKO_PORT"

# Every timeout below is (default, floor, env var). The floors exist because §Security
# forbids a value meaning "never" -- an unspecified timeout is implemented as no timeout.
IDLE_SECS = (1800, 60, "TREKO_IDLE_SECS")
POLL_SECS = (5, 1, "TREKO_POLL_SECS")
ANALYZE_SECS = (60, 5, "TREKO_ANALYZE_SECS")

# The cmux probe and the send share one bound: 5s. An unbounded probe is a server that
# neither starts nor reports why (§Security); an unbounded send is a request that hangs.
CMUX_TIMEOUT_SECS = 5
CMUX_BIN = os.environ.get("CMUX_BIN", "cmux")
SURFACE_ENV = "CMUX_SURFACE_ID"

# Repo resolution and the busy-port probe are both startup-time, unattended subprocess/network
# calls on an attacker-controllable path (§"Auto-launch"); each gets its own bound rather than
# running unbounded.
GIT_TIMEOUT_SECS = 5
PORT_PROBE_TIMEOUT_SECS = 2  # the spec pins this: "GET /, 2s timeout"

MAX_BODY_BYTES = 1024  # 1 KiB; read at most this, never buffer an unbounded body
TOKEN_HEADER = "X-Tracker-Token"
INDEX_FILE = "Treko.dc.html"

# The three-row allowlist IS the authorization set (§Security). A fourth row is a spec
# change plus a judge round, never an implementation call. `reanalyze` sends no keystroke.
SEND_COMMANDS = {
    # cmux interprets the `\n` escape itself, matching panes/adapters/cmux.sh:164, which
    # passes "bash $launcher_q\n" from inside bash double quotes -- two literal characters.
    "clear": "/clear\\n",
    "handoff": "/handoff\\n",
}
LOCAL_COMMANDS = ("reanalyze",)
ALLOWED_IDS = frozenset(SEND_COMMANDS) | frozenset(LOCAL_COMMANDS)

# The servable set: an explicit, closed manifest. Criterion 13 proves it correct by
# loading the page -- a grep is not the contract, and four rounds of widening one search
# each opened a new blind spot just past the new edge (§Design 3). `_ds/` is enumerated by
# its two requested files, never globbed: the glob also covers three files nothing asks for.
STATIC_MANIFEST = (
    "vendor-resources.js",
    "support.js",
    "_ds/nocturne-73641b21-c7ad-488a-8264-a28262dfe83e/styles.css",
    "_ds/nocturne-73641b21-c7ad-488a-8264-a28262dfe83e/_ds_bundle.js",
    "tracker-data.js",
    "tracker-data-fallback.js",
    "tracker-data.sample.js",
    "vendor/react.production.min.js",
    "vendor/react-dom.production.min.js",
    "vendor/babel.min.js",
    "vendor/phosphor/regular/style.css",
    "vendor/phosphor/regular/Phosphor.woff2",
    "vendor/phosphor/fill/style.css",
    "vendor/phosphor/fill/Phosphor-Fill.woff2",
    "vendor/inter/inter.css",
    "vendor/inter/inter-latin.woff2",
    "treko-icon.png",
)

# Never mimetypes.guess_type: its answer depends on the host's /etc/mime.types, which would
# make the served type a property of the machine. `.html` is here because GET / serves the
# substituted page and that constant deserves one source -- GET / is not a manifest row, so
# the entry is deliberately unused by the manifest (§Design 3: the check is one-directional).
EXTENSION_TYPES = {
    ".js": "text/javascript",
    ".css": "text/css",
    ".html": "text/html",
    ".woff2": "font/woff2",
    ".png": "image/png",
}

CSP = (
    "default-src 'self'; connect-src 'self'; img-src 'self' data:; "
    "style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-eval'; "
    "frame-ancestors 'none'"
)

# tracker-data.js absent is the normal first-run path, not an error: store.py generates it,
# and tracker-data-fallback.js exists precisely to cover its absence. A 500 here would
# break the empty state instead of rendering it (§Design 3).
FIRST_RUN_OPTIONAL = "tracker-data.js"

SERVE_ROOT = Path(__file__).resolve().parent


# ----------------------------------------------------------------- audit log

_audit_lock = threading.Lock()


def audit(outcome, status, reason="-", command_id="-", surface="-", sent="no",
          path="-", errno_name="-", stream=sys.stderr):
    """One line per request. Refusals are logged as loudly as successes (§Design 3).

    Never logs request headers, bodies, or the token, in whole or in part: §Out of scope
    bans persisting the token to a file, and a log file is none of the three things it
    names, which is exactly why the prohibition is restated at the log.
    """
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = ("%s %s id=%s surface=%s sent=%s status=%s reason=%s path=%s errno=%s\n"
            % (stamp, outcome, command_id, surface, sent, status, reason, path, errno_name))
    with _audit_lock:
        stream.write(line)
        stream.flush()


# ----------------------------------------------------------------- startup checks


def read_timeout(spec, environ=None):
    """Resolve one (default, floor, env) triple. Rejects anything meaning "never"."""
    default, floor, var = spec
    raw = (environ if environ is not None else os.environ).get(var)
    if raw is None or raw == "":
        return default
    try:
        value = int(raw)
    except ValueError:
        raise StartupAbort("%s=%r is not an integer" % (var, raw))
    if value <= 0:
        raise StartupAbort("%s=%d would disable the timeout; it may not be disabled" % (var, value))
    if value < floor:
        sys.stderr.write("server: %s=%d raised to the %ds minimum\n" % (var, value, floor))
        return floor
    return value


def read_port(environ=None):
    raw = (environ if environ is not None else os.environ).get(PORT_ENV)
    if raw is None or raw == "":
        return DEFAULT_PORT
    try:
        port = int(raw)
    except ValueError:
        raise StartupAbort("%s=%r is not an integer" % (PORT_ENV, raw))
    if not 1 <= port <= 65535:
        raise StartupAbort("%s=%d is not a valid port" % (PORT_ENV, port))
    return port


def check_manifest_types(manifest=STATIC_MANIFEST, types=EXTENSION_TYPES):
    """manifest is a subset of the extension map -- checked one way only.

    Widening the manifest without widening the map is a server that will not start, which
    is the intended direction of the error. An unused map entry is legal and must not
    abort: the map carries `.html` for GET /, which is not a manifest row.
    """
    missing = sorted({Path(p).suffix for p in manifest} - set(types))
    if missing:
        raise StartupAbort(
            "manifest uses extensions absent from EXTENSION_TYPES: %s" % ", ".join(missing))


def check_index_injectable(root=SERVE_ROOT):
    """The token reaches the page through <head>; no <head>, no token.

    Same posture as the manifest check: surface it at startup, not when a user first loads
    the page and silently gets an unauthenticated UI.
    """
    index = root / INDEX_FILE
    try:
        text = index.read_text()
    except OSError as exc:
        raise StartupAbort("cannot read %s: %s" % (INDEX_FILE, exc.strerror))
    if "<head>" not in text:
        raise StartupAbort("%s has no <head> to inject the token into" % INDEX_FILE)


def bind_surface(environ=None, timeout=CMUX_TIMEOUT_SECS):
    """Capture the session's own surface UUID once, and prove it is a terminal.

    The UUID is inherited, never deduced. A send targeted at a *deduced* surface was
    delivered to a different live Claude session at exit 0 during task 1's spike
    (§"Injection route"); the fix is to delete the inference, not to check it harder.
    """
    env = environ if environ is not None else os.environ
    surface = (env.get(SURFACE_ENV) or "").strip()
    if not surface:
        raise StartupAbort(
            "%s is unset or empty -- the server was detached or launched outside cmux, and "
            "a send with no target defaults to whatever surface it inherits" % SURFACE_ENV)
    try:
        probe = subprocess.run(
            [CMUX_BIN, "read-screen", "--surface", surface],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise StartupAbort("`%s read-screen` exceeded %ds probing the surface" % (CMUX_BIN, timeout))
    except OSError as exc:
        raise StartupAbort("cannot run `%s`: %s" % (CMUX_BIN, exc.strerror))
    if probe.returncode != 0:
        raise StartupAbort(
            "`%s read-screen --surface %s` exited %d -- the control channel does not exist "
            "for this target (an agent-session surface is not a terminal)"
            % (CMUX_BIN, surface, probe.returncode))
    return surface


def resolve_repo(explicit_repo, timeout=GIT_TIMEOUT_SECS):
    """An explicit `--repo` is trusted as given. With none, resolve via git.

    `git rev-parse --show-toplevel` runs in the process's actual working directory, not
    `$PWD` -- a skill invoked from a subdirectory must survey the repo, not the
    subdirectory. Outside a repository this is an abort naming that reason, never a survey
    of an arbitrary directory (§"Design: auto-launch").
    """
    if explicit_repo is not None:
        return Path(explicit_repo).resolve()
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise StartupAbort("`git rev-parse --show-toplevel` exceeded %ds" % timeout)
    except OSError as exc:
        raise StartupAbort("cannot run git: %s" % exc.strerror)
    if result.returncode != 0:
        # git's own fatal message already reads "not a git repository ...", which is the
        # wording NO_REPO_RE pins; forwarded verbatim rather than paraphrased.
        raise StartupAbort(result.stderr.strip() or "not inside a git repository")
    return Path(result.stdout.strip()).resolve()


def probe_listener(port, timeout=PORT_PROBE_TIMEOUT_SECS):
    """`GET /` at a port this process could not bind. Distinguishes exactly two outcomes.

    Never tries to identify *which* session holds the port -- nothing in an HTTP response
    can answer that, and a confident-sounding guess there is worse than none (§"Design:
    auto-launch"). "A Treko page answered" is read off this server's own `Server` header,
    the one signature it emits about itself.
    """
    try:
        conn = http.client.HTTPConnection(HOST, port, timeout=timeout)
        try:
            conn.request("GET", "/")
            response = conn.getresponse()
            response.read()
            server_header = response.getheader("Server", "")
        finally:
            conn.close()
    except (OSError, http.client.HTTPException):
        return False
    return "treko" in server_header.lower()


# ----------------------------------------------------------------- send path


# The two unconfirmable states refuse identically on the wire -- 502 send_failed, nothing
# sent -- so the audit reason is the only place an operator can tell "cmux hung" from "cmux
# errored", and a stuck control channel needs a different response from a broken one. Keyed
# by state so task 9 can drive every value from the mapping rather than a hand-listed pair.
CONFIRM_REFUSAL_REASONS = {"unrunnable": "confirm_failed", "timeout": "confirm_timeout"}


def confirm_surface(surface, timeout=CMUX_TIMEOUT_SECS):
    """Re-resolve the bound UUID before any send.

    Returns 'present'|'absent'|'unrunnable'|'timeout'. "Could not confirm" is not
    "confirmed absent" and must never be read as "probably fine" -- the last two outcomes
    refuse, and they are the ones that are silent when wrong. They are separate states
    only so the audit stream keeps them apart; see CONFIRM_REFUSAL_REASONS.
    """
    try:
        tree = subprocess.run(
            [CMUX_BIN, "tree", "--id-format", "both"],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return "timeout"
    except OSError:
        return "unrunnable"
    if tree.returncode != 0:
        return "unrunnable"
    return "present" if surface in tree.stdout else "absent"


def send_keys(surface, payload, timeout=CMUX_TIMEOUT_SECS):
    """Invoke `cmux send`. Returns (ok, sent) where sent is 'yes' or 'unknown'.

    `unknown` is the honest answer whenever send was invoked and did not exit 0: a timeout
    kill may still have typed. A log that resolved this to "failed" would be a lie in the
    direction that loses the operator's trust.
    """
    try:
        result = subprocess.run(
            [CMUX_BIN, "send", "--surface", surface, "--", payload],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, "unknown"
    except OSError:
        return False, "unknown"
    if result.returncode != 0:
        sys.stderr.write("server: cmux send exited %d\n" % result.returncode)
        return False, "unknown"
    return True, "yes"


def run_reanalyze(repo_root, store_path, timeout):
    """Re-run the analyzer out of process and re-emit the store. Returns True on success.

    Out of process because the timeout has to be enforceable: `reanalyze` walks every card
    and every worktree, so "it will finish" is exactly the assumption that hangs a request
    forever. On any failure the previous tracker-data.js is left intact by §Design 2's
    atomic write, and the UI surfaces the failure rather than showing stale data as fresh.
    """
    analyzer = str(SERVE_ROOT / "analyze.py")
    try:
        result = subprocess.run(
            [sys.executable, analyzer, str(repo_root)],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return _reanalyze_failed("analyzer exceeded %ds" % timeout)
    except OSError as exc:
        return _reanalyze_failed("cannot run the analyzer: %s" % exc.strerror)
    if result.returncode != 0:
        # The analyzer's own stderr is the only thing that names the cause; without it a
        # reanalyze failure is a black box on the one path that rewrites the store.
        return _reanalyze_failed("analyzer exited %d: %s"
                                 % (result.returncode, result.stderr.strip().splitlines()[-1:]))
    try:
        run = json.loads(result.stdout)
    except ValueError:
        return _reanalyze_failed("analyzer stdout was not JSON")
    try:
        store.emit_run(store_path, run)
    except (OSError, ValueError) as exc:
        return _reanalyze_failed("store write failed: %s" % exc)
    return True


def _reanalyze_failed(detail):
    """Diagnostics go to stderr, never into the response body (§Design 3: no echo)."""
    sys.stderr.write("server: reanalyze failed -- %s\n" % detail)
    return False


# ----------------------------------------------------------------- HTTP handler


class ControlHandler(http.server.BaseHTTPRequestHandler):
    """Two dynamic routes plus a closed static mount. Every other path is 404."""

    protocol_version = "HTTP/1.1"
    server_version = "treko"
    sys_version = ""

    # The base class emits an Apache-style line per request to stderr. The audit line is
    # the record this component keeps; a second, unstructured one only dilutes it.
    def log_message(self, fmt, *args):
        pass

    def __getattr__(self, name):
        # BaseHTTPRequestHandler dispatches on do_<METHOD>. Anything not defined below is
        # 405 rather than the base class's 501, so an unusual verb is answered the same
        # way as a wrong one -- the status table admits no 501.
        if name.startswith("do_"):
            return self._method_not_allowed
        raise AttributeError(name)

    # ------------------------------------------------------------- plumbing

    @property
    def config(self):
        return self.server.config

    def _respond(self, status, body=b"", content_type=None, extra_headers=()):
        self.send_response(status)
        if content_type:
            self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for key, value in extra_headers:
            self.send_header(key, value)
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)

    def _fail(self, status, error, reason, command_id="-", sent="no", path="-", errno_name="-",
              outcome="refused"):
        """Every failure body is {"ok": false, "error": <code>} and echoes no request content.

        An error body that reflects input is a free XSS gadget, so nothing from the request
        reaches it -- not the path, not the id, not the header that failed.
        """
        body = json.dumps({"ok": False, "error": error}).encode()
        self._respond(status, body, "application/json")
        audit(outcome, status, reason=reason, command_id=command_id, surface="-", sent=sent,
              path=path, errno_name=errno_name)

    def _method_not_allowed(self):
        self._fail(405, "method_not_allowed", "method_not_allowed")

    def _host_ok(self):
        """Reject any Host that is not 127.0.0.1:<port>.

        A DNS-rebinding attack reaches a localhost server with an attacker-chosen Host, and
        GET / hands out the credential with no Origin to check, because a top-level
        navigation sends none.
        """
        return self.headers.get("Host", "") == self.config["origin_host"]

    # ------------------------------------------------------------- routes

    def do_GET(self):
        if not self._host_ok():
            return self._fail(403, "forbidden", "host_mismatch")
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if path == "/":
            return self._serve_index()
        if path == "/command":
            return self._method_not_allowed()
        return self._serve_static(path)

    def do_OPTIONS(self):
        if not self._host_ok():
            return self._fail(403, "forbidden", "host_mismatch")
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if path != "/command":
            return self._method_not_allowed()
        # 204 and no Access-Control-Allow-* header of any kind. The server never emits
        # CORS headers, so a genuine cross-origin preflight fails by construction -- there
        # is no allow-list of origins to get wrong, because there is no allow-list at all.
        self._respond(204)
        audit("accepted", 204, reason="-")

    def do_POST(self):
        if not self._host_ok():
            return self._fail(403, "forbidden", "host_mismatch")
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if path != "/command":
            if path == "/" or path.lstrip("/") in STATIC_MANIFEST:
                return self._method_not_allowed()
            return self._fail(404, "not_found", "not_found")
        return self._handle_command()

    def _serve_index(self):
        """GET / -- the token-bearing response, so it carries the CSP and no-store.

        no-store is not boilerplate: without it the browser may persist the token-bearing
        response into its own disk cache, which is a file on disk holding the credential,
        just not one this repo wrote.
        """
        index = SERVE_ROOT / INDEX_FILE
        try:
            text = index.read_text()
        except OSError as exc:
            return self._fail(500, "asset_unreadable", "asset_unreadable", path=INDEX_FILE,
                              errno_name=errno.errorcode.get(exc.errno, "-"), outcome="failed")
        meta = '<meta name="tracker-token" content="%s">' % self.config["token"]
        body = text.replace("<head>", "<head>\n" + meta, 1).encode()
        self._respond(200, body, EXTENSION_TYPES[".html"], extra_headers=(
            ("Cache-Control", "no-store"),
            ("Content-Security-Policy", CSP),
            ("X-Content-Type-Options", "nosniff"),
        ))
        audit("accepted", 200, reason="-")

    def _serve_static(self, path):
        relative = path.lstrip("/")
        if relative not in STATIC_MANIFEST:
            # Includes /favicon.ico, which every browser requests unprompted and which is
            # deliberately not served, and every traversal probe: a path that is not a
            # manifest row is not servable, however it is spelled.
            return self._fail(404, "not_found", "not_found")

        if relative == FIRST_RUN_OPTIONAL:
            # The one row that lives outside the serving root (D3). The check below is
            # re-pointed at the store's directory, never removed -- a planted symlink 403s.
            root, target = self.config["store_dir"], self.config["store_path"]
        else:
            root, target = SERVE_ROOT, SERVE_ROOT / relative
        try:
            resolved = target.resolve()
        except OSError as exc:
            return self._fail(500, "asset_unreadable", "asset_unreadable", path=relative,
                              errno_name=errno.errorcode.get(exc.errno, "-"), outcome="failed")
        if root not in resolved.parents:
            # A manifest row that resolves outside the serving root -- a planted symlink.
            # §Design 3 mandates 403 here; the reason enum has no value for it (see the
            # note in the task-8 handoff), so it is logged distinctly rather than silently.
            return self._fail(403, "forbidden", "path_escape", path=relative)

        try:
            body = resolved.read_bytes()
        except FileNotFoundError as exc:
            if relative == FIRST_RUN_OPTIONAL:
                return self._fail(404, "not_found", "not_found", path=relative)
            return self._fail(500, "asset_unreadable", "asset_unreadable", path=relative,
                              errno_name=errno.errorcode.get(exc.errno, "-"), outcome="failed")
        except OSError as exc:
            return self._fail(500, "asset_unreadable", "asset_unreadable", path=relative,
                              errno_name=errno.errorcode.get(exc.errno, "-"), outcome="failed")

        # nosniff matters because criterion 13 asserts the UI *renders*: a stylesheet served
        # as the wrong type is discarded by the browser while still answering 200, and set
        # equality would pass over an unstyled page.
        self._respond(200, body, EXTENSION_TYPES[Path(relative).suffix], extra_headers=(
            ("X-Content-Type-Options", "nosniff"),
        ))
        audit("accepted", 200, reason="-", path=relative)

    # ------------------------------------------------------------- POST /command

    def _handle_command(self):
        """Header checks precede the body, so an unauthenticated caller learns nothing.

        Bad token, unknown id and bad origin all collapse to one 403 on the wire, so the
        endpoint cannot be used to enumerate the allowlist or confirm a guessed token. The
        audit line carries the internal cause, on a stream the caller cannot read.
        """
        origin = self.headers.get("Origin")
        if origin is not None and origin != self.config["origin"]:
            return self._fail(403, "forbidden", "origin_mismatch")
        fetch_site = self.headers.get("Sec-Fetch-Site")
        if fetch_site is not None and fetch_site != "same-origin":
            return self._fail(403, "forbidden", "origin_mismatch")

        presented = self.headers.get(TOKEN_HEADER, "")
        if not hmac.compare_digest(presented, self.config["token"]):
            return self._fail(403, "forbidden", "bad_token")

        media_type = self.headers.get("Content-Type", "").split(";")[0].strip().lower()
        if media_type != "application/json":
            return self._fail(415, "unsupported_media_type", "unsupported_media_type")

        payload = self._read_body()
        if payload is None:
            return  # _read_body has already answered and logged

        command_id = payload.get("id")
        if command_id not in ALLOWED_IDS:
            return self._fail(403, "forbidden", "unknown_id")

        if command_id in LOCAL_COMMANDS:
            return self._run_local(command_id)
        return self._run_send(command_id)

    def _read_body(self):
        """Returns the parsed object, or None having already answered.

        Reads at most 1 KiB + 1 byte: the cap is enforced on the read, not merely checked
        against a header a caller controls.
        """
        if self.headers.get("Transfer-Encoding"):
            self._fail(400, "malformed", "malformed")
            return None
        declared = self.headers.get("Content-Length")
        if declared is None:
            self._fail(400, "malformed", "malformed")
            return None
        try:
            length = int(declared)
        except ValueError:
            self._fail(400, "malformed", "malformed")
            return None
        if length < 0:
            self._fail(400, "malformed", "malformed")
            return None
        if length > MAX_BODY_BYTES:
            self._fail(413, "too_large", "too_large")
            return None

        raw = self.rfile.read(min(length, MAX_BODY_BYTES + 1))
        if len(raw) > MAX_BODY_BYTES:
            self._fail(413, "too_large", "too_large")
            return None
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            self._fail(400, "malformed", "malformed")
            return None
        # Exactly one key, `id`, a string. Unknown keys are a 400, never ignored: silent
        # tolerance is how an argument field gets smuggled in later, and commands take no
        # arguments in v1 or after.
        if not isinstance(payload, dict) or set(payload) != {"id"} \
                or not isinstance(payload.get("id"), str):
            self._fail(400, "malformed", "malformed")
            return None
        return payload

    def _run_local(self, command_id):
        ok = run_reanalyze(self.config["repo_root"], self.config["store_path"],
                           self.config["analyze_secs"])
        if not ok:
            return self._fail(500, "reanalyze_failed", "reanalyze_failed",
                              command_id=command_id, outcome="failed")
        body = json.dumps({"ok": True, "id": command_id}).encode()
        self._respond(200, body, "application/json")
        audit("accepted", 200, reason="-", command_id=command_id, sent="no")

    def _run_send(self, command_id):
        surface = self.config["surface"]
        state = confirm_surface(surface)
        if state == "absent":
            # Criterion 9: the refusal happens on the near side of the socket, so nothing
            # reaches the focused tab.
            return self._fail(409, "unresolved_surface", "unresolved_surface",
                              command_id=command_id)
        if state in CONFIRM_REFUSAL_REASONS:
            return self._fail(502, "send_failed", CONFIRM_REFUSAL_REASONS[state],
                              command_id=command_id, outcome="failed")

        ok, sent = send_keys(surface, SEND_COMMANDS[command_id])
        if not ok:
            body = json.dumps({"ok": False, "error": "send_failed"}).encode()
            self._respond(502, body, "application/json")
            audit("failed", 502, reason="send_failed", command_id=command_id,
                  surface=surface, sent=sent)
            return
        body = json.dumps({"ok": True, "id": command_id}).encode()
        self._respond(200, body, "application/json")
        audit("accepted", 200, reason="-", command_id=command_id, surface=surface, sent=sent)


class ControlServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, handler, config):
        self.config = config
        self.last_request = time.monotonic()
        super().__init__(address, handler)

    def process_request(self, request, client_address):
        self.last_request = time.monotonic()
        super().process_request(request, client_address)


# ----------------------------------------------------------------- lifetime


def watchdog(httpd, idle_secs, poll_secs, parent_pid, stop):
    """Bounded lifetime, both halves, on their own poll -- explicitly not the idle timer.

    The parent-death check is the portable one: prctl(PR_SET_PDEATHSIG) does not exist on
    macOS, the binding platform. On POSIX an orphan is reparented, so getppid() changes.
    """
    while not stop.wait(poll_secs):
        if os.getppid() != parent_pid:
            sys.stderr.write("server: parent session ended; exiting\n")
            break
        if time.monotonic() - httpd.last_request >= idle_secs:
            sys.stderr.write("server: idle for %ds; exiting\n" % idle_secs)
            break
    else:
        return
    threading.Thread(target=httpd.shutdown, daemon=True).start()


def build_config(surface, token, repo_root, port, analyze_secs, store_dir):
    origin = "http://%s:%d" % (HOST, port)
    return {
        "surface": surface,
        "token": token,
        "repo_root": repo_root,
        "store_dir": store_dir,
        # The only place the store path is constructed; a second one drifts (D3).
        "store_path": store_dir / FIRST_RUN_OPTIONAL,
        "origin": origin,
        "origin_host": "%s:%d" % (HOST, port),
        "analyze_secs": analyze_secs,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description="Treko control server.")
    parser.add_argument("--repo", default=None,
                        help="repository the `reanalyze` command re-surveys; resolved via "
                             "`git rev-parse --show-toplevel` in the cwd when omitted")
    parser.add_argument("--open", action="store_true", dest="open_browser",
                        help="open a browser at the bound URL after a successful bind, "
                             "never as a forked child (§'Auto-launch must start the server "
                             "the way the docs tell a human to')")
    args = parser.parse_args(argv)

    try:
        port = read_port()
        idle_secs = read_timeout(IDLE_SECS)
        poll_secs = read_timeout(POLL_SECS)
        analyze_secs = read_timeout(ANALYZE_SECS)
        check_manifest_types()
        check_index_injectable()
        repo_root = resolve_repo(args.repo)
        surface = bind_surface()
        store_dir = store_location.ensure_store_dir(store_location.read_store_dir())
        # Generated at startup, held in memory only, never written to disk, never passed
        # as a command-line argument (which would expose it to ps). Dying process, dead
        # token. Built here so the copy below can take the path from `config`.
        token = secrets.token_urlsafe(32)
        config = build_config(surface, token, repo_root, port, analyze_secs, store_dir)
        # D4, on this same abort path: a corrupt legacy store stops the launch (decision 4).
        store_location.adopt_legacy_store(config["store_path"],
                                          SERVE_ROOT / FIRST_RUN_OPTIONAL)
    except StartupAbort as exc:
        sys.stderr.write("server: %s\n" % exc)
        return 2

    try:
        httpd = ControlServer((HOST, port), ControlHandler, config)
    except OSError as exc:
        # A bind that fails is a startup abort, never a fallback. A second server on a
        # different port leaves the browser talking to the first one, which holds a
        # different token, so every button returns the deliberately collapsed 403 and the
        # operator reads a stale-token problem as a broken feature.
        if exc.errno == errno.EADDRINUSE:
            if probe_listener(port):
                sys.stderr.write(
                    "server: port %d is already in use -- the probe answered as a Treko "
                    "page already serving there. Not probing for a free port.\n" % port)
            else:
                sys.stderr.write(
                    "server: port %d is already in use -- the probe did not answer as a "
                    "Treko page (something else holds this port). Not probing for a free "
                    "port.\n" % port)
        else:
            sys.stderr.write("server: cannot bind %s:%d: %s\n"
                             % (HOST, port, errno.errorcode.get(exc.errno, exc.strerror)))
        return 2

    # Both steps below are auto-launch only (--open); a plain `server.py` start must not
    # gain a side effect it never had -- other tests start the server against a deliberately
    # emptied or symlinked tracker-data.js and expect it to stay exactly as they left it.
    if args.open_browser:
        # First-run only: a repo with no run would otherwise open to an empty page, which
        # reads as "nothing is in flight" rather than "nothing has been measured". A repo
        # that already has one is never re-analyzed here -- that is what the `reanalyze`
        # button is for, and re-running on every launch would silently overwrite a survey
        # the user is reading.
        if not store.read_store(config["store_path"])["runs"]:
            run_reanalyze(repo_root, config["store_path"], analyze_secs)

        # Inside the already-running server process, after the bind above and before
        # serve_forever below -- never a forked child, which would become the server's new
        # parent and silently disable the watchdog's os.getppid() check.
        webbrowser.open(config["origin"])

    stop = threading.Event()
    watcher = threading.Thread(
        target=watchdog, args=(httpd, idle_secs, poll_secs, os.getppid(), stop), daemon=True)
    watcher.start()

    sys.stderr.write("server: http://%s:%d/ surface=%s idle=%ds poll=%ds store=%s\n"
                     % (HOST, port, surface, idle_secs, poll_secs, config["store_dir"]))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
