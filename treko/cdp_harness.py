"""A minimal headless-Chrome driver over the Chrome DevTools Protocol (CDP) — stdlib only.

Split out of `test_theme.py` for the same reason `server_harness.py` is split out of
`test_server.py`: this is fixture machinery, not an assertion, and it is reusable by any test
that needs to read resolved computed style from a real render (`docs/features/
treko-theme-and-layout.md` §Verification, "Proof C").

**Why a hand-rolled WebSocket client.** `Runtime.evaluate` over CDP is the only way to read
`getComputedStyle()` from outside the page without editing `Treko.dc.html` to inject a script —
and CDP's control channel is JSON-over-WebSocket, not HTTP. This repo's Python environment
carries no `websocket-client` / `websockets` / `selenium` / `requests` (checked: `pip3 list`
shows only `pytest`), and `Parallel-Agent Invariants` forbids adding a dependency unilaterally.
The client below implements just enough of RFC 6455 (client-to-server masking, server-to-client
unmasked frames, the 7/16/64-bit payload-length cases, fragmented-message reassembly) to carry
CDP's JSON messages both ways. Nothing here negotiates `permessage-deflate`; Chrome's CDP
endpoint does not require it.

Also: `Runtime.evaluate` runs in the same privileged console context DevTools itself uses, so it
executes regardless of the page's `script-src` CSP (which carries no `'unsafe-inline'` — Hazard
3) — the same reason typing into the DevTools console works on a page that would refuse an
injected `<script>` tag.

**Why not the interactive browser tool.** It refuses `file://` and is documented as being for
interactive use, not an unattended verification step (`docs/features/
treko-theme-and-layout.md` §Verification, Proof B and Proof C both say so explicitly).

**Launch discipline.** Chrome is started as a direct `subprocess.Popen` child, the same
discipline `server_harness.launch` uses for `server.py` — never `nohup`/`setsid`/backgrounded —
with a private, throwaway `--user-data-dir` so it never touches a developer's real profile, and
`close()` terminates it the same way `Server.stop()` does.

**`TREKO_CHROME_DENY_BIRD` — an opt-in escape hatch for a wedged macOS.** See
`BIRD_DENY_PROFILE` below. Off by default; a healthy machine never needs it, and it is
opt-in rather than an automatic retry on purpose — a silent relaunch under a
weakened sandbox would let a genuine Chrome fault look like a pass.
"""

import base64
import http.client
import json
import os
import socket
import struct
import subprocess
import time

CHROME_BINARY = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# docs/features/treko-theme-and-layout.md §"Pinned versions": both Proof B and Proof C must run
# this exact build -- "two hashes, or two contrast reads, from different Chrome builds are not
# comparable."
#
# Re-pinned 2026-08-24 from `151.0.7922.172`, which Chrome auto-updated away from at 15:04 local.
# The assert below fires before launch, so the whole browser-driven half of the suite (24 tests at
# that commit) failed at construction without reaching a page. Safe to move because nothing stores
# a Chrome-derived constant: `test_guards.py`'s sha256s hash file bytes, Proof A is a source
# comparison, Proof B's hashes are an archived 151 receipt that is never re-derived, and Proof C
# asserts WCAG thresholds live rather than against a recorded number. Full reasoning and the
# user's approval: the card's §"Pinned versions", "The Chrome re-pin, 2026-08-24".
PINNED_VERSION = "152.0.7977.54"

DEVTOOLS_TIMEOUT_SECS = 10
NAV_TIMEOUT_SECS = 20

# Set TREKO_CHROME_DENY_BIRD=1 to launch Chrome under `sandbox-exec` with the profile below.
#
# WHY. Chrome's browser process calls `-[NSFileManager ubiquityIdentityToken]` during
# startup — a *synchronous* XPC round-trip to the launchd agent `com.apple.bird`
# (iCloud Drive). When bird is crash-looping, launchd throttles it to "spawn scheduled" and
# queues that message for a service that never comes up, so the call never returns. Chrome
# hangs BEFORE it binds `--remote-debugging-port`: the process stays alive and silent,
# writes no `DevToolsActivePort`, and behaves identically under `--headless=new`/`old` and
# with or without `--no-sandbox`. Observed 2026-08-24 on macOS 26.5.2: `sample` parked
# 2612/2612 main-thread frames in `__NSXPCCONNECTION_IS_WAITING_FOR_A_SYNCHRONOUS_REPLY__`,
# and `launchctl print gui/$UID/com.apple.bird` reported `successive crashes = 48`
# (EXC_BREAKPOINT inside CloudKit's `NSXPCEncoder`). A 20-line Python program calling the
# same API hung too, which is what rules Chrome out as the cause.
#
# Denying the lookup makes the call return nil in 0s instead of hanging. macOS forbids
# nesting seatbelt profiles, so Chrome cannot initialise its own child sandbox inside ours
# — hence `--no-sandbox`, which is added ONLY on this path. Acceptable here and
# nowhere else: the harness renders a local `file://` page out of this repo, headless, in a
# throwaway profile, and kills it at teardown; no untrusted content is ever loaded.
#
# This is a workaround for a broken machine, not a fix. The fix is to stop bird
# crash-looping.
BIRD_DENY_PROFILE = (
    '(version 1)(allow default)'
    '(deny mach-lookup (global-name-regex #"^com\\.apple\\.bird"))'
)
DENY_BIRD_ENV = "TREKO_CHROME_DENY_BIRD"


def installed_version():
    """`Google Chrome --version` output verbatim, e.g. 'Google Chrome 151.0.7922.172'."""
    result = subprocess.run([CHROME_BINARY, "--version"], capture_output=True, text=True,
                             timeout=10)
    return result.stdout.strip()


def _free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class _WebSocket:
    """Just enough of RFC 6455 to talk to Chrome's CDP endpoint: text frames, both directions,
    extended payload lengths, fragmented-message reassembly. No compression."""

    def __init__(self, host, port, path):
        self.sock = socket.create_connection((host, port), timeout=DEVTOOLS_TIMEOUT_SECS)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            "GET %s HTTP/1.1\r\n"
            "Host: %s:%d\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n" % (path, host, port, key)
        )
        self.sock.sendall(request.encode())
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("CDP websocket handshake got no response")
            response += chunk
        header, _, rest = response.partition(b"\r\n\r\n")
        status_line = header.split(b"\r\n", 1)[0]
        if b"101" not in status_line:
            raise ConnectionError("CDP websocket handshake refused: %r" % status_line)
        self._buf = rest

    def send(self, text):
        payload = text.encode("utf-8")
        mask = os.urandom(4)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        length = len(payload)
        if length < 126:
            header = struct.pack("!BB", 0x81, 0x80 | length)
        elif length < 65536:
            header = struct.pack("!BBH", 0x81, 0x80 | 126, length)
        else:
            header = struct.pack("!BBQ", 0x81, 0x80 | 127, length)
        self.sock.sendall(header + mask + masked)

    def _recv_exact(self, n):
        while len(self._buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("CDP websocket closed mid-frame")
            self._buf += chunk
        data, self._buf = self._buf[:n], self._buf[n:]
        return data

    def recv(self):
        """One complete message, reassembled across continuation frames if Chrome sends any."""
        parts = []
        while True:
            first, second = self._recv_exact(2)
            fin = first & 0x80
            opcode = first & 0x0F
            masked = second & 0x80
            length = second & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._recv_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._recv_exact(8))[0]
            mask_key = self._recv_exact(4) if masked else None
            payload = self._recv_exact(length)
            if mask_key:
                payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
            if opcode == 0x8:
                raise ConnectionError("CDP websocket closed by Chrome")
            if opcode in (0x0, 0x1, 0x2):
                parts.append(payload)
            if fin:
                break
        return b"".join(parts).decode("utf-8")

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class Chrome:
    """A headless Chrome process plus one attached page target, driven over CDP."""

    def __init__(self, user_data_dir):
        version = installed_version()
        if PINNED_VERSION not in version:
            raise AssertionError(
                "Chrome version mismatch: pinned %s (docs/features/treko-theme-and-layout.md "
                "§\"Pinned versions\"), installed %r -- Proof C says two contrast reads "
                "from different Chrome builds are not comparable"
                % (PINNED_VERSION, version)
            )
        self.devtools_port = _free_port()
        self.denied_bird = os.environ.get(DENY_BIRD_ENV) == "1"
        flags = ["--headless=new", "--disable-gpu", "--no-first-run", "--disable-extensions",
                 "--remote-debugging-port=%d" % self.devtools_port,
                 "--user-data-dir=%s" % user_data_dir, "about:blank"]
        if self.denied_bird:
            # `sandbox-exec` execs Chrome in place, so `self.proc.pid` is still Chrome's own pid
            # and `close()` reaps it unchanged.
            argv = ["sandbox-exec", "-p", BIRD_DENY_PROFILE, CHROME_BINARY,
                    "--no-sandbox"] + flags
        else:
            argv = [CHROME_BINARY] + flags
        self.proc = subprocess.Popen(
            argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self._msg_id = 0
        self.ws = None
        try:
            self._attach_to_page()
        except Exception as failure:
            self.close()
            if self.denied_bird:
                raise
            raise AssertionError(
                "%s\n\nIf Chrome stayed alive but silent and never bound the devtools port, "
                "this is probably the macOS iCloud (`com.apple.bird`) hang: check "
                "`launchctl print gui/$UID/com.apple.bird` for a non-zero `successive crashes`, "
                "then re-run with %s=1. See BIRD_DENY_PROFILE in this file."
                % (failure, DENY_BIRD_ENV)
            ) from failure

    def _attach_to_page(self):
        deadline = time.time() + DEVTOOLS_TIMEOUT_SECS
        pages = []
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise AssertionError(
                    "chrome exited %d before devtools was reachable" % self.proc.returncode)
            try:
                conn = http.client.HTTPConnection("127.0.0.1", self.devtools_port, timeout=1)
                conn.request("GET", "/json/list")
                resp = conn.getresponse()
                pages = [t for t in json.loads(resp.read()) if t.get("type") == "page"]
                if pages:
                    break
            except (OSError, http.client.HTTPException):
                pass
            time.sleep(0.05)
        if not pages:
            raise AssertionError("chrome never reported a page target on the devtools endpoint")
        ws_url = pages[0]["webSocketDebuggerUrl"]
        rest = ws_url.split("://", 1)[1]
        host_port, path = rest.split("/", 1)
        host, port = host_port.split(":")
        self.ws = _WebSocket(host, int(port), "/" + path)
        self._send("Page.enable")

    def _send(self, method, params=None):
        self._msg_id += 1
        mid = self._msg_id
        self.ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
        return mid

    def _wait_for(self, mid, timeout=NAV_TIMEOUT_SECS):
        deadline = time.time() + timeout
        while time.time() < deadline:
            message = json.loads(self.ws.recv())
            if message.get("id") == mid:
                return message
        raise TimeoutError("no CDP response for message id %d within %ds" % (mid, timeout))

    def navigate(self, url):
        mid = self._send("Page.navigate", {"url": url})
        resp = self._wait_for(mid)
        if "error" in resp:
            raise AssertionError("Page.navigate failed: %r" % resp["error"])
        self._wait_ready()

    def reload(self):
        mid = self._send("Page.reload")
        self._wait_for(mid)
        self._wait_ready()

    def add_startup_script(self, source):
        """Run `source` in every new document BEFORE any page script executes.

        The only way to test a precondition the page reads *at mount* -- an unavailable or
        poisoned `localStorage`, say. Setting it up with `evaluate()` after load is too late:
        the seed has already run. Persists across `reload()`, which is what makes the
        seed-then-reload pattern the other tests use work here too.
        """
        mid = self._send("Page.addScriptToEvaluateOnNewDocument", {"source": source})
        resp = self._wait_for(mid)
        if "error" in resp:
            raise AssertionError(
                "Page.addScriptToEvaluateOnNewDocument failed: %r" % resp["error"])
        return resp["result"]["identifier"]

    def _wait_ready(self, timeout=NAV_TIMEOUT_SECS):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.evaluate("document.readyState") == "complete":
                return
            time.sleep(0.05)
        raise TimeoutError("page never reached readyState complete within %ds" % timeout)

    def evaluate(self, expression, timeout=NAV_TIMEOUT_SECS):
        """`Runtime.evaluate` with `returnByValue: true`."""
        mid = self._send("Runtime.evaluate",
                          {"expression": expression, "returnByValue": True})
        resp = self._wait_for(mid, timeout)
        if "error" in resp:
            raise AssertionError("Runtime.evaluate transport error: %r" % resp["error"])
        result = resp["result"]["result"]
        if result.get("subtype") == "error":
            raise AssertionError("page-side JS threw: %s" % result.get("description"))
        return result.get("value")

    def close(self):
        if self.ws is not None:
            self.ws.close()
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=10)
