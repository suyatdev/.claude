# Observability verdict — memsearch freshness (round 3, architecting)

- **Repo:** `.claude` · **Branch:** `main` · **HEAD:** `34718d8f86ba7bcd88ca8a88135ac9f3143a07d9`
- **Stage:** `architecting` (advisory — blocks nothing)
- **Spec:** `docs/features/memsearch-freshness.md` @ blob `eef3aea004dc865e692205b17562f2f56cc89e26`
- **Diff scored:** none — `phase: planning`, `branch: none`, no implementation code exists
- **Timestamp:** 2026-08-06T22:07:58Z
- **Prior rounds:** `…-memsearch-freshness.md` (`risk=high`) · `…-round2.md` (`risk=medium`, `success_masking=fail`)

> Filename keeps the established `<date>-<branch_slug>-<feature>-round<N>` convention already used by
> rounds 1 and 2 for this branch. Writing the bare `2026-08-06-main.md` would have overwritten the
> round-2 verdict and destroyed the audit trail this gate exists to keep.

---

## Round 2's `fail` is closed — properly, at the level of the class

`last_run_errors` now has a reader. Not one clause but five, and they reinforce each other:

- R3 adds a *degraded* line — `⚠ last run had 47 errors …` — gated on `last_run_errors > 0`.
- The classification table gives it row 5, with a stated tie-break against stale.
- A scenario pins it: *"A run that failed on every file is never reported as fresh."*
- Falsifier (f) covers it: *"a run that errored on every source is reported as fresh."*
- Task 4 carries the instruction that actually matters: **"the degraded-line test must assert the
  emitted line, not the parsed field."**

That last one is the difference between fixing a bug and fixing a bug class, and the spec says so in
its own words: *"A written-but-unread field is the same defect this feature exists to fix, one field
over."* Eight of round 2's nine concerns are addressed (the ninth, non-atomic `write_text`, is
neither fixed nor non-goaled). This is a good revision.

Two **new** findings, neither caught in rounds 1–2, both cheap to fix before code exists.

---

## Finding 1 — the scheduler will not actually fire every 6h, and the stale line will cry wolf

From `man launchd.plist` **on this machine**, `StartInterval`:

> "If the system is asleep during the time of the next scheduled interval firing, that interval will
> be missed due to shortcomings in kqueue(3)."

The spec never mentions sleep. Decision 1's whole argument is that `STALE_HOURS` (8) sits above the
interval (6) *"so it fires only when a run has genuinely been missed rather than during the normal
gap between runs"* — and that a threshold firing on ordinary days is **"strictly worse than silence,
because it burns the one channel that reports the failure."** That reasoning is correct. Its premise
— that firings land every 6h — is not, on a laptop that sleeps.

Walk it: last run finishes 22:30, machine sleeps 00:00–08:00, the 04:30 firing is missed, the next is
10:30. The 08:15 session sees `last_run` 9h45m old → **stale ⚠ with the remediation command**, on a
perfectly healthy schedule. Most mornings. The remediation is a 2–3h foreground indexing run (see
finding 2), so the reader will not run it, will learn the ⚠ is noise, and the real freeze — the one
this feature exists to catch — arrives dressed identically.

`RunAtLoad: true` covers boot, not wake. I did **not** verify whether PowerNap / dark-wake runs a
`ProcessType: Background` job on this Mac; that is the open question and it decides how bad this is.
Fixes are all cheap: `StartCalendarInterval` (fires on wake for a passed calendar time), a
`STALE_HOURS` sized to cover a night, or accept it and say so in decision 1.

## Finding 2 — `RUN_MAX_HOURS = 6` rests on an overlap that cannot happen, and on a number that is a partial

**The rationale is contradicted by the platform.** R3 pins `RUN_MAX_HOURS` to the interval because
*"a run still going when the next is due is by definition the pathological overlap."* Same man page,
same paragraph: *"If the job is running during an interval firing, that interval firing will likewise
be missed."* launchd never runs two instances of one label — a >6h run is not an overlap, it is just
a slow run, and the scheduler already handles it by skipping. The constant needs its own
justification; right now it borrows one that does not apply.

**The measurement backing it is an elapsed-so-far, not a duration.** The spec records: *"an
incremental run over 601 sources was observed taking 1h26m on 2026-08-06."* That figure is round 2's
*still-running* reading. Measured myself, just now:

| | |
|---|---|
| Process | pid 30024, `etime` **02:07:38** — still running |
| `sources` rows | **683** (was 601 when the spec was written, 228 at diagnosis) |
| `status.json` | **mtime Jul 18**, still reporting `chunks: 2332, sources: 228` |

So the run the spec calls "1h26m" is at 2h08m and has not finished. Headroom under a 6h ceiling is
~2x, not the ~4x it reads as, on a corpus that grew **228 → 683 in three weeks**. The consequence if
a run does cross 6h is mild — a false *stuck ⚠*, which correctly withholds the remediation command —
but it is the same channel taking the same damage as finding 1. Round 2's honest *"elapsed, still
running; projected ~2h10m"* became *"was observed taking 1h26m"* in the spec. Same shape as the
`last_indexed` trap the spec catalogues: a number that resembles the quantity you want.

That same `status.json` line is also **live proof the design's core fix is right**: two hours into a
rebuild, the session-start nudge is announcing `2332 chunks` against a DB holding 683 sources,
because `_write_status` runs only at `run_index`'s exit (`index.py:100`). `run_started` fixes exactly
this. If that run is killed now, nothing is ever written about it at all.

---

## Smaller, still worth fixing before code

**Precedence hides the degraded state.** Rows 1–2 (in-progress / stuck) outrank rows 4–5, and the
in-progress line carries **no warning marker**. With runs empirically taking 2–3h out of every 6h, a
session start has a large chance of landing mid-run — and for that whole window a prior run's
`last_run_errors > 0` is invisible. That is the round-2 fix going quiet under a healthy-looking line.
Cheap: let the degraded marker ride on the in-progress line, or test errors before in-progress.
Related: the contract states *"stale wins when both hold"* and **no scenario pins that tie-break** —
14 scenarios cover the 6 rows, none covers precedence between them, and precedence is where this
feature's bugs will live.

**R8 reaches into two other repos.** `is_excluded` is a plain substring match
(`config.py:79-81`: `any(pat in str(path))`). Removing `"CODING_MEMORY.md"` from `exclude_paths`
therefore newly indexes **three** files — `~/.claude`'s plus `vibe-scape/CODING_MEMORY.md` and
`Snatch-Bracket/CODING_MEMORY.md`, both of which exist. The parent spec's justification
(`memory-system-split.spec.md:544-546` — it *"becomes the durable archive"*) is real and verified,
but it is about `~/.claude`'s memory system; the original design excluded *"CODING_MEMORY.md (and
per-repo equivalents)"* on a signal-quality argument that still stands for two repos nobody has
re-decided. Scope the pattern, or name the widening.

**"the golden query … will now fail correctly" is an untested prediction.**
`test_golden_queries.py` asserts `expect_path_contains` appears in top-k. The entry asserting the
exclusion expects `memory-rag-index-design` — and that design doc still contains its
*"What Is NOT Indexed"* section, so the test will most likely **keep passing** over a false premise.
Task 7 updates the query anyway, so the outcome is fine; the reasoning is not, and an implementer
waiting for a red test will wait forever. A green test pinning an obsolete fact, in the branch about
green signals pinning obsolete facts.

**The design doc it falsifies is not scheduled for update.** R8 correctly fixes `memsearch/README.md`
in the same change (round-2 compliance's catch). But `docs/superpowers/specs/2026-07-17-memory-rag-
index-design.md:135,154-163` argues the exclusion at length, **is itself indexed**, and is left
standing. After this lands the index contains an authoritative-sounding answer to *"why is
CODING_MEMORY.md excluded"* alongside the file it says is excluded. The spec's own rule — *"A README
fixed 'later' is a README that lies in between"* — applies verbatim.

**Round 2 concern 7 is neither fixed nor non-goaled.** `_write_status` uses `write_text` (not an
atomic replace), the design now calls it **twice per run**, and the entry write is a
read-modify-write (it must preserve the prior `last_run`). Concurrent manual runs are an explicit
non-goal, so two writers are permitted. A torn file lands in the existing malformed-JSON branch →
**silence**, not the unknown-age line. Not a false green, so not masking; but the one channel
vanishing is worth a sentence either way.

**Falsifier (c) mis-describes its own signal.** *"the launchd agent stops running and nothing
surfaces it within `STALE_HOURS`"* — if it dies **mid-run**, `run_started > last_run` persists and
row 1/2 wins, so the surfacing is the *stuck* line at `RUN_MAX_HOURS`, never the stale line. The
falsifier would read as failed while the design worked.

---

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | concern | Round-2 `fail` fully closed: `last_run_errors` gets a line, a row, a scenario, a falsifier clause, and a task instruction to assert the *line*. `status.py` in scope; `run_started` gets fail-toward-doubt; uninstall first-class. Deduction: the stated property *"fires only when a run has genuinely been missed"* is not delivered by `StartInterval` on a sleeping Mac. |
| `execution` | concern | No code (architecting). Ran the real harness myself: `hooks/memsearch-nudge.test.sh` → **5/5 pass, exit 0**; the 14 new scenarios are additive to a harness that works. Deductions: `RUN_MAX_HOURS`' one measurement is a partial elapsed time being exceeded live right now; task 9 verifies the job is *loaded*, not that it *fires across a sleep*. |
| `trajectory` | pass | Each round's defect fixed as a class, not an instance — round 2's unread field produced a rule, a test instruction and a falsifier clause, not just a branch. Two constants split rather than collapsed, with the conflation named. Falsified premise recorded with its cost. Reasoning, not luck. One lapse: an elapsed-so-far promoted into a duration. |
| `regression` | concern | Existing `status.json` keys pinned unchanged; nudge contract (one line, exit 0, never invokes the CLI) preserved; tasks 6/7 split config from golden query. New: R8's substring match indexes two other repos' `CODING_MEMORY.md` (both verified present); non-atomic double `write_text` still unaddressed. |
| `context_budget` | pass | Still at most one line at session start; the longest new line adds ~10 tokens. No always-on rule or skill growth; single spec file, no split. Newly indexed churn is retrieval noise, not always-on context. |
| `traceability` | concern | Seven numbered decisions each state *why*; ADR 0018 sequenced as task 2 *before* code; falsifier written before code; toolchain re-verified by me (py3.9.6 rejects `Z`/accepts `+00:00`; `launchctl getenv PATH` empty; `bin/memsearch` is `exec uv run`). Round-2's R7→R9 misreferences fixed. Deductions: `RUN_MAX_HOURS` justified by an overlap the platform documents cannot occur; *"will now fail correctly"* unfounded; the falsified design doc unscheduled. |
| `success_masking` | concern | Up from **fail**. Headline hole shut and asserted as a *line*. Residual: in-progress/stuck outranks degraded and carries no marker, so a degraded state is invisible for the 2–3h a run is in flight; torn `status.json` → silence, not unknown-age; the exclusion golden query likely stays green over a false premise. |
| `intent_drift` | pass | Scope still ends at parent item 5, item 6 excluded with a reason. This round's growth (`status.py`, uninstall, `RUN_MAX_HOURS`, degraded line) is entirely judge-requested and inside the feature's purpose. Seven non-goals, each naming its own residual risk. Unnamed drift: R8's reach into two other repos. |
| `checkpoint` | pass | Up from concern — round 2's exact gap closed: `--uninstall` is first-class with scenarios, exit codes, no-op success, and *"never touches `memory-index/`"*. Frontmatter verified against reality (HEAD `34718d8` on `main`, clean tree, no impl code). Task 1 flips phase and creates the branch before any code. Nit: no task says "if abandoned, run `--uninstall`". |
| `audit_trail` | pass | ADR 0018 required for both structural decisions with options weighed; falsified premise and lost blindness ordering recorded with costs; prior verdicts cited. R8's reversal of a reasoned exclusion is attributable upstream (`memory-system-split.spec.md:544-546`), verified. |

**Risk:** medium · **Confidence:** high

A lower medium than round 2's. No dimension fails, the load-bearing defect class is genuinely closed
and pinned three ways, and every remaining item is pre-implementation and cheap. It is not `low`
because finding 1 damages the exact channel this feature exists to build: an alarm that fires most
mornings on a healthy system is how the next silent freeze goes unnoticed. Confidence is `high` —
every load-bearing claim re-verified against source and the live machine, the existing harness run,
the platform man page read, the running indexer measured.

---

## Concerns

1. `StartInterval` misses firings while the Mac sleeps; a healthy schedule reads stale most mornings
2. Morning false-stale carries the remediation — a 2–3h run nobody will do, so the ⚠ gets ignored
3. `RUN_MAX_HOURS=6` justified by a launchd overlap the man page says cannot happen
4. Its one measurement (1h26m) is a partial elapsed; the same run is at 2h08m, 683 sources, unfinished
5. In-progress/stuck outranks degraded and carries no marker — errors hidden for the 2–3h of a run
6. Stale-vs-degraded tie-break is stated in the contract but pinned by no scenario
7. R8's substring match also indexes two other repos' `CODING_MEMORY.md`, unnamed in the spec
8. "the golden query will now fail correctly" is unfounded — it will most likely stay green
9. The design doc asserting the exclusion is indexed, falsified by R8, and unscheduled for update
10. Round-2 concern 7 (non-atomic `write_text`, now twice per run) neither fixed nor non-goaled
11. Falsifier (c) names the stale line; a mid-run death surfaces as *stuck*, so (c) misreads as failed

## Recommended before implementation (advisory — none of this blocks)

- Check empirically whether the job fires after a sleep; if not, use `StartCalendarInterval` or size
  `STALE_HOURS` to cover a night. Record the answer next to decision 1.
- Give `RUN_MAX_HOURS` its own rationale, and record the *completed* duration of the current run.
- Let the degraded marker survive an in-progress line; add a scenario per precedence pair.
- Scope the `CODING_MEMORY.md` exclusion removal to `~/.claude`, or state the widening.
- Add the memory-rag-index design doc to task 6's same-commit correction list.
- Fix or non-goal the non-atomic `status.json` write; reword falsifier (c).
