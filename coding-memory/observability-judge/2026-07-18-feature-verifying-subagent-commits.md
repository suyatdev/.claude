# Observability Judge Verdict — feature/verifying-subagent-commits (implementation)

- **Repo:** .claude
- **Branch:** feature/verifying-subagent-commits
- **HEAD:** 367da777d3711fc5a9e44c20b63262888da878b4
- **Stage:** implementation
- **Timestamp:** 2026-07-18T17:35:06Z

**Note:** this is a re-run at a new HEAD. A prior verdict on this same branch (HEAD
`8701ca8...`, same timestamp date) raised five concerns. Two follow-up commits landed since; this
run verifies those two directly rather than re-describing the whole branch. The underlying change
itself — a new prose skill (`skills/verifying-subagent-commits/SKILL.md`) plus one `CLAUDE.md`
catalog line plus one `rules/gates.md` stub, written up from a real repeated failure trace (a
dispatched subagent committing to the wrong git checkout three times in one session despite an
explicit self-check instruction) — is unchanged from the prior run.

## What was changed

Since the last check, two small follow-up commits were made, each responding to one thing the last
review flagged:

1. `8701ca8` added a sentence to the skill's trigger description saying what it's *not* for
   (judging whether a commit's contents are good — that's a different skill's job), matching this
   repo's house rule that a skill description should state both when to use it and when not to.
2. `367da77` trimmed that same description from ~488 characters down to ~348, because 488 was
   nearly 2.5x this repo's own "~200 char" guideline for skill descriptions — on the very commit
   meant to bring it into line with that guideline.

Nothing else changed. No other files were touched in either follow-up commit.

## Does it do what you wanted?

Yes, verified directly rather than taken on the summary's word:

- **Description length, fixed and now typical, not just "less bad."** Counted the live frontmatter
  string: 348 characters (the task said "~344," close enough — one word choice off). More
  importantly, I measured every other skill's actual description length in this repo (15 skills,
  range 275–414 chars) and 348 sits almost exactly in the middle of that real distribution — it's
  the same length as `managing-session-memory`'s description, word-for-word tied. The repo's
  written guideline says "near 200," but no actual skill in the repo hits that; 348 isn't an
  outlier relative to how this repo's skills actually get written, it's the norm. Both trigger
  halves survived the trim and read clearly: the positive clause ("Use when a dispatched
  implementer/fix subagent reports DONE with a commit SHA, before trusting that report or
  dispatching a reviewer — subagents told to self-check their worktree have still committed to the
  wrong checkout") and the negative/boundary clause ("Not for judging whether the commit's contents
  are correct (see /code-review) — only whether it landed in the right place"). Nothing was cut
  that changes what the skill does or doesn't cover.
- **The no-ADR decision holds up against the actual repo history, not just the stated rationale.**
  I checked out the closer precedent named in the rationale: `feature/diagramming-skill` (merged as
  PR #12, commit `1864a02`) shipped a new skill + `CLAUDE.md` catalog line + no hook wiring, and I
  confirmed via `git log` that it has no companion ADR commit anywhere in its history. ADR-0001
  (`docs/decisions/0001-observability-judge.md`), by contrast, covers a change that added a new
  hook (`judge-guard.sh`) that mechanically blocks `gh pr create` — a materially different, more
  consequential kind of change than a prose-only checkpoint. This skill's own body already states
  plainly that it is *not* hook-enforced ("no generic script can know which checkout is correct for
  a given dispatch"). Given that, treating it like the diagramming-skill precedent rather than the
  observability-judge precedent is the right call, and the "why" is already recorded in the skill's
  own text and the `rules/gates.md` stub — an ADR would mostly duplicate that.
- Diff since the prior run's HEAD is exactly the two single-line description edits described above
  — confirmed via `git diff`. No other files touched, no scope creep.

## What could go wrong / what I'm unsure about

- **`CODING_MEMORY.md` still hasn't caught up.** As of this HEAD, it still says this branch "exists
  locally (not pushed, no PR)" — it doesn't reflect either follow-up commit or the fact that the
  branch is now further along toward a PR. The plan is to fix this in the very next commit, before
  opening the PR, which is reasonable — but at this exact commit, the audit trail genuinely has a
  gap between what happened and what's recorded. Not a defect in the diff under review, but real
  and unresolved *right now*.
- **The pressure-test efficacy claim is still unverified this session.** No artifact exists in this
  repo to check, and re-running a full pressure test is out of scope for this housekeeping pass.
  This is a disclosed, known limitation, not a hidden one. Given the change is a prose-only
  checkpoint (no code path it can silently break, no hook it can bypass) and risk is already low,
  this doesn't need to block a merge — but it also means the skill's core efficacy claim remains an
  assertion carried forward from a session that no longer exists to re-check, indefinitely, until
  someone actually reruns it.
- **Still no mechanical enforcement.** The skill itself says as much: this depends on the
  controller remembering to run the check, the same class of failure that caused the original bug.
  This is the same shape of limitation as several other gates in `rules/gates.md` (e.g. the
  model-switch gate, the new-instruction gate) that are also judgment-only rather than hook-backed
  — so it's not a new or unusual risk for this repo, just an inherent one for this kind of gate.
- **Every new gate stub is a permanent, always-loaded cost.** The `rules/gates.md` addition is 476
  characters — proportionate to its siblings (the file's stubs range roughly 255–626 chars), not
  bloated relative to precedent, but it is still a small tax paid on every single session from now
  on, forever, since this file loads unconditionally via `CLAUDE.md`.
- No automated test suite exists for skill content in this repo — disclosed, consistent with the
  authoring standard's stated current state, not a hidden gap.

## What I'd double-check before merging

- Confirm the next commit actually updates `CODING_MEMORY.md` / branch tracking before the PR is
  opened, as planned — don't let it slip past this housekeeping pass.
- At some point, actually rerun (or at least fully re-read) the pressure-test scenario rather than
  carrying the claim forward unverified indefinitely — not a merge blocker here, but worth doing
  before leaning on this skill in a high-stakes multi-agent run.
- Nothing further needed on description length or the ADR question — both were checked against
  hard evidence (the repo's real description-length distribution; the diagramming-skill precedent's
  actual git history) this run, not just re-asserted.

## Dimension Table

| Dimension | Verdict |
|---|---|
| intent | pass |
| execution | pass |
| trajectory | pass |
| regression | pass |
| context_budget | concern |
| traceability | pass |
| success_masking | pass |
| intent_drift | pass |
| checkpoint | pass |
| audit_trail | concern |

## Concerns

- CODING_MEMORY.md still does not reflect this branch's current state at this HEAD (two follow-up commits, further along toward a PR) — planned as the immediate next commit, not yet done.
- The skill's core efficacy claim (pressure-tested, still caught a bad commit) remains a secondhand assertion from a prior session, not re-verified this session or by this judge, and no artifact exists in-repo to check it against.
- No mechanical enforcement exists for this checkpoint (controller-memory-dependent), matching the same structural limitation already accepted for other judgment-only gates in this repo (model-switch, new-instruction) rather than a defect unique to this change.
- Every new `rules/gates.md` stub is a permanent addition to always-loaded context; this one (476 chars) is proportionate to its siblings but is a recurring, non-zero cost paid every session going forward.
- No automated test suite exists for skill content in this repo (disclosed, consistent with the repo's stated current state).

## Resolved since prior verdict (verified this run, not just re-asserted)

- Description length: trimmed 488 → 348 chars, confirmed via direct character count; measured against all 15 other skills' actual descriptions in this repo (range 275–414) and found squarely typical, not an outlier. Both the positive trigger and the "not for X" boundary clause survived the trim intact and read clearly.
- No ADR: confirmed via `git log` that the closer precedent (`feature/diagramming-skill`, PR #12, commit `1864a02` — new skill + catalog line, no hook) shipped with no ADR. ADR-0001 covers a materially different, hook-enforced change. The decision not to write an ADR here holds up against the actual repo history, not just the stated rationale.

## Risk / Confidence

- **risk:** low
- **confidence:** high
