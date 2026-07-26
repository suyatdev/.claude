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
# Minimal for now: a line-level match. The full frontmatter contract — fenced, at most one
# phase: line, a value from the legal three — is a later task, and until it lands a
# malformed file is read more permissively than the contract allows.
PLANNING_RE='^phase:[[:space:]]*planning[[:space:]]*$'
IMPL_RE='^phase:[[:space:]]*implementation[[:space:]]*$'
BRANCH_SED='s/^branch:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p'

planning_files=""
for f in "$root"/docs/features/*.md; do
  [ -f "$f" ] || continue          # no match: the glob stayed literal, so the dir is empty
  grep -Eq "$PLANNING_RE" "$f" || continue
  planning_files="$planning_files${f#"$root"/}
"
done
[ -n "$planning_files" ] || exit 0

# --- Step 8: drop the superseded ---------------------------------------------------------
# Not yet implemented. Until it is, a planning file whose gate has already opened on some
# other branch still denies here.

# --- Step 9: is the current branch claimed? ----------------------------------------------
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
if [ -n "$branch" ]; then
  for f in "$root"/docs/features/*.md; do
    [ -f "$f" ] || continue
    grep -Eq "$IMPL_RE" "$f" || continue
    # Compare the branch as a string, never as an interpolated regex: a branch name is
    # user input, and one carrying a regex metacharacter would otherwise match wrongly.
    claim=$(sed -n -E "$BRANCH_SED" "$f" | head -1)
    [ "$claim" = "$branch" ] && exit 0
  done
fi

# --- Step 10: deny -----------------------------------------------------------------------
# Bare for now; the message contract is the next task.
exit 2
