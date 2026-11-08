"""Section 8.1's name, dir and queue label (docs/features/treko-ledger.spec.md), in `ledger_state.py`.

Companion to `test_ledger_state.py` (G1 and G4), which is at its line cap. The signatures are the
coordinator's, from the spec's wording and the same inputs as `run_id`:
`run_name(directory, repo, branch, worktree)`, `run_dir(directory)` and
`queue_label(directory, repo, branch, worktree)`. The directory is already canonical (section 3.4).

  name  = the directory's last component, then " · repo <r>", " · branch <b>", " · worktree <w>"
          for each narrowing that is not "", in that order.
  dir   = the directory with the home folder replaced by "~", only where home is a whole path
          component; anything else is unchanged.
  label = dir where the name has the last component, then the same parts, joined by " · "
          (the prototype's `parts.join(' · ')`, Ledger.dc.html:176-177, which drops empty parts).

Worktrees below are bare names: whether a worktree *path* is shown as typed, canonical or
home-collapsed is not in the spec.

Run:  see section 15 of the spec (the pinned `uv run ... pytest` command).
"""

import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import ledger_state  # noqa: E402  — path shim above must run first

SEP = " · "  # the middle dot, with a space each side
NARROWINGS = [  # (repo, branch, worktree): every subset of the three, then "x" in each slot alone
    ("", "", ""), ("memsearch", "", ""), ("", "main", ""), ("", "", "wt-a"),
    ("memsearch", "main", ""), ("memsearch", "", "wt-a"), ("", "main", "wt-a"),
    ("memsearch", "main", "wt-a"), ("x", "", ""), ("", "x", ""), ("", "", "x"),
]


@pytest.fixture
def home(tmp_path, monkeypatch):
    """A fake home with a `dev` folder, a sibling `homework` that shares its name prefix."""
    folder = tmp_path / "home"
    (folder / "dev").mkdir(parents=True)
    (tmp_path / "homework" / "dev").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(folder))
    return folder


def name(directory, repo="", branch="", worktree=""):
    return ledger_state.run_name(directory, repo, branch, worktree)


def label(directory, repo="", branch="", worktree=""):
    return ledger_state.queue_label(directory, repo, branch, worktree)


# ---------------------------------------------------------------- dir

def test_a_folder_inside_home_is_collapsed_to_a_tilde(home):
    assert ledger_state.run_dir(str(home / "dev")) == "~/dev"
    assert ledger_state.run_dir(str(home / "dev" / "a" / "b")) == "~/dev/a/b"
    assert ledger_state.run_dir(str(home)) == "~"


def test_a_folder_outside_home_is_left_as_it_is(home):
    for outside in ("/opt/x/dev", "/", str(home.parent / "elsewhere" / "dev")):
        assert ledger_state.run_dir(outside) == outside


def test_a_sibling_sharing_the_home_name_as_a_prefix_is_not_inside_home(home):
    sibling = home.parent / "homework" / "dev"
    assert str(sibling).startswith(str(home))  # a plain startswith would give "~work/dev"
    assert ledger_state.run_dir(str(sibling)) == str(sibling)
    assert ledger_state.run_dir(str(home.parent / "homework")) == str(home.parent / "homework")


# ---------------------------------------------------------------- name

def test_a_name_is_the_last_component_then_one_labelled_part_per_narrowing(home):
    folder = str(home / "dev")
    assert name(folder) == "dev"
    assert name(folder, "memsearch") == "dev" + SEP + "repo memsearch"  # section 3.3's example
    assert name(folder, branch="main") == "dev" + SEP + "branch main"
    assert name(folder, worktree="wt-a") == "dev" + SEP + "worktree wt-a"
    assert name(folder, "memsearch", "main") == "dev" + SEP + "repo memsearch" + SEP + "branch main"
    assert name(folder, "memsearch", "main", "wt-a") == SEP.join(
        ["dev", "repo memsearch", "branch main", "worktree wt-a"])


def test_the_parts_keep_their_order_whichever_of_them_are_present(home):
    folder = str(home / "dev")  # a name that appended parts as they were given would reorder these
    assert name(folder, "r", "", "w") == SEP.join(["dev", "repo r", "worktree w"])
    assert name(folder, "", "b", "w") == SEP.join(["dev", "branch b", "worktree w"])


def test_a_name_uses_the_folder_name_not_the_collapsed_path(home):
    assert name(str(home / "dev")) == "dev"  # "~/dev" is the label's job
    assert name("/opt/x/dev") == "dev"


def test_two_runs_of_one_folder_with_different_narrowings_have_different_names(home):
    names = [name(str(home / "dev"), *narrowing) for narrowing in NARROWINGS]
    assert len(set(names)) == len(NARROWINGS), names  # leaving the "repo " word out merges x/x/x


# ---------------------------------------------------------------- queue label

def test_a_label_is_the_collapsed_directory_then_the_same_parts(home):
    folder = str(home / "dev")
    assert label(folder) == "~/dev"
    assert label(folder, "memsearch") == "~/dev" + SEP + "repo memsearch"  # section 3.3's example
    assert label(folder, "memsearch", "main", "wt-a") == SEP.join(
        ["~/dev", "repo memsearch", "branch main", "worktree wt-a"])
    assert label(folder, "", "b", "w") == SEP.join(["~/dev", "branch b", "worktree w"])
    assert label(folder) == ledger_state.run_dir(folder)  # nothing is added when nothing narrows


def test_a_label_outside_home_is_not_mangled(home):
    assert label("/opt/x/dev", "", "main") == SEP.join(["/opt/x/dev", "branch main"])
    sibling = str(home.parent / "homework" / "dev")
    assert label(sibling, "memsearch") == SEP.join([sibling, "repo memsearch"])


def test_a_label_is_built_on_the_directory_where_a_name_uses_its_last_component(home):
    first, second = str(home / "dev"), str(home.parent / "homework" / "dev")
    assert name(first) == name(second) == "dev"  # one folder name, two places
    assert label(first) != label(second)
    assert label(first, "memsearch") != name(first, "memsearch")


def test_two_runs_of_one_folder_with_different_narrowings_have_different_labels(home):
    labels = [label(str(home / "dev"), *narrowing) for narrowing in NARROWINGS]
    assert len(set(labels)) == len(NARROWINGS), labels


def test_a_label_parts_after_the_directory_equal_the_names_parts(home):
    folder = str(home / "dev")
    for narrowing in NARROWINGS:
        tail = name(folder, *narrowing).split(SEP, 1)[1:]
        assert label(folder, *narrowing).split(SEP, 1)[1:] == tail
