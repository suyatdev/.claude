#!/usr/bin/env bash
# worktree-guard.probe.sh — what worktree-guard.sh actually does in its
# precondition failure states, measured rather than read off the source.
#
# WHY THIS EXISTS. Nine of the guard's refusal messages either claimed, or were
# silent about, "settings.json is exempt from this guard, so the hook
# registration and its WORKTREE_GUARD_MODE switch stay editable." That sentence
# is a recoverability promise: whatever else is broken, you can still reach the
# switch that turns the guard off. Task 17 enumerated the population at six
# sites firing before the exemption list is ever consulted (worktree-guard.sh,
# Step A4 as of that task) — the two E1/E2 already measured below, plus E6-E9
# added by that task: no enterable ancestor, an unrecognized --show-toplevel
# diagnostic, an empty --show-toplevel, and a failed submodule probe. This
# script constructs each state on its own and prints what happened, so the
# written record cites a run rather than a reading.
#
# It is a PROBE, not a test: it asserts nothing and always exits 0 (unless the
# fixture itself cannot be built). Read the table. The suite that does assert is
# hooks/worktree-guard.test.sh.
#
# Run: bash hooks/worktree-guard.probe.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/worktree-guard.sh"
[ -r "$HOOK" ] || { printf 'probe: %s is not readable\n' "$HOOK" >&2; exit 1; }

# Physical form, for the same reason the suite takes it: on macOS `mktemp -d`
# hands back the /var symlink while git resolves to /private/var, so a fixture
# path built from the symlink form never compares equal to what the guard reads.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GIT_REAL="$(command -v git)"

HOME_FIX="$TMP/home"
STATE_DIR="$TMP/state"
mkdir -p "$HOME_FIX/.worktrees" "$STATE_DIR"
chmod 700 "$HOME_FIX/.worktrees"

git_q() { git "$@" >/dev/null 2>&1; }

# A primary checkout named .claude, so the fixture matches the repository the
# guard was written for and a non-exempt write there is genuinely refusable.
PRIMARY="$TMP/repos/.claude"
mkdir -p "$PRIMARY"
git_q -C "$PRIMARY" init -q
git_q -C "$PRIMARY" commit -q --allow-empty -m init
mkdir -p "$PRIMARY/hooks" "$PRIMARY/panes" "$PRIMARY/docs" "$PRIMARY/rules"
: > "$PRIMARY/panes/run-pane-agent.sh"
: > "$PRIMARY/settings.json"

# --- stubs ---------------------------------------------------------------------

# A `git` shim ahead of the real one, bending --version and (task 17) three more
# probes on their own knobs, each independent so a state bends exactly one thing:
# STUB_TOPLEVEL_DIAG (an unrecognized --show-toplevel diagnostic, rc=128),
# STUB_TOPLEVEL_EMPTY (--show-toplevel exits 0 printing nothing), STUB_SUPER_FAIL
# (the submodule probe exits non-zero). Everything else is handed straight
# through, so each state differs from a healthy run in exactly one probe.
mk_git_stub() {
  mkdir -p "$TMP/stub"
  cat > "$TMP/stub/git" <<STUB
#!/bin/sh
if [ "\$1" = "--version" ] && [ -n "\${STUB_VERSION:-}" ]; then
  printf '%s\n' "\$STUB_VERSION"; exit 0
fi
for a in "\$@"; do
  case "\$a" in
    --show-toplevel)
      [ -n "\${STUB_TOPLEVEL_DIAG:-}" ] && { printf '%s\n' "\$STUB_TOPLEVEL_DIAG" >&2; exit 128; }
      [ "\${STUB_TOPLEVEL_EMPTY:-}" = 1 ] && exit 0
      ;;
    --show-superproject-working-tree)
      [ "\${STUB_SUPER_FAIL:-}" = 1 ] && exit 1
      ;;
  esac
done
exec "$GIT_REAL" "\$@"
STUB
  chmod +x "$TMP/stub/git"
  printf '%s' "$TMP/stub:$PATH"
}

# A PATH of symlinks to everything except the named basenames.
mk_shadow_path() { # $1 dir name, $2.. basenames to leave out
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

# --- payloads ------------------------------------------------------------------

payload_write() { # $1 path
  python3 -c 'import json,sys
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Write",
                  "tool_input":{"file_path":sys.argv[1]},"session_id":"probe"}))' "$1"
}
payload_bash() { # $1 command
  python3 -c 'import json,sys
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Bash",
                  "tool_input":{"command":sys.argv[1]},"session_id":"probe"}))' "$1"
}

# --- runner --------------------------------------------------------------------

CLAIM='settings.json is exempt from this guard'

n=0
run() { # $1 label, $2 payload, $3.. env assignments (HOME=@UNSET drops HOME)
  local label="$1" payload="$2"; shift 2
  n=$((n+1))
  local errf="$TMP/err.$n" outf="$TMP/out.$n"
  # HOME is added LAST-but-conditionally: `env -u HOME HOME=/fix` re-sets what the
  # -u removed, so an unset case must never put the assignment on the line at all.
  # The first version of this probe did, and every $HOME-unset row silently
  # measured a healthy guard instead.
  local -a envv=(WORKTREE_GUARD_STATE_DIR="$STATE_DIR" WORKTREE_GUARD_MODE=deny)
  local -a unsets=() a
  local drop_home=0
  for a in "$@"; do
    case "$a" in
      HOME=@UNSET) drop_home=1; unsets+=(-u HOME) ;;
      *) envv+=("$a") ;;
    esac
  done
  [ "$drop_home" = 0 ] && envv+=(HOME="$HOME_FIX")
  ( cd "$PRIMARY" && printf '%s' "$payload" |
      env ${unsets[@]+"${unsets[@]}"} "${envv[@]}" bash "$HOOK" ) >"$outf" 2>"$errf"
  local rc=$?
  # Whitespace-normalized, because the messages are hard-wrapped and the claim
  # straddles a line break in require_home() but not in deny_version(). A plain
  # `grep -F` on the raw file reported "claim not printed" for the one arm whose
  # claim matters most — a wrapping artefact reading as a substantive difference.
  local claim=no
  tr '\n' ' ' < "$errf" | tr -s ' ' | grep -qF -- "$CLAIM" && claim=yes
  local first; first=$(head -1 "$errf")
  [ -z "$first" ] && first='(no stderr)'
  # Trimmed to the distinguishing clause; the full text is in err.N.
  first=${first#worktree-guard: }
  printf '  [%2d] rc=%-2s claim-printed=%-3s  %-30s  %s\n' \
    "$n" "$rc" "$claim" "$label" "${first:0:74}"
}

printf 'worktree-guard.probe.sh — mode=deny, cwd=%s (a PRIMARY checkout)\n' "$PRIMARY"
printf 'claim-printed = the refusal text contains "%s"\n\n' "$CLAIM"

W_EXEMPT="$(payload_write "$PRIMARY/settings.json")"
W_GUARDED="$(payload_write "$PRIMARY/panes/run-pane-agent.sh")"
# `git switch main` is Arm D's canonical refusable command; `git status` is
# allowed even by a healthy guard, so it cannot tell "the arm ran and allowed"
# from "no arm ran at all".
B_SWITCH="$(payload_bash 'git switch main')"
B_STATUS="$(payload_bash 'git status')"

printf 'E0 healthy — the control, so every later row is read against a guard that works\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"
run 'Write panes/... (guarded)'      "$W_GUARDED"
run 'Bash: git switch main'          "$B_SWITCH"
printf '\n'

printf 'E1 $HOME unset — require_home()\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"   HOME=@UNSET
run 'Write panes/... (guarded)'      "$W_GUARDED"  HOME=@UNSET
run 'Bash: git switch main'          "$B_SWITCH"   HOME=@UNSET
run 'Bash + WORKTREE_EXEMPT'         "$B_SWITCH"   HOME=@UNSET WORKTREE_EXEMPT=probe
printf '\n'

GIT_STUB_PATH="$(mk_git_stub)"
OLD='git version 2.30.0'
printf 'E2 git below the version floor — deny_version()\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"   PATH="$GIT_STUB_PATH" STUB_VERSION="$OLD"
run 'Write panes/... (guarded)'      "$W_GUARDED"  PATH="$GIT_STUB_PATH" STUB_VERSION="$OLD"
run 'Bash: git switch main'          "$B_SWITCH"   PATH="$GIT_STUB_PATH" STUB_VERSION="$OLD"
run 'Bash + WORKTREE_EXEMPT'         "$B_SWITCH"   PATH="$GIT_STUB_PATH" STUB_VERSION="$OLD" WORKTREE_EXEMPT=probe
printf '\n'

printf 'E3 the lib dir is missing — deny_arms()\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"   WORKTREE_GUARD_LIB="$TMP/nolib"
run 'Write panes/... (guarded)'      "$W_GUARDED"  WORKTREE_GUARD_LIB="$TMP/nolib"
run 'Bash: git switch main'          "$B_SWITCH"   WORKTREE_GUARD_LIB="$TMP/nolib"
run 'Bash + WORKTREE_EXEMPT'         "$B_SWITCH"   WORKTREE_GUARD_LIB="$TMP/nolib" WORKTREE_EXEMPT=probe
printf '\n'

NOPY="$(mk_shadow_path nopy python3 python)"
printf 'E4 python3 and python shadowed — the recipe the card USED to cite for E1/E2/E3\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"   PATH="$NOPY"
run 'Write panes/... (guarded)'      "$W_GUARDED"  PATH="$NOPY"
printf '\n'

printf 'E5 a mistyped WORKTREE_GUARD_MODE — the cross that 189 green tests missed\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"   WORKTREE_GUARD_MODE=DENY
run 'Write panes/... (guarded)'      "$W_GUARDED"  WORKTREE_GUARD_MODE=DENY
run 'Bash: git switch main'          "$B_SWITCH"   WORKTREE_GUARD_MODE=DENY
printf '\n'

# --- task 17: the four states no earlier probe reached -------------------------
# E6-E8 reuse $GIT_STUB_PATH from E2 above — same stub file, three more knobs.
# All four fire before the repository root is knowable, so — unlike E1/E2 — a
# fixed guard must show claim-printed=no on BOTH rows, exempt and guarded alike;
# there is no repo root to relativize $W_EXEMPT's path against.

printf 'E6 git --show-toplevel emits an unrecognized diagnostic\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"   PATH="$GIT_STUB_PATH" \
  STUB_TOPLEVEL_DIAG='fatal: detected dubious ownership'
run 'Write panes/... (guarded)'      "$W_GUARDED"  PATH="$GIT_STUB_PATH" \
  STUB_TOPLEVEL_DIAG='fatal: detected dubious ownership'
printf '\n'

printf 'E7 git --show-toplevel exits 0 and prints nothing\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"   PATH="$GIT_STUB_PATH" STUB_TOPLEVEL_EMPTY=1
run 'Write panes/... (guarded)'      "$W_GUARDED"  PATH="$GIT_STUB_PATH" STUB_TOPLEVEL_EMPTY=1
printf '\n'

printf 'E8 the submodule probe (--show-superproject-working-tree) exits non-zero\n'
run 'Write settings.json (exempt)'   "$W_EXEMPT"   PATH="$GIT_STUB_PATH" STUB_SUPER_FAIL=1
run 'Write panes/... (guarded)'      "$W_GUARDED"  PATH="$GIT_STUB_PATH" STUB_SUPER_FAIL=1
printf '\n'

printf 'E9 no enterable ancestor of the write target (plain filesystem permissions)\n'
mkdir -p "$TMP/locked/sub"
LOCKED_EXEMPT="$(payload_write "$TMP/locked/sub/settings.json")"
LOCKED_GUARDED="$(payload_write "$TMP/locked/sub/panes/x.sh")"
chmod 000 "$TMP/locked"
run 'Write <unenterable>/settings.json' "$LOCKED_EXEMPT"
run 'Write <unenterable>/panes/x.sh'    "$LOCKED_GUARDED"
chmod 755 "$TMP/locked"
printf '\n'

printf 'Full stderr per row: %s/err.N (N is the bracketed index). Fixture removed on exit.\n' "$TMP"
exit 0
