#!/usr/bin/env bash
# dispatch-pane-agent.routing.test.sh — surface-ref fixtures, round-robin, tab targeting, degrade paths.
# Run: bash panes/dispatch-pane-agent.routing.test.sh
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


tl_finish
