# Observability verdict — `feature/memsearch-freshness` @ `46c9906`

- **stage:** implementation (gates the PR)
- **repo:** `.claude` · **base:** `main` @ `b78eae8` · **21 commits**
- **judged:** 2026-08-08T05:24:22Z
- **spec:** `docs/features/memsearch-freshness.md` (single canonical file)

---

## What was changed

The memory index used to be a car with a fuel gauge painted on. Every session start printed
"8615 chunks" — a number that sounded like a health check but was only ever a count of what was
already in the tank. Nothing refilled the tank, and nothing checked. It ran dry for 19 days and the
gauge never moved.

This branch does three things: it hires a driver (a background `launchd` agent that rebuilds the
index on a schedule), it replaces the painted gauge with a real one (`status.json` now records *when
a run happened* separately from *how current the content is*, and the session-start line reports one
of eight states — in progress, stuck, abandoned, stale, degraded, fresh, or honestly "unknown"), and
it starts indexing the session archive (`CODING_MEMORY.md`) that was previously excluded.

## Does it do what was intended?

Yes, on the part that matters most — and I confirmed it live, not from the write-up:

- `launchctl list` shows `local.memsearch-index` loaded, last exit `0`.
- `memory-index/status.json` carries all six fields including `run_started`, `last_run`,
  `last_run_errors` — the split that makes the original defect unrepeatable.
- The session-start line in my own transcript reads `last run 54m ago`, which is the new reporting
  actually reporting.
- Tests I ran myself: unit `74 passed`, golden `16 passed`, nudge hook `27/27 passed`.
- The R9 measurement table reproduced **exactly**, query for query, clause for clause, against the
  recorded result. That is unusually good measurement hygiene and I want to say so plainly.

## What could go wrong — the honest concerns

### 1. The central conclusion of task 10b is backwards, and it exonerates the change ⚠️

The record says: *"R10's measured noise cost on R9's bar: **zero**. The regression is
self-inflicted"* — i.e. the newly-indexed archive displaced nothing, and the real culprit is this
document's own `## Verification` section appearing at rank 1.

The evidence offered is *"no `archive_doc` hit appears in any of the five queries' top-6."* That
observation is true — I verified all 30 rows are `curated_doc`. **But it does not support the
conclusion**, because of how the scorer works. `search.py:16,60-66` fuses two retrievers by
Reciprocal Rank Fusion over a **200-candidate pool per branch**. An item's score depends on its
*rank* in each list. So a chunk that sits at candidate rank 8 and never reaches the visible top-6
still pushes every chunk below it down one rank, shrinking its score. **Invisible displacement is
the expected mode of this scorer, not an edge case.** Absence from the top-6 is not absence of
effect.

Probing the candidate pools directly, archive chunks are present and ranked *above* target chunks
in every one of the five queries — for `falsifier-base-pin`, 12 of them in the vector list and 18 in
the keyword list, with `CODING_MEMORY.md:1000-1021` sitting at vector rank 8, directly above the
target's chunks at ranks 10, 11 and 12.

I then ran the counterfactual the record never ran — re-fuse the same candidate lists with one
population removed — and it inverts the finding:

| query | as-is | minus **archive** (R10) | minus **this doc** (the alleged displacer) |
|---|---|---|---|
| `stale-phase-guard-rule-text` | PASS / PASS | PASS / PASS | PASS / PASS |
| `falsifier-base-pin` | **FAIL(1)** / PASS | **PASS(2)** / PASS ← *fixed* | **FAIL(1)** / PASS ← *unchanged* |
| `git-guard-empty-index` | PASS(2) / PASS | **FAIL(1)** / PASS ← *broken* | **FAIL(1)** / PASS |
| `verification-marker-gate` | FAIL / FAIL | FAIL / FAIL | FAIL / FAIL (top hit changes, clause still fails) |
| `phase-guard-hook` | PASS / **FAIL** | PASS / **FAIL** | PASS / **FAIL** (top hit changes, clause still fails) |

Read the two right-hand columns:

- **Removing this document's `## Verification` section flips zero of the ten clause outcomes.** It
  is the visible rank-1 occupant on two queries, and removing it changes the *name* of the top hit
  while both queries still fail clause 2. It is a passenger, not the driver.
- **Removing the archive flips two.** `falsifier-base-pin` — the single query the record names as
  *"regressed vs 8b"* — goes FAIL→PASS. And `git-guard-empty-index` — the single query named as
  *"improved"* — goes PASS→FAIL. **Both** of the two moves the record correctly noticed trace to
  R10, the one cause it ruled out.

This is a clean R10 counterfactual, not an approximation of one: `config.json` shows
`CODING_MEMORY.md` moved out of `exclude_paths` **on this branch**, and all 257 `archive_doc` chunks
are new here. Removing them reconstructs the pre-R10 corpus. (Method caveat, stated so it can be
attacked: I drop chunks from the 200-candidate lists and re-fuse rather than re-indexing. The pool
does not backfill, but a backfilled item would enter at candidate rank ~200, contributing ~0.0038 —
an order of magnitude below the ~0.036–0.049 scores in the top-6 — so it cannot change these
outcomes.)

So the honest restatement is: **there is a real retrieval regression caused by this branch's archive
indexing, and the document records it as caused by something else.** A reader acting on this record
will defer the wrong fix — excluding the `## Verification` section from indexing would not have
recovered `falsifier-base-pin`.

Worth noting the architecting-stage verdict for this same feature (`verdicts.jsonl`, 2026-08-07)
already warned: *"R9 has no control; task 10(b) pre-commits attribution to R10 noise cost."* That
warning was accurate and the implementation ran without the control anyway.

### 2. On the three things you asked me to attack

**(1) Is "reported, not blocked" defensible for R9?** The textual argument holds — I checked, and
falsifier clause (i) conditions only on 8b's scores being recorded and on target span
(`:1755`), never on R9 passing; task 10 does ask for a failure to be reported. So you are not
misreading the spec. But the argument is *load-bearing on the attribution in point 1*, and that
attribution is wrong. "R9 is red for reasons not caused by this branch" would be a defensible ship;
"R9 is red and one of the three failures is a regression this branch caused, mis-attributed" is a
weaker position than the one written down. Two of the three failures (`verification-marker-gate`,
`phase-guard-hook` clause 2) genuinely pre-date R10 — they failed identically at 8b. The third does
not.

**(2) Is there a reading where the archive is implicated?** Yes — see point 1. You looked at *who is
standing in the frame* and concluded the archive wasn't in the photo. The scorer's mechanism means
the thing that pushed the target out of frame is usually itself out of frame.

**(3) Are the falsifier clauses honest?** Yes, and this is the strongest part of the record. Marking
ten clauses "held (in test), window not open", refusing to call that a discharge, and explicitly
naming clause (c) as *"passed because something surfaced"* is more self-critical than most
implementations manage. I would not soften it and I would not harden it. It does not overstate.

### 3. Smaller, real

- **"FAIL, 2 of 5" is ambiguous and has already misled a reader.** It means *2 of 5 passed*; the
  body two lines down says `3 failed, 4 passed` and *"4 passed = the 2 clean queries + the 2
  structural guards"*. The commit message renders it `R9 fails 2/5`, which reads as *2 failed*. I
  misread it on first pass. Fix: "3 of 5 fail; 2 pass."
- **The default test run hides the failing bar.** `pyproject.toml` sets
  `addopts = "-m 'not golden and not measurement'"`, so a bare `pytest -q` prints `74 passed` while
  R9 is red. Justified (it needs a real index) but it means green means less than it looks.
- **The golden suite cannot see this class of regression.** Its assertion is presence-anywhere-in-
  top-k (`test_golden_queries.py:39`); R9's clauses are invisible to it. The doc says so. But it
  means 16/16 green sat on top of a live ranking regression.
- **This is not cleanly revertible.** `git revert` restores `exclude_paths`, but the 257 archive
  chunks stay in the live DB — removing them costs a `--full` cold rebuild, measured at 4h51m34s.
  The record says this; it still means the checkpoint is a git checkpoint, not a system one.
- **`RUN_MAX_HOURS = 6` is at 81% of a measured cold run** with an explicitly non-durable margin
  (`skipped=0` means cost scales with session count). When it is exceeded, a healthy run starts
  reporting as *stuck*.
- **The founding defect's species survives by design.** A run whose corpus vanished completes clean
  and renders fresh forever. User-decided non-goal, disclosed, fix named — respected, but it means
  this feature does not close the class of bug it was built for.
- **No lock**: a manual index can race the scheduled one, and both write `status.json`. Recorded.

## What I'd double-check before merging

1. **Re-run the counterfactual above and rewrite task 10b's causal claim.** Either state R10's cost
   as measured (it flips two clauses, one each way) or state plainly that the cost was not measured
   because R9 has no control. The current text asserts zero, and it is the one number in this
   document that a later reader would act on.
2. **Decide whether `falsifier-base-pin`'s clause-1 regression is acceptable now that it has a
   cause.** It may well be — the archive is meant to compete — but that should be an accepted cost,
   not an unnoticed one.
3. **Fix the "2 of 5" phrasing** in the doc heading and in commit `997c57a`'s trail.
4. **Confirm ADR 0021 will carry the corrected attribution**, not the current one, into the
   deferred planning pass.
5. Housekeeping: the working tree has uncommitted `coding-memory/compliance-judge/verdicts.jsonl`
   and an untracked `2026-08-08-falsify-harness-signatures.md`. Not this branch's content, but they
   should not ride along.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| `intent` | **pass** | Agent loaded, `status.json` split live, 8-state line emitting, archive indexed. Verified independently, not read off the doc. |
| `execution` | **concern** | Unit 74✓, golden 16✓, nudge 27/27✓, R9 table reproduced exactly. But R9 — the feature's own retrieval bar — is red at merge, and one of its three failures is branch-caused. |
| `trajectory` | **concern** | Rigor is high throughout (rank-tertile anti-gaming, counts computed from source, non-vacuity check on golden 11, falsifier evaluated by letter). The one conclusion that exonerates the change is the one that was not tested against a control — after the architecting judge named that exact gap. |
| `regression` | **concern** | A real ranking regression (`falsifier-base-pin` clause 1) is caused by R10 and recorded as not caused by R10. Golden suite structurally cannot detect it. |
| `context_budget` | **pass** | One bounded session-start line, guaranteed ≤1 line and exit 0 by 27 tests. No always-on rule or skill growth; `rules/gates.md` untouched. |
| `traceability` | **concern** | Documentation quality is genuinely excellent — and the headline causal claim is confidently wrong, plus "2 of 5" is ambiguous enough that it misled this judge and arguably its own commit message. |
| `success_masking` | **concern** | Default `pytest` deselects the failing bar; golden 16/16 green over a live regression; zero-files corpus still renders fresh forever; `RUN_MAX_HOURS` at 81% of measured cold. |
| `intent_drift` | **pass** | Scope tight to the spec. Two ADRs (0018, 0020), 0021 named as owed. No new dependencies — `pyproject.toml` diff is markers only. |
| `checkpoint` | **concern** | 21 clean commits, but git revert does not undo the live artifact: archive chunks persist until a ~4h51m `--full`. Recorded, still real. |
| `audit_trail` | **pass** | Every measurement reproducible from the doc; I reproduced the full R9 table and the timing basis. ADR-worthy decisions have ADRs. |

## Concerns

1. Task 10b's causal claim is refuted by counterfactual: removing the archive flips 2 clause outcomes; removing this doc's `## Verification` flips 0
2. "R10's measured noise cost: zero" rests on absence from top-6, but RRF over a 200-candidate pool displaces invisibly — archive chunks rank above target chunks in all 5 queries
3. `falsifier-base-pin` clause-1 regression is branch-caused (R10), recorded as self-inflicted
4. `git-guard-empty-index`'s recorded "improvement" is also R10's doing — the "net is a coincidence" note is right, both attributions are wrong
5. Architecting verdict already warned "R9 has no control; task 10(b) pre-commits attribution to R10 noise cost" — implemented without the control
6. "FAIL, 2 of 5" means 2 passed; commit `997c57a` renders it "fails 2/5"; body says "3 failed, 4 passed"
7. `addopts` deselects `measurement`, so default `pytest -q` reports 74 passed with the retrieval bar red
8. Golden suite's presence-only assertion cannot detect the ranking regression R9 detects
9. Not cleanly revertible: 257 archive chunks persist in the live DB after a git revert; removal costs a 4h51m `--full`
10. `RUN_MAX_HOURS=6` at 81% of measured cold run, margin explicitly non-durable — overrun renders a healthy run as "stuck"
11. Zero-files corpus still renders fresh indefinitely — the founding defect's species, by declared non-goal
12. No lock: manual and scheduled index can race, both writing `status.json`
13. Falsifier window not open — 10 clauses "held in test", 6 never observed in production; clause (c) passes on something surfacing, not the right thing
14. Uncommitted `compliance-judge/verdicts.jsonl` + untracked file in the working tree

**risk = medium · confidence = high**
