"""Task 21 (docs/features/treko-ledger.spec.md, section 5.4 "The catch-all" and "One job"; decision D54): no job can
stay `running` for ever. Owns D14 (the catch-all) and D15 (the reap waits after a time-limit kill).

API ASSUMED (decision D54, quoted from the card; the three new public names are fixed there):
  ledger_failures.INTERNAL_ERROR == "internal_error"
  ledger_failures.internal_failure(error, stage) -> JobFailure(INTERNAL_ERROR, stage, cause=<class name of error>)
  ledger_jobs.JobRunner.paused() -> bool   False on a new runner; True once an exception in the runner loop outside
                                           any item has paused it (nothing resumes it in this task: that is task 26)
  run_next has an `except Exception` after `except JobFailure`, covering steps 1 to 6 (the stage-record setup too).
  Stage rule (D54 call 2): the last stage reached: "scan" once the scan is launched, the stage a `treko-progress`
  report names once one arrives, "merge" before the merge, "write" before the write, None before the scan.
  Line rule (D54 calls 1, 3, 4): `... internal_error <Class> at none` for stage None; an analyzer's reap-timeout line is
  `server: job <item> reap timeout <pid>` and its wait after a time-limit kill goes through the registry's `reap_wait`;
  a loop exception writes `server: runner error <Class>` and pauses.

NOT built, so not tested: an owner tag or a sweep on ChildRegistry (D54: each launch site already kills and reaps),
a failing ledger writer (task 26), the idle predicate (task 22), resuming a paused runner (task 26).

The fakes, the `world` fixture and the helpers are task 19's and 20's. Every call that must not hang runs on a daemon
thread under a hard limit (`Bounded`), so a wait that is given no limit fails its test instead of hanging the run.
The injected reap wait blocks when it is handed no limit and reports a timeout at once when it is handed one.
Each test names the wrong shortcut it catches.
"""

import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from server_harness import HANGING_ANALYZER  # noqa: E402
from test_ledger_failures import (  # noqa: E402
    SCAN_NEVER_ENDS, SECRET, failed_detail, runner_with, stderr_of, write_program,
)
from test_ledger_runner import NEWER, OLDER, POLL_SECS, QUIET_SECS, SCAN_SECS, jobs, wait_until, world  # noqa: E402,F401

HARD_SECS = 20  # the longest a call that must not hang may take
REAP_LIMIT = 5  # REAP_WAIT_SECS (section 5.4); the limit every bounded reap is handed
SHORT_SECS = 1  # the scan or analyzer bound for a time-limit kill
DEFAULTS = {"repo": None, "exit": None, "timedOut": False, "errno": None}  # task 20's detail, but for the stage
SLEEPS_ONCE = ("import json, os, sys, time\nsys.stdin.read()\nif not os.path.exists(%r):\n    open(%r, 'w').close()\n"
               "    time.sleep(60)\nprint(json.dumps({'outcome': 'no_repository', 'families': [], 'questions': [], 'missed': {}}))\n")
FAMILY_WITHOUT_LABEL = ("import json, sys\nsys.stdin.read()\nprint(json.dumps({'outcome': 'ok', 'questions': [], 'missed': {},"
                        " 'families': [{'root': '/nowhere'}]}))\n")


# ------------------------------------------------------------------------------------------------ helpers

class Bounded:
    """`call()` on a daemon thread; `result()` fails the test when it is still running after the limit, or when an
    exception escaped it (the item must be settled inside run_next, not by whoever called it)."""

    def __init__(self, call):
        self.box = {}
        self.thread = threading.Thread(target=self._run, args=(call,), daemon=True)
        self.thread.start()

    def _run(self, call):
        try:
            self.box["value"] = call()
        except BaseException as error:  # noqa: BLE001 - handed back to the test thread by result()
            self.box["error"] = error

    def result(self, secs=HARD_SECS):
        self.thread.join(secs)
        if self.thread.is_alive():
            pytest.fail("the call was still running after %d s (a reap wait given no limit?)" % secs)
        if "error" in self.box:
            pytest.fail("the call let %s escape" % type(self.box["error"]).__name__)
        return self.box["value"]


def bounded(call, secs=HARD_SECS):
    return Bounded(call).result(secs)


class StuckReaps:
    """A reap wait that never sees the process end: handed a limit it reports a timeout at once, handed none it
    blocks (until released at teardown) the way a wait with no limit would."""

    def __init__(self):
        self.given, self.release = [], threading.Event()

    def __call__(self, proc, timeout):
        self.given.append(timeout)
        if timeout is None:
            self.release.wait(HARD_SECS * 3)
        raise subprocess.TimeoutExpired(proc.args, timeout)


@pytest.fixture
def stuck(world):
    """The world's registry replaced by one whose reap waits never see an end (lines in `.lines`, every process it
    launched in `.launched`). Teardown kills and reaps those processes itself, since the injected wait never will."""
    lines, waits, launched = [], StuckReaps(), []
    registry = jobs().ChildRegistry({**os.environ, "FAKE_HANG_SECS": "60"}, reap_wait=waits, log=lines.append)
    real_launch = registry.launch

    def launch(argv, **kwargs):
        proc = real_launch(argv, **kwargs)
        launched.append(proc)
        return proc

    registry.launch = launch
    world.registry = registry
    yield SimpleNamespace(registry=registry, lines=lines, waits=waits, launched=launched)
    waits.release.set()
    registry.close()
    for proc in launched:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        proc.wait(timeout=REAP_LIMIT)


def gated_alpha(world):
    """One family whose fake analyzer waits for `go-alpha-<n>` before each stage line; nothing is released yet."""
    world.families("alpha")
    world.ctrl.analyzer("alpha", gated=True)


def release_through_cards(world):
    for number in (1, 2, 3):  # the analyzer prints worktrees, branches, cards and then waits for gate 4
        world.ctrl.go("alpha", number)


def raises_on_first_cards(calls):
    """A report handler that raises RuntimeError(SECRET) the first time it receives `cards` (D14's seam)."""
    def report(stage):
        calls.append(stage)
        if stage == "cards" and calls.count("cards") == 1:
            raise RuntimeError(SECRET)
    return report


def not_queued_or_running(world, item_id):
    memory, _ = world.item(item_id)
    return memory is None or memory["state"] not in ("waiting", "running")


# ----------------------------------------------------------------------------------------- A. D14: the catch-all

def test_d14_a_report_handler_that_raises_fails_the_item_internal_error_and_frees_the_queue(world, capsys):
    """D14. Catches: an exception that escapes run_next, an analyzer still running beside the next job, a code other
    than internal_error, a stage other than the last one reached (`cards`), the message in stderr or ledger.json, an
    item left running, no last_job_end, and a queue that does not go on to the next waiting item."""
    gated_alpha(world)
    first = world.queue("2121000000000001", OLDER)
    second = world.queue("2121000000000002", NEWER, repo="alpha")
    runner = world.runner(report=raises_on_first_cards([]))
    job = Bounded(runner.run_next)
    wait_until(lambda: world.ctrl.exists("argv-alpha.json"), "the analyzer started")
    (analyzer,) = world.registry.children()
    release_through_cards(world)
    assert job.result() == first["item"]
    assert analyzer.returncode is not None, "the analyzer was still running when run_next returned"
    assert failed_detail(world, first["item"], "internal_error") == dict(DEFAULTS, stage="cards")
    err = stderr_of(capsys)
    line = "server: job %s internal_error RuntimeError at cards" % first["item"]
    assert err.splitlines().count(line) == 1 and SECRET not in err
    assert SECRET not in (world.store_dir / "ledger.json").read_text()
    assert runner.last_job_end is not None and runner.progress() is None
    world.ctrl.go("alpha", 4)
    assert bounded(runner.run_next) == second["item"], "the next waiting item starts"
    assert world.item(second["item"]) == (None, None) and world.stored_run(second["run"]) is not None


def test_d14_the_reap_inside_the_catch_all_is_bounded_logs_once_and_leaves_the_process_registered(world, stuck):
    """D14, the round-4 bounded wait. Catches a wait handed no limit (the item never ends, so the hard limit fails
    it), a missing or doubled reap-timeout line, the analyzer's label `job analyzer` instead of `job <item>` (D54
    call 3), a process dropped from the registry, a kill that never landed, and a queue that stays stuck."""
    gated_alpha(world)
    first = world.queue("2222000000000001", OLDER)
    second = world.queue("2222000000000002", NEWER, repo="alpha")
    runner = world.runner(report=raises_on_first_cards([]))
    job = Bounded(runner.run_next)
    wait_until(lambda: len(stuck.launched) == 2, "the analyzer started")
    analyzer = stuck.launched[1]
    release_through_cards(world)
    assert job.result() == first["item"]
    assert failed_detail(world, first["item"], "internal_error")["stage"] == "cards"
    assert stuck.lines == ["server: job %s reap timeout %d" % (first["item"], analyzer.pid)]
    assert stuck.waits.given == [REAP_LIMIT], "one bounded reap, no second sweep"
    assert analyzer in stuck.registry.children()
    assert analyzer.wait(timeout=REAP_LIMIT) < 0, "the kill never landed"
    world.ctrl.go("alpha", 4)
    assert bounded(runner.run_next) == second["item"] and not_queued_or_running(world, second["item"])
    assert len(world.ctrl.scan_requests()) == 2, "the next waiting item did not start"


def test_d14_an_exception_before_any_stage_is_internal_error_with_stage_none(world, capsys):
    """D14 / D54 call 1. Falsifier: a catch-all that starts only at the scan lets this escape run_next (the stage
    record is set up right after the claim, from a `directory` that is not a string). Also catches a crash on the
    missing stage in the log line, and a subprocess started for an item that never got to the scan."""
    item = world.queue("2323000000000001", OLDER)

    def broken_request(state):
        state["queue"][0]["request"]["directory"] = None
        return state

    world.ledger.update(broken_request)
    runner = world.runner()
    assert bounded(runner.run_next) == item["item"]
    assert failed_detail(world, item["item"], "internal_error")["stage"] is None
    shape = re.compile(r"server: job %s internal_error \w+ at none" % item["item"])
    assert any(shape.fullmatch(line) for line in stderr_of(capsys).splitlines())
    assert runner.last_job_end is not None and not world.ctrl.scan_requests()


def test_d14_an_exception_after_the_scan_is_launched_records_the_scan_stage(world, capsys):
    """D54 call 2. A scan that answers a family with no `label` makes the runner itself raise before any report.
    Catches a stage left None once the scan has run, and a code other than internal_error."""
    item = world.queue("2424000000000001", OLDER)
    runner = runner_with(world, write_program(world, "scan_no_label.py", FAMILY_WITHOUT_LABEL))
    assert bounded(runner.run_next) == item["item"]
    assert failed_detail(world, item["item"], "internal_error")["stage"] == "scan"
    shape = re.compile(r"server: job %s internal_error \w+ at scan" % item["item"])
    assert any(shape.fullmatch(line) for line in stderr_of(capsys).splitlines())


# --------------------------------------------------------------------------------------------- B. the runner loop

class FlakyLedger:
    """The real ledger, except that `snapshot()` raises (the runner is choosing the next item) while `broken`."""

    def __init__(self, real):
        self._real, self.broken = real, True

    def snapshot(self):
        if self.broken:
            raise RuntimeError(SECRET)
        return self._real.snapshot()

    def update(self, change):
        return self._real.update(change)


def test_a_new_runner_is_not_paused(world):
    """Catches a `paused()` that starts True, or a method that is not there."""
    assert world.runner().paused() is False


def test_a_loop_exception_is_logged_and_pauses_the_runner_so_a_later_wake_starts_nothing(world, capsys):
    """Section 5.4, last paragraph. Falsifier: a loop that only logs and carries on runs the waiting item on the
    second wake. Also catches the message in stderr, a pause that never shows in `paused()`, and a thread that cannot
    leave once the registry is closed."""
    world.families("alpha")
    item = world.queue("2525000000000001", OLDER)
    flaky = FlakyLedger(world.ledger)
    runner = jobs().JobRunner(flaky, world.registry, world.store_path, 60, 60, scan_program=str(world.scan_program),
                              analyze_program=str(world.analyzer_program))
    before, seen = set(threading.enumerate()), []
    started = []

    def stderr_so_far():
        seen.append(capsys.readouterr().err)
        return "".join(seen).splitlines()

    try:
        runner.start()
        started = [t for t in threading.enumerate() if t not in before]
        runner.wake()
        wait_until(lambda: "server: runner error RuntimeError" in stderr_so_far(), "the loop's error line")
        wait_until(runner.paused, "the runner pausing")
        assert SECRET not in "".join(seen)
        flaky.broken = False
        runner.wake()
        deadline = time.monotonic() + 4 * QUIET_SECS
        while time.monotonic() < deadline:
            memory, disk = world.item(item["item"])
            assert memory["state"] == disk["state"] == "waiting" and not world.ctrl.scan_requests(), "a paused runner ran"
            time.sleep(POLL_SECS)
        assert runner.paused() is True
        world.registry.close()
        runner.wake()
        wait_until(lambda: not any(t.is_alive() for t in started), "the thread leaving after close + wake")
    finally:
        world.registry.close()
        world.ctrl.release_all()
        runner.wake()
        for thread in started:
            thread.join(HARD_SECS)


# ----------------------------------------------------------------------- C. D15: reap waits after a time-limit kill

def test_d15_a_submit_time_scan_past_its_bound_answers_scan_timeout_and_logs_one_reap_timeout(world, stuck):
    """D15, submit time. Catches a kill path handed no wait limit (the request never answers, so the hard limit fails
    it), another answer than 500 scan_timeout, an item queued, a missing, doubled or unlabelled reap-timeout line
    (`server: scan reap timeout <pid>`) and a process dropped from the registry."""
    import ledger_routes
    request = {"directory": world.directory, "repo": "", "branch": "", "worktree": ""}
    program = write_program(world, "scan_never_ends.py", SCAN_NEVER_ENDS)
    answer = bounded(lambda: ledger_routes.accept_analysis(world.ledger, stuck.registry, SHORT_SECS, request,
                                                           program=program))
    assert answer == (500, "scan_timeout", "scan_timeout")
    assert world.ledger.snapshot()["queue"] == []
    (scan,) = stuck.launched
    assert stuck.lines == ["server: scan reap timeout %d" % scan.pid] and stuck.waits.given == [REAP_LIMIT]
    assert scan in stuck.registry.children()


def test_d15_a_job_time_scan_past_its_bound_fails_the_item_logs_one_reap_timeout_and_the_next_item_starts(world, stuck):
    """D15, job time (the code exists today, so this guards it). Catches a kill path handed no wait limit (the item
    never ends), another code than scan_timeout, a line without `job <item>`, a doubled line, a process dropped from
    the registry, and a queue that does not go on."""
    program = write_program(world, "scan_sleeps_once.py", SLEEPS_ONCE % ((str(world.tmp_path / "slept"),) * 2))
    first = world.queue("2727000000000001", OLDER)
    second = world.queue("2727000000000002", NEWER, repo="alpha")
    runner = runner_with(world, program, scan_secs=SHORT_SECS)
    assert bounded(runner.run_next) == first["item"]
    assert failed_detail(world, first["item"], "scan_timeout")["timedOut"] is True
    (scan,) = stuck.launched
    assert stuck.lines == ["server: job %s reap timeout %d" % (first["item"], scan.pid)]
    assert stuck.waits.given == [REAP_LIMIT] and scan in stuck.registry.children()
    assert bounded(runner.run_next) == second["item"]
    assert world.item(second["item"])[0]["error"] == "no_repository", "the next item's scan did not run"


def test_d15_an_analyzer_killed_at_its_time_limit_fails_the_family_and_logs_one_reap_timeout(world, stuck):
    """D15, the one that fails today: `_analyze` waits on the process itself after the kill and labels a stuck
    reap `job analyzer`. Catches a wait handed no limit or one that bypasses the registry (no line, the process
    dropped), the label `job analyzer`, a family not marked timedOut, and an item not failed analysis_failed."""
    world.families("alpha")
    program = write_program(world, "hang_analyzer.py", HANGING_ANALYZER)
    item = world.queue("2828000000000001", OLDER)
    runner = jobs().JobRunner(world.ledger, stuck.registry, world.store_path, SHORT_SECS, SCAN_SECS,
                              scan_program=str(world.scan_program), analyze_program=program)
    assert bounded(runner.run_next) == item["item"]
    detail = failed_detail(world, item["item"], "analysis_failed")
    assert detail["timedOut"] is True and detail["stage"] == "worktrees" and detail["repo"] == "alpha"
    analyzer = stuck.launched[1]
    assert stuck.lines == ["server: job %s reap timeout %d" % (item["item"], analyzer.pid)]
    assert stuck.waits.given == [REAP_LIMIT] and analyzer in stuck.registry.children()
    assert runner.last_job_end is not None and runner.progress() is None


# --------------------------------------------------------------------------------------------- D. the new names

def test_internal_error_is_the_code_internal_error():
    """Catches a misspelt or renamed code (the card, the spec and the status page all name this one)."""
    from ledger_failures import INTERNAL_ERROR
    assert INTERNAL_ERROR == "internal_error"


def test_internal_failure_carries_the_class_name_as_its_cause_and_never_the_message():
    """Catches the exception's message (a path, a field of the request) kept as the cause or anywhere on the failure,
    a lost stage, and a failure that is not a JobFailure (so `detail_of` and `job_failure_line` could not take it)."""
    from ledger_failures import INTERNAL_ERROR, JobFailure, detail_of, internal_failure, job_failure_line
    failure = internal_failure(RuntimeError(SECRET), "cards")
    assert isinstance(failure, JobFailure)
    assert (failure.code, failure.stage, failure.cause) == (INTERNAL_ERROR, "cards", "RuntimeError")
    assert SECRET not in " ".join(str(value) for value in vars(failure).values())
    assert job_failure_line("item-1", failure) == "server: job item-1 internal_error RuntimeError at cards"
    assert detail_of(failure) == dict(DEFAULTS, stage="cards")


def test_internal_failure_with_no_stage_keeps_none_in_the_detail_and_says_none_in_the_line():
    """D54 call 1. Catches a stage invented for a job that reached none ("scan", an empty string) and a detail that
    leaves the `stage` key out."""
    from ledger_failures import detail_of, internal_failure, job_failure_line
    failure = internal_failure(ValueError(SECRET), None)
    assert failure.stage is None and failure.cause == "ValueError"
    assert detail_of(failure) == dict(DEFAULTS, stage=None)
    line = job_failure_line("item-1", failure)
    assert line == "server: job item-1 internal_error ValueError at none" and SECRET not in line


def test_job_failure_line_does_not_crash_on_a_failure_with_no_stage():
    """Today the line is built with `" ".join` over a None stage and raises TypeError. Catches that crash for any
    failure (not only the new code) and a line that spells the missing stage `None` or leaves it out."""
    from ledger_failures import JobFailure, job_failure_line
    line = job_failure_line("item-2", JobFailure("scan_failed", None))
    assert line == "server: job item-2 scan_failed at none"
