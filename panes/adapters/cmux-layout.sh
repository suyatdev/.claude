#!/usr/bin/env bash
# cmux-layout.sh — pure layout decision helper, SOURCED by cmux.sh, never
# executed and never calling cmux: every function reads stdin/arguments and
# prints a result, so the whole file unit-tests against canned JSON fixtures
# (spec: Components). Layout state lives in surface titles because the cmux
# tree is flat — titles are the positional memory.
#
# Normalized form (TSV, one surface per line):  pane_ref \t surface_ref \t title
# Managed grammar (anchored; inside the frozen [A-Za-z0-9 ._:-]<=64 allowlist):
#   impl.<slot>:<run-id> <label>   slot 1-4    |   aux:<run-id> <label>

LAYOUT_JQ="${PANE_JQ_BIN:-/usr/bin/jq}"
LAYOUT_MANAGED_RE='^(impl\.([1-4])|aux):([0-9]+-[0-9]+-[0-9]+) '

# Workspace scoping is SERVER-side: the caller passes --workspace
# "$CMUX_WORKSPACE_ID" to `cmux --json tree` (probe P1 — the UUID is accepted
# directly). The prelude below is defence-in-depth for a ref-form value only.
# $CMUX_WORKSPACE_ID is a UUID (probe P7) while the tree's own refs are of the
# form workspace:8, so in live use this client-side filter will normally NOT
# match and will correctly fall through to returning everything. That fallback
# is load-bearing — without it a UUID would scope the tree down to nothing and
# the whole layout feature would silently degrade to legacy. Do not try to
# make a UUID match by rewriting it as workspace:<uuid>; that matches nothing.
#
# Spliced into every tree-reading function rather than copied, so the two
# cannot drift apart. Output is an ARRAY of documents to descend into.
# shellcheck disable=SC2016  # $ws is a jq variable bound by --arg, not a shell one
LAYOUT_JQ_WS_SCOPE='
  (if $ws != "" and ([.. | objects | select(has("panes") and .ref? == $ws)] | length) > 0
   then [.. | objects | select(has("panes") and .ref? == $ws)] else [.] end)'

# stdin: `cmux --json tree` output -> normalized TSV. Recursive descent keeps
# this resilient to wrapper objects; the live-captured fixture test pins it to
# the real 0.64.20 shape (probe P2), in which a pane keys its own ref as "ref"
# and a surface keys its own as "ref" while carrying "pane_ref" + "title".
layout_normalize_tree() {
  local ws="${CMUX_WORKSPACE_ID:-}"
  "$LAYOUT_JQ" -r --arg ws "$ws" "$LAYOUT_JQ_WS_SCOPE"'
    | [.[] | .. | objects | select(has("ref") and has("pane_ref") and has("title"))]
    | .[] | [.pane_ref, .ref, .title] | @tsv' 2>/dev/null
}

# stdin: `cmux --json tree` output -> the surface ref to anchor a far-right
# split on, or NOTHING when no pane qualifies. Same workspace scoping as
# layout_normalize_tree, including the load-bearing fallback.
#
# A pane carries an "index" and it IS left-to-right order — verified live
# 2026-07-21 by a controlled experiment: each new pane took the index matching
# its visual position (idx0 -> idx0,idx1 -> idx0,idx1,idx2). So the rightmost
# pane is the one with the MAX index. This corrects probe P3's "geometry is not
# exposed in the tree": pixel geometry is not, but ordering is, and that is all
# a far-right anchor needs. The anchor itself is the pane's
# "selected_surface_ref" — the surface it is actually showing, which is what a
# split anchors against, and a scalar, so there is no empty-array case.
#
# "index" is REQUIRED to be a number rather than defaulted: a tree without it
# yields no anchor and the caller falls back to env-implicit targeting, a
# visible degradation, instead of max_by silently ranking every pane equal and
# returning whichever happened to come last in the document.
layout_rightmost_surface() {
  local ws="${CMUX_WORKSPACE_ID:-}"
  "$LAYOUT_JQ" -r --arg ws "$ws" "$LAYOUT_JQ_WS_SCOPE"'
    | [.[] | .. | objects
       | select(has("surface_refs") and (.index | type) == "number"
                and (.selected_surface_ref | type) == "string")]
    | max_by(.index) | .selected_surface_ref // empty' 2>/dev/null
}

# stdin: normalized TSV -> managed surfaces only:
#   kind(impl|aux) \t slot(1-4|-) \t run_id \t pane_ref \t surface_ref
# Near-miss titles simply do not match — unmanaged, invisible (spec). The
# `|| [ -n "$pane" ]` guard keeps the final line when stdin lacks its trailing
# newline (command substitution strips it).
layout_managed() {
  local pane="" surface="" title=""
  while IFS=$'\t' read -r pane surface title || [ -n "$pane" ]; do
    [[ "$title" =~ $LAYOUT_MANAGED_RE ]] || continue
    if [ -n "${BASH_REMATCH[2]}" ]; then
      printf 'impl\t%s\t%s\t%s\t%s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "$pane" "$surface"
    else
      printf 'aux\t-\t%s\t%s\t%s\n' "${BASH_REMATCH[3]}" "$pane" "$surface"
    fi
  done
}

# $1 run_id -> 0 finished, 1 running. Missing run dir = finished (the 7-day
# cleanup removes old dirs; obs-judge success_masking caveat is accepted and
# recorded in the spec).
layout_run_finished() {
  local root="${PANE_STATE_DIR:-$HOME/.claude/panes/state}"
  local dir="$root/runs/$1"
  [ -d "$dir" ] || return 0
  [ -f "$dir/agent-exit" ]
}

# $1 prefix (impl.<slot>|aux), $2 run_id ("" = unmanaged), $3 label.
# Truncates from the RIGHT at 64 so the managed prefix always survives (spec).
layout_compose_title() {
  if [ -n "$2" ]; then printf '%.64s' "$1:$2 $3"; else printf '%.64s' "$3"; fi
}

# $1 role (implementer|aux), $2 run_id (may be ""), $3 label; tree JSON on
# stdin. Prints one PLAN: line and one TITLE: line (contract in the header).
# Reuse is per-SURFACE (any finished impl surface, oldest run-id epoch first) —
# the Gherkin "only slot 2's run-id has a marker" scenario pins this reading.
#
# The classification passes read from here-strings, not a pipe: a pipe would put
# the loop in a subshell and discard the arrays it builds. Expansion results are
# never re-scanned, so a hostile ref in "$managed" cannot inject.
layout_decide() {
  local role="$1" new_run="$2" label="$3"
  local raw norm managed kind slot rid pane surface epoch s
  # stdin is consumed ONCE and kept: the aux path needs the raw JSON a second
  # time for layout_rightmost_surface, and stdin is gone after the first read.
  raw="$(cat)"
  norm="$(printf '%s' "$raw" | layout_normalize_tree)"
  managed="$(printf '%s\n' "$norm" | layout_managed)"

  # Pass A — winning pane per slot (duplicate slot: newest run-id epoch wins;
  # losers are unmanaged from here on and never touched). All five indices stay
  # initialized: the file is sourced under `set -u`, where a gap is fatal.
  local slot_pane=("" "" "" "" "") slot_max=("" -1 -1 -1 -1) slot_ref=("" "" "" "" "")
  while IFS=$'\t' read -r kind slot rid pane surface; do
    [ "$kind" = impl ] || continue
    epoch="${rid%%-*}"
    # 2>/dev/null: a run-id too large for shell arithmetic loses, never errors.
    if [ "$epoch" -gt "${slot_max[$slot]}" ] 2>/dev/null; then
      slot_max[slot]="$epoch"; slot_pane[slot]="$pane"
    fi
  done <<< "$managed"

  # Pass B — per-slot target refs and the oldest finished reusable surface.
  local reuse_ref="" reuse_slot="" reuse_epoch=""
  while IFS=$'\t' read -r kind slot rid pane surface; do
    [ "$kind" = impl ] || continue
    [ "$pane" = "${slot_pane[$slot]}" ] || continue
    [ -n "${slot_ref[$slot]}" ] || slot_ref[slot]="$surface"
    if layout_run_finished "$rid"; then
      epoch="${rid%%-*}"
      if [ -z "$reuse_ref" ] || [ "$epoch" -lt "$reuse_epoch" ]; then
        reuse_ref="$surface"; reuse_slot="$slot"; reuse_epoch="$epoch"
      fi
    fi
  done <<< "$managed"

  if [ "$role" = implementer ]; then
    if [ -n "$reuse_ref" ]; then
      printf 'PLAN: reuse %s\n' "$reuse_ref"
      printf 'TITLE: %s\n' "$(layout_compose_title "impl.$reuse_slot" "$new_run" "$label")"
      return 0
    fi
    local missing=""
    for s in 1 2 3 4; do [ -n "${slot_pane[$s]}" ] || { missing="$s"; break; }; done
    if [ -n "$missing" ]; then
      # Split table (spec): deps are well-founded — 2,3 need 1; 4 needs 2; a
      # missing slot 1 is env-implicit from main again, so lowest-missing-first
      # self-heals user-closed slots.
      case "$missing" in
        1) printf 'PLAN: split right env\n' ;;
        2) printf 'PLAN: split down %s\n'  "${slot_ref[1]}" ;;
        3) printf 'PLAN: split right %s\n' "${slot_ref[1]}" ;;
        4) printf 'PLAN: split right %s\n' "${slot_ref[2]}" ;;
      esac
      printf 'TITLE: %s\n' "$(layout_compose_title "impl.$missing" "$new_run" "$label")"
      return 0
    fi
    # Tab overflow: fewest surfaces wins, ties go to the LOWEST slot — hence
    # strict -lt, which leaves an equal count on the slot already chosen.
    local best_slot="" best_count=0 count
    for s in 1 2 3 4; do
      count="$(printf '%s\n' "$norm" | awk -F'\t' -v p="${slot_pane[$s]}" '$1==p' | grep -c .)"
      if [ -z "$best_slot" ] || [ "$count" -lt "$best_count" ]; then best_slot="$s"; best_count="$count"; fi
    done
    printf 'PLAN: tab %s\n' "${slot_pane[$best_slot]}"
    printf 'TITLE: %s\n' "$(layout_compose_title "impl.$best_slot" "$new_run" "$label")"
    return 0
  fi

  # aux path. Aux pane = pane with >=1 aux surface and NO impl surface (impl
  # wins mixed panes); among several, the one holding the newest aux run-id.
  local aux_pane="" aux_newest=-1 aux_reuse_ref="" aux_reuse_epoch=""
  while IFS=$'\t' read -r kind slot rid pane surface; do
    [ "$kind" = aux ] || continue
    # END {exit found} inverts the sense: this pane HAVING an impl surface exits
    # non-zero, so `|| continue` drops it. Uninitialized found => exit 0 => keep.
    printf '%s\n' "$managed" | awk -F'\t' -v p="$pane" '$1=="impl" && $4==p {found=1} END {exit found}' || continue
    if [ "${rid%%-*}" -gt "$aux_newest" ] 2>/dev/null; then aux_newest="${rid%%-*}"; aux_pane="$pane"; fi
  done <<< "$managed"
  if [ -n "$aux_pane" ]; then
    while IFS=$'\t' read -r kind slot rid pane surface; do
      [ "$kind" = aux ] || continue
      [ "$pane" = "$aux_pane" ] || continue
      if layout_run_finished "$rid"; then
        epoch="${rid%%-*}"
        if [ -z "$aux_reuse_ref" ] || [ "$epoch" -lt "$aux_reuse_epoch" ]; then
          aux_reuse_ref="$surface"; aux_reuse_epoch="$epoch"
        fi
      fi
    done <<< "$managed"
    if [ -n "$aux_reuse_ref" ]; then printf 'PLAN: reuse %s\n' "$aux_reuse_ref"
    else printf 'PLAN: tab %s\n' "$aux_pane"; fi
  else
    # No aux column yet: anchor the new column on the RIGHTMOST pane, whichever
    # it is, so the split lands at the far right. The anchor cannot come from
    # `new-pane --direction right`: that verb has no anchor flag and splits
    # relative to the CURRENT pane, which is the caller's own far-left main
    # session, so live it placed the aux column 2nd from left (observed
    # 2026-07-21). No usable pane at all -> env-implicit targeting from main
    # (spec: Aux path fallbacks).
    local anchor
    anchor="$(printf '%s' "$raw" | layout_rightmost_surface)"
    printf 'PLAN: aux-create %s\n' "${anchor:-env}"
  fi
  printf 'TITLE: %s\n' "$(layout_compose_title aux "$new_run" "$label")"
}
