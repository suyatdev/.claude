# shellcheck shell=bash
# 30-library-load-failures.sh — sourced by ../pre-compact-handoff.test.sh — not runnable on its own.
# Covers the fail-OPEN append-only behaviour when a required library is unloadable, Finding B (two libraries gate the directive), and the filing rule living in exactly one place. Reads $REPO_KEEP from 20-keep-region-and-framing.sh.

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

