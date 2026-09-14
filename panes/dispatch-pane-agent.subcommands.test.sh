#!/usr/bin/env bash
# dispatch-pane-agent.subcommands.test.sh — wait, handoff.
# Run: bash panes/dispatch-pane-agent.subcommands.test.sh
#
# File-wide: the `[ cond ] && ok || bad` harness is safe here — ok()/bad() both
# end in `pass=/fail=` arithmetic assignments that always return 0, so `bad`
# never runs after a passing `ok`. SC2015's "C may run when A is true" caveat
# does not apply.
# shellcheck disable=SC2015
set -u
# shellcheck source=/dev/null
. "$(dirname "$0")/test-lib.sh"
PANES="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$PANES/dispatch-pane-agent.sh"

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


tl_finish
