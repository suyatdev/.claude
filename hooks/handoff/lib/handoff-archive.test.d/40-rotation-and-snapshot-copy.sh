# shellcheck shell=bash
# 40-rotation-and-snapshot-copy.sh — sourced by ../handoff-archive.test.sh — not runnable on its own.
# Covers archive_rotate_if_needed() boundary/gap-numbering/no-bytes-lost tests and the atomic snapshot_notepad copy contract.

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

