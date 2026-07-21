#!/usr/bin/env bash
# cmux adapter — open_pane <title> <launcher-path>; prints the new surface ref.
#
# Verified live 2026-07-21 from a non-TTY process: `new-split down` targets the
# calling workspace via $CMUX_WORKSPACE_ID/$CMUX_SURFACE_ID in the environment
# and prints "OK surface:N workspace:M" — the ref is field 2. The launcher is
# started by typing into the fresh pane's shell (`cmux send`); only the
# validated launcher path is ever interpolated. rename-tab is cosmetic and
# never fatal.
set -u
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
# shellcheck source=/dev/null
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

[ "${1:-}" = "open_pane" ] || { printf 'usage: cmux.sh open_pane <title> <launcher>\n' >&2; exit 64; }
title="${2:-}"; launcher="${3:-}"
validate_open_pane_args "$title" "$launcher" || exit 65

if [ "${PANE_DRYRUN:-}" = "1" ]; then
  printf 'DRYRUN: %s new-split down\n' "$CMUX_BIN"
  printf 'DRYRUN: %s send --surface <ref> -- "bash %s\\n"\n' "$CMUX_BIN" "$launcher"
  printf 'DRYRUN: %s rename-tab --surface <ref> -- "%s"\n' "$CMUX_BIN" "$title"
  exit 0
fi

out=$("$CMUX_BIN" new-split down </dev/null 2>&1) || { printf 'cmux: new-split failed: %s\n' "$out" >&2; exit 1; }
ref=$(printf '%s' "$out" | awk '$1=="OK"{print $2}')
case "$ref" in
  surface:*) ;;
  *) printf 'cmux: unexpected new-split output: %s\n' "$out" >&2; exit 1 ;;
esac
"$CMUX_BIN" send --surface "$ref" -- "bash $launcher\n" >/dev/null \
  || { printf 'cmux: send failed for %s\n' "$ref" >&2; exit 1; }
"$CMUX_BIN" rename-tab --surface "$ref" -- "$title" >/dev/null 2>&1 || true
printf '%s\n' "$ref"
