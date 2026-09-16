# 10-preexisting-behaviour.sh — sourced by ../pre-compact-handoff.test.sh — not runnable on its own.
# Covers pre-existing behaviour: the CLAUDE_PANE_AGENT short-circuit, the no-task/no-bug directive, and the three MODE_DIRECTIVE branches.

# ============================================================================
# Pre-existing behaviour: CLAUDE_PANE_AGENT short-circuit
# ============================================================================
REPO_PANE="$(mkrepo repo-pane)"
PANE_OUT="$TMP/pane.out"; PANE_ERR="$TMP/pane.err"
( cd "$REPO_PANE" && CLAUDE_PANE_AGENT=1 bash "$HOOK" < /dev/null ) >"$PANE_OUT" 2>"$PANE_ERR"
PANE_RC=$?
if [ "$PANE_RC" -eq 0 ]; then
  ok "CLAUDE_PANE_AGENT set: hook exits 0"
else
  bad "CLAUDE_PANE_AGENT set: hook exits 0" "rc=$PANE_RC err=$(cat "$PANE_ERR")"
fi
if [ ! -s "$PANE_OUT" ]; then
  ok "CLAUDE_PANE_AGENT set: no directive is emitted"
else
  bad "CLAUDE_PANE_AGENT set: no directive is emitted" "$(cat "$PANE_OUT")"
fi

# ============================================================================
# Pre-existing behaviour: no task, no bug -> empty MODE_DIRECTIVE, plain directive
# ============================================================================
REPO_NONE="$(mkrepo repo-none)"
run_hook "$REPO_NONE" "$HOOK"
if [ "$RC" -eq 0 ]; then
  ok "no task/bug: hook exits 0"
else
  bad "no task/bug: hook exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" '<pre-compact-handoff>'; then
  ok "no task/bug: directive is still emitted"
else
  bad "no task/bug: directive is still emitted" "$(cat "$OUT")"
fi
if has "$OUT" 'DETECTED STATE'; then
  bad "no task/bug: no DETECTED STATE block" "found one anyway: $(cat "$OUT")"
else
  ok "no task/bug: no DETECTED STATE block"
fi
if has "$OUT" 'Line targets: general 120-150, task 140-170, bug 160-190 (if needed).'; then
  ok "the line-target string is intact"
else
  bad "the line-target string is intact" "$(cat "$OUT")"
fi
if has "$OUT" '4. After compaction, you MUST read .claude/session-state.md before doing anything else.'; then
  ok "the post-compaction read-first instruction is intact"
else
  bad "the post-compaction read-first instruction is intact" "$(cat "$OUT")"
fi

# ============================================================================
# Pre-existing behaviour: the three MODE_DIRECTIVE branches
# ============================================================================
REPO_TASK="$(mkrepo repo-task)"
mkdir -p "$REPO_TASK/.claude"
: > "$REPO_TASK/.claude/current-task.md"
run_hook "$REPO_TASK" "$HOOK"
if has "$OUT" 'DETECTED STATE: Active multi-session task.'; then
  ok "task only: the task MODE_DIRECTIVE fires"
else
  bad "task only: the task MODE_DIRECTIVE fires" "$(cat "$OUT")"
fi

REPO_BUG="$(mkrepo repo-bug)"
mkdir -p "$REPO_BUG/.claude"
: > "$REPO_BUG/.claude/current-bug.md"
run_hook "$REPO_BUG" "$HOOK"
if has "$OUT" 'DETECTED STATE: Active bug investigation.'; then
  ok "bug only: the bug MODE_DIRECTIVE fires"
else
  bad "bug only: the bug MODE_DIRECTIVE fires" "$(cat "$OUT")"
fi

REPO_BOTH="$(mkrepo repo-taskbug)"
mkdir -p "$REPO_BOTH/.claude"
: > "$REPO_BOTH/.claude/current-task.md"
: > "$REPO_BOTH/.claude/current-bug.md"
run_hook "$REPO_BOTH" "$HOOK"
if has "$OUT" 'DETECTED STATE: Active task AND active bug (task.bug mode).'; then
  ok "task+bug: the combined MODE_DIRECTIVE fires"
else
  bad "task+bug: the combined MODE_DIRECTIVE fires" "$(cat "$OUT")"
fi

