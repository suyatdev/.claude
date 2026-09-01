#!/usr/bin/env python3
"""Split a raw Bash command string into the segments that actually run a command.

Extracted verbatim from classify-pr-command.py, which needed it to answer "does some
segment really run `gh pr create`?" and is now shared with classify-git-command.py so
git-guard and doc-guard answer the same question about `git commit` / `git push`. One
lexer means one set of accepted limits instead of three regexes drifting apart -- the
guards previously matched a regex anchored to the START of the command, so anything
chained (`git add -- x && git commit -m y`) skipped the guard body entirely.

shlex does the shell quoting a flat regex cannot. Quoted text survives as a single
token, so `git commit` inside a commit message or an echo argument can never sit at a
segment command position and is correctly ignored.
"""

import re
import shlex

# punctuation_chars=True makes shlex emit control operators as standalone tokens even when
# unspaced (`push&&gh` -> `push`, `&&`, `gh`), which a plain whitespace split cannot see.
# Braces are in the set deliberately: a brace group opens a command context exactly as a
# subshell does, but `{` is not one of shlex's punctuation chars, so it lexed as an ordinary
# token and took the segment command position -- `{ gh pr create; }` walked past the guard
# while `( gh pr create )` did not.
OPS = "(){};<>|&"

# The subset of OPS that opens or closes a COMMAND GROUP rather than separating
# two commands. `<(` and `>(` are process substitutions: they contain `(` and open
# a command context exactly as `(` does, which is why _is_redirect already refuses
# to treat them as redirections.
GROUPING = "(){}"


def _is_redirect(tok):
    """True for a punctuation token that redirects rather than separates two commands.

    `<` and `>` are in OPS because shlex must emit them as standalone tokens, but a redirection is
    PART of the command it attaches to and may appear anywhere in it -- including before the command
    name. Treating one as a separator (which this module did until 2026-08-04) produced three
    failures at once: `2>&1` left the fd digit behind as a phantom operand so doc-guard denied real
    commits; the redirect target reached a segment command position; and a LEADING redirect
    (`> out.txt git commit ...`) pushed the real command out of position 0 entirely, so no guard saw
    it. See docs/features/shell-segments-redirects.md.

    Containing `<` or `>` is necessary but NOT sufficient, and the exception is load-bearing.
    PROCESS SUBSTITUTION -- `<(cmd)` and `>(cmd)` -- contains `<`/`>` yet OPENS A COMMAND CONTEXT
    exactly as `(` does. Treating it as a redirection eats the substituted command's NAME along with
    the operator: `cat <(gh pr create)` lexed to ['cat','pr','create'] and
    `echo hi > >(git commit -m x -- src/app.js)` buried a whole commit inside echo's argv, so
    argv[0] was never `git` -- reintroducing, in a new shape, the very fail-open this change was
    written to close. Both are valid executable bash (`bash -n`). Caught by the observability judge
    on the first revision of this fix, not by the test suite, which had no case for it.

    So: a redirection contains `<` or `>` AND no paren. That partitions the set exactly --
    redirections `> >> < << <<< <> >| >& <& &> &>>`; control operators `| || && ; ;; & ( ) { }` plus
    the substitution openers `<(` `>(`, which MUST split so the command inside reaches a segment
    command position. `|&` -- bash's pipe-with-stderr -- contains neither and stays a separator.
    """
    if "(" in tok or ")" in tok:
        return False
    return "<" in tok or ">" in tok

# Words that occupy the command position while the real command follows them. `rtk` is the
# token-proxy wrapper used in this repo; the rest are shell keywords/builtins that take a
# command as an argument. Stripped in a loop so they stack (`time rtk gh pr create`).
# `eval` covers only the unquoted form -- `eval "gh pr create"` keeps the whole command as one
# quoted token, which by design can never reach a command position. That limit is inherent to
# lexing, not an oversight. This is a denylist: `env`, `timeout` and loop keywords are not in
# it, so those shapes stay open. Recorded in ADR 0012 as accepted, not fixed.
WRAPPERS = ("rtk", "time", "eval", "command", "builtin", "exec", "nohup")

ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# Characters after which an unquoted, unescaped `#` BEGINS A WORD (and so can open a comment),
# together with start-of-input and unquoted whitespace (space/tab/newline -- checked directly
# in _strip_word_initial_comments below, not through this set, since bash's whitespace here is
# narrower than Python's str.isspace()). Measured against real bash AND real zsh, which agreed
# on every row -- see check_bash_fidelity() in the sibling test and ADR 0040 -- not read off
# either manual.
#
# `)` and `}` are DELIBERATELY EXCLUDED even though a subshell's `)` and a brace group's `}`
# really do begin a word in bash: the identical characters ALSO close `$( )` and `${ }`, where
# they do NOT, and telling the two apart needs expansion-nesting tracking this pre-pass does
# not do. Excluding them can only ever emit MORE tokens than bash would, never fewer -- the
# subshell form is then read fail-CLOSED (a command bash would not have run becomes visible to
# a guard) rather than fail-OPEN. Accepted deviation, pinned from both sides in the test suite.
WORD_BREAK_CHARS = ";&|("
WORD_BREAK_WHITESPACE = " \t\n"


def _strip_word_initial_comments(src):
    """Delete an unquoted, unescaped `#` THAT BEGINS A WORD through the end of its LINE.

    A quote-aware pre-pass over the raw text, run in _lex() BEFORE the newline -> ';'
    translation, so "end of line" here really means end of line and not end of input. See ADR
    0040: shlex's own `commenters='#'` opens a comment at an unquoted `#` ANYWHERE in a word,
    which is not bash's rule, and -- because _lex used to translate newline -> ';' first --
    discarded to end of INPUT rather than end of LINE once it did open one. Both were fail-open:
    `echo hi#; <anything>` hid <anything> from every guard built on this lexer.

    Runs before shlex ever sees the string because shlex strips quotes as it tokenizes, and by
    the time a re-scan of tokens could look for `#`, the quoting information the rule needs --
    was this `#` inside a string literal -- is already gone. A derived parse cannot recover what
    its own producer discarded.

    Never raises. An unterminated quote is not this function's problem to catch: it copies the
    rest of the string through unchanged (there is nothing left to close), and lets shlex raise
    ValueError downstream exactly as it does today.
    """
    out = []
    in_single = False
    in_double = False
    at_word_start = True  # start of input begins a word
    i = 0
    n = len(src)
    while i < n:
        c = src[i]

        if in_single:
            # Nothing is special in a single-quoted string except the closing quote itself.
            out.append(c)
            if c == "'":
                in_single = False
                at_word_start = False  # a closing quote does not begin a word
            i += 1
            continue

        if in_double:
            if c == "\\" and i + 1 < n:
                out.append(c)
                out.append(src[i + 1])
                i += 2
                at_word_start = False
                continue
            out.append(c)
            if c == '"':
                in_double = False
                at_word_start = False
            i += 1
            continue

        # Unquoted. A backslash escapes the very next character, including whitespace --
        # `echo a\ # b` keeps its '#' as text because the escaped space does not end the word.
        if c == "\\" and i + 1 < n:
            out.append(c)
            out.append(src[i + 1])
            i += 2
            at_word_start = False
            continue

        if c == "'":
            in_single = True
            out.append(c)
            at_word_start = False
            i += 1
            continue

        if c == '"':
            in_double = True
            out.append(c)
            at_word_start = False
            i += 1
            continue

        if c == "#" and at_word_start:
            # Delete through end of line, keeping the newline (and everything after it) so a
            # command on the next line is still seen. No newline left means the comment runs to
            # end of input, same as bash at the end of a script.
            nl = src.find("\n", i)
            i = n if nl == -1 else nl
            continue

        out.append(c)
        at_word_start = c in WORD_BREAK_WHITESPACE or c in WORD_BREAK_CHARS
        i += 1

    return "".join(out)


def _lex(src):
    """Return the raw shlex token list for `src`, or None if shlex cannot parse it.

    The token-producing head of segments(), extracted so has_grouping() can take a SECOND
    VIEW of the same tokens. One lexer, two views: a second parser would be free to disagree
    with this one about what is quoted, and the disagreement would land in a guard.

    None, not [], for unparseable input -- segments() has to tell that case apart from a
    genuinely empty command, and both legitimately produce no tokens.
    """
    # A backslash-newline is a line CONTINUATION: bash joins the two lines into one command. So
    # this pair is deleted BEFORE the newline translation below, which routes the result into the
    # existing chained-operator path instead of adding a matcher. Order matters -- translate first
    # and the continuation becomes a spurious command separator, which is how it slipped through.
    #
    # bash then ends a command at a newline exactly as it does at `;`, but shlex counts newline as
    # ordinary whitespace, so two lines of one Bash call used to lex into a single segment with no
    # command at position 0. Translating BEFORE lexing is deliberate: the shlex quoting rules then
    # keep the substituted char inside a quoted string as part of that token, so a multi-line
    # commit message still cannot reach the command position of a segment. Splitting the raw input
    # per line instead would raise on any quote spanning lines and fail open -- strictly worse.
    #
    # Backticks are deliberately NOT translated, though doing so does catch a backticked command.
    # shlex cannot see heredocs, so the same translation makes any heredoc body containing one fail
    # CLOSED, and writing that text is routine here. Trading a rare false negative for a common
    # false positive that blocks legitimate work is the wrong direction for a momentum guardrail.
    # Recorded in ADR 0012 as an open shape.
    #
    # The word-initial comment pre-pass runs HERE, between the continuation join and the newline
    # translation -- ordering is load-bearing (ADR 0040). It must see real newlines to scope a
    # comment to end of LINE, so it has to run before they become ';'. commenters="" below is not
    # optional once the pre-pass runs: shlex's own '#'-anywhere-in-a-word rule would otherwise
    # still fire on whatever the pre-pass correctly left as ordinary text (e.g. `fix#123`).
    try:
        joined = src.replace("\\\n", "")
        stripped = _strip_word_initial_comments(joined)
        lex = shlex.shlex(stripped.replace("\n", ";"), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        return list(lex)
    except ValueError:
        return None


def has_grouping(src):
    """True if `src` holds a command-grouping operator OUTSIDE quotes.

    segments() appends a fresh segment for every control operator and throws the operator
    away, so `(`, `)`, `{` and `}` are indistinguishable in its return value. That distinction
    is load-bearing and unrecoverable from the outside: bash discards a `cd` at `)` but keeps
    it past `}`, so an index-ordered rule over the flat segment list carries a subshell's `cd`
    to segments bash would never have applied it to. A caller that cannot resolve the
    ambiguity can at least refuse to guess, which is what this answers.

    False for unparseable input: it reports what the lexer SAW, and it saw nothing. Callers
    that must fail closed on that read it off segments() returning [], which is the signal
    that already exists for it.
    """
    toks = _lex(src)
    if toks is None:
        return False
    return any(tok and all(ch in OPS for ch in tok) and any(ch in GROUPING for ch in tok)
               for tok in toks)


def segments(src):
    """Return [(assignments, argv), ...] -- one entry per shell segment of `src`.

    `assignments` maps the leading `VAR=value` prefixes of that segment to their values;
    `argv` is the remaining tokens, with wrapper words already stripped, so argv[0] is the
    command that segment really runs (or the segment is empty).

    Returns [] for input shlex cannot parse. That is a deliberate fail-OPEN, not a bug: a
    command that is valid bash but not shlex-parseable (some exotic quoting forms) is treated
    as running nothing. Failing closed here would block unrelated commands that merely contain
    such quoting, which is wrong for a momentum guardrail -- the callers' repo/branch checks
    still fail closed for the cases that matter. classify-git-command.py is the one caller
    that overrides this, because it is the last line of defence and this rationale is written
    for callers that are not.
    """
    toks = _lex(src)
    if toks is None:
        return []

    # A redirection is consumed with its target instead of splitting; only control operators split.
    #
    # The leading fd digit (`2` in `2>&1`) is dropped from the segment it was already appended to.
    # shlex discards spacing, so `cmd 2>x` and `cmd 2 >x` are the same token stream and no lexer can
    # tell them apart. ACCEPTED LIMIT, stated rather than discovered -- and the width is ANY trailing
    # bare digit, not only a file named `2`:
    #   `git log -n 5 > out`                       loses the `5` (an option value, no guard impact)
    #   `git commit -m x -- docs/foo.md 2 > out`   loses the pathspec: git-guard BLOCK -> ALLOW
    # The pathspec case is the one guard-visible flip, because git-guard's docs-only exemption is
    # decided from the pathspec. Accepted anyway: the alternative reinstates a FALSE DENIAL on the
    # routine `2>&1` idiom, and a bare digit can never be argv[0], so the command itself is still
    # always recognised. It is a fail-OPEN on a Tier-1 guard, recorded as one -- see ADR 0015.
    # Pinned from both sides by check_accepted_limit() in the sibling test (the digit IS dropped, an
    # ordinary filename is NOT) so the trade-off cannot widen silently.
    raw = [[]]
    drop_target = False
    for t in toks:
        is_op = bool(t) and all(ch in OPS for ch in t)
        if drop_target:
            drop_target = False
            # A redirection's target is a WORD. If the next token is punctuation it is not a
            # target and must not be swallowed -- decisively in `echo hi > >(git commit ...)`,
            # where the target is a process substitution that still has to open a command
            # context. Consuming it blindly left argv[0] == "echo" and hid the commit, which is
            # the same fail-open in a new shape. Fall through and classify it normally.
            if not is_op:
                continue
        if is_op:
            if _is_redirect(t):
                if raw[-1] and raw[-1][-1].isdigit():
                    raw[-1].pop()
                drop_target = True
            else:
                raw.append([])
        else:
            raw[-1].append(t)

    out = []
    for seg in raw:
        while seg and seg[0] in WRAPPERS:
            seg = seg[1:]
        assigns = {}
        i = 0
        while i < len(seg) and ASSIGN_RE.match(seg[i]):
            name, _, val = seg[i].partition("=")
            assigns[name] = val
            i += 1
        out.append((assigns, seg[i:]))
    return out
