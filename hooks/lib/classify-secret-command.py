#!/usr/bin/env python3
"""Decide whether a raw Bash command surfaces credential material via a known
secret-bearing dotfile/path, or dumps a process's full environment.

Two independent checks, either one blocks (docs/features/secret-command-guard.md):

  1. ENV DUMP -- `os.environ` / `process.env` anywhere in the RAW command text
     (not lexed: these are Python/JS expressions inside a -c/-e string, and
     shlex would just hand the same quoted token back unchanged), or a bare
     `env`/`printenv` with NO ARGUMENTS as a segment's own command (argv[0]
     after shell_segments' wrapper-stripping). `env FOO=bar cmd` and
     `printenv HOME` both take arguments and are legitimate; a bare `env`
     prints every inherited variable, unredacted, to the transcript -- the
     exact shape that fired once this session via a diagnostic script.

  2. DOTFILE MENTION -- a token in any segment matches a known secret-bearing
     path. There is NO permitted read shape: every mention blocks.

     v1 carved out an exception for a grep/egrep/fgrep call carrying an
     -o-family flag, on the theory that -o echoes only the substring a
     supplied pattern captured rather than the file's raw lines. That theory
     was false and the carve-out reproduced the incident verbatim, because
     the CALLER supplies the pattern:

         $ grep -o 'export .*' ~/.terminal_aliases
         export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMIK7MDENG"

     A second defect rode along: the flag test accepted any single-dash token
     containing an 'o', so `grep -e -notes .env` satisfied it with no -o
     present -- `-notes` there is grep's PATTERN, not a flag. Removed whole
     on 2026-08-28 rather than narrowed; a bounded-pattern variant was
     considered and rejected because `grep -o '[A-Za-z0-9/+=]\\{20,\\}'`
     still extracts the value. See ADR 0039.

     The .env family exempts three suffixes -- .env.example, .env.template,
     .env.sample -- which are conventionally committed and never carry a real
     value. Without them the guard blocked `git add .env.example` and
     `docker compose --env-file .env.example up`, ordinary work it was never
     meant to touch.

Escape hatch: a leading `SECRET_EXEMPT=<reason>` assignment on any segment,
with a NON-EMPTY reason, allows the command and reports the reason for the
caller to log -- matching MERGE_EXEMPT / TEST_EXEMPT / JUDGE_EXEMPT /
WORKTREE_EXEMPT elsewhere in this repo. v1 shipped no bypass on the reasoning
that the hook "only fires on two narrow shapes, not ordinary work"; the
.env.example measurements above proved that false.

What this does NOT decide is written down in the card's Known-gaps table and
pinned by ALLOW assertions in the test suite: variable indirection
(`F=~/.zshrc; cat "$F"`), a path built by expansion, a read performed inside a
script file, a secrets file not named .env (`config/prod.env`), and the
full-environment dumps that are not bare env/printenv (`export -p`,
`declare -p`, `set`, `env -0`, `ps eww`).

One boundary matters when reading "a token in any segment matches" above.
SEVEN of the eight patterns are anchored at BOTH ends -- `(^|/)` before the
name and `$` after -- so for those the rule is "the path is a WHOLE TRAILING
COMPONENT of a lexed token", which is narrower than "a suffix" in one direction
and than "any mention" in the other. Both of these allow, measured:

    cat foo.zshrc                      no `/` before the name -> not a component
    bash -c "cat ~/.zshrc | head -5"   token does not END at the name

while `cat ./foo/.zshrc` and `bash -c "cat ~/.zshrc"` both block. Pre-existing
and deliberate -- widening it would mean matching paths inside arbitrary quoted
program text, which is a different and much noisier problem.

The EIGHTH -- `Application Support/[^/]*/credentials` -- is deliberately an
unanchored substring match, so it is WIDER: it blocks a `.bak` suffix and a
mid-string mention, both of which the anchored seven allow. Measured, and
pinned by assertions. This is a momentum guardrail, not a security boundary.

Segments come from shell_segments.segments(), the same lexer git-guard and
doc-guard use, so a chained or piped command is judged per segment rather
than by a regex anchored to the string's start.

Usage: classify-secret-command.py <raw-command-text>
Exit 0 = allow (silent). Exit 2 = block (one-line reason on stderr).
Exit 3 = allowed by SECRET_EXEMPT (reason on stderr, for the caller to log).
Any other exit (missing arg, internal error) means the caller should fail
OPEN -- this hook's blast radius is every Bash call in every session, and a
broken classifier must never become a de facto ban on using the shell.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_segments import segments  # noqa: E402

ENV_DUMP_RE = re.compile(r"os\.environ|process\.env")

EXEMPT_VAR = "SECRET_EXEMPT"

# (regex, human label). Anchored on the basename so a longer, unrelated file
# (".envrc" vs ".env") cannot false-positive.
DOTFILE_PATTERNS = [
    (r"(^|/)\.terminal_aliases$", "~/.terminal_aliases"),
    (r"(^|/)\.bash_profile$", "~/.bash_profile"),
    (r"(^|/)\.zshrc$", "~/.zshrc"),
    (r"(^|/)\.zprofile$", "~/.zprofile"),
    (r"(^|/)\.zshenv$", "~/.zshenv"),
    (r"(^|/)\.env(\.[^/]*)?$", ".env / .env.*"),
    (r"(^|/)credentials\.json$", "credentials.json"),
    (r"Application Support/[^/]*/credentials", "*/Application Support/*/credentials*"),
]
DOTFILE_RE = [(re.compile(p), label) for p, label in DOTFILE_PATTERNS]

# Conventionally committed, never carry a real value. Checked only against a
# token the .env pattern already matched, so an unrelated "foo.sample" is
# unaffected either way.
ENV_EXEMPT_SUFFIXES = (".example", ".template", ".sample")
ENV_LABEL = ".env / .env.*"


def matches_dotfile(tok):
    for rx, label in DOTFILE_RE:
        if rx.search(tok):
            if label == ENV_LABEL and tok.endswith(ENV_EXEMPT_SUFFIXES):
                return None
            return label
    return None


def exempt_reason(parsed):
    """The first non-empty SECRET_EXEMPT assignment across all segments."""
    for assigns, _argv in parsed:
        reason = (assigns or {}).get(EXEMPT_VAR)
        if reason:
            return reason
    return None


def main():
    if len(sys.argv) < 2:
        return 0
    command = sys.argv[1]

    parsed = segments(command)

    # Checked before anything else so the hatch clears BOTH block shapes.
    reason = exempt_reason(parsed)
    if reason:
        print("exempted (%s=%s)" % (EXEMPT_VAR, reason), file=sys.stderr)
        return 3

    if ENV_DUMP_RE.search(command):
        print("a raw os.environ/process.env expression dumps the full inherited environment", file=sys.stderr)
        return 2

    for _assigns, argv in parsed:
        if not argv:
            continue

        if argv[0] in ("env", "printenv") and len(argv) == 1:
            print("a bare '%s' with no arguments dumps the full inherited environment" % argv[0], file=sys.stderr)
            return 2

        for tok in argv:
            label = matches_dotfile(tok)
            if label:
                print("mentions %s, which can surface credential material" % label, file=sys.stderr)
                return 2

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Internal error -- the caller fails OPEN on any exit other than 0/2/3.
        sys.exit(1)
