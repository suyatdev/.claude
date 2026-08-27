#!/usr/bin/env bash
# create-worktree.test.sh — unit tests for create-worktree.sh (Arm B: WorktreeCreate /
# WorktreeRemove).
#
# Written BEFORE the hook exists (card task 7, TDD) — the suite's job first is to be red for
# the right reason ("hook not found"), not "assertion never evaluated".
#
# Feeds WorktreeCreate/WorktreeRemove JSON on stdin — the payload shape task 1b measured
# live against Claude Code 2.1.241 — from inside throwaway git repos under $TMP, with $HOME
# redirected so ~/.worktrees is a fixture rather than the real store.
#
# Run: bash hooks/create-worktree.test.sh
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/create-worktree.sh"

# Physical path, not the one mktemp hands back — same reason as worktree-guard.test.sh:26-27.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GIT_REAL="$(command -v git)"
git_q() { "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }

HOME_FIX="$TMP/home"
mkdir -p "$HOME_FIX"

pass=0; fail=0; skip=0; n=0

ok()      { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad()     { printf 'FAIL — %s\n' "$1"; fail=$((fail+1)); }
skipped() { printf 'skip — %s\n' "$1"; skip=$((skip+1)); }

# ---------------------------------------------------------------- payloads ---

payload_create() { # $1 name, $2 cwd, [$3 session_id]
  python3 -c 'import json,sys
d={"hook_event_name":"WorktreeCreate","cwd":sys.argv[2],"name":sys.argv[1]}
if len(sys.argv)>3: d["session_id"]=sys.argv[3]
print(json.dumps(d))' "$@"
}

payload_remove() { # $1 worktree_path, $2 cwd, [$3 session_id]
  python3 -c 'import json,sys
d={"hook_event_name":"WorktreeRemove","cwd":sys.argv[2],"worktree_path":sys.argv[1]}
if len(sys.argv)>3: d["session_id"]=sys.argv[3]
print(json.dumps(d))' "$@"
}

payload_create_noname() { # $1 cwd
  python3 -c 'import json,sys
print(json.dumps({"hook_event_name":"WorktreeCreate","cwd":sys.argv[1]}))' "$1"
}

payload_remove_nopath() { # $1 cwd
  python3 -c 'import json,sys
print(json.dumps({"hook_event_name":"WorktreeRemove","cwd":sys.argv[1]}))' "$1"
}

# ----------------------------------------------------------------- runner ---

RUN_ENV=()
got=0; out=""; err=""
_run() { # $1 payload text — exit code in $got, streams in $out/$err
  n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
  printf '%s' "$1" | env \
    HOME="$HOME_FIX" \
    ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
    bash "$HOOK" >"$out" 2>"$err"
  got=$?
  RUN_ENV=()
}

# Same shape as $out/$err above, for the one case (C-atomic) that closes stdout itself.
_run_closed_stdout() { # $1 payload text
  n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
  : > "$out"
  printf '%s' "$1" | env HOME="$HOME_FIX" bash "$HOOK" 1>&- 2>"$err"
  got=$?
}

assert_exit()  { # $1 desc, $2 expected code
  [ "$got" = "$2" ] && { ok "$1"; return; }
  bad "$1 (exit $got, wanted $2; stderr: $(cat "$err"))"
}
assert_stdout_empty() { # $1 desc
  if [ -s "$out" ]; then
    bad "$1 (stdout was NOT empty: $(cat "$out"))"
  else
    ok "$1"
  fi
}
assert_stderr_has() { # $1 desc, $2 required substring
  if grep -qF -- "$2" "$err"; then
    ok "$1"
  else
    bad "$1 (missing substring '$2'; stderr: $(cat "$err"))"
  fi
}
assert_stdout_last_line() { # $1 desc, $2 expected last non-empty line
  local got_line
  got_line=$(awk 'NF{l=$0} END{print l}' "$out")
  if [ "$got_line" = "$2" ]; then
    ok "$1"
  else
    bad "$1 (last stdout line '$got_line', wanted '$2')"
  fi
}

# A refusal must fail closed: exit 1, no stdout, stderr names the reason.
fail_case() { # $1 desc, $2 payload text, $3 required stderr substring
  _run "$2"
  assert_exit "$1 — exit 1" 1
  assert_stdout_empty "$1 — no stdout"
  assert_stderr_has "$1 — stderr names it" "$3"
}

# ================================================================= FIXTURES ==

# A primary repo with a resolvable origin/HEAD, built WITHOUT a real remote —
# refs/remotes/origin/HEAD is fabricated directly so symbolic-ref resolves it with no
# network. mkdir -p -m 700 is per-level (ensure_dir_0700 checks each level's own perms).
mk_primary_repo() { # $1 path
  local repo="$1"
  mkdir -p "$repo"
  ( cd "$repo" && git_q init -q && printf x > f.txt && git_q add f.txt && git_q commit -q -m init )
  ( cd "$repo" && git_q update-ref refs/remotes/origin/main refs/heads/main )
  ( cd "$repo" && git_q symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main )
}

STORE_ROOT="$HOME_FIX/.worktrees"

reset_home() {
  rm -rf "$HOME_FIX"
  mkdir -p "$HOME_FIX"
}

# Each case that wants an ordinary primary repo gets its own, under a fresh parent — never
# the same "$TMP/repos/proj" directory reused across cases. Reuse was tried first and broke
# silently: a worktree or branch left behind by an EARLIER case (a stale `feat-x` worktree
# registration, an existing `feat-x` branch) made a LATER case's `git worktree add` fail for
# a reason that had nothing to do with what that case was testing. The basename stays "proj"
# so assertions against $STORE_ROOT/proj/... keep reading naturally.
REPO_N=0
PRIMARY=""
fresh_primary() {
  REPO_N=$((REPO_N+1))
  PRIMARY="$TMP/repos/r$REPO_N/proj"
  mk_primary_repo "$PRIMARY"
}

# ================================================================= GROUP P ===
# General preconditions shared by both events.

reset_home
_run ''
fail_case 'P1 empty stdin' '' 'this hook payload could not be read'

n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
printf 'not json' | env HOME="$HOME_FIX" bash "$HOOK" >"$out" 2>"$err"
got=$?
assert_exit 'P2 unparseable JSON — exit 1' 1
assert_stdout_empty 'P2 unparseable JSON — no stdout'
assert_stderr_has 'P2 unparseable JSON — stderr names it' 'could not be read as JSON'

fresh_primary

n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
printf '%s' "$(payload_create feat-x "$PRIMARY")" | \
  python3 -c 'import json,sys
d=json.loads(sys.stdin.read()); d["hook_event_name"]="SomeOtherEvent"; print(json.dumps(d))' | \
  env HOME="$HOME_FIX" bash "$HOOK" >"$out" 2>"$err"
got=$?
assert_exit 'P3 unrecognized hook_event_name — exit 1' 1
assert_stdout_empty 'P3 unrecognized hook_event_name — no stdout'
assert_stderr_has 'P3 unrecognized hook_event_name — stderr names it' 'neither WorktreeCreate nor WorktreeRemove'

# ================================================================= GROUP C ===
# WorktreeCreate.

# C1 — first worktree for a repo (Arm B contract; boundaries 17/19/22 non-failure paths).
reset_home
fresh_primary
_run "$(payload_create feat-x "$PRIMARY" s-c1)"
assert_exit 'C1 first worktree — exit 0' 0
assert_stdout_last_line 'C1 first worktree — stdout path' "$STORE_ROOT/proj/feat-x"
if [ -d "$STORE_ROOT/proj/feat-x" ]; then ok 'C1 …the directory exists'; else bad 'C1 …the directory exists'; fi
mode=$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$HOME_FIX/.worktrees" 2>/dev/null)
[ "$mode" = 0o700 ] && ok 'C1 …~/.worktrees is mode 700' || bad "C1 …~/.worktrees is mode 700 (got $mode)"
mode=$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$STORE_ROOT/proj" 2>/dev/null)
[ "$mode" = 0o700 ] && ok 'C1 …the per-repo store is mode 700' || bad "C1 …the per-repo store is mode 700 (got $mode)"
if [ -f "$STORE_ROOT/proj/.repo-root" ] && [ "$(cat "$STORE_ROOT/proj/.repo-root")" = "$PRIMARY" ]; then
  ok 'C1 ….repo-root marker names the repo root'
else
  bad 'C1 ….repo-root marker names the repo root'
fi
if ( cd "$PRIMARY" && git_q worktree list --porcelain | grep -qF "worktree $STORE_ROOT/proj/feat-x" ); then
  ok 'C1 …git worktree list registers it'
else
  bad 'C1 …git worktree list registers it'
fi
if ( cd "$STORE_ROOT/proj/feat-x" && git_q symbolic-ref --short HEAD ) | grep -qx feat-x; then
  ok 'C1 …the branch is feat-x, verbatim'
else
  bad 'C1 …the branch is feat-x, verbatim'
fi

# C2 — the store has been widened (boundary 18).
reset_home
fresh_primary
mkdir -p "$STORE_ROOT" && chmod 755 "$STORE_ROOT"
fail_case 'C2 store widened (755)' "$(payload_create feat-x "$PRIMARY")" 'chmod 700'
chmod 700 "$STORE_ROOT"

# C3 — the per-repo directory has been widened, store itself correct (boundary 18, the
# discriminating value 750 — group-read only, neither the "world-readable" nor
# "world-writable" case).
reset_home
fresh_primary
mkdir -p -m 700 "$STORE_ROOT"
mkdir -p -m 750 "$STORE_ROOT/proj"
fail_case 'C3 per-repo dir widened (750)' "$(payload_create feat-x "$PRIMARY")" "chmod 700 $STORE_ROOT/proj"

# C4 — git worktree add fails on its own (boundary 21): pre-create the destination as a
# non-empty plain directory so git refuses it.
reset_home
fresh_primary
mkdir -p -m 700 "$STORE_ROOT"
mkdir -p -m 700 "$STORE_ROOT/proj"
mkdir -p "$STORE_ROOT/proj/feat-x" && printf junk > "$STORE_ROOT/proj/feat-x/junk"
fail_case 'C4 git worktree add fails' "$(payload_create feat-x "$PRIMARY")" 'git worktree add failed'
assert_stderr_has 'C4 …quotes git'"'"'s error' 'git said:'

# C5/C6 — HOME carries no usable value (boundary 15).
reset_home
fresh_primary
n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
( unset HOME; printf '%s' "$(payload_create feat-x "$PRIMARY")" | env -u HOME bash "$HOOK" >"$out" 2>"$err" )
got=$?
assert_exit 'C5 HOME unset — exit 1' 1
assert_stdout_empty 'C5 HOME unset — no stdout'
assert_stderr_has 'C5 HOME unset — stderr names it' 'HOME is unset or empty'
if [ ! -d "/.worktrees" ]; then ok 'C5 …no directory created at /.worktrees'; else bad 'C5 …no directory created at /.worktrees'; fi

n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
printf '%s' "$(payload_create feat-x "$PRIMARY")" | env HOME='' bash "$HOOK" >"$out" 2>"$err"
got=$?
assert_exit 'C6 HOME empty — exit 1' 1
assert_stdout_empty 'C6 HOME empty — no stdout'
assert_stderr_has 'C6 HOME empty — stderr names it' 'HOME is unset or empty'

# C7 — the payload's cwd is not inside a git repository (boundary 16).
reset_home
SCRATCH="$TMP/scratch"; mkdir -p "$SCRATCH"
fail_case 'C7 cwd outside any repo' "$(payload_create feat-x "$SCRATCH")" 'repository root could not be resolved'

# C8 — mkdir of the store fails: ~/.worktrees exists as a regular FILE (boundary 17).
reset_home
fresh_primary
printf 'not a directory' > "$STORE_ROOT"
fail_case 'C8 store path is a plain file' "$(payload_create feat-x "$PRIMARY")" 'exists but is not a directory'
rm -f "$STORE_ROOT"

# C9/C10 — the .repo-root marker cannot be read or written (boundary 19). Ordering: git
# worktree add must never run — checked via git worktree list on the primary repo.
reset_home
fresh_primary
mkdir -p -m 700 "$STORE_ROOT"
mkdir -p -m 700 "$STORE_ROOT/proj"
chmod 500 "$STORE_ROOT/proj"   # writable-by-owner bit off; still owner-only (0500 & 0o077 == 0)
fail_case 'C9 marker cannot be written (dir read-only)' "$(payload_create feat-x "$PRIMARY")" '.repo-root marker'
chmod 700 "$STORE_ROOT/proj"
if ( cd "$PRIMARY" && git_q worktree list --porcelain | grep -qF "worktree $STORE_ROOT/proj/feat-x" ); then
  bad 'C9 …git worktree add never ran'
else
  ok 'C9 …git worktree add never ran'
fi

reset_home
fresh_primary
mkdir -p -m 700 "$STORE_ROOT"
mkdir -p -m 700 "$STORE_ROOT/proj"
printf '%s\n' "$PRIMARY" > "$STORE_ROOT/proj/.repo-root"
chmod 000 "$STORE_ROOT/proj/.repo-root"
fail_case 'C10 marker exists but cannot be read' "$(payload_create feat-x "$PRIMARY")" '.repo-root marker'
chmod 700 "$STORE_ROOT/proj/.repo-root"

# C11 — the marker names a different repo root: a basename collision (boundary 20).
reset_home
A="$TMP/orgs/a/proj"; B="$TMP/orgs/b/proj"
mk_primary_repo "$A"
mk_primary_repo "$B"
_run "$(payload_create feat-a "$A")"
assert_exit 'C11 setup: first repo claims the store' 0
fail_case 'C11 second repo, same basename, collides' "$(payload_create feat-b "$B")" "$A"
assert_stderr_has 'C11 …names the second root too' "$B"
if [ -e "$STORE_ROOT/proj/feat-b" ]; then bad 'C11 …no worktree added for the colliding repo'; else ok 'C11 …no worktree added for the colliding repo'; fi

# C12 — the requested branch already exists: reuse it (boundary 22, not a failure).
reset_home
fresh_primary
( cd "$PRIMARY" && git_q branch feat-x )
before_sha=$( cd "$PRIMARY" && git_q rev-parse feat-x )
_run "$(payload_create feat-x "$PRIMARY")"
assert_exit 'C12 reuse existing branch — exit 0' 0
assert_stdout_last_line 'C12 reuse existing branch — stdout path' "$STORE_ROOT/proj/feat-x"
after_sha=$( cd "$PRIMARY" && git_q rev-parse feat-x )
[ "$before_sha" = "$after_sha" ] && ok 'C12 …the branch was not moved (no -b, no --force)' || bad 'C12 …the branch was not moved (no -b, no --force)'

# C13 — the base ref cannot be resolved (boundary 23): a repo with no origin/HEAD at all,
# requesting a NEW branch name.
reset_home
NOORIGIN="$TMP/repos/noorigin"
mkdir -p "$NOORIGIN"
( cd "$NOORIGIN" && git_q init -q && printf x > f.txt && git_q add f.txt && git_q commit -q -m init )
before_branches=$( cd "$NOORIGIN" && git_q branch --list | wc -l | tr -d ' ')
fail_case 'C13 base ref unresolvable' "$(payload_create feat-new "$NOORIGIN")" 'refs/remotes/origin/HEAD'
after_branches=$( cd "$NOORIGIN" && git_q branch --list | wc -l | tr -d ' ')
[ "$before_branches" = "$after_branches" ] && ok 'C13 …no branch was created from local HEAD' || bad 'C13 …no branch was created from local HEAD'

# C14 — atomic create-and-report (boundary 25): git worktree add succeeds, but the report
# step fails (stdout closed) — the hook must clean up the worktree it just created.
reset_home
fresh_primary
_run_closed_stdout "$(payload_create feat-x "$PRIMARY")"
assert_exit 'C14 report fails after add succeeds — exit 1' 1
assert_stderr_has 'C14 …stderr says it cleaned up' 'removed to avoid leaving an orphan'
if ( cd "$PRIMARY" && git_q worktree list --porcelain | grep -qF "worktree $STORE_ROOT/proj/feat-x" ); then
  bad 'C14 …git worktree list registers no orphan'
else
  ok 'C14 …git worktree list registers no orphan'
fi
if [ -d "$STORE_ROOT/proj/feat-x" ]; then bad 'C14 …the directory was removed'; else ok 'C14 …the directory was removed'; fi

# C15 — the payload carries no name at all: nothing to build a branch or a path from.
reset_home
fresh_primary
fail_case 'C15 payload has no name' "$(payload_create_noname "$PRIMARY")" 'no worktree name'

# ================================================================= GROUP R ===
# WorktreeRemove.

# R1 — refuse on a dirty worktree (boundary 26): --force never passed, directory stays.
reset_home
fresh_primary
_run "$(payload_create feat-x "$PRIMARY")"
WT="$STORE_ROOT/proj/feat-x"
printf 'dirty\n' >> "$WT/f.txt"
fail_case 'R1 WorktreeRemove on dirty worktree' "$(payload_remove "$WT" "$PRIMARY")" 'f.txt'
assert_stderr_has 'R1 …the refusal names the uncommitted-changes contract' 'uncommitted changes'
if [ -d "$WT" ]; then ok 'R1 …the directory is left in place'; else bad 'R1 …the directory is left in place'; fi
if ( cd "$PRIMARY" && git_q worktree list --porcelain | grep -qF "worktree $WT" ); then
  ok 'R1 …git worktree list still registers it'
else
  bad 'R1 …git worktree list still registers it'
fi

# R2 — WorktreeRemove succeeds: the worktree AND the branch it created are both gone
# (boundary 27 — "the branch assertion is the half most likely to be dropped").
reset_home
fresh_primary
_run "$(payload_create feat-x "$PRIMARY")"
WT="$STORE_ROOT/proj/feat-x"
_run "$(payload_remove "$WT" "$PRIMARY")"
assert_exit 'R2 clean WorktreeRemove — exit 0' 0
if [ -d "$WT" ]; then bad 'R2 …the directory is gone'; else ok 'R2 …the directory is gone'; fi
if ( cd "$PRIMARY" && git_q worktree list --porcelain | grep -qF "worktree $WT" ); then
  bad 'R2 …git worktree list registers no entry'
else
  ok 'R2 …git worktree list registers no entry'
fi
if ( cd "$PRIMARY" && git_q rev-parse --verify --quiet refs/heads/feat-x >/dev/null 2>&1 ); then
  bad 'R2 …the branch feat-x is deleted'
else
  ok 'R2 …the branch feat-x is deleted'
fi

# R3 — git worktree remove fails (boundary 24): locked, not dirty. Directory left in place.
reset_home
fresh_primary
_run "$(payload_create feat-x "$PRIMARY")"
WT="$STORE_ROOT/proj/feat-x"
( cd "$PRIMARY" && git_q worktree lock "$WT" )
fail_case 'R3 git worktree remove fails (locked)' "$(payload_remove "$WT" "$PRIMARY")" 'git worktree remove failed'
if [ -d "$WT" ]; then ok 'R3 …the directory is left in place'; else bad 'R3 …the directory is left in place'; fi
( cd "$PRIMARY" && git_q worktree unlock "$WT" ) >/dev/null 2>&1

# R4 — the payload carries no worktree_path.
reset_home
fresh_primary
fail_case 'R4 payload has no worktree_path' "$(payload_remove_nopath "$PRIMARY")" 'no worktree_path'

# R5 — worktree_path does not resolve to any repository.
reset_home
NOTAREPO="$TMP/not-a-repo"; mkdir -p "$NOTAREPO"
fail_case 'R5 worktree_path outside any repo' "$(payload_remove "$NOTAREPO" "$TMP")" 'could not be resolved'

# R6 — a detached-HEAD worktree: nothing to delete, and that is not an error.
reset_home
fresh_primary
DETACHED="$TMP/detached-wt"
( cd "$PRIMARY" && git_q worktree add -q --detach "$DETACHED" main )
_run "$(payload_remove "$DETACHED" "$PRIMARY")"
assert_exit 'R6 detached-HEAD WorktreeRemove — exit 0' 0
if [ -d "$DETACHED" ]; then bad 'R6 …the directory is gone'; else ok 'R6 …the directory is gone'; fi

# ------------------------------------------------------------------ summary ---

printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
