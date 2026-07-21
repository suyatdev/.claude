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
cat > "$PANE_CMUX_BIN" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
sub=""
for a in "$@"; do case "$a" in --json) ;; *) sub="$a"; break ;; esac; done
[ -f "$FAKE_DIR/$sub" ] && cat "$FAKE_DIR/$sub"
rc=0; [ -f "$FAKE_DIR/$sub.rc" ] && rc="$(cat "$FAKE_DIR/$sub.rc")"
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

# No managed surface anywhere -> the quadrant is empty, slot 1 is the target.
T_EMPTY="$(tree "$(workspace workspace:1 "$(pane pane:1 'surface:10|zsh')")")"
# Slot 1 taken and RUNNING (a run dir with no agent-exit marker) -> slot 2 is
# the target and it must split DOWN off slot 1's own surface ref. Without the
# explicit run dir the missing dir would read as FINISHED and this would be a
# reuse instead.
running 1700000001-1-1
T_SLOT1="$(tree "$(workspace workspace:1 \
  "$(pane pane:1 'surface:10|zsh')" \
  "$(pane pane:44 'surface:65|impl.1:1700000001-1-1 taskA')")")"

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
printf '%s' "$OUT" | grep -q 'DRYRUN: PLAN: aux-create env' && ok "aux role derives the aux plan" || bad "aux role derives the aux plan" "$OUT"
printf '%s' "$OUT" | grep -q "DRYRUN: TITLE: aux:$RUN_ID lbl" && ok "aux role composes the aux title" || bad "aux role composes the aux title" "$OUT"

# --- an unknown role degrades to aux, and its RAW value never escapes
reset_fake; set_tree "$T_EMPTY"
ROLE_BOGUS='evil-role"; id #'
OUT="$(PANE_DRYRUN=1 PANE_AGENT_ROLE="$ROLE_BOGUS" bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>&1)"
printf '%s' "$OUT" | grep -q 'unknown PANE_AGENT_ROLE' && ok "unknown role noted on stderr" || bad "unknown role noted on stderr" "$OUT"
printf '%s' "$OUT" | grep -q "DRYRUN: TITLE: aux:$RUN_ID lbl" && ok "unknown role falls back to aux" || bad "unknown role falls back to aux" "$OUT"
printf '%s\n%s' "$OUT" "$(cat "$FAKE_LOG")" | grep -qF -- "$ROLE_BOGUS" && bad "raw role value never reaches output or argv" "$OUT" || ok "raw role value never reaches output or argv"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
