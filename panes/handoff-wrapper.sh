#!/usr/bin/env bash
# handoff-wrapper.sh — what the 75k handoff pane runs. Prints the prompt, blocks
# until the user presses Enter, then execs a fresh interactive claude session
# seeded to restore context. Identical behavior in all four terminals — no
# pre-typed keystroke tricks (spec). Closing the pane instead is harmless.
#
# CLAUDE_PANE_AGENT is deliberately NOT set here: the handoff session is a real
# interactive session and must run all hooks normally.
set -u
CLAUDE_BIN="$HOME/.local/bin/claude"
SEED_PROMPT="Read .claude/session-state.md and CODING_MEMORY.md, then continue the work in progress."

target_cwd="${1:-$PWD}"
cd "$target_cwd" 2>/dev/null || printf 'handoff: warning — could not cd to %s, starting here\n' "$target_cwd"

printf '=== Context handoff ===\n'
printf 'The main session crossed 75k tokens. A fresh session will continue the work in:\n  %s\n\n' "$target_cwd"
printf 'Press Enter to start handoff session\n'
IFS= read -r _

# Layout-v2 (spec assumption 2): this pane was opened under a managed
# "aux:<run-id>" title. Once adopted as the main session that title must stop
# matching the managed grammar, or future aux dispatches would tab onto main's
# pane. Best-effort by design — documented consequence if it fails.
#
# Deliberately NO --surface: probe P7 recorded $CMUX_SURFACE_ID as a UUID and only
# --workspace was proven to accept UUIDs, while P6 recorded that an unresolvable
# --surface silently falls through to the FOCUSED tab (exit 0). Passing the UUID
# would risk branding an innocent pane. With --surface omitted, cmux resolves via
# $CMUX_TAB_ID/$CMUX_SURFACE_ID from this pane's own environment — the correct
# target, no ref-format guessing. Unverified live; confirm at the end of Task 8.
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
if [ -n "${CMUX_SURFACE_ID:-}" ] && [ -n "${CMUX_WORKSPACE_ID:-}" ] && [ -x "$CMUX_BIN" ]; then
  "$CMUX_BIN" rename-tab --workspace "$CMUX_WORKSPACE_ID" -- "main session" >/dev/null 2>&1 || true
fi

exec "$CLAUDE_BIN" --dangerously-skip-permissions "$SEED_PROMPT"
