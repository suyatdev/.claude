# Observability verdict — memsearch freshness (round 2, architecting)

- **Repo:** `.claude` · **Branch:** `main` · **HEAD:** `124b504d5b3d31128d2690d75bb746258be39557`
- **Stage:** `architecting` (advisory — blocks nothing)
- **Spec:** `docs/features/memsearch-freshness.md` @ blob `ca5b5e0260b008c1f3d75163871e4fb0519c202b`
- **Diff scored:** none — no implementation code exists
- **Timestamp:** 2026-08-06T21:28:41Z
- **Round 1:** `2026-08-06-main-memsearch-freshness.md` (`risk=high`)

> Note: the invocation named HEAD `fd0abab`; the live HEAD is `124b504` (`docs(memory): session 29`).
> The spec blob sha matched exactly, so the scored artifact is the intended one.

---

## Lead finding — `success_masking` = **fail**

The round-1 defect is genuinely fixed. The **same class of defect reappears one field over.**

A scheduled run with Ollama down does not crash. Verified against source, end to end:

- `index.py:135-137` — `_index_one` wraps every source in `try: … except Exception as e:
  report["errors"].append(...)`. The embed call raises, gets recorded, **and the loop continues.**
- `index.py:100` — `run_index` then reaches `_write_status(cfg, conn)` unconditionally.
- `cli.py:66` — prints the errors to stderr and `return 0`.

So a run that errors on **every single source** still stamps `last_run = now`. Under R1's
classification the nudge prints the **fresh** line — `memsearch: 6393 chunks, last run 3h ago` —
over an index that has not absorbed a byte in weeks. That is round 1's defect exactly: a green
signal vouching for a frozen index.

`last_run_errors` is the field that would catch it, and **nothing reads it.** R5 defines it. The
`hooks/memsearch-nudge.sh` contract lists what the hook parses — "`chunks` (existing) plus
`last_run` and `run_started` (new)". `last_run_errors` is absent. No line in R1/R2/R3 renders it.
Decision 6 argues, correctly on its premises, that the exit code is the wrong channel — then calls
`status.json` "the reporting channel that reaches a human" while specifying no consumer.

The test evidence hides this rather than exposing it. The scenario *"A completed run stamps its own
completion … And last_run_errors is 2"* pins that the field is **written**. No scenario pins that
anything **reports** it. A green suite over a silent failure.

The falsifier does not catch it either: (a) is missing-stale, (b) is false-stale, (c) is agent-stopped.
None is *"ran on schedule, errored on everything, reported fresh."*

**Cheap to close before implementation:** one clause in R1 (`last_run_errors > 0` → warn), one
scenario, one line in the hook contract. It is a `fail` because the design currently believes this
hole is shut.

---

## Answers to the four questions asked

### 1. Does the triple close the hole, or move it? What still fails silently?

`last_run` closes the original hole cleanly — that part is right, and the regression scenario pins
it. Four things still fail silently:

1. **All-errors run reads fresh** (above). The headline.
2. **A future-dated `run_started` produces a permanent "in progress" line.** R2 guards `last_run`
   against future timestamps ("fail toward doubt"). **`run_started` has no validity rule at all.**
   Walk R3's classification with `run_started` = now + 1 day: `run_started > last_run` is true;
   `now − run_started` is negative, therefore `< STALE_HOURS`, therefore **in-progress** — forever.
   And R3 says the in-progress line "carries no remediation command." A frozen index reported as
   busy, permanently, with nothing to do about it. The design defends one new field against clock
   skew and not the other.
3. **`memsearch status` keeps printing the misleading proxy.** `status.py:27` renders
   `sources: N  last_indexed: …` and the spec never touches it. The module docstring literally
   reads *"Index health: counts, **staleness**, …"*. After this lands, a human who types
   `memsearch status` to ask "is my index fresh?" is answered with `last_indexed` — the exact field
   decision 2 exists to stop people reading that way. The fix reaches one of two human-facing
   surfaces.
4. **A truncated `status.json` is silent, not unknown.** `_write_status` uses `write_text` (not an
   atomic replace) and the design now calls it **twice per run**, doubling the window. A torn write
   lands in the existing malformed-JSON branch → *nothing emitted*, per the "Malformed status.json
   stays silent" scenario. The one channel that reports the failure disappears rather than degrading
   to the unknown-age line.

### 2. Is `status.json`-not-exit-code defensible?

**The reasoning holds; the conclusion outruns it.** Both premises check out — `cli.py:66` does
`return 0` unconditionally after printing errors, and the plist sets no `KeepAlive`, so launchd
genuinely would ignore a non-zero exit for a `StartInterval` job. Declining to widen the CLI's exit
contract is the right call.

But it is a **half-fix of the same species as the original defect.** Unlike `last_indexed`, the
value written is *correct* — the failure is not a wrong number, it is a right number with no reader.
The practical effect is identical: the nudge's green line does not mean what a reader will take it
to mean. Decision 6 is sound as a *negative* (don't touch exit codes) and unfinished as a
*positive* (nothing consumes the channel it chose instead).

### 3. Is the abandoned-run rule correct?

Directionally right — an in-progress claim must not be an infinite excuse. Two problems.

**One constant, two semantics.** `STALE_HOURS` answers *"how old may a finished run be?"*.
Abandonment asks *"how long may a run legitimately take?"*. Different questions, different natural
values; the spec reuses one number without saying why. That is conflation of the same shape as
`last_indexed`-for-staleness, at one remove.

**The number is remembered, not measured** — in a spec whose toolchain table is proudly *"verified
on this machine, not remembered."* I measured the live run:

| | |
|---|---|
| Started (pid 30024) | 16:01:40 local |
| Observed at | 17:28:04 local |
| **Elapsed, still running** | **1h 26m** |
| Progress | 405 of 601 sources (`sources` by `indexed_at`) |
| Projected total | ~2h 10m |

That is ~4x headroom under an 8h threshold — adequate today, and it was **40 minutes when this
revision was written**, so the figure the spec reasoned from has already more than doubled while the
spec sat still. The exposure sits at task 9: `RunAtLoad: true` fires a run immediately at install,
against whatever backlog exists. A model change forces `index --full` (the toolchain table says so),
and the source set has already grown 228 → 601. If a run ever does cross 8h, the failure is
**not** a harmless spurious warning: the stale line carries the remediation command, so it tells the
reader to launch `memsearch index` **into a live indexer** — re-creating precisely the concurrent-run
invitation that decision 5 and R3 exist to prevent. The mitigation inverts into the hazard at the
threshold.

Recommend: a separate `RUN_MAX_HOURS` constant, and record the measured run duration next to it.

### 4. Are the non-goals honestly scoped?

**Yes for what they name.** They are unusually good: the lock/pidfile item states exactly what is
and is not mitigated ("R3 stops the nudge from *inviting* one; it does not prevent one"), and the
re-measurement item names its own residual risk ("an index that is reliably fresh but retrieves
noise stays silent afterwards"). That is scoping a gap, not laundering one.

**Incomplete for what they omit.** The unread `last_run_errors` belongs in that list and is not
there — it is presented as closed. And the lock non-goal understates itself: past 8h the nudge
resumes inviting a second indexer (question 3).

### On R9's blindness admission (honesty and clarity only, as directed)

**Honest and clear.** It states what was lost, what remains ("discipline plus the single-commit
ordering, not … proof from git"), refuses to dress it up in those words, and invites the reader to
discount the result. Critically it **propagated** the downgrade — falsifier (d) was rewritten to say
it no longer proves authorship-before-rebuild, rather than left reading as though it still did.
Background records the cost ("the stale-index baseline … can never be re-measured") instead of
quietly restating a corrected premise. This is the strongest part of the revision.

**One defect in it:** the Background paragraph cites **R7** three times — "the stale-index baseline
in R7", "the blindness ordering R7 relied on", "(see R7 and the falsifier)". The baseline and the
blindness admission are in **R9**. R7 is the installer requirement. A reader following the pointer
lands on `launchctl bootstrap` and may conclude the admission does not exist. A stale cross-reference
in the one paragraph whose entire job is to point at the honesty.

---

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | concern | Round-1 defect genuinely fixed and pinned by a regression scenario. But `last_run_errors`' stated purpose ("distinguish ran-and-failed from ran-and-found-nothing") is met by no reader-facing behaviour, and `memsearch status` still reports `last_indexed`. |
| `execution` | concern | Architecting stage, no code, no test command supplied. Design is testable and the harness exists — I ran `hooks/memsearch-nudge.test.sh`: **5/5 pass, exit 0** (real baseline). Untested branches: `last_run_errors` surfacing, malformed/future `run_started`. Abandonment threshold has no measured basis. |
| `trajectory` | pass | Fixed the exact defect for the right reason; added `run_started` on an articulated safety rationale; refreshed a falsified premise instead of smoothing it; downgraded a guarantee it could no longer support and propagated the downgrade. Reasoning, not luck. |
| `regression` | concern | Existing status keys explicitly unchanged; `test_index.py:94` still satisfied; nudge contract preserved. But the design introduces a **new** silent state (future `run_started` → permanent in-progress) and doubles the non-atomic `write_text` window. |
| `context_budget` | pass | Nudge stays at one line; fresh line grows a few tokens. No always-on rule or skill growth. Single spec file, no split. |
| `traceability` | concern | Seven numbered decisions each state *why*; ADR 0018 scheduled as task 2, before task 3's code; falsifier written before code; toolchain verified not remembered. Deductions: three wrong `R7`→`R9` cross-references in the honesty paragraph; `last_run_errors` defined with no traceable consumer. |
| `success_masking` | **fail** | All-errors run stamps `last_run` and reads **fresh** (verified `index.py:135-137` → `index.py:100` → `cli.py:66`). `last_run_errors` written, never read. The one scenario covering it asserts the write, not the report. No falsifier clause covers it. |
| `intent_drift` | pass | Scope ends at parent item 5, item 6 excluded with a reason; four unrelated items explicitly non-goaled. The one widening (into the `memsearch` package) is disclosed and user-approved. Tasks 6 and 7 split the config change from the golden-query edit, honouring "never edit tests and implementation in the same step". |
| `checkpoint` | concern | `phase: planning` / `branch: none` verified against reality (HEAD = `main`, no impl code, only the spec dirty). Task 1 flips phase and creates the branch before any code. **But `install-schedule` has no uninstaller** — `git revert` does not remove a job from `~/Library/LaunchAgents`, leaving a loaded daemon executing a binary from a checkout that no longer expects it. |
| `audit_trail` | pass | ADR 0018 required for both structural decisions with options weighed; falsified premise recorded with its cost; round-1 verdict cited. Attributable throughout. |

**Risk:** medium · **Confidence:** high

Round 1 was `high`; the load-bearing defect is genuinely closed, which is real progress. Risk does
not fall to `low` because the same *class* of defect recurs in a new field, and no code exists yet.
Confidence is `high`: every source reference re-verified myself, the live run measured, the existing
test suite executed.

---

## Concerns

1. `last_run_errors` is written but read by nothing — an all-errors run reports fresh
2. Future-dated `run_started` yields a permanent in-progress line with no remediation
3. Abandonment threshold reuses `STALE_HOURS`; conflates two different questions
4. Abandonment threshold unmeasured — live run at 1h26m and growing (was 40m when specced)
5. Past 8h the stale line invites a second indexer into a live run, inverting decision 5
6. `memsearch status` (`status.py:27`) still prints `last_indexed` as the staleness answer
7. Non-atomic `write_text`, now twice per run; a torn file is silent, not unknown-age
8. Background cites R7 three times where R9 is meant — in the honesty paragraph
9. `install-schedule` has no uninstaller; a git revert leaves the launchd agent loaded

## Recommended before implementation (advisory — none of this blocks)

- Give `last_run_errors` a reader: warn when `> 0`, and add a scenario asserting the **line**, not
  the field.
- Extend R2's fail-toward-doubt rule to `run_started`.
- Split abandonment into its own constant; record the measured run duration beside it.
- Decide whether `status.py` is in scope; if not, non-goal it explicitly.
- Fix the three `R7` → `R9` references.
- Add an uninstall path, or non-goal it.
