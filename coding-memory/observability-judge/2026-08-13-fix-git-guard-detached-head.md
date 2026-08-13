# Observability verdict — git-guard trusts symbolic-ref, not abbrev-ref (implementation)

- **ts:** 2026-08-13T03:55:15Z
- **repo:** memsearch-freshness
- **branch:** `fix/git-guard-detached-head`
- **head_sha:** a4781860ee9daa52899a3ea2c59906e7ce3652a7
- **stage:** implementation (gates the PR)
- **base:** main (merge-base `1c48eedc5049138ffc7eff4473c94e4af734480d`)
- **test command:** `bash hooks/git-guard.test.sh` — ran it myself: **108 passed, 0 failed** (matches the claimed count)
- **risk:** medium · **confidence:** high

## What was changed

`hooks/git-guard.sh` is the lock that stops source code from being committed straight to `main`, and
stops a force-push from landing on `main`. Both checks start by asking git one question: *which
branch am I standing on?* The old way of asking that question (`git rev-parse --abbrev-ref HEAD`)
answers with the literal word `HEAD` in three completely different situations — a genuinely detached
checkout, a brand-new repo with no commits yet, and (combined with a separate failure) not being in a
repo at all — and the lock read all three as "not main," so it stepped aside. That's a lock that opens
itself when it gets confused, which is exactly backwards, and it already happened once for real (two
commits reached `main` unjudged after a checkout that detaches HEAD).

The fix swaps in `git symbolic-ref --short HEAD`, which never says the ambiguous word `HEAD` — it
names the branch whenever one genuinely exists, and answers nothing only when there truly isn't one.
That one remaining "don't know" case is set to fail closed (block), with a single carefully bounded
exception: while git is mid-rebase/mid-cherry-pick/mid-merge and waiting for the operator to finish it
(because the escape hatch, `git switch -c`, is something git itself refuses to run in that state) —
except a rebase that will land on `main`/`master` when it finishes, which stays guarded. Each of those
three boundary conditions is backed by a test row that was proven by *breaking* the code on purpose and
watching the right test go red, not just by reading the logic. The refusal messages were also rewritten
to say what the guard actually saw, instead of one vague sentence for three different situations. All
of it is written up in a spec, a decision record (ADR 0026), and a checklist with real command output,
not just prose claims.

## Does it do what you wanted?

Yes. I read the diff, the ADR, and the spec's measurement/test-matrix sections, and ran the test suite
myself rather than trusting the reported number — it came back 108/0, matching the summary exactly. The
design also visibly responded to the architecting-stage judge's findings from three days ago (this repo
already had a verdict on file: `coding-memory/observability-judge/2026-08-10-HEAD.md`, risk=medium) —
the unborn-`HEAD` hole that judge found is now closed by `symbolic-ref`, the refusal messages now name
the observed checkout, and the carve-out's three edge cases are each pinned by a mutation-tested row.
The one gap the ADR itself calls out — `merge`/`cherry-pick`/`revert`/`am`/`rebase` never raising the
`COMMIT` fact the whole allowlist depends on — is pre-existing on `main` today, correctly scoped out of
this fix rather than silently left implicit, and recorded as a class in the ADR rather than patched
here (a `PreToolUse` hook can't yet know what those commands will contain).

## What could go wrong / what I'm unsure about

- **The spec-compliance gate on this work was exited without ever getting a passing verdict.** Six
  rounds ran; the last was a **fail** (round 6), and the spec has been edited again since — that latest
  revision was never re-judged. This is disclosed plainly in the feature file's own "Gate record"
  section (an explicit, dated user decision, not something hidden), but it means three compliance
  findings are still formally open (`core-conduct/verification-before-write-down`,
  `writing-specs/api-contracts`, `writing-specs/unambiguous-requirements`). The code itself is heavily
  self-verified by mutation testing, which is why I'm not calling this a blocking defect — but it's a
  real, disclosed gap in the paper trail, not a clean pass.
- **The working tree wasn't clean at the moment I judged it.** `docs/features/git-guard-detached-head.md`
  has an uncommitted frontmatter edit (`phase: implementation` → `phase: review`) sitting on top of
  `head_sha` a478186. It's metadata-only, not code, so it doesn't change what I evaluated — but it
  should be committed before opening the PR so the checked-out state matches what gets reviewed.
- **The carve-out knowingly widens an existing gap, on purpose.** A hand-typed commit made mid
  cherry-pick/revert/merge-conflict on a detached HEAD is now also unguarded by this change, stacked on
  top of the pre-existing hole above. The ADR's reasoning (none of those three move a branch, so nothing
  committed there reaches `main` regardless) holds up, but it's a second accepted risk sitting next to
  the first one.
- **Three new scripts landed permanently under `hooks/`** (`measure-headname.sh`, `measure-matrix.sh`,
  `verify-carveout-hole.sh`) as the reproducible evidence behind the spec's tables — a deliberate
  checklist step, not scope creep, but `hooks/` otherwise holds only things Claude Code actually
  executes as hooks; worth a second look at whether that's the right permanent home.
- **One checklist box is still unchecked** — "cut the branch from fetched `origin/main`" — even though
  the branch obviously exists with 16 commits on it. Likely just bookkeeping that lagged reality, but
  worth a glance to confirm the branch point was sound.

## What I'd double-check before merging

1. Either get a fresh compliance-judge pass on the spec's current revision, or accept in writing that
   the three open ids ship unresolved — don't let the "gate exited" note quietly age into "gate passed."
2. Commit the pending `phase: review` frontmatter edit before opening the PR.
3. Skim the three new `hooks/measure-*.sh` scripts once for whether they belong in `hooks/` long-term or
   should move under something like `scripts/` or `tools/` — no functional issue, just placement.
4. Re-read the ADR's "residual hole" section once more before merge — it's the one part of this change
   that widens exposure rather than closing it, and it's easy to skim past since it's framed as
   pre-existing.

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Fixes the shared helper (both call sites), closes the unborn-HEAD hole the prior architecting verdict found, matches the decisions summary exactly. |
| execution | pass | Ran the suite myself: 108 passed, 0 failed, matching the claim. |
| trajectory | pass | ADR surveys and measures three rejected alternatives; carve-out's three bounds are each mutation-proved, not just asserted. |
| regression | pass | Behavior changes are enumerated as "Accepted costs" in the ADR and each is pinned by a test row (before/after both measured). |
| context_budget | pass | `rules/gates.md` grew by two sentences across two existing bullets (28 lines total); no new always-on file. |
| traceability | pass | ADR 0026 + spec with a six-state measurement table and 19-row test matrix; refusal messages now name the observed checkout. |
| success_masking | pass | Mutation-tested carve-out rows, and the checklist itself records catching a real fixture bug (wrong-cwd path resolution) via writing real assertions. |
| intent_drift | pass | Diff stays inside git-guard.sh/its tests/its docs; no unrelated dependency or drive-by edit found. |
| checkpoint | concern | Working tree has an uncommitted docs-only frontmatter edit at judgment time; one checklist box (branch-cut-from-fetched-origin) left unchecked despite the branch existing. |
| audit_trail | pass | Gate exit is explicitly dated, attributed to the user, and states plainly that no passing verdict exists — the honest disclosure itself is what makes this attributable, not a hidden waiver. |

## Concerns

- Compliance-judge gate exited without a passing verdict (round 6 = fail); latest spec revision unjudged; 3 ids still formally open.
- Working tree not clean at judgment time — uncommitted `phase: review` frontmatter edit on the spec file.
- Carve-out knowingly stacks a second accepted-risk widening on top of the pre-existing merge/cherry-pick/revert/am/rebase COMMIT-fact gap.
- Three measurement scripts now live permanently under `hooks/`, which otherwise holds only executed hooks — placement worth a second look.
- Checklist item "cut the branch from fetched origin/main" left unchecked despite the branch clearly existing.
