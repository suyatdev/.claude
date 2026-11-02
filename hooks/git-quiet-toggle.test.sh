#!/usr/bin/env bash
# git-quiet-toggle.test.sh — tests for git-quiet-toggle.sh (UserPromptSubmit).
# Covers docs/features/git-guard-quiet.md R14 (toggle side), R15, R16, R17, and the
# "the phrase inside other text does nothing" scenario.
#
# Every case runs against a throwaway $HOME (mktemp -d), never the real
# ~/.claude/hooks/state. Each case asserts the EMITTED line and the state on disk
# together, because a toggle that prints the right words without touching the flag
# (or the reverse) is the defect this hook exists to prevent.
#
# GIT_QUIET_TOGGLE overrides the script under test, to falsify the suite against a stub;
# a run against an override never writes a test marker.
#
# Run: bash hooks/git-quiet-toggle.test.sh
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

DEFAULT_HOOK="$(cd "$(dirname "$0")" && pwd)/git-quiet-toggle.sh"
HOOK="${GIT_QUIET_TOGGLE:-$DEFAULT_HOOK}"
TMP="$(mktemp -d)" || exit 1
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

PHRASE_QUIET='git-guard quiet'
PHRASE_ON='git-guard on'
STATE_REL='.claude/hooks/state/git-guard-quiet'

# The three message strings are copied from the card's "The toggle" section, character for
# character; the suite pins them so wording drift is a red test, not a surprise.
ON_LINE='git-guard quiet: ON for this session (read-only -C lookups, git add, and plain feature-branch commits and "push <remote> HEAD" pass without a prompt; everything else still asks).'
OFF_LINE='git-guard quiet: OFF for this session (the -C prompt is back).'
FAILED_ON_PREFIX='git-guard quiet: FAILED to change state — the prompt is ON. '
FAILED_OFF_PREFIX='git-guard quiet: FAILED to change state — the prompt is OFF. '

SID_A='fb455a92-bc6d-49bf-93ff-b776fb118c9c'
SID_B='0c9d3a11-2b7e-4f55-8a06-1d2e3f4a5b6c'

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s\n%s\n' "$1" "$2"; fail=$((fail+1)); }

n_homes=0
new_home() { # sets H to a fresh empty fake $HOME (not a subshell: the counter must persist)
  n_homes=$((n_homes+1))
  H="$TMP/home$n_homes"
  mkdir -p "$H"
}

# pj <prompt> <session_id> — a UserPromptSubmit payload with the two fields the hook reads.
pj() {
  python3 -c '
import json, sys
print(json.dumps({"hook_event_name": "UserPromptSubmit", "cwd": "/x",
                  "prompt": sys.argv[1], "session_id": sys.argv[2]}))' "$1" "$2"
}

# run <home> <payload> — runs the hook; sets OUT (stdout), NLINES (stdout line count), RC.
# UMASK, when set, is applied first; HOOK_PATH, when set, replaces PATH and runs the script
# under /bin/bash (an env-shebang cannot find bash on an empty PATH).
run() {
  local home="$1" payload="$2"
  if [ -n "${HOOK_PATH+x}" ]; then
    ( [ -z "${UMASK:-}" ] || umask "$UMASK"
      printf '%s' "$payload" | HOME="$home" PATH="$HOOK_PATH" /bin/bash "$HOOK" ) >"$TMP/out" 2>"$TMP/err"
  else
    ( [ -z "${UMASK:-}" ] || umask "$UMASK"
      printf '%s' "$payload" | HOME="$home" "$HOOK" ) >"$TMP/out" 2>"$TMP/err"
  fi
  RC=$?
  OUT="$(cat "$TMP/out")"
  NLINES="$(wc -l <"$TMP/out" | tr -d ' ')"
}

flag() { printf '%s/%s/%s' "$1" "$STATE_REL" "$2"; }
has_flag() { [ -f "$(flag "$1" "$2")" ]; }
modeof() { python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }
# Everything the hook may have left under a fake home, as a sorted list.
tree_of() { ( cd "$1" && find . | LC_ALL=C sort ); }

# want <desc> <home> <expected-stdout> <expected-flag-for-SID_A: yes|no>
# One line of stdout, exact; exit 0; the flag on disk agrees with the printed state.
want() {
  local desc="$1" home="$2" line="$3" flag_state="$4" detail="" good=1
  [ "$RC" -eq 0 ] || { good=0; detail="$detail rc=$RC"; }
  [ "$OUT" = "$line" ] || { good=0; detail="$detail stdout=[$OUT]"; }
  [ "$NLINES" -eq 1 ] || { good=0; detail="$detail lines=$NLINES"; }
  if [ "$flag_state" = yes ]; then has_flag "$home" "$SID_A" || { good=0; detail="$detail flag-missing"; }
  else has_flag "$home" "$SID_A" && { good=0; detail="$detail flag-present"; }; fi
  if [ "$good" -eq 1 ]; then ok "$desc"; else bad "$desc" "  $detail"; fi
}

# silent <desc> <home> — no stdout, exit 0, and nothing at all created under the home.
silent() {
  local desc="$1" home="$2" detail="" good=1 stray
  [ "$RC" -eq 0 ] || { good=0; detail="$detail rc=$RC"; }
  [ -z "$OUT" ] || { good=0; detail="$detail stdout=[$OUT]"; }
  stray="$(tree_of "$home")"
  [ "$stray" = "." ] || { good=0; detail="$detail created:$(printf '%s' "$stray" | tr '\n' ' ')"; }
  if [ "$good" -eq 1 ]; then ok "$desc"; else bad "$desc" "  $detail"; fi
}

# failed <desc> <prefix> — exactly one stdout line starting with the FAILED prefix and carrying
# an error text after it; exit 0.
failed() {
  local desc="$1" prefix="$2" detail="" good=1 rest
  [ "$RC" -eq 0 ] || { good=0; detail="$detail rc=$RC"; }
  [ "$NLINES" -eq 1 ] || { good=0; detail="$detail lines=$NLINES"; }
  case "$OUT" in
    "$prefix"?*) rest="${OUT#"$prefix"}"; [ -n "$rest" ] || { good=0; detail="$detail empty-error"; } ;;
    *) good=0; detail="$detail stdout=[$OUT]" ;;
  esac
  if [ "$good" -eq 1 ]; then ok "$desc"; else bad "$desc" "  $detail"; fi
}

# untouched <desc> <home> — the hook left nothing behind under the home.
untouched() {
  local stray
  stray="$(tree_of "$2")"
  if [ "$stray" = "." ]; then ok "$1"
  else bad "$1" "  created: $(printf '%s' "$stray" | tr '\n' ' ')"; fi
}

# ── Script under test exists and is executable ──────────────────────────────
if [ -x "$HOOK" ]; then ok "script exists and is executable"
else bad "script exists and is executable" "  not an executable file: $HOOK"; fi

# ── Switching on: message, flag, modes ──────────────────────────────────────
new_home
run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
want "quiet prints the ON line and creates the session flag" "$H" "$ON_LINE" yes
d="$(modeof "$H/$STATE_REL" 2>/dev/null)"
[ "$d" = 700 ] && ok "state directory is mode 0700" || bad "state directory is mode 0700" "  mode=[$d]"
f="$(modeof "$(flag "$H" "$SID_A")" 2>/dev/null)"
[ "$f" = 600 ] && ok "flag file is mode 0600" || bad "flag file is mode 0600" "  mode=[$f]"

for um in 000 022 077; do
  new_home; H2="$H"; UMASK="$um" run "$H2" "$(pj "$PHRASE_QUIET" "$SID_A")"
  d="$(modeof "$H2/$STATE_REL" 2>/dev/null)"; f="$(modeof "$(flag "$H2" "$SID_A")" 2>/dev/null)"
  [ "$d/$f" = 700/600 ] && ok "modes 0700/0600 hold under umask $um" \
    || bad "modes 0700/0600 hold under umask $um" "  dir/file=[$d/$f]"
done

# ── Idempotence ─────────────────────────────────────────────────────────────
run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
want "quiet when already quiet prints ON and keeps the flag" "$H" "$ON_LINE" yes
n="$(ls "$H/$STATE_REL" 2>/dev/null | wc -l | tr -d ' ')"
[ "$n" -eq 1 ] && ok "quiet twice leaves exactly one flag file" || bad "quiet twice leaves exactly one flag file" "  files=$n"

# ── Switching off ───────────────────────────────────────────────────────────
run "$H" "$(pj "$PHRASE_ON" "$SID_A")"
want "on prints the OFF line and removes the session flag" "$H" "$OFF_LINE" no
run "$H" "$(pj "$PHRASE_ON" "$SID_A")"
want "on when already on prints OFF and stays unflagged" "$H" "$OFF_LINE" no

new_home
run "$H" "$(pj "$PHRASE_ON" "$SID_A")"
want "on in a session that never went quiet prints OFF" "$H" "$OFF_LINE" no
[ ! -e "$H/$STATE_REL" ] && ok "on does not create the state directory" \
  || bad "on does not create the state directory" "  $(tree_of "$H" | tr '\n' ' ')"

# ── R14: the flag is per session_id ─────────────────────────────────────────
new_home
run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
run "$H" "$(pj "$PHRASE_ON" "$SID_B")"
has_flag "$H" "$SID_A" && ok "on for session B leaves session A's flag" \
  || bad "on for session B leaves session A's flag" "  A's flag is gone"
run "$H" "$(pj "$PHRASE_QUIET" "$SID_B")"
n="$(ls "$H/$STATE_REL" 2>/dev/null | wc -l | tr -d ' ')"
{ has_flag "$H" "$SID_A" && has_flag "$H" "$SID_B" && [ "$n" -eq 2 ]; } \
  && ok "quiet for session B adds its own file beside A's" \
  || bad "quiet for session B adds its own file beside A's" "  files=$n"
run "$H" "$(pj "$PHRASE_ON" "$SID_A")"
{ ! has_flag "$H" "$SID_A" && has_flag "$H" "$SID_B"; } \
  && ok "on for session A removes only A's flag" \
  || bad "on for session A removes only A's flag" "  A=$(has_flag "$H" "$SID_A" && echo y || echo n) B=$(has_flag "$H" "$SID_B" && echo y || echo n)"

# ── R16: only the whole message, trimmed, case-sensitive ────────────────────
new_home; run "$H" "$(pj "  $PHRASE_QUIET " "$SID_A")"
want "surrounding spaces are trimmed (quiet)" "$H" "$ON_LINE" yes
new_home; run "$H" "$(pj $'\n\t'"$PHRASE_QUIET"$'\n' "$SID_A")"
want "surrounding newlines and tabs are trimmed (quiet)" "$H" "$ON_LINE" yes
new_home; run "$H" "$(pj $' \n'"$PHRASE_ON"$'\t ' "$SID_A")"
want "surrounding whitespace is trimmed (on)" "$H" "$OFF_LINE" no

while IFS= read -r msg; do
  new_home; run "$H" "$(pj "$msg" "$SID_A")"
  silent "other text does nothing: [$msg]" "$H"
done <<'EOF'
should I type git-guard quiet?
Git-Guard Quiet
GIT-GUARD QUIET
git-guard QUIET
Git-guard on
git-guard ON
git-guard  quiet
git-guard quiet please
please git-guard quiet
git-guard quiet.
git-guard quiet?
"git-guard quiet"
`git-guard quiet`
git-guard
quiet
git-guard on now
turn git-guard on
git-guard-quiet
git guard quiet
<task-notification>git-guard quiet</task-notification>
hello
EOF

new_home; run "$H" "$(pj "" "$SID_A")"
silent "an empty message does nothing" "$H"
new_home; run "$H" "$(pj "   " "$SID_A")"
silent "a whitespace-only message does nothing" "$H"
new_home; run "$H" "$(pj $'git-guard quiet\ngit-guard on' "$SID_A")"
silent "two phrases on two lines is not the exact phrase" "$H"
new_home; run "$H" "$(pj $'notes:\ngit-guard quiet' "$SID_A")"
silent "the phrase on a later line of a longer message does nothing" "$H"
new_home; run "$H" "$(pj $'git-guard\xc2\xa0quiet' "$SID_A")"
silent "a non-breaking space inside the phrase does nothing" "$H"

# A message that merely contains the off phrase must not remove a flag that exists.
new_home; run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
run "$H" "$(pj "should I type git-guard on?" "$SID_A")"
{ [ -z "$OUT" ] && has_flag "$H" "$SID_A"; } && ok "text containing 'git-guard on' does not remove an existing flag" \
  || bad "text containing 'git-guard on' does not remove an existing flag" "  stdout=[$OUT]"

# Non-trigger messages stay silent even when the rest of the payload is unusable (R16 before R15).
new_home; run "$H" "$(pj "hello" "../evil")"
silent "an ordinary message with a bad session_id is still silent" "$H"
new_home; run "$H" '{"hook_event_name":"UserPromptSubmit","prompt":"hello"}'
silent "an ordinary message with no session_id is still silent" "$H"
new_home; run "$H" '{"hook_event_name":"UserPromptSubmit","session_id":"'"$SID_A"'"}'
silent "a payload with no prompt does nothing" "$H"
new_home; run "$H" '{"prompt":42,"session_id":"'"$SID_A"'"}'
silent "a non-string prompt does nothing" "$H"

# ── R15: session_id is validated before it becomes a path component ─────────
long129="$(printf 'a%.0s' $(seq 1 129))"
long128="$(printf 'a%.0s' $(seq 1 128))"
bad_ids=( '..' '.' '../evil' 'a/b' '/abs' 'a b' 'a.b' 'a_b' $'tab\tx' $'abc\n' 'héllo' "$long129" )
for sid in "${bad_ids[@]}"; do
  label="$(printf '%s' "$sid" | cut -c1-24 | tr '\n\t' '??')"
  for phrase in "$PHRASE_QUIET" "$PHRASE_ON"; do
    new_home; run "$H" "$(pj "$phrase" "$sid")"
    failed "invalid session_id [$label] with [$phrase] prints FAILED (prompt ON)" "$FAILED_ON_PREFIX"
    untouched "invalid session_id [$label] with [$phrase] changes nothing" "$H"
  done
done

for raw in '{"prompt":"git-guard quiet"}' '{"prompt":"git-guard quiet","session_id":null}' \
           '{"prompt":"git-guard quiet","session_id":12345}' '{"prompt":"git-guard quiet","session_id":["x"]}' \
           '{"prompt":"git-guard quiet","session_id":""}' '{"prompt":"git-guard on"}'; do
  new_home; run "$H" "$raw"
  failed "missing or non-string session_id prints FAILED: $raw" "$FAILED_ON_PREFIX"
  untouched "missing or non-string session_id changes nothing: $raw" "$H"
done

# A bad id for 'on' must not disturb a real session's flag.
new_home; run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
run "$H" "$(pj "$PHRASE_ON" "../$SID_A")"
has_flag "$H" "$SID_A" && ok "an invalid id for 'on' leaves a real flag alone" \
  || bad "an invalid id for 'on' leaves a real flag alone" "  flag gone"

# Boundaries of the allowed shape: 1 and 128 characters are fine, digits and hyphens included.
for sid in 'a' '7' '-' "$long128" 'ABC-def-012'; do
  new_home; run "$H" "$(pj "$PHRASE_QUIET" "$sid")"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$ON_LINE" ] && [ -f "$(flag "$H" "$sid")" ]; then
    ok "valid session_id accepted: ${#sid} chars [$(printf '%s' "$sid" | cut -c1-12)]"
  else bad "valid session_id accepted: ${#sid} chars" "  rc=$RC stdout=[$OUT]"; fi
done

# ── R17: never blocks; every error is the FAILED line and exit 0 ────────────
new_home; run "$H" 'this is not json'
failed "unparseable payload prints FAILED" "$FAILED_ON_PREFIX"
new_home; run "$H" ''
failed "empty stdin prints FAILED" "$FAILED_ON_PREFIX"
for raw in '[]' '"git-guard quiet"' 'null' '42'; do
  new_home; run "$H" "$raw"
  failed "payload that is not a JSON object prints FAILED: $raw" "$FAILED_ON_PREFIX"
done

# Unwritable state directory: 'quiet' cannot create the flag; the printed state is the measured one (ON).
new_home; mkdir -p "$H/$STATE_REL"; chmod 0500 "$H/$STATE_REL" 2>/dev/null
run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
failed "quiet into an unwritable state dir prints FAILED, prompt ON" "$FAILED_ON_PREFIX"
has_flag "$H" "$SID_A" && bad "unwritable dir: no flag appears" "  flag exists" || ok "unwritable dir: no flag appears"

# Unwritable state directory with a live flag: 'on' cannot remove it; the printed state is OFF (still quiet).
new_home; run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"; chmod 0500 "$H/$STATE_REL" 2>/dev/null
run "$H" "$(pj "$PHRASE_ON" "$SID_A")"
failed "on when the flag cannot be removed prints FAILED, prompt OFF" "$FAILED_OFF_PREFIX"
has_flag "$H" "$SID_A" && ok "flag that could not be removed is still there" || bad "flag that could not be removed is still there" "  flag gone"
chmod 0700 "$H/$STATE_REL" 2>/dev/null

# $HOME that is a regular file: the state path cannot exist.
H="$TMP/home-is-a-file"; : >"$H"
run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
failed "HOME that is a file prints FAILED" "$FAILED_ON_PREFIX"

# HOME unset.
( printf '%s' "$(pj "$PHRASE_QUIET" "$SID_A")" | env -u HOME "$HOOK" ) >"$TMP/out" 2>"$TMP/err"; RC=$?
OUT="$(cat "$TMP/out")"; NLINES="$(wc -l <"$TMP/out" | tr -d ' ')"
failed "HOME unset prints FAILED" "$FAILED_ON_PREFIX"

# A pre-existing flag path that is a directory: creating the flag is impossible.
new_home; mkdir -p "$(flag "$H" "$SID_A")"
run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
failed "flag path occupied by a directory prints FAILED" "$FAILED_ON_PREFIX"

# python3 missing from PATH: the hook cannot parse anything; it still must not block.
new_home; mkdir -p "$TMP/emptybin"
HOOK_PATH="$TMP/emptybin" run "$H" "$(pj "$PHRASE_QUIET" "$SID_A")"
failed "python3 missing prints FAILED and exits 0" "$FAILED_ON_PREFIX"
untouched "python3 missing changes nothing" "$H"

# Registration is Task 7 and is deliberately not asserted here.

printf '%d/%d passed\n' "$pass" "$((pass+fail))"
if [ "$fail" -eq 0 ] && [ "$HOOK" = "$DEFAULT_HOOK" ]; then
  ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py "$MARKER_SELF" ) \
    || { printf 'marker write FAILED\n' >&2; exit 1; }
fi
[ "$fail" -eq 0 ]
