#!/usr/bin/env bash
# registered-hooks-executable.test.sh -- every hook script registered in settings.json must be
# stored in git as mode 100755. A script stored 100644 cannot be started by Claude Code (exit
# 126), so the hook it implements silently does nothing. Spec: docs/features/hook-exec-bit-test.md
# (R1-R7a).
# Run BY HAND: bash hooks/registered-hooks-executable.test.sh
# There is no CI and nothing runs this when a hook is added (R7a); run it after editing
# settings.json or adding a hook script.
#
# What it reads: settings.json and file modes come from the git INDEX (git show :settings.json,
# git ls-files -s), never the working tree, so a local chmod +x cannot hide a 100644 that a fresh
# clone would receive. Checking is one function, check_repo <repo-root>; the suite runs it against
# throwaway fixture repos (to prove it can both fail and pass), then once against the repository
# that contains this file. Every fixture builds its own repo in its own mktemp -d.
#
# Known limit, accepted: a parser regression that loses SOME scripts (say 23 -> 20) still passes;
# the printed counts and a by-hand comparison are the only guard against that.
set -u
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)" || { printf 'FAIL — mktemp -d failed; cannot build fixtures\n' >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT
export GIT_CEILING_DIRECTORIES="$TMP"
HERE="$(cd "$(dirname "$0")" && pwd -P)"
OUT=""; RC=0; n_repo=0
pass=0; fail=0

# ------------------------------------------------------------------ the checker
# check_repo <repo-root>: prints "ok/skip/FAIL" lines, a counts line and "result: PASS|FAIL";
# exit 0 when clean, 1 otherwise. Runs every git command as git -C <repo-root>.
check_repo() {
  python3 -I - "$1" <<'PY'
import json, re, shlex, subprocess, sys

sys.stdout.reconfigure(encoding="utf-8")
root = sys.argv[1]
INTERPRETERS = ("bash", "sh", "zsh", "python3", "python", "node")
PREFIXES = ("$HOME/.claude/", "${HOME}/.claude/", "~/.claude/")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SHORT_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
EXEC_MODE = "100755"
SHOW = 100


def git(*args):
    return subprocess.run(["git", "-C", root] + list(args),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def short(cmd):
    return cmd if len(cmd) <= SHOW else cmd[:SHOW] + "…"


def die(msg):
    print("FAIL " + msg)
    print("result: FAIL")
    sys.exit(1)


if git("rev-parse", "--git-dir").returncode != 0:
    die("not a git repository (or not enterable): " + root)

shown = git("show", ":settings.json")
if shown.returncode != 0:
    die("settings.json is missing from the git index of " + root)
try:
    settings = json.loads(shown.stdout.decode("utf-8"))
except (ValueError, UnicodeDecodeError) as err:
    die("settings.json in the index is not valid JSON: " + str(err))
if not isinstance(settings, dict):
    die("settings.json in the index is valid JSON but not an object")

problems = []
entries = []  # (event, handler)
hooks = settings.get("hooks", {})
if not isinstance(hooks, dict):
    problems.append("settings.json 'hooks' is not an object")
    hooks = {}
for event, groups in hooks.items():
    if not isinstance(groups, list):
        problems.append("hook event %s is not a list" % event)
        continue
    for group in groups:
        inner = group.get("hooks") if isinstance(group, dict) else None
        if not isinstance(inner, list):
            problems.append("a group under hook event %s has no 'hooks' list" % event)
            continue
        for handler in inner:
            entries.append((event, handler))
if settings.get("statusLine") is not None:
    entries.append(("statusLine", settings["statusLine"]))


def classify(cmd):
    """Return ('checked', repo-relative-path) | ('interpreter', None) | ('other', None)."""
    words = shlex.split(cmd)
    while words and ASSIGN.match(words[0]):
        words.pop(0)
    if not words:
        return ("other", None)
    first = words[0]
    for prefix in PREFIXES:
        if first.startswith(prefix):
            return ("checked", first[len(prefix):])
    if first not in INTERPRETERS:
        return ("other", None)
    has_c = has_file = False
    rest = words[1:]
    for i, word in enumerate(rest):
        if word == "--":
            has_file = i + 1 < len(rest)
            break
        if word.startswith("--"):
            continue
        if word.startswith("-") and len(word) > 1:
            if SHORT_C.match(word):
                has_c = True
                break
            continue
        has_file = True
        break
    return ("interpreter", None) if has_file and not has_c else ("other", None)


checked = {}   # repo-relative path -> events, in first-seen order
skipped = []   # (event, reason, command)
for event, handler in entries:
    cmd = handler.get("command") if isinstance(handler, dict) else None
    if not isinstance(cmd, str) or not cmd.strip():
        skipped.append((event, "no command", ""))
        continue
    try:
        kind, path = classify(cmd)
    except ValueError as err:
        problems.append("cannot split the command on %s (%s): %s" % (event, err, short(cmd)))
        continue
    if kind == "checked":
        events = checked.setdefault(path, [])
        if event not in events:
            events.append(event)
    elif kind == "interpreter":
        skipped.append((event, "interpreter", cmd))
    else:
        skipped.append((event, "other command", cmd))
        if ".claude/" in cmd:
            problems.append(
                "unread .claude/ path in a skipped command on %s: %s -- a likely repo path in a "
                "shape the parser does not read; teach the parser or explain it, never skip it "
                "silently" % (event, short(cmd)))

for event, reason, cmd in skipped:
    print("skip  [%s] %s%s" % (event, reason, ": " + short(cmd) if cmd else ""))

if not checked:
    problems.append("found no registered hook scripts — the parser is broken, not the repo clean")

modes = {}
listing = git("ls-files", "-s", "-z").stdout.decode("utf-8", "replace")
for item in listing.split("\0"):
    meta, _, path = item.partition("\t")
    if meta and path:
        modes.setdefault(path, meta.split()[0])

for path in sorted(checked):
    where = ", ".join(checked[path])
    mode = modes.get(path)
    if mode is None:
        problems.append("%s is registered on %s but missing from the git index" % (path, where))
    elif mode != EXEC_MODE:
        problems.append("%s is registered on %s but stored as mode %s, needs %s"
                        % (path, where, mode, EXEC_MODE))
    else:
        print("ok    %s (%s) registered on: %s" % (path, mode, where))

for problem in problems:
    print("FAIL " + problem)
print("counts: entries read %d | checked scripts (distinct) %d | skipped commands %d"
      % (len(entries), len(checked), len(skipped)))
print("result: " + ("FAIL (%d problems)" % len(problems) if problems else "PASS"))
sys.exit(1 if problems else 0)
PY
}

# ------------------------------------------------------------------ fixture builders
say_ok() { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
say_bad() { printf 'FAIL — %s\n  %s\n' "$1" "$2"; fail=$((fail+1)); }

new_repo() { # sets REPO to a fresh git repo of its own (no case inherits another's state)
  n_repo=$((n_repo+1)); REPO="$TMP/fix.$n_repo"
  mkdir -p "$REPO" && git -C "$REPO" init -q || { say_bad "fixture $n_repo" "git init failed in $REPO"; exit 1; }
}

add_script() { # $1 repo, $2 relpath, $3 index mode (755|644), $4 disk mode (755|644, default = $3)
  mkdir -p "$(dirname "$1/$2")"
  printf '#!/bin/sh\nexit 0\n' > "$1/$2"
  chmod "${4:-$3}" "$1/$2"
  git -C "$1" add -- "$2"
  if [ "$3" = 755 ]; then git -C "$1" update-index --chmod=+x -- "$2"; else git -C "$1" update-index --chmod=-x -- "$2"; fi
}

put_settings() { # $1 repo, then "Event<TAB>command" args ("@nocmd" = a hook with no command
  # field; event "statusLine" = the top-level statusLine key); written and staged
  python3 -I - "$@" <<'PY'
import json, sys
repo, specs = sys.argv[1], sys.argv[2:]
out = {"hooks": {}}
for spec in specs:
    event, _, cmd = spec.partition("\t")
    handler = {"type": "command"} if cmd == "@nocmd" else {"type": "command", "command": cmd}
    if event == "statusLine":
        out["statusLine"] = handler
    else:
        out["hooks"].setdefault(event, []).append({"hooks": [handler]})
with open(repo + "/settings.json", "w") as f:
    json.dump(out, f)
PY
  git -C "$1" add -- settings.json
}

T="$(printf '\t')"
run_check() { OUT="$(check_repo "$1" 2>&1)"; RC=$?; }

expect_fail() { # $1 desc, $2 repo, rest: strings the output must contain
  local desc="$1" repo="$2" needle; shift 2
  run_check "$repo"
  [ "$RC" -ne 0 ] || { say_bad "$desc" "wanted a failure, got rc=0"$'\n'"$OUT"; return; }
  for needle in "$@"; do
    case "$OUT" in *"$needle"*) ;; *) say_bad "$desc" "output lacks: $needle"$'\n'"$OUT"; return ;; esac
  done
  say_ok "$desc"
}
expect_pass() { # same, for a clean run
  local desc="$1" repo="$2" needle; shift 2
  run_check "$repo"
  [ "$RC" -eq 0 ] || { say_bad "$desc" "wanted a pass, got rc=$RC"$'\n'"$OUT"; return; }
  for needle in "$@"; do
    case "$OUT" in *"$needle"*) ;; *) say_bad "$desc" "output lacks: $needle"$'\n'"$OUT"; return ;; esac
  done
  say_ok "$desc"
}
lacks() { # $1 desc, $2 needle the LAST run's output must not hold (call right after expect_*)
  case "$OUT" in *"$2"*) say_bad "$1" "output unexpectedly contains: $2"$'\n'"$OUT" ;; *) say_ok "$1" ;; esac
}

# ------------------------------------------------------------------ R6 fixture cases
printf '== fixtures (each builds its own repo) ==\n'

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 644
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
expect_fail "a 100644 registered script fails, naming path, event and mode" "$r" "hooks/x.sh" "Stop" "100644"

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
expect_pass "the same script at 100755 passes and prints its counts" "$r" "result: PASS" "checked scripts (distinct) 1"

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 644 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
[ -x "$r/hooks/x.sh" ] || say_bad "fixture sanity" "hooks/x.sh should be executable on disk"
expect_fail "100644 in the index but executable on disk still fails (a local chmod hides nothing)" "$r" "hooks/x.sh" "100644"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
add_script "$r" statusline.sh 644
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "statusLine${T}bash \"\$HOME/.claude/statusline.sh\""
expect_pass "an interpreter-invoked 100644 script passes and is listed as skipped (interpreter)" "$r" "skip  [statusLine] interpreter"
lacks "the interpreter-invoked script is not reported as a failure" "FAIL"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
add_script "$r" hooks/y.sh 644
add_script "$r" hooks/z.py 644
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}bash -e \$HOME/.claude/hooks/y.sh" "Stop${T}python3 -I \$HOME/.claude/hooks/z.py"
expect_pass "options before the script file (bash -e, python3 -I) still count as interpreter + file" "$r" "skip  [Stop] interpreter: bash -e" "skip  [Stop] interpreter: python3 -I"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}\$HOME/.claude/hooks/gone.sh"
expect_fail "a registered path missing from the index fails and is named as missing" "$r" "hooks/gone.sh" "missing from the git index"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}if [ -f \"\$HOME/.orca/h.sh\" ]; then /bin/sh \"\$HOME/.orca/h.sh\"; fi"
expect_pass "a non-path command beside one valid 100755 script passes and is listed as skipped" "$r" "skip  [Stop] other command: if [ -f" "skipped commands 1"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}@nocmd"
expect_pass "an entry with no command field is listed as skipped (no command), never a crash" "$r" "skip  [Stop] no command" "result: PASS"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
add_script "$r" x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}bash -c \"\$HOME/.claude/x.sh\""
expect_fail "bash -c \"\$HOME/.claude/x.sh\" fails with its own unread-path message" "$r" "unread .claude/ path" "bash -c"
lacks "...and not with the zero-scripts message" "found no registered hook scripts"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}bash -lc \"\$HOME/.claude/x.sh\""
expect_fail "a combined short flag containing c (-lc) is treated as -c" "$r" "unread .claude/ path" "bash -lc"

new_repo; r="$REPO"
add_script "$r" hooks/a.sh 644
put_settings "$r" "Stop${T}VAR=1 \$HOME/.claude/hooks/a.sh"
expect_fail "a VAR=1 assignment prefix is dropped and the script is checked" "$r" "hooks/a.sh" "100644"

new_repo; r="$REPO"
add_script "$r" hooks/a.sh 644
add_script "$r" hooks/b.sh 644
add_script "$r" hooks/c.sh 644
put_settings "$r" "Stop${T}VAR=1 \$HOME/.claude/hooks/a.sh" "Stop${T}~/.claude/hooks/b.sh" "Stop${T}\${HOME}/.claude/hooks/c.sh"
expect_fail "VAR=1, ~/.claude/ and \${HOME}/.claude/ forms are all checked" "$r" "hooks/a.sh" "hooks/b.sh" "hooks/c.sh"

new_repo; r="$REPO"
add_script "$r" hooks/a.sh 755
add_script "$r" hooks/b.sh 755
add_script "$r" hooks/c.sh 755
put_settings "$r" "Stop${T}VAR=1 \$HOME/.claude/hooks/a.sh" "Stop${T}~/.claude/hooks/b.sh" "Stop${T}\${HOME}/.claude/hooks/c.sh"
expect_pass "the same three spellings at 100755 pass with three distinct scripts" "$r" "checked scripts (distinct) 3"

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 644
put_settings "$r" "PreToolUse${T}\$HOME/.claude/hooks/x.sh" "Stop${T}\$HOME/.claude/hooks/x.sh"
expect_fail "one script on two events is reported once, naming both events" "$r" "hooks/x.sh" "PreToolUse, Stop"
n_fail_lines="$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^FAIL ')"
[ "$n_fail_lines" -eq 1 ] && say_ok "...as exactly one FAIL line" || say_bad "...as exactly one FAIL line" "got $n_fail_lines"$'\n'"$OUT"

new_repo; r="$REPO"
printf '{ "hooks": ' > "$r/settings.json"; git -C "$r" add -- settings.json
expect_fail "settings.json in the index that is not valid JSON fails and says so" "$r" "not valid JSON"

new_repo; r="$REPO"
expect_fail "settings.json absent from the index fails and says so" "$r" "missing from the git index"

new_repo; r="$REPO"
add_script "$r" hooks/x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/x.sh"
git -C "$r" reset -q -- settings.json
expect_fail "settings.json only in the working tree (not staged) fails: the index is what is read" "$r" "missing from the git index"

new_repo; r="$REPO"
put_settings "$r" "Stop${T}echo hello"
expect_fail "zero checked scripts fails: the parser is broken, not the repo clean" "$r" "found no registered hook scripts"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
add_script "$r" hooks/x.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}exec \"\$HOME/.claude/hooks/x.sh\""
expect_fail "a skipped command containing .claude/ fails, naming it as an unread path" "$r" "unread .claude/ path" "exec"

new_repo; r="$REPO"
add_script "$r" hooks/ok.sh 755
put_settings "$r" "Stop${T}\$HOME/.claude/hooks/ok.sh" "Stop${T}\$HOME/.claude/hooks/q.sh \"unbalanced"
expect_fail "a command that cannot be split (unbalanced quotes) fails" "$r" "cannot split the command"

new_repo; r="$REPO"
add_script "$r" hooks/sl.sh 644
put_settings "$r" "statusLine${T}\$HOME/.claude/hooks/sl.sh"
expect_fail "a direct-path statusLine is checked too" "$r" "hooks/sl.sh" "statusLine" "100644"

new_repo; r="$REPO"
add_script "$r" hooks/n.sh 644
put_settings "$r" "BrandNewEventName${T}\$HOME/.claude/hooks/n.sh"
expect_fail "an event key nobody listed in advance is covered (no hard-coded event names)" "$r" "hooks/n.sh" "BrandNewEventName"

mkdir -p "$TMP/not-a-repo"
expect_fail "a target that is not a git repository fails" "$TMP/not-a-repo" "not a git repository"

# ------------------------------------------------------------------ the real repo
printf '\n== the real repo (the repository containing this suite) ==\n'
REAL_ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REAL_ROOT" ]; then
  say_bad "real repo: locate the repository that contains this suite" "git -C $HERE rev-parse --show-toplevel failed"
else
  run_check "$REAL_ROOT"
  printf '%s\n' "$OUT"
  [ "$RC" -eq 0 ] && say_ok "every registered hook script in $REAL_ROOT is stored 100755" \
    || say_bad "every registered hook script in $REAL_ROOT is stored 100755" "see the FAIL lines above"
fi

printf '\nregistered-hooks-executable: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
