#!/usr/bin/env bash
#
# checkpoint-before-modify.sh — refuse to start a batch of edits with no rollback point.
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
# Usage: checkpoint-before-modify.sh [repo-dir]
# Exit:  0 = a rollback point exists (silent).  2 = no clean checkpoint.

set -u

dir="${1:-.}"
cd "$dir" 2>/dev/null || {
  printf 'checkpoint-before-modify: cannot enter directory: %s\n' "$dir" >&2
  exit 2
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'checkpoint-before-modify: not a git repository — there is no rollback point.\n' >&2
  printf 'Run "git init" and make an initial commit before a batch of modifications.\n' >&2
  exit 2
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  printf 'checkpoint-before-modify: repository has no commits — nothing to roll back to.\n' >&2
  printf 'Make an initial commit before a batch of modifications.\n' >&2
  exit 2
fi

# --porcelain covers staged, unstaged, and untracked files in one pass.
dirty=$(git status --porcelain 2>/dev/null)

if [ -n "$dirty" ]; then
  printf 'checkpoint-before-modify: uncommitted work would be unrecoverable if overwritten.\n' >&2
  printf 'At risk:\n' >&2
  printf '%s\n' "$dirty" | sed 's/^/  /' >&2
  printf 'Commit or stash these before a batch of modifications.\n' >&2
  exit 2
fi

exit 0
