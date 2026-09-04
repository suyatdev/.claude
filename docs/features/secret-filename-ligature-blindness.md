---
phase: planning
model_tier: high
branch: null
---

# `secret-command-guard` misses ligature spellings of secret file names

**Placeholder. Not designed. Do not implement from this file — the first task is to
re-derive the cost, because the one figure that matters disagreed with itself twice.**

Queued 2026-09-03 out of task 8 of `docs/features/secret-filename-case-blindness.md`
(branch `fix/secret-filename-case-blindness`). That card folded file names with
`re.IGNORECASE`, closing 9 of 12 measured same-file bypasses. **Three survive**, and they
survive by construction: a ligature is a *decomposition*, not a case difference, so no
case-folding flag can ever reach it.

## The three, measured

Each opens the **real** file on this volume — proven with decoy files in a scratch
directory, not by reasoning about Unicode:

| Spelling | Codepoints | Real file it opens |
|---|---|---|
| `.bash_proﬁle` | U+FB01 | `.bash_profile` |
| `.baſh_proﬁle` | U+017F, U+FB01 | `.bash_profile` |
| `.zproﬁle` | U+FB01 | `.zprofile` |

They are pinned as **ALLOW** assertions in `hooks/secret-command-guard.test.sh` and carry a
row in the Known-gaps table of `docs/features/secret-command-guard.md`, so the residual is
recorded rather than forgotten.

## Why the obvious fix is not the fix

Normalising the token with NFKD before matching closes **all** of them — and every other
same-file bypass — but it refuses **hundreds** of names that are genuinely different files.

⚠️ **The exact NFKD false-refusal figure is deliberately unpublished.** Two sweeps on the
predecessor card returned 577 and 1,881 against populations that were supposed to be the
same. Neither figure is trustworthy and **neither is to be resurrected**. Run
`hooks/secret-filename-fold.probe.sh` for the current number and treat it as an order of
magnitude until someone explains the disagreement.

So "normalise everything" is the wrong shape. The likely right shape is far narrower: fold
**only the specific ligature codepoints that appear in these seven protected names**, which
on the evidence above is U+FB01 alone. That is a hypothesis, not a decision.

## Task 1 — re-derive the cost, before anything else

Nothing else starts until this is done, and it must be done with the two-oracle structure
the predecessor card established (filesystem truth from decoy files, guard verdict from the
imported patterns; never create, read, or name a real secret-bearing file):

- Re-run `hooks/secret-filename-fold.probe.sh` and record the NFKD column **and the
  population it was computed over**. The two disagreeing figures are the reason this task
  exists — find out which population differed, or say plainly that you could not.
- Add a fifth strategy column: `re.IGNORECASE` plus a **targeted** pre-fold of only the
  ligature codepoints reachable in the eight protected patterns. Report its bypasses and
  its false refusals in the same two columns as the other four.
- Sweep **every letter position and every non-overlapping combination**, as task 3 of the
  predecessor card does. Three separate rounds there shipped a confident table built on a
  population with a hole; the per-name coverage print exists so the fourth hole is visible.
- Only then decide, and only then open a gate.

## Out of scope until task 1 lands

Everything. Including the implementation shape suggested above.

## Pointers

- Predecessor card and all its measurements: `docs/features/secret-filename-case-blindness.md`
- The fold decision and its rejected alternatives:
  `docs/decisions/0042-secret-command-guard-folds-file-names-case-insensitively.md`
- The probe that produced every number: `hooks/secret-filename-fold.probe.sh`
- Guard design and the Known-gaps table: `docs/features/secret-command-guard.md`
