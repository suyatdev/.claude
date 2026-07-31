#!/usr/bin/env bash
#
# judge-guard.sh — PreToolUse hook (matcher: Bash).
#
# Blocks `gh pr create` unless a FRESH implementation-stage observability-judge
# verdict exists for the current repo+branch+HEAD. Strict freshness: the stored
# full head_sha must equal current HEAD, so any commit added after judging forces
# a re-run and the gate always reflects exactly what will ship.
#
# This is a safety gate (it prevents shipping un-judged code), so its machinery
# fails CLOSED: a missing python, an unreadable payload, an unusable classifier and
# an unreadable verdict store each block rather than allow. Contrast doc-guard.sh,
# a momentum guardrail that fails open.
#
# It is NOT a security boundary, and "fails closed" is a claim about the machinery,
# not about coverage: some command SHAPES are deliberately not detected (a backticked
# `gh pr create`, a heredoc body), an empty payload passes, and a classifier that hangs
# rather than fails has no timeout. Those are named and accepted in ADR 0012 —
# an earlier version of this header claimed "any inability to verify blocks", which
# read as a coverage guarantee the hook has never made.
#
# Escape hatch: `JUDGE_EXEMPT=<reason> gh pr create ...` (logged).
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

# Parse the PreToolUse payload. The parser must SAY it ran, because silence here is ambiguous in a
# way silence nowhere else in this hook is: a truncated payload, a non-JSON payload, a wrong-shaped
# payload and a failing interpreter all produced exactly what a call with nothing to guard produced.
# `except ValueError: sys.exit(0)` plus `2>/dev/null` collapsed them into one silent allow, so a
# garbled payload disarmed the gate exactly as an absent classifier did. Hence a sentinel: the parser
# prints its verdict on line 1 only after it has decided, and the command follows from line 2.
#
# WHICH tool called is decided by `tool_name`, a required PreToolUse field and the one the matcher
# itself filters on — deliberately not by the hook's own registration. An earlier revision reasoned
# from "every Edit, Read and Write reaches this hook" to "an absent command must pass"; that premise
# was false (the sole registration matches `Bash`), and it had quietly chosen the behaviour. Reading
# the payload keeps this file correct under any matcher, instead of correct only while a setting in
# a different file — one no test covers — happens to hold.
#
#   Bash + a runnable command  -> OK, classify it
#   Bash + nothing runnable    -> exit 4, BLOCK: a Bash call this hook could not verify, and the
#                                 only sender is the session itself, which has no reason to issue
#                                 an empty one. Fail closed, as everywhere else on this branch.
#   any other named tool       -> SKIP, pass: nothing here is a shell command to guard
#   anything else              -> exit 3, BLOCK: not a payload this hook can reason about. That
#                                 covers a bad top-level type (an array or scalar is not a
#                                 PreToolUse payload at all) and a missing or non-string
#                                 `tool_name`, which means malformed input, not a boring tool.
parsed=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    raise SystemExit(3)
if not isinstance(p, dict):
    raise SystemExit(3)
tn = p.get("tool_name")
if not isinstance(tn, str) or not tn:
    raise SystemExit(3)
if tn != "Bash":
    sys.stdout.write("SKIP\n")
    raise SystemExit(0)
ti = p.get("tool_input")
c = ti.get("command") if isinstance(ti, dict) else None
# Whitespace is not a command: an all-space string is as unrunnable as an empty one, and blocking
# both states the rule in terms of what the payload can DO, not which falsy shape it arrived in.
# (No backticks or apostrophes in here: this block is single-quoted shell, and a stray one of
# either ends the quote and breaks the whole hook. That is why the classifier lives in its own file.)
if not isinstance(c, str) or not c.strip():
    raise SystemExit(4)
sys.stdout.write("OK\n")
sys.stdout.write(c)
' 2>/dev/null)
# The parser is the last command in the pipeline and there is no `pipefail`, so this is its own
# status, not the printf's — same reading as classify_rc below. Status is checked as well as the
# sentinel because a parser can print its answer and still die afterwards.
parse_rc=$?
parse_ok=$(printf '%s\n' "$parsed" | sed -n '1p')
command_line=$(printf '%s\n' "$parsed" | sed -n '2,$p')
# Status AND sentinel, as a pair, on every arm: a parser can print its answer and still die
# afterwards, and an interpreter that fails on its own can exit 4 without ever having decided
# anything. `4:` matches only when stdout was empty, which is the shape the block below emits.
case "$parse_rc:$parse_ok" in
  0:OK)   ;;
  0:SKIP) exit 0 ;;
  4:)
    printf 'judge-guard: a Bash call arrived with no runnable command -- failing closed.\n' >&2
    printf 'judge-guard: this hook cannot verify a command it cannot read; re-issue the command, or unregister the hook in settings.json to recover.\n' >&2
    exit 2
    ;;
  *)
    printf 'judge-guard: could not read the PreToolUse payload (malformed JSON, missing tool_name, or python failed) -- failing closed.\n' >&2
    printf 'judge-guard: if this persists, every Bash command stays blocked; unregister the hook in settings.json to recover.\n' >&2
    exit 2
    ;;
esac

# Unreachable by construction: `0:OK` is emitted only after the parser has found a command with a
# non-space character in it. Kept as an assertion rather than deleted, and inverted from the exit 0
# it used to be — if that invariant is ever broken by an edit up there, the failure it produces
# should be a block, not the silent allow that this branch has now found four times.
[ -n "$command_line" ] || {
  printf 'judge-guard: internal error -- parser reported OK with no command -- failing closed.\n' >&2
  exit 2
}

# Classify the command with python — shlex handles the shell quoting a flat bash regex cannot.
# The command line is split into shell segments on control operators (and on newlines, which end a
# command just as `;` does), and EACH segment is tested: a chained or multi-line
# `git push && gh pr create` is guarded exactly like a bare invocation.
# (That chained form used to be an accepted gap; it is what let a PR ship unjudged, so it is now
# caught. A `$(...)`-substituted `gh pr create` is likewise caught, since it too really runs.)
# Quoted text survives as a single token, so `gh pr create` inside a commit message or an echo
# argument can never sit at a segment's command position and is still ignored.
#
# The classifier lives in its own file rather than an inline `python -c` string: quoted in shell,
# a single apostrophe anywhere in it — even in a comment — terminated the quote and broke the whole
# hook, three times. It is also now importable, so bypass shapes get unit tests instead of ad-hoc
# probing. Rationale and the accepted-open shapes: hooks/lib/classify-pr-command.py and ADR 0012.
# Resolved from this script's own directory so the hook works from any $PWD, as the tests do.
CLASSIFIER="$(cd "$(dirname "$0")" && pwd)/lib/classify-pr-command.py"
classify=$(printf '%s' "$command_line" | "$py" "$CLASSIFIER" 2>/dev/null)
# No `set -e` and no `pipefail` here, so this is the classifier's own status, not the printf's.
classify_rc=$?
kind=$(printf '%s\n' "$classify" | sed -n '1p')
exempt_reason=$(printf '%s\n' "$classify" | sed -n '2p')

# An inability to verify blocks — same rule as the missing-python branch above, and the same
# single-source-of-truth stance as the verdict store: a broken install surfaces as a named-path
# error rather than being papered over.
# This validates the classifier's OUTPUT rather than the file's existence, because `[ -f ]` only
# catches an absent file. A present-but-unusable one — empty, truncated by a partial checkout
# (the case ADR 0012 cites as motivation), syntactically broken, or unreadable — produces no
# output past the `2>/dev/null`, leaving `kind` empty. Under a file-existence check that fell
# through to `exit 0` and silently passed every `gh pr create`: a gate that looks armed and does
# nothing, which is the exact defect this hook exists to prevent. `kind` is only ever PR or NO,
# so anything else means the classifier did not run, whatever the reason.
# The cost is deliberate and accepted: with no usable classifier, nothing can distinguish a PR
# command from any other, so ALL Bash commands block until the install is repaired (ADR 0012).
# That is also why the message must name a repair route that survives the block — git and every
# other shell command is denied while this holds, so pointing at one would be a dead end.
# Status is checked as well as shape, because a classifier can answer and still have failed: one
# that prints a well-formed NO and then dies leaves `kind` holding a legal value, and shape alone
# would pass it. That is only unreachable against today's classifier because it happens to print
# its answer last — the classifier's shape protecting the hook rather than the hook protecting
# itself, which stops holding the moment the classifier is refactored.
case "$classify_rc:$kind" in
  0:PR|0:NO) ;;
  *)
    printf 'judge-guard: classifier at %s produced no usable output -- failing closed (it is missing, empty, truncated, or broken).\n' "$CLASSIFIER" >&2
    printf 'judge-guard: ALL Bash commands are blocked until it is repaired, so repair it with the Write tool, or unregister the hook in settings.json.\n' >&2
    exit 2
    ;;
esac

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
