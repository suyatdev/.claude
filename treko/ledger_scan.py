"""Find every git repository in and around a typed directory (docs/features/treko-ledger.spec.md section 4).

Run as a subprocess: the request (`{"directory", "repo", "branch", "worktree"}`) as JSON on stdin, one JSON
object on stdout (section 4.4), exit 0 for every outcome. A request that is not JSON, has no directory, or
gives a repo, branch or worktree that is not text exits 2 with a line on stderr. Narrowing by those three
(section 4.2) and the choice of each card's live copy (section 4.3) happen here, after the families are found.

Every git call inherits this process's environment (no `env=`: the server's builder protects git through the
environment it launches the scan with) and is bounded by GIT_TIMEOUT_SECS. A call that fails or passes the
bound is a refusal of that path: the path is left out and named in a "Why could git not read" question.
"""

import json
import os
import stat
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # not on sys.path under `python3 -I`

import cards  # noqa: E402  — what a card is lives in cards.py

GIT_TIMEOUT_SECS = 5  # section 4; server.py holds the same value for the scan as a whole
MAX_DEPTH = 5  # section 4.1: the typed directory is depth 0, a depth-5 folder is checked but never listed
ANCESTOR_LIMIT = 5  # section 4.1: "up" counts only the directory itself and its 5 nearest ancestors
SKIPPED_NAMES = frozenset({"node_modules"})
HIDDEN_FLAG = getattr(stat, "UF_HIDDEN", 0)  # macOS only; 0 elsewhere, so no flag ever matches
EXIT_BAD_REQUEST = 2
HEADS_PREFIX = "refs/heads/"
FEATURES_DIR = os.path.join("docs", "features")
NARROWING_KEYS = ("repo", "branch", "worktree")

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
        attrs = {line.partition(" ")[0]: line.partition(" ")[2] for line in lines[1:]}
        entries.append({"path": lines[0][len("worktree "):], "attrs": attrs})
    return entries


def _trees(entry_text):
    """The worktrees that exist and are not bare or prunable, in git's order, as {"path", "name", "branch"}.
    The first is the primary checkout. `branch` is "" for a detached HEAD."""
    trees = []
    for entry in _porcelain_entries(entry_text):
        if "bare" in entry["attrs"] or "prunable" in entry["attrs"] or not os.path.isdir(entry["path"]):
            continue
        ref = entry["attrs"].get("branch", "")
        trees.append({"path": os.path.realpath(entry["path"]), "name": os.path.basename(entry["path"]),
                      "branch": ref[len(HEADS_PREFIX):] if ref.startswith(HEADS_PREFIX) else ""})
    return trees


def _families(candidates, refusals):
    """One family per common directory, as {"root", "label", "trees"} sorted by root."""
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
            trees = _trees(_git(top, "worktree", "list", "--porcelain"))
        except GitFailure as failure:
            refusals.append(_refusal(top, failure.reason))
            continue
        if not trees:
            refusals.append(_refusal(top, "git lists no worktree of this repository that exists and is not bare"))
            continue
        root = trees[0]["path"]
        families.append({"root": root, "label": os.path.basename(root), "trees": trees})
    return sorted(families, key=lambda family: family["root"])


# ---------------------------------------------------------------------------------- cards

def _read(path):
    """The parsed card, or None when it cannot be read: section 4.3 says such a copy is never on its branch."""
    try:
        return cards.Card(Path(path))
    except (OSError, ValueError):
        return None


def _copies(trees, questions):
    """card name -> [(tree, path)] in git's worktree order; `*.spec.md` files are never cards."""
    found = {}
    for tree in trees:
        folder = os.path.join(tree["path"], FEATURES_DIR)
        try:
            names = sorted(os.listdir(folder)) if os.path.isdir(folder) else []
        except OSError as error:
            questions.append({"q": "Why could the cards in `%s` not be read?" % folder, "ctx": str(error)})
            continue
        for name in names:
            path = os.path.join(folder, name)
            if name.endswith(".md") and not name.endswith(cards.SPEC_SUFFIX) and os.path.isfile(path):
                found.setdefault(name[: -len(".md")], []).append((tree, path))
    return found


def _choose(trees, copies, questions):
    """card name -> (path of its live copy, parsed Card or None), by section 4.3's three rules."""
    chosen = {}
    for name in sorted(copies):
        read = [(tree, path, _read(path)) for tree, path in copies[name]]
        live = [item for item in read if item[2] is not None and item[2].branch and item[2].branch == item[0]["branch"]]
        if len(live) > 1:
            where = ["`%s`" % item[0]["name"] for item in live]
            questions.append({"q": "Which copy of `%s` is current?" % name,
                              "ctx": "The copies in %s each name the branch checked out there; the one in %s, "
                                     "listed first by git, is used." % (", ".join(where), where[0])})
        primary = [item for item in read if item[0] is trees[0]]
        pick = (live or primary or read)[0]
        chosen[name] = (pick[1], pick[2])
    return chosen


def _closure(seeds, chosen):
    """`seeds` plus every card they name in `## Depends on`, transitively, as each one's live copy reads it."""
    kept, pending = set(), list(seeds)
    while pending:
        name = pending.pop()
        if name in kept or name not in chosen:
            continue  # a cycle, or a dependency that is no card of this family
        kept.add(name)
        card = chosen[name][1]
        if card is not None:
            pending.extend(target for target, _ in card.depends_on)
    return kept


# --------------------------------------------------------------------------------- narrowing

def _is_worktree(tree, worktree, resolved):
    return tree["path"] == resolved or tree["name"] == worktree


def _narrow(families, repo, branch, worktree):
    """(outcome, [(family, names of the cards it keeps)]) by section 4.2."""
    if repo:
        families = [family for family in families if family["label"] == repo]
        if not families:
            return "no_matching_repository", []
    allowed = {family["root"]: None for family in families}  # the branches the worktree allows, per family
    if worktree:
        resolved = os.path.realpath(os.path.expanduser(worktree))
        allowed = {}
        for family in families:
            matching = [tree["branch"] for tree in family["trees"] if _is_worktree(tree, worktree, resolved)]
            if matching:
                allowed[family["root"]] = set(matching)
        if not allowed:
            return "no_such_worktree", []
    families = [family for family in families if family["root"] in allowed]
    if not (branch or worktree):
        return "ok", [(family, set(family["chosen"])) for family in families]
    kept = []
    for family in families:
        permitted = allowed[family["root"]]
        seeds = {name for name, (_, card) in family["chosen"].items()
                 if card is not None and card.branch and (not branch or card.branch == branch)
                 and (permitted is None or card.branch in permitted)}
        if seeds:
            kept.append((family, _closure(seeds, family["chosen"])))
    return ("ok", kept) if kept else ("nothing_matched", [])


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


def _result(outcome, families, questions, missed):
    return {"outcome": outcome, "families": families, "questions": questions, "missed": missed}


def scan(directory, repo="", branch="", worktree=""):
    """The section 4.4 object for a canonical directory."""
    missed = {"unreadable": 0, "depthLimit": 0, "symlinks": 0}
    if not os.path.isdir(directory):
        return _result("no_such_directory", [], [], missed)
    refusals = []
    candidates = _walk_down(directory, missed)
    for top in _walk_up(directory, refusals):
        if top not in candidates:
            candidates.append(top)
    found = _families(candidates, refusals)
    for family in found:
        family["questions"] = []
        copies = _copies(family["trees"], family["questions"])
        family["chosen"] = _choose(family["trees"], copies, family["questions"])
    outcome, kept = _narrow(found, repo, branch, worktree) if found else ("no_repository", [])
    families = [{"root": family["root"], "label": family["label"],
                 "cards": [family["chosen"][name][0] for name in sorted(names)],
                 "questions": family["questions"]} for family, names in kept]
    refusals.sort(key=lambda question: question["q"])
    return _result(outcome, families, _missed_question(directory, missed) + refusals, missed)


def _text_field(request, key):
    value = request.get(key)
    if value is None:
        return ""
    if not isinstance(value, str):
        raise ValueError("%s must be text" % key)
    return value


def main():
    try:
        request = json.load(sys.stdin)
        directory = request["directory"]
        if not isinstance(directory, str) or not directory:
            raise ValueError("directory must be a non-empty string")
        narrowing = {key: _text_field(request, key) for key in NARROWING_KEYS}
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        print("ledger_scan: bad request: %s" % error, file=sys.stderr)
        return EXIT_BAD_REQUEST
    print(json.dumps(scan(os.path.realpath(os.path.expanduser(directory)), **narrowing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
