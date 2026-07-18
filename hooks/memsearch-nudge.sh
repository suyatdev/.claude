#!/usr/bin/env bash
# memsearch-nudge.sh — SessionStart availability nudge (Tier 3: informational).
#
# Prints AT MOST one line: that a memory index exists and how to query it.
# It deliberately does NOT auto-inject chunks — the spec protects the context
# budget, and the agent decides when a task actually needs history. Silent on
# any problem: a nudge must never delay or break a session start.
STATUS="${MEMSEARCH_STATUS:-$HOME/.claude/memory-index/status.json}"
[ -f "$STATUS" ] || exit 0
CHUNKS="$(python3 -c '
import json, sys
try:
    print(int(json.load(open(sys.argv[1])).get("chunks", 0)))
except Exception:
    print(0)
' "$STATUS" 2>/dev/null)" || exit 0
case "$CHUNKS" in (''|*[!0-9]*) exit 0;; esac
[ "$CHUNKS" -gt 0 ] || exit 0
echo "memsearch: $CHUNKS chunks of past-session memory indexed — query with: ~/.claude/memsearch/bin/memsearch query \"<question>\" [--repo R] [--type decision|episodic|doc] [-k 6]"
exit 0
