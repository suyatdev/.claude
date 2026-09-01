#!/usr/bin/env python3
"""Decide whether a `git commit` bash command may proceed, per the verification-marker gate.

Called by hooks/test-marker-guard.sh, and only for a repo it has already confirmed has opted in
(see that file's header). Reads the SAME PreToolUse payload bash buffered, from stdin; writes
EXACTLY one tab-separated line to stdout; never touches the network or prompts for anything.

ADR 0026: no JSON crosses back into bash. Classification, path collection, pairing, marker
reading and blob comparison all run in this one process; bash consumes only the TSV line below.
See docs/features/verification-marker-gate.md, section 3 ("hooks/test-marker-guard.sh -- the
gate") for the full node-by-node contract this file implements, and "Which paths, and which
content" for the collection/pairing rules.

Exit codes, and they are the whole contract with bash:
  0   a TSV line was printed -- bash trusts stdout, not this code, for the verdict
  3   the payload on stdin could not be read (reserved -- and ONLY for this)
  any other non-zero, or 0 with nothing on stdout: bash treats as MSG_CLASSIFIER_FAILED

Wire line: OUTCOME<TAB>DOOR<TAB>DETAIL<TAB>PAIR, exactly four fields, none ever empty -- a
door/detail/pair that has nothing to say prints the literal "-", never "". See "The wire is one
tab-separated line" in the spec for why: a TAB is IFS whitespace, so a genuinely empty field
collapses under `read` and everything after it shifts left.
"""

import importlib.util
import json
import os
import re
import subprocess
import sys

_HERE = os.path.dirname(os.path.realpath(__file__))


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Uncaught on purpose: a missing or broken classify-commit-command.py must surface as a non-zero
# exit with no TSV line, which bash's own rc/output check already turns into
# MSG_CLASSIFIER_FAILED -- see the door table's row 5 ("including a failed import of the
# classifier module, which node CM cannot see").
_CLASSIFIER = _load("classify_commit_command", "classify-commit-command.py")
classify = _CLASSIFIER.classify

EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

# 1-200 bytes, every byte 0x20-0x7E. A `bytes` pattern checked with fullmatch, not `$` -- Python's
# `$` also matches just before a single trailing newline, which would silently admit a 201-byte
# reason ending in one. See the spec's "Validating the exemption in Python" for the measured
# wrong spellings this is not.
_EXEMPT_RE = re.compile(rb"^[ -~]{1,200}$")

# Message-only trigger detection for MSG_UNSUPPORTED_FORM's field 3. classify()'s own
# Classification carries no trigger -- its six-field contract is frozen in the spec -- so this
# re-derives WHY form came back UNSUPPORTED using the same exported building blocks
# classify-commit-command.py is itself built from (segments, resolve_subcommand,
# COMMIT_VALUE_FLAGS), the way hooks/git-guard.sh's own prints_and_exits_option() already does
# for its own message-only need. It never changes the block/allow decision -- classify() already
# made that -- only which of the four trigger names gets reported.
_INCLUDE_FLAGS = {"-i", "--include", "--pathspec-from-file"}
_PATCH_FLAGS = {"-p", "--patch", "--interactive"}


def _unsupported_trigger(command):
    cd_seen = False
    for _assigns, argv in _CLASSIFIER.segments(command):
        if not argv:
            continue
        if argv[0] == "cd":
            cd_seen = True
            continue
        if _CLASSIFIER.program(argv[0]) != "git" or len(argv) < 2:
            continue
        subcommand, rest, blocking_option = _CLASSIFIER.resolve_subcommand(argv)
        if blocking_option is not None:
            return "FOREIGN_REPO"
        if subcommand != "commit":
            continue
        if cd_seen:
            return "FOREIGN_REPO"
        i, n = 0, len(rest)
        while i < n:
            tok = rest[i]
            if tok == "--" or not tok.startswith("-"):
                i += 1
                continue
            name, has_eq, _value = tok.partition("=")
            if name in _INCLUDE_FLAGS:
                return "INCLUDE_OR_FROM_FILE"
            if name in _PATCH_FLAGS:
                return "PATCH_OR_INTERACTIVE"
            if name in _CLASSIFIER.COMMIT_VALUE_FLAGS and not has_eq:
                i += 1
            i += 1
        return "OFF_WHITELIST"
    return "OFF_WHITELIST"


def _valid_exempt(value):
    return _EXEMPT_RE.fullmatch(value.encode("utf-8", errors="surrogateescape")) is not None


def _git(args, cwd):
    return subprocess.run(
        ["git"] + args, cwd=cwd, capture_output=True, text=True, errors="replace"
    )


def _resolve_toplevel(cwd):
    proc = _git(["rev-parse", "--show-toplevel"], cwd)
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def _resolve_base(toplevel, amend):
    ref = "HEAD^" if amend else "HEAD"
    proc = _git(["rev-parse", "--verify", ref], toplevel)
    if proc.returncode != 0:
        return EMPTY_TREE
    return proc.stdout.strip()


class _GitFailure(Exception):
    """An unexpected non-zero exit from a git call this module does not treat as a defined
    answer -- see "Every git invocation is status-checked" in the spec for the four exceptions."""


def _collect_path_set(toplevel, base, form, paths):
    if form == "PLAIN":
        args = ["diff", "--cached", "--name-only", "--diff-filter=d", base]
    elif form == "PATHSPEC":
        args = ["diff", "--name-only", "--diff-filter=d", base, "--"] + paths
    elif form == "ALL":
        args = ["diff", "--name-only", "--diff-filter=d", base]
    else:
        # No default-allow arm (§3): by this call site UNSUPPORTED/INVALID/NONE are already
        # handled and returned above, so only PLAIN/PATHSPEC/ALL are legal here. Anything
        # else -- including None from a half-upgraded classifier -- raises, uncaught, so it
        # surfaces as MSG_CLASSIFIER_FAILED rather than silently collecting as ALL.
        raise RuntimeError("unrecognised form for a COMMIT: {!r}".format(form))
    proc = _git(args, toplevel)
    if proc.returncode != 0:
        raise _GitFailure()
    return [line for line in proc.stdout.split("\n") if line]


def _classify_role(path):
    """Step 1 of pair formation: role and derived sibling, ordered so `.test.sh` never falls
    through to the plain `.sh` arm. Returns (None, None) for a path that forms no pair."""
    if path.endswith(".test.sh"):
        return "test", path[: -len(".test.sh")] + ".sh"
    if path.endswith(".test.py"):
        return "test", path[: -len(".test.py")] + ".py"
    if path.endswith(".sh"):
        return "subject", path[: -len(".sh")] + ".test.sh"
    if path.endswith(".py"):
        return "subject", path[: -len(".py")] + ".test.py"
    return None, None


def _tracked(toplevel, path):
    proc = _git(["ls-files", "--error-unmatch", "--", path], toplevel)
    return proc.returncode == 0


def _form_pairs(toplevel, path_set):
    """Step 2 (asymmetric existence) and step 3 (the pair set is a SET) of pair formation."""
    pairs = set()
    for path in path_set:
        role, sibling = _classify_role(path)
        if role is None:
            continue
        if role == "subject":
            subject, test = path, sibling
            on_disk = os.path.exists(os.path.join(toplevel, test))
            if not (_tracked(toplevel, test) or on_disk):
                continue  # no sibling test at all -- never gated, per Scope
        else:
            test, subject = path, sibling
            if not _tracked(toplevel, subject):
                continue  # the three orphan suites land here
        pairs.add((subject, test))
    return sorted(pairs)


def _absent_and_blob(toplevel, path, in_set, form, base):
    """(is_absent, blob_sha) for one pair member, per "Which paths, and which content"."""
    if form == "PLAIN":
        proc = _git(["ls-files", "--stage", "--", path], toplevel)
        line = proc.stdout.strip()
        if not line:
            return True, None
        return False, line.split()[1]

    if form == "PATHSPEC" and in_set:
        if not os.path.exists(os.path.join(toplevel, path)):
            return True, None
        proc = _git(["hash-object", "--", path], toplevel)
        if proc.returncode != 0:
            raise _GitFailure()
        return False, proc.stdout.strip()

    if form == "ALL" and in_set:
        # --diff-filter=d already excludes deletions from the path set, so every path this
        # collector returned exists on disk -- no ABSENT case needed here (spec: "a member IN
        # the path set needs no ABSENT case at all").
        proc = _git(["hash-object", "--", path], toplevel)
        if proc.returncode != 0:
            raise _GitFailure()
        return False, proc.stdout.strip()

    # <base> blob: PATHSPEC-outside (cat-file -e alone) or ALL-outside (cat-file -e OR disk-miss)
    exists = _git(["cat-file", "-e", "{}:{}".format(base, path)], toplevel)
    absent = exists.returncode != 0
    if form == "ALL" and not absent:
        absent = not os.path.exists(os.path.join(toplevel, path))
    if absent:
        return True, None
    proc = _git(["rev-parse", "{}:{}".format(base, path)], toplevel)
    if proc.returncode != 0:
        raise _GitFailure()
    return False, proc.stdout.strip()


_BLOB_RE = re.compile(r"^([0-9a-f]{40}|[0-9a-f]{64})$")


def _read_marker(toplevel, subject, test):
    """None (no marker), "BAD" (unreadable or invalid), or {"subject": sha, "test": sha}."""
    key = subject.replace("%", "%25").replace("/", "%2F")
    path = os.path.join(toplevel, "hooks", "state", "test-markers", key)
    try:
        with open(path, "rb") as handle:
            raw = handle.read()
    except OSError:
        return None
    text = raw.decode("utf-8", errors="replace")
    try:
        data = json.loads(text)
    except ValueError:
        return "BAD"
    if not isinstance(data, dict) or data.get("version") != 1:
        return "BAD"
    subj, tst = data.get("subject"), data.get("test")
    if not isinstance(subj, dict) or not isinstance(tst, dict):
        return "BAD"
    if subj.get("path") != subject or tst.get("path") != test:
        return "BAD"
    subject_blob, test_blob = subj.get("blob"), tst.get("blob")
    if not isinstance(subject_blob, str) or not _BLOB_RE.match(subject_blob):
        return "BAD"
    if not isinstance(test_blob, str) or not _BLOB_RE.match(test_blob):
        return "BAD"
    return {"subject": subject_blob, "test": test_blob}


def _remedy(test_path):
    interpreter = "bash" if test_path.endswith(".sh") else "python3"
    return "{} {}".format(interpreter, test_path)


def _emit(outcome, door="-", detail="-", pair="-"):
    sys.stdout.write("{}\t{}\t{}\t{}\n".format(outcome, door, detail, pair))


def _decide(payload):
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        # Unreachable in practice -- bash already required a string cwd before invoking this
        # call (node RC) -- but this call re-reads the same payload independently, so it is
        # answered the same way rather than assumed away.
        _emit("ALLOW")
        return

    tool_name = payload.get("tool_name")
    if not isinstance(tool_name, str):
        tool_name = ""
    tool_input = payload.get("tool_input")
    command = ""
    if isinstance(tool_input, dict):
        value = tool_input.get("command")
        if isinstance(value, str):
            command = value

    result = classify(tool_name, command)

    if result.kind == "NOTHING_RUNNABLE":
        if result.tool == "Bash":
            _emit("BLOCK", "MSG_NOTHING_RUNNABLE")
        else:
            _emit("ALLOW")
        return
    if result.kind == "OTHER":
        _emit("ALLOW")
        return
    if result.kind != "COMMIT":
        # No default-allow arm (§3): kind is a closed domain (COMMIT | OTHER |
        # NOTHING_RUNNABLE), both handled above. Anything else means the classifier is
        # answering outside its own contract -- raise, uncaught, so this surfaces as
        # MSG_CLASSIFIER_FAILED rather than silently allowing the commit.
        raise RuntimeError("classifier returned an unrecognised kind: {!r}".format(result.kind))

    # Node H -- checked before node I, so a non-commit carrying a stray TEST_EXEMPT can never
    # reach this validation at all (see the classify() dispatch above).
    if result.exempt:
        if not _valid_exempt(result.exempt):
            _emit("BLOCK", "MSG_BAD_EXEMPT")
        else:
            _emit("EXEMPT", detail=result.exempt)
        return

    if result.form == "UNSUPPORTED":
        _emit("BLOCK", "MSG_UNSUPPORTED_FORM", _unsupported_trigger(command))
        return
    if result.form == "INVALID":
        # Git itself refuses this (exit 128, nothing committed) -- nothing downstream matters.
        _emit("ALLOW")
        return

    toplevel = _resolve_toplevel(cwd)
    if toplevel is None:
        # "No repo here" is node F's answer, already settled by bash before this call ran.
        _emit("ALLOW")
        return

    base = _resolve_base(toplevel, result.amend)

    try:
        path_set = _collect_path_set(toplevel, base, result.form, result.paths)
    except _GitFailure:
        _emit("BLOCK", "MSG_GIT_FAILED")
        return

    pairs = _form_pairs(toplevel, path_set)
    if not pairs:
        _emit("ALLOW")
        return

    path_set_set = set(path_set)
    for subject, test in pairs:
        pair_field = "{}|{}".format(subject, test)
        marker = _read_marker(toplevel, subject, test)
        if marker is None:
            _emit("BLOCK", "MSG_NO_MARKER", _remedy(test), pair_field)
            return
        if marker == "BAD":
            _emit("BLOCK", "MSG_BAD_MARKER", pair=pair_field)
            return
        try:
            # Test checked before subject: when a pair goes wrong on both sides at once (e.g.
            # the test half is deleted while the subject half is also mid-edit), the receipt's
            # weaker claim is that the SUBJECT was verified, and that claim rests on the test
            # actually being there to have run it -- so an absent/stale test is reported first.
            test_absent, test_blob = _absent_and_blob(
                toplevel, test, test in path_set_set, result.form, base
            )
            subject_absent, subject_blob = _absent_and_blob(
                toplevel, subject, subject in path_set_set, result.form, base
            )
        except _GitFailure:
            _emit("BLOCK", "MSG_GIT_FAILED")
            return
        if test_absent or test_blob != marker["test"]:
            _emit("BLOCK", "MSG_STALE_TEST", pair=pair_field)
            return
        if subject_absent or subject_blob != marker["subject"]:
            _emit("BLOCK", "MSG_STALE_SUBJECT", pair=pair_field)
            return

    _emit("ALLOW")


def main():
    raw = sys.stdin.buffer.read()
    text = raw.decode("utf-8", errors="replace")
    try:
        payload = json.loads(text)
    except ValueError:
        sys.exit(3)
    if not isinstance(payload, dict):
        sys.exit(3)
    _decide(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
