#!/usr/bin/env bash
# End-to-end falsifier for the redirection fix in lib/shell_segments.py.
#
# Drives the REAL git-guard.sh through the REAL PreToolUse JSON payload, once with a PRE-FIX lexer
# and once with the working tree's, and prints both verdicts side by side. Exists because the
# evidence for this change was originally a markdown table nobody could re-run (observability judge,
# 2026-08-04).
#
# Every row carries an expectation, so this FAILS when the fix regresses -- it is not a report.
# Read the BASELINE and CONTROL rows first: if those ever differ between lexers, the harness is
# broken and no other row means anything.
#
# Usage: bash hooks/shell-segments-falsifier.sh [base-rev]     (default: the pinned pre-fix commit)
set -u

# A DIFFERENTIAL harness's baseline must be a FIXED COMMIT, never a branch. This defaulted to `main`
# and so self-invalidated the moment the fix it demonstrates was merged there (cc035d2, ~40 minutes
# after the script was written): `old` became `new`, all four mode rows collapsed, and the script
# reported "4 row(s) UNEXPECTED" -- four content failures for what was purely a harness problem, in
# the most alarming possible presentation. A branch that will eventually contain the change under
# test is not a baseline; it is the thing being tested, twice.
#
# bc7da76 is the commit fix/shell-segments-redirects branched from. An unreachable pin (shallow
# clone, rewritten history) is a NAMED error below, not a wrong answer -- that trade is the point.
BASE="${1:-bc7da76}"
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

# Assert the baseline actually PREDATES the fix, before running a single row. Pinning the default is
# not enough on its own: it cures today's symptom and leaves the failure MODE -- a silently invalid
# baseline reported as content failures -- completely intact for the next caller who passes a base by
# hand. Ask the base lexer the defect directly: pre-fix, a LEADING redirect pushes the real command
# out of position 0, so no segment starts with `git`. A base where one does already has the fix.
base_state=$(cd "$TMP/old/lib" && python3 -c '
import sys
sys.path.insert(0, ".")
try:
    from shell_segments import segments
    segs = segments("> out.txt git commit -m x -- foo.sh")
except Exception as exc:
    print("ERR " + type(exc).__name__ + ": " + str(exc))
else:
    print("FIXED" if any(argv and argv[0] == "git" for _, argv in segs) else "PRE-FIX")
' 2>&1)

case "$base_state" in
  PRE-FIX) : ;;   # correct: the baseline still has the defect, so the rows below mean something
  FIXED)
    echo "falsifier: BASELINE IS NOT PRE-FIX — '$BASE' already contains the redirection fix."
    echo "           Every row would compare the fix with itself, so no row was run."
    echo "           This is a HARNESS problem, not a regression in lib/shell_segments.py."
    echo "           Pass a commit from before the fix, e.g.:"
    echo "               bash hooks/shell-segments-falsifier.sh bc7da76"
    exit 1 ;;
  *)
    echo "falsifier: cannot evaluate the baseline lexer read from '$BASE'"
    echo "           ${base_state:-(no output — is python3 on PATH?)}"
    exit 1 ;;
esac

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
# ACCEPTED FAIL-OPEN, pinned so it cannot change silently. ANY trailing bare digit before a redirect
# is dropped -- `git log -n 5 > out` loses the `5` too. This row is the one GUARD-VISIBLE case: the
# dropped token was the pathspec, so git-guard's docs-only exemption flips deny -> allow. ADR 0015.
# The width itself (option values, not just pathspecs) is pinned in shell_segments.test.py.
row "ACCEPTED fail-open: bare digit pathspec"  2 0 'git commit -m x -- docs/foo.md 2 > out'

echo
if [ "$fails" -eq 0 ]; then echo "falsifier: all rows as expected"; else echo "falsifier: $fails row(s) UNEXPECTED"; fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
