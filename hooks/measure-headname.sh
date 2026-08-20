#!/usr/bin/env bash
# measure-headname.sh — measures the head-name-tightened carve-out
# (`sequencer_in_progress` with the refs/heads/main|master clause) against
# the loose one (any sequencer marker, regardless of which branch it will
# move) that an earlier draft of the spec considered. Reproduces the carve-
# out bounds table in docs/features/git-guard-detached-head.md ("The
# in-progress-operation carve-out"). Patches COPIES only, never the repo's
# own hook.
#
# Every fixture asserts the state it claims to build before it is measured.
#
# Run: bash hooks/measure-headname.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cp "$REPO/hooks/git-guard.sh" "$W/orig.sh"
mkdir -p "$W/lib"; cp "$REPO/hooks/lib/"* "$W/lib/" 2>/dev/null

mk_hook() { # $1 out  $2 loose|tight
python3 - "$W/orig.sh" "$1" "$2" <<'PY'
import sys
src = open(sys.argv[1]).read(); mode = sys.argv[3]
old = '''current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

on_main() {
  local b
  b="$(current_branch)"
  [ "$b" = "main" ] || [ "$b" = "master" ]
}'''
loose = '''sequencer_in_progress() {
  local marker
  for marker in rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD MERGE_HEAD; do
    [ -e "$(git rev-parse --git-path "$marker" 2>/dev/null)" ] && return 0
  done
  return 1
}'''
tight = '''sequencer_in_progress() {
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
}'''
new = '''current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}

''' + (loose if mode == "loose" else tight) + '''

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
}
mk_hook "$W/loose.sh" loose
mk_hook "$W/tight.sh" tight
[ -s "$W/loose.sh" ] && [ -s "$W/tight.sh" ] || { echo "HARNESS -- patch failed" >&2; exit 1; }

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }
hook() { ( cd "$2" && payload "$3" | bash "$1" >/dev/null 2>&1; echo $? ); }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

FAILED=0
ok()  { printf 'ok   — %s\n' "$1"; }
bad() { printf 'FAIL — %s\n' "$1" >&2; FAILED=1; }
assert_eq() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 (want [$2], got [$3])"; }

symref() { ( cd "$1" && git symbolic-ref --short HEAD 2>/dev/null ); }
marker_present() { # $1 dir  $2 marker name -> yes/no
  ( cd "$1" && [ -e "$(git rev-parse --git-path "$2" 2>/dev/null)" ] ) && echo yes || echo no
}
head_name() { # $1 dir  $2 marker name (rebase-merge|rebase-apply) -> content or empty
  ( cd "$1" && cat "$(git rev-parse --git-path "$2")/head-name" 2>/dev/null )
}

row() { printf '  %-38s loose=%s tight=%s\n' "$1" "$2" "$3"; }

echo "### 1. rebase -i started FROM main (the hole)"
D="$W/a"; mkdir -p "$D"
( cd "$D"; git init -q -b main .; mkdir -p src
  for i in 1 2 3; do echo $i > src/f$i.sh; git add -A; git commit -q -m c$i; done
  GIT_SEQUENCE_EDITOR="sed -i '' '1s/^pick/edit/'" git rebase -i HEAD~2 >/dev/null 2>&1
  echo bd > src/backdoor.sh; git add -- src/backdoor.sh ) >/dev/null 2>&1
assert_eq "1: branchless"  ""              "$(symref "$D")"
assert_eq "1: head-name"   refs/heads/main "$(head_name "$D" rebase-merge)"
l=$(hook "$W/loose.sh" "$D" 'git commit -m x -- src/backdoor.sh')
t=$(hook "$W/tight.sh" "$D" 'git commit -m x -- src/backdoor.sh')
row "commit source" "$l" "$t"
assert_eq "1: loose lets the backdoor through" 0 "$l"
assert_eq "1: tight closes it"                 2 "$t"

echo "### 2. rebase -i started FROM feat/x (must stay carved out)"
D="$W/b"; mkdir -p "$D"
( cd "$D"; git init -q -b main .; mkdir -p src
  echo a > src/a.sh; git add -A; git commit -q -m base
  git checkout -q -b feat/x
  for i in 1 2; do echo $i > src/g$i.sh; git add -A; git commit -q -m g$i; done
  GIT_SEQUENCE_EDITOR="sed -i '' '1s/^pick/edit/'" git rebase -i HEAD~2 >/dev/null 2>&1
  echo z >> src/g1.sh; git add -A ) >/dev/null 2>&1
assert_eq "2: branchless"  ""                "$(symref "$D")"
assert_eq "2: head-name"   refs/heads/feat/x "$(head_name "$D" rebase-merge)"
l=$(hook "$W/loose.sh" "$D" 'git commit --amend --no-edit')
t=$(hook "$W/tight.sh" "$D" 'git commit --amend --no-edit')
row "commit --amend" "$l" "$t"
assert_eq "2: loose carves out" 0 "$l"
assert_eq "2: tight carves out" 0 "$t"

echo "### 3. cherry-pick conflict while detached (must stay carved out)"
D="$W/c"; mkdir -p "$D"
( cd "$D"; git init -q -b main .; mkdir -p src
  echo base > src/app.sh; git add -A; git commit -q -m base
  git checkout -q -b other; echo other > src/app.sh; git add -A; git commit -q -m other
  git checkout -q main; echo mainline > src/app.sh; git add -A; git commit -q -m mainline
  git checkout -q --detach main; git cherry-pick other >/dev/null 2>&1
  echo fixed > src/app.sh; git add -A ) >/dev/null 2>&1
assert_eq "3: branchless" "" "$(symref "$D")"
assert_eq "3: CHERRY_PICK_HEAD present" yes "$(marker_present "$D" CHERRY_PICK_HEAD)"
l=$(hook "$W/loose.sh" "$D" 'git commit -m x')
t=$(hook "$W/tight.sh" "$D" 'git commit -m x')
row "commit" "$l" "$t"
assert_eq "3: loose carves out" 0 "$l"
assert_eq "3: tight carves out" 0 "$t"

echo "### 4. plain detached, no operation (must stay blocked)"
D="$W/d"; mkdir -p "$D"
( cd "$D"; git init -q -b main .; mkdir -p src
  echo a > src/app.sh; git add -A; git commit -q -m c1
  git checkout -q --detach HEAD; echo b >> src/app.sh; git add -- src/app.sh ) >/dev/null 2>&1
assert_eq "4: branchless" "" "$(symref "$D")"
for m in rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD MERGE_HEAD; do
  assert_eq "4: no $m (no-operation fixture)" no "$(marker_present "$D" "$m")"
done
l=$(hook "$W/loose.sh" "$D" 'git commit -m x')
t=$(hook "$W/tight.sh" "$D" 'git commit -m x')
row "commit source" "$l" "$t"
assert_eq "4: loose still blocks" 2 "$l"
assert_eq "4: tight still blocks" 2 "$t"

echo "### 5. rebase --apply from main (does head-name exist for that backend?)"
D="$W/e"; mkdir -p "$D"
( cd "$D"; git init -q -b main .; mkdir -p src
  for i in 1 2 3; do echo $i > src/h$i.sh; git add -A; git commit -q -m h$i; done
  git checkout -q -b tmp HEAD~2; echo conflict > src/h2.sh; git add -A; git commit -q -m conf
  git checkout -q main; git rebase --apply tmp >/dev/null 2>&1 ) >/dev/null 2>&1
assert_eq "5: branchless"                                     "" "$(symref "$D")"
assert_eq "5: rebase-apply present"                            yes "$(marker_present "$D" rebase-apply)"
assert_eq "5: rebase-apply head-name"                           refs/heads/main "$(head_name "$D" rebase-apply)"
assert_eq "5: rebase-merge absent (apply backend, not merge)"  no "$(marker_present "$D" rebase-merge)"

[ "$FAILED" -eq 0 ] || { echo; echo "measure-headname.sh: one or more assertions FAILED" >&2; exit 1; }
echo
echo "all assertions passed."
