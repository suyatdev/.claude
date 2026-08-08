# Observability judge — memsearch-freshness (architecting, loop 2 round 9)

- **ts (UTC):** 2026-08-07T11:36:32Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `ceadcf060ba8ea7fd50cb6ace14448ef6db22a43`
- **stage:** `architecting` (advisory — does not gate a PR)
- **artifact:** `docs/features/memsearch-freshness.md`, 1,270 lines, committed on `main` @ `254cb98`,
  blob `60199bd97edddf6e50e99c047a2a3573b34ffb40` (confirmed via `git rev-parse HEAD:<path>`)
- **checkpoint:** clean tree, `origin/main == HEAD == ceadcf0`, `phase: planning`, `branch: none`
- **test command:** none supplied and no implementation code exists. I ran what *is* runnable —
  the golden retrieval suite and three live retrieval probes — and say plainly below what that
  does and does not license.

> **Round 8's `success_masking: fail` is closed.** All three routes that made it fail are gone:
> the anti-gaming rule pins no counts and computes from source; the spread rule is strict in all
> four places; R9 now has an aggregate pass mark. **Risk drops high → medium.** What remains is
> one class of defect, three instances: a measurement whose *reading* is not licensed by its
> *design*, and an index-of-itself built by the method the previous round was faulted for.

## What was changed

Think of the memory index as a smoke detector that stopped chirping. For 19 days it reported
"all good" while its battery was flat, and nothing anywhere checked. This round-9 spec is the
design for two things: a timer that re-tests the detector every 6 hours, and — first, deliberately
— **a display that tells you the detector's real state** rather than a number it remembers from
a fortnight ago.

Round 9 itself did five text edits: removed every pinned chunk count from the anti-gaming rule
(compute from the source files at task-8 time instead of asking the stale index); made one strict
version of the sample-spread rule appear in all the places that state it; gave the retrieval bar an
explicit pass mark (**all five** queries, not one of five); added an inventory of the seven places
that restate that bar; and bounded design decision 5 to the first `RUN_ABANDON_HOURS`.

## Does it do what you wanted?

Mostly yes, and the freshness half is genuinely strong. I verified rather than accepted:

| Claim | How I checked | Result |
|---|---|---|
| The bar can actually **pass** | Live probe, `k=6`: *"why was the stale phase guard rule text corrected"* | A **6-chunk** feature file took the **top hit and 3 of 6** — clause 1 and clause 2 both reachable for the smallest target ✅ |
| The bar can actually **fail** | Live probe: *"what does the git guard do when the index is empty"* | A **24-chunk** feature file got **1 hit, not top** — **both clauses fail today** ✅ Genuinely two-sided |
| No repeat of the `≥0.30` defect | Read `search.py` end to end | `search()` has **no per-source dedup** (`:66-82`), results are chunk-level and sliced to `k` — so "≥2 hits from one file" is not unsatisfiable by construction ✅ |
| The stated scorer ceiling | Probe top score vs. `2 × 1/61 × 1.5` | Observed **0.049180** against a computed **0.04918** — task 8b's ceiling figure is exact ✅ |
| Round 9's reason for deleting the counts | `split_markdown` over source vs. `memory.db` | Index says this spec is **14 chunks**; source says **62**. The recalibration was necessary and is correct ✅ |
| The spread rule is now strict everywhere | grep for `third` | R9:355, scenario:1025, falsifier (i):1065, task 8b:1215 — **all four strict** ✅ Round-8 concern 2 closed |
| The pass mark exists | grep `all five` | R9:331 — *"passes iff all five queries satisfy both clauses"* ✅ Round-8 concern 3 closed |
| The state table's 17-surface inventory | Independent `grep` for every `state N` / `states N` | **Every hit maps to an inventoried row. No orphan.** ✅ |
| ~25 `file:line` citations | Read each in place | `config.py:56,57-60` · `chunk.py:111` · `status.py:27` · `db.py:103,112-120,121,125,156` · `index.py:57,67,73,74,100,125-127,135-137` · `cli.py:39,66` · `search.py:19,64,80` · `pyproject.toml:23` · `test_config.py:42,48` · `test_index.py:58,84,93,105,106,117,135,136,148,149,160,161` · `README.md:22` — **all exact** ✅ |
| The plan sweep | `grep -n CODING_MEMORY` on the 3,079-line plan | **14 hits**, and the four named as asserting the retired rule (19, 2828, 2890, 2942) are exactly the four that do ✅ |
| Toolchain table | Ran each | bash 3.2.57 · python3 3.9.6 · uv 0.11.28 · no `timeout` binary · `plutil`/`launchctl` present · `fromisoformat` **rejects `Z`, parses `+00:00`** · **`launchctl getenv PATH` is empty** — every row true ✅ The `PATH` key really is load-bearing |
| Live state of the index | `status.json` + sqlite | `sources: 911`, `187 @ 2026-07-18`, `724 @ 2026-08-06` — **exactly** as the Background states ✅ |
| The nudge stays one line | Read `hooks/memsearch-nudge.sh` + this session's own SessionStart | One line, registered at `settings.json:71` ✅ |

**The eight states are distinguishable and complete.** I walked every row against every scenario:
first-match-wins leaves no overlap, all eight are reachable (state 4 is the real post-upgrade state,
since today's `status.json` has neither new field), the decay path from 1/2 always lands in 3 or 5
(never a gap), and a future `run_started` cannot pin state 1. The strongest single control in the
document is **task 4's "every test asserts the emitted line, not the parsed field"** — that is
precisely the written-but-unread defect this feature exists to fix, closed at the right layer.

## What could go wrong / what I'm unsure about

**1. The one measurement that decides the risky half cannot support the conclusion it is given.**
Task 10(b) says *"A failure of either clause is a real result about R10's noise cost"* (`:1256`).
But the five queries are **authored after R10 lands** (task 8 is explicitly ordered after task 7)
and **run once, only afterwards**. There is no before-measurement of those queries, and the frozen
Baseline (`:430`) is a different query set on an index the session-28 rebuild destroyed. My probes
show the top competitors for feature-file queries are already `coding-memory/observability-judge/*`
verdict files at **weight 1.5** — the *same* tier as feature files, higher than the archive's
proposed 1.0. Three of six hits on the git-guard probe were judge files. So a red R9 is at least as
likely to be pre-existing crowding as archive noise, and the spec pre-commits to reading it as
archive noise. Analogy: weighing yourself once *after* dinner and calling the number the weight of
the dinner.

**2. Free control available, not scheduled.** I ran `uv run pytest -m golden -q`:
**16 passed in 1.75s**, at `ceadcf0`, on the pre-R10 corpus. That is exactly the before-picture
task 10(a) needs to attribute its after-picture — and nothing in the spec says to capture it. It
cost me two seconds.

**3. The surface that does the grading does not carry the pass mark, and the index says it does.**
R9's derived-surface table (`:350`) lists *"Task 10(b) | both clauses, **the pass mark** | derived ·
agrees"*. Task 10(b) (`:1251-1254`) says only *"record pass/fail per query"*. `grep "all five"`
returns **exactly one hit in the whole document** — R9:331. So a 3-of-5 result gets written under
Verification as three passes and two failures, with nothing at the point of grading saying the
branch missed its bar. Milder than round 8 (the bar now exists), but the inventory built to catch
this drift is asserting an agreement that is not there.

**4. R9's own inventory was written from a reading, not a sweep — the exact method the spec says
regenerates R3's table.** Applying R3's own inclusion standard (which admits Design decisions that
merely *defer* to R3), at least four surfaces restate R9 and are missing: R10's *"**R9 is the
instrument**: it scores feature-file retrieval at `k=6` … R9 fails and says so"* (`:606-608`); the
Non-goal *"R9 measures once, at landing"* (`:1144-1145`); the Non-goal *"R9 measures whether the
whole-file version actually degrades retrieval"* (`:1119-1123`); and *What success means*
(`:1152-1156`), which R9 has to argue against by name at `:334-337`. **All four currently agree** —
this is a completeness defect, not a contradiction. But an index that is 6-of-7 accurate and misses
4 surfaces cannot do its job on the *next* edit, which is the whole reason it exists.

**5. The counting unit is per-file; the competition unit is per-feature.** Membership is per-feature
— `docs/features/F.md` **or** `F.spec.md` (`:414-416`). Task 8b says *"each target **feature file's**
chunk count from the source file"* (`:1212`). Measured live: `memory-system-split.md` = **6** chunks,
`memory-system-split.spec.md` = **31**, feature total = **37**. Range across the ten features is
**6–91**, so bottom third is ≤34.3: at **6** that feature fills the "hard, small target" slot; at its
true **37** it is mid-range. **The sample can still be softened by 6× while complying with the rule
written to prevent it.** Round 8's concern 5 was answered by deleting the numbers, not the ambiguity.

**6. The population the "range" is drawn from is never stated.** Ten feature files span 6–91, so top
third ≥62.7 admits exactly **two** candidates (70, 91) — the rule genuinely bites, which is good. But
if "corpus size range" means the whole indexed corpus, whose largest doc the spec itself puts at 121
chunks (`:592`), the top third moves to ≥82 and admits **one**. Both readings are available. (Note,
without irony: this spec is **62** chunks — 0.7 below its own top-third line.)

**7. The spec's own thesis, one field over: `3,484` has already rotted.** Three copies (`:468`,
`:590`, `:1222`); only `:590` carries the "treat as a floor" caveat. `wc -l` today: **3,535**. It
grew 51 lines inside the round that deleted pinned chunk counts for exactly this reason. No
acceptance criterion depends on it, so this is a smell rather than a break.

**8. Carried, unchanged, structural.** A run that walks **zero files** still renders as state 8,
*fresh*, indefinitely — the same species as the original defect, correctly named as a bounded
non-goal, still live. **Silence still equals health**: absent `status.json`, `chunks == 0`, an
unregistered hook and a file unreadable mid-rebuild are all indistinguishable from a healthy quiet.
**No prune path** — re-excluding the archive after a failing R9 leaves every chunk already written
scored and returned until a multi-hour `--full`. **Task 9's stop-and-ask has no falsifier clause**
(round-7 concern 4, round-8 concern 8, still open): `RUN_MAX_HOURS`/`RUN_ABANDON_HOURS` can be kept
without the cold-run measurement and nothing records that they were. *(One round-8 note I now
retract: `RUN_ABANDON_HOURS` having no explicit stop-and-ask trigger is **not** a hole — any run
threatening 24h necessarily crosses the 6h trigger first, so it is covered transitively.)*
**Falsifier (c)** remains unobservable at task-10c time. **`scheduled-index.log` is unbounded** and
is the destination of four of the eight lines.

## What I'd double-check before merging

These are all text edits, in `phase: planning`, before a line of code exists. In rough order of value:

1. **Capture the pre-R10 control.** Record today's `-m golden` result (16 passed @ `ceadcf0`) in the
   spec or under Verification, so task 10(a)'s after-picture has a before-picture. Two seconds.
2. **Either give R9 a control, or soften its conclusion.** A post-hoc re-score of the five queries
   with `archive_doc` chunks filtered out costs no reindex and turns task 10(b) into a real
   before/after. If that is out of scope, change `:1256` to say what the measurement can actually
   support — that a failure is a result about *retrieval*, attribution unresolved.
3. **Put the pass mark where the grading happens** (task 10(b)), and fix or re-scope R9's inventory
   row that claims it is already there.
4. **Regenerate R9's inventory by sweep**, the way R3's table is regenerated — the four omissions
   above are the test case.
5. **State the counting unit as per-feature** (`F.md` + `F.spec.md` summed) and name the population
   the "range" is computed over. `memory-system-split` at 6-vs-37 is the live counterexample.
6. Caveat or delete the two uncaveated `3,484`s (now 3,535).
7. Consider whether task 9's stop-and-ask earns a falsifier clause — third round it has been raised.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | **pass** | All five directed round-9 changes are present and correctly executed; nothing added beyond them. Reporting-before-scheduling ordering is the right call and is argued, not assumed. Scope correctly stops at parent item 5. |
| execution | **concern** | No code exists; scored on design-verifiability against the live tree. The freshness half is excellent and independently verified — eight states complete, reachable, non-overlapping; ~25 citations exact; toolchain table true row by row; task 4's assert-the-emitted-line rule is the strongest control here. The acceptance half is not: the grading surface carries no pass mark, R10-attribution has no control, the counting unit is ambiguous, and a free pre-change baseline goes uncaptured. |
| trajectory | **pass** | Up from concern. Every round-9 fix is correct and correctly *reasoned*: the anti-gaming recalibration is exactly right (I confirmed index 14 vs. source 62), the strict-wording unification landed in all four places, and the deleted-clause history is honestly kept. I considered holding this at concern for R9's inventory being written by reading rather than sweep — but that is a completeness gap causing no current disagreement, not unsound reasoning, and it is materially better than round 8's *no index at all*. Recorded under traceability instead. |
| regression | **pass** | Documentation-only; no mechanism, dependency or behaviour change. The implementation it *designs* is enumerated with verified exactness — I checked all twelve `test_index.py` line/assertion pairs, both `test_config.py` targets, `config.py:56`'s must-survive line, and the plan's 14-hit sweep. Nothing orphaned. |
| context_budget | **pass** | Feature doc, not always-on content. The SessionStart nudge is one line in every state — observed live in this session. 1,270 lines is mid-pack against siblings (1,166 / 1,303 / 1,779). Grew +56 this round; R9 still spends ~34 lines on the obituary of a deleted clause (round-8 concern 10, open, migration target already named). Named cost, not a finding. |
| traceability | **concern** | The decision record is exemplary and round 8's specific gap is **closed** — the anti-gaming rule now records its *method* ("computed from source at task-8 time, never read from the index"), which is exactly what was missing. Held at concern for the document's index-of-itself: R9's table asserts Task 10(b) restates the pass mark when it does not, omits four surfaces that restate R9, and two of three `3,484` copies are uncaveated and now stale by 51 lines. A map that misdescribes the territory is a traceability defect. |
| success_masking | **concern** | **Up from `fail`.** All three round-8 routes are genuinely closed, verified independently. What remains: **(1)** task 10(b) records per-query pass/fail with no aggregate verdict, so a 3-of-5 lands under Verification looking recorded rather than failed; **(2)** R9's single post-change measurement is pre-committed to a causal reading (*"a real result about R10's noise cost"*) that its design cannot license — no control, and my probes show the dominant crowders are already-1.5-weighted judge files, not the archive; **(3)** a free pre-R10 golden baseline exists and is unscheduled. Carried: a zero-file run still reads as fresh; silence still equals health. Crucially, the bar itself is now genuinely two-sided — I made it pass on a 6-chunk file and fail on a 24-chunk one. |
| intent_drift | **pass** | Only the five directed edits and their forced consequences. No drive-by changes, no new dependencies, no scope growth. Verified by reading the round-9 diff surface, not by trusting the summary. |
| checkpoint | **concern** | Spec committed and pushed, `origin/main == HEAD == ceadcf0`, clean tree; absent implementation branch is by design, not a finding. Held for two unchanged structural gaps: nothing reverts embedded chunks (the exit is a multi-hour `--full`), and task 7 remains a deliberately coarse seven-part single commit — correctly justified, still the branch's riskiest change in one revert unit. Credit where due: R7 making `--uninstall` first-class is a real checkpoint control for an artifact that lives outside the repo where `git revert` cannot reach. |
| audit_trail | **pass** | Dated, attributed user decisions throughout; ADR 0018 and 0019 both mandated as tasks; every removal kept in place with its evidence and its date. The round-9 correction record — *"a spec whose thesis is 'the index lies about its freshness' calibrated its anti-gaming guard by asking the index instead of the files"* — is ADR-quality self-reporting. |

**risk: medium · confidence: high**

Confidence is high because every claim above rests on a measurement I took: `split_markdown` run over
all eleven feature files, three live `k=6` retrieval probes against the real index, the golden suite
executed (`16 passed`), `memory.db` queried directly for per-feature chunk counts and `indexed_at`
distribution, `status.json` read, `wc -l`, `launchctl getenv PATH`, `python3 -VV` and a live
`fromisoformat` check, an independent `grep` sweep for every state reference, and roughly 25
`file:line` citations opened and read in place.

Risk is **medium**, down from high, and it means "these are worth one more text pass, not a redesign."
Round 8's `fail` is honestly closed — I checked each route rather than accepting the round's own
account. The freshness half is the strongest artifact in this loop and I found nothing wrong with its
mechanism. The medium mark is for the acceptance half: the branch's only measurement of whether
indexing a 3,500-line archive damaged retrieval is a single post-change reading with no control,
pre-committed to a causal conclusion, graded by a task that does not state the bar. It will produce a
number. Whether that number means what the spec says it means is not yet established — which, for a
feature whose thesis is *"the observability is the feature,"* is the finding that matters.

## Concerns

1. **R9 has no control, and task 10(b) pre-commits to a causal reading it cannot support** — the five
   queries are authored after R10 lands (task 8 after task 7) and run once, post-change; the frozen
   Baseline is a different query set on a destroyed index. Live probes show the dominant competitors
   for feature-file queries are `coding-memory/observability-judge/*` files at weight **1.5** — above
   the archive's proposed 1.0 — so a failure is at least as likely to be pre-existing crowding.
2. **A free pre-R10 control exists and is unscheduled** — `uv run pytest -m golden -q` is **16 passed**
   at `ceadcf0` today. Task 10(a) reads its post-change run as evidence about R10 with no before-picture.
3. **The grading surface carries no pass mark while the index says it does** — `grep "all five"`
   returns exactly one hit (R9:331); task 10(b) says only "record pass/fail per query"; R9's table
   (`:350`) claims task 10(b) restates the pass mark.
4. **R9's derived-surface inventory was written from a reading, not a sweep** — at least four
   surfaces restate R9 and are missing (`:606-608`, `:1119-1123`, `:1144-1145`, `:1152-1156`). All
   currently agree; the defect is that the index cannot catch the *next* edit.
5. **Counting unit per-file, competition unit per-feature** — `memory-system-split` is 6 chunks
   (`.md`) or 37 (both files, measured live). At 6 it fills the bottom-third slot; at 37 it is
   mid-range. The sample can be softened 6× while complying. Round-8 concern 5, not closed.
6. **The population defining the "range" is unstated** — over the ten feature files (6–91) the top
   third admits two candidates; over the whole indexed corpus (largest doc 121 chunks per `:592`) it
   admits one.
7. **`3,484` has rotted to 3,535 within the round**; two of three copies uncaveated (`:468`, `:1222`).
   No bar depends on it, but it is the spec's own thesis one field over.
8. **Task 9's stop-and-ask still has no falsifier clause** — round-7 concern 4, round-8 concern 8,
   open. The run constants can be kept without the cold-run measurement and nothing records it.
   *(Retracted from round 8: the missing explicit `RUN_ABANDON_HOURS` trigger is covered transitively
   — any run threatening 24h crosses the 6h trigger first.)*
9. **Falsifier clause (c) remains unobservable at task-10c time** — its "20 sessions after it lands"
   scope has no scheduled re-read and Non-goals rule out any post-landing cadence.
10. **A run that walks zero files still reads as state 8, fresh, indefinitely** — bounded Non-goal,
    correctly pointed; still the same species as the defect the feature exists to fix.
11. **Silence still equals health** — absent `status.json`, `chunks == 0`, an unregistered hook and a
    file unreadable mid-rebuild are indistinguishable. No heartbeat. Structural, carried.
12. **No prune path** — re-excluding the archive after a failing R9 leaves its chunks scored and
    returned until a multi-hour `index --full`. Disclosed and accepted.
13. **`scheduled-index.log` is unbounded** and is the destination of four of the eight nudge lines;
    rotation needs task 9's size figure. Disclosed Non-goal.
14. **R9 still devotes ~34 lines to the history of a deleted clause** — round-8 concern 10; the
    `≥0.30` ceiling derivation stays load-bearing, the round-6/7 narrative belongs in ADR 0019.
15. Marginal: **R5 (`:291-293`) restates state 6's condition** ("absent, non-integer … *unknown*,
    never zero, per R3") and is not in R3's 17-entry inventory. Out of scope by the table's stated
    rule ("every surface *naming* a state"), in scope by the standard that admitted Design decisions.
    Noted for the next sweep, not asked for as a fix.
