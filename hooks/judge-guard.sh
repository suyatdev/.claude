#!/usr/bin/env bash
#
# judge-guard.sh — PreToolUse hook (matcher: Bash).
#
# Blocks `gh pr create` unless a FRESH implementation-stage observability-judge
# verdict exists for the current repo+branch+HEAD. Strict freshness: the stored
# full head_sha must equal current HEAD, so any commit added after judging forces
# a re-run and the gate always reflects exactly what will ship.
#
# This is a safety gate (it prevents shipping un-judged code), so it fails CLOSED:
# any inability to verify blocks. Contrast doc-guard.sh, a momentum guardrail that
# fails open. Escape hatch: `JUDGE_EXEMPT=<reason> gh pr create ...` (logged).
#
# Regexes live in variables, never inline in `[[ ]]` — a bare `(` or `;` in an
# inline regex kills bash's parser and a dead script exits non-zero. Same trap and
# fix as git-guard.sh / doc-guard.sh.
#
# Exit 0 = allow (silent). Exit 2 = blocked, reason on stderr.

set -u

VERDICTS="${JUDGE_VERDICTS_FILE:-$HOME/.claude/coding-memory/observability-judge/verdicts.jsonl}"

payload=""
if [ ! -t 0 ]; then payload=$(cat); fi
[ -n "$payload" ] || exit 0

py=$(command -v python3 || command -v python) || py=""
if [ -z "$py" ]; then
  printf 'judge-guard: python3 not on PATH; cannot verify a verdict -- failing closed.\n' >&2
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

# Classify the command with python — shlex handles the shell quoting a flat bash regex
# cannot. A command is guarded only when, after an optional leading `rtk` wrapper and any
# leading NAME=VALUE env-assignments, the actual command is `gh pr create`; the phrase inside
# a commit message, an echo, or a quoted string is therefore ignored. JUDGE_EXEMPT's value
# (quoted or not) is captured here. Accepted limitation: a chained `foo && gh pr create` is not
# caught — a momentum guardrail, not a security boundary, the same tradeoff git-guard makes.
classify=$(printf '%s' "$command_line" | "$py" -c '
import re, shlex, sys
try:
    toks = shlex.split(sys.stdin.read())
except ValueError:
    # Deliberate fail-OPEN, not a bug: a command that is valid bash but not
    # shlex-parseable (some exotic shell quoting forms) is treated as "not a gh
    # pr create". Failing closed here would block unrelated commands that merely
    # contain such quoting, which is wrong for a momentum guardrail -- the
    # repo/branch/HEAD checks below still fail closed for the cases that matter.
    print("NO"); print(""); sys.exit(0)
if toks and toks[0] == "rtk":
    toks = toks[1:]
assign = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
exempt = ""
i = 0
while i < len(toks) and assign.match(toks[i]):
    name, _, val = toks[i].partition("=")
    if name == "JUDGE_EXEMPT":
        exempt = val.replace("\n", " ")
    i += 1
print("PR" if toks[i:i+3] == ["gh", "pr", "create"] else "NO")
print(exempt)
' 2>/dev/null)
kind=$(printf '%s\n' "$classify" | sed -n '1p')
exempt_reason=$(printf '%s\n' "$classify" | sed -n '2p')

[ "$kind" = "PR" ] || exit 0

# Escape hatch: a non-empty JUDGE_EXEMPT reason (quoted or not) as a leading env-assignment
# allows the PR and logs the exemption.
if [ -n "$exempt_reason" ]; then
  printf 'judge-guard: exempted (JUDGE_EXEMPT=%s); skipping verdict check.\n' "$exempt_reason" >&2
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'judge-guard: not inside a git repo; cannot verify a verdict -- failing closed.\n' >&2
  exit 2
fi

repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
head_sha=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$repo" ] || [ -z "$branch" ] || [ -z "$head_sha" ]; then
  printf 'judge-guard: could not determine repo/branch/HEAD -- failing closed.\n' >&2
  exit 2
fi

if [ ! -f "$VERDICTS" ]; then
  printf 'judge-guard: no verdict store yet (%s). Run the observability judge before opening a PR.\n' "$VERDICTS" >&2
  exit 2
fi

match=$("$py" - "$VERDICTS" "$repo" "$branch" "$head_sha" <<'PYEOF'
import json, sys
path, repo, branch, head = sys.argv[1:5]
found = False
try:
    with open(path) as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                v = json.loads(raw)
            except ValueError:
                continue
            if (v.get("stage") == "implementation" and v.get("repo") == repo
                    and v.get("branch") == branch and v.get("head_sha") == head):
                found = True
                break
except OSError:
    sys.exit(3)
sys.stdout.write("1" if found else "0")
PYEOF
)
if [ $? -ne 0 ]; then
  printf 'judge-guard: could not read the verdict store -- failing closed.\n' >&2
  exit 2
fi
if [ "$match" = "1" ]; then
  exit 0
fi

{
  printf 'judge-guard: no fresh observability-judge verdict for %s@%s (branch %s).\n' "$repo" "${head_sha:0:12}" "$branch"
  printf 'Run the observability judge on the current HEAD (see running-the-observability-judge), then retry.\n'
  printf 'To bypass a genuinely exempt PR: JUDGE_EXEMPT=<reason> gh pr create ...\n'
} >&2
exit 2
