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
exec "$CLAUDE_BIN" --dangerously-skip-permissions "$SEED_PROMPT"
