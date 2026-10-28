#!/usr/bin/env bash
# registered-hooks-executable.test.sh -- every hook script registered in settings.json must be
# stored in git as mode 100755. A script stored 100644 cannot be started by Claude Code (exit
# 126), so the hook it implements silently does nothing. Spec: docs/features/hook-exec-bit-test.md
# (R1-R7a).
# Run BY HAND: bash hooks/registered-hooks-executable.test.sh
# This suite itself still has no CI and nothing runs it when a hook is added (R7a); run it after
# editing settings.json or adding a hook script. The same check (the shared module, against HEAD)
# now also runs at `gh pr create` through hooks/hook-exec-pr-guard.sh (docs/decisions/0049-*).
#
# What it reads: settings.json and file modes come from the git INDEX (git show :settings.json,
# git ls-files -s), never the working tree, so a local chmod +x cannot hide a 100644 that a fresh
# clone would receive. Checking is one function, check_repo <repo-root> [--rev <commit>], a call
# into hooks/lib/registered_hook_modes.py; the suite runs it against
# throwaway fixture repos (to prove it can both fail and pass), then once against the repository
# that contains this file. Every fixture builds its own repo in its own mktemp -d.
#
# Known limit, accepted: a parser regression that loses SOME scripts (say 23 -> 20) still passes;
# the printed counts and a by-hand comparison are the only guard against that.
set -u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)" || { printf 'FAIL — mktemp -d failed; cannot build fixtures\n' >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT
export GIT_CEILING_DIRECTORIES="$TMP"
HERE="$(cd "$(dirname "$0")" && pwd -P)"
OUT=""; RC=0; n_repo=0
pass=0; fail=0

# ------------------------------------------------------------------ the checker
# check_repo <repo-root> [--rev <commit>]: one call to the shared checker (R1), which prints
# "ok/skip/FAIL" lines, a counts line and "result: PASS|FAIL"; exit 0 when clean, 1 otherwise.
# Without --rev it reads the git index; with --rev it reads that commit. Extra args pass through.
check_repo() {
  python3 -I "$HERE/lib/registered_hook_modes.py" "$@"
}

# ------------------------------------------------------------------ fixture builders
say_ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
say_bad() { printf 'FAIL — %s\n  %s\n' "$1" "$2"; fail=$((fail+1)); }

new_repo() { # sets REPO to a fresh git repo of its own (no case inherits another's state)
  n_repo=$((n_repo+1)); REPO="$TMP/fix.$n_repo"
  mkdir -p "$REPO" && git -C "$REPO" init -q || { say_bad "fixture $n_repo" "git init failed in $REPO"; exit 1; }
}

add_script() { # $1 repo, $2 relpath, $3 index mode (755|644), $4 disk mode (755|644, default = $3)
  mkdir -p "$(dirname "$1/$2")"
  printf '#!/bin/sh\nexit 0\n' > "$1/$2"
  chmod "${4:-$3}" "$1/$2"
  git -C "$1" add -- "$2"
  if [ "$3" = 755 ]; then git -C "$1" update-index --chmod=+x -- "$2"; else git -C "$1" update-index --chmod=-x -- "$2"; fi
}

put_settings() { # $1 repo, then "Event<TAB>command" args ("@nocmd" = a hook with no command
  # field; event "statusLine" = the top-level statusLine key); written and staged
  python3 -I - "$@" <<'PY'
import json, sys
repo, specs = sys.argv[1], sys.argv[2:]
out = {"hooks": {}}
for spec in specs:
    event, _, cmd = spec.partition("\t")
    handler = {"type": "command"} if cmd == "@nocmd" else {"type": "command", "command": cmd}
    if event == "statusLine":
        out["statusLine"] = handler
    else:
        out["hooks"].setdefault(event, []).append({"hooks": [handler]})
with open(repo + "/settings.json", "w") as f:
    json.dump(out, f)
PY
  git -C "$1" add -- settings.json
}

T="$(printf '\t')"
RUN_EXTRA=""   # extra checker args for the next run_check (word-split on purpose: "--rev HEAD")
run_check() { OUT="$(check_repo "$1" $RUN_EXTRA 2>&1)"; RC=$?; }
with_extra() { # $1 extra checker args, rest: a command (expect_fail ...) run with them, then reset
  RUN_EXTRA="$1"; shift; "$@"; RUN_EXTRA=""
}
commit_repo() { # $1 repo: commit whatever is staged (no pathspec, so staged modes are kept)
  git -C "$1" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m fixture \
    || { say_bad "fixture commit" "git commit failed in $1"; exit 1; }
}

expect_fail() { # $1 desc, $2 repo, rest: strings the output must contain
  local desc="$1" repo="$2" needle; shift 2
  run_check "$repo"
  [ "$RC" -ne 0 ] || { say_bad "$desc" "wanted a failure, got rc=0"$'\n'"$OUT"; return; }
  for needle in "$@"; do
    case "$OUT" in *"$needle"*) ;; *) say_bad "$desc" "output lacks: $needle"$'\n'"$OUT"; return ;; esac
  done
  say_ok "$desc"
}
expect_pass() { # same, for a clean run
  local desc="$1" repo="$2" needle; shift 2
  run_check "$repo"
  [ "$RC" -eq 0 ] || { say_bad "$desc" "wanted a pass, got rc=$RC"$'\n'"$OUT"; return; }
  for needle in "$@"; do
    case "$OUT" in *"$needle"*) ;; *) say_bad "$desc" "output lacks: $needle"$'\n'"$OUT"; return ;; esac
  done
  say_ok "$desc"
}
lacks() { # $1 desc, $2 needle the LAST run's output must not hold (call right after expect_*)
  case "$OUT" in *"$2"*) say_bad "$1" "output unexpectedly contains: $2"$'\n'"$OUT" ;; *) say_ok "$1" ;; esac
}

# ------------------------------------------------------------------ R6 fixture cases
printf '== fixtures (each builds its own repo) ==\n'

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 644
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
expect_fail "a 100644 registered script fails, naming path, event and mode" "$r" "hooks/x.sh" "Stop" "100644"

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
expect_pass "the same script at 100755 passes and prints its counts" "$r" "result: PASS" "checked scripts (distinct) 1"

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 644 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
[ -x "$r/hooks/x.sh" ] || say_bad "fixture sanity" "hooks/x.sh should be executable on disk"
expect_fail "100644 in the index but executable on disk still fails (a local chmod hides nothing)" "$r" "hooks/x.sh" "100644"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
add_script "$r" statusline.sh 644
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "statusLine${T}bash \"\$HOME/.claude/statusline.sh\""
expect_pass "an interpreter-invoked 100644 script passes and is listed as skipped (interpreter)" "$r" "skip  [statusLine] interpreter"
lacks "the interpreter-invoked script is not reported as a failure" "FAIL"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
add_script "$r" hooks/y.sh 644
add_script "$r" hooks/z.py 644
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}bash -e \$HOME/.claude/hooks/y.sh" "Stop${T}python3 -I \$HOME/.claude/hooks/z.py"
expect_pass "options before the script file (bash -e, python3 -I) still count as interpreter + file" "$r" "skip  [Stop] interpreter: bash -e" "skip  [Stop] interpreter: python3 -I"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}\$HOME/.claude/hooks/gone.sh"
expect_fail "a registered path missing from the index fails and is named as missing" "$r" "hooks/gone.sh" "missing from the git index"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}if [ -f \"\$HOME/.orca/h.sh\" ]; then /bin/sh \"\$HOME/.orca/h.sh\"; fi"
expect_pass "a non-path command beside one valid 100755 script passes and is listed as skipped" "$r" "skip  [Stop] other command: if [ -f" "skipped commands 1"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}@nocmd"
expect_pass "an entry with no command field is listed as skipped (no command), never a crash" "$r" "skip  [Stop] no command" "result: PASS"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
add_script "$r" x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}bash -c \"\$HOME/.claude/x.sh\""
expect_fail "bash -c \"\$HOME/.claude/x.sh\" fails with its own unread-path message" "$r" "unread .claude/ path" "bash -c"
lacks "...and not with the zero-scripts message" "found no registered hook scripts"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}bash -lc \"\$HOME/.claude/x.sh\""
expect_fail "a combined short flag containing c (-lc) is treated as -c" "$r" "unread .claude/ path" "bash -lc"

new_repo; r="$REPO"
add_script "$r" hooks/a.sh 644
put_settings "$r" "Stop${T}VAR=1 \$HOME/.claude/hooks/a.sh"
expect_fail "a VAR=1 assignment prefix is dropped and the script is checked" "$r" "hooks/a.sh" "100644"

new_repo; r="$REPO"
add_script "$r" hooks/a.sh 644
add_script "$r" hooks/b.sh 644
add_script "$r" hooks/c.sh 644
put_settings "$r" "Stop${T}VAR=1 \$HOME/.claude/hooks/a.sh" "Stop${T}~/.claude/hooks/b.sh" "Stop${T}\${HOME}/.claude/hooks/c.sh"
expect_fail "VAR=1, ~/.claude/ and \${HOME}/.claude/ forms are all checked" "$r" "hooks/a.sh" "hooks/b.sh" "hooks/c.sh"

new_repo; r="$REPO"
add_script "$r" hooks/a.sh 755
add_script "$r" hooks/b.sh 755
add_script "$r" hooks/c.sh 755
put_settings "$r" "Stop${T}VAR=1 \$HOME/.claude/hooks/a.sh" "Stop${T}~/.claude/hooks/b.sh" "Stop${T}\${HOME}/.claude/hooks/c.sh"
expect_pass "the same three spellings at 100755 pass with three distinct scripts" "$r" "checked scripts (distinct) 3"

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 644
put_settings "$r" "PreToolUse${T}\$HOME/.claude/hooks/x.sh" "Stop${T}\$HOME/.claude/hooks/x.sh"
expect_fail "one script on two events is reported once, naming both events" "$r" "hooks/x.sh" "PreToolUse, Stop"
n_fail_lines="$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^FAIL ')"
[ "$n_fail_lines" -eq 1 ] && say_ok "...as exactly one FAIL line" || say_bad "...as exactly one FAIL line" "got $n_fail_lines"$'\n'"$OUT"

new_repo; r="$REPO"
printf '{ "hooks": ' > "$r/settings.json"; git -C "$r" add -- settings.json
expect_fail "settings.json in the index that is not valid JSON fails and says so" "$r" "not valid JSON"

new_repo; r="$REPO"
expect_fail "settings.json absent from the index fails and says so" "$r" "missing from the git index"

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
git -C "$r" reset -q -- settings.json
expect_fail "settings.json only in the working tree (not staged) fails: the index is what is read" "$r" "missing from the git index"

new_repo; r="$REPO"
put_settings "$r" "Stop${T}echo hello"
expect_fail "zero checked scripts fails: the parser is broken, not the repo clean" "$r" "found no registered hook scripts"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
add_script "$r" hooks/x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}exec \"\$HOME/.claude/hooks/x.sh\""
expect_fail "a skipped command containing .claude/ fails, naming it as an unread path" "$r" "unread .claude/ path" "exec"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}\$HOME/.claude/hooks/q.sh \"unbalanced"
expect_fail "a command that cannot be split (unbalanced quotes) fails" "$r" "cannot split the command"

new_repo; r="$REPO"
add_script "$r" hooks/sl.sh 644
put_settings "$r" "statusLine${T}\$HOME/.claude/hooks/sl.sh"
expect_fail "a direct-path statusLine is checked too" "$r" "hooks/sl.sh" "statusLine" "100644"

new_repo; r="$REPO"
add_script "$r" hooks/n.sh 644
put_settings "$r" "BrandNewEventName${T}\$HOME/.claude/hooks/n.sh"
expect_fail "an event key nobody listed in advance is covered (no hard-coded event names)" "$r" "hooks/n.sh" "BrandNewEventName"

mkdir -p "$TMP/not-a-repo"
expect_fail "a target that is not a git repository fails" "$TMP/not-a-repo" "not a git repository"

# ------------------------------------------------------------------ R2 cases: --rev reads a commit
# Each builds an index that DIFFERS from HEAD, so a checker that reads the wrong side (or mixes
# the two) gives the wrong answer. HEAD is made by commit_repo (no pathspec), then the index is
# moved with git update-index / git add.
printf '\n== --rev HEAD (the commit, never the index) ==\n'

new_repo; r="$REPO"   # (a) 100755 in the index, 100644 in HEAD
add_script "$r" hooks/x.sh 644
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
commit_repo "$r"
git -C "$r" update-index --chmod=+x -- hooks/x.sh
with_extra "--rev HEAD" expect_fail "(a) 100755 in the index but 100644 in HEAD fails with --rev HEAD, naming the path, mode and commit HEAD" "$r" "hooks/x.sh" "100644" "commit HEAD"
lacks "(a) ...and the --rev message does not name the git index" "git index"
expect_pass "(a) ...while the same repo passes without --rev (the index is 100755)" "$r" "result: PASS"

new_repo; r="$REPO"   # (b) 100644 in the index, 100755 in HEAD
add_script "$r" hooks/x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
commit_repo "$r"
git -C "$r" update-index --chmod=-x -- hooks/x.sh
with_extra "--rev HEAD" expect_pass "(b) 100644 in the index but 100755 in HEAD passes with --rev HEAD" "$r" "result: PASS" "checked scripts (distinct) 1"
expect_fail "(b) ...while the same repo fails without --rev (the index is 100644)" "$r" "hooks/x.sh" "100644"

new_repo; r="$REPO"   # (c) HEAD's settings.json registers a script the index's does not
add_script "$r" hooks/ok.sh 755
add_script "$r" hooks/bad.sh 644
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}\$HOME/.claude/hooks/bad.sh"
commit_repo "$r"
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh"
with_extra "--rev HEAD" expect_fail "(c) a 100644 script registered only in HEAD's settings.json fails with --rev HEAD" "$r" "hooks/bad.sh" "100644"
expect_pass "(c) ...and passes without --rev (the index's settings.json does not register it)" "$r" "result: PASS" "checked scripts (distinct) 1"

new_repo; r="$REPO"   # (d) a ref that does not resolve
add_script "$r" hooks/x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
commit_repo "$r"
with_extra "--rev nosuchref" expect_fail "(d) --rev nosuchref fails and names nosuchref" "$r" "nosuchref" "result: FAIL"

# R1: every line that names its source says "commit <c>" where the index run says the index.
new_repo; r="$REPO"   # registered script absent from HEAD but present in the index
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}\$HOME/.claude/hooks/gone.sh"
commit_repo "$r"
add_script "$r" hooks/gone.sh 755
with_extra "--rev HEAD" expect_fail "--rev: a registered path absent from the commit is reported as missing from commit HEAD" "$r" "hooks/gone.sh" "missing from commit HEAD"
lacks "--rev: ...and not as missing from the git index" "git index"

new_repo; r="$REPO"   # settings.json absent from HEAD but staged in the index
add_script "$r" hooks/x.sh 755
commit_repo "$r"
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
with_extra "--rev HEAD" expect_fail "--rev: settings.json absent from the commit fails as missing from commit HEAD" "$r" "settings.json is missing from commit HEAD"
lacks "--rev: ...and does not name the git index" "git index"

new_repo; r="$REPO"   # invalid JSON in HEAD, valid JSON staged
add_script "$r" hooks/x.sh 755
printf '{ "hooks": ' > "$r/settings.json"; git -C "$r" add -- settings.json
commit_repo "$r"
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
with_extra "--rev HEAD" expect_fail "--rev: settings.json that is not valid JSON in the commit fails, naming commit HEAD" "$r" "not valid JSON" "commit HEAD"
lacks "--rev: ...and does not say 'in the index'" "in the index"

new_repo; r="$REPO"   # valid JSON but not an object in HEAD, valid object staged
add_script "$r" hooks/x.sh 755
printf '[]' > "$r/settings.json"; git -C "$r" add -- settings.json
commit_repo "$r"
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
with_extra "--rev HEAD" expect_fail "--rev: settings.json that is valid JSON but not an object fails, naming commit HEAD" "$r" "valid JSON but not an object" "commit HEAD"
lacks "--rev: ...and does not say 'in the index'" "in the index"

# ------------------------------------------------------------------ the real repo
printf '\n== the real repo (the repository containing this suite) ==\n'
REAL_ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REAL_ROOT" ]; then
  say_bad "real repo: locate the repository that contains this suite" "git -C $HERE rev-parse --show-toplevel failed"
else
  run_check "$REAL_ROOT"
  printf '%s\n' "$OUT"
  [ "$RC" -eq 0 ] && say_ok "every registered hook script in $REAL_ROOT is stored 100755" \
    || say_bad "every registered hook script in $REAL_ROOT is stored 100755" "see the FAIL lines above"
fi

printf '\nregistered-hooks-executable: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
