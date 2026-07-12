#!/usr/bin/env bash
#
# require-project-standards.sh — make the new-project standards gate real.
#
# The `setting-up-a-new-project` skill defines a blocking gate: before a repo gets
# source code, an opt-in register is run and the answers are written to
# `.claude/project-standards.md`. As written, that gate is an instruction — and an
# instruction is only a suggestion. A session can be talked out of it ("let's just
# get something working first"), or can simply forget it after a compaction. The
# gate then quietly does not happen, and the project accretes code with no agreed
# standards, which is the exact failure the skill exists to prevent.
#
# This hook is the enforcement half. The skill asks the questions; this makes sure
# they actually get asked. If project source code is about to be written into a git
# repo that has no `.claude/project-standards.md`, the write is blocked.
#
# Deliberately does NOT block:
#   - writes under `.claude/`   — otherwise the register could never be created
#   - docs / markdown / plain text — writing a README before setup is harmless
#   - anything outside a git repo  — scratch files are not a project
#
# Usage: require-project-standards.sh <target-file-path>
#        ... or as a Claude Code PreToolUse hook (reads file_path from stdin JSON).
# Exit:  0 = allowed (silent).  2 = blocked, run the skill first.

set -u

STANDARDS_REL=".claude/project-standards.md"

target="${1:-}"
if [ -z "$target" ] && [ ! -t 0 ]; then
  target=$(sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

# Nothing to judge — do not block on a payload we could not parse.
[ -n "$target" ] || exit 0

case "$target" in
  /*) ;;
  *) target="$PWD/$target" ;;
esac

base=$(basename -- "$target")

# The target file — and often several of its parent dirs — does not exist yet.
# Walk up to the nearest existing ancestor, remembering the not-yet-created tail
# so the full repo-relative path can be reconstructed. Losing that tail would
# corrupt the exemption checks below.
probe=$(dirname -- "$target")
tail=""
while [ ! -d "$probe" ] && [ "$probe" != "/" ] && [ "$probe" != "." ]; do
  tail="$(basename -- "$probe")${tail:+/$tail}"
  probe=$(dirname -- "$probe")
done
[ -d "$probe" ] || exit 0

repo_root=$(cd "$probe" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || repo_root=""

# Not a git repo → not a project → not our business.
[ -n "$repo_root" ] || exit 0

# `git rev-parse --show-toplevel` reports a PHYSICAL path, so the side we compare
# it against must be physical too (`pwd -P`). On macOS /tmp is a symlink to
# /private/tmp; using the logical pwd makes the prefix strip below fail silently,
# which would mangle rel_path and defeat the .claude/ exemption.
phys=$(cd "$probe" 2>/dev/null && pwd -P) || exit 0
full_dir="$phys${tail:+/$tail}"
rel="${full_dir#"$repo_root"}"
rel="${rel#/}"
rel_path="${rel:+$rel/}$base"

# Exemption: the register itself and everything else under .claude/.
case "$rel_path" in
  .claude/*) exit 0 ;;
esac

# Exemption: docs. Writing prose before standards exist is not the failure mode.
case "$base" in
  *.md|*.markdown|*.mdx|*.rst|*.txt|*.adoc|LICENSE|LICENSE.*|NOTICE) exit 0 ;;
esac

# The gate itself.
if [ -f "$repo_root/$STANDARDS_REL" ]; then
  exit 0
fi

printf 'require-project-standards: blocked write to %s\n' "$rel_path" >&2
printf '\n' >&2
printf 'This repo has no %s.\n' "$STANDARDS_REL" >&2
printf 'Repo root: %s\n' "$repo_root" >&2
printf '\n' >&2
printf 'Run the `setting-up-a-new-project` skill first. It runs the opt-in register\n' >&2
printf '(language, test runner, lint, CI, review gates) and writes the answers to\n' >&2
printf '%s. Source code is gated until that exists.\n' "$STANDARDS_REL" >&2
exit 2
