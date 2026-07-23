#!/usr/bin/env bash
# pane-dispatch-guard.sh — PreToolUse hook, matcher "Task|Agent" (registered
# under both candidate tool names; only the one the installed CLI emits fires).
#
# Denies in-process dispatch of redirect-listed subagent types when a terminal
# pane can carry them instead, pointing the model at dispatch-pane-agent.sh.
# This is a momentum redirect, NOT a security boundary: it fails OPEN — any
# parse failure, missing conf, no terminal, or a prior adapter failure this
# session (cooldown flag) means "allow", which is exactly today's behavior.
# Deny only when ALL four spec conditions hold. Exit 0 allow, exit 2 deny.
set -u

CONF="${PANE_REDIRECT_CONF:-$HOME/.claude/panes/redirect-agents.conf}"
INPROCESS_CONF="${PANE_INPROCESS_CONF:-$HOME/.claude/panes/inprocess-agents.conf}"
STATE_DIR="${PANE_STATE_DIR:-$HOME/.claude/panes/state}"
DETECT="${PANE_TERMINAL_DETECT:-$HOME/.claude/panes/terminal-detect.sh}"
JQ_BIN="/usr/bin/jq"

# in_conf <conf-file> <type> -> 0 if the type is a non-comment line in the file.
in_conf() {
  local conf="$1" want="$2" line
  [ -f "$conf" ] || return 1
  while IFS= read -r line; do
    line="${line%%#*}"
    line=$(printf '%s' "$line" | tr -d '[:space:]')
    [ -n "$line" ] && [ "$line" = "$want" ] && return 0
  done < "$conf"
  return 1
}

# Condition: never fire inside a pane session (recursion guard).
[ -n "${CLAUDE_PANE_AGENT:-}" ] && exit 0

payload=""
if [ ! -t 0 ]; then payload=$(cat); fi
[ -n "$payload" ] || exit 0
[ -x "$JQ_BIN" ] || exit 0   # fail open

subagent_type=$(printf '%s' "$payload" | "$JQ_BIN" -er '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
[ -n "$subagent_type" ] || exit 0

# Lane 1: read-only helpers ALWAYS run in-process (independent of terminal/policy).
if in_conf "$INPROCESS_CONF" "$subagent_type"; then exit 0; fi

# Fail-open floor: no terminal, or a prior adapter failure this session -> allow.
term=$("$DETECT" 2>/dev/null) || exit 0
[ "$term" != "none" ] || exit 0

# The dispatcher (not a hook — no stdin session_id) keys its flag by
# $CLAUDE_CODE_SESSION_ID; hooks receive session_id on stdin. Check both, and
# surface any divergence (obs r2 advisory 2) instead of silently missing flags.
sid=$(printf '%s' "$payload" | "$JQ_BIN" -er '.session_id // empty' 2>/dev/null) || sid=""
env_sid="${CLAUDE_CODE_SESSION_ID:-}"
if [ -n "$sid" ] && [ -n "$env_sid" ] && [ "$sid" != "$env_sid" ]; then
  printf 'pane-dispatch-guard: session-id mismatch (stdin %s vs env %s) — cooldown flags may not line up.\n' "$sid" "$env_sid" >&2
fi
# "nosession" is the literal the dispatcher falls back to when
# CLAUDE_CODE_SESSION_ID is empty (obs final-review F2) — honor that flag too, or
# the env-drift degrade case loops (guard denies while dispatch keeps failing).
for key in "$sid" "$env_sid" nosession; do
  if [ -n "$key" ] && [ -f "$STATE_DIR/adapter-failed-$key" ]; then
    printf 'pane-dispatch-guard: a pane adapter failed earlier this session — allowing in-process dispatch.\n' >&2
    exit 0
  fi
done

# Lane 2: judges are ALWAYS paned, regardless of policy.
if in_conf "$CONF" "$subagent_type"; then
  {
    printf 'pane-dispatch-guard: "%s" is a judge — it always runs in its own terminal pane (%s), never in-process.\n' "$subagent_type" "$term"
    printf 'Redirect it to a pane:\n'
    printf '  1. Write the agent prompt to a file in the scratchpad.\n'
    # $HOME is shown literally in the guidance text, not expanded here (SC2016 deliberate).
    # shellcheck disable=SC2016
    printf '  2. "$HOME"/.claude/panes/dispatch-pane-agent.sh dispatch %s --prompt-file <f> [--cwd <repo>]\n' "$subagent_type"
    # shellcheck disable=SC2016
    printf '  3. "$HOME"/.claude/panes/dispatch-pane-agent.sh wait --result-file <RESULT_FILE printed by dispatch>\n'
    printf 'Procedure and fallback rules: load the dispatching-pane-agents skill.\n'
  } >&2
  exit 2
fi

# Lane 3: governed worker — consult the per-session policy (first matching key).
policy=""
for key in "$env_sid" "$sid" nosession; do
  [ -n "$key" ] || continue
  pf="$STATE_DIR/pane-policy-$key"
  [ -f "$pf" ] || continue
  line="$(head -n 1 "$pf" 2>/dev/null)"
  if [ "$line" = "inline" ]; then policy="inline"; break; fi
  if printf '%s' "$line" | grep -Eq '^panes max=([1-9]|1[0-6])$'; then policy="panes"; break; fi
done

case "$policy" in
  inline) exit 0 ;;   # worker fan-out runs in-process this session
  panes)
    {
      printf 'pane-dispatch-guard: session policy is "panes" — "%s" runs in a pane/tab, not in-process (%s).\n' "$subagent_type" "$term"
      printf '  1. Write the agent prompt to a file in the scratchpad.\n'
      # shellcheck disable=SC2016
      printf '  2. "$HOME"/.claude/panes/dispatch-pane-agent.sh dispatch %s --prompt-file <f> [--cwd <repo>]\n' "$subagent_type"
      # shellcheck disable=SC2016
      printf '  3. "$HOME"/.claude/panes/dispatch-pane-agent.sh wait --result-file <RESULT_FILE printed by dispatch>\n'
      printf 'The dispatcher owns pane-vs-tab and the max-N overflow. Load the dispatching-pane-agents skill.\n'
    } >&2
    exit 2 ;;
  *)  # no policy recorded (or malformed) -> ask once, then retry
    {
      printf 'pane-dispatch-guard: no pane-split policy set for this session — ask the user once.\n'
      printf '  1. Call AskUserQuestion: "inline" (workers in-process) or "panes" with a max N (suggest 3).\n'
      # shellcheck disable=SC2016
      printf '  2. Record it: "$HOME"/.claude/panes/dispatch-pane-agent.sh set-policy inline\n'
      # shellcheck disable=SC2016
      printf '     or:        "$HOME"/.claude/panes/dispatch-pane-agent.sh set-policy panes --max <N>\n'
      printf '  3. Retry this same dispatch; the guard now routes by the recorded policy.\n'
      printf 'Rationale and the three lanes: load the dispatching-pane-agents skill.\n'
    } >&2
    exit 2 ;;
esac
