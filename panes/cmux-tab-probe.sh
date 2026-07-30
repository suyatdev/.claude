#!/usr/bin/env bash
# cmux-tab-probe.sh — live probe backing the pane-split-policy open_tab primitive
# (spec: docs/superpowers/specs/2026-07-22-pane-split-policy-design.md). Run it
# from a cmux pane after any cmux upgrade, BEFORE trusting cmux.sh open_tab.
# EVIDENCE-GATHERING, not a contract: when cmux changes, update the expectations
# here and re-record the findings in coding-memory/branches/pane-split-policy.md.
set -u
CMUX_BIN="${PANE_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
JQ_BIN="${PANE_JQ_BIN:-/usr/bin/jq}"
FIXTURE="${1:-$HOME/.claude/panes/adapters/fixtures/tab-live.json}"
export CMUX_QUIET=1

say()  { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

[ -x "$CMUX_BIN" ] || { echo "no cmux at $CMUX_BIN"; exit 1; }
[ -x "$JQ_BIN" ]   || { echo "no jq at $JQ_BIN"; exit 1; }
note "cmux: $("$CMUX_BIN" version 2>&1 | head -1)"

NORM_JQ='[.. | objects | select(has("ref") and has("pane_ref") and has("title"))]
         | .[] | [.pane_ref, .ref, .title] | @tsv'
norm() { "$JQ_BIN" -r "$NORM_JQ" 2>/dev/null; }

say "T1: scratch workspace"
ws_out="$("$CMUX_BIN" new-workspace --name "tab-probe-scratch" 2>&1)"
ws_ref="$(printf '%s' "$ws_out" | awk '$1=="OK"{print $2}')"
case "$ws_ref" in workspace:*) note "scratch: $ws_ref" ;; *) echo "no workspace ref: $ws_out"; exit 1 ;; esac
cleanup() { "$CMUX_BIN" close-workspace --workspace "$ws_ref" >/dev/null 2>&1; }
trap cleanup EXIT

say "T2: base pane + its surface/pane refs"
base_surface="$("$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | awk -F'\t' 'NR==1{print $2}')"
base_pane="$("$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | awk -F'\t' 'NR==1{print $1}')"
note "base surface=$base_surface  base pane=$base_pane"

say "T3: candidate — new-surface --pane <pane-ref> (attach a tab to a NAMED pane)"
ns_out="$("$CMUX_BIN" --json new-surface --pane "$base_pane" --workspace "$ws_ref" 2>&1)"
printf '   %s\n' "$ns_out"
new_ref="$(printf '%s' "$ns_out" | "$JQ_BIN" -er '.surface_ref' 2>/dev/null)" || new_ref=""
note "new surface ref=[$new_ref] (expect surface:*)"
note "tree AFTER — confirm the new surface shares base pane $base_pane (same pane_ref column):"
"$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | sed 's/^/   /'
note "FINDING: if the new surface's pane_ref == $base_pane, 'new-surface --pane <pane>' IS"
note "         the open_tab primitive — a tab inside the target pane. Record it."

say "T4: does the tab accept a launcher via send? (open_tab must run the agent)"
if [ -n "$new_ref" ]; then
  "$CMUX_BIN" send --workspace "$ws_ref" --surface "$new_ref" -- "echo TAB_SEND_OK\n" >/dev/null 2>&1
  note "sent an echo to $new_ref — visually confirm TAB_SEND_OK printed in the new tab."
fi

say "T5: capture fixture"
mkdir -p "$(dirname "$FIXTURE")"
"$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null > "$FIXTURE"
printf '   fixture written: %s (%s bytes)\n' "$FIXTURE" "$(wc -c < "$FIXTURE" | tr -d ' ')"
note "REVIEW before committing — no real titles/paths:"
"$JQ_BIN" -r '[.. | objects | .title? // empty] | unique | .[]' "$FIXTURE" | sed 's/^/   title: /'

say "VISUAL CHECK — do this NOW, before pressing Enter (the surfaces are still live)"
note "Switch your cmux view to the '$ws_ref' (tab-probe-scratch) workspace if you are"
note "not already in it — cmux may not have auto-focused it."
note "Q1 (WORKSPACES): in the workspace switcher, how many NEW workspaces appeared?"
note "    Expect EXACTLY ONE: tab-probe-scratch ($ws_ref). If a SECOND new workspace"
note "    appeared when T3 ran, then 'new-surface --pane' spawned a WORKSPACE, not an"
note "    in-pane tab — that is the finding, record it."
note "Q2 (TABS): look at the pane $base_pane. Does its TAB STRIP show TWO tabs"
note "    (base $base_surface + new $new_ref)? Two tabs => new-surface --pane IS an"
note "    in-pane tab (matches the tree). If the new surface is in its own window or"
note "    workspace instead, record WHERE it landed."
note "Q3 (SEND): did TAB_SEND_OK (from T4) print inside the NEW tab?"
printf '\n'

say "cleanup"
printf '   Press Enter to close %s ' "$ws_ref"; IFS= read -r _
cleanup
note "closed."
