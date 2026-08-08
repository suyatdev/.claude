# Observability judge — memsearch-freshness (architecting, loop 2 round 7)

- **ts (UTC):** 2026-08-07T05:37:22Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `a7b95e77b4a51f25da5d055366b096fa6c7902e6`
- **stage:** `architecting` (advisory — does not gate a PR)
- **artifact:** `docs/features/memsearch-freshness.md`, committed and pushed on `main` @ `a7b95e7`
  (`origin/main == HEAD`), clean tree, `phase: planning`, `branch: none`
- **test command:** none supplied; no implementation code exists. `execution` is scored on
  design-verifiability against the live tree, not on a run — stated plainly rather than implied.

**No dimension is `fail`.** Round 6's three findings on R9 are closed, and the compliance judge's two
are closed. `trajectory` rises to **pass**. What follows is one notch down, and the sharpest item is
a *consequence* of this round's fix rather than something it failed to fix.

## What was changed

Round 7 did six things, all directed by the two judges plus one self-caught citation error. R9 now
says outright that a floor set from this run cannot fail this run and that clause 3 is a recorded
baseline, not a verdict; a query's result is the conjunction of the clauses that bind, never a bare
`pass`; falsifier clause (i) names the skip as a falsification; a second scenario covers the no-floor
path; R2 defers its wording to the state table and points at its own zero-files exception; and the
stale `3,433` is synced to `3,484`.

## Do the fixes close the gaps, or merely describe them?

**Four close. One describes, and describing it is the right call for this branch. One is closed at
three of four surfaces.** Everything below is re-derived from the live tree, not accepted from the
document.

| Round-7 claim | Verified independently |
|---|---|
| Weight multiply is `search.py:80`, not `:78` | exact ✅ — `:80` is `r["score"] = round(base_score * r.pop("weight"), 6)` |
| `RRF_K = 60` at `search.py:19`; fusion at `:61-64` | exact ✅ — `:64` is the `1.0 / (RRF_K + rank + 1)` accumulation |
| Archive is **3,484** lines, synced in all three places | exact ✅ — `wc -l` = 3,484; lines 380, 502, 1117 all read 3,484 |
| R2's guarantee ("a missing/unparseable/future-dated `last_run` never yields a fresh line") | ✅ **holds against all eight rows** — an unusable `last_run` is caught by state 4 before state 8 can be reached, so `fresh` is genuinely unreachable. The old pinned line contradicted states 1–3; the fix is correct, not just softer. |
| The Contracts classification table was deleted in round 5 | ✅ — lines 609-611 now carry a pointer, not a table |
| Spec 1113 → 1163 lines | exact ✅ |

### 1. Clause 3 — honest now, but the machinery outlived its own obituary

The disclosure at lines 303-315 is unusually good. It concedes every premise: the floor cannot fail
the run it is set from, R9 is measured once, so on the only day clause 3 is evaluated it is
guaranteed to pass. It then draws the conclusion "clause 3's value is as a recorded baseline for a
future change."

**Follow that conclusion one step further and the step disappears.** Task 8b has two halves:

- **(i) Measure and record the raw scores** — "every hit's score alongside whether it belongs to the
  named feature, the raw numbers, unrounded, with no pass/fail attached." This is genuinely
  valuable, needs no human decision, cannot be gamed, and cannot fail. **This is the baseline.**
- **(ii) A human picks a floor from those numbers** — this is clause 3. It produces a number
  *strictly less informative* than the raw data already recorded in half (i), it cannot fail this
  run, and the Non-goals rule out any cadence that would give it a future run to grade.

So the value the spec claims for clause 3 is delivered entirely by half (i), which is not clause 3.
Keeping half (ii) costs a blocking human gate, a falsifier clause whose sole purpose is to detect
skipping that gate, a second Gherkin scenario, a reporting convention, and ~35 lines. **The caller's
framing is correct: its only remaining failure mode is being skipped.**

I am not calling this wrong — the floor is a dated user decision (2026-08-07) and architecture
trade-offs stay human-owned. The precise finding is narrower and actionable: **that decision weighed
two options — "floor from data" vs. "floor as a guess" — and the third, simplest one is absent.**
Record the raw baseline under Verification, drop clause 3 and the floor decision, gate on clauses 1
and 2. Worth putting to the user before the gate opens, because it is a KISS/YAGNI simplification
that loses nothing measurable.

### 2. The gate moved onto clauses 1 and 2 — whose difficulty is a 15× uncontrolled variable

This is the round's most consequential residual, and it exists *because* of the round's fix. R9 now
says the branch "is gated by clauses 1 and 2, which are rank-based, **were fixed before the queries
were written**, and can genuinely fail."

Fixing the *clauses* before the queries does not fix their *stringency*, because stringency is set
by **which five features the queries name** — chosen in task 8, explicitly "after task 7, so the
queries are written against the corpus they will be scored on."

I measured the candidate pool with the real chunker:

| feature (`.md` + `.spec.md`) | chunks |
|---|---|
| `phase-guard-hook` | **91** |
| `replay-harness-base-pin` | 70 |
| `memsearch-freshness` | 58 |
| `verification-marker-gate` | 53 |
| `memory-system-split` | 37 |
| `git-guard-empty-index` | 24 |
| `git-guard-chained-command` | 13 |
| `shell-segments-redirects` | 13 |
| `falsifier-base-pin` | 9 |
| `stale-phase-guard-rule-text` | **6** |

Clause 1 is "**≥2 hits** belonging to the named feature" in a top-6. A query naming a 91-chunk
feature has **fifteen times** more chunks competing for those six slots than one naming a 6-chunk
feature. **R9 does not control for this**: it does not require the five to span the range, does not
require the chunk count to be recorded beside each result, and does not say a 5/5 over the top of
the distribution means less than a 5/5 across it.

Falsifier (d) guards against *modifying* the queries after seeing results. Nothing guards against
*choosing* five well-covered features before running any — and no bad faith is required, since an
author who has just written a 58-chunk spec knows which features are thin. The surviving blindness
discipline ("written without first running any query against the rebuilt index") does not cover it.

Cheap to close, one sentence in R9 before task 8: the five must span the chunk-count range, and each
result records the named feature's chunk count. Left open, the clause the spec now leans its whole
verdict on is as post-hoc-tunable as the one it just demoted — by target selection instead of by
threshold.

### 3. Falsifier (i) is the right clause in a list nothing schedules an evaluation of

Adding (i) was correct and it does catch the bare-`pass` case. But the caller asked whether it is
enforceable in practice, and the honest answer is **not yet**.

(i) is classified as an "observation", not a hook test. Grepping the Tasks section for `falsifier`
returns **nothing** — tasks 1-11 never mention it, and task 11 is only "Observability judge
(implementation stage), then PR." The Verification stub says "pass/fail per area and open issues
only." So **(c), (d) and (i) have no named evaluator and no named moment.** (i) is additionally
scoped by a preamble — "across the 20 sessions after it lands" — that does not fit a clause about
the state of the ship itself.

And the symmetry is telling: **task 9 has a structurally identical prose stop-and-ask** ("if it
exceeds `RUN_MAX_HOURS`, stop and put the constant back to the user") with **no falsifier clause at
all**. The round added a guard for one unbacked stop-and-ask and not the other.

One line in task 11 — "evaluate every falsifier clause and record the result under Verification" —
closes (c), (d) and (i) together.

### 4. The index of derived surfaces was fixed by patching two entries, not by enumerating

The round-7 commit message correctly celebrates the best finding of the loop: *"the index of derived
surfaces had itself gone stale — the exact failure the table exists to prevent, one level up."* The
fix added the two entries the compliance judge named (R2, clause (h)).

**I grepped for every state-number reference outside the table.** At least six more surfaces restate
it by number and are still not in the index:

- **lines 612-616** (Contracts, "Ordering consequences") — *"states 5, 6 and 7 all warn, and stale
  wins"*, *"State 3 is checked before state 4"*. **This is the strongest instance**: those ordering
  rules appear nowhere in the table itself, which only says "first match wins".
- **line 191** ("Why each state exists") — restates row 3's condition verbatim.
- **lines 226-228** — the `RUN_ABANDON_HOURS` rationale, by state number.
- **line 993** (zero-files Non-goal) — "renders as state 8, fresh".
- **lines 1025-1027** (concurrency Non-goal) — "neither state 1 nor state 2 carries the remediation
  command"; "reclassifies a run as state 5".
- **line 1034** (log Non-goal) — "states 2, 3, 6 and 7 all point a reader at that file".

The standing rule is *audit the surface after repeat findings — stop patching and enumerate.* Round
7 identified the class explicitly and then patched two instances of it. Same species, one level down.

**Related and unfixed: R9 has no derived-surfaces index of its own**, despite now being the second
multi-surface authority in the document — it governs two scenarios, falsifier (i), task 8b and task
10(b). The discipline was learned for R3's table and not generalised.

### 5. The conjunction rule is right at three surfaces of four

R9 (312-315) ✅, the new scenario (934-940) ✅, falsifier (i) ✅. **Task 10(b) still reads "record
pass/fail per query"** (line 1147) — the exact wording round 6 flagged. It now sits beside a ⚠️ note
saying clause 3 is reported as `not yet binding`, but the conjunction rule for the *query's overall
result* is not there. The task list is the surface an implementer actually works from. Fourth
consecutive round in which a rewritten requirement left a task surface un-re-derived.

### 6. Line count: synced, not deduplicated

`3,484` is now exact in all three places. But round 6's finding was that the standing rule is *delete
the duplicate, don't sync it* — and the fix chosen was to sync. Only line 502 carries the "treat any
figure as a floor" caveat; the file grows every session, so 380 and 1117 will be wrong again before
task 7 runs. Immaterial to the argument; named because it is the drift species this loop keeps
producing.

## On length and scar tissue — the caller asked directly

I nearly recorded 1,163 lines as a finding and **checked the baseline first.** Sibling feature docs in
this repo run **1,166 / 1,303 / 1,779** lines. This spec is at the house norm, not an outlier, and it
is a feature doc rather than always-on rule content. At 77,973 characters (~20k tokens) it is
genuinely more than one comfortable pass, and the one-canonical-file `MAY`-split threshold is met —
worth considering, not required, and not a `context_budget` concern on a threshold this repo
routinely exceeds.

The **14 ⚠️ blocks** are the honest question. Today they are load-bearing: a reader meeting `2.3×` or
`≥0.30` in an old commit needs to know it was wrong and why. Line 1157 ("before round 6 this clause
read `≥0.30`") is already archaeology, and the whole set belongs in ADR 0019 or session memory once
the branch lands. **Durable record now, scar tissue after landing** — the migration point is the
finding, not the volume.

## Carried, unchanged

- **A run that walks zero files still reads as state 8, fresh, indefinitely.** Now named in two
  places (R2's exception pointer and the Non-goal) instead of one. Naming is not removing; the
  masking is live in a feature whose entire purpose is to stop the index lying about its freshness.
- **Silence still equals health** — absent `status.json`, `chunks == 0`, an unregistered hook and an
  unreadable file mid-rebuild all render as nothing at all. Structural, recorded, not re-argued.
- **No prune path.** `git revert` undoes the config, not the vectors; the exit is a multi-hour
  `index --full`. Fully disclosed — disclosure is not coverage.
- **`RUN_ABANDON_HOURS` (24h)** still clears an unmeasured cold-run duration, gated by task 9's
  prose stop-and-ask (see finding 3).

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | **pass** | All six directed fixes present and correctly executed; nothing added beyond direction. Every figure re-measured exact — `search.py:80`, `RRF_K=60` at `:19`, 3,484 lines in all three places, R2's guarantee re-derived against all eight table rows. |
| execution | **concern** | Clause 3's machinery survives its own obituary — the step's only remaining failure mode is being skipped, and the simplest option (drop it, keep the raw baseline) was never weighed. Falsifier (c)/(d)/(i) have no named evaluation moment; task 9's identical stop-and-ask has no clause at all. Task 10(b)'s rollup is the one surface not re-derived. R9 has no derived-surfaces index despite now governing four. |
| trajectory | **pass** | Up from **concern**. The round accepted a correct critique and *stated it in the spec rather than arguing it away*, in the strongest available terms; self-audited one level up and found the better bug (the index of derived surfaces gone stale); and corrected its own citation against source. That is the shape of a healthy review loop. The enumerate-vs-patch gap is recorded under `execution`, not double-counted here. |
| regression | **pass** | Documentation-only edits; no new mechanism, dependency, or behaviour. The one substantive rewrite (R2 defers wording to the table) I verified row-by-row: `fresh` is genuinely unreachable with an unusable `last_run`, because state 4 catches everything states 1-3 did not. Carried residuals unchanged and disclosed. |
| context_budget | **pass** | Checked the baseline before scoring: 1,163 lines is at this repo's feature-doc norm (siblings 1,166 / 1,303 / 1,779), and it is not always-on content — the session-start hook is still one line in every state. Two costs named, neither blocking: ~20k tokens is more than one comfortable pass, and the spec is itself indexed at `curated_doc` 1.5 / 58 chunks into the corpus R9 scores. |
| traceability | **pass** | Every correction is recorded in place with its evidence, its old value, and why it was wrong — including the citation error the author caught in their own text. The round-7 commit message is itself an excellent audit record. Durable today; the migration point (ADR 0019 / session memory at landing) is the standing concern, not the volume. |
| success_masking | **concern** | The sharpest instance is closed: clause 3 no longer claims to be a verdict, and three of four surfaces enforce "never a bare `pass`". What replaces it is one notch smaller but real — **the gate moved onto clauses 1 and 2, whose difficulty is an uncontrolled 15× variable** (6 to 91 chunks across the candidate features) set by a task-8 choice made with the corpus in hand, guarded by nothing. Plus: falsifier (i) is unenforced, and zero-files-reads-as-fresh is live. |
| intent_drift | **pass** | Only what the two judges directed, plus one self-caught citation fix. No drive-by edits, no new dependencies, no scope growth. |
| checkpoint | **concern** | Spec committed and pushed on `main` @ `a7b95e7`, `origin/main == HEAD`, clean tree; branch pending task 1 by design (not a finding). Held at concern for two unchanged structural gaps: nothing reverts embedded chunks (the exit is a multi-hour `--full`), and task 7 is a deliberately coarse seven-part single commit — correctly justified, since a partial application leaves the tool refusing to start, but it is the branch's riskiest change in one revert unit. |
| audit_trail | **pass** | Three dated, attributed user decisions; ADR 0018 and ADR 0019 both mandated with options-weighed content; each correction names what was wrong, when it was measured, and what replaced it. One gap: the floor decision's options list weighs two and omits the third (no clause 3 at all). |

**risk: medium · confidence: high**

Confidence is high because every claim below rests on a measurement I took: `search.py:80` and `:19`
read from source, 3,484 counted with `wc -l`, R2's guarantee walked against all eight table rows, the
state-number surfaces enumerated by grep rather than by reading, chunk counts produced by the real
`split_markdown` over all ten candidate features, and push state confirmed with `git rev-parse`. I
also checked the sibling feature-doc lengths *before* scoring `context_budget`, and dropped a finding
I would otherwise have recorded.

Risk stays medium. Round 6's blocking issues are genuinely closed and this round's self-audit was the
best work in the loop. Medium reflects three things still live and all cheap to close **before task 8
commits the queries**: the clauses the spec now leans its verdict on have unpinned difficulty, the
falsifier that guards the remaining skip has no evaluation moment, and clause 3's machinery is
retained without the simplest alternative having been weighed.

## Concerns

1. **Clauses 1 and 2 now carry the branch's verdict, and their difficulty is uncontrolled** —
   candidate features span **6 to 91 chunks** (measured with the real chunker). "≥2 hits in top-6" is
   ~15× easier for the largest than the smallest. Task 8 picks the five with the corpus in hand;
   nothing requires them to span the range or to record each feature's chunk count. The blindness
   discipline covers *tuning*, not *target selection*.
2. **Clause 3's machinery survives its own obituary** — task 8b's measurement half produces the
   baseline; the floor half produces something strictly less informative that cannot fail and has no
   future run to grade. Its only remaining failure mode is being skipped. The user decision weighed
   "floor from data" vs. "floor as a guess"; the third option — drop clause 3, keep the raw baseline
   — was never weighed.
3. **Falsifier clauses (c), (d) and (i) have no named evaluation moment** — `falsifier` appears
   nowhere in the Tasks section; task 11 is "judge, then PR". (i) is additionally scoped by a
   "20 sessions after it lands" preamble that does not fit a landing-time condition. One line in task
   11 closes all three.
4. **Task 9's stop-and-ask has no falsifier clause at all** — structurally identical to task 8b's,
   which just got one. `RUN_MAX_HOURS` can be set without the cold-run measurement and nothing
   records that it was.
5. **The derived-surfaces index is still incomplete after being fixed for being incomplete** — six
   more surfaces restate the state table by number, notably lines 612-616, whose ordering rules
   ("stale wins", "state 3 before state 4") appear nowhere in the table itself. The class was named
   and two instances were patched.
6. **R9 has no derived-surfaces index** despite now governing two scenarios, falsifier (i), task 8b
   and task 10(b) — the discipline was learned for R3's table and not generalised.
7. **Task 10(b) still says "record pass/fail per query"** — the conjunction rule lives only in R9.
   Fourth consecutive round where a rewritten requirement left a task surface un-re-derived.
8. **The archive line count was synced, not deduplicated** — three copies of a number that grows
   every session; only one carries the "treat as a floor" caveat.
9. **Correction narrative is accumulating in the artifact an implementer reads at task time** — 14 ⚠️
   blocks, several now archaeology. Load-bearing today; belongs in ADR 0019 or session memory once
   the branch lands.
10. A run that walks zero sources still reads as **state 8, fresh**, indefinitely — now named twice
    as a bounded Non-goal with the right forward pointer. Naming is not removing; the masking is live.
11. Silence still equals health: absent `status.json`, `chunks == 0`, an unregistered hook and an
    unreadable status file mid-rebuild are indistinguishable. No heartbeat; structural, carried.
12. No prune path: re-excluding `CODING_MEMORY.md` after a failing R9 leaves its chunks scored and
    returned until a multi-hour `index --full` (disclosed and accepted).
13. `RUN_ABANDON_HOURS` (24h) still clears an unmeasured cold-run duration; past it the stale line
    hands a possibly-live run the index command with no lock. Gated by task 9's stop-and-ask — see
    concern 4.
14. `scheduled-index.log` is unbounded and is the destination of four of eight nudge lines (disclosed
    as a Non-goal; rotation needs task 9's size figure).
