#!/usr/bin/env bash
# cmux-exec.test.sh — Layer-2 adapter tests against a fake cmux binary that
# logs argv and replays scripted per-subcommand responses. Asserts CALL
# SEQUENCES and the two-tier degradation matrix.
# Run: bash panes/adapters/cmux-exec.test.sh
#
# File-wide: the `[ cond ] && ok || bad` harness is safe here — ok()/bad() both
# end in a `pass=`/`fail=` arithmetic assignment that always returns 0, so `bad`
# never runs after a passing `ok`. SC2015's "C may run when A is true" caveat
# does not apply.
# shellcheck disable=SC2015
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PANE_STATE_DIR="$TMP/state"
RUN_ID="1700000010-1-1"
RUN_DIR="$PANE_STATE_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR"
LAUNCHER="$RUN_DIR/launch.sh"
printf '#!/usr/bin/env bash\necho hi\n' > "$LAUNCHER"; chmod 700 "$LAUNCHER"
export PANE_CMUX_BIN="$TMP/fake-cmux"
export FAKE_DIR="$TMP/fake"; export FAKE_LOG="$TMP/fake.log"
mkdir -p "$FAKE_DIR"
# This suite may itself be run from inside a real cmux pane, where these are
# set. Every case that needs them sets them explicitly, so clear them first.
unset CMUX_WORKSPACE_ID
unset CMUX_SURFACE_ID
# UUID form, as the live environment actually exports it (probe P7).
WS_UUID="49F4D8B9-887A-44A0-985A-D8F779B73683"

# the fake: first non-flag arg = subcommand; response file $FAKE_DIR/<sub>,
# exit code file $FAKE_DIR/<sub>.rc (default 0). --json is a flag, skip it.
#
# Per-CALL overrides $FAKE_DIR/<sub>.<n> and $FAKE_DIR/<sub>.rc.<n> win over the
# flat ones for the n-th call to that subcommand. Verify-after-rename (probe P6)
# re-reads the tree, so a single static response cannot express "the tree the
# adapter derived from" vs "the tree it sees after the stamp" — without the
# sequence every case would look mis-targeted and the verification assertions
# could not tell a pass from a failure.
cat > "$PANE_CMUX_BIN" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
sub=""
for a in "$@"; do case "$a" in --json) ;; *) sub="$a"; break ;; esac; done
n=1; [ -f "$FAKE_DIR/$sub.n" ] && n="$(cat "$FAKE_DIR/$sub.n")"
printf '%s' "$((n+1))" > "$FAKE_DIR/$sub.n"
if   [ -f "$FAKE_DIR/$sub.$n" ]; then cat "$FAKE_DIR/$sub.$n"
elif [ -f "$FAKE_DIR/$sub" ];    then cat "$FAKE_DIR/$sub"; fi
rc=0
if   [ -f "$FAKE_DIR/$sub.rc.$n" ]; then rc="$(cat "$FAKE_DIR/$sub.rc.$n")"
elif [ -f "$FAKE_DIR/$sub.rc" ];    then rc="$(cat "$FAKE_DIR/$sub.rc")"; fi
exit "$rc"
FAKE
chmod 700 "$PANE_CMUX_BIN"

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s%s\n' "$1" "${2:+ ($2)}"; fail=$((fail+1)); }
reset_fake() { rm -rf "$FAKE_DIR" "$FAKE_LOG"; mkdir -p "$FAKE_DIR"; : > "$FAKE_LOG"; }
adapter() { # $1 role; runs the adapter, captures out/err/rc
  OUT="$(PANE_AGENT_ROLE="$1" bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>"$TMP/err")"
  RC=$?; ERR="$(cat "$TMP/err")"
}
set_tree() { printf '%s' "$1" > "$FAKE_DIR/tree"; }
split_ok()  { printf 'OK surface:42 workspace:1\n' > "$FAKE_DIR/new-split"; }
running()   { mkdir -p "$PANE_STATE_DIR/runs/$1"; rm -f "$PANE_STATE_DIR/runs/$1/agent-exit"; }

# --- tree builders -----------------------------------------------------------
# Shape mirrors fixtures/tree-live.json EXACTLY (probe P2), same as the builders
# in cmux-layout.test.sh: a pane keys its own ref as "ref" (not "pane_ref"); a
# surface keys its own as "ref" and carries "pane_ref" + "title". Hand-written
# JSON in the imagined shape normalizes to NOTHING while layout_decide still
# prints a plausible "split right env" plan — so every assertion below would
# pass green on a silently-dead fixture. T_SLOT1 exists to close that hole: its
# expected plan is only reachable if the tree really was parsed.
#
# A pane also carries "index" (left-to-right position) and
# "selected_surface_ref"; layout_rightmost_surface reads both, and a pane that
# omits "index" yields NO anchor, so an aux fixture built without one falls back
# to "aux-create env" and its assertion goes red instead of passing silently.
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
  # selected_surface_ref = the first surface, exactly as in the live fixture.
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

# No managed surface anywhere -> the quadrant is empty, slot 1 is the target.
T_EMPTY="$(tree "$(workspace workspace:1 "$(pane pane:1 0 'surface:10|zsh')")")"
# Slot 1 taken and RUNNING (a run dir with no agent-exit marker) -> slot 2 is
# the target and it must split DOWN off slot 1's own surface ref. Without the
# explicit run dir the missing dir would read as FINISHED and this would be a
# reuse instead.
running 1700000001-1-1
S1_PANES=(
  "$(pane pane:1 0 'surface:10|zsh')"
  "$(pane pane:44 1 'surface:65|impl.1:1700000001-1-1 taskA')"
)
T_SLOT1="$(tree "$(workspace workspace:1 "${S1_PANES[@]}")")"

# --- Tier 1: tree call fails -> legacy + breadcrumb + exit 0
reset_fake; printf '1' > "$FAKE_DIR/tree.rc"; split_ok
adapter implementer
[ "$RC" -eq 0 ] && ok "tree failure -> exit 0" || bad "tree failure -> exit 0" "rc=$RC $ERR"
grep -q '^new-split down$' "$FAKE_LOG" && ok "tree failure -> legacy new-split down" || bad "tree failure -> legacy new-split down" "$(cat "$FAKE_LOG")"
printf '%s' "$ERR" | grep -q 'cmux-layout: degraded' && ok "breadcrumb on stderr" || bad "breadcrumb on stderr" "$ERR"

# --- Tier 1: unparseable tree -> legacy
reset_fake; printf 'not json' > "$FAKE_DIR/tree"; split_ok
adapter implementer
[ "$RC" -eq 0 ] && grep -q '^new-split down$' "$FAKE_LOG" && ok "garbage tree -> legacy" || bad "garbage tree -> legacy" "rc=$RC"

# --- Tier 1: jq missing -> legacy
reset_fake; set_tree "$T_EMPTY"; split_ok
OUT="$(PANE_AGENT_ROLE=implementer PANE_JQ_BIN=/nonexistent bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>"$TMP/err")"
RC=$?
[ "$RC" -eq 0 ] && grep -q '^new-split down$' "$FAKE_LOG" && ok "jq missing -> legacy" || bad "jq missing -> legacy" "rc=$RC $(cat "$TMP/err")"

# --- Tier 2: legacy split itself fails -> exit nonzero (dispatcher cooldown).
# The REASON is asserted, not just the exit code: an empty new-split response
# also trips the ref-shape guard further down, which exits 1 all by itself, so a
# bare "rc != 0" check stays green even when this guard is deleted outright.
reset_fake; printf '1' > "$FAKE_DIR/tree.rc"; printf '1' > "$FAKE_DIR/new-split.rc"
adapter implementer
[ "$RC" -ne 0 ] && printf '%s' "$ERR" | grep -q 'new-split failed' && ok "legacy split failure -> nonzero (Tier 2)" || bad "legacy split failure -> nonzero (Tier 2)" "rc=$RC $ERR"

# --- ...and the exit STATUS is what is trusted, not the shape of stdout: a
# failing new-split that still prints a plausible "OK surface:N" line must never
# be read as success and handed on to send.
reset_fake; printf '1' > "$FAKE_DIR/tree.rc"; split_ok; printf '1' > "$FAKE_DIR/new-split.rc"
adapter implementer
[ "$RC" -ne 0 ] && ok "new-split exit status beats plausible stdout" || bad "new-split exit status beats plausible stdout" "rc=$RC out=$OUT"

# --- Tier 2: send fails post-creation -> exit nonzero
reset_fake; printf '1' > "$FAKE_DIR/tree.rc"; split_ok; printf '1' > "$FAKE_DIR/send.rc"
adapter implementer
[ "$RC" -ne 0 ] && ok "send failure -> nonzero (Tier 2)" || bad "send failure -> nonzero (Tier 2)"

# --- workspace scoping (probe P1/P5). A bare tree is WINDOW-scoped, so without
# --workspace the adapter would classify foreign panes from other workspaces.
# The mutating calls carry it because refs resolve relative to a workspace
# context; new-split takes no ref, so it stays verbatim v1.
reset_fake; set_tree "$T_EMPTY"; split_ok
OUT="$(CMUX_WORKSPACE_ID="$WS_UUID" PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>"$TMP/err")"
grep -qxF -- "--json tree --workspace $WS_UUID" "$FAKE_LOG" && ok "tree fetch is workspace-scoped when CMUX_WORKSPACE_ID set" || bad "tree fetch is workspace-scoped when CMUX_WORKSPACE_ID set" "$(cat "$FAKE_LOG")"
grep -qxF -- "new-split down" "$FAKE_LOG" && ok "new-split stays bare (no ref to resolve)" || bad "new-split stays bare (no ref to resolve)" "$(cat "$FAKE_LOG")"
grep -qF -- "send --workspace $WS_UUID --surface surface:42 " "$FAKE_LOG" && ok "send carries --workspace" || bad "send carries --workspace" "$(cat "$FAKE_LOG")"
grep -qF -- "rename-tab --workspace $WS_UUID --surface surface:42 " "$FAKE_LOG" && ok "rename-tab carries --workspace" || bad "rename-tab carries --workspace" "$(cat "$FAKE_LOG")"

# --- ...and never an empty --workspace when the variable is unset
reset_fake; set_tree "$T_EMPTY"; split_ok
adapter implementer
grep -qxF -- "--json tree" "$FAKE_LOG" && ok "tree fetch is bare when CMUX_WORKSPACE_ID unset" || bad "tree fetch is bare when CMUX_WORKSPACE_ID unset" "$(cat "$FAKE_LOG")"
grep -q -- "--workspace" "$FAKE_LOG" && bad "no empty --workspace when unset" "$(cat "$FAKE_LOG")" || ok "no empty --workspace when unset"

# --- dryrun without PANE_CMUX_BIN prints the legacy plan (Layer-3 compat).
# adapters.test.sh never sets PANE_CMUX_BIN and asserts exactly this, on a
# machine where the real cmux DOES exist — hence the guard, not a bare probe.
OUT="$(env -u PANE_CMUX_BIN PANE_DRYRUN=1 PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>&1)"
printf '%s' "$OUT" | grep -q 'new-split down' && ok "dryrun sans fake -> legacy plan" || bad "dryrun sans fake -> legacy plan" "$OUT"

# --- dryrun WITH the fake derives and prints the plan
reset_fake; set_tree "$T_EMPTY"
OUT="$(PANE_DRYRUN=1 PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>&1)"
printf '%s' "$OUT" | grep -q 'DRYRUN: PLAN: split right env' && ok "dryrun derives plan" || bad "dryrun derives plan" "$OUT"
printf '%s' "$OUT" | grep -q "DRYRUN: TITLE: impl.1:$RUN_ID lbl" && ok "dryrun composes title" || bad "dryrun composes title" "$OUT"

# --- ...and the derived plan actually reflects the tree's CONTENT. A fixture in
# the wrong shape normalizes to nothing and silently falls back to the slot-1
# plan above, so these two are what make the shape load-bearing.
reset_fake; set_tree "$T_SLOT1"
OUT="$(PANE_DRYRUN=1 PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>&1)"
printf '%s' "$OUT" | grep -q 'DRYRUN: PLAN: split down surface:65' && ok "occupied slot 1 -> plan splits down off its ref" || bad "occupied slot 1 -> plan splits down off its ref" "$OUT"
printf '%s' "$OUT" | grep -q "DRYRUN: TITLE: impl.2:$RUN_ID lbl" && ok "occupied slot 1 -> title takes slot 2" || bad "occupied slot 1 -> title takes slot 2" "$OUT"

# --- the role reaches layout_decide as the adapter's own mapped constant
reset_fake; set_tree "$T_EMPTY"
OUT="$(PANE_DRYRUN=1 PANE_AGENT_ROLE=aux bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>&1)"
printf '%s' "$OUT" | grep -q 'DRYRUN: PLAN: aux-create surface:10' && ok "aux role derives the aux plan" || bad "aux role derives the aux plan" "$OUT"
printf '%s' "$OUT" | grep -q "DRYRUN: TITLE: aux:$RUN_ID lbl" && ok "aux role composes the aux title" || bad "aux role composes the aux title" "$OUT"

# --- an unknown role degrades to aux, and its RAW value never escapes
reset_fake; set_tree "$T_EMPTY"
ROLE_BOGUS='evil-role"; id #'
OUT="$(PANE_DRYRUN=1 PANE_AGENT_ROLE="$ROLE_BOGUS" bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>&1)"
printf '%s' "$OUT" | grep -q 'unknown PANE_AGENT_ROLE' && ok "unknown role noted on stderr" || bad "unknown role noted on stderr" "$OUT"
printf '%s' "$OUT" | grep -q "DRYRUN: TITLE: aux:$RUN_ID lbl" && ok "unknown role falls back to aux" || bad "unknown role falls back to aux" "$OUT"
printf '%s\n%s' "$OUT" "$(cat "$FAKE_LOG")" | grep -qF -- "$ROLE_BOGUS" && bad "raw role value never reaches output or argv" "$OUT" || ok "raw role value never reaches output or argv"

# =============================================================================
# Plan EXECUTION. Everything above pins the frame (derive, degrade, legacy
# floor); everything below pins what the adapter does with a derived plan.
# =============================================================================

# new-split/new-surface/new-pane --json OUTPUT (probes P3/P5). This is NOT tree
# shape — the created object keys its ref as "surface_ref" — so .surface_ref is
# the right selector here even though the tree keys the same thing as "ref".
JSON_SPLIT='{"pane_ref":"pane:30","surface_ref":"surface:51","type":"terminal","window_ref":"window:1","workspace_ref":"workspace:1"}'
creates()    { printf '%s\n' "$JSON_SPLIT" > "$FAKE_DIR/$1"; }  # $1 = new-split|new-surface|new-pane
set_tree_n() { printf '%s' "$2" > "$FAKE_DIR/tree.$1"; }        # $1 = which tree read

# Composed titles this run: the adapter stamps these, so the post-rename trees
# below have to carry them verbatim or verification reports a mis-target.
MT1="impl.1:$RUN_ID lbl"; MT2="impl.2:$RUN_ID lbl"; MTA="aux:$RUN_ID lbl"

# T_SLOT1 with one more surface — the tree as it looks AFTER a successful stamp.
slot1_plus() { tree "$(workspace workspace:1 "${S1_PANES[@]}" "$(pane pane:30 2 "$1|$2")")"; }

# A full, all-RUNNING quadrant. Slot 1's pane deliberately carries a SECOND
# surface so the overflow tie-break is discriminating: fewest-surfaces wins, so
# the expected answer is slot 2's pane, NOT the lowest-numbered one.
FULL_PANES=(
  "$(pane pane:44 0 'surface:65|impl.1:1700000011-1-1 a' 'surface:66|zsh')"
  "$(pane pane:45 1 'surface:70|impl.2:1700000012-1-1 b')"
  "$(pane pane:46 2 'surface:80|impl.3:1700000013-1-1 c')"
  "$(pane pane:47 3 'surface:90|impl.4:1700000014-1-1 d')"
)
T_FULL="$(tree "$(workspace workspace:1 "${FULL_PANES[@]}")")"
full_plus() { tree "$(workspace workspace:1 "${FULL_PANES[@]}" "$(pane pane:30 4 "$1|$2")")"; }

# --- CREATE: slot 1 busy+running -> targeted split down, send, managed stamp
running 1700000001-1-1
reset_fake; set_tree "$T_SLOT1"; set_tree_n 2 "$(slot1_plus surface:51 "$MT2")"; creates new-split
adapter implementer
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:51" ] && ok "create prints the json-captured ref" || bad "create prints the json-captured ref" "rc=$RC out=$OUT"
grep -qF -- '--json new-split down --surface surface:65' "$FAKE_LOG" && ok "slot 2 splits down off slot 1's surface" || bad "slot 2 splits down off slot 1's surface" "$(cat "$FAKE_LOG")"
grep -qF -- "send --surface surface:51 -- bash $LAUNCHER" "$FAKE_LOG" && ok "send targets the newly created surface" || bad "send targets the newly created surface" "$(cat "$FAKE_LOG")"
grep -qF -- "rename-tab --surface surface:51 -- $MT2" "$FAKE_LOG" && ok "rename carries the managed impl.2 prefix" || bad "rename carries the managed impl.2 prefix" "$(cat "$FAKE_LOG")"
[ "$(grep -c 'rename-tab' "$FAKE_LOG")" -eq 1 ] && ok "a rename that verifies issues no repair" || bad "a rename that verifies issues no repair" "$(cat "$FAKE_LOG")"

# --- ...and every created call carries --workspace: a ref with no workspace
# context resolves to not_found (probe P5). It is appended by split_capture
# rather than written at each call site, so no site can forget it.
reset_fake; set_tree "$T_SLOT1"; set_tree_n 2 "$(slot1_plus surface:51 "$MT2")"; creates new-split
OUT="$(CMUX_WORKSPACE_ID="$WS_UUID" PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>"$TMP/err")"
grep -qxF -- "--json new-split down --surface surface:65 --workspace $WS_UUID" "$FAKE_LOG" && ok "a created split carries --workspace" || bad "a created split carries --workspace" "$(cat "$FAKE_LOG")"

# --- REUSE: a finished slot is typed into, never recreated and never respawned.
# Probe P4: respawn-pane REPLACES the surface's process and the surface closes
# when that process exits — live, it destroyed surface:67 and took its pane with
# it, so respawning to reuse destroys the thing being reused. Reuse is `send`
# (user-approved deviation 2026-07-21; the spec's intent is unchanged).
mkdir -p "$PANE_STATE_DIR/runs/1700000001-1-1"
printf 'DONE\n' > "$PANE_STATE_DIR/runs/1700000001-1-1/agent-exit"
reset_fake; set_tree "$T_SLOT1"
set_tree_n 2 "$(tree "$(workspace workspace:1 "$(pane pane:1 0 'surface:10|zsh')" "$(pane pane:44 1 "surface:65|$MT1")")")"
adapter implementer
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:65" ] && ok "reuse prints the reused ref" || bad "reuse prints the reused ref" "rc=$RC out=$OUT"
grep -qF -- "send --surface surface:65 -- bash $LAUNCHER" "$FAKE_LOG" && ok "reuse sends into the surviving shell" || bad "reuse sends into the surviving shell" "$(cat "$FAKE_LOG")"
grep -Eq '(^|--json )(new-split|new-surface|new-pane)' "$FAKE_LOG" && bad "reuse creates nothing" "$(cat "$FAKE_LOG")" || ok "reuse creates nothing"
grep -q 'respawn' "$FAKE_LOG" && bad "reuse never respawns (P4: respawn destroys the surface)" "$(cat "$FAKE_LOG")" || ok "reuse never respawns (P4: respawn destroys the surface)"
grep -qF -- "rename-tab --surface surface:65 -- $MT1" "$FAKE_LOG" && ok "reuse restamps the surface for the new run" || bad "reuse restamps the surface for the new run" "$(cat "$FAKE_LOG")"
rm -f "$PANE_STATE_DIR/runs/1700000001-1-1/agent-exit"

# --- TAB overflow: a full busy quadrant tabs the fewest-surfaces slot
for r in 1700000011-1-1 1700000012-1-1 1700000013-1-1 1700000014-1-1; do running "$r"; done
reset_fake; set_tree "$T_FULL"; set_tree_n 2 "$(full_plus surface:51 "$MT2")"; creates new-surface
adapter implementer
grep -qF -- '--json new-surface --pane pane:45' "$FAKE_LOG" && ok "overflow tabs the fewest-surfaces slot" || bad "overflow tabs the fewest-surfaces slot" "$(cat "$FAKE_LOG")"
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:51" ] && ok "overflow prints the tabbed surface ref" || bad "overflow prints the tabbed surface ref" "rc=$RC out=$OUT"

# --- AUX create: the new column is anchored on the RIGHTMOST pane's surface.
# `new-pane --direction right` is never used: it has no anchor flag and splits
# relative to the CURRENT pane, which is the caller's own far-left main session,
# so live it landed the aux column 2nd from left (observed 2026-07-21, Task 8).
# pane:47 is T_FULL's max-index pane, so surface:90 is the anchor; a fixture
# whose panes carried no "index" would yield "aux-create env" and a bare
# `new-split right`, which is what makes this assertion load-bearing.
reset_fake; set_tree "$T_FULL"; set_tree_n 2 "$(full_plus surface:51 "$MTA")"
creates new-split
adapter aux
grep -qF -- '--json new-split right --surface surface:90' "$FAKE_LOG" && ok "aux anchors the new column on the rightmost pane's surface" || bad "aux anchors the new column on the rightmost pane's surface" "$(cat "$FAKE_LOG")"
grep -q 'new-pane' "$FAKE_LOG" && bad "aux-create never calls new-pane (it cannot target the rightmost pane)" "$(cat "$FAKE_LOG")" || ok "aux-create never calls new-pane (it cannot target the rightmost pane)"
grep -qF -- "rename-tab --surface surface:51 -- $MTA" "$FAKE_LOG" && ok "aux rename carries the aux prefix" || bad "aux rename carries the aux prefix" "$(cat "$FAKE_LOG")"

# --- ...and with no usable pane the anchor is env-implicit: a bare split right.
reset_fake; set_tree "$(tree "$(workspace workspace:1)")"; set_tree_n 2 "$(tree "$(workspace workspace:1 "$(pane pane:30 0 "surface:51|$MTA")")")"
creates new-split
adapter aux
grep -qxF -- '--json new-split right' "$FAKE_LOG" && ok "aux with no usable pane splits right env-implicitly" || bad "aux with no usable pane splits right env-implicitly" "$(cat "$FAKE_LOG")"

# --- TOCTOU: the plan target vanishes -> exactly ONE re-derivation, then the
# legacy floor, still exit 0. Tree reads on this path: derive, one re-derive,
# and the legacy stamp's verification read = 3. CEILING = 5. The 9th tree read
# is scripted to fail so an unbounded-retry mutation blows the ceiling and lands
# on legacy instead of hanging the suite.
reset_fake; set_tree "$T_FULL"; set_tree_n 3 "$(full_plus surface:42 lbl)"
printf '1' > "$FAKE_DIR/new-surface.rc"; printf '1' > "$FAKE_DIR/tree.rc.9"; split_ok
adapter implementer
[ "$RC" -eq 0 ] && ok "TOCTOU path stays exit 0" || bad "TOCTOU path stays exit 0" "rc=$RC $ERR"
[ "$(printf '%s' "$ERR" | grep -c 'plan target vanished')" -eq 1 ] && ok "exactly one re-derivation, not a loop" || bad "exactly one re-derivation, not a loop" "$ERR"
[ "$(grep -c '^--json tree' "$FAKE_LOG")" -lt 5 ] && ok "tree reads stay under the ceiling" || bad "tree reads stay under the ceiling" "reads=$(grep -c '^--json tree' "$FAKE_LOG")"
grep -qxF -- 'new-split down' "$FAKE_LOG" && ok "TOCTOU falls to the legacy floor" || bad "TOCTOU falls to the legacy floor" "$(cat "$FAKE_LOG")"

# --- VERIFY-AFTER-RENAME (probe P6). rename-tab resolves --tab -> --surface ->
# $CMUX_TAB_ID/$CMUX_SURFACE_ID -> the FOCUSED tab, and an unresolvable ref
# falls through that chain WITHOUT erroring (proven live against surface:9999 at
# exit 0). So the stamp can land on an innocent surface — here surface:99, the
# user's own main session — while cmux reports success. The adapter re-reads the
# tree once, repairs the victim, and leaves the intended surface unmanaged.
T_VICTIM="$(tree "$(workspace workspace:1 \
  "$(pane pane:1 0 'surface:10|zsh' 'surface:99|main session')" \
  "$(pane pane:44 1 'surface:65|impl.1:1700000001-1-1 taskA')")")"
T_VICTIM_POST="$(tree "$(workspace workspace:1 \
  "$(pane pane:1 0 'surface:10|zsh' "surface:99|$MT2")" \
  "$(pane pane:44 1 'surface:65|impl.1:1700000001-1-1 taskA')" \
  "$(pane pane:30 2 'surface:51|zsh')")")"
reset_fake; set_tree "$T_VICTIM"; set_tree_n 2 "$T_VICTIM_POST"; creates new-split
adapter implementer
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:51" ] && ok "a mis-targeted rename never fails the dispatch" || bad "a mis-targeted rename never fails the dispatch" "rc=$RC out=$OUT"
printf '%s' "$ERR" | grep -q 'MIS-TARGETED' && ok "mis-target breadcrumb fires" || bad "mis-target breadcrumb fires" "$ERR"
grep -qF -- 'rename-tab --surface surface:99 -- main session' "$FAKE_LOG" && ok "collateral victim is renamed back" || bad "collateral victim is renamed back" "$(cat "$FAKE_LOG")"
[ "$(grep -c -- 'rename-tab --surface surface:51' "$FAKE_LOG")" -eq 1 ] && ok "intended surface left unmanaged, not re-stamped" || bad "intended surface left unmanaged, not re-stamped" "$(cat "$FAKE_LOG")"

# --- a launcher path with no run-id in it stamps a bare, unmanaged title
ODD="$PANE_STATE_DIR/runs/oddname"; mkdir -p "$ODD"
printf '#!/usr/bin/env bash\necho hi\n' > "$ODD/launch.sh"; chmod 700 "$ODD/launch.sh"
reset_fake; set_tree "$T_SLOT1"; set_tree_n 2 "$(slot1_plus surface:51 lbl)"; creates new-split
OUT="$(PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$ODD/launch.sh" 2>"$TMP/err")"
grep -qF -- 'rename-tab --surface surface:51 -- lbl' "$FAKE_LOG" && ok "no run-id -> bare unmanaged title" || bad "no run-id -> bare unmanaged title" "$(cat "$FAKE_LOG")"

# --- a created ref that is not a surface is never sent into. `jq -e` only
# rejects null/false, so an empty or pane-shaped ref would otherwise reach
# `send --surface` blind; the shape is checked exactly as legacy_open checks
# its own. Both derivations get the bad shape, the legacy floor gets a good one.
reset_fake; set_tree "$T_SLOT1"; set_tree_n 3 "$(slot1_plus surface:42 lbl)"
printf '{"surface_ref":"pane:9"}\n' > "$FAKE_DIR/new-split.1"
printf '{"surface_ref":"pane:9"}\n' > "$FAKE_DIR/new-split.2"
split_ok
adapter implementer
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:42" ] && ok "a non-surface created ref falls to the legacy floor" || bad "a non-surface created ref falls to the legacy floor" "rc=$RC out=$OUT"
grep -q -- 'send .*--surface pane:9' "$FAKE_LOG" && bad "a non-surface ref is never sent into" "$(cat "$FAKE_LOG")" || ok "a non-surface ref is never sent into"

# --- a launcher path containing a space is escaped before it is sent. The sent
# text has SHELL semantics (probe P4: 'A B' survived as one argument), and
# validate_open_pane_args constrains only the run-id segment — the state-root
# prefix is interpolated from $PANE_STATE_DIR/$HOME verbatim, so a home like
# "/Users/Mark Suyat" yields an ACCEPTED launcher path with a space in it.
# Unquoted, `bash /Users/Mark Suyat/.../launch.sh` runs `bash /Users/Mark`.
SP_DIR="$TMP/sp ace"; mkdir -p "$SP_DIR/runs/1700000020-1-1"
SP_LAUNCHER="$SP_DIR/runs/1700000020-1-1/launch.sh"
printf '#!/usr/bin/env bash\necho hi\n' > "$SP_LAUNCHER"; chmod 700 "$SP_LAUNCHER"
reset_fake; set_tree "$T_EMPTY"; creates new-split
set_tree_n 2 "$(tree "$(workspace workspace:1 "$(pane pane:1 0 'surface:10|zsh')" \
  "$(pane pane:30 1 "surface:51|impl.1:1700000020-1-1 lbl")")")"
OUT="$(PANE_STATE_DIR="$SP_DIR" PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$SP_LAUNCHER" 2>"$TMP/err")"
grep -qF -- "bash $SP_LAUNCHER" "$FAKE_LOG" && bad "space in a launcher path is escaped before send" "$(cat "$FAKE_LOG")" || ok "space in a launcher path is escaped before send"
grep -qF -- "bash ${SP_LAUNCHER// /\\ }" "$FAKE_LOG" && ok "the escaped launcher still names the real path" || bad "the escaped launcher still names the real path" "$(cat "$FAKE_LOG")"

# --- cmux version gate -------------------------------------------------------
# The layout logic is calibrated against ONE cmux release. layout_rightmost_surface
# in particular ships a max-index HEURISTIC (Correction 27: `index` is traversal
# order, not left-to-right), and every assertion in this file drives a FAKE binary
# — so a real cmux that walks panes differently mis-places the aux column with the
# whole suite still green. The version is the one thing that IS checkable, so a
# mismatch must be announced loudly and durably. It must never degrade: an upgrade
# silently switching the feature off is the failure this gate exists to prevent.
#
# The setup below is a genuinely SUCCEEDING layout path (slot 1 created, stamped,
# and verified against the second tree read), not the legacy floor — otherwise
# "still dispatches" would pass on surface:42 from split_ok and prove nothing.
VER_MARKER="$PANE_STATE_DIR/cmux-version-mismatch"
ver_setup() {
  reset_fake; rm -f "$VER_MARKER"; set_tree "$T_EMPTY"; creates new-split
  set_tree_n 2 "$(tree "$(workspace workspace:1 "$(pane pane:1 0 'surface:10|zsh')" \
    "$(pane pane:30 1 "surface:51|$MT1")")")"
}

# Guard the guard: the setup must reach the layout path with no version file at
# all. If this ever fails, every assertion below is measuring the legacy floor.
ver_setup; adapter implementer
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:51" ] && ok "version-gate baseline reaches the layout path" || bad "version-gate baseline reaches the layout path" "rc=$RC out=$OUT err=$ERR"

ver_setup; printf 'cmux 0.64.20 (100) [14e3400b9]\n' > "$FAKE_DIR/version"
adapter implementer
[ "$OUT" = "surface:51" ] && ok "the pinned version dispatches through the layout path" || bad "the pinned version dispatches through the layout path" "rc=$RC out=$OUT err=$ERR"
printf '%s' "$ERR" | grep -qi 'version' && bad "the pinned version warns about nothing" "$ERR" || ok "the pinned version warns about nothing"
[ -e "$VER_MARKER" ] && bad "the pinned version leaves no marker" "marker exists" || ok "the pinned version leaves no marker"

ver_setup; printf 'cmux 0.65.0 (101) [deadbeef]\n' > "$FAKE_DIR/version"
adapter implementer
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:51" ] && ok "a version mismatch still dispatches (warn, never degrade)" || bad "a version mismatch still dispatches (warn, never degrade)" "rc=$RC out=$OUT err=$ERR"
grep -q '^new-split down$' "$FAKE_LOG" && bad "a version mismatch does not fall to legacy" "$(cat "$FAKE_LOG")" || ok "a version mismatch does not fall to legacy"
printf '%s' "$ERR" | grep -qF '0.65.0' && printf '%s' "$ERR" | grep -qF '0.64.20' \
  && ok "the warning names both the found and the verified version" || bad "the warning names both the found and the verified version" "$ERR"
[ "$(printf '%s' "$ERR" | grep -c .)" -ge 2 ] && ok "the mismatch warning is louder than one line" || bad "the mismatch warning is louder than one line" "$ERR"
grep -qF '0.65.0' "$VER_MARKER" 2>/dev/null && ok "a mismatch leaves a durable marker naming the version" || bad "a mismatch leaves a durable marker naming the version" "$(cat "$VER_MARKER" 2>/dev/null)"

# One warning per dispatch, not per cmux call: the check must run once.
[ "$(grep -c '^version$' "$FAKE_LOG")" -eq 1 ] && ok "the version is checked exactly once per dispatch" || bad "the version is checked exactly once per dispatch" "$(grep -c '^version$' "$FAKE_LOG") calls"

# Fail OPEN: an unreadable version must never warn and never block. A cmux whose
# `version` output shape changed would otherwise cry wolf on every dispatch.
for desc in "version call fails" "version output is unparseable"; do
  ver_setup
  case "$desc" in
    "version call fails")            printf '1\n' > "$FAKE_DIR/version.rc" ;;
    "version output is unparseable") printf 'garbage\n' > "$FAKE_DIR/version" ;;
  esac
  adapter implementer
  [ "$RC" -eq 0 ] && [ "$OUT" = "surface:51" ] && ok "$desc -> dispatch proceeds" || bad "$desc -> dispatch proceeds" "rc=$RC out=$OUT err=$ERR"
  printf '%s' "$ERR" | grep -qi 'version' && bad "$desc -> stays silent" "$ERR" || ok "$desc -> stays silent"
  [ -e "$VER_MARKER" ] && bad "$desc -> leaves no marker" "marker exists" || ok "$desc -> leaves no marker"
done

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
