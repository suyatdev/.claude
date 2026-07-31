#!/usr/bin/env python3
"""Unit tests for classify-pr-command.py. Run: python3 hooks/lib/classify-pr-command.test.py

These exist because the classifier used to be an inline shell string, so the only way to probe a
bypass shape was to drive the whole hook and read an exit code. Every shape below was previously
found by ad-hoc measurement -- several of them after a reviewer reported one and a re-measurement
of a *different* string wrongly overturned it. Pinning the shapes here makes that class of mistake
impossible to repeat silently.

Deliberately dependency-free (no pytest): adding a dependency is not a unilateral call, and this
has to run anywhere the hook runs.
"""

import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "classify_pr_command", os.path.join(_HERE, "classify-pr-command.py")
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
classify = _MOD.classify

# (command, expected_kind, expected_exempt, why)
CASES = [
    # --- guarded: these really run gh pr create and must be caught ---
    ("gh pr create", "PR", "", "bare invocation"),
    ("gh pr create --fill", "PR", "", "with flags"),
    ("git push && gh pr create", "PR", "", "chained && -- the shape that let a PR ship unjudged"),
    ("git push&&gh pr create", "PR", "", "unspaced && needs punctuation_chars"),
    ("git push; gh pr create", "PR", "", "chained ;"),
    ("git push || gh pr create", "PR", "", "chained ||"),
    ("foo | gh pr create", "PR", "", "piped"),
    ("git push\ngh pr create", "PR", "", "newline ends a command exactly as ; does"),
    ("git push\n\ngh pr create", "PR", "", "blank line between"),
    ("git push && \\\ngh pr create", "PR", "", "backslash-newline is a CONTINUATION, not a separator"),
    ("$(gh pr create)", "PR", "", "unquoted command substitution really runs"),
    ("( gh pr create )", "PR", "", "subshell"),
    ("{ gh pr create; }", "PR", "", "brace group -- { is not a shlex punctuation char by default"),
    ("{ git push; gh pr create; }", "PR", "", "NOT the same string as the line above; both pinned"),
    ("gh -R owner/repo pr create", "PR", "", "global flag before the subcommand is valid gh"),
    ("gh --repo owner/repo pr create", "PR", "", "long form"),
    ("rtk gh pr create", "PR", "", "repo token-proxy wrapper"),
    ("time gh pr create", "PR", "", "keyword prefix takes the command slot"),
    ("eval gh pr create", "PR", "", "unquoted eval"),
    ("time rtk gh pr create", "PR", "", "wrappers stack, so stripping loops"),

    # --- ignored: the phrase appears but nothing runs it. False positives block real work,
    # --- which is worse than a rare miss for a momentum guardrail, so these are load-bearing.
    ("git status", "NO", "", "unrelated"),
    ("gh pr list", "NO", "", "different subcommand"),
    ("gh -R owner/repo pr list", "NO", "", "flags do not make list into create"),
    ("mytool pr create", "NO", "", "pr create without gh at the command position"),
    ("echo gh pr create", "NO", "", "argument, not a command"),
    ('git commit -m "feat: blocking gh pr create without a verdict"', "NO", "", "commit message"),
    ('git commit -m "feat: guard\n\ngh pr create must block"', "NO", "",
     "multi-line quoted message survives the newline translation as one token"),
    ('git commit -m "see \\\ngh pr create"', "NO", "", "quoted continuation stays quoted"),
    ('git commit -m "run `gh pr create` first"', "NO", "", "backtick inside a quoted message"),
    ("gh", "NO", "", "bare gh"),
    ("gh pr", "NO", "", "no create"),
    ("", "NO", "", "empty input"),
    ("   ", "NO", "", "whitespace only"),
    ("unbalanced ' quote gh pr create", "NO", "", "unparseable -> fail OPEN, by design"),

    # --- accepted-open shapes. These DO run gh pr create and are deliberately not caught.
    # --- Pinned so that closing one is a conscious decision with a failing test, never a drift.
    ('PR_URL="$(gh pr create)"', "NO", "",
     "quoted substitution is ONE token -- the same property that protects commit messages"),
    ('eval "gh pr create"', "NO", "", "quoted eval argument cannot reach a command position"),
    ("echo `gh pr create`", "NO", "",
     "backticks left open on purpose: translating them made heredoc bodies fail CLOSED"),
    ("env gh pr create", "NO", "", "wrapper list is a denylist; env is not in it"),
    ("timeout 30 gh pr create", "NO", "", "denylist gap"),
    ("for x in 1; do gh pr create; done", "NO", "", "do takes the command slot; loop keywords absent"),
    ("GH=gh; $GH pr create", "NO", "", "variable indirection is invisible to lexing"),

    # --- JUDGE_EXEMPT extraction: binds to its own segment, mirroring bash ---
    ("JUDGE_EXEMPT=hotfix gh pr create", "PR", "hotfix", "bare value"),
    ('JUDGE_EXEMPT="skip, docs only" gh pr create', "PR", "skip, docs only", "quoted multi-word"),
    ("JUDGE_EXEMPT= gh pr create", "PR", "", "empty value must NOT exempt -- hook treats it as absent"),
    ('git push && JUDGE_EXEMPT="docs only" gh pr create', "PR", "docs only", "on the gh segment"),
    ('time JUDGE_EXEMPT="docs only" gh pr create', "PR", "docs only", "after a stripped wrapper"),
    ('FOO="a b" gh pr create', "PR", "", "unrelated quoted-space env prefix must not bypass"),
    # An unquoted newline inside the value is a real command separator, so this lexes as
    # `JUDGE_EXEMPT=a` then `b gh pr create` -- whose command is `b`, not `gh`. bash agrees. Pinned
    # because the first draft of this test asserted PR and the classifier was right, not the test.
    ("JUDGE_EXEMPT=a\nb gh pr create", "NO", "", "newline splits before gh reaches a command slot"),
]


def main():
    passed = failed = 0
    for cmd, want_kind, want_exempt, why in CASES:
        got_kind, got_exempt = classify(cmd)
        if (got_kind, got_exempt) == (want_kind, want_exempt):
            passed += 1
        else:
            failed += 1
            print("FAIL — {!r} ({})\n       want ({!r}, {!r}), got ({!r}, {!r})".format(
                cmd, why, want_kind, want_exempt, got_kind, got_exempt))
    print("\nclassifier unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
