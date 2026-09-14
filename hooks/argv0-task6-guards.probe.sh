#!/usr/bin/env bash
# Task 6 probe (docs/features/argv0-spelling-blindness.md) -- the tracked,
# re-runnable version of the throwaway probe that produced the card's opening
# "Measured: the current behavior" table for git-guard.sh, doc-guard.sh,
# merge-guard.sh and secret-command-guard.sh.
#
# Runs the REAL hook scripts against throwaway scratch repos -- never against
# this worktree's index. Measurement only: this script does not fix anything.
#
# Hard precondition: for each guard, the lowercase control MUST refuse (rc=2)
# before any capitalized/path row for that guard is reported. If the control
# does not refuse, the fixture never engaged the guard body, and the group is
# printed as UNMEASURED rather than as a clean table -- the card was burned
# twice by exactly the alternative (a payload missing hook_event_name, and a
# missing sibling-test fixture, both of which made a control read "allowed"
# when it meant "never inspected").
#
# Security constraint: the env-dump forms (ENV, Printenv, env, printenv,
# /usr/bin/env) are NEVER executed here -- only ever passed to the guard as
# command TEXT inside a JSON payload. A judge ran one of these for real during
# planning and dumped a live API key into its context (rotated). Do not change
# that.
#
# Usage: hooks/argv0-task6-guards.probe.sh
set -u

HOOKDIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_ID="argv0-task6-probe"
UNMEASURED=0

payload() { # $1 cwd  $2 command
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s},"cwd":%s,"session_id":"%s"}' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$2")" \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")" \
    "$SESSION_ID"
}

run() { # $1 script  $2 cwd  $3 command
  payload "$2" "$3" | "$1" >/tmp/argv0-task6.out 2>/tmp/argv0-task6.err
  echo $?
}

# Runs the control row for a guard and asserts it refuses (rc=2). Prints the
# control result either way. Returns 1 (and sets UNMEASURED) if it did not
# refuse, so the caller can skip the rest of the group.
assert_control_refuses() { # $1 label  $2 script  $3 cwd  $4 control-command
  local rc
  rc=$(run "$2" "$3" "$4")
  printf '%-24s control=%-20s rc=%s  stderr=%s\n' "$1" "$4" "$rc" "$(head -c 200 /tmp/argv0-task6.err | tr '\n' ' ')"
  if [ "$rc" != "2" ]; then
    printf '%s: UNMEASURED -- lowercase control did not refuse (rc=%s, expected 2). The fixture never engaged the guard body; skipping this group rather than printing a table that would look clean.\n' "$1" "$rc"
    UNMEASURED=1
    return 1
  fi
  return 0
}

echo "== git-guard.sh =="
REPO=$(mktemp -d /tmp/gg-probe.XXXXXX)
cd "$REPO" || exit 1
git init -q -b main
git config user.email test@example.com
git config user.name test
git commit --allow-empty -q -m init
python3 -c "
for i in range(130):
    print(f'def f{i}(): return {i}')
" > src.py
git add src.py >/dev/null

if assert_control_refuses "git-guard.sh" "$HOOKDIR/git-guard.sh" "$REPO" "git commit -m x"; then
  for spelling in "Git" "GIT" "/usr/bin/git"; do
    rc=$(run "$HOOKDIR/git-guard.sh" "$REPO" "$spelling commit -m x")
    printf '%-24s %-20s rc=%s\n' "git-guard.sh" "$spelling" "$rc"
  done
fi
cd "$HOOKDIR" || exit 1
rm -rf "$REPO"
echo

echo "== doc-guard.sh =="
REPO=$(mktemp -d /tmp/dg-probe.XXXXXX)
cd "$REPO" || exit 1
git init -q -b main
git config user.email test@example.com
git config user.name test
git commit --allow-empty -q -m init
python3 -c "
for i in range(130):
    print(f'def f{i}(): return {i}')
" > src.py
git add src.py >/dev/null

if assert_control_refuses "doc-guard.sh" "$HOOKDIR/doc-guard.sh" "$REPO" "git commit -m x"; then
  for spelling in "Git" "GIT" "/usr/bin/git"; do
    rc=$(run "$HOOKDIR/doc-guard.sh" "$REPO" "$spelling commit -m x")
    printf '%-24s %-20s rc=%s\n' "doc-guard.sh" "$spelling" "$rc"
  done
fi
cd "$HOOKDIR" || exit 1
rm -rf "$REPO"
echo

echo "== merge-guard.sh =="
REPO=$(mktemp -d /tmp/mg-probe.XXXXXX)
cd "$REPO" || exit 1
git init -q
git config user.email test@example.com
git config user.name test
git commit --allow-empty -q -m init

if assert_control_refuses "merge-guard.sh" "$HOOKDIR/merge-guard.sh" "$REPO" "gh pr merge 5"; then
  for spelling in "Gh" "/opt/homebrew/bin/gh"; do
    rc=$(run "$HOOKDIR/merge-guard.sh" "$REPO" "$spelling pr merge 5")
    printf '%-24s %-20s rc=%s\n' "merge-guard.sh" "$spelling" "$rc"
  done
fi
cd "$HOOKDIR" || exit 1
rm -rf "$REPO"
echo

echo "== secret-command-guard.sh =="
REPO=$(mktemp -d /tmp/scg-probe.XXXXXX)
cd "$REPO" || exit 1
git init -q
git config user.email test@example.com
git config user.name test
git commit --allow-empty -q -m init

# `env` / `printenv` are passed only as command TEXT inside the JSON payload
# below -- never executed. The guard classifies from text; nothing runs.
if assert_control_refuses "secret-command-guard.sh" "$HOOKDIR/secret-command-guard.sh" "$REPO" "env"; then
  rc=$(run "$HOOKDIR/secret-command-guard.sh" "$REPO" "printenv")
  printf '%-24s %-20s rc=%s\n' "secret-command-guard.sh" "printenv" "$rc"
  for spelling in "ENV" "Printenv" "/usr/bin/env"; do
    rc=$(run "$HOOKDIR/secret-command-guard.sh" "$REPO" "$spelling")
    printf '%-24s %-20s rc=%s\n' "secret-command-guard.sh" "$spelling" "$rc"
  done
fi
cd "$HOOKDIR" || exit 1
rm -rf "$REPO"
echo

if [ "$UNMEASURED" -eq 1 ]; then
  echo "One or more groups above are UNMEASURED -- see the messages inline."
  exit 1
fi
