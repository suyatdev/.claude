#!/usr/bin/env bash
#
# dependency-guard.sh -- ask before a package is installed, and refuse an install that is unpinned
# or has no recent vetting report (Tier 1, PreToolUse, matchers Bash and Edit|Write|NotebookEdit).
#
# Spec: docs/features/dependency-vetting-guard.md ("Hook decisions", "Failure handling (D7)").
# hooks/lib/decide-dependency.py does the work (classifiers + steps 0-3 + log); this wrapper reads
# the payload, calls it, and owns the one thing it cannot: being broken itself.
#
# Decisions: exit 0 with no output = allow; exit 2 with the reason on stderr = deny; exit 0 with the
# `ask` object on stdout = ask Mark. A deny names the command to run (vet-dependency) or the
# spelling to use; an ask is the one-line summary of the vetting record.
#
# D7 -- this guard's OWN failure is an `ask` saying so, never a silent allow and never a blanket
# deny: python3 missing, the decision helper missing or crashing, a lib missing, a classifier
# exception, an unparseable payload. The reason rides in the ask itself, because stderr of an exit-0
# ask is not shown. "Broken -> ask" costs one prompt per call while broken; that noise is the signal.
#
# NOT a security boundary: it reads command text only (Known gaps in the card list what it cannot
# see), and the vetting record is forgeable by the agent. It is a speed bump in front of Mark's
# approval, which is the control.
#
# State: DEPENDENCY_GUARD_STATE_DIR (default <this dir>/state, gitignored) holds vetting/ (records)
# and dependency-guard.log. The variable exists so a test can point at a mktemp -d dir.

set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd -P)"
STATE_DIR="${DEPENDENCY_GUARD_STATE_DIR:-$HOOK_DIR/state}"
DECIDER="$HOOK_DIR/lib/decide-dependency.py"
LOG="$STATE_DIR/dependency-guard.log"

payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi

# The wrapper's own broken report, for when no python helper can speak. $1 is FIXED ASCII text
# (never payload data), so it needs no escaping and cannot forge a log line.
broken_ask() {
  local why="$1" sid="${CLAUDE_CODE_SESSION_ID:-nosession}" suffix=""
  sid="${sid//[^A-Za-z0-9._-]/?}"
  ( umask 077
    mkdir -p "$STATE_DIR" &&
      printf '%s\t%s\tbroken\t-\t-\t-\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sid" "dependency-guard is broken: $why" >> "$LOG"
  ) 2>/dev/null || suffix=" (log write failed)"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"dependency-guard is broken: %s%s"}}\n' "$why" "$suffix"
}

py=$(command -v python3) || py=""
if [ -z "$py" ]; then
  broken_ask "python3 not found"
  exit 0
fi
if [ ! -r "$DECIDER" ]; then
  broken_ask "decide-dependency.py not found"
  exit 0
fi

out=$(printf '%s' "$payload" | "$py" -I "$DECIDER" "$HOOK_DIR" "$STATE_DIR" 2>/dev/null)
status=$?   # read immediately -- anything else here overwrites it

case "$status" in
  0) [ -z "$out" ] || printf '%s\n' "$out"; exit 0 ;;
  2) printf '%s\n' "$out" >&2; exit 2 ;;
  *) broken_ask "decide-dependency.py exited $status"; exit 0 ;;
esac
