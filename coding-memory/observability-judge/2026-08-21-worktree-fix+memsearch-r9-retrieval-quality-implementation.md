# Observability judge — implementation verdict

- **repo:** `fix+memsearch-r9-retrieval-quality` (worktree of `~/.claude`)
- **branch:** `worktree-fix+memsearch-r9-retrieval-quality`
- **head_sha:** `ee81648e866da9e85e458d8755943032d40309a9`
- **base:** `main` (merge-base `5d4d71d35981d1880aa2c06ec96c79d671c13cf8`)
- **stage:** implementation
- **ts:** 2026-08-21T04:46:58Z
- **risk:** medium · **confidence:** high

---

## What was changed

The memory search tool keeps a private index of this repo's documents so you can ask it
questions in English. When it ranks answers, it multiplies each result's score by a number
that says "documents of this kind matter this much." Three things changed:

1. **Judge verdicts became their own kind of document.** They used to be filed under the same
   label as ordinary repo docs and specs. Now anything sitting in an `observability-judge/` or
   `compliance-judge/` folder is labelled `judge_doc` and gets its own multiplier.
2. **The multiplier moved out of the filing cabinet and into the settings file.** It used to be
   stamped onto every row when the document was indexed — so changing it meant re-indexing
   everything (hours). Now it's looked up from `config.json` at the moment you search. The old
   stamped column is deleted by a one-way, version-stamped database upgrade that takes a file
   copy first, so you can restore in seconds if it goes wrong.
3. **The new multiplier's value (1.2) was measured, not guessed.** A sweep ran the five R9
   measurement queries at 1.5, 1.4, 1.3, 1.2, 1.1 and 1.0 against a *copy* of the live index and
   adopted the best-scoring value closest to the old behaviour.

Analogy: the library used to write the shelf-priority in pen on every book's spine. Now it's a
single line in the librarian's rulebook, checked when you ask a question — and judge verdicts
got their own shelf.

## Does it do what was wanted?

Mostly yes, and it says so honestly where it doesn't.

- All three ADR 0030 changes are present and tested. I re-ran the suite myself:
  `104 passed, 23 deselected in 0.61s`.
- **R9 still fails: 3 of 5 against a 5-of-5 bar.** The bar was *not* moved to make the change
  look successful, and the feature card states the failure flatly with the two failing query
  transcripts pasted in. That is the right call — the alternative (redrawing the bar after
  seeing the score) is the exact move this feature already retired once. Shipping a measured
  partial improvement with a red requirement left red is honest engineering, not a defect.
- The reasoning is genuinely sound, not lucky. Three defects in the implementation *plan* were
  reproduced before being fixed: a migration that could not roll back (Python `sqlite3` opens an
  implicit transaction for data changes only, never `ALTER TABLE`), a "same index state" proof
  that was unsatisfiable because searching itself writes a latency row and moves the file's
  mtime, and a weight test that could not fail because the scores tied and the sort was stable.

## What could go wrong / what I'm unsure about

**The big one — the change can silently do nothing after merge.** Two steps are needed:
`memsearch index` (upgrades the database) and `memsearch index --reclassify` (re-labels the
judge documents). Only the first happens automatically, via the 6-hourly scheduled job. An
ordinary index run skips unchanged files by content hash, so it re-labels almost nothing —
measured: **108 `judge_doc` chunks after a plain run, 3609 after the reclassify pass.** If step
two is forgotten, every test stays green, `memsearch status` reports a healthy index, and
roughly 97% of this change is inert with **no runtime signal at all**. The only guard is a
README section. There is no checklist item, no status warning, and no assertion. This is the
textbook shape of success masking: everything reports fine while the thing you built isn't on.

**A quiet window where search is down and the greeting says otherwise.** After merge the live
database is still at the old version until the scheduled job upgrades it — up to six hours.
During that window `memsearch query` refuses outright (with a clear, actionable message), but
the SessionStart line you see at every session start reads `status.json`, which only the
upgrading command writes — so it will go on cheerfully reporting "12270 chunks, fresh" while
every query fails. `memsearch status` does print `MIGRATION REQUIRED:`, but nobody runs that at
session start. The code comments acknowledge this exactly; the gap is structural (no writer
exists that could record "upgrade pending") rather than an oversight, and failure is loud at the
point of use. Still a real hole in the always-on surface.

**Two knowingly-wrong sentences left in an accepted ADR.** ADR 0030 still describes the
`with conn:` migration that was proven not to work, and still claims the 1.5 baseline equals
today's behaviour — which is false for 153 chunks in repo-root judge folders that were at 1.2,
not 1.5. Both are corrected in the feature card, and the card says so explicitly. But the ADR
carries no forward pointer, so a reader who lands there first meets the wrong version and never
meets the correction. Trading a re-review round for a permanently misleading decision record is
the wrong side of that trade, even though the substance of the adoption is unaffected (a
counterfactual was run: zero repo-root `judge_doc` hits in any target's top-6 at either weight).

**The upgrade is one-way.** The rollback is a single `.pre-v0.bak` file copy — and
`_take_backup` deliberately deletes older copies. That's correct hygiene, but it means one
copy, one chance. The 82 MB live index is the real thing, not a test fixture.

## What I'd double-check before merging

1. **Turn the post-merge reclassify into something you cannot miss.** A README heading is not a
   guard. At minimum add it as a tracked checklist item on the feature card; better, have
   `status` flag a suspiciously low `judge_doc` count, or have the scheduled job's log say
   whether the pass has ever run. Right now the failure mode is invisible.
2. **Immediately after merge, run both commands in order and read the output** — then confirm
   `memsearch status`'s `by source_type` line shows `judge_doc` in the thousands, not ~108.
   That single number is the whole difference between this change working and not.
3. **Add one forward-pointing line to ADR 0030** naming the feature card as the corrected
   record for the migration mechanism and the 1.5 baseline. One sentence, no re-review of the
   decision itself.
4. **Confirm the `.pre-v0.bak` copy exists and is 82 MB before you touch anything else** — it
   is the only route back from the one-way upgrade.
5. Sanity-check the accepted exposure: *any* folder named `observability-judge/` or
   `compliance-judge/` in a configured repo root now gets the judge tier. It's pinned by a test
   as deliberate; just make sure that's still what you want in the two configured repos.

## Dimension scores

| Dimension | Score | Note |
|---|---|---|
| `intent` | pass | All three ADR 0030 changes present; R9 measured, bar untouched and reported red. |
| `execution` | pass | Suite re-run by me: `104 passed, 23 deselected`. New tests discriminate (fail-injection rollback; 3× ratio at `abs=2e-6`). |
| `trajectory` | pass | Three plan defects reproduced before being fixed; adoption follows the stated protocol with each rejection naming its clause; counterfactual run for the 153-chunk inflation. |
| `regression` | concern | One-way migration on an 82 MB live index; up to 6 h where `query` refuses and the SessionStart nudge cannot say so. Loud at point of use, silent on the always-on surface. |
| `context_budget` | pass | No `rules/`, `CLAUDE.md` or skill changes. The 1873-line ledger sits under `.superpowers/`, outside `curated_docs`/`repo_roots`, so it is neither always-on nor indexed. |
| `traceability` | concern | ADR 0030 knowingly retains two stale statements corrected only in the feature card, with no forward pointer from the ADR. |
| `success_masking` | concern | Forgetting `index --reclassify` leaves ~97% of the change inert (108 vs 3609 chunks) with green tests, green status and no runtime signal. README-only guard. |
| `intent_drift` | pass | No dependency changes (`pyproject.toml`/`uv.lock` untouched); diff confined to `memsearch/` and its own docs. |
| `checkpoint` | pass | 20 focused commits; file-copy backup taken before the drop; live index verified byte-identical (sha256 + size recorded before and after). |
| `audit_trail` | pass | ADR + card + ledger, attributable commits; both parked minors closed in `ee81648`; the card's own `grep -c 'ADR 0021' == 2` invariant verified holding. |

## Concerns

- `index --reclassify` is manual and unenforced; skipping it leaves ~97% of the change inert with no runtime signal (108 vs 3609 judge_doc chunks)
- No post-merge reclassify task on the feature card checklist — the only guard is a README section
- Up to a 6 h post-merge window where `memsearch query` refuses while the SessionStart nudge still reports the index healthy
- ADR 0030 retains two knowingly-stale statements (the `with conn:` migration; the 1.5-baseline claim) with no forward pointer to the card's corrections
- Schema migration is one-way; rollback is a single `.pre-v0.bak` copy that later migrations delete
- Judge tier keys on any `observability-judge`/`compliance-judge` directory name in a configured repo root (pinned as deliberate, but a live exposure)
- R9 remains red at 3 of 5 against a 5-of-5 bar — correctly reported, not a defect, but the feature does not close
