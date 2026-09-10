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
  # summary line. The child's own summary line is deliberately dropped.
  s_ok=0
  s_fail=0
  while IFS= read -r line; do
    case "$line" in
      "ok   — "*) printf '%s\n' "$line"; pass=$((pass + 1)); s_ok=$((s_ok + 1)) ;;
      "FAIL — "*) printf '%s\n' "$line"; fail=$((fail + 1)); s_fail=$((s_fail + 1)) ;;
    esac
  done < "$out"

  # A suite that dies partway leaves its green assertions on stdout and would
  # otherwise be indistinguishable from one that finished. Folding its exit
  # status into `fail` is what stops tl_finish writing a marker for a partial
  # run. It emits a label only when it fails, so a green run stays at 139.
  if [ "$rc" -ne 0 ]; then
    bad "concern suite exited 0: $suite" "rc=$rc; stderr: $(tr '\n' ' ' < "$err")"
  fi

  printf 'ran %-12s %3s ok  %3s fail  (exit %s)\n' "$suite" "$s_ok" "$s_fail" "$rc" >&2
done

tl_finish
