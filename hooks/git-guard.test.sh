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
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

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
# The policy these cases pin (ADR 0014): an empty index is relaxed for EXACTLY
# one shape -- a commit that names its own paths after `--`, with nothing on the
# line that could add to them. Everything else denies, which is what `main` does
# today, so this branch is never weaker than `main` on any command.
#
# Two earlier rounds tried the other design -- work out what the whole command
# line will have staged by the time git looks -- and each round's enumeration was
# measured short (first `git add`, then nine more staging commands). The cases
# below are therefore split into "the commit names it" and "everything else",
# with no case anywhere asserting what a SIBLING command would stage.
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

# THE ONE RELAXATION, and the regression this branch exists to remove:
# documentation, refused only because the `add` had not run yet.
empty_index
run_case "docs pathspec, add INSIDE the command, empty index -> allow"   0 'git add -- docs/tracked.md && git commit -m msg -- docs/tracked.md'
run_case "docs pathspec, no add at all, empty index -> allow"            0 'git commit -m msg -- docs/tracked.md'

# Same shape, source file: the index is equally empty, so only the pathspec
# distinguishes these two. This is the case a naive "empty -> allow" breaks.
run_case "source pathspec, add INSIDE the command, empty index -> block"  2 'git add -- src/tracked.sh && git commit -m msg -- src/tracked.sh'

# A pathspec is EXCLUSIVE: git commits those paths and leaves whatever else the
# chain staged sitting in the index, uncommitted. So the guard may judge the
# named paths alone -- and only here, because only here has it read them.
empty_index src/tracked.sh docs/tracked.md
run_case "chain stages source, commit names only docs -> allow"          0 'git add -- src/tracked.sh && git commit -m msg -- docs/tracked.md'

# ---------------------------------------------------------------------------
# Guard 1 — EVERYTHING ELSE WITH AN EMPTY INDEX DENIES.
#
# Not because the hook worked out what these would commit -- it deliberately
# does not try -- but because it could not read the answer off the command line,
# and "cannot tell" means block. Every case here is also what `main` does today,
# which is the property that makes the relaxation above provably safe.
# ---------------------------------------------------------------------------
empty_index docs/tracked.md

run_case "bare commit, empty index -> block"                             2 'git commit -m msg'
run_case "commit -a, only docs modified, empty index -> block"           2 'git commit -a -m msg'
run_case "chain stages DOCS, commit takes no pathspec -> block"          2 'git add -- docs/tracked.md && git commit -m msg'
run_case "chain stages docs with -A -> block"                            2 'git add -A && git commit -m msg'
# Harmless options do not make a commit readable; there is still no pathspec.
run_case "harmless --no-edit with nothing staged -> block"               2 'git commit --no-edit -m msg'
run_case "harmless --no-verify with nothing staged -> block"             2 'git commit --no-verify -m msg'

empty_index src/tracked.sh
run_case "commit -a, source modified, empty index -> block"              2 'git commit -a -m msg'
run_case "chain stages SOURCE, commit takes no pathspec -> block"        2 'git add -- src/tracked.sh && git commit -m msg'
run_case "chain stages source with -A -> block"                          2 'git add -A && git commit -m msg'
run_case "chain stages source with . -> block"                           2 'git add . && git commit -m msg'

# --amend re-writes HEAD's tree; HEAD here is the source-bearing "tracked pair".
# Abbreviated and paths-from-a-file options: git accepts an unambiguous prefix,
# and --pathspec-from-file hides its paths in a file this hook cannot read.
# No `--` separator: telling a pathspec from an option value would need a table
# of which git flags take arguments, and a leftover token is only a SUSPECTED path.
empty_index
run_case "commit --amend, source in HEAD, empty index -> block"          2 'git commit --amend --no-edit'
run_case "abbreviated --amen -> block"                                   2 'git commit --amen --no-edit'
run_case "--pathspec-from-file hides its paths -> block"                 2 'git commit --pathspec-from-file=list'
run_case "docs path with NO -- separator, empty index -> block"          2 'git commit -m msg docs/tracked.md'

# ---------------------------------------------------------------------------
# Guard 1 — THE NINE OTHER COMMANDS THAT FILL THE INDEX.
#
# `git add` is not special. Round 2 measured every command below as a regression
# under the previous design -- blocked on `main`, allowed by this branch -- for
# the single reason that the enumeration listed `git add` and not them. They are
# pinned here NOT because the guard now knows them: it deliberately knows none of
# them. They pass because the commit names no paths, exactly like every other
# unreadable shape. If a future change starts inferring what a sibling command
# stages, this block turns red before the reasoning gets a second chance.
#
# These strings are DATA. Nothing here runs them, so no fixture state is needed.
# ---------------------------------------------------------------------------
empty_index src/tracked.sh

run_case "git rm stages a deletion -> block"             2 'git rm src/tracked.sh && git commit -m msg'
run_case "git mv stages a rename -> block"               2 'git mv src/tracked.sh src/moved.sh && git commit -m msg'
run_case "git reset --soft re-stages HEAD -> block"      2 'git reset --soft HEAD~1 && git commit -m msg'
run_case "git checkout HEAD~1 -- <path> stages -> block" 2 'git checkout HEAD~1 -- src/tracked.sh && git commit -m msg'
run_case "git restore --staged stages -> block"          2 'git restore --source=HEAD~1 --staged -- src/tracked.sh && git commit -m msg'
run_case "git apply --cached stages -> block"            2 'git apply --cached patch.diff && git commit -m msg'
run_case "git stash pop --index stages -> block"         2 'git stash pop --index && git commit -m msg'
run_case "git cherry-pick -n stages -> block"            2 'git cherry-pick -n abc123 && git commit -m msg'
run_case "git revert -n stages -> block"                 2 'git revert -n abc123 && git commit -m msg'

# ---------------------------------------------------------------------------
# Guard 1 — A PATHSPEC IS ONLY THE WHOLE STORY WHEN NOTHING CAN ADD TO IT.
#
# The relaxation reads the paths after `--`. Four options make that reading
# incomplete while leaving it looking perfectly well-formed:
#   -i/--include  commits the INDEX AS WELL as the named paths
#   -o/--only     unrecognised, so its effect on the file set is unknown
#   -a/--all      also commits tracked worktree edits
#   --amend       also re-writes HEAD's tree
# The first three used to sail through, because a `--` returned the paths before
# the flag table was ever consulted.
# ---------------------------------------------------------------------------
empty_index docs/tracked.md

run_case "-i also commits the index, docs pathspec -> block"      2 'git add -- src/tracked.sh && git commit -i -m msg -- docs/tracked.md'
run_case "--include, docs pathspec -> block"                      2 'git commit --include -m msg -- docs/tracked.md'
run_case "-o is not understood, docs pathspec -> block"           2 'git commit -o -m msg -- docs/tracked.md'
run_case "--only, docs pathspec -> block"                         2 'git commit --only -m msg -- docs/tracked.md'
run_case "-a alongside a docs pathspec -> block"                  2 'git commit -a -m msg -- docs/tracked.md'
run_case "--amend alongside a docs pathspec -> block"             2 'git commit --amend -m msg -- docs/tracked.md'

# ---------------------------------------------------------------------------
# Guard 1 — ONE LINE, SEVERAL COMMITS.
#
# Facts reach the hook as a flat SET with no segment identity, so the paths named
# by one commit used to answer for the whole line. In the first case the second
# commit really does carry src/tracked.sh: `main` blocks it and this branch
# allowed it, because the union of facts said "documentation". A fact that GRANTS
# permission has to hold for every commit on the line -- which is the rule
# PUSH_FORCE already follows in the denying direction.
# ---------------------------------------------------------------------------
empty_index docs/tracked.md src/tracked.sh

run_case "docs commit, then a bare second commit -> block"  2 'git commit -m a -- docs/tracked.md && git add -- src/tracked.sh && git commit -m b'
run_case "bare commit FIRST, docs commit second -> block"   2 'git commit -m a && git commit -m b -- docs/tracked.md'
run_case "second commit after a ; separator -> block"       2 'git commit -m a -- docs/tracked.md ; git commit -m b'
run_case "second commit carries -a -> block"                2 'git commit -m a -- docs/tracked.md && git commit -a -m b'
run_case "one names docs, the other names source -> block"  2 'git commit -m a -- docs/tracked.md && git commit -m b -- src/tracked.sh'
# The rule must not cost the shape it is meant to leave alone.
run_case "BOTH commits name only docs -> allow"             0 'git commit -m a -- docs/tracked.md && git commit -m b -- docs/tracked.md'

# ---------------------------------------------------------------------------
# Guard 1 — A PATHSPEC IS JUDGED AS A PATH, NOT AS A STRING.
#
# The allowlist is a `case` over the literal token, so `coding-memory/../src/x`
# satisfied `coding-memory/*` while git resolves it to a source file, and a .md
# file anywhere in the repo satisfied `docs/*.md` by way of `docs/../`. A `..`
# COMPONENT means the string the hook read and the file git will commit are two
# different things, and the hook may only judge what it has actually read. A `..`
# inside a file NAME traverses nothing and stays allowed.
# ---------------------------------------------------------------------------
run_case "a .. component escapes coding-memory/ -> block"   2 'git commit -m msg -- coding-memory/../src/tracked.sh'
run_case "a .. component escapes docs/ -> block"            2 'git commit -m msg -- docs/../notes.md'
run_case "a leading ../ -> block"                           2 'git commit -m msg -- ../docs/tracked.md'
run_case ".. inside a FILENAME is not traversal -> allow"   0 'git commit -m msg -- docs/v1..v2.md'

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

# A fact carries its path after a TAB (`COMMIT_PATH<tab>docs/x.md`), and tab is in
# bash's default IFS -- so splitting the fact stream on whitespace turned a FILE
# named PUSH_FORCE into the force-push fact and blocked an unrelated push. Facts
# are one per line and must be compared as whole lines.
run_case "a file named PUSH_FORCE is not a force push -> allow" 0 'git commit -m msg -- PUSH_FORCE && git push'

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
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
