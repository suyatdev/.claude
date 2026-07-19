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
# Injection assertions compare against the script's own colour-code baseline
# rather than looking for specific byte patterns, so a surplus escape is caught
# whatever encoding produced it. Testing only the literal-backslash form would
# pass by construction once printf '%b' is gone, while leaving the real-byte
# route wide open -- that is exactly the hole this file exists to close.
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

BASE_PAYLOAD='{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus 4.8"},"context_window":{"total_input_tokens":100}}'
BASE_OUT="$(render "$BASE_PAYLOAD")"
BASE_ESC="$(count_byte "$BASE_OUT" '\033')"

# --- Group 1: rendering -------------------------------------------------------

case "$BASE_OUT" in
  *"Opus 4.8"*"100 tokens"*) ok "baseline renders model and token segments" ;;
  *) bad "baseline segments missing: $BASE_OUT" ;;
esac

OUT="$(render '{"workspace":{"current_dir":"/tmp"}}')"
case "$OUT" in
  *"|"*|*"│"*) bad "no model/tokens should leave no separator: $OUT" ;;
  *) ok "absent model/context_window -> no dangling separator" ;;
esac

OUT="$(render '{"cwd":"/tmp","context_window":{"total_input_tokens":42}}')"
case "$OUT" in
  *"42 tokens"*) ok "sub-1000 tokens render raw, not k-formatted" ;;
  *) bad "expected raw token count: $OUT" ;;
esac

OUT="$(render '{"cwd":"/tmp","context_window":{"total_input_tokens":113300}}')"
case "$OUT" in
  *"113.3k tokens"*) ok "tokens >=1000 render in k form" ;;
  *) bad "expected k-formatted tokens: $OUT" ;;
esac

OUT="$(render '{"cwd":"/tmp"}')"
case "$OUT" in
  *"git:("*) bad "non-git dir should have no git segment: $OUT" ;;
  *) ok "non-git directory -> no git segment" ;;
esac

# Build a throwaway repo rather than assuming the script sits inside one --
# otherwise this assertion silently depends on where the file was copied to.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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

# --- Group 2: control-byte injection -----------------------------------------

assert_no_injection() { # $1 desc, $2 payload
  local desc="$1" out esc nl bel cr
  out="$(render "$2")"
  esc="$(count_byte "$out" '\033')"
  bel="$(count_byte "$out" '\007')"
  cr="$(count_byte "$out" '\r')"
  nl="$(printf '%s' "$out" | tr -dc '\n' | wc -c | tr -d ' ')"
  if [ "$esc" -le "$BASE_ESC" ] && [ "$nl" -eq 0 ] && [ "$bel" -eq 0 ] && [ "$cr" -eq 0 ]; then
    ok "$desc (esc=$esc<=$BASE_ESC nl=$nl bel=$bel cr=$cr)"
  else
    bad "$desc injected control bytes (esc=$esc base=$BASE_ESC nl=$nl bel=$bel cr=$cr)"
  fi
}

# Route 1: literal backslash text, which printf '%b' would have expanded.
assert_no_injection "literal \\x1b in display_name stays inert" \
  '{"cwd":"/tmp","model":{"display_name":"Opus\\x1b[5m4.8"}}'

# Route 2: real control bytes, which jq decodes and printf '%s' would forward.
assert_no_injection "real ESC in display_name is stripped" \
  '{"cwd":"/tmp","model":{"display_name":"Opus\u001b[5m4.8"}}'

assert_no_injection "real newline in current_dir cannot split the line" \
  '{"cwd":"/tmp/aa\u000abb"}'

assert_no_injection "OSC title-rewrite sequence is stripped" \
  '{"cwd":"/tmp","model":{"display_name":"\u001b]0;pwned\u0007Opus"}}'

assert_no_injection "carriage return cannot overwrite the line" \
  '{"cwd":"/tmp","model":{"display_name":"Opus\u000d4.8"}}'

# The $PWD fallback is reached whenever stdin yields no usable cwd. $PWD is as
# external as the JSON -- it is a directory name -- so it must be stripped too.
# Regression test for a hole that survived the first strip because the fallback
# was applied after it.
HOSTILE="$TMP/$(printf '\033')]0;HIJACK$(printf '\007')evil"
mkdir -p "$HOSTILE"
for shape in '{}' 'garbage' '{"cwd":null}' '{"workspace":{}}'; do
  OUT="$(render_in "$HOSTILE" "$shape" 2>/dev/null)"
  bel="$(count_byte "$OUT" '\007')"
  esc="$(count_byte "$OUT" '\033')"
  if [ "$bel" -eq 0 ] && [ "$esc" -le "$BASE_ESC" ]; then
    ok "\$PWD fallback stripped for stdin '$shape' (esc=$esc bel=$bel)"
  else
    bad "\$PWD fallback leaked control bytes for stdin '$shape' (esc=$esc bel=$bel)"
  fi
done

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
