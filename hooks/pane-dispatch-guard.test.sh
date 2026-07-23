#!/usr/bin/env bash
# pane-dispatch-guard.test.sh — feeds PreToolUse JSON on stdin (the production
# code path). Run: bash hooks/pane-dispatch-guard.test.sh
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/pane-dispatch-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export PANE_REDIRECT_CONF="$TMP/redirect.conf"
export PANE_INPROCESS_CONF="$TMP/inprocess.conf"
export PANE_STATE_DIR="$TMP/state"
export PANE_TERMINAL_DETECT="$TMP/detect.sh"
mkdir -p "$PANE_STATE_DIR"
printf '# comment\n\ncompliance-judge\nobservability-judge\n' > "$PANE_REDIRECT_CONF"
printf '# read-only in-process set\nExplore\nPlan\n' > "$PANE_INPROCESS_CONF"
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"; chmod 700 "$TMP/detect.sh"
unset CLAUDE_PANE_AGENT CLAUDE_CODE_SESSION_ID

POLICY="$PANE_STATE_DIR/pane-policy-s1"

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

# read-only lane — always in-process, even with a panes policy set
printf 'panes max=3\n' > "$POLICY"
run_case "Explore -> allow in-process"        0 "$(payload Explore s1)" X=1
run_case "Plan -> allow in-process"           0 "$(payload Plan s1)" X=1
# judge lane — always paned, regardless of policy
run_case "judge under panes -> deny"          2 "$(payload compliance-judge s1)" X=1
printf 'inline\n' > "$POLICY"
run_case "judge under inline -> deny"         2 "$(payload observability-judge s1)" X=1
rm -f "$POLICY"
run_case "judge with no policy -> deny"       2 "$(payload compliance-judge s1)" X=1
# governed worker lane
run_case "worker no policy -> deny (ask)"     2 "$(payload general-purpose s1)" X=1
printf 'inline\n' > "$POLICY"
run_case "worker under inline -> allow"       0 "$(payload general-purpose s1)" X=1
printf 'panes max=2\n' > "$POLICY"
run_case "worker under panes -> deny (redirect)" 2 "$(payload general-purpose s1)" X=1
printf 'garbage line\n' > "$POLICY"
run_case "worker malformed policy -> deny (ask)" 2 "$(payload general-purpose s1)" X=1
rm -f "$POLICY"

# Important-1 repro: a legacy zero-padded policy file (pre-fix `set-policy`
# could write "panes max=03") must still be recognized as valid -- not looped
# into "ask" forever. Checks the message shape, not just the exit code: both
# ask and redirect exit 2, so the discriminator is which guidance fires.
printf 'panes max=03\n' > "$POLICY"
out=$(printf '%s' "$(payload general-purpose s1)" | bash "$HOOK" 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'dispatch-pane-agent.sh' \
   && ! printf '%s' "$out" | grep -q 'AskUserQuestion'; then
  printf 'ok   — legacy zero-padded policy (panes max=03) redirects, not ask\n'; pass=$((pass+1))
else printf 'FAIL — legacy zero-padded policy not recognized (rc=%s got: %s)\n' "$rc" "$out"; fail=$((fail+1)); fi
rm -f "$POLICY"

# Important-2 repro: a stale `nosession` policy must NOT override a malformed
# policy at the real session key -- that silently leaks another session's
# policy and contradicts "malformed -> ask" (Global Constraint safe-degrade).
printf 'garbage line\n' > "$POLICY"
printf 'inline\n' > "$PANE_STATE_DIR/pane-policy-nosession"
run_case "malformed primary + stale nosession -> deny (ask), no leak" 2 "$(payload general-purpose s1)" X=1
rm -f "$POLICY" "$PANE_STATE_DIR/pane-policy-nosession"

# fail-open floor still holds
run_case "inside pane -> allow"               0 "$(payload general-purpose s1)" CLAUDE_PANE_AGENT=1
run_case "malformed stdin -> allow"           0 'not json' X=1
run_case "empty stdin -> allow"               0 '' X=1

printf '#!/usr/bin/env bash\necho none\n' > "$TMP/detect.sh"
run_case "no terminal -> allow"               0 "$(payload observability-judge s1)" X=1
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"

# cooldown flags: stdin session id, then env session id, then divergence warning
: > "$PANE_STATE_DIR/adapter-failed-s1"
run_case "cooldown (stdin sid) -> allow"     0 "$(payload observability-judge s1)" X=1
rm -f "$PANE_STATE_DIR/adapter-failed-s1"
: > "$PANE_STATE_DIR/adapter-failed-env-sid"
run_case "cooldown (env sid) -> allow"       0 "$(payload observability-judge s1)" CLAUDE_CODE_SESSION_ID=env-sid
rm -f "$PANE_STATE_DIR/adapter-failed-env-sid"
# F2 (regression): the dispatcher's empty-session fallback writes
# adapter-failed-nosession (CLAUDE_CODE_SESSION_ID unset); the guard must honor
# that key too, else the env-drift degrade case is a deny loop.
: > "$PANE_STATE_DIR/adapter-failed-nosession"
run_case "cooldown (nosession key) -> allow" 0 "$(payload observability-judge s1)" X=1
rm -f "$PANE_STATE_DIR/adapter-failed-nosession"

# A missing conf is never a hard error: the type is simply unlisted for that lane
# and falls through to the policy (inline here), which allows in-process.
printf 'inline\n' > "$POLICY"
run_case "missing redirect conf -> policy lane"  0 "$(payload observability-judge s1)" PANE_REDIRECT_CONF="$TMP/absent.conf"
# Minor-4: a "panes" (not inline) policy here so a correct guard MUST exit 2
# once Explore falls through the missing conf into the governed Lane 3 --
# proving in_conf's missing-file branch does NOT quietly match everything.
# (Lane 1's bypass-of-policy behavior is proven separately by "Explore ->
# allow in-process" near the top of this file, which runs under a panes
# policy too.)
printf 'panes max=2\n' > "$POLICY"
run_case "missing inprocess conf -> falls to policy lane (panes)" 2 "$(payload Explore s1)" PANE_INPROCESS_CONF="$TMP/absent.conf"
rm -f "$POLICY"

out=$(printf '%s' "$(payload observability-judge s1)" | CLAUDE_CODE_SESSION_ID=other bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'session-id mismatch'; then
  printf 'ok   — sid divergence warned\n'; pass=$((pass+1))
else printf 'FAIL — sid divergence not warned (got: %s)\n' "$out"; fail=$((fail+1)); fi

out=$(printf '%s' "$(payload observability-judge s1)" | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'dispatch-pane-agent.sh' && printf '%s' "$out" | grep -q 'dispatching-pane-agents'; then
  printf 'ok   — deny message has dispatcher + skill pointers\n'; pass=$((pass+1))
else printf 'FAIL — deny message incomplete (got: %s)\n' "$out"; fail=$((fail+1)); fi

# no-policy worker -> ASK guidance names AskUserQuestion + set-policy
rm -f "$POLICY"
out=$(printf '%s' "$(payload general-purpose s1)" | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'AskUserQuestion' && printf '%s' "$out" | grep -q 'set-policy'; then
  printf 'ok   — no-policy worker gets ask guidance\n'; pass=$((pass+1))
else printf 'FAIL — ask guidance incomplete (got: %s)\n' "$out"; fail=$((fail+1)); fi
# worker under panes -> REDIRECT guidance names the dispatcher + skill
printf 'panes max=2\n' > "$POLICY"
out=$(printf '%s' "$(payload general-purpose s1)" | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'dispatch-pane-agent.sh' && printf '%s' "$out" | grep -q 'dispatching-pane-agents'; then
  printf 'ok   — panes worker gets redirect guidance\n'; pass=$((pass+1))
else printf 'FAIL — redirect guidance incomplete (got: %s)\n' "$out"; fail=$((fail+1)); fi
rm -f "$POLICY"
# bounded N at READ time: an out-of-range max is "no policy" -> ask, never redirect
printf 'panes max=99\n' > "$POLICY"
out=$(printf '%s' "$(payload general-purpose s1)" | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'AskUserQuestion'; then
  printf 'ok   — out-of-range max falls back to ask guidance\n'; pass=$((pass+1))
else printf 'FAIL — out-of-range max not treated as no-policy (got: %s)\n' "$out"; fail=$((fail+1)); fi
rm -f "$POLICY"
# Minor-5a: max=17 is one past the 1..16 bound -> ask, not redirect. Kills the
# "widen the bound to 1[0-9]" mutant, which would wrongly accept 17-19.
printf 'panes max=17\n' > "$POLICY"
out=$(printf '%s' "$(payload general-purpose s1)" | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'AskUserQuestion'; then
  printf 'ok   — max=17 boundary falls back to ask guidance\n'; pass=$((pass+1))
else printf 'FAIL — max=17 boundary not treated as no-policy (got: %s)\n' "$out"; fail=$((fail+1)); fi
rm -f "$POLICY"

# Minor-5b: env_sid/nosession precedence (the session-key triple is a Global
# Constraint and was untested -- the suite unsets CLAUDE_CODE_SESSION_ID
# throughout, so set it explicitly here). env_sid's own policy must win over
# a stale nosession policy with a different value.
ESID="env-precedence-sid"
printf 'panes max=4\n' > "$PANE_STATE_DIR/pane-policy-$ESID"
printf 'inline\n' > "$PANE_STATE_DIR/pane-policy-nosession"
out=$(printf '%s' "$(payload general-purpose s1)" | CLAUDE_CODE_SESSION_ID="$ESID" bash "$HOOK" 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'dispatch-pane-agent.sh' \
   && ! printf '%s' "$out" | grep -q 'AskUserQuestion'; then
  printf 'ok   — env_sid policy takes precedence over stale nosession\n'; pass=$((pass+1))
else printf 'FAIL — env_sid precedence over nosession (rc=%s got: %s)\n' "$rc" "$out"; fail=$((fail+1)); fi
rm -f "$PANE_STATE_DIR/pane-policy-$ESID"

# Minor-5c: nosession IS still consulted as a genuine fallback when env_sid is
# empty and the sid key has no policy file. Kills the "drop nosession from the
# policy loop" mutant (which this suite's other cases don't exercise, since
# they either supply no nosession file or supply one alongside a valid sid
# file that wins first).
printf 'panes max=5\n' > "$PANE_STATE_DIR/pane-policy-nosession"
out=$(printf '%s' "$(payload general-purpose s1)" | bash "$HOOK" 2>&1 >/dev/null); rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'dispatch-pane-agent.sh' \
   && ! printf '%s' "$out" | grep -q 'AskUserQuestion'; then
  printf 'ok   — nosession fallback used when env_sid empty, sid has no policy\n'; pass=$((pass+1))
else printf 'FAIL — nosession fallback (rc=%s got: %s)\n' "$rc" "$out"; fail=$((fail+1)); fi
rm -f "$PANE_STATE_DIR/pane-policy-nosession"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
