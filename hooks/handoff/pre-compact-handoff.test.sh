#!/usr/bin/env bash
# pre-compact-handoff.test.sh — behaviour tests for hooks/handoff/pre-compact-handoff.sh,
# covering task 8 of docs/features/handoff-trim-safety.md ("Rewrite the trim directive in
# both hooks: cutting means filing into the archive, and the protected headings are
# re-injected verbatim"). live-handoff.sh gets the same treatment in a sibling task/file;
# this suite is scoped to pre-compact-handoff.sh only.
#
# This hook had no test suite before this task, so this file also pins its PRE-EXISTING
# behaviour, not only the new part: the CLAUDE_PANE_AGENT short-circuit, the three
# MODE_DIRECTIVE branches (task+bug / bug / task) selected by .claude/current-task.md and
# .claude/current-bug.md, the no-task-no-bug branch, and the line-target string.
#
# What is new, in the card's terms:
#   * the directive names the archive path and the filing rule -- removing a line means
#     filing it first, not deleting it outright;
#   * when the notepad has [KEEP] headings, they are re-injected verbatim inside a
#     tamper-evident, tagged DATA envelope (open tag == close tag);
#   * when a library cannot be loaded, the hook still emits a directive -- it orders
#     APPEND-ONLY instead of a rewrite, names whichever library actually failed to load,
#     and carries no filing rule or line-target text -- a target invites a cut it cannot
#     back up. live-handoff.sh reaches the same append-only instruction by a different
#     route: it suppresses only its TRIM directive and falls back to the append-mode
#     directive it already emits under the cap (docs/decisions/0046);
#   * a missing notepad does not break the hook -- keep_trim_directive already handles
#     that by printing the filing rule alone.
#
# Run: bash hooks/handoff/pre-compact-handoff.test.sh
# The test bodies live in hooks/handoff/pre-compact-handoff.test.d/*.sh, sourced below
# in order; this file keeps only the header, setup/helpers, and the summary/marker tail.
#
# The hook short-circuits on CLAUDE_PANE_AGENT, and this suite may itself run from a pane,
# so every invocation that expects real work goes through run_hook(), which clears that
# variable. The one test that WANTS the short-circuit sets it explicitly.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2034 # only used inside the sourced *.test.d/ part files below,
# which shellcheck does not statically follow without -x
HOOK="$HOOK_DIR/pre-compact-handoff.sh"

# Physical path, not the one mktemp hands back -- on macOS mktemp -d returns the /var
# symlink form while other tools resolve it to /private/var, and a path-string comparison
# of the two forms reads as a mismatch that isn't one.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

pass=0; fail=0
ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

# mkrepo NAME — a throwaway git repo with no .claude directory yet (the hook creates one
# itself). Prints the repo path.
mkrepo() {
  local name="$1" repo
  repo="$TMP/$name"
  mkdir -p "$repo"
  ( cd "$repo" && git init -q )
  printf '%s' "$repo"
}

# run_hook REPO HOOKPATH — runs HOOKPATH from inside REPO with CLAUDE_PANE_AGENT and
# CLAUDE_CODE_SESSION_ID cleared (task 9 added a session-identity fallback chain that
# would otherwise pick up whatever this test session itself exports, making the
# "nosession" default nondeterministic). /dev/null is supplied on stdin to match how a
# real PreCompact invocation would pipe a JSON payload in when the caller has none to
# send. Stdout/stderr land in $OUT/$ERR, rc in $RC.
OUT=""; ERR=""; RC=0
run_hook() {
  local repo="$1" hook="$2"
  OUT="$TMP/hook.out"; ERR="$TMP/hook.err"
  ( cd "$repo" && env -u CLAUDE_PANE_AGENT -u CLAUDE_CODE_SESSION_ID bash "$hook" < /dev/null ) \
    >"$OUT" 2>"$ERR"
  RC=$?
}

# run_hook_sid REPO HOOKPATH SESSION_ID [ENV_SESSION_ID] — like run_hook, but feeds a
# PreCompact-shaped JSON payload on stdin instead of /dev/null, so the session-identity
# tests below can control what the hook sees. SESSION_ID "" omits the field from the
# payload entirely (the payload-absent fallback path). ENV_SESSION_ID sets
# CLAUDE_CODE_SESSION_ID for the run (default: cleared), so the payload -> env var ->
# "nosession" fallback chain can be exercised one link at a time. Mirrors
# live-handoff.test.sh's run_hook, which does the same thing for the UserPromptSubmit
# hook; added as a separate function rather than changing run_hook's signature, so none
# of the pre-existing call sites above need to change.
run_hook_sid() {
  local repo="$1" hook="$2" sid="$3" envsid="${4:-}" payload
  if [ -n "$sid" ]; then
    payload="$(printf '{"hook_event_name":"PreCompact","session_id":"%s","cwd":"%s"}' "$sid" "$repo")"
  else
    payload="$(printf '{"hook_event_name":"PreCompact","cwd":"%s"}' "$repo")"
  fi
  OUT="$TMP/hook.out"; ERR="$TMP/hook.err"
  ( cd "$repo" && printf '%s' "$payload" \
      | env -u CLAUDE_PANE_AGENT CLAUDE_CODE_SESSION_ID="$envsid" bash "$hook" ) \
      >"$OUT" 2>"$ERR"
  # shellcheck disable=SC2034 # only read inside the sourced *.test.d/ part files below
  RC=$?
}

has() { grep -qF -- "$2" "$1"; }

# envelope_wraps FILE FRAGMENT — 0 if FRAGMENT appears on some line strictly between a
# "=== Handoff <tag> (DATA" opener and a "=== End handoff <tag> (end of DATA) ===" closer
# carrying the SAME tag; 1 otherwise (no envelope, mismatched tags, or the fragment isn't
# inside one). Anchored to the actual envelope lines rather than a bare grep -F for the
# fragment text, so an unrelated line elsewhere in the directive can't produce a false ok.
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

# source_test_parts (hooks/handoff/lib/test-parts.sh) fails loudly -- FAIL line, exit 2 --
# on a missing/unreadable/syntax-broken part or a part count mismatch, instead of `source`
# silently skipping forward. See that helper's header and its test suite for why.
source "$HOOK_DIR/lib/test-parts.sh" || exit 2
command -v source_test_parts >/dev/null 2>&1 || {
  printf 'FAIL — source_test_parts not defined after sourcing lib/test-parts.sh\n'
  exit 2
}
source_test_parts "$HOOK_DIR/pre-compact-handoff.test.d" 5

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
