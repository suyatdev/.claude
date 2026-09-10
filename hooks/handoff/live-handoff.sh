#!/bin/bash
# Vendored from https://github.com/Sonovore/claude-code-handoff @ c6cb717 (2026-07-20)
# Locally patched 2026-07-20: INIT template gained the "<!-- Files touched this session -->"
# marker so the PostToolUse tracker's sed target exists (upstream bug: the tracker silently
# no-ops whenever this template wins the file-creation race against proactive-handoff.sh init).
# Live Handoff — UserPromptSubmit hook
# Injects a directive on EVERY user message telling Claude to maintain session-state.md
# This is the primary mechanism for continuous context preservation.
#
# How it works:
#   - Fires before Claude processes each user message
#   - Outputs a <live-handoff> directive into Claude's system context
#   - Claude sees this directive and updates .claude/session-state.md as needed
#   - When session-state.md grows too large, the directive switches to "rewrite" mode
#
# Install: place in .claude/hooks/ and add UserPromptSubmit to .claude/settings.json
#
# Locally patched 2026-09-09 by docs/features/handoff-trim-safety.md: before any directive
# is emitted, the notepad is copied to a per-session snapshot, and the trim directive is
# withheld whenever that copy could not be taken. Rationale, in the card's terms:
#   - the snapshot happens on EVERY turn, not only over the cap (spec finding C3). The
#     directive is a request, not a ceiling: a model can rewrite the notepad below the cap
#     too, and before this the great majority of turns had no copy behind them at all.
#   - the filename carries the session id (spec finding C2). A single shared snapshot let
#     the first session to finish delete it, after which a second session in the same repo
#     found none and checked nothing.
#   - a failed snapshot suppresses the trim (spec finding O-C). Asking for a cut while
#     unable to back it up is exactly the promise this card exists to stop making, so the
#     trim pauses and the append directive says why.

set -euo pipefail

# Pane agent sessions must not clobber the interactive session's handoff state
# (pane-orchestration spec, error-handling table).
[ -n "${CLAUDE_PANE_AGENT:-}" ] && exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_FILE="$REPO_ROOT/.claude/session-state.md"

# Ensure .claude directory exists
mkdir -p "$REPO_ROOT/.claude"

# --- Session identity ---------------------------------------------------------------
# Hooks receive the id on stdin; a pane-less caller may only have the environment
# variable, and a caller with neither still gets a working (if less specific) snapshot
# rather than none. Same three-step fallback and the same "nosession" literal as
# hooks/secret-command-guard.sh, so the two agree about what to call an unnamed session.
JQ_BIN="/usr/bin/jq"
HOOK_PAYLOAD=""
[ -t 0 ] || HOOK_PAYLOAD="$(cat 2>/dev/null || true)"
SESSION_RAW=""
if [ -n "$HOOK_PAYLOAD" ] && [ -x "$JQ_BIN" ]; then
  SESSION_RAW="$(printf '%s' "$HOOK_PAYLOAD" | "$JQ_BIN" -er '.session_id // empty' 2>/dev/null)" \
    || SESSION_RAW=""
fi
[ -n "$SESSION_RAW" ] || SESSION_RAW="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$SESSION_RAW" ] || SESSION_RAW="nosession"

# The id reaches a filename, so everything outside the portable-filename set becomes an
# underscore — a payload is untrusted input, and "../../x" must not steer a write out of
# .claude. Real ids are UUID-shaped, so in practice this substitutes nothing.
SESSION_SLUG="$(printf '%s' "$SESSION_RAW" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
[ -n "$SESSION_SLUG" ] || SESSION_SLUG="nosession"

PRETRIM_FILE="$REPO_ROOT/.claude/session-state.pretrim.${SESSION_SLUG}.md"
STRIKE_FILE="$REPO_ROOT/.claude/session-state.keepguard-strikes.${SESSION_SLUG}"

# snapshot_notepad() lives in the shared library, resolved from THIS file's own directory
# (never $PWD, never `git rev-parse`) so the hook behaves the same whatever the caller cwd.
# Sourcing happens inside the `if` so `set -e` cannot kill the hook on a library that fails
# to parse: an unloadable library is handled below as a snapshot failure, which is the same
# "cannot back this up" state as an unwritable disk and must not fall through to a trim.
HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HOOK_DIR/lib/handoff-archive.sh"
LIB_OK=false
# shellcheck disable=SC1090  # library lives beside this hook, not user input
if [ -r "$LIB" ] && . "$LIB"; then
  LIB_OK=true
fi

# Check for active task/bug files
HAS_TASK=false
HAS_BUG=false
[ -f "$REPO_ROOT/.claude/current-task.md" ] && HAS_TASK=true
[ -f "$REPO_ROOT/.claude/current-bug.md" ] && HAS_BUG=true

# Line limits vary by mode:
#   General: 60-80 lines
#   Task: 80-100 lines
#   Bug (or task+bug): 100-120 lines
if [ "$HAS_BUG" = true ]; then
    MAX_LINES=120
    TARGET_LINES=100
elif [ "$HAS_TASK" = true ]; then
    MAX_LINES=100
    TARGET_LINES=80
else
    MAX_LINES=80
    TARGET_LINES=60
fi

# Create state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" << 'INIT'
# Session State

Auto-maintained during conversation. Do not delete.

## Decisions & Architecture

## Key Context

## Modified Files
<!-- Files touched this session -->

## Current Focus

## Next Steps
INIT
fi

# --- Snapshot, before any directive is emitted ----------------------------------------
# One case deliberately does NOT refresh the snapshot: a keep-guard strike is outstanding
# and the snapshot it is holding still exists. That snapshot is the pre-damage copy the
# guard blocked on, and the notepad in front of us is the damaged one — overwriting it
# would destroy the only recovery source at exactly the moment it is needed, and would
# make "the guard has already blocked twice on the same PT" unreachable. A strike file
# with no snapshot beside it is not that case: snapshot normally, so a deleted copy plus a
# stale strike file cannot leave the session permanently unprotected.
SNAPSHOT_OK=false
SNAPSHOT_REASON=""
if [ -f "$STRIKE_FILE" ] && [ -r "$PRETRIM_FILE" ]; then
    SNAPSHOT_OK=true
elif [ "$LIB_OK" != true ]; then
    SNAPSHOT_REASON="the snapshot library ${LIB} could not be loaded"
elif snapshot_notepad "$STATE_FILE" "$PRETRIM_FILE"; then
    SNAPSHOT_OK=true
else
    SNAPSHOT_REASON="${PRETRIM_FILE} could not be written"
fi

SNAPSHOT_WARNING=""
if [ "$SNAPSHOT_OK" != true ]; then
    SNAPSHOT_WARNING="
⚠️ TRIM SUPPRESSED — no pre-trim snapshot was taken: ${SNAPSHOT_REASON}.
Append only this turn. Do NOT rewrite, shorten, reorder or delete any part of
.claude/session-state.md: nothing removed while the snapshot is unavailable can be
recovered. Report this to the user, and fix the write failure (usually an unwritable
.claude directory) or copy the file aside by hand before trimming anything."
fi

# Count current lines
LINE_COUNT=$(wc -l < "$STATE_FILE" | tr -d ' ')

# Build the task/bug completion check directive
TASK_BUG_DIRECTIVE=""
if [ "$HAS_TASK" = true ] || [ "$HAS_BUG" = true ]; then
    TASK_BUG_DIRECTIVE="
Also evaluate: has the current task or bug been completed?
- If a TASK is done: remove task-specific details from session-state.md, delete .claude/current-task.md, and note completion in session-state.md
- If a BUG is fixed: remove bug investigation details from session-state.md, delete .claude/current-bug.md, and note the fix in session-state.md
- If still in progress: keep task/bug context current in session-state.md"
fi

# Always output a directive — Claude sees this every turn. The SNAPSHOT_OK conjunct is the
# suppression: with no copy behind it, the oversize branch is never taken whatever the line
# count, and the append branch below carries the warning instead.
if [ "$SNAPSHOT_OK" = true ] && [ "$LINE_COUNT" -gt "$MAX_LINES" ]; then
    cat << DIRECTIVE
<live-handoff>
REQUIRED: Before responding, update .claude/session-state.md:
1. Read the current file
2. It has grown too large. Rewrite it keeping ONLY the most critical information:
   - Active decisions and their rationale
   - Key context that would be lost if early conversation is compressed
   - Current focus and immediate next steps
   - Important file locations and what changed
3. Remove anything that is: obvious from code, already committed, no longer relevant, or low-importance
4. Target: under ${TARGET_LINES} lines. Be ruthless — only keep what you'd need to continue this work cold.
${TASK_BUG_DIRECTIVE}
</live-handoff>
DIRECTIVE
else
    cat << DIRECTIVE
<live-handoff>
REQUIRED: Before responding, check if anything important happened since session-state.md was last updated.
If yes — append to the appropriate section in .claude/session-state.md:
- Decisions made and why
- Architecture or approach changes
- Key discoveries or gotchas
- Important file:line references
- Changes to current focus or next steps
If nothing noteworthy happened (e.g. simple question, no new info), skip the update.
Do NOT rewrite the whole file — just append new items to existing sections.
${TASK_BUG_DIRECTIVE}${SNAPSHOT_WARNING}
</live-handoff>
DIRECTIVE
fi

exit 0
