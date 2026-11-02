# shellcheck shell=bash
# 30-session-identity-and-strike-survival.sh — sourced by ../live-handoff.test.sh — not runnable on its own.
# Covers two-sessions-do-not-blind-each-other (C2), the session-id fallback chain, traversal-shaped id sanitization, and a keep-guard-held snapshot surviving the next turn.

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

