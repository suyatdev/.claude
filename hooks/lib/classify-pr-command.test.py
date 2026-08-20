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
import subprocess
import sys

MARKER_SELF = os.path.abspath(__file__)
# cwd=dirname(MARKER_SELF), never the inherited process cwd: this file is also run as a nested
# subprocess by judge-guard.test.sh from inside a throwaway repo, where the ambient cwd resolves
# to that fixture's toplevel, not this one's.
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(MARKER_SELF),
                             capture_output=True, text=True, check=True).stdout.strip()

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
    # Adjacency is what separates this classifier from a substring match, and it was the one
    # load-bearing property no case pinned: a mutation dropping the requirement that `create`
    # immediately follow `pr` left the suite fully green while this command started blocking.
    ("gh pr list --search create", "NO", "", "create as a flag value, not adjacent to pr"),
    # The exemption name is matched exactly, never by suffix. A suffix match would hand every
    # *_EXEMPT variable in the repo the power to wave a PR past the gate -- MERGE_EXEMPT is a real
    # one, belonging to merge-guard.sh, and would silently become a judge bypass. Mutating the
    # equality check to endswith("EXEMPT") escaped every other case in this file.
    ("MERGE_EXEMPT=x gh pr create", "PR", "", "another guard's exemption is not this guard's"),
    ("gh pr view 12 --json title --jq .title create", "NO", "", "create trailing as an argument"),
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


# --- generalised: subcommand and exempt_var are now parameters (task 5), defaulting to
# --- ("pr", "create") / "JUDGE_EXEMPT" -- every case above calls classify(cmd) with no
# --- extra args, so it exercises exactly those defaults and is proof the generalisation
# --- changed nothing for the existing caller. These cases exercise the PARAMETERS
# --- themselves: merge-guard.sh (task 6) is the second caller, passing
# --- subcommand=("pr", "merge"), exempt_var="MERGE_EXEMPT". The lexer (segments()) is
# --- untouched and already proven above for chaining/quoting/wrappers against "pr create" --
# --- re-proving every one of those shapes against "pr merge" would be redundant, since
# --- adjacency-matching happens after lexing and does not care which pair it is comparing.
# --- (command, subcommand, exempt_var, expected_kind, expected_exempt, why)
PAIR_CASES = [
    ("gh pr merge 5", ("pr", "merge"), "MERGE_EXEMPT", "PR", "", "the new pair matches"),
    ("gh pr merge 5", ("pr", "create"), "JUDGE_EXEMPT", "NO", "",
     "the SAME command does not match the default pair -- proves the parameter is live"),
    ("gh pr create", ("pr", "merge"), "MERGE_EXEMPT", "NO", "",
     "and the converse: the default-pair command does not match the new one"),
    ("gh -R o/r pr merge 5", ("pr", "merge"), "MERGE_EXEMPT", "PR", "",
     "a global flag before the subcommand is still valid gh, same as pr create"),
    ("echo hi && gh pr merge 5", ("pr", "merge"), "MERGE_EXEMPT", "PR", "",
     "chaining still works -- the lexer is unchanged"),
    ("MERGE_EXEMPT=intentional gh pr merge 5", ("pr", "merge"), "MERGE_EXEMPT",
     "PR", "intentional", "the new exempt_var is read from its own segment"),
    ("JUDGE_EXEMPT=x gh pr merge 5", ("pr", "merge"), "MERGE_EXEMPT", "PR", "",
     "the OTHER guard's exemption variable must not leak in -- asking for MERGE_EXEMPT "
     "must not see a JUDGE_EXEMPT prefix, the same isolation the default direction already had"),
    ("gh pr view 12", ("pr", "merge"), "MERGE_EXEMPT", "NO", "", "different subcommand, still NO"),
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
    for cmd, subcommand, exempt_var, want_kind, want_exempt, why in PAIR_CASES:
        got_kind, got_exempt = classify(cmd, subcommand=subcommand, exempt_var=exempt_var)
        if (got_kind, got_exempt) == (want_kind, want_exempt):
            passed += 1
        else:
            failed += 1
            print("FAIL — {!r} subcommand={!r} exempt_var={!r} ({})\n"
                  "       want ({!r}, {!r}), got ({!r}, {!r})".format(
                      cmd, subcommand, exempt_var, why, want_kind, want_exempt, got_kind, got_exempt))
    print("\nclassifier unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
