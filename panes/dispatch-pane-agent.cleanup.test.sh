#!/usr/bin/env bash
# dispatch-pane-agent.cleanup.test.sh — cleanup_stale -- run-dir and work-child retention.
# Run: bash panes/dispatch-pane-agent.cleanup.test.sh
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

# --- stale-state housekeeping (>7 days old gets removed)
OLD="$PANE_STATE_DIR/runs/1000000000-1-1"
mkdir -p "$OLD"; touch -t 202001010000 "$OLD"
touch -t 202001010000 "$PANE_STATE_DIR/adapter-failed-ancient"
printf '#!/usr/bin/env bash\necho surface:1\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/r4.md" --cwd "$TMP" >/dev/null 2>&1
[ ! -d "$OLD" ] && ok "stale run dir cleaned" || bad "stale run dir cleaned"
[ ! -f "$PANE_STATE_DIR/adapter-failed-ancient" ] && ok "stale flag cleaned" || bad "stale flag cleaned"

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
# The ages STRADDLE 24h (WORK_STALE_MINUTES=1440), not 48h. This originally read
# 25h-survives / 49h-pruned, copied from the buggy -mtime +1 output the card
# recorded; measured on one fixture set aged 23h/25h/36h/49h, `-mmin +2880` (the
# only round constant that satisfies that pair) and `-mtime +1` (the bug) prune
# an IDENTICAL set -- 49h alone -- so the old pair could not tell the fix from
# the defect. Under -mtime +1 neither 23h nor 25h is pruned, so the 25h case
# below is the one that discriminates; the 23h case holds under both and guards
# only against an over-eager pruner. See the card, "The boundary pair straddles
# 24h, not 48h".
CS_23H="$PANE_STATE_DIR/runs/cs-23h-$$"
mkdir -p "$CS_23H/work"
printf 'DONE\n' > "$CS_23H/agent-exit"
printf 'p\n' > "$CS_23H/prompt.md"
touch -t "$(ts_hours_ago 23)" "$CS_23H/work"
call_cleanup_stale >/dev/null 2>&1
[ -d "$CS_23H/work" ] && ok "a completed run's 23h-old work child survives cleanup_stale" \
  || bad "a completed run's 23h-old work child survives cleanup_stale" "$CS_23H/work missing"

CS_25H="$PANE_STATE_DIR/runs/cs-25h-$$"
mkdir -p "$CS_25H/work"
printf 'DONE\n' > "$CS_25H/agent-exit"
printf 'p\n' > "$CS_25H/prompt.md"
printf 'l\n' > "$CS_25H/launch.sh"
touch -t "$(ts_hours_ago 25)" "$CS_25H/work"
call_cleanup_stale >/dev/null 2>&1
[ ! -d "$CS_25H/work" ] && ok "a completed run's 25h-old work child is pruned by cleanup_stale" \
  || bad "a completed run's 25h-old work child is pruned by cleanup_stale" "$CS_25H/work still present"
{ [ -f "$CS_25H/prompt.md" ] && [ -f "$CS_25H/launch.sh" ] && [ -f "$CS_25H/agent-exit" ]; } \
  && ok "pruning the 25h-old work child leaves prompt.md, launch.sh and agent-exit in place" \
  || bad "pruning the 25h-old work child leaves the run dir's other files in place" \
    "prompt.md=$([ -f "$CS_25H/prompt.md" ] && echo y || echo n) launch.sh=$([ -f "$CS_25H/launch.sh" ] && echo y || echo n) agent-exit=$([ -f "$CS_25H/agent-exit" ] && echo y || echo n)"

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


tl_finish
