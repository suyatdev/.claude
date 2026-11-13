"""Task 14 (docs/features/treko-ledger.spec.md sections 3.1 to 3.3 and 3.6; decision D46): the Ledger page and
its status answer, beside the unchanged board. Owns A1 and A7. Not here: POST /ledger's ops (tasks 16, 17), A8, task 19.

Modules under test are imported inside each test, so one missing name fails only that test. Each test names the
wrong shortcut it catches. Servers are real `server.py` processes from the harness, stopped at teardown. The token
goes only into request headers, never into an assertion message.
"""

import http.client
import json
import os
import re
import sys
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import server  # noqa: E402  (path shim above must run first)
import server_harness as harness  # noqa: E402

# API ASSUMED (D46): ledger_routes.build_status(ledger, runner, store_dir) -> dict (runner needs only .progress();
# runs come from <store_dir>/tracker-data.js); ledger_routes.check_status_request(headers, config) -> None or the
# audit reason; server.ControlHandler._serve_page(file_name), called by _serve_index; server.check_index_injectable
# (root) checks both page files; server.build_config(...) has "ledger" and "runner" keys, None by default.

TOKEN = "X-Tracker-Token"
LEDGER_FILE, BOARD_FILE = "Ledger.dc.html", "Treko.dc.html"
PAGES = ("/ledger", "/ledger/status")
FORBIDDEN = b'{"ok": false, "error": "forbidden"}'
UNIT_TOKEN = "unit-test-token-" + "a" * 27  # a made-up value, not any server's
MARKER_PAGE = "<!doctype html>\n<html>\n<head>\n<title>x</title>\n</head>\n<body>LEDGER-MARKER</body>\n</html>\n"
NO_HEAD = "<html><body>no head</body></html>"
SETTLE_SECS, AUDIT_WAIT_SECS, EXIT_WAIT_SECS = 0.2, 5, 10
REQUEST = {"directory": "/srv/dev", "repo": "memsearch", "branch": "", "worktree": ""}
DETAIL = {"stage": "branches", "repo": "memsearch", "exit": 1, "timedOut": False, "errno": None}


def page_bytes(root, name, token):
    """What today's one substitution makes of a page file (server.py `_serve_index`)."""
    meta = ('<meta name="tracker-token" content="%s">\n<meta name="tracker-channel" content="%s">'
            % (token, server.CHANNEL_OK))
    text = (Path(root) / name).read_text(encoding="utf-8")
    return text.replace("<head>", "<head>\n" + meta, 1).encode()


def new_audit_lines(srv, baseline, at_least):
    """Audit lines since `baseline`, once `at_least` exist (bounded wait) and a stray extra one has had time to land."""
    deadline = time.monotonic() + AUDIT_WAIT_SECS
    while len(srv.audit()) < baseline + at_least and time.monotonic() < deadline:
        time.sleep(0.02)
    time.sleep(SETTLE_SECS)  # the line is written after the reply
    return srv.audit()[baseline:]


def poll(srv, token=None, **kwargs):
    """GET /ledger/status; token None sends the real one, False sends none."""
    headers = dict(kwargs.pop("headers", {}))
    if token is not False:
        headers[TOKEN] = srv.token if token is None else token
    return srv.get("/ledger/status", headers=headers, **kwargs)


@pytest.fixture
def ledger_srv(tree, launcher):
    """A running server whose Ledger page is a file the test wrote, so no test depends on the skeleton."""
    (tree / LEDGER_FILE).write_text(MARKER_PAGE, encoding="utf-8")
    srv = launcher(tree=tree)
    assert srv.token  # read now: fetching it later would add an audit line (GET /) inside a test's window
    return srv


def headers_of(**fields):
    """Case-insensitive like a real request's headers; `Sec_Fetch_Site` is spelled Sec-Fetch-Site."""
    message = http.client.HTTPMessage()
    for key, value in fields.items():
        message[key.replace("_", "-")] = value
    return message


def unit_config():
    return server.build_config(None, UNIT_TOKEN, Path("/repo"), 8422, 60, Path("/store"), server.CHANNEL_OK)


def test_ledger_page_is_its_own_file_with_both_metas_the_csp_and_the_headers(ledger_srv):
    """Catches serving the board's file at /ledger, a page without the token or a header, an injection anywhere but
    right after the first <head>, a query string that changes the route (3.1), or a silent accepted page (only the
    status poll is exempt from 'one line per request')."""
    baseline = len(ledger_srv.audit())
    got = ledger_srv.get("/ledger")
    assert got.status == 200 and got.header("Content-Type").startswith("text/html")
    assert got.body == page_bytes(ledger_srv.tree, LEDGER_FILE, ledger_srv.token)  # both metas, one substitution
    assert got.header("Cache-Control") == "no-store"
    assert got.header("Content-Security-Policy") == server.CSP
    assert got.header("X-Content-Type-Options") == "nosniff"
    assert ledger_srv.get("/ledger?x=1").body == got.body
    lines = new_audit_lines(ledger_srv, baseline, at_least=2)
    assert [(line["outcome"], line["status"], line["id"]) for line in lines] == [("accepted", "200", "-")] * 2


def test_ledger_page_with_a_foreign_host_is_refused(ledger_srv):
    """GUARD, passes today (the Host check precedes routing). Catches a /ledger route that skips it."""
    got = ledger_srv.get("/ledger", host="evil.test:1")
    assert (got.status, got.body) == (403, FORBIDDEN)
    assert ledger_srv.last_audit(reason="host_mismatch")["outcome"] == "refused"


def test_get_slash_is_the_board_byte_for_byte_and_headers_as_today(ledger_srv):
    """GUARD, passes today. Catches moving the board or changing its substitution when the pages share a function."""
    got = ledger_srv.get("/")
    assert got.body == page_bytes(ledger_srv.tree, BOARD_FILE, ledger_srv.token)
    assert got.header("Cache-Control") == "no-store"
    assert got.header("Content-Security-Policy") == server.CSP
    assert got.header("X-Content-Type-Options") == "nosniff"
    assert b"LEDGER-MARKER" not in got.body


@pytest.mark.parametrize("how", ["missing", "mode0"])
def test_an_unreadable_ledger_file_after_startup_is_500_asset_unreadable(ledger_srv, how):
    """Catches a Ledger route that lets the read error escape (no reply) or answers 404 for a file that exists."""
    path = ledger_srv.tree / LEDGER_FILE
    if how == "mode0" and os.geteuid() == 0:
        pytest.skip("root ignores the permission bits this drives")
    path.unlink() if how == "missing" else path.chmod(0o000)
    try:
        got = ledger_srv.get("/ledger")
        assert (got.status, got.json()) == (500, {"ok": False, "error": "asset_unreadable"})
        line = ledger_srv.last_audit(reason="asset_unreadable")
        assert (line["outcome"], line["status"]) == ("failed", "500")
        # READING: as GET / does (server.py `_serve_index`), the audit line's path= names the file.
        assert line["path"] == LEDGER_FILE
        assert ledger_srv.get("/").status == 200  # the board does not depend on the Ledger file
    finally:
        if path.exists():
            path.chmod(0o644)


def write_root(tmp_path, board=MARKER_PAGE, ledger=MARKER_PAGE):
    root = tmp_path / "root"
    root.mkdir()
    for name, text in ((BOARD_FILE, board), (LEDGER_FILE, ledger)):
        if text is not None:
            (root / name).write_text(text)
    return root


@pytest.mark.parametrize("board,ledger,name,expect", [
    (MARKER_PAGE, NO_HEAD, LEDGER_FILE, "no <head>"), (MARKER_PAGE, None, LEDGER_FILE, "cannot read"),
    ("<html></html>", MARKER_PAGE, BOARD_FILE, "no <head>")],  # last row GUARD, passes today: the board's check stays
    ids=["ledger-no-head", "ledger-missing", "board-no-head"])
def test_check_index_injectable_aborts_naming_the_bad_page_file(tmp_path, board, ledger, name, expect):
    """Catches a startup check that looks at the board only: a bad Ledger file would start unauthenticated."""
    with pytest.raises(server.StartupAbort) as raised:
        server.check_index_injectable(write_root(tmp_path, board=board, ledger=ledger))
    assert name in str(raised.value) and expect in str(raised.value)


@pytest.mark.parametrize("how", ["no-head", "missing"])
def test_the_server_exits_2_naming_the_ledger_file_and_serves_nothing(tree, launcher, how):
    """Catches a startup check that is only unit-deep: main() must turn it into exit 2 before the bind."""
    path = tree / LEDGER_FILE
    path.unlink(missing_ok=True) if how == "missing" else path.write_text(NO_HEAD)
    srv = launcher(tree=tree, wait=False)
    assert srv.wait_for_exit(EXIT_WAIT_SECS) == 2
    assert LEDGER_FILE in srv.stderr
    assert harness.refuses_connection(srv.port)


def test_the_shipped_skeleton_has_a_head_and_only_servable_local_assets():
    """Catches a skeleton that would trip the startup check, or load assets the manifest does not serve.
    READING: 'the board's asset tags' means: at least one local src/href, and each is a STATIC_MANIFEST row."""
    text = (harness.REAL_TREE / LEDGER_FILE).read_text(encoding="utf-8")
    assert "<head>" in text
    refs = [ref[2:] if ref.startswith("./") else ref
            for ref in re.findall(r'(?:src|href)="([^":]+)"', text) if not ref.startswith(("#", "/"))]
    assert refs and all(ref in server.STATIC_MANIFEST for ref in refs)


def test_build_config_gains_ledger_and_runner_defaulting_to_none():
    """Catches a config without the keys (a KeyError in the status route) or with a live default (shared state)."""
    config = unit_config()
    assert "ledger" in config and "runner" in config and config["ledger"] is None and config["runner"] is None


def test_serve_index_is_serve_page_with_the_board_file():
    """Catches a second copy of the serving code: the board must go through the function the Ledger uses.
    READING: _serve_index calls self._serve_page(INDEX_FILE), the file name as the one positional argument."""
    calls = []
    server.ControlHandler._serve_index(SimpleNamespace(_serve_page=lambda *a, **k: calls.append((a, k))))
    assert calls == [((BOARD_FILE,), {})]


@pytest.mark.parametrize("path", PAGES)
def test_options_is_204_with_no_cors_header_and_one_accepted_audit_line(ledger_srv, path):
    """Catches a 405 for OPTIONS (the table says 204) and any Access-Control-* header (the server emits none).
    READING: OPTIONS is not a status poll, so its accepted 204 is audited like /command's (3.6 exempts polls only)."""
    baseline = len(ledger_srv.audit())
    got = ledger_srv.request("OPTIONS", path)
    assert (got.status, got.body) == (204, b"")
    assert not [key for key in got.headers if key.lower().startswith("access-control-")]
    lines = new_audit_lines(ledger_srv, baseline, at_least=1)
    assert [(line["outcome"], line["status"]) for line in lines] == [("accepted", "204")]


@pytest.mark.parametrize("method,path", [(m, p) for m in ("PUT", "DELETE", "PATCH") for p in PAGES]
                         + [("POST", "/ledger/status")])
def test_any_other_method_is_405(ledger_srv, method, path):
    """Catches a new route answering 404 or 501 for a method the table refuses. The PUT, DELETE and PATCH rows are
    GUARDS that pass today; POST /ledger/status is not (it is 404 until the route exists). POST /ledger is task 16's."""
    got = ledger_srv.request(method, path, headers={TOKEN: ledger_srv.token}, body="{}")
    assert (got.status, got.json()) == (405, {"ok": False, "error": "method_not_allowed"})


def test_the_rest_of_the_table_is_as_before(ledger_srv):
    """GUARD, passes today. Catches prefix routing (/ledger/x stays 404) and an OPTIONS or POST that widens past 405."""
    for path in ("/ledger/", "/ledger/status/", "/ledger/other"):
        assert ledger_srv.get(path).status == 404, path
    assert ledger_srv.request("POST", "/nowhere", body="{}").status == 404
    odd = (("OPTIONS", "/"), ("OPTIONS", "/x"), ("POST", "/"))
    assert [ledger_srv.request(m, p, body="{}").status for m, p in odd] == [405] * 3


def test_an_accepted_poll_is_json_with_the_headers_and_the_payload_shape(ledger_srv):
    """Catches a status route that is missing, mistyped, cacheable, lacks a key of section 3.3, or requires Origin."""
    import ledger_state
    import store
    got = poll(ledger_srv)
    assert got.status == 200 and got.header("Content-Type").split(";")[0] == "application/json"
    assert got.header("Cache-Control") == "no-store" and got.header("X-Content-Type-Options") == "nosniff"
    payload = got.json()
    assert set(payload) == {"ok", "storeDir", "queue", "runs", "runsError"}
    assert payload["ok"] is True and payload["queue"] == [] and payload["runsError"] is None
    expected = ledger_state.run_rows(store.read_store(ledger_srv.tree / "tracker-data.js")["runs"], [])
    assert payload["runs"] == expected and expected  # the sample store has runs, so [] could not pass
    assert payload["storeDir"].endswith("/treko")
    # Origin and Sec-Fetch-Site are judged only when present; a same-origin fetch's values must pass.
    origin = "http://127.0.0.1:%d" % ledger_srv.port
    assert poll(ledger_srv, headers={"Origin": origin, "Sec-Fetch-Site": "same-origin"}).status == 200


def test_accepted_polls_write_no_audit_line(ledger_srv):
    """Catches auditing every poll (up to 1,800 lines an hour that bury the state-changing ones): O3.
    A sentinel 404 after the polls must be the only new line."""
    baseline = len(ledger_srv.audit())
    assert [poll(ledger_srv).status for _ in range(3)] == [200, 200, 200]
    assert ledger_srv.get("/no-such-path").status == 404
    lines = new_audit_lines(ledger_srv, baseline, at_least=1)
    assert [line["reason"] for line in lines] == ["not_found"]


REFUSALS = [  # name, foreign Host?, extra headers, token (None = the real one, False = none), audit reason
    ("host", True, {}, None, "host_mismatch"),
    ("origin", False, {"Origin": "http://evil.test"}, None, "origin_mismatch"),
    ("fetch-site", False, {"Sec-Fetch-Site": "cross-site"}, None, "origin_mismatch"),
    ("no-token", False, {}, False, "bad_token"),
    ("wrong-token", False, {}, "x" * 43, "bad_token"),
    ("byte-e9", False, {}, "\xe9", "bad_token"),
    ("utf8-e-acute", False, {}, "é".encode("utf-8").decode("latin-1"), "bad_token"),
    ("host-then-origin-then-token", True, {"Origin": "http://evil.test"}, False, "host_mismatch"),
    ("origin-then-token", False, {"Origin": "http://evil.test"}, "x" * 43, "origin_mismatch"),
]


@pytest.mark.parametrize("name,foreign,extra,token,reason", REFUSALS, ids=[row[0] for row in REFUSALS])
def test_every_refusal_is_the_one_collapsed_403_with_exactly_one_id_status_audit_line(
        ledger_srv, name, foreign, extra, token, reason):
    """Catches a refusal that tells the caller which check failed (an oracle), writes no line (a non-ASCII token
    crashed the handler before U10), writes two, or checks in the wrong order.
    READING: a foreign-Host poll is still 'the poll', so its line carries id=status like the others (D46 puts the
    Host check inside check_status_request)."""
    baseline = len(ledger_srv.audit())
    got = poll(ledger_srv, token=token, headers=extra, host="evil.test:1" if foreign else None)
    assert (got.status, got.body) == (403, FORBIDDEN) and got.header("Content-Type").split(";")[0] == "application/json"
    lines = new_audit_lines(ledger_srv, baseline, at_least=1)
    assert [(l["id"], l["outcome"], l["status"], l["reason"]) for l in lines] == [("status", "refused", "403", reason)]


def check(**fields):
    import ledger_routes
    return ledger_routes.check_status_request(headers_of(**fields), unit_config())


def good(**more):
    return dict({"Host": "127.0.0.1:8422", "X_Tracker_Token": UNIT_TOKEN}, **more)


def test_check_status_request_is_none_when_everything_passes():
    """Catches a check that requires Origin or Sec-Fetch-Site: each is judged only when present."""
    assert check(**good()) is None
    assert check(**good(Origin="http://127.0.0.1:8422", Sec_Fetch_Site="same-origin")) is None


@pytest.mark.parametrize("fields,reason", [
    (good(Host="evil.test:1"), "host_mismatch"),
    (good(Origin="http://evil.test"), "origin_mismatch"),
    (good(Sec_Fetch_Site="cross-site"), "origin_mismatch"),
    ({"Host": "127.0.0.1:8422"}, "bad_token"),
    (good(X_Tracker_Token="wrong"), "bad_token"),
    (good(X_Tracker_Token="\xe9"), "bad_token"),
])
def test_check_status_request_returns_the_audit_reason(fields, reason):
    """Catches a check that returns a boolean, the wire word 'forbidden', or raises on a non-ASCII token
    (hmac.compare_digest raises TypeError on one: U10)."""
    assert check(**fields) == reason


def test_check_status_request_checks_host_then_origin_then_token():
    """Catches the checks in any other order: the reason is the first failing check, never a later one."""
    assert check(Host="evil.test:1", Origin="http://evil.test", Sec_Fetch_Site="cross-site") == "host_mismatch"
    assert check(**good(Origin="http://evil.test", X_Tracker_Token="wrong")) == "origin_mismatch"
    assert check(**good(Sec_Fetch_Site="cross-site", X_Tracker_Token="wrong")) == "origin_mismatch"


def item(item_id, state, minute, **more):
    return dict({"item": item_id, "state": state, "queuedAt": "2026-11-03T09:%02d:00Z" % minute,
                 "request": dict(REQUEST), "run": "r" + item_id, "error": None, "detail": None}, **more)


def status(tmp_path, queue=(), stage=None, hidden=(), store_text=None, store_dir=None):
    import ledger_routes
    import ledger_state
    if store_text is not None:
        (tmp_path / "tracker-data.js").write_text(store_text)
    state = {"version": 1, "queue": list(queue), "hidden": list(hidden), "requests": {}}
    runner = SimpleNamespace(progress=lambda: None if stage is None else dict(stage))
    return ledger_routes.build_status(ledger_state.Ledger(state=state), runner, store_dir or tmp_path)


def write_runs(tmp_path, *run_ids):
    import store
    data = store.new_store()
    for number, run_id in enumerate(run_ids):
        data = store.upsert_run(data, {"id": run_id, "name": "run " + run_id, "dir": "~/dev", "branches": [],
                                       "features": [], "analyzedAt": "2026-11-03T09:%02d:00Z" % number})
    store.write_store(tmp_path / "tracker-data.js", data)
    return data["runs"]


def test_build_status_collapses_the_home_folder_in_store_dir(tmp_path, monkeypatch):
    """Catches a raw absolute path (D8 shows the user a path; analyze._home_collapse turns home into ~)."""
    home = tmp_path / "home"
    (home / ".local/state/treko").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    assert status(tmp_path, store_dir=home / ".local/state/treko")["storeDir"] == "~/.local/state/treko"
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()
    assert status(tmp_path, store_dir=elsewhere)["storeDir"] == str(elsewhere)


def test_the_payload_has_exactly_the_keys_each_queue_state_allows(tmp_path):
    """Catches error on a non-failed item, detail on a waiting or running one, a missing detail on an interrupted
    one, or a private key (request, hidden) leaking into a plain-JSON payload (section 3.3).
    READING: queue order is the stored order; label is ledger_state.queue_label of the request."""
    import ledger_state
    queue = [item("a1", "running", 0), item("b2", "waiting", 1),
             item("c3", "failed", 2, error="analysis_failed", detail=dict(DETAIL)),
             item("d4", "interrupted", 3, detail=dict(DETAIL))]
    payload = status(tmp_path, queue=queue, stage={"done": 3, "total": 11, "label": "x: reading cards"})
    got, base = payload["queue"], {"item", "state", "label", "queuedAt", "run"}
    assert set(payload) == {"ok", "storeDir", "queue", "runs", "runsError"} and payload["ok"] is True
    assert json.loads(json.dumps(payload)) == payload
    assert [row["item"] for row in got] == ["a1", "b2", "c3", "d4"]
    assert [set(row) for row in got] == [base | {"stage"}, base, base | {"error", "detail"}, base | {"detail"}]
    assert got[0]["label"] == ledger_state.queue_label("/srv/dev", "memsearch", "", "")
    assert (got[2]["error"], got[2]["detail"]) == ("analysis_failed", DETAIL) and got[3]["detail"] == DETAIL


def test_stage_is_on_the_running_item_only_and_is_the_runners_record(tmp_path):
    """Catches stage on the first item, on every item, on a waiting item when nothing runs, or a dropped null total."""
    stage = {"done": 3, "total": 11, "label": "memsearch (1 of 2): reading cards"}
    queue = [item("b2", "waiting", 1), item("a1", "running", 0)]
    got = status(tmp_path, queue=queue, stage=stage)["queue"]
    assert [("stage" in row) for row in got] == [False, True] and got[1]["stage"] == stage
    idle = status(tmp_path, queue=queue[:1], stage=stage)["queue"]  # a stale record, nothing running
    assert all("stage" not in row for row in idle)
    scanning = {"done": 0, "total": None, "label": "scanning ~/dev"}  # E4: 'total' is present and None, not dropped
    assert status(tmp_path, queue=queue[1:], stage=scanning)["queue"][0]["stage"] == scanning


def test_runs_are_task_9s_rows_without_the_hidden_ones(tmp_path):
    """Catches a runs list built here instead of by ledger_state.run_rows, a hidden run shown, or a first run
    (no tracker-data.js yet) treated as store_unreadable."""
    import ledger_state
    assert (status(tmp_path)["runs"], status(tmp_path)["runsError"]) == ([], None)
    runs = write_runs(tmp_path, "r1", "r2", "r3")
    got = status(tmp_path, hidden=["r2"])
    assert got["runs"] == ledger_state.run_rows(runs, ["r2"]) and got["runsError"] is None
    assert {row["id"] for row in got["runs"]} == {"r1", "r3"}


def test_an_unparseable_store_gives_null_runs_and_store_unreadable_but_keeps_the_queue(tmp_path):
    """Catches a status that raises on a corrupt store, or drops the queue so a running job vanishes."""
    stage = {"done": 1, "total": 7, "label": "x"}
    got = status(tmp_path, queue=[item("a1", "running", 0)], stage=stage, store_text="this is not a store")
    assert got["runs"] is None and got["runsError"] == "store_unreadable" and got["ok"] is True
    assert [row["item"] for row in got["queue"]] == ["a1"] and got["queue"][0]["stage"] == stage
