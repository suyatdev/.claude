#!/usr/bin/env bash
# verify-carveout-hole.sh — independently checks the round-3 observability
# judge's findings 1-3 in docs/features/git-guard-detached-head.md: a
# carve-out with no head-name clause reopens the exact hole the fix closes,
# `git switch -c` cannot escape a running rebase or merge, and a NAMED
# main/master checkout stays guarded through a merge conflict regardless of
# the carve-out. Patches COPIES of the hook only, never the repo's own.
#
# Run: bash hooks/verify-carveout-hole.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
cp "$REPO/hooks/git-guard.sh" "$W/orig.sh"
mkdir -p "$W/lib"; cp "$REPO/hooks/lib/"* "$W/lib/" 2>/dev/null

mkpatch() { # $1 out  $2 carve|nocarve
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
carve = '''current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}
sequencer_in_progress() {
  local marker
  for marker in rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD MERGE_HEAD; do
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
nocarve = '''current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}
on_main() {
  local b
  b="$(current_branch)"
  case "$b" in
    main|master) return 0 ;;
    "") return 0 ;;
    *) return 1 ;;
  esac
}'''
assert old in src, "anchor not found -- hook text drifted"
open(sys.argv[2], 'w').write(src.replace(old, carve if mode == "carve" else nocarve))
PY
}
mkpatch "$W/carve.sh" carve
mkpatch "$W/nocarve.sh" nocarve
[ -s "$W/carve.sh" ] && [ -s "$W/nocarve.sh" ] || { echo "HARNESS -- patch failed" >&2; exit 1; }

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }
hook() { ( cd "$2" && payload "$3" | bash "$1" >/dev/null 2>&1; echo $? ); }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

FAILED=0
ok()  { printf 'ok   — %s\n' "$1"; }
bad() { printf 'FAIL — %s\n' "$1" >&2; FAILED=1; }
assert_eq() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 (want [$2], got [$3])"; }

echo "########## FINDING 1: rebase started FROM main (the loose carve-out's hole) ##########"
D="$W/r1"; mkdir -p "$D"
( cd "$D"
  git init -q -b main .; mkdir -p src
  echo a > src/a.sh; git add -A; git commit -q -m c1
  echo b > src/b.sh; git add -A; git commit -q -m c2
  echo c > src/c.sh; git add -A; git commit -q -m c3
  GIT_SEQUENCE_EDITOR="sed -i '' '1s/^pick/edit/'" git rebase -i HEAD~2 >/dev/null 2>&1
) >/dev/null 2>&1
assert_eq "1: branchless"           ""              "$( cd "$D" && git symbolic-ref --short HEAD 2>/dev/null)"
assert_eq "1: rebase-merge present" yes "$( ( cd "$D" && [ -e "$(git rev-parse --git-path rebase-merge)" ] ) && echo yes || echo no)"
assert_eq "1: head-name"            refs/heads/main "$( cd "$D" && cat "$(git rev-parse --git-path rebase-merge)/head-name" 2>/dev/null)"

( cd "$D" && echo backdoor > src/backdoor.sh && git add -- src/backdoor.sh )
CMD='git commit -m msg -- src/backdoor.sh'
o=$(hook "$W/orig.sh" "$D" "$CMD"); c=$(hook "$W/carve.sh" "$D" "$CMD"); n=$(hook "$W/nocarve.sh" "$D" "$CMD")
printf '  hook exits -> orig=%s carve=%s nocarve=%s\n' "$o" "$c" "$n"
assert_eq "1: unmodified hook never saw this case"       0 "$o"
assert_eq "1: LOOSE carve-out lets it through (the hole)" 0 "$c"
assert_eq "1: no carve-out at all blocks it"              2 "$n"

( cd "$D" && git commit -q -m backdoor -- src/backdoor.sh && git rebase --continue >/dev/null 2>&1 )
assert_eq "1: HEAD is main after --continue" main "$( cd "$D" && git symbolic-ref --short HEAD 2>/dev/null || echo detached)"
on_main_count=$( cd "$D" && git ls-tree -r --name-only main | grep -c '^src/backdoor.sh$' )
assert_eq "1: backdoor.sh landed on main (demonstrates the hole)" 1 "$on_main_count"

echo
echo "########## FINDING 3: does 'git switch -c' escape a running rebase? ##########"
D2="$W/r3"; mkdir -p "$D2"
( cd "$D2"
  git init -q -b main .; mkdir -p src
  for i in 1 2 3; do echo $i > src/f$i.sh; git add -A; git commit -q -m c$i; done
  GIT_SEQUENCE_EDITOR="sed -i '' '1s/^pick/edit/'" git rebase -i HEAD~2 >/dev/null 2>&1
) >/dev/null 2>&1
switch_out=$( cd "$D2" && git switch -c tmp/x 2>&1 | head -1 )
printf '  git switch -c tmp/x  -> %s\n' "$switch_out"
case "$switch_out" in
  *"cannot switch branch while rebasing"*) ok "3: switch -c refused as documented" ;;
  *) bad "3: switch -c did not refuse (got: $switch_out)" ;;
esac
assert_eq "3: rebase still active after the refused switch" yes "$( ( cd "$D2" && [ -e "$(git rev-parse --git-path rebase-merge)" ] ) && echo yes || echo no)"
( cd "$D2" && git rebase --continue >/dev/null 2>&1 )
assert_eq "3: --continue still succeeds (rebase survives the attempt)" main "$( cd "$D2" && git symbolic-ref --short HEAD 2>/dev/null)"

echo
echo "########## FINDING 2: named main + MERGE_HEAD stays guarded regardless of the carve-out ##########"
D3="$W/r2"; mkdir -p "$D3"
( cd "$D3"
  git init -q -b main .; mkdir -p src
  echo base > src/app.sh; git add -A; git commit -q -m base
  git checkout -q -b other; echo other > src/app.sh; git add -A; git commit -q -m other
  git checkout -q main; echo mainline > src/app.sh; git add -A; git commit -q -m mainline
  git merge other >/dev/null 2>&1
) >/dev/null 2>&1
assert_eq "2: still on branch main" main "$( cd "$D3" && git symbolic-ref --short HEAD 2>/dev/null)"
assert_eq "2: MERGE_HEAD present"   yes  "$( ( cd "$D3" && [ -e "$(git rev-parse --git-path MERGE_HEAD)" ] ) && echo yes || echo no)"
( cd "$D3" && echo resolved > src/app.sh && git add -A )
carve_exit=$(hook "$W/carve.sh" "$D3" 'git commit -m msg')
printf '  hook exit (carve) for a source commit: %s\n' "$carve_exit"
assert_eq "2: named main stays guarded through the merge" 2 "$carve_exit"
switch2=$( cd "$D3" && git switch -c tmp/y 2>&1 | head -1 )
printf '  git switch -c tmp/y -> %s\n' "$switch2"
case "$switch2" in
  *"cannot switch branch while merging"*) ok "2: switch -c refused as documented" ;;
  *) bad "2: switch -c did not refuse (got: $switch2)" ;;
esac

[ "$FAILED" -eq 0 ] || { echo; echo "verify-carveout-hole.sh: one or more assertions FAILED" >&2; exit 1; }
echo
echo "all assertions passed."
