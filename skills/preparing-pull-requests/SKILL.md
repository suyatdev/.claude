---
name: preparing-pull-requests
description: Use when naming a branch, writing a commit message, opening or updating a pull request, or resuming work on an existing branch/PR. Covers branch naming, Conventional Commits, the PR description template, PR memory tracking, and brainstorm-then-branch sequencing. Not for the default-branch-commit or force-push gates themselves (see rules/gates.md) or the new-project setup register (see setting-up-a-new-project).
---

# Preparing Pull Requests

## Branching

- **Name branches after what changed, not who or when:** `feature/short-description`, `bugfix/short-description`, or `chore/short-description` — readable as a plain-English summary of the PR's purpose (`feature/user-auth-flow`, not `feature/session-2026-07-10` or `feature/mark-changes`).
- **Main-to-feature:** if currently on `main`/`master`, update it, do the brainstorm, then create and switch to a new feature branch before any implementation.
- **Brainstorm-then-branch:** brainstorming and planning happen while on `main`/`master`. When the brainstorm is done, commit the feature card under `docs/features/` — documentation only, no code — to `main`/`master`, then check out the feature branch. `git-guard` permits little else on the default branch: the allowlist is `docs/*.md` plus the two judge ledgers by exact path (`coding-memory/observability-judge/verdicts.jsonl`, `coding-memory/compliance-judge/verdicts.jsonl`), so the older instruction to commit `CODING_MEMORY.md` here is now **blocked**, not merely stale — ADR 0031 retired that file, while the two ledgers stayed tracked and are named individually so they remain committable. For feature-scale work the brainstorm's decisions carry forward in the card's spec, created before the branch exists; for everything else, the handoff and commit history are what the next session actually reads.
- **Working-branch freshness:** before adding more implementation commits to an existing branch, make sure it's up to date with its tracked remote/base, while still following the PR/remote-first checks below.
- **Branch resume:** before continuing work on an existing branch, follow `managing-session-memory`'s restore procedure — the live handoff and, for feature-scale branches, `docs/features/<name>.md` are the primary source, not `CODING_MEMORY.md`. Reach `CODING_MEMORY.md` only by targeted lookup (grep or `memsearch query`), never a full read, and mainly for non-feature-scale branches that have no feature file — and note it is now a **frozen, machine-local** archive (ADR 0031), so it will not exist in a fresh clone and nothing new is appended to it.

## Commit Messages

Format every commit via Conventional Commits: `feat(api): add validation checks`, `fix(auth): correct token refresh`, `chore(deps): bump lodash`.

## PR / Remote Workflow

- **PR/remote-first:** before any pull/sync step, check whether an open PR already exists for the current repo/branch and whether a remote already exists for pushing updates.
- **Never pull-first:** don't start a session by pulling from remote just to "update first."
- **Existing PR → update it:** if an open PR and remote already exist for this branch, push to that existing branch/PR rather than opening a new one.
- **No PR yet → create one:** push once, create the PR — as a draft, per the flow below. The PR's own metadata needs no local copy; `gh pr view` is the record (see PR Memory Tracking).
- **Open every PR as a draft:** `gh pr create --draft` → commit and push the audit trail → `gh pr ready`. This is enforceable rather than advisory: GitHub refuses to merge a draft, and `hooks/judge-guard.sh` matches on `gh pr create`, so a draft clears the *identical* freshness gate with no hook change. It removes the Merge button for exactly the window that causes stranding, instead of asking a human to remember.
- **Why advisory versions were abandoned:** the mitigation this replaced was "remember to say it out loud" — a promise written after each of three stranding incidents and each time followed by another. Advisory mitigations are **0-for-3** by the record's own evidence, and a chat message never reaches whoever clicks Merge days later.
- **Check reachability after a merge:** always verify `git merge-base --is-ancestor <tip> origin/main` after a PR merges — never assume the merge captured the branch tip.
- **Later sessions:** query the PR's live state with `gh pr view` before deciding whether any pull is necessary — don't guess, and don't look for a saved local copy; there isn't one any more.
- **Cross-environment continuity:** resuming a PR from a different environment (desktop/remote/browser) than the one that opened it — note the switch in the branch's `docs/features/<name>.md` (or the PR description, for non-feature-scale work) and verify the branch tip matches the remote before pushing. The session with the most recent push is the most up to date. Note that `.claude/session-state.md` is machine-local and will be absent here, so it cannot carry the handover.
- **A merged PR is closed, not paused:** if you push new commits to a branch whose PR already merged, that push does **not** reopen the old PR — GitHub does not resurrect a merged PR from a later push. Check the PR's actual state (e.g. `gh pr view <n> --json state,mergedAt`) before assuming "push to the existing branch" satisfies the "update the existing PR" rule; if it's already merged, open a new PR for the new commits instead.

## The PR Description Template

Every PR description covers, in this order:

1. **What changed, in plain language** — translate technical/architectural detail for a non-engineer; define any unavoidable jargon inline.
2. **Why the change was made.**
3. **Links to related PRs**, or "None."
4. **Screenshots**, if UI-related: a scoped **before** and **after** of the specific section that changed (not a full-page dump). If non-UI: "N/A - non-UI change."
5. **Step-by-step testing instructions** used to verify the change.
6. **Change summary and risk assessment:** what changed and where it could break, so review targets architectural impact over line-by-line diffing.

## PR Memory Tracking

- **GitHub is the record of PR state.** Branch, remote, PR number, open/closed, and merge commit are all derivable with `gh pr view` / `gh pr list --state all` — do not maintain a parallel copy. `CODING_MEMORY.md` and `coding-memory/pr-tracking.md` are **retired and gitignored** (ADR 0031): writing PR state there now succeeds locally and never leaves the machine, which is worse than not recording it.
- What GitHub does *not* hold, and therefore still gets written down: the **reasoning** — why a PR was closed unmerged, a decision taken mid-review, a cross-environment handover. That goes in the branch's `docs/features/<name>.md`, or an ADR under `docs/decisions/` if it is structural.
- For feature-scale branches, implementation state lives in the branch's `docs/features/<name>.md` (frontmatter + checklist) per `managing-session-memory`. Non-feature-scale branches (a fix, a chore) have no such file; the commit history and the PR description are the record.
- Commit and push these updates as part of the same branch, so continuity context ships inside the PR itself.

## Before Requesting Review

- **Tests pass first:** never approve or request a PR generation unless local tests pass successfully.
- **Feature PRs update the README Roadmap:** if the PR delivers a feature or user-visible implementation, the repo README's Roadmap section reflects it in this same branch (see `writing-project-readmes`). Fixes, refactors, and chores are exempt — the roadmap tracks capabilities, not internals.
- **Scrutinize AI-written code harder than human-written:** hallucinated dependencies, thin error handling, and correctness gaps that look right at a glance are the specific failure modes to check for. Approval fatigue is a quality risk, not an inconvenience — approving without reading is not reviewing.

## Trigger Phrases

Positive — this skill should fire:

- "let's open a PR for this branch"
- "what should I name this branch?"
- "I'm resuming work on an old feature branch, what's the status?"

Negative — this skill should *not* fire:

- "should I commit this straight to main?" → `rules/gates.md` (default-branch safety)
- "set up a new repo" → `setting-up-a-new-project`
- "add input validation to this endpoint" → `writing-secure-code`
