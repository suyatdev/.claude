"""Find every git repository in and around a typed directory (docs/features/treko-ledger.spec.md section 4).

Run as a subprocess: the request (`{"directory", "repo", "branch", "worktree"}`) as JSON on stdin, one JSON
object on stdout (section 4.4), exit 0 for every outcome. A request that is not JSON, or has no directory,
exits 2 with a line on stderr. Narrowing by repo, branch or worktree and `families[].cards` are task 12's.

Every git call inherits this process's environment (no `env=`: the server's builder protects git through the
environment it launches the scan with) and is bounded by GIT_TIMEOUT_SECS. A call that fails or passes the
bound is a refusal of that path: the path is left out and named in a "Why could git not read" question.
"""

import json
import os
import stat
import subprocess
import sys

GIT_TIMEOUT_SECS = 5  # section 4; server.py holds the same value for the scan as a whole
MAX_DEPTH = 5  # section 4.1: the typed directory is depth 0, a depth-5 folder is checked but never listed
ANCESTOR_LIMIT = 5  # section 4.1: "up" counts only the directory itself and its 5 nearest ancestors
SKIPPED_NAMES = frozenset({"node_modules"})
HIDDEN_FLAG = getattr(stat, "UF_HIDDEN", 0)  # macOS only; 0 elsewhere, so no flag ever matches
EXIT_BAD_REQUEST = 2

MISSED_CLAUSES = (  # section 7.2, in the order it words them
    ("unreadable", "%d folders could not be listed"),
    ("depthLimit", "%d folders at depth 5 were not looked inside"),
    ("symlinks", "%d symlinked folders were not followed"),
)
MISSED_TAIL = "so any repository inside them is missing from this run."


class GitFailure(Exception):
    """git did not answer for a path. `broken` is true when it could not even be asked (timeout, no git)."""

    def __init__(self, reason, broken):
        super().__init__(reason)
        self.reason = reason
        self.broken = broken


def _git(folder, *args):
    """stdout of `git -C folder args`, or GitFailure."""
    try:
        done = subprocess.run(["git", "-C", folder, *args], capture_output=True, text=True,
                              timeout=GIT_TIMEOUT_SECS)
    except subprocess.TimeoutExpired:
        raise GitFailure("git did not answer within %d seconds" % GIT_TIMEOUT_SECS, True)
    except OSError as error:
        raise GitFailure("git could not be started: %s" % error, True)
    if done.returncode != 0:
        raise GitFailure(done.stderr.strip() or "git exited %d" % done.returncode, False)
    return done.stdout


def _refusal(path, reason):
    return {"q": "Why could git not read `%s`?" % path, "ctx": reason}


# ---------------------------------------------------------------------------------- down

def _has_git_entry(folder):
    return os.path.lexists(os.path.join(folder, ".git"))


def _subfolders(folder, missed):
    """The folders directly under `folder` that the walk may enter, counting what it cannot or will not."""
    try:
        with os.scandir(folder) as listing:
            entries = sorted(listing, key=lambda entry: entry.name)
    except OSError:
        missed["unreadable"] += 1
        return []
    found = []
    for entry in entries:
        if entry.name in SKIPPED_NAMES or entry.name.startswith("."):
            continue
        try:
            flags = getattr(entry.stat(follow_symlinks=False), "st_flags", 0)
        except OSError:
            missed["unreadable"] += 1
            continue
        if flags & HIDDEN_FLAG:
            continue
        if entry.is_symlink():
            if os.path.isdir(entry.path):
                missed["symlinks"] += 1
            continue
        if entry.is_dir(follow_symlinks=False):
            found.append(entry.path)
    return found


def _walk_down(directory, missed):
    """Folders holding a `.git` entry, breadth first. A repository is never entered, the typed one included."""
    if _has_git_entry(directory):
        return [directory]
    candidates = []
    level = [directory]
    for depth in range(1, MAX_DEPTH + 1):
        following = []
        for folder in level:
            for child in _subfolders(folder, missed):
                if _has_git_entry(child):
                    candidates.append(child)
                elif depth == MAX_DEPTH:
                    missed["depthLimit"] += 1
                else:
                    following.append(child)
        level = following
    return candidates


# ------------------------------------------------------------------------------------ up

def _walk_up(directory, refusals):
    """The repository `directory` is inside, if its root is the directory or one of its nearest ancestors."""
    try:
        top = os.path.realpath(_git(directory, "rev-parse", "--show-toplevel").strip())
    except GitFailure as failure:
        if failure.broken:
            refusals.append(_refusal(directory, failure.reason))
        return []  # exit 128 here means "not inside a repository", which is an answer
    nearest = [directory]
    while len(nearest) <= ANCESTOR_LIMIT and os.path.dirname(nearest[-1]) != nearest[-1]:
        nearest.append(os.path.dirname(nearest[-1]))
    return [top] if top in nearest else []


# ------------------------------------------------------------------------------ families

def _confirm(candidate):
    """(common directory, top level) for a candidate, resolved; GitFailure when git refuses it."""
    lines = _git(candidate, "rev-parse", "--path-format=absolute", "--git-common-dir", "--show-toplevel").splitlines()
    if len(lines) != 2:
        raise GitFailure("git printed %d lines where 2 were expected" % len(lines), False)
    return os.path.realpath(lines[0]), os.path.realpath(lines[1])


def _porcelain_entries(text):
    """`worktree list --porcelain` as a list of {"path", "attrs"}, in git's order."""
    entries = []
    for block in text.split("\n\n"):
        lines = [line for line in block.splitlines() if line]
        if not lines or not lines[0].startswith("worktree "):
            continue
        attrs = {line.split(" ", 1)[0] for line in lines[1:]}
        entries.append({"path": lines[0][len("worktree "):], "attrs": attrs})
    return entries


def _primary(entry_text):
    """The first listed worktree that is not bare, prunable or gone from disk; None when there is none."""
    for entry in _porcelain_entries(entry_text):
        if "bare" in entry["attrs"] or "prunable" in entry["attrs"] or not os.path.isdir(entry["path"]):
            continue
        return os.path.realpath(entry["path"])
    return None


def _families(candidates, refusals):
    """One family per common directory, as {"root", "label"} sorted by root."""
    grouped = {}
    for candidate in candidates:
        try:
            common, top = _confirm(candidate)
        except GitFailure as failure:
            refusals.append(_refusal(candidate, failure.reason))
            continue
        grouped.setdefault(common, top)  # the first candidate stands for the family
    families = []
    for top in grouped.values():
        try:
            root = _primary(_git(top, "worktree", "list", "--porcelain"))
        except GitFailure as failure:
            refusals.append(_refusal(top, failure.reason))
            continue
        if root is None:
            refusals.append(_refusal(top, "git lists no worktree of this repository that exists and is not bare"))
            continue
        families.append({"root": root, "label": os.path.basename(root)})
    return sorted(families, key=lambda family: family["root"])


# ------------------------------------------------------------------------------ question

def _missed_question(directory, missed):
    clauses = [template % missed[key] for key, template in MISSED_CLAUSES if missed[key]]
    if not clauses:
        return []
    if len(clauses) == 1:
        joined = clauses[0]
    elif len(clauses) == 2:
        joined = " and ".join(clauses)
    else:
        joined = ", ".join(clauses[:-1]) + ", and " + clauses[-1]
    return [{"q": "Were repositories missed under `%s`?" % directory, "ctx": "%s, %s" % (joined, MISSED_TAIL)}]


def scan(directory):
    """The section 4.4 object for a canonical directory."""
    missed = {"unreadable": 0, "depthLimit": 0, "symlinks": 0}
    refusals = []
    candidates = _walk_down(directory, missed)
    for top in _walk_up(directory, refusals):
        if top not in candidates:
            candidates.append(top)
    families = _families(candidates, refusals)
    refusals.sort(key=lambda question: question["q"])
    return {"outcome": "ok" if families else "no_repository", "families": families,
            "questions": _missed_question(directory, missed) + refusals, "missed": missed}


def main():
    try:
        request = json.load(sys.stdin)
        directory = request["directory"]
        if not isinstance(directory, str) or not directory:
            raise ValueError("directory must be a non-empty string")
    except (ValueError, KeyError, TypeError) as error:
        print("ledger_scan: bad request: %s" % error, file=sys.stderr)
        return EXIT_BAD_REQUEST
    print(json.dumps(scan(os.path.realpath(os.path.expanduser(directory)))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
