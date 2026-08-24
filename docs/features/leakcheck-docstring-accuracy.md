---
phase: implementation
model_tier: xhigh
branch: fix/leakcheck-docstring-accuracy
---

# leakcheck docstring accuracy

Follow-up 1 of 3 left open by `hook-wiring-health-check` when it closed (PR #69, `62f4535`).
Comment-only: no behaviour changes, no regex changes, no test changes.

Card exists for one mechanical reason, not because a docstring fix is feature-scale work
(`managing-session-memory` says explicitly that it is not): `phase-guard` is repo-global, so with
other cards sitting at `phase: planning` any write under `hooks/` is denied on a branch no
`implementation` card claims. Straight to `implementation` — the change was specified and approved
in conversation, so there is no planning cycle to run.

## Problem

`hooks/verify-hook-wiring.leakcheck.py`'s module docstring carries three numbers that went stale
together when the family list grew from seven to thirteen (since `671fdf7`). The file is an audit
record of a security property, so wrong figures in it are worse than no figures.

## Tasks

- [x] Re-measure every claim in the docstring from a clean `main` checkout, at runtime
- [x] Correct the three stale numbers; state the denominator asymmetry the comparison hides
- [x] Confirm the falsifier still goes red, and the live checker still exits 0

## Verification

Measured on `fix/leakcheck-docstring-accuracy` off `origin/main` @ `ab39635`, not carried over
from the closing card:

| claim | docstring said | measured | note |
|---|---|---|---|
| families | Seven | **13** | counted from the printed table, not a regex over the source — a regex over `FAMILIES` matches separator literals inside the lambdas and returns 19 |
| current renderer | `0/14000` | **0 of 52,000** | `13 x 2000 x 2 surfaces`; exit 0 |
| `2fad70f` renderer | `995 leaks` | **9013 leaks** | exit 1 |
| — std base64 | `123/2000` | **123/2000** | reproduces exactly |
| — short b64 | `871/2000` | **871/2000** | reproduces exactly |

The two per-family breakdowns were never wrong; only the totals were. `995` was the correct
seven-family total (`123 + 1 urlsafe + 871`), which is why it looked plausible for so long.

**Denominator asymmetry, now stated in the docstring:** the `2fad70f` run measures 26,000 checks,
not 52,000. That revision predates `render_name` (`git show 2fad70f:hooks/verify-hook-wiring.sh`
greps 0 for it, current `main` greps 2), and the sub-key surface is skipped when the renderer
under test has none. Reporting `9013` beside `0` without that reads as one ratio and is another.

## Non-goals

Behaviour. The renderer, the regexes, the `SEPARATORS` constant and every test are untouched.
