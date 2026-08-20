#!/usr/bin/env bash
#
# test-marker-guard.sh — PreToolUse hook (matcher: Bash).
#
# Blocks a `git commit` when a file with a sibling test (the X.sh<->X.test.sh /
# X.py<->X.test.py convention) is being committed at a version its test suite has never passed
# against. "The marker is a receipt, not a grade" (ADR 0027, docs/decisions/) -- this proves the
# suite RAN against these exact bytes, never that the suite is any good.
#
# Global-but-INERT (docs/features/verification-marker-gate.md, "Where the gate is active"):
# registered for every repo on this machine, but does nothing unless
# <toplevel>/hooks/lib/write-test-marker.py exists and is readable -- the opt-in signal, since a
# repo cannot be held to a receipt it has no way to issue. The ONE exception is MSG_NO_PYTHON,
# which fires before any repo can even be identified, exactly like git-guard.sh / judge-guard.sh /
# merge-guard.sh already do.
#
# This is a thin bash wrapper around ONE python3 decision call (ADR 0026: no JSON crosses back
# into bash). Bash owns: the raw-payload pre-filter, the cwd/toplevel/opt-in resolution before
# that call, and turning its one TSV line of output into an exit code, a stderr message and a log
# line. Everything else -- classification, path collection, pairing, marker reading, blob
# comparison -- runs in hooks/lib/decide-commit-gate.py, which this file never parses the output
# of beyond the four-field shape check below.
#
# Exit 0 = allow (silent). Exit 2 = blocked, reason on stderr.
#
# Escape hatch: `TEST_EXEMPT='<reason>' git commit ...` (1-200 bytes of printable ASCII,
# validated and logged, never silently discarded).

set -u

HOOKDIR="$(cd "$(dirname "$0")" && pwd)"
ENTRY="$HOOKDIR/lib/decide-commit-gate.py"

TAB="$(printf '\t')"

# --- The pre-filter: raw payload bytes, before anything else runs -------------------------
# A payload that does not even MENTION "commit" anywhere cannot be a git commit, so every door
# below it -- including the python3 check -- is skipped. This is what keeps a totally unrelated
# Bash call (or one with no stdin at all) from paying for a python3 start.
payload=""
if [ ! -t 0 ]; then payload=$(cat); fi

case "$payload" in
  *commit*) ;;
  *) exit 0 ;;
esac

# --- node NP: is python3 usable? The only machine-global door -----------------------------
py=$(command -v python3 || command -v python) || py=""
if [ -z "$py" ]; then
  printf 'test-marker-guard: MSG_NO_PYTHON -- python3 not on PATH; cannot verify test markers -- failing closed.\n' >&2
  exit 2
fi

# --- node RC: does the payload parse, and does it carry a string cwd? ----------------------
# The target repo is unknowable without this, so an unparseable payload or a missing cwd is
# allowed exactly as git-guard.sh:72 allows on an empty command extraction -- accepted-open,
# never a machine-global block (only MSG_NO_PYTHON is that).
cwd=$(printf '%s' "$payload" | "$py" -I -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(payload, dict):
    value = payload.get("cwd")
    if isinstance(value, str):
        sys.stdout.write(value)
' 2>/dev/null)
[ -n "$cwd" ] || exit 0

# --- node F: does a toplevel resolve from that cwd? -----------------------------------------
# Measured: outside a repo this exits 128 with empty stdout -- "there is no repo here", not an
# error, so the gate allows and leaves the refusal to git itself.
toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -n "$toplevel" ] || exit 0

# --- node G: is the writer installed in THIS repo? The opt-in signal -----------------------
[ -r "$toplevel/hooks/lib/write-test-marker.py" ] || exit 0

STATE_DIR="$toplevel/hooks/state"
LOG="$STATE_DIR/test-marker.log"

# The store and the log are default-deny (core-conduct). Both this hook and the writer can be
# the first to touch hooks/state/, and whichever runs second cannot repair a loose mode it did
# not set (measured: mkdir -p -m and os.makedirs alike leave a PRE-EXISTING directory's mode
# untouched) -- so both components run the identical create-then-chmod pair, unconditionally.
write_log() { # $1 verdict (BLOCK|EXEMPT), $2 reason, $3 pair
  mkdir -p -m 0700 "$STATE_DIR" 2>/dev/null
  chmod 0700 "$STATE_DIR" 2>/dev/null
  touch "$LOG" 2>/dev/null
  chmod 0600 "$LOG" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >> "$LOG" 2>/dev/null
}

# --- node CM: is the decision entry point present and readable? ----------------------------
if [ ! -r "$ENTRY" ]; then
  printf 'test-marker-guard: MSG_CLASSIFIER_MISSING -- %s is missing or unreadable; every commit in this repo is blocked until it is restored.\n' "$ENTRY" >&2
  write_log BLOCK MSG_CLASSIFIER_MISSING -
  exit 2
fi

# --- node CF: the decision call. Bash hands over the SAME buffered bytes it already read; the
# entry point does not re-read the tool's stdin. Its own stderr is discarded -- an internal
# traceback is not part of this hook's message contract, only its exit code and stdout are.
out=$(printf '%s' "$payload" | "$py" -I "$ENTRY" 2>/dev/null)
rc=$?

if [ "$rc" -eq 3 ]; then
  printf 'test-marker-guard: MSG_BAD_PAYLOAD -- the decision call could not read a payload this hook already parsed.\n' >&2
  write_log BLOCK MSG_BAD_PAYLOAD -
  exit 2
fi
if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
  printf 'test-marker-guard: MSG_CLASSIFIER_FAILED -- the decision call exited abnormally.\n' >&2
  write_log BLOCK MSG_CLASSIFIER_FAILED -
  exit 2
fi

# --- node CO: shape check, before any field is believed -------------------------------------
bad_shape=0
case "$out" in
  *$'\n'*) bad_shape=1 ;;
esac

f1=""; f2=""; f3=""; f4=""
if [ "$bad_shape" -eq 0 ]; then
  IFS="$TAB" read -r f1 f2 f3 f4 <<< "$out"
  [ -n "$f1" ] || bad_shape=1
  [ -n "$f2" ] || bad_shape=1
  [ -n "$f3" ] || bad_shape=1
  [ -n "$f4" ] || bad_shape=1
  case "$f4" in
    *"$TAB"*) bad_shape=1 ;;
  esac
  case "$f1" in
    ALLOW|BLOCK|EXEMPT) ;;
    *) bad_shape=1 ;;
  esac
fi

if [ "$bad_shape" -ne 0 ]; then
  printf 'test-marker-guard: MSG_CLASSIFIER_BAD_OUTPUT -- the decision call reported something this gate cannot parse.\n' >&2
  write_log BLOCK MSG_CLASSIFIER_BAD_OUTPUT -
  exit 2
fi

# --- node DEC: field 1 decides ---------------------------------------------------------------
case "$f1" in
  ALLOW)
    exit 0
    ;;
  EXEMPT)
    write_log EXEMPT "$f3" "$f4"
    exit 0
    ;;
esac

# f1 is BLOCK. Field 2's domain is checked by the SAME case that prints the message -- a
# constant this version does not recognise is indistinguishable from a corrupt line, and both
# are the same failure: a component said something this version cannot act on.
case "$f2" in
  MSG_NOTHING_RUNNABLE)
    printf 'test-marker-guard: MSG_NOTHING_RUNNABLE -- this Bash call has nothing runnable in it.\n' >&2
    ;;
  MSG_BAD_EXEMPT)
    printf 'test-marker-guard: MSG_BAD_EXEMPT -- TEST_EXEMPT must be 1-200 bytes of printable ASCII (0x20-0x7E), with no control characters.\n' >&2
    ;;
  MSG_UNSUPPORTED_FORM)
    printf 'test-marker-guard: MSG_UNSUPPORTED_FORM (%s) -- this commit'"'"'s contents cannot be verified before it runs. Run it as its own command, or set TEST_EXEMPT.\n' "$f3" >&2
    ;;
  MSG_GIT_FAILED)
    printf 'test-marker-guard: MSG_GIT_FAILED -- a git command this gate depends on failed unexpectedly.\n' >&2
    ;;
  MSG_NO_MARKER)
    printf 'test-marker-guard: MSG_NO_MARKER -- %s has no test marker. Run: %s\n' "$f4" "$f3" >&2
    ;;
  MSG_BAD_MARKER)
    printf 'test-marker-guard: MSG_BAD_MARKER -- the marker for %s is unreadable or invalid.\n' "$f4" >&2
    ;;
  MSG_STALE_SUBJECT)
    printf 'test-marker-guard: MSG_STALE_SUBJECT -- %s would ship a version its test never ran against.\n' "$f4" >&2
    ;;
  MSG_STALE_TEST)
    printf 'test-marker-guard: MSG_STALE_TEST -- %s would ship a test version that was never run.\n' "$f4" >&2
    ;;
  *)
    f2=MSG_CLASSIFIER_BAD_OUTPUT
    f4=-
    printf 'test-marker-guard: MSG_CLASSIFIER_BAD_OUTPUT -- the decision call named a door this version of the gate does not recognise.\n' >&2
    ;;
esac

write_log BLOCK "$f2" "$f4"
exit 2
