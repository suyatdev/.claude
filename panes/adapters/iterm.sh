#!/usr/bin/env bash
# iTerm2 adapter — open_pane <title> <launcher-path> | open_tab <surface-ref>
# <title> <launcher-path>; prints the new session id.
#
# Requires a one-time macOS Automation grant (System Settings > Privacy &
# Security > Automation); a missing grant surfaces as osascript failure and the
# caller writes the cooldown flag — degrade, never block. Interpolating title
# and launcher into the AppleScript source is safe ONLY because
# validate_open_pane_args / validate_open_tab_args pin title to
# [A-Za-z0-9 ._:-] (no quotes or backslashes) and the launcher to the
# state-dir path shape.
set -u
OSASCRIPT_BIN="/usr/bin/osascript"
# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

verb="${1:-}"
case "$verb" in
  open_pane)
    title="${2:-}"; launcher="${3:-}"
    validate_open_pane_args "$title" "$launcher" || exit 65
    osa_script=$(cat <<EOF
tell application "iTerm2"
  tell current session of current window
    set newSession to (split horizontally with default profile command "bash $launcher")
  end tell
  tell newSession to set name to "$title"
  return id of newSession
end tell
EOF
) ;;
  open_tab)
    ref_in="${2:-}"; title="${3:-}"; launcher="${4:-}"
    validate_open_tab_args "$ref_in" "$title" "$launcher" || exit 65
    # iTerm tabs are window-level; the surface ref is validated for contract
    # uniformity and audit only.
    osa_script=$(cat <<EOF
tell application "iTerm2"
  tell current window
    set newTab to (create tab with default profile command "bash $launcher")
  end tell
  tell current session of newTab to set name to "$title"
  return id of current session of newTab
end tell
EOF
) ;;
  *) printf 'usage: iterm.sh {open_pane|open_tab} ...\n' >&2; exit 64 ;;
esac

if [ "${PANE_DRYRUN:-}" = "1" ]; then
  printf 'DRYRUN: %s -e <<EOF\n%s\nEOF\n' "$OSASCRIPT_BIN" "$osa_script"
  exit 0
fi

if ! ref=$("$OSASCRIPT_BIN" -e "$osa_script" 2>&1); then
  printf 'iterm: osascript failed (Automation grant missing?): %s\n' "$ref" >&2; exit 1
fi
printf '%s\n' "$ref"
