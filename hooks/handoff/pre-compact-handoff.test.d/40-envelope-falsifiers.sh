# shellcheck shell=bash
# 40-envelope-falsifiers.sh — sourced by ../pre-compact-handoff.test.sh — not runnable on its own.
# Falsifiers proving envelope_wraps (tag-match and containment) can actually fail. Reads $REPO_KEEP and $TMP/good-keep.out from 20-keep-region-and-framing.sh.

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

