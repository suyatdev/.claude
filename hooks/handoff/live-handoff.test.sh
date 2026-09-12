#!/usr/bin/env bash
# live-handoff.test.sh — behaviour tests for hooks/handoff/live-handoff.sh, covering the
# snapshot step added by the "snapshot on every turn" task of
# docs/features/handoff-trim-safety.md (named, not numbered — that card renumbers).
#
# What is under test, in the card's terms:
#   * a per-session snapshot is written on EVERY turn, not only over the write cap
#     (spec finding C3), so a voluntary rewrite below the cap is still recoverable;
#   * the snapshot filename carries the session id, so two sessions in one repo do not
#     blind each other (spec finding C2);
#   * if the snapshot cannot be written the trim directive is SUPPRESSED whatever the
#     line count, and the append directive carries a warning naming the failure
#     (spec finding O-C, scenario "The snapshot cannot be written");
#   * a snapshot the keep-guard is holding across a strike is not overwritten, so the
#     "already blocked twice on the same PT" scenario is reachable at all;
#   * every pre-existing behaviour of the hook still holds: pane-agent short-circuit,
#     INIT template creation, the task/bug cap table and its extra directive.
#
# Run: bash hooks/handoff/live-handoff.test.sh
#
# The hook short-circuits on CLAUDE_PANE_AGENT, and this suite may itself be run from a
# pane, so every invocation that expects real work goes through run_hook(), which clears
# that variable. The one test that WANTS the short-circuit sets it explicitly.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HOOK_DIR/live-handoff.sh"
LIB="$HOOK_DIR/lib/handoff-archive.sh"

# Physical path, not the one mktemp hands back — on macOS mktemp -d returns the /var
# symlink form while other tools resolve it to /private/var, and a cmp of two paths that
# differ only by that prefix reads as a failure.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
# chmod back before rm -rf: a test below makes a .claude directory read-only, and the
# trap cannot delete what it cannot enter.
cleanup() { chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

pass=0; fail=0
ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

# mkrepo NAME [LINES] — a throwaway git repo with a .claude/session-state.md of LINES
# lines (default 10). Prints the repo path. Each line is unique so a truncation shows up
# as a content difference, not just a length one.
mkrepo() {
  local name="$1" lines="${2:-10}" repo i
  repo="$TMP/$name"
  mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q )
  : > "$repo/.claude/session-state.md"
  i=1
  while [ "$i" -le "$lines" ]; do
    printf 'notepad line %d\n' "$i" >> "$repo/.claude/session-state.md"
    i=$((i+1))
  done
  printf '%s' "$repo"
}

# run_hook REPO HOOKPATH SESSION_ID [ENV_SESSION_ID] — runs HOOKPATH from inside REPO with
# a UserPromptSubmit-shaped payload on stdin. SESSION_ID "" omits the field from the
# payload entirely (the fallback path). Stdout and stderr land in $OUT / $ERR, rc in $RC.
OUT=""; ERR=""; RC=0
run_hook() {
  local repo="$1" hook="$2" sid="$3" envsid="${4:-}" payload
  if [ -n "$sid" ]; then
    payload="$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","cwd":"%s"}' "$sid" "$repo")"
  else
    payload="$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s"}' "$repo")"
  fi
  OUT="$TMP/hook.out"; ERR="$TMP/hook.err"
  ( cd "$repo" && printf '%s' "$payload" \
      | env -u CLAUDE_PANE_AGENT CLAUDE_CODE_SESSION_ID="$envsid" bash "$hook" ) \
      >"$OUT" 2>"$ERR"
  RC=$?
}

has() { grep -qF -- "$2" "$1"; }

# ============================================================================
# Normal path, under the write cap: snapshot taken anyway, append directive out
# ============================================================================
REPO_A="$(mkrepo repo-under 10)"
run_hook "$REPO_A" "$HOOK" "sess-aaa"
PT_A="$REPO_A/.claude/session-state.pretrim.sess-aaa.md"
if [ "$RC" -eq 0 ]; then
  ok "under the cap: hook exits 0"
else
  bad "under the cap: hook exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if [ -f "$PT_A" ]; then
  ok "under the cap: a snapshot is still written (C3 — every turn, not only over the cap)"
else
  bad "under the cap: a snapshot is still written (C3 — every turn, not only over the cap)" \
    "no file at $PT_A; .claude holds: $(ls "$REPO_A/.claude")"
fi
if cmp -s "$PT_A" "$REPO_A/.claude/session-state.md"; then
  ok "the snapshot is byte-identical to the notepad"
else
  bad "the snapshot is byte-identical to the notepad" "cmp differs"
fi
if has "$OUT" "Do NOT rewrite the whole file"; then
  ok "under the cap: the append-mode directive is emitted"
else
  bad "under the cap: the append-mode directive is emitted" "$(cat "$OUT")"
fi
if has "$OUT" "It has grown too large"; then
  bad "under the cap: no trim directive" "trim text present"
else
  ok "under the cap: no trim directive"
fi
if grep -qE '=== (End )?[Hh]andoff [0-9a-f]+ ' "$OUT"; then
  bad "under the cap: no envelope markers leak into the append-mode directive" \
    "envelope found: $(cat "$OUT")"
else
  ok "under the cap: no envelope markers leak into the append-mode directive"
fi

# ============================================================================
# Over the write cap: snapshot taken, trim directive out
# ============================================================================
REPO_B="$(mkrepo repo-over 160)"
run_hook "$REPO_B" "$HOOK" "sess-bbb"
PT_B="$REPO_B/.claude/session-state.pretrim.sess-bbb.md"
if [ -f "$PT_B" ] && cmp -s "$PT_B" "$REPO_B/.claude/session-state.md"; then
  ok "over the cap: a byte-identical snapshot is written before the directive"
else
  bad "over the cap: a byte-identical snapshot is written before the directive" \
    "exists=$([ -f "$PT_B" ] && echo yes || echo no)"
fi
if has "$OUT" "It has grown too large"; then
  ok "over the cap: the trim directive is emitted when the snapshot succeeded"
else
  bad "over the cap: the trim directive is emitted when the snapshot succeeded" "$(cat "$OUT")"
fi

# --- Task 8: the trim directive files instead of deletes, and names the archive -------
# REPO_B has no [KEEP] region (mkrepo's lines are plain), so this also covers "over the
# cap with no KEEP region": the filing rule still fires and no envelope markers appear.
if has "$OUT" "$REPO_B/.claude/session-state.archive.md"; then
  ok "over the cap, no KEEP region: the trim directive names the archive path"
else
  bad "over the cap, no KEEP region: the trim directive names the archive path" "$(cat "$OUT")"
fi
if has "$OUT" "Filing rule:"; then
  ok "over the cap, no KEEP region: the trim directive carries the filing rule"
else
  bad "over the cap, no KEEP region: the trim directive carries the filing rule" "$(cat "$OUT")"
fi
if grep -qE '=== (End )?[Hh]andoff [0-9a-f]+ ' "$OUT"; then
  bad "over the cap, no KEEP region: no envelope markers leak in" "envelope found: $(cat "$OUT")"
else
  ok "over the cap, no KEEP region: no envelope markers leak in"
fi
if has "$OUT" "Be ruthless"; then
  bad "the old deletion-only phrasing is gone from the trim directive" "'Be ruthless' still present"
else
  ok "the old deletion-only phrasing is gone from the trim directive"
fi

# ============================================================================
# Task 8: over the cap WITH a [KEEP] region — the protected heading must reach the model
# verbatim inside a tamper-evident envelope, open and close tags matching.
# ============================================================================
REPO_P="$TMP/repo-keep"
mkdir -p "$REPO_P/.claude"
( cd "$REPO_P" && git init -q )
{
  printf '# Session State\n\n## Decisions [KEEP]\nRationale line, must survive.\n\n'
  i=1
  while [ "$i" -le 150 ]; do
    printf 'notepad line %d\n' "$i"
    i=$((i+1))
  done
} > "$REPO_P/.claude/session-state.md"
run_hook "$REPO_P" "$HOOK" "sess-ppp"
if has "$OUT" "It has grown too large"; then
  ok "over the cap with a KEEP region: the trim directive still fires"
else
  bad "over the cap with a KEEP region: the trim directive still fires" "$(cat "$OUT")"
fi
if has "$OUT" "$REPO_P/.claude/session-state.archive.md"; then
  ok "over the cap with a KEEP region: the trim directive still names the archive path"
else
  bad "over the cap with a KEEP region: the trim directive still names the archive path" "$(cat "$OUT")"
fi
if has "$OUT" "Decisions [KEEP]"; then
  ok "over the cap with a KEEP region: the protected heading text appears in the directive"
else
  bad "over the cap with a KEEP region: the protected heading text appears in the directive" "$(cat "$OUT")"
fi
# Capture the tag with an anchored group, not a bare [0-9a-f]+ scan — the surrounding
# words ("Handoff", "DATA") themselves contain hex-alphabet letters, so an unanchored
# grep -oE would pick up spurious single-letter "matches" from the prose around the tag.
KEEP_OPEN_TAG="$(sed -nE 's/.*=== Handoff ([0-9a-f]+) \(DATA.*/\1/p' "$OUT")"
KEEP_CLOSE_TAG="$(sed -nE 's/.*=== End handoff ([0-9a-f]+) \(end of DATA\) ===.*/\1/p' "$OUT")"
if [ -n "$KEEP_OPEN_TAG" ] && [ "$KEEP_OPEN_TAG" = "$KEEP_CLOSE_TAG" ]; then
  ok "over the cap with a KEEP region: the heading sits inside a matching-tag envelope"
else
  bad "over the cap with a KEEP region: the heading sits inside a matching-tag envelope" \
    "open=[$KEEP_OPEN_TAG] close=[$KEEP_CLOSE_TAG] out=$(cat "$OUT")"
fi

# --- Falsifier for the matching-tag assertion above: a mutant reinject library whose ----
# close tag is hardcoded instead of reusing $tag. Proves the assertion actually compares
# VALUES (not just "an envelope exists") — without this, a broken tag pairing could slip
# through unnoticed. Never touches the real library; only a scratch copy.
MUT_KEEP_DIR="$TMP/mutant-keep-tag"
mkdir -p "$MUT_KEEP_DIR/lib"
cp "$HOOK" "$MUT_KEEP_DIR/live-handoff.sh"
cp "$LIB" "$MUT_KEEP_DIR/lib/handoff-archive.sh"
sed 's/=== End handoff %s (end of DATA) ===/=== End handoff deadbeef (end of DATA) ===/' \
  "$HOOK_DIR/lib/handoff-keep-reinject.sh" > "$MUT_KEEP_DIR/lib/handoff-keep-reinject.sh"
chmod +x "$MUT_KEEP_DIR/live-handoff.sh"
if cmp -s "$MUT_KEEP_DIR/lib/handoff-keep-reinject.sh" "$HOOK_DIR/lib/handoff-keep-reinject.sh"; then
  bad "falsifier: the close-tag line was found and replaced" \
    "sed changed nothing — the falsifier below proves nothing"
else
  ok "falsifier: the close-tag line was found and replaced"
fi
REPO_Q="$TMP/repo-keep-mut"
mkdir -p "$REPO_Q/.claude"
( cd "$REPO_Q" && git init -q )
cp "$REPO_P/.claude/session-state.md" "$REPO_Q/.claude/session-state.md"
run_hook "$REPO_Q" "$MUT_KEEP_DIR/live-handoff.sh" "sess-qqq"
MUT_OPEN_TAG="$(sed -nE 's/.*=== Handoff ([0-9a-f]+) \(DATA.*/\1/p' "$OUT")"
MUT_CLOSE_TAG="$(sed -nE 's/.*=== End handoff ([0-9a-f]+) \(end of DATA\) ===.*/\1/p' "$OUT")"
# Both tags must be PRESENT and DIFFER. Testing only "not equal" would also be satisfied
# by an empty pair, i.e. by the mutant emitting no envelope at all — which is what happens
# if the sed leaves an unparseable library and REINJECT_LIB_OK suppresses the trim. That
# outcome proves nothing about tag comparison, so it must read as a failure, not a pass.
if [ -z "$MUT_OPEN_TAG" ] || [ -z "$MUT_CLOSE_TAG" ]; then
  bad "falsifier: the matching-tag assertion fails against a mismatched envelope" \
    "the mutant emitted no envelope at all (open=[$MUT_OPEN_TAG] close=[$MUT_CLOSE_TAG]); the tag comparison was never exercised"
elif [ "$MUT_OPEN_TAG" = "$MUT_CLOSE_TAG" ]; then
  bad "falsifier: the matching-tag assertion fails against a mismatched envelope" \
    "the mutant produced matching tags too ([$MUT_OPEN_TAG]/[$MUT_CLOSE_TAG]), so the real assertion discriminates nothing"
else
  ok "falsifier: the matching-tag assertion fails against a mismatched envelope"
fi
# Restore: the same content through the REAL hook passes again (already shown above by the
# REPO_P assertion, re-stated here beside the break for an explicit break/restore pair).
if [ -n "$KEEP_OPEN_TAG" ] && [ "$KEEP_OPEN_TAG" = "$KEEP_CLOSE_TAG" ]; then
  ok "restore: the unmodified hook and library produce a matching-tag envelope again"
else
  bad "restore: the unmodified hook and library produce a matching-tag envelope again" \
    "open=[$KEEP_OPEN_TAG] close=[$KEEP_CLOSE_TAG]"
fi

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

# ============================================================================
# Scenario: Two sessions in one repo do not blind each other (finding C2)
# ============================================================================
REPO_E="$(mkrepo repo-two 20)"
run_hook "$REPO_E" "$HOOK" "sess-AAA"
run_hook "$REPO_E" "$HOOK" "sess-BBB"
if [ -f "$REPO_E/.claude/session-state.pretrim.sess-AAA.md" ] \
   && [ -f "$REPO_E/.claude/session-state.pretrim.sess-BBB.md" ]; then
  ok "two sessions in one repo get two distinct snapshots"
else
  bad "two sessions in one repo get two distinct snapshots" \
    ".claude holds: $(ls "$REPO_E/.claude")"
fi

# ============================================================================
# Session id fallbacks: payload first, then $CLAUDE_CODE_SESSION_ID, then a literal.
# ============================================================================
REPO_G="$(mkrepo repo-envsid 12)"
run_hook "$REPO_G" "$HOOK" "" "env-sid-1"
if [ -f "$REPO_G/.claude/session-state.pretrim.env-sid-1.md" ]; then
  ok "a payload with no session_id falls back to CLAUDE_CODE_SESSION_ID"
else
  bad "a payload with no session_id falls back to CLAUDE_CODE_SESSION_ID" \
    ".claude holds: $(ls "$REPO_G/.claude")"
fi
REPO_H="$(mkrepo repo-nosid 12)"
run_hook "$REPO_H" "$HOOK" "" ""
if [ -f "$REPO_H/.claude/session-state.pretrim.nosession.md" ]; then
  ok "no session id anywhere falls back to the nosession literal, and still snapshots"
else
  bad "no session id anywhere falls back to the nosession literal, and still snapshots" \
    ".claude holds: $(ls "$REPO_H/.claude")"
fi

# ============================================================================
# The session id reaches a filename, so it is sanitized: a traversal-shaped id must not
# escape .claude, and must not silently become the no-snapshot case either.
# ============================================================================
REPO_I="$(mkrepo repo-evil 12)"
run_hook "$REPO_I" "$HOOK" "../../evil id/x"
# Every legitimate snapshot in this run lives inside some repo's .claude directory, so a
# stray is any pretrim file OUTSIDE one — scoping this to "not under $REPO_I/.claude" made
# the other repos' own correct snapshots read as escapes.
# Self-test first: a "found nothing" result is only worth reading if the search can find
# something. Plant a decoy stray, confirm the same expression counts it, then remove it.
printf 'decoy\n' > "$TMP/session-state.pretrim.decoy.md"
DECOY_SEEN="$(find "$TMP" -name 'session-state.pretrim.*' -not -path '*/.claude/*' 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$TMP/session-state.pretrim.decoy.md"
if [ "$DECOY_SEEN" = "1" ]; then
  ok "the stray-snapshot search finds a planted stray, so a zero below means something"
else
  bad "the stray-snapshot search finds a planted stray, so a zero below means something" \
    "the decoy was not counted (got $DECOY_SEEN)"
fi
ESCAPED="$(find "$TMP" -name 'session-state.pretrim.*' -not -path '*/.claude/*' 2>/dev/null | wc -l | tr -d ' ')"
INSIDE="$(find "$REPO_I/.claude" -maxdepth 1 -name 'session-state.pretrim.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$ESCAPED" = "0" ]; then
  ok "a traversal-shaped session id writes nothing outside the repo .claude directory"
else
  bad "a traversal-shaped session id writes nothing outside the repo .claude directory" \
    "found $ESCAPED stray snapshot(s)"
fi
if [ "$INSIDE" = "1" ]; then
  ok "a traversal-shaped session id still produces exactly one snapshot inside .claude"
else
  bad "a traversal-shaped session id still produces exactly one snapshot inside .claude" \
    "found $INSIDE"
fi

# ============================================================================
# A snapshot the keep-guard is holding across a strike must survive the next turn —
# otherwise "the guard has already blocked twice on the same PT" can never happen, and
# the copy of last resort is overwritten by the damaged notepad.
# ============================================================================
REPO_J="$(mkrepo repo-strike 20)"
PT_J="$REPO_J/.claude/session-state.pretrim.sess-jjj.md"
printf 'ORIGINAL SNAPSHOT CONTENT\n' > "$PT_J"
: > "$REPO_J/.claude/session-state.keepguard-strikes.sess-jjj"
run_hook "$REPO_J" "$HOOK" "sess-jjj"
if has "$PT_J" "ORIGINAL SNAPSHOT CONTENT"; then
  ok "a retained snapshot is not overwritten while a strike file exists"
else
  bad "a retained snapshot is not overwritten while a strike file exists" \
    "the recovery copy was replaced by the current notepad"
fi
# Discriminator: with no strike file the same starting state IS overwritten, so the test
# above is measuring the strike check and not some unrelated refusal to write.
REPO_K="$(mkrepo repo-nostrike 20)"
PT_K="$REPO_K/.claude/session-state.pretrim.sess-kkk.md"
printf 'ORIGINAL SNAPSHOT CONTENT\n' > "$PT_K"
run_hook "$REPO_K" "$HOOK" "sess-kkk"
if has "$PT_K" "ORIGINAL SNAPSHOT CONTENT"; then
  bad "with no strike file the snapshot is refreshed" "stale content survived"
else
  ok "with no strike file the snapshot is refreshed"
fi
# And a strike file with no snapshot beside it must still snapshot — otherwise a deleted
# PT plus a stale strike file leaves the turn unprotected forever.
REPO_L="$(mkrepo repo-strike-nopt 20)"
: > "$REPO_L/.claude/session-state.keepguard-strikes.sess-lll"
run_hook "$REPO_L" "$HOOK" "sess-lll"
if [ -f "$REPO_L/.claude/session-state.pretrim.sess-lll.md" ]; then
  ok "a strike file with no snapshot beside it still takes a fresh snapshot"
else
  bad "a strike file with no snapshot beside it still takes a fresh snapshot" \
    ".claude holds: $(ls "$REPO_L/.claude")"
fi

# ============================================================================
# Pre-existing behaviour that must not regress
# ============================================================================
REPO_M="$(mkrepo repo-pane 160)"
PANE_OUT="$TMP/pane.out"
( cd "$REPO_M" && printf '{"session_id":"sess-mmm"}' \
    | env CLAUDE_PANE_AGENT=1 bash "$HOOK" ) >"$PANE_OUT" 2>&1
PANE_RC=$?
if [ "$PANE_RC" -eq 0 ] && [ ! -s "$PANE_OUT" ] \
   && [ ! -f "$REPO_M/.claude/session-state.pretrim.sess-mmm.md" ]; then
  ok "a pane agent emits nothing and writes no snapshot"
else
  bad "a pane agent emits nothing and writes no snapshot" \
    "rc=$PANE_RC out=$(cat "$PANE_OUT")"
fi

REPO_N="$TMP/repo-init"
mkdir -p "$REPO_N/.claude"
( cd "$REPO_N" && git init -q )
run_hook "$REPO_N" "$HOOK" "sess-nnn"
if [ -f "$REPO_N/.claude/session-state.md" ] \
   && has "$REPO_N/.claude/session-state.md" "Files touched this session"; then
  ok "a missing notepad is still created from the INIT template"
else
  bad "a missing notepad is still created from the INIT template" "template missing or unmarked"
fi
if [ -f "$REPO_N/.claude/session-state.pretrim.sess-nnn.md" ]; then
  ok "the freshly created notepad is snapshotted on the same turn"
else
  bad "the freshly created notepad is snapshotted on the same turn" \
    ".claude holds: $(ls "$REPO_N/.claude")"
fi

# The task/bug cap table and its extra directive: 160 lines is over the 150-line general
# cap but under the 170-line task cap, so the task file is what decides.
REPO_O="$(mkrepo repo-task 160)"
: > "$REPO_O/.claude/current-task.md"
run_hook "$REPO_O" "$HOOK" "sess-ooo"
if has "$OUT" "has the current task or bug been completed"; then
  ok "the task/bug directive still rides along when current-task.md exists"
else
  bad "the task/bug directive still rides along when current-task.md exists" "$(cat "$OUT")"
fi
if has "$OUT" "It has grown too large"; then
  bad "the task cap still raises the trim threshold to 170 lines" "160 lines trimmed as if the cap were 150"
else
  ok "the task cap still raises the trim threshold to 170 lines"
fi

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
