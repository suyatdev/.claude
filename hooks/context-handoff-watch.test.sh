#!/usr/bin/env bash
# context-handoff-watch.test.sh — synthetic transcripts through the watcher.
# Run: bash hooks/context-handoff-watch.test.sh
# Assertions are single-quoted strings eval'd later by chk(), so the vars they
# reference (and `out`, read only inside those strings) are deliberately not
# expanded here — suppress the resulting false positives file-wide.
# shellcheck disable=SC2016,SC2034
set -u
HOOK="$(cd "$(dirname "$0")" && pwd)/context-handoff-watch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PANE_STATE_DIR="$TMP/state"
export PANE_DISPATCH="$TMP/dispatch-stub.sh"
mkdir -p "$PANE_STATE_DIR"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> "%s/dispatch-calls"\n' "$TMP" > "$PANE_DISPATCH"
chmod 700 "$PANE_DISPATCH"
unset CLAUDE_PANE_AGENT

transcript() { # $1 path, $2 input, $3 cache_creation, $4 cache_read — plus noise lines
  {
    printf '{"type":"user","message":{"content":"hi"}}\n'
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1,"output_tokens":5}}}\n'
    printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":9}}}\n' "$2" "$3" "$4"
  } > "$1"
}
payload() { # $1 session_id, $2 transcript_path
  /usr/bin/jq -nc --arg s "$1" --arg t "$2" --arg c "$TMP" \
    '{hook_event_name:"PostToolUse",session_id:$s,transcript_path:$t,cwd:$c}'
}

pass=0; fail=0
chk() { if eval "$2"; then printf 'ok   — %s\n' "$1"; pass=$((pass+1)); else printf 'FAIL — %s\n' "$1"; fail=$((fail+1)); fi; }

# below threshold -> silent, no flag, no dispatch
transcript "$TMP/t-low.jsonl" 20000 10000 10000
out=$(printf '%s' "$(payload s-low "$TMP/t-low.jsonl")" | bash "$HOOK")
chk "below 75k: silent"        '[ -z "$out" ]'
chk "below 75k: no flag"       '[ ! -f "$PANE_STATE_DIR/handoff-fired-s-low" ]'
chk "below 75k: no dispatch"   '[ ! -f "$TMP/dispatch-calls" ]'

# exactly 75000 -> fires (>=): flag + dispatch handoff + additionalContext JSON
transcript "$TMP/t-at.jsonl" 25000 25000 25000
out=$(printf '%s' "$(payload s-at "$TMP/t-at.jsonl")" | bash "$HOOK")
chk "at 75k: flag written"     '[ -f "$PANE_STATE_DIR/handoff-fired-s-at" ]'
chk "at 75k: dispatch handoff" 'grep -q "^handoff$" "$TMP/dispatch-calls"'
chk "at 75k: cwd passed"       'grep -q "$TMP" "$TMP/dispatch-calls"'
chk "at 75k: additionalContext" 'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"checkpoint\")" >/dev/null'

# second call same session -> dedupe: silent, dispatch NOT called again
cp "$TMP/dispatch-calls" "$TMP/calls-before"
out=$(printf '%s' "$(payload s-at "$TMP/t-at.jsonl")" | bash "$HOOK")
chk "refire: silent"           '[ -z "$out" ]'
chk "refire: no new dispatch"  'cmp -s "$TMP/dispatch-calls" "$TMP/calls-before"'

# fired-flag-first ordering (obs r2 advisory 1): with the flag present the
# transcript must not even be opened — an unreadable transcript still exits 0.
transcript "$TMP/t-locked.jsonl" 90000 0 0
chmod 000 "$TMP/t-locked.jsonl"
: > "$PANE_STATE_DIR/handoff-fired-s-locked"
printf '%s' "$(payload s-locked "$TMP/t-locked.jsonl")" | bash "$HOOK" >/dev/null 2>&1
chk "flag-first: exit 0 despite unreadable transcript" '[ $? -eq 0 ]'
chmod 644 "$TMP/t-locked.jsonl"

# pane sessions never fire, even far above threshold
transcript "$TMP/t-pane.jsonl" 90000 0 0
out=$(printf '%s' "$(payload s-pane "$TMP/t-pane.jsonl")" | CLAUDE_PANE_AGENT=1 bash "$HOOK")
chk "pane session: silent"     '[ -z "$out" ] && [ ! -f "$PANE_STATE_DIR/handoff-fired-s-pane" ]'

# malformed / missing input -> silent exit 0
printf 'garbage' | bash "$HOOK" >/dev/null 2>&1
chk "garbage stdin: exit 0"    '[ $? -eq 0 ]'
printf '%s' "$(payload s-x "$TMP/absent.jsonl")" | bash "$HOOK" >/dev/null 2>&1
chk "missing transcript: exit 0" '[ $? -eq 0 ]'

# --- F5 (regression): additionalContext must reflect whether the handoff
# dispatch actually succeeded, not claim a ready pane unconditionally.
# success path (default stub exits 0): the ready message is emitted.
transcript "$TMP/t-f5ok.jsonl" 80000 0 0
out=$(printf '%s' "$(payload s-f5ok "$TMP/t-f5ok.jsonl")" | bash "$HOOK")
chk "F5 success: pane-ready message" 'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"pane is ready\")" >/dev/null'
chk "F5 success: mentions checkpoint"  'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"checkpoint\")" >/dev/null'

# failure path: a dispatcher stub that exits nonzero must NOT claim a ready pane.
FAILDISPATCH="$TMP/dispatch-fail.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAILDISPATCH"; chmod 700 "$FAILDISPATCH"
transcript "$TMP/t-f5fail.jsonl" 80000 0 0
out=$(printf '%s' "$(payload s-f5fail "$TMP/t-f5fail.jsonl")" | PANE_DISPATCH="$FAILDISPATCH" bash "$HOOK")
chk "F5 failure: additionalContext still emitted" 'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext" >/dev/null'
chk "F5 failure: no false pane-ready claim"       '! printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"pane is ready\")" >/dev/null'
chk "F5 failure: says pane could not be prepared" 'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"could not be prepared\")" >/dev/null'
chk "F5 failure: still mentions checkpoint"       'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"checkpoint\")" >/dev/null'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
