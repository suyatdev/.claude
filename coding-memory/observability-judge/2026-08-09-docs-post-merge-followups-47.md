# Observability verdict — `docs/post-merge-followups-47` (implementation)

- **ts:** 2026-08-09T20:25:31Z
- **repo:** `memsearch-freshness` (worktree of `~/.claude`)
- **branch:** `docs/post-merge-followups-47`
- **head_sha:** `6e35701f5ebd4f751f3b982f4bbd08397124d495`
- **base:** `origin/main` @ `b829eea`
- **diff:** 1 commit, 3 files, +34 / −10 (records only)
- **tests:** `cd ~/.claude/memsearch && uv run pytest -q` → **74 passed, 23 deselected** (0.37s). Run
  by me. Exercises nothing in this diff; the PR says so, and that is accurate, not an evasion.
- **risk:** low · **confidence:** high

---

## What was changed

Three record files were updated after PR #47 merged. Nothing that runs was touched.

1. `coding-memory/pr-tracking.md` — PR #47 flipped from OPEN to MERGED at `b829eea`, plus a
   merge-verification note and the reasoning behind the outcome backfill.
2. `coding-memory/observability-judge/verdicts.jsonl` — the eight verdicts from
   `docs/r9-counterfactual-control` had `outcome` changed from `null` to `"rework"`.
3. `CODING_MEMORY.md` — the session-49 archive entry closed out with the merge result.

## Does it do what was intended?

Mechanically, yes, and every mechanical claim it makes survives independent re-derivation. One
stated **statistic is false**, repeated in all three places it appears.

### Verified independently — all clean

| Claim in the record | My check | Result |
| --- | --- | --- |
| Merge took branch content verbatim | `git diff --stat dfb171b b829eea` | empty ✅ |
| Only 2 deletions vs old `main` | `git diff --numstat 64d8acb b829eea` | 2 deletions, both in `docs/features/memsearch-freshness.md` ✅ |
| Those 2 deletions were intended replacements | `git diff -U3` on that file | `branch: feature/…` → `branch: none  # merged via PR #45…`, and a sentence extended in place. Both replaced, neither dropped ✅ |
| No conflict markers | `git grep -nE '^(<<<<<<<\|>>>>>>>\|=======)$'` on the same pathspec, exit code read directly | rc=1 ✅ |
| …and the probe can actually report a hit | falsifier: same command shape + pathspec, pattern known present | rc=0 ✅ — the probe is not blind |
| Backfill touched only the intended rows | parsed both revisions, per-key comparison | 135 rows before and after; exactly 8 rows differ; `outcome` is the only key that differs; key order preserved; no keys added ✅ |
| `"rework"` is a legal value | `skills/running-the-observability-judge/SKILL.md:45` (`clean`/`rework`/`bug`); file already holds 34 `clean` / 25 `rework` | ✅ consistent with the existing vocabulary |

The `head`-exit-code catch described in the commit message is real discipline and correctly
disclosed. `git grep … | head` reports `head`'s status, so that first probe would have said "clean"
against a file full of markers. Catching, re-running and falsifying it is exactly right.

### The one defect — the `risk=low` count is wrong

The record says all eight verdicts were `risk=low`. **Six were `low`; two were `medium`.**

```
2026-08-09T16:56:23Z  52b09c39  risk=low     conf=medium  outcome=rework
2026-08-09T17:07:04Z  3609faa9  risk=low     conf=high    outcome=rework
2026-08-09T17:20:27Z  3e9ec4b7  risk=low     conf=high    outcome=rework
2026-08-09T17:30:27Z  3592a636  risk=medium  conf=high    outcome=rework   ← not low
2026-08-09T17:43:40Z  77102c41  risk=medium  conf=high    outcome=rework   ← not low
2026-08-09T18:16:53Z  f0cbde56  risk=low     conf=high    outcome=rework
2026-08-09T19:57:10Z  1c89fbe9  risk=low     conf=high    outcome=rework
2026-08-09T20:06:29Z  d0c3da58  risk=low     conf=high    outcome=rework
```

It appears three times:

- `CODING_MEMORY.md:4757` — "Each returned `risk=low`, and each was followed by a fix commit — 8 for 8."
- `coding-memory/pr-tracking.md:880` — "Every one returned `risk=low` and every one was followed by a fix commit."
- commit `6e35701` subject and body — "eight risk=low verdicts all became rework"; "8 for 8 is the
  clearest instance of the gap in the record."

**What it does to the argument.** The direction survives: six `risk=low` verdicts were all reworked,
and that alone makes the point. The magnitude does not. "8 for 8" becomes "6 of 6 low, plus 2 mediums
that were also reworked", and the two mediums cut mildly *against* the strongest phrasing — on those
two rounds the judge did raise the risk field, so it was not inert. The sentence "a low-risk verdict
predicts nothing about whether the content is right" is a general law asserted from n=6 on one
docs-only branch; it is the sentence most likely to be quoted back later, so its denominator ought to
be right.

**On the risk-vs-correctness framing itself.** The framing is sound and worth keeping. `risk` in this
rubric is blast radius, and documentation genuinely cannot break production, so a docs branch pinned
at `low` while needing eight rounds of correction is not a miscalibration. It is over-reached only in
how absolutely it is stated. The stronger, unstated number is right there in the same rows:
**`confidence` was `high` on 7 of 8** verdicts that all required rework. `confidence` is the field
that plausibly *does* claim something about correctness, and it was wrong seven times. That is the
sharper finding, and the record misses it while overstating the weaker one.

**Self-referential note.** This commit's own message says "a check that cannot fail has not passed",
and its self-verification paragraph is thorough about the mechanism (which rows, which keys) and
silent about the statistic. The verification passed while the headline claim went unchecked. That is
the same species the record was written to warn about.

Also worth one line: appending to `CODING_MEMORY.md` nudges that document's chunk count, which is the
self-perturbation mechanism the merged branch flagged as still live. +14 lines is negligible, but the
bookkeeping for a measurement is not outside the measurement.

## Dimensions

| Dimension | Score | Note |
| --- | --- | --- |
| `intent` | pass | Exactly the three intended records; nothing more. |
| `execution` | concern | The data operation is verifiably correct; the prose ships a false statistic, repeated 3×. Test run is real but irrelevant to this diff. |
| `trajectory` | concern | Genuinely strong reasoning on merge verification (the `head` exit-code catch, the falsifier). The same rigour was not applied to the branch's own verdict rows. |
| `regression` | pass | JSONL schema, row count, key order all intact; `rework` is a defined value; `judge-guard.sh` keys on `head_sha`/`stage`, not `outcome`. |
| `context_budget` | pass | +14 lines to an append-only archive and +10 to PR tracking; neither is always-on context. |
| `traceability` | concern | Unusually well documented and every claim is falsifiable from the repo in seconds — which is how the error was found. But the stated explanation overstates its evidence. |
| `success_masking` | concern | Self-verification confirmed the mechanism and never checked the headline number; the green pytest run touches nothing here. |
| `intent_drift` | pass | Three files, all in scope. No drive-by edits, no dependencies, no source touched. |
| `checkpoint` | pass | Single commit on a branch off merged `main`; `git revert 6e35701` is a clean restore point. Nothing destructive. |
| `audit_trail` | pass | Fully attributable, one commit, provenance clear. Not ADR-worthy — it is bookkeeping. |

## Concerns

- "Every one returned `risk=low`" is false — 6 low, 2 medium — repeated in `CODING_MEMORY.md:4757`, `pr-tracking.md:880`, and the commit message
- "8 for 8" overstates the denominator; the real figure is 6 of 6 low plus 2 medium, all reworked
- The two `medium` verdicts mildly undercut "the risk field predicts nothing" — on those rounds it did move
- Unstated and stronger: `confidence: high` on 7 of 8 verdicts that all needed rework
- Self-verification checked which rows changed but never checked the statistic being asserted about them
- Appending to `CODING_MEMORY.md` perturbs the chunk-count instrument the merged branch was measuring

## Scope note

I confined this to the three changed files, as asked, and did not re-review the merged feature doc.
The deep read was warranted only because a load-bearing number was offered for checking — and it did
not hold. There is no second finding; the rest is clean.

My own `risk=low` on this verdict means the change cannot break anything, not that it is correct.
The content has a known error. That distinction is the record's own thesis, which it earns.
