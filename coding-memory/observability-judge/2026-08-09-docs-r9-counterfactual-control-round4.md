# Observability verdict — `docs/r9-counterfactual-control` @ `3592a63` (round 4)

- **repo:** `memsearch-freshness` (worktree of `~/.claude`)
- **branch:** `docs/r9-counterfactual-control` → slug `docs-r9-counterfactual-control`
- **head_sha:** `3592a63631410921faf85a3ca2cf3a560b359c3a` (amends `3e9ec4b`, judged in
  `2026-08-09-docs-r9-counterfactual-control-round3.md`)
- **base:** `origin/main` @ `64d8acb` (local `main` still stale at `8d79094` — a tool defaulting to
  `main` diffs 34 files instead of 2)
- **stage:** implementation
- **ts:** 2026-08-09T17:30:27Z
- **filename note:** rounds 1–3 occupy the bare slug, `-round2` and `-round3`; suffixed `-round4`
  per this directory's convention.
- **diff:** 2 files, +351 / −2 vs `origin/main` — `docs/features/memsearch-freshness.md` (+287/−2),
  `CODING_MEMORY.md` (+64). Round-3 → round-4 delta is +62. No source, tests or config.
- **test command run by me:** `cd ~/.claude/memsearch && uv run pytest -q` → **74 passed, 23
  deselected in 0.38s**. Matches the caller's report. It exercises nothing in this diff.
- **what I ran beyond the tests:** I found the pinned artefact, copied it to `/tmp/judge4/`, and
  re-ran the round-4 experiment myself — approximate *and* exact method — using the author's own
  pinned query vectors. Scripts and evidence: `/tmp/judge4/replicate.py`, `/tmp/judge4/enum.py`,
  `/tmp/judge4/exact.py`. **The author's artefact was never opened for writing.**

---

## Lead finding — one dimension is `fail`

**The refutation is correct. The conclusion drawn from it is false, and I measured it false on the
author's own snapshot, under both methods.**

The doc now says (`:2180-2184`):

> So the three verdict chunks are **specifically** load-bearing, and equal-sized removals of
> neighbouring occupants are not substitutes.

Removing ranks **2/4/6** — `memsearch-freshness.md` plus two `replay-harness-base-pin.md` chunks,
containing **zero judge chunks** — recovers the query identically:

```
exact method (physical delete + vec0 delete + FTS rebuild), pinned snapshot, pinned vectors
  as-is                        chunks=8960  -> FAIL (1)
  ranks 3/5/7  judge chunks x3 chunks=8957  -> PASS (2)
  ranks 2/4/6  judge chunks x0 chunks=8957  -> PASS (2)   <-- the falsifier
  ranks 4/6    judge chunks x0 chunks=8958  -> FAIL (1)
```

Exhaustively, every subset of ranks 2–7 (all of which sit above the target at rank 8):

| removal size | sets tested | result | judge-chunk count |
|---|---|---|---|
| 2 | all 15 pairs | **FAIL (1)** — 15/15 | 0, 1 or 2 — no effect |
| 3 | all 20 triples | **PASS (2)** — 20/20 | 0, 1, 2 or 3 — no effect |

35 for 35, with no exceptions and no dependence on which document the chunks came from. The rule is
**removal size**, not document identity: *any* three chunks removed from ranks 2–7 recovers clause 1;
*any* two does not.

## What was changed

Think of a queue at a ticket window. Round 3 (me) said: your customer is 8th, and the barrier is that
6 people are ahead — pull any two out and she's inside the cut-off. The author pulled out the two I
named, and she *still* didn't make it, so they concluded she must be blocked by those three specific
people. What actually happened is that a person standing 9th slipped into the gap the moment it
opened. You need to pull **three** people out, and it genuinely does not matter which three.

Concretely, this round does five things:

1. **Refutes my ranks-4/6/10 prediction with a measurement.** Correct — 4/6/10 stays FAIL (1). My
   arithmetic was wrong.
2. **Refutes my "the snapshot is gone" claim.** Also correct — see below; I retract it.
3. Downgrades the exact placebo to n=1, "consistent with, not proof of". As I asked.
4. Marks the superseded placebo table with an in-cell ⚠️ SUPERSEDED banner *above* it. As I asked.
5. Fixes the three-session-stale `branch:` frontmatter to `none`, with an explanatory note rather
   than a silent edit. As I asked.

## Does it do what you wanted?

Three of five, cleanly. The two refutations are where it comes apart — in opposite directions.

### Refutation 2 — the snapshot. I was wrong; you were right; I retract in full.

`memory.pinned.db` exists at
`/private/tmp/claude-501/-Users-marksuyat--claude-memsearch-freshness/d21f0b1f…/scratchpad/`,
**60116992 bytes**, exactly as stated. I opened it read-only and the content anchors match to the
character:

```
chunks=8960  sources=1025  max(indexed_at)=2026-08-09T04:45:14+00:00
```

The scratchpad also holds `vectors.json` (pinned query vectors), `counterfactual.py`, `placebo.py`,
`fts_exact.py`, `round2_checks.py`, `round3_checks.py`, and four derived DB copies. Rounds 1 and 3
searched `/tmp`, `/var/folders`, `~/.claude` and the worktree and concluded destruction from absence.
That was a bad inference from an incomplete search, twice, and it is my error, not the author's.
`traceability` moves **concern → pass**, and the round-3 concern list should be read as superseded on
that point.

The doc's new availability paragraph is the right response, and it is *more* pessimistic than
reality — I re-ran every table in this section from that artefact today. Two small notes: (a) "nobody
can re-run these tables" is currently false, so the honest framing is "expected to be destroyed, so
treat the derivation as the record"; (b) rounds 2 and 3 preserved `round2_checks.py` /
`round3_checks.py` in the scratchpad, but **there is no round-4 script** — the six-row table's code
was not kept even ephemerally.

### Refutation 1 — the re-fusion reasoning. Sound as far as it goes, and it does not reach the conclusion.

You asked me to attack the reasoning rather than concede it. I did both: I conceded the example and
attacked the inference, and the attack succeeds.

**Where you are right.** I decomposed your published depth-10 scores into their RRF branch ranks
(each score is `1.5 × [1/(60+p_vec) + 1/(60+p_fts)]`, and the fit is essentially unique):

| final rank | chunk | branch ranks |
|---|---|---|
| 1 | `git-guard-empty-index.md:14-25` (target) | (1, 2) |
| 2 | `memsearch-freshness.md:1541` | (1, 9) |
| 3 | JUDGE:17-36 | (6, 14) |
| 4 | `replay:594` | (7, 18) |
| 5 | JUDGE:445 | (8, 17) |
| 6 | `replay:607` | (20, 26) |
| 7 | JUDGE:195 | (7, 49) or (22, 24) |
| 8 | `git-guard-empty-index.md:1-6` (target) | (6, 54) |
| 9 | ADR 0014:1-6 | (11, 42) or (12, 40) |
| 10 | `replay:907` | (16, 43) |

My positional model was wrong for exactly the reason you give, and the mechanism is visible here.
Ranks 8 and 9 are separated by **0.000052** — 0.15%. Deleting ranks 4/6/10 gives ADR 0014 (rank 9) a
gain in *both* branches (its ranks 11 and 42 both sit below deleted entries), while the target at
rank 8 gains only in the deep FTS branch (54 → 51, worth almost nothing) because nothing was deleted
above its vector rank of 6. ADR 0014 leapfrogs into the slot I predicted the target would take. So
yes: scores are sums across re-fused branches, not positions in one queue, and my "any two" was
arithmetic that ignored the leapfrog. Measured, and I reproduce your FAIL (1) exactly.

Two corrections to how the mechanism is stated, though: the **200-candidate pool re-draw is not what
does the work.** A new entrant arrives at branch rank ~200, worth `1.5/260 ≈ 0.0058` — it cannot
reach 0.036 and does not appear anywhere in my post-deletion top-8s. What does the work is
*differential per-branch rank gain* among chunks already in the pool, plus a 5.2e-05 margin at ranks
8/9. The doc names the pool, which is the wrong half of the sentence.

**Where it does not reach.** Refuting one counterexample is not confirming the hypothesis. My example
`{4,6,10}` was badly chosen for a reason that is now obvious: **rank 10 is *below* the target at rank
8, so it is inert** — `{4,6,10}` is effectively a two-chunk removal, and every two-chunk removal
fails. The class I should have named is "any three chunks above the target." The author tested six
sets; five of them are 1- or 2-effective-removals, and the sixth is the judge triple. **No set in the
table varies document identity while holding removal size at three** — which is precisely the
comparison the conclusion needs.

I ran that comparison. `{2,4,6}` — same size, three effective removals, **no judge chunks** — gives
PASS (2) under the approximate method and under an exact FTS rebuild. So do all 20 triples. The
sentence "equal-sized removals of neighbouring occupants are not substitutes" is false; they are
exact substitutes.

**And note the structural confound that made this predictable:** `{3,5,7}` is positionally dominant
over `{4,6,10}` in both branches (3<4, 5<6, 7<10). Comparing them tests "higher-ranked vs
lower-ranked", not "judge vs non-judge". This query's top-10 contains only three judge chunks and
they happen to be the higher-ranked triple, so the experiment as designed **cannot** separate the two
variables; it needed a same-size, same-depth non-judge triple, and one was available at ranks 2/4/6.

**What survives, and it is still worth having.** The honest statement is the one the doc already
makes 140 lines earlier at `:2042` and states better than the new paragraph does:

> A judge verdict about feature F outranks F's own spec on a query about F.

That is *structural* — equal weight 1.5, derivative subject matter — and it is checkable without any
counterfactual. It is a perfectly good input to ADR 0021. The counterfactual adds one thing to it:
**clause 1 on this query is three ranks deep, and the three occupants that happen to sit there are a
verdict about the same fix.** That is a statement about margin depth plus an unlucky coincidence of
tenancy, and it is what I would send to ADR 0021.

### Is the doc still readable?

Partly, and it got worse this round, though not badly. Measured: the card is now **2252 lines** with
**63 ⚠️ markers**, 11 of them in this ~300-line section. The numbered 1→4 narrowing at the end is
still the right shape and still rescues a reader who reaches it.

The specific new hazard is that the round-4 addition is the **most confidently worded paragraph in
the section** ("**Measured, and it does not**", "**specifically** load-bearing") and it is the one
that is wrong. Every genuinely uncertain claim around it now carries a hedge; the false one carries
none. A reader calibrating on typography will trust exactly the wrong line. The in-cell SUPERSEDED
banner was the right fix for the placebo table and I would apply the same treatment here.

The `.spec.md` split is now more justified than it was, but it is a MAY and it is not what is wrong
with this document.

### Standing disclosure

Accepted and re-confirmed: chunks under `%/memsearch-freshness/%` = 0; my verdicts are written to a
worktree path matching no `curated_docs` entry, so these rounds are not perturbing the measurement.
The cost is deferred to merge. Note that `CODING_MEMORY.md` is a different matter — see below.

## What could go wrong / what I'm unsure about

1. **`fail` — the doc asserts a specific, falsified claim, in bold, as the answer to a challenge.**
   Detailed above. Not hypothetical: 20/20 triples pass regardless of document.
2. **The falsified claim is also written into `CODING_MEMORY.md`** (`+64` this round): *"Refuting it
   strengthened the finding — the three verdict chunks are specifically load-bearing, not merely
   three of six occupants."* `CODING_MEMORY.md` **is** in the indexed corpus. A wrong conclusion in a
   feature doc is a wrong conclusion; a wrong conclusion in the memory index is one that will be
   retrieved and re-asserted later, by this system, on a query about this system. That is the worse
   of the two placements and it is the one I would fix first.
3. **The reasoning pattern, not the arithmetic, is the thing to correct.** "A judge predicted X; X is
   false; therefore my claim is strengthened" is a non-sequitur, and it is load-bearing here. The
   right move after falsifying a counterexample is to ask *what class the counterexample was drawn
   from* and test the class. That was one cheap script away — the artefact, harness and vectors were
   all still on disk, as this verdict demonstrates.
4. **The six-row table records no method.** Fifteen lines above it, the doc states its own rule
   (`:2149-2151`): *"Any new variant must be re-measured exactly rather than assumed."* Six new
   variants were added with no approximate/exact column, while the table immediately above them has
   one. (I checked both ways and they agree here — but the doc does not say, and its own rule says it
   must.)
5. **Success masking, unchanged:** `pyproject.toml:26` deselects the measurement marker, so
   `pytest -q` reports 74 green over a **2-of-5 red** retrieval bar. The green I ran says nothing
   about this diff.
6. **Context budget.** +351 lines vs `origin/main` into a 2252-line card that lands in the indexed
   corpus on merge — the corpus this document is about crowding.
7. **My own results, stated with their limits.** Single query (`git-guard-empty-index`), single
   pinned index state, the author's pinned vectors. I did not re-embed. Exact-method runs deleted
   from `chunks` and `chunk_vec` and rebuilt `chunk_fts`; if the author's exact method differed, our
   numbers could differ — but my as-is depth-10 reproduces their published listing score-for-score,
   and all six of their rows reproduce, so the harnesses agree where they overlap.
8. **What I am not disputing, again:** the headline retraction. Those three chunks were indexed at
   `2026-08-07T23:38:14+00:00`, before the query failed, so this instrument cannot assign the
   regression's cause. That conclusion is untouched by any of the above — and it is worth saying that
   today's finding makes it *stronger*, not weaker: if document identity does not matter at all, then
   the crowding story was never the regression's cause on either reading.

## What I'd double-check before merging

1. **Replace the "specifically load-bearing" paragraph.** Suggested wording, which is what my data
   supports: *"Challenged and tested. The round-3 prediction (ranks 4/6/10) is wrong — measured, it
   stays FAIL (1) — because rank 10 sits below the target and is inert, and because ADR 0014 at rank
   9 leapfrogs into any single freed slot. But the class-level version holds: exhaustively, all 15
   two-chunk removals from ranks 2–7 fail and all 20 three-chunk removals pass, with no dependence on
   document identity — including `{2,4,6}`, which contains no judge chunks. Clause 1 on this query is
   three ranks deep. The three verdict chunks are sufficient, and so is any other triple above the
   target."*
2. **Fix the `CODING_MEMORY.md` entry before it is indexed.** Same correction. This is the one with a
   half-life.
3. **Re-run it yourself before taking my word for it** — `/tmp/judge4/enum.py` and
   `/tmp/judge4/exact.py`, artefact still on disk. I would rather you falsify me than adopt this
   because a judge said so; that is the whole point of what you did to my round-3 claim.
4. **Add the method column to the six-row table**, per the doc's own `:2149-2151` rule.
5. **Say the artefact is expected to be destroyed rather than that it is unreachable** — it is
   reachable right now, and the derivation-not-the-file framing already carries the argument.
6. **Keep `:2042` as the claim ADR 0021 inherits** — "a judge verdict about F outranks F's own spec on
   a query about F" is structural, checkable, and survives everything measured this round.

Docs-only, nothing executes, and the branch is trivially revertible — this does not block a merge on
safety grounds. It blocks shipping the section as an input to ADR 0021's weighting decision, because
the sentence a reader will act on is the one that is false.

---

## Dimensions

| dimension | score | note |
|---|---|---|
| intent | pass | all three adopted round-3 points landed exactly as asked (n=1 downgrade, in-cell SUPERSEDED banner, frontmatter fixed with an explanatory note rather than a silent edit); both challenges were answered with measurement rather than deference |
| execution | concern | every reported number reproduces exactly on my independent replication (all six rows, approximate and exact), but the control set never varies document identity at fixed removal size, and the new six-row table carries no method column in a doc that mandates one at `:2149-2151` |
| trajectory | concern | running my prediction instead of conceding it is exactly right and I want to reinforce it; the step "the counterexample is false, therefore the claim is strengthened" is a non-sequitur, and the discriminating control was one cheap script away with the artefact still on disk |
| regression | pass | docs-only, +351/−2, no source, tests or config; my runs used copies and never opened the author's artefact for writing |
| context_budget | concern | 2252 lines, 63 ⚠️ markers file-wide and 11 in this ~300-line section; +351 lands in the indexed corpus on merge — the corpus this document is about crowding |
| traceability | pass | **round-3 concern retracted.** `memory.pinned.db` exists, 60116992 bytes, anchors verified by me exactly (8960 / 1025 / 2026-08-09T04:45:14+00:00); harness and pinned vectors present; I reproduced the published depth-10 listing score-for-score. Minor: no round-4 script preserved where rounds 2 and 3 kept theirs |
| success_masking | **fail** | six green rows conceal that removal *size* was never separated from document *identity*: exhaustively, 15/15 pairs from ranks 2–7 FAIL and 20/20 triples PASS with judge-chunk count 0–3 irrelevant, and `{2,4,6}` (zero judge chunks) gives PASS (2) under an exact FTS rebuild — the doc's bolded "specifically load-bearing" is false. `pytest -q` green over a 2-of-5 red retrieval bar persists |
| intent_drift | pass | scope is exactly the three adopted points plus the two refutations; no drive-by edits, no new deps |
| checkpoint | pass | single amended docs-only commit off `origin/main`; trivially revertible; artefacts live outside the repo and were not mutated |
| audit_trail | concern | frontmatter fixed and annotated rather than silently edited — the right pattern; but the falsified generalization is also committed to `CODING_MEMORY.md`, which **is** in the indexed corpus, so the wrong claim becomes retrievable rather than merely written |

**risk:** medium · **confidence:** high

### Concerns
- FALSIFIED CLAIM: the doc states in bold at `:2180-2184` that the three verdict chunks are "specifically load-bearing" and that "equal-sized removals of neighbouring occupants are not substitutes" - measured false on the author's own pinned snapshot under both the approximate and the exact (physical delete + vec0 delete + FTS rebuild) method
- Exhaustive control the author did not run: all 15 two-chunk removals from ranks 2-7 give FAIL (1) and all 20 three-chunk removals give PASS (2), with judge-chunk count (0/1/2/3) having no effect; `{2,4,6}` contains zero judge chunks and gives PASS (2)
- The operative variable is removal SIZE, not document identity - clause 1 on this query is three ranks deep, not one as my round 3 claimed and not document-specific as round 4 claims
- My round-3 example `{4,6,10}` was wrong because rank 10 sits BELOW the target at rank 8 and is inert, making it a two-chunk removal; the author's refutation of that example is correct and reproduces exactly, but refuting one counterexample does not confirm the hypothesis
- Structural confound: `{3,5,7}` is positionally dominant over `{4,6,10}` in both RRF branches (3<4, 5<6, 7<10), so that comparison tests higher-ranked vs lower-ranked, not judge vs non-judge; the query's top-10 holds only three judge chunks and they are the higher triple, so the design cannot separate the two variables
- The stated mechanism names the wrong half: the 200-candidate pool re-draw contributes at most 1.5/260 ~ 0.0058 and appears nowhere in the post-deletion top-8; the actual cause is differential per-branch rank gain plus a 5.2e-05 margin between ranks 8 and 9, where ADR 0014 leapfrogs into any single freed slot
- The falsified generalization is also committed to CODING_MEMORY.md, which IS in the indexed corpus - a wrong conclusion that will be retrieved and re-asserted, unlike the feature-doc line
- The round-4 paragraph is the most confidently worded in the section and the only one carrying no hedge, while every genuinely uncertain claim around it is hedged - a reader calibrating on typography trusts exactly the wrong line
- The six-row table records no approximate/exact method column, 15 lines below the doc's own rule at `:2149-2151` that any new variant must be re-measured exactly; the table immediately above it does have that column
- RETRACTED FROM ROUND 3: `memory.pinned.db` was never destroyed - it exists at 60116992 bytes in the session scratchpad and its anchors (8960 / 1025 / 2026-08-09T04:45:14+00:00) verify exactly; rounds 1 and 3 inferred destruction from an incomplete search, twice
- The doc's new availability paragraph slightly overstates in the safe direction: "nobody can re-run these tables" is currently false - I re-ran all of them today
- No round-4 measurement script preserved in the scratchpad, where rounds 2 and 3 kept round2_checks.py and round3_checks.py
- Feature card is 2252 lines with 63 warning markers, 11 in this ~300-line section; the optional .spec.md split remains untaken
- pyproject.toml:26 deselects the measurement marker, so `pytest -q` reports 74 passed / 23 deselected over a 2-of-5 red retrieval bar; it exercises nothing in this diff
- Local `main` stale at 8d79094; a tool defaulting to `main` diffs 34 files instead of 2
- Uncommitted verdicts.jsonl was already dirty on entry (doc-guard flagged it); my append adds to that
- NOT DISPUTED and strengthened by this round: the headline retraction stands - the three chunks were indexed at 2026-08-07T23:38:14+00:00, before the failure, so the instrument cannot assign the regression's cause; if document identity does not matter at all, the crowding story was never the cause on either reading
- The claim worth sending to ADR 0021 is the structural one already at `:2042` - a judge verdict about feature F outranks F's own spec on a query about F, at equal weight 1.5 with derivative subject matter - which needs no counterfactual at all
