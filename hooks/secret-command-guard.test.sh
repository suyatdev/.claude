#!/usr/bin/env bash
# secret-command-guard.test.sh — drives the PreToolUse block path with JSON on
# stdin (the production code path). Run: bash hooks/secret-command-guard.test.sh
#
# Covers docs/features/secret-command-guard.md Scope item 1 (the two block
# shapes: any mention of a named secret-bearing path, and a full-environment
# dump), the 2026-08-28 amendment (the grep -o carve-out is GONE, the three
# non-secret .env suffixes are exempt, SECRET_EXEMPT is the escape hatch),
# and the Known-gaps table — every row of which is pinned by an ALLOW
# assertion, so a later widening cannot silently change the disclosed
# contract without turning this suite red.
#
# Registration self-test convention and its mutation control follow this
# repo's other guards (see feature-sync-guard.test.sh).
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

run_case_nomsg() { # $1 desc, $2 want-exit, $3 stderr substring that must be ABSENT, $4 command
  local desc="$1" want="$2" bad_msg="$3" cmd="$4" got err
  err=$(mktemp)
  payload "$cmd" | bash "$HOOK" >/dev/null 2>"$err"
  got=$?
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL — %s (want exit %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); rm -f "$err"; return
  fi
  case "$(cat "$err")" in
    *"$bad_msg"*) printf 'FAIL — %s: stderr still recommends "%s"\n' "$desc" "$bad_msg"; fail=$((fail+1)) ;;
    *) printf 'ok   — %s (exit %s, never says "%s")\n' "$desc" "$got" "$bad_msg"; pass=$((pass+1)) ;;
  esac
  rm -f "$err"
}

# =============================================================================
# Dotfile / path mentions — EVERY mention blocks. There is no permitted read
# shape (2026-08-28 amendment; ADR 0039).
# =============================================================================
run_case_msg "cat a raw dotfile -> block, names it"                     2 '.zshrc' 'cat ~/.zshrc'
run_case_msg "unflagged grep on a dotfile -> block (the real incident)" 2 '.terminal_aliases' 'grep -n "export " ~/.terminal_aliases'
run_case_msg "cat piped into grep -o -> blocks the cat segment"         2 '.zshrc' 'cat ~/.zshrc | grep -o "KEY=.*"'
run_case_msg "credentials.json -> block"                                2 'credentials.json' 'cat credentials.json'
run_case_msg "Application Support credentials path -> block"            2 'credentials' \
  'cat "/Users/x/Library/Application Support/gh/credentials"'
run_case "unrelated .envrc file -> allow (not .env or .env.*)"          0 'cat .envrc'
run_case "unrelated file -> allow"                                      0 'cat README.md'

# -----------------------------------------------------------------------------
# The carve-out that reproduced the incident. These three ALLOWed before the
# 2026-08-28 amendment; `grep -o 'export .*'` printed the whole secret line.
# -----------------------------------------------------------------------------
run_case_msg "grep -o 'export .*' -> block (reproduced the leak verbatim)"  2 '.terminal_aliases' \
  "grep -o 'export .*' ~/.terminal_aliases"
run_case_msg "grep -o '.*' -> block (the pattern is the caller's to choose)" 2 '.terminal_aliases' \
  "grep -o '.*' ~/.terminal_aliases"
run_case_msg "narrow grep -o -> block too; no shape is permitted now"    2 '.zshrc' \
  "grep -o 'ANTHROPIC[A-Z_]*=[A-Za-z0-9]*' ~/.zshrc"
run_case_msg "grep --only-matching -> block"                            2 '.terminal_aliases' \
  "grep --only-matching 'KEY=[a-z]*' ~/.terminal_aliases"
run_case_msg "grep -no clustered flag -> block"                         2 '.zshrc' "grep -no 'KEY=[a-z]*' ~/.zshrc"
run_case_msg "grep -e -notes .env -> block (a pattern is not an -o flag)" 2 '.env' 'grep -e -notes .env'

# The deny message must not recommend the shape that leaked.
run_case_nomsg "deny message no longer recommends grep -o"              2 'grep -o' 'cat ~/.zshrc'

# =============================================================================
# The .env family: three conventionally-committed suffixes are exempt.
# =============================================================================
run_case "git add .env.example -> allow (never carries a value)"        0 'git add .env.example'
run_case "cat .env.template -> allow"                                   0 'cat .env.template'
run_case "cat .env.sample -> allow"                                     0 'cat .env.sample'
run_case "a path'd .env.example -> allow"                               0 'cat config/.env.example'
run_case_msg "control: bare .env -> block"                              2 '.env' 'cat .env'
run_case_msg "control: .env.local -> block"                             2 '.env' 'cat .env.local'
run_case_msg "control: .env.production -> block"                        2 '.env' 'cat .env.production'
run_case_msg "control: docker --env-file .env -> block"                 2 '.env' 'docker compose --env-file .env up'
run_case "docker --env-file .env.example -> allow"                      0 'docker compose --env-file .env.example up'

# =============================================================================
# SECRET_EXEMPT=<reason> — the escape hatch, matching this repo's other Tier 1
# guards (MERGE_EXEMPT / TEST_EXEMPT / JUDGE_EXEMPT / WORKTREE_EXEMPT).
# =============================================================================
run_case "SECRET_EXEMPT with a reason -> allow"                         0 'SECRET_EXEMPT=rotating-the-key cat ~/.zshrc'
run_case "SECRET_EXEMPT also clears an env dump"                        0 'SECRET_EXEMPT=debugging-a-hook env'
run_case_msg "SECRET_EXEMPT with an EMPTY reason -> still blocks"       2 '.zshrc' 'SECRET_EXEMPT= cat ~/.zshrc'
run_case_msg "an unrelated assignment does not exempt"                  2 '.zshrc' 'FOO=bar cat ~/.zshrc'

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
# KNOWN GAPS — every row of the card's Known-gaps table, pinned as ALLOW.
#
# These are NOT endorsements. They record measured, disclosed holes so that
# widening the guard is a deliberate edit to this block rather than a silent
# change to what the card promises. If one of these starts failing, the guard
# grew: update the card's table in the same commit.
# =============================================================================
run_case "GAP: variable indirection (assignment value is discarded)"    0 'F=~/.zshrc; cat "$F"'
run_case "GAP: a path built by expansion is not a literal token"        0 'SUF=rc; cat ~/.zsh$SUF'
run_case "GAP: export -p dumps the environment"                         0 'export -p'
run_case "GAP: declare -p dumps the environment"                        0 'declare -p'
run_case "GAP: bare set dumps the environment"                          0 'set'
run_case "GAP: env -0 takes an argument, so it is not 'bare'"           0 'env -0'
run_case "GAP: printenv -0 takes an argument"                           0 'printenv -0'
run_case "GAP: ps eww shows another process's environment"             0 'ps eww 1234'
run_case "GAP: a secret read inside a script file is invisible"         0 'bash diagnose.sh'

# ---------------------------------------------------------------------------
# GAP: the real rule is "the path is the SUFFIX of a lexed token", not "any
# mention". A path inside an interpreter/remote string is one token WITH the
# path at its end, so it blocks -- add anything after it and the token no
# longer ends there, so it allows. Found by the observability judge (round 2)
# and reproduced; pre-existing, not introduced by the carve-out removal.
# These pin the boundary so the strong wording elsewhere cannot drift away
# from it silently.
# ---------------------------------------------------------------------------
run_case_msg "control: path at the END of a -c string -> blocks"        2 '.zshrc' 'bash -c "cat ~/.zshrc"'
run_case "GAP: anything after the path in a -c string -> allows"        0 'bash -c "cat ~/.zshrc | head -5"'
run_case "GAP: a path mid-string in a remote command -> allows"         0 'ssh host "cat ~/.zshrc; true"'
run_case "GAP: a path inside a python -c open() call -> allows"         0 "python3 -c \"print(open('/Users/m/.zshrc').read())\""
run_case "GAP: a non-dotfile secrets file (prod.env) is out of scope"   0 'cat config/prod.env'

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
