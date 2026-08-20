#!/usr/bin/env python3
"""Falsification harness for statusline-command.test.sh.

A suite that passes proves nothing on its own -- it might be asserting something
that cannot fail. This runs the CURRENT test suite against every historical
version of statusline-command.sh that this repository still has an object for,
and checks each one fails exactly the Group 2 (control-byte injection)
assertions covering the defect it still carries.

Scoped to Group 2 deliberately, not the whole suite: Group 1 (rendering) grows
every time an unrelated feature (token bar, worktree name, wrapping, ...) gets
a new test, and none of those existed yet in these historical versions -- they
would always fail there for reasons that have nothing to do with the injection
defect this harness exists to track. A whole-suite PASS COUNT drifts every time
Group 1 grows, which is why this harness's EXPECTED counts needed recalibrating
three times (20 -> 50 -> 66 -> 68) and eventually went stale. Scoping to Group 2
and asserting WHICH named cases fail, not how many, survives Group 1's growth
structurally: comparisons are pinned to the fixed, purpose-built cases below,
not to the suite's total shape. The test file marks the group's bounds in its
own stdout with @@GROUP2-START@@ / @@GROUP2-END@@ sentinels for exactly this.

Historical versions tracked, and what each still gets wrong in Group 2:

    925c310  original: no stripping at all -- both routes and $PWD open
    29d6131  routes 1-2 closed; $PWD fallback still unstripped
    4d63b09  $PWD ordering fixed; fully closed
    e882659  regressed: a SECOND unstripped fallback added below the strip

`f0902ed` -- the version 925c310 was long labelled a fix against -- does not
exist in this repository, in any reachable or unreachable form, and GitHub has
no record of it either (checked via `gh api repos/.../commits/f0902ed`, 422).
It was never pushed: almost certainly a local commit amended away before this
branch's first push on 2026-07-19, later garbage-collected. Measuring 925c310
directly (see below) shows it is actually the unfixed original -- every
Group 2 case fails except the two that pass "for the right reason" regardless
of stripping (see the two callouts below) -- so 925c310 now carries the
description and role f0902ed used to have, and the old "925c310: route-1 fix
only" label was wrong the moment f0902ed's own row could no longer be checked
against it. This was verified by running the current suite against 925c310's
actual blob, not assumed from the commit message.

Run: python3 statusline-command.falsify.py

WHY THIS IS PYTHON AND NOT SHELL: the rtk proxy rewrites git commands issued
from the agent's Bash tool, and for `git show <sha>:<path>` it returns the
commit object rather than the file blob. That silently produced an identical
result for every version -- the harness appeared to work while testing the same
non-script text four times. Invoking git from Python avoids the rewrite, and
each blob is verified to start with '#!' before it is trusted.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent
SCRIPT_NAME = "statusline-command.sh"
SUITE_NAME = "statusline-command.test.sh"
GROUP2_START = "@@GROUP2-START@@"
GROUP2_END = "@@GROUP2-END@@"

# The 13 Group 2 assertions' fixed description text, as written in
# statusline-command.test.sh today. Matched by substring containment against
# each "FAIL — ..." line, not equality, because two of the bad() calls append
# the live rendered output (hostname/username included) after the fixed part
# for debugging -- containment reads the stable prefix and ignores the rest.
# "literal \x1b in display_name stays inert" is omitted: it passes in every
# version this harness has ever seen (the literal-backslash form was never a
# route printf '%s' could open), so it carries no discriminating signal.
GROUP2_TEMPLATES = (
    "real ESC in display_name is stripped",
    "real newline in current_dir cannot split the line",
    "OSC title-rewrite sequence is stripped",
    "carriage return cannot overwrite the line",
    "ESC stripped with model and context bar both rendering",
    "$PWD fallback leaked control bytes for stdin '{}'",
    "$PWD fallback leaked control bytes for stdin 'garbage'",
    '$PWD fallback leaked control bytes for stdin \'{"cwd":null}\'',
    '$PWD fallback leaked control bytes for stdin \'{"workspace":{}}\'',
    "all-control cwd leaked via the $PWD fallthrough",
    "field content lost, not just its control byte",
    "path truncated at the control byte",
)

# sha -> (expected-failing Group 2 templates, what that version still gets wrong)
# Each set is derived from running the current suite against that version's own
# blob (see module docstring) -- never copied from what a prior run printed,
# which would make the harness certify whatever it happens to see.
EXPECTED = {
    "925c310": (
        frozenset(GROUP2_TEMPLATES) - {"all-control cwd leaked via the $PWD fallthrough"},
        "original: no stripping at all -- both routes and $PWD open. The one "
        "$PWD-family case that does NOT fail here is deliberate: with no "
        "stripping anywhere, an all-control cwd never empties, so it never "
        "reaches the fallthrough this case checks -- passing for the right "
        "reason, not because anything is fixed.",
    ),
    "29d6131": (
        frozenset(
            {
                "$PWD fallback leaked control bytes for stdin '{}'",
                "$PWD fallback leaked control bytes for stdin 'garbage'",
                '$PWD fallback leaked control bytes for stdin \'{"cwd":null}\'',
                '$PWD fallback leaked control bytes for stdin \'{"workspace":{}}\'',
                "all-control cwd leaked via the $PWD fallthrough",
            }
        ),
        "routes 1-2 closed; $PWD fallback still unstripped",
    ),
    "4d63b09": (frozenset(), "$PWD ordering fixed; fully closed"),
    "e882659": (
        frozenset({"all-control cwd leaked via the $PWD fallthrough"}),
        "regressed: a second unstripped fallback added below the strip",
    ),
}


def blob_at(sha: str) -> bytes:
    out = subprocess.run(
        ["git", "-C", str(REPO), "show", f"{sha}:{SCRIPT_NAME}"],
        capture_output=True,
    )
    blob = out.stdout
    if not blob.startswith(b"#!"):
        raise SystemExit(
            f"{sha}: extraction returned a non-script ({blob[:40]!r}). "
            "If this ran through a git proxy, it is a commit object, not a "
            "blob. If stderr says 'invalid object name', the commit does not "
            "exist in this repository at all -- check `gh api "
            f"repos/<owner>/<repo>/commits/{sha}` before assuming it is "
            "recoverable; see the module docstring for f0902ed's case."
        )
    return blob


def run_suite(work: Path) -> tuple[int, int, list[str], frozenset[str]]:
    """Returns (passed, total, unmatched-group2-lines, matched-group2-templates)."""
    proc = subprocess.run(["bash", str(work / SUITE_NAME)], capture_output=True)
    out = proc.stdout.decode(errors="replace")
    lines = out.splitlines()

    m = None
    for ln in lines:
        if ln.endswith(" passed"):
            m = ln
    if m is None:
        raise SystemExit(f"suite produced no tally:\n{out}\n{proc.stderr.decode()}")
    passed_s, total_s = m.split(" ")[0].split("/")
    passed, total = int(passed_s), int(total_s)

    try:
        s = lines.index(GROUP2_START)
        e = lines.index(GROUP2_END)
    except ValueError:
        raise SystemExit(
            f"suite output is missing {GROUP2_START}/{GROUP2_END} -- "
            "statusline-command.test.sh no longer marks Group 2's bounds"
        )
    group2_fails = [ln for ln in lines[s + 1 : e] if ln.startswith("FAIL")]

    matched = frozenset(t for t in GROUP2_TEMPLATES if any(t in ln for ln in group2_fails))
    unmatched = [ln for ln in group2_fails if not any(t in ln for t in GROUP2_TEMPLATES)]
    return passed, total, unmatched, matched


def main() -> int:
    suite = (REPO / SUITE_NAME).read_bytes()
    ok = True

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / SUITE_NAME).write_bytes(suite)

        # Sanity floor: the working-tree script must pass everything. If it does
        # not, the historical comparisons below mean nothing.
        (work / SCRIPT_NAME).write_bytes((REPO / SCRIPT_NAME).read_bytes())
        passed, total, unmatched, _ = run_suite(work)
        print(f"{'working tree':12} {passed}/{total}")
        if passed != total:
            ok = False
        if unmatched:
            ok = False
            print("            unmatched Group 2 failures (GROUP2_TEMPLATES is stale):")
            for u in unmatched:
                print(f"              - {u[:90]}")

        for sha, (want, label) in EXPECTED.items():
            (work / SCRIPT_NAME).write_bytes(blob_at(sha))
            passed, total, unmatched, matched = run_suite(work)
            if unmatched:
                ok = False
                print(f"{sha:12} unmatched Group 2 failures (GROUP2_TEMPLATES is stale):")
                for u in unmatched:
                    print(f"              - {u[:90]}")
                continue
            verdict = "ok" if matched == want else "MISMATCH"
            print(f"{sha:12} {passed}/{total}  {verdict}  {label}")
            if matched != want:
                ok = False
                for missing in sorted(want - matched):
                    print(f"              expected to fail, but passed: {missing}")
                for extra in sorted(matched - want):
                    print(f"              failed unexpectedly: {extra}")

    print()
    print("falsification intact" if ok else "FALSIFICATION BROKEN")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
