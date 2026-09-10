#!/usr/bin/env bash
# dispatch-pane-agent.test.sh — runs the six concern suites and reports the total.
# Run: bash panes/dispatch-pane-agent.test.sh
#
# Why this file still exists at this name, holding no assertions of its own:
# the verification-marker gate pairs X.sh with X.test.sh and nothing else. The
# six concern suites are named X.<concern>.test.sh, which derives the subject
# X.<concern>.sh — a file that does not exist — so each of them writes no
# marker, and `panes/dispatch-pane-agent.sh` would pair with nothing and never
# be gated at all. Measured against hooks/lib/decide-commit-gate.py _form_pairs:
# with this name present, staging the dispatcher yields one pair; with it
# absent, it yields none. This runner restores both the pair and the receipt,
# and the receipt stays honest because it is written only when all six pass.
set -u
# shellcheck source=/dev/null
. "$(dirname "$0")/test-lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"

# Named explicitly rather than globbed: a glob cannot tell "this suite was
# deleted" from "this suite never existed", and a shrinking glob still reports
# green. Adding a concern file means adding it here.
SUITES="dispatch policy routing cleanup scratch subcommands"

# The mirror of that: a concern file added to panes/ but never added to SUITES
# would silently never run. The named list stays authoritative; this only
# reports the drift. Emits a label solely when it finds some.
for f in "$HERE"/dispatch-pane-agent.*.test.sh; do
  [ -e "$f" ] || continue
  base="${f##*/}"
  concern="${base#dispatch-pane-agent.}"
  concern="${concern%.test.sh}"
  case " $SUITES " in
    *" $concern "*) ;;
    *) bad "concern suite is listed in SUITES: $concern" "$base exists but SUITES does not name it" ;;
  esac
done

for suite in $SUITES; do
  f="$HERE/dispatch-pane-agent.$suite.test.sh"
  if [ ! -f "$f" ]; then
    bad "concern suite present: $suite" "no such file: $f"
    continue
  fi

  out="$TMP/$suite.out"
  err="$TMP/$suite.err"
  bash "$f" > "$out" 2> "$err"
  rc=$?

  # Re-emit the child's assertion lines verbatim so this runner's own stdout is
  # the full RUN-SET, and count them here rather than trusting the child's
  # summary line. The child's own summary line is deliberately dropped from
  # stdout — but it is read back below, where it is the completion sentinel.
  s_ok=0
  s_fail=0
  while IFS= read -r line; do
    case "$line" in
      "ok   — "*) printf '%s\n' "$line"; pass=$((pass + 1)); s_ok=$((s_ok + 1)) ;;
      "FAIL — "*) printf '%s\n' "$line"; fail=$((fail + 1)); s_fail=$((s_fail + 1)) ;;
    esac
  done < "$out"

  # A non-zero exit catches the CRASH shapes. It does not catch the quiet one:
  # a child that ends normally before reaching tl_finish — an early `exit 0`, or
  # a truncated file — returns 0 and leaves its partial green assertions on
  # stdout, which is indistinguishable from a finished suite. Measured: both
  # shapes reported "130 passed, 0 failed" and would have written a marker for a
  # run that lost 9 assertions. tl_finish is the child's last statement, so its
  # summary line is present if and only if the child reached the end; requiring
  # it, and reconciling its numbers against the ones counted above, is what
  # makes "all six finished" a checked fact rather than an assumption.
  summary=$(grep -E '^[0-9]+ passed, [0-9]+ failed$' "$out" | tail -n 1)
  if [ -z "$summary" ]; then
    bad "concern suite ran to completion: $suite" \
      "no summary line -- it stopped before tl_finish (rc=$rc)"
  else
    c_ok="${summary%% passed,*}"
    c_fail="${summary##*, }"
    c_fail="${c_fail%% failed}"
    if [ "$c_ok" != "$s_ok" ] || [ "$c_fail" != "$s_fail" ]; then
      bad "concern suite counts reconcile: $suite" \
        "child reported $c_ok/$c_fail, runner counted $s_ok/$s_fail"
    fi
  fi

  if [ "$rc" -ne 0 ]; then
    bad "concern suite exited 0: $suite" "rc=$rc; stderr: $(tr '\n' ' ' < "$err")"
  fi

  # $TMP is deleted on EXIT, so a failing child's stderr would be unreachable by
  # the time anyone reads the summary. Surface it here, while it still exists.
  if [ "$rc" -ne 0 ] || [ "$s_fail" -ne 0 ]; then
    printf -- '--- %s stderr ---\n' "$suite" >&2
    cat "$err" >&2
  fi

  printf 'ran %-12s %3s ok  %3s fail  (exit %s)\n' "$suite" "$s_ok" "$s_fail" "$rc" >&2
done

tl_finish
