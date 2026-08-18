#!/usr/bin/env bash
#
# merge-guard.sh — PreToolUse hook (matcher: Bash).
#
# Blocks `gh pr merge` — merging a pull request on the remote (GitHub) from the
# CLI. Merges should land through the GitHub UI with review, not be triggered
# autonomously mid-session. Server-side PR merges only: a local
# `git merge origin/main`, `gh pr create`, and `gh pr view` all pass untouched.
#
# This is a momentum guardrail, not a security boundary. Escape hatch:
# `MERGE_EXEMPT=<reason> gh pr merge ...` allows the merge and logs the reason —
# the same convention as judge-guard.sh's JUDGE_EXEMPT.
#
# Classification now calls the SAME shared adjacent-pair-in-a-segment reader
# hooks/judge-guard.sh uses for `gh pr create` (lib/classify-pr-command.py,
# generalised for this — docs/features/global-option-blindness.md, task 5) —
# rather than an inline shlex-only classifier duplicating that logic. The old
# inline version required "gh", "pr", "merge" to be adjacent AT A FIXED OFFSET,
# with only ONE leading `rtk` wrapper stripped, so three shapes bypassed it
# silently: a global flag before the subcommand (`gh -R o/r pr merge 5`), any
# chained command (`echo hi && gh pr merge 5`), and a STACK of wrappers
# (`time rtk gh pr merge 5` — only the single literal `rtk` was ever
# stripped). All three are closed for free by switching to the shared reader,
# which lexes the whole command into shell segments (`rules/gates.md`'s own
# chained-command gap) and finds the pair at any position within one.
#
# Fails CLOSED when python is unavailable (cannot inspect the command), matching
# git-guard.sh / judge-guard.sh; fails OPEN on exotic unparseable quoting (the
# shared reader's own accepted-open shapes — see classify-pr-command.py).
#
# Exit 0 = allow (silent, or exempted with a reason on stderr). Exit 2 =
# blocked, reason on stderr.

set -u

CLASSIFIER="$(cd "$(dirname "$0")" && pwd)/lib/classify-pr-command.py"

payload=""
if [ ! -t 0 ]; then payload=$(cat); fi
[ -n "$payload" ] || exit 0

py=$(command -v python3 || command -v python) || py=""
if [ -z "$py" ]; then
  printf 'merge-guard: python3 not on PATH; cannot inspect the command -- failing closed.\n' >&2
  exit 2
fi

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

classify=$(printf '%s' "$command_line" | "$py" -c '
import importlib.util, sys

spec = importlib.util.spec_from_file_location("classify_pr_command", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

kind, exempt = mod.classify(sys.stdin.read(), subcommand=("pr", "merge"), exempt_var="MERGE_EXEMPT")
sys.stdout.write(kind + "\n" + exempt + "\n")
' "$CLASSIFIER" 2>/dev/null)
kind=$(printf '%s\n' "$classify" | sed -n '1p')
exempt_reason=$(printf '%s\n' "$classify" | sed -n '2p')

# classify() returns "PR" for a matched pair regardless of which pair was
# asked for -- see its own docstring ("both are `gh pr <verb>` operations").
[ "$kind" = "PR" ] || exit 0

# Escape hatch: a non-empty MERGE_EXEMPT reason as a leading env-assignment
# allows the merge and logs the exemption.
if [ -n "$exempt_reason" ]; then
  printf 'merge-guard: exempted (MERGE_EXEMPT=%s); allowing the PR merge.\n' "$exempt_reason" >&2
  exit 0
fi

{
  printf 'merge-guard: `gh pr merge` is blocked -- merge pull requests through the GitHub UI with review, not from the CLI mid-session.\n'
  printf 'To bypass a genuinely intentional merge: MERGE_EXEMPT=<reason> gh pr merge ...\n'
} >&2
exit 2
