# 50-pretrim-snapshot.sh — sourced by ../pre-compact-handoff.test.sh — not runnable on its own.
# Task 9: routes this hook through the same pre-trim snapshot as live-handoff.sh -- healthy run, missing-notepad, and library-failure interaction with the snapshot. Reads $REPO_KEEP from 20-keep-region-and-framing.sh.

# ============================================================================
# Task 9 (docs/features/handoff-trim-safety.md): route this hook through the same
# pre-trim snapshot as live-handoff.sh. Before this task the hook had zero references to
# snapshot_notepad/PRETRIM_FILE -- the healthy REWRITE directive fired on the reinject
# library alone, with nothing backing up the notepad it was about to order a cut in.
#
# New behaviour, in the card's terms:
#   * session identity uses the same three-step fallback as live-handoff.sh (payload
#     session_id, then $CLAUDE_CODE_SESSION_ID, then the "nosession" literal), and the
#     same PRETRIM_FILE/STRIKE_FILE filename contract handoff-keep-guard.sh depends on;
#   * a byte-identical snapshot is taken BEFORE any directive is emitted;
#   * the REWRITE directive fires only when the snapshot succeeded AND the reinject
#     library loaded -- otherwise the existing append-only directive fires, with no line
#     target, and a reason distinguishing "the snapshot could not be written" from
#     "a library could not be loaded" (the FAILED_LIB mechanism already covers the
#     latter, and keeps a snapshot-library failure and a reinject-library failure
#     distinguishable from each other by which path FAILED_LIB names);
#   * a missing notepad is not a snapshot FAILURE -- there is nothing to back up, and
#     keep_trim_directive already handles a missing notepad on its own (pre-existing
#     "no session-state.md" test above), so this must not force append-only.
# ============================================================================

# ----------------------------------------------------------------------------
# Healthy run: a byte-identical snapshot exists alongside the ordinary rewrite
# directive, and the [KEEP] envelope and line-target text are unaffected.
# ----------------------------------------------------------------------------
REPO_SNAP="$(mkrepo repo-snapshot)"
mkdir -p "$REPO_SNAP/.claude"
{
  printf '# Session State\n\n## Critical Fact [KEEP]\nMust survive.\n\n'
  i=1
  while [ "$i" -le 160 ]; do
    printf 'notepad line %d\n' "$i"
    i=$((i+1))
  done
} > "$REPO_SNAP/.claude/session-state.md"
run_hook_sid "$REPO_SNAP" "$HOOK" "sess-snap"
PT_SNAP="$REPO_SNAP/.claude/session-state.pretrim.sess-snap.md"
if [ "$RC" -eq 0 ]; then
  ok "healthy run: hook exits 0"
else
  bad "healthy run: hook exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if [ -f "$PT_SNAP" ]; then
  ok "healthy run: a pre-trim snapshot file is written"
else
  bad "healthy run: a pre-trim snapshot file is written" ".claude holds: $(ls "$REPO_SNAP/.claude")"
fi
if cmp -s "$PT_SNAP" "$REPO_SNAP/.claude/session-state.md"; then
  ok "healthy run: the snapshot is byte-identical to the notepad"
else
  bad "healthy run: the snapshot is byte-identical to the notepad" "cmp differs"
fi
if has "$OUT" 'Line targets: general 120-150, task 140-170, bug 160-190 (if needed).'; then
  ok "healthy run: the rewrite directive still carries the line-target string"
else
  bad "healthy run: the rewrite directive still carries the line-target string" "$(cat "$OUT")"
fi
if envelope_wraps "$OUT" 'Critical Fact [KEEP]'; then
  ok "healthy run: the [KEEP] heading is still re-injected inside a matching-tag envelope"
else
  bad "healthy run: the [KEEP] heading is still re-injected inside a matching-tag envelope" "$(cat "$OUT")"
fi

# ----------------------------------------------------------------------------
# Session identity: payload session_id, two distinct snapshots, env-var fallback,
# nosession fallback, and a traversal-shaped id sanitized to stay inside .claude.
# ----------------------------------------------------------------------------
REPO_SID_A="$(mkrepo repo-sid-a)"
mkdir -p "$REPO_SID_A/.claude"
printf 'line one\n' > "$REPO_SID_A/.claude/session-state.md"
run_hook_sid "$REPO_SID_A" "$HOOK" "sess-payload-1"
if [ -f "$REPO_SID_A/.claude/session-state.pretrim.sess-payload-1.md" ]; then
  ok "a session_id on stdin lands in the snapshot filename"
else
  bad "a session_id on stdin lands in the snapshot filename" ".claude holds: $(ls "$REPO_SID_A/.claude")"
fi

REPO_SID_B="$(mkrepo repo-sid-b)"
mkdir -p "$REPO_SID_B/.claude"
printf 'line one\n' > "$REPO_SID_B/.claude/session-state.md"
run_hook_sid "$REPO_SID_B" "$HOOK" "sess-first"
run_hook_sid "$REPO_SID_B" "$HOOK" "sess-second"
if [ -f "$REPO_SID_B/.claude/session-state.pretrim.sess-first.md" ] \
   && [ -f "$REPO_SID_B/.claude/session-state.pretrim.sess-second.md" ]; then
  ok "two payloads in one repo produce two distinct snapshots"
else
  bad "two payloads in one repo produce two distinct snapshots" ".claude holds: $(ls "$REPO_SID_B/.claude")"
fi

REPO_SID_C="$(mkrepo repo-sid-c)"
mkdir -p "$REPO_SID_C/.claude"
printf 'line one\n' > "$REPO_SID_C/.claude/session-state.md"
run_hook_sid "$REPO_SID_C" "$HOOK" "" "env-sid-1"
if [ -f "$REPO_SID_C/.claude/session-state.pretrim.env-sid-1.md" ]; then
  ok "no session_id in the payload falls back to CLAUDE_CODE_SESSION_ID"
else
  bad "no session_id in the payload falls back to CLAUDE_CODE_SESSION_ID" ".claude holds: $(ls "$REPO_SID_C/.claude")"
fi

REPO_SID_D="$(mkrepo repo-sid-d)"
mkdir -p "$REPO_SID_D/.claude"
printf 'line one\n' > "$REPO_SID_D/.claude/session-state.md"
run_hook_sid "$REPO_SID_D" "$HOOK" "" ""
if [ -f "$REPO_SID_D/.claude/session-state.pretrim.nosession.md" ]; then
  ok "neither payload nor env var falls back to the nosession literal, and still snapshots"
else
  bad "neither payload nor env var falls back to the nosession literal, and still snapshots" \
    ".claude holds: $(ls "$REPO_SID_D/.claude")"
fi

REPO_SID_E="$(mkrepo repo-sid-evil)"
mkdir -p "$REPO_SID_E/.claude"
printf 'line one\n' > "$REPO_SID_E/.claude/session-state.md"
run_hook_sid "$REPO_SID_E" "$HOOK" "../../evil id/x"
# Every legitimate snapshot in this run lives inside some repo's .claude directory, so a
# stray is any pretrim file OUTSIDE one. Self-test first: a "found nothing" result is
# only worth reading if the search can find something.
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
INSIDE="$(find "$REPO_SID_E/.claude" -maxdepth 1 -name 'session-state.pretrim.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$ESCAPED" = "0" ]; then
  ok "a traversal-shaped session id writes nothing outside the repo .claude directory"
else
  bad "a traversal-shaped session id writes nothing outside the repo .claude directory" \
    "found $ESCAPED stray snapshot(s)"
fi
if [ "$INSIDE" = "1" ]; then
  ok "a traversal-shaped session id still produces exactly one snapshot inside .claude"
else
  bad "a traversal-shaped session id still produces exactly one snapshot inside .claude" "found $INSIDE"
fi

# ----------------------------------------------------------------------------
# Strike retention: a snapshot the keep-guard is holding across a strike must survive
# this hook's own run too -- same rule as live-handoff.sh, same reasoning (the guard's
# copy is the pre-damage one; overwriting it with the damaged notepad in front of us
# would destroy the only recovery source at exactly the moment it is needed).
# ----------------------------------------------------------------------------
REPO_STRIKE="$(mkrepo repo-strike)"
mkdir -p "$REPO_STRIKE/.claude"
printf 'current damaged notepad\n' > "$REPO_STRIKE/.claude/session-state.md"
PT_STRIKE="$REPO_STRIKE/.claude/session-state.pretrim.sess-strike.md"
printf 'ORIGINAL SNAPSHOT CONTENT\n' > "$PT_STRIKE"
: > "$REPO_STRIKE/.claude/session-state.keepguard-strikes.sess-strike"
run_hook_sid "$REPO_STRIKE" "$HOOK" "sess-strike"
if has "$PT_STRIKE" "ORIGINAL SNAPSHOT CONTENT"; then
  ok "a retained snapshot is not overwritten while a strike file exists"
else
  bad "a retained snapshot is not overwritten while a strike file exists" \
    "the recovery copy was replaced by the current notepad"
fi

# Discriminator: with no strike file the same starting state IS overwritten, so the test
# above is measuring the strike check and not some unrelated refusal to write.
REPO_NOSTRIKE="$(mkrepo repo-nostrike)"
mkdir -p "$REPO_NOSTRIKE/.claude"
printf 'current notepad\n' > "$REPO_NOSTRIKE/.claude/session-state.md"
PT_NOSTRIKE="$REPO_NOSTRIKE/.claude/session-state.pretrim.sess-nostrike.md"
printf 'ORIGINAL SNAPSHOT CONTENT\n' > "$PT_NOSTRIKE"
run_hook_sid "$REPO_NOSTRIKE" "$HOOK" "sess-nostrike"
if has "$PT_NOSTRIKE" "ORIGINAL SNAPSHOT CONTENT"; then
  bad "with no strike file the snapshot is refreshed" "stale content survived"
else
  ok "with no strike file the snapshot is refreshed"
fi

# And a strike file with no snapshot beside it must still snapshot -- otherwise a
# deleted PT plus a stale strike file leaves the turn unprotected forever.
REPO_STRIKE_NOPT="$(mkrepo repo-strike-nopt)"
mkdir -p "$REPO_STRIKE_NOPT/.claude"
printf 'current notepad\n' > "$REPO_STRIKE_NOPT/.claude/session-state.md"
: > "$REPO_STRIKE_NOPT/.claude/session-state.keepguard-strikes.sess-strikenopt"
run_hook_sid "$REPO_STRIKE_NOPT" "$HOOK" "sess-strikenopt"
if [ -f "$REPO_STRIKE_NOPT/.claude/session-state.pretrim.sess-strikenopt.md" ]; then
  ok "a strike file with no snapshot beside it still takes a fresh snapshot"
else
  bad "a strike file with no snapshot beside it still takes a fresh snapshot" \
    ".claude holds: $(ls "$REPO_STRIKE_NOPT/.claude")"
fi

# ----------------------------------------------------------------------------
# A missing notepad is not a snapshot failure: nothing to back up, so the healthy
# rewrite directive still fires (via keep_trim_directive's own missing-notepad
# handling), and no pretrim file is written since there was nothing to copy.
# ----------------------------------------------------------------------------
REPO_NONOTEPAD="$(mkrepo repo-nonotepad)"
run_hook_sid "$REPO_NONOTEPAD" "$HOOK" "sess-nonotepad"
if has "$OUT" 'Line targets: general 120-150, task 140-170, bug 160-190 (if needed).'; then
  ok "missing notepad: the healthy rewrite directive still fires, not append-only"
else
  bad "missing notepad: the healthy rewrite directive still fires, not append-only" "$(cat "$OUT")"
fi
if [ ! -e "$REPO_NONOTEPAD/.claude/session-state.pretrim.sess-nonotepad.md" ]; then
  ok "missing notepad: no snapshot file is written (nothing existed to copy)"
else
  bad "missing notepad: no snapshot file is written (nothing existed to copy)" \
    ".claude holds: $(ls "$REPO_NONOTEPAD/.claude")"
fi

# ----------------------------------------------------------------------------
# Snapshot failure: the notepad exists but .claude cannot be written to (mktemp beside
# the pretrim path fails). rc 0, a directive IS emitted, it orders append-only, carries
# no line-target text, names the pretrim path -- and its wording is distinct from the
# library-failure wording used for a corrupt/missing library.
# ----------------------------------------------------------------------------
SNAPSHOT_FAIL_STR='A pre-trim snapshot could not be taken this run:'
REPO_NOWRITE="$(mkrepo repo-nowrite)"
mkdir -p "$REPO_NOWRITE/.claude"
printf '# Session State\n\n## Critical Fact [KEEP]\nMust survive.\n' \
  > "$REPO_NOWRITE/.claude/session-state.md"
chmod 500 "$REPO_NOWRITE/.claude"
run_hook_sid "$REPO_NOWRITE" "$HOOK" "sess-nowrite"
chmod 700 "$REPO_NOWRITE/.claude"
if [ "$RC" -eq 0 ]; then
  ok "snapshot write failure: hook still exits 0"
else
  bad "snapshot write failure: hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" '<pre-compact-handoff>'; then
  ok "snapshot write failure: a directive is still emitted"
else
  bad "snapshot write failure: a directive is still emitted" "$(cat "$OUT")"
fi
if has "$OUT" "$APPEND_ONLY_STR"; then
  ok "snapshot write failure: the directive orders append-only"
else
  bad "snapshot write failure: the directive orders append-only" "$(cat "$OUT")"
fi
if has "$OUT" "$LINE_TARGET_STR"; then
  bad "snapshot write failure: no line-target string is carried" "found one anyway: $(cat "$OUT")"
else
  ok "snapshot write failure: no line-target string is carried"
fi
if has "$OUT" "$SNAPSHOT_FAIL_STR"; then
  ok "snapshot write failure: the reason names the pre-trim snapshot, not a library"
else
  bad "snapshot write failure: the reason names the pre-trim snapshot, not a library" "$(cat "$OUT")"
fi
if has "$OUT" "$REPO_NOWRITE/.claude/session-state.pretrim.sess-nowrite.md"; then
  ok "snapshot write failure: the reason names the pretrim path"
else
  bad "snapshot write failure: the reason names the pretrim path" "$(cat "$OUT")"
fi
if has "$OUT" "$LIB_WARN_STR"; then
  bad "snapshot write failure: the library-failure wording is NOT reused" "found it anyway: $(cat "$OUT")"
else
  ok "snapshot write failure: the library-failure wording is NOT reused"
fi
if [ ! -f "$REPO_NOWRITE/.claude/session-state.pretrim.sess-nowrite.md" ]; then
  ok "snapshot write failure: no partial snapshot is left behind"
else
  bad "snapshot write failure: no partial snapshot is left behind" "a file was left at the PT path"
fi
if has "$OUT" '=== Handoff '; then
  bad "snapshot write failure: the [KEEP] reinjection envelope is absent" "found one anyway: $(cat "$OUT")"
else
  ok "snapshot write failure: the [KEEP] reinjection envelope is absent"
fi
cp "$OUT" "$TMP/snapfail.out"

# ----------------------------------------------------------------------------
# Distinguishability: the snapshot-failure wording and the library-failure wording must
# never appear in each other's output. Re-run both existing library-failure scratch
# hooks (CORRUPT_HOOK, ABSENT_HOOK -- still in scope from the section above) fresh, so
# this doesn't depend on mutating earlier assertions.
# ----------------------------------------------------------------------------
run_hook "$REPO_KEEP" "$CORRUPT_HOOK"
cp "$OUT" "$TMP/corrupt-lib-recheck.out"
run_hook "$REPO_KEEP" "$ABSENT_HOOK"
cp "$OUT" "$TMP/absent-lib-recheck.out"
if has "$TMP/corrupt-lib-recheck.out" "$SNAPSHOT_FAIL_STR"; then
  bad "corrupt reinject library: the snapshot-failure wording does not leak in" \
    "found it anyway: $(cat "$TMP/corrupt-lib-recheck.out")"
else
  ok "corrupt reinject library: the snapshot-failure wording does not leak in"
fi
if has "$TMP/absent-lib-recheck.out" "$SNAPSHOT_FAIL_STR"; then
  bad "absent reinject library: the snapshot-failure wording does not leak in" \
    "found it anyway: $(cat "$TMP/absent-lib-recheck.out")"
else
  ok "absent reinject library: the snapshot-failure wording does not leak in"
fi

# ----------------------------------------------------------------------------
# Falsifier: prove the assertions above can actually fail. Strip the SNAPSHOT_OK
# conjunct from a scratch COPY of the hook's healthy-directive gate and confirm the
# rewrite directive (with the line-target string) fires against the same
# unwritable-.claude repo that the real hook correctly degraded above.
# ----------------------------------------------------------------------------
SNAP_MUT_DIR="$TMP/scratch-hook-snapmut"
mkdir -p "$SNAP_MUT_DIR/lib"
cp "$HOOK_DIR/lib/handoff-archive.sh" "$SNAP_MUT_DIR/lib/handoff-archive.sh"
cp "$HOOK_DIR/lib/handoff-keep-reinject.sh" "$SNAP_MUT_DIR/lib/handoff-keep-reinject.sh"
sed 's/\[ "\$SNAPSHOT_OK" = true \] \&\& //' "$HOOK" > "$SNAP_MUT_DIR/pre-compact-handoff.sh"
if cmp -s "$SNAP_MUT_DIR/pre-compact-handoff.sh" "$HOOK"; then
  bad "falsifier: the SNAPSHOT_OK guard was found and removed" \
    "sed changed nothing -- the guard text moved, so the falsifier below proves nothing"
else
  ok "falsifier: the SNAPSHOT_OK guard was found and removed"
fi

REPO_SNAPFALSE="$(mkrepo repo-snapfalsify)"
mkdir -p "$REPO_SNAPFALSE/.claude"
printf 'notepad content\n' > "$REPO_SNAPFALSE/.claude/session-state.md"
chmod 500 "$REPO_SNAPFALSE/.claude"
run_hook_sid "$REPO_SNAPFALSE" "$SNAP_MUT_DIR/pre-compact-handoff.sh" "sess-snapfalse"
chmod 700 "$REPO_SNAPFALSE/.claude"
if has "$OUT" "$LINE_TARGET_STR"; then
  ok "falsifier: without the guard the rewrite directive DOES fire with no snapshot behind it"
else
  bad "falsifier: without the guard the rewrite directive DOES fire with no snapshot behind it" \
    "the mutant stayed in append-only mode, so the suppression tests above discriminate nothing"
fi

