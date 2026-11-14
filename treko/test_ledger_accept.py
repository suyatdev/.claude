"""Task 17 (spec 3.4 step 8, 3.5, 5.6, sections 10 and 11 A5; D49): `enqueue` and `accept_analysis`, in process. The ops
route (`handle_op`), reanalyze and G7, and the real HTTP rows for the same codes, are in test_ledger_accept_server.py. Modules are imported at the top; every public
name under test is looked up INSIDE each test, so a missing function fails that test alone. Each assertion names the
mutation it catches. API ASSUMED (D49 and the task brief; `scan_secs`, `scan_program` and `program=` are test seams):
  ledger_state.MAX_QUEUE_ITEMS == 20; enqueue(ledger, request) -> (item_id, started, None) | (None, None, code)
  ledger_routes.accept_analysis(ledger, registry, scan_secs, request, *, program=None) -> (200, body) | (status, error, reason)
  ledger_routes.reanalyze_request(ledger, run) -> the recorded request or None
  ledger_routes.handle_op(op, fields, config) -> (200, body) | refusal; config keys ledger, registry, scan_secs, runner,
  optional scan_program; remove/retry/delete answer ledger_routes.OP_STUB_REFUSAL (task 18). READINGS flagged below."""

import json
import os
import re
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ledger_jobs  # noqa: E402
import ledger_routes  # noqa: E402
import ledger_state  # noqa: E402
import server_harness as harness  # noqa: E402
import store  # noqa: E402
from test_ledger_scan_more import make_repo, world  # noqa: E402,F401  (`world` is a fixture)

SCAN_SECS = 30
HEX16, REAL_WRITE = re.compile(r"[0-9a-f]{16}"), ledger_state.write_ledger
OK_SCAN = 'print(json.dumps({"outcome": "ok", "families": [], "questions": [], "missed": {}}))'
FAKES = {"ok": OK_SCAN, "hang": "time.sleep(60)", "exit-3": "sys.exit(3)", "garbage": "print('not json')",
         "no-families": 'print(json.dumps({"outcome": "ok"}))', "ok-but-exit-1": OK_SCAN + "\nsys.exit(1)"}
BLOCKING = ("import json, os, sys, time\njson.load(sys.stdin)\nopen(STARTED, 'w').close()\ndeadline = time.time() + 30\n"
            "while not os.path.exists(GO) and time.time() < deadline:\n    time.sleep(0.02)\n" + OK_SCAN + "\n")


def req(directory="/work/a", repo="", branch="", worktree=""):
    return {"directory": directory, "repo": repo, "branch": branch, "worktree": worktree}


def rid(request):
    return ledger_state.run_id(request["directory"], request["repo"], request["branch"], request["worktree"])


def queued(request, state="waiting", number=1):
    error = "analysis_failed" if state == "failed" else None
    return {"item": "%016x" % number, "state": state, "queuedAt": "2026-11-14T00:00:00Z", "request": request,
            "run": rid(request), "error": error, "detail": None}


def many(count, state="failed"):
    return [queued(req("/work/%d" % n), state, n + 1) for n in range(count)]


def make_ledger(folder, items=(), requests=None):
    state = {"version": ledger_state.LEDGER_VERSION, "queue": list(items), "hidden": [], "requests": dict(requests or {})}
    REAL_WRITE(folder, state)  # the real function, captured before any test counts or breaks writes
    return ledger_state.Ledger(state=state, store_dir=folder)


def disk(folder):
    path = Path(folder) / ledger_state.LEDGER_FILE
    return path.read_bytes() if path.exists() else None


@pytest.fixture(autouse=True)
def cmux_log(tmp_path_factory, monkeypatch):
    """A5: the fake cmux every child here would inherit; the log it writes must still be empty at teardown."""
    folder = tmp_path_factory.mktemp("cmux")
    log = folder / "cmux-calls.jsonl"
    monkeypatch.setenv("CMUX_BIN", str(harness.install_fake_cmux(folder)))
    monkeypatch.setenv("FAKE_CMUX_LOG", str(log))
    yield log
    assert not log.exists() or log.read_text() == "", "a test caused a cmux call: " + log.read_text()


@pytest.fixture
def writes(monkeypatch):
    """Every ledger write the code under test makes (the state written), still carried out."""
    seen = []
    monkeypatch.setattr(ledger_state, "write_ledger", lambda folder, state: (seen.append(state), REAL_WRITE(folder, state))[1])
    return seen


def refuse_write(folder, state):
    raise ledger_state.LedgerWriteError("ENOSPC")


def wait_for(path, secs=10):
    deadline = time.monotonic() + secs
    while not path.exists() and time.monotonic() < deadline:
        time.sleep(0.02)
    return path.exists()


def fake_scan(folder, name):
    path = Path(folder) / ("fake-%s.py" % name)
    path.write_text("import json, sys, time\njson.load(sys.stdin)\n" + FAKES[name] + "\n")
    return str(path)


def registry(env=None):
    return ledger_jobs.ChildRegistry(dict(os.environ) if env is None else env)


def accept(ledger, program, request, secs=SCAN_SECS, reg=None):
    return ledger_routes.accept_analysis(ledger, reg or registry(), secs, request, program=program)


def untouched(ledger, folder, before, writes_seen):
    """A5/G7: a refusal changes no state, no file, and does not even rewrite the file."""
    assert (ledger.snapshot(), disk(folder), writes_seen) == (before[0], before[1], [])


def snap(ledger, folder):
    return ledger.snapshot(), disk(folder)


def test_the_cmux_log_the_autouse_check_reads_is_the_one_a_cmux_call_writes(cmux_log):
    """A5 falsifier: a cmux call from here lands in this very log (or the autouse check could never fail)."""
    subprocess.run([os.environ["CMUX_BIN"], "send"], env=os.environ, check=True)
    assert [json.loads(line)["argv"] for line in cmux_log.read_text().splitlines()] == [["send"]]
    cmux_log.write_text("")  # this one test made the call on purpose


# ----------------------------------------------------------------------------------------------------- enqueue

def test_the_queue_cap_is_twenty():
    assert ledger_state.MAX_QUEUE_ITEMS == 20  # a cap of 10 or 25


def test_enqueue_writes_one_waiting_item_and_the_recorded_request_in_a_single_save(tmp_path, writes):
    """Catches two saves (item, then requests: a crash between them loses the request), a missing requests[run], a
    wrong item shape, a request not stored whole, a state other than waiting, and a stale or fixed queuedAt."""
    ledger, request = make_ledger(tmp_path), req()
    item_id, started, refusal = ledger_state.enqueue(ledger, request)
    state = ledger.snapshot()
    assert (started, refusal) == (True, None) and HEX16.fullmatch(item_id)
    assert state["queue"] == [{"item": item_id, "state": "waiting", "queuedAt": state["queue"][0]["queuedAt"],
                               "request": request, "run": rid(request), "error": None, "detail": None}]
    stamp = datetime.strptime(state["queue"][0]["queuedAt"], store.TIMESTAMP_FORMAT).replace(tzinfo=timezone.utc)
    assert abs((datetime.now(timezone.utc) - stamp).total_seconds()) < 60
    assert state["requests"] == {rid(request): request}
    assert writes == [state] and json.loads(disk(tmp_path)) == state  # one save, holding both


@pytest.mark.parametrize("others,started", [
    ((), True), (("waiting",), False), (("running",), False), (("failed", "interrupted"), True), (("failed", "waiting"), False)])
def test_started_is_true_only_when_no_other_item_is_running_or_waiting(tmp_path, others, started):
    """Catches `started = queue is empty` (fails the failed/interrupted row), `no running` only (fails waiting), and a
    constant."""
    ledger = make_ledger(tmp_path, [queued(req("/work/o%d" % n), state, n + 1) for n, state in enumerate(others)])
    assert ledger_state.enqueue(ledger, req())[1] is started


@pytest.mark.parametrize("state", ["waiting", "running"])
def test_the_same_run_waiting_or_running_is_already_queued_and_nothing_is_written(tmp_path, writes, state):
    """Catches checking `waiting` only (two identical submits then leave a second item beside a running one), a
    refusal that still writes, and one that changes the in-memory queue."""
    ledger = make_ledger(tmp_path, [queued(req(), state)])
    before = snap(ledger, tmp_path)
    assert ledger_state.enqueue(ledger, req()) == (None, None, "already_queued")
    untouched(ledger, tmp_path, before, writes)


@pytest.mark.parametrize("state", ["failed", "interrupted"])
def test_the_same_run_failed_or_interrupted_does_not_block_a_new_item(tmp_path, state):
    """Catches an already_queued test on the run id alone: a failed run could then never be analyzed again."""
    ledger = make_ledger(tmp_path, [queued(req(), state)])
    item_id, started, refusal = ledger_state.enqueue(ledger, req())
    assert (started, refusal) == (True, None) and len(ledger.snapshot()["queue"]) == 2


def test_two_different_runs_are_both_accepted_in_order_and_only_the_first_starts(tmp_path):
    """Catches a refusal keyed on the whole queue, an overwritten first item, and a repeated id."""
    ledger = make_ledger(tmp_path)
    first, second = ledger_state.enqueue(ledger, req("/work/a")), ledger_state.enqueue(ledger, req("/work/b"))
    assert (first[1:], second[1:]) == ((True, None), (False, None)) and first[0] != second[0]
    state = ledger.snapshot()
    assert [item["item"] for item in state["queue"]] == [first[0], second[0]]
    assert set(state["requests"]) == {rid(req("/work/a")), rid(req("/work/b"))}


@pytest.mark.parametrize("states", [("failed",) * 20, ("interrupted",) * 20, ("running", "waiting") + ("failed",) * 18])
def test_a_queue_of_twenty_items_of_any_state_refuses_a_twenty_first(tmp_path, writes, states):
    """Catches counting only live items (twenty failed ones must still fill it) and `>` where `>=` is meant."""
    ledger = make_ledger(tmp_path, [queued(req("/work/%d" % n), state, n + 1) for n, state in enumerate(states)])
    before = snap(ledger, tmp_path)
    assert ledger_state.enqueue(ledger, req("/work/new")) == (None, None, "queue_full")
    untouched(ledger, tmp_path, before, writes)


def test_nineteen_items_accept_a_twentieth_and_then_refuse_a_twenty_first(tmp_path):
    """Catches an off-by-one: a cap of 19 refuses the twentieth."""
    ledger = make_ledger(tmp_path, many(19))
    assert ledger_state.enqueue(ledger, req("/work/new"))[2] is None
    assert ledger_state.enqueue(ledger, req("/work/newer")) == (None, None, "queue_full")


def test_twenty_ids_are_distinct_lowercase_hex(tmp_path):
    """Catches a repeated or counter-shaped id and one that is not 16 lowercase hex digits."""
    ledger = make_ledger(tmp_path)
    ids = [ledger_state.enqueue(ledger, req("/work/%d" % n))[0] for n in range(20)]
    assert len(set(ids)) == 20 and all(HEX16.fullmatch(one) for one in ids)


def test_a_full_queue_that_already_holds_the_run_answers_already_queued(tmp_path):
    """READING (the task brief orders the checks already_queued first; spec 3.5 gives no precedence): a run already
    waiting is refused as already_queued even when the queue is also full. Catches the cap check running first."""
    items = many(19) + [queued(req(), "waiting", 99)]
    assert ledger_state.enqueue(make_ledger(tmp_path, items), req()) == (None, None, "already_queued")


@pytest.mark.parametrize("how", ["write_ledger", "os.replace"])
def test_a_failed_save_raises_and_leaves_the_state_and_the_file_as_they_were(tmp_path, monkeypatch, how):
    """Catches an in-memory change made before the save (a phantom item), a swallowed failure, and a half-written file."""
    ledger = make_ledger(tmp_path, [queued(req("/work/o"), "waiting", 5)])
    before = snap(ledger, tmp_path)

    def broken(*args, **kwargs):
        raise OSError(28, "No space left on device")

    with monkeypatch.context() as patch:
        patch.setattr(*((ledger_state, "write_ledger", refuse_write) if how == "write_ledger" else (os, "replace", broken)))
        with pytest.raises(ledger_state.LedgerWriteError):
            ledger_state.enqueue(ledger, req())
    assert snap(ledger, tmp_path) == before and os.listdir(str(tmp_path)) == [ledger_state.LEDGER_FILE]


def test_two_threads_racing_the_identical_request_leave_exactly_one_item(tmp_path):
    """Spec 5.6, scenario 'two identical submits race'. Catches a check made outside the lock (check, lock, append): the
    result is two items. A race cannot be proven absent, so 40 rounds run with the thread switch interval at 1 microsecond."""
    previous, request = sys.getswitchinterval(), req()
    sys.setswitchinterval(1e-6)
    try:
        for round_number in range(40):
            folder = tmp_path / str(round_number)
            folder.mkdir()
            ledger, barrier, results = make_ledger(folder), threading.Barrier(2), []

            def send():
                barrier.wait()
                results.append(ledger_state.enqueue(ledger, request))

            threads = [threading.Thread(target=send) for _ in range(2)]
            [thread.start() for thread in threads]
            [thread.join(20) for thread in threads]
            assert sorted(str(result[2]) for result in results) == ["None", "already_queued"], round_number
            assert len(ledger.snapshot()["queue"]) == 1
    finally:
        sys.setswitchinterval(previous)


# ------------------------------------------------------------------------------------------------ accept_analysis

def test_accept_analysis_queues_after_an_ok_scan_and_answers_the_success_body(tmp_path):
    """Catches a wrong op word, `item` or `started` missing or stringly, and a body that is not exactly the four keys."""
    ledger, request = make_ledger(tmp_path), req(str(tmp_path))
    status, body = accept(ledger, fake_scan(tmp_path, "ok"), request)
    [item] = ledger.snapshot()["queue"]
    assert status == 200 and body == {"ok": True, "op": "analyze", "item": item["item"], "started": True}
    assert item["request"] == request and ledger.snapshot()["requests"] == {rid(request): request}


@pytest.mark.parametrize("outcome", ["no_repository", "no_matching_repository", "no_such_worktree", "nothing_matched"])
def test_a_scan_that_finds_nothing_to_queue_answers_its_422_and_queues_nothing(world, tmp_path, writes, outcome):
    """Real scan program, real repository. Catches a wrong status (500), a code renamed on the way out, an enqueue
    before the scan's verdict, and a ledger write for a refusal."""
    proj = make_repo(world, world.tree / "proj")
    empty = world.base / "empty"
    empty.mkdir()
    request = {"no_repository": req(str(empty)), "no_matching_repository": req(str(proj), repo="nope"),
               "no_such_worktree": req(str(proj), worktree="ghost"), "nothing_matched": req(str(proj), branch="feat-x")}[outcome]
    ledger = make_ledger(tmp_path)
    before = snap(ledger, tmp_path)
    reg = registry(dict(world.env, CMUX_BIN=os.environ["CMUX_BIN"], FAKE_CMUX_LOG=os.environ["FAKE_CMUX_LOG"]))
    assert accept(ledger, None, request, reg=reg) == (422, outcome, outcome)
    untouched(ledger, tmp_path, before, writes)


def test_a_real_scan_of_a_real_repository_queues_the_request(world, tmp_path):
    """Catches a success path that only ever worked against a fake: a real repo, a real scan, 200 and one waiting item."""
    request = req(str(make_repo(world, world.tree / "proj")))
    ledger = make_ledger(tmp_path)
    reg = registry(dict(world.env, CMUX_BIN=os.environ["CMUX_BIN"], FAKE_CMUX_LOG=os.environ["FAKE_CMUX_LOG"]))
    status, body = accept(ledger, None, request, reg=reg)
    assert (status, body["started"], body["op"]) == (200, True, "analyze")
    assert [(item["item"], item["state"]) for item in ledger.snapshot()["queue"]] == [(body["item"], "waiting")]


@pytest.mark.parametrize("fake", ["exit-3", "garbage", "no-families", "ok-but-exit-1"])
def test_a_scan_that_breaks_its_contract_answers_500_scan_failed_and_queues_nothing(tmp_path, writes, fake):
    """Catches treating a crash or unreadable output as `ok`, reading stdout without the exit status (the last row), and
    a queue entry made before the answer is known."""
    ledger = make_ledger(tmp_path)
    before = snap(ledger, tmp_path)
    assert accept(ledger, fake_scan(tmp_path, fake), req(str(tmp_path))) == (500, "scan_failed", "scan_failed")
    untouched(ledger, tmp_path, before, writes)


def test_a_scan_that_passes_its_time_limit_answers_500_scan_timeout_and_queues_nothing(tmp_path, writes):
    """Catches a bound that is not passed through (the call would take 60 s) and a timeout read as success."""
    ledger = make_ledger(tmp_path)
    before = snap(ledger, tmp_path)
    assert accept(ledger, fake_scan(tmp_path, "hang"), req(str(tmp_path)), secs=1) == (500, "scan_timeout", "scan_timeout")
    untouched(ledger, tmp_path, before, writes)


def test_an_interpreter_that_cannot_be_started_answers_500_launch_failed_and_queues_nothing(tmp_path, writes, monkeypatch):
    """Scenario 'the directory scan cannot be started at submit'. Catches an OSError that escapes the route (a traceback,
    no answer) or one mapped to scan_failed. run_scan starts `sys.executable <program>`, so the seam is the interpreter."""
    ledger, reg = make_ledger(tmp_path), registry()
    before = snap(ledger, tmp_path)
    program = fake_scan(tmp_path, "ok")
    with monkeypatch.context() as patch:
        patch.setattr(sys, "executable", str(tmp_path / "no-such-python"))
        result = accept(ledger, program, req(str(tmp_path)), reg=reg)
    assert result == (500, "launch_failed", "launch_failed") and reg.children() == frozenset()
    untouched(ledger, tmp_path, before, writes)


def test_a_closed_registry_refuses_without_raising_and_queues_nothing(tmp_path, writes):
    """READING (D49 addendum): the spec names no code for a closed registry ('the server stopping, never a failure', 4,
    5.3), and a new code would be a spec change, so the existing 500 internal_error is pinned. Catches RegistryClosed
    escaping the route, and an item queued with no scan behind it."""
    ledger, reg = make_ledger(tmp_path), registry()
    before = snap(ledger, tmp_path)
    reg.close()
    result = accept(ledger, fake_scan(tmp_path, "ok"), req(str(tmp_path)), reg=reg)
    assert result == (500, "internal_error", "internal_error")
    untouched(ledger, tmp_path, before, writes)


def test_the_scan_runs_before_the_ledger_lock_is_taken(tmp_path):
    """Spec 5.6. The scan blocks until released; while it runs the test takes the ledger lock itself (snapshot, update)
    from another thread. Catches a scan inside the lock: the probe then cannot finish and every other request would wait
    behind a slow scan."""
    started, go = tmp_path / "started", tmp_path / "go"
    script = tmp_path / "blocking.py"
    script.write_text("STARTED, GO = %r, %r\n%s" % (str(started), str(go), BLOCKING))
    ledger, result, probed = ledger_state.Ledger(), [], threading.Event()
    worker = threading.Thread(target=lambda: result.append(accept(ledger, str(script), req(str(tmp_path)))), daemon=True)
    worker.start()
    try:
        assert wait_for(started), "the scan never started"

        def probe():
            ledger.snapshot()
            ledger.update(lambda state: state)
            probed.set()

        threading.Thread(target=probe, daemon=True).start()
        assert probed.wait(3), "the ledger lock was held while the scan ran"
        assert worker.is_alive() and not result  # the probe really ran during the scan
    finally:
        go.touch()
    worker.join(20)
    assert result[0][0] == 200


def test_a_scan_refusal_beats_an_enqueue_refusal(tmp_path):
    """Catches the queue checks running before the scan (spec 5.6: the scan is first). Same run waiting AND a scan that
    finds no repository: the scan's code wins."""
    ledger = make_ledger(tmp_path, [queued(req(str(tmp_path)))])
    program = tmp_path / "nothing.py"
    program.write_text('import json, sys\njson.load(sys.stdin)\nprint(json.dumps({"outcome": "no_repository", "families": [], "questions": [], "missed": {}}))\n')
    assert accept(ledger, str(program), req(str(tmp_path))) == (422, "no_repository", "no_repository")


@pytest.mark.parametrize("items,code", [([queued(req())], "already_queued"), (many(20), "queue_full")])
def test_accept_analysis_answers_409_for_a_run_already_queued_or_a_full_queue(tmp_path, writes, items, code):
    """Catches a 400/422/500 for these two, and a refusal that still writes."""
    ledger = make_ledger(tmp_path, items)
    before = snap(ledger, tmp_path)
    assert accept(ledger, fake_scan(tmp_path, "ok"), req()) == (409, code, code)
    untouched(ledger, tmp_path, before, writes)


def test_a_failed_ledger_write_answers_500_ledger_write_failed_and_changes_nothing(tmp_path, monkeypatch):
    """Catches an uncaught LedgerWriteError (a dropped connection) and a state that moved before the save failed."""
    ledger = make_ledger(tmp_path)
    before = snap(ledger, tmp_path)
    program = fake_scan(tmp_path, "ok")
    with monkeypatch.context() as patch:
        patch.setattr(ledger_state, "write_ledger", refuse_write)
        assert accept(ledger, program, req()) == (500, "ledger_write_failed", "ledger_write_failed")
    assert snap(ledger, tmp_path) == before

