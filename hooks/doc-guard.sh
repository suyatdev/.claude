#!/usr/bin/env bash
#
# doc-guard.sh — documentation-checkpoint guard.
#
# Purpose: make it hard for a business-logic or direction-pivoting change to
# leave a session undocumented. Three behaviors, dispatched on hook_event_name:
#
#   1. PreToolUse (matcher: Bash) — block-at-commit. A `git commit` whose staged
#      change is a SUBSTANTIAL source change (>= DOC_GUARD_THRESH_FILES files or
#      >= DOC_GUARD_THRESH_LINES changed lines) but stages no documentation
#      (docs/) is blocked. Bypass with a `Doc-Exempt: <reason>` trailer for
#      genuinely trivial/mechanical commits. Trivial source-only commits pass
#      silently, so the many small commits of an SDD run are not held hostage.
#
#   2. PreCompact (manual/auto) — before compaction, if the working tree has
#      uncommitted tracked changes, inject a warning to save docs/features/ and
#      docs/decisions/ entries and commit first (compacting with unsaved state
#      is how it gets lost).
#
#   3. SessionStart (any source) — at the start of a session, INCLUDING the one
#      that follows a /clear or /compact, if the working tree has uncommitted
#      tracked changes, inject them into context so the slip surfaces on turn 1
#      and gets reconciled (see managing-session-memory). /clear itself cannot be
#      blocked by any hook, so surfacing it in the next session IS the guarantee.
#
# This is a momentum guardrail, not a security boundary: it fails OPEN (missing
# python, unparseable payload, or a non-git cwd all exit 0) rather than block
# legitimate work. Contrast git-guard.sh, whose branch/force-push guards fail
# CLOSED because they protect against a destructive action, not a missing note.
#
# Regexes live in variables, not inline in [[ ]] — a bare ( or ; in an inline
# regex makes bash's parser die and a dead script exits non-zero. Same trap and
# fix as git-guard.sh.
#
# Exit 0 = allow / silent (or JSON on stdout for the advisory events).
# Exit 2 = blocked (PreToolUse commit), reason on stderr.

set -u

DOC_GUARD_THRESH_FILES=3
DOC_GUARD_THRESH_LINES=20

CLASSIFIER="$(cd "$(dirname "$0")" && pwd)/lib/classify-git-command.py"

payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi
[ -n "$payload" ] || exit 0

py=$(command -v python3 || command -v python) || py=""
# Fail OPEN: without python we cannot inspect the payload, and a documentation
# reminder is not worth blocking every commit over.
[ -n "$py" ] || exit 0

event=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
sys.stdout.write(p.get("hook_event_name") or "")
' 2>/dev/null)

in_git_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# Uncommitted TRACKED changes only — untracked files are excluded so gitignored
# runtime junk (daemon/, jobs/, paste-cache/, ...) doesn't cry wolf.
tracked_status() { git status --porcelain --untracked-files=no 2>/dev/null; }

emit_context() {
  # $1 = hookEventName; stdin = status text. Emits SessionStart/PreCompact JSON.
  local ev="$1"
  "$py" -c '
import json, sys
ev = sys.argv[1]
status = sys.stdin.read().rstrip("\n")
ctx = (
    "⚠️ doc-guard: the working tree has uncommitted tracked changes:\n"
    + status
    + "\n\nPer managing-session-memory, save any docs/features/ and docs/decisions/ "
      "entries and commit before continuing, clearing, or compacting — a session "
      "cleared before its checkpoint loses this. If a change here affects business "
      "logic or pivots the direction of a feature, it also needs an ADR under "
      "docs/decisions/."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": ev, "additionalContext": ctx}}))
' "$ev"
}

case "$event" in
  SessionStart | PreCompact)
    in_git_repo || exit 0
    status="$(tracked_status)"
    [ -n "$status" ] || exit 0
    printf '%s' "$status" | emit_context "$event"
    exit 0
    ;;
  PreToolUse) ;;   # fall through to the commit check below
  *) exit 0 ;;
esac

# --- PreToolUse: block-at-commit ---
command_line=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
ti = p.get("tool_input")
if isinstance(ti, dict):
    v = ti.get("command")
    if isinstance(v, str):
        sys.stdout.write(v)
' 2>/dev/null)
[ -n "$command_line" ] || exit 0

# Whether this really runs `git commit` is decided by lib/classify-git-command.py,
# which lexes the command into shell segments (and absorbs the `rtk git ...` form the
# RTK hook produces by rewriting plain git commands ahead of this one). This used to
# be a regex ANCHORED to the start of the command string, so anything chained —
# `git add -- x && git commit -m y`, the shape this repo uses constantly — skipped the
# check entirely, and the documentation guarantee this hook exists to provide was not
# enforced on the commit shape actually in use.
#
# A classifier that will not run leaves `facts` empty and the commit allowed: this hook
# fails OPEN throughout, because a missing note is not worth blocking work over.
# Contrast git-guard.sh, which fails closed on the same condition.
facts=$(printf '%s' "$command_line" | "$py" "$CLASSIFIER" 2>/dev/null) || exit 0

# One fact per LINE, and compared as a whole line -- the same reader git-guard.sh
# already uses, ported here. An unquoted `for f in $facts` splits on bash's default
# IFS, which includes the TAB that carries a path in `COMMIT_PATH<tab><path>` -- so
# committing a file named COMMIT_ALL produced the token COMMIT_ALL and made this hook
# judge HEAD's diff instead of the index it was about to commit.
has_fact() {
  local f
  while IFS= read -r f; do
    [ "$f" = "$1" ] && return 0
  done <<< "$facts"
  return 1
}

has_fact COMMIT || exit 0
in_git_repo || exit 0

# Bypass: a Doc-Exempt: trailer anywhere in the command allows the commit.
if [[ "$command_line" == *Doc-Exempt:* ]]; then
  exit 0
fi

# `commit -a`/`--all`/`-am` stages tracked edits at commit time — they are not in
# the index yet when this PreToolUse fires — so diff against HEAD for those;
# otherwise inspect the staged index. COMMIT_ALL is set only when that flag belongs
# to the commit's OWN segment; it used to be searched for across the whole command
# string, so `git commit -m msg && ls -a` made this judge every dirty tracked file
# instead of the (empty) index it was actually about to commit.
if has_fact COMMIT_ALL && git rev-parse HEAD >/dev/null 2>&1; then
  numstat=$(git diff HEAD --numstat 2>/dev/null)
else
  numstat=$(git diff --cached --numstat 2>/dev/null)
fi
[ -n "$numstat" ] || exit 0   # nothing to inspect (e.g. --amend --no-edit) → allow

has_doc=0
src_files=0
src_lines=0
while IFS=$'\t' read -r add del path; do
  [ -z "$path" ] && continue
  case "$path" in
    # Broader than git-guard.sh's `docs/*.md`, deliberately: the question here is
    # "did documentation ride along with this commit?", and a diagram or screenshot
    # counts. git-guard asks "may this reach main unreviewed?", where it must not.
    # The two rules are not meant to agree — do not align them.
    docs/*) has_doc=1; continue ;;
  esac
  src_files=$((src_files + 1))
  [[ "$add" =~ ^[0-9]+$ ]] && src_lines=$((src_lines + add))
  [[ "$del" =~ ^[0-9]+$ ]] && src_lines=$((src_lines + del))
done <<< "$numstat"

# Satisfied if a doc file rides along, or if nothing substantive is staged.
[ "$has_doc" -eq 1 ] && exit 0
[ "$src_files" -eq 0 ] && exit 0

if [ "$src_files" -ge "$DOC_GUARD_THRESH_FILES" ] || [ "$src_lines" -ge "$DOC_GUARD_THRESH_LINES" ]; then
  {
    printf 'doc-guard: this commit makes a substantial source change (%s file(s), %s line(s)) but records no documentation.\n' "$src_files" "$src_lines"
    printf 'Nothing staged under docs/ (incl. docs/features/, docs/decisions/, docs/specs/).\n\n'
    printf 'If it affects business logic or pivots the direction of a feature: update the docs/features/ entry and add an ADR under docs/decisions/ (see managing-session-memory), then re-commit.\n'
    printf 'If it is genuinely trivial (refactor, formatting, mechanical): add a  Doc-Exempt: <reason>  trailer to the commit message.\n'
  } >&2
  exit 2
fi

exit 0
