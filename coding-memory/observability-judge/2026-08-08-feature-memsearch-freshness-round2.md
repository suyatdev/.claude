# Observability verdict (re-judge) — `feature/memsearch-freshness` @ `b81ff6f`

- **stage:** implementation (gates the PR)
- **repo:** `.claude` · **base:** `main` @ `b78eae8` · **23 commits**
- **judged:** 2026-08-08T05:53:04Z
- **spec:** `docs/features/memsearch-freshness.md` (single canonical file, 1812 lines)
- **supersedes:** `2026-08-08-feature-memsearch-freshness.md` @ `46c9906` (risk=medium, confidence=high)

---

## What was changed

Since the last verdict, nothing about the *product* changed — no code, no config, no tests. Both new
commits are documentation. What changed is the **record of why the product is the way it is**.

Last pass I said the branch's headline causal claim was backwards: it blamed the wrong culprit for a
retrieval regression. The author did not take that on faith. They rebuilt my counterfactual from
scratch, with a harness guard requiring the no-op variant to reproduce `search()` exactly, confirmed
my result, then **retracted the wrong conclusion in place** — leaving the mistaken reasoning visible
and labelled rather than quietly overwriting it — and recorded a **user decision** to accept the
regression as a known cost, with the reasoning written down.

## Does it do what was intended?

Yes. I re-verified rather than re-read, and I ran every test command:

| command | result |
|---|---|
| `uv run pytest -q` | **74 passed**, 23 deselected |
| `uv run pytest -m golden -q` | **16 passed** |
| `uv run pytest -m measurement -q` | **3 failed, 4 passed** — exactly as declared |
| `uv run python -m tests.test_measurement_queries` | table reproduces the record |
| `bash hooks/memsearch-nudge.test.sh` | **27/27 passed** |

**I re-derived the counterfactual with my own harness** (`/tmp/judge_cf.py`, written independently of
the branch's), drawing pools at 1000 and truncating to 200 *after* removal. It reproduced the doc's
control table **cell for cell**, including the incidental `hits 4 → 5` detail:

```
query                                   no-op     -archive    -thisfile
stale-phase-guard-rule-text            P(4)/P       P(4)/P       P(5)/P
falsifier-base-pin                     F(1)/P       P(2)/P       F(1)/P
git-guard-empty-index                  P(2)/P       F(1)/P       F(1)/P
verification-marker-gate               F(1)/F       F(1)/F       F(1)/F
phase-guard-hook                       P(2)/F       P(2)/F       P(2)/F
```

**The correction is correct, and it is not an overcorrection.** Three independent lines of evidence
converge on "R10 caused both moves":

1. The **task 8b temporal baseline** — taken when the archive was genuinely absent from the index
   (zero `archive_doc` rows) — recorded `falsifier-base-pin` PASS(2) and `git-guard-empty-index`
   FAIL(1). This is a stronger control than any leave-one-out, and it is exactly what
   `minus archive_doc` recovers.
2. The branch's own leave-one-out control.
3. My independently written harness.

I also verified the reconstruction is legitimate: `config.json` (`b78eae8..HEAD`) shows
`CODING_MEMORY.md` removed from `exclude_paths` and added to `curated_docs` with a new
`archive_doc: 1.0` weight **on this branch**, and all 257 `archive_doc` chunks are new here.

## What could go wrong — the honest concerns

### 1. "Removing this file flips none" is contradicted by the doc's own table — and the error is mine ⚠️

The corrected section concludes: *"Removing the archive flips two outcomes… **Removing this file
flips none.**… **Passenger, not driver.**"*

Read the third column of its own table. `git-guard-empty-index` is **PASS (2)** as-is and
**FAIL (1)** with this file removed. That is a flipped clause outcome. My harness confirms it:
`P(2)/P` → `F(1)/P`.

So the true counts are:

- `minus archive_doc` → flips **2** clause outcomes ✓ (as recorded)
- `minus this file` → flips **1**, not zero ✗

At query level it is starker: as-is R9 scores **2 of 5**; with this file removed it scores **1 of 5**.
The feature file is not a passenger — it is **load-bearing for one of the two queries that currently
pass**.

**This error originated in my previous verdict, not in the branch.** My own concern #1 read
*"removing this doc's `## Verification` flips 0"*, and my table contradicted my prose in exactly the
same cell. The author re-derived the numbers correctly — their table is right — and inherited my
faulty summary sentence. I am flagging it against the branch because it is in the branch's record
now, but the provenance is mine and the author's measurement was sound.

**Why it matters beyond bookkeeping:** it weakens the symmetry the accepted-cost argument leans on.
"2 of 5 before, 2 of 5 after — R10 only swapped which two" is true, but the *post* "2" includes a
query whose pass is jointly propped up by the archive **and** by the measurement record itself. The
right-hand side of that symmetry is less stable than the left.

### 2. Is "accepted cost" adequately evidenced, or a rationalisation?

**Mostly evidenced.** I tried to break it and its two load-bearing legs held:

- **"R9's bar has never passed."** Verified against the 8b table: 8b passed `stale` and
  `falsifier-base-pin` (2 of 5); now it passes `stale` and `git-guard-empty-index` (2 of 5). R10
  swapped which two. It did not break a green bar. ✓
- **"Two of the three failures are pre-existing."** `verification-marker-gate` and `phase-guard-hook`
  fail in all three control variants **and** failed identically at 8b with the archive absent. That
  is ADR/judge-verdict crowding, not R10. ✓

The hole is not in the reasoning, it is in the **durability**: the acceptance is a point-in-time
judgment on a corpus that grows monotonically and has **no alarm attached**. `CODING_MEMORY.md` grew
507 lines on this branch alone; the archive is at 257 chunks; R9 is the only detector that can see
this class of drift, and `pyproject.toml:26` deselects it from the default run. The doc says "re-check
as the archive grows" for the *golden* margin, but the acceptance decision itself carries no trigger,
threshold, or owner for the re-check. An accepted cost with no monitor becomes an unnoticed cost.

### 3. The record was accepted against an index that is already stale

`status.json` reports `last_run: 2026-08-08T04:29:56Z`. Both correction commits landed **after** it
(`6686b6e` 05:35Z, `b81ff6f` 05:52Z). Confirmed against the live DB: the new verdict file has
**0 chunks** indexed.

So the numbers the decision was taken on describe a corpus that no longer matches the repo. Landing
this branch adds, on the next scheduled run:

- **+75 net lines** to the feature file, all inside `## Verification` — the section already holding
  rank 1 at the score ceiling on the two worst queries;
- a **new 190-line judge verdict** under `coding-memory/observability-judge/`, a `curated_doc` at
  weight **1.5** (higher than `archive_doc`'s 1.0), naming `falsifier-base-pin` ×7,
  `git-guard-empty-index` ×3, `verification-marker-gate` ×2, `phase-guard-hook` ×2.

Judge verdicts are proven strong competitors here: at 8b they held **rank 1 on two of the five
queries**, and they still occupy ranks 3–6 today. Mitigating: the new file does not contain the
literal query strings, and at ~15.6 chunks per verdict file the addition is ~7–10 chunks against
8615. The effect is real but modest — the point is that it is **unmeasured**, and the R9 table will
move again before anyone looks.

The retracted insight — *"recording a retrieval measurement inside an indexed document perturbs the
next run of it"* — was correct as a mechanism. The retraction rightly demoted it as the *cause of
these failures*, but the doc now reads as having largely disposed of it, and the correction itself
made that section 75 lines heavier.

### 4. On the visible-retraction style (asked directly)

**Keep it.** Erasing a causal error erases the lesson, and this one is genuinely instructive — the
"absence from the frame is not absence of effect" mechanism is the sort of thing a future reader will
re-derive the hard way otherwise. Preserving the wrong inference *plus why it was tempting* is the
strongest audit-trail move on this branch.

But the cost you named is real and now compounding: the section is indexed, it is already rank 1 on
two queries, and the fix for that is deferred. My recommendation: keep the retraction visible, and
treat the doc's own named remedy — hold measurement records outside the indexed corpus, or exclude
`## Verification` from indexing — as **more** urgent than before, not less. It is the only concern
here that this change actively worsened.

### 5. Falsifier verdicts (task 10c) — re-checked, unchanged

The corrections touched nothing in 10c. Ten clauses, six held only in test because the window is
20 sessions post-landing. Clause (i) still conditions on 8b's scores being *recorded* and on target
span, never on R9 passing — so R9's red does not falsify the feature, and the doc says so explicitly
rather than letting a reader infer it. Still the most self-critical part of the record. **Pass,
unchanged.**

### 6. Carried forward, unchanged from last pass

- **Not cleanly revertible.** `git revert` restores `exclude_paths`, but 257 `archive_doc` chunks stay
  in the live DB; removal costs a measured **4h51m34s** `--full`. Git checkpoint, not a system one.
- **`RUN_MAX_HOURS = 6` sits at 81% of a measured cold run**, margin explicitly non-durable. Overrun
  makes a healthy run report as *stuck*.
- **Zero-files corpus still renders fresh forever** — the founding defect's species, a declared and
  user-owned non-goal.
- **No lock**: manual and scheduled index can race, both writing `status.json`.
- **Golden suite structurally cannot see this class of regression** — presence-anywhere-in-top-k
  (`test_golden_queries.py:39`).

### 7. The stray compliance-judge files — the author's call was right

`coding-memory/compliance-judge/verdicts.jsonl` (modified) and
`2026-08-08-falsify-harness-signatures.md` (untracked) belong to a different session on a different
feature. Declining to touch them and pathspec-scoping every commit is **correct** under the
parallel-agent invariants in `core-conduct.md` ("Never touch files outside your assigned feature
domain"). I withdraw the housekeeping item from my last verdict. The only residual care: do not use
`git commit -a` on this branch, or they will ride along.

## What I'd double-check before merging

1. **Fix the one-sentence contradiction** — "removing this file flips none / passenger, not driver"
   should read *flips one* (`git-guard-empty-index` clause 1, PASS→FAIL), and should note the file is
   load-bearing for one of the two passing queries. The table beneath it is already correct. Cite my
   error as the source so the provenance is honest.
2. **Attach a re-check trigger to the accepted cost.** Name a threshold (archive chunk count, or "run
   `-m measurement` at each ADR 0021 revisit") and an owner. Accepted-with-no-monitor is how a known
   cost becomes an unknown one.
3. **Re-run `-m measurement` after the first index run that includes these two commits**, and record
   the delta. The decision was taken on a pre-correction snapshot; you should know which way it moved
   before ADR 0021 inherits the numbers.
4. **Consider putting R9 in CI as reported-not-blocking** rather than deselected. `addopts` currently
   makes `pytest -q` print `74 passed` while the feature's own bar is red.
5. **ADR 0021** must inherit the *corrected* attribution including item 1's fix. Correctly deferred as
   out-of-phase (`phase: review`) — carried, not dropped.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| `intent` | **pass** | No product change since last pass; agent loaded, `status.json` split live, 8-state line emitting, archive indexed. All five test commands run and match declarations. |
| `execution` | **concern** | Unit 74✓, golden 16✓, nudge 27/27✓, measurement 3F/4P exactly as declared. R9 — the feature's own retrieval bar — is still red at merge. Now an owned, reasoned red rather than a misattributed one, but red. |
| `trajectory` | **concern** | Sharply improved: the author rebuilt the counterfactual independently with a no-op harness guard rather than trusting the judge, and explicitly refused to retune without a control. Held back because the same species recurred — a conclusion outrunning its own table — in the very section rewritten to fix that failure mode. |
| `regression` | **concern** | `falsifier-base-pin` clause 1 is a real R10-caused regression, now correctly attributed and explicitly accepted by the user. Detection gap persists: golden can't see ranking, R9 is deselected by default, archive grows every session. |
| `context_budget` | **pass** | No always-on rule/skill/prompt growth; `rules/gates.md` and `CLAUDE.md` untouched. One bounded session-start line, ≤1 line and exit 0 guaranteed by 27 tests. (Retrieval budget is a separate, flagged issue.) |
| `traceability` | **pass** | Upgraded from concern. Headline causal claim is now correct and I reproduced its control table exactly from the doc alone. Retraction visible with the wrong inference preserved. One summary sentence contradicts its own adjacent table — caught only because the evidence is right there, which is what traceable means. |
| `success_masking` | **concern** | `addopts` deselects the failing bar; golden 16/16 green over a live ranking regression; zero-files corpus renders fresh forever; `RUN_MAX_HOURS` at 81% of measured cold. New: accepted cost has no monitor on a monotonically growing corpus. |
| `intent_drift` | **pass** | Both commits docs-only and scoped to the feature file plus memory/verdict records. No new dependencies. Declining to touch another session's compliance-judge files is correct per parallel-agent invariants. ADR 0021 correctly deferred as out-of-phase. |
| `checkpoint` | **concern** | 23 clean commits, but `git revert` does not undo the live artifact — 257 archive chunks persist until a ~4h51m `--full`. New: live index (`last_run 04:29:56Z`) is stale against HEAD, so system and repo currently disagree. |
| `audit_trail` | **pass** | Decision attributed to the user with date and the frame it was taken under; retraction preserves the wrong reasoning and why it was tempting; ADRs 0018/0020 present, 0021 named and deferred. Every measurement reproducible — I reproduced the control table and the 8b baseline independently. |

## Concerns

1. "Removing this file flips none / passenger, not driver" is contradicted by the doc's own table: `git-guard-empty-index` goes PASS(2)→FAIL(1) with this file removed. Flips one, not zero — error inherited from the prior judge verdict
2. At query level, R9 scores 2 of 5 as-is but 1 of 5 with this file removed — the feature file is load-bearing for one of the two passing queries, not a passenger
3. Accepted cost carries no re-check trigger, threshold, or owner, on a corpus that grows every session (CODING_MEMORY.md +507 lines on this branch alone)
4. Decision was taken against a stale index: `last_run 04:29:56Z` predates both correction commits; the new verdict file has 0 chunks indexed
5. The corrections add ~75 lines to the already-rank-1 `## Verification` section plus a 190-line curated_doc verdict at weight 1.5 — the self-perturbation the doc retracted as a cause but did not eliminate as a mechanism
6. R9 remains red at merge (3 of 5 fail); `addopts` deselects it so default `pytest -q` reports 74 passed
7. Golden suite's presence-only assertion structurally cannot detect this class of ranking regression
8. Not cleanly revertible: 257 archive chunks persist after a git revert; removal costs a measured 4h51m34s `--full`
9. `RUN_MAX_HOURS=6` at 81% of measured cold run, margin explicitly non-durable — overrun renders a healthy run as "stuck"
10. Zero-files corpus still renders fresh indefinitely — the founding defect's species, by declared non-goal
11. No lock: manual and scheduled index can race, both writing `status.json`
12. Falsifier window not open — 10 clauses held in test, 6 never observed in production; post-landing re-check owed
13. Working tree carries another session's compliance-judge files — correctly left alone, but `git commit -a` would sweep them in

**risk = medium · confidence = high**
