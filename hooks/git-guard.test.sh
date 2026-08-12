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

# ---------------------------------------------------------------------------
# State helpers for the git-guard-detached-head matrix
# (docs/features/git-guard-detached-head.md). Each builds exactly ONE
# branchless or sequencer state and asserts it was reached before handing
# back control -- a fixture that silently misses its target state makes
# every row built on it report a real-looking pass for the wrong reason,
# which is exactly what writing real assertions into step 1's measurement
# scripts caught twice. Directory-returning helpers print the repo path on
# stdout and build it under $TMP, so the file's EXIT trap cleans it up.
# Nothing here is wired into run_case yet -- that starts with run_case_in,
# the next checklist item, because run_case hardcodes `cd "$REPO"` and most
# of these states need their own directory.
# ---------------------------------------------------------------------------

assert_symref() { # $1 dir, $2 wanted `symbolic-ref --short HEAD` (may be empty)
  local dir="$1" want="$2" got
  got="$(cd "$dir" && git symbolic-ref --short HEAD 2>/dev/null)"
  [ "$got" = "$want" ] || {
    printf 'HARNESS — %s: wanted symbolic-ref [%s], got [%s]\n' "$dir" "$want" "$got" >&2
    exit 1
  }
}

assert_marker() { # $1 dir, $2 marker name, $3 yes|no
  local dir="$1" marker="$2" want="$3" got
  got=$( ( cd "$dir" && [ -e "$(git rev-parse --git-path "$marker" 2>/dev/null)" ] ) && echo yes || echo no )
  [ "$got" = "$want" ] || {
    printf 'HARNESS — %s: wanted %s marker=%s, got %s\n' "$dir" "$marker" "$want" "$got" >&2
    exit 1
  }
}

assert_headname() { # $1 dir, $2 marker dir (rebase-merge|rebase-apply), $3 wanted head-name
  local dir="$1" marker="$2" want="$3" got
  got="$(cd "$dir" && cat "$(git rev-parse --git-path "$marker")/head-name" 2>/dev/null)"
  [ "$got" = "$want" ] || {
    printf 'HARNESS — %s: wanted %s head-name [%s], got [%s]\n' "$dir" "$marker" "$want" "$got" >&2
    exit 1
  }
}

mk_dir_repo() { # $1 initial branch -> fresh configured repo dir under $TMP, prints its path
  local dir br="$1"
  dir="$(mktemp -d "$TMP/repo.XXXXXX")"
  git -C "$dir" init -q -b "$br"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name  test
  printf '%s' "$dir"
}

# Plain detached HEAD in the SHARED $REPO, no sequencer operation running
# (rows 1, 2, 6). Detaches at whatever commit is currently checked out --
# call on_branch first to choose which history it detaches from.
detached() {
  git -C "$REPO" checkout -q --detach HEAD || {
    printf 'HARNESS — could not detach HEAD (dirty worktree?)\n' >&2
    exit 1
  }
  assert_symref "$REPO" ""
}

# A directory that is not a git repository at all (rows 3, 4).
nonrepo_dir() {
  local dir
  dir="$(mktemp -d "$TMP/nonrepo.XXXXXX")"
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 && {
    printf 'HARNESS — %s unexpectedly is a git repository\n' "$dir" >&2
    exit 1
  }
  printf '%s' "$dir"
}

# A branch with no commits yet -- `symbolic-ref` names it, but HEAD does not
# resolve (rows 5, 7).
unborn_repo() { # $1 branch name
  local dir br="$1"
  dir="$(mk_dir_repo "$br")"
  assert_symref "$dir" "$br"
  git -C "$dir" rev-parse HEAD >/dev/null 2>&1 && {
    printf 'HARNESS — %s: HEAD resolves, branch is not unborn\n' "$dir" >&2
    exit 1
  }
  printf '%s' "$dir"
}

# `git rebase -i` stopped at an `edit` step, HEAD detached, head-name
# pointing at whichever branch the rebase was started from (rows 8, 15).
rebase_edit_stopped() { # $1 branch to rebase FROM
  local dir br="$1" i
  dir="$(mk_dir_repo main)"
  printf 'seed\n' > "$dir/seed.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm seed
  [ "$br" = main ] || git -C "$dir" checkout -q -b "$br"
  for i in 1 2 3; do
    printf '%s\n' "$i" > "$dir/f$i.sh"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "c$i"
  done
  ( cd "$dir" && GIT_SEQUENCE_EDITOR="sed -i '' '1s/^pick/edit/'" git rebase -i HEAD~2 ) >/dev/null 2>&1
  assert_symref "$dir" ""
  assert_headname "$dir" rebase-merge "refs/heads/$br"
  printf '%s' "$dir"
}

# A cherry-pick stopped on a conflict, HEAD detached (row 9).
cherry_pick_conflict() {
  local dir
  dir="$(mk_dir_repo main)"
  printf 'base\n' > "$dir/app.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm base
  git -C "$dir" checkout -q -b other
  printf 'other\n' > "$dir/app.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm other
  git -C "$dir" checkout -q main
  printf 'mainline\n' > "$dir/app.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm mainline
  git -C "$dir" checkout -q --detach main
  ( cd "$dir" && git cherry-pick other ) >/dev/null 2>&1
  assert_symref "$dir" ""
  assert_marker "$dir" CHERRY_PICK_HEAD yes
  printf '%s' "$dir"
}

# A merge stopped on a conflict while a NAMED main is checked out -- not
# detached at all (row 16), the case that pins `sequencer_in_progress` as
# consulted only from the branchless arm of `on_main`.
named_main_merge_conflict() {
  local dir
  dir="$(mk_dir_repo main)"
  printf 'base\n' > "$dir/app.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm base
  git -C "$dir" checkout -q -b other
  printf 'other\n' > "$dir/app.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm other
  git -C "$dir" checkout -q main
  printf 'mainline\n' > "$dir/app.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm mainline
  ( cd "$dir" && git merge other ) >/dev/null 2>&1
  assert_symref "$dir" main
  assert_marker "$dir" MERGE_HEAD yes
  printf '%s' "$dir"
}

# `git rebase --apply` stopped on a conflict, HEAD detached, head-name
# pointing at whichever branch the rebase was started from (rows 17, 19).
rebase_apply_stopped() { # $1 branch to rebase FROM
  local dir br="$1" i
  dir="$(mk_dir_repo main)"
  printf 'seed\n' > "$dir/seed.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm seed
  [ "$br" = main ] || git -C "$dir" checkout -q -b "$br"
  for i in 1 2 3; do
    printf '%s\n' "$i" > "$dir/h$i.sh"
    git -C "$dir" add -A
    git -C "$dir" commit -qm "h$i"
  done
  git -C "$dir" checkout -q -b tmp HEAD~2
  printf 'conflict\n' > "$dir/h2.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm conf
  git -C "$dir" checkout -q "$br"
  ( cd "$dir" && git rebase --apply tmp ) >/dev/null 2>&1
  assert_symref "$dir" ""
  assert_headname "$dir" rebase-apply "refs/heads/$br"
  printf '%s' "$dir"
}

# A repo whose checked-out branch is literally `master` (row 18) -- nothing
# in the existing 77 cases, nor any other new row, ever feeds that string to
# on_main's `case`.
master_repo() {
  local dir
  dir="$(mk_dir_repo main)"
  printf 'seed\n' > "$dir/seed.sh"; git -C "$dir" add -A; git -C "$dir" commit -qm seed
  git -C "$dir" branch master
  git -C "$dir" checkout -q master
  assert_symref "$dir" master
  printf '%s' "$dir"
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

_run_case_common() { # $1 dir, $2 desc, $3 want-exit, $4 command string
  local dir="$1" desc="$2" want="$3" cmd="$4" got
  ( cd "$dir" && payload "$cmd" | bash "$HOOK" >/dev/null 2>&1 )
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

run_case() { # $1 desc, $2 want-exit, $3 command string
  _run_case_common "$REPO" "$1" "$2" "$3"
}

# Like run_case, but against a caller-supplied directory instead of the
# module-level $REPO -- needed for rows whose fixture is its own repository
# (a non-repo cwd, an unborn branch, a named-master checkout, an
# apply-backend rebase) rather than a checkout state of $REPO.
run_case_in() { # $1 dir, $2 desc, $3 want-exit, $4 command string
  _run_case_common "$1" "$2" "$3" "$4"
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
# Detached-HEAD / sequencer-state matrix (docs/features/git-guard-detached-head.md)
#
# Each want-exit below is the table's "After" column -- the behavior the fix
# in a later checklist step must produce -- not necessarily today's exit code.
# Rows 1-5, 15 and 17 are therefore EXPECTED TO FAIL here: their Before and
# After differ and the fix has not landed. Rows 6-14, 16, 18 and 19 have no
# gap between Before and After and must already be green. A row in the first
# group that passes now is testing nothing -- see the checklist.
# ---------------------------------------------------------------------------
on_branch main
git -C "$REPO" reset -q --hard
git -C "$REPO" clean -fdq

# Rows 1, 2, 6 — plain detached HEAD in the shared $REPO.
detached
stage src/app.sh
run_case "row 1: detached, source staged -> block"            2 'git commit -m msg'
run_case "row 2: detached, force-with-lease -> block"         2 'git push --force-with-lease origin HEAD:main'
stage docs/notes.md
run_case "row 6: detached, docs only staged -> allow"         0 'git commit -m msg'

# Rows 3, 4 — not a git repository at all.
NONREPO_DIR="$(nonrepo_dir)"
run_case_in "$NONREPO_DIR" "row 3: non-repository, commit -- src/app.sh -> block" 2 'git commit -m msg -- src/app.sh'
run_case_in "$NONREPO_DIR" "row 4: non-repository, force-with-lease -> block"     2 'git push --force-with-lease'

# Row 5 — unborn main, source staged.
UNBORN_MAIN_DIR="$(unborn_repo main)"
mkdir -p "$UNBORN_MAIN_DIR/src"
printf 'x\n' > "$UNBORN_MAIN_DIR/src/app.sh"
git -C "$UNBORN_MAIN_DIR" add -- src/app.sh
run_case_in "$UNBORN_MAIN_DIR" "row 5: unborn main, source staged -> block" 2 'git commit -m msg'

# Row 7 — unborn feat/x, source staged.
UNBORN_FEAT_DIR="$(unborn_repo feat/x)"
mkdir -p "$UNBORN_FEAT_DIR/src"
printf 'x\n' > "$UNBORN_FEAT_DIR/src/app.sh"
git -C "$UNBORN_FEAT_DIR" add -- src/app.sh
run_case_in "$UNBORN_FEAT_DIR" "row 7: unborn feat/x, source staged -> allow" 0 'git commit -m msg'

# Row 8 — rebase -i stopped at edit, started from a feature branch, amended.
REBASE_EDIT_FEAT_DIR="$(rebase_edit_stopped feat/x)"
mkdir -p "$REBASE_EDIT_FEAT_DIR/src"
printf 'x\n' > "$REBASE_EDIT_FEAT_DIR/src/app.sh"
git -C "$REBASE_EDIT_FEAT_DIR" add -- src/app.sh
run_case_in "$REBASE_EDIT_FEAT_DIR" "row 8: rebase-edit stop (feat/x), amend -> allow" 0 'git commit --amend --no-edit'

# Row 15 — the same stop, but started from main: the carve-out's merge-backend bound.
REBASE_EDIT_MAIN_DIR="$(rebase_edit_stopped main)"
mkdir -p "$REBASE_EDIT_MAIN_DIR/src"
printf 'x\n' > "$REBASE_EDIT_MAIN_DIR/src/app.sh"
git -C "$REBASE_EDIT_MAIN_DIR" add -- src/app.sh
run_case_in "$REBASE_EDIT_MAIN_DIR" "row 15: rebase-edit stop (main), source staged -> block" 2 'git commit -m msg'

# Row 9 — cherry-pick stopped on a conflict, HEAD detached, conflict resolved and staged.
CHERRY_DIR="$(cherry_pick_conflict)"
printf 'resolved\n' > "$CHERRY_DIR/app.sh"
git -C "$CHERRY_DIR" add -- app.sh
run_case_in "$CHERRY_DIR" "row 9: cherry-pick conflict, source staged -> allow" 0 'git commit -m msg'

# Row 10 — mid-rebase; the classifier raises no fact for `rebase --continue` itself.
REBASE_CONTINUE_DIR="$(rebase_edit_stopped feat/x)"
run_case_in "$REBASE_CONTINUE_DIR" "row 10: detached mid-rebase, add + continue -> allow" 0 'git add -- src/app.sh && git rebase --continue'

# Rows 11-13 — a plainly named feature branch, off which the guard has no opinion.
on_branch feature
git -C "$REPO" reset -q --hard
git -C "$REPO" clean -fdq
stage src/app.sh
run_case "row 11: feature branch, source staged -> allow"     0 'git commit -m msg'
run_case "row 12: feature branch, force-with-lease -> allow"  0 'git push --force-with-lease'
run_case "row 13: feature branch, bare force -> block"        2 'git push --force'

# Row 14 — named main, docs only staged.
on_branch main
git -C "$REPO" reset -q --hard
git -C "$REPO" clean -fdq
stage docs/notes.md
run_case "row 14: main, docs only staged -> allow"            0 'git commit -m msg'

# Row 16 — named main mid-merge conflict: sequencer_in_progress must stay
# reachable only from the branchless arm, never override a plainly named branch.
MERGE_CONFLICT_DIR="$(named_main_merge_conflict)"
printf 'resolved\n' > "$MERGE_CONFLICT_DIR/app.sh"
git -C "$MERGE_CONFLICT_DIR" add -- app.sh
run_case_in "$MERGE_CONFLICT_DIR" "row 16: named main mid-merge, source staged -> block" 2 'git commit -m msg'

# Row 17 — rebase --apply stopped, started from master: the carve-out's apply-backend bound.
REBASE_APPLY_MASTER_DIR="$(rebase_apply_stopped master)"
mkdir -p "$REBASE_APPLY_MASTER_DIR/src"
printf 'x\n' > "$REBASE_APPLY_MASTER_DIR/src/app.sh"
git -C "$REBASE_APPLY_MASTER_DIR" add -- src/app.sh
run_case_in "$REBASE_APPLY_MASTER_DIR" "row 17: rebase --apply stop (master), source staged -> block" 2 'git commit -m msg'

# Row 18 — a checked-out branch literally named master.
MASTER_DIR="$(master_repo)"
mkdir -p "$MASTER_DIR/src"
printf 'x\n' > "$MASTER_DIR/src/app.sh"
git -C "$MASTER_DIR" add -- src/app.sh
run_case_in "$MASTER_DIR" "row 18: named master, source staged -> block" 2 'git commit -m msg'

# Row 19 — rebase --apply stopped, started from feat/x: the only row that can
# see a dropped rebase-apply clause, because it is the only one expecting 0.
REBASE_APPLY_FEAT_DIR="$(rebase_apply_stopped feat/x)"
mkdir -p "$REBASE_APPLY_FEAT_DIR/src"
printf 'x\n' > "$REBASE_APPLY_FEAT_DIR/src/app.sh"
git -C "$REBASE_APPLY_FEAT_DIR" add -- src/app.sh
run_case_in "$REBASE_APPLY_FEAT_DIR" "row 19: rebase --apply stop (feat/x), source staged -> allow" 0 'git commit -m msg'

# ---------------------------------------------------------------------------
printf '\ngit-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
