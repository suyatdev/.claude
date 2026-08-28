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
     path. Blocks UNLESS that mention sits inside a grep/egrep/fgrep call
     carrying an -o-family flag (-o, --only-matching, or a clustered short
     option containing 'o'), the shape that echoes only the substring a
     supplied pattern captured, not the file's raw lines. Piping a plain
     `cat` of the file INTO a `grep -o` does not count: the file is named in
     the cat segment, not inside the grep call, so that segment still
     blocks -- the protection has to wrap the read itself. The shape that
     actually fired in this repo was an unflagged `grep -n "export "` on
     ~/.terminal_aliases, which echoed complete `export VAR="value"` lines.

Segments come from shell_segments.segments(), the same lexer git-guard and
doc-guard use, so a chained or piped command is judged per segment rather
than by a regex anchored to the string's start.

Usage: classify-secret-command.py <raw-command-text>
Exit 0 = allow (silent). Exit 2 = block (one-line reason on stderr).
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

GREP_CMDS = {"grep", "egrep", "fgrep"}


def is_only_matching_flag(tok):
    if tok in ("-o", "--only-matching"):
        return True
    # A clustered short-option word, e.g. -no, -Eo, -io -- anything starting
    # with a single dash (not --) that contains 'o' among its flag letters.
    return tok.startswith("-") and not tok.startswith("--") and "o" in tok[1:]


def matches_dotfile(tok):
    for rx, label in DOTFILE_RE:
        if rx.search(tok):
            return label
    return None


def main():
    if len(sys.argv) < 2:
        return 0
    command = sys.argv[1]

    if ENV_DUMP_RE.search(command):
        print("a raw os.environ/process.env expression dumps the full inherited environment", file=sys.stderr)
        return 2

    for _assigns, argv in segments(command):
        if not argv:
            continue

        if argv[0] in ("env", "printenv") and len(argv) == 1:
            print("a bare '%s' with no arguments dumps the full inherited environment" % argv[0], file=sys.stderr)
            return 2

        hit_label = None
        for tok in argv:
            label = matches_dotfile(tok)
            if label:
                hit_label = label
                break
        if hit_label is None:
            continue

        if argv[0] in GREP_CMDS and any(is_only_matching_flag(t) for t in argv[1:]):
            continue  # protected: an -o-family grep call, allowed

        print("mentions %s outside a grep/egrep/fgrep -o call" % hit_label, file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Internal error -- the caller fails OPEN on any exit other than 0/2.
        sys.exit(1)
