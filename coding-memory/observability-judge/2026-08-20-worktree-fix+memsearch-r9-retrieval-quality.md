# Observability verdict — ADR 0030 (architecting)

- **Repo:** fix+memsearch-r9-retrieval-quality (worktree)
- **Branch:** `worktree-fix+memsearch-r9-retrieval-quality`
- **HEAD:** `052dd5da2b0bd94fcb271d232a8e659786f7f220`
- **Stage:** architecting (advisory — blocks nothing)
- **Artifact:** `docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md` (262 lines)
- **Date (UTC):** 2026-08-20T18:07:52Z

## What was changed

Nothing runs differently yet — this is a plan, not code. The plan says: judge verdicts
(the files this very agent writes) are currently ranked as importantly as specs and ADRs
when memsearch answers a query, and because verdicts are long, they crowd out the shorter
documents they grade. So verdicts get their own dial. Two supporting moves make that dial
actually turnable: the importance number stops being stamped into every row of the database
at index time and is instead looked up fresh at query time, and a new `index --reclassify`
pass re-labels the rows that already exist without redoing the expensive embedding work.
The quality bar R9 stays failing and stays written down.

Confirmed by diff: only `CODING_MEMORY.md`, the ADR, and the feature file changed. **No
implementation exists, correctly.**

## Does it do what was intended?

Yes, and the reasoning is unusually well-audited. I re-opened every code citation and all
held: `index.py:169` (weight read at index time), `db.py:75`/`db.py:134` (stored column),
`search.py:24`/`search.py:80` (read and multiply), `test_measurement_queries.py:120-123`
(score ceiling) and the retired score-floor rationale at the top of that file. The venv's
SQLite really is 3.53.3, so `ALTER TABLE … DROP COLUMN` is genuinely available. The
diagnosis — a config edit cannot move a ranking because the value is frozen into the rows —
is correct as written.

**On the adoption rule (your falsifiability question): it can fail, and that is rare.**
Baseline is measured in the same run, improvement must be *strictly* greater, no target may
lose hits, no target may lose its top hit, and "adopt nothing, ship 1.5, record R9 unchanged"
is written down as a legitimate outcome. That closes the usual escape hatches. The one
remaining hole is the one you already suspected: the rule says the sweep rows must be taken
"against the same index state", but names no mechanism to *prove* they were. The corpus is
live and a scheduled indexer writes to it. If it moves mid-sweep, nothing in the plan detects
it and the baseline comparison quietly stops meaning anything.

## What could go wrong

1. **Dropping the `weight` column has no cheap rollback, and one is available.** The plan's
   rollback is `index --full` — a documented multi-hour re-embed. The database is a single
   75 MB file. Copying it before the `ALTER TABLE` would turn a one-way migration into a
   ten-second revert. The plan does not ask for that copy, which sits badly against the
   house checkpoint-before-modify rule.
2. **The migration fires from the database-open path, so a plain `query` can mutate schema.**
   A read-only lookup — including the one the SessionStart hook runs — becomes a writer for
   one run. If the scheduled indexer holds the lock at that moment, the plan's own fail-closed
   rule turns a routine query into a hard error. That is the safe direction, but it is a
   user-visible failure mode the ADR does not acknowledge.
3. **No schema-version marker.** Old code against a migrated DB fails on `SELECT … weight`
   with a raw SQLite error rather than a named "this database is newer than your code".
   A `PRAGMA user_version` bump is a two-line addition; `db.py` has none today.
4. **Reclassify reports transitions but no denominator.** Per-transition counts are the right
   call and directly answer your worry — a bare "185 files updated" would hide a
   wrong-direction move. But without a *files walked* total and an *unchanged* count, a reader
   cannot tell a complete walk from a truncated one that happened to produce plausible
   transitions. Adding "walked N, changed M, unchanged N−M" and a post-pass re-check that zero
   disagreements remain would make the pass self-proving rather than self-asserting.
5. **The one number the ADR measured itself is already wrong.** It states the judge directories
   hold "163 and 22 files, 185 together". Only `*.md` is walked (`index.py:65`), so the real
   split is **162 and 23** — the total is right by coincidence, the parts are not, and the two
   figures were counted by different methods. Tiny in magnitude, but it is precisely the
   stale-pinned-count species this whole feature exists to eliminate, appearing inside the ADR
   that argues against it.
6. **`README.md` in each judge directory becomes a `judge_doc`.** 2 files of 185. Harmless,
   but the tier is named for verdicts and will not contain only verdicts.

**On the known limitation: accepting it is defensible and it is recorded clearly.** The
regression was never diagnosed and the pinned state needed to diagnose it is gone — you cannot
investigate a state that no longer exists. The ADR says so twice, in "Consequences" and in the
measurement-instrument note, and explicitly frames the change as tuning a proxy whose number
"will not generalize". A later reader will not mistake this for a root-cause fix.

## What I'd double-check before implementing

- Add the pre-drop database file copy, and name it in the ADR as the rollback.
- Record `chunk` count (or DB mtime) at the start and end of the sweep, and abort the sweep if
  it moved — otherwise clause 1's "same run" guarantee is unenforced.
- Give reclassify a walked/changed/unchanged denominator and an idempotency re-check.
- Fix 163/22 → 162/23, or state the counting method.
- Decide whether a `query` should be allowed to migrate schema, or whether the drop belongs
  behind an explicit `index` invocation.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Diagnosis correct; every code citation re-verified |
| execution | concern | Design stage, nothing runnable; sweep-state pinning unspecified |
| trajectory | pass | Alternatives enumerated with measurements, scope corrected three times |
| regression | concern | Destructive drop from the db-open path; lock contention with the scheduled indexer |
| context_budget | pass | On-demand ADR; adds nothing to always-on context |
| traceability | pass | Citations hold; the no-line-numbers policy for the moving doc is justified |
| success_masking | concern | Live corpus can drift under the sweep undetected; reclassify has no denominator |
| intent_drift | pass | Diff is ADR + feature file + memory only; no deps, no drive-by edits |
| checkpoint | concern | One-way migration with no DB backup; rollback is a multi-hour rebuild |
| audit_trail | pass | ADR-worthy, limitations explicit; one self-measured count off by one each way |

## Concerns

- No pre-drop database backup; rollback is a multi-hour `index --full`
- Schema migration triggered from the db-open path, so `query` can mutate schema and hit lock contention
- No `PRAGMA user_version` marker; old code meets a migrated DB as a raw SQLite error
- Sweep requires "same index state" but specifies no mechanism to detect corpus drift
- Reclassify reports transitions without a walked/unchanged denominator or idempotency re-check
- Self-measured file counts stated 163/22; actual `*.md` split is 162/23
- `README.md` in each judge directory is classified `judge_doc`

**risk=medium confidence=high**
