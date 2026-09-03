#!/usr/bin/env bash
# Task 9 probe (docs/features/argv0-spelling-blindness.md) -- measures whether
# test-marker-guard.sh and judge-guard.sh are blind to a capitalized/path argv[0]
# spelling of `git` / `gh`, the way git-guard.sh, doc-guard.sh, merge-guard.sh and
# secret-command-guard.sh already were measured to be.
#
# Runs the REAL hook scripts against a throwaway scratch repo -- never against this
# worktree's index. Measurement only: this script does not fix anything.
#
# Usage: hooks/argv0-task9-guards.probe.sh
set -u

HOOKDIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_ID="argv0-task9-probe"

payload() { # $1 cwd  $2 command
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s},"cwd":%s,"session_id":"%s"}' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$2")" \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")" \
    "$SESSION_ID"
}

run() { # $1 script  $2 cwd  $3 command
  payload "$2" "$3" | "$1" >/tmp/argv0-task9.out 2>/tmp/argv0-task9.err
  echo $?
}

echo "== test-marker-guard.sh =="
REPO=$(mktemp -d /tmp/tmg-probe.XXXXXX)
cd "$REPO" || exit 1
git init -q
git config user.email test@example.com
git config user.name test
mkdir -p hooks/lib
cp "$HOOKDIR/lib/write-test-marker.py" hooks/lib/
cp "$HOOKDIR/lib/decide-commit-gate.py" hooks/lib/
cp "$HOOKDIR/lib/classify-commit-command.py" hooks/lib/
cp "$HOOKDIR/lib/classify-git-command.py" hooks/lib/
cp "$HOOKDIR/lib/shell_segments.py" hooks/lib/
cat > foo.py <<'PYEOF'
def add(a, b):
    return a + b
PYEOF
cat > foo.test.py <<'PYEOF'
import foo

def test_add():
    assert foo.add(1, 2) == 3
PYEOF
git add foo.py foo.test.py hooks >/dev/null

for spelling in "git" "Git" "GIT" "/usr/bin/git"; do
  rc=$(run "$HOOKDIR/test-marker-guard.sh" "$REPO" "$spelling commit -m x")
  printf '%-16s rc=%s  stderr=%s\n' "$spelling" "$rc" "$(head -c 200 /tmp/argv0-task9.err | tr '\n' ' ')"
done
cd "$HOOKDIR" || exit 1
rm -rf "$REPO"

echo
echo "== judge-guard.sh =="
REPO=$(mktemp -d /tmp/jg-probe.XXXXXX)
cd "$REPO" || exit 1
git init -q
git config user.email test@example.com
git config user.name test
git commit --allow-empty -q -m init

for spelling in "gh" "Gh" "GH" "/opt/homebrew/bin/gh"; do
  rc=$(run "$HOOKDIR/judge-guard.sh" "$REPO" "$spelling pr create --title x --body y")
  printf '%-24s rc=%s  stderr=%s\n' "$spelling" "$rc" "$(head -c 200 /tmp/argv0-task9.err | tr '\n' ' ')"
done
cd "$HOOKDIR" || exit 1
rm -rf "$REPO"
