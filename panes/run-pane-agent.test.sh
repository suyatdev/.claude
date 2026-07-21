#!/usr/bin/env bash
# run-pane-agent.test.sh — exercises the result-file contract with a stubbed
# claude binary. Run: bash panes/run-pane-agent.test.sh
set -u
RUNNER="$(cd "$(dirname "$0")" && pwd)/run-pane-agent.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PROMPT="$TMP/prompt.md"; printf 'do the thing\n' > "$PROMPT"

make_stub() { # $1 body of the stub script
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$TMP/claude-stub"
  chmod 700 "$TMP/claude-stub"
}

pass=0; fail=0
check() { # $1 desc, $2 want-exit, $3 result-file, $4 want-final-line, $5 want-body-grep
  local desc="$1" want="$2" rf="$3" wantlast="$4" wantbody="$5" got last
  PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$PROMPT" "$rf" "$TMP" >/dev/null 2>&1
  got=$?
  last=$(tail -n 1 "$rf" 2>/dev/null)
  if [ "$got" -ne "$want" ]; then printf 'FAIL — %s (exit want %s got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); return; fi
  if [ "$last" != "$wantlast" ]; then printf 'FAIL — %s (final line: %s)\n' "$desc" "$last"; fail=$((fail+1)); return; fi
  if [ -n "$wantbody" ] && ! grep -qF "$wantbody" "$rf"; then printf 'FAIL — %s (body missing %s)\n' "$desc" "$wantbody"; fail=$((fail+1)); return; fi
  printf 'ok   — %s\n' "$desc"; pass=$((pass+1))
}

# 1. clean envelope -> DONE, body is .result
make_stub 'printf "{\"result\":\"the verdict text\"}\n"'
check "clean run -> DONE + extracted body" 0 "$TMP/r1.md" "PANE_RESULT: DONE" "the verdict text"

# 2. CLI exits non-zero -> FAILED, body = raw stdout + stderr tail
make_stub 'printf "partial out\n"; printf "boom\n" >&2; exit 3'
check "failed run -> FAILED + stderr tail" 1 "$TMP/r2.md" "PANE_RESULT: FAILED" "boom"

# 3. exit 0 but garbage envelope -> FAILED with raw body (fail closed)
make_stub 'printf "not json at all\n"'
check "garbage envelope -> FAILED + raw body" 1 "$TMP/r3.md" "PANE_RESULT: FAILED" "not json at all"

# 4. CLAUDE_PANE_AGENT=1 is exported to the child
# shellcheck disable=SC2016 # stub body is expanded when the stub runs, not here
make_stub 'printf "{\"result\":\"env=%s\"}\n" "${CLAUDE_PANE_AGENT:-unset}"'
check "recursion guard exported" 0 "$TMP/r4.md" "PANE_RESULT: DONE" "env=1"

# 5. no leftover temp files next to the result (atomicity hygiene)
if ls "$TMP"/.pane-result.* >/dev/null 2>&1; then
  printf 'FAIL — temp result files left behind\n'; fail=$((fail+1))
else printf 'ok   — no temp files left behind\n'; pass=$((pass+1)); fi

# 6. stub receives the pinned flags (no --bare; skip-permissions present)
# shellcheck disable=SC2016 # stub body is expanded when the stub runs, not here
make_stub 'printf "%s\n" "$*" > "$PANE_ARGS_OUT"; printf "{\"result\":\"x\"}\n"'
PANE_ARGS_OUT="$TMP/args" PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$PROMPT" "$TMP/r6.md" "$TMP" >/dev/null 2>&1
if grep -q -- '--agent pane-echo' "$TMP/args" && grep -q -- '--output-format json' "$TMP/args" \
   && grep -q -- '--dangerously-skip-permissions' "$TMP/args" && ! grep -q -- '--bare' "$TMP/args"; then
  printf 'ok   — invocation flags per spec\n'; pass=$((pass+1))
else printf 'FAIL — invocation flags wrong: %s\n' "$(cat "$TMP/args")"; fail=$((fail+1)); fi

# 7-10. agent-exit marker (pane-layout v2): written only after a successful
# result write, containing the status; fail_early and non-runs-shaped run dirs
# write no marker.
RUNS="$TMP/state/runs/1700000000-2-2"; mkdir -p "$RUNS"
cp "$PROMPT" "$RUNS/prompt.md"
make_stub 'printf "{\"result\":\"ok\"}\n"'
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$RUNS/prompt.md" "$TMP/r7.md" "$TMP" >/dev/null 2>&1
if [ "$(cat "$RUNS/agent-exit" 2>/dev/null)" = "DONE" ]; then
  printf 'ok   — marker DONE after clean run\n'; pass=$((pass+1))
else printf 'FAIL — marker DONE after clean run\n'; fail=$((fail+1)); fi

RUNS2="$TMP/state/runs/1700000000-3-3"; mkdir -p "$RUNS2"; cp "$PROMPT" "$RUNS2/prompt.md"
make_stub 'exit 3'
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$RUNS2/prompt.md" "$TMP/r8.md" "$TMP" >/dev/null 2>&1
if [ "$(cat "$RUNS2/agent-exit" 2>/dev/null)" = "FAILED" ]; then
  printf 'ok   — marker FAILED after failed run\n'; pass=$((pass+1))
else printf 'FAIL — marker FAILED after failed run\n'; fail=$((fail+1)); fi

RUNS3="$TMP/state/runs/1700000000-4-4"; mkdir -p "$RUNS3"
# fail_early path: prompt file missing entirely
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$RUNS3/prompt.md" "$TMP/r9.md" "$TMP" >/dev/null 2>&1
if [ ! -e "$RUNS3/agent-exit" ]; then
  printf 'ok   — fail_early writes no marker\n'; pass=$((pass+1))
else printf 'FAIL — fail_early writes no marker\n'; fail=$((fail+1)); fi

# prompt outside a runs/ dir (shape guard): no marker anywhere near it
make_stub 'printf "{\"result\":\"ok\"}\n"'
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$PROMPT" "$TMP/r10.md" "$TMP" >/dev/null 2>&1
if [ ! -e "$TMP/agent-exit" ]; then
  printf 'ok   — shape guard: no marker outside runs dirs\n'; pass=$((pass+1))
else printf 'FAIL — shape guard: no marker outside runs dirs\n'; fail=$((fail+1)); fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
