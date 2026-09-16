# shellcheck shell=bash
# shellcheck disable=SC2154  # got/out/err are assigned by the entry file's run helper (slim-session-start.test.sh) before this part is sourced
# 40-contract-and-guard-liveness.sh — sourced by ../slim-session-start.test.sh — not runnable on its own.
# Covers the session-state.md-only read contract, guard-liveness reporting, and settings.json registration.

# --- Contract: reads session-state.md only ---------------------------------------------
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
printf 'DO NOT EMIT ME\n' > "$REPO/.claude/context.md"
printf 'DO NOT EMIT ME EITHER\n' > "$REPO/.claude/task-history.md"
printf 'DO NOT EMIT ME EITHER\n' > "$REPO/CODING_MEMORY.md"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"DO NOT EMIT"*) bad "only session-state.md is read" "$OUT" ;;
  *) ok "only session-state.md is read (context.md/task-history.md/CODING_MEMORY.md ignored)" ;;
esac

# --- Scenario: Guard liveness (task 13, spec finding O2) ------------------------------
# docs/features/handoff-trim-safety.spec.md, "Guard liveness (finding O2)" and its
# Behaviour scenarios "The guard has not run" / "The session-start report reads the last
# decision token". The heartbeat log written by handoff-keep-guard.sh lives at
# .claude/session-state.keepguard.log; line format (handoff-keep-guard.sh:201):
#   2026-09-08T16:38:44Z session=<id> decision=<token> protected_regions=<n> removed_lines=<n>
# The five decision= tokens the guard actually writes: allow, block, unprotected,
# failopen, archive_failed (handoff-keep-guard.sh:249,295,314,344,355,365).

# (a) No log at all -> "never run here".
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"guard: never run here"*) ok "guard liveness: no log at all -> 'never run here'" ;;
  *) bad "guard liveness: no log at all -> 'never run here'" "$OUT" ;;
esac

# (b) Spec scenario "The session-start report reads the last decision token": last line
# decision=unprotected, notepad OLDER than the log (mtime alone reads healthy).
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
GL_LOG="$REPO/.claude/session-state.keepguard.log"
printf '2026-09-08T16:38:44Z session=abc123 decision=unprotected protected_regions=0 removed_lines=0\n' \
  > "$GL_LOG"
backdate "$REPO/.claude/session-state.md" 2
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"left the notepad unprotected"*) ok "guard liveness: decision=unprotected is read from the last log line even though mtime alone reads healthy" ;;
  *) bad "guard liveness: decision=unprotected is read from the last log line even though mtime alone reads healthy" "$OUT" ;;
esac

# And a reader that consults only mtime fails this scenario: a mutant that forces the
# parsed token to "allow" regardless of what the log actually says. Anchor: the case-arm
# assignment `token=unprotected ;;` inside guard_liveness_state (slim-session-start.sh) is
# rewritten to `token=allow ;;` -- robust because it is the single line that maps the
# literal log token to the internal variable, and (checked below) occurs exactly once.
GL_TOKEN_ANCHOR='token=unprotected ;;'
GL_TOKEN_ANCHOR_N="$(grep -c -F -- "$GL_TOKEN_ANCHOR" "$HOOK")"
if [ "$GL_TOKEN_ANCHOR_N" -eq 1 ]; then
  ok "falsifier: the unprotected->token case-arm anchor is unique in the hook"
else
  bad "falsifier: the unprotected->token case-arm anchor is unique in the hook" \
    "found $GL_TOKEN_ANCHOR_N occurrences of '$GL_TOKEN_ANCHOR', want 1"
fi
MUT_TOKEN="$TMP/mutant-token-allow"
mkdir -p "$MUT_TOKEN/lib"
cp "$MUT_LIB_SRC" "$MUT_TOKEN/lib/handoff-archive.sh"
sed 's/token=unprotected ;;/token=allow ;;/' "$HOOK" > "$MUT_TOKEN/slim-session-start.sh"
chmod +x "$MUT_TOKEN/slim-session-start.sh"
if cmp -s "$MUT_TOKEN/slim-session-start.sh" "$HOOK"; then
  bad "falsifier: sed changed the unprotected->allow token mapping" "mutant identical to the real hook"
else
  ok "falsifier: sed changed the unprotected->allow token mapping"
fi
( cd "$REPO" && bash "$MUT_TOKEN/slim-session-start.sh" ) > "$TMP/mut-token.out" 2>/dev/null
MUT_TOKEN_OUT="$(cat "$TMP/mut-token.out")"
case "$MUT_TOKEN_OUT" in
  *"unprotected"*) bad "falsifier: mutant with the token forced to allow no longer reports 'unprotected' (the assertion is vacuous)" "$MUT_TOKEN_OUT" ;;
  *) ok "falsifier: mutant with the token forced to allow no longer reports 'unprotected'" ;;
esac

# (c) Last line decision=allow, notepad touched AFTER the log -> "notepad changed after
# that run" is appended.
new_repo
GL_LOG="$REPO/.claude/session-state.keepguard.log"
printf '2026-09-08T16:38:44Z session=abc123 decision=allow protected_regions=1 removed_lines=0\n' \
  > "$GL_LOG"
backdate "$GL_LOG" 1
printf 'fresh notes\n' > "$REPO/.claude/session-state.md"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"notepad changed after that run"*) ok "guard liveness: notepad newer than the log is flagged" ;;
  *) bad "guard liveness: notepad newer than the log is flagged" "$OUT" ;;
esac

# (d) Last line decision=allow, notepad OLDER than the log -> plain 'ok', no append, and
# none of the other-state phrases leak in.
new_repo
printf 'old notes\n' > "$REPO/.claude/session-state.md"
backdate "$REPO/.claude/session-state.md" 2
GL_LOG="$REPO/.claude/session-state.keepguard.log"
printf '2026-09-08T16:38:44Z session=abc123 decision=allow protected_regions=1 removed_lines=0\n' \
  > "$GL_LOG"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"guard: ok (last run allow)"*) ok "guard liveness: decision=allow with an older notepad -> 'ok', no append" ;;
  *) bad "guard liveness: decision=allow with an older notepad -> 'ok', no append" "$OUT" ;;
esac
GL_NONE_LEAKED=1
for s in unprotected "changed after" "never run"; do
  case "$OUT" in *"$s"*) GL_NONE_LEAKED=0 ;; esac
done
if [ "$GL_NONE_LEAKED" -eq 1 ]; then
  ok "guard liveness: allow header carries none of unprotected/changed-after/never-run"
else
  bad "guard liveness: allow header carries none of unprotected/changed-after/never-run" "$OUT"
fi

# (e) Every remaining token maps to its own phrase.
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
backdate "$REPO/.claude/session-state.md" 2
printf '2026-09-08T16:38:44Z session=a decision=archive_failed protected_regions=1 removed_lines=2\n' \
  > "$REPO/.claude/session-state.keepguard.log"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"could not archive"*) ok "guard liveness: decision=archive_failed -> 'could not archive'" ;;
  *) bad "guard liveness: decision=archive_failed -> 'could not archive'" "$OUT" ;;
esac

new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
backdate "$REPO/.claude/session-state.md" 2
printf '2026-09-08T16:38:44Z session=a decision=block protected_regions=1 removed_lines=0\n' \
  > "$REPO/.claude/session-state.keepguard.log"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"blocked a turn"*) ok "guard liveness: decision=block -> 'blocked a turn'" ;;
  *) bad "guard liveness: decision=block -> 'blocked a turn'" "$OUT" ;;
esac

new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
backdate "$REPO/.claude/session-state.md" 2
printf '2026-09-08T16:38:44Z session=a decision=failopen protected_regions=1 removed_lines=0\n' \
  > "$REPO/.claude/session-state.keepguard.log"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"strike cap"*) ok "guard liveness: decision=failopen -> 'strike cap'" ;;
  *) bad "guard liveness: decision=failopen -> 'strike cap'" "$OUT" ;;
esac

# (f) Last line wins, regardless of what came before it.
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
backdate "$REPO/.claude/session-state.md" 2
{
  printf '2026-09-08T16:00:00Z session=a decision=unprotected protected_regions=0 removed_lines=0\n'
  printf '2026-09-08T16:10:00Z session=a decision=unprotected protected_regions=0 removed_lines=0\n'
  printf '2026-09-08T16:20:00Z session=a decision=allow protected_regions=1 removed_lines=0\n'
} > "$REPO/.claude/session-state.keepguard.log"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"guard: ok (last run allow)"*) ok "guard liveness: last line wins (unprotected, unprotected, allow -> ok)" ;;
  *) bad "guard liveness: last line wins (unprotected, unprotected, allow -> ok)" "$OUT" ;;
esac

new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
backdate "$REPO/.claude/session-state.md" 2
{
  printf '2026-09-08T16:00:00Z session=a decision=allow protected_regions=1 removed_lines=0\n'
  printf '2026-09-08T16:10:00Z session=a decision=allow protected_regions=1 removed_lines=0\n'
  printf '2026-09-08T16:20:00Z session=a decision=unprotected protected_regions=0 removed_lines=0\n'
} > "$REPO/.claude/session-state.keepguard.log"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"left the notepad unprotected"*) ok "guard liveness: last line wins (allow, allow, unprotected -> unprotected)" ;;
  *) bad "guard liveness: last line wins (allow, allow, unprotected -> unprotected)" "$OUT" ;;
esac

# (g) Unreadable log -> 'log unreadable', exit 0, body still emitted. Skipped (with a
# printed note) if this suite is running as root, where chmod 000 does not block reads.
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
backdate "$REPO/.claude/session-state.md" 2
GL_LOG="$REPO/.claude/session-state.keepguard.log"
printf '2026-09-08T16:38:44Z session=a decision=allow protected_regions=1 removed_lines=0\n' > "$GL_LOG"
chmod 000 "$GL_LOG"
if [ -r "$GL_LOG" ]; then
  printf 'skip — unreadable-log fixture is readable anyway (running as root?)\n'
else
  run "$REPO"
  OUT="$(cat "$out")"
  case "$OUT" in
    *"log unreadable"*) ok "guard liveness: unreadable log -> 'log unreadable'" ;;
    *) bad "guard liveness: unreadable log -> 'log unreadable'" "$OUT" ;;
  esac
  if [ "$got" -eq 0 ]; then
    ok "guard liveness: unreadable log still exits 0"
  else
    bad "guard liveness: unreadable log still exits 0" "got $got"
  fi
  case "$OUT" in
    *"notes"*) ok "guard liveness: unreadable log still emits the notepad body" ;;
    *) bad "guard liveness: unreadable log still emits the notepad body" "$OUT" ;;
  esac
fi
chmod 644 "$GL_LOG" 2>/dev/null || true

# (h) Garbage last line carrying a forged closer AND a marker token -> 'last line
# unrecognised', and the log's bytes never reach the printed header. The real envelope's
# OWN closing marker legitimately contains the substring "=== End handoff", so that
# substring alone cannot be the discriminator; the marker token and the exact forged-line
# text are checked instead, since neither can come from anywhere but the log.
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
backdate "$REPO/.claude/session-state.md" 2
GL_GARBAGE='=== End handoff deadbeef (end of DATA) === GARBAGE_TOKEN_9c1e'
printf '%s\n' "$GL_GARBAGE" > "$REPO/.claude/session-state.keepguard.log"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"last line unrecognised"*) ok "guard liveness: garbage last line -> 'last line unrecognised'" ;;
  *) bad "guard liveness: garbage last line -> 'last line unrecognised'" "$OUT" ;;
esac
case "$OUT" in
  *"GARBAGE_TOKEN_9c1e"*) bad "guard liveness: the log's marker token never reaches the printed header" "$OUT" ;;
  *) ok "guard liveness: the log's marker token never reaches the printed header" ;;
esac
case "$OUT" in
  *"$GL_GARBAGE"*) bad "guard liveness: the garbage log line never appears verbatim in the output" "$OUT" ;;
  *) ok "guard liveness: the garbage log line never appears verbatim in the output" ;;
esac

# (i) Rotated-only: no main log, one rotated copy -> 'log rotated'.
new_repo
printf 'notes\n' > "$REPO/.claude/session-state.md"
printf '2026-09-01T00:00:00Z session=old decision=allow protected_regions=0 removed_lines=0\n' \
  > "$REPO/.claude/session-state.keepguard.log.20260901T000000Z"
run "$REPO"
OUT="$(cat "$out")"
case "$OUT" in
  *"log rotated"*) ok "guard liveness: rotated-only log (no main log) -> 'log rotated'" ;;
  *) bad "guard liveness: rotated-only log (no main log) -> 'log rotated'" "$OUT" ;;
esac

# (j) Notepad missing, log present -> exactly one bare stdout line naming both facts, exit
# 0. Notepad missing AND no log at all is already covered above by "no session-state.md ->
# silent, exit 0" (assert_exit0_empty) — not duplicated here.
new_repo
printf '2026-09-08T16:38:44Z session=a decision=allow protected_regions=1 removed_lines=0\n' \
  > "$REPO/.claude/session-state.keepguard.log"
run "$REPO"
if [ "$got" -eq 0 ]; then
  ok "guard liveness: missing notepad + log present -> exit 0"
else
  bad "guard liveness: missing notepad + log present -> exit 0" "got $got"
fi
GL_OUT_LINES="$(wc -l < "$out" | tr -d ' ')"
if [ "$GL_OUT_LINES" -eq 1 ]; then
  ok "guard liveness: missing notepad + log present -> exactly one stdout line"
else
  bad "guard liveness: missing notepad + log present -> exactly one stdout line" \
    "got $GL_OUT_LINES lines: $(cat "$out")"
fi
OUT="$(cat "$out")"
case "$OUT" in
  *"session-state.md is missing"*) ok "guard liveness: missing-notepad line names session-state.md" ;;
  *) bad "guard liveness: missing-notepad line names session-state.md" "$OUT" ;;
esac
case "$OUT" in
  *"guard: ok"*) ok "guard liveness: missing-notepad line still carries the guard state" ;;
  *) bad "guard liveness: missing-notepad line still carries the guard state" "$OUT" ;;
esac

# (k) Notepad present but empty (0 bytes), log present -> the same bare line, exit 0.
new_repo
: > "$REPO/.claude/session-state.md"
printf '2026-09-08T16:38:44Z session=a decision=allow protected_regions=1 removed_lines=0\n' \
  > "$REPO/.claude/session-state.keepguard.log"
run "$REPO"
if [ "$got" -eq 0 ]; then
  ok "guard liveness: empty notepad + log present -> exit 0"
else
  bad "guard liveness: empty notepad + log present -> exit 0" "got $got"
fi
OUT="$(cat "$out")"
case "$OUT" in
  *"session-state.md is missing"*"guard: ok"*) ok "guard liveness: empty notepad -> the same bare missing-notepad line" ;;
  *) bad "guard liveness: empty notepad -> the same bare missing-notepad line" "$OUT" ;;
esac

# (l) Mutation control for "above the early exits" (task 13 ordering requirement, same C6
# rationale as falsifier A above for the reaper). The mutant moves BOTH the guard_state
# assignment and the missing-notepad report line to occur AFTER the
# notepad-missing/unreadable exit guard. For the (j) fixture (missing notepad, log
# present) that exit fires first, so the relocated lines never run and a correctly
# discriminating mutant prints nothing at all -- not merely a wrong phrase.
GL_ANCHOR_ASSIGN='guard_state="$(guard_liveness_state "$repo_root" "$state_file")"'
GL_ANCHOR_REPORT='[ -f "$state_file" ] && [ -r "$state_file" ] || report_missing_notepad "$repo_root" "$guard_state"'
GL_ANCHOR_EXIT='[ -f "$state_file" ] && [ -r "$state_file" ] || exit 0'
GL_N_ASSIGN="$(grep -c -F -- "$GL_ANCHOR_ASSIGN" "$HOOK")"
GL_N_REPORT="$(grep -c -F -- "$GL_ANCHOR_REPORT" "$HOOK")"
GL_N_EXIT="$(grep -c -F -- "$GL_ANCHOR_EXIT" "$HOOK")"
if [ "$GL_N_ASSIGN" -eq 1 ] && [ "$GL_N_REPORT" -eq 1 ] && [ "$GL_N_EXIT" -eq 1 ]; then
  ok "falsifier: the guard-liveness ordering anchors are each unique in the hook"
else
  bad "falsifier: the guard-liveness ordering anchors are each unique in the hook" \
    "assign=$GL_N_ASSIGN report=$GL_N_REPORT exit=$GL_N_EXIT (want 1/1/1)"
fi
MUT_ORDER="$TMP/mutant-guard-order"
mkdir -p "$MUT_ORDER/lib"
cp "$MUT_LIB_SRC" "$MUT_ORDER/lib/handoff-archive.sh"
awk -v assign_anchor="$GL_ANCHOR_ASSIGN" -v report_anchor="$GL_ANCHOR_REPORT" -v exit_anchor="$GL_ANCHOR_EXIT" '
  index($0, assign_anchor) > 0 { next }
  index($0, report_anchor) > 0 { next }
  { print }
  index($0, exit_anchor) > 0 {
    print "  " assign_anchor
    print "  " report_anchor
  }
' "$HOOK" > "$MUT_ORDER/slim-session-start.sh"
chmod +x "$MUT_ORDER/slim-session-start.sh"
if cmp -s "$MUT_ORDER/slim-session-start.sh" "$HOOK"; then
  bad "falsifier: the guard-liveness assign/report lines were found and moved below the exit" \
    "mutant identical to the real hook"
else
  ok "falsifier: the guard-liveness assign/report lines were found and moved below the exit"
fi
new_repo
printf '2026-09-08T16:38:44Z session=a decision=allow protected_regions=1 removed_lines=0\n' \
  > "$REPO/.claude/session-state.keepguard.log"
( cd "$REPO" && bash "$MUT_ORDER/slim-session-start.sh" ) > "$TMP/mut-order.out" 2>"$TMP/mut-order.err"
if [ -s "$TMP/mut-order.out" ]; then
  bad "falsifier: mutant with guard-liveness moved below the early exit prints nothing for the missing-notepad case" \
    "mutant printed: $(cat "$TMP/mut-order.out")"
else
  ok "falsifier: mutant with guard-liveness moved below the early exit prints nothing for the missing-notepad case"
fi

# (m) CLAUDE_PANE_AGENT still exits first, before anything -- including guard liveness.
new_repo
GL_PANE_LOG="$REPO/.claude/session-state.keepguard.log"
printf '2026-09-08T16:38:44Z session=a decision=allow protected_regions=1 removed_lines=0\n' \
  > "$GL_PANE_LOG"
run "$REPO" CLAUDE_PANE_AGENT=1
assert_exit0_empty "guard liveness: CLAUDE_PANE_AGENT set, notepad missing, log present -> still silent, exit 0"

# --- Registration assertion: this hook must actually be wired into settings.json -----
# A hook can pass every test above while sitting unregistered in settings.json, in which
# case it never runs in production (judge-guard.test.sh:344 names the hazard). Checked
# against the REAL repo settings.json, not a fixture — that file is what Claude Code
# actually loads.
SETTINGS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)/settings.json"
if [ -f "$SETTINGS" ] && /usr/bin/jq -e \
     '[.hooks.SessionStart[]?.hooks[]?.command] | any(test("hooks/handoff/slim-session-start\\.sh"))' \
     "$SETTINGS" >/dev/null 2>&1; then
  ok "slim-session-start.sh is registered under SessionStart in settings.json"
else
  bad "slim-session-start.sh is registered under SessionStart in settings.json" "not found in $SETTINGS"
fi

# Self-check: the assertion above must be able to fail, not just always pass — the exact
# vacuous-test trap task 4 hit. Strip the hook from a copy of the real file and confirm
# the same query reports it missing.
MUTANT="$TMP/settings-mutant.json"
/usr/bin/jq 'del(.hooks.SessionStart[]?.hooks[]? | select(.command | test("slim-session-start")))' \
  "$SETTINGS" > "$MUTANT" 2>/dev/null
if /usr/bin/jq -e \
     '[.hooks.SessionStart[]?.hooks[]?.command] | any(test("hooks/handoff/slim-session-start\\.sh"))' \
     "$MUTANT" >/dev/null 2>&1; then
  bad "registration check can fail (hook removed from a copy)" "mutant still reported present"
else
  ok "registration check can fail (hook removed from a copy)"
fi

