#!/usr/bin/env python3
"""Record that a suite passed against the exact content it was run over.

Called by each paired suite after its tally, with the repo root as cwd:

    python3 -I hooks/lib/write-test-marker.py "$MARKER_SELF"

It writes `<repo>/hooks/state/test-markers/<encoded-subject>` -- a receipt naming the two blobs
that were green together, which hooks/test-marker-guard.sh later compares against what a commit
is trying to stage. The marker is a receipt, not a grade (ADR 0027): it records what was verified,
never whether the verification was any good.

Three outcomes, and they are deliberately not the same:

  * a marker is written                     -> exit 0
  * the test has no tracked subject         -> notice on stderr, NO marker, exit 0
  * anything else (unpaired or untracked
    input, no repo, a failed git call)      -> message on stderr, non-zero

The middle case exists because a green suite must not be turned red by the absence of a file it
never claimed to own; the third fails loudly because the writer only ever receives a suite's own
$0, so a bad argument is a call-site wiring error, and a silent no-marker would surface later as
a confusing block instead.

Every git call is pinned to the repo root with `-C`. Measured: after `--full-name` normalisation
the derived subject path is repo-relative, so a git call made from any other cwd resolves it
against *that* cwd (`panes/panes/adapters/...`) and reports a tracked subject as missing.
"""

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

__all__ = ["write_marker", "derive_subject", "encode_key", "WriterError"]

SCHEMA_VERSION = 1
STATE_MODE = 0o700
MARKER_MODE = 0o600

STATE_DIR = os.path.join("hooks", "state")
STORE_DIR = os.path.join(STATE_DIR, "test-markers")

# Rows 1 and 2 of the step-1 classification table -- the only two forms that pair. Rows 3-5 are
# the gate's direction or form no pair at all, and none of them is valid input here.
PAIR_SUFFIXES = ((".test.sh", ".sh"), (".test.py", ".py"))


class WriterError(Exception):
    """A failure the calling suite must see: it is reported on stderr and exits non-zero."""


def _git(root, args):
    """Run git at `root`, returning stripped stdout; raise WriterError on a non-zero exit."""
    proc = subprocess.run(
        ["git", "-C", root] + list(args), capture_output=True, text=True
    )
    if proc.returncode != 0:
        detail = proc.stderr.strip() or "exit {}".format(proc.returncode)
        raise WriterError("git {} failed: {}".format(" ".join(args), detail))
    return proc.stdout.strip()


def _repo_root():
    """The toplevel of the repo containing the writer's OWN cwd -- never $HOME.

    Resolved here rather than from the argument because the call site is specified to run the
    writer with the repo root as its cwd; a marker written inside a linked worktree has to be
    read back inside that worktree.
    """
    proc = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    if proc.returncode != 0:
        raise WriterError(
            "not inside a git repository (cwd {}): {}".format(
                os.getcwd(), proc.stderr.strip() or "exit {}".format(proc.returncode)
            )
        )
    return proc.stdout.strip()


def _normalise(root, path):
    """The repo-relative path of a tracked file, from any absolute or cwd-relative form.

    The suite passes `$0`, which is relative to the suite's cwd -- measured: running
    `bash adapters/cmux-layout.test.sh` from inside `panes/` yields `adapters/cmux-layout.test.sh`
    while the store key needs `panes/adapters/cmux-layout.test.sh`. `--error-unmatch` makes an
    untracked path an error rather than a silently empty answer.
    """
    return _git(root, ["ls-files", "--full-name", "--error-unmatch", "--", path])


def _is_tracked(root, rel):
    proc = subprocess.run(
        ["git", "-C", root, "ls-files", "--error-unmatch", "--", rel],
        capture_output=True,
        text=True,
    )
    return proc.returncode == 0


def derive_subject(test_rel):
    """The sibling subject for a test path, or None when the path forms no pair.

    Derivation is on the suffix alone, so a nested path keeps its directory: row 1 turns
    `panes/adapters/cmux-layout.test.sh` into `panes/adapters/cmux-layout.sh`.
    """
    for test_suffix, subject_suffix in PAIR_SUFFIXES:
        if test_rel.endswith(test_suffix):
            return test_rel[: -len(test_suffix)] + subject_suffix
    return None


def encode_key(subject_rel):
    """The store filename for a repo-relative subject path.

    The order is normative and load-bearing: `%` encodes FIRST, then `/`. Applied the other way
    round, the `%2F` the slash pass introduces is re-encoded by the percent pass into `%252F` --
    measured on `hooks/judge-guard.sh`, which carries no `%` at all, so the reversed order
    corrupts the key of every file in the store. A writer and a gate that both got this wrong
    would agree with each other and pass every round-trip test.
    """
    return subject_rel.replace("%", "%25").replace("/", "%2F")


def _ensure_store(root):
    """Create `hooks/state/` at 0700 and the store beneath it, returning the store path.

    The chmod is not redundant with the mode= argument: measured, `os.makedirs(mode=0o700,
    exist_ok=True)` against a directory already at 0755 returns without error and leaves it at
    0755, exactly as `mkdir -p -m 0700` does. Both this writer and the gate can be the first to
    create the directory, and whichever loses the race cannot repair a loose mode it did not set,
    so both run the same idempotent pair and call order stops mattering.
    """
    state = os.path.join(root, STATE_DIR)
    store = os.path.join(root, STORE_DIR)
    os.makedirs(state, mode=STATE_MODE, exist_ok=True)
    os.chmod(state, STATE_MODE)
    os.makedirs(store, mode=STATE_MODE, exist_ok=True)
    return store


def _write_atomically(path, payload):
    """Temp file in the SAME directory + os.replace, so a reader never sees a partial marker.

    Same directory because os.replace is only atomic within one filesystem. mkstemp already
    creates at 0600, but the mode is set explicitly rather than inherited: it is a stated
    requirement of the store, not a side effect of how the temp file happened to be made.
    """
    directory = os.path.dirname(path)
    handle, temp = tempfile.mkstemp(dir=directory, prefix=".tmp-marker-")
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(payload)
        os.chmod(temp, MARKER_MODE)
        os.replace(temp, path)
    except BaseException:
        # leave no residue: the store's listing is itself asserted, and a stray temp file would
        # be read by nothing and cleaned by nothing
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def write_marker(test_path):
    """Write the marker for `test_path`, returning its path, or None for a test with no subject.

    Raises WriterError for input that forms no pair, input that is not tracked, and any failing
    git call -- see the module docstring for why those are not the same outcome as None.
    """
    root = _repo_root()
    test_rel = _normalise(root, test_path)

    subject_rel = derive_subject(test_rel)
    if subject_rel is None:
        raise WriterError(
            "{} is not a test path: expected a name ending {}".format(
                test_rel, " or ".join(suffix for suffix, _ in PAIR_SUFFIXES)
            )
        )

    if not _is_tracked(root, subject_rel):
        sys.stderr.write(
            "marker skipped: {} has no tracked subject {}\n".format(test_rel, subject_rel)
        )
        return None

    marker = {
        "version": SCHEMA_VERSION,
        "subject": {
            "path": subject_rel,
            "blob": _git(root, ["hash-object", "--", subject_rel]),
        },
        "test": {
            "path": test_rel,
            "blob": _git(root, ["hash-object", "--", test_rel]),
        },
        # informational only, and nothing may decide on it: freshness is decided by content
        # hashes alone, because a timestamp rule would re-admit the staleness problem the blob
        # key dissolves
        "written_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    path = os.path.join(_ensure_store(root), encode_key(subject_rel))
    _write_atomically(path, json.dumps(marker, indent=2, sort_keys=True) + "\n")
    return path


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        sys.stderr.write("usage: write-test-marker.py <test-file-path>\n")
        return 2
    try:
        write_marker(args[0])
    except WriterError as error:
        sys.stderr.write("marker write failed: {}\n".format(error))
        return 1
    except OSError as error:
        sys.stderr.write("marker write failed: {}\n".format(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
