"""Check that every hook script registered in settings.json is stored in git as mode 100755.

Spec: docs/features/hook-exec-bit-test.md (R1-R7a), docs/features/hook-exec-bit-pr-guard.md (R1).
A script stored 100644 cannot be started by Claude Code (exit 126), so the hook it implements
silently does nothing.

    python3 -I hooks/lib/registered_hook_modes.py <repo-root> [--rev <commit>]

Without --rev, settings.json and the file modes come from the git INDEX (git show :settings.json,
git ls-files -s), never the working tree, so a local chmod +x cannot hide a 100644 that a fresh
clone would receive. With --rev <commit> both come from that commit (git show <commit>:settings.json,
git ls-tree -r), never mixing in the index; each message that names its source says `commit <c>`
where the index run names the index. Prints ok/skip/FAIL lines, a counts line and a final
`result: PASS|FAIL...`; exit 0 when clean, 1 on any problem. Any other exit (argparse's 2 on bad
usage, a traceback) or a missing final `result:` line means the checker did not run.
Standard library only.
"""

import argparse
import json
import re
import shlex
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
parser = argparse.ArgumentParser(prog="registered_hook_modes.py", allow_abbrev=False)
parser.add_argument("root", help="repository root to check")
parser.add_argument("--rev", metavar="COMMIT",
                    help="read settings.json and file modes from this commit instead of the index")
args = parser.parse_args()
root = args.root
rev = args.rev
INTERPRETERS = ("bash", "sh", "zsh", "python3", "python", "node")
PREFIXES = ("$HOME/.claude/", "${HOME}/.claude/", "~/.claude/")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SHORT_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
EXEC_MODE = "100755"
SHOW = 100
# How the messages name where settings.json and the modes were read from.
SOURCE = "the git index" if rev is None else "commit " + rev
SOURCE_SHORT = "the index" if rev is None else "commit " + rev
# The index message has never named its source ("stored as mode 100644, needs 100755"); the
# commit one must, so it is the only line that gains a suffix.
MODE_IN_COMMIT = "" if rev is None else " in commit " + rev


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

if rev is not None and (rev.startswith("-")
                        or git("rev-parse", "--verify", "--quiet", rev + "^{commit}").returncode != 0):
    die("--rev %s does not resolve to a commit in %s" % (rev, root))

shown = git("show", ":settings.json" if rev is None else rev + ":settings.json")
if shown.returncode != 0:
    die("settings.json is missing from %s of %s" % (SOURCE, root))
try:
    settings = json.loads(shown.stdout.decode("utf-8"))
except (ValueError, UnicodeDecodeError) as err:
    die("settings.json in %s is not valid JSON: %s" % (SOURCE_SHORT, err))
if not isinstance(settings, dict):
    die("settings.json in %s is valid JSON but not an object" % SOURCE_SHORT)

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
# ls-files -s prints "<mode> SP <object> SP <stage> TAB <path>", ls-tree "<mode> SP <type> SP
# <object> TAB <path>"; the mode is the first word and the path follows the tab in both.
listing = (git("ls-files", "-s", "-z") if rev is None else git("ls-tree", "-r", "-z", rev)
           ).stdout.decode("utf-8", "replace")
for item in listing.split("\0"):
    meta, _, path = item.partition("\t")
    if meta and path:
        modes.setdefault(path, meta.split()[0])

for path in sorted(checked):
    where = ", ".join(checked[path])
    mode = modes.get(path)
    if mode is None:
        problems.append("%s is registered on %s but missing from %s" % (path, where, SOURCE))
    elif mode != EXEC_MODE:
        problems.append("%s is registered on %s but stored as mode %s%s, needs %s"
                        % (path, where, mode, MODE_IN_COMMIT, EXEC_MODE))
    else:
        print("ok    %s (%s) registered on: %s" % (path, mode, where))

for problem in problems:
    print("FAIL " + problem)
print("counts: entries read %d | checked scripts (distinct) %d | skipped commands %d"
      % (len(entries), len(checked), len(skipped)))
print("result: " + ("FAIL (%d problems)" % len(problems) if problems else "PASS"))
sys.exit(1 if problems else 0)
