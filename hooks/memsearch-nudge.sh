#!/usr/bin/env bash
# memsearch-nudge.sh — SessionStart availability + freshness nudge (Tier 3).
#
# Prints AT MOST one line: that a memory index exists, how current it is, and
# how to query it. It deliberately does NOT auto-inject chunks — the spec
# protects the context budget, and the agent decides when a task actually needs
# history. Silent on any problem: a nudge must never delay or break a session
# start, so every path exits 0 and a broken status file emits nothing.
#
# The index once froze for 19 days while this hook went on vouching for it.
# Reporting the RUN's recency — not the content's — is what makes it honest.
#
# Classification is the state table in docs/features/memsearch-freshness.md:
# eight states, first match wins. That table is the single source of truth and
# is deliberately NOT restated here; three consecutive review rounds went stale
# on a second copy of it. This file implements those eight rows and nothing else.
STATUS="${MEMSEARCH_STATUS:-$HOME/.claude/memory-index/status.json}"
[ -f "$STATUS" ] || exit 0

LOG='~/.claude/memory-index/scheduled-index.log'
IDX='~/.claude/memsearch/bin/memsearch index'
HINT='~/.claude/memsearch/bin/memsearch query "<question>" [--repo R] [--type decision|episodic|doc] [-k 6]'

# One interpreter start, one object read — never the memsearch CLI, so a broken
# venv or slow import can never delay a session start. Both stamps come back as
# an age in seconds; one that does not parse, or that lies in the future, comes
# back as "-" and is then treated exactly as absent. An error count that is
# missing, non-integer or negative is "-" too: unknown is not zero.
FIELDS="$(python3 -c '
import json, sys
from datetime import datetime, timezone


def age(v):
    if not isinstance(v, str):
        return "-"
    try:
        t = datetime.fromisoformat(v)
    except ValueError:
        return "-"
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    seconds = int((datetime.now(timezone.utc) - t).total_seconds())
    return "-" if seconds < 0 else str(seconds)


try:
    d = json.load(open(sys.argv[1]))
    chunks = int(d.get("chunks", 0))
except Exception:
    print("0 - - -")
    raise SystemExit(0)
errors = d.get("last_run_errors")
readable = isinstance(errors, int) and not isinstance(errors, bool) and errors >= 0
print(chunks, age(d.get("last_run")), age(d.get("run_started")),
      errors if readable else "-")
' "$STATUS" 2>/dev/null)" || exit 0

read -r CHUNKS LR RS ERRORS <<< "$FIELDS"
case "${CHUNKS:-}" in (''|*[!0-9]*) exit 0;; esac
[ "$CHUNKS" -gt 0 ] || exit 0

# Env overrides exist for the tests; a non-numeric one falls back to the default
# rather than breaking the arithmetic and emitting a mangled line.
num() { case "$1" in (''|*[!0-9]*) printf '%s' "$2";; (*) printf '%s' "$1";; esac; }
STALE_S=$((   $(num "${STALE_HOURS:-}" 8)        * 3600 ))
MAX_S=$((     $(num "${RUN_MAX_HOURS:-}" 6)      * 3600 ))
ABANDON_S=$(( $(num "${RUN_ABANDON_HOURS:-}" 24) * 3600 ))

fmt_age() { # seconds -> Nm under an hour, Nh under a day, else Nd
  if   [ "$1" -lt 3600 ];  then printf '%dm' "$(( $1 / 60 ))"
  elif [ "$1" -lt 86400 ]; then printf '%dh' "$(( $1 / 3600 ))"
  else                          printf '%dd' "$(( $1 / 86400 ))"
  fi
}

# A smaller age means a more recent stamp, so run_started > last_run is RS < LR.
RS_NEWER=0
if [ "$RS" != "-" ] && { [ "$LR" = "-" ] || [ "$RS" -lt "$LR" ]; }; then RS_NEWER=1; fi

STATE=8
if   [ "$RS_NEWER" = 1 ] && [ "$RS" -lt "$MAX_S" ];                     then STATE=1
elif [ "$RS_NEWER" = 1 ] && [ "$RS" -lt "$ABANDON_S" ];                 then STATE=2
elif [ "$LR" = "-" ] && [ "$RS" != "-" ] && [ "$RS" -ge "$ABANDON_S" ]; then STATE=3
elif [ "$LR" = "-" ];                                                   then STATE=4
elif [ "$LR" -ge "$STALE_S" ];                                          then STATE=5
elif [ "$ERRORS" = "-" ];                                               then STATE=6
elif [ "$ERRORS" -gt 0 ];                                               then STATE=7
fi

case "$STATE" in
  1) printf 'memsearch: index run in progress (started %s ago) — %s chunks; query with: %s\n' \
       "$(fmt_age "$RS")" "$CHUNKS" "$HINT" ;;
  2) printf 'memsearch: ⚠ index run stuck (started %s ago) — %s chunks; see %s\n' \
       "$(fmt_age "$RS")" "$CHUNKS" "$LOG" ;;
  3) printf 'memsearch: ⚠ %s chunks — first index run never completed (started %s ago); see %s\n' \
       "$CHUNKS" "$(fmt_age "$RS")" "$LOG" ;;
  4) printf 'memsearch: %s chunks, age unknown — query with: %s\n' \
       "$CHUNKS" "$HINT" ;;
  5) printf 'memsearch: ⚠ stale — %s chunks, last run %s ago; run %s\n' \
       "$CHUNKS" "$(fmt_age "$LR")" "$IDX" ;;
  6) printf 'memsearch: ⚠ %s chunks, last run %s ago (error count unreadable) — see %s\n' \
       "$CHUNKS" "$(fmt_age "$LR")" "$LOG" ;;
  7) printf 'memsearch: ⚠ last run had %s errors — %s chunks, last run %s ago; see %s\n' \
       "$ERRORS" "$CHUNKS" "$(fmt_age "$LR")" "$LOG" ;;
  8) printf 'memsearch: %s chunks, last run %s ago — query with: %s\n' \
       "$CHUNKS" "$(fmt_age "$LR")" "$HINT" ;;
esac
exit 0
