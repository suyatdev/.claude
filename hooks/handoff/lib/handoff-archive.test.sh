#!/usr/bin/env bash
# handoff-archive.test.sh — unit tests for the shared hooks/handoff/lib/handoff-archive.sh
# library extracted from slim-session-start.sh by the extraction step of
# docs/features/handoff-trim-safety.md (named, not numbered — that card renumbers).
# Covers: the library is pure definitions (silent, idempotent, no set -u/-e imposed),
# gen_tag(), sanitize_line(), and the missing-library contract slim-session-start.sh now
# depends on (silent exit 0, emit nothing) — plus a falsifier proving the assertions here
# can actually fail, not just always pass.
# Run: bash hooks/handoff/lib/handoff-archive.test.sh
# The test bodies live in hooks/handoff/lib/handoff-archive.test.d/*.sh, sourced below
# in order; this file keeps only the header, setup/helpers, and the summary/marker tail.
#
# No CLAUDE_PANE_AGENT short-circuit to worry about here — that guard lives in
# slim-session-start.sh's main(), not in this library, so unlike its sibling suite this
# one does not need `env -u CLAUDE_PANE_AGENT` to get a clean run.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC2034 # only used inside the sourced *.test.d/ part files below,
# which shellcheck does not statically follow without -x
LIB="$LIB_DIR/handoff-archive.sh"
# shellcheck disable=SC2034 # only used inside the sourced *.test.d/ part files below
HOOK="$(cd "$LIB_DIR/.." && pwd)/slim-session-start.sh"

# Physical path, not the one mktemp hands back — mirrors slim-session-start.test.sh's note:
# on macOS mktemp -d returns the /var symlink form while other tools resolve to /private/var.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s (%s)\n' "$1" "$2"; fail=$((fail+1)); }

# Sources $1 (a library path) in a fresh bash process under set -u, then runs sanitize_line
# on $2 and prints just its output. Isolates each call from this test script's own state.
run_sanitize() { # $1 lib path, $2 line
  bash -c 'set -u; source "$1"; sanitize_line "$2"' _ "$1" "$2"
}

# ========================================================================================
# The rest of this file tests the library-building step's additions: snapshot, [KEEP]
# region extraction with fence tracking, protected-line membership, archive append,
# rotation, secret flagging and quarantine. Fence cases come first, per the card's
# TDD instruction, since fence tracking is what every other extraction test depends on.
#
# Helper: runs FUNC (with ARGS) in a fresh bash process after sourcing $LIB, isolating
# each call from this test script's own state exactly as run_sanitize does above.
# Captures stdout to $OUT and stderr to $ERR (both required args), returns FUNC's rc.
# ========================================================================================
call_lib() { # $1 out-file, $2 err-file, $3 lib path, $4 func name, $5.. func args
  local out="$1" err="$2" lib="$3" func="$4"
  shift 4
  bash -c 'set -u; source "$1"; shift; "$@"' _ "$lib" "$func" "$@" >"$out" 2>"$err"
  return $?
}

# shellcheck disable=SC2034 # only used inside the sourced *.test.d/ part files below
SCRATCH_ERR="$TMP/scratch.err"   # a throwaway err sink for calls that don't check stderr
# shellcheck disable=SC2034 # only used inside the sourced *.test.d/ part files below
REAL_SCANNER="$(cd "$LIB_DIR/../.." && pwd)/scan-secrets.sh"

# shellcheck source=hooks/handoff/lib/handoff-archive.test.d/10-definitions-and-sanitize.sh
source "$LIB_DIR/handoff-archive.test.d/10-definitions-and-sanitize.sh"
# shellcheck source=hooks/handoff/lib/handoff-archive.test.d/20-constants-and-fence.sh
source "$LIB_DIR/handoff-archive.test.d/20-constants-and-fence.sh"
# shellcheck source=hooks/handoff/lib/handoff-archive.test.d/30-membership.sh
source "$LIB_DIR/handoff-archive.test.d/30-membership.sh"
# shellcheck source=hooks/handoff/lib/handoff-archive.test.d/40-rotation-and-snapshot-copy.sh
source "$LIB_DIR/handoff-archive.test.d/40-rotation-and-snapshot-copy.sh"
# shellcheck source=hooks/handoff/lib/handoff-archive.test.d/50-secrets-quarantine-and-contract.sh
source "$LIB_DIR/handoff-archive.test.d/50-secrets-quarantine-and-contract.sh"

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
