#!/usr/bin/env bash
# cmux-layout.test.sh — Layer-1 pure decision tests: canned tree JSON + a fake
# state dir, zero cmux. Run: bash panes/adapters/cmux-layout.test.sh
#
# File-wide: the `[ cond ] && ok || bad` harness is safe here — ok()/bad() both
# end in `pass=/fail=` arithmetic assignments that always return 0, so `bad`
# never runs after a passing `ok`. SC2015's "C may run when A is true" caveat
# does not apply.
# shellcheck disable=SC2015
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PANE_STATE_DIR="$TMP/state"
mkdir -p "$PANE_STATE_DIR/runs"
unset CMUX_WORKSPACE_ID
# shellcheck source=/dev/null
. "$HERE/cmux-layout.sh"

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s%s\n' "$1" "${2:+ ($2)}"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want [$3] got [$2]"; }

mkrun()  { mkdir -p "$PANE_STATE_DIR/runs/$1"; }                 # running
mkdone() { mkrun "$1"; printf 'DONE\n' > "$PANE_STATE_DIR/runs/$1/agent-exit"; }

# --- tree builders -----------------------------------------------------------
# Shape mirrors fixtures/tree-live.json EXACTLY (probe P2): a pane keys its own
# ref as "ref" (not "pane_ref"); a surface keys its own as "ref" and carries
# "pane_ref" + "title". Builders that drift from the fixture would keep these
# canned cases green while live use silently returns nothing, so the fixture
# equivalence assertion below is a hard requirement, not a nicety.
#
# A pane also carries "index" (its left-to-right position) and
# "selected_surface_ref" (the surface it is showing). Both are in the live
# fixture and both are load-bearing for layout_rightmost_surface, so pane()
# takes the index explicitly rather than defaulting it — a fixture must state
# its own left-to-right order.
surfaces_of() { # $1 pane_ref, $2.. "surface_ref|title" -> surfaces[] body
  local p="$1"; shift; local s i=0 out=""
  for s in "$@"; do
    out="$out{\"ref\":\"${s%%|*}\",\"pane_ref\":\"$p\",\"title\":\"${s#*|}\",\"index_in_pane\":$i},"
    i=$((i+1))
  done
  printf '%s' "${out%,}"
}
pane() { # $1 pane_ref, $2 index (left-to-right), $3.. "surface_ref|title" pairs
  local p="$1" idx="$2"; shift 2; local s refs=""
  for s in "$@"; do refs="$refs\"${s%%|*}\","; done
  # selected_surface_ref = the first surface, exactly as in the live fixture
  # (pane:44 shows surface:65, its index_in_pane 0).
  printf '{"ref":"%s","index":%s,"selected_surface_ref":"%s","surface_count":%s,"surface_refs":[%s],"surfaces":[%s]}' \
    "$p" "$idx" "${1%%|*}" "$#" "${refs%,}" "$(surfaces_of "$p" "$@")"
}
workspace() { # $1 workspace_ref, $2.. pane json blobs
  local w="$1"; shift; local IFS=,
  printf '{"ref":"%s","title":"ws","panes":[%s]}' "$w" "$*"
}
tree() { # $1.. workspace json blobs
  local IFS=,
  printf '{"windows":[{"ref":"window:1","workspaces":[%s]}]}' "$*"
}

# --- normalize: the live fixture pins the real 0.64.20 shape -----------------
norm_live="$(layout_normalize_tree < "$HERE/fixtures/tree-live.json")"
eq "live fixture normalizes to its 3 known surfaces" "$norm_live" \
   "$(printf 'pane:44\tsurface:65\timpl.1:1700000001-1-1 taskA\npane:44\tsurface:68\tTerminal\npane:45\tsurface:66\taux:1700000002-4-5 judge')"
printf '%s\n' "$norm_live" | awk -F'\t' 'NF!=3{exit 1}' && ok "TSV is 3 fields" || bad "TSV is 3 fields"

# --- rightmost anchor: the live fixture pins index + selected_surface_ref ----
# pane:44 is index 0, pane:45 is index 1, so the far-right anchor is pane:45's
# own surface. Content-pinned, not just non-empty: an implementation that
# returned nothing would otherwise read as "no usable pane" and pass.
rm_live="$(layout_rightmost_surface < "$HERE/fixtures/tree-live.json")"
eq "live fixture rightmost surface is the max-index pane's" "$rm_live" "surface:66"

# --- the builders must agree with the fixture, through the same code path ----
# Same logical content, built by hand: if the builders' shape drifts from the
# captured reality, this goes red before any canned case can mislead us. Both
# outputs are pinned above/below to non-empty text, so neither assertion can
# pass by both sides being equally empty.
canned_live="$(tree "$(workspace workspace:8 \
  "$(pane pane:44 0 'surface:65|impl.1:1700000001-1-1 taskA' 'surface:68|Terminal')" \
  "$(pane pane:45 1 'surface:66|aux:1700000002-4-5 judge')")")"
eq "canned builders normalize identically to the live fixture" \
   "$(printf '%s' "$canned_live" | layout_normalize_tree)" "$norm_live"
eq "canned builders pick the same rightmost surface as the live fixture" \
   "$(printf '%s' "$canned_live" | layout_rightmost_surface)" "$rm_live"

# --- rightmost anchor: max INDEX, not document order -------------------------
# Index order and document order deliberately DISAGREE here: the max-index pane
# is written FIRST. "last pane in the document" returns surface:10; only reading
# .index returns surface:20. The live-fixture case above is the mirror image
# (max-index pane written last), so between them both drifts are excluded.
t_order="$(tree "$(workspace workspace:1 \
  "$(pane pane:2 7 'surface:20|zsh')" \
  "$(pane pane:1 3 'surface:10|zsh')")")"
eq "rightmost is the max-index pane, not the last in document order" \
   "$(printf '%s' "$t_order" | layout_rightmost_surface)" "surface:20"

eq "no pane at all -> no anchor" "$(printf '{"windows":[]}' | layout_rightmost_surface)" ""

# A pane missing "index" must yield NO anchor rather than being ranked equal to
# every other pane: that is what makes builder drift fail loudly here instead of
# silently degrading live. Hand-written, deliberately NOT via pane().
t_noidx='{"windows":[{"ref":"window:1","workspaces":[{"ref":"workspace:1","panes":[
  {"ref":"pane:1","selected_surface_ref":"surface:10","surface_refs":["surface:10"],
   "surfaces":[{"ref":"surface:10","pane_ref":"pane:1","title":"zsh"}]}]}]}]}'
eq "a pane with no index yields no anchor" "$(printf '%s' "$t_noidx" | layout_rightmost_surface)" ""

# --- normalize: canned shape, field mapping exact ----------------------------
t="$(tree "$(workspace workspace:1 \
  "$(pane pane:1 0 'surface:10|zsh')" \
  "$(pane pane:2 1 'surface:20|impl.1:1700000001-1-1 taskA')")")"
norm="$(printf '%s' "$t" | layout_normalize_tree)"
eq "normalize maps pane/surface/title" "$(printf '%s\n' "$norm" | sed -n 2p)" \
   "$(printf 'pane:2\tsurface:20\timpl.1:1700000001-1-1 taskA')"

# --- workspace filter: ref-form value scopes to one workspace ----------------
# Ref form, not a UUID: CMUX_WORKSPACE_ID is a UUID in live use and legitimately
# will not match here — that path is the fallback case asserted just below.
# Indices are workspace-local in a real tree; this fixture gives the foreign
# pane the higher one so the "whole tree" fallback below has an unambiguous
# winner, which is the only thing that case is asserting.
t2="$(tree "$(workspace workspace:1 "$(pane pane:1 0 'surface:10|mine')")" \
           "$(workspace workspace:2 "$(pane pane:9 1 'surface:90|impl.1:1700000001-1-1 other-ws')")")"
n2="$(printf '%s' "$t2" | CMUX_WORKSPACE_ID=workspace:1 layout_normalize_tree)"
eq "workspace filter excludes foreign panes" "$n2" "$(printf 'pane:1\tsurface:10\tmine')"

n3="$(printf '%s' "$t2" | CMUX_WORKSPACE_ID=1b2c3d4e-0000-0000-0000-000000000000 layout_normalize_tree)"
eq "unmatchable workspace id returns the whole tree" \
   "$(printf '%s\n' "$n3" | wc -l | tr -d ' ')" "2"

# The anchor selector applies the SAME filter, with the same load-bearing
# fallback — a UUID legitimately matches nothing and must not scope the tree
# down to no anchor at all.
eq "rightmost anchor respects the workspace filter" \
   "$(printf '%s' "$t2" | CMUX_WORKSPACE_ID=workspace:1 layout_rightmost_surface)" "surface:10"
eq "unmatchable workspace id keeps the whole tree in play for the anchor" \
   "$(printf '%s' "$t2" | CMUX_WORKSPACE_ID=1b2c3d4e-0000-0000-0000-000000000000 layout_rightmost_surface)" \
   "surface:90"

# --- managed classification --------------------------------------------------
m="$(printf 'pane:2\tsurface:20\timpl.3:1700000001-2-3 taskA\npane:3\tsurface:30\taux:1700000002-4-5 judge\npane:4\tsurface:40\tzsh\npane:5\tsurface:50\timpl.9:1700000001-1-1 badslot\npane:6\tsurface:60\timpl.2:notarunid x\npane:7\tsurface:70\timpl.1:1700000001-1-1x\n' | layout_managed)"
eq "impl line parsed" "$(printf '%s\n' "$m" | sed -n 1p)" "$(printf 'impl\t3\t1700000001-2-3\tpane:2\tsurface:20')"
eq "aux line parsed"  "$(printf '%s\n' "$m" | sed -n 2p)" "$(printf 'aux\t-\t1700000002-4-5\tpane:3\tsurface:30')"
eq "unmanaged/malformed excluded" "$(printf '%s\n' "$m" | wc -l | tr -d ' ')" "2"

# --- finished check ----------------------------------------------------------
mkdone 1700000001-1-1; mkrun 1700000002-1-1
layout_run_finished 1700000001-1-1 && ok "marker => finished" || bad "marker => finished"
layout_run_finished 1700000002-1-1 && bad "no marker => running" || ok "no marker => running"
layout_run_finished 1699999999-9-9 && ok "missing run dir => finished" || bad "missing run dir => finished"

# --- layout_decide: implementer path -----------------------------------------
# Every tree() below goes through workspace(): feeding pane blobs straight into
# the workspaces slot still normalizes correctly (recursive descent looks right
# through the missing level), so a drifted builder would stay green here and
# only fail live — exactly the hazard the fixture equivalence check above exists
# to catch.
decide()  { printf '%s' "$1" | layout_decide "$2" "$3" "$4"; }
running() { mkrun "$1"; rm -f "$PANE_STATE_DIR/runs/$1/agent-exit"; }  # reset to running
NEW=1700000099-9-9

t_empty="$(tree "$(workspace workspace:1 "$(pane pane:1 0 'surface:10|zsh')")")"
eq "empty ws -> create slot 1" "$(decide "$t_empty" implementer $NEW lbl)" \
   "$(printf 'PLAN: split right env\nTITLE: impl.1:%s lbl' $NEW)"

# The finished-check cases above left 1700000001-1-1 marked finished. A stale
# marker silently turns a create into a reuse, so every run-id these cases touch
# is reset explicitly rather than assumed.
running 1700000001-1-1
t_s1="$(tree "$(workspace workspace:1 \
  "$(pane pane:1 0 'surface:10|zsh')" \
  "$(pane pane:2 1 'surface:20|impl.1:1700000001-1-1 a')")")"
eq "slot1 busy -> create slot 2" "$(decide "$t_s1" implementer $NEW lbl)" \
   "$(printf 'PLAN: split down surface:20\nTITLE: impl.2:%s lbl' $NEW)"

running 1700000002-1-1; running 1700000003-1-1
t_s124="$(tree "$(workspace workspace:1 \
  "$(pane pane:2 0 'surface:20|impl.1:1700000001-1-1 a')" \
  "$(pane pane:3 1 'surface:30|impl.2:1700000002-1-1 b')" \
  "$(pane pane:5 2 'surface:50|impl.4:1700000003-1-1 d')")")"
eq "lowest missing slot (3) from slot1" "$(decide "$t_s124" implementer $NEW lbl)" \
   "$(printf 'PLAN: split right surface:20\nTITLE: impl.3:%s lbl' $NEW)"

# TWO finished surfaces, so "oldest" genuinely discriminates: with only one,
# the assertion passes whichever way the comparison points and proves nothing.
mkdone 1700000002-1-1; mkdone 1700000003-1-1
eq "finished slot reused before growth (oldest finished)" \
   "$(decide "$t_s124" implementer $NEW lbl)" \
   "$(printf 'PLAN: reuse surface:30\nTITLE: impl.2:%s lbl' $NEW)"
running 1700000002-1-1; running 1700000003-1-1

mkrun 1700000004-1-1
t_full="$(tree "$(workspace workspace:1 \
  "$(pane pane:2 0 'surface:20|impl.1:1700000001-1-1 a' 'surface:21|zsh')" \
  "$(pane pane:3 1 'surface:30|impl.2:1700000002-1-1 b')" \
  "$(pane pane:4 2 'surface:40|impl.3:1700000003-1-1 c' 'surface:41|zsh')" \
  "$(pane pane:5 3 'surface:50|impl.4:1700000004-1-1 d')")")"
eq "full busy quadrant -> tab fewest-surfaces, tie lowest slot" \
   "$(decide "$t_full" implementer $NEW lbl)" \
   "$(printf 'PLAN: tab pane:3\nTITLE: impl.2:%s lbl' $NEW)"

# duplicate slot: newest run-id's pane wins; loser is invisible
mkrun 1700000005-1-1
t_dup="$(tree "$(workspace workspace:1 \
  "$(pane pane:2 0 'surface:20|impl.1:1700000001-1-1 old')" \
  "$(pane pane:6 1 'surface:60|impl.1:1700000005-1-1 new')")")"
eq "duplicate slot -> newest wins as split target" "$(decide "$t_dup" implementer $NEW lbl)" \
   "$(printf 'PLAN: split down surface:60\nTITLE: impl.2:%s lbl' $NEW)"

# --- layout_decide: aux path -------------------------------------------------
# The aux-create anchor is the RIGHTMOST pane, not a quadrant slot: pane:9 here
# is an ordinary unmanaged pane sitting to the right of the quadrant, and it is
# what the new column must split off. The superseded rule (slot 3, else slot 4,
# else env) would have answered surface:40, so this case discriminates.
t_noaux="$(tree "$(workspace workspace:1 \
  "$(pane pane:2 0 'surface:20|impl.1:1700000001-1-1 a')" \
  "$(pane pane:4 1 'surface:40|impl.3:1700000003-1-1 c')" \
  "$(pane pane:9 2 'surface:90|zsh')")")"
eq "no aux pane -> aux-create anchors on the rightmost pane" "$(decide "$t_noaux" aux $NEW judgelbl)" \
   "$(printf 'PLAN: aux-create surface:90\nTITLE: aux:%s judgelbl' $NEW)"
eq "no quadrant -> aux-create anchors on main's own pane" "$(decide "$t_empty" aux $NEW judgelbl)" \
   "$(printf 'PLAN: aux-create surface:10\nTITLE: aux:%s judgelbl' $NEW)"
# Only with no usable pane at all does the anchor fall back to env-implicit
# targeting (spec: Aux path fallbacks).
t_nopane="$(tree "$(workspace workspace:1)")"
eq "no pane at all -> aux-create env" "$(decide "$t_nopane" aux $NEW judgelbl)" \
   "$(printf 'PLAN: aux-create env\nTITLE: aux:%s judgelbl' $NEW)"

mkrun 1700000006-1-1
t_aux="$(tree "$(workspace workspace:1 \
  "$(pane pane:2 0 'surface:20|impl.1:1700000001-1-1 a')" \
  "$(pane pane:7 1 'surface:70|aux:1700000006-1-1 judge')")")"
eq "busy aux pane -> tab on it" "$(decide "$t_aux" aux $NEW lbl)" \
   "$(printf 'PLAN: tab pane:7\nTITLE: aux:%s lbl' $NEW)"
mkdone 1700000006-1-1
eq "finished aux surface reused (extension, user-approved)" "$(decide "$t_aux" aux $NEW lbl)" \
   "$(printf 'PLAN: reuse surface:70\nTITLE: aux:%s lbl' $NEW)"

# mixed pane: impl wins -> pane is a slot, its aux surface never aux-targets
t_mixed="$(tree "$(workspace workspace:1 \
  "$(pane pane:2 0 'surface:20|impl.1:1700000001-1-1 a' 'surface:21|aux:1700000006-1-1 j')")")"
eq "mixed pane is impl -> aux creates its own column" "$(decide "$t_mixed" aux $NEW lbl)" \
   "$(printf 'PLAN: aux-create surface:20\nTITLE: aux:%s lbl' $NEW)"

# --- titles ------------------------------------------------------------------
eq "empty run_id -> unmanaged bare label" "$(layout_compose_title impl.1 '' plainlabel)" "plainlabel"
long_label="$(printf 'L%.0s' $(seq 1 80))"
composed="$(layout_compose_title impl.2 $NEW "$long_label")"
eq "title truncated to 64" "${#composed}" "64"
case "$composed" in "impl.2:$NEW "*) ok "prefix never truncated" ;; *) bad "prefix never truncated" "$composed" ;; esac

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
