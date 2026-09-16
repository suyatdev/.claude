# shellcheck shell=bash
# test-lib.sh — shared harness for the panes/*.test.sh suites.
#
# Sourced, not executed. Caller contract, in order:
#   1. set -u
#   2. . "$(dirname "$0")/test-lib.sh"   (this file)
#   3. domain fixtures (detect.sh stub, adapter stub, PROMPT, PANE_* exports, ...)
#   4. assertions, calling ok()/bad() (or a per-file equivalent)
#   5. tl_finish as the LAST line — the script's exit status is tl_finish's.
#
# No caller may install its own `trap ... EXIT` (see TMP below) and no caller
# may rely on footer code running automatically (see tl_finish below).

# $0 under `source` is the CALLER's $0, not this file's path — that is exactly
# why MARKER_SELF is built here rather than passed in: computing it in the
# library captures the sourcing script's own path.
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# `|| exit 1`, NOT `|| return 1`. A sourced file's `return` only returns from
# the sourcing (dot) command — the caller keeps running with MARKER_ROOT
# unset, `set -u` or not, and would exit 0. That is fail-open: a suite run
# outside a git repository would report a green pass. `exit` terminates the
# calling script's process outright, preserving today's fail-closed behaviour.
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

# `|| exit 1` for the same fail-closed reason as MARKER_ROOT above: without
# it a failed mktemp leaves TMP empty, every "$TMP/..." path resolves to /,
# and the suite runs on against the real filesystem.
TMP="$(mktemp -d)" || exit 1
# This library creates TMP, so it — and only it — owns the cleanup trap. A
# second `trap ... EXIT` installed by a caller would replace this one rather
# than chain with it, leaking $TMP. Callers must not trap EXIT themselves.
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok() { # $1 label
  printf 'ok   — %s\n' "$1"
  pass=$((pass + 1))
}

bad() { # $1 label, $2 optional detail
  printf 'FAIL — %s%s\n' "$1" "${2:+ ($2)}"
  fail=$((fail + 1))
}

# tl_finish is an explicit function the caller invokes last — it is
# deliberately NOT top-level code in this file and NOT an EXIT trap:
#
#   - Top-level code in a sourced file runs at SOURCE time, i.e. first, while
#     pass=0 fail=0 are still their initial values. That would print a green
#     "0 passed, 0 failed" and write a test marker for a suite that never
#     ran — the exact "receipt for work not done" failure this split exists
#     to avoid.
#   - An EXIT trap here would collide with the `trap ... EXIT` above that
#     removes $TMP; only one EXIT trap can be installed at a time, so this
#     one would silently replace the cleanup trap and leak the temp dir.
#
# Hence: a plain function, called by the caller as its last statement.
tl_finish() {
  printf '\n%s passed, %s failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
    "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
  [ "$fail" -eq 0 ]
}
