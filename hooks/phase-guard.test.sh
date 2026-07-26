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

got=0; out=""; err=""
_run() { # $1 cwd, $2 payload — leaves the exit code in $got, the streams in $out/$err
  n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
  ( cd "$1" && printf '%s' "$2" | bash "$HOOK" ) >"$out" 2>"$err"
  got=$?
}

# The fail-open assertion: exit 0, empty stdout, empty stderr.
allow_silent() { # $1 desc, $2 cwd, $3 payload
  local desc="$1"
  _run "$2" "$3"
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

# The deny assertion: exit 2 and empty stdout, which the Output contract requires on
# every path. Deliberately NO stderr assertion — the deny message is a later task, and
# asserting it here would leave that task unable to make this one green.
deny() { # $1 desc, $2 cwd, $3 payload
  local desc="$1"
  _run "$2" "$3"
  if [ "$got" -ne 2 ]; then
    printf 'FAIL — %s (want exit 2, got %s)\n' "$desc" "$got"; fail=$((fail+1)); return
  fi
  if [ -s "$out" ]; then
    printf 'FAIL — %s (stdout not empty: %s)\n' "$desc" "$(cat "$out")"; fail=$((fail+1)); return
  fi
  printf 'ok   — %s\n' "$desc"; pass=$((pass+1))
}

# Element assertions for the deny message. `deny` leaves its captured stderr in $err, so
# these read that file instead of re-running the hook — every element is then checked
# against one and the same deny, not against separate runs that could disagree.
err_has() { # $1 desc, $2 extended regex that must match some line of stderr
  if grep -Eq -- "$2" "$err"; then
    printf 'ok   — %s\n' "$1"; pass=$((pass+1))
  else
    printf 'FAIL — %s (no stderr line matches /%s/)\n' "$1" "$2"; fail=$((fail+1))
  fi
}

err_lacks() { # $1 desc, $2 extended regex that must match nothing in stderr
  if grep -Eq -- "$2" "$err"; then
    printf 'FAIL — %s (stderr matches /%s/: %s)\n' "$1" "$2" "$(grep -Em1 -- "$2" "$err")"
    fail=$((fail+1))
  else
    printf 'ok   — %s\n' "$1"; pass=$((pass+1))
  fi
}

mkrepo() { # $1 dir — an initialized repo on branch main carrying one commit
  mkdir -p "$1"
  ( cd "$1" && git init -q -b main && git config user.email t@t.t && git config user.name t &&
    git commit -q --allow-empty -m init )
}

feature_file() { # $1 repo, $2 relative path, $3 phase, $4 branch value ("" omits the key)
  local dest="$1/$2" br="${4:-}"
  mkdir -p "$(dirname "$dest")"
  { printf -- '---\nphase: %s\nmodel_tier: high\n' "$3"
    [ -n "$br" ] && printf 'branch: %s\n' "$br"
    printf -- '---\n\n# fixture\n'
  } > "$dest"
}

# OPTED — a fully opted-in repo: docs/features/a.md at phase: planning, on branch main,
# which no feature file claims. A guarded write here is a real deny, so each case below
# that expects exit 0 isolates the step it names instead of passing by accident.
OPTED="$TMP/opted"; mkrepo "$OPTED"; feature_file "$OPTED" docs/features/a.md planning none
# BARE — a git repo that never opted in: no docs/features/.
BARE="$TMP/bare"; mkrepo "$BARE"
# NOREPO — a directory outside any git repository.
NOREPO="$TMP/norepo"; mkdir -p "$NOREPO"
# OUTSIDE — a directory outside OPTED, for the path-outside-the-root case.
OUTSIDE="$TMP/outside"; mkdir -p "$OUTSIDE"
# NOPLANNING — opted in, but nothing sits at phase: planning.
NOPLANNING="$TMP/noplanning"; mkrepo "$NOPLANNING"
feature_file "$NOPLANNING" docs/features/a.md implementation
# EMPTYFEATURES — docs/features/ exists and holds nothing at all.
EMPTYFEATURES="$TMP/emptyfeatures"; mkrepo "$EMPTYFEATURES"; mkdir -p "$EMPTYFEATURES/docs/features"
# DENYMSG — the deny-message fixture. TWO files at phase: planning, because the contract
# says "every offending path": a message that named only the first would pass a
# single-file check. The branch name is deliberately odd rather than the scenario's
# `main` — "stderr names the current branch" is not falsifiable against a string a deny
# message could plausibly contain for some other reason.
DENYMSG="$TMP/denymsg"; mkrepo "$DENYMSG"
feature_file "$DENYMSG" docs/features/alpha.md planning
feature_file "$DENYMSG" docs/features/beta.md planning
( cd "$DENYMSG" && git checkout -q -b wip/unclaimed-xyz )

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

# --- Group B row 1: the core deny ------------------------------------------------------
# A feature file at phase: planning, on a branch no feature file claims, and a write to
# source. This is the case the whole hook exists for.

deny "B1 planning file + unclaimed branch -> deny" "$OPTED" "$(payload Write file_path "$OPTED/src/x.sh")"

# --- Step 7's two silent fail-opens -----------------------------------------------------
# The second is the one worth pinning: zero files makes "every file was skipped" vacuously
# true, so a repo that created docs/features/ and nothing else must stay SILENT rather than
# firing the audible cannot-evaluate line.

allow_silent "A1.7 nothing at phase: planning (step 7)" "$NOPLANNING" \
  "$(payload Write file_path "$NOPLANNING/src/x.sh")"
allow_silent "docs/features/ exists but is empty (step 7, silent)" "$EMPTYFEATURES" \
  "$(payload Write file_path "$EMPTYFEATURES/src/x.sh")"

# --- The deny-message contract ------------------------------------------------------------
# All four required elements, or the block is unactionable — a session that is told "no"
# without being told which file said no, or how to open the gate, will go looking for a
# bypass. That is the failure this message exists to prevent, so each element is asserted
# separately: a message missing one of the four should fail on that one, and name it.
#
# This is the first test in the suite that touches stderr at all. Everything above asserts
# either an empty stderr (the allows) or says nothing about it (the deny), which is what
# let the bare `exit 2` of the previous task be green.

deny "deny-message: two planning files + unclaimed branch" "$DENYMSG" \
  "$(payload Write file_path "$DENYMSG/src/x.sh")"

# 1. Every offending feature-file path, each with its own phase:. Same-line, because a
#    message listing the paths in one place and the word "planning" in another leaves a
#    reader guessing which file is at which phase once the list runs past one entry.
err_has "element 1: names docs/features/alpha.md with its phase" 'docs/features/alpha\.md.*phase: planning'
err_has "element 1: names docs/features/beta.md with its phase"  'docs/features/beta\.md.*phase: planning'

# 2. The current branch. The deny is branch-scoped, so a message that omits the branch
#    omits the reason.
err_has "element 2: names the current branch" 'wip/unclaimed-xyz'

# 3. Both legitimate fixes. The first is the literal gate phrase plus both frontmatter
#    edits it authorizes; the second is the stale-file exit, which is the one a session
#    blocked by an abandoned feature file actually needs.
err_has "element 3a: the literal gate phrase"        'gate confirmed'
err_has "element 3a: advancing phase:"               'phase: implementation'
err_has "element 3a: recording the branch"           'record.*branch:'
err_has "element 3b: the stale-file exit"            'stale.*delete|delete.*stale'

# 4. The no-bypass clause, and that it stays narrow. Q6 built no bypass env var, so the
#    message says so — but the Bash-tool write surface is unguarded (Non-goals), so a
#    message claiming there is no way around the guard would be false, and a safety
#    message that overclaims teaches sessions to distrust the true parts too.
err_has   "element 4: no bypass environment variable" 'no bypass environment variable'
err_lacks "element 4: does not overclaim a closed surface" \
  'no way around|cannot be bypassed|impossible to bypass|there is no bypass\.'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
