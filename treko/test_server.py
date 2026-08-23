"""Tests for server.py — the whole of this feature's trust boundary.

Covers the **wire contract** half of §Tasks 9 — acceptance criteria 6, 7, 9, 10, 11 and
12 of §Acceptance criteria in docs/features/tracking-feature-state.spec.md, plus the
controls §Tasks 9 pins because no criterion owns them: every manifest row served, the
`vendor-resources.js` mapping, `X-Content-Type-Options`, the four send-time outcomes,
`asset_unreadable`, the `reanalyze` timeout, and total `reason` coverage in both
directions.

**Criterion 14 and every startup abort are in `test_server_lifetime.py`.** §Tasks 9
names this file for criterion 14, so the pointer is here rather than left to a reader to
discover: the split is by launch-shape versus wire-shape, the seam the spec itself draws
when it calls bind failure "a launch property rather than a wire property", and it was
forced by this file passing the repo's 800-line ceiling.

**Criterion 13 is deliberately absent.** It is an agent-run browser enumeration owned by
task 14, not a pytest test, and a source-level stand-in for it is the substitution four
judge rounds removed. What lives here instead is the serve-side half criterion 13 cannot
reach — `vendor/babel.min.js` is on the manifest and is never requested on load, so the
table-driven manifest test below is the only thing that asserts it at all.

**A fake `cmux` proves the server's decision and never that keystrokes arrived.** Task
1's live spike closed the transport half (§Verification); what a fake still cannot tell
is a right surface ref from a resolvable wrong one, which is why criterion 12 asserts
the ref handed to `send` is byte-identical to the one the server was started with.

Runtime is dominated by three unavoidable waits: the idle-shutdown clause floors at 60s
by §Security and no override makes it cheaper, and the two `cmux` timeout paths cost 5s
each. Do not lower the floors — that deletes the control the test exists to prove.
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


# --------------------------------------------------------------------------
# the reason enum, from §Design 3 — the spec is authoritative, not the code
# --------------------------------------------------------------------------

# §"Audit log" lists these sixteen values plus `-` on success, and §Tasks 9 requires the
# check in both directions: every status row has a value, every value has a row. The
# mapping is transcribed from the status table, NOT read back out of server.py — a table
# derived from the implementation asserts only that the implementation equals itself.
REASON_STATUS = {
    "malformed": 400,
    "bad_token": 403,
    "unknown_id": 403,
    "origin_mismatch": 403,
    "host_mismatch": 403,
    "path_escape": 403,
    "not_found": 404,
    "method_not_allowed": 405,
    "unresolved_surface": 409,
    "too_large": 413,
    "unsupported_media_type": 415,
    "asset_unreadable": 500,
    "reanalyze_failed": 500,
    "send_failed": 502,
    "confirm_failed": 502,
    "confirm_timeout": 502,
}

# Every status the contract table carries. `204` (the OPTIONS preflight) and `200` are
# successes and log `reason=-`, so they are not part of the refusal enum.
CONTRACT_STATUSES = {400, 403, 404, 405, 409, 413, 415, 500, 502}

# Filled in as tests drive requests; the last test compares it against REASON_STATUS.
# A coverage claim assembled from what actually ran, never from a hand-written list.
OBSERVED_REASONS = set()


def assert_reason(srv, expected, **match):
    """Assert some request really produced this reason, and record that it was driven.

    Filters on the reason itself rather than taking the newest line for a status: several
    reasons share a status (three share `403`), so "the last 403" is whichever request ran
    last, not the one under test.
    """
    line = srv.last_audit(reason=expected, **match)
    assert int(line["status"]) == REASON_STATUS[expected], \
        "reason %s logged status %s; §Design 3 pairs it with %d" % (
            expected, line["status"], REASON_STATUS[expected])
    OBSERVED_REASONS.add(expected)
    return line


# --------------------------------------------------------------------------
# the static manifest — table-driven, so a row added later is covered unedited
# --------------------------------------------------------------------------


@pytest.mark.parametrize("relative", server.STATIC_MANIFEST)
def test_every_manifest_row_is_served_with_its_mapped_type(srv, relative):
    """§Tasks 9: every row served, with the type the fixed map assigns it.

    Table-driven over the manifest rather than a hand-listed subset, because criterion 13
    covers only what the browser requests *on load* — `vendor/babel.min.js` is vendored,
    on the manifest, and lazily loaded, so nothing else in this feature asserts it.
    """
    response = srv.get("/" + relative)
    assert response.status == 200, "%s: %d" % (relative, response.status)
    assert response.header("Content-Type") == server.EXTENSION_TYPES[Path(relative).suffix]
    assert response.body, "%s served an empty body" % relative


@pytest.mark.parametrize("relative", server.STATIC_MANIFEST)
def test_every_manifest_row_carries_nosniff(srv, relative):
    """A missing nosniff is invisible in a passing render; it only matters against a
    browser that would have sniffed, which is why criterion 13 cannot see it."""
    assert srv.get("/" + relative).header("X-Content-Type-Options") == "nosniff"


def test_manifest_is_covered_by_the_extension_map(srv):
    """The one-directional check the server aborts on, asserted as a property too."""
    unmapped = sorted({Path(p).suffix for p in server.STATIC_MANIFEST}
                      - set(server.EXTENSION_TYPES))
    assert unmapped == []


# --------------------------------------------------------------------------
# vendor-resources.js — serving a row is only half of what "vendored" means
# --------------------------------------------------------------------------


def cdn_urls_in_support(tree):
    """Every CDN URL `support.js` can request, derived from its own source.

    Derived rather than hand-listed so a fourth CDN script is covered without editing
    this test: find the identifiers passed to `cdnScriptFor(...)`, then resolve each to
    its string literal.
    """
    text = (tree / "support.js").read_text(errors="replace")
    names = set(re.findall(r"cdnScriptFor\(\s*([A-Za-z_][A-Za-z0-9_]*)", text))
    urls = {}
    for name in sorted(names):
        match = re.search(r'var\s+%s\s*=\s*"([^"]+)"' % re.escape(name), text)
        if match and match.group(1).startswith("http"):
            urls[name] = match.group(1)
    return urls


def resource_map(tree):
    text = (tree / "vendor-resources.js").read_text(errors="replace")
    match = re.search(r"window\.__resources\s*=\s*(\{.*?\})\s*;", text, re.S)
    assert match, "vendor-resources.js does not assign window.__resources"
    return json.loads(match.group(1))


def unmapped_cdn_urls(tree):
    """The problems, as strings. Empty means every CDN URL resolves to a manifest row."""
    mapping = resource_map(tree)
    problems = []
    for name, url in cdn_urls_in_support(tree).items():
        if url not in mapping:
            problems.append("%s (%s) is not a key of window.__resources" % (name, url))
            continue
        target = mapping[url]
        if target not in server.STATIC_MANIFEST:
            problems.append("%s maps to %r, which is not a manifest row" % (name, target))
        elif not (tree / target).exists():
            problems.append("%s maps to %r, which does not exist" % (name, target))
    return problems


def test_every_cdn_url_is_redirected_to_a_vendored_manifest_row(tree):
    """`window.__resources` fails *open* — a mistyped key silently goes back to unpkg.com,
    and criterion 8's file:// path has no CSP to catch it."""
    urls = cdn_urls_in_support(tree)
    # Guard the derivation itself: a regex that matched nothing would pass vacuously.
    assert len(urls) >= 3, "derived only %d CDN URLs from support.js: %r" % (len(urls), urls)
    assert unmapped_cdn_urls(tree) == []


def test_the_mapping_check_fails_when_a_key_is_mutated(tree):
    """Falsifier for the test above — a mapping test that reads both sides from the same
    source can pass while asserting nothing, so prove this one can fail."""
    path = tree / "vendor-resources.js"
    original = path.read_text()
    key = next(iter(resource_map(tree)))
    path.write_text(original.replace(key, key.replace("react", "raect", 1), 1))
    assert unmapped_cdn_urls(tree), "mutating a key left the check passing"


# --------------------------------------------------------------------------
# criterion 6 — one 403, byte-identical across all three causes
# --------------------------------------------------------------------------


FORBIDDEN_BODY = b'{"ok": false, "error": "forbidden"}'


def test_no_token_wrong_token_and_unknown_id_are_byte_identical_403s(srv):
    absent = srv.command("clear", token=False)
    wrong = srv.command("clear", token="x" * 43)
    unknown = srv.command("rm -rf /")

    for name, response in [("absent", absent), ("wrong", wrong), ("unknown id", unknown)]:
        assert response.status == 403, "%s token: %d" % (name, response.status)
        assert response.body == FORBIDDEN_BODY, "%s: %r" % (name, response.body)

    assert absent.body == wrong.body == unknown.body
    assert srv.cmux_calls("send") == [], "a refused command still reached the session"

    assert_reason(srv, "bad_token", status="403", id="-")
    assert_reason(srv, "unknown_id", status="403")


def test_a_foreign_host_header_is_refused_before_the_token_is_handed_out(srv):
    """The DNS-rebinding guard: GET / is the route that publishes the credential and has
    no Origin to check, because a top-level navigation sends none."""
    response = srv.get("/", host="tracker.example.com")
    assert response.status == 403
    assert response.body == FORBIDDEN_BODY
    assert b"tracker-token" not in response.body
    assert_reason(srv, "host_mismatch", status="403")


# --------------------------------------------------------------------------
# criterion 7 — a cross-origin page cannot reach the endpoint
# --------------------------------------------------------------------------


def test_preflight_emits_no_cors_headers_at_all(srv):
    response = srv.request("OPTIONS", "/command")
    assert response.status == 204
    allow = [k for k in response.headers if k.lower().startswith("access-control-allow")]
    assert allow == [], "server emitted CORS headers: %r" % allow


def test_a_cross_origin_post_is_refused_and_sends_nothing(srv):
    response = srv.command("clear", origin="https://evil.example")
    assert response.status == 403
    assert response.body == FORBIDDEN_BODY
    assert srv.cmux_calls("send") == []
    assert_reason(srv, "origin_mismatch", status="403")


def test_a_cross_site_fetch_metadata_header_is_refused(srv):
    response = srv.command("clear", extra={"Sec-Fetch-Site": "cross-site"})
    assert response.status == 403
    assert srv.cmux_calls("send") == []


# --------------------------------------------------------------------------
# criterion 9 — a surface that no longer resolves refuses before any send
# --------------------------------------------------------------------------


def test_an_absent_surface_is_a_409_and_no_keystroke_is_sent(launcher):
    """The refusal happens on the near side of the socket, so nothing reaches the focused
    tab — which holds whether or not `send` inherits `rename-tab`'s fall-through."""
    srv = launcher(tree_surface=harness.OTHER_SURFACE)
    response = srv.command("clear")

    assert response.status == 409
    assert response.json() == {"ok": False, "error": "unresolved_surface"}
    assert srv.cmux_calls("send") == [], "refused a surface and sent to it anyway"
    line = assert_reason(srv, "unresolved_surface", status="409")
    assert line["sent"] == "no"


# --------------------------------------------------------------------------
# criterion 10 — the token reaches the page and nowhere else
# --------------------------------------------------------------------------


def test_the_token_never_leaves_the_served_page(srv, tmp_path):
    """Every clause, because a test checking one passes while the feature is broken.

    The preconditions are the point: an accepted `reanalyze` is the only command that
    makes the token-holding process rewrite a file, and a refusal carrying the real token
    in a header is the request most likely to be logged verbatim.
    """
    index = srv.get("/")
    token = srv.token

    reanalyze = srv.command("reanalyze", timeout=120)
    assert reanalyze.status == 200, "reanalyze precondition failed: %s\n%s" % (
        reanalyze.body, srv.stderr)
    refused = srv.command("not-an-allowlisted-id")
    assert refused.status == 403

    raw = token.encode()

    # (1) every file under the served tree, including the just-rewritten store
    for path in sorted(srv.tree.rglob("*")):
        if path.is_file() and not path.is_symlink():
            assert raw not in path.read_bytes(), "token written to %s" % path

    # (2) the server's own command line
    cmdline = subprocess.run(["ps", "-p", str(srv.proc.pid), "-o", "command="],
                             capture_output=True, text=True, check=True).stdout
    assert cmdline.strip(), "ps reported no command line for the server"
    assert token not in cmdline

    # (3) the environment of every child it spawns. server.py passes no `env=` to any
    # subprocess, so a child's environment is the server's verbatim — asserted, not assumed.
    source = (srv.tree / "server.py").read_text()
    assert "env=" not in source, "server.py now passes env= somewhere; widen this check"
    children = srv.cmux_calls()
    assert children, "no child was spawned, so this clause proved nothing"
    for call in children:
        for key, value in call["env"].items():
            assert token not in value, "token reached a child in %s" % key

    # (4) the captured stderr for the whole test — §Out of scope bans a file, an env var
    # and argv, and a log stream is none of those three.
    assert token not in srv.stderr

    # (5) present exactly once in the served page, in the meta tag, with no-store and CSP
    body = index.body.decode()
    assert body.count(token) == 1
    assert '<meta name="tracker-token" content="%s">' % token in body
    assert index.header("Cache-Control") == "no-store"
    assert index.header("Content-Security-Policy") == server.CSP
    assert "frame-ancestors 'none'" in index.header("Content-Security-Policy")


# --------------------------------------------------------------------------
# criterion 11 — outside the tree is 403, inside but off-manifest is 404
# --------------------------------------------------------------------------


ESCAPING_PATHS = [
    "/../../rules/core-conduct.md",
    "/..%2f..%2frules%2fcore-conduct.md",
    "/%2e%2e/%2e%2e/rules/core-conduct.md",
    "//etc/passwd",
    "/./../../CLAUDE.md",
]

# Real files inside treko/ that are not manifest rows. The copy keeps them so the
# manifest is what refuses, not the filesystem.
OFF_MANIFEST_PATHS = [
    "/store.py",
    "/analyze.py",
    "/tracker-data.json",
    "/test_server.py",
    "/server.py",
    "/favicon.ico",
]


@pytest.mark.parametrize("path", ESCAPING_PATHS)
def test_a_path_leaving_the_tree_is_refused_and_leaks_nothing(srv, path):
    response = srv.get(path)
    assert response.status in (403, 404), "%s: %d" % (path, response.status)
    assert b"Core Conduct" not in response.body
    assert b"root:" not in response.body


@pytest.mark.parametrize("path", OFF_MANIFEST_PATHS)
def test_an_off_manifest_path_inside_the_tree_is_404(srv, path):
    """`404` not `403`, matching the wire contract: an unlisted path is indistinguishable
    from a nonexistent one, which is what stops the server confirming what exists."""
    response = srv.get(path)
    assert response.status == 404
    assert response.json() == {"ok": False, "error": "not_found"}
    assert b"import" not in response.body


def test_a_traversal_probe_is_audited_with_a_named_reason(srv):
    """§"Audit log" claims refusals are the only evidence a hostile page probed the
    endpoint; logged as `-`, that evidence does not exist."""
    srv.get("/../../rules/core-conduct.md")
    assert_reason(srv, "not_found", status="404")


def test_a_manifest_row_that_symlinks_out_of_the_tree_is_403(launcher, tree, tmp_path):
    """The value that had no row for four rounds: a manifest member is servable, so the
    manifest check passes and only the resolved-path check stands between a planted
    symlink and the file it points at."""
    secret = tmp_path / "outside-the-tree.txt"
    secret.write_text("SENTINEL-OUTSIDE-SERVE-ROOT")
    target = tree / "tracker-data.js"
    target.unlink()
    target.symlink_to(secret)

    srv = launcher(tree=tree)
    response = srv.get("/tracker-data.js")

    assert response.status == 403
    assert response.body == FORBIDDEN_BODY
    assert b"SENTINEL" not in response.body
    line = assert_reason(srv, "path_escape", status="403")
    assert line["path"] == "tracker-data.js"


# --------------------------------------------------------------------------
# criterion 12 — what success looks like, asserted at the invocation
# --------------------------------------------------------------------------


@pytest.mark.parametrize("command_id", sorted(server.SEND_COMMANDS))
def test_an_allowlisted_command_invokes_send_once_at_the_bound_surface(launcher, command_id):
    """A `200` proves the server decided to send, not that anything was sent — and a fake
    cannot tell a right ref from a resolvable wrong one, so assert the ref itself."""
    srv = launcher()
    response = srv.command(command_id)

    assert response.status == 200
    assert response.json() == {"ok": True, "id": command_id}

    sends = srv.cmux_calls("send")
    assert len(sends) == 1, "expected one send, got %d" % len(sends)
    argv = sends[0]["argv"]
    assert argv[1] == "--surface"
    assert argv[2] == harness.FAKE_SURFACE, "sent to %r, bound to %r" % (
        argv[2], harness.FAKE_SURFACE)
    assert argv[-1] == server.SEND_COMMANDS[command_id]

    line = srv.last_audit(status="200", id=command_id)
    assert line["outcome"] == "accepted"
    assert line["sent"] == "yes"
    assert line["surface"] == harness.FAKE_SURFACE


def test_reanalyze_succeeds_without_invoking_cmux_at_all(srv):
    """The one exception, asserted separately: `reanalyze` types nothing."""
    before = len(srv.cmux_calls())
    response = srv.command("reanalyze", timeout=120)

    assert response.status == 200, "%s\n%s" % (response.body, srv.stderr)
    assert response.json() == {"ok": True, "id": "reanalyze"}
    assert len(srv.cmux_calls()) == before, "reanalyze invoked cmux"

    line = srv.last_audit(status="200", id="reanalyze")
    assert line["sent"] == "no"


# --------------------------------------------------------------------------
# the four send-time outcomes
# --------------------------------------------------------------------------


def test_an_unrunnable_confirmation_refuses_and_sends_nothing(launcher):
    """`cmux tree` exits non-zero: unconfirmable is refused, never assumed fine."""
    srv = launcher(overrides={"FAKE_TREE": "fail"})
    response = srv.command("clear")

    assert response.status == 502
    assert response.json() == {"ok": False, "error": "send_failed"}
    assert srv.cmux_calls("send") == []
    line = assert_reason(srv, "confirm_failed", status="502")
    assert line["sent"] == "no"


def test_a_timed_out_confirmation_is_a_distinct_audit_reason(launcher):
    """The sub-case task 8's split exists for: on the wire it is the same 502, and the
    audit reason is the only place an operator can tell "cmux hung" from "cmux errored"."""
    srv = launcher(overrides={"FAKE_TREE": "hang"})
    response = srv.command("clear", timeout=60)

    assert response.status == 502
    assert response.json() == {"ok": False, "error": "send_failed"}
    assert srv.cmux_calls("send") == []
    line = assert_reason(srv, "confirm_timeout", status="502")
    assert line["sent"] == "no"


@pytest.mark.parametrize("mode", ["fail", "hang"])
def test_a_failed_send_after_a_good_confirmation_is_sent_unknown(launcher, mode):
    """The worst failure this feature has: the surface was confirmed, `send` *was*
    invoked, and the server genuinely cannot say whether keystrokes landed. Logging
    `sent=no` here would assert that nothing was typed."""
    srv = launcher(overrides={"FAKE_SEND": mode})
    response = srv.command("clear", timeout=60)

    assert response.status == 502
    assert response.json() == {"ok": False, "error": "send_failed"}
    assert len(srv.cmux_calls("send")) == 1, "send was not invoked, so `unknown` is untested"
    line = assert_reason(srv, "send_failed", status="502")
    assert line["sent"] == "unknown", "resolved an unknowable outcome to %r" % line["sent"]


# --------------------------------------------------------------------------
# the remaining contract rows: malformed, too_large, media type, method
# --------------------------------------------------------------------------


MALFORMED_BODIES = [
    pytest.param("[]", id="not-an-object"),
    pytest.param('{"id": 1}', id="id-not-a-string"),
    pytest.param("{}", id="id-missing"),
    pytest.param('{"id": "clear", "args": "x"}', id="extra-key"),
    pytest.param("not json at all", id="not-json"),
]


@pytest.mark.parametrize("body", MALFORMED_BODIES)
def test_a_malformed_body_is_400_and_sends_nothing(srv, body):
    response = srv.command("clear", body=body)
    assert response.status == 400
    assert response.json() == {"ok": False, "error": "malformed"}
    assert srv.cmux_calls("send") == []
    assert_reason(srv, "malformed", status="400")


def test_a_body_over_1_kib_is_413(srv):
    oversized = json.dumps({"id": "clear", "pad": "x" * (server.MAX_BODY_BYTES + 64)})
    response = srv.command("clear", body=oversized)
    assert response.status == 413
    assert response.json() == {"ok": False, "error": "too_large"}
    assert_reason(srv, "too_large", status="413")


def test_a_non_json_content_type_is_415(srv):
    response = srv.command("clear", content_type="text/plain")
    assert response.status == 415
    assert response.json() == {"ok": False, "error": "unsupported_media_type"}
    assert_reason(srv, "unsupported_media_type", status="415")


METHOD_NOT_ALLOWED = [
    ("GET", "/command"),
    ("POST", "/"),
    ("POST", "/support.js"),
    ("OPTIONS", "/"),
    ("PUT", "/"),
    ("DELETE", "/command"),
]


@pytest.mark.parametrize("method,path", METHOD_NOT_ALLOWED)
def test_a_disallowed_method_path_pair_is_405(srv, method, path):
    response = srv.request(method, path, headers={"Content-Length": "0"})
    assert response.status == 405, "%s %s: %d" % (method, path, response.status)
    assert response.json() == {"ok": False, "error": "method_not_allowed"}
    assert_reason(srv, "method_not_allowed", status="405")


def test_a_post_to_an_unknown_path_is_404_not_405(srv):
    """The 404 row takes precedence: the path failing to exist settles the request before
    its method does."""
    response = srv.request("POST", "/nope", headers={"Content-Length": "0"})
    assert response.status == 404


# --------------------------------------------------------------------------
# asset_unreadable — a manifest row that is on the list and cannot be read
# --------------------------------------------------------------------------


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores the permission bits this drives")
def test_an_unreadable_manifest_row_is_500_naming_path_and_errno(launcher, tree):
    """Arrived in round 5 with nothing exercising it. The body must carry no filesystem
    detail; the audit line must carry the *manifest* path, never the serving root."""
    (tree / "support.js").chmod(0o000)
    srv = launcher(tree=tree)
    try:
        response = srv.get("/support.js")
    finally:
        (tree / "support.js").chmod(0o644)

    assert response.status == 500
    assert response.json() == {"ok": False, "error": "asset_unreadable"}
    assert str(tree).encode() not in response.body
    assert b"/" not in response.body

    line = assert_reason(srv, "asset_unreadable", status="500")
    assert line["outcome"] == "failed"
    assert line["path"] == "support.js"
    assert line["errno"] == "EACCES"


def test_tracker_data_absent_is_404_not_500(launcher, tree):
    """The stated exception, and it is the normal first-run path: a 500 here would break
    the empty state instead of rendering it."""
    (tree / "tracker-data.js").unlink()
    srv = launcher(tree=tree)
    response = srv.get("/tracker-data.js")

    assert response.status == 404
    assert response.json() == {"ok": False, "error": "not_found"}


# --------------------------------------------------------------------------
# the reanalyze timeout — a timeout never made to fire is not a timeout
# --------------------------------------------------------------------------


def test_a_hanging_analyzer_times_out_and_leaves_the_store_intact(launcher, tree):
    analyzer = tree / "analyze.py"
    analyzer.write_text(harness.HANGING_ANALYZER)
    store_path = tree / "tracker-data.js"
    before = store_path.read_bytes()

    srv = launcher(tree=tree, overrides={"TREKO_ANALYZE_SECS": "5"})
    started = time.monotonic()
    response = srv.command("reanalyze", timeout=60)
    elapsed = time.monotonic() - started

    assert response.status == 500
    assert response.json() == {"ok": False, "error": "reanalyze_failed"}
    assert elapsed < harness.HANG_SECS, "the request outlived the analyzer's own bound"
    assert store_path.read_bytes() == before, "a failed reanalyze rewrote the store"
    line = assert_reason(srv, "reanalyze_failed", status="500")
    assert line["outcome"] == "failed"


# --------------------------------------------------------------------------
# reason coverage, in both directions
# --------------------------------------------------------------------------


def reasons_emitted_in_source():
    """Every reason value server.py can emit — all three shapes, not just the literals.

    §Tasks 9 supplies a two-grep derivation and warns it undercounts silently. It does:
    it returns 14 pairs against a 16-value enum, because `_run_send` passes
    `CONFIRM_REFUSAL_REASONS[state]` — a *computed* reason, invisible to a grep for string
    literals. That is the third emitting shape the spec predicted but could not name, and
    it is read here from the mapping itself rather than from the text of the call.
    """
    source = (harness.REAL_TREE / "server.py").read_text()
    literal = set(re.findall(r'_fail\(\s*\d+,\s*"[a-z_]+",\s*"([a-z_]+)"', source))
    audited = set(re.findall(r'audit\(\s*"[a-z]+",\s*\d+,\s*reason="([a-z_]+)"', source))
    return literal | audited | set(server.CONFIRM_REFUSAL_REASONS.values())


def test_the_enum_and_the_status_table_cover_each_other():
    """Every row has a value, every value has a row — the check §Design 3 asks for after
    four rounds in which a value with no row and rows with no value both shipped."""
    assert set(REASON_STATUS.values()) == CONTRACT_STATUSES
    assert reasons_emitted_in_source() == set(REASON_STATUS), (
        "source and §Design 3 disagree: only in source %r, only in the spec %r"
        % (sorted(reasons_emitted_in_source() - set(REASON_STATUS)),
           sorted(set(REASON_STATUS) - reasons_emitted_in_source())))


def test_zz_every_reason_value_was_driven_by_a_real_request(request):
    """Coverage assembled from what actually ran. "Reachable by reading the source" is
    exactly what this refuses to accept: a value only a code path mentions is
    indistinguishable, on inspection, from one the server can never emit.
    """
    if request.config.option.keyword or request.config.option.markexpr:
        pytest.skip("partial run: coverage is only meaningful over the whole module")
    missing = sorted(set(REASON_STATUS) - OBSERVED_REASONS)
    assert missing == [], "no request in this suite produced: %s" % ", ".join(missing)
