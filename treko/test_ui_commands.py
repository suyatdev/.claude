"""Criterion 15 — what the page does with every row of §Design 3's failure table.

This is the one suite that can reach any of it. Every other criterion in this card is a
property of the server; these are properties of the *page*, so no request-level assertion
touches them. A button that posts, takes a `403` and quietly returns to looking idle
satisfies every server-side test here while being precisely the failure the audit log
exists to catch.

**Why the handler is sliced out of an HTML file.** It cannot live in a `.js` file of its
own: the servable set is a closed sixteen-row list pinned in both `server.py` and the spec
half, so adding a row is a spec change, and it would reopen criterion 13. A plain inline
`<script>` is refused by the CSP, which carries no `'unsafe-inline'` for scripts. That
leaves the `text/x-dc` block, which survives because the browser never executes it. So the
handler is fenced between two markers there and this module cuts it out and loads it in
`node` — the same shape as `test_store.py`'s `load_via_node`, which had a real `.js` file
to point at and this one does not.

**A node-less host must report criterion 15 as NOT VERIFIED.** Unlike criterion 5, there is
no unguarded Python sibling that covers part of it: the behaviour is browser JS end to end.
A green run of this file's siblings implies nothing about it (§Tasks 10, task 13).
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import channel  # noqa: E402
import server  # noqa: E402
import server_harness as harness  # noqa: E402

NODE = shutil.which("node")
HTML = Path(__file__).resolve().parent / "Treko.dc.html"

# Every row of §Design 3's "What the page does with a failure" table, by the outcome name
# the handler is required to resolve it to. The mapping is the contract; `test_zz_...`
# below refuses to pass until a real drive has produced each one.
ROW_OUTCOMES = {
    "success",          # 200
    "stale_token",      # 403 forbidden
    "session_ended",    # 409 unresolved_surface
    "send_unknown",     # 502 send_failed
    "analysis_failed",  # 500 reanalyze_failed
    "page_bug",         # 400 / 413 / 415
    "unexpected",       # an `error` code absent from the table
    "server_gone",      # fetch rejects
    "no_channel",       # 503 no_channel (a degraded server, D5)
}
OBSERVED_OUTCOMES = set()

# The two rows where the page must stop offering the button, because a retry cannot work.
TERMINAL_OUTCOMES = {"session_ended", "server_gone"}

ANALYZED_AT = "2026-08-12T04:05:06Z"

# An analyzer that fails immediately. The suite already proves the *timeout* path
# (test_server.py); here the only thing that matters is that the server answers 500, and a
# non-zero exit gets there without spending the timeout's five seconds.
FAILING_ANALYZER = "#!/usr/bin/env python3\nimport sys\nsys.exit(3)\n"

NODE_BRIDGE = r"""
const fs = require('fs');
const os = require('os');
const path = require('path');

const START = '// <<< tracker-command-handler: node-loadable slice begins >>>';
const END = '// <<< tracker-command-handler: node-loadable slice ends >>>';

function loadHandler(htmlPath) {
  const html = fs.readFileSync(htmlPath, 'utf8');
  const starts = html.split(START).length - 1;
  const ends = html.split(END).length - 1;
  if (starts !== 1 || ends !== 1) {
    throw new Error('expected exactly one marker pair in ' + htmlPath +
                    ', found ' + starts + ' start / ' + ends + ' end');
  }
  const body = html.slice(html.indexOf(START) + START.length, html.indexOf(END));
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'tracker-cmd-')),
                         'tracker-commands.js');
  fs.writeFileSync(file, body);
  const loaded = require(file);
  if (!loaded || typeof loaded.applyCommand !== 'function') {
    throw new Error('the sliced region exported no applyCommand()');
  }
  return loaded;
}

// A canned response, for the rows a correctly behaving server cannot produce: 400/413/415
// are the page's own bugs, and an `error` code outside the table is by definition one the
// server never emits. Everything else is driven against a real server.
function stubFetch(spec) {
  return function () {
    return Promise.resolve({
      ok: spec.status === 200,
      status: spec.status,
      json: function () { return Promise.resolve(spec.body); },
    });
  };
}

// The fence's pure functions, called directly. Each one is guarded so a missing export
// reads as a null the test can name, rather than one TypeError failing every test at once.
function probe(handler, spec) {
  const fn = function (name) { return typeof handler[name] === 'function'; };
  const live = {};
  for (const hasToken of [true, false]) {
    for (const channelOk of [true, false]) {
      live[hasToken + ',' + channelOk] =
        fn('liveIds') ? handler.liveIds(hasToken, channelOk) : null;
    }
  }
  const reasons = {};
  for (const token of spec.tokens) {
    reasons[token] = fn('channelReason') ? handler.channelReason(token) : null;
  }
  return {
    ids: handler.IDS,
    localIds: handler.LOCAL_IDS === undefined ? null : handler.LOCAL_IDS,
    sendIds: handler.SEND_IDS === undefined ? null : handler.SEND_IDS,
    channelReasons: handler.CHANNEL_REASONS === undefined ? null : handler.CHANNEL_REASONS,
    healthyIsIds: fn('liveIds') ? handler.liveIds(true, true) === handler.IDS : null,
    live: live,
    reasons: reasons,
  };
}

async function main() {
  const spec = JSON.parse(process.argv[1]);
  const handler = loadHandler(spec.htmlPath);
  if (spec.mode === 'probe') {
    process.stdout.write(JSON.stringify(probe(handler, spec)));
    return;
  }
  const before = handler.idleView(spec.analyzedAt);
  const fetchImpl = spec.stub ? stubFetch(spec.stub) : fetch;
  const after = await handler.applyCommand(before, {
    fetchImpl: fetchImpl,
    url: spec.url,
    token: spec.token,
    id: spec.id,
  });
  process.stdout.write(JSON.stringify({
    before: before,
    after: after,
    messages: handler.MESSAGES,
    ids: handler.IDS,
    copyText: handler.COPY_TEXT,
  }));
}

main().catch(function (err) {
  process.stderr.write(String((err && err.stack) || err) + '\n');
  process.exit(1);
});
"""


def drive(*, url="http://127.0.0.1:1/command", token="t", id="clear", stub=None,
          analyzed_at=ANALYZED_AT):
    """Run one row through the real handler in a real JS engine, and hand back the views."""
    spec = json.dumps({
        "htmlPath": str(HTML),
        "url": url,
        "token": token,
        "id": id,
        "stub": stub,
        "analyzedAt": analyzed_at,
    })
    proc = subprocess.run(
        [NODE, "-e", NODE_BRIDGE, "--", spec],
        capture_output=True, text=True, timeout=60,
    )
    if proc.returncode != 0:
        raise AssertionError("node rejected the handler:\n%s" % proc.stderr)
    return json.loads(proc.stdout)


def probe_fence(tokens=()):
    """Call the fence's pure functions directly, off the same sliced region `drive` loads."""
    spec = json.dumps({"htmlPath": str(HTML), "mode": "probe", "tokens": list(tokens)})
    proc = subprocess.run(
        [NODE, "-e", NODE_BRIDGE, "--", spec],
        capture_output=True, text=True, timeout=60,
    )
    if proc.returncode != 0:
        raise AssertionError("node rejected the handler:\n%s" % proc.stderr)
    return json.loads(proc.stdout)


def assert_row(result, outcome):
    """Both halves of criterion 15: the row's own visible state, and — the clause that
    carries the criterion — that it never *also* reaches the 200 success state.

    Two assertions, not one. A handler that shows an error and then falls through into the
    success path passes the first and fails the second, which is the whole point.
    """
    after, messages = result["after"], result["messages"]
    assert after["outcome"] == outcome, "row resolved to %r" % after["outcome"]
    assert after["message"] == messages[outcome], "row showed the wrong fixed string"

    if outcome != "success":
        assert after["outcome"] != "success"
        assert after["message"] != messages["success"], "an error row also showed success"
        assert after["shouldReload"] is False, "a failed command still refreshed the view"

    # Rule 1: no response leaves the button looking like nothing happened.
    assert after["message"] != "", "the row left the page silent"
    assert after["outcome"] != "idle", "the row never left the resting state"

    OBSERVED_OUTCOMES.add(outcome)


def command_url(srv):
    return "http://127.0.0.1:%d/command" % srv.port


# --------------------------------------------------------------------------
# the marker fence itself — the thing every other test here depends on


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_the_handler_slice_is_fenced_exactly_once_and_loads_standalone():
    """The slice must carry no page dependency — no React, no DCLogic, no `document`.

    Asserted by loading it in `node`, where none of those exist: an accidental reference
    to any of them is a ReferenceError here and a broken button in the browser, and the
    browser is where nobody is watching.
    """
    result = drive(stub={"status": 200, "body": {"ok": True, "id": "clear"}})
    assert result["ids"] == ["clear", "handoff", "reanalyze"], "the allowlist drifted"
    assert set(result["copyText"]) == set(result["ids"]), "a command has no copyable text"
    for id_, text in result["copyText"].items():
        assert text.strip() != "", "%s offers empty copyable text" % id_


# --------------------------------------------------------------------------
# the rows a real server produces


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_200_reaches_the_success_state(srv):
    result = drive(url=command_url(srv), token=srv.token, id="clear")
    assert_row(result, "success")


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_403_says_the_token_is_stale_and_still_offers_a_retry(srv):
    """The normal case, not an anomaly: the token lives one server lifetime, so any page
    left open across a restart lands here. It is the one error row that stays recoverable.
    """
    result = drive(url=command_url(srv), token="not-the-real-token", id="clear")
    assert_row(result, "stale_token")
    assert result["after"]["offersButton"] is True, "a reloadable page lost its button"


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_409_stops_offering_the_button_and_offers_the_copyable_text(launcher):
    # The real token, deliberately: a wrong one would collapse into the 403 row and this
    # test would pass while never once reaching the 409 it exists for.
    srv = launcher(tree_surface=harness.OTHER_SURFACE)
    result = drive(url=command_url(srv), token=srv.token, id="clear")
    assert_row(result, "session_ended")
    assert result["after"]["offersButton"] is False, "offered a retry that cannot work"
    assert result["after"]["offersCopyText"] is True, "no fallback for a dead channel"


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_502_resolves_to_neither_sent_nor_failed(launcher):
    """`sent=unknown` must never read as `sent` — and equally never as `failed`. The
    keystroke may well have landed; a page that picks either word is asserting something
    the server explicitly does not know.
    """
    srv = launcher(overrides={"FAKE_SEND": "fail"})
    result = drive(url=command_url(srv), token=srv.token, id="clear")
    assert_row(result, "send_unknown")

    shown = result["after"]["message"].lower()
    assert "sent" not in shown, "resolved an unknown send to 'sent'"
    assert "failed" not in shown, "resolved an unknown send to 'failed'"


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_500_leaves_the_displayed_analyzed_at_byte_identical(launcher, tree):
    """The stale timestamp is the only on-screen signal that the data is old. Refreshing it
    on a failed re-analysis is exactly how a failure comes to look like a success.
    """
    (tree / "analyze.py").write_text(FAILING_ANALYZER)
    srv = launcher(tree=tree)
    result = drive(url=command_url(srv), token=srv.token, id="reanalyze")
    assert_row(result, "analysis_failed")

    before = result["before"]["analyzedAt"].encode("utf-8")
    after = result["after"]["analyzedAt"].encode("utf-8")
    assert after == before, "a failed re-analysis refreshed the timestamp"


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_a_stopped_server_is_a_terminal_state_with_the_copyable_text(srv):
    """Driven by really stopping the server, never by mocking a rejection. A server exiting
    under an open page is the normal end of every session — idle timeout or parent death —
    not an edge case, and a mocked rejection would not prove the real one is caught.
    """
    url, token = command_url(srv), srv.token
    srv.stop()
    assert harness.refuses_connection(srv.port), "the port was still accepting connections"

    result = drive(url=url, token=token, id="clear")
    assert_row(result, "server_gone")
    assert result["after"]["offersButton"] is False, "offered a button with no server"
    assert result["after"]["offersCopyText"] is True, "no fallback once the server is gone"


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_503_no_channel_keeps_the_button_for_what_still_works(launcher):
    """A degraded server — launched with no surface, never a stubbed 503 — refuses a send.

    The row is deliberately not terminal (D5): terminality is applied to every id, so a
    terminal `no_channel` would withdraw Re-analyze in the one mode where it still works.
    """
    srv = launcher(surface="")
    result = drive(url=command_url(srv), token=srv.token, id="clear")
    assert_row(result, "no_channel")
    assert result["after"]["offersButton"] is True, "no_channel withdrew every button"
    assert result["after"]["offersCopyText"] is False


# --------------------------------------------------------------------------
# D4 / D5 — the fence's pure functions, called off the node bridge

# Transcribed from §D5's table, not read back out of the page: a table derived from the
# implementation asserts only that the implementation equals itself.
CHANNEL_REASON_TEXT = {
    "surface_unset": "Launched outside cmux, so there is no session to type into.",
    "probe_timeout": "cmux did not answer within 5s — the control channel may be wedged.",
    "probe_failed": ("This surface is not a terminal; an agent-session surface has no "
                     "control channel."),
    "cmux_unrunnable": "cmux could not be run on this host.",
}
CHANNEL_REASON_FALLBACK = "No control channel."

# Pinned, never invented by the test. The assertion is whole-token absence from the
# returned string, so a probe like `control` or `No` — itself a substring of the fallback
# — would fail a correct implementation. This token shares `channel` with the fallback;
# that is fine, because what is asserted is that the *whole* token is absent.
PROBE_TOKEN = "zz_not_a_channel_token"

REASON_TOKENS = {member.value for member in channel.Reason}


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_live_ids_resolve_for_all_four_token_and_channel_combinations():
    """`[]` with no token; all three with a token and a channel; Re-analyze alone when the
    channel is down — every value other than `'ok'` reaches the fence as `channelOk=false`.
    """
    result = probe_fence()
    ids = ["clear", "handoff", "reanalyze"]
    assert result["live"] == {
        "true,true": ids,
        "true,false": ["reanalyze"],
        "false,true": [],
        "false,false": [],
    }


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_a_healthy_channel_is_never_handed_the_degraded_button_set():
    """Criterion 10's second half: channel-ok resolves to the allowlist itself."""
    assert probe_fence()["healthyIsIds"] is True


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_the_page_partition_matches_the_servers():
    """Both sides read, neither trusted: a hand-written list would pin the copy, not the
    agreement between them."""
    result = probe_fence()
    assert result["localIds"] is not None and result["sendIds"] is not None, \
        "the fence exports no LOCAL_IDS / SEND_IDS"
    assert set(result["localIds"]) == set(server.LOCAL_COMMANDS)
    assert set(result["sendIds"]) == set(server.SEND_COMMANDS)


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_the_channel_reason_table_keys_match_the_reason_enum():
    """A renamed member would otherwise fall through to the fallback — a legal, designed
    outcome — and the page would quietly stop saying which of four things broke."""
    reasons = probe_fence()["channelReasons"]
    assert reasons is not None, "the fence exports no CHANNEL_REASONS"
    assert set(reasons) == REASON_TOKENS


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_each_reason_token_maps_to_its_own_text():
    reasons = probe_fence(sorted(REASON_TOKENS))["reasons"]
    assert reasons == CHANNEL_REASON_TEXT


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_an_unrecognised_channel_token_falls_to_the_fixed_string():
    """Criterion 7's security clause. A real server only ever emits one of five tokens, so
    this direct call is the only place an unrecognised one can be exercised at all."""
    shown = probe_fence([PROBE_TOKEN])["reasons"][PROBE_TOKEN]
    assert shown == CHANNEL_REASON_FALLBACK
    assert PROBE_TOKEN not in shown, "the attribute's own text reached the page"


# --------------------------------------------------------------------------
# the rows no correctly behaving server can produce


@pytest.mark.skipif(NODE is None, reason="node not installed")
@pytest.mark.parametrize("status,error", [(400, "malformed"),
                                          (413, "too_large"),
                                          (415, "unsupported_media_type")])
def test_the_pages_own_bugs_reach_a_visible_unexpected_state(status, error):
    """The page cannot produce these by following the contract, so reaching one means the
    wiring is wrong — which is a thing to say on screen, not to swallow.
    """
    result = drive(stub={"status": status, "body": {"ok": False, "error": error}})
    assert_row(result, "page_bug")


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_an_unknown_error_code_is_never_rendered_back():
    """Rule 2's falsifier. A handler that renders the server's text passes every other row
    in this file and fails only this one: the code is fixed-string-mapped, and a code with
    no mapping shows the page's own "unexpected" string rather than the server's bytes.
    """
    code = "zzz_never_defined_by_this_server"
    result = drive(stub={"status": 418, "body": {"ok": False, "error": code}})
    assert_row(result, "unexpected")

    # Not just the message field — no part of the resulting view may carry it. A code that
    # leaks through any other key is the same gadget by a different route.
    assert code not in json.dumps(result["after"]), "the server's text reached the page"


@pytest.mark.skipif(NODE is None, reason="node not installed")
@pytest.mark.parametrize("code", ["constructor", "toString", "__proto__"])
def test_an_error_code_borrowed_from_the_prototype_is_still_unknown(code):
    """The lookup of `error` against the row table must not walk the prototype chain.

    A bare `TABLE[code]` is truthy for "constructor" and "toString", so a body carrying one
    resolves to a row that was never written down — the page would show a real message for
    a code the server cannot emit. Only the guard makes these reach the unknown path, so
    the guard gets an assertion rather than a comment.
    """
    result = drive(stub={"status": 418, "body": {"ok": False, "error": code}})
    assert_row(result, "unexpected")


# --------------------------------------------------------------------------


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_zz_every_table_row_was_driven_by_a_real_response(request):
    """Coverage assembled from what actually ran, never from reading the handler. A row
    the handler merely mentions is indistinguishable, on inspection, from one it can never
    reach — and this card's recurring failure is exactly that assertion written backwards.
    """
    if request.config.option.keyword or request.config.option.markexpr:
        pytest.skip("partial run: coverage is only meaningful over the whole module")
    missing = sorted(ROW_OUTCOMES - OBSERVED_OUTCOMES)
    assert missing == [], "no response in this suite produced: %s" % ", ".join(missing)
