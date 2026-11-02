#!/usr/bin/env python3
"""Cross-check the two independent attributions of the layer-2 mktemp lines against the log.

    python3 docs/features/evidence/worktree-location-guard/verify-fixture-fingerprint.py

Two agents attributed the same 1066 lines by deliberately different methods and never read
each other's work. They converged on the same fixture fingerprint, stated in different units:

  the source-side reading, from `hooks/git-guard.test.sh:91`, described the population of
  `repo.XXXXXX` directories as 23 with one lock, 46 with two, 69 with three, 46 with four;

  the timing-side reading, from burst structure alone, described a single suite run as
  producing exactly 8 variant directories with lock counts {4,4,3,3,3,2,2,1}, and said that
  signature recurs identically 23 times.

Those are the same claim if and only if the second, multiplied by 23 runs, reproduces the
first. This script checks that against the log rather than against either report, so
agreement between the two agents cannot be the thing being measured. Two readings that agree
can still be one error repeated; the log is the third party.
"""

import collections
import re
import sys
from pathlib import Path

TSV = Path(__file__).with_name("layer2-would-deny.tsv")
VARIANT = re.compile(r"/(repo\.[A-Za-z0-9]{6})/\.git/HEAD\.lock$")

# What the timing side says one run looks like.
RUN_SIGNATURE = sorted([4, 4, 3, 3, 3, 2, 2, 1], reverse=True)
# What the source side says the whole population looks like: lock count -> directories.
SOURCE_POPULATION = {1: 23, 2: 46, 3: 69, 4: 46}


def main() -> int:
    if not TSV.exists():
        print("missing evidence file: " + str(TSV), file=sys.stderr)
        return 2

    per_dir: collections.Counter = collections.Counter()
    for line in TSV.open(encoding="utf-8"):
        target = line.rstrip("\n").split("\t")[-1]
        match = VARIANT.search(target)
        if match:
            per_dir[target] += 1

    by_lockcount = collections.Counter(per_dir.values())
    total_dirs = len(per_dir)
    total_lines = sum(per_dir.values())

    print("MEASURED FROM THE LOG")
    print("  distinct repo.XXXXXX directories : " + str(total_dirs))
    print("  lines across them                : " + str(total_lines))
    print("  directories by lock count        : "
          + str(dict(sorted(by_lockcount.items()))))

    runs = total_dirs / len(RUN_SIGNATURE) if RUN_SIGNATURE else 0
    print("")
    print("TIMING-SIDE CLAIM: 8 variant dirs per run, locks " + str(RUN_SIGNATURE))
    print("  implied run count (dirs / 8)     : " + str(runs))
    print("  implied lines (runs * " + str(sum(RUN_SIGNATURE)) + ")"
          + " " * 10 + ": " + str(int(runs * sum(RUN_SIGNATURE)) if runs == int(runs) else "n/a"))

    print("")
    print("SOURCE-SIDE CLAIM: " + str(SOURCE_POPULATION))
    print("  implied dirs                     : " + str(sum(SOURCE_POPULATION.values())))
    print("  implied lines                    : "
          + str(sum(k * v for k, v in SOURCE_POPULATION.items())))

    print("")
    checks = {
        "directory count matches source side":
            total_dirs == sum(SOURCE_POPULATION.values()),
        "line count matches source side":
            total_lines == sum(k * v for k, v in SOURCE_POPULATION.items()),
        "lock-count distribution matches source side":
            dict(by_lockcount) == SOURCE_POPULATION,
        "directory count is a whole number of 8-dir runs":
            total_dirs % len(RUN_SIGNATURE) == 0,
        "per-run signature scales to the measured distribution":
            all(by_lockcount.get(lock, 0)
                == RUN_SIGNATURE.count(lock) * (total_dirs // len(RUN_SIGNATURE))
                for lock in set(RUN_SIGNATURE)),
    }
    for label, ok in checks.items():
        print(("  PASS  " if ok else "  FAIL  ") + label)

    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
