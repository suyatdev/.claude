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
# shapes this blocks: a named secret-bearing dotfile/path outside a grep -o
# call, and a full-environment dump (os.environ/process.env, or a bare
# env/printenv). hooks/lib/classify-secret-command.py does the analysis;
# this wrapper only reads the PreToolUse payload and reports its verdict.
#
# FAILS OPEN on a missing python3, an unparseable payload, or any internal
# error in the classifier -- the opposite direction from scan-secrets.sh, a
# deliberate choice: this hook's blast radius is every Bash call in every
# session, so a broken classifier must never become a de facto ban on using
# the shell the way a broken write-scanner blocking one file would not.
#
# No bypass environment variable, by design (matches the spec) -- this hook
# only fires on the two narrow, already-incident shapes below, not on
# ordinary work, so there is no legitimate case that needs an escape hatch.
#
# Exit 0 = allow / silent. Exit 2 = blocked, reason on stderr.

set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSIFIER="$HOOK_DIR/lib/classify-secret-command.py"

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

reason=$("$py" "$CLASSIFIER" "$command_line" 2>&1 >/dev/null)
status=$?
[ "$status" -eq 2 ] || exit 0

printf 'secret-command-guard: blocked -- %s.\n' "$reason" >&2
printf 'This command was refused because it could surface credential material in the transcript.\n' >&2
printf 'Read the specific value with a narrower tool (e.g. grep -o capturing only the value, never the whole line), or ask the user to share it out of band.\n' >&2
exit 2
