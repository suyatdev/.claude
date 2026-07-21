#!/usr/bin/env bash
# pane-dispatch-guard.test.sh — feeds PreToolUse JSON on stdin (the production
# code path). Run: bash hooks/pane-dispatch-guard.test.sh
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/pane-dispatch-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export PANE_REDIRECT_CONF="$TMP/redirect.conf"
export PANE_STATE_DIR="$TMP/state"
export PANE_TERMINAL_DETECT="$TMP/detect.sh"
mkdir -p "$PANE_STATE_DIR"
printf '# comment\n\ncompliance-judge\nobservability-judge\n' > "$PANE_REDIRECT_CONF"
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"; chmod 700 "$TMP/detect.sh"
unset CLAUDE_PANE_AGENT CLAUDE_CODE_SESSION_ID

payload() { # $1 subagent_type, $2 session_id
  /usr/bin/jq -nc --arg t "$1" --arg s "$2" \
    '{hook_event_name:"PreToolUse",session_id:$s,tool_input:{subagent_type:$t,prompt:"x"}}'
}

pass=0; fail=0
run_case() { # $1 desc, $2 want-exit, $3 stdin-payload, then extra env as VAR=VAL...
  local desc="$1" want="$2" pl="$3"; shift 3
  printf '%s' "$pl" | env "$@" bash "$HOOK" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); fi
}

run_case "listed judge + terminal -> deny"   2 "$(payload observability-judge s1)" X=1
run_case "compliance-judge -> deny"          2 "$(payload compliance-judge s1)" X=1
run_case "Explore -> allow"                  0 "$(payload Explore s1)" X=1
run_case "unlisted type -> allow"            0 "$(payload general-purpose s1)" X=1
run_case "inside pane -> allow"              0 "$(payload observability-judge s1)" CLAUDE_PANE_AGENT=1
run_case "malformed stdin -> allow"          0 'not json' X=1
run_case "empty stdin -> allow"              0 '' X=1
run_case "missing conf -> allow"             0 "$(payload observability-judge s1)" PANE_REDIRECT_CONF="$TMP/absent.conf"

printf '#!/usr/bin/env bash\necho none\n' > "$TMP/detect.sh"
run_case "no terminal -> allow"              0 "$(payload observability-judge s1)" X=1
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"

# cooldown flags: stdin session id, then env session id, then divergence warning
: > "$PANE_STATE_DIR/adapter-failed-s1"
run_case "cooldown (stdin sid) -> allow"     0 "$(payload observability-judge s1)" X=1
rm -f "$PANE_STATE_DIR/adapter-failed-s1"
: > "$PANE_STATE_DIR/adapter-failed-env-sid"
run_case "cooldown (env sid) -> allow"       0 "$(payload observability-judge s1)" CLAUDE_CODE_SESSION_ID=env-sid
rm -f "$PANE_STATE_DIR/adapter-failed-env-sid"

out=$(printf '%s' "$(payload observability-judge s1)" | CLAUDE_CODE_SESSION_ID=other bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'session-id mismatch'; then
  printf 'ok   — sid divergence warned\n'; pass=$((pass+1))
else printf 'FAIL — sid divergence not warned (got: %s)\n' "$out"; fail=$((fail+1)); fi

out=$(printf '%s' "$(payload observability-judge s1)" | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'dispatch-pane-agent.sh' && printf '%s' "$out" | grep -q 'dispatching-pane-agents'; then
  printf 'ok   — deny message has dispatcher + skill pointers\n'; pass=$((pass+1))
else printf 'FAIL — deny message incomplete (got: %s)\n' "$out"; fail=$((fail+1)); fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
