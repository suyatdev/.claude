"""Acceptance tests for the analyzer's options (docs/features/treko-ledger.spec.md, §11 E).

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

import os
import re
import subprocess
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent
NEW_ANALYZER = HERE / "analyze.py"

BASELINE_BLOB = "8b805d1f826cae5c22fdcb23de3a57e56049a734"
RUNTIME_PYTHON = "/usr/bin/python3"
RUN_TIMEOUT_SECONDS = 60
BASE_BRANCH = "main"

# The one byte the falsifier changes: the directory the analyzer reads cards from, by default.
DEFAULT_PATH_LITERAL = '"docs" / "features"'
DEFAULT_PATH_MUTANT = '"docs" / "feature"'

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

    def card(self, name, branch, tasks, depends_on=(), phase="implementation", suffix=".md"):
        lines = ["---", "phase: %s" % phase, "model_tier: high", "branch: %s" % branch, "---",
                 "", "# %s" % name, ""]
        if depends_on:
            lines += ["## Depends on", ""] + ["- %s — %s needs it" % (d, name) for d in depends_on]
            lines.append("")
        lines += ["## Tasks", ""] + tasks + [""]
        self.write("docs/features/%s%s" % (name, suffix), "\n".join(lines))

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


BUILDERS = {
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
    """A copy of the working tree's analyzer with one byte of the default card path changed."""
    source = NEW_ANALYZER.read_bytes()
    old, new = DEFAULT_PATH_LITERAL.encode(), DEFAULT_PATH_MUTANT.encode()
    assert source.count(old) == 1, "the default card path is no longer spelled once as %r" % old
    assert len(new) == len(old) - 1, "the mutant must differ by exactly one byte"
    treko = dest / "treko"
    treko.mkdir(parents=True)
    (treko / "analyze.py").write_bytes(source.replace(old, new))
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
