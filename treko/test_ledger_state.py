"""G1 and G4 (docs/features/treko-ledger.spec.md, section 11 "G. Runs, ids, Delete"): the Ledger's
run ids (section 8.1) and the list rows it shows (sections 3.3 and 8.3), in `ledger_state.py`.

Names are fixed by card decision D41: `run_id(directory, repo, branch, worktree)` and
`run_rows(runs, hidden)`. Directory canonicalising (`expanduser`, then `realpath`, section 3.4)
stays with the caller, so `run_id` takes canonical strings and the id tests canonicalise the
spellings themselves, on a real symlink under `tmp_path`.

A row figure is derived from one key of the run. When the run lacks that key the figure is the string
"—", never None and never 0 (D41, section 8.3); a key that is present but empty gives a real 0.
Most fixtures below are built so that the shortcut a careless implementation would take gives a
different number, and the test asserts that the shortcut differs before it asserts the answer.

Run:  see section 15 of the spec (the pinned `uv run ... pytest` command).
"""

import copy
import hashlib
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import ledger_state  # noqa: E402  — path shim above must run first

DASH = "—"  # U+2014, the character the analyzer writes for "no worktree" (cards.NO_VALUE)
UNREADABLE = "?/?"  # a card whose checklist cannot be parsed (analyze.py:47)
FIGURES = ("repos", "branches", "worktrees", "features", "tasksDone", "tasksTotal",
           "unreadableCards")
ID_PATTERN = re.compile(r"r[0-9a-f]{16}")

# sha256 of the section 8.1 text, computed outside Python:  printf '%s' '<text>' | shasum -a 256
PINNED_IDS = (
    (("/Users/x/dev", "memsearch", "", ""), "re768e05cbfa1af82"),
    (("/Users/x/dev", "", "", ""), "r5617c2701fd6955f"),
    (("/Users/x/café", "", "", ""), "r6824773012d9ec13"),
)


def recipe_digest(fields, ensure_ascii):
    text = json.dumps(list(fields), ensure_ascii=ensure_ascii, separators=(",", ":"))
    return "r" + hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def canonical(path):
    """What the caller does before `run_id` (section 3.4)."""
    return os.path.realpath(os.path.expanduser(path))


def rid(directory, repo="", branch="", worktree=""):
    return ledger_state.run_id(directory, repo, branch, worktree)


# ---------------------------------------------------------------- G1: ids

def test_an_id_is_r_then_sixteen_lowercase_hex_digits():
    got = rid("/Users/x/dev")
    assert ID_PATTERN.fullmatch(got), got


def test_ids_equal_digests_computed_outside_this_module():
    for fields, expected in PINNED_IDS:
        assert rid(*fields) == expected, fields


def test_non_ascii_text_is_hashed_unescaped():
    fields = ("/Users/x/café", "", "", "")
    escaped = recipe_digest(fields, ensure_ascii=True)
    assert escaped != recipe_digest(fields, ensure_ascii=False)  # the fixture can tell them apart
    assert rid(*fields) != escaped
    assert rid(*fields) == recipe_digest(fields, ensure_ascii=False)


def test_the_same_arguments_always_give_the_same_id():
    assert rid("/Users/x/dev", "memsearch", "main") == rid("/Users/x/dev", "memsearch", "main")


def test_one_folder_typed_three_ways_gives_one_id(tmp_path, monkeypatch):
    real = tmp_path / "x"
    real.mkdir()
    link = tmp_path / "link"
    os.symlink(real, link)
    monkeypatch.setenv("HOME", str(tmp_path))
    typed = ["~/x", str(real), str(link)]
    assert len(set(typed)) == 3  # three spellings really are three strings...
    assert len({rid(spelling) for spelling in typed}) == 3  # ...which hash apart until canonicalised
    folders = {canonical(spelling) for spelling in typed}
    assert len(folders) == 1
    assert len({rid(folder) for folder in folders}) == 1


def test_the_same_folder_name_in_two_places_gives_two_ids(tmp_path, monkeypatch):
    for parent in ("dev", "work"):
        (tmp_path / parent / "foo").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(tmp_path))
    dev, work = canonical("~/dev/foo"), canonical("~/work/foo")
    assert os.path.basename(dev) == os.path.basename(work) == "foo"  # an id from the name collides
    assert dev != work
    assert rid(dev) != rid(work)


def test_each_narrowing_changes_the_id():
    base = "/Users/x/dev"
    ids = {
        "none": rid(base),
        "repo": rid(base, repo="memsearch"),
        "branch": rid(base, branch="main"),
        "worktree": rid(base, worktree="/Users/x/dev/wt"),
    }
    assert len(set(ids.values())) == 4, ids
    assert rid(base, "memsearch", "main") != ids["repo"]  # narrowing a narrowed request, too
    assert rid(base, "memsearch", "main") != ids["branch"]


def test_the_same_text_in_another_slot_changes_the_id():
    base = "/Users/x/dev"
    slots = [rid(base, "x"), rid(base, "", "x"), rid(base, "", "", "x")]
    assert len(set(slots)) == 3  # a hash over the set of values would give one


def test_text_moved_across_a_field_boundary_changes_the_id():
    base = "/Users/x/dev"
    assert rid(base, "ab", "c") != rid(base, "a", "bc")  # a plain concatenation would not
    assert rid(base + "/a", "b") != rid(base, "a/b")


# ---------------------------------------------------------------- G4: rows

def branch(repo, name, wt=DASH, note="clean"):
    return {"repo": repo, "branch": name, "wt": wt, "ahead": 0, "behind": 0, "dirty": False,
            "note": note, "tone": "ok", "last": "2 days ago"}


def feature(name, meta):
    return {"name": name, "meta": meta, "tasks": []}


def make_run(run_id, **keys):
    return {"id": run_id, "name": "run " + run_id, **keys}


def full_run(run_id="r1", analyzed="2026-11-03T09:13:20Z"):
    """Two repositories; five branches, two of them with a worktree that exists; five cards."""
    return make_run(
        run_id, name="dev · repo memsearch", dir="~/dev", analyzedAt=analyzed,
        branches=[
            branch("alpha", "main", wt="/w/alpha"),
            branch("alpha", "feat/x", wt=DASH, note="ahead 2"),
            branch("alpha", "feat/y", wt="", note="clean"),
            branch("beta", "feat/z", wt="/w/beta-z", note="folder missing"),
            branch("beta", "main", wt="/w/beta", note="3 uncommitted"),
        ],
        features=[feature("one", "3/5"), feature("two", "10/12"), feature("three", UNREADABLE),
                  feature("four", "0/0"), feature("five", UNREADABLE)],
        waves=[], constraints=[], graph={}, kanban={}, questions=[],  # a row must not carry these
    )


def rows_of(runs, hidden=()):
    return ledger_state.run_rows(copy.deepcopy(list(runs)), list(hidden))


def only_row(run, others=()):
    return {row["id"]: row for row in rows_of([run, *others])}[run["id"]]


def test_a_full_run_gives_the_row_of_section_3_3():
    row = only_row(full_run(), others=[full_run("r2")])
    assert row == {
        "id": "r1", "name": "dev · repo memsearch", "dir": "~/dev",
        "analyzedAt": "2026-11-03T09:13:20Z", "repos": 2, "branches": 5, "worktrees": 2,
        "features": 5, "tasksDone": 13, "tasksTotal": 17, "unreadableCards": 2,
        "canDelete": True,
    }


def test_worktrees_leave_out_empty_dash_and_folder_missing_only():
    branches = full_run()["branches"]
    by_wt_alone = sum(1 for b in branches if b["wt"] not in ("", DASH))
    by_truthiness = sum(1 for b in branches if b["wt"])  # the prototype's count (section 8.3)
    assert (by_wt_alone, by_truthiness) == (3, 4)
    got = only_row(full_run())["worktrees"]
    assert got == 2  # a dirty branch ("3 uncommitted") with a worktree still counts


def test_a_gone_worktree_folder_is_not_counted_though_its_path_is_in_wt():
    run = make_run("r1", branches=[branch("a", "main", wt="/w/a", note="folder missing")])
    assert run["branches"][0]["wt"] == "/w/a"
    assert only_row(run)["worktrees"] == 0  # counting by wt alone gives 1


def test_repos_are_distinct_values_of_branches_repo():
    run = make_run("r1", branches=[branch("a", "m"), branch("a", "n"), branch("b", "m")])
    row = only_row(run)
    assert (row["repos"], row["branches"]) == (2, 3)  # len(branches) or a non-distinct count: 3


def test_unreadable_cards_are_counted_and_left_out_of_both_sums():
    run = make_run("r1", features=[feature("a", "2/4"), feature("b", UNREADABLE),
                                   feature("c", UNREADABLE), feature("d", "10/10")])
    row = only_row(run)
    assert (row["tasksDone"], row["tasksTotal"]) == (12, 14)  # a one-digit pattern sums 2/4 only
    assert row["unreadableCards"] == 2  # a flag instead of a count gives 1
    assert row["features"] == 4  # an unreadable card is still a card


def test_a_run_whose_every_card_is_unreadable_sums_to_zero_and_counts_them():
    row = only_row(make_run("r1", features=[feature("a", UNREADABLE), feature("b", UNREADABLE)]))
    assert (row["tasksDone"], row["tasksTotal"], row["unreadableCards"]) == (0, 0, 2)


def test_a_run_with_empty_lists_shows_real_zeros():
    row = only_row(make_run("r1", dir="~/dev", analyzedAt="2026-11-03T09:13:20Z",
                            branches=[], features=[], waves=[], questions=[]))
    assert {key: row[key] for key in FIGURES} == dict.fromkeys(FIGURES, 0)
    assert all(type(row[key]) is int for key in FIGURES)  # an empty list is present, not absent


def test_a_run_holding_only_id_and_name_is_listed_with_a_dash_for_every_figure():
    bare = {"id": "rbare", "name": "seeded by test_autolaunch"}
    rows = rows_of([bare, full_run("r2")])
    assert sorted(row["id"] for row in rows) == ["r2", "rbare"]  # still listed
    row = {r["id"]: r for r in rows}["rbare"]
    assert {key: row[key] for key in FIGURES} == dict.fromkeys(FIGURES, DASH)
    assert row["name"] == "seeded by test_autolaunch"
    assert all(value is not None for value in row.values())
    assert row["tasksDone"] != 0 and row["tasksTotal"] != 0  # no bar: nothing reads as a zero


def test_dir_and_analyzed_at_read_dash_when_the_run_lacks_them():
    row = only_row({"id": "rbare", "name": "n"}, others=[full_run("r2")])
    assert (row["dir"], row["analyzedAt"]) == (DASH, DASH)


def test_each_figure_follows_only_its_own_key():
    del_features = full_run()
    del del_features["features"]
    no_features = only_row(del_features)
    assert (no_features["repos"], no_features["branches"], no_features["worktrees"]) == (2, 5, 2)
    assert {no_features[k] for k in ("features", "tasksDone", "tasksTotal",
                                     "unreadableCards")} == {DASH}
    del_branches = full_run()
    del del_branches["branches"]
    no_branches = only_row(del_branches)
    assert {no_branches[k] for k in ("repos", "branches", "worktrees")} == {DASH}
    assert (no_branches["features"], no_branches["tasksDone"], no_branches["tasksTotal"],
            no_branches["unreadableCards"]) == (5, 13, 17, 2)


# ---------------------------------------------------------------- G4: order and canDelete

def dated(run_id, analyzed=None):
    return make_run(run_id) if analyzed is None else make_run(run_id, analyzedAt=analyzed)


def ids_of(rows):
    return [row["id"] for row in rows]


def test_rows_sort_newest_first_and_ties_keep_store_order():
    store = [dated("a", "2026-11-02T10:00:00Z"), dated("b", "2026-11-02T10:00:00Z"),
             dated("old", "2026-11-01T08:00:00Z"), dated("new", "2026-11-03T09:13:20Z"),
             dated("t1", "2026-11-02T10:00:00Z")]
    # ascending gives old first; reversing an ascending sort flips the tie to t1, b, a.
    assert ids_of(rows_of(store)) == ["new", "a", "b", "t1", "old"]


def test_a_run_without_analyzed_at_sorts_after_every_run_that_has_one():
    store = [dated("none1"), dated("a", "2026-11-02T10:00:00Z"), dated("none2"),
             dated("old", "2000-01-01T00:00:00Z")]
    # keyed on the display string "—" (U+2014), a missing date would sort above every digit.
    assert ids_of(rows_of(store)) == ["a", "old", "none1", "none2"]


def test_can_delete_is_true_only_while_more_than_one_run_is_visible():
    two = rows_of([dated("a", "2026-11-02T00:00:00Z"), dated("b", "2026-11-01T00:00:00Z")])
    one = rows_of([dated("a", "2026-11-02T00:00:00Z")])
    assert [row["canDelete"] for row in two] == [True, True]
    assert [row["canDelete"] for row in one] == [False]
    assert one[0]["canDelete"] is False and two[0]["canDelete"] is True  # a JSON boolean


def test_hidden_runs_are_left_out_before_can_delete_is_decided():
    store = [dated("a", "2026-11-03T00:00:00Z"), dated("b", "2026-11-02T00:00:00Z"),
             dated("c", "2026-11-01T00:00:00Z")]
    two_visible = rows_of(store, hidden=["b"])
    assert ids_of(two_visible) == ["a", "c"]
    assert [row["canDelete"] for row in two_visible] == [True, True]
    last_visible = rows_of(store, hidden=["b", "c"])
    assert ids_of(last_visible) == ["a"]
    assert last_visible[0]["canDelete"] is False  # len(runs) > 1 would say True
    assert rows_of(store, hidden=["a", "b", "c"]) == []


def test_a_hidden_id_no_run_has_hides_nothing_and_counts_for_nothing():
    store = [dated("a", "2026-11-02T00:00:00Z"), dated("b", "2026-11-01T00:00:00Z")]
    rows = rows_of(store, hidden=["gone"])
    assert ids_of(rows) == ["a", "b"]
    assert [row["canDelete"] for row in rows] == [True, True]  # len(runs) - len(hidden) would be 1


def test_rows_are_computed_on_every_call_and_the_inputs_are_left_alone():
    runs = [dated("r0", "2026-11-01T00:00:00Z"), full_run("r1")]  # store order is oldest first
    hidden = ["nobody"]
    before = copy.deepcopy((runs, hidden))
    first = {row["id"]: row for row in ledger_state.run_rows(runs, hidden)}
    assert (runs, hidden) == before  # sorting the store's own list in place would reorder it
    runs[1]["features"].append(feature("six", "1/1"))
    second = {row["id"]: row for row in ledger_state.run_rows(runs, hidden)}
    assert (first["r1"]["features"], second["r1"]["features"]) == (5, 6)  # a cached row says 5
    assert (first["r1"]["tasksDone"], second["r1"]["tasksDone"]) == (13, 14)
