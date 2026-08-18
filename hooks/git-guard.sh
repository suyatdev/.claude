#!/usr/bin/env bash
#
# git-guard.sh — PreToolUse hook (matcher: Bash).
#
# Two deterministic guards an instruction alone cannot hold under momentum:
#   1. Default-branch commit guard: blocks `git commit` on main/master unless
#      every staged file is CODING_MEMORY.md, under coding-memory/, or a MARKDOWN
#      file under docs/ (the brainstorm-then-branch and documentation exceptions).
#      The docs/ exception is deliberately by file type, not by directory: an
#      executable dropped under docs/ must not inherit a free ride onto main.
#      doc-guard.sh deliberately uses the BROADER `docs/*` for the same directory.
#      The two are not meant to agree: doc-guard asks "did documentation ride along
#      with this commit?", where a diagram or screenshot counts; this guard asks
#      "may this file reach main unreviewed?", where it must not. Do not align them.
#   2. Force-push guard: blocks a bare `git push --force`/`-f` on any branch;
#      allows `--force-with-lease` except when the current branch is main/master.
#      Scope note: this matches `--force`/`-f`/`--force-with-lease` specifically,
#      not the `+refspec` force-push form (`git push origin +main`) — a momentum
#      guardrail, not a security boundary.
#
# Which git command is being run is decided by lib/classify-git-command.py, which
# lexes the command into shell segments. Both guards previously matched a regex
# ANCHORED to the start of the command string, so anything chained — `git add -- x
# && git commit -m y`, the shape this repo uses constantly — never matched and the
# guard body never ran. The hook exited 0 without having evaluated anything, and
# commits reached main that the allowlist forbids. Flags are now judged within the
# segment that owns them: `git push --force && echo --force-with-lease` used to read
# as a leased push and go unblocked, and `git push && echo --force` used to be
# blocked. Shapes still deliberately open are documented in lib/shell_segments.py.
#
# That classifier also absorbs the `rtk git ...` form: the RTK PreToolUse hook
# (registered ahead of this one in settings.json) rewrites plain git commands before
# this guard runs, so the command it sees may already carry an `rtk ` prefix.
#
# Exit 0 = allow (silent). Exit 2 = blocked, reason on stderr.
#
# Fails CLOSED (exit 2) when it cannot inspect the command at all — no python3, or
# an unrunnable classifier. These guards protect against a destructive or
# unreviewable action, so "cannot tell" must not mean "allow"; contrast doc-guard.sh,
# which fails open because a missing note is not worth blocking work over.

set -u

CLASSIFIER="$(cd "$(dirname "$0")" && pwd)/lib/classify-git-command.py"

payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi

[ -n "$payload" ] || exit 0

py=$(command -v python3 || command -v python) || py=""
if [ -z "$py" ]; then
  printf 'git-guard: python3 not on PATH; cannot inspect the command -- failing closed.\n' >&2
  exit 2
fi

command_line=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
tool_input = payload.get("tool_input")
if isinstance(tool_input, dict):
    value = tool_input.get("command")
    if isinstance(value, str):
        sys.stdout.write(value)
' 2>/dev/null)

[ -n "$command_line" ] || exit 0

if ! facts=$(printf '%s' "$command_line" | "$py" "$CLASSIFIER" 2>/dev/null); then
  printf 'git-guard: cannot run %s; failing closed.\n' "$CLASSIFIER" >&2
  printf 'Restore it (it lives beside this hook) to unblock Bash calls.\n' >&2
  exit 2
fi

# One fact per LINE, and compared as a whole line. An unquoted `for f in $facts`
# splits on bash's default IFS, which includes the TAB that carries a path in
# `COMMIT_PATH<tab><path>` -- so committing a file named PUSH_FORCE produced the
# token PUSH_FORCE and blocked the push in the very same command line.
has_fact() {
  local f
  while IFS= read -r f; do
    [ "$f" = "$1" ] && return 0
  done <<< "$facts"
  return 1
}

current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo ""
}

# Git is replaying or completing work that already exists and is waiting on a
# command to finish it. Refusing here strands the operator mid-operation with
# advice they cannot follow -- `git switch -c` refuses while a sequencer runs.
#
# EXCEPT a rebase whose head-name is the default branch. That rebase MOVES that
# branch onto the replayed commits when it finishes, so a commit made during it
# really is reaching main, and the guard must stay on. Measured: without this
# clause a source file committed during a rebase started from main IS on main
# after --continue. Both backends write head-name (merge and apply alike).
sequencer_in_progress() {
  local marker dir
  for marker in rebase-merge rebase-apply; do
    dir="$(git rev-parse --git-path "$marker" 2>/dev/null)"
    [ -e "$dir" ] || continue
    case "$(cat "$dir/head-name" 2>/dev/null)" in
      refs/heads/main|refs/heads/master) return 1 ;;
    esac
    return 0
  done
  # Cherry-pick, revert and merge move no branch: finishing one leaves the
  # commit on the detached HEAD it was already on.
  #
  # `git am` stopped on a conflict from a DETACHED HEAD does reach this arm --
  # it writes rebase-apply with no head-name, so the case above falls through to
  # `return 0` and the guard stands down. That is safe for the cherry-pick
  # reason, not the reason an earlier draft gave: an `am` replaying onto a
  # detached HEAD updates no branch, so nothing it commits reaches main. An `am`
  # on a NAMED branch never gets here, because symbolic-ref answers.
  for marker in CHERRY_PICK_HEAD REVERT_HEAD MERGE_HEAD; do
    [ -e "$(git rev-parse --git-path "$marker" 2>/dev/null)" ] && return 0
  done
  return 1
}

on_main() {
  local b
  b="$(current_branch)"
  case "$b" in
    main|master) return 0 ;;
    # Empty means HEAD names no branch: a detached checkout, or not a repository
    # at all. Cannot-tell, and this guard fails CLOSED (see the file header) --
    # except while git has an operation in progress, which it is waiting on the
    # operator to finish. See the carve-out above.
    "")          sequencer_in_progress && return 1; return 0 ;;
    *)           return 1 ;;
  esac
}

# Describes the observed checkout for a refusal message. Distinguishing "detached"
# from "not a repository" is what lets the reader tell a true block from a false one.
#
# Safe to add ahead of the symbolic-ref/on_main rewrite: on_main() today only ever
# returns true for a literally-named main/master checkout, so the only argument
# this is ever called with while that holds is "main" or "master" -- the other
# arms become reachable once current_branch() starts returning "" for a detached
# HEAD instead of the literal string "HEAD".
checkout_desc() {
  local hn
  case "$1" in
    "")
      git rev-parse --git-dir >/dev/null 2>&1 ||
        { printf 'a directory that is not a git repository'; return; }
      # Bound 1 refuses here while a plain detached HEAD also refuses -- without
      # this case both render identically and the operator cannot see which rule
      # caught them.
      hn=$(rebase_head_name)
      case "$hn" in
        refs/heads/*) printf "a detached HEAD mid-rebase that will update '%s'" "${hn#refs/heads/}" ;;
        *)            printf 'a detached HEAD (no branch checked out)' ;;
      esac ;;
    *) printf "branch '%s'" "$1" ;;
  esac
}

# The head-name of an in-progress rebase, or nothing.
#
# NOT a substitute for sequencer_in_progress's own loop: empty here is ambiguous
# (no rebase at all, vs. a `git am` whose rebase-apply carries no head-name), and
# those two need opposite answers. The two must agree on the ONE thing they share
# -- which marker directories exist and what head-name each holds -- so the fence
# and the message can never describe different states. If one gains a marker, so
# does the other.
rebase_head_name() {
  local marker dir
  for marker in rebase-merge rebase-apply; do
    dir="$(git rev-parse --git-path "$marker" 2>/dev/null)"
    [ -e "$dir" ] && { cat "$dir/head-name" 2>/dev/null; return; }
  done
}

# Any of the five sequencer/operation markers present, regardless of head-name.
# Message-selection only -- never used to gate. Deliberately separate from
# sequencer_in_progress() (added with the on_main() rewrite): that function's
# head-name special case exists to answer a GATING question ("does finishing
# this operation move main?"), which is irrelevant here -- a checkout that is
# already a NAMED main/master needs only to know an operation is running, not
# where it will land.
operation_in_progress() {
  local marker
  for marker in rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD MERGE_HEAD; do
    [ -e "$(git rev-parse --git-path "$marker" 2>/dev/null)" ] && return 0
  done
  return 1
}

# The remedy line appended after a refusal, keyed on what the guard observed.
# $1 is "commit" or "push"; $2 is current_branch()'s raw value. Every branch
# below is exact text from the message contract -- see the feature file.
remedy_line() {
  local kind="$1" b="$2" hn
  case "$b" in
    "")
      git rev-parse --git-dir >/dev/null 2>&1 || {
        printf 'git-guard cannot judge this command from here. Run it from inside the target repository.'
        return
      }
      hn=$(rebase_head_name)
      case "$hn" in
        refs/heads/main|refs/heads/master)
          case "$kind" in
            commit) printf "Let the rebase make this commit: git rebase --continue. Committing by hand here puts unreviewed work on %s." "${hn#refs/heads/}" ;;
            push)   printf 'Finish the rebase first: git rebase --continue.' ;;
          esac ;;
        *)
          case "$kind" in
            commit) printf 'Create a feature branch first: git switch -c <name>. Commits made here belong to no branch.' ;;
            push)   printf 'Create a feature branch first: git switch -c <name>, then push it.' ;;
          esac ;;
      esac ;;
    *)
      if operation_in_progress; then
        case "$kind" in
          commit) printf 'Finish the operation first (git rebase --continue, or git merge --continue); do not switch branches -- git will refuse.' ;;
          push)   printf 'Finish the operation first; do not switch branches -- git will refuse.' ;;
        esac
      else
        case "$kind" in
          commit) printf 'Create a feature branch instead (git switch -c <name>), or stage only documentation.' ;;
          push)   printf 'Push from a feature branch instead (git switch -c <name>).' ;;
        esac
      fi ;;
  esac
}

# The paths this commit names for ITSELF, or nothing at all.
#
# PreToolUse runs BEFORE the command, so `git add -- x && git commit -m msg -- x`
# -- the form this repo mandates on every commit -- arrives here with NOTHING
# staged. An empty index means "the index cannot answer", not "nothing is
# allowed", so the command is asked instead. It is asked exactly ONE question:
# which paths does the `commit` name after a `--`? Printing nothing means the
# question had no answer, and the caller treats that as block.
#
# What this deliberately does NOT do is work out what the rest of the command
# line will have staged by the time git looks. Two review rounds tried; each
# enumeration was measured short (first the chain's own `git add`, then nine
# further commands that fill the index), and short in the ALLOW direction is a
# fail-open. Reading the commit's own pathspec is a much narrower question, and
# every path it grants is one the hook has read off the command line -- but
# "read" is not "resolved": a path with a `..` component names a file other than
# the one the pattern matched, so the allowlist below refuses those outright.
#
# A pathspec is EXCLUSIVE -- git commits those paths and leaves whatever else is
# staged sitting in the index -- but only while nothing else on the LINE widens
# it. The classifier withholds COMMIT_PATHSPEC unless every commit segment names
# its own paths and none of them carries -i/--include (unrecognised on purpose),
# -a or --amend. The three checks below are belt and braces over that: they bind
# across the whole line rather than per segment, so they can only ever refuse
# more, and they keep a classifier regression from becoming a fail-open here.
# See ADR 0014.
commit_pathspec_files() {
  local tab
  tab=$(printf '\t')
  if has_fact COMMIT_PATHSPEC \
     && ! has_fact COMMIT_ALL \
     && ! has_fact COMMIT_AMEND \
     && ! has_fact COMMIT_BARE_ARGS; then
    printf '%s\n' "$facts" | grep "^COMMIT_PATH${tab}" | cut -f2-
  fi
}

# --- Guard 2: force-push ---
# PUSH_FORCE already means "bare force, with no --force-with-lease in that same
# segment", so the two cases below cannot both fire for one push.
if has_fact PUSH_FORCE; then
  printf 'git-guard: bare "git push --force"/"-f" is blocked on every branch. Use --force-with-lease instead (still blocked while main/master is checked out).\n' >&2
  exit 2
fi
if has_fact PUSH_LEASE && on_main; then
  checkout_branch="$(current_branch)"
  printf 'git-guard: refusing --force-with-lease -- the checkout is %s.\n' "$(checkout_desc "$checkout_branch")" >&2
  printf '%s\n' "$(remedy_line push "$checkout_branch")" >&2
  exit 2
fi

# --- Guard 1: default-branch commit ---
if has_fact COMMIT && on_main; then
  checkout_branch="$(current_branch)"
  files=$(git diff --cached --name-only 2>/dev/null || echo "")
  label="Staged files"

  if [ -z "$files" ]; then
    files=$(commit_pathspec_files)
    label="Files this commit would contain"
    if [ -z "$files" ]; then
      # Nothing staged AND the commit names nothing checkable. Everything this
      # branch relaxed is above; this is main's behaviour, unchanged, and it is
      # what keeps the ten commands that fill an index blocked without the hook
      # having to know a single one of them.
      printf 'git-guard: the checkout is %s, and nothing is staged -- so this commit is judged by the paths it names, and it names none that can be checked.\n' "$(checkout_desc "$checkout_branch")" >&2
      printf 'Name them after a separator: git commit -m msg -- <path>\n' >&2
      printf '(-a, --amend, -i/--include and an unseparated path all commit more than the paths given, so none of them can stand in for one.)\n' >&2
      exit 2
    fi
  fi

  allowed=1
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      # A `..` COMPONENT means the string matched here and the file git will
      # actually commit are two different things: `coding-memory/../src/app.sh`
      # satisfies `coding-memory/*`, and `docs/../notes.md` satisfies `docs/*.md`
      # from anywhere in the repo. The hook may only judge what it has read, so a
      # traversing path is refused rather than resolved — resolving it would mean
      # answering "relative to which directory?", which is Defect C's question and
      # is not settled here. A `..` inside a file NAME (`docs/v1..v2.md`) traverses
      # nothing and is untouched by these four patterns.
      ..|../*|*/../*|*/..) allowed=0 ;;
      # `*` spans `/` in a case pattern, so `docs/*.md` covers any depth while
      # still rejecting `docs/tool.sh` — and `docs/notes.md.sh`.
      CODING_MEMORY.md|coding-memory/*|docs/*.md) ;;
      *) allowed=0 ;;
    esac
  done <<< "$files"
  if [ "$allowed" -ne 1 ]; then
    printf 'git-guard: refusing this commit -- the checkout is %s, where commits are restricted to documentation (CODING_MEMORY.md, coding-memory/*, docs/*.md).\n' "$(checkout_desc "$checkout_branch")" >&2
    printf '%s:\n%s\n' "$label" "$files" | sed 's/^/  /' >&2
    printf '%s\n' "$(remedy_line commit "$checkout_branch")" >&2
    exit 2
  fi
fi

# --- Guard 3: cannot tell which repository or branch this line targets ---
# SCOPE_UNKNOWN (lib/classify-git-command.py) is a global option ahead of the
# subcommand this file cannot account for -- it may redirect the repository,
# change what a pathspec means, or simply be unrecognised. Runs on EVERY
# branch: the guard cannot tell WHICH branch a redirecting option targets, so
# on_main() is not even a meaningful question here. Checked LAST, after both
# guards above: those are proven protections and win outright if they also
# fire on this line (an existing hard block is never downgraded to a
# prompt) -- this is strictly additive over what used to be a silent,
# unexamined allow, which is the whole defect this feature fixes.
#
# Unverified whether stderr from an exit-0 hook is surfaced anywhere -- the
# embedded hooks reference (this binary, 2.1.234) documents `systemMessage`
# and `suppressOutput` for stdout, and says nothing about stderr for any exit
# code. A live check would need an actual ask decision to fire, which is
# task 9's blocking manual acceptance test, not something to trigger here.
# Conservative assumption either way: permissionDecisionReason is the
# guaranteed-visible record, so the SAME text also goes to stderr for free --
# the house convention (merge-guard.sh, judge-guard.sh, feature-sync-guard.sh
# all `printf ... >&2`), and correct whether or not it turns out redundant.
scope_tab=$(printf '\t')
scope_option=$(printf '%s\n' "$facts" | grep "^SCOPE_UNKNOWN${scope_tab}" | head -1 | cut -f2-)
if [ -n "$scope_option" ]; then
  reason="This command carries $scope_option ahead of the subcommand, which git-guard cannot account for -- it may point git at a different repository or change how a pathspec is read. Confirm this is intended."
  printf 'git-guard: %s\n' "$reason" >&2
  "$py" -c '
import json, sys
sys.stdout.write(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": sys.argv[1],
    }
}, separators=(",", ":")) + "\n")
' "$reason"
  exit 0
fi

exit 0
