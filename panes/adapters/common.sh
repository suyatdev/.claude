#!/usr/bin/env bash
# common.sh — shared adapter validation. Sourced by each adapter, never executed.
#
# Adapters are the injection boundary (spec: "Injection rule"): they must hold
# even if a future caller bypasses the dispatcher, so each adapter re-validates
# its two inputs instead of trusting the caller's sanitization. PANE_STATE_DIR
# is overridable for tests only; a caller who controls the environment already
# controls the process, so the override is not a boundary weakening.
#
# validate_open_pane_args <title> <launcher-path>  -> 0 ok, 1 reject (reason on stderr)
validate_open_pane_args() {
  local title="$1" launcher="$2"
  local state_root="${PANE_STATE_DIR:-$HOME/.claude/panes/state}"
  local title_re='^[A-Za-z0-9 ._:-]{1,64}$'
  local launcher_re="^${state_root}/runs/[A-Za-z0-9-]+/launch\.sh$"
  if ! [[ "$title" =~ $title_re ]]; then
    printf 'adapter: title outside allowlist [A-Za-z0-9 ._:-] (max 64)\n' >&2; return 1
  fi
  if ! [[ "$launcher" =~ $launcher_re ]]; then
    printf 'adapter: launcher path outside %s/runs/\n' "$state_root" >&2; return 1
  fi
  if [ ! -f "$launcher" ]; then
    printf 'adapter: launcher does not exist: %s\n' "$launcher" >&2; return 1
  fi
}

# validate_open_tab_args <surface-ref> <title> <launcher-path> -> 0 ok, 1 reject.
# The surface-ref is a NEW caller-supplied token crossing into adapter command
# lines; pin it to a strict allowlist covering every adapter's ref shape
# (surface:99, %3, a UUID, window-123) with no spaces/quotes/shell metacharacters.
# Title + launcher reuse the open_pane boundary exactly.
validate_open_tab_args() {
  local ref="$1" title="$2" launcher="$3"
  local ref_re='^[A-Za-z0-9:%_.-]{1,64}$'
  if ! [[ "$ref" =~ $ref_re ]]; then
    printf 'adapter: surface-ref outside allowlist [A-Za-z0-9:%%_.-] (max 64)\n' >&2; return 1
  fi
  validate_open_pane_args "$title" "$launcher"
}
