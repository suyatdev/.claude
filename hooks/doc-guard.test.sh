#!/usr/bin/env bash
# doc-guard.test.sh — drives the PreToolUse block-at-commit path with JSON on stdin
# (the production code path). Run: bash hooks/doc-guard.test.sh
#
# Why this suite exists: doc-guard had no tests, and its commit detector was the
# same start-anchored regex as git-guard's. Any chained command -- `git add -- x &&
# git commit -m y` -- skipped the check entirely, so the documentation guarantee
# this hook exists to provide was not being enforced on the commit shape the repo
# actually uses.
#
# The second, subtler defect pinned here: `-a`/`--all`/`-am` switches doc-guard from
# inspecting the staged index to diffing HEAD. That flag was matched anywhere in the
# whole command string, so `-a` belonging to some OTHER segment silently changed
# which files the guard judged.
#
# The commands below are DATA fed to the hook on stdin. Nothing here executes them.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK="$(cd "$(dirname "$0")" && pwd)/doc-guard.sh"
# shellcheck disable=SC1091  # this test's own dynamically-resolved path, not user input
source "$(cd "$(dirname "$0")" && pwd)/lib/guard_test_helpers.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/src"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name  test
for n in 1 2 3; do printf 'line\n' > "$REPO/src/f$n.sh"; done
printf 'seed\n' > "$REPO/CODING_MEMORY.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm seed

pass=0; fail=0

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }

reset_tree() {
  git -C "$REPO" reset -q
  git -C "$REPO" checkout -q -- .
}

stage() { # $@ = paths to rewrite and stage
  reset_tree
  local f
  for f in "$@"; do
    mkdir -p "$REPO/$(dirname "$f")"
    printf 'edited\n' > "$REPO/$f"
    git -C "$REPO" add -- "$f"
  done
}

stage_big() { # $1 = path; rewrite it with enough lines to pass the 20-line threshold
  reset_tree
  : > "$REPO/$1"
  local i
  for i in $(seq 1 25); do printf 'new line %s\n' "$i" >> "$REPO/$1"; done
  git -C "$REPO" add -- "$1"
}

modify_unstaged() { # $@ = tracked paths to dirty WITHOUT staging
  reset_tree
  local f
  for f in "$@"; do printf 'dirty\n' > "$REPO/$f"; done
}

run_case() { # $1 desc, $2 want-exit, $3 command string
  local desc="$1" want="$2" cmd="$3" got
  ( cd "$REPO" && payload "$cmd" | bash "$HOOK" >/dev/null 2>&1 )
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

# ---------------------------------------------------------------------------
# Substantial source change with no documentation staged
# ---------------------------------------------------------------------------
stage src/f1.sh src/f2.sh src/f3.sh
run_case "3 source files, plain commit -> block"            2 'git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh
run_case "3 source files, CHAINED commit -> block"          2 'git add -- src && git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh
run_case "3 source files, ; separator -> block"             2 'git add -- src ; git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh
run_case "3 source files, rtk CHAINED -> block"             2 'git add -- src && rtk git commit -m msg'
stage_big src/f1.sh
run_case "1 file over the line threshold, CHAINED -> block" 2 'git add -- src/f1.sh && git commit -m msg'

# ---------------------------------------------------------------------------
# Satisfied, or not substantial enough to care about
# ---------------------------------------------------------------------------
stage src/f1.sh src/f2.sh src/f3.sh docs/decisions/adr.md
run_case "docs ride along, CHAINED -> allow"                0 'git add -A && git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh CODING_MEMORY.md
run_case "CODING_MEMORY.md alone no longer satisfies has_doc -> block" 2 'git add -A && git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh docs/note.md
run_case "docs/ ride along, CHAINED -> allow"               0 'git add -A && git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh
run_case "Doc-Exempt trailer, CHAINED -> allow"             0 'git add -- src && git commit -m "msg

Doc-Exempt: mechanical rename"'
stage src/f1.sh
run_case "single trivial file, CHAINED -> allow"            0 'git add -- src/f1.sh && git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh
run_case "not a commit at all -> allow"                     0 'git add -- src && git status'
stage src/f1.sh src/f2.sh src/f3.sh
run_case "commit named in a quoted string -> allow"         0 'echo "then git commit it"'

# ---------------------------------------------------------------------------
# `-a` must bind to the commit segment, not to any token in the line
# ---------------------------------------------------------------------------
modify_unstaged src/f1.sh src/f2.sh src/f3.sh
run_case "commit -am with unstaged edits -> block"          2 'git commit -am msg'
modify_unstaged src/f1.sh src/f2.sh src/f3.sh
run_case "commit -am CHAINED -> block"                      2 'git fetch && git commit -am msg'
# Nothing is staged here, so this commit would record nothing. The `-a` belongs to
# `ls`, and reading it as the commit's made the guard judge unrelated dirty files.
modify_unstaged src/f1.sh src/f2.sh src/f3.sh
run_case "-a owned by ANOTHER segment -> allow"             0 'git commit -m msg && ls -a'

# ---------------------------------------------------------------------------
# Fail direction. This hook fails OPEN -- a missing note is not worth blocking work
# over -- which is the exact OPPOSITE of git-guard on the identical condition, whose
# matching case is pinned in git-guard.test.sh. The two directions are a deliberate
# design split that until now lived only in comments, so a future refactor could
# have quietly aligned them and nothing would have failed.
#
# The hook resolves its classifier relative to its own location, so copying it
# somewhere with no lib/ beside it is exactly the "classifier missing" condition.
# ---------------------------------------------------------------------------
ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN"
cp "$HOOK" "$ORPHAN/doc-guard.sh"

# Staged state that WOULD be blocked if the classifier were readable, so a pass here
# can only mean the fail-open path ran -- not that there was nothing to complain about.
stage src/f1.sh src/f2.sh src/f3.sh
( cd "$REPO" && payload 'git commit -m msg' | bash "$ORPHAN/doc-guard.sh" >/dev/null 2>&1 )
got=$?
if [ "$got" -eq 0 ]; then
  printf 'ok   — no classifier, blockable commit -> FAIL OPEN (exit %s)\n' "$got"; pass=$((pass+1))
else
  printf 'FAIL — no classifier, blockable commit -> FAIL OPEN (want 0, got %s)\n' "$got"; fail=$((fail+1))
fi

# Control: the same staged state through the real hook still blocks, so the case
# above is proving the fail-open path and not a broken fixture.
run_case "control: same state, real hook -> block"          2 'git commit -m msg'

# ---------------------------------------------------------------------------
# global-option-blindness (docs/features/global-option-blindness.md, task 4).
# Both scenarios fall out of the classifier fix (task 2) with NO new code in
# THIS file: doc-guard.sh only ever asks has_fact COMMIT, which the
# classifier now correctly answers for a bucket-1-prefixed commit and
# correctly withholds for a SCOPE_UNKNOWN-denied one. Pinned here as a real
# regression guard, not padding -- a future edit to either file could
# silently break either half, and nothing before this suite would catch it.
# ---------------------------------------------------------------------------
stage src/f1.sh src/f2.sh src/f3.sh
run_case "bucket-1 global option no longer hides the commit -> block" 2 'git --no-pager commit -m x'

stage src/f1.sh src/f2.sh src/f3.sh
run_case "SCOPE_UNKNOWN (cannot-tell) -> doc-guard stays silent" 0 'git -C . commit -m x'
got_stdout="$(cd "$REPO" && payload 'git -C . commit -m x' | bash "$HOOK" 2>/dev/null)"
if [ -z "$got_stdout" ]; then
  printf 'ok   —   ...no permissionDecision written; git-guard is the only guard that prompts\n'; pass=$((pass+1))
else
  printf 'FAIL —   ...no permissionDecision written\n  got:\n%s\n' "$got_stdout"; fail=$((fail+1))
fi

# ---------------------------------------------------------------------------
# worktree-location-guard task 5: the fact READER. git-guard fixed this bug in
# its own copy and recorded why; doc-guard kept the unquoted `for f in $facts`
# form, which splits on bash's default IFS -- and that includes the TAB carrying
# a path in `COMMIT_PATH<tab><path>`. The classifier now emits seven more
# tab-bearing facts, so the exposure was about to widen; the reader was ported
# BEFORE any of them shipped.
#
# doc-guard reads exactly two facts, COMMIT and COMMIT_ALL, so the discriminating
# file name is one of those. Committing a file called COMMIT_ALL by pathspec used
# to make the split hand back the token COMMIT_ALL, which switched the hook from
# inspecting the (trivial) index to diffing HEAD -- where three unrelated dirty
# source files were waiting. Behaviour, not the fact set: the fact set necessarily
# grows, so asserting it is unchanged is impossible.
# ---------------------------------------------------------------------------
# reset_tree FIRST, and commit with a pathspec: a bare `git commit` here would
# sweep the previous case's staged src/ files into HEAD, and every later case
# would then stage a file identical to HEAD, produce an empty numstat and allow.
reset_tree
printf 'seed\n' > "$REPO/COMMIT_ALL"
git -C "$REPO" add -- COMMIT_ALL
git -C "$REPO" commit -qm 'add a file whose name is a fact token' -- COMMIT_ALL

modify_unstaged src/f1.sh src/f2.sh src/f3.sh
printf 'edited\n' > "$REPO/COMMIT_ALL"
git -C "$REPO" add -- COMMIT_ALL
run_case "a file NAMED COMMIT_ALL does not word-split into the fact -> allow" 0 \
  'git commit -m msg -- COMMIT_ALL'

# Control, so the row above cannot pass because the fixture was inert: the SAME
# dirty tree with a real -am commit still blocks. If this ever allows, the case
# above is proving nothing.
modify_unstaged src/f1.sh src/f2.sh src/f3.sh
run_case "  ...control: the same dirty tree with a real -am -> block"        2 'git commit -am msg'

# The new facts must not disturb doc-guard at all. Each command below emits at
# least one SEG_* fact the hook has never seen, and each must land exactly where
# it landed before task 5.
stage src/f1.sh src/f2.sh src/f3.sh
run_case "SEG_CD rides along, commit still judged -> block"   2 'cd . && git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh docs/note.md
run_case "SEG_CD rides along, docs satisfy it -> allow"       0 'cd . && git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh
run_case "SEG_ENV rides along, commit still judged -> block"  2 'GIT_AUTHOR_NAME=x git commit -m msg'
stage src/f1.sh src/f2.sh src/f3.sh
run_case "SEG_OPAQUE rides along, no commit fact -> allow"    0 'timeout 5 git commit -m msg'

# SEG_UNPARSED — this guard DELIBERATELY still allows, and that is a decision, not an
# oversight. The observability judge (round 3, 2026-08-31) proposed making both this guard
# and git-guard.sh refuse a command the lexer cannot read. git-guard.sh now does, because
# its own header already commits it to failing closed when it cannot inspect a command.
# This one says the opposite in two places -- "it fails OPEN (missing note) rather than
# block legitimate work" -- and reversing a documented decision was not what the change was
# for. The harm the judge found (an unreviewable commit reaching main, a force push) is
# git-guard's to refuse and now is refused there; what stays open here is a missing
# documentation note, which is exactly what this guard's policy says is not worth blocking
# work over. Pinned so the choice is visible rather than merely absent.
run_case "SEG_UNPARSED -> allow, deliberately (see git-guard)" 0 "git commit -m 'unbalanced"

# ---------------------------------------------------------------------------
printf '\ndoc-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
