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
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

on_main() {
  local b
  b="$(current_branch)"
  [ "$b" = "main" ] || [ "$b" = "master" ]
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
  printf 'git-guard: --force-with-lease is blocked while main/master is checked out.\n' >&2
  exit 2
fi

# --- Guard 1: default-branch commit ---
if has_fact COMMIT && on_main; then
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
      printf 'git-guard: nothing is staged yet, so this commit is judged by the paths it names -- and it names none that can be checked.\n' >&2
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
    printf 'git-guard: commits to main/master are blocked except documentation (CODING_MEMORY.md, coding-memory/*, docs/*.md).\n' >&2
    printf '%s:\n%s\n' "$label" "$files" | sed 's/^/  /' >&2
    printf 'Create a feature branch instead, or stage only documentation.\n' >&2
    exit 2
  fi
fi

exit 0
