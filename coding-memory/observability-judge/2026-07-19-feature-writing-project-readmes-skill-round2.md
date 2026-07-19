# Observability Judge Verdict — feature/writing-project-readmes-skill (implementation, round 2)

- **Repo:** .claude
- **Branch:** feature/writing-project-readmes-skill
- **HEAD:** 0d23feb174acb3b1343a5637a83b6fc0fde97390
- **Stage:** implementation
- **Timestamp:** 2026-07-19T06:10:56Z
- **Prior verdict:** round 1 @ 3c5a826 (risk=low conf=medium) —
  see `2026-07-19-feature-writing-project-readmes-skill.md`

## What was changed

One new commit (`0d23feb`, 3 files, +32/−21) on top of the round-1 branch. It fixes the single
actionable finding round 1 raised: the skill's own "did you leave any template text behind?" check
had a blind spot. Think of it like a metal detector that only beeped on coins but not on rings —
the fix re-labels every valuable so it always beeps. Every placeholder in the README template now
carries a `[TODO: …]` marker (the `OWNER/REPO` placeholders were already greppable and stay as-is),
and the skill's verify step is simplified to a single pattern: `grep -nE 'OWNER/REPO|\[TODO:'
README.md` must come back empty. The template's HTML comment and the branch log were updated to
explain why the marker must never be restyled. Nothing else in the branch changed.

## Does it do what you wanted?

Yes — the round-2 delta does exactly the one thing it set out to do, and I re-verified it myself
this round rather than taking it on the record:

- I ran the new grep against the raw template: **25 hits**, and critically all three multi-line
  guidance blocks (About, Built With, Roadmap) now have a `[TODO:` on their *opening* line, so a
  whole leftover block is caught by its first line.
- I simulated the false-positive cases the summary claims are safe: a real markdown link
  `[Explore](https://x.com)` and task-list checkboxes `- [x] Done` / `- [ ] Upcoming` produce
  **zero** matches; only a genuine `[TODO: …]` leftover matches. Confirmed — no false positives
  from links or checkboxes.
- The round-1 finding is resolved at the root (greppable *by construction*) rather than by
  chasing prose patterns in the grep — the better of the two fixes, because it can't drift out of
  sync with the template's wording later.

The original three user asks (template-based README creation, automatic scaffolding for new
projects, Roadmap upkeep on feature landing) were delivered in round 1 and are unchanged here.

## What could go wrong / what I'm unsure about

- **One narrow evasion remains, and it's honestly disclosed.** The multi-line `[TODO: …]` blocks
  put the marker only on their opening line; their continuation/closing lines (e.g. template lines
  52, 57, 119, each ending in `]`) carry no marker. So if someone deleted *only* the opening line
  of a multi-line block and kept its tail, the grep would miss the orphaned tail. This is a real
  hole, but it requires an unnatural partial edit — nobody leaves template prose behind that way —
  and the primary instruction ("fill every placeholder with real facts") is the actual safety net.
  Documented in the decisions summary as an accepted limit; I agree it's not worth complicating the
  design to close.
- **Behavioral evidence is still second-hand — unchanged from round 1.** The RED/GREEN subagent
  runs and 8/8 routing checks live as prose in the branch log; the fixture was a session
  scratchpad and no test log was committed, so I can't re-run them. This delta doesn't touch that,
  and the *round-2* change is fully deterministic-grep-checkable — which I did check first-hand —
  so it doesn't lower my confidence in this specific verdict.
- **The verdict store is uncommitted in the working tree.** `verdicts.jsonl` shows modified and the
  round-1 markdown is untracked (`??`); my round-2 files add to that. Per house convention the
  observability store is committed separately, so these will ride with the next docs commit or the
  PR — flagging so they aren't lost. They are not part of the branch diff under review.
- **Pre-existing `settings.json` mod persists** in the working tree — disclosed, unrelated to this
  branch, and structurally cannot enter the PR.

## What I'd double-check before merging

1. Nothing blocking. The round-1 finding is closed; the residual continuation-line gap is an
   accepted, documented limit, not a follow-up item.
2. Make sure the observability-store files (round-1 + round-2 markdown, `verdicts.jsonl`) get
   committed so the audit trail lands with the PR, and that the unrelated `settings.json` change
   does not ride along.
3. The behavioral RED/GREEN/routing claims remain the one thing I can't independently replay — if
   you want full first-hand coverage some day, committing a tiny fixture + check would close it,
   but it's not a merge blocker for a skill-only change.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Delta precisely closes the round-1 finding; no scope beyond it |
| execution | pass | I re-ran the new grep: 25 template hits, 0 false positives on links/checkboxes |
| trajectory | pass | Root-cause fix (greppable by construction) over pattern-chasing; residual limit disclosed |
| regression | pass | 3 files, additive markers + one grep line + branch log; template structure preserved |
| context_budget | pass | No always-on additions this round; skill/template stay on-demand |
| traceability | pass | Commit message + branch log record finding → fix → re-verify evidence |
| success_masking | pass | Primary masking path (skill check passing with obvious leftover prose) now closed; only an implausible partial-edit evasion remains, disclosed |
| intent_drift | pass | Exactly the finding-fix plus its required documentation; no drive-bys |
| checkpoint | pass | Single clean revertible commit on the feature branch |
| audit_trail | pass | Exemplary — round-1 finding and its fix both recorded with deterministic evidence |

## Concerns

1. Multi-line `[TODO: …]` blocks mark only the opening line; a continuation/closing line left
   orphaned by deleting just the block opener would evade the verify grep — real but requires an
   unnatural partial edit, disclosed and accepted as a design limit.
2. Behavioral RED/GREEN and 8/8 routing evidence remains subagent-reported prose (fixture was
   session-scratchpad, no test log committed) — unchanged from round 1 and not touched by this
   delta; the round-2 change itself is deterministically verified first-hand.
3. Observability store is uncommitted (`verdicts.jsonl` modified, round-1 markdown untracked) —
   must be committed to land the audit trail with the PR.
4. Pre-existing uncommitted `settings.json` mod persists — disclosed, unrelated, cannot enter the
   PR.

**risk=low confidence=high**
