#!/usr/bin/env bash
# memsearch-nudge.test.sh — unit tests for memsearch-nudge.sh.
# Overrides the status file via MEMSEARCH_STATUS; asserts one-line-max output
# and always-exit-0 (a nudge must never block a session).
# Run: bash hooks/memsearch-nudge.test.sh
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/memsearch-nudge.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
run_case() { # $1 desc, $2 want-lines, $3 status-file ("" = unset)
  local desc="$1" want_lines="$2" status_file="$3" out rc lines
  if [ -n "$status_file" ]; then
    out="$(MEMSEARCH_STATUS="$status_file" bash "$HOOK" 2>/dev/null)"
  else
    out="$(MEMSEARCH_STATUS="$TMP/absent.json" bash "$HOOK" 2>/dev/null)"
  fi
  rc=$?
  lines=0; [ -n "$out" ] && lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$lines" -eq "$want_lines" ]; then
    printf 'ok   — %s (%s line(s))\n' "$desc" "$lines"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s lines rc 0, got %s lines rc %s)\n' \
      "$desc" "$want_lines" "$lines" "$rc"; fail=$((fail+1))
  fi
}

run_case "no status file -> silent"        0 ""

printf '{"chunks": 1234, "sources": 50}' > "$TMP/ok.json"
run_case "indexed -> exactly one line"     1 "$TMP/ok.json"

OUT="$(MEMSEARCH_STATUS="$TMP/ok.json" bash "$HOOK")"
case "$OUT" in
  *memsearch*1234*) printf 'ok   — nudge names memsearch + chunk count\n'; pass=$((pass+1));;
  *) printf 'FAIL — nudge content wrong: %s\n' "$OUT"; fail=$((fail+1));;
esac

printf '{"chunks": 0, "sources": 0}' > "$TMP/zero.json"
run_case "zero chunks -> silent"           0 "$TMP/zero.json"

printf 'not json at all' > "$TMP/bad.json"
run_case "malformed status -> silent"      0 "$TMP/bad.json"

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ]
