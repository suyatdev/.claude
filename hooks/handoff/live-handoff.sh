#!/bin/bash
# Vendored from https://github.com/Sonovore/claude-code-handoff @ c6cb717 (2026-07-20)
# Locally patched 2026-07-20: INIT template gained the "<!-- Files touched this session -->"
# marker so the PostToolUse tracker's sed target exists (upstream bug: the tracker silently
# no-ops whenever this template wins the file-creation race against proactive-handoff.sh init).
# Live Handoff — UserPromptSubmit hook
# Injects a directive on EVERY user message telling Claude to maintain session-state.md
# This is the primary mechanism for continuous context preservation.
#
# How it works:
#   - Fires before Claude processes each user message
#   - Outputs a <live-handoff> directive into Claude's system context
#   - Claude sees this directive and updates .claude/session-state.md as needed
#   - When session-state.md grows too large, the directive switches to "rewrite" mode
#
# Install: place in .claude/hooks/ and add UserPromptSubmit to .claude/settings.json
#
# Locally patched 2026-09-09 by docs/features/handoff-trim-safety.md: before any directive
# is emitted, the notepad is copied to a per-session snapshot, and the trim directive is
# withheld whenever that copy could not be taken. Rationale, in the card's terms:
#   - the snapshot happens on EVERY turn, not only over the cap (spec finding C3). The
#     directive is a request, not a ceiling: a model can rewrite the notepad below the cap
#     too, and before this the great majority of turns had no copy behind them at all.
#   - the filename carries the session id (spec finding C2). A single shared snapshot let
#     the first session to finish delete it, after which a second session in the same repo
#     found none and checked nothing.
#   - a failed snapshot suppresses the trim (spec finding O-C). Asking for a cut while
#     unable to back it up is exactly the promise this card exists to stop making, so the
#     trim pauses and the append directive says why.
#
# Locally patched 2026-09-12 by task 8 of docs/features/handoff-trim-safety.md: the trim
# directive no longer tells the model to delete lines — it tells it to file them into
# .claude/session-state.archive.md first (hooks/handoff/lib/handoff-keep-reinject.sh,
# keep_trim_directive()), and any [KEEP]-protected heading in the notepad is re-injected
# verbatim, inside a tamper-evident envelope, as something that must survive the rewrite.
# When that library cannot be loaded (or does not define keep_trim_directive), the trim
# directive is suppressed the same way a failed snapshot suppresses it — a separate flag
# and a separate, self-naming warning, since the two failures are independent and the
# reader must be able to tell them apart.
#
# Locally patched 2026-09-12 (same day, follow-up) after finding both library loads below
# claimed a guarantee the code did not provide: "sourced inside the `if` so a parse failure
# cannot kill the hook under `set -e`" was false, measured against this file itself — a
# library that fails to PARSE (not merely a missing or empty one) kills the whole
# non-interactive shell the moment `.` hits the syntax error, `if`/`&&` guard
# notwithstanding, so no directive was emitted at all. Both `.` calls are now wrapped in
# `set +e` / `set -e` (the same fix already carried by pre-compact-handoff.sh, with the
# same measurement noted there); the `if`/`&&` guard on its own only ever covered a
# missing/unreadable file or a well-formed library that returns non-zero or never defines
# what it should.

set -euo pipefail

# Pane agent sessions must not clobber the interactive session's handoff state
# (pane-orchestration spec, error-handling table).
[ -n "${CLAUDE_PANE_AGENT:-}" ] && exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_FILE="$REPO_ROOT/.claude/session-state.md"

# Ensure .claude directory exists
mkdir -p "$REPO_ROOT/.claude"

# --- Session identity ---------------------------------------------------------------
# Hooks receive the id on stdin; a pane-less caller may only have the environment
# variable, and a caller with neither still gets a working (if less specific) snapshot
# rather than none. Same three-step fallback and the same "nosession" literal as
# hooks/secret-command-guard.sh, so the two agree about what to call an unnamed session.
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
# underscore — a payload is untrusted input, and "../../x" must not steer a write out of
# .claude. Real ids are UUID-shaped, so in practice this substitutes nothing.
SESSION_SLUG="$(printf '%s' "$SESSION_RAW" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
[ -n "$SESSION_SLUG" ] || SESSION_SLUG="nosession"

PRETRIM_FILE="$REPO_ROOT/.claude/session-state.pretrim.${SESSION_SLUG}.md"
STRIKE_FILE="$REPO_ROOT/.claude/session-state.keepguard-strikes.${SESSION_SLUG}"
# Same literal handoff-keep-guard.sh:105 uses for its own ARCHIVE_FILE — one archive per
# repo, not per session, since filed lines are meant to be found later regardless of which
# session did the filing.
ARCHIVE_FILE="$REPO_ROOT/.claude/session-state.archive.md"

# snapshot_notepad() lives in the shared library, resolved from THIS file's own directory
# (never $PWD, never `git rev-parse`) so the hook behaves the same whatever the caller cwd.
# Measured (not assumed — see pre-compact-handoff.sh's matching comment, and this card's
# corrupt-library tests): under `set -euo pipefail`, sourcing a file with an actual syntax
# error does NOT just make the `.` command return non-zero for the `if` to gate on — bash
# treats a parse error hit while sourcing as fatal and exits the whole non-interactive
# shell right there, `if`/`&&` guard notwithstanding. `set +e` around the sourcing (and
# `set -e` restored immediately after) is what actually makes "a library that fails to
# parse cannot kill the hook" true; the `if` alone only covers a MISSING/unreadable file or
# a well-formed library that returns non-zero or never defines what it should. An
# unloadable library is handled below as a snapshot failure, which is the same "cannot back
# this up" state as an unwritable disk and must not fall through to a trim.
HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HOOK_DIR/lib/handoff-archive.sh"
LIB_OK=false
set +e
# shellcheck disable=SC1090  # library lives beside this hook, not user input
if [ -r "$LIB" ] && . "$LIB"; then
  LIB_OK=true
fi
set -e

# The reinject library (keep_trim_directive, task 8) depends on extract_keep_lines,
# gen_tag and sanitize_line, all defined in handoff-archive.sh above — so it is only
# sourced when LIB_OK, and after LIB, never before. Loaded the same defensive way:
# resolved from HOOK_DIR, wrapped in the same `set +e` / `set -e` toggle as LIB above so a
# parse failure here cannot kill the hook under `set -e` either (the bare `if`/`&&` guard
# does not intercept a parse error — see the measurement note above LIB). The `declare -f`
# check is deliberate and not redundant with the `.` exit status: a syntactically valid but
# empty file sources with rc 0 while leaving keep_trim_directive undefined, and that must
# still read as "unloadable" here.
REINJECT_LIB="$HOOK_DIR/lib/handoff-keep-reinject.sh"
REINJECT_LIB_OK=false
set +e
# shellcheck disable=SC1090  # library lives beside this hook, not user input
if [ "$LIB_OK" = true ] && [ -r "$REINJECT_LIB" ] && . "$REINJECT_LIB" \
   && declare -f keep_trim_directive >/dev/null 2>&1; then
  REINJECT_LIB_OK=true
fi
set -e

# Check for active task/bug files
HAS_TASK=false
HAS_BUG=false
[ -f "$REPO_ROOT/.claude/current-task.md" ] && HAS_TASK=true
[ -f "$REPO_ROOT/.claude/current-bug.md" ] && HAS_BUG=true

# Line limits vary by mode:
#   General: 120-150 lines
#   Task: 140-170 lines
#   Bug (or task+bug): 160-190 lines
if [ "$HAS_BUG" = true ]; then
    MAX_LINES=190
    TARGET_LINES=160
elif [ "$HAS_TASK" = true ]; then
    MAX_LINES=170
    TARGET_LINES=140
else
    MAX_LINES=150
    TARGET_LINES=120
fi

# Create state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" << 'INIT'
# Session State

Auto-maintained during conversation. Do not delete.

## Decisions & Architecture

## Key Context

## Modified Files
<!-- Files touched this session -->

## Current Focus

## Next Steps
INIT
fi

# --- Snapshot, before any directive is emitted ----------------------------------------
# One case deliberately does NOT refresh the snapshot: a keep-guard strike is outstanding
# and the snapshot it is holding still exists. That snapshot is the pre-damage copy the
# guard blocked on, and the notepad in front of us is the damaged one — overwriting it
# would destroy the only recovery source at exactly the moment it is needed, and would
# make "the guard has already blocked twice on the same PT" unreachable. A strike file
# with no snapshot beside it is not that case: snapshot normally, so a deleted copy plus a
# stale strike file cannot leave the session permanently unprotected.
SNAPSHOT_OK=false
SNAPSHOT_REASON=""
if [ -f "$STRIKE_FILE" ] && [ -r "$PRETRIM_FILE" ]; then
    SNAPSHOT_OK=true
elif [ "$LIB_OK" != true ]; then
    SNAPSHOT_REASON="the snapshot library ${LIB} could not be loaded"
elif snapshot_notepad "$STATE_FILE" "$PRETRIM_FILE"; then
    SNAPSHOT_OK=true
else
    SNAPSHOT_REASON="${PRETRIM_FILE} could not be written"
fi

SNAPSHOT_WARNING=""
if [ "$SNAPSHOT_OK" != true ]; then
    SNAPSHOT_WARNING="
⚠️ TRIM SUPPRESSED — no pre-trim snapshot was taken: ${SNAPSHOT_REASON}.
Append only this turn. Do NOT rewrite, shorten, reorder or delete any part of
.claude/session-state.md: nothing removed while the snapshot is unavailable can be
recovered. Report this to the user, and fix the write failure (usually an unwritable
.claude directory) or copy the file aside by hand before trimming anything."
fi

# Both hooks end up ordering APPEND-ONLY here; they only reach it differently. This one
# suppresses the trim directive and falls back to the append-mode directive it already
# emits under the cap, plus the warning below. pre-compact-handoff.sh has no such fallback
# — its only directive is a rewrite order — so it builds an append-only one, and emits no
# line target on that path because a target invites a cut. Do not harmonise the two
# branches into one: giving that hook this hook's fallback would hand it a line target.
# Rationale, and the measurement: docs/decisions/0046-neither-trim-hook-orders-a-cut-it-cannot-back-up.md
#
# A second, distinct suppression reason (task 8): the snapshot can succeed while the
# reinject library still cannot be loaded — they are different scripts that fail
# independently, and the reader (model and human) must be able to tell which one
# happened. Deliberately its own flag/reason rather than folded into SNAPSHOT_OK/REASON
# above: ordering a cut while unable to state the filing rule or list the protected
# [KEEP] headings is the same unbacked promise the snapshot suppression exists to stop
# making, so it gets the same fail-closed treatment, worded to name itself. Gated on
# SNAPSHOT_OK so it fires only when snapshot failure isn't already the reason we are in
# append mode — the two warnings are otherwise mutually exclusive by construction.
REINJECT_WARNING=""
if [ "$SNAPSHOT_OK" = true ] && [ "$REINJECT_LIB_OK" != true ]; then
    REINJECT_WARNING="
⚠️ TRIM SUPPRESSED — the archive-filing/reinjection library could not be loaded:
${REINJECT_LIB} could not be sourced, or does not define keep_trim_directive.
Append only this turn. Do NOT rewrite, shorten, reorder or delete any part of
.claude/session-state.md: cutting a line requires being able to state where it must be
filed and which [KEEP] headings must survive untouched, and neither can be produced
safely right now. Report this to the user, and check ${REINJECT_LIB} for a syntax error
or a missing file before trimming anything."
fi

# Count current lines
LINE_COUNT=$(wc -l < "$STATE_FILE" | tr -d ' ')

# Build the task/bug completion check directive. TASK_BUG_DIRECTIVE is vendored upstream
# text (see the file header) — but its ORIGINAL wording orders a removal ("remove
# task-specific details ... delete .claude/current-task.md") unconditionally, and that
# text is interpolated into BOTH the trim branch and the append-mode branch below. On a
# suppressed path (SNAPSHOT_OK or REINJECT_LIB_OK false) that collides with the very
# warning telling the model not to remove or delete anything: two contradictory
# instructions in the same directive, and a removal ordered with no filing rule or
# protected-heading list behind it — the exact defect ADR 0046
# (docs/decisions/0046-neither-trim-hook-orders-a-cut-it-cannot-back-up.md) rejected for
# the sibling trim directive. So this local patch branches on the same TRIM_AUTHORIZED
# gate as the trim directive itself: on the healthy path the vendored wording is
# untouched; on a suppressed path the directive still surfaces a finished task/fixed bug
# (that is its job) but defers the cleanup instead of ordering it. A future vendor
# re-sync must not flatten this back to the single unconditional string.
TASK_BUG_DIRECTIVE=""
if [ "$HAS_TASK" = true ] || [ "$HAS_BUG" = true ]; then
    if [ "$SNAPSHOT_OK" = true ] && [ "$REINJECT_LIB_OK" = true ]; then
        TASK_BUG_DIRECTIVE="
Also evaluate: has the current task or bug been completed?
- If a TASK is done: remove task-specific details from session-state.md, delete .claude/current-task.md, and note completion in session-state.md
- If a BUG is fixed: remove bug investigation details from session-state.md, delete .claude/current-bug.md, and note the fix in session-state.md
- If still in progress: keep task/bug context current in session-state.md"
    else
        TASK_BUG_DIRECTIVE="
Also evaluate: has the current task or bug been completed?
- If a TASK is done: note the completion in session-state.md, but keep the task-specific details and .claude/current-task.md exactly as they are this turn — trimming is suppressed right now (see the warning below), so that cleanup waits for a later turn when trimming is allowed again.
- If a BUG is fixed: note the fix in session-state.md, but keep the bug investigation details and .claude/current-bug.md exactly as they are this turn — trimming is suppressed right now (see the warning below), so that cleanup waits for a later turn when trimming is allowed again.
- If still in progress: keep task/bug context current in session-state.md"
    fi
fi

# Trim-directive filing fragment (task 8), computed here as a plain assignment and NOT
# inside the `cat << DIRECTIVE` heredoc below: a command substitution embedded in a
# heredoc still runs under `set -e` at heredoc-expansion time, and a failure inside
# keep_trim_directive's call chain there would kill the hook AFTER the snapshot has
# already been taken but before any directive reached the model at all — worse than the
# ordinary append-mode fallback. Computing it as an assignment keeps any such failure in
# ordinary command-substitution territory, where `|| TRIM_KEEP_DIRECTIVE=""` (belt and
# suspenders alongside keep_trim_directive's own documented rc-0 contract) is what
# decides the fallback, not an uncontrolled heredoc abort. Only computed on the path
# that will actually use it — the same trim/append gate used below.
TRIM_KEEP_DIRECTIVE=""
if [ "$SNAPSHOT_OK" = true ] && [ "$REINJECT_LIB_OK" = true ] && [ "$LINE_COUNT" -gt "$MAX_LINES" ]; then
    TRIM_KEEP_DIRECTIVE="$(keep_trim_directive "$STATE_FILE" "$ARCHIVE_FILE")" || TRIM_KEEP_DIRECTIVE=""
fi

# Always output a directive — Claude sees this every turn. The SNAPSHOT_OK and
# REINJECT_LIB_OK conjuncts are the suppression: with no copy behind it, or with no way to
# state the filing rule and list protected [KEEP] headings, the oversize branch is never
# taken whatever the line count, and the append branch below carries whichever warning
# applies instead.
if [ "$SNAPSHOT_OK" = true ] && [ "$REINJECT_LIB_OK" = true ] && [ "$LINE_COUNT" -gt "$MAX_LINES" ]; then
    cat << DIRECTIVE
<live-handoff>
REQUIRED: Before responding, update .claude/session-state.md:
1. Read the current file
2. It has grown too large. Rewrite it keeping ONLY the most critical information:
   - Active decisions and their rationale
   - Key context that would be lost if early conversation is compressed
   - Current focus and immediate next steps
   - Important file locations and what changed
3. Removing a line does not mean deleting it — it means filing it, per this rule:
${TRIM_KEEP_DIRECTIVE}
4. Target: under ${TARGET_LINES} lines. Keep only what you'd need to continue this work cold; nothing under a protected [KEEP] heading may be removed.
${TASK_BUG_DIRECTIVE}
</live-handoff>
DIRECTIVE
else
    cat << DIRECTIVE
<live-handoff>
REQUIRED: Before responding, check if anything important happened since session-state.md was last updated.
If yes — append to the appropriate section in .claude/session-state.md:
- Decisions made and why
- Architecture or approach changes
- Key discoveries or gotchas
- Important file:line references
- Changes to current focus or next steps
If nothing noteworthy happened (e.g. simple question, no new info), skip the update.
Do NOT rewrite the whole file — just append new items to existing sections.
${TASK_BUG_DIRECTIVE}${SNAPSHOT_WARNING}${REINJECT_WARNING}
</live-handoff>
DIRECTIVE
fi

exit 0
