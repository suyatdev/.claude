"""Task 16 (spec 3.4 to 3.6, 3.8; D47): POST /ledger's seven refusals, the shared token check and body reader, the two
U10 refusals. Owns A3 and A2's rows for the codes this task introduces. Not here: the ops (task 17), A8, the stub's answer.
Modules under test are imported inside each test, so one missing name fails only that test; each test names the wrong
shortcut it catches. Servers are real `server.py` processes; one is shared by every refusal row (each row asserts a refusal
changes nothing). The token goes only into request headers. API ASSUMED (D47): ledger_routes.token_ok(presented, expected);
read_json_body(headers, rfile, cap) -> parsed JSON or (status, error, reason); LEDGER_MAX_BODY_BYTES; check_ledger_post(
headers, rfile, config) -> (op, fields, None) or (None, None, (status, error, reason, audit_id))."""

import http.client
import io
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import server  # noqa: E402  (path shim above must run first)
import server_harness as harness  # noqa: E402

TOKEN = "X-Tracker-Token"
UNIT_TOKEN, UNIT_PORT = "unit-test-token-" + "a" * 27, 8422  # made-up values, not any server's
SENT, SURR, E2 = "0123456789abcdef", "\ud800", "é"  # SURR: json.dumps writes it as the ASCII escape \ud800
SETTLE_SECS, AUDIT_WAIT_SECS, SOCKET_SECS = 0.15, 5, 10
STEP_STATUSES = (400, 403, 413, 415, 422)
STEP_ERRORS = {"malformed", "forbidden", "unsupported_media_type", "too_large", "invalid_input", "relative_path",
               "no_such_directory", "no_such_run", "not_found", "method_not_allowed"}  # the last two: no route yet
D, R = "{dir}", "{run}"  # placeholders filled per context: a real folder, a run id the store holds
EVIL, X43, EVIL_ORIGIN = {"Host": "evil.test:1"}, "x" * 43, {"Origin": "http://evil.test"}
ana = lambda **more: dict({"op": "analyze", "directory": D}, **more)  # noqa: E731
DEL, REAN = {"op": "delete", "run": R}, {"op": "reanalyze", "run": R}
RM, RT = {"op": "remove", "item": SENT}, {"op": "retry", "item": SENT}
OPS = {"analyze": ana(), "reanalyze": REAN, "remove": RM, "retry": RT, "delete": DEL}
NO_RUN = {"op": "delete", "run": "no-such-run"}
exp = lambda status, error, reason=None, audit_id="-": (status, error, reason or error, audit_id)  # noqa: E731
bad = lambda op: exp(400, "malformed", audit_id=op)  # noqa: E731
BAD_TOKEN, HOST, ORIGIN = exp(403, "forbidden", "bad_token"), exp(403, "forbidden", "host_mismatch"), exp(403, "forbidden", "origin_mismatch")
UNKNOWN_OP, T415, MAL = exp(403, "forbidden", "unknown_op"), exp(415, "unsupported_media_type"), exp(400, "malformed")
M3 = (400, "malformed", "malformed")
INV_A, NO_RUN_DEL = exp(422, "invalid_input", audit_id="analyze"), exp(404, "no_such_run", audit_id="delete")


def row(name, body, expect, hdr=None, size=None):
    return pytest.param(body, hdr or {}, expect, size, id=name)


def many(expect, cases, prefix=""):
    return [row(prefix + name, body, expect) for name, body in cases.items()]


def make_ctx(root):
    """Folders the rows name, under a fake home: a project folder, a file, and links to a file, nowhere and a folder."""
    home = Path(root) / "home"
    (home / "proj").mkdir(parents=True)
    (home / "proj" / "sentinel.txt").write_text("keep")
    (home / "afile").write_text("x")
    (home / "link-to-file").symlink_to(home / "afile")
    (home / "dangling").symlink_to(home / "nowhere")
    (home / "linkdir").symlink_to(home / "proj", target_is_directory=True)
    return SimpleNamespace(home=str(home), dir=str(home / "proj"), run="unit-run", srv=None)


def fill(value, ctx):
    if isinstance(value, dict):
        return {key: fill(item, ctx) for key, item in value.items()}
    if isinstance(value, str):
        return value.replace("{dir}", ctx.dir).replace("{home}", ctx.home).replace("{run}", ctx.run)
    return value


def pad(data, size=None):
    return data if size is None else data + b" " * (size - len(data))  # trailing spaces keep JSON valid


def body_bytes(body, ctx, size=None):
    if isinstance(body, (bytes, str)):
        return pad(body if isinstance(body, bytes) else fill(body, ctx).encode(), size)
    return pad(json.dumps(fill(body, ctx)).encode(), size)


nest = lambda opened, closed=0: ("[" * opened + "]" * closed).encode()  # noqa: E731


def build_headers(origin_host, token, length, overrides):
    headers = {"Host": origin_host, "Origin": "http://" + origin_host, TOKEN: token,
               "Content-Type": "application/json", "Content-Length": str(length)}
    headers.update(overrides)
    return {key: value for key, value in headers.items() if value is not None}  # None removes a header


def message(headers):
    msg = http.client.HTTPMessage()
    for key, value in headers.items():
        msg[key] = value
    return msg


def raw(srv, method, path, headers, body=b""):
    """One request on a raw socket (so a header can be absent or odd); (status, bytes after the headers)."""
    lines = ["%s %s HTTP/1.1" % (method, path), "Connection: close"] + ["%s: %s" % item for item in headers.items()]
    chunks = []
    with socket.create_connection(("127.0.0.1", srv.port), timeout=SOCKET_SECS) as sock:
        try:
            sock.sendall(("\r\n".join(lines) + "\r\n\r\n").encode("latin-1") + body)
            chunk = sock.recv(65536)
            while chunk:
                chunks.append(chunk)
                chunk = sock.recv(65536)
        except (BrokenPipeError, ConnectionResetError):
            pass  # the server may answer and close before it has read a body it refused
    head, _, rest = b"".join(chunks).partition(b"\r\n\r\n")
    return (int(head.split(b" ", 2)[1]) if head.startswith(b"HTTP/") else None), rest


def snapshot(*roots):
    walked = [os.path.join(folder, name) for root in roots for folder, dirs, files in os.walk(str(root))
              if "__pycache__" not in folder for name in dirs + files]
    return {path: (info.st_mode, info.st_size, info.st_mtime_ns) for path, info in ((p, os.lstat(p)) for p in walked)}


def new_audit_lines(srv, baseline, at_least=1):
    deadline = time.monotonic() + AUDIT_WAIT_SECS
    while len(srv.audit()) < baseline + at_least and time.monotonic() < deadline:
        time.sleep(0.02)
    time.sleep(SETTLE_SECS)  # the line is written after the reply; a stray second one needs time to land
    return srv.audit()[baseline:]


def serve(ctx, srv):
    import store
    assert srv.token  # read now: fetching it later would add an audit line (GET /) inside a test's window
    ctx.srv, ctx.run = srv, store.read_store(srv.tree / "tracker-data.js")["runs"][0]["id"]
    return ctx


def send(ctx, path, body, overrides, size=None):
    srv, data = ctx.srv, body_bytes(body, ctx, size)
    return raw(srv, "POST", path, build_headers("127.0.0.1:%d" % srv.port, srv.token, len(data), overrides), data)


@pytest.fixture(scope="module")
def shared(tmp_path_factory):
    root = tmp_path_factory.mktemp("post")
    ctx = make_ctx(root)
    srv = harness.launch(root, overrides={"HOME": ctx.home})
    try:
        yield serve(ctx, srv)
    finally:
        srv.stop()


@pytest.fixture
def unit(tmp_path, monkeypatch):
    import store
    ctx = make_ctx(tmp_path)
    (tmp_path / "store").mkdir()
    store.write_store(tmp_path / "store" / "tracker-data.js", store.upsert_run(store.new_store(), {
        "id": ctx.run, "name": "run", "dir": "~/dev", "branches": [], "features": [], "analyzedAt": "2026-11-03T09:00:00Z"}))
    monkeypatch.setenv("HOME", ctx.home)
    # subprocess.run and check_output go through Popen: a validation step that starts a process (git, cmux) fails here
    monkeypatch.setattr(subprocess, "Popen", lambda *args, **kwargs: pytest.fail("a validation step started a process"))
    ctx.config = server.build_config(None, UNIT_TOKEN, Path("/repo"), UNIT_PORT, 60, tmp_path / "store", server.CHANNEL_OK)
    return ctx


def check(ctx, body, overrides=None, size=None):
    import ledger_routes
    data = body_bytes(body, ctx, size)
    headers = message(build_headers("127.0.0.1:%d" % UNIT_PORT, UNIT_TOKEN, len(data), overrides or {}))
    return ledger_routes.check_ledger_post(headers, io.BytesIO(data), ctx.config)


ROWS = [
    # step 1: Host, then Origin and Sec-Fetch-Site, then the token (the two host rows pass today: do_POST checks Host first)
    row("host", DEL, HOST, EVIL), row("origin", DEL, ORIGIN, EVIL_ORIGIN), row("fetch-site", DEL, ORIGIN, {"Sec-Fetch-Site": "cross-site"}),
    row("no-token", DEL, BAD_TOKEN, {TOKEN: None}), row("wrong-token", DEL, BAD_TOKEN, {TOKEN: X43}),
    row("token-byte-e9", DEL, BAD_TOKEN, {TOKEN: "\xe9"}), row("token-utf8-e", DEL, BAD_TOKEN, {TOKEN: E2.encode().decode("latin-1")}),
    row("host-before-origin-and-token", DEL, HOST, dict(EVIL, **dict(EVIL_ORIGIN, **{TOKEN: None}))),
    row("origin-before-token", DEL, ORIGIN, dict(EVIL_ORIGIN, **{TOKEN: X43})),
    row("token-before-content-type", "{", BAD_TOKEN, {TOKEN: None, "Content-Type": "text/plain"}),
    row("type-text", DEL, T415, {"Content-Type": "text/plain"}), row("type-missing", DEL, T415, {"Content-Type": None}),
    row("type-before-body", "{", T415, {"Content-Type": "text/plain"}),
    row("transfer-encoding", DEL, MAL, {"Transfer-Encoding": "chunked"}), row("no-content-length", DEL, MAL, {"Content-Length": None}),
    row("length-word", DEL, MAL, {"Content-Length": "abc"}), row("length-negative", DEL, MAL, {"Content-Length": "-1"}),
    row("4097-bytes", DEL, exp(413, "too_large"), size=4097),
    row("4096-bytes-reach-step-7", NO_RUN, NO_RUN_DEL, size=4096), row("1025-bytes-reach-step-7", NO_RUN, NO_RUN_DEL, size=1025),
    *many(MAL, {"not-json": "{", "empty-body": "", "json-list": "[1]", "json-null": "null", "no-op": {}, "op-int": {"op": 5},
                "op-list": {"op": ["delete"]}, "bad-utf8": b'{"op":"\xff"}', "nested-closed-1024": nest(1024, 1024),
                "nested-open-4000": nest(4000), "nested-open-1000": nest(1000)}),
    # step 5: the wire answer is the one a bad token gets; the audit id stays "-"
    *many(UNKNOWN_OP, {"unknown-op": {"op": "nope"}, "op-wrong-case": {"op": "Delete", "run": R}, "op-empty": {"op": ""},
                       "unknown-op-before-key-check": {"op": "nope", "x": 1, "run": 5}}),
    *[row("unknown-key-" + name, dict(body, extra="x"), bad(name)) for name, body in OPS.items()],
    *[row("missing-key-" + name, {"op": name}, bad(name)) for name in OPS],
    *many(bad("analyze"), {"directory-not-string": ana(directory=5), "optional-not-string": ana(repo=5),
                           "key-set-before-field-rules": ana(directory="relative", x="y")}, "analyze-"),
    row("value-not-string-delete", {"op": "delete", "run": 5}, bad("delete")), row("value-not-string-remove", {"op": "remove", "item": 5}, bad("remove")),
    row("another-ops-keys", dict(DEL, item=SENT), bad("delete")), row("key-set-before-store", dict(NO_RUN, x="y"), bad("delete")),
    *many(INV_A, {"directory": ana(directory="/tmp/" + SURR + "x"), "repo": ana(repo=SURR), "branch": ana(branch=SURR),
                  "worktree": ana(worktree=SURR), "before-every-other-rule": ana(directory="relative/x", branch=SURR)}, "surrogate-"),
    row("surrogate-run", {"op": "delete", "run": "a" + SURR}, bad("delete")), row("surrogate-item", {"op": "remove", "item": SURR}, bad("remove")),
    *many(INV_A, {"1025-bytes": ana(directory="/" + "a" * 1024), "513-chars-1025-bytes": ana(directory="/" + E2 * 512),
                  "control-before-realpath": ana(directory="relative\x01"), **{"control-%d" % ord(c): ana(directory=D + c) for c in "\x01\x7f\x00\n"}}, "dir-"),
    *many(exp(422, "relative_path", audit_id="analyze"), {"plain": ana(directory="relative/dir"), "dot": ana(directory="."),
                                                          "dollar-home-is-not-expanded": ana(directory="$HOME/proj")}, "relative-"),
    *many(exp(422, "no_such_directory", audit_id="analyze"), {"missing": ana(directory=D + "/missing"), "file": ana(directory="{home}/afile"),
          "link-to-file": ana(directory="{home}/link-to-file"), "dangling-link": ana(directory="{home}/dangling"),
          "tilde-expanded": ana(directory="~/missing"), "1024-bytes-pass-the-length-rule": ana(directory="/" + "a" * 1023)}, "dir-"),
    # repo, branch, worktree: byte counts and control characters, and `/` for repo only
    *many(INV_A, {"repo-256-bytes": ana(repo="r" * 256), "repo-128-chars-256-bytes": ana(repo=E2 * 128), "repo-slash": ana(repo="a/b"),
                  "repo-control": ana(repo="a\nb"), "branch-256-bytes": ana(branch="b" * 256), "branch-control": ana(branch="a\x01b"),
                  "worktree-1025-bytes": ana(worktree="w" * 1025), "worktree-513-chars-1026-bytes": ana(worktree=E2 * 513),
                  "worktree-control": ana(worktree="a\x01b")}),
    *[row("item-" + name, dict(RM, item=value), bad("remove")) for name, value in (
        ("uppercase", SENT.upper()), ("15-chars", SENT[:15]), ("17-chars", SENT + "0"), ("trailing-newline", SENT + "\n"),
        ("empty", ""), ("not-hex", "g" * 16), ("arabic-digits", "٠" * 16), ("leading-space", " " + SENT[1:]))],
    *[row("run-" + name, dict(DEL, run=value), bad("delete")) for name, value in (
        ("empty", ""), ("256-bytes", "x" * 256), ("128-chars-256-bytes", E2 * 128), ("control", "a\nb"))],
    row("run-reanalyze-empty", dict(REAN, run=""), bad("reanalyze")),
    row("run-delete-unknown", NO_RUN, NO_RUN_DEL), row("run-255-bytes-unknown", dict(DEL, run="x" * 255), NO_RUN_DEL),
    row("run-reanalyze-unknown", {"op": "reanalyze", "run": "no-such-run"}, exp(404, "no_such_run", audit_id="reanalyze")),
]


def assert_refused(ctx, path, body, overrides, expect, size=None):
    srv, (status, error, reason, audit_id) = ctx.srv, expect
    before, baseline = snapshot(srv.tree, ctx.home), len(srv.audit())
    traces, cmux = srv.stderr.count("Traceback"), srv.cmux_calls()
    assert send(ctx, path, body, overrides, size) == (status, json.dumps({"ok": False, "error": error}).encode())  # once, no echo
    lines = new_audit_lines(srv, baseline)
    assert [(l["outcome"], l["status"], l["id"], l["reason"]) for l in lines] == [("refused", str(status), audit_id, reason)]
    assert srv.stderr.count("Traceback") == traces
    assert snapshot(srv.tree, ctx.home) == before  # nothing created, written or changed: no queue file, no folder
    assert srv.cmux_calls() == cmux  # A5: no cmux process (the unit rows ban Popen; a git call would also touch the folders)


@pytest.mark.parametrize("body,overrides,expect,size", ROWS)
def test_post_ledger_refuses_at_the_right_step_once_with_one_audit_line_and_no_side_effect(shared, body, overrides, expect, size):
    """Catches a missing route (404 today), checks out of order, a double or no answer, a wrong audit id (- until step 5),
    echoed request content, or disk, git or cmux touched first. Falsifiers by row: a cap of 1024 or a character count,
    `re.match` with `$` or `\\d` for item, a store lookup before the shape check, an unknown key ignored, no UTF-8 rule.
    GUARD, passes today: the two host rows."""
    assert_refused(shared, "/ledger", body, overrides, expect, size)


@pytest.mark.parametrize("body,size,expect", [
    pytest.param(nest(1024), None, MAL, id="nested-open-1024"), pytest.param({"id": "clear"}, 1025, exp(413, "too_large"), id="1025-bytes"),
    pytest.param({"id": "nope"}, 1024, exp(403, "forbidden", "unknown_id"), id="1024-bytes-reach-the-id-check")])
def test_command_keeps_its_1024_cap_and_refuses_deep_nesting(shared, body, size, expect):
    """The nesting row catches a reader that catches only ValueError and UnicodeDecodeError (no reply today). The other
    two are GUARDS that pass today: /command's cap stays 1024, not /ledger's 4096."""
    assert_refused(shared, "/command", body, {}, expect, size)


@pytest.mark.parametrize("route", ["/command", "/ledger", "/ledger/status"])
@pytest.mark.parametrize("token", ["\xe9", E2.encode().decode("latin-1")], ids=["byte-e9", "utf8-e-acute"])
def test_a_non_ascii_token_is_the_collapsed_403_bad_token_on_three_routes(shared, route, token):
    """Catches a token check that hands the raw header to hmac.compare_digest: it raises TypeError, so the client gets no
    response and no audit line (the status route passes today: task 14 already refuses it).
    READING: the poll's audit id is `status` and the two POST routes' is `-`, which 3.6 and the A3 text imply."""
    srv = shared.srv
    before, baseline, traces = snapshot(srv.tree, shared.home), len(srv.audit()), srv.stderr.count("Traceback")
    if route == "/ledger/status":
        got = raw(srv, "GET", route, {"Host": "127.0.0.1:%d" % srv.port, TOKEN: token})
    else:
        got = send(shared, route, {"id": "clear"} if route == "/command" else DEL, {TOKEN: token})
    assert got == (403, b'{"ok": false, "error": "forbidden"}')
    lines = new_audit_lines(srv, baseline)
    assert [(l["outcome"], l["id"], l["reason"]) for l in lines] == [("refused", "status" if "status" in route else "-", "bad_token")]
    assert srv.stderr.count("Traceback") == traces and snapshot(srv.tree, shared.home) == before
    assert srv.get("/ledger/status", headers={TOKEN: srv.token}).status == 200  # the server is still serving


def test_an_unknown_op_carrying_a_newline_writes_exactly_one_audit_line_and_none_that_parses_as_accepted(shared):
    """A2's falsifier: a handler that writes the raw op into id= writes three lines, the middle one an accepted entry."""
    srv = shared.srv
    forged = "2026-11-13T00:00:00Z accepted id=delete surface=- sent=no status=200 reason=- path=- errno=-"
    before, baseline = len(srv.stderr.splitlines()), len(srv.audit())
    assert send(shared, "/ledger", {"op": "x\n%s\n" % forged}, {})[0] == 403
    new_audit_lines(srv, baseline)
    written = srv.stderr.splitlines()[before:]
    assert len(written) == 1 and harness.parse_audit(written[0])["id"] == "-"
    assert [l for l in map(harness.parse_audit, written) if l and l["outcome"] == "accepted"] == []


PASSING = [  # bodies that clear steps 1 to 7: (name, body, padded size)
    ("analyze-directory-only", ana(), None), ("analyze-optionals-empty", ana(repo="", branch="", worktree=""), None),
    ("analyze-optionals-at-limit", ana(repo="r" * 255, branch="feat/" + "b" * 250, worktree="/" + "w" * 1023), None),
    ("analyze-multibyte-branch-at-limit", ana(branch=E2 * 127 + "x"), None),
    ("analyze-tilde-folder", ana(directory="~/proj"), None), ("analyze-tilde-alone", ana(directory="~"), None),
    ("analyze-symlinked-folder", ana(directory="{home}/linkdir"), None), ("analyze-dot-dot", ana(directory="{dir}/../proj"), None),
    ("analyze-trailing-slash", ana(directory=D + "/"), None), ("reanalyze", REAN, None), ("delete", DEL, None),
    ("remove", RM, None), ("retry", RT, None), ("delete-at-4096-bytes", DEL, 4096), ("delete-at-1025-bytes", DEL, 1025),
]


@pytest.mark.parametrize("name,body,size", PASSING, ids=[name for name, _, _ in PASSING])
def test_a_request_that_clears_steps_1_to_7_is_not_refused_and_is_audited_with_its_op(tmp_path, launcher, name, body, size):
    """Catches a rule that is too strict (a valid request refused with a step 1-7 code) and a stub with no audit id.
    READING: the spec does not say what the op stub answers (task 17 replaces it), so only 'not a step 1-7 refusal' is
    asserted, plus 3.6's rule that every request writes one audit line and id= is the accepted op.
    NOTE for task 17: delete and reanalyze are real ops by then; those rows must move to a fake store."""
    ctx = make_ctx(tmp_path)
    serve(ctx, launcher(overrides={"HOME": ctx.home}))
    baseline = len(ctx.srv.audit())
    status, answer = send(ctx, "/ledger", body, {}, size)
    error = (json.loads(answer) if answer.startswith(b"{") else {}).get("error")
    assert status is not None and status not in STEP_STATUSES and error not in STEP_ERRORS
    assert [line["id"] for line in new_audit_lines(ctx.srv, baseline)] == [body["op"]]


@pytest.mark.parametrize("name,body,size", PASSING, ids=[name for name, _, _ in PASSING])
def test_check_ledger_post_returns_the_op_and_its_fields_and_starts_no_process(unit, name, body, size):
    """Catches the wrong return shape, a dropped field, a `directory` that is not canonicalized (os.path.realpath of the
    expanded value: what step 8 uses), or a git call while only validating.
    READING: `fields` holds each key the request carried, as strings; keys the request left out are not asserted."""
    op, fields, refusal = check(unit, body, size=size)
    assert (op, refusal) == (body["op"], None)
    for key, value in fill(body, unit).items():
        want = os.path.realpath(os.path.expanduser(value)) if key == "directory" else value
        assert key == "op" or fields[key] == want, key


@pytest.mark.parametrize("body,overrides,expect,size", ROWS)
def test_check_ledger_post_returns_the_refusal_tuple_and_starts_no_process(unit, body, overrides, expect, size):
    """The same rows at unit level. Catches a refusal that is not (status, error, reason, audit_id), a wrong audit id, or
    a step that raises instead of returning (a lone surrogate, a deep nest, a non-ASCII token)."""
    op, fields, refusal = check(unit, body, overrides, size)
    assert (op, fields, tuple(refusal)) == (None, None, expect)


def test_check_ledger_post_and_the_poll_use_the_one_shared_token_check(unit, monkeypatch):
    """Catches a second copy of the comparison: task 14's check_status_request carries one today (D47 retires it).
    READING: both look `token_ok` up on ledger_routes at call time."""
    import ledger_routes
    monkeypatch.setattr(ledger_routes, "token_ok", lambda presented, expected: True)
    assert check(unit, DEL, {TOKEN: X43})[2] is None
    headers = message(build_headers("127.0.0.1:%d" % UNIT_PORT, X43, 0, {}))
    assert ledger_routes.check_status_request(headers, unit.config) is None
    monkeypatch.setattr(ledger_routes, "token_ok", lambda presented, expected: False)
    assert tuple(check(unit, DEL)[2]) == BAD_TOKEN


@pytest.mark.parametrize("presented,want", [
    (UNIT_TOKEN, True), (X43, False), ("", False), (UNIT_TOKEN[:-1], False), (UNIT_TOKEN + "x", False),
    ("\xe9", False), (E2.encode().decode("latin-1"), False), (UNIT_TOKEN[:-1] + "\xe9", False)])
def test_token_ok_is_a_bool_and_compares_with_compare_digest_only_an_ascii_token(presented, want, monkeypatch):
    """Catches a truthy non-bool (`is`), a non-ASCII value reaching hmac.compare_digest (TypeError), an `==` that drops
    the constant-time compare, and a prefix or suffix match.
    READING: 'compares as today' means hmac.compare_digest is called, found on the hmac module at call time."""
    import hmac
    import ledger_routes
    calls, real = [], hmac.compare_digest
    monkeypatch.setattr(hmac, "compare_digest", lambda left, right: calls.append(left) or real(left, right))
    assert ledger_routes.token_ok(presented, UNIT_TOKEN) is want
    assert len(calls) == (1 if presented.isascii() else 0)


def reader(body, cap, **headers):
    import ledger_routes
    fields = dict({"Content-Length": str(len(body))}, **headers)
    rfile = io.BytesIO(body)
    return ledger_routes.read_json_body(message({k: v for k, v in fields.items() if v is not None}), rfile, cap), rfile


@pytest.mark.parametrize("body,cap,headers,want", [
    pytest.param(b'{"a": 1}', 1024, {}, {"a": 1}, id="object"),
    pytest.param(b"[1]", 1024, {}, [1], id="no-shape-check"),  # READING: the route keeps its own shape check (D47)
    pytest.param(b'{"a": "\\ud800"}', 1024, {}, {"a": SURR}, id="lone-surrogate-escape-is-accepted"),
    pytest.param(pad(b"{}", 1024), 1024, {}, {}, id="exactly-at-1024"),
    pytest.param(pad(b"{}", 1025), 1024, {}, (413, "too_large", "too_large"), id="1025-over-1024"),
    pytest.param(pad(b"{}", 4096), 4096, {}, {}, id="exactly-at-4096"),
    pytest.param(pad(b"{}", 1025), 4096, {}, {}, id="1025-under-4096: the cap is a parameter"),
    pytest.param(pad(b"{}", 4097), 4096, {}, (413, "too_large", "too_large"), id="4097-over-4096"),
    pytest.param(b"{}", 1024, {"Transfer-Encoding": "chunked"}, M3, id="transfer-encoding"),
    pytest.param(b"{}", 1024, {"Content-Length": None}, M3, id="no-length"),
    pytest.param(b"{}", 1024, {"Content-Length": "abc"}, M3, id="length-word"),
    pytest.param(b"{}", 1024, {"Content-Length": "-1"}, M3, id="length-negative"),
    pytest.param(b'{"a":"\xff"}', 1024, {}, M3, id="bad-utf8"), pytest.param(b"{", 1024, {}, M3, id="bad-json"),
    pytest.param(b"", 1024, {}, M3, id="empty"), pytest.param(nest(1024, 1024), 4096, {}, M3, id="recursion-error-closed"),
    pytest.param(nest(1024), 1024, {}, M3, id="recursion-error-open"),
    pytest.param(b"x" * 10000, 1024, {}, (413, "too_large", "too_large"), id="10000-bytes-never-read-in-full")])
def test_read_json_body_returns_the_object_or_a_status_error_reason_tuple(body, cap, headers, want):
    """Catches a reader that raises (RecursionError escapes a ValueError-only catch), a hard-coded cap, a body read in
    full before the cap applies (at most cap + 1 bytes are read), a lenient UTF-8 decode, or a refusal that is not the (status, error, reason) triple."""
    import ledger_routes
    got, rfile = reader(body, cap, **headers)
    assert (tuple(got) if isinstance(want, tuple) else got) == want
    assert rfile.tell() <= cap + 1 and ledger_routes.LEDGER_MAX_BODY_BYTES == 4096
