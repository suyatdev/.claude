#!/usr/bin/env bash
#
# git-guard.sh — PreToolUse hook (matcher: Bash).
#
# Two deterministic guards an instruction alone cannot hold under momentum:
#   1. Default-branch commit guard: blocks `git commit` on main/master unless
#      every staged file is CODING_MEMORY.md or under coding-memory/ (the
#      brainstorm-then-branch exception).
#   2. Force-push guard: blocks a bare `git push --force`/`-f` on any branch;
#      allows `--force-with-lease` except when the current branch is main/master.
#
# Must also catch the `rtk git ...` form: the RTK PreToolUse hook (registered
# ahead of this one in settings.json) rewrites plain git commands before this
# guard runs, so the command it sees may already carry an `rtk ` prefix.
#
# Exit 0 = allow (silent). Exit 2 = blocked, reason on stderr.
#
# Regexes live in variables, never inline in `[[ ]]` — a bare `(` or `;` inside
# an inline regex makes bash's parser die with "unexpected EOF", and a dead
# script exits non-zero, which PreToolUse reads as a block. See
# hooks/checkpoint-before-modify.sh for the same trap, caught the same way.

set -u

payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi

[ -n "$payload" ] || exit 0

py=$(command -v python3 || command -v python) || py=""
if [ -z "$py" ]; then
  printf 'git-guard: python3 not on PATH; cannot inspect the command -- failing closed.\n' >&2
  exit 2
fi

command_line=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
tool_input = payload.get("tool_input")
if isinstance(tool_input, dict):
    value = tool_input.get("command")
    if isinstance(value, str):
        sys.stdout.write(value)
' 2>/dev/null)

[ -n "$command_line" ] || exit 0

# Strip leading whitespace, then a leading `rtk ` wrapper if present.
normalized="${command_line#"${command_line%%[![:space:]]*}"}"
if [[ "$normalized" == rtk\ * ]]; then
  normalized="${normalized#rtk }"
fi

current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

on_main() {
  local b
  b="$(current_branch)"
  [ "$b" = "main" ] || [ "$b" = "master" ]
}

# --- Guard 2: force-push ---
push_re='^git[[:space:]]+push([[:space:]]|$)'
if [[ "$normalized" =~ $push_re ]]; then
  force_re='(^|[[:space:]])(--force|-f)([[:space:]]|$)'
  lease_re='--force-with-lease'
  if [[ "$normalized" =~ $force_re ]] && [[ ! "$normalized" =~ $lease_re ]]; then
    printf 'git-guard: bare "git push --force"/"-f" is blocked on every branch. Use --force-with-lease instead (still blocked while main/master is checked out).\n' >&2
    exit 2
  fi
  if [[ "$normalized" =~ $lease_re ]] && on_main; then
    printf 'git-guard: --force-with-lease is blocked while main/master is checked out.\n' >&2
    exit 2
  fi
fi

# --- Guard 1: default-branch commit ---
commit_re='^git[[:space:]]+commit([[:space:]]|$)'
if [[ "$normalized" =~ $commit_re ]] && on_main; then
  staged=$(git diff --cached --name-only 2>/dev/null || echo "")
  allowed=1
  if [ -z "$staged" ]; then
    allowed=0
  else
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in
        CODING_MEMORY.md|coding-memory/*) ;;
        *) allowed=0 ;;
      esac
    done <<< "$staged"
  fi
  if [ "$allowed" -ne 1 ]; then
    printf 'git-guard: commits to main/master are blocked except a CODING_MEMORY.md-only brainstorm commit.\n' >&2
    printf 'Staged files:\n%s\n' "$staged" | sed 's/^/  /' >&2
    printf 'Create a feature branch instead, or stage only CODING_MEMORY.md / coding-memory/*.\n' >&2
    exit 2
  fi
fi

exit 0
