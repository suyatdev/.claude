#!/usr/bin/env bash
# Task 5 — wall-clock measurement against the =<150 ms session-start budget.
# Two configurations, because they cost different amounts: the machine as it is
# today (HEAD:settings.json absent, so check 2 short-circuits) and a checkout
# where check 2 actually runs both git calls and the semantic comparison.
set -u
HOOK="$1"
N=20

# TRUE_HOME is what the hook must be given; REAL is the config dir inside it.
# Passing REAL as HOME instead makes the hook look for ~/.claude/.claude and
# exit before python ever starts -- a 3 ms "measurement" of the early return.
TRUE_HOME="$HOME"
REAL="$TRUE_HOME/.claude"

# A scratch HOME whose ~/.claude IS a committed repo, so check 2 runs in full.
S="$(mktemp -d)"
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/.claude"
cp -R "$REAL/hooks" "$S/.claude/hooks"
cp "$REAL/settings.json" "$S/.claude/settings.json"
git -C "$S/.claude" init -q -b main
git -C "$S/.claude" -c user.name=t -c user.email=t@example.invalid add -A
git -C "$S/.claude" -c user.name=t -c user.email=t@example.invalid commit -q -m base

ms_per_run() { # $1 = HOME to use -> mean ms over $N runs
  local h="$1" start end i
  start=$(python3 -c 'import time; print(int(time.time()*1000))')
  i=0
  while [ "$i" -lt "$N" ]; do
    HOME="$h" bash "$HOOK" >/dev/null 2>&1
    i=$((i+1))
  done
  end=$(python3 -c 'import time; print(int(time.time()*1000))')
  echo $(( (end - start) / N ))
}

# One untimed pass per configuration so the page cache and git's object cache
# are warm -- the budget is stated for a warm cache, and a cold first run would
# measure the disk, not the hook.
HOME="$TRUE_HOME" bash "$HOOK" >/dev/null 2>&1
HOME="$S" bash "$HOOK" >/dev/null 2>&1

# A timing run that never reached python would be indistinguishable from a fast
# one, so state up front that each configuration actually read its settings.json.
echo "sanity — each configuration must find a settings.json to parse:"
for h in "$TRUE_HOME" "$S"; do
  printf '  HOME=%-20s settings.json readable: %s\n' \
    "$(basename "$h")" "$([ -f "$h/.claude/settings.json" ] && echo yes || echo NO)"
done
echo

echo "runs per configuration: $N"
echo "check 2 short-circuits (this machine today): $(ms_per_run "$TRUE_HOME") ms/run"
echo "check 2 runs in full (committed ~/.claude):  $(ms_per_run "$S") ms/run"
echo
echo "for scale, the fixed cost of the interpreter alone:"
start=$(python3 -c 'import time; print(int(time.time()*1000))')
i=0; while [ "$i" -lt "$N" ]; do python3 -c pass; i=$((i+1)); done
end=$(python3 -c 'import time; print(int(time.time()*1000))')
echo "bare python3 -c pass: $(( (end - start) / N )) ms/run"
