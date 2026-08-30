#!/usr/bin/env bash
#
# secret-command-guard.sh — block Bash commands that surface credential
# material (Tier 1, PreToolUse, matcher Bash).
#
# This session leaked real secrets from ~/.terminal_aliases twice in one
# sitting: once via a diagnostic script that printed a subprocess's full
# inherited environment, once via `grep -n "export "` on a dotfile, which
# echoed complete `export VAR="value"` lines into the transcript.
# rules/core-conduct.md already says "nothing sensitive lives client-side" --
# it did not prevent either leak, because prose is advisory and a
# PostToolUse hook cannot retroactively redact output already returned to
# the model (confirmed against this repo's existing PostToolUse hooks, which
# only ever add context, never replace a prior tool result). Prevention has
# to happen at PreToolUse, on the command text, before it runs.
#
# See docs/features/secret-command-guard.md for the full scope and the two
# shapes this blocks: ANY mention of a named secret-bearing dotfile/path, and
# a full-environment dump (os.environ/process.env, or a bare env/printenv).
# hooks/lib/classify-secret-command.py does the analysis; this wrapper only
# reads the PreToolUse payload and reports its verdict.
#
# There is no permitted read shape. v1 allowed a grep -o call on the theory
# that -o echoes only the matched substring; the caller picks the pattern, so
# `grep -o 'export .*'` reproduced the incident verbatim. Carve-out removed
# 2026-08-28 -- ADR 0039.
#
# FAILS OPEN on a missing python3, an unparseable payload, or any internal
# error in the classifier -- the opposite direction from scan-secrets.sh, a
# deliberate choice: this hook's blast radius is every Bash call in every
# session, so a broken classifier must never become a de facto ban on using
# the shell the way a broken write-scanner blocking one file would not.
#
# Bypass: `SECRET_EXEMPT=<reason> <command>` (logged), matching this repo's
# other Tier 1 guards. v1 shipped none, on the reasoning that the hook fires
# only on narrow incident shapes and never on ordinary work -- measurement
# refuted that (it blocked `git add .env.example`), so the hatch exists.
#
# As of 2026-08-30 the flag alone no longer clears a block. It is honoured only
# alongside a session- and command-scoped approval record, granted by
# `hooks/lib/secret_approval.py grant <id>` after the user typed the literal
# phrase `secret-gate override` (rules/gates.md). One approval clears one run of
# one command and is deleted on use. An unapproved flag is IGNORED, not fatal:
# the command is judged on its own merits, so an exempt on a harmless command
# still allows. A full-environment dump can never be cleared this way at all.
#
# That approval is a SPEED BUMP, and NOTHING PRINTED BELOW MAY IMPLY OTHERWISE:
# the record is written from inside the session by the agent the gate
# constrains, so it is forgeable. It states that an approval was claimed; it
# does not prove one was given. The typed phrase is the load-bearing control.
#
# NOT a security boundary, and this file must not imply otherwise: the card's
# Known-gaps table lists EIGHT measured ALLOW shapes, incl. variable indirection,
# any read performed inside a script file, and -- the shortest of them -- an INPUT
# REDIRECTION: `cat < ~/.zshrc` lexes to argv ['cat'], matches nothing, and is
# allowed, because the lexer drops the redirection target. Note especially that "any
# mention" means, for 7 of the 8 patterns, "the path is a WHOLE TRAILING
# COMPONENT of a lexed token" (the Application Support pattern is an unanchored
# substring match, and so is wider):
# `bash -c "cat ~/.zshrc"` blocks but `bash -c "cat ~/.zshrc | head -5"` does
# not (the token no longer ends there), and `cat foo.zshrc` does not either
# (no `/` before the name).
#
# Exit 0 = allow / silent. Exit 2 = blocked, reason on stderr.

set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSIFIER="$HOOK_DIR/lib/classify-secret-command.py"
APPROVAL_LIB="$HOOK_DIR/lib/secret_approval.py"

payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi
[ -n "$payload" ] || exit 0

py=$(command -v python3 || command -v python) || py=""
# Fail OPEN: without python we cannot inspect the payload at all.
[ -n "$py" ] || exit 0
[ -r "$CLASSIFIER" ] || exit 0

event=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
sys.stdout.write(p.get("hook_event_name") or "")
' 2>/dev/null)
[ "$event" = "PreToolUse" ] || exit 0

command_line=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
ti = p.get("tool_input")
if isinstance(ti, dict):
    v = ti.get("command")
    if isinstance(v, str):
        sys.stdout.write(v)
' 2>/dev/null)
[ -n "$command_line" ] || exit 0

# Approval records are session-scoped, so the classifier needs the session id.
# Hooks receive it on stdin; the grant helper, run as an ordinary Bash command,
# reads $CLAUDE_CODE_SESSION_ID instead. Fall back to that here so the two agree
# when the payload omits the field, and to the same "nosession" literal the
# other guards use when neither is available.
session_id=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
v = p.get("session_id")
if isinstance(v, str):
    sys.stdout.write(v)
' 2>/dev/null)
[ -n "$session_id" ] || session_id="${CLAUDE_CODE_SESSION_ID:-nosession}"

reason=$("$py" "$CLASSIFIER" "$command_line" "$session_id" 2>&1 >/dev/null)
status=$?

# Exit 3 = an approved SECRET_EXEMPT was found and its approval spent. Allow,
# but say so on stderr so the bypass leaves a trace rather than passing silently.
if [ "$status" -eq 3 ]; then
  printf 'secret-command-guard: %s; allowing.\n' "$reason" >&2
  exit 0
fi

# Exit 4 = a full-environment dump. Blocked like exit 2, but it is NOT
# approvable, so this branch deliberately offers no approval id and no grant
# command -- printing a route that cannot work is worse than printing none.
if [ "$status" -eq 4 ]; then
  printf 'secret-command-guard: blocked -- %s.\n' "$reason" >&2
  printf 'A full-environment dump cannot be approved: there is nothing for the user to inspect in advance,\n' >&2
  printf 'so there is nothing an approval could be an approval of. SECRET_EXEMPT does not clear it.\n' >&2
  printf 'Ask the user for the specific value out of band instead.\n' >&2
  printf 'If this fired on prose that merely mentions the expression -- a commit message or PR body -- reword the text.\n' >&2
  exit 2
fi

[ "$status" -eq 2 ] || exit 0

# The approval id is a hash of this command, so the user is approving a command
# rather than a file or a session. Computed here rather than inside the reason
# line so the classifier keeps one-line output.
approval_id=""
approval_why="broken"
if [ -r "$APPROVAL_LIB" ]; then
  id_err=$(mktemp)
  approval_id=$("$py" "$APPROVAL_LIB" id "$command_line" 2>"$id_err")
  id_status=$?          # read immediately -- anything else here overwrites it
  case "$id_status" in
    0) approval_why="" ;;
    3) approval_why=$(cat "$id_err"); approval_id="" ;;
    *) approval_why="broken"; approval_id="" ;;
  esac
  rm -f "$id_err"
fi

printf 'secret-command-guard: blocked -- %s.\n' "$reason" >&2
printf 'This command was refused because it could surface credential material in the transcript.\n' >&2
# Deliberately prescribes no read shape. The previous wording recommended
# `grep -o capturing only the value` -- the exact command that leaked, since
# `grep -o "export .*"` prints the whole assignment. There is no safe way to
# echo a secret file into the transcript, so do not offer one.
printf 'There is no permitted way to read this file into the transcript. Ask the user to share the value out of band.\n' >&2
if [ -n "$approval_id" ]; then
  printf '\nIf the user has inspected THIS EXACT COMMAND and typed the literal phrase `secret-gate override`,\n' >&2
  printf 'record that and re-run once:\n' >&2
  printf '  %s %s grant %s\n' "$py" "$APPROVAL_LIB" "$approval_id" >&2
  printf '  SECRET_EXEMPT=<reason> <the same command>\n' >&2
  printf 'The approval covers one run of this one command and is deleted on first use.\n' >&2
  printf 'It is written from inside this session, so it records that an approval was claimed -- it does not prove\n' >&2
  printf 'one was given. The typed phrase is the control; this file is only a speed bump. Do not grant it yourself.\n' >&2
elif [ "$approval_why" != broken ] && [ -n "$approval_why" ]; then
  printf '\nThis command cannot be approved through the override path: %s.\n' "$approval_why" >&2
  printf 'Ask the user for the value out of band, or seek approval for the plain command without the\n' >&2
  printf 'redirection or wrapper word and run that one.\n' >&2
else
  printf '\nThe override path is unavailable: hooks/lib/secret_approval.py is missing or broken, so no exemption\n' >&2
  printf 'can be verified. The block above still stands. Ask the user for the value out of band.\n' >&2
fi
exit 2
