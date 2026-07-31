#!/usr/bin/env python3
"""Classify a raw Bash command string as "does this really run `gh pr create`?".

Used by hooks/judge-guard.sh. Reads the command line on stdin and writes two lines
to stdout: the kind ("PR" or "NO"), then the JUDGE_EXEMPT reason ("" when absent).

Extracted from an inline `python -c` string inside judge-guard.sh (ADR 0012). That
string was single-quoted in shell, so a lone apostrophe anywhere in it -- including
in a comment -- terminated the quote and broke the entire hook. It happened three
times, twice inside the very comment block warning against it, costing ~24 spurious
test failures each time; a warning comment was a disproven control. Living in its
own file removes the hazard by construction and makes the classifier importable, so
bypass shapes can be unit-tested directly instead of probed through the hook.

shlex does the shell quoting a flat regex cannot. Quoted text survives as a single
token, so `gh pr create` inside a commit message or an echo argument can never sit
at a segment command position and is correctly ignored.
"""

import re
import shlex
import sys

# punctuation_chars=True makes shlex emit control operators as standalone tokens even when
# unspaced (`push&&gh` -> `push`, `&&`, `gh`), which a plain whitespace split cannot see.
# Braces are in the set deliberately: a brace group opens a command context exactly as a
# subshell does, but `{` is not one of shlex's punctuation chars, so it lexed as an ordinary
# token and took the segment command position -- `{ gh pr create; }` walked past the guard
# while `( gh pr create )` did not.
OPS = "(){};<>|&"

# Words that occupy the command position while the real command follows them. `rtk` is the
# token-proxy wrapper used in this repo; the rest are shell keywords/builtins that take a
# command as an argument. Stripped in a loop so they stack (`time rtk gh pr create`).
# `eval` covers only the unquoted form -- `eval "gh pr create"` keeps the whole command as one
# quoted token, which by design can never reach a command position. That limit is inherent to
# lexing, not an oversight. This is a denylist: `env`, `timeout` and loop keywords are not in
# it, so those shapes stay open. Recorded in ADR 0012 as accepted, not fixed.
WRAPPERS = ("rtk", "time", "eval", "command", "builtin", "exec", "nohup")

ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def classify(src):
    """Return (kind, exempt_reason) for a raw Bash command string.

    kind is "PR" when some shell segment really runs `gh pr create`, else "NO".
    exempt_reason is the JUDGE_EXEMPT value from the *matching* segment, mirroring bash,
    where such a prefix binds only to its own command.
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
    # Backticks are deliberately NOT translated, though doing so does catch `gh pr create` in a
    # legacy substitution. shlex cannot see heredocs, so the same translation makes any heredoc
    # body containing a backticked `gh pr create` fail CLOSED, and writing that text is routine
    # here. Trading a rare false negative for a common false positive that blocks legitimate work
    # is the wrong direction for a momentum guardrail. Recorded in ADR 0012 as an open shape.
    try:
        joined = src.replace("\\\n", "")
        lex = shlex.shlex(joined.replace("\n", ";"), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        # Deliberate fail-OPEN, not a bug: a command that is valid bash but not shlex-parseable
        # (some exotic shell quoting forms) is treated as "not a gh pr create". Failing closed
        # here would block unrelated commands that merely contain such quoting, which is wrong
        # for a momentum guardrail -- the repo/branch/HEAD checks in the hook still fail closed
        # for the cases that matter.
        return ("NO", "")

    segments = [[]]
    for t in toks:
        if t and all(ch in OPS for ch in t):
            segments.append([])
        else:
            segments[-1].append(t)

    for seg in segments:
        while seg and seg[0] in WRAPPERS:
            seg = seg[1:]
        exempt = ""
        i = 0
        while i < len(seg) and ASSIGN_RE.match(seg[i]):
            name, _, val = seg[i].partition("=")
            if name == "JUDGE_EXEMPT":
                exempt = val.replace("\n", " ")
            i += 1
        # `gh` must hold the command position, but `pr create` need not be tokens 1-2: global
        # flags are legal before the subcommand (`gh -R owner/repo pr create`). Requiring the two
        # words ADJACENT keeps the false-positive surface narrow -- quoted text is a single token,
        # so a commit message mentioning the phrase still cannot produce an adjacent bare pair.
        rest = seg[i:]
        if rest and rest[0] == "gh":
            for j in range(1, len(rest) - 1):
                if rest[j] == "pr" and rest[j + 1] == "create":
                    return ("PR", exempt)
    return ("NO", "")


def main():
    kind, exempt = classify(sys.stdin.read())
    sys.stdout.write(kind + "\n" + exempt + "\n")


if __name__ == "__main__":
    main()
