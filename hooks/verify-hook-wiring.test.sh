#!/usr/bin/env bash
# verify-hook-wiring.test.sh — unit tests for verify-hook-wiring.sh.
#
# Run: bash hooks/verify-hook-wiring.test.sh
#
# Every case builds a throwaway ~/.claude under a FAKE $HOME and drives the hook
# with HOME pointed at it. Nothing here reads or writes the real ~/.claude — the
# hook resolves everything from $HOME by contract, so overriding HOME is both the
# isolation mechanism and a test of that contract.
#
# What each case asserts, always: exit 0, an exact stdout line count, empty
# stderr, the wanted substrings present and the unwanted ones ABSENT. The absent
# list is where the real proof lives. A check that over-reports is the failure
# mode this whole feature is built to avoid — a reader who learns to skip the
# output is worse off than one who never had the check — so a case that only
# asserted "the finding is present" would pass against a hook that shouts about
# every hook in the file.
#
# Two paths are deliberately left BROKEN in the healthy fixture and forbidden in
# every assertion: $HOME/.orca/agent-hooks/claude-hook.sh (referenced four times
# inside one `if [ -f ... ]` conditional — unparseable, must be skipped) and
# $HOME/.claude/statusline-command.sh (statusLine is not a hook and is out of
# check 1's scope). Neither file is ever created. If either name appears in the
# output, extraction has over-reached.
set -u
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1

HOOK="$(cd "$(dirname "$0")" && pwd)/verify-hook-wiring.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s\n%s\n' "$1" "$2"; fail=$((fail+1)); }

# The fixture repos live under a fake HOME, so there is no ~/.gitconfig to name a
# committer and no system config to inherit. Both are supplied here rather than
# written into each repo, so a fixture is one `git init` and nothing else.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

# A trimmed copy of the real settings.json: the three command shapes that
# actually occur (bare $HOME path; $HOME path plus an argument; the orca
# `if [ -f ... ]` conditional), one non-hook statusLine, and both of the keys
# check 2 must ignore.
base_settings() { cat <<'JSON'
{
  "permissions": { "defaultMode": "default" },
  "model": "opus[1m]",
  "effortLevel": "xhigh",
  "theme": "dark",
  "tui": "fullscreen",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/git-guard.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/doc-guard.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/judge-guard.sh" }
        ]
      },
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f \"$HOME/.orca/agent-hooks/claude-hook.sh\" ] && [ -r \"$HOME/.orca/agent-hooks/claude-hook.sh\" ] && [ -x \"$HOME/.orca/agent-hooks/claude-hook.sh\" ]; then /bin/sh \"$HOME/.orca/agent-hooks/claude-hook.sh\"; else cat >/dev/null 2>&1 || :; fi",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/memsearch-nudge.sh" },
          { "type": "command", "command": "$HOME/.claude/hooks/handoff/proactive-handoff.sh save" }
        ]
      }
    ]
  },
  "statusLine": { "type": "command", "command": "bash \"$HOME/.claude/statusline-command.sh\"" },
  "enabledPlugins": { "superpowers@claude-plugins-official": true }
}
JSON
}

REAL_HOOKS="git-guard.sh doc-guard.sh judge-guard.sh memsearch-nudge.sh"

stub_script() { printf '#!/bin/sh\nexit 0\n' > "$1"; chmod 755 "$1"; }

new_home() { # $1 case name -> echoes the fake HOME path
  local h="$TMP/$1" s
  mkdir -p "$h/.claude/hooks/handoff"
  for s in $REAL_HOOKS; do stub_script "$h/.claude/hooks/$s"; done
  stub_script "$h/.claude/hooks/handoff/proactive-handoff.sh"
  base_settings > "$h/.claude/settings.json"
  git -C "$h/.claude" init -q -b main
  git -C "$h/.claude" add -A
  git -C "$h/.claude" commit -q -m base
  printf '%s' "$h"
}

# Mutates a settings.json in place. The python body arrives as argv[2] and is
# exec'd, so a `$HOME` inside it is inert text — bash never re-expands the
# result of an expansion, and the body itself is always single-quoted here.
edit_json() { # $1 file, $2 python body operating on the dict `d`
  python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
exec(sys.argv[2])
json.dump(d, open(p, "w"), indent=2)
' "$1" "$2"
}

DROP_JUDGE='g = d["hooks"]["PreToolUse"][0]["hooks"]
d["hooks"]["PreToolUse"][0]["hooks"] = [h for h in g if "judge-guard" not in h["command"]]'

# ---------------------------------------------------------------------------
# Assertion
# ---------------------------------------------------------------------------
check() { # $1 desc, $2 fake HOME, $3 want-lines, $4 "pat|pat|..", $5 "notpat|.."
  local desc="$1" h="$2" want="$3" wants="$4" nots="$5" out rc err lines ok_=1 detail=""
  out="$(HOME="$h" bash "$HOOK" 2>"$TMP/stderr")"; rc=$?
  err="$(cat "$TMP/stderr")"
  lines=0; [ -n "$out" ] && lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  [ "$rc" -eq 0 ] || { ok_=0; detail="$detail rc=$rc(want 0)"; }
  [ -z "$err" ] || { ok_=0; detail="$detail stderr:<$err>"; }
  [ "$lines" -eq "$want" ] || { ok_=0; detail="$detail lines=$lines want=$want"; }
  local IFS='|'
  for p in $wants; do
    [ -z "$p" ] && continue
    case "$out" in (*"$p"*) ;; (*) ok_=0; detail="$detail missing:<$p>";; esac
  done
  for p in $nots; do
    [ -z "$p" ] && continue
    case "$out" in (*"$p"*) ok_=0; detail="$detail unwanted:<$p>";; esac
  done
  unset IFS
  if [ "$ok_" -eq 1 ]; then ok "$desc"; else bad "$desc" "  got: $out
  why:$detail"; fi
}

PFX='verify-hook-wiring:'
ORCA='claude-hook.sh'
SL='statusline-command.sh'

# ===========================================================================
# Scenario: healthy wiring stays silent
# ===========================================================================
H="$(new_home healthy)"
check "healthy wiring stays silent" "$H" 0 "" ""

# ===========================================================================
# Scenario: a registered hook's script has been renamed away
# ===========================================================================
H="$(new_home renamed)"; rm -f "$H/.claude/hooks/doc-guard.sh"
check "renamed-away script: named, with its event, as unable to run" "$H" 1 \
  "$PFX|doc-guard.sh|PreToolUse" \
  "git-guard.sh|judge-guard.sh|memsearch-nudge.sh|$ORCA|$SL|drift"

# ===========================================================================
# Scenario: a hook script exists but is not executable
# ===========================================================================
H="$(new_home notexec)"; chmod 644 "$H/.claude/hooks/judge-guard.sh"
check "existing but mode 644: named as not executable" "$H" 1 \
  "$PFX|judge-guard.sh|not executable" \
  "doc-guard.sh|$ORCA|$SL|drift"

# A missing file and an unexecutable one are different repairs, so they must not
# render as the same sentence.
H="$(new_home twobroken)"
rm -f "$H/.claude/hooks/git-guard.sh"; chmod 644 "$H/.claude/hooks/doc-guard.sh"
check "every broken hook gets its own line" "$H" 2 \
  "git-guard.sh|doc-guard.sh|not executable" "judge-guard.sh|$ORCA|$SL"

# A hook nested a directory deeper, invoked with an argument — the shape
# `handoff/proactive-handoff.sh save` takes. The argument must not be mistaken
# for part of the path.
H="$(new_home withargs)"; rm -f "$H/.claude/hooks/handoff/proactive-handoff.sh"
check "a command with an argument still resolves its script" "$H" 1 \
  "$PFX|proactive-handoff.sh|SessionStart" "git-guard.sh|$ORCA|$SL"

# ===========================================================================
# Scenario: switching models does not trigger the drift check
# ===========================================================================
H="$(new_home modelswitch)"
edit_json "$H/.claude/settings.json" 'd["model"] = "sonnet"; d["effortLevel"] = "low"'
check "model/effortLevel drift is not reported" "$H" 0 "" ""

# theme and tui are preferences, not wiring — ignored for the same reason.
H="$(new_home prefs)"
edit_json "$H/.claude/settings.json" 'd["theme"] = "light"; d["tui"] = "inline"'
check "a preference change is not drift" "$H" 0 "" ""

# The comparison is semantic, not textual: reindenting and sorting every key
# rewrites the whole file byte-for-byte without changing one setting.
H="$(new_home reformat)"
# Read fully before opening for write: `open(p, "w").write(json.load(open(p)))`
# truncates the file before the load runs, leaving an empty settings.json that
# this case would then pass against for the wrong reason.
python3 -c 'import json, sys
p = sys.argv[1]
text = json.dumps(json.load(open(p)), indent=4, sort_keys=True)
open(p, "w").write(text)' "$H/.claude/settings.json"
check "reformatting the file is not drift" "$H" 0 "" ""

# ===========================================================================
# Scenario: a guard was removed from the live file
# ===========================================================================
H="$(new_home removed)"
edit_json "$H/.claude/settings.json" "$DROP_JUDGE"
check "a guard in HEAD but absent locally is named" "$H" 1 \
  "$PFX|judge-guard.sh|HEAD" "not executable|doc-guard.sh|$ORCA|$SL"

# The other direction: wiring that was never reviewed, added by hand to the live
# file. Its script exists, so check 1 has nothing to say about it.
H="$(new_home added)"
stub_script "$H/.claude/hooks/rogue.sh"
edit_json "$H/.claude/settings.json" \
  'd["hooks"]["PreToolUse"][0]["hooks"].append(
     {"type": "command", "command": "$HOME/.claude/hooks/rogue.sh"})'
check "a guard present locally but not in HEAD is named" "$H" 1 \
  "$PFX|rogue.sh" "not executable|git-guard.sh|$ORCA|$SL"

# permissions.defaultMode is the value PR #63's judge caught drifting — a
# security posture change nobody announced. It is a wiring key, so it reports.
#
# Naming the sub-key and both values is the whole point of these cases. This
# feature exists BECAUSE that drift went unnoticed, so "permissions differs" is
# the one output it cannot afford: it tells the reader something moved and then
# makes them go diff the file by hand to learn what. The hooks key already gets
# per-item detail; the other wiring keys were reporting at key level only.
H="$(new_home perms)"
edit_json "$H/.claude/settings.json" 'd["permissions"]["defaultMode"] = "bypassPermissions"'
check "a changed sub-key is named, with both values" "$H" 1 \
  "$PFX|permissions.defaultMode|bypassPermissions|default" \
  "not executable|no such file|$ORCA|$SL"

H="$(new_home permsadd)"
edit_json "$H/.claude/settings.json" 'd["permissions"]["allow"] = ["Bash(ls:*)"]'
check "a sub-key only in the live file is named as added" "$H" 1 \
  "$PFX|permissions.allow|absent from HEAD" \
  "not executable|no such file|$ORCA|$SL"

H="$(new_home permsdel)"
edit_json "$H/.claude/settings.json" 'del d["permissions"]["defaultMode"]'
check "a sub-key only in HEAD is named as removed" "$H" 1 \
  "$PFX|permissions.defaultMode|absent from the live file" \
  "not executable|no such file|$ORCA|$SL"

# Two independent movements must not collapse into one vague line.
H="$(new_home permstwo)"
edit_json "$H/.claude/settings.json" \
  'd["permissions"]["defaultMode"] = "acceptEdits"
d["permissions"]["deny"] = ["Read(./.env)"]'
check "two changed sub-keys produce two lines" "$H" 2 \
  "$PFX|permissions.defaultMode|permissions.deny" \
  "not executable|no such file|$ORCA|$SL"

# statusLine is an object too, so it gets the same treatment — the sub-key is
# named. Its value is deliberately NOT printed: a command string carries quotes,
# `$HOME` and a path, so it fails the safe-value shape, and of everything under
# the wiring keys it is the likeliest place for a credential to be hiding in an
# argument. Naming `statusLine.command` already tells the reader a status-line
# command changed, which is the actionable part.
H="$(new_home slkey)"
edit_json "$H/.claude/settings.json" \
  'd["statusLine"]["command"] = "bash \"$HOME/.claude/other-line.sh\""'
check "a statusLine sub-key is named, its command withheld" "$H" 1 \
  "$PFX|statusLine.command|changed" \
  "other-line.sh|not executable|no such file|$ORCA|$SL"

# Printing values is new, and it is the one thing this change added that could
# leak. settings.json is not supposed to hold credentials — `env` is excluded
# from WIRING_KEYS for that reason — but "supposed to" is a convention, and this
# check exists precisely because conventions drift unobserved. These two cases
# turn it into a mechanism. Both must still NAME the sub-key: knowing a secret-
# shaped setting moved is the finding; printing it is not.
# Both sides must HOLD the key for the value-printing path to run at all, so
# this one commits it to HEAD first and then changes it live. Written the naive
# way first — set it only in the live file — which turned out to exercise the
# added-sub-key branch instead, and that branch prints no value to redact. The
# test was wrong, not the hook.
H="$(new_home redactname)"
edit_json "$H/.claude/settings.json" 'd["permissions"]["apiKey"] = "sk-head-must-not-appear"'
git -C "$H/.claude" commit -qam withkey
edit_json "$H/.claude/settings.json" 'd["permissions"]["apiKey"] = "sk-live-must-not-appear"'
check "a secret-shaped sub-key name redacts both values" "$H" 1 \
  "$PFX|permissions.apiKey|redacted" \
  "sk-live-must-not-appear|sk-head-must-not-appear|not executable|no such file|$ORCA|$SL"

# Verdict 209 found the gap these two close: the word filter only catches a
# LABELLED secret, and most real credentials are opaque strings under ordinary
# names. Truncating such a value and printing the prefix leaks it just as
# thoroughly as printing all of it — 57 characters of a JWT is still a JWT.
JWT='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.dQw4w9WgXcQ1234567890abcdefghijklmnop'
H="$(new_home longvalue)"
edit_json "$H/.claude/settings.json" "d['permissions']['defaultMode'] = '$JWT'"
git -C "$H/.claude" commit -qam withjwt
edit_json "$H/.claude/settings.json" "d['permissions']['defaultMode'] = '${JWT}CHANGED'"
check "an over-long value is withheld, not truncated and leaked" "$H" 1 \
  "$PFX|permissions.defaultMode|changed" \
  "eyJhbGciOiJIUzI1|not executable|no such file|$ORCA|$SL"

# An opaque token that fits inside the length cap: no sensitive word anywhere,
# ordinary sub-key name. A long unbroken alphanumeric run mixing letters and
# digits is what a credential looks like and what config values do not.
OPAQUE='a1b2c3d4e5f6g7h8i9j0k1l2m3'
H="$(new_home opaque)"
edit_json "$H/.claude/settings.json" "d['permissions']['defaultMode'] = '$OPAQUE'"
check "an opaque token under a plain name is withheld" "$H" 1 \
  "$PFX|permissions.defaultMode" \
  "$OPAQUE|not executable|no such file|$ORCA|$SL"

# Verdict 210: standard base64 uses + and /, which BREAK a [A-Za-z0-9_-] run
# into harmless-looking pieces. A 40-byte secret encodes to ~56 characters —
# under the old 60-char cap — so neither the length nor the shape test caught
# it. Measured at roughly one in six random AWS-length keys. This is the case
# that forced the renderer to default-deny instead of default-print.
B64='Xy9+aB/cD3eF+gH4iJ/kL5mN+oP6qR/sT7uV+wX8yZ0='
H="$(new_home base64secret)"
edit_json "$H/.claude/settings.json" "d['permissions']['defaultMode'] = '$B64'"
check "a standard-base64 secret is withheld" "$H" 1 \
  "$PFX|permissions.defaultMode" \
  "$B64|Xy9+aB|not executable|no such file|$ORCA|$SL"

# A structure is not a legible value: there is no one-line rendering of a list
# that helps a reader, and plenty that could hide a credential inside.
H="$(new_home structure)"
edit_json "$H/.claude/settings.json" \
  'd["permissions"]["defaultMode"] = {"nested": "Xy9+aB/cD3eF+gH4iJ/kL5mN"}'
check "a structured value is withheld, not rendered" "$H" 1 \
  "$PFX|permissions.defaultMode|changed" \
  "Xy9+aB|nested|not executable|no such file|$ORCA|$SL"

# The added/removed branches never render a value, so a secret arriving under a
# brand-new key cannot leak through them. Asserted rather than assumed, because
# that is a property of the code today and nothing else pins it.
H="$(new_home redactadded)"
edit_json "$H/.claude/settings.json" 'd["permissions"]["apiKey"] = "sk-live-must-not-appear"'
check "a secret added under a new sub-key names the key without its value" "$H" 1 \
  "$PFX|permissions.apiKey|absent from HEAD" \
  "sk-live-must-not-appear|not executable|no such file|$ORCA|$SL"

H="$(new_home redactvalue)"
edit_json "$H/.claude/settings.json" \
  'd["permissions"]["defaultMode"] = "default AUTH_TOKEN=must-not-appear"'
check "a secret-shaped value redacts even under a plain name" "$H" 1 \
  "$PFX|permissions.defaultMode|redacted" \
  "must-not-appear|not executable|no such file|$ORCA|$SL"

# When a wiring key stops being an object there is no sub-key to name, so the
# key-level line has to remain — recursion must not become the only path.
H="$(new_home slscalar)"
edit_json "$H/.claude/settings.json" 'd["statusLine"] = "no-longer-an-object"'
check "a key that stops being an object still reports at key level" "$H" 1 \
  "$PFX|statusLine" \
  "not executable|no such file|$ORCA"

# ===========================================================================
# Scenario: the check cannot do its job and says nothing
# ===========================================================================
H="$(new_home badjson)"; printf 'not json at all' > "$H/.claude/settings.json"
check "malformed settings.json -> silent" "$H" 0 "" ""

H="$(new_home nosettings)"; rm -f "$H/.claude/settings.json"
check "absent settings.json -> silent" "$H" 0 "" ""

# ===========================================================================
# Scenario: ~/.claude is mid-rebase
# ===========================================================================
# Both checks are armed before the assertion: a hook script is deleted (check 1
# must speak) AND the live file drifts from HEAD (check 2 must not). Without the
# second half, "skipped" would be indistinguishable from "ran and found nothing".
H="$(new_home rebasing)"; G="$H/.claude"
git -C "$G" checkout -q -b feature
printf 'B\n' > "$G/README.md"; git -C "$G" add README.md; git -C "$G" commit -q -m B
git -C "$G" checkout -q main
printf 'C\n' > "$G/README.md"; git -C "$G" add README.md; git -C "$G" commit -q -m C
git -C "$G" checkout -q feature
git -C "$G" rebase main >/dev/null 2>&1 || true
if [ -d "$G/.git/rebase-merge" ] || [ -d "$G/.git/rebase-apply" ]; then
  ok "fixture: the rebase really did stop mid-flight"
else
  bad "fixture: mid-rebase" "  no rebase-merge/rebase-apply directory — the case below proves nothing"
fi
rm -f "$G/hooks/git-guard.sh"
edit_json "$G/settings.json" "$DROP_JUDGE"
check "mid-rebase: check 1 runs, check 2 is skipped without comment" "$H" 1 \
  "$PFX|git-guard.sh" "judge-guard|HEAD|drift"

# A plain detached HEAD, same reasoning: check 2 has no branch to compare on.
H="$(new_home detached)"
git -C "$H/.claude" checkout -q --detach
edit_json "$H/.claude/settings.json" "$DROP_JUDGE"
check "detached HEAD: drift check skipped" "$H" 0 "" ""

# Not a git repo at all — every session in every repo runs this, and ~/.claude
# is not guaranteed to be a checkout on someone else's machine.
H="$(new_home norepo)"
rm -rf "$H/.claude/.git"; rm -f "$H/.claude/hooks/doc-guard.sh"
check "not a git repo: check 1 runs, check 2 skipped" "$H" 1 \
  "doc-guard.sh" "drift|HEAD"

# Tracked once, untracked later: HEAD has no settings.json blob to compare.
H="$(new_home untracked)"
git -C "$H/.claude" rm -q --cached settings.json
git -C "$H/.claude" commit -q -m "stop tracking settings.json"
edit_json "$H/.claude/settings.json" "$DROP_JUDGE"
check "no settings.json in HEAD: drift check skipped" "$H" 0 "" ""

# ===========================================================================
# Scenario: an unparseable command string is not reported as broken
# ===========================================================================
# The orca conditional in every fixture already covers the shape that occurs in
# production. This is a second shape — a pipeline into a script that does not
# exist — committed first so that check 2 has nothing to say and any output can
# only have come from check 1 over-reaching.
H="$(new_home unparseable)"
edit_json "$H/.claude/settings.json" \
  'd["hooks"]["Stop"] = [{"hooks": [{"type": "command",
     "command": "cat /dev/null | $HOME/.claude/hooks/nope.sh && echo done"}]}]'
git -C "$H/.claude" commit -q -am "register an unparseable command"
check "an unparseable command is skipped, not reported" "$H" 0 "" ""

# ===========================================================================
# Registration — an unregistered hook protects nothing
# ===========================================================================
if python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
hits = [g for grp in s.get("hooks", {}).get("SessionStart", [])
        for g in grp.get("hooks", [])
        if "verify-hook-wiring.sh" in g.get("command", "")]
raise SystemExit(0 if len(hits) == 1 else 1)' "$ROOT/settings.json"; then
  ok "registered exactly once on SessionStart in settings.json"
else
  bad "registration" "  verify-hook-wiring.sh is not registered once on SessionStart"
fi

printf '\n%d/%d passed\n' "$pass" "$((pass+fail))"
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
[ "$fail" -eq 0 ]
