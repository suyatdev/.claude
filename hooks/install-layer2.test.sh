#!/usr/bin/env bash
# install-layer2.test.sh — unit tests for hooks/install-layer2.sh.
#
# Written BEFORE the script exists (card task 6e, piece 1, TDD). Until it lands
# every case here should fail for the RIGHT reason — "the script is not on disk",
# which control H1 names in the first line of output rather than leaving 20
# assertions to imply it.
#
# NOTHING HERE TOUCHES THE MACHINE'S REAL GIT CONFIG. That is the whole hazard of
# testing this script: arming is a `git config --global core.hooksPath` write,
# which replaces .git/hooks in EVERY repository on the machine. Isolation uses no
# test-only seam in the production script — GIT_CONFIG_GLOBAL points at a file
# under $TMP (git's own override, honoured by `git config --global`) and HOME is
# redirected, which is where the script derives its install directory from. A
# script that needed an override variable to be testable would be a script whose
# real path is never the tested one (the argument memsearch/bin/install-schedule.test.sh
# makes about the same shape).
#
# Run: bash hooks/install-layer2.test.sh
set -u

# The test-marker pair (hooks/test-marker-guard.sh, ADR 0027): install-layer2.sh
# ↔ install-layer2.test.sh IS an X.sh/X.test.sh sibling, unlike reference-transaction,
# whose filename git owns. So this suite writes the receipt on a green run.
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/install-layer2.sh"
HOOK_SRC="$HERE/reference-transaction"
MODE_SRC="$HERE/reference-transaction.mode"
LIVENESS_SRC="$HERE/lib/worktree_guard_liveness.sh"

# Physical path, not the one mktemp hands back: on macOS `mktemp -d` returns the
# /var symlink form while `git rev-parse` resolves to /private/var, and this suite
# compares a configured path against a resolved one.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

GIT_REAL="$(command -v git)"
export GIT_CONFIG_SYSTEM=/dev/null

pass=0; fail=0; skip=0
ok()   { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL — %s\n' "$1"; fail=$((fail+1)); }
skipped() { printf 'skip — %s\n' "$1"; skip=$((skip+1)); }

# ------------------------------------------------------------- the control ---
# Control. Without the script on disk every "it refused" case passes against
# bash's own 127, and a suite of refusals proves nothing about a script that does
# not exist. Every case below is gated on this.
PRESENT=0
if [ -f "$SCRIPT" ] && [ -r "$SCRIPT" ]; then PRESENT=1; fi
if [ "$PRESENT" = 1 ]; then
  ok 'H1 install-layer2.sh is on disk'
else
  bad "H1 install-layer2.sh is on disk (missing: $SCRIPT)"
fi

LIVENESS_PRESENT=0
if [ -f "$LIVENESS_SRC" ] && [ -r "$LIVENESS_SRC" ]; then LIVENESS_PRESENT=1; fi
if [ "$LIVENESS_PRESENT" = 1 ]; then
  ok 'H2 the shared liveness check is on disk (the installer reports through it)'
else
  bad "H2 the shared liveness check is on disk (missing: $LIVENESS_SRC)"
fi

# --------------------------------------------------------------- fixtures ---

git_q() { "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

# A throwaway checkout holding a COPY of the four files the installer needs, so a
# case can break one of them without touching the tracked tree. It is a real git
# repository because the installer resolves the backend and the liveness check
# against the repository it is run from.
n_fix=0
mk_fixture() { # -> echoes the fixture root; $FIX_HOME/$FIX_GC are set beside it
  n_fix=$((n_fix+1))
  local root="$TMP/fix$n_fix"
  mkdir -p "$root/hooks/lib" "$root/home"
  [ "$PRESENT" = 1 ] && cp "$SCRIPT" "$root/hooks/" && chmod +x "$root/hooks/install-layer2.sh"
  cp "$HOOK_SRC" "$root/hooks/" 2>/dev/null
  cp "$MODE_SRC" "$root/hooks/" 2>/dev/null
  cp "$LIVENESS_SRC" "$root/hooks/lib/" 2>/dev/null
  GIT_CONFIG_GLOBAL=/dev/null git_q -C "$root" init -q 2>/dev/null
  printf 'x\n' > "$root/f.txt"
  GIT_CONFIG_GLOBAL=/dev/null git_q -C "$root" add . >/dev/null 2>&1
  GIT_CONFIG_GLOBAL=/dev/null git_q -C "$root" commit -q -m init >/dev/null 2>&1
  FIX_HOME="$root/home"
  FIX_GC="$root/gitconfig-global"
  : > "$FIX_GC"
  printf '%s' "$root"
}

# The install target the script derives: ${XDG_CONFIG_HOME:-$HOME/.config}/git/hooks.
# Spelled out here rather than read back out of the script, so a script that
# silently moved it fails a case instead of moving the assertion with it.
target_of() { printf '%s/.config/git/hooks' "$1"; }

RC=0; OUT=''; ERR=''
run_install() { # $1 fixture root, $2.. args
  local root="$1"; shift
  OUT="$(cd "$root" && HOME="$root/home" GIT_CONFIG_GLOBAL="$root/gitconfig-global" \
         env -u XDG_CONFIG_HOME bash "$root/hooks/install-layer2.sh" "$@" 2>"$TMP/err")"
  RC=$?
  ERR="$(cat "$TMP/err")"
}

cfg() { # $1 fixture root — the global core.hooksPath, or the empty string
  GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL="$1/gitconfig-global" \
    "$GIT_REAL" config --global --get core.hooksPath 2>/dev/null || true
}

set_mode_src() { printf '%s\n' "$2" > "$1/hooks/reference-transaction.mode"; }

expect_rc() { # $1 desc, $2 want, $3 got
  if [ "$3" = "$2" ]; then ok "$1"; else
    printf 'FAIL — %s (want rc=%s, got %s)\n  stdout: %s\n  stderr: %s\n' \
      "$1" "$2" "$3" "$OUT" "$ERR"; fail=$((fail+1))
  fi
}

expect_says() { # $1 desc, $2 substring — searched across BOTH streams
  if printf '%s\n%s' "$OUT" "$ERR" | grep -qF -- "$2"; then ok "$1"; else
    printf 'FAIL — %s\n  want (substring): %s\n  stdout: %s\n  stderr: %s\n' \
      "$1" "$2" "$OUT" "$ERR"; fail=$((fail+1))
  fi
}

if [ "$PRESENT" != 1 ]; then
  printf '\n(the script is absent — the cases below run anyway, and every failure\n'
  printf ' below is the red the control above already named)\n\n'
fi

# ============================================================== GROUP I ===
# Feature: arming layer 2 (card task 6e, piece 1). One command to run, one file
# to read before running it.

# I1 — THE LOG-MODE REFUSAL (piece 4's second half). The shipped mode file says
# `log`, and arming is not free: it replaces .git/hooks in every repository on
# this machine. Paying that for a guard that enforces nothing should be a thing
# you asked for, so the default is a refusal.
F="$(mk_fixture)"
run_install "$F"
expect_rc 'I1 refuses to arm while the mode file says log' 1 "$RC"
expect_says 'I1 …and the message names the flag that overrides it' '--arm-in-log-mode'
if [ -z "$(cfg "$F")" ]; then
  ok 'I1 …and NOTHING was changed: no global core.hooksPath was written'
else
  printf 'FAIL — I1 a refusal must change nothing (core.hooksPath=%s)\n' "$(cfg "$F")"
  fail=$((fail+1))
fi
if [ ! -e "$(target_of "$F/home")/reference-transaction" ]; then
  ok 'I1 …and no hook file was placed'
else
  bad 'I1 …and no hook file was placed'
fi

# I2 — the arm itself, under the flag. Four separate assertions, because "it
# exited 0" is the one thing an installer must never be believed on: the whole
# reason the liveness check exists is that a hook can be present and inert.
F="$(mk_fixture)"
run_install "$F" --arm-in-log-mode
expect_rc 'I2 --arm-in-log-mode arms it' 0 "$RC"
T="$(target_of "$F/home")"
[ -f "$T/reference-transaction" ] && ok 'I2 …the hook file is placed' \
  || bad "I2 …the hook file is placed (missing: $T/reference-transaction)"
[ -x "$T/reference-transaction" ] && ok 'I2 …and is executable' \
  || bad 'I2 …and is executable'
[ -f "$T/reference-transaction.mode" ] && ok 'I2 …the mode file is placed beside it' \
  || bad 'I2 …the mode file is placed beside it'
if [ "$(cfg "$F")" = "$T" ]; then
  ok 'I2 …and the global core.hooksPath names the install directory'
else
  printf 'FAIL — I2 global core.hooksPath (want %s, got %s)\n' "$T" "$(cfg "$F")"
  fail=$((fail+1))
fi
expect_says 'I2 …and it reports the liveness verdict rather than only "done"' "$T"

# I3 — idempotence. Running it twice is the ordinary case (a hook file changes and
# is re-placed), and the second run must not trip its own conflict check on the
# core.hooksPath the first run wrote.
run_install "$F" --arm-in-log-mode
expect_rc 'I3 running it again is not an error' 0 "$RC"
if [ "$(cfg "$F")" = "$T" ]; then
  ok 'I3 …and the state is unchanged'
else
  printf 'FAIL — I3 state after a second run (want %s, got %s)\n' "$T" "$(cfg "$F")"
  fail=$((fail+1))
fi

# I4 — the conflict. A global core.hooksPath already pointing somewhere else is
# somebody's install, and overwriting it would remove THEIR hooks from every
# repository on the machine without a word.
F="$(mk_fixture)"
mkdir -p "$F/someone-elses-hooks"
GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL="$F/gitconfig-global" \
  "$GIT_REAL" config --global core.hooksPath "$F/someone-elses-hooks"
run_install "$F" --arm-in-log-mode
expect_rc 'I4 refuses when core.hooksPath already points elsewhere' 1 "$RC"
expect_says 'I4 …and the message names the value it found' "$F/someone-elses-hooks"
if [ "$(cfg "$F")" = "$F/someone-elses-hooks" ]; then
  ok 'I4 …and that value is left exactly as it was'
else
  printf 'FAIL — I4 the existing value must survive (got %s)\n' "$(cfg "$F")"
  fail=$((fail+1))
fi

# I5 — the ref backend, task 6a's arming rule. Under reftable there is no
# <common-dir>/HEAD.lock, so layer 2's whole rule allows everything: arming there
# installs a guard that is silently off for the entire repository.
F="$(mk_fixture)"
RTFIX="$F/reftable"
if GIT_CONFIG_GLOBAL=/dev/null git_q init -q --ref-format=reftable "$RTFIX" >/dev/null 2>&1 &&
   [ -d "$RTFIX/.git" ]; then
  cp -R "$F/hooks" "$RTFIX/hooks"
  mkdir -p "$RTFIX/home"
  : > "$RTFIX/gitconfig-global"
  run_install "$RTFIX" --arm-in-log-mode
  expect_rc 'I5 refuses on a non-files ref backend' 1 "$RC"
  expect_says 'I5 …and the message names the backend it read' 'reftable'
  if [ -z "$(cfg "$RTFIX")" ]; then
    ok 'I5 …and nothing was armed'
  else
    bad 'I5 …and nothing was armed'
  fi
else
  skipped 'I5 refuses on a non-files ref backend (this git has no --ref-format)'
  skipped 'I5 …and the message names the backend it read'
  skipped 'I5 …and nothing was armed'
fi

# I6/I7 — the source files. An installer that armed core.hooksPath and then found
# it had nothing to place would leave every repository on the machine pointed at
# an empty directory, which git reads as "no hooks at all".
F="$(mk_fixture)"
rm -f "$F/hooks/reference-transaction"
run_install "$F" --arm-in-log-mode
expect_rc 'I6 refuses when the hook source is missing' 1 "$RC"
[ -z "$(cfg "$F")" ] && ok 'I6 …and armed nothing' || bad 'I6 …and armed nothing'

F="$(mk_fixture)"
rm -f "$F/hooks/reference-transaction.mode"
run_install "$F" --arm-in-log-mode
expect_rc 'I7 refuses when the mode source is missing' 1 "$RC"
[ -z "$(cfg "$F")" ] && ok 'I7 …and armed nothing' || bad 'I7 …and armed nothing'

# I8 — a mode file that already says `deny` needs no flag. The flag is about
# arming something inert, not about arming at all.
F="$(mk_fixture)"
set_mode_src "$F" deny
run_install "$F"
expect_rc 'I8 a deny mode file arms with no flag' 0 "$RC"
T="$(target_of "$F/home")"
[ -x "$T/reference-transaction" ] && ok 'I8 …and the hook is in place and executable' \
  || bad 'I8 …and the hook is in place and executable'

# I9 — usage. An unknown flag is not a licence to do the default thing.
F="$(mk_fixture)"
run_install "$F" --burn-it-down
expect_rc 'I9 an unrecognised argument is a usage error' 64 "$RC"
[ -z "$(cfg "$F")" ] && ok 'I9 …and nothing was armed' || bad 'I9 …and nothing was armed'

# ============================================================== GROUP U ===
# Feature: getting back out. The `git config --global` write lives OUTSIDE the
# repository, so no commit, checkout or revert removes it — the same argument
# install-schedule makes for its own --uninstall, one layer down. This is not in
# the card's four bullets; it is here because an unrevertable machine-wide write
# with no documented way back is worse than the papercut it prevents.

F="$(mk_fixture)"
set_mode_src "$F" deny
run_install "$F"
T="$(target_of "$F/home")"
run_install "$F" --uninstall
expect_rc 'U1 --uninstall exits 0' 0 "$RC"
[ -z "$(cfg "$F")" ] && ok 'U1 …and the global core.hooksPath is gone' \
  || bad "U1 …and the global core.hooksPath is gone (survived: $(cfg "$F"))"
[ ! -e "$T/reference-transaction" ] && ok 'U1 …and the placed hook is removed' \
  || bad 'U1 …and the placed hook is removed'

# U3 — THE WAY BACK MUST NOT DEPEND ON THE SWITCH, and this case exists because a
# mutation showed U2 passing for the wrong reason. With --uninstall handled after
# the mode check, an --uninstall on a repo whose mode file says `log` was refused
# by the LOG-MODE guard, not by anything about uninstalling — so deleting U2's
# own guard left the suite fully green. Uninstalling must work regardless of what
# the mode file says, of whether it is readable, and of the ref backend: it is the
# only route out of a machine-wide config write, and gating it on the thing being
# undone is how an escape hatch stops being one.
F="$(mk_fixture)"
set_mode_src "$F" deny
run_install "$F"
T="$(target_of "$F/home")"
set_mode_src "$F" log
run_install "$F" --uninstall
expect_rc 'U3 --uninstall works while the mode file says log' 0 "$RC"
[ -z "$(cfg "$F")" ] && ok 'U3 …and the global core.hooksPath is gone' \
  || bad "U3 …and the global core.hooksPath is gone (survived: $(cfg "$F"))"

# U4 — the same, with no readable mode file at all. An install whose mode file was
# deleted is exactly the state someone needs to get out of.
F="$(mk_fixture)"
set_mode_src "$F" deny
run_install "$F"
rm -f "$F/hooks/reference-transaction.mode"
run_install "$F" --uninstall
expect_rc 'U4 --uninstall works with no mode file at all' 0 "$RC"
[ -z "$(cfg "$F")" ] && ok 'U4 …and the global core.hooksPath is gone' \
  || bad "U4 …and the global core.hooksPath is gone (survived: $(cfg "$F"))"

# U2 — it must not disarm somebody else's install. Same argument as I4, in the
# other direction: an --uninstall that unset a core.hooksPath it did not write
# would remove their hooks from every repository on the machine.
F="$(mk_fixture)"
set_mode_src "$F" deny          # so a log-mode refusal cannot stand in for the real one
mkdir -p "$F/someone-elses-hooks"
GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL="$F/gitconfig-global" \
  "$GIT_REAL" config --global core.hooksPath "$F/someone-elses-hooks"
run_install "$F" --uninstall
expect_rc 'U2 --uninstall refuses when core.hooksPath is not ours' 1 "$RC"
if [ "$(cfg "$F")" = "$F/someone-elses-hooks" ]; then
  ok 'U2 …and leaves it exactly as it was'
else
  printf 'FAIL — U2 the foreign value must survive (got %s)\n' "$(cfg "$F")"
  fail=$((fail+1))
fi

# ============================================================== GROUP E ===
# Feature: it actually armed something. GROUP I asserts the FILES and the CONFIG;
# this group asserts the EFFECT, through a real git. Without it the whole suite
# passes against an installer that copies a file and writes a config key that no
# git ever reads — which is exactly the failure mode the liveness check exists for
# one layer up.

F="$(mk_fixture)"
set_mode_src "$F" deny
run_install "$F"
if [ "$RC" = 0 ]; then
  E_HOME="$F/home"; E_GC="$F/gitconfig-global"

  # E1 — git init, the case task 6e piece 5 exists for. Armed, machine-wide, in a
  # directory git has never seen.
  E_INIT="$F/e-init"
  ( HOME="$E_HOME" GIT_CONFIG_GLOBAL="$E_GC" GIT_CONFIG_SYSTEM=/dev/null \
      "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main \
      init -q "$E_INIT" ) >"$TMP/e1.out" 2>&1
  E1_RC=$?
  if [ "$E1_RC" = 0 ] && [ -f "$E_INIT/.git/HEAD" ]; then
    ok 'E1 git init succeeds under the armed install, and writes its HEAD'
  else
    printf 'FAIL — E1 git init under the armed install (rc=%s, HEAD present=%s)\n  %s\n' \
      "$E1_RC" "$( [ -f "$E_INIT/.git/HEAD" ] && echo yes || echo no )" "$(cat "$TMP/e1.out")"
    fail=$((fail+1))
  fi

  # E2 — and the guard is not merely inert. A branch switch in that repository's
  # primary checkout must be refused, machine-wide, with no per-repo setup. This
  # is the assertion E1 alone cannot make: an install that armed NOTHING passes E1.
  ( cd "$E_INIT" && printf 'y\n' > g.txt &&
    HOME="$E_HOME" GIT_CONFIG_GLOBAL="$E_GC" GIT_CONFIG_SYSTEM=/dev/null \
      "$GIT_REAL" -c user.email=t@t -c user.name=t add g.txt &&
    HOME="$E_HOME" GIT_CONFIG_GLOBAL="$E_GC" GIT_CONFIG_SYSTEM=/dev/null \
      "$GIT_REAL" -c user.email=t@t -c user.name=t commit -q -m one &&
    HOME="$E_HOME" GIT_CONFIG_GLOBAL="$E_GC" GIT_CONFIG_SYSTEM=/dev/null \
      "$GIT_REAL" branch other ) >/dev/null 2>&1
  ( cd "$E_INIT" && HOME="$E_HOME" GIT_CONFIG_GLOBAL="$E_GC" GIT_CONFIG_SYSTEM=/dev/null \
      "$GIT_REAL" switch other ) >"$TMP/e2.out" 2>&1
  E2_RC=$?
  if [ "$E2_RC" = 128 ]; then
    ok 'E2 …and a branch switch in that primary checkout IS refused (the install is live)'
  else
    printf 'FAIL — E2 a switch under the armed install (want rc=128, got %s)\n  %s\n' \
      "$E2_RC" "$(cat "$TMP/e2.out")"; fail=$((fail+1))
  fi
  if grep -qF 'worktree-location-guard (layer 2):' "$TMP/e2.out"; then
    ok 'E2 …and the refusal names which layer refused'
  else
    printf 'FAIL — E2 the refusal must carry the layer-2 prefix\n  %s\n' "$(cat "$TMP/e2.out")"
    fail=$((fail+1))
  fi
else
  skipped 'E1 git init succeeds under the armed install, and writes its HEAD'
  skipped 'E2 …and a branch switch in that primary checkout IS refused (the install is live)'
  skipped 'E2 …and the refusal names which layer refused'
fi

printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
