#!/usr/bin/env bash
#
# loosening-guard.sh -- stop and ask before a commit widens a security guard's permission list.
#
# Purpose: the three guards (secret-command-guard, git-guard, worktree-guard) are only as strong as the
# lists in their files. This hook fires on `git commit`, compares the fourteen files that carry those
# lists (ADR 0052) against origin/main, and ASKS a human when the commit loosens them or changes
# them in a way no direction can be read from. Tightening and cosmetic edits pass silently. The
# design is docs/superpowers/specs/2026-09-20-guard-loosening-approval-design.md as amended by
# ADRs 0052 (what the list is), 0053 (merges) and 0054 (approval lifetime; attendedness); the
# specification of the behaviour is hooks/loosening-guard.test.sh.
#
# This is a thin wrapper. The judgement is in lib/loosening_guard.py and its siblings; this file only
# makes sure they can run, and turns every way they can fail into exit 2.
#
# FAIL CLOSED, the opposite of doc-guard.sh: this hook is on a path with a tiny blast radius (a commit
# that stages one of fourteen files) and a false refusal costs one commit, while a silent miss lets a
# loosening through. Exit 2 blocks; exit 1 would NOT block, so no path may end in 1 -- a checker crash is
# rewritten to 2 below. Never an `ask` on a refuse path: under a bypass-permissions session an ask is
# silently allowed and the command runs (measured, card task 0).
#
# Degraded environments (python3 or a library missing) refuse only a command that mentions "commit",
# so a missing tool cannot make every Bash call in every session fail -- the hook cannot inspect such a
# command, and a command without that word cannot run `git commit`.
#
# Momentum guardrail, not a security boundary: the approval record is written from inside the session.
# It gates a loosening being PROPOSED; PR review stays the last line.
#
# Exit 0 = allow (silent) or ask (JSON on stdout). Exit 2 = refused, reason on stderr.

set -u

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || HERE=""
LIB="$HERE/lib"
MAIN="$LIB/loosening_guard.py"
# Every file the checker imports or runs. A lone copy of this script (E10) must refuse, not fall open.
REQUIRED_LIBS="loosening_guard.py loosening_decide.py loosening_extract.py loosening_shell.py \
loosening_states.py loosening_watch.py secret_approval.py shell_segments.py classify-git-command.py"

log_decision() { # $1 decision, $2 class
  [ -n "${LOOSENING_GUARD_LOG:-}" ] || return 0
  printf 'decision=%s class=%s\n' "$1" "$2" >> "$LOOSENING_GUARD_LOG" 2>/dev/null || true
}

degraded=""
py="$(command -v python3)" || py=""
if [ -z "$py" ]; then
  degraded="python3 is not on PATH, so the staged files cannot be compared"
else
  for lib_file in $REQUIRED_LIBS; do
    if [ ! -r "$LIB/$lib_file" ]; then
      degraded="the checker library $LIB/$lib_file is missing or unreadable (hooks/lib must sit beside this script)"
      break
    fi
  done
fi

if [ -n "$degraded" ]; then
  payload="$(cat)"
  case "$payload" in
    *commit*)
      printf 'loosening-guard: %s; a command that mentions a commit is refused rather than waved through.\n' "$degraded" >&2
      log_decision refuse environment
      exit 2
      ;;
  esac
  log_decision skip unrelated
  exit 0
fi

LG_BASH="${BASH:-}" "$py" -I "$MAIN"
rc=$?
case "$rc" in
  0 | 2) exit "$rc" ;;
esac
printf 'loosening-guard: the checker failed unexpectedly (exit %s); refusing rather than guessing.\n' "$rc" >&2
log_decision refuse internal
exit 2
