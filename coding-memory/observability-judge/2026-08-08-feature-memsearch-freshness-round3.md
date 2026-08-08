# Observability verdict (round 3) — `feature/memsearch-freshness` @ `1be05b5`

- **stage:** implementation (gates the PR)
- **repo:** `.claude` · **base:** `main` @ `b78eae8` · **24 commits**
- **judged:** 2026-08-08T06:27:53Z
- **head_sha:** `1be05b51a4b73037c03d01b11ee857d226612dea`
- **spec:** `docs/features/memsearch-freshness.md` (`phase: review`, 1848 lines)
- **supersedes:** `…-round2.md` @ `b81ff6f` (risk=medium, confidence=high)

---

## What was changed

Confirmed docs-only since round 2 — `git diff --stat b81ff6f..HEAD` touches four files, none of them
code, config, or test:

```
 CODING_MEMORY.md                                   |  49 +++++
 ...-feature-memsearch-freshness-round2.md          | 229 +++++++++++++++++++++
 coding-memory/observability-judge/verdicts.jsonl   |   1 +
 docs/features/memsearch-freshness.md               |  52 ++++-
```

Think of it like a lab notebook, not the experiment. The experiment (the launchd schedule, the
run/content recency split, the archive indexing) has not moved since round 2. What moved is **the
written record of who caused what** — and this is the third correction to the same paragraph.

The story in one line: the record first blamed the wrong thing, round 1 corrected the blame, and then
round 2 caught that the *correction* had a sentence contradicting its own table. This commit fixes
that sentence and bolts an alarm onto the decision that rested on it.

## Does it do what was intended?

**Yes, and I verified the numbers myself rather than reading them.** I wrote my own counterfactual
harness (`/tmp/judge3_cf.py`) from `search.py`'s algorithm — not from the branch's harness — drawing
candidate pools at 1000 and truncating to 200 *after* removal, with a guard that the no-op variant
must reproduce `search()` exactly. It did, on all five queries. Result:

```
query                            as-is     -archive   -thisfile
stale-phase-guard-rule-text      P(4)/P     P(4)/P     P(5)/P
falsifier-base-pin               F(1)/P     P(2)/P     F(1)/P
git-guard-empty-index            P(2)/P     F(1)/P     F(1)/P
verification-marker-gate         F(1)/F     F(1)/F     F(1)/F
phase-guard-hook                 P(2)/F     P(2)/F     P(2)/F

no-op guard reproduces search() exactly: True
R9  as-is=2/5   minus-archive=2/5   minus-thisfile=1/5
```

**Every claim in the corrected paragraph is accurate.** Checked individually:

| claim in the doc | my check |
|---|---|
| "flips **one**, not zero" | ✓ `git-guard-empty-index` P(2)→F(1) with the file dropped |
| "Without this file R9 scores **1 of 5**, not 2" | ✓ reproduced exactly |
| "The archive is the driver of both moves against 8b" | ✓ `-archive` flips exactly the two that moved |
| "passes only with **both** populations present" | ✓ dropping either breaks it |
| "renames the top hit to `2026-08-02-main.md` and ADR `0011`" | ✓ printed both, exact match |
| "hits 4 → 5" on `stale-…` | ✓ |
| chunk counts 6 / 9 / 24 / 53 / 91 | ✓ recomputed from source |
| mechanism: RRF ranks the pool *before* the weight multiply | ✓ `search.py:59-75` — `base_score * weight` happens after pool construction |
| `pyproject.toml:26` deselects the bar | ✓ that is literally line 26 |
| index is stale against HEAD | ✓ `last_run 04:29:56Z`; round-2 verdict has **0** chunks |

All four test commands run, all match their declarations:

| command | result |
|---|---|
| `uv run pytest -q` | **74 passed**, 23 deselected |
| `uv run pytest -m golden -q` | **16 passed**, 81 deselected |
| `uv run pytest -m measurement -q` | **3 failed, 4 passed** — exactly as declared |
| `bash hooks/memsearch-nudge.test.sh` | **27/27 passed** |

**The correction is right and — importantly — it is not an over-correction.** The easy failure here
would have been to swing from "this file is innocent" to "this file is the culprit". It didn't. It
kept the archive attribution (on three agreeing sources) and narrowed only the specific sentence that
was wrong. It also bounded the accepted-cost decision **worse** than before rather than quietly
letting it stand, which is the opposite of motivated reasoning.

## What could go wrong — the honest concerns

### 1. The monitor's threshold is the one metric this doc proved is blind ⚠️ (new, substantive)

This is my only new finding of substance, and it is a design gap, not phrasing.

The new monitor reads: *"**Threshold:** if R9 drops **below 2 of 5**, the accepted cost has changed
shape and the decision is reopened."* (`memsearch-freshness.md:1802-1803`)

Now read what the same document established 90 lines earlier, at `:1711`:

> ⚠️ **The count is unchanged from 8b's 2-of-5 and the composition is not.** Recording only "2 of 5,
> same as before" would have reported no change where two queries in fact moved in opposite
> directions.

That sentence is the founding insight of this entire section — the whole retraction chain exists
because a stable count of 2/5 concealed one regression and one improvement cancelling. The monitor
then adopts **that exact count** as its trip-wire. If the next run comes back 2 of 5 with both passes
belonging to *different* queries, the threshold is not crossed and the decision is not reopened —
reproducing the precise blindness that cost this branch two review rounds.

The trigger does say "record the delta", which would surface composition to a human reading it. So
this is recoverable in practice. But the *automatic* reopen condition is count-only. **Fix is one
line:** make the threshold "below 2 of 5 **or any change in which queries pass**". Non-blocking for
the PR; it belongs to ADR 0021, which the doc already names as the owner.

### 2. "On the other three queries" — phrasing, not a factual error (non-blocking)

`:1764` says the file is "a visible occupant with no effect on the verdict" on "the other three
queries". There are five queries and one was just named load-bearing, so "the other three" only adds
up if the reader infers that the second currently-passing query (`stale-phase-guard-rule-text`) is
being excluded alongside the first. It is consistent under that reading, and the table above it is
complete and correct.

**Calling this what it is: a readability wrinkle, not a mistake.** Given that the last two rounds each
found a genuine prose-vs-table contradiction here, I checked it hard and it is not one. I would not
hold a PR for it. If it gets touched, "the remaining three" or naming them would close it.

### 3. This file is now the joint-largest feature document in the corpus (new measurement)

Fresh numbers, since the doc reasons about its own retrieval footprint:

- `docs/features/memsearch-freshness.md` is **91 chunks** — tied with `phase-guard-hook` for the
  largest feature in `docs/features/`, and inside R9's **top tertile** by its own anti-gaming rule.
- Indexed drift, quantified: the feature file is **78 indexed → 91 current (+13)**; `CODING_MEMORY.md`
  is **236 → 253 (+17)**; the round-2 verdict is **0 chunks**. So roughly **+30 chunks plus two judge
  verdicts** land on the next scheduled run.

This is the self-perturbation mechanism the doc correctly demoted as the *cause* of the failures but
explicitly kept as a live mechanism. It is disclosed, the trigger is tied to the next scheduled run
rather than a date, and the magnitude is modest against 8615 chunks. **The disclosure is accurate — I
am recording the size, not disputing it.**

A related fragility worth one line: R9's span guard (`test_targets_span_the_corpus_size_range`) ranks
the *whole* `docs/features/` population, currently N=10. `phase-guard-hook` sits at the top-tertile
boundary. Adding a large new feature doc could push it out of the top third and fail the guard. That
fails **loudly** as a test, so it is a maintenance note, not a masking risk.

### 4. Carried, unchanged — the disclosures are correct, re-verified not re-read

- **R9 red at merge**, 3 of 5 fail; `addopts` (`pyproject.toml:26`) means plain `pytest -q` prints
  `74 passed` over a red bar. Re-confirmed.
- **Golden suite is presence-only** (`test_golden_queries.py:39`) and structurally cannot see a
  ranking regression. Re-confirmed at 16/16 green.
- **Not cleanly revertible** — 257 `archive_doc` chunks survive `git revert`; removal costs a measured
  4h51m34s `--full`. Confirmed 257 live in the DB.
- **`RUN_MAX_HOURS=6` at 81%** of the measured cold run, margin explicitly non-durable.
- **Zero-files corpus reads fresh forever** — declared, user-settled non-goal.
- **No index lock**; falsifier window not open (10 clauses held in test, post-landing re-check owed).

### 5. The compliance-judge files — not re-raised as an action

`coding-memory/compliance-judge/verdicts.jsonl` (modified) and `2026-08-08-falsify-harness-signatures.md`
(untracked) are in the working tree and belong to another session on another feature. Leaving them
alone is **correct** under the parallel-agent invariants. Noting only the mechanical hazard, as asked:
`git commit -a` on this branch would sweep them in. Every commit here has been pathspec-scoped.

### 6. On the three-layer correction stack (a process observation)

The section now carries the original wrong inference, its retraction, and a correction to the
retraction, all visible. **Keep it** — same recommendation as round 2. The cost is that one paragraph
now takes real effort to read in order; the benefit is that a future reader sees both failure modes
("absence from the frame is not absence of effect", and "check the claim against your own table")
with the reasoning that made each tempting.

The honest process note: **both factual errors were caught by review, not by self-check**, and both
were the same species — a summary sentence outrunning the table printed directly beneath it. This
round's fix is sound and independently verified, and the doc says so plainly rather than blaming the
reviewer whose phrasing it inherited ("my own output was on screen … copying a reviewer's summary over
reading my own table is the whole failure"). That is the right posture. The gate is working; it is
just doing more of the work than self-check is.

## What I'd double-check before merging

1. **Widen the monitor's threshold to catch composition, not just count** (concern 1). One line, and
   it is the difference between an alarm that works and one that reproduces the bug it was built for.
   ADR 0021 already owns it.
2. **Re-run `-m measurement` after the first scheduled index run containing these commits.** Already
   the doc's own trigger; ~+30 chunks plus two verdicts land at that run, so the numbers will move.
3. **R9 in CI as reported-not-blocking** rather than deselected — carried from round 2, planning-pass
   work.
4. **Do not use `git commit -a`** while the other session's compliance-judge files sit in the tree.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| `intent` | **pass** | Round 3 does exactly what round 2 asked: "flips none" → "flips one", and the bare note upgraded to owner + trigger + threshold. Docs-only, confirmed by `git diff --stat`. No product change. |
| `execution` | **concern** | All four commands run and match declarations exactly (74 / 16 / 3F-4P / 27-27). R9 — the feature's own retrieval bar — is still red at merge. An owned, correctly-attributed, user-accepted red, but red. Unchanged by this commit. |
| `trajectory` | **pass** | Upgraded from concern. The correction was re-derived from a re-run control, not guessed, and I reproduced it independently cell-for-cell. Crucially it did **not** overcorrect — the archive attribution survives on three agreeing sources, and the decision was bounded *worse*, not defended. Provenance of the inherited error stated honestly. |
| `regression` | **concern** | `falsifier-base-pin` clause 1 remains a real R10-caused regression, correctly attributed and explicitly user-accepted. Detection gap persists: golden can't see ranking, R9 is deselected by default, archive grows every session. Unchanged. |
| `context_budget` | **pass** | `CLAUDE.md`, `rules/`, `skills/`, `settings.json` untouched across the entire branch (`git diff --stat b78eae8..HEAD` on those paths is empty). One bounded session-start line, ≤1 line and exit 0 guaranteed by 27 tests. Retrieval budget is tracked separately as concern 3. |
| `traceability` | **pass** | Strongest dimension here. I reproduced the full control table, the top-hit renames, the chunk counts, and the RRF mechanism from the document alone, with an independently written harness. Ten checkable claims, ten correct. |
| `success_masking` | **concern** | New: the monitor's reopen threshold is count-only, the exact metric this doc proved conceals compensating moves (`:1711` vs `:1802`). Carried: `addopts` deselects the failing bar; golden 16/16 green over a live ranking regression; `RUN_MAX_HOURS` at 81% of measured cold; zero-files corpus renders fresh forever. |
| `intent_drift` | **pass** | Single docs-only commit scoped to the feature file, `CODING_MEMORY.md`, and the verdict store. No new dependencies. Declining to touch another session's compliance-judge files is correct per parallel-agent invariants. ADR 0021 correctly deferred as out-of-phase (`phase: review`). |
| `checkpoint` | **concern** | 24 clean, pathspec-scoped commits and a trivially revertible docs change. But `git revert` still does not undo the live artifact — 257 archive chunks persist until a ~4h51m `--full` — and the index (`last_run 04:29:56Z`) remains stale against HEAD, so repo and system disagree by ~30 chunks plus two verdicts. |
| `audit_trail` | **pass** | Exemplary. Three correction layers preserved visibly with the reasoning that made each tempting; user decision attributed with date and the frame it was taken under; the inherited-phrasing provenance stated without hiding behind the reviewer; ADRs 0018/0020 present, 0021 named, owned, and deferred; monitor carries owner + trigger + threshold. |

## Concerns

1. Monitor's reopen threshold ("below 2 of 5") is count-only — the doc itself proves at `:1711` that a stable count concealed two opposite moves; a 2/5 with different queries passing would not trip it
2. R9 remains red at merge (3 of 5 fail); `pyproject.toml:26` deselects it so default `pytest -q` reports 74 passed
3. `falsifier-base-pin` clause 1 is a live, user-accepted R10-caused ranking regression
4. Index stale against HEAD: feature file 78→91 chunks, `CODING_MEMORY.md` 236→253, round-2 verdict 0 chunks — decision taken on a snapshot that no longer matches the repo (disclosed)
5. `docs/features/memsearch-freshness.md` is now 91 chunks — tied for largest feature doc, inside R9's own top tertile; the self-perturbation mechanism is demoted as cause but still live
6. Golden suite's presence-only assertion structurally cannot detect this class of ranking regression
7. Not cleanly revertible: 257 archive chunks persist after `git revert`; removal costs a measured 4h51m34s `--full`
8. `RUN_MAX_HOURS=6` at 81% of measured cold run, margin explicitly non-durable — overrun renders a healthy run as "stuck"
9. Zero-files corpus renders fresh indefinitely — the founding defect's species, by declared non-goal
10. No index lock: manual and scheduled runs can race, both writing `status.json`
11. Falsifier window not open — 10 clauses held in test, post-landing re-check owed
12. R9 span guard depends on the whole `docs/features/` population (N=10); a new large feature doc could push `phase-guard-hook` out of the top tertile — fails loudly, maintenance note only
13. "On the other three queries" (`:1764`) is a coverage-phrasing wrinkle, not a factual error — table beneath it is complete and correct; non-blocking
14. Working tree carries another session's compliance-judge files — correctly left alone, but `git commit -a` would sweep them in

**risk = medium · confidence = high**
