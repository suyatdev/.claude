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
#      (CODING_MEMORY.md, coding-memory/, docs/) is blocked. Bypass with a
#      `Doc-Exempt: <reason>` trailer for genuinely trivial/mechanical commits.
#      Trivial source-only commits pass silently, so the many small commits of an
#      SDD run are not held hostage.
#
#   2. PreCompact (manual/auto) — before compaction, if the working tree has
#      uncommitted tracked changes, inject a warning to save CODING_MEMORY.md and
#      commit first (compacting with unsaved state is how it gets lost).
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
    + "\n\nPer managing-session-memory, save CODING_MEMORY.md and any docs/decisions "
      "or coding-memory entries and commit before continuing, clearing, or compacting "
      "— a session cleared before its checkpoint loses this. If a change here "
      "affects business logic or pivots the direction of a feature, it also needs an "
      "ADR under docs/decisions/."
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

# Strip leading whitespace, then a leading rtk wrapper (the RTK hook runs first
# and may already have rewritten `git ...` to `rtk git ...`).
normalized="${command_line#"${command_line%%[![:space:]]*}"}"
if [[ "$normalized" == rtk\ * ]]; then
  normalized="${normalized#rtk }"
fi

commit_re='^git[[:space:]]+commit([[:space:]]|$)'
[[ "$normalized" =~ $commit_re ]] || exit 0
in_git_repo || exit 0

# Bypass: a Doc-Exempt: trailer anywhere in the command allows the commit.
if [[ "$normalized" == *Doc-Exempt:* ]]; then
  exit 0
fi

# `commit -a`/`--all`/`-am` stages tracked edits at commit time — they are not in
# the index yet when this PreToolUse fires — so diff against HEAD for those;
# otherwise inspect the staged index.
all_re='(^|[[:space:]])(-a|--all|-am)([[:space:]]|$)'
if [[ "$normalized" =~ $all_re ]] && git rev-parse HEAD >/dev/null 2>&1; then
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
    CODING_MEMORY.md|coding-memory/*|docs/*) has_doc=1; continue ;;
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
    printf 'Nothing staged under CODING_MEMORY.md, coding-memory/, or docs/ (incl. docs/decisions/, docs/specs/).\n\n'
    printf 'If it affects business logic or pivots the direction of a feature: add an ADR under docs/decisions/ and a CODING_MEMORY.md pointer (see managing-session-memory), then re-commit.\n'
    printf 'If it is genuinely trivial (refactor, formatting, mechanical): add a  Doc-Exempt: <reason>  trailer to the commit message.\n'
  } >&2
  exit 2
fi

exit 0
