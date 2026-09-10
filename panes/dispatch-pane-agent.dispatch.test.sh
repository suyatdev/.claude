#!/usr/bin/env bash
# dispatch-pane-agent.dispatch.test.sh — happy path, launcher shape, --role/--model validation.
# Run: bash panes/dispatch-pane-agent.dispatch.test.sh
#
# File-wide: the `[ cond ] && ok || bad` harness is safe here — ok()/bad() both
# end in `pass=/fail=` arithmetic assignments that always return 0, so `bad`
# never runs after a passing `ok`. SC2015's "C may run when A is true" caveat
# does not apply.
# shellcheck disable=SC2015
set -u
# shellcheck source=/dev/null
. "$(dirname "$0")/test-lib.sh"
PANES="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$PANES/dispatch-pane-agent.sh"

export PANE_HOME="$PANES"
export PANE_STATE_DIR="$TMP/state"
export PANE_ADAPTERS_DIR="$TMP/adapters"
export PANE_TERMINAL_DETECT="$TMP/detect.sh"
export CLAUDE_CODE_SESSION_ID="test-session-123"

mkdir -p "$PANE_ADAPTERS_DIR"
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"; chmod 700 "$TMP/detect.sh"
# ok-adapter records its args and the role env, and succeeds; bad-adapter fails.
# The single quotes around ${PANE_AGENT_ROLE:-unset} are deliberate: it must reach
# the generated stub UNexpanded so the stub reads the dispatcher's exported value.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/adapter-args"\nprintf "%%s\\n" "${PANE_AGENT_ROLE:-unset}" > "%s/adapter-role"\necho surface:99\n' "$TMP" "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
PROMPT="$TMP/prompt.md"; printf 'judge this\n' > "$PROMPT"

# --- dispatch happy path
# The launcher lookup below is unscoped `find | head -n1`. It is correct today
# only because this is the first dispatch in the file, so exactly one launch.sh
# exists. Splitting the suite reorders execution and would silently break that.
# A marker touched immediately before the dispatch makes this run the only
# newer match, the same guard the handoff section already uses.
touch "$TMP/dispatch-marker"
out=$(bash "$DISPATCH" dispatch observability-judge --prompt-file "$PROMPT" --result-file "$TMP/r.md" --cwd "$TMP" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "dispatch exits 0" || bad "dispatch exits 0" "rc=$rc: $out"
printf '%s' "$out" | grep -q '^RESULT_FILE: ' && ok "prints RESULT_FILE" || bad "prints RESULT_FILE" "$out"
printf '%s' "$out" | grep -q '^PANE_REF: surface:99' && ok "prints adapter ref" || bad "prints adapter ref" "$out"

launcher=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$TMP/dispatch-marker" | head -n 1)
[ -n "$launcher" ] && ok "launcher created" || bad "launcher created"
perms=$(stat -f '%Lp' "$launcher")
[ "$perms" = "700" ] && ok "launcher mode 700" || bad "launcher mode 700" "$perms"
run_dir_perms=$(stat -f '%Lp' "$(dirname "$launcher")")
[ "$run_dir_perms" = "700" ] && ok "run dir mode 700" || bad "run dir mode 700" "$run_dir_perms"
grep -q 'run-pane-agent.sh' "$launcher" && ok "launcher runs runner" || bad "launcher runs runner"
grep -q 'observability-judge' "$launcher" && ok "launcher carries agent type" || bad "launcher carries agent type"
grep -q 'prompt.md' "$launcher" && ok "prompt copied into run dir" || bad "prompt copied into run dir"
title=$(sed -n '2p' "$TMP/adapter-args")
[ "$title" = "observability-judge" ] && ok "bare agent-type title passed" || bad "bare agent-type title passed" "$title"

role_seen=$(cat "$TMP/adapter-role" 2>/dev/null)
[ "$role_seen" = "aux" ] && ok "role defaults to aux" || bad "role defaults to aux" "$role_seen"

# --- --role validation and export
# Test-only plan deviation: the brief's `[ $? -eq 0 ]` trips SC2181 after a
# command substitution; captured into rc first, matching the happy-path idiom above.
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/role1.md" --cwd "$TMP" --role implementer 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "--role implementer accepted" || bad "--role implementer accepted" "rc=$rc: $out"
[ "$(cat "$TMP/adapter-role" 2>/dev/null)" = "implementer" ] && ok "implementer role exported" || bad "implementer role exported"
rm -f "$TMP/adapter-args"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/role2.md" --cwd "$TMP" --role wizard >/dev/null 2>&1
[ $? -eq 64 ] && ok "garbage --role -> usage exit 64" || bad "garbage --role -> usage exit 64"
[ ! -f "$TMP/adapter-args" ] && ok "garbage --role never reaches adapter" || bad "garbage --role never reaches adapter"

# --- validation failures
bash "$DISPATCH" dispatch 'x;rm' --prompt-file "$PROMPT" >/dev/null 2>&1
[ $? -eq 64 ] && ok "bad agent-type rejected" || bad "bad agent-type rejected"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$TMP/absent" >/dev/null 2>&1
[ $? -eq 64 ] && ok "missing prompt rejected" || bad "missing prompt rejected"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --cwd "$TMP/nodir" >/dev/null 2>&1
[ $? -eq 64 ] && ok "bad cwd rejected" || bad "bad cwd rejected"
touch "$TMP/r.md"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/r.md" --cwd "$TMP" >/dev/null 2>&1
[ $? -eq 65 ] && ok "existing result file refused" || bad "existing result file refused"

# --- F1 (regression): the default result path is unique per dispatch.
# Force the scratchpad-default branch by creating a real dir matching
# scratchpad_dir()'s hardcoded /private/tmp/claude-<uid>/*/<sid>/scratchpad glob,
# then dispatch the same agent type twice with no --result-file. Pre-fix, both
# resolve to $agent-$(date +%s).md and collide within one second.
printf '#!/usr/bin/env bash\necho surface:f1\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
F1SID="panetest-f1-$$-$RANDOM"
F1ROOT="/private/tmp/claude-$(id -u)/panetest-$$-$RANDOM"
F1SCRATCH="$F1ROOT/$F1SID/scratchpad"
mkdir -p "$F1SCRATCH"
rf1=$(CLAUDE_CODE_SESSION_ID="$F1SID" bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --cwd "$TMP" 2>/dev/null | sed -n 's/^RESULT_FILE: //p')
rf2=$(CLAUDE_CODE_SESSION_ID="$F1SID" bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --cwd "$TMP" 2>/dev/null | sed -n 's/^RESULT_FILE: //p')
case "$rf1" in "$F1SCRATCH"/pane-results/*) ok "default result lands in scratchpad pane-results" ;; *) bad "default result lands in scratchpad pane-results" "$rf1" ;; esac
{ [ -n "$rf1" ] && [ -n "$rf2" ] && [ "$rf1" != "$rf2" ]; } && ok "same-type default result paths are unique" || bad "same-type default result paths are unique" "rf1=$rf1 rf2=$rf2"
rm -rf "$F1ROOT"

# --- F4 (regression): a relative --result-file is canonicalized to an absolute
# path against the dispatcher's CWD, so dispatcher/runner/wait all name one file.
printf '#!/usr/bin/env bash\necho surface:f4\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
mkdir -p "$TMP/relcwd"
rfrel=$(cd "$TMP/relcwd" && bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file rel-out.md --cwd "$TMP" 2>/dev/null | sed -n 's/^RESULT_FILE: //p')
rfrel_expect="$(cd "$TMP/relcwd" && pwd)/rel-out.md"
{ [ -n "$rfrel" ] && [ "$rfrel" = "$rfrel_expect" ]; } && ok "relative --result-file canonicalized to absolute" || bad "relative --result-file canonicalized to absolute" "got=$rfrel want=$rfrel_expect"

# --- --model passthrough: accepted, forwarded to the launcher, value required.
# Without this the dispatcher cannot honor a model-switch gate at all: the pane
# inherits settings.json (verified: opus[1m]) no matter what tier was chosen.
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/model1.md" --cwd "$TMP" --model claude-sonnet-5 2>&1)
rc=$?
[ "$rc" -eq 0 ] && ok "--model accepted" || bad "--model accepted" "rc=$rc: $out"
grep -rql 'claude-sonnet-5' "$PANE_STATE_DIR/runs" --include=launch.sh >/dev/null 2>&1 \
  && ok "--model reaches the launcher" || bad "--model reaches the launcher"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/model2.md" --cwd "$TMP" --model >/dev/null 2>&1
[ $? -eq 64 ] && ok "--model with no value -> usage exit 64" || bad "--model with no value -> usage exit 64"

# Criterion 3: a shape-invalid --model dies before any pane opens. "a b" fails
# MODEL_RE (embedded space); no run dir may be created for this call.
before_count=$(find "$PANE_STATE_DIR/runs" -name launch.sh | wc -l | tr -d ' ')
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/model3.md" --cwd "$TMP" --model "a b" 2>&1)
rc=$?
after_count=$(find "$PANE_STATE_DIR/runs" -name launch.sh | wc -l | tr -d ' ')
[ "$rc" -ne 0 ] && ok "--model \"a b\" (shape-invalid) -> non-zero exit" \
  || bad "--model \"a b\" (shape-invalid) -> non-zero exit" "rc=$rc: $out"
[ "$before_count" = "$after_count" ] && ok "--model \"a b\" -> no pane opened" \
  || bad "--model \"a b\" -> no pane opened" "before=$before_count after=$after_count"

# Criterion: unflagged dispatch produces a launcher byte-identical in shape to
# pre-flag -- exactly 5 %q-quoted args after run-pane-agent.sh, no trailing ''.
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/model4.md" --cwd "$TMP" 2>&1)
nomodel_launcher=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$PROMPT" -exec grep -l 'model4.md' {} + 2>/dev/null | head -n 1)
if [ -n "$nomodel_launcher" ] && ! grep -q "run-pane-agent.sh.*''" "$nomodel_launcher"; then
  ok "unflagged dispatch: launcher has no trailing empty --model arg"
else
  bad "unflagged dispatch: launcher has no trailing empty --model arg" "$nomodel_launcher"
fi


tl_finish
