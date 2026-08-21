#!/usr/bin/env bash
# memsearch-nudge.test.sh — unit tests for memsearch-nudge.sh.
# Overrides the status file via MEMSEARCH_STATUS; asserts one-line-max output
# and always-exit-0 (a nudge must never block a session).
#
# Every case asserts the EMITTED LINE, not a parsed field. A field nobody reads
# is the defect this whole feature exists to close, so a test that inspects the
# parse rather than the output would be testing the wrong end of it.
#
# Run: bash hooks/memsearch-nudge.test.sh
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK="$(cd "$(dirname "$0")" && pwd)/memsearch-nudge.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0

ok()   { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL — %s\n%s\n' "$1" "$2"; fail=$((fail+1)); }

ts() { # $1 = signed seconds from now -> ISO-8601 UTC, second precision
  python3 -c 'import sys
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) +
       timedelta(seconds=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"
}

hours() { echo $(( $1 * 3600 )); }

status() { # $1 file, $2.. raw JSON members
  local f="$1"; shift
  local body=""
  for m in "$@"; do body="${body:+$body, }$m"; done
  printf '{%s}' "$body" > "$f"
}

# Every emitting case funnels through here: at most one line, always exit 0,
# the wanted substrings present and the unwanted ones absent.
check() { # $1 desc, $2 status file, $3 want-lines, $4 "pat|pat|..", $5 "notpat|.."
  local desc="$1" f="$2" want="$3" wants="$4" nots="$5" out rc lines ok_=1 detail=""
  out="$(MEMSEARCH_STATUS="$f" bash "$HOOK" 2>/dev/null)"; rc=$?
  lines=0; [ -n "$out" ] && lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  [ "$rc" -eq 0 ] || { ok_=0; detail="rc=$rc"; }
  [ "$lines" -eq "$want" ] || { ok_=0; detail="$detail lines=$lines want=$want"; }
  local IFS='|'
  for p in $wants; do
    [ -z "$p" ] && continue
    case "$out" in (*"$p"*) ;; (*) ok_=0; detail="$detail missing:<$p>";; esac
  done
  for p in $nots; do
    [ -z "$p" ] && continue
    case "$out" in (*"$p"*) ok_=0; detail="$detail unwanted:<$p>";; esac
  done
  unset IFS
  if [ "$ok_" -eq 1 ]; then ok "$desc"; else bad "$desc" "  got: $out
  why:$detail"; fi
}

WARN='⚠'
IDXCMD='run ~/.claude/memsearch/bin/memsearch index'
LOG='~/.claude/memory-index/scheduled-index.log'
QUERY='query with:'

# ── The two silent paths (R4) — outside the state table, emit nothing ────────
check "absent status.json -> silent" "$TMP/absent.json" 0 "" ""

status "$TMP/zero.json" '"chunks": 0' '"sources": 0'
check "zero chunks -> silent" "$TMP/zero.json" 0 "" ""

status "$TMP/nochunks.json" '"sources": 50'
check "chunks key absent -> silent" "$TMP/nochunks.json" 0 "" ""

printf 'not json at all' > "$TMP/bad.json"
check "malformed status.json -> silent" "$TMP/bad.json" 0 "" ""

# ── State 1 — in progress ───────────────────────────────────────────────────
status "$TMP/s1.json" '"chunks": 2332' "\"run_started\": \"$(ts -720)\"" \
  "\"last_run\": \"$(ts -$(hours 3))\""
check "1 in progress: names the run, no remediation" "$TMP/s1.json" 1 \
  "in progress|12m ago|2332 chunks|$QUERY" "$WARN|$IDXCMD|$LOG"

# "The first run after upgrade has no last_run yet" — state 1, not state 4.
status "$TMP/s1b.json" '"chunks": 2332' "\"run_started\": \"$(ts -300)\""
check "1 first run after upgrade: in progress, not unknown-age" "$TMP/s1b.json" 1 \
  "in progress|5m ago" "age unknown|$IDXCMD"

# ── State 2 — stuck ─────────────────────────────────────────────────────────
status "$TMP/s2.json" '"chunks": 2332' "\"run_started\": \"$(ts -$(hours 9))\"" \
  "\"last_run\": \"$(ts -$(hours 30))\""
check "2 stuck: flagged, names the log, never invites a second indexer" \
  "$TMP/s2.json" 1 "$WARN|stuck|9h ago|$LOG" "$IDXCMD"

# "A wedged scheduled run surfaces as stuck, not as stale" — last_run is itself
# older than STALE_HOURS, so state 5 would also match; state 2 must win.
status "$TMP/s2b.json" '"chunks": 2332' "\"run_started\": \"$(ts -$(hours 9))\"" \
  "\"last_run\": \"$(ts -$(hours 20))\""
check "2 wedged run: stuck wins over stale" "$TMP/s2b.json" 1 \
  "$WARN|stuck|$LOG" "stale|$IDXCMD"

# ── State 3 — abandoned first run ───────────────────────────────────────────
# Without this state the first-ever run being killed falls through to a bare
# unknown-age line: no marker, no log pointer, and a dead scheduler unreported.
status "$TMP/s3.json" '"chunks": 2332' "\"run_started\": \"$(ts -$(hours 30))\""
check "3 abandoned first run: warns, names the log, not unknown-age" \
  "$TMP/s3.json" 1 "$WARN|first index run never completed|1d ago|$LOG" \
  "age unknown|in progress|$IDXCMD"

# ── State 4 — unknown age ───────────────────────────────────────────────────
status "$TMP/s4.json" '"chunks": 2332' '"sources": 50'
check "4 last_run absent: unknown age, chunks still reported" "$TMP/s4.json" 1 \
  "2332 chunks|age unknown|$QUERY" "$WARN|$IDXCMD"

status "$TMP/s4b.json" '"chunks": 2332' "\"last_run\": \"$(ts $(hours 2))\""
check "4 future last_run: unknown age, never fresh" "$TMP/s4b.json" 1 \
  "age unknown" "last run|$WARN"

status "$TMP/s4c.json" '"chunks": 2332' '"last_run": "not-a-timestamp"'
check "4 unparseable last_run: unknown age" "$TMP/s4c.json" 1 "age unknown" ""

# ── State 5 — stale ─────────────────────────────────────────────────────────
status "$TMP/s5.json" '"chunks": 2332' "\"last_run\": \"$(ts -$(hours 456))\"" \
  '"last_run_errors": 0'
check "5 stale: marker, age, and the index command" "$TMP/s5.json" 1 \
  "$WARN|stale|2332 chunks|19d ago|$IDXCMD" ""

# The threshold itself counts as stale; one minute under it does not.
status "$TMP/s5b.json" '"chunks": 2332' "\"last_run\": \"$(ts -$(hours 8))\"" \
  '"last_run_errors": 0'
check "5 exactly STALE_HOURS is stale" "$TMP/s5b.json" 1 "$WARN|stale|$IDXCMD" ""

status "$TMP/s8c.json" '"chunks": 2332' "\"last_run\": \"$(ts -28740)\"" \
  '"last_run_errors": 0'
check "8 at 7h59m it is still fresh" "$TMP/s8c.json" 1 \
  "last run 7h ago|$QUERY" "$WARN|stale|$IDXCMD"

# "A stuck marker decays rather than hiding a dead scheduler": past
# RUN_ABANDON_HOURS the in-progress claim stops being believed and a prior
# last_run makes the fall-through state 5, whose remediation actually works.
status "$TMP/s5c.json" '"chunks": 2332' "\"run_started\": \"$(ts -$(hours 30))\"" \
  "\"last_run\": \"$(ts -$(hours 40))\"" '"last_run_errors": 0'
check "5 decay: stale, not stuck, once the claim is too old to believe" \
  "$TMP/s5c.json" 1 "$WARN|stale|$IDXCMD" "stuck|in progress"

# ── State 6 — error count unreadable (unknown is not zero) ──────────────────
status "$TMP/s6.json" '"chunks": 2332' "\"last_run\": \"$(ts -$(hours 2))\""
check "6 errors absent: age reported, cleanliness withheld" "$TMP/s6.json" 1 \
  "$WARN|last run 2h ago|error count unreadable|$LOG" "$IDXCMD"

status "$TMP/s6b.json" '"chunks": 2332' "\"last_run\": \"$(ts -$(hours 2))\"" \
  '"last_run_errors": "many"'
check "6 non-integer errors: unreadable, not fresh" "$TMP/s6b.json" 1 \
  "$WARN|error count unreadable" ""

status "$TMP/s6c.json" '"chunks": 2332' "\"last_run\": \"$(ts -$(hours 2))\"" \
  '"last_run_errors": -1'
check "6 negative errors: unreadable" "$TMP/s6c.json" 1 \
  "$WARN|error count unreadable" ""

# ── State 7 — degraded ──────────────────────────────────────────────────────
status "$TMP/s7.json" '"chunks": 2332' "\"last_run\": \"$(ts -$(hours 2))\"" \
  '"last_run_errors": 47'
check "7 degraded: names the count, points at the log not the indexer" \
  "$TMP/s7.json" 1 "$WARN|47 errors|last run 2h ago|$LOG" "$IDXCMD"

# ── State 8 — fresh ─────────────────────────────────────────────────────────
status "$TMP/s8.json" '"chunks": 2332' "\"last_run\": \"$(ts -$(hours 3))\"" \
  '"last_run_errors": 0'
check "8 fresh: age, no marker, no remediation" "$TMP/s8.json" 1 \
  "2332 chunks|last run 3h ago|$QUERY" "$WARN|$IDXCMD|$LOG"

# A successful run that changed nothing: last_indexed is 19 days old, and the
# line must still read fresh — this is the whole point of the two-field split.
status "$TMP/s8b.json" '"chunks": 2332' '"last_indexed": "2026-07-18T09:00:00+00:00"' \
  "\"last_run\": \"$(ts -$(hours 1))\"" '"last_run_errors": 0'
check "8 quiet night: stale content, fresh run" "$TMP/s8b.json" 1 \
  "last run 1h ago" "$WARN|stale|$IDXCMD"

# A future run_started is unusable, never in-progress — otherwise clock skew
# pins the in-progress line forever.
status "$TMP/s8d.json" '"chunks": 2332' "\"run_started\": \"$(ts $(hours 3))\"" \
  "\"last_run\": \"$(ts -$(hours 2))\"" '"last_run_errors": 0'
check "8 future run_started: fresh, not in progress" "$TMP/s8d.json" 1 \
  "last run 2h ago" "in progress|$WARN"

# ── The constants are overridable, and the thresholds actually bind ─────────
out="$(MEMSEARCH_STATUS="$TMP/s8.json" STALE_HOURS=1 bash "$HOOK" 2>/dev/null)"
case "$out" in
  (*stale*) ok "STALE_HOURS override moves the 3h-old run into stale";;
  (*) bad "STALE_HOURS override" "  got: $out";;
esac

out="$(MEMSEARCH_STATUS="$TMP/s1.json" RUN_MAX_HOURS=0 bash "$HOOK" 2>/dev/null)"
case "$out" in
  (*stuck*) ok "RUN_MAX_HOURS override moves the 12m run into stuck";;
  (*) bad "RUN_MAX_HOURS override" "  got: $out";;
esac

out="$(MEMSEARCH_STATUS="$TMP/s3.json" RUN_ABANDON_HOURS=99 bash "$HOOK" 2>/dev/null)"
case "$out" in
  (*stuck*) ok "RUN_ABANDON_HOURS override keeps the 30h run merely stuck";;
  (*) bad "RUN_ABANDON_HOURS override" "  got: $out";;
esac

# ── Registration — an unregistered hook protects nothing ────────────────────
if python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
hits = [g for grp in s.get("hooks", {}).get("SessionStart", [])
        for g in grp.get("hooks", [])
        if "memsearch-nudge.sh" in g.get("command", "")]
raise SystemExit(0 if len(hits) == 1 else 1)' "$ROOT/settings.json"; then
  ok "registered exactly once on SessionStart in settings.json"
else
  bad "registration" "  memsearch-nudge.sh is not registered once on SessionStart"
fi

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
