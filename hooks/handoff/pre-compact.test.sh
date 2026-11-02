#!/usr/bin/env bash
# pre-compact.test.sh — behaviour tests for hooks/handoff/pre-compact.sh, covering the
# notepad-injection task of docs/features/handoff-trim-safety.md (named, not numbered —
# that card renumbers) and decision D7.
#
# What is under test, in the card's terms:
#   * `.claude/session-state.md` is injected at all — the spec's "adjacent defects" list
#     records that this hook re-injected context.md, current-task.md and current-bug.md
#     and NOT the one file kept current, so a compaction summary was built from a notepad
#     nobody had written to since July;
#   * it is injected FIRST, ahead of context.md, so the freshest state leads the summary
#     rather than trailing three stale files (spec scenario "PreCompact injects the live
#     notepad");
#   * an existing-but-unreadable notepad is NAMED, not silently skipped. Skipping is the
#     total-loss failure this whole card exists to prevent, and `set -euo pipefail` plus a
#     bare `cat` would instead abort the hook and drop all four files;
#   * every pre-existing behaviour still holds: pane-agent short-circuit, the banner, the
#     other three files, their relative order, and rc 0 when none of them exist.
#
# Run: bash hooks/handoff/pre-compact.test.sh
#
# The hook short-circuits on CLAUDE_PANE_AGENT, and this suite may itself be run from a
# pane, so every invocation that expects real work goes through run_hook(), which clears
# that variable. The one test that WANTS the short-circuit sets it explicitly.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HOOK_DIR/pre-compact.sh"

# Physical path, not the one mktemp hands back — on macOS mktemp -d returns the /var
# symlink form while other tools resolve it to /private/var.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
# chmod back before rm -rf: a test below makes the notepad unreadable, and on a
# restrictive umask the trap cannot delete what it cannot read.
cleanup() { chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

pass=0; fail=0
ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

# mkrepo NAME FILE... — a throwaway git repo containing each named .claude/ FILE, whose
# body is a line unique to that file so an ordering error shows up as a content
# difference and not merely a missing label. Prints the repo path.
mkrepo() {
  local name="$1" repo f
  shift
  repo="$TMP/$name"
  mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q )
  for f in "$@"; do
    printf 'BODY-OF-%s\n' "$f" > "$repo/.claude/$f"
  done
  printf '%s' "$repo"
}

# run_hook REPO [HOOKPATH] — runs HOOKPATH (default $HOOK) from inside REPO with a
# PreCompact-shaped payload on stdin. Stdout and stderr land in $OUT / $ERR, rc in $RC.
OUT=""; ERR=""; RC=0
run_hook() {
  local repo="$1" hook="${2:-$HOOK}" payload
  payload='{"hook_event_name":"PreCompact","trigger":"auto"}'
  OUT="$TMP/hook.out"; ERR="$TMP/hook.err"
  ( cd "$repo" && printf '%s' "$payload" \
      | env -u CLAUDE_PANE_AGENT bash "$hook" ) >"$OUT" 2>"$ERR"
  RC=$?
}

has() { grep -qF -- "$2" "$1"; }

# lineno FILE NEEDLE — 1-based line of the first occurrence of NEEDLE, or empty.
lineno() { grep -n -F -m1 -- "$2" "$1" | cut -d: -f1; }

# before FILE A B — true when A first occurs strictly before B. Missing either side is a
# failure, never a pass: a check that reads "in order" because neither string is present
# would go green on a hook that emitted nothing at all.
before() {
  local a b
  a="$(lineno "$1" "$2")"; b="$(lineno "$1" "$3")"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

# ============================================================================
# The headline case: notepad and a stale context.md both present
# ============================================================================
REPO_A="$(mkrepo repo-both session-state.md context.md)"
run_hook "$REPO_A"

if [ "$RC" -eq 0 ]; then
  ok "both files present: hook exits 0"
else
  bad "both files present: hook exits 0" "rc=$RC err=$(cat "$ERR")"
fi

if has "$OUT" "--- session-state.md ---"; then
  ok "the notepad gets its own labelled section"
else
  bad "the notepad gets its own labelled section" "$(cat "$OUT")"
fi

if has "$OUT" "BODY-OF-session-state.md"; then
  ok "the notepad body is emitted, not just its label"
else
  bad "the notepad body is emitted, not just its label" "$(cat "$OUT")"
fi

if before "$OUT" "BODY-OF-session-state.md" "BODY-OF-context.md"; then
  ok "the notepad body precedes the context.md body"
else
  bad "the notepad body precedes the context.md body" "$(cat "$OUT")"
fi

if before "$OUT" "--- session-state.md ---" "--- context.md ---"; then
  ok "the notepad label precedes the context.md label"
else
  bad "the notepad label precedes the context.md label" "$(cat "$OUT")"
fi

if has "$OUT" "=== Handoff Context (re-injecting for compaction) ==="; then
  ok "the pre-existing banner still leads the output"
else
  bad "the pre-existing banner still leads the output" "$(cat "$OUT")"
fi

if before "$OUT" "=== Handoff Context (re-injecting for compaction) ===" \
    "--- session-state.md ---"; then
  ok "the banner comes before the notepad, not after it"
else
  bad "the banner comes before the notepad, not after it" "$(cat "$OUT")"
fi

# ============================================================================
# All four files: the notepad leads and the inherited three keep their order
# ============================================================================
REPO_B="$(mkrepo repo-all session-state.md context.md current-task.md current-bug.md)"
run_hook "$REPO_B"

if before "$OUT" "BODY-OF-session-state.md" "BODY-OF-context.md" \
   && before "$OUT" "BODY-OF-context.md" "BODY-OF-current-task.md" \
   && before "$OUT" "BODY-OF-current-task.md" "BODY-OF-current-bug.md"; then
  ok "all four emit in order: session-state, context, current-task, current-bug"
else
  bad "all four emit in order: session-state, context, current-task, current-bug" \
      "$(cat "$OUT")"
fi

# ============================================================================
# Regression cover for the three files that were already there
# ============================================================================
REPO_C="$(mkrepo repo-no-notepad context.md current-task.md current-bug.md)"
run_hook "$REPO_C"

if [ "$RC" -eq 0 ]; then
  ok "no notepad: hook still exits 0"
else
  bad "no notepad: hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi

if has "$OUT" "BODY-OF-context.md" && has "$OUT" "BODY-OF-current-task.md" \
   && has "$OUT" "BODY-OF-current-bug.md"; then
  ok "no notepad: the other three files are still emitted"
else
  bad "no notepad: the other three files are still emitted" "$(cat "$OUT")"
fi

if has "$OUT" "--- session-state.md ---"; then
  bad "no notepad: no empty notepad section is emitted" "label present with no file"
else
  ok "no notepad: no empty notepad section is emitted"
fi

# ============================================================================
# Notepad only — the common case in a repo that never adopted the other three
# ============================================================================
REPO_D="$(mkrepo repo-notepad-only session-state.md)"
run_hook "$REPO_D"

if [ "$RC" -eq 0 ] && has "$OUT" "BODY-OF-session-state.md"; then
  ok "notepad only: emitted, rc 0"
else
  bad "notepad only: emitted, rc 0" "rc=$RC out=$(cat "$OUT")"
fi

# ============================================================================
# Nothing at all — pre-existing behaviour: the banner, rc 0, no failure
# ============================================================================
REPO_E="$(mkrepo repo-empty)"
run_hook "$REPO_E"

if [ "$RC" -eq 0 ] && has "$OUT" "=== Handoff Context (re-injecting for compaction) ==="; then
  ok "no files at all: banner only, rc 0"
else
  bad "no files at all: banner only, rc 0" "rc=$RC out=$(cat "$OUT")"
fi

# ============================================================================
# An unreadable notepad is named, not silently dropped — and does not abort the
# hook. Under `set -euo pipefail` a bare `cat` on an unreadable file would take
# the other three files down with it.
# ============================================================================
REPO_F="$(mkrepo repo-unreadable session-state.md context.md)"
chmod 000 "$REPO_F/.claude/session-state.md"
run_hook "$REPO_F"

if [ "$RC" -eq 0 ]; then
  ok "unreadable notepad: hook still exits 0"
else
  bad "unreadable notepad: hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi

if has "$OUT" "could not be read"; then
  ok "unreadable notepad: the failure is named in the output"
else
  bad "unreadable notepad: the failure is named in the output" "$(cat "$OUT")"
fi

if has "$OUT" "BODY-OF-context.md"; then
  ok "unreadable notepad: the other files survive it"
else
  bad "unreadable notepad: the other files survive it" "$(cat "$OUT")"
fi

chmod 644 "$REPO_F/.claude/session-state.md"

# ============================================================================
# Pane-agent short-circuit — the one test that wants the early exit
# ============================================================================
REPO_G="$(mkrepo repo-pane session-state.md)"
PANE_OUT="$TMP/pane.out"
( cd "$REPO_G" && printf '%s' '{"hook_event_name":"PreCompact"}' \
    | CLAUDE_PANE_AGENT=1 bash "$HOOK" ) >"$PANE_OUT" 2>&1
PANE_RC=$?
if [ "$PANE_RC" -eq 0 ] && [ ! -s "$PANE_OUT" ]; then
  ok "pane agent: exits 0 and prints nothing"
else
  bad "pane agent: exits 0 and prints nothing" "rc=$PANE_RC out=$(cat "$PANE_OUT")"
fi

# ============================================================================
# Falsifiers. Both ordering checks above would go green on output that merely
# CONTAINS the two strings, so each is re-run here against a stub that emits the
# rejected alternative — the pre-change order, notepad last. The stub is written
# here rather than derived from the hook, so it keeps constructing its case after
# the implementation lands (a mutation built by editing the live file stops
# discriminating the moment that file changes).
# ============================================================================
STUB="$TMP/stub-old-order.sh"
cat > "$STUB" <<'STUB_EOF'
#!/bin/bash
set -euo pipefail
[ -n "${CLAUDE_PANE_AGENT:-}" ] && exit 0
cd "$(git rev-parse --show-toplevel)"
echo ""
echo "=== Handoff Context (re-injecting for compaction) ==="
if [ -f ".claude/context.md" ]; then
    echo ""
    echo "--- context.md ---"
    cat ".claude/context.md"
fi
if [ -f ".claude/session-state.md" ]; then
    echo ""
    echo "--- session-state.md ---"
    cat ".claude/session-state.md"
fi
STUB_EOF
run_hook "$REPO_A" "$STUB"

if before "$OUT" "BODY-OF-session-state.md" "BODY-OF-context.md"; then
  bad "falsifier: the body-order check rejects notepad-last output" \
      "the check passed on the rejected order"
else
  ok "falsifier: the body-order check rejects notepad-last output"
fi

if before "$OUT" "--- session-state.md ---" "--- context.md ---"; then
  bad "falsifier: the label-order check rejects notepad-last output" \
      "the check passed on the rejected order"
else
  ok "falsifier: the label-order check rejects notepad-last output"
fi

# And a stub that emits nothing must not read as "in order" — the missing-side
# guard in before(), which is the difference between an ordering check and a
# check that two greps both failed.
EMPTY_STUB="$TMP/stub-silent.sh"
printf '#!/bin/bash\nexit 0\n' > "$EMPTY_STUB"
run_hook "$REPO_A" "$EMPTY_STUB"
if before "$OUT" "BODY-OF-session-state.md" "BODY-OF-context.md"; then
  bad "falsifier: silent output is not treated as correctly ordered" "empty output passed"
else
  ok "falsifier: silent output is not treated as correctly ordered"
fi

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
