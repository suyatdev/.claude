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
trap 'rm -rf "$TMP" "$NONGIT" "$STATE_HOME"' EXIT

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
