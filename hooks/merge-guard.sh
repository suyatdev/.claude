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
# Must also catch the `rtk gh ...` form: the RTK PreToolUse hook (registered
# ahead of this one in settings.json) may rewrite the command before this guard
# runs, so a leading `rtk ` wrapper is stripped before classifying.
#
# Command classification uses python shlex (same approach as judge-guard.sh):
# shlex handles the shell quoting a flat bash regex cannot, so the phrase inside
# an echo, a commit message, or a quoted string is ignored — only a real
# `gh pr merge` command is caught. Accepted limitation: a chained
# `foo && gh pr merge` is not caught, the same tradeoff git-guard.sh makes.
#
# Fails CLOSED when python is unavailable (cannot inspect the command), matching
# git-guard.sh / judge-guard.sh; fails OPEN on exotic unparseable quoting.
#
# Regexes live in variables, never inline in `[[ ]]` — a bare `(` or `;` in an
# inline regex kills bash's parser and a dead script exits non-zero, which
# PreToolUse reads as a block. Same trap and fix as git-guard.sh.
#
# Exit 0 = allow (silent). Exit 2 = blocked, reason on stderr.

set -u

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

# Classify with python shlex: strip an optional leading `rtk` wrapper and any
# leading NAME=VALUE env-assignments, capture MERGE_EXEMPT's value (quoted or
# not), then test whether the actual command is `gh pr merge`.
classify=$(printf '%s' "$command_line" | "$py" -c '
import re, shlex, sys
try:
    toks = shlex.split(sys.stdin.read())
except ValueError:
    # Deliberate fail-OPEN, not a bug: a command that is valid bash but not
    # shlex-parseable (some exotic shell quoting) is treated as "not a gh pr
    # merge". Failing closed here would block unrelated commands that merely
    # contain such quoting, wrong for a momentum guardrail.
    print("NO"); print(""); sys.exit(0)
if toks and toks[0] == "rtk":
    toks = toks[1:]
assign = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
exempt = ""
i = 0
while i < len(toks) and assign.match(toks[i]):
    name, _, val = toks[i].partition("=")
    if name == "MERGE_EXEMPT":
        exempt = val.replace("\n", " ")
    i += 1
print("MERGE" if toks[i:i+3] == ["gh", "pr", "merge"] else "NO")
print(exempt)
' 2>/dev/null)
kind=$(printf '%s\n' "$classify" | sed -n '1p')
exempt_reason=$(printf '%s\n' "$classify" | sed -n '2p')

[ "$kind" = "MERGE" ] || exit 0

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
