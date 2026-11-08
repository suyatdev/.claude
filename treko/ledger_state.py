"""Run ids, names and list rows (docs/features/treko-ledger.spec.md sections 8.1 and 8.3), and the
in-memory ledger of section 5.1 behind the one lock of section 5.6.

A caller canonicalises the directory (`expanduser`, then `realpath`, section 3.4) before it reaches
any function here; only a worktree is canonicalised in `run_id`, because section 8.1 says so.
No file is read or written here yet: `ledger.json` is task 15's.
"""

import copy
import hashlib
import json
import os
import re
import threading

from cards import NO_VALUE, UNPARSEABLE_META

LEDGER_VERSION = 1
ID_PREFIX = "r"
ID_HEX_DIGITS = 16
NAME_SEPARATOR = " · "  # U+00B7 with a space each side, the prototype's `parts.join(' · ')`
HOME_MARK = "~"
# What a row shows for a figure whose key the run lacks (D41). Spelled as the analyzer's "no
# worktree" dash on purpose, but it is this module's own rule, so it is not that constant.
ABSENT_FIGURE = "—"
FOLDER_MISSING = "folder missing"  # the note the analyzer gives a branch whose worktree is gone
TASKS_META = re.compile(r"(\d+)/(\d+)")


# ----------------------------------------------------------------------- id, name, dir, label

def _canonical_worktree(worktree):
    if "/" in worktree or worktree.startswith("~"):
        return os.path.realpath(os.path.expanduser(worktree))
    return worktree


def run_id(directory, repo, branch, worktree):
    fields = [directory, repo, branch, _canonical_worktree(worktree)]
    text = json.dumps(fields, ensure_ascii=False, separators=(",", ":"))
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return ID_PREFIX + digest[:ID_HEX_DIGITS]


def _narrowing_parts(repo, branch, worktree):
    labelled = (("repo", repo), ("branch", branch), ("worktree", worktree))
    return ["%s %s" % (word, value) for word, value in labelled if value]


def _last_component(directory):
    return os.path.basename(directory.rstrip("/")) or directory


def run_name(directory, repo, branch, worktree):
    return NAME_SEPARATOR.join(
        [_last_component(directory), *_narrowing_parts(repo, branch, worktree)])


def run_dir(directory):
    """Home becomes `~` only where it is a whole path component: `/Users/xy` is not in `/Users/x`."""
    home = os.path.expanduser(HOME_MARK).rstrip("/")
    if not home:
        return directory
    if directory == home:
        return HOME_MARK
    if directory.startswith(home + "/"):
        return HOME_MARK + directory[len(home):]
    return directory


def queue_label(directory, repo, branch, worktree):
    return NAME_SEPARATOR.join([run_dir(directory), *_narrowing_parts(repo, branch, worktree)])


# ------------------------------------------------------------------------------------- rows

def _stored(run, key):
    value = run.get(key)
    return ABSENT_FIGURE if value is None else value


def _has_worktree(branch):
    shown = branch.get("wt", "") not in ("", NO_VALUE)
    return shown and branch.get("note") != FOLDER_MISSING


def _branch_figures(branches):
    """repos, branches, worktrees."""
    if branches is None:
        return (ABSENT_FIGURE,) * 3
    repos = {branch.get("repo") for branch in branches}
    return len(repos), len(branches), sum(1 for branch in branches if _has_worktree(branch))


def _feature_figures(features):
    """features, tasksDone, tasksTotal, unreadableCards."""
    if features is None:
        return (ABSENT_FIGURE,) * 4
    done = total = unreadable = 0
    for feature in features:
        meta = feature.get("meta")
        if meta == UNPARSEABLE_META:
            unreadable += 1
            continue
        counts = TASKS_META.fullmatch(meta) if isinstance(meta, str) else None
        if counts:
            done += int(counts.group(1))
            total += int(counts.group(2))
    return len(features), done, total, unreadable


def _row(run, can_delete):
    repos, branches, worktrees = _branch_figures(run.get("branches"))
    features, done, total, unreadable = _feature_figures(run.get("features"))
    return {
        "id": run["id"], "name": _stored(run, "name"), "dir": _stored(run, "dir"),
        "analyzedAt": _stored(run, "analyzedAt"),
        "repos": repos, "branches": branches, "worktrees": worktrees,
        "features": features, "tasksDone": done, "tasksTotal": total,
        "unreadableCards": unreadable, "canDelete": can_delete,
    }


def _analyzed_at(run):
    stamp = run.get("analyzedAt")
    return stamp if isinstance(stamp, str) else ""  # "" sorts below every timestamp


def run_rows(runs, hidden):
    """The Ledger's list, newest first; recomputed from the runs on every call (D28)."""
    hidden_ids = set(hidden)
    visible = [run for run in runs if run.get("id") not in hidden_ids]
    # `reverse=True` keeps equal keys in their original order, which is the tie rule (section 8.3).
    newest_first = sorted(visible, key=_analyzed_at, reverse=True)
    can_delete = len(visible) > 1
    return [_row(run, can_delete) for run in newest_first]


# ---------------------------------------------------------------------------- the ledger

def _empty_state():
    return {"version": LEDGER_VERSION, "queue": [], "hidden": [], "requests": {}}


class Ledger:
    """Section 5.1's state, guarded by the one lock of section 5.6.

    Nothing outside holds a reference to the state: `snapshot` hands out a copy, and `update` gives
    its change a private copy, so a change that raises leaves the state as it was. The lock is not
    reentrant, so a change must not call back into the ledger.
    """

    def __init__(self, state=None):
        self._lock = threading.Lock()
        self._state = _empty_state() if state is None else copy.deepcopy(state)

    def snapshot(self):
        with self._lock:
            return copy.deepcopy(self._state)

    def update(self, change):
        """Replace the state with `change(copy of the state)`; returns a copy of the new state."""
        with self._lock:
            self._state = copy.deepcopy(change(copy.deepcopy(self._state)))
            return copy.deepcopy(self._state)
