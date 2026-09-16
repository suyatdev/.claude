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
#   * when a library cannot be loaded, the hook still emits a directive -- it orders
#     APPEND-ONLY instead of a rewrite, names whichever library actually failed to load,
#     and carries no filing rule or line-target text -- a target invites a cut it cannot
#     back up. live-handoff.sh reaches the same append-only instruction by a different
#     route: it suppresses only its TRIM directive and falls back to the append-mode
#     directive it already emits under the cap (docs/decisions/0046);
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

# run_hook REPO HOOKPATH — runs HOOKPATH from inside REPO with CLAUDE_PANE_AGENT and
# CLAUDE_CODE_SESSION_ID cleared (task 9 added a session-identity fallback chain that
# would otherwise pick up whatever this test session itself exports, making the
# "nosession" default nondeterministic). /dev/null is supplied on stdin to match how a
# real PreCompact invocation would pipe a JSON payload in when the caller has none to
# send. Stdout/stderr land in $OUT/$ERR, rc in $RC.
OUT=""; ERR=""; RC=0
run_hook() {
  local repo="$1" hook="$2"
  OUT="$TMP/hook.out"; ERR="$TMP/hook.err"
  ( cd "$repo" && env -u CLAUDE_PANE_AGENT -u CLAUDE_CODE_SESSION_ID bash "$hook" < /dev/null ) \
    >"$OUT" 2>"$ERR"
  RC=$?
}

# run_hook_sid REPO HOOKPATH SESSION_ID [ENV_SESSION_ID] — like run_hook, but feeds a
# PreCompact-shaped JSON payload on stdin instead of /dev/null, so the session-identity
# tests below can control what the hook sees. SESSION_ID "" omits the field from the
# payload entirely (the payload-absent fallback path). ENV_SESSION_ID sets
# CLAUDE_CODE_SESSION_ID for the run (default: cleared), so the payload -> env var ->
# "nosession" fallback chain can be exercised one link at a time. Mirrors
# live-handoff.test.sh's run_hook, which does the same thing for the UserPromptSubmit
# hook; added as a separate function rather than changing run_hook's signature, so none
# of the pre-existing call sites above need to change.
run_hook_sid() {
  local repo="$1" hook="$2" sid="$3" envsid="${4:-}" payload
  if [ -n "$sid" ]; then
    payload="$(printf '{"hook_event_name":"PreCompact","session_id":"%s","cwd":"%s"}' "$sid" "$repo")"
  else
    payload="$(printf '{"hook_event_name":"PreCompact","cwd":"%s"}' "$repo")"
  fi
  OUT="$TMP/hook.out"; ERR="$TMP/hook.err"
  ( cd "$repo" && printf '%s' "$payload" \
      | env -u CLAUDE_PANE_AGENT CLAUDE_CODE_SESSION_ID="$envsid" bash "$hook" ) \
      >"$OUT" 2>"$ERR"
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
# New behaviour: libraries unloadable -- directive still emitted (fail OPEN), ordering
# APPEND-ONLY instead of a rewrite. live-handoff.sh reaches the same append-only
# instruction differently: it suppresses only its trim directive and still emits its own
# append-mode directive, rather than withholding output entirely (docs/decisions/0046).
# Simulated with a SCRATCH COPY of the hook tree whose reinject library is corrupt or
# absent -- the real files under hooks/handoff/lib/ are never touched.
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
# Finding B (judge round): the gate above loads TWO libraries (handoff-archive.sh, then
# handoff-keep-reinject.sh) but the degraded directive used to hardcode REINJECT_LIB as
# the thing that failed -- so a corrupt handoff-archive.sh got blamed on the intact
# handoff-keep-reinject.sh instead. Corrupt ONLY handoff-archive.sh in a fresh scratch
# hook tree (the reinject library is copied over intact and untouched) and confirm the
# directive names the library that actually failed, not the other one.
# ============================================================================
ARCHIVEBUG_DIR="$TMP/scratch-hook-archivebug"
mkdir -p "$ARCHIVEBUG_DIR/lib"
cp "$HOOK" "$ARCHIVEBUG_DIR/pre-compact-handoff.sh"
cp "$HOOK_DIR/lib/handoff-keep-reinject.sh" "$ARCHIVEBUG_DIR/lib/handoff-keep-reinject.sh"
printf 'this is not valid bash ((((\n' > "$ARCHIVEBUG_DIR/lib/handoff-archive.sh"
ARCHIVEBUG_HOOK="$ARCHIVEBUG_DIR/pre-compact-handoff.sh"
ARCHIVEBUG_ARCHIVE_LIB="$ARCHIVEBUG_DIR/lib/handoff-archive.sh"
ARCHIVEBUG_REINJECT_LIB="$ARCHIVEBUG_DIR/lib/handoff-keep-reinject.sh"
run_hook "$REPO_KEEP" "$ARCHIVEBUG_HOOK"
if [ "$RC" -eq 0 ]; then
  ok "corrupt archive library only: hook still exits 0"
else
  bad "corrupt archive library only: hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" '<pre-compact-handoff>'; then
  ok "corrupt archive library only: a directive is still emitted"
else
  bad "corrupt archive library only: a directive is still emitted" "$(cat "$OUT")"
fi
if has "$OUT" "$APPEND_ONLY_STR"; then
  ok "corrupt archive library only: the directive orders append-only"
else
  bad "corrupt archive library only: the directive orders append-only" "$(cat "$OUT")"
fi
if has "$OUT" "$ARCHIVEBUG_ARCHIVE_LIB"; then
  ok "corrupt archive library only: the directive names the archive library that actually failed"
else
  bad "corrupt archive library only: the directive names the archive library that actually failed" \
    "$(cat "$OUT")"
fi
if has "$OUT" "$ARCHIVEBUG_REINJECT_LIB"; then
  bad "corrupt archive library only: the directive does NOT blame the intact reinject library" \
    "$(cat "$OUT")"
else
  ok "corrupt archive library only: the directive does NOT blame the intact reinject library"
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

# ============================================================================
# Task 9 (docs/features/handoff-trim-safety.md): route this hook through the same
# pre-trim snapshot as live-handoff.sh. Before this task the hook had zero references to
# snapshot_notepad/PRETRIM_FILE -- the healthy REWRITE directive fired on the reinject
# library alone, with nothing backing up the notepad it was about to order a cut in.
#
# New behaviour, in the card's terms:
#   * session identity uses the same three-step fallback as live-handoff.sh (payload
#     session_id, then $CLAUDE_CODE_SESSION_ID, then the "nosession" literal), and the
#     same PRETRIM_FILE/STRIKE_FILE filename contract handoff-keep-guard.sh depends on;
#   * a byte-identical snapshot is taken BEFORE any directive is emitted;
#   * the REWRITE directive fires only when the snapshot succeeded AND the reinject
#     library loaded -- otherwise the existing append-only directive fires, with no line
#     target, and a reason distinguishing "the snapshot could not be written" from
#     "a library could not be loaded" (the FAILED_LIB mechanism already covers the
#     latter, and keeps a snapshot-library failure and a reinject-library failure
#     distinguishable from each other by which path FAILED_LIB names);
#   * a missing notepad is not a snapshot FAILURE -- there is nothing to back up, and
#     keep_trim_directive already handles a missing notepad on its own (pre-existing
#     "no session-state.md" test above), so this must not force append-only.
# ============================================================================

# ----------------------------------------------------------------------------
# Healthy run: a byte-identical snapshot exists alongside the ordinary rewrite
# directive, and the [KEEP] envelope and line-target text are unaffected.
# ----------------------------------------------------------------------------
REPO_SNAP="$(mkrepo repo-snapshot)"
mkdir -p "$REPO_SNAP/.claude"
{
  printf '# Session State\n\n## Critical Fact [KEEP]\nMust survive.\n\n'
  i=1
  while [ "$i" -le 160 ]; do
    printf 'notepad line %d\n' "$i"
    i=$((i+1))
  done
} > "$REPO_SNAP/.claude/session-state.md"
run_hook_sid "$REPO_SNAP" "$HOOK" "sess-snap"
PT_SNAP="$REPO_SNAP/.claude/session-state.pretrim.sess-snap.md"
if [ "$RC" -eq 0 ]; then
  ok "healthy run: hook exits 0"
else
  bad "healthy run: hook exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if [ -f "$PT_SNAP" ]; then
  ok "healthy run: a pre-trim snapshot file is written"
else
  bad "healthy run: a pre-trim snapshot file is written" ".claude holds: $(ls "$REPO_SNAP/.claude")"
fi
if cmp -s "$PT_SNAP" "$REPO_SNAP/.claude/session-state.md"; then
  ok "healthy run: the snapshot is byte-identical to the notepad"
else
  bad "healthy run: the snapshot is byte-identical to the notepad" "cmp differs"
fi
if has "$OUT" 'Line targets: general 120-150, task 140-170, bug 160-190 (if needed).'; then
  ok "healthy run: the rewrite directive still carries the line-target string"
else
  bad "healthy run: the rewrite directive still carries the line-target string" "$(cat "$OUT")"
fi
if envelope_wraps "$OUT" 'Critical Fact [KEEP]'; then
  ok "healthy run: the [KEEP] heading is still re-injected inside a matching-tag envelope"
else
  bad "healthy run: the [KEEP] heading is still re-injected inside a matching-tag envelope" "$(cat "$OUT")"
fi

# ----------------------------------------------------------------------------
# Session identity: payload session_id, two distinct snapshots, env-var fallback,
# nosession fallback, and a traversal-shaped id sanitized to stay inside .claude.
# ----------------------------------------------------------------------------
REPO_SID_A="$(mkrepo repo-sid-a)"
mkdir -p "$REPO_SID_A/.claude"
printf 'line one\n' > "$REPO_SID_A/.claude/session-state.md"
run_hook_sid "$REPO_SID_A" "$HOOK" "sess-payload-1"
if [ -f "$REPO_SID_A/.claude/session-state.pretrim.sess-payload-1.md" ]; then
  ok "a session_id on stdin lands in the snapshot filename"
else
  bad "a session_id on stdin lands in the snapshot filename" ".claude holds: $(ls "$REPO_SID_A/.claude")"
fi

REPO_SID_B="$(mkrepo repo-sid-b)"
mkdir -p "$REPO_SID_B/.claude"
printf 'line one\n' > "$REPO_SID_B/.claude/session-state.md"
run_hook_sid "$REPO_SID_B" "$HOOK" "sess-first"
run_hook_sid "$REPO_SID_B" "$HOOK" "sess-second"
if [ -f "$REPO_SID_B/.claude/session-state.pretrim.sess-first.md" ] \
   && [ -f "$REPO_SID_B/.claude/session-state.pretrim.sess-second.md" ]; then
  ok "two payloads in one repo produce two distinct snapshots"
else
  bad "two payloads in one repo produce two distinct snapshots" ".claude holds: $(ls "$REPO_SID_B/.claude")"
fi

REPO_SID_C="$(mkrepo repo-sid-c)"
mkdir -p "$REPO_SID_C/.claude"
printf 'line one\n' > "$REPO_SID_C/.claude/session-state.md"
run_hook_sid "$REPO_SID_C" "$HOOK" "" "env-sid-1"
if [ -f "$REPO_SID_C/.claude/session-state.pretrim.env-sid-1.md" ]; then
  ok "no session_id in the payload falls back to CLAUDE_CODE_SESSION_ID"
else
  bad "no session_id in the payload falls back to CLAUDE_CODE_SESSION_ID" ".claude holds: $(ls "$REPO_SID_C/.claude")"
fi

REPO_SID_D="$(mkrepo repo-sid-d)"
mkdir -p "$REPO_SID_D/.claude"
printf 'line one\n' > "$REPO_SID_D/.claude/session-state.md"
run_hook_sid "$REPO_SID_D" "$HOOK" "" ""
if [ -f "$REPO_SID_D/.claude/session-state.pretrim.nosession.md" ]; then
  ok "neither payload nor env var falls back to the nosession literal, and still snapshots"
else
  bad "neither payload nor env var falls back to the nosession literal, and still snapshots" \
    ".claude holds: $(ls "$REPO_SID_D/.claude")"
fi

REPO_SID_E="$(mkrepo repo-sid-evil)"
mkdir -p "$REPO_SID_E/.claude"
printf 'line one\n' > "$REPO_SID_E/.claude/session-state.md"
run_hook_sid "$REPO_SID_E" "$HOOK" "../../evil id/x"
# Every legitimate snapshot in this run lives inside some repo's .claude directory, so a
# stray is any pretrim file OUTSIDE one. Self-test first: a "found nothing" result is
# only worth reading if the search can find something.
printf 'decoy\n' > "$TMP/session-state.pretrim.decoy.md"
DECOY_SEEN="$(find "$TMP" -name 'session-state.pretrim.*' -not -path '*/.claude/*' 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$TMP/session-state.pretrim.decoy.md"
if [ "$DECOY_SEEN" = "1" ]; then
  ok "the stray-snapshot search finds a planted stray, so a zero below means something"
else
  bad "the stray-snapshot search finds a planted stray, so a zero below means something" \
    "the decoy was not counted (got $DECOY_SEEN)"
fi
ESCAPED="$(find "$TMP" -name 'session-state.pretrim.*' -not -path '*/.claude/*' 2>/dev/null | wc -l | tr -d ' ')"
INSIDE="$(find "$REPO_SID_E/.claude" -maxdepth 1 -name 'session-state.pretrim.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$ESCAPED" = "0" ]; then
  ok "a traversal-shaped session id writes nothing outside the repo .claude directory"
else
  bad "a traversal-shaped session id writes nothing outside the repo .claude directory" \
    "found $ESCAPED stray snapshot(s)"
fi
if [ "$INSIDE" = "1" ]; then
  ok "a traversal-shaped session id still produces exactly one snapshot inside .claude"
else
  bad "a traversal-shaped session id still produces exactly one snapshot inside .claude" "found $INSIDE"
fi

# ----------------------------------------------------------------------------
# Strike retention: a snapshot the keep-guard is holding across a strike must survive
# this hook's own run too -- same rule as live-handoff.sh, same reasoning (the guard's
# copy is the pre-damage one; overwriting it with the damaged notepad in front of us
# would destroy the only recovery source at exactly the moment it is needed).
# ----------------------------------------------------------------------------
REPO_STRIKE="$(mkrepo repo-strike)"
mkdir -p "$REPO_STRIKE/.claude"
printf 'current damaged notepad\n' > "$REPO_STRIKE/.claude/session-state.md"
PT_STRIKE="$REPO_STRIKE/.claude/session-state.pretrim.sess-strike.md"
printf 'ORIGINAL SNAPSHOT CONTENT\n' > "$PT_STRIKE"
: > "$REPO_STRIKE/.claude/session-state.keepguard-strikes.sess-strike"
run_hook_sid "$REPO_STRIKE" "$HOOK" "sess-strike"
if has "$PT_STRIKE" "ORIGINAL SNAPSHOT CONTENT"; then
  ok "a retained snapshot is not overwritten while a strike file exists"
else
  bad "a retained snapshot is not overwritten while a strike file exists" \
    "the recovery copy was replaced by the current notepad"
fi

# Discriminator: with no strike file the same starting state IS overwritten, so the test
# above is measuring the strike check and not some unrelated refusal to write.
REPO_NOSTRIKE="$(mkrepo repo-nostrike)"
mkdir -p "$REPO_NOSTRIKE/.claude"
printf 'current notepad\n' > "$REPO_NOSTRIKE/.claude/session-state.md"
PT_NOSTRIKE="$REPO_NOSTRIKE/.claude/session-state.pretrim.sess-nostrike.md"
printf 'ORIGINAL SNAPSHOT CONTENT\n' > "$PT_NOSTRIKE"
run_hook_sid "$REPO_NOSTRIKE" "$HOOK" "sess-nostrike"
if has "$PT_NOSTRIKE" "ORIGINAL SNAPSHOT CONTENT"; then
  bad "with no strike file the snapshot is refreshed" "stale content survived"
else
  ok "with no strike file the snapshot is refreshed"
fi

# And a strike file with no snapshot beside it must still snapshot -- otherwise a
# deleted PT plus a stale strike file leaves the turn unprotected forever.
REPO_STRIKE_NOPT="$(mkrepo repo-strike-nopt)"
mkdir -p "$REPO_STRIKE_NOPT/.claude"
printf 'current notepad\n' > "$REPO_STRIKE_NOPT/.claude/session-state.md"
: > "$REPO_STRIKE_NOPT/.claude/session-state.keepguard-strikes.sess-strikenopt"
run_hook_sid "$REPO_STRIKE_NOPT" "$HOOK" "sess-strikenopt"
if [ -f "$REPO_STRIKE_NOPT/.claude/session-state.pretrim.sess-strikenopt.md" ]; then
  ok "a strike file with no snapshot beside it still takes a fresh snapshot"
else
  bad "a strike file with no snapshot beside it still takes a fresh snapshot" \
    ".claude holds: $(ls "$REPO_STRIKE_NOPT/.claude")"
fi

# ----------------------------------------------------------------------------
# A missing notepad is not a snapshot failure: nothing to back up, so the healthy
# rewrite directive still fires (via keep_trim_directive's own missing-notepad
# handling), and no pretrim file is written since there was nothing to copy.
# ----------------------------------------------------------------------------
REPO_NONOTEPAD="$(mkrepo repo-nonotepad)"
run_hook_sid "$REPO_NONOTEPAD" "$HOOK" "sess-nonotepad"
if has "$OUT" 'Line targets: general 120-150, task 140-170, bug 160-190 (if needed).'; then
  ok "missing notepad: the healthy rewrite directive still fires, not append-only"
else
  bad "missing notepad: the healthy rewrite directive still fires, not append-only" "$(cat "$OUT")"
fi
if [ ! -e "$REPO_NONOTEPAD/.claude/session-state.pretrim.sess-nonotepad.md" ]; then
  ok "missing notepad: no snapshot file is written (nothing existed to copy)"
else
  bad "missing notepad: no snapshot file is written (nothing existed to copy)" \
    ".claude holds: $(ls "$REPO_NONOTEPAD/.claude")"
fi

# ----------------------------------------------------------------------------
# Snapshot failure: the notepad exists but .claude cannot be written to (mktemp beside
# the pretrim path fails). rc 0, a directive IS emitted, it orders append-only, carries
# no line-target text, names the pretrim path -- and its wording is distinct from the
# library-failure wording used for a corrupt/missing library.
# ----------------------------------------------------------------------------
SNAPSHOT_FAIL_STR='A pre-trim snapshot could not be taken this run:'
REPO_NOWRITE="$(mkrepo repo-nowrite)"
mkdir -p "$REPO_NOWRITE/.claude"
printf '# Session State\n\n## Critical Fact [KEEP]\nMust survive.\n' \
  > "$REPO_NOWRITE/.claude/session-state.md"
chmod 500 "$REPO_NOWRITE/.claude"
run_hook_sid "$REPO_NOWRITE" "$HOOK" "sess-nowrite"
chmod 700 "$REPO_NOWRITE/.claude"
if [ "$RC" -eq 0 ]; then
  ok "snapshot write failure: hook still exits 0"
else
  bad "snapshot write failure: hook still exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if has "$OUT" '<pre-compact-handoff>'; then
  ok "snapshot write failure: a directive is still emitted"
else
  bad "snapshot write failure: a directive is still emitted" "$(cat "$OUT")"
fi
if has "$OUT" "$APPEND_ONLY_STR"; then
  ok "snapshot write failure: the directive orders append-only"
else
  bad "snapshot write failure: the directive orders append-only" "$(cat "$OUT")"
fi
if has "$OUT" "$LINE_TARGET_STR"; then
  bad "snapshot write failure: no line-target string is carried" "found one anyway: $(cat "$OUT")"
else
  ok "snapshot write failure: no line-target string is carried"
fi
if has "$OUT" "$SNAPSHOT_FAIL_STR"; then
  ok "snapshot write failure: the reason names the pre-trim snapshot, not a library"
else
  bad "snapshot write failure: the reason names the pre-trim snapshot, not a library" "$(cat "$OUT")"
fi
if has "$OUT" "$REPO_NOWRITE/.claude/session-state.pretrim.sess-nowrite.md"; then
  ok "snapshot write failure: the reason names the pretrim path"
else
  bad "snapshot write failure: the reason names the pretrim path" "$(cat "$OUT")"
fi
if has "$OUT" "$LIB_WARN_STR"; then
  bad "snapshot write failure: the library-failure wording is NOT reused" "found it anyway: $(cat "$OUT")"
else
  ok "snapshot write failure: the library-failure wording is NOT reused"
fi
if [ ! -f "$REPO_NOWRITE/.claude/session-state.pretrim.sess-nowrite.md" ]; then
  ok "snapshot write failure: no partial snapshot is left behind"
else
  bad "snapshot write failure: no partial snapshot is left behind" "a file was left at the PT path"
fi
if has "$OUT" '=== Handoff '; then
  bad "snapshot write failure: the [KEEP] reinjection envelope is absent" "found one anyway: $(cat "$OUT")"
else
  ok "snapshot write failure: the [KEEP] reinjection envelope is absent"
fi
cp "$OUT" "$TMP/snapfail.out"

# ----------------------------------------------------------------------------
# Distinguishability: the snapshot-failure wording and the library-failure wording must
# never appear in each other's output. Re-run both existing library-failure scratch
# hooks (CORRUPT_HOOK, ABSENT_HOOK -- still in scope from the section above) fresh, so
# this doesn't depend on mutating earlier assertions.
# ----------------------------------------------------------------------------
run_hook "$REPO_KEEP" "$CORRUPT_HOOK"
cp "$OUT" "$TMP/corrupt-lib-recheck.out"
run_hook "$REPO_KEEP" "$ABSENT_HOOK"
cp "$OUT" "$TMP/absent-lib-recheck.out"
if has "$TMP/corrupt-lib-recheck.out" "$SNAPSHOT_FAIL_STR"; then
  bad "corrupt reinject library: the snapshot-failure wording does not leak in" \
    "found it anyway: $(cat "$TMP/corrupt-lib-recheck.out")"
else
  ok "corrupt reinject library: the snapshot-failure wording does not leak in"
fi
if has "$TMP/absent-lib-recheck.out" "$SNAPSHOT_FAIL_STR"; then
  bad "absent reinject library: the snapshot-failure wording does not leak in" \
    "found it anyway: $(cat "$TMP/absent-lib-recheck.out")"
else
  ok "absent reinject library: the snapshot-failure wording does not leak in"
fi

# ----------------------------------------------------------------------------
# Falsifier: prove the assertions above can actually fail. Strip the SNAPSHOT_OK
# conjunct from a scratch COPY of the hook's healthy-directive gate and confirm the
# rewrite directive (with the line-target string) fires against the same
# unwritable-.claude repo that the real hook correctly degraded above.
# ----------------------------------------------------------------------------
SNAP_MUT_DIR="$TMP/scratch-hook-snapmut"
mkdir -p "$SNAP_MUT_DIR/lib"
cp "$HOOK_DIR/lib/handoff-archive.sh" "$SNAP_MUT_DIR/lib/handoff-archive.sh"
cp "$HOOK_DIR/lib/handoff-keep-reinject.sh" "$SNAP_MUT_DIR/lib/handoff-keep-reinject.sh"
sed 's/\[ "\$SNAPSHOT_OK" = true \] \&\& //' "$HOOK" > "$SNAP_MUT_DIR/pre-compact-handoff.sh"
if cmp -s "$SNAP_MUT_DIR/pre-compact-handoff.sh" "$HOOK"; then
  bad "falsifier: the SNAPSHOT_OK guard was found and removed" \
    "sed changed nothing -- the guard text moved, so the falsifier below proves nothing"
else
  ok "falsifier: the SNAPSHOT_OK guard was found and removed"
fi

REPO_SNAPFALSE="$(mkrepo repo-snapfalsify)"
mkdir -p "$REPO_SNAPFALSE/.claude"
printf 'notepad content\n' > "$REPO_SNAPFALSE/.claude/session-state.md"
chmod 500 "$REPO_SNAPFALSE/.claude"
run_hook_sid "$REPO_SNAPFALSE" "$SNAP_MUT_DIR/pre-compact-handoff.sh" "sess-snapfalse"
chmod 700 "$REPO_SNAPFALSE/.claude"
if has "$OUT" "$LINE_TARGET_STR"; then
  ok "falsifier: without the guard the rewrite directive DOES fire with no snapshot behind it"
else
  bad "falsifier: without the guard the rewrite directive DOES fire with no snapshot behind it" \
    "the mutant stayed in append-only mode, so the suppression tests above discriminate nothing"
fi

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
