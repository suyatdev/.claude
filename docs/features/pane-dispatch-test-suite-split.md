---
phase: planning
model_tier: high
branch: TBD
---

# `panes/dispatch-pane-agent.test.sh` is 957 lines, past the 800-line hard maximum

Queued 2026-09-07 out of round 4 of the compliance judge and the final implementation-stage
observability judge on `docs/features/pane-agent-scratch-isolation.md`
(branch `fix/pane-agent-scratch-isolation`, HEAD `81f58d5`).

## What is wrong

`rules/core-conduct.md` Code Style sets **<400 lines preferred, 800 max**. Measured
2026-09-07 with `wc -l`:

| Ref | Lines |
|---|---|
| branch base `3ab2d57` | 771 |
| `fix/pane-agent-scratch-isolation` HEAD `81f58d5` | 957 |

The scratch-isolation card's twenty new assertions (its tasks 2 and 4) carried the file 157
lines past the ceiling. Nothing in that card's Contracts, checklist or first three judge
rounds noticed; the compliance judge raised it in round 4 and it is recorded there as a
knowingly-shipped residual rather than fixed on that branch.

## Why it was not fixed there

Splitting the suite is a mechanical change to the one file that is the unbiased baseline for
every other change on that branch. `rules/core-conduct.md` Testing forbids editing tests and
implementation in the same step, and doing the split in the same breath as the feature the
suite validates is exactly that. Deferring is the cheaper error.

## Open questions — decide before implementing, do not decide here

1. **Split on what axis?** The file covers at least four concerns: the dispatch happy path
   and launcher shape, the pane/tab routing policy (round-robin, overflow, failure streaks,
   cooldowns), `cleanup_stale` retention, and this card's scratch isolation. Concern-per-file
   is the obvious cut; whether routing alone is still over 400 lines is unmeasured.
2. **What carries the shared harness?** The stubs (`detect.sh`, the recording adapter), the
   `ok`/`bad` counters and the test-marker write are set up once at the top. A shared
   `panes/test-lib.sh` sourced by each file is one answer; duplicating the preamble per file
   is another and is worse.
3. **How is the split proved to have lost nothing?** A total that still adds to 139 is not
   proof — a changed count and an unchanged count can both hide a swap. The check is set
   membership over assertion labels before and after, not arithmetic.
4. **Do the `ok`/`bad` label divergences get fixed in the same pass?** 48 of 135 pairs in
   this file spell the two labels differently, which silently defeats matching a failure by
   its pass text (measured on `fix/pane-agent-scratch-isolation`). Probably its own step,
   for the same reason this card exists.

## Not started

No branch, no code. This card is `phase: planning`; the gate transition needs the literal
phrase `gate confirmed`.
