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
surfaces_of() { # $1 pane_ref, $2.. "surface_ref|title" -> surfaces[] body
  local p="$1"; shift; local s i=0 out=""
  for s in "$@"; do
    out="$out{\"ref\":\"${s%%|*}\",\"pane_ref\":\"$p\",\"title\":\"${s#*|}\",\"index_in_pane\":$i},"
    i=$((i+1))
  done
  printf '%s' "${out%,}"
}
pane() { # $1 pane_ref, $2.. "surface_ref|title" pairs
  local p="$1"; shift; local s refs=""
  for s in "$@"; do refs="$refs\"${s%%|*}\","; done
  printf '{"ref":"%s","surface_count":%s,"surface_refs":[%s],"surfaces":[%s]}' \
    "$p" "$#" "${refs%,}" "$(surfaces_of "$p" "$@")"
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

# --- the builders must agree with the fixture, through the same code path ----
# Same logical content, built by hand: if the builders' shape drifts from the
# captured reality, this goes red before any canned case can mislead us.
canned_live="$(tree "$(workspace workspace:8 \
  "$(pane pane:44 'surface:65|impl.1:1700000001-1-1 taskA' 'surface:68|Terminal')" \
  "$(pane pane:45 'surface:66|aux:1700000002-4-5 judge')")")"
eq "canned builders normalize identically to the live fixture" \
   "$(printf '%s' "$canned_live" | layout_normalize_tree)" "$norm_live"

# --- normalize: canned shape, field mapping exact ----------------------------
t="$(tree "$(workspace workspace:1 \
  "$(pane pane:1 'surface:10|zsh')" \
  "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 taskA')")")"
norm="$(printf '%s' "$t" | layout_normalize_tree)"
eq "normalize maps pane/surface/title" "$(printf '%s\n' "$norm" | sed -n 2p)" \
   "$(printf 'pane:2\tsurface:20\timpl.1:1700000001-1-1 taskA')"

# --- workspace filter: ref-form value scopes to one workspace ----------------
# Ref form, not a UUID: CMUX_WORKSPACE_ID is a UUID in live use and legitimately
# will not match here — that path is the fallback case asserted just below.
t2="$(tree "$(workspace workspace:1 "$(pane pane:1 'surface:10|mine')")" \
           "$(workspace workspace:2 "$(pane pane:9 'surface:90|impl.1:1700000001-1-1 other-ws')")")"
n2="$(printf '%s' "$t2" | CMUX_WORKSPACE_ID=workspace:1 layout_normalize_tree)"
eq "workspace filter excludes foreign panes" "$n2" "$(printf 'pane:1\tsurface:10\tmine')"

n3="$(printf '%s' "$t2" | CMUX_WORKSPACE_ID=1b2c3d4e-0000-0000-0000-000000000000 layout_normalize_tree)"
eq "unmatchable workspace id returns the whole tree" \
   "$(printf '%s\n' "$n3" | wc -l | tr -d ' ')" "2"

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

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
