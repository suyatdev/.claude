#!/usr/bin/env bash
# worktree-guard.test.sh — unit tests for worktree-guard.sh (layer 1).
#
# Written BEFORE the hook exists (card task 3, TDD). Every case below is expected
# to fail until task 4/5/6 land; the suite's job today is to be red for the right
# reason — "hook not found", not "assertion never evaluated".
#
# Feeds PreToolUse JSON on stdin — the code path that actually runs in
# production — from inside throwaway git repos under $TMP, with $HOME redirected
# so ~/.worktrees is a fixture rather than the real store, and the log redirected
# so no case can append to hooks/state/worktree-guard.log.
#
# Run: bash hooks/worktree-guard.test.sh
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/worktree-guard.sh"
LIB="$HERE/lib"

# Physical path, not the one mktemp hands back. On macOS `mktemp -d` returns the
# /var symlink form while `git rev-parse` resolves to /private/var, so fixture
# paths built from the symlink form would never compare equal to what the guard
# reads — every path test would pass or fail for the wrong reason.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GIT_REAL="$(command -v git)"

# The two test-time redirections. HOME_FIX makes ~/.worktrees a fixture;
# STATE_DIR relocates the log the guard appends refusals to. The state-dir
# override follows the existing house precedent, phase-guard.sh's
# PHASE_GUARD_STATE_DIR — without one, "the log cannot be appended to" cases
# would have to break the real hooks/state directory.
HOME_FIX="$TMP/home"
STATE_DIR="$TMP/state"
LOG="$STATE_DIR/worktree-guard.log"
mkdir -p "$HOME_FIX/.worktrees" "$STATE_DIR"
chmod 700 "$HOME_FIX/.worktrees"

pass=0; fail=0; skip=0; n=0

ok()   { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL — %s\n' "$1"; fail=$((fail+1)); }
# A skip is counted, not merely printed. A case this suite cannot construct is a
# gap in coverage; leaving it out of the totals lets "0 failed" read as "every
# scenario is pinned", which is the one thing the summary line must not do.
skipped() { printf 'skip — %s\n' "$1"; skip=$((skip+1)); }

# ---------------------------------------------------------------- payloads ---

payload_write() { # $1 tool, $2 path key (file_path|notebook_path), $3 path, [$4 session_id]
  python3 -c 'import json,sys
d={"hook_event_name":"PreToolUse","tool_name":sys.argv[1],
   "tool_input":{sys.argv[2]:sys.argv[3]}}
if len(sys.argv)>4: d["session_id"]=sys.argv[4]
print(json.dumps(d))' "$@"
}

payload_nopath() { # $1 tool — the write-family payload carrying NO path key (boundary 2)
  python3 -c 'import json,sys
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":sys.argv[1],
                  "tool_input":{"content":"x"},"session_id":"s-nopath"}))' "$1"
}

payload_bash() { # $1 command, [$2 session_id]
  python3 -c 'import json,sys
d={"hook_event_name":"PreToolUse","tool_name":"Bash",
   "tool_input":{"command":sys.argv[1]}}
if len(sys.argv)>2: d["session_id"]=sys.argv[2]
print(json.dumps(d))' "$@"
}

# ----------------------------------------------------------------- runner ---

# Per-case environment. Set RUN_ENV before an assertion; the runner consumes and
# clears it, so a knob can never leak into the next case. Entries land AFTER the
# defaults on the `env` line, so a case can override WORKTREE_GUARD_MODE, HOME or
# PATH by naming it again.
RUN_ENV=()

got=0; out=""; err=""
_run() { # $1 cwd, $2 payload text — exit code in $got, streams in $out/$err
  n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
  ( cd "$1" && printf '%s' "$2" | env \
      HOME="$HOME_FIX" \
      WORKTREE_GUARD_STATE_DIR="$STATE_DIR" \
      WORKTREE_GUARD_MODE=deny \
      ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
      bash "$HOOK" ) >"$out" 2>"$err"
  got=$?
  # 127 is bash reporting the hook is not on disk. Every "stderr does not say X"
  # assertion is trivially true against that, so the negative helpers below
  # refuse to count until some invocation in this run has actually reached the
  # hook. See LOG_LIVE for the same argument about the log.
  [ "$got" -ne 127 ] && HOOK_RAN=1
  RUN_ENV=()
}
HOOK_RAN=0

# The stderr counterpart of assert_log_lacks. A required-absence assertion is
# evidence only once the hook has been observed to run at all.
assert_last_stderr_lacks() { # $1 desc, $2 forbidden substring
  if [ "$HOOK_RAN" != 1 ]; then
    printf 'FAIL — %s (VACUOUS: the hook has not been reached in this run)\n' "$1"
    fail=$((fail+1)); return
  fi
  if grep -qF -- "$2" "$err"; then
    printf 'FAIL — %s (found forbidden substring: %s)\n  stderr: %s\n' "$1" "$2" "$(cat "$err")"
    fail=$((fail+1)); return
  fi
  ok "$1"
}

# deny: exit 2, and stderr carries the house prefix. The prefix is asserted on
# every deny because both this hook and phase-guard.sh are PreToolUse on the same
# matchers — a bare exit 2 does not establish which one refused.
deny() { # $1 desc, $2 cwd, $3 payload, [$4 required stderr substring]
  local desc="$1"
  _run "$2" "$3"
  if [ "$got" -ne 2 ]; then
    printf 'FAIL — %s (want exit 2, got %s)\n  stderr: %s\n' \
      "$desc" "$got" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  if ! grep -qF 'worktree-guard:' "$err"; then
    printf 'FAIL — %s (stderr carries no worktree-guard: prefix)\n  stderr: %s\n' \
      "$desc" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  if [ $# -ge 4 ] && ! grep -qF -- "$4" "$err"; then
    printf 'FAIL — %s\n  want (substring): %s\n  stderr: %s\n' \
      "$desc" "$4" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  ok "$desc"
}

# allow_silent: exit 0, empty stdout, empty stderr. All three, because an "allow"
# that warns is a different behavior from an allow that says nothing, and several
# boundaries below distinguish exactly those two.
allow_silent() { # $1 desc, $2 cwd, $3 payload
  local desc="$1"
  _run "$2" "$3"
  if [ "$got" -ne 0 ]; then
    printf 'FAIL — %s (want exit 0, got %s)\n  stderr: %s\n' \
      "$desc" "$got" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  if [ -s "$out" ]; then
    printf 'FAIL — %s (stdout not empty: %s)\n' "$desc" "$(cat "$out")"; fail=$((fail+1)); return
  fi
  if [ -s "$err" ]; then
    printf 'FAIL — %s (stderr not empty: %s)\n' "$desc" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  ok "$desc"
}

# allow_warn: exit 0, but stderr carries $4. The log-append fail-opens
# (boundary 10, rules 1 and 3) are allows that must still be audible; asserting
# them with allow_silent would pass on a guard that dropped the warning.
allow_warn() { # $1 desc, $2 cwd, $3 payload, $4 required stderr substring
  local desc="$1"
  _run "$2" "$3"
  if [ "$got" -ne 0 ]; then
    printf 'FAIL — %s (want exit 0, got %s)\n  stderr: %s\n' \
      "$desc" "$got" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  if ! grep -qF -- "$4" "$err"; then
    printf 'FAIL — %s\n  want (substring): %s\n  stderr: %s\n' \
      "$desc" "$4" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  ok "$desc"
}

# -------------------------------------------------------------------- log ---

log_reset() { rm -f "$LOG"; }

# `grep -c .` prints 0 AND exits 1 on an empty file, so the obvious
# `[ -f x ] && grep -c . x || printf 0` one-liner emits "0\n0" for a log that
# exists but is empty — which no numeric comparison below would match. The
# absent and empty cases are separated explicitly.
log_lines() {
  [ -f "$LOG" ] || { printf '0'; return; }
  grep -c . "$LOG" || true
}

# A negative log assertion is VACUOUS until something in this run has been seen
# to write a line: with no hook on disk, "nothing was appended" is true of every
# conceivable implementation, and the case reports ok while proving nothing.
# log_control() is the falsifier — it drives one would-deny in log mode and
# requires exactly one line. Until it succeeds, assert_log_empty and
# assert_log_lacks fail as vacuous rather than passing.
LOG_LIVE=0
log_control() { # $1 desc, $2 cwd, $3 payload
  log_reset
  RUN_ENV=(WORKTREE_GUARD_MODE=log)
  _run "$2" "$3"
  local c; c="$(log_lines)"
  if [ "$c" = 1 ]; then LOG_LIVE=1; ok "$1"; else
    printf 'FAIL — %s (want exactly 1 log line, got %s)\n' "$1" "$c"
    fail=$((fail+1))
  fi
}

assert_log_empty() { # $1 desc
  if [ "$LOG_LIVE" != 1 ]; then
    printf 'FAIL — %s (VACUOUS: no log line has been observed in this run)\n' "$1"
    fail=$((fail+1)); return
  fi
  local c; c="$(log_lines)"
  if [ "$c" = 0 ]; then ok "$1"; else
    printf 'FAIL — %s (want 0 log lines, got %s)\n%s\n' "$1" "$c" "$(cat "$LOG")"
    fail=$((fail+1))
  fi
}

assert_log_count() { # $1 desc, $2 expected line count
  # Expecting zero is a required-absence assertion and takes the same control as
  # assert_log_empty; expecting one or more is self-falsifying and does not.
  if [ "$2" = 0 ] && [ "$LOG_LIVE" != 1 ]; then
    printf 'FAIL — %s (VACUOUS: no log line has been observed in this run)\n' "$1"
    fail=$((fail+1)); return
  fi
  local c; c="$(log_lines)"
  if [ "$c" = "$2" ]; then ok "$1"; else
    printf 'FAIL — %s (want %s log lines, got %s)\n%s\n' "$1" "$2" "$c" \
      "$(cat "$LOG" 2>/dev/null)"; fail=$((fail+1))
  fi
}

assert_log_has() { # $1 desc, $2 required substring
  if [ -f "$LOG" ] && grep -qF -- "$2" "$LOG"; then ok "$1"; else
    printf 'FAIL — %s\n  want (substring): %s\n  log:\n%s\n' "$1" "$2" \
      "$(cat "$LOG" 2>/dev/null)"; fail=$((fail+1))
  fi
}

assert_log_lacks() { # $1 desc, $2 forbidden substring
  if [ "$LOG_LIVE" != 1 ]; then
    printf 'FAIL — %s (VACUOUS: no log line has been observed in this run)\n' "$1"
    fail=$((fail+1)); return
  fi
  if [ -f "$LOG" ] && grep -qF -- "$2" "$LOG"; then
    printf 'FAIL — %s (found forbidden substring: %s)\n%s\n' "$1" "$2" "$(cat "$LOG")"
    fail=$((fail+1))
  else ok "$1"; fi
}

# --------------------------------------------------------------- fixtures ---

git_q() { "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

mk_repo() { # $1 absolute path — a primary checkout with one commit
  mkdir -p "$1"
  git_q -C "$1" init -q
  git_q -C "$1" commit -q --allow-empty -m init
  mkdir -p "$1/hooks" "$1/panes" "$1/docs/features" "$1/rules" "$1/skills/treko"
  : > "$1/hooks/git-guard.sh"; : > "$1/panes/run-pane-agent.sh"
}

mk_linked() { # $1 repo path, $2 worktree name — under the centralized root
  local base; base="$(basename "$1")"
  mkdir -p "$HOME_FIX/.worktrees/$base"
  git_q -C "$1" worktree add -q "$HOME_FIX/.worktrees/$base/$2" -b "$2" >/dev/null 2>&1
  mkdir -p "$HOME_FIX/.worktrees/$base/$2/hooks"
  : > "$HOME_FIX/.worktrees/$base/$2/hooks/git-guard.sh"
  printf '%s\n' "$1" > "$HOME_FIX/.worktrees/$base/.repo-root"
}

# ------------------------------------------------------------------ stubs ---

# A `git` shim placed ahead of the real one on PATH. Every knob is an environment
# variable so a case bends exactly one probe and leaves the rest real: a stub that
# answered everything would let an implementation pass this suite without ever
# calling git.
mk_git_stub() {
  mkdir -p "$TMP/stub"
  cat > "$TMP/stub/git" <<STUB
#!/bin/sh
# knobs: STUB_VERSION, STUB_TOPLEVEL_RC/STUB_TOPLEVEL_MSG,
#        STUB_FAIL_PROBE (rev-parse flag -> exit 128),
#        STUB_EMPTY_PROBE (rev-parse flag -> exit 0, no output)
if [ "\$1" = "--version" ] && [ -n "\${STUB_VERSION:-}" ]; then
  printf '%s\n' "\$STUB_VERSION"; exit 0
fi
is_rp=0; probe=""
for a in "\$@"; do
  case "\$a" in
    rev-parse) is_rp=1 ;;
    --show-toplevel|--show-superproject-working-tree|--git-dir|--git-common-dir|--absolute-git-dir|--show-ref-format)
      probe="\$a" ;;
  esac
done
if [ "\$is_rp" = 1 ] && [ -n "\$probe" ]; then
  if [ "\$probe" = "--show-toplevel" ] && [ -n "\${STUB_TOPLEVEL_RC:-}" ]; then
    printf '%s\n' "\${STUB_TOPLEVEL_MSG:-}" >&2
    exit "\$STUB_TOPLEVEL_RC"
  fi
  [ "\$probe" = "\${STUB_FAIL_PROBE:-}" ]  && exit 128
  [ "\$probe" = "\${STUB_EMPTY_PROBE:-}" ] && exit 0
fi
exec "$GIT_REAL" "\$@"
STUB
  chmod +x "$TMP/stub/git"
  printf '%s' "$TMP/stub:$PATH"
}

# A PATH from which the named executables are genuinely absent — a farm of
# symlinks to everything else on the current PATH. `command -v` must fail, so a
# shim that exits 127 would not do: that tests a broken tool, not a missing one.
mk_shadow_path() { # $1 shadow dir name, $2.. basenames to exclude
  local dir="$TMP/$1" d f b excl x
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    local IFS=:
    for d in $PATH; do
      unset IFS
      [ -d "$d" ] || { IFS=:; continue; }
      for f in "$d"/*; do
        b="${f##*/}"; excl=0
        for x in "${@:2}"; do [ "$b" = "$x" ] && excl=1; done
        [ "$excl" = 1 ] && continue
        [ -e "$dir/$b" ] && continue
        ln -s "$f" "$dir/$b" 2>/dev/null
      done
      IFS=:
    done
    unset IFS
  fi
  printf '%s' "$dir"
}

# ================================================================= GROUP P ===
# Feature: worktree-guard.sh — preconditions shared by every arm (card :1524)

PRIMARY="$TMP/repos/.claude"
mk_repo "$PRIMARY"
mk_linked "$PRIMARY" "feat-x"
LINKED="$HOME_FIX/.worktrees/.claude/feat-x"
WT_ROOT="$HOME_FIX/.worktrees/.claude"

# P0 — the falsifiability control for every assert_log_empty/assert_log_lacks
# below. A write at the root of a primary checkout is a would-deny; in log mode
# it must produce exactly one line. Until this passes, the negative log
# assertions in this suite are not evidence and report themselves as vacuous.
log_control 'P0 the log can be written in this run (control for every log-empty case)' \
  "$PRIMARY" "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-p0)"

log_reset

# P1 — Scenario Outline: The stdin payload cannot be parsed (boundary 1).
# The guard cannot identify what it is being asked to permit, so it cannot
# permit it. This deny precedes arm selection entirely.
deny 'P1a payload absent'                 "$PRIMARY" ''
deny 'P1b payload is the empty string'    "$PRIMARY" ''
deny 'P1c payload is truncated JSON'      "$PRIMARY" '{"tool_name":'
deny 'P1d payload is not JSON at all'     "$PRIMARY" 'not json at all'

# P2 — Boundary 1, second half. In log mode a deny normally becomes a would-deny
# line, but that line requires a session_id an unparseable payload cannot supply.
# Boundary 1 outranks the mode, and no line is written with a fabricated or empty
# session_id. Both halves are asserted: the deny AND the absence of the line.
log_reset
RUN_ENV=(WORKTREE_GUARD_MODE=log)
deny 'P2 unparseable payload denies in log mode too' "$PRIMARY" 'not json at all'
assert_log_empty 'P2 …and writes no line with an empty session_id'

# P3 — Boundary 7. python3 absent. "git status" is a command Arm D ALLOWS, so an
# implementation that skips the lexer it cannot run allows this; the deny is what
# discriminates.
RUN_ENV=(PATH="$(mk_shadow_path nopy python3 python)")
deny 'P3 python3 and python both absent' "$PRIMARY" "$(payload_bash 'git status' s-p3)"

# P4 — Boundary 7. A lexer exits non-zero. Same reasoning as an absent
# interpreter: an unlexable command line is an unknown one. Each lexer is broken
# in turn by pointing the hook at a lib dir holding a stub that exits 1 — the
# suite must not depend on which of the two the guard calls first.
mkdir -p "$TMP/badlib"
cp "$LIB"/*.py "$TMP/badlib/" 2>/dev/null
for script in shell_segments.py classify-git-command.py; do
  cp "$LIB"/*.py "$TMP/badlib/" 2>/dev/null
  printf '#!/usr/bin/env python3\nimport sys\nsys.exit(1)\n' > "$TMP/badlib/$script"
  RUN_ENV=(WORKTREE_GUARD_LIB="$TMP/badlib")
  deny "P4 $script exits non-zero" "$PRIMARY" "$(payload_bash 'git status' s-p4)"
done

# P5 — Boundary 13. HOME carries no usable value. The command is the CORRECT one
# (Arm B2's allow case), so an implementation that lets an empty $HOME expand to
# "" and compares against "/.worktrees/", or that skips a test it cannot perform,
# allows it. Denying is the only answer that does not turn an undefined ~ into a
# grant.
CORRECT_ADD="git worktree add $WT_ROOT/feat-y -b feat/y"
RUN_ENV=(HOME=)
deny 'P5a HOME is the empty string' "$PRIMARY" "$(payload_bash "$CORRECT_ADD" s-p5a)"
# HOME unset needs `env -u`, which the RUN_ENV mechanism cannot express.
n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
( cd "$PRIMARY" && printf '%s' "$(payload_bash "$CORRECT_ADD" s-p5b)" \
  | env -u HOME WORKTREE_GUARD_STATE_DIR="$STATE_DIR" WORKTREE_GUARD_MODE=deny \
      bash "$HOOK" ) >"$out" 2>"$err"
if [ "$?" -eq 2 ] && grep -qF 'worktree-guard:' "$err"; then
  ok 'P5b HOME is unset'
else
  printf 'FAIL — P5b HOME is unset (want exit 2 + prefix)\n  stderr: %s\n' "$(cat "$err")"
  fail=$((fail+1))
fi

# ================================================================= GROUP A ===
# Feature: Arm A — writes are refused from a primary checkout (card :1588)

# A1 — Write at the root of a primary checkout. The message must name the
# centralized root as the place to work instead; a bare "denied" leaves the
# session with nowhere to go.
deny 'A1 write at the root of a primary checkout' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-a1)" \
  ".worktrees/.claude/"

# A2 — Write from a subdirectory. This is the fail-open the naive
# --git-dir/--git-common-dir compare produces: from a subdirectory the bare forms
# differ and the guard reads "linked worktree".
deny 'A2 write from a subdirectory of a primary checkout' "$PRIMARY/hooks" \
  "$(payload_write Write file_path "$PRIMARY/hooks/git-guard.sh" s-a2)"

# A3 — Write inside a linked worktree.
allow_silent 'A3 write inside a linked worktree' "$LINKED" \
  "$(payload_write Write file_path "$LINKED/hooks/git-guard.sh" s-a3)"

# A4 — Scenario Outline: exempt paths are always allowed from a primary
# checkout. The list is the card's "exemption list, stated in full"; the retired
# CODING_MEMORY.md/coding-memory entries stay in because the exemption does.
for p in \
  docs/features/anything.md \
  .claude/settings.local.json \
  settings.json \
  projects/-Users-x--claude/memory/a.md \
  rules/gates.md \
  skills/treko/SKILL.md \
  CODING_MEMORY.md \
  coding-memory/compliance-judge/verdicts.jsonl
do
  mkdir -p "$PRIMARY/$(dirname "$p")"
  allow_silent "A4 exempt path $p" "$PRIMARY" \
    "$(payload_write Write file_path "$PRIMARY/$p" s-a4)"
done

# A5 — A path outside any git repository (boundary 5).
mkdir -p "$TMP/notarepo"
allow_silent 'A5 path outside any git repository' "$TMP/notarepo" \
  "$(payload_write Write file_path "$TMP/notarepo/notes.md" s-a5)"

# A6 — Detached HEAD in a primary checkout. Detachment does not make a primary
# checkout safe to share.
git_q -C "$PRIMARY" checkout -q --detach >/dev/null 2>&1
deny 'A6 detached HEAD in a primary checkout' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-a6)"
git_q -C "$PRIMARY" checkout -q main >/dev/null 2>&1 \
  || git_q -C "$PRIMARY" checkout -q master >/dev/null 2>&1

# A7 — Bare repository (boundary 5a). The Given is the measured behaviour, not a
# restatement of the verdict: task 2a recorded rc=128 with
# "fatal: this operation must be run in a work tree", at the bare directory and
# in a subdirectory of it. An implementation reading that as a generic validation
# failure denies here — which is what the recipe did before 2026-08-26.
BARE="$TMP/repos/bare.git"
git_q init -q --bare "$BARE"
allow_silent 'A7a bare repository, at its root' "$BARE" \
  "$(payload_write Write file_path "$BARE/config" s-a7a)"
mkdir -p "$BARE/objects"
allow_silent 'A7b bare repository, in a subdirectory' "$BARE/objects" \
  "$(payload_write Write file_path "$BARE/objects/info/x" s-a7b)"

# A8 — A linked worktree checked out FROM a bare repository. NOT the bare case,
# and the suite must keep them apart: measured in task 2a, --show-toplevel
# succeeds, --git-dir is <bare>/worktrees/<n> and --git-common-dir is <bare>, so
# this reaches the linked-worktree allow by a different route. An implementation
# short-circuiting on "the common dir is bare" would allow both while having
# stopped judging this one.
git_q -C "$PRIMARY" push -q "$BARE" HEAD:refs/heads/main >/dev/null 2>&1
BAREWT="$TMP/repos/bare-wt"
git_q -C "$BARE" worktree add -q "$BAREWT" main >/dev/null 2>&1
allow_silent 'A8 linked worktree checked out from a bare repository' "$BAREWT" \
  "$(payload_write Write file_path "$BAREWT/file.txt" s-a8)"

# A9 — Submodule. Measured in task 2a: --show-superproject-working-tree printed
# the superproject path from the submodule root and from a subdirectory of it,
# and printed EMPTY for a primary checkout, a linked worktree and the
# superproject itself. The submodule's --git-dir and --git-common-dir were both
# <super>/.git/modules/<n>, i.e. EQUAL — which is why omitting this step denies
# every submodule as a primary checkout.
SUPER="$TMP/repos/super"
mk_repo "$SUPER"
git_q -C "$SUPER" -c protocol.file.allow=always submodule add -q "$PRIMARY" mod >/dev/null 2>&1
git_q -C "$SUPER" commit -q -m sub >/dev/null 2>&1
mkdir -p "$SUPER/mod/sub"
allow_silent 'A9a submodule, at its root' "$SUPER/mod" \
  "$(payload_write Write file_path "$SUPER/mod/hooks/git-guard.sh" s-a9a)"
allow_silent 'A9b submodule, in a subdirectory' "$SUPER/mod/sub" \
  "$(payload_write Write file_path "$SUPER/mod/sub/x.txt" s-a9b)"

# A10 — git is not installed (boundary 3). Precedent: test-marker-guard's
# MSG_NO_PYTHON blocks everywhere.
RUN_ENV=(PATH="$(mk_shadow_path nogit git)")
deny 'A10 git absent from PATH' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-a10)" \
  "could not verify the checkout"

# A11 — git predates --path-format (boundary 4). No git this old exists on this
# machine, so the version is stubbed; the message must name the floor.
RUN_ENV=(PATH="$(mk_git_stub)" STUB_VERSION="git version 2.30.0")
deny 'A11 git 2.30.0 is below the floor' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-a11)" \
  "2.31"

# A12 — git --version output cannot be parsed (boundary 4, the "or unparseable"
# half). The target denies under Arm A anyway, so only naming the floor proves
# the version check ran and reached the right conclusion.
RUN_ENV=(PATH="$(mk_git_stub)" STUB_VERSION="git version (unknown)")
deny 'A12 git --version output cannot be parsed' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-a12)" \
  "2.31"

# A13 — rev-parse errors after the repo is established (boundary 6).
RUN_ENV=(PATH="$(mk_git_stub)" STUB_FAIL_PROBE="--git-dir")
deny 'A13 --git-dir exits non-zero after the repo is established' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-a13)"

# A14 — Scenario Outline: the payload carries no write target (boundary 2). The
# cwd is a primary checkout ON PURPOSE: an implementation that falls back to the
# session cwd when the payload carries no path denies here, and that fallback is
# the bug class phase-guard.sh records in its own Step 4 comment.
log_reset
for tool in Edit Write NotebookEdit; do
  allow_silent "A14 $tool with no path in the payload" "$PRIMARY" "$(payload_nopath "$tool")"
done
assert_log_empty 'A14 …and nothing is appended to the log'

# A15 — rev-parse fails with a diagnostic step 4 recognizes neither way. The
# message must quote the text it actually read: step 4 discriminates on two
# English sentences from git, so an upstream wording change lands in this
# deny-everything branch, and a deny that does not name what it read is
# indistinguishable from every other deny.
RUN_ENV=(PATH="$(mk_git_stub)" STUB_TOPLEVEL_RC=128 \
         STUB_TOPLEVEL_MSG="fatal: detected dubious ownership")
deny 'A15 unrecognized rev-parse diagnostic denies and quotes it' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-a15)" \
  "detected dubious ownership"

# A16 — A rev-parse probe exits 0 but prints nothing (boundary 6, "or empty
# output"). The target is a LINKED worktree precisely so a swallowed empty read
# produces an ALLOW and a correct implementation produces a DENY; against a
# primary-checkout target both answers are "deny" and the case proves nothing.
RUN_ENV=(PATH="$(mk_git_stub)" STUB_EMPTY_PROBE="--git-common-dir")
deny 'A16 --git-common-dir exits 0 printing nothing' "$LINKED" \
  "$(payload_write Write file_path "$LINKED/hooks/git-guard.sh" s-a16)"

# A17 — The submodule probe exits non-zero (boundary 6). It runs BEFORE the
# primary-vs-linked compare, so a swallowed failure here lands on the
# linked-worktree allow rather than on any error path. --is-bare-repository is
# GONE from this case, not merely unlisted: task 2a removed that probe from the
# recipe, so a case asserting its failure would assert against a command the
# guard never issues.
RUN_ENV=(PATH="$(mk_git_stub)" STUB_FAIL_PROBE="--show-superproject-working-tree")
deny 'A17 the submodule probe exits non-zero' "$LINKED" \
  "$(payload_write Write file_path "$LINKED/hooks/git-guard.sh" s-a17)"


# ================================================================= GROUP B ===
# Feature: Arm B2 — hand-rolled git worktree add (card :1754)

# Fixtures this group needs beyond GROUP P's. OTHER is a second repository with
# its OWN centralized root and .repo-root marker: every "-C / cd redirects
# somewhere else" scenario needs two namespaces that are both individually valid,
# so a deny can only come from binding the redirect to the right segment.
OTHER="$TMP/repos/other"
mk_repo "$OTHER"
mk_linked "$OTHER" "seed"
OTHER_WT_ROOT="$HOME_FIX/.worktrees/other"

# B1 — Scenario: Add to the centralized root. The allow that keeps the guard
# usable; if this denies, the sanctioned way to make a worktree by hand is gone.
allow_silent 'B1 add to the centralized root' "$PRIMARY" \
  "$(payload_bash "git worktree add $WT_ROOT/feat-y -b feat/y" s-b1)"

# B2 — Scenario: Add anywhere else. The message must name the centralized root as
# the correct parent; a bare "denied" leaves the session with nowhere to put it.
deny 'B2 add anywhere else' "$PRIMARY" \
  "$(payload_bash 'git worktree add ../scratch-tree' s-b2)" \
  ".worktrees/.claude/"

# B3 — Scenario: Add chained behind another command. shell_segments.py binds the
# operand to its own segment; an implementation that only inspects the first
# command on the line allows this. /tmp is the card's literal cd target.
deny 'B3 add chained behind another command' "$PRIMARY" \
  "$(payload_bash 'cd /tmp && git worktree add ../scratch-tree' s-b3)"

# B4 — Scenario: -C names a resolvable repository, and the path is correct for
# it. 215 uses of `git -C` exist across this repo's own scripts, so a blanket
# deny on -C is unusable; the redirect must be resolved, not refused.
allow_silent 'B4 -C resolves and the path is correct for that repo' "$PRIMARY" \
  "$(payload_bash "git -C $OTHER worktree add $OTHER_WT_ROOT/feat-a" s-b4)"

# B5 — Scenario: -C names an unresolvable directory (boundary 12). The guard
# cannot tell which repository it is protecting, so it fails closed — and names
# both the operand and the segment index, or the deny is unactionable.
deny 'B5 -C names an unresolvable directory' "$PRIMARY" \
  "$(payload_bash "git -C /no/such/dir worktree add $WT_ROOT/feat-a" s-b5)" \
  "/no/such/dir"
if grep -qF 'segment 0' "$err"; then
  ok 'B5 …and the message names segment 0'
else
  printf 'FAIL — B5 …and the message names segment 0\n  stderr: %s\n' "$(cat "$err")"
  fail=$((fail+1))
fi

# B6 — Scenario: -C redirects to another repo but the path looks right for this
# one. The discriminating case: the path PASSES if judged against the session's
# repo, so only binding the -C directory to the SAME segment index as the path
# reaches the right verdict — and the message must name the other repo's root.
deny 'B6 -C redirects but the path suits the session repo' "$PRIMARY" \
  "$(payload_bash "git -C $OTHER worktree add $WT_ROOT/feat-a" s-b6)" \
  ".worktrees/other/"

# B7 — Scenario: cd redirects to another repo but the path looks right for this
# one. Round 4's blocking finding: identical in kind to B6, reached through cd.
# Arm B2 had no cwd-resolution step at all and allowed this.
deny 'B7 cd redirects but the path suits the session repo' "$PRIMARY" \
  "$(payload_bash "cd $OTHER && git worktree add $WT_ROOT/feat-a" s-b7)" \
  ".worktrees/other/"

# B8 — Scenario: -C in an earlier segment does not carry to a later one. Round
# 4's advisory finding: a flat GIT_DIR_OPT fact let segment 0's redirect excuse
# segment 1's switch — the incident this whole feature exists to stop. Segment
# 1's effective repo is the session cwd, a primary checkout, so this denies.
deny 'B8 -C on segment 0 does not carry to segment 1' "$PRIMARY" \
  "$(payload_bash "git -C $OTHER log && git switch main" s-b8)"

# B9 — Scenario: Two adds on one line, only one of them wrong. Indexed facts are
# judged per segment, so the deny must name the segment that earned it. Naming
# segment 0 would mean the guard cannot tell which add it refused.
deny 'B9 two adds on one line, only the second wrong' "$PRIMARY" \
  "$(payload_bash "git worktree add $WT_ROOT/a && git -C /no/such/dir worktree add $WT_ROOT/b" s-b9)" \
  "segment 1"
assert_last_stderr_lacks 'B9 …and does not name segment 0' 'segment 0'

# B10 — Scenario: A cd whose operand cannot be resolved (boundary 12). The
# classifier emits SEG_CD<tab>0<tab>UNRESOLVABLE; the deny must still name the
# operand the reader can see on their command line, and its segment.
deny 'B10 a cd whose operand cannot be resolved' "$PRIMARY" \
  "$(payload_bash 'cd "$d" && git worktree add '"$WT_ROOT"'/feat-a' s-b10)" \
  '$d'
if grep -qF 'segment 0' "$err"; then
  ok 'B10 …and the message names segment 0'
else
  printf 'FAIL — B10 …and the message names segment 0\n  stderr: %s\n' "$(cat "$err")"
  fail=$((fail+1))
fi

# B11 — Scenario: The command line cannot be lexed at all. Measured 2026-08-24:
# this input makes segments() return [] on exit 0, so boundary 7 never fires and
# the empty fact set reads as "no worktree add here". SEG_UNPARSED overrides
# shell_segments.py's deliberate fail-open — an absent fact is not safety.
deny 'B11 the command line cannot be lexed at all' "$PRIMARY" \
  "$(payload_bash 'git worktree add "unclosed' s-b11)"

# B12 — Scenario: The path operand follows an option value. -b takes a value, so
# an implementation reading "first non-option token" takes feat/z as the path and
# denies a correctly-placed worktree.
allow_silent 'B12 the path operand follows an option value' "$PRIMARY" \
  "$(payload_bash "git worktree add -b feat/z $WT_ROOT/feat-z" s-b12)"

# B13 — Scenario: Basename collision (boundary 14, the "disagrees" half). Two
# repos named api in different orgs would share ~/.worktrees/api/. The marker is
# written pointing at org-a while the session sits in org-b, so the only thing
# separating them is the compare — and the refusal must name both roots.
ORG_A="$TMP/repos/org-a/api"
ORG_B="$TMP/repos/org-b/api"
mk_repo "$ORG_A"
mk_repo "$ORG_B"
mkdir -p "$HOME_FIX/.worktrees/api"
printf '%s\n' "$ORG_A" > "$HOME_FIX/.worktrees/api/.repo-root"
deny 'B13 basename collision between two repos named api' "$ORG_B" \
  "$(payload_bash "git worktree add $HOME_FIX/.worktrees/api/feat-q" s-b13)" \
  "$ORG_A"
if grep -qF -- "$ORG_B" "$err"; then
  ok 'B13 …and the message names the current repo root too'
else
  printf 'FAIL — B13 …and the message names the current repo root too\n  stderr: %s\n' \
    "$(cat "$err")"
  fail=$((fail+1))
fi

# B14 — Scenario: A relative path operand that resolves under the centralized
# root (boundary 11). "Resolve to an absolute real path first" is the whole rule;
# an implementation that string-matches the raw operand against ~/.worktrees/
# denies a correctly-placed worktree. The only relative operand here that ALLOWS.
allow_silent 'B14 a relative operand resolving under the centralized root' "$LINKED" \
  "$(payload_bash 'git worktree add ../feat-y -b feat/y' s-b14)"

# B15 — Scenario: A symlinked path operand (boundary 11). The raw operand sits
# under the centralized root and passes any string test; only the resolved REAL
# path shows the worktree landing outside it. The link target is built explicitly
# so the escape is real and not merely asserted.
mkdir -p "$TMP/elsewhere"
ln -s "$TMP/elsewhere" "$WT_ROOT/feat-link"
deny 'B15 a symlinked path operand escapes the centralized root' "$PRIMARY" \
  "$(payload_bash "git worktree add $WT_ROOT/feat-link/feat-y" s-b15)" \
  ".worktrees/.claude/"

# B16 — Scenario: A path operand that cannot be resolved (boundary 11). Distinct
# from B10's unresolvable cd operand: the path operand has its own resolution
# step, so an implementation that resolves the cwd correctly can still take an
# unvouchable path. The message must name the operand.
deny 'B16 a path operand that cannot be resolved' "$PRIMARY" \
  "$(payload_bash 'git worktree add $SOME_VAR/feat-y' s-b16)" \
  '$SOME_VAR'

# B17 — Scenario: The .repo-root marker cannot be read (boundary 14, the "cannot
# be read" half). An unreadable marker is an UNDETERMINED collision, not an
# absent one; reading a failed read as "no marker yet" is exactly how two repos
# come to share one directory silently. Note: chmod 000 does not block a process
# running as root, so this case only discriminates for an unprivileged runner.
chmod 000 "$WT_ROOT/.repo-root"
deny 'B17 the .repo-root marker cannot be read' "$PRIMARY" \
  "$(payload_bash "git worktree add $WT_ROOT/feat-q" s-b17)"
chmod 644 "$WT_ROOT/.repo-root"
# ================================================================= GROUP D ===
# Feature: Arm D — moving a primary checkout's HEAD (card :1893)

# Fixtures shared by this group. $OTHER is a real directory that is NOT a git
# repo: every scenario below that mentions another location denies for a lexing
# reason (SEG_OPAQUE / SEG_GROUPED / SEG_SCOPE_OPT), never because the operand
# could not be resolved (boundary 12, card :1331). Making it exist keeps those
# two denials from being confusable — a missing directory would let a guard that
# does nothing but resolve operands pass most of this group.
OTHER="$TMP/other"
mkdir -p "$OTHER"
# The card writes `--git-dir=/tmp/o/.git`. The VALUE is never read — measured,
# SEG_SCOPE_OPT carries the option name only (card :879-883) — so this path is
# deliberately left nonexistent; if a case ever passes because of it, the guard
# resolved something the design says it cannot see.
OTHER_GIT="$TMP/o/.git"

# ---- Scenario Outline: HEAD-moving commands are denied (card :1895) ----------
# Given the session cwd is a primary checkout. One case per Examples row, D1–D18
# in card order. Every row moves the primary's HEAD out from under whichever
# other session shares this checkout — the incident this arm exists for.

DN=0

# D1–D5 — the `switch` family. All five spellings, including `-` and `--detach`,
# because a classifier keyed on "the operand looks like a branch name" allows
# `git switch -` and `git switch --detach HEAD` while still moving HEAD.
for c in \
  'git switch main' \
  'git switch -c feat/x' \
  'git switch -' \
  'git switch --detach HEAD' \
  'git switch --orphan feat/x'
do
  DN=$((DN+1))
  deny "D$DN deny: $c" "$PRIMARY" "$(payload_bash "$c" "s-d$DN")"
done

# D6–D9 — the `checkout` family. Kept separate from the switch family on
# purpose: `git checkout` is the one subcommand that is BOTH a HEAD move and a
# path restore, so the guard must discriminate on the operand shape rather than
# on the subcommand name. D19–D22 below are the other half of that pair.
for c in \
  'git checkout main' \
  'git checkout -b feat/x' \
  'git checkout -' \
  'git checkout --detach'
do
  DN=$((DN+1))
  deny "D$DN deny: $c" "$PRIMARY" "$(payload_bash "$c" "s-d$DN")"
done

# D10–D12 — integrate-and-advance. `git merge --ff-only main` is the command in
# this repo's own logged incident (card :1919, session-state.md:85) and the first
# version of this arm did not cover it: a rule listing only switch/checkout
# allows every one of these three.
for c in \
  'git merge --ff-only main' \
  'git pull' \
  'git rebase main'
do
  DN=$((DN+1))
  deny "D$DN deny: $c" "$PRIMARY" "$(payload_bash "$c" "s-d$DN")"
done

# D13–D14 — reset. BOTH --hard and --soft, because --soft is the one that looks
# harmless: it leaves the worktree alone and still moves the shared HEAD, which
# is the whole of what this arm protects. D23 pins the pathspec form as an allow.
for c in \
  'git reset --hard HEAD~1' \
  'git reset --soft HEAD~1'
do
  DN=$((DN+1))
  deny "D$DN deny: $c" "$PRIMARY" "$(payload_bash "$c" "s-d$DN")"
done

# D15–D16 — replay onto HEAD. Neither names a branch, so a guard that looks for
# a branch-shaped operand sees nothing to object to and lets both through.
for c in \
  'git cherry-pick abc1234' \
  'git revert abc1234'
do
  DN=$((DN+1))
  deny "D$DN deny: $c" "$PRIMARY" "$(payload_bash "$c" "s-d$DN")"
done

# D17–D18 — stash restore. The subcommand is `stash`, not a ref-moving verb, so
# these are the rows that fail a rule written over subcommand names alone; both
# write the worktree and the index of a checkout someone else is using.
for c in \
  'git stash pop' \
  'git stash apply'
do
  DN=$((DN+1))
  deny "D$DN deny: $c" "$PRIMARY" "$(payload_bash "$c" "s-d$DN")"
done

# ---- Scenario Outline: named-path commands are allowed (card :1922) ----------
# D19–D25. Run from the PRIMARY checkout deliberately: inside a linked worktree
# every one of these allows regardless, so only the primary discriminates a
# guard that judges the subcommand from one that judges what it touches. This is
# the false-deny half of the checkout/reset pairs above — over-deny here and the
# only way to edit a tracked file in the primary checkout is to disable the hook.
for c in \
  'git checkout -- docs/a.md' \
  'git checkout main -- docs/a.md' \
  'git restore docs/a.md' \
  'git restore --staged docs/a.md' \
  'git reset -- docs/a.md' \
  'git status' \
  'git log --oneline'
do
  DN=$((DN+1))
  allow_silent "D$DN allow: $c" "$PRIMARY" "$(payload_bash "$c" "s-d$DN")"
done

# D26 — Scenario: an unrecognized git subcommand passes layer 1 (card :1935).
# Layer 1's under-block is deliberate (Non-goals): denying every subcommand the
# classifier has not been taught makes the guard unusable. `git bisect start`
# DOES move HEAD; it is refused by layer 2's lock rule instead.
# NOT EXPRESSIBLE HERE: the scenario's second half ("layer 2 denies with
# rc=128") needs a repo with hooks/reference-transaction armed and a real git
# invocation. This harness feeds PreToolUse JSON to layer 1 only, so that half
# belongs to the Arm D layer-2 group (card :2174).
allow_silent 'D26 layer 1 allows an unrecognized subcommand (git bisect start)' \
  "$PRIMARY" "$(payload_bash 'git bisect start' s-d26)"

# D27 — Scenario: an unrecognized subcommand that moves no ref (card :1949). The
# companion to D26 and the reason layer 1 is not a blanket subcommand deny: this
# one writes no HEAD transaction, so neither layer sees it and it is correctly
# untouched. Without this case, "deny every unknown subcommand" passes D26.
allow_silent 'D27 layer 1 allows git bisect log' \
  "$PRIMARY" "$(payload_bash 'git bisect log' s-d27)"

# D28 — Scenario: switching inside a linked worktree (card :1959). A linked
# worktree's HEAD is its own; nobody else shares it. This is the case that fails
# if the arm is implemented as "deny git switch everywhere".
allow_silent 'D28 git switch main inside a linked worktree' \
  "$LINKED" "$(payload_bash 'git switch main' s-d28)"

# D29 — Scenario: cd into the primary checkout first (card :1965). Arm D resolves
# the EFFECTIVE cwd; reading only the payload's cwd leaves this route open, which
# is the same incident by a narrower path. The card writes `cd ~/.claude`; the
# fixture primary is $PRIMARY, written absolute so the case tests cd resolution
# and not tilde expansion (a separate concern, and shlex keeps `~` literal).
deny 'D29 cd into the primary checkout, then git switch' "$LINKED" \
  "$(payload_bash "cd $PRIMARY && git switch main" s-d29)"

# D30 — Scenario: cd to an operand that cannot be resolved (card :1972,
# boundary 11/12). Single-quoted so the literal `$SOME_VAR` reaches the payload —
# the guard must never expand it. The message names the operand, because a deny
# that does not say which operand it could not resolve is unactionable.
deny 'D30 cd to an unresolvable operand' "$PRIMARY" \
  "$(payload_bash 'cd $SOME_VAR && git switch main' s-d30)" \
  '$SOME_VAR'

# D31 — Scenario: a repo-redirecting global option other than -C (card :1980).
# SEG_SCOPE_OPT. The option's VALUE never reaches the fact stream — measured, the
# attached and separate spellings emit byte-identical output (card :879-883) — so
# this class denies rather than joining the cd/-C resolution path.
# D31b re-runs the same payload for the segment-index half of the Then line;
# `deny` takes one required substring, and dropping either half would let a
# message that names only one of the two pass.
GITDIR_CMD="git --git-dir=$OTHER_GIT --work-tree=$TMP/o switch main"
deny 'D31 --git-dir/--work-tree redirect denies, naming the option' "$PRIMARY" \
  "$(payload_bash "$GITDIR_CMD" s-d31)" '--git-dir'
deny 'D31b …and names segment 0' "$PRIMARY" \
  "$(payload_bash "$GITDIR_CMD" s-d31b)" 'segment 0'

# Scenario: every other member of GLOBAL_REDIRECT behaves the same way
# (card :1989) — asserted at the end of this group as D-GR, by importing the
# tuple at run time. It is NOT a copy of the list; see the D-GR block.

# D32 — Scenario: an unrecognized global option (card :1996). Bucket 3.
# resolve_subcommand returns the identical shape for an unknown option as for a
# known redirector (classify-git-command.py:171-173), so no new rule is needed —
# and an option git adds tomorrow lands in "cannot tell", never in "allow".
deny 'D32 an unrecognized global option denies, naming it' "$PRIMARY" \
  "$(payload_bash 'git --super-prefix=x switch main' s-d32)" '--super-prefix'

# D33 — Scenario: a GIT_ environment assignment redirects the repository
# (card :2006). Measured: today this emits exactly COMMIT, byte-identical to a
# purely local commit — the assignment sits in the assignments dict and is
# discarded (card :885-893). D33b covers the segment-index half of the Then.
ENVDIR_CMD="GIT_DIR=$OTHER_GIT git commit -m x"
deny 'D33 GIT_DIR= assignment denies, naming the variable' "$PRIMARY" \
  "$(payload_bash "$ENVDIR_CMD" s-d33)" 'GIT_DIR'
deny 'D33b …and names segment 0' "$PRIMARY" \
  "$(payload_bash "$ENVDIR_CMD" s-d33b)" 'segment 0'

# D34 — Scenario: a non-git environment assignment is not a redirect
# (card :2014). The rule is a GIT_ prefix test over the assignments dict, not an
# enumeration, so an unrelated assignment must be untouched. Run from the LINKED
# worktree exactly as the Given says: from the primary the switch denies on its
# own and the case would pass without the prefix test existing.
allow_silent 'D34 FOO=bar is not a GIT_ redirect' "$LINKED" \
  "$(payload_bash 'FOO=bar git switch main' s-d34)"

# D35 — Scenario: a wrapper hides git behind the command position (card :2022).
# SEG_OPAQUE, clause 3a. Measured: this emits NO fact at all today, and `env -C`
# works on this host (card :921), so it is a live HEAD move against another repo
# that is wholly invisible. WRAPPERS is a documented denylist
# (shell_segments.py:62-63) and `env` is not in it. D35b: the segment-index half.
ENVC_CMD="env -C $OTHER git switch main"
deny 'D35 env -C hides git behind argv[0], naming the token' "$PRIMARY" \
  "$(payload_bash "$ENVC_CMD" s-d35)" 'git'
deny 'D35b …and names segment 0' "$PRIMARY" \
  "$(payload_bash "$ENVC_CMD" s-d35b)" 'segment 0'

# D36 — Scenario: a shell keyword holds the command position (card :2031). Same
# clause-3a rule, no new clause: `if`/`then` take argv[0] and git sits at
# argv[1]. This is the case that fails if 3a is implemented as a wrapper-word
# list instead of an argv[0]-is-neither-git-nor-cd test.
deny 'D36 if cd …; then git commit …; fi' "$PRIMARY" \
  "$(payload_bash "if cd $OTHER; then git commit -m x; fi" s-d36)"

# D37 — Scenario: a command that only mentions git — the accepted false denial
# (card :2037). STATED, NOT DISCOVERED. Denying a command that merely mentions
# git is the price of not enumerating shell keywords; WORKTREE_EXEMPT (D50)
# clears it. If this ever flips to allow, clause 3a has been narrowed and D35/D36
# should have failed with it.
deny 'D37 echo git switch main — the accepted false denial' "$PRIMARY" \
  "$(payload_bash 'echo git switch main' s-d37)" 'git'

# D38 — Scenario: a git command hidden inside a quoted shell string (card :2050).
# Clause 3b. Measured 2026-08-25: segments() returns ['sh','-c','git switch
# main'] — the git call survives lexing as ONE token, so clause 3a cannot see it
# and every rule above allows it. D38b: the segment-index half of the Then.
deny 'D38 sh -c quoted git switch, naming the collapsed token' "$PRIMARY" \
  "$(payload_bash "sh -c 'git switch main'" s-d38)" 'git switch main'
deny 'D38b …and names segment 0' "$PRIMARY" \
  "$(payload_bash "sh -c 'git switch main'" s-d38b)" 'segment 0'

# D39 — Scenario: eval leaves the whole command as argv[0] (card :2058).
# WRAPPERS strips `eval`, leaving argv == ['git switch main'] — a single
# collapsed token IN command position. No special case: clause 3b re-lexes
# argv[0] like any other whitespace-bearing token, which is what this pins.
deny 'D39 eval "git switch main"' "$PRIMARY" \
  "$(payload_bash 'eval "git switch main"' s-d39)"

# D40 — Scenario: a shell the rule never names (card :2066).
# THE REGRESSION CANARY. Clause 3b contains no shell name, no `-c` and no wrapper
# word — it tests whether a re-lexed token reaches command position. If this case
# ever needs `zsh` added to a list to pass, the rule has been rewritten as the
# sixth hand-list and the change must be rejected.
deny 'D40 zsh -c quoted git switch — the regression canary' "$PRIMARY" \
  "$(payload_bash "zsh -c 'git switch main'" s-d40)"

# D41 — Scenario: a cd inside a quoted shell string (card :2075). The inner lex
# yields two segments and the FIRST holds cd in command position, so this fails
# an implementation of 3b that re-lexes looking only for git.
deny 'D41 sh -c quoted cd && git switch' "$PRIMARY" \
  "$(payload_bash "sh -c 'cd $OTHER && git switch main'" s-d41)"

# ---- clause 3c: the nested constructions, built rather than quoted -----------
# Built with shlex.quote so the nesting is generated, not transcribed: a
# hand-typed four-deep quoting is exactly the fixture most likely to be wrong in
# a way that makes the case pass for another reason.
NEST3_SWITCH="$(python3 -c 'import shlex,sys
cmd = sys.argv[1]
for _ in range(int(sys.argv[2])): cmd = "sh -c " + shlex.quote(cmd)
sys.stdout.write(cmd)' 'git switch main' 3)"
NEST4_SWITCH="$(python3 -c 'import shlex,sys
cmd = sys.argv[1]
for _ in range(int(sys.argv[2])): cmd = "sh -c " + shlex.quote(cmd)
sys.stdout.write(cmd)' 'git switch main' 4)"
NEST4_WTADD="$(python3 -c 'import shlex,sys
cmd = sys.argv[1]
for _ in range(int(sys.argv[2])): cmd = "sh -c " + shlex.quote(cmd)
sys.stdout.write(cmd)' 'git worktree add /wrong/place' 4)"

# PREMISE for D42/D44 (and D-3B-R3/R4). The fixture must not assume the property
# it is built to exercise: this asserts against the LIVE segments() that the
# three-deep form does reach command position within the bound of 3 and the
# four-deep form does not. Without it, a construction that collapsed to nothing
# would make D42/D44 pass as vacuous allows.
if python3 - "$LIB/shell_segments.py" "$NEST3_SWITCH" "$NEST4_SWITCH" "$NEST4_WTADD" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ss", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def depth_of_hit(src, depth=0, bound=3):
    """Lowest re-lex depth at which git/cd reaches argv[0]; 0 if never within bound."""
    for _assigns, argv in m.segments(src):
        if depth and argv and argv[0] in ("git", "cd"):
            return depth
        if depth >= bound:
            continue
        for tok in argv:
            if " " in tok:
                hit = depth_of_hit(tok, depth + 1, bound)
                if hit:
                    return hit
    return 0

three, four, wtadd = sys.argv[2], sys.argv[3], sys.argv[4]
assert depth_of_hit(three) == 3, depth_of_hit(three)
assert depth_of_hit(four) == 0, depth_of_hit(four)
assert depth_of_hit(wtadd) == 0, depth_of_hit(wtadd)
PY
then ok 'D42/D44 premise: 3 levels resolve, 4 levels stay collapsed at the bound'
else bad 'D42/D44 premise: nested fixtures do not straddle the depth bound of 3'
fi

# D42 — Scenario: a collapsed token still collapsed at the depth bound
# (card :2083). ALLOW ON PURPOSE. Clause 3c, relaxed 2026-08-25: three levels
# re-lexed with no git or cd in command position is evidence, not blindness. The
# bound itself is still required — unbounded recursion is a DoS surface on a
# PreToolUse hook — it just no longer denies at the bound.
# NOT EXPRESSIBLE HERE: the "layer 2 denies with rc=128" half needs an armed
# reference-transaction hook; it belongs to the layer-2 group (card :2174).
allow_silent 'D42 git switch nested past the depth bound — layer 1 allows' \
  "$PRIMARY" "$(payload_bash "$NEST4_SWITCH" s-d42)"

# D43 — Scenario: a collapsed token segments() cannot parse (card :2095). The
# half of clause 3c that does NOT relax: here the guard has no view at any depth,
# so an absent fact would read as "nothing here" — the exact failure SEG_UNPARSED
# exists to stop. Arm B2 has no layer-2 backstop (layer 2 allows worktree add by
# design), so this one must keep denying for both arms.
# CONSTRUCTED, not quoted, and the premise is measured immediately below: the
# closing quote matters. WITH it the outer line lexes and only the inner token is
# unparseable (the empty-lex branch this case is for); WITHOUT it the OUTER line
# is unparseable and the case is caught by line-scoped SEG_UNPARSED instead — a
# different rule, passing for the wrong reason (card :2105-2110).
UNPARSED_TOK='git worktree add "unclosed'
UNPARSED_CMD="sh -c '$UNPARSED_TOK'"
if python3 - "$LIB/shell_segments.py" "$UNPARSED_TOK" "$UNPARSED_CMD" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ss", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
inner, outer = sys.argv[2], sys.argv[3]
outer_segs = m.segments(outer)
assert m.segments(inner) == [], m.segments(inner)          # the empty-lex branch
assert len(outer_segs) == 1, outer_segs                     # the OUTER line lexes
assert outer_segs[0][1][-1] == inner, outer_segs            # …and carries the token
PY
then ok 'D43 premise: the outer line lexes, the inner token lexes to []'
else bad 'D43 premise: fixture is not the empty-lex case (outer unparseable?)'
fi
deny 'D43 a collapsed token segments() returns [] for — layer 1 denies' "$PRIMARY" \
  "$(payload_bash "$UNPARSED_CMD" s-d43)" "$UNPARSED_TOK"

# D44 — Scenario: a worktree add nested past the depth bound (card :2112).
# ASSERTS THE GAP ON PURPOSE, like the two Non-goals residuals. Layer 2 judges
# HEAD moves, not worktree locations, so nothing catches this — the one genuinely
# unbackstopped residual the 3c relaxation creates. If a later change makes it
# deny, that is a decision to take deliberately, not a bug fix to land quietly.
allow_silent 'D44 git worktree add nested past the bound — both layers allow' \
  "$PRIMARY" "$(payload_bash "$NEST4_WTADD" s-d44)"

# D45 — Scenario: a PR title that mentions git — must NOT deny (card :2123).
# THE FALSE-DENY GUARD. Clause 3b tests COMMAND POSITION, not presence. The wider
# "git anywhere in the re-lexed tokens" variant was measured on 2026-08-25 and
# falsely denied 4 of 19 real shapes, this one among them — a shape this workflow
# types constantly. Deleting this case is how that regression is re-introduced.
allow_silent 'D45 gh pr create with git in the title' "$PRIMARY" \
  "$(payload_bash 'gh pr create --title "fix git guard" --body "closes the hole"' s-d45)"

# D46 — Scenario: a git call inside a script file — a stated residual, ALLOWED
# (card :2133). NOT A DEFECT. The hook gets the command text, never the file's
# contents; there is no token to re-lex. The script is created here and really
# does contain a HEAD move, so the case asserts the actual gap rather than an
# empty one.
printf '#!/bin/sh\ngit switch main\n' > "$PRIMARY/myscript.sh"
chmod +x "$PRIMARY/myscript.sh"
allow_silent 'D46 ./myscript.sh — stated residual, allowed on purpose' "$PRIMARY" \
  "$(payload_bash './myscript.sh' s-d46)"

# D47 — Scenario: a git call built inside an interpreter string — a stated
# residual, ALLOWED (card :2141). Measured 2026-08-25: re-lexes to argv[0] ==
# "import", so command position is not git and the rule correctly does not fire.
# Closing this means parsing arbitrary languages, which is not lexing.
allow_silent 'D47 python3 -c building a git call — stated residual, allowed' \
  "$PRIMARY" \
  "$(payload_bash "python3 -c 'import subprocess; subprocess.run([\"git\",\"log\"])'" s-d47)"

# D48 — Scenario: a cd inside a subshell — the accepted over-denial (card :2151).
# SEG_GROUPED. Bash discards this cd at the ')', so the switch really does act on
# the session repo and refusing it is over-strict — stated so it is not later read
# as a defect. The required substring is "(": segments() throws the operator away
# (shell_segments.py:139-140), so the only place the guard can name it from is the
# raw line, and a message that names the grouping operator contains it either way.
deny 'D48 cd inside a subshell — accepted over-denial, names the operator' \
  "$PRIMARY" "$(payload_bash "( cd $OTHER && git log ) && git switch main" s-d48)" '('

# D49 — Scenario: a cd inside a brace group (card :2161). The same fact set as
# D48 and here the cd genuinely DOES persist past `}`. One rule covers both
# because nothing in the return value can separate them — which is precisely why
# both cases must exist: a guard that "fixed" the D48 over-denial by special-
# casing parens fails here.
deny 'D49 cd inside a brace group' "$PRIMARY" \
  "$(payload_bash "{ cd $OTHER; git log; } && git switch main" s-d49)"

# D50 — Scenario: the documented bypass (card :2168). ALLOW ON PURPOSE, and the
# only escape hatch for D37's accepted false denial. The log line is the half
# that matters: task 10's arm-it decision is computed from this log, so a bypass
# that leaves no trace is indistinguishable from the guard never having fired.
# The Then line's "arm=D decision=bypass exempt-reason=hotfix" is prose for the
# TAB-SEPARATED fields specified at card :1485
#   <iso8601> <session_id> <arm> <mode> <decision> <repo-root> <path-or-command> [<exempt-reason>]
# so the assertions pin that format, not the Gherkin wording — mode is `deny`
# here because that is the runner's default.
log_reset
allow_silent 'D50 WORKTREE_EXEMPT=hotfix git switch main is allowed' "$PRIMARY" \
  "$(payload_bash 'WORKTREE_EXEMPT=hotfix git switch main' s-d50)"
assert_log_count 'D50 …and appends exactly one line' 1
assert_log_has 'D50 …with arm D, mode deny, decision bypass' "$(printf '\tD\tdeny\tbypass\t')"
assert_log_has 'D50 …and the exempt reason' "$(printf '\thotfix')"
assert_log_has 'D50 …and the session id' 's-d50'

# ------------------------------------------------- task 3(a): GLOBAL_REDIRECT ---
# Card :1989 and :1245-1248. The tuple is READ AT RUN TIME from the real
# classify-git-command.py — never copied here — so a member added upstream
# without revisiting derivation 1 fails this suite instead of failing open. The
# filename carries a hyphen, so importlib.util.spec_from_file_location is the
# only import form available.
GR_MEMBERS="$(python3 - "$LIB/classify-git-command.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cgc", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sys.stdout.write(" ".join(mod.GLOBAL_REDIRECT))
PY
)"

# D-GR — the premise, asserted before the loop. A failed import returns the empty
# string, the loop below then runs zero times, and a group of ten assertions
# vanishes without a single FAIL line. This is the assertion that cannot go
# silent: it demands a plural tuple that really contains -C.
GR_COUNT=0
for opt in $GR_MEMBERS; do GR_COUNT=$((GR_COUNT+1)); done
if [ "$GR_COUNT" -ge 2 ] && printf '%s\n' $GR_MEMBERS | grep -qxF -- '-C'; then
  ok "D-GR imported GLOBAL_REDIRECT at run time ($GR_COUNT members)"
else
  bad "D-GR could not import GLOBAL_REDIRECT (got: '$GR_MEMBERS')"
fi

# D-GR1..n — every member EXCEPT -C denies, naming the option. -C is the single
# member the guard resolves (via SEG_GIT_C) instead of refusing; every other
# non-None blocking_option is SEG_SCOPE_OPT (card :870-877). The command is a
# HEAD move so the case stays about the option, not about the subcommand.
# The bare `git <option> switch main` spelling is used for every member — the
# card's own wording at :1991 — because attaching a plausible VALUE per member
# would be a hand-written table, the exact thing this case exists to avoid.
# resolve_subcommand splits on "=" before the lookup (classify-git-command.py:164),
# so the attached and bare spellings reach the identical branch.
GRN=0
for opt in $GR_MEMBERS; do
  [ "$opt" = "-C" ] && continue
  GRN=$((GRN+1))
  deny "D-GR$GRN git $opt switch main denies" "$PRIMARY" \
    "$(payload_bash "git $opt switch main" "s-dgr$GRN")" "$opt"
done

# --------------------------------------- task 3(b): the measured shape table ---
# Card :917-924. Each of these four emits NO FACT AT ALL today because
# argv[0] != "git"; the table is the measurement and these cases pin it. They
# overlap D35/D36 and the 3b carryovers below on purpose — this block is indexed
# to the table so a row deleted upstream leaves a visibly unpinned shape.

# D-SH1 — `env -C` — a live HEAD move against another repo, wholly invisible.
deny 'D-SH1 env -C <dir> git switch main' "$PRIMARY" \
  "$(payload_bash "env -C $OTHER git switch main" s-dsh1)"

# D-SH2 — `env GIT_DIR=…` — defeats derivation 2 as well: the assignment sits
# BEHIND env, so it is an ordinary argv token, not an assignments entry. A guard
# implementing only the GIT_ prefix test over the dict allows this one.
deny 'D-SH2 env GIT_DIR=… git commit -m x' "$PRIMARY" \
  "$(payload_bash "env GIT_DIR=$OTHER_GIT git commit -m x" s-dsh2)"

# D-SH3 — `if`/`then` hold the command position; git sits at argv[1].
deny 'D-SH3 if cd …; then git commit -m x; fi' "$PRIMARY" \
  "$(payload_bash "if cd $OTHER; then git commit -m x; fi" s-dsh3)"

# D-SH4 — `timeout` — named in the WRAPPERS denylist comment as knowingly open
# (shell_segments.py:62-63) and left open there by ADR 0012. This guard is the
# last line of defence, so it may not inherit that trade-off.
deny 'D-SH4 timeout 5 git commit -m x' "$PRIMARY" \
  "$(payload_bash 'timeout 5 git commit -m x' s-dsh4)"

# ------------------------------------------------ task 3(c): clause 3b groups ---
# Card :3101-3136. Three groups, all three required. Every command was measured
# against the live segments() on 2026-08-25; these cases pin the measurement,
# they do not restate the prose. The must-deny list is 10 = 6 shared shapes + 3
# round-5 carryovers + 1 abstract case no literal command can stand for.
# The strings are quoted VERBATIM from the measurement, `/tmp/other` included, so
# they are byte-comparable with the card. That path is not a fixture and need not
# exist: these deny under clause 3a/3b, which never resolves the operand. The
# resolvable-operand versions of the same three shapes are D35/D36/D-SH1/D-SH3,
# so a guard that denied only because the directory was missing still fails there.

# D-3B-D1..D6 — the 6 shared shapes. `bash -c` and `sh -c` differ only in the
# quoting of the collapsed token, which is the point: both survive lexing as ONE
# token, so clause 3a is blind to both. D-3B-D6 is nested two deep and must be
# caught by the recursion, not by the first re-lex.
DBN=0
for c in \
  "sh -c 'git switch main'" \
  'bash -c "git switch main"' \
  "zsh -c 'git switch main'" \
  'eval "git switch main"' \
  "sh -c 'cd /tmp/other && git switch main'" \
  "sh -c \"sh -c 'git switch main'\""
do
  DBN=$((DBN+1))
  deny "D-3B-D$DBN must deny: $c" "$PRIMARY" "$(payload_bash "$c" "s-d3bd$DBN")"
done

# D-3B-D7..D9 — the 3 round-5 carryovers, also measured. Clause 3a shapes kept in
# the 3b must-deny population because the two lists are differently composed
# (card :3104-3108): 6 + 3 = 9 measured, and the union with the abstract case
# below is 10. Deleting them here re-opens the "the prose says 9, the list says
# 8" contradiction rounds 3–7 kept re-reading.
for c in \
  "env -C /tmp/other git switch main" \
  'timeout 5 git commit -m x' \
  'if cd /tmp/other; then git commit -m x; fi'
do
  DBN=$((DBN+1))
  deny "D-3B-D$DBN must deny: $c" "$PRIMARY" "$(payload_bash "$c" "s-d3bd$DBN")"
done

# D-3B-D10 — the 1 abstract case, CONSTRUCTED rather than quoted: a collapsed
# token segments() returns [] for. Built by appending an unbalanced double quote
# to a git command, then re-verified against the live segments() so the case
# cannot silently stop being the empty-lex case. Same fixture as D43, asserted
# here as the tenth member of the must-deny population.
# MEASURED 2026-08-26 on /usr/bin/python3 3.9.6:
#   segments('git worktree add "unclosed')            -> []
#   segments('sh -c \'git worktree add "unclosed\'')  -> [({}, ['sh','-c','git worktree add "unclosed'])]
DBN=$((DBN+1))
deny "D-3B-D$DBN must deny: a collapsed token segments() returns [] for" "$PRIMARY" \
  "$(payload_bash "$UNPARSED_CMD" "s-d3bd$DBN")" "$UNPARSED_TOK"

# D-3B-A1..A4 — must allow, the false-deny guard. These are the shapes the wider
# "git anywhere in the re-lexed tokens" variant was measured to break (4 of 19
# real shapes). This group is why clause 3b tests command position rather than
# mere presence; without it the next revision silently widens the rule and breaks
# the PR workflow. Run from the PRIMARY checkout, where the rule is strictest.
DBA=0
for c in \
  'gh pr create --title "fix git guard" --body "closes the hole"' \
  'gh issue comment 12 --body "the git switch case is covered"' \
  "git commit -m 'fix: git switch is now denied'" \
  'curl -s "https://github.com/o/r.git"'
do
  DBA=$((DBA+1))
  allow_silent "D-3B-A$DBA must allow: $c" "$PRIMARY" "$(payload_bash "$c" "s-d3ba$DBA")"
done

# D-3B-R1..R4 — must allow, THE STATED RESIDUALS. THESE ASSERT AN ALLOW ON
# PURPOSE (card :3129-3136, Non-goals). They are not gaps waiting to be closed by
# a later revision: R1/R2 would require reading arbitrary files and parsing
# arbitrary languages, and R3/R4 are the clause-3c depth-bound relaxation the
# user decided on 2026-08-25. If a later change makes any of them deny, that is a
# behavior change to decide deliberately, not a bug fix to land quietly — do NOT
# "fix" these into denies.
# R3 additionally records that its gap is at LAYER 1 ONLY: layer 2 refuses that
# HEAD move regardless of quoting. That half is asserted in the layer-2 group
# (card :2174); this harness drives layer 1 alone.
# R4 is the one genuinely unbackstopped residual: layer 2 judges HEAD moves, not
# worktree locations, so `git worktree add` past the bound is allowed by both.
allow_silent 'D-3B-R1 residual, allowed on purpose: ./myscript.sh' "$PRIMARY" \
  "$(payload_bash './myscript.sh' s-d3br1)"
allow_silent 'D-3B-R2 residual, allowed on purpose: python3 -c building a git call' \
  "$PRIMARY" \
  "$(payload_bash "python3 -c 'import subprocess; subprocess.run([\"git\",\"log\"])'" s-d3br2)"
allow_silent 'D-3B-R3 residual, allowed on purpose: git switch past the depth bound (layer 1 only)' \
  "$PRIMARY" "$(payload_bash "$NEST4_SWITCH" s-d3br3)"
allow_silent 'D-3B-R4 residual, allowed on purpose: git worktree add past the depth bound' \
  "$PRIMARY" "$(payload_bash "$NEST4_WTADD" s-d3br4)"
# ================================================================= GROUP L ===
# Feature: the liveness check — layer 1 reports when layer 2 is not armed (card :2467)

# A repo of this group's own, so no case here mutates $PRIMARY's config and leaks
# a core.hooksPath into a later group. mk_linked is called for the .repo-root
# fixture only: boundary 14 denies when ~/.worktrees/<repo>/.repo-root cannot be
# read, and a deny raised THERE would never reach the liveness check, so the
# hooksPath substring below would fail for a reason that has nothing to do with
# layer 2.
LIVE="$TMP/repos/live"
mk_repo "$LIVE"
mk_linked "$LIVE" "feat-live"

# The three absence modes, built explicitly rather than by mutating one directory:
# the card measured all three to fail open SILENTLY at layer 2 (rc=0, HEAD moved),
# so layer 2 cannot report any of them and only layer 1 can. "Present but not
# executable" is the mode that reads most like a working install and is the one a
# file-existence test passes — it is the falsifier for the whole check, which is
# why it is a case of its own and not folded into "missing file".
HP_NOFILE="$TMP/live/hp-nofile"          # directory exists, empty
HP_NOEXEC="$TMP/live/hp-noexec"          # file present, mode 644
HP_MISSING="$TMP/live/hp-missing"        # never created
HP_ARMED="$TMP/live/hp-armed"            # the control: present and executable
mkdir -p "$HP_NOFILE" "$HP_NOEXEC" "$HP_ARMED"
printf '#!/bin/sh\nexit 0\n' > "$HP_NOEXEC/reference-transaction"; chmod 644 "$HP_NOEXEC/reference-transaction"
printf '#!/bin/sh\nexit 0\n' > "$HP_ARMED/reference-transaction";  chmod 755 "$HP_ARMED/reference-transaction"

# Arming is a `git config --global core.hooksPath` write (task 6e), so the
# resolution path these cases exercise is the GLOBAL one. The harness exports
# GIT_CONFIG_GLOBAL=/dev/null, so each case names it again in RUN_ENV to override.
for m in nofile noexec missing armed; do
  case "$m" in
    nofile)  d="$HP_NOFILE" ;;
    noexec)  d="$HP_NOEXEC" ;;
    missing) d="$HP_MISSING" ;;
    armed)   d="$HP_ARMED" ;;
  esac
  git_q config --file "$TMP/live/gc-$m" core.hooksPath "$d"
done

# L1..L3 — Scenario Outline: Layer 1 reports when layer 2 is not armed, one case
# per Examples row. Boundary 34 is layer 2's side of this (no layer-2 code runs,
# so no layer-2 verdict exists); the mitigation is external, and it is this check.
#
# Why `deny` and not `allow_warn`: "git switch main" from a primary checkout is
# denied by Arm D on its own (card :1895), independently of anything layer 2 does,
# so exit 2 here encodes NO answer to task 6b's open question — the card records
# only "reports", and does not say whether layer 1 denies, warns, or logs. What
# each case actually pins is the discriminating half: stderr NAMES THE RESOLVED
# hooksPath. If task 6b lands on report-to-log-only, these three assertions are
# the ones that must change, and nothing else in the group does.
# RUN_ENV is set immediately before each assertion because the runner consumes and
# clears it, so a hooksPath can never leak into the next case.
RUN_ENV=(GIT_CONFIG_GLOBAL="$TMP/live/gc-nofile")
deny 'L1 no reference-transaction file exists at the resolved hooksPath' "$LIVE" \
  "$(payload_bash 'git switch main' s-l1)" "$HP_NOFILE"

RUN_ENV=(GIT_CONFIG_GLOBAL="$TMP/live/gc-noexec")
deny 'L2 reference-transaction exists but is not executable' "$LIVE" \
  "$(payload_bash 'git switch main' s-l2)" "$HP_NOEXEC"

RUN_ENV=(GIT_CONFIG_GLOBAL="$TMP/live/gc-missing")
deny 'L3 the resolved hooksPath directory does not exist' "$LIVE" \
  "$(payload_bash 'git switch main' s-l3)" "$HP_MISSING"

# L4 — the armed control. Not an Examples row; added because a check that reports
# every time is indistinguishable from a check that reports unconditionally, and
# three "it reported" cases cannot tell those apart. The lacks-half is asserted on
# the hooksPath rather than on any wording, because the card fixes the FACT the
# report carries (":2478, the report names the resolved hooksPath") and fixes no
# phrasing. $err survives the deny() call — it is set by _run, which deny calls.
RUN_ENV=(GIT_CONFIG_GLOBAL="$TMP/live/gc-armed")
deny 'L4 armed control — Arm D still denies the switch' "$LIVE" \
  "$(payload_bash 'git switch main' s-l4)"
assert_last_stderr_lacks \
  'L4 …and says nothing about liveness (an armed layer 2 must not be reported)' "$HP_ARMED"

# L5 — Scenario: A repo-local core.hooksPath silently removes layer 2. The global
# config names the ARMED directory on purpose: that is the falsifier. A check that
# reads `git config --global core.hooksPath` reports "armed" for precisely the one
# repo where the guard is gone, and only a check reading the EFFECTIVE value
# (local beats global — husky and lefthook both install by setting it locally)
# names .husky here. Its own repo, so the local set cannot leak.
HUSKY="$TMP/repos/husky"
mk_repo "$HUSKY"
mk_linked "$HUSKY" "feat-husky"
git_q -C "$HUSKY" config core.hooksPath .husky
RUN_ENV=(GIT_CONFIG_GLOBAL="$TMP/live/gc-armed")
deny 'L5 a repo-local core.hooksPath is what the liveness check must resolve' "$HUSKY" \
  "$(payload_bash 'git switch main' s-l5)" ".husky"

# L6 — Scenario: The check is not self-hosting. Deliberately NOT asserted: the
# scenario's Given is "settings.json does not register worktree-guard.sh", and
# this suite reaches the guard only by invoking $HOOK directly. There is no
# payload that produces the unregistered world, so any case here would pass
# without evaluating anything. A skip note keeps it on the record instead of a
# fabricated green. The regress terminates at settings.json, which is tracked and
# reviewable — no hook can guard its own registration.
skipped 'L6 the check is not self-hosting (unassertable: the suite invokes the hook directly)'

# L7 — Scenario: An assignment prefix on the git command line reaches layer 2.
# The arrival half is card-measured ("Mode and bypass must reach a different
# process") and can only be asserted in layer 2's own suite: layer 2 is a child of
# git, and this suite never runs git on the guard's behalf, so it cannot observe
# that environment. Layer 1's contribution is the half asserted here — it must let
# the prefixed command through unrefused, because a layer-1 deny means git never
# runs and the prefix reaches nothing. Silence is the card's reading: stderr is
# specified for denies and for boundary 10's warnings, and a bypass is neither.
allow_silent 'L7 an assignment prefix is allowed through by layer 1 (layer-2 arrival is asserted in layer 2 suite)' \
  "$PRIMARY" "$(payload_bash 'WORKTREE_EXEMPT=hotfix git switch main' s-l7)"

# L8 — Scenario: WORKTREE_GUARD_MODE reaches layer 2 from settings.json env.
# ⬜ THE CARD RECORDS THE ANSWER AS OPEN — task 6c, card :3184: whether
# settings.json `env` reaches layer 2 is NOT MEASURED, and until it is run no
# claim that WORKTREE_GUARD_MODE arms layer 2 may be written down. Layer 2 is a
# child of git, not of the hook, so the measured assignment-prefix route in L7
# does not settle it. This case therefore asserts ONLY layer 1's half — that layer
# 1 honours a mode value it inherits from its environment — and the description
# says so, so a green line here can never be read as coverage of the layer-2 half.
log_reset
RUN_ENV=(WORKTREE_GUARD_MODE=log)
allow_silent 'L8 layer 1 honours the inherited mode (layer-2 arrival NOT MEASURED — card 6c)' \
  "$PRIMARY" "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-l8)"

# ================================================================= GROUP G ===
# Feature: Arming and the log (card :2678)

# The field separator, spelled once. Bash 3.2 has no $'\t' in every position that
# matters here, and every format assertion below depends on real tab bytes rather
# than on whitespace that merely prints like them.
TAB="$(printf '\t')"

# G1 — Scenario: WORKTREE_GUARD_MODE is unset (boundary 8). Absence is the
# documented ship state: allow, and record would-deny. The runner defaults the
# variable to deny, and RUN_ENV can only set it — including to the empty string,
# which is boundary 9's "present but wrong", a different case. Unsetting needs
# `env -u`, so this case is hand-rolled the same way P5b is.
log_reset
n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
( cd "$PRIMARY" && printf '%s' "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-g1)" \
  | env -u WORKTREE_GUARD_MODE HOME="$HOME_FIX" WORKTREE_GUARD_STATE_DIR="$STATE_DIR" \
      bash "$HOOK" ) >"$out" 2>"$err"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$err" ]; then
  ok 'G1 an unset WORKTREE_GUARD_MODE allows'
else
  printf 'FAIL — G1 an unset WORKTREE_GUARD_MODE allows (want exit 0 and empty stderr, got %s)\n  stderr: %s\n' \
    "$rc" "$(cat "$err")"; fail=$((fail+1))
fi
assert_log_count 'G1 …and appends exactly one line' 1
assert_log_has   'G1 …carrying arm A, mode log, decision would-deny' \
  "${TAB}A${TAB}log${TAB}would-deny${TAB}"

# G2 — Scenario: WORKTREE_GUARD_MODE holds an unrecognized value (boundary 9).
# Deny, and name the value. Absence and a typo are deliberately different cases:
# reading a failed attempt to arm the guard as "off" is a silent disarm. The
# required substring is the typo itself, which is the only thing that proves the
# value was read rather than defaulted.
log_reset
RUN_ENV=(WORKTREE_GUARD_MODE=denyy)
deny 'G2 an unrecognized mode denies and names the value' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-g2)" \
  "denyy"

# G3 — Scenario: Allows are never logged. One line per refusal or bypass, never
# per evaluation: the round-2 volume measurement put one-line-per-evaluation at
# 10–20 MB per three days, at which size "review the log before flipping" is not
# a real instruction. Both halves are asserted — the allow AND the empty log.
log_reset
allow_silent 'G3 an exempt-path write is allowed' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/settings.json" s-g3)"
assert_log_empty 'G3 …and nothing is appended to the log'

# G4 — Scenario: A refusal is logged once, with the session id. This is the case
# that pins the LINE FORMAT, not merely that a line exists. The card gives the
# field order positionally (:1485):
#   <iso8601> <session_id> <arm> <mode> <decision> <repo-root> <path-or-command> [<exempt-reason>]
# so the assertion is one fixed string of tab-joined fields, which fails on a
# reordering, on a missing field, and on a separator that is not a tab. The
# `arm=D decision=bypass` phrasing at :2172 is prose naming the VALUES; the format
# line is the contract, and this case is where that reading is recorded.
log_reset
deny 'G4 Arm A denies a write in deny mode' "$PRIMARY" \
  "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-g4)"
assert_log_count 'G4 …exactly one line, not one per evaluation' 1
assert_log_has   'G4 …session_id, arm, mode, decision, repo-root, path in the card order' \
  "${TAB}s-g4${TAB}A${TAB}deny${TAB}deny${TAB}${PRIMARY}${TAB}${PRIMARY}/panes/run-pane-agent.sh"
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$LOG" 2>/dev/null; then
  ok 'G4 …opening with an ISO 8601 timestamp'
else
  printf 'FAIL — G4 …opening with an ISO 8601 timestamp\n  log:\n%s\n' "$(cat "$LOG" 2>/dev/null)"
  fail=$((fail+1))
fi
# Field COUNT, separately: a line whose fields are right but which carries an
# eighth field on a non-bypass refusal has an empty exempt-reason slot the card
# does not specify, and no substring assertion can see that.
nf="$(awk -F"$TAB" 'NR==1{print NF}' "$LOG" 2>/dev/null)"
if [ "$nf" = 7 ]; then
  ok 'G4 …with exactly 7 tab-separated fields (no exempt-reason on a refusal)'
else
  printf 'FAIL — G4 …with exactly 7 tab-separated fields (got %s)\n  log:\n%s\n' \
    "${nf:-none}" "$(cat "$LOG" 2>/dev/null)"; fail=$((fail+1))
fi

# G5 — Scenario: A command containing a newline stays on one line. 21.4% of real
# commands (1,601 of 7,474) contain a newline and tabs appear in 0.0%, so tab
# separation is safe as chosen and the path-or-command field must escape \n. Both
# halves matter: the escape AND the line count — a guard that wrote the raw
# newline would still "contain" the command text while producing two log lines,
# and a line-oriented log whose fields hold raw newlines is not parseable.
log_reset
CMD_NL="$(printf 'git switch main\ngit status')"
deny 'G5 Arm D denies a command containing a newline' "$PRIMARY" \
  "$(payload_bash "$CMD_NL" s-g5)"
assert_log_count 'G5 …and the log still holds exactly one line' 1
assert_log_has   'G5 …with the newline escaped as \n in the command field' \
  "git switch main\\ngit status"

# --- Boundary 10: the log cannot be appended to. Three rules, three outcomes. ---
#
# The block below denies the guard permission to CREATE the log by dropping write
# on $STATE_DIR (mode 500, then restored to 700). 500 and not 000: the directory
# must stay readable so the log can be read back after the case, otherwise
# "nothing was appended" and "nothing could be read" are indistinguishable — and
# each case restores the mode BEFORE asserting on the log for the same reason.
# The log file itself is removed first, so the failure is a failed create rather
# than a failed append to an existing file; either satisfies the card's "cannot be
# appended to", and a create failure is the one that leaves no file for
# assert_log_count to misread as an empty one.
#
# MEANINGFUL ONLY FOR A NON-ROOT RUNNER: root ignores the permission bits and
# every append below would succeed, turning four cases green while measuring
# nothing. That is announced as a skip rather than passed silently.
if [ "$(id -u)" = 0 ]; then
  for _g in G6 G7 G8 G9; do
    skipped "$_g boundary 10 (running as root: chmod 500 does not deny writes)"
  done
else
  # G6 — Scenario: The log cannot be written, in log mode. Boundary 10 rule 1:
  # warn and allow. A guard that is not enforcing must not start enforcing because
  # a disk filled up. The warning must name the log path — the card fixes that
  # fact, so it is the substring, not a wording.
  log_reset
  chmod 500 "$STATE_DIR"
  RUN_ENV=(WORKTREE_GUARD_MODE=log)
  allow_warn 'G6 log mode, failed append: allow and warn naming the log path' "$PRIMARY" \
    "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-g6)" \
    "$LOG"
  chmod 700 "$STATE_DIR"
  assert_log_count 'G6 …and the would-deny line is lost, as stated' 0

  # G7 — Scenario: The log cannot be written while recording a refusal. Boundary
  # 10 rule 2, the one case round 3's blanket-deny reasoning does cover: the
  # command was already being refused, so the append failure changes nothing about
  # the outcome — but the message must say the decision could not be recorded,
  # which is what separates this deny from every other deny.
  log_reset
  chmod 500 "$STATE_DIR"
  deny 'G7 deny mode, failed append while recording a refusal: deny and say so' "$PRIMARY" \
    "$(payload_write Write file_path "$PRIMARY/panes/run-pane-agent.sh" s-g7)" \
    "could not be recorded"
  chmod 700 "$STATE_DIR"

  # G8 — Scenario: The log cannot be written while recording a bypass. Boundary 10
  # rule 3, the design's ONLY deliberate fail-open on an enforcement path. Round 4
  # disproved the claim that this path fires only on a refusal: a bypass is an
  # allow, and switching the escape hatch off because the disk is full is the worst
  # moment to switch it off — the user reaching for it is already blocked on
  # something. All three halves are asserted, because the lost record is silent in
  # the log by design and the stderr warning is its only trace.
  log_reset
  chmod 500 "$STATE_DIR"
  allow_warn 'G8 deny mode, failed append while recording a bypass: allow and warn' "$PRIMARY" \
    "$(payload_bash 'WORKTREE_EXEMPT=hotfix git switch main' s-g8)" \
    "$LOG"
  chmod 700 "$STATE_DIR"
  assert_log_count 'G8 …and no line is appended — the bypass record is lost with no in-log trace' 0

  # G9 — Scenario: The log cannot be written, but no line was due. Allows are never
  # logged, so no append is attempted and no failure occurs. The unwritable log is
  # the whole point of the fixture: an implementation that probes the log on every
  # evaluation rather than only when it has a line to write warns here, and
  # allow_silent is what catches it.
  log_reset
  chmod 500 "$STATE_DIR"
  allow_silent 'G9 failed append is never reached when no line was due' "$PRIMARY" \
    "$(payload_write Write file_path "$PRIMARY/settings.json" s-g9)"
  chmod 700 "$STATE_DIR"
  assert_log_empty 'G9 …and the log is still empty'
fi

# Belt and braces: whichever branch ran, $STATE_DIR is writable and the log is
# clean before any later group runs. A leaked 500 here would fail every log
# assertion after this point for a reason no later case names.
chmod 700 "$STATE_DIR"
log_reset

printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
