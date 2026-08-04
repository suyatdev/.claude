#!/usr/bin/env bash
# End-to-end falsifier for the redirection fix in lib/shell_segments.py.
#
# Drives the REAL git-guard.sh through the REAL PreToolUse JSON payload, once with main's lexer and
# once with the working tree's, and prints both verdicts side by side. Exists because the evidence
# for this change was originally a markdown table nobody could re-run (observability judge, 2026-08-04).
#
# Every row carries an expectation, so this FAILS when the fix regresses -- it is not a report.
# Read the BASELINE and CONTROL rows first: if those ever differ between lexers, the harness is
# broken and no other row means anything.
#
# Usage: bash hooks/shell-segments-falsifier.sh [base-rev]     (default: main)
set -u
BASE="${1:-main}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v /usr/bin/jq >/dev/null || { echo "falsifier: needs /usr/bin/jq"; exit 1; }

# Two hook trees differing ONLY in shell_segments.py.
for T in old new; do
  mkdir -p "$TMP/$T/lib"
  cp "$HERE/git-guard.sh" "$TMP/$T/"
  cp "$HERE"/lib/*.py "$TMP/$T/lib/"
done
git -C "$REPO_ROOT" show "$BASE:hooks/lib/shell_segments.py" > "$TMP/old/lib/shell_segments.py" || {
  echo "falsifier: cannot read $BASE:hooks/lib/shell_segments.py"; exit 1; }
cp "$HERE/lib/shell_segments.py" "$TMP/new/lib/shell_segments.py"

# Fixture: on main, HEAD exists, NOTHING staged. The empty index is required -- guard 1 consults the
# pathspec only when the index is empty (git-guard.sh:155-157). With files staged every row returns
# the same value for the wrong reason, which is how the first three attempts at this proved nothing.
REPO="$TMP/repo"; mkdir -p "$REPO/docs" "$REPO/src"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email f@f; git -C "$REPO" config user.name f
printf 'doc\n' > "$REPO/docs/foo.md"; printf 'code\n' > "$REPO/src/app.js"; printf 'two\n' > "$REPO/2"
git -C "$REPO" add -A; git -C "$REPO" commit -qm init
printf 'more\n' >> "$REPO/docs/foo.md"          # dirty but UNSTAGED
[ -n "$(git -C "$REPO" diff --cached --name-only)" ] && { echo "falsifier: index not empty"; exit 1; }

verdict() { # $1=tree $2=cmd -> exit code of the guard
  printf '%s' "$2" | /usr/bin/jq -Rc '{hook_event_name:"PreToolUse",tool_input:{command:.}}' \
    | ( cd "$REPO" && bash "$1/git-guard.sh" >/dev/null 2>&1 )
  echo $?
}

fails=0
row() { # $1=label $2=want_old $3=want_new $4=cmd
  local o n status
  o=$(verdict "$TMP/old" "$4"); n=$(verdict "$TMP/new" "$4")
  if [ "$o" = "$2" ] && [ "$n" = "$3" ]; then status="ok  "; else status="FAIL"; fails=$((fails + 1)); fi
  printf '%s  %-42s old=%s new=%s   (want old=%s new=%s)\n' "$status" "$1" "$o" "$n" "$2" "$3"
}

echo "base=$BASE   0=allow 2=block"
echo
row "BASELINE docs commit, no redirect"   0 0 'git commit -m x -- docs/foo.md'
row "CONTROL  source commit to main"      2 2 'git commit -m x -- src/app.js'
echo
row "(a) false denial from 2>&1"          2 0 'git commit -m x -- docs/foo.md 2>&1 | tail -3'
row "(c) leading redirect hid the commit" 0 2 '> out.txt git commit -m x -- src/app.js'
row "(c) mid-command redirect"            0 2 'git >out.txt commit -m x -- src/app.js'
echo
# Process substitution: introduced by revision 1 of this fix, so `old` (which predates the fix
# entirely) already blocks. The point is that `new` must block too -- it briefly did not.
row "proc-subst >( ) must not hide"       2 2 'echo hi > >(git commit -m x -- src/app.js)'
echo
# ACCEPTED FAIL-OPEN, pinned so it cannot change silently. A file literally named `2` immediately
# before a redirect loses its pathspec, flipping git-guard's docs-only exemption deny -> allow.
row "ACCEPTED fail-open: file named '2'"  2 0 'git commit -m x -- docs/foo.md 2 > out'

echo
if [ "$fails" -eq 0 ]; then echo "falsifier: all rows as expected"; else echo "falsifier: $fails row(s) UNEXPECTED"; fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
