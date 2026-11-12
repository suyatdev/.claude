"""Run ids, names and list rows (docs/features/treko-ledger.spec.md sections 8.1 and 8.3), and the
in-memory ledger of section 5.1 behind the one lock of section 5.6.

A caller canonicalises the directory (`expanduser`, then `realpath`, section 3.4) before it reaches
any function here; only a worktree is canonicalised in `run_id`, because section 8.1 says so.
The ledger's file, `<store dir>/ledger.json`, and the store folder's lock are task 15's (D44): they
are read, written and taken here, and nowhere else.
"""

import copy
import errno
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile
import threading
from pathlib import Path

from cards import NO_VALUE, UNPARSEABLE_META

LEDGER_VERSION = 1
LEDGER_FILE = "ledger.json"
LOCK_FILE = ".treko-server.lock"
TEMP_PREFIX = ".ledger-"
TEMP_SUFFIX = ".tmp"
OWNER_ONLY = 0o600
ITEM_STATES = ("waiting", "running", "interrupted", "failed")
NOT_AN_OS_ERROR = "UNEXPECTED"  # what a write failure that has no errno says instead of a value
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


class LedgerStartupError(Exception):
    """The store folder or its ledger file cannot be used; the message names which."""


class LedgerWriteError(Exception):
    """A save failed; the message is the errno symbolic name (or a fixed word), never a field value."""


def _errno_name(exc):
    return errno.errorcode.get(exc.errno, "UNKNOWN")


# ------------------------------------------------------------------- the file and the store lock

def _rule_broken(state):
    """The first rule of section 5.1 the state breaks, as words for the message; None when sound."""
    if not isinstance(state, dict):
        return "is not a JSON object"
    if state.get("version") != LEDGER_VERSION:
        return "has version %r, not %d" % (state.get("version"), LEDGER_VERSION)
    for key in ("queue", "hidden", "requests"):
        if key not in state:
            return "lacks %r" % key
    if not isinstance(state["queue"], list):
        return "has a 'queue' that is not a list"
    if not isinstance(state["hidden"], list):
        return "has a 'hidden' that is not a list"
    if not isinstance(state["requests"], dict):
        return "has a 'requests' that is not an object"
    for item in state["queue"]:
        if not isinstance(item, dict) or item.get("state") not in ITEM_STATES:
            return "has a queue item that is not an object with a state of %s" % "/".join(ITEM_STATES)
    return None


def load_ledger(store_dir):
    """The saved ledger, or an empty one when the file is absent; anything else wrong aborts startup."""
    path = Path(store_dir) / LEDGER_FILE
    try:
        with open(str(path), encoding="utf-8") as handle:
            text = handle.read()
    except FileNotFoundError:
        return _empty_state()
    except OSError as exc:
        raise LedgerStartupError("cannot read ledger file %s: %s" % (path, _errno_name(exc)))
    try:
        state = json.loads(text)
    except ValueError:  # includes a file that is not UTF-8
        raise LedgerStartupError("ledger file %s is not valid JSON" % path)
    broken = _rule_broken(state)
    if broken:
        raise LedgerStartupError("ledger file %s %s" % (path, broken))
    return state


def _unlink_quietly(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def write_ledger(store_dir, state):
    """Save `state` whole or not at all: temp file beside the target, fsync, then `os.replace`.

    Any failure removes the temp file, says one line on stderr and raises LedgerWriteError, so the
    old file is still whole. The line names the errno and nothing from `state`.
    """
    store_dir = Path(store_dir)
    temp_path = None
    try:
        store_dir.mkdir(parents=True, exist_ok=True)
        fd, temp_path = tempfile.mkstemp(dir=str(store_dir), prefix=TEMP_PREFIX, suffix=TEMP_SUFFIX)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            os.fchmod(handle.fileno(), OWNER_ONLY)  # a umask cannot widen it, an old file's mode is not carried
            json.dump(state, handle, ensure_ascii=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, str(store_dir / LEDGER_FILE))
    except Exception as exc:
        if temp_path is not None:
            _unlink_quietly(temp_path)
        name = _errno_name(exc) if isinstance(exc, OSError) else NOT_AN_OS_ERROR
        sys.stderr.write("server: ledger write failed: %s\n" % name)
        raise LedgerWriteError(name) from None


def acquire_store_lock(store_dir):
    """Take the one-server-per-store-folder lock and return the open file; the caller holds it.

    The lock lives as long as the returned file object: closing it, or letting it be collected,
    releases it. The lock file itself is never deleted.
    """
    path = Path(store_dir) / LOCK_FILE
    try:
        fd = os.open(str(path), os.O_RDWR | os.O_CREAT, OWNER_ONLY)
    except OSError as exc:
        raise LedgerStartupError("cannot open lock file %s: %s" % (path, _errno_name(exc)))
    try:
        os.fchmod(fd, OWNER_ONLY)  # the open's mode is masked by the umask, and an old file may be wider
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        raise LedgerStartupError("another Treko server is using %s" % store_dir)
    except OSError as exc:
        os.close(fd)
        raise LedgerStartupError("cannot lock %s: %s" % (path, _errno_name(exc)))
    return os.fdopen(fd, "r+")


class Ledger:
    """Section 5.1's state, guarded by the one lock of section 5.6.

    Nothing outside holds a reference to the state: `snapshot` hands out a copy, and `update` gives
    its change a private copy, so a change that raises leaves the state as it was. The lock is not
    reentrant, so a change must not call back into the ledger. With a `store_dir` the new state is
    saved before it replaces the old one, so a failed save changes nothing (section 5.6).
    """

    def __init__(self, state=None, store_dir=None):
        self._lock = threading.Lock()
        self._state = _empty_state() if state is None else copy.deepcopy(state)
        self._store_dir = store_dir

    def snapshot(self):
        with self._lock:
            return copy.deepcopy(self._state)

    def update(self, change):
        """Replace the state with `change(copy of the state)`; returns a copy of the new state."""
        with self._lock:
            new_state = copy.deepcopy(change(copy.deepcopy(self._state)))
            if self._store_dir is not None:
                write_ledger(self._store_dir, new_state)
            self._state = new_state
            return copy.deepcopy(self._state)
