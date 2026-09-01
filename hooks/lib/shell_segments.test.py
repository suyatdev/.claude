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
import subprocess
import sys

MARKER_SELF = os.path.abspath(__file__)
# cwd=dirname(MARKER_SELF), never the inherited process cwd -- mirrors classify-pr-command.test.py,
# the sibling this repo's suites nest-invoke from inside a throwaway repo.
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(MARKER_SELF),
                             capture_output=True, text=True, check=True).stdout.strip()

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

    # --- THE FIX: `#` opens a comment only where it begins a WORD, which is bash's own rule ---
    # shlex opens one at an unquoted `#` ANYWHERE in a word, and -- because _lex translates
    # newline -> `;` BEFORE lexing -- then discards to end of INPUT rather than end of line.
    # Two independent infidelities, both fail-OPEN. Every expectation in this block is pinned
    # against real bash and zsh by check_bash_fidelity() below, so it is an execution rather
    # than a reading of the manual.

    # (a) the exploit. Nine characters hid every following segment from all eight Tier-1
    # guards at once -- measured end to end in docs/features/shell-lexer-comment-blindness.md.
    ("echo hi#; git commit -m x -- foo.sh", [["echo", "hi#"], GIT_COMMIT],
     "word-final # is ordinary text in bash -- this was a universal guard bypass"),
    ("echo hi#; gh pr create", [["echo", "hi#"], ["gh", "pr", "create"]],
     "same nine characters against the PR classifier"),
    ("echo hi#&&git push --force", [["echo", "hi#"], ["git", "push", "--force"]],
     "no whitespace anywhere: the operator still splits"),
    ("git add a#b && git commit -m x -- foo.sh", [["git", "add", "a#b"], GIT_COMMIT],
     "# in the middle of a word, mid-command"),

    # (b) the second, separate fail-open: a GENUINE comment must end at the newline. It did
    # not, because by lexing time there were no newlines left to end it.
    ("git add -- a.sh # note\ngit commit -m x -- foo.sh", [["git", "add", "--", "a.sh"], GIT_COMMIT],
     "a real comment ends at end of LINE; the next line's command must still be seen"),

    # (c) the half the fix must not break -- a word-initial comment is still stripped.
    ("git status # a real comment", [["git", "status"]], "comment after whitespace"),
    ("git status ;# no space after the operator", [["git", "status"]],
     "a control operator begins a word too, so # right after `;` IS a comment"),
    ("# leading comment only", [], "a whole-line comment runs nothing"),
    ("git status\t# after a tab", [["git", "status"]], "any unquoted whitespace, not only a space"),

    # (d) the false positives a bare `commenters=\"\"` would introduce. These are ordinary work,
    # and this lexer sits on every Bash call -- a false denial here is expensive, which is the
    # whole reason SECRET_EXEMPT had to be retrofitted to secret-command-guard.sh.
    ("git commit -m fix#123 -- foo.sh", [["git", "commit", "-m", "fix#123", "--", "foo.sh"]],
     "an issue number is not a comment"),
    ("echo '#not a comment'", [["echo", "#not a comment"]], "single-quoted # is text"),
    ('echo "a # b"', [["echo", "a # b"]], "double-quoted # is text"),
    ("echo \\#notcomment", [["echo", "#notcomment"]],
     "a BACKSLASH-escaped # at word start is text -- measured against bash, not assumed"),
    ("echo a\\ # b", [["echo", "a #", "b"]],
     "backslash-escaped whitespace does NOT end the word, so this # is still text"),
    ("echo 'a'#b", [["echo", "a#b"]], "a closing quote does not end the word either"),
    ("curl http://x/#frag", [["curl", "http://x/#frag"]], "a URL fragment"),

    # (e) `)` and `}` are AMBIGUOUS word breaks, and this is measured rather than reasoned:
    # a `)` that closes a SUBSHELL ends the word, so bash comments after it -- but a `)` that
    # closes `$( )` does NOT, and the same split holds for `}` vs `${ }` and for a backtick.
    # Telling the two apart needs expansion tracking the pre-pass deliberately does not do;
    # it excludes the closers instead, which can only ever emit MORE tokens. So the expansion
    # forms are read faithfully and the following command is no longer hidden...
    ("echo $(echo x)#y; git commit -m x -- foo.sh",
     [["echo", "$"], ["echo", "x"], ["#y"], GIT_COMMIT],
     "a ) closing $( ) does not end the word -- the commit after it must still be seen"),
    ("V=q; echo ${V}#y; git commit -m x -- foo.sh",
     [["echo", "${V}#y"], GIT_COMMIT], "same for } closing ${ }"),
    ("echo `echo x`#y; git commit -m x -- foo.sh",
     [["echo", "`echo", "x`#y"], GIT_COMMIT], "same for a closing backtick"),
    # ...and the subshell form is read fail-CLOSED on purpose: bash really does start a comment
    # here and this lexer does not, so a guard sees a command bash would not have run. Pinned
    # from BOTH sides -- here, and as an expected disagreement in check_bash_fidelity().
    ("(echo hi)# git commit -m x -- foo.sh",
     [["echo", "hi"], ["#"] + GIT_COMMIT],
     "ACCEPTED fail-closed deviation: a ) closing a subshell is not treated as a word break"),

    # (f) ANSI-C quoting, `$'...'`, where a backslash escapes a quote WITHOUT closing the
    # string. Neither shlex nor this pre-pass models it, so the quote is read as closing one
    # character early and the whole command becomes unparseable -- segments() then returns []
    # and fails OPEN, the pre-existing behaviour its own docstring documents. Found by the
    # observability judge, then reproduced and scoped by a differential fuzz over 5,216
    # inputs: it is the ONLY shape in that population where this lexer sees fewer commands
    # than the old one, and what it loses is always a harmless `echo` head -- the guarded
    # command after the `;` was invisible to BOTH lexers, so no protection changed hands.
    # Pinned so the fail-open is a recorded limit rather than a surprise.
    ("echo $'a\\'#b'; git commit -m x -- foo.sh", [],
     "$'...' with an escaped quote is unparseable: fail-OPEN, pre-existing, both lexers"),

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


# (command, expected has_grouping, why) -- worktree-location-guard derivation 4.
#
# segments() appends a fresh segment for every control operator and THROWS THE
# OPERATOR AWAY, so `(`, `)`, `{` and `}` are indistinguishable in its return
# value. That distinction is load-bearing and unrecoverable: bash discards a `cd`
# at `)` but keeps it past `}`. This second VIEW of the same token stream is what
# lets a caller notice the ambiguity instead of resolving it wrongly.
GROUPING_CASES = [
    ("( cd /x && git log ) && git switch main", True, "subshell parens"),
    ("{ cd /x; git log; }", True, "brace group -- `{` is not a shlex punctuation char by default"),
    ("( git log )", True, "parens with nothing to carry are still parens"),
    ("cd /x && git switch main", False, "control operators are not grouping operators"),
    ("git commit -m x ; git push", False, "; separates, it does not group"),
    ("git log | grep x", False, "a pipe separates"),
    ("git log > out.txt", False, "a redirection is part of its command"),
    ("git log 2>&1", False, "and so is the fd form, which is why `>&` must not read as grouping"),
    # ONE LEXER, TWO VIEWS. Every row below holds a grouping character inside a
    # QUOTED token, where it is ordinary text. A second parser written to scan the
    # raw string is exactly what would get these wrong.
    ('echo "(a)"', False, "parens inside double quotes are one ordinary token"),
    ("echo '(a)'", False, "and inside single quotes"),
    ('git commit -m "fix(lexer): stop splitting"', False,
     "a Conventional-Commits scope is the routine shape this repo would have broken on"),
    ('echo "{ }"', False, "braces inside quotes"),
    ("git commit -m 'see f(x)'", False, "an unspaced paren inside a quoted message"),
    # Process substitution contains `(` AND opens a command context, so it groups.
    ("cat <(git log)", True, "`<(` opens a command context exactly as `(` does"),
    ("echo hi > >(git log)", True, "the `>(` opener, likewise"),
    ("", False, "empty input"),
    ("   ", False, "whitespace only"),
    ("unbalanced ' quote ( git log )", False,
     "shlex cannot lex this at all. has_grouping reports what it SAW, which is nothing; "
     "the empty return from segments() is the signal callers fail closed on"),
]


def check_has_grouping():
    """Pin has_grouping()'s answers. Absent, this reports one clean failure per row
    rather than exploding at import, so the red run is readable."""
    fn = getattr(_MOD, "has_grouping", None)
    if fn is None:
        return ["has_grouping() DOES NOT EXIST — shell_segments.py exports {!r}".format(
            sorted(n for n in dir(_MOD) if not n.startswith("__")))]
    problems = []
    for src, want, why in GROUPING_CASES:
        got = fn(src)
        if got is not want:
            problems.append("FAIL — has_grouping({!r}) ({})\n       want {!r}, got {!r}".format(
                src, why, want, got))
    return problems


def check_one_lexer():
    """ONE LEXER, TWO VIEWS -- asserted structurally, not by reading the source.

    Replacing _lex must move BOTH views. A has_grouping() carrying its own parser
    would keep answering from the real command string and go unmoved here, which
    is the only failure mode this rule exists to prevent. The card rejects a
    second parser outright, and prose cannot enforce that; this can.
    """
    lex = getattr(_MOD, "_lex", None)
    fn = getattr(_MOD, "has_grouping", None)
    if lex is None or fn is None:
        return ["_lex()/has_grouping() DO NOT BOTH EXIST — got _lex={!r}, has_grouping={!r}".format(
            lex, fn)]

    # Sanity first: _lex is the real token producer, not a stub that happens to exist.
    if lex("a && b") != ["a", "&&", "b"]:
        return ["_lex() IS NOT THE TOKEN PRODUCER — _lex('a && b') = {!r}".format(lex("a && b"))]
    if lex("unbalanced ' quote") is not None:
        return ["_lex() MUST RETURN None FOR UNPARSEABLE INPUT, so segments() can tell that "
                "case apart from an empty command — got {!r}".format(lex("unbalanced ' quote"))]

    original = _MOD._lex
    try:
        _MOD._lex = lambda src: ["(", "cd", "/x"]
        seg_view = _MOD.segments("this string holds no parens")
        grp_view = _MOD.has_grouping("this string holds no parens")
    finally:
        _MOD._lex = original

    problems = []
    if [argv for _, argv in seg_view if argv] != [["cd", "/x"]]:
        problems.append("SECOND PARSER — segments() did not read the substituted _lex; got {!r}".format(
            seg_view))
    if grp_view is not True:
        problems.append(
            "SECOND PARSER — has_grouping() did not read the substituted _lex. It answered {!r} "
            "for a token stream whose first token is '(', which means it lexed the source "
            "string itself. One lexer, two views: a second parser is an automatic reject.".format(
                grp_view))
    return problems


# Anchored OUTSIDE this file: each command is executed by a real shell and the lexer is held to
# what the shell actually did. The CASES block above states bash's rule; this proves the statement.
# `SECOND` is echoed by the half a comment would swallow, so "did SECOND print?" is exactly the
# question every guard is really asking. Every command is a harmless echo -- nothing here may have
# an effect if a shell disagrees with us about where the comment starts.
FIDELITY = [
    "echo hi#; echo SECOND",
    "echo hi ; # echo SECOND",
    "echo hi ;# echo SECOND",
    "echo 'hi#'; echo SECOND",
    'echo "a # b"; echo SECOND',
    "echo \\#notcomment; echo SECOND",
    "echo a\\ # b; echo SECOND",
    "echo 'a'#b; echo SECOND",
    "echo a#b#c; echo SECOND",
    "echo hi >/dev/null # x; echo SECOND",
    "# echo SECOND",
    "echo http://x/#frag; echo SECOND",
    "echo hi\t# echo SECOND",
    "echo $(echo x)#y; echo SECOND",
    "V=q; echo ${V}#y; echo SECOND",
    "echo `echo x`#y; echo SECOND",
]

# The ONE shape where this lexer deliberately disagrees with the shell. A `)` closing a subshell
# really does end the word, so bash starts a comment there -- but distinguishing it from the `)`
# that closes `$( )` needs expansion tracking the pre-pass does not do, so the rule excludes both
# closers. The tokens after the `#` are therefore RETAINED rather than discarded, which is the
# fail-closed direction: this lexer never hides less than bash runs.
#
# What actually reaches a guard is milder, and is measured rather than reasoned: `#` itself takes
# the segment's command position, so classify-git-command reports SEG_OPAQUE and emits no COMMIT
# fact -- git-guard and doc-guard allow, which is what bash's own reading would produce anyway,
# while worktree-guard denies on an opaque segment. So the deviation costs a possible false
# denial on one guard, never a hidden command on any.
#
# Asserted here, not merely absent from FIDELITY, and asserted EXACTLY (the `#` must still be at
# argv[0]) so the deviation cannot widen -- or quietly reverse -- unnoticed.
FIDELITY_DEVIATION = [
    ("(echo hi)# echo SECOND", ["#", "echo", "SECOND"]),
]


def check_bash_fidelity():
    """The lexer must see `echo SECOND` as a command exactly when the shell really runs it.

    bash is REQUIRED -- a missing shell is reported as a failure, never skipped, because a check
    that quietly declines to run is indistinguishable from a passing one. zsh is checked too (it is
    this machine's login shell) and is required for the same reason; if the two shells ever disagree
    the disagreement itself is the finding, so each is asserted separately rather than merged.

    The harness also has to be able to fail in both directions: if no command runs SECOND, or every
    command does, the table discriminates nothing and the whole check is reported broken.
    """
    out = []
    for shell in ("bash", "zsh"):
        ran_true = ran_false = 0
        for cmd in FIDELITY:
            try:
                proc = subprocess.run([shell, "-c", cmd], capture_output=True, text=True, timeout=10)
            except (OSError, subprocess.SubprocessError) as exc:
                out.append("FAIL — {} could not run {!r}: {}".format(shell, cmd, exc))
                continue
            really_ran = "SECOND" in proc.stdout
            ran_true += really_ran
            ran_false += not really_ran
            lexer_sees = ["echo", "SECOND"] in argvs(cmd)
            if lexer_sees != really_ran:
                out.append(
                    "FAIL — {} disagrees with the lexer on {!r}\n"
                    "       shell ran the second command: {}  (stdout {!r})\n"
                    "       lexer saw it as a command:    {}  (argvs {!r})".format(
                        shell, cmd, really_ran, proc.stdout, lexer_sees, argvs(cmd)))
        if not ran_true or not ran_false:
            out.append("FAIL — {} fidelity table discriminates nothing: {} ran, {} did not"
                       .format(shell, ran_true, ran_false))

        for cmd, want_argv in FIDELITY_DEVIATION:
            try:
                proc = subprocess.run([shell, "-c", cmd], capture_output=True, text=True, timeout=10)
            except (OSError, subprocess.SubprocessError) as exc:
                out.append("FAIL — {} could not run {!r}: {}".format(shell, cmd, exc))
                continue
            really_ran = "SECOND" in proc.stdout
            got = argvs(cmd)
            if really_ran or want_argv not in got:
                out.append(
                    "FAIL — {} accepted deviation no longer holds for {!r}\n"
                    "       expected: shell does NOT run it, and the lexer RETAINS {!r}\n"
                    "       got:      shell ran {}, argvs {!r}".format(
                        shell, cmd, want_argv, really_ran, got))
    return out


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

    for extra in (check_heredoc, check_assignments, check_unparseable, check_accepted_limit,
                  check_has_grouping, check_one_lexer, check_bash_fidelity):
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
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
