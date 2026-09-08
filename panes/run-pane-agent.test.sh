#!/usr/bin/env bash
# run-pane-agent.test.sh — exercises the result-file contract with a stubbed
# claude binary. Run: bash panes/run-pane-agent.test.sh
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1
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

# 11-12. --model passthrough (optional 5th positional). Present -> the flag reaches
# the CLI so a dispatch can honor a model-switch gate; absent -> no --model at all,
# so the configured default still wins and every existing 4-arg caller is unchanged.
# shellcheck disable=SC2016 # stub body is expanded when the stub runs, not here
make_stub 'printf "%s\n" "$*" > "$PANE_ARGS_OUT"; printf "{\"result\":\"x\"}\n"'
PANE_ARGS_OUT="$TMP/args-model" PANE_CLAUDE_BIN="$TMP/claude-stub" \
  bash "$RUNNER" pane-echo "$PROMPT" "$TMP/r11.md" "$TMP" sonnet >/dev/null 2>&1
if grep -q -- '--model sonnet' "$TMP/args-model"; then
  printf 'ok   — 5th positional passes --model to the CLI\n'; pass=$((pass+1))
else printf 'FAIL — 5th positional passes --model to the CLI (%s)\n' "$(cat "$TMP/args-model" 2>/dev/null)"; fail=$((fail+1)); fi

PANE_ARGS_OUT="$TMP/args-nomodel" PANE_CLAUDE_BIN="$TMP/claude-stub" \
  bash "$RUNNER" pane-echo "$PROMPT" "$TMP/r12.md" "$TMP" >/dev/null 2>&1
if ! grep -q -- '--model' "$TMP/args-nomodel"; then
  printf 'ok   — no 5th positional emits no --model flag\n'; pass=$((pass+1))
else printf 'FAIL — no 5th positional emits no --model flag (%s)\n' "$(cat "$TMP/args-nomodel" 2>/dev/null)"; fail=$((fail+1)); fi

# 13-18. Per-dispatch scratch isolation (docs/features/pane-agent-scratch-isolation.md,
# "Layer 1 — mechanics" changes 3 and 4a). run-pane-agent.sh does not yet derive run_dir
# up front, export TMPDIR at <run_dir>/work, mkdir -p it, or write work-used — every
# assertion below is expected to be RED against today's implementation.

# 13. an in-shape run dir whose work/ child already exists -> TMPDIR exported at it
RUNS13="$TMP/state/runs/1700000000-13-13"; mkdir -p "$RUNS13/work"; cp "$PROMPT" "$RUNS13/prompt.md"
RUNS13_ABS="$(cd "$RUNS13" && pwd)"
# shellcheck disable=SC2016 # stub body is expanded when the stub runs, not here
make_stub 'printf "%s\n" "${TMPDIR:-unset}" > "$PANE_TMPDIR_OUT"; printf "{\"result\":\"x\"}\n"'
PANE_TMPDIR_OUT="$TMP/tmpdir-13" PANE_CLAUDE_BIN="$TMP/claude-stub" \
  bash "$RUNNER" pane-echo "$RUNS13/prompt.md" "$TMP/r13.md" "$TMP" >/dev/null 2>&1
got13="$(cat "$TMP/tmpdir-13" 2>/dev/null)"
if [ "$got13" = "$RUNS13_ABS/work" ]; then
  printf 'ok   — TMPDIR exported at existing run_dir/work\n'; pass=$((pass+1))
else printf 'FAIL — TMPDIR exported at existing run_dir/work (got %s want %s)\n' "$got13" "$RUNS13_ABS/work"; fail=$((fail+1)); fi

# 14. an in-shape run dir whose work/ child is missing -> it is CREATED, not skipped,
# and TMPDIR is still exported at it (the card: falling back to the inherited TMPDIR
# reinstates the shared-scratch collision this feature removes).
RUNS14="$TMP/state/runs/1700000000-14-14"; mkdir -p "$RUNS14"; cp "$PROMPT" "$RUNS14/prompt.md"
RUNS14_ABS="$(cd "$RUNS14" && pwd)"
# shellcheck disable=SC2016 # stub body is expanded when the stub runs, not here
make_stub 'printf "%s\n" "${TMPDIR:-unset}" > "$PANE_TMPDIR_OUT"; printf "{\"result\":\"x\"}\n"'
PANE_TMPDIR_OUT="$TMP/tmpdir-14" PANE_CLAUDE_BIN="$TMP/claude-stub" \
  bash "$RUNNER" pane-echo "$RUNS14/prompt.md" "$TMP/r14.md" "$TMP" >/dev/null 2>&1
got14="$(cat "$TMP/tmpdir-14" 2>/dev/null)"
if [ -d "$RUNS14/work" ] && [ "$got14" = "$RUNS14_ABS/work" ]; then
  printf 'ok   — missing run_dir/work is created and TMPDIR exported at it\n'; pass=$((pass+1))
else printf 'FAIL — missing run_dir/work is created and TMPDIR exported at it (dir=%s got=%s want=%s)\n' \
  "$( [ -d "$RUNS14/work" ] && printf yes || printf no )" "$got14" "$RUNS14_ABS/work"; fail=$((fail+1)); fi

# 15. an out-of-shape prompt path (direct invocation outside */runs/*) leaves TMPDIR
# alone and prints a line containing the word "shared" to the pane; the result file
# is still written.
# shellcheck disable=SC2016 # stub body is expanded when the stub runs, not here
make_stub 'printf "%s\n" "${TMPDIR:-unset}" > "$PANE_TMPDIR_OUT"; printf "{\"result\":\"x\"}\n"'
PANE_TMPDIR_OUT="$TMP/tmpdir-15" PANE_CLAUDE_BIN="$TMP/claude-stub" TMPDIR="/tmp/sentinel-do-not-touch-15" \
  bash "$RUNNER" pane-echo "$PROMPT" "$TMP/r15.md" "$TMP" >"$TMP/out-15" 2>&1
got15="$(cat "$TMP/tmpdir-15" 2>/dev/null)"; last15="$(tail -n 1 "$TMP/r15.md" 2>/dev/null)"
if [ "$got15" = "/tmp/sentinel-do-not-touch-15" ] && grep -q 'shared' "$TMP/out-15" \
   && [ "$last15" = "PANE_RESULT: DONE" ]; then
  printf 'ok   — out-of-shape prompt path leaves TMPDIR alone and warns shared\n'; pass=$((pass+1))
else printf 'FAIL — out-of-shape prompt path leaves TMPDIR alone and warns shared (tmpdir=%s last=%s)\n' \
  "$got15" "$last15"; fail=$((fail+1)); fi

# 16. mkdir -p of the work dir failing also leaves TMPDIR alone and prints the shared
# line; the result file is still written. Forced by pre-placing a regular file at the
# exact work path, so mkdir -p cannot create a directory there.
RUNS16="$TMP/state/runs/1700000000-16-16"; mkdir -p "$RUNS16"; cp "$PROMPT" "$RUNS16/prompt.md"
printf 'blocker\n' > "$RUNS16/work"
# shellcheck disable=SC2016 # stub body is expanded when the stub runs, not here
make_stub 'printf "%s\n" "${TMPDIR:-unset}" > "$PANE_TMPDIR_OUT"; printf "{\"result\":\"x\"}\n"'
PANE_TMPDIR_OUT="$TMP/tmpdir-16" PANE_CLAUDE_BIN="$TMP/claude-stub" TMPDIR="/tmp/sentinel-do-not-touch-16" \
  bash "$RUNNER" pane-echo "$RUNS16/prompt.md" "$TMP/r16.md" "$TMP" >"$TMP/out-16" 2>&1
got16="$(cat "$TMP/tmpdir-16" 2>/dev/null)"; last16="$(tail -n 1 "$TMP/r16.md" 2>/dev/null)"
if [ "$got16" = "/tmp/sentinel-do-not-touch-16" ] && grep -q 'shared' "$TMP/out-16" \
   && [ "$last16" = "PANE_RESULT: DONE" ]; then
  printf 'ok   — mkdir -p failure leaves TMPDIR alone and warns shared\n'; pass=$((pass+1))
else printf 'FAIL — mkdir -p failure leaves TMPDIR alone and warns shared (tmpdir=%s last=%s)\n' \
  "$got16" "$last16"; fail=$((fail+1)); fi

# 17-18. work-used marker (card change 4a): non-empty when the agent wrote a file
# under run_dir/work, empty when it wrote nothing there.
RUNS17="$TMP/state/runs/1700000000-17-17"; mkdir -p "$RUNS17"; cp "$PROMPT" "$RUNS17/prompt.md"
# shellcheck disable=SC2016 # stub body is expanded when the stub runs, not here
make_stub 'printf "x" > "$TMPDIR/touched" 2>/dev/null; printf "{\"result\":\"x\"}\n"'
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$RUNS17/prompt.md" "$TMP/r17.md" "$TMP" >/dev/null 2>&1
if [ -s "$RUNS17/work-used" ]; then
  printf 'ok   — work-used is non-empty after the agent wrote under work/\n'; pass=$((pass+1))
else printf 'FAIL — work-used is non-empty after the agent wrote under work/\n'; fail=$((fail+1)); fi

RUNS18="$TMP/state/runs/1700000000-18-18"; mkdir -p "$RUNS18"; cp "$PROMPT" "$RUNS18/prompt.md"
make_stub 'printf "{\"result\":\"x\"}\n"'
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$RUNS18/prompt.md" "$TMP/r18.md" "$TMP" >/dev/null 2>&1
exists18=no; size18=0
if [ -e "$RUNS18/work-used" ]; then exists18=yes; size18="$(wc -c < "$RUNS18/work-used")"; fi
if [ "$exists18" = yes ] && [ ! -s "$RUNS18/work-used" ]; then
  printf 'ok   — work-used is empty when the agent wrote nothing under work/\n'; pass=$((pass+1))
else printf 'FAIL — work-used is empty when the agent wrote nothing under work/ (exists=%s size=%s)\n' \
  "$exists18" "$size18"; fail=$((fail+1)); fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
