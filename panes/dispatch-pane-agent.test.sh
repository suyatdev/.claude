#!/usr/bin/env bash
# dispatch-pane-agent.test.sh — dispatcher logic with stubbed detect + adapter.
# Run: bash panes/dispatch-pane-agent.test.sh
#
# File-wide: the `[ cond ] && ok || bad` harness is safe here — ok()/bad() both
# end in `pass=/fail=` arithmetic assignments that always return 0, so `bad`
# never runs after a passing `ok`. SC2015's "C may run when A is true" caveat
# does not apply.
# shellcheck disable=SC2015
set -u
PANES="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$PANES/dispatch-pane-agent.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export PANE_HOME="$PANES"
export PANE_STATE_DIR="$TMP/state"
export PANE_ADAPTERS_DIR="$TMP/adapters"
export PANE_TERMINAL_DETECT="$TMP/detect.sh"
export CLAUDE_CODE_SESSION_ID="test-session-123"

mkdir -p "$PANE_ADAPTERS_DIR"
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"; chmod 700 "$TMP/detect.sh"
# ok-adapter records its args and the role env, and succeeds; bad-adapter fails.
# The single quotes around ${PANE_AGENT_ROLE:-unset} are deliberate: it must reach
# the generated stub UNexpanded so the stub reads the dispatcher's exported value.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/adapter-args"\nprintf "%%s\\n" "${PANE_AGENT_ROLE:-unset}" > "%s/adapter-role"\necho surface:99\n' "$TMP" "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
PROMPT="$TMP/prompt.md"; printf 'judge this\n' > "$PROMPT"

pass=0; fail=0
ok()   { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL — %s%s\n' "$1" "${2:+ ($2)}"; fail=$((fail+1)); }

# --- dispatch happy path
out=$(bash "$DISPATCH" dispatch observability-judge --prompt-file "$PROMPT" --result-file "$TMP/r.md" --cwd "$TMP" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "dispatch exits 0" || bad "dispatch exits 0" "rc=$rc: $out"
printf '%s' "$out" | grep -q '^RESULT_FILE: ' && ok "prints RESULT_FILE" || bad "prints RESULT_FILE" "$out"
printf '%s' "$out" | grep -q '^PANE_REF: surface:99' && ok "prints adapter ref" || bad "prints adapter ref" "$out"

launcher=$(find "$PANE_STATE_DIR/runs" -name launch.sh | head -n 1)
[ -n "$launcher" ] && ok "launcher created" || bad "launcher created"
perms=$(stat -f '%Lp' "$launcher")
[ "$perms" = "700" ] && ok "launcher mode 700" || bad "launcher mode 700" "$perms"
run_dir_perms=$(stat -f '%Lp' "$(dirname "$launcher")")
[ "$run_dir_perms" = "700" ] && ok "run dir mode 700" || bad "run dir mode 700" "$run_dir_perms"
grep -q 'run-pane-agent.sh' "$launcher" && ok "launcher runs runner" || bad "launcher runs runner"
grep -q 'observability-judge' "$launcher" && ok "launcher carries agent type" || bad "launcher carries agent type"
grep -q 'prompt.md' "$launcher" && ok "prompt copied into run dir" || bad "prompt copied into run dir"
title=$(sed -n '2p' "$TMP/adapter-args")
[ "$title" = "observability-judge" ] && ok "bare agent-type title passed" || bad "bare agent-type title passed" "$title"

role_seen=$(cat "$TMP/adapter-role" 2>/dev/null)
[ "$role_seen" = "aux" ] && ok "role defaults to aux" || bad "role defaults to aux" "$role_seen"

# --- --role validation and export
# Test-only plan deviation: the brief's `[ $? -eq 0 ]` trips SC2181 after a
# command substitution; captured into rc first, matching the happy-path idiom above.
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/role1.md" --cwd "$TMP" --role implementer 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "--role implementer accepted" || bad "--role implementer accepted" "rc=$rc: $out"
[ "$(cat "$TMP/adapter-role" 2>/dev/null)" = "implementer" ] && ok "implementer role exported" || bad "implementer role exported"
rm -f "$TMP/adapter-args"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/role2.md" --cwd "$TMP" --role wizard >/dev/null 2>&1
[ $? -eq 64 ] && ok "garbage --role -> usage exit 64" || bad "garbage --role -> usage exit 64"
[ ! -f "$TMP/adapter-args" ] && ok "garbage --role never reaches adapter" || bad "garbage --role never reaches adapter"

# --- validation failures
bash "$DISPATCH" dispatch 'x;rm' --prompt-file "$PROMPT" >/dev/null 2>&1
[ $? -eq 64 ] && ok "bad agent-type rejected" || bad "bad agent-type rejected"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$TMP/absent" >/dev/null 2>&1
[ $? -eq 64 ] && ok "missing prompt rejected" || bad "missing prompt rejected"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --cwd "$TMP/nodir" >/dev/null 2>&1
[ $? -eq 64 ] && ok "bad cwd rejected" || bad "bad cwd rejected"
touch "$TMP/r.md"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/r.md" --cwd "$TMP" >/dev/null 2>&1
[ $? -eq 65 ] && ok "existing result file refused" || bad "existing result file refused"

# --- no terminal
printf '#!/usr/bin/env bash\necho none\n' > "$TMP/detect.sh"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/r2.md" --cwd "$TMP" >/dev/null 2>&1
[ $? -eq 3 ] && ok "no terminal -> exit 3, no cooldown" || bad "no terminal -> exit 3"
[ ! -f "$PANE_STATE_DIR/adapter-failed-test-session-123" ] && ok "no cooldown on none" || bad "no cooldown on none"
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"

# --- adapter failure writes the cooldown flag
printf '#!/usr/bin/env bash\nexit 1\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/r3.md" --cwd "$TMP" >/dev/null 2>&1
[ $? -eq 4 ] && ok "adapter failure -> exit 4" || bad "adapter failure -> exit 4"
[ -f "$PANE_STATE_DIR/adapter-failed-test-session-123" ] && ok "cooldown flag written" || bad "cooldown flag written"

# --- stale-state housekeeping (>7 days old gets removed)
OLD="$PANE_STATE_DIR/runs/1000000000-1-1"
mkdir -p "$OLD"; touch -t 202001010000 "$OLD"
touch -t 202001010000 "$PANE_STATE_DIR/adapter-failed-ancient"
printf '#!/usr/bin/env bash\necho surface:1\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/r4.md" --cwd "$TMP" >/dev/null 2>&1
[ ! -d "$OLD" ] && ok "stale run dir cleaned" || bad "stale run dir cleaned"
[ ! -f "$PANE_STATE_DIR/adapter-failed-ancient" ] && ok "stale flag cleaned" || bad "stale flag cleaned"

# --- wait
RF="$TMP/wait-result.md"
printf 'verdict body\nPANE_RESULT: DONE\n' > "$RF"
out=$(bash "$DISPATCH" wait --result-file "$RF" --timeout 5); rc=$?
[ "$rc" -eq 0 ] && ok "wait DONE -> 0" || bad "wait DONE -> 0" "rc=$rc"
printf '%s' "$out" | grep -q 'verdict body' && ok "wait prints content" || bad "wait prints content"
RF2="$TMP/wait-failed.md"
printf 'sad\nPANE_RESULT: FAILED\n' > "$RF2"
bash "$DISPATCH" wait --result-file "$RF2" --timeout 5 >/dev/null; rc=$?
[ "$rc" -eq 1 ] && ok "wait FAILED -> 1" || bad "wait FAILED -> 1" "rc=$rc"
printf 'body without sentinel\n' > "$TMP/wait-partial.md"
# CMUX_PANEL_ID= empties the var for this one command so wait takes the sleep
# branch regardless of the ambient environment (deliberate, not a typo).
# shellcheck disable=SC1007
CMUX_PANEL_ID= bash "$DISPATCH" wait --result-file "$TMP/wait-partial.md" --timeout 3 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "wait no-sentinel -> timeout 2" || bad "wait no-sentinel -> timeout 2" "rc=$rc"
# shellcheck disable=SC1007
CMUX_PANEL_ID= bash "$DISPATCH" wait --result-file "$TMP/never.md" --timeout 3 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "wait absent-file -> timeout 2" || bad "wait absent-file -> timeout 2" "rc=$rc"
bash "$DISPATCH" wait --result-file "$RF" --timeout xx >/dev/null 2>&1
[ $? -eq 64 ] && ok "non-numeric timeout rejected" || bad "non-numeric timeout rejected"

# --- handoff
# shellcheck disable=SC2016 # role expansion belongs to the generated stub (see line 25)
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/handoff-args"\nprintf "%%s\\n" "${PANE_AGENT_ROLE:-unset}" > "%s/adapter-role"\necho surface:7\n' "$TMP" "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
# Task-7 test-only plan deviation: the brief keyed the launcher search off
# "$TMP/adapter-args", but the no-terminal / adapter-failure / stale-state
# dispatches above each leave a launch.sh newer than adapter-args, so
# `find ... | head -n1` nondeterministically picked a run-pane-agent launcher.
# A fresh marker touched immediately before this dispatch makes the handoff
# launcher the only newer match.
touch "$TMP/handoff-marker"
out=$(bash "$DISPATCH" handoff --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "handoff exits 0" || bad "handoff exits 0" "rc=$rc: $out"
hl=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$TMP/handoff-marker" | head -n 1)
grep -q 'handoff-wrapper.sh' "$hl" && ok "handoff launcher runs wrapper" || bad "handoff launcher runs wrapper"
# Task-7 test-only plan deviation: brief read sed -n '1p' (= adapter argv[1]
# "open_pane"); the sanitized title is argv[2] per the Task 4 adapter contract
# (the same fix Task 6 applied to its dispatch-title assertion), so line 2.
htitle=$(sed -n '2p' "$TMP/handoff-args")
[ "$htitle" = "handoff: press Enter" ] && ok "handoff title" || bad "handoff title" "$htitle"
[ "$(cat "$TMP/adapter-role" 2>/dev/null)" = "aux" ] && ok "handoff role is aux" || bad "handoff role is aux"
bash "$DISPATCH" handoff --cwd "$TMP/nodir" >/dev/null 2>&1
[ $? -eq 64 ] && ok "handoff bad cwd rejected" || bad "handoff bad cwd rejected"

# --- F1 (regression): the default result path is unique per dispatch.
# Force the scratchpad-default branch by creating a real dir matching
# scratchpad_dir()'s hardcoded /private/tmp/claude-<uid>/*/<sid>/scratchpad glob,
# then dispatch the same agent type twice with no --result-file. Pre-fix, both
# resolve to $agent-$(date +%s).md and collide within one second.
printf '#!/usr/bin/env bash\necho surface:f1\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
F1SID="panetest-f1-$$-$RANDOM"
F1ROOT="/private/tmp/claude-$(id -u)/panetest-$$-$RANDOM"
F1SCRATCH="$F1ROOT/$F1SID/scratchpad"
mkdir -p "$F1SCRATCH"
rf1=$(CLAUDE_CODE_SESSION_ID="$F1SID" bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --cwd "$TMP" 2>/dev/null | sed -n 's/^RESULT_FILE: //p')
rf2=$(CLAUDE_CODE_SESSION_ID="$F1SID" bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --cwd "$TMP" 2>/dev/null | sed -n 's/^RESULT_FILE: //p')
case "$rf1" in "$F1SCRATCH"/pane-results/*) ok "default result lands in scratchpad pane-results" ;; *) bad "default result lands in scratchpad pane-results" "$rf1" ;; esac
{ [ -n "$rf1" ] && [ -n "$rf2" ] && [ "$rf1" != "$rf2" ]; } && ok "same-type default result paths are unique" || bad "same-type default result paths are unique" "rf1=$rf1 rf2=$rf2"
rm -rf "$F1ROOT"

# --- F4 (regression): a relative --result-file is canonicalized to an absolute
# path against the dispatcher's CWD, so dispatcher/runner/wait all name one file.
printf '#!/usr/bin/env bash\necho surface:f4\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
mkdir -p "$TMP/relcwd"
rfrel=$(cd "$TMP/relcwd" && bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file rel-out.md --cwd "$TMP" 2>/dev/null | sed -n 's/^RESULT_FILE: //p')
rfrel_expect="$(cd "$TMP/relcwd" && pwd)/rel-out.md"
{ [ -n "$rfrel" ] && [ "$rfrel" = "$rfrel_expect" ]; } && ok "relative --result-file canonicalized to absolute" || bad "relative --result-file canonicalized to absolute" "got=$rfrel want=$rfrel_expect"

# --- set-policy writes and validates the per-session policy file
export PANE_STATE_DIR="$TMP/state"   # already set at top; restated for locality
SP_SID="policy-sess-$$"
CLAUDE_CODE_SESSION_ID="$SP_SID" bash "$DISPATCH" set-policy inline >/dev/null 2>&1
[ "$(cat "$PANE_STATE_DIR/pane-policy-$SP_SID" 2>/dev/null)" = "inline" ] && ok "set-policy inline written" || bad "set-policy inline written"
CLAUDE_CODE_SESSION_ID="$SP_SID" bash "$DISPATCH" set-policy panes --max 3 >/dev/null 2>&1
[ "$(cat "$PANE_STATE_DIR/pane-policy-$SP_SID" 2>/dev/null)" = "panes max=3" ] && ok "set-policy panes max=3 written" || bad "set-policy panes max=3 written"
# Important-1 repro: a zero-padded N must be normalized to canonical base-10
# at write time, else the guard (which does not accept padded ints) loops the
# session into "ask" forever even though set-policy reported success.
CLAUDE_CODE_SESSION_ID="$SP_SID" bash "$DISPATCH" set-policy panes --max 03 >/dev/null 2>&1
sp_got=$(cat "$PANE_STATE_DIR/pane-policy-$SP_SID" 2>/dev/null)
[ "$sp_got" = "panes max=3" ] && ok "set-policy panes --max 03 normalized" || bad "set-policy panes --max 03 normalized" "$sp_got"
CLAUDE_CODE_SESSION_ID="$SP_SID" bash "$DISPATCH" set-policy panes --max 08 >/dev/null 2>&1
sp_got=$(cat "$PANE_STATE_DIR/pane-policy-$SP_SID" 2>/dev/null)
[ "$sp_got" = "panes max=8" ] && ok "set-policy panes --max 08 normalized" || bad "set-policy panes --max 08 normalized" "$sp_got"
# T2 carry-forward A: pin the specific cause, not just die's generic exit 64.
out=$(bash "$DISPATCH" set-policy panes --max 0 2>&1); rc=$?
{ [ "$rc" -eq 64 ] && printf '%s' "$out" | grep -q 'out of range'; } \
  && ok "set-policy max=0 rejected (out of range)" || bad "set-policy max=0 rejected (out of range)" "rc=$rc: $out"
out=$(bash "$DISPATCH" set-policy panes --max 99 2>&1); rc=$?
{ [ "$rc" -eq 64 ] && printf '%s' "$out" | grep -q 'out of range'; } \
  && ok "set-policy max=99 (>16) rejected (out of range)" || bad "set-policy max=99 (>16) rejected (out of range)" "rc=$rc: $out"
out=$(bash "$DISPATCH" set-policy panes --max abc 2>&1); rc=$?
{ [ "$rc" -eq 64 ] && printf '%s' "$out" | grep -q 'whole number'; } \
  && ok "set-policy non-numeric max rejected (whole number)" || bad "set-policy non-numeric max rejected (whole number)" "rc=$rc: $out"

# --- T2 carry-forward B: read_policy direct branch coverage (5 branches).
# Sources everything above the CLI dispatch (the stable `cmd=` line) so the
# function/constant definitions load without running the script's case
# statement (which would `die`/exit on an empty or bogus $1).
RP_DIR="$TMP/read_policy_cases"; mkdir -p "$RP_DIR"
call_read_policy() { f="$1" bash -c "$(sed '/^cmd=/,$d' "$DISPATCH")"$'\nread_policy "$f"'; }

printf 'inline\n' > "$RP_DIR/inline"
rp_got=$(call_read_policy "$RP_DIR/inline")
[ "$rp_got" = "inline" ] && ok "read_policy: inline" || bad "read_policy: inline" "$rp_got"

printf 'panes max=5\n' > "$RP_DIR/valid"
rp_got=$(call_read_policy "$RP_DIR/valid")
[ "$rp_got" = "panes max=5" ] && ok "read_policy: valid panes max=N" || bad "read_policy: valid panes max=N" "$rp_got"

printf 'panes max=99\n' > "$RP_DIR/oorange"
rp_got=$(call_read_policy "$RP_DIR/oorange")
[ -z "$rp_got" ] && ok "read_policy: out-of-range N -> empty" || bad "read_policy: out-of-range N -> empty" "$rp_got"

printf 'garbage\n' > "$RP_DIR/malformed"
rp_got=$(call_read_policy "$RP_DIR/malformed")
[ -z "$rp_got" ] && ok "read_policy: malformed -> empty" || bad "read_policy: malformed -> empty" "$rp_got"

rp_got=$(call_read_policy "$RP_DIR/missing")
[ -z "$rp_got" ] && ok "read_policy: missing file -> empty" || bad "read_policy: missing file -> empty" "$rp_got"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
