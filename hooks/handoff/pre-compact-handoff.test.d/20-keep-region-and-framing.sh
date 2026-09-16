# 20-keep-region-and-framing.sh — sourced by ../pre-compact-handoff.test.sh — not runnable on its own.
# Covers the [KEEP]-region/no-[KEEP]/no-notepad new behaviour and the "REWRITE qualified by the filing rule" wording check. Writes $TMP/good-keep.out, read by 40-envelope-falsifiers.sh.

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

