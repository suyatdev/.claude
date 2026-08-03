#!/usr/bin/env bash
#
# git-guard.sh — PreToolUse hook (matcher: Bash).
#
# Two deterministic guards an instruction alone cannot hold under momentum:
#   1. Default-branch commit guard: blocks `git commit` on main/master unless
#      every staged file is CODING_MEMORY.md, under coding-memory/, or a MARKDOWN
#      file under docs/ (the brainstorm-then-branch and documentation exceptions).
#      The docs/ exception is deliberately by file type, not by directory: an
#      executable dropped under docs/ must not inherit a free ride onto main.
#      doc-guard.sh deliberately uses the BROADER `docs/*` for the same directory.
#      The two are not meant to agree: doc-guard asks "did documentation ride along
#      with this commit?", where a diagram or screenshot counts; this guard asks
#      "may this file reach main unreviewed?", where it must not. Do not align them.
#   2. Force-push guard: blocks a bare `git push --force`/`-f` on any branch;
#      allows `--force-with-lease` except when the current branch is main/master.
#      Scope note: this matches `--force`/`-f`/`--force-with-lease` specifically,
#      not the `+refspec` force-push form (`git push origin +main`) — a momentum
#      guardrail, not a security boundary.
#
# Which git command is being run is decided by lib/classify-git-command.py, which
# lexes the command into shell segments. Both guards previously matched a regex
# ANCHORED to the start of the command string, so anything chained — `git add -- x
# && git commit -m y`, the shape this repo uses constantly — never matched and the
# guard body never ran. The hook exited 0 without having evaluated anything, and
# commits reached main that the allowlist forbids. Flags are now judged within the
# segment that owns them: `git push --force && echo --force-with-lease` used to read
# as a leased push and go unblocked, and `git push && echo --force` used to be
# blocked. Shapes still deliberately open are documented in lib/shell_segments.py.
#
# That classifier also absorbs the `rtk git ...` form: the RTK PreToolUse hook
# (registered ahead of this one in settings.json) rewrites plain git commands before
# this guard runs, so the command it sees may already carry an `rtk ` prefix.
#
# Exit 0 = allow (silent). Exit 2 = blocked, reason on stderr.
#
# Fails CLOSED (exit 2) when it cannot inspect the command at all — no python3, or
# an unrunnable classifier. These guards protect against a destructive or
# unreviewable action, so "cannot tell" must not mean "allow"; contrast doc-guard.sh,
# which fails open because a missing note is not worth blocking work over.

set -u

CLASSIFIER="$(cd "$(dirname "$0")" && pwd)/lib/classify-git-command.py"

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

if ! facts=$(printf '%s' "$command_line" | "$py" "$CLASSIFIER" 2>/dev/null); then
  printf 'git-guard: cannot run %s; failing closed.\n' "$CLASSIFIER" >&2
  printf 'Restore it (it lives beside this hook) to unblock Bash calls.\n' >&2
  exit 2
fi

has_fact() {
  local f
  for f in $facts; do
    [ "$f" = "$1" ] && return 0
  done
  return 1
}

current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

on_main() {
  local b
  b="$(current_branch)"
  [ "$b" = "main" ] || [ "$b" = "master" ]
}

# --- Guard 2: force-push ---
# PUSH_FORCE already means "bare force, with no --force-with-lease in that same
# segment", so the two cases below cannot both fire for one push.
if has_fact PUSH_FORCE; then
  printf 'git-guard: bare "git push --force"/"-f" is blocked on every branch. Use --force-with-lease instead (still blocked while main/master is checked out).\n' >&2
  exit 2
fi
if has_fact PUSH_LEASE && on_main; then
  printf 'git-guard: --force-with-lease is blocked while main/master is checked out.\n' >&2
  exit 2
fi

# --- Guard 1: default-branch commit ---
if has_fact COMMIT && on_main; then
  staged=$(git diff --cached --name-only 2>/dev/null || echo "")
  allowed=1
  if [ -z "$staged" ]; then
    allowed=0
  else
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in
        # `*` spans `/` in a case pattern, so `docs/*.md` covers any depth while
        # still rejecting `docs/tool.sh` — and `docs/notes.md.sh`.
        CODING_MEMORY.md|coding-memory/*|docs/*.md) ;;
        *) allowed=0 ;;
      esac
    done <<< "$staged"
  fi
  if [ "$allowed" -ne 1 ]; then
    printf 'git-guard: commits to main/master are blocked except documentation (CODING_MEMORY.md, coding-memory/*, docs/*.md).\n' >&2
    printf 'Staged files:\n%s\n' "$staged" | sed 's/^/  /' >&2
    printf 'Create a feature branch instead, or stage only documentation.\n' >&2
    exit 2
  fi
fi

exit 0
