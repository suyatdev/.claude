#!/usr/bin/env bash
#
# hook-exec-pr-guard.sh — PreToolUse hook (matcher: Bash).
#
# Refuses `gh pr create` while any hook script registered in settings.json is stored in the
# branch's HEAD commit as anything but mode 100755. A script stored 100644 cannot be started by
# Claude Code (exit 126), so the hook it implements silently does nothing; this has reached main
# twice through a PR (#109, #105). The check itself is hooks/lib/registered_hook_modes.py, the same
# module hooks/registered-hooks-executable.test.sh runs by hand.
#
# Spec: docs/features/hook-exec-bit-pr-guard.md (R3-R8, and its flowchart for the order below).
#
# Reads: the PreToolUse payload on stdin (tool_input.command), $HOME, the session's git repo.
#
# Fail directions, in the order the script meets them:
#   - OUT of scope (not this repo, no HOME, no git, empty stdin) -> allow, silent. Scope is decided
#     with bash and git only, before any Python, so nothing this hook depends on can block a
#     command in another repository.
#   - IN scope, machinery broken (no python3, unreadable payload, unusable classifier) -> exit 2 for
#     every Bash command here, as judge-guard.sh already does in the same three states. The message
#     names a repair route that survives the block, because git and every other shell command is
#     denied while it holds.
#   - IN scope, a gh pr create whose checker did not run -> exit 2 naming the module.
# Not a security boundary: command shapes the classifier does not read are accepted-open (ADR 0012).
#
# Escape hatch: `HOOK_EXEC_EXEMPT=<reason> gh pr create ...` (logged to stderr).
#
# Exit 0 = allow. Exit 2 = blocked, reason on stderr. Nothing is ever written to stdout.

set -u

PREFIX='hook-exec-pr-guard:'
# Both helpers load from this script's own directory, never $HOME/.claude/hooks, so the suite can
# run a broken copy and a worktree's hooks are the ones that run.
HERE="$(cd "$(dirname "$0")" && pwd -P)"
CLASSIFIER="$HERE/lib/classify-pr-command.py"
CHECKER="$HERE/lib/registered_hook_modes.py"
REPAIR='repair it with the Write tool, or unregister the hook in settings.json'

payload=""
if [ ! -t 0 ]; then payload=$(cat); fi
[ -n "$payload" ] || exit 0

# ---- R4: scope, bash + git only ----
[ -n "${HOME:-}" ] || exit 0
command -v git >/dev/null 2>&1 || exit 0
[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] || exit 0
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
session_git=$(cd -P "$common" 2>/dev/null && pwd -P) || exit 0
claude_git=$(cd -P "$HOME/.claude/.git" 2>/dev/null && pwd -P) || exit 0
[ -n "$session_git" ] && [ "$session_git" = "$claude_git" ] || exit 0

# ---- R8: in scope from here, so broken machinery fails closed ----
# python3 only, not judge-guard's `python3 || python`: a bare `python` can be Python 2, which has
# neither -I nor the stdlib calls the checker makes.
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s python3 not on PATH; cannot read the command -- failing closed. ALL Bash commands in this repo are blocked until python3 is back on PATH or you %s.\n' "$PREFIX" "$REPAIR" >&2
  exit 2
fi

# -I keeps the caller's directory off sys.path (a json.py in $PWD must not shadow the stdlib). The
# parser prints OK/SKIP on line 1 only after deciding; the command follows from line 2. No
# apostrophes in the Python below: it sits inside single-quoted shell.
parsed=$(printf '%s' "$payload" | python3 -I -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    raise SystemExit(3)
if not isinstance(p, dict):
    raise SystemExit(3)
ti = p.get("tool_input")
c = ti.get("command") if isinstance(ti, dict) else None
if isinstance(c, str) and c.strip():
    sys.stdout.write("OK\n" + c)
else:
    sys.stdout.write("SKIP\n")
' 2>/dev/null)
parse_rc=$?
parse_kind=$(printf '%s\n' "$parsed" | sed -n '1p')
case "$parse_rc:$parse_kind" in
  0:OK)   ;;
  0:SKIP) exit 0 ;;
  *)
    printf '%s could not read the PreToolUse payload (not valid JSON, not an object, or python3 failed) -- failing closed. ALL Bash commands in this repo are blocked until it reads again; %s.\n' "$PREFIX" "$REPAIR" >&2
    exit 2
    ;;
esac
command_line=$(printf '%s\n' "$parsed" | sed -n '2,$p')
[ -n "$command_line" ] || exit 0

# ---- R3: does this command run `gh pr create`? ----
classified=$(printf '%s' "$command_line" | python3 -I -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("classify_pr_command", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
kind, exempt = mod.classify(sys.stdin.read(), subcommand=("pr", "create"), exempt_var="HOOK_EXEC_EXEMPT")
sys.stdout.write(kind + "\n" + exempt + "\n")
' "$CLASSIFIER" 2>/dev/null)
classify_rc=$?
kind=$(printf '%s\n' "$classified" | sed -n '1p')
exempt_reason=$(printf '%s\n' "$classified" | sed -n '2p')
# Status AND shape, as judge-guard.sh does: a classifier can print a legal NO and still have died.
case "$classify_rc:$kind" in
  0:PR|0:NO) ;;
  *)
    printf '%s classifier at %s produced no usable output -- failing closed (it is missing, empty, truncated, or broken). ALL Bash commands in this repo are blocked until it is repaired; %s.\n' "$PREFIX" "$CLASSIFIER" "$REPAIR" >&2
    exit 2
    ;;
esac
[ "$kind" = "PR" ] || exit 0

# ---- R7: bypass ----
if [ -n "$exempt_reason" ]; then
  printf '%s exempted (HOOK_EXEC_EXEMPT=%s)\n' "$PREFIX" "$exempt_reason" >&2
  exit 0
fi

# ---- R5/R6: the shared checker, against HEAD (what gh pr create publishes), not the index ----
toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
result=$(python3 -I "$CHECKER" "$toplevel" --rev HEAD 2>/dev/null)
checker_rc=$?
last_line=$(printf '%s\n' "$result" | sed -n '$p')

case "$checker_rc:$last_line" in
  0:"result: PASS") exit 0 ;;
  1:"result: FAIL"*)
    {
      printf '%s\n' "$result" | sed -n "s/^FAIL /$PREFIX FAIL /p"
      # Only a mode problem has a chmod fix; the other FAIL lines already say what is wrong.
      printf '%s\n' "$result" | sed -n 's/^FAIL \(.*\) is registered on .* but stored as mode .*/\1/p' |
        while IFS= read -r path; do
          printf '%s fix %s: chmod +x %s, then git add -- %s, then commit (the check reads HEAD, so a staged change is not enough)\n' "$PREFIX" "$path" "$path" "$path"
        done
      printf '%s to bypass a genuinely exempt PR: HOOK_EXEC_EXEMPT=<reason> gh pr create ...\n' "$PREFIX"
    } >&2
    exit 2
    ;;
  *)
    printf '%s checker %s did not run (exit %s, last line [%s]) -- failing closed; %s.\n' "$PREFIX" "$CHECKER" "$checker_rc" "$last_line" "$REPAIR" >&2
    exit 2
    ;;
esac
