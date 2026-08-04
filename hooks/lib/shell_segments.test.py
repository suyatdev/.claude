#!/usr/bin/env python3
"""Unit tests for shell_segments.py. Run: python3 hooks/lib/shell_segments.test.py

Written 2026-08-04 with the redirection fix (queue item 1). Until then this module -- the shared
lexer every guard depends on, and the only file in hooks/lib/ without a test suite -- had none, and
classify-git-command.test.py carried zero redirect cases. That absence is precisely why a redirection
was misread as a command separator for as long as it was: nothing could have caught it.

So this file is not only the fix's red suite. The REGRESSION block below pins behaviour that already
worked, because the fix edits the one loop every caller funnels through.

Deliberately dependency-free (no pytest), matching its siblings: adding a dependency is not a
unilateral call, and this has to run anywhere the hook runs.
"""

import importlib.util
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "shell_segments", os.path.join(_HERE, "shell_segments.py")
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
segments = _MOD.segments


def argvs(src):
    """Non-empty argv lists, which is what every caller actually asks about."""
    return [argv for _, argv in segments(src) if argv]


GIT_COMMIT = ["git", "commit", "-m", "x", "--", "foo.sh"]

# (command, expected non-empty argvs, why)
CASES = [
    # --- THE FIX: redirections are part of a command, not a separator between two ---
    # (a) fail-CLOSED. The stray fd digit became a pathspec and doc-guard denied a real commit.
    ("git commit -m msg -- FILE 2>&1 | tail -3",
     [["git", "commit", "-m", "msg", "--", "FILE"], ["tail", "-3"]],
     "2>&1 must leave no phantom '2' operand and no phantom '1' command"),
    ("git commit -m msg -- FILE 2>/dev/null",
     [["git", "commit", "-m", "msg", "--", "FILE"]],
     "fd digit and target both consumed"),

    # (b) the redirect TARGET must never reach a command position.
    ("git commit -m x -- foo.sh > out.txt", [GIT_COMMIT], "target is not a command"),
    ("git commit -m x -- foo.sh >>log", [GIT_COMMIT[:]], "append form"),
    ("cat <in.txt", [["cat"]], "input redirect"),
    ("git commit -m x -- foo.sh &> all.log", [GIT_COMMIT], "&> is a redirect, not a background &"),
    ("git commit -m x -- foo.sh >| clobber", [GIT_COMMIT], ">| is noclobber-override, not a pipe"),
    ("git commit -m x -- foo.sh 2>&1 1<&0", [GIT_COMMIT], "fd-duplicating forms in both directions"),

    # (c) fail-OPEN. A leading or mid-command redirect hid the command from every guard.
    ("> out.txt git commit -m x -- foo.sh", [GIT_COMMIT],
     "leading redirect must not hide the command -- this was a Tier-1 guard bypass"),
    ("git >out.txt commit -m x -- foo.sh", [GIT_COMMIT],
     "mid-command redirect must not truncate argv to ['git']"),
    ("2>err git commit -m x -- foo.sh", [GIT_COMMIT], "leading redirect with an fd digit"),

    # Control operators must STILL split. This is the half the fix must not break.
    ("git add -- a.sh && git commit -m x -- a.sh",
     [["git", "add", "--", "a.sh"], ["git", "commit", "-m", "x", "--", "a.sh"]], "&& still splits"),
    ("git log |& tail", [["git", "log"], ["tail"]],
     "|& is pipe-with-stderr: no < or >, so it stays a splitter"),
    ("git log | tail", [["git", "log"], ["tail"]], "plain pipe"),
    ("git add -- a.sh; git commit -m x -- a.sh",
     [["git", "add", "--", "a.sh"], ["git", "commit", "-m", "x", "--", "a.sh"]], "; still splits"),

    # PROCESS SUBSTITUTION. `<(` and `>(` contain < / > but OPEN A COMMAND CONTEXT, so they must
    # split like `(` does. The first revision of this fix classified them as redirections and ate the
    # substituted command's NAME -- a fail-open in a new shape, found by the observability judge and
    # NOT by this suite, which had no case for it. These are the cases that absence cost.
    ("cat <(gh pr create)", [["cat"], ["gh", "pr", "create"]],
     "<( must not eat 'gh' -- the command inside really runs"),
    ("echo hi > >(git commit -m x -- src/app.js)",
     [["echo", "hi"], ["git", "commit", "-m", "x", "--", "src/app.js"]],
     ">( as a redirect TARGET still opens a command context; argv[0] must not stay 'echo'"),
    ("diff <(git show a) <(git show b)",
     [["diff"], ["git", "show", "a"], ["git", "show", "b"]], "two substitutions in one command"),
    ("git commit -m x -- foo.sh > out.txt", [GIT_COMMIT], "a plain word target is still consumed"),

    # Composition with the wrapper stripping the module already did.
    ("rtk git commit -m x -- a.sh 2>/dev/null",
     [["git", "commit", "-m", "x", "--", "a.sh"]], "wrapper strip and redirect strip compose"),

    # The one plausible regression: a heredoc body must not leak into the command's argv. It does
    # not, because the \n -> ; translation already isolates each body line into its own segment.
    # Asserted on the FIRST segment only; the body lines are noise segments, as they were before.
    ("git commit -q -F - -- CODING_MEMORY.md <<'MSG'\ndocs: subject\nMSG\n",
     None,  # handled by a dedicated check below
     "heredoc delimiter consumed, body does not join argv"),

    # Quoted redirect characters are text, not syntax.
    ("git commit -m 'a > b' -- a.sh",
     [["git", "commit", "-m", "a > b", "--", "a.sh"]], "a quoted '>' must not be read as a redirect"),
    ('git commit -m "2>&1 in the subject" -- a.sh',
     [["git", "commit", "-m", "2>&1 in the subject", "--", "a.sh"]], "quoted fd syntax is prose"),

    # --- REGRESSION: behaviour that already worked and the fix must preserve ---
    ("git push && gh pr create", [["git", "push"], ["gh", "pr", "create"]], "chained &&"),
    ("git push&&gh pr create", [["git", "push"], ["gh", "pr", "create"]], "unspaced &&"),
    ("git push || gh pr create", [["git", "push"], ["gh", "pr", "create"]], "chained ||"),
    ("( gh pr create )", [["gh", "pr", "create"]], "subshell"),
    ("{ gh pr create; }", [["gh", "pr", "create"]], "brace group"),
    ("git push\ngh pr create", [["git", "push"], ["gh", "pr", "create"]], "newline ends a command"),
    ("git push && \\\ngh pr create", [["git", "push"], ["gh", "pr", "create"]],
     "backslash-newline is a CONTINUATION, not a separator"),
    ("time rtk gh pr create", [["gh", "pr", "create"]], "wrappers stack, so stripping loops"),
    ("git status", [["git", "status"]], "the ordinary case still works"),
]


def check_assignments():
    """VAR=value prefixes still parse, and survive a redirect on the same command."""
    out = []
    got = segments("FOO=bar git commit -m x -- a.sh")
    want = [({"FOO": "bar"}, ["git", "commit", "-m", "x", "--", "a.sh"])]
    if got != want:
        out.append("FAIL — assignment prefix\n       want {!r}\n       got  {!r}".format(want, got))

    got = segments("FOO=bar git commit -m x -- a.sh 2>/dev/null")
    want = [({"FOO": "bar"}, ["git", "commit", "-m", "x", "--", "a.sh"])]
    if got != want:
        out.append("FAIL — assignment + redirect\n       want {!r}\n       got  {!r}".format(want, got))
    return out


def check_unparseable():
    """Unparseable input still fails OPEN with [] -- a deliberate choice, not a bug."""
    got = segments('git commit -m "unterminated')
    if got != []:
        return ["FAIL — unparseable input should fail open with []\n       got {!r}".format(got)]
    return []


def check_heredoc():
    src = "git commit -q -F - -- CODING_MEMORY.md <<'MSG'\ndocs: subject\nMSG\n"
    want = ["git", "commit", "-q", "-F", "-", "--", "CODING_MEMORY.md"]
    got = argvs(src)
    if not got or got[0] != want:
        return ["FAIL — heredoc body leaked into argv\n       want first {!r}\n       got  {!r}".format(
            want, got)]
    return []


def check_accepted_limit():
    """ANY trailing bare digit before a redirect is dropped. Stated, not discovered.

    shlex discards spacing, so `cmd 2>x` and `cmd 2 >x` are indistinguishable. Dropping is still the
    right direction -- it beats INVENTING the operand in the common 2>&1 form -- but this note has
    been written too narrowly twice, so both corrections are recorded here rather than re-derived.

    (1) The COST was undersold: "a bare digit can never be argv[0], so command recognition is
        unaffected" is true of argv[0] and beside the point. git-guard's docs-only exemption is
        decided from the PATHSPEC, so losing a path flips deny -> allow.
    (2) The WIDTH was undersold: it is not "a file literally named 2". It is any trailing bare digit,
        including an option value -- `git log -n 5 > out` loses the `5`.

    Both are pinned below. The pathspec case is the one guard-visible flip, and it is checked at
    guard level by hooks/shell-segments-falsifier.sh:
      `git commit -m x -- docs/foo.md 2 > out` on main -- old BLOCKS (the file `2` is not
      documentation), new ALLOWS. Accepted as the lesser error against a false denial on the routine
      `2>&1` idiom, but it is a fail-OPEN on a Tier-1 guard and is recorded as one -- see ADR 0015.

    The other side of the trade is pinned by the CASES row `git commit -m x -- foo.sh > out.txt`:
    an ordinary filename before a redirect must NOT be dropped. Both must hold, or the limit has
    moved and the spec, ADR 0015 and this test are updated together.
    """
    problems = []

    got = argvs("git commit -m x -- 2 > out")
    if got != [["git", "commit", "-m", "x", "--"]]:
        problems.append(
            "ACCEPTED-LIMIT CHANGED — a bare digit as the pathspec before a redirect\n"
            "       got {!r}\n       If this now keeps the '2', the limit is gone: update "
            "the spec, ADR 0015 and this test together.".format(got))

    # The same rule, away from the pathspec: proves the drop is not pathspec-specific.
    got = argvs("git log -n 5 > out")
    if got != [["git", "log", "-n"]]:
        problems.append(
            "ACCEPTED-LIMIT WIDTH CHANGED — a bare digit as an option value before a redirect\n"
            "       got {!r}\n       The limit is 'any trailing bare digit', not 'a file named 2'. "
            "If this now keeps the '5', update the spec, ADR 0015 and this test together.".format(got))

    return problems


def main():
    passed = failed = 0
    problems = []

    for cmd, want, why in CASES:
        if want is None:
            continue  # heredoc: asserted in check_heredoc()
        got = argvs(cmd)
        if got == want:
            passed += 1
        else:
            failed += 1
            problems.append("FAIL — {!r} ({})\n       want {!r}\n       got  {!r}".format(
                cmd, why, want, got))

    for extra in (check_heredoc, check_assignments, check_unparseable, check_accepted_limit):
        msgs = extra()
        if msgs:
            failed += len(msgs)
            problems.extend(msgs)
        else:
            passed += 1

    for p in problems:
        print(p)
    print("\nshell_segments unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
