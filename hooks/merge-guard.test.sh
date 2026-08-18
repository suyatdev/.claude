#!/usr/bin/env bash
# merge-guard.test.sh — drives the hook with PreToolUse JSON on stdin (the production
# code path). Run: bash hooks/merge-guard.test.sh
#
# Why this suite exists (docs/features/global-option-blindness.md, task 0b): of the
# 18 hook scripts under hooks/, merge-guard.sh is the only one this feature names as
# its sole *silent* failure mode -- a rewrite that quietly stopped blocking `gh pr
# merge` would fail open with nothing to say so -- and it had no suite at all. This
# pins today's behaviour first, before task 6's rewrite touches the hook, so that
# rewrite has a safety net instead of none.
#
# merge-guard.sh never reads or writes the checkout -- it only classifies the command
# string -- so every case below runs against a bare scratch directory, not a git repo.
#
# The commands below are DATA fed to the hook on stdin. Nothing here executes them.
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/merge-guard.sh"
# shellcheck disable=SC1091  # this test's own dynamically-resolved path, not user input
source "$(cd "$(dirname "$0")" && pwd)/lib/guard_test_helpers.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }

run_case() { # $1 desc, $2 want-exit, $3 command string
  local desc="$1" want="$2" cmd="$3" got
  ( cd "$TMP" && payload "$cmd" | bash "$HOOK" >/dev/null 2>&1 )
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

# ---------------------------------------------------------------------------
# `gh pr merge` -- blocked, reason on stderr
# ---------------------------------------------------------------------------
run_case "plain gh pr merge -> block"                         2 'gh pr merge 5'
assert_stderr "$TMP" "  ...blocked message names the GitHub-UI remedy" 'gh pr merge 5' \
  'merge-guard: `gh pr merge` is blocked -- merge pull requests through the GitHub UI with review, not from the CLI mid-session.'

# ---------------------------------------------------------------------------
# MERGE_EXEMPT=<reason> -- allowed, reason echoed on stderr
# ---------------------------------------------------------------------------
run_case "MERGE_EXEMPT set -> allow"                          0 'MERGE_EXEMPT="release cut" gh pr merge 5'
assert_stderr "$TMP" "  ...exemption reason echoed on stderr" 'MERGE_EXEMPT="release cut" gh pr merge 5' \
  'merge-guard: exempted (MERGE_EXEMPT=release cut); allowing the PR merge.'

# ---------------------------------------------------------------------------
# An ordinary `git merge` -- untouched
# ---------------------------------------------------------------------------
run_case "ordinary git merge -> allow, untouched"             0 'git merge origin/main'

# ---------------------------------------------------------------------------
printf '\nmerge-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
