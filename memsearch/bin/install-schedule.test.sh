#!/usr/bin/env bash
# install-schedule.test.sh — unit tests for install-schedule.
#
# NOTHING here touches the real ~/Library/LaunchAgents or the real launchctl.
# Isolation uses no test-only seam in the production script: HOME is redirected
# to a temp tree (the script derives the LaunchAgents path from it) and a stub
# launchctl is prepended to PATH. A script that needed an override variable to
# be testable would be a script whose real path is never the tested one.
#
# Run: bash memsearch/bin/install-schedule.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/install-schedule"
TEMPLATE="$HERE/../launchd/local.memsearch-index.plist.template"
LABEL="local.memsearch-index"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s\n     %s\n' "$1" "$2"; fail=$((fail+1)); }

# A stub launchctl whose loaded-service set is a file, so bootstrap/bootout/print
# actually agree with each other across calls the way the real one does.
make_stub() { # $1 = stub dir, $2 = "" | "bootstrap-fails"
  mkdir -p "$1"
  cat > "$1/launchctl" <<STUB
#!/usr/bin/env bash
STATE="\${LAUNCHCTL_STATE:?}"
touch "\$STATE"
case "\$1" in
  print)    grep -qxF "\$2" "\$STATE" || { echo "Could not find service" >&2; exit 113; } ;;
  bootout)  grep -qxF "\$2" "\$STATE" || { echo "Boot-out failed: 3: No such process" >&2; exit 3; }
            grep -vxF "\$2" "\$STATE" > "\$STATE.new"; mv "\$STATE.new" "\$STATE" ;;
  bootstrap)
            [ "\${STUB_BOOTSTRAP_FAILS:-0}" = 1 ] && { echo "Bootstrap failed: 5: Input/output error" >&2; exit 5; }
            [ "\${STUB_BOOTSTRAP_LIES:-0}" = 1 ] && exit 0   # exits 0, loads nothing
            echo "\$2/\$(basename "\$3" .plist)" >> "\$STATE" ;;
  *)        exit 99 ;;
esac
exit 0
STUB
  chmod +x "$1/launchctl"
}

STUB_DIR="$TMP/stub"
make_stub "$STUB_DIR"

# $1 fake-home, then args; captures OUT/ERR/RC
run_install() {
  local home="$1"; shift
  OUT="$(HOME="$home" PATH="$STUB_DIR:$PATH" LAUNCHCTL_STATE="$TMP/loaded" \
         "$SCRIPT" "$@" 2>"$TMP/err")"
  RC=$?
  ERR="$(cat "$TMP/err")"
}

fresh_home() { # -> a temp HOME with an empty loaded-service set
  local h="$TMP/home$RANDOM$RANDOM"
  mkdir -p "$h"
  : > "$TMP/loaded"
  printf '%s' "$h"
}

plist_of() { printf '%s/Library/LaunchAgents/%s.plist' "$1" "$LABEL"; }

# ── The committed template hides no absolute path ───────────────────────────
if [ -f "$TEMPLATE" ]; then
  if grep -q '__HOME__' "$TEMPLATE" && ! grep -qE '/Users/|/home/' "$TEMPLATE"; then
    ok "template uses __HOME__ and commits no absolute path"
  else
    bad "template placeholder" "$(grep -nE '/Users/|/home/|__HOME__' "$TEMPLATE")"
  fi
  if plutil -lint "$TEMPLATE" >/dev/null 2>&1; then
    ok "committed template is itself valid plist syntax"
  else
    bad "template plutil -lint" "$(plutil -lint "$TEMPLATE" 2>&1)"
  fi
else
  bad "template exists" "missing: $TEMPLATE"
  bad "template plutil -lint" "missing: $TEMPLATE"
fi

# ── Installing the agent loads it ───────────────────────────────────────────
H="$(fresh_home)"
run_install "$H"
P="$(plist_of "$H")"
if [ "$RC" -eq 0 ] && [ -f "$P" ]; then ok "install exits 0 and renders the plist"
else bad "install" "rc=$RC plist=$P err=$ERR"; fi

if [ -f "$P" ] && [ "$(stat -f '%Lp' "$P")" = "644" ]; then
  ok "rendered plist is mode 0644 (launchd refuses group/world-writable)"
else
  bad "plist mode" "got $( [ -f "$P" ] && stat -f '%Lp' "$P" )"
fi

if [ -f "$P" ] && grep -q "$H/.claude/memsearch/bin/memsearch" "$P" \
   && ! grep -q '__HOME__' "$P"; then
  ok "\$HOME is expanded at install time, placeholder consumed"
else
  bad "render" "$( [ -f "$P" ] && grep -n '__HOME__\|ProgramArguments' -A2 "$P" | head -6)"
fi

if [ -f "$P" ] && plutil -lint "$P" >/dev/null 2>&1; then
  ok "rendered plist passes plutil -lint"
else
  bad "rendered plutil -lint" "$( [ -f "$P" ] && plutil -lint "$P" 2>&1)"
fi

if grep -qxF "gui/$(id -u)/$LABEL" "$TMP/loaded" 2>/dev/null; then
  ok "the job is actually loaded after install"
else
  bad "job loaded" "loaded set: $(cat "$TMP/loaded" 2>/dev/null)"
fi

# ── Installing twice is not an error ────────────────────────────────────────
run_install "$H"
if [ "$RC" -eq 0 ] && [ "$(grep -cxF "gui/$(id -u)/$LABEL" "$TMP/loaded")" = "1" ]; then
  ok "re-install replaces cleanly, exactly one instance loaded"
else
  bad "idempotent install" "rc=$RC loaded=$(cat "$TMP/loaded") err=$ERR"
fi

# ── Uninstalling removes the job and its plist ──────────────────────────────
mkdir -p "$H/.claude/memory-index"
printf 'the index must survive' > "$H/.claude/memory-index/memory.db"
run_install "$H" --uninstall
if [ "$RC" -eq 0 ] && [ ! -f "$P" ] && ! grep -qxF "gui/$(id -u)/$LABEL" "$TMP/loaded"; then
  ok "uninstall boots the job out and removes the plist"
else
  bad "uninstall" "rc=$RC plist_exists=$( [ -f "$P" ] && echo yes || echo no) err=$ERR"
fi

if [ -f "$H/.claude/memory-index/memory.db" ]; then
  ok "uninstall never touches memory-index/ — removing a schedule is not removing an index"
else
  bad "uninstall touched the index" "memory.db is gone"
fi

# ── Uninstalling when nothing is installed is not an error ──────────────────
H2="$(fresh_home)"
run_install "$H2" --uninstall
if [ "$RC" -eq 0 ]; then ok "uninstall with nothing installed is a no-op success"
else bad "uninstall no-op" "rc=$RC err=$ERR"; fi

# ── A malformed plist is never bootstrapped ─────────────────────────────────
# A real plutil failure from a real malformed template, not a mocked one: the
# script is copied into a tree whose template is broken.
BROKEN="$TMP/broken"
mkdir -p "$BROKEN/bin" "$BROKEN/launchd"
cp "$SCRIPT" "$BROKEN/bin/install-schedule"
printf '<?xml version="1.0"?>\n<plist version="1.0"><dict><key>Label</key>\n' \
  > "$BROKEN/launchd/local.memsearch-index.plist.template"
H3="$(fresh_home)"
OUT="$(HOME="$H3" PATH="$STUB_DIR:$PATH" LAUNCHCTL_STATE="$TMP/loaded" \
       "$BROKEN/bin/install-schedule" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
if [ "$RC" -eq 1 ] && [ ! -s "$TMP/loaded" ] && [ ! -f "$(plist_of "$H3")" ]; then
  ok "malformed plist: exit 1, nothing bootstrapped, nothing left behind"
else
  bad "malformed plist" "rc=$RC loaded=$(cat "$TMP/loaded") err=$ERR"
fi
case "$OUT" in
  (*[Ii]nstalled*|*[Ss]uccess*) bad "malformed plist printed success" "$OUT";;
  (*) ok "malformed plist prints no success message";;
esac

# ── A failed bootstrap is not reported as success ───────────────────────────
H4="$(fresh_home)"
OUT="$(HOME="$H4" PATH="$STUB_DIR:$PATH" LAUNCHCTL_STATE="$TMP/loaded" \
       STUB_BOOTSTRAP_FAILS=1 "$SCRIPT" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
if [ "$RC" -eq 2 ]; then ok "failed bootstrap exits 2"
else bad "failed bootstrap" "rc=$RC err=$ERR"; fi
case "$ERR" in
  (*bootstrap*) ok "failed bootstrap names the failing step on stderr";;
  (*) bad "failed bootstrap stderr" "$ERR";;
esac

# ── A bootstrap that reports success but loads nothing is a failed install ──
# The exit code is not the authority; the loaded-service set is.
H4b="$(fresh_home)"
OUT="$(HOME="$H4b" PATH="$STUB_DIR:$PATH" LAUNCHCTL_STATE="$TMP/loaded" \
       STUB_BOOTSTRAP_LIES=1 "$SCRIPT" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
if [ "$RC" -eq 2 ] && [ ! -s "$TMP/loaded" ]; then
  ok "a lying bootstrap is caught by verification, not believed"
else
  bad "lying bootstrap" "rc=$RC out=$OUT err=$ERR"
fi

# ── An unwritable LaunchAgents directory fails closed ───────────────────────
H5="$(fresh_home)"
mkdir -p "$H5/Library/LaunchAgents"
chmod 500 "$H5/Library/LaunchAgents"
run_install "$H5"
if [ "$RC" -eq 3 ] && [ ! -f "$(plist_of "$H5")" ]; then
  ok "unwritable LaunchAgents: exit 3, no plist left behind"
else
  bad "unwritable LaunchAgents" "rc=$RC err=$ERR"
fi
chmod 700 "$H5/Library/LaunchAgents"

# ── The interval and the log destination are what R6 specifies ─────────────
H6="$(fresh_home)"
run_install "$H6"
P6="$(plist_of "$H6")"
if [ -f "$P6" ] \
   && [ "$(plutil -extract StartInterval raw "$P6" 2>/dev/null)" = "21600" ] \
   && [ "$(plutil -extract RunAtLoad raw "$P6" 2>/dev/null)" = "true" ] \
   && [ "$(plutil -extract StandardOutPath raw "$P6" 2>/dev/null)" \
        = "$H6/.claude/memory-index/scheduled-index.log" ]; then
  ok "plist carries the 6h interval, RunAtLoad, and its own log path"
else
  bad "plist keys" "$( [ -f "$P6" ] && plutil -p "$P6" | head -20)"
fi

# PATH is load-bearing, not boilerplate: launchctl getenv PATH is empty, so
# without this key the job dies at exec every 6h while the installer says OK.
if [ -f "$P6" ] && plutil -extract EnvironmentVariables.PATH raw "$P6" 2>/dev/null \
     | grep -q '/opt/homebrew/bin'; then
  ok "plist pins a PATH that can find uv"
else
  bad "plist PATH" "$( [ -f "$P6" ] && plutil -extract EnvironmentVariables raw "$P6" 2>&1)"
fi

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ]
