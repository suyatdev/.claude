#!/usr/bin/env bash
# dispatch-pane-agent.sh — entry point for pane orchestration.
#
#   dispatch <agent-type> --prompt-file <f> [--result-file <f>] [--cwd <dir>]
#   wait --result-file <f> [--timeout <secs>]
#   handoff [--cwd <dir>]
#
# Design: docs/superpowers/specs/2026-07-20-pane-orchestration-design.md.
# Degrades, never blocks: one adapter failure writes a per-session cooldown
# flag (keyed by $CLAUDE_CODE_SESSION_ID — the dispatcher is not a hook, so it
# has no stdin session_id; pane-dispatch-guard.sh checks both sources) and the
# guard then allows in-process dispatch for the rest of the session.
set -u
umask 077

PANES_DIR="${PANE_HOME:-$HOME/.claude/panes}"
STATE_DIR="${PANE_STATE_DIR:-$PANES_DIR/state}"
ADAPTERS_DIR="${PANE_ADAPTERS_DIR:-$PANES_DIR/adapters}"
DETECT="${PANE_TERMINAL_DETECT:-$PANES_DIR/terminal-detect.sh}"
RUNS_DIR="$STATE_DIR/runs"
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
STALE_DAYS=7
DEFAULT_TIMEOUT=900
POLL_SECS=2
CMUX_WAIT_SECS=15
AGENT_TYPE_RE='^[A-Za-z0-9_-]{1,64}$'
TIMEOUT_RE='^[0-9]+$'

die() { printf 'dispatch-pane-agent: %s\n' "$1" >&2; exit "${2:-64}"; }

# Housekeeping decision (obs r2 residual 2): state older than STALE_DAYS is
# deleted on every invocation — nothing legitimate lives in state for a week.
cleanup_stale() {
  [ -d "$STATE_DIR" ] || return 0
  find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$STALE_DAYS" -exec rm -rf {} + 2>/dev/null
  find "$STATE_DIR" -maxdepth 1 -type f -mtime +"$STALE_DAYS" -delete 2>/dev/null
  return 0
}

# Unique under concurrent dispatches (obs r2 residual 5): epoch-pid-random,
# and mkdir itself is the atomic uniqueness check — collision retries.
new_run_dir() {
  local i run_id
  for i in 1 2 3 4 5; do
    run_id="$(date +%s)-$$-$RANDOM"
    if mkdir "$RUNS_DIR/$run_id" 2>/dev/null; then printf '%s\n' "$RUNS_DIR/$run_id"; return 0; fi
    sleep 0."$i"
  done
  return 1
}

sanitize_title() { printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._:-' | cut -c1-64; }

# Default result location per spec: the session scratchpad's pane-results/.
# Derivable because the scratchpad path ends .../<session-id>/scratchpad and
# CLAUDE_CODE_SESSION_ID matches that segment (verified 2026-07-21).
scratchpad_dir() {
  local sid="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$sid" ] || return 0
  find "/private/tmp/claude-$(id -u)" -maxdepth 3 -type d -path "*/$sid/scratchpad" 2>/dev/null | head -n 1
}

open_pane_or_cooldown() { # $1 title, $2 launcher — prints TERMINAL/PANE_REF
  local term ref sid
  term="$("$DETECT" 2>/dev/null)" || term=none
  if [ "$term" = "none" ] || [ ! -x "$ADAPTERS_DIR/$term.sh" ]; then
    die "no supported terminal ('$term') — dispatch in-process via the Agent tool instead" 3
  fi
  if ! ref="$("$ADAPTERS_DIR/$term.sh" open_pane "$1" "$2")"; then
    sid="${CLAUDE_CODE_SESSION_ID:-nosession}"
    : > "$STATE_DIR/adapter-failed-$sid"
    die "adapter '$term' failed; cooldown flag written — in-process dispatch is allowed for the rest of this session" 4
  fi
  printf 'TERMINAL: %s\nPANE_REF: %s\n' "$term" "$ref"
}

cmd="${1:-}"
[ $# -ge 1 ] && shift

case "$cmd" in
  dispatch)
    agent_type="${1:-}"
    # shellcheck disable=SC2015 # non-empty agent_type guarantees $1 exists, so shift never fails into die
    [ -n "$agent_type" ] && shift || die "usage: dispatch <agent-type> --prompt-file <f> [--result-file <f>] [--cwd <dir>]"
    prompt_file=""; result_file=""; run_cwd="$PWD"
    while [ $# -gt 0 ]; do
      case "$1" in
        --prompt-file) [ $# -ge 2 ] || die "--prompt-file needs a value"; prompt_file="$2"; shift 2 ;;
        --result-file) [ $# -ge 2 ] || die "--result-file needs a value"; result_file="$2"; shift 2 ;;
        --cwd)         [ $# -ge 2 ] || die "--cwd needs a value";         run_cwd="$2";     shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    [[ "$agent_type" =~ $AGENT_TYPE_RE ]] || die "agent-type must match [A-Za-z0-9_-]{1,64}"
    { [ -f "$prompt_file" ] && [ -r "$prompt_file" ]; } || die "--prompt-file missing or unreadable: $prompt_file"
    [ -d "$run_cwd" ] || die "--cwd is not an existing directory: $run_cwd"
    run_cwd="$(cd "$run_cwd" && pwd)" || die "cannot resolve --cwd"

    # Canonicalize a user-supplied --result-file to an absolute path against the
    # caller's CWD, the same way --cwd is resolved above (obs final-review F4).
    # A relative path would otherwise resolve against three different CWDs in the
    # dispatcher, the runner, and wait. The default path (computed below) is
    # already absolute, so this only touches an explicit --result-file.
    if [ -n "$result_file" ]; then
      rf_parent="$(dirname "$result_file")"
      rf_abs_parent="$(cd "$rf_parent" 2>/dev/null && pwd)" || die "result-file directory does not exist: $rf_parent"
      result_file="$rf_abs_parent/$(basename "$result_file")"
    fi

    mkdir -p "$RUNS_DIR"
    cleanup_stale
    run_dir="$(new_run_dir)" || die "could not create a unique run dir under $RUNS_DIR"

    if [ -z "$result_file" ]; then
      scratch="$(scratchpad_dir)"
      if [ -n "$scratch" ] && [ -d "$scratch" ]; then
        mkdir -p "$scratch/pane-results"
        # Unique per dispatch (obs final-review F1): epoch-pid-random, the same
        # recipe new_run_dir uses — two same-type dispatches in one second must
        # not collide onto one file that both runners would mv over.
        result_file="$scratch/pane-results/$agent_type-$(date +%s)-$$-$RANDOM.md"
      else
        result_file="$run_dir/result.md"
      fi
    fi
    [ -e "$result_file" ] && die "refusing to reuse an existing result file: $result_file" 65
    [ -d "$(dirname "$result_file")" ] || die "result-file directory does not exist: $(dirname "$result_file")"

    cp "$prompt_file" "$run_dir/prompt.md" || die "cannot copy prompt into run dir"

    # The launcher is the injection boundary's controlled token: %q-quoted args,
    # mode 700, inside the 700 run dir (prompt lives there too). It keeps the
    # pane open after the agent exits by dropping into an interactive shell.
    launcher="$run_dir/launch.sh"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'bash %q %q %q %q %q\n' "$PANES_DIR/run-pane-agent.sh" "$agent_type" "$run_dir/prompt.md" "$result_file" "$run_cwd"
      printf 'echo; echo "[pane kept open for inspection -- agent exit $?]"\n'
      printf 'exec /bin/zsh -i\n'
    } > "$launcher"
    chmod 700 "$launcher"

    open_pane_or_cooldown "$(sanitize_title "pane: $agent_type")" "$launcher"
    printf 'RESULT_FILE: %s\n' "$result_file"
    ;;

  wait)
    result_file=""; timeout="$DEFAULT_TIMEOUT"
    while [ $# -gt 0 ]; do
      case "$1" in
        --result-file) [ $# -ge 2 ] || die "--result-file needs a value"; result_file="$2"; shift 2 ;;
        --timeout)     [ $# -ge 2 ] || die "--timeout needs a value";     timeout="$2";     shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    [ -n "$result_file" ] || die "wait needs --result-file"
    [[ "$timeout" =~ $TIMEOUT_RE ]] || die "--timeout must be a whole number of seconds"
    deadline=$(( $(date +%s) + timeout ))
    while :; do
      if [ -f "$result_file" ]; then
        last="$(tail -n 1 "$result_file")"
        case "$last" in
          'PANE_RESULT: DONE')   cat "$result_file"; exit 0 ;;
          'PANE_RESULT: FAILED') cat "$result_file"; exit 1 ;;
        esac
      fi
      if [ "$(date +%s)" -ge "$deadline" ]; then
        printf 'dispatch-pane-agent: wait timed out after %ss (%s); the pane stays open for post-mortem\n' "$timeout" "$result_file" >&2
        exit 2
      fi
      # Latency nicety per spec: block on cmux wait-for (runner signals it)
      # instead of a fixed sleep; correctness still comes from the file check.
      if [ -n "${CMUX_PANEL_ID:-}" ] && [ -x "$CMUX_BIN" ]; then
        # If cmux wait-for fails fast, fall back to the fixed poll interval so
        # the loop cannot hot-spin (obs final-review F3); the file check below
        # stays authoritative either way.
        "$CMUX_BIN" wait-for "pane-$(basename "$result_file")" --timeout "$CMUX_WAIT_SECS" >/dev/null 2>&1 || sleep "$POLL_SECS"
      else
        sleep "$POLL_SECS"
      fi
    done
    ;;

  handoff)
    run_cwd="$PWD"
    while [ $# -gt 0 ]; do
      case "$1" in
        --cwd) [ $# -ge 2 ] || die "--cwd needs a value"; run_cwd="$2"; shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    [ -d "$run_cwd" ] || die "--cwd is not an existing directory: $run_cwd"
    run_cwd="$(cd "$run_cwd" && pwd)" || die "cannot resolve --cwd"
    mkdir -p "$RUNS_DIR"
    cleanup_stale
    run_dir="$(new_run_dir)" || die "could not create a unique run dir under $RUNS_DIR"
    launcher="$run_dir/launch.sh"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'bash %q %q\n' "$PANES_DIR/handoff-wrapper.sh" "$run_cwd"
      printf 'exec /bin/zsh -i\n'
    } > "$launcher"
    chmod 700 "$launcher"
    open_pane_or_cooldown "$(sanitize_title "handoff: press Enter")" "$launcher"
    ;;

  *)
    die "usage: dispatch-pane-agent.sh {dispatch|wait|handoff} ..." ;;
esac
