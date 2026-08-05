# 0016 — A differential harness must prove its two sides differ, and must name its baseline

- **Status:** accepted
- **Date:** 2026-08-05
- **Context:** `hooks/git-guard.replay.sh`, standalone (does not amend a prior ADR)

## Context

`git-guard.replay.sh` runs a baseline `git-guard.sh` and the branch's own over a 63-command × 6-state
matrix and reports every case where the baseline blocks and the branch allows. Before this change the
baseline was hard-coded to `main` at four sites, with no override parameter. That produced a program
that, on `main` itself or on any branch that never touches the three files it compares, silently
compared a copy of itself against itself: 378 identical, 0 relaxed, exit 0 — the exact shape of a
genuine, hard-won pass. `docs/features/falsifier-base-pin.md` found this defect live while fixing its
sibling harness (`hooks/shell-segments-falsifier.sh`) for the same class of bug.

Measured on this host against `main` @ `c461e4c`: six bases produce five distinct false-pass shapes
— a vacuous baseline (same code, praised as agreement), a degenerate one (unchecked extraction
failures), an unresolved worktree path (candidate exits 127, tallied `same`), a base whose files don't
exist (three empty files "agree" with anything), and a passing run whose printed baseline is the
literal string `main`, which names a different commit every week. `docs/features/replay-harness-base-pin.md`
records the full measurement table and the fix for four of the five; the fifth (a fundamentally more
robust exit-code contract) is explicitly deferred there, not closed here.

## The rule

> A differential harness must prove its two sides differ before reporting agreement, and must state
> its resolved baseline — as a fixed commit id — in its output. Agreement between a program and
> itself, or between two empty files, is not evidence; and a number that does not carry its baseline
> cannot be audited later without archaeology.

This is now the second time this exact class of bug has bitten a harness in this repo — first
`shell-segments-falsifier.sh` (fixed on `docs/features/falsifier-base-pin.md`), now `git-guard.replay.sh`.
Recording it as a rule, rather than leaving it as two independent point fixes, is what makes a third
instance a review-time catch instead of a third rediscovery.

## What this change proves, and what it does not

This change makes the harness refuse to report agreement when its two sides are provably the same
program (same required file set, identical bytes), and makes it fail with a named error — instead of
silently proceeding — when a side's required files cannot be read or when the worktree path cannot be
resolved to a directory containing `hooks/git-guard.sh`. Every successful run now prints its resolved
40-character base SHA in both the header and the summary line, not the rev string.

**It does not make the harness robust to an arbitrary broken candidate.** The `else → same` tally in
the comparison loop still counts any exit code outside `{0, 2}` as agreement — a candidate that crashes
with a segfault or exits 127 for a reason other than the now-fixed unresolved-path case is still
tallied as matching the baseline. Separately, `relaxed` is defined as `base = 2 && candidate = 0`, so a
candidate that blocks *everything* (exits 2 unconditionally, including on commands that don't touch
git) registers zero relaxations by construction — a false pass dressed as hardening. Both limits are
pre-existing in the comparison logic this change does not otherwise modify; they are queued as their
own item, not fixed here, per the user's explicit decision to avoid widening this branch mid-flight —
the same decision this repo made, and violated, on the two branches immediately preceding this one.
The harness's exit code also still carries no signal about *relaxations found*: a run that reports 62
relaxed rows exits 0, identically to a clean run. All three are recorded as open limits, not silently
inherited.

## Provenance of prior figures

Five citation sites across four files quoted a replay-harness figure before this fix existed to name a
base. None of those figures are retracted — each is annotated with the base it was actually measured
against, so a reader is not left to re-derive it:

| file | site | base the figure was measured against |
|---|---|---|
| `docs/features/git-guard-empty-index.md` | `:310-318` | per-row candidates `27c5ac5` / `4be542b` / the fix, vs `main` as it then stood — this measurement predates `BASE_REV`, so no fixed SHA was recorded at the time |
| `docs/features/shell-segments-redirects.md` | `:117-118` | `main` @ `bc7da76`, ~68 minutes before this branch's own merge |
| `docs/features/shell-segments-redirects.md` | `:140` | same measurement as the site above |
| `docs/features/falsifier-base-pin.md` | `:145` | already states its own provenance correctly — the candidate and baseline are both `main` at measurement time, which is exactly the tautology this ADR's rule forbids; no edit needed, and it refers to a live post-merge run, not a figure needing this table |
| this ADR (`:below`) | — | restates `docs/decisions/0015-…:110`'s "378/378 identical" figure; that file is **not edited** — this repo amends by writing a new record (ADR 0009, ADR 0011, ADR 0013), never by touching a prior one |

**Restating ADR 0015's figure:** `docs/decisions/0015-redirections-are-part-of-a-command.md` states
"`git-guard.replay.sh` reports 378/378 identical across its 63-command matrix" as evidence the replay
harness cannot see the redirect-handling defect class it addresses. That figure was measured against
`main` as it stood at the time (2026-08-04, pre-dating `BASE_REV`) — code identical to the candidate
under test, which is precisely the vacuous-baseline shape this ADR's rule now refuses. The conclusion
ADR 0015 drew from it — "evidence of no regression, not evidence the fix works" — holds regardless,
because that conclusion never depended on the baseline being non-vacuous in the first place.

## Consequences

- Every future replay-harness run, passing or refusing, names a real, resolvable base — copying a
  number out of this repo's history no longer requires archaeology to know what it was measured
  against.
- The two comparison-logic limits (the `else → same` tally, and `relaxed`'s one-sided definition) and
  the unconditional `exit 0` remain open, tracked in `docs/features/replay-harness-base-pin.md`'s
  non-goals, not here — this record does not claim to have closed them.
- `hooks/shell-segments-falsifier.sh` is unaffected: it already pins its base to a fixed SHA by
  construction and was the first fix in this class (`docs/features/falsifier-base-pin.md`).
