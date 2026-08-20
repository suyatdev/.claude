# Observability verdict — git-guard: detached HEAD (architecting, round 3)

- **repo:** memsearch-freshness
- **branch:** `HEAD` (detached worktree — card named by spec slug, not branch)
- **head_sha:** `0819db75229b2b31a98a080b3edf56bef5720603`
- **spec:** `docs/features/git-guard-detached-head.md` (blob `33cb04d9f4f14090fc05e752e1ff390a2a7dbc3c`)
- **stage:** architecting — advisory only, does not block
- **ts:** 2026-08-10T22:56:51Z
- **risk:** medium · **confidence:** high

## What was changed

A safety hook has a bouncer whose only job is to ask "which branch am I on?" before letting a
commit through to `main`. The bouncer asks the question in a way that answers the literal word
`HEAD` when nobody is on a branch — and since `HEAD` isn't `main`, the bouncer waves everything
through. The spec swaps the question for one that has a single meaning, so "I can't tell" now
means "stop" instead of "go ahead".

Round 3 adds a **carve-out**: while git is mid-rebase, mid-merge, mid-cherry-pick or mid-revert,
the bouncer stands down, because refusing there would leave the operator stuck halfway through an
operation with no way out.

## Does it do what was wanted?

Mostly yes, and the round-2 findings were genuinely adopted at class level rather than patched
narrowly. But the carve-out — the thing I was asked to judge hard — is **not bounded as tightly as
the spec claims**, and two sentences justifying it are falsified by measurement on the spec's own
pinned git 2.50.1.

## What could go wrong

### 1. The carve-out re-opens the exact hole the fix exists to close (measured)

A rebase started *from* `main` leaves HEAD detached with `rebase-merge` present — and on completion
git moves `main` onto the replayed commits. So any hand-written commit at a rebase stop rides onto
`main`. Measured end-to-end:

```
state: symbolic-ref=[] head-name=refs/heads/main
hook exit for 'git commit -m msg -- src/backdoor.sh':  orig=0  patched=0  nocarve=2
after --continue: HEAD branch=main
does main contain the unreviewed file? -> YES, src/backdoor.sh IS ON main
main log: 421eeba c3  75f3e60 sneaky  fd4ef58 c2  21b50f9 c1
```

The `nocarve=2` column is the point: **without** the carve-out the guard catches this; **with** it,
it does not. And the trigger is not exotic — a conflicting `git pull --rebase` on `main` reaches the
identical state (`symbolic-ref=[] markers=[rebase-merge]`, hook exit `0`). Note the spec's own
justifying fixture is an instance: its `rebase-merge/head-name` reads `refs/heads/main`.

Fairness: `orig=0` too, so this is **not a regression** — it is a pre-existing hole the fix declines
to close. The defect is in the claim, not the behaviour: spec:148 says *"This is a deliberate
fail-open, and it is the only one. It is bounded by state git writes to disk"*, and the ADR
obligation describes the widening only as *"a hand-written `git commit` while those operations are
in progress"* — never that such a commit can land on `main`.

**Bounded remedy, measured as implementable:** `rebase-merge/head-name` and `rebase-apply/head-name`
both read `refs/heads/main`. On the cannot-tell arm, keep the guard on when a rebase marker's
`head-name` is `main`/`master`. `CHERRY_PICK_HEAD`/`REVERT_HEAD`/`MERGE_HEAD` while detached commit
onto the detached HEAD and move no branch, so they stay safely carved out. `git am` has no
`head-name`, but `am` stays on a **named** branch (`symbolic-ref=[main]`) and never reaches this arm.
The marker set is over-broad in exactly one direction, and git already writes the discriminator.

### 2. "No refusal is ever issued mid-operation" is false (measured)

spec:246-249 argues the `git switch -c` remedy line is safe *because* the carve-out guarantees this.
It only holds for branchless checkouts. On a **named** `main` with a sequencer running, a refusal is
issued — and the advised remedy cannot be followed:

```
state: symbolic-ref=[main] markers=[MERGE_HEAD]
git-guard: commits to main/master are blocked except documentation (...)
Create a feature branch instead, or stage only documentation.   EXIT=2
$ git switch -c wip
fatal: cannot switch branch while merging
```

Cherry-pick and revert conflicts on named `main` behave identically (both exit `2`). The spec
contradicts itself: spec:141-142 correctly states a named `main` stays guarded *whether or not a
sequencer is running*. Pre-existing behaviour, so not a regression — but the safety argument for
keeping the remedy line unchanged is unsound, and the guarantee must be scoped to "on a branchless
checkout". Git's own hint (`git merge --quit` / `git worktree add`) is the honest wording.

### 3. The carve-out's stated rationale is overstated (measured)

spec:124 and the code comment at spec:130-131 both say the remedy *"would destroy the operation"*.
It would not:

```
$ git switch -c wip
fatal: cannot switch branch while rebasing
after:  on=[] rebase-merge present=yes
      continue: Successfully rebased and updated refs/heads/main.
```

Git refuses and the rebase survives intact. The real harm is milder — an operator stranded with
advice that cannot be followed, and with no bypass variable. The carve-out is still defensible on
that weaker ground, but the **rebase arm carries the highest cost (finding 1) on the most overstated
justification**. That asymmetry should be resolved before implementation, not after.

### 4. Matrix evaluability — good, with three gaps

The 14 rows do now separate the three outcomes: rows 1–5 catch **under-blocking**, rows 6–14 catch
**over-blocking**, and the discriminator claim holds (I built a no-carve-out variant; rows 8/9
collapse to `2` under it, exactly as spec:283-286 asserts). Redundancy is mild and cheap: row 14 is
covered by the existing 77 by the spec's own admission, and row 13 (bare `--force`) is unrelated to
this change. Both are fine as sentinels. Uncovered states that matter:

- **Named `main`/`master` *with* a sequencer marker.** The negative test that pins the carve-out
  inside the cannot-tell arm. Today nothing fails if a future edit hoists `sequencer_in_progress`
  above the `case`. Given this round is entirely about bounding a fail-open, this is the single most
  valuable missing row.
- **Rebase whose `head-name` is `refs/heads/main`.** Finding 1. Even if the hole is accepted, a row
  recording the exit code makes it visible and makes a later tightening a test-first change.
- **The empty-index detached cell** (spec:168, `0 → 2`) is in the cost matrix but has no row among
  the 14, and the checklist says "add all 14 matrix rows" — so a measured cell ships untested. The
  script's ad-hoc probe reproduces it (`0 → 2`).
- Minor: `MERGE_HEAD`/`REVERT_HEAD` detached rows are asserted by construction. The marker loop is
  literal strings, so a typo in an untested name ships silently. ~4 lines each.
- Minor: `git bisect` is branchless with **no** marker, so a commit there is refused (measured `2`).
  Defensible, but it is an over-block not listed among the four accepted costs.

### 5. Fixture audit — clean

Every fixture reaches the state it is named for; I verified independently rather than trusting `ok`.
`rebase_edit` → `symbolic-ref=<empty> markers=[rebase-merge] staged=[src/f1.sh]`; `cherry_conflict`
→ `markers=[CHERRY_PICK_HEAD]`; `unborn_main`/`unborn_feat` → `main`/`feat/x` correctly named;
`nonrepo` → genuinely `fatal: not a git repository`. All 12 rows reproduced. Two hygiene weaknesses
that did **not** bite: `mk()` swallows all setup output and never asserts the state it built (a
future fixture failing to reach its state would still print `ok`), and `mk()` is re-run for reused
names (`feature` ×3, `detached` ×2) with `git init`/`checkout -b` failures suppressed — I confirmed
pass 2 still lands correctly, so results stand, but that is luck rather than design. The
`assert old in src` anchor is good practice and fails loudly on drift.

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Correct root cause; round-2 findings adopted at class level, verified |
| execution | concern | Carve-out lets unreviewed source reach `main` via `git pull --rebase` (measured); two justifications falsified |
| trajectory | pass | Evidence-led; alternatives rejected with reasons; overstatements are the exception |
| regression | pass | Rows 6–14 hold; existing 77 preserved; the hole is pre-existing, not introduced |
| context_budget | pass | Docs-on-demand spec; hook grows ~15 lines, no always-on context |
| traceability | concern | Fail-open documented but its bound described inaccurately; "lands on `main`" unrecorded |
| success_masking | concern | All-green matrix never exercises the state where the carve-out is dangerous, nor the one pinning it |
| intent_drift | pass | Tight scope; explicit out-of-scope list; doc obligations named |
| checkpoint | pass | Planning phase, no code; tests-before-hook ordering; clean revert point |
| audit_trail | pass | ADR 0026 obligation specific, enumerates the five-command class, locates stubs by quoted text |

## Concerns

1. Carve-out lets a hand-written source commit reach `main` via a rebase started from `main`; `git pull --rebase` reaches it
2. `head-name` reads `refs/heads/main` and is unused; a 3-line tightening would bound the rebase arm
3. spec:246-249 "no refusal is ever issued while an operation is running" is false on a named `main` with a marker
4. spec:124/130 "would destroy the operation" is false — `git switch -c` refuses and the rebase survives
5. No matrix row pins `sequencer_in_progress` inside the cannot-tell arm (named `main` + marker)
6. Empty-index detached cell is in the cost matrix but absent from the 14 rows the checklist builds
7. `measure-matrix.sh` fixtures never assert the state they built; reuse of `mk()` state names relies on luck
