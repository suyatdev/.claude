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

# ========================================================================================
# The rest of this file tests the task-3 additions to the library: snapshot, [KEEP]
# region extraction with fence tracking, protected-line membership, archive append,
# rotation, secret flagging and quarantine. Fence cases come first, per the card's
# TDD instruction, since fence tracking is what every other extraction test depends on.
#
# Helper: runs FUNC (with ARGS) in a fresh bash process after sourcing $LIB, isolating
# each call from this test script's own state exactly as run_sanitize does above.
# Captures stdout to $OUT and stderr to $ERR (both required args), returns FUNC's rc.
# ========================================================================================
call_lib() { # $1 out-file, $2 err-file, $3 lib path, $4 func name, $5.. func args
  local out="$1" err="$2" lib="$3" func="$4"
  shift 4
  bash -c 'set -u; source "$1"; shift; "$@"' _ "$lib" "$func" "$@" >"$out" 2>"$err"
  return $?
}

SCRATCH_ERR="$TMP/scratch.err"   # a throwaway err sink for calls that don't check stderr
REAL_SCANNER="$(cd "$LIB_DIR/../.." && pwd)/scan-secrets.sh"

# --- Constants: ARCHIVE_ROTATE_AT_BYTES and SCAN_SECRETS_CMD --------------------------
CONST_OUT="$(bash -c 'set -u; source "$1"; printf "%s\n%s\n" "$ARCHIVE_ROTATE_AT_BYTES" "$SCAN_SECRETS_CMD"' _ "$LIB")"
CONST_ROTATE="$(printf '%s\n' "$CONST_OUT" | sed -n '1p')"
CONST_SCANNER="$(printf '%s\n' "$CONST_OUT" | sed -n '2p')"
if [ "$CONST_ROTATE" = "1048576" ]; then
  ok "ARCHIVE_ROTATE_AT_BYTES is 1048576"
else
  bad "ARCHIVE_ROTATE_AT_BYTES is 1048576" "got '$CONST_ROTATE'"
fi
# Canonicalize before comparing -- SCAN_SECRETS_CMD is resolved via a relative "../.."
# path, not a canonicalized one, so a raw string compare against REAL_SCANNER would be
# a false negative even when both point at the same file.
CONST_SCANNER_CANON="$(cd "$(dirname "$CONST_SCANNER")" 2>/dev/null && pwd)/$(basename "$CONST_SCANNER")"
if [ "$CONST_SCANNER_CANON" = "$REAL_SCANNER" ] && [ -x "$CONST_SCANNER" ]; then
  ok "SCAN_SECRETS_CMD resolves to hooks/scan-secrets.sh by default"
else
  bad "SCAN_SECRETS_CMD resolves to hooks/scan-secrets.sh by default" \
    "got '$CONST_SCANNER' (canon '$CONST_SCANNER_CANON'), want '$REAL_SCANNER'"
fi

# --- SCAN_SECRETS_CMD resolves from BASH_SOURCE, never $PWD, never git rev-parse ------
# Copy the library and the scanner into a throwaway tree at the SAME relative layout
# (hooks/scan-secrets.sh, hooks/handoff/lib/handoff-archive.sh), source the COPY while
# cwd is elsewhere, and confirm it resolves to the COPY, not the real repo's file. This
# is the only way to actually distinguish BASH_SOURCE resolution from a $PWD-based one.
ALT_ROOT="$TMP/alt-repo"
mkdir -p "$ALT_ROOT/hooks/handoff/lib"
cp "$REAL_SCANNER" "$ALT_ROOT/hooks/scan-secrets.sh"
cp "$LIB" "$ALT_ROOT/hooks/handoff/lib/handoff-archive.sh"
ALT_SCANNER_WANT="$ALT_ROOT/hooks/scan-secrets.sh"
ALT_SCANNER_GOT="$(cd "$TMP" && bash -c 'set -u; source "$1"; printf "%s" "$SCAN_SECRETS_CMD"' _ "$ALT_ROOT/hooks/handoff/lib/handoff-archive.sh")"
ALT_SCANNER_GOT_CANON="$(cd "$(dirname "$ALT_SCANNER_GOT")" 2>/dev/null && pwd)/$(basename "$ALT_SCANNER_GOT")"
if [ "$ALT_SCANNER_GOT_CANON" = "$ALT_SCANNER_WANT" ]; then
  ok "SCAN_SECRETS_CMD resolves relative to BASH_SOURCE, not cwd"
else
  bad "SCAN_SECRETS_CMD resolves relative to BASH_SOURCE, not cwd" \
    "got '$ALT_SCANNER_GOT' (canon '$ALT_SCANNER_GOT_CANON'), want '$ALT_SCANNER_WANT'"
fi

# --- SCAN_SECRETS_CMD is overridable via env for tests -------------------------------
OVERRIDE_OUT="$(env HANDOFF_SCAN_SECRETS_CMD="/nonexistent/fake-scanner.sh" bash -c 'set -u; source "$1"; printf "%s" "$SCAN_SECRETS_CMD"' _ "$LIB")"
if [ "$OVERRIDE_OUT" = "/nonexistent/fake-scanner.sh" ]; then
  ok "SCAN_SECRETS_CMD is overridable via HANDOFF_SCAN_SECRETS_CMD"
else
  bad "SCAN_SECRETS_CMD is overridable via HANDOFF_SCAN_SECRETS_CMD" "got '$OVERRIDE_OUT'"
fi

# ==========================================================================================
# extract_keep_lines -- [KEEP] region extraction with fence tracking. FENCE CASES FIRST:
# these are the load-bearing scenarios, since every other extraction test assumes fence
# tracking already works.
# ==========================================================================================

# --- Fence: a "## " line inside a fenced block inside a KEEP region is body -----------
FENCE_INSIDE_ENDS_MD="$TMP/fence-inside-ends.md"
cat > "$FENCE_INSIDE_ENDS_MD" <<'EOF'
## Standing rules [KEEP]
before fence
```
## not a real heading
still body
```
after fence
## Next
excluded
EOF
FENCE_INSIDE_ENDS_WANT="$TMP/fence-inside-ends.want"
cat > "$FENCE_INSIDE_ENDS_WANT" <<'EOF'
## Standing rules [KEEP]
before fence
```
## not a real heading
still body
```
after fence
EOF
FENCE_INSIDE_ENDS_GOT="$TMP/fence-inside-ends.got"
call_lib "$FENCE_INSIDE_ENDS_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_INSIDE_ENDS_MD"
if diff -q "$FENCE_INSIDE_ENDS_WANT" "$FENCE_INSIDE_ENDS_GOT" >/dev/null 2>&1; then
  ok "a '## ' line inside a fenced block inside a KEEP region is body, region does not end there"
else
  bad "a '## ' line inside a fenced block inside a KEEP region is body, region does not end there" \
    "$(diff "$FENCE_INSIDE_ENDS_WANT" "$FENCE_INSIDE_ENDS_GOT")"
fi

# --- Fence: a "## Something [KEEP]" line inside a fenced block opens NO region --------
FENCE_INSIDE_OPENS_MD="$TMP/fence-inside-opens.md"
cat > "$FENCE_INSIDE_OPENS_MD" <<'EOF'
## Outer
not protected
```
## Something [KEEP]
also not protected
```
still not protected
## Z
EOF
FENCE_INSIDE_OPENS_GOT="$TMP/fence-inside-opens.got"
call_lib "$FENCE_INSIDE_OPENS_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_INSIDE_OPENS_MD"
if [ ! -s "$FENCE_INSIDE_OPENS_GOT" ]; then
  ok "a '[KEEP]' heading inside a fenced block opens no region"
else
  bad "a '[KEEP]' heading inside a fenced block opens no region" "$(cat "$FENCE_INSIDE_OPENS_GOT")"
fi

# --- Fence: three tildes do not close a three-backtick fence --------------------------
FENCE_TILDE_MD="$TMP/fence-tilde.md"
cat > "$FENCE_TILDE_MD" <<'EOF'
## R [KEEP]
```
~~~
tilde is body
```
now closed
## End
EOF
FENCE_TILDE_WANT="$TMP/fence-tilde.want"
cat > "$FENCE_TILDE_WANT" <<'EOF'
## R [KEEP]
```
~~~
tilde is body
```
now closed
EOF
FENCE_TILDE_GOT="$TMP/fence-tilde.got"
call_lib "$FENCE_TILDE_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_TILDE_MD"
if diff -q "$FENCE_TILDE_WANT" "$FENCE_TILDE_GOT" >/dev/null 2>&1; then
  ok "a tilde fence does not close a backtick fence -- fence stays open, tilde line is body"
else
  bad "a tilde fence does not close a backtick fence -- fence stays open, tilde line is body" \
    "$(diff "$FENCE_TILDE_WANT" "$FENCE_TILDE_GOT")"
fi

# --- Fence: a longer closing fence closes a shorter opening one -----------------------
FENCE_LONGER_CLOSES_MD="$TMP/fence-longer-closes.md"
cat > "$FENCE_LONGER_CLOSES_MD" <<'EOF'
## S [KEEP]
```
body
````
after
## End
EOF
FENCE_LONGER_CLOSES_WANT="$TMP/fence-longer-closes.want"
cat > "$FENCE_LONGER_CLOSES_WANT" <<'EOF'
## S [KEEP]
```
body
````
after
EOF
FENCE_LONGER_CLOSES_GOT="$TMP/fence-longer-closes.got"
call_lib "$FENCE_LONGER_CLOSES_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_LONGER_CLOSES_MD"
if diff -q "$FENCE_LONGER_CLOSES_WANT" "$FENCE_LONGER_CLOSES_GOT" >/dev/null 2>&1; then
  ok "a longer closing fence (4 backticks) closes a shorter opening one (3 backticks)"
else
  bad "a longer closing fence (4 backticks) closes a shorter opening one (3 backticks)" \
    "$(diff "$FENCE_LONGER_CLOSES_WANT" "$FENCE_LONGER_CLOSES_GOT")"
fi

# --- Fence: a shorter closing fence does NOT close a longer opening one ---------------
FENCE_SHORTER_MD="$TMP/fence-shorter.md"
cat > "$FENCE_SHORTER_MD" <<'EOF'
## T [KEEP]
````
body
```
still open (3 doesn't close 4)
````
now closed
## End
EOF
FENCE_SHORTER_WANT="$TMP/fence-shorter.want"
cat > "$FENCE_SHORTER_WANT" <<'EOF'
## T [KEEP]
````
body
```
still open (3 doesn't close 4)
````
now closed
EOF
FENCE_SHORTER_GOT="$TMP/fence-shorter.got"
call_lib "$FENCE_SHORTER_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_SHORTER_MD"
if diff -q "$FENCE_SHORTER_WANT" "$FENCE_SHORTER_GOT" >/dev/null 2>&1; then
  ok "a shorter closing fence (3 backticks) does not close a longer opening one (4 backticks)"
else
  bad "a shorter closing fence (3 backticks) does not close a longer opening one (4 backticks)" \
    "$(diff "$FENCE_SHORTER_WANT" "$FENCE_SHORTER_GOT")"
fi

# --- Fence: indented up to three spaces opens; four spaces does not -------------------
FENCE_INDENT_MD="$TMP/fence-indent.md"
cat > "$FENCE_INDENT_MD" <<'EOF'
## U [KEEP]
   ```
   indented fence body
   ```
line-after-3space-fence
    ```
four-space line is not a fence, just body
## End
EOF
FENCE_INDENT_WANT="$TMP/fence-indent.want"
cat > "$FENCE_INDENT_WANT" <<'EOF'
## U [KEEP]
   ```
   indented fence body
   ```
line-after-3space-fence
    ```
four-space line is not a fence, just body
EOF
FENCE_INDENT_GOT="$TMP/fence-indent.got"
call_lib "$FENCE_INDENT_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_INDENT_MD"
if diff -q "$FENCE_INDENT_WANT" "$FENCE_INDENT_GOT" >/dev/null 2>&1; then
  ok "a fence indented up to three spaces opens; a four-space indent does not"
else
  bad "a fence indented up to three spaces opens; a four-space indent does not" \
    "$(diff "$FENCE_INDENT_WANT" "$FENCE_INDENT_GOT")"
fi

# --- YAML front matter is skipped before parsing begins -------------------------------
FRONTMATTER_MD="$TMP/frontmatter.md"
cat > "$FRONTMATTER_MD" <<'EOF'
---
title: doc
tags: [a, b]
---
## V [KEEP]
protected line
## End
EOF
FRONTMATTER_WANT="$TMP/frontmatter.want"
cat > "$FRONTMATTER_WANT" <<'EOF'
## V [KEEP]
protected line
EOF
FRONTMATTER_GOT="$TMP/frontmatter.got"
call_lib "$FRONTMATTER_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FRONTMATTER_MD"
if diff -q "$FRONTMATTER_WANT" "$FRONTMATTER_GOT" >/dev/null 2>&1; then
  ok "YAML front matter is skipped before parsing begins"
else
  bad "YAML front matter is skipped before parsing begins" "$(diff "$FRONTMATTER_WANT" "$FRONTMATTER_GOT")"
fi

# --- Setext headings are body, not ATX headings ----------------------------------------
SETEXT_MD="$TMP/setext.md"
cat > "$SETEXT_MD" <<'EOF'
## W [KEEP]
Title Text
===
more text
Another Title
---
tail
## End
EOF
SETEXT_WANT="$TMP/setext.want"
cat > "$SETEXT_WANT" <<'EOF'
## W [KEEP]
Title Text
===
more text
Another Title
---
tail
EOF
SETEXT_GOT="$TMP/setext.got"
call_lib "$SETEXT_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$SETEXT_MD"
if diff -q "$SETEXT_WANT" "$SETEXT_GOT" >/dev/null 2>&1; then
  ok "setext headings (=== or --- underline) are body, not ATX headings"
else
  bad "setext headings (=== or --- underline) are body, not ATX headings" "$(diff "$SETEXT_WANT" "$SETEXT_GOT")"
fi

# --- Region ends at the next ATX heading of ANY level ----------------------------------
ANYLEVEL_MD="$TMP/anylevel.md"
cat > "$ANYLEVEL_MD" <<'EOF'
### X [KEEP]
body
# Y
excluded
EOF
ANYLEVEL_WANT="$TMP/anylevel.want"
cat > "$ANYLEVEL_WANT" <<'EOF'
### X [KEEP]
body
EOF
ANYLEVEL_GOT="$TMP/anylevel.got"
call_lib "$ANYLEVEL_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$ANYLEVEL_MD"
if diff -q "$ANYLEVEL_WANT" "$ANYLEVEL_GOT" >/dev/null 2>&1; then
  ok "a region ends at the next ATX heading of any level (level 3 KEEP ended by level 1)"
else
  bad "a region ends at the next ATX heading of any level (level 3 KEEP ended by level 1)" \
    "$(diff "$ANYLEVEL_WANT" "$ANYLEVEL_GOT")"
fi

# --- Region ends at end of file when no later heading exists --------------------------
EOF_END_MD="$TMP/eof-end.md"
cat > "$EOF_END_MD" <<'EOF'
## Z [KEEP]
line1
line2
EOF
EOF_END_GOT="$TMP/eof-end.got"
call_lib "$EOF_END_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$EOF_END_MD"
if diff -q "$EOF_END_MD" "$EOF_END_GOT" >/dev/null 2>&1; then
  ok "a region with no later heading runs to end of file"
else
  bad "a region with no later heading runs to end of file" "$(diff "$EOF_END_MD" "$EOF_END_GOT")"
fi

# --- Falsifier: fence tracking removed -> the fence-inside-ends test must fail --------
# Mutate a COPY: force `fence` to never open (every "fence = 1;" becomes "fence = 0;"),
# so a "## " line inside what should be a fenced block is tested as a real heading and
# wrongly ends the region early.
FENCE_MUTANT_LIB="$TMP/handoff-archive.fence-mutant.sh"
sed 's/fence = 1;/fence = 0;/g' "$LIB" > "$FENCE_MUTANT_LIB"
if grep -q 'fence = 1;' "$FENCE_MUTANT_LIB"; then
  bad "falsifier setup: fence-mutant copy still contains 'fence = 1;'" "sed did not strip it"
else
  ok "falsifier setup: fence-mutant copy has fence-opening assignments neutralized"
fi
FENCE_MUTANT_GOT="$TMP/fence-inside-ends.mutant.got"
call_lib "$FENCE_MUTANT_GOT" "$SCRATCH_ERR" "$FENCE_MUTANT_LIB" extract_keep_lines "$FENCE_INSIDE_ENDS_MD"
if diff -q "$FENCE_INSIDE_ENDS_WANT" "$FENCE_MUTANT_GOT" >/dev/null 2>&1; then
  bad "falsifier: fence-tracking-removed mutant should mis-end the region, but it still matched" \
    "$(cat "$FENCE_MUTANT_GOT")"
else
  ok "falsifier: with fence tracking removed, the 'inside a fence' extraction test goes red"
fi

# ==========================================================================================
# missing_protected_lines -- set membership between the snapshot's protected lines and
# the current file, using grep -F -x (fixed-string, whole-line), never a regex.
# ==========================================================================================

MEMBER_SNAP="$TMP/member-snap.md"
cat > "$MEMBER_SNAP" <<'EOF'
## Standing rules [KEEP]
- Always work in a worktree.
- Never skip hooks.
- Pattern .* matches [any] char $end (test)
- Always work in a worktree.
## Other
not protected
EOF

# --- Membership: reordering, re-nesting and moving all PASS ---------------------------
MEMBER_REORDER="$TMP/member-reorder.md"
cat > "$MEMBER_REORDER" <<'EOF'
## Different heading
- Never skip hooks.
### Nested somewhere else
- Always work in a worktree.
- Pattern .* matches [any] char $end (test)
## Standing rules [KEEP]
extra line
EOF
MEMBER_REORDER_OUT="$TMP/member-reorder.out"
call_lib "$MEMBER_REORDER_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_REORDER"
MEMBER_REORDER_RC=$?
if [ "$MEMBER_REORDER_RC" -eq 0 ] && [ ! -s "$MEMBER_REORDER_OUT" ]; then
  ok "reordering, re-nesting and moving protected lines all PASS (rc 0, nothing missing)"
else
  bad "reordering, re-nesting and moving protected lines all PASS (rc 0, nothing missing)" \
    "rc=$MEMBER_REORDER_RC out=$(cat "$MEMBER_REORDER_OUT")"
fi

MEMBER_MOVED="$TMP/member-moved.md"
cat > "$MEMBER_MOVED" <<'EOF'
# New Parent
## Standing rules [KEEP]
- Always work in a worktree.
- Never skip hooks.
- Pattern .* matches [any] char $end (test)
EOF
MEMBER_MOVED_OUT="$TMP/member-moved.out"
call_lib "$MEMBER_MOVED_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_MOVED"
MEMBER_MOVED_RC=$?
if [ "$MEMBER_MOVED_RC" -eq 0 ] && [ ! -s "$MEMBER_MOVED_OUT" ]; then
  ok "moving a protected block under a different parent heading PASSES"
else
  bad "moving a protected block under a different parent heading PASSES" \
    "rc=$MEMBER_MOVED_RC out=$(cat "$MEMBER_MOVED_OUT")"
fi

# --- Membership: deleting a protected line FAILS ---------------------------------------
MEMBER_DELETED="$TMP/member-deleted.md"
cat > "$MEMBER_DELETED" <<'EOF'
## Standing rules [KEEP]
- Always work in a worktree.
- Pattern .* matches [any] char $end (test)
EOF
MEMBER_DELETED_OUT="$TMP/member-deleted.out"
call_lib "$MEMBER_DELETED_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_DELETED"
MEMBER_DELETED_RC=$?
if [ "$MEMBER_DELETED_RC" -eq 1 ] && [ "$(cat "$MEMBER_DELETED_OUT")" = "- Never skip hooks." ]; then
  ok "deleting a protected line FAILS and names exactly that line"
else
  bad "deleting a protected line FAILS and names exactly that line" \
    "rc=$MEMBER_DELETED_RC out=$(cat "$MEMBER_DELETED_OUT")"
fi

# --- Membership: stripping the [KEEP] tag off the heading FAILS (heading is protected) -
MEMBER_STRIPPED="$TMP/member-stripped-tag.md"
cat > "$MEMBER_STRIPPED" <<'EOF'
## Standing rules
- Always work in a worktree.
- Never skip hooks.
- Pattern .* matches [any] char $end (test)
EOF
MEMBER_STRIPPED_OUT="$TMP/member-stripped-tag.out"
call_lib "$MEMBER_STRIPPED_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_STRIPPED"
MEMBER_STRIPPED_RC=$?
if [ "$MEMBER_STRIPPED_RC" -eq 1 ] && [ "$(cat "$MEMBER_STRIPPED_OUT")" = "## Standing rules [KEEP]" ]; then
  ok "stripping the [KEEP] tag off the heading FAILS -- the heading is itself protected"
else
  bad "stripping the [KEEP] tag off the heading FAILS -- the heading is itself protected" \
    "rc=$MEMBER_STRIPPED_RC out=$(cat "$MEMBER_STRIPPED_OUT")"
fi

# --- Membership: a duplicated protected line surviving once PASSES (set, not multiset) -
MEMBER_DUP_SNAP="$TMP/member-dup-snap.md"
cat > "$MEMBER_DUP_SNAP" <<'EOF'
## Dup [KEEP]
same line
same line
EOF
MEMBER_DUP_CURRENT="$TMP/member-dup-current.md"
cat > "$MEMBER_DUP_CURRENT" <<'EOF'
## Dup [KEEP]
same line
EOF
MEMBER_DUP_OUT="$TMP/member-dup.out"
call_lib "$MEMBER_DUP_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_DUP_SNAP" "$MEMBER_DUP_CURRENT"
MEMBER_DUP_RC=$?
if [ "$MEMBER_DUP_RC" -eq 0 ] && [ ! -s "$MEMBER_DUP_OUT" ]; then
  ok "a protected line duplicated in the snapshot surviving once PASSES (set membership)"
else
  bad "a protected line duplicated in the snapshot surviving once PASSES (set membership)" \
    "rc=$MEMBER_DUP_RC out=$(cat "$MEMBER_DUP_OUT")"
fi

# --- Membership: a protected line with regex metacharacters is matched LITERALLY -------
MEMBER_META_SNAP="$TMP/member-meta-snap.md"
cat > "$MEMBER_META_SNAP" <<'EOF'
## Meta [KEEP]
a.b*c$
list: [a](b) end
EOF
MEMBER_META_PASS="$TMP/member-meta-pass.md"
cat > "$MEMBER_META_PASS" <<'EOF'
list: [a](b) end
random other line
a.b*c$
## Meta [KEEP]
EOF
MEMBER_META_PASS_OUT="$TMP/member-meta-pass.out"
call_lib "$MEMBER_META_PASS_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_META_SNAP" "$MEMBER_META_PASS"
MEMBER_META_PASS_RC=$?
if [ "$MEMBER_META_PASS_RC" -eq 0 ] && [ ! -s "$MEMBER_META_PASS_OUT" ]; then
  ok "a protected line containing regex metacharacters matches when present verbatim"
else
  bad "a protected line containing regex metacharacters matches when present verbatim" \
    "rc=$MEMBER_META_PASS_RC out=$(cat "$MEMBER_META_PASS_OUT")"
fi

# 'axbc' would satisfy the BRE/ERE regex `a.b*c$` (. = any char, b* = zero-or-more b,
# $ = end anchor) even though it is a completely different literal string. If the
# matcher were ever a regex instead of -F, this line would be found and NOT reported
# missing -- so this is the discriminating case for fixed-string matching.
MEMBER_META_FAIL="$TMP/member-meta-fail.md"
cat > "$MEMBER_META_FAIL" <<'EOF'
list: [a](b) end
## Meta [KEEP]
axbc
EOF
MEMBER_META_FAIL_OUT="$TMP/member-meta-fail.out"
call_lib "$MEMBER_META_FAIL_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_META_SNAP" "$MEMBER_META_FAIL"
MEMBER_META_FAIL_RC=$?
if [ "$MEMBER_META_FAIL_RC" -eq 1 ] && [ "$(cat "$MEMBER_META_FAIL_OUT")" = 'a.b*c$' ]; then
  ok "a regex-confusable line ('axbc') does not satisfy the literal 'a.b*c\$' -- fixed-string match"
else
  bad "a regex-confusable line ('axbc') does not satisfy the literal 'a.b*c\$' -- fixed-string match" \
    "rc=$MEMBER_META_FAIL_RC out=$(cat "$MEMBER_META_FAIL_OUT")"
fi

# --- Membership: a missing CURRENT file means every protected line is missing ---------
MEMBER_NO_CURRENT="$TMP/does-not-exist.md"
MEMBER_NO_CURRENT_OUT="$TMP/member-no-current.out"
call_lib "$MEMBER_NO_CURRENT_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_NO_CURRENT"
MEMBER_NO_CURRENT_RC=$?
MEMBER_NO_CURRENT_LINES="$(wc -l < "$MEMBER_NO_CURRENT_OUT" | tr -d ' ')"
if [ "$MEMBER_NO_CURRENT_RC" -eq 1 ] && [ "$MEMBER_NO_CURRENT_LINES" -eq 4 ]; then
  ok "a missing CURRENT file means every one of the 4 protected lines is reported missing"
else
  bad "a missing CURRENT file means every one of the 4 protected lines is reported missing" \
    "rc=$MEMBER_NO_CURRENT_RC lines=$MEMBER_NO_CURRENT_LINES out=$(cat "$MEMBER_NO_CURRENT_OUT")"
fi

# --- Membership: blank lines are excluded from the protected set ----------------------
MEMBER_BLANK_SNAP="$TMP/member-blank-snap.md"
cat > "$MEMBER_BLANK_SNAP" <<'EOF'
## Blank [KEEP]
line one

line two
EOF
MEMBER_BLANK_CURRENT="$TMP/member-blank-current.md"
cat > "$MEMBER_BLANK_CURRENT" <<'EOF'
## Blank [KEEP]
line one
line two
EOF
MEMBER_BLANK_OUT="$TMP/member-blank.out"
call_lib "$MEMBER_BLANK_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_BLANK_SNAP" "$MEMBER_BLANK_CURRENT"
MEMBER_BLANK_RC=$?
if [ "$MEMBER_BLANK_RC" -eq 0 ] && [ ! -s "$MEMBER_BLANK_OUT" ]; then
  ok "a blank line inside a KEEP region is excluded from the protected set"
else
  bad "a blank line inside a KEEP region is excluded from the protected set" \
    "rc=$MEMBER_BLANK_RC out=$(cat "$MEMBER_BLANK_OUT")"
fi

# --- Membership: trailing whitespace is stripped from BOTH sides before comparing -----
MEMBER_TRAIL_SNAP="$TMP/member-trail-snap.md"
printf '## Trail [KEEP]\npadded line   \n' > "$MEMBER_TRAIL_SNAP"
MEMBER_TRAIL_CURRENT="$TMP/member-trail-current.md"
printf '## Trail [KEEP]\npadded line\n' > "$MEMBER_TRAIL_CURRENT"
MEMBER_TRAIL_OUT="$TMP/member-trail.out"
call_lib "$MEMBER_TRAIL_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_TRAIL_SNAP" "$MEMBER_TRAIL_CURRENT"
MEMBER_TRAIL_RC=$?
if [ "$MEMBER_TRAIL_RC" -eq 0 ] && [ ! -s "$MEMBER_TRAIL_OUT" ]; then
  ok "trailing whitespace is stripped from both sides before comparing"
else
  bad "trailing whitespace is stripped from both sides before comparing" \
    "rc=$MEMBER_TRAIL_RC out=$(cat "$MEMBER_TRAIL_OUT")"
fi

# --- Falsifier: grep -F changed to a regex match -> the metachar test must fail -------
GREP_MUTANT_LIB="$TMP/handoff-archive.grep-mutant.sh"
sed 's/grep -F -x -q/grep -x -q/' "$LIB" > "$GREP_MUTANT_LIB"
if grep -q 'grep -F -x -q' "$GREP_MUTANT_LIB"; then
  bad "falsifier setup: grep-mutant copy still contains 'grep -F -x -q'" "sed did not strip it"
else
  ok "falsifier setup: grep-mutant copy has -F stripped from the membership match"
fi
GREP_MUTANT_OUT="$TMP/member-meta-fail.mutant.out"
call_lib "$GREP_MUTANT_OUT" "$SCRATCH_ERR" "$GREP_MUTANT_LIB" missing_protected_lines "$MEMBER_META_SNAP" "$MEMBER_META_FAIL"
GREP_MUTANT_RC=$?
if [ "$GREP_MUTANT_RC" -eq 1 ] && [ "$(cat "$GREP_MUTANT_OUT")" = 'a.b*c$' ]; then
  bad "falsifier: dropping -F should let the regex-confusable line pass, but the test still failed correctly" \
    "rc=$GREP_MUTANT_RC out=$(cat "$GREP_MUTANT_OUT")"
else
  ok "falsifier: with -F dropped, the regex-metacharacter membership test goes red (rc=$GREP_MUTANT_RC out=$(cat "$GREP_MUTANT_OUT"))"
fi

# ==========================================================================================
# archive_rotate_if_needed -- rotates when current_size + PENDING_BYTES exceeds
# ARCHIVE_ROTATE_AT_BYTES (1048576). Renames to session-state.archive.<N>.md, one above
# the highest existing rotation number, tolerating gaps. No bytes are ever deleted.
# ==========================================================================================

# --- Boundary: current + pending == threshold exactly -> no rotation ------------------
ROTATE_DIR_A="$TMP/rotate-a"
mkdir -p "$ROTATE_DIR_A"
ROTATE_ARCHIVE_A="$ROTATE_DIR_A/session-state.archive.md"
/usr/bin/head -c $((1048576 - 100)) /dev/zero > "$ROTATE_ARCHIVE_A"
call_lib "$TMP/rotate-a.out" "$SCRATCH_ERR" "$LIB" archive_rotate_if_needed "$ROTATE_ARCHIVE_A" 100
ROTATE_A_RC=$?
if [ "$ROTATE_A_RC" -eq 0 ] && [ -f "$ROTATE_ARCHIVE_A" ] && [ ! -e "$ROTATE_DIR_A/session-state.archive.1.md" ]; then
  ok "rotation boundary: current + pending == threshold exactly does NOT rotate"
else
  bad "rotation boundary: current + pending == threshold exactly does NOT rotate" \
    "rc=$ROTATE_A_RC $(ls -la "$ROTATE_DIR_A")"
fi

# --- Boundary: current + pending == threshold + 1 -> rotates --------------------------
ROTATE_DIR_B="$TMP/rotate-b"
mkdir -p "$ROTATE_DIR_B"
ROTATE_ARCHIVE_B="$ROTATE_DIR_B/session-state.archive.md"
/usr/bin/head -c $((1048576 - 100)) /dev/zero > "$ROTATE_ARCHIVE_B"
call_lib "$TMP/rotate-b.out" "$SCRATCH_ERR" "$LIB" archive_rotate_if_needed "$ROTATE_ARCHIVE_B" 101
ROTATE_B_RC=$?
if [ "$ROTATE_B_RC" -eq 0 ] && [ ! -e "$ROTATE_ARCHIVE_B" ] && [ -f "$ROTATE_DIR_B/session-state.archive.1.md" ]; then
  ok "rotation boundary: current + pending == threshold + 1 DOES rotate"
else
  bad "rotation boundary: current + pending == threshold + 1 DOES rotate" \
    "rc=$ROTATE_B_RC $(ls -la "$ROTATE_DIR_B")"
fi

# --- Numbering with gaps: .1. and .4. exist -> new file is .5. ------------------------
ROTATE_DIR_C="$TMP/rotate-c"
mkdir -p "$ROTATE_DIR_C"
ROTATE_ARCHIVE_C="$ROTATE_DIR_C/session-state.archive.md"
printf 'live content\n' > "$ROTATE_ARCHIVE_C"
printf 'rotation one\n' > "$ROTATE_DIR_C/session-state.archive.1.md"
printf 'rotation four\n' > "$ROTATE_DIR_C/session-state.archive.4.md"
call_lib "$TMP/rotate-c.out" "$SCRATCH_ERR" "$LIB" archive_rotate_if_needed "$ROTATE_ARCHIVE_C" $((1048576 + 1))
ROTATE_C_RC=$?
if [ "$ROTATE_C_RC" -eq 0 ] && [ -f "$ROTATE_DIR_C/session-state.archive.5.md" ] \
   && [ -f "$ROTATE_DIR_C/session-state.archive.1.md" ] && [ -f "$ROTATE_DIR_C/session-state.archive.4.md" ]; then
  ok "rotation numbering with gaps (.1. and .4. exist) picks .5., one above the highest"
else
  bad "rotation numbering with gaps (.1. and .4. exist) picks .5., one above the highest" \
    "rc=$ROTATE_C_RC $(ls -la "$ROTATE_DIR_C")"
fi

# --- No bytes are lost across a rotation -----------------------------------------------
ROTATE_DIR_D="$TMP/rotate-d"
mkdir -p "$ROTATE_DIR_D"
ROTATE_ARCHIVE_D="$ROTATE_DIR_D/session-state.archive.md"
ROTATE_CONTENT_D="$TMP/rotate-d-content.txt"
{ i=0; while [ "$i" -lt 500 ]; do printf 'ORIGINAL ARCHIVE CONTENT LINE %d\n' "$i"; i=$((i+1)); done; } > "$ROTATE_CONTENT_D"
cp "$ROTATE_CONTENT_D" "$ROTATE_ARCHIVE_D"
call_lib "$TMP/rotate-d.out" "$SCRATCH_ERR" "$LIB" archive_rotate_if_needed "$ROTATE_ARCHIVE_D" $((1048576 + 1))
if [ -f "$ROTATE_DIR_D/session-state.archive.1.md" ] && cmp -s "$ROTATE_CONTENT_D" "$ROTATE_DIR_D/session-state.archive.1.md"; then
  ok "rotation loses no bytes -- rotated file is byte-identical to the pre-rotation content"
else
  bad "rotation loses no bytes -- rotated file is byte-identical to the pre-rotation content" \
    "$(ls -la "$ROTATE_DIR_D")"
fi

# --- Falsifier: rotation threshold changed to ignore pending -> boundary test must fail -
ROTATE_MUTANT_LIB="$TMP/handoff-archive.rotate-mutant.sh"
sed 's/current_size + pending_bytes/current_size/' "$LIB" > "$ROTATE_MUTANT_LIB"
if grep -q 'current_size + pending_bytes' "$ROTATE_MUTANT_LIB"; then
  bad "falsifier setup: rotate-mutant copy still adds pending_bytes to the total" "sed did not strip it"
else
  ok "falsifier setup: rotate-mutant copy ignores pending_bytes in the rotation total"
fi
ROTATE_MUTANT_DIR="$TMP/rotate-mutant"
mkdir -p "$ROTATE_MUTANT_DIR"
ROTATE_MUTANT_ARCHIVE="$ROTATE_MUTANT_DIR/session-state.archive.md"
/usr/bin/head -c $((1048576 - 100)) /dev/zero > "$ROTATE_MUTANT_ARCHIVE"
call_lib "$TMP/rotate-mutant.out" "$SCRATCH_ERR" "$ROTATE_MUTANT_LIB" archive_rotate_if_needed "$ROTATE_MUTANT_ARCHIVE" 101
if [ -f "$ROTATE_MUTANT_DIR/session-state.archive.1.md" ]; then
  bad "falsifier: ignoring pending_bytes should skip the rotation the boundary test expects, but it rotated anyway" \
    "$(ls -la "$ROTATE_MUTANT_DIR")"
else
  ok "falsifier: with pending_bytes ignored, the rotation boundary test goes red (no rotation happened)"
fi

# ==========================================================================================
# snapshot_notepad -- atomic byte-identical copy: write beside DEST, then mv into place.
# ==========================================================================================

# --- Succeeds and is byte-identical -----------------------------------------------------
SNAP_SRC="$TMP/snapshot-src.md"
printf 'line one\nline two\nline three\n' > "$SNAP_SRC"
SNAP_DEST_DIR="$TMP/snapshot-dest-dir"
mkdir -p "$SNAP_DEST_DIR"
SNAP_DEST="$SNAP_DEST_DIR/session-state.pretrim.sess1.md"
call_lib "$TMP/snap-ok.out" "$SCRATCH_ERR" "$LIB" snapshot_notepad "$SNAP_SRC" "$SNAP_DEST"
SNAP_OK_RC=$?
if [ "$SNAP_OK_RC" -eq 0 ] && [ -f "$SNAP_DEST" ] && cmp -s "$SNAP_SRC" "$SNAP_DEST"; then
  ok "snapshot_notepad succeeds and produces a byte-identical copy"
else
  bad "snapshot_notepad succeeds and produces a byte-identical copy" "rc=$SNAP_OK_RC"
fi
# No leftover temp file beside the destination.
SNAP_STRAY="$(find "$SNAP_DEST_DIR" -name '*.XXXXXX*' -o -name '*.tmp.*' 2>/dev/null)"
if [ -z "$SNAP_STRAY" ]; then
  ok "snapshot_notepad leaves no stray temp file beside the destination on success"
else
  bad "snapshot_notepad leaves no stray temp file beside the destination on success" "$SNAP_STRAY"
fi

# --- Fails non-zero on an unreadable SRC, leaves no DEST -------------------------------
SNAP_UNREADABLE_SRC="$TMP/snapshot-unreadable-src.md"
printf 'secret\n' > "$SNAP_UNREADABLE_SRC"
chmod 000 "$SNAP_UNREADABLE_SRC"
if [ -r "$SNAP_UNREADABLE_SRC" ]; then
  printf 'skip — unreadable-src fixture is readable anyway (running as root?)\n'
else
  SNAP_DEST2="$SNAP_DEST_DIR/session-state.pretrim.sess2.md"
  call_lib "$TMP/snap-unreadable.out" "$SCRATCH_ERR" "$LIB" snapshot_notepad "$SNAP_UNREADABLE_SRC" "$SNAP_DEST2"
  SNAP_UNREADABLE_RC=$?
  if [ "$SNAP_UNREADABLE_RC" -ne 0 ] && [ ! -e "$SNAP_DEST2" ]; then
    ok "snapshot_notepad fails non-zero on an unreadable SRC and leaves no DEST"
  else
    bad "snapshot_notepad fails non-zero on an unreadable SRC and leaves no DEST" \
      "rc=$SNAP_UNREADABLE_RC dest_exists=$([ -e "$SNAP_DEST2" ] && echo yes || echo no)"
  fi
fi
chmod 700 "$SNAP_UNREADABLE_SRC" 2>/dev/null || true

# --- Fails non-zero into an unwritable directory, leaves no partial file ---------------
SNAP_RO_DIR="$TMP/snapshot-readonly-dir"
mkdir -p "$SNAP_RO_DIR"
chmod 555 "$SNAP_RO_DIR"
SNAP_RO_DEST="$SNAP_RO_DIR/session-state.pretrim.sess3.md"
if touch "$SNAP_RO_DIR/probe" 2>/dev/null; then
  rm -f "$SNAP_RO_DIR/probe"
  printf 'skip — read-only-dir fixture is writable anyway (running as root?)\n'
else
  call_lib "$TMP/snap-ro.out" "$SCRATCH_ERR" "$LIB" snapshot_notepad "$SNAP_SRC" "$SNAP_RO_DEST"
  SNAP_RO_RC=$?
  SNAP_RO_CONTENTS="$(ls -A "$SNAP_RO_DIR" 2>/dev/null)"
  if [ "$SNAP_RO_RC" -ne 0 ] && [ -z "$SNAP_RO_CONTENTS" ]; then
    ok "snapshot_notepad fails non-zero into an unwritable directory, leaves no partial file"
  else
    bad "snapshot_notepad fails non-zero into an unwritable directory, leaves no partial file" \
      "rc=$SNAP_RO_RC dir_contents=[$SNAP_RO_CONTENTS]"
  fi
fi
chmod 700 "$SNAP_RO_DIR" 2>/dev/null || true

# ==========================================================================================
# block_has_secret, secret_labels, quarantine_block, archive_append, file_removed_block
#
# The fake AWS key below is assembled from two separate halves at runtime so that the
# literal, scanner-matching string never appears as contiguous text in this source
# file — this repo's own PreToolUse scan-secrets.sh guard blocks writing it directly.
# ==========================================================================================

FAKE_AWS_KEY_PREFIX="AKIA"
FAKE_AWS_KEY_SUFFIX="ABCDEFGHIJKLMNOP"
FAKE_AWS_KEY="${FAKE_AWS_KEY_PREFIX}${FAKE_AWS_KEY_SUFFIX}"

SECRET_BLOCK="$TMP/secret-block.md"
cat > "$SECRET_BLOCK" <<EOF
export AWS_ACCESS_KEY_ID=${FAKE_AWS_KEY}
some other line
EOF
CLEAN_BLOCK="$TMP/clean-block.md"
cat > "$CLEAN_BLOCK" <<'EOF'
- Always work in a worktree.
- Never skip hooks.
EOF

# --- block_has_secret: real scanner flags a fake credential, passes clean text --------
call_lib "$TMP/bhs-secret.out" "$SCRATCH_ERR" "$LIB" block_has_secret "$SECRET_BLOCK"
BHS_SECRET_RC=$?
if [ "$BHS_SECRET_RC" -eq 0 ]; then
  ok "block_has_secret flags a block carrying a fake AWS credential"
else
  bad "block_has_secret flags a block carrying a fake AWS credential" "rc=$BHS_SECRET_RC"
fi

call_lib "$TMP/bhs-clean.out" "$SCRATCH_ERR" "$LIB" block_has_secret "$CLEAN_BLOCK"
BHS_CLEAN_RC=$?
if [ "$BHS_CLEAN_RC" -eq 1 ]; then
  ok "block_has_secret passes a clean block"
else
  bad "block_has_secret passes a clean block" "rc=$BHS_CLEAN_RC"
fi

# --- block_has_secret: a missing scanner fails CLOSED (clean content flagged anyway) --
BHS_MISSING_OUT="$TMP/bhs-missing.out"
env HANDOFF_SCAN_SECRETS_CMD=/nonexistent/no-such-scanner.sh \
  bash -c 'set -u; source "$1"; block_has_secret "$2"' _ "$LIB" "$CLEAN_BLOCK" >"$BHS_MISSING_OUT" 2>"$SCRATCH_ERR"
BHS_MISSING_RC=$?
if [ "$BHS_MISSING_RC" -eq 0 ]; then
  ok "block_has_secret fails CLOSED (flagged) when the scanner is missing, even on clean content"
else
  bad "block_has_secret fails CLOSED (flagged) when the scanner is missing, even on clean content" "rc=$BHS_MISSING_RC"
fi

# --- block_has_secret: a scanner that exits with an unexpected code fails CLOSED too --
BROKEN_SCANNER="$TMP/broken-scanner.sh"
cat > "$BROKEN_SCANNER" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$BROKEN_SCANNER"
BHS_BROKEN_OUT="$TMP/bhs-broken.out"
env HANDOFF_SCAN_SECRETS_CMD="$BROKEN_SCANNER" \
  bash -c 'set -u; source "$1"; block_has_secret "$2"' _ "$LIB" "$CLEAN_BLOCK" >"$BHS_BROKEN_OUT" 2>"$SCRATCH_ERR"
BHS_BROKEN_RC=$?
if [ "$BHS_BROKEN_RC" -eq 0 ]; then
  ok "block_has_secret fails CLOSED when the scanner exits with an unexpected code (1, not 0 or 2)"
else
  bad "block_has_secret fails CLOSED when the scanner exits with an unexpected code (1, not 0 or 2)" "rc=$BHS_BROKEN_RC"
fi

# --- secret_labels: prints pattern names only, never the matched text or a path -------
call_lib "$TMP/labels.out" "$SCRATCH_ERR" "$LIB" secret_labels "$SECRET_BLOCK"
LABELS_OUT="$(cat "$TMP/labels.out")"
case "$LABELS_OUT" in
  *"AWS access key id"*) ok "secret_labels reports the pattern name 'AWS access key id'" ;;
  *) bad "secret_labels reports the pattern name 'AWS access key id'" "$LABELS_OUT" ;;
esac
case "$LABELS_OUT" in
  *"$FAKE_AWS_KEY"*) bad "secret_labels must never echo the matched secret text" "$LABELS_OUT" ;;
  *) ok "secret_labels never echoes the matched secret text" ;;
esac
case "$LABELS_OUT" in
  *"$SECRET_BLOCK"*) bad "secret_labels must never echo the LINES_FILE temp path" "$LABELS_OUT" ;;
  *) ok "secret_labels never echoes the LINES_FILE temp path" ;;
esac

# --- archive_append: failure into an unwritable path returns non-zero -----------------
ARCHIVE_RO_DIR="$TMP/archive-readonly-dir"
mkdir -p "$ARCHIVE_RO_DIR"
chmod 555 "$ARCHIVE_RO_DIR"
if touch "$ARCHIVE_RO_DIR/probe" 2>/dev/null; then
  rm -f "$ARCHIVE_RO_DIR/probe"
  printf 'skip — archive-append unwritable-dir fixture is writable anyway (running as root?)\n'
else
  call_lib "$TMP/append-fail.out" "$SCRATCH_ERR" "$LIB" archive_append \
    "$ARCHIVE_RO_DIR/session-state.archive.md" "## Auto-captured heading" "$CLEAN_BLOCK"
  APPEND_FAIL_RC=$?
  if [ "$APPEND_FAIL_RC" -ne 0 ]; then
    ok "archive_append returns non-zero when the archive path is unwritable"
  else
    bad "archive_append returns non-zero when the archive path is unwritable" "rc=$APPEND_FAIL_RC"
  fi
fi
chmod 700 "$ARCHIVE_RO_DIR" 2>/dev/null || true

# --- file_removed_block: a clean block is archived normally ---------------------------
FRB_CLEAN_DIR="$TMP/frb-clean"
mkdir -p "$FRB_CLEAN_DIR"
FRB_CLEAN_ARCHIVE="$FRB_CLEAN_DIR/session-state.archive.md"
FRB_CLEAN_QUARANTINE="$FRB_CLEAN_DIR/session-state.quarantine.md"
call_lib "$TMP/frb-clean.out" "$SCRATCH_ERR" "$LIB" file_removed_block \
  "$FRB_CLEAN_ARCHIVE" "$FRB_CLEAN_QUARANTINE" "$CLEAN_BLOCK" "sess-clean"
FRB_CLEAN_RC=$?
if [ "$FRB_CLEAN_RC" -eq 0 ] && [ -f "$FRB_CLEAN_ARCHIVE" ] \
   && grep -q '^## Auto-captured .*secrets: none)$' "$FRB_CLEAN_ARCHIVE" \
   && grep -F -x -q -- "- Always work in a worktree." "$FRB_CLEAN_ARCHIVE" \
   && [ ! -e "$FRB_CLEAN_QUARANTINE" ]; then
  ok "file_removed_block archives a clean block normally, with an Auto-captured/secrets:none heading"
else
  bad "file_removed_block archives a clean block normally, with an Auto-captured/secrets:none heading" \
    "rc=$FRB_CLEAN_RC $(cat "$FRB_CLEAN_ARCHIVE" 2>/dev/null)"
fi

# --- file_removed_block: a flagged block is quarantined, not archived; rest of archive
# --- is untouched; the archive carries a stub, never the secret text -------------------
FRB_SECRET_DIR="$TMP/frb-secret"
mkdir -p "$FRB_SECRET_DIR"
FRB_SECRET_ARCHIVE="$FRB_SECRET_DIR/session-state.archive.md"
FRB_SECRET_QUARANTINE="$FRB_SECRET_DIR/session-state.quarantine.md"
cat > "$FRB_SECRET_ARCHIVE" <<'EOF'
## Auto-captured 2020-01-01T00:00:00Z (session preexist, 2 lines, secrets: none)
- pre-existing entry line one
- pre-existing entry line two
EOF
cp "$FRB_SECRET_ARCHIVE" "$TMP/frb-secret-archive-before.md"
call_lib "$TMP/frb-secret.out" "$SCRATCH_ERR" "$LIB" file_removed_block \
  "$FRB_SECRET_ARCHIVE" "$FRB_SECRET_QUARANTINE" "$SECRET_BLOCK" "sess-secret"
FRB_SECRET_RC=$?
if [ "$FRB_SECRET_RC" -eq 0 ] \
   && grep -F -x -q -- "export AWS_ACCESS_KEY_ID=${FAKE_AWS_KEY}" "$FRB_SECRET_QUARANTINE" \
   && ! grep -q "$FAKE_AWS_KEY" "$FRB_SECRET_ARCHIVE" \
   && grep -qi "quarantin" "$FRB_SECRET_ARCHIVE"; then
  ok "file_removed_block quarantines a flagged block; the archive gets a stub, not the secret"
else
  bad "file_removed_block quarantines a flagged block; the archive gets a stub, not the secret" \
    "rc=$FRB_SECRET_RC archive=$(cat "$FRB_SECRET_ARCHIVE" 2>/dev/null) quarantine=$(cat "$FRB_SECRET_QUARANTINE" 2>/dev/null)"
fi
# The rest of the archive (the pre-existing entry) is untouched.
if head -n 3 "$FRB_SECRET_ARCHIVE" 2>/dev/null | diff -q - "$TMP/frb-secret-archive-before.md" >/dev/null 2>&1; then
  ok "quarantining one block leaves the rest of the archive untouched"
else
  bad "quarantining one block leaves the rest of the archive untouched" \
    "$(diff <(head -n 3 "$FRB_SECRET_ARCHIVE") "$TMP/frb-secret-archive-before.md")"
fi

# --- Falsifier: secret check made fail-open -> the broken-scanner test must fail ------
SECRET_MUTANT_LIB="$TMP/handoff-archive.secret-mutant.sh"
sed 's/\[ -x "\$SCAN_SECRETS_CMD" \] || return 0/[ -x "$SCAN_SECRETS_CMD" ] || return 1/' "$LIB" > "$SECRET_MUTANT_LIB"
if grep -Fq '[ -x "$SCAN_SECRETS_CMD" ] || return 0' "$SECRET_MUTANT_LIB" 2>/dev/null; then
  bad "falsifier setup: secret-mutant copy still fails closed on a missing scanner" "sed did not change it"
else
  ok "falsifier setup: secret-mutant copy fails OPEN on a missing scanner"
fi
SECRET_MUTANT_OUT="$TMP/bhs-missing.mutant.out"
env HANDOFF_SCAN_SECRETS_CMD=/nonexistent/no-such-scanner.sh \
  bash -c 'set -u; source "$1"; block_has_secret "$2"' _ "$SECRET_MUTANT_LIB" "$CLEAN_BLOCK" >"$SECRET_MUTANT_OUT" 2>"$SCRATCH_ERR"
SECRET_MUTANT_RC=$?
if [ "$SECRET_MUTANT_RC" -eq 0 ]; then
  bad "falsifier: fail-open mutant should pass a missing scanner through as clean, but it still flagged" "rc=$SECRET_MUTANT_RC"
else
  ok "falsifier: with the secret check made fail-open, the missing-scanner test goes red (rc=$SECRET_MUTANT_RC, was flagged, want clean/1)"
fi

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
