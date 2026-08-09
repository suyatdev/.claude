# Observability verdict — `docs/r9-counterfactual-control` @ `3e9ec4b` (round 3)

- **repo:** `memsearch-freshness` (worktree of `~/.claude`)
- **branch:** `docs/r9-counterfactual-control` → slug `docs-r9-counterfactual-control`
- **head_sha:** `3e9ec4b70f86c8a8e75a75f5993910b417896f25` (amends `3609faa`, judged in
  `2026-08-09-docs-r9-counterfactual-control-round2.md`)
- **base:** `origin/main` @ `64d8acb` (local `main` still stale at `8d79094` — a tool defaulting to
  `main` diffs 34 files instead of 2)
- **stage:** implementation
- **ts:** 2026-08-09T17:20:27Z
- **filename note:** rounds 1 and 2 already occupy the bare slug and `-round2`; suffixed `-round3`
  per this directory's convention.
- **diff:** 2 files, +294 / −1 vs `origin/main` — `docs/features/memsearch-freshness.md`,
  `CODING_MEMORY.md`. Round-2 → round-3 delta is +130 / −38. No source, tests or config.
- **test command run by me:** `cd ~/.claude/memsearch && uv run pytest -q` → **74 passed, 23
  deselected in 0.34s**. Matches the caller's report. It exercises nothing in this diff.

---

## What was changed

Think of it as a detective who spent three rounds narrowing down a suspect, got a confession — and
then checked the calendar and found the suspect was already in the building on the day nothing was
wrong. The suspect can still explain why the door is stuck *today*; he cannot explain why it
*became* stuck.

The concrete version: a five-question retrieval quiz (R9) went from passing to failing. To find out
what was crowding out the right answers, the author copied the search index, deleted one pile of
documents, and re-ran the quiz. Rounds 1 and 2 concluded "judge verdicts are the cause."

This round does four things, three of them mine and one nobody asked for:

1. **My "run the placebo exactly" suggestion — and it went worse than I predicted.** Placebo seed 11,
   measured exactly, flips `falsifier-base-pin` PASS (2) → **FAIL (2)**. So the placebo's null was
   partly a measurement artefact, and "verdict-safe, not count-exact" was wrong. Both corrected in
   place with ⚠️.
2. **My "delete only the three chunks" suggestion — confirmed.** Dropping 3 chunks recovers the query
   identically to dropping 2405. The class-level claim is now explicitly marked **untested**.
3. **The sha256 fixed, with the trap written down** — a live SQLite file rewrites itself on connect,
   so a hash of one is not a fixture. Replaced with content anchors.
4. **The thing none of us had.** Chasing (2), the author checked *when* those three chunks entered
   the index: `2026-08-07T23:38:14+00:00` — **already there at 10b, when the query still passed.**
   Something present while a test passes cannot be why it later failed. So the whole instrument
   answers a different question than the one it was run to answer, and the regression's cause is
   **unassigned**.

## Does it do what you wanted?

Yes, and this is the strongest round of the three — because the biggest correction was self-inflicted
and it demoted the author's own result rather than defending it.

**What I verified independently**, read-only against the live index (`~/.claude/memory-index/memory.db`,
opened `mode=ro`, never through `dbmod.connect()`):

- **The timestamp — the load-bearing new claim — is exact.**
  `sources.indexed_at = 2026-08-07T23:38:14+00:00` for
  `coding-memory/observability-judge/2026-08-03-fix-git-guard-empty-index.md`. Matches the doc
  character for character.
- **It really was the original backfill.** Sources cluster in a rolling batch from
  `2026-08-07T23:36:51` onward; 23:38:14 sits inside it.
- **The inference holds on the calendar.** Task 10's commits are `997c57a` / `6686b6e` at
  `2026-08-08T01:07–01:35 -04:00` = **05:07–05:35 UTC**, ~5.5 hours *after* those chunks were
  indexed. So "already present at 10b" is sound, not asserted.
- **41 chunks** for that source, at **weight 1.5** — both as stated.
- **The 639-line verdict vs the 375-line spec** — both confirmed by `wc -l`.
- **The 2405 figure reconciles exactly**, which round 2 only verified as arithmetic
  (8960 − 6555). The composition is: canonical `observability-judge` **1541** + canonical
  `compliance-judge` **711** + judge verdicts inside the two repo roots **153** = **2405**. That is a
  clean, independent confirmation, and it also shows the variant is *both* judges plus repo-root
  copies at weight 1.2 — broader than "observability verdicts", which the doc's wording
  ("judge-verdict corpus") does cover fairly.
- **The sha256 explanation is mechanically true.** `db.py:48-56` — `connect()` calls `_init_schema`,
  which runs `CREATE TABLE IF NOT EXISTS` inside `with conn:`. That writes. A hash of a live SQLite
  DB is genuinely not a usable fixture.
- **The doc's own honesty check passes:** live index is now **9016 chunks / 1039 sources /
  `max(indexed_at) 2026-08-09T16:55:31`**, so the recipe's 8960 is indeed unreachable.

The category error being caught by the author, from a timestamp, while answering an objection about
something else entirely — and then promoted to *the* headline over a result that flattered the
previous three rounds — is the best trajectory signal I have seen on this branch.

## Answering the three questions you asked for pressure on

### 1. Is "three chunks are sufficient" worth shipping? — Keep it, but it proves less than it reads

Ship it, but not as written, because **the three-chunk result is very close to arithmetically
guaranteed by the depth-10 listing you already published — it does not single out the verdict file.**

Clause 1 needs 2 belonging hits in the top 6. Your listing has the target at rank 1 and rank 8.
Getting rank 8 into the top 6 requires removing **any 2** chunks from ranks 2–7. You removed 3
(ranks 3/5/7) → the rank-8 chunk lands at position 5. PASS (2). But run the same arithmetic on the
other candidate in your own table:

```
 2. memsearch-freshness.md          4. replay-harness-base-pin.md:594-606
 3. JUDGE :17-36                    6. replay-harness-base-pin.md:607-635
 5. JUDGE :445-471                 10. replay-harness-base-pin.md:907-927
 7. JUDGE :195-218
```

Remove ranks **4, 6, 10** — three chunks of `replay-harness-base-pin.md`, a *feature doc*, not a
judge verdict — and the remaining order is 1,2,3,5,7,8,9, putting the rank-8 chunk at position **6**:
also inside the top 6, also **PASS (2)**. Same size, same recovery, different document, opposite
conclusion.

So "three chunks of the verdict are sufficient" is true and also would have been true of a
same-sized slice of an ordinary feature doc. What the experiment actually measured is that **this
query's clause-1 margin is one rank deep**, and almost any three-chunk deletion above rank 8 flips
it. That is a statement about margin thinness, not about judge verdicts. *(Positional prediction from
your own listing — I could not execute it, see below — but your exact rebuild confirmed the
positional prediction in the 3-chunk case, so it is credible.)*

This also weakens the placebo's rescue. The placebo can only touch the eligible chunks at ranks 2, 4
and 6 (ranks 3/5/7 are judges, excluded), each dropped at ≈ 2405/6372 ≈ 0.38. P(≥2 of 3) ≈ **0.32**.
One exact seed not recovering the query is therefore a ~2-in-3 outcome, not a demonstration.
"Removing 2405 unrelated chunks fails to reproduce the effect" is an n=1 coin flip described as a
control. *(Back-of-envelope: independent uniform dropout, ignores RRF and backfill.)*

**Recommendation:** keep the three-chunk result, but restate it as *"clause 1 on this query is one
rank from failing; any two chunks above rank 8 flip it, and the three that happen to sit there are a
verdict about the same fix."* That is what survives, it is still a real and cheap lead for ADR 0021,
and — importantly — it no longer invites the misreading, because it stops naming a culprit at all.
As currently written, "the minimal sufficient cause is three chunks" reads as *identification*, and
your section heading says exactly that.

### 2. Has the correction history become the thing a reader must fight through? — Partly, and the fix is mechanical

The doc is usable, and the numbered 1→4 narrowing at the end is genuinely the right shape — a reader
who reaches it gets the truth in ~12 lines. Two specific hazards, both cheap:

- **Every table is still printed under its original framing, with the retraction underneath.** The
  placebo table at `:2089` is followed by "⚠️ that null is partly an artefact." A skimmer — or a
  retrieval snippet, which is this feature's whole subject — takes the table and stops. Mark the
  *cells* (or retitle the table "superseded — approximate method"), don't only add prose after it.
- **The section is now ~5 ⚠️ blocks over ~150 lines**, each one narrowing its predecessor. The
  correction record belongs at the end (where you have it); the *body* should state only the
  surviving claim. Right now the body still argues the superseded ones first.

And the structural one: the card is **2209 lines** and grew every round. The `.spec.md` split is a
MAY, not a MUST, but this section alone is the argument for taking it.

### 3. Self-interest — and I have to retract my own round-2 claim

Round 2 I wrote that this verdict file "is itself another `curated_doc` at weight 1.5" and that "the
next R9 run will include these words." **That was wrong, and I can now show it.** `config.json`
indexes `~/.claude/coding-memory`; my verdicts for this branch are written to
`~/.claude/memsearch-freshness/coding-memory/...`, which is a *worktree* path and matches no
`curated_docs` entry and no `repo_root`. I checked: chunks under `%/memsearch-freshness/%` = **0**.
My rounds are not in the measured corpus and did not perturb it.

The honest residue is deferred, not absent: on merge, this branch's +294 doc lines land in the
indexed canonical copy, and any verdict files that get *committed* would land in the indexed
`coding-memory/observability-judge/` too. So each round adds to the problem **at merge**, not now.

## What could go wrong / what I'm unsure about

**1. The pinned artefact is gone, and with it every table in this section.** New this round, and it
is the biggest verification loss. `memory.pinned.db` no longer exists anywhere I can find (`/tmp`,
`/var/folders`, `~/.claude`, the worktree — nothing). Round 2 I could re-run the placebo against it
cell-for-cell; **round 3 I could reproduce none of the tables.** The three-chunk table, the exact
placebo seed 11, the exact-FTS table and the noise probe are now permanently unfalsifiable.

**2. Relatedly, the sha256 fix swapped one unusable fixture for three.** The doc replaced the hash
with content anchors `chunks = 8960`, `sources = 1025`, `max(indexed_at) = 2026-08-09T04:45:14`. Live
is **9016 / 1039 / 16:55:31**. The correction addressed the anchor's *stability* — correctly — but
not its *availability*. No reader can meet any of the three anchors, and the doc does not say the
snapshot is destroyed.

**3. The retained result is the one I can least check, and (per §1 above) the one that proves least.**
Uncomfortable combination: what the doc tells ADR 0021 to act on is the three-chunk lead, which is
unreproducible *and* positionally over-determined.

**4. The decisive control can no longer be run.** Deleting ranks 4/6/10 would settle whether this is
about judge verdicts or about a thin margin. It needed the pinned DB.

**5. Success masking, unchanged:** `pyproject.toml:26` deselects the measurement marker, so
`pytest -q` reports 74 green over a **2-of-5 red** retrieval bar. The green I ran says nothing about
this diff.

**6. Frontmatter still wrong, third round running.** `branch: feature/memsearch-freshness` while HEAD
is `docs/r9-counterfactual-control`. `rules/gates.md` calls a branch/phase mismatch stop-and-report;
flagged in rounds 2 and 3 and still there.

**7. Uncommitted `verdicts.jsonl`** was already dirty on entry (doc-guard flagged it); my append adds
to that.

**8. What I am *not* disputing:** the retraction itself. The timestamp is real, the calendar works,
and "a leave-one-out varies populations at one instant; a regression is a change between two
instants" is correct. That conclusion stands without any of the missing artefacts — which is exactly
why it is the safest thing in the document.

## What I'd double-check before merging

1. **Say in the doc that the snapshot is destroyed.** One sentence. Otherwise a reader burns an hour
   on three anchors that cannot be met.
2. **Restate the three-chunk finding as margin depth, not identification** — ranks 4/6/10 predict the
   same recovery from a feature doc. This is the one that changes what ADR 0021 inherits.
3. **Downgrade the exact placebo to n=1** — ~32% chance of that null by luck; it currently reads as
   ruling dilution out.
4. **Mark the superseded tables in-cell**, not only in prose beneath them.
5. **Fix the frontmatter branch.**

None of these block a docs-only merge — nothing here executes, and the headline conclusion (the
regression is unexplained) is *more* conservative than what it replaced. They block treating the
three-chunk lead as settled input to the ADR 0021 weighting decision, which is what it is for.

---

## Dimensions

| dimension | score | note |
|---|---|---|
| intent | pass | all four round-2 points addressed; two by refuting the author's own prior claim with data |
| execution | pass | tests 74 passed / 23 deselected, run by me; timestamp, backfill batch, 41 chunks, weight 1.5, 639/375 line counts and the 2405 decomposition (1541+711+153) all independently verified read-only |
| trajectory | pass | self-caught category error found from a timestamp while answering an unrelated objection, and promoted over a result that flattered three prior rounds; "state which question the instrument answers" is a genuine transferable rule |
| regression | pass | docs-only; no source, tests or config; pinned artefacts live outside the repo |
| context_budget | concern | +294 lines into a 2209-line card that lands in the indexed corpus on merge; `.spec.md` split still declined; section is ~5 stacked ⚠️ retractions |
| traceability | concern | `memory.pinned.db` no longer exists — every table this round is now unreproducible; the sha256 fix replaced one unmeetable anchor with three (8960/1025/04:45:14 vs live 9016/1039/16:55:31) and the doc does not say the snapshot is gone |
| success_masking | concern | three-chunk "minimal cause" is positionally over-determined — ranks 4/6/10 of a *feature doc* predict the same PASS (2), so it reads as identification but measures margin depth; exact placebo is n=1 with ≈32% false-null probability yet is stated as ruling out dilution; `pytest -q` green over a 2-of-5 red R9 |
| intent_drift | pass | scope is exactly the two owed controls, the sha256 fix, the `:1971` wording, plus the self-caught invalidation; no drive-by edits |
| checkpoint | pass | single amended docs-only commit off `origin/main`; trivially revertible; nothing mutated outside the vanished scratchpad |
| audit_trail | concern | commit body and `CODING_MEMORY.md` entry are detailed and correctly demote the prior conclusion, but frontmatter still records `branch: feature/memsearch-freshness` against HEAD `docs/r9-counterfactual-control` — flagged in rounds 2 and 3, unfixed |

**risk:** low · **confidence:** high

### Concerns
- Pinned snapshot `memory.pinned.db` no longer exists anywhere on the filesystem — the three-chunk table, exact placebo seed 11, exact-FTS table and noise probe are now permanently unreproducible; round 2 could still re-run the placebo, round 3 could reproduce none of it
- The doc does not state that the snapshot is destroyed; it still offers a reproduction recipe
- sha256 fix replaced one unmeetable anchor with three unmeetable anchors: `chunks = 8960` / `sources = 1025` / `max(indexed_at) = 04:45:14` vs live `9016` / `1039` / `16:55:31` — stability was fixed, availability was not
- Three-chunk "minimal sufficient cause" is positionally over-determined: rank 8 needs only 2 removals from ranks 2-7, and removing ranks 4/6/10 (three `replay-harness-base-pin.md` chunks, a feature doc) predicts the same PASS (2) — the result measures clause-1 margin depth, not judge-verdict displacement
- Exact placebo is a single seed with ≈32% probability of a false null (only ranks 2/4/6 are eligible, p≈0.38 each, P(≥2 of 3)≈0.32), yet "a size-matched random deletion does not recover the query" is stated as a control
- The decisive discriminating control (delete ranks 4/6/10) can no longer be run — the artefact it needed is gone
- The result retained for ADR 0021 is simultaneously the least reproducible and the least discriminating claim in the section
- Superseded tables are still printed under their original framing with the retraction only in prose beneath — a skimmer or a retrieval snippet takes the table and stops
- Section now carries ~5 stacked ⚠️ narrowings over ~150 lines; the surviving claim is stated last, after the superseded ones are argued first
- Feature card is 2209 lines and grew every round; the optional `.spec.md` split remains untaken
- Frontmatter still records `branch: feature/memsearch-freshness` while HEAD is `docs/r9-counterfactual-control` — third round unfixed; `rules/gates.md` calls this stop-and-report
- `pyproject.toml:26` deselects the measurement marker, so `pytest -q` reports 74 passed over a 2-of-5 red retrieval bar
- Local `main` stale at `8d79094`; a tool defaulting to `main` diffs 34 files instead of 2
- 10b's index state still unreconstructed — now correctly the blocking open item, but the regression's cause remains unassigned
- Judge self-interest, corrected from round 2: my prior claim that these verdict files enter the measured corpus was **wrong** — worktree paths match no `curated_docs` entry (chunks under `%/memsearch-freshness/%` = 0); the perturbation is deferred to merge, not present now
- `2405` verified as `1541` canonical obs-judge + `711` canonical compliance-judge + `153` repo-root judge verdicts (weight 1.2) — broader than "observability verdicts", though the doc's "judge-verdict corpus" wording covers it
