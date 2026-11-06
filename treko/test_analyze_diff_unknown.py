"""E7: a diff git cannot compute shows "diff unknown" (docs/features/treko-ledger.spec.md, §11 E7).

Lives in its own file, not in test_analyze_options.py, which is at its line cap; it reuses that
file's fixture class and helpers by importing the module (never `import *`, so none of its tests
are collected a second time here).

Each fixture is a `--filter=blob:none` clone of a fixture origin served over file://. A local
branch in the clone points at a commit whose changed blob was never fetched, and both analyzers
run with GIT_NO_LAZY_FETCH=1, so git cannot fetch it and `git diff --shortstat` exits non-zero.
The tests assert that precondition first.

Three parts: the branch a card with a task names (value shown, one question), a second branch no
card names (nothing shown, no question: U12), and a branch only a card with no tasks names
(nothing shown, no question: D28). Falsifiers: the baseline analyzer run through the same checks;
fetching the object so the two analyzers agree; and synthetic outputs of analyzers that ask too
often, run through the same checks.

Run:  see §15 of the spec (the pinned `uv run ... pytest` command).
"""

import copy
import json
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "hooks" / "lib"))

import test_analyze_options as base  # noqa: E402

NO_LAZY_FETCH = "GIT_NO_LAZY_FETCH"
GIT_MESSAGE_FRAGMENT = "promisor remote"  # what git says when it may not fetch the object
DIFF_UNKNOWN = "diff unknown"
CARD, NAMED = "alpha", "feat/alpha"  # a card with tasks, and the branch it names
ORPHAN = "feat/orphan"  # a failing branch no card names
EMPTY_CARD, EMPTY_NAMED = "gamma", "feat/gamma"  # a card with no task lines, and its branch
TASKS = ["- [ ] 1 — first", "- [ ] 2 — second"]


# --------------------------------------------------------------------------------- fixtures


def _blobless_clone(tmp_path, name, cards, branches):
    """Origin with `cards` on main and one commit adding a file on each of `branches`; then a
    blobless clone with a local branch for each, whose changed blob is missing."""
    root = tmp_path / name
    (root / "home").mkdir(parents=True)
    fx = base.Fixture(root)
    origin = root / "origin"
    fx.root = origin
    fx.init()
    fx.git("config", "uploadpack.allowFilter", "true")
    for card_name, branch, tasks in cards:
        fx.card(card_name, branch, tasks)
    fx.commit_all("cards")
    for branch in branches:
        fx.git("checkout", "-q", "-b", branch)
        fx.write("%s.txt" % branch.replace("/", "-"), "work on %s\n" % branch)
        fx.commit_all("work on %s" % branch)
        fx.git("checkout", "-q", base.BASE_BRANCH)
    clone = root / "repo"
    base._run(["git", "clone", "-q", "--filter=blob:none", "file://%s" % origin, str(clone)],
              fx.env, root)
    fx.root = clone
    for branch in branches:
        base._run(["git", "-C", str(clone), "branch", branch, "origin/%s" % branch], fx.env, root)
    return fx


@pytest.fixture
def named_and_orphan(tmp_path):
    """Parts 1 and 2: one failing branch a card with tasks names, one that no card names."""
    return _blobless_clone(tmp_path, "named_and_orphan", [(CARD, NAMED, TASKS)], [NAMED, ORPHAN])


@pytest.fixture
def only_an_empty_card(tmp_path):
    """Part 3: one failing branch, named by one card whose checklist has no task lines."""
    return _blobless_clone(tmp_path, "only_an_empty_card", [(EMPTY_CARD, EMPTY_NAMED, [])],
                           [EMPTY_NAMED])


def _nolazy_env(fx):
    env = base._git_env(fx.base / "home")
    env[NO_LAZY_FETCH] = "1"
    return env


def _git_here(fx, env, *args):
    return base._run(["git", "-C", str(fx.root), *args], env, fx.base, check=False)


def _assert_diff_fails(fx, branch):
    """The fixture's own precondition. Returns git's message line, for the context check."""
    env = _nolazy_env(fx)
    diff = _git_here(fx, env, "diff", "--shortstat", "%s...%s" % (base.BASE_BRANCH, branch))
    assert diff.returncode != 0, "git diff --shortstat works for %s: %r" % (branch, diff.stdout)
    missing = _git_here(fx, env, "rev-list", "--objects", "--missing=print", "--all")
    assert missing.returncode == 0, missing.stderr
    assert any(l.startswith("?") for l in missing.stdout.decode().splitlines()), \
        "no missing object is reported"
    lines = [l.strip() for l in diff.stderr.decode().splitlines() if GIT_MESSAGE_FRAGMENT in l]
    assert lines, "git did not say why: %r" % diff.stderr
    return lines[0]


def _fetch_by_plain_diff(fx, branches):
    """One plain `git diff` per branch, without the setting: git fetches the blob it lacks."""
    env = base._git_env(fx.base / "home")
    for branch in branches:
        diff = _git_here(fx, env, "diff", "--shortstat", "%s...%s" % (base.BASE_BRANCH, branch))
        assert diff.returncode == 0, diff.stderr
        again = _git_here(fx, _nolazy_env(fx), "diff", "--shortstat",
                          "%s...%s" % (base.BASE_BRANCH, branch))
        assert again.returncode == 0, "the object is still missing for %s" % branch


def _run_both(fx, tmp_path):
    """(new, baseline), each (stdout, stderr, exit status), both under GIT_NO_LAZY_FETCH=1."""
    env = _nolazy_env(fx)
    baseline = base._materialize_baseline(tmp_path / "baseline")

    def run(script):
        done = base._run([base.RUNTIME_PYTHON, str(script), str(fx.root)], env, fx.base,
                         check=False)
        return done.stdout, done.stderr, done.returncode

    return run(base.NEW_ANALYZER), run(baseline)


# ------------------------------------------------------------------------------------ checks


def _feature(run, name):
    return next(f for f in run["features"] if f["name"] == name)


def _branch(run, name):
    return next(b for b in run["branches"] if b["branch"] == name)


def _runs(new_out, old_out):
    assert new_out[2] == 0 and old_out[2] == 0, (new_out[1], old_out[1])
    return json.loads(new_out[0]), json.loads(old_out[0])


def _check_diff_unknown(new_out, old_out, git_line):
    """Part 1: every task of the card says "diff unknown"; one question, last; all else equal."""
    new, old = _runs(new_out, old_out)
    tasks = _feature(new, CARD)["tasks"]
    assert len(tasks) >= 1
    for task in tasks:
        assert task["d"]["diff"] == DIFF_UNKNOWN
    assert _branch(old, NAMED)["ahead"] == 1, "the branch must be ahead, or `ahead` proves nothing"
    assert len(new["questions"]) == len(old["questions"]) + 1
    extra = new["questions"][-1]
    assert NAMED in extra["q"], extra
    assert git_line in extra["ctx"], extra
    expected = copy.deepcopy(new)
    for task, before in zip(_feature(expected, CARD)["tasks"], _feature(old, CARD)["tasks"]):
        task["d"]["diff"] = before["d"]["diff"]
    expected["questions"] = expected["questions"][:-1]
    assert json.dumps(expected) == json.dumps(old)


def _check_orphan_is_silent(new_out, old_out):
    """Part 2: the branch no card names adds no question and its failed diff shows nowhere."""
    new, old = _runs(new_out, old_out)
    assert len(new["questions"]) == len(old["questions"]) + 1, \
        "questions: %d, expected the baseline's %d plus exactly one" % (
            len(new["questions"]), len(old["questions"]))
    for question in new["questions"]:
        assert ORPHAN not in question["q"] and ORPHAN not in question["ctx"], question
    assert _branch(new, ORPHAN) == _branch(old, ORPHAN)
    assert new_out[0].decode().count(ORPHAN) == old_out[0].decode().count(ORPHAN) >= 1
    shown = [t for f in new["features"] for t in f["tasks"] if t["d"]["diff"] == DIFF_UNKNOWN]
    assert len(shown) == len(_feature(new, CARD)["tasks"])  # only the named card's tasks


def _check_card_without_tasks(new_out, old_out):
    """Part 3: the card is listed with no tasks, nothing is asked, and the output is unchanged."""
    new, old = _runs(new_out, old_out)
    assert _feature(new, EMPTY_CARD)["tasks"] == []
    assert _branch(old, EMPTY_NAMED)["ahead"] == 1
    assert DIFF_UNKNOWN not in new_out[0].decode()
    assert len(new["questions"]) == len(old["questions"]), "a question was added"
    assert new_out == old_out


# ---------------------------------------------------------------------------------- the tests


def test_e7_part1_a_failed_diff_shows_diff_unknown_and_asks_once(tmp_path, named_and_orphan):
    fx = named_and_orphan
    git_line = _assert_diff_fails(fx, NAMED)
    new_out, old_out = _run_both(fx, tmp_path)
    _check_diff_unknown(new_out, old_out, git_line)


def test_e7_part2_a_branch_no_card_names_adds_no_question(tmp_path, named_and_orphan):
    fx = named_and_orphan
    _assert_diff_fails(fx, NAMED)
    _assert_diff_fails(fx, ORPHAN)
    new_out, old_out = _run_both(fx, tmp_path)
    _check_orphan_is_silent(new_out, old_out)


def test_e7_part3_a_card_without_tasks_adds_no_question_and_no_value(tmp_path, only_an_empty_card):
    """Passes today by design: D28 says the output is the baseline's, byte for byte."""
    fx = only_an_empty_card
    _assert_diff_fails(fx, EMPTY_NAMED)
    new_out, old_out = _run_both(fx, tmp_path)
    _check_card_without_tasks(new_out, old_out)


def test_e7_falsifier_the_baseline_gives_empty_and_no_question(tmp_path, named_and_orphan):
    fx = named_and_orphan
    git_line = _assert_diff_fails(fx, NAMED)
    _, old_out = _run_both(fx, tmp_path)
    old = json.loads(old_out[0])
    assert {t["d"]["diff"] for t in _feature(old, CARD)["tasks"]} == {""}  # what must be caught
    with pytest.raises(AssertionError, match="'' == 'diff unknown'"):
        _check_diff_unknown(old_out, old_out, git_line)
    with pytest.raises(AssertionError, match="expected the baseline's"):
        _check_orphan_is_silent(old_out, old_out)


@pytest.mark.parametrize("which", ["named_and_orphan", "only_an_empty_card"])
def test_e7_once_the_object_is_fetched_the_analyzers_agree(tmp_path, request, which):
    fx = request.getfixturevalue(which)
    branches = (NAMED, ORPHAN) if which == "named_and_orphan" else (EMPTY_NAMED,)
    for branch in branches:
        _assert_diff_fails(fx, branch)
    _fetch_by_plain_diff(fx, branches)
    new_out, old_out = _run_both(fx, tmp_path)
    assert new_out[2] == 0 and new_out == old_out
    assert DIFF_UNKNOWN not in new_out[0].decode()
    if which == "named_and_orphan":  # the value now shows, so the agreement is not vacuous
        diffs = {t["d"]["diff"] for t in _feature(json.loads(new_out[0]), CARD)["tasks"]}
        assert diffs and all(d.startswith("+1 ") for d in diffs), diffs


# ------------------------------------------------- falsifier (c): analyzers that ask too often


def _synthetic(old_out, asked, feature=None, git_line=GIT_MESSAGE_FRAGMENT):
    """What an analyzer would print if it did what E7 says for `feature`, plus a question for each
    branch in `asked`: the baseline's run with the value set and the questions appended."""
    run = json.loads(old_out[0])
    if feature:
        for task in _feature(run, feature)["tasks"]:
            task["d"]["diff"] = DIFF_UNKNOWN
    for branch in asked:
        run["questions"].append({
            "id": "q%d" % (len(run["questions"]) + 1),
            "q": "Why could git not compute the diff of `%s`?" % branch,
            "ctx": "git said: %s" % git_line,
            "resolved": False})
    return json.dumps(run).encode(), b"", 0


def test_e7_falsifier_asking_for_every_failed_diff_adds_two_questions_not_one(
        tmp_path, named_and_orphan):
    """Built without a stub analyzer: a synthetic output stands in for one that asks about every
    failing branch, since a real stub would need the very change this task adds."""
    fx = named_and_orphan
    git_line = _assert_diff_fails(fx, NAMED)
    _, old_out = _run_both(fx, tmp_path)
    right = _synthetic(old_out, [NAMED], CARD, git_line)
    _check_orphan_is_silent(right, old_out)  # the checks can pass on the right shape
    _check_diff_unknown(right, old_out, git_line)
    wrong = _synthetic(old_out, [NAMED, ORPHAN], CARD, git_line)
    assert len(json.loads(wrong[0])["questions"]) == len(json.loads(old_out[0])["questions"]) + 2
    with pytest.raises(AssertionError, match="expected the baseline's"):
        _check_orphan_is_silent(wrong, old_out)


def test_e7_falsifier_asking_for_every_named_branch_changes_the_output(
        tmp_path, only_an_empty_card):
    fx = only_an_empty_card
    _assert_diff_fails(fx, EMPTY_NAMED)
    _, old_out = _run_both(fx, tmp_path)
    _check_card_without_tasks(old_out, old_out)  # the check can pass on the right shape
    wrong = _synthetic(old_out, [EMPTY_NAMED])
    with pytest.raises(AssertionError, match="a question was added"):
        _check_card_without_tasks(wrong, old_out)
