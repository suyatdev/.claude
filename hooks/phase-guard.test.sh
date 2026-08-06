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

# A payload carrying a session_id. The Flag contract keys the noparse exit off THIS in preference
# to the environment; the plain `payload` helper omits it, which exercises the fallback.
#
# Defined up here, beside `payload`, rather than beside the Group A2 cases that first needed it:
# the step-7 silent assertions below also need it, and they run several hundred lines earlier.
payload_sid() { # $1 tool_name, $2 path key, $3 absolute path, $4 session_id
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":sys.argv[1],"tool_input":{sys.argv[2]:sys.argv[3]},"session_id":sys.argv[4]}))' "$@"
}

# Asserts NO once-per-session flag was written for $1. The audible fail-opens are suppressed after
# their first firing, so "stderr was empty" alone cannot distinguish "correctly silent" from
# "already warned under this key". Every silent assertion that could plausibly warn therefore
# pins its own session id and checks the store directly.
no_flag_for() { # $1 session id, $2 description
  local hits; hits=$(find "$PHASE_GUARD_STATE_DIR" -name "*-$1" 2>/dev/null)
  if [ -n "$hits" ]; then
    printf 'FAIL — %s (flag written: %s)\n' "$2" "$hits"; fail=$((fail+1)); return
  fi
  printf 'ok   — %s\n' "$2"; pass=$((pass+1))
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

# The four audible reasons. Every one names the guard and its own distinguishable cause; A2.6/A2.7
# depend on two of them being tellable apart, and Group A1's git cases on a third.
NOPY_RE='^phase-guard: .*[Pp]ython'
NOPARSE_RE='^phase-guard: .*could not be read as a feature card'
NOLIST_RE='^phase-guard: .*cannot be listed'
NOGIT_RE='^phase-guard: .*git query'
NOPAYLOAD_RE='^phase-guard: .*payload'
NOGITBIN_RE='^phase-guard: .*no git on PATH'
DETACHED_RE='^phase-guard: .*detached HEAD'
# Deliberately does not contain the word "payload": NOPAYLOAD_RE would otherwise match this
# message too, and A2.6/A2.7's requirement that every reason be tellable apart is the point.
NORESOLVE_RE='^phase-guard: .*could not be resolved'
NOREPOREAD_RE='^phase-guard: .*cannot be read'

# The audible fail-open assertion: exit 0, empty stdout, and EXACTLY ONE stderr line matching.
# The line count is asserted, not merely a match — a match-only assertion cannot see a per-write
# regression, which is the whole reason the once-per-session flag exists.
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
allow_silent "A1.2 not inside a git repository (step 4)"        "$NOREPO" "$(payload Write file_path "$NOREPO/src/x.sh")"
allow_silent "A1.3 no docs/features/ (step 4)"                  "$BARE"   "$(payload Write file_path "$BARE/src/x.sh")"
# A1.4: step 1 catches only *empty* stdin, so a truncated payload reaches the parser. An
# unhandled traceback would exit nonzero — a code a PreToolUse harness may read as deny.
# A1.4/A1.5 CONVERTED from asserted-silent, for the same reason as A1.8-A1.10b below. $OPTED holds
# an un-superseded planning card on an unclaimed branch: a valid payload here DENIES. Feed the same
# fixture a truncated payload, a non-JSON one, or one whose path key has been renamed, and it
# allowed in silence — the guard switched off by a malformed message, at the earliest step of all.
# The suite asserted that silence a few lines above the four git cases it also asserted, which is
# how one bug class survived four judge rounds reading this file as evidence of correctness.
export CLAUDE_CODE_SESSION_ID=a1-nojson
allow_audible "A1.4 non-empty stdin that is not JSON (step 3) says so" "$OPTED" \
  '{"hook_event_name":"PreToo' "$NOPAYLOAD_RE"
export CLAUDE_CODE_SESSION_ID=a1-nopath
allow_audible "A1.5 neither file_path nor notebook_path (step 3) says so" "$OPTED" \
  '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"old_string":"a","new_string":"b"}}' \
  "$NOPAYLOAD_RE"
allow_silent "A1.6 path outside the repository root (step 5)"   "$OPTED"  "$(payload Write file_path "$OUTSIDE/x.sh")"

# --- The unguarded-path scenario: never blocked, even mid-planning -------------------
# This list IS the escape hatch (Q6): a repo locked by a stale planning file is always
# unlocked by editing that file, because feature files live under docs/**. settings.json
# is on it because it holds this hook's own registration — a guard that can block edits
# to its own off switch is a footgun.

for rel in docs/features/a.md docs/decisions/0011.md CODING_MEMORY.md coding-memory/x.md \
           .claude/session-state.md settings.json \
           projects/-Users-x--claude/memory/feedback_x.md \
           projects/-Users-x--claude/memory/MEMORY.md; do
  allow_silent "unguarded path: $rel" "$OPTED" "$(payload Write file_path "$OPTED/$rel")"
done

# projects/*/memory/* is where the harness's own memory tool writes. Omitting it
# meant EVERY memory write was refused while any feature file sat at planning --
# i.e. for the whole of a multi-branch register -- while rules/gates.md promised
# that documentation and memory paths are never blocked.
#
# The exemption is the memory directory, NOT projects/ at large: a repo could
# hold source under projects/, and this hook is the only thing standing between
# a planning phase and an unreviewed edit to it.
deny "projects/ is not exempt outside memory/" "$OPTED" "$(payload Write file_path "$OPTED/projects/p/app.sh")"
deny "a file merely NAMED memory is not exempt" "$OPTED" "$(payload Write file_path "$OPTED/projects/p/memory.sh")"

# --- Group B row 1: the core deny ------------------------------------------------------
# A feature file at phase: planning, on a branch no feature file claims, and a write to
# source. This is the case the whole hook exists for.

deny "B1 planning file + unclaimed branch -> deny" "$OPTED" "$(payload Write file_path "$OPTED/src/x.sh")"

# --- Step 7's two silent fail-opens -----------------------------------------------------
# The second is the one worth pinning: zero files makes "every file was skipped" vacuously
# true, so a repo that created docs/features/ and nothing else must stay SILENT rather than
# firing the audible cannot-evaluate line.

#
# Both pin their OWN session id, and both then assert the flag store is untouched. Without that
# the pair is order-dependent: `allow_silent` only checks that stderr was empty, and the noparse
# line is suppressed after its first firing under a given key. Every case here shares the
# `nosession` fallback key, so ANY earlier case that warned would make these two pass for the
# wrong reason — silent because already-warned, not silent because correct.
#
# Measured before pinning: no earlier case writes that flag today, and mutating away the
# `nfiles > 0` guard is still caught. So this is not a repair of a broken assertion — it is
# removing a dependency on test order that nothing was enforcing. (The round-3 note claimed
# "A1.7 warns first and suppresses the empty case behind it"; A1.7 parses its file fine and
# never warns at all, so that specific mechanism was wrong even though the exposure is real.)
allow_silent "A1.7 nothing at phase: planning (step 7)" "$NOPLANNING" \
  "$(payload_sid Write file_path "$NOPLANNING/src/x.sh" sid-a17)"
no_flag_for sid-a17 "A1.7 is silent because nothing is at planning, not because it already warned"
allow_silent "docs/features/ exists but is empty (step 7, silent)" "$EMPTYFEATURES" \
  "$(payload_sid Write file_path "$EMPTYFEATURES/src/x.sh" sid-emptyfeatures)"
no_flag_for sid-emptyfeatures "empty docs/features/ writes no flag — the nfiles > 0 guard held"

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
# A3.1 above CANNOT isolate the `NR == 1` clause. That clause does two jobs — reject a file whose
# line 1 is not `---`, and `next` past line 1 so an opening fence never trips the closing-fence
# rule. A3.1's shape is still skipped when the REJECTION is removed: its first `---` lands on
# line 2, trips the closing rule with nphase still 0, and the file fails the contract by a
# different route. The verdict never moves, so the assertion cannot see the clause it names.
#
# A3.1b is the shape that discriminates. Line 1 is junk, and `phase:` sits between it and the
# first fence — so with the rejection removed the parser skips line 1, reads phase=planning,
# closes cleanly on line 3 with nphase == 1, and PRINTS `planning`. bad.md becomes a second
# planning file and the deny names it; `err_lacks` is the assertion that moves.
#
# Mutation-checked against BOTH faithful mutants, because the first one tried was too blunt to
# mean anything: deleting the whole rule makes every well-formed file fail (line 1's own `---`
# closes the frontmatter immediately), which fails 41 assertions and isolates nothing. The
# honest mutant is `NR == 1 { next }` — rejection gone, line 1 still consumed. A3.1b catches
# that one and A3.1 does not, which is exactly the gap this case was added to close.
a3_case 1b 'junk line 1, phase: above the fence — isolates the line-1 clause' 'not a fence
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
# 5b. The `nbranch > 1` clause, which nothing else reaches: the suite stayed 88/0 with it deleted.
# Counting `branch:` lines only matters if a second one could CHANGE the answer, so the shape has
# to make the duplicate load-bearing rather than decorative. bad.md claims implementation and lists
# two branches, the last of which is the branch under test — awk keeps the last assignment, so with
# the clause removed bad.md parses, claims main, and the deny becomes an ALLOW. With the clause
# intact bad.md is skipped, nothing claims main, and good.md denies as usual. `deny` is the
# assertion that moves, and it moves all the way to exit 0 rather than to a different message.
a3_case 5b 'two branch: lines, the last one claiming this branch' '---
phase: implementation
branch: somewhere-else
branch: main
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
# Every shim falls through to the REAL git for anything it does not intercept — otherwise step 4's
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

# THESE FOUR WERE ASSERTED SILENT, AND THAT WAS THE BUG CLASS ITSELF.
#
# $OPTED holds an un-superseded planning card on an unclaimed branch — the hook was on its way to
# DENY. Steps 8 and 9 then fail, and it allows instead. That is not "not applicable here"; it is
# the guard being switched off by a transient git failure, in precisely the state where it was
# about to do its job, and the suite ENFORCED the silence rather than merely missing it.
#
# Four judge rounds each found one instance of this class one step earlier than the last. The
# audit that followed enumerated every exit instead of chasing the next one, and the rule that
# falls out is: once the hook knows THIS REPO OPTED IN, any later inability to COMPLETE the
# evaluation must be AUDIBLE — these four qualify twice over, since a planning card is active here
# too. Everything upstream of that knowledge ("no payload", "not a repo", "never opted in") stays
# silent, and so does an evaluation that RAN and returned "not applicable", because there the hook
# genuinely has nothing to say. (The planning card was stated as a second precondition here until
# round 5 falsified it; the boundary is the opt-in test alone. See Group A4.)
#
# Each still exits 0 and each still speaks at most once per session, so a flapping git costs one
# line per session, not one per write.
each_shim_speaks() { # $1 desc, $2 shim dir — a fresh session id per case, or the flag suppresses it
  export CLAUDE_CODE_SESSION_ID="a1-$3"
  with_git_shim "$2" allow_audible "$1" "$OPTED" "$PL" "$NOGIT_RE"
}
each_shim_speaks "A1.8 for-each-ref exits nonzero (step 8) says so"    "$SHIM_FER" fer
each_shim_speaks "A1.9 cat-file --batch exits nonzero (step 8) says so" "$SHIM_CF"  cf
each_shim_speaks "A1.10a rev-parse --abbrev-ref exits nonzero (step 9) says so" "$SHIM_RPF" rpf
each_shim_speaks "A1.10b rev-parse --abbrev-ref prints nothing (step 9) says so" "$SHIM_RPE" rpe

# 11 uses a real detached HEAD rather than a shim — it is reachable during any rebase or bisect,
# and the real thing is a stronger fixture than a simulation of it. The fixture stays here; the
# ASSERTION moved to A4.6, which requires the same allow but no longer accepts silence. A1.11's
# `allow_silent` was removed rather than kept alongside it, because the two state opposite
# requirements about one exit and a suite that asserts both can only ever half-pass.
DETACHED="$TMP/detached"; mkrepo "$DETACHED"
feature_file "$DETACHED" docs/features/a.md planning
( cd "$DETACHED" && git add -A && git commit -q -m init && git checkout -q --detach )

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

# `allow_audible` and the four reason regexes now live at the top, beside the other assertion
# helpers — Group A1's git fail-opens assert audibility too, and they run several hundred lines
# above this point. What each line must carry is unchanged: the guard's own name (an unattributed
# line on a shared stderr is noise) and the reason, distinguishably — A2.6/A2.7 turn on two of
# them being tellable apart.

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
# the wrong reason. awk/sed/head are included though step 2 exits before them — their absence would
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

# A2.1 — step 2, the no-interpreter exit. The guard is off in EVERY repo until PATH is fixed.
export CLAUDE_CODE_SESSION_ID=a2-nopython
with_path "$NOPYBIN" allow_audible "A2.1 no interpreter says so (step 2)" \
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

# A2.15-A2.17 — the PARTIAL skip, the gap the rest of Group A2 could not see. Every fixture above
# makes EVERY file malformed, and every Group A3 fixture pairs a malformed file with a well-formed
# PLANNING one that denies regardless. Neither shape can reach the case that matters: one file the
# contract reads fine and sits at a non-planning phase, plus one it cannot read AT ALL that was the
# repo's only planning card. Nothing is then left at planning, so the hook allows — and the old
# `nparsed -eq 0` tally is false, because one file did parse, so it allowed in COMPLETE SILENCE.
#
# That is the death this whole group exists to make audible, reached by the likeliest route in
# practice: a one-character frontmatter slip in the card you are actively working on, while the
# finished cards beside it stay valid. The count grows as a repo accumulates features, so the
# guarantee got weaker exactly as the repo got more to guard.
PARTIAL="$TMP/partial-skip"; mkrepo "$PARTIAL"; mkdir -p "$PARTIAL/docs/features"
feature_file "$PARTIAL" docs/features/done.md review
# The planning card, with its closing fence forgotten. Written literally rather than via
# feature_file for the same reason as the NOPARSE fixture: the helper cannot produce a file the
# contract rejects, and being unproducible is what makes it malformed.
printf -- '---\nphase: planning\nmodel_tier: high\n\n# the card being worked on right now\n' \
  > "$PARTIAL/docs/features/wip.md"
PL_PARTIAL="$(payload Write file_path "$PARTIAL/src/x.sh")"

export CLAUDE_CODE_SESSION_ID=a2-partial
allow_audible "A2.15 one unreadable card among readable ones still says so" \
  "$PARTIAL" "$PL_PARTIAL" "$NOPARSE_RE"
allow_silent "A2.16 a second write in the same session adds no line" "$PARTIAL" "$PL_PARTIAL"

# The other half of the tally, kept honest: a repo whose files ALL parse must stay silent. Without
# this, widening the skip test to `nfiles > nparsed` could be mutated to an unconditional warn and
# nothing would catch it. Pins its own session id and checks the store, per the no_flag_for note.
ALLPARSE="$TMP/all-parse"; mkrepo "$ALLPARSE"
feature_file "$ALLPARSE" docs/features/done.md review
feature_file "$ALLPARSE" docs/features/other.md implementation feat/other
allow_silent "A2.17 every card readable and none at planning stays silent" "$ALLPARSE" \
  "$(payload_sid Write file_path "$ALLPARSE/src/x.sh" sid-allparse)"
no_flag_for sid-allparse "A2.17 wrote no flag — the skip test tracks unreadable files, not files"

# A2.18 — the SECOND route to "nothing is left at planning", and the reason this check does not
# live at an exit. A2.15's fix was placed inside the no-planning-files branch, which reads as the
# whole story until you notice step 8 can empty that same list one stage later: a card that is
# planning in the working tree but already advanced on its own branch is dropped as superseded,
# and the exit below that drop was a bare `exit 0`. Same silence, same cause, one stage further
# down — a stale card on main is exactly what supersession exists for, so this is the ordinary
# shape, not a contrived one.
#
# The lesson the fix encodes: a skipped card is unreadable regardless of which path the hook then
# takes, so the warning belongs immediately after the parse loop, not at any one exit. Guarding
# exits one at a time is what produced the same bug twice.
SUPSKIP="$TMP/superseded-plus-skip"; supersede_repo "$SUPSKIP" review sup/x
printf -- '---\nphase: planning\nmodel_tier: high\n\n# the card being worked on right now\n' \
  > "$SUPSKIP/docs/features/wip.md"
export CLAUDE_CODE_SESSION_ID=a2-supskip
allow_audible "A2.18 a skipped card still speaks when supersession empties the list" \
  "$SUPSKIP" "$(payload Write file_path "$SUPSKIP/src/x.sh")" "$NOPARSE_RE"

# A2.19-A2.21 — UNREADABLE entries, as opposed to malformed ones. Every fixture above this point
# is a real, readable file whose CONTENT breaks the contract; nothing anywhere in the suite is an
# entry the parser cannot open at all. That is a structural blind spot, not a missing case: the
# skip counter sat behind `[ -f "$f" ]`, which quietly does two jobs — detect the unexpanded glob
# in an empty directory (its real job) and, invisibly, drop every entry that is not a regular
# file. A dropped entry is never counted, so "was anything skipped?" cannot trip on it, and the
# guard goes silent one step EARLIER than the exits rounds 1 and 2 were about.
#
# The severity is not hypothetical. A card symlinked into docs/features/ whose target is moved or
# renamed denies one moment and, the next, silently stops denying — measured directly: target
# present -> exit 2 with the full message; target moved -> exit 0, no output. A real planning
# card vanishing from the gate without a word is the exact failure this whole group exists for.
#
# The boundary the fix draws: an entry that EXISTS IN ANY FORM is counted, and only a glob that
# matched nothing is skipped. `-e` is false for a dangling symlink, so `-L` is needed beside it.
UNREADABLE="$TMP/unreadable-entries"; mkrepo "$UNREADABLE"
# mkrepo does not create docs/features/ — only feature_file does, and no card is wanted here.
# Without this the symlink never lands, the repo reads as never-opted-in, and the case passes
# at step 4 for entirely the wrong reason.
mkdir -p "$UNREADABLE/docs/features"
ln -s /nonexistent/target.md "$UNREADABLE/docs/features/dangling.md"
export CLAUDE_CODE_SESSION_ID=a2-dangling
allow_audible "A2.19 a dangling symlink is an unreadable card, not an absent one" \
  "$UNREADABLE" "$(payload Write file_path "$UNREADABLE/src/x.sh")" "$NOPARSE_RE"

# A directory named *.md matches the glob too, and awk cannot read it either.
DIRENTRY="$TMP/dir-entry"; mkrepo "$DIRENTRY"; mkdir -p "$DIRENTRY/docs/features/weird.md"
export CLAUDE_CODE_SESSION_ID=a2-direntry
allow_audible "A2.20 a directory matching *.md is counted, not dropped" \
  "$DIRENTRY" "$(payload Write file_path "$DIRENTRY/src/x.sh")" "$NOPARSE_RE"

# A2.21 — a card that exists and is a regular file but cannot be OPENED. This one was always
# counted (it passes `-f`), so it warned correctly even before the fix; what it pins is the
# stderr that awk itself writes when the open fails. `allow_audible` requires EXACTLY ONE stderr
# line, so awk's own error escaping to the user is a failure here rather than cosmetic — and it
# escapes the once-per-session suppression, which is why the second write is asserted too.
# Skipped when running as a user that can read a 000 file (root), where the premise cannot hold.
UNOPENABLE="$TMP/unopenable"; mkrepo "$UNOPENABLE"
feature_file "$UNOPENABLE" docs/features/a.md planning
chmod 000 "$UNOPENABLE/docs/features/a.md"
if [ -r "$UNOPENABLE/docs/features/a.md" ]; then
  printf 'skip — A2.21 needs a user that cannot read a mode-000 file\n'
else
  export CLAUDE_CODE_SESSION_ID=a2-unopenable
  allow_audible "A2.21 an unopenable card warns once, and awk stays quiet" \
    "$UNOPENABLE" "$(payload Write file_path "$UNOPENABLE/src/x.sh")" "$NOPARSE_RE"
  allow_silent "A2.22 ...and the second write in that session is fully silent" \
    "$UNOPENABLE" "$(payload Write file_path "$UNOPENABLE/src/x.sh")"
fi
chmod 644 "$UNOPENABLE/docs/features/a.md"

# --- Group A4: the fail-open audit ------------------------------------------------------------
# Four judge rounds found four instances of one class, each a step earlier than the last. Chasing
# the fifth was refused; this group is the enumeration that replaced it. Every exit in the hook is
# classified as JUSTIFIABLY SILENT (the hook genuinely has nothing to say) or MUST BE AUDIBLE (the
# hook knows THIS REPO OPTED IN and then could not COMPLETE the evaluation — it was on its way to
# judge the write, and something stopped it). The boundary is that knowledge, and nothing else.
#
# This comment first bolted "and holds an un-superseded planning card" onto the opt-in test. Round
# 5 falsified that — all three non-git warnings fire in a repo holding no planning card at all —
# and the wrong version left one exit misclassified. Corrected in review, against the spec.
#
# Justifiably silent, each already covered in Group A1: no payload; not a git repo; no
# docs/features/; a path outside the root; an exempt path; nothing at planning; every planning
# card superseded; the branch is claimed. Every one of those is an evaluation that never started
# or one that RAN and came back "not applicable".
#
# Must be audible: no interpreter (A2.1); no git on PATH (A4.5); an unreadable payload (A1.4,
# A1.5); an unresolvable write target (A5.6); any entry skipped (A2.4, A2.15, A2.18-A2.22); the
# four git failures (A1.8-A1.10b); docs/features/ unlistable (A4.1/A4.2 below, the instance RUN 4
# found); and detached HEAD (A4.6), which allows but no longer in silence. SIX of these —
# A1.4/A1.5 and A1.8-A1.10b — were asserted SILENT by this suite until the audit converted them,
# which is what the class looked like from the inside: not missing tests, enforcing ones.
#
# A4.1/A4.2 — docs/features/ exists, so step 4 says the repo opted in, but the directory itself
# cannot be listed. Every card vanishes at once and nfiles is 0, so the skip tally has nothing to
# compare and stays quiet: the repo looks opted-in and unguarded simultaneously. 444 is the sharper
# of the two — the shell still expands the glob to the real filename, so the entry is KNOWN to
# exist and is still dropped, because -e and -L both need search permission on the directory.
# Bracketed by controls at 755 either side, so a pass cannot come from the fixture being broken.
NOLIST="$TMP/unlistable"; mkrepo "$NOLIST"
feature_file "$NOLIST" docs/features/a.md planning
PL_NOLIST="$(payload Write file_path "$NOLIST/src/x.sh")"
deny "A4.0 control — the same repo at 755 denies" "$NOLIST" "$PL_NOLIST"
if chmod 444 "$NOLIST/docs/features" && [ ! -x "$NOLIST/docs/features" ]; then
  export CLAUDE_CODE_SESSION_ID=a4-444
  allow_audible "A4.1 docs/features/ readable but not searchable says so" \
    "$NOLIST" "$PL_NOLIST" "$NOLIST_RE"
  chmod 000 "$NOLIST/docs/features"
  export CLAUDE_CODE_SESSION_ID=a4-000
  allow_audible "A4.2 docs/features/ wholly unreadable says so" \
    "$NOLIST" "$PL_NOLIST" "$NOLIST_RE"
else
  printf 'skip — A4.1/A4.2 need a user that cannot search a mode-444 directory\n'
fi
chmod 755 "$NOLIST/docs/features"
deny "A4.3 control — restoring 755 denies again" "$NOLIST" "$PL_NOLIST"

# A4.4 — step 5, the symlinked repo path. Raised as a fixture gotcha in round 1, re-raised as a
# real route by two judge rounds, and never fixed: `git rev-parse --show-toplevel` always reports
# the PHYSICAL path, while a payload can legitimately reach the same file through a symlinked
# ancestor (/tmp and /var are symlinks on macOS; so is any repo reached via a symlinked checkout).
# The prefix match then fails and the write is treated as outside the repository — the guard is off
# for the WHOLE repo, permanently, and silently. Bracketed by a physical-path control.
SYMREPO="$TMP/symrepo-real"; mkrepo "$SYMREPO"
feature_file "$SYMREPO" docs/features/a.md planning
SYMLINK="$TMP/symrepo-link"; ln -s "$SYMREPO" "$SYMLINK"
deny "A4.4a control — the physical path denies" "$SYMREPO" \
  "$(payload Write file_path "$SYMREPO/src/x.sh")"
deny "A4.4b the same file via a symlinked repo path still denies" "$SYMREPO" \
  "$(payload Write file_path "$SYMLINK/src/x.sh")"

# A4.5 — git absent from PATH. Machine-wide and permanent exactly like a missing interpreter,
# which speaks (A2.1); this was silent, for no reason anyone chose. Built by symlink like NOPYBIN
# so "no git" is the only difference from a normal run.
NOGITBIN="$TMP/nogitbin"; mkdir -p "$NOGITBIN"
for b in bash cat grep mkdir awk sed head python3; do
  [ -n "$(command -v "$b" 2>/dev/null)" ] && ln -sf "$(command -v "$b")" "$NOGITBIN/$b"
done
export CLAUDE_CODE_SESSION_ID=a4-nogitbin
with_path "$NOGITBIN" allow_audible "A4.5 no git on PATH says so, like no interpreter" \
  "$OPTED" "$PL_OPTED" "$NOGITBIN_RE"

# A4.6 — detached HEAD. Still ALLOWS (denying every write through a rebase is the blast radius the
# design refuses), but no longer silently. The old justification — "a rebase issues many writes and
# a line per write would be noise" — is exactly what warn_once already prevents, so it argued for
# silence using the problem the flag solves. As shipped it was also a one-command bypass
# (`git checkout --detach`) of a guard whose deny message says there is no bypass variable.
export CLAUDE_CODE_SESSION_ID=a4-detached
allow_audible "A4.6 detached HEAD allows, but says the guard is off" "$DETACHED" \
  "$(payload Write file_path "$DETACHED/src/x.sh")" "$DETACHED_RE"

# A4.7 — HOME unset. STATE_DIR defaults from $HOME, and under `set -u` an unset HOME is an unbound
# variable: exit 1 on EVERY write, which the spec's own Output contract calls illegitimate.
# PHASE_GUARD_STATE_DIR must be unset too, or its `:-` default short-circuits $HOME and the case
# passes without ever reaching the condition. Safe on a DENY: warn_once never runs, so nothing is
# written anywhere even though the store location is unresolvable.
A4_HOME_SAVED="${HOME:-}"; A4_SD_SAVED="${PHASE_GUARD_STATE_DIR:-}"
unset HOME PHASE_GUARD_STATE_DIR
_run "$OPTED" "$PL_OPTED"
export PHASE_GUARD_STATE_DIR="$A4_SD_SAVED"
if [ "$got" -eq 2 ]; then
  printf 'ok   — A4.7 an unset HOME still denies rather than exiting 1\n'; pass=$((pass+1))
else
  printf 'FAIL — A4.7 an unset HOME still denies rather than exiting 1 (got %s)\n' "$got"
  fail=$((fail+1))
fi
export HOME="$A4_HOME_SAVED"

# --- Group A5: the two defects the audit commit introduced at step 5 ---------------------------
# Both live inside 9996c0b's own fix for the fail-open class, and neither was pinned. Reachability
# is low — payload paths are absolute by contract — but step 5 decides whether a path is ours to
# judge at all, so anything it gets wrong fails OPEN and nothing downstream can catch it.
#
# A5.1-A5.3 — the walk-up reattaches the remainder with no separator whenever NO ancestor of the
# path exists, which is every relative path: `dirname` bottoms out at ".", `${file_path#"."}`
# strips nothing, and `$fp_phys` + `x.sh` glues into `…/optedx.sh`. That matches no root, so the
# write escapes the gate in silence. Asserted as DENY rather than as a silent allow, because
# `cd "$fp_dir"` already resolves "." to the session cwd: anchoring a relative target there is what
# the surrounding code means, and a target resolving into an opted-in repo with an active planning
# card on an unclaimed branch is precisely a guarded write.
export CLAUDE_CODE_SESSION_ID=a5-rel
deny "A5.1 a relative target with no directory part denies" "$OPTED" \
  "$(payload Write file_path "x.sh")"
deny "A5.2 a relative target with directories denies" "$OPTED" \
  "$(payload Write file_path "src/x.sh")"
# A5.3 is the sharper form: `${file_path#"."}` eats the leading dot, so `.hidden.sh` glued into
# `…/optedhidden.sh` — a different file, not merely an unmatched one.
deny "A5.3 a relative dotfile target denies without losing its dot" "$OPTED" \
  "$(payload Write file_path ".hidden.sh")"
# A5.4/A5.5 — controls in both directions. `./src/x.sh` already worked (its remainder keeps the
# slash) and must not regress; an exempt path must stay exempt, so the glue fix cannot convert a
# silent fail-open into a false deny, which is the one outcome this hook may never produce.
deny "A5.4 control — a ./-prefixed relative target still denies" "$OPTED" \
  "$(payload Write file_path "./src/x.sh")"
allow_silent "A5.5 control — a relative target under docs/ is still exempt" "$OPTED" \
  "$(payload Write file_path "docs/x.md")"

# A5.6 — the other one: `[ -n "$fp_phys" ] || exit 0`, a silent fail-open written inside the fix
# for silent fail-opens. `cd` fails when the deepest EXISTING ancestor cannot be searched, and the
# hook then cannot tell a path of its own from one outside. No repo has been identified at this
# exit — THE RULE's opted-in condition never ran — so it speaks only via warn_if_cwd_opted_in's
# cwd fallback, which is why this fixture runs from $OPTED. (An earlier version of this comment
# said "step 3 has already passed, so the rule says it speaks": correct under the pre-508c55b
# numbering, wrong reasoning under the code's — RUN 9.) `-d` on the locked directory still
# works — that reads its parent, which is 755.
LOCKED="$TMP/locked/sub"; mkdir -p "$LOCKED"
export CLAUDE_CODE_SESSION_ID=a5-noresolve
if chmod 000 "$LOCKED" && [ ! -x "$LOCKED" ]; then
  allow_audible "A5.6 a write target that cannot be resolved says so" "$OPTED" \
    "$(payload Write file_path "$LOCKED/x.sh")" "$NORESOLVE_RE"
else
  printf 'skip — A5.6 needs a user that cannot search a mode-000 directory\n'
fi
chmod 755 "$LOCKED"

# --- Group A6: the repo is the FILE'S, not the session's ---------------------------------------
# The root was resolved by running `git rev-parse` in whatever directory the SESSION happened to
# be standing in (step 4). The same target file was therefore denied or allowed according to the
# session's cwd — and the allow was silent, which is the audit's class one step upstream of every
# exit the audit enumerated. Found by the ROUND 6 verdict, which named the defect, reported the
# probe and prescribed the one-line remedy that shipped; an earlier version of this comment claimed
# six rounds had missed it, which was false and is corrected here as it was in the feature card.
#
# A6.3/A6.4 are the case that made this worth the cost: a linked worktree has its own toplevel, so
# a session in the primary checkout writing into its worktree (or the reverse) resolved the wrong
# repo entirely. That is the parallel-agent workflow this gate exists to protect, not an edge case.
#
# WTMAIN commits its card, unlike every other fixture here: a linked worktree only checks out what
# has been committed, so an uncommitted card would leave the worktree looking like it never opted in
# and the case would pass for the wrong reason.
WTMAIN="$TMP/wtmain"; mkrepo "$WTMAIN"
feature_file "$WTMAIN" docs/features/a.md planning
( cd "$WTMAIN" && git add -A && git commit -q -m card )
WTLINK="$TMP/wtlink"
( cd "$WTMAIN" && git worktree add -q -b wip/x "$WTLINK" )

export CLAUDE_CODE_SESSION_ID=a6-elsewhere
deny "A6.1 cwd in another repo, target in the opted-in one, denies" "$BARE"   "$PL_OPTED"
deny "A6.2 cwd outside any repo, target in the opted-in one, denies" "$NOREPO" "$PL_OPTED"
deny "A6.3 cwd in the primary checkout, target in its worktree, denies" "$WTMAIN" \
  "$(payload Write file_path "$WTLINK/src/x.sh")"
deny "A6.4 cwd in the worktree, target in the primary checkout, denies" "$WTLINK" \
  "$(payload Write file_path "$WTMAIN/src/x.sh")"

# A6.5/A6.6 — the same reordering must not start denying, or warning, on the strength of a cwd that
# is now irrelevant. A6.6 is the hot path itself: every write in every repo that never opted in.
allow_silent "A6.5 control — a target in a repo that never opted in stays silent" "$OPTED" \
  "$(payload Write file_path "$BARE/src/x.sh")"
allow_silent "A6.6 control — the hot path in a repo that never opted in stays silent" "$BARE" \
  "$(payload Write file_path "$BARE/src/x.sh")"

# A6.7 — the negative half of the payload/resolution warnings. Once the parse runs BEFORE the repo
# is known, those exits can no longer ask "did this repo opt in?" and the session's cwd is the only
# signal left. A1.4/A1.5 pin that it still speaks when the cwd IS an opted-in repo; this pins that
# it does not put a line into every repo on the machine that never opted in.
export CLAUDE_CODE_SESSION_ID=a6-quietpayload
allow_silent "A6.7 an unreadable payload outside any opted-in repo stays silent" "$BARE" \
  '{"hook_event_name":"PreToo'
no_flag_for a6-quietpayload "A6.7b ...and wrote no flag, so that silence is real"

# --- Group A7: an unreadable .git is a repo we cannot read, not "no repo" -----------------------
# The eighth instance of the branch's one class, and the third report of THIS instance — rounds 5
# and 6 both carried it as "an unreadable .git in an opted-in repo → silent", and neither the code
# nor the record moved. The audit's own "Justifiably silent" list is where it hid: the row reads
# "not a git repo", and `git rev-parse --show-toplevel` exits non-zero for BOTH "there is no repo
# here" and "there is one and I cannot read it". One row, two conditions, only one of them
# justifiable — the same shape as the six exits the first audit pass had to convert.
#
# The discriminator cannot be `warn_if_cwd_opted_in`: that helper resolves the root from the
# SESSION's cwd, which fails for the same reason the target's did whenever the two are the same
# repo — the exact case here. So the hook walks up from the target for an EXISTING .git entry
# instead. That answers "is this a repo?" without needing to read it, and needs no cwd at all.
#
# It cannot know whether that repo opted in — reading docs/features/ needs the root it just failed
# to get — so the message is conditional in the NOPARSE_MSG style rather than asserting the gate
# was dropped. One line per session via warn_once, like every other audible exit.
UNREADABLE="$TMP/unreadable"; mkrepo "$UNREADABLE"
feature_file "$UNREADABLE" "docs/features/f.md" planning ""
export CLAUDE_CODE_SESSION_ID=a7-unreadable
if chmod 000 "$UNREADABLE/.git" && [ ! -r "$UNREADABLE/.git" ]; then
  allow_audible "A7.1 a repo whose .git cannot be read says so" "$OPTED" \
    "$(payload Write file_path "$UNREADABLE/src/x.sh")" "$NOREPOREAD_RE"
  # The control that makes A7.1 mean something: the justifiable half of the row it splits. A
  # directory under no repo at all must stay silent, or the fix has simply moved the noise.
  export CLAUDE_CODE_SESSION_ID=a7-norepo
  allow_silent "A7.2 control — a target under no repo at all stays silent" "$OPTED" \
    "$(payload Write file_path "$TMP/nonrepo-a7/src/x.sh")"
  no_flag_for a7-norepo "A7.3 ...and wrote no flag, so that silence is real"

  # A7.4 pins the RATIONALE, which A7.1 does not. A7.1 runs with cwd in $OPTED — a readable repo —
  # so a `warn_if_cwd_opted_in` implementation would resolve a root, find the opt-in, and speak;
  # A7.1 stays green under the very substitution the comment above rules out. The case the walk-up
  # exists for is cwd INSIDE the unreadable repo, where that helper fails for the same reason the
  # target's rev-parse did and the warning is lost. Reachable because only .git is mode 000: the
  # work tree is still enterable. RUN 8 found this gap — the fix was sound and unpinned.
  export CLAUDE_CODE_SESSION_ID=a7-cwd-unreadable
  allow_audible "A7.4 ...and still says so when the session's own cwd is that repo" "$UNREADABLE" \
    "$(payload Write file_path "$UNREADABLE/src/x.sh")" "$NOREPOREAD_RE"
else
  printf 'skip — A7 needs a user that cannot read a mode-000 .git\n'
fi
chmod 755 "$UNREADABLE/.git" 2>/dev/null

# --- Group A8: the spec half is not a phase card -------------------------------------------------
# Task 11 of docs/features/memory-system-split.md. `<name>.spec.md` is the pair's long half and
# carries no frontmatter by contract, but the glob at line 356 was `docs/features/*.md`, which
# matches it too. Excluded by name (`case "$f" in *.spec.md) continue ;; esac`), before nfiles
# counts it — content is never inspected, which A8.2 exists to prove.

# A8.1 — alone, no frontmatter at all: the shape the contract actually specifies. Without the
# exclusion this hits `[ -n "$parsed_fm" ] || continue` (nfiles counted, nparsed not), which trips
# `nfiles -gt nparsed` and fires noparse EVERY session on a file that was never a card.
A8ALONE="$TMP/a8-alone"; mkrepo "$A8ALONE"; mkdir -p "$A8ALONE/docs/features"
printf '# just a spec\n\nsome prose, no fences at all.\n' > "$A8ALONE/docs/features/name.spec.md"
export CLAUDE_CODE_SESSION_ID=a8-alone
allow_silent "A8.1 a frontmatter-less .spec.md alone does not warn" "$A8ALONE" \
  "$(payload_sid Write file_path "$A8ALONE/src/x.sh" a8-alone)"
no_flag_for a8-alone "A8.1b ...and wrote no noparse flag, so the silence is not just suppression"

# A8.2 — well-formed `phase: planning` frontmatter inside a .spec.md. A malformed pair (or a slip
# migrating task 5) could put it there; the exclusion is by NAME, so this must still be ignored
# rather than collected into planning_files and freeze source edits repo-wide on a card that does
# not own the gate. Without the exclusion this is indistinguishable from a real planning card and
# A8.2 would deny.
A8PLANNING="$TMP/a8-planning"; mkrepo "$A8PLANNING"
feature_file "$A8PLANNING" docs/features/name.spec.md planning ""
export CLAUDE_CODE_SESSION_ID=a8-planning
allow_silent "A8.2 a .spec.md carrying phase: planning is still excluded by name" "$A8PLANNING" \
  "$(payload_sid Write file_path "$A8PLANNING/src/x.sh" a8-planning)"

# A8.3 — mixed with a genuine planning card. Proves the exclusion does not swallow a real deny
# (real.md still denies) and does not make the tally miscount around it (no noparse flag, even
# though a deny fires on the very same run).
A8MIXED="$TMP/a8-mixed"; mkrepo "$A8MIXED"
feature_file "$A8MIXED" docs/features/real.md planning ""
printf '# just a spec\n' > "$A8MIXED/docs/features/real.spec.md"
export CLAUDE_CODE_SESSION_ID=a8-mixed
deny    "A8.3 a real planning card still denies beside an excluded .spec.md" "$A8MIXED" \
  "$(payload_sid Write file_path "$A8MIXED/src/x.sh" a8-mixed)"
err_has   "A8.3b names real.md"      'docs/features/real\.md'
err_lacks "A8.3c does not name real.spec.md" 'docs/features/real\.spec\.md'
no_flag_for a8-mixed "A8.3d ...and the deny is the only thing that fired — no noparse flag"

# --- Group D: the record — doc↔code drift tripwires ---------------------------------------------
# RUNS 6-9 each found the explanatory record contradicting the code while every behavioural test
# stayed green: the suite could not see the document, so a clean run certified nothing about the
# claims a reader actually navigates by. These are grep tripwires, not semantic checks — they pin
# exactly the surfaces that have demonstrably rotted (step numbering, the audible-exit counts, the
# flag-reason set) and nothing else. If the feature card ever moves, update DOC here with it.
DOC="$(cd "$(dirname "$0")" && pwd)/../docs/features/phase-guard-hook.md"

# The first line of each numbered item in the doc's canonical Order-of-operations list.
doc_steps_body() {
  awk '/^\*\*Order of operations\*\*/{f=1; next} f && /^### /{exit} f' "$DOC" | grep -E '^[0-9]+\. '
}

# D1 — the doc's list and the code's `# --- Step N ---` headers agree on count and order, 1..N
# with no gaps. Step numbers mean the code's headers; this is the cheapest check that the prose
# still has headers to mean.
code_n=$(grep -c '^# --- Step ' "$HOOK")
doc_n=$(doc_steps_body | grep -c .)
code_seq=$(grep '^# --- Step ' "$HOOK" | sed 's/^# --- Step \([0-9][0-9]*\):.*/\1/' | tr '\n' ' ')
doc_seq=$(doc_steps_body | sed 's/^\([0-9][0-9]*\)\. .*/\1/' | tr '\n' ' ')
want_seq=""; i=1
while [ "$i" -le "$code_n" ]; do want_seq="$want_seq$i "; i=$((i+1)); done
if [ "$doc_n" -eq "$code_n" ] && [ "$code_seq" = "$want_seq" ] && [ "$doc_seq" = "$want_seq" ]; then
  printf 'ok   — D1 the doc step list and the code step headers agree (count and order)\n'; pass=$((pass+1))
else
  printf 'FAIL — D1 step lists disagree (code: %s/ doc: %s/ want: %s)\n' "$code_seq" "$doc_seq" "$want_seq"; fail=$((fail+1))
fi

# D2 — step number N names the same operation on both sides. One keyword per side per step: not
# semantics, just enough that a renumber on either side cannot read as the neighbouring step. A
# step with no keyword row below is a FAIL by design — growing the hook means growing this table.
mismatch=""; i=1
while [ "$i" -le "$code_n" ]; do
  dk=""; ck=""
  case "$i" in
    1)  dk="stdin payload";           ck="the payload";;
    2)  dk="tools";                   ck="tools";;
    3)  dk="path out of the payload"; ck="path out of the payload";;
    4)  dk="opted in";                ck="opted in";;
    5)  dk="elativize";               ck="elativize";;
    6)  dk="Classify";                ck="guarded";;
    7)  dk="frontmatter";             ck="planning";;
    8)  dk="superseded";              ck="superseded";;
    9)  dk="current branch";          ck="branch";;
    10) dk="deny";                    ck="deny";;
  esac
  if [ -z "$dk" ]; then
    mismatch="$mismatch nokeyword:$i"
  else
    doc_steps_body | sed -n "${i}p" | grep -qF "$dk" || mismatch="$mismatch doc:$i"
    grep "^# --- Step $i:" "$HOOK" | grep -qF "$ck" || mismatch="$mismatch code:$i"
  fi
  i=$((i+1))
done
if [ -z "$mismatch" ]; then
  printf 'ok   — D2 each step number names the same operation in doc and code\n'; pass=$((pass+1))
else
  printf 'FAIL — D2 step keyword mismatch at:%s\n' "$mismatch"; fail=$((fail+1))
fi

# D3 — the Flag contract's Path row names every reason the code can actually write. Derived from
# the call sites, not from memory: the row was authored when there were two reasons and lagged the
# audit as it grew (RUN 9). Comment lines are excluded so prose mentioning the helpers cannot vote.
reasons=$(grep -vE '^[[:space:]]*#' "$HOOK" \
  | grep -oE '(warn_once|warn_if_cwd_opted_in) [a-z][a-z]*' | awk '{print $2}' | sort -u)
path_row=$(grep -F '| Path |' "$DOC")
missing=""
for r in $reasons; do
  case "$path_row" in *\`"$r"\`*) ;; *) missing="$missing $r";; esac
done
if [ -n "$reasons" ] && [ -z "$missing" ]; then
  printf 'ok   — D3 the Flag contract names every reason the code can write\n'; pass=$((pass+1))
else
  printf 'FAIL — D3 Flag contract Path row is missing:%s\n' "${missing:- (reason extraction broke)}"; fail=$((fail+1))
fi

# D4 — the Output contract's audible counts are the derived truth, stated exactly once. The doc
# must carry the sentence "<rows> audible rows across <reasons> once-per-session" where both
# numbers are computed here, not asserted here — so the contract cannot silently undercount again.
rows_n=$(awk '/Why it must speak/{f=1} f && /^$/{exit} f' "$DOC" | grep -c '^|')
rows_n=$((rows_n - 2)) # header row + separator row
reasons_n=$(printf '%s\n' "$reasons" | grep -c .)
phrase_hits=$(grep -c 'audible rows across' "$DOC")
want_phrase="$rows_n audible rows across $reasons_n once-per-session"
if [ "$phrase_hits" -eq 1 ] && grep -qF "$want_phrase" "$DOC"; then
  printf 'ok   — D4 the Output contract counts are derived truth, stated once\n'; pass=$((pass+1))
else
  printf 'FAIL — D4 want exactly one "%s" (phrase hits: %s)\n' "$want_phrase" "$phrase_hits"; fail=$((fail+1))
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
