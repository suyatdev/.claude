# Observability judge — `memsearch-freshness` (architecting, advisory) — loop 2, round 2

- **repo:** `.claude`
- **branch:** `main` (`branch_slug`: `main`)
- **head_sha:** `d48513d3f9de0d94b0ab29c1da0815262649c1af`
- **stage:** `architecting` (advisory — does **not** gate a PR; only an implementation-stage verdict does)
- **spec:** `docs/features/memsearch-freshness.md` (717 lines, `phase: planning`, `branch: none`)
- **round:** second compliance loop, round 2 (round 1 = `3b793fa`, `fail` on `intent`/`execution`/`success_masking`)
- **test command:** `cd ~/.claude/memsearch && python3 -m pytest` — **run, with a correction.**
  System `python3` (3.9.6) has no `pytest`; the project is a `uv` project pinned to py3.12.
  Ran as `uv run --project ~/.claude/memsearch --quiet python -m pytest -q` →
  **63 passed, 16 deselected, 0.30s.** Real result, not asserted. The 16 deselected are the point
  of finding 2 below.
- **judged:** 2026-08-07T02:13:54Z (local 2026-08-06 22:13; filename uses the local date to sit
  beside its sibling round files)

**Filename note.** `2026-08-06-main.md` is already occupied by another feature's verdict, so this
directory's established `<date>-main-<feature>-round<N>.md` convention is used. Overwriting a
different feature's verdict to satisfy a filename rule would destroy the audit trail this file exists
to create.

---

## What was changed

Two things, in one spec. **First**, the memory index froze for 19 days and — the part that matters —
*nothing noticed*, while the session-start line kept cheerfully announcing "N chunks indexed" every
morning. The fix is a smoke alarm plus a timer: a `launchd` job re-indexes every 6h, and the
session-start line now reports *when the indexer last finished*, going `⚠ stale` past 8h. **Second**
(R10), the big session-history archive `CODING_MEMORY.md`, which the tool was explicitly configured
never to read, gets indexed — with its own low weight tier so 3,232 lines of narrative can't outrank
the decision records that narrate it.

Think of it as: the freezer broke and nobody knew, because the only thermometer was showing the
temperature of the *room*. This spec adds a thermometer inside the freezer, a timer that opens the
door every 6h, and — separately — puts a box back in that someone had banned three years' worth of
recipes ago.

## Does it do what you wanted?

**Yes — and round 1's fatal defect is genuinely fixed, not papered over.** Last round R10 would have
indexed nothing that mattered: lifting the ban did not help, because `~/.claude/CODING_MEMORY.md` was
never on a road the indexer drives down. The spec now adds it to `curated_docs` (the road), adds a
**negative-control scenario** that fails if only the ban is lifted, extends the fixture to cover the
`~/.claude`-root position that the old fixture quietly faked, and makes task 9 confirm the *exact*
path rather than "one per repo". That is the right shape of fix, and I verified each part against the
live source.

Everything load-bearing the spec cites, I checked and it is true:

| Spec claim | Verified |
|---|---|
| the guard is `config.py:57-60`, and `:56` must survive | exact |
| `_iter_docs` hardcodes `source_type` per bucket (`index.py:44-51`) | exact |
| `SOURCE_TYPES` at `db.py:16` | exact — and **no SQL `CHECK` constraint**, so `archive_doc` needs no DB migration |
| golden query is **line 4**, not line 2 | exact |
| `test_index.py` `processed` counts at 84/135/149/160 each rise by one | exact — all four confirmed |
| `test_index.py:58` fixture writes the file *inside* the curated dir | exact — this is the pre-created-condition trap, correctly named |
| `status.py:27` prints `last_indexed` as its freshness answer | exact |
| `digest_input_char_cap` doesn't touch docs | exact — and `chunk_doc` caps sections at 2,000 chars, so the 285k archive splits safely; no oversized-embed risk |

**The trajectory is the strongest part of this spec.** It retracts its own fabricated run-duration
figure in the text rather than quietly deleting it, retracts an earlier sleep concern with named
machine-specific evidence, names three measurement traps that each produced a confidently wrong
answer, and writes its falsifier before the code — then *weakens* falsifier (d) in public when the
orphaned rebuild destroyed its proof. That is honest engineering, and it is why `trajectory`,
`traceability`, and `audit_trail` all pass.

## What could go wrong / what I'm unsure about

No dimension is `fail`. Four things are worth your attention, two of them new this round.

**1. The archive lands in the wrong drawer (new).** R10's whole justification is *"three weeks of
decisions and history exist only in this file."* But `chunk.py:111` decides the retrieval bucket by
path substring: `"decision" if "decisions" in path else "doc"`. So every chunk of the archive becomes
`recall_type = doc`. The session-start line itself advertises `--type decision|episodic|doc`. After
R10, someone asking for **session history** with `--type episodic`, or for **decisions** with
`--type decision`, *still* misses the archive — the hole is narrowed, not closed. Unfiltered queries
do reach it, so this isn't fatal, but the spec adds a new `source_type` tier and says nothing about
`recall_type` at all. Related: the replacement golden query is described only as "retrieves session
history from `CODING_MEMORY.md`" — if an implementer writes it with the natural `{"rtype":
"episodic"}` filter (the existing suite has exactly such a query at line 12), **it fails**, and
nothing in the spec warns them.

**2. "Run the full suite" runs none of the retrieval tests (new).** `pyproject.toml` sets
`addopts = "-m 'not golden'"`. My run: *63 passed, **16 deselected***. Those 16 are
`test_golden_queries.py` — the real retrieval-quality net, run against the live index, and precisely
the regression net for the noise risk R10 introduces. Task 7 says "run the full suite"; that will go
green with every retrieval assertion switched off. Nothing in tasks 7–10 schedules `-m golden`, so
**the replacement golden query R10.5 writes is never executed** by the plan that writes it. A test
written and never run is the same defect this feature exists to fix, one file over.

**3. The duration measurement measures the wrong run.** Task 9 records the wall-clock of the first
scheduled run and escalates if it exceeds `RUN_MAX_HOURS`. But that run is a *warm incremental* one
against a mostly-rebuilt index; `RUN_MAX_HOURS` has to cover the *worst* run — a first backfill or an
`index --full` (which `model_mismatch` actively tells you to run). A small number from task 9 would
look like validation and wouldn't be. Consequence is alert fatigue, not damage: a long legitimate run
shows the *stuck* line, whose remediation is deliberately "check before starting another".

**4. R10 has no way back, and the spec plans for needing one.** R7 gets a first-class removal path
(`--uninstall`, no-op success, never touches `memory-index/`) — good. R10 gets none: **there is no
prune anywhere in the indexer.** `replace_source` only updates paths it re-visits; nothing deletes a
source that disappears from config. So if R9 fails and you re-exclude the file, its ~150+ chunks stay
in `memory.db` and keep polluting results; only `index --full` (which unlinks the DB and rebuilds over
hours) purges them. The spec explicitly contemplates R9 failing and forbids quietly re-excluding —
but never says what the way out costs. This was raised last round and is still unaddressed.

**On the three open items you flagged — the current spec text does not change my read.** All three
stand exactly as written:

- **`last_run_errors` has no unusable/missing rule.** The contract's usability rule is explicitly
  scoped to *timestamps* ("for both fields" = `last_run`, `run_started`). A missing or garbage
  `last_run_errors` — e.g. a `status.json` written by the pre-upgrade code, or by the orphaned manual
  run — takes the natural `0` default and prints the **reassuring fresh line**. That is R2's own
  "fail toward doubt" principle applied to two fields out of three.
- **A permanently-failing source pins the degraded warning forever** — and R10 makes this *likelier*,
  not less: it adds the corpus's single largest file, and any source that fails every run holds
  `last_run_errors > 0` in perpetuity, firing decision 1's own alert-fatigue failure through the one
  channel that reports real failures.
- **The degraded line still points at re-running the indexer, never at `scheduled-index.log`** — the
  evidence R6 goes out of its way to create, with `PYTHONUNBUFFERED` set specifically so its tail
  survives. The spec builds the evidence and then points the reader away from it.

Two smaller ones: the archive's `session_date` is the *file's mtime*, so ~30 sessions of narrative all
date to the run — `--since` filters will mis-date July history as today. And R10.6 enumerates plan
lines 19 and 2828, but that file also restates the retired premise at **line 2890** (an example query
"why is CODING_MEMORY.md excluded…") and **line 2942** (the golden-query JSON) — both prose, both
inside the indexed `docs/` corpus, both matching the spec's own stated worry that "a missed line
becomes a retired rule the index will serve as current". The design-doc enumeration, by contrast, I
checked as complete.

## What I'd double-check before merging

1. **Decide `recall_type` for the archive** before task 7, and say so in the spec — `doc`, `episodic`,
   or per-section. Then pin the replacement golden query's filters explicitly.
2. **Add `-m golden` to task 10** (or to task 7's verification), and say what a golden failure means.
   Without it, the retrieval net is off during the one change that stresses it.
3. **Re-word task 9** to measure, or at least name, the worst-case run — and note that the incremental
   figure is not the one `RUN_MAX_HOURS` must cover.
4. **State R10's exit cost** in a sentence: "reverting the config does not un-index the file; purging
   requires `index --full`." Even as a non-goal, it belongs next to R9's anticipated failure.
5. **Close or explicitly waive the three open items** — especially the `last_run_errors` default,
   which is the one place this design still prints a reassuring line it cannot prove.
6. Point the degraded line at `scheduled-index.log`. One word, and the evidence R6 creates becomes
   reachable.

---

## Dimensions

| Dimension | Verdict | Why |
|---|---|---|
| `intent` | concern | Round-1's fatal reachability defect is properly fixed and verified. But `recall_type` stays `doc` for the archive, so `--type decision`/`--type episodic` still miss the history R10 exists to expose — unacknowledged. |
| `execution` | concern | Every cited line/number verifies against source; suite green (63 passed). But task 7's "full suite" deselects all 16 retrieval tests, and task 9 measures a warm incremental run against a worst-case threshold. |
| `trajectory` | pass | Self-correcting and evidence-led: fabricated duration retracted in-text, sleep concern retracted with named evidence, three measurement traps recorded, falsifier written first and publicly weakened when its proof was lost. |
| `regression` | concern | Test deltas enumerated precisely, including the four `processed` counts a literal implementer would trip on, and `archive_doc` needs no DB migration (no `CHECK` constraint). But the retrieval-quality net is deselected by default and unscheduled, and `cfg.weights[st]` raises a `KeyError` on partial application that `_index_one` swallows into `errors` with exit 0. |
| `context_budget` | pass | A feature spec under `docs/features/`, not always-on context. The nudge stays at exactly one line on every path. |
| `traceability` | pass | Retractions dated and kept, evidence measured not remembered, two ADRs scheduled, a data-flow diagram whose dotted edge names the load-bearing dependency. |
| `success_masking` | concern | Round-1's `fail` is properly fixed with a negative-control scenario. Three live masking paths remain: a missing `last_run_errors` prints the fresh line; "full suite" green with retrieval assertions off; a warm incremental duration reading that would falsely validate `RUN_MAX_HOURS=6`. |
| `intent_drift` | pass | Tight scope; non-goals fence off item 6, a lock/pidfile, the promotion pipeline, the exit-code contract, and two unrelated backlog items. R10 is a user-requested reversal, recorded as such. |
| `checkpoint` | concern | `launchd` removal is first-class and correctly reasoned (it lives outside the repo, so `git revert` misses it). The index side has no counterpart: no prune exists, so R10 cannot be undone without a multi-hour `index --full`, while the spec explicitly anticipates wanting out. |
| `audit_trail` | pass | ADR 0018 and 0019 both scheduled with the options to weigh; the `archive_doc` tier attributed to a dated user decision; reversals of prior rationale recorded rather than overwritten. |

**risk: medium** — no `fail`; the round-1 defect is genuinely closed. Medium rather than low because
R10 is irreversible in practice against a failure mode the spec itself anticipates, and the
instrument that would catch that failure is switched off by default.

**confidence: high** — every load-bearing claim was checked against source or the live index, and the
test suite was actually run.

## Concerns

1. `recall_type` for the archive is hardcoded `doc` (`chunk.py:111`); `--type decision|episodic` still misses the history R10 exists to expose
2. task 7's "full suite" excludes all 16 golden retrieval tests (`addopts = -m 'not golden'`); R10.5's replacement query is never run
3. task 9 measures a warm incremental run; `RUN_MAX_HOURS` must cover the worst run, so a small figure falsely validates 6h
4. no prune exists in the indexer: reverting R10's config leaves its chunks in `memory.db`; only `index --full` purges, unlike R7's first-class uninstall
5. R10.6 names plan lines 19 and 2828 but misses 2890 and 2942, which restate the retired premise inside the indexed corpus
6. `last_run_errors` still has no unusable/missing rule; the natural `0` default prints the reassuring fresh line (open, awaiting user)
7. a permanently-failing source still pins the degraded warning on forever — likelier now that R10 adds the corpus's largest file (open)
8. the degraded line still points at re-running the indexer, never at `scheduled-index.log`, the evidence R6 creates (open)
9. the archive's `session_date` is the file mtime, so ~30 sessions of narrative date to the run; `--since` filters mis-date it
10. `cfg.weights[st]` raises `KeyError` on a partial R10 application, swallowed into `report["errors"]` with exit 0
