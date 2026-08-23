#!/usr/bin/env bash
# context-handoff-watch.sh — PostToolUse hook, matcher "*". At >= threshold context
# tokens (input + cache_creation + cache_read of the transcript's last assistant
# usage entry — the statusline's orange line), once per session: write the
# fired-flag, prepare a press-Enter handoff pane, and nudge the freshness
# checkpoint via additionalContext.
#
# Threshold is model-dependent: 100k for Sonnet, 130k for Opus/Fable, 75k fallback.
# These are context-rot budgets, not window fractions -- see ADR 0035.
#
# ORDERING IS LOAD-BEARING (obs r2 advisory 1): this hook runs on every tool
# call in every repo, so the per-session fired-flag check comes BEFORE any
# transcript access — after firing once, the cost is one stat. Never blocks:
# every failure path exits 0 silently.
set -u
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

# Last assistant usage entry, and the last model id in the same window — one
# tail, one jq. The two are picked INDEPENDENTLY (last non-null usage, last
# non-null model), not read off a single turn: they coincide in every real
# transcript, but nothing here enforces that they must. tail keeps the parse
# O(1) in transcript size. Emitted as "<fill> <model>"; a model id never
# contains a space, and an absent one leaves the field empty.
# shellcheck disable=SC2016  # single-quoted jq program: \(...) is jq interpolation
meta=$(tail -n "$TAIL_LINES" "$transcript" 2>/dev/null | "$JQ_BIN" -rs '
  [.[] | select(.type? == "assistant") | .message? | select(. != null)] as $m
  | (([$m[] | .usage? | select(. != null)] | last) // {}) as $u
  | (([$m[] | .model? | select(. != null)] | last) // "") as $id
  | "\(($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) \($id)"
  ' 2>/dev/null) || exit 0
fill=${meta%% *}
model_id=${meta#* }
case "$fill" in ''|*[!0-9]*) exit 0 ;; esac

# Threshold scales with the model actually generating the tokens: 100k Sonnet,
# 130k Opus/Fable, 75k for anything unrecognised. The numbers are budgets for
# where answer quality decays, NOT fractions of the window -- rot does not scale
# with window size, so a 1M-context model gets no proportional allowance.
#
# The PostToolUse payload carries NO .model key (verified against a captured
# live payload), so the transcript is the only live source; settings.json .model
# is the fallback for a transcript whose assistant turns carry no model id.
if [ -z "$model_id" ] && [ -f "$HOME/.claude/settings.json" ]; then
  model_id=$("$JQ_BIN" -r '.model // empty' "$HOME/.claude/settings.json" 2>/dev/null) || true
fi
case "$model_id" in
  *[Ss]onnet*) THRESHOLD=100000 ;;
  *[Oo]pus*|*[Ff]able*) THRESHOLD=130000 ;;
  *) THRESHOLD=75000 ;;
esac

[ "$fill" -ge "$THRESHOLD" ] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
: > "$flag"

cwd=$(printf '%s' "$payload" | "$JQ_BIN" -er '.cwd // empty' 2>/dev/null) || cwd=""
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
# Condition the nudge text on whether the handoff pane was actually prepared
# (obs final-review F5): the failure is still swallowed so the hook's own
# plumbing stays silent, but we must not tell the user a pane is ready when it
# is not. Only the additionalContext wording changes; the hook still exits 0.
if "$DISPATCH" handoff --cwd "$cwd" >/dev/null 2>&1; then
  pane_note=" Then tell the user a handoff pane is ready: pressing Enter in it starts the fresh session."
else
  pane_note=" A handoff pane could not be prepared, so continue in this session after checkpointing."
fi

# shellcheck disable=SC2016  # single-quoted jq program: \($fill) is jq interpolation, not shell
"$JQ_BIN" -nc --arg fill "$fill" --arg thresh "$THRESHOLD" --arg pane "$pane_note" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("context-handoff-watch: session context is at \($fill) tokens (>= \($thresh)). Run the freshness checkpoint now — update the active feature card under docs/features/, commit, push." + $pane)
  }
}'
exit 0
