"""Task 19 (docs/features/treko-ledger.spec.md, sections 5.4 steps 1 to 6 and 6.2; decision D45): the job runner,
part 1. Owns E4 and D7.

Pinned here, each through the public names D45 fixes (see the `API ASSUMED` block):
  * which item runs (the oldest waiting one), and that a closed registry marks nothing running;
  * step 1: the item is `running` in memory AND in ledger.json before the scan starts;
  * the success path: the run is in the store, the item is gone from the queue and from the file, `last_job_end`
    is set, `progress()` is None again;
  * E4: `total` is None until the scan ends, then 4N + 3; `done` moves by one per reported stage and by nothing
    between reports; a failed family's unreported stages count as done; the labels of section 6.2;
  * D7: a two-repo job whose second analyzer fails still succeeds, with ONE question naming that repo, the exit
    status and the analyzer's last stderr line; a job whose analyzers all fail writes nothing and fails
    `analysis_failed`;
  * the runner thread: `start()` plus `wake()` runs a queued item, and the thread leaves once the registry is closed.
Other failure codes (task 20), the stuck-job bounds (21), restart (22), stop and kill (23), the idle rule (25),
write-failure rules (26) and the hide list (28) are not tested here.

`ledger_jobs` is imported inside each test, never at module top, so a missing name fails each test on its own.
Each test names the wrong shortcut it catches.

FAKES. No real repository is analyzed. A fake scan prints canned section 4.4 JSON (the shape ledger_scan.scan
returns: outcome, families[{root, label, cards, questions}], questions, missed). A fake analyzer prints the four
`treko-progress <stage>` lines on stderr and a run holding the key set of ADR 0023 on stdout. Both read small
control files in a folder under tmp_path and can wait for a `go-<label>-<n>` file between stage lines, so the test
decides when each stage "finishes".

PROCESS SAFETY. Only the children the tests' own ChildRegistry started are ever killed (`kill_all` at teardown).
Every wait and join is bounded, helper threads are daemons and are joined, and a `release-all` file is written in
a `finally` so no fake waits on a dead test. The fakes wait at most FAKE_WAIT_SECS themselves. The environment is
passed to the children and never printed.
"""

import contextlib
import json
import os
import sys
import threading
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

# API ASSUMED (decision D45; the spec names behaviour, D45 names these identifiers). All in ledger_jobs:
#   JobRunner(ledger, registry, store_path, analyze_secs, scan_secs, report=None, scan_program=None,
#             analyze_program=None)
#       .run_next() -> item id or None     oldest waiting item (smallest queuedAt) run on the calling thread from
#                                          step 1 to its end; None when nothing waits or the registry is closed
#                                          (then nothing is marked running)
#       .start() / .wake()                 a daemon thread that calls run_next whenever woken and leaves its loop
#                                          once the registry is closed and it is woken
#       .progress() -> None | {"done": int, "total": int | None, "label": str}
#       .last_job_end -> None | number     monotonic seconds (server.py's clock) or wall seconds; either is accepted
#       report(stage)                      called once per `treko-progress <stage>` line; the default records it
# The two *_program arguments are script paths run with sys.executable. The scan gets the request as JSON on stdin
# (run_scan's contract); the analyzer gets argv [primary checkout, "--progress", ("--card", path)*].
# The runner calls `ledger_merge.merge(...)` and `store.emit_run(...)` as module attributes at call time (so a test
# can wrap them); it does not bind them with `from ... import`.
# Readings the tests choose (the spec is silent): "scanning <dir>" shows the directory as the request holds it, or
# with the home folder collapsed to ~ (ledger_state.run_dir); with one family the label is "<label>: <stage label>".

WAIT_SECS = 20  # the longest a test waits for a state the runner should reach
JOIN_SECS = 30
FAKE_WAIT_SECS = 30
ANALYZE_SECS = SCAN_SECS = 60  # the bounds handed to the runner; far above any fake's run time
POLL_SECS = 0.02
QUIET_SECS = 0.3  # how long "nothing moves" is observed for
STAGES = ("worktrees", "branches", "cards", "order")
STAGE_LABELS = ("reading worktrees", "reading branches", "reading cards", "deriving merge order")
LEDGER_FILE = "ledger.json"
OLDER, NEWER = "2026-11-03T09:00:00Z", "2026-11-03T10:00:00Z"
SECOND_EXIT, LAST_LINE, NOISE_LINE = 17, "boom-second", "earlier-noise"

CONTROL_HELPERS = '''
import json, os, sys, time
CTRL = __CTRL__
def wait_for(name):
    deadline = time.time() + __WAIT__
    while time.time() < deadline:
        if os.path.exists(os.path.join(CTRL, name)) or os.path.exists(os.path.join(CTRL, "release-all")):
            return
        time.sleep(0.02)
def read_json(name, default):
    path = os.path.join(CTRL, name)
    if not os.path.exists(path):
        return default
    with open(path) as handle:
        return json.load(handle)
'''

FAKE_SCAN = CONTROL_HELPERS + '''
request = json.load(sys.stdin)
with open(os.path.join(CTRL, "scan-requests.jsonl"), "a") as handle:
    handle.write(json.dumps(request) + "\\n")
with open(__LEDGER__) as handle:  # what ledger.json held when the scan started
    seen = handle.read()
with open(os.path.join(CTRL, "scan-saw-ledger.json"), "w") as handle:
    handle.write(seen)
open(os.path.join(CTRL, "scan-started"), "w").close()
config = read_json("scan.json", {})
if config.get("hold"):
    wait_for("scan-release")
print(json.dumps({"outcome": "ok", "families": read_json("families.json", []), "questions": [],
                  "missed": {"unreadable": 0, "depthLimit": 0, "symlinks": 0}}))
'''

FAKE_ANALYZER = CONTROL_HELPERS + '''
STAGES = __STAGES__
root = sys.argv[1]
label = os.path.basename(root)
with open(os.path.join(CTRL, "argv-" + label + ".json"), "w") as handle:
    json.dump(sys.argv[1:], handle)
config = read_json("analyzer-" + label + ".json", {})

def fail():
    for line in config.get("noise", []):
        sys.stderr.write(line + "\\n")
    sys.stderr.write(config.get("last", "failed") + "\\n")
    sys.stderr.flush()
    sys.exit(config["exit"])

for number, stage in enumerate(STAGES, 1):
    if config.get("fail_after") == number - 1:
        fail()
    if config.get("gated"):
        wait_for("go-%s-%d" % (label, number))
    sys.stderr.write("treko-progress %s\\n" % stage)
    sys.stderr.flush()
if config.get("fail_after") == len(STAGES):
    fail()
branch = {"repo": label, "branch": "main", "wt": root, "ahead": 0, "behind": 0, "dirty": False,
          "note": "clean", "tone": "ok", "last": "now"}
print(json.dumps({"id": "analyzer-id", "name": label, "dir": root, "analyzedAt": "",
                  "features": [{"name": "card-" + label, "meta": "0/1", "tasks": []}], "waves": [],
                  "constraints": [], "branches": [branch], "graph": {"nodes": [], "edges": []}, "kanban": [],
                  "questions": []}))
'''


def jobs():
    """The module under test, imported at call time so each test fails on its own while a name is missing."""
    import ledger_jobs
    return ledger_jobs


# ------------------------------------------------------------------------------------------------ the world

class Control:
    """The folder the fakes read their instructions from and report into."""

    def __init__(self, folder):
        self.folder = folder
        folder.mkdir()

    def write_json(self, name, value):
        (self.folder / name).write_text(json.dumps(value))

    def touch(self, name):
        (self.folder / name).write_text("")

    def exists(self, name):
        return (self.folder / name).exists()

    def read_json(self, name):
        return json.loads((self.folder / name).read_text())

    def scan_requests(self):
        path = self.folder / "scan-requests.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def go(self, label, number):
        self.touch("go-%s-%d" % (label, number))

    def analyzer(self, label, **config):
        self.write_json("analyzer-%s.json" % label, config)

    def release_all(self):
        self.touch("release-all")


def fill(template, **values):
    for key, value in values.items():
        template = template.replace("__%s__" % key, value)
    return template


class World:
    """A ledger with a store folder, a real ChildRegistry, fake programs and a store path, all under tmp_path."""

    def __init__(self, tmp_path):
        import ledger_state
        self.state_module = ledger_state
        self.store_dir = tmp_path / "store"
        self.store_path = self.store_dir / "tracker-data.js"
        self.directory = str((tmp_path / "scanned").resolve())
        Path(self.directory).mkdir()
        self.ledger = ledger_state.Ledger(store_dir=self.store_dir)
        self.registry = None
        self.tmp_path = tmp_path
        self.ctrl = Control(tmp_path / "control")
        ctrl_text = repr(str(self.ctrl.folder))
        fakes = tmp_path / "fakes"
        fakes.mkdir()
        self.scan_program = fakes / "fake_scan.py"
        self.scan_program.write_text(fill(FAKE_SCAN, CTRL=ctrl_text, WAIT=str(FAKE_WAIT_SECS),
                                          LEDGER=repr(str(self.store_dir / LEDGER_FILE))))
        self.analyzer_program = fakes / "fake_analyzer.py"
        self.analyzer_program.write_text(fill(FAKE_ANALYZER, CTRL=ctrl_text, WAIT=str(FAKE_WAIT_SECS),
                                              STAGES=repr(list(STAGES))))
        self.roots = {}
        self.cards = {}

    def families(self, *labels):
        """The families the fake scan reports: one primary checkout folder and one card copy each."""
        listed = []
        for label in labels:
            root = self.tmp_path / "repos" / label
            card = root / "docs" / "features" / ("card-%s.md" % label)
            card.parent.mkdir(parents=True)
            card.write_text("card\n")
            self.roots[label], self.cards[label] = str(root), str(card)
            listed.append({"root": str(root), "label": label, "cards": [str(card)], "questions": []})
        self.ctrl.write_json("families.json", listed)

    def queue(self, item_id, queued_at, repo=""):
        """An item as task 14 would queue it: a waiting item plus its `requests` entry (section 5.1)."""
        request = {"directory": self.directory, "repo": repo, "branch": "", "worktree": ""}
        item = {"item": item_id, "state": "waiting", "queuedAt": queued_at, "request": request,
                "run": self.state_module.run_id(self.directory, repo, "", ""), "error": None, "detail": None}

        def change(state):
            state["queue"].append(item)
            state["requests"][item["run"]] = dict(request)
            return state

        self.ledger.update(change)
        return item

    def runner(self, **kwargs):
        return jobs().JobRunner(self.ledger, self.registry, self.store_path, ANALYZE_SECS, SCAN_SECS,
                                scan_program=str(self.scan_program),
                                analyze_program=str(self.analyzer_program), **kwargs)

    def item(self, item_id):
        """(item in memory, item in ledger.json); either is None when the item is not queued."""
        memory = [i for i in self.ledger.snapshot()["queue"] if i["item"] == item_id]
        disk = [i for i in self.disk()["queue"] if i["item"] == item_id]
        return (memory[0] if memory else None), (disk[0] if disk else None)

    def disk(self):
        return json.loads((self.store_dir / LEDGER_FILE).read_text())

    def stored_run(self, run_id):
        import store
        return store.get_run(store.read_store(self.store_path), run_id)


@pytest.fixture
def world(tmp_path):
    built = World(tmp_path)
    built.registry = jobs().ChildRegistry(dict(os.environ))
    yield built
    built.ctrl.release_all()
    built.registry.close()
    built.registry.kill_all()


class Job:
    """`runner.run_next()` on a daemon thread, so the test can look at the runner while it works."""

    def __init__(self, runner):
        self.box = {}
        self.thread = threading.Thread(target=self._run, args=(runner,), daemon=True)
        self.thread.start()

    def _run(self, runner):
        try:
            self.box["id"] = runner.run_next()
        except BaseException as error:  # noqa: BLE001 - handed back to the test thread by result()
            self.box["error"] = error

    def result(self, secs=JOIN_SECS):
        self.thread.join(secs)
        if self.thread.is_alive():
            pytest.fail("run_next was still running after %d s" % secs)
        if "error" in self.box:
            raise self.box["error"]
        return self.box["id"]


@contextlib.contextmanager
def running(world, runner):
    """A Job whose fakes are released and whose thread is joined whatever the test did."""
    job = Job(runner)
    try:
        yield job
    finally:
        world.ctrl.release_all()
        job.thread.join(JOIN_SECS)


def run_to_end(world, runner):
    with running(world, runner) as job:
        return job.result()


def wait_until(check, what, secs=WAIT_SECS):
    deadline = time.monotonic() + secs
    while True:
        value = check()
        if value:
            return value
        if time.monotonic() > deadline:
            pytest.fail("never happened within %d s: %s" % (int(secs), what))
        time.sleep(POLL_SECS)


def scanning_labels(world):
    return {"scanning " + world.directory, "scanning " + world.state_module.run_dir(world.directory)}


def progress_where(runner, predicate, what):
    def check():
        seen = runner.progress()
        return seen if seen is not None and predicate(seen) else None
    return wait_until(check, what)


def assert_still(runner, expected):
    """No report arrived, so the record does not move: sampled twice, with time passing (criterion E3's reading)."""
    first = runner.progress()
    time.sleep(QUIET_SECS)
    assert first == expected and runner.progress() == expected, "progress moved with no stage report: %r" % (first,)


# ------------------------------------------------------------------------------------- which item runs

def test_nothing_waiting_returns_none_and_a_closed_registry_marks_nothing_running(world):
    """A runner that always picks the first queue entry would run the failed and interrupted ones; one that
    skips the closed check would mark the item running and have the scan refused (section 5.4 step 1)."""
    world.families("alpha")
    runner = world.runner()
    assert runner.run_next() is None and runner.progress() is None and runner.last_job_end is None
    world.queue("aaaa000000000001", OLDER)
    world.queue("aaaa000000000002", NEWER)

    def settled(state):
        state["queue"][0]["state"], state["queue"][1]["state"] = "failed", "interrupted"
        return state
    world.ledger.update(settled)
    assert runner.run_next() is None, "a failed or an interrupted item is not waiting"
    assert not world.ctrl.scan_requests()

    world.queue("aaaa000000000003", NEWER)
    world.registry.close()
    assert runner.run_next() is None, "a closed registry starts no job"
    memory, disk = world.item("aaaa000000000003")
    assert memory["state"] == disk["state"] == "waiting", "closed registry: the item must stay waiting"
    assert not world.ctrl.scan_requests() and runner.progress() is None


def test_the_oldest_waiting_item_runs_first(world):
    """Falsifier: a runner that takes the first entry of the list (the newer item, queued first here) or the last."""
    world.families("alpha")
    newer = world.queue("bbbb000000000001", NEWER, repo="alpha")
    older = world.queue("bbbb000000000002", OLDER)
    assert run_to_end(world, world.runner()) == older["item"]
    assert world.ctrl.scan_requests() == [older["request"]], "the scan ran for the wrong item"
    assert world.item(older["item"]) == (None, None)
    memory, disk = world.item(newer["item"])
    assert memory["state"] == disk["state"] == "waiting"


# ------------------------------------------------------------------------------------------ step 1

def test_the_item_is_running_in_memory_and_on_disk_before_the_scan_starts(world):
    """Falsifier: a runner that marks the item running only after the scan (the scan's own copy of ledger.json
    would still say waiting), or marks it in memory but writes the file later (section 5.6, write 1)."""
    world.families("alpha")
    world.ctrl.write_json("scan.json", {"hold": True})
    item = world.queue("cccc000000000001", OLDER)
    runner = world.runner()
    with running(world, runner) as job:
        wait_until(lambda: world.ctrl.exists("scan-started"), "the fake scan started")
        memory, disk = world.item(item["item"])
        assert memory["state"] == "running" and disk["state"] == "running"
        assert runner.progress() is not None
        saw = json.loads((world.ctrl.folder / "scan-saw-ledger.json").read_text())
        assert [i["state"] for i in saw["queue"]] == ["running"], "the scan started before the file said running"
        world.ctrl.touch("scan-release")
        assert job.result() == item["item"]


# --------------------------------------------------------------------------------------- the success path

def test_one_family_job_stores_the_run_removes_the_item_and_records_the_end(world):
    """Falsifier: a runner that skips emit_run, leaves the item in the queue or the file, never sets
    last_job_end, or leaves a stale progress record; and one that omits --progress or the chosen card copies."""
    world.families("alpha")
    item = world.queue("dddd000000000001", OLDER)
    runner = world.runner()
    before_mono, before_wall = time.monotonic(), time.time()
    assert run_to_end(world, runner) == item["item"]
    run = world.stored_run(item["run"])
    assert run is not None and run["id"] == item["run"], "the store has no run under the item's run id"
    assert [f["name"] for f in run["features"]] == ["card-alpha"]
    assert world.item(item["item"]) == (None, None), "the item must leave the queue in memory and on disk"
    ended = runner.last_job_end
    assert isinstance(ended, (int, float)) and (
        before_mono <= ended <= time.monotonic() or before_wall <= ended <= time.time()), ended
    assert runner.progress() is None
    argv = world.ctrl.read_json("argv-alpha.json")
    assert argv[0] == world.roots["alpha"] and "--progress" in argv
    assert argv[argv.index("--card") + 1] == world.cards["alpha"]


# ------------------------------------------------------------------------------------------------ E4

def test_e4_two_families_total_is_null_then_eleven_and_done_moves_only_on_a_report(world):
    """E4. Falsifier: a total known before the scan ends; 4N + 3 miscounted (8 or 12); a bar that moves between
    reports (timer, or the whole family at its exit); done counted from 0 after the scan; a label that is not the
    stage now running."""
    world.families("alpha", "beta")
    world.ctrl.write_json("scan.json", {"hold": True})
    for label in ("alpha", "beta"):
        world.ctrl.analyzer(label, gated=True)
    world.queue("eeee000000000001", OLDER)
    runner = world.runner()
    with running(world, runner) as job:
        wait_until(lambda: world.ctrl.exists("scan-started"), "the fake scan started")
        scanning = runner.progress()
        assert scanning["done"] == 0 and scanning["total"] is None and scanning["label"] in scanning_labels(world)
        world.ctrl.touch("scan-release")
        after_scan = progress_where(runner, lambda p: p["total"] is not None, "the total after the scan")
        assert after_scan == {"done": 1, "total": 11, "label": "alpha (1 of 2): reading worktrees"}
        assert_still(runner, after_scan)
        steps = [("alpha", n, "alpha (1 of 2): " + STAGE_LABELS[n]) for n in (1, 2, 3)]
        steps += [("alpha", 4, "beta (2 of 2): reading worktrees")]
        steps += [("beta", n, "beta (2 of 2): " + STAGE_LABELS[n]) for n in (1, 2, 3)]
        for done, (label, number, expected_label) in enumerate(steps, 2):
            world.ctrl.go(label, number)  # the fake prints that stage's line now
            expected = {"done": done, "total": 11, "label": expected_label}
            assert progress_where(runner, lambda p: p["done"] >= done, "done reaching %d" % done) == expected
            assert_still(runner, expected)
        world.ctrl.go("beta", 4)
        assert job.result() == "eeee000000000001"


def test_e4_one_family_total_is_seven_and_the_label_drops_the_count(world):
    """E4 with N = 1. Falsifier: a label that always says "(1 of 1)", or a total of 4N + 4 or 8."""
    world.families("alpha")
    world.ctrl.analyzer("alpha", gated=True)
    world.queue("ffff000000000001", OLDER)
    runner = world.runner()
    with running(world, runner) as job:
        first = progress_where(runner, lambda p: p["total"] is not None, "the total after the scan")
        assert first == {"done": 1, "total": 7, "label": "alpha: reading worktrees"}
        for number in (1, 2, 3):
            world.ctrl.go("alpha", number)
            expected = {"done": 1 + number, "total": 7, "label": "alpha: " + STAGE_LABELS[number]}
            assert progress_where(runner, lambda p: p["done"] > number, "one more stage") == expected
            assert_still(runner, expected)
        world.ctrl.go("alpha", 4)
        job.result()


def test_e4_a_failed_familys_unreported_stages_count_as_done_at_the_merge_and_the_write(world):
    """E4. The second analyzer reports one stage, then exits non-zero. Falsifier: a runner that counts only reported
    stages (done 6 of 11 at the merge) or none of the failed family's (5)."""
    import ledger_merge
    import store
    world.families("alpha", "beta")
    world.ctrl.analyzer("beta", fail_after=1, exit=3, last="beta-stopped")
    world.queue("1111000000000001", OLDER)
    runner = world.runner()
    seen = {}
    real_merge, real_emit = ledger_merge.merge, store.emit_run

    def merge_spy(*args, **kwargs):
        seen["merge"] = runner.progress()
        return real_merge(*args, **kwargs)

    def emit_spy(*args, **kwargs):
        seen["write"] = runner.progress()
        return real_emit(*args, **kwargs)

    patch = pytest.MonkeyPatch()
    patch.setattr(ledger_merge, "merge", merge_spy)
    patch.setattr(store, "emit_run", emit_spy)
    try:
        run_to_end(world, runner)
    finally:
        patch.undo()
    assert seen["merge"] == {"done": 9, "total": 11, "label": "merging the runs"}
    assert seen["write"] == {"done": 10, "total": 11, "label": "writing the store"}


def test_the_report_handler_gets_each_stage_once_per_family_in_order(world):
    """Falsifier: a runner that parses the lines but never calls the handler, calls it with the whole line instead
    of the stage name, or calls it more than once per line."""
    world.families("alpha", "beta")
    world.queue("2222000000000001", OLDER)
    stages = []
    run_to_end(world, world.runner(report=stages.append))
    assert stages == list(STAGES) * 2


# ------------------------------------------------------------------------------------------------ D7

def test_d7_a_second_analyzer_that_fails_still_writes_the_first_repo_with_one_question(world):
    """D7. Falsifier: a job that fails whole when one family fails (no run, item failed), a run that carries the
    failed family's content, no question, a question that omits the repo, the status or the last stderr line, one
    that dumps the whole stderr (including the earlier noise and the progress line), or a second question."""
    world.families("alpha", "beta")
    world.ctrl.analyzer("beta", fail_after=1, exit=SECOND_EXIT, noise=[NOISE_LINE], last=LAST_LINE)
    item = world.queue("3333000000000001", OLDER)
    assert run_to_end(world, world.runner()) == item["item"]
    assert world.item(item["item"]) == (None, None), "a partly failed job still succeeds"
    run = world.stored_run(item["run"])
    assert [f["name"] for f in run["features"]] == ["card-alpha"], "the run holds the first repo's content only"
    assert [b["repo"] for b in run["branches"]] == ["alpha"]
    assert len(run["questions"]) == 1, run["questions"]
    question = run["questions"][0]
    assert "`beta`" in question["q"]  # section 7.2: "Why could `<label>` not be analyzed?"
    assert str(SECOND_EXIT) in question["ctx"] and LAST_LINE in question["ctx"]
    assert NOISE_LINE not in question["ctx"] and "treko-progress" not in question["ctx"], question["ctx"]


def test_d7_every_analyzer_failing_writes_nothing_and_fails_the_item(world):
    """D7. Falsifier: a runner that emits an empty run (the store changes), removes the item, uses another code
    (internal_error, merge_failed), or forgets last_job_end on this end."""
    import store
    world.families("alpha", "beta")
    for label in ("alpha", "beta"):
        world.ctrl.analyzer(label, fail_after=0, exit=5, last="failed-" + label)
    store.emit_run(world.store_path, {"id": "rOLD0000000000001", "name": "previous"})
    before = world.store_path.read_bytes()
    item = world.queue("4444000000000001", OLDER)
    runner = world.runner()
    run_to_end(world, runner)
    assert world.store_path.read_bytes() == before, "a job whose analyzers all failed wrote to the store"
    memory, disk = world.item(item["item"])
    assert memory["state"] == disk["state"] == "failed"
    assert memory["error"] == disk["error"] == "analysis_failed"
    assert runner.last_job_end is not None and runner.progress() is None


# --------------------------------------------------------------------------------------------- thread

def test_the_runner_thread_runs_a_woken_item_and_leaves_once_the_registry_is_closed(world):
    """Falsifier: a thread that never reads the queue on wake(), runs only items queued before start(), ignores
    the closed registry (the second item would be marked running and the scan launched), or never ends. D45 gives
    no handle to the thread, so it is found as the new live thread start() creates."""
    world.families("alpha")
    runner = world.runner()
    before = set(threading.enumerate())
    started = []
    try:
        runner.start()
        started = [t for t in threading.enumerate() if t not in before]
        assert started and all(t.daemon for t in started), "start() must create a daemon thread"
        first = world.queue("5555000000000001", OLDER)
        runner.wake()
        wait_until(lambda: world.stored_run(first["run"]) and world.item(first["item"]) == (None, None),
                   "the woken item stored and removed")
        world.registry.close()
        second = world.queue("5555000000000002", NEWER, repo="alpha")
        runner.wake()
        wait_until(lambda: not any(t.is_alive() for t in started), "the runner thread leaving after close + wake")
        memory, disk = world.item(second["item"])
        assert memory["state"] == disk["state"] == "waiting", "a closed registry must leave the item waiting"
        assert len(world.ctrl.scan_requests()) == 1, "the thread started a job after the registry closed"
    finally:
        world.registry.close()
        world.ctrl.release_all()
        runner.wake()
        for thread in started:
            thread.join(JOIN_SECS)
