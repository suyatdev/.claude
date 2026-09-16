#!/usr/bin/env bash
# slim-session-start.test.sh — unit tests for slim-session-start.sh.
# Runs the hook from inside throwaway git repos (no real repo or session state is
# touched), covering the Gherkin scenarios in docs/features/memory-system-split.md
# under "Feature: Session start loads the live thread and nothing else."
# Run: bash hooks/handoff/slim-session-start.test.sh
# The test bodies live in hooks/handoff/slim-session-start.test.d/*.sh, sourced below in
# order; this file keeps only the header, setup/helpers, and the summary/marker tail.
#
# ⚠️ RUN THIS WITH `env -u CLAUDE_PANE_AGENT` IF YOU ARE A PANED AGENT.
# slim-session-start.sh:53 short-circuits to exit 0 whenever CLAUDE_PANE_AGENT is
# set -- by design, so a pane agent never emits a handoff envelope. That variable
# is set inside every pane, so running this suite there gives a reproducible
# 13/29, exit 1. It is not a regression and the 16 "failures" are phantom.
# Measured 2026-08-20: CLAUDE_PANE_AGENT=1 -> 13/29; env -u -> 29/29.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK="$(cd "$(dirname "$0")" && pwd)/slim-session-start.sh"
# Physical path, not the one mktemp hands back — mirrors phase-guard.test.sh's note:
# on macOS mktemp -d returns the /var symlink form while `git rev-parse --show-toplevel`
# resolves to /private/var, and stat/mtime math below needs a path git actually agrees on.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

pass=0; fail=0; n=0

# Sets up a throwaway git repo at $TMP/repo-$n and cd's the caller there via a global.
REPO=""
new_repo() {
  n=$((n+1))
  REPO="$TMP/repo-$n"
  mkdir -p "$REPO/.claude"
  ( cd "$REPO" && git init -q )
}

got=0; out=""; err=""
run() { # $1 cwd, $2.. extra env assignments (VAR=val), optional
  local cwd="$1"; shift
  out="$TMP/out.$n"; err="$TMP/err.$n"
  ( cd "$cwd" && env "$@" bash "$HOOK" ) >"$out" 2>"$err"
  got=$?
}

ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

assert_exit0_empty() { # $1 desc
  local desc="$1"
  if [ "$got" -ne 0 ]; then bad "$desc" "want exit 0, got $got"; return; fi
  if [ -s "$out" ]; then bad "$desc" "want empty stdout, got: $(cat "$out")"; return; fi
  ok "$desc"
}

# Backdates a file's mtime by $2 hours. Mirrors the "Handoff whose writer stopped"
# fixture above so every staleness test shares one epoch-then-touch recipe.
backdate() { # $1 file $2 hours-ago
  local f="$1" hrs="$2" epoch
  epoch=$(( $(date +%s) - hrs*3600 ))
  # `touch -t` parses its stamp as LOCAL time, so the stamp must be formatted local (no
  # `-u`) -- a UTC-formatted stamp lands the mtime one TZ-offset in the future of the
  # intended epoch. Masked in every caller that backdates by hours well past the offset
  # (measured skew on this UTC-4 machine: +14400s with `-u`, 0s without).
  touch -t "$(date -r "$epoch" +%Y%m%d%H%M.%S)" "$f" 2>/dev/null \
    || TZ=UTC touch -d "@$epoch" "$f" 2>/dev/null
}

# write_fixed_lines FILE START END — appends "line NNNNN\n" for START..END, APPENDING to
# FILE (caller truncates first if a clean fixture is wanted). Every line is exactly 11
# bytes ("line " + 5 digits + "\n"), so a fixture built from this is distinguishable
# line-by-line (a partial line never matches the pattern) and its byte total is derivable
# by arithmetic instead of a magic number.
write_fixed_lines() {
  local file="$1" start="$2" end="$3" i
  i="$start"
  while [ "$i" -le "$end" ]; do
    printf 'line %05d\n' "$i" >> "$file"
    i=$((i+1))
  done
}

# shellcheck source=hooks/handoff/slim-session-start.test.d/10-envelope-and-tag.sh
source "$(dirname "$0")/slim-session-start.test.d/10-envelope-and-tag.sh"
# shellcheck source=hooks/handoff/slim-session-start.test.d/20-truncation.sh
source "$(dirname "$0")/slim-session-start.test.d/20-truncation.sh"
# shellcheck source=hooks/handoff/slim-session-start.test.d/30-snapshot-reaper.sh
source "$(dirname "$0")/slim-session-start.test.d/30-snapshot-reaper.sh"
# shellcheck source=hooks/handoff/slim-session-start.test.d/40-contract-and-guard-liveness.sh
source "$(dirname "$0")/slim-session-start.test.d/40-contract-and-guard-liveness.sh"

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
