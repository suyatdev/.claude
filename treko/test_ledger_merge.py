"""F1, F2 and F3 (docs/features/treko-ledger.spec.md, section 11 F): `ledger_merge.merge(request,
parts, scan_questions) -> run`, the pure function that makes one run out of several repositories'.

What it is handed is fixed by decision D42: `request` is `{"directory", "repo", "branch", "worktree"}`,
`scan_questions` is a list of `{"q", "ctx"}`, and a part is `{"root", "label", "questions", "run"}` for a
family the analyzer finished or `{"root", "label", "questions", "failure": {"exit", "timedOut",
"stderr"}}` for one it did not. Every run below is the real analyzer's, on a throwaway git repository
under a fake HOME, and every schema check compares against one of them.

Test-side oracles are one-liners over the family runs (concatenate, then renumber); the two that carry a
decision (merged waves, graph spacing) are also written out by hand. Each test names what a wrong
shortcut would do.

Run:  see section 15 of the spec (the pinned `uv run ... pytest` command).
"""

import copy
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import analyze  # noqa: E402  — path shim above must run first
import ledger_merge  # noqa: E402  — the module under test; task 10's green step writes it
import ledger_state  # noqa: E402

Y0, DY = analyze.GRAPH_Y0, analyze.GRAPH_DY
CYCLE_NOTE_TEXT = "cycle — order undetermined, see questions"
SCAN = [
    {"q": "Were repositories missed under `~/dev`?", "ctx": "3 folders could not be listed."},
    {"q": "Why could git not read `/x`?", "ctx": "fatal: detected dubious ownership"},
]


# ------------------------------------------------------------------------------------ fixtures

def _git(root, *args):
    env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull,
               GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
               GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, env=env)


def _card(features, name, depends=None, phase="implementation", branch="none"):
    lines = ["---", "phase: " + phase, "model_tier: high", "branch: " + branch, "---", "", "# " + name, ""]
    if depends is not None:
        lines += ["## Depends on", ""] + ["- " + target for target in depends] + [""]
    lines += ["## Tasks", "", "- [x] 1 — first", "- [ ] 2 — second", ""]
    (features / (name + ".md")).write_text("\n".join(lines))


def family(parent, folder, cards, trunk="main", branches=()):
    """A part for a real analyzer run over `parent/folder`. A card is (name, depends or None, **frontmatter)."""
    root = parent / folder
    (root / "docs" / "features").mkdir(parents=True)
    _git(root, "-c", "init.defaultBranch=" + trunk, "init", "-q")
    (root / "README.md").write_text("fixture\n")
    for name, depends, *extra in cards:
        _card(root / "docs" / "features", name, depends, **(extra[0] if extra else {}))
    _git(root, "add", "-A")
    _git(root, "commit", "-q", "-m", "fixture")
    for branch in branches:
        _git(root, "branch", branch)
    return {"root": str(root), "label": folder, "questions": [], "run": analyze.analyze(root)}


def failed(parent, folder, exit_status, timed_out, stderr):
    failure = {"exit": exit_status, "timedOut": timed_out, "stderr": stderr}
    return {"root": str(parent / folder), "label": folder, "questions": [], "failure": failure}


@pytest.fixture(scope="module")
def world(tmp_path_factory):
    """Families under a fake home, built once. `beta` has every section filled and a cycle; `gamma`
    and `delta` are cycles only (delta reuses alpha's card names on purpose); `wide` is 14 nodes."""
    patch = pytest.MonkeyPatch()
    home = tmp_path_factory.mktemp("ledger-merge").resolve() / "home"
    dev = home / "dev"
    dev.mkdir(parents=True)
    patch.setenv("HOME", str(home))
    yield SimpleNamespace(
        dev=dev,
        alpha=family(dev, "alpha", [("a1", []), ("a2", ["a1"]), ("a3", ["a2"]), ("a4", None, {"phase": "review"})]),
        beta=family(dev, "beta", [("b1", None), ("b2", ["b1"]), ("b3", ["b1"]), ("b6", ["b1"]),
                                  ("b4", ["b5"]), ("b5", ["b4"])]),
        gamma=family(dev, "gamma", [("g1", ["g2"]), ("g2", ["g1"]), ("g3", ["g1"])]),
        delta=family(dev, "delta", [("a1", ["a2"]), ("a2", ["a1"])]),
        wide=family(dev, "wide", [("w%02d" % number, None) for number in range(14)]),
        empty=family(dev, "empty", []),
        broken=failed(dev, "broken", 7, False, "analyze: git failed in the primary checkout: bad object"),
        slow=failed(dev, "slow", None, True, "treko-progress branches"),
    )
    patch.undo()


def merged(world, *parts, scan=(), **narrowing):
    request = {"directory": str(world.dev), "repo": "", "branch": "", "worktree": ""}
    request.update(narrowing)
    return ledger_merge.merge(request, copy.deepcopy(list(parts)), copy.deepcopy(list(scan)))


def concat(parts, section):
    return [row for part in parts if "run" in part for row in part["run"][section]]


def item(name):
    return {"t": name, "pr": "", "prState": ""}


def wave(number, note, *names):
    return {"n": number, "note": note, "items": [item(name) for name in names]}


def tops_and_bottoms(out, counts):
    """(first y, largest y) of each consecutive run of `counts` merged nodes."""
    spans, start = [], 0
    for count in counts:
        ys = [node["y"] for node in out["graph"]["nodes"][start:start + count]]
        spans.append((min(ys), max(ys)))
        start += count
    return spans


# --------------------------------------------------------------------------------------- F1

SECTIONS = ("features", "waves", "constraints", "branches", "kanban", "questions")


def test_the_identity_fixtures_fill_every_section(world):
    """Without this, 'nothing was dropped' is true of an empty run too."""
    run = world.beta["run"]
    assert all(run[key] for key in SECTIONS) and run["graph"]["nodes"] and run["graph"]["edges"]
    assert sum(bool(column["items"]) for column in run["kanban"]) >= 2
    assert len(run["questions"]) >= 3 and len(run["constraints"]) >= 3


@pytest.mark.parametrize("name", ["alpha", "beta", "gamma", "delta", "wide", "empty"])
def test_one_family_comes_back_as_the_analyzers_run_with_only_id_name_dir_replaced(world, name):
    """Whole-dict equality. Falsifier: reorder, renumber, drop a key, re-sort or regroup anything."""
    part = world.__dict__[name]
    expected = copy.deepcopy(part["run"])
    expected.update(id=ledger_state.run_id(str(world.dev), "", "", ""), name="dev", dir="~/dev", analyzedAt="")
    assert merged(world, part) == expected


def test_id_name_and_dir_come_from_the_request_not_from_the_run(world):
    """Falsifier: reading them off the analyzer's run (`alpha`, `~/dev/alpha`) or off the part's root."""
    out = merged(world, world.alpha, repo="alpha", branch="main")
    assert out["id"] == ledger_state.run_id(str(world.dev), "alpha", "main", "")
    assert out["id"] != merged(world, world.alpha)["id"]
    assert (out["name"], out["dir"]) == ("dev · repo alpha · branch main", "~/dev")
    assert world.alpha["run"]["dir"] == "~/dev/alpha" and world.alpha["run"]["name"] == "alpha"


def test_analyzed_at_is_emptied_for_the_store_to_stamp(world):
    """Falsifier: copying the run's own timestamp through."""
    part = copy.deepcopy(world.alpha)
    part["run"]["analyzedAt"] = "2026-11-03T09:13:20Z"
    assert merged(world, part)["analyzedAt"] == ""


def test_merge_changes_nothing_it_is_given(world):
    """Pure. Falsifier: renumbering or relabelling in place changes the inputs and the second call."""
    request = {"directory": str(world.dev), "repo": "", "branch": "", "worktree": ""}
    twin = dict(world.alpha, root=str(world.dev / "elsewhere" / "alpha"))  # same folder name, so labels collide
    parts = copy.deepcopy([world.alpha, twin, world.broken, world.beta])
    scan = copy.deepcopy(SCAN)
    before = copy.deepcopy((request, parts, scan))
    first = ledger_merge.merge(request, parts, scan)
    assert (request, parts, scan) == before
    assert ledger_merge.merge(request, parts, scan) == first


# --------------------------------------------------------------------------------------- F2

def test_cycle_note_is_the_note_the_real_analyzer_emits(world):
    """Falsifier: a constant with another dash or wording. The note is read from the analyzer's own run."""
    emitted = world.beta["run"]["waves"][-1]["note"]
    assert emitted == CYCLE_NOTE_TEXT
    assert ledger_merge.CYCLE_NOTE == emitted


def test_layered_waves_merge_by_index_and_cycle_waves_merge_into_one_last_wave(world):
    """Three families, a cycle in two. Falsifiers: sorting families by label, concatenating the waves,
    leaving a cycle at its own index (beta's is wave 3), keeping one family's own cycle number,
    taking the max of the own numbers (3), and one cycle wave per family."""
    w = world
    notes = [one["note"] for one in w.alpha["run"]["waves"]]
    cycle = w.beta["run"]["waves"][-1]["note"]
    assert merged(w, w.beta, w.alpha, w.gamma)["waves"] == [
        wave("1", notes[0], "b1", "a1", "a4"),
        wave("2", notes[1], "b2", "b3", "b6", "a2"),
        wave("3", notes[2], "a3"),
        wave("4", cycle, "b4", "b5", "g1", "g2", "g3"),
    ]


def test_a_cycle_in_one_family_only_still_goes_last_and_after_the_longest_run(world):
    """Falsifier: beta's own wave number (3) kept, which would sit beside alpha's wave 3."""
    w = world
    notes = [one["note"] for one in w.alpha["run"]["waves"]]
    cycle = w.beta["run"]["waves"][-1]["note"]
    assert merged(w, w.alpha, w.beta)["waves"] == [
        wave("1", notes[0], "a1", "a4", "b1"),
        wave("2", notes[1], "a2", "b2", "b3", "b6"),
        wave("3", notes[2], "a3"),
        wave("4", cycle, "b4", "b5"),
    ]


def test_with_no_layered_wave_anywhere_the_merged_cycle_wave_is_wave_one(world):
    """Falsifier: numbering it 0, 2 or after the families' own count, or one cycle wave each."""
    w = world
    cycle = w.gamma["run"]["waves"][-1]["note"]
    assert merged(w, w.gamma, w.delta)["waves"] == [wave("1", cycle, "g1", "g2", "g3", "a1", "a2")]


def test_node_ids_are_renumbered_in_family_order_with_the_analyzers_function(world):
    """29 nodes, so the ids reach `AA`. Falsifier: ids restarting per family, or `chr(65 + i)`."""
    w = world
    parts = [w.beta, w.alpha, w.wide, w.gamma, w.delta]
    nodes = merged(w, *parts)["graph"]["nodes"]
    assert [node["id"] for node in nodes] == [analyze._node_id(index) for index in range(29)]
    assert [node["id"] for node in nodes][26:] == ["AA", "AB", "AC"]
    assert [node["label"] for node in nodes] == [n["label"] for p in parts for n in p["run"]["graph"]["nodes"]]


def test_edges_follow_their_own_familys_nodes_even_when_card_names_repeat(world):
    """alpha and delta both have cards a1 and a2. Falsifier: remapping an edge by card name."""
    w = world
    parts = [w.alpha, w.delta, w.beta]
    expected, offset = [], 0
    for part in parts:
        nodes = part["run"]["graph"]["nodes"]
        ids = {node["id"]: analyze._node_id(offset + index) for index, node in enumerate(nodes)}
        expected += [[ids[source], ids[target]] for source, target in part["run"]["graph"]["edges"]]
        offset += len(nodes)
    assert merged(w, *parts)["graph"]["edges"] == expected
    assert expected[0] != w.alpha["run"]["graph"]["edges"][1], "the fixture must renumber something"


def test_ids_are_unique_and_every_edge_names_existing_nodes(world):
    """Falsifier: kept analyzer ids (every family restarts at q1, C1 and A)."""
    w = world
    out = merged(w, w.beta, w.alpha, w.wide, w.gamma, w.delta, w.broken, scan=SCAN)
    for rows in (out["graph"]["nodes"], out["questions"], out["constraints"]):
        assert len({row["id"] for row in rows}) == len(rows)
    node_ids = {node["id"] for node in out["graph"]["nodes"]}
    assert out["graph"]["edges"] and all(set(edge) <= node_ids for edge in out["graph"]["edges"])


def test_each_familys_graph_sits_one_empty_row_below_the_previous_one(world):
    """beta has 3 rows, alpha 2, gamma 3. Falsifiers: no shift (boxes pile up), a shift of one row
    (no empty row), x moved, rows squeezed or stretched."""
    w = world
    parts = [w.beta, w.alpha, w.gamma]
    out = merged(w, *parts)
    assert tops_and_bottoms(out, [6, 4, 3]) == [
        (Y0, Y0 + 2 * DY), (Y0 + 4 * DY, Y0 + 5 * DY), (Y0 + 7 * DY, Y0 + 9 * DY)]
    source = [node for part in parts for node in part["run"]["graph"]["nodes"]]
    assert [node["x"] for node in out["graph"]["nodes"]] == [node["x"] for node in source]
    assert len({(node["x"], node["y"]) for node in out["graph"]["nodes"]}) == len(source)
    start = 0
    for part, (top, _) in zip(parts, tops_and_bottoms(out, [6, 4, 3])):
        own = part["run"]["graph"]["nodes"]
        moved = out["graph"]["nodes"][start:start + len(own)]
        assert [node["y"] - top for node in moved] == [node["y"] - Y0 for node in own]
        start += len(own)


def test_a_family_without_nodes_takes_no_space(world):
    """Empty, failed, then nothing before the first. Falsifier: a gap counted for a family with no nodes."""
    w = world
    out = merged(w, w.empty, w.broken, w.alpha, w.empty, w.slow, w.beta)
    assert tops_and_bottoms(out, [4, 6]) == [(Y0, Y0 + DY), (Y0 + 3 * DY, Y0 + 5 * DY)]


def test_constraints_are_concatenated_and_renumbered_c1_to_cn(world):
    """Falsifier: keeping each family's C1.., or renumbering from C0 or after reordering."""
    w = world
    parts = [w.beta, w.alpha]
    rows = merged(w, *parts)["constraints"]
    assert [row["id"] for row in rows] == ["C%d" % number for number in range(1, len(rows) + 1)]
    assert [{k: v for k, v in row.items() if k != "id"} for row in rows] == [
        {k: v for k, v in row.items() if k != "id"} for row in concat(parts, "constraints")]
    assert len(rows) == 7


def test_features_branches_and_kanban_columns_are_concatenated_in_family_order(world):
    """Falsifier: only the first family, sorted families, or eight columns instead of four."""
    w = world
    parts = [w.beta, w.alpha, w.gamma]
    out = merged(w, *parts)
    assert out["features"] == concat(parts, "features")
    assert out["branches"] == concat(parts, "branches")
    assert [(c["title"], c["tone"]) for c in out["kanban"]] == [
        (c["title"], c["tone"]) for c in w.alpha["run"]["kanban"]]
    for index, column in enumerate(out["kanban"]):
        assert column["items"] == [i for p in parts for i in p["run"]["kanban"][index]["items"]]
    assert sum(len(column["items"]) for column in out["kanban"]) == 13


def test_a_merged_run_has_the_analyzers_key_set_and_value_types(world):
    """Compared with a real analyzer run, key by key. Falsifier: an extra key on any row, a wave
    number that is an int, an edge that is a tuple, a question without `resolved`, a None stamp."""
    w = world

    def same_shape(actual, reference, where):
        assert type(actual) is type(reference), where
        if isinstance(reference, dict):
            assert set(actual) == set(reference), where
            for key in reference:
                same_shape(actual[key], reference[key], where + "." + key)
        elif isinstance(reference, list) and reference:
            for index, row in enumerate(actual):
                same_shape(row, reference[0], "%s[%d]" % (where, index))

    for parts in ([w.alpha, w.beta], [w.beta, w.alpha, w.gamma, w.empty, w.broken], [w.wide, w.delta, w.slow]):
        same_shape(merged(w, *parts, scan=SCAN), w.beta["run"], "run")


def test_questions_are_scan_first_then_failed_families_then_each_familys_own(world):
    """Each family's scan questions go just before its analyzer's. Falsifiers: scan questions after
    the merge's own, failed ones at the end, the family's scan questions after its analyzer's,
    no renumbering, q0.."""
    w = world
    alpha = dict(copy.deepcopy(w.alpha), questions=[{"q": "Which copy of `a1` is current?", "ctx": "wt-a, wt-b"}])
    beta = dict(copy.deepcopy(w.beta), questions=[{"q": "Which copy of `b2` is current?", "ctx": "wt-c, wt-d"},
                                                  {"q": "Which copy of `b3` is current?", "ctx": "wt-e, wt-f"}])
    out = merged(w, alpha, w.broken, beta, w.slow, scan=SCAN)["questions"]
    own = [[q["q"] for q in part["questions"]] for part in (alpha, beta)]
    assert [q["q"] for q in out] == (
        [s["q"] for s in SCAN] + ["Why could `broken` not be analyzed?", "Why could `slow` not be analyzed?"]
        + own[0] + [q["q"] for q in w.alpha["run"]["questions"]]
        + own[1] + [q["q"] for q in w.beta["run"]["questions"]])
    assert [q["id"] for q in out] == ["q%d" % number for number in range(1, len(out) + 1)]
    assert all(q["resolved"] is False for q in out)
    assert [q["ctx"] for q in out[:2]] == [s["ctx"] for s in SCAN] and out[4]["ctx"] == "wt-a, wt-b"


def test_a_failed_familys_own_scan_questions_stay_at_its_place_in_family_order(world):
    """Reading of D42 item 6, 'each family's questions': a failed family still has them. Falsifier:
    dropping them, or putting them with the failed-family questions."""
    w = world
    broken = dict(copy.deepcopy(w.broken), questions=[{"q": "Which copy of `x` is current?", "ctx": "wt-a, wt-b"}])
    asked = [q["q"] for q in merged(w, w.alpha, broken, w.beta)["questions"]]
    first = [q["q"] for q in w.alpha["run"]["questions"]]
    assert asked == (["Why could `broken` not be analyzed?"] + first + ["Which copy of `x` is current?"]
                     + [q["q"] for q in w.beta["run"]["questions"]])


def test_a_failed_family_is_a_question_with_its_repo_and_the_exit_status(world):
    """Falsifier: no repo in the text, no stderr line, no exit status, or the family silently dropped."""
    w = world
    out = merged(w, w.alpha, w.broken)
    asked = [q for q in out["questions"] if q["q"] == "Why could `broken` not be analyzed?"]
    assert len(asked) == 1 and out["features"] == w.alpha["run"]["features"]
    assert w.broken["failure"]["stderr"] in asked[0]["ctx"]
    assert "exit" in asked[0]["ctx"].lower() and "7" in asked[0]["ctx"]


def test_a_failed_family_that_timed_out_says_so_instead_of_an_exit_status(world):
    """Falsifier: reading the missing exit status as 'exit status None', or ignoring `timedOut`."""
    asked = [q for q in merged(world, world.alpha, world.slow)["questions"]
             if q["q"] == "Why could `slow` not be analyzed?"]
    assert len(asked) == 1
    ctx = asked[0]["ctx"]
    assert world.slow["failure"]["stderr"] in ctx and "time" in ctx.lower() and "None" not in ctx
