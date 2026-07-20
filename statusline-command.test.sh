#!/usr/bin/env bash
# statusline-command.test.sh — unit tests for statusline-command.sh.
#
# Two groups:
#   1. Rendering — the segments appear/disappear correctly for each payload shape.
#   2. Control-byte injection — untrusted field values cannot reach the terminal
#      as live escapes. This is the group that matters: an injected escape does
#      not fail visibly (a stripped one is invisible, a successful one reads as a
#      rendering quirk), and the defect regressed once during development after
#      being fixed by only one of its two routes.
#
# Injection assertions compare escape COUNTS against a benign twin of the same
# payload rather than looking for specific byte patterns, so a surplus escape is
# caught whatever encoding produced it. Testing only the literal-backslash form
# would pass by construction once printf '%b' is gone, while leaving the
# real-byte route wide open -- that is exactly the hole this file exists to
# close. See the twin rationale above assert_no_injection for why the ceiling is
# per-payload and not one global baseline.
#
# Payloads carry control bytes as the literal text \u001b, which jq decodes into
# a real byte. That keeps this test file itself free of control characters.
#
# Run: bash statusline-command.test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/statusline-command.sh"

pass=0; fail=0

ok()   { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL — %s\n' "$1"; fail=$((fail+1)); }

# stderr is deliberately NOT swallowed: a jq parse error here would otherwise be
# invisible, and a payload jq rejects makes its assertion pass vacuously.
render() { printf '%s' "$1" | bash "$SCRIPT"; }

# Same, but runs the script from a given directory, to exercise the $PWD fallback.
render_in() { printf '%s' "$2" | (cd "$1" && bash "$SCRIPT"); }

count_byte() { # $1 output, $2 tr-class
  printf '%s' "$1" | tr -dc "$2" | wc -c | tr -d ' '
}

# Every throwaway directory is created here under ONE trap. A second
# `trap ... EXIT` further down would REPLACE this handler rather than add to it,
# silently leaking whatever the earlier one was responsible for.
TMP="$(mktemp -d)"        # made into a git repo below, for the git-segment cases
NONGIT="$(mktemp -d)"     # never a repo -- the benign twin for $PWD-fallback cases
STATE_HOME="$(mktemp -d)" # stands in for $HOME so the sigma cases cannot read or
                          # corrupt the real per-session counters under ~/.claude
RACE_HOME="$(mktemp -d)"  # separate again: the concurrency case writes from many
                          # processes at once and would perturb the serial cases
LOCK_HOME="$(mktemp -d)"  # lock-recovery cases, which plant hand-built lock dirs
BREAK_HOME="$(mktemp -d)" # stale-lock breaking UNDER concurrency
UNIT_HOME="$(mktemp -d)"  # direct lock-helper calls, created here so the trap owns it
JSON_HOME="$(mktemp -d)"  # legacy-state-format migration case
trap 'rm -rf "$TMP" "$NONGIT" "$STATE_HOME" "$RACE_HOME" "$LOCK_HOME" "$JSON_HOME" "$BREAK_HOME" "$UNIT_HOME"' EXIT

BASE_PAYLOAD='{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus 4.8"},"context_window":{"total_input_tokens":100}}'
BASE_OUT="$(render "$BASE_PAYLOAD")"

# Bar glyphs, written as escapes so this file stays plain ASCII apart from the
# few characters the assertions genuinely compare against.
FULL=$'\xe2\x96\x88'
EMPTY=$'\xe2\x96\x91'

# Builds the expected bar for a given fill count. The fill counts passed in below
# are derived by hand from the payload and the 100k reference, never read back
# from the script -- a helper that recomputed them the way the script does would
# agree with a broken script.
bar_of() { # $1 filled cells (of 10)
  local i=0 s=""
  while [ "$i" -lt "$1" ]; do s="${s}${FULL}"; i=$((i+1)); done
  while [ "$i" -lt 10 ]; do s="${s}${EMPTY}"; i=$((i+1)); done
  printf '%s' "$s"
}
BAR_EMPTY_10="$(bar_of 0)"
BAR_FULL_10="$(bar_of 10)"

# Colour codes the bar tiers use, for asserting tier boundaries.
C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[0;33m'
C_ORANGE=$'\033[38;5;208m'
C_RED=$'\033[0;31m'

# --- Group 1: rendering -------------------------------------------------------

case "$BASE_OUT" in
  *"Opus 4.8"*"${BAR_EMPTY_10} 100"*) ok "baseline renders model and context-bar segments" ;;
  *) bad "baseline segments missing: $BASE_OUT" ;;
esac

OUT="$(render '{"workspace":{"current_dir":"/tmp"}}')"
case "$OUT" in
  *"|"*|*"│"*) bad "no model/tokens should leave no separator: $OUT" ;;
  *) ok "absent model/context_window -> no dangling separator" ;;
esac

OUT="$(render '{"cwd":"/tmp","context_window":{"total_input_tokens":42}}')"
case "$OUT" in
  *"${BAR_EMPTY_10} 42"*) ok "sub-1000 tokens render raw, not k-formatted" ;;
  *) bad "expected raw token count: $OUT" ;;
esac

# Past the 100k reference the bar clamps full rather than overflowing, and the
# exact count stays visible beside it -- asserted together because the clamp is
# only defensible while the number is still shown.
OUT="$(render '{"cwd":"/tmp","context_window":{"total_input_tokens":113300}}')"
case "$OUT" in
  *"${BAR_FULL_10} 113.3k"*) ok "tokens >=1000 render in k form, bar clamps full" ;;
  *) bad "expected k-formatted tokens with a full bar: $OUT" ;;
esac

OUT="$(render '{"cwd":"/tmp"}')"
case "$OUT" in
  *"git:("*) bad "non-git dir should have no git segment: $OUT" ;;
  *) ok "non-git directory -> no git segment" ;;
esac

# Build a throwaway repo rather than assuming the script sits inside one --
# otherwise this assertion silently depends on where the file was copied to.
git -C "$TMP" init -q 2>/dev/null
git -C "$TMP" checkout -q -b testbranch 2>/dev/null

OUT="$(render "{\"cwd\":\"$TMP\"}")"
case "$OUT" in
  *"git:("*testbranch*) ok "git repo -> git segment names the branch" ;;
  *) bad "expected git segment naming testbranch: $OUT" ;;
esac

# A fresh repo with no commits still has a symbolic HEAD, so the branch renders.
: > "$TMP/f"
OUT="$(render "{\"cwd\":\"$TMP\"}")"
case "$OUT" in
  *"✗"*) ok "uncommitted changes -> dirty marker" ;;
  *) bad "expected dirty marker: $OUT" ;;
esac

# Non-integer token counts must not crash the awk formatter.
OUT="$(render '{"cwd":"/tmp","context_window":{"total_input_tokens":"not-a-number"}}')"
if [ -n "$OUT" ]; then ok "non-integer token count does not crash the render"
else bad "non-integer token count produced no output"; fi

# --- Bar tiers and fill -------------------------------------------------------
# Colour and fill both scale to the same 100k reference, so each case asserts
# them TOGETHER: a tier boundary that moves without its fill moving (or the
# reverse) means the two halves of the widget have drifted apart, which is the
# specific bug that made an earlier version render a red bar that looked empty.
assert_bar() { # $1 desc, $2 tokens, $3 expected colour, $4 expected fill, $5 expected label
  local out expected
  out="$(render "{\"cwd\":\"/tmp\",\"context_window\":{\"total_input_tokens\":$2}}")"
  expected="$3$(bar_of "$4") $5"
  case "$out" in
    *"$expected"*) ok "$1" ;;
    *) bad "$1 -- expected [$expected] in: $out" ;;
  esac
}

assert_bar "bar tier: below 50k is green"          10000 "$C_GREEN"   1 "10.0k"
assert_bar "bar tier: 50k boundary turns yellow"   50000 "$C_YELLOW"  5 "50.0k"
assert_bar "bar tier: 75k boundary turns orange"   75000 "$C_ORANGE"  8 "75.0k"
assert_bar "bar tier: 100k boundary turns red"    100000 "$C_RED"    10 "100.0k"
assert_bar "bar fill rounds to the nearest cell"   45000 "$C_GREEN"   5 "45.0k"

# --- Cumulative token counter -------------------------------------------------
# Sigma keeps per-session state on disk, so these render against a throwaway
# HOME. Running them against the real one would both read stale totals and
# scribble on live session counters.
SIGMA=$'\xce\xa3'
render_sess() { printf '%s' "$1" | HOME="$STATE_HOME" bash "$SCRIPT"; }
usage_payload() { # $1 session, $2 input, $3 output, $4 cache_read
  printf '{"cwd":"/tmp","session_id":"%s","context_window":{"current_usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s}}}' \
    "$1" "$2" "$3" "$4"
}

OUT="$(render_sess "$(usage_payload s1 100 50 0)")"
case "$OUT" in
  *"${SIGMA} 150"*) ok "sigma sums input+output on the first call" ;;
  *) bad "expected sigma 150: $OUT" ;;
esac

OUT="$(render_sess "$(usage_payload s1 200 30 0)")"
case "$OUT" in
  *"${SIGMA} 380"*) ok "sigma accumulates across calls" ;;
  *) bad "expected sigma 380: $OUT" ;;
esac

# The statusline re-renders far more often than the API responds, so an
# unchanged usage signature must not be counted a second time.
OUT="$(render_sess "$(usage_payload s1 200 30 0)")"
case "$OUT" in
  *"${SIGMA} 380"*) ok "an unchanged usage signature does not double-count" ;;
  *) bad "expected sigma to stay 380: $OUT" ;;
esac

# Cache traffic is excluded by design: it outweighs conversation volume by two
# orders of magnitude and would swamp the figure.
OUT="$(render_sess "$(usage_payload s1 10 5 900000)")"
case "$OUT" in
  *"${SIGMA} 395"*) ok "cache tokens are excluded from sigma" ;;
  *) bad "expected sigma 395 with cache ignored: $OUT" ;;
esac

OUT="$(render_sess "$(usage_payload s2 7 3 0)")"
case "$OUT" in
  *"${SIGMA} 10"*) ok "sigma is per-session, not global" ;;
  *) bad "expected a fresh sigma of 10 for a new session: $OUT" ;;
esac

# Concurrent renders must not LOSE updates. The statusline re-renders on a timer
# and can overlap with itself, so two processes can read the same total, each add
# their own call, and each write back -- the later write erasing the earlier one.
# The atomic `mv` in the script prevents a torn READ and does nothing whatsoever
# for a lost UPDATE; conflating the two is what left this open.
#
# 20 concurrent writers each contribute a distinct amount, so a lost update
# leaves a total that is both wrong and specific about how much went missing.
#
# The total is read back through a final RENDER rather than by parsing the state
# file, so this asserts the observable behaviour and stays valid across changes
# to how the total is stored. That final render carries a signature no writer
# used and a zero contribution: it is a new call, so it is not skipped as a
# duplicate, and it adds nothing to the figure it is reporting.
#
# Amounts are chosen to keep the total under 1000, because at or above that the
# display switches to k-form ("20.4k") and would round away the exact value the
# assertion depends on.
race_render() { printf '%s' "$1" | HOME="$RACE_HOME" bash "$SCRIPT" >/dev/null 2>&1; }

race_render "$(usage_payload race 100 0 0)"
RACE_EXPECTED=100
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  race_render "$(usage_payload race $((10 + i)) 0 0)" &
  RACE_EXPECTED=$((RACE_EXPECTED + 10 + i))
done
wait
OUT="$(printf '%s' "$(usage_payload race 0 0 0)" | HOME="$RACE_HOME" bash "$SCRIPT")"
case "$OUT" in
  *"${SIGMA} ${RACE_EXPECTED}"*) ok "concurrent renders do not lose sigma updates (total $RACE_EXPECTED)" ;;
  *) bad "sigma lost updates under concurrency: expected $RACE_EXPECTED in: $OUT" ;;
esac

# --- Stale-lock recovery ------------------------------------------------------
# White-box by necessity: these plant lock directories by hand, so they encode
# the lock's name and layout. The coupling is worth it. Both bugs found in the
# lock were invisible to every black-box assertion here -- a PID check that was
# dead code because `read` reports EOF on a file with no trailing newline, and a
# give-up ceiling more than twice its intended length because the age check
# forked per attempt. Hand-probing found them; only the suite keeps them found.
LOCK_STATE_DIR="$LOCK_HOME/.claude/statusline-state"
mkdir -p "$LOCK_STATE_DIR"
LOCK_DIR="$LOCK_STATE_DIR/.session-lockcase.lock"
lock_render() { printf '%s' "$(usage_payload lockcase "$1" 0 0)" | HOME="$LOCK_HOME" bash "$SCRIPT"; }
assert_sigma() { # $1 desc, $2 output, $3 expected total
  case "$2" in
    *"${SIGMA} $3"*) ok "$1" ;;
    *) bad "$1 -- expected sigma $3 in: $2" ;;
  esac
}

# A recently-reaped PID is used rather than a large literal: it is genuinely
# dead, whereas a number like 999999 only happens to exceed the default pid_max.
( exit 0 ) & DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null

# Both newline forms are asserted, and the UNTERMINATED one is the case that
# matters. `read` reports EOF (non-zero) on a final line with no trailing
# newline even though it assigned the value, so a reader that treats that status
# as failure silently discards a perfectly good PID -- which is exactly how the
# PID check came to be dead code. A test that only ever plants a newline-
# terminated file cannot see that bug: it was written this way first, and the
# mutation that restores the bug passed 43/43 against it.
rm -rf "$LOCK_DIR"; mkdir -p "$LOCK_DIR"; printf '%s' "$DEAD_PID" >"$LOCK_DIR/pid"
assert_sigma "dead PID with NO trailing newline is still read and the lock cleared" "$(lock_render 50)" 50

rm -rf "$LOCK_DIR"; mkdir -p "$LOCK_DIR"; printf '%s\n' "$DEAD_PID" >"$LOCK_DIR/pid"
assert_sigma "dead PID with a trailing newline is read and the lock cleared" "$(lock_render 55)" 105

# A pid-less lock is the normal, microseconds-long window of a healthy holder
# between mkdir and the pid write. Breaking it on sight would reintroduce the
# lost update, so a young one must be waited out and the update skipped.
rm -rf "$LOCK_DIR"; mkdir -p "$LOCK_DIR"
assert_sigma "young pid-less lock is left alone and the update is skipped" "$(lock_render 60)" 105

# Same lock, now aged past the staleness threshold: its holder cannot be alive.
# This also demonstrates that a skip is DEFERRAL, not loss -- the signature from
# the skipped render above was never stored, so this render still counts it.
touch -t 202001010000 "$LOCK_DIR"
assert_sigma "aged pid-less lock is broken and the skipped usage is retried" "$(lock_render 60)" 165

# A live holder must never be evicted, however long it holds.
rm -rf "$LOCK_DIR"; mkdir -p "$LOCK_DIR"; printf '%s\n' "$$" >"$LOCK_DIR/pid"
assert_sigma "lock held by a live PID is never broken" "$(lock_render 70)" 165

# A coarse guard against a spin that never terminates or grows without bound.
# It deliberately does NOT claim to catch the per-attempt-fork regression: that
# bug measured ~455ms against an intended ~390ms ceiling, and no portable
# timing assertion separates those two reliably. The comment on LOCK_ATTEMPTS
# in the script is what carries that constraint.
rm -rf "$LOCK_DIR"; mkdir -p "$LOCK_DIR"
LOCK_T0="$(date '+%s')"
lock_render 80 >/dev/null 2>&1
LOCK_ELAPSED=$(( $(date '+%s') - LOCK_T0 ))
if [ "$LOCK_ELAPSED" -le 2 ]; then
  ok "giving up on an unavailable lock stays bounded (${LOCK_ELAPSED}s <= 2s)"
else
  bad "giving up on an unavailable lock took ${LOCK_ELAPSED}s -- spin is unbounded or forking per attempt"
fi
rm -rf "$LOCK_DIR"

# Breaking a stale lock must be atomic with respect to whoever takes it next.
# Every stale-lock case above is single-render, and that is precisely why they
# all pass while this one does not: when several renders each independently
# judge the same lock stale, each removes it, and a removal can delete a lock
# another render has legitimately just acquired -- reintroducing the lost update
# inside the mechanism built to prevent it. Found by the observability judge,
# not by this suite, which is the argument for the case existing at all.
BREAK_STATE_DIR="$BREAK_HOME/.claude/statusline-state"
mkdir -p "$BREAK_STATE_DIR"
break_render() { printf '%s' "$(usage_payload brk "$1" 0 0)" | HOME="$BREAK_HOME" bash "$SCRIPT" >/dev/null 2>&1; }

break_render 100
BREAK_EXPECTED=100
# Plant a stale lock so every one of the concurrent renders below arrives to
# find one, and all of them reach the breaking path at once.
mkdir -p "$BREAK_STATE_DIR/.session-brk.lock"
touch -t 202001010000 "$BREAK_STATE_DIR/.session-brk.lock"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  break_render $((10 + i)) &
  BREAK_EXPECTED=$((BREAK_EXPECTED + 10 + i))
done
wait
OUT="$(printf '%s' "$(usage_payload brk 0 0 0)" | HOME="$BREAK_HOME" bash "$SCRIPT")"
case "$OUT" in
  *"${SIGMA} ${BREAK_EXPECTED}"*) ok "breaking a stale lock under concurrency loses no updates (total $BREAK_EXPECTED)" ;;
  *) bad "stale-lock break lost updates: expected $BREAK_EXPECTED in: $OUT" ;;
esac

# An AGED lock whose PID is still alive is the PID-reuse case: PIDs are reused
# after wraparound, so `kill -0` cannot distinguish a reused PID from the
# original holder, and without an age backstop such a lock wedges this session's
# counter permanently and silently. The backstop runs after the spin, so the
# wedge clears on the render AFTER the one that hit it -- assert exactly that,
# rather than expecting the first render to recover.
#
# Without this case, deleting the whole backstop leaves the suite green: it was
# added on a judge finding and was itself untested, which is how the same class
# of gap keeps recurring on this branch.
rm -rf "$LOCK_DIR"; mkdir -p "$LOCK_DIR"; printf '%s\n' "$$" >"$LOCK_DIR/pid"
touch -t 202001010000 "$LOCK_DIR"
assert_sigma "aged lock held by a LIVE pid does not recover on the first render" "$(lock_render 80)" 165
assert_sigma "aged lock held by a LIVE pid recovers on the next render" "$(lock_render 80)" 245

# A render must never evict a lock it does not own. Here the planted lock is
# young and live, so it is neither stale nor aged: the render must give up,
# leave it standing, and record nothing.
rm -rf "$LOCK_DIR"; mkdir -p "$LOCK_DIR"; printf '%s\n' "$$" >"$LOCK_DIR/pid"
assert_sigma "young live lock blocks the update rather than being evicted" "$(lock_render 90)" 245
if [ -d "$LOCK_DIR" ]; then
  ok "a foreign live lock is still standing after the render gives up"
else
  bad "the render evicted a foreign live lock it did not own"
fi
rm -rf "$LOCK_DIR"

# --- Lock helpers, exercised directly ----------------------------------------
# These guards cannot be reached through a normal render. They only matter when
# a lock is broken and re-taken inside another render's ~3ms critical section,
# which no black-box test can schedule deterministically -- stripping the
# ownership check from release leaves the entire suite green, verified by
# mutation. So the functions are called directly instead, by sourcing the script
# in a SUBSHELL with stdin closed and output discarded. The subshell is what
# keeps the sourced script's many globals from colliding with this file's.
unit_lock_helpers() {
  # shellcheck disable=SC1090
  HOME="$UNIT_HOME" . "$SCRIPT" >/dev/null 2>&1 </dev/null

  mine="$UNIT_HOME/mine.lock"; foreign="$UNIT_HOME/foreign.lock"
  mkdir -p "$mine" "$foreign"
  printf '%s\n' "$$" >"$mine/pid"
  printf '%s\n' "999999" >"$foreign/pid"
  release_lock_if_owned "$mine"
  release_lock_if_owned "$foreign"
  [ -d "$mine" ] && { printf 'release kept a lock it owned\n'; return 1; }
  [ -d "$foreign" ] || { printf 'release removed a lock it did NOT own\n'; return 1; }

  # break_lock_verified, pid mode: matching capture is removed, differing
  # capture is restored rather than destroyed.
  match="$UNIT_HOME/match.lock"; differ="$UNIT_HOME/differ.lock"
  mkdir -p "$match" "$differ"
  printf '%s\n' "4242" >"$match/pid"
  printf '%s\n' "7777" >"$differ/pid"
  break_lock_verified "$match" "pid:4242"
  break_lock_verified "$differ" "pid:4242"
  [ -d "$match" ] && { printf 'pid-mode break kept a verified stale lock\n'; return 1; }
  [ -d "$differ" ] || { printf 'pid-mode break destroyed a lock it had not judged\n'; return 1; }

  # break_lock_verified, age mode: this is the mode whose verification was
  # originally wrong -- the break was justified by age but verified by pid, so a
  # lock re-taken in between passed the check and a live lock was deleted.
  aged="$UNIT_HOME/aged.lock"; fresh="$UNIT_HOME/fresh.lock"
  mkdir -p "$aged" "$fresh"
  touch -t 202001010000 "$aged"
  break_lock_verified "$aged" "age"
  break_lock_verified "$fresh" "age"
  [ -d "$aged" ] && { printf 'age-mode break kept an aged lock\n'; return 1; }
  [ -d "$fresh" ] || { printf 'age-mode break destroyed a FRESH lock\n'; return 1; }

  # A restored lock must come back INTACT, not nested. `mv dirA dirB` moves dirA
  # inside dirB when dirB exists rather than failing, so a restore written with
  # mv can bury the capture inside a live lock -- putting the capture's pid file
  # at the live lock's path, where it defeats the true owner's ownership check.
  [ -f "$differ/pid" ] || { printf 'restored lock lost its pid file\n'; return 1; }
  nested="$(find "$differ" -mindepth 1 -type d | wc -l | tr -d ' ')"
  [ "$nested" = "0" ] || { printf 'restore nested %s directories inside the lock\n' "$nested"; return 1; }
  read -r restored_pid <"$differ/pid"
  [ "$restored_pid" = "7777" ] || { printf 'restored lock has pid %s, not its owner 7777\n' "$restored_pid"; return 1; }

  # Force the OCCUPIED-PATH restore. While age verification forks `find`, the
  # lock path stands empty, so a new holder can take it before the restore runs.
  # That interleaving is the only thing that makes a restore written with mkdir
  # distinguishable from one written with mv: mv nests the capture inside the
  # new holder's lock and its pid file displaces the owner's, defeating the
  # owner's ownership check. Without this case the mv form passes the suite.
  occupied=0
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    raced="$UNIT_HOME/raced$attempt.lock"
    mkdir -p "$raced"; printf '%s\n' "1111" >"$raced/pid"
    break_lock_verified "$raced" "age" &
    bpid=$!
    spins=0
    while [ -d "$raced" ] && [ "$spins" -lt 200000 ]; do spins=$((spins + 1)); done
    if mkdir "$raced" 2>/dev/null; then
      printf '%s\n' "2222" >"$raced/pid"
      occupied=1
    fi
    wait "$bpid" 2>/dev/null
    [ "$occupied" = "1" ] && break
  done
  [ "$occupied" = "1" ] || { printf 'could not construct the occupied-path restore in 20 attempts\n'; return 1; }
  nested_live="$(find "$raced" -mindepth 1 -type d | wc -l | tr -d ' ')"
  [ "$nested_live" = "0" ] || { printf 'occupied-path restore nested %s dirs inside the LIVE lock\n' "$nested_live"; return 1; }
  read -r raced_pid <"$raced/pid" 2>/dev/null
  [ "$raced_pid" = "2222" ] || { printf 'occupied-path restore displaced the live holder pid (got %s)\n' "$raced_pid"; return 1; }

  # A leftover grave from a killed render must make the break fail closed, not
  # nest the new capture inside the stale one.
  blocked="$UNIT_HOME/blocked.lock"
  mkdir -p "$blocked" "$blocked.dead.$$"
  printf '%s\n' "4242" >"$blocked/pid"
  break_lock_verified "$blocked" "pid:4242"
  [ -d "$blocked" ] || { printf 'break proceeded despite a leftover grave\n'; return 1; }
  [ -f "$blocked/pid" ] || { printf 'break disturbed a lock it should have left alone\n'; return 1; }
  rm -rf "$blocked.dead.$$"

  # Nothing may be left behind on any path.
  leftovers="$(find "$UNIT_HOME" -name '*.dead.*' | wc -l | tr -d ' ')"
  [ "$leftovers" = "0" ] || { printf 'break left %s captured directories behind\n' "$leftovers"; return 1; }
  return 0
}
UNIT_ERR="$(unit_lock_helpers 2>&1)" && ok "lock helpers behave correctly when called directly" \
  || bad "lock helper unit checks: $UNIT_ERR"

# A state file in the previous JSON format must not crash the render or be
# misread as a total. It fails charset validation, so the counter restarts.
mkdir -p "$JSON_HOME/.claude/statusline-state"
printf '{"sig":"1:2:3:4","cum_tokens":500}\n' >"$JSON_HOME/.claude/statusline-state/session-legacy.json"
OUT="$(printf '%s' "$(usage_payload legacy 77 0 0)" | HOME="$JSON_HOME" bash "$SCRIPT")"
case "$OUT" in
  *"${SIGMA} 77"*) ok "legacy JSON state file is ignored, counter restarts cleanly" ;;
  *) bad "legacy JSON state file was misread or crashed the render: $OUT" ;;
esac

# --- Weekly quota segment -----------------------------------------------------
# resets_at is epoch SECONDS. An earlier version assumed ISO-8601 and rendered no
# countdown at all -- indistinguishable from the field being absent, so it looked
# like a missing feature rather than a parse failure. These pin both shapes.
CLOCK=$'\xe2\x8f\xb1'
NOW="$(date -u '+%s')"
FUTURE=$((NOW + 200000))  # 2d 7h out
PAST=$((NOW - 100))

quota_payload() { # $1 pct, $2 resets_at ('' to omit the field entirely)
  if [ -z "$2" ]; then
    printf '{"cwd":"/tmp","rate_limits":{"seven_day":{"used_percentage":%s}}}' "$1"
  else
    printf '{"cwd":"/tmp","rate_limits":{"seven_day":{"used_percentage":%s,"resets_at":"%s"}}}' "$1" "$2"
  fi
}

OUT="$(render "$(quota_payload 63 "$FUTURE")")"
case "$OUT" in
  *"${CLOCK} 63% used · resets 2d 7h"*) ok "quota renders percentage plus epoch-seconds countdown" ;;
  *) bad "expected quota with countdown: $OUT" ;;
esac

ISO="$(date -u -r "$FUTURE" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$FUTURE" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"
if [ -n "$ISO" ]; then
  OUT="$(render "$(quota_payload 63 "$ISO")")"
  case "$OUT" in
    *"63% used · resets 2d 7h"*) ok "ISO-8601 resets_at also yields a countdown" ;;
    *) bad "expected a countdown from an ISO timestamp: $OUT" ;;
  esac
else
  bad "could not build an ISO timestamp with either BSD or GNU date"
fi

# A missing, elapsed, or unparseable timestamp degrades to the bare percentage --
# never a stale, negative, or absent segment.
for case_desc in "absent:" "elapsed:$PAST" "unparseable:not-a-timestamp"; do
  label="${case_desc%%:*}"; stamp="${case_desc#*:}"
  OUT="$(render "$(quota_payload 63 "$stamp")")"
  case "$OUT" in
    *"63% used"*)
      case "$OUT" in
        *resets*) bad "$label resets_at rendered a countdown anyway: $OUT" ;;
        *) ok "$label resets_at degrades to the bare percentage" ;;
      esac ;;
    *) bad "$label resets_at lost the quota segment entirely: $OUT" ;;
  esac
done

# --- Group 2: control-byte injection -----------------------------------------

# Each hostile payload is compared against a BENIGN TWIN -- the same payload
# shape with harmless field values -- rather than against one global baseline.
# A single shared baseline only holds while every injection payload renders the
# same segments as it does, and that assumption broke silently: when the context
# bar landed, the baseline payload grew a second segment the injection payloads
# did not carry, and the comparison quietly gained 4 bytes of slack -- roughly
# four colour sequences that could have leaked with every assertion still green.
# A twin cannot drift that way, because adding a segment moves both sides.
assert_no_injection() { # $1 desc, $2 hostile payload, $3 benign twin payload
  local desc="$1" out esc nl bel cr limit
  limit="$(count_byte "$(render "$3")" '\033')"
  out="$(render "$2")"
  esc="$(count_byte "$out" '\033')"
  bel="$(count_byte "$out" '\007')"
  cr="$(count_byte "$out" '\r')"
  nl="$(printf '%s' "$out" | tr -dc '\n' | wc -c | tr -d ' ')"
  if [ "$esc" -le "$limit" ] && [ "$nl" -eq 0 ] && [ "$bel" -eq 0 ] && [ "$cr" -eq 0 ]; then
    ok "$desc (esc=$esc<=$limit nl=$nl bel=$bel cr=$cr)"
  else
    bad "$desc injected control bytes (esc=$esc limit=$limit nl=$nl bel=$bel cr=$cr)"
  fi
}

# Route 1: literal backslash text, which printf '%b' would have expanded.
assert_no_injection "literal \\x1b in display_name stays inert" \
  '{"cwd":"/tmp","model":{"display_name":"Opus\\x1b[5m4.8"}}' \
  '{"cwd":"/tmp","model":{"display_name":"Opus 4.8"}}'

# Route 2: real control bytes, which jq decodes and printf '%s' would forward.
assert_no_injection "real ESC in display_name is stripped" \
  '{"cwd":"/tmp","model":{"display_name":"Opus\u001b[5m4.8"}}' \
  '{"cwd":"/tmp","model":{"display_name":"Opus 4.8"}}'

assert_no_injection "real newline in current_dir cannot split the line" \
  '{"cwd":"/tmp/aa\u000abb"}' \
  '{"cwd":"/tmp/aabb"}'

assert_no_injection "OSC title-rewrite sequence is stripped" \
  '{"cwd":"/tmp","model":{"display_name":"\u001b]0;pwned\u0007Opus"}}' \
  '{"cwd":"/tmp","model":{"display_name":"Opus"}}'

assert_no_injection "carriage return cannot overwrite the line" \
  '{"cwd":"/tmp","model":{"display_name":"Opus\u000d4.8"}}' \
  '{"cwd":"/tmp","model":{"display_name":"Opus4.8"}}'

# Every hostile payload above renders a model segment and no context bar. This
# pair covers the two-segment shape, so the tight comparison is asserted on the
# exact shape whose slack went unnoticed when the bar landed.
assert_no_injection "ESC stripped with model and context bar both rendering" \
  '{"cwd":"/tmp","model":{"display_name":"Opus\u001b[5m4.8"},"context_window":{"total_input_tokens":100}}' \
  '{"cwd":"/tmp","model":{"display_name":"Opus 4.8"},"context_window":{"total_input_tokens":100}}'

# The $PWD fallback is reached whenever stdin yields no usable cwd. $PWD is as
# external as the JSON -- it is a directory name -- so it must be stripped too.
# Regression test for a hole that survived the first strip because the fallback
# was applied after it.
HOSTILE="$TMP/$(printf '\033')]0;HIJACK$(printf '\007')evil"
mkdir -p "$HOSTILE"
# The benign twin for this group must live OUTSIDE any git repo. A sibling of
# $HOSTILE inside $TMP looks like the natural choice and is wrong: the hostile
# directory's real name holds control bytes, so its stripped path does not exist
# on disk, `git -C` fails, and no git segment renders. A twin inside the repo
# does render one, putting the ceiling 8 escapes above what the hostile payload
# can legitimately emit -- looser than the global baseline this group replaced.
# Matching the segment SET is what makes a twin a twin; sharing a parent is not.
BENIGN="$NONGIT/benign"
mkdir -p "$BENIGN"
for shape in '{}' 'garbage' '{"cwd":null}' '{"workspace":{}}'; do
  OUT="$(render_in "$HOSTILE" "$shape" 2>/dev/null)"
  LIMIT_OUT="$(render_in "$BENIGN" "$shape" 2>/dev/null)"
  limit="$(count_byte "$LIMIT_OUT" '\033')"
  bel="$(count_byte "$OUT" '\007')"
  esc="$(count_byte "$OUT" '\033')"
  if [ "$bel" -eq 0 ] && [ "$esc" -le "$limit" ]; then
    ok "\$PWD fallback stripped for stdin '$shape' (esc=$esc<=$limit bel=$bel)"
  else
    bad "\$PWD fallback leaked control bytes for stdin '$shape' (esc=$esc limit=$limit bel=$bel)"
  fi
done

# A cwd of nothing but control bytes strips to empty and falls through to $PWD.
# That second assignment was itself unstripped for one commit, so this asserts
# the fallthrough specifically -- the four shapes above never reach it, because
# they are empty before the strip rather than after it.
CTRL_ONLY='{"cwd":"\u0001\u0002\u0003"}'
OUT="$(render_in "$HOSTILE" "$CTRL_ONLY" 2>/dev/null)"
# Asserted on BEL alone, deliberately. The escape baseline is not usable here:
# when cwd strips to empty, git falls back to the process directory and the git
# segment may or may not render, moving the escape count for reasons unrelated to
# any leak. BEL is never legitimate output, so it is unambiguous.
bel="$(count_byte "$OUT" '\007')"
if [ "$bel" -eq 0 ]; then
  ok "all-control cwd falls through to a stripped \$PWD (bel=$bel)"
else
  bad "all-control cwd leaked via the \$PWD fallthrough (bel=$bel)"
fi

# Stripping must remove the control byte without discarding the whole field.
OUT="$(render '{"cwd":"/tmp","model":{"display_name":"Opus\u001b[5m4.8"}}')"
case "$OUT" in
  *"Opus[5m4.8"*) ok "surrounding text survives stripping" ;;
  *) bad "field content lost, not just its control byte: $OUT" ;;
esac

OUT="$(render '{"cwd":"/tmp/aa\u000abb"}')"
case "$OUT" in
  *aabb*) ok "path with a stripped newline is joined, not truncated" ;;
  *) bad "path truncated at the control byte: $OUT" ;;
esac

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ]
