"""Task 18 (spec 3.5, 5.6, 8.4, scenarios "removing items", "Delete hides", "the last visible run cannot be deleted";
D51; G3, G5, A2 rows for these codes): `remove_item`, `retry_item`, `hide_run` in process, then the `remove`, `retry` and
`delete` ops through `handle_op`, then the same codes as real HTTP requests. Helpers come from test_ledger_accept.py and
test_ledger_accept_server.py. Modules are imported at the top; every public name under test is looked up INSIDE each
test, so a missing function fails that test alone. Each docstring names the mutation (wrong implementation) it catches.
API ASSUMED (D51 and the task brief):
  ledger_state.remove_item(ledger, item_id) / retry_item(ledger, item_id) / hide_run(ledger, run, run_ids) -> None | code
  ledger_routes.handle_op(op, fields, config): config has `store_dir` (a Path; the store is `<store_dir>/tracker-data.js`)
  and `runner`; answers (200, {"ok": True, "op": op}) or (status, error, reason); wakes the runner once, after a retry only.
READINGS (the spec is silent): which code wins when an item is both not retryable and has a live twin (not tested); what
hiding an already hidden run does (not tested); a run id handed to hide_run that is not in run_ids (not tested).
NOT here: `item_running` over HTTP (task 39 drives it against a real running job: a seeded running item would be turned
interrupted by task 22), a successful `retry` over HTTP (the runner would pick the item up), and `store_unreadable` over
HTTP (step 7 of 3.4 already answers it before the op runs, so that row is green today and a new test would prove nothing)."""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ledger_routes  # noqa: E402
import ledger_state  # noqa: E402
import store  # noqa: E402
from test_ledger_accept import REAL_WRITE, cmux_log, queued, refuse_write, req, snap, untouched, writes  # noqa: E402,F401
from test_ledger_accept import disk as folder_disk  # noqa: E402
from test_ledger_accept_server import (SAMPLE_RUNS, Runner, assert_refused, audit_since, boot, config, ledger_doc,  # noqa: E402,F401
                                       post)  # cmux_log is autouse (A5), boot and writes are fixtures
from test_ledger_accept_server import disk as server_disk  # noqa: E402

NO_ITEM = "f" * 16  # 16 hex digits that name no item
LEDGER_WRITE_FAILED = (500, "ledger_write_failed", "ledger_write_failed")


def item(number, state="waiting", directory=None):
    """An item with its own id, run, timestamp and (for a failed or interrupted one) error and detail, so no key is shared."""
    row = queued(req(directory or "/work/%d" % number), state, number)
    row["queuedAt"] = "2026-11-14T00:00:%02dZ" % number
    if state in ("failed", "interrupted"):
        row["error"], row["detail"] = "analysis_failed" if state == "failed" else "interrupted", "detail %d" % number
    return row


def iid(number):
    return "%016x" % number


def seeded(folder, items, hidden=(), requests=None):
    """A saved ledger with `hidden` and `requests` filled, so that a helper which touches them is caught."""
    state = {"version": ledger_state.LEDGER_VERSION, "queue": list(items), "hidden": list(hidden),
             "requests": {"/x": req("/work/x")} if requests is None else requests}
    REAL_WRITE(folder, state)  # the real write, so the `writes` fixture counts only what the code under test saves
    return ledger_state.Ledger(state=state, store_dir=folder)


def refused(ledger, folder, writes_seen, call, code):
    """The helper answers `code`, and the state, ledger.json and the number of saves are all as they were."""
    before = snap(ledger, folder)
    assert call() == code
    untouched(ledger, folder, before, writes_seen)


def raises_and_changes_nothing(ledger, folder, call, monkeypatch):
    before = snap(ledger, folder)
    monkeypatch.setattr(ledger_state, "write_ledger", refuse_write)
    with pytest.raises(ledger_state.LedgerWriteError):
        call()
    assert snap(ledger, folder) == before


def store_with(folder, ids):
    """A parseable `tracker-data.js` holding runs with these ids; returns its bytes."""
    data = store.new_store()
    for run_id in ids:
        data = store.upsert_run(data, {"id": run_id, "name": run_id, "dir": "~/dev", "branches": [], "features": [],
                                       "analyzedAt": "2026-11-03T09:00:00Z"})
    path = Path(folder) / "tracker-data.js"
    store.write_store(path, data)
    return path.read_bytes()


def saved(folder):
    return json.loads(folder_disk(folder))


# ---------------------------------------------------------------------------------------------- remove_item

@pytest.mark.parametrize("state", ["waiting", "failed", "interrupted"])
def test_remove_item_takes_out_exactly_that_item_and_saves_once(tmp_path, writes, state):
    """Catches a removal by list position (ids 12 and 1 differ), a removal of a neighbour, a reorder of the others, a
    return value other than None, a save that is missing or done twice, and a touched `requests` or `hidden`."""
    items = [item(11, "running"), item(12, state), item(13, "waiting"), item(14, "failed")]
    ledger = seeded(tmp_path, items, hidden=["h1"])
    assert ledger_state.remove_item(ledger, iid(12)) is None
    after = ledger.snapshot()
    assert after["queue"] == [items[0], items[2], items[3]]
    assert (after["hidden"], after["requests"]) == (["h1"], {"/x": req("/work/x")})
    assert saved(tmp_path) == after and writes == [after]


def test_remove_item_refuses_the_running_item_with_item_running_and_writes_nothing(tmp_path, writes):
    """Catches a removal of the running item (the runner would then finish a job nobody can see)."""
    ledger = seeded(tmp_path, [item(1, "running"), item(2, "waiting")])
    refused(ledger, tmp_path, writes, lambda: ledger_state.remove_item(ledger, iid(1)), "item_running")


def test_remove_item_refuses_an_unknown_id_with_no_such_item_and_writes_nothing(tmp_path, writes):
    """Catches a KeyError or None for an unknown id, and a removal of the first item when nothing matches."""
    ledger = seeded(tmp_path, [item(1, "failed"), item(2, "waiting")])
    refused(ledger, tmp_path, writes, lambda: ledger_state.remove_item(ledger, NO_ITEM), "no_such_item")
    refused(ledger, tmp_path, writes, lambda: ledger_state.remove_item(ledger, iid(1)[:-1]), "no_such_item")


def test_remove_item_with_a_failing_save_raises_and_leaves_the_state_as_it_was(tmp_path, monkeypatch):
    """Catches a state changed in memory before the save, and a LedgerWriteError swallowed into a refusal code."""
    ledger = seeded(tmp_path, [item(1, "failed"), item(2, "waiting")])
    raises_and_changes_nothing(ledger, tmp_path, lambda: ledger_state.remove_item(ledger, iid(1)), monkeypatch)


# ----------------------------------------------------------------------------------------------- retry_item

@pytest.mark.parametrize("state", ["failed", "interrupted"])
def test_retry_item_puts_the_item_back_to_waiting_at_the_same_place_and_clears_error_and_detail(tmp_path, writes, state):
    """Catches an append to the end of the queue or a move to the front (index 1 of 4), an error or detail kept, any other
    key changed (id, run, request, queuedAt), another item touched, a second save, and `requests` or `hidden` touched."""
    items = [item(1, "running"), item(2, state), item(3, "waiting"), item(4, "failed")]
    ledger = seeded(tmp_path, items, hidden=["h1"])
    assert ledger_state.retry_item(ledger, iid(2)) is None
    after = ledger.snapshot()
    assert [row["item"] for row in after["queue"]] == [iid(n) for n in (1, 2, 3, 4)]
    assert after["queue"][1] == {**items[1], "state": "waiting", "error": None, "detail": None}
    assert [after["queue"][n] for n in (0, 2, 3)] == [items[n] for n in (0, 2, 3)]
    assert (after["hidden"], after["requests"]) == (["h1"], {"/x": req("/work/x")})
    assert saved(tmp_path) == after and writes == [after]


@pytest.mark.parametrize("state", ["waiting", "running"])
def test_retry_item_refuses_a_waiting_or_running_item_with_not_retryable_and_writes_nothing(tmp_path, writes, state):
    """Catches a retry that accepts any item (a running job put back to waiting would run twice)."""
    ledger = seeded(tmp_path, [item(1, "failed"), item(2, state)])
    refused(ledger, tmp_path, writes, lambda: ledger_state.retry_item(ledger, iid(2)), "not_retryable")


@pytest.mark.parametrize("other", ["waiting", "running"])
def test_retry_item_refuses_when_another_item_for_the_same_run_is_live_with_already_queued(tmp_path, writes, other):
    """Catches a missing check (two live items for one run), and a check on waiting only (the running twin)."""
    twin = {**item(2, other, "/work/1"), "run": item(1)["run"]}
    ledger = seeded(tmp_path, [item(1, "failed"), twin])
    refused(ledger, tmp_path, writes, lambda: ledger_state.retry_item(ledger, iid(1)), "already_queued")


@pytest.mark.parametrize("other", ["failed", "interrupted"])
def test_retry_item_is_not_blocked_by_another_failed_or_interrupted_item_for_the_same_run(tmp_path, other):
    """Catches an already_queued check that ignores the state of the other item, or that tests the retried item against
    itself (it shares its own run, so every retry would be refused)."""
    twin = {**item(2, other, "/work/1"), "run": item(1)["run"]}
    ledger = seeded(tmp_path, [item(1, "failed"), twin])
    assert ledger_state.retry_item(ledger, iid(1)) is None
    assert [row["state"] for row in ledger.snapshot()["queue"]] == ["waiting", other]


def test_retry_item_refuses_an_unknown_id_with_no_such_item_and_writes_nothing(tmp_path, writes):
    """Catches a KeyError, or a retry of the first failed item when nothing matches."""
    ledger = seeded(tmp_path, [item(1, "failed"), item(2, "waiting")])
    refused(ledger, tmp_path, writes, lambda: ledger_state.retry_item(ledger, NO_ITEM), "no_such_item")


def test_retry_item_with_a_failing_save_raises_and_leaves_the_state_as_it_was(tmp_path, monkeypatch):
    """Catches a state changed in memory before the save, and a swallowed LedgerWriteError."""
    ledger = seeded(tmp_path, [item(1, "failed"), item(2, "waiting")])
    raises_and_changes_nothing(ledger, tmp_path, lambda: ledger_state.retry_item(ledger, iid(1)), monkeypatch)


# ------------------------------------------------------------------------------------------------ hide_run

def test_hide_run_appends_the_run_to_hidden_and_saves_once(tmp_path, writes):
    """Catches a hidden list replaced instead of appended to (C would be lost), a run put at the front, a second save, and
    a touched queue or `requests`."""
    items = [item(1, "failed")]
    ledger = seeded(tmp_path, items, hidden=["rC"])
    assert ledger_state.hide_run(ledger, "rA", ["rA", "rB", "rC"]) is None
    after = ledger.snapshot()
    assert (after["hidden"], after["queue"], after["requests"]) == (["rC", "rA"], items, {"/x": req("/work/x")})
    assert saved(tmp_path) == after and writes == [after]


def test_hide_run_refuses_to_hide_the_last_visible_run_with_last_run(tmp_path, writes):
    """Catches a check made before the run is added (the second hide would pass), and a check that counts the hidden run."""
    ledger = seeded(tmp_path, [])
    assert ledger_state.hide_run(ledger, "rA", ["rA", "rB"]) is None
    before, count = snap(ledger, tmp_path), len(writes)
    assert ledger_state.hide_run(ledger, "rB", ["rA", "rB"]) == "last_run"
    assert snap(ledger, tmp_path) == before and len(writes) == count


@pytest.mark.parametrize("run_ids,hidden,run", [
    (["rA"], [], "rA"), (["rA", "rB"], ["rB"], "rA"), (["rA"], ["stale"], "rA"), (["rA", "rB", "rC"], ["rB", "rC"], "rA")])
def test_hide_run_refuses_when_no_run_would_stay_visible_and_writes_nothing(tmp_path, writes, run_ids, hidden, run):
    """Catches a count of hidden ids against run ids by length (the stale id would balance the one run), a hidden id
    that is not a run counted as a visible one, and no check at all (one run in the store)."""
    ledger = seeded(tmp_path, [item(1, "failed")], hidden=hidden)
    refused(ledger, tmp_path, writes, lambda: ledger_state.hide_run(ledger, run, run_ids), "last_run")


def test_hide_run_counts_a_stale_hidden_id_as_nothing_when_another_run_is_still_visible(tmp_path):
    """Catches a rule that refuses whenever hidden is not empty, or that treats a stale id as a hidden run of the store."""
    ledger = seeded(tmp_path, [], hidden=["stale"])
    assert ledger_state.hide_run(ledger, "rA", ["rA", "rB"]) is None
    assert ledger.snapshot()["hidden"] == ["stale", "rA"]


def test_hide_run_with_a_failing_save_raises_and_leaves_the_state_as_it_was(tmp_path, monkeypatch):
    """Catches a state changed in memory before the save, and a swallowed LedgerWriteError."""
    ledger = seeded(tmp_path, [])
    raises_and_changes_nothing(ledger, tmp_path, lambda: ledger_state.hide_run(ledger, "rA", ["rA", "rB"]), monkeypatch)


# ----------------------------------------------------------------------------- handle_op (in process)

def routed(tmp_path, items, runs=("rA", "rB"), hidden=()):
    """(ledger, runner, config, store bytes): a ledger and a store in one folder, a runner that counts wakes."""
    ledger = seeded(tmp_path, items, hidden=hidden)
    runner = Runner(ledger)
    return ledger, runner, {**config(ledger, runner, None), "store_dir": tmp_path}, store_with(tmp_path, runs)


def test_handle_op_remove_answers_200_removes_the_item_and_does_not_wake_the_runner(tmp_path):
    """Catches the stub answer, a body with other keys or another op name, an item left in the queue, and a wake (nothing
    became runnable: a wake would start a runner pass for no reason)."""
    ledger, runner, cfg, _ = routed(tmp_path, [item(1, "failed"), item(2, "waiting")])
    assert ledger_routes.handle_op("remove", {"item": iid(1)}, cfg) == (200, {"ok": True, "op": "remove"})
    assert [row["item"] for row in ledger.snapshot()["queue"]] == [iid(2)] and runner.saw == []
    assert saved(tmp_path) == ledger.snapshot()


def test_handle_op_retry_answers_200_wakes_the_runner_once_and_the_item_is_waiting_by_then(tmp_path):
    """Catches the stub answer, no wake (the retried item would sit until a restart), two wakes, and a wake before the save
    (the runner would then find the item still failed)."""
    ledger, runner, cfg, _ = routed(tmp_path, [item(1, "waiting"), item(2, "failed"), item(3, "waiting")])
    assert ledger_routes.handle_op("retry", {"item": iid(2)}, cfg) == (200, {"ok": True, "op": "retry"})
    assert len(runner.saw) == 1
    assert [(row["item"], row["state"], row["error"]) for row in runner.saw[0]] == [
        (iid(1), "waiting", None), (iid(2), "waiting", None), (iid(3), "waiting", None)]
    assert saved(tmp_path) == ledger.snapshot()


def test_handle_op_delete_hides_the_run_leaves_the_store_bytes_alone_and_does_not_wake_the_runner(tmp_path):
    """G3. Catches the stub answer, a run removed from the store file (the bytes would change), a run not added to
    hidden, a wake, and run ids read from somewhere else than the store (the ledger's `requests` is empty of them)."""
    ledger, runner, cfg, store_bytes = routed(tmp_path, [item(1, "failed")])
    assert ledger_routes.handle_op("delete", {"run": "rA"}, cfg) == (200, {"ok": True, "op": "delete"})
    assert ledger.snapshot()["hidden"] == ["rA"] and saved(tmp_path)["hidden"] == ["rA"]
    assert (tmp_path / "tracker-data.js").read_bytes() == store_bytes and runner.saw == []


@pytest.mark.parametrize("op,fields,items,expected", [
    ("remove", {"item": iid(1)}, [item(1, "running")], (409, "item_running", "item_running")),
    ("remove", {"item": NO_ITEM}, [item(1, "failed")], (404, "no_such_item", "no_such_item")),
    ("retry", {"item": NO_ITEM}, [item(1, "failed")], (404, "no_such_item", "no_such_item")),
    ("retry", {"item": iid(1)}, [item(1, "waiting")], (409, "not_retryable", "not_retryable")),
    ("retry", {"item": iid(1)}, [item(1, "running")], (409, "not_retryable", "not_retryable")),
    ("retry", {"item": iid(1)}, [item(1, "failed"), {**item(2, "waiting", "/work/1"), "run": item(1)["run"]}],
     (409, "already_queued", "already_queued"))])
def test_handle_op_refusals_answer_their_exact_tuple_change_nothing_and_do_not_wake_the_runner(tmp_path, writes, op, fields,
                                                                                               items, expected):
    """A2 rows. Catches a wrong status, code or reason, a stub answer, a save for a refusal, and a wake after a refusal."""
    ledger, runner, cfg, _ = routed(tmp_path, items)
    before = snap(ledger, tmp_path)
    assert ledger_routes.handle_op(op, fields, cfg) == expected
    untouched(ledger, tmp_path, before, writes)
    assert runner.saw == []


def test_g5_delete_of_the_only_visible_run_answers_409_last_run_and_changes_nothing(tmp_path, writes):
    """G5. The store holds one run. Catches the stub answer, a delete that hides it anyway, and a wake."""
    ledger, runner, cfg, store_bytes = routed(tmp_path, [item(1, "failed")], runs=("rA",))
    before = snap(ledger, tmp_path)
    assert ledger_routes.handle_op("delete", {"run": "rA"}, cfg) == (409, "last_run", "last_run")
    untouched(ledger, tmp_path, before, writes)
    assert runner.saw == [] and (tmp_path / "tracker-data.js").read_bytes() == store_bytes


def test_g5_delete_counts_visible_runs_from_the_store_not_from_the_hidden_list_alone(tmp_path, writes):
    """G5. Two runs in the store, B already hidden: A is the only visible one. Catches a count of the ledger's hidden
    list against nothing, which would let A through."""
    ledger, runner, cfg, _ = routed(tmp_path, [], hidden=["rB"])
    before = snap(ledger, tmp_path)
    assert ledger_routes.handle_op("delete", {"run": "rA"}, cfg) == (409, "last_run", "last_run")
    untouched(ledger, tmp_path, before, writes)
    assert runner.saw == []


def test_handle_op_delete_of_a_store_that_does_not_parse_answers_500_store_unreadable_and_changes_nothing(tmp_path, writes):
    """A2 row. Catches the stub answer, a store error that escapes handle_op, and a run hidden from an unreadable store."""
    ledger, runner, cfg, _ = routed(tmp_path, [item(1, "failed")])
    (tmp_path / "tracker-data.js").write_text("this is not a store")
    before = snap(ledger, tmp_path)
    assert ledger_routes.handle_op("delete", {"run": "rA"}, cfg) == (500, "store_unreadable", "store_unreadable")
    untouched(ledger, tmp_path, before, writes)
    assert runner.saw == [] and (tmp_path / "tracker-data.js").read_text() == "this is not a store"


@pytest.mark.parametrize("op,fields,items", [
    ("remove", {"item": iid(1)}, [item(1, "failed")]), ("retry", {"item": iid(1)}, [item(1, "failed")]),
    ("delete", {"run": "rA"}, [item(1, "failed")])])
def test_handle_op_a_failed_save_answers_500_ledger_write_failed_changes_nothing_and_does_not_wake(tmp_path, monkeypatch, op,
                                                                                                   fields, items):
    """A2 row. Catches an uncaught LedgerWriteError, a state changed before the save, and a wake after a failed save."""
    ledger, runner, cfg, _ = routed(tmp_path, items)
    before = snap(ledger, tmp_path)
    monkeypatch.setattr(ledger_state, "write_ledger", refuse_write)
    assert ledger_routes.handle_op(op, fields, cfg) == LEDGER_WRITE_FAILED == ledger_routes.LEDGER_WRITE_FAILED
    assert snap(ledger, tmp_path) == before and runner.saw == []


# ------------------------------------------------------------------------------------ real HTTP rows (A2)

def seeded_doc(items, hidden=()):
    return {**ledger_doc(items), "hidden": list(hidden)}


def assert_accepted(srv, body):
    """One 200 `{"ok": true, "op": op}`, one audit line (accepted, id = the op, reason `-`), no traceback."""
    baseline, traces = len(srv.audit()), srv.stderr.count("Traceback")
    assert post(srv, body) == (200, {"ok": True, "op": body["op"]})
    [line] = audit_since(srv, baseline)
    assert (line["outcome"], line["status"], line["id"], line["reason"]) == ("accepted", "200", body["op"], "-")
    assert srv.stderr.count("Traceback") == traces


def test_http_remove_of_an_unknown_item_is_404_no_such_item(boot):
    """A2 row. The ledger holds only an interrupted item (never a running one: task 22 would turn it interrupted)."""
    srv = boot(seed=lambda proj: seeded_doc([item(1, "interrupted")]))
    assert_refused(srv, {"op": "remove", "item": NO_ITEM}, 404, "no_such_item")
    assert [row["item"] for row in server_doc(srv)["queue"]] == [iid(1)]


def test_http_retry_of_an_unknown_item_is_404_no_such_item(boot):
    """A2 row. Catches the stub answer and a retry of the first failed item when nothing matches."""
    srv = boot(seed=lambda proj: seeded_doc([item(1, "failed")]))
    assert_refused(srv, {"op": "retry", "item": NO_ITEM}, 404, "no_such_item")
    assert server_doc(srv)["queue"][0]["state"] == "failed"


def test_http_retry_of_a_waiting_item_is_409_not_retryable(boot):
    """A2 row. The item is seeded and nothing wakes the runner (a refusal never does), so it stays waiting."""
    srv = boot(seed=lambda proj: seeded_doc([item(1, "waiting")]))
    assert_refused(srv, {"op": "retry", "item": iid(1)}, 409, "not_retryable")
    assert [row["state"] for row in server_doc(srv)["queue"]] == ["waiting"]


def test_http_retry_of_a_failed_item_whose_run_is_waiting_is_409_already_queued(boot):
    """A2 row. The twin is seeded waiting, as in the analyze already_queued row, so it stays waiting."""
    srv = boot(seed=lambda proj: seeded_doc([item(1, "failed", proj), item(2, "waiting", proj)]))
    assert_refused(srv, {"op": "retry", "item": iid(1)}, 409, "already_queued")
    assert [row["state"] for row in server_doc(srv)["queue"]] == ["failed", "waiting"]


def test_http_delete_of_the_only_visible_run_is_409_last_run(boot):
    """A2 row and G5 over the wire: every run of the sample store but one is hidden, then the last is deleted."""
    srv = boot(seed=lambda proj: seeded_doc([], hidden=SAMPLE_RUNS[1:]))
    store_bytes = (srv.tree / "tracker-data.js").read_bytes()
    assert_refused(srv, {"op": "delete", "run": SAMPLE_RUNS[0]}, 409, "last_run")
    assert server_doc(srv)["hidden"] == SAMPLE_RUNS[1:] and (srv.tree / "tracker-data.js").read_bytes() == store_bytes


def test_http_remove_of_a_failed_item_answers_200_audits_it_and_saves_the_queue_without_it(boot):
    """Catches the stub answer, a missing audit line, and an item still in ledger.json after a 200."""
    srv = boot(seed=lambda proj: seeded_doc([item(1, "failed"), item(2, "interrupted")]))
    assert_accepted(srv, {"op": "remove", "item": iid(1)})
    assert [row["item"] for row in server_doc(srv)["queue"]] == [iid(2)]


def test_http_delete_of_a_run_answers_200_audits_it_hides_it_and_leaves_the_store_bytes_alone(boot):
    """G3 over the wire. Catches the stub answer, a run not added to hidden, and a store file rewritten."""
    srv = boot()
    store_bytes = (srv.tree / "tracker-data.js").read_bytes()
    assert_accepted(srv, {"op": "delete", "run": SAMPLE_RUNS[0]})
    assert server_doc(srv)["hidden"] == [SAMPLE_RUNS[0]] and (srv.tree / "tracker-data.js").read_bytes() == store_bytes


def server_doc(srv):
    return json.loads(server_disk(srv))
