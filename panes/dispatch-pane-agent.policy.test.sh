#!/usr/bin/env bash
# dispatch-pane-agent.policy.test.sh — no-terminal + adapter-failure cooldown, set-policy, read_policy, lane/session markers, live worker count, overflow.
# Run: bash panes/dispatch-pane-agent.policy.test.sh
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

# NEW-A (pair pin): read_policy already rejects an N past 2^64 -- the test
# builtin errors on it where the guard's $((10#$n)) wrapped it into range. This
# pins that read_policy still rejects it once POLICY_RE caps the digit count,
# so the two readers cannot drift apart again. Green on both sides by design.
printf 'panes max=18446744073709551619\n' > "$RP_DIR/wrap"
rp_got=$(call_read_policy "$RP_DIR/wrap")
[ -z "$rp_got" ] && ok "read_policy: 64-bit-wrapping N -> empty" || bad "read_policy: 64-bit-wrapping N -> empty" "$rp_got"

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


tl_finish
