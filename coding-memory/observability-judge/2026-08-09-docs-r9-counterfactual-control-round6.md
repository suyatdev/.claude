# Observability judge — round 6

- **repo:** `memsearch-freshness` (worktree of `~/.claude`)
- **branch:** `docs/r9-counterfactual-control`
- **head_sha:** `f0cbde56c47eb0b8108d842bfc3216ba6c5315db`
- **base:** `origin/main` @ `64d8acb1b228a224726128a28e86cd904855a4c9`
- **stage:** implementation
- **ts:** 2026-08-09T18:16:53Z
- **judged delta:** full diff vs base (8 files, +1693/−2), attention weighted on `77102c4..HEAD`
  (+1298/−11) — the part no prior round has seen.
- **test command:** `cd ~/.claude/memsearch && uv run pytest -q` → **74 passed, 23 deselected in
  0.41s**, run by me. Exercises nothing in this diff; the diff is documentation only.

---

## What was changed

Think of this branch as a **lab notebook for one stubborn search bug**, not as working code. Nothing
that runs was touched — no source, no config, no tests. What changed is the write-up.

Three things landed:

1. A **"read this first" summary box** was bolted to the top of a very long investigation section, so
   a reader lands on the four things that are actually true before wading through the five wrong
   turns that produced them.
2. The **closing conclusion was reversed**. The previous version said "no reweighting is supported by
   this evidence at all." Round 5 said that was wrong. The author went and *measured* it instead of
   just accepting the correction, and found that turning one knob down (judge documents from weight
   1.5 to 1.2) takes the retrieval scorecard from 2-of-5 passing to 3-of-5 with nothing getting
   worse. That table is new.
3. **All five previous judge verdicts were committed**, including the four places where those judges
   were factually wrong and got refuted by measurement.

## Does it do what you wanted?

**Mostly yes, and the reasoning is the best part of it.** Round 5's `execution: fail` — a closing
paragraph that stated a falsified claim — is genuinely fixed, and fixed the right way: the author
re-ran the experiment before believing the judge who raised it. The diagnosis of *why* the old claim
was wrong is correct and I verified the mechanism it rests on. `search.py:80` reads

```python
r["score"] = round(base_score * r.pop("weight"), 6)
```

— the weight really is a plain multiplier applied *after* the ranked lists are fused, so a weight
sweep does not disturb which candidates were retrieved. That makes the sweep an exact measurement
with no re-index, exactly as the doc claims. The structural claim also checks out: the judge verdict
is 639 lines, the spec it grades is 375, and `config.json:17` gives both `curated_doc` **1.5**.

Three of round 5's five residuals were cleared (the "has cost a verdict" over-claim, the dangling
cross-reference, the un-marked placebo heading).

**But the headline recommendation is ambiguous in a way that could bite.** See below — it is the one
finding I would not let through unaddressed.

## What could go wrong / what I'm unsure about

**1. The one actionable result cannot be applied the way it is written.** The doc says

> ⇒ **`curated_doc` weight 1.2 for judge verdicts takes R9 from 2 of 5 to 3 of 5 with no
> regression.** (`:2326`)

There is no such knob. `config.json:17` is
`{"curated_doc": 1.5, "repo_doc": 1.2, "transcript_digest": 1.0, "archive_doc": 1.0}` — weights are
keyed by **source type**, and `curated_doc` covers *all* of `~/.claude/coding-memory`,
`~/.claude/docs`, `PORTS.md` and `CODING_MEMORY.md` (`config.json:11`). The value is baked into each
row at index time (`index.py:169` → `db.py:75`).

And a blanket `curated_doc → 1.2` **provably cannot produce the measured result.** Every one of the
ten rows the doc prints at `:2046-2055` is `curated_doc`. Since `score = rrf × weight`, scaling them
all by the same 0.8 leaves their order among themselves untouched, and only lets `repo_doc` /
`archive_doc` chunks rise *past* them — pushing the target at rank 8 further down, never up. So the
sweep must have scoped judge chunks *specifically*, which today needs a new weight class or source
type plus a re-index or weight backfill. **The doc never says which population it re-weighted.** A
junior developer told "1.5 → 1.2" would edit `config.json:17`, demote every spec and ADR in the
corpus, and not reproduce the number.

**2. Two claims round 5 flagged as falsified are still live, untagged, in the indexed corpus.**

- `:1857-1863` — "remove it and R9 is **1 of 5**" — a second copy of a claim that *is* correctly
  marked superseded 25 lines earlier at `:1830-1835`. This copy has no marker.
- `CODING_MEMORY.md:4649` still says the class-level claim is "**untested** — one document, one
  query" (the enumeration tested it and found it null), and `:4655-4657` still says "retuning moves
  the failure rather than removing it" — which the new 1.2 sweep directly contradicts.

This matters more than ordinary doc staleness because `CODING_MEMORY.md` *is* the indexed corpus at
`curated_doc` 1.5, and `chunk.py:13` sets `MAX_SECTION_CHARS = 2000` — so those paragraphs are
retrieved as standalone chunks, detached from the corrections sitting elsewhere in the file. The new
corrective paragraph at `:4632-4641` is a *different chunk* from the stale one at `:4655`.

**3. A supersede marker points the wrong way.** `:2131` reads "The three columns **below** are
SUPERSEDED" — the placebo columns are **above**, at `:2123-2129`. A reader following that pointer
lands in the FTS section. This is exactly the "trap" the author asked about, and it is real.

**4. The new sweep table repeats the reporting weakness the section itself diagnosed.** At `:2069`
the doc warns "Dropping the judges is not free, **and the count would hide it**" — and under exact
measurement, `minus judges` eroded `stale-phase-guard-rule-text` from PASS (4) to PASS (3)
(`:2160`). The sweep table's "anything regress?" column is **verdict-level only**, with no per-target
hit counts for the two already-passing targets. A margin erosion of exactly that shape would print
as "no". The doc's own rule at `:2173` ("any new variant must be re-measured exactly") also has no
method column here — the mechanism does make it exact, but the table does not say so.

**5. Merging this PR enlarges the very population the section measures.** The five verdict files are
~97.7k characters — roughly **48 chunks** at `MAX_SECTION_CHARS = 2000`, about **+2% of the
2405-chunk judge corpus**. In the worktree they sit outside every curated root, so they are not
indexed now; once merged to `~/.claude/coding-memory/observability-judge/` they index at
`curated_doc` **1.5**. R9's margin on the query under study is **three ranks deep**. So the monitor's
own re-check trigger will next fire against a corpus this PR changed. **I have not measured whether
it moves R9** — I am stating a mechanism, not a result. The doc acknowledges self-perturbation for
the feature card (`:1970-1973`) but not for the verdict commit, which is the larger addition.

**6. The summary box slightly over-states, in two places.** Claim 3 asserts the weight change "does
help" with no hedge; the body's own caveat — "a lead to re-confirm rather than a tuning to apply
blind" — is 340 lines away at `:2333`. Claim 3 also calls it "the only actionable result", while
`:2331` sends *two* items to ADR 0021. Claim 4 generalises a three-rank margin measured on **one**
query into a statement about "R9's clause 1"; the body scopes it to that query at `:2236`. Both are
mild, and both are the same species of over-reach the section exists to document.

**7. What I could not verify.** The sweep's numbers themselves. The pinned snapshot is
session-scoped and the live index has moved to 9016 chunks, so the table is unreproducible by me —
the doc says this plainly and honestly (`:2099-2106`), which is the right call, but it means the
headline number rests on the author's word. I verified the *mechanism* that makes the sweep sound;
I did not verify the *result*.

**8. Pre-existing, unchanged:** `pyproject.toml:26` deselects the `measurement` marker, so the green
`74 passed` I ran sits over a 2-of-5 red retrieval bar and touches nothing in this diff. The feature
card is now **2341 lines with 67 warning markers**, 13 of them in this 363-line section; the optional
`.spec.md` split remains untaken.

## What I'd double-check before merging

1. **State how the sweep was scoped**, in one sentence, next to the table — "judge-verdict chunks
   only, set to 1.2 via …". Without it the section's only actionable output is un-actionable, and
   ADR 0021 inherits an instruction that cannot be followed. This is the one I would block on.
2. **Add the missing supersede marker at `:1859`** and fix the two stale paragraphs in
   `CODING_MEMORY.md` (`:4649`, `:4655-4657`) — they are in the retrieval path.
3. **Change "below" to "above" at `:2131`.** One word.
4. **Add per-target hit counts to the sweep table**, or say explicitly that margins were not
   recorded — the doc's own `:2069` warning demands it.
5. **Note in the doc that merging adds ~48 judge chunks at weight 1.5** before the monitor's
   re-check trigger fires, so the next R9 reading is not comparable to the pinned baseline.
6. Optionally, pull the "re-confirm before applying" hedge from `:2333` up into box claim 3.

---

## Dimension table

| dimension | score | why |
|---|---|---|
| `intent` | **pass** | The stated goal — correct round 5's falsified closing by measuring the interior point, and lead with the conclusion — was met, and met by re-measuring rather than by adopting the judge's claim. |
| `execution` | **concern** | Round 5's `fail` is fixed. Remaining: the 1.2 recommendation is not expressible in the config surface it names; two round-5 residuals persist; `:2131` points the wrong direction; the sweep table omits margins. Test command runs green but exercises nothing here. |
| `trajectory` | **pass** | Best dimension. Correctly identified that deletion-invariance to identity ≠ weight-invariance (deletion samples only the `weight = 0` endpoint), verified the mechanism before trusting it, and kept "the narrative was withdrawn" separate from "the remedy survives". Reasoning, not luck. |
| `regression` | **concern** | No code touched, tests green. But merging adds ~48 judge chunks at `curated_doc` 1.5 to the corpus the section measures, immediately before R9's re-check trigger; and two falsified claims stay retrievable. |
| `context_budget` | **concern** | Feature card 2341 lines / 67 markers, +1220 lines of verdicts into a curated root at weight 1.5. Not always-on rule context, but it is retrieved context; the `.spec.md` split remains untaken across six rounds. |
| `traceability` | **concern** | Second round flagged: no sweep derivation, no preserved script, no statement of the re-weighted population, no method column. The omission is now demonstrably material rather than cosmetic. |
| `success_masking` | **concern** | `74 passed / 23 deselected` over a red 2-of-5 retrieval bar; the sweep table's verdict-only "no regression" column is the same count-hides-the-margin shape the doc diagnoses at `:2069`; stale claims retrievable detached from their corrections. |
| `intent_drift` | **pass** | Docs-only, no dependencies, no drive-by edits. The verdict commit is in scope as audit trail. |
| `checkpoint` | **pass** | Two clean, well-scoped commits; clean working tree; base recorded; stale frontmatter `branch:` corrected to `none` with a note explaining the three-session drift. Trivially revertable. |
| `audit_trail` | **pass** | Exemplary. Five verdicts committed in full *including* four places the judges were refuted by measurement; commit messages state the correction chain; ADR 0021 named as owner with a blocking open item. |

**risk:** low — documentation only, nothing running can break, fully revertable, and the one
recommendation carries its own "re-confirm before applying" hedge in the body.
**confidence:** high — I ran the tests, read the full diff, and independently verified the weight
mechanism (`search.py:80`), the config schema (`config.json:11,17`), the chunk size
(`chunk.py:13`), the file lengths (639/375) and every residual by grep. The one thing I could **not**
verify is the sweep table's numbers, because the pinned snapshot is gone.
