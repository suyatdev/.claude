#!/usr/bin/env bash
# Task 4 probe — read-only against the real ~/.claude, then a break/restore
# proof inside a scratch $HOME built from the REAL hooks and settings.json.
# Nothing here writes to the real config.
#
# Deliberately committed, not throwaway: it is the standing re-run of "can this
# check actually go red?" against the real configuration. A green check that has
# never been watched going red proves nothing, and that evidence has to be
# reproducible by the next reader, not just asserted in the feature card.
# Run: bash hooks/verify-hook-wiring.probe.sh "$PWD/hooks/verify-hook-wiring.sh"
set -u

REAL="$HOME/.claude"
HOOK="$1"          # absolute path to verify-hook-wiring.sh under test

lines() { [ -n "$1" ] && printf '%s\n' "$1" | wc -l | tr -d ' ' || echo 0; }

# Baseline taken BEFORE anything runs. Section D compares against this rather than
# against "empty": the real settings.json is routinely already dirty from /model
# rewriting its "model" key (ADR 0032), so a non-empty status says nothing on its
# own. Only a CHANGE between these two snapshots means this probe touched something.
BEFORE="$(git -C "$REAL" status --porcelain -- settings.json hooks 2>/dev/null)"

echo "=== A. why is the real config silent? ==="
[ -e "$REAL/.git" ] && echo "A1 .git present: yes" || echo "A1 .git present: NO"
if branch="$(git -C "$REAL" symbolic-ref -q HEAD 2>&1)"; then
  echo "A2 symbolic-ref HEAD: $branch"
else
  echo "A2 symbolic-ref HEAD: FAILED (detached or mid-rebase) -> check 2 skips"
fi
if blob="$(git -C "$REAL" show HEAD:settings.json 2>&1)"; then
  echo "A3 HEAD:settings.json: present, $(printf '%s' "$blob" | wc -c | tr -d ' ') bytes"
else
  echo "A3 HEAD:settings.json: ABSENT -> check 2 skips ($blob)"
fi
echo "A4 live settings.json: $(wc -c < "$REAL/settings.json" | tr -d ' ') bytes"

echo
echo "=== B. break/restore proof in a scratch HOME built from the REAL files ==="
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/.claude"
cp -R "$REAL/hooks" "$S/.claude/hooks"
cp "$REAL/settings.json" "$S/.claude/settings.json"
[ -f "$REAL/statusline-command.sh" ] && cp "$REAL/statusline-command.sh" "$S/.claude/"

echo "B1 baseline (real settings.json, real hooks, not a repo -> check 1 only):"
out="$(HOME="$S" bash "$HOOK" 2>&1)"; rc=$?
printf '    rc=%s lines=%s\n' "$rc" "$(lines "$out")"
[ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /'

echo "B2 rename judge-guard.sh away (the positive control):"
mv "$S/.claude/hooks/judge-guard.sh" "$S/.claude/hooks/judge-guard.sh.bak"
out="$(HOME="$S" bash "$HOOK" 2>&1)"; rc=$?
printf '    rc=%s lines=%s\n' "$rc" "$(lines "$out")"
printf '%s\n' "$out" | sed 's/^/    /'

echo "B3 restore it, chmod 644 phase-guard.sh instead:"
mv "$S/.claude/hooks/judge-guard.sh.bak" "$S/.claude/hooks/judge-guard.sh"
chmod 644 "$S/.claude/hooks/phase-guard.sh"
out="$(HOME="$S" bash "$HOOK" 2>&1)"; rc=$?
printf '    rc=%s lines=%s\n' "$rc" "$(lines "$out")"
printf '%s\n' "$out" | sed 's/^/    /'

echo "B4 restore mode, confirm it goes quiet again:"
chmod 755 "$S/.claude/hooks/phase-guard.sh"
out="$(HOME="$S" bash "$HOOK" 2>&1)"; rc=$?
printf '    rc=%s lines=%s\n' "$rc" "$(lines "$out")"
[ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /'

echo
echo "=== C. drift proof: scratch repo tracking the REAL settings.json ==="
git -C "$S/.claude" init -q -b main
git -C "$S/.claude" -c user.name=t -c user.email=t@example.invalid add -A
git -C "$S/.claude" -c user.name=t -c user.email=t@example.invalid commit -q -m base
echo "C1 committed as-is -> expect silence:"
out="$(HOME="$S" bash "$HOOK" 2>&1)"; rc=$?
printf '    rc=%s lines=%s\n' "$rc" "$(lines "$out")"
[ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /'

echo "C2 drop phase-guard.sh from the LIVE file only -> expect one drift line:"
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for grp in d["hooks"]["PreToolUse"]:
    grp["hooks"] = [h for h in grp["hooks"] if "phase-guard" not in h["command"]]
d["hooks"]["PreToolUse"] = [g for g in d["hooks"]["PreToolUse"] if g["hooks"]]
json.dump(d, open(p, "w"), indent=2)
' "$S/.claude/settings.json"
out="$(HOME="$S" bash "$HOOK" 2>&1)"; rc=$?
printf '    rc=%s lines=%s\n' "$rc" "$(lines "$out")"
printf '%s\n' "$out" | sed 's/^/    /'

echo "C3 also flip permissions.defaultMode -> expect a second, permissions line:"
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["permissions"]["defaultMode"] = "bypassPermissions"
json.dump(d, open(p, "w"), indent=2)
' "$S/.claude/settings.json"
out="$(HOME="$S" bash "$HOOK" 2>&1)"; rc=$?
printf '    rc=%s lines=%s\n' "$rc" "$(lines "$out")"
printf '%s\n' "$out" | sed 's/^/    /'

echo "C4 restore the live file from HEAD -> expect silence again:"
git -C "$S/.claude" checkout -- settings.json
out="$(HOME="$S" bash "$HOOK" 2>&1)"; rc=$?
printf '    rc=%s lines=%s\n' "$rc" "$(lines "$out")"
[ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/    /'

echo
echo "=== D. the real ~/.claude was not touched ==="
AFTER="$(git -C "$REAL" status --porcelain -- settings.json hooks 2>/dev/null)"
echo "D1 status before: ${BEFORE:-(clean)}"
echo "D2 status after:  ${AFTER:-(clean)}"
if [ "$BEFORE" = "$AFTER" ]; then
  echo "D3 UNCHANGED — this probe touched nothing in the real ~/.claude"
else
  echo "D3 CHANGED — this probe modified the real ~/.claude. Investigate before trusting B/C."
fi
