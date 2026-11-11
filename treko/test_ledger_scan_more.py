"""C1, C2, C3 and C6 (docs/features/treko-ledger.spec.md, section 11 C): `ledger_scan.py` finds every
repository in and around a typed directory, counts each once, and says what it could not look at.

The module runs as a subprocess: the request (`{"directory", "repo", "branch", "worktree"}`) as JSON on
stdin, one JSON object on stdout (section 4.4), exit 0 for every outcome. Every test drives it that way
over a real tree of throwaway git repositories under `tmp_path`, with global git config cut off.

What this file leaves to task 12 (C4, C5): narrowing, `no_such_directory`, and `families[].cards` /
`families[].questions` (section 4.3's copy choice). A family's worktrees have no output key in section 4.4,
so C3's "the family lists worktrees outside the scanned tree" is read through the one thing task 11 emits
from them: the family's root, the first worktree git lists that is not bare, prunable or gone.

Each test names the wrong shortcut it catches. Run: see section 15 of the spec (the pinned `uv run` line).
"""

import ast
import json
import os
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import ledger_merge  # noqa: E402  — C1's run-level sentence composes the scan with the real merge

SCAN = HERE / "ledger_scan.py"
GIT_TIMEOUT_SECS = 5  # section 4; a test below pins it to server.py's constant
RUN_LIMIT_SECS = 40  # this file's own bound on one scan run, not the server's TREKO_SCAN_SECS
RESULT_KEYS = {"outcome", "families", "questions", "missed"}
MISSED_KEYS = ("unreadable", "depthLimit", "symlinks")
NOTHING_MISSED = dict.fromkeys(MISSED_KEYS, 0)
CLAUSES = {  # section 7.2's three clauses, with their count
    "unreadable": "%d folders could not be listed",
    "depthLimit": "%d folders at depth 5 were not looked inside",
    "symlinks": "%d symlinked folders were not followed",
}
CLAUSE_STEMS = {"unreadable": "could not be listed", "depthLimit": "at depth 5", "symlinks": "symlinked"}
MISSED_TAIL = "so any repository inside them is missing from this run."
CONFIRM_ARGS = ["rev-parse", "--path-format=absolute", "--git-common-dir", "--show-toplevel"]

# A git on PATH that logs each call with its environment, hangs (a heartbeat file per call) for the
# calls a rule names, and otherwise runs the real git.
FAKE_GIT = r'''import json, os, sys, time
args = sys.argv[1:]
target = os.getcwd()
while len(args) >= 2 and args[0] == "-C":
    target = os.path.realpath(os.path.join(target, args[1]))
    args = args[2:]
with open(os.environ["FAKE_GIT_LOG"], "a") as log:
    log.write(json.dumps({"args": args, "target": target, "env": dict(os.environ)}) + "\n")
for rule in json.loads(os.environ["FAKE_GIT_HANG"]):
    if rule["has"] in args and (target == rule["path"] or target.startswith(rule["path"] + os.sep)):
        beat = os.path.join(os.environ["FAKE_GIT_BEATS"], str(os.getpid()))
        start = time.time()
        while time.time() - start < 40:
            with open(beat, "a") as handle:
                handle.write("%f\n" % time.time())
            time.sleep(0.1)
        sys.exit(1)
os.execv(os.environ["FAKE_GIT_REAL"], [os.environ["FAKE_GIT_REAL"]] + sys.argv[1:])
'''


# ------------------------------------------------------------------------------------ fixtures

@pytest.fixture
def world(tmp_path):
    """`tree` is the directory a test types; the rest of `base` is outside it."""
    base = tmp_path.resolve()
    (base / "home").mkdir()
    (base / "tree").mkdir()
    env = {"PATH": os.environ["PATH"], "HOME": str(base / "home"), "LC_ALL": "C",
           "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CEILING_DIRECTORIES": str(base),
           "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
           "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}
    world = SimpleNamespace(base=base, tree=base / "tree", env=env, locked=[])
    yield world
    for folder in world.locked:
        folder.chmod(0o755)


def git(world, *args):
    return subprocess.run(["git", *args], env=world.env, check=True, capture_output=True, text=True).stdout


def make_repo(world, path):
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    git(world, "-C", str(path), "init", "-q", "-b", "main")
    git(world, "-C", str(path), "commit", "-q", "--allow-empty", "-m", "fixture")
    return path


def add_worktree(world, repo, path, branch):
    git(world, "-C", str(repo), "worktree", "add", "-q", str(path), "-b", branch)
    return Path(path)


def install_fake_git(world, env, hang):
    (world.base / "fake_git.py").write_text(FAKE_GIT)
    (world.base / "fakebin").mkdir(exist_ok=True)
    (world.base / "beats").mkdir(exist_ok=True)
    wrapper = world.base / "fakebin" / "git"
    wrapper.write_text("#!/bin/sh\nexec %s %s \"$@\"\n" % (shlex.quote(sys.executable), shlex.quote(str(world.base / "fake_git.py"))))
    wrapper.chmod(0o755)
    env.update(FAKE_GIT_LOG=str(world.base / "calls.jsonl"), FAKE_GIT_BEATS=str(world.base / "beats"),
               FAKE_GIT_REAL=shutil.which("git", path=env["PATH"]), FAKE_GIT_HANG=json.dumps(hang),
               PATH=str(world.base / "fakebin") + os.pathsep + env["PATH"])


def git_calls(world):
    log = world.base / "calls.jsonl"
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def hung_lifetimes(world):
    """How long each hung fake-git call lived, first heartbeat to last, which the scan's kill ended."""
    lifetimes = []
    for beat in sorted((world.base / "beats").glob("*")):
        stamps = [float(line) for line in beat.read_text().split("\n")[:-1]]
        lifetimes.append(stamps[-1] - stamps[0])
    return lifetimes


def run_scan(world, directory, hang=None, env_extra=None):
    """The scan as the server launches it. `hang` (a list of rules) puts the fake git first on PATH."""
    env = dict(world.env, **(env_extra or {}))
    if hang is not None:
        install_fake_git(world, env, hang)
    request = {"directory": str(directory), "repo": "", "branch": "", "worktree": ""}
    proc = subprocess.Popen([sys.executable, str(SCAN)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, env=env, cwd=str(world.base), start_new_session=True)
    try:
        out, err = proc.communicate(json.dumps(request), timeout=RUN_LIMIT_SECS)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError("the scan was still running after %d s" % RUN_LIMIT_SECS)
    assert proc.returncode == 0, "the scan exited %s; stderr: %s" % (proc.returncode, err[-600:])
    result = json.loads(out)  # all of stdout must be the one object
    check_shape(result)
    return result


def check_shape(result):
    assert isinstance(result, dict) and set(result) == RESULT_KEYS, "keys: %r" % sorted(result)
    assert set(result["missed"]) == set(MISSED_KEYS)
    assert all(type(count) is int and count >= 0 for count in result["missed"].values())
    for question in result["questions"]:
        assert set(question) == {"q", "ctx"} and all(isinstance(text, str) for text in question.values())
    roots = [family["root"] for family in result["families"]]
    assert len(set(roots)) == len(roots), "a repository was counted twice: %r" % roots
    for family in result["families"]:
        assert {"root", "label"} <= set(family) <= {"root", "label", "cards", "questions"}
        assert family["label"] == Path(family["root"]).name


def roots(result):
    assert result["outcome"] == "ok", result["outcome"]
    return [family["root"] for family in result["families"]]


def asked(result, stem):
    return [question for question in result["questions"] if question["q"].startswith(stem)]


MISSED_STEM = "Were repositories missed under"
REFUSED_STEM = "Why could git not read"


def build_missed(world, unreadable=0, depth_limit=0, symlinks=0):
    """A tree with exactly these three counts of section 4.1. Unreadable folders need a user other than root."""
    if unreadable and os.geteuid() == 0:
        pytest.skip("root can list a mode-000 folder")
    (world.base / "link-target").mkdir(exist_ok=True)
    for number in range(unreadable):
        folder = world.tree / ("locked-%d" % number)
        folder.mkdir()
        folder.chmod(0)
        world.locked.append(folder)
    for number in range(depth_limit):
        (world.tree / ("deep-%d" % number) / "b" / "c" / "d" / "e").mkdir(parents=True)  # e is at depth 5
    for number in range(symlinks):
        (world.tree / ("link-%d" % number)).symlink_to(world.base / "link-target", target_is_directory=True)


# --------------------------------------------------------------------------------------- C1

def test_a_repo_at_depth_five_is_found_and_one_at_depth_six_is_not(world):
    """A limit of 4 loses `five`; a limit of 6 finds `six` and counts nothing."""
    five = make_repo(world, world.tree / "d1/d2/d3/d4/five")
    make_repo(world, world.tree / "d1/d2/d3/d4/d5/six")
    one = make_repo(world, world.tree / "d1/one")
    result = run_scan(world, world.tree)
    assert roots(result) == sorted([str(one), str(five)])
    assert result["missed"] == dict(NOTHING_MISSED, depthLimit=1)  # d5, the depth-5 folder that is no repository


def test_descent_stops_at_a_repository(world):
    """A scan that goes on into `outer` finds `inner`, and counts the depth-5 folder inside `outer`."""
    outer = make_repo(world, world.tree / "outer")
    make_repo(world, outer / "vendor" / "inner")
    (outer / "a/b/c/d/e").mkdir(parents=True)
    result = run_scan(world, world.tree)
    assert roots(result) == [str(outer)]
    assert result["missed"] == NOTHING_MISSED


def test_a_dot_git_file_stops_descent_like_a_dot_git_folder(world):
    """A stop that tests only for a `.git` directory goes into the worktree `wt` and finds `inner`."""
    main = make_repo(world, world.tree / "main")
    add_worktree(world, main, world.tree / "wt", "wt-branch")
    make_repo(world, world.tree / "wt" / "inner")
    assert roots(run_scan(world, world.tree)) == [str(main)]


def test_descent_stops_at_depth_zero_when_the_typed_directory_is_a_repository(world):
    """OQ-6: scanning the launch repo must not pull in repositories nested in it. A scan that checks for
    `.git` only below the root finds `nested`; one that adds the repo above as well counts the root twice."""
    make_repo(world, world.tree)
    make_repo(world, world.tree / "nested")
    result = run_scan(world, world.tree)
    assert roots(result) == [str(world.tree)]
    assert result["missed"] == NOTHING_MISSED


@pytest.mark.parametrize("kind", ["dot", "node_modules", "uf_hidden", "symlink", "skipped_at_depth_five"])
def test_skipped_folders_hide_their_repositories_and_only_symlinks_are_counted(world, kind):
    """Each skip rule alone. A scan lacking one finds the hidden repo; one that counts hidden folders or
    `node_modules` shows a depthLimit or a question; one that follows a link finds `linked`."""
    visible = make_repo(world, world.tree / "visible")
    symlinks = 0
    if kind == "symlink":
        (world.tree / "link").symlink_to(make_repo(world, world.base / "elsewhere" / "linked"), target_is_directory=True)
        symlinks = 1
    elif kind == "skipped_at_depth_five":
        (world.tree / "d1/d2/d3/d4/.dot").mkdir(parents=True)
        (world.tree / "d1/d2/d3/d4/node_modules").mkdir()
    else:
        hidden = make_repo(world, world.tree / {"dot": ".hidden", "node_modules": "node_modules", "uf_hidden": "flagged"}[kind] / "inner").parent
        if kind == "uf_hidden":
            if not hasattr(os, "chflags"):
                pytest.skip("chflags hidden exists on macOS only")
            os.chflags(str(hidden), stat.UF_HIDDEN)
    result = run_scan(world, world.tree)
    assert roots(result) == [str(visible)]
    assert result["missed"] == dict(NOTHING_MISSED, symlinks=symlinks)
    assert len(asked(result, MISSED_STEM)) == symlinks


def test_a_hidden_typed_directory_is_still_scanned(world):
    """The skip rules are for the folders listed under the directory; `~/.claude` is a valid thing to type."""
    typed = world.base / ".typed"
    inside = make_repo(world, typed / "inside")
    assert roots(run_scan(world, typed)) == [str(inside)]


def test_no_repository_anywhere_is_an_outcome_with_exit_zero(world):
    """Not a crash: no repository below, none in the five ancestors. `run_scan` already demands exit 0."""
    (world.tree / "empty").mkdir()
    result = run_scan(world, world.tree)
    assert result["outcome"] == "no_repository" and result["families"] == []
    assert asked(result, REFUSED_STEM) == [], "a folder without a .git entry is not a refused candidate"


def test_the_run_a_scan_leads_to_has_the_near_repository_and_asks_about_the_depth_five_folder(world):
    """C1's sentence, composed scan -> `analyze.py --card` -> `ledger_merge.merge`. A scan that reaches depth
    6 puts `far-card` in the run; one that does not count the folder at depth 5 leaves the run silent."""
    near = make_repo(world, world.tree / "one" / "near")
    far = make_repo(world, world.tree / "d1/d2/d3/d4/d5/far")
    for repo, name in ((near, "near-card"), (far, "far-card")):
        card = "---\nphase: implementation\nmodel_tier: high\nbranch: none\n---\n\n# %s\n\n## Tasks\n\n- [x] 1 — first\n- [ ] 2 — second\n"
        (repo / "docs" / "features").mkdir(parents=True)
        (repo / "docs" / "features" / (name + ".md")).write_text(card % name, encoding="utf-8")
        git(world, "-C", str(repo), "add", "-A")
        git(world, "-C", str(repo), "commit", "-q", "-m", "card")
    result = run_scan(world, world.tree)
    parts = []
    for family in result["families"]:
        cards = sorted(str(path) for path in (Path(family["root"]) / "docs" / "features").glob("*.md"))
        args = [sys.executable, str(HERE / "analyze.py"), family["root"]]
        for card in cards:
            args += ["--card", card]
        analysis = subprocess.run(args, env=world.env, cwd=str(world.base), capture_output=True, text=True, check=True)
        parts.append({"root": family["root"], "label": family["label"], "questions": family.get("questions", []),
                      "run": json.loads(analysis.stdout)})
    request = {"directory": str(world.tree), "repo": "", "branch": "", "worktree": ""}
    run = ledger_merge.merge(request, parts, result["questions"])
    assert [feature["name"] for feature in run["features"]] == ["near-card"]
    assert {task["repo"] for feature in run["features"] for task in feature["tasks"]} == {"near"}
    first = run["questions"][0]
    assert first["id"] == "q1" and first["q"] == "Were repositories missed under `%s`?" % world.tree
    assert re.search(r"\b1 folders? at depth 5 were not looked inside", first["ctx"]), first["ctx"]


# --------------------------------------------------------------------------------------- C2

@pytest.mark.parametrize("levels,found", [(0, True), (1, True), (5, True), (6, False)])
def test_up_reaches_the_five_nearest_ancestors(world, levels, found):
    """A directory 5 levels under a repo root finds it, 6 does not. A limit of 4 loses the 5; unlimited finds the 6."""
    top = make_repo(world, world.tree / "top")
    start = top.joinpath(*"abcdef"[:levels])
    start.mkdir(parents=True, exist_ok=True)
    result = run_scan(world, start)
    if found:
        assert roots(result) == [str(top)]
    else:
        assert result["outcome"] == "no_repository" and result["families"] == []


def test_a_repo_above_and_one_below_the_typed_directory_are_both_found(world):
    """A scan with no up step loses `top`; one with no down step loses `nested`."""
    top = make_repo(world, world.tree / "top")
    nested = make_repo(world, top / "sub" / "nested")
    assert roots(run_scan(world, top / "sub")) == sorted([str(top), str(nested)])


# --------------------------------------------------------------------------------------- C3

def test_a_repo_and_its_worktrees_inside_the_tree_are_one_family_rooted_at_the_primary(world):
    """Grouping by toplevel gives three families. `a-first` sorts before `main`, so a root taken from the
    first candidate found is the worktree, not the primary checkout."""
    main = make_repo(world, world.tree / "main")
    add_worktree(world, main, world.tree / "a-first", "branch-one")
    add_worktree(world, main, world.tree / "z-last", "branch-two")
    result = run_scan(world, world.tree)
    assert roots(result) == [str(main)] and result["families"][0]["label"] == "main"


def test_every_starting_point_in_a_family_reaches_the_same_family(world):
    """The primary is outside the scanned tree; a scan that only keeps what is under the tree finds nothing."""
    main = make_repo(world, world.base / "elsewhere" / "main")
    first = add_worktree(world, main, world.tree / "wt-one", "branch-one")
    second = add_worktree(world, main, world.base / "other" / "wt-two", "branch-two")
    for start in (world.tree, first, second, main):
        assert roots(run_scan(world, start)) == [str(main)], "starting from %s" % start


def test_repositories_with_one_folder_name_are_separate_families(world):
    """Grouping by folder name fuses `one/proj` and `two/proj`."""
    one = make_repo(world, world.tree / "one" / "proj")
    two = make_repo(world, world.tree / "two" / "proj")
    result = run_scan(world, world.tree)
    assert roots(result) == [str(one), str(two)]
    assert [family["label"] for family in result["families"]] == ["proj", "proj"]


def test_families_are_sorted_by_primary_checkout_path(world):
    """Discovery order (breadth first) is z, mid, zed; sorting by label gives mid, z, zed; the path gives zed, mid, z."""
    z = make_repo(world, world.tree / "z")
    mid = make_repo(world, world.tree / "m" / "mid")
    zed = make_repo(world, world.tree / "a" / "deep" / "zed")
    assert roots(run_scan(world, world.tree)) == [str(zed), str(mid), str(z)]


def test_the_primary_skips_a_bare_entry_a_prunable_one_and_one_whose_folder_is_gone(world):
    """Four worktrees of a bare repository (git lists linked ones by path, and `aaa-wts` sorts before `tree`,
    so the order is A B C D): A is prunable though its folder exists, B is locked (so never prunable) with its
    folder gone, C is healthy, D is the one under the typed tree. The primary is C.
    Taking the first entry gives the bare repo; the first non-bare gives A; filtering only 'prunable' gives B;
    filtering only 'missing' gives A; taking D's own toplevel gives D."""
    bare = world.base / "repo.git"
    git(world, "clone", "-q", "--bare", str(make_repo(world, world.base / "source")), str(bare))
    homes = {name: world.base / "aaa-wts" / name for name in "ABC"}
    homes["D"] = world.tree / "D"
    for name in "ABCD":
        git(world, "-C", str(bare), "worktree", "add", "-q", str(homes[name]), "-b", "branch-" + name)
    (homes["A"] / ".git").unlink()
    git(world, "-C", str(bare), "worktree", "lock", str(homes["B"]))
    shutil.rmtree(homes["B"])
    result = run_scan(world, world.tree)
    assert roots(result) == [str(homes["C"])] and result["families"][0]["label"] == "C"


def test_git_is_asked_what_section_4_1_says(world):
    """Up is `rev-parse --show-toplevel` on the typed directory; each candidate gets the confirm command; the
    family's worktrees come from `worktree list --porcelain`. Grouping by `--git-dir` or listing with
    `git worktree list` without `--porcelain` changes these calls."""
    main = make_repo(world, world.tree / "main")
    first = add_worktree(world, main, world.tree / "a-first", "branch-one")
    result = run_scan(world, world.tree, hang=[])
    calls = git_calls(world)
    assert roots(result) == [str(main)]
    assert str(world.tree) in {call["target"] for call in calls if call["args"] == ["rev-parse", "--show-toplevel"]}
    assert {call["target"] for call in calls if call["args"] == CONFIRM_ARGS} == {str(main), str(first)}
    listed = [call["target"] for call in calls if call["args"] == ["worktree", "list", "--porcelain"]]
    assert listed and all(target.startswith((str(main), str(first))) for target in listed)


def test_git_is_given_the_environment_the_scan_was_given(world):
    """The server's builder protects git through the scan's environment (section 2 default 3), so a git call
    that replaces it with `env={...}` drops the protection. Behaviour half; the next test reads the source."""
    make_repo(world, world.tree / "repo")
    marker = {"TREKO_PROBE": "kept", "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.quotepath", "GIT_CONFIG_VALUE_0": "false"}
    run_scan(world, world.tree, hang=[], env_extra=marker)
    calls = git_calls(world)
    assert calls and all(call["env"].get(key) == value for call in calls for key, value in marker.items())


def test_no_call_in_the_module_passes_env():
    """C8's launch check for `ledger_scan.py`: its git calls inherit, as `analyze.py`'s `_git` does. Source half."""
    tree = ast.parse(SCAN.read_text())
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    launches = [call for call in calls if getattr(call.func, "attr", "") in {"run", "Popen", "check_output", "call", "check_call"}]
    assert launches, "no call starts git, so this check would pass on nothing"
    assert [call.lineno for call in calls if any(keyword.arg == "env" for keyword in call.keywords)] == []


def test_the_limit_these_tests_use_is_the_servers():
    assert re.search(r"^GIT_TIMEOUT_SECS = %d\b" % GIT_TIMEOUT_SECS, (HERE / "server.py").read_text(), re.MULTILINE)


# --------------------------------------------------------------------------------------- C6

def test_all_three_counts_are_one_question_worded_as_section_7_2(world):
    """2 unreadable, 3 at depth 5, 2 symlinks. A scan that asks once per count, or words the context another way, fails."""
    build_missed(world, unreadable=2, depth_limit=3, symlinks=2)
    make_repo(world, world.tree / "found")
    result = run_scan(world, world.tree)
    assert result["missed"] == {"unreadable": 2, "depthLimit": 3, "symlinks": 2}
    assert asked(result, MISSED_STEM) == [{
        "q": "Were repositories missed under `%s`?" % world.tree,
        "ctx": "2 folders could not be listed, 3 folders at depth 5 were not looked inside, and 2 symlinked "
               "folders were not followed, so any repository inside them is missing from this run."}]


@pytest.mark.parametrize("counts", [(2, 0, 0), (0, 3, 0), (0, 0, 2), (2, 0, 2), (0, 3, 2)])
def test_a_count_that_is_zero_is_left_out_of_the_context(world, counts):
    """A context that always lists all three says '0 folders ...'; one that is not asked at all loses the count."""
    build_missed(world, *counts)
    result = run_scan(world, world.tree)
    assert tuple(result["missed"][key] for key in MISSED_KEYS) == counts
    [question] = asked(result, MISSED_STEM)
    for key, count in zip(MISSED_KEYS, counts):
        if count:
            assert CLAUSES[key] % count in question["ctx"]
        else:
            assert CLAUSE_STEMS[key] not in question["ctx"]
    assert question["ctx"].endswith(MISSED_TAIL) and not re.search(r"\b0 ", question["ctx"])


def test_nothing_missed_asks_nothing(world):
    """A scan that always asks puts the question on every clean tree."""
    make_repo(world, world.tree / "repo")
    result = run_scan(world, world.tree)
    assert result["missed"] == NOTHING_MISSED and asked(result, MISSED_STEM) == []


def test_unreadable_folders_are_counted_once_each_and_their_repositories_are_missing(world):
    """A swallowed listing error counts 0; a count taken per attempt counts 4."""
    if os.geteuid() == 0:
        pytest.skip("root can list a mode-000 folder")
    inside = make_repo(world, world.tree / "locked-a" / "repo")
    make_repo(world, world.tree / "found")
    for name in ("locked-a", "locked-b"):
        (world.tree / name).mkdir(exist_ok=True)
        (world.tree / name).chmod(0)
        world.locked.append(world.tree / name)
    result = run_scan(world, world.tree)
    assert roots(result) == [str(world.tree / "found")] and str(inside) not in roots(result)
    assert result["missed"] == dict(NOTHING_MISSED, unreadable=2)


def test_candidates_git_refuses_are_named_and_the_rest_are_still_found(world):
    """A stale pointer is a folder whose `.git` names a repository that is gone. A scan that drops it silently
    has no question; one that gives up on the whole scan has no `good`."""
    good = make_repo(world, world.tree / "good")
    for name in ("stale-a", "stale-b"):
        (world.tree / name).mkdir()
        (world.tree / name / ".git").write_text("gitdir: /nonexistent/%s\n" % name)
    result = run_scan(world, world.tree)
    assert roots(result) == [str(good)]
    refusals = sorted(asked(result, REFUSED_STEM), key=lambda question: question["q"])
    assert [question["q"] for question in refusals] == ["Why could git not read `%s`?" % (world.tree / name) for name in ("stale-a", "stale-b")]
    assert all("not a git repository" in question["ctx"] for question in refusals), refusals
    assert result["missed"] == NOTHING_MISSED


@pytest.mark.parametrize("stage", ["confirm", "worktree_list"])
def test_a_git_call_that_passes_the_time_limit_is_read_as_a_refusal_of_that_path(world, stage):
    """The fake git hangs for one repository's call and runs the real git for the rest. The call is killed at
    GIT_TIMEOUT_SECS, once, the path is left out and named with the limit as its context, and `good` is found.
    No timeout hangs until this file's own bound; a shorter or longer one shows in how long the call lived.
    A scan that treats the timeout as a crash exits non-zero. For 'worktree_list' the family is left out."""
    good = make_repo(world, world.tree / "good")
    slow = make_repo(world, world.tree / "slow")
    rule = {"has": {"confirm": "--git-common-dir", "worktree_list": "worktree"}[stage], "path": str(slow)}
    result = run_scan(world, world.tree, hang=[rule])
    assert roots(result) == [str(good)]
    [refusal] = asked(result, REFUSED_STEM)
    assert refusal["q"] == "Why could git not read `%s`?" % slow
    assert str(GIT_TIMEOUT_SECS) in refusal["ctx"], refusal["ctx"]
    [lifetime] = hung_lifetimes(world)
    assert GIT_TIMEOUT_SECS - 1.0 <= lifetime <= GIT_TIMEOUT_SECS + 1.5, "the call lived %.1f s" % lifetime  # 1 s for the stub to start
