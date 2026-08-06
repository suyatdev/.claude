#!/usr/bin/env bash
#
# feature-sync-guard.sh — feature-file pair sync guard (Tier 1, blocking).
#
# Decision 6 of docs/features/memory-system-split.md lets a feature file split into
# `<name>.md` (frontmatter + checklist) and `<name>.spec.md` (the prose half). That
# departs from one-canonical-file discipline, and the whole trade was accepted on the
# strength of this hook firing: two documents describing one feature are only safe
# while their task lists cannot silently diverge. A dormant Tier-1 hook is
# indistinguishable from a compliant one — four hooks in this repo pass their tests
# while unregistered, which is why the sibling test asserts its own registration.
#
# Blocks a `git commit` that would record a pair whose task lists differ. Ticking a
# box, appending a completion note, and editing spec prose are all free: identity is
# the item's leading text up to the first em dash (lib/feature_tasks.py).
#
# THE MISSING-PARTNER CASE IS AN ALLOW, and it is the sharpest edge in the contract.
# Decision 7 makes single-file features permanent, so "no <name>.spec.md" means this
# feature was never a pair — not that a migration is unfinished. Read the other way,
# the guard would block every commit touching the eight unmigrated feature files,
# including the spec that defines this hook. The rule is pair-CONDITIONAL: it engages
# only once both halves exist, and until then it is deliberately silent. The stated
# cost is that deleting a spec half outright converts a pair back into a legal
# single-file feature and passes — accepted, because the alternative is a registry of
# which features are pairs, which is more state to drift than the drift it prevents.
#
# TWO FAIL DIRECTIONS IN ONE HOOK, deliberately, so do not align them in a refactor:
#
#   * INFRASTRUCTURE ABSENCE FAILS OPEN — no python, no helper, no git repo, an
#     unparseable payload. Same as doc-guard.sh, whose shape this follows: a
#     documentation-consistency guard is not worth blocking every commit in the repo
#     when an interpreter moves.
#   * A PARSE FAILURE INSIDE A REAL PAIR FAILS CLOSED. Both halves exist and one is
#     malformed: that is a broken file, not a shape choice, and reading it as "no
#     tasks" would let a divergence through as an empty-set match.
#
# Bypass: `FEATURE_SYNC_EXEMPT=<reason> git commit ...`. Printed to stderr and nothing
# else, matching judge-guard.sh:230 and merge-guard.sh:93 — there is no ~/.claude/logs,
# so a bypass is visible in the transcript and vanishes with it. Making bypasses
# durable is a change to all three hooks at once and is out of scope here.
#
# ACCEPTED LIMIT, stated rather than discovered: the halves are read from the INDEX
# (or, for `commit -a`, the working tree), not from a per-pathspec projection of what
# `git commit -- <path>` would record. A pathspec-restricted commit whose partner half
# has an unrelated staged change is therefore judged against the index. The direction
# is toward blocking, never toward a silent allow, and modelling git's pathspec
# semantics here would duplicate the parser ADR 0014 exists to avoid.
#
# Regexes live in variables, not inline in [[ ]] — a bare ( or ; in an inline regex
# makes bash's parser die and a dead script exits non-zero. Same trap as git-guard.sh.
#
# Exit 0 = allow / silent. Exit 2 = blocked, reason on stderr.

set -u

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSIFIER="$HOOK_DIR/lib/classify-git-command.py"
COMPARER="$HOOK_DIR/lib/feature_tasks.py"

FEATURE_DIR="docs/features"

payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi
[ -n "$payload" ] || exit 0

py=$(command -v python3 || command -v python) || py=""
# Fail OPEN: without python we cannot inspect the payload at all.
[ -n "$py" ] || exit 0
[ -r "$CLASSIFIER" ] && [ -r "$COMPARER" ] || exit 0

event=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
sys.stdout.write(p.get("hook_event_name") or "")
' 2>/dev/null)
[ "$event" = "PreToolUse" ] || exit 0

command_line=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
ti = p.get("tool_input")
if isinstance(ti, dict):
    v = ti.get("command")
    if isinstance(v, str):
        sys.stdout.write(v)
' 2>/dev/null)
[ -n "$command_line" ] || exit 0

# Whether this really runs `git commit` is decided by lib/classify-git-command.py,
# which lexes the command into shell segments (ADR 0015) so a chained
# `git add -- x && git commit -m y` — the shape this repo uses constantly — is
# evaluated per segment instead of by a regex anchored to the start of the string.
facts=$(printf '%s' "$command_line" | "$py" "$CLASSIFIER" 2>/dev/null) || exit 0

has_fact() {
  local f
  for f in $facts; do
    [ "$f" = "$1" ] && return 0
  done
  return 1
}

has_fact COMMIT || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Escape hatch. Read from the assignments of the segment that runs `git commit`, via
# the same lexer, so an assignment belonging to some other segment cannot excuse this
# commit. No apostrophes below: this python lives inside a single-quoted shell string,
# and one apostrophe in a comment terminates it and breaks the whole hook (the trap
# recorded against classify-git-command.py in CODING_MEMORY.md).
export FSG_HOOK_DIR="$HOOK_DIR"
exempt_reason=$(printf '%s' "$command_line" | "$py" -c '
import os, sys
sys.path.insert(0, os.path.join(os.environ["FSG_HOOK_DIR"], "lib"))
try:
    from shell_segments import segments
except ImportError:
    sys.exit(0)
for assigns, argv in segments(sys.stdin.read()):
    if len(argv) >= 2 and argv[0] == "git" and argv[1] == "commit":
        value = assigns.get("FEATURE_SYNC_EXEMPT", "")
        if value:
            sys.stdout.write(value.replace("\n", " "))
            break
' 2>/dev/null)

if [ -n "$exempt_reason" ]; then
  printf 'feature-sync-guard: exempted (FEATURE_SYNC_EXEMPT=%s); allowing the commit.\n' \
    "$exempt_reason" >&2
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$repo_root" || exit 0

# `commit -a`/`--all`/`-am` stages tracked edits AT COMMIT TIME — they are not in the
# index yet when this PreToolUse fires — so the tree to judge is the working tree.
# Otherwise the index IS what the commit records. COMMIT_ALL is set only when that
# flag belongs to the commit's own segment.
use_worktree=0
if has_fact COMMIT_ALL; then
  use_worktree=1
  changed=$(git diff HEAD --name-only 2>/dev/null)
else
  changed=$(git diff --cached --name-only 2>/dev/null)
fi
[ -n "$changed" ] || exit 0

# Feature names touched by this commit, deduplicated. A path is in scope only when it
# sits directly under docs/features/ — a nested path is some other document.
names=$(printf '%s\n' "$changed" | "$py" -c '
import os, sys
prefix = sys.argv[1] + "/"
seen = []
for line in sys.stdin.read().splitlines():
    if not line.startswith(prefix):
        continue
    rest = line[len(prefix):]
    if "/" in rest:
        continue
    if rest.endswith(".spec.md"):
        name = rest[: -len(".spec.md")]
    elif rest.endswith(".md"):
        name = rest[: -len(".md")]
    else:
        continue
    if name and name not in seen:
        seen.append(name)
sys.stdout.write("\n".join(seen))
' "$FEATURE_DIR" 2>/dev/null)
[ -n "$names" ] || exit 0

work="$(mktemp -d)" || exit 0
trap 'rm -rf "$work"' EXIT

# Materialize one half as it will exist AFTER the commit. Returns 1 when that half is
# absent, which is the missing-partner allow — never an error.
read_half() { # $1 = repo-relative path, $2 = destination
  if [ "$use_worktree" -eq 1 ]; then
    [ -f "$1" ] || return 1
    cat -- "$1" > "$2" 2>/dev/null || return 1
  else
    git show ":$1" > "$2" 2>/dev/null || return 1
  fi
  return 0
}

while IFS= read -r name; do
  [ -n "$name" ] || continue
  checklist="$FEATURE_DIR/$name.md"
  spec="$FEATURE_DIR/$name.spec.md"

  read_half "$checklist" "$work/checklist.md" || continue
  read_half "$spec" "$work/spec.md" || continue

  message=$("$py" "$COMPARER" "$work/checklist.md" "$work/spec.md" "$name" 2>/dev/null)
  status=$?
  [ "$status" -eq 0 ] && continue
  # An unexpected status means the comparer itself failed to run — fail OPEN, the
  # infrastructure direction, not the parse direction.
  [ "$status" -eq 3 ] || [ "$status" -eq 4 ] || continue

  {
    if [ "$status" -eq 4 ]; then
      printf 'feature-sync-guard: %s could not be parsed, and both halves of the pair exist.\n\n' "$name"
      printf '%s\n\n' "$message"
      printf 'Both halves exist, so this is a malformed file rather than a single-file feature.\n'
      printf 'Fix the checklist syntax (a task line is "- [ ] <id> — <text>") and re-commit.\n'
    else
      printf 'feature-sync-guard: this commit would record a feature pair whose task lists disagree.\n\n'
      printf '%s\n\n' "$message"
      printf 'Decision 6 of docs/features/memory-system-split.md allows the pair shape only while the\n'
      printf 'task lists match. Add the missing task to the other half (ticking a box and appending a\n'
      printf 'completion note need no matching edit), then re-commit.\n'
    fi
    printf 'To bypass a genuinely intentional divergence: FEATURE_SYNC_EXEMPT=<reason> git commit ...\n'
  } >&2
  exit 2
done <<< "$names"

exit 0
