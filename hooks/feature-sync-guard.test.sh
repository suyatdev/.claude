#!/usr/bin/env bash
# feature-sync-guard.test.sh — drives the PreToolUse block-at-commit path with JSON
# on stdin (the production code path). Run: bash hooks/feature-sync-guard.test.sh
#
# Covers the Gherkin scenarios in docs/features/memory-system-split.md under
# "Feature: The feature-file pair cannot silently diverge".
#
# The two cases the feature file calls out as distinct, because they pull in
# opposite directions and a single "something is wrong" test would hide either:
#
#   * MISSING PARTNER -> ALLOW. Decision 7 makes single-file features permanent, so
#     "no <name>.spec.md" means this feature was never a pair, not that a migration
#     is unfinished. A guard that blocked here would block every commit touching the
#     eight unmigrated feature files -- including this spec before task 5 runs.
#   * BOTH EXIST, EITHER UNPARSEABLE -> BLOCK. A malformed checklist in a real pair
#     is a broken file, not a shape choice, and reading it as "no tasks" would let a
#     divergence through as an empty-set match.
#
# The commands below are DATA fed to the hook on stdin. Nothing here executes them.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK="$(cd "$(dirname "$0")" && pwd)/feature-sync-guard.sh"
# Physical path: on macOS mktemp -d hands back the /var symlink form while
# `git rev-parse --show-toplevel` resolves to /private/var, and the hook cd's to the
# root it computes. Same note as phase-guard.test.sh / slim-session-start.test.sh.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

REPO="$TMP/repo"
mkdir -p "$REPO/docs/features" "$REPO/src"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name  test

pass=0; fail=0

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }

# --- fixture writers ---------------------------------------------------------
# A checklist half: frontmatter + tasks. $1 = path, $2.. = task lines.
write_checklist() {
  local path="$1"; shift
  {
    printf -- '---\nphase: implementation\nmodel_tier: low\nbranch: feat/x\n---\n\n'
    printf -- '# Feature\n\n## Tasks\n\n'
    printf -- '%s\n' "$@"
  } > "$REPO/$path"
}

# A spec half: no frontmatter (it carries none, by contract). $1 = path, $2.. = tasks.
write_spec() {
  local path="$1"; shift
  {
    printf -- '# Feature — spec\n\nProse that adds no task.\n\n## Tasks\n\n'
    printf -- '%s\n' "$@"
  } > "$REPO/$path"
}

# Baseline: one in-sync pair (tasks 1 and 2) plus a single-file feature, committed.
write_checklist docs/features/paired.md \
  '- [ ] 1 — Do the first thing' \
  '- [ ] 2 — Do the second thing'
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length'
write_checklist docs/features/solo.md \
  '- [ ] 1 — Solo feature task one'
printf 'line\n' > "$REPO/src/app.sh"
git -C "$REPO" add -A
git -C "$REPO" commit -qm seed

reset_tree() {
  git -C "$REPO" reset -q --hard HEAD
  git -C "$REPO" clean -qfd
}

stage() { local f; for f in "$@"; do git -C "$REPO" add -A -- "$f"; done; }

run_case() { # $1 desc, $2 want-exit, $3 command string
  local desc="$1" want="$2" cmd="$3" got
  ( cd "$REPO" && payload "$cmd" | bash "$HOOK" >/dev/null 2>&1 )
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

run_case_msg() { # $1 desc, $2 want-exit, $3 stderr substring, $4 command string
  local desc="$1" want="$2" want_msg="$3" cmd="$4" got err
  err="$TMP/err.txt"
  ( cd "$REPO" && payload "$cmd" | bash "$HOOK" >/dev/null 2>"$err" )
  got=$?
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL — %s (want exit %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); return
  fi
  case "$(cat "$err")" in
    *"$want_msg"*) printf 'ok   — %s (exit %s, names "%s")\n' "$desc" "$got" "$want_msg"; pass=$((pass+1)) ;;
    *) printf 'FAIL — %s: stderr lacks "%s", got: %s\n' "$desc" "$want_msg" "$(cat "$err")"; fail=$((fail+1)) ;;
  esac
}

# =============================================================================
# In-sync pair — the allow list from the contract
# =============================================================================
reset_tree
write_checklist docs/features/paired.md \
  '- [x] 1 — Do the first thing' \
  '- [ ] 2 — Do the second thing'
stage docs/features/paired.md
run_case "tick a box, checklist half alone -> allow"          0 'git commit -m msg'

reset_tree
write_checklist docs/features/paired.md \
  '- [x] 1 — Do the first thing — done: landed in abc1234, 3 tests added' \
  '- [ ] 2 — Do the second thing'
stage docs/features/paired.md
run_case "append a completion note after the em dash -> allow" 0 'git commit -m msg'

reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at much greater length now' \
  '- [ ] 2 — Do the second thing, described at length'
stage docs/features/paired.spec.md
run_case "edit spec prose that adds no task -> allow"         0 'git commit -m msg'

reset_tree
write_checklist docs/features/paired.md \
  '- [x] 1 — Do the first thing' \
  '- [x] 2 — Do the second thing'
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length'
stage docs/features/paired.md docs/features/paired.spec.md
run_case "both halves edited, still in sync -> allow"         0 'git commit -m msg'

# Identity normalizes on whitespace and case, so these are the SAME two tasks. The
# variation MUST sit before the em dash: everything after it is outside the identity by
# construction, so a fixture that varies the tail proves nothing about normalization.
# The first version of this case did exactly that and survived a mutation that deleted
# .lower() outright -- a test that could not fail, pinning the fixture's premise rather
# than the behavior.
reset_tree
write_checklist docs/features/paired.md \
  '- [ ] Task  One — do the first thing' \
  '- [ ] 2 — Do the second thing'
write_spec docs/features/paired.spec.md \
  '- [ ] TASK ONE — do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length'
stage docs/features/paired.md docs/features/paired.spec.md
run_case "identity differs only by whitespace/case -> allow"  0 'git commit -m msg'

# =============================================================================
# Divergent pair — blocks
# =============================================================================
reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
stage docs/features/paired.spec.md
run_case_msg "task added to spec half only -> block, names it" 2 '3' 'git commit -m msg'

reset_tree
write_checklist docs/features/paired.md \
  '- [ ] 1 — Do the first thing' \
  '- [ ] 2 — Do the second thing' \
  '- [ ] 3 — A third thing that exists only in the checklist'
stage docs/features/paired.md
run_case_msg "task added to checklist half only -> block"     2 '3' 'git commit -m msg'

reset_tree
write_checklist docs/features/paired.md \
  '- [ ] 1 — Do the first thing'
stage docs/features/paired.md
run_case_msg "task removed from checklist half only -> block" 2 '2' 'git commit -m msg'

reset_tree
write_checklist docs/features/paired.md \
  '- [ ] 1a — Do the first thing' \
  '- [ ] 2 — Do the second thing'
stage docs/features/paired.md
run_case "task identity renamed in one half -> block"         2 'git commit -m msg'

# ADR 0015: the guard must lex segments, not match a start-anchored regex. The state
# is staged BEFORE the chained command is fed in, exactly as doc-guard.test.sh:83 does,
# because this is a PreToolUse hook -- the `git add` in the string has not run yet. What
# is under test here is that `git commit` is still FOUND when it is not at position 0.
reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
stage docs/features/paired.spec.md
run_case "CHAINED add && commit, divergent -> block"          2 'git add -- docs/features/paired.spec.md && git commit -m msg'

reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
stage docs/features/paired.spec.md
run_case "; separator, divergent -> block"                    2 'git add -- docs/features/paired.spec.md ; git commit -m msg'

# ACCEPTED LIMIT, pinned so it cannot widen silently. With the divergence written but
# NOT yet staged, a chained `git add && git commit` is allowed: the add has not run when
# this PreToolUse fires, and modelling what a sibling command will stage is the fail-open
# ADR 0014 removed (at least ten commands fill the index; every enumeration measured
# short). The guard trusts only what the commit itself can see. The `-am` case above is
# the shape that IS caught, because -a stages at commit time and the hook reads the
# worktree for it.
reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
run_case "unstaged divergence + chained add -> allow (limit)" 0 'git add -- docs/features/paired.spec.md && git commit -m msg'

# `-a` stages tracked edits AT COMMIT TIME, so the index is not yet the answer.
reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
run_case "commit -am with divergence unstaged -> block"       2 'git commit -am msg'

# =============================================================================
# Missing partner — the permanent single-file shape, always allowed
# =============================================================================
reset_tree
write_checklist docs/features/solo.md \
  '- [ ] 1 — Solo feature task one' \
  '- [ ] 2 — A task added with no spec half in sight'
stage docs/features/solo.md
run_case "single-file feature, task added -> allow"           0 'git commit -m msg'

reset_tree
write_checklist docs/features/brand-new.md \
  '- [ ] 1 — First task of a brand-new one-file feature'
stage docs/features/brand-new.md
run_case "brand-new feature created as one file -> allow"     0 'git commit -m msg'

reset_tree
git -C "$REPO" rm -q docs/features/paired.spec.md
run_case "spec half deleted outright -> allow (blind spot)"   0 'git commit -m msg'

# The spec that specifies the pair shape, committed before its own migration runs.
reset_tree
write_checklist docs/features/memory-system-split.md \
  '- [ ] 4 — Write the guard' \
  '- [ ] 5 — Split this file into the pair shape'
stage docs/features/memory-system-split.md
run_case "this spec before its own migration -> allow"        0 'git commit -m msg'

# =============================================================================
# Parse failures — fail CLOSED, but only when both halves exist
# =============================================================================
reset_tree
write_checklist docs/features/paired.md \
  '- [] 1 — Malformed: no space in the checkbox' \
  '- [ ] 2 — Do the second thing'
stage docs/features/paired.md
run_case_msg "malformed checkbox in checklist half -> block"  2 'parse' 'git commit -m msg'

reset_tree
write_spec docs/features/paired.spec.md \
  '- [y] 1 — Malformed: not a checkbox marker' \
  '- [ ] 2 — Do the second thing, described at length'
stage docs/features/paired.spec.md
run_case_msg "malformed checkbox in spec half -> block"       2 'parse' 'git commit -m msg'

reset_tree
write_checklist docs/features/paired.md \
  '- [ ] 1 — Do the first thing' \
  '- [ ] 1 — Duplicate identity, cannot key a set' \
  '- [ ] 2 — Do the second thing'
stage docs/features/paired.md
run_case_msg "duplicate task identity -> block"               2 'parse' 'git commit -m msg'

# A malformed line in a SINGLE-FILE feature is not this guard's business: with no
# partner there is nothing to compare, and blocking would break the missing-partner
# allow above for anyone whose prose happens to look like a broken checkbox.
reset_tree
write_checklist docs/features/solo.md \
  '- [] 1 — Malformed, but this feature has no spec half'
stage docs/features/solo.md
run_case "malformed checkbox, NO partner -> allow"            0 'git commit -m msg'

# CONTROL against the parse rule being too greedy: a markdown link in a bullet list
# starts with "- [" too. Reading it as a broken checkbox would block ordinary prose.
reset_tree
{
  printf -- '# Feature — spec\n\nSee also:\n\n'
  printf -- '- [the other doc](docs/other.md)\n'
  printf -- '- [ADR 0015](docs/decisions/0015.md) for the lexer\n\n'
  printf -- '## Tasks\n\n'
  printf -- '- [ ] 1 — Do the first thing, described at length\n'
  printf -- '- [ ] 2 — Do the second thing, described at length\n'
} > "$REPO/docs/features/paired.spec.md"
stage docs/features/paired.spec.md
run_case "markdown link bullets are not checkboxes -> allow"  0 'git commit -m msg'

# =============================================================================
# Trigger scoping — the guard must stay out of everything else
# =============================================================================
reset_tree
printf 'edited\n' > "$REPO/src/app.sh"
stage src/app.sh
run_case "commit touching no feature file -> allow"           0 'git commit -m msg'

reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
stage docs/features/paired.spec.md
run_case "divergent but not a commit at all -> allow"         0 'git add -- docs && git status'

reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
stage docs/features/paired.spec.md
run_case "commit named only in a quoted string -> allow"      0 'echo "then git commit it"'

# =============================================================================
# Bypass
# =============================================================================
reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
stage docs/features/paired.spec.md
run_case_msg "FEATURE_SYNC_EXEMPT -> allow, logged to stderr" 0 'FEATURE_SYNC_EXEMPT' \
  'FEATURE_SYNC_EXEMPT="spec half lands next commit" git commit -m msg'

# =============================================================================
# Fail direction. Infrastructure absence fails OPEN (as doc-guard does on the same
# condition); a PARSE failure inside a real pair fails CLOSED. The two directions
# live in one hook, so pin both or a refactor can quietly align them.
#
# The hook resolves its helpers relative to its own location, so copying it
# somewhere with no lib/ beside it is exactly the "helpers missing" condition.
# =============================================================================
ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN"
cp "$HOOK" "$ORPHAN/feature-sync-guard.sh"

reset_tree
write_spec docs/features/paired.spec.md \
  '- [ ] 1 — Do the first thing, described at length' \
  '- [ ] 2 — Do the second thing, described at length' \
  '- [ ] 3 — A third thing that exists only in the spec'
stage docs/features/paired.spec.md
( cd "$REPO" && payload 'git commit -m msg' | bash "$ORPHAN/feature-sync-guard.sh" >/dev/null 2>&1 )
got=$?
if [ "$got" -eq 0 ]; then
  printf 'ok   — no helpers, divergent pair -> FAIL OPEN (exit %s)\n' "$got"; pass=$((pass+1))
else
  printf 'FAIL — no helpers, divergent pair -> FAIL OPEN (want 0, got %s)\n' "$got"; fail=$((fail+1))
fi

# Control: the same staged state through the real hook still blocks, so the case
# above is proving the fail-open path and not a broken fixture.
run_case "control: same divergent state, real hook -> block"  2 'git commit -m msg'

# =============================================================================
# Registration assertion: this hook must actually be wired into settings.json. A hook
# can pass every case above while sitting unregistered, in which case it never runs in
# production (judge-guard.test.sh:344 names the hazard). Checked against the REAL repo
# settings.json, not the throwaway $REPO fixture used above — that file is what Claude
# Code actually loads.
# =============================================================================
SETTINGS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)/settings.json"
if [ -f "$SETTINGS" ] && /usr/bin/jq -e \
     '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("hooks/feature-sync-guard\\.sh"))' \
     "$SETTINGS" >/dev/null 2>&1; then
  printf 'ok   — feature-sync-guard.sh is registered under PreToolUse in settings.json\n'
  pass=$((pass+1))
else
  printf 'FAIL — feature-sync-guard.sh is registered under PreToolUse in settings.json (not found in %s)\n' "$SETTINGS"
  fail=$((fail+1))
fi

# Self-check: the assertion above must be able to fail, not just always pass — the exact
# vacuous-test trap task 4 hit. Strip the hook from a copy of the real file and confirm
# the same query reports it missing.
MUTANT="$TMP/settings-mutant.json"
/usr/bin/jq 'del(.hooks.PreToolUse[]?.hooks[]? | select(.command | test("feature-sync-guard")))' \
  "$SETTINGS" > "$MUTANT" 2>/dev/null
if /usr/bin/jq -e \
     '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("hooks/feature-sync-guard\\.sh"))' \
     "$MUTANT" >/dev/null 2>&1; then
  printf 'FAIL — registration check can fail (hook removed from a copy): mutant still reported present\n'
  fail=$((fail+1))
else
  printf 'ok   — registration check can fail (hook removed from a copy)\n'
  pass=$((pass+1))
fi

# =============================================================================
# argv0-spelling-blindness (docs/features/argv0-spelling-blindness.md, task 2
# completion pass, RED). feature-sync-guard.sh:130's OWN
# `argv[0] == "git" and argv[1] == "commit"` check reads FEATURE_SYNC_EXEMPT
# from the assignments of the segment that runs the commit -- for a capitalized
# or path-qualified spelling, this check never matches, so the exemption is
# silently ignored even though the same commit really runs.
#
# It cannot be exercised end to end through run_case: `has_fact COMMIT` (line
# 111, from classify-git-command.py's own :520 site, a separate call site
# already covered by task 2's ARGV0_SPELLING_CASES rows) fails to fire for a
# capitalized/path invocation pre-fix, so the hook exits at line 111 before
# this exempt-reading code ever runs, regardless of :130's own bug -- fixing
# :520 alone would not fix :130, and a fixture routed past line 111 would leave
# :130 untested by construction. Isolated instead, the same way
# test-marker-guard.test.sh isolates decide-commit-gate.py's own git check: the
# exempt_reason assignment is extracted from the REAL script text with awk
# (start/end markers, not a hardcoded line range, so extraction survives
# drift) and sourced, so the assertions run the actual bytes of
# feature-sync-guard.sh, never a copy.
#
# Measured directly against this checkout, pre-fix, 2026-09-01: the lowercase
# control reports "reason"; all three capitalized/path spellings report empty
# (verbatim, quoted in the FAIL lines below).
# =============================================================================
FSG_EXTRACT="$TMP/exempt_reason.sh"
awk '/^export FSG_HOOK_DIR=/{p=1} p{print} p && /^'"'"' 2>\/dev\/null\)$/{exit}' \
  "$HOOK" > "$FSG_EXTRACT"
if [ -s "$FSG_EXTRACT" ]; then
  py="$(command -v python3 || command -v python)"

  check_exempt_reason() { # $1 desc, $2 command_line, $3 expected result
    local desc="$1" want="$3" got
    HOOK_DIR="$(cd "$(dirname "$HOOK")" && pwd)"
    command_line="$2"
    # shellcheck disable=SC1090  # extracted at run time from the real hook, see above
    source "$FSG_EXTRACT"
    got="$exempt_reason"
    if [ "$got" = "$want" ]; then
      printf 'ok   — %s (got %s)\n' "$desc" "${got:-<empty>}"; pass=$((pass+1))
    else
      printf 'FAIL — %s (want %s, got %s)\n' "$desc" "${want:-<empty>}" "${got:-<empty>}"; fail=$((fail+1))
    fi
  }

  check_exempt_reason \
    "argv0-spelling RED: control -- lowercase 'FEATURE_SYNC_EXEMPT=reason git commit' -> reports reason" \
    'FEATURE_SYNC_EXEMPT=reason git commit -m x' 'reason'
  check_exempt_reason \
    "argv0-spelling RED: capitalized 'FEATURE_SYNC_EXEMPT=reason Git commit' must report reason like lowercase (measured pre-fix: empty)" \
    'FEATURE_SYNC_EXEMPT=reason Git commit -m x' 'reason'
  check_exempt_reason \
    "argv0-spelling RED: 'FEATURE_SYNC_EXEMPT=reason GIT commit' must report reason like lowercase (measured pre-fix: empty)" \
    'FEATURE_SYNC_EXEMPT=reason GIT commit -m x' 'reason'
  check_exempt_reason \
    "argv0-spelling RED: 'FEATURE_SYNC_EXEMPT=reason /usr/bin/git commit' must report reason like lowercase (measured pre-fix: empty)" \
    'FEATURE_SYNC_EXEMPT=reason /usr/bin/git commit -m x' 'reason'
else
  printf 'FAIL — argv0-spelling RED: could not extract the exempt_reason assignment from feature-sync-guard.sh (extraction markers drifted) -- unmeasured\n'
  fail=$((fail+1))
fi

printf '\nfeature-sync-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
