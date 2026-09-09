#!/usr/bin/env bash
# handoff-archive.test.sh — unit tests for the shared hooks/handoff/lib/handoff-archive.sh
# library extracted from slim-session-start.sh by the extraction step of
# docs/features/handoff-trim-safety.md (named, not numbered — that card renumbers).
# Covers: the library is pure definitions (silent, idempotent, no set -u/-e imposed),
# gen_tag(), sanitize_line(), and the missing-library contract slim-session-start.sh now
# depends on (silent exit 0, emit nothing) — plus a falsifier proving the assertions here
# can actually fail, not just always pass.
# Run: bash hooks/handoff/lib/handoff-archive.test.sh
#
# No CLAUDE_PANE_AGENT short-circuit to worry about here — that guard lives in
# slim-session-start.sh's main(), not in this library, so unlike its sibling suite this
# one does not need `env -u CLAUDE_PANE_AGENT` to get a clean run.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$LIB_DIR/handoff-archive.sh"
HOOK="$(cd "$LIB_DIR/.." && pwd)/slim-session-start.sh"

# Physical path, not the one mktemp hands back — mirrors slim-session-start.test.sh's note:
# on macOS mktemp -d returns the /var symlink form while other tools resolve to /private/var.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

# Sources $1 (a library path) in a fresh bash process under set -u, then runs sanitize_line
# on $2 and prints just its output. Isolates each call from this test script's own state.
run_sanitize() { # $1 lib path, $2 line
  bash -c 'set -u; source "$1"; sanitize_line "$2"' _ "$1" "$2"
}

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

# --- Contract: missing library -> slim-session-start.sh exits 0, emits nothing --------
# The hook-level consequence of making the hook source a library at all: it is Tier 3 and
# informational, and its own header promises silence on every failure, so a missing or
# unreadable library must not print or delay a session start.
MISSING_DIR="$TMP/hook-no-lib"
mkdir -p "$MISSING_DIR"
cp "$HOOK" "$MISSING_DIR/slim-session-start.sh"
# Deliberately no lib/ subdirectory created here.
MISS_OUT="$TMP/missing-lib.out"; MISS_ERR="$TMP/missing-lib.err"
( cd "$TMP" && bash "$MISSING_DIR/slim-session-start.sh" ) >"$MISS_OUT" 2>"$MISS_ERR"
MISS_RC=$?
if [ "$MISS_RC" -eq 0 ] && [ ! -s "$MISS_OUT" ] && [ ! -s "$MISS_ERR" ]; then
  ok "hook with a missing library -> exit 0, no stdout, no stderr"
else
  bad "hook with a missing library -> exit 0, no stdout, no stderr" \
    "rc=$MISS_RC out=$(cat "$MISS_OUT") err=$(cat "$MISS_ERR")"
fi

# --- Contract: unreadable library -> slim-session-start.sh exits 0, emits nothing ------
UNREADABLE_DIR="$TMP/hook-unreadable-lib"
mkdir -p "$UNREADABLE_DIR/lib"
cp "$HOOK" "$UNREADABLE_DIR/slim-session-start.sh"
cp "$LIB" "$UNREADABLE_DIR/lib/handoff-archive.sh"
chmod 000 "$UNREADABLE_DIR/lib/handoff-archive.sh"
if [ -r "$UNREADABLE_DIR/lib/handoff-archive.sh" ]; then
  # Running as a user (e.g. root) that ignores permission bits -- this scenario cannot be
  # constructed here, so skip rather than assert something the fixture cannot produce.
  printf 'skip — unreadable-library fixture is readable anyway (running as root?)\n'
else
  UNREAD_OUT="$TMP/unreadable-lib.out"; UNREAD_ERR="$TMP/unreadable-lib.err"
  ( cd "$TMP" && bash "$UNREADABLE_DIR/slim-session-start.sh" ) >"$UNREAD_OUT" 2>"$UNREAD_ERR"
  UNREAD_RC=$?
  if [ "$UNREAD_RC" -eq 0 ] && [ ! -s "$UNREAD_OUT" ] && [ ! -s "$UNREAD_ERR" ]; then
    ok "hook with an unreadable library -> exit 0, no stdout, no stderr"
  else
    bad "hook with an unreadable library -> exit 0, no stdout, no stderr" \
      "rc=$UNREAD_RC out=$(cat "$UNREAD_OUT") err=$(cat "$UNREAD_ERR")"
  fi
fi
chmod 700 "$UNREADABLE_DIR/lib/handoff-archive.sh" 2>/dev/null || true

# --- Contract: corrupt-but-READABLE library -> exit 0, no stdout, but stderr SPEAKS ----
# A third state neither "missing" nor "unreadable": the file is there and readable but does
# not parse. Pinned deliberately, and deliberately NOT silenced. Exit 0 and empty stdout
# keep the Tier-3 promise (never delay or break a session start, never emit a half-built
# envelope), but the bash parse error is left on stderr on purpose: a library that fails to
# load is a real defect, and swallowing it would reproduce the exact silent-death shape this
# card exists to prevent. The next step on that card pours real code into this file, so the
# behaviour is asserted now rather than discovered later.
CORRUPT_DIR="$TMP/hook-corrupt-lib"
mkdir -p "$CORRUPT_DIR/lib"
cp "$HOOK" "$CORRUPT_DIR/slim-session-start.sh"
printf 'this is not ( valid bash\n' > "$CORRUPT_DIR/lib/handoff-archive.sh"
CORRUPT_REPO="$TMP/corrupt-repo"
mkdir -p "$CORRUPT_REPO/.claude"
( cd "$CORRUPT_REPO" && git init -q )
printf 'notes that must not leak\n' > "$CORRUPT_REPO/.claude/session-state.md"
CORRUPT_OUT="$TMP/corrupt-lib.out"; CORRUPT_ERR="$TMP/corrupt-lib.err"
( cd "$CORRUPT_REPO" && bash "$CORRUPT_DIR/slim-session-start.sh" ) >"$CORRUPT_OUT" 2>"$CORRUPT_ERR"
CORRUPT_RC=$?
if [ "$CORRUPT_RC" -eq 0 ] && [ ! -s "$CORRUPT_OUT" ]; then
  ok "hook with a corrupt-but-readable library -> exit 0, no stdout"
else
  bad "hook with a corrupt-but-readable library -> exit 0, no stdout" \
    "rc=$CORRUPT_RC out=$(cat "$CORRUPT_OUT")"
fi
if [ -s "$CORRUPT_ERR" ]; then
  ok "a corrupt library is NOT silenced -- the parse error reaches stderr"
else
  bad "a corrupt library is NOT silenced -- the parse error reaches stderr" \
    "stderr was empty; a library that fails to load must not die quietly"
fi

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
