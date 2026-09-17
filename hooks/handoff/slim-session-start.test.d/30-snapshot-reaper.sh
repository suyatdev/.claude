# shellcheck shell=bash
# shellcheck disable=SC2154  # got/out/err are assigned by the entry file's run helper (slim-session-start.test.sh) before this part is sourced
# 30-snapshot-reaper.sh — sourced by ../slim-session-start.test.sh — not runnable on its own.
# Covers pane-agent handling and the stale/fresh/orphaned snapshot reaper falsifiers.

# --- Scenario: Pane agent — edge -------------------------------------------------------
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
run "$REPO" CLAUDE_PANE_AGENT=1
assert_exit0_empty "CLAUDE_PANE_AGENT set -> silent, exit 0"

# --- Scenario: A stale snapshot is reaped -----------------------------------------------
# docs/features/handoff-trim-safety.spec.md, reap_after_hours: 24.
new_repo
printf '# Session State\n\ncurrent notes\n' > "$REPO/.claude/session-state.md"
STALE_SNAP="$REPO/.claude/session-state.pretrim.reap-abc123.md"
printf 'UNIQUE_REAP_TOKEN_7f3a\nold line two\n' > "$STALE_SNAP"
backdate "$STALE_SNAP" 30
run "$REPO"
if [ "$got" -ne 0 ]; then
  bad "stale snapshot present -> hook still exits 0" "got $got"
else
  ok "stale snapshot present -> hook still exits 0"
fi
if [ -f "$STALE_SNAP" ]; then
  bad "stale snapshot is deleted after archiving" "snapshot still present at $STALE_SNAP"
else
  ok "stale snapshot is deleted after archiving"
fi
STALE_ARCHIVE="$REPO/.claude/session-state.archive.md"
if [ -f "$STALE_ARCHIVE" ] && grep -F -q 'UNIQUE_REAP_TOKEN_7f3a' "$STALE_ARCHIVE"; then
  ok "the reaper appends the stale snapshot to AR before deletion, never discarded"
else
  bad "the reaper appends the stale snapshot to AR before deletion, never discarded" \
    "archive missing token: $(cat "$STALE_ARCHIVE" 2>/dev/null)"
fi
case "$(cat "$STALE_ARCHIVE" 2>/dev/null)" in
  *"## Auto-captured"*) ok "reaped block reuses the Auto-captured heading, same as a normal trim" ;;
  *) bad "reaped block reuses the Auto-captured heading, same as a normal trim" "$(cat "$STALE_ARCHIVE" 2>/dev/null)" ;;
esac

# --- Scenario: A fresh (non-stale) snapshot is left alone -- edge, not a named scenario -
# Guards the reap_after_hours gate itself: nothing here should touch an in-flight snapshot.
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
FRESH_SNAP="$REPO/.claude/session-state.pretrim.fresh999.md"
printf 'FRESH_TOKEN_should_not_be_reaped\n' > "$FRESH_SNAP"
run "$REPO"
if [ -f "$FRESH_SNAP" ]; then
  ok "a fresh (under 24h) snapshot is not reaped"
else
  bad "a fresh (under 24h) snapshot is not reaped" "snapshot was deleted"
fi
FRESH_ARCHIVE="$REPO/.claude/session-state.archive.md"
if [ -f "$FRESH_ARCHIVE" ] && grep -F -q 'FRESH_TOKEN_should_not_be_reaped' "$FRESH_ARCHIVE" 2>/dev/null; then
  bad "a fresh (under 24h) snapshot is not archived" "token found in archive"
else
  ok "a fresh (under 24h) snapshot is not archived"
fi

# --- Scenario: An orphaned snapshot is reaped even when the notepad is gone -------------
new_repo
ORPHAN_SNAP="$REPO/.claude/session-state.pretrim.orphan-xyz.md"
printf 'UNIQUE_ORPHAN_TOKEN_9d21\n' > "$ORPHAN_SNAP"
backdate "$ORPHAN_SNAP" 30
run "$REPO"
assert_exit0_empty "orphaned stale snapshot, no session-state.md at all -> still silent, exit 0"
ORPHAN_ARCHIVE="$REPO/.claude/session-state.archive.md"
if [ -f "$ORPHAN_ARCHIVE" ] && grep -F -q 'UNIQUE_ORPHAN_TOKEN_9d21' "$ORPHAN_ARCHIVE"; then
  ok "the reaper runs before any early exit, so the orphaned snapshot is archived"
else
  bad "the reaper runs before any early exit, so the orphaned snapshot is archived" \
    "archive missing token (no early exit should have reached first): $(cat "$ORPHAN_ARCHIVE" 2>/dev/null)"
fi
if [ -f "$ORPHAN_SNAP" ]; then
  bad "orphaned snapshot is deleted only after it is archived" "snapshot still present"
else
  ok "orphaned snapshot is deleted only after it is archived"
fi

# --- Scenario: A pane agent must not touch handoff state (reaper included) --------------
# Per the spec's own scenario, CLAUDE_PANE_AGENT makes every one of these four hooks exit 0
# immediately -- the reaper does not get a carve-out.
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
PANE_SNAP="$REPO/.claude/session-state.pretrim.paneagent.md"
printf 'UNIQUE_PANE_TOKEN_11bb\n' > "$PANE_SNAP"
backdate "$PANE_SNAP" 30
run "$REPO" CLAUDE_PANE_AGENT=1
assert_exit0_empty "CLAUDE_PANE_AGENT set -> silent, exit 0, even with a stale snapshot present"
if [ -f "$PANE_SNAP" ]; then
  ok "CLAUDE_PANE_AGENT set -> the reaper does not touch the snapshot"
else
  bad "CLAUDE_PANE_AGENT set -> the reaper does not touch the snapshot" \
    "snapshot was reaped despite CLAUDE_PANE_AGENT"
fi

# --- Scenario: The reaper cannot append --------------------------------------------------
new_repo
printf '# Session State\n\nnotes\n' > "$REPO/.claude/session-state.md"
FAIL_SNAP="$REPO/.claude/session-state.pretrim.failtest.md"
printf 'UNIQUE_FAIL_TOKEN_44aa\n' > "$FAIL_SNAP"
backdate "$FAIL_SNAP" 30
chmod 555 "$REPO/.claude"
if [ -w "$REPO/.claude" ]; then
  printf 'skip — read-only-dir fixture is writable anyway (running as root?)\n'
else
  run "$REPO"
  FAIL_OUT="$(cat "$out")"
  if [ -f "$FAIL_SNAP" ]; then
    ok "the reaper cannot append -> the snapshot is left in place, not deleted"
  else
    bad "the reaper cannot append -> the snapshot is left in place, not deleted" "snapshot was deleted"
  fi
  case "$FAIL_OUT" in
    *"failtest"*) ok "the reaper's append failure is reported, not silenced" ;;
    *) bad "the reaper's append failure is reported, not silenced" "$FAIL_OUT" ;;
  esac
  if [ "$got" -ne 0 ]; then
    bad "a reap failure still never breaks session start (exit 0)" "got $got"
  else
    ok "a reap failure still never breaks session start (exit 0)"
  fi
fi
chmod 700 "$REPO/.claude" 2>/dev/null || true

# --- Falsifiers for the two reaper properties -------------------------------------------
# Both reaper properties above could pass for the wrong reason, so each is paired with a
# mutant built from a COPY of the real hook (the live-handoff.test.sh idiom). Each mutation
# asserts it changed something first: an edit that matched nothing proves nothing.
MUT_LIB_SRC="$(cd "$(dirname "$0")" && pwd)/lib/handoff-archive.sh"

# Falsifier A -- ordering (finding C6). Move the reaper call BELOW the session-state.md
# early exit and confirm the orphan scenario then loses the snapshot text entirely.
MUT_A="$TMP/mutant-order"
mkdir -p "$MUT_A/lib"
cp "$MUT_LIB_SRC" "$MUT_A/lib/handoff-archive.sh"
awk '
  /^  reap_stale_snapshots "\$repo_root"$/ { next }
  { print }
  /^  \[ -f "\$state_file" \] && \[ -r "\$state_file" \] \|\| exit 0$/ {
    print "  reap_stale_snapshots \"$repo_root\""
  }
' "$HOOK" > "$MUT_A/slim-session-start.sh"
chmod +x "$MUT_A/slim-session-start.sh"
if cmp -s "$MUT_A/slim-session-start.sh" "$HOOK"; then
  bad "falsifier A: the reaper call was found and moved below the early exit" \
    "awk changed nothing -- the call or the guard was reworded, so falsifier A proves nothing"
elif [ "$(grep -c -F 'reap_stale_snapshots "$repo_root"' "$MUT_A/slim-session-start.sh")" -ne 1 ]; then
  bad "falsifier A: the reaper call was found and moved below the early exit" \
    "the mutant does not hold exactly one call, so it would test deletion rather than ordering"
else
  ok "falsifier A: the reaper call was found and moved below the early exit"
fi
new_repo
ORDER_SNAP="$REPO/.claude/session-state.pretrim.order-mut.md"
printf 'UNIQUE_ORDER_TOKEN_5c8e\n' > "$ORDER_SNAP"
backdate "$ORDER_SNAP" 30
( cd "$REPO" && bash "$MUT_A/slim-session-start.sh" ) >/dev/null 2>&1
if grep -F -q 'UNIQUE_ORDER_TOKEN_5c8e' "$REPO/.claude/session-state.archive.md" 2>/dev/null; then
  bad "falsifier A: below the early exit the orphaned snapshot is NOT archived" \
    "the mutant archived it anyway, so the ordering assertion discriminates nothing"
else
  ok "falsifier A: below the early exit the orphaned snapshot is NOT archived"
fi

# Falsifier B -- delete only after the append is confirmed. Make the delete unconditional
# and confirm the snapshot is then destroyed by the very append failure the real hook
# survives. This fixture keeps .claude writable, because rm needs write on the DIRECTORY:
# the read-only-dir fixture above would block the mutant's rm too and prove nothing. Only
# the archive file itself is unwritable, so only the append fails.
MUT_B="$TMP/mutant-delete"
mkdir -p "$MUT_B/lib"
cp "$MUT_LIB_SRC" "$MUT_B/lib/handoff-archive.sh"
sed 's/if file_removed_block .*; then/if true; then/' "$HOOK" > "$MUT_B/slim-session-start.sh"
chmod +x "$MUT_B/slim-session-start.sh"
if cmp -s "$MUT_B/slim-session-start.sh" "$HOOK"; then
  bad "falsifier B: the append-confirmed condition was found and removed" \
    "sed changed nothing, so falsifier B proves nothing"
else
  ok "falsifier B: the append-confirmed condition was found and removed"
fi

# One fixture shape, run twice: once against the real hook, once against the mutant.
ro_archive_repo() {
  new_repo
  printf '# Session State\n\nnotes\n' > "$REPO/.claude/session-state.md"
  printf 'UNIQUE_RO_ARCHIVE_TOKEN_2b70\n' > "$REPO/.claude/session-state.pretrim.roarch.md"
  backdate "$REPO/.claude/session-state.pretrim.roarch.md" 30
  : > "$REPO/.claude/session-state.archive.md"
  chmod 444 "$REPO/.claude/session-state.archive.md"
}

ro_archive_repo
run "$REPO"
if [ -f "$REPO/.claude/session-state.pretrim.roarch.md" ]; then
  ok "unwritable archive file: the real hook keeps the snapshot"
else
  bad "unwritable archive file: the real hook keeps the snapshot" "snapshot was deleted"
fi
chmod 644 "$REPO/.claude/session-state.archive.md" 2>/dev/null || true

ro_archive_repo
( cd "$REPO" && bash "$MUT_B/slim-session-start.sh" ) >/dev/null 2>&1
if [ -f "$REPO/.claude/session-state.pretrim.roarch.md" ]; then
  bad "falsifier B: without the condition the mutant deletes the unarchived snapshot" \
    "the mutant kept it too, so the retention assertion discriminates nothing"
else
  ok "falsifier B: without the condition the mutant deletes the unarchived snapshot"
fi
chmod 644 "$REPO/.claude/session-state.archive.md" 2>/dev/null || true

