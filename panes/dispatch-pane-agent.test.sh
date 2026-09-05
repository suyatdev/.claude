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
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1
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

# --- Task 6: lane/session markers + live worker count (real run-dir fixtures)
export PANE_REDIRECT_CONF="$TMP/redirect.conf"   # dispatcher classifies lane via this
# M1: a comment-only line (must be ignored, never matched as an agent type), an
# inline comment on compliance-judge (drop the `${line%%#*}` strip and this
# entry misclassifies as a worker), and whitespace-padding on observability-judge
# (drop the `tr -d '[:space:]'` strip and this entry misclassifies too) — both
# strips are otherwise unexercised by a clean fixture and could be deleted
# without the suite noticing.
printf '# always-paned judges\ncompliance-judge   # spec compliance judge\n   observability-judge   \n' > "$PANE_REDIRECT_CONF"
CSID="count-sess-$$"
# Run ids come from mktemp, not $RANDOM: several call sites capture the dir with
# $(...), and a subshell's $RANDOM draw is lost to the parent, so the next
# fixture would silently reuse the same dir (that hazard already produced one
# false RED during Task 7 — "3 live" where the fixture meant 4). Harmless while
# every mk_run call site is a plain redirect; fixed so the next one cannot be
# poisoned. Same recipe as mk_run_ref below.
mk_run() { # $1 lane, $2 session, $3 exited(yes/no) -> makes a fake run dir
  local d
  mkdir -p "$PANE_STATE_DIR/runs"
  d="$(mktemp -d "$PANE_STATE_DIR/runs/$(date +%s)-$$-XXXXXX")"
  printf '%s\n' "$1" > "$d/lane"; printf '%s\n' "$2" > "$d/session"; printf 'surface:%s\n' "$RANDOM" > "$d/surface"
  [ "$3" = yes ] && printf 'DONE\n' > "$d/agent-exit"; printf '%s\n' "$d"
}
mk_run worker "$CSID" no  >/dev/null   # live worker 1
mk_run worker "$CSID" no  >/dev/null   # live worker 2
mk_run worker "$CSID" yes >/dev/null   # completed -> not counted
mk_run judge  "$CSID" no  >/dev/null   # judge -> not counted
mk_run worker other-sess no >/dev/null # other session -> not counted
n=$(CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" count-workers 2>/dev/null)
[ "$n" = "2" ] && ok "count_live_workers excludes exited/judge/other-session" || bad "count_live_workers" "got $n want 2"

# --- Task 6: judge dispatch -> open_pane, lane=judge, never blocked by policy count
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/adapter-args"\necho surface:J1\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
# Test-only plan deviation: the brief keyed the lane-file search off "$PROMPT",
# but the mk_run judge fixture above also creates a lane file containing
# "judge" newer than $PROMPT, so the assertion would pass before the dispatcher
# writes any lane marker (vacuous). A marker touched immediately before this
# dispatch makes the dispatcher's run dir the only newer match (the same
# pattern as handoff-marker above).
touch "$TMP/judge-lane-marker"
out=$(CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" dispatch compliance-judge --prompt-file "$PROMPT" --result-file "$TMP/j.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "judge dispatch under panes max=1 still opens a pane" || bad "judge dispatch under panes" "rc=$rc: $out"
jd=$(find "$PANE_STATE_DIR/runs" -name lane -newer "$TMP/judge-lane-marker" -exec grep -l judge {} \; | head -n1)
[ -n "$jd" ] && ok "judge run tagged lane=judge" || bad "judge run tagged lane=judge"
# Test-only additions beyond the brief's sketch: the session and surface
# markers are Task 6 deliverables too — assert them on the same run dir.
jrd="$(dirname "${jd:-/nonexistent}")"
[ "$(cat "$jrd/session" 2>/dev/null)" = "$CSID" ] && ok "judge run tagged session key" || bad "judge run tagged session key" "$(cat "$jrd/session" 2>/dev/null)"
[ "$(cat "$jrd/surface" 2>/dev/null)" = "surface:J1" ] && ok "surface ref recorded after open_pane" || bad "surface ref recorded after open_pane" "$(cat "$jrd/surface" 2>/dev/null)"

# --- M1: the whitespace-padded observability-judge conf entry ("   observability-judge   ")
# is still recognized as always-paned — never gated — under the same panes
# max=1 + 2-live-workers conditions as the compliance-judge case above.
touch "$TMP/obs-judge-lane-marker"
out=$(CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" dispatch observability-judge --prompt-file "$PROMPT" --result-file "$TMP/oj.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "observability-judge (whitespace-padded conf entry) opens a pane" || bad "observability-judge (whitespace-padded conf entry) opens a pane" "rc=$rc: $out"
ojd=$(find "$PANE_STATE_DIR/runs" -name lane -newer "$TMP/obs-judge-lane-marker" -exec grep -l judge {} \; | head -n1)
[ -n "$ojd" ] && ok "observability-judge run tagged lane=judge" || bad "observability-judge run tagged lane=judge"

# --- Task 7: a worker at/over panes max=1 with 2 live worker panes overflows to
# a TAB in one of them (this replaces Task 6's interim exit-3 assertion).
out=$(CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/w.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "worker over max overflows to a tab (exit 0)" || bad "worker over max overflows to a tab" "rc=$rc: $out"
[ "$(sed -n '1p' "$TMP/adapter-args" 2>/dev/null)" = "open_tab" ] && ok "over-max dispatch calls the adapter open_tab verb" || bad "over-max calls open_tab" "$(sed -n '1p' "$TMP/adapter-args" 2>/dev/null)"
[ ! -f "$PANE_STATE_DIR/adapter-failed-$CSID" ] && ok "over-max does not write cooldown" || bad "over-max writes no cooldown"

# --- Task 6a (C1 regression): a worker strictly UNDER max opens a pane (exit 0).
# Isolated session key + a single live-worker fixture so this is unaffected by
# the CSID fixtures above; pre-fix, the dispatching run counts itself as an
# already-live worker (1 fixture + itself = 2 >= max 2), wrongly gating it.
UMAX_SID="under-max-$$"
mk_run worker "$UMAX_SID" no >/dev/null   # one live worker fixture
CLAUDE_CODE_SESSION_ID="$UMAX_SID" bash "$DISPATCH" set-policy panes --max 2 >/dev/null 2>&1
rm -f "$TMP/adapter-args"
out=$(CLAUDE_CODE_SESSION_ID="$UMAX_SID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/uw.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "worker under max opens a pane" || bad "worker under max opens a pane" "rc=$rc: $out"
# T6a-Minor: rc 0 alone does not prove the adapter ran. No clean exit-0 path
# skips it today, but a refactor could open one, so assert the pane was really
# opened — the ref the adapter printed, and the verb it was called with — to
# match the happy-path test's rigor.
printf '%s' "$out" | grep -q '^PANE_REF: surface:J1' && ok "worker under max actually reaches the adapter" || bad "worker under max reaches the adapter" "$out"
[ "$(sed -n '1p' "$TMP/adapter-args" 2>/dev/null)" = "open_pane" ] && ok "worker under max uses the open_pane verb" || bad "worker under max uses open_pane" "$(sed -n '1p' "$TMP/adapter-args" 2>/dev/null)"
# Obs-judge finding 2: the decisive computation — count, max in force, outcome —
# must be recorded, not just the resulting markers. Pane case: no tab target.
printf '%s' "$out" | grep -q '^ROUTE: lane=worker live=1 max=2 kind=pane target=-$' \
  && ok "under-max dispatch records the routing decision (live/max/pane)" || bad "under-max records the routing decision" "$out"

# --- Task 7 fixtures: like mk_run but with an explicit surface ref and an
# explicit surface KIND (pane|tab; "" writes no kind marker, which must be read
# as "pane" so every pre-Task-7 fixture above stays valid). Run ids come from
# mktemp, not $RANDOM or a counter: several call sites capture the dir with
# $(...), and a subshell's $RANDOM draw / counter bump is lost to the parent, so
# the next fixture would silently reuse the same dir.
mk_run_ref() { # $1 lane, $2 session, $3 exited(yes/no), $4 surface-ref(""=none), $5 kind(""=none)
  local d
  mkdir -p "$PANE_STATE_DIR/runs"
  d="$(mktemp -d "$PANE_STATE_DIR/runs/$(date +%s)-$$-t7XXXXXX")"
  printf '%s\n' "$1" > "$d/lane"; printf '%s\n' "$2" > "$d/session"
  [ -n "$4" ] && printf '%s\n' "$4" > "$d/surface"
  [ -n "${5:-}" ] && printf '%s\n' "$5" > "$d/kind"
  [ "$3" = yes ] && printf 'DONE\n' > "$d/agent-exit"
  printf '%s\n' "$d"
}

# --- Task 7: overflow targets a live worker pane's surface, round-robin, and
# the resulting tab run does not itself consume a worker slot.
# The fake adapter answers BOTH verbs and records each verb's argv separately.
# shellcheck disable=SC2016 # $1/$@ must reach the generated stub unexpanded (see line 25)
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) printf "%%s\\n" "$@" > "%s/adapter-args"; echo surface:P9 ;;\n  open_tab)  printf "%%s\\n" "$@" > "%s/tab-args"; echo surface:T1 ;;\n  *) exit 64 ;;\nesac\n' "$TMP" "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
OSID="overflow-sess-$$"
CLAUDE_CODE_SESSION_ID="$OSID" bash "$DISPATCH" set-policy panes --max 2 >/dev/null 2>&1
mk_run_ref worker "$OSID" no surface:AA "" >/dev/null   # live worker pane 1
mk_run_ref worker "$OSID" no surface:BB "" >/dev/null   # live worker pane 2
rm -f "$TMP/tab-args" "$TMP/adapter-args"
out=$(CLAUDE_CODE_SESSION_ID="$OSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/o1.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "overflow worker exits 0 (tab)" || bad "overflow worker exits 0" "rc=$rc: $out"
# open_tab <surface> <title> <launcher>: argv[2] = surface, argv[3] = title.
t1=$(sed -n '2p' "$TMP/tab-args" 2>/dev/null)
case "$t1" in surface:AA|surface:BB) ok "overflow open_tab targets a live worker surface" ;; *) bad "overflow open_tab targets a live worker surface" "$t1" ;; esac
[ "$(sed -n '3p' "$TMP/tab-args" 2>/dev/null)" = "general-purpose" ] && ok "overflow open_tab carries the sanitized title" || bad "overflow open_tab title" "$(sed -n '3p' "$TMP/tab-args" 2>/dev/null)"
printf '%s' "$out" | grep -q '^PANE_REF: surface:T1' && ok "overflow prints the new tab ref" || bad "overflow prints tab ref" "$out"
# Obs-judge finding 2, tab case: the line must name the surface actually tabbed
# into, so a routing surprise never has to be re-derived by hand.
printf '%s' "$out" | grep -qE '^ROUTE: lane=worker live=2 max=2 kind=tab target=surface:(AA|BB)$' \
  && ok "overflow records the routing decision (live/max/target)" || bad "overflow records the routing decision" "$out"
# Round-robin: the next overflow must land on the OTHER live worker pane.
out=$(CLAUDE_CODE_SESSION_ID="$OSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/o2.md" --cwd "$TMP" 2>&1); rc=$?
t2=$(sed -n '2p' "$TMP/tab-args" 2>/dev/null)
{ [ "$rc" -eq 0 ] && [ -n "$t2" ] && [ "$t2" != "$t1" ]; } && ok "round-robin rotates to the other live worker pane" || bad "round-robin rotates to the other live worker pane" "first=$t1 second=$t2 rc=$rc"
# Correction A: a run living in a tab is not a pane, so it must not count toward
# N. Two overflow tabs are now live on top of the two panes; the count is 2.
n=$(CLAUDE_CODE_SESSION_ID="$OSID" bash "$DISPATCH" count-workers 2>/dev/null)
[ "$n" = "2" ] && ok "overflow tab runs are not counted as live worker panes" || bad "overflow tab runs not counted" "got $n want 2"

# --- Task 7 / Correction A: spec Gherkin "A freed worker pane is reclaimed
# rather than tabbed". panes max=3, three live worker panes plus two live
# tab runs; free one pane -> live PANE count is 2 (< 3) so the next worker must
# open a PANE. Counting the tab runs would report 4 and wrongly overflow.
FSID="freed-pane-$$"
CLAUDE_CODE_SESSION_ID="$FSID" bash "$DISPATCH" set-policy panes --max 3 >/dev/null 2>&1
mk_run_ref worker "$FSID" no surface:FP1 pane >/dev/null
mk_run_ref worker "$FSID" no surface:FP2 pane >/dev/null
freed=$(mk_run_ref worker "$FSID" no surface:FP3 pane)
mk_run_ref worker "$FSID" no surface:FT1 tab >/dev/null
mk_run_ref worker "$FSID" no surface:FT2 tab >/dev/null
printf 'DONE\n' > "$freed/agent-exit"    # that pane's agent completed -> slot freed
rm -f "$TMP/tab-args" "$TMP/adapter-args"
out=$(CLAUDE_CODE_SESSION_ID="$FSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/f1.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "freed-pane dispatch exits 0" || bad "freed-pane dispatch exits 0" "rc=$rc: $out"
[ "$(sed -n '1p' "$TMP/adapter-args" 2>/dev/null)" = "open_pane" ] && ok "a freed worker pane is reclaimed (open_pane, not open_tab)" || bad "a freed worker pane is reclaimed" "verb=$(sed -n '1p' "$TMP/adapter-args" 2>/dev/null) tab-target=$(sed -n '2p' "$TMP/tab-args" 2>/dev/null)"
[ ! -f "$TMP/tab-args" ] && ok "freed-pane dispatch never calls open_tab" || bad "freed-pane dispatch never calls open_tab"

# --- Task 7 / Correction A: a tab run is never an overflow TARGET (open_tab
# into a tab would nest a tab in a tab). One live worker pane + one live tab run
# at panes max=1: TWO consecutive overflows must BOTH target the pane. Two, not
# one: if tab runs were eligible the round-robin would necessarily hand one of
# the two dispatches a ref that is not the pane's.
TSID="tab-target-$$"
CLAUDE_CODE_SESSION_ID="$TSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
mk_run_ref worker "$TSID" no surface:KP pane >/dev/null
mk_run_ref worker "$TSID" no surface:KT tab  >/dev/null
rm -f "$TMP/tab-args"
CLAUDE_CODE_SESSION_ID="$TSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/t1.md" --cwd "$TMP" >/dev/null 2>&1
k1=$(sed -n '2p' "$TMP/tab-args" 2>/dev/null)
CLAUDE_CODE_SESSION_ID="$TSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/t2.md" --cwd "$TMP" >/dev/null 2>&1
k2=$(sed -n '2p' "$TMP/tab-args" 2>/dev/null)
{ [ "$k1" = "surface:KP" ] && [ "$k2" = "surface:KP" ]; } && ok "overflow never targets a tab run surface" || bad "overflow never targets a tab run surface" "first=$k1 second=$k2"

# --- Task 7 / Correction B: an overflow with no selectable target degrades this
# spawn to in-process (exit 3, no cooldown — capacity, not an adapter failure)
# and adds no phantom. The target is resolved BEFORE the lane/session markers
# are written, so this dispatch leaves no lane=worker run dir at all.
NOSID="no-target-$$"
printf '#!/usr/bin/env bash\necho surface:Z1\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
CLAUDE_CODE_SESSION_ID="$NOSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
mk_run_ref worker "$NOSID" no "" pane >/dev/null   # live worker pane whose surface write never landed
CLAUDE_CODE_SESSION_ID="$NOSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/n1.md" --cwd "$TMP" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "overflow with no selectable target -> exit 3 (in-process)" || bad "no-target overflow -> exit 3" "rc=$rc"
[ ! -f "$PANE_STATE_DIR/adapter-failed-$NOSID" ] && ok "no-target overflow writes no cooldown" || bad "no-target overflow writes no cooldown"
n=$(CLAUDE_CODE_SESSION_ID="$NOSID" bash "$DISPATCH" count-workers 2>/dev/null)
[ "$n" = "1" ] && ok "no-target overflow adds no phantom live worker" || bad "no-target overflow adds no phantom" "got $n want 1 (the surfaceless fixture only)"

# --- Task 7 / Correction B: a dispatch that fails to OPEN its surface must not
# be counted live for the rest of the session (the I1 phantom-worker residual
# pinned by Task 6a). A phantom inflates the count into premature overflow and,
# having no surface, is not a selectable target either -> the next dispatch dies
# exit 3, which the spec forbids for the overflow path.
NTSID="no-term-$$"
printf '#!/usr/bin/env bash\necho none\n' > "$TMP/detect.sh"
CLAUDE_CODE_SESSION_ID="$NTSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/nt.md" --cwd "$TMP" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "no-terminal worker -> exit 3" || bad "no-terminal worker -> exit 3" "rc=$rc"
n=$(CLAUDE_CODE_SESSION_ID="$NTSID" bash "$DISPATCH" count-workers 2>/dev/null)
[ "$n" = "0" ] && ok "no-terminal failure leaves no phantom live worker" || bad "no-terminal failure leaves no phantom" "got $n want 0"
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"

APSID="pane-fail-$$"
printf '#!/usr/bin/env bash\nexit 1\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
CLAUDE_CODE_SESSION_ID="$APSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/ap.md" --cwd "$TMP" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok "open_pane failure -> exit 4" || bad "open_pane failure -> exit 4" "rc=$rc"
# Regression pin for the open_tab reclassification below: open_pane failing IS an
# adapter failure and must keep both halves of that classification.
[ -f "$PANE_STATE_DIR/adapter-failed-$APSID" ] && ok "open_pane failure still writes the cooldown" || bad "open_pane failure still writes the cooldown"
n=$(CLAUDE_CODE_SESSION_ID="$APSID" bash "$DISPATCH" count-workers 2>/dev/null)
[ "$n" = "0" ] && ok "open_pane failure leaves no phantom live worker" || bad "open_pane failure leaves no phantom" "got $n want 0"

# --- Obs-judge finding: an open_tab failure is STALE LOCAL STATE, not a broken
# adapter. A worker pane closed by hand (or lost to a cmux restart, or an agent
# hung past the wait timeout) never gets its completion marker, so it stays
# counted live AND keeps a surface ref that no longer resolves; the next overflow
# tabs into nothing. Required: exit 3 with NO cooldown (degrade this ONE spawn to
# in-process, the same classification the no-target path uses), dead-mark the
# stale TARGET so the next overflow picks a different pane, and dead-mark this
# dispatch's own run dir so it leaves no phantom.
# CONTRACT CHANGE: this replaces Task 7's "open_tab failure -> exit 4" and
# "open_tab failure writes cooldown" assertions, which pinned the old behavior.
# shellcheck disable=SC2016 # $1/$@ must reach the generated stub unexpanded (see line 25)
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) echo surface:P1 ;;\n  open_tab) printf "%%s\\n" "$@" > "%s/tab-args"; exit 1 ;;\n  *) exit 64 ;;\nesac\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
XSID="tab-fail-$$"
CLAUDE_CODE_SESSION_ID="$XSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
xp=$(mk_run_ref worker "$XSID" no surface:XP pane)
xq=$(mk_run_ref worker "$XSID" no surface:XQ pane)
rm -f "$TMP/tab-args"
touch "$TMP/tab-fail-marker"
CLAUDE_CODE_SESSION_ID="$XSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/x1.md" --cwd "$TMP" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "open_tab failure -> exit 3 (in-process, not an adapter failure)" || bad "open_tab failure -> exit 3" "rc=$rc"
[ ! -f "$PANE_STATE_DIR/adapter-failed-$XSID" ] && ok "open_tab failure writes no cooldown" || bad "open_tab failure writes no cooldown"
xt1=$(sed -n '2p' "$TMP/tab-args" 2>/dev/null)
case "$xt1" in surface:XP) xdead="$xp" ;; surface:XQ) xdead="$xq" ;; *) xdead="" ;; esac
{ [ -n "$xdead" ] && [ -f "$xdead/agent-exit" ]; } && ok "open_tab failure dead-marks the stale target's run dir" || bad "open_tab failure dead-marks the stale target" "target=$xt1"
# The dispatch's OWN run dir is the one created after the marker; the target's
# dir is excluded by path because dead-marking it also bumps its mtime.
xown=$(find "$PANE_STATE_DIR/runs" -mindepth 1 -maxdepth 1 -type d -newer "$TMP/tab-fail-marker" ! -path "${xdead:-/nonexistent}" | head -n 1)
{ [ -n "$xown" ] && [ -f "$xown/agent-exit" ]; } && ok "open_tab failure dead-marks its own run dir (no phantom)" || bad "open_tab failure dead-marks its own run dir" "dir=$xown"
# The durable half of the routing record: stderr reaches the caller now, this
# copy outlives the session — and this is the failure that most needs it.
xroute=$(cat "${xown:-/nonexistent}/route" 2>/dev/null)
[ "$xroute" = "lane=worker live=2 max=1 kind=tab target=$xt1" ] && ok "the failed overflow's routing decision survives in its run dir" || bad "failed overflow's routing decision in run dir" "$xroute"
# Rewind the round-robin index so rotation ALONE would re-pick the same target:
# only the dead-mark above can change the answer here.
printf '0\n' > "$PANE_STATE_DIR/pane-rr-$XSID"
CLAUDE_CODE_SESSION_ID="$XSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/x2.md" --cwd "$TMP" >/dev/null 2>&1
xt2=$(sed -n '2p' "$TMP/tab-args" 2>/dev/null)
{ [ -n "$xt2" ] && [ "$xt2" != "$xt1" ]; } && ok "a later overflow selects a different target after an open_tab failure" || bad "later overflow selects a different target" "first=$xt1 second=$xt2"

# --- Obs-judge RUN 2 finding: retiring the target on EVERY open_tab failure
# keeps max=N honest only while the adapter can actually tab. An adapter that
# cannot tab at all fails every overflow, and each failure retires a HEALTHY
# pane's marker — so the live count drops under N, the next worker opens a
# brand-new pane, and the real pane count grows without bound while the session
# never cools down. Fix: count CONSECUTIVE open_tab failures per session and
# write the cooldown at the threshold (exit 4), restoring the bound.
#
# Only a SUCCESSFUL open_tab clears the streak. An open_pane success proves
# nothing about tab capability, and in this very loop an open_pane succeeds
# between every pair of tab failures — resetting on it would make the threshold
# unreachable and pin the bug in place.
TFSID="tab-streak-$$"
# shellcheck disable=SC2016 # $1 must reach the generated stub unexpanded (see line 25)
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) echo surface:TFP ;;\n  open_tab) exit 1 ;;\n  *) exit 64 ;;\nesac\n' > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
CLAUDE_CODE_SESSION_ID="$TFSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
mk_run_ref worker "$TFSID" no surface:TF1 pane >/dev/null   # the one live worker pane
tf_dispatch() { # $1 = tag -> rc of one dispatch under $TFSID
  CLAUDE_CODE_SESSION_ID="$TFSID" bash "$DISPATCH" dispatch general-purpose \
    --prompt-file "$PROMPT" --result-file "$TMP/$1.md" --cwd "$TMP" >/dev/null 2>&1
}
# The growth loop, one full turn per pair: overflow fails and retires a pane,
# then the freed slot opens a new one. Failures 1 and 2 must still degrade only
# this spawn (exit 3, no cooldown) — one stale pane has to self-heal silently.
tf_dispatch tf1; rc=$?
[ "$rc" -eq 3 ] && ok "tab-failure streak 1 -> exit 3" || bad "tab-failure streak 1 -> exit 3" "rc=$rc"
tf_dispatch tf2 >/dev/null 2>&1                              # freed slot -> open_pane succeeds
tf_dispatch tf3; rc=$?
[ "$rc" -eq 3 ] && ok "tab-failure streak 2 -> still exit 3, no cooldown" || bad "tab-failure streak 2 -> exit 3" "rc=$rc"
[ ! -f "$PANE_STATE_DIR/adapter-failed-$TFSID" ] && ok "an open_pane success between tab failures does not reset the streak" || bad "open_pane success must not reset the streak"
tf_dispatch tf4 >/dev/null 2>&1
tf_dispatch tf5; rc=$?
[ "$rc" -eq 4 ] && ok "tab-failure streak 3 -> exit 4 (adapter cannot tab)" || bad "tab-failure streak 3 -> exit 4" "rc=$rc"
[ -f "$PANE_STATE_DIR/adapter-failed-$TFSID" ] && ok "the 3rd consecutive open_tab failure writes the cooldown" || bad "3rd consecutive open_tab failure writes the cooldown"

# A successful open_tab is the only evidence the adapter CAN tab, so it clears
# the streak: without the reset, two failures early in a long healthy session
# would leave it one failure from a spurious cooldown forever.
TRSID="tab-reset-$$"
CLAUDE_CODE_SESSION_ID="$TRSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
mk_run_ref worker "$TRSID" no surface:TR1 pane >/dev/null
tr_dispatch() { CLAUDE_CODE_SESSION_ID="$TRSID" bash "$DISPATCH" dispatch general-purpose \
    --prompt-file "$PROMPT" --result-file "$TMP/$1.md" --cwd "$TMP" >/dev/null 2>&1; }
tr_dispatch tr1; tr_dispatch tr2; tr_dispatch tr3          # streak -> 2 (tr2 opens a pane)
# shellcheck disable=SC2016 # $1 must reach the generated stub unexpanded (see line 25)
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) echo surface:TRP ;;\n  open_tab) echo surface:TRT ;;\n  *) exit 64 ;;\nesac\n' > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
tr_dispatch tr4 >/dev/null 2>&1                            # open_pane: refills the freed slot
tr_dispatch tr5; rc=$?
[ "$rc" -eq 0 ] && ok "open_tab succeeds once the adapter can tab" || bad "open_tab succeeds" "rc=$rc"
# shellcheck disable=SC2016 # $1 must reach the generated stub unexpanded (see line 25)
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) echo surface:TRP ;;\n  open_tab) exit 1 ;;\n  *) exit 64 ;;\nesac\n' > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
tr_dispatch tr6; rc=$?
[ "$rc" -eq 3 ] && ok "the failure after a successful tab restarts the streak (exit 3)" || bad "successful tab restarts the streak" "rc=$rc"
[ ! -f "$PANE_STATE_DIR/adapter-failed-$TRSID" ] && ok "a successful open_tab clears the failure streak" || bad "successful open_tab clears the streak"

# --- Obs-judge RUN 3 --------------------------------------------------------
# The three blocks below use multi-line adapter stubs, so they are written as
# quoted heredocs rather than the single-line printf stubs above: the stub bodies
# are longer than the ones that fit on a line, and a quoted heredoc keeps `$1`
# and `$2` unexpanded without the SC2016 dance. They read $PANE_STATE_DIR, which
# the suite exports (line 17) and every adapter therefore inherits.

# RUN 3's structural finding: RUN 2 added eight assertions that all pin the
# streak MECHANISM, and nothing anywhere counts real panes against max=N — the
# property RUN 2 actually raised. This is that property, asserted directly.
# open_pane is the only verb that creates a pane, so counting its invocations
# counts panes: a healthy adapter, max=2, six sequential worker dispatches whose
# run dirs all stay live (nothing writes agent-exit, so no slot is ever freed).
# shellcheck disable=SC2154 # PANE_STATE_DIR is exported by this suite and read inside the stub
cat > "$PANE_ADAPTERS_DIR/cmux.sh" <<'PCEOF'
#!/usr/bin/env bash
# A distinct ref per pane: run_dir_for_surface has to tell them apart.
case "$1" in
  open_pane) n=$(( $(cat "$PANE_STATE_DIR/panes" 2>/dev/null || echo 0) + 1 ))
             printf '%s\n' "$n" > "$PANE_STATE_DIR/panes"
             printf 'surface:PC%s\n' "$n" ;;
  open_tab)  printf '%s\n' "$2" >> "$PANE_STATE_DIR/tabs"; printf 'surface:PCT\n' ;;
  *) exit 64 ;;
esac
PCEOF
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
PCSID="pane-count-$$"
CLAUDE_CODE_SESSION_ID="$PCSID" bash "$DISPATCH" set-policy panes --max 2 >/dev/null 2>&1
rm -f "$PANE_STATE_DIR/panes" "$PANE_STATE_DIR/tabs"
pc_rcs=""
for i in 1 2 3 4 5 6; do
  CLAUDE_CODE_SESSION_ID="$PCSID" bash "$DISPATCH" dispatch general-purpose \
    --prompt-file "$PROMPT" --result-file "$TMP/pc$i.md" --cwd "$TMP" >/dev/null 2>&1
  pc_rcs="$pc_rcs$?"
done
pc_panes=$(cat "$PANE_STATE_DIR/panes" 2>/dev/null || echo 0)
pc_tabs=$(wc -l < "$PANE_STATE_DIR/tabs" 2>/dev/null | tr -d ' '); pc_tabs="${pc_tabs:-0}"
[ "$pc_panes" -le 2 ] && ok "panes max=2 bounds real panes: 6 workers opened $pc_panes pane(s), never more than 2" \
  || bad "panes max=2 bounds real panes" "6 workers opened $pc_panes panes, max is 2"
[ "$pc_panes" -eq 2 ] && ok "panes max=2 is also filled: both slots used before overflowing" \
  || bad "panes max=2 is filled" "got $pc_panes want 2"
[ "$pc_tabs" -eq 4 ] && ok "every worker past max=2 overflows to a tab (4 of 6)" || bad "workers past max overflow to tabs" "got $pc_tabs want 4"
# Spec: an overflow worker may neither block nor go inline, so all six must be 0.
[ "$pc_rcs" = "000000" ] && ok "no worker is blocked or degraded while max=2 is honored" || bad "no worker blocked or degraded" "rcs=$pc_rcs"
pc_live=$(CLAUDE_CODE_SESSION_ID="$PCSID" bash "$DISPATCH" count-workers 2>/dev/null)
[ "$pc_live" = "2" ] && ok "live worker panes settle at max=2, not at the worker count" || bad "live worker panes settle at max" "got $pc_live want 2"

# RUN 3 F1. The durable record claimed the pane leak "stops dead when the
# cooldown lands". It does not: this dispatcher only ever WRITES
# adapter-failed-<sid> (two sites in open_surface_or_cooldown) and never reads
# it. hooks/pane-dispatch-guard.sh is its sole reader, so the bound on pane
# growth is EMERGENT — the guard stops routing work to this script — and not
# mechanical. A direct `dispatch` invocation is not bounded at all, and the
# branch declares that direct invocation happens.
# The guard's half of that contract ("cooldown flag present -> allow in-process")
# is already covered by hooks/pane-dispatch-guard.test.sh, three cases: stdin
# session id, env session id, and the nosession fallback key. Duplicating it here
# would prove nothing. What nothing covered is the DISPATCHER's half, so that is
# what this pins — the two halves must stay legible as two, or the next reader
# re-derives the same false single bound.
CDSID="cooldown-noop-$$"
CLAUDE_CODE_SESSION_ID="$CDSID" bash "$DISPATCH" set-policy panes --max 2 >/dev/null 2>&1
mkdir -p "$PANE_STATE_DIR"
: > "$PANE_STATE_DIR/adapter-failed-$CDSID"      # this session is already cooled down
rm -f "$PANE_STATE_DIR/panes"
CLAUDE_CODE_SESSION_ID="$CDSID" bash "$DISPATCH" dispatch general-purpose \
  --prompt-file "$PROMPT" --result-file "$TMP/cd1.md" --cwd "$TMP" >/dev/null 2>&1; rc=$?
cd_panes=$(cat "$PANE_STATE_DIR/panes" 2>/dev/null || echo 0)
{ [ "$rc" -eq 0 ] && [ "$cd_panes" -eq 1 ]; } \
  && ok "a cooled-down session still opens a pane on direct dispatch (the bound is the guard's, not the dispatcher's)" \
  || bad "cooled-down session still opens a pane on direct dispatch" "rc=$rc panes=$cd_panes"

# RUN 3 F2/F3, re-graded by repro — see the branch log for the evidence table.
# RUN 3 held that the round-robin index advancing on a FAILED open_tab marches
# the selector through every stale pane and is what lets three stale panes
# declare a HEALTHY adapter tab-incapable, and proposed advancing only on
# success. Against production run-dir names the opposite is true. new_run_dir
# names every run <epoch>-<pid>-<random>; the epoch field is fixed width, so
# glob order is creation order, so a pane that went stale ALWAYS sorts before
# every pane opened after it. A standing index therefore re-probes the oldest —
# most-likely-stale — pane on every overflow and drains the stale ones one per
# dispatch without ever reaching a healthy one, which is precisely how the streak
# would reach its limit on a healthy adapter. The advance is what carries the
# selector past them to a pane whose successful tab clears the streak.
#
# That coupling is load-bearing and was one "cosmetic cleanup" away from being
# removed. This pins it end to end: three worker panes lost to a cmux restart
# five minutes ago, plus an adapter that tabs fine into anything still alive,
# must never cool the session down. Fixtures are named with a PAST epoch on
# purpose — the naming IS the precondition under test, so mk_run_ref's mktemp
# suffix would not express it.
mk_stale_run() {   # $1 session-key, $2 surface-ref, $3 age in seconds -> run dir
  local d
  mkdir -p "$PANE_STATE_DIR/runs"
  d="$(mktemp -d "$PANE_STATE_DIR/runs/$(( $(date +%s) - $3 ))-$$-XXXXXX")"
  printf 'worker\n' > "$d/lane"; printf '%s\n' "$1" > "$d/session"
  printf 'pane\n' > "$d/kind"; printf '%s\n' "$2" > "$d/surface"
  printf '%s\n' "$d"
}
# shellcheck disable=SC2154 # PANE_STATE_DIR is exported by this suite and read inside the stub
cat > "$PANE_ADAPTERS_DIR/cmux.sh" <<'RREOF'
#!/usr/bin/env bash
# Healthy: it tabs into anything still alive. The GHOST refs belong to panes the
# restart killed, so only those fail — the adapter itself is fine.
case "$1" in
  open_pane) n=$(( $(cat "$PANE_STATE_DIR/panes" 2>/dev/null || echo 0) + 1 ))
             printf '%s\n' "$n" > "$PANE_STATE_DIR/panes"
             printf 'surface:RRLIVE%s\n' "$n" ;;
  open_tab)  printf '%s\n' "$2" >> "$PANE_STATE_DIR/tabtargets"
             case "$2" in *GHOST*) exit 1 ;; *) printf 'surface:RRTAB\n' ;; esac ;;
  *) exit 64 ;;
esac
RREOF
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
RRSID="restart-ghosts-$$"
CLAUDE_CODE_SESSION_ID="$RRSID" bash "$DISPATCH" set-policy panes --max 3 >/dev/null 2>&1
mk_stale_run "$RRSID" surface:GHOST1 300 >/dev/null
mk_stale_run "$RRSID" surface:GHOST2 300 >/dev/null
mk_stale_run "$RRSID" surface:GHOST3 300 >/dev/null
rm -f "$PANE_STATE_DIR/panes" "$PANE_STATE_DIR/tabtargets"
rr_rcs=""
for i in 1 2 3 4 5 6 7 8; do
  CLAUDE_CODE_SESSION_ID="$RRSID" bash "$DISPATCH" dispatch general-purpose \
    --prompt-file "$PROMPT" --result-file "$TMP/rr$i.md" --cwd "$TMP" >/dev/null 2>&1
  rr_rcs="$rr_rcs$?"
done
[ ! -f "$PANE_STATE_DIR/adapter-failed-$RRSID" ] \
  && ok "three panes lost to a cmux restart never cool down a healthy adapter" \
  || bad "stale panes must not cool down a healthy adapter" "cooldown written; rcs=$rr_rcs"
case "$rr_rcs" in *4*) bad "no dispatch is told the adapter is tab-incapable" "rcs=$rr_rcs" ;;
  *) ok "no dispatch is told the healthy adapter is tab-incapable (no exit 4)" ;; esac
# The reason there is no cooldown: the selector reached a pane opened AFTER the
# restart and tabbed into it, which cleared the streak. Without that this would
# pass for the wrong reason (e.g. if overflow had stopped happening at all).
grep -qv GHOST "$PANE_STATE_DIR/tabtargets" 2>/dev/null \
  && ok "the selector reaches a post-restart pane, whose successful tab clears the streak" \
  || bad "selector never reaches a post-restart pane" "targets=$(tr '\n' ' ' < "$PANE_STATE_DIR/tabtargets" 2>/dev/null)"
[ "$(cat "$PANE_STATE_DIR/panes" 2>/dev/null || echo 0)" -le 3 ] \
  && ok "the restart's stale panes are replaced up to max=3, not past it" \
  || bad "stale panes replaced past max" "panes=$(cat "$PANE_STATE_DIR/panes" 2>/dev/null)"

# --- final-review carry-forwards -------------------------------------------

# Nit-8: `while read -r line` drops a conf's final line when it has no trailing
# newline, so a hand-edited conf silently loses its last entry -- and is_judge
# misclassifying a judge as a worker subjects it to the max-N gate it is meant
# to sit outside. Under panes max=1 with one live worker pane, a judge opens a
# PANE while a misclassified worker overflows to a TAB, so the verb the adapter
# records is the discriminator. The guard's in_conf has the same parser and is
# fixed in the same commit: if only one side were fixed they would disagree.
# shellcheck disable=SC2016 # $1/$@ must reach the generated stub unexpanded (see line 25)
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) printf "%%s\\n" "$@" > "%s/adapter-args"; echo surface:NL9 ;;\n  open_tab)  printf "%%s\\n" "$@" > "%s/tab-args"; echo surface:NLT ;;\n  *) exit 64 ;;\nesac\n' "$TMP" "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
NLSID="nonl-judge-$$"
printf '# always-paned judges\ncompliance-judge' > "$TMP/redirect-nonl.conf"   # deliberately unterminated
CLAUDE_CODE_SESSION_ID="$NLSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
mk_run_ref worker "$NLSID" no surface:NLP pane >/dev/null
rm -f "$TMP/tab-args" "$TMP/adapter-args"
PANE_REDIRECT_CONF="$TMP/redirect-nonl.conf" CLAUDE_CODE_SESSION_ID="$NLSID" bash "$DISPATCH" \
  dispatch compliance-judge --prompt-file "$PROMPT" --result-file "$TMP/nl.md" --cwd "$TMP" >/dev/null 2>&1; rc=$?
{ [ "$rc" -eq 0 ] && [ "$(sed -n '1p' "$TMP/adapter-args" 2>/dev/null)" = "open_pane" ]; } \
  && ok "judge on an unterminated final conf line still bypasses the worker gate" \
  || bad "unterminated final conf line dropped by is_judge" "rc=$rc verb=$(sed -n '1p' "$TMP/adapter-args" 2>/dev/null)"

# NEW-A (pair pin): read_policy already rejects an N past 2^64 -- the test
# builtin errors on it where the guard's $((10#$n)) wrapped it into range. This
# pins that read_policy still rejects it once POLICY_RE caps the digit count,
# so the two readers cannot drift apart again. Green on both sides by design.
printf 'panes max=18446744073709551619\n' > "$RP_DIR/wrap"
rp_got=$(call_read_policy "$RP_DIR/wrap")
[ -z "$rp_got" ] && ok "read_policy: 64-bit-wrapping N -> empty" || bad "read_policy: 64-bit-wrapping N -> empty" "$rp_got"

# T7 reviewer Minor 2: `lane` must be the single commit point for the marker
# set. live_worker_panes gates on lane=worker && session=key BEFORE it reads
# kind, and a MISSING kind reads as "pane" by design -- so with lane written
# first, a concurrent counter can see a half-written tab dispatch as a pane.
# Writing kind first and lane last closes that window. The window is a race, not
# a reachable end state (all three writes complete before the adapter is ever
# called), so the regression guard is the source order itself.
# shellcheck disable=SC2016 # $run_dir is grep's literal search text, not an expansion
mo=$(grep -oE '> "\$run_dir/(kind|lane|session)"' "$DISPATCH" | sed 's|.*/||; s|"||' | tr '\n' ' ')
[ "$mo" = "kind session lane " ] && ok "marker writes commit lane last (kind, session, lane)" \
  || bad "marker write order" "got: $mo want: kind session lane"

# An empty session key must count nothing. It is unreachable from the CLI (every
# caller defaults to "nosession"), but live_worker_panes' session test compares
# marker CONTENT, so an empty key matches every run dir whose session marker is
# missing or empty -- "no session" silently meaning "all sessions". The predicate
# is shared by the count and the overflow target choice, so it fails closed
# itself rather than trusting its callers. Called directly: the CLI cannot
# express this input.
call_count_workers() { k="$1" bash -c "$(sed '/^cmd=/,$d' "$DISPATCH")"$'\ncount_live_workers "$k"'; }
EMPTYD="$(mktemp -d "$PANE_STATE_DIR/runs/$(date +%s)-$$-emptyXXXXXX")"
printf 'worker\n' > "$EMPTYD/lane"; printf '\n' > "$EMPTYD/session"; printf 'surface:E1\n' > "$EMPTYD/surface"
cw=$(call_count_workers "")
[ "$cw" = "0" ] && ok "empty session key counts no live workers" || bad "empty session key counts no live workers" "got $cw want 0"

# Usage-string drift (pre-existing): the fallthrough usage omitted the two
# subcommands added since it was written.
out=$(bash "$DISPATCH" bogus-subcommand 2>&1); rc=$?
{ [ "$rc" -eq 64 ] && printf '%s' "$out" | grep -q 'set-policy' && printf '%s' "$out" | grep -q 'count-workers'; } \
  && ok "usage names every subcommand" || bad "usage names every subcommand" "rc=$rc: $out"

# --- --model passthrough: accepted, forwarded to the launcher, value required.
# Without this the dispatcher cannot honor a model-switch gate at all: the pane
# inherits settings.json (verified: opus[1m]) no matter what tier was chosen.
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/model1.md" --cwd "$TMP" --model claude-sonnet-5 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "--model accepted" || bad "--model accepted" "rc=$rc: $out"
grep -rql 'claude-sonnet-5' "$PANE_STATE_DIR/runs" --include=launch.sh >/dev/null 2>&1 \
  && ok "--model reaches the launcher" || bad "--model reaches the launcher"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/model2.md" --cwd "$TMP" --model >/dev/null 2>&1
[ $? -eq 64 ] && ok "--model with no value -> usage exit 64" || bad "--model with no value -> usage exit 64"

# Criterion 3: a shape-invalid --model dies before any pane opens. "a b" fails
# MODEL_RE (embedded space); no run dir may be created for this call.
before_count=$(find "$PANE_STATE_DIR/runs" -name launch.sh | wc -l | tr -d ' ')
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/model3.md" --cwd "$TMP" --model "a b" 2>&1)
rc=$?
after_count=$(find "$PANE_STATE_DIR/runs" -name launch.sh | wc -l | tr -d ' ')
[ "$rc" -ne 0 ] && ok "--model \"a b\" (shape-invalid) -> non-zero exit" \
  || bad "--model \"a b\" (shape-invalid) -> non-zero exit" "rc=$rc: $out"
[ "$before_count" = "$after_count" ] && ok "--model \"a b\" -> no pane opened" \
  || bad "--model \"a b\" -> no pane opened" "before=$before_count after=$after_count"

# Criterion: unflagged dispatch produces a launcher byte-identical in shape to
# pre-flag -- exactly 5 %q-quoted args after run-pane-agent.sh, no trailing ''.
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/model4.md" --cwd "$TMP" 2>&1)
nomodel_launcher=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$PROMPT" -exec grep -l 'model4.md' {} + 2>/dev/null | head -n 1)
if [ -n "$nomodel_launcher" ] && ! grep -q "run-pane-agent.sh.*''" "$nomodel_launcher"; then
  ok "unflagged dispatch: launcher has no trailing empty --model arg"
else
  bad "unflagged dispatch: launcher has no trailing empty --model arg" "$nomodel_launcher"
fi

# ============================================================================
# Card docs/features/pane-agent-scratch-isolation.md, checklist item 2:
# failing assertions for the dispatch subcommand's new per-run "work" dir and
# preamble-wrapped prompt.md. Self-contained -- fresh adapter/detect stubs and
# marker-based "newer" lookups, matching the house idiom above, rather than
# reusing variables set by earlier sections.
# ============================================================================
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"; chmod 700 "$TMP/detect.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/wd-adapter-args"\necho surface:WD1\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"

touch "$TMP/wd-marker1"
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/wd-r1.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "work-dir dispatch happy path exits 0" || bad "work-dir dispatch happy path exits 0" "rc=$rc: $out"
wd_launcher=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$TMP/wd-marker1" | head -n 1)
[ -n "$wd_launcher" ] && ok "work-dir dispatch: run dir located" || bad "work-dir dispatch: run dir located"
wd_run_dir="$(dirname "${wd_launcher:-/nonexistent}")"

[ -d "$wd_run_dir/work" ] && ok "a 'work' child of the run dir exists after dispatch" \
  || bad "a 'work' child of the run dir exists after dispatch" "$wd_run_dir/work"
wd_work_perms=$(stat -f '%Lp' "$wd_run_dir/work" 2>/dev/null)
[ "$wd_work_perms" = "700" ] && ok "the work dir's mode is 700" || bad "the work dir's mode is 700" "$wd_work_perms"
grep -qF "$wd_run_dir/work" "$wd_run_dir/prompt.md" 2>/dev/null \
  && ok "the work dir's absolute path appears in the prompt.md preamble" \
  || bad "the work dir's absolute path appears in the prompt.md preamble" "$(cat "$wd_run_dir/prompt.md" 2>/dev/null)"

# --- the preamble sits at the HEAD of prompt.md, and the caller's bytes
# survive verbatim even when the caller's own prompt contains a line that is
# exactly "---" (the preamble's own delimiter shape).
DASH_PROMPT="$TMP/dash-prompt.md"
printf 'line one\n---\nline two\n' > "$DASH_PROMPT"
touch "$TMP/wd-marker2"
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$DASH_PROMPT" --result-file "$TMP/wd-r2.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "dispatch with a literal '---' line in the caller's prompt exits 0" \
  || bad "dispatch with a literal '---' line in the caller's prompt exits 0" "rc=$rc: $out"
dash_prompt_md=$(find "$PANE_STATE_DIR/runs" -name prompt.md -newer "$TMP/wd-marker2" | head -n 1)
[ -n "$dash_prompt_md" ] && ok "dash-prompt dispatch: prompt.md located" || bad "dash-prompt dispatch: prompt.md located"

head -n 1 "${dash_prompt_md:-/nonexistent}" 2>/dev/null | grep -q 'Your private scratch directory for this dispatch is:' \
  && ok "the preamble occupies the head of prompt.md, ahead of the caller's bytes" \
  || bad "the preamble occupies the head of prompt.md" "$(head -n 1 "${dash_prompt_md:-/nonexistent}" 2>/dev/null)"

delim_line=$(grep -n '^--- end of dispatch preamble; the task follows ---$' "${dash_prompt_md:-/nonexistent}" 2>/dev/null | head -n 1 | cut -d: -f1)
if [ -n "$delim_line" ]; then
  tail -n +"$((delim_line + 1))" "$dash_prompt_md" > "$TMP/dash-actual-body" 2>/dev/null
else
  : > "$TMP/dash-actual-body"
fi
diff -q "$DASH_PROMPT" "$TMP/dash-actual-body" >/dev/null 2>&1 \
  && ok "the caller's prompt bytes are preserved byte-for-byte after the preamble, including its own literal '---' line" \
  || bad "caller's prompt bytes preserved verbatim after the preamble" "no preamble delimiter found, or body diverged from $DASH_PROMPT"

# --- mkdir of the work child failing dies before any pane/adapter opens.
# A PATH-prepended stub `mkdir` fails only on a path ending "/work" (the shape
# the design pins) and defers to the real /bin/mkdir for every other caller
# (mkdir -p "$RUNS_DIR", and new_run_dir's own "mkdir $RUNS_DIR/$run_id"),
# since neither of those paths ends in "/work".
MKDIR_FAIL_BIN="$TMP/mkdir-fail-bin"; mkdir -p "$MKDIR_FAIL_BIN"
cat > "$MKDIR_FAIL_BIN/mkdir" <<'MKEOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    */work) exit 1 ;;
  esac
done
exec /bin/mkdir "$@"
MKEOF
chmod 700 "$MKDIR_FAIL_BIN/mkdir"
rm -f "$TMP/wd-adapter-args"
before_launchers=$(find "$PANE_STATE_DIR/runs" -name launch.sh | wc -l | tr -d ' ')
out=$(PATH="$MKDIR_FAIL_BIN:$PATH" bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/wd-mkdirfail.md" --cwd "$TMP" 2>&1); rc=$?
after_launchers=$(find "$PANE_STATE_DIR/runs" -name launch.sh | wc -l | tr -d ' ')
[ "$rc" -ne 0 ] && ok "a work dir mkdir failure makes dispatch exit non-zero" \
  || bad "a work dir mkdir failure makes dispatch exit non-zero" "rc=$rc: $out"
printf '%s' "$out" | grep -q '/work' && ok "the mkdir-failure message names the work path" \
  || bad "the mkdir-failure message names the work path" "$out"
[ "$before_launchers" = "$after_launchers" ] && ok "a work dir mkdir failure opens no pane (no new launcher)" \
  || bad "a work dir mkdir failure opens no pane" "before=$before_launchers after=$after_launchers"
[ ! -f "$TMP/wd-adapter-args" ] && ok "a work dir mkdir failure never calls the adapter" \
  || bad "a work dir mkdir failure never calls the adapter"

# --- non-discriminating (card checklist item 6): this rides entirely on
# new_run_dir's pre-existing uniqueness guarantee and passes with or without
# the work-dir change. Kept for completeness per the card's own instruction;
# do not count it as coverage for the new work-dir feature.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/wd-adapter-args"\necho surface:WD2\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
touch "$TMP/wd-marker3"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/wd-r3.md" --cwd "$TMP" >/dev/null 2>&1
l3=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$TMP/wd-marker3" | head -n 1)
touch "$TMP/wd-marker4"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/wd-r4.md" --cwd "$TMP" >/dev/null 2>&1
l4=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$TMP/wd-marker4" | head -n 1)
wd3="$(dirname "${l3:-/nonexistent}")/work"; wd4="$(dirname "${l4:-/nonexistent}")/work"
{ [ -n "$l3" ] && [ -n "$l4" ] && [ "$wd3" != "$wd4" ]; } \
  && ok "two dispatches get different work dirs (non-discriminating -- rides on new_run_dir)" \
  || bad "two dispatches get different work dirs" "wd3=$wd3 wd4=$wd4"

# ============================================================================
# Card docs/features/pane-agent-scratch-isolation.md, checklist item 4:
# failing assertions for cleanup_stale's new WORK_STALE_MINUTES pruning of a
# run dir's "work" child, one per Gherkin case. Ages are set with `touch -t`
# to an EXACT wall-clock offset -- never `-mtime` in the fixture, since BSD
# find truncates -mtime to whole days (the card's own measured defect) and a
# fixture built the same way could no longer discriminate. cleanup_stale is
# invoked directly (sourcing the script up to its `cmd=` dispatch line, the
# same technique call_read_policy/call_count_workers use above) rather than
# via a full `dispatch`, so these fixtures are never disturbed by an
# unrelated dispatch's own cleanup_stale call.
# ============================================================================
call_cleanup_stale() { bash -c "$(sed '/^cmd=/,$d' "$DISPATCH")"$'\ncleanup_stale'; }
ts_hours_ago() { date -v-"$1"H '+%Y%m%d%H%M.%S'; }
ts_days_ago()  { date -v-"$1"d '+%Y%m%d%H%M.%S'; }

mkdir -p "$PANE_STATE_DIR/runs"

# Boundary pair -- this is what catches BSD find's -mtime whole-day truncation.
CS_25H="$PANE_STATE_DIR/runs/cs-25h-$$"
mkdir -p "$CS_25H/work"
printf 'DONE\n' > "$CS_25H/agent-exit"
printf 'p\n' > "$CS_25H/prompt.md"
touch -t "$(ts_hours_ago 25)" "$CS_25H/work"
call_cleanup_stale >/dev/null 2>&1
[ -d "$CS_25H/work" ] && ok "a completed run's 25h-old work child survives cleanup_stale" \
  || bad "a completed run's 25h-old work child survives cleanup_stale" "$CS_25H/work missing"

CS_49H="$PANE_STATE_DIR/runs/cs-49h-$$"
mkdir -p "$CS_49H/work"
printf 'DONE\n' > "$CS_49H/agent-exit"
printf 'p\n' > "$CS_49H/prompt.md"
printf 'l\n' > "$CS_49H/launch.sh"
touch -t "$(ts_hours_ago 49)" "$CS_49H/work"
call_cleanup_stale >/dev/null 2>&1
[ ! -d "$CS_49H/work" ] && ok "a completed run's 49h-old work child is pruned by cleanup_stale" \
  || bad "a completed run's 49h-old work child is pruned by cleanup_stale" "$CS_49H/work still present"
{ [ -f "$CS_49H/prompt.md" ] && [ -f "$CS_49H/launch.sh" ] && [ -f "$CS_49H/agent-exit" ]; } \
  && ok "pruning the 49h-old work child leaves prompt.md, launch.sh and agent-exit in place" \
  || bad "pruning the 49h-old work child leaves the run dir's other files in place" \
    "prompt.md=$([ -f "$CS_49H/prompt.md" ] && echo y || echo n) launch.sh=$([ -f "$CS_49H/launch.sh" ] && echo y || echo n) agent-exit=$([ -f "$CS_49H/agent-exit" ] && echo y || echo n)"

# An unfinished run (no agent-exit) keeps its scratch regardless of age. The
# RUN DIR itself is left fresh here, deliberately: the pre-existing, unrelated
# STALE_DAYS=7 rule already deletes any run dir outright past that whole-dir
# clock, agent-exit or not (see the "stale-state housekeeping" fixture above),
# and the card's own design leaves that rule "unchanged". Aging the run dir
# itself here would trip THAT mechanism instead and prove nothing about the
# new work-pruning precondition under test -- so only the work child is aged,
# in isolation, to well past WORK_STALE_MINUTES.
CS_NOEXIT="$PANE_STATE_DIR/runs/cs-noexit-$$"
mkdir -p "$CS_NOEXIT/work"
printf 'p\n' > "$CS_NOEXIT/prompt.md"
touch -t "$(ts_days_ago 30)" "$CS_NOEXIT/work"
call_cleanup_stale >/dev/null 2>&1
[ -d "$CS_NOEXIT/work" ] && ok "a work child on a run with no agent-exit marker survives regardless of age (30 days)" \
  || bad "a work child with no agent-exit marker survives regardless of age" "$CS_NOEXIT/work missing"

# Pruning must not restart the run dir's own 7-day clock: touch -r restores
# the parent's mtime to prompt.md's (never modified after dispatch, so it is
# a stable reference), in the same breath the work child is removed.
CS_RESTART="$PANE_STATE_DIR/runs/cs-restart-$$"
mkdir -p "$CS_RESTART/work"
printf 'DONE\n' > "$CS_RESTART/agent-exit"
printf 'p\n' > "$CS_RESTART/prompt.md"
ts3d="$(ts_days_ago 3)"
touch -t "$ts3d" "$CS_RESTART/prompt.md"
touch -t "$ts3d" "$CS_RESTART/work"
touch -t "$ts3d" "$CS_RESTART"
before_mtime=$(stat -f '%m' "$CS_RESTART")
call_cleanup_stale >/dev/null 2>&1
after_mtime=$(stat -f '%m' "$CS_RESTART")
# Precondition for the mtime check below: the work child must actually have
# been pruned, or an unchanged mtime would pass vacuously (nothing happened).
[ ! -d "$CS_RESTART/work" ] && ok "the 3-day-old work child was pruned (precondition for the mtime-restore check)" \
  || bad "the 3-day-old work child was pruned (precondition for the mtime-restore check)" "still present -- the mtime check below cannot discriminate until this is fixed too"
[ "$before_mtime" = "$after_mtime" ] && ok "pruning a stale work child does not restart the run dir's own mtime clock" \
  || bad "pruning a stale work child does not restart the run dir's own mtime clock" "before=$before_mtime after=$after_mtime"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
