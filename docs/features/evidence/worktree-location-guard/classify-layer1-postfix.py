#!/usr/bin/env python3
"""Bucket the layer-1 post-fix would-deny lines by what the refused command actually contained.

Run from the repository root:

    python3 docs/features/evidence/worktree-location-guard/classify-layer1-postfix.py

This answers one narrow question and no other: of the commands layer 1 turned away in the
post-fix window, how many contained a git subcommand capable of moving HEAD, placing a
worktree, or otherwise doing the thing the guard exists to prevent?

It is deliberately a crude textual test, not the guard's own classifier. That is the point:
it is an INDEPENDENT reading of the same population. A command it buckets as carrying no git
token at all cannot have been a real violation, whatever the guard's reason for refusing it,
so the "no git token" bucket is a lower bound on the false-positive count that does not
depend on trusting the guard's own parse.

It does NOT establish the converse. A command in the "HEAD-moving subcommand" bucket is not
thereby a correct refusal: it may have run inside a linked worktree, which is exactly what
the guard is supposed to allow. Those need the per-line review, not this script.
"""

import collections
import re
import sys
from pathlib import Path

TSV = Path(__file__).with_name("layer1-post-fix-would-deny.tsv")

# Subcommands that move HEAD, place a worktree, or write refs. Matched loosely and
# generously — the bucket is meant to over-collect, so that the "no git at all" bucket
# it leaves behind is conservative.
MOVERS = (
    "commit", "checkout", "switch", "merge", "rebase", "reset", "cherry-pick",
    "revert", "stash", "pull", "bisect", "worktree", "branch", "push", "clone", "init",
)

GIT_TOKEN = re.compile(r"(?:^|[\s;&|(])git(?:$|[\s;&|)])")


def bucket(arm: str, command: str) -> str:
    if arm == "A":
        return "A: a file-write target, not a command"
    if not GIT_TOKEN.search(command):
        return "B2D: no git token anywhere in the command"
    hits = sorted({
        m for m in MOVERS
        if re.search(GIT_TOKEN.pattern + r"[^;&|]{0,120}?" + re.escape(m), command)
    })
    if hits:
        return "B2D: git plus " + ", ".join(hits)
    return "B2D: a git token, but no HEAD-moving subcommand"


def main() -> int:
    if not TSV.exists():
        print("missing evidence file: " + str(TSV), file=sys.stderr)
        return 2

    rows = [line.rstrip("\n").split("\t") for line in TSV.open(encoding="utf-8")]
    counts: collections.Counter = collections.Counter()
    samples: dict[str, list[str]] = collections.defaultdict(list)

    for row in rows:
        arm = row[2] if len(row) > 2 else "?"
        command = row[6] if len(row) > 6 else ""
        key = bucket(arm, command)
        counts[key] += 1
        if len(samples[key]) < 2:
            samples[key].append(command[:160])

    print("lines read: " + str(len(rows)))
    for key, n in counts.most_common():
        print("")
        print(str(n) + "  |  " + key)
        for sample in samples[key]:
            print("      e.g. " + sample)
    return 0


if __name__ == "__main__":
    sys.exit(main())
