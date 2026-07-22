#!/usr/bin/env bash
# run-pane-agent.sh — the process a pane runs (started by a generated launcher).
#
# Executes the agent headlessly and writes the result file per the spec's
# contract: body = jq-extracted .result of the CLI JSON envelope; when the run
# fails OR the envelope doesn't parse, body = raw stdout + a stderr tail and
# the status is FAILED (fail closed — an unreadable success is not a success).
# Final line is exactly "PANE_RESULT: DONE" or "PANE_RESULT: FAILED"; the write
# is atomic (temp + mv in the result file's own directory, same filesystem).
#
# Usage: run-pane-agent.sh <agent-type> <prompt-file> <result-file> <cwd>
set -u
umask 077

CLAUDE_BIN="${PANE_CLAUDE_BIN:-$HOME/.local/bin/claude}"
JQ_BIN="/usr/bin/jq"
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
STDERR_TAIL_LINES=20

agent_type="${1:-}"; prompt_file="${2:-}"; result_file="${3:-}"; run_cwd="${4:-}"
if [ -z "$agent_type" ] || [ -z "$prompt_file" ] || [ -z "$result_file" ] || [ -z "$run_cwd" ]; then
  printf 'usage: run-pane-agent.sh <agent-type> <prompt-file> <result-file> <cwd>\n' >&2
  exit 64
fi

write_result() { # $1 body, $2 DONE|FAILED — atomic
  local tmp
  tmp="$(mktemp "$(dirname "$result_file")/.pane-result.XXXXXX")" || return 1
  { printf '%s\n' "$1"; printf 'PANE_RESULT: %s\n' "$2"; } > "$tmp"
  mv -f "$tmp" "$result_file"
}

fail_early() { # a failure before the agent could even start still honors the contract
  write_result "run-pane-agent: $1" FAILED
  printf 'run-pane-agent: %s\n' "$1" >&2
  exit 1
}

printf '=== pane agent: %s ===\ncwd:    %s\nresult: %s\n\n' "$agent_type" "$run_cwd" "$result_file"

[ -r "$prompt_file" ] || fail_early "prompt file unreadable: $prompt_file"
cd "$run_cwd" || fail_early "cannot cd to $run_cwd"

# Recursion guard: the pane session must not re-trigger the pane hooks or the
# handoff hooks (spec error table). Exported here so it reaches the claude child.
export CLAUDE_PANE_AGENT=1

tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
trap 'rm -f "$tmp_out" "$tmp_err"' EXIT

status=DONE
# No --bare (spec: it disables hooks/CLAUDE.md and breaks OAuth auth).
# --dangerously-skip-permissions matches the machine-wide posture (shell alias +
# cmux launch argv); without it a headless run auto-denies non-allowlisted tool
# calls and the agent dies mid-task. It skips prompts, not hooks.
"$CLAUDE_BIN" -p "$(cat "$prompt_file")" --agent "$agent_type" \
  --output-format json --dangerously-skip-permissions \
  > "$tmp_out" 2> "$tmp_err" || status=FAILED

body=""
if [ "$status" = DONE ]; then
  body="$("$JQ_BIN" -er '.result' "$tmp_out" 2>/dev/null)" || status=FAILED
fi
if [ "$status" = FAILED ]; then
  body="$(cat "$tmp_out"; printf '\n--- stderr tail ---\n'; tail -n "$STDERR_TAIL_LINES" "$tmp_err")"
fi

write_result "$body" "$status" || fail_early "cannot write result file: $result_file"

# Layout-v2 completion marker: written ONLY after a successful result write, so
# a fail_early run leaves no marker and its pane is never auto-reused (spec:
# the error pane is preserved for post-mortem). Run dir comes from the prompt
# file's directory with a shape guard — never trust it blindly. `cd`+`pwd`
# normalizes first, so the guard tests a resolved absolute path and a caller
# path laced with `../` cannot sneak past it.
marker_dir="$(cd "$(dirname "$prompt_file")" 2>/dev/null && pwd)" || marker_dir=""
case "$marker_dir" in
  # stderr redirect goes FIRST: a failing `> file` is reported by the shell
  # before a trailing 2>/dev/null would apply, and our breadcrumb is the one
  # message worth printing.
  */runs/*) printf '%s\n' "$status" 2>/dev/null > "$marker_dir/agent-exit" \
              || printf 'run-pane-agent: could not write agent-exit marker\n' >&2 ;;
esac

# cmux niceties, best-effort: unblock any `wait` using wait-for, then notify.
if [ -n "${CMUX_SURFACE_ID:-}" ] && [ -x "$CMUX_BIN" ]; then
  "$CMUX_BIN" wait-for -S "pane-$(basename "$result_file")" >/dev/null 2>&1 || true
  "$CMUX_BIN" notify --title "pane agent: $status" --body "$agent_type" >/dev/null 2>&1 || true
fi

printf '\n=== %s — result written to %s ===\n' "$status" "$result_file"
[ "$status" = DONE ]
