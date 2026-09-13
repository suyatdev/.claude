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

set -euo pipefail

# Pane agent sessions must not clobber the interactive session's handoff state
# (pane-orchestration spec, error-handling table).
[ -n "${CLAUDE_PANE_AGENT:-}" ] && exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

mkdir -p "$REPO_ROOT/.claude"

# Same literal handoff-keep-guard.sh:105 uses for its own archive path.
ARCHIVE_FILE="$REPO_ROOT/.claude/session-state.archive.md"

# keep_trim_directive() lives in the shared reinject library, resolved from THIS file's
# own directory (never $PWD, never `git rev-parse`) so the hook behaves the same whatever
# the caller's cwd.
HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_LIB="$HOOK_DIR/lib/handoff-archive.sh"
REINJECT_LIB="$HOOK_DIR/lib/handoff-keep-reinject.sh"
REINJECT_LIB_OK=false
# Measured (not assumed): under `set -e`, sourcing a file with an actual syntax error
# does NOT just make the `.` command return non-zero for the `if` to gate on -- bash
# treats a parse error hit while sourcing as fatal and exits the whole non-interactive
# shell right there, `if`/`&&` guard notwithstanding. `set +e` around the sourcing (and
# `set -e` restored immediately after) is what actually makes "a library that fails to
# parse cannot kill the hook" true; the `if` alone only covers a MISSING/unreadable file
# or a well-formed library that returns non-zero or never defines the function.
set +e
# shellcheck disable=SC1090  # libraries live beside this hook, not user input
if [ -r "$ARCHIVE_LIB" ] && . "$ARCHIVE_LIB" && [ -r "$REINJECT_LIB" ] && . "$REINJECT_LIB"; then
    # A library that sources cleanly but whose function never landed (a partial or
    # renamed file) must not be trusted just because `.` returned 0 -- confirm the
    # function itself exists before relying on it.
    declare -f keep_trim_directive >/dev/null 2>&1 && REINJECT_LIB_OK=true
fi
set -e

# KEEP_TRIM_FRAGMENT is computed BEFORE the heredoc below, not inside it: a command
# substitution written directly inside a heredoc still runs at heredoc-expansion time,
# still under `set -e`, and a failure there would kill this hook exactly when compaction
# is imminent -- the one moment it must not silently exit non-zero. Computing it into a
# plain variable first means the heredoc only ever does a variable interpolation, which
# cannot fail. Only the healthy (REINJECT_LIB_OK) branch needs this -- the fallback branch
# below has no fragment to compute, because it orders no rewrite at all.
if [ "$REINJECT_LIB_OK" = true ]; then
    KEEP_TRIM_FRAGMENT="$(keep_trim_directive "$REPO_ROOT/.claude/session-state.md" "$ARCHIVE_FILE")"
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

if [ "$REINJECT_LIB_OK" = true ]; then
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
    # Still emit a directive, but order APPEND-ONLY: the protected [KEEP] headings could
    # not be listed, so nothing can be safely identified as removable this run, and
    # authorising a cut here is exactly the promise this card exists to stop making.
    # Withholding the directive entirely -- what live-handoff.sh does in the same state --
    # is wrong HERE: compaction is imminent and this hook fires once, so suppressing it
    # would forfeit the whole notepad rather than defer a cut. live-handoff.sh fires again
    # on the very next prompt and can afford to wait.
    #
    # Both hooks therefore end up ordering append-only; they differ only in route, since
    # live-handoff.sh has an under-cap append directive to fall back on and this one does
    # not. Do not harmonise the two branches: this path deliberately carries NO line
    # target, and this hook's only other directive does.
    # Rationale and the measurement:
    # docs/decisions/0046-neither-trim-hook-orders-a-cut-it-cannot-back-up.md
    cat << DIRECTIVE
<pre-compact-handoff>
CRITICAL: Context compaction is about to happen. You MUST update .claude/session-state.md NOW.
${MODE_DIRECTIVE}

The archive-filing helper library (${REINJECT_LIB}) could not be loaded here, so the protected [KEEP] heading(s) in the notepad could not be listed -- nothing can be safely identified as removable this run. Fix that library, then let this hook run again.

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
