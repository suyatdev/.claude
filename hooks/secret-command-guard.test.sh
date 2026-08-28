#!/usr/bin/env bash
# secret-command-guard.test.sh — drives the PreToolUse block path with JSON on
# stdin (the production code path). Run: bash hooks/secret-command-guard.test.sh
#
# Covers docs/features/secret-command-guard.md Scope item 1 (the two block
# shapes: a named dotfile outside a protected grep -o call, and a full-
# environment dump) plus the registration self-test convention this repo's
# other guards use (see feature-sync-guard.test.sh) with a mutation control.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK="$(cd "$(dirname "$0")" && pwd)/secret-command-guard.sh"

pass=0; fail=0

payload() { /usr/bin/jq -nc --arg c "$1" '{hook_event_name:"PreToolUse",tool_input:{command:$c}}'; }

run_case() { # $1 desc, $2 want-exit, $3 command string
  local desc="$1" want="$2" cmd="$3" got
  payload "$cmd" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else
    printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1))
  fi
}

run_case_msg() { # $1 desc, $2 want-exit, $3 stderr substring, $4 command string
  local desc="$1" want="$2" want_msg="$3" cmd="$4" got err
  err=$(mktemp)
  payload "$cmd" | bash "$HOOK" >/dev/null 2>"$err"
  got=$?
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL — %s (want exit %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); rm -f "$err"; return
  fi
  case "$(cat "$err")" in
    *"$want_msg"*) printf 'ok   — %s (exit %s, names "%s")\n' "$desc" "$got" "$want_msg"; pass=$((pass+1)) ;;
    *) printf 'FAIL — %s: stderr lacks "%s", got: %s\n' "$desc" "$want_msg" "$(cat "$err")"; fail=$((fail+1)) ;;
  esac
  rm -f "$err"
}

# =============================================================================
# Dotfile / path mentions — block unless inside a protected grep -o call
# =============================================================================
run_case_msg "cat a raw dotfile -> block, names it"                     2 '.zshrc' 'cat ~/.zshrc'
run_case_msg "unflagged grep on a dotfile -> block (the real incident)" 2 '.terminal_aliases' 'grep -n "export " ~/.terminal_aliases'
run_case "grep -o on a dotfile -> allow (protected shape)"              0 "grep -o 'ANTHROPIC[A-Z_]*=[A-Za-z0-9]*' ~/.zshrc"
run_case "grep --only-matching on a dotfile -> allow"                   0 "grep --only-matching 'KEY=[a-z]*' ~/.terminal_aliases"
run_case "grep -no clustered flag on a dotfile -> allow"                0 "grep -no 'KEY=[a-z]*' ~/.zshrc"
run_case_msg "cat piped into grep -o -> still blocks the cat segment"   2 '.zshrc' 'cat ~/.zshrc | grep -o "KEY=.*"'
run_case_msg ".env file -> block"                                       2 '.env' 'cat .env'
run_case "unrelated .envrc file -> allow (not .env or .env.*)"          0 'cat .envrc'
run_case_msg "credentials.json -> block"                                2 'credentials.json' 'cat credentials.json'
run_case_msg "Application Support credentials path -> block"            2 'credentials' \
  'cat "/Users/x/Library/Application Support/gh/credentials"'
run_case "unrelated file -> allow"                                      0 'cat README.md'

# =============================================================================
# Full-environment dumps
# =============================================================================
run_case_msg "bare env -> block"                                        2 "'env'" 'env'
run_case_msg "bare printenv -> block"                                   2 "'printenv'" 'printenv'
run_case "env with an assignment argument -> allow"                     0 'env FOO=bar mycmd'
run_case "printenv with a specific var -> allow"                        0 'printenv HOME'
run_case_msg "os.environ in a python -c string -> block"                2 'os.environ' 'python3 -c "print(os.environ)"'
run_case_msg "process.env in a node -e string -> block"                 2 'process.env' "node -e 'console.log(process.env)'"

# =============================================================================
# Trigger scoping
# =============================================================================
run_case "ordinary command with no secret shape -> allow"               0 'git status'
run_case "a VAR=value shell prefix on an ordinary command -> allow"     0 'FOO=bar echo hi'

# =============================================================================
# Fail-open direction — infrastructure absence never blocks
# =============================================================================
ORPHAN=$(mktemp -d)
cp "$HOOK" "$ORPHAN/secret-command-guard.sh"
payload 'cat ~/.zshrc' | bash "$ORPHAN/secret-command-guard.sh" >/dev/null 2>&1
got=$?
if [ "$got" -eq 0 ]; then
  printf 'ok   — no lib/ helper, would-be-blocked command -> FAIL OPEN (exit %s)\n' "$got"; pass=$((pass+1))
else
  printf 'FAIL — no lib/ helper, would-be-blocked command -> FAIL OPEN (want 0, got %s)\n' "$got"; fail=$((fail+1))
fi
rm -rf "$ORPHAN"

run_case_msg "control: same command, real hook -> block"                2 '.zshrc' 'cat ~/.zshrc'

# =============================================================================
# Registration assertion: checked against the REAL repo settings.json, not a
# fixture — that file is what Claude Code actually loads.
# =============================================================================
SETTINGS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)/settings.json"
if [ -f "$SETTINGS" ] && /usr/bin/jq -e \
     '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("hooks/secret-command-guard\\.sh"))' \
     "$SETTINGS" >/dev/null 2>&1; then
  printf 'ok   — secret-command-guard.sh is registered under PreToolUse in settings.json\n'
  pass=$((pass+1))
else
  printf 'FAIL — secret-command-guard.sh is registered under PreToolUse in settings.json (not found in %s)\n' "$SETTINGS"
  fail=$((fail+1))
fi

# Self-check: the assertion above must be able to fail, not just always pass.
# Strip the hook from a copy of the real file and confirm the same query
# reports it missing.
MUTANT=$(mktemp)
/usr/bin/jq 'del(.hooks.PreToolUse[]?.hooks[]? | select(.command | test("secret-command-guard")))' \
  "$SETTINGS" > "$MUTANT" 2>/dev/null
if /usr/bin/jq -e \
     '[.hooks.PreToolUse[]?.hooks[]?.command] | any(test("hooks/secret-command-guard\\.sh"))' \
     "$MUTANT" >/dev/null 2>&1; then
  printf 'FAIL — registration check can fail (hook removed from a copy): mutant still reported present\n'
  fail=$((fail+1))
else
  printf 'ok   — registration check can fail (hook removed from a copy)\n'
  pass=$((pass+1))
fi
rm -f "$MUTANT"

printf '\nsecret-command-guard: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
