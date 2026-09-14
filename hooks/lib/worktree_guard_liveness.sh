#!/usr/bin/env bash
#
# worktree_guard_liveness.sh — "is layer 2 armed for this repository?", answered once.
#
# SOURCED, never executed. Two callers, and that is the whole reason this file exists:
#
#   * hooks/worktree-guard.sh (layer 1) appends a report to every refusal it prints, so an
#     unarmed layer 2 is not silent;
#   * hooks/install-layer2.sh runs it after arming, so an install that placed a file and
#     changed nothing git reads is reported as a failure rather than as success.
#
# Two copies of that judgement would drift, and the drift would be invisible: the installer
# would report "armed" under criteria layer 1 does not use, and nobody reads both files at
# once. This is the same argument round 4 made about resolve_effective_repo() — one rule, one
# definition, both callers moving together.
#
# WHAT "ARMED" MEANS, and why each clause is here. All three absence modes were measured to
# fail open SILENTLY at layer 2 (rc=0, HEAD moved), so layer 2 cannot report any of them:
#
#   * the resolved hooks directory does not exist;
#   * no `reference-transaction` file is in it;
#   * it is there but is not a regular file, or is not executable — the mode that reads most
#     like a working install, and the one a bare presence test passes.
#
# WHAT IS DELIBERATELY *NOT* CHECKED: the mode file (reference-transaction.mode) that layer 2
# reads beside itself. Its absence does NOT fail open — the hook refuses every HEAD move with
# a message naming the file — and this check exists for the failures that are silent. Adding
# it would widen the check's contract for no safety gained. The installer verifies the mode
# file separately, because placing it is the installer's own job.
#
# The repository is passed IN, never re-derived. Layer 1's arms have already resolved it, and
# a second derivation here is a second place for it to be wrong.

# The hook filename git looks for. There is no `.sh`: git resolves hooks by exact filename.
WG_LAYER2_HOOK='reference-transaction'

# The path handed to `git rev-parse --git-path`, which is how the EFFECTIVE core.hooksPath is
# resolved. Measured against a throwaway repo, all four shapes: --git-path honours the whole
# config precedence (a repo-LOCAL core.hooksPath beats a global one — the husky/lefthook case
# this check exists for), falls back to <git-dir>/hooks when it is unset, resolves a relative
# value against the repository rather than the caller's cwd, and answers the COMMON hooks
# directory from inside a linked worktree.
WG_HOOKS_GIT_PATH='hooks'

# The two outputs. WG_LIVENESS_PATH is the resolved hooks directory ('' when git would not
# answer); WG_LIVENESS_STATE is the short phrase naming what is wrong ('' when armed). The
# PROSE stays with each caller: layer 1 appends a paragraph to a refusal, the installer prints
# a report, and the two audiences are not the same. What is shared is the verdict.
WG_LIVENESS_PATH=''
WG_LIVENESS_STATE=''

wg_liveness() { # $1 the repository to check — 0 armed, 1 not armed, 2 unresolvable
  local hook
  WG_LIVENESS_PATH=''
  WG_LIVENESS_STATE=''
  [ -n "${1:-}" ] || { WG_LIVENESS_STATE='no repository was given to check'; return 2; }
  # --path-format=absolute for the same reason layer 1's boundary 6 uses it: without it the
  # answer is relative to the caller's cwd, and a relative path tested with [ -d ] answers a
  # question about the wrong directory.
  WG_LIVENESS_PATH=$(git -C "$1" rev-parse --path-format=absolute --git-path \
    "$WG_HOOKS_GIT_PATH" 2>/dev/null) || WG_LIVENESS_PATH=''
  if [ -z "$WG_LIVENESS_PATH" ]; then
    WG_LIVENESS_STATE='git would not report a hooks path for it'
    return 2
  fi
  hook="$WG_LIVENESS_PATH/$WG_LAYER2_HOOK"
  # Armed means a REGULAR file that is executable, which is what git itself requires.
  if [ ! -d "$WG_LIVENESS_PATH" ]; then
    WG_LIVENESS_STATE='that directory does not exist'
  elif [ ! -e "$hook" ]; then
    WG_LIVENESS_STATE="no \`$WG_LAYER2_HOOK\` file is in it"
  elif [ ! -f "$hook" ]; then
    WG_LIVENESS_STATE="\`$WG_LAYER2_HOOK\` is there but is not a regular file"
  elif [ ! -x "$hook" ]; then
    WG_LIVENESS_STATE="\`$WG_LAYER2_HOOK\` is there but is not executable"
  else
    return 0
  fi
  return 1
}
