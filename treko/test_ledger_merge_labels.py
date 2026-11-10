"""F3 (docs/features/treko-ledger.spec.md, section 11 F; OQ-3 as decision D42 item 4 reads it): when two
families share a folder name, `ledger_merge.merge` labels both by their home-collapsed primary-checkout
path in `tasks[].repo`, `branches[].repo`, the kanban `m` prefix and the `<label>` in the failed-family
question, and changes nothing else.

Companion to `test_ledger_merge.py` (F1 and F2), which is at its line cap; the fixture builders come
from there. Two repositories called `foo` sit in `~/dev` and `~/work` under a fake HOME. Both hold cards
called `foo-sync` and `shared`, and one task's branch is also called `foo`, so a replacement of the folder
name anywhere but the three places changes a card name, a branch or a question. `~/work/foo` has no
`main`, so the analyzer asks "Which branch is the merge base for foo?", text it wrote itself.

Run:  see section 15 of the spec (the pinned `uv run ... pytest` command).
"""

import copy
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from test_ledger_merge import concat, failed, family, merged  # noqa: E402  — helpers only, no test names


@pytest.fixture(scope="module")
def labels(tmp_path_factory):
    patch = pytest.MonkeyPatch()
    home = tmp_path_factory.mktemp("ledger-labels").resolve() / "home"
    dev, work = home / "dev", home / "work"
    dev.mkdir(parents=True)
    work.mkdir()
    patch.setenv("HOME", str(home))
    shared = [("foo-sync", None, {"branch": "foo"}), ("shared", [])]
    yield SimpleNamespace(
        dev=dev,
        foo_dev=family(dev, "foo", shared, branches=["foo"]),
        foo_work=family(work, "foo", shared, trunk="trunk"),
        bar=family(dev, "bar", [("shared", [])]),
        broken=failed(dev, "broken", 7, False, "analyze: git failed in the primary checkout: bad object"),
        gone=failed(work, "foo", 1, False, "analyze: not a directory"),
    )
    patch.undo()


def relabelled(part, label):
    """The analyzer's run for `part`, with its folder name replaced by `label` in the three places only."""
    run = copy.deepcopy(part["run"])
    for feature in run["features"]:
        for task in feature["tasks"]:
            task["repo"] = label
    for branch in run["branches"]:
        branch["repo"] = label
    for column in run["kanban"]:
        for row in column["items"]:
            assert row["m"].startswith(part["label"] + " · ")
            row["m"] = label + row["m"][len(part["label"]):]
    return run


def card_names(run):
    return ([f["name"] for f in run["features"]] + [n["label"] for n in run["graph"]["nodes"]]
            + [i["t"] for w in run["waves"] for i in w["items"]] + [i["t"] for c in run["kanban"] for i in c["items"]]
            + [t["name"] for f in run["features"] for t in f["tasks"]])


def prefixes(run):
    return {row["m"].split(" · ")[0] for column in run["kanban"] for row in column["items"]}


def test_the_fixture_really_has_two_families_with_one_folder_name(labels):
    assert labels.foo_dev["label"] == labels.foo_work["label"] == "foo"
    assert labels.foo_dev["root"] != labels.foo_work["root"]
    assert {t["repo"] for f in labels.foo_dev["run"]["features"] for t in f["tasks"]} == {"foo"}


def test_colliding_folder_names_are_labelled_by_their_home_collapsed_paths(labels):
    """~/dev/foo and ~/work/foo in tasks[].repo, branches[].repo and the kanban `m` prefix. Falsifiers:
    leaving the folder name (the board would fuse the two), labelling only one family, or labelling by
    the full path instead of the home-collapsed one."""
    out = merged(labels, labels.foo_dev, labels.foo_work)
    dev, work = relabelled(labels.foo_dev, "~/dev/foo"), relabelled(labels.foo_work, "~/work/foo")
    assert out["features"] == dev["features"] + work["features"]
    assert out["branches"] == dev["branches"] + work["branches"]
    assert [c["items"] for c in out["kanban"]] == [a["items"] + b["items"] for a, b in zip(dev["kanban"], work["kanban"])]
    assert {t["repo"] for f in out["features"] for t in f["tasks"]} == {"~/dev/foo", "~/work/foo"}
    assert {b["repo"] for b in out["branches"]} == {"~/dev/foo", "~/work/foo"}
    assert prefixes(out) == {"~/dev/foo", "~/work/foo"}


def test_every_card_name_and_every_analyzer_question_keeps_its_text(labels):
    """Falsifier: replacing the folder name everywhere in the run (card `foo-sync`, a task's branch
    `foo`, the analyzer's own question about `foo`)."""
    both = [labels.foo_dev, labels.foo_work]
    out = merged(labels, *both)
    assert sorted(card_names(out)) == sorted(n for part in both for n in card_names(part["run"]))
    assert "foo-sync" in card_names(out)
    assert {t["branch"] for f in out["features"] for t in f["tasks"]} == {"foo", "—"}
    assert "Which branch is the merge base for foo?" in [q["q"] for q in out["questions"]]
    for part in both:
        assert {(q["q"], q["ctx"]) for q in part["run"]["questions"]} <= {(q["q"], q["ctx"]) for q in out["questions"]}
    assert out["constraints"] == concat(both, "constraints")


def test_without_a_collision_labels_stay_folder_names(labels):
    """Falsifier: always using full paths."""
    out = merged(labels, labels.foo_dev, labels.bar)
    assert out["features"] == concat([labels.foo_dev, labels.bar], "features")
    assert out["branches"] == concat([labels.foo_dev, labels.bar], "branches")
    assert prefixes(out) == {"foo", "bar"}


def test_only_the_families_that_collide_get_path_labels(labels):
    """Falsifier: any collision switching every family to paths."""
    out = merged(labels, labels.foo_dev, labels.bar, labels.foo_work)
    expected = [relabelled(labels.foo_dev, "~/dev/foo"), labels.bar["run"], relabelled(labels.foo_work, "~/work/foo")]
    assert out["features"] == [f for run in expected for f in run["features"]]
    assert out["branches"] == [b for run in expected for b in run["branches"]]
    assert prefixes(out) == {"~/dev/foo", "bar", "~/work/foo"}


def test_the_name_in_a_failed_family_question_is_the_path_when_names_collide(labels):
    """A failed family is a family (a reading of OQ-3 and D42 item 4). Falsifier: the bare folder name,
    which names neither of the two, or a path for a family that collides with nothing."""
    out = merged(labels, labels.foo_dev, labels.gone, labels.broken)
    asked = [q["q"] for q in out["questions"]]
    assert "Why could `~/work/foo` not be analyzed?" in asked
    assert "Why could `broken` not be analyzed?" in asked
    assert {b["repo"] for b in out["branches"]} == {"~/dev/foo"}
