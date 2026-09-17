#!/bin/bash
# Vendored from https://github.com/Sonovore/claude-code-handoff @ c6cb717 (2026-07-20)
# PreCompact hook — re-injects handoff context before autocompaction.
#
# When Claude Code hits its context limit, it compacts the conversation.
# This hook outputs the handoff files so they get included in the
# compaction summary, preventing context loss.
#
# Install: symlink into .claude/hooks/ and add to .claude/settings.json
#   (see settings-snippet.json or the README for the full config)
#
# Local change (docs/features/handoff-trim-safety.md, decision D7): session-state.md is
# injected, and injected FIRST. The vendored original sent context.md, current-task.md
# and current-bug.md only — every file except the one the live-handoff hook keeps
# current — so a compaction summary could be built from a notepad months out of date
# while the fresh one sat unread. Order matters as well as presence: the freshest state
# leads the summary rather than trailing three stale files.

set -euo pipefail

# Pane agent sessions must not clobber the interactive session's handoff state
# (pane-orchestration spec, error-handling table).
[ -n "${CLAUDE_PANE_AGENT:-}" ] && exit 0

cd "$(git rev-parse --show-toplevel)"

echo ""
echo "=== Handoff Context (re-injecting for compaction) ==="

# The live notepad, first. Existence and readability are tested separately, and the
# read is judged by cat itself rather than by a -r probe: -r would still let a
# directory or an I/O error abort the hook under `set -euo pipefail` and take the
# three files below down with it. A notepad that cannot be read is NAMED rather than
# skipped — silently dropping the freshest state is the exact total-loss failure this
# card exists to prevent.
if [ -f ".claude/session-state.md" ]; then
    echo ""
    echo "--- session-state.md ---"
    if ! cat ".claude/session-state.md"; then
        echo "(WARNING: session-state.md exists but could not be read — the freshest handoff state is MISSING from this summary. Read the file directly before relying on anything below.)"
    fi
fi

if [ -f ".claude/context.md" ]; then
    echo ""
    echo "--- context.md ---"
    cat ".claude/context.md"
fi

if [ -f ".claude/current-task.md" ]; then
    echo ""
    echo "--- current-task.md ---"
    cat ".claude/current-task.md"
fi

if [ -f ".claude/current-bug.md" ]; then
    echo ""
    echo "--- current-bug.md ---"
    cat ".claude/current-bug.md"
fi
