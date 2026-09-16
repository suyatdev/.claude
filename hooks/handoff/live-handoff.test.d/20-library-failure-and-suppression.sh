# shellcheck shell=bash
# 20-library-failure-and-suppression.sh — sourced by ../live-handoff.test.sh — not runnable on its own.
# Covers fail-closed reinject/archive library failures (missing function, corrupt parse), the snapshot-cannot-be-written suppression scenario and its falsifier, and a missing snapshot library.

# ============================================================================
# Task 8, fail-closed: the reinject library is present but does not define
# keep_trim_directive (a valid-but-empty file — sourcing it returns 0, so this is the
# case that a bare "did `.` succeed?" check would miss; only declare -f catches it).
# No trim directive may be emitted, whatever the line count, and the append-mode warning
# must name THIS failure, distinctly from the pre-trim-snapshot warning above.
# ============================================================================
NOREINJECT_DIR="$TMP/no-reinject"
mkdir -p "$NOREINJECT_DIR/lib"
cp "$HOOK" "$NOREINJECT_DIR/live-handoff.sh"
cp "$LIB" "$NOREINJECT_DIR/lib/handoff-archive.sh"
: > "$NOREINJECT_DIR/lib/handoff-keep-reinject.sh"
chmod +x "$NOREINJECT_DIR/live-handoff.sh"
REPO_R="$(mkrepo repo-noreinject 160)"
run_hook "$REPO_R" "$NOREINJECT_DIR/live-handoff.sh" "sess-rrr"
if [ "$RC" -eq 0 ]; then
  ok "unloadable reinject library: the hook still exits 0"
else
  bad "unloadable reinject library: the hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" "It has grown too large"; then
  bad "unloadable reinject library suppresses the trim directive, whatever the line count" \
    "the trim directive was emitted with 160 lines and no reinject library"
else
  ok "unloadable reinject library suppresses the trim directive, whatever the line count"
fi
if has "$OUT" "Do NOT rewrite the whole file"; then
  ok "unloadable reinject library still emits the append-mode directive"
else
  bad "unloadable reinject library still emits the append-mode directive" "$(cat "$OUT")"
fi
if has "$OUT" "TRIM SUPPRESSED" && has "$OUT" "keep-reinject.sh"; then
  ok "unloadable reinject library names ITS OWN failure in the warning"
else
  bad "unloadable reinject library names ITS OWN failure in the warning" "$(cat "$OUT")"
fi
if has "$OUT" "no pre-trim snapshot was taken"; then
  bad "the reinject-failure warning is distinct from the snapshot-failure warning" \
    "the snapshot wording leaked into a reinject-only failure: $(cat "$OUT")"
else
  ok "the reinject-failure warning is distinct from the snapshot-failure warning"
fi

# ============================================================================
# A CORRUPT (parse-error) reinject library, distinct from NOREINJECT_DIR above: that
# scenario is an EMPTY file, which sources cleanly (rc 0) and is only caught by the
# `declare -f` check. A file that fails to parse is a different failure — measured (see
# pre-compact-handoff.sh's comment) to kill the whole non-interactive shell with rc=2 when
# sourced under `set -euo pipefail` inside a bare `if`/`&&` guard, before that guard's body
# ever runs. This must still land as "reinject library unloadable, trim suppressed",
# never as a dead hook emitting nothing.
# ============================================================================
CORRUPTREINJECT_DIR="$TMP/corruptreinject"
mkdir -p "$CORRUPTREINJECT_DIR/lib"
cp "$HOOK" "$CORRUPTREINJECT_DIR/live-handoff.sh"
cp "$LIB" "$CORRUPTREINJECT_DIR/lib/handoff-archive.sh"
printf 'this is not valid bash ((((\n' > "$CORRUPTREINJECT_DIR/lib/handoff-keep-reinject.sh"
chmod +x "$CORRUPTREINJECT_DIR/live-handoff.sh"
REPO_T="$(mkrepo repo-corruptreinject 160)"
run_hook "$REPO_T" "$CORRUPTREINJECT_DIR/live-handoff.sh" "sess-ttt"
if [ "$RC" -eq 0 ]; then
  ok "corrupt (parse-error) reinject library: the hook still exits 0"
else
  bad "corrupt (parse-error) reinject library: the hook still exits 0" \
    "rc=$RC out=$(cat "$OUT") err=$(cat "$ERR")"
fi
if [ -s "$OUT" ]; then
  ok "corrupt reinject library: a directive is still emitted"
else
  bad "corrupt reinject library: a directive is still emitted" "empty output"
fi
# Presence is required before the comparison: an empty $OUT would satisfy "no trim text"
# vacuously, so this checks append-mode is ACTUALLY there, not merely that trim is absent.
if [ -s "$OUT" ] && has "$OUT" "Do NOT rewrite the whole file" \
   && ! has "$OUT" "It has grown too large"; then
  ok "corrupt reinject library: append-mode directive wins over trim, whatever the line count"
else
  bad "corrupt reinject library: append-mode directive wins over trim, whatever the line count" \
    "rc=$RC out=$(cat "$OUT")"
fi
if [ -s "$OUT" ] && has "$OUT" "TRIM SUPPRESSED" && has "$OUT" "keep-reinject.sh"; then
  ok "corrupt reinject library names ITS OWN failure in the warning"
else
  bad "corrupt reinject library names ITS OWN failure in the warning" "$(cat "$OUT")"
fi
if [ -s "$OUT" ] && ! has "$OUT" "no pre-trim snapshot was taken"; then
  ok "corrupt reinject library warning is distinct from the snapshot-failure warning"
else
  bad "corrupt reinject library warning is distinct from the snapshot-failure warning" \
    "$(cat "$OUT")"
fi

# ============================================================================
# Scenario: The snapshot cannot be written
#   Then no trim directive is emitted, whatever the line count
#   And the append-mode directive is emitted with a warning naming the failure
# ============================================================================
REPO_C="$(mkrepo repo-readonly 160)"
chmod 500 "$REPO_C/.claude"
run_hook "$REPO_C" "$HOOK" "sess-ccc"
chmod 700 "$REPO_C/.claude"
if [ "$RC" -eq 0 ]; then
  ok "read-only .claude: the hook still exits 0"
else
  bad "read-only .claude: the hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" "It has grown too large"; then
  bad "snapshot failure suppresses the trim directive, whatever the line count" \
    "the trim directive was emitted with 140 lines and no snapshot"
else
  ok "snapshot failure suppresses the trim directive, whatever the line count"
fi
if has "$OUT" "Do NOT rewrite the whole file"; then
  ok "snapshot failure still emits the append-mode directive"
else
  bad "snapshot failure still emits the append-mode directive" "$(cat "$OUT")"
fi
if has "$OUT" "TRIM SUPPRESSED" && has "$OUT" "could not be written"; then
  ok "snapshot failure emits a warning naming the failure"
else
  bad "snapshot failure emits a warning naming the failure" "$(cat "$OUT")"
fi
if [ ! -f "$REPO_C/.claude/session-state.pretrim.sess-ccc.md" ]; then
  ok "snapshot failure leaves no partial snapshot behind"
else
  bad "snapshot failure leaves no partial snapshot behind" "a file was left at the PT path"
fi

# ============================================================================
# Falsifier for the suppression assertion above: delete the SNAPSHOT_OK guard from a
# COPY of the hook and confirm the trim directive reappears in the same read-only repo.
# Without this, "no trim directive" could be passing because the hook never trims at all.
# ============================================================================
MUT_DIR="$TMP/mutant"
mkdir -p "$MUT_DIR/lib"
cp "$LIB" "$MUT_DIR/lib/handoff-archive.sh"
# The reinject library must be present and intact too (task 8 added a second, independent
# gate, REINJECT_LIB_OK) — otherwise this falsifier would prove nothing about SNAPSHOT_OK
# specifically: the trim would stay suppressed by the OTHER gate and look like a pass.
cp "$HOOK_DIR/lib/handoff-keep-reinject.sh" "$MUT_DIR/lib/handoff-keep-reinject.sh"
sed 's/\[ "\$SNAPSHOT_OK" = true \] \&\& //' "$HOOK" > "$MUT_DIR/live-handoff.sh"
chmod +x "$MUT_DIR/live-handoff.sh"
if cmp -s "$MUT_DIR/live-handoff.sh" "$HOOK"; then
  bad "falsifier: the SNAPSHOT_OK guard was found and removed" \
    "sed changed nothing — the guard text moved, so the falsifier below proves nothing"
else
  ok "falsifier: the SNAPSHOT_OK guard was found and removed"
fi
REPO_F="$(mkrepo repo-falsify 160)"
chmod 500 "$REPO_F/.claude"
run_hook "$REPO_F" "$MUT_DIR/live-handoff.sh" "sess-fff"
chmod 700 "$REPO_F/.claude"
if has "$OUT" "It has grown too large"; then
  ok "falsifier: without the guard the trim directive DOES fire with no snapshot"
else
  bad "falsifier: without the guard the trim directive DOES fire with no snapshot" \
    "the mutant stayed silent, so the suppression test above discriminates nothing"
fi

# ============================================================================
# A missing library is a snapshot failure too — it is the same "cannot back this up"
# state, and must not silently fall through to a trim.
# ============================================================================
NOLIB_DIR="$TMP/nolib"
mkdir -p "$NOLIB_DIR"
cp "$HOOK" "$NOLIB_DIR/live-handoff.sh"
chmod +x "$NOLIB_DIR/live-handoff.sh"
REPO_D="$(mkrepo repo-nolib 160)"
run_hook "$REPO_D" "$NOLIB_DIR/live-handoff.sh" "sess-ddd"
if [ "$RC" -eq 0 ]; then
  ok "missing library: the hook still exits 0"
else
  bad "missing library: the hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" "It has grown too large"; then
  bad "missing library suppresses the trim directive" "the trim directive was emitted"
else
  ok "missing library suppresses the trim directive"
fi
if has "$OUT" "TRIM SUPPRESSED" && has "$OUT" "could not be loaded"; then
  ok "missing library emits a warning naming the library, not a generic failure"
else
  bad "missing library emits a warning naming the library, not a generic failure" "$(cat "$OUT")"
fi

# ============================================================================
# A CORRUPT (parse-error) archive library, distinct from NOLIB_DIR above: that scenario is
# a MISSING file, caught by the `[ -r "$LIB" ]` half of the guard before `.` ever runs. A
# file that fails to parse is a different failure — measured (see pre-compact-handoff.sh's
# comment) to kill the whole non-interactive shell with rc=2 when sourced under
# `set -euo pipefail` inside a bare `if`/`&&` guard. This is the snapshot library, so the
# expected outcome is the SAME as any other unloadable-snapshot-library case: append-mode
# directive, trim suppressed whatever the line count, warning names the archive library.
# ============================================================================
CORRUPTLIB_DIR="$TMP/corruptlib"
mkdir -p "$CORRUPTLIB_DIR/lib"
cp "$HOOK" "$CORRUPTLIB_DIR/live-handoff.sh"
cp "$HOOK_DIR/lib/handoff-keep-reinject.sh" "$CORRUPTLIB_DIR/lib/handoff-keep-reinject.sh"
printf 'foo() {\n' > "$CORRUPTLIB_DIR/lib/handoff-archive.sh"
chmod +x "$CORRUPTLIB_DIR/live-handoff.sh"
REPO_S="$(mkrepo repo-corruptlib 160)"
run_hook "$REPO_S" "$CORRUPTLIB_DIR/live-handoff.sh" "sess-sss"
if [ "$RC" -eq 0 ]; then
  ok "corrupt (parse-error) archive library: the hook still exits 0"
else
  bad "corrupt (parse-error) archive library: the hook still exits 0" \
    "rc=$RC out=$(cat "$OUT") err=$(cat "$ERR")"
fi
if [ -s "$OUT" ]; then
  ok "corrupt archive library: a directive is still emitted"
else
  bad "corrupt archive library: a directive is still emitted" "empty output"
fi
# Presence is required before the comparison — see the matching comment in the
# corrupt-reinject-library block above for why a bare "no trim text" check is not enough.
if [ -s "$OUT" ] && has "$OUT" "Do NOT rewrite the whole file" \
   && ! has "$OUT" "It has grown too large"; then
  ok "corrupt archive library: append-mode directive wins over trim, whatever the line count"
else
  bad "corrupt archive library: append-mode directive wins over trim, whatever the line count" \
    "rc=$RC out=$(cat "$OUT")"
fi
if [ -s "$OUT" ] && has "$OUT" "TRIM SUPPRESSED" \
   && has "$OUT" "$CORRUPTLIB_DIR/lib/handoff-archive.sh"; then
  ok "corrupt archive library names the snapshot/archive-library failure in the warning"
else
  bad "corrupt archive library names the snapshot/archive-library failure in the warning" \
    "$(cat "$OUT")"
fi

