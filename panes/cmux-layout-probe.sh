#!/usr/bin/env bash
# cmux-layout-probe.sh — live probe backing the pane-layout-v2 assumptions
# (spec: docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md). Run it
# from a cmux pane after any cmux upgrade, BEFORE trusting the layout adapter.
#
# It builds a scratch workspace, exercises every primitive the adapter relies
# on, prints a P1..P7 findings report, captures the scratch workspace tree as
# the committed test fixture, and cleans up.
#
# Findings are recorded in coding-memory/branches/pane-layout-v2.md. This
# script is EVIDENCE-GATHERING, not a contract — when cmux changes, update the
# expectations here and re-record the findings rather than trusting the old ones.
set -u
CMUX_BIN="${PANE_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
JQ_BIN="${PANE_JQ_BIN:-/usr/bin/jq}"
FIXTURE="${1:-$HOME/.claude/panes/adapters/fixtures/tree-live.json}"
# Silences the "new-workspace is now an alias for workspace create" notice that
# would otherwise contaminate the parsed stdout of mutating commands.
export CMUX_QUIET=1

say()  { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

[ -x "$CMUX_BIN" ] || { echo "no cmux at $CMUX_BIN"; exit 1; }
[ -x "$JQ_BIN" ]   || { echo "no jq at $JQ_BIN"; exit 1; }
note "cmux: $("$CMUX_BIN" version 2>&1 | head -1)"
note "jq:   $("$JQ_BIN" --version 2>&1)"

# The normalized-TSV jq the adapter uses. Surfaces are the only objects that
# carry ref + pane_ref + title together, which makes this selector exact:
# workspace/pane/surface objects each key their OWN ref as "ref", and only
# surfaces also carry a parent "pane_ref".
NORM_JQ='[.. | objects | select(has("ref") and has("pane_ref") and has("title"))]
         | .[] | [.pane_ref, .ref, .title] | @tsv'
norm() { "$JQ_BIN" -r "$NORM_JQ" 2>/dev/null; }

say "P7: env formats (record verbatim)"
printf '   CMUX_WORKSPACE_ID=%s\n   CMUX_SURFACE_ID=%s\n' \
  "${CMUX_WORKSPACE_ID:-unset}" "${CMUX_SURFACE_ID:-unset}"
note "tree default output uses REFS (workspace:N); these env vars are UUIDs."
note "--id-format both exposes workspace_id + workspace_ref side by side:"
"$CMUX_BIN" --json --id-format both tree 2>/dev/null \
  | "$JQ_BIN" -r '.caller | "   caller workspace_id=\(.workspace_id) workspace_ref=\(.workspace_ref)"'

say "P2a: create scratch workspace"
# NOTE: new-workspace is a legacy alias for `workspace create` and does NOT
# honour --json — it prints "OK workspace:N" as plain text. Parse, don't jq.
ws_out="$("$CMUX_BIN" new-workspace --name "layout-probe-scratch" 2>&1)"
printf '   %s\n' "$ws_out"
ws_ref="$(printf '%s' "$ws_out" | awk '$1=="OK"{print $2}')"
case "$ws_ref" in
  workspace:*) note "scratch workspace: $ws_ref" ;;
  *) echo "could not parse workspace ref from: $ws_out -- STOP"; exit 1 ;;
esac
cleanup() { "$CMUX_BIN" close-workspace --workspace "$ws_ref" >/dev/null 2>&1; }
trap cleanup EXIT

say "P1: is bare --json tree scoped to the CALLING workspace?"
bare_n="$("$CMUX_BIN" --json tree 2>/dev/null | "$JQ_BIN" '[.windows[].workspaces[]] | length')"
scoped_n="$("$CMUX_BIN" --json tree --workspace "${CMUX_WORKSPACE_ID:-$ws_ref}" 2>/dev/null \
            | "$JQ_BIN" '[.windows[].workspaces[]] | length')"
note "bare tree workspaces=$bare_n   --workspace-scoped workspaces=$scoped_n"
if [ "${bare_n:-0}" -gt 1 ]; then
  note "FINDING: bare tree is WINDOW-scoped, not workspace-scoped (spec assumption 1 FALSE)."
  note "         Use 'tree --workspace \$CMUX_WORKSPACE_ID' — the UUID is accepted directly."
else
  note "bare tree returned a single workspace; re-check with >1 workspace open before trusting."
fi
note "Third mechanism (no env var needed) — the tree names its own caller:"
"$CMUX_BIN" --json tree 2>/dev/null | "$JQ_BIN" -r '.caller | "   caller workspace_ref=\(.workspace_ref)"'

say "P2b: real tree JSON shape"
note "nesting: windows[] > workspaces[] > panes[] > surfaces[]"
note "each level keys its own ref as \"ref\"; surfaces also carry pane_ref + title"
note "normalized TSV of the scratch workspace:"
"$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | sed 's/^/   /'
first_surface="$("$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | awk -F'\t' 'NR==1{print $2}')"
first_pane="$("$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | awk -F'\t' 'NR==1{print $1}')"

say "P3: does new-pane --direction right exist, and is it a full-height column?"
"$CMUX_BIN" --json new-pane --direction right --workspace "$ws_ref" 2>&1 | sed 's/^/   /'
note "returns JSON with pane_ref + surface_ref. GEOMETRY IS NOT IN THE TREE —"
note "visually confirm in the scratch workspace that the right pane is full-height."

say "P5: new-surface --json returns refs; targeting needs ref + --workspace context"
note "bare pane UUID without workspace context (expected: not_found):"
pane_uuid="$("$CMUX_BIN" --json --id-format both tree --workspace "$ws_ref" 2>/dev/null \
  | "$JQ_BIN" -r '[.. | objects | select(has("ref") and has("surfaces"))][0].id')"
"$CMUX_BIN" --json new-surface --pane "$pane_uuid" 2>&1 | sed 's/^/   /'
note "pane REF + explicit --workspace (expected: JSON with refs):"
"$CMUX_BIN" --json new-surface --pane "$first_pane" --workspace "$ws_ref" 2>&1 | sed 's/^/   /'

say "P6: rename-tab round-trip AND the silent mis-target hazard"
"$CMUX_BIN" rename-tab --workspace "$ws_ref" --surface "$first_surface" \
  -- "impl.1:1700000001-1-1 taskA" 2>&1 | sed 's/^/   /'
# shellcheck disable=SC2016  # $r is a jq variable bound by --arg, not a shell one
got="$("$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null \
  | "$JQ_BIN" -r --arg r "$first_surface" '[.. | objects
      | select(has("ref") and has("pane_ref") and has("title"))][]
      | select(.ref==$r) | .title')"
note "round-trip title on $first_surface: [$got]"
note "now renaming a NONEXISTENT surface (surface:9999) — watch the exit code:"
# Captured, not piped: after a pipeline $? is sed's status, which would report
# the P6 hazard as a clean failure when it is in fact a silent success.
bogus_out="$("$CMUX_BIN" rename-tab --workspace "$ws_ref" --surface surface:9999 \
  -- "BOGUS-TARGET-TEST" 2>&1)"; bogus_rc=$?
printf '   %s\n' "$bogus_out"
note "exit=$bogus_rc — if this is 0, rename-tab SILENTLY renamed the FOCUSED tab instead."
note "HAZARD: a surface closing between tree-fetch and rename stamps a managed"
note "title onto an innocent surface. The adapter MUST verify-after-rename."
"$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | sed 's/^/   /'

say "P4: respawn-pane --command semantics (DESTRUCTIVE — uses a throwaway surface)"
sp_out="$("$CMUX_BIN" --json new-split down --workspace "$ws_ref" --surface "$first_surface" 2>&1)"
sp_ref="$(printf '%s' "$sp_out" | "$JQ_BIN" -er '.surface_ref' 2>/dev/null)" || sp_ref=""
if [ -n "$sp_ref" ]; then
  p4out="$(mktemp)"
  "$CMUX_BIN" respawn-pane --workspace "$ws_ref" --surface "$sp_ref" \
    --command "echo SHELL_OK > $p4out && printf '[%s]\n' 'A B' >> $p4out" >/dev/null 2>&1
  sleep 3
  note "output file contents:"; sed 's/^/   /' "$p4out" 2>/dev/null
  if grep -q 'SHELL_OK' "$p4out" 2>/dev/null; then
    note "FINDING: SHELL semantics — && chained, redirection ran, 'A B' stayed one arg."
    note "         Any command text MUST be shell-quoted before interpolation."
  else
    note "FINDING: argv semantics (no shell) — record the raw behaviour above."
  fi
  rm -f "$p4out"
  still_there="$("$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | awk -F'\t' -v r="$sp_ref" '$2==r')"
  if [ -z "$still_there" ]; then
    note "FINDING: respawn-pane DESTROYED $sp_ref — it replaces the surface's"
    note "         process, and the surface closes when that process exits."
    note "         Use 'cmux send' for reuse instead (non-destructive; v1-proven)."
  else
    note "$sp_ref survived respawn-pane — re-evaluate the reuse mechanism."
  fi
fi

say "P2c: capture the scratch workspace tree as the committed fixture"
mkdir -p "$(dirname "$FIXTURE")"
"$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null > "$FIXTURE"
printf '   fixture written: %s (%s bytes)\n' \
  "$FIXTURE" "$(wc -c < "$FIXTURE" | tr -d ' ')"
note "REVIEW before committing — it must contain no real titles or paths:"
"$JQ_BIN" -r '[.. | objects | .title? // empty] | unique | .[]' "$FIXTURE" | sed 's/^/   title: /'

say "cleanup"
printf '   Press Enter to close the scratch workspace %s ' "$ws_ref"; IFS= read -r _
cleanup
note "closed."
