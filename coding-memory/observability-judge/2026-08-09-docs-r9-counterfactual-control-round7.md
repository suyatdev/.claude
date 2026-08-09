# Observability judge — round 7

- **repo:** `memsearch-freshness` (worktree of `~/.claude`)
- **branch:** `docs/r9-counterfactual-control`
- **head_sha:** `1c89fbe9e2e84b255c0fec9d68e7cb98e799c4ae`
- **base:** `origin/main` @ `64d8acb1b228a224726128a28e86cd904855a4c9`
- **stage:** implementation
- **ts:** 2026-08-09T19:57:10Z
- **judged delta:** `f0cbde5..HEAD` — 1 commit, 4 files, +199/−3. Prior six rounds not re-litigated.
- **test command:** `cd ~/.claude/memsearch && uv run pytest -q` → **74 passed, 23 deselected in
  0.36s**, run by me. Documentation-only diff; the suite exercises nothing in it.

**Method note.** Rather than reading the markers and judging whether they *look* navigable, I ran the
project's real chunker (`memsearch.chunk.chunk_doc`) over both changed documents and asked whether
each correction shares a retrieval chunk with the claim it corrects. That converts the author's third
question from an opinion into a measurement. Results are in the table below.

---

## What was changed

This is still a **lab notebook for one stubborn search bug**, not working code. Nothing executable was
touched. Round 6 said the notebook's one useful recommendation — "turn judge-document weight down from
1.5 to 1.2" — could not actually be carried out as written. This commit responds to that in four
places, and pushes back on a fifth.

The heart of it: the notebook had a **knob that doesn't exist**. It read like a config edit. It isn't.
The weight dial is keyed by *kind of document*, and judge verdicts share one bucket with every spec and
ADR in the corpus — so setting that bucket to 1.2 would demote everything at once and reproduce
nothing. The commit adds a stop sign saying exactly that, and names the concrete engineering move
required first (give judge verdicts their own `source_type`, the way `CODING_MEMORY.md` already got
one). Plus: a withdrawn claim gets tagged, a stale paragraph in the session archive gets corrected, a
pointer that said "below" now says "above", and a column that could hide a regression is labelled as
such.

## Does it do what you wanted?

**Yes — and three of the four fixes are verifiably real rather than cosmetic.** I checked the
mechanism the whole argument rests on and it holds: `search.py:80` is

```python
r["score"] = round(base_score * r.pop("weight"), 6)
```

a plain multiplier applied *after* fusion, and every one of the ten ranks printed at `:2056-2065` is
`curated_doc` (10/10, counted). So a uniform multiplier scales them equally and **cannot reorder
them** — which independently proves the sweep must have re-weighted judge chunks specifically. The new
paragraph's central conclusion is correct.

**On the round-6 claim you declined: you are right, and round 6 was wrong.** I read the text as it
stood at `f0cbde5`, which is the fair test. The `⇒` line said *"`curated_doc` weight 1.2 **for judge
verdicts**"* and the sweep table's header column was *"judge weight"*. Round 6's sentence — "the doc
never says which population it re-weighted" — is false on the text. The real defect was the absent
knob, which round 6 also found and stated correctly in the same paragraph. Leaving the wrong clause
standing in the round-6 file instead of quietly editing it is the right call for a calibration record.

**Did the fixes discharge, or are they cosmetic?** Measured, not eyeballed:

| fix | claim → its correction | same retrieval chunk? |
|---|---|---|
| #2 `:1859` SUPERSEDED | L1859 → L1866 | **chunk 87 / chunk 87 ✓** |
| #4 "below"→"above" | L2136 table → L2141 marker | **chunk 102 / chunk 102 ✓** |
| #1 knob paragraph | L2341 `⇒` line → L2348 | **chunk 110 / chunk 110 ✓** |
| #3 archive correction | L4656 → L4657 tag | **chunk 281 / chunk 281 ✓** |

All four land in the same chunk as what they correct, so they survive retrieval, not just linear
reading. Fix #4 is better than asked: the heading at `:2123` carries an inline `⚠️ SUPERSEDED`, so any
hit inside chunk 102 sees a warning in its first line. **Tagging-in-place is working, and the several
markers in one section are navigable rather than noise** — each is adjacent to its own claim, not
pooled in an errata list.

## What could go wrong / what I'm unsure about

**1. The new knob paragraph gets its own bucket list wrong — and the error is one sentence from the
evidence that refutes it.** `:2342-2343` reads:

> `config.json:17` keys `weights` by *source type*, and `curated_docs` is a single bucket holding judge
> verdicts, feature docs, ADRs, `PORTS.md` and `CODING_MEMORY.md` alike.

`CODING_MEMORY.md` is **not** in that weight bucket. `index.py` carves it out by filename:

```python
ARCHIVE_FILENAME = "CODING_MEMORY.md"                                    # :46
    return "archive_doc" if path.name == ARCHIVE_FILENAME else default   # :58
```

so its `source_type` is `archive_doc` at weight **1.0**, not `curated_doc` 1.5. **This same file says
so, twice**: at `:490` ("`archive_doc` tier at **1.0**") and in its own Gherkin at `:1006-1014` ("Given
CODING_MEMORY.md is indexed as archive_doc … Then their source_type is archive_doc"). The next sentence
of the new paragraph then cites `index.py:44-51` as the precedent to follow — and that precedent *is
the carve-out of `CODING_MEMORY.md`*. The paragraph names a member and then points at the commit that
removed it.

Strictly, `curated_docs` (plural, `config.json:11`) is the *path* list and does contain the archive; the
singular `curated_doc` is the weight class and does not. The plural/singular slip is doing the work of
hiding the error, inside a sentence whose operative conclusion is about weights.

**This does not break the conclusion — if anything it strengthens it**: the cited precedent turns out
to be an exact, already-shipped template. But it is a wrong enumeration in the one paragraph whose
whole job is to stop a reader acting on an unverified claim, and the decisions summary repeats it
verbatim under "I verified this at source". The verification confirmed the *conclusion* and not the
*enumeration* — the same species this section exists to document. Consequence for ADR 0021: a reader
would believe demoting `curated_doc` to 1.2 also demotes the archive. It doesn't; the archive is
already at 1.0, i.e. already **below** the proposed value.

**2. Round 6's finding #2 had two archive items; one was silently dropped.** Fix #3 corrected
`CODING_MEMORY.md:4656`. The other — `:4648`, "the class-level claim *judge verdicts crowd out feature
docs* is **untested** — one document, one query" — is untouched and undeclared. It matters for the same
reason fix #3 did, and I measured it: `:4648` is **chunk 280**; the branch's own final position, "**The
judge-crowding story is dead**" (`:4689`), is **chunk 282**. Two chunks apart, so retrieval returns the
weaker statement detached from the stronger one. Mitigating: "untested" *under*-claims rather than
asserting something false, so a reader is under-informed rather than misled — and round 6's gloss
("the enumeration tested it and found it null") was itself a shade strong. Low severity, but the
selection between the two sub-items was never stated.

**3. The sweep table row can be retrieved without its caveat.** The `⇒` prose conclusion shares chunk
110 with the knob paragraph ✓, but the **table itself** (the `1.2` row, `:2334`) is **chunk 109** —
detached. A hit on the bare table gets "1.2 → 3 of 5, nothing regresses" with no stop sign. Well
mitigated by the summary-box caveat at `:2001-2009` (a third co-location), so this is a residual, not a
hole.

**4. `index.py:44-51` is a slightly off citation.** The mechanism is `:46` and the `return` at `:58`;
`44-45` are blank and `51` is mid-docstring. The reader lands close enough to find it, but this
branch's own recorded lesson is *store the derivation, not the number*.

**5. On the ~48-chunk merge effect you flagged as out of scope — I largely agree with you, and more
than you argued.** I measured it rather than estimating: this PR adds **99** judge-verdict chunks at
`curated_doc` 1.5, not ~48 — **+4.1%** of the 2405-chunk judge corpus, roughly double round 6's
character-division estimate (the chunker splits on headings too). But the disclosure round 6 asked for
is *already in the doc*: `:1878-1880` says re-run "after the **first scheduled index run that includes
these commits** … so today's numbers will move", and the threshold at `:1881-1886` records **which
queries pass, not how many** — precisely the trip-wire that would catch a composition shift. Deferring
the *measurement* to ADR 0021 is correct; you cannot re-run a pinned experiment from a docs branch. I'd
only carry the measured figure forward so the ADR inherits a number instead of an estimate.

**6. Pre-existing, unchanged.** `pyproject.toml:26` deselects the `measurement` marker, so the green
`74 passed` I ran sits over a red **2-of-5** retrieval bar and touches nothing in this diff. The feature
card is now **2363 lines**; the optional `.spec.md` split remains untaken across seven rounds.

## What I'd double-check before merging

1. **Drop `CODING_MEMORY.md` from the bucket list at `:2343`** (and fix the singular/plural), or say
   explicitly that it is already carved out to `archive_doc` 1.0. One clause. It is the only thing here
   that could mislead ADR 0021, and correcting it makes the paragraph's own argument stronger.
2. **Either correct `CODING_MEMORY.md:4648` or state why you judged it not stale** — it's two chunks
   from its own refutation.
3. **Widen the citation to `index.py:46-58`** so it spans the line that does the work.
4. Optional: move the `🛑` stop sign above the sweep table rather than below the `⇒`, so chunk 109
   carries it too.
5. Optional: record **99 chunks / +4.1%** in the re-check trigger, replacing round 6's estimate.

---

## Dimension table

| dimension | score | why |
|---|---|---|
| `intent` | **pass** | All four round-6 remedies landed, and the fifth was declined with reasoning. The contested claim was contested with the text to back it rather than silently obeyed — which is what the invocation asked for and what a calibration record needs. |
| `execution` | **concern** | Three of four fixes verified genuinely discharged at chunk level, and the flagship conclusion independently checked (10/10 ranks `curated_doc`; `search.py:80` post-fusion). Against that: a wrong bucket enumeration inside the flagship fix, one undeclared partial discharge, a detached table row, an off citation. Nothing runs, so no `fail`. |
| `trajectory` | **pass** | Strongest dimension for a second round. Verified at source before acting, refused a judge's incorrect clause with evidence, kept "narrative withdrawn" separate from "remedy survives", and named the missing knob as an engineering task rather than a number. The one blemish is an inherited premise, not faulty reasoning. |
| `regression` | **pass** | Docs only; suite green, run by me; single revertable commit. Upgraded from round 6's `concern` because I read the re-check trigger: it already discloses that these commits move the numbers and thresholds on *which* queries pass, so the corpus-growth effect is disclosed and bounded rather than unmonitored. |
| `context_budget` | **concern** | Feature card 2363 lines; this PR adds a measured 99 chunks at `curated_doc` 1.5 (+4.1% of the judge corpus) to the retrieved corpus the branch itself measures; `.spec.md` split untaken across seven rounds. Not always-on rule context. |
| `traceability` | **concern** | The sweep's derivation and script remain unpreserved and unreproducible (pinned state gone) — honestly acknowledged, still a gap. Plus the unsourced bucket-membership claim and the off-by-a-few `index.py` range. |
| `success_masking` | **concern** | `74 passed / 23 deselected` over a red 2-of-5 bar it does not exercise. The verdict-level "anything regress?" column is now *disclosed* as count-hides-erosion (a real improvement) but not fixed; and `:4648` stays retrievable detached from its refutation. |
| `intent_drift` | **pass** | Docs-only, no dependencies, no drive-by edits, scoped to discharging round 6. The declined item was declined out loud with reasoning, not quietly skipped. |
| `checkpoint` | **pass** | One well-scoped commit on a clean base, clean working tree, message states the correction chain. Trivially revertable. |
| `audit_trail` | **pass** | Exemplary, and better than round 6's. The author committed a verdict containing a claim they believe is wrong rather than editing it, and flagged the disagreement for adjudication instead of burying it. That is the behaviour a calibration record exists to capture. |

**risk:** low — documentation only, nothing executable touched, fully revertable, and the flagship
recommendation is now guarded by an explicit "the knob does not exist yet" stop sign that I measured to
sit in the same retrieval chunk as the recommendation itself.

**confidence:** high — I ran the test command, read the full delta, and verified every load-bearing
claim against real source (`config.json:11,17`; `index.py:46,58`; `search.py:80`; `chunk.py:13`),
re-read the disputed text at `f0cbde5` to adjudicate it, and ran the project's own chunker to convert
the navigability question into a measurement. The one thing I still cannot verify is the sweep table's
numbers, because the pinned snapshot is gone — the doc says so plainly.

## Concerns

- `CODING_MEMORY.md` listed as a `curated_doc` weight-bucket member at `:2343`; it is `archive_doc` 1.0 per `index.py:46,58` and this file's own `:490` / `:1006-1014`
- Round 6's second archive item (`CODING_MEMORY.md:4648` "untested") left uncorrected and undeclared; chunk 280 vs its refutation in chunk 282
- Sweep table row (chunk 109) retrievable without the "no knob" stop sign (chunk 110)
- `index.py:44-51` citation excludes the `return` at `:58` that implements the carve-out
- Sweep numbers remain unreproducible; no preserved script or pinned state
- Green suite (74 passed) sits over a red 2-of-5 retrieval bar; `measurement` deselected at `pyproject.toml:26`
- PR adds a measured 99 judge chunks (+4.1%) at weight 1.5 before the re-check trigger fires; deferral accepted, magnitude un-recorded in the doc
- Feature card 2363 lines; `.spec.md` split untaken across seven rounds
