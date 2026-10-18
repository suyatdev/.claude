#!/usr/bin/env bash
# hook-exec-pr-guard.test.sh -- suite for hooks/hook-exec-pr-guard.sh, the PreToolUse Bash hook that
# refuses `gh pr create` while a hook script registered in settings.json is stored in the branch's
# HEAD commit as anything but mode 100755. Spec: docs/features/hook-exec-bit-pr-guard.md (R1-R9 and
# its Gherkin block; comments below cite them as "R3", "Scenario: ...").
# Run BY HAND: bash hooks/hook-exec-pr-guard.test.sh
#
# Every case builds its own fixture: a fake $HOME from mktemp -d holding .claude as a git repo whose
# settings.json registers $HOME/.claude/hooks/a.sh on PreToolUse, plus a worktree of it where the
# scenario needs one, and the hook runs with that directory as its working directory and HOME
# pointing at the fake. GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1 and GIT_CEILING_DIRECTORIES
# keep every git call away from the real ~/.claude and its global core.hooksPath -- without the
# ceiling a scratch directory under $HOME can resolve to the real repo and the out-of-scope cases
# pass for the wrong reason.
#
# Broken-machinery cases (empty classifier, empty or lying checker, no python3) cannot mutate the
# real hooks/lib, so the guard loads its helpers from ITS OWN directory (R3) and the suite runs a
# COPY of the guard beside a COPY of hooks/lib, breaks the copy, and runs that. A control case runs
# an unbroken copy so a copy that cannot work is told apart from a break that does.
#
# A deny is never judged by its exit code alone. Exit 2 is also what a machinery failure returns,
# so every "blocks" case also requires text that only the intended refusal can carry (the script's
# path, a cause name), and every refusal line must start "hook-exec-pr-guard:".
#
# Bash 3.2 only: no associative arrays, mapfile or ${var,,}.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd -P)"
GUARD="$HERE/hook-exec-pr-guard.sh"
PREFIX='hook-exec-pr-guard:'

TMP="$(mktemp -d)" || { printf 'FAIL — mktemp -d failed; cannot build fixtures\n' >&2; exit 1; }
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$TMP"

pass=0; fail=0
n_fix=0; n_copy=0
H=""; MAIN=""; WT=""; CD=""
RC=0; OUT=""; ERR=""
G_GUARD=""; G_HOME=""; G_PATH=""

say_ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
say_bad() { printf 'FAIL — %s\n  %s\n' "$1" "$2"; fail=$((fail+1)); }
fatal() { printf 'FAIL — %s\n' "$1" >&2; exit 1; }
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

# ------------------------------------------------------------------ fixture builders
put_script() { # $1 repo, $2 relpath, $3 mode 755|644: write it, stage it, record exactly that mode
  mkdir -p "$(dirname "$1/$2")"
  printf '#!/bin/sh\nexit 0\n' > "$1/$2"
  chmod "$3" "$1/$2"
  git -C "$1" add -- "$2"
  if [ "$3" = 755 ]; then git -C "$1" update-index --chmod=+x -- "$2"; else git -C "$1" update-index --chmod=-x -- "$2"; fi
}

put_settings() { # $1 repo, rest: repo-relative scripts to register on PreToolUse; written and staged
  local repo="$1"; shift
  python3 -I - "$repo" "$@" <<'PY'
import json, sys
repo, rels = sys.argv[1], sys.argv[2:]
hooks = [{"type": "command", "command": "$HOME/.claude/" + r} for r in rels]
with open(repo + "/settings.json", "w") as f:
    json.dump({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": hooks}]}}, f)
PY
  git -C "$repo" add -- settings.json
}

commit_mode() { # $1 checkout, $2 relpath, $3 mode: a commit that stores the script that way
  put_script "$1" "$2" "$3"
  git -C "$1" commit -q -m "mode $3 $2" || fatal "fixture: commit_mode failed in $1"
}

reset_run() { G_GUARD="$GUARD"; G_HOME="$H"; G_PATH="$PATH"; }

new_fix() { # $1 = a.sh's mode in the first commit (default 755). Sets H, MAIN, WT (WT not yet created)
  n_fix=$((n_fix+1)); H="$TMP/h.$n_fix"; MAIN="$H/.claude"; WT="$H/wt"
  reset_run
  mkdir -p "$MAIN/hooks" || fatal "fixture $n_fix: mkdir failed"
  git -C "$MAIN" init -q -b main || fatal "fixture $n_fix: git init failed"
  git -C "$MAIN" config user.email t@t.t
  git -C "$MAIN" config user.name t
  put_script "$MAIN" hooks/a.sh "${1:-755}"
  put_settings "$MAIN" hooks/a.sh
  git -C "$MAIN" commit -q -m base || fatal "fixture $n_fix: first commit failed"
}

new_wt() { git -C "$MAIN" worktree add -q -b feat "$WT" || fatal "fixture $n_fix: worktree add failed"; }

add_unrelated_commit() { # $1 checkout: a commit that does not touch any hook or settings.json
  printf 'note\n' > "$1/note.txt"
  git -C "$1" add -- note.txt
  git -C "$1" commit -q -m "unrelated" || fatal "fixture: unrelated commit failed in $1"
}

mk_other() { # $1 dir: an independent repo (never a worktree of anything) whose HEAD stores a.sh 100644
  mkdir -p "$1/hooks" || fatal "fixture: mkdir $1 failed"
  git -C "$1" init -q -b main || fatal "fixture: git init $1 failed"
  git -C "$1" config user.email t@t.t
  git -C "$1" config user.name t
  put_script "$1" hooks/a.sh 644
  put_settings "$1" hooks/a.sh
  git -C "$1" commit -q -m other || fatal "fixture: commit in $1 failed"
}

head_mode() { git -C "$1" ls-tree HEAD -- hooks/a.sh | awk '{print $1}'; }
index_mode() { git -C "$1" ls-files -s -- hooks/a.sh | awk '{print $1}'; }
sane() { # $1 what, $2 got, $3 want: a fixture that is not what the case says it is proves nothing
  [ "$2" = "$3" ] || say_bad "fixture sanity: $1" "want $3, got $2"
}

mk_copy() { # sets CD: a scratch dir holding a copy of the guard beside a copy of hooks/lib
  n_copy=$((n_copy+1)); CD="$TMP/cp.$n_copy"
  mkdir -p "$CD" || fatal "copy $n_copy: mkdir failed"
  cp "$GUARD" "$CD/hook-exec-pr-guard.sh" 2>/dev/null || say_bad "fixture: copy the guard" "cannot copy $GUARD"
  cp -R "$HERE/lib" "$CD/lib" || fatal "copy $n_copy: cp -R hooks/lib failed"
  chmod -R u+w "$CD"
}

mk_bin() { # $1 dir, $2 1|0 (include git): symlinks to ordinary tools, never python3 or python
  local t p
  mkdir -p "$1" || fatal "mk_bin: mkdir $1 failed"
  for t in bash sh cat dirname basename sed awk grep tr head tail cut sort uniq env mktemp rm mkdir \
           pwd readlink realpath wc ls printf test id date cp mv ln sleep true false; do
    p="$(type -P "$t" 2>/dev/null)"
    case "$p" in /*) ln -s "$p" "$1/$t" ;; esac
  done
  if [ "$2" = 1 ]; then
    p="$(type -P git)"
    case "$p" in /*) ln -s "$p" "$1/git" ;; esac
  fi
}

# ------------------------------------------------------------------ runners and assertions
payload_for() { # $1 command -> a PreToolUse Bash payload, as judge-guard.test.sh builds it
  python3 -I -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}

run_guard() { # $1 cwd, $2 raw stdin. Uses G_GUARD, G_HOME ("__unset__" = no HOME at all), G_PATH
  local cwd="$1" raw="$2"
  if [ "$G_HOME" = "__unset__" ]; then
    ( cd "$cwd" || exit 97; printf '%s' "$raw" | env -u HOME "PATH=$G_PATH" /bin/bash "$G_GUARD" >"$TMP/out" 2>"$TMP/err" )
  else
    ( cd "$cwd" || exit 97; printf '%s' "$raw" | env "HOME=$G_HOME" "PATH=$G_PATH" /bin/bash "$G_GUARD" >"$TMP/out" 2>"$TMP/err" )
  fi
  RC=$?
  OUT="$(cat "$TMP/out")"; ERR="$(cat "$TMP/err")"
}
run_cmd() { run_guard "$1" "$(payload_for "$2")"; } # $1 cwd, $2 the Bash command

check_allow() { # $1 desc: the last run exited 0 and printed nothing on either stream
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then say_ok "$1"
  else say_bad "$1" "want exit 0 and no output; got rc=$RC stdout=[$OUT] stderr=[$ERR]"; fi
}

all_prefixed() { printf '%s\n' "$ERR" | awk -v p="$PREFIX" 'index($0, p) != 1 {bad = 1} END {exit bad + 0}'; }

check_exempt() { # $1 desc, $2 the exact stderr text the bypass must print
  if [ "$RC" -ne 0 ] || [ -n "$OUT" ]; then say_bad "$1" "want exit 0, no stdout; got rc=$RC stdout=[$OUT] stderr=[$ERR]"; return; fi
  contains "$ERR" "$2" || { say_bad "$1" "stderr lacks: $2"$'\n'"  got: [$ERR]"; return; }
  all_prefixed || { say_bad "$1" "a stderr line lacks the $PREFIX prefix: [$ERR]"; return; }
  say_ok "$1"
}

_deny() { # $1 need-repair-route 0|1, $2 desc, rest: strings stderr must contain (at least one)
  local route="$1" desc="$2" n lc; shift 2
  [ "$#" -gt 0 ] || { say_bad "$desc" "suite bug: a deny check needs at least one needle, or exit 2 alone passes"; return; }
  [ "$RC" -eq 2 ] || { say_bad "$desc" "want exit 2; got rc=$RC stdout=[$OUT] stderr=[$ERR]"; return; }
  [ -n "$ERR" ] || { say_bad "$desc" "exit 2 with an empty stderr"; return; }
  all_prefixed || { say_bad "$desc" "a stderr line lacks the $PREFIX prefix: [$ERR]"; return; }
  for n in "$@"; do
    contains "$ERR" "$n" || { say_bad "$desc" "stderr lacks: $n"$'\n'"  got: [$ERR]"; return; }
  done
  if [ "$route" = 1 ]; then
    lc="$(printf '%s' "$ERR" | tr '[:upper:]' '[:lower:]')"
    case "$lc" in
      *"write tool"*|*unregister*) ;;
      *) say_bad "$desc" "stderr names no repair route that survives the block (the Write tool, or unregistering the hook): [$ERR]"; return ;;
    esac
  fi
  say_ok "$desc"
}
check_deny() { _deny 0 "$@"; }
check_deny_route() { _deny 1 "$@"; }

# ------------------------------------------------------------------ sanity: the suite's own tools
NOPY="$TMP/nopy-bin"; mk_bin "$NOPY" 1
NOGIT="$TMP/nogit-bin"; mk_bin "$NOGIT" 0
if PATH="$NOPY" command -v python3 >/dev/null 2>&1 || PATH="$NOPY" command -v python >/dev/null 2>&1 \
   || ! PATH="$NOPY" git --version >/dev/null 2>&1; then
  say_bad "fixture sanity: the no-python PATH keeps git and has neither python3 nor python" "PATH=$NOPY"
else
  say_ok "fixture sanity: the no-python PATH keeps git and has neither python3 nor python"
fi
if PATH="$NOGIT" command -v git >/dev/null 2>&1; then
  say_bad "fixture sanity: the no-git PATH has no git" "PATH=$NOGIT"
else
  say_ok "fixture sanity: the no-git PATH has no git"
fi

# ------------------------------------------------------------------ Scenarios: what is checked
printf '== what is checked: the worktree HEAD, every registered script (R5) ==\n'

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
sane "HEAD stores 100644" "$(head_mode "$WT")" 100644
run_cmd "$WT" "gh pr create --fill"
check_deny "Scenario: a registered script stored 100644 blocks the PR" \
  "hooks/a.sh" "PreToolUse" "100644" "chmod +x" "git add --" "commit" "HOOK_EXEC_EXEMPT"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "gh pr create --fill"
check_deny "the refusal tells the fix in order: chmod, git add -- <path>, commit" \
  "chmod +x hooks/a.sh" "git add -- hooks/a.sh"

new_fix; new_wt
run_cmd "$WT" "gh pr create"
check_allow "Scenario: a clean branch (HEAD stores every registered script 100755) is allowed"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644; chmod 755 "$WT/hooks/a.sh"
[ -x "$WT/hooks/a.sh" ] || say_bad "fixture sanity: a.sh executable on disk" "not +x"
sane "HEAD stores 100644" "$(head_mode "$WT")" 100644
run_cmd "$WT" "gh pr create"
check_deny "Scenario: an executable copy on disk does not hide the 100644 commit" "hooks/a.sh" "100644"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
put_script "$WT" hooks/a.sh 755
sane "HEAD stores 100644" "$(head_mode "$WT")" 100644
sane "index stores 100755" "$(index_mode "$WT")" 100755
run_cmd "$WT" "gh pr create"
check_deny "Scenario: a staged fix that is not committed does not help" "hooks/a.sh" "100644"

new_fix; new_wt; put_script "$WT" hooks/a.sh 644
sane "HEAD stores 100755" "$(head_mode "$WT")" 100755
sane "index stores 100644" "$(index_mode "$WT")" 100644
run_cmd "$WT" "gh pr create"
check_allow "HEAD is what is published: a staged breakage that is not committed does not block"

new_fix 644; new_wt; add_unrelated_commit "$WT"
sane "HEAD stores 100644" "$(head_mode "$WT")" 100644
run_cmd "$WT" "gh pr create"
check_deny "Scenario: an unchanged old mistake (the branch never touches it) still blocks" "hooks/a.sh" "100644"

new_fix 644; new_wt; commit_mode "$WT" hooks/a.sh 755
run_cmd "$WT" "gh pr create"
check_allow "the branch is judged, not main: a branch that fixes the mode passes while main still stores 100644"

new_fix; new_wt; commit_mode "$MAIN" hooks/a.sh 644
sane "the worktree's HEAD stores 100755" "$(head_mode "$WT")" 100755
run_cmd "$WT" "gh pr create"
check_allow "the branch is judged, not main: a clean worktree passes while main's own HEAD is 100644"

new_fix; new_wt
put_settings "$WT" hooks/a.sh hooks/gone.sh
git -C "$WT" commit -q -m "register gone.sh" || fatal "fixture: commit failed"
run_cmd "$WT" "gh pr create"
check_deny "Scenario: a registered script missing from HEAD blocks, naming it as missing" \
  "hooks/gone.sh" "missing from commit HEAD"

new_fix; new_wt
put_script "$WT" hooks/b.sh 644; put_settings "$WT" hooks/a.sh hooks/b.sh
commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "gh pr create"
check_deny "every problem is listed, not just the first (R6)" "hooks/a.sh" "hooks/b.sh" "100644"

new_fix; new_wt
printf '{ "hooks": ' > "$WT/settings.json"; git -C "$WT" add -- settings.json
git -C "$WT" commit -q -m "break settings" || fatal "fixture: commit failed"
run_cmd "$WT" "gh pr create"
check_deny "Scenario: a settings.json at HEAD that is not valid JSON fails closed, naming the JSON error" \
  "settings.json" "JSON"

# ------------------------------------------------------------------ Scenarios: which repository (R4)
printf '\n== which repository: decided first, from bash and git only (R4) ==\n'

new_fix; mk_other "$H/other"
run_cmd "$H/other" "gh pr create"
check_allow "Scenario: another repository is untouched (bad HEAD there, exit 0, silent)"

new_fix; commit_mode "$MAIN" hooks/a.sh 644; git clone -q "$MAIN" "$H/clone" || fatal "fixture: clone failed"
sane "the clone's HEAD stores 100644" "$(head_mode "$H/clone")" 100644
run_cmd "$H/clone" "gh pr create"
check_allow "a clone of ~/.claude is another repository, not a worktree of it (known gap, scope decision)"

new_fix; mk_other "$MAIN/nested"
run_cmd "$MAIN/nested" "gh pr create"
check_allow "a repository nested inside ~/.claude has its own git dir and is out of scope"

new_fix; mkdir -p "$TMP/plain.$n_fix"
run_cmd "$TMP/plain.$n_fix" "gh pr create"
check_allow "Scenario: outside any repository the hook exits 0"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644; G_HOME="__unset__"
run_cmd "$WT" "gh pr create"
check_allow "Scenario: with HOME unset the hook exits 0"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644; G_HOME=""
run_cmd "$WT" "gh pr create"
check_allow "HOME empty: no ~/.claude to compare with, so the hook exits 0"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644; G_PATH="$NOGIT"
run_cmd "$WT" "gh pr create"
check_allow "git missing from PATH: scope is unknowable, so the hook exits 0"

new_fix; commit_mode "$MAIN" hooks/a.sh 644
sane "HEAD stores 100644" "$(head_mode "$MAIN")" 100644
run_cmd "$MAIN" "gh pr create"
check_deny "Scenario: the main checkout itself is in scope" "hooks/a.sh" "100644"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT/hooks" "gh pr create"
check_deny "a session in a subdirectory of the worktree is still in scope" "hooks/a.sh" "100644"

new_fix; commit_mode "$MAIN" hooks/a.sh 644
run_cmd "$MAIN/hooks" "gh pr create"
check_deny "a session in a subdirectory of the main checkout is still in scope" "hooks/a.sh" "100644"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
ln -s "$H" "$TMP/link.$n_fix"; G_HOME="$TMP/link.$n_fix"
run_cmd "$WT" "gh pr create"
check_deny "HOME reached through a symlink is resolved (cd -P) and still matches the git dir" "hooks/a.sh" "100644"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_guard "$WT" ""
check_allow "an empty stdin exits 0, silent"

# ------------------------------------------------------------------ Scenarios: which commands (R3)
printf '\n== which commands: only a real gh pr create, read per shell segment (R3) ==\n'

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "gh pr view 5";                          check_allow "Outline: gh pr view 5 passes with a bad HEAD"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" 'git commit -m "gh pr create later"';    check_allow "Outline: a commit message that mentions the phrase passes"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "echo gh pr create";                     check_allow "Outline: echo gh pr create passes"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "gh pr list";                            check_allow "gh pr list passes with a bad HEAD"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "ls";                                    check_allow "an ordinary command (ls) passes with a bad HEAD"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "git push && gh pr create --fill"
check_deny "Scenario: a chained gh pr create is still read" "hooks/a.sh" "100644"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "time gh -R o/r pr create"
check_deny "Scenario: a wrapped gh pr create (time, a global -R flag) is still read" "hooks/a.sh" "100644"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "rtk gh pr create --fill"
check_deny "an rtk-wrapped gh pr create is still read" "hooks/a.sh" "100644"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" $'git push -u origin br\ngh pr create --fill'
check_deny "a newline-separated gh pr create is still read" "hooks/a.sh" "100644"

# ------------------------------------------------------------------ Scenarios: the bypass (R7)
printf '\n== the bypass: HOOK_EXEC_EXEMPT=<reason> on the gh segment (R7) ==\n'

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "HOOK_EXEC_EXEMPT=docs-only gh pr create"
check_exempt "Scenario: the bypass allows and prints the reason" "hook-exec-pr-guard: exempted (HOOK_EXEC_EXEMPT=docs-only)"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" 'HOOK_EXEC_EXEMPT="docs only, ok" gh pr create --fill'
check_exempt "a quoted multi-word reason is read whole and printed" "hook-exec-pr-guard: exempted (HOOK_EXEC_EXEMPT=docs only, ok)"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" 'git push && HOOK_EXEC_EXEMPT=later gh pr create --fill'
check_exempt "the bypass on the gh segment of a chained command works" "hook-exec-pr-guard: exempted (HOOK_EXEC_EXEMPT=later)"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "JUDGE_EXEMPT=x gh pr create"
check_deny "Outline: JUDGE_EXEMPT is not a bypass here" "hooks/a.sh" "100644"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "HOOK_EXEC_EXEMPT= gh pr create"
check_deny "Outline: an empty HOOK_EXEC_EXEMPT is not a bypass" "hooks/a.sh" "100644"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "HOOK_EXEC_EXEMPT=x true && gh pr create --fill"
check_deny "Outline: HOOK_EXEC_EXEMPT on another segment is not a bypass" "hooks/a.sh" "100644"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "MERGE_EXEMPT=x gh pr create"
check_deny "MERGE_EXEMPT is not a bypass here" "hooks/a.sh" "100644"
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
run_cmd "$WT" "FOO_HOOK_EXEC_EXEMPT=x gh pr create"
check_deny "the variable name is matched exactly, never by suffix" "hooks/a.sh" "100644"

# ------------------------------------------------------------------ Scenarios: payloads
printf '\n== payloads: no command passes; an unreadable payload fails closed in scope (R3, R8) ==\n'

PAY_NOINPUT='{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
PAY_EMPTYINPUT='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{}}'
PAY_NUMCMD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":42}}'
PAY_NULLCMD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":null}}'
PAY_LISTCMD='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":["gh","pr","create"]}}'
PAY_BLANK='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"   "}}'
PAY_EMPTYSTR='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":""}}'
PAY_NEWLINE='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\n\t "}}'
PAY_TRUNC='{"hook_event_name":"PreToolUse","tool_input":{"command":'
PAY_ARRAY='[]'
PAY_ARRAY3='[1, 2, 3]'
PAY_STRING='"just a string"'
PAY_NULL='null'
PAY_NOTJSON='not json at all'

for_payload_allow() { # $1 desc, $2 raw payload: in scope with a bad HEAD, the call carries no command
  new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
  run_guard "$WT" "$2"
  check_allow "$1"
}
for_payload_allow "Scenario: a payload with no tool_input passes"                    "$PAY_NOINPUT"
for_payload_allow "Scenario: a payload whose tool_input has no command passes"        "$PAY_EMPTYINPUT"
for_payload_allow "a non-string command (number) passes"                              "$PAY_NUMCMD"
for_payload_allow "a non-string command (null) passes"                                "$PAY_NULLCMD"
for_payload_allow "a non-string command (list) passes"                                "$PAY_LISTCMD"
for_payload_allow "Scenario: a blank command (spaces) passes"                         "$PAY_BLANK"
for_payload_allow "an empty command string passes"                                    "$PAY_EMPTYSTR"
for_payload_allow "a whitespace-only command (newline, tab) passes"                   "$PAY_NEWLINE"

for_payload_deny() { # $1 desc, $2 raw payload: in scope, the payload cannot be read as an object
  new_fix; new_wt
  run_guard "$WT" "$2"
  check_deny_route "$1" "payload"
}
for_payload_deny "Outline: a truncated-JSON payload fails closed, naming the payload and a repair route" "$PAY_TRUNC"
for_payload_deny "a non-JSON payload fails closed, naming the payload"                                    "$PAY_NOTJSON"
for_payload_deny "valid JSON that is not an object ([]) is treated as unparseable"                        "$PAY_ARRAY"
for_payload_deny "valid JSON that is not an object ([1, 2, 3]) is treated as unparseable"                 "$PAY_ARRAY3"
for_payload_deny "valid JSON that is not an object (a string) is treated as unparseable"                  "$PAY_STRING"
for_payload_deny "valid JSON that is not an object (null) is treated as unparseable"                      "$PAY_NULL"

for_payload_other() { # $1 desc, $2 raw payload: the same unreadable payload in ANOTHER repository
  new_fix; mk_other "$H/other"
  run_guard "$H/other" "$2"
  check_allow "$1"
}
for_payload_other "scope comes first: a truncated payload in another repository exits 0, silent" "$PAY_TRUNC"
for_payload_other "scope comes first: a non-object payload ([]) in another repository exits 0, silent" "$PAY_ARRAY"

# ------------------------------------------------------------------ Scenarios: broken machinery (R8)
printf '\n== broken machinery: fails closed in scope, never reaches another repository (R8) ==\n'

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"
run_cmd "$WT" "gh pr create"
check_allow "control: an unbroken copy of the guard and hooks/lib allows a clean branch"

new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"
run_cmd "$WT" "gh pr create"
check_deny "control: an unbroken copy refuses a bad HEAD" "hooks/a.sh" "100644"

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"; : > "$CD/lib/classify-pr-command.py"
run_cmd "$WT" "ls"
check_deny_route "Outline: the classifier file is empty -> every Bash command refused, naming the classifier path" "classify-pr-command.py"

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"; rm -f "$CD/lib/classify-pr-command.py"
run_cmd "$WT" "ls"
check_deny_route "the classifier file is absent -> every Bash command refused, naming the classifier path" "classify-pr-command.py"

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"; printf 'def (\n' > "$CD/lib/classify-pr-command.py"
run_cmd "$WT" "ls"
check_deny_route "a classifier with a syntax error -> refused, naming the classifier path" "classify-pr-command.py"

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"
printf 'def classify(src, subcommand=None, exempt_var=None):\n    return ("MAYBE", "")\n' > "$CD/lib/classify-pr-command.py"
run_cmd "$WT" "ls"
check_deny_route "a classifier that answers something other than PR or NO -> refused, naming the classifier path" "classify-pr-command.py"

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"
printf 'def classify(src, subcommand=None, exempt_var=None):\n    raise RuntimeError("boom")\n' > "$CD/lib/classify-pr-command.py"
run_cmd "$WT" "ls"
check_deny_route "a classifier that raises -> refused, naming the classifier path" "classify-pr-command.py"

new_fix; new_wt; G_PATH="$NOPY"
run_cmd "$WT" "ls"
check_deny_route "Outline: python3 is not on PATH (git is) -> every Bash command refused, naming python3" "python3"

new_fix; new_wt; G_PATH="$NOPY"
run_cmd "$WT" "gh pr create"
check_deny_route "python3 missing, gh pr create -> refused, naming python3" "python3"

new_fix; new_wt
run_guard "$WT" "$PAY_TRUNC"
check_deny_route "Outline: the payload is truncated JSON -> refused, naming the payload and a repair route" "payload"

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"; : > "$CD/lib/classify-pr-command.py"; G_PATH="$NOPY"
mkdir -p "$H/other"; mk_other "$H/other"
run_cmd "$H/other" "gh pr create"
check_allow "Scenario: broken machinery never reaches another repository (empty classifier, no python3)"

new_fix; mk_other "$H/other"; G_PATH="$NOPY"
run_cmd "$H/other" "ls"
check_allow "python3 missing in another repository: exit 0, silent"

# ------------------------------------------------------------------ Scenarios: an unusable checker (R1, R6, R8)
printf '\n== an unusable checker: fails closed for gh pr create, naming the module (R6, R8) ==\n'
MODULE=registered_hook_modes.py

checker_case() { # $1 desc, $2 how: empty|absent|wrongline|passexit1|trailing|crash
  new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"
  case "$2" in
    empty)      : > "$CD/lib/$MODULE" ;;
    absent)     rm -f "$CD/lib/$MODULE" ;;
    wrongline)  printf 'import sys\nprint("result: MAYBE")\nsys.exit(0)\n' > "$CD/lib/$MODULE" ;;
    passexit1)  printf 'import sys\nprint("result: PASS")\nsys.exit(1)\n' > "$CD/lib/$MODULE" ;;
    trailing)   printf 'import sys\nprint("result: PASS")\nprint("counts: 0")\nsys.exit(0)\n' > "$CD/lib/$MODULE" ;;
    crash)      printf 'raise RuntimeError("boom")\n' > "$CD/lib/$MODULE" ;;
  esac
  run_cmd "$WT" "gh pr create"
  check_deny_route "$1" "$MODULE"
}
checker_case "Outline: the checker module is empty -> refused, naming the module"                          empty
checker_case "the checker module is absent -> refused, naming the module"                                  absent
checker_case "Outline: the checker exits 0 but its last line is not 'result: PASS' -> refused"             wrongline
checker_case "the checker prints 'result: PASS' but exits 1 -> refused (R6 needs both)"                    passexit1
checker_case "'result: PASS' is not the LAST line (a counts line follows) -> refused"                      trailing
checker_case "the checker crashes (exit 1, no result line) -> refused"                                     crash

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"; : > "$CD/lib/$MODULE"
run_cmd "$WT" "ls"
check_allow "a broken checker blocks only gh pr create: ls still passes (R8)"

new_fix; new_wt; mk_copy; G_GUARD="$CD/hook-exec-pr-guard.sh"
printf 'import sys\nprint("result: MAYBE")\nsys.exit(0)\n' > "$CD/lib/$MODULE"
run_cmd "$WT" "echo gh pr create"
check_allow "a lying checker is not consulted for a command that is not a PR creation"

# ------------------------------------------------------------------ the three file-mode assertions
printf '\n== the guard file itself (the #110 assertions) ==\n'

if [ -x "$GUARD" ]; then say_ok "the hook is executable on disk"; else say_bad "the hook is executable on disk" "not +x: $GUARD"; fi

git_mode="$(git -C "$HERE" ls-files -s -- hook-exec-pr-guard.sh 2>/dev/null)"
case "$git_mode" in
  100755*) say_ok "git records the hook as executable (100755)" ;;
  "")      say_bad "git records the hook as executable (100755)" "hooks/hook-exec-pr-guard.sh is not tracked: chmod +x it, then git add -- hooks/hook-exec-pr-guard.sh" ;;
  *)       say_bad "git records the hook as executable (100755)" "got: $git_mode" ;;
esac

# settings.json runs the script as a bare command; every other run here goes through `bash <path>`
# and is blind to the mode bit. 126/127 mean it could not even start.
new_fix; new_wt; commit_mode "$WT" hooks/a.sh 644
( cd "$WT" || exit 97; payload_for "gh pr create" | env "HOME=$H" "PATH=$PATH" "$GUARD" >"$TMP/out" 2>"$TMP/err" )
RC=$?; OUT="$(cat "$TMP/out")"; ERR="$(cat "$TMP/err")"
if [ "$RC" -eq 126 ] || [ "$RC" -eq 127 ]; then
  say_bad "the hook runs directly with no bash prefix" "rc=$RC err=[$ERR]"
else
  check_deny "the hook runs directly with no bash prefix, and still refuses a bad HEAD (rc=$RC)" "hooks/a.sh" "100644"
fi

printf '\nhook-exec-pr-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
