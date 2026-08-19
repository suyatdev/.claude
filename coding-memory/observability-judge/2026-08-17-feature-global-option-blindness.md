# Observability judge verdict — global-option-blindness (architecting, advisory)

- repo: `global-option-blindness`
- branch: `feature/global-option-blindness`
- head_sha: `4646a10041614377424305a768445e4a9fd3b5a5`
- stage: `architecting` (advisory — no source has been written; checklist 0/11, `phase: planning`)
- ts: `2026-08-17T19:53:25Z`
- doc judged: `docs/features/global-option-blindness.md`, revision 4.1 (unchanged text label; citations fixed)
- **This supersedes my prior verdict at this same path**, taken at `b9c5c9c` minutes earlier
  (`risk=medium confidence=high`, zero errors found). This round is a refresh, triggered because
  the compliance judge failed revision 4.1 on round 4 (`core-conduct/stale-line-citation`) after my
  prior read, and commit `4646a10` fixed it. I did not re-litigate anything my prior round already
  passed; I re-verified only the delta and re-checked whether it changes the three open concerns.

## What was changed

A ~26-line, three-hunk documentation fix, nothing else touched:

1. Two `git-guard.sh` citations that had gone stale — the design was written on a sibling worktree
   where they pointed at `:142`/`:152`; this branch was cut *after* a merge inserted ~140 lines
   above them, so the numbers silently landed inside an unrelated comment block. Corrected to
   `:280`/`:292`, with a new warning telling the reader to `grep -n` rather than trust the number,
   and an honest note recording exactly how and why the old numbers rotted.
2. Task 3 now names its target block by literal source text (`` the `if has_fact COMMIT && on_main;
   then` block ``) in addition to the line number — a citation that survives the next line-count
   drift, not just a corrected number.
3. The bucket-1 paragraph no longer claims its membership is "the union of the two Examples
   tables"; it now says the two tables cover everything except `--attr-source`, which has its own
   standalone scenarios instead.

## Does it do what you wanted?

Yes. I independently re-derived every changed citation against the real files rather than trusting
the commit message:

- `hooks/git-guard.sh:280` is `if has_fact PUSH_FORCE; then` and `:292` is `if has_fact COMMIT &&
  on_main; then` — both match exactly (`wc -l` confirms the file is 339 lines now, consistent with
  the ~140-line insertion the spec describes).
- `hooks/lib/classify-git-command.py:150/152/169` (`subcommand, rest = argv[1], argv[2:]`; the
  `commit`/`push` gates) still match exactly, as the spec claims.
- The bucket-1 recount holds arithmetically: the no-value list is 16 options minus `--bare` (15),
  plus `--exec-path`, `--attr-source`, `--list-cmds` = 18 members. The harmless Examples table
  carries exactly its 8; the print-and-exit Examples table carries its 7 plus `--exec-path` plus
  `--list-cmds` (both spellings) = 9 distinct options; `--attr-source` is the 18th, standalone. The
  corrected sentence is true; the sentence it replaced was not.

This is a surgical fix — exactly the one blocking violation plus the one non-blocking note the
compliance judge raised, nothing more. No drive-by edits, no scope creep into unrelated sections.

## What could go wrong / what I'm unsure about

Two questions were asked of this refresh specifically:

**Does the fix change my risk assessment or the three open concerns?** No. The delta does not touch
task 9 (the manual `ask`-really-prompts check), task 0c (whether the test suites run automatically
at all), the unverified stderr-surfacing question, or the "no log file" audit_trail trade-off. All
three concerns from the prior round (`execution`, `success_masking`, `audit_trail`) stand exactly as
recorded. Risk stays `medium`.

**Is "re-derive, don't trust the number" sufficient for a spec whose citations have now rotted once
mid-flight, or does something need to fail loudly on a stale citation?** I judge it sufficient at
this stage, for three reasons, not zero reasons:

- Something already *did* fail loudly here — the compliance judge is the fail-loud mechanism, and
  it caught this exact defect (round 4) before merge. This episode is evidence the safety net works,
  not evidence one is missing.
- Task 3's fix is stronger than a corrected number: pairing the citation with the literal source
  text (`` the `if has_fact COMMIT && on_main; then` block ``) means a *future* line-count drift
  degrades the reference to "still findable by search," not to "silently wrong," the way a bare
  number does. That is the right fix for the failure mode that actually occurred.
- Building an automated citation-checker for markdown specs (verifying every `file:line` reference
  against the real file at commit time) would be new tooling with no precedent anywhere else in this
  repo's hook set, and would itself be scope creep for a feature about bash guard blindness — a
  second problem grafted onto this one.

The residual risk is real but small: the mitigation is still a *process* instruction ("re-run
`grep -n`"), not a hard gate — the same category of residual risk task 9 already carries as a
named, accepted limit. If this branch rebases again before task 3 executes, a third drift is
possible, though now it would land as "the named block moved," which a text search still finds,
rather than "the block silently became something else." I would not block on this; I would name it
as a pattern worth a one-line ADR note (a citation that carries its own anchor text is more durable
than one that carries only a number) if this pattern recurs on a future card.

## What I'd double-check before merging (i.e., before task 11 / PR)

Unchanged from the prior round, since nothing in this delta touched them:

- When task 3 runs, record the stderr-surfacing answer plainly, and if it comes back "swallowed,"
  revisit whether bucket 2's `ask` framing needs a caveat about what the user actually has to rely on.
- When task 0c runs, if the answer is "nothing runs these automatically," treat that as a follow-up
  worth its own line in ADR 0029.
- Task 9's fallback path (drop to `deny`, revisit bucket 2) is written but never rehearsed.
- New this round: when task 3 actually greps `git-guard.sh`, confirm the block still reads `if
  has_fact COMMIT && on_main; then` verbatim — if a further merge changed that literal text (not
  just its line number) between now and implementation, the anchor itself needs re-deriving, not
  just the number beside it.

## Dimension table

| dimension | verdict | why |
|---|---|---|
| intent | pass | Same design throughout; the fix addresses exactly the compliance judge's finding plus its one non-blocking note, nothing else. |
| execution | concern | Unchanged from the prior round — task 9 (manual prompt check) and task 0c (do the suites run automatically) are both still open at judgment time; this delta doesn't touch either. |
| trajectory | pass | A fourth self-correction cycle handled the same way as the prior three: the root cause is named plainly in the commit message and in the spec itself, and the fix upgrades the citation (adds a literal-text anchor) rather than just patching the number. |
| regression | pass | Unchanged; the delta doesn't touch any task, scenario, or contract section. |
| context_budget | pass | Unchanged; lives in `docs/features/*`, loaded on demand. |
| traceability | pass | I independently re-verified both corrected `git-guard.sh` citations (`:280`, `:292`) and the three `classify-git-command.py` citations against the real files — all match exactly. The bucket-1 recount was independently re-derived arithmetically and holds. |
| success_masking | concern | Unchanged — task 9's manual step and task 0c's open question remain the two ways a green plan could still hide a real gap. |
| intent_drift | pass | The fix is scoped to exactly the violation and the one advisory note; no drive-by edits elsewhere in the document. |
| checkpoint | pass | Unchanged; per-hook independent rollback story untouched by this delta. |
| audit_trail | concern | Unchanged — the "no log file" trade-off is still a stated limit, not a closed gap. The citation-drift episode itself is a small positive counter-example (the commit message states exactly what was wrong, on which branch, and why, before recording the fix), but it doesn't resolve the underlying `SCOPE_UNKNOWN`-frequency gap. |

## Concerns

- Unchanged from the prior round: stderr-surfacing on an exit-0 hook is unverified and deferred to
  task 3; task 9 is a blocking but irreducibly manual, one-time permission-prompt check; task 0c (do
  the suites run automatically) is an open question at judgment time; `audit_trail`'s "no log file"
  decision remains a stated, ADR-bound trade-off rather than a closed gap.
- New, non-blocking: the citation-drift mitigation (re-derive, plus a literal-text anchor) is a
  process safeguard, not a hard gate. It is proportionate for this feature's scope, but if the same
  file moves again before task 3 executes, only the number would auto-invalidate itself via the
  `grep -n` instruction — the anchor text still needs a human to notice if it, too, changed.
- Positive, not a concern, worth repeating: this round is direct evidence the compliance-judge gate
  functions as the "fail loudly on a stale citation" mechanism the refresh prompt asked about — it
  caught the defect before merge, and the fix was root-caused rather than patched blind.

## Risk / confidence

risk=medium confidence=high
