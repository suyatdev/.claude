#!/usr/bin/env bash
#
# phase-guard.sh — PreToolUse hook (matcher: Edit|Write|NotebookEdit).
#
# Computational enforcement of the phase gate. A feature file sitting at
# `phase: planning` means implementation has not been authorized yet, so a write to
# source is denied until the gate opens. Permission is branch-scoped: a feature whose
# gate has opened claims a branch, and the guard only blocks on branches no feature
# file claims. Design and scenarios: docs/features/phase-guard-hook.md.
#
# Exit 0 = allow (silent). Exit 2 = deny, reason on stderr. No other exit code is
# legitimate: under `set -u` an unbound variable exits 1, and a fail-open path that
# leaks a nonzero code is a defect regardless of how the harness classifies it. Every
# fail-open exit below is therefore an explicit `exit 0`, and stdout is empty on every
# path without exception.
#
# Fail-open everywhere except the final deny. This hook fires on every write in every
# repo on this machine, so a false block costs a whole session in repos that never
# opted in. That is the deliberate divergence from judge-guard.sh, which fails closed
# because it guards one rare command where a false block costs a single retry.
#
# Regexes live in variables, never inline in `[[ ]]` — the trap at git-guard.sh:22.

set -u

LF='
'

# --- The exits that must not be silent -------------------------------------------------
# THE RULE, and it is the whole design: once this hook knows the repo is opted in AND holds
# an un-superseded `planning` card, it was on its way to DENY. Any later inability to finish
# the evaluation is the guard being switched off in exactly the state where it was about to
# do its job — a state in which a working guard and a dead one are byte-identical, since
# every ⊘ emits nothing. Those exits speak. Everything UPSTREAM of that knowledge ("not a
# repo", "not opted in", "this path is not guarded") stays silent, because there the hook
# genuinely has nothing to say.
#
# This rule replaced instance-patching. Four judge rounds each found one exit that went
# silent, every one a step earlier than the last — the tally, then the supersession exit,
# then the entry counting, then the directory listing. Each fix was locally correct and each
# was followed by a new instance, because the surface was being explored reactively. The
# audit enumerates it instead; Group A4 in the test suite is that enumeration, and four of
# the cases below were previously asserted SILENT by the suite itself.
#
# Every one still exits 0, and every one prints AT MOST ONCE PER SESSION: this hook fires on
# every write, and a line per write would be noise the reader learns to skip past. A flapping
# git therefore costs one line per session, not one per write.
STATE_DIR="${PHASE_GUARD_STATE_DIR:-$HOME/.claude/hooks/state}"
# The environment id is the ONLY key available to the no-interpreter exit — that branch
# fires because the JSON parser is what failed, so the payload's own session_id is by
# construction unreadable there.
sid_env="${CLAUDE_CODE_SESSION_ID:-}"

NOPYTHON_MSG='phase-guard: no python3 or python on PATH — the phase gate is not being enforced in any repo until that is fixed.'
# Phrased conditionally on purpose. The glob takes every *.md in docs/features/, so an ordinary
# README.md there is "skipped" too — and telling a session the gate cannot be evaluated when the
# only unreadable file was never a feature card is a false alarm, on the one hook that fires on
# every write. "if it is one" is true in both cases and still names the real risk in the case
# that matters. What a non-card file in docs/features/ should MEAN is a contract question, left
# open deliberately rather than settled by a message.
NOPARSE_MSG='phase-guard: a file in docs/features/ could not be read as a feature card and was skipped — if it is one, the gate is not seeing it.'
# The directory exists (step 3 passed) but cannot be listed, so EVERY card vanishes at once and
# the skip tally has nothing to compare — the repo looks opted-in and unguarded at the same time.
# Distinct from NOPARSE because the fix is different: this one is a permission, not a typo.
NOLIST_MSG='phase-guard: docs/features/ cannot be listed (check its permissions) — this repo opted in, but no card can be read, so the gate is not being enforced here.'
# A git query the evaluation depends on failed while an un-superseded planning card was active.
# Transient by nature, which is why it fails OPEN rather than closed — but never silently, or a
# flaky git is indistinguishable from an approved branch.
NOGIT_MSG='phase-guard: a git query needed to finish the phase check failed — a planning card is active, so this write was NOT checked against it.'

# One flag file per reason, so whichever fires first never suppresses the other: a session
# told the guard is dead for the wrong reason would go fix the wrong thing.
warn_once() { # $1 reason (nopython|noparse), $2 session id ("" -> nosession), $3 message
  local flag="$STATE_DIR/phase-guard-$1-${2:-nosession}"
  [ -e "$flag" ] && return 0
  printf '%s\n' "$3" 1>&2
  # Store failures are swallowed, and the line is printed BEFORE the store is touched at
  # all. This is the deliberate divergence from context-handoff-watch.sh:42, which bails
  # silently (`|| exit 0`) when its store is unwritable: that sibling's flag gates a nudge,
  # while this one gates the warning that the guard is DEAD — and a fix for silent failure
  # that itself fails silently is the original problem one level up. The cost is that an
  # unwritable store degrades this to once per write, which is the right way to fail.
  mkdir -p "$STATE_DIR" 2>/dev/null && : > "$flag" 2>/dev/null
  return 0
}

# --- Step 1: the payload -------------------------------------------------------------
payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi
[ -n "$payload" ] || exit 0

# --- Step 2: the repository root ------------------------------------------------------
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$root" ] || exit 0

# --- Step 3: did this repo opt in? ----------------------------------------------------
# The hottest path in the design — it runs on every write in every repo — so this is a
# bash builtin, not a `stat` subprocess. Deliberately AFTER step 2: a bare
# `./docs/features` test assumes the hook's CWD is the repo root, and would silently
# stop guarding from any subdirectory.
[ -d "$root/docs/features" ] || exit 0

# --- Step 4: the interpreter, then the path out of the payload ------------------------
py=$(command -v python3 || command -v python) || py=""
# The first of the two exits that must not stay silent: with no interpreter the guard is
# off in every repo on this machine, permanently, until PATH is fixed.
if [ -z "$py" ]; then
  warn_once nopython "$sid_env" "$NOPYTHON_MSG"
  exit 0
fi

# Step 1 catches only *empty* stdin, so a truncated or non-JSON payload reaches this
# parser. Every failure to produce a usable path takes the same silent fail-open: an
# unhandled traceback exits nonzero, which a PreToolUse harness may read as deny.
# NotebookEdit carries no file_path — notebook_path is its only path key, so reading
# file_path alone would fail open on every notebook write.
#
# session_id rides along in the SAME subprocess rather than a second one: this is the hot
# path, and the noparse exit below needs the payload's id in preference to the
# environment's. Emitted as `<session_id>\n<file_path>` — the id can never contain a
# newline, so the first LF is an unambiguous separator, while a path (which can) keeps
# everything after it.
parsed=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
    ti = p.get("tool_input") or {}
    sys.stdout.write((p.get("session_id") or "") + "\n" +
                     (ti.get("file_path") or ti.get("notebook_path") or ""))
except Exception:
    sys.exit(0)
') || parsed=""

# Command substitution strips trailing newlines, so a payload carrying no usable path
# collapses to a single line with no LF left in it. That case fails open one line below
# and needs no session id to do it, which is why losing the id with it costs nothing.
case "$parsed" in
  *"$LF"*) sid_payload=${parsed%%"$LF"*}; file_path=${parsed#*"$LF"} ;;
  *)       sid_payload=""; file_path="" ;;
esac
[ -n "$file_path" ] || exit 0

# --- Step 5: relativize against the root ----------------------------------------------
# Payload paths are absolute. A path outside this repository is not ours to judge.
case "$file_path" in
  "$root"/*) rel=${file_path#"$root"/} ;;
  *) exit 0 ;;
esac

# --- Step 6: is this path guarded at all? ---------------------------------------------
# doc-guard.sh:149's list verbatim, plus .claude/* and settings.json. settings.json is
# exempt because it holds this hook's own registration, and a guard that can block edits
# to its own off switch is a footgun. The escape hatch for a stale planning file is to
# edit that file, which works because feature files live under docs/**.
case "$rel" in
  CODING_MEMORY.md|coding-memory/*|docs/*|.claude/*|settings.json) exit 0 ;;
esac

# --- Step 7: which feature files sit at phase: planning? --------------------------------
# The frontmatter contract, one awk pass per file. Well-formed iff line 1 is exactly `---`,
# a closing `---` follows, and between them sit exactly one `phase:` line carrying one of
# the three legal values and at most one `branch:` line. Unknown keys between the fences are
# ignored, so model_tier and future keys stay forward-compatible.
#
# Anything else is SKIPPED, never guessed at. That is why the value is matched against the
# legal three rather than merely tested for "planning": a `phase: plannning` typo must not
# read as "not planning, therefore allow". A skip still costs the gate that file's opinion —
# the guarantee is that it cannot cost it SILENTLY, which the tally below the loop is what
# actually delivers.
#
# Prints the phase value for a well-formed file, nothing for a malformed one. Awk missing or
# failing therefore reads as malformed, which fails open — consistent with every other ⊘.
#
# A skipped file in an opted-in repo is the "cannot evaluate" case, and the second of the two
# exits that must not be silent — see the tally below the loop.
TAB='	'
# The parser emits `<phase>TAB<branch>` for a well-formed file and NOTHING for a malformed one,
# so a single evaluation of the contract feeds both the planning tally and step 9's claim check.
#
# It used to emit the phase alone, and step 9 re-derived the claim with its own `grep -Eq` +
# `sed` over the raw file. That was a fail-open (B2b/B2c): both matchers were unbounded, so any
# text ANYWHERE in the file that looked like `phase: implementation` plus `branch: <name>`
# granted permission — and feature files are exactly the documents that quote those keys in
# prose. Worse, a file this parser had already SKIPPED as malformed still got a vote, because
# step 9 never consulted the parser's verdict. A file the contract cannot read has no opinion
# the hook is entitled to act on, least of all the one that unlocks writing.
#
# The branch value keeps the old single-token strictness. A malformed value yields an EMPTY
# branch rather than invalidating the file, which preserves A3.7: an unusable `branch:` leaves
# the feature unclaimed, and unclaimed is a deny, never a skip.
# shellcheck disable=SC2016  # $0 is awk's own, not a shell expansion — it must not expand.
FRONTMATTER_AWK='
NR == 1     { if ($0 != "---") exit; next }
$0 == "---" { closed = 1; exit }
/^phase:/   { nphase++; phase = $0 }
/^branch:/  { nbranch++; branch = $0 }
END {
  if (!closed || nphase != 1 || nbranch > 1) exit
  if (phase !~ /^phase:[[:space:]]*(planning|implementation|review)[[:space:]]*$/) exit
  sub(/^phase:[[:space:]]*/, "", phase)
  sub(/[[:space:]]*$/, "", phase)
  if (branch !~ /^branch:[[:space:]]*[^[:space:]]+[[:space:]]*$/) branch = ""
  else { sub(/^branch:[[:space:]]*/, "", branch); sub(/[[:space:]]*$/, "", branch) }
  print phase "\t" branch
}'

# Step 3 established the directory EXISTS; this establishes it can actually be LISTED. Both bits
# are needed and they fail independently: at mode 444 the shell still expands the glob to the real
# filenames, so entries are known to exist, but `-e`/`-L` need SEARCH permission and every one is
# dropped uncounted — nfiles stays 0, the skip tally has nothing to compare, and the repo reads as
# opted-in and unguarded at the same time. Checked here rather than at step 3 because the payload's
# session id is only parsed at step 4, and the once-per-session key should prefer it.
if [ ! -r "$root/docs/features" ] || [ ! -x "$root/docs/features" ]; then
  warn_once nolist "${sid_payload:-$sid_env}" "$NOLIST_MSG"
  exit 0
fi

planning_files=""
claimed_branches=""
nfiles=0
nparsed=0
for f in "$root"/docs/features/*.md; do
  # EXISTS IN ANY FORM is the test, and the only thing filtered out is a glob that matched
  # nothing. `-f` was wrong here because it silently did two jobs: detect the unexpanded glob
  # in an empty directory, and drop every entry that is not a regular file — a dangling
  # symlink, a directory named *.md. A dropped entry is never counted, so the skip tally below
  # could not trip on it and the guard went silent one step earlier than any exit. A card
  # symlinked in here whose target is moved denies one moment and stops denying the next.
  # `-L` is needed beside `-e`: `-e` follows the link and is FALSE for a dangling one, which is
  # exactly the entry that must still count.
  [ -e "$f" ] || [ -L "$f" ] || continue
  nfiles=$((nfiles + 1))
  # awk's own stderr is discarded: an entry it cannot open (mode 000, a directory) makes it
  # write a diagnostic per invocation, which reaches the user on EVERY write and escapes the
  # once-per-session suppression that the warning below is careful to respect. The failure is
  # not lost — an unopenable entry produces no output, which is already the skip signal.
  parsed_fm=$(awk "$FRONTMATTER_AWK" "$f" 2>/dev/null)
  # Empty output IS the skip signal: the parser prints a record for a well-formed file and
  # nothing for one it cannot read or cannot parse, so this counts what could be read.
  [ -n "$parsed_fm" ] || continue
  nparsed=$((nparsed + 1))
  file_phase=${parsed_fm%%"$TAB"*}
  file_branch=${parsed_fm#*"$TAB"}
  # Collected in THIS loop, from THIS parse, so a claim can only come from a file the contract
  # accepted. Step 9 checks membership rather than re-reading anything off disk.
  if [ "$file_phase" = "implementation" ] && [ -n "$file_branch" ]; then
    claimed_branches="$claimed_branches$file_branch
"
  fi
  [ "$file_phase" = "planning" ] || continue
  planning_files="$planning_files${f#"$root"/}
"
done

# The second exit that must not be silent — checked HERE, immediately after the parse loop,
# rather than at any one exit below. A skipped card is unreadable no matter which path the hook
# then takes, and every path from here but one ends in an allow. Two conditions, both learned
# the hard way:
#
#   "was ANY card skipped", not "were they ALL". One readable card is enough to make an
#   all-skipped tally false, so a repo holding one good card and one unreadable card allowed
#   the write without a word — and the unreadable one is precisely the card that might have
#   denied.
#
#   ...and placed before every exit, not inside one. The first fix for that lived inside the
#   no-planning-files branch below, which left step 8's supersession exit silent in exactly the
#   same way one stage further down. Guarding exits one at a time is what produced the same bug
#   twice; one check upstream of all of them is what stops it recurring. A2.15 and A2.18 pin the
#   two routes, A2.17 pins that a repo whose cards all parse stays quiet.
#
# Zero files makes the comparison false on its own, so this cannot fire in a repo that created
# docs/features/ and nothing else.
if [ "$nfiles" -gt "$nparsed" ]; then
  warn_once noparse "${sid_payload:-$sid_env}" "$NOPARSE_MSG"
fi

[ -n "$planning_files" ] || exit 0

# --- Step 8: drop the superseded ---------------------------------------------------------
# A planning file whose gate has already opened on some branch must stop denying everywhere:
# its stale copy on main is stale BY DESIGN once the gate opened. `review` counts as well as
# `implementation`, or a finished feature whose main copy still reads planning blocks forever.
#
# Every branch's copy is read in ONE subprocess. The naive `git show` per branch is
# O(branches) processes on a hook that fires on every write, and produces identical answers —
# which is why Group C asserts the process counts structurally rather than the answers.
#
# `git cat-file --batch` output is ASYMMETRIC: a blob emits `<sha> blob <size>` WITHOUT
# echoing its request, while a miss echoes the request verbatim plus ` missing`. Results are
# therefore matched to requests by INPUT ORDER — anything else mis-attributes every blob.
#
# Content is consumed by BYTE COUNT, not by line: cat-file emits exactly <size> bytes then an
# LF of its own. When the blob already ends in a newline that LF arrives as a separate empty
# line and must be skipped; when it does not, the LF merges into the last content line and
# there is nothing to skip. Reading line-wise instead drifts one line into the next entry.
#
# The phase line is only honoured between the fences. Feature files discuss `phase:` values in
# their own prose, so an unbounded match would let a spec paragraph supersede a real gate.
# shellcheck disable=SC2016  # $0/$NF are awk's own — they must not expand here.
BATCH_AWK='
BEGIN { split(ENVIRON["PHASE_GUARD_REQS"], R, "\n") }
state == 1 {
  consumed += length($0) + 1
  nline++
  if (nline == 1)                     infm = ($0 == "---")
  else if (infm && $0 == "---")       infm = 0
  else if (infm && $0 ~ /^phase:[[:space:]]*(implementation|review)[[:space:]]*$/) mark[path] = 1
  if (consumed >= size) { if (consumed == size) skipnext = 1; state = 0 }
  next
}
skipnext == 1 { skipnext = 0; next }
{
  i++
  path = R[i]; sub(/^[^:]*:/, "", path)
  if ($0 ~ / missing$/) next
  size = $NF; state = 1; consumed = 0; nline = 0
}
END { for (p in mark) print p }'

# An empty for-each-ref is NOT a failure — a repo with no local branches supersedes nothing,
# so every candidate survives to step 9. Only a nonzero exit is a failure.
# Past this point a planning card is active, so every remaining fail-open speaks (see THE RULE).
branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null) ||
  { warn_once nogit "${sid_payload:-$sid_env}" "$NOGIT_MSG"; exit 0; }

if [ -n "$branches" ]; then
  # Split on newlines only. A branch name cannot contain a space, but a feature-file path can,
  # and the default IFS would split one into two bogus requests.
  old_ifs=$IFS
  IFS='
'
  reqs=""
  for b in $branches; do
    for f in $planning_files; do
      reqs="$reqs$b:$f
"
    done
  done

  # pipefail is what makes "either git call failing → fail open" true: without it the
  # pipeline reports awk's status and a broken cat-file would read as an empty result set,
  # which is indistinguishable from "nothing is superseded" and would deny on a git error.
  set -o pipefail
  superseded=$(printf '%s' "$reqs" |
    git cat-file --batch 2>/dev/null |
    PHASE_GUARD_REQS="$reqs" awk "$BATCH_AWK") ||
    { IFS=$old_ifs; warn_once nogit "${sid_payload:-$sid_env}" "$NOGIT_MSG"; exit 0; }
  set +o pipefail

  remaining=""
  for f in $planning_files; do
    is_superseded=0
    for s in $superseded; do
      [ "$f" = "$s" ] && { is_superseded=1; break; }
    done
    [ "$is_superseded" -eq 0 ] && remaining="$remaining$f
"
  done
  IFS=$old_ifs
  planning_files=$remaining
  [ -n "$planning_files" ] || exit 0
fi

# --- Step 9: is the current branch claimed? ----------------------------------------------
# Both fail-opens are here rather than upstream: the only path onward from this step is deny,
# so a transient git failure would otherwise flip the hook from fail-open to fail-everything.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) ||
  { warn_once nogit "${sid_payload:-$sid_env}" "$NOGIT_MSG"; exit 0; }
[ -n "$branch" ] ||
  { warn_once nogit "${sid_payload:-$sid_env}" "$NOGIT_MSG"; exit 0; }
# Detached HEAD — reachable during any rebase or bisect. No branch means no claim can match,
# so without this the hook would deny every write for the length of a rebase.
[ "$branch" = "HEAD" ] && exit 0

# Membership test against the claims step 7 collected from the contract parser. Compared as
# strings, never as interpolated regexes: a branch name is user input, and one carrying a regex
# metacharacter would otherwise match wrongly. Split on newlines only — a branch name cannot
# contain whitespace, but the default IFS would still be the wrong tool here.
old_ifs=$IFS
IFS='
'
for claim in $claimed_branches; do
  [ "$claim" = "$branch" ] && { IFS=$old_ifs; exit 0; }
done
IFS=$old_ifs

# --- Step 10: deny -----------------------------------------------------------------------
# All four elements of the Deny message contract, because a block that says only "no" sends
# the session hunting for a bypass — which is the failure this message exists to prevent.
# The phase is printed as the constant `planning` rather than echoed back from the file:
# step 7's match IS the definition of offending here, and echoing the raw line would leak
# its whitespace variants into a message the contract wants uniform.
# Element 4 stays narrow — "no bypass environment variable", never "no way around this".
# The Bash-tool write surface is unguarded (Non-goals), so the wider claim would be false,
# and a safety message that overclaims teaches sessions to distrust its true parts too.
{
  printf 'phase-guard: write blocked — %s\n\n' "$rel"
  printf 'Implementation is not authorized on this branch: a feature file is still at\n'
  printf 'phase: planning, and no feature file records this branch as its own.\n\n'
  printf '  current branch: %s\n\n' "${branch:-<unresolved>}"
  printf 'Still at planning:\n'
  printf '%s' "$planning_files" | while IFS= read -r offending; do
    [ -n "$offending" ] || continue
    printf '  - %s — phase: planning\n' "$offending"
  done
  printf '\nTwo legitimate fixes (feature files live under docs/, which this guard never blocks):\n'
  printf '  1. Open the gate — on the literal user phrase "gate confirmed", advance the file\n'
  printf '     to phase: implementation and record its branch: %s\n' "${branch:-<this branch>}"
  printf '  2. If the file is stale or abandoned, advance or delete it.\n\n'
  printf 'There is no bypass environment variable; this guard ships without one by design.\n'
} 1>&2
exit 2
