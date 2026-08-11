#!/usr/bin/env bash
# measure-matrix.sh — reproduces the spec's changed-cell matrix
# (docs/features/git-guard-detached-head.md, "What changes — measured, not
# estimated") against the FINAL patched hook: current_branch via
# `symbolic-ref`, the head-name-tightened `sequencer_in_progress`, and the
# case-form `on_main`. Patches a COPY of the hook in a scratch dir; the
# repo's own hooks/git-guard.sh is never touched.
#
# Every fixture asserts the state it claims to build before it is measured —
# a fixture that silently fails to reach its state makes the row it feeds
# meaningless while still reporting a result.
#
# Run: bash hooks/measure-matrix.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ORIG="$WORK/git-guard.orig.sh"
PATCHED="$WORK/git-guard.patched.sh"
cp "$REPO/hooks/git-guard.sh" "$ORIG"
mkdir -p "$WORK/lib"; cp "$REPO/hooks/lib/"* "$WORK/lib/" 2>/dev/null

python3 - "$ORIG" "$PATCHED" <<'PY'
import sys
src = open(sys.argv[1]).read()
old = '''current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

on_main() {
  local b
  b="$(current_branch)"
  [ "$b" = "main" ] || [ "$b" = "master" ]
}'''
new = '''current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}

sequencer_in_progress() {
  local marker dir
  for marker in rebase-merge rebase-apply; do
    dir="$(git rev-parse --git-path "$marker" 2>/dev/null)"
    [ -e "$dir" ] || continue
    case "$(cat "$dir/head-name" 2>/dev/null)" in
      refs/heads/main|refs/heads/master) return 1 ;;
    esac
    return 0
  done
  for marker in CHERRY_PICK_HEAD REVERT_HEAD MERGE_HEAD; do
    [ -e "$(git rev-parse --git-path "$marker" 2>/dev/null)" ] && return 0
  done
  return 1
}

on_main() {
  local b
  b="$(current_branch)"
  case "$b" in
    main|master) return 0 ;;
    "") sequencer_in_progress && return 1; return 0 ;;
    *) return 1 ;;
  esac
}'''
assert old in src, "anchor not found -- hook text drifted"
open(sys.argv[2], 'w').write(src.replace(old, new))
PY
[ $? -eq 0 ] || { echo "HARNESS — patch failed" >&2; exit 1; }
chmod +x "$ORIG" "$PATCHED"

FAILED=0
ok()  { printf 'ok   — %s\n' "$1"; }
bad() { printf 'FAIL — %s\n' "$1" >&2; FAILED=1; }
assert_eq() { # $1 label  $2 expected  $3 actual
  if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 (want [$2], got [$3])"; fi
}

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }
run() { # $1 hook  $2 dir  $3 command -> exit code
  ( cd "$2" 2>/dev/null || { echo 99; exit; }; payload "$3" | bash "$1" >/dev/null 2>&1; echo $? )
}

# Builds fixture $1 under $WORK/$1 and prints its path. State is asserted
# separately by assert_fixture() so a caller always sees which check failed.
mk() {
  local d="$WORK/$1"
  mkdir -p "$d"
  ( cd "$d"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    case "$1" in
      detached)
        git init -q -b main .; mkdir -p src docs
        echo a > src/app.sh; echo d > docs/notes.md; git add -A; git commit -q -m c1
        echo b >> src/app.sh; git add -A; git commit -q -m c2
        git checkout -q --detach HEAD; echo c >> src/app.sh; git add -- src/app.sh ;;
      detached_docs)
        git init -q -b main .; mkdir -p src docs
        echo a > src/app.sh; echo d > docs/notes.md; git add -A; git commit -q -m c1
        git checkout -q --detach HEAD; echo e >> docs/notes.md; git add -- docs/notes.md ;;
      rebase_from_main)
        git init -q -b main .; mkdir -p src
        for i in 1 2 3; do echo $i > src/f$i.sh; git add -A; git commit -q -m c$i; done
        GIT_SEQUENCE_EDITOR="sed -i '' '1s/^pick/edit/'" git rebase -i HEAD~2 >/dev/null 2>&1
        echo x >> src/f1.sh; git add -A ;;
      cherry_conflict)
        git init -q -b main .; mkdir -p src
        echo base > src/app.sh; git add -A; git commit -q -m base
        git checkout -q -b other; echo other > src/app.sh; git add -A; git commit -q -m other
        git checkout -q main; echo mainline > src/app.sh; git add -A; git commit -q -m mainline
        git checkout -q --detach main; git cherry-pick other >/dev/null 2>&1
        echo resolved > src/app.sh; git add -A ;;
      unborn_main)
        git init -q -b main .; mkdir -p src; echo a > src/app.sh; git add -A ;;
      unborn_feat)
        git init -q -b feat/x .; mkdir -p src; echo a > src/app.sh; git add -A ;;
      feature)
        git init -q -b main .; mkdir -p src
        echo a > src/app.sh; git add -A; git commit -q -m c1
        git checkout -q -b feat/x; echo b >> src/app.sh; git add -- src/app.sh ;;
      nonrepo) : ;;
    esac ) >/dev/null 2>&1
  echo "$d"
}

# The state each fixture claims to have built -- asserted against the same
# ground the hook itself reads (symbolic-ref, sequencer marker files).
assert_fixture() {
  local name="$1" d="$2" symref markexists headname m
  case "$name" in
    detached|detached_docs)
      symref="$(cd "$d" && git symbolic-ref --short HEAD 2>/dev/null)"
      assert_eq "$name: branchless" "" "$symref"
      markexists=no
      for m in rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD MERGE_HEAD; do
        ( cd "$d" && [ -e "$(git rev-parse --git-path "$m" 2>/dev/null)" ] ) && markexists=yes
      done
      assert_eq "$name: no sequencer marker (no-operation fixture)" no "$markexists" ;;
    rebase_from_main)
      symref="$(cd "$d" && git symbolic-ref --short HEAD 2>/dev/null)"
      assert_eq "$name: branchless" "" "$symref"
      headname="$(cd "$d" && cat "$(git rev-parse --git-path rebase-merge)/head-name" 2>/dev/null)"
      assert_eq "$name: head-name" "refs/heads/main" "$headname" ;;
    cherry_conflict)
      symref="$(cd "$d" && git symbolic-ref --short HEAD 2>/dev/null)"
      assert_eq "$name: branchless" "" "$symref"
      ( cd "$d" && [ -e "$(git rev-parse --git-path CHERRY_PICK_HEAD 2>/dev/null)" ] ) \
        && ok "$name: CHERRY_PICK_HEAD present" || bad "$name: CHERRY_PICK_HEAD present"
      ;;
    unborn_main) assert_eq "$name: on branch main"   main   "$(cd "$d" && git symbolic-ref --short HEAD 2>/dev/null)" ;;
    unborn_feat) assert_eq "$name: on branch feat/x" feat/x "$(cd "$d" && git symbolic-ref --short HEAD 2>/dev/null)" ;;
    feature)     assert_eq "$name: on branch feat/x" feat/x "$(cd "$d" && git symbolic-ref --short HEAD 2>/dev/null)" ;;
    nonrepo)
      ( cd "$d" && git rev-parse --git-dir >/dev/null 2>&1 ) \
        && bad "$name: is a git repository" || ok "$name: not a git repository" ;;
  esac
}

printf '%-34s %-46s %6s %6s %s\n' STATE COMMAND BEFORE AFTER VERDICT
printf '%.0s-' {1..108}; echo

check() { # $1 state  $2 cmd  $3 expect_before  $4 expect_after
  local d; d=$(mk "$1")
  assert_fixture "$1" "$d"
  local b a v
  b=$(run "$ORIG" "$d" "$2"); a=$(run "$PATCHED" "$d" "$2")
  if [ "$b" = "$3" ] && [ "$a" = "$4" ]; then v="ok"; else v="MISMATCH (spec said $3/$4)"; FAILED=1; fi
  printf '%-34s %-46s %6s %6s %s\n' "$1" "$2" "$b" "$a" "$v"
}

# rows matching the spec's changed-cell matrix
check detached          'git commit -m msg'                             0 2
check detached           'git push --force-with-lease origin HEAD:main' 0 2
check nonrepo            'cd /elsewhere/repo && git commit -m msg -- src/app.sh' 0 2
check nonrepo            'git push --force-with-lease'                  0 2
check unborn_main        'git commit -m msg'                            0 2
check detached_docs      'git commit -m msg'                            0 0
check rebase_from_main    'git commit -m msg'                           0 2
check cherry_conflict    'git commit -m msg'                            0 0
check unborn_feat        'git commit -m msg'                            0 0
check feature             'git commit -m msg'                           0 0
check feature             'git push --force-with-lease'                 0 0
check feature             'git push --force'                            2 2

echo
echo "empty-index probe (nothing staged, no pathspec) -- spec claims 0 -> 2:"
D=$(mk detached); ( cd "$D" && git reset -q ) 2>/dev/null
b=$(run "$ORIG" "$D" 'git commit -m msg'); a=$(run "$PATCHED" "$D" 'git commit -m msg')
printf '%-34s %-46s %6s %6s\n' "detached (index emptied)" "git commit -m msg" "$b" "$a"
assert_eq "detached, empty index: before" 0 "$b"
assert_eq "detached, empty index: after"  2 "$a"

[ "$FAILED" -eq 0 ] || { echo; echo "measure-matrix.sh: one or more assertions FAILED" >&2; exit 1; }
echo
echo "all assertions passed."
