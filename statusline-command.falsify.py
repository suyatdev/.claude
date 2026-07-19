#!/usr/bin/env python3
"""Falsification harness for statusline-command.test.sh.

A suite that passes proves nothing on its own -- it might be asserting something
that cannot fail. This runs the CURRENT test suite against every historical
version of statusline-command.sh and checks each one fails exactly the
assertions covering the defect it still carries.

Expected, and asserted below:

    f0902ed   9/20   printf '%b'; both injection routes open, plus $PWD
    925c310  10/20   route 1 closed; route 2 and $PWD open
    29d6131  15/20   routes 1-2 closed; $PWD fallback still unstripped
    4d63b09  20/20   $PWD ordering fixed; empty-cwd handling cosmetic only
    e882659  19/20   regressed: a SECOND unstripped fallback added below the strip

These are the single source of truth alongside EXPECTED below; if the two ever
disagree, EXPECTED is what runs.

Run: python3 statusline-command.falsify.py

WHY THIS IS PYTHON AND NOT SHELL: the rtk proxy rewrites git commands issued
from the agent's Bash tool, and for `git show <sha>:<path>` it returns the
commit object rather than the file blob. That silently produced an identical
result for every version -- the harness appeared to work while testing the same
non-script text four times. Invoking git from Python avoids the rewrite, and
each blob is verified to start with '#!' before it is trusted.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent
SCRIPT_NAME = "statusline-command.sh"
SUITE_NAME = "statusline-command.test.sh"

# sha -> (expected passes, what that version still gets wrong)
# Each count is derived from what that version does, not copied from what it
# printed -- fitting these to observed output would make the harness certify
# whatever it happens to see.
EXPECTED = {
    # No stripping at all, so an all-control cwd never empties and never reaches
    # the fallthrough: that one assertion passes here for the right reason.
    "f0902ed": (9, "original: printf '%b', no stripping"),
    "925c310": (10, "route-1 fix only: printf '%s', no stripping"),
    # strip-then-fallback: an all-control cwd empties, then takes a raw $PWD.
    "29d6131": (15, "route-2 fix, but $PWD fallback unstripped"),
    # fallback-then-strip: an all-control cwd empties and STAYS empty, so there
    # is no leak. Its flaw is cosmetic only -- `git -C ""` silently resolves to
    # the process directory -- which is why it scores full marks here.
    "4d63b09": (20, "$PWD ordering fixed; empty-cwd handling cosmetic only"),
    # Added a second fallback below the strip, reintroducing the raw $PWD leak
    # that 4d63b09 had closed.
    "e882659": (19, "regressed: second unstripped fallback below the strip"),
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
            "If this ran through a git proxy, it is a commit object, not a blob."
        )
    return blob


def run_suite(work: Path) -> tuple[int, int, list[str]]:
    proc = subprocess.run(
        ["bash", str(work / SUITE_NAME)], capture_output=True
    )
    out = proc.stdout.decode(errors="replace")
    m = re.search(r"(\d+)/(\d+) passed", out)
    if not m:
        raise SystemExit(f"suite produced no tally:\n{out}\n{proc.stderr.decode()}")
    fails = [
        ln.split("(")[0].replace("FAIL — ", "").strip()
        for ln in out.splitlines()
        if ln.startswith("FAIL")
    ]
    return int(m.group(1)), int(m.group(2)), fails


def main() -> int:
    suite = (REPO / SUITE_NAME).read_bytes()
    ok = True

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / SUITE_NAME).write_bytes(suite)

        # Sanity floor: the working-tree script must pass everything. If it does
        # not, the historical comparisons below mean nothing.
        (work / SCRIPT_NAME).write_bytes((REPO / SCRIPT_NAME).read_bytes())
        passed, total, fails = run_suite(work)
        print(f"{'working tree':12} {passed}/{total}")
        if passed != total:
            ok = False
            for f in fails:
                print(f"{'':14} - {f[:70]}")

        for sha, (want, label) in EXPECTED.items():
            (work / SCRIPT_NAME).write_bytes(blob_at(sha))
            passed, total, fails = run_suite(work)
            verdict = "ok" if passed == want else f"MISMATCH (want {want})"
            print(f"{sha:12} {passed}/{total}  {verdict}  {label}")
            if passed != want:
                ok = False
            for f in fails:
                print(f"{'':14} - {f[:70]}")

    print()
    print("falsification intact" if ok else "FALSIFICATION BROKEN")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
