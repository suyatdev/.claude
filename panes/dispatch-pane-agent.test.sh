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
# ok-adapter records its args and succeeds; bad-adapter fails
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/adapter-args"\necho surface:99\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
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
[ "$title" = "pane: observability-judge" ] && ok "sanitized title passed" || bad "sanitized title passed" "$title"

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
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/handoff-args"\necho surface:7\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
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
bash "$DISPATCH" handoff --cwd "$TMP/nodir" >/dev/null 2>&1
[ $? -eq 64 ] && ok "handoff bad cwd rejected" || bad "handoff bad cwd rejected"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
