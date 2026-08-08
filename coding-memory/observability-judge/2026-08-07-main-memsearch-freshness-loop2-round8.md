# Observability judge — memsearch-freshness (architecting, loop 2 round 8)

- **ts (UTC):** 2026-08-07T06:56:41Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `1a15a77f905a85c837eb1bc0eb8807613d87bfd0`
- **stage:** `architecting` (advisory — does not gate a PR)
- **artifact:** `docs/features/memsearch-freshness.md`, committed and pushed on `main` @ `1a15a77`
  (`origin/main == HEAD`), clean tree, `phase: planning`, `branch: none`
- **test command:** none supplied; no implementation code exists. `execution` is scored on
  design-verifiability against the live tree, not on a run — stated plainly rather than implied.

> **`success_masking` is `fail` this round.** All four round-7 findings were accepted and three are
> genuinely closed. The fourth — the anti-tuning guard added to close the sample-selection hole — is
> **calibrated from a stale index**, and the number it got wrong is the spec's own file, by 4×, in
> the direction that defeats the guard. Two further defects in the same requirement mean R9 has no
> stated pass condition at all. Everything here is cheap to fix; nothing is implemented yet.

## What was changed

Round 8 did four directed things plus one compliance fix. R9's third clause (the score floor) is
**deleted** rather than repaired a third time; what survives is task 8b recording raw scores as a
baseline. The two rank clauses are hardened with a **range-spanning rule** — at least one query
target in the bottom third of the chunk-count range, one in the top, each target's count recorded
beside its result. The hand-maintained list of state-table-derived surfaces is replaced by a
**mechanically swept inventory of 16 surfaces, keyed by section rather than line number**. New
**task 10c** evaluates every falsifier clause (a)–(i) and records held / falsified / not yet
observable. Falsifier clause **(a)** is scoped to "no state 1, 2 or 3 line applies".

## What holds — verified independently, not accepted from the document

| Claim | Verified |
|---|---|
| Clause 3 removed cleanly | ✅ every surviving `floor` / `clause 3` hit (lines 325–362, 978, 1161, 1202) is correctly-scoped **history**; the two live hits at 540 and 1137 are unrelated words. Line 371 updated to "Both of R9's clauses"; task 10b says "there is no third clause"; both no-floor scenarios rewritten. **No orphan, no surface still assuming three clauses.** |
| Clause (a) fix is correct | ✅ re-derived against all eight rows. State 2 does force `last_run > 8h`, so (a) and (g) were genuinely unsatisfiable together; the new scoping resolves it. Excluding state **4** as well would have been unnecessary — a `last_run` older than `STALE_HOURS` is by definition parseable and past, so state 4 cannot apply. The scoping is exactly as tight as it needs to be. |
| The 16-surface sweep is real | ✅ I ran my own `grep` for every state-number reference and every state name. **All six surfaces I named in round 7 are now indexed**, including 612–616's ordering rules. I found no state-number surface missing from the table. The two Design-decisions lines (84, 95) restate state behaviour by name but explicitly defer to `(R3)` — pointers, not duplicates. This is the enumeration that was asked for. |
| Task 10c is a genuine schedule | ✅ `falsifier` now appears in the task list. **8 of 9 clauses are evaluable at 10c time** — (a)(b)(e)(f)(g)(h) as task-4 hook tests, (d) from git history, (i) from the recorded scores. |
| Archive line count | ✅ `wc -l CODING_MEMORY.md` = **3,484**, exact at all three sites (418, 540, 1166). |
| Checkpoint state | ✅ `origin/main == HEAD == 1a15a77`, clean tree, `phase: planning`, `branch: none`. |
| Session-start hook | ✅ one line, in every state — observed live in this session. |

## FAIL — the guard that was added to stop sample-tuning is calibrated from a stale index

R9 now says the five targets must span the corpus size range, and prints the measured spread:
*"Measured 2026-08-07, the eleven indexed feature files run from 6 to 91 chunks … `memsearch-freshness` **14** …"*

I re-ran the real chunker (`split_markdown`) over all eleven files and queried the live index:

| file | spec says | live index | **source, chunked now** |
|---|---|---|---|
| `phase-guard-hook.md` | 91 | 91 | 91 ✅ |
| `replay-harness-base-pin.md` | 70 | 70 | 70 ✅ |
| `verification-marker-gate.md` | 53 | 53 | 53 ✅ |
| `memory-system-split.spec.md` | 31 | 31 | 31 ✅ |
| `git-guard-empty-index.md` | 24 | 24 | 24 ✅ |
| **`memsearch-freshness.md`** | **14** | **14** | **60** ❌ |
| the remaining five | 13/13/9/6/6 | same | same ✅ |

**Ten of eleven figures are exact. The eleventh is the spec's own file, and it is wrong by 4×.**
The figures were not invented — every one matches the **index**. But the index is stale *for this
one file*, because it is the only file being edited each round: `last_indexed` is
`2026-08-06T23:56`, the file's mtime is `2026-08-07 02:55`, and the indexed chunks for it stop at
`line_end = 250` of a **1,214-line** document.

Why it defeats the guard:

- Thirds of the stated 6–91 range fall at **34.3** and **62.7**. At `14` the spec's own file reads
  as a **bottom-third** target. At its true `60` it is mid-to-top.
- Target selection happens in **task 8**, guided by this table. An implementer filling the
  "one in the bottom third" slot with `memsearch-freshness` on the strength of `14` would put a
  60-chunk file in the hard slot — **the exact sample-tuning the rule was written to prevent,
  performed while complying with it.**
- The figure is also *inherently* unstable: this file grew 58 → 60 chunks during the round. Any
  static count for it is stale on write. R9 should derive the counts at task-8 time from the
  post-task-7 rebuild, not embed a round-8 table.
- **Partial mitigation, credited:** task 8b records each target's real count beside its result, so a
  reader who recomputes the thirds can catch it after the fact. But the table they would check
  against is the wrong one, so the comparison confirms the error rather than exposing it.

**The irony is load-bearing, not decorative.** A spec whose entire thesis is *"the index lies about
its own freshness"* calibrated its one anti-gaming guard by reading the index instead of the source.
This is the fourth consecutive version of R9's bar that cannot do its job: round 5 set a bar 6× the
scorer's ceiling (could only fail), round 6 a floor drawn from the run it grades (could only pass),
round 7 a guard on that guard, round 8 a guard fed a stale number.

### Two more defects in the same requirement

**1. The spread rule exists in two incompatible strengths, and the enforceable one is the weak one.**

| Surface | What it says |
|---|---|
| R9 (325–327) | ≥1 target in the bottom third **and** ≥1 in the top third — **strict** |
| Scenario (972–976) | identical to R9 — **strict** ✅ |
| Task 8b (1160) | "confirm the five targets are **not all drawn from one third**" — **weak** |
| Falsifier (i) (1015) | "with **all five** … from the same third" — **weak** |
| Task 10b (1198) | records the counts, no spread check at all |

Four top-third targets plus one middle-third target **passes task 8b and passes falsifier (i), and
violates R9 and the scenario.** The falsifier is the surface task 10c evaluates, so the version that
gets graded is the weak one. Round 7's concern 6 — *"R9 has no derived-surfaces index despite now
governing four surfaces"* — was not closed, and **this is its first concrete casualty**: the round
enumerated the surfaces of the state table and, in the same edit, created a second multi-surface
authority with no index and immediately drifted it.

Related, same edit: the counts are listed **per file** (`memory-system-split` 6 and
`memory-system-split.spec` 31 separately) while R9's membership rule is **per feature** (`F.md`
**or** `F.spec.md`). A query naming `memory-system-split` faces **37** competing chunks, not 6.
Picking it as the bottom-third target on the strength of `6` understates by 6×. Round 6's "two units
conflated" finding, recurring.

Also: "third" is undefined — by **range value** (bottom third ≤ 34.3 catches **7 of 11** files) or
by **distribution tercile** (bottom ≈ 6, 6, 9, 13). The ambiguity leaks in the permissive direction.

**2. R9 says it gates the branch, and states no pass condition.**

R9 (313): *"both can genuinely fail, and both gate this branch."* Nowhere does the spec say **how
many of the five queries must pass**. Every surface says "record pass/fail **per query**". A 1-of-5
result satisfies R9, both scenarios, task 8b, task 10b and falsifier (i) — recorded, honest, and
non-blocking. And *What success means* (1101–1103) states outright that *"a reliably fresh index that
still retrieves noise is a legitimate and useful outcome of this branch."*

So R9 is a **recording** requirement wearing a gate's sentence. This was survivable while clause 3
absorbed attention; now that "the branch rests entirely on two rank clauses," the aggregate bar is
the gate — and it does not exist. This is the same species as the (a)/(g) contradiction the round
just fixed: a requirement and its success definition disagreeing, with nothing resolving them.

## On length and scar tissue — the caller asked directly, so here is the measurement

**The notes do not outweigh the spec, and I am not recording length as a finding.** Counted, not
estimated: **12 ⚠️ blocks spanning 188 lines = 15.5%** of 1,214; 19 lines mention a round number.
Sibling feature docs run **1,166 / 1,303 / 1,779**, so this is mid-pack, and it is a feature doc, not
always-on content. At ~20k tokens it is more than one comfortable pass and the one-canonical-file
`MAY`-split threshold is met — worth considering, not required.

The honest finding is about **shape, not volume**: R9 now spends ~34 lines (329–362) narrating three
dead versions of a clause that no longer exists — a third of the requirement's text is the obituary
of a non-requirement. The `≥0.30` ceiling derivation is still load-bearing (task 10b cites it to void
old readings); the round-6/round-7 narrative is pure review history. **Durable record now, scar
tissue after landing** — unchanged from round 7, one round more overdue, and the migration target
(ADR 0019 / session memory) is already named.

One small self-referential slip: the sweep's provenance line says *"across all 1,163 lines"* — the
document is 1,214. A structural copy of the document, inside the paragraph arguing that structural
copies of the document go stale.

## Carried, unchanged

- **A run that walks zero files still reads as state 8, fresh, indefinitely** — named twice as a
  bounded Non-goal. Naming is not removing.
- **Silence still equals health** — absent `status.json`, `chunks == 0`, an unregistered hook and an
  unreadable file mid-rebuild all render as nothing at all.
- **No prune path.** `git revert` undoes the config, not the vectors; the exit is a multi-hour
  `index --full`.
- **Task 9's stop-and-ask still has no falsifier clause** (round-7 concern 4, unclosed) —
  `RUN_MAX_HOURS` can be set without the cold-run measurement and nothing records that it was.
- **`RUN_ABANDON_HOURS` (24h)** still clears an unmeasured cold-run duration.
- **Three copies of `3,484`**, synced rather than deduplicated; only one carries the "floor" caveat.
- **Falsifier clause (c)** is genuinely unobservable at task 10c time — its "20 sessions after it
  lands" scope has no scheduled re-read, and Non-goals rule out any later cadence.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | **pass** | All four directed findings and the compliance fix are present and correctly executed: clause 3 deleted (not repaired), spread rule added, task 10c added, 16 surfaces mechanically enumerated, clause (a) scoped. Nothing added beyond direction. |
| execution | **concern** | The state-table half is excellent and independently verified. The R9 half is not: the new guard's calibration is stale, its rule exists in strict and weak forms across four surfaces, its units are per-file where membership is per-feature, "third" is undefined, and no aggregate pass condition exists. Two round-7 concerns remain open (R9 has no derived-surfaces index; task 9's stop-and-ask has no falsifier clause). |
| trajectory | **concern** | Down from **pass**, narrowly and specifically. The deletion decision is the best call of the loop — three attempts at one clause *is* the argument for deleting it — and recording the round's own line-number failure inside the table it produced is exemplary. The downgrade is this: the round applied *enumerate-don't-patch* to the surface it was cited on, and in the same edit created a second multi-surface authority with no index, which drifted immediately. The lesson was applied as an instance fix, not as a method — the exact failure its own commit message names. |
| regression | **pass** | Documentation-only; no mechanism, dependency or behaviour change. The removal is clean — I grepped every surviving mention and read each in place; none is orphaned. The state-table edit re-derived row by row: (a)'s new scoping is correct and minimal. |
| context_budget | **pass** | Session-start hook is one line in every state (observed live). 1,214 lines / ~20k tokens is mid-pack against siblings at 1,166 / 1,303 / 1,779; ⚠️ blocks are 15.5% of the document, measured. Not always-on content. Named cost, not a finding. |
| traceability | **concern** | Down from **pass**, for one root cause. The correction record is genuinely excellent — every removal kept in place with its evidence, dated, attributed, and it caught a real bug this round. But the chunk-count table is stamped *"Measured 2026-08-07"* **without recording what was measured**, and the method (reading the live index rather than chunking the source) silently produced a figure 4× wrong for the spec's own file. Recording the method *is* traceability; had it been recorded, the staleness would have been self-evident. |
| success_masking | **fail** | The single acceptance measurement for the branch's riskiest change can report a clean result while measuring nothing, by three independent routes: **(1)** the anti-tuning guard is calibrated from a stale index and misplaces the spec's own file from the top third into the bottom third; **(2)** the guard's enforceable form — falsifier (i), which task 10c grades — is weaker than R9's stated rule, so 4-top-third-plus-1-middle passes falsification while violating the requirement; **(3)** R9 claims to gate the branch and states no aggregate pass condition, while *What success means* blesses a noisy result as legitimate. Fourth consecutive round in which R9's bar cannot do what it says. |
| intent_drift | **pass** | The removal is clean — verified by grep and by reading every remaining hit, not by trusting the diff. Only the four directed changes, the compliance fix, and their forced consequences. No drive-by edits, no new dependencies, no scope growth. |
| checkpoint | **concern** | Spec committed and pushed on `main` @ `1a15a77`, `origin/main == HEAD`, clean tree; the absent implementation branch is by design (not a finding). Held at concern for two unchanged structural gaps: nothing reverts embedded chunks (the exit is a multi-hour `--full`), and task 7 remains a deliberately coarse seven-part single commit — correctly justified, still the branch's riskiest change in one revert unit. |
| audit_trail | **pass** | Dated, attributed user decisions; the round-8 commit message is ADR-quality and states its own reasoning honestly; ADR 0018 and 0019 both mandated. Round 7's gap (the floor decision omitted the third option) is moot — the third option was taken. Minor: deleting a requirement that survived three review rounds is arguably ADR-worthy on its own, and lives only in the spec and the commit message. |

**risk: high · confidence: high**

Confidence is high because every claim rests on a measurement I took: `split_markdown` run over all
eleven feature files (60 vs. the stated 14), the live `memory.db` queried directly (14 chunks,
`max(line_end) = 250`), `status.json`'s `last_indexed` compared against the file's mtime, `wc -l` for
3,484 and 1,214, an independent `grep` sweep for every state-number and state-name reference, a
scripted census of the ⚠️ blocks, and `git rev-parse` for push state. I re-derived clause (a) against
all eight table rows before crediting it.

Risk is **high**, and it means "do not let task 8 run against this spec," not "abandon the design."
The freshness half — the state table, the eight rendered lines, the sixteen enumerated surfaces, the
hook-test falsifier clauses — is the strongest it has been in the loop and I found nothing wrong with
it. The high mark is for the acceptance half: the branch's only measurement of whether indexing a
3,484-line archive damaged retrieval has no stated pass condition and one guard fed a wrong number.
If it lands as written, R9 goes green while measuring nothing — precisely the failure this feature
exists to fix. Every item is a text edit, in `phase: planning`, before any code exists.

## Concerns

1. **[FAIL] R9's chunk-count table is read from a stale index; `memsearch-freshness` is listed at 14
   chunks and is actually 60** — ten of eleven figures match the index exactly, the eleventh is the
   spec's own file, and the index for it stops at line 250 of 1,214. At 14 it reads as a bottom-third
   target; at 60 it is mid-to-top. Task 8 picks targets from this table, so the "one in the bottom
   third" slot can be filled by a top-third file **while complying with the rule written to prevent
   exactly that**. Fix: derive counts at task-8 time from the post-task-7 rebuild, from source.
2. **The spread rule has a strict form and a weak form, and the weak one is what gets graded** — R9
   and the scenario say "≥1 bottom third **and** ≥1 top third"; task 8b says "not all from one
   third"; falsifier (i) says "all five from the same third". Four top-third targets plus one middle
   passes the falsifier and fails R9. Task 10c grades the falsifier.
3. **R9 states no aggregate pass condition** — "both gate this branch", but nothing says how many of
   five must pass, and *What success means* calls a noisy result legitimate. A 1-of-5 result complies
   with every surface. The gate is a recording requirement.
4. **R9 still has no derived-surfaces index** — round-7 concern 6, unclosed, and now demonstrably the
   cause of concern 2. The enumerate-don't-patch discipline was applied to the state table only.
5. **Per-file counts under a per-feature membership rule** — `memory-system-split` is listed as 6 and
   31; a query naming that feature faces 37 competing chunks. Round 6's "two units conflated",
   recurring in the fix for round 7's finding.
6. **"Third" is undefined** — by range value, "bottom third" (≤34.3) admits 7 of 11 files; by
   distribution tercile it admits 4. The ambiguity is permissive.
7. **The chunk-count table is stamped "Measured 2026-08-07" with no record of the method** — the
   method is what went wrong, and recording it would have exposed the staleness immediately.
8. **Task 9's stop-and-ask still has no falsifier clause** — round-7 concern 4, unclosed.
   `RUN_MAX_HOURS` can be set without the cold-run measurement with nothing recording that it was.
9. **Falsifier clause (c) is unobservable at task 10c** — its "20 sessions after it lands" scope has
   no scheduled re-read, and Non-goals rule out any post-landing cadence. 8 of 9 clauses are
   evaluable; this one will be honestly ticked "not yet observable" forever.
10. **R9 devotes ~34 lines to the history of a deleted clause** — a third of the requirement is the
    obituary of a non-requirement. Load-bearing in part (the `≥0.30` ceiling voids old readings);
    the rest belongs in ADR 0019 or session memory at landing.
11. **The sweep's own provenance line says "all 1,163 lines"; the document is 1,214** — a structural
    copy inside the paragraph arguing against structural copies.
12. **Three copies of `3,484`**, exact today, synced rather than deduplicated; only one caveated.
13. A run that walks zero sources still reads as **state 8, fresh**, indefinitely — bounded Non-goal,
    correctly pointed; the masking is live in a feature built to stop the index lying about freshness.
14. **Silence still equals health** — absent `status.json`, `chunks == 0`, an unregistered hook and an
    unreadable status file mid-rebuild are indistinguishable. No heartbeat; structural, carried.
15. **No prune path** — re-excluding `CODING_MEMORY.md` after a failing R9 leaves its chunks scored
    and returned until a multi-hour `index --full` (disclosed and accepted).
16. **`RUN_ABANDON_HOURS` (24h)** still clears an unmeasured cold-run duration; past it the stale line
    hands a possibly-live run the index command with no lock. Gated by concern 8's unbacked step.
17. **`scheduled-index.log` is unbounded** and is the destination of four of eight nudge lines
    (disclosed as a Non-goal; rotation needs task 9's size figure).
