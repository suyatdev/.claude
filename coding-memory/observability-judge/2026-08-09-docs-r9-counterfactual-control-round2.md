# Observability verdict — `docs/r9-counterfactual-control` @ `3609faa` (round 2)

- **repo:** `memsearch-freshness` (worktree of `~/.claude`)
- **branch:** `docs/r9-counterfactual-control` → slug `docs-r9-counterfactual-control`
- **head_sha:** `3609faa90632bd854bc208a56b6b82efff98592e` (amends `52b09c3`, judged in
  `2026-08-09-docs-r9-counterfactual-control.md`)
- **base:** `origin/main` @ `64d8acb` (local `main` still stale at `8d79094`)
- **stage:** implementation
- **ts:** 2026-08-09T17:07:04Z
- **filename note:** the round-1 verdict already occupies `2026-08-09-docs-r9-counterfactual-control.md`
  and is untracked; writing the bare slug would have destroyed it. Suffixed `-round2` per this
  directory's existing convention (`…-round2.md` … `…-round5.md`).
- **diff:** 2 files, +202 / −1 — `docs/features/memsearch-freshness.md`, `CODING_MEMORY.md`. No
  source, no tests, no config.
- **test command run by me:** `cd ~/.claude/memsearch && uv run pytest -q` → **74 passed, 23
  deselected in 0.34s**. Matches the caller's report. It exercises nothing in this diff.

---

## What was changed

Last round I raised five objections to an experiment write-up. This round is the response, plus one
error the author found in their own work while answering objection 4 — and that self-caught error is
the biggest thing in the diff.

The experiment: an index of this repo's notes is failing a five-question retrieval quiz. To find out
which pile of documents is crowding out the right answers, copy the index, delete one pile, re-run
the quiz. The earlier round concluded "the judge verdicts are the cause."

What changed:

1. **All ten ranks are now printed** (I had complained four were elided, and guessed the missing rows
   might be archive chunks). **My guess was wrong** — the missing rows are three
   `replay-harness-base-pin.md` chunks and one ADR. No archive chunk appears in the top ten at all,
   which independently explains why deleting the archive can't move this query.
2. **"The cause" downgraded to "the only population tested that moves it"** in the heading, the commit
   subject and the memory entry, with a closing paragraph saying plainly that this is sufficiency over
   a tested set, not uniqueness.
3. **The reproducibility claim rewritten** — I said the pinned artefacts didn't exist; **I was wrong
   on the facts**, they're in a session scratchpad I hadn't searched. But they're ephemeral, so the doc
   now says reproduction means re-derivable, not re-runnable.
4. **The BM25 objection measured instead of argued.** Judge chunks were physically deleted from a copy
   of the pinned database and the keyword index rebuilt. All five verdicts survive; one hit *count*
   moves (4 → 3). Recorded as "verdict-safe, not count-exact."
5. **A size error corrected, unprompted.** The judge pile is **2405 chunks (27% of the index)**, not
   the 237-chunk batch previously described — so the "delete judges" test removed 8× more than any
   other test. To rule out "you just deleted a quarter of the corpus," a **size-matched placebo** was
   run: delete 2405 *random* unrelated chunks, three seeds. Nothing moved.

## Does it do what you wanted?

Yes — and this round I could check the load-bearing claim myself rather than take it on trust.

- I **re-ran the placebo script** against the pinned snapshot. It reproduced the doc's table exactly,
  cell for cell, and printed `judge chunks=2405   eligible placebo pool=6372`.
- The **2405 figure is arithmetic, not assertion**: the pinned database has 8960 chunks, the
  judges-removed copy has **6555**. 8960 − 6555 = 2405. Both verified read-only.
- The **depth-10 listing in the doc matches the raw `results.txt`** line for line, including the two
  rows I'd been unable to see.
- The structural claims check out: `memsearch/config.json:17` puts `curated_doc` at **1.5** (verdicts
  and feature specs share it, archive sits at 1.0); `memsearch/memsearch/db.py:80-81` really is
  external-content FTS5, which is what made the exact rebuild possible; `ollama.py:31-42` passes only
  `{model, input}`, so "no seed" is true.

The self-caught size error is the strongest trajectory signal in five rounds of this document. It was
found while answering an objection about something else, it invalidated the framing of the section,
and it was corrected in place with a visible ⚠️ rather than quietly edited out.

## Answering the three questions you asked for pressure on

**1. Does the placebo license the subject-matter conclusion, or does excluding target-feature chunks
guarantee the null?**

It does not guarantee the null — but it is a weaker test than the write-up implies. Excluding target
chunks is correct (deleting a target's own document could only ever hurt it). The pool it leaves is
**not** disjoint from the competitive field: on `git-guard-empty-index`, the query the whole finding
rests on, **5 of the top 10 are placebo-eligible** — rank 2 (`memsearch-freshness.md`), ranks 4, 6, 10
(`replay-harness-base-pin.md`, which is a *different* feature from the `falsifier-base-pin` target and
so is fair game) and rank 9 (ADR 0014). So a dilution effect had a real path to show up.

But the power is moderate, not decisive. To promote the rank-8 chunk into the top 6, at least two of
ranks 2–7 must go; three of those six are eligible, each dropped with probability 2405/6372 ≈ 0.38.
That puts a chance flip at roughly **1-in-3 per seed** — so three straight nulls is about a
**p ≈ 0.3** result. *(Back-of-envelope: assumes independent uniform dropout and ignores RRF re-ranking
and pool backfill. It is an order-of-magnitude sanity check, not a computed statistic.)*

Verdict: the placebo genuinely moves the conclusion from "unsupported" to "supported," and "the
crowding is by subject matter" is the right *direction*. The sentence **"Every placebo column is
identical to `as-is`"** followed by a flat mechanism claim reads as decisive when the test carries
maybe two-to-one odds. The cheap decisive control was not run: **a dose-matched judge draw** — delete
**295 random judge chunks** (matching the archive) or, better, **only the three verdict chunks at
ranks 3, 5 and 7**. If three chunks flip it, the effect is one document, not a 2405-chunk population,
and the planning pass would inherit a very different fix.

**2. Is "verdict-safe, not count-exact" safe from n=1?**

No — and the exposure is not where you looked. You worried about generalizing from one variant. The
sharper problem is that **the placebo, this round's load-bearing control, was measured only with the
approximate method**, at exactly the 2405-chunk drop size where the exact rebuild just proved the
approximation off by one hit count — and in the direction of **over-counting** (approximate said
`PASS (4)`, exact said `PASS (3)`).

Now read the placebo table: `falsifier-base-pin` reads **`PASS (2)`** in all three placebo columns.
Clause 1 needs ≥2. **One over-count is the difference between `PASS (2)` and `FAIL (1)`** — and a
placebo that flips a query is a placebo that breaks the subject-matter conclusion outright. So the
one known instance of the method's error is exactly large enough, and pointed in exactly the right
direction, to overturn the control it was not applied to.

That is cheap to close: `fts_exact.py` already exists; point it at one placebo seed instead of the
judge set. Until then, "verdict-safe" is a claim about one variant being used to underwrite five
others, which is the same one-notch over-statement this section has now corrected four times.

**3. Self-interest disclosure — same as last round, and it cuts the other way this time.**

The conclusion is that judge output crowds out feature documents. I am the judge. My incentive is to
discount it; I did not, and I reproduced the mechanism myself. The disclosure worth adding is
concrete rather than rhetorical: **this verdict file is itself another `curated_doc` at weight 1.5,
about a feature, filed next to the feature's spec.** By the finding's own logic I have just made the
measured problem slightly worse, and the next R9 run will include these words.

## What could go wrong / what I'm unsure about

**1. The sha256 the doc tells a reader to verify against does not match the file.** New finding, and
the same species this document keeps producing — a verification instruction that cannot pass. The doc
says: confirm the snapshot "against sha256 `9ba25e05de7f558c…` (60116992 bytes)". I hashed it:

```
77997c764c6ce96baafaff74263bf3971f0fb6929796661fafc2062879ec7451   memory.pinned.db  (60116992 bytes)
mtime 2026-08-09T03:25:27   ·   pin.json written 03:20:31, recording 9ba25e05…
```

The file has not been touched since the measurement run (mtime 03:25:27; `results.txt` 03:25:28), so
this is not later corruption — SQLite rewrote the header when the harness opened it, **after** the
hash was taken. The recorded hash therefore never described the artefact as measured. The
*substantive* invariants do verify — I confirmed `chunks = 8960` and
`max(indexed_at) = 2026-08-09T04:45:14+00:00` read-only — so the data is intact and the finding
stands. But a future reader following the stated recipe gets a mismatch on a good artefact and, per
the doc's own rule ("a different `last_indexed` voids the comparison"), would wrongly discard it.
Drop the hash or re-record it; the chunk count and timestamp are the real anchors.

**2. The reproduction recipe is already non-executable.** It says "re-pin, confirm `chunks = 8960`."
The live index is at **9016** and moving. Only the ephemeral scratchpad copy holds the 8960-chunk
state. That is honestly framed ("re-derivable, not re-runnable"), but the recipe as written has no
path to success today, and the doc doesn't say so.

**3. The two controls on the control have no persisted raw output.** `results.txt` covers the main
counterfactual only. The placebo table, the exact-FTS table and the 8/8 noise probe exist in the doc
as retyped numbers; their scripts are in the same ephemeral scratchpad, their outputs nowhere. I
closed this for the placebo by re-running it (exact match) and for FTS structurally (the 6555-chunk
database exists), but the **noise probe — "≤1.08e-04 per element, min cosine 0.999999803, identical
verdicts on 8/8"** — is the one load-bearing number in this diff I could not verify from any artefact.

**4. Residual over-claim at `:1971`, in the sentence a reader hits first.** The definite-article fix
landed in the heading, the commit subject and `CODING_MEMORY.md`, but the forward pointer into the
new section still reads: **"The cause is assigned, and it is neither of the two populations this
section suspected."** That is the frame the very next section spends a paragraph disclaiming. Same
species, fifth instance, now one line above its own retraction.

**5. The likely-minimal cause is much smaller than the population credited.** The doc's own depth-10
evidence shows the flip driven by **three chunks of one verdict file** about that exact fix. Crediting
"the judge-verdict corpus (2405 chunks, 27%)" is true as a population statement but invites a
population-scale remedy (retune `curated_doc` weight) for what may be a three-chunk, one-document
effect — and the doc already measures that the population-scale remedy costs `falsifier-base-pin` its
pass. The minimal-sufficient-set test is one line of the existing harness.

**6. Self-perturbation, unchanged.** This commit adds 165 lines to the 2130-line document under
measurement and 38 lines to `CODING_MEMORY.md`, both `curated_doc` at 1.5. Acknowledged for prior
entries, not for this one.

**7. Inherited, unfixed:** frontmatter still records `branch: feature/memsearch-freshness` while HEAD
is `docs/r9-counterfactual-control`; local `main` is stale at `8d79094` (a tool defaulting to `main`
diffs 34 files instead of 2); `pyproject.toml:26` deselects the measurement marker, so `pytest -q`
reports 74 green over a 2-of-5 red retrieval bar.

## What I'd double-check before merging

1. **Run `fts_exact.py` against one placebo seed.** `falsifier-base-pin` at `PASS (2)` is one known
   over-count from `FAIL (1)`, and that flip would break the round's main conclusion. Highest value
   per minute in this list.
2. **Fix or delete the sha256.** As written it fails against the intact artefact.
3. **Fix `:1971`** — "The cause is assigned" now contradicts the section it introduces.
4. **Optional but clarifying:** drop only the three verdict chunks at ranks 3/5/7. If that flips it,
   the finding is about one oversized verdict, not a 2405-chunk population, and the planning pass
   inherits a different and much cheaper fix.

None of these block a docs-only merge — nothing here executes. They block treating the conclusion as
settled input to the ADR 0021 weighting decision, which is what it will be used for.

---

## Dimensions

| dimension | score | note |
|---|---|---|
| intent | pass | all five prior findings materially addressed; two were addressed by refuting me with data |
| execution | pass | placebo table independently reproduced cell-for-cell; 2405 = 8960 − 6555 verified in the artefacts; tests 74 passed / 23 deselected |
| trajectory | pass | unprompted self-caught size error (2405 vs 237), corrected visibly with ⚠️; claim strength downgraded rather than defended |
| regression | pass | docs-only; no source, tests or config touched; the pinned artefacts live outside the repo |
| context_budget | concern | +202 lines of `curated_doc` weight-1.5 text into the corpus this document is measuring; card now 2130 lines, `.spec.md` split still not taken |
| traceability | concern | recorded sha256 does not match the artefact; reproduction recipe non-executable (live index past 8960); placebo/FTS/noise raw outputs not persisted |
| success_masking | concern | placebo measured only with the approximation just shown to over-count by one at the same drop size; `falsifier-base-pin` placebo `PASS (2)` is one over-count from breaking the conclusion; `pytest -q` green over a 2-of-5 red R9 |
| intent_drift | pass | scope is exactly the owed control plus the two controls the prior verdict prompted; no drive-by edits |
| checkpoint | pass | single amended docs-only commit off `origin/main`; trivially revertible; nothing mutated outside the scratchpad |
| audit_trail | pass | commit body detailed and attributed; the size error corrected in place rather than silently; ADR 0021 ownership restated |

**risk:** low · **confidence:** high

### Concerns
- Recorded sha256 `9ba25e05…` does not match the pinned DB (`77997c76…`, mtime unchanged since the run) — the stated verification step fails against an intact artefact
- Reproduction recipe ("re-pin, confirm chunks = 8960") is non-executable: live index is at 9016 and only the ephemeral scratchpad holds the pinned state
- Placebo control measured only with the candidate-drop approximation, at the same 2405-chunk drop size where the exact rebuild proved it over-counts by one hit
- `falsifier-base-pin` reads `PASS (2)` in all three placebo columns — one over-count from `FAIL (1)`, which would break the subject-matter conclusion
- Placebo power is moderate, not decisive: ~1-in-3 chance per seed of a chance flip (rough estimate), so three nulls ≈ p 0.3; stated as if categorical
- Dose-matched judge control not run (295 random judge chunks, or just the 3 verdict chunks at ranks 3/5/7) — the minimal sufficient set is likely one document, not a 2405-chunk population
- `:1971` still reads "The cause is assigned" — the definite-article fix missed the forward pointer a reader hits before the section that disclaims it
- Noise-probe numbers (≤1.08e-04, min cosine 0.999999803, 8/8 identical) have no persisted artefact and could not be verified
- Placebo uses a separate re-implementation (`variant_search_by_id`); the no-op path-for-path guard the doc calls load-bearing was not re-asserted for it
- Self-perturbation: +165 lines into the 2130-line document under measurement, +38 into `CODING_MEMORY.md`, both curated_doc 1.5 — including this verdict file
- Judge self-interest: the finding constrains judge output; disclosed, and the evidence was independently reproduced rather than discounted
- Frontmatter still records `branch: feature/memsearch-freshness` while HEAD is `docs/r9-counterfactual-control`
- Local `main` stale at `8d79094`; a tool defaulting to `main` diffs 34 files instead of 2
- `pyproject.toml:26` deselects the measurement marker, so `pytest -q` reports 74 passed over a 2-of-5 red retrieval bar
- 10b's index state still unreconstructed — correctly left open, but the reconciliation remains unavailable
