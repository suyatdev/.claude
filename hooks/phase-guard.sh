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
# One of the two exits that must not stay silent: with no interpreter the guard is off
# in every repo, permanently, until PATH is fixed. The once-per-session line this exit
# owes arrives with the flag contract (task 12); it is silent until then.
[ -n "$py" ] || exit 0

# Step 1 catches only *empty* stdin, so a truncated or non-JSON payload reaches this
# parser. Every failure to produce a usable path takes the same silent fail-open: an
# unhandled traceback exits nonzero, which a PreToolUse harness may read as deny.
# NotebookEdit carries no file_path — notebook_path is its only path key, so reading
# file_path alone would fail open on every notebook write.
file_path=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
    ti = p.get("tool_input") or {}
    sys.stdout.write(ti.get("file_path") or ti.get("notebook_path") or "")
except Exception:
    sys.exit(0)
') || file_path=""
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
# read as "not planning, therefore allow" and silently switch a CRITICAL gate off.
#
# Prints the phase value for a well-formed file, nothing for a malformed one. Awk missing or
# failing therefore reads as malformed, which fails open — consistent with every other ⊘.
#
# A skipped file in an opted-in repo is the "cannot evaluate" case, and the second of the two
# exits that must not be silent. Like the no-interpreter exit at step 4 it stays silent here:
# its once-per-session line is inseparable from the flag contract, and both land at task 12.
IMPL_RE='^phase:[[:space:]]*implementation[[:space:]]*$'
BRANCH_SED='s/^branch:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p'
# shellcheck disable=SC2016  # $0 is awk's own, not a shell expansion — it must not expand.
FRONTMATTER_AWK='
NR == 1     { if ($0 != "---") exit; next }
$0 == "---" { closed = 1; exit }
/^phase:/   { nphase++; phase = $0 }
/^branch:/  { nbranch++ }
END {
  if (!closed || nphase != 1 || nbranch > 1) exit
  if (phase !~ /^phase:[[:space:]]*(planning|implementation|review)[[:space:]]*$/) exit
  sub(/^phase:[[:space:]]*/, "", phase)
  sub(/[[:space:]]*$/, "", phase)
  print phase
}'

planning_files=""
for f in "$root"/docs/features/*.md; do
  [ -f "$f" ] || continue          # no match: the glob stayed literal, so the dir is empty
  [ "$(awk "$FRONTMATTER_AWK" "$f")" = "planning" ] || continue
  planning_files="$planning_files${f#"$root"/}
"
done
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
branches=$(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null) || exit 0

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
    PHASE_GUARD_REQS="$reqs" awk "$BATCH_AWK") || { IFS=$old_ifs; exit 0; }
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
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ -n "$branch" ] || exit 0
# Detached HEAD — reachable during any rebase or bisect. No branch means no claim can match,
# so without this the hook would deny every write for the length of a rebase.
[ "$branch" = "HEAD" ] && exit 0

for f in "$root"/docs/features/*.md; do
  [ -f "$f" ] || continue
  grep -Eq "$IMPL_RE" "$f" || continue
  # Compare the branch as a string, never as an interpolated regex: a branch name is
  # user input, and one carrying a regex metacharacter would otherwise match wrongly.
  claim=$(sed -n -E "$BRANCH_SED" "$f" | head -1)
  [ "$claim" = "$branch" ] && exit 0
done

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
