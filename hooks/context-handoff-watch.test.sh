#!/usr/bin/env bash
# context-handoff-watch.test.sh — synthetic transcripts through the watcher.
# Run: bash hooks/context-handoff-watch.test.sh
# Assertions are single-quoted strings eval'd later by chk(), so the vars they
# reference (and `out`, read only inside those strings) are deliberately not
# expanded here — suppress the resulting false positives file-wide.
# shellcheck disable=SC2016,SC2034
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1
HOOK="$(cd "$(dirname "$0")" && pwd)/context-handoff-watch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PANE_STATE_DIR="$TMP/state"
export PANE_DISPATCH="$TMP/dispatch-stub.sh"
mkdir -p "$PANE_STATE_DIR"
# Isolate HOME so settings.json fallback always reads 75k (no settings file in $TMP).
export HOME="$TMP"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" >> "%s/dispatch-calls"\n' "$TMP" > "$PANE_DISPATCH"
chmod 700 "$PANE_DISPATCH"
unset CLAUDE_PANE_AGENT
unset HANDOFF_PANE_MODE

transcript() { # $1 path, $2 input, $3 cache_creation, $4 cache_read, [$5 model] — plus noise
  local model_field=""
  [ -n "${5:-}" ] && model_field=$(printf '"model":"%s",' "$5")
  {
    printf '{"type":"user","message":{"content":"hi"}}\n'
    printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":1,"cache_read_input_tokens":1,"output_tokens":5}}}\n'
    printf '{"type":"assistant","message":{%s"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":9}}}\n' "$model_field" "$2" "$3" "$4"
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

# --- Model-aware thresholds ---------------------------------------------------
# The live model comes from the transcript's last assistant .message.model. The
# PostToolUse payload carries NO .model key — verified against a captured live
# payload, whose only keys are: cwd, duration_ms, effort, hook_event_name,
# permission_mode, prompt_id, session_id, tool_input, tool_name, tool_response,
# tool_use_id, transcript_path. settings.json .model is the fallback.

# Sonnet threshold is 100k: 76k clears the old 75k fallback but must NOT fire.
transcript "$TMP/t-sonnet-low.jsonl" 76000 0 0 "claude-sonnet-5"
out=$(printf '%s' "$(payload s-sonnet-low "$TMP/t-sonnet-low.jsonl")" | bash "$HOOK")
chk "sonnet 76k (< 100k): silent"  '[ -z "$out" ]'
chk "sonnet 76k (< 100k): no flag" '[ ! -f "$PANE_STATE_DIR/handoff-fired-s-sonnet-low" ]'

transcript "$TMP/t-sonnet-at.jsonl" 40000 30000 30000 "claude-sonnet-5"  # = 100000
out=$(printf '%s' "$(payload s-sonnet-at "$TMP/t-sonnet-at.jsonl")" | bash "$HOOK")
chk "sonnet at 100k: flag written"      '[ -f "$PANE_STATE_DIR/handoff-fired-s-sonnet-at" ]'
chk "sonnet at 100k: threshold in text" 'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"100000\")" >/dev/null'

# Opus threshold is 130k: 101k clears the Sonnet mark but must NOT fire.
transcript "$TMP/t-opus-low.jsonl" 101000 0 0 "claude-opus-5"
out=$(printf '%s' "$(payload s-opus-low "$TMP/t-opus-low.jsonl")" | bash "$HOOK")
chk "opus 101k (< 130k): silent"  '[ -z "$out" ]'
chk "opus 101k (< 130k): no flag" '[ ! -f "$PANE_STATE_DIR/handoff-fired-s-opus-low" ]'

transcript "$TMP/t-opus-at.jsonl" 50000 40000 40000 "claude-opus-5"  # = 130000
out=$(printf '%s' "$(payload s-opus-at "$TMP/t-opus-at.jsonl")" | bash "$HOOK")
chk "opus at 130k: flag written"      '[ -f "$PANE_STATE_DIR/handoff-fired-s-opus-at" ]'
chk "opus at 130k: threshold in text" 'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"130000\")" >/dev/null'

# The 1M-context suffix must not defeat the match.
transcript "$TMP/t-opus1m.jsonl" 50000 40000 40000 "claude-opus-5[1m]"
out=$(printf '%s' "$(payload s-opus1m "$TMP/t-opus1m.jsonl")" | bash "$HOOK")
chk "opus[1m] at 130k: flag written" '[ -f "$PANE_STATE_DIR/handoff-fired-s-opus1m" ]'

# Fable also gets 130k.
transcript "$TMP/t-fable-at.jsonl" 50000 40000 40000 "claude-fable-5"
out=$(printf '%s' "$(payload s-fable-at "$TMP/t-fable-at.jsonl")" | bash "$HOOK")
chk "fable at 130k: flag written" '[ -f "$PANE_STATE_DIR/handoff-fired-s-fable-at" ]'

# A 200k-window Opus now gets a nudge that can actually fire. Under the old 200k
# threshold the fill had to reach the whole window, which auto-compact prevents,
# so the hook was silent exactly where it was needed. 130k is reachable, and the
# hook carries no window cap, so this one number covers every Opus window.
transcript "$TMP/t-opus-reachable.jsonl" 130000 0 0 "claude-opus-5"
out=$(printf '%s' "$(payload s-opus-reach "$TMP/t-opus-reachable.jsonl")" | bash "$HOOK")
chk "opus at 130k fires below any 200k wall" '[ -f "$PANE_STATE_DIR/handoff-fired-s-opus-reach" ]'

# An unrecognised model keeps the 75k fallback.
transcript "$TMP/t-haiku.jsonl" 75000 0 0 "claude-haiku-4-5-20251001"
out=$(printf '%s' "$(payload s-haiku "$TMP/t-haiku.jsonl")" | bash "$HOOK")
chk "haiku at 75k: flag written" '[ -f "$PANE_STATE_DIR/handoff-fired-s-haiku" ]'

# settings.json .model is consulted only when the transcript names no model.
SETTINGS_HOME="$TMP/settings-home"
mkdir -p "$SETTINGS_HOME/.claude"
printf '{"model":"opus[1m]"}\n' > "$SETTINGS_HOME/.claude/settings.json"

transcript "$TMP/t-nomodel-low.jsonl" 101000 0 0
out=$(printf '%s' "$(payload s-set-low "$TMP/t-nomodel-low.jsonl")" | HOME="$SETTINGS_HOME" bash "$HOOK")
chk "settings opus, 101k (< 130k): no flag" '[ ! -f "$PANE_STATE_DIR/handoff-fired-s-set-low" ]'

transcript "$TMP/t-nomodel-at.jsonl" 50000 40000 40000
out=$(printf '%s' "$(payload s-set-at "$TMP/t-nomodel-at.jsonl")" | HOME="$SETTINGS_HOME" bash "$HOOK")
chk "settings opus, at 130k: flag written" '[ -f "$PANE_STATE_DIR/handoff-fired-s-set-at" ]'

# Transcript model outranks settings.json: sonnet (100k) fires at 101k where
# the settings-derived opus threshold (130k) would have stayed silent.
transcript "$TMP/t-override.jsonl" 101000 0 0 "claude-sonnet-5"
out=$(printf '%s' "$(payload s-override "$TMP/t-override.jsonl")" | HOME="$SETTINGS_HOME" bash "$HOOK")
chk "transcript sonnet outranks settings opus: fires at 101k" '[ -f "$PANE_STATE_DIR/handoff-fired-s-override" ]'

# --- HANDOFF_PANE_MODE toggle --------------------------------------------
# off: dispatch is never invoked, but the checkpoint nudge still fires.
# (dispatch-calls already exists from earlier cases in this suite, so diff
# against a pre-call snapshot rather than asserting the file's absence.)
cp "$TMP/dispatch-calls" "$TMP/calls-before-toggle"
transcript "$TMP/t-toggleoff.jsonl" 80000 0 0
out=$(printf '%s' "$(payload s-toggleoff "$TMP/t-toggleoff.jsonl")" | HANDOFF_PANE_MODE=off bash "$HOOK")
chk "toggle off: flag written"        '[ -f "$PANE_STATE_DIR/handoff-fired-s-toggleoff" ]'
chk "toggle off: dispatch not called" 'cmp -s "$TMP/dispatch-calls" "$TMP/calls-before-toggle"'
chk "toggle off: still mentions checkpoint" 'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"checkpoint\")" >/dev/null'
chk "toggle off: says disabled"       'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"disabled\")" >/dev/null'
chk "toggle off: no pane-ready claim" '! printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"pane is ready\")" >/dev/null'
chk "toggle off: no failure wording"  '! printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"could not be prepared\")" >/dev/null'

# unset (default) and any non-"off" value keep today's behavior: dispatch runs.
transcript "$TMP/t-toggleon.jsonl" 80000 0 0
out=$(printf '%s' "$(payload s-toggleon "$TMP/t-toggleon.jsonl")" | HANDOFF_PANE_MODE=on bash "$HOOK")
chk "toggle on: dispatch called"      'grep -q "^handoff$" "$TMP/dispatch-calls"'
chk "toggle on: pane-ready message"   'printf "%s" "$out" | /usr/bin/jq -e ".hookSpecificOutput.additionalContext | contains(\"pane is ready\")" >/dev/null'

transcript "$TMP/t-togglegarbage.jsonl" 80000 0 0
out=$(printf '%s' "$(payload s-togglegarbage "$TMP/t-togglegarbage.jsonl")" | HANDOFF_PANE_MODE=bogus bash "$HOOK")
chk "toggle mistyped value: dispatch still called" 'grep -q "^handoff$" "$TMP/dispatch-calls"'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
