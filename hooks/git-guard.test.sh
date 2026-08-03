#!/usr/bin/env bash
# git-guard.test.sh — drives the hook with PreToolUse JSON on stdin (the production
# code path). Run: bash hooks/git-guard.test.sh
#
# Why this suite exists: git-guard shipped with no tests at all, and for as long as
# it has existed both of its guards matched a regex ANCHORED to the start of the
# command string. Anything chained -- `git add -- x && git commit -m y`, the shape
# this repo uses constantly -- never matched, so the guard body never ran and the
# hook exited 0 without having evaluated anything. Commits reached `main` that the
# allowlist forbids; the guard's stated policy and its behaviour had diverged
# silently, and no test could catch it because there were no tests.
#
# The commands below are DATA fed to the hook on stdin. Nothing here executes them.
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/git-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name  test
printf 'seed\n' > "$REPO/CODING_MEMORY.md"
git -C "$REPO" add -- CODING_MEMORY.md
git -C "$REPO" commit -qm seed
git -C "$REPO" branch feature

pass=0; fail=0

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }

# A checkout that cannot proceed -- e.g. a tracked file left modified by an
# earlier case -- otherwise fails silently and every later case runs on the
# WRONG branch, reporting a real-looking pass or fail for the wrong reason.
on_branch() {
  git -C "$REPO" checkout -q "$1" || {
    printf 'HARNESS — could not switch to %s (dirty worktree?)\n' "$1" >&2
    exit 1
  }
}

stage() { # $@ = paths to create and stage; no args = stage nothing
  git -C "$REPO" reset -q
  local f
  for f in "$@"; do
    mkdir -p "$REPO/$(dirname "$f")"
    printf 'change %s\n' "$$" > "$REPO/$f"
    git -C "$REPO" add -- "$f"
  done
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
# Guard 1 — default-branch commit
# ---------------------------------------------------------------------------
on_branch main
stage src/app.sh

run_case "plain commit, source staged on main -> block"      2 'git commit -m msg'
run_case "CHAINED commit, source staged on main -> block"    2 'git add -- src/app.sh && git commit -m msg'
run_case "chained with ; separator -> block"                 2 'git add -- src/app.sh ; git commit -m msg'
run_case "chained with || separator -> block"                2 'false || git commit -m msg'
run_case "newline-separated -> block"                        2 'git add -- src/app.sh
git commit -m msg'
run_case "rtk wrapper, plain -> block"                       2 'rtk git commit -m msg'
run_case "rtk wrapper, CHAINED -> block"                     2 'git add -- src/app.sh && rtk git commit -m msg'
run_case "env prefix before commit -> block"                 2 'GIT_AUTHOR_NAME=x git commit -m msg'

# False positives are as damaging as fail-opens: a guard that blocks legitimate
# work gets disabled. Quoted text is one token and can never hold a command slot.
run_case "commit named inside a quoted message -> allow"     0 'echo "remember to git commit later"'
run_case "commit as a commit-message substring -> allow"     0 'git log --grep "git commit"'
run_case "unrelated command -> allow"                        0 'ls -la'

# The brainstorm exception, and the docs/** widening that keeps the real
# workflow legal once the guard actually evaluates.
stage CODING_MEMORY.md
run_case "CODING_MEMORY.md only on main -> allow"            0 'git commit -m notes'
stage coding-memory/verdicts.jsonl
run_case "coding-memory/* on main -> allow"                  0 'git commit -m verdicts'
stage docs/features/x.md
run_case "docs/** on main -> allow (widened)"                0 'git commit -m spec'
stage docs/features/x.md
run_case "docs/** on main, CHAINED -> allow (widened)"       0 'git add -- docs/features/x.md && git commit -m spec'
stage docs/features/x.md src/app.sh
run_case "docs/** mixed with source on main -> block"        2 'git commit -m mixed'

# Off the default branch the guard has no opinion at all.
on_branch feature
stage src/app.sh
run_case "source on a feature branch -> allow"               0 'git add -- src/app.sh && git commit -m msg'

# ---------------------------------------------------------------------------
# Guard 1 — EMPTY INDEX at hook time.
#
# PreToolUse fires BEFORE the command runs, so a command that does its own
# `git add` reaches the hook with nothing staged. Every case below therefore
# stages ONLY inside the command string and never calls `stage`: that helper
# pre-creates precisely the state which hid this bug from 33 tests, a
# 24,016-case fuzz run and a mutation round. A fixture that creates what the
# command under test would create itself cannot see the bug, and neither
# fuzzing nor mutation can find it -- both validate assertions, never the
# fixture's premise.
#
# "Empty index -> allow" would be a fail-OPEN, because three shapes commit
# content the index does not show. Each gets a case pinning it blocked.
# ---------------------------------------------------------------------------
on_branch main

# A tracked, COMMITTED pair. `stage`-created files are untracked, and neither
# `commit -a` nor `--amend` ever picks an untracked file up -- so without this
# the -a cases below would pass for the wrong reason.
mkdir -p "$REPO/src" "$REPO/docs"
printf 'v1\n' > "$REPO/src/tracked.sh"
printf 'v1\n' > "$REPO/docs/tracked.md"
git -C "$REPO" add -- src/tracked.sh docs/tracked.md
git -C "$REPO" commit -qm "tracked pair"

empty_index() { # $@ = tracked paths to modify in the WORKTREE ONLY, never staged
  # --hard, not a plain reset: a plain one clears the index but leaves the
  # PREVIOUS case's edits sitting in the worktree, so a case asking for "only
  # docs modified" silently also had source modified, and `commit -a` read the
  # leftover. The helper has to establish the whole state it claims, not part.
  #
  # `clean -fdq` for the same reason one level out: earlier sections leave
  # UNTRACKED files behind, and `git add -A` stages those too -- so "only docs
  # modified" would still have handed a source file to the -A cases.
  git -C "$REPO" reset -q --hard
  git -C "$REPO" clean -fdq
  local f
  for f in "$@"; do printf 'change %s\n' "$$" > "$REPO/$f"; done
}

# The regression itself: documentation, refused because the add had not run yet.
empty_index
run_case "docs pathspec, add INSIDE the command, empty index -> allow"   0 'git add -- docs/tracked.md && git commit -m msg -- docs/tracked.md'
run_case "bare commit, empty index -> allow (git itself refuses it)"     0 'git commit -m msg'

# Same shape, source file: the index is equally empty, so only the pathspec
# distinguishes these two. This is the case a naive "empty -> allow" breaks.
run_case "source pathspec, add INSIDE the command, empty index -> block"  2 'git add -- src/tracked.sh && git commit -m msg -- src/tracked.sh'

# -a commits the WORKTREE, which an index read cannot see.
empty_index src/tracked.sh
run_case "commit -a, source modified, empty index -> block"              2 'git commit -a -m msg'
empty_index docs/tracked.md
run_case "commit -a, only docs modified, empty index -> allow"           0 'git commit -a -m msg'

# --amend re-writes HEAD's tree; HEAD here is the source-bearing "tracked pair".
empty_index
run_case "commit --amend, source in HEAD, empty index -> block"          2 'git commit --amend --no-edit'

# No `--` separator: telling a pathspec from an option value needs a table of
# which git flags take arguments. The hook does not have one, and this file's
# stated fail direction is that "cannot tell" means block.
run_case "docs path with NO -- separator, empty index -> block"          2 'git commit -m msg docs/tracked.md'

# ---------------------------------------------------------------------------
# Guard 1 — THE CHAIN'S OWN `git add`.
#
# The fourth way a commit carries content the index cannot show, and the one
# the first version of this fix missed: the command stages its OWN files a
# moment before committing. With no pathspec on the `commit`, asking the
# command what it will commit finds nothing -- but the `git add` runs first, so
# the index is emphatically not empty by the time git looks.
#
# "git refuses an empty commit itself" is therefore FALSE for exactly the shape
# this repo uses constantly. These cases are the four regressions that reasoning
# produced, each measured against main before being written.
# ---------------------------------------------------------------------------
on_branch main

empty_index src/tracked.sh
run_case "chain stages SOURCE, commit takes no pathspec -> block"        2 'git add -- src/tracked.sh && git commit -m msg'
run_case "chain stages source with -A -> block"                          2 'git add -A && git commit -m msg'
run_case "chain stages source with . -> block"                           2 'git add . && git commit -m msg'

empty_index docs/tracked.md
run_case "chain stages DOCS, commit takes no pathspec -> allow"          0 'git add -- docs/tracked.md && git commit -m msg'
run_case "chain stages docs with -A -> allow"                            0 'git add -A && git commit -m msg'

# An explicit pathspec on the commit wins: git commits those paths and leaves
# whatever else the chain staged sitting in the index, uncommitted.
empty_index src/tracked.sh docs/tracked.md
run_case "chain stages source, commit names only docs -> allow"          0 'git add -- src/tracked.sh && git commit -m msg -- docs/tracked.md'

# Abbreviated and paths-from-a-file options: git accepts an unambiguous prefix,
# and --pathspec-from-file hides its paths in a file this hook cannot read.
# Neither can be understood, so both must fail closed rather than sail through.
empty_index
run_case "abbreviated --amen -> block"                                   2 'git commit --amen --no-edit'
run_case "--pathspec-from-file hides its paths -> block"                 2 'git commit --pathspec-from-file=list'

# ...but the ordinary harmless options must NOT become false positives.
run_case "harmless --no-edit with nothing staged -> allow"               0 'git commit --no-edit -m msg'
run_case "harmless --no-verify with nothing staged -> allow"             0 'git commit --no-verify -m msg'

# Hand the worktree back clean. These cases deliberately leave tracked files
# modified, and `feature` does not carry them -- so the next branch switch
# would refuse, which used to happen without a word.
git -C "$REPO" reset -q --hard
git -C "$REPO" clean -fdq

# ---------------------------------------------------------------------------
# Guard 2 — force push
# ---------------------------------------------------------------------------
on_branch feature
run_case "bare --force on a feature branch -> block"         2 'git push --force'
run_case "bare --force CHAINED -> block"                     2 'git fetch && git push --force'
run_case "bare -f CHAINED -> block"                          2 'git fetch && git push -f'
run_case "--force-with-lease on a feature branch -> allow"   0 'git push --force-with-lease'
run_case "--force-with-lease CHAINED on feature -> allow"    0 'git fetch && git push --force-with-lease'

# The flag must belong to the SAME segment as the push. Searching the whole
# command string made an unrelated argument elsewhere block a legitimate push.
run_case "--force in a LATER segment -> allow"               0 'git push && echo --force'
run_case "--force in an EARLIER segment -> allow"            0 'echo --force && git push'
run_case "--force inside a quoted string -> allow"           0 'git push -m "do not use --force"'

on_branch main
run_case "--force-with-lease on main -> block"               2 'git push --force-with-lease'
run_case "--force-with-lease CHAINED on main -> block"       2 'git fetch && git push --force-with-lease'
run_case "plain push on main -> allow"                       0 'git push'

# ---------------------------------------------------------------------------
# docs/ is allowed by FILE TYPE, not by directory
# ---------------------------------------------------------------------------
on_branch main
stage docs/tool.sh
run_case "a script under docs/ on main -> block"             2 'git commit -m tool'
stage docs/notes.md.sh
run_case "a .sh merely ending in .md.sh on main -> block"    2 'git commit -m sneaky'
stage docs/a/b/deep.md
run_case "markdown nested any depth on main -> allow"        0 'git commit -m deep'

# ---------------------------------------------------------------------------
# Fail direction. git-guard protects against a destructive or unreviewable action,
# so "cannot tell" must mean "block" -- the opposite of doc-guard, whose matching
# case is pinned in doc-guard.test.sh. Until this pair existed the two hooks'
# opposite behaviours lived only in comments, with nothing holding them apart.
#
# The hook resolves its classifier relative to its own location, so copying it
# somewhere with no lib/ beside it is exactly the "classifier missing" condition.
# ---------------------------------------------------------------------------
ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN"
cp "$HOOK" "$ORPHAN/git-guard.sh"

orphan_case() { # $1 desc, $2 want-exit, $3 command
  local desc="$1" want="$2" cmd="$3" got
  ( cd "$REPO" && payload "$cmd" | bash "$ORPHAN/git-guard.sh" >/dev/null 2>&1 )
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

orphan_case "no classifier, commit -> FAIL CLOSED"           2 'git commit -m msg'
# The cost of failing closed, stated as a test rather than left as a surprise:
# this hook runs on every Bash call, so an unreadable classifier stops all of them.
orphan_case "no classifier, unrelated command -> FAIL CLOSED" 2 'ls -la'

# ---------------------------------------------------------------------------
printf '\ngit-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
