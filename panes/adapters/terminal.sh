#!/usr/bin/env bash
# Terminal.app adapter — open_pane <title> <launcher-path>. Terminal.app has no
# splits; a new tab is the honest best (spec). `do script` returns a tab whose
# custom title we set; the printed ref is the front window id (informational
# only — nothing consumes refs programmatically). Same interpolation-safety
# argument as iterm.sh: inputs are allowlist-validated first.
set -u
OSASCRIPT_BIN="/usr/bin/osascript"
# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

[ "${1:-}" = "open_pane" ] || { printf 'usage: terminal.sh open_pane <title> <launcher>\n' >&2; exit 64; }
title="${2:-}"; launcher="${3:-}"
validate_open_pane_args "$title" "$launcher" || exit 65

osa_script=$(cat <<EOF
tell application "Terminal"
  set newTab to do script "bash $launcher"
  set custom title of newTab to "$title"
  return id of front window
end tell
EOF
)

if [ "${PANE_DRYRUN:-}" = "1" ]; then
  printf 'DRYRUN: %s -e <<EOF\n%s\nEOF\n' "$OSASCRIPT_BIN" "$osa_script"
  exit 0
fi

if ! ref=$("$OSASCRIPT_BIN" -e "$osa_script" 2>&1); then
  printf 'terminal: osascript failed: %s\n' "$ref" >&2; exit 1
fi
printf 'window-%s\n' "$ref"
