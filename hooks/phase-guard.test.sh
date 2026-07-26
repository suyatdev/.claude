#!/usr/bin/env bash
# phase-guard.test.sh — unit tests for phase-guard.sh.
# Feeds PreToolUse JSON on stdin (the code path that actually runs in production) from
# inside throwaway git repos, so no real repo, branch, or session-flag state is touched.
# Run: bash hooks/phase-guard.test.sh
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/phase-guard.sh"
# Physical path, not the one mktemp hands back. On macOS `mktemp -d` returns the
# /var symlink form while `git rev-parse --show-toplevel` resolves to /private/var,
# so payload paths built from the symlink form would never relativize against the
# root (step 5) — every guarded case would fail open and pass for the wrong reason.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
# The Flag contract's test-time override — keeps $HOME/.claude/hooks/state untouched.
export PHASE_GUARD_STATE_DIR="$TMP/state"

pass=0; fail=0; n=0

payload() { # $1 tool_name, $2 path key (file_path|notebook_path), $3 absolute path
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":sys.argv[1],"tool_input":{sys.argv[2]:sys.argv[3]}}))' "$@"
}

# Every case in this file shares one assertion: exit 0, empty stdout, empty stderr.
allow_silent() { # $1 desc, $2 cwd, $3 payload
  local desc="$1" dir="$2" pay="$3" got out err
  n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
  ( cd "$dir" && printf '%s' "$pay" | bash "$HOOK" ) >"$out" 2>"$err"
  got=$?
  if [ "$got" -ne 0 ]; then
    printf 'FAIL — %s (want exit 0, got %s)\n' "$desc" "$got"; fail=$((fail+1)); return
  fi
  if [ -s "$out" ]; then
    printf 'FAIL — %s (stdout not empty: %s)\n' "$desc" "$(cat "$out")"; fail=$((fail+1)); return
  fi
  if [ -s "$err" ]; then
    printf 'FAIL — %s (stderr not empty: %s)\n' "$desc" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  printf 'ok   — %s\n' "$desc"; pass=$((pass+1))
}

mkrepo() { # $1 dir — an initialized repo on branch main carrying one commit
  mkdir -p "$1"
  ( cd "$1" && git init -q -b main && git config user.email t@t.t && git config user.name t &&
    git commit -q --allow-empty -m init )
}

planning_file() { # $1 repo, $2 relative path — a well-formed feature file at phase: planning
  mkdir -p "$(dirname "$1/$2")"
  printf -- '---\nphase: planning\nmodel_tier: high\nbranch: none\n---\n\n# fixture\n' > "$1/$2"
}

# OPTED — a fully opted-in repo: docs/features/a.md at phase: planning, on branch main,
# which no feature file claims. A guarded write here is a real deny, so each case below
# that expects exit 0 isolates the step it names instead of passing by accident.
OPTED="$TMP/opted"; mkrepo "$OPTED"; planning_file "$OPTED" docs/features/a.md
# BARE — a git repo that never opted in: no docs/features/.
BARE="$TMP/bare"; mkrepo "$BARE"
# NOREPO — a directory outside any git repository.
NOREPO="$TMP/norepo"; mkdir -p "$NOREPO"
# OUTSIDE — a directory outside OPTED, for the path-outside-the-root case.
OUTSIDE="$TMP/outside"; mkdir -p "$OUTSIDE"

# --- Group A1, examples 1-6: silent fail-open ---------------------------------------
# "Not applicable here" — the common case in every repo that never opted in.

allow_silent "A1.1 empty stdin (step 1)"                        "$OPTED"  ""
allow_silent "A1.2 not inside a git repository (step 2)"        "$NOREPO" "$(payload Write file_path "$NOREPO/src/x.sh")"
allow_silent "A1.3 no docs/features/ (step 3)"                  "$BARE"   "$(payload Write file_path "$BARE/src/x.sh")"
# A1.4: step 1 catches only *empty* stdin, so a truncated payload reaches the parser. An
# unhandled traceback would exit nonzero — a code a PreToolUse harness may read as deny.
allow_silent "A1.4 non-empty stdin that is not JSON (step 4)"   "$OPTED"  '{"hook_event_name":"PreToo'
allow_silent "A1.5 neither file_path nor notebook_path (step 4)" "$OPTED" '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"old_string":"a","new_string":"b"}}'
allow_silent "A1.6 path outside the repository root (step 5)"   "$OPTED"  "$(payload Write file_path "$OUTSIDE/x.sh")"

# --- The unguarded-path scenario: never blocked, even mid-planning -------------------
# This list IS the escape hatch (Q6): a repo locked by a stale planning file is always
# unlocked by editing that file, because feature files live under docs/**. settings.json
# is on it because it holds this hook's own registration — a guard that can block edits
# to its own off switch is a footgun.

for rel in docs/features/a.md docs/decisions/0011.md CODING_MEMORY.md coding-memory/x.md \
           .claude/session-state.md settings.json; do
  allow_silent "unguarded path: $rel" "$OPTED" "$(payload Write file_path "$OPTED/$rel")"
done

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
