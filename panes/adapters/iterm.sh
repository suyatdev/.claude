#!/usr/bin/env bash
# iTerm2 adapter — open_pane <title> <launcher-path>; prints the new session id.
#
# Requires a one-time macOS Automation grant (System Settings > Privacy &
# Security > Automation); a missing grant surfaces as osascript failure and the
# caller writes the cooldown flag — degrade, never block. Interpolating title
# and launcher into the AppleScript source is safe ONLY because
# validate_open_pane_args pins title to [A-Za-z0-9 ._:-] (no quotes or
# backslashes) and the launcher to the state-dir path shape.
set -u
OSASCRIPT_BIN="/usr/bin/osascript"
# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

[ "${1:-}" = "open_pane" ] || { printf 'usage: iterm.sh open_pane <title> <launcher>\n' >&2; exit 64; }
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
)

if [ "${PANE_DRYRUN:-}" = "1" ]; then
  printf 'DRYRUN: %s -e <<EOF\n%s\nEOF\n' "$OSASCRIPT_BIN" "$osa_script"
  exit 0
fi

if ! ref=$("$OSASCRIPT_BIN" -e "$osa_script" 2>&1); then
  printf 'iterm: osascript failed (Automation grant missing?): %s\n' "$ref" >&2; exit 1
fi
printf '%s\n' "$ref"
