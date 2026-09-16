#!/usr/bin/env bash
# test-parts.test.sh — unit tests for hooks/handoff/lib/test-parts.sh, the shared
# source_test_parts() helper the four split *.test.sh runners under hooks/handoff/ use to
# source their *.test.d/NN-*.sh parts.
#
# Why this exists (observability finding, verdict 2026-09-16 on e19fc78): each runner used
# to `source` its parts in a bare sequence. `source` is not fatal on a missing/unreadable
# file or a syntax error inside a part — the runner just skips forward, still prints
# "N/N passed", exits 0, and writes its test marker. A green summary no longer proved every
# part ran. See docs/features/handoff-trim-safety.md, "Verification" section, for the
# measured before/after counts on the four real suites.
#
# Run: bash hooks/handoff/lib/test-parts.test.sh
#
# Covers, in order:
#   (a) a fake two-part fixture — both parts source into the CALLING shell, in order, and
#       control returns to the caller when the count matches;
#   (b) EXPECTED_COUNT one higher than the parts actually present — FAIL, exit 2, nothing
#       after the call runs;
#   (c) a syntax error inside a part — FAIL, exit 2;
#   (d) an unreadable part (chmod 000) — FAIL, exit 2 (skipped, with a note, when running
#       as root, since root ignores a 000 mode);
#   (e) the REAL falsifiers: each of the four actual split suites, copied and mutated
#       (last part deleted, then a syntax error injected), must itself fail loudly — not
#       just the fake fixture above.
#
# source_test_parts() calls `exit` on failure, deliberately terminating whatever process
# sourced it — so every call below runs in a throwaway `bash -c` subprocess (isolating
# this runner's own process from that exit), mirroring handoff-archive.test.sh's
# call_lib() pattern.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$LIB_DIR/test-parts.sh"
REPO_ROOT="$(cd "$LIB_DIR/../../.." && pwd)"

# Physical path, not the one mktemp hands back — mirrors every sibling suite's note: on
# macOS mktemp -d returns the /var symlink form while `git rev-parse --show-toplevel`
# resolves to /private/var, and a path-string comparison of the two reads as a mismatch
# that isn't one.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

# mkfakeparts DIR — writes a two-part fixture: 10-a.sh appends "A" to COUNTER,
# 20-b.sh appends "B". A caller that sources both in order ends up with COUNTER=AB;
# out of order or missing one gives anything else.
mkfakeparts() {
  local dir="$1"
  mkdir -p "$dir"
  printf 'COUNTER="${COUNTER:-}A"\n' > "$dir/10-a.sh"
  printf 'COUNTER="${COUNTER:-}B"\n' > "$dir/20-b.sh"
}

# call_stp OUT ERR PARTS_DIR EXPECTED_COUNT — runs source_test_parts in a fresh
# subprocess, printing COUNTER and an AFTER_CALL_RAN marker afterward so "nothing after
# the call runs" (on failure) and "both parts sourced into the caller's shell" (on
# success) are both checkable from the captured output rather than trusted on faith.
# Returns source_test_parts' own exit status.
call_stp() {
  local out="$1" err="$2" parts_dir="$3" expected="$4"
  bash -c '
    set -u
    source "$1" || exit 2
    source_test_parts "$2" "$3"
    printf "COUNTER=%s\n" "${COUNTER:-}"
    printf "AFTER_CALL_RAN\n"
  ' _ "$LIB" "$parts_dir" "$expected" >"$out" 2>"$err"
  return $?
}

# ==========================================================================================
# (a) Two real parts, exact count — both sourced in order into the caller's shell, count
#     check passes, control returns to the caller.
# ==========================================================================================
FAKE_A="$TMP/fake-a"
mkfakeparts "$FAKE_A"
OUT_A="$TMP/a.out"; ERR_A="$TMP/a.err"
call_stp "$OUT_A" "$ERR_A" "$FAKE_A" 2
RC_A=$?
if [ "$RC_A" -eq 0 ]; then ok "exact count -> source_test_parts returns 0"
else bad "exact count -> source_test_parts returns 0" "rc=$RC_A stderr=$(cat "$ERR_A")"; fi
if grep -qx 'COUNTER=AB' "$OUT_A"; then
  ok "exact count -> both parts sourced, in order, into the caller's own shell"
else
  bad "exact count -> both parts sourced, in order, into the caller's own shell" \
    "$(cat "$OUT_A")"
fi
if grep -qx 'AFTER_CALL_RAN' "$OUT_A"; then
  ok "exact count -> control returns to the caller (no spurious exit)"
else
  bad "exact count -> control returns to the caller (no spurious exit)" "$(cat "$OUT_A")"
fi

# ==========================================================================================
# (b) EXPECTED_COUNT one higher than the parts present -> FAIL, exit 2, nothing after
#     the call runs.
# ==========================================================================================
OUT_B="$TMP/b.out"; ERR_B="$TMP/b.err"
call_stp "$OUT_B" "$ERR_B" "$FAKE_A" 3
RC_B=$?
if [ "$RC_B" -eq 2 ]; then ok "count mismatch (3 expected, 2 present) -> exit 2"
else bad "count mismatch (3 expected, 2 present) -> exit 2" "rc=$RC_B"; fi
if grep -q 'FAIL' "$OUT_B"; then ok "count mismatch -> a FAIL line is printed"
else bad "count mismatch -> a FAIL line is printed" "$(cat "$OUT_B")"; fi
if grep -q '2' "$OUT_B" && grep -q '3' "$OUT_B"; then
  ok "count mismatch -> the FAIL line names both the expected and found counts"
else
  bad "count mismatch -> the FAIL line names both the expected and found counts" "$(cat "$OUT_B")"
fi
if grep -qx 'AFTER_CALL_RAN' "$OUT_B"; then
  bad "count mismatch -> nothing after the call runs" "AFTER_CALL_RAN was printed"
else
  ok "count mismatch -> nothing after the call runs"
fi

# ==========================================================================================
# (c) A syntax error inside a part -> FAIL, exit 2, nothing after the call runs.
# ==========================================================================================
FAKE_C="$TMP/fake-c"
mkfakeparts "$FAKE_C"
printf 'if [ 1 ]\n' >> "$FAKE_C/20-b.sh"   # deliberately unclosed -- bash -n must reject it
OUT_C="$TMP/c.out"; ERR_C="$TMP/c.err"
call_stp "$OUT_C" "$ERR_C" "$FAKE_C" 2
RC_C=$?
if [ "$RC_C" -eq 2 ]; then ok "syntax error in a part -> exit 2"
else bad "syntax error in a part -> exit 2" "rc=$RC_C"; fi
if grep -q 'FAIL' "$OUT_C"; then ok "syntax error in a part -> a FAIL line is printed"
else bad "syntax error in a part -> a FAIL line is printed" "$(cat "$OUT_C")"; fi
if grep -qx 'AFTER_CALL_RAN' "$OUT_C"; then
  bad "syntax error in a part -> nothing after the call runs" "AFTER_CALL_RAN was printed"
else
  ok "syntax error in a part -> nothing after the call runs"
fi
# The good part (10-a.sh) must never have been sourced either -- the loop refuses the
# FIRST bad part it finds and stops, it does not skip past it and keep going.
if grep -q 'COUNTER=' "$OUT_C"; then
  bad "syntax error in a part -> no part after it is treated as sourced" "$(cat "$OUT_C")"
else
  ok "syntax error in a part -> no part after it is treated as sourced"
fi

# ==========================================================================================
# (d) An unreadable part (chmod 000) -> FAIL, exit 2. Skipped, with a printed note, when
#     this process runs as root -- root ignores a 000 mode, so the premise doesn't hold.
# ==========================================================================================
if [ "$(id -u)" = "0" ]; then
  printf 'note — skipped: running as root, chmod 000 does not make a file unreadable\n'
else
  FAKE_D="$TMP/fake-d"
  mkfakeparts "$FAKE_D"
  chmod 000 "$FAKE_D/20-b.sh"
  OUT_D="$TMP/d.out"; ERR_D="$TMP/d.err"
  call_stp "$OUT_D" "$ERR_D" "$FAKE_D" 2
  RC_D=$?
  if [ "$RC_D" -eq 2 ]; then ok "unreadable part -> exit 2"
  else bad "unreadable part -> exit 2" "rc=$RC_D"; fi
  if grep -q 'FAIL' "$OUT_D"; then ok "unreadable part -> a FAIL line is printed"
  else bad "unreadable part -> a FAIL line is printed" "$(cat "$OUT_D")"; fi
  if grep -qx 'AFTER_CALL_RAN' "$OUT_D"; then
    bad "unreadable part -> nothing after the call runs" "AFTER_CALL_RAN was printed"
  else
    ok "unreadable part -> nothing after the call runs"
  fi
fi

# ==========================================================================================
# (e) Real-runner falsifiers — the fixture above proves the helper works in isolation; this
#     proves the four ACTUAL split suites actually call it and actually fail loudly.
#
#     Each real suite is copied whole (cp -R hooks) into its own scratch dir and given its
#     OWN throwaway git repo (git init -q; git add -A — git ls-files reads the index, so no
#     commit is needed) before being mutated. This deliberately does NOT follow a literal
#     "run it from a non-repo directory" recipe: every runner resolves MARKER_ROOT via
#     `git rev-parse --show-toplevel` as its very first executable line, so outside ANY git
#     repo that line fails and the process exits before ever reaching the part-sourcing
#     logic under test — a mutant and an unmutated copy would then be indistinguishable
#     (both exit 1 with no output), which is not a falsifier, it's a tautology. Giving each
#     copy its own repo lets MARKER_ROOT resolve — but resolves it to the SCRATCH COPY's
#     own toplevel, never to this worktree's, so a marker the mutant run writes (verified
#     below to be harmless either way) lands inside $TMP, nowhere near the real
#     hooks/state/. That is checked, not assumed: SAFETY below hashes this worktree's real
#     hooks/state/ before and after every one of these runs.
# ==========================================================================================
REAL_SUITES="
hooks/handoff/slim-session-start.test.sh|hooks/handoff/slim-session-start.test.d|40-contract-and-guard-liveness.sh
hooks/handoff/pre-compact-handoff.test.sh|hooks/handoff/pre-compact-handoff.test.d|50-pretrim-snapshot.sh
hooks/handoff/live-handoff.test.sh|hooks/handoff/live-handoff.test.d|40-preexisting-and-task-bug-wording.sh
hooks/handoff/lib/handoff-archive.test.sh|hooks/handoff/lib/handoff-archive.test.d|50-secrets-quarantine-and-contract.sh
"

# state_snapshot DIR — one string covering every file's path, mtime and size under DIR
# (or "MISSING"), hashed to a single token. Two snapshots compare equal iff nothing was
# added, removed, or modified — mtime alone would miss a same-second rewrite; size alone
# would miss a same-size rewrite; together with the path list they catch both.
state_snapshot() {
  local dir="$1"
  if [ ! -d "$dir" ]; then printf 'MISSING'; return; fi
  find "$dir" -type f -exec stat -f '%N %m %z' {} \; 2>/dev/null | sort | md5 -q
}

REAL_STATE_DIR="$REPO_ROOT/hooks/state"
STATE_BEFORE="$(state_snapshot "$REAL_STATE_DIR")"

# mk_isolated_copy N -> prints the path of a fresh scratch copy of hooks/, with its own
# throwaway git repo, files staged.
mk_isolated_copy() {
  local n="$1" dir
  dir="$TMP/copy-$n"
  mkdir -p "$dir"
  cp -R "$REPO_ROOT/hooks" "$dir/hooks"
  ( cd "$dir" \
      && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q . \
      && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git add -A ) >/dev/null 2>&1
  printf '%s' "$dir"
}

n_copy=0
E_TIME_START="$(date +%s)"
while IFS='|' read -r rel_script rel_partsdir last_part; do
  [ -n "$rel_script" ] || continue

  # --- Mutant 1: the suite's last part is deleted outright. ---------------------------
  n_copy=$((n_copy+1))
  COPY1="$(mk_isolated_copy "$n_copy")"
  rm -f "$COPY1/$rel_partsdir/$last_part"
  OUT1="$TMP/e.$n_copy.out"
  ( cd "$COPY1" && env -u CLAUDE_PANE_AGENT bash "$rel_script" ) >"$OUT1" 2>&1
  RC1=$?
  if [ "$RC1" -ne 0 ]; then
    ok "$rel_script: last part deleted -> exit code is non-zero"
  else
    bad "$rel_script: last part deleted -> exit code is non-zero" "rc=$RC1"
  fi
  if grep -qE '^[0-9]+/[0-9]+ passed$' "$OUT1"; then
    bad "$rel_script: last part deleted -> no \"N/N passed\" line printed" "$(tail -3 "$OUT1")"
  else
    ok "$rel_script: last part deleted -> no \"N/N passed\" line printed"
  fi

  # --- Mutant 2: the suite's last part gets a syntax error appended. ------------------
  n_copy=$((n_copy+1))
  COPY2="$(mk_isolated_copy "$n_copy")"
  printf 'fi\n' >> "$COPY2/$rel_partsdir/$last_part"
  OUT2="$TMP/e.$n_copy.out"
  ( cd "$COPY2" && env -u CLAUDE_PANE_AGENT bash "$rel_script" ) >"$OUT2" 2>&1
  RC2=$?
  if [ "$RC2" -ne 0 ]; then
    ok "$rel_script: syntax error appended to last part -> exit code is non-zero"
  else
    bad "$rel_script: syntax error appended to last part -> exit code is non-zero" "rc=$RC2"
  fi
  if grep -qE '^[0-9]+/[0-9]+ passed$' "$OUT2"; then
    bad "$rel_script: syntax error appended to last part -> no \"N/N passed\" line printed" \
      "$(tail -3 "$OUT2")"
  else
    ok "$rel_script: syntax error appended to last part -> no \"N/N passed\" line printed"
  fi
done <<EOF_SUITES
$REAL_SUITES
EOF_SUITES
E_TIME_END="$(date +%s)"
printf 'test-parts.test.sh: real-runner falsifiers wall time: %ds\n' "$((E_TIME_END - E_TIME_START))"

# --- SAFETY: none of the eight runs above touched this worktree's real hooks/state/. ----
STATE_AFTER="$(state_snapshot "$REAL_STATE_DIR")"
if [ "$STATE_BEFORE" = "$STATE_AFTER" ]; then
  ok "SAFETY: this worktree's real hooks/state/ is byte-for-byte unchanged (mtime+size hash) by all eight scratch-copy runs"
else
  bad "SAFETY: this worktree's real hooks/state/ is byte-for-byte unchanged (mtime+size hash) by all eight scratch-copy runs" \
    "before=$STATE_BEFORE after=$STATE_AFTER"
fi

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
