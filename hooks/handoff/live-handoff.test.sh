#!/usr/bin/env bash
# live-handoff.test.sh — behaviour tests for hooks/handoff/live-handoff.sh, covering the
# snapshot step added by the "snapshot on every turn" task of
# docs/features/handoff-trim-safety.md (named, not numbered — that card renumbers).
#
# What is under test, in the card's terms:
#   * a per-session snapshot is written on EVERY turn, not only over the write cap
#     (spec finding C3), so a voluntary rewrite below the cap is still recoverable;
#   * the snapshot filename carries the session id, so two sessions in one repo do not
#     blind each other (spec finding C2);
#   * if the snapshot cannot be written the trim directive is SUPPRESSED whatever the
#     line count, and the append directive carries a warning naming the failure
#     (spec finding O-C, scenario "The snapshot cannot be written");
#   * a snapshot the keep-guard is holding across a strike is not overwritten, so the
#     "already blocked twice on the same PT" scenario is reachable at all;
#   * every pre-existing behaviour of the hook still holds: pane-agent short-circuit,
#     INIT template creation, the task/bug cap table and its extra directive.
#
# Run: bash hooks/handoff/live-handoff.test.sh
# The test bodies live in hooks/handoff/live-handoff.test.d/*.sh, sourced below in
# order; this file keeps only the header, setup/helpers, and the summary/marker tail.
#
# The hook short-circuits on CLAUDE_PANE_AGENT, and this suite may itself be run from a
# pane, so every invocation that expects real work goes through run_hook(), which clears
# that variable. The one test that WANTS the short-circuit sets it explicitly.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2034 # only used inside the sourced *.test.d/ part files below,
# which shellcheck does not statically follow without -x
HOOK="$HOOK_DIR/live-handoff.sh"
# shellcheck disable=SC2034 # only used inside the sourced *.test.d/ part files below
LIB="$HOOK_DIR/lib/handoff-archive.sh"

# Physical path, not the one mktemp hands back — on macOS mktemp -d returns the /var
# symlink form while other tools resolve it to /private/var, and a cmp of two paths that
# differ only by that prefix reads as a failure.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
# chmod back before rm -rf: a test below makes a .claude directory read-only, and the
# trap cannot delete what it cannot enter.
cleanup() { chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

pass=0; fail=0
ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

# mkrepo NAME [LINES] — a throwaway git repo with a .claude/session-state.md of LINES
# lines (default 10). Prints the repo path. Each line is unique so a truncation shows up
# as a content difference, not just a length one.
mkrepo() {
  local name="$1" lines="${2:-10}" repo i
  repo="$TMP/$name"
  mkdir -p "$repo/.claude"
  ( cd "$repo" && git init -q )
  : > "$repo/.claude/session-state.md"
  i=1
  while [ "$i" -le "$lines" ]; do
    printf 'notepad line %d\n' "$i" >> "$repo/.claude/session-state.md"
    i=$((i+1))
  done
  printf '%s' "$repo"
}

# run_hook REPO HOOKPATH SESSION_ID [ENV_SESSION_ID] — runs HOOKPATH from inside REPO with
# a UserPromptSubmit-shaped payload on stdin. SESSION_ID "" omits the field from the
# payload entirely (the fallback path). Stdout and stderr land in $OUT / $ERR, rc in $RC.
OUT=""; ERR=""; RC=0
run_hook() {
  local repo="$1" hook="$2" sid="$3" envsid="${4:-}" payload
  if [ -n "$sid" ]; then
    payload="$(printf '{"hook_event_name":"UserPromptSubmit","session_id":"%s","cwd":"%s"}' "$sid" "$repo")"
  else
    payload="$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s"}' "$repo")"
  fi
  OUT="$TMP/hook.out"; ERR="$TMP/hook.err"
  ( cd "$repo" && printf '%s' "$payload" \
      | env -u CLAUDE_PANE_AGENT CLAUDE_CODE_SESSION_ID="$envsid" bash "$hook" ) \
      >"$OUT" 2>"$ERR"
  # shellcheck disable=SC2034 # only read inside the sourced *.test.d/ part files below
  RC=$?
}

has() { grep -qF -- "$2" "$1"; }

# task_bug_section FILE — prints just the TASK_BUG_DIRECTIVE portion of an emitted
# directive (from its "Also evaluate:" opener up to, but not including, the next
# "⚠️"-prefixed warning line or end of file). Isolating this from the rest of the
# directive matters for Finding A below: SNAPSHOT_WARNING and REINJECT_WARNING legitimately
# contain the words "removed"/"delete" of their own (they order append-only, forbidding
# removal), so a whole-output grep for those verbs would flag warnings that are already
# correct rather than the task/bug directive this finding is actually about.
task_bug_section() {
  awk '
    /^Also evaluate:/ { grab=1 }
    grab && /^⚠️/ { grab=0 }
    grab { print }
  ' "$1"
}

# envelope_wraps FILE FRAGMENT — 0 if FRAGMENT appears on some line strictly between a
# "=== Handoff <tag> (DATA" opener and a "=== End handoff <tag> (end of DATA) ===" closer
# carrying the SAME tag; 1 otherwise (no envelope, mismatched tags, or the fragment isn't
# inside one). Ported from pre-compact-handoff.test.sh's own envelope_wraps helper, which
# the observability judge found is the only one of the three consumer suites that actually
# tests containment rather than "the heading appears somewhere + some tags match somewhere
# else". Duplicated on purpose rather than shared — these suites are independently
# runnable by design — and anchored to the actual envelope lines rather than a bare
# grep -F for the fragment text, so an unrelated line elsewhere in the directive can't
# produce a false ok.
envelope_wraps() {
  local file="$1" frag="$2" open close
  open="$(grep -oE '=== Handoff [0-9a-f]{8} \(DATA' "$file" | head -1 | grep -oE '[0-9a-f]{8}')"
  close="$(grep -oE '=== End handoff [0-9a-f]{8} \(end of DATA\) ===' "$file" | head -1 | grep -oE '[0-9a-f]{8}')"
  [ -n "$open" ] || return 1
  [ "$open" = "$close" ] || return 1
  awk -v open="$open" -v frag="$frag" '
    index($0, "=== Handoff " open " (DATA") { inenv = 1; next }
    index($0, "=== End handoff " open " (end of DATA) ===") { inenv = 0 }
    inenv && index($0, frag) { found = 1 }
    END { exit !found }
  ' "$file"
}

# shellcheck source=hooks/handoff/live-handoff.test.d/10-snapshot-and-keep-envelope.sh
source "$HOOK_DIR/live-handoff.test.d/10-snapshot-and-keep-envelope.sh"
# shellcheck source=hooks/handoff/live-handoff.test.d/20-library-failure-and-suppression.sh
source "$HOOK_DIR/live-handoff.test.d/20-library-failure-and-suppression.sh"
# shellcheck source=hooks/handoff/live-handoff.test.d/30-session-identity-and-strike-survival.sh
source "$HOOK_DIR/live-handoff.test.d/30-session-identity-and-strike-survival.sh"
# shellcheck source=hooks/handoff/live-handoff.test.d/40-preexisting-and-task-bug-wording.sh
source "$HOOK_DIR/live-handoff.test.d/40-preexisting-and-task-bug-wording.sh"

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
