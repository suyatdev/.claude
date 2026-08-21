#!/usr/bin/env bash
# Replay: run a baseline git-guard (third positional, default `main`) and this
# branch's git-guard over the same command matrix in the same fixture states, and
# report every case where the base BLOCKS and the branch ALLOWS. Against the
# default base, that set must be empty for "never weaker than main" to hold.
set -u
WT_INPUT="$1"                 # worktree path (the branch under test), as typed
UNDER_TEST="${2:-worktree}"  # "worktree" = the fix; or a git rev to extract instead
BASE_REV="${3:-main}"        # baseline to compare against; default keeps the stated contract
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

INVOCATION="bash hooks/git-guard.replay.sh <worktree> [worktree|<rev>] [<base-rev>]"

# Every named error and every refusal: one plain sentence, no matrix, non-zero exit.
fail() {
  printf 'REPLAY ERROR: %s\n' "$1" >&2
  printf 'Corrected invocation: %s\n' "$INVOCATION" >&2
  exit 1
}

# Resolve to an absolute, real path before anything else uses it — a relative
# path like "." would otherwise be read against whatever directory a later
# `cd` or subshell happens to be in, and route 3 (the candidate exiting 127,
# silently tallied "same") never surfaces.
WT="$(cd "$WT_INPUT" 2>/dev/null && pwd -P)"
if [ -z "$WT" ] || [ ! -f "$WT/hooks/git-guard.sh" ]; then
  fail "the worktree '$WT_INPUT' (as typed) does not resolve to a directory containing hooks/git-guard.sh."
fi

# Resolve before extracting anything, so every later error can name a real SHA. An
# unresolvable rev is the ONE case with no SHA to name, so it names the string as typed.
resolve_rev() {  # $1 = rev as typed, $2 = side label
  local sha
  sha="$(git -C "$WT" rev-parse --verify --quiet "${1}^{commit}" 2>/dev/null)"
  if [ -z "$sha" ]; then
    fail "the $2 rev '$1' (as typed) is unresolved — rev-parse produced no commit for it, so no SHA can be named."
  fi
  printf '%s\n' "$sha"
}

# $1 = resolved sha, $2 = side label, $3 = path in repo, $4 = destination
extract_required() {
  if ! git -C "$WT" show "${1}:${3}" > "$4" 2>/dev/null; then
    fail "the $2 at $1 does not contain $3, so its guard cannot run; no matrix was produced."
  fi
  if [ ! -s "$4" ]; then
    fail "the $2 at $1 has an empty $3 — an empty file cannot execute as intended and would manufacture a false result."
  fi
}

# Same present-and-non-empty rule as extract_required, for a side whose bytes already
# live on disk: nothing is extracted, nothing is written. $1 = side identity (here, the
# resolved absolute worktree path), $2 = side label, $3 = path in repo, $4 = disk path.
require_on_disk() {
  if [ ! -f "$4" ]; then
    fail "the $2 at $1 does not contain $3, so its guard cannot run; no matrix was produced."
  fi
  if [ ! -s "$4" ]; then
    fail "the $2 at $1 has an empty $3 — an empty file cannot execute as intended and would manufacture a false result."
  fi
}

# The two lib/*.py helpers are required ONLY when that side's git-guard.sh actually
# references lib/, read from the bytes that will execute. A guard that predates the
# helper split is self-contained: recorded, not rejected.
extract_helpers_if_referenced() {  # $1 = resolved sha, $2 = side label, $3 = side dir
  if grep -q 'lib/' "$3/git-guard.sh"; then
    extract_required "$1" "$2" hooks/lib/classify-git-command.py "$3/lib/classify-git-command.py"
    extract_required "$1" "$2" hooks/lib/shell_segments.py       "$3/lib/shell_segments.py"
  else
    printf 'NOTE: the %s at %s is a self-contained guard (git-guard.sh references no lib/); its hooks/lib/*.py are not part of this comparison.\n' "$2" "$1"
  fi
}

# --- the base hook, with its own lib beside it (it resolves the classifier by $0) ---
BASE_SHA="$(resolve_rev "$BASE_REV" base)" || exit 1
BASE="$TMP/base"; mkdir -p "$BASE/lib"
extract_required "$BASE_SHA" base hooks/git-guard.sh "$BASE/git-guard.sh"
extract_helpers_if_referenced "$BASE_SHA" base "$BASE"

BASE_LIB="$BASE/lib"
if [ "$UNDER_TEST" = worktree ]; then
  # Read from disk, not `git show HEAD:` — the on-disk bytes are the ones that execute.
  NEW="$WT/hooks/git-guard.sh"
  CAND_LIB="$WT/hooks/lib"
  # Validated here, same as any other side (part 2, revision 10): present and non-empty,
  # plus the two lib/*.py helpers if this guard references lib/. Read-only — no
  # extraction, no rm -f — because $WT is the user's real repository, not a temp dir.
  require_on_disk "$WT" candidate hooks/git-guard.sh "$NEW"
  if grep -q 'lib/' "$NEW"; then
    require_on_disk "$WT" candidate hooks/lib/classify-git-command.py "$CAND_LIB/classify-git-command.py"
    require_on_disk "$WT" candidate hooks/lib/shell_segments.py       "$CAND_LIB/shell_segments.py"
  fi
else
  CAND_SHA="$(resolve_rev "$UNDER_TEST" candidate)" || exit 1
  CAND="$TMP/cand"; mkdir -p "$CAND/lib"
  extract_required "$CAND_SHA" candidate hooks/git-guard.sh "$CAND/git-guard.sh"
  extract_helpers_if_referenced "$CAND_SHA" candidate "$CAND"
  NEW="$CAND/git-guard.sh"
  CAND_LIB="$CAND/lib"
fi

# --- refuse a vacuous run: a program compared with itself proves nothing ---
# A side's set is part 2's required set and nothing else. Membership is decided by the
# bytes that will actually execute, NOT by what sits on disk: an unreferenced helper
# cannot run, so it cannot make a run differential. Sets are compared first, so `cmp`
# never receives a path that is not a member of both sides.
side_members() {  # $1 = the guard bytes that will execute
  printf 'git-guard.sh\n'
  if grep -q 'lib/' "$1" 2>/dev/null; then
    printf 'lib/classify-git-command.py\n'
    printf 'lib/shell_segments.py\n'
  fi
}

member_path() {  # $1 = base|cand, $2 = logical member
  case "$2" in
    git-guard.sh)
      if [ "$1" = base ]; then printf '%s\n' "$BASE/git-guard.sh"; else printf '%s\n' "$NEW"; fi ;;
    lib/*)
      if [ "$1" = base ]; then printf '%s/%s\n' "$BASE_LIB" "${2#lib/}"
      else printf '%s/%s\n' "$CAND_LIB" "${2#lib/}"; fi ;;
  esac
}

BASE_MEMBERS="$(side_members "$BASE/git-guard.sh")"
CAND_MEMBERS="$(side_members "$NEW")"

if [ "$BASE_MEMBERS" = "$CAND_MEMBERS" ]; then
  VACUOUS=1
  while IFS= read -r member; do
    [ -n "$member" ] || continue
    cmp -s "$(member_path base "$member")" "$(member_path cand "$member")" || VACUOUS=0
  done <<MEMBERS
$BASE_MEMBERS
MEMBERS
  if [ "$VACUOUS" = 1 ]; then
    printf 'REPLAY REFUSED: base %s and the candidate are the same program — same file set, identical bytes — so this run would prove nothing.\n' "$BASE_SHA" >&2
    printf 'Corrected invocation: %s — pass a base that predates the change under test.\n' "$INVOCATION" >&2
    exit 1
  fi
fi

# --- fixture repo, mirroring git-guard.test.sh ---
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@e.com; git -C "$REPO" config user.name t
# CODING_MEMORY.md stays a FIXTURE file (the matrix still names it) but is no
# longer a PERMITTED path on main -- docs/features/rule-surface-trim.md.
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
  # These two are EXPECTED to report stricter against any base predating
  # docs/features/rule-surface-trim.md, which removed CODING_MEMORY.md and
  # coding-memory/* from the main-branch allowlist. See EXPECTED_STRICTER below.
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
  # Blocked on BOTH sides, so it does NOT diverge -- but the REASON changed with
  # docs/features/rule-surface-trim.md: it used to be the `..` arm rescuing a
  # string that satisfied `coding-memory/*`, and is now simply a prefix that is
  # not allowlisted at all. `docs/../notes.md` below is what exercises the `..`
  # arm now.
  'git commit -m msg -- coding-memory/../src/tracked.sh'
  'git commit -m msg -- docs/../notes.md'
  'git commit -m msg -- ../docs/tracked.md'
  'git commit -m msg -- docs/v1..v2.md'
  'git -C sub commit -m msg'
  'git -C sub commit -m msg -- src/tracked.sh'
  'echo "remember to git commit later"'
)

# Commands this branch deliberately began BLOCKING that the base allowed. Without
# this list an intended narrowing is indistinguishable from a regression: both
# just print `stricter`. Each entry needs a reason in the matrix above.
#   docs/features/rule-surface-trim.md -- retired CODING_MEMORY.md and
#   coding-memory/* from the main-branch documentation allowlist.
EXPECTED_STRICTER=(
  'git commit -m msg -- CODING_MEMORY.md'
  'git commit -m msg -- coding-memory/x.jsonl'
)

is_expected_stricter() {
  local e
  for e in "${EXPECTED_STRICTER[@]}"; do
    [ "$1" = "$e" ] && return 0
  done
  return 1
}

# Every case where main BLOCKS and the candidate ALLOWS is a relaxation. Each one
# has to be inspected: a relaxation is intended ONLY where the commit names its own
# documentation paths. Printed once per distinct command, not once per state.
relaxed=0; stricter=0; same=0; unexpected=0
: > "$TMP/relaxed"
for state in empty-clean empty-docs empty-src empty-both staged-docs staged-src; do
  for c in "${CMDS[@]}"; do
    set_state "$state"; a=$(run "$BASE/git-guard.sh" "$c")
    set_state "$state"; b=$(run "$NEW" "$c")
    if [ "$a" = 2 ] && [ "$b" = 0 ]; then
      relaxed=$((relaxed+1)); printf '%s\n' "$c" >> "$TMP/relaxed"
    elif [ "$a" = 0 ] && [ "$b" = 2 ]; then
      stricter=$((stricter+1))
      if is_expected_stricter "$c"; then
        printf 'stricter (EXPECTED, rule-surface-trim) [%s] %s\n' "$state" "$c"
      else
        unexpected=$((unexpected+1))
        printf 'stricter (UNEXPECTED -- inspect this) [%s] %s\n' "$state" "$c"
      fi
    else
      same=$((same+1))
    fi
  done
done
printf 'DISTINCT COMMANDS base=%s (%s) BLOCKS and %s ALLOWS:\n' "$BASE_SHA" "$BASE_REV" "$UNDER_TEST"
sort -u "$TMP/relaxed" | sed 's/^/  /'
printf '\nbase=%s (%s) — %s commands x 6 states = %s pairs: %s identical, %s stricter (%s unexpected), %s relaxed (%s distinct commands)\n' \
  "$BASE_SHA" "$BASE_REV" "${#CMDS[@]}" "$((relaxed+stricter+same))" "$same" "$stricter" "$unexpected" "$relaxed" "$(sort -u "$TMP/relaxed" | grep -c . || true)"

# Gate, don't just report (observability judge, 2026-08-20, ADR 0031). Until now
# this harness printed `N unexpected` and still exited 0, so a caller running it
# in a chain -- or a human skimming the last line -- could not tell a clean run
# from a divergent one. `relaxed` breaks the stated "never weaker than main"
# contract; `unexpected` means a stricter divergence nobody declared in
# EXPECTED_STRICTER, which is indistinguishable from a regression.
if [ "$relaxed" -gt 0 ] || [ "$unexpected" -gt 0 ]; then
  printf 'REPLAY FAILED: %s relaxed, %s unexpected stricter — inspect before trusting this run.\n' \
    "$relaxed" "$unexpected" >&2
  exit 1
fi
exit 0
