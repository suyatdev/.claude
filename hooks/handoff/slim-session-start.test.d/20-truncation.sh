# shellcheck shell=bash
# shellcheck disable=SC2154  # got/out/err are assigned by the entry file's run helper (slim-session-start.test.sh) before this part is sourced
# 20-truncation.sh — sourced by ../slim-session-start.test.sh — not runnable on its own.
# Covers the reader-truncation scenarios, KEEP-marker disclosure, and the byte-based budget.

# --- Scenario: The reader truncates instead of blanking — edge ------------------------
# docs/features/handoff-trim-safety.spec.md: an oversized handoff is no longer dropped
# wholesale -- whole lines are printed in order until the byte budget is spent, then a
# line names how many lines/bytes were withheld and the path to read, and no partial
# line is ever printed. Fixture: 500 fixed-width lines ("line 00001".."line 00500", 11
# bytes each including the newline) so truncation is measurable line-by-line -- a whole
# fixture line either survives intact or is withheld, there is no partial-match case --
# and the withheld counts can be checked arithmetically against the fixture rather than
# pinned to a magic number.
new_repo
FIX_LINES=500
: > "$REPO/.claude/session-state.md"
write_fixed_lines "$REPO/.claude/session-state.md" 1 "$FIX_LINES"
FIX_BYTES=$(wc -c < "$REPO/.claude/session-state.md" | tr -d ' ')
CAP=2000
run "$REPO" SLIM_HANDOFF_MAX_BYTES=$CAP
OUT="$(cat "$out")"
if [ "$got" -ne 0 ]; then
  bad "oversized handoff -> exit 0" "got $got"
else
  ok "oversized handoff -> exit 0"
fi
case "$OUT" in
  *"written:"*) ok "oversized handoff still carries the written: header" ;;
  *) bad "oversized handoff still carries the written: header" "$OUT" ;;
esac
case "$OUT" in
  *$'\n''line 00001'$'\n'*) ok "oversized handoff emits the first body line (truncate, not blank)" ;;
  *) bad "oversized handoff emits the first body line (truncate, not blank)" "$OUT" ;;
esac
LAST_FIX_LINE="line $(printf '%05d' "$FIX_LINES")"
case "$OUT" in
  *"$LAST_FIX_LINE"*) bad "oversized handoff withholds the last body line (truncation happened)" "$OUT" ;;
  *) ok "oversized handoff withholds the last body line (truncation happened)" ;;
esac

# No partial line: every output line shaped like a fixture line ("line NNNNN") must
# appear verbatim as a whole line somewhere in the fixture -- a partial line (cut mid
# number, or missing the trailing digits) would not.
PARTIAL_FOUND=""
EMITTED_BODY_COUNT=0
while IFS= read -r ln; do
  case "$ln" in
    line\ *)
      if grep -F -x -q -- "$ln" "$REPO/.claude/session-state.md"; then
        EMITTED_BODY_COUNT=$((EMITTED_BODY_COUNT + 1))
      else
        PARTIAL_FOUND="$ln"
      fi
      ;;
  esac
done < "$out"
if [ -z "$PARTIAL_FOUND" ]; then
  ok "no emitted body line is a partial fixture line"
else
  bad "no emitted body line is a partial fixture line" "found: '$PARTIAL_FOUND'"
fi

# The withheld-count line: names a line count, a byte count, and the read path.
WITHHELD_TEXT="$(grep -i 'withheld' "$out")"
case "$WITHHELD_TEXT" in
  *".claude/session-state.md"*) ok "withheld line names the .claude/session-state.md path" ;;
  *) bad "withheld line names the .claude/session-state.md path" "$OUT" ;;
esac
WITHHELD_LINES_N="$(printf '%s\n' "$WITHHELD_TEXT" | sed -nE 's/.*[^0-9]([0-9]+)[[:space:]]*lines?.*/\1/p' | head -1)"
WITHHELD_BYTES_N="$(printf '%s\n' "$WITHHELD_TEXT" | sed -nE 's/.*[^0-9]([0-9]+)[[:space:]]*bytes?.*/\1/p' | head -1)"
if [ -n "$WITHHELD_LINES_N" ] && [ -n "$WITHHELD_BYTES_N" ]; then
  ok "withheld line names both a line count and a byte count"
else
  bad "withheld line names both a line count and a byte count" "$OUT"
fi

# Arithmetic check against the fixture, not a hardcoded number: emitted + withheld ==
# total lines, exactly. Bytes: the implementation's exact accounting (e.g. whether the
# envelope header counts toward the budget) isn't pinned by the spec, so bytes are
# checked loosely -- non-zero and less than the fixture total -- per the task's own
# fallback instruction.
WITHHELD_LINES_WANT=$((FIX_LINES - EMITTED_BODY_COUNT))
if [ "$WITHHELD_LINES_N" = "$WITHHELD_LINES_WANT" ]; then
  ok "withheld line count is arithmetically correct ($EMITTED_BODY_COUNT emitted + $WITHHELD_LINES_WANT withheld = $FIX_LINES total)"
else
  bad "withheld line count is arithmetically correct against the fixture" \
    "emitted=$EMITTED_BODY_COUNT want withheld=$WITHHELD_LINES_WANT got withheld='$WITHHELD_LINES_N'"
fi
case "$WITHHELD_BYTES_N" in
  ''|*[!0-9]*) BYTES_N_NUMERIC=0 ;;
  *) BYTES_N_NUMERIC=1 ;;
esac
if [ "$BYTES_N_NUMERIC" -eq 1 ] && [ "$WITHHELD_BYTES_N" -gt 0 ] && [ "$WITHHELD_BYTES_N" -lt "$FIX_BYTES" ]; then
  ok "withheld byte count is non-zero and less than the total fixture bytes ($FIX_BYTES)"
else
  bad "withheld byte count is non-zero and less than the total fixture bytes ($FIX_BYTES)" "got '$WITHHELD_BYTES_N'"
fi

EMITTED_BODY_BYTES=$((EMITTED_BODY_COUNT * 11))
if [ "$EMITTED_BODY_BYTES" -le "$CAP" ]; then
  ok "total emitted body bytes ($EMITTED_BODY_BYTES) do not exceed the cap passed in ($CAP)"
else
  bad "total emitted body bytes do not exceed the cap passed in" "emitted=$EMITTED_BODY_BYTES cap=$CAP"
fi

# --- Scenario: The reader truncates instead of blanking — [KEEP] disclosure -----------
# extract_keep_lines() (lib/handoff-archive.sh) is measured (2026-09-11, all 24 cut
# points of a fence-and-two-region fixture) to be positional: the KEEP lines of a
# K-line prefix equal the first portion of the KEEP lines of the whole file. So an
# implementation is expected to compare "KEEP lines in the emitted prefix" against
# "KEEP lines in the whole file" to decide whether to disclose a loss -- this tests that
# observable behavior, not the mechanism. B1 and B2 differ ONLY in where the [KEEP]
# region sits, so together they discriminate a real positional check from one that
# always (or never) claims a loss.

# make_keep_fixture FILE POSITION(top|bottom) FILLER_LINES
make_keep_fixture() {
  local file="$1" position="$2" filler="$3" i
  : > "$file"
  if [ "$position" = "top" ]; then
    printf '## Notes [KEEP]\nkeep line one\nkeep line two\n## End Notes\n' >> "$file"
  fi
  i=1
  while [ "$i" -le "$filler" ]; do
    printf 'filler %05d\n' "$i" >> "$file"
    i=$((i+1))
  done
  if [ "$position" = "bottom" ]; then
    printf '## Notes [KEEP]\nkeep line one\nkeep line two\n## End Notes\n' >> "$file"
  fi
}

KEEP_FILLER=500
KEEP_CAP=2000

# B1 — the [KEEP] region sits at the END: truncation cuts into it, so it must be
# disclosed by name.
new_repo
make_keep_fixture "$REPO/.claude/session-state.md" bottom "$KEEP_FILLER"
run "$REPO" SLIM_HANDOFF_MAX_BYTES=$KEEP_CAP
if grep -iE 'withheld|omitted' "$out" | grep -qi 'keep'; then
  ok "B1: a [KEEP] region cut off by truncation is disclosed by name"
else
  bad "B1: a [KEEP] region cut off by truncation is disclosed by name" "$(cat "$out")"
fi

# B2 — same oversize length, but the [KEEP] region sits at the very TOP, entirely
# inside the surviving prefix: nothing KEEP-tagged is withheld, so no KEEP claim
# should appear. This is the discriminating control: without it, an implementation
# that unconditionally prints "KEEP lines were withheld" would pass B1 too.
new_repo
make_keep_fixture "$REPO/.claude/session-state.md" top "$KEEP_FILLER"
run "$REPO" SLIM_HANDOFF_MAX_BYTES=$KEEP_CAP
if grep -iE 'withheld|omitted' "$out" | grep -qi 'keep'; then
  bad "B2: a [KEEP] region fully inside the surviving prefix is NOT claimed withheld" "$(cat "$out")"
else
  ok "B2: a [KEEP] region fully inside the surviving prefix is NOT claimed withheld"
fi

# B3 — below the cap: unchanged, whole body emitted, no withheld/truncation line. Cap is
# passed explicitly as the new default (24576) so this exercises the truncate-vs-full-
# emit boundary itself, independent of whatever the hook's compiled-in default is right
# now (that is Task C's job, immediately below).
new_repo
FIX_LINES_B3=818   # 818 * 11 = 8,998 bytes -- "SS is 9,000 bytes" from the spec scenario
: > "$REPO/.claude/session-state.md"
write_fixed_lines "$REPO/.claude/session-state.md" 1 "$FIX_LINES_B3"
run "$REPO" SLIM_HANDOFF_MAX_BYTES=24576
OUT="$(cat "$out")"
case "$OUT" in
  *$'\n''line 00001'$'\n'*) ok "B3: under the cap, the first body line is emitted" ;;
  *) bad "B3: under the cap, the first body line is emitted" "$OUT" ;;
esac
LAST_B3_LINE="line $(printf '%05d' "$FIX_LINES_B3")"
case "$OUT" in
  *"$LAST_B3_LINE"*) ok "B3: under the cap, the whole body is emitted (last line present)" ;;
  *) bad "B3: under the cap, the whole body is emitted (last line present)" "$OUT" ;;
esac
if grep -iE 'withheld|omitted' "$out" >/dev/null 2>&1; then
  bad "B3: under the cap, no withheld/truncation line appears" "$OUT"
else
  ok "B3: under the cap, no withheld/truncation line appears"
fi

# --- Scenario: the default MAX_BYTES is 24576 (raised from 8192) ----------------------
# ~12,000 bytes: over the OLD default (8192) but under the NEW default (24576). No
# SLIM_HANDOFF_MAX_BYTES is passed at all, so this pins the hook's own default rather
# than an override -- `run "$REPO" -u SLIM_HANDOFF_MAX_BYTES` builds `env -u
# SLIM_HANDOFF_MAX_BYTES bash "$HOOK"`, which really leaves the variable unset rather
# than silently inheriting whatever this test shell happens to have (this suite itself
# never exports it, but the caller might).
new_repo
FIX_LINES_C=1100   # 1100 * 11 = 12,100 bytes
: > "$REPO/.claude/session-state.md"
write_fixed_lines "$REPO/.claude/session-state.md" 1 "$FIX_LINES_C"
run "$REPO" -u SLIM_HANDOFF_MAX_BYTES
OUT="$(cat "$out")"
if [ "$got" -eq 0 ]; then
  ok "default cap: hook exits 0"
else
  bad "default cap: hook exits 0" "got $got"
fi
case "$OUT" in
  *$'\n''line 00001'$'\n'*) ok "default cap (24576): a 12,100-byte handoff emits its first body line" ;;
  *) bad "default cap (24576): a 12,100-byte handoff emits its first body line" "$OUT" ;;
esac
LAST_C_LINE="line $(printf '%05d' "$FIX_LINES_C")"
case "$OUT" in
  *"$LAST_C_LINE"*) ok "default cap (24576): the whole body is emitted, last line present too" ;;
  *) bad "default cap (24576): the whole body is emitted, last line present too" "$OUT" ;;
esac
if grep -iE 'withheld|omitted' "$out" >/dev/null 2>&1; then
  bad "default cap (24576): no withheld/omitted line for a file under the new default" "$OUT"
else
  ok "default cap (24576): no withheld/omitted line for a file under the new default"
fi

# --- Scenario: The truncation budget counts BYTES, not characters — edge ---------------
# Every other fixture in this suite is pure ASCII, where byte length and character length
# are identical, so none of them can tell the two apart. A real notepad is not ASCII: it
# routinely carries em dashes and ⚠️. Measured 2026-09-11 — deleting the `local LC_ALL=C`
# statement from slim-session-start.sh (so ${#line} counts characters) left this suite at
# 63/63, i.e. byte accounting was correct but entirely unpinned. This scenario is that
# missing control.
#
# Fixture: one 11-byte ASCII line, then 8 em dashes (U+2014, 3 bytes each) = 24 bytes + a
# newline = 25 bytes but only 9 characters. Total 36 bytes, cap 20:
#   byte accounting:      11 + 25 = 36 > 20  -> line 2 withheld   (correct)
#   character accounting: 11 +  9 = 20 <= 20 -> line 2 emitted    (the bug)
# So the em-dash line's absence from the output is what discriminates, and the cap is
# deliberately the exact value at which character accounting just barely admits it.
new_repo
MB_FILE="$REPO/.claude/session-state.md"
printf 'aaaaaaaaaa\n' > "$MB_FILE"
printf '————————\n' >> "$MB_FILE"
MB_BYTES=$(wc -c < "$MB_FILE" | tr -d ' ')
if [ "$MB_BYTES" -eq 36 ]; then
  ok "multi-byte fixture is 36 bytes as the arithmetic above assumes"
else
  bad "multi-byte fixture is 36 bytes as the arithmetic above assumes" "got $MB_BYTES"
fi
run "$REPO" SLIM_HANDOFF_MAX_BYTES=20
OUT="$(cat "$out")"
case "$OUT" in
  *aaaaaaaaaa*) ok "byte budget: the 11-byte ASCII line fits and is emitted" ;;
  *) bad "byte budget: the 11-byte ASCII line fits and is emitted" "$OUT" ;;
esac
case "$OUT" in
  *$'———'*)
    bad "byte budget counts bytes not characters: the 25-byte em-dash line is withheld" \
      "emitted under a 20-byte cap, so \${#line} is counting characters" ;;
  *) ok "byte budget counts bytes not characters: the 25-byte em-dash line is withheld" ;;
esac
case "$OUT" in
  *"1 lines (25 bytes) withheld"*) ok "byte budget: withheld counts are 1 line / 25 bytes" ;;
  *) bad "byte budget: withheld counts are 1 line / 25 bytes" "$OUT" ;;
esac

