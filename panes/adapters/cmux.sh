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

# The text `send` delivers has SHELL semantics (probe P4: `&&` chained, a
# redirection ran, 'A B' survived as one argument), and
# validate_open_pane_args constrains only the run-id segment — the state-root
# prefix is interpolated from $PANE_STATE_DIR/$HOME verbatim, so a home like
# "/Users/Mark Suyat" yields an ACCEPTED launcher path containing a space
# (verified), and the unescaped "." in that interpolated regex admits one
# arbitrary character per dot position. %q leaves an ordinary path
# byte-identical to the v1-proven form and escapes only when it must.
launcher_q="$(printf '%q' "$launcher")"

# Raw tree of the current derivation, kept for verify-after-rename's before/
# after differential. Empty = no usable tree this run (already degraded).
TREE_RAW=""

fetch_tree() { # stdout: raw tree JSON; non-zero = Tier-1 degrade
  [ -x "$JQ_BIN" ] || { degraded "jq missing"; return 1; }
  local tree
  # A BARE tree is WINDOW-scoped, not workspace-scoped (probe P1 returned five
  # workspaces live), so an unscoped fetch would classify foreign panes from
  # other workspaces and place implementers against them. Scoping is therefore
  # server-side; layout_normalize_tree's client-side filter is only
  # defence-in-depth. Flags go AFTER the subcommand so `tree` stays the first
  # non-flag argument.
  tree="$("$CMUX_BIN" --json tree ${WS_ARGS[@]+"${WS_ARGS[@]}"} </dev/null 2>/dev/null)" \
    || { degraded "tree call failed"; return 1; }
  printf '%s' "$tree" | "$JQ_BIN" -e . >/dev/null 2>&1 || { degraded "tree unparseable"; return 1; }
  printf '%s' "$tree"
}

decide_plan() { # tree JSON on stdin -> PLAN:+TITLE:; non-zero = Tier-1 degrade
  local out
  out="$(layout_decide "$role" "$run_id" "$title")" || { degraded "derivation failed"; return 1; }
  printf '%s\n' "$out" | grep -q '^PLAN: ' || { degraded "derivation nonsense"; return 1; }
  printf '%s\n' "$out"
}

derive_plan() { # fetch + decide in one shot — the dryrun preview's composition
  local tree
  tree="$(fetch_tree)" || return 1
  printf '%s' "$tree" | decide_plan
}

send_launcher() { # $1 surface ref -> 0 sent, non-zero not sent
  "$CMUX_BIN" send ${WS_ARGS[@]+"${WS_ARGS[@]}"} --surface "$1" -- "bash $launcher_q\n" >/dev/null
}

# $1 surface ref, $2 composed title. Stamps the title, then VERIFIES it landed.
# rename-tab resolves --tab -> --surface -> $CMUX_TAB_ID/$CMUX_SURFACE_ID -> the
# FOCUSED tab, and an unresolvable ref falls through that chain WITHOUT erroring
# (probe P6, proven live against surface:9999 at exit 0). A surface closing
# between the tree fetch and the rename therefore stamps a managed title onto an
# INNOCENT surface — corrupting the layout state machine and potentially
# branding the user's own main session. Plain retry cannot help: the failure is
# silent and already committed by the time it is observable. So: one extra tree
# read, and a mis-target is repaired best-effort. Bounded — no loop, no
# recursion, and the repair rename rides the same fallback chain, so it is
# attempted once and deliberately NOT verified. A rename fault is never fatal:
# the send has already happened and the agent is live in that surface (Tier 1).
stamp_title() {
  local after pre victim prev vpane vref vtitle
  "$CMUX_BIN" rename-tab ${WS_ARGS[@]+"${WS_ARGS[@]}"} --surface "$1" -- "$2" >/dev/null 2>&1 \
    || { printf 'cmux: rename failed; surface stays unmanaged\n' >&2; return 0; }
  [ -n "$TREE_RAW" ] || return 0
  after="$(fetch_tree 2>/dev/null | layout_normalize_tree)"
  [ -n "$after" ] || { printf 'cmux: rename unverifiable (no tree); %s may be unmanaged\n' "$1" >&2; return 0; }
  printf '%s\n' "$after" | awk -F'\t' -v s="$1" -v t="$2" '$2==s && $3==t {f=1} END {exit !f}' && return 0

  # Mis-targeted. The victim is a surface that NOW carries the composed title but
  # carried a DIFFERENT one before the rename — that differential is what keeps a
  # surface legitimately holding this title from being "repaired" away.
  pre="$(printf '%s' "$TREE_RAW" | layout_normalize_tree)"
  victim=""; prev=""
  while IFS=$'\t' read -r vpane vref vtitle || [ -n "$vpane" ]; do
    if [ "$vtitle" != "$2" ] || [ "$vref" = "$1" ]; then continue; fi
    prev="$(printf '%s\n' "$pre" | awk -F'\t' -v v="$vref" '$2==v {print $3; exit}')"
    if [ -n "$prev" ] && [ "$prev" != "$2" ]; then victim="$vref"; break; fi
    prev=""
  done <<< "$after"

  if [ -n "$victim" ]; then
    "$CMUX_BIN" rename-tab ${WS_ARGS[@]+"${WS_ARGS[@]}"} --surface "$victim" -- "$prev" >/dev/null 2>&1 || true
    printf 'cmux: rename MIS-TARGETED (probe P6): %s stays unmanaged; restored %s to "%s"\n' "$1" "$victim" "$prev" >&2
  else
    printf 'cmux: rename MIS-TARGETED (probe P6): %s stays unmanaged; no repairable victim found\n' "$1" >&2
  fi
}

finish_surface() { # $1 surface ref, $2 title — send launcher, stamp, print ref
  send_launcher "$1" || { printf 'cmux: send failed for %s\n' "$1" >&2; exit 1; }
  # The managed title is load-bearing; if the stamp fails the surface is just
  # unmanaged (extra splits later at worst) — note it, never die for it.
  stamp_title "$1" "$2"
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

json_ref() { "$JQ_BIN" -er '.surface_ref' 2>/dev/null; }   # stdin: --json output

# $1.. subcommand + its positionals + flags -> prints the created surface ref.
# --workspace is APPENDED here rather than written at each call site, so no site
# can forget it (probe P5: a ref with no workspace context is not_found) and
# positionals stay adjacent to their subcommand. Flag order is immaterial — P5
# proved `--pane <ref> --workspace <ws>`, P6 the reverse.
split_capture() {
  local out ref
  out="$("$CMUX_BIN" --json "$@" ${WS_ARGS[@]+"${WS_ARGS[@]}"} </dev/null 2>/dev/null)" || return 1
  ref="$(printf '%s' "$out" | json_ref)" || return 1
  # `jq -e` only rejects null/false, so an empty or pane-shaped ref would reach
  # `send --surface` blind. Shape-checked exactly as legacy_open checks its own.
  case "$ref" in surface:*) ;; *) return 1 ;; esac
  printf '%s\n' "$ref"
}

execute_plan() { # $1 "PLAN: ..." line, $2 composed title. rc 1 = retryable
  local verb rest ref dir target
  verb="$(printf '%s' "$1" | awk '{print $2}')"
  rest="$(printf '%s' "$1" | cut -d' ' -f3-)"
  case "$verb" in
    reuse)
      # NOT the respawn subcommand: probe P4 found it replaces the surface's
      # process and the surface closes when that process exits — live, it
      # destroyed surface:67 and took its last-surface pane with it, so
      # respawning to reuse destroys the very thing being reused. Reuse
      # types into the surviving shell with `send`, which is v1-proven here
      # (user-approved deviation 2026-07-21; the spec's intent is unchanged).
      # A failing send is RETRYABLE, not Tier 2 — nothing was created, the
      # target just vanished.
      send_launcher "$rest" || return 1
      stamp_title "$rest" "$2"
      printf '%s\n' "$rest"
      ;;
    split)
      dir="${rest%% *}"; target="${rest#* }"
      if [ "$target" = env ]; then ref="$(split_capture new-split "$dir")" || return 1
      else ref="$(split_capture new-split "$dir" --surface "$target")" || return 1; fi
      finish_surface "$ref" "$2"
      ;;
    tab)
      ref="$(split_capture new-surface --pane "$rest")" || return 1
      finish_surface "$ref" "$2"
      ;;
    aux-create)
      # Primary: full-height right column (probe P3 confirmed the geometry);
      # fallback: split right of a right-column slot (imperfect geometry, still
      # functional); last: let cmux target env-implicitly from main.
      if ref="$(split_capture new-pane --direction right)"; then :
      elif [ "$rest" = env ]; then ref="$(split_capture new-split right)" || return 1
      else ref="$(split_capture new-split right --surface "$rest")" || return 1; fi
      finish_surface "$ref" "$2"
      ;;
    *) return 1 ;;
  esac
}

# Derive -> execute. A vanished target (TOCTOU) earns exactly ONE fresh
# derivation, then the legacy floor. Tier-2 failures inside finish_surface/
# legacy_open exit 1 directly — they are not retried (spec error table).
attempt=1
while :; do
  TREE_RAW="$(fetch_tree)" || { legacy_open; exit 0; }
  plan_out="$(printf '%s' "$TREE_RAW" | decide_plan)" || { legacy_open; exit 0; }
  plan_line="$(printf '%s\n' "$plan_out" | grep '^PLAN: ' | head -n 1)"
  composed="$(printf '%s\n' "$plan_out" | sed -n 's/^TITLE: //p' | head -n 1)"
  [ -n "$composed" ] || composed="$title"
  execute_plan "$plan_line" "$composed" && exit 0
  if [ "$attempt" -eq 1 ]; then
    attempt=2
    degraded "plan target vanished; re-deriving once"
    continue
  fi
  degraded "execution failed twice"
  legacy_open
  exit 0
done
