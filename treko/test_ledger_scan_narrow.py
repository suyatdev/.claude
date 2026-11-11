"""C4 and C5 (docs/features/treko-ledger.spec.md, section 11 C): `ledger_scan.py` narrows its families by
`repo`, `branch` and `worktree`, keeps every card the kept cards depend on, and chooses each card's live copy.

The request is `{"directory", "repo", "branch", "worktree"}` as JSON on stdin and the answer one JSON object
(section 4.4), exit 0 for every outcome. This file reuses task 11's fixtures from `test_ledger_scan_more.py`
(real throwaway git repositories and worktrees under `tmp_path`, global git config cut off) and drives the
scan the same way. It is a separate file because `test_ledger_scan.py` and `test_ledger_scan_more.py` already
hold 375 and 504 lines and the 800-line cap leaves no room there.

Cards are written straight into each folder's `docs/features/` and never committed, so a worktree holds
exactly the copies a test puts in it. `families[].cards` is read as a set of file paths (the order of the
list is the analyzer's business, section 4.3); a card name appearing twice in it is itself a failure.
Each test names the wrong shortcut it catches.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_ledger_scan_more import (  # noqa: E402,F401  — `world` is a fixture
    MISSED_STEM, RUN_LIMIT_SECS, SCAN, add_worktree, asked, build_missed, check_shape, git, make_repo, world,
)

COPY_STEM = "Which copy of"


def copy_question(name):
    return "Which copy of `%s` is current?" % name


# ------------------------------------------------------------------------------------ helpers

def narrow(world, directory=None, **narrowing):
    """The scan as the server launches it, with `repo`/`branch`/`worktree` given; the result is shape-checked."""
    request = {"directory": str(directory or world.tree), "repo": "", "branch": "", "worktree": ""}
    request.update(narrowing)
    proc = subprocess.Popen([sys.executable, str(SCAN)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, env=world.env, cwd=str(world.base))
    try:
        out, err = proc.communicate(json.dumps(request), timeout=RUN_LIMIT_SECS)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise AssertionError("the scan was still running after %d s: a closure that never ends?" % RUN_LIMIT_SECS)
    assert proc.returncode == 0, "the scan exited %s; stderr: %s" % (proc.returncode, err[-600:])
    result = json.loads(out)
    check_shape(result)
    return result


def wt(world, main, folder, branch):
    """A worktree of `main` at <home>/wts/<repo>/<folder>, on a new branch. git lists linked worktrees by name."""
    path = world.base / "home" / "wts" / main.name / folder
    path.parent.mkdir(parents=True, exist_ok=True)
    return add_worktree(world, main, path, branch)


def write_card(folder, name, branch="none", depends=(), raw=None):
    """`<folder>/docs/features/<name>.md`; `raw` writes those bytes instead. Returns the path as a string."""
    path = folder / "docs" / "features" / (name + ".md")
    path.parent.mkdir(parents=True, exist_ok=True)
    if raw is not None:
        path.write_bytes(raw)
        return str(path)
    text = "---\nphase: implementation\nmodel_tier: high\nbranch: %s\n---\n\n# %s\n\n## Tasks\n\n- [ ] 1 — first\n" % (branch, name)
    if depends:
        text += "\n## Depends on\n\n" + "".join("- `%s` — needed first\n" % target for target in depends)
    path.write_text(text, encoding="utf-8")
    return str(path)


def family_of(result, primary):
    [family] = [candidate for candidate in result["families"] if candidate["root"] == str(primary)]
    return family


def cards_of(result, primary):
    """The sorted `cards` paths of one family of an `ok` result; each card name must appear once."""
    assert result["outcome"] == "ok", result["outcome"]
    family = family_of(result, primary)
    assert "cards" in family, "the family has no `cards` key: %r" % sorted(family)
    names = [Path(path).name for path in family["cards"]]
    assert len(set(names)) == len(names), "a card appears twice: %r" % names
    return sorted(family["cards"])


def paths(*files):
    return sorted(str(item) for item in files)


def copy_questions(result, primary):
    return [question for question in family_of(result, primary).get("questions", []) if question["q"].startswith(COPY_STEM)]


def kept_roots(result):
    assert result["outcome"] == "ok", result["outcome"]
    return [family["root"] for family in result["families"]]


# ------------------------------------------------------------------------------- C4: repo

@pytest.fixture
def named(world):
    """memsearch (with a worktree folder named digest), memsearch-old and mem; one card each."""
    made = {name: make_repo(world, world.tree / name) for name in ("memsearch", "memsearch-old", "mem")}
    made["digest"] = wt(world, made["memsearch"], "digest", "feat-digest")
    made["cards"] = {name: write_card(made[name], "card-" + name) for name in ("memsearch", "memsearch-old", "mem")}
    return made


def test_repo_keeps_the_family_whose_primary_folder_name_is_exactly_that(named, world):
    """Substring or prefix matching keeps memsearch-old (and `mem` would keep all three); ignoring `repo` keeps all."""
    result = narrow(world, repo="memsearch")
    assert kept_roots(result) == [str(named["memsearch"])]
    assert cards_of(result, named["memsearch"]) == paths(named["cards"]["memsearch"])


@pytest.mark.parametrize("repo", ["search", "memsearc", "Memsearch", "digest"])
def test_repo_that_is_a_part_of_a_name_another_case_or_a_worktree_folder_matches_nothing(named, world, repo):
    """A substring, a prefix, a case-folded compare, or taking the name from a worktree's folder instead of the
    primary checkout's would each keep a family here; they must answer no_matching_repository."""
    assert narrow(world, repo=repo)["outcome"] == "no_matching_repository"


def test_two_families_with_one_folder_name_are_both_kept_by_repo(world):
    """Keeping only the first family named `proj` loses `two/proj`."""
    one = make_repo(world, world.tree / "one" / "proj")
    two = make_repo(world, world.tree / "two" / "proj")
    make_repo(world, world.tree / "other")
    write_card(one, "card-one")
    write_card(two, "card-two")
    result = narrow(world, repo="proj")
    assert kept_roots(result) == [str(one), str(two)]
    assert cards_of(result, two) == paths(two / "docs/features/card-two.md")


def test_without_narrowing_every_family_lists_its_cards_and_one_without_cards_lists_none(world):
    """A scan that drops families with no cards when nothing narrows loses `bare`; one that leaves out `cards`
    for it breaks the key section 4.4 gives every family."""
    full = make_repo(world, world.tree / "full")
    bare = make_repo(world, world.tree / "bare")
    first, second = write_card(full, "first"), write_card(full, "second")
    result = narrow(world)
    assert kept_roots(result) == [str(bare), str(full)]
    assert cards_of(result, full) == paths(first, second)
    assert cards_of(result, bare) == []


# ----------------------------------------------------------------------------- C4: branch

@pytest.fixture
def branched(world):
    """alpha: x-card and xy-card each on their own worktree's branch, bare-feat and plain on the primary.
    beta: beta-x on a worktree on feat-x, and beta-plain. gamma: one card on no branch."""
    alpha = make_repo(world, world.tree / "alpha")
    beta = make_repo(world, world.tree / "beta")
    gamma = make_repo(world, world.tree / "gamma")
    cards = {
        "x": write_card(wt(world, alpha, "wt-x", "feat-x"), "x-card", "feat-x"),
        "xy": write_card(wt(world, alpha, "wt-xy", "feat-x-2"), "xy-card", "feat-x-2"),
        "bare": write_card(alpha, "bare-feat", "feat"),
        "plain": write_card(alpha, "plain"),
        "beta-x": write_card(wt(world, beta, "wt-x", "feat-x"), "beta-x", "feat-x"),
        "beta-plain": write_card(beta, "beta-plain"),
        "gamma": write_card(gamma, "gamma-card"),
    }
    return {"alpha": alpha, "beta": beta, "gamma": gamma, "cards": cards}


def test_branch_keeps_each_familys_cards_on_exactly_that_branch_and_drops_families_without(branched, world):
    """Prefix matching (`feat-x`) keeps xy-card; ignoring branch keeps gamma; keeping empty families lists gamma."""
    made, result = branched, narrow(world, branch="feat-x")
    assert kept_roots(result) == [str(made["alpha"]), str(made["beta"])]
    assert cards_of(result, made["alpha"]) == paths(made["cards"]["x"])
    assert cards_of(result, made["beta"]) == paths(made["cards"]["beta-x"])


def test_branch_that_is_a_prefix_of_another_branch_keeps_only_the_card_naming_it(branched, world):
    """`feat` is a prefix of `feat-x` and `feat-x-2`; a startswith or `in` compare keeps all three of alpha's."""
    result = narrow(world, branch="feat")
    assert kept_roots(result) == [str(branched["alpha"])]
    assert cards_of(result, branched["alpha"]) == paths(branched["cards"]["bare"])


@pytest.mark.parametrize("branch", ["FEAT-X", "feat-", "feat-y"])
def test_branch_nothing_names_exactly_is_nothing_matched(branched, world, branch):
    """A case-folded or prefix compare keeps a card."""
    assert narrow(world, branch=branch)["outcome"] == "nothing_matched"


def test_branch_is_compared_after_card_branch_normalization(world):
    """`Card.branch` drops a trailing YAML comment (`  # PR #39 (…)`) and surrounding blanks. A raw-line compare
    misses both; a card whose value is only `none  # note` has no branch, and a `—` value neither."""
    repo = make_repo(world, world.tree / "repo")
    commented = write_card(repo, "commented", "feat/ledger  # PR #39 (merged later)")
    spaced = write_card(repo, "spaced", "   feat/ledger   ")
    write_card(repo, "dashed", "—")
    write_card(repo, "none-noted", "none  # merged via PR #39")
    write_card(repo, "longer", "feat/ledger-v2")
    result = narrow(world, branch="feat/ledger")
    assert cards_of(result, repo) == paths(commented, spaced)


def test_repo_and_branch_together_keep_only_that_repos_matching_cards(branched, world):
    """`repo` ignored when `branch` is given keeps beta as well; `branch` ignored keeps alpha's other cards."""
    result = narrow(world, repo="beta", branch="feat-x")
    assert kept_roots(result) == [str(branched["beta"])]
    assert cards_of(result, branched["beta"]) == paths(branched["cards"]["beta-x"])


def test_a_repo_that_exists_with_no_card_on_the_branch_is_nothing_matched_and_a_missing_one_is_not(branched, world):
    """Answering no_matching_repository whenever the branch finds nothing, or nothing_matched whenever the
    repo is missing, swaps the two outcomes."""
    assert narrow(world, repo="gamma", branch="feat-x")["outcome"] == "nothing_matched"
    assert narrow(world, repo="delta", branch="feat-x")["outcome"] == "no_matching_repository"


# --------------------------------------------------------------------------- C4: worktree

@pytest.fixture
def worktrees(world):
    """alpha: wt-a (feat-a, card a-card), wt-b (feat-b, card b-card), wt-empty (feat-empty, no card), and on
    the primary `claims-a` (names feat-a, no other copy) and `plain`. beta: its own folder wt-a (feat-q)."""
    alpha = make_repo(world, world.tree / "alpha")
    beta = make_repo(world, world.tree / "beta")
    folders = {"wt-a": wt(world, alpha, "wt-a", "feat-a"), "wt-b": wt(world, alpha, "wt-b", "feat-b"),
               "wt-empty": wt(world, alpha, "wt-empty", "feat-empty"), "beta-wt-a": wt(world, beta, "wt-a", "feat-q")}
    cards = {
        "a": write_card(folders["wt-a"], "a-card", "feat-a"), "b": write_card(folders["wt-b"], "b-card", "feat-b"),
        "claims-a": write_card(alpha, "claims-a", "feat-a"), "plain": write_card(alpha, "plain"),
        "q": write_card(folders["beta-wt-a"], "q-card", "feat-q"), "beta-plain": write_card(beta, "beta-plain"),
    }
    return {"alpha": alpha, "beta": beta, "folders": folders, "cards": cards}


def _alias(world, folder):
    link = world.base / "alias"
    link.symlink_to(folder, target_is_directory=True)
    return str(link)


FORMS = {  # each names alpha's wt-a, and no folder name equals the string given
    "resolved path": lambda world, folder: str(folder),
    "tilde": lambda world, folder: "~/wts/alpha/wt-a",
    "symlink to it": _alias,
    "trailing slash": lambda world, folder: str(folder) + "/",
    "dot-dot": lambda world, folder: str(folder.parent / "wt-b" / ".." / "wt-a"),
}


@pytest.mark.parametrize("form", FORMS)
def test_worktree_given_as_a_path_is_expanded_and_resolved_before_it_is_compared(worktrees, world, form):
    """A string compare against git's path misses `~`, a symlink, a trailing slash and `..`. Only alpha has
    this worktree, so beta (whose own folder is also called wt-a) must not be kept by a name match either."""
    given = FORMS[form](world, worktrees["folders"]["wt-a"])
    result = narrow(world, worktree=given)
    assert kept_roots(result) == [str(worktrees["alpha"])]
    assert cards_of(result, worktrees["alpha"]) == paths(worktrees["cards"]["a"], worktrees["cards"]["claims-a"])


def test_worktree_given_as_a_folder_name_applies_in_every_family_that_has_one_so_named(worktrees, world):
    """A name match that stops at the first family, or one that applies alpha's branch to beta, loses beta's q-card."""
    result = narrow(world, worktree="wt-a")
    assert kept_roots(result) == [str(worktrees["alpha"]), str(worktrees["beta"])]
    assert cards_of(result, worktrees["alpha"]) == paths(worktrees["cards"]["a"], worktrees["cards"]["claims-a"])
    assert cards_of(result, worktrees["beta"]) == paths(worktrees["cards"]["q"])


def test_worktree_keeps_cards_by_the_branch_their_chosen_copy_names_not_by_where_the_file_sits(worktrees, world):
    """claims-a sits in the primary checkout but its only copy names feat-a, wt-a's branch: kept for wt-a, and
    not for wt-b. A filter on the files under the worktree's folder drops it for wt-a; one that keeps
    everything in the primary checkout keeps it, and `plain`, for wt-b."""
    wide = narrow(world, worktree="wt-a", repo="alpha")
    assert cards_of(wide, worktrees["alpha"]) == paths(worktrees["cards"]["a"], worktrees["cards"]["claims-a"])
    result = narrow(world, worktree="wt-b")
    assert cards_of(result, worktrees["alpha"]) == paths(worktrees["cards"]["b"])
    assert kept_roots(result) == [str(worktrees["alpha"])]


@pytest.mark.parametrize("worktree,branch,kept", [("wt-a", "feat-a", True), ("wt-a", "feat-b", False), ("wt-b", "feat-a", False)])
def test_worktree_and_branch_together_must_both_hold(worktrees, world, worktree, branch, kept):
    """An OR keeps b-card for (wt-a, feat-b); a scan that uses only `branch` keeps a-card for (wt-b, feat-a);
    one that uses only `worktree` keeps a-card for (wt-a, feat-b)."""
    result = narrow(world, worktree=worktree, branch=branch, repo="alpha")
    if kept:
        assert cards_of(result, worktrees["alpha"]) == paths(worktrees["cards"]["a"], worktrees["cards"]["claims-a"])
    else:
        assert result["outcome"] == "nothing_matched"


def test_a_worktree_with_no_card_naming_its_branch_is_nothing_matched(worktrees, world):
    """The worktree exists, so no_such_worktree would be the wrong answer; ignoring it would keep every card."""
    assert narrow(world, worktree="wt-empty")["outcome"] == "nothing_matched"


def test_a_family_whose_worktrees_do_not_match_is_dropped_but_the_scan_is_not_no_such_worktree(worktrees, world):
    """Only alpha has wt-b: beta is dropped, and the outcome stays ok because some family has the worktree."""
    result = narrow(world, worktree="wt-b")
    assert kept_roots(result) == [str(worktrees["alpha"])]


def test_a_worktree_no_found_repository_has_is_no_such_worktree(worktrees, world):
    """Each value names no registered worktree: unknown name, an existing folder that is no worktree, a plain
    folder whose name is `wt-a`, and the typed tree. A basename compare on the given path accepts the decoy;
    a scan that answers nothing_matched for these cannot tell a missing worktree from a card-less one."""
    decoy = world.base / "decoy" / "wt-a"
    decoy.mkdir(parents=True)
    for given in ("no-such-wt", str(world.tree), str(decoy), str(world.base / "never" / "created")):
        assert narrow(world, worktree=given)["outcome"] == "no_such_worktree", given
    assert narrow(world, worktree="wt-a")["outcome"] == "ok"


def test_a_worktree_removed_since_is_no_such_worktree(worktrees, world):
    """A scan that remembers worktrees, or reads them from the card folders, still finds wt-b after its removal."""
    git(world, "-C", str(worktrees["alpha"]), "worktree", "remove", "--force", str(worktrees["folders"]["wt-b"]))
    assert narrow(world, worktree="wt-b")["outcome"] == "no_such_worktree"


def test_no_such_worktree_is_decided_before_the_repo_has_cards(worktrees, world):
    """With a repo that exists and a worktree that does not, the answer is the worktree's, not ok or nothing_matched."""
    assert narrow(world, repo="alpha", worktree="wt-zzz")["outcome"] == "no_such_worktree"


# ---------------------------------------------------------------------------- C4: outcomes

@pytest.mark.parametrize("kind", ["missing", "a_file"])
def test_a_directory_that_is_gone_is_no_such_directory_with_exit_zero(world, kind):
    """The scan today walks a missing path, finds nothing and says no_repository; a file is no directory either."""
    target = world.base / "gone"
    if kind == "a_file":
        target.write_text("x")
    result = narrow(world, directory=target)
    assert result["outcome"] == "no_such_directory" and result["families"] == []


def test_narrowing_does_not_turn_no_repository_into_another_outcome(world):
    """No repository anywhere stays no_repository even when branch/worktree/repo are given (a scan that
    answers nothing_matched or no_matching_repository whenever narrowing is present fails)."""
    (world.tree / "empty").mkdir()
    for narrowing in ({"branch": "feat-x"}, {"repo": "proj"}, {"worktree": "wt"}):
        assert narrow(world, **narrowing)["outcome"] == "no_repository", narrowing


# ---------------------------------------------------------------------------- C4: closure

def test_dependencies_are_kept_transitively_within_the_family_from_the_chosen_copy(world):
    """top's live copy (in wt-top) depends on mid and a missing card; mid on base; base back on top (a cycle).
    `top`'s primary copy lists nothing, so edges read from the primary lose mid; a one-level closure loses
    base; a cycle-blind closure never ends; a card that does not exist must not crash; `elsewhere` is a card
    of another family, which is not followed, so beta is dropped. `unrelated` stays out."""
    alpha = make_repo(world, world.tree / "alpha")
    beta = make_repo(world, world.tree / "beta")
    wt_top = wt(world, alpha, "wt-top", "feat-top")
    top = write_card(wt_top, "top", "feat-top", depends=["mid", "ghost", "elsewhere"])
    write_card(alpha, "top")  # the primary's stale copy: no branch, no dependencies
    mid = write_card(alpha, "mid", depends=["base"])
    base = write_card(alpha, "base", depends=["top"])
    write_card(alpha, "unrelated")
    write_card(beta, "elsewhere")
    for narrowing in ({"branch": "feat-top"}, {"worktree": "wt-top"}):
        result = narrow(world, **narrowing)
        assert kept_roots(result) == [str(alpha)], narrowing
        assert cards_of(result, alpha) == paths(top, mid, base), narrowing


def test_a_dependency_is_kept_as_its_own_chosen_copy(world):
    """`dep` has a copy in wt-dep that is on its branch and a stale one on the primary: the kept path is the
    live one, which a closure that adds the primary's file by name gets wrong."""
    alpha = make_repo(world, world.tree / "alpha")
    top = write_card(wt(world, alpha, "wt-top", "feat-top"), "top", "feat-top", depends=["dep"])
    live = write_card(wt(world, alpha, "wt-dep", "feat-dep"), "dep", "feat-dep")
    write_card(alpha, "dep")
    assert cards_of(narrow(world, branch="feat-top"), alpha) == paths(top, live)


# ------------------------------------------------------------------------ C4: kept whole

def test_questions_and_missed_are_kept_whole_when_cards_are_narrowed_away(world):
    """Narrowing removes cards and nothing else: the family question about `disputed` (two copies on their
    branches) stays although `disputed` is not kept, and the scan's own question and counts are unchanged.
    A narrowing that filters questions by kept cards, or rebuilds the result, loses them."""
    build_missed(world, symlinks=1)
    alpha = make_repo(world, world.tree / "alpha")
    kept = write_card(wt(world, alpha, "wt-k", "feat-k"), "kept", "feat-k")
    write_card(wt(world, alpha, "wt-d1", "feat-d1"), "disputed", "feat-d1")
    write_card(wt(world, alpha, "wt-d2", "feat-d2"), "disputed", "feat-d2")
    whole = narrow(world)
    assert [q["q"] for q in family_of(whole, alpha).get("questions", [])] == [copy_question("disputed")]
    narrowed = narrow(world, branch="feat-k")
    assert cards_of(narrowed, alpha) == paths(kept)
    assert family_of(narrowed, alpha)["questions"] == family_of(whole, alpha)["questions"]
    assert narrowed["questions"] == whole["questions"] and len(asked(narrowed, MISSED_STEM)) == 1
    assert narrowed["missed"] == whole["missed"]


# ----------------------------------------------------------------------------- C5: the rule

def test_rule_1_a_copy_on_its_branch_beats_the_primarys_and_asks_nothing(world):
    """The primary's copy still says `branch: none` (a planning card) while the worktree copy names the branch:
    the worktree copy is chosen. Always taking the primary's copy picks the other; taking the last one found
    does too when the walk meets the primary last. One on-branch copy is no disagreement."""
    main = make_repo(world, world.tree / "proj")
    write_card(main, "card")
    live = write_card(wt(world, main, "wt-live", "feat-live"), "card", "feat-live")
    result = narrow(world)
    assert cards_of(result, main) == paths(live)
    assert copy_questions(result, main) == []


def test_rule_1_the_planning_card_is_found_by_the_branch_its_worktree_copy_names(world):
    """Branch narrowing reads the chosen copy: a scan that reads the primary's copy sees `none` and answers
    nothing_matched."""
    main = make_repo(world, world.tree / "proj")
    write_card(main, "card")
    live = write_card(wt(world, main, "wt-live", "feat-live"), "card", "feat-live")
    assert cards_of(narrow(world, branch="feat-live"), main) == paths(live)


def test_rule_1_a_primary_copy_that_only_claims_the_branch_does_not_win(world):
    """The primary (on main) says `branch: feat-claimed`, so it is not on its branch; wt-live's copy is. The
    chosen copy names feat-live, so a search by feat-claimed finds nothing. A scan that matches `branch` against
    any copy keeps the card for feat-claimed."""
    main = make_repo(world, world.tree / "proj")
    write_card(main, "card", "feat-claimed")
    live = write_card(wt(world, main, "wt-live", "feat-live"), "card", "feat-live")
    assert cards_of(narrow(world), main) == paths(live)
    assert narrow(world, branch="feat-claimed")["outcome"] == "nothing_matched"
    assert cards_of(narrow(world, branch="feat-live"), main) == paths(live)


def test_rule_2_a_copy_naming_another_branch_than_its_worktrees_is_not_on_its_branch(world):
    """wt-a is on feat-a but its copy says feat-other: not on its branch, so the primary's copy is chosen. A scan
    that treats any non-`none` branch as on-branch picks the worktree copy; none of this asks a question."""
    main = make_repo(world, world.tree / "proj")
    chosen = write_card(main, "card")
    write_card(wt(world, main, "wt-a", "feat-a"), "card", "feat-other")
    result = narrow(world)
    assert cards_of(result, main) == paths(chosen)
    assert copy_questions(result, main) == []


def test_rule_2_a_copy_that_cannot_be_read_is_never_on_its_branch(world):
    """wt-live's copy is not UTF-8, so it is not on its branch even though the worktree's branch is feat-live and
    the file exists: the primary's copy is chosen. A scan that decides by the file existing picks the broken copy
    and one that lets the read error escape exits non-zero."""
    main = make_repo(world, world.tree / "proj")
    chosen = write_card(main, "card")
    write_card(wt(world, main, "wt-live", "feat-live"), "card", raw=b"---\nbranch: feat-live\n---\n\xff\xfe\n")
    result = narrow(world)
    assert cards_of(result, main) == paths(chosen)
    assert copy_questions(result, main) == []


def test_rule_3_with_no_primary_copy_the_first_listed_worktrees_is_chosen(world):
    """The copies are in first-wt and second-wt, neither on its branch, none on the primary. git lists linked
    worktrees by name, so first-wt is first even though second-wt is created first; the primary's `plain` card
    has no copy elsewhere. Taking the last copy, or the creation order, picks the other; no question is asked."""
    main = make_repo(world, world.tree / "proj")
    second = wt(world, main, "second-wt", "feat-second")
    first = wt(world, main, "first-wt", "feat-first")
    write_card(second, "card")
    chosen = write_card(first, "card")
    plain = write_card(main, "plain")
    result = narrow(world)
    assert cards_of(result, main) == paths(chosen, plain)
    assert copy_questions(result, main) == []


def test_rule_1_several_copies_on_their_branches_choose_the_first_listed_and_ask_which_is_current(world):
    """first-wt and second-wt each hold a copy on its own branch; the primary's does not. The first listed wins
    (second-wt is created first), and the family is asked "Which copy of `shared` is current?" once, naming both
    worktrees. A scan that asks nothing, asks in the scan-level questions, asks once per copy, or picks the last
    fails. Narrowing then reads the chosen copy: the branch of the loser finds nothing."""
    main = make_repo(world, world.tree / "proj")
    second = wt(world, main, "second-wt", "feat-second")
    first = wt(world, main, "first-wt", "feat-first")
    write_card(second, "shared", "feat-second")
    chosen = write_card(first, "shared", "feat-first")
    write_card(main, "shared")
    result = narrow(world)
    assert cards_of(result, main) == paths(chosen)
    [question] = copy_questions(result, main)
    assert question["q"] == copy_question("shared")
    assert "first-wt" in question["ctx"] and "second-wt" in question["ctx"], question["ctx"]
    assert asked(result, COPY_STEM) == [], "the question belongs to the family, not to the scan"
    assert narrow(world, branch="feat-second")["outcome"] == "nothing_matched"
    assert cards_of(narrow(world, branch="feat-first"), main) == paths(chosen)


def test_each_card_appears_once_though_every_worktree_holds_a_copy(world):
    """`dup` has a copy in the primary and in three worktrees. One entry per name: a scan that lists every copy
    returns four (cards_of fails on the repeat)."""
    main = make_repo(world, world.tree / "proj")
    for folder in ("wt-1", "wt-2", "wt-3"):
        write_card(wt(world, main, folder, "feat-" + folder), "dup")
    write_card(main, "dup")
    solo = write_card(wt(world, main, "wt-solo", "feat-solo"), "solo")
    found = cards_of(narrow(world), main)
    assert len(found) == 2 and solo in found
    assert sorted(Path(path).name for path in found) == ["dup.md", "solo.md"]


def test_spec_files_are_never_cards(world):
    """`x.spec.md` next to `x.md`, in the primary and in a worktree, and a `lonely.spec.md` with no `.md`
    partner. A glob of `*.md` lists the spec files; a worktree-only spec must not become a card either."""
    main = make_repo(world, world.tree / "proj")
    card = write_card(main, "x")
    other = wt(world, main, "wt-a", "feat-a")
    for folder in (main, other):
        (folder / "docs" / "features").mkdir(parents=True, exist_ok=True)
        (folder / "docs" / "features" / "x.spec.md").write_text("# spec\n")
    (other / "docs" / "features" / "lonely.spec.md").write_text("# spec\n")
    (other / "docs" / "features" / "notes.txt").write_text("not a card\n")
    assert cards_of(narrow(world), main) == paths(card)
