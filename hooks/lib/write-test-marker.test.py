#!/usr/bin/env python3
"""Unit tests for write-test-marker.py. Run: python3 hooks/lib/write-test-marker.test.py

The writer is the only component that produces a marker, so this suite pins its output shape
directly rather than inferring it from the gate's behaviour -- the same argument that produced
classify-git-command.test.py. Throwaway git repos, because every resolution step the writer
takes (`ls-files --full-name`, `hash-object`, `rev-parse --show-toplevel`) runs against a real
index in the writer's OWN cwd.

Deliberately dependency-free (no pytest): adding a dependency is not a unilateral call, and
this has to run anywhere the hook runs.

EVERY case drives the writer the way the card's call site does -- an ABSOLUTE path argument,
with the repo root as cwd -- because that pairing is the specified contract, not an incidental
detail. Measured while writing this suite: normalise the test path to repo-relative and then
hand that value to a second git call from a DIFFERENT cwd and git resolves it against the cwd
(`panes/panes/adapters/...`), so the subject check reports "not tracked" for a file that is.

SCOPE: the two repo-level inventory assertions belong to task 8, not here. Until the 11
pre-existing suites are wired, a wiring assertion is legitimately red -- see the feature card,
"What the inventory test asserts, and why not a count". The suite-level case where $0 itself is
relative is also task 8's: the call site resolves that before the writer ever sees it.
"""

import contextlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_WRITER = os.path.join(_HERE, "write-test-marker.py")

# Asserted as NUMBERS, not read back off the artifact under test -- a mode derived from the file
# the writer just produced agrees with whatever wrote it, including a wrong one.
MARKER_MODE = 0o600
STORE_MODE = 0o700

# ISO-8601 with a literal Z, matching the schema block in the card. Informational only: nothing
# in this suite lets written_at influence an outcome, because nothing in the writer may.
WRITTEN_AT_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
BLOB_RE = re.compile(r"^([0-9a-f]{40}|[0-9a-f]{64})$")


def _load_writer():
    """Return the writer module, or None when it does not exist yet (the RED state)."""
    if not os.path.exists(_WRITER):
        return None
    spec = importlib.util.spec_from_file_location("write_test_marker", _WRITER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@contextlib.contextmanager
def _cd(path):
    """chdir with restore. The writer resolves git paths in ITS cwd, so the cwd IS an input."""
    prior = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(prior)


@contextlib.contextmanager
def _repo(files, add=None):
    """A throwaway repo containing `files` {relpath: content}; `add` defaults to all of them.

    Only the paths in `add` are staged, so an UNTRACKED file is expressible -- which is the
    whole point of the no-subject skip and the failure-exit cases.
    """
    root = tempfile.mkdtemp(prefix="marker-writer-test-")
    try:
        subprocess.run(["git", "init", "-q", root], check=True)
        for key, value in (("user.email", "t@example.com"), ("user.name", "t")):
            subprocess.run(["git", "-C", root, "config", key, value], check=True)
        for rel, content in files.items():
            full = os.path.join(root, rel)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as handle:
                handle.write(content)
        staged = files.keys() if add is None else add
        for rel in staged:
            subprocess.run(["git", "-C", root, "add", "--", rel], check=True)
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def _self(root, rel):
    """MARKER_SELF as the call site builds it: absolute, resolved before any chdir."""
    return os.path.join(root, rel)


def _store(root):
    return os.path.join(root, "hooks", "state", "test-markers")


def _state_dir(root):
    """The card modes `hooks/state/`, NOT the test-markers/ subdirectory inside it. Asserting
    a mode on the subdirectory would invent a requirement -- a 0700 parent already blocks
    traversal, so the spec has no reason to state one."""
    return os.path.join(root, "hooks", "state")


def _git(root, *args):
    out = subprocess.run(
        ["git", "-C", root] + list(args), capture_output=True, text=True, check=True
    )
    return out.stdout.strip()


def _run_cli(root, arg):
    return subprocess.run(
        [sys.executable, "-I", _WRITER, arg], cwd=root, capture_output=True, text=True
    )


# --- derivation -------------------------------------------------------------------------
# Driven from the card's step-1 classification table. Rows 1 and 2 are the writer's direction
# (it is handed a TEST path and derives the subject); rows 3-5 are the gate's direction or form
# no pair at all, and are asserted in the classifier's suite, not here.
DERIVATION = [
    ("hooks/foo.test.sh", "hooks/foo.sh", "row 1 -- strip .test.sh, append .sh"),
    ("hooks/foo.test.py", "hooks/foo.py", "row 2 -- strip .test.py, append .py"),
    ("panes/adapters/cmux-layout.test.sh", "panes/adapters/cmux-layout.sh",
     "row 1 through a nested path -- derivation is on the basename, not the dirname"),
]

# --- percent-encoding -------------------------------------------------------------------
# LITERAL expected keys, never the writer's own output round-tripped. A writer and a gate that
# both applied the substitutions in the revision 1-13 order would agree with each other and pass
# every round-trip test; only a literal catches it. The first row is the measured case from the
# card: it carries no `%` at all, and the wrong order still corrupts it.
ENCODING = [
    ("hooks/judge-guard.sh", "hooks%2Fjudge-guard.sh",
     "measured: the wrong order yields hooks%252Fjudge-guard.sh -- no % needed in the path"),
    ("panes/adapters/cmux-layout.sh", "panes%2Fadapters%2Fcmux-layout.sh",
     "the key the subdirectory scenario in the card requires"),
    ("hooks/a%b.sh", "hooks%2Fa%25b.sh",
     "% encodes FIRST, so the %25 it produces is not re-encoded by the / pass"),
]


def check_derivation(mod, record):
    for test_rel, subject_rel, why in DERIVATION:
        files = {test_rel: "test body\n", subject_rel: "subject body\n"}
        with _repo(files) as root, _cd(root):
            marker = mod.write_marker(_self(root, test_rel))
            if marker is None:
                record(False, "derivation {}".format(test_rel),
                       "want a marker, got None ({})".format(why))
                continue
            with open(marker) as handle:
                doc = json.load(handle)
            got = doc.get("subject", {}).get("path")
            record(got == subject_rel, "derivation {}".format(test_rel),
                   "want subject {!r}, got {!r} ({})".format(subject_rel, got, why))


def check_encoding(mod, record):
    for subject_rel, want_key, why in ENCODING:
        test_rel = subject_rel[:-3] + ".test.sh"
        files = {test_rel: "test body\n", subject_rel: "subject body\n"}
        with _repo(files) as root, _cd(root):
            marker = mod.write_marker(_self(root, test_rel))
            got = os.path.basename(marker) if marker else None
            record(got == want_key, "encoding {}".format(subject_rel),
                   "want key {!r}, got {!r} ({})".format(want_key, got, why))


def check_normalisation(mod, record):
    """An absolute MARKER_SELF must become a repo-relative key, never an absolute one.

    This is the writer's half of the measured subdirectory case: the suite resolves $0 to an
    absolute path before any cd, and the writer turns that back into the repo-relative key the
    gate looks up. An implementation that skips --full-name keys the store by an absolute path
    and the gate never finds it.
    """
    test_rel = "panes/adapters/cmux-layout.test.sh"
    subject_rel = "panes/adapters/cmux-layout.sh"
    files = {test_rel: "test body\n", subject_rel: "subject body\n"}
    with _repo(files) as root, _cd(root):
        marker = mod.write_marker(_self(root, test_rel))
        got = os.path.basename(marker) if marker else None
        want = "panes%2Fadapters%2Fcmux-layout.sh"
        record(got == want, "an absolute path normalises to a repo-relative key",
               "want {!r}, got {!r}".format(want, got))
        if marker:
            with open(marker) as handle:
                doc = json.load(handle)
            for side, rel in (("test", test_rel), ("subject", subject_rel)):
                got_path = doc.get(side, {}).get("path")
                record(got_path == rel, "the recorded {} path is repo-relative".format(side),
                       "want {!r}, got {!r}".format(rel, got_path))


def check_no_subject_skip(mod, record):
    """An untracked subject: notice on stderr, NO marker, exit 0. A green suite stays green."""
    test_rel = "hooks/orphan.test.sh"
    subject_rel = "hooks/orphan.sh"
    # the subject exists ON DISK but is never staged -- tracked-ness is the predicate here, and
    # a fixture that omitted the file entirely would pass against an implementation that checks
    # existence instead of the index
    files = {test_rel: "test body\n", subject_rel: "subject body\n"}
    with _repo(files, add=[test_rel]) as root:
        proc = _run_cli(root, _self(root, test_rel))
        record(proc.returncode == 0, "no-subject skip exits 0",
               "want 0, got {} (stderr: {!r})".format(proc.returncode, proc.stderr.strip()))
        record(proc.stderr.strip() != "", "no-subject skip writes a notice to stderr",
               "want a one-line notice, got empty stderr")
        listing = os.listdir(_store(root)) if os.path.isdir(_store(root)) else []
        record(listing == [], "no-subject skip writes no marker",
               "want an empty store, got {!r}".format(listing))


def check_schema_and_mode(mod, record):
    test_rel = "hooks/foo.test.sh"
    subject_rel = "hooks/foo.sh"
    files = {test_rel: "test body\n", subject_rel: "subject body\n"}
    with _repo(files) as root, _cd(root):
        marker = mod.write_marker(_self(root, test_rel))
        if marker is None:
            record(False, "schema", "want a marker, got None")
            return
        with open(marker) as handle:
            doc = json.load(handle)

        record(doc.get("version") == 1, "schema version is 1",
               "want 1, got {!r}".format(doc.get("version")))
        for side, rel in (("subject", subject_rel), ("test", test_rel)):
            record(doc.get(side, {}).get("path") == rel, "schema {} path".format(side),
                   "want {!r}, got {!r}".format(rel, doc.get(side, {}).get("path")))
            blob = doc.get(side, {}).get("blob", "")
            record(bool(BLOB_RE.match(blob)), "schema {} blob is a hex oid".format(side),
                   "want 40 or 64 hex chars, got {!r}".format(blob))
            # the blob must hash the real CONTENT, not merely be hex-shaped
            want_blob = _git(root, "hash-object", "--", rel)
            record(blob == want_blob, "schema {} blob hashes the real content".format(side),
                   "want {!r}, got {!r}".format(want_blob, blob))

        stamp = doc.get("written_at", "")
        record(bool(WRITTEN_AT_RE.match(stamp)), "schema written_at is ISO-8601 Z",
               "want YYYY-MM-DDTHH:MM:SSZ, got {!r}".format(stamp))

        marker_mode = os.stat(marker).st_mode & 0o777
        record(marker_mode == MARKER_MODE, "marker file is 0600",
               "want {:o}, got {:o} -- a umask default would leave this 0644".format(
                   MARKER_MODE, marker_mode))
        state_mode = os.stat(_state_dir(root)).st_mode & 0o777
        record(state_mode == STORE_MODE, "hooks/state/ the writer created is 0700",
               "want {:o}, got {:o}".format(STORE_MODE, state_mode))


def check_atomic_write(mod, record):
    """Temp file in the SAME directory + os.replace: no residue, and a rewrite replaces."""
    test_rel = "hooks/foo.test.sh"
    subject_rel = "hooks/foo.sh"
    files = {test_rel: "test body\n", subject_rel: "subject body\n"}
    with _repo(files) as root, _cd(root):
        marker = mod.write_marker(_self(root, test_rel))
        listing = sorted(os.listdir(_store(root)))
        want = [os.path.basename(marker)] if marker else []
        record(listing == want, "atomic write leaves no temp residue",
               "want {!r}, got {!r}".format(want, listing))

        # rewriting over an existing marker must replace it, not fail and not accumulate
        with open(os.path.join(root, subject_rel), "w") as handle:
            handle.write("changed body\n")
        subprocess.run(["git", "-C", root, "add", "--", subject_rel], check=True)
        second = mod.write_marker(_self(root, test_rel))
        listing = sorted(os.listdir(_store(root)))
        record(listing == want, "a rewrite replaces rather than accumulating",
               "want {!r}, got {!r}".format(want, listing))
        if second:
            with open(second) as handle:
                doc = json.load(handle)
            want_blob = _git(root, "hash-object", "--", subject_rel)
            record(doc.get("subject", {}).get("blob") == want_blob,
                   "a rewrite records the NEW content",
                   "want {!r}, got {!r}".format(want_blob, doc.get("subject", {}).get("blob")))


def check_failure_exits(mod, record):
    """An untracked TEST path cannot be normalised, so the writer fails loudly. A silent
    no-marker would surface later as a confusing block."""
    test_rel = "hooks/ghost.test.sh"
    subject_rel = "hooks/ghost.sh"
    files = {test_rel: "test body\n", subject_rel: "subject body\n"}
    with _repo(files, add=[subject_rel]) as root:
        proc = _run_cli(root, _self(root, test_rel))
        record(proc.returncode != 0, "an untracked test path exits non-zero",
               "want non-zero, got {}".format(proc.returncode))
        record(proc.stderr.strip() != "", "an untracked test path explains itself on stderr",
               "want a message, got empty stderr")
        listing = os.listdir(_store(root)) if os.path.isdir(_store(root)) else []
        record(listing == [], "an untracked test path writes no marker",
               "want an empty store, got {!r}".format(listing))

    # outside a repo entirely there is no toplevel to resolve
    outside = tempfile.mkdtemp(prefix="marker-writer-norepo-")
    try:
        with open(os.path.join(outside, "foo.test.sh"), "w") as handle:
            handle.write("test body\n")
        proc = _run_cli(outside, os.path.join(outside, "foo.test.sh"))
        record(proc.returncode != 0, "outside a repo the writer exits non-zero",
               "want non-zero, got {}".format(proc.returncode))
    finally:
        shutil.rmtree(outside, ignore_errors=True)


CHECKS = [
    check_derivation,
    check_encoding,
    check_normalisation,
    check_no_subject_skip,
    check_schema_and_mode,
    check_atomic_write,
    check_failure_exits,
]


def main():
    results = []

    def record(ok, name, detail):
        results.append((ok, name, detail))

    mod = _load_writer()
    if mod is None:
        print("FAIL — {} does not exist yet (task 5 is the green step)".format(
            os.path.relpath(_WRITER, os.getcwd())))
        print("\nwriter unit: 0 passed, {} check groups could not run".format(len(CHECKS)))
        return 1

    for check in CHECKS:
        check(mod, record)

    passed = sum(1 for ok, _, _ in results if ok)
    for ok, name, detail in results:
        if not ok:
            print("FAIL — {}\n       {}".format(name, detail))
    failed = len(results) - passed
    print("\nwriter unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
