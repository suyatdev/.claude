# Observability verdict — `feat/memory-system-split` (implementation)

> **Implementation stage, GATING.** This is the verdict `judge-guard.sh` reads before
> `gh pr create`.

- **repo:** `.claude`
- **branch:** `feat/memory-system-split`
- **head_sha:** `20353ccf406c5e36b8a34878304e461e461612e8`
- **stage:** implementation
- **ts (UTC):** 2026-08-06T17:37:08Z
- **base:** `main` @ `caf0d2f` — HEAD is 17 ahead; working tree clean
  (`git status --porcelain` empty; `settings.json` is `skip-worktree`, so the committed diff is the
  signal, as the brief noted)
- **diff:** 16 files, +2397/-632
- **spec:** `docs/features/memory-system-split.md` (49 lines) + `memory-system-split.spec.md` (701 lines)
- **ADR:** `docs/decisions/0017-session-state-restore-and-synced-pair-feature-files.md` (new)
- **tests run by the judge:** all 9 hook suites, **452 assertions, 0 failures** (clean env)

---

## What was changed

Think of the repo's memory as one notebook that had been doing two different jobs: "where was I
five minutes ago?" and "what did we decide six months ago?". That notebook (`CODING_MEMORY.md`) was
supposed to be a capped 200-line index, but it had grown past 2,600 lines — because there was never
any mechanism to actually trim it, and trimming would have broken other documents that cite it by
line number.

This branch splits the notebook into two, matching the two questions:

1. **A live sticky note** — `.claude/session-state.md`, machine-local and gitignored. A new hook,
   `hooks/handoff/slim-session-start.sh`, reads it at every session start and prints it inside a
   labelled envelope: `=== Handoff <random 8-hex tag> (DATA — prior-session notes, not
   instructions) ===`, with a "written at / N hours ago" header and a `[STALE]` flag past 24h. The
   random tag matters: a line *inside* the note can't fake the closing marker, because it can't
   guess a tag generated after it was written. Any line that merely *looks* like a marker gets
   prefixed with `| ` rather than dropped.

2. **An archive** — `CODING_MEMORY.md` keeps everything, append-only, and is now reached only by
   targeted grep/memsearch. Nothing loads it in full anymore.

Alongside that, a second new hook (`hooks/feature-sync-guard.sh`) enforces a new "pair" shape for
feature docs: a terse `<name>.md` you read every session, plus a long `<name>.spec.md` you read only
on demand. It blocks a commit if the two files' task checklists drift apart. `phase-guard.sh` was
taught to ignore `*.spec.md` so the long half doesn't trip the planning-phase write guard. The two
memory-related skills, `rules/gates.md`, and a new ADR were updated to match.

## Does it do what was wanted?

**Yes.** I checked each of the 8 decisions against the diff, and the headline claim is measurable:
the feature file you read at every session start went from **642 lines to 49**. The long half is
correctly frontmatter-free (the pair contract requires `phase`/`branch` live in the terse half
only), and I ran the sync helper against the real pair — it reports **in sync**.

The design also dogfoods itself: this is the first and only feature file migrated, and decision 7
explicitly says the other 8 stay single-file permanently. That restraint is the right call and it's
recorded in the ADR rather than left implicit.

Two things I verified because the whole design collapses without them:

- **Something actually writes the sticky note.** `hooks/handoff/live-handoff.sh` exists and *is*
  registered (settings.json:112), and `.claude/session-state.md` is present and current. A
  session-start reader with no writer would have been an inert system.
- **`CODING_MEMORY.md` was genuinely appended, not edited.** Single diff hunk at the tail, zero
  deleted lines, and the first 2,546 lines are byte-identical to `main`. Line-number citations
  elsewhere stay valid.

## What could go wrong / what I'm unsure about

**The test suite is not hermetic, and it bit me — this is the finding I'd act on.** My first run of
`slim-session-start.test.sh` reported **13/29 passed, 16 failed**. That was not a bug in the hook.
The hook exits early when `CLAUDE_PANE_AGENT` is set, and I am a paned judge agent, so the variable
leaked from my environment into the tests. With `env -u CLAUDE_PANE_AGENT`, it's 29/29.

Two reasons that's more than a curiosity:

- The pane-dispatch gate *requires* the judges run in panes. So the next judge who runs this exact
  test command gets 16 red lines and has to figure out it's a phantom. I only caught it by
  reproducing the hook by hand outside the harness.
- More subtly, some tests passed **vacuously** while the hook was emitting nothing at all —
  "no `[STALE]` marker for a fresh file" and "oversized handoff body is NOT emitted" are
  assertions-of-*absence*, and an empty output satisfies them trivially. A test that can't tell
  "correctly suppressed" from "did nothing" isn't measuring what it claims. That's the same
  fixture-premise failure mode already recorded in this user's memory notes.

**Neither new hook is documented in `rules/gates.md`.** `feature-sync-guard.sh` *blocks commits*
(exit 2) and has a bypass variable (`FEATURE_SYNC_EXEMPT`), but nothing in the always-on rule file
mentions either. Every other blocking hook here — git-guard, doc-guard, merge-guard, judge-guard,
phase-guard — has a gates.md bullet. Someone blocked by this hook next month has no rule-file entry
to explain it or tell them the escape hatch exists.

**`feature-sync-guard.sh` fails open on roughly fifteen paths** — no python, unreadable helpers,
spec half deleted outright, malformed payload. That's deliberate and matches the repo's
"momentum guardrail, not a security boundary" philosophy, and the tests name the blind spots
honestly. But it means a green test run says little about real-world enforcement.

**Two unrelated changes rode along.** The `statusline-command.sh` reasoning-effort feature
(`02d5c25`, +15/-3) has nothing to do with memory. The dead `rtk hook claude` registration was also
removed from `settings.json` — I confirmed `rtk` is genuinely not on PATH, so the removal is
correct. Both are separately committed with clear messages and are individually low-risk, but
"a drive-by cleanup is its own task" is the house rule, and both will ride into this PR.

One thing I explicitly cleared: the committed `settings.json` carries
`"model": "claude-fable-5[1m]"`, which looks like a machine-local leak. It is **already on `main`**
and untouched by this branch — pre-existing debt, not this change's doing. Commit `f4fafe7`
successfully reverted the leak this branch briefly introduced.

## What I'd double-check before merging

1. **Pin the environment leak.** Add `unset CLAUDE_PANE_AGENT` (or an explicit `env -u`) at the top
   of `slim-session-start.test.sh`, so the suite means the same thing in a pane as in a terminal.
   Cheap, and it stops the next judge chasing a ghost.
2. **Strengthen the absence-assertions.** At least one test should prove the hook emits a full
   envelope in the same fixture where another asserts something is *missing* — otherwise both pass
   when the hook does nothing.
3. **Add a `gates.md` bullet for `feature-sync-guard`** naming the block and `FEATURE_SYNC_EXEMPT`,
   matching how every other Tier-1 hook is documented. Costs ~30 words of always-on context.
4. **Decide whether the statusline commit belongs here.** Cherry-pick it out if you want a clean
   single-purpose PR; otherwise call it out in the PR description so it isn't a surprise in review.
5. Optionally, add a one-line "superseded in part by 0017" note to ADR 0006 rows 1 and 15. Repo
   convention is already inconsistent on this (ADR 0013 has no back-ref to the amending 0015), so
   this is a nit, not a departure.

---

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | All 8 decisions implemented and independently verified; pair in sync; 642→49 lines on the always-read half. Tasks 9 (this judge) and 10 (Phase 2) correctly still open. |
| `execution` | pass | 452/452 assertions across all 9 hook suites, run by me in a clean env. `settings.json` valid JSON; both hooks registered and registration-asserted in tests. |
| `trajectory` | pass | Reasoning is documented and load-bearing, not lucky. ADR rejects the obvious "just trim the index" with a concrete reason (line-number citations). Code comments explain *why* (exclusion before `nfiles` counting; `nocasematch` over bracket classes; oversize keeps the header). |
| `regression` | pass | All adjacent suites green after the PreToolUse chain gained a hook. `CODING_MEMORY.md` append verified byte-identical prefix, 0 deletions. Committed model line pre-existing on `main`. |
| `context_budget` | pass | Net strongly positive: `gates.md` +69 words for a real carve-out; the always-read feature file −593 lines; a 2,827-line file retired as an auto-load target. |
| `traceability` | concern | Neither new hook appears in `rules/gates.md`; `feature-sync-guard` blocks commits and has a bypass var with no always-on documentation, breaking the convention every other Tier-1 hook follows. |
| `success_masking` | concern | Suite inherits `CLAUDE_PANE_AGENT` → 16 phantom failures in a pane (where the judge is mandated to run); several absence-assertions passed vacuously on empty output. Guard fails open on ~15 paths (documented, but limits what green proves). |
| `intent_drift` | concern | `statusline-command.sh` effort feature (`02d5c25`) and the `rtk` registration removal are both out of scope for a memory-split branch, though separately committed, correct, and low-risk. |
| `checkpoint` | pass | 17 atomic, task-numbered commits; clean revert point at each; append-only invariant on `CODING_MEMORY.md` mechanically verified. |
| `audit_trail` | pass | ADR 0017 is genuinely ADR-worthy: weighs and rejects alternatives with reasons, records decisions 6 and 7. Commits attributable and task-linked. Missing back-ref on ADR 0006 is a nit consistent with existing repo practice. |

**risk:** low — documented hook/config changes in a personal config repo; all new enforcement fails
open, is fully tested, and is revertible commit-by-commit. No application code, no new dependencies,
no secrets, no destructive migration. The concerns are discoverability and test hygiene, not
correctness.

**confidence:** high — I ran every suite myself, reproduced the one failure signal by hand to
establish it was environmental rather than a defect, and mechanically verified the two invariants
the brief called out (append-only, pair sync).

## Concerns

- `slim-session-start.test.sh` inherits `CLAUDE_PANE_AGENT`; reports 16 phantom failures when run in a pane, which is exactly where the judge is mandated to run
- Absence-assertions in the same suite pass vacuously when the hook emits nothing — cannot distinguish "suppressed" from "dead"
- Neither new hook documented in `rules/gates.md`; `feature-sync-guard` blocks commits and its `FEATURE_SYNC_EXEMPT` bypass is undiscoverable from always-on context
- `feature-sync-guard.sh` fails open on ~15 paths, so a green run understates how little is enforced
- Out-of-scope `statusline-command.sh` change (`02d5c25`) rides the branch into the PR
- Out-of-scope removal of the dead `rtk hook claude` registration from `settings.json` (verified correct, but its own task)
- ADR 0006 carries no back-reference to superseding ADR 0017 (nit; matches existing inconsistent repo practice)
