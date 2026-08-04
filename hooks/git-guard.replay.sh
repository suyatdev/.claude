#!/usr/bin/env bash
# Replay: run main's git-guard and this branch's git-guard over the same command
# matrix in the same fixture states, and report every case where main BLOCKS and
# the branch ALLOWS. That set must be empty for "never weaker than main" to hold.
set -u
WT="$1"                      # worktree path (the branch under test)
UNDER_TEST="${2:-worktree}"  # "worktree" = the fix; or a git rev to extract instead
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- main's hook, with main's lib beside it (it resolves the classifier by $0) ---
BASE="$TMP/base"; mkdir -p "$BASE/lib"
git -C "$WT" show main:hooks/git-guard.sh              > "$BASE/git-guard.sh"
git -C "$WT" show main:hooks/lib/classify-git-command.py > "$BASE/lib/classify-git-command.py"
git -C "$WT" show main:hooks/lib/shell_segments.py     > "$BASE/lib/shell_segments.py"
if [ "$UNDER_TEST" = worktree ]; then
  NEW="$WT/hooks/git-guard.sh"
else
  CAND="$TMP/cand"; mkdir -p "$CAND/lib"
  git -C "$WT" show "$UNDER_TEST:hooks/git-guard.sh"              > "$CAND/git-guard.sh"
  git -C "$WT" show "$UNDER_TEST:hooks/lib/classify-git-command.py" > "$CAND/lib/classify-git-command.py"
  git -C "$WT" show "$UNDER_TEST:hooks/lib/shell_segments.py"     > "$CAND/lib/shell_segments.py"
  NEW="$CAND/git-guard.sh"
fi

# --- fixture repo, mirroring git-guard.test.sh ---
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@e.com; git -C "$REPO" config user.name t
printf 'seed\n' > "$REPO/CODING_MEMORY.md"
mkdir -p "$REPO/src" "$REPO/docs"
printf 'v1\n' > "$REPO/src/tracked.sh"; printf 'v1\n' > "$REPO/docs/tracked.md"
git -C "$REPO" add -A; git -C "$REPO" commit -qm seed

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }
run()     { ( cd "$REPO" && payload "$2" | bash "$1" >/dev/null 2>&1 ); echo $?; }

set_state() {
  git -C "$REPO" reset -q --hard; git -C "$REPO" clean -fdq
  case "$1" in
    empty-docs)   printf 'x\n' > "$REPO/docs/tracked.md" ;;
    empty-src)    printf 'x\n' > "$REPO/src/tracked.sh" ;;
    empty-both)   printf 'x\n' > "$REPO/docs/tracked.md"; printf 'x\n' > "$REPO/src/tracked.sh" ;;
    empty-clean)  : ;;
    staged-docs)  printf 'x\n' > "$REPO/docs/tracked.md"; git -C "$REPO" add -- docs/tracked.md ;;
    staged-src)   printf 'x\n' > "$REPO/src/tracked.sh"; git -C "$REPO" add -- src/tracked.sh ;;
  esac
}

CMDS=(
  'git commit -m msg'
  'git commit'
  'git commit -a -m msg'
  'git commit -am msg'
  'git commit --amend --no-edit'
  'git commit --amen --no-edit'
  'git commit --no-edit -m msg'
  'git commit --no-verify -m msg'
  'git commit -q --signoff -m msg'
  'git commit --pathspec-from-file=list'
  'git commit --some-future-option'
  'git commit -m msg docs/tracked.md'
  'git commit -m msg -- docs/tracked.md'
  'git commit -m msg -- src/tracked.sh'
  'git commit -m msg -- docs/tracked.md src/tracked.sh'
  'git commit -m msg -- CODING_MEMORY.md'
  'git commit -m msg -- coding-memory/x.jsonl'
  'git commit -m msg -- docs/tool.sh'
  'git commit -m msg -- docs/a/b/deep.md'
  'git commit -i -m msg -- docs/tracked.md'
  'git add -- src/tracked.sh && git commit -i -m msg -- docs/tracked.md'
  'git add -- src/tracked.sh && git commit -o -m msg -- docs/tracked.md'
  'git commit --include -m msg -- docs/tracked.md'
  'git commit -o -m msg -- docs/tracked.md'
  'git commit --only -m msg -- docs/tracked.md'
  'git commit -a -m msg -- docs/tracked.md'
  'git commit --amend -m msg -- docs/tracked.md'
  'git add -- docs/tracked.md && git commit -m msg'
  'git add -- src/tracked.sh && git commit -m msg'
  'git add -- docs/tracked.md && git commit -m msg -- docs/tracked.md'
  'git add -- src/tracked.sh && git commit -m msg -- docs/tracked.md'
  'git add -A && git commit -m msg'
  'git add . && git commit -m msg'
  'git add -u && git commit -m msg'
  'git rm src/tracked.sh && git commit -m msg'
  'git mv src/tracked.sh src/moved.sh && git commit -m msg'
  'git reset --soft HEAD~1 && git commit -m msg'
  'git checkout HEAD~1 -- src/tracked.sh && git commit -m msg'
  'git restore --source=HEAD~1 --staged -- src/tracked.sh && git commit -m msg'
  'git apply --cached patch.diff && git commit -m msg'
  'git stash pop --index && git commit -m msg'
  'git cherry-pick -n abc123 && git commit -m msg'
  'git revert -n abc123 && git commit -m msg'
  'git commit -m msg && git push'
  'git commit -m msg -- PUSH_FORCE && git push'
  'git commit -m msg -- COMMIT_ALL'
  'git push'
  'git push --force'
  'git push --force-with-lease'
  'ls -la'
  'git commit -m a -- docs/tracked.md && git add -- src/tracked.sh && git commit -m b'
  'git commit -m a && git commit -m b -- docs/tracked.md'
  'git commit -m a -- docs/tracked.md ; git commit -m b'
  'git commit -m a -- docs/tracked.md && git commit -a -m b'
  'git commit -m a -- docs/tracked.md && git commit -m b -- src/tracked.sh'
  'git commit -m a -- docs/tracked.md && git commit -m b -- docs/tracked.md'
  'git commit -m msg -- coding-memory/../src/tracked.sh'
  'git commit -m msg -- docs/../notes.md'
  'git commit -m msg -- ../docs/tracked.md'
  'git commit -m msg -- docs/v1..v2.md'
  'git -C sub commit -m msg'
  'git -C sub commit -m msg -- src/tracked.sh'
  'echo "remember to git commit later"'
)

# Every case where main BLOCKS and the candidate ALLOWS is a relaxation. Each one
# has to be inspected: a relaxation is intended ONLY where the commit names its own
# documentation paths. Printed once per distinct command, not once per state.
relaxed=0; stricter=0; same=0
: > "$TMP/relaxed"
for state in empty-clean empty-docs empty-src empty-both staged-docs staged-src; do
  for c in "${CMDS[@]}"; do
    set_state "$state"; a=$(run "$BASE/git-guard.sh" "$c")
    set_state "$state"; b=$(run "$NEW" "$c")
    if [ "$a" = 2 ] && [ "$b" = 0 ]; then
      relaxed=$((relaxed+1)); printf '%s\n' "$c" >> "$TMP/relaxed"
    elif [ "$a" = 0 ] && [ "$b" = 2 ]; then
      stricter=$((stricter+1)); printf 'stricter [%s] %s\n' "$state" "$c"
    else
      same=$((same+1))
    fi
  done
done
printf 'DISTINCT COMMANDS main BLOCKS and %s ALLOWS:\n' "$UNDER_TEST"
sort -u "$TMP/relaxed" | sed 's/^/  /'
printf '\n%s commands x 6 states = %s pairs: %s identical, %s stricter, %s relaxed (%s distinct commands)\n' \
  "${#CMDS[@]}" "$((relaxed+stricter+same))" "$same" "$stricter" "$relaxed" "$(sort -u "$TMP/relaxed" | grep -c . || true)"
