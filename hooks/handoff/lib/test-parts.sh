#!/usr/bin/env bash
# test-parts.sh — shared helper for the split *.test.sh runners under hooks/handoff/,
# used to source their *.test.d/NN-*.sh parts. Pure definitions: sourcing this file runs
# nothing, prints nothing, and exits nothing — same contract as
# hooks/handoff/lib/handoff-archive.sh's header. Safe to source more than once.
#
# Why this exists (observability finding, verdict 2026-09-16 on e19fc78): the four split
# runners used to `source` each part directly, in a bare sequence. `source` is not fatal
# on a missing/unreadable file or a syntax error inside a part — the runner just skips
# forward, still prints "N/N passed", exits 0, and writes its test marker. A green summary
# no longer proved every part ran. See hooks/handoff/lib/test-parts.test.sh for the suite
# that pins this, including falsifiers run against the four real split suites themselves.
#
# source_test_parts() below fails loudly instead: a missing part, an unreadable part, a
# part that fails `bash -n`, or a part count that does not match what the caller expects
# all print a `FAIL — ` line and `exit 2` — deliberately terminating the CALLER's process
# (this is meant to be sourced, not executed) before the caller's own summary/marker
# lines run. Every caller below therefore does:
#
#   source ".../lib/test-parts.sh" || exit 2
#   command -v source_test_parts >/dev/null 2>&1 || exit 2
#   source_test_parts "<parts dir>" <N>
#
# source_test_parts PARTS_DIR EXPECTED_COUNT
#   Globs "$PARTS_DIR"/[0-9][0-9]-*.sh in filename order and, for each part found:
#     - refuses if the file is not readable (covers an existing-but-permission-denied
#       part; a part that does not exist at all simply never appears in the glob, and is
#       instead caught by the count check below)
#     - refuses if `bash -n` reports a syntax error
#     - otherwise sources it into the CALLER's shell, so its own pass/fail bookkeeping
#       counts against the caller's totals, and counts it
#   After the loop, refuses if the count found does not equal EXPECTED_COUNT — this is
#   what catches a part that went missing outright, not just one that is present but
#   broken.
#
#   Never trust `source`'s own return status here: it is the exit status of the LAST
#   command the sourced part happened to run, not a load-succeeded signal, and a part
#   whose last command legitimately returns non-zero (e.g. a `grep` that finds nothing)
#   would otherwise be misread as a load failure.
source_test_parts() {
  local parts_dir="$1" expected_count="$2" part found=0

  for part in "$parts_dir"/[0-9][0-9]-*.sh; do
    if [ ! -r "$part" ]; then
      printf 'FAIL — part missing or unreadable: %s\n' "$part"
      exit 2
    fi
    if ! bash -n "$part" 2>/dev/null; then
      printf 'FAIL — syntax error in part: %s\n' "$part"
      exit 2
    fi
    # shellcheck source=/dev/null
    source "$part"
    found=$((found + 1))
  done

  if [ "$found" -ne "$expected_count" ]; then
    printf 'FAIL — expected %d parts, found %d\n' "$expected_count" "$found"
    exit 2
  fi
}
