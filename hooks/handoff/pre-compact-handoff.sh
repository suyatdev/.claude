#!/bin/bash
# Vendored from https://github.com/Sonovore/claude-code-handoff @ c6cb717 (2026-07-20)
# Pre-Compact Handoff Failsafe
# Fires before context compaction — tells Claude to dump full state to session-state.md
# Detects active task/bug state and tailors the handoff format accordingly.
#
# This is the last-resort mechanism. live-handoff.sh handles the ongoing updates;
# this hook ensures nothing is lost when autocompaction hits.
#
# Install: place in .claude/hooks/ and add to PreCompact in .claude/settings.json
#
# Locally patched by docs/features/handoff-trim-safety.md, task 8: step 2 used to say
# "REWRITE it completely" with no filing rule at all -- exactly how a fact vanishes for
# good, which is the bug this card exists to fix. The directive now embeds the shared
# keep_trim_directive() fragment (hooks/handoff/lib/handoff-keep-reinject.sh): anything
# removed from the notepad must be filed into the archive first, and any [KEEP]-tagged
# heading is re-injected verbatim so the model sees exactly what must survive the rewrite.
#
# Locally patched by docs/features/handoff-trim-safety.md, task 9: this hook ordered a
# REWRITE with no snapshot behind it at all -- the one hook in this card's scope that
# never copied the notepad aside before telling the model to cut from it. It now takes
# the same per-session pre-trim snapshot as live-handoff.sh (snapshot_notepad(), the
# same PRETRIM_FILE/STRIKE_FILE filename contract, the same strike-retention rule) BEFORE
# any directive is emitted, and the REWRITE directive fires only when that snapshot
# succeeded -- not just when the reinject library loaded. A snapshot failure (or a
# snapshot library that cannot be loaded) degrades to the same append-only directive a
# reinject-library failure already used, with its own distinct reason. Unlike
# live-handoff.sh, this hook has no INIT template and never creates the notepad -- a
# repo with no session-state.md yet has nothing to back up, so a missing notepad is
# guarded explicitly and is NOT treated as a snapshot failure.

set -euo pipefail

# Pane agent sessions must not clobber the interactive session's handoff state
# (pane-orchestration spec, error-handling table).
[ -n "${CLAUDE_PANE_AGENT:-}" ] && exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_FILE="$REPO_ROOT/.claude/session-state.md"

mkdir -p "$REPO_ROOT/.claude"

# --- Session identity ---------------------------------------------------------------
# PreCompact hooks receive the payload on stdin, same as UserPromptSubmit. Same
# three-step fallback and the same "nosession" literal as live-handoff.sh and
# hooks/secret-command-guard.sh: a payload with no session_id, or no payload at all,
# still gets a working (if less specific) snapshot rather than none.
JQ_BIN="/usr/bin/jq"
HOOK_PAYLOAD=""
[ -t 0 ] || HOOK_PAYLOAD="$(cat 2>/dev/null || true)"
SESSION_RAW=""
if [ -n "$HOOK_PAYLOAD" ] && [ -x "$JQ_BIN" ]; then
  SESSION_RAW="$(printf '%s' "$HOOK_PAYLOAD" | "$JQ_BIN" -er '.session_id // empty' 2>/dev/null)" \
    || SESSION_RAW=""
fi
[ -n "$SESSION_RAW" ] || SESSION_RAW="${CLAUDE_CODE_SESSION_ID:-}"
[ -n "$SESSION_RAW" ] || SESSION_RAW="nosession"

# The id reaches a filename, so everything outside the portable-filename set becomes an
# underscore -- a payload is untrusted input, and "../../x" must not steer a write out of
# .claude. Real ids are UUID-shaped, so in practice this substitutes nothing. Same rule,
# byte-for-byte, as live-handoff.sh -- these two filenames are a CONTRACT with
# handoff-keep-guard.sh (hooks/handoff/handoff-keep-guard.sh:99-104), which derives the
# identical SESSION_SLUG independently and must land on the same filenames.
SESSION_SLUG="$(printf '%s' "$SESSION_RAW" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
[ -n "$SESSION_SLUG" ] || SESSION_SLUG="nosession"

PRETRIM_FILE="$REPO_ROOT/.claude/session-state.pretrim.${SESSION_SLUG}.md"
STRIKE_FILE="$REPO_ROOT/.claude/session-state.keepguard-strikes.${SESSION_SLUG}"

# Same literal handoff-keep-guard.sh:105 uses for its own archive path.
ARCHIVE_FILE="$REPO_ROOT/.claude/session-state.archive.md"

# keep_trim_directive() lives in the shared reinject library, resolved from THIS file's
# own directory (never $PWD, never `git rev-parse`) so the hook behaves the same whatever
# the caller's cwd.
HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_LIB="$HOOK_DIR/lib/handoff-archive.sh"
REINJECT_LIB="$HOOK_DIR/lib/handoff-keep-reinject.sh"
ARCHIVE_LIB_OK=false
REINJECT_LIB_OK=false
# FAILED_LIB names whichever library actually failed to load, for the degraded directive
# below to cite. It starts at ARCHIVE_LIB (the first one attempted) and only advances to
# REINJECT_LIB once ARCHIVE_LIB has already sourced cleanly -- so a corrupt, missing, or
# unreadable ARCHIVE_LIB is never misreported as a REINJECT_LIB failure. Mirrors how
# live-handoff.sh keeps its two load failures (LIB_OK / REINJECT_LIB_OK) distinguishable.
FAILED_LIB="$ARCHIVE_LIB"
# Measured (not assumed): under `set -e`, sourcing a file with an actual syntax error
# does NOT just make the `.` command return non-zero for the `if` to gate on -- bash
# treats a parse error hit while sourcing as fatal and exits the whole non-interactive
# shell right there, `if`/`&&` guard notwithstanding. `set +e` around the sourcing (and
# `set -e` restored immediately after) is what actually makes "a library that fails to
# parse cannot kill the hook" true; the `if` alone only covers a MISSING/unreadable file
# or a well-formed library that returns non-zero or never defines the function.
set +e
# shellcheck disable=SC1090  # libraries live beside this hook, not user input
if [ -r "$ARCHIVE_LIB" ] && . "$ARCHIVE_LIB"; then
    ARCHIVE_LIB_OK=true
    FAILED_LIB="$REINJECT_LIB"
    if [ -r "$REINJECT_LIB" ] && . "$REINJECT_LIB"; then
        # A library that sources cleanly but whose function never landed (a partial or
        # renamed file) must not be trusted just because `.` returned 0 -- confirm the
        # function itself exists before relying on it.
        declare -f keep_trim_directive >/dev/null 2>&1 && REINJECT_LIB_OK=true
    fi
fi
set -e

# --- Snapshot, before any directive is emitted ----------------------------------------
# Mirrors live-handoff.sh's snapshot gate and its strike-retention rule: a keep-guard
# strike still holding its pre-damage copy must not have that copy overwritten by the
# damaged notepad in front of us; a strike with no snapshot beside it is not that case,
# so it snapshots normally (a deleted PT plus a stale strike file must not leave the
# session permanently unprotected).
#
# One case this hook has that live-handoff.sh does not: a notepad that does not exist
# yet. live-handoff.sh always has one by this point -- it creates STATE_FILE from an
# INIT template above if missing. This hook never creates the notepad; it only reads it
# (via keep_trim_directive/extract_keep_lines), so a fresh repo with no prior turn
# reaches here with nothing to back up. That is not a snapshot FAILURE -- there is
# nothing to protect, so there is nothing this hook failed to protect -- and
# keep_trim_directive already handles a missing notepad on its own (it prints the filing
# rule with no [KEEP] fragment). Treating it as a failure would wrongly force every
# fresh repo's first compaction into append-only mode.
SNAPSHOT_OK=false
SNAPSHOT_REASON=""
if [ ! -f "$STATE_FILE" ]; then
    SNAPSHOT_OK=true
elif [ -f "$STRIKE_FILE" ] && [ -r "$PRETRIM_FILE" ]; then
    SNAPSHOT_OK=true
elif [ "$ARCHIVE_LIB_OK" != true ]; then
    # No SNAPSHOT_REASON assignment here on purpose: it would never be read. This branch
    # exists only to keep SNAPSHOT_OK false and skip the snapshot_notepad call below
    # (undefined when the library failed to load) -- ARCHIVE_LIB_OK false implies
    # REINJECT_LIB_OK false too (REINJECT_LIB is only ever attempted after ARCHIVE_LIB
    # sources cleanly, above), so the DEGRADED_REASON branch further down (same ordering
    # rationale, see its comment) always takes the "library could not be loaded" path in
    # this case and never reads SNAPSHOT_REASON.
    :
elif snapshot_notepad "$STATE_FILE" "$PRETRIM_FILE"; then
    SNAPSHOT_OK=true
else
    SNAPSHOT_REASON="${PRETRIM_FILE} could not be written"
fi

# KEEP_TRIM_FRAGMENT is computed BEFORE the heredoc below, not inside it: a command
# substitution written directly inside a heredoc still runs at heredoc-expansion time,
# still under `set -e`, and a failure there would kill this hook exactly when compaction
# is imminent -- the one moment it must not silently exit non-zero. Computing it into a
# plain variable first means the heredoc only ever does a variable interpolation, which
# cannot fail. Only the healthy (SNAPSHOT_OK and REINJECT_LIB_OK) branch needs this -- the
# fallback branch below has no fragment to compute, because it orders no rewrite at all.
if [ "$SNAPSHOT_OK" = true ] && [ "$REINJECT_LIB_OK" = true ]; then
    KEEP_TRIM_FRAGMENT="$(keep_trim_directive "$STATE_FILE" "$ARCHIVE_FILE")"
fi

# Detect current work mode
HAS_TASK=false
HAS_BUG=false
[ -f "$REPO_ROOT/.claude/current-task.md" ] && HAS_TASK=true
[ -f "$REPO_ROOT/.claude/current-bug.md" ] && HAS_BUG=true

# Determine handoff type directive based on detected state
if [ "$HAS_BUG" = true ] && [ "$HAS_TASK" = true ]; then
    MODE_DIRECTIVE="
DETECTED STATE: Active task AND active bug (task.bug mode).
Before writing session-state.md, use AskUserQuestion to confirm with the user:
  Question: \"Context compaction is imminent. You have an active task and bug. How should I save state?\"
  Options:
  1. Task+Bug — preserve both task and bug investigation details
  2. Task only — bug is resolved, keep task context
  3. General — both are resolved, save general context only

Then write session-state.md accordingly:
- Task+Bug: include task progress, acceptance criteria, bug symptom, hypothesis, investigation table, reproduce steps
- Task only: include task progress, acceptance criteria, completed/remaining items
- General: standard context dump"
elif [ "$HAS_BUG" = true ]; then
    MODE_DIRECTIVE="
DETECTED STATE: Active bug investigation.
Before writing session-state.md, use AskUserQuestion to confirm with the user:
  Question: \"Context compaction is imminent. You have an active bug investigation. Is the bug still open?\"
  Options:
  1. Bug still open — preserve investigation state (symptom, hypothesis, what was tried, reproduce steps)
  2. Bug is fixed — save general context only

Then write session-state.md accordingly:
- Bug open: include symptom, current hypothesis, investigation table (what tried / result), reproduce steps, key file:line locations
- Bug fixed: note the fix, standard context dump"
elif [ "$HAS_TASK" = true ]; then
    MODE_DIRECTIVE="
DETECTED STATE: Active multi-session task.
Before writing session-state.md, use AskUserQuestion to confirm with the user:
  Question: \"Context compaction is imminent. You have an active task. Is it still in progress?\"
  Options:
  1. Task in progress — preserve task tracking state
  2. Task complete — save general context only

Then write session-state.md accordingly:
- In progress: include goal, acceptance criteria, progress %, architecture decisions, completed items, remaining items, key code locations
- Complete: note completion, standard context dump. Delete .claude/current-task.md"
else
    MODE_DIRECTIVE=""
fi

if [ "$SNAPSHOT_OK" = true ] && [ "$REINJECT_LIB_OK" = true ]; then
    cat << DIRECTIVE
<pre-compact-handoff>
CRITICAL: Context compaction is about to happen. You MUST update .claude/session-state.md NOW.
${MODE_DIRECTIVE}

REQUIRED content for session-state.md (adapt format based on mode above):
1. Read the current session-state.md
2. REWRITE it completely with everything needed to continue this work after compaction, but removing anything means filing it first, not deleting it:
${KEEP_TRIM_FRAGMENT}
   Keep in the rewrite:
   - What are we working on and why
   - All decisions made and their rationale
   - Key discoveries, gotchas, blockers
   - Important file:line references
   - What was just completed
   - What needs to happen next
3. This file will be your ONLY memory after compaction. Line targets: general 120-150, task 140-170, bug 160-190 (if needed).
4. After compaction, you MUST read .claude/session-state.md before doing anything else.
</pre-compact-handoff>
DIRECTIVE
else
    # Still emit a directive, but order APPEND-ONLY: either the protected [KEEP] headings
    # could not be listed, or the pre-trim snapshot that would back up a cut could not be
    # taken -- either way nothing can be safely identified as removable this run, and
    # authorising a cut here is exactly the promise this card exists to stop making.
    # Withholding this directive entirely would be wrong HERE: compaction is imminent and
    # this hook fires once, so suppressing it would forfeit the whole notepad rather than
    # defer a cut. live-handoff.sh can afford to suppress its OWN trim directive in the
    # same state -- it still emits its append-mode directive rather than withholding
    # output entirely, and fires again on the very next prompt, so a deferred cut there
    # costs one turn, not the whole notepad.
    #
    # Both hooks therefore end up ordering append-only; they differ only in route, since
    # live-handoff.sh has an under-cap append directive to fall back on and this one does
    # not. Do not harmonise the two branches: this path deliberately carries NO line
    # target, and this hook's only other directive does.
    # Rationale and the measurement:
    # docs/decisions/0046-neither-trim-hook-orders-a-cut-it-cannot-back-up.md
    #
    # The two possible reasons are kept distinguishable (task 9): a library failure
    # (REINJECT_LIB_OK false, which also covers an unloadable ARCHIVE_LIB via the
    # FAILED_LIB mechanism above) keeps its pre-existing wording unchanged; a snapshot
    # that could not be written while both libraries loaded fine gets its own wording
    # naming the pretrim path, so a reader can tell "fix a library" from "fix a
    # write failure" apart. Checked in this order because when ARCHIVE_LIB_OK is false,
    # REINJECT_LIB_OK is false too (REINJECT_LIB is only ever sourced after ARCHIVE_LIB
    # loads cleanly) -- so an unloadable snapshot library always falls into the
    # library-failure branch below, consistent with "Keep the existing FAILED_LIB
    # behaviour for the library cases."
    if [ "$REINJECT_LIB_OK" != true ]; then
        DEGRADED_REASON="The archive-filing helper library (${FAILED_LIB}) could not be loaded here, so the protected [KEEP] heading(s) in the notepad could not be listed -- nothing can be safely identified as removable this run. Fix that library, then let this hook run again."
    else
        DEGRADED_REASON="A pre-trim snapshot could not be taken this run: ${SNAPSHOT_REASON}. Ordering a cut with no backup behind it is exactly the unbacked promise this hook exists to stop making. Fix the write failure (usually an unwritable .claude directory), then let this hook run again."
    fi
    cat << DIRECTIVE
<pre-compact-handoff>
CRITICAL: Context compaction is about to happen. You MUST update .claude/session-state.md NOW.
${MODE_DIRECTIVE}

${DEGRADED_REASON}

REQUIRED action for session-state.md:
1. APPEND ONLY. Do not rewrite, shorten, reorder, or delete any existing part of .claude/session-state.md this run.
2. Add a new, clearly dated section covering everything needed to continue this work after compaction:
   - What are we working on and why
   - All decisions made and their rationale
   - Key discoveries, gotchas, blockers
   - Important file:line references
   - What was just completed
   - What needs to happen next
3. After compaction, you MUST read .claude/session-state.md before doing anything else.
</pre-compact-handoff>
DIRECTIVE
fi

exit 0
