#!/usr/bin/env bash
# adapters.test.sh — dry-run + validation tests; opens no real panes.
# Run: bash panes/adapters.test.sh
set -u
ADAPTERS="$(cd "$(dirname "$0")" && pwd)/adapters"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PANE_STATE_DIR="$TMP/state"
RUN_DIR="$PANE_STATE_DIR/runs/1700000000-1-1"
mkdir -p "$RUN_DIR"
LAUNCHER="$RUN_DIR/launch.sh"
printf '#!/usr/bin/env bash\necho hi\n' > "$LAUNCHER"; chmod 700 "$LAUNCHER"

pass=0; fail=0
run_case() { # $1 desc, $2 want-exit, $3 adapter, $4 title, $5 launcher, $6 grep-pattern-or-empty
  local desc="$1" want="$2" adapter="$3" title="$4" launcher="$5" pat="$6" out got
  out=$(PANE_DRYRUN=1 bash "$ADAPTERS/$adapter.sh" open_pane "$title" "$launcher" 2>&1)
  got=$?
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL — %s (want exit %s, got %s: %s)\n' "$desc" "$want" "$got" "$out"; fail=$((fail+1)); return
  fi
  if [ -n "$pat" ] && ! printf '%s' "$out" | grep -qF "$pat"; then
    printf 'FAIL — %s (missing %s in: %s)\n' "$desc" "$pat" "$out"; fail=$((fail+1)); return
  fi
  printf 'ok   — %s\n' "$desc"; pass=$((pass+1))
}

tab_case() { # $1 desc, $2 want-exit, $3 adapter, $4 surface-ref, $5 title, $6 launcher, $7 grep-pattern-or-empty
  local desc="$1" want="$2" adapter="$3" ref="$4" title="$5" launcher="$6" pat="$7" out got
  out=$(PANE_DRYRUN=1 bash "$ADAPTERS/$adapter.sh" open_tab "$ref" "$title" "$launcher" 2>&1)
  got=$?
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL — %s (want exit %s, got %s: %s)\n' "$desc" "$want" "$got" "$out"; fail=$((fail+1)); return
  fi
  if [ -n "$pat" ] && ! printf '%s' "$out" | grep -qF "$pat"; then
    printf 'FAIL — %s (missing %s in: %s)\n' "$desc" "$pat" "$out"; fail=$((fail+1)); return
  fi
  printf 'ok   — %s\n' "$desc"; pass=$((pass+1))
}

for a in cmux tmux iterm terminal; do
  run_case "$a dryrun emits commands"      0  "$a" "pane: judge" "$LAUNCHER" "DRYRUN:"
  run_case "$a dryrun names launcher"      0  "$a" "pane: judge" "$LAUNCHER" "$LAUNCHER"
  run_case "$a rejects shell-meta title"   65 "$a" 'x"; rm -rf /' "$LAUNCHER" ""
  run_case "$a rejects outside launcher"   65 "$a" "ok title" "/tmp/evil.sh" ""
  run_case "$a rejects missing launcher"   65 "$a" "ok title" "$RUN_DIR/absent.sh" ""
done
run_case "cmux dryrun shows new-split"     0  cmux "t" "$LAUNCHER" "new-split down"
run_case "tmux dryrun shows split-window"  0  tmux "t" "$LAUNCHER" "split-window"
run_case "iterm dryrun shows osascript"    0  iterm "t" "$LAUNCHER" "osascript"
run_case "terminal dryrun shows do script" 0  terminal "t" "$LAUNCHER" "do script"

# --- open_tab: surface-ref validation + per-adapter dryrun
for a in cmux tmux iterm terminal; do
  tab_case "$a open_tab dryrun ok"               0  "$a" "surface:42" "worker.1" "$LAUNCHER" "$LAUNCHER"
  tab_case "$a open_tab rejects bad surface ref" 65 "$a" 'surface 42; rm' "worker.1" "$LAUNCHER" ""
  tab_case "$a open_tab rejects bad title"       65 "$a" "surface:42" 'bad"title' "$LAUNCHER" ""
  bash "$ADAPTERS/$a.sh" bogus "surface:42" "worker.1" "$LAUNCHER" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq 64 ]; then printf 'ok   — %s rejects unknown verb\n' "$a"; pass=$((pass+1))
  else printf 'FAIL — %s rejects unknown verb (got %s)\n' "$a" "$got"; fail=$((fail+1)); fi
done
tab_case "cmux open_tab dryrun names new-surface" 0 cmux "surface:42" "worker.1" "$LAUNCHER" "new-surface"

# --- cmux open_tab live path: surface->pane resolution against the Task 1 probe
# fixture, driven by a fake cmux (precedent: PANE_CMUX_BIN). Opens no real panes.
FAKE_CMUX="$TMP/fake-cmux.sh"
cat > "$FAKE_CMUX" <<FCE
#!/usr/bin/env bash
case "\$*" in
  *"--json tree"*) cat "$ADAPTERS/fixtures/tab-live.json" ;;
  *"new-surface"*) echo '{"surface_ref":"surface:777"}' ;;
  *) : ;;
esac
FCE
chmod 700 "$FAKE_CMUX"

out=$(PANE_CMUX_BIN="$FAKE_CMUX" bash "$ADAPTERS/cmux.sh" open_tab "surface:77" "worker.1" "$LAUNCHER" 2>/dev/null)
got=$?
if [ "$got" -eq 0 ] && [ "$out" = "surface:777" ]; then
  printf 'ok   — cmux open_tab live resolves surface to pane\n'; pass=$((pass+1))
else
  printf 'FAIL — cmux open_tab live resolves surface to pane (got %s: %s)\n' "$got" "$out"; fail=$((fail+1))
fi

PANE_CMUX_BIN="$FAKE_CMUX" bash "$ADAPTERS/cmux.sh" open_tab "surface:9999" "worker.1" "$LAUNCHER" >/dev/null 2>&1
got=$?
if [ "$got" -eq 1 ]; then
  printf 'ok   — cmux open_tab degrades on unknown surface\n'; pass=$((pass+1))
else
  printf 'FAIL — cmux open_tab degrades on unknown surface (got %s)\n' "$got"; fail=$((fail+1))
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
