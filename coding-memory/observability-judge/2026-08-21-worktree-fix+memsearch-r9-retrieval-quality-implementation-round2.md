# Observability verdict — implementation (round 2)

- **Repo:** `fix+memsearch-r9-retrieval-quality` (worktree)
- **Branch:** `worktree-fix+memsearch-r9-retrieval-quality`
- **HEAD:** `eef95be65ec1d6dd29f3fd84c76cdc11a9aa402c` (read at judge time; round 1 ran at `ee81648`)
- **Base:** `main` (merge-base `5d4d71d`)
- **Stage:** implementation
- **Timestamp:** 2026-08-21T04:54:34Z
- **Test command run by me:** `cd memsearch && uv run pytest -q` → **104 passed, 23 deselected in 0.58s** (matches the reported result)

## What was changed

Think of the search index as a library where every shelf has a "trust multiplier". Before this
change, that multiplier was **glued onto every book when it was shelved**, and judge verdicts had no
shelf of their own — they sat with ordinary repo docs.

Three things changed:

1. **Judge verdicts get their own shelf**, `judge_doc` (`memsearch/memsearch/index.py`,
   `_doc_source_type` now checks the parent directory name against
   `{observability-judge, compliance-judge}`).
2. **The multiplier is read off a sign on the shelf instead of glued to each book.** The
   `chunks.weight` column is dropped under a versioned migration (`PRAGMA user_version 0 → 1`), and
   `search.py:_weight_for` looks the number up in `config.json` on every query. Retuning a weight is
   now a config edit, not a multi-hour re-embed.
3. **The new shelf's number was chosen by measurement**, not taste: a sweep harness
   (`memsearch/tests/sweep_judge_weight.py`) scores R9 at 1.5/1.4/1.3/1.2/1.1/1.0 and *computes* the
   adoption, printing `ADOPT judge_doc = 1.2 (R9 2 of 5 -> 3 of 5)`.

Plus the round-2 additions: **task 13** on the feature card (the post-merge two-step, with an
acceptance number) and one **Roadmap line** in the root `README.md`.

## Does it do what was wanted?

Yes, with one honest limit stated everywhere it matters: **R9 still fails, 3 of 5 against a 5-of-5
bar, and the bar was not moved.** That is stated in the feature-card frontmatter note (`:16`), in the
ADR head (`:16`), and in a section literally headed *"R9 after the change — still failing, bar
untouched"* (`:1868-1873`), which adds the anti-gaming reasoning for not redrawing the bar. Nothing
is soft-pedalled. Shipping a measured partial improvement with the bar intact is the right call —
the alternative is a bar rewritten after seeing the score, which this feature already retired once.

**Your round-1 recommendation was wrong; you were right to reject it.** I re-read the code:
`_take_backup` is defined at `memsearch/memsearch/db.py:135-152` and called from `migrate()` at
`:175`, *after* the version check and *before* the drop. The copy therefore cannot exist until step 1
has run. Task 13's instruction to check `<db>.pre-v0.bak` **between** the two steps is correct, and
its note that `db.py:142-144` deletes copies from earlier migrations is also correct. Every line
citation in task 13 verified.

Verified independently:
- Plan-defect fix 1 (rollback): `migrate()` uses explicit `BEGIN IMMEDIATE` / `commit` / `rollback`
  with `PRAGMA user_version` set *inside* the transaction, and the comment names the exact reason
  (`sqlite3` opens an implicit transaction for DML only). `test_a_failure_after_the_drop_rolls_the_drop_back`
  and `test_a_failed_drop_leaves_the_database_untouched` both exist and pass.
- Plan-defect fix 3 (the test that could not fail): `test_search.py:173` now asserts
  `out[0] == approx(3 * out[1], abs=2e-6)`, with the tolerance derived from `search()`'s 6-decimal
  rounding — a real discriminator, not a tie.
- Adoption is not fitted to the Task-1 seed: `sweep_judge_weight.py:165-180` computes eligibility
  from the three clauses and takes the eligible row closest to 1.5. 1.4 and 1.3 are rejected on
  `pass count 2 not > baseline 2`; 1.2 is simply the first eligible row.
- Round-1's two parked Minors are **fixed**, not still parked: the ADR misquote now reads "today's
  **effective** behaviour" (card `:1846`) and `memsearch/README.md:24-26` no longer claims the schema
  never converts itself.
- Fail-closed behaviour is real: `search()` refuses an unmigrated DB, `run_reclassify` refuses one
  too, `_weight_for` raises rather than defaulting, and `config._validate_weights` rejects a config
  missing any known source type at load time.

## What could go wrong / what I am unsure about

- **The change is inert until a human runs two commands, and nothing fails if they don't.** Skip
  `index --reclassify` and ~97% of this does nothing (108 vs 3609 `judge_doc` chunks) while all 104
  tests pass and `memsearch status` reads healthy. Task 13 makes this a tracked task with a numeric
  acceptance — a genuine improvement over README prose — but it is still a checklist item, not a
  guard.
- **The green suite does not test the thing this branch exists to fix.** `pyproject.toml:26` sets
  `addopts = "-m 'not golden and not measurement'"`, so the 23 deselected tests include every R9
  measurement query. "104 passed" is a unit-level statement about migration, reclassify and weight
  plumbing; it says nothing about retrieval quality.
- **The 6h post-merge blind spot is real and unfixed in code.** `status_report` gained a
  `MIGRATION REQUIRED:` line, but `status.json` — the only thing the SessionStart hook reads — does
  not carry it (`status.py:57` says so in a comment). So `memsearch query` refuses while the session
  banner still says the index is fine, until the launchd run migrates it. Documented in task 13;
  self-healing within 6h; low severity, but it is exactly the shape of failure this rubric exists to
  name.
- **The split record is now the standing traceability hazard.** ADR 0030 keeps two statements known
  to be wrong (the `with conn:` migration, and "1.5 == today's effective behaviour", false for 153
  chunks), the corrections live only in the feature card, and **round 2 deliberately added no forward
  pointer from the ADR.** A reader who lands on the ADR — the durable, "accepted", compliance-passed
  artifact — meets both wrong statements with no signal a correction exists. The reason not to edit
  (retriggering the compliance gate) is a process cost, not a correctness argument. This is the one
  place I would push back: a single italic line naming the card as the corrected record is cheaper
  than the eventual reader who trusts the ADR.
- **The migration is one-way and its rollback is self-deleting.** `_take_backup` unlinks copies from
  earlier migrations (`db.py:142-144`), so exactly one restore point exists at a time.
- **The tier keys on a directory *name* anywhere under a configured repo root**, so any future
  `observability-judge/` directory is silently promoted. Pinned by a test, deliberate, but it is a
  live exposure rather than a closed one.
- Minor, non-blocking: `reclassify.py` imports the private `index._iter_docs` across a module
  boundary; the `vanished` set subtracts `s.split(":")[0]`, which mis-parses a path containing a
  colon (affects a reported count only); and two version markers now coexist (`meta.schema_version`
  and `PRAGMA user_version`) with nothing stating which is authoritative.

## What I would double-check before merging

1. Run task 13's two commands **in order**, against the real index, and check the acceptance number:
   `memsearch status`'s `by source_type` must show `judge_doc` in the thousands, not ~108. Between
   the steps, confirm `<db_path>.pre-v0.bak` exists and is non-empty (not before step 1 — it cannot
   exist yet).
2. Run `uv run pytest -m measurement` against the real index after the reclassify pass and confirm
   it still reports 3 of 5, not fewer. The default suite cannot tell you this.
3. Decide the ADR forward-pointer question explicitly rather than letting it stay parked — it is a
   one-line edit versus a permanently misleading accepted decision record.
4. Confirm no other machine or checkout is mid-`memsearch query` when step 1 runs; the migration is
   one-way and the shared index is ~82 MB.
5. Leave `coding-memory/**` uncommitted as instructed; the verdict must stay uncommitted until the
   PR is open (judge-guard wants `head_sha == HEAD`).

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | ADR 0030's three parts are all built; the partial R9 result is stated plainly in three places |
| execution | pass | `104 passed, 23 deselected` re-run and observed by me at `eef95be` |
| trajectory | pass | Three plan defects reproduced before being fixed; adoption computed by the harness, not chosen; a wrong controller instruction was caught and recorded |
| regression | concern | One-way migration with a single self-deleting backup; unmigrated-index refusal window; live shared index at `user_version 0` |
| context_budget | pass | No always-on rule/skill growth; one Roadmap line; all detail is on-demand docs |
| traceability | concern | ADR 0030 knowingly retains two wrong statements with no forward pointer to the corrected record |
| success_masking | concern | Default suite deselects every R9 measurement test; skipping the reclassify pass leaves the change inert with a fully green suite and a healthy status line |
| intent_drift | pass | Diff confined to `memsearch/` plus ADR/card/README; no new dependencies; round-2 edits are directly responsive to round 1 |
| checkpoint | pass | Small ordered commits; migration takes a restorable copy before the drop, with rollback covered by tests |
| audit_trail | pass | ADR + canonical feature card + ledger with full round history; both round-1 parked Minors closed in `ee81648` |

## Concerns

- Default `pytest -q` deselects all 23 golden/measurement tests, so the green suite never exercises R9 — the bar this branch exists to move
- The post-merge `index --reclassify` pass is manual and unenforced; skipping it leaves ~97% of the change inert (108 vs 3609 judge_doc chunks) with every test green
- ADR 0030 still carries two knowingly-wrong statements and round 2 deliberately added no forward pointer to the feature card's corrections
- Up to a 6h window where `memsearch query` refuses while the SessionStart line, which reads status.json only, still reports the index healthy
- Schema migration is one-way and the rollback copy is deleted by the next migration
- R9 remains red at 3 of 5 against a 5-of-5 bar — correctly reported and deliberate, but the feature does not close
- judge_doc keys on any `observability-judge`/`compliance-judge` directory name under a configured repo root
- Minor: `reclassify.py` imports private `index._iter_docs`; `vanished` mis-parses a colon-bearing path; `meta.schema_version` and `PRAGMA user_version` coexist without a stated authority

**risk=medium confidence=high**
