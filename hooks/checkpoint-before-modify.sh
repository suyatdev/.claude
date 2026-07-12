#!/usr/bin/env bash
#
# checkpoint-before-modify.sh — refuse to start a DESTRUCTIVE operation with no rollback point.
#
# Why this is a hook and not an instruction: an agent that is about to make a
# sweeping change is exactly the agent least likely to stop and check whether the
# work it is about to overwrite is recoverable. "Commit before large refactors" is
# a rule everyone agrees with and nobody remembers under momentum. The cost of
# forgetting is asymmetric — uncommitted work that gets overwritten is simply gone,
# and no amount of apologizing at the end restores it.
#
# A "clean checkpoint" means: this is a git repo, it has at least one commit, and
# the working tree has nothing that would be lost. Anything else is reported by
# name so the operator can see exactly what is at risk.
#
# WHY THERE IS A COMMAND ALLOWLIST:
#
# The first version of this hook gated EVERY Bash call on a clean tree. Wired to
# `PreToolUse` on `Bash`, that strands the agent completely: the moment the tree is
# dirty, `git add`, `git commit`, and `git stash` are blocked too — and those are
# the only actions that would satisfy the hook. The single instruction it prints
# ("commit or stash these") names commands it has just made unreachable. There is
# no move that recovers; the operator has to leave the session and go to a terminal.
# A guard whose remedy it also blocks is not a guard, it is a trap.
#
# So the decision is made per-command, in this order:
#   1. RECOVERY / READ-ONLY — always allowed, dirty tree or not. This is the escape
#      hatch, and it is checked FIRST so that no later pattern can shadow it. A
#      commit message containing the words "rm -rf" must not block the commit.
#   2. DESTRUCTIVE — requires a clean checkpoint. These are the commands that can
#      actually vaporize uncommitted work.
#   3. Everything else — allowed. Running the test suite on a dirty tree is normal
#      work, and blocking it buys nothing.
#
# This is a rollback guard, not a security boundary: it matches on the leading
# command, so `git commit -m "x" && rm -rf /` slips through. Anything that must not
# be bypassable belongs in the permission system, not here.
#
# Usage: checkpoint-before-modify.sh [repo-dir]     # CLI mode: always checks
#        <payload.json checkpoint-before-modify.sh [repo-dir]   # hook mode
# Exit:  0 = allowed (silent).  2 = destructive command with no clean checkpoint.

set -u

dir="${1:-.}"

# Hook mode: pull the command out of the PreToolUse payload.
# CLI mode (no payload): no command to judge, so the checkpoint is checked unconditionally.
command_line=""
normalized=""
payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi

if [ -n "$payload" ]; then
  py=$(command -v python3 || command -v python) || py=""
  if [ -z "$py" ]; then
    # Degrade to a no-op, loudly. Blocking every Bash call because the parser is
    # missing would re-create the exact trap this allowlist exists to remove — and
    # a rollback guard is not worth stranding a session over.
    printf 'checkpoint-before-modify: python3 not on PATH; cannot read the command from the\n' >&2
    printf 'payload, so this checkpoint guard is NOT running. Install python3 to re-enable it.\n' >&2
    exit 0
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

  # A payload with no `command` is not a Bash tool call. Nothing to guard.
  [ -n "$command_line" ] || exit 0

  # Strip leading whitespace and any `VAR=value` prefixes so the real command is first.
  normalized="${command_line#"${command_line%%[![:space:]]*}"}"
  while [[ "$normalized" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
    normalized="${normalized#"${BASH_REMATCH[0]}"}"
  done

  # The regexes live in variables, not inline: bash's `[[ ]]` parser treats a bare
  # `(` or `;` inside an inline regex as shell syntax and dies with "unexpected EOF".
  # A dead script exits non-zero, which reads as "blocked" — a syntax error would
  # silently turn this guard into the very trap it is meant to remove.

  # 1. Recovery and read-only. Always allowed — this is what makes the hook escapable.
  #    `git add`/`commit`/`stash` are here because they ARE the remedy the hook demands.
  allow_patterns=(
    '^git[[:space:]]+(add|commit|stash|status|diff|log|show|fetch|remote|config|rev-parse|ls-files|blame)([[:space:]]|$)'
    '^(ls|pwd|cat|head|tail|wc|echo|printf|grep|rg|which|stat|file|env|date|true)([[:space:]]|$)'
  )
  for pattern in "${allow_patterns[@]}"; do
    if [[ "$normalized" =~ $pattern ]]; then
      exit 0
    fi
  done

  # 2. Destructive. These can vaporize uncommitted work, so they need a rollback point.
  destructive_patterns=(
    '(^|[[:space:];|&(])rm[[:space:]]+(-[[:alnum:]]*[rRf]|--recursive|--force)'
    'git[[:space:]]+reset[[:space:]]+.*--hard'
    'git[[:space:]]+(clean|restore|rebase|merge|cherry-pick|revert|filter-branch)([[:space:]]|$)'
    'git[[:space:]]+checkout[[:space:]]+(-f|--force|--([[:space:]]|$)|\.)'
    'git[[:space:]]+push[[:space:]]+.*(--force|-f([[:space:]]|$))'
    'git[[:space:]]+branch[[:space:]]+-[dD]'
    '(^|[[:space:];|&(])(shred|truncate)([[:space:]]|$)'
    '(^|[[:space:];|&(])dd[[:space:]]+.*of='
    '(^|[[:space:];|&(])sed[[:space:]]+.*-i'
    '(find|xargs)[[:space:]]+.*(-delete|-exec[[:space:]]+rm)'
  )
  is_destructive=0
  for pattern in "${destructive_patterns[@]}"; do
    if [[ "$normalized" =~ $pattern ]]; then
      is_destructive=1
      break
    fi
  done

  # 3. Everything else is ordinary work — running the tests on a dirty tree is normal.
  [ "$is_destructive" -eq 1 ] || exit 0
fi

cd "$dir" 2>/dev/null || {
  printf 'checkpoint-before-modify: cannot enter directory: %s\n' "$dir" >&2
  exit 2
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'checkpoint-before-modify: not a git repository — there is no rollback point.\n' >&2
  printf 'Run "git init" and make an initial commit before a destructive operation.\n' >&2
  exit 2
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  printf 'checkpoint-before-modify: repository has no commits — nothing to roll back to.\n' >&2
  printf 'Make an initial commit before a destructive operation.\n' >&2
  exit 2
fi

# --porcelain covers staged, unstaged, and untracked files in one pass.
dirty=$(git status --porcelain 2>/dev/null)

if [ -n "$dirty" ]; then
  printf 'checkpoint-before-modify: uncommitted work would be unrecoverable if overwritten.\n' >&2
  if [ -n "$normalized" ]; then
    printf 'Blocked command: %s\n' "$command_line" >&2
  fi
  printf 'At risk:\n' >&2
  printf '%s\n' "$dirty" | sed 's/^/  /' >&2
  printf 'Commit or stash these first — "git add", "git commit", and "git stash" are\n' >&2
  printf 'allowlisted by this hook and will not be blocked.\n' >&2
  exit 2
fi

exit 0
