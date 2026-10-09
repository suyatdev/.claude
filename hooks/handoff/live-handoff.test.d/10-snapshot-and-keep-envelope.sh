# shellcheck shell=bash
# 10-snapshot-and-keep-envelope.sh — sourced by ../live-handoff.test.sh — not runnable on its own.
# Covers the every-turn snapshot (under and over the write cap), the Task 8 filing rule, the [KEEP] envelope with matching-tag falsifier, and the CONTAINMENT falsifier.

# ============================================================================
# Normal path, under the write cap: snapshot taken anyway, append directive out
# ============================================================================
REPO_A="$(mkrepo repo-under 10)"
run_hook "$REPO_A" "$HOOK" "sess-aaa"
PT_A="$REPO_A/.claude/session-state.pretrim.sess-aaa.md"
if [ "$RC" -eq 0 ]; then
  ok "under the cap: hook exits 0"
else
  bad "under the cap: hook exits 0" "rc=$RC err=$(cat "$ERR")"
fi
if [ -f "$PT_A" ]; then
  ok "under the cap: a snapshot is still written (C3 — every turn, not only over the cap)"
else
  bad "under the cap: a snapshot is still written (C3 — every turn, not only over the cap)" \
    "no file at $PT_A; .claude holds: $(ls "$REPO_A/.claude")"
fi
if cmp -s "$PT_A" "$REPO_A/.claude/session-state.md"; then
  ok "the snapshot is byte-identical to the notepad"
else
  bad "the snapshot is byte-identical to the notepad" "cmp differs"
fi
if has "$OUT" "Do NOT rewrite the whole file"; then
  ok "under the cap: the append-mode directive is emitted"
else
  bad "under the cap: the append-mode directive is emitted" "$(cat "$OUT")"
fi
if has "$OUT" "It has grown too large"; then
  bad "under the cap: no trim directive" "trim text present"
else
  ok "under the cap: no trim directive"
fi
if grep -qE '=== (End )?[Hh]andoff [0-9a-f]+ ' "$OUT"; then
  bad "under the cap: no envelope markers leak into the append-mode directive" \
    "envelope found: $(cat "$OUT")"
else
  ok "under the cap: no envelope markers leak into the append-mode directive"
fi

# ============================================================================
# Over the write cap: snapshot taken, trim directive out
# ============================================================================
REPO_B="$(mkrepo repo-over 160)"
run_hook "$REPO_B" "$HOOK" "sess-bbb"
PT_B="$REPO_B/.claude/session-state.pretrim.sess-bbb.md"
if [ -f "$PT_B" ] && cmp -s "$PT_B" "$REPO_B/.claude/session-state.md"; then
  ok "over the cap: a byte-identical snapshot is written before the directive"
else
  bad "over the cap: a byte-identical snapshot is written before the directive" \
    "exists=$([ -f "$PT_B" ] && echo yes || echo no)"
fi
if has "$OUT" "It has grown too large"; then
  ok "over the cap: the trim directive is emitted when the snapshot succeeded"
else
  bad "over the cap: the trim directive is emitted when the snapshot succeeded" "$(cat "$OUT")"
fi

# --- Task 8: the trim directive files instead of deletes, and names the archive -------
# REPO_B has no [KEEP] region (mkrepo's lines are plain), so this also covers "over the
# cap with no KEEP region": the filing rule still fires and no envelope markers appear.
if has "$OUT" "$REPO_B/.claude/session-state.archive.md"; then
  ok "over the cap, no KEEP region: the trim directive names the archive path"
else
  bad "over the cap, no KEEP region: the trim directive names the archive path" "$(cat "$OUT")"
fi
if has "$OUT" "Filing rule:"; then
  ok "over the cap, no KEEP region: the trim directive carries the filing rule"
else
  bad "over the cap, no KEEP region: the trim directive carries the filing rule" "$(cat "$OUT")"
fi
if grep -qE '=== (End )?[Hh]andoff [0-9a-f]+ ' "$OUT"; then
  bad "over the cap, no KEEP region: no envelope markers leak in" "envelope found: $(cat "$OUT")"
else
  ok "over the cap, no KEEP region: no envelope markers leak in"
fi
if has "$OUT" "Be ruthless"; then
  bad "the old deletion-only phrasing is gone from the trim directive" "'Be ruthless' still present"
else
  ok "the old deletion-only phrasing is gone from the trim directive"
fi

# ============================================================================
# Task 8: over the cap WITH a [KEEP] region — the protected heading must reach the model
# verbatim inside a tamper-evident envelope, open and close tags matching.
# ============================================================================
REPO_P="$TMP/repo-keep"
mkdir -p "$REPO_P/.claude"
( cd "$REPO_P" && git init -q )
{
  printf '# Session State\n\n## Decisions [KEEP]\nRationale line, must survive.\n\n'
  i=1
  while [ "$i" -le 150 ]; do
    printf 'notepad line %d\n' "$i"
    i=$((i+1))
  done
} > "$REPO_P/.claude/session-state.md"
run_hook "$REPO_P" "$HOOK" "sess-ppp"
if has "$OUT" "It has grown too large"; then
  ok "over the cap with a KEEP region: the trim directive still fires"
else
  bad "over the cap with a KEEP region: the trim directive still fires" "$(cat "$OUT")"
fi
if has "$OUT" "$REPO_P/.claude/session-state.archive.md"; then
  ok "over the cap with a KEEP region: the trim directive still names the archive path"
else
  bad "over the cap with a KEEP region: the trim directive still names the archive path" "$(cat "$OUT")"
fi
if has "$OUT" "Decisions [KEEP]"; then
  ok "over the cap with a KEEP region: the protected heading text appears in the directive"
else
  bad "over the cap with a KEEP region: the protected heading text appears in the directive" "$(cat "$OUT")"
fi
# Capture the tag with an anchored group, not a bare [0-9a-f]+ scan — the surrounding
# words ("Handoff", "DATA") themselves contain hex-alphabet letters, so an unanchored
# grep -oE would pick up spurious single-letter "matches" from the prose around the tag.
KEEP_OPEN_TAG="$(sed -nE 's/.*=== Handoff ([0-9a-f]+) \(DATA.*/\1/p' "$OUT")"
KEEP_CLOSE_TAG="$(sed -nE 's/.*=== End handoff ([0-9a-f]+) \(end of DATA\) ===.*/\1/p' "$OUT")"
if [ -n "$KEEP_OPEN_TAG" ] && [ "$KEEP_OPEN_TAG" = "$KEEP_CLOSE_TAG" ]; then
  ok "over the cap with a KEEP region: the heading sits inside a matching-tag envelope"
else
  bad "over the cap with a KEEP region: the heading sits inside a matching-tag envelope" \
    "open=[$KEEP_OPEN_TAG] close=[$KEEP_CLOSE_TAG] out=$(cat "$OUT")"
fi
# The two checks above only prove the heading text and matching tags each appear somewhere
# in the output -- not that the heading is actually BETWEEN the tags. A mutant that prints
# an empty-but-correctly-tagged envelope and then the raw heading afterward would still
# satisfy both. envelope_wraps checks real containment; see the falsifier further below
# that proves it actually discriminates that exact mutant. Saved aside now, before the
# mismatched-tag mutant below overwrites $OUT, so the falsifier's "restore" step and the
# containment falsifier can both compare against this exact genuine output.
cp "$OUT" "$TMP/good-keep.out"
if envelope_wraps "$TMP/good-keep.out" 'Decisions [KEEP]'; then
  ok "over the cap with a KEEP region: the heading sits INSIDE the matching-tag envelope, not merely somewhere in the output"
else
  bad "over the cap with a KEEP region: the heading sits INSIDE the matching-tag envelope, not merely somewhere in the output" \
    "$(cat "$TMP/good-keep.out")"
fi

# --- Falsifier for the matching-tag assertion above: a mutant reinject library whose ----
# close tag is hardcoded instead of reusing $tag. Proves the assertion actually compares
# VALUES (not just "an envelope exists") — without this, a broken tag pairing could slip
# through unnoticed. Never touches the real library; only a scratch copy.
MUT_KEEP_DIR="$TMP/mutant-keep-tag"
mkdir -p "$MUT_KEEP_DIR/lib"
cp "$HOOK" "$MUT_KEEP_DIR/live-handoff.sh"
cp "$LIB" "$MUT_KEEP_DIR/lib/handoff-archive.sh"
sed 's/=== End handoff %s (end of DATA) ===/=== End handoff deadbeef (end of DATA) ===/' \
  "$HOOK_DIR/lib/handoff-keep-reinject.sh" > "$MUT_KEEP_DIR/lib/handoff-keep-reinject.sh"
chmod +x "$MUT_KEEP_DIR/live-handoff.sh"
if cmp -s "$MUT_KEEP_DIR/lib/handoff-keep-reinject.sh" "$HOOK_DIR/lib/handoff-keep-reinject.sh"; then
  bad "falsifier: the close-tag line was found and replaced" \
    "sed changed nothing — the falsifier below proves nothing"
else
  ok "falsifier: the close-tag line was found and replaced"
fi
REPO_Q="$TMP/repo-keep-mut"
mkdir -p "$REPO_Q/.claude"
( cd "$REPO_Q" && git init -q )
cp "$REPO_P/.claude/session-state.md" "$REPO_Q/.claude/session-state.md"
run_hook "$REPO_Q" "$MUT_KEEP_DIR/live-handoff.sh" "sess-qqq"
MUT_OPEN_TAG="$(sed -nE 's/.*=== Handoff ([0-9a-f]+) \(DATA.*/\1/p' "$OUT")"
MUT_CLOSE_TAG="$(sed -nE 's/.*=== End handoff ([0-9a-f]+) \(end of DATA\) ===.*/\1/p' "$OUT")"
# Both tags must be PRESENT and DIFFER. Testing only "not equal" would also be satisfied
# by an empty pair, i.e. by the mutant emitting no envelope at all — which is what happens
# if the sed leaves an unparseable library and REINJECT_LIB_OK suppresses the trim. That
# outcome proves nothing about tag comparison, so it must read as a failure, not a pass.
if [ -z "$MUT_OPEN_TAG" ] || [ -z "$MUT_CLOSE_TAG" ]; then
  bad "falsifier: the matching-tag assertion fails against a mismatched envelope" \
    "the mutant emitted no envelope at all (open=[$MUT_OPEN_TAG] close=[$MUT_CLOSE_TAG]); the tag comparison was never exercised"
elif [ "$MUT_OPEN_TAG" = "$MUT_CLOSE_TAG" ]; then
  bad "falsifier: the matching-tag assertion fails against a mismatched envelope" \
    "the mutant produced matching tags too ([$MUT_OPEN_TAG]/[$MUT_CLOSE_TAG]), so the real assertion discriminates nothing"
else
  ok "falsifier: the matching-tag assertion fails against a mismatched envelope"
fi
# Restore: the same content through the REAL hook passes again (already shown above by the
# REPO_P assertion, re-stated here beside the break for an explicit break/restore pair).
if [ -n "$KEEP_OPEN_TAG" ] && [ "$KEEP_OPEN_TAG" = "$KEEP_CLOSE_TAG" ]; then
  ok "restore: the unmodified hook and library produce a matching-tag envelope again"
else
  bad "restore: the unmodified hook and library produce a matching-tag envelope again" \
    "open=[$KEEP_OPEN_TAG] close=[$KEEP_CLOSE_TAG]"
fi

# ============================================================================
# Falsifier: prove envelope_wraps requires CONTAINMENT, not just "the heading text and a
# same-tag envelope both appear somewhere in the output" -- the observability judge's
# reported gap. Build a scratch hook tree whose reinject library's envelope_keep_headings
# emits an EMPTY envelope (open immediately followed by close, same real tag, nothing
# between) and then dumps the raw, UNSANITIZED heading text after the close marker --
# outside the envelope entirely. This defeats both the sanitizer (a plain `cat`, not
# sanitize_line) and any check that only looks for "does this text appear anywhere", and
# must still be rejected. Never touches the real library; only a scratch copy, and the
# replacement count is asserted exactly 1 so a future edit to the library fails this setup
# loudly instead of silently patching nothing.
# ============================================================================
RAWOUT_DIR="$TMP/mutant-keep-rawout"
mkdir -p "$RAWOUT_DIR/lib"
cp "$HOOK" "$RAWOUT_DIR/live-handoff.sh"
cp "$LIB" "$RAWOUT_DIR/lib/handoff-archive.sh"
python3 - "$HOOK_DIR/lib/handoff-keep-reinject.sh" "$RAWOUT_DIR/lib/handoff-keep-reinject.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
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
chmod +x "$RAWOUT_DIR/live-handoff.sh"
if [ "$RAWOUT_SETUP_RC" -eq 0 ]; then
  ok "containment falsifier setup: the scratch library was patched to emit an empty envelope plus a raw heading outside it"
else
  bad "containment falsifier setup: the scratch library was patched to emit an empty envelope plus a raw heading outside it" \
    "python3 replace failed, rc=$RAWOUT_SETUP_RC"
fi

REPO_RAWOUT="$TMP/repo-keep-rawout"
mkdir -p "$REPO_RAWOUT/.claude"
( cd "$REPO_RAWOUT" && git init -q )
cp "$REPO_P/.claude/session-state.md" "$REPO_RAWOUT/.claude/session-state.md"
run_hook "$REPO_RAWOUT" "$RAWOUT_DIR/live-handoff.sh" "sess-rawout"
cp "$OUT" "$TMP/rawout.out"

# Sanity check first: the mutant must actually produce BOTH a tagged envelope and the raw
# heading text, or a rejection below would be vacuous -- rejecting because the fixture is
# broken, not because envelope_wraps caught the defect it's meant to catch.
if grep -qF '=== Handoff ' "$TMP/rawout.out" && grep -qF 'Decisions [KEEP]' "$TMP/rawout.out"; then
  ok "containment falsifier: the mutant output actually contains a tagged envelope and the raw heading"
else
  bad "containment falsifier: the mutant output actually contains a tagged envelope and the raw heading" \
    "$(cat "$TMP/rawout.out")"
fi

if envelope_wraps "$TMP/rawout.out" 'Decisions [KEEP]'; then
  bad "containment falsifier: envelope_wraps rejects a raw heading printed outside an empty envelope" \
    "envelope_wraps accepted the mutant output: $(cat "$TMP/rawout.out")"
else
  ok "containment falsifier: envelope_wraps rejects a raw heading printed outside an empty envelope"
fi

if envelope_wraps "$TMP/good-keep.out" 'Decisions [KEEP]'; then
  ok "containment falsifier: envelope_wraps still accepts the real hook's genuine output"
else
  bad "containment falsifier: envelope_wraps still accepts the real hook's genuine output" \
    "$(cat "$TMP/good-keep.out")"
fi

