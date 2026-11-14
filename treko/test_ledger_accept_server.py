"""Task 17, part 2 (spec 3.4 step 8, 3.5, 5.6; G7, A2 rows, A5; D49): the ops route (`handle_op`, reanalyze, G7) in process,
then the same codes as real HTTP requests to a real `server.py`. Helpers and the A5 autouse fixture come from
test_ledger_accept.py. Server rows swap the scan script inside the harness's private tree copy: its `branch` field names
the outcome to print, and `hang`, `crash`, `garbage` misbehave. The token goes only into headers.
API ASSUMED: as test_ledger_accept.py. NOT drivable over HTTP: `launch_failed` (the scan runs on the server's own
interpreter, so nothing cheap stops it starting); it is driven in process in test_ledger_accept.py."""

import json
import os
import shutil
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ledger_routes  # noqa: E402
import ledger_state  # noqa: E402
import server_harness as harness  # noqa: E402
import store  # noqa: E402
from test_ledger_accept import (HEX16, SCAN_SECS, cmux_log, fake_scan, make_ledger, many, queued, registry,  # noqa: E402,F401
                                req, rid, snap, untouched, writes)  # cmux_log is autouse (A5), writes a fixture
from test_ledger_scan_more import add_worktree, git, make_repo, world  # noqa: E402,F401  (`world` is a fixture)
from test_ledger_scan_narrow import write_card  # noqa: E402

HTTP_SCAN = '''import json, sys, time
request = json.load(sys.stdin)
mode = request["branch"]
if mode == "hang":
    time.sleep(60)
elif mode == "crash":
    sys.exit(3)
elif mode == "garbage":
    print("not json")
else:
    print(json.dumps({"outcome": mode or "ok", "families": [], "questions": [], "missed": {}}))
'''
SAMPLE_RUNS = [run["id"] for run in store.read_store(harness.REAL_TREE / "tracker-data.sample.js")["runs"]]
TOKEN = "X-Tracker-Token"


# ------------------------------------------------------------------------- reanalyze, G7, and handle_op (in process)

class Runner:
    """Counts wake() calls and records the queue each one saw."""

    def __init__(self, ledger):
        self.ledger, self.saw = ledger, []

    def wake(self):
        self.saw.append(self.ledger.snapshot()["queue"])


def config(ledger, runner, program, reg=None):
    return {"ledger": ledger, "registry": reg or registry(), "scan_secs": SCAN_SECS, "runner": runner, "scan_program": program}


def real_registry(world):
    return registry(dict(world.env, CMUX_BIN=os.environ["CMUX_BIN"], FAKE_CMUX_LOG=os.environ["FAKE_CMUX_LOG"]))


def test_reanalyze_request_returns_the_recorded_request_or_none(tmp_path):
    """Catches a lookup by item id, a copy that differs, and a KeyError for a run with no record (that case is task 28)."""
    request = req("/work/a", "r", "b", "w")
    ledger = make_ledger(tmp_path, requests={rid(request): request})
    assert ledger_routes.reanalyze_request(ledger, rid(request)) == request
    assert ledger_routes.reanalyze_request(ledger, "r0123456789abcdef") is None


def test_handle_op_analyze_queues_wakes_the_runner_once_after_the_item_exists_and_fills_absent_fields(tmp_path):
    """Catches no wake (the item sits until restart), two wakes, a wake before the enqueue (the runner then finds nothing),
    and optional fields left out of the stored request (the run id would then differ from the form's)."""
    ledger = make_ledger(tmp_path)
    runner, directory = Runner(ledger), str(tmp_path)
    status, body = ledger_routes.handle_op("analyze", {"directory": directory}, config(ledger, runner, fake_scan(tmp_path, "ok")))
    [item] = ledger.snapshot()["queue"]
    assert status == 200 and body == {"ok": True, "op": "analyze", "item": item["item"], "started": True}
    assert item["request"] == req(directory) and [[row["item"] for row in queue] for queue in runner.saw] == [[item["item"]]]


@pytest.mark.parametrize("fake,items,status,code", [
    ("exit-3", [], 500, "scan_failed"), ("ok", [queued(req())], 409, "already_queued"), ("ok", many(20), 409, "queue_full")])
def test_a_refused_op_does_not_wake_the_runner(tmp_path, fake, items, status, code):
    """Catches a wake placed before the outcome is known (it would start a runner for an item never queued)."""
    ledger = make_ledger(tmp_path, items)
    runner = Runner(ledger)
    assert ledger_routes.handle_op("analyze", {"directory": "/work/a"}, config(ledger, runner, fake_scan(tmp_path, fake))) == (status, code, code)
    assert runner.saw == []


@pytest.mark.parametrize("op,fields", [("remove", {"item": "0" * 16}), ("retry", {"item": "0" * 16}), ("delete", {"run": "r1"})])
def test_remove_retry_and_delete_still_answer_the_stub_until_task_18(tmp_path, op, fields):
    """Catches a handle_op that sends every op through the analyze path, or answers 200 for the ops task 18 owns."""
    ledger = make_ledger(tmp_path, [queued(req())])
    before, runner = snap(ledger, tmp_path), Runner(ledger)
    assert ledger_routes.handle_op(op, fields, config(ledger, runner, fake_scan(tmp_path, "ok"))) == ledger_routes.OP_STUB_REFUSAL
    assert snap(ledger, tmp_path) == before and runner.saw == []


def test_reanalyze_goes_through_the_analyze_path_and_answers_op_reanalyze(tmp_path):
    """Catches a body that says analyze, a request replaced by the form's, and a missing wake."""
    request = req(str(tmp_path), branch="feat-x")
    ledger = make_ledger(tmp_path, requests={rid(request): request})
    runner = Runner(ledger)
    status, body = ledger_routes.handle_op("reanalyze", {"run": rid(request)}, config(ledger, runner, fake_scan(tmp_path, "ok")))
    [item] = ledger.snapshot()["queue"]
    assert (status, body) == (200, {"ok": True, "op": "reanalyze", "item": item["item"], "started": True})
    assert item["request"] == request and len(runner.saw) == 1


def test_reanalyze_of_a_run_already_waiting_is_already_queued(tmp_path):
    """G7: the same path as analyze. Catches a reanalyze that skips the queue checks."""
    request = req(str(tmp_path))
    ledger = make_ledger(tmp_path, [queued(request)], {rid(request): request})
    before, runner = snap(ledger, tmp_path), Runner(ledger)
    answer = ledger_routes.handle_op("reanalyze", {"run": rid(request)}, config(ledger, runner, fake_scan(tmp_path, "ok")))
    assert answer == (409, "already_queued", "already_queued") and snap(ledger, tmp_path) == before and runner.saw == []


def test_g7_a_recorded_directory_that_was_deleted_answers_422_no_such_directory_and_writes_nothing(tmp_path, writes):
    """G7. The fake scan says `ok`, so the refusal must come from the route's own directory rule (spec 3.4: the field
    rules run again), not from the scan. Catches a reanalyze that trusts the recorded directory."""
    gone = tmp_path / "gone"
    gone.mkdir()
    request = req(str(gone))
    ledger = make_ledger(tmp_path, requests={rid(request): request})
    before, runner = snap(ledger, tmp_path), Runner(ledger)
    shutil.rmtree(gone)
    answer = ledger_routes.handle_op("reanalyze", {"run": rid(request)}, config(ledger, runner, fake_scan(tmp_path, "ok")))
    assert answer == (422, "no_such_directory", "no_such_directory") and runner.saw == []
    untouched(ledger, tmp_path, before, writes)


def test_g7_a_run_narrowed_to_a_removed_worktree_answers_422_no_such_worktree_and_writes_nothing(world, tmp_path, writes):
    """G7, real git. First proves the same request is accepted while the worktree exists (so the later refusal is not a
    fixture mistake), then `git worktree remove`s it. Catches a reanalyze that queues a stale narrowing."""
    proj = make_repo(world, world.tree / "proj")
    write_card(proj, "card-gone", branch="feat-gone")
    gone = add_worktree(world, proj, world.base / "wts" / "gone", "feat-gone")
    request, reg = req(str(proj), worktree=str(gone)), real_registry(world)
    probe = ledger_state.Ledger(state={"version": 1, "queue": [], "hidden": [], "requests": {rid(request): request}})
    assert ledger_routes.handle_op("reanalyze", {"run": rid(request)}, config(probe, Runner(probe), None, reg))[0] == 200
    git(world, "-C", str(proj), "worktree", "remove", str(gone))
    ledger = make_ledger(tmp_path, requests={rid(request): request})
    before, runner = snap(ledger, tmp_path), Runner(ledger)
    answer = ledger_routes.handle_op("reanalyze", {"run": rid(request)}, config(ledger, runner, None, reg))
    assert answer == (422, "no_such_worktree", "no_such_worktree") and runner.saw == []
    untouched(ledger, tmp_path, before, writes)


# ----------------------------------------------------------------------------------- real HTTP rows (A2, A5)

def ledger_doc(items=(), requests=None):
    return {"version": ledger_state.LEDGER_VERSION, "queue": list(items), "hidden": [], "requests": dict(requests or {})}


def boot_server(folder, seed=None, scan_secs=None):
    """`seed(proj)` returns the ledger.json the server starts with; `proj` is the canonical folder the request names."""
    proj = folder / "proj"
    proj.mkdir(exist_ok=True)
    tree = harness.build_tree(folder)
    (tree / "ledger_scan.py").write_text(HTTP_SCAN)
    if seed is not None:
        (tree / ledger_state.LEDGER_FILE).write_text(json.dumps(seed(str(proj.resolve()))))
    srv = harness.launch(folder, tree=tree, overrides={"TREKO_SCAN_SECS": str(scan_secs)} if scan_secs else None)
    srv.token  # fetched now: a later GET / would add an audit line inside a test's window
    srv.baseline, srv.proj = srv.cmux_calls(), str(proj.resolve())  # the startup probe is the server's own cmux use
    return srv


def finish(srv):
    srv.stop()
    assert srv.cmux_calls() == srv.baseline, "A5: a /ledger request made a cmux call"


@pytest.fixture
def boot(tmp_path):
    started = []

    def make(**kwargs):
        started.append(boot_server(tmp_path, **kwargs))
        return started[-1]

    yield make
    for srv in started:
        finish(srv)


@pytest.fixture(scope="module")
def shared(tmp_path_factory):
    srv = boot_server(tmp_path_factory.mktemp("accept"), scan_secs=5)  # 5 is the floor: the `hang` row waits it out
    yield srv
    finish(srv)


def post(srv, body):
    answer = srv.request("POST", "/ledger", headers={"Content-Type": "application/json", TOKEN: srv.token}, body=json.dumps(body))
    return answer.status, answer.json()


def disk(srv):
    path = srv.tree / ledger_state.LEDGER_FILE
    return path.read_bytes() if path.exists() else None


def queue_of(srv):
    return srv.get("/ledger/status", headers={TOKEN: srv.token}).json()["queue"]


def audit_since(srv, baseline):
    deadline = time.monotonic() + 5
    while len(srv.audit()) <= baseline and time.monotonic() < deadline:
        time.sleep(0.02)
    time.sleep(0.15)  # the line is written after the reply; a stray second one needs time to land
    return srv.audit()[baseline:]


def assert_refused(srv, body, status, error):
    """One answer `{"ok": false, "error": code}`, one audit line (id = the op, reason = the code), nothing changed."""
    before, baseline, traces = disk(srv), len(srv.audit()), srv.stderr.count("Traceback")
    assert post(srv, body) == (status, {"ok": False, "error": error})
    [line] = audit_since(srv, baseline)
    assert (line["status"], line["id"], line["reason"]) == (str(status), body["op"], error)
    assert line["outcome"] == "refused" or status >= 500  # READING: 3.6 does not say refused or failed for a 500
    assert disk(srv) == before and srv.stderr.count("Traceback") == traces


@pytest.mark.parametrize("mode,status,error", [
    ("no_repository", 422, "no_repository"), ("no_matching_repository", 422, "no_matching_repository"),
    ("no_such_worktree", 422, "no_such_worktree"), ("nothing_matched", 422, "nothing_matched"),
    ("crash", 500, "scan_failed"), ("garbage", 500, "scan_failed"), ("hang", 500, "scan_timeout")])
def test_http_a_scan_that_cannot_queue_answers_its_code_audits_it_and_changes_nothing(shared, mode, status, error):
    """A2 rows. Catches the op stub still answering internal_error, a code renamed, a wrong status, an item queued or
    ledger.json written for a refusal, and (hang) a bound that is not TREKO_SCAN_SECS."""
    assert_refused(shared, {"op": "analyze", "directory": shared.proj, "branch": mode}, status, error)
    assert queue_of(shared) == []


def test_http_an_accepted_analyze_answers_audits_and_records_the_request(boot):
    """Catches a stub answer, a body that is not the four keys, a missing audit line, and requests[run] not saved."""
    srv = boot()
    baseline, request = len(srv.audit()), req(srv.proj)
    status, body = post(srv, {"op": "analyze", "directory": srv.proj})
    assert (status, set(body), body.get("op"), body.get("started")) == (200, {"ok", "op", "item", "started"}, "analyze", True)
    assert HEX16.fullmatch(body["item"])
    assert [(l["outcome"], l["status"], l["id"], l["reason"]) for l in audit_since(srv, baseline)] == [("accepted", "200", "analyze", "-")]
    saved = json.loads(disk(srv))
    assert saved["requests"] == {rid(request): request} and body["item"] in [item["item"] for item in saved["queue"]]


def test_http_started_is_false_when_another_item_is_already_waiting(boot):
    """Catches `started` hard-coded true: the page would tell the user a queued job had begun."""
    srv = boot(seed=lambda proj: ledger_doc([queued(req("/work/other"))]))
    assert post(srv, {"op": "analyze", "directory": srv.proj})[1].get("started", "no body") is False


def test_http_a_run_already_waiting_is_409_already_queued(boot):
    """A2 row. The item is seeded, so it is still waiting however fast the server is."""
    srv = boot(seed=lambda proj: ledger_doc([queued(req(proj))]))
    assert_refused(srv, {"op": "analyze", "directory": srv.proj}, 409, "already_queued")


def test_http_twenty_items_of_any_state_refuse_a_21st_with_409_queue_full(boot):
    """A2 row. Catches a cap that counts live items only."""
    srv = boot(seed=lambda proj: ledger_doc(many(20)))
    assert_refused(srv, {"op": "analyze", "directory": srv.proj}, 409, "queue_full")


def test_http_nineteen_items_still_accept_a_request(boot):
    """Catches an off-by-one in the cap, over the wire."""
    srv = boot(seed=lambda proj: ledger_doc(many(19)))
    assert post(srv, {"op": "analyze", "directory": srv.proj})[0] == 200


def test_http_a_ledger_that_cannot_be_written_answers_500_ledger_write_failed_and_queues_nothing(boot):
    """A2 row. The store folder is made read-only after the server started, so the save fails for real (EACCES).
    Catches an uncaught LedgerWriteError and an item added to memory before the save."""
    srv = boot()
    os.chmod(str(srv.tree), 0o500)
    try:
        assert_refused(srv, {"op": "analyze", "directory": srv.proj}, 500, "ledger_write_failed")
    finally:
        os.chmod(str(srv.tree), 0o700)
    assert queue_of(srv) == []


def test_http_reanalyze_queues_the_recorded_request_and_a_missing_directory_is_422_no_such_directory(boot):
    """A2 row and G7 over the wire. Two recorded requests for two runs of the shared sample store; the fake scan says ok
    for both, so the second refusal can only come from the route's own directory rule."""
    assert len(SAMPLE_RUNS) >= 2, "the sample store needs two runs"
    live, gone = SAMPLE_RUNS[:2]
    srv = boot(seed=lambda proj: ledger_doc(requests={live: req(proj), gone: req(proj + "-removed")}))
    assert_refused(srv, {"op": "reanalyze", "run": gone}, 422, "no_such_directory")
    status, body = post(srv, {"op": "reanalyze", "run": live})
    assert (status, body.get("op"), body.get("started")) == (200, "reanalyze", True)


def test_http_a_cmux_call_does_grow_the_log_the_teardown_check_reads(boot):
    """A5 falsifier: a send command makes the server call cmux, and that lands in the same log, so the check in `finish`
    could fail. The baseline is then reset on purpose."""
    srv = boot()
    assert srv.command("clear").status == 200 and len(srv.cmux_calls()) > len(srv.baseline)
    srv.baseline = srv.cmux_calls()
