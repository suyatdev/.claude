#!/usr/bin/env bash
# test-marker-guard.test.sh -- drives hooks/test-marker-guard.sh with a PreToolUse payload on
# STDIN, the production path, against real commits in throwaway repos.
# Run: bash hooks/test-marker-guard.test.sh
#
# A hook tested only through its CLI path is a bug that has already shipped in this repo, so
# every case here goes in the way the harness sends it: JSON on stdin, `cwd` naming the repo.
#
# Three habits this suite is built around, each earned by a defect that passed the version
# without it:
#
#   * LOG ASSERTIONS READ BY FIELD (awk -F'\t'), never by grep. `grep EXEMPT` passes against an
#     `echo`-written log in which the separator is the two characters \ and t and no reader can
#     ever reach field 2 -- the line still looks tab-separated in a terminal.
#   * FIXTURES ARE WRONG ON PURPOSE. A $HOME store that agrees with the repo's, a marker whose
#     timestamp nobody varies, a directory race run only in the winning order: each of those
#     passes under the very defect it appears to test. Where a case exists to prove a source was
#     consulted, the other source is made to DISAGREE.
#   * THE UMASK IS SET EXPLICITLY wherever a file mode is asserted. A suite inheriting 0077
#     reports 0600 on a log the gate created 0644.
#
# The two Examples tables under "every door that writes a line" drive the door cases below as
# data (DOORS_TSV, DOORS_BASH). They are not hand-copied into per-door cases: two spellings of
# one check is this spec's own named defect class.
set -u

HOOKS="$(cd "$(dirname "$0")" && pwd)"
GATE="$HOOKS/test-marker-guard.sh"
WRITER="$HOOKS/lib/write-test-marker.py"
ENTRY="$HOOKS/lib/decide-commit-gate.py"
CLASSIFIER="$HOOKS/lib/classify-commit-command.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LOGREL="hooks/state/test-marker.log"
STOREREL="hooks/state/test-markers"
PAIR='hooks/foo.sh|hooks/foo.test.sh'

pass=0
fail=0

ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s\n' "$1"; fail=$((fail+1)); }

# ---------------------------------------------------------------------------
# Payloads. `cwd` is top-level, the field the gate reads with its inline python3
# JSON extract; the command lives under tool_input, where the harness puts it.
# ---------------------------------------------------------------------------

payload() { # $1 command, $2 cwd, [$3 tool], [$4 description]
  /usr/bin/jq -nc --arg c "$1" --arg d "$2" --arg t "${3:-Bash}" --arg n "${4:-}" \
    '{hook_event_name:"PreToolUse",tool_name:$t,cwd:$d,
      tool_input:(if $n == "" then {command:$c} else {command:$c,description:$n} end)}'
}

payload_nocmd() { # $1 cwd, $2 tool -- tool_input carries no command field at all
  /usr/bin/jq -nc --arg d "$1" --arg t "$2" \
    '{hook_event_name:"PreToolUse",tool_name:$t,cwd:$d,tool_input:{}}'
}

# ---------------------------------------------------------------------------
# Repos. `adopt` installs the writer, which is the opt-in signal; `inert` does not.
# Nothing here creates hooks/state/ -- the mode cases at the end assert who creates
# it and with what mode, and a fixture that pre-created it would answer that for them.
# ---------------------------------------------------------------------------

# The path comes from mktemp, not a counter: setup_door below runs inside a command
# substitution, so a counter incremented there is lost and the next door reuses the path.
new_repo() { # $1 = adopt|inert -- echoes the repo path
  local repo
  repo="$(mktemp -d "$TMP/r.XXXXXX")"
  mkdir -p "$repo/hooks/lib" "$repo/docs"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  printf 'v1 subject\n' > "$repo/hooks/foo.sh"
  printf 'v1 suite\n'   > "$repo/hooks/foo.test.sh"
  printf 'notes\n'      > "$repo/docs/notes.md"
  printf 'py subject\n' > "$repo/hooks/lib/classify-pr-command.py"
  printf 'py suite\n'   > "$repo/hooks/lib/classify-pr-command.test.py"
  if [ "$1" = adopt ]; then cp "$WRITER" "$repo/hooks/lib/write-test-marker.py"; fi
  git -C "$repo" add -A
  git -C "$repo" commit -qm seed
  printf '%s' "$repo"
}

edit()  { printf '%s\n' "$3" > "$1/$2"; }
stage() { git -C "$1" add -- "$2"; }

# The real writer, run with the repo root as cwd -- the specified call site. Measured: after
# --full-name normalisation the derived subject is repo-relative, so a call from anywhere else
# resolves it against THAT cwd and reports a tracked subject as missing.
mark() { ( cd "$1" && python3 -I "$WRITER" "$2" ) >/dev/null 2>&1; }

key() { printf '%s' "$1" | sed -e 's/%/%25/g' -e 's|/|%2F|g'; }

hand_marker() { # $1 repo, $2 subject, $3 test, $4 subject-blob, $5 test-blob, $6 written_at
  mkdir -p "$1/$STOREREL"
  printf '{\n "subject": {"blob": "%s", "path": "%s"},\n "test": {"blob": "%s", "path": "%s"},\n "version": 1,\n "written_at": "%s"\n}\n' \
    "$4" "$2" "$5" "$3" "$6" > "$1/$STOREREL/$(key "$2")"
}

blob() { git -C "$1" hash-object -- "$1/$2"; }

# ---------------------------------------------------------------------------
# Running the gate. RC is captured before anything else can overwrite $?.
# RUN_ENV is a space-free VAR=value list; /bin/bash is absolute because the
# no-python case hands `env` a PATH that must not have to resolve the shell.
# ---------------------------------------------------------------------------

RC=0
ERR=""
RUN_ENV=""

run_raw() { # $1 raw payload bytes, [$2 gate override]
  # shellcheck disable=SC2086  # RUN_ENV MUST word-split: empty means "no override", and a
  # quoted empty string would hand `env` an argument it reads as a command name.
  ERR="$(printf '%s' "$1" | /usr/bin/env $RUN_ENV /bin/bash "${2:-$GATE}" 2>&1 >/dev/null)"
  RC=$?
}

run_hook() { # $1 repo, $2 command, [$3 gate override], [$4 tool], [$5 description]
  run_raw "$(payload "$2" "$1" "${4:-Bash}" "${5:-}")" "${3:-$GATE}"
}

expect_exit() { # $1 desc, $2 want
  if [ "$RC" -eq "$2" ]; then ok "$1 (exit $RC)"; else bad "$1 (want exit $2, got $RC)"; fi
}

expect_msg() { # $1 desc, $2 substring
  case "$ERR" in
    *"$2"*) ok "$1 — message names $2" ;;
    *)      bad "$1 — message lacks $2" ;;
  esac
}

allow() { # $1 desc, $2 repo, $3 cmd, [$4 gate]
  run_hook "$2" "$3" "${4:-$GATE}"
  expect_exit "$1" 0
}

block() { # $1 desc, $2 repo, $3 cmd, $4 door, [$5 trigger-or-detail], [$6 gate]
  run_hook "$2" "$3" "${6:-$GATE}"
  expect_exit "$1" 2
  expect_msg "$1" "$4"
  if [ $# -ge 5 ] && [ -n "$5" ]; then expect_msg "$1" "$5"; fi
  return 0
}

# ---------------------------------------------------------------------------
# The log, read BY FIELD. log_field prints one field of the last line; a grep
# would pass against a log whose separator is not a tab at all.
# ---------------------------------------------------------------------------

log_count() {
  if [ -f "$1/$LOGREL" ]; then awk 'END {print NR}' "$1/$LOGREL"; else printf '0'; fi
}

log_field() { # $1 repo, $2 field index -- of the LAST line
  [ -f "$1/$LOGREL" ] || return 0
  awk -F'\t' -v f="$2" '{v = $f} END {print v}' "$1/$LOGREL"
}

expect_log_field() { # $1 desc, $2 repo, $3 field, $4 want
  local got
  got="$(log_field "$2" "$3")"
  if [ "$got" = "$4" ]; then
    ok "$1 — log field $3 is '$4'"
  else
    bad "$1 — log field $3: want '$4', got '$got'"
  fi
}

expect_log_count() { # $1 desc, $2 repo, $3 want
  local got
  got="$(log_count "$2")"
  if [ "$got" = "$3" ]; then ok "$1 — $3 log line(s)"; else bad "$1 — want $3 log lines, got $got"; fi
}

mode_of() { /usr/bin/stat -f '%OLp' "$1" 2>/dev/null; }

expect_mode() { # $1 desc, $2 path, $3 want
  local got
  got="$(mode_of "$2")"
  if [ "$got" = "$3" ]; then ok "$1 — mode $3"; else bad "$1 — want mode $3, got '${got:-absent}'"; fi
}

# ---------------------------------------------------------------------------
# Stub gates. The hook reads both Python files from ITS OWN directory, never from
# the target repo, so a stub is a copy of the hook beside a lib/ we control --
# the shape doc-guard.test.sh already uses for its missing-classifier case.
# ---------------------------------------------------------------------------

stub_gate() { # $1 name, $2 entry spec, $3 classifier spec -- echoes the gate path
  local dir="$TMP/stubs/$1"
  rm -rf "$dir"
  mkdir -p "$dir/lib"
  cp "$GATE" "$dir/test-marker-guard.sh" 2>/dev/null
  chmod +x "$dir/test-marker-guard.sh" 2>/dev/null
  case "$2" in
    REAL)  cp "$ENTRY" "$dir/lib/decide-commit-gate.py" 2>/dev/null ;;
    EMPTY) : > "$dir/lib/decide-commit-gate.py" ;;
    OMIT)  : ;;
    *)     printf '%s\n' "$2" > "$dir/lib/decide-commit-gate.py" ;;
  esac
  case "$3" in
    REAL)  cp "$CLASSIFIER" "$dir/lib/classify-commit-command.py" 2>/dev/null ;;
    EMPTY) : > "$dir/lib/classify-commit-command.py" ;;
    OMIT)  : ;;
    *)     printf '%s\n' "$3" > "$dir/lib/classify-commit-command.py" ;;
  esac
  printf '%s' "$dir/test-marker-guard.sh"
}

emit() { printf 'import sys; sys.stdout.write(%s)' "$1"; }

printf '### A. Correct behaviour — the gate stays out of the way\n\n'

# ---------------------------------------------------------------------------
# A1-A2. A fresh marker allows; written_at never decides, in either direction.
# ---------------------------------------------------------------------------

R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
allow "fresh marker allows the commit" "$R" 'git commit -m msg'

# Both directions, because either row alone is satisfied by an implementation that reads the
# clock: an ancient timestamp must not block matching blobs, and a current one must not rescue
# blobs that do not match. Through revision 16 no scenario varied the timestamp at all.
while IFS='|' read -r stamp blobs want door; do
  [ -n "$stamp" ] || continue
  R="$(new_repo adopt)"
  # A staged-but-unchanged foo.sh produces no diff against base at all (measured, 2026-08-20:
  # git status/diff show nothing for a re-added identical file, and a real `git commit` with
  # only that staged refuses with "nothing to commit"), so PLAIN's diff-based collector can never
  # see it. Editing it first keeps this row a genuine, git-observable in-scope commit.
  edit "$R" hooks/foo.sh 'v2 subject'
  if [ "$blobs" = match ]; then
    hand_marker "$R" hooks/foo.sh hooks/foo.test.sh \
      "$(blob "$R" hooks/foo.sh)" "$(blob "$R" hooks/foo.test.sh)" "$stamp"
  else
    hand_marker "$R" hooks/foo.sh hooks/foo.test.sh \
      0000000000000000000000000000000000000000 "$(blob "$R" hooks/foo.test.sh)" "$stamp"
  fi
  stage "$R" hooks/foo.sh
  run_hook "$R" 'git commit -m msg'
  expect_exit "written_at $stamp, blobs $blobs" "$want"
  if [ -n "$door" ]; then expect_msg "written_at $stamp, blobs $blobs" "$door"; fi
done <<'TABLE'
1970-01-01T00:00:00Z|match|0|
2099-01-01T00:00:00Z|match|0|
2026-08-14T00:00:00Z|differ|2|MSG_STALE_SUBJECT
TABLE

# ---------------------------------------------------------------------------
# A3-A4. Which store was consulted. Both cases are stale-on-purpose: with the other
# store absent or agreeing, a gate reading the wrong one passes both.
# ---------------------------------------------------------------------------

R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
FAKEHOME="$TMP/fakehome"
mkdir -p "$FAKEHOME/$STOREREL"
hand_marker "$FAKEHOME" hooks/foo.sh hooks/foo.test.sh \
  1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 \
  2026-08-14T00:00:00Z
OLDHOME="$HOME"
HOME="$FAKEHOME"; export HOME
run_hook "$R" 'git commit -m msg'
HOME="$OLDHOME"; export HOME
expect_exit "marker read from the repo toplevel, not \$HOME (whose copy is stale)" 0

R="$(new_repo adopt)"
WT="$TMP/wt-linked"
git -C "$R" worktree add -q "$WT" -b side
hand_marker "$R" hooks/foo.sh hooks/foo.test.sh \
  3333333333333333333333333333333333333333 4444444444444444444444444444444444444444 \
  2026-08-14T00:00:00Z
mark "$WT" hooks/foo.test.sh
stage "$WT" hooks/foo.sh
allow "linked worktree reads its own marker, not the main checkout's stale one" "$WT" 'git commit -m msg'

# ---------------------------------------------------------------------------
# A8-A9. A repo that has not opted in is never gated -- including when the gate's own
# Python files are broken. Both rows, because the two files fail at different doors in
# an adopting repo and one row would leave the other's inertness asserted by argument.
# ---------------------------------------------------------------------------

R="$(new_repo inert)"
stage "$R" hooks/foo.sh
allow "a repo without the writer is never gated" "$R" 'git commit -m msg'

R="$(new_repo inert)"
stage "$R" hooks/foo.sh
allow "no writer + entry point deleted -> still allowed" "$R" 'git commit -m msg' \
  "$(stub_gate inert-noentry OMIT REAL)"
allow "no writer + classifier deleted -> still allowed" "$R" 'git commit -m msg' \
  "$(stub_gate inert-noclassifier REAL OMIT)"

# ---------------------------------------------------------------------------
# A10-A18. Allow paths. Each is a way this control can wrongly fire.
# ---------------------------------------------------------------------------

run_raw 'this is not json at all'
expect_exit "an unparseable payload is not a machine-global block" 0

run_raw '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m msg"}}'
expect_exit "a payload carrying no cwd is not a machine-global block" 0

R="$(new_repo adopt)"
stage "$R" docs/notes.md
allow "a file with no sibling test is never gated" "$R" 'git commit -m msg'

R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
edit "$R" docs/notes.md 'dirty but unstaged'
allow "partial staging is not a false block (staged is a subset of tested)" "$R" 'git commit -m msg'

R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
printf 'scratch\n' > "$R/scratch.tmp"
allow "untracked scratch files are irrelevant" "$R" 'git commit -m msg'

R="$(new_repo adopt)"
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
edit "$R" docs/notes.md 'v2 notes'
allow "a pathspec narrows the gate to what is being committed" "$R" 'git commit -m msg -- docs/notes.md'

R="$(new_repo adopt)"
printf 'bar\n' > "$R/hooks/bar.md"
git -C "$R" add -A; git -C "$R" commit -qm bar
edit "$R" hooks/bar.md 'bar v2'
allow "a pathspec covering an unchanged sibling-tested file does not block" "$R" 'git commit -m msg -- hooks/'

R="$(new_repo adopt)"
printf 'orphan suite\n' > "$R/panes-adapters.test.sh"
git -C "$R" add -- panes-adapters.test.sh
allow "an orphan suite is never gated" "$R" 'git commit -m msg'

mkdir -p "$TMP/norepo"
allow "a commit outside any repository is left to git" "$TMP/norepo" 'git commit -m msg'

# HEAD unborn: measured, rev-parse --verify HEAD and git diff --cached HEAD both exit 128, so
# without the empty-tree base this blocks every repo's first commit.
UNBORN="$TMP/unborn"
mkdir -p "$UNBORN/hooks/lib"
git -C "$UNBORN" init -q -b main
git -C "$UNBORN" config user.email test@example.com
git -C "$UNBORN" config user.name test
cp "$WRITER" "$UNBORN/hooks/lib/write-test-marker.py"
printf 'v1 subject\n' > "$UNBORN/hooks/foo.sh"
printf 'v1 suite\n'   > "$UNBORN/hooks/foo.test.sh"
git -C "$UNBORN" add -A
hand_marker "$UNBORN" hooks/foo.sh hooks/foo.test.sh \
  "$(blob "$UNBORN" hooks/foo.sh)" "$(blob "$UNBORN" hooks/foo.test.sh)" 2026-08-14T00:00:00Z
allow "the first commit in a writer-installed repo is not a git failure" "$UNBORN" 'git commit -m msg'

printf '\n### B. Incorrect behaviour the gate must catch\n\n'

R="$(new_repo adopt)"
# Unchanged content is invisible to the diff-based collector (see the written_at loop's note
# above) -- edit before staging so this is a real, in-scope commit.
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
block "no marker at all" "$R" 'git commit -m msg' MSG_NO_MARKER 'bash hooks/foo.test.sh'

R="$(new_repo adopt)"
edit "$R" hooks/lib/classify-pr-command.py 'py v2'
stage "$R" hooks/lib/classify-pr-command.py
block "the remedy names the right interpreter for a Python pair" "$R" 'git commit -m msg' \
  MSG_NO_MARKER 'python3 hooks/lib/classify-pr-command.test.py'

R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
block "the subject changed after the run" "$R" 'git commit -m msg' MSG_STALE_SUBJECT

R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
edit "$R" hooks/foo.test.sh 'v2 suite'
stage "$R" hooks/foo.test.sh
block "a test version that was never run is being shipped" "$R" 'git commit -m msg' MSG_STALE_TEST

# Measured: this commit ships v2 while the index holds v1, so an index read wrongly allows.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
edit "$R" hooks/foo.sh 'v2 subject'
block "a pathspec commit is gated on worktree content, not the index" "$R" \
  'git commit -m msg -- hooks/foo.sh' MSG_STALE_SUBJECT

# Measured (M4): naming foo.sh in the pathspec ships its WORKTREE content (v3), which
# mismatches the marker's recorded v2 -- MSG_STALE_SUBJECT. foo.test.sh, left out of the
# pathspec, ships its BASE content (v2, untouched by this commit) and still matches the marker.
R="$(new_repo adopt)"
edit "$R" hooks/foo.sh 'v2 subject'
edit "$R" hooks/foo.test.sh 'v2 suite'
git -C "$R" add -A; git -C "$R" commit -qm v2
mark "$R" hooks/foo.test.sh
edit "$R" hooks/foo.sh 'v3 subject'
edit "$R" hooks/foo.test.sh 'v3 suite'
block "a pair member outside the pathspec is compared against base, not the worktree" "$R" \
  'git commit -m msg -- hooks/foo.sh' MSG_STALE_SUBJECT

# Measured: `git diff --cached` returns zero paths here, so a gate collecting from the index
# finds no pairs and allows.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
edit "$R" hooks/foo.sh 'v2 subject'
block "git commit -a does not escape the gate" "$R" 'git commit -a -m msg' MSG_STALE_SUBJECT

# Measured G1: -am is -a -m msg and ships the WORKTREE blob. A classifier matching only the
# literal tokens -a/--all reads this as PLAIN, hashes the index, and allows.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
edit "$R" hooks/foo.sh 'v2 subject'
block "a bundled -am is decomposed and does not escape the gate" "$R" 'git commit -am msg' \
  MSG_STALE_SUBJECT

# Measured G2: a bare operand is a pathspec with no -- needed.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
edit "$R" hooks/foo.sh 'v2 subject'
block "a pathspec with no -- separator is still a pathspec" "$R" 'git commit -m msg hooks/foo.sh' \
  MSG_STALE_SUBJECT

# Measured G5: -F consumes msg.txt as the message file. Reading it as an operand switches the
# form to PATHSPEC and hashes the wrong source.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
printf 'a message\n' > "$R/msg.txt"
allow "a flag value is never mistaken for a pathspec" "$R" 'git commit -F msg.txt'

# Measured G6: textual scanning for -- splits this command in the wrong place.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
allow "a -- inside a message value is not an operand separator" "$R" \
  "git commit -m 'fix -- thing' hooks/foo.sh"

# Measured G8/G9: git itself exits 128 and commits nothing, so the hook allows and lets git
# refuse. G9 is the bundled form, which requires decomposition BEFORE the -a-plus-operand check.
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
allow "-a combined with a pathspec is left to git" "$R" 'git commit -a -m msg -- hooks/foo.sh'
allow "a bundled -a with a pathspec is left to git" "$R" 'git commit -am msg -- hooks/foo.sh'

printf '\n### B2. The four UNSUPPORTED triggers, each asserted by the trigger its message names\n\n'

# One constant, four triggers. Asserting MSG_UNSUPPORTED_FORM alone cannot tell them apart --
# mutation testing on judge-guard showed 48 assertions that could not distinguish one door
# from another while a mutant survived a 101/0 suite.

R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
block "an abbreviated but valid option blocks rather than falling through to PLAIN" "$R" \
  'git commit --am -m msg' MSG_UNSUPPORTED_FORM OFF_WHITELIST

R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
edit "$R" docs/notes.md 'notes v2'
block "git commit -i does not sweep an untested staged file past the gate" "$R" \
  'git commit -m msg -i -- docs/notes.md' MSG_UNSUPPORTED_FORM INCLUDE_OR_FROM_FILE

FOREIGN="$(new_repo adopt)"
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
block "a commit aimed at another repo cannot be verified, so it blocks" "$R" \
  "cd $FOREIGN && git commit -m msg" MSG_UNSUPPORTED_FORM FOREIGN_REPO

# The fourth trigger, and through revision 18 the only one with no scenario at all. Written
# against a FRESH marker deliberately: these block because the content is chosen interactively
# AFTER the hook returns, not because anything is stale. A stale setup would block under an
# implementation that never implemented this trigger, certifying its absence as correct.
while IFS='|' read -r cmd; do
  [ -n "$cmd" ] || continue
  R="$(new_repo adopt)"
  mark "$R" hooks/foo.test.sh
  stage "$R" hooks/foo.sh
  block "interactive selection blocks even with a fresh marker: $cmd" "$R" "$cmd" \
    MSG_UNSUPPORTED_FORM PATCH_OR_INTERACTIVE
  expect_log_field "interactive: $cmd" "$R" 3 MSG_UNSUPPORTED_FORM
done <<'TABLE'
git commit -p -m msg
git commit --patch -m msg
git commit --interactive
TABLE

# Measured: the amended commit's contents are `git diff --cached HEAD^`, not HEAD.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
block "an amend re-commits a file at an untested version" "$R" 'git commit --amend --no-edit' \
  MSG_STALE_SUBJECT

# The same broken file that is harmless in a non-adopting repo must fail closed here -- and at
# two DIFFERENT doors, which is what keeps node CM's reach honest. bash's `test -r` sees only
# the entry point; a failed import of the classifier raises inside it.
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
block "a missing entry point blocks in a repo that HAS opted in" "$R" 'git commit -m msg' \
  MSG_CLASSIFIER_MISSING "" "$(stub_gate adopt-noentry OMIT REAL)"
block "a missing classifier blocks at a DIFFERENT door" "$R" 'git commit -m msg' \
  MSG_CLASSIFIER_FAILED "" "$(stub_gate adopt-noclassifier REAL OMIT)"

printf '\n### C. Edges\n\n'

R="$(new_repo adopt)"
mkdir -p "$R/$STOREREL"
printf 'not json' > "$R/$STOREREL/$(key hooks/foo.sh)"
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
block "a corrupt marker fails closed" "$R" 'git commit -m msg' MSG_BAD_MARKER

# A corrupt index makes a collection command exit non-zero with empty stdout. rev-parse
# --show-toplevel does not read the index, so the repo still resolves and the gate gets far
# enough to try collecting.
R="$(new_repo adopt)"
printf 'garbage' > "$R/.git/index"
block "a git failure is never read as 'nothing to check'" "$R" 'git commit -m msg' MSG_GIT_FAILED

R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
allow "a deletion needs no test run" "$R" 'git commit -m msg'
R="$(new_repo adopt)"
git -C "$R" rm -q -- hooks/foo.sh hooks/foo.test.sh
allow "both halves staged as deletions" "$R" 'git commit -m msg'

# --diff-filter=d drops the D half of the rename and keeps the A half. Both halves move, so if
# the OLD paths were in the path set they would form a pair with no marker and block.
R="$(new_repo adopt)"
git -C "$R" mv hooks/foo.sh hooks/foo2.sh
git -C "$R" mv hooks/foo.test.sh hooks/foo2.test.sh
hand_marker "$R" hooks/foo2.sh hooks/foo2.test.sh \
  "$(blob "$R" hooks/foo2.sh)" "$(blob "$R" hooks/foo2.test.sh)" 2026-08-14T00:00:00Z
allow "a rename is gated at its new path only" "$R" 'git commit -m msg'

R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
git -C "$R" rm -q --cached -- hooks/foo.test.sh
block "half a pair is deleted while the other half changes" "$R" 'git commit -m msg' MSG_STALE_TEST

# cat-file -e answering "no" is a defined result; only unexpected git failures are infrastructure.
R="$(new_repo adopt)"
printf 'new\n' > "$R/hooks/new.sh"
printf 'new suite\n' > "$R/hooks/new.test.sh"
git -C "$R" add -- hooks/new.sh hooks/new.test.sh
hand_marker "$R" hooks/new.sh hooks/new.test.sh \
  "$(blob "$R" hooks/new.sh)" "$(blob "$R" hooks/new.test.sh)" 2026-08-14T00:00:00Z
block "an absent base blob is a stale door, not a git-failure door" "$R" \
  'git commit -m msg -- hooks/new.sh' MSG_STALE_TEST

# PLAIN's content source is the index, so the ABSENT probe is "ls-files --stage prints nothing".
# Probing <base> instead passes and allows a commit whose tree drops the test.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
edit "$R" hooks/foo.sh 'v2 subject'
mark "$R" hooks/foo.test.sh
stage "$R" hooks/foo.sh
git -C "$R" rm -q --cached -- hooks/foo.test.sh
block "a member staged for deletion is ABSENT under an index source" "$R" 'git commit -m msg' \
  MSG_STALE_TEST

# Measured on git 2.50.1: -a does not add an untracked file, so the resulting tree holds no
# entry for it. A disk probe reports it present and hashes a blob the commit never contains.
R="$(new_repo adopt)"
mark "$R" hooks/foo.test.sh
git -C "$R" rm -q --cached -- hooks/foo.test.sh
git -C "$R" commit -qm 'untrack the suite'
edit "$R" hooks/foo.sh 'v2 subject'
block "an untracked pair member is ABSENT under -a, never hashed from disk" "$R" \
  'git commit -am msg' MSG_STALE_TEST

printf '\n### C2. TEST_EXEMPT validation — 200 bytes of 0x20-0x7E, consulted by fullmatch\n\n'

R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
EXEMPT_REPO="$R"

# shell_segments.segments() replaces every embedded newline with ';' before TEST_EXEMPT is ever
# extracted (measured 2026-08-20), and ';' is printable ASCII -- a raw \n can never reach this
# validator through the real pipeline, so this scenario uses 0x01 (SOH) instead, a different
# byte in the same rejected 0x00-0x1f range that segments() passes through unchanged.
block "an exemption carrying an embedded control character is rejected" "$EXEMPT_REPO" \
  "$(printf "TEST_EXEMPT='vendored\001upstream' git commit -m msg")" MSG_BAD_EXEMPT

# Regression test for revision 15: Python's `$` matches just before a single trailing newline,
# so re.match ADMITS a value ending in one -- measured on 3.9.6 -- while re.fullmatch refuses it.
# This can no longer be exercised end-to-end: shell_segments.segments() replaces every embedded
# or trailing newline with ';' before TEST_EXEMPT is extracted (measured 2026-08-20), and the
# spec requires exempt come from exactly that extraction (:2191) -- so a raw trailing newline can
# never reach decide-commit-gate.py through the real pipeline. Checked directly against the
# validator instead, which still proves fullmatch (not match) is the implementation in place.
if python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('decide_commit_gate', '$HOOKS/lib/decide-commit-gate.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
value = 'vendored upstream\n'
assert mod._EXEMPT_RE.match(value.encode()) is not None, 're.match should (wrongly) admit a trailing newline'
assert mod._valid_exempt(value) is False, '_valid_exempt must reject a trailing newline via fullmatch'
" 2>/dev/null; then
  ok "the exempt validator rejects a trailing newline via fullmatch, not match"
else
  bad "the exempt validator rejects a trailing newline via fullmatch, not match"
fi

# The same defect reached through the length door: under re.match the {1,200} quantifier
# consumes the 200 printable bytes and `$` matches before the newline, so 201 bytes pass.
BYTES200="$(/usr/bin/awk 'BEGIN { s = ""; while (length(s) < 200) s = s "x"; print s }')"
block "the byte bound is not escapable by a trailing newline" "$EXEMPT_REPO" \
  "TEST_EXEMPT='$BYTES200
' git commit -m msg" MSG_BAD_EXEMPT

# None of U+202E, U+200B, U+200D encodes to bytes inside 0x20-0x7E, so the byte-range check
# refuses them with no locale involved. Regression test for revision 11, whose regex did not
# compile and so could not have distinguished them.
block "an exemption carrying a bidirectional override is rejected" "$EXEMPT_REPO" \
  "$(printf "TEST_EXEMPT='routine \342\200\256cleanup' git commit -m msg")" MSG_BAD_EXEMPT

BYTES201="${BYTES200}x"
block "an over-long exemption reason is rejected, not truncated" "$EXEMPT_REPO" \
  "TEST_EXEMPT='$BYTES201' git commit -m msg" MSG_BAD_EXEMPT

# Revisions 11-13 stated this cost in prose and asserted nothing, so a later "fix" widening the
# class would have passed the whole suite.
block "a non-ASCII exemption reason is rejected" "$EXEMPT_REPO" \
  "$(printf "TEST_EXEMPT='caf\303\251 upstream' git commit -m msg")" MSG_BAD_EXEMPT

# The check matches bytes, so the caller's locale cannot change the verdict. Asserted explicitly
# because that independence is invisible at the call site, and because revisions 11-13 reached
# it by pinning a locale -- a mechanism this scenario must keep passing without.
RUN_ENV="LANG=en_US.UTF-8"
run_hook "$EXEMPT_REPO" "TEST_EXEMPT='vendored upstream' git commit -m msg"
RUN_ENV=""
expect_exit "an ASCII exemption is accepted under a UTF-8 login locale" 0

R="$(new_repo adopt)"
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
block "an empty exemption is not an exemption" "$R" 'TEST_EXEMPT= git commit -m msg' MSG_NO_MARKER

R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
allow "an explicit exemption is honoured" "$R" "TEST_EXEMPT='vendored upstream' git commit -m msg"
expect_log_count "an explicit exemption is logged" "$R" 1
expect_log_field "an explicit exemption is logged" "$R" 2 EXEMPT
expect_log_field "an explicit exemption is logged" "$R" 3 'vendored upstream'
expect_log_field "the exemption precedes any pair, so field 4 has none to name" "$R" 4 '-'

# The enforcing case for the `read -r` pin. Without -r bash eats the backslash (measured) and
# every positive assertion in this suite still passes -- the reason is merely wrong in the one
# record anyone would later audit.
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
allow "an exemption containing a backslash is honoured" "$R" \
  "TEST_EXEMPT='vendored \upstream fix' git commit -m msg"
expect_log_field "a backslash in the reason reaches the log intact" "$R" 3 'vendored \upstream fix'

# The exemption check precedes the form decision; the reverse order makes this unreachable while
# MSG_UNSUPPORTED_FORM's own message recommends it.
FOREIGN="$(new_repo adopt)"
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
allow "an exemption rescues a commit aimed at another repo" "$R" \
  "cd $FOREIGN && TEST_EXEMPT='other repo' git commit -m msg"
expect_log_field "the rescued foreign commit is logged EXEMPT" "$R" 2 EXEMPT

# The exempt regex is checked at node H, only once kind is COMMIT. Folding it into shape
# validation would let any non-commit carrying a stray TEST_EXEMPT block the session.
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
allow "a malformed TEST_EXEMPT on a non-commit does not block" "$R" \
  "TEST_EXEMPT='bad
value' echo not a commit"

printf '\n### C3. Payload shapes and the pre-filter\n\n'

# The pre-filter reads the RAW PAYLOAD, so this door stays reachable. Filtering on the parsed
# command would allow here and make the door, its scenario and its mutant all dead.
R="$(new_repo adopt)"
run_hook "$R" '   ' "$GATE" Bash 'commit the work'
expect_exit "a payload mentioning commit with nothing runnable blocks" 2
expect_msg "a payload mentioning commit with nothing runnable blocks" MSG_NOTHING_RUNNABLE

R="$(new_repo adopt)"
run_hook "$R" '   ' "$GATE" Bash 'tidy the tree'
expect_exit "nothing runnable and no commit anywhere is allowed" 0

R="$(new_repo adopt)"
allow "a payload that mentions commit without being one is allowed" "$R" 'echo "commit this"'

R="$(new_repo adopt)"
run_raw "$(payload_nocmd "$R" Edit)"
expect_exit "a non-Bash tool with no command passes" 0

# subprocess.run with a list never re-lexes an operand. With shell=True this collects two
# nonexistent paths and the git error surfaces as MSG_GIT_FAILED -- a block, so it fails closed,
# but on a commit that was always legitimate.
R="$(new_repo adopt)"
printf 'spaced\n' > "$R/hooks/foo bar.sh"
printf 'spaced suite\n' > "$R/hooks/foo bar.test.sh"
git -C "$R" add -- 'hooks/foo bar.sh' 'hooks/foo bar.test.sh'
git -C "$R" commit -qm spaced
edit "$R" 'hooks/foo bar.sh' 'spaced v2'
mark "$R" 'hooks/foo bar.test.sh'
allow "a pathspec operand containing a space and a semicolon is one path" "$R" \
  "git commit -m msg -- 'hooks/foo bar.sh'"

printf '\n### D. The TSV boundary — the surface ADR 0026 created\n\n'

# No scenario reaches this boundary through a real commit, so every case here stubs the entry
# point. A suite that only ever sees well-formed lines asserts nothing about the check that
# reads them. The `~` separator is used because one shape's payload contains a `|`.
while IFS='~' read -r shape line; do
  [ -n "$shape" ] || continue
  R="$(new_repo adopt)"
  stage "$R" hooks/foo.sh
  block "malformed TSV: $shape" "$R" 'git commit -m msg' MSG_CLASSIFIER_BAD_OUTPUT "" \
    "$(stub_gate "tsv-$(printf '%s' "$shape" | tr ' ' '-')" "$(emit "\"$line\"")" REAL)"
done <<'TABLE'
two lines~ALLOW\t-\t-\t-\nALLOW\t-\t-\t-\n
three fields~ALLOW\t-\t-\n
five fields~ALLOW\t-\t-\t-\t-\n
empty field 3~BLOCK\tMSG_STALE_TEST\t\thooks/foo.sh|hooks/foo.test.sh\n
unknown door in field 2~BLOCK\tMSG_FROM_A_LATER_VERSION\t-\t-\n
out-of-domain field 1~MAYBE\t-\t-\t-\n
TABLE

# Exit 3 is reserved: bash already parsed the same bytes for cwd, so it means two reads of one
# payload disagreed. The dedicated code is what makes this a different door from a broken call.
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
block "a decision call that cannot read the payload is not confused with a broken one" "$R" \
  'git commit -m msg' MSG_BAD_PAYLOAD "" "$(stub_gate exit3 'import sys; sys.exit(3)' REAL)"

# The two component mutants of the mutation floor. They reach one door by different routes: an
# emptied entry point exits 0 printing nothing; an emptied classifier lets the import succeed
# and makes the call raise. A suite emptying only one never exercises the import path.
block "component mutant: an emptied entry point" "$R" 'git commit -m msg' \
  MSG_CLASSIFIER_FAILED "" "$(stub_gate mutant-entry EMPTY REAL)"
block "component mutant: an emptied classifier" "$R" 'git commit -m msg' \
  MSG_CLASSIFIER_FAILED "" "$(stub_gate mutant-classifier REAL EMPTY)"

printf '\n### E. Every door that writes a line, driven from the spec Examples tables\n\n'

# The two tables are transcribed once and drive the loop as data. Do not re-add a per-door copy
# beside them: two spellings of one check is this spec's own named defect class.
DOORS_TSV='MSG_NOTHING_RUNNABLE|-
MSG_BAD_EXEMPT|-
MSG_UNSUPPORTED_FORM|-
MSG_GIT_FAILED|-
MSG_NO_MARKER|pair
MSG_BAD_MARKER|pair
MSG_STALE_SUBJECT|pair
MSG_STALE_TEST|pair'

DOORS_BASH='MSG_CLASSIFIER_MISSING|-
MSG_BAD_PAYLOAD|-
MSG_CLASSIFIER_FAILED|-
MSG_CLASSIFIER_BAD_OUTPUT|-'

# Each door's state, printed as repo TAB command TAB gate. The table above supplies the door
# list and the field-4 expectation; this supplies the only thing a table cannot.
setup_door() {
  local repo cmd gate desc
  gate="$GATE"
  cmd='git commit -m msg'
  desc='-'   # `-`, never empty: a tab is IFS whitespace, so an empty field vanishes on read
  repo="$(new_repo adopt)"
  case "$1" in
    MSG_NOTHING_RUNNABLE)
      cmd='   '; desc='commit the work' ;;
    MSG_BAD_EXEMPT)
      stage "$repo" hooks/foo.sh
      # single-line on purpose: this setup crosses a here-doc, which keeps one line only
      cmd="$(printf "TEST_EXEMPT='caf\303\251 upstream' git commit -m msg")" ;;
    MSG_UNSUPPORTED_FORM)
      stage "$repo" hooks/foo.sh
      cmd='git commit -p -m msg' ;;
    MSG_GIT_FAILED)
      printf 'garbage' > "$repo/.git/index" ;;
    MSG_NO_MARKER)
      edit "$repo" hooks/foo.sh 'v2 subject'
      stage "$repo" hooks/foo.sh ;;
    MSG_BAD_MARKER)
      mkdir -p "$repo/$STOREREL"
      printf 'not json' > "$repo/$STOREREL/$(key hooks/foo.sh)"
      edit "$repo" hooks/foo.sh 'v2 subject'
      stage "$repo" hooks/foo.sh ;;
    MSG_STALE_SUBJECT)
      mark "$repo" hooks/foo.test.sh
      edit "$repo" hooks/foo.sh 'v2 subject'
      stage "$repo" hooks/foo.sh ;;
    MSG_STALE_TEST)
      mark "$repo" hooks/foo.test.sh
      edit "$repo" hooks/foo.test.sh 'v2 suite'
      stage "$repo" hooks/foo.test.sh ;;
    MSG_CLASSIFIER_MISSING)
      stage "$repo" hooks/foo.sh
      gate="$(stub_gate door-noentry OMIT REAL)" ;;
    MSG_BAD_PAYLOAD)
      stage "$repo" hooks/foo.sh
      gate="$(stub_gate door-exit3 'import sys; sys.exit(3)' REAL)" ;;
    MSG_CLASSIFIER_FAILED)
      stage "$repo" hooks/foo.sh
      gate="$(stub_gate door-noclassifier REAL OMIT)" ;;
    MSG_CLASSIFIER_BAD_OUTPUT)
      stage "$repo" hooks/foo.sh
      gate="$(stub_gate door-badshape "$(emit '"MAYBE\t-\t-\t-\n"')" REAL)" ;;
    *)
      return 1 ;;
  esac
  printf '%s\t%s\t%s\t%s' "$repo" "$cmd" "$gate" "$desc"
}

while IFS='|' read -r door want4; do
  [ -n "$door" ] || continue
  setup="$(setup_door "$door")" || { bad "door $door has no setup"; continue; }
  IFS=$'\t' read -r repo cmd gate desc <<EOF
$setup
EOF
  [ "$want4" = pair ] && want4="$PAIR"
  [ "$desc" = '-' ] && desc=""
  run_hook "$repo" "$cmd" "$gate" Bash "$desc"
  expect_exit "door $door" 2
  expect_msg "door $door" "$door"
  expect_log_count "door $door" "$repo" 1
  expect_log_field "door $door" "$repo" 2 BLOCK
  expect_log_field "door $door" "$repo" 3 "$door"
  expect_log_field "door $door" "$repo" 4 "$want4"
done <<EOF
$DOORS_TSV
$DOORS_BASH
EOF

# The two log scenarios that assert NO line is written. Without them a logger appending on every
# path passes every positive assertion above.
R="$(new_repo adopt)"
stage "$R" docs/notes.md
allow "an allowed commit writes no log line" "$R" 'git commit -m msg'
expect_log_count "an allowed commit writes no log line" "$R" 0

# MSG_NO_PYTHON is the thirteenth door and the only machine-global one: no toplevel has been
# resolved, so there is no <repo>/hooks/state/ to append to. The PATH below grants exactly the
# externals the gate is allowed to need -- adding one to the gate means adding it here.
NOPY="$TMP/nopy"
mkdir -p "$NOPY"
for u in cat git mkdir chmod date rm sed awk tr cut wc dirname basename mktemp stat touch id uname; do
  for d in /bin /usr/bin; do
    [ -x "$d/$u" ] && ln -sf "$d/$u" "$NOPY/$u" && break
  done
done
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
RUN_ENV="PATH=$NOPY"
run_hook "$R" 'git commit -m msg'
RUN_ENV=""
expect_exit "python3 missing blocks at MSG_NO_PYTHON" 2
expect_msg "python3 missing blocks at MSG_NO_PYTHON" MSG_NO_PYTHON
expect_log_count "the door that fires before a repo is known writes no line" "$R" 0

# Nine of the thirteen doors fire before a pair exists; field 4 is total because it has a
# defined value for them, not because every door reaches one.
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
edit "$R" docs/notes.md 'notes v2'
block "a block with no pair still writes a well-formed line" "$R" \
  'git commit -m msg -i -- docs/notes.md' MSG_UNSUPPORTED_FORM
expect_log_field "a block with no pair still writes a well-formed line" "$R" 4 '-'

printf '\n### F. The store and the log are default-deny, and both components can create them\n\n'

# Whichever component runs second cannot repair a loose mode it did not set, so BOTH orderings
# are asserted. A suite exercising only the winning order passes while the other ships 0755.
# The umask is set explicitly in every case here: inheriting 0077 reports 0600 on a 0644 file.

R="$(new_repo adopt)"
# ALLOW never calls write_log (exit 0 is silent, by design -- header comment, line 24), so this
# repo needs the gate to actually reach a BLOCK door to exercise store creation at all.
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
( umask 022; run_hook "$R" 'git commit -m msg' )
expect_mode "gate first: hooks/state/ is created 0700" "$R/hooks/state" 700
( cd "$R" && umask 022 && python3 -I "$WRITER" hooks/foo.test.sh ) >/dev/null 2>&1
expect_mode "gate first, then writer: hooks/state/ stays 0700" "$R/hooks/state" 700
expect_mode "gate first, then writer: the marker is 0600" "$R/$STOREREL/$(key hooks/foo.sh)" 600

R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
( cd "$R" && umask 022 && python3 -I "$WRITER" hooks/foo.test.sh ) >/dev/null 2>&1
expect_mode "writer first: hooks/state/ is created 0700" "$R/hooks/state" 700
expect_mode "writer first: the marker is 0600" "$R/$STOREREL/$(key hooks/foo.sh)" 600
( umask 022; run_hook "$R" 'git commit -m msg' )
expect_mode "writer first, then gate: hooks/state/ stays 0700" "$R/hooks/state" 700

# The case mkdir -p -m and os.makedirs both fail: measured, neither touches a PRE-EXISTING
# directory's mode, so no creation-time flag satisfies this and an explicit chmod is required.
R="$(new_repo adopt)"
stage "$R" hooks/foo.sh
mkdir -p "$R/hooks/state"
chmod 755 "$R/hooks/state"
( cd "$R" && umask 022 && python3 -I "$WRITER" hooks/foo.test.sh ) >/dev/null 2>&1
expect_mode "pre-existing 0755 store, writer runs: repaired to 0700" "$R/hooks/state" 700

R="$(new_repo adopt)"
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
mkdir -p "$R/hooks/state"
chmod 755 "$R/hooks/state"
( umask 022; run_hook "$R" 'git commit -m msg' )
expect_mode "pre-existing 0755 store, gate runs: repaired to 0700" "$R/hooks/state" 700

# `>>` alone creates the log 0644 under a default umask, which is why the spec requires a
# touch-then-chmod before the first append. Every other log scenario passes against a 0644 log.
R="$(new_repo adopt)"
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
( umask 022; run_hook "$R" 'git commit -m msg' )
expect_mode "a log created under umask 022 is 0600, not the append default" "$R/$LOGREL" 600

R="$(new_repo adopt)"
edit "$R" hooks/foo.sh 'v2 subject'
stage "$R" hooks/foo.sh
mkdir -p "$R/hooks/state"
: > "$R/$LOGREL"
chmod 644 "$R/$LOGREL"
( umask 022; run_hook "$R" 'git commit -m msg' )
expect_mode "a pre-existing 0644 log is repaired to 0600" "$R/$LOGREL" 600

# ---------------------------------------------------------------------------
printf '\ntest-marker-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
