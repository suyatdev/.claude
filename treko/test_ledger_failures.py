"""Task 20 (docs/features/treko-ledger.spec.md, sections 3.5, 3.6 and 5.4 steps 2 to 5; decision D53): the job runner,
part 2. Owns D12 and D13: each way a job can fail ends with its own error code, a `detail` record and one safe
stderr line.

Groups 1 to 7 drive `JobRunner.run_next()` on the calling thread and never import `treko/ledger_failures.py`, so
today they fail on the missing behaviour (the `merge=` and `emit_run=` keyword arguments, and the codes), not on a
missing module. Group 8 tests the four new names of D53 directly and imports that module inside each test.

API ASSUMED (decision D53, quoted from the card):
  JobRunner(ledger, registry, store_path, analyze_secs, scan_secs, report=None, scan_program=None,
            analyze_program=None, merge=None, emit_run=None)
      merge(request, parts, questions) replaces ledger_merge.merge; emit_run(store_path, run) replaces store.emit_run.
  ledger_failures.JobFailure(code, stage, repo=None, exit=None, timed_out=False, errno=None, cause=None)
  ledger_failures.detail_of(failure) -> {"stage", "repo", "exit", "timedOut", "errno"}
  ledger_failures.job_failure_line(item_id, failure) -> "server: job <item> <code> <cause> at <stage>"
  ledger_failures.errno_name(error) -> "ENOENT" and so on, or None

The fakes, the `world` fixture and the helpers are task 19's (test_ledger_runner.py). A spawn failure is a stand-in
registry whose `launch` raises OSError. Each test names the wrong shortcut it catches.
"""

import errno
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_ledger_runner import (  # noqa: E402,F401  — `world` is a fixture
    ANALYZE_SECS, NEWER, OLDER, SCAN_SECS, jobs, world,
)

SECRET = "secret /Users/x/path"  # an exception message that must never reach stderr or ledger.json
DETAIL_KEYS = {"stage", "repo", "exit", "timedOut", "errno"}
SHORT_SCAN_SECS = 0.5  # the scan bound for the timeout test; the fake would sleep far longer
SCAN_EXITS_ONE = "import sys\nsys.stdin.read()\nsys.exit(1)\n"
SCAN_NEVER_ENDS = "import sys, time\nsys.stdin.read()\ntime.sleep(30)\n"
GIT_IDENTITY = {"GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
                "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}
SCAN_OUTCOMES = ("no_such_directory", "no_repository", "no_matching_repository", "no_such_worktree",
                 "nothing_matched")
NARROWING_FOR = {"no_matching_repository": {"repo": "zzz"}, "no_such_worktree": {"worktree": "no-such-wt"},
                 "nothing_matched": {"branch": "no-such-branch"}}  # the request fields that meet that outcome


# ------------------------------------------------------------------------------------------------ helpers

class FailingLaunch:
    """A registry that behaves as the real one except that its `fail_on`-th launch raises OSError(ENOENT)."""

    def __init__(self, real, fail_on):
        self._real, self._fail_on, self.launches = real, fail_on, []

    def __getattr__(self, name):
        return getattr(self._real, name)

    def launch(self, argv, **popen_kwargs):
        self.launches.append(argv)
        if len(self.launches) == self._fail_on:
            raise OSError(errno.ENOENT, SECRET)
        return self._real.launch(argv, **popen_kwargs)


def runner_with(world, scan_program, scan_secs=SCAN_SECS, **kwargs):
    """A runner over the world's fake analyzer and the given scan program (None: the real scan)."""
    return jobs().JobRunner(world.ledger, world.registry, world.store_path, ANALYZE_SECS, scan_secs,
                            scan_program=scan_program, analyze_program=str(world.analyzer_program), **kwargs)


def write_program(world, name, text):
    program = world.tmp_path / name
    program.write_text(text)
    return str(program)


def seed_waiting(world, item_id, **narrowing):
    """A waiting item as it sits in ledger.json, whose request carries the given repo, branch and worktree."""
    request = {"directory": world.directory, "repo": "", "branch": "", "worktree": ""}
    request.update(narrowing)
    run = world.state_module.run_id(request["directory"], request["repo"], request["branch"], request["worktree"])
    item = {"item": item_id, "state": "waiting", "queuedAt": OLDER, "request": request, "run": run,
            "error": None, "detail": None}

    def change(state):
        state["queue"].append(item)
        state["requests"][run] = dict(request)
        return state

    world.ledger.update(change)
    return item


def failed_detail(world, item_id, code):
    """The item's `detail` once it has failed with `code`; memory and ledger.json agree, no item is `running`,
    and the detail holds exactly the five keys of section 5.1."""
    memory, disk = world.item(item_id)
    assert memory["state"] == disk["state"] == "failed"
    assert memory["error"] == disk["error"] == code
    assert memory["detail"] is not None and set(memory["detail"]) == DETAIL_KEYS, memory["detail"]
    assert disk["detail"] == memory["detail"]
    assert [i["item"] for i in world.ledger.snapshot()["queue"] if i["state"] == "running"] == []
    return memory["detail"]


def store_bytes(world):
    return world.store_path.read_bytes() if world.store_path.exists() else None


def stderr_of(capsys):
    return capsys.readouterr().err


def isolated_git_env(world):
    """PATH and nothing else of the machine's, so the throwaway repositories and the scan meet no user config."""
    return {"PATH": os.environ["PATH"], "HOME": str(world.tmp_path), "LC_ALL": "C", "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CEILING_DIRECTORIES": str(world.tmp_path), **GIT_IDENTITY}


def make_git_repo(env, path):
    path.mkdir(parents=True)
    for args in (("init", "-q", "-b", "main"), ("commit", "-q", "--allow-empty", "-m", "fixture")):
        subprocess.run(["git", "-C", str(path), *args], env=env, check=True, capture_output=True)


# ------------------------------------------------------------------------------- 1. D12: merge and write

def test_d12_a_merge_that_raises_fails_the_item_writes_nothing_and_the_next_item_runs(world, capsys):
    """D12 merge_failed. Catches: a raise that escapes run_next or is marked internal_error, a store write after the
    failed merge, the message in stderr, an item left running, no last_job_end, and a runner that cannot go on."""
    import store
    world.families("alpha", "beta")
    store.emit_run(world.store_path, {"id": "rOLD0000000000001", "name": "previous"})
    before = store_bytes(world)
    first = world.queue("1212000000000001", OLDER)
    second = world.queue("1212000000000002", NEWER, repo="alpha")
    calls = []

    def merge(request, parts, questions):
        calls.append(len(parts))
        if len(calls) == 1:
            raise ValueError(SECRET)
        import ledger_merge
        return ledger_merge.merge(request, parts, questions)

    runner = world.runner(merge=merge)
    assert runner.run_next() == first["item"] and calls == [2], "both families reach the merge"
    assert failed_detail(world, first["item"], "merge_failed")["stage"] == "merge"
    assert store_bytes(world) == before, "a failed merge wrote to the store"
    err = stderr_of(capsys)
    assert "server: job %s merge_failed ValueError at merge" % first["item"] in err.splitlines()
    assert SECRET not in err and SECRET not in (world.store_dir / "ledger.json").read_text()
    assert runner.last_job_end is not None and runner.progress() is None
    assert runner.run_next() == second["item"], "the waiting item starts next"
    assert world.item(second["item"]) == (None, None) and world.stored_run(second["run"]) is not None


def test_d12_a_store_write_that_raises_enospc_fails_the_item_and_names_the_errno(world, capsys):
    """D12 store_write_failed. Catches: the OSError escaping, internal_error, a wrong stage, an errno left out of the
    detail, the message in stderr, and a store that changed."""
    import store
    world.families("alpha")
    store.emit_run(world.store_path, {"id": "rOLD0000000000001", "name": "previous"})
    before = store_bytes(world)
    item = world.queue("2323000000000001", OLDER)
    calls = []

    def emit_run(path, run):
        calls.append((path, run["id"]))
        raise OSError(errno.ENOSPC, SECRET)

    runner = world.runner(emit_run=emit_run)
    assert runner.run_next() == item["item"] and calls == [(world.store_path, item["run"])]
    detail = failed_detail(world, item["item"], "store_write_failed")
    assert detail["stage"] == "write" and detail["errno"] == "ENOSPC"
    assert store_bytes(world) == before
    err = stderr_of(capsys)
    assert "server: job %s store_write_failed ENOSPC at write" % item["item"] in err.splitlines()
    assert SECRET not in err
    assert runner.last_job_end is not None


# ------------------------------------------------------------------------------------- 3 and 4. D12: scan

def test_d12_a_scan_that_exits_one_at_job_time_fails_the_item_scan_failed(world):
    """D12 scan_failed. Catches: internal_error, a wrong stage, and an exit status left out of the detail."""
    world.families("alpha")
    item = world.queue("3434000000000001", OLDER)
    runner = runner_with(world, write_program(world, "scan_exits_one.py", SCAN_EXITS_ONE))
    assert runner.run_next() == item["item"]
    detail = failed_detail(world, item["item"], "scan_failed")
    assert detail["stage"] == "scan" and detail["exit"] == 1 and detail["timedOut"] is False


def test_a_scan_that_runs_past_its_bound_at_job_time_is_scan_timeout_with_timed_out_set(world):
    """Catches a timeout reported without `timedOut` in the detail (the spec leaves its stage and exit open)."""
    world.families("alpha")
    item = world.queue("3535000000000001", OLDER)
    runner = runner_with(world, write_program(world, "scan_never_ends.py", SCAN_NEVER_ENDS), SHORT_SCAN_SECS)
    assert runner.run_next() == item["item"]
    assert failed_detail(world, item["item"], "scan_timeout")["timedOut"] is True


@pytest.mark.parametrize("outcome", SCAN_OUTCOMES)
def test_d12_a_waiting_item_whose_request_now_meets_a_scan_outcome_fails_with_that_code(world, capsys, outcome):
    """D12, the real scan program. Catches a job that marks every scan outcome `internal_error` (the spec's named
    falsifier), another code for one of them, or a missing `scan` stage."""
    env = isolated_git_env(world)
    world.registry = jobs().ChildRegistry(env)
    if outcome not in ("no_such_directory", "no_repository"):
        make_git_repo(env, Path(world.directory) / "alpha")
    item = seed_waiting(world, "4545000000000001", **NARROWING_FOR.get(outcome, {}))
    if outcome == "no_such_directory":
        shutil.rmtree(world.directory)  # removed while the item waited
    runner = runner_with(world, None)
    assert runner.run_next() == item["item"]
    assert failed_detail(world, item["item"], outcome)["stage"] == "scan"
    assert "server: job %s %s at scan" % (item["item"], outcome) in stderr_of(capsys).splitlines()
    assert runner.last_job_end is not None and not world.store_path.exists()


# ------------------------------------------------------------------------------------- 5 and 6. D13: launch

def test_d13_an_analyzer_that_cannot_start_fails_the_whole_job_at_once(world, capsys):
    """D13. Catches: the OSError read as a family failure (and the second family still launched, or the job ending
    analysis_failed), a wrong stage, the wrong family's label, an errno left out, the message in stderr."""
    world.families("alpha", "beta")
    world.registry = FailingLaunch(world.registry, fail_on=2)  # launch 1 is the scan, launch 2 alpha's analyzer
    item = world.queue("5656000000000001", OLDER)
    runner = world.runner()
    assert runner.run_next() == item["item"]
    detail = failed_detail(world, item["item"], "launch_failed")
    assert detail["stage"] == "worktrees" and detail["repo"] == "alpha" and detail["errno"] == "ENOENT"
    assert len(world.registry.launches) == 2, "no second family's launch is attempted"
    assert not world.store_path.exists() and runner.last_job_end is not None and runner.progress() is None
    err = stderr_of(capsys)
    assert "server: job %s launch_failed ENOENT at worktrees" % item["item"] in err.splitlines()
    assert SECRET not in err


def test_d13_a_scan_that_cannot_start_at_job_time_fails_the_item_launch_failed(world, capsys):
    """D13, job-time half (the submit-time 500 is test_ledger_accept.py's). Catches the OSError escaping run_next, a
    wrong code or stage, an errno left out, and the message in stderr."""
    world.families("alpha")
    world.registry = FailingLaunch(world.registry, fail_on=1)
    item = world.queue("6767000000000001", OLDER)
    runner = world.runner()
    assert runner.run_next() == item["item"]
    detail = failed_detail(world, item["item"], "launch_failed")
    assert detail["stage"] == "scan" and detail["errno"] == "ENOENT"
    assert len(world.registry.launches) == 1 and runner.last_job_end is not None
    err = stderr_of(capsys)
    assert "server: job %s launch_failed ENOENT at scan" % item["item"] in err.splitlines()
    assert SECRET not in err


# ---------------------------------------------------------------------------------- 7. detail on every item

def test_every_family_failing_leaves_a_detail_with_all_five_keys_and_nothing_timed_out(world):
    """analysis_failed carries a `detail` too (an item that fails with `detail` None is the shortcut). Its stage,
    repo and exit are left open by the spec; a spawn that worked and an analyzer that ended on its own mean no
    timeout and no errno."""
    world.families("alpha", "beta")
    for label in ("alpha", "beta"):
        world.ctrl.analyzer(label, fail_after=0, exit=5, last="failed-" + label)
    item = world.queue("7878000000000001", OLDER)
    assert world.runner().run_next() == item["item"]
    detail = failed_detail(world, item["item"], "analysis_failed")
    assert detail["timedOut"] is False and detail["errno"] is None


# ------------------------------------------------------------------------------------ 8. the four new names

def test_job_failure_is_an_exception_that_carries_its_fields_and_defaults():
    """Catches a plain class (not raisable), a lost field, and a default other than None or False."""
    from ledger_failures import JobFailure
    full = JobFailure("merge_failed", "merge", repo="alpha", exit=3, timed_out=True, errno="ENOSPC", cause="ValueError")
    assert isinstance(full, Exception)
    assert (full.code, full.stage, full.repo, full.exit, full.timed_out, full.errno, full.cause) == (
        "merge_failed", "merge", "alpha", 3, True, "ENOSPC", "ValueError")
    bare = JobFailure("no_repository", "scan")
    assert (bare.repo, bare.exit, bare.timed_out, bare.errno, bare.cause) == (None, None, False, None, None)
    with pytest.raises(JobFailure) as caught:
        raise bare
    assert caught.value is bare


def test_detail_of_returns_exactly_the_five_keys_with_timed_out_spelled_timedOut():
    """Catches a snake_case key, an extra key (the cause, the code), a missing key, and a lost value."""
    from ledger_failures import JobFailure, detail_of
    failure = JobFailure("store_write_failed", "write", repo="alpha", exit=2, timed_out=True, errno="ENOSPC",
                         cause="ENOSPC")
    assert detail_of(failure) == {"stage": "write", "repo": "alpha", "exit": 2, "timedOut": True, "errno": "ENOSPC"}
    assert detail_of(JobFailure("no_repository", "scan")) == {
        "stage": "scan", "repo": None, "exit": None, "timedOut": False, "errno": None}


def test_job_failure_line_names_item_code_cause_and_stage_and_leaves_a_missing_cause_out():
    """Catches a line that has a message, a doubled space or `None` where the cause is missing, or a wrong order."""
    from ledger_failures import JobFailure, job_failure_line
    with_cause = JobFailure("merge_failed", "merge", cause="ValueError")
    assert job_failure_line("9f2c4a1b7d3e5f60", with_cause) == "server: job 9f2c4a1b7d3e5f60 merge_failed ValueError at merge"
    no_cause = JobFailure("no_repository", "scan")
    assert job_failure_line("9f2c4a1b7d3e5f60", no_cause) == "server: job 9f2c4a1b7d3e5f60 no_repository at scan"


def test_errno_name_is_the_symbolic_name_of_an_os_error_or_none():
    """Catches the number or the message used as the name, and a crash on an OSError that has no errno."""
    from ledger_failures import errno_name
    assert errno_name(OSError(errno.ENOENT, "x")) == "ENOENT"
    assert errno_name(OSError(errno.ENOSPC, "x")) == "ENOSPC"
    assert errno_name(OSError("no number")) is None
