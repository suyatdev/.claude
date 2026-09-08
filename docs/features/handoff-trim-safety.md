---
phase: planning
model_tier: high
branch: none
---

# Handoff trim safety — stop the session notepad losing facts

`.claude/session-state.md` is the notepad the next session reads after a `/clear`. Past its
line cap the only mechanism is a directive telling the model to delete text: no copy is kept,
nothing is marked un-cuttable, and separately the session-start reader drops the entire body
past 8192 bytes. Facts vanish silently, twice over.

Live proof, not theory: `mtg-wizard` was 235 lines at 10:42 on 2026-09-08 and 64 lines at
13:56 the same day — roughly 171 lines cut with no snapshot and no record, while this card
sat waiting to be judged.

**Measured evidence, the fifteen user decisions D1-D15, and the full spec live in
[`handoff-trim-safety.spec.md`](handoff-trim-safety.spec.md).** Read it before implementing;
do not read it at session start.

Status: planning, round 3 revision. Compliance FAILED twice — 9 violations in round 1, 8 in
round 2 — and the observability read failed its `success_masking` dimension in round 2. Every
finding from both rounds was independently re-measured before being acted on, and every one
held. Two round-2 findings were defects the design would have shipped: the replacement
memsearch globs matched **zero** files, and the evidence table carried a byte-per-line range
that re-measurement falsified. **D16 is answered** (2026-09-08): a secret-looking cut block goes to
`session-state.quarantine.md`, never the archive, never indexed, deletable by hand. **D17 is
answered**: the read cap is 24,576, confirmed by the user against the arithmetic and the
context cost, superseding the ~12,000 in D6. (superseded: D16 open, what happens to a
block that looks like it contains a secret). The gate has not opened.

## Tasks

Ordered so every step is independently useful and nothing depends on a later step. Tasks 1-4
are the safety floor; 5-8 remove the loss; 9-11 are enforcement; 12-15 are reach.

- [ ] 0. Extract `gen_tag`, `sanitize_line` **and the three module-level values they read**
      (`MARKER_PATTERN`, `TAG_BYTES`, `URANDOM_SRC`) from `slim-session-start.sh` into
      `hooks/handoff/lib/handoff-archive.sh`, with tests, and leave both call sites behaving
      identically — before anything new consumes them. Moving a working function out of a hook
      that currently passes its tests is the riskiest edit in this list, so it goes first and
      alone.
- [ ] 1. `hooks/handoff/lib/handoff-archive.sh` — snapshot, `[KEEP]` region extraction with
      full fence tracking (`awk` with an explicit fence-state variable), archive append,
      rotation, secret flagging, quarantine. Line membership uses `grep -F -x -q`, never a
      regex. Pure library, no hook wiring. Tests first, fence cases first among those.
- [ ] 2. `live-handoff.sh` snapshots on **every** turn to a per-session filename, and
      **suppresses the trim directive** if the snapshot cannot be written.
- [ ] 3. `.gitignore` coverage confirmed in all six repos holding a notepad — measured with
      `git check-ignore`, never assumed. Covers `session-state.archive*`, `.pretrim.*`,
      `.keepguard-strikes.*`, `.keepguard.log` and **`session-state.quarantine.md`** — the one
      file designed to hold secrets, and the one left off this list until round 3.
      `mtg-wizard/.gitignore` and `vibe-scape/.gitignore` list `.claude/` files one by one, so
      none of these is covered there today. This task runs **before** anything that creates
      the files, not seventeen tasks after it.
- [ ] 4. Stale-snapshot reaper in `slim-session-start.sh`: append to the archive, then delete.
- [ ] 5. Raise the write caps to 150/120, 170/140, 190/160 in **both** `live-handoff.sh:40-49`
      and `pre-compact-handoff.sh:85`.
- [ ] 6. Raise `SLIM_HANDOFF_MAX_BYTES` to 24576 and replace the body-drop
      (`slim-session-start.sh:84-88`) with truncate-and-say.
- [ ] 7. Rewrite the trim directive in both hooks: cutting means filing into the archive, and
      the protected headings are re-injected verbatim.
- [ ] 8. Route `pre-compact-handoff.sh` through the same snapshot. This is the pre-clear path
      the original bug report came from.
- [ ] 9. `hooks/handoff/handoff-keep-guard.sh` as a `Stop` hook: protected-block check, strike
      cap with reset on both exits, mechanical archive append, liveness heartbeat. Block
      messages carry headings and counts only — never notepad body lines.
- [ ] 10. Confirm the `Stop` hook JSON contract against the installed binary, not the docs
      page, and pin the finding in a comment.
- [ ] 11. Register the guard in `settings.json` under `Stop`.
- [ ] 12. Guard-liveness reporting in `slim-session-start.sh`.
- [ ] 13. `pre-compact.sh` injects `session-state.md` first (D7).
- [ ] 14. memsearch: `archive_roots`/`archive_pattern` via `Path.rglob`, zero-match reporting, `_doc_source_type`
      widened off the retired `CODING_MEMORY.md`, and a `--reclassify` run so `archive_doc`
      becomes a usable health signal.
- [ ] 15. Document the `[KEEP]` convention in `skills/managing-session-memory/SKILL.md`, and
      tag the sections that need protecting in this repo notepad as the first real use.
- [ ] 16. ADR under `docs/decisions/` for the two structural decisions this design takes:
      D11 (an append-only store that rotates and is never deleted) and D12 (that store being
      permanent, gitignored and machine-local). `rules/gates.md` requires an ADR for structural
      decisions and the previous revisions did not schedule one.
- [ ] 17. Commit the `.gitignore` fix for the exposed root running log. Applied on disk and
      effective since 2026-09-08, but held out of the docs-only commits to `main`, so it has
      no commit of its own yet and would be lost by a clean checkout.
- [ ] 18. Reap the quarantine path: `session-state.quarantine.md` needs its own gitignore
      coverage, its own exclusion from indexing, and a stated purge procedure — the retention
      trade-off is D16, answered: quarantine file, not redaction, not archive-as-normal.

Split into `handoff-trim-safety.spec.md` at 719 lines, exercising the MAY in
`rules/gates.md` (one-canonical-file discipline). The card keeps frontmatter, tasks and
verification — what a restore needs; the companion keeps evidence, decisions and the spec —
what an implementer needs. There is no third progress document, and there will not be one.

## Verification

Written in answer to observability finding O3. The empty section was itself the finding.

**The measurement that decides whether this works.** Not "the archive file exists" and not
"the tests pass" — both of those are true of a design that archives nothing.

1. Seed the notepad with N unique, greppable tokens, at least one inside a `[KEEP]` region
   and at least one outside it.
2. Drive a real trim through the real hook, not a simulation.
3. Assert every token that left `session-state.md` is **byte-present** in
   `session-state.archive.md`, and that every `[KEEP]` token is still in the notepad.
4. **Then stub out the archive append and re-run.** The test must go red. A check that cannot
   fail has measured nothing (finding O4, and memory `feedback_confirm_the_check_can_fail`).

**Falsifiers to build before believing any green run.** Each must be shown to produce a red:

| Mutation | Must be caught by |
|---|---|
| Archive append deleted | the seeded-token test |
| `[KEEP]` heading regex made to match nothing | the protected-line scenarios |
| Fence tracking removed | the heading-inside-a-fence scenarios, both directions |
| Strike reset removed | the fail-open scenario, run twice |
| Snapshot-failure suppression removed | the read-only-directory scenario |
| Liveness log write removed | the guard-has-not-run scenario |
| Zero-match root warning removed | the memsearch root scenario |
| Matcher reverted to `glob.glob(..., recursive=True)` | the archive-root test, which asserts a non-zero live match |
| Archive-append failure handling removed | a read-only-archive scenario |
| `decision=unprotected` collapsed back into `allow` | a no-snapshot scenario reading the log line |
| Log-write failure silenced | a read-only-log scenario |
| Quarantine reverted to skipping the whole file | an indexer scenario asserting the rest of the archive still indexes |
| Envelope removed from the block reason | a scenario feeding a notepad heading that mimics an envelope marker |
| Reaper moved back below the early exits | the deleted-notepad scenario, which must still archive the snapshot |

**R1 is measured at runtime, not asserted between constants.** The test walks the live notepad
population, computes bytes per non-blank line for each, and reports the maximum against the
configured read cap. It is allowed to report a shortfall — that is the point. A shortfall is
degraded-but-safe, because the reader truncates rather than blanks; a *blank* is a failure.

**Rollout evidence to collect once live (D14 chose full immediate enforcement).**

- Every repo has a `session-state.keepguard.log` with at least one line. A repo without one
  means the registration did not take there.
- At least one real trim has produced an `Auto-captured` block whose line count matches the
  drop in the notepad line count.
- `mtg-wizard` specifically: it lost roughly 171 lines unrecorded on 2026-09-08 while this
  card was being judged. The first trim after rollout must leave a record.
- memsearch reports zero-match on no configured glob.

**Falsifier coverage is a claim to re-check, not a property to assert.** An earlier revision
stated every control had one; review then found five rows pointing at scenarios that did not
exist, and those five were exactly the controls added to fix the round before. They have since
been written. Check it by listing the scenarios and matching them against the table, which is
what caught it — not by reading this paragraph. Round 2 found that several controls added in
response to round 1 had none — the new surface shipped unasserted, which is the failure
recorded in `feedback_ship_the_control_with_its_test`. The table above is the response, and it
is the thing to re-check first when a later revision adds another control.

**Explicitly not proven by any of the above:** that a secret is never archived (gap 7), that a
subagent edit is caught (gap 1), or that a determined model cannot delete the snapshot first
(gap 2). Those are stated limits, not test targets.
