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


def _is_redirect(tok):
    """True for a punctuation token that redirects rather than separates two commands.

    `<` and `>` are in OPS because shlex must emit them as standalone tokens, but a redirection is
    PART of the command it attaches to and may appear anywhere in it -- including before the command
    name. Treating one as a separator (which this module did until 2026-08-04) produced three
    failures at once: `2>&1` left the fd digit behind as a phantom operand so doc-guard denied real
    commits; the redirect target reached a segment command position; and a LEADING redirect
    (`> out.txt git commit ...`) pushed the real command out of position 0 entirely, so no guard saw
    it. See docs/features/shell-segments-redirects.md.

    Containing `<` or `>` is the whole test, and it partitions the operator set exactly: redirections
    `> >> < << <<< <> >| >& <& &> &>>` all contain one; control operators `| || && ; ;; & ( ) { }`
    contain neither. `|&` -- bash's pipe-with-stderr -- correctly stays a separator.
    """
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


def segments(src):
    """Return [(assignments, argv), ...] -- one entry per shell segment of `src`.

    `assignments` maps the leading `VAR=value` prefixes of that segment to their values;
    `argv` is the remaining tokens, with wrapper words already stripped, so argv[0] is the
    command that segment really runs (or the segment is empty).

    Returns [] for input shlex cannot parse. That is a deliberate fail-OPEN, not a bug: a
    command that is valid bash but not shlex-parseable (some exotic quoting forms) is treated
    as running nothing. Failing closed here would block unrelated commands that merely contain
    such quoting, which is wrong for a momentum guardrail -- the callers' repo/branch checks
    still fail closed for the cases that matter.
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
    try:
        joined = src.replace("\\\n", "")
        lex = shlex.shlex(joined.replace("\n", ";"), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        return []

    # A redirection is consumed with its target instead of splitting; only control operators split.
    #
    # The leading fd digit (`2` in `2>&1`) is dropped from the segment it was already appended to.
    # shlex discards spacing, so `cmd 2>x` and `cmd 2 >x` are the same token stream and no lexer can
    # tell them apart. ACCEPTED LIMIT, stated rather than discovered: this loses a genuine operand in
    # `cmd -- 2 > out`, i.e. a file literally named `2` immediately before a redirect. That is
    # strictly better than the old behaviour, which INVENTED that operand in the far more common
    # `2>&1`, and a bare digit can never be argv[0], so command recognition is unaffected. Pinned by
    # check_accepted_limit() in the sibling test so the trade-off cannot change silently.
    raw = [[]]
    drop_target = False
    for t in toks:
        if drop_target:
            drop_target = False
            continue
        if t and all(ch in OPS for ch in t):
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
