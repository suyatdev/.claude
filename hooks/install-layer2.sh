#!/usr/bin/env bash
#
# install-layer2.sh — arm (or disarm) layer 2 of the worktree location guard.
#
# Running it is one command. Reading what it will do is this file, and that is the point: the
# thing it changes is a `git config --global core.hooksPath` write, which lives OUTSIDE the
# repository and REPLACES .git/hooks in every repository on this machine. A change with that
# reach should be reviewable before it is run, not explained afterwards.
#
#   hooks/install-layer2.sh                     arm, if the mode file says `deny`
#   hooks/install-layer2.sh --arm-in-log-mode   arm even while it says `log`
#   hooks/install-layer2.sh --uninstall         put it back
#
# WHAT IT DOES, in order, and it refuses before touching anything rather than half-way through:
#
# --uninstall is handled BEFORE any of the steps below, because it must not depend on the
# thing it is undoing — not on the ref backend, not on a readable mode file, and not on what
# that file says.
#
#   1. this repository's ref backend must be `files` (task 6a's arming rule) — under any other
#      backend there is no <common-dir>/HEAD.lock, so layer 2's whole rule allows everything
#      and arming installs a guard that is silently off;
#   2. the mode file must not say `log` unless --arm-in-log-mode says so;
#   3. the source files must be here;
#   4. the global core.hooksPath must be unset, or already ours — never overwritten;
#   5. place `reference-transaction` (executable) and `reference-transaction.mode` beside it;
#   6. write the global core.hooksPath;
#   7. run the SHARED liveness check and report what it says.
#
# ⚠️ THE ARMING WRITE IS NOT IN THE REPO, AND CANNOT BE. That is exactly why layer 1's mode
# switch lives in tracked settings.json and this one does not: `git config --global` writes to
# a file outside every checkout, so no commit records it and no revert removes it. The
# resolution is not to make the write tracked — it cannot be — but to make its ABSENCE
# DETECTED: task 6b's liveness check runs on every relevant tool call and reports an unarmed
# layer 2, and step 7 above runs the same check through the same code so the installer cannot
# report success under criteria layer 1 does not use. Tracked DETECTION standing in for
# tracked STATE is the trade being made here, and it belongs in the ADR (card task 11).
#
# ⚠️ WHAT ARMING COSTS, stated rather than discovered. core.hooksPath REPLACES .git/hooks; it
# does not add to it. Any repository on this machine that relies on a hook in .git/hooks stops
# running it. The card measured 0 non-sample executable hooks and 0 local core.hooksPath
# settings under $HOME, so the cost today is latent rather than live — but the reciprocal risk
# is real and is why the liveness check exists: husky and lefthook install by setting
# core.hooksPath LOCALLY, and local beats global, so the first repository to run `husky install`
# silently removes layer 2 from the one repository where work is happening.
#
# This script does NOT re-measure that blast radius. An unbounded `find $HOME` was measured to
# time out (card, "Installation"), and a bounded one would report a floor while reading like a
# count. It reports what is in the install directory, which it can see, and nothing it cannot.
#
# It also does not register anything in settings.json — that is card task 9, and deliberately
# last, because an armed layer 1 blocks edits to its own source.
#
#   0   armed (or removed) and verified
#   1   refused a precondition — NOTHING was changed
#   2   a step failed, or the liveness check failed after arming
#  64   usage
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK_NAME='reference-transaction'
MODE_NAME='reference-transaction.mode'
HOOK_SRC="$HERE/$HOOK_NAME"
MODE_SRC="$HERE/$MODE_NAME"
LIVENESS_LIB="$HERE/lib/worktree_guard_liveness.sh"

# The only ref backend layer 2's rule is defined for. Spelled the same way the hook spells it,
# and an allowlist of one rather than a denylist of `reftable` — a backend nobody has heard of
# yet must land on the same refusal.
SUPPORTED_BACKEND='files'
MODE_LOG='log'
MODE_DENY='deny'

# Where the hook is placed. NOT inside this repository: a global core.hooksPath pointing into a
# checkout breaks the moment that checkout is moved, removed or replaced by a worktree, and it
# would also put an untracked copy of a tracked file in `git status` forever. $XDG_CONFIG_HOME
# is git's own configuration home and is the convention this repo already follows elsewhere
# (treko's $TREKO_STORE_DIR).
TARGET="${XDG_CONFIG_HOME:-${HOME:-}/.config}/git/hooks"

say()  { printf 'install-layer2: %s\n' "$1"; }
die()  { printf 'install-layer2: %s\n' "$2" >&2; exit "$1"; }

ARM_IN_LOG_MODE=0
UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --arm-in-log-mode) ARM_IN_LOG_MODE=1 ;;
    --uninstall)       UNINSTALL=1 ;;
    *) die 64 "usage: install-layer2.sh [--arm-in-log-mode] [--uninstall]
  (unrecognised argument: $1 — an unknown flag is not a licence to do the default thing)" ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 ||
  die 1 'no git on PATH, so neither the ref backend nor the install can be established.'
[ -n "${HOME:-}" ] || [ -n "${XDG_CONFIG_HOME:-}" ] ||
  die 1 'neither $XDG_CONFIG_HOME nor $HOME is set, so there is no place to install to.'

# --- whose core.hooksPath is it? -----------------------------------------------------------
# Read BEFORE anything is placed. `--get` exits non-zero when the key is unset, which is not
# an error here.
CURRENT="$(git config --global --get core.hooksPath 2>/dev/null)" || CURRENT=''

# UNINSTALL RUNS BEFORE THE BACKEND AND MODE GATES, on purpose. It is the only route out of a
# machine-wide config write, so it must not depend on the ref backend, on a readable mode file,
# or on what that file says — an install whose mode file was deleted is exactly the state
# someone needs to get out of. A mutation found the earlier ordering hiding U2: --uninstall on
# a log-mode repository was refused by the log-mode guard, so the guard that actually protects
# somebody else's core.hooksPath could be deleted with the suite staying green.
uninstall() {
  if [ -z "$CURRENT" ]; then
    say "the global core.hooksPath is already unset."
  elif [ "$CURRENT" != "$TARGET" ]; then
    die 1 "the global core.hooksPath points somewhere this script did not install.

  found:    $CURRENT
  ours:     $TARGET

Unsetting it would remove somebody else's hooks from every repository on this machine. It was
left exactly as it was."
  else
    git config --global --unset core.hooksPath ||
      die 2 "could not unset the global core.hooksPath (it still reads: $CURRENT)."
    say "global core.hooksPath unset."
  fi
  rm -f "$TARGET/$HOOK_NAME" "$TARGET/$MODE_NAME"
  say "removed $TARGET/$HOOK_NAME and $TARGET/$MODE_NAME (the directory itself is left alone)."
  exit 0
}
[ "$UNINSTALL" = 1 ] && uninstall

# The repository this is being run from. The backend check and the liveness report are both
# about a REPOSITORY, and this is the only one the script can see. Say so plainly rather than
# letting one repo's answer read as a statement about the machine: arming is global and covers
# repositories that do not exist yet.
REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" || REPO=''
[ -n "$REPO" ] ||
  die 1 "this script is not inside a git repository ($HERE), so the ref backend it must check
before arming cannot be read."

# --- step 1: the ref backend ---------------------------------------------------------------
BACKEND="$(git -C "$REPO" rev-parse --show-ref-format 2>/dev/null)" || BACKEND=''
if [ "$BACKEND" != "$SUPPORTED_BACKEND" ]; then
  die 1 "this repository's ref backend reads as [${BACKEND:-<no answer>}], and layer 2
implements only [$SUPPORTED_BACKEND].

  repository: $REPO

Its whole rule is the presence of <common-git-dir>/HEAD.lock. On any other backend that file
does not exist, so the refusal clause could never fire and every HEAD write would be allowed —
the guard would be silently off rather than absent. Nothing was armed."
fi

# --- step 2: the mode ----------------------------------------------------------------------
[ -r "$MODE_SRC" ] ||
  die 1 "the mode file is missing or unreadable: $MODE_SRC
Layer 2 reads its arming switch from beside itself and refuses every HEAD move without it, so
placing the hook without this file would install a guard that blocks everything. Nothing was
armed."
[ -r "$HOOK_SRC" ] ||
  die 1 "the hook is missing or unreadable: $HOOK_SRC
Arming core.hooksPath with nothing to place would point every repository on this machine at a
directory git reads as 'no hooks at all'. Nothing was armed."

# Same reader as the hook's own: blank lines and `#` lines skipped, surrounding whitespace
# trimmed, first remaining line decides. A second spelling of this rule would be a second thing
# to keep in step, so it is kept deliberately identical and deliberately small.
MODE=''
while IFS= read -r one_line || [ -n "$one_line" ]; do
  one_line=${one_line#"${one_line%%[![:space:]]*}"}
  one_line=${one_line%"${one_line##*[![:space:]]}"}
  [ -z "$one_line" ] && continue
  case "$one_line" in '#'*) continue ;; esac
  MODE=$one_line
  break
done < "$MODE_SRC"

case "$MODE" in
  "$MODE_LOG"|"$MODE_DENY") ;;
  *) die 1 "the mode file does not name a mode.

  file:  $MODE_SRC
  read:  [${MODE:-<no value line>}]
  wants: $MODE_LOG or $MODE_DENY

Nothing was armed." ;;
esac

if [ "$MODE" = "$MODE_LOG" ] && [ "$ARM_IN_LOG_MODE" != 1 ]; then
  die 1 "the mode file says \`$MODE_LOG\`, so layer 2 would enforce nothing once armed.

  file: $MODE_SRC

Arming is not free — it replaces .git/hooks in every repository on this machine — and paying
that for a guard that only records should be something you asked for rather than something
that happened. Two ways forward:

  * arm it anyway, to start the evidence window (card task 10):
      $0 --arm-in-log-mode
  * flip the mode file to \`$MODE_DENY\` first, in its own deliberate commit, and re-run.

Nothing was armed."
fi

# --- step 3: is the global core.hooksPath somebody else's? ---------------------------------
# $CURRENT was read above, before anything could be placed.
if [ -n "$CURRENT" ] && [ "$CURRENT" != "$TARGET" ]; then
  die 1 "the global core.hooksPath is already set, and to something else.

  found:  $CURRENT
  wanted: $TARGET

Overwriting it would remove those hooks from every repository on this machine without a word.
Resolve it deliberately — move that directory's hooks under $TARGET and re-run, or install
layer 2 into $CURRENT by hand. Nothing was changed."
fi

# --- step 4: place the files ---------------------------------------------------------------
mkdir -p "$TARGET" || die 2 "could not create $TARGET"
[ -d "$TARGET" ] || die 2 "$TARGET is not a directory"

# Everything ALREADY in the install directory becomes a machine-wide hook the moment
# core.hooksPath points here, so it is named rather than left to be discovered. This is a
# report about a directory the script can see; it is deliberately not a claim about the machine.
OTHERS="$(ls -A "$TARGET" 2>/dev/null | grep -vxF -e "$HOOK_NAME" -e "$MODE_NAME" || true)"

cp "$HOOK_SRC" "$TARGET/$HOOK_NAME" || die 2 "could not place $TARGET/$HOOK_NAME"
chmod +x "$TARGET/$HOOK_NAME" || die 2 "could not make $TARGET/$HOOK_NAME executable"
cp "$MODE_SRC" "$TARGET/$MODE_NAME" || die 2 "could not place $TARGET/$MODE_NAME"

# --- step 5: arm it ------------------------------------------------------------------------
git config --global core.hooksPath "$TARGET" ||
  die 2 "could not write the global core.hooksPath"

# --- step 6: the shared liveness check -----------------------------------------------------
# The SAME code layer 1 runs, sourced rather than reimplemented: an installer with its own
# notion of "armed" would report success under criteria layer 1 does not use, and nobody reads
# both files at once. An install that placed a file and wrote a config key no git ever reads
# is the failure this step exists to catch, so its verdict decides the exit code.
[ -r "$LIVENESS_LIB" ] ||
  die 2 "armed, but the liveness check could not be run: $LIVENESS_LIB is missing.
Verify by hand before trusting this install:
  git -C <repo> rev-parse --path-format=absolute --git-path hooks"
# shellcheck source=lib/worktree_guard_liveness.sh
. "$LIVENESS_LIB" || die 2 "armed, but $LIVENESS_LIB could not be sourced."

wg_liveness "$REPO"
LIVE_RC=$?

if [ "$LIVE_RC" -ne 0 ]; then
  die 2 "armed, but the liveness check does NOT report layer 2 as armed: ${WG_LIVENESS_STATE:-unknown}

  hooks path: ${WG_LIVENESS_PATH:-<unresolved>}
  expected:   $TARGET/$HOOK_NAME, executable
  repository: $REPO

The global core.hooksPath was written; the install is not verified. Re-run, or --uninstall."
fi

say "layer 2 is ARMED, and the liveness check agrees."
printf '  hooks path:  %s\n' "$WG_LIVENESS_PATH"
printf '  hook:        %s\n' "$TARGET/$HOOK_NAME"
printf '  mode:        %s (%s)\n' "$MODE" "$TARGET/$MODE_NAME"
printf '  checked in:  %s\n' "$REPO"
if [ "$MODE" = "$MODE_LOG" ]; then
  printf '\n  In `%s` mode layer 2 refuses nothing. Every refusal it would have made is\n' "$MODE_LOG"
  printf '  appended to hooks/state/reference-transaction.log as WOULD-DENY. Flipping to\n'
  printf '  `%s` is card task 10, in its own deliberate commit.\n' "$MODE_DENY"
fi
if [ -n "$OTHERS" ]; then
  printf '\n  Also in that directory, and now machine-wide git hooks:\n'
  printf '%s\n' "$OTHERS" | sed 's/^/    /'
fi
printf '\n  This checked ONE repository. Arming is global and covers repositories that do not\n'
printf '  exist yet; a repo-LOCAL core.hooksPath (husky, lefthook) beats it and silently\n'
printf '  removes layer 2 there. Layer 1 re-runs this same check on every refusal it prints.\n'
printf '\n  To undo: %s --uninstall\n' "$0"
exit 0
