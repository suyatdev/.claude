#!/usr/bin/env bash
# scan-secrets.test.sh — drives scan-secrets.sh's two modes: hook mode (a
# PreToolUse payload on stdin) and CLI mode (file paths as args). Run:
# bash hooks/scan-secrets.test.sh
#
# rules/gates.md's "Dormant hooks" bullet claimed this script "passes its
# tests" while no test file existed anywhere in the repo (verified: `find .
# -iname "*.test.sh"` before this file was added had no scan-secrets entry).
# docs/features/secret-command-guard.md's verification plan says "confirm
# scan-secrets.sh's existing test suite still passes before registering it"
# -- that assumed a suite that was never written. This file is that suite,
# written now because registering a Tier-1, FAIL-CLOSED hook under
# PreToolUse/Edit|Write|NotebookEdit with zero coverage would make every
# write in every session on this machine depend on unverified logic.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK="$(cd "$(dirname "$0")" && pwd)/scan-secrets.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0

payload_write() { # $1 file_path, $2 content
  /usr/bin/jq -nc --arg p "$1" --arg c "$2" '{hook_event_name:"PreToolUse",tool_input:{file_path:$p, content:$c}}'
}
payload_edit() { # $1 file_path, $2 new_string
  /usr/bin/jq -nc --arg p "$1" --arg c "$2" '{hook_event_name:"PreToolUse",tool_input:{file_path:$p, new_string:$c}}'
}
payload_multiedit() { # $1 file_path, $2 first new_string, $3 second new_string
  /usr/bin/jq -nc --arg p "$1" --arg a "$2" --arg b "$3" \
    '{hook_event_name:"PreToolUse",tool_input:{file_path:$p, edits:[{new_string:$a},{new_string:$b}]}}'
}

run_hook() { # $1 desc, $2 want-exit, $3 payload-json
  local desc="$1" want="$2" json="$3" got
  printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

run_cli() { # $1 desc, $2 want-exit, $3.. file args
  local desc="$1" want="$2"; shift 2
  local got
  bash "$HOOK" "$@" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

# =============================================================================
# Hook mode — each of the five patterns, one at a time, plus a clean baseline
# =============================================================================
run_hook "clean content -> allow"                 0 "$(payload_write /tmp/x.txt 'hello world, nothing sensitive here')"
run_hook "AWS access key id -> block"              2 "$(payload_write /tmp/x.txt 'key = AKIAIOSFODNN7EXAMPLE')"
run_hook "private key header -> block"             2 "$(payload_write /tmp/x.pem 'first line
-----BEGIN RSA PRIVATE KEY-----
MIIBOgIBAAJBAK...
-----END RSA PRIVATE KEY-----')"
run_hook "generic api key assignment -> block"     2 "$(payload_write /tmp/x.env 'api_key: "abcdefgh12345678"')"
run_hook "bearer token -> block"                   2 "$(payload_write /tmp/x.txt 'Authorization: Bearer abcdefghijklmnop1234567890')"
run_hook "password assignment -> block"            2 "$(payload_write /tmp/x.txt 'password = "supersecretvalue"')"

# Edit (new_string) and MultiEdit (edits[].new_string) go through the same
# extractor as Write's content -- confirm both shapes are actually scanned,
# not just the content key.
run_hook "Edit new_string carrying a secret -> block" 2 "$(payload_edit /tmp/x.txt 'password = "supersecretvalue"')"
run_hook "MultiEdit second edit carries a secret -> block" 2 \
  "$(payload_multiedit /tmp/x.txt 'clean line one' 'password = "supersecretvalue"')"
run_hook "MultiEdit, neither edit has a secret -> allow" 0 \
  "$(payload_multiedit /tmp/x.txt 'clean line one' 'clean line two')"

# The secret sits on its own line only once the payload's JSON-escaped
# newlines are decoded. A text-level extractor working on the raw JSON
# string would see one long line and could miss a pattern anchored to
# whitespace around it; a real JSON parser decodes it before scanning.
run_hook "secret reachable only through JSON-escaped newline -> block" 2 \
  "$(payload_write /tmp/x.txt $'line one\npassword = "supersecretvalue"\nline three')"

# Non-Write/Edit tool_input shape (e.g. a Bash payload) -- nothing to scan.
run_hook "unrelated tool_input shape (no content/new_string/edits) -> allow" 0 \
  '{"hook_event_name":"PreToolUse","tool_input":{"command":"echo hi"}}'

# =============================================================================
# Fail CLOSED — the opposite direction from secret-command-guard, by design
# (scan-secrets.sh's header states this explicitly)
# =============================================================================
printf '%s\n' 'not valid json at all' > "$TMP/bad.json"
got=$(bash "$HOOK" < "$TMP/bad.json" >/dev/null 2>&1; echo $?)
if [ "$got" -eq 2 ]; then
  printf 'ok   — unparseable payload -> FAIL CLOSED (exit %s)\n' "$got"; pass=$((pass+1))
else
  printf 'FAIL — unparseable payload -> FAIL CLOSED (want 2, got %s)\n' "$got"; fail=$((fail+1))
fi

# =============================================================================
# CLI mode — file paths as args, for pre-commit hooks / manual sweeps
# =============================================================================
printf 'password = "supersecretvalue"\n' > "$TMP/dirty.txt"
printf 'nothing sensitive here\n' > "$TMP/clean.txt"
run_cli "CLI mode, file with a secret -> block"    2 "$TMP/dirty.txt"
run_cli "CLI mode, clean file -> allow"            0 "$TMP/clean.txt"
run_cli "CLI mode, multiple files, one dirty -> block" 2 "$TMP/clean.txt" "$TMP/dirty.txt"

# =============================================================================
# Registration assertion: scan-secrets.sh must actually be wired into
# settings.json under PreToolUse/Edit|Write|NotebookEdit, with a mutation
# control so the assertion itself is proven able to fail.
# =============================================================================
SETTINGS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)/settings.json"
if [ -f "$SETTINGS" ] && /usr/bin/jq -e \
     '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("hooks/scan-secrets\\.sh"))' \
     "$SETTINGS" >/dev/null 2>&1; then
  printf 'ok   — scan-secrets.sh is registered under PreToolUse in settings.json\n'
  pass=$((pass+1))
else
  printf 'FAIL — scan-secrets.sh is registered under PreToolUse in settings.json (not found in %s)\n' "$SETTINGS"
  fail=$((fail+1))
fi

MUTANT="$TMP/settings-mutant.json"
/usr/bin/jq 'del(.hooks.PreToolUse[]?.hooks[]? | select(.command | test("scan-secrets")))' \
  "$SETTINGS" > "$MUTANT" 2>/dev/null
if /usr/bin/jq -e \
     '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("hooks/scan-secrets\\.sh"))' \
     "$MUTANT" >/dev/null 2>&1; then
  printf 'FAIL — registration check can fail (hook removed from a copy): mutant still reported present\n'
  fail=$((fail+1))
else
  printf 'ok   — registration check can fail (hook removed from a copy)\n'
  pass=$((pass+1))
fi

printf '\nscan-secrets: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
