# Observability judge — memsearch-freshness (architecting, loop 2 round 11)

- **ts (UTC):** 2026-08-07T19:52:41Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `e707767440abffaa919023f9a78aac69801b4b66`
- **stage:** `architecting` (advisory — does not gate a PR)
- **artifact:** `docs/features/memsearch-freshness.md`, 1,317 lines, blob
  `b71672c3082aa6b495c10dee328532134810b4e0` — **verified against the invocation's expected blob,
  exact match**
- **checkpoint:** clean tree, `phase: planning`, `branch: none`, spec committed @ `e707767`
- **test command:** none supplied; no implementation code exists. I ran what *is* runnable — the
  golden retrieval suite, `wc` against every pinned size figure and its denominator, a per-feature
  census of `docs/features/`, and direct reads of every code line R10 cites — and say below what
  that licenses and what it does not.

> **Three of my four round-10 findings are genuinely closed; I verified each rather than accepting
> the summary. One is closed at the level it was raised and re-opens one level down.** Risk stays
> **medium**, and it is now concentrated in a single sentence of R9 plus the document's size. The
> freshness half I would still ship as designed.

## What was changed

Picture a smoke detector that stopped chirping. For 19 days it reported "all good" on a flat
battery and nothing checked. The spec designs a timer that re-tests the detector every six hours
and — deliberately first — a display that shows the detector's *real* state instead of a number it
remembers from a fortnight ago.

Round 11 is 28 added lines and nothing else. The `git diff 85baf2d..e707767` contains exactly the
four claimed edits: R9's "range" now names its population, the Gherkin scenario stops speaking
per-file, task 1b gets `git commit --allow-empty`, and the archive's size is re-measured and pinned
in one caveated place with its restatements de-numbered. No drive-by edits. R3's state table —
the strongest artifact in this document — was not touched at all.

## Does it do what you wanted?

Yes for three of four, verified by measurement rather than by reading the summary.

| Round-10 finding | How I checked | Result |
|---|---|---|
| 1. Range's population undefined | Read R9 `:335-344`, scenario `:1039-1045`, falsifier (i) `:1085-1088`, task 8b `:1253-1257` | **All four now name the same population**: every feature under `docs/features/`, per-feature summed, explicitly not the five chosen ✅ — but see finding 1 below |
| Population is actually computable | Computed it: 10 features, per-feature summed | **Ran it end to end.** `76 · 152 · 217 · 218 · 375 · 766 · 1166 · 1303 · 1317 · 1779` lines ✅ mechanically derivable at task-8 time |
| 2. Scenario still per-file | Read `:1039-1045` | Now *"ranked by **per-feature** chunk count"*, and the enumeration that caused the miss is gone — replaced by *"No list of those surfaces appears here"* `:358` ✅ **root cause, not the instance** |
| 2b. Two-item inventory at old `:348` | `grep` for it | **Deleted** ✅ (round-10 concern 6, closed) |
| 3. Task 1b has no carrier | Read `:1193-1195` | *"use `git commit --allow-empty`"*, verbatim ✅ |
| 3b. Sweep not mechanizable | Read `:152-175`, `:1188-1201` | **Still prose.** Not addressed — and it still matters (finding 2) |
| Archive size rotted | `wc -m` on both files | **317,249 chars / 3,723 lines** — spec exact ✅. Denominator `wc -m` = **184,620** — spec exact ✅. `317249/184620 = 1.7184` → spec says **1.72×** ✅ |
| Pinned in one place | `grep` for every figure | One pinned occurrence `:589-592`; `:465` and `:1263` de-numbered; the multiplier's second copy replaced by a pointer `:606-609` ✅ |
| Golden baseline still reproduces | `uv run pytest -m golden -q` | **16 passed, 63 deselected in 3.08s** — spec pins *16 passed, 63 deselected* ✅ |
| Every R10 code citation | Read each line | `chunk.py:111` `recall = "decision" if "decisions" in str(path) else "doc"` ✅ · `db.py:16` no `archive_doc` ✅ · `db.py:17` already has `episodic` ✅ · `config.py:56` `excludes = …` / `:57-60` the guard ✅ · `index.py:44-51` hardcoded per bucket ✅ · **all ten `test_index.py` line citations and all four inline comments exact**, including `:117` = the changed-file test and `:149` = the limit-scoped one ✅ · fixture `:58` writes `CODING_MEMORY.md` **into the curated directory** ✅ — the pre-created-condition trap, exactly as described |

**I owe a correction of my own.** Round 10 I reported the multiplier as "now at least 1.73×". That
was a bytes-numerator (`wc -c` = 320,406) over a characters-denominator (`wc -m` = 184,620). The
spec's discipline — *"every figure in this paragraph is now an on-disk character count, compared
like with like"* — is correct and mine was the mismatched number. Like-for-like it is 1.7184 →
**1.72× is right**. My round-10 concern 8 is withdrawn.

## What could go wrong / what I'm unsure about

**1. The spread rule's loophole moved down one level, and it still admits the falsifier's own
counterexample.** The *population* half is genuinely closed. What is still undefined is what
"third" means — the **bottom third of the value span** (min + range/3) or the **bottom-ranked third
of the population** (a tertile). All four surfaces are equally silent, so this is not drift between
them; it is one underdetermination present identically in all four. It bites, with real numbers.

Measured per-feature across all ten features under `docs/features/` (characters, `wc -m`, a proxy
for chunk count — chunking is size-driven, so the ordering will be close but the exact boundaries
will move):

```
  5,056 stale-phase-guard-rule-text      47,683 memory-system-split
  8,254 falsifier-base-pin               72,921 verification-marker-gate
 12,293 git-guard-chained-command        89,003 memsearch-freshness
 13,947 shell-segments-redirects         97,988 replay-harness-base-pin
 27,509 git-guard-empty-index           131,516 phase-guard-hook
```

- **Value-span reading:** span 5,056–131,516; bottom third ≤ **47,209**, top third ≥ **89,363**.
  A sample of `{git-guard-empty-index, verification-marker-gate, memsearch-freshness,
  replay-harness-base-pin, phase-guard-hook}` **passes** — 27,509 clears the bottom bound,
  131,516 clears the top.
- **Rank-tertile reading:** bottom third = the three smallest; `git-guard-empty-index` is **rank 5
  of 10**, the middle of the population. The same sample **fails**.

That sample is **four large targets plus one medium** — the exact shape falsifier (i) `:1088`
declares a falsification. So the guard protecting the branch's only measurement of R10 still has a
reading under which the falsifier's own named counterexample passes. This is round-10 finding 1,
one level down: closed at the level it was raised, re-opened beneath it. **One sentence fixes it**
— e.g. *"bottom third means the bottom-ranked third of the population: of ten features, the three
smallest."* My pick: rank-tertile, because a skewed corpus makes the value-span reading put half
the population in its own "bottom third," which is the same measures-nothing failure in different
clothes.

**2. Task 1b is still a hand sweep, and finding 1 is live evidence for why that matters.** It now
has a carrier (`--allow-empty`, correctly closed) but no mechanism. Contrast R10.6, which hands the
implementer a literal `grep -n CODING_MEMORY` and names which of the fourteen hits to fix. The
R3/R9 sweep is prose that explicitly demands finding things no grep can find — *"a state named in
prose, without its number, is still a surface"*, *"an ordering claim is duplication"*. It rests on
exactly the careful reading that under-counted in rounds 5 through 10. And finding 1 above is a
defect the sweep would have to catch by noticing that four surfaces agree with each other while all
four are silent on the same thing — the hardest possible class for a human read-through, because
there is no disagreement to spot. Escalation also still leaves no artifact: `"GATE: Spec change
needed"` is a spoken announcement, and `rules/gates.md` records that the phase guard **exempts
`docs/*`**, so "no in-place spec edit during implementation" is discipline, not enforcement.

**3. The document has outgrown its own structural decision — and it is now costing.** You asked me
to rule plainly. My answer is **yes, the added precision now costs more than it buys**, but the cost
is concentrated and the fix is *relocation, not deletion*. Three concrete observations:

- **R4 through R10 are orphaned in the outline.** There is no heading between `:245`
  (`#### The three constants`) and `:327` (`#### R9's derived surfaces are swept, not listed`), and
  none between `:327` and `:635` (`### Data flow`). So **R4–R8 sit under a subheading about R3's
  constants, and R10 — the largest and most operationally consequential requirement in the spec, at
  ~194 lines — sits under a subheading about R9's derived surfaces.** A reader navigating by outline
  cannot find R10. That is a navigability defect created purely by growth without restructuring, and
  it is the cheapest thing on this list to fix.
- **~120 lines are obituary rather than instruction** — 29 retrospective `round N` references. Each
  documents a real defect that survived multiple judge rounds, so deleting them risks
  reintroduction; that argument is sound. But three blocks have outgrown it:
  the retired `≥0.30` clause's history `:379-412` (**34 lines**, whose migration target ADR 0019 was
  named in round 8 and is still un-migrated three rounds later); the archive-size correction
  narrative `:594-617` (**24 lines** explaining why previous numbers were wrong, attached to a figure
  that **gates nothing** — the spec itself says *"R9, not this paragraph, remains the instrument
  that decides it"*); and the inventory obituaries told three times at `:140-150`, `:327-334` and
  `:356-361` (**~25 lines** for one story).
- **The obituaries have begun rotting too.** One of this round's own edits `:606-609` was fixing a
  correction narrative that had gone stale about stale numbers. And `:359` says the enumerated list
  named *"the three restatements"*; the list at round 10's `:348` named **two** (task 8b and
  falsifier (i)) — verified against `85baf2d`. Trivial in isolation, but it is a stored
  self-description drifting inside the section that forbids stored self-descriptions.

**The sections I would cut, by line range** — all three to ADR 0019, which is already a scheduled
task and already the named migration target:

| Lines | Content | Leave behind |
|---|---|---|
| `:379-412` | the `≥0.30` clause's five-round history | 3 lines: the ceiling is 0.04918, a floor was impossible, see ADR 0019 |
| `:594-617` | archive-size unit-conflation + rot narrative | keep `:589-592` (the measurement); 2 lines of caveat |
| `:140-150`, `:327-334`, `:356-361` | the inventory story, told three times | one 3-line statement of the method's rule |

Plus the heading fix. That is ~85 lines relocated and four headings added — roughly 1,230 lines and,
far more importantly, a navigable requirements list. **One tension worth naming:** `:12-13` says
*"Single-file by design — the pair (`.md` + `.spec.md`) shape is `memory-system-split`'s alone (ADR
0017, decision 7)"*, so the house rule's own MAY-split escape hatch is foreclosed by an ADR written
when this document was far shorter. I am **not** recommending reopening ADR 0017 — relocation to
ADR 0019 achieves the same relief and is already planned.

**4. Carried, structural, unchanged — the honest limit, and the direct answer to the central
question.** A run that walks **zero files** completes cleanly, stamps `last_run` at now, leaves
`chunks` at its prior non-zero value, and renders as **state 8, fresh, indefinitely** (`:1114-1128`).
You asked whether the bounding is wrong. **The bounding is right and I am not re-raising it as a
defect** — it is dated, attributed, pointed at its own fix (*"record the walked-source count and add
the state"*), and the spec calls it *"the same species as the failure in the Background"* in its own
words. But it must stay stated plainly, because it is the direct answer to the question this loop
keeps asking: **this design can tell a true green from a false one for every condition R3's table
classifies, and cannot for the one condition that caused the founding failure.** R10 fixes *that
instance* by config; nothing detects the class. Alongside it, unchanged and disclosed: silence still
equals health (absent `status.json`, `chunks == 0`, an unregistered hook, and a file unreadable
mid-rebuild are indistinguishable from a healthy quiet start); **the monitor has no monitor**, by
the data-flow diagram's own dotted edge; there is **no prune path**; `scheduled-index.log` is
unbounded and is the destination of four of the eight lines; falsifier (c) remains unobservable at
task-10c time.

**5. R9 still has no control, and task 10(b) still pre-commits attribution.** `:1302-1303` — *"A
failure of either clause is a real result about R10's noise cost"* — while the five queries are
authored **after** task 7 lands and run **once**, afterwards. 10(a)'s before/after is real (I
re-confirmed it reproduces) but corpus-level, and the spec says the two instruments *"are not the
same instrument"* without ever saying how to read them jointly. If golden holds except the
pre-registered entry 11 and R9 still fails, nothing tells the reader that attribution to the archive
is weakly supported at best.

## What I'd double-check before merging

All text edits, `phase: planning`, before a line of code exists. In order of value:

1. **Define "third"** — one sentence in R9, propagated to the scenario, falsifier (i) and task 8b.
   *My pick: the bottom-ranked third of the population (of ten features, the three smallest),
   because the value-span reading puts half the population in its own bottom third and admits the
   falsifier's own counterexample.*
2. **Relocate the three obituary blocks to ADR 0019 and add headings for R4–R10.** The heading fix
   costs four lines and is the single highest readability return in the document.
3. **Give task 1b one mechanical anchor** — even a `grep -n "state [1-8]\|bottom third\|per-feature"`
   starting point would turn "read it all carefully" into "check these hits, then read for the
   prose-only surfaces." It will not find everything; it does not have to.
4. **Connect the two instruments** — say that a red R9 alongside a clean 10(a) means attribution is
   *unresolved*, not that it is R10's noise cost.
5. **Fix `:359`'s "three restatements"** to match what the deleted list actually named (two).

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | **pass** | Exactly the four directed edits, verified against the artifact rather than the summary; the diff is +28 lines and contains nothing else. Finding 2's fix went to the **root cause** — the enumeration that caused the miss was deleted, not just the missed instance. My suggested population was adopted and I confirmed it is mechanically computable by computing it. Scope still stops at parent item 5. |
| execution | **concern** | No code exists; scored on design-verifiability against the live tree. Every R10 code citation re-checked is **exact** — `chunk.py:111`, `db.py:16-17`, `config.py:56-60`, `index.py:44-51`, all ten `test_index.py` lines, all four inline comments, and the fixture's pre-created-condition trap. Golden baseline reproduces (16 passed, 63 deselected). Held at concern because the guard on the branch's only measurement of R10 admits a reading under which the falsifier's own named counterexample passes, and the document's remaining self-check is still a hand sweep with no mechanism. |
| trajectory | **pass** | Sound and root-directed. Adopting the fixed population is right; deleting the enumeration that produced the round-10 miss — rather than adding the fourth entry to it — is the *delete the duplicate, don't sync it* rule applied correctly for the third round running. Re-measuring the archive like-for-like and pinning it once, with the multiplier's second copy replaced by a pointer, fixed a defect I had **mis-measured myself**: my "≥1.73×" mixed bytes over characters and the spec's number is the correct one. |
| regression | **pass** | Documentation-only. R3's state table and all eight rendered lines untouched by this diff, so last round's hand-walk of all 20 state surfaces still holds. No dangling references left by the removed two-item inventory. No mechanism, dependency or behaviour change. |
| context_budget | **concern** | *Changed from pass.* Not because this is always-on — it is a read-on-demand feature doc and the `SessionStart` nudge stays one line in every state. It is a concern because the artifact has outgrown its own structure: **1,317 lines and rising every round (1,270 → 1,289 → 1,317)**; R4–R8 and R10 are orphaned in the outline under R3's and R9's `####` subheadings, so the largest requirement in the spec (~194 lines) is unnavigable; ~120 lines are retrospective rather than buildable, with ADR 0019 named as the migration target in **round 8** and still un-migrated; and the correction narrative has itself started rotting (`:606-609` this round, `:359` now). The house MAY-split remedy is foreclosed by ADR 0017 `:12-13`. ~85 lines of relocation plus four headings resolves it without reopening that ADR. |
| traceability | **pass** | *Improved from concern.* Two of three residues genuinely closed and verified by measurement: the two-item inventory is deleted, and the archive figures are now correct, single-pinned, caveated, and **compared like with like** — I re-derived 317,249 / 184,620 = 1.7184 → 1.72× against both files on disk. Every code citation I sampled is exact. Remaining, noted not held: the sweep's output lands in a commit message, durable and dated but **outside the indexed corpus this feature exists to improve**, and `:359` mis-states its own history by one. |
| success_masking | **concern** | The core question, and the answer is genuinely mixed. Strong: the pre-R10 control is pinned and reproduces; entry 11 is pre-registered as a predicted casualty with the correct reading written down in advance; the spec states plainly that a green golden run is not evidence (11 `must` can fail, 3 `stretch` + 2 `negative` warn and pass regardless); task 4's *"every test asserts the emitted line, not the parsed field"* remains the strongest control in the document. Held at concern for four: **(1)** the spread rule's "third" is undefined and the value-span reading passes the four-large-plus-one-medium sample falsifier (i) calls a falsification — demonstrated above with the real ten-feature census; **(2)** a zero-walked-files run still renders state 8 fresh indefinitely, so nothing in this branch can reproduce the founding failure in the general case; **(3)** silence still equals health and the nudge is the scheduler's only monitor by the diagram's own admission; **(4)** `:1302` still pre-commits a clause failure to R10's noise cost with no control over R9's five queries and no rule for reading the two instruments jointly. |
| intent_drift | **pass** | The diff *is* the four directed edits and their forced consequences — I read it line by line. +28 lines, no new dependencies, no drive-by edits, no scope growth. The deleted inventories were not re-litigated, per instruction. |
| checkpoint | **concern** | Spec committed at `e707767`, clean tree, `phase: planning`, `branch: none` — correct, and the absent implementation branch is by design. **Task 1b's carrier is now closed** (`--allow-empty`, verified verbatim). Held for two carried items: task 7 remains a deliberately coarse seven-part single commit — correctly justified, still the branch's riskiest change in one revert unit — and there is still **no prune path**, so re-excluding the archive after a failing R9 leaves its chunks scored and returned until a multi-hour `--full`. Credit sustained: R7 making `--uninstall` first-class is a real checkpoint control for an artifact living outside the repo where `git revert` cannot reach. |
| audit_trail | **pass** | Dated, attributed user decisions throughout; ADRs 0018 and 0019 both scheduled as tasks; every removal keeps its evidence and its date, including this round's account of why the archive figure was re-measured and why the multiplier is no longer restated. Task 1b's escalation phrase is verbatim and quotable. The one gap — escalation produces an announcement, not an artifact — is recorded under concerns rather than held against this dimension. |

**risk: medium · confidence: high**

Confidence is high because every claim rests on a measurement taken at HEAD: the blob hash confirmed
against the invocation's expected value; `git diff 85baf2d..e707767` read in full; `uv run pytest -m
golden -q` executed; `wc -m` and `wc -c` run on the archive *and* on its denominator, which I located
this round after failing to last round; a per-feature census of all ten features under
`docs/features/` computed both ways and the tertile boundaries derived from it; and every code line
R10 cites read directly. The one figure I report as a proxy — characters standing in for chunk counts
in the tertile example — is labelled as such.

Risk is **medium** and means "one more text pass, not a redesign." Two of the three open items are
one-sentence fixes and the third is relocation of text that is already scheduled to move. The
freshness half I would ship as designed; I have found nothing wrong with its mechanism in two
rounds, and its citation fidelity is the highest I have seen in this repo. The medium mark is for
the acceptance half and for the document's shape: **the guard that grades this branch's only
measurement of R10 is still the least mechanized artifact in a spec whose thesis is "the
observability is the feature," and the spec has now grown past the point where the hand reading it
depends on is reliable.**

## Concerns

1. **"Third" is undefined — value span or rank tertile** — all four surfaces name the population but
   none says which; the value-span reading passes a four-large-plus-one-medium sample that falsifier
   (i) explicitly calls a falsification (demonstrated against the real ten-feature census).
2. **Task 1b's sweep is still not mechanizable** — carrier closed, mechanism not; it must catch a
   defect where four surfaces agree with each other while all four are silent on the same thing.
3. **Task 1b's escalation leaves no artifact** — a spoken `"GATE: Spec change needed"`; the phase
   guard exempts `docs/*`, so the no-in-place-edit premise is discipline, not enforcement.
4. **The spec is 1,317 lines and structurally orphaned** — R4–R8 and R10 sit under R3's and R9's
   `####` subheadings, so the largest requirement (~194 lines) is unnavigable by outline.
5. **~120 lines are obituary, and ADR 0019 was named as their migration target in round 8** — three
   rounds later the 34-line `≥0.30` history, the 24-line archive-size narrative and the thrice-told
   inventory story are all still in the spec.
6. **The correction narrative has started rotting itself** — `:606-609` fixed this round; `:359`
   says the deleted list named "three restatements" where it named two.
7. **R9 still has no control and `:1302` still pre-commits attribution** to R10's noise cost; the
   two instruments are declared distinct and never reconciled.
8. **A run that walks zero files still reads as state 8, fresh, indefinitely** — the founding
   defect's own species; correctly bounded Non-goal, restated because it is the direct answer to
   this loop's central question, not because the bounding is wrong.
9. **Silence still equals health** — absent `status.json`, `chunks == 0`, an unregistered hook and a
   file unreadable mid-rebuild are indistinguishable; the monitor has no monitor.
10. **No prune path** — re-excluding the archive after a failing R9 leaves its chunks scored and
    returned until a multi-hour `index --full`. Disclosed and accepted.
11. **`scheduled-index.log` is unbounded** and is the destination of four of the eight nudge lines.
    Disclosed Non-goal pending task 9's size figure.
12. **Falsifier (c) remains unobservable at task-10c time** — its "20 sessions after it lands"
    window has no scheduled re-read.
13. **The sweep's output lands outside the indexed corpus** — durable and dated in a commit message,
    but not retrievable by the `memsearch` this feature exists to improve.

*Withdrawn from round 10: concern 8 (archive multiplier). My "≥1.73×" mixed a bytes numerator with a
characters denominator; measured like-for-like the spec's 1.72× is correct.*
