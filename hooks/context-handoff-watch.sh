#!/usr/bin/env bash
# context-handoff-watch.sh — PostToolUse hook, matcher "*". At >= 75,000 context
# tokens (input + cache_creation + cache_read of the transcript's last assistant
# usage entry — the statusline's orange line), once per session: write the
# fired-flag, prepare a press-Enter handoff pane, and nudge the freshness
# checkpoint via additionalContext.
#
# ORDERING IS LOAD-BEARING (obs r2 advisory 1): this hook runs on every tool
# call in every repo, so the per-session fired-flag check comes BEFORE any
# transcript access — after firing once, the cost is one stat. Never blocks:
# every failure path exits 0 silently.
set -u
THRESHOLD=75000
STATE_DIR="${PANE_STATE_DIR:-$HOME/.claude/panes/state}"
DISPATCH="${PANE_DISPATCH:-$HOME/.claude/panes/dispatch-pane-agent.sh}"
JQ_BIN="/usr/bin/jq"
TAIL_LINES=200

[ -n "${CLAUDE_PANE_AGENT:-}" ] && exit 0
payload=""
if [ ! -t 0 ]; then payload=$(cat); fi
[ -n "$payload" ] || exit 0
[ -x "$JQ_BIN" ] || exit 0

sid=$(printf '%s' "$payload" | "$JQ_BIN" -er '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$sid" ] || exit 0
flag="$STATE_DIR/handoff-fired-$sid"
[ -f "$flag" ] && exit 0   # cheap path forever after firing — before transcript work

transcript=$(printf '%s' "$payload" | "$JQ_BIN" -er '.transcript_path // empty' 2>/dev/null) || exit 0
[ -f "$transcript" ] && [ -r "$transcript" ] || exit 0

# Last assistant usage entry only; tail keeps the parse O(1) in transcript size.
fill=$(tail -n "$TAIL_LINES" "$transcript" 2>/dev/null | "$JQ_BIN" -s '
  [.[] | select(.type? == "assistant") | .message.usage? | select(. != null)] | last
  | if . == null then 0
    else (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
    end' 2>/dev/null) || exit 0
case "$fill" in ''|*[!0-9]*) exit 0 ;; esac
[ "$fill" -ge "$THRESHOLD" ] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
: > "$flag"

cwd=$(printf '%s' "$payload" | "$JQ_BIN" -er '.cwd // empty' 2>/dev/null) || cwd=""
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
"$DISPATCH" handoff --cwd "$cwd" >/dev/null 2>&1 || true

# shellcheck disable=SC2016  # single-quoted jq program: \($fill) is jq interpolation, not shell
"$JQ_BIN" -nc --arg fill "$fill" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("context-handoff-watch: session context is at \($fill) tokens (>= 75k). Run the freshness checkpoint now — update CODING_MEMORY.md, commit, push — then tell the user a handoff pane is ready: pressing Enter in it starts the fresh session.")
  }
}'
exit 0
