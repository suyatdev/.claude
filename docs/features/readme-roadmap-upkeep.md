---
phase: review
model_tier: low
branch: docs/readme-roadmap-task-tracker
---

# README Roadmap upkeep after PR #51

**This card exists because `phase-guard.sh` requires one, not because the work is feature-scale.**
`managing-session-memory` is explicit that a typo fix or a one-line change does not earn a feature
file. The guard cannot make that judgment: it denies writes to source while any card sits at
`phase: planning` unless some card at `phase: implementation` records the current branch. Two
unrelated cards (`falsify-harness-signatures`, `verification-marker-gate`) are at `planning` with
`branch: none`, and they belong to other work — advancing or deleting them to unblock this change
would be a workaround, not a fix. So this card is the honest minimum: it records the branch, and it
is deliberately small.

## Scope

Update `README.md`'s `## 🗺️ Roadmap` only. Three lines, all verified against the repo rather than
assumed:

1. **Add** the feature-state tracker as `- [x]` (#51) — merged 2026-08-12 at `06e7c9d`. It was never
   listed, and `writing-project-readmes` says a landed feature is added as `- [x]` if absent.
2. **Check off** per-session pane-split policy with three-lane routing (#28). Verified shipped:
   `panes/dispatch-pane-agent.sh` implements `set-policy`, and this session's own judge dispatches
   printed `ROUTE: lane=judge`.
3. **Check off** the `phase-guard.sh` hook (#30). Verified shipped: it is registered in
   `settings.json` — and it is what blocked this very change, which is the strongest evidence
   available that it is live rather than merely present.

## Out of scope

- The `## What's in here` table has no `task-tracker/` row and no `skills/` row. Real, and left
  alone: the request was the Roadmap. Raise it as its own change.
- The remaining `- [ ]` item (reconciling files that describe the retired
  `coding-memory/branches/<branch>.md` workflow) is untouched — not verified either way.

## Tasks

- [x] 1 — Edit the three Roadmap lines in `README.md`. No other file.
  - All three re-derived, not carried: PR #51 `MERGED` at `06e7c9d`; `phase-guard.sh` is a live
    `Edit|Write|NotebookEdit` registration at `settings.json:42-50` on `origin/main`, not a mention;
    `set-policy` is a real command branch at `panes/dispatch-pane-agent.sh:494`.
  - "Proposes a merge order" checked against source, not the skills catalog: `_layer()` +
    `_build_waves()` in `task-tracker/analyze.py:482-494` derive waves from `## Depends on` edges
    with cycle detection.
- [x] 2 — Observability judge at `implementation` stage, then open the PR.
  - Verdict at `c443d01`: **`risk=low`, `confidence=high`**. Written to the **worktree** store, not
    `$HOME/.claude` — `judge-guard.sh:239-249` resolves the store from `git rev-parse --show-toplevel`
    of the judged repo, so the agent's hardcoded default would have missed the gate entirely.
  - PR **#53** opened while the verdict was still uncommitted; committing it first would move HEAD and
    invalidate it (`head_sha` must equal HEAD).
  - The judge caught a factual error in my own dispatch brief: I wrote "one commit" when the branch
    carries two (`d5c00bb` card, `c443d01` edit). Verdict unaffected — it read the real diff.

## Verification

Roadmap claims must be re-derived, never carried from this card:

```
git show origin/main:settings.json | grep -c phase-guard      # (2) registration
grep -c 'set-policy' panes/dispatch-pane-agent.sh             # (3) policy shipped
gh pr view 51 --json state,mergeCommit                        # (1) merged, 06e7c9d
```
