#!/usr/bin/env bash
# judge-guard.test.sh — unit tests for judge-guard.sh.
# Feeds PreToolUse JSON on stdin (the code path that actually runs in production),
# overriding the verdicts file and running inside a throwaway git repo so no real
# state is touched. Run: bash hooks/judge-guard.test.sh
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/judge-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cd "$TMP" || exit 1
git init -q
git config user.email t@t.t
git config user.name t
git commit -q --allow-empty -m init
SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
REPO="$(basename "$(git rev-parse --show-toplevel)")"

VFILE="$TMP/verdicts.jsonl"
export JUDGE_VERDICTS_FILE="$VFILE"

pass=0; fail=0
run_case() { # $1 desc, $2 want-exit, $3 command
  local desc="$1" want="$2" cmd="$3" payload got
  payload=$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); fi
}
line() { # emit a verdict line with given stage/repo/branch/sha
  python3 -c 'import json,sys; print(json.dumps({"stage":sys.argv[1],"repo":sys.argv[2],"branch":sys.argv[3],"head_sha":sys.argv[4]}))' "$@"
}

: > "$VFILE";                                   run_case "non-gh command passes"            0 "git status"
rm -f "$VFILE";                                 run_case "gh pr create, no verdicts -> block" 2 "gh pr create --fill"
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"; run_case "fresh verdict -> pass"     0 "gh pr create --fill"
line implementation "$REPO" "$BRANCH" deadbeef > "$VFILE"; run_case "stale sha -> block"       2 "gh pr create --fill"
line implementation "$REPO" other "$SHA"      > "$VFILE"; run_case "wrong branch -> block"      2 "gh pr create --fill"
line architecting  "$REPO" "$BRANCH" "$SHA"   > "$VFILE"; run_case "architecting stage -> block" 2 "gh pr create --fill"
rm -f "$VFILE";                                 run_case "JUDGE_EXEMPT=<reason> -> pass"     0 "JUDGE_EXEMPT=hotfix gh pr create --fill"
rm -f "$VFILE";                                 run_case "JUDGE_EXEMPT= (empty) -> block"    2 "JUDGE_EXEMPT= gh pr create --fill"
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"; run_case "gh pr list unaffected"     0 "gh pr list"

# Regression: the phrase inside another command must NOT trigger the guard.
rm -f "$VFILE"
run_case "commit msg containing phrase -> ignore" 0 'git commit -m "feat: blocking gh pr create without a verdict"'
run_case "echo containing phrase -> ignore"       0 "echo gh pr create"

# Regression (round 2): a quoted-space env prefix must NOT silently bypass the guard.
rm -f "$VFILE"
run_case "quoted-space env prefix, no verdict -> block" 2 'FOO="a b" gh pr create --fill'
run_case "quoted multi-word JUDGE_EXEMPT -> exempt pass" 0 'JUDGE_EXEMPT="skip, docs only" gh pr create --fill'
# Exit code alone can't distinguish a silent bypass from a real exemption (both exit 0),
# so assert the quoted JUDGE_EXEMPT path actually LOGS its exemption.
rm -f "$VFILE"
exempt_payload=$(python3 -c 'import json; print(json.dumps({"hook_event_name":"PreToolUse","tool_input":{"command":"JUDGE_EXEMPT=\"skip, docs only\" gh pr create --fill"}}))')
exempt_out=$(printf '%s' "$exempt_payload" | bash "$HOOK" 2>&1)
if printf '%s' "$exempt_out" | grep -q 'exempted (JUDGE_EXEMPT=skip, docs only)'; then
  printf 'ok   — quoted JUDGE_EXEMPT logs exemption\n'; pass=$((pass+1))
else
  printf 'FAIL — quoted JUDGE_EXEMPT did not log exemption (got: %s)\n' "$exempt_out"; fail=$((fail+1))
fi

# Regression: RTK rewrites commands in this environment, so a leading `rtk ` wrapper is
# stripped before classification — `rtk gh pr create` must be guarded like a bare invocation.
rm -f "$VFILE"
run_case "rtk-wrapped invocation, no verdict -> block"   2 "rtk gh pr create --fill"
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"
run_case "rtk-wrapped invocation, fresh verdict -> pass" 0 "rtk gh pr create --fill"

# Regression: with no JUDGE_VERDICTS_FILE override, the guard must read the JUDGED REPO's
# store. The judge writes verdicts repo-relative (agents/observability-judge.md: "Write ONLY
# under coding-memory/observability-judge/"), but the guard used to read $HOME/.claude's copy.
# Those two paths coincide only for the ~/.claude repo itself, so in every other repo the gate
# was permanently unsatisfiable — no verdict could ever be found, however many were recorded.
run_case_default() { # $1 desc, $2 want-exit, $3 command — runs with JUDGE_VERDICTS_FILE unset
  local desc="$1" want="$2" cmd="$3" payload got
  payload=$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  ( unset JUDGE_VERDICTS_FILE; printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1 )
  got=$?
  if [ "$got" -eq "$want" ]; then printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); fi
}

RVFILE="$TMP/coding-memory/observability-judge/verdicts.jsonl"
mkdir -p "$(dirname "$RVFILE")"
rm -f "$RVFILE"
run_case_default "repo store absent -> block"              2 "gh pr create --fill"
line implementation "$REPO" "$BRANCH" "$SHA"   > "$RVFILE"
run_case_default "fresh verdict in repo store -> pass"     0 "gh pr create --fill"
line implementation "$REPO" "$BRANCH" deadbeef > "$RVFILE"
run_case_default "stale sha in repo store -> block"        2 "gh pr create --fill"
rm -f "$RVFILE"

# Regression: a chained `gh pr create` must be GUARDED, not skipped. This inverts a previously
# documented-and-asserted gap ("chained && -> ignore"): that gap is what let vibe-scape's PR #25
# ship with no verdict at all, because push-then-create was issued as one chained Bash call.
# The quoted-phrase cases above must keep passing — detection is per shell segment, not a
# substring match, so `gh pr create` inside a commit message is still ignored.
rm -f "$VFILE"
run_case "chained && -> block"             2 "cd /tmp && gh pr create --fill"
run_case "chained && no spaces -> block"   2 "git push&&gh pr create --fill"
run_case "chained ; -> block"              2 "git push; gh pr create --fill"
run_case "chained || -> block"             2 "git push || gh pr create --fill"
run_case "piped | -> block"                2 "foo | gh pr create --fill"
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"
run_case "chained && with fresh verdict -> pass" 0 "git push && gh pr create --fill"
rm -f "$VFILE"
run_case "chained && with JUDGE_EXEMPT on gh segment -> pass" 0 'git push && JUDGE_EXEMPT="docs only" gh pr create --fill'

# Regression: bash treats a NEWLINE as a command separator exactly like `;`, but shlex counts it
# as ordinary whitespace, so `git push` and `gh pr create` on two lines of a single Bash call
# lexed into ONE segment and no command ever sat at a segment's position 0. Same defect class the
# chained cases above close, and multi-line command strings are a routine shape, not an exotic one.
rm -f "$VFILE"
run_case "newline-separated -> block"           2 $'git push -u origin br\ngh pr create --fill'
run_case "newline, blank line between -> block" 2 $'git push\n\ngh pr create --fill'
run_case "newline after a && chain -> block"    2 $'cd /tmp && git push\ngh pr create --fill'
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"
run_case "newline-separated, fresh verdict -> pass" 0 $'git push\ngh pr create --fill'
rm -f "$VFILE"
run_case "newline, JUDGE_EXEMPT on gh line -> pass" 0 $'git push\nJUDGE_EXEMPT="docs only" gh pr create --fill'
# The false-positive protection must survive the newline split: a multi-line quoted commit
# message stays a single token, so its embedded phrase never occupies a segment's command slot.
run_case "multi-line quoted commit msg -> ignore" 0 $'git commit -m "feat: guard\n\ngh pr create must block"'

# Regression: four more shapes that reached `gh pr create` without a verdict. Found by measuring
# the hook against real command forms rather than by reasoning about it — the plain-newline fix
# above closed one shape and left its nearest neighbour (`\` + newline) open, which is exactly the
# kind of gap that survives a review that only reads the diff.
#
# 1. A backslash-newline is a line CONTINUATION: bash joins the two lines into one command, so
#    this is the already-guarded `&&` chain wearing a different coat. Deleting the pair before the
#    newline translation routes it back into that path rather than adding a new matcher.
rm -f "$VFILE"
run_case "backslash-newline continuation -> block"  2 $'git push -u origin br && \\\ngh pr create --fill'
run_case "backslash-newline, plain -> block"        2 $'git push \\\n&& gh pr create --fill'
# 2. `gh -R owner/repo pr create` is a valid, documented gh form; `pr` simply is not token 1.
run_case "gh with global -R flag -> block"          2 "gh -R owner/repo pr create --fill"
run_case "gh with --repo flag -> block"             2 "gh --repo owner/repo pr create --fill"
# 3. Backticks are legacy command substitution and really run. Translating them to `;` DID catch
#    them, and was reverted: shlex cannot see heredocs, so the same translation made any heredoc
#    body containing a backticked `gh pr create` fail CLOSED — and writing exactly that text is
#    routine in this repo (`git commit -m "$(cat <<'MSG'` with an ADR table in the body). A rare
#    false negative was traded for a common false positive that blocks legitimate work, so the
#    backtick form stays a documented open shape. Asserted here so the choice is deliberate and
#    visible, not an accident.
run_case "backtick substitution -> ignore (known)"  0 'echo `gh pr create --fill`'
run_case "heredoc w/ backticked phrase -> ignore"   0 $'cat <<EOF\nsee `gh pr create` docs\nEOF'
# 4. Keyword/builtin prefixes sit at the command position and displace `gh`, exactly as the
#    already-stripped `rtk` wrapper does.
run_case "time prefix -> block"                     2 "time gh pr create --fill"
run_case "eval prefix -> block"                     2 "eval gh pr create --fill"
run_case "command prefix -> block"                  2 "command gh pr create --fill"
run_case "stacked prefixes -> block"                2 "time rtk gh pr create --fill"
# The fresh-verdict and exemption paths must still work through each new shape.
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"
run_case "continuation, fresh verdict -> pass"      0 $'git push && \\\ngh pr create --fill'
run_case "gh -R, fresh verdict -> pass"             0 "gh -R owner/repo pr create --fill"
rm -f "$VFILE"
run_case "time prefix, JUDGE_EXEMPT -> pass"        0 'time JUDGE_EXEMPT="docs only" gh pr create --fill'
# False-positive protection must survive all four: quoted text is one token and can never occupy a
# segment command slot, and a bare `pr create` with no `gh` at the command position is not a match.
run_case "quoted continuation in msg -> ignore"     0 $'git commit -m "see \\\ngh pr create"'
run_case "quoted backtick phrase -> ignore"         0 'git commit -m "run `gh pr create` first"'
run_case "gh pr list is not create -> ignore"       0 "gh -R owner/repo pr list"
run_case "pr create without gh -> ignore"           0 "mytool pr create --fill"

# Regression: a brace group opens a command context, but `{` is not one of shlex's punctuation
# chars, so it lexes as an ordinary token and sits at the segment command position, displacing
# `gh`. Round 2 of review reported this and a later re-measurement WRONGLY overturned it by
# testing `{ git push; gh pr create; }` -- a different string, which blocks because `git` takes
# the command slot and the `;` then opens a fresh segment. Both are pinned here so the distinction
# cannot be lost again.
rm -f "$VFILE"
run_case "brace group alone -> block"               2 "{ gh pr create --fill; }"
run_case "brace group after a command -> block"     2 "{ git push; gh pr create --fill; }"
run_case "subshell paren group -> block"            2 "( gh pr create --fill )"

# Regression: extracting the classifier to hooks/lib/ introduced a failure mode that could not
# exist while it was an inline string — the file can be ABSENT (a partial checkout, or a hook
# copied on its own, which has happened in this repo). An absent classifier produces no output, so
# `kind` is empty and the hook exits 0: the gate then silently passes every `gh pr create`. That is
# exactly the "gate that looks armed and does nothing" defect this line of work exists to remove,
# so it must fail CLOSED naming the path, as the missing-python branch already does.
run_case_at() { # $1 hook path, $2 desc, $3 want-exit, $4 command
  local hook="$1" desc="$2" want="$3" cmd="$4" payload got
  payload=$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  printf '%s' "$payload" | bash "$hook" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); fi
}
BROKEN="$TMP/brokenhook"
mkdir -p "$BROKEN"
cp "$HOOK" "$BROKEN/judge-guard.sh"   # deliberately WITHOUT a lib/ alongside it
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"
run_case_at "$BROKEN/judge-guard.sh" "missing classifier, gh pr create -> block" 2 "gh pr create --fill"
# Indiscriminate by design: with no classifier there is no way to tell a PR command from any other,
# so unrelated commands block too. A loud, self-describing halt beats a silently dead gate — and it
# mirrors the missing-python branch, which already blocks everything for the same reason.
run_case_at "$BROKEN/judge-guard.sh" "missing classifier, unrelated cmd -> block" 2 "git status"
# A fail-closed that does not name the path is unfixable in practice, so assert the message too.
broken_payload=$(python3 -c 'import json; print(json.dumps({"hook_event_name":"PreToolUse","tool_input":{"command":"gh pr create"}}))')
broken_out=$(printf '%s' "$broken_payload" | bash "$BROKEN/judge-guard.sh" 2>&1)
if printf '%s' "$broken_out" | grep -q 'classify-pr-command.py'; then
  printf 'ok   — missing classifier names the path\n'; pass=$((pass+1))
else
  printf 'FAIL — missing classifier did not name the path (got: %s)\n' "$broken_out"; fail=$((fail+1))
fi
# The intact hook must be unaffected — this is the control for the three cases above.
run_case_at "$HOOK" "intact classifier still classifies -> pass" 0 "gh pr create --fill"

# --- A classifier that is PRESENT but UNUSABLE ---------------------------------------------------
# The cases above only cover an ABSENT file, because `[ ! -f ]` is all the hook checks. But the
# partial-checkout story that motivates ADR 0012 produces a TRUNCATED file at least as readily as a
# missing one, and `2>/dev/null` on the classifier call swallows every interpreter error. So each
# shape below yields empty output, `kind` is empty, and the hook exits 0 — the same silently-dead
# gate the missing-file branch was added to remove, just reached by a different route.
# $VFILE deliberately still holds a FRESH verdict, so a working classifier would exit 0 here: an
# exit of 2 can therefore only have come from the fail-closed path, never from a stale verdict.
UNUSABLE="$TMP/unusablehook"
mkdir -p "$UNUSABLE/lib"
cp "$HOOK" "$UNUSABLE/judge-guard.sh"
install_broken() { # $1 shape
  chmod 644 "$UNUSABLE/lib/classify-pr-command.py" 2>/dev/null
  case "$1" in
    empty)      : > "$UNUSABLE/lib/classify-pr-command.py" ;;
    syntax)     printf 'def (\n' > "$UNUSABLE/lib/classify-pr-command.py" ;;
    truncated)  head -c 400 "$(dirname "$HOOK")/lib/classify-pr-command.py" \
                  > "$UNUSABLE/lib/classify-pr-command.py" ;;
    unreadable) cp "$(dirname "$HOOK")/lib/classify-pr-command.py" "$UNUSABLE/lib/"
                chmod 000 "$UNUSABLE/lib/classify-pr-command.py" ;;
    # A classifier can answer and *still* have failed. Validating only the shape of the answer
    # accepts these: both print a well-formed NO, so `kind` is a legal value and the hook exits 0
    # with the gate silently disarmed. They are unreachable against today's real classifier only
    # because it happens to print its answer last — that is the classifier's shape protecting the
    # hook, not the hook protecting itself, and it is the kind of incidental invariant that stops
    # holding the moment the classifier is refactored.
    answer_then_fail)  printf 'print("NO")\nprint("")\nraise SystemExit(1)\n' \
                         > "$UNUSABLE/lib/classify-pr-command.py" ;;
    answer_then_crash) printf 'print("NO")\nprint("")\nraise RuntimeError("boom")\n' \
                         > "$UNUSABLE/lib/classify-pr-command.py" ;;
  esac
}
for shape in empty syntax truncated answer_then_fail answer_then_crash; do
  install_broken "$shape"
  run_case_at "$UNUSABLE/judge-guard.sh" "$shape classifier, gh pr create -> block" 2 "gh pr create --fill"
done
# Root can read a chmod 000 file, so this shape proves nothing when the suite runs as root.
if [ "$(id -u)" -ne 0 ]; then
  install_broken unreadable
  run_case_at "$UNUSABLE/judge-guard.sh" "unreadable classifier, gh pr create -> block" 2 "gh pr create --fill"
  chmod 644 "$UNUSABLE/lib/classify-pr-command.py" 2>/dev/null
else
  printf 'skip — unreadable classifier (running as root)\n'
fi
# Blocking every Bash command is what makes the repair route load-bearing: the operator cannot run
# git or any shell command to restore the file, so a message pointing at one is a dead end. Assert
# the message names a route that still works under the block rather than merely naming the path.
install_broken truncated
unusable_out=$(printf '%s' "$broken_payload" | bash "$UNUSABLE/judge-guard.sh" 2>&1)
if printf '%s' "$unusable_out" | grep -qi 'write tool\|unregister'; then
  printf 'ok   — unusable classifier names a repair route that survives the block\n'; pass=$((pass+1))
else
  printf 'FAIL — unusable classifier message gives no usable repair route (got: %s)\n' "$unusable_out"
  fail=$((fail+1))
fi

# --- PAYLOAD PARSER: a parse failure must not read as "no command" -------------------------------
# Everything above enters through a well-formed payload, so the parser that produces `command_line`
# was itself untested. Its `except ValueError: sys.exit(0)` — plus `2>/dev/null` on the call —
# collapsed four outcomes into one silent exit 0: malformed JSON, a non-JSON payload, a payload
# whose shape crashes the parser, and an interpreter that fails outright. Exactly ONE of the four is
# legitimate: valid JSON carrying no `command` string is not a Bash call and must pass. Because
# nothing downstream can tell the four apart, a garbled payload disarmed the gate the same way an
# absent classifier did — the defect this whole line of work exists to remove, reached by a third
# route. So the parser must SAY it ran, not merely fail to say anything.
# $VFILE deliberately holds a FRESH verdict here, so a working hook exits 0 on a real `gh pr create`
# (asserted as the control below): an exit of 2 can only have come from the fail-closed parse path.
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"
run_payload() { # $1 desc, $2 want-exit, $3 raw payload written to stdin verbatim
  local desc="$1" want="$2" raw="$3" got
  printf '%s' "$raw" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); fi
}
run_payload "truncated JSON -> block"       2 '{"hook_event_name":"PreToolUse","tool_input":{"command":'
run_payload "non-JSON payload -> block"     2 'not json at all'
# Valid JSON of the wrong SHAPE: `.get` on a list raises AttributeError, so the parser dies with an
# empty stdout — indistinguishable, under the old check, from a deliberate "nothing to guard".
run_payload "JSON array payload -> block"   2 '[1, 2, 3]'
run_payload "JSON scalar payload -> block"  2 '"just a string"'
# The three shapes that must still PASS. These are the whole reason the fix cannot simply block on
# empty output: every non-Bash tool call in the session reaches this hook, and blocking them would
# take the editor down with the gate.
run_payload "no tool_input -> pass"                 0 '{"hook_event_name":"PreToolUse"}'
run_payload "tool_input without a command -> pass"  0 '{"hook_event_name":"PreToolUse","tool_input":{"file_path":"/tmp/x"}}'
run_payload "empty command string -> pass"          0 '{"hook_event_name":"PreToolUse","tool_input":{"command":""}}'
run_payload "non-string command -> pass"            0 '{"hook_event_name":"PreToolUse","tool_input":{"command":42}}'
# Control: the same fresh verdict, through a well-formed payload, still allows the PR.
run_case "control: fresh verdict still passes" 0 "gh pr create --fill"

# An interpreter that is FOUND but fails is the parser-side twin of the unusable classifier: the
# existing `command -v python3` check only proves a file is on PATH, and `2>/dev/null` hides
# whatever it does next. Stubbed rather than mutated, so this exercises the real hook end to end.
STUBBIN="$TMP/stubbin"
mkdir -p "$STUBBIN"
printf '#!/bin/sh\nexit 1\n' > "$STUBBIN/python3"
cp "$STUBBIN/python3" "$STUBBIN/python"   # `command -v python` is the documented fallback
chmod 755 "$STUBBIN/python3" "$STUBBIN/python"
good_payload=$(python3 -c 'import json; print(json.dumps({"hook_event_name":"PreToolUse","tool_input":{"command":"gh pr create --fill"}}))')
( PATH="$STUBBIN:$PATH"; printf '%s' "$good_payload" | bash "$HOOK" >/dev/null 2>&1 )
stub_rc=$?
if [ "$stub_rc" -eq 2 ]; then
  printf 'ok   — failing python interpreter -> block (exit 2)\n'; pass=$((pass+1))
else
  printf 'FAIL — failing python interpreter (want 2, got %s)\n' "$stub_rc"; fail=$((fail+1))
fi

# A fail-closed that does not say WHICH stage refused is indistinguishable from the classifier's,
# and the two have different repairs — so the message must name the payload.
parse_out=$(printf '%s' 'not json at all' | bash "$HOOK" 2>&1)
if printf '%s' "$parse_out" | grep -qi 'payload'; then
  printf 'ok   — parse failure names the payload as the cause\n'; pass=$((pass+1))
else
  printf 'FAIL — parse failure gave no usable cause (got: %s)\n' "$parse_out"; fail=$((fail+1))
fi

# The classifier's own unit suite runs here too, so one command covers both layers and the python
# cases cannot rot unnoticed. Detail on failure comes from running that file directly.
if python3 "$(dirname "$HOOK")/lib/classify-pr-command.test.py" >/dev/null 2>&1; then
  printf 'ok   — classifier unit suite\n'; pass=$((pass+1))
else
  printf 'FAIL — classifier unit suite (run hooks/lib/classify-pr-command.test.py for detail)\n'
  fail=$((fail+1))
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
