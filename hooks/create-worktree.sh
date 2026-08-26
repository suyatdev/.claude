#!/usr/bin/env bash
#
# create-worktree.sh — WorktreeCreate / WorktreeRemove lifecycle hook.
#
# Registered with no `matcher` (task 9, not this file):
#   "WorktreeCreate": [ { "hooks": [ { "type": "command", "command": "<abs>/create-worktree.sh" } ] } ]
#   "WorktreeRemove": [ { "hooks": [ { "type": "command", "command": "<abs>/create-worktree.sh" } ] } ]
#
# Arm B of the worktree location guard (card, "Arm B — the location, by redirect"). Unlike
# worktree-guard.sh, this is not a PreToolUse deny: `hookBased: true` means Claude creates no
# worktree and no branch of its own, and reports none — this hook does both, or the session
# silently lands in `<repo>/.claude/worktrees` instead of the centralized store, because that
# fallback path exists with no hook consultation at all (card, "The limitation to design
# around"). The harness's own contract, measured task 1b: the LAST NON-EMPTY trimmed line of
# stdout is taken as the worktree path on success, and a broken hook fails the session closed
# — every malformed output (empty, relative, nonexistent) is rejected. So a lifecycle hook has
# no "deny": it either succeeds and prints exactly one absolute path, or it fails — stderr
# message, exit 1, and NOTHING on stdout, because emitting a path for a worktree that does not
# exist sends the session into a nonexistent directory.
#
# WorktreeRemove fires and, with a hook registered, Claude performs NO cleanup of its own
# (measured, task 1b open question 9) — the session reports "Exited and removed worktree at
# …" whether or not this hook does anything at all. Cleanup is entirely this hook's job:
# `git worktree remove` the path, then delete the branch this hook created, or both accumulate
# under ~/.worktrees forever while the UI claims they are gone.
#
# Design, the full Arm B contract, the branch/base table, and failure boundaries 15-27:
# docs/features/worktree-location-guard.md.
#
# Fails CLOSED, for the same reason worktree-guard.sh and reference-transaction do: a hook
# that switches itself off exactly when it cannot verify its own precondition is
# indistinguishable from the feature being absent.

set -u

LF='
'

# git rev-parse --path-format=absolute is what keeps a repo root physical rather than
# logical — /tmp and /var are symlinks on macOS, and a logical root would make every later
# path compare meaningless. It landed in git 2.31; below the floor this hook fails rather
# than guessing, same precedent as worktree-guard.sh and reference-transaction.
FLOOR_MAJOR=2
FLOOR_MINOR=31
FLOOR='2.31'

# The centralized worktree store, relative to $HOME. Rule 2 of the card's Problem section —
# the same value worktree-guard.sh's Arm B2 tests a `git worktree add` operand against.
STORE_REL='.worktrees'

# The marker naming which repo root a store directory belongs to (card, boundary 14/19/20).
# worktree-guard.sh's Arm B2 only ever READS this file, as a check on a hand-rolled `git
# worktree add`; this hook is the one that WRITES it, on a store's first use.
MARKER_NAME='.repo-root'

PREFIX='create-worktree:'

# The single failure exit. Every path above prints a message and stops here: stderr, exit 1,
# and — because this runs before anything is ever written to stdout — no stdout path either.
fail() { # $1 message body, without the prefix
  printf '%s %s\n' "$PREFIX" "$1" 1>&2
  exit 1
}

# --- step 1: the payload -------------------------------------------------------------------
payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi
[ -n "$payload" ] || fail "this hook payload could not be read at all — nothing was on stdin. Nothing was created or removed."

py=$(command -v python3 || command -v python) || py=""
[ -n "$py" ] || fail "no python3 or python on PATH, so this hook payload could not be read. Nothing was created or removed."

# Emitted as `<event>\n<cwd>\n<name>\n<worktree_path>\nEND`. The END sentinel keeps a value
# whose last character is itself a newline from being eaten by command substitution's
# trailing-newline strip (same idiom as worktree-guard.sh:266-293).
parsed=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
if not isinstance(p, dict):
    sys.exit(1)
def s(v):
    return v if isinstance(v, str) else ""
sys.stdout.write(s(p.get("hook_event_name")) + "\n" +
                 s(p.get("cwd")).replace("\n", " ") + "\n" +
                 s(p.get("name")) + "\n" +
                 s(p.get("worktree_path")) + "\nEND")
')
rc=$?
[ "$rc" -eq 0 ] || fail "this hook payload could not be read as JSON. Nothing was created or removed."

parsed=${parsed%END}
event=${parsed%%"$LF"*}
rest=${parsed#*"$LF"}
payload_cwd=${rest%%"$LF"*}
rest=${rest#*"$LF"}
name=${rest%%"$LF"*}
rest=${rest#*"$LF"}
worktree_path=${rest%"$LF"}

# --- shared preconditions -------------------------------------------------------------------

require_home() { # boundary 15
  [ -n "${HOME:-}" ] || fail "\$HOME is unset or empty. The centralized worktree store is defined as ~/.worktrees, and with no \$HOME there is no path to build it at. Fix the environment this session was launched with."
}

require_git() {
  local git_version version major minor tail_version
  command -v git >/dev/null 2>&1 || fail "no git on PATH, so this hook could not resolve or act on any repository."
  git_version=$(git --version 2>/dev/null) || fail "git --version failed, so its version could not be checked against the floor ($FLOOR)."
  version=${git_version#git version }
  major=${version%%.*}
  tail_version=${version#*.}
  minor=${tail_version%%.*}
  case "$major" in ''|*[!0-9]*) fail "git's version could not be parsed from '$git_version' (floor: $FLOOR)." ;; esac
  case "$minor" in ''|*[!0-9]*) fail "git's version could not be parsed from '$git_version' (floor: $FLOOR)." ;; esac
  if [ "$major" -lt "$FLOOR_MAJOR" ] ||
     { [ "$major" -eq "$FLOOR_MAJOR" ] && [ "$minor" -lt "$FLOOR_MINOR" ]; }; then
    fail "git is older than $FLOOR ($git_version). This hook resolves repository roots with --path-format=absolute, which requires it. Install git >= $FLOOR."
  fi
}

require_git

# --- step 2: dispatch on the event -----------------------------------------------------------

case "$event" in
  WorktreeCreate)
    # ==========================================================================================
    # WorktreeCreate
    # ==========================================================================================
    [ -n "$name" ] || fail "the payload carried no worktree name, so no branch could be chosen and nothing was created."

    require_home

    # Boundary 16. Resolved from the payload's cwd and NOTHING else (task 1b: "the safe rule —
    # build only on cwd and name"). No fallback to a session-relative guess: with no repository
    # under cwd there is no <repo-name> segment and no repository to add a worktree to.
    repo_root=$(git -C "$payload_cwd" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)
    rt_rc=$?
    if [ "$rt_rc" -ne 0 ] || [ -z "$repo_root" ]; then
      fail "the repository root could not be resolved from cwd.

  cwd: $payload_cwd

Nothing was created."
    fi

    repo_name=$(basename "$repo_root")
    store="${HOME%/}/$STORE_REL/$repo_name"

    # Boundaries 17/18. ~/.worktrees will hold working copies of every repo on this machine,
    # including any secrets those trees carry, so a directory this hook creates starts at
    # owner-only — and a directory that already exists wider than that is refused rather than
    # silently re-chmod'd, in case the user widened it on purpose.
    ensure_dir_0700() { # $1 path, $2 what it is (for the message)
      local path="$1" what="$2" mode_ok err
      if [ -e "$path" ]; then
        if [ ! -d "$path" ]; then
          fail "$what exists but is not a directory: $path. Nothing was created."
        fi
        mode_ok=$("$py" -c '
import os, sys
m = os.stat(sys.argv[1]).st_mode & 0o777
sys.exit(0 if (m & 0o077) == 0 else 1)
' "$path" && printf ok || printf no)
        if [ "$mode_ok" != ok ]; then
          fail "$what already exists with a group or other permission bit set.

  path: $path

Never silently re-chmod a directory you may have widened on purpose — fix it by hand:

  chmod 700 $path"
        fi
        return 0
      fi
      if ! err=$(mkdir -m 700 "$path" 2>&1); then
        fail "creating $what failed.

  mkdir -m 700 $path
  error: $err"
      fi
    }
    ensure_dir_0700 "${HOME%/}/$STORE_REL" "the centralized worktree store"
    ensure_dir_0700 "$store" "this repository's worktree directory"

    # Boundaries 19/20 — the basename-collision check. Two repositories named the same would
    # otherwise share one store directory silently; the marker is what makes that a refusal
    # instead. Arm B2 (worktree-guard.sh) only ever reads this file; this hook is the one that
    # writes it, on a store's first use.
    marker="$store/$MARKER_NAME"
    if [ -e "$marker" ]; then
      if IFS= read -r marker_root < "$marker" 2>/dev/null && [ -n "$marker_root" ]; then
        if [ "$marker_root" != "$repo_root" ]; then
          fail "the centralized store for repository name '$repo_name' already belongs to a different repository.

  store:        $store/
  marked for:   $marker_root
  this repo is: $repo_root

Nothing was created."
        fi
      else
        fail "the .repo-root marker exists but could not be read.

  marker: $marker

An unreadable marker is an UNDETERMINED collision, not an absent one — proceeding would risk
two repositories sharing one store silently. Fix its permissions or its contents. Nothing was
created."
      fi
    else
      if ! printf '%s\n' "$repo_root" > "$marker" 2>/dev/null; then
        fail "the .repo-root marker could not be written.

  marker: $marker

Nothing was created."
      fi
    fi

    # Branch/base contract (card, "Branch and base selection"). Branch name is the payload's
    # name VERBATIM — the managed path's worktree-<name> rename is a deliberate non-goal here
    # (memory reference_enterworktree_renames_the_branch_you_asked_for). Base ref is
    # origin/HEAD, resolved via symbolic-ref; an unresolvable base FAILS rather than falling
    # back to local HEAD, which is exactly how a worktree ends up based on whatever branch the
    # primary checkout happened to be parked on (the incident this whole feature exists to stop).
    branch=$name
    path="$store/$name"

    if git -C "$repo_root" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1; then
      # Boundary 22 — not a failure. Reuse the existing branch: never -b over it, never force.
      add_stderr=$(git -C "$repo_root" worktree add "$path" "$branch" 2>&1 1>/dev/null)
      add_rc=$?
    else
      # Boundary 23.
      base_ref=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)
      base_rc=$?
      if [ "$base_rc" -ne 0 ] || [ -z "$base_ref" ]; then
        fail "the base ref refs/remotes/origin/HEAD could not be resolved for this repository, so no worktree was created.

  repository: $repo_root
  tried:      refs/remotes/origin/HEAD

Falling back to local HEAD is exactly how a worktree ends up based on whatever branch the
primary checkout happened to be parked on. Set the remote's HEAD (git remote set-head origin
-a) and retry."
      fi
      add_stderr=$(git -C "$repo_root" worktree add -b "$branch" "$path" "$base_ref" 2>&1 1>/dev/null)
      add_rc=$?
    fi

    # Boundary 21.
    if [ "$add_rc" -ne 0 ]; then
      fail "git worktree add failed.

  git said: $add_stderr

Nothing was created."
    fi

    # Boundary 25 — create and report ATOMICALLY. A create-then-misreport leaves an orphan
    # registered in git worktree list (observed twice during the task 1b probe). Any failure
    # from this point on must clean up the worktree it just created before this hook exits.
    final_path=$(cd "$path" 2>/dev/null && pwd -P) || final_path=""
    if [ -z "$final_path" ]; then
      git -C "$repo_root" worktree remove "$path" >/dev/null 2>&1
      fail "git worktree add succeeded but the new worktree's absolute path could not be resolved afterward, so it was removed to avoid leaving an orphan.

  path: $path"
    fi
    if ! printf '%s\n' "$final_path"; then
      git -C "$repo_root" worktree remove "$path" >/dev/null 2>&1
      fail "git worktree add succeeded but the path could not be written to stdout, so the worktree was removed to avoid leaving an orphan.

  path: $final_path"
    fi
    exit 0
    ;;

  WorktreeRemove)
    # ==========================================================================================
    # WorktreeRemove
    # ==========================================================================================
    [ -n "$worktree_path" ] || fail "the payload carried no worktree_path, so there was nothing to remove."

    main_common_dir=$(git -C "$worktree_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    mc_rc=$?
    if [ "$mc_rc" -ne 0 ] || [ -z "$main_common_dir" ]; then
      fail "the repository owning this worktree could not be resolved, so nothing was removed.

  worktree_path: $worktree_path"
    fi
    main_root=$(dirname "$main_common_dir")

    # Boundary 26 — refuse rather than force. git worktree remove declines a dirty worktree on
    # its own, but its own message does not NAME the dirty paths; this hook checks first so the
    # refusal does. Claude reports "Exited and removed worktree at …" regardless (measured,
    # card Non-goals) — between a stale directory and silently destroyed uncommitted work, the
    # stale directory is recoverable, so this hook never passes --force.
    dirty=$(git -C "$worktree_path" status --porcelain 2>/dev/null)
    if [ -n "$dirty" ]; then
      fail "refused — this worktree has uncommitted changes:

$dirty

  worktree_path: $worktree_path

git worktree remove declines a dirty worktree without --force, and this hook never passes
--force. Commit, stash, or discard the changes above, then retry."
    fi

    # The branch this worktree has checked out, captured BEFORE removal — the worktree is
    # gone afterward and there is nothing left to ask. Empty means detached HEAD; nothing to
    # delete. There is no persisted record of whether this hook created the branch or reused
    # one that already existed (each invocation is a separate process, same as every other
    # hook in this card) — see the report for the judgment call this makes.
    branch=$(git -C "$worktree_path" symbolic-ref --short -q HEAD 2>/dev/null) || branch=""

    # Boundary 24 — on failure, leave the directory in place. Never rm -rf a path git declined
    # to remove.
    remove_stderr=$(git -C "$main_root" worktree remove "$worktree_path" 2>&1 1>/dev/null)
    remove_rc=$?
    if [ "$remove_rc" -ne 0 ]; then
      fail "git worktree remove failed — the directory is left in place.

  worktree_path: $worktree_path
  git said:       $remove_stderr"
    fi

    # Boundary 27. Claude performs no cleanup of its own on the hook path (measured, task 1b
    # open question 9) — anything skipped here is left behind while the session is told it was
    # removed. Non-fatal: the worktree is already gone by this point, so a failed branch
    # delete is surfaced on stderr rather than turned into a false "removal failed".
    if [ -n "$branch" ]; then
      branch_stderr=$(git -C "$main_root" branch -D "$branch" 2>&1 1>/dev/null)
      branch_rc=$?
      if [ "$branch_rc" -ne 0 ]; then
        printf '%s %s\n' "$PREFIX" "the worktree was removed, but its branch could not be deleted.

  branch:   $branch
  git said: $branch_stderr" 1>&2
      fi
    fi
    exit 0
    ;;

  *)
    fail "the payload's hook_event_name ('$event') is neither WorktreeCreate nor WorktreeRemove, so this hook could not identify what was being asked. Nothing was created or removed."
    ;;
esac
