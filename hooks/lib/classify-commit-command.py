#!/usr/bin/env python3
"""Classify a raw Bash command string as a `git commit` invocation, in the detail the
verification-marker gate needs: which of the five commit forms it is, whether it amends,
which paths (if any) it names, and any TEST_EXEMPT reason riding along.

Imported by hooks/lib/decide-commit-gate.py, never executed directly -- there is no argv,
no stdin, no process exit here. See docs/features/verification-marker-gate.md, section
"The command grammar" and "hooks/test-marker-guard.sh -- the gate".

Declares no option table of its own: `segments` and `WRAPPERS` come from shell_segments.py;
`resolve_subcommand`, `commit_scan`, `COMMIT_VALUE_FLAGS`, `COMMIT_SAFE_FLAGS`,
`GLOBAL_SKIP_NO_VALUE`, `GLOBAL_SKIP_CONSUMING` and `GLOBAL_REDIRECT` come from
classify-git-command.py, loaded the same way hooks/git-guard.sh already loads that module
(a hyphen in the filename forbids a plain `import`).

Deliberately does NOT call classify-git-command.classify(): that function's fact set is
lossy by design for a block/allow guard and collapses PATHSPEC, ALL and UNSUPPORTED into
one COMMIT_BARE_ARGS bucket -- precisely the distinction this module exists to make. It
also cannot see a bare pathspec operand with no `--` (G2: commit_scan() at
classify-git-command.py:198 treats it as "cannot tell" rather than as an operand), so this
module's own token walk implements rule 3 directly instead of delegating to commit_scan()
for that part. resolve_subcommand() IS reused as-is, and commit_scan is imported so a
caller that legitimately wants the shared, more conservative reading (decide-commit-gate.py
may, for the parts of "which paths, and which content" that are its own concern) can reach
it from one place instead of loading classify-git-command.py a second time.
"""

import os
import re
import sys
from collections import namedtuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shell_segments import WRAPPERS, segments  # noqa: E402  (path must be set first)

import importlib.util  # noqa: E402

_HERE = os.path.dirname(os.path.abspath(__file__))
_GIT_SPEC = importlib.util.spec_from_file_location(
    "classify_git_command", os.path.join(_HERE, "classify-git-command.py")
)
_GIT_MOD = importlib.util.module_from_spec(_GIT_SPEC)
_GIT_SPEC.loader.exec_module(_GIT_MOD)

resolve_subcommand = _GIT_MOD.resolve_subcommand
commit_scan = _GIT_MOD.commit_scan
COMMIT_VALUE_FLAGS = _GIT_MOD.COMMIT_VALUE_FLAGS
COMMIT_SAFE_FLAGS = _GIT_MOD.COMMIT_SAFE_FLAGS
GLOBAL_SKIP_NO_VALUE = _GIT_MOD.GLOBAL_SKIP_NO_VALUE
GLOBAL_SKIP_CONSUMING = _GIT_MOD.GLOBAL_SKIP_CONSUMING
GLOBAL_REDIRECT = _GIT_MOD.GLOBAL_REDIRECT

__all__ = [
    "classify", "Classification", "WRAPPERS", "resolve_subcommand", "commit_scan",
    "COMMIT_VALUE_FLAGS", "COMMIT_SAFE_FLAGS", "GLOBAL_SKIP_NO_VALUE",
    "GLOBAL_SKIP_CONSUMING", "GLOBAL_REDIRECT",
]

Classification = namedtuple("Classification", ["tool", "kind", "form", "amend", "paths", "exempt"])

# -o/--only is PATHSPEC-equivalent, resolved LOCALLY -- opposite of the shared tables, which
# treat it as unrecognised (two tests there pin that as deliberate). See the spec's warning
# callout in "The command grammar": adding it to the shared tables flips a Tier-1 guard
# elsewhere, so it is resolved here and nowhere else.
_LOCAL_PATHSPEC_EQUIVALENT = ("-o", "--only")

# -i/--include and --pathspec-from-file (commits more than the pathspec names); -p/--patch
# and --interactive (select content after this hook has already returned). Neither pair is
# on the shared safe/value tables, so the shared layer already refuses them as unrecognised;
# named here explicitly so this classifier's UNSUPPORTED trigger is not an accident of that
# refusal but a decision this module states for itself.
_LOCAL_UNSUPPORTED = ("-i", "--include", "--pathspec-from-file", "-p", "--patch", "--interactive")

_SHORT_VALUE = {f for f in COMMIT_VALUE_FLAGS if f.startswith("-") and not f.startswith("--") and f != "-am"}
_LONG_VALUE = {f for f in COMMIT_VALUE_FLAGS if f.startswith("--")}
_SHORT_SAFE = {f for f in COMMIT_SAFE_FLAGS if f.startswith("-") and not f.startswith("--")}
_LONG_SAFE = {f for f in COMMIT_SAFE_FLAGS if f.startswith("--")}

_NOTHING_RUNNABLE_RE = re.compile(r"\A[\s\x00-\x1f\x7f]*\Z")


def _is_nothing_runnable(command):
    if not command:
        return True
    return bool(_NOTHING_RUNNABLE_RE.match(command))


def _expand_bundle(tok):
    """"-amHELLO" -> ["-a", "-m", "HELLO"]; "-am" -> ["-a", "-m"]; "-qam" -> ["-q", "-a", "-m"].

    Rule 1: walk a short-flag bundle left to right; the first flag that takes a value
    consumes the rest of the token if any remains, otherwise the bundle simply ends there
    and the caller's own walk consumes the next real token as that flag's value.
    """
    chars = tok[1:]
    out = []
    i = 0
    while i < len(chars):
        ch = "-" + chars[i]
        if ch in _SHORT_VALUE:
            out.append(ch)
            remainder = chars[i + 1:]
            if remainder:
                out.append(remainder)
            return out
        out.append(ch)
        i += 1
    return out


def _preprocess(rest):
    """Expand every short-option bundle in `rest`; everything else passes through unchanged."""
    out = []
    for tok in rest:
        if not tok.startswith("-") or tok.startswith("--") or tok == "--" or len(tok) <= 2:
            out.append(tok)
            continue
        out.extend(_expand_bundle(tok))
    return out


def _scan_commit_tokens(rest):
    """(seen_all, seen_amend, unsupported, operands) for the tokens after `commit`.

    Rule 3: any token not consumed as a flag or a flag's value is a pathspec operand,
    whether or not a `--` preceded it (G2) -- the one respect in which this walk must NOT
    reuse commit_scan(), which discards a bare operand as "cannot tell" instead.
    """
    processed = _preprocess(rest)
    seen_all = any(tok in ("-a", "--all") for tok in processed)
    seen_amend = "--amend" in processed
    unsupported = False
    operands = []
    saw_dashdash = False
    i = 0
    n = len(processed)
    while i < n:
        tok = processed[i]
        if saw_dashdash:
            operands.append(tok)
            i += 1
            continue
        if tok == "--":
            saw_dashdash = True
            i += 1
            continue
        if not tok.startswith("-"):
            operands.append(tok)
            i += 1
            continue

        name, has_eq, _value = tok.partition("=")
        inline = has_eq == "="

        if name in _LOCAL_UNSUPPORTED:
            unsupported = True
            # --pathspec-from-file is the one local-unsupported flag that takes a value in
            # real git; consume it so it is never misread as a bare operand below.
            if name == "--pathspec-from-file" and not inline:
                i += 1
            i += 1
            continue
        if name in _LOCAL_PATHSPEC_EQUIVALENT:
            i += 1
            continue
        if name in _SHORT_VALUE or name in _LONG_VALUE:
            if not inline:
                i += 1  # consume the next token as this flag's value
            i += 1
            continue
        if name in _SHORT_SAFE or name in _LONG_SAFE:
            i += 1
            continue
        unsupported = True  # off-whitelist: not in either table
        i += 1

    return seen_all, seen_amend, unsupported, operands


def _resolve_form(seen_all, unsupported, operands):
    """Rule 4, first match wins, in the fixed order: INVALID, UNSUPPORTED, ALL, PATHSPEC, PLAIN."""
    if seen_all and operands:
        return "INVALID"
    if unsupported:
        return "UNSUPPORTED"
    if seen_all:
        return "ALL"
    if operands:
        return "PATHSPEC"
    return "PLAIN"


def classify(tool_name, command):
    """Return a Classification for one raw Bash command string.

    kind is total: COMMIT, OTHER, or NOTHING_RUNNABLE (command absent, empty, or only
    whitespace/control characters). form, amend, paths and exempt are always populated per
    the kind x field matrix in the spec -- NONE/False/[]/"" for the non-COMMIT rows, never
    null or omitted.
    """
    if _is_nothing_runnable(command):
        return Classification(tool_name, "NOTHING_RUNNABLE", "NONE", False, [], "")

    segs = segments(command)
    cd_seen = False
    for assigns, argv in segs:
        if not argv:
            continue
        if argv[0] == "cd":
            cd_seen = True
            continue
        if argv[0] != "git" or len(argv) < 2:
            continue

        subcommand, rest, blocking_option = resolve_subcommand(argv)

        if blocking_option is not None:
            # A global option ahead of the subcommand makes the repo -- and so the
            # commit's contents -- unknowable before this call returns (cd, -C,
            # --git-dir, --work-tree and anything unrecognised all land here). Fail
            # closed: treat it as a commit this hook cannot see into, not as "not a
            # commit". See the FOREIGN_REPO trigger in the spec's "What UNSUPPORTED
            # absorbs" section.
            return Classification(
                tool_name, "COMMIT", "UNSUPPORTED", False, [],
                assigns.get("TEST_EXEMPT", ""),
            )
        if subcommand != "commit":
            continue

        seen_all, seen_amend, unsupported, operands = _scan_commit_tokens(rest)
        if cd_seen:
            unsupported = True  # a cd earlier on the line -- the shared layer cannot see this at all

        form = _resolve_form(seen_all, unsupported, operands)
        paths = operands if form == "PATHSPEC" else []
        return Classification(
            tool_name, "COMMIT", form, seen_amend, paths,
            assigns.get("TEST_EXEMPT", ""),
        )

    exempt = ""
    for assigns, argv in segs:
        if argv:
            exempt = assigns.get("TEST_EXEMPT", "")
            break
    return Classification(tool_name, "OTHER", "NONE", False, [], exempt)
