"""A branch name taken from a scanned repository must never be read by git as an option.

Why this file exists: the Ledger lets the page name a directory, so the analyzer will read repositories
the user did not write. A branch called `--output=/some/file` is a valid git ref, and `analyze.py` used
to hand it to `git log` / `git diff` as a bare argument, which git reads as the `--output` option and
obeys: it overwrites that file. Found by both judges on ADR 0056 (2026-11-06) and reproduced by hand.
ADR 0056 section 10 lists it as a route; the fix is `--end-of-options` before every repository-sourced
ref, which every call below must carry.

Each test builds a throwaway repository under `tmp_path`, plants hostile branch names, calls one of the
analyzer's own helpers, and asserts the whole sandbox (everything but `.git`) is byte-for-byte what it
was. A helper that obeys the name leaves a new or changed file and fails.

Run:  uv run --python 3.11.15 --with pytest==9.1.1 --no-project pytest treko/test_analyze_refs.py
"""

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

PRECIOUS = "precious\n"


def _git_env(home):
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
    return env


def _git(root, env, *args):
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, env=env)


def _snapshot(sandbox):
    """Every file under the sandbox except `.git`, with its bytes: the state a hostile ref must not change."""
    seen = {}
    for path in sorted(sandbox.rglob("*")):
        if ".git" in path.relative_to(sandbox).parts or not path.is_file():
            continue
        seen[str(path.relative_to(sandbox))] = path.read_bytes()
    return seen


@pytest.fixture
def sandbox(tmp_path, monkeypatch):
    """A repository with a `main` and hostile branches, and a file outside it that must stay untouched."""
    env = _git_env(tmp_path)
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    root = tmp_path / "repo"
    root.mkdir()
    _git(root, env, "init", "-q", "-b", "main")
    _git(root, env, "commit", "-q", "--allow-empty", "-m", "subject line")
    (tmp_path / "outside.txt").write_text(PRECIOUS)
    absolute = "--output=%s" % (tmp_path / "outside.txt")
    relative = "--output=planted-in-the-repository"
    for name in (absolute, relative):
        _git(root, env, "update-ref", "refs/heads/" + name, "HEAD")
    return {"root": root, "absolute": absolute, "relative": relative, "tmp": tmp_path}


def _assert_nothing_written(sandbox, before):
    assert _snapshot(sandbox["tmp"]) == before, "a repository-sourced ref was obeyed as a git option"


def test_the_last_commit_age_of_a_flag_shaped_branch_writes_nothing(sandbox):
    before = _snapshot(sandbox["tmp"])
    analyzer._collect_branch_facts(sandbox["root"], "main", {})
    _assert_nothing_written(sandbox, before)


@pytest.mark.parametrize("which", ["absolute", "relative"])
def test_a_flag_shaped_branch_as_the_compared_branch_writes_nothing(sandbox, which):
    before = _snapshot(sandbox["tmp"])
    branch = sandbox[which]
    analyzer._ahead_behind(sandbox["root"], "main", branch)
    analyzer._diffstat(sandbox["root"], "main", branch)
    analyzer._commits(sandbox["root"], "main", branch)
    analyzer._commits(sandbox["root"], None, branch)
    _assert_nothing_written(sandbox, before)


@pytest.mark.parametrize("which", ["absolute", "relative"])
def test_a_flag_shaped_branch_as_the_base_writes_nothing(sandbox, which):
    before = _snapshot(sandbox["tmp"])
    base = sandbox[which]
    analyzer._ahead_behind(sandbox["root"], base, "main")
    analyzer._diffstat(sandbox["root"], base, "main")
    analyzer._commits(sandbox["root"], base, "main")
    _assert_nothing_written(sandbox, before)
