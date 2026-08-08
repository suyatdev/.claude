# Observability judge — memsearch-freshness (architecting, loop 2 round 6)

- **ts (UTC):** 2026-08-07T05:31:44Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `dd3004988e038b9b5b6ee4d2304c0b6db9f7619d`
- **stage:** `architecting` (advisory — does not gate a PR)
- **artifact:** `docs/features/memsearch-freshness.md`, committed on `main` @ `dd30049`, clean tree
- **test command:** none supplied; no implementation code exists. `execution` is scored on
  design-verifiability against the live tree, not on a run — stated plainly rather than implied.

**No dimension is `fail` this round.** Round 5's `execution: fail` is closed: the arithmetically
impossible bar is gone, the ceiling is recorded in the spec at the point of use, and the two clauses
that carry the feature's real question now bind unconditionally. What follows is one notch down.

## What was changed

The memory index froze for 19 days and the session-start line kept cheerfully vouching for it. This
design fixes both halves: a `launchd` job re-indexes every 6 hours, and the one line you see at
session start reports what it actually knows — fresh, running, stuck, abandoned, stale, degraded,
error-count-unreadable, or age-unknown — and never claims freshness it cannot prove.

Round 6 did four things: replaced the impossible `≥0.30` retrieval bar with a floor set from
measurement (new task 8b, applied by task 10); named the zero-files-walked blind spot as a bounded
Non-goal; fixed the "usable" wording collision and the decay scenario's contradictory Givens; and
corrected two figures that had conflated units.

## Does it do what was intended?

Yes on all four, and the evidence discipline is again the strongest part of the document. **Every
round-6 figure I re-measured came out exact.** I did not accept the document's account of anything:

| Claim added or corrected in round 6 | Verified independently |
|---|---|
| `CODING_MEMORY.md` **300,160 characters / 3,484 lines** | exact ✅ (bytes are 303,173 — the char/byte split the round names is real) |
| Three indexed docs larger than the old candidate: **184,620 / 153,701 / 131,516** characters | exact ✅, and they are the top three by character count |
| Largest indexed doc is `vibe-scape/…/2026-07-13-live-presence-plan.md`, **184,620 chars / 121 chunks** | exact ✅ |
| `2026-07-26-03b-deploy-design.md` is largest by **chunk count (130)**, not by size | exact ✅ (130 chunks; 128,317 chars — 4th by size) |
| Multiplier is **1.62×**, not 2.3× | exact ✅ (300,160 / 184,620 = **1.626**) |
| **20** session-pattern headings, in **two** forms — **17** date-first, **3** session-first | exact ✅ |
| **Zero** headings carry the `## Session N — <date>` shape the old text named | exact ✅ |
| Scorer ceiling `2 × 1/(RRF_K+1) × 1.5 = 0.04918`, `RRF_K = 60` | re-derived from `search.py:19,60-63,78` ✅ |
| Decay scenario now `last_run` 40h / `run_started` 30h | consistent ✅ — the round-4/5 contradiction is closed |
| "Usable" keeps one definition; only the age threshold moves a run between states | consistent with the table ✅ — state 3 is reachable again |

**I ran the real chunker rather than estimating, and it supports the design more than the spec
claims.** `split_markdown` on the live archive yields **190 chunks** — against the current chunk
leader's 130, that is **1.46×**, *below* the 1.62× character ratio. So the archive lands at ~190 of
7,631 chunks (**2.5% of the corpus**) at weight **1.0**, the lowest tier, beneath `repo_doc` 1.2 and
`curated_doc` 1.5. Measured both ways, the corrected number holds and the noise risk this paragraph
exists to size is genuinely modest. The old 2.3× was wrong in *both* units, not just one.

## The question asked: does the staged floor remove the success-masking, or relocate it?

**It removes one failure mode cleanly and introduces a smaller, quieter one that the spec does not
name.** Three findings, in severity order.

### 1. A floor set from the run it grades cannot fail that run — and that run is the only one

Task 8b runs the five queries, records the raw scores, and a human picks the floor **with the answers
in hand**. Whatever number is chosen will sit at or below what was observed, so clause 3 passes by
construction. That alone would be a tolerable regression baseline — except the Non-goals close the
other end: *"Re-measuring retrieval on any cadence after this lands. R9 measures once, at landing."*

Combine the two and **clause 3 conveys no information on the only occasion it will ever be
evaluated.** It cannot fail at landing, and there is no later run for it to grade.

This is the same species as the defect the round removed, with the sign flipped: a check that could
only ever fail became a check that can only ever pass. The old one was at least loud — a guaranteed
0/5 is unmissable. The new one is agreeable and green.

The design's instinct is right — an a-priori RRF threshold genuinely *is* a guess, since the scale
depends on corpus size, `RRF_K` and the weight table, and the user's own standing rule prefers the
honest weaker measurement to a computed substitute. The gap is not the choice; **it is that this
document names every other cost it takes and does not name this one.** Falsifier clause (d) exists
precisely to stop the *queries* being tuned post-hoc; nothing applies the equivalent discipline to
the *threshold*. One sentence in R9 closes it: say that a floor set from this run is a baseline for
future comparison, not a pass/fail on this run, and that clause 3 passing at landing is not evidence.

### 2. `not yet binding` is safe at the clause; the per-query rollup is where it can read as a pass

At clause level the default is genuinely well-chosen: never a pass, never a fail, never against an
invented number, plus a stop-and-ask. That is the right shape.

**The rollup is undefined, and the Scenario contradicts it.** R9's acceptance is all three clauses.
Task 10(b) says record "pass/fail per query" while one clause may be inert — and the Scenario at
lines 891-895 admits only two values: *"Then the pass or fail of each is recorded under Verification."*
An implementer resolving that ambiguity for a query that passes clauses 1 and 2 will most naturally
write **pass**, and a Verification table reading "R9: 5/5 pass" is exactly the thing a reader
mistakes for a full pass. This is round 5's species recurring in a new place — R9 was rewritten and
its scenario was not re-derived, in a document whose central discipline is that every surface derives
from one authoritative statement.

### 3. The staged floor creates a skip path with no falsifier clause

`not yet binding` is a **permitted, non-failing** outcome. So the lowest-effort route through the
checklist is: skip 8b's stop-and-ask, run task 10, record `not yet binding`, ship. The spec's
counter-measure is a prose instruction ("stop and ask"), and nothing mechanical backs it — task 8b is
a checkbox, and the phase-gate machinery does not know about it.

The falsifier is where this belongs and it has no clause for it. (a)–(h) cover the nudge and the
queries; **none says "this has failed if the branch lands with clause 3 never bound."** Adding clause
(i) would let the document's own instrument detect its own skip. Cheap now; invisible later.

## The zero-files Non-goal — is naming it honest and sufficient?

**Honest: yes, unusually so.** The bullet names the mechanism (`chunks` is a database total that
survives a run indexing nothing), states why R4's escape hatch misses it, says outright that it is
*"the same species as the failure in the Background"*, and leaves a forward pointer naming the right
fix (record the walked-source count, add a ninth state) and the wrong one (widen `chunks`). It is
dated and attributed. I am not re-litigating the scope call, which is reasonable for a bounded branch.

**Sufficient with one gap.** R2's headline is absolute — *"the nudge never claims freshness it cannot
prove"* — and in this case state 8 does exactly that. The Non-goal that scopes R2 sits ~800 lines
away; a reader of R2 alone gets the unqualified promise. The spec has already established the fix
pattern elsewhere: state 6's rationale explicitly scopes R2 ("R2's 'fail toward doubt' rule is scoped
to *timestamps*"). R2 simply needs the same pointer to its own exception. Documentation, not scope.

## What else claims to measure something it cannot? (full sweep)

Nothing new. The document is now unusually clean on this axis, and each surviving weakness is
disclosed at the point of use: the `-m golden` net can only fail on 11 of its 16 cases (disclosed,
task 10(a)); falsifier (c) and (d) are observations, not tests (disclosed); (d) is weaker than
written because the rebuild came first (disclosed); the R9 baseline is frozen and unrepeatable
(disclosed); `RUN_MAX_HOURS`/`RUN_ABANDON_HOURS` still clear an unmeasured cold-run duration (gated
by task 9's explicit stop-and-ask). The three original measurement traps remain the best part of the
spec. Clause 3 above is the only place left where a check is presented as sharper than it is.

## Carried, unchanged

- **Silence still equals health** — an absent `status.json`, `chunks == 0`, an unregistered hook and
  an unreadable file mid-rebuild all render as nothing at all. Not materially changed this round;
  recorded as the standing structural cost of "one line at session start is the only monitor", not
  re-argued.
- **No prune path.** `git revert` undoes the config, not the vectors; the exit is a multi-hour
  `index --full`. Fully disclosed — disclosure is not coverage.

## New minor finding — one fact, three copies, one updated

The archive's line count is stated in three places. Round 6 updated the noise paragraph to **3,484**
and left **3,433** at line 344 ("3,433 lines of session narrative") and line 1067 ("the 3,433-line
archive"). Harmless in effect — the "treat as a floor" caveat covers it and the argument does not
turn on 51 lines — but it is the exact drift species this loop keeps producing, and the standing rule
is to make one copy authoritative and delete the rest rather than sync them.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | **pass** | All four round-5 directed fixes are present and correctly executed; nothing was added beyond direction. Every corrected figure re-measured exact. |
| execution | **concern** | Up from **fail**. The impossibility is gone, the ceiling is recorded at the point of use, clauses 1 and 2 bind unconditionally. Remaining: clause 3 cannot fail on the only run that evaluates it; the per-query rollup with an inert clause is undefined and the Scenario admits only pass/fail; no falsifier clause detects landing with the floor never set. |
| trajectory | **concern** | Large improvement over round 5 — the method is right and every claim I re-checked was exact. One notch withheld: "set the bar after seeing the data" is a known reasoning hazard, defensible here, but a document that names every trade it takes does not name this one, and R9's own wording implies a clause-3 failure is possible when it is not. |
| regression | **pass** | Up from concern, on measurement rather than assertion. I ran the real chunker: 190 chunks, 2.5% of corpus, weight 1.0 (lowest tier) — the footprint is smaller than the spec feared in both units. The strict regression net now half-binds instead of being wholly inert. Residual (golden entry 11 forecast; 5 of 16 golden cases warn-only; no prune path) is disclosed and pre-registered. |
| context_budget | **pass** | Feature doc, not always-on rule content; the session-start hook is still one line in every state. Two costs worth naming, neither blocking: the doc now carries four separate correction blocks (~110 lines this round) that a task-time implementer pays for to learn about numbers no longer present — these belong in ADR 0019 or session memory once the branch lands; and the spec is itself indexed at **56 chunks / weight 1.5**, so its growth feeds the very corpus R9 scores. |
| traceability | **pass** | This is the round's strongest dimension. Every correction is recorded in place with its evidence, its old value, and why it was wrong — including one that makes the risk *less* alarming, which is the direction that proves the discipline is not self-serving. It helps a future reader rather than bloating: a reader who meets "2.3×" in an old commit needs to know it was wrong and why. Only blemish: 3,433 vs 3,484 in three places. |
| success_masking | **concern** | The impossible-red is gone. What replaces it is a floor that cannot fail the run it is set from, on a feature that measures once; a `not yet binding` outcome that is non-failing and unguarded by any falsifier clause; plus the carried zero-files-reads-as-fresh, now honestly named but not removed. Held at concern rather than raised, because the substantive retrieval checks — top hit belongs, ≥2 hits belong — bind unconditionally and *can* fail. Clause 3 is the one to distrust; clauses 1 and 2 are what actually gates. |
| intent_drift | **pass** | Round 6 added only what was directed. The Non-goal is a scope *reduction*, bounded, dated, attributed, with a forward pointer. No drive-by edits, no new dependencies. |
| checkpoint | **concern** | Spec on `main` @ `dd30049`, clean tree; branch pending task 1 by design (not a finding). Task 8b improves this — the floor and its evidence land in one commit, so the bar and its justification share a revert point. Held at concern for the unchanged gap: nothing reverts embedded chunks, and the stated exit is a multi-hour `--full`. |
| audit_trail | **pass** | Three user decisions dated and attributed (floor 2026-08-07, zero-files Non-goal 2026-08-07, weight tier 2026-08-06); ADR 0018 and ADR 0019 both mandated with options-weighed content; each correction names what was wrong, when it was measured, and what replaced it. |

**risk: medium · confidence: high**

Confidence is high because I re-derived the RRF ceiling from `search.py`, ran the real
`split_markdown` against the live archive rather than estimating chunk counts, and re-measured every
figure round 6 changed — all of which matched the document exactly.

Risk drops from high to medium, not to low. The blocking defect is genuinely fixed and the round's
evidence work is excellent. Medium reflects three things that remain live and are all cheap to close
*before task 8 commits the queries*: the headline bar's third clause has no falsification power at
landing, its reporting contract is ambiguous in a way that reads as a pass, and there is a permitted
path where the branch ships with that bar never evaluated at all.

## Concerns

1. **A floor set in task 8b from the run it grades cannot fail that run** — and the Non-goals rule out
   re-measuring on any cadence, so clause 3 carries no information on the only occasion it is
   evaluated. Post-hoc threshold; the cost is not named anywhere, in a document that names every
   other cost it takes.
2. **The per-query rollup with an inert clause is undefined, and the Scenario contradicts task 10** —
   line 894 admits only "pass or fail" per query; a query passing clauses 1 and 2 will be recorded as
   `pass`, and "R9: 5/5 pass" reads as a full pass with the score bar never applied. R9 was rewritten
   and its scenario was not re-derived.
3. **`not yet binding` is a permitted non-failing outcome with no falsifier clause** — the lowest-effort
   route is to skip 8b's stop-and-ask and ship green. Falsifier (a)–(h) has no clause for "landed with
   clause 3 never bound"; add (i).
4. **R2's absolute promise ("never claims freshness it cannot prove") is contradicted by the zero-files
   Non-goal ~800 lines away** — state 8 does claim it there. The Non-goal is honest and sufficiently
   detailed; R2 just needs the pointer to its own exception, exactly as state 6 already scopes R2 to
   timestamps.
5. **The archive's line count lives in three places and round 6 updated one** — 3,484 in the noise
   paragraph, 3,433 at lines 344 and 1067. Immaterial to the argument; the exact drift species this
   loop keeps producing.
6. **Correction narrative is accumulating in the artifact an implementer reads at task time** — four
   ⚠️ blocks now explain numbers that are no longer present. Load-bearing today; belongs in ADR 0019
   or session memory once the branch lands.
7. Silence still equals health: absent `status.json`, `chunks == 0`, an unregistered hook and an
   unreadable status file mid-rebuild are indistinguishable. No heartbeat; structural, carried.
8. A run that walks zero sources still reads as state 8, fresh, indefinitely — now named as a bounded
   Non-goal with the right forward pointer. Naming is not removing; the masking is live.
9. No prune path: re-excluding `CODING_MEMORY.md` after a failing R9 leaves its chunks scored and
   returned until a multi-hour `index --full` (disclosed and accepted).
10. `RUN_ABANDON_HOURS` (24h) still clears an unmeasured cold-run duration; past it the stale line
    hands a possibly-live run the index command with no lock. Gated by task 9's stop-and-ask — the
    right mitigation, still an open number.
11. `scheduled-index.log` is unbounded and is the destination of four of eight nudge lines (disclosed
    as a Non-goal; rotation needs task 9's size figure).
