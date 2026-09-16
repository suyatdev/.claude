# shellcheck shell=bash
# 40-preexisting-and-task-bug-wording.sh — sourced by ../live-handoff.test.sh — not runnable on its own.
# Covers pre-existing behaviour that must not regress, and Finding A -- the task/bug directive keeps its removal wording on the healthy path but never orders removal on a suppressed path.

# ============================================================================
# Pre-existing behaviour that must not regress
# ============================================================================
REPO_M="$(mkrepo repo-pane 160)"
PANE_OUT="$TMP/pane.out"
( cd "$REPO_M" && printf '{"session_id":"sess-mmm"}' \
    | env CLAUDE_PANE_AGENT=1 bash "$HOOK" ) >"$PANE_OUT" 2>&1
PANE_RC=$?
if [ "$PANE_RC" -eq 0 ] && [ ! -s "$PANE_OUT" ] \
   && [ ! -f "$REPO_M/.claude/session-state.pretrim.sess-mmm.md" ]; then
  ok "a pane agent emits nothing and writes no snapshot"
else
  bad "a pane agent emits nothing and writes no snapshot" \
    "rc=$PANE_RC out=$(cat "$PANE_OUT")"
fi

REPO_N="$TMP/repo-init"
mkdir -p "$REPO_N/.claude"
( cd "$REPO_N" && git init -q )
run_hook "$REPO_N" "$HOOK" "sess-nnn"
if [ -f "$REPO_N/.claude/session-state.md" ] \
   && has "$REPO_N/.claude/session-state.md" "Files touched this session"; then
  ok "a missing notepad is still created from the INIT template"
else
  bad "a missing notepad is still created from the INIT template" "template missing or unmarked"
fi
if [ -f "$REPO_N/.claude/session-state.pretrim.sess-nnn.md" ]; then
  ok "the freshly created notepad is snapshotted on the same turn"
else
  bad "the freshly created notepad is snapshotted on the same turn" \
    ".claude holds: $(ls "$REPO_N/.claude")"
fi

# The task/bug cap table and its extra directive: 160 lines is over the 150-line general
# cap but under the 170-line task cap, so the task file is what decides.
REPO_O="$(mkrepo repo-task 160)"
: > "$REPO_O/.claude/current-task.md"
run_hook "$REPO_O" "$HOOK" "sess-ooo"
if has "$OUT" "has the current task or bug been completed"; then
  ok "the task/bug directive still rides along when current-task.md exists"
else
  bad "the task/bug directive still rides along when current-task.md exists" "$(cat "$OUT")"
fi
if has "$OUT" "It has grown too large"; then
  bad "the task cap still raises the trim threshold to 170 lines" "160 lines trimmed as if the cap were 150"
else
  ok "the task cap still raises the trim threshold to 170 lines"
fi

# ============================================================================
# Finding A (judge round): on the HEALTHY trim path (both SNAPSHOT_OK and
# REINJECT_LIB_OK), the task/bug directive's original removal/deletion wording is
# unchanged — the fix below only touches the suppressed path.
# ============================================================================
REPO_TASKTRIM="$(mkrepo repo-tasktrim 200)"
: > "$REPO_TASKTRIM/.claude/current-task.md"
run_hook "$REPO_TASKTRIM" "$HOOK" "sess-tasktrim"
if has "$OUT" "It has grown too large" \
   && has "$OUT" "remove task-specific details from session-state.md" \
   && has "$OUT" "delete .claude/current-task.md"; then
  ok "healthy trim path: the task/bug directive still orders removal, unchanged wording"
else
  bad "healthy trim path: the task/bug directive still orders removal, unchanged wording" \
    "$(cat "$OUT")"
fi

# ============================================================================
# Finding A: on a SUPPRESSED path (here, the snapshot cannot be written), the task/bug
# directive must not order any removal or deletion — that is exactly the unbacked cut
# ADR 0046 rejected for the trim directive itself, and this directive was ordering it
# right alongside a warning saying "Do NOT ... delete any part of session-state.md". It
# must still surface the finished task and defer the cleanup instead of ordering it.
# ============================================================================
REPO_TASKNOCUT="$(mkrepo repo-tasknocut 200)"
: > "$REPO_TASKNOCUT/.claude/current-task.md"
chmod 500 "$REPO_TASKNOCUT/.claude"
run_hook "$REPO_TASKNOCUT" "$HOOK" "sess-tasknocut"
chmod 700 "$REPO_TASKNOCUT/.claude"
if [ "$RC" -eq 0 ]; then
  ok "suppressed path with a task file: the hook still exits 0"
else
  bad "suppressed path with a task file: the hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" "TRIM SUPPRESSED"; then
  ok "suppressed path with a task file: the snapshot-failure warning still fires"
else
  bad "suppressed path with a task file: the snapshot-failure warning still fires" "$(cat "$OUT")"
fi
if has "$OUT" "has the current task or bug been completed"; then
  ok "suppressed path: the task/bug directive still fires and surfaces the finished task"
else
  bad "suppressed path: the task/bug directive still fires and surfaces the finished task" \
    "$(cat "$OUT")"
fi
TASKBUG_SECTION="$(task_bug_section "$OUT")"
if [ -n "$TASKBUG_SECTION" ]; then
  ok "suppressed path: the task/bug section was actually extracted (non-vacuous check ahead)"
else
  bad "suppressed path: the task/bug section was actually extracted (non-vacuous check ahead)" \
    "extraction found nothing in: $(cat "$OUT")"
fi
if [ -n "$TASKBUG_SECTION" ] && ! printf '%s\n' "$TASKBUG_SECTION" | grep -qiE 'remove|delet'; then
  ok "suppressed path: no removal/deletion verb survives in the task/bug directive"
else
  bad "suppressed path: no removal/deletion verb survives in the task/bug directive" \
    "$TASKBUG_SECTION"
fi
if [ -n "$TASKBUG_SECTION" ] && printf '%s\n' "$TASKBUG_SECTION" | grep -qiE 'later turn|defer'; then
  ok "suppressed path: the directive defers cleanup to a later turn instead of ordering it"
else
  bad "suppressed path: the directive defers cleanup to a later turn instead of ordering it" \
    "$TASKBUG_SECTION"
fi

