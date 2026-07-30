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

# The verdict store is resolved per-repo, below, once the repo root is known: the judge
# writes verdicts repo-relative (agents/observability-judge.md: "Write ONLY under
# coding-memory/observability-judge/"), so the guard must read the JUDGED repo's store.
# It previously hardcoded $HOME/.claude's copy, which coincides with the repo store only
# for the ~/.claude repo itself — leaving the gate unsatisfiable everywhere else.
# Single source of truth on purpose: no fallback to a second location, so a judge that
# writes to the wrong place surfaces as a named-path error instead of being papered over.
VERDICTS_REL="coding-memory/observability-judge/verdicts.jsonl"

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
# cannot. The command line is split into shell segments on control operators (and on newlines,
# which end a command just as `;` does), and EACH segment is tested: a chained or multi-line
# `git push && gh pr create` is guarded exactly like a bare invocation.
# (That chained form used to be an accepted gap; it is what let a PR ship unjudged, so it is now
# caught. A `$(...)`-substituted `gh pr create` is likewise caught, since it too really runs.)
# Within a segment, an optional leading `rtk` wrapper and any leading NAME=VALUE env-assignments
# are stripped before matching, and JUDGE_EXEMPT's value (quoted or not) is captured from the
# matching segment — mirroring bash, where such a prefix binds only to its own command.
# Quoted text survives as a single token, so `gh pr create` inside a commit message or an echo
# argument can never sit at a segment's command position and is still ignored.
classify=$(printf '%s' "$command_line" | "$py" -c '
import re, shlex, sys
try:
    # bash ends a command at a newline exactly as it does at `;`, but shlex counts newline as
    # ordinary whitespace, so two lines of one Bash call used to lex into a single segment with no
    # command at position 0. Translating BEFORE lexing is deliberate: the shlex quoting rules then
    # keep the substituted char inside a quoted string as part of that token, so a multi-line
    # commit message still cannot reach the command position of a segment. Splitting the raw input
    # per line instead would raise on any quote spanning lines and fail open -- strictly worse.
    # NOTE: no apostrophes in this block -- it lives inside a single-quoted shell string.
    #
    # A backslash-newline is a line CONTINUATION: bash joins the two lines into one command. So
    # this pair is deleted BEFORE the newline translation below, which routes the result into the
    # existing chained-operator path instead of adding a matcher. Order matters -- translate first
    # and the continuation becomes a spurious command separator, which is how it slipped through.
    #
    # Backticks are deliberately NOT translated, though doing so does catch `gh pr create` in a
    # legacy substitution. shlex cannot see heredocs, so the same translation makes any heredoc
    # body containing a backticked `gh pr create` fail CLOSED, and writing that text is routine
    # here. Trading a rare false negative for a common false positive that blocks legitimate work
    # is the wrong direction for a momentum guardrail. Recorded in ADR 0012 as an open shape.
    src = sys.stdin.read().replace("\\\n", "")
    lex = shlex.shlex(src.replace("\n", ";"), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    toks = list(lex)
except ValueError:
    # Deliberate fail-OPEN, not a bug: a command that is valid bash but not
    # shlex-parseable (some exotic shell quoting forms) is treated as "not a gh
    # pr create". Failing closed here would block unrelated commands that merely
    # contain such quoting, which is wrong for a momentum guardrail -- the
    # repo/branch/HEAD checks below still fail closed for the cases that matter.
    print("NO"); print(""); sys.exit(0)

# punctuation_chars=True makes shlex emit control operators as standalone tokens even when
# unspaced (`push&&gh` -> `push`, `&&`, `gh`), which a plain whitespace split cannot see.
# Braces are added to the punctuation set here: a brace group opens a command context exactly
# as a subshell does, but `{` is not a punctuation char, so it lexed as an ordinary token and took
# the segment command position -- `{ gh pr create; }` walked past while `( gh pr create )` did not.
OPS = "(){};<>|&"
segments = [[]]
for t in toks:
    if t and all(ch in OPS for ch in t):
        segments.append([])
    else:
        segments[-1].append(t)

assign = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Words that occupy the command position while the real command follows them. `rtk` is the
# token-proxy wrapper used in this repo; the rest are shell keywords/builtins that take a command
# as argument. Stripped in a loop so they stack (`time rtk gh pr create`). `eval` covers only the
# unquoted form -- `eval "gh pr create"` keeps the whole command as one quoted token, which
# by design can never reach a command position. That limit is inherent to lexing, not an oversight.
WRAPPERS = ("rtk", "time", "eval", "command", "builtin", "exec", "nohup")
for seg in segments:
    while seg and seg[0] in WRAPPERS:
        seg = seg[1:]
    exempt = ""
    i = 0
    while i < len(seg) and assign.match(seg[i]):
        name, _, val = seg[i].partition("=")
        if name == "JUDGE_EXEMPT":
            exempt = val.replace("\n", " ")
        i += 1
    # `gh` must hold the command position, but `pr create` need not be tokens 1-2: global flags
    # are legal before the subcommand (`gh -R owner/repo pr create`). Requiring the two words
    # ADJACENT keeps the false-positive surface narrow -- quoted text is a single token, so a
    # commit message mentioning the phrase still cannot produce an adjacent bare pair.
    rest = seg[i:]
    if rest and rest[0] == "gh":
        for j in range(1, len(rest) - 1):
            if rest[j] == "pr" and rest[j+1] == "create":
                print("PR"); print(exempt); sys.exit(0)
print("NO"); print("")
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

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
repo=$(basename "$repo_root" 2>/dev/null)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
head_sha=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$repo_root" ] || [ -z "$repo" ] || [ -z "$branch" ] || [ -z "$head_sha" ]; then
  printf 'judge-guard: could not determine repo/branch/HEAD -- failing closed.\n' >&2
  exit 2
fi

# Resolved from the repo root (not $PWD) so the gate behaves the same from any subdirectory.
VERDICTS="${JUDGE_VERDICTS_FILE:-$repo_root/$VERDICTS_REL}"

if [ ! -f "$VERDICTS" ]; then
  printf 'judge-guard: no verdict store at %s. Run the observability judge before opening a PR.\n' "$VERDICTS" >&2
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
