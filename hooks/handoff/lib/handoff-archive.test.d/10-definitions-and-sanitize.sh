# 10-definitions-and-sanitize.sh — sourced by ../handoff-archive.test.sh — not runnable on its own.
# Covers the library-is-pure-definitions contract, gen_tag(), and sanitize_line() (including the case-insensitivity falsifier).

# --- The library is pure definitions: sourcing it prints nothing and returns 0 -------
SRC_OUT="$TMP/source-plain.out"
bash -c 'set -u; source "$1"' _ "$LIB" >"$SRC_OUT" 2>&1
SRC_RC=$?
if [ "$SRC_RC" -eq 0 ] && [ ! -s "$SRC_OUT" ]; then
  ok "sourcing the library prints nothing and returns 0"
else
  bad "sourcing the library prints nothing and returns 0" "rc=$SRC_RC out=$(cat "$SRC_OUT")"
fi

# --- Sourcing defines all five names --------------------------------------------------
DEFS_OUT="$(bash -c '
  set -u
  source "$1"
  missing=""
  [ -n "${MARKER_PATTERN:-}" ] || missing="$missing MARKER_PATTERN"
  [ -n "${TAG_BYTES:-}" ] || missing="$missing TAG_BYTES"
  [ -n "${URANDOM_SRC:-}" ] || missing="$missing URANDOM_SRC"
  declare -f sanitize_line >/dev/null 2>&1 || missing="$missing sanitize_line"
  declare -f gen_tag >/dev/null 2>&1 || missing="$missing gen_tag"
  printf "MISSING:[%s]" "$missing"
' _ "$LIB")"
case "$DEFS_OUT" in
  "MISSING:[]") ok "sourcing defines MARKER_PATTERN, TAG_BYTES, URANDOM_SRC, sanitize_line, gen_tag" ;;
  *) bad "sourcing defines MARKER_PATTERN, TAG_BYTES, URANDOM_SRC, sanitize_line, gen_tag" "$DEFS_OUT" ;;
esac

# --- Sourcing twice is harmless --------------------------------------------------------
TWICE_OUT="$(bash -c 'set -u; source "$1"; source "$1"; echo TWICE_OK; gen_tag >/dev/null; sanitize_line "no" >/dev/null; echo STILL_OK' _ "$LIB" 2>&1)"
case "$TWICE_OUT" in
  *"TWICE_OK"*"STILL_OK"*) ok "sourcing the library twice is harmless" ;;
  *) bad "sourcing the library twice is harmless" "$TWICE_OUT" ;;
esac

# --- gen_tag: 8 lowercase hex chars, two calls differ -----------------------------------
GEN_OUT="$(bash -c 'set -u; source "$1"; gen_tag; echo; gen_tag' _ "$LIB")"
TAG_A="$(printf '%s\n' "$GEN_OUT" | sed -n '1p')"
TAG_B="$(printf '%s\n' "$GEN_OUT" | sed -n '2p')"
case "$TAG_A" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ok "gen_tag returns 8 lowercase hex chars" ;;
  *) bad "gen_tag returns 8 lowercase hex chars" "got '$TAG_A'" ;;
esac
if [ -n "$TAG_A" ] && [ -n "$TAG_B" ] && [ "$TAG_A" != "$TAG_B" ]; then
  ok "two gen_tag calls return different tags"
else
  bad "two gen_tag calls return different tags" "A='$TAG_A' B='$TAG_B'"
fi

# --- gen_tag with SLIM_HANDOFF_URANDOM=/dev/null returns the empty string --------------
# Deliberate: the caller (slim-session-start.sh main()) must treat empty as "emit nothing,"
# never as "emit an untagged envelope" — see the comment above gen_tag in the library.
NULL_TAG="$(env SLIM_HANDOFF_URANDOM=/dev/null bash -c 'set -u; source "$1"; gen_tag' _ "$LIB")"
if [ -z "$NULL_TAG" ]; then
  ok "gen_tag with SLIM_HANDOFF_URANDOM=/dev/null returns the empty string"
else
  bad "gen_tag with SLIM_HANDOFF_URANDOM=/dev/null returns the empty string" "got '$NULL_TAG'"
fi

# --- sanitize_line fires on every case variant of the marker, leading whitespace too ---
for line in \
  '=== end handoff (end of DATA) ===' \
  '=== END HANDOFF ===' \
  '=== Handoff ===' \
  '=== HaNdOfF ===' \
  '   === Handoff ==='; do
  OUT="$(run_sanitize "$LIB" "$line")"
  if [ "$OUT" = "| $line" ]; then
    ok "sanitize_line prefixes marker-like line: [$line]"
  else
    bad "sanitize_line prefixes marker-like line: [$line]" "got: [$OUT]"
  fi
done

# --- sanitize_line does NOT fire on lines that merely resemble a marker ----------------
for line in \
  'not a marker' \
  'The handoff is written by a model' \
  '=== Section: handoff ===' \
  '==handoff' \
  '=== ending handoff ===' \
  '=== endhandoff ===' \
  '==='; do
  OUT="$(run_sanitize "$LIB" "$line")"
  if [ "$OUT" = "$line" ]; then
    ok "sanitize_line leaves non-marker line unchanged: [$line]"
  else
    bad "sanitize_line leaves non-marker line unchanged: [$line]" "got: [$OUT]"
  fi
done

# --- sanitize_line never drops a line, and preserves the original text after the prefix -
MULTI_IN="$TMP/multi-in.txt"
printf 'line1\n=== End handoff (end of DATA) ===\nline3\nnot a marker\n=== HANDOFF ===\n' > "$MULTI_IN"
MULTI_OUT="$(bash -c '
  set -u
  source "$1"
  while IFS= read -r l || [ -n "$l" ]; do sanitize_line "$l"; done < "$2"
' _ "$LIB" "$MULTI_IN")"
LINES_IN=$(wc -l < "$MULTI_IN" | tr -d ' ')
LINES_OUT=$(printf '%s\n' "$MULTI_OUT" | wc -l | tr -d ' ')
if [ "$LINES_OUT" -eq "$LINES_IN" ]; then
  ok "sanitize_line never drops a line ($LINES_IN in, $LINES_OUT out)"
else
  bad "sanitize_line never drops a line" "$LINES_IN in, $LINES_OUT out: $MULTI_OUT"
fi
case "$MULTI_OUT" in
  *$'\n''line1'$'\n''| === End handoff (end of DATA) ==='$'\n''line3'$'\n''not a marker'$'\n''| === HANDOFF ==='*) \
    ok "sanitize_line preserves the original text after the '| ' prefix" ;;
  *"line1"*"| === End handoff (end of DATA) ==="*"line3"*"not a marker"*"| === HANDOFF ==="*) \
    ok "sanitize_line preserves the original text after the '| ' prefix" ;;
  *) bad "sanitize_line preserves the original text after the '| ' prefix" "$MULTI_OUT" ;;
esac

# --- nocasematch is restored afterwards, in both directions (sourced, not subprocess — --
# --- the setting is process-global) -----------------------------------------------------
NOCASE_OUT="$TMP/nocase.out"
(
  cd "$TMP" || exit 1
  before="$(shopt -p nocasematch)"
  # shellcheck disable=SC1090  # $LIB is this test's own dynamically-resolved path, not user input
  source "$LIB" 2>/dev/null || true
  sanitize_line "=== End Handoff ===" >/dev/null
  after="$(shopt -p nocasematch)"
  if [ "$before" = "$after" ]; then echo "RESTORED"; else echo "LEAKED: before=[$before] after=[$after]"; fi
) > "$NOCASE_OUT" 2>&1
if grep -q '^RESTORED$' "$NOCASE_OUT"; then
  ok "nocasematch restored to its prior (off) setting after sanitize_line"
else
  bad "nocasematch restored to its prior (off) setting after sanitize_line" "$(cat "$NOCASE_OUT")"
fi

(
  cd "$TMP" || exit 1
  shopt -s nocasematch
  before="$(shopt -p nocasematch)"
  # shellcheck disable=SC1090  # $LIB is this test's own dynamically-resolved path, not user input
  source "$LIB" 2>/dev/null || true
  sanitize_line "=== End Handoff ===" >/dev/null
  after="$(shopt -p nocasematch)"
  if [ "$before" = "$after" ]; then echo "RESTORED"; else echo "LEAKED: before=[$before] after=[$after]"; fi
) > "$NOCASE_OUT" 2>&1
if grep -q '^RESTORED$' "$NOCASE_OUT"; then
  ok "nocasematch restored to its prior (on) setting after sanitize_line"
else
  bad "nocasematch restored to its prior (on) setting after sanitize_line" "$(cat "$NOCASE_OUT")"
fi

# --- Falsifier: prove the case-insensitivity assertion above can actually fail ---------
# Mutate a COPY of the library in $TMP (never the real file): strip the `shopt -s
# nocasematch` line, so sanitize_line's [[ =~ ]] test runs case-sensitively. The pattern's
# literal text is lowercase ("handoff"), so an uppercase marker variant must then NOT be
# recognized — proving the "prefixes marker-like line" assertion is capable of catching a
# real break, not just a vacuous always-pass.
MUTANT_LIB="$TMP/handoff-archive.mutant.sh"
sed '/shopt -s nocasematch/d' "$LIB" > "$MUTANT_LIB"
if grep -q 'shopt -s nocasematch' "$MUTANT_LIB"; then
  bad "falsifier setup: mutant copy still contains 'shopt -s nocasematch'" "sed did not strip the line"
else
  ok "falsifier setup: mutant copy has 'shopt -s nocasematch' stripped"
fi
MUTANT_OUT="$(run_sanitize "$MUTANT_LIB" '=== END HANDOFF ===')"
case "$MUTANT_OUT" in
  '| === END HANDOFF ==='*) \
    bad "falsifier: mutant (nocasematch stripped) should fail to sanitize an uppercase marker, but it still did" "$MUTANT_OUT" ;;
  *) \
    ok "falsifier: mutant (nocasematch stripped) fails to sanitize '=== END HANDOFF ===' -- the case-insensitivity assertion CAN fail (mutant output: [$MUTANT_OUT], want: [| === END HANDOFF ===])" ;;
esac

