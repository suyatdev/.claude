#!/usr/bin/env python3
"""Unit tests for classify-commit-command.py. Run: python3 hooks/lib/classify-commit-command.test.py

Scoped to only what the shared grammar layer (classify-git-command.py / shell_segments.py) does
NOT already decide -- see docs/features/verification-marker-gate.md, checklist task 2. The
shared suite (classify-git-command.test.py, 114 passed) already covers: rule 0 wrapper
stripping for every WRAPPERS member; `git add ... && git commit ...` segmentation;
`--opt=value` self-containment (G3); a value-taking flag consuming the next token (G5); `--`
inside a value not being a separator (G6); -S/--gpg-sign never eating a pathspec; --amend when
fully spelled; an abbreviated-but-valid option (--am) refusing to fall through to PLAIN; and
`git -C` / `--git-dir` / `--work-tree` as repo-redirect triggers. None of that is re-asserted
here.

Deliberately dependency-free (no pytest), matching classify-git-command.test.py and
classify-pr-command.test.py.
"""

import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "classify_commit_command", os.path.join(_HERE, "classify-commit-command.py")
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
classify = _MOD.classify

PASSED = 0
FAILED = 0


def check(label, got, want):
    global PASSED, FAILED
    if got == want:
        PASSED += 1
    else:
        FAILED += 1
        print("FAIL — {}\n       want {!r}, got {!r}".format(label, want, got))


def form_of(command, tool="Bash"):
    return classify(tool, command).form


def paths_of(command, tool="Bash"):
    return classify(tool, command).paths


def exempt_of(command, tool="Bash"):
    return classify(tool, command).exempt


def kind_of(command, tool="Bash"):
    return classify(tool, command).kind


# =====================================================================================
# (a) Rule 1, bundle decomposition. The shared layer enumerates the literal "-am" only
# (it is one entry in COMMIT_VALUE_FLAGS), so every OTHER bundle spelling currently reads
# as "cannot tell" there. This classifier must decompose all four.
# =====================================================================================

check("'-am msg' resolves to ALL (G1, bundled)", form_of("git commit -am msg"), "ALL")
check("'-amHELLO' resolves to ALL (G4, value attaches to the last flag)",
      form_of("git commit -amHELLO"), "ALL")
check("'-qam msg' resolves to ALL (a harmless flag ahead of the bundle)",
      form_of("git commit -qam msg"), "ALL")
check("'-vam msg' resolves to ALL (same, verbose ahead of the bundle)",
      form_of("git commit -vam msg"), "ALL")

# =====================================================================================
# (b) G2 -- a bare operand is a pathspec, no `--` needed. commit_scan() in the shared
# layer discards it (classify-git-command.py:198); this classifier must not.
# =====================================================================================

check("G2 bare operand resolves to PATHSPEC",
      form_of("git commit -m msg foo.sh"), "PATHSPEC")
check("G2 bare operand is collected verbatim",
      paths_of("git commit -m msg foo.sh"), ["foo.sh"])

# =====================================================================================
# (c) INVALID (G8, G9) resolves before every other block, including before the bundle's
# own ALL trigger and before an UNSUPPORTED trigger fired by the same command.
# =====================================================================================

check("G8: '-a -m msg -- foo.sh' is INVALID",
      form_of("git commit -a -m msg -- foo.sh"), "INVALID")
check("G9: '-am msg -- foo.sh' is INVALID too -- decompose before the -a+operand check",
      form_of("git commit -am msg -- foo.sh"), "INVALID")

# =====================================================================================
# (d) All five `form` values, in the order rule 4 fixes -- including a command that
# fires two (or three) triggers at once, to prove the ORDER is enforced rather than
# merely each value being reachable in isolation.
# =====================================================================================

check("PLAIN is the default, reached only by exhausting the list",
      form_of("git commit -m msg"), "PLAIN")
check("PATHSPEC: any operand", form_of("git commit -m msg -- foo.sh"), "PATHSPEC")
check("ALL: -a with no operand", form_of("git commit -a -m msg"), "ALL")
check("UNSUPPORTED: an off-whitelist trigger",
      form_of("git commit -i -m msg"), "UNSUPPORTED")
check("INVALID: -a with an operand", form_of("git commit -a -m msg -- foo.sh"), "INVALID")
check("double trigger: -a (ALL) + -i (UNSUPPORTED), no operand -- UNSUPPORTED wins (order 2 over 3)",
      form_of("git commit -a -i"), "UNSUPPORTED")
check("triple trigger: -a + -i + an operand -- INVALID wins over both (order 1 over 2 and 3)",
      form_of("git commit -a -i -- foo.sh"), "INVALID")

# =====================================================================================
# (e) Each UNSUPPORTED trigger asserted separately, so a fold can never silently drop
# one. `cd` is not implemented by the shared layer at all; the other four are collapsed
# into one COMMIT_BARE_ARGS bucket there.
# =====================================================================================

check("cd before the commit is a FOREIGN_REPO trigger the shared layer cannot see",
      form_of("cd /other/repo && git commit -m msg"), "UNSUPPORTED")
check("-i triggers UNSUPPORTED", form_of("git commit -i -m msg"), "UNSUPPORTED")
check("--include triggers UNSUPPORTED (long spelling of -i)",
      form_of("git commit --include -m msg"), "UNSUPPORTED")
check("--pathspec-from-file triggers UNSUPPORTED",
      form_of("git commit --pathspec-from-file=list.txt -m msg"), "UNSUPPORTED")
check("-p triggers UNSUPPORTED", form_of("git commit -p"), "UNSUPPORTED")
check("--patch triggers UNSUPPORTED (long spelling of -p)",
      form_of("git commit --patch"), "UNSUPPORTED")
check("--interactive triggers UNSUPPORTED",
      form_of("git commit --interactive"), "UNSUPPORTED")

# =====================================================================================
# (f) -o/--only resolved locally as PATHSPEC-equivalent (G7) -- the opposite of what the
# shared tables say, by user decision; this feature does not touch the shared tables.
# =====================================================================================

check("G7: -o is PATHSPEC-equivalent", form_of("git commit -o -m msg -- foo.sh"), "PATHSPEC")
check("G7: -o's paths are collected", paths_of("git commit -o -m msg -- foo.sh"), ["foo.sh"])
check("--only, long spelling, is PATHSPEC-equivalent too",
      form_of("git commit --only -m msg -- foo.sh"), "PATHSPEC")
check("--only's paths are collected",
      paths_of("git commit --only -m msg -- foo.sh"), ["foo.sh"])

# =====================================================================================
# (g) kind: OTHER vs NOTHING_RUNNABLE. classify-git-command.classify() cannot tell
# `git status` from `echo hello` -- both come back `[]` -- and that ambiguity must not
# leak into this layer: both are ordinary OTHER, distinct from an absent command.
# =====================================================================================

check("'git status' is OTHER, not NOTHING_RUNNABLE", kind_of("git status"), "OTHER")
check("'echo hello' is OTHER, not NOTHING_RUNNABLE", kind_of("echo hello"), "OTHER")
check("an empty command is NOTHING_RUNNABLE", kind_of(""), "NOTHING_RUNNABLE")
check("a whitespace-only command is NOTHING_RUNNABLE", kind_of("   \t  "), "NOTHING_RUNNABLE")
check("a control-character-only command is NOTHING_RUNNABLE",
      kind_of("\x01\x02\n"), "NOTHING_RUNNABLE")
check("an absent (None) command is NOTHING_RUNNABLE", kind_of(None), "NOTHING_RUNNABLE")

# =====================================================================================
# (h) raw `exempt` passthrough, taken from shell_segments.segments()'s assignment map --
# not from classify-git-command.py, which discards it. Matched by exact variable name,
# never by suffix (classify-pr-command.py:63 is the precedent).
# =====================================================================================

check("TEST_EXEMPT reaches a COMMIT classification, raw",
      exempt_of("TEST_EXEMPT=vendored upstream git commit -m msg"), "vendored")
check("TEST_EXEMPT reaches an OTHER classification too -- it lexes fine against non-commits",
      exempt_of("TEST_EXEMPT=x ls"), "x")
check("no TEST_EXEMPT means the empty string, not absence",
      exempt_of("git commit -m msg"), "")
check("an absent command reports no exempt value",
      exempt_of(""), "")
check("a variable that merely ends in _EXEMPT is never matched by suffix",
      exempt_of("SOMETEST_EXEMPT=x git commit -m msg"), "")

# =====================================================================================
# (i) All 15 cells of the `kind` x field totality matrix (5 fields x 3 kinds -- 15, not
# 18: revision 14 deleted the `v` schema sentinel row). One representative command per
# kind, every field checked, `tool` varied across the three to prove it is a verbatim
# passthrough of tool_name rather than a hardcoded "Bash".
# =====================================================================================

_commit = classify("Bash", "TEST_EXEMPT=x git commit --amend -m msg -- foo.sh")
check("COMMIT: tool is tool_name, verbatim", _commit.tool, "Bash")
check("COMMIT: form is one of the five commit forms (PATHSPEC here)", _commit.form, "PATHSPEC")
check("COMMIT: amend reflects --amend", _commit.amend, True)
check("COMMIT: paths holds the pathspec operands", _commit.paths, ["foo.sh"])
check("COMMIT: exempt is the raw TEST_EXEMPT value", _commit.exempt, "x")

_other = classify("Write", "TEST_EXEMPT=y ls")
check("OTHER: tool is tool_name, verbatim", _other.tool, "Write")
check("OTHER: form is NONE", _other.form, "NONE")
check("OTHER: amend is false", _other.amend, False)
check("OTHER: paths is empty", _other.paths, [])
check("OTHER: exempt is still reported -- TEST_EXEMPT=y ls lexes perfectly well", _other.exempt, "y")

_nothing = classify("NotebookEdit", "")
check("NOTHING_RUNNABLE: tool is tool_name, verbatim", _nothing.tool, "NotebookEdit")
check("NOTHING_RUNNABLE: form is NONE", _nothing.form, "NONE")
check("NOTHING_RUNNABLE: amend is false", _nothing.amend, False)
check("NOTHING_RUNNABLE: paths is empty", _nothing.paths, [])
check("NOTHING_RUNNABLE: exempt is the empty string -- there is no command string to parse one out of",
      _nothing.exempt, "")


def main():
    print("\nclassify-commit-command unit: {} passed, {} failed".format(PASSED, FAILED))
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
