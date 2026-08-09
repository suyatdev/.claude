"""Acceptance tests for analyze.py — criteria 1 and 2 of docs/features/tracking-feature-state.md.

Every test builds a throwaway git repo under pytest's `tmp_path`. Nothing here reads the
repo it ships in, deliberately: this repo's card set changes while parallel agents work,
so a test asserting "N cards in, N features out" against it would be flaky by construction
rather than by accident. The git commands below only ever run with an explicit `-C` into
that tmpdir.

Run:  uvx pytest==8.3.4 task-tracker/test_analyze.py
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO_ROOT / "hooks" / "lib"))

import analyze as analyzer  # noqa: E402
import feature_tasks  # noqa: E402  — imported independently, to recompute counts ourselves

# Pinned from the shipped UI (`Task Tracker.dc.html`), which does
# `TONES[x] || TONES.neutral` — an unknown tone renders as grey, silently.
UI_TONES = {"ok", "warn", "bad", "info", "accent", "neutral"}
# Pinned from the same file's STATE_RANK; an unknown state sorts as undefined.
UI_STATES = {"Blocked", "In progress", "In review", "Stale", "Not started", "Merged", "Done"}

RUN_KEYS = {
    "id", "name", "dir", "analyzedAt", "features", "waves",
    "constraints", "branches", "graph", "kanban", "questions",
}
BRANCH_KEYS = {"repo", "branch", "wt", "ahead", "behind", "dirty", "note", "tone", "last"}
FEATURE_KEYS = {"name", "meta", "tasks"}
NO_BRANCH = "—"


# --------------------------------------------------------------------------- fixtures


def _git_env(home):
    """Env that cannot reach the developer's real git config, hooks, or identity."""
    env = dict(os.environ)
    env.update(
        {
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_SYSTEM": os.devnull,
            "GIT_AUTHOR_NAME": "Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "HOME": str(home),
        }
    )
    for leaked in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
        env.pop(leaked, None)
    return env


class Repo:
    """A disposable git repo with feature cards. Confined to tmp_path."""

    def __init__(self, tmp_path):
        self.root = tmp_path / "repo"
        self.wt_dir = tmp_path / "wt"
        self.root.mkdir()
        self.wt_dir.mkdir()
        self.env = _git_env(tmp_path)
        self.git("-c", "init.defaultBranch=main", "init", "-q")
        (self.root / "docs" / "features").mkdir(parents=True)
        self.write("README.md", "fixture\n")
        self.commit("root commit")

    def git(self, *args, cwd=None):
        return subprocess.run(
            ["git", "-C", str(cwd or self.root), *args],
            check=True, capture_output=True, text=True, env=self.env,
        ).stdout

    def write(self, relpath, text):
        target = self.root / relpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def card(self, name, tasks=(), phase="implementation", branch="none",
             model_tier="high", body="", depends_on=None, suffix=".md"):
        """Write docs/features/<name><suffix> and return its text."""
        lines = [
            "---",
            "phase: %s" % phase,
            "model_tier: %s" % model_tier,
            "branch: %s" % branch,
            "---",
            "",
            "# %s" % name,
            "",
            body,
            "",
        ]
        if depends_on is not None:
            lines.append("## Depends on")
            lines.append("")
            lines.extend(depends_on)
            lines.append("")
        if tasks:
            lines.append("## Tasks")
            lines.append("")
            for index, (done, text) in enumerate(tasks, 1):
                lines.append("- [%s] %d — %s" % ("x" if done else " ", index, text))
            lines.append("")
        text = "\n".join(lines)
        self.write("docs/features/%s%s" % (name, suffix), text)
        return text

    def add_worktree(self, branch, name=None):
        path = self.wt_dir / (name or branch.replace("/", "-"))
        self.git("worktree", "add", "-q", "-b", branch, str(path))
        return path


@pytest.fixture
def repo(tmp_path):
    return Repo(tmp_path)


def _independent_total(text, label):
    """Total task count straight from feature_tasks.py's own function."""
    return len(feature_tasks.task_ids(text, label))


def _feature(run, name):
    for feature in run["features"]:
        if feature["name"] == name:
            return feature
    raise AssertionError("no feature %r in %s" % (name, [f["name"] for f in run["features"]]))


def _questions_mentioning(run, needle):
    return [
        q for q in run["questions"]
        if needle in q["q"] or needle in q.get("ctx", "")
    ]


# ------------------------------------------------------- criterion 1: features and meta


def test_criterion_1_n_cards_in_n_features_out(repo):
    """N feature cards in, N features[] out — and a .spec.md half is not a card."""
    alpha = repo.card("alpha", tasks=[(True, "one"), (True, "two"), (False, "three"), (False, "four")])
    repo.card("beta", tasks=[(False, "one"), (False, "two")])
    repo.card("gamma", tasks=[])
    # The split half of alpha. Same task list, per the memory-system-split contract.
    repo.card("alpha", tasks=[(True, "one"), (True, "two"), (False, "three"), (False, "four")],
              suffix=".spec.md")
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    assert {f["name"] for f in run["features"]} == {"alpha", "beta", "gamma"}
    assert len(run["features"]) == 3, "a .spec.md half must not count as a second card"
    assert _independent_total(alpha, "alpha.md") == 4


def test_criterion_1_meta_matches_feature_tasks_own_count(repo):
    """Each meta is '<done>/<total>' and the total is feature_tasks.py's own count."""
    texts = {
        "alpha": repo.card("alpha", tasks=[(True, "one"), (True, "two"), (False, "three"), (False, "four")]),
        "beta": repo.card("beta", tasks=[(False, "one"), (False, "two")]),
        "gamma": repo.card("gamma", tasks=[]),
        "delta": repo.card("delta", tasks=[(True, "only")]),
    }
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    # Hardcoded expectations — independent of any counting code under test.
    assert _feature(run, "alpha")["meta"] == "2/4"
    assert _feature(run, "beta")["meta"] == "0/2"
    assert _feature(run, "gamma")["meta"] == "0/0"
    assert _feature(run, "delta")["meta"] == "1/1"

    # And the total half agrees with feature_tasks.py for every card.
    for name, text in texts.items():
        total = _independent_total(text, "%s.md" % name)
        assert _feature(run, name)["meta"].split("/")[1] == str(total)


def test_criterion_1_ticked_count_tracks_the_checkbox_not_the_text(repo):
    """A ticked box and an appended completion note move done, never total."""
    repo.card("alpha", tasks=[(True, "one — landed in abc1234"), (False, "two")])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    assert _feature(run, "alpha")["meta"] == "1/2"


def test_unparseable_card_becomes_a_question_and_does_not_crash(repo):
    """A malformed checkbox is feature_tasks.py's ParseError — report it, never guess."""
    repo.write(
        "docs/features/broken.md",
        "---\nphase: implementation\nbranch: none\n---\n\n- [y] 1 — malformed\n",
    )
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    assert _questions_mentioning(run, "broken"), "an unparseable card must surface as a question"
    assert all(not q["resolved"] for q in _questions_mentioning(run, "broken"))


# --------------------------------------------- criterion 2: branch:none vs worktree drift


def test_criterion_2_branch_none_with_a_worktree_becomes_a_question(repo):
    """branch: none in frontmatter + a worktree holding a branch named for the card."""
    repo.card("orphan-drift", tasks=[(False, "do the thing")], branch="none")
    repo.commit("cards")
    repo.add_worktree("feat/orphan-drift")

    run = analyzer.analyze(repo.root)

    drift = _questions_mentioning(run, "orphan-drift")
    assert drift, "the drift must appear in questions[]"
    assert any("feat/orphan-drift" in (q["q"] + q.get("ctx", "")) for q in drift), \
        "the question must name the worktree branch it conflicts with"
    assert all(not q["resolved"] for q in drift)


def test_criterion_2_drift_is_not_silently_resolved_in_either_direction(repo):
    """Neither side is rewritten: the card still says none, the branch is still listed."""
    repo.card("orphan-drift", tasks=[(False, "do the thing")], branch="none")
    repo.commit("cards")
    repo.add_worktree("feat/orphan-drift")

    run = analyzer.analyze(repo.root)

    task = _feature(run, "orphan-drift")["tasks"][0]
    assert task["branch"] == NO_BRANCH, \
        "the card said branch: none — the analyzer must not adopt the worktree's branch"

    listed = {b["branch"] for b in run["branches"]}
    assert "feat/orphan-drift" in listed, \
        "the worktree branch is real — the analyzer must not drop it to match the card"


def test_no_drift_question_when_frontmatter_and_worktree_agree(repo):
    """The drift check must be able to stay silent, or it proves nothing when it fires."""
    repo.card("agreed", tasks=[(False, "do the thing")], branch="feat/agreed")
    repo.commit("cards")
    repo.add_worktree("feat/agreed")

    run = analyzer.analyze(repo.root)

    assert not _questions_mentioning(run, "agreed"), \
        "a card whose branch matches its worktree is not drift"


def test_criterion_2_drift_does_not_fire_for_an_unrelated_branch(repo):
    """The false-positive direction: branch: none plus a branch that is not named for it."""
    repo.card("lonely", tasks=[(False, "do the thing")], branch="none")
    repo.commit("cards")
    repo.add_worktree("feat/something-else")

    run = analyzer.analyze(repo.root)

    assert not _questions_mentioning(run, "feat/something-else"), \
        "a branch not named for the card is not that card's drift"


# ------------------------------------------------------------------ branches[] from git


def test_branches_report_ahead_behind_and_dirty(repo):
    """Pins the left/right orientation of rev-list --left-right --count."""
    repo.card("alpha", tasks=[(False, "one")], branch="feat/alpha")
    repo.commit("cards")
    worktree = repo.add_worktree("feat/alpha")

    # Two commits on the branch...
    (worktree / "a.txt").write_text("a\n")
    repo.git("add", "-A", cwd=worktree)
    repo.git("commit", "-q", "-m", "a", cwd=worktree)
    (worktree / "b.txt").write_text("b\n")
    repo.git("add", "-A", cwd=worktree)
    repo.git("commit", "-q", "-m", "b", cwd=worktree)
    # ...and one on main underneath it.
    repo.write("main-only.txt", "m\n")
    repo.commit("main moves")
    # Leave the branch worktree dirty.
    (worktree / "scratch.txt").write_text("uncommitted\n")

    run = analyzer.analyze(repo.root)
    entry = next(b for b in run["branches"] if b["branch"] == "feat/alpha")

    assert entry["ahead"] == 2, "two commits on the branch that main does not have"
    assert entry["behind"] == 1, "one commit on main that the branch does not have"
    assert entry["dirty"] is True
    assert entry["wt"].endswith("feat-alpha")


def test_branch_with_no_worktree_is_listed_and_is_not_dirty(repo):
    repo.git("branch", "feat/detached-from-any-worktree")

    run = analyzer.analyze(repo.root)
    entry = next(b for b in run["branches"] if b["branch"] == "feat/detached-from-any-worktree")

    assert entry["wt"] == NO_BRANCH
    assert entry["dirty"] is False


# --------------------------------------------- waves / constraints / graph (task 5 rules)


def test_prose_never_creates_a_dependency(repo):
    """Neither a paragraph nor a bullet outside ## Depends on is a dependency.

    The bulleted half is the one that matters: a bullet that names another card reads
    exactly like a declared dependency, and is the shape a section-gate bug would let
    through.
    """
    repo.card("alpha", tasks=[(False, "one")],
              body="This must land after beta, which blocks it entirely.\n"
                   "\n"
                   "## Notes\n"
                   "\n"
                   "- beta — must land first, or the API is missing\n")
    repo.card("beta", tasks=[(False, "one")])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    assert run["constraints"] == [], "no ## Depends on section means no constraint"
    assert run["graph"]["edges"] == [], "prose must not become an edge"


def test_depends_on_stops_at_the_next_heading(repo):
    """Only the ## Depends on section is read — the section after it is not."""
    repo.card("alpha", tasks=[(False, "one")])
    repo.card("gamma", tasks=[(False, "one")])
    repo.card("beta", tasks=[(False, "one")], depends_on=[
        "- alpha — beta consumes alpha's API",
        "",
        "## Notes",
        "",
        "- gamma — mentioned here, but not a dependency",
    ])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    labels = {node["id"]: node["label"] for node in run["graph"]["nodes"]}
    edges = {(labels[a], labels[b]) for a, b in run["graph"]["edges"]}
    assert ("alpha", "beta") in edges
    assert ("gamma", "beta") not in edges, "a bullet after the next heading is not a dependency"
    assert len(run["constraints"]) == 1


def test_cards_without_depends_on_surface_as_an_admitted_gap(repo):
    """Undetectable ordering is a question, never a confident wave."""
    repo.card("alpha", tasks=[(False, "one")],
              body="This must land after beta.")
    repo.card("beta", tasks=[(False, "one")])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    gap = [q for q in run["questions"] if "Depends on" in q.get("ctx", "") + q["q"]]
    assert gap, "the analyzer must admit that it cannot see undeclared dependencies"
    assert all(not q["resolved"] for q in gap)


def test_explicit_depends_on_orders_the_waves(repo):
    repo.card("alpha", tasks=[(False, "one")], branch="feat/alpha")
    repo.card("beta", tasks=[(False, "one")], branch="feat/beta",
              depends_on=["- alpha — beta consumes the API alpha introduces"])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)
    wave_of = {
        item["t"]: wave["n"]
        for wave in run["waves"] for item in wave["items"]
    }

    assert wave_of["alpha"] == "1"
    assert wave_of["beta"] == "2"


def test_explicit_depends_on_creates_a_constraint_and_an_edge(repo):
    repo.card("alpha", tasks=[(False, "one")])
    repo.card("beta", tasks=[(False, "one")],
              depends_on=["- alpha — beta consumes the API alpha introduces"])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    assert len(run["constraints"]) == 1
    constraint = run["constraints"][0]
    assert "alpha" in constraint["pair"] and "beta" in constraint["pair"]
    assert "consumes the API" in constraint["body"], "the declared reason must survive"

    labels = {node["id"]: node["label"] for node in run["graph"]["nodes"]}
    edges = {(labels[a], labels[b]) for a, b in run["graph"]["edges"]}
    assert ("alpha", "beta") in edges


def test_depends_on_an_unknown_card_is_a_question_not_an_edge(repo):
    repo.card("beta", tasks=[(False, "one")],
              depends_on=["- nonexistent — something that is not a card here"])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    assert _questions_mentioning(run, "nonexistent"), \
        "an unresolvable dependency target must be admitted"
    labels = {node["label"] for node in run["graph"]["nodes"]}
    assert "nonexistent" not in labels, "never invent a node for a card that does not exist"


def test_dependency_cycle_is_a_question_not_an_infinite_loop(repo):
    repo.card("alpha", tasks=[(False, "one")], depends_on=["- beta — circular"])
    repo.card("beta", tasks=[(False, "one")], depends_on=["- alpha — circular"])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    cycle = [q for q in run["questions"] if "cycle" in (q["q"] + q.get("ctx", "")).lower()]
    assert cycle, "a dependency cycle must be reported, not silently ordered"


# ------------------------------------------------------------------- schema conformance


def test_run_has_exactly_the_schema_top_level_keys(repo):
    repo.card("alpha", tasks=[(False, "one")])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    assert set(run) == RUN_KEYS


def test_emitted_vocabulary_stays_inside_what_the_ui_renders(repo):
    """An unknown tone renders grey and an unknown state sorts as undefined — both silent."""
    repo.card("alpha", tasks=[(True, "one"), (False, "two")], branch="feat/alpha")
    repo.card("beta", tasks=[(False, "one")], phase="planning")
    repo.commit("cards")
    repo.add_worktree("feat/alpha")

    run = analyzer.analyze(repo.root)

    assert {b["tone"] for b in run["branches"]} <= UI_TONES
    assert {k["tone"] for k in run["kanban"]} <= UI_TONES
    assert {n["tone"] for n in run["graph"]["nodes"]} <= UI_TONES
    states = {t["state"] for f in run["features"] for t in f["tasks"]}
    assert states <= UI_STATES, "states outside STATE_RANK sort as undefined in the UI"


def test_feature_and_branch_entries_carry_every_schema_field(repo):
    repo.card("alpha", tasks=[(False, "one")], branch="feat/alpha")
    repo.commit("cards")
    repo.add_worktree("feat/alpha")

    run = analyzer.analyze(repo.root)

    for feature in run["features"]:
        assert set(feature) == FEATURE_KEYS
    for entry in run["branches"]:
        assert set(entry) == BRANCH_KEYS
        assert isinstance(entry["ahead"], int) and isinstance(entry["behind"], int)
        assert isinstance(entry["dirty"], bool)
    for node in run["graph"]["nodes"]:
        assert {"id", "label", "sub", "tone", "x", "y"} <= set(node)
    for edge in run["graph"]["edges"]:
        assert len(edge) == 2


def test_analyzed_at_is_left_for_the_store_to_stamp(repo):
    """The analyzer reads no clock, so it must not claim a freshness it cannot keep.

    store.py stamps `analyzedAt` only when the analyzer leaves it empty
    (`if not incoming.get("analyzedAt")`). A hardcoded 'just now' here would be
    truthy forever: a run analyzed last week would still read 'just now', which is
    the stale hand-written survey this feature exists to replace.
    """
    repo.card("alpha", tasks=[(False, "one")])
    repo.commit("cards")

    run = analyzer.analyze(repo.root)

    assert run["analyzedAt"] == "", "a frozen relative time goes stale silently"


def test_run_is_json_serializable(repo):
    """store.py writes this into tracker-data.js — an unserializable value breaks the UI."""
    repo.card("alpha", tasks=[(False, "one")], branch="feat/alpha")
    repo.commit("cards")
    repo.add_worktree("feat/alpha")

    run = analyzer.analyze(repo.root)

    assert json.loads(json.dumps(run)) == run


def test_analyzer_writes_nothing_to_the_analyzed_repo(repo):
    """Out of scope, permanently: the analyzer never edits a card to fix drift it found."""
    repo.card("orphan-drift", tasks=[(False, "one")], branch="none")
    repo.commit("cards")
    repo.add_worktree("feat/orphan-drift")
    before = repo.git("status", "--porcelain")

    analyzer.analyze(repo.root)

    assert repo.git("status", "--porcelain") == before
