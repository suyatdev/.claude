#!/usr/bin/env bash
# cmux adapter — open_pane <title> <launcher-path>; prints the new surface ref.
#
# v2 (pane-layout): derives a structured layout (main | 2x2 implementer
# quadrant | far-right aux column) live from `cmux --json tree` plus the title
# convention in cmux-layout.sh. Layout smarts only ever fail INTO the legacy
# `new-split down` path (Tier 1: one stderr breadcrumb, exit 0, never a
# cooldown); only the legacy path itself failing exits non-zero (Tier 2 ->
# dispatcher cooldown), exactly v1's semantics. PANE_CMUX_BIN/PANE_JQ_BIN are
# test-only overrides (precedent: PANE_CLAUDE_BIN — controlling the environment
# already means controlling the process).
#
# NOT `set -e`, deliberately: cmux-layout.sh's tab-count loop runs `grep -c .`,
# which prints 0 but EXITS 1 on empty input (verified, bash 3.2.57).
set -u
CMUX_BIN="${PANE_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
JQ_BIN="${PANE_JQ_BIN:-/usr/bin/jq}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/common.sh"
# shellcheck source=/dev/null
. "$HERE/cmux-layout.sh"

[ "${1:-}" = "open_pane" ] || { printf 'usage: cmux.sh open_pane <title> <launcher>\n' >&2; exit 64; }
title="${2:-}"; launcher="${3:-}"
validate_open_pane_args "$title" "$launcher" || exit 65

degraded() { printf 'cmux-layout: degraded (%s)\n' "$1" >&2; }

# Refs resolve relative to a workspace context that defaults to
# $CMUX_WORKSPACE_ID (probe P5), so every call that names or reads one carries
# it explicitly when it is set. Never emit an empty --workspace. bash 3.2 treats
# "${arr[@]}" on an EMPTY array as an unbound variable under `set -u`, hence the
# ${arr[@]+...} guard at each use site.
WS_ARGS=()
[ -n "${CMUX_WORKSPACE_ID:-}" ] && WS_ARGS=(--workspace "$CMUX_WORKSPACE_ID")

# Role from the dispatcher; absent/unknown -> aux with a note (spec error
# table). The raw env value never reaches a command line or title.
role="${PANE_AGENT_ROLE:-}"
case "$role" in
  implementer|aux) ;;
  "") role=aux ;;
  *) printf 'cmux: unknown PANE_AGENT_ROLE -> aux\n' >&2; role=aux ;;
esac

# run-id from the already-validated launcher path .../runs/<run-id>/launch.sh;
# extraction failure -> unprefixed (unmanaged) title, dispatch proceeds.
run_id="$(basename "$(dirname "$launcher")")"
if ! [[ "$run_id" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]]; then
  printf 'cmux: no run-id in launcher path; surface will be unmanaged\n' >&2
  run_id=""
fi

derive_plan() { # stdout: PLAN:+TITLE: lines; non-zero = Tier-1 degrade
  [ -x "$JQ_BIN" ] || { degraded "jq missing"; return 1; }
  local tree out
  # A BARE tree is WINDOW-scoped, not workspace-scoped (probe P1 returned five
  # workspaces live), so an unscoped fetch would classify foreign panes from
  # other workspaces and place implementers against them. Scoping is therefore
  # server-side; layout_normalize_tree's client-side filter is only
  # defence-in-depth. Flags go AFTER the subcommand so `tree` stays the first
  # non-flag argument.
  tree="$("$CMUX_BIN" --json tree ${WS_ARGS[@]+"${WS_ARGS[@]}"} </dev/null 2>/dev/null)" \
    || { degraded "tree call failed"; return 1; }
  printf '%s' "$tree" | "$JQ_BIN" -e . >/dev/null 2>&1 || { degraded "tree unparseable"; return 1; }
  out="$(printf '%s' "$tree" | layout_decide "$role" "$run_id" "$title")" || { degraded "derivation failed"; return 1; }
  printf '%s\n' "$out" | grep -q '^PLAN: ' || { degraded "derivation nonsense"; return 1; }
  printf '%s\n' "$out"
}

finish_surface() { # $1 surface ref, $2 title — send launcher, stamp, print ref
  "$CMUX_BIN" send ${WS_ARGS[@]+"${WS_ARGS[@]}"} --surface "$1" -- "bash $launcher\n" >/dev/null \
    || { printf 'cmux: send failed for %s\n' "$1" >&2; exit 1; }
  # The managed title is load-bearing; if the stamp fails the surface is just
  # unmanaged (extra splits later at worst) — note it, never die for it.
  "$CMUX_BIN" rename-tab ${WS_ARGS[@]+"${WS_ARGS[@]}"} --surface "$1" -- "$2" >/dev/null 2>&1 \
    || printf 'cmux: rename failed; surface stays unmanaged\n' >&2
  printf '%s\n' "$1"
}

legacy_open() { # v1 behavior verbatim — the degradation floor (Tier 2 inside)
  local out ref
  # No --workspace here on purpose: new-split takes no ref, so there is nothing
  # to resolve, and this is the proven v1 floor. Do not "harmonize" it.
  out=$("$CMUX_BIN" new-split down </dev/null 2>&1) || { printf 'cmux: new-split failed: %s\n' "$out" >&2; exit 1; }
  ref=$(printf '%s' "$out" | awk '$1=="OK"{print $2}')
  case "$ref" in
    surface:*) ;;
    *) printf 'cmux: unexpected new-split output: %s\n' "$out" >&2; exit 1 ;;
  esac
  finish_surface "$ref" "$title"
}

if [ "${PANE_DRYRUN:-}" = "1" ]; then
  # Derivation is read-only, so dryrun derives the real plan when a fake cmux is
  # wired in via PANE_CMUX_BIN. The guard is on PANE_CMUX_BIN specifically and
  # NOT on "a cmux exists": adapters.test.sh never sets it and asserts the
  # legacy plan, while running on machines where the real app IS installed —
  # deriving there would break that suite and reach the user's live workspace
  # from a test. So: fake wired in -> derive; otherwise -> print the legacy plan.
  if [ -n "${PANE_CMUX_BIN:-}" ] && plan_out="$(derive_plan 2>/dev/null)"; then
    printf '%s\n' "$plan_out" | sed 's/^/DRYRUN: /'
    printf 'DRYRUN: %s send --surface <ref> -- "bash %s\\n"\n' "$CMUX_BIN" "$launcher"
  else
    printf 'DRYRUN: %s new-split down\n' "$CMUX_BIN"
    printf 'DRYRUN: %s send --surface <ref> -- "bash %s\\n"\n' "$CMUX_BIN" "$launcher"
    printf 'DRYRUN: %s rename-tab --surface <ref> -- "%s"\n' "$CMUX_BIN" "$title"
  fi
  exit 0
fi

# Task 7 replaces this stanza with plan execution + TOCTOU retry. Until then:
# derive (so Tier-1 breadcrumbs are real) and always take the legacy floor.
derive_plan >/dev/null || true
legacy_open
