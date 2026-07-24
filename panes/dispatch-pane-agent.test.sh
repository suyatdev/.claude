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
mk_run() { # $1 lane, $2 session, $3 exited(yes/no) -> makes a fake run dir
  local d; d="$PANE_STATE_DIR/runs/$(date +%s)-$$-$RANDOM"; mkdir -p "$d"
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
out=$(CLAUDE_CODE_SESSION_ID="$UMAX_SID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/uw.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "worker under max opens a pane" || bad "worker under max opens a pane" "rc=$rc: $out"

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
n=$(CLAUDE_CODE_SESSION_ID="$APSID" bash "$DISPATCH" count-workers 2>/dev/null)
[ "$n" = "0" ] && ok "open_pane failure leaves no phantom live worker" || bad "open_pane failure leaves no phantom" "got $n want 0"

# --- Task 7: open_tab failure degrades this spawn to in-process (exit 4) and
# writes the session cooldown flag, exactly as an open_pane failure does. Its
# run dir is dead-marked too, so it can never be mistaken for a live run.
# shellcheck disable=SC2016 # $1 must reach the generated stub unexpanded (see line 25)
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) echo surface:P1 ;;\n  open_tab) exit 1 ;;\n  *) exit 64 ;;\nesac\n' > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
XSID="tab-fail-$$"
CLAUDE_CODE_SESSION_ID="$XSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
mk_run_ref worker "$XSID" no surface:XP pane >/dev/null
touch "$TMP/tab-fail-marker"
CLAUDE_CODE_SESSION_ID="$XSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/x1.md" --cwd "$TMP" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok "open_tab failure -> exit 4" || bad "open_tab failure -> exit 4" "rc=$rc"
[ -f "$PANE_STATE_DIR/adapter-failed-$XSID" ] && ok "open_tab failure writes cooldown" || bad "open_tab failure writes cooldown"
xd=$(find "$PANE_STATE_DIR/runs" -mindepth 1 -maxdepth 1 -type d -newer "$TMP/tab-fail-marker" | head -n 1)
{ [ -n "$xd" ] && [ -f "$xd/agent-exit" ]; } && ok "open_tab failure dead-marks its run dir" || bad "open_tab failure dead-marks its run dir" "dir=$xd"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
