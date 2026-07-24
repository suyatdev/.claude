#!/usr/bin/env bash
# tmux adapter — open_pane <title> <launcher-path> | open_tab <surface-ref>
# <title> <launcher-path>; prints the new pane id.
# -d keeps focus on the caller's pane; -P -F prints the ref. The pane title is
# set via select-pane -T (tmux >= 3.0), cosmetic and never fatal.
set -u
TMUX_BIN="/opt/homebrew/bin/tmux"
# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

verb="${1:-}"
case "$verb" in
  open_pane)
    title="${2:-}"; launcher="${3:-}"
    validate_open_pane_args "$title" "$launcher" || exit 65
    if [ "${PANE_DRYRUN:-}" = "1" ]; then
      printf 'DRYRUN: %s split-window -d -P -F #{pane_id} "bash %s"\n' "$TMUX_BIN" "$launcher"
      printf 'DRYRUN: %s select-pane -t <ref> -T "%s"\n' "$TMUX_BIN" "$title"; exit 0
    fi
    ref=$("$TMUX_BIN" split-window -d -P -F '#{pane_id}' "bash $launcher") \
      || { printf 'tmux: split-window failed\n' >&2; exit 1; }
    "$TMUX_BIN" select-pane -t "$ref" -T "$title" 2>/dev/null || true
    printf '%s\n' "$ref" ;;
  open_tab)
    ref_in="${2:-}"; title="${3:-}"; launcher="${4:-}"
    validate_open_tab_args "$ref_in" "$title" "$launcher" || exit 65
    # tmux "tab" = a new window (the surface ref is not needed to place it; it is
    # validated for contract uniformity and audit only).
    if [ "${PANE_DRYRUN:-}" = "1" ]; then
      printf 'DRYRUN: %s new-window -d -P -F #{pane_id} "bash %s"\n' "$TMUX_BIN" "$launcher"
      printf 'DRYRUN: %s select-pane -t <ref> -T "%s"\n' "$TMUX_BIN" "$title"; exit 0
    fi
    ref=$("$TMUX_BIN" new-window -d -P -F '#{pane_id}' "bash $launcher") \
      || { printf 'tmux: new-window failed\n' >&2; exit 1; }
    "$TMUX_BIN" select-pane -t "$ref" -T "$title" 2>/dev/null || true
    printf '%s\n' "$ref" ;;
  *) printf 'usage: tmux.sh {open_pane|open_tab} ...\n' >&2; exit 64 ;;
esac
