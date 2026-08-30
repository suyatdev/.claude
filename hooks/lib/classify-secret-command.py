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
with a NON-EMPTY reason -- but as of 2026-08-30 (task 13 on
docs/features/output-secret-redaction.md) the flag NO LONGER CLEARS A BLOCK ON
ITS OWN. It is honoured only when a matching approval record exists, granted by
`secret_approval.py grant <id>` after the user typed the literal phrase
`secret-gate override` (rules/gates.md). The record is session-scoped,
command-scoped, and DELETED on first use, so one approval clears one run of one
command. An unapproved flag is IGNORED, not fatal: the command is then judged on
its own merits, so an exempt on a harmless command still allows.

That check is a SPEED BUMP, not a security boundary, and the deny message must
not imply otherwise: the record is written from inside the session by the agent
the gate constrains, so it is forgeable. It states that an approval was claimed;
it does not prove one was given. See secret_approval.py for the full rationale.

A FULL-ENVIRONMENT DUMP CANNOT BE EXEMPTED AT ALL, by any flag or any approval:
there is nothing for the user to inspect in advance, so there is nothing an
approval could be an approval OF (rules/gates.md; user decision 2026-08-30). The
env-dump check therefore runs BEFORE the exempt check. Until that date it ran
after, and `SECRET_EXEMPT=x env` was allowed -- pinned green by three assertions
that are now inverted. Exit 4 reports this class separately from exit 2 so the
wrapper can offer an approval id for one and, correctly, none for the other.

v1 shipped no bypass at all, on the reasoning that the hook "only fires on two
narrow shapes, not ordinary work"; the .env.example measurements above proved
that false.

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

Usage: classify-secret-command.py <raw-command-text> [session-id]
Exit 0 = allow (silent). Exit 2 = block, APPROVABLE (one-line reason on stderr).
Exit 4 = block, NEVER approvable -- a full-environment dump.
Exit 3 = allowed by an approved SECRET_EXEMPT (reason on stderr, to be logged).
Any other exit (missing arg, internal error) means the caller should fail
OPEN -- this hook's blast radius is every Bash call in every session, and a
broken classifier must never become a de facto ban on using the shell.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_segments import segments  # noqa: E402
# Defensive: a broken or missing helper must disable only the HATCH, never the
# block checks. The first cut let this import fail open like the rest of the
# hook, which shipped a silent off-switch for the whole guard -- corrupt one
# auxiliary file and both block shapes vanished with an empty stderr. Found by
# the observability judge, 2026-08-30. Refusing the hatch instead is safer in
# both directions: secret shapes still block, and ordinary commands still allow,
# so it is not a de facto ban on using the shell either.
try:
    from secret_approval import consume as consume_approval  # noqa: E402
    from secret_approval import fingerprint, is_approvable  # noqa: E402
    APPROVAL_HELPER_OK = True
except Exception:  # noqa: BLE001 -- any import failure, not just ImportError
    APPROVAL_HELPER_OK = False

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
    session = sys.argv[2] if len(sys.argv) > 2 else ""

    parsed = segments(command)

    # ---- Full-environment dumps. Checked FIRST, because no flag and no
    # approval can clear one: there is nothing to inspect in advance.
    if ENV_DUMP_RE.search(command):
        print("a raw os.environ/process.env expression dumps the full inherited environment", file=sys.stderr)
        return 4

    for _assigns, argv in parsed:
        if argv and argv[0] in ("env", "printenv") and len(argv) == 1:
            print("a bare '%s' with no arguments dumps the full inherited environment" % argv[0], file=sys.stderr)
            return 4

    # ---- The hatch, now gated on a recorded approval. An unapproved flag is
    # ignored rather than fatal, so the command falls through to be judged on
    # its own merits below.
    ignored_note = ""
    reason = exempt_reason(parsed)
    if reason:
        if not APPROVAL_HELPER_OK:
            ignored_note = ("; %s ignored -- the approval helper is unavailable, so no "
                            "exemption can be verified" % EXEMPT_VAR)
        elif not is_approvable(command):
            ignored_note = ("; %s ignored -- a redirection is invisible to the approval id, "
                            "so this command cannot be approved" % EXEMPT_VAR)
        elif consume_approval(session, fingerprint(command)):
            print("exempted (%s=%s); approval consumed" % (EXEMPT_VAR, reason), file=sys.stderr)
            return 3
        else:
            ignored_note = "; %s ignored -- no recorded approval for this command" % EXEMPT_VAR

    for _assigns, argv in parsed:
        for tok in argv or []:
            label = matches_dotfile(tok)
            if label:
                print("mentions %s, which can surface credential material%s"
                      % (label, ignored_note), file=sys.stderr)
                return 2

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Internal error -- the caller fails OPEN on any exit other than 0/2/3.
        sys.exit(1)
