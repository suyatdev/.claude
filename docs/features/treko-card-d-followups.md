---
phase: implementation
model_tier: low
branch: chore/treko-card-d-followups
---

> **Gate status: OPEN.** The user said `gate confirmed` on 2026-08-26 for task 4 (the source-file
> comment edit); tasks 1-3 (docs-only frontmatter) needed no gate and are already done, committed
> as `4859144` on the now-deleted `feat/treko-non-text-contrast` and recovered onto this branch by
> cherry-pick (`54dea3c`) after that branch's remote was deleted for task 5 — see task 5 note below.
> Branch cut from `origin/main`. Task 5's two approved remote deletions
> (`feat/treko-non-text-contrast`, `feat/treko-store-location`) are also already done.

# Post-merge follow-ups for card D (PR #80)

Bookkeeping left behind by `treko-non-text-contrast.md` merging as PR #80 (`d740ce2`,
2026-08-26), plus one stale code comment that card D's own criterion 10 forbade touching while
it was open. No behaviour changes. Feature detail lives in `docs/features/treko-non-text-contrast.md`
and ADR 0037 — nothing is restated here.

## Why a card at all

`managing-session-memory` says a one-line fix does not earn a feature file, and the frontmatter
edits below would not need one. Task 4 does: `treko/test_theme.py` is **not** on `phase-guard.sh`'s
exempt list, so the write is denied from any branch while an un-superseded `planning` card exists
(`falsify-harness-signatures`, `treko-branch-graph-traversal`, `treko-degraded-no-cmux`,
`worktree-location-guard` — all legitimately active) and no card claims the working branch at
`phase: implementation`. That is the mechanism the hook names, not a workaround, and it is the
same reason `post-merge-followups-45.md` exists.

## Constraints

- **Branch off `origin/main`; do not check out `main`** — it is held by the worktree
  `.claude/worktrees/treko-card-b-spec`.
- **Do not reopen `feat/treko-non-text-contrast`.** It is merged; card D stays at `phase: review`.
- Four other worktrees are live (`rule-surface-trim`, `treko-card-b-spec`,
  `verifying-durable-claims`, and the primary checkout on `docs/reconcile-worktree-location-guard`).
  Scope every commit with `-- <paths>`; never `git commit -a`.
- Anything that launches Chrome needs `TREKO_CHROME_DENY_BIRD=1`.

## Tasks

- [x] 1 — `docs/features/treko-non-text-contrast.md` frontmatter: `branch: feat/treko-non-text-contrast`
      is stale. Merged via PR #80 (`d740ce2`) 2026-08-26. Record the merge and the branch's fate in
      the same `branch: none  # merged via PR ...` form the other closed cards use.
      **Done** — verified via `gh pr view 80 --json mergeCommit`.
- [x] 2 — `docs/features/treko-theme-and-layout.md` frontmatter: same staleness. Merged via PR #79
      (`82a9315`) 2026-08-25; the remote branch is already gone. This is the item the card-D handoff
      recorded as blocked — it was blocked only because that session could not check out `main`.
      **Done** — this worktree could already read the file (docs/features files aren't
      branch-gated the way the handoff assumed); verified via `gh pr view 79 --json mergeCommit`.
- [x] 3 — `docs/features/treko-store-location.md` frontmatter: same staleness. Merged via PR #68
      (`d499d60`) 2026-08-23; `origin/feat/treko-store-location` still exists and is an ancestor of
      `origin/main`.
      **Done** — verified via `gh pr view 68 --json mergeCommit` and
      `git merge-base --is-ancestor`.
- [ ] 4 — `treko/test_theme.py`: two stale figures, **which are two different measurements and must
      not be given the same value.**
      - `:377` — "848 elements with rendered area … 367 paint a mark in their own color". Card D
        §Background 8 re-measured both on one page load, taking the text count from card A's own
        unmodified `CONTRAST_CHECK_JS`: **851 / 368**, both themes. Re-run the measurement before
        editing rather than copying these numbers across — this comment went stale in place once
        already, and a Chrome re-pin (`152.0.7977.54` → `.65`) landed between that measurement and
        this card.
      - `:324` — "measured on this exact page: 848 visible elements". This one counts
        `document.querySelectorAll('body *').length`, a **body-descendant** count, not rendered
        area. 851 is the wrong relation for it. Card D's "What was NOT verified" section records
        the body-descendant figure as ~902 from planning notes, **not reproducible and dropped
        rather than repeated**. Measure it fresh, or leave the sentence without a number. Do not
        transplant 851.
      - Neither figure is load-bearing: the assertion's floor is `>= 200`. This is a stale comment,
        not a live bug.
- [~] 5 — Branch cleanup. Delete `feat/treko-non-text-contrast` and `feat/treko-store-location`
      locally and on the remote (both are ancestors of `origin/main`), and any other local branch
      that is fully merged and not checked out by a live worktree. Verify merged-ness against
      `origin/main`, not `HEAD` — `git branch -d` checks HEAD and will refuse a branch that is in
      `origin/main`.
      **Partially done, and it nearly ate task 1's work.** The user approved remote-only deletion
      from this session (`feat/treko-non-text-contrast` and `feat/treko-store-location`, both
      confirmed ancestors of `origin/main` via `git merge-base --is-ancestor`). But task 1-3's
      frontmatter fix had already been committed and pushed straight to
      `feat/treko-non-text-contrast` (following the pattern this card's own header cites,
      `post-merge-followups-45.md`) *before* task 5 ran — so `git push origin --delete
      feat/treko-non-text-contrast` deleted the only remote copy of that commit. It was not lost:
      the local branch ref still held it, and it was cherry-picked onto this branch (`54dea3c`,
      originally `4859144`) and verified present in all three files before this card was written.
      **Lesson for next time: do task-5-shaped deletions last, after everything else on the branch
      being deleted is confirmed merged elsewhere — never in the same session as a fix landed on
      that branch with no PR.** Local branch deletion (the "skip local" half the user chose) and
      the broader "any other fully-merged local branch" sweep are still open — do them from a
      worktree that is not sitting on the branch being deleted.

## Not in scope

- **The §D5 DEBT repair** (the three tokens pinned at their current too-faint ratios). It needs its
  own card and an owner. Deliberately not opened here: a new un-superseded `planning` card makes
  `phase-guard` deny source writes repo-wide, which would obstruct the four live worktrees. Whoever
  takes it should know that repairing one token turns the suite red until its recorded ratio is
  re-recorded — that is the design, not a regression.
- **Any palette or `treko/` behaviour change.** Task 4 edits comment prose only.

## Verification

- Task 4: run `treko/test_theme.py` and `treko/test_nontext_contrast.py`; the suite must stay at
  its post-merge count with 0 failed and 0 deselected. A comment edit that changes a count means
  something other than a comment was edited.
- Tasks 1–3: `git diff` shows changes confined to the three frontmatter blocks.
- Task 5: `git branch --list` and `git ls-remote --heads origin` no longer name the deleted refs,
  and `git worktree list` is unchanged.
