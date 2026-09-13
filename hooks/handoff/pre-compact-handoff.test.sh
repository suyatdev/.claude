#!/usr/bin/env bash
# pre-compact-handoff.test.sh — behaviour tests for hooks/handoff/pre-compact-handoff.sh,
# covering task 8 of docs/features/handoff-trim-safety.md ("Rewrite the trim directive in
# both hooks: cutting means filing into the archive, and the protected headings are
# re-injected verbatim"). live-handoff.sh gets the same treatment in a sibling task/file;
# this suite is scoped to pre-compact-handoff.sh only.
#
# This hook had no test suite before this task, so this file also pins its PRE-EXISTING
# behaviour, not only the new part: the CLAUDE_PANE_AGENT short-circuit, the three
# MODE_DIRECTIVE branches (task+bug / bug / task) selected by .claude/current-task.md and
# .claude/current-bug.md, the no-task-no-bug branch, and the line-target string.
#
# What is new, in the card's terms:
#   * the directive names the archive path and the filing rule -- removing a line means
#     filing it first, not deleting it outright;
#   * when the notepad has [KEEP] headings, they are re-injected verbatim inside a
#     tamper-evident, tagged DATA envelope (open tag == close tag);
#   * when the reinject library cannot be loaded, the hook still emits a directive (the
#     OPPOSITE fail direction from live-handoff.sh, which suppresses instead) but orders
#     APPEND-ONLY instead of a rewrite, names the library path that failed, and carries no
#     filing rule or line-target text -- a target invites a cut it cannot back up;
#   * a missing notepad does not break the hook -- keep_trim_directive already handles
#     that by printing the filing rule alone.
#
# Run: bash hooks/handoff/pre-compact-handoff.test.sh
#
# The hook short-circuits on CLAUDE_PANE_AGENT, and this suite may itself run from a pane,
# so every invocation that expects real work goes through run_hook(), which clears that
# variable. The one test that WANTS the short-circuit sets it explicitly.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HOOK_DIR/pre-compact-handoff.sh"

# Physical path, not the one mktemp hands back -- on macOS mktemp -d returns the /var
# symlink form while other tools resolve it to /private/var, and a path-string comparison
# of the two forms reads as a mismatch that isn't one.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

pass=0; fail=0
ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

# mkrepo NAME — a throwaway git repo with no .claude directory yet (the hook creates one
# itself). Prints the repo path.
mkrepo() {
  local name="$1" repo
  repo="$TMP/$name"
  mkdir -p "$repo"
  ( cd "$repo" && git init -q )
  printf '%s' "$repo"
}

# run_hook REPO HOOKPATH — runs HOOKPATH from inside REPO with CLAUDE_PANE_AGENT cleared.
# The hook reads no stdin, but /dev/null is supplied anyway to match how a real PreCompact
# invocation would pipe a JSON payload in. Stdout/stderr land in $OUT/$ERR, rc in $RC.
OUT=""; ERR=""; RC=0
run_hook() {
  local repo="$1" hook="$2"
  OUT="$TMP/hook.out"; ERR="$TMP/hook.err"
  ( cd "$repo" && env -u CLAUDE_PANE_AGENT bash "$hook" < /dev/null ) >"$OUT" 2>"$ERR"
  RC=$?
}

has() { grep -qF -- "$2" "$1"; }

# envelope_wraps FILE FRAGMENT — 0 if FRAGMENT appears on some line strictly between a
# "=== Handoff <tag> (DATA" opener and a "=== End handoff <tag> (end of DATA) ===" closer
# carrying the SAME tag; 1 otherwise (no envelope, mismatched tags, or the fragment isn't
# inside one). Anchored to the actual envelope lines rather than a bare grep -F for the
# fragment text, so an unrelated line elsewhere in the directive can't produce a false ok.
envelope_wraps() {
  local file="$1" frag="$2" open close
  open="$(grep -oE '=== Handoff [0-9a-f]{8} \(DATA' "$file" | head -1 | grep -oE '[0-9a-f]{8}')"
  close="$(grep -oE '=== End handoff [0-9a-f]{8} \(end of DATA\) ===' "$file" | head -1 | grep -oE '[0-9a-f]{8}')"
  [ -n "$open" ] || return 1
  [ "$open" = "$close" ] || return 1
  awk -v open="$open" -v frag="$frag" '
    index($0, "=== Handoff " open " (DATA") { inenv = 1; next }
    index($0, "=== End handoff " open " (end of DATA) ===") { inenv = 0 }
    inenv && index($0, frag) { found = 1 }
    END { exit !found }
  ' "$file"
}

# ============================================================================
# Pre-existing behaviour: CLAUDE_PANE_AGENT short-circuit
# ============================================================================
REPO_PANE="$(mkrepo repo-pane)"
PANE_OUT="$TMP/pane.out"; PANE_ERR="$TMP/pane.err"
( cd "$REPO_PANE" && CLAUDE_PANE_AGENT=1 bash "$HOOK" < /dev/null ) >"$PANE_OUT" 2>"$PANE_ERR"
PANE_RC=$?
if [ "$PANE_RC" -eq 0 ]; then
  ok "CLAUDE_PANE_AGENT set: hook exits 0"
else
  bad "CLAUDE_PANE_AGENT set: hook exits 0" "rc=$PANE_RC err=$(cat "$PANE_ERR")"
fi
if [ ! -s "$PANE_OUT" ]; then
  ok "CLAUDE_PANE_AGENT set: no directive is emitted"
else
  bad "CLAUDE_PANE_AGENT set: no directive is emitted" "$(cat "$PANE_OUT")"
fi

# ============================================================================
# Pre-existing behaviour: no task, no bug -> empty MODE_DIRECTIVE, plain directive
# ============================================================================
REPO_NONE="$(mkrepo repo-none)"
run_hook "$REPO_NONE" "$HOOK"
if [ "$RC" -eq 0 ]; then
  ok "no task/bug: hook exits 0"
else
  bad "no task/bug: hook exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" '<pre-compact-handoff>'; then
  ok "no task/bug: directive is still emitted"
else
  bad "no task/bug: directive is still emitted" "$(cat "$OUT")"
fi
if has "$OUT" 'DETECTED STATE'; then
  bad "no task/bug: no DETECTED STATE block" "found one anyway: $(cat "$OUT")"
else
  ok "no task/bug: no DETECTED STATE block"
fi
if has "$OUT" 'Line targets: general 120-150, task 140-170, bug 160-190 (if needed).'; then
  ok "the line-target string is intact"
else
  bad "the line-target string is intact" "$(cat "$OUT")"
fi
if has "$OUT" '4. After compaction, you MUST read .claude/session-state.md before doing anything else.'; then
  ok "the post-compaction read-first instruction is intact"
else
  bad "the post-compaction read-first instruction is intact" "$(cat "$OUT")"
fi

# ============================================================================
# Pre-existing behaviour: the three MODE_DIRECTIVE branches
# ============================================================================
REPO_TASK="$(mkrepo repo-task)"
mkdir -p "$REPO_TASK/.claude"
: > "$REPO_TASK/.claude/current-task.md"
run_hook "$REPO_TASK" "$HOOK"
if has "$OUT" 'DETECTED STATE: Active multi-session task.'; then
  ok "task only: the task MODE_DIRECTIVE fires"
else
  bad "task only: the task MODE_DIRECTIVE fires" "$(cat "$OUT")"
fi

REPO_BUG="$(mkrepo repo-bug)"
mkdir -p "$REPO_BUG/.claude"
: > "$REPO_BUG/.claude/current-bug.md"
run_hook "$REPO_BUG" "$HOOK"
if has "$OUT" 'DETECTED STATE: Active bug investigation.'; then
  ok "bug only: the bug MODE_DIRECTIVE fires"
else
  bad "bug only: the bug MODE_DIRECTIVE fires" "$(cat "$OUT")"
fi

REPO_BOTH="$(mkrepo repo-taskbug)"
mkdir -p "$REPO_BOTH/.claude"
: > "$REPO_BOTH/.claude/current-task.md"
: > "$REPO_BOTH/.claude/current-bug.md"
run_hook "$REPO_BOTH" "$HOOK"
if has "$OUT" 'DETECTED STATE: Active task AND active bug (task.bug mode).'; then
  ok "task+bug: the combined MODE_DIRECTIVE fires"
else
  bad "task+bug: the combined MODE_DIRECTIVE fires" "$(cat "$OUT")"
fi

# ============================================================================
# New behaviour: a [KEEP] region present -- archive path, filing rule, tagged envelope
# ============================================================================
REPO_KEEP="$(mkrepo repo-keep)"
mkdir -p "$REPO_KEEP/.claude"
cat > "$REPO_KEEP/.claude/session-state.md" <<'EOF'
# Session State

## Critical Fact [KEEP]
Do not lose this line under any rewrite.

## Ordinary Section
Nothing protected here.
EOF
run_hook "$REPO_KEEP" "$HOOK"
ARCHIVE_PATH_KEEP="$REPO_KEEP/.claude/session-state.archive.md"
if has "$OUT" "$ARCHIVE_PATH_KEEP"; then
  ok "KEEP region present: the directive names the archive path"
else
  bad "KEEP region present: the directive names the archive path" "$(cat "$OUT")"
fi
if has "$OUT" 'Filing rule: when you remove any line from the notepad, first append those exact lines to'; then
  ok "KEEP region present: the filing rule is embedded"
else
  bad "KEEP region present: the filing rule is embedded" "$(cat "$OUT")"
fi
if envelope_wraps "$OUT" 'Critical Fact [KEEP]'; then
  ok "KEEP region present: the heading is re-injected inside a matching-tag envelope"
else
  bad "KEEP region present: the heading is re-injected inside a matching-tag envelope" "$(cat "$OUT")"
fi
# Save this output aside -- the falsifier section below re-uses it as the "good" side of
# the comparison.
cp "$OUT" "$TMP/good-keep.out"

# ============================================================================
# New behaviour: no [KEEP] region -- filing rule still present, no envelope at all
# ============================================================================
REPO_NOKEEP="$(mkrepo repo-nokeep)"
mkdir -p "$REPO_NOKEEP/.claude"
cat > "$REPO_NOKEEP/.claude/session-state.md" <<'EOF'
# Session State

## Ordinary Section
Nothing protected here.
EOF
run_hook "$REPO_NOKEEP" "$HOOK"
if has "$OUT" 'Filing rule:'; then
  ok "no KEEP region: the filing rule still appears"
else
  bad "no KEEP region: the filing rule still appears" "$(cat "$OUT")"
fi
if has "$OUT" '=== Handoff '; then
  bad "no KEEP region: no envelope marker appears" "found one anyway: $(cat "$OUT")"
else
  ok "no KEEP region: no envelope marker appears"
fi

# ============================================================================
# New behaviour: no session-state.md at all -- hook still exits 0, still emits a directive
# ============================================================================
REPO_NOSTATE="$(mkrepo repo-nostate)"
run_hook "$REPO_NOSTATE" "$HOOK"
if [ "$RC" -eq 0 ]; then
  ok "no session-state.md: hook still exits 0"
else
  bad "no session-state.md: hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" '<pre-compact-handoff>'; then
  ok "no session-state.md: a directive is still emitted"
else
  bad "no session-state.md: a directive is still emitted" "$(cat "$OUT")"
fi
if has "$OUT" 'Filing rule:'; then
  ok "no session-state.md: the filing rule still appears (keep_trim_directive handles an unreadable notepad)"
else
  bad "no session-state.md: the filing rule still appears (keep_trim_directive handles an unreadable notepad)" "$(cat "$OUT")"
fi

# ============================================================================
# New behaviour: the bare "REWRITE it completely" deletion framing no longer stands
# unqualified by the filing rule
# ============================================================================
if has "$OUT" 'REWRITE it completely'; then
  ok "the REWRITE step is still present"
else
  bad "the REWRITE step is still present" "$(cat "$OUT")"
fi
# Re-use the KEEP-region run: this is the one place the phrase's neighbourhood matters.
if has "$TMP/good-keep.out" 'means filing it first, not deleting it'; then
  ok "the REWRITE step is qualified by the filing rule, not left bare"
else
  bad "the REWRITE step is qualified by the filing rule, not left bare" "$(cat "$TMP/good-keep.out")"
fi

# ============================================================================
# New behaviour: libraries unloadable -- directive still emitted (fail OPEN, but ordering
# APPEND-ONLY instead of a rewrite -- the opposite direction from live-handoff.sh, which
# suppresses its directive entirely). Simulated with a SCRATCH COPY of the hook tree whose
# reinject library is corrupt or absent -- the real files under hooks/handoff/lib/ are
# never touched.
# ============================================================================

# make_scratch_hook LIBSTATE — copies pre-compact-handoff.sh and lib/handoff-archive.sh
# into a fresh scratch hook directory so BASH_SOURCE-based library resolution loads the
# COPY, never the real files under test. LIBSTATE "corrupt" writes a reinject library that
# fails to parse; "absent" omits the file entirely. Prints the scratch hook's path.
make_scratch_hook() {
  local libstate="$1" dir
  dir="$TMP/scratch-hook-$libstate"
  mkdir -p "$dir/lib"
  cp "$HOOK" "$dir/pre-compact-handoff.sh"
  cp "$HOOK_DIR/lib/handoff-archive.sh" "$dir/lib/handoff-archive.sh"
  if [ "$libstate" = "corrupt" ]; then
    printf 'this is not valid bash ((((\n' > "$dir/lib/handoff-keep-reinject.sh"
  fi
  # "absent": no lib/handoff-keep-reinject.sh at all.
  printf '%s' "$dir/pre-compact-handoff.sh"
}

# Fragments pinned against the hook's OWN wording, defined once so the corrupt and absent
# cases below compare against exactly the same strings.
APPEND_ONLY_STR='APPEND ONLY. Do not rewrite, shorten, reorder, or delete any existing part of .claude/session-state.md this run.'
LIB_WARN_STR='could not be loaded here, so the protected [KEEP] heading(s) in the notepad could not be listed'
LINE_TARGET_STR='Line targets: general 120-150, task 140-170, bug 160-190 (if needed).'

CORRUPT_HOOK="$(make_scratch_hook corrupt)"
CORRUPT_LIB="$(dirname "$CORRUPT_HOOK")/lib/handoff-keep-reinject.sh"
run_hook "$REPO_KEEP" "$CORRUPT_HOOK"
if [ "$RC" -eq 0 ]; then
  ok "reinject library corrupt: hook still exits 0"
else
  bad "reinject library corrupt: hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" '<pre-compact-handoff>'; then
  ok "reinject library corrupt: a directive is still emitted"
else
  bad "reinject library corrupt: a directive is still emitted" "$(cat "$OUT")"
fi
if has "$OUT" "$APPEND_ONLY_STR"; then
  ok "reinject library corrupt: the directive orders append-only"
else
  bad "reinject library corrupt: the directive orders append-only" "$(cat "$OUT")"
fi
if has "$OUT" "$LIB_WARN_STR"; then
  ok "reinject library corrupt: the warning names the un-listable [KEEP] headings"
else
  bad "reinject library corrupt: the warning names the un-listable [KEEP] headings" "$(cat "$OUT")"
fi
if has "$OUT" "$CORRUPT_LIB"; then
  ok "reinject library corrupt: the directive names the failed library's path"
else
  bad "reinject library corrupt: the directive names the failed library's path" "$(cat "$OUT")"
fi
if has "$OUT" 'Filing rule:'; then
  bad "reinject library corrupt: no filing-rule text is carried" "found one anyway: $(cat "$OUT")"
else
  ok "reinject library corrupt: no filing-rule text is carried"
fi
if has "$OUT" "$LINE_TARGET_STR"; then
  bad "reinject library corrupt: no line-target string is carried" "found one anyway: $(cat "$OUT")"
else
  ok "reinject library corrupt: no line-target string is carried"
fi
if has "$OUT" '=== Handoff '; then
  bad "reinject library corrupt: no envelope marker is fabricated" "found one anyway: $(cat "$OUT")"
else
  ok "reinject library corrupt: no envelope marker is fabricated"
fi
if grep -qF 'you MUST read .claude/session-state.md before doing anything else' "$OUT"; then
  ok "reinject library corrupt: the read-first-after-compaction instruction is kept"
else
  bad "reinject library corrupt: the read-first-after-compaction instruction is kept" "$(cat "$OUT")"
fi
cp "$OUT" "$TMP/broken-lib.out"

run_hook "$REPO_TASK" "$CORRUPT_HOOK"
if has "$OUT" 'DETECTED STATE: Active multi-session task.'; then
  ok "reinject library corrupt: MODE_DIRECTIVE still fires in the append-only branch"
else
  bad "reinject library corrupt: MODE_DIRECTIVE still fires in the append-only branch" "$(cat "$OUT")"
fi

ABSENT_HOOK="$(make_scratch_hook absent)"
ABSENT_LIB="$(dirname "$ABSENT_HOOK")/lib/handoff-keep-reinject.sh"
run_hook "$REPO_KEEP" "$ABSENT_HOOK"
if [ "$RC" -eq 0 ] && has "$OUT" '<pre-compact-handoff>' && has "$OUT" "$LIB_WARN_STR"; then
  ok "reinject library absent: hook still exits 0 and warns the same way"
else
  bad "reinject library absent: hook still exits 0 and warns the same way" "rc=$RC out=$(cat "$OUT")"
fi
if has "$OUT" "$APPEND_ONLY_STR"; then
  ok "reinject library absent: the directive orders append-only"
else
  bad "reinject library absent: the directive orders append-only" "$(cat "$OUT")"
fi
if has "$OUT" "$ABSENT_LIB"; then
  ok "reinject library absent: the directive names the missing library's path"
else
  bad "reinject library absent: the directive names the missing library's path" "$(cat "$OUT")"
fi
if has "$OUT" 'Filing rule:'; then
  bad "reinject library absent: no filing-rule text is carried" "found one anyway: $(cat "$OUT")"
else
  ok "reinject library absent: no filing-rule text is carried"
fi
if has "$OUT" "$LINE_TARGET_STR"; then
  bad "reinject library absent: no line-target string is carried" "found one anyway: $(cat "$OUT")"
else
  ok "reinject library absent: no line-target string is carried"
fi

# ============================================================================
# The filing rule must live in exactly one place: the shared library. Assert its absence
# from the HOOK SOURCE ITSELF, not just from one run's output -- the fallback branch used
# to hand-copy this wording (task 8's Finding B), and a source-level check catches a
# reintroduced copy that a differently-shaped fixture might not happen to exercise.
# ============================================================================
if grep -qF 'Filing rule:' "$HOOK"; then
  bad "the filing rule is not hand-copied anywhere in pre-compact-handoff.sh" "found a copy in the source file"
else
  ok "the filing rule is not hand-copied anywhere in pre-compact-handoff.sh"
fi

# ============================================================================
# Falsifier: prove the envelope/tag-match assertion (envelope_wraps, used above) actually
# discriminates a real bug rather than being satisfiable by any output that merely
# contains the words "Handoff" and "End handoff" somewhere. Break the ONE mechanism that
# assertion depends on -- the closing tag matching the opening tag -- in a scratch copy of
# the reinject library, run it, and confirm envelope_wraps correctly reports failure; then
# confirm the untouched library (the "good-keep.out" captured above) still passes.
# ============================================================================
TAGBUG_DIR="$TMP/scratch-hook-tagbug"
mkdir -p "$TAGBUG_DIR/lib"
cp "$HOOK" "$TAGBUG_DIR/pre-compact-handoff.sh"
cp "$HOOK_DIR/lib/handoff-archive.sh" "$TAGBUG_DIR/lib/handoff-archive.sh"
python3 - "$HOOK_DIR/lib/handoff-keep-reinject.sh" "$TAGBUG_DIR/lib/handoff-keep-reinject.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
old = "  printf '=== End handoff %s (end of DATA) ===\\n' \"$tag\"\n"
new = "  printf '=== End handoff 00000000 (end of DATA) ===\\n'\n"
if old not in text:
    sys.stderr.write("FALSIFIER SETUP FAILED: expected line not found in source library\n")
    sys.exit(1)
text = text.replace(old, new, 1)
open(dst, "w").write(text)
PY
TAGBUG_SETUP_RC=$?
if [ "$TAGBUG_SETUP_RC" -eq 0 ]; then
  ok "falsifier setup: the scratch copy's closing tag was successfully hardcoded to a mismatch"
else
  bad "falsifier setup: the scratch copy's closing tag was successfully hardcoded to a mismatch" \
    "python3 replace failed, rc=$TAGBUG_SETUP_RC"
fi

run_hook "$REPO_KEEP" "$TAGBUG_DIR/pre-compact-handoff.sh"
cp "$OUT" "$TMP/tagbug.out"

envelope_wraps "$TMP/tagbug.out" 'Critical Fact [KEEP]'
BROKEN_RC=$?
envelope_wraps "$TMP/good-keep.out" 'Critical Fact [KEEP]'
GOOD_RC=$?
if [ "$BROKEN_RC" -ne 0 ] && [ "$GOOD_RC" -eq 0 ]; then
  ok "falsifier: envelope_wraps fails on the mismatched-tag scratch output and passes on the real one"
else
  bad "falsifier: envelope_wraps fails on the mismatched-tag scratch output and passes on the real one" \
    "broken_rc=$BROKEN_RC (want nonzero) good_rc=$GOOD_RC (want 0) tagbug_out=$(cat "$TMP/tagbug.out")"
fi

# ============================================================================
# Falsifier: prove envelope_wraps requires CONTAINMENT, not just "the heading text and a
# same-tag envelope both appear somewhere in the file" -- the observability judge's
# reported gap. Build a scratch library whose envelope_keep_headings emits an EMPTY
# envelope (open immediately followed by close, same real tag, nothing between) and then
# dumps the raw, UNSANITIZED heading text after the close marker -- outside the envelope
# entirely. This defeats both the sanitizer (a plain `cat`, not sanitize_line) and any
# check that only looks for "does this text appear anywhere", and must still be rejected.
# ============================================================================
RAWOUT_DIR="$TMP/scratch-hook-rawout"
mkdir -p "$RAWOUT_DIR/lib"
cp "$HOOK" "$RAWOUT_DIR/pre-compact-handoff.sh"
cp "$HOOK_DIR/lib/handoff-archive.sh" "$RAWOUT_DIR/lib/handoff-archive.sh"
python3 - "$HOOK_DIR/lib/handoff-keep-reinject.sh" "$RAWOUT_DIR/lib/handoff-keep-reinject.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
# Two small, exact, single-occurrence anchors -- safer than reproducing the whole
# function body (which contains a literal em dash) as one giant match.
repls = [
    ('  while IFS= read -r line || [ -n "$line" ]; do\n',
     '  while false; do\n'),
    ('  printf \'=== End handoff %s (end of DATA) ===\\n\' "$tag"\n  return 0\n}\n',
     '  printf \'=== End handoff %s (end of DATA) ===\\n\' "$tag"\n'
     '  cat "$headings_file"\n  return 0\n}\n'),
]
for old, new in repls:
    if text.count(old) != 1:
        sys.stderr.write("FALSIFIER SETUP FAILED: expected exactly one match for %r, found %d\n" % (old, text.count(old)))
        sys.exit(1)
    text = text.replace(old, new, 1)
open(dst, "w").write(text)
PY
RAWOUT_SETUP_RC=$?
if [ "$RAWOUT_SETUP_RC" -eq 0 ]; then
  ok "containment falsifier setup: the scratch library was patched to emit an empty envelope plus a raw heading outside it"
else
  bad "containment falsifier setup: the scratch library was patched to emit an empty envelope plus a raw heading outside it" \
    "python3 replace failed, rc=$RAWOUT_SETUP_RC"
fi

run_hook "$REPO_KEEP" "$RAWOUT_DIR/pre-compact-handoff.sh"
cp "$OUT" "$TMP/rawout.out"

# Sanity check first: the mutant must actually produce BOTH a tagged envelope and the raw
# heading text, or a rejection below would be vacuous -- rejecting because the fixture is
# broken, not because envelope_wraps caught the defect it's meant to catch.
if grep -qF '=== Handoff ' "$TMP/rawout.out" && grep -qF 'Critical Fact [KEEP]' "$TMP/rawout.out"; then
  ok "containment falsifier: the mutant output actually contains a tagged envelope and the raw heading"
else
  bad "containment falsifier: the mutant output actually contains a tagged envelope and the raw heading" "$(cat "$TMP/rawout.out")"
fi

envelope_wraps "$TMP/rawout.out" 'Critical Fact [KEEP]'
RAWOUT_RC=$?
if [ "$RAWOUT_RC" -ne 0 ]; then
  ok "containment falsifier: envelope_wraps rejects a raw heading printed outside an empty envelope"
else
  bad "containment falsifier: envelope_wraps rejects a raw heading printed outside an empty envelope" \
    "rc=$RAWOUT_RC (want nonzero) rawout_out=$(cat "$TMP/rawout.out")"
fi

envelope_wraps "$TMP/good-keep.out" 'Critical Fact [KEEP]'
GOOD2_RC=$?
if [ "$GOOD2_RC" -eq 0 ]; then
  ok "containment falsifier: envelope_wraps still accepts the real hook's genuine output"
else
  bad "containment falsifier: envelope_wraps still accepts the real hook's genuine output" "$(cat "$TMP/good-keep.out")"
fi

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
