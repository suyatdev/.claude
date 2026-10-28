#!/usr/bin/env bash
# git-guard-quiet.test.sh -- hook-level tests for the `git-guard quiet` decision inside
# git-guard.sh. Covers docs/features/git-guard-quiet.md R1-R14, R15 (git-guard side), R18,
# R24, R25, R26 and R27, plus the relative -C folder rule measured in Task 0.
#
# Invoked from git-guard.test.sh (ADR 0044: that runner keeps the paired name, so the
# test-marker gate covers this suite). It writes no marker of its own: it has no paired subject.
#
# Every case drives the hook with PreToolUse JSON on stdin, from a real temp repository, with a
# fake $HOME holding the flag -- never the real ~/.claude/hooks/state. The commands are DATA;
# nothing here executes them. Each case asserts the DECISION (allow = exit 0 and nothing on
# stdout or stderr; ask = the ask JSON; deny = exit 2) together with the log, because a hook that
# allows without logging, or logs without allowing, is the defect this suite exists to catch.
#
# R1 is measured against origin/main's own git-guard, extracted with `git show`.
#
# QUIET_STUB_LIB=<file> swaps that file in for lib/git_guard_quiet.py, to falsify the suite
# against a stub child (always-allow, always-ask).
#
# Run: bash hooks/git-guard-quiet.test.sh
set -u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 1
TMP="$(mktemp -d)" || exit 1
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

SID='fb455a92-bc6d-49bf-93ff-b776fb118c9c'
SID_OTHER='0c9d3a11-2b7e-4f55-8a06-1d2e3f4a5b6c'
STATE_REL='.claude/hooks/state'
SLOW_LIMIT_SECONDS=14

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s\n%s\n' "$1" "$2"; fail=$((fail+1)); }
harness() { printf 'HARNESS — %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Hook trees. OURS is the real hooks dir (or a copy holding a stub child); ORIGIN is origin/main's.
# ---------------------------------------------------------------------------
copy_tree() { # $1 name -> prints the new hooks dir (git-guard.sh + lib/)
  local d="$TMP/trees/$1"
  mkdir -p "$d" && cp "$HERE/git-guard.sh" "$d/" && cp -R "$HERE/lib" "$d/lib" || harness "cannot copy the hook tree"
  printf '%s' "$d"
}
tree_with_child() { # $1 name, $2 python source for lib/git_guard_quiet.py -> hooks dir
  local d; d="$(copy_tree "$1")"
  printf '%s\n' "$2" > "$d/lib/git_guard_quiet.py"
  printf '%s' "$d"
}

OURS="$HERE"
if [ -n "${QUIET_STUB_LIB:-}" ]; then
  OURS="$(copy_tree stub)"; cp "$QUIET_STUB_LIB" "$OURS/lib/git_guard_quiet.py" || harness "cannot install the stub child"
fi
ORIGIN="$TMP/origin-main"
mkdir -p "$ORIGIN/lib"
for f in git-guard.sh lib/classify-git-command.py lib/shell_segments.py; do
  git -C "$ROOT" show "origin/main:hooks/$f" > "$ORIGIN/$f" 2>/dev/null || harness "origin/main:hooks/$f is not available (git fetch origin?)"
done

# ---------------------------------------------------------------------------
# Fixtures: S session cwd on main; M repo on main; F worktree on feat/x; U worktree on feat/u whose
# upstream is origin/main with push.default=upstream; T repo on main with a TAG named main.
# ---------------------------------------------------------------------------
mkrepo() { local d="$TMP/$1"; git init -q -b "$2" "$d" && git -C "$d" commit -q --allow-empty -m seed && printf '%s' "$d"; }
S="$(mkrepo S main)"; M="$(mkrepo M main)"; T="$(mkrepo T main)"
git -C "$T" tag main
git init -q --bare "$TMP/origin.git" && git -C "$M" remote add origin "$TMP/origin.git" && git -C "$M" push -q origin main 2>/dev/null
F="$TMP/F"; U="$TMP/U"
git -C "$M" worktree add -q -b feat/x "$F" || harness "worktree F"
git -C "$M" worktree add -q -b feat/u "$U" || harness "worktree U"
git -C "$U" branch -q --set-upstream-to=origin/main && git -C "$M" config push.default upstream || harness "upstream for U"
DET="$TMP/DET"; git -C "$M" worktree add -q --detach "$DET" || harness "worktree DET"
REB="$TMP/REB"; git -C "$M" worktree add -q -b feat/reb "$REB" || harness "worktree REB"
MRG="$TMP/MRG"; git -C "$M" worktree add -q -b feat/mrg "$MRG" || harness "worktree MRG"
mkdir -p "$(git -C "$REB" rev-parse --absolute-git-dir)/rebase-merge"
: > "$(git -C "$MRG" rev-parse --absolute-git-dir)/MERGE_HEAD"
NOTREPO="$TMP/plain"; mkdir -p "$NOTREPO"
REL="$TMP/rel"; mkdir -p "$REL"; ln -s "$F" "$REL/feat-rel"
case_worktree() { # $1 name $2 ref -> a worktree whose HEAD names that (unborn) branch
  local d="$TMP/$1"; git -C "$M" worktree add -q --detach "$d" && git -C "$d" symbolic-ref HEAD "$2" && printf '%s' "$d"
}
CASE_Main="$(case_worktree caseMain refs/heads/Main)"
CASE_MASTER="$(case_worktree caseMASTER refs/heads/MASTER)"
CASE_LONGS="$(case_worktree caseLongS "refs/heads/ma"$'\xc5\xbf'"ter")"
[ "$(git -C "$T" symbolic-ref --short HEAD)" = "heads/main" ] || harness "T: --short must print heads/main (tag fixture)"

H="$TMP/home"
mkhome() { mkdir -p "$1/$STATE_REL/git-guard-quiet"; }
mkhome "$H"; : > "$H/$STATE_REL/git-guard-quiet/$SID"
H0="$TMP/home-noflag"; mkhome "$H0"
log_count() { local f="$1/$STATE_REL/git-guard-quiet.log"; if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else printf 0; fi; }
last_log_field() { tail -n 1 "$1/$STATE_REL/git-guard-quiet.log" 2>/dev/null | cut -f"$2"; }

# ---------------------------------------------------------------------------
# Running the hook
# ---------------------------------------------------------------------------
RUN_PATH=""; UNSET_HOME=""
# run_hook <hooks_dir> <home> <session_id|-> <cwd> <command> -> RC, OUT_BYTES, ERR, DEC
run_hook() {
  local dir="$1" home="$2" sid="$3" cwd="$4" cmd="$5" payload
  payload="$(python3 -c '
import json, sys
d = {"hook_event_name": "PreToolUse", "cwd": sys.argv[3], "tool_input": {"command": sys.argv[4]}}
if sys.argv[2] != "-":
    d["session_id"] = sys.argv[2]
sys.stdout.write(json.dumps(d))' x "$sid" "$cwd" "$cmd")"
  if [ -n "$UNSET_HOME" ]; then
    ( cd "$cwd" && printf '%s' "$payload" | env -u HOME PATH="${RUN_PATH:-$PATH}" bash "$dir/git-guard.sh" ) >"$TMP/out" 2>"$TMP/err"
  else
    ( cd "$cwd" && printf '%s' "$payload" | env HOME="$home" PATH="${RUN_PATH:-$PATH}" bash "$dir/git-guard.sh" ) >"$TMP/out" 2>"$TMP/err"
  fi
  RC=$?
  OUT_BYTES="$(wc -c < "$TMP/out" | tr -d ' ')"
  ERR="$(cat "$TMP/err")"
  if [ "$RC" -eq 2 ]; then DEC=deny
  elif [ "$RC" -ne 0 ]; then DEC="rc$RC"
  elif [ "$OUT_BYTES" -eq 0 ]; then DEC=allow
  elif grep -q '"permissionDecision":"ask"' "$TMP/out"; then DEC=ask
  else DEC=odd; fi
}

# expect <desc> <allow|ask|deny> <command> [cwd] [hooks_dir] [home] [sid]
# Asserts the decision, that an allow is silent on BOTH streams, and the log rule (allow +1, else +0).
expect() {
  local desc="$1" want="$2" cmd="$3" cwd="${4:-$S}" dir="${5:-$OURS}" home="${6:-$H}" sid="${7-$SID}" before after wantlog=0 started=$SECONDS
  [ "$want" = allow ] && wantlog=1
  before="$(log_count "$home")"
  run_hook "$dir" "$home" "$sid" "$cwd" "$cmd"
  after="$(log_count "$home")"
  if [ "$DEC" = "$want" ] && [ $((after-before)) -eq $wantlog ] && { [ "$want" != allow ] || [ -z "$ERR" ]; }; then
    ok "$desc -> $want"
  else
    bad "$desc -> want $want" "  got $DEC rc=$RC stdout-bytes=$OUT_BYTES log+=$((after-before)) stderr=$(printf '%s' "$ERR" | head -c 200)"
  fi
  LAST_SECONDS=$((SECONDS-started))
}
expect_logged() { # <desc> <read|lands> <command>
  expect "$1" allow "$3"; [ "$(last_log_field "$H" 3)" = "$2" ] && ok "$1: log kind $2" || bad "$1: log kind $2" "  got $(last_log_field "$H" 3)"
}

# R1: with quiet off (no flag, or another session's flag) ours is byte-for-byte origin/main's.
same_as_origin() { # <desc> <command> <cwd> <want-today: ask|deny|allow> <home> <sid>
  local rc out err dec
  run_hook "$ORIGIN" "$5" "$6" "$3" "$2"; rc=$RC; err=$ERR; out="$(cat "$TMP/out")"; dec=$DEC
  run_hook "$OURS" "$5" "$6" "$3" "$2"
  if [ "$RC" = "$rc" ] && [ "$ERR" = "$err" ] && [ "$(cat "$TMP/out")" = "$out" ] && [ "$dec" = "$4" ]; then
    ok "R1 $1 (quiet off, today = $4)"
  else
    bad "R1 $1 (quiet off)" "  origin: dec=$dec rc=$rc  ours: dec=$DEC rc=$RC (wanted today=$4)"
  fi
}

# ---------------------------------------------------------------------------
# The case table: want-with-quiet-on | description | command (@F@ etc. are fixture paths)
# ---------------------------------------------------------------------------
CASES=(
  'allow|R2 W + status + hash-object + wc|W=@F@; git -C "$W" status --short; git -C "$W" hash-object @F@/f.txt; wc -l @F@/f.txt'
  'allow|R2 cat-file|git -C @F@ cat-file -t HEAD'
  'allow|R3 add, commit, push|git -C @F@ add -- f && git -C @F@ commit -m x -- f && git -C @F@ push -u origin HEAD'
  'allow|R4 wrapper|time git -C @F@ commit -m x'
  'ask|R5 commit on main|git -C @M@ commit -m x'
  'ask|R5 push on main|git -C @M@ push origin HEAD'
  'ask|R6 switch main then commit|git -C @F@ switch main && git -C @F@ commit -m x'
  'ask|R6 merge|git -C @M@ merge feat/x'
  'ask|R6 symbolic-ref|git -C @F@ symbolic-ref HEAD refs/heads/main'
  'ask|R6 config hooksPath|git -C @F@ config core.hooksPath /dev/null'
  'ask|R7 HEAD:refs/heads/main|git -C @F@ push origin HEAD:refs/heads/main'
  'ask|R7 HEAD:main|git -C @F@ push origin HEAD:main'
  'ask|R7 --all|git -C @F@ push --all'
  'ask|R7 --mirror|git -C @F@ push --mirror'
  'ask|R7 branch name|git -C @F@ push origin feat/x'
  'ask|R8 bare push, upstream=origin/main|git -C @U@ push'
  'ask|R8 bare push|git -C @F@ push'
  'ask|R9 --force|git -C @F@ push --force'
  'ask|R9 -uf|git -C @F@ push -uf origin HEAD'
  'ask|R9 --force-with-lease=|git -C @F@ push --force-with-lease=feat/x'
  'ask|R27 push -o HEAD is a bare push|git -C @U@ push -o HEAD'
  'ask|R27 push --push-option HEAD is a bare push|git -C @U@ push --push-option HEAD'
  'ask|R10 export GIT_DIR|export GIT_DIR=@M@/.git; git -C @F@ commit -m x'
  'ask|R10 pushd|pushd @M@ && git -C . commit -m x'
  'ask|R10 cd|cd @M@ && git -C . commit -m x'
  'ask|R10 variable folder|git -C "$W" commit -m x'
  'ask|R10 GIT_DIR assignment|GIT_DIR=@M@/.git git -C @F@ status'
  'ask|R11 detached folder|git -C @DET@ commit -m x'
  'ask|R11 mid-rebase folder|git -C @REB@ commit -m x'
  'ask|R11 mid-merge folder|git -C @MRG@ commit -m x'
  'ask|R11 not a repository|git -C @NOTREPO@ commit -m x'
  'ask|R12 -c after -C|git -C @F@ -c core.hooksPath=/dev/null status'
  'ask|R12 -c before -C|git -c core.hooksPath=/dev/null -C @F@ status'
  'ask|R12 -c on a second segment|git -C @F@ status && git -c core.hooksPath=/dev/null status'
  'ask|R12 alias|git -C @F@ st'
  'ask|R12 --output|git -C @F@ diff --output=/tmp/x'
  'ask|R20 $( )|git -C @F@ status -- "$(git -C @F@ switch main; git -C @F@ commit -m x)"'
  'ask|R20 backtick|git -C @F@ commit -m "x`git -C @F@ switch main`"'
  'ask|R20 <( )|git -C @F@ log <(git -C @M@ merge x)'
  'ask|R21 redirect on a commit line|git -C @F@ status > @F@/.git/HEAD && git -C @F@ commit -m x'
  'ask|R22 branch --no-list -D|git -C @F@ branch --list --no-list -D main'
  'ask|R22 branch -l -M|git -C @F@ branch -l -M main old'
  'ask|R22 hash-object -wt|git -C @F@ hash-object -wt blob f'
  'ask|R22 worktree list --porcelain x|git -C @F@ worktree list --porcelain x'
  'ask|R23 tag named main|git -C @T@ commit -m x'
  'ask|R25 branch Main|git -C @CASE_Main@ commit -m x'
  'ask|R25 branch MASTER|git -C @CASE_MASTER@ commit -m x'
  'ask|R25 branch with U+017F|git -C @CASE_LONGS@ commit -m x'
  'ask|R26 eval status|eval git -C @F@ status'
  'ask|R26 eval commit|eval git -C @F@ commit -m x'
  'deny|R13 plain commit on main (Guard 1 first)|git -C @F@ status && git commit -m y'
)
subst() { local s="$1"; s="${s//@F@/$F}"; s="${s//@M@/$M}"; s="${s//@U@/$U}"; s="${s//@T@/$T}"; s="${s//@DET@/$DET}"; s="${s//@REB@/$REB}"
  s="${s//@MRG@/$MRG}"; s="${s//@NOTREPO@/$NOTREPO}"; s="${s//@CASE_Main@/$CASE_Main}"; s="${s//@CASE_MASTER@/$CASE_MASTER}"; s="${s//@CASE_LONGS@/$CASE_LONGS}"; printf '%s' "$s"; }

for row in "${CASES[@]}"; do
  IFS='|' read -r want desc cmd <<< "$row"
  cmd="$(subst "$cmd")"
  today="$want"; [ "$want" = allow ] && today=ask
  same_as_origin "$desc" "$cmd" "$S" "$today" "$H0" "$SID"
  same_as_origin "$desc [R14: another session's flag]" "$cmd" "$S" "$today" "$H" "$SID_OTHER"
  case "$desc" in
    R2\ *) expect_logged "$desc" read "$cmd" ;;
    R3\ *|R4\ *) expect_logged "$desc" lands "$cmd" ;;
    *) expect "$desc" "$want" "$cmd" ;;
  esac
done

# R14 (session scoping) and the Task 0 rule: a RELATIVE -C folder on a commit/push asks even when it
# is a valid feature worktree; the same folder written absolutely passes; a relative READ passes.
expect "R14 other session, R2 line" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H" "$SID_OTHER"
expect "Task 0 relative folder, commit" ask "git -C feat-rel commit -m x" "$REL"
expect "Task 0 relative folder, push" ask "git -C feat-rel push origin HEAD" "$REL"
expect "Task 0 relative folder, read-only (D3: any folder)" allow "git -C feat-rel status" "$REL"
expect "Task 0 control: absolute folder, commit" allow "git -C $F commit -m x" "$REL"
# R27: a commit message whose later line looks like a fact is data.
FORGED="$(printf 'git -C %s commit -m "x\nSEG_QUIET\t0\tread"' "$F")"
expect "R27 forged fact in a message, feature folder" allow "$FORGED"
expect "R27 forged fact in a message, main folder" ask "$(printf 'git -C %s commit -m "x\nSEG_QUIET\t0\tread"' "$M")"

# Scenario "on restores the prompt": deleting the flag brings the ask back.
rm -f "$H/$STATE_REL/git-guard-quiet/$SID"
expect "flag removed: R2 line asks again" ask "git -C $F cat-file -t HEAD"
: > "$H/$STATE_REL/git-guard-quiet/$SID"
expect "flag restored: R2 line passes" allow "git -C $F cat-file -t HEAD"

# R15 (git-guard side): the session_id is validated BEFORE it becomes a path. Each case plants a flag
# at the literal location a naive join would reach; none may be honoured.
S_DIR="$H/$STATE_REL/git-guard-quiet"
: > "$H/$STATE_REL/x"; expect "R15 session_id ../x" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H" "../x"
LONG="$(printf 'a%.0s' $(seq 1 129))"; : > "$S_DIR/$LONG"; expect "R15 129-char session_id" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H" "$LONG"
LONG128="${LONG%a}"; : > "$S_DIR/$LONG128"; expect "R15 control: 128-char session_id" allow "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H" "$LONG128"
: > "$S_DIR/a b"; expect "R15 session_id with a space" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H" "a b"
: > "$S_DIR/$(printf 'a\nb')"; expect "R15 session_id with a newline" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H" "$(printf 'a\nb')"
expect "R15 session_id missing from the payload" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H" "-"
expect "R15 session_id empty" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H" ""

# R18: any error reading the flag, running a D7 git call or writing the log -> ask.
UNSET_HOME=1 expect "R18 HOME unset" ask "git -C $F cat-file -t HEAD"
H2="$TMP/home-flagdir"; mkhome "$H2"; mkdir "$H2/$STATE_REL/git-guard-quiet/$SID"
expect "R18 flag path is a directory" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H2"
H3="$TMP/home-state-locked"; mkhome "$H3"; : > "$H3/$STATE_REL/git-guard-quiet/$SID"; chmod 000 "$H3/$STATE_REL/git-guard-quiet"
expect "R18 state dir unreadable" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H3"; chmod 700 "$H3/$STATE_REL/git-guard-quiet"
H4="$TMP/home-logdir"; mkhome "$H4"; : > "$H4/$STATE_REL/git-guard-quiet/$SID"; mkdir "$H4/$STATE_REL/git-guard-quiet.log"
expect "R18 log cannot be appended (path is a directory)" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H4"
H5="$TMP/home-statero"; mkhome "$H5"; : > "$H5/$STATE_REL/git-guard-quiet/$SID"; chmod 500 "$H5/$STATE_REL"
expect "R18 log cannot be created (state dir read-only)" ask "git -C $F cat-file -t HEAD" "$S" "$OURS" "$H5"; chmod 700 "$H5/$STATE_REL"

# R24: the child absent, unreadable, failing, raising, lying, or slow -> ask, and git-guard writes no log.
R3LINE="git -C $F add -- f && git -C $F commit -m x -- f && git -C $F push -u origin HEAD"
R2LINE="W=$F; git -C \"\$W\" status --short; wc -l f"
t="$(copy_tree absent)"; rm "$t/lib/git_guard_quiet.py"
expect "R24 child absent: R2" ask "$R2LINE" "$S" "$t"; expect "R24 child absent: R3" ask "$R3LINE" "$S" "$t"
t="$(copy_tree unreadable)"; chmod 000 "$t/lib/git_guard_quiet.py"
expect "R24 child unreadable: R2" ask "$R2LINE" "$S" "$t"; expect "R24 child unreadable: R3" ask "$R3LINE" "$S" "$t"
STUBS=(
  "exits non-zero after printing allow|import sys; sys.stdout.write('allow'); sys.exit(3)"
  "raises|raise RuntimeError('boom')"
  "syntax error|def ("
  "prints allow plus a word|import sys; sys.stdout.write('allow now')"
  "prints ALLOW|import sys; sys.stdout.write('ALLOW')"
  "prints two lines|import sys; sys.stdout.write('allow\\nask')"
  "prints nothing|pass"
  "prints ask|import sys; sys.stdout.write('ask')"
)
for row in "${STUBS[@]}"; do
  IFS='|' read -r name src <<< "$row"
  t="$(tree_with_child "stub-${name// /-}" "$src")"
  expect "R24 child $name: R2" ask "$R2LINE" "$S" "$t"; expect "R24 child $name: R3" ask "$R3LINE" "$S" "$t"
done
t="$(tree_with_child stub-ok "import sys; sys.stdout.write('allow')")"
run_hook "$t" "$H" "$SID" "$S" "$R2LINE"
[ "$DEC" = allow ] && ok "R24 control: a child printing exactly allow is honoured" || bad "R24 control: a child printing exactly allow is honoured" "  got $DEC"
# The child is never started without a flag (D1), and is started with one.
SENT="$TMP/sentinel"
t="$(tree_with_child stub-sentinel "open('$SENT','w').close()")"
run_hook "$t" "$H0" "$SID" "$S" "$R2LINE"; [ ! -e "$SENT" ] && ok "D1 no flag: the child is never started" || bad "D1 no flag: the child is never started" "  sentinel exists"
run_hook "$t" "$H" "$SID" "$S" "$R2LINE"; [ -e "$SENT" ] && ok "control: with a flag the child IS started" || bad "control: with a flag the child IS started" "  sentinel missing"
rm -f "$SENT"
run_hook "$t" "$H" "$SID" "$S" "git status"; [ ! -e "$SENT" ] && ok "a line without SCOPE_UNKNOWN never reaches the child" || bad "a line without SCOPE_UNKNOWN never reaches the child" "  sentinel exists"

# R24 timeouts: a D7 git call that stalls ends in a prompt, well inside the hook timeout.
mkstub() { mkdir -p "$TMP/stubbin/$1"; printf '#!/bin/sh\n%s\n' "$2" > "$TMP/stubbin/$1/git"; chmod 755 "$TMP/stubbin/$1/git"; printf '%s' "$TMP/stubbin/$1:$PATH"; }
REALGIT="$(command -v git)"
RUN_PATH="$(mkstub delegate "exec $REALGIT \"\$@\"")"
expect "R24 control: a git stub that delegates still allows R3" allow "$R3LINE"
RUN_PATH="$(mkstub sleepall "exec sleep 30")"
expect "R24 git stalls on every call: R3" ask "$R3LINE"; [ "$LAST_SECONDS" -lt "$SLOW_LIMIT_SECONDS" ] && ok "R24 stall answered in ${LAST_SECONDS}s" || bad "R24 stall answered in time" "  took ${LAST_SECONDS}s"
RUN_PATH="$(mkstub sleeprev "case \"\$*\" in *symbolic-ref*) exec $REALGIT \"\$@\" ;; *) exec sleep 30 ;; esac")"
expect "R24 git stalls on the second call (rev-parse): R3" ask "$R3LINE"; [ "$LAST_SECONDS" -lt "$SLOW_LIMIT_SECONDS" ] && ok "R24 second-call stall answered in ${LAST_SECONDS}s" || bad "R24 second-call stall answered in time" "  took ${LAST_SECONDS}s"
RUN_PATH="$(mkstub failall "exit 1")"
expect "R18 a D7 git call that fails: R3" ask "$R3LINE"
expect "a read line never calls git, so a broken git still passes" allow "git -C $F cat-file -t HEAD"
RUN_PATH=""

printf '\ngit-guard-quiet: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
