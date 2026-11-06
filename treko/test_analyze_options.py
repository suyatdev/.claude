"""Acceptance tests for the analyzer's options (docs/features/treko-ledger.spec.md, §11 E).

E1 (`--progress`) and E5 (`--card`) come after E2. Each is shown able to fail by §11's two-stub
rule: stub analyzers, built in the test, that ignore the option, refuse, or batch the report at
the end are run through the same checks the real analyzer runs through.

This file starts with E2, "the analyzer is unchanged", as a differential: the analyzer as it
was before the ledger card (blob 8b805d1f826cae5c22fdcb23de3a57e56049a734, taken out of git
with `git cat-file -p`) and the analyzer in this working tree run over the same fixtures,
and their stdout, stderr and exit status must be equal byte for byte, plain and with
`--pretty`. Neither run passes `--progress` or `--card`. Both run under `/usr/bin/python3`
(3.9.6), the interpreter the server launches the analyzer with, not the test runner's.

Every fixture is a repository the card's promise covers (§6.3, §6.4): `git status` succeeds
in each worktree, `git diff --shortstat` succeeds for each branch a card names, and every
listed worktree folder exists. The tests assert that first, so a fixture that drifted out of
scope fails there instead of passing for the wrong reason. The falsifier runs the same
comparison on a copy of the analyzer with one default-path byte changed and must see it fail.

Run:  see §15 of the spec (the pinned `uv run ... pytest` command).
"""

import json
import os
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
NEW_ANALYZER = HERE / "analyze.py"
NEW_CARDS = HERE / "cards.py"  # where the default card path lives since split 1

BASELINE_BLOB = "8b805d1f826cae5c22fdcb23de3a57e56049a734"
RUNTIME_PYTHON = "/usr/bin/python3"
RUN_TIMEOUT_SECONDS = 60
BASE_BRANCH = "main"

# The one byte the falsifier changes: the directory the analyzer reads cards from, by default.
DEFAULT_PATH_LITERAL = '"docs" / "features"'
DEFAULT_PATH_MUTANT = '"docs" / "feature"'

PROGRESS_STAGES = ("worktrees", "branches", "cards", "order")
PROGRESS_STDERR = "".join("treko-progress %s\n" % stage for stage in PROGRESS_STAGES).encode()
FOREACHREF_DELAY_SECONDS = 2
MIN_LEAD_SECONDS = 1.5  # E1: the `worktrees` line is read at least this long before exit

FIXTURE_NAMES = ("worktrees_chain_cycle", "not_a_repository", "idless_task")
FIXTURE_ARGS = {"plain": [], "pretty": ["--pretty"]}


# --------------------------------------------------------------------------- environment


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
            "PYTHONDONTWRITEBYTECODE": "1",
        }
    )
    for leaked in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
        env.pop(leaked, None)
    return env


def _run(argv, env, cwd, check=True):
    result = subprocess.run(
        argv, cwd=str(cwd), env=env, capture_output=True, timeout=RUN_TIMEOUT_SECONDS
    )
    if check and result.returncode != 0:
        raise AssertionError(
            "%s exited %d: %s" % (argv, result.returncode, result.stderr.decode(errors="replace"))
        )
    return result


# --------------------------------------------------------------------------- fixtures


class Fixture:
    """A repository built under `base`, committed with fixed dates so git's relative times match."""

    def __init__(self, base):
        self.base = base
        self.env = _git_env(base / "home")
        self.root = base / "repo"
        self._clock = 0

    def git(self, *args, cwd=None, check=True):
        env = dict(self.env)
        self._clock += 1
        stamp = "2020-01-%02dT12:00:00+0000" % self._clock
        env["GIT_AUTHOR_DATE"] = stamp
        env["GIT_COMMITTER_DATE"] = stamp
        result = _run(["git", "-C", str(cwd or self.root), *args], env, self.base, check=check)
        return result.stdout.decode()

    def init(self):
        self.root.mkdir()
        self.git("-c", "init.defaultBranch=%s" % BASE_BRANCH, "init", "-q")
        (self.root / "docs" / "features").mkdir(parents=True)
        self.write("README.md", "fixture\n")

    def write(self, relpath, text, cwd=None):
        target = (cwd or self.root) / relpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def card(self, name, branch, tasks, depends_on=(), phase="implementation", suffix=".md",
             cwd=None):
        lines = ["---", "phase: %s" % phase, "model_tier: high", "branch: %s" % branch, "---",
                 "", "# %s" % name, ""]
        if depends_on:
            lines += ["## Depends on", ""] + ["- %s — %s needs it" % (d, name) for d in depends_on]
            lines.append("")
        lines += ["## Tasks", ""] + tasks + [""]
        self.write("docs/features/%s%s" % (name, suffix), "\n".join(lines), cwd=cwd)

    def commit_all(self, message, cwd=None):
        self.git("add", "-A", cwd=cwd)
        self.git("commit", "-q", "-m", message, cwd=cwd)

    def worktree(self, branch):
        path = self.base / "wt" / branch.replace("/", "-")
        self.git("worktree", "add", "-q", "-b", branch, str(path))
        return path


def _fixture_worktrees_chain_cycle(base):
    """Worktrees, a depends-on chain, a cycle and a spec half; the exit-0 path."""
    fx = Fixture(base)
    fx.init()
    fx.card("alpha", "feat/alpha", ["- [x] 1 — first", "- [ ] 2 — second"])
    fx.card("beta", "feat/beta", ["- [ ] 1 — only"], depends_on=["alpha"])
    fx.card("cleanup", "feat/cleanup", ["- [ ] 1 — last link"], depends_on=["beta"])
    fx.card("gamma", "feat/gamma", ["- [ ] 1 — loops"], depends_on=["delta"])
    fx.card("delta", "none", ["- [ ] 1 — loops back"], depends_on=["gamma"])
    # A spec half whose task identities differ from its card's: the analyzer asks which is right.
    fx.card("alpha", "feat/alpha", ["- [x] 1 — first", "- [ ] 3 — third"], suffix=".spec.md")
    fx.commit_all("cards")
    alpha, beta, cleanup = (fx.worktree("feat/" + n) for n in ("alpha", "beta", "cleanup"))
    fx.git("branch", "feat/gamma")
    fx.write("src.txt", "alpha work\n", cwd=alpha)
    fx.commit_all("alpha work", cwd=alpha)
    fx.write("scratch.txt", "uncommitted\n", cwd=beta)  # beta's worktree is dirty
    fx.write("main.txt", "main moves on\n")
    fx.commit_all("main moves on")  # every feat/* branch is now one behind
    assert cleanup.is_dir()
    return fx.root


def _fixture_not_a_repository(base):
    """A directory that is not a repository: the exit-1 path."""
    plain = base / "plain"
    plain.mkdir()
    (plain / "note.txt").write_text("not a repo\n")
    return plain


def _fixture_idless_task(base):
    """A card with a task that has no identity before the em dash: an unparseable checklist."""
    fx = Fixture(base)
    fx.init()
    fx.card("anonymous", "feat/anonymous", ["- [ ] — nothing before the dash", "- [ ] 2 — fine"])
    fx.commit_all("cards")
    fx.worktree("feat/anonymous")
    return fx.root


def _fixture_other_worktree_copy(base):
    """`alpha` twice: the primary has its halves disagree one way, the worktree the other way."""
    fx = Fixture(base)
    fx.init()
    fx.card("alpha", "feat/alpha", ["- [ ] 1 — one", "- [ ] 2 — two"])
    fx.card("alpha", "feat/alpha", ["- [ ] 1 — one", "- [ ] 2 — two", "- [ ] 9 — nine"],
            suffix=".spec.md")
    fx.commit_all("cards")
    wt = fx.worktree("feat/alpha")
    fx.card("alpha", "feat/alpha", ["- [ ] 1 — one", "- [ ] 2 — two", "- [ ] 3 — three"], cwd=wt)
    fx.card("alpha", "feat/alpha", ["- [ ] 1 — one", "- [ ] 2 — two"], suffix=".spec.md", cwd=wt)
    return fx.root


BUILDERS = {
    "other_worktree_copy": _fixture_other_worktree_copy,
    "worktrees_chain_cycle": _fixture_worktrees_chain_cycle,
    "not_a_repository": _fixture_not_a_repository,
    "idless_task": _fixture_idless_task,
}


@pytest.fixture
def fixture_for(tmp_path):
    def build(name):
        base = tmp_path / name
        (base / "home").mkdir(parents=True)  # a private $HOME, so `~` collapsing is reproducible
        return BUILDERS[name](base), _git_env(base / "home")

    return build


# ------------------------------------------------------------------------ the two analyzers


def _materialize_baseline(dest):
    """The pre-change analyzer beside a `hooks/lib` link, the layout `analyze.py` imports from."""
    treko = dest / "treko"
    treko.mkdir(parents=True)
    blob = _run(["git", "-C", str(REPO_ROOT), "cat-file", "-p", BASELINE_BLOB], os.environ, dest)
    (treko / "analyze.py").write_bytes(blob.stdout)
    _link_hooks(dest)
    return treko / "analyze.py"


def _link_hooks(dest):
    (dest / "hooks").mkdir(exist_ok=True)
    (dest / "hooks" / "lib").symlink_to(REPO_ROOT / "hooks" / "lib", target_is_directory=True)


def _materialize_mutant(dest):
    """The working tree's analyzer beside a `cards.py` whose default card path has one byte changed."""
    source = NEW_CARDS.read_bytes()
    old, new = DEFAULT_PATH_LITERAL.encode(), DEFAULT_PATH_MUTANT.encode()
    assert source.count(old) == 1, "the default card path is no longer spelled once as %r" % old
    assert len(new) == len(old) - 1, "the mutant must differ by exactly one byte"
    treko = dest / "treko"
    treko.mkdir(parents=True)
    (treko / "analyze.py").write_bytes(NEW_ANALYZER.read_bytes())
    (treko / "cards.py").write_bytes(source.replace(old, new))
    _link_hooks(dest)
    return treko / "analyze.py"


def _run_analyzer(script, repo_root, extra_args, base):
    """(stdout, stderr, exit status), as raw bytes, under the pinned runtime interpreter."""
    result = _run(
        [RUNTIME_PYTHON, str(script), str(repo_root), *extra_args],
        _git_env(base / "home"),
        base,
        check=False,
    )
    return result.stdout, result.stderr, result.returncode


def _mismatch(expected, actual):
    """None when equal; otherwise which of stdout, stderr and exit status differ."""
    names = ("stdout", "stderr", "exit status")
    differing = [n for n, a, b in zip(names, expected, actual) if a != b]
    return None if not differing else "differs in: %s" % ", ".join(differing)


# ------------------------------------------------------------------------ healthy fixtures


def _card_branches(repo_root):
    """Branches that cards name and that have at least one task line."""
    found = set()
    for card in (repo_root / "docs" / "features").glob("*.md"):
        if card.name.endswith(".spec.md"):
            continue
        text = card.read_text()
        branch = re.search(r"^branch:\s*(\S+)\s*$", text, re.M)
        if branch and branch.group(1) != "none" and re.search(r"^- \[[ xX]\]", text, re.M):
            found.add(branch.group(1))
    return found


def _assert_in_scope(repo_root, env):
    """§6.3 and §6.4: nothing in this fixture takes one of the analyzer's changed branches."""
    listing = _run(["git", "-C", str(repo_root), "worktree", "list", "--porcelain"], env, repo_root)
    folders = [l[len("worktree "):] for l in listing.stdout.decode().splitlines()
               if l.startswith("worktree ")]
    assert len(folders) > 1, "the fixture must have a worktree beside the main one"
    for folder in folders:
        assert Path(folder).is_dir(), "worktree folder missing: %s" % folder
        status = _run(["git", "-C", folder, "status", "--porcelain"], env, repo_root, check=False)
        assert status.returncode == 0, "git status fails in %s" % folder
    branches = _card_branches(repo_root)
    assert branches, "the fixture must have a card that names a branch"
    for branch in sorted(branches):
        diff = _run(["git", "-C", str(repo_root), "diff", "--shortstat",
                     "%s...%s" % (BASE_BRANCH, branch)], env, repo_root, check=False)
        assert diff.returncode == 0, "git diff --shortstat fails for %s" % branch


# --------------------------------------------------------------------------------- tests


def test_baseline_blob_is_the_one_the_spec_names(tmp_path):
    script = _materialize_baseline(tmp_path)
    blob = _run(["git", "hash-object", str(script)], os.environ, tmp_path).stdout.decode().strip()
    assert blob == BASELINE_BLOB


def test_the_runtime_interpreter_is_the_pinned_one(tmp_path):
    version = _run([RUNTIME_PYTHON, "-c", "import sys; print('%d.%d.%d' % sys.version_info[:3])"],
                   os.environ, tmp_path).stdout.decode().strip()
    assert version == "3.9.6"


@pytest.mark.parametrize("fixture_name", ["worktrees_chain_cycle", "idless_task"])
def test_repository_fixtures_are_inside_the_unchanged_scope(tmp_path, fixture_for, fixture_name):
    repo_root, env = fixture_for(fixture_name)
    _assert_in_scope(repo_root, env)


@pytest.mark.parametrize("fixture_name", FIXTURE_NAMES)
@pytest.mark.parametrize("mode", sorted(FIXTURE_ARGS))
def test_e2_new_analyzer_matches_the_baseline_byte_for_byte(tmp_path, fixture_for, fixture_name,
                                                            mode):
    repo_root, _ = fixture_for(fixture_name)
    base = tmp_path / fixture_name
    baseline = _materialize_baseline(tmp_path / "baseline")
    expected = _run_analyzer(baseline, repo_root, FIXTURE_ARGS[mode], base)
    actual = _run_analyzer(NEW_ANALYZER, repo_root, FIXTURE_ARGS[mode], base)

    assert _mismatch(expected, actual) is None
    assert actual == expected
    # The comparison is not vacuous: each fixture takes the path it is named for.
    stdout, stderr, status = expected
    if fixture_name == "not_a_repository":
        assert (status, stdout) == (1, b"") and b"not a git repository" in stderr
    else:
        assert status == 0 and stderr == b"" and stdout.startswith(b"{")
    if mode == "pretty" and status == 0:
        assert b'\n  "' in stdout


def test_e2_the_chain_cycle_and_spec_half_are_all_in_the_output(tmp_path, fixture_for):
    repo_root, _ = fixture_for("worktrees_chain_cycle")
    baseline = _materialize_baseline(tmp_path / "baseline")
    stdout, _, _ = _run_analyzer(baseline, repo_root, [], tmp_path / "worktrees_chain_cycle")
    text = stdout.decode()
    assert "dependency cycle delta, gamma" in text
    assert "Which half of `alpha` is right?" in text
    assert "alpha merges before beta" in text and "beta merges before cleanup" in text
    assert "1 uncommitted" in text and "needs rebase" in text


@pytest.mark.parametrize("fixture_name", ["worktrees_chain_cycle", "idless_task"])
def test_e2_falsifier_one_default_path_byte_fails_the_comparison(tmp_path, fixture_for,
                                                                 fixture_name):
    repo_root, _ = fixture_for(fixture_name)
    base = tmp_path / fixture_name
    baseline = _materialize_baseline(tmp_path / "baseline")
    mutant = _materialize_mutant(tmp_path / "mutant")
    expected = _run_analyzer(baseline, repo_root, [], base)
    actual = _run_analyzer(mutant, repo_root, [], base)

    verdict = _mismatch(expected, actual)
    assert verdict is not None, "the comparison cannot see a changed default path"
    assert actual != expected


# ------------------------------------------------------------------- stubs: the two-stub rule

STUB_SOURCE = '''
import subprocess, sys
REAL, KIND, STAGES = %(real)r, %(kind)r, %(stages)r
if KIND == "refuse":
    sys.exit(2)
argv, kept, progress, i = sys.argv[1:], [], False, 0
while i < len(argv):
    if argv[i] == "--progress":
        progress = True
    elif argv[i] == "--card":
        i += 1
    else:
        kept.append(argv[i])
    i += 1
done = subprocess.run([sys.executable, REAL, *kept], capture_output=True)
sys.stdout.buffer.write(done.stdout)
sys.stderr.buffer.write(done.stderr)
if progress and KIND == "batched":
    for stage in STAGES:
        sys.stderr.write("treko-progress %%s\\n" %% stage)
        sys.stderr.flush()
sys.exit(done.returncode)
'''


def _stub(dest, kind):
    """A stand-in analyzer. refuse: exits 2. ignore: drops --progress and --card, delegates.
    batched: as ignore, then prints the four lines only after the real run has ended."""
    dest.mkdir(parents=True, exist_ok=True)
    script = dest / ("stub_%s.py" % kind)
    script.write_text(STUB_SOURCE % {"real": str(NEW_ANALYZER), "kind": kind,
                                     "stages": PROGRESS_STAGES})
    return script


def _slow_git_dir(dest):
    """A folder holding a `git` that sleeps before `for-each-ref`, then runs the real git."""
    dest.mkdir(parents=True, exist_ok=True)
    wrapper = dest / "git"
    wrapper.write_text(
        '#!/bin/sh\nfor a in "$@"; do\n  if [ "$a" = for-each-ref ]; then sleep %d; break; fi\n'
        'done\nexec %s "$@"\n' % (FOREACHREF_DELAY_SECONDS, shutil.which("git")))
    wrapper.chmod(0o755)
    return dest


# ---------------------------------------------------------------------------------- E1 checks


def _check_progress_report(script, repo_root, base, extra):
    """E1, first half: exactly the four lines, in order, and stdout as without the flag."""
    plain = _run_analyzer(script, repo_root, extra, base)
    flagged = _run_analyzer(script, repo_root, ["--progress", *extra], base)
    assert flagged[2] == 0, "--progress run failed: %s" % flagged[1].decode(errors="replace")
    assert flagged[1] == PROGRESS_STDERR, "stderr was %r" % flagged[1]
    assert flagged[0] == plain[0], "stdout changed under --progress"


def _run_timed(script, repo_root, extra_args, base, path_first):
    """Run the analyzer, noting when each stderr line is read and when the process ended."""
    env = _git_env(base / "home")
    env["PATH"] = str(path_first) + os.pathsep + env["PATH"]
    started = time.monotonic()
    proc = subprocess.Popen([RUNTIME_PYTHON, str(script), str(repo_root), *extra_args],
                            cwd=str(base), env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    killer = threading.Timer(RUN_TIMEOUT_SECONDS, proc.kill)
    killer.start()
    drained = []
    drain = threading.Thread(target=lambda: drained.append(proc.stdout.read()))
    drain.start()
    arrivals = [(raw.decode(), time.monotonic()) for raw in iter(proc.stderr.readline, b"")]
    status = proc.wait()
    ended = time.monotonic()
    killer.cancel()
    drain.join()
    return {"arrivals": arrivals, "status": status, "elapsed": ended - started,
            "lead": ended - arrivals[0][1] if arrivals else None}


def _check_lines_arrive_as_stages_end(script, repo_root, base, slow_git):
    """E1, second half: with `for-each-ref` slowed by 2 s, `worktrees` is read early."""
    run = _run_timed(script, repo_root, ["--progress"], base, slow_git)
    assert run["status"] == 0, run
    assert "".join(text for text, _ in run["arrivals"]).encode() == PROGRESS_STDERR
    assert run["elapsed"] >= FOREACHREF_DELAY_SECONDS, "the git wrapper never delayed anything"
    assert run["lead"] >= MIN_LEAD_SECONDS, "worktrees line came %.2f s before exit" % run["lead"]


# ----------------------------------------------------------------------------------- E1 tests


@pytest.mark.parametrize("mode", sorted(FIXTURE_ARGS))
def test_e1_progress_prints_the_four_lines_in_order_and_leaves_stdout_alone(
        tmp_path, fixture_for, mode):
    repo_root, _ = fixture_for("worktrees_chain_cycle")
    _check_progress_report(NEW_ANALYZER, repo_root, tmp_path / "worktrees_chain_cycle",
                           FIXTURE_ARGS[mode])


def test_e1_each_line_arrives_as_its_stage_ends(tmp_path, fixture_for):
    repo_root, _ = fixture_for("worktrees_chain_cycle")
    _check_lines_arrive_as_stages_end(NEW_ANALYZER, repo_root, tmp_path / "worktrees_chain_cycle",
                                      _slow_git_dir(tmp_path / "slow"))


@pytest.mark.parametrize("kind", ["refuse", "ignore"])
def test_e1_falsifier_a_stub_that_prints_no_lines_fails_the_line_check(tmp_path, fixture_for, kind):
    repo_root, _ = fixture_for("worktrees_chain_cycle")
    with pytest.raises(AssertionError):
        _check_progress_report(_stub(tmp_path / "stub", kind), repo_root,
                               tmp_path / "worktrees_chain_cycle", [])


def test_e1_falsifier_a_stub_that_batches_the_lines_fails_only_the_timing_check(
        tmp_path, fixture_for):
    repo_root, _ = fixture_for("worktrees_chain_cycle")
    base = tmp_path / "worktrees_chain_cycle"
    batched = _stub(tmp_path / "stub", "batched")
    _check_progress_report(batched, repo_root, base, [])  # the line check can be satisfied
    with pytest.raises(AssertionError, match="before exit"):
        _check_lines_arrive_as_stages_end(batched, repo_root, base,
                                          _slow_git_dir(tmp_path / "slow"))


# ---------------------------------------------------------------------------------- E5 checks


def _default_card_paths(repo_root):
    features = repo_root / "docs" / "features"
    return sorted(p for p in features.glob("*.md") if not p.name.endswith(".spec.md"))


def _card_args(paths):
    return [arg for path in paths for arg in ("--card", str(path))]


def _feature_names(stdout):
    return [feature["name"] for feature in json.loads(stdout)["features"]]


def _check_every_default_path_is_the_same_as_none(script, repo_root, base):
    paths = _default_card_paths(repo_root)
    assert len(paths) > 2, "the fixture needs several cards for order to matter"
    expected = _run_analyzer(script, repo_root, [], base)
    assert expected[2] == 0
    for given in (paths, list(reversed(paths))):
        actual = _run_analyzer(script, repo_root, _card_args(given), base)
        assert actual[2] == 0, "--card run failed: %s" % actual[1].decode(errors="replace")
        assert actual == expected, "differs from a run without --card"


def _check_a_subset_is_exactly_that_subset(script, repo_root, base):
    kept = [repo_root / "docs" / "features" / ("%s.md" % n) for n in ("beta", "alpha")]
    assert len(kept) < len(_default_card_paths(repo_root))
    stdout, stderr, status = _run_analyzer(script, repo_root, _card_args(kept), base)
    assert status == 0, stderr.decode(errors="replace")
    assert _feature_names(stdout) == ["alpha", "beta"]  # by file name, not the order given


def _check_another_worktrees_copy_meets_its_own_spec_half(script, repo_root, base):
    primary = repo_root / "docs" / "features" / "alpha.md"
    other = base / "wt" / "feat-alpha" / "docs" / "features" / "alpha.md"
    assert primary.is_file() and other.is_file() and primary != other
    heading = "alpha.md and alpha.spec.md list different tasks:\n  in "
    expected = {
        other: heading + "alpha.md but missing from alpha.spec.md: 3",
        primary: heading + "alpha.spec.md but missing from alpha.md: 9",
    }
    for copy, context in expected.items():
        stdout, stderr, status = _run_analyzer(script, repo_root, _card_args([copy]), base)
        assert status == 0, stderr.decode(errors="replace")
        assert _feature_names(stdout) == ["alpha"]
        halves = [q["ctx"] for q in json.loads(stdout)["questions"]
                  if q["q"] == "Which half of `alpha` is right?"]
        assert halves == [context], "for %s: %r" % (copy, halves)


# ----------------------------------------------------------------------------------- E5 tests


def test_e5_every_default_path_given_is_the_same_as_none(tmp_path, fixture_for):
    repo_root, _ = fixture_for("worktrees_chain_cycle")
    _check_every_default_path_is_the_same_as_none(NEW_ANALYZER, repo_root,
                                                  tmp_path / "worktrees_chain_cycle")


def test_e5_a_subset_gives_exactly_that_subset_by_file_name(tmp_path, fixture_for):
    repo_root, _ = fixture_for("worktrees_chain_cycle")
    _check_a_subset_is_exactly_that_subset(NEW_ANALYZER, repo_root,
                                           tmp_path / "worktrees_chain_cycle")


def test_e5_another_worktrees_copy_is_compared_with_its_own_spec_half(tmp_path, fixture_for):
    repo_root, _ = fixture_for("other_worktree_copy")
    _check_another_worktrees_copy_meets_its_own_spec_half(NEW_ANALYZER, repo_root,
                                                          tmp_path / "other_worktree_copy")


def test_e5_falsifier_stubs_that_refuse_or_ignore_the_option_fail_the_checks(
        tmp_path, fixture_for):
    chain, _ = fixture_for("worktrees_chain_cycle")
    copies, _ = fixture_for("other_worktree_copy")
    chain_base, copies_base = tmp_path / "worktrees_chain_cycle", tmp_path / "other_worktree_copy"
    ignore, refuse = _stub(tmp_path / "stub", "ignore"), _stub(tmp_path / "stub", "refuse")
    # An analyzer that drops --card satisfies "all default paths" (it reads them anyway) ...
    _check_every_default_path_is_the_same_as_none(ignore, chain, chain_base)
    # ... but not the two checks that need the option to select something.
    with pytest.raises(AssertionError):
        _check_a_subset_is_exactly_that_subset(ignore, chain, chain_base)
    with pytest.raises(AssertionError):
        _check_another_worktrees_copy_meets_its_own_spec_half(ignore, copies, copies_base)
    # One that refuses fails all three.
    with pytest.raises(AssertionError):
        _check_every_default_path_is_the_same_as_none(refuse, chain, chain_base)
    with pytest.raises(AssertionError):
        _check_a_subset_is_exactly_that_subset(refuse, chain, chain_base)
    with pytest.raises(AssertionError):
        _check_another_worktrees_copy_meets_its_own_spec_half(refuse, copies, copies_base)


# ----------------------------------------------------------------------- E6 and E8 fixtures

TARGET_BRANCH = "feat/alpha"  # the branch whose worktree is damaged; it stays level with main
INDEX_JUNK = b"not an index"
GIT_INDEX_MESSAGE = "index file smaller than expected"


def _two_branch_repo(tmp_path, name):
    """main plus `feat/alpha` in a second worktree, level with main, named by one card."""
    base = tmp_path / name
    (base / "home").mkdir(parents=True)
    fx = Fixture(base)
    fx.init()
    fx.card("alpha", TARGET_BRANCH, ["- [ ] 1 — only"])
    fx.commit_all("cards")
    return fx, fx.worktree(TARGET_BRANCH), base


def _listed_worktree(fx, wt):
    """(path as git lists it, that entry's lines) from `git worktree list --porcelain`."""
    for block in fx.git("worktree", "list", "--porcelain").split("\n\n"):
        lines = block.splitlines()
        if lines and lines[0].startswith("worktree ") and Path(lines[0][9:]).name == wt.name:
            return lines[0][9:], lines
    raise AssertionError("git does not list a worktree named %s" % wt.name)


def _break_index(fx, wt):
    """Overwrite the worktree's index with junk; return (index file, the original bytes)."""
    index = Path(fx.git("rev-parse", "--absolute-git-dir", cwd=wt).strip()) / "index"
    original = index.read_bytes()
    index.write_bytes(INDEX_JUNK)
    return index, original


def _assert_status_fails(fx, wt):
    status = _run(["git", "-C", str(wt), "status", "--porcelain"], fx.env, fx.base, check=False)
    assert status.returncode != 0, "git status still works in %s" % wt
    assert GIT_INDEX_MESSAGE in status.stderr.decode(), status.stderr


def _run_both(tmp_path, repo_root, base):
    dest = tmp_path / "baseline"
    baseline = dest / "treko" / "analyze.py" if dest.exists() else _materialize_baseline(dest)
    return (_run_analyzer(NEW_ANALYZER, repo_root, [], base),
            _run_analyzer(baseline, repo_root, [], base))


def _target(run):
    return next(b for b in run["branches"] if b["branch"] == TARGET_BRANCH)


def _everything_else(run, questions):
    """The run as bytes, minus the damaged branch's entry and with the given questions."""
    rest = dict(run, questions=questions)
    rest["branches"] = [b for b in run["branches"] if b["branch"] != TARGET_BRANCH]
    return json.dumps(rest)


def _check_branch_keeps_its_facts(new, old):
    for key in ("ahead", "behind", "last"):
        assert _target(new)[key] == _target(old)[key], key


def _check_changes_unknown(new_out, old_out, wt):
    """E6: the damaged worktree reads "changes unknown" and costs exactly one question."""
    assert new_out[2] == 0 and old_out[2] == 0, (new_out[1], old_out[1])
    new, old = json.loads(new_out[0]), json.loads(old_out[0])
    got = _target(new)
    assert got["dirty"] is False
    assert got["note"] == "changes unknown"
    assert got["tone"] == "neutral"
    _check_branch_keeps_its_facts(new, old)
    assert len(old["questions"]) > 0, "the baseline should have questions to come after"
    assert len(new["questions"]) == len(old["questions"]) + 1
    extra = new["questions"][-1]
    assert wt.name in extra["q"], extra
    assert GIT_INDEX_MESSAGE in extra["ctx"], extra
    assert _everything_else(new, new["questions"][:-1]) == _everything_else(old, old["questions"])


def _check_folder_missing(new_out, old_out, listed_path):
    """E8: the gone folder reads "folder missing", keeps its path, and asks nothing."""
    assert new_out[2] == 0 and old_out[2] == 0, (new_out[1], old_out[1])
    new, old = json.loads(new_out[0]), json.loads(old_out[0])
    got = _target(new)
    assert got["dirty"] is False
    assert got["note"] == "folder missing"
    assert got["tone"] == "neutral"
    assert got["wt"] == listed_path  # not under the fixture's $HOME, so collapsing changes nothing
    _check_branch_keeps_its_facts(new, old)
    assert new["questions"] == old["questions"]
    assert _everything_else(new, new["questions"]) == _everything_else(old, old["questions"])


# ------------------------------------------------------------------------------ E6 and E8 tests


def test_e6_a_failing_git_status_shows_changes_unknown(tmp_path):
    fx, wt, base = _two_branch_repo(tmp_path, "e6")
    _break_index(fx, wt)
    _assert_status_fails(fx, wt)
    new_out, old_out = _run_both(tmp_path, fx.root, base)
    _check_changes_unknown(new_out, old_out, wt)


def test_e6_falsifier_the_baseline_reports_that_branch_as_clean(tmp_path):
    fx, wt, base = _two_branch_repo(tmp_path, "e6")
    _break_index(fx, wt)
    _assert_status_fails(fx, wt)
    _, old_out = _run_both(tmp_path, fx.root, base)
    assert _target(json.loads(old_out[0]))["note"] == "clean"  # what the check must catch
    with pytest.raises(AssertionError, match="'clean' == 'changes unknown'"):
        _check_changes_unknown(old_out, old_out, wt)


def test_e6_before_the_damage_and_after_the_repair_the_analyzers_agree(tmp_path):
    fx, wt, base = _two_branch_repo(tmp_path, "e6")
    _assert_in_scope(fx.root, fx.env)
    new_out, old_out = _run_both(tmp_path, fx.root, base)
    assert new_out == old_out and new_out[2] == 0
    index, original = _break_index(fx, wt)
    _assert_status_fails(fx, wt)
    index.write_bytes(original)
    _assert_in_scope(fx.root, fx.env)
    new_out, old_out = _run_both(tmp_path, fx.root, base)
    assert new_out == old_out and new_out[2] == 0


def _remove_folder_leaving_it_listed(fx, wt):
    """rm -rf, not `git worktree remove`, then assert git still lists it as prunable."""
    shutil.rmtree(wt)
    listed, lines = _listed_worktree(fx, wt)
    assert any(line.startswith("prunable") for line in lines), lines
    assert not Path(listed).exists()
    return listed


def test_e8_a_worktree_whose_folder_is_gone_shows_folder_missing(tmp_path):
    fx, wt, base = _two_branch_repo(tmp_path, "e8")
    listed = _remove_folder_leaving_it_listed(fx, wt)
    new_out, old_out = _run_both(tmp_path, fx.root, base)
    _check_folder_missing(new_out, old_out, listed)


def test_e8_falsifier_the_baseline_reports_that_branch_as_clean(tmp_path):
    fx, wt, base = _two_branch_repo(tmp_path, "e8")
    listed = _remove_folder_leaving_it_listed(fx, wt)
    _, old_out = _run_both(tmp_path, fx.root, base)
    assert _target(json.loads(old_out[0]))["tone"] == "ok"  # what the check must catch
    with pytest.raises(AssertionError, match="'clean' == 'folder missing'"):
        _check_folder_missing(old_out, old_out, listed)


def test_e8_before_the_folder_is_deleted_the_analyzers_agree(tmp_path):
    fx, wt, base = _two_branch_repo(tmp_path, "e8")
    _assert_in_scope(fx.root, fx.env)
    new_out, old_out = _run_both(tmp_path, fx.root, base)
    assert new_out == old_out and new_out[2] == 0
