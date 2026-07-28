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

# --- Group A3: the frontmatter contract ------------------------------------------------------
# A malformed feature file is SKIPPED, never guessed at — a one-character typo must not silently
# switch a CRITICAL gate off. Each case pairs the malformed bad.md with a well-formed good.md at
# phase: planning, so the deny still happens and the assertion isolates one thing: which file the
# message names. Without good.md a skipped bad.md would leave nothing to deny on, and every case
# would pass by exiting 0 for the wrong reason.

# Written literally rather than through feature_file(), because every shape here is one that
# helper cannot produce — being unproducible is exactly what makes them malformed.
a3_repo() { # $1 example id, $2 literal bad.md content — echoes the repo path
  local r="$TMP/a3-$1"
  mkrepo "$r"
  feature_file "$r" docs/features/good.md planning
  printf '%s' "$2" > "$r/docs/features/bad.md"
  printf '%s' "$r"
}

a3_case() { # $1 example id, $2 defect description, $3 literal bad.md content
  local r; r=$(a3_repo "$1" "$3")
  deny      "A3.$1 $2: still denies"   "$r" "$(payload Write file_path "$r/src/x.sh")"
  err_has   "A3.$1 names good.md"      'docs/features/good\.md'
  err_lacks "A3.$1 does not name bad.md" 'docs/features/bad\.md'
}

a3_case 1 'no opening --- on line 1'    '
---
phase: planning
---
'
a3_case 2 'opening --- but no closing ---' '---
phase: planning
model_tier: high
'
a3_case 3 'phase: plannning (typo)'     '---
phase: plannning
---
'
a3_case 4 'phase: Planning (wrong case)' '---
phase: Planning
---
'
# Two IDENTICAL phase: lines, not two contradictory ones. The contract counts lines, so a parser
# that deduplicated values would wrongly accept this — and a contradictory pair would additionally
# drag step 9 into the scenario, which is a different clause.
a3_case 5 'two phase: lines'            '---
phase: planning
phase: planning
---
'
a3_case 6 'no phase: line at all'       '---
model_tier: high
---
'

# 7. An absent branch: key means UNCLAIMED, not malformed. b.md is load-bearing, not scenery: a
#    deny needs some planning file, and without it this scenario would assert an exit 2 that step 7
#    cannot produce. It isolates that a.md's missing branch: leaves feat/a unclaimed, so b.md denies.
A3MB="$TMP/a3-missing-branch"; mkrepo "$A3MB"
feature_file "$A3MB" docs/features/a.md implementation
feature_file "$A3MB" docs/features/b.md planning
( cd "$A3MB" && git checkout -q -b feat/a )
deny    "A3.7 absent branch: is unclaimed, not malformed" "$A3MB" \
  "$(payload Write file_path "$A3MB/src/x.sh")"
err_has "A3.7 names docs/features/b.md" 'docs/features/b\.md'

# 8. Unknown keys between the fences are ignored, so model_tier and future keys stay compatible.
A3FC="$TMP/a3-forward-compat"; mkrepo "$A3FC"
mkdir -p "$A3FC/docs/features"
printf -- '---\nphase: planning\nmodel_tier: high\nunknown_future_key: whatever\n---\n\n# fixture\n' \
  > "$A3FC/docs/features/a.md"
deny    "A3.8 unknown frontmatter keys are forward-compatible" "$A3FC" \
  "$(payload Write file_path "$A3FC/src/x.sh")"
err_has "A3.8 names docs/features/a.md" 'docs/features/a\.md'

# --- git shims ---------------------------------------------------------------------------------
# Several scenarios below need a specific git subcommand to fail, return nothing, or be counted.
# Every shim falls through to the REAL git for anything it does not intercept — otherwise step 2's
# `rev-parse --show-toplevel` would break too and the case would pass by exiting at the wrong step.
# The real path is captured HERE, before any shim reaches PATH, so a shim can never recurse.
export GIT_SHIM_REAL; GIT_SHIM_REAL="$(command -v git)"

# shellcheck disable=SC2016  # the shim's own $@/$*/$GIT_SHIM_REAL must reach it unexpanded.
make_git_shim() { # $1 dir, $2 case body matched against " $* "
  mkdir -p "$1"
  { printf '#!/usr/bin/env bash\n'
    printf 'case " $* " in\n%s\nesac\n' "$2"
    printf 'exec "$GIT_SHIM_REAL" "$@"\n'
  } > "$1/git"
  chmod +x "$1/git"
}

with_git_shim() { # $1 shim dir, then an assertion function and its arguments
  local dir="$1" saved="$PATH"; shift
  PATH="$dir:$PATH"
  "$@"
  PATH="$saved"
}

# --- Group B rows 2-5, and the NotebookEdit regression --------------------------------------
# B2: the branch is claimed -> allow.
BCLAIM="$TMP/b-claimed"; mkrepo "$BCLAIM"
feature_file "$BCLAIM" docs/features/a.md implementation feat/a
( cd "$BCLAIM" && git checkout -q -b feat/a )
allow_silent "B2 claimed branch -> allow" "$BCLAIM" "$(payload Write file_path "$BCLAIM/src/x.sh")"

# --- Group B rows 2b/2c: a claim must come from the FRONTMATTER CONTRACT, not from raw text ---
# Escalation 3 from the implementation phase. Step 9 re-reads each file with its own grep+sed
# instead of the parser step 7 already ran, so anything that merely LOOKS like a claim anywhere
# in the file grants implementation permission on that branch. Both shapes below are fail-opens:
# the guard goes silent on a branch nothing legitimately claims. This is the direction that
# matters — the design accepts "easy to disarm", but only by editing frontmatter, which is a
# deliberate act; being disarmed by PROSE is not a decision anyone made.
#
# B2b: a planning file that merely DISCUSSES the contract in its body. Feature files are exactly
# the documents that quote `phase: implementation` and `branch: <name>` in prose — this very
# feature's own spec does, at length — so this is the common case, not a contrived one.
BPROSE="$TMP/b-prose"; mkrepo "$BPROSE"; mkdir -p "$BPROSE/docs/features"
{ printf -- '---\nphase: planning\nmodel_tier: high\n---\n\n# spec\n\n'
  printf -- 'When the gate opens the file advances to:\n'
  printf -- 'phase: implementation\n'
  printf -- 'and records its own branch as:\n'
  printf -- 'branch: feat/a\n'
} > "$BPROSE/docs/features/a.md"
( cd "$BPROSE" && git add -A && git commit -q -m init && git checkout -q -b feat/a )
deny "B2b prose describing a claim does not grant one" "$BPROSE" \
  "$(payload Write file_path "$BPROSE/src/x.sh")"

# B2c: a file step 7 SKIPPED as malformed (two phase: keys violates the frontmatter contract)
# must not be readable as a claim by a later step. A file the contract could not parse has no
# opinion the hook is entitled to act on — least of all the opinion that unlocks writing.
BMAL="$TMP/b-malformed-claim"; mkrepo "$BMAL"; mkdir -p "$BMAL/docs/features"
feature_file "$BMAL" docs/features/good.md planning
printf -- '---\nphase: implementation\nphase: implementation\nbranch: feat/a\n---\n' \
  > "$BMAL/docs/features/bad.md"
( cd "$BMAL" && git add -A && git commit -q -m init && git checkout -q -b feat/a )
deny "B2c a malformed file cannot claim a branch" "$BMAL" \
  "$(payload Write file_path "$BMAL/src/x.sh")"

# B3: one feature at planning must not revoke another feature's open gate.
BBOTH="$TMP/b-both"; mkrepo "$BBOTH"
feature_file "$BBOTH" docs/features/a.md implementation feat/a
feature_file "$BBOTH" docs/features/b.md planning
( cd "$BBOTH" && git checkout -q -b feat/a )
allow_silent "B3 another feature at planning does not revoke an open gate" "$BBOTH" \
  "$(payload Write file_path "$BBOTH/src/x.sh")"

# B4/B5: supersession. The working tree still reads planning; some OTHER branch's committed copy
# has moved on, which means that file's gate already opened and it must stop denying everywhere.
# Built once per phase because the branch copy is what is under test, not the working tree.
supersede_repo() { # $1 dir, $2 phase recorded on branch feat/a, $3 branch to end up on
  mkrepo "$1"
  feature_file "$1" docs/features/a.md planning
  ( cd "$1" && git add -A && git commit -q -m planning
    git checkout -q -b feat/a )
  feature_file "$1" docs/features/a.md "$2" feat/a
  ( cd "$1" && git commit -q -am "$2"
    git checkout -q main && git checkout -q -b "$3" )
}
BSUP="$TMP/b-superseded-impl"; supersede_repo "$BSUP" implementation hotfix/x
allow_silent "B4 a planning file superseded by implementation stops denying" "$BSUP" \
  "$(payload Write file_path "$BSUP/src/x.sh")"

BREV="$TMP/b-superseded-review"; supersede_repo "$BREV" review review/x
allow_silent "B5 a planning file superseded by review stops denying too" "$BREV" \
  "$(payload Write file_path "$BREV/src/x.sh")"

# The regression test for the file_path-only bug: NotebookEdit carries notebook_path and nothing
# else, so reading file_path alone would silently exempt an entire tool.
deny "B6 NotebookEdit is guarded like any other write" "$OPTED" \
  "$(payload NotebookEdit notebook_path "$OPTED/analysis.ipynb")"

# --- Group A1 examples 8-11: the git fail-opens ----------------------------------------------
# Steps 8 and 9 are the two most likely to fail on a large repo, and the only path onward from
# them is deny — so without these the hook would flip from fail-open to fail-everything.
SHIM_FER="$TMP/shim-fer"; make_git_shim "$SHIM_FER" '  *" for-each-ref "*) exit 1 ;;'
SHIM_CF="$TMP/shim-cf";   make_git_shim "$SHIM_CF"  '  *" cat-file "*) exit 1 ;;'
SHIM_RPF="$TMP/shim-rpf"; make_git_shim "$SHIM_RPF" '  *" --abbrev-ref "*) exit 1 ;;'
SHIM_RPE="$TMP/shim-rpe"; make_git_shim "$SHIM_RPE" '  *" --abbrev-ref "*) exit 0 ;;'

PL="$(payload Write file_path "$OPTED/src/x.sh")"
with_git_shim "$SHIM_FER" allow_silent "A1.8 for-each-ref exits nonzero (step 8)"    "$OPTED" "$PL"
with_git_shim "$SHIM_CF"  allow_silent "A1.9 cat-file --batch exits nonzero (step 8)" "$OPTED" "$PL"
with_git_shim "$SHIM_RPF" allow_silent "A1.10a rev-parse --abbrev-ref exits nonzero (step 9)" \
  "$OPTED" "$PL"
with_git_shim "$SHIM_RPE" allow_silent "A1.10b rev-parse --abbrev-ref prints nothing (step 9)" \
  "$OPTED" "$PL"

# 11 uses a real detached HEAD rather than a shim — it is reachable during any rebase or bisect,
# and the real thing is a stronger fixture than a simulation of it.
DETACHED="$TMP/detached"; mkrepo "$DETACHED"
feature_file "$DETACHED" docs/features/a.md planning
( cd "$DETACHED" && git add -A && git commit -q -m init && git checkout -q --detach )
allow_silent "A1.11 detached HEAD (step 9)" "$DETACHED" \
  "$(payload Write file_path "$DETACHED/src/x.sh")"

# An empty for-each-ref is NOT a failure: nothing supersedes, so every candidate survives to step 9
# and the deny stands. This exists to stop an implementer conflating "no branches" with "git broke".
SHIM_FEREMPTY="$TMP/shim-fer-empty"; make_git_shim "$SHIM_FEREMPTY" '  *" for-each-ref "*) exit 0 ;;'
with_git_shim "$SHIM_FEREMPTY" deny "A1.12 no local branches supersedes nothing but still denies" \
  "$OPTED" "$PL"

# --- The input-order parser -------------------------------------------------------------------
# `git cat-file --batch` output is ASYMMETRIC: a blob emits `<sha> blob <size>` WITHOUT echoing its
# request, while a miss echoes the request verbatim plus ` missing`. A parser that matches results
# to requests by anything other than input order mis-attributes every blob.
#
# THREE files, and the ordering of all three is load-bearing. `docs/features/*.md` globs
# alphabetically and branches come from for-each-ref sorted, so feat/a's requests are 1=alpha,
# 2=beta, 3=gamma:
#
#   alpha — planning, WITH a trailing newline, and carrying a literal `phase: implementation`
#           line in its PROSE, below the closing fence. Must survive.
#   beta  — superseded on feat/a (implementation), committed with NO trailing newline. Must drop.
#   gamma — deleted on feat/a, so its record is the asymmetric `missing` echo. Must survive.
#
# ROUNDS 1-4 HAD THIS AS A PLACEBO and the round-4 "one fixture reorder" diagnosis was ALSO wrong —
# reversing alpha/beta was measured and all three mutants still escaped. The actual requirement is
# that a NORMAL trailing-newline blob be READ BEFORE the superseded one, because that is the only
# arrangement in which a desync can still corrupt the record that decides the outcome. With the
# superseded file at request 1 or 2 its mark is already set before any drift begins, so the drift
# lands only on planning files whose mis-parse changes no answer.
#
# Each of the three claims now has a mutant that this case, and only this case, catches:
#   drop the trailing-LF skip  -> alpha's extra LF is read as a record header, beta desyncs and is
#                                 never marked -> beta survives -> `err_lacks beta` fires.
#   collapse input-order attribution -> beta's implementation mark lands on alpha -> alpha drops.
#   unbound the phase match    -> alpha's PROSE line marks it superseded -> alpha drops.
ORDER="$TMP/input-order"; mkrepo "$ORDER"
# mkdir -p is not decorative: feature_file() does its own, but this file is written literally
# (it needs prose feature_file cannot produce) and a missing dir would silently drop alpha.
mkdir -p "$ORDER/docs/features"
{ printf -- '---\nphase: planning\nmodel_tier: high\n---\n\n# fixture\n\n'
  printf -- 'Prose that discusses the contract, which must NOT supersede anything:\n'
  printf -- 'phase: implementation\n'
} > "$ORDER/docs/features/alpha.md"
feature_file "$ORDER" docs/features/beta.md  planning
feature_file "$ORDER" docs/features/gamma.md planning
( cd "$ORDER" && git add -A && git commit -q -m planning && git checkout -q -b feat/a )
printf -- '---\nphase: implementation\nbranch: feat/a\n---' > "$ORDER/docs/features/beta.md"
( cd "$ORDER" && git rm -q docs/features/gamma.md && git commit -q -am moved
  git checkout -q main && git checkout -q -b hotfix/x )
deny      "C0 input-order: superseded beta drops, alpha and gamma survive" "$ORDER" \
  "$(payload Write file_path "$ORDER/src/x.sh")"
err_has   "C0 names docs/features/alpha.md — prose phase: is not a gate" 'docs/features/alpha\.md'
err_has   "C0 names docs/features/gamma.md — the missing-record echo"    'docs/features/gamma\.md'
err_lacks "C0 does not name docs/features/beta.md"                       'docs/features/beta\.md'

# --- Group C: one subprocess, not O(branches) -------------------------------------------------
# Asserted structurally, not behaviourally: the O(branches) implementation produces the same
# answers, so a test that checked answers would pass either way and measure nothing.
export GIT_SHIM_ARGV_LOG="$TMP/git-argv.log" GIT_SHIM_STDIN_LOG="$TMP/git-stdin.log"
: > "$GIT_SHIM_ARGV_LOG"; : > "$GIT_SHIM_STDIN_LOG"
SHIM_COUNT="$TMP/shim-count"
# shellcheck disable=SC2016  # same as make_git_shim: the shim resolves these, not this script.
make_git_shim "$SHIM_COUNT" '  *" cat-file "*) printf "%s\n" "$*" >> "$GIT_SHIM_ARGV_LOG"; tee -a "$GIT_SHIM_STDIN_LOG" | "$GIT_SHIM_REAL" "$@"; exit $? ;;
  *) printf "%s\n" "$*" >> "$GIT_SHIM_ARGV_LOG" ;;'

# ORDER has 3 local branches (main, feat/a, hotfix/x) and 2 candidate planning files.
with_git_shim "$SHIM_COUNT" deny "C1 the counted run still denies" "$ORDER" \
  "$(payload Write file_path "$ORDER/src/x.sh")"

count_is() { # $1 desc, $2 expected count, $3 log file, $4 extended regex
  local got; got=$(grep -Ec -- "$4" "$3" 2>/dev/null || true)
  if [ "${got:-0}" -eq "$2" ]; then
    printf 'ok   — %s\n' "$1"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$1" "$2" "${got:-0}"; fail=$((fail+1))
  fi
}

count_is "C2 exactly one cat-file --batch invocation" 1 "$GIT_SHIM_ARGV_LOG" 'cat-file --batch'
count_is "C3 exactly one for-each-ref invocation"     1 "$GIT_SHIM_ARGV_LOG" 'for-each-ref'
count_is "C4 zero git show invocations"               0 "$GIT_SHIM_ARGV_LOG" '(^| )show( |$)'
count_is "C5 cat-file is fed 3 branches x 3 files"    9 "$GIT_SHIM_STDIN_LOG" '^[^:]+:docs/features/'

# --- Group A2: fail-open, but audible ----------------------------------------------------------
# Six of the eight fail-open exits mean "not applicable here" and are correctly silent. These two
# mean something else: THIS REPO OPTED IN AND THE GUARD COULD NOT EVALUATE IT. Without a line, a
# working guard and a dead one are byte-identical — every ⊘ emits nothing and Group A1 asserts
# exactly that, so the suite that proves the silence is also what hides the death.
#
# Both still exit 0, and both print AT MOST ONCE PER SESSION: per-write printing is not acceptable
# on a hook that fires on every write. Line COUNT is therefore asserted, not merely a match — a
# match-only assertion cannot see the per-write regression the flag exists to prevent.

# What the line must carry: the guard's own name (an unattributed line on a shared stderr is
# noise), and the reason, distinguishably — A2.6/A2.7 below turn on the two being tellable apart.
NOPY_RE='^phase-guard: .*[Pp]ython'
NOPARSE_RE='^phase-guard: .*docs/features'

# The audible fail-open assertion: exit 0, empty stdout, and EXACTLY ONE stderr line matching.
allow_audible() { # $1 desc, $2 cwd, $3 payload, $4 extended regex the line must match
  local desc="$1" lines
  _run "$2" "$3"
  if [ "$got" -ne 0 ]; then
    printf 'FAIL — %s (want exit 0, got %s)\n' "$desc" "$got"; fail=$((fail+1)); return
  fi
  if [ -s "$out" ]; then
    printf 'FAIL — %s (stdout not empty: %s)\n' "$desc" "$(cat "$out")"; fail=$((fail+1)); return
  fi
  lines=$(grep -c '' "$err" 2>/dev/null || true); [ -n "$lines" ] || lines=0
  if [ "$lines" -ne 1 ]; then
    printf 'FAIL — %s (want exactly 1 stderr line, got %s: %s)\n' "$desc" "$lines" "$(cat "$err")"
    fail=$((fail+1)); return
  fi
  if ! grep -Eq -- "$4" "$err"; then
    printf 'FAIL — %s (line does not match /%s/: %s)\n' "$desc" "$4" "$(cat "$err")"
    fail=$((fail+1)); return
  fi
  printf 'ok   — %s\n' "$desc"; pass=$((pass+1))
}

# A payload carrying a session_id. The Flag contract keys the noparse exit off THIS in preference
# to the environment; the plain `payload` helper omits it, which exercises the fallback.
payload_sid() { # $1 tool_name, $2 path key, $3 absolute path, $4 session_id
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":sys.argv[1],"tool_input":{sys.argv[2]:sys.argv[3]},"session_id":sys.argv[4]}))' "$@"
}

with_path() { # $1 replacement PATH, then an assertion function and its arguments
  local newpath="$1" saved="$PATH"; shift
  PATH="$newpath"
  "$@"
  PATH="$saved"
}

with_state_dir() { # $1 PHASE_GUARD_STATE_DIR value, then an assertion function and its arguments
  local saved="$PHASE_GUARD_STATE_DIR"; export PHASE_GUARD_STATE_DIR="$1"; shift
  "$@"
  export PHASE_GUARD_STATE_DIR="$saved"
}

# NOPYBIN — a PATH carrying every utility the hook and these assertions can reach EXCEPT an
# interpreter, so "no python" is the ONLY difference between this fixture and a normal run.
# Built by symlink rather than by filtering the real PATH: a filter has to guess which directories
# hold a python, and a missed pyenv/conda shim would leave the hook working and the case green for
# the wrong reason. awk/sed/head are included though step 4 exits before them — their absence would
# make a later failure read as "no python" when it was "no awk".
NOPYBIN="$TMP/nopybin"; mkdir -p "$NOPYBIN"
for b in bash cat git grep mkdir awk sed head; do
  ln -sf "$(command -v "$b")" "$NOPYBIN/$b"
done

# NOPARSE — opted in, two feature files, BOTH malformed, by two different defects. A one-file
# fixture cannot tell "every file was skipped" from "the only file was skipped", and the exit is
# defined on the former.
NOPARSE="$TMP/noparse"; mkrepo "$NOPARSE"; mkdir -p "$NOPARSE/docs/features"
printf 'no frontmatter fence at all\n'                        > "$NOPARSE/docs/features/a.md"
printf -- '---\nphase: planning\nphase: review\n---\n'        > "$NOPARSE/docs/features/b.md"

PL_OPTED="$(payload Write file_path "$OPTED/src/x.sh")"
PL_NOPARSE="$(payload Write file_path "$NOPARSE/src/x.sh")"

# Zero files is NOT this case — it makes "every file was skipped" vacuously true and would fire in
# any repo that created the directory and nothing else. Already pinned silent above (the
# EMPTYFEATURES case at step 7); not repeated here, because two assertions of one property means a
# later change can satisfy one and break the other.

# A2.1 — step 4, the no-interpreter exit. The guard is off in EVERY repo until PATH is fixed.
export CLAUDE_CODE_SESSION_ID=a2-nopython
with_path "$NOPYBIN" allow_audible "A2.1 no interpreter says so (step 4)" \
  "$OPTED" "$PL_OPTED" "$NOPY_RE"
with_path "$NOPYBIN" allow_silent "A2.2 a second write in the same session adds no line" \
  "$OPTED" "$PL_OPTED"

# A2.3 is what makes the flag a SESSION flag: without it, a write-once-per-machine implementation
# — or a permanent flag with no session in its key — satisfies A2.2 and measures nothing.
export CLAUDE_CODE_SESSION_ID=a2-nopython-2
with_path "$NOPYBIN" allow_audible "A2.3 a different session says so again" \
  "$OPTED" "$PL_OPTED" "$NOPY_RE"

# A2.4 — step 7, the every-file-skipped exit. This repo opted in and the guard cannot read its
# own input, which is not the same as having nothing to say.
export CLAUDE_CODE_SESSION_ID=a2-noparse
allow_audible "A2.4 every feature file unparseable says so (step 7)" \
  "$NOPARSE" "$PL_NOPARSE" "$NOPARSE_RE"
allow_silent "A2.5 a second write in the same session adds no line" "$NOPARSE" "$PL_NOPARSE"

# A2.6/A2.7 — two independent flags, not one "already warned" bit. These deliberately reuse the
# sessions above, so they run against real accumulated flag state rather than a simulation of it:
# a shared flag would make whichever reason fired first silence the other permanently, and the
# session would be told the guard is dead for a reason that is not the live one.
export CLAUDE_CODE_SESSION_ID=a2-nopython
allow_audible "A2.6 noparse still speaks in a session where nopython already fired" \
  "$NOPARSE" "$PL_NOPARSE" "$NOPARSE_RE"
export CLAUDE_CODE_SESSION_ID=a2-noparse
with_path "$NOPYBIN" allow_audible "A2.7 nopython still speaks in a session where noparse fired" \
  "$OPTED" "$PL_OPTED" "$NOPY_RE"

# A2.8-A2.10 — the noparse key is the PAYLOAD's session_id, in preference to the environment.
# The environment is deliberately changed under A2.9 and held constant under A2.10, so an
# implementation that read $CLAUDE_CODE_SESSION_ID first fails both: A2.9 would speak again and
# A2.10 would fall silent. Asserting only "the second one is quiet" cannot separate the two keys.
export CLAUDE_CODE_SESSION_ID=a2-sid-env
PL_SID1="$(payload_sid Write file_path "$NOPARSE/src/x.sh" a2-sid-payload)"
PL_SID2="$(payload_sid Write file_path "$NOPARSE/src/x.sh" a2-sid-payload-2)"
allow_audible "A2.8 a payload-borne session_id speaks once" "$NOPARSE" "$PL_SID1" "$NOPARSE_RE"
export CLAUDE_CODE_SESSION_ID=a2-sid-env-changed
allow_silent "A2.9 same payload session_id, changed environment -> still quiet" \
  "$NOPARSE" "$PL_SID1"
export CLAUDE_CODE_SESSION_ID=a2-sid-env
allow_audible "A2.10 new payload session_id, unchanged environment -> speaks" \
  "$NOPARSE" "$PL_SID2" "$NOPARSE_RE"

# A2.11/A2.12 — neither key available: the literal `nosession`, as dispatch-pane-agent.sh:70
# writes and pane-dispatch-guard.sh:55 reads. Degrades to once-per-machine-until-cleaned, which is
# the accepted floor — never to once-per-write.
unset CLAUDE_CODE_SESSION_ID
allow_audible "A2.11 no session id anywhere still speaks once" \
  "$NOPARSE" "$PL_NOPARSE" "$NOPARSE_RE"
allow_silent "A2.12 ...and falls back to a shared nosession key rather than re-speaking" \
  "$NOPARSE" "$PL_NOPARSE"

# A2.13/A2.14 — the deliberate divergence from context-handoff-watch.sh:42, which bails silently
# (`|| exit 0`) when its store is unwritable. That sibling's flag gates a nudge; this one gates the
# warning that the guard is DEAD, and a fix for silent failure that itself fails silently is the
# original problem one level up. The store is blocked by a REGULAR FILE standing where the
# directory would go — `mkdir -p` cannot succeed against that even for root, which a chmod can.
export CLAUDE_CODE_SESSION_ID=a2-unwritable
: > "$TMP/blocked"
with_state_dir "$TMP/blocked/state" allow_audible \
  "A2.13 an unwritable state dir still speaks, and still exits 0" \
  "$NOPARSE" "$PL_NOPARSE" "$NOPARSE_RE"
# The accepted cost of that choice, asserted so it stays a known trade and not a surprise: with no
# flag persistable, every write speaks. Silence here would mean the flag landed somewhere the
# contract never named.
with_state_dir "$TMP/blocked/state" allow_audible \
  "A2.14 ...and speaks again, since no flag could be written" \
  "$NOPARSE" "$PL_NOPARSE" "$NOPARSE_RE"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
