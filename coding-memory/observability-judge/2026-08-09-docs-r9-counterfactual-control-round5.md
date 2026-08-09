# Observability verdict — `docs/r9-counterfactual-control` @ `77102c4` (round 5)

- **repo:** `memsearch-freshness` (worktree of `~/.claude`)
- **branch:** `docs/r9-counterfactual-control` → slug `docs-r9-counterfactual-control`
- **head_sha:** `77102c41e422eb8186e99692bc22e127e350700d` (amends `3592a63`, judged in
  `2026-08-09-docs-r9-counterfactual-control-round4.md`)
- **base:** `origin/main` @ `64d8acb`
- **stage:** implementation
- **ts:** 2026-08-09T17:43:40Z
- **filename note:** rounds 1–4 occupy the bare slug, `-round2`, `-round3`, `-round4`; suffixed
  `-round5` per this directory's convention.
- **diff:** 2 files, +406 / −2 vs `origin/main` — `docs/features/memsearch-freshness.md` (+327/−2),
  `CODING_MEMORY.md` (+81). Round-4 → round-5 delta is +55. No source, tests or config.
- **test command run by me:** `cd ~/.claude/memsearch && uv run pytest -q` → **74 passed, 23
  deselected in 0.38s**. Matches the caller's report. It exercises nothing in this diff.
- **what I ran beyond the tests:** re-ran the round-4 exhaustive enumeration on my own copy of the
  pinned snapshot (`/tmp/judge4/enum.py`) — **it reproduces the author's table exactly**. Then ran a
  *new* control the section never ran: a judge-**weight** sweep (`/tmp/judge4/weight.py`). The
  author's artefact was never opened for writing.

---

## Lead finding — `execution` is `fail`

**The withdrawal is right. The conclusion drawn *from* the withdrawal is wrong, in the opposite
direction, and it is the one sentence ADR 0021 will act on.**

The doc closes (`:2283-2288`):

> **No reweighting is supported by this evidence at all**, since document identity had no measured
> effect; reweighting anything moves the failure rather than removing it (`minus judges` costs
> `falsifier-base-pin` its pass)

Measured on the author's own pinned snapshot, the author's own pinned vectors, the real two-clause
criterion (`test_measurement_queries.py:163-164`), with the judge corpus defined exactly as the doc
defines it (observability-judge 1694 + compliance-judge 711 = **2405**):

```
judge weight   stale-phase-guard   falsifier-base-pin   git-guard-empty-index   verification-marker   phase-guard-hook
 1.5 (as-is)      PASS (4)             PASS (2)              FAIL (1)              FAIL (1)            FAIL (2)   -> 2 of 5
 1.4              PASS (4)             PASS (2)              FAIL (1)              FAIL (1)            FAIL (2)   -> 2 of 5
 1.2              PASS (4)             PASS (2)              PASS (2)              FAIL (3)            FAIL (3)   -> 3 of 5
 1.0              PASS (4)             PASS (2)              PASS (2)              FAIL (3)            FAIL (3)   -> 3 of 5
```

My `as-is` row matches the doc's published `as-is` column cell-for-cell, so the harness is calibrated
to theirs. **A judge weight of 1.2 takes R9 from 2 of 5 to 3 of 5 and nothing regresses** — the two
remaining failures each *gain* belonging hits (1→3 and 2→3). That is a reweighting supported by this
evidence, produced from this evidence, on this snapshot.

And note the method advantage: a weight change **needs no FTS rebuild and no approximation at all**.
It touches nothing in the index; it is a post-fusion multiplier. It is the cheapest exact control in
this whole section, and it is the only one that was never run.

**The inferential slip.** Deletion-invariance to document identity does **not** imply
weight-invariance, because a weight change is *defined by* identity. The enumeration shows that
removing *any* three chunks above the target works — which means an intervention that demotes three
of those six slots works, and a judge-weight cut is exactly such an intervention, because the judge
chunks happen to hold three of the six. What the enumeration destroys is the **narrative** ("judge
verdicts semantically crowd out the specs they grade"); it leaves the **remedy** untouched. The doc
threw both away.

The parenthetical is the tell: `minus judges` is a deletion — weight **0**. Generalising "weight 0
costs `falsifier-base-pin`" to "reweighting anything moves the failure" is a claim about the whole
curve from one endpoint, and the interior point at 1.2 falsifies it.

This is the same species of error the section spent 300 lines cataloguing — a conclusion one
inferential step past the measurement — now running in the *conservative* direction. The section's own
rule (`:2252`, "Stated at the strength the evidence supports, no further") is violated by
understatement. That is still a violation, and here it is the expensive one, because it forecloses the
decision ADR 0021 exists to make.

## What was changed

Think of a doorway six people deep. Round 4 proved that *who* those six people are does not matter —
pull any three out and your person gets through. The author correctly wrote that down and killed the
story that the three "judges" in the queue were special. But then they wrote: *since it doesn't matter
who they are, there's nothing to do about them.* That doesn't follow. Asking three specific people to
step back is still a way of clearing three slots — and when I actually asked (lowered the judge
weight), the doorway cleared and **nobody else got stuck**, which is better than the earlier plan of
throwing all the judges out of the building.

Concretely this round: the round-4 finding was adopted in full and independently re-verified;
`CODING_MEMORY.md` was fixed first as asked; both headings, the closing synthesis and the ADR-0021
inheritance were rewritten; the "judge crowding" reading was withdrawn rather than softened; and a
fourth narrowing was added naming the non-sequitur.

## Does it do what you wanted?

Yes on the adoption, and I want to be clear about that before the criticism: **you re-ran my
enumeration instead of taking my word, and it reproduces exactly.**

```
15 pairs  from ranks 2-7 -> FAIL (1)  15/15
20 triples from ranks 2-7 -> PASS (2) 20/20   including (2,4,6), judge-chunks=0
3/5/7 PASS(2) | 4/6/10 FAIL(1) | 4/6 FAIL(1) | 2/4 FAIL(1) | 4 FAIL(1) | 9/10 FAIL(1)
```

The judge-count breakdowns in your table (`0→0/3, 1→0/9, 2→0/3` and `0→1/1, 1→9/9, 2→9/9, 3→1/1`) are
combinatorially correct and match my run. The structural survivor checks too: `2026-08-03-fix-git-guard-empty-index.md`
is **639** lines, `git-guard-empty-index.md` is **375**, and `config.json:17` gives `curated_doc: 1.5`
to both. That claim inherits cleanly.

### Q1 — "Is the withdrawal complete, or does some sentence still smuggle in a document-identity story?"

**Not complete. Four survive**, and one of them is a bolded sub-heading.

1. **`:2042-2047`, the paragraph directly under the depth-10 listing** — the most quotable block in
   the section. It still reads: *"what the control establishes is that here it **has** cost a
   verdict. See the minimal-cause section below before generalising it: measured, this is one
   document on one query, not a property of the class."* Three faults in six lines: the control
   establishes no such thing; "one document on one query" is the withdrawn round-3 framing; and
   **"the minimal-cause section" no longer exists** — you renamed that heading this round, so the
   pointer now dangles.
2. **`:2093`, a bolded sub-heading** — *"**1. Size-matched placebo — the effect is subject-matter,
   not dilution.**"* It asserts as a heading precisely what `:2194` withdraws.
3. **`:1856-1862`** — a *second, untagged* copy of the falsified claim: *"passes only while this
   file's own `## Verification` section is in the corpus — remove it and R9 is **1 of 5**."* You
   tagged the first copy at `:1829-1834` with a clean ⚠️ correction. This one is 25 lines below it,
   it is itself already a ⚠️ paragraph (so it reads as vetted), and it is the paragraph attached to
   a recorded **user decision**. Corrected in one place, live in the other.
4. **`CODING_MEMORY.md:4636-4638`** — *"(3) What holds: … the class-level claim … is **untested** —
   one document, one query."* Presented as "what holds", present tense.

On (4), the retrievability arithmetic matters and is checkable: `chunk.py:13` sets
`MAX_SECTION_CHARS = 2000`, the session-48 entry is ~7.6k characters, so it will index as roughly
four chunks. **Line 4636 and its correction at 4672 will not be in the same chunk.** `CODING_MEMORY.md`
is in `curated_docs` at weight 1.5 (`config.json:11,17`) — a retrieval can surface the stale framing
alone. That is the exact hazard round 4 named; you fixed the headline, which was the important half,
but the intermediate survived.

### Q2 — "Does the section support what it says ADR 0021 inherits?"

**Partly. The structural observation, yes — verified. The reweighting claim, no — measured false**
(lead finding). And `:2042` contradicts the closing from inside the same section: one paragraph says
the control established that a judge verdict cost R9 a verdict, the closing says no document is
implicated. A reader who retrieves one chunk gets whichever one the ranker hands them.

What I would send to ADR 0021 instead: *the structural fact (639-line verdict, 375-line spec, equal
weight 1.5) needs no counterfactual and stands. There is no measured **subject-matter** effect, so
there is no evidence-based case for singling the judge class out on crowding grounds. Separately and
independently: a judge weight of ~1.2 is a measured candidate that takes R9 from 2/5 to 3/5 on the
pinned state with no R9 regression — checked exactly, since a weight change needs no re-index. It has
not been checked against the 16 golden cases or everyday retrieval, and a global weight cut reaches
far beyond R9, so it is a candidate to evaluate, not a change to make. And the regression's cause is
still unassigned.*

### Q3 — "Five narrowings in, is a reader landing on what is true, or on the archaeology?"

**On the archaeology, and I'll name the cuts since you asked for them.** Measured: the card is **2290
lines** with **65 ⚠️ markers**; the section is **314 lines** holding **11** of them. Roughly 200 of
those 314 lines are apparatus built to defend a conclusion that no longer exists, and the correction
lands at line ~2171 — a reader hits ~195 lines of evidence for the dead story first.

Two things already help a lot and should stay: the **heading now states the conclusion** ("no document
is implicated"), and the numbered 1→5 narrowing still rescues anyone who reaches the end.

Concrete cuts, in order of value:

- **Collapse `#### Two controls on the control` (`:2088-2170`, ~84 lines, 4 ⚠️, 2 tables) to ~10
  lines.** Both controls exist to defend judge-crowding against a dilution alternative. Nobody now
  asks that question, and both results already reappear as single rows in your collapse table at
  `:2200-2208`. Keep exactly two sentences of it, because they are still live method rules: *a
  size-matched random deletion does not recover the query (exact, n=1 seed); it does perturb
  `falsifier-base-pin`, so the candidate-drop approximation is not verdict-safe — re-measure any new
  variant exactly.* **~70 lines and 4 markers gone.**
- **Move the three artefact/hash/availability ⚠️ paragraphs (`:2063-2085`, ~22 lines) to a
  "Reproduction" footnote at the end of the section.** That is method hygiene, not finding, and it
  currently sits between the evidence and the conclusion.
- **Lift the corrected conclusion to the top.** Put the `:2194` + `:2210-2220` block (six lines: no
  identity effect, margin three ranks deep, structural survivor) immediately under the `###` heading,
  before any table. Everything after it then reads as *how we got here*, which is what it is.
- **Delete your own superseded reasoning where a ⚠️ is doing the work of a delete.** You offered
  this and I'd take it: `:2171-2185` (the six-row table plus its non-sequitur autopsy) can shrink to
  two sentences, because the exhaustive table at `:2188-2192` strictly supersedes it. Git holds the
  history; the card does not need to.

Net: ~314 → ~210 lines, 11 → ~6 markers, conclusion first. The `.spec.md` split is still a MAY and
still not the problem.

### Standing disclosure

Accepted and re-confirmed against the pinned snapshot: `%/memsearch-freshness/%` = 0 chunks; my
verdicts are written to a worktree path matching no `curated_docs` entry, so these rounds do not
perturb the measurement. Deferred to merge.

## What could go wrong / what I'm unsure about

1. **`fail` — the closing reweighting claim is measured false**, and it is the sentence ADR 0021
   inherits. Detail above. Not hypothetical: weight 1.2 → 3 of 5, no regression, exact method.
2. **The one intervention under decision was never controlled.** The section ran five deletion
   variants, a size-matched placebo, an exact FTS rebuild, and a 35-cell exhaustive enumeration —
   and never once varied the parameter ADR 0021 will change. A weight sweep is five lines of code and
   needs no re-index.
3. **Four surviving document-identity sentences**, listed under Q1. The `:2042` one is the worst
   placement in the document (directly under the depth-10 block) and carries a dangling cross-
   reference to a heading you renamed.
4. **`CODING_MEMORY.md:4636` will index as its own chunk**, separated from its correction. Weight
   1.5, retrievable, stale framing stated as "what holds".
5. **No round-5 script preserved.** Rounds 2 and 3 left `round2_checks.py` / `round3_checks.py` in
   the scratchpad; rounds 4 and 5 left nothing. The doc says the enumeration was "confirmed by
   re-running it here" — I independently verified the numbers are right, so the claim is true, but
   the record of the run is gone. Given this section's whole thesis is derivation-over-artefact, the
   derivation of *this* table is not written down either.
6. **Success masking, unchanged:** `pyproject.toml:26` deselects `measurement` and `golden`, so
   `pytest -q` reports 74 green over a **2-of-5 red** retrieval bar. The green I ran says nothing
   about this diff.
7. **Context budget.** 2290 lines, 65 markers, +406 into the indexed corpus at weight 1.5 — the
   corpus this document is about crowding.
8. **Limits on my own weight result, stated plainly.** One pinned snapshot, five queries, the
   author's pinned vectors, judge corpus = both judge directories by path prefix. I did not re-embed
   and I did not run the 16 golden cases. A global weight cut affects every query in the system, not
   just R9 — I am reporting that the doc's "no reweighting is supported" is false, **not** that 1.2
   should be adopted.
9. **`:2019` minor** — "`minus judges` is the only variant that moves anything, and **the mechanism**
   is visible at depth 10" still implies a judge-specific mechanism. True as stated about the
   variants tested; misleading now.
10. **Not disputed, and still the most important line in the section:** the three chunks were indexed
    `2026-08-07T23:38:14+00:00`, before the query failed, so this instrument cannot assign the
    regression's cause. Untouched by everything above.

## What I'd double-check before merging

1. **Rewrite `:2283-2288`.** Suggested, and it is what my data supports: *"What ADR 0021 inherits: a
   structural observation needing no counterfactual (639-line verdict vs 375-line spec at equal
   weight 1.5); no measured subject-matter effect, so no crowding-based case for singling out the
   judge class; but a **weight** change is identity-selective by construction and was never
   controlled here — a judge weight of ~1.2 takes R9 from 2/5 to 3/5 on the pinned state with no R9
   regression, exactly measured, and needs checking against the golden set before adoption. Deleting
   the judges outright (weight 0) does cost `falsifier-base-pin` its pass; a partial cut does not.
   And the regression itself is still unexplained."*
2. **Run the weight sweep yourself before taking my word for it** — `/tmp/judge4/weight.py`, artefact
   still on disk, same standard you applied to my round-4 claim. I would rather you falsify me.
3. **Sweep the four residuals** (`:2042-2047`, `:2093`, `:1856-1862`, `CODING_MEMORY.md:4636-4638`),
   and fix the dangling "minimal-cause section" pointer.
4. **Do the readability cuts in Q3**, at minimum the `Two controls on the control` collapse and
   lifting the conclusion above the tables.
5. **Preserve the enumeration and weight scripts** as a derivation block in the doc, per this
   section's own standard.
6. Cosmetic: `:2285-2286` has a ragged wrap left over from the edit.

Docs-only, nothing executes, trivially revertible — this does not block a merge on safety grounds. It
blocks shipping the section as ADR 0021's input, because the closing sentence forecloses the decision
on evidence that says the opposite.

---

## Dimensions

| dimension | score | note |
|---|---|---|
| intent | pass | the round-4 finding was adopted in full and, correctly, re-run rather than accepted — I reproduce the enumeration exactly (15/15 FAIL, 20/20 PASS, judge count irrelevant); `CODING_MEMORY.md` fixed first as asked; both headings, closing synthesis and ADR inheritance rewritten; withdrawn rather than softened; fourth narrowing added |
| execution | **fail** | the closing claim ADR 0021 inherits — "No reweighting is supported by this evidence at all… reweighting anything moves the failure" — is measured false on the author's own pinned snapshot with the author's own vectors and the real two-clause criterion: judge weight 1.5→1.2 takes R9 from 2/5 to 3/5 with no query regressing. Deletion-invariance to identity does not imply weight-invariance, because a weight change is defined by identity |
| trajectory | concern | method is exemplary (re-ran instead of adopting, withdrew instead of reframing, named its own non-sequitur); but the step "identity had no effect ⇒ no reweighting supported" is itself a non-sequitur of the type the section had just finished cataloguing, and the discriminating control is a five-line weight sweep needing no re-index |
| regression | pass | docs-only, +406/−2, no source, tests or config; my runs used my own copy and never opened the author's artefact for writing |
| context_budget | concern | 2290 lines, 65 ⚠️ file-wide, 11 in a 314-line section of which ~200 lines are apparatus for a withdrawn conclusion; +406 lands in the indexed corpus at weight 1.5 on merge — the corpus this document is about crowding |
| traceability | pass | pinned artefact present and verified (8960 chunks; judge corpus 1694+711=2405 exactly as the doc states); 639/375 line counts and `config.json:17` weight 1.5 both confirmed; published `as-is` column reproduces cell-for-cell. Minor: no round-5 script preserved where rounds 2 and 3 kept theirs, and the new table's derivation is not written down |
| success_masking | concern | a 35-cell exhaustive enumeration reads as complete coverage while varying only *deletion*; the identity-selective intervention actually under decision (weight) was never controlled, and it is the one that recovers the query without the deletion's cost. `pytest -q` green over a 2-of-5 red bar persists (`pyproject.toml:26`) |
| intent_drift | pass | scope is exactly the adopted round-4 finding across the two files; no drive-by edits, no new deps, no source touched |
| checkpoint | pass | single amended docs-only commit off `origin/main` @ `64d8acb`; trivially revertible; artefacts live outside the repo and were not mutated |
| audit_trail | concern | headline corrections landed in the right file first; but four document-identity sentences survive uncorrected, including a bolded sub-heading at `:2093`, a dangling cross-reference to a renamed section at `:2046`, an untagged duplicate of a falsified claim at `:1856-1862` attached to a user decision, and `CODING_MEMORY.md:4636` which will index as its own chunk (`chunk.py:13`, 2000 chars) separated from its correction 36 lines later |

**risk:** medium · **confidence:** high

### Concerns
- FALSIFIED CLOSING CLAIM: `:2283-2288` states "No reweighting is supported by this evidence at all" and "reweighting anything moves the failure rather than removing it" - measured false on the author's own pinned snapshot: judge weight 1.5 -> 1.2 takes R9 from 2 of 5 to 3 of 5 (git-guard-empty-index FAIL(1) -> PASS(2)) with no query regressing, and the two remaining failures each gain belonging hits
- The inferential slip: deletion-invariance to document identity does not imply weight-invariance, because a weight change is defined BY identity; the enumeration destroys the crowding narrative but leaves the remedy untouched
- "minus judges costs falsifier-base-pin its pass" is a deletion (weight 0) generalised to the whole curve; the interior point at 1.2 keeps falsifier-base-pin at PASS (2)
- The one intervention ADR 0021 will actually decide (a weight change) was never controlled, despite being the cheapest exact control available - it needs no FTS rebuild and no approximation, since it is a post-fusion multiplier
- RESIDUAL 1: `:2042-2047` still says "what the control establishes is that here it **has** cost a verdict" and "measured, this is one document on one query" - the withdrawn claim, in the most quotable position in the section, directly under the depth-10 listing
- RESIDUAL 1b: the same paragraph points to "the minimal-cause section below", a heading renamed this round - the cross-reference now dangles
- RESIDUAL 2: `:2093` is a bolded sub-heading asserting "the effect is subject-matter, not dilution", which `:2194` withdraws
- RESIDUAL 3: `:1856-1862` is a second, untagged copy of the falsified "remove it and R9 is 1 of 5" claim, 25 lines below the copy that WAS tagged at `:1829-1834`; it is itself a warning paragraph so it reads as vetted, and it is attached to a recorded user decision
- RESIDUAL 4: `CODING_MEMORY.md:4636-4638` still states "(3) What holds: ... one document, one query" in present tense; with MAX_SECTION_CHARS=2000 (chunk.py:13) and a ~7.6k-char entry it indexes as ~4 chunks, so it will separate from its correction 36 lines later, in a file at curated_doc weight 1.5
- VERIFIED AND ADOPTED CORRECTLY: I re-ran the round-4 enumeration and reproduce it exactly - 15/15 pairs FAIL, 20/20 triples PASS, judge-chunk count 0-3 irrelevant, including (2,4,6) with zero judge chunks; the author re-ran rather than adopting, which is the right standard
- VERIFIED: the surviving structural claim checks out exactly - 639-line verdict, 375-line spec, curated_doc weight 1.5 for both (config.json:17); judge corpus 2405 = observability-judge 1694 + compliance-judge 711; pinned snapshot 8960 chunks
- Readability: 2290 lines, 65 warning markers; the 314-line section holds 11 of them and ~200 of its lines are apparatus defending a withdrawn conclusion, with the correction landing at ~:2171. Recommended cuts: collapse `Two controls on the control` (:2088-2170, ~84 lines, 4 markers) to ~10 lines since both results already appear as rows in the collapse table; move the three artefact/hash/availability warnings (:2063-2085) to a Reproduction footnote; lift the corrected conclusion above the tables; shrink :2171-2185 which the exhaustive table supersedes
- No round-5 script preserved in the scratchpad where rounds 2 and 3 kept round2_checks.py and round3_checks.py; the new table's derivation is not written into the doc either, against this section's own derivation-over-artefact standard
- pyproject.toml:26 deselects both the measurement and golden markers, so `pytest -q` reports 74 passed / 23 deselected over a 2-of-5 red retrieval bar; it exercises nothing in this diff
- `:2019` minor: "minus judges is the only variant that moves anything, and the mechanism is visible at depth 10" still implies a judge-specific mechanism
- Limits on my weight result: one pinned snapshot, five queries, author's pinned vectors, no re-embedding, golden set not run; a global weight cut reaches beyond R9, so this is a candidate to evaluate, not a change to make
- Cosmetic: ragged line wrap at :2285-2286 left over from the edit
- NOT DISPUTED: the headline retraction stands - the three chunks were indexed 2026-08-07T23:38:14+00:00, before the query failed, so the instrument cannot assign the regression's cause
- Uncommitted verdicts.jsonl was already dirty on entry (doc-guard flagged it); my append adds to that
