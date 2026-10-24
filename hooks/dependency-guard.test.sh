#!/usr/bin/env bash
# dependency-guard.test.sh -- drives hooks/dependency-guard.sh with real PreToolUse payloads
# (hook_event_name included), one case per hook Scenario in
# docs/features/dependency-vetting-guard.md, plus the broken-guard paths.
# Run: bash hooks/dependency-guard.test.sh
#
# Isolation: every run points the hook at a mktemp -d state dir through
# DEPENDENCY_GUARD_STATE_DIR and at a fake $HOME, so neither the real hooks/state/ nor the real
# home is touched (a closing check compares the real log's stat before and after). No network, no
# install: commands are DATA on stdin, nothing here executes them.
#
# Falsification: DEPENDENCY_GUARD_HOOK=<script> runs the whole suite against a stub instead (an
# always-allow and an always-deny stub were used to prove each case can fail). A stub run never
# writes a test marker.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HERE="$(cd "$(dirname "$0")" && pwd -P)"
HOOK="${DEPENDENCY_GUARD_HOOK:-$HERE/dependency-guard.sh}"
LIB="$HERE/lib"
VETTER="$HERE/bin/vet-dependency"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROJ="$TMP/proj"; FAKE_HOME="$TMP/home"
mkdir -p "$PROJ" "$FAKE_HOME"
STATE=""; OUT=""; ERR=""; RC=0; n_state=0; n_copy=0
pass=0; fail=0
TAB="$(printf '\t')"
REAL_LOG="$HERE/state/dependency-guard.log"
real_log_before="$(stat -f '%m %z' "$REAL_LOG" 2>&1 || stat -c '%Y %s' "$REAL_LOG" 2>&1)"

# ------------------------------------------------------------------ payloads
bash_payload() { /usr/bin/jq -nc --arg c "$1" \
  '{hook_event_name:"PreToolUse",session_id:"sess-test",tool_name:"Bash",tool_input:{command:$c}}'; }
edit_payload() { /usr/bin/jq -nc --arg f "$1" --arg o "$2" --arg n "$3" \
  '{hook_event_name:"PreToolUse",session_id:"sess-test",tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}'; }
write_payload() { /usr/bin/jq -nc --arg f "$1" --arg c "$2" \
  '{hook_event_name:"PreToolUse",session_id:"sess-test",tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }

# ------------------------------------------------------------------ state + records
new_state() { n_state=$((n_state+1)); STATE="$TMP/state.$n_state"; mkdir -p "$STATE"; }

mkrec() { # eco name version age_hours complete [signals-json] [reasons-json]
  python3 -I - "$LIB" "$STATE/vetting" "$1" "$2" "$3" "$4" "$5" "${6:-[]}" "${7:-[]}" <<'PY'
import datetime, json, sys
lib, store, eco, name, version, age_hours, complete, signals, reasons = sys.argv[1:10]
sys.path.insert(0, lib)
import vetting_record as vr
now = datetime.datetime.now(datetime.timezone.utc)
vr.write_record(store, {
    "schema": 1, "ecosystem": eco, "name": name, "version": version,
    "vetted_at": vr.format_vetted_at(now - datetime.timedelta(hours=float(age_hours))),
    "complete": complete == "true", "incomplete_reasons": json.loads(reasons),
    "signals": json.loads(signals), "report": "hooks/state/vetting/report.md"})
PY
}

log_count() { if [ -f "$STATE/dependency-guard.log" ]; then wc -l < "$STATE/dependency-guard.log" | tr -d ' '; else echo 0; fi; }

# ------------------------------------------------------------------ running
run_with() { # $1 hook script, $2 payload; env for the hook comes from the caller's prefix
  local errf="$TMP/err.out"
  OUT="$(cd "$PROJ" && printf '%s' "$2" | HOME="$FAKE_HOME" DEPENDENCY_GUARD_STATE_DIR="$STATE" bash "$1" 2>"$errf")"; RC=$?
  ERR="$(cat "$errf")"
}
run() { run_with "$HOOK" "$1"; }

say_ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
say_bad() { printf 'FAIL — %s\n  %s\n' "$1" "$2"; fail=$((fail+1)); }

has_all() { # $1 desc, $2 haystack label, $3 haystack, rest: needles; returns 0 when all present
  local desc="$1" label="$2" hay="$3" needle; shift 3
  for needle in "$@"; do
    case "$hay" in *"$needle"*) ;; *) say_bad "$desc" "want $label to contain: $needle"$'\n'"  got: $hay"; return 1 ;; esac
  done
}
lacks() { # $1 desc, $2 haystack, $3 needle it must not hold, $4 text it MUST hold (so a stub that
  # says nothing cannot pass: an absence only counts when the real message is there)
  case "$2" in *"$4"*) ;; *) say_bad "$1" "want the real message (containing: $4); got: $2"; return ;; esac
  case "$2" in *"$3"*) say_bad "$1" "must not contain: $3"$'\n'"  got: $2" ;; *) say_ok "$1" ;; esac
}

check_allow() { # $1 desc  (uses RC/OUT/ERR)
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then say_ok "$1"
  else say_bad "$1" "want exit 0 with no output; got rc=$RC out=[$OUT] err=[$ERR]"; fi
}
check_deny() { # $1 desc, rest needles
  local desc="$1"; shift
  if [ "$RC" -ne 2 ] || [ -n "$OUT" ]; then say_bad "$desc" "want exit 2 and empty stdout; got rc=$RC out=[$OUT] err=[$ERR]"; return; fi
  has_all "$desc" stderr "$ERR" "$@" && say_ok "$desc"
}
ASK_PREFIX='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"'
ask_reason() { printf '%s' "$OUT" | /usr/bin/jq -r '.hookSpecificOutput.permissionDecisionReason'; }
check_ask() { # $1 desc, rest needles (searched in the decoded reason)
  local desc="$1" reason; shift
  if [ "$RC" -ne 0 ]; then say_bad "$desc" "want exit 0; got rc=$RC out=[$OUT] err=[$ERR]"; return; fi
  case "$OUT" in "$ASK_PREFIX"*'"}}') ;; *) say_bad "$desc" "stdout is not the compact ask object: [$OUT]"; return ;; esac
  if [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -ne 1 ]; then say_bad "$desc" "ask is not one line"; return; fi
  printf '%s' "$OUT" | /usr/bin/jq -e '(keys == ["hookSpecificOutput"]) and (.hookSpecificOutput | keys == ["hookEventName","permissionDecision","permissionDecisionReason"])' >/dev/null \
    || { say_bad "$desc" "ask object has the wrong keys: [$OUT]"; return; }
  reason="$(ask_reason)"
  has_all "$desc" reason "$reason" "$@" && say_ok "$desc"
}

allow_cmd() { run "$(bash_payload "$2")"; check_allow "$1"; }
deny_cmd() { local d="$1" c="$2"; shift 2; run "$(bash_payload "$c")"; check_deny "$d" "$@"; }
ask_cmd() { local d="$1" c="$2"; shift 2; run "$(bash_payload "$c")"; check_ask "$d" "$@"; }

# a copy of the hook + libs that a case may break without touching the real ones
make_copy() { # sets COPY; $1 = space-separated lib files to leave out. Not run in a $(...) subshell:
  # the counter must advance in the caller, or every copy lands in the same directory.
  n_copy=$((n_copy+1)); COPY="$TMP/copy.$n_copy"
  local f
  mkdir -p "$COPY/lib"; cp "$HOOK" "$COPY/dependency-guard.sh"
  for f in shell_segments.py classify-install-command.py classify-manifest-edit.py vetting_record.py decide-dependency.py; do
    case " ${1:-} " in *" $f "*) continue ;; esac
    [ -f "$LIB/$f" ] && cp "$LIB/$f" "$COPY/lib/$f"
  done
}

printf 'dependency-guard hook: scenarios\n'

# ------------------------------------------------------------------ decisions on a command
new_state
deny_cmd "unpinned install is refused (MSG_UNPINNED naming zod@<exact-version>)" "npm install zod" \
  "dependency-guard: npm zod has no exact version" "zod@<exact-version>"
mkrec npm zod 3.23.8 24 true
deny_cmd "range is refused even when vetted" "npm install zod@^3.23.8" "has no exact version" "zod@3.23.8"
ask_cmd "vetted install reaches Mark" "npm install zod@3.23.8" "npm zod@3.23.8" "0 stop" "vetted 1 day ago"
mkrec npm left-pad 1.3.0 2 true '[{"check":"direct_vulns","status":"stop","detail":"1 advisory"},{"check":"typosquat","status":"stop","detail":"x"},{"check":"popularity","status":"caution","detail":"low"}]'
ask_cmd "ask names the stop and caution checks, not just the counts" "npm install left-pad@1.3.0" \
  "2 stop (direct_vulns, typosquat)" "1 caution (popularity)" "vetted 2 hours ago"

new_state
deny_cmd "pinned but unvetted install is stopped with the command to run" "npm install zod@3.23.8" \
  "has no vetting report from the last 7 days" "run: $VETTER npm zod 3.23.8  — then show Mark the report and your recommendation before retrying"
mkrec npm zod 3.23.8 192 true
deny_cmd "stale record (8 days) is treated as missing" "npm install zod@3.23.8" "has no vetting report from the last 7 days"
mkrec npm zod 3.23.8 167 true
ask_cmd "a record just inside 7 days is fresh" "npm install zod@3.23.8" "npm zod@3.23.8" "vetted 6 days ago"

new_state
mkrec pypi requests 2.32.3 24 false '[]' '["transitive scan unsupported for pypi"]'
ask_cmd "incomplete record is disclosed at the prompt" "pip install requests==2.32.3" \
  "pypi requests@2.32.3" "INCOMPLETE: transitive scan unsupported for pypi"
mkrec npm cowsay 1.6.0 24 true
ask_cmd "a runner's ask says it runs from the registry" "npx cowsay@1.6.0 hi" "npm cowsay@1.6.0" "runs from registry"

new_state
before="$(log_count)"
ask_cmd "exemption skips vetting but not the prompt" "VET_EXEMPT=offline-mirror npm install zod@3.23.8" \
  "npm zod@3.23.8" "VET_EXEMPT: offline-mirror"
after="$(log_count)"
[ $((after - before)) -eq 1 ] && say_ok "the exempt ask appends exactly one log line" || say_bad "the exempt ask appends exactly one log line" "log went from $before to $after lines"
last="$(tail -n 1 "$STATE/dependency-guard.log")"
fields="$(printf '%s' "$last" | awk -F'\t' '{print NF}')"
[ "$fields" -eq 7 ] && say_ok "a log line has seven tab-separated fields" || say_bad "a log line has seven tab-separated fields" "got $fields: $last"
case "$last" in *"${TAB}sess-test${TAB}ask${TAB}npm${TAB}zod${TAB}3.23.8${TAB}"*) say_ok "log line carries session, decision, ecosystem, name, version" ;;
  *) say_bad "log line carries session, decision, ecosystem, name, version" "$last" ;; esac
case "$last" in 20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z"$TAB"*) say_ok "log line starts with a UTC timestamp" ;;
  *) say_bad "log line starts with a UTC timestamp" "$last" ;; esac
mode="$(python3 -I -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$STATE/dependency-guard.log")"
[ "$mode" = "0o600" ] && say_ok "the log is created 0600" || say_bad "the log is created 0600" "mode $mode"

new_state
deny_cmd "exemption does not rescue an unpinned install" "VET_EXEMPT=x npm install zod" "has no exact version"
deny_cmd "exemption value with shell metacharacters is ignored" "VET_EXEMPT='a;b' npm install zod@3.23.8" "has no vetting report from the last 7 days"
deny_cmd "exemption value with a space is ignored" "VET_EXEMPT='a b' npm install zod@3.23.8" "has no vetting report from the last 7 days"

new_state
# A deny first, so the log provably works here; the allows after it must then add nothing.
deny_cmd "a deny writes one log line" "npm install zod" "has no exact version"
[ "$(log_count)" -eq 1 ] && say_ok "the deny wrote exactly one line" || say_bad "the deny wrote exactly one line" "log has $(log_count) lines"
allow_cmd "lockfile reinstall passes untouched (npm ci)" "npm ci"
allow_cmd "lockfile reinstall passes untouched (bare npm install)" "npm install"
allow_cmd "unrelated command is untouched" "git status"
allow_cmd "an empty command is untouched" ""
[ "$(log_count)" -eq 1 ] && say_ok "allowed commands write no log line" || say_bad "allowed commands write no log line" "log has $(log_count) lines, want 1"

new_state
deny_cmd "chained install is seen" "cd app && npm install left-pad@1.3.0" "npm left-pad 1.3.0"
deny_cmd "wrapped install is seen" "env FOO=1 sudo npm i zod@3.23.8" "vet-dependency npm zod 3.23.8"
deny_cmd "run-from-registry counts as an install" "npx cowsay@1.6.0 hi" "vet-dependency npm cowsay 1.6.0"
deny_cmd "an npm install alias is an install" "npm isntall left-pad@1.3.0" "vet-dependency npm left-pad 1.3.0"
deny_cmd "--version inside an install is the version, not a help call" "gem install rails --version 7.1.3" "vet-dependency rubygems rails 7.1.3"
deny_cmd "Go module path with several slashes is accepted" "go get golang.org/x/text@v0.3.8" "vet-dependency go golang.org/x/text v0.3.8"
deny_cmd "cargo add without = is a range" "cargo add serde@1.0.210" "has no exact version" "serde@=1.0.210"
deny_cmd "a malformed version is unpinned, so no path is built from it" "pip install 'requests==2.32.3/../evil'" "has no exact version" "requests==<exact-version>"
run "$(bash_payload "pip install 'requests==2.32.3/../evil'")"; lacks "the malformed version is not echoed anywhere" "$ERR" "evil" "has no exact version"
deny_cmd "node_modules/.bin/npm install is still an npm install" "node_modules/.bin/npm install left-pad@1.3.0" "vet-dependency npm left-pad 1.3.0"
deny_cmd "yarn's other name, called directly, is still a yarn install" "node_modules/.bin/yarnpkg add left-pad@1.3.0" "vet-dependency npm left-pad 1.3.0"
for c in 'corepack pnpm add left-pad@1.3.0' 'corepack pnpm@9.0.0 add left-pad@1.3.0'; do
  deny_cmd "corepack is read as the manager it runs: $c" "$c" "vet-dependency npm left-pad 1.3.0"; done
allow_cmd "running the project's own copy directly is not an install" "node_modules/.bin/tsc --noEmit"

# ---- multi-package: every intent is decided, the strongest wins
new_state
mkrec npm zod 3.23.8 24 true
deny_cmd "every package in a multi-package install is decided" "npm install zod@3.23.8 left-pad@1.3.0" "vet-dependency npm left-pad 1.3.0"
before="$(log_count)"; run "$(bash_payload "npm install zod@3.23.8 left-pad@1.3.0")"
[ $(( $(log_count) - before )) -eq 2 ] && say_ok "one log line per intent (an ask and a deny)" || say_bad "one log line per intent (an ask and a deny)" "gained $(( $(log_count) - before ))"
deny_cmd "an unpinned package later in the command still denies" "npm install zod@3.23.8 left-pad" "left-pad@<exact-version>"
deny_cmd "a deny has one line per denied package" "npm install left-pad@1.3.0 lodash@4.17.21 zod@3.23.8" "vet-dependency npm left-pad 1.3.0" "vet-dependency npm lodash 4.17.21"
run "$(bash_payload "npm install left-pad@1.3.0 lodash@4.17.21 zod@3.23.8")"
[ "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" -eq 2 ] && say_ok "two denied packages give two stderr lines (the ask is not in them)" || say_bad "two denied packages give two stderr lines" "$ERR"
mkrec npm left-pad 1.3.0 24 true
ask_cmd "a multi-package ask names every package" "npm install zod@3.23.8 left-pad@1.3.0" "npm zod@3.23.8" "npm left-pad@1.3.0"
run "$(bash_payload "npm install zod@3.23.8 left-pad@1.3.0")"
case "$(ask_reason)" in *"; dependency-guard: npm left-pad@1.3.0"*) say_ok "ask clauses are joined by '; '" ;; *) say_bad "ask clauses are joined by '; '" "$(ask_reason)" ;; esac

# ---- non-registry sources and requirements files
new_state
for c in 'npm install ./local-pkg' 'npm install github:user/repo'; do
  ask_cmd "a non-registry source asks instead of denying: $c" "$c" "not a registry package"; done
ask_cmd "requirements-file install asks, naming the file" "pip install -r requirements.txt" "requirements.txt" "installs everything listed in"
ask_cmd "an invalid package name asks, naming it" "go get a/../b@v1.0.0" "not a valid package name" "a/../b"

# ---- Homebrew (D8)
new_state
deny_cmd "unvetted Homebrew install prints the versionless vetter line" "brew install jq" \
  "dependency-guard: homebrew jq has no vetting report from the last 7 days" "run: $VETTER homebrew jq  — then show Mark"
mkrec homebrew jq 1.7.0 100 false '[]' '["no OSV ecosystem"]'
mkrec homebrew jq 1.7.1 24 false '[]' '["no OSV ecosystem"]'
ask_cmd "Homebrew install finds the newest fresh record" "brew install jq" "jq" "1.7.1" "INCOMPLETE: no OSV ecosystem"
new_state
ask_cmd "Homebrew exemption with no record still asks" "VET_EXEMPT=offline brew install jq" "homebrew jq" "VET_EXEMPT: offline"

# ---- runners (D9 dropped) and MSG_RUNNER_INSTALLER
new_state
deny_cmd "a versionless npx is refused (and says to run the local copy)" "npx tsc --noEmit" \
  "npm tsc has no exact version" "node_modules/.bin/tsc"
deny_cmd "a scoped runner package gets no local-path advice" "npx @scope/tool" "has no exact version"
run "$(bash_payload "npx @scope/tool")"; lacks "scoped: no node_modules/.bin advice" "$ERR" "node_modules/.bin" "has no exact version"
deny_cmd "npx with no local copy and no version is refused" "npx cowsay hi" "has no exact version"
deny_cmd "pnpx is refused without a version" "pnpx tsc" "has no exact version"
deny_cmd "npx -p names an install" "npx -p cowsay cowsay hi" "npm cowsay has no exact version"
deny_cmd "a pinned -p does not pin the command word" "npx -p cowsay@1.6.0 cowsay" "npm cowsay has no exact version"
run "$(bash_payload "uvx ruff")"; lacks "a PyPI runner gets no node_modules advice" "$ERR" "node_modules/.bin" "has no exact version"
for c in 'cd app && npx tsc' '(cd sub) && npx tsc' 'cd a && cd b && npx tsc' 'npx --prefix=/tmp/other tsc' 'npx --yes tsc' \
         'FOO=1 npx tsc' 'env npx tsc' 'time npx tsc' "eval npx tsc '; npx -y cowsay'" 'npx tsc "$(npx -y cowsay)"' \
         'npx tsc `npx -y cowsay`' 'npx tsc; npx -y cowsay'; do
  deny_cmd "a versionless npx is refused in any shape: $c" "$c" "has no exact version"; done
for row in 'npx npm install left-pad@1.3.0|npm' 'npx npm@12.0.1 install left-pad|npm' 'npx NPM install left-pad@1.3.0|NPM' \
           'npx yarnpkg add left-pad@1.3.0|yarnpkg' 'npx corepack pnpm add left-pad|corepack' 'npx pip --version|pip' \
           'VET_EXEMPT=x npx npm@12.0.1 install a|npm'; do
  c="${row%|*}"; p="${row##*|}"
  deny_cmd "a runner naming a package manager is refused: $c" "$c" "would fetch the package manager $p " "run $p directly so the guard can check what it installs"; done
for row in 'npm exec npm@12.0.1 install left-pad|npm exec' 'pnx npm@12.0.1 install left-pad|pnx' \
           'pnpm dlx yarn@1.22.22 add left-pad|pnpm dlx' 'uvx pip==24.2 install requests|uvx'; do
  c="${row%|*}"; r="${row##*|}"
  deny_cmd "every runner naming a package manager is refused: $c" "$c" "dependency-guard: $r would fetch the package manager"; done

# ---- commands the lexer cannot read
new_state
NL=$'\n'
unreadable_pre="cat <<'EOF'${NL}it's a note${NL}EOF${NL}"
ask_cmd "a command the lexer cannot read that names an install tool asks" "${unreadable_pre}npm i zod@3.23.8" "cannot read this command"
ask_cmd "an unreadable command naming bunx asks" "${unreadable_pre}bunx cowsay@1.6.0" "cannot read this command"
ask_cmd "the tool word is matched in any letter case" "${unreadable_pre}NPM i zod@3.23.8" "cannot read this command"
ask_cmd "the tool word is matched as a whole word, not inside a word" "${unreadable_pre}pip3 install x" "cannot read this command"
before="$(log_count)"
allow_cmd "a command the lexer cannot read with no install tool passes" "${unreadable_pre}echo done"
[ $(( $(log_count) - before )) -eq 1 ] && say_ok "an unreadable command with no tool word is logged once" || say_bad "an unreadable command with no tool word is logged once" "gained $(( $(log_count) - before ))"
case "$(tail -n 1 "$STATE/dependency-guard.log")" in *"${TAB}allow-unreadable${TAB}"*) say_ok "the log line says allow-unreadable" ;; *) say_bad "the log line says allow-unreadable" "$(tail -n 1 "$STATE/dependency-guard.log")" ;; esac
allow_cmd "a tool name inside a longer word does not count" "${unreadable_pre}echo gopher npmrc"
before="$(log_count)"; run "$(bash_payload "${unreadable_pre}npm i zod@3.23.8")"
case "$(tail -n 1 "$STATE/dependency-guard.log")" in *"${TAB}cannot-read${TAB}"*) [ $(( $(log_count) - before )) -eq 1 ] && say_ok "cannot-read asks write one log line" || say_bad "cannot-read asks write one log line" "wrong line count" ;;
  *) say_bad "cannot-read asks write one log line" "$(tail -n 1 "$STATE/dependency-guard.log")" ;; esac

# ---- manifest edits
new_state
PKG="$PROJ/package.json"
printf '{\n  "name": "app",\n  "dependencies": {}\n}\n' > "$PKG"
old='"dependencies": {}'
run "$(edit_payload "$PKG" "$old" '"dependencies": {"zod": "3.23.8"}')"
check_deny "manifest edit adding a dependency (no record)" "vet-dependency npm zod 3.23.8"
run "$(edit_payload "$PKG" "$old" '"dependencies": {"zod": "^3.23.8"}')"
check_deny "manifest edit adding a range" "has no exact version" "zod@3.23.8"
mkrec npm zod 3.23.8 24 true
run "$(edit_payload "$PKG" "$old" '"dependencies": {"zod": "3.23.8", "left-pad": "1.3.0"}')"
check_deny "manifest edit adding two dependencies decides both" "vet-dependency npm left-pad 1.3.0"
run "$(edit_payload "$PKG" "$old" '"dependencies": {"zod": "3.23.8"}')"
check_ask "a vetted manifest dependency reaches Mark" "npm zod@3.23.8" "0 stop"
run "$(edit_payload "$PKG" "$old" '"dependencies": {"foo": "file:../foo"}')"
check_ask "a manifest file: dependency is asked about, not refused" "not a registry package" "file:../foo"
run "$(edit_payload "$PKG" "$old" '"dependencies": {')"
check_ask "unparseable package.json asks" "package.json"
run "$(edit_payload "$PKG" '"name": "app"' '"name": "renamed"')"
check_allow "a package.json edit that adds no dependency passes"
run "$(write_payload "$PROJ/package.json" '{"name":"app","dependencies":{"zod":"3.23.8"}}')"
check_ask "Write of package.json with a vetted dependency asks" "npm zod@3.23.8"
run "$(write_payload "$PROJ/Cargo.toml" '[package]')"
check_ask "unparsed manifest: Write of Cargo.toml asks with the dependency-file warning" "Cargo.toml" "dependency"
run "$(write_payload "$PROJ/yarn.lock" 'x')"
check_ask "a lockfile edit asks" "yarn.lock"
run "$(write_payload "$PROJ/requirements.txt" 'requests==2.32.3')"
check_deny "requirements.txt addition is vetted" "vet-dependency pypi requests 2.32.3"
run "$(write_payload "$PROJ/notes.md" 'npm install zod')"
check_allow "a non-manifest Write passes"
run "$(/usr/bin/jq -nc --arg f "$PROJ/a.ipynb" '{hook_event_name:"PreToolUse",session_id:"s",tool_name:"NotebookEdit",tool_input:{notebook_path:$f,new_source:"x"}}')"
check_allow "NotebookEdit of a non-manifest passes"
run "$(/usr/bin/jq -nc --arg f "$PROJ/package.json" '{hook_event_name:"PreToolUse",session_id:"s",tool_name:"NotebookEdit",tool_input:{notebook_path:$f,new_source:"x"}}')"
check_ask "NotebookEdit aimed at a manifest asks" "package.json"
run '{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Read","tool_input":{"file_path":"/x"}}'
check_allow "a tool the guard does not watch passes"
run "$(/usr/bin/jq -nc '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"npm install zod"}}')"
check_allow "hook_event_name other than PreToolUse is allowed with no output"
run "$(/usr/bin/jq -nc '{tool_name:"Bash",tool_input:{command:"npm install zod"}}')"
check_allow "a payload with no hook_event_name is allowed with no output"
run '{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_input":{}}'
check_allow "a Bash payload with no command has nothing to classify"

# ---- source: other (card, "Not from a registry"): the git-host warning, and no name validation
new_state
GITNOTE="downloads from a git host, not vetted, and the code can change unless pinned to a commit"
for c in 'npm install git+https://github.com/u/r.git' 'npm install git://h/r' 'npm install ssh://git@h/r' \
         'npm install git@github.com:u/r.git' 'npm install https://github.com/u/r/tarball/main' \
         'npm install github:u/r' 'npm install gitlab:u/r' 'npm install bitbucket:u/r' 'npm install gist:abc' \
         'npm install user/repo' 'npm install user/repo#abc123' 'npm install foo@github:u/r' \
         'npm install foo@npm:user/repo' 'pip install git+https://github.com/u/r'; do
  ask_cmd "a git source gets the git-host warning: $c" "$c" "not a registry package" "$GITNOTE"
  lacks "a git source is never refused as an invalid name: $c" "$(ask_reason)" "not a valid package name" "not a registry package"
done
for c in 'npm install ./local-pkg' 'npm install file:../x' 'npm install link:../x' 'npm install workspace:*' \
         'npm install x.tgz' 'npm install dist/x.tgz' 'npm install /abs/path' 'npm install https://example.com/x.tgz' \
         'npm install foo@file:../foo' 'pip install ./pkg' 'pip install https://h/x.whl'; do
  ask_cmd "a non-git source asks without the git-host warning: $c" "$c" "not a registry package"
  lacks "a non-git source gets no git-host warning: $c" "$(ask_reason)" "git host" "not a registry package"
done
run "$(bash_payload "npm install github:u/r")"
case "$(tail -n 1 "$STATE/dependency-guard.log")" in
  *"${TAB}ask${TAB}npm${TAB}"*"not a registry package"*) say_ok "the log line for a source:other ask says 'not a registry package'" ;;
  *) say_bad "the log line for a source:other ask says 'not a registry package'" "$(tail -n 1 "$STATE/dependency-guard.log")" ;; esac
lacks "the log line never says invalid name" "$(tail -n 1 "$STATE/dependency-guard.log")" "valid package name" "not a registry package"
old='"dependencies": {}'
for v in 'github:u/r' 'npm:user/repo' 'user/repo#abc123' 'git+https://github.com/u/r.git' 'https://github.com/u/r/tarball/main'; do
  run "$(edit_payload "$PKG" "$old" "\"dependencies\": {\"foo\": \"$v\"}")"
  check_ask "a manifest git value gets the git-host warning: $v" "not a registry package" "$GITNOTE"
done
for v in 'file:../foo' 'link:../foo' 'workspace:*' './foo' 'https://example.com/foo.tgz'; do
  run "$(edit_payload "$PKG" "$old" "\"dependencies\": {\"foo\": \"$v\"}")"
  check_ask "a manifest non-git value asks without the git-host warning: $v" "not a registry package"
  lacks "a manifest non-git value gets no git-host warning: $v" "$(ask_reason)" "git host" "not a registry package"
done
# These need the classifier to return source:other for a value after `name@` / a pip path with `/`
# (card: "both classifiers return source: other for every one of these forms").
ask_cmd "a git ref after name@ is source:other with the git-host warning" "npm install foo@user/repo#abc123" "not a registry package" "$GITNOTE"
ask_cmd "a pip path containing / is source:other, no git-host warning" "pip install reqs/dev.txt" "not a registry package"
lacks "the pip path gets no git-host warning" "$(ask_reason)" "git host" "not a registry package"
# vetting_record.validate_name refusing a leading `-` (card, Input validation `name`)
run "$(edit_payload "$PKG" "$old" '"dependencies": {"-x": "1.0.0"}')"
check_ask "a manifest key with a leading - asks with the invalid-name reason" "not a valid package name" "-x"

# ---- the five Scenarios added to the card with HEAD 338bed7
ask_cmd "Scenario: a git-host value after name@ asks and says the code can change (npm install foo@user/repo)" \
  "npm install foo@user/repo" "not a registry package" "the code can change unless pinned to a commit"
ask_cmd "Scenario: a dot-named GitHub repo is a shorthand and is asked about (npm install user/.github)" \
  "npm install user/.github" "not a registry package" "the code can change unless pinned to a commit"
deny_cmd "Scenario: a version with a slash is not a shorthand (npm install foo@1.2.3/evil)" \
  "npm install foo@1.2.3/evil" "npm foo has no exact version" "foo@<exact-version>"
lacks "Scenario: the slash version is not echoed or turned into a path" "$ERR" "evil" "has no exact version"
ask_cmd "Scenario: a local directory is not a registry package (pip install sub/dir)" \
  "pip install sub/dir" "not a registry package" "sub/dir"
lacks "Scenario: a local directory gets no git-host clause" "$(ask_reason)" "git host" "not a registry package"
run "$(write_payload "$PROJ/package.json" '{"name":"app","dependencies":{"-x":"1.0.0"}}')"
check_ask "Scenario: a Write of package.json adding \"-x\" asks, naming the raw value" "not a valid package name" "-x"

# ---- updates, upgrades and indirect installs (card, Mark 2026-10-15): asked about, never allowed silently
new_state
UPDATE_NOTE="an update or upgrade the guard does not vet"
for c in 'npm update zod@4.0.0' 'npm upgrade zod' 'npm update' 'npm up zod' 'npm u zod' 'npm udpate zod' \
         'pnpm up zod' 'pnpm update -g' 'pnpm upgrade zod' 'pn up zod' 'yarn upgrade zod' 'yarn up zod' \
         'yarn upgrade-interactive' 'yarn global upgrade' 'yarnpkg upgrade zod' 'bun update zod' 'bun upgrade' \
         'uv tool upgrade ruff' 'uv lock --upgrade' 'uv sync -U' 'uv lock --upgrade-package requests' \
         'poetry update' 'pipx upgrade ruff' 'pipx upgrade-all' 'pipx reinstall ruff' 'pipx reinstall-all' \
         'cargo update' 'go get -u ./...' 'go get -u=patch' 'gem update rails' 'brew upgrade jq' \
         'uv lock -P requests' 'uv add -U' 'uv run --upgrade pytest' 'uv sync --upgrade-group dev' 'npm audit fix --force' 'npm audit fix' \
         'pnpm audit --fix' 'pn audit --fix' 'sudo npm update' 'cd app && brew upgrade' 'corepack pnpm update zod'; do
  ask_cmd "an update is asked about: $c" "$c" "$UPDATE_NOTE" "check what it will change before approving"
done
ask_cmd "an update naming no package says everything" "npm update" "npm update everything: $UPDATE_NOTE"
ask_cmd "the form is the tool plus the matched words" "uv lock --upgrade" "uv lock --upgrade everything: $UPDATE_NOTE"
ask_cmd "npm audit fix names its form" "npm audit fix --force" "npm audit fix everything: $UPDATE_NOTE"
ask_cmd "go get -u names its form" "go get -u ./..." "go get -u ./...: $UPDATE_NOTE"
ask_cmd "an update naming a package names it" "brew upgrade jq" "brew upgrade jq: $UPDATE_NOTE"
ask_cmd "VET_EXEMPT changes nothing for an update" "VET_EXEMPT=offline npm update zod" "$UPDATE_NOTE"
lacks "VET_EXEMPT is not echoed for an update" "$(ask_reason)" "VET_EXEMPT" "$UPDATE_NOTE"
for c in 'uv lock' 'uv sync' 'uv run pytest' 'brew update' 'npm update --help' 'brew upgrade -h' 'npm audit' 'pnpm audit'; do
  allow_cmd "not an update, or help only: $c" "$c"
done
# help counts only among the tool's own options: before `--`, and for uv run before the command
for c in 'npm update -h' 'uv lock --upgrade -h' 'go get -u -h' 'uv run pytest --upgrade'; do
  allow_cmd "help or flag belongs to the tool's own options, or not the tool's: $c" "$c"
done
for c in 'uv run --upgrade pytest -h' 'npm update -- -h'; do
  ask_cmd "a help flag that is not the tool's own does not exempt the update: $c" "$c" "$UPDATE_NOTE"
done
# Closed gap (docs/features/dependency-guard-yarn-workspaces.md, R8): these three were ALLOW pins; a yarn
# workspace wrapper now gets the decision of the command inside it. The full matrix is further down.
deny_cmd "yarn workspace add is denied like yarn add: yarn workspace app add zod@1.0.0" "yarn workspace app add zod@1.0.0" \
  "has no vetting report from the last 7 days" "vet-dependency npm zod 1.0.0"
deny_cmd "yarn workspaces foreach add is denied like yarn add: yarn workspaces foreach -A add zod@1.0.0" "yarn workspaces foreach -A add zod@1.0.0" \
  "has no vetting report from the last 7 days" "vet-dependency npm zod 1.0.0"
ask_cmd "yarn workspace up is asked about like yarn up: yarn workspace app up zod" "yarn workspace app up zod" \
  "yarn workspace up zod: $UPDATE_NOTE" "check what it will change before approving"
before="$(log_count)"; run "$(bash_payload "npm update zod")"
[ $(( $(log_count) - before )) -eq 1 ] && say_ok "an update ask appends exactly one log line" || say_bad "an update ask appends exactly one log line" "gained $(( $(log_count) - before ))"
case "$(tail -n 1 "$STATE/dependency-guard.log")" in
  *"${TAB}ask${TAB}npm${TAB}zod${TAB}-${TAB}"*"npm update zod: $UPDATE_NOTE"*) say_ok "the update log line carries ask, ecosystem, name, no version, the reason" ;;
  *) say_bad "the update log line carries ask, ecosystem, name, no version, the reason" "$(tail -n 1 "$STATE/dependency-guard.log")" ;; esac
ask_cmd "an install run through xargs is asked about" "xargs npm i" "xargs npm: the packages come from input the guard cannot read" "check it before approving"
for c in 'xargs npm i' 'xargs -n 1 npm i x' 'xargs -I{} npm i {}' 'xargs sudo npm i' 'sudo xargs npm i'; do
  ask_cmd "an xargs install is asked about: $c" "$c" "xargs npm: the packages come from input the guard cannot read" "check it before approving"
done
ask_cmd "xargs pip install is asked about, not a guard failure" "xargs pip install" "xargs pip: the packages come from input the guard cannot read"
ask_cmd "xargs corepack pnpm add x names the first tool word" "xargs corepack pnpm add x" "xargs corepack: the packages come from input the guard cannot read"
ask_cmd "xargs with options and a pipe is asked about" "find . -name package.json | xargs -n1 -I{} pip install {}" "xargs pip: the packages come from input the guard cannot read"
ask_cmd "VET_EXEMPT changes nothing for xargs" "VET_EXEMPT=x xargs brew install" "xargs brew: the packages come from input the guard cannot read"
allow_cmd "xargs of something that is not an install tool is untouched" "xargs rm -f"
new_state
deny_cmd "yarn global add takes the normal install path (MSG_VET_FIRST)" "yarn global add left-pad@1.3.0" \
  "has no vetting report from the last 7 days" "vet-dependency npm left-pad 1.3.0"
deny_cmd "yarn global add without a version is the unpinned deny" "yarn global add left-pad" "npm left-pad has no exact version" "left-pad@<exact-version>"
mkrec npm left-pad 1.3.0 24 true
ask_cmd "a vetted yarn global add reaches Mark like pnpm add -g" "yarn global add left-pad@1.3.0" "npm left-pad@1.3.0" "vetted 1 day ago"
new_state
deny_cmd "an update beside a pinned install still reaches the strongest decision" "go get -u example.com/m@v1.2.3" \
  "has no vetting report from the last 7 days" "vet-dependency go example.com/m v1.2.3"
run "$(bash_payload "go get -u example.com/m@v1.2.3")"
lacks "the deny output holds the deny only, not the update ask" "$ERR" "$UPDATE_NOTE" "has no vetting report"
[ "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" -eq 1 ] && say_ok "one denied package gives one stderr line" || say_bad "one denied package gives one stderr line" "$ERR"
deny_cmd "VET_EXEMPT does not turn an update's deny into anything but the unpinned deny" "VET_EXEMPT=x go get -u example.com/m" "example.com/m has no exact version"
new_state
mkrec go example.com/m v1.2.3 24 true
ask_cmd "with a record the go -u command asks, update clause included" "go get -u example.com/m@v1.2.3" "go example.com/m@v1.2.3" "$UPDATE_NOTE"

# ---- yarn workspace forms (docs/features/dependency-guard-yarn-workspaces.md, R1-R8)
# `yarn workspace <name> <rest>` and `yarn workspaces foreach [options] <rest>` get the decision of
# `yarn <rest>`. Rows under "stays allowed" and the --cwd control pass before the fix too: they pin what
# the fix must not break.
new_state
same_result() { # $1 desc, $2 wrapped command, $3 plain command: same exit code, stdout and stderr.
  # The plain form must itself decide (deny or ask), or the comparison would pass on two silent allows.
  local rc_p out_p err_p
  run "$(bash_payload "$3")"; rc_p=$RC; out_p=$OUT; err_p=$ERR
  if [ "$rc_p" -eq 0 ] && [ -z "$out_p" ]; then say_bad "$1" "control [$3] was allowed, so there is nothing to compare"; return; fi
  run "$(bash_payload "$2")"
  if [ "$RC" -eq "$rc_p" ] && [ "$OUT" = "$out_p" ] && [ "$ERR" = "$err_p" ]; then say_ok "$1"
  else say_bad "$1" "want the result of [$3] (rc=$rc_p out=[$out_p] err=[$err_p]); got rc=$RC out=[$OUT] err=[$ERR]"; fi
}

# R1 + Evidence rows 1, 4, 5, 6 + Scenarios 1-2: install/dlx/global forms, same reason text as top level
deny_cmd "Scenario: an unvetted add inside a workspace is denied like a plain add" "yarn workspace web add lodash" \
  "npm lodash has no exact version" "lodash@<exact-version>"
deny_cmd "Scenario: dlx inside a workspace is denied like plain dlx" "yarn workspace web dlx x" \
  "npm x has no exact version" "x@<exact-version>"
deny_cmd "a pinned but unvetted add inside a workspace is stopped with the vet command" "yarn workspace web add lodash@4.17.21" \
  "npm lodash@4.17.21 has no vetting report from the last 7 days" "vet-dependency npm lodash 4.17.21"
for c in 'add lodash' 'add lodash@4.17.21' 'install lodash' 'dlx x' 'dlx x@1.0.0' 'global add lodash'; do
  same_result "yarn workspace web $c has the exact result of yarn $c" "yarn workspace web $c" "yarn $c"
done
# R2: foreach (yarn 4 has no `global`, so that form is not paired with it)
for c in 'add lodash' 'add lodash@4.17.21' 'install lodash' 'dlx x' 'dlx x@1.0.0'; do
  same_result "yarn workspaces foreach -A $c has the exact result of yarn $c" "yarn workspaces foreach -A $c" "yarn $c"
done
mkrec npm zod 3.23.8 24 true
ask_cmd "a vetted add inside a workspace reaches Mark like a plain add" "yarn workspace web add zod@3.23.8" "npm zod@3.23.8" "vetted 1 day ago"
ask_cmd "a vetted add inside foreach reaches Mark like a plain add" "yarn workspaces foreach -A add zod@3.23.8" "npm zod@3.23.8" "vetted 1 day ago"

# R1 + R5 + Evidence rows 2, 3: updates ask, and the form keeps the wrapper but never the workspace name
for pair in 'up|up everything' 'upgrade|upgrade everything' 'up lodash|up lodash' 'upgrade lodash|upgrade lodash' \
            'upgrade-interactive|upgrade-interactive everything'; do
  rest="${pair%%|*}"; form="${pair#*|}"
  ask_cmd "yarn workspace web $rest asks, naming the wrapper: yarn workspace $form" "yarn workspace web $rest" \
    "yarn workspace $form: $UPDATE_NOTE" "check what it will change before approving"
  ask_cmd "yarn workspaces foreach -A $rest asks, naming the wrapper: yarn workspaces foreach $form" "yarn workspaces foreach -A $rest" \
    "yarn workspaces foreach $form: $UPDATE_NOTE" "check what it will change before approving"
done
ask_cmd "Scenario: an update inside foreach asks, naming the wrapper" "yarn workspaces foreach -A up" \
  "yarn workspaces foreach up everything"
ask_cmd "the workspace global upgrade form asks like yarn global upgrade" "yarn workspace web global upgrade" "$UPDATE_NOTE"
run "$(bash_payload "yarn workspace web up")"
lacks "R5: the workspace name is never part of the form" "$(ask_reason)" "workspace web" "$UPDATE_NOTE"
before="$(log_count)"
ask_cmd "an update inside a workspace asks (for the log check below)" "yarn workspace web up lodash" "yarn workspace up lodash: $UPDATE_NOTE"
[ $(( $(log_count) - before )) -eq 1 ] && say_ok "a workspace update ask appends exactly one log line" || say_bad "a workspace update ask appends exactly one log line" "gained $(( $(log_count) - before ))"
case "$(tail -n 1 "$STATE/dependency-guard.log")" in
  *"${TAB}ask${TAB}npm${TAB}lodash${TAB}-${TAB}"*"yarn workspace up lodash: $UPDATE_NOTE"*) say_ok "R5: the workspace log line carries the wrapper form and no workspace name" ;;
  *) say_bad "R5: the workspace log line carries the wrapper form and no workspace name" "$(tail -n 1 "$STATE/dependency-guard.log")" ;; esac

# R2: foreach options. Value-taking ones (--from, --include, --exclude, -j/--jobs) consume the next word;
# every other dash word is a flag on its own. The first word left starts <rest>.
for o in '' '-A' '--all' '-R' '-W' '-v' '-p' '-i' '-t' '-pt' '-Apt' '--parallel' '--topological' '--topological-dev' \
         '--verbose' '--no-private' '--recursive' '--worktree' '--interlaced' '--jobs=2' '--include=web' '--exclude=api' '--from=web' \
         '--include web' '--exclude api' '--from web' '-j 2' '--jobs 2' '--include up' '--exclude dlx' '--from add' \
         '-A --include web --exclude api -j 4 -pt'; do
  deny_cmd "foreach option(s) skipped, add still denied: foreach ${o:-<none>} add lodash" "yarn workspaces foreach${o:+ $o} add lodash" \
    "npm lodash has no exact version" "lodash@<exact-version>"
done
deny_cmd "foreach dlx still denied behind a value-taking option" "yarn workspaces foreach --include web dlx x" "npm x has no exact version" "x@<exact-version>"
ask_cmd "foreach -j 2 up asks, naming the wrapper" "yarn workspaces foreach -j 2 up" "yarn workspaces foreach up everything" "$UPDATE_NOTE"
ask_cmd "foreach --include web up asks, naming the wrapper" "yarn workspaces foreach --include web up lodash" "yarn workspaces foreach up lodash" "$UPDATE_NOTE"
# Scenarios 4-7 (R3): --since never takes the next word
deny_cmd "Scenario: a value-taking foreach option is skipped (--include web add lodash)" "yarn workspaces foreach --include web add lodash" \
  "npm lodash has no exact version" "lodash@<exact-version>"
deny_cmd "Scenario: a bare --since is a flag on its own" "yarn workspaces foreach --since add lodash" \
  "npm lodash has no exact version" "lodash@<exact-version>"
ask_cmd "Scenario: --since=ref is one word, so up asks" "yarn workspaces foreach --since=main up" "yarn workspaces foreach up everything" "$UPDATE_NOTE"
allow_cmd "Scenario: the word after a bare --since is the command, so it runs a script named main (up)" "yarn workspaces foreach --since main up"
allow_cmd "R3: the word after a bare --since is the command (add lodash is script main's arguments)" "yarn workspaces foreach --since main add lodash"

# R7: a value-taking option that swallows the last word leaves nothing after the wrapper
for c in 'yarn workspace web' 'yarn workspaces foreach' 'yarn workspaces foreach -A' 'yarn workspaces foreach -A --include up' \
         'yarn workspaces foreach --include web' 'yarn workspaces foreach -j 2' 'yarn workspaces foreach --since main'; do
  allow_cmd "R7: a wrapper with nothing after it stays allowed: $c" "$c"
done

# R4 + Evidence row 7 + Scenario 8: yarn 1's workspaces run is a script run, not a wrapper
for c in 'yarn workspaces run add lodash' 'yarn workspaces run upgrade' 'yarn workspaces run dlx x' 'yarn workspaces run build'; do
  allow_cmd "R4: workspaces run is a script run and stays allowed: $c" "$c"
done

# R6 + Evidence row 6 + Scenario 9: not an install, update or runner form inside the wrapper -> stays allowed
for c in 'yarn workspace web remove lodash' 'yarn workspace web run build' 'yarn workspace web run add lodash' 'yarn workspace web build' \
         'yarn workspaces foreach run build' 'yarn workspaces foreach -A run build' 'yarn workspaces foreach -A run add lodash' \
         'yarn workspaces foreach -A remove lodash' 'yarn workspaces info' 'yarn workspaces list'; do
  allow_cmd "R6: stays allowed: $c" "$c"
done

# Evidence row 3: other spellings of the program, and a wrapper inside a chain or behind an assignment
for pre in 'yarnpkg' 'corepack yarn' 'VAR=1 yarn' 'cd x && yarn' 'env FOO=1 yarn' 'node_modules/.bin/yarnpkg'; do
  deny_cmd "Scenario: other spellings are covered: $pre workspace web add lodash" "$pre workspace web add lodash" \
    "npm lodash has no exact version" "lodash@<exact-version>"
  deny_cmd "Scenario: other spellings are covered: $pre workspaces foreach -A add lodash" "$pre workspaces foreach -A add lodash" \
    "npm lodash has no exact version" "lodash@<exact-version>"
  ask_cmd "other spellings are covered: $pre workspace web up" "$pre workspace web up" "workspace up everything: $UPDATE_NOTE"
done
for pre in 'yarnpkg' 'corepack yarn' 'VAR=1 yarn' 'cd x && yarn'; do
  allow_cmd "other spellings stay allowed for a script run: $pre workspaces run add lodash" "$pre workspaces run add lodash"
  allow_cmd "other spellings stay allowed for a remove: $pre workspace web remove lodash" "$pre workspace web remove lodash"
done
# Evidence row 8: --cwd was already handled
deny_cmd "control: yarn --cwd web add lodash is already denied" "yarn --cwd web add lodash" "npm lodash has no exact version" "lodash@<exact-version>"

# ---- yarn exec, pnpm exec, nested yarn wrappers, pnpm option widths (docs/features/dependency-guard-exec-wrappers.md, R1-R10)
# `exec` runs what follows; a yarn wrapper inside a yarn wrapper is unwrapped until none is left; pnpm's -w, --workspace
# and --config are booleans; an option the guard does not know gets both widths; pnpm's m/multi/recursive is -r.
# Every "like" row goes through same_result, so its plain command must itself decide. Rows marked (kept) in their
# comment pass before the fix too: they pin behaviour the fix must not change.
new_state
SQ="'"
NOTHING_X="npm x has no exact version"
cannot_read_like_top_level() { # $1 desc, $2 command: the cannot-read ask a top-level unreadable command gets, and the cannot-read log word
  local rc_p out_p err_p before
  run "$(bash_payload "${unreadable_pre}npm i zod@3.23.8")"; rc_p=$RC; out_p=$OUT; err_p=$ERR
  if [ -z "$out_p" ]; then say_bad "$1" "control (a top-level unreadable command) was not asked about"; return; fi
  before="$(log_count)"; run "$(bash_payload "$2")"
  if [ "$RC" -ne "$rc_p" ] || [ "$OUT" != "$out_p" ] || [ "$ERR" != "$err_p" ]; then
    say_bad "$1" "want the cannot-read ask (rc=$rc_p out=[$out_p]); got rc=$RC out=[$OUT] err=[$ERR]"; return; fi
  if [ $(( $(log_count) - before )) -ne 1 ]; then say_bad "$1" "want exactly one log line; gained $(( $(log_count) - before ))"; return; fi
  case "$(tail -n 1 "$STATE/dependency-guard.log")" in
    *"${TAB}cannot-read${TAB}"*) say_ok "$1" ;;
    *) say_bad "$1" "the log word is not cannot-read: $(tail -n 1 "$STATE/dependency-guard.log")" ;; esac
}

# R1, R2, R3, R4 + Evidence table 1 + Scenarios: the exec'd command decides like the same command typed alone
for row in 'yarn exec npm i x|npm i x' 'yarn exec npm update|npm update' 'yarn exec yarn add x|yarn add x' \
           'yarn exec npx cowsay|npx cowsay' "yarn exec 'npm i x'|npm i x" \
           'yarn workspace web exec npm i x|npm i x' 'yarn workspaces foreach -A exec npm i x|npm i x' \
           'yarnpkg exec npm i x|npm i x' 'corepack yarn exec npm i x|npm i x' \
           'pnpm exec npm i x|npm i x' 'pn exec npm i x|npm i x' 'pnpm -r exec npm i x|npm i x' \
           "yarn exec 'cd web && npm i x'|npm i x" "yarn exec 'cd web && npm' i x|npm i x" \
           'yarn exec -- npm i x|npm i x' 'pnpm exec -- npm i x|npm i x' \
           'pnpm exec --filter web npm i x|npm i x' 'pnpm exec -r npm i x|npm i x' 'pnpm exec --dir=web npm i x|npm i x' \
           "pnpm exec -c 'npm i x'|npm i x" 'pnpm exec -c npm i x|npm i x' 'pnpm --shell-mode exec npm i x|npm i x' \
           'pnpm --reporter silent exec npm i x|npm i x' 'pnpm -w exec npm i x|npm i x' 'pnpm m exec npm i x|npm i x' \
           'VET_EXEMPT=reason yarn exec npm i x@1.0.0|VET_EXEMPT=reason npm i x@1.0.0' \
           "yarn exec 'VET_EXEMPT=reason npm i x@1.0.0'|npm i x@1.0.0"; do
  same_result "exec: [${row%|*}] has the exact result of [${row##*|}]" "${row%|*}" "${row##*|}"
done
# R4: a yarn wrapper inside a yarn wrapper
for row in 'yarn workspace web workspaces foreach -A add x|yarn add x' 'yarn workspace a workspace b add x|yarn add x' \
           'yarn workspaces foreach -A workspace b add x|yarn add x'; do
  same_result "nested wrappers: [${row%|*}] has the exact result of [${row##*|}]" "${row%|*}" "${row##*|}"
done
# R5: an update behind nested wrappers keeps every wrapper word, never the workspace name
ask_cmd "nested wrappers keep every wrapper word in an update ask: yarn workspace web workspaces foreach -A up" \
  "yarn workspace web workspaces foreach -A up" "yarn workspace workspaces foreach up everything: $UPDATE_NOTE"
# R2: a string the lexer cannot read, and the pnpm shell-mode string; both compare with a top-level unreadable command
cannot_read_like_top_level "cannot-read: yarn exec \"npm i 'x\"" "yarn exec \"npm i ${SQ}x\""
cannot_read_like_top_level "cannot-read: pnpm exec -c \"npm i 'x\"" "pnpm exec -c \"npm i ${SQ}x\""
cannot_read_like_top_level "cannot-read: pnpm exec -c npm i \"'x\"" "pnpm exec -c npm i \"${SQ}x\""
cannot_read_like_top_level "cannot-read: pnpm -c exec npm i \"'x\"" "pnpm -c exec npm i \"${SQ}x\""
cannot_read_like_top_level "cannot-read: pnpm --shell-mode exec npm i \"'x\"" "pnpm --shell-mode exec npm i \"${SQ}x\""
for c in 'pnpm -c exec' 'pnpm --shell-mode exec'; do
  same_result "shell mode typed before exec: [$c npm i \"'x\"] has the exact result of [pnpm exec -c npm i \"'x\"]" \
    "$c npm i \"${SQ}x\"" "pnpm exec -c npm i \"${SQ}x\""
done
# R3: the reading cap. 7 repeats of `yarn exec -y exec ` double the readings 7 times, 128 > MAX_READINGS (64)
cap_cmd=""; for _i in 1 2 3 4 5 6 7; do cap_cmd="${cap_cmd}yarn exec -y exec "; done; cap_cmd="${cap_cmd}npm i x"
cannot_read_like_top_level "reading cap: 7 x 'yarn exec -y exec ' then npm i x gets the cannot-read ask" "$cap_cmd"
# R7: pins for the Known-gaps lines that name a command
deny_cmd "R7: \$@ is not special-cased, the args are appended and x is installed: yarn exec 'npm i \"\$@\"' x" \
  "yarn exec 'npm i \"\$@\"' x" "$NOTHING_X" "x@<exact-version>"
deny_cmd "R7: an option read both ways: pnpm exec --filter npm i x" "pnpm exec --filter npm i x" "$NOTHING_X" "x@<exact-version>"
deny_cmd "R7 over-read: pnpm -r run add x is no longer allowed" "pnpm -r run add x" "$NOTHING_X" "x@<exact-version>"
deny_cmd "R7 over-read: pnpm --filter add test is no longer allowed" "pnpm --filter add test" "npm test has no exact version" "test@<exact-version>"
deny_cmd "R7 over-read: npm --prefix add test is no longer allowed" "npm --prefix add test" "npm test has no exact version" "test@<exact-version>"
allow_cmd "R7 (kept): bun exec 'npm i x' stays allowed (bun is out of scope)" "bun exec 'npm i x'"
allow_cmd "R7 (kept): yarn add -w x stays allowed (yarn's own subcommand words keep one reading)" "yarn add -w x"
allow_cmd "R7 (kept): bun --cwd add x stays allowed (bun is outside R9)" "bun --cwd add x"

# R9: pnpm's -w, --workspace and --config are booleans; an option the guard does not know gets both widths
for row in 'pnpm -w add x|pnpm add x' 'pn -w add x|pnpm add x' 'pnpm add -w x|pnpm add x' 'pnpm add -w x@1.0.0|pnpm add x@1.0.0' \
           'pnpm i -w x|pnpm i x' 'pnpm add --workspace x|pnpm add x' 'pnpm --workspace add x|pnpm add x' \
           'pnpm add --config x|pnpm add x' 'pnpm add --config x@1.0.0|pnpm add x@1.0.0' \
           'pnpm --reporter silent add x|pnpm add x' 'pnpm --store-dir /s add x|pnpm add x' 'pnpm --state-dir /s add x|pnpm add x' \
           'yarn --mutex file:/tmp/m add x|yarn add x' 'yarn -w add x|yarn add x' \
           'pnpm dlx -w cowsay|pnpm dlx cowsay' 'pnpm dlx -c cowsay|pnpm dlx cowsay'; do
  same_result "R9 widths: [${row%|*}] has the exact result of [${row##*|}]" "${row%|*}" "${row##*|}"
done
# R10: pnpm's recursive/multi/m alias is --recursive
for row in 'pnpm m add x|pnpm -r add x' 'pnpm multi add x|pnpm -r add x' 'pnpm recursive add x|pnpm -r add x' 'pnpm m up|pnpm -r up'; do
  same_result "R10 alias: [${row%|*}] has the exact result of [${row##*|}]" "${row%|*}" "${row##*|}"
done
allow_cmd "R10 (kept): pnpm m with nothing after it installs nothing" "pnpm m"
allow_cmd "R10 (kept): pnpm recursive with nothing after it installs nothing" "pnpm recursive"

# (kept) today's reading stays one of the readings, so nothing denied or asked today can become an allow
for c in 'pnpm -w web add x' 'pn -w web add x' 'pnpm --workspace web add x' 'pnpm --config foo add x' 'pnpm add -w --filter x'; do
  deny_cmd "kept: still denied, naming x: $c" "$c" "$NOTHING_X" "x@<exact-version>"
done
ask_cmd "kept: still asked: pnpm -w web update" "pnpm -w web update" "pnpm update everything: $UPDATE_NOTE"
ask_cmd "kept: still asked: pnpm -w foo audit --fix" "pnpm -w foo audit --fix" "pnpm audit --fix everything: $UPDATE_NOTE"
ask_cmd "kept: still asked: pnpm -r up" "pnpm -r up" "pnpm up everything: $UPDATE_NOTE"
deny_cmd "kept: npm's -w still takes a value, so x is named: npm -w web install x" "npm -w web install x" "$NOTHING_X" "x@<exact-version>"
run "$(bash_payload "npm -w web install x")"; lacks "kept: npm -w web install x never names web" "$ERR" "npm web" "$NOTHING_X"
# (kept) rows of the Evidence tables that are already handled
same_result "kept: yarn workspace web add x has the exact result of yarn add x" "yarn workspace web add x" "yarn add x"
deny_cmd "kept: npm exec -- npm i x is refused as a runner naming a package manager" "npm exec -- npm i x" \
  "dependency-guard: npm exec would fetch the package manager npm"
for c in 'pnpm --workspace-root add x' 'pnpm --filter web add x' 'pnpm -r add x' "pnpm -c exec cd web '&&' npm i x" \
         'pnpm --reporter=silent add x' 'pnpm add --store-dir /s x'; do
  deny_cmd "kept: already denied, naming x: $c" "$c" "$NOTHING_X" "x@<exact-version>"
done
deny_cmd "kept: pnpm dlx cowsay is denied" "pnpm dlx cowsay" "npm cowsay has no exact version" "cowsay@<exact-version>"
# R6 (kept): an exec whose inner command installs nothing, or with nothing after it, stays allowed
for c in 'yarn exec echo hi' 'yarn exec tsc' 'pnpm exec eslint .' 'yarn exec' 'pnpm exec -c' "yarn exec \"echo ${SQ}hi\""; do
  allow_cmd "R6 (kept): stays allowed: $c" "$c"
done

# ---- log forging
new_state
before="$(log_count)"
run "$(write_payload "$PROJ/package.json" "$(/usr/bin/jq -nc --arg v '3.23.8' '{name:"app",dependencies:{("zod\t\nx"):$v}}')")"
check_ask "a crafted manifest name (tab and newline) asks, naming the sanitised value" "not a valid package name" "zod?"
[ $(( $(log_count) - before )) -eq 1 ] && say_ok "a crafted name cannot forge a log line (exactly one line gained)" || say_bad "a crafted name cannot forge a log line" "gained $(( $(log_count) - before ))"
awk -F'\t' 'NF != 7 {bad=1} END {exit bad}' "$STATE/dependency-guard.log" && say_ok "every log line still has seven fields" || say_bad "every log line still has seven fields" "$(cat "$STATE/dependency-guard.log")"
long="$(python3 -c 'print("a" * 300)')"
run "$(bash_payload "npm install $long@3.23.8")"
check_ask "an over-long name asks" "not a valid package name"
awk -F'\t' '{for (i = 1; i <= NF; i++) if (length($i) > 200) bad=1} END {exit bad}' "$STATE/dependency-guard.log" && say_ok "log fields are cut to 200 characters" || say_bad "log fields are cut to 200 characters" "a field is longer than 200"
run "$(bash_payload "npm install \"zod${TAB}x@3.23.8\"")"
check_ask "a tab inside a command-line name asks" "not a valid package name"
awk -F'\t' 'NF != 7 {bad=1} END {exit bad}' "$STATE/dependency-guard.log" && say_ok "a tab in a command-line name does not add a log field" || say_bad "a tab in a command-line name does not add a log field" "$(cat "$STATE/dependency-guard.log")"

# ---- log write failure
new_state
mkdir "$STATE/dependency-guard.log"
deny_cmd "a failed log write leaves the deny in place and says so" "npm install zod@3.23.8" "has no vetting report from the last 7 days" "(log write failed)"
mkrec npm zod 3.23.8 24 true
ask_cmd "a failed log write leaves the ask in place and says so" "npm install zod@3.23.8" "npm zod@3.23.8" "(log write failed)"
new_state
rm -rf "$STATE"
deny_cmd "the hook creates a missing state dir" "npm install zod@3.23.8" "has no vetting report"
[ -f "$STATE/dependency-guard.log" ] && say_ok "the log is written into the new state dir" || say_bad "the log is written into the new state dir" "no log in $STATE"

# ---- the broken-guard paths
printf '\ndependency-guard hook: broken-guard paths\n'
new_state
for lib in classify-install-command.py classify-manifest-edit.py vetting_record.py shell_segments.py; do
  make_copy "$lib"; d="$COPY"; before="$(log_count)"
  run_with "$d/dependency-guard.sh" "$(bash_payload "git status")"
  check_ask "guard broken: $lib missing -> ask" "dependency-guard is broken" "${lib%.py}"
  [ $(( $(log_count) - before )) -eq 1 ] && say_ok "guard broken ($lib missing): one log line" || say_bad "guard broken ($lib missing): one log line" "gained $(( $(log_count) - before ))"
done
make_copy "decide-dependency.py"; d="$COPY"; before="$(log_count)"
run_with "$d/dependency-guard.sh" "$(bash_payload "git status")"
check_ask "guard broken: the decision helper missing -> ask" "dependency-guard is broken" "decide-dependency"
case "$(tail -n 1 "$STATE/dependency-guard.log")" in *"${TAB}broken${TAB}"*) say_ok "the wrapper's own broken line is logged" ;; *) say_bad "the wrapper's own broken line is logged" "$(tail -n 1 "$STATE/dependency-guard.log")" ;; esac

make_copy "classify-install-command.py"; d="$COPY"
printf 'def classify(src):\n    raise ValueError("boom\\nsecond-line")\ndef is_unreadable(src):\n    return False\ndef mentions_install_tool(src):\n    return False\nINSTALL_TOOL_WORDS = ()\n' > "$d/lib/classify-install-command.py"
before="$(log_count)"
run_with "$d/dependency-guard.sh" "$(bash_payload "git status")"
check_ask "a classifier exception puts the class and first line in the ask" "dependency-guard is broken" "ValueError: boom"
lacks "only the first line of the error is shown" "$(ask_reason)" "second-line" "ValueError: boom"
[ $(( $(log_count) - before )) -eq 1 ] && say_ok "a classifier exception appends one log line" || say_bad "a classifier exception appends one log line" "gained $(( $(log_count) - before ))"
printf 'raise RuntimeError("import boom")\n' > "$d/lib/classify-install-command.py"
run_with "$d/dependency-guard.sh" "$(bash_payload "git status")"
check_ask "an import-time error is reported with its class" "dependency-guard is broken" "RuntimeError: import boom"

run '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":'
check_ask "an unparseable payload asks (broken)" "dependency-guard is broken"
run ''
check_ask "an empty payload asks (broken)" "dependency-guard is broken"
run "$(/usr/bin/jq -nc --arg f "$PROJ/package.json" '{hook_event_name:"PreToolUse",session_id:"s",tool_name:"Write",tool_input:{file_path:$f}}')"
check_ask "a manifest classifier exception asks (broken)" "dependency-guard is broken" "ValueError"

# python3 off PATH: only the tools the wrapper needs are linked in
NOPY="$TMP/nopy-bin"; mkdir -p "$NOPY"
for t in cat date dirname mkdir rm mktemp printf; do p="$(command -v "$t" 2>/dev/null)"; case "$p" in /*) ln -s "$p" "$NOPY/$t" ;; esac; done
make_copy ""; d="$COPY"; before="$(log_count)"
OUT="$(printf '%s' "$(bash_payload "git status")" | PATH="$NOPY" HOME="$FAKE_HOME" DEPENDENCY_GUARD_STATE_DIR="$STATE" /bin/bash "$d/dependency-guard.sh" 2>"$TMP/err.out")"; RC=$?; ERR="$(cat "$TMP/err.out")"
check_ask "python3 missing: the wrapper prints the ask with printf" "dependency-guard is broken: python3 not found"
[ $(( $(log_count) - before )) -eq 1 ] && say_ok "python3 missing: the wrapper appends one fixed-text log line" || say_bad "python3 missing: the wrapper appends one fixed-text log line" "gained $(( $(log_count) - before ))"
case "$(tail -n 1 "$STATE/dependency-guard.log")" in *"${TAB}broken${TAB}"*"python3 not found") say_ok "python3 missing: line is decision broken, reason 'python3 not found'" ;; *) say_bad "python3 missing: line is decision broken, reason 'python3 not found'" "$(tail -n 1 "$STATE/dependency-guard.log")" ;; esac

# default state dir is the hook's own hooks/state (proved on the copy, never the real tree)
make_copy ""; d="$COPY"
OUT="$(cd "$PROJ" && printf '%s' "$(bash_payload "npm install zod@3.23.8")" | env -u DEPENDENCY_GUARD_STATE_DIR HOME="$FAKE_HOME" bash "$d/dependency-guard.sh" 2>"$TMP/err.out")"; RC=$?; ERR="$(cat "$TMP/err.out")"
check_deny "with no override the state dir is <hooks>/state (deny still works)" "has no vetting report"
[ -f "$d/state/dependency-guard.log" ] && say_ok "the default log lives at <hooks>/state/dependency-guard.log" || say_bad "the default log lives at <hooks>/state/dependency-guard.log" "no log in $d/state"

# ---- executable bit: settings.json runs the script as a bare command, and run_with's `bash "$1"` is blind to the mode bit
[ -x "$HOOK" ] && say_ok "the hook is executable on disk" || say_bad "the hook is executable on disk" "not +x: $HOOK"
git_mode="$(git -C "$HERE/.." ls-files -s -- hooks/dependency-guard.sh 2>/dev/null)"
if [ -z "$git_mode" ]; then printf 'note — hooks/dependency-guard.sh is not tracked here (a copy?); skipping the git mode assertion\n'
else case "$git_mode" in 100755*) say_ok "git records the hook as executable (100755)" ;; *) say_bad "git records the hook as executable (100755)" "got: $git_mode" ;; esac; fi
new_state
OUT="$(cd "$PROJ" && printf '%s' "$(bash_payload "git status")" | HOME="$FAKE_HOME" DEPENDENCY_GUARD_STATE_DIR="$STATE" "$HOOK" 2>"$TMP/err.out")"; RC=$?; ERR="$(cat "$TMP/err.out")"
if [ "$RC" -ne 126 ] && [ "$RC" -ne 127 ]; then say_ok "the hook runs directly with no bash prefix (rc=$RC)"; else say_bad "the hook runs directly with no bash prefix" "rc=$RC err=[$ERR]"; fi

# ---- the real state was never touched
real_log_after="$(stat -f '%m %z' "$REAL_LOG" 2>&1 || stat -c '%Y %s' "$REAL_LOG" 2>&1)"
[ "$real_log_before" = "$real_log_after" ] && say_ok "the real hooks/state log was not touched" || say_bad "the real hooks/state log was not touched" "before [$real_log_before] after [$real_log_after]"

printf '\ndependency-guard: %s passed, %s failed\n' "$pass" "$fail"
[ -z "${DEPENDENCY_GUARD_HOOK:-}" ] && [ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
