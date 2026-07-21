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

# stdin: `cmux --json tree` output -> normalized TSV. Recursive descent keeps
# this resilient to wrapper objects; the live-captured fixture test pins it to
# the real 0.64.20 shape (probe P2), in which a pane keys its own ref as "ref"
# and a surface keys its own as "ref" while carrying "pane_ref" + "title".
#
# Workspace scoping is SERVER-side: the caller passes --workspace
# "$CMUX_WORKSPACE_ID" to `cmux --json tree` (probe P1 — the UUID is accepted
# directly). The filter below is defence-in-depth for a ref-form value only.
# $CMUX_WORKSPACE_ID is a UUID (probe P7) while the tree's own refs are of the
# form workspace:8, so in live use this client-side filter will normally NOT
# match and will correctly fall through to returning everything. That fallback
# is load-bearing — without it a UUID would scope the tree down to nothing and
# the whole layout feature would silently degrade to legacy. Do not try to
# make a UUID match by rewriting it as workspace:<uuid>; that matches nothing.
layout_normalize_tree() {
  local ws="${CMUX_WORKSPACE_ID:-}"
  # shellcheck disable=SC2016  # $ws/$p are jq variables bound by --arg, not shell ones
  "$LAYOUT_JQ" -r --arg ws "$ws" '
    (if $ws != "" and ([.. | objects | select(has("panes") and .ref? == $ws)] | length) > 0
     then [.. | objects | select(has("panes") and .ref? == $ws)] else [.] end)
    | [.[] | .. | objects | select(has("ref") and has("pane_ref") and has("title"))]
    | .[] | [.pane_ref, .ref, .title] | @tsv' 2>/dev/null
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
