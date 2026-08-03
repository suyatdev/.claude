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

HOOK="$(cd "$(dirname "$0")" && pwd)/doc-guard.sh"
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
stage src/f1.sh src/f2.sh src/f3.sh CODING_MEMORY.md
run_case "docs ride along, CHAINED -> allow"                0 'git add -A && git commit -m msg'
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
printf '\ndoc-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
