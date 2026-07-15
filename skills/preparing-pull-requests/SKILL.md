---
name: preparing-pull-requests
description: Use when naming a branch, writing a commit message, opening or updating a pull request, or resuming work on an existing branch/PR. Covers branch naming, Conventional Commits, the PR description template, PR memory tracking, and brainstorm-then-branch sequencing. Not for the default-branch-commit or force-push gates themselves (see rules/gates.md) or the new-project setup register (see setting-up-a-new-project).
---

# Preparing Pull Requests

## Branching

- **Name branches after what changed, not who or when:** `feature/short-description`, `bugfix/short-description`, or `chore/short-description` — readable as a plain-English summary of the PR's purpose (`feature/user-auth-flow`, not `feature/session-2026-07-10` or `feature/mark-changes`).
- **Main-to-feature:** if currently on `main`/`master`, update it, do the brainstorm, then create and switch to a new feature branch before any implementation.
- **Brainstorm-then-branch:** brainstorming and planning happen while on `main`/`master`. When the brainstorm is done, commit the updated `CODING_MEMORY.md` — and only `CODING_MEMORY.md`, no code — to `main`/`master`, then check out the feature branch. Every future branch forked from `main` then inherits the full brainstorm context automatically.
- **Working-branch freshness:** before adding more implementation commits to an existing branch, make sure it's up to date with its tracked remote/base, while still following the PR/remote-first checks below.
- **Branch resume:** before continuing work on an existing branch, read its entry in `CODING_MEMORY.md` and resume from the latest checkpoint.

## Commit Messages

Format every commit via Conventional Commits: `feat(api): add validation checks`, `fix(auth): correct token refresh`, `chore(deps): bump lodash`.

## PR / Remote Workflow

- **PR/remote-first:** before any pull/sync step, check whether an open PR already exists for the current repo/branch and whether a remote already exists for pushing updates.
- **Never pull-first:** don't start a session by pulling from remote just to "update first."
- **Existing PR → update it:** if an open PR and remote already exist for this branch, push to that existing branch/PR rather than opening a new one.
- **No PR yet → create one:** push once, create the PR, and immediately save the PR metadata (below) in `CODING_MEMORY.md`.
- **Later sessions:** consult the saved PR metadata before deciding whether any pull is necessary — don't re-derive it by guessing.
- **Cross-environment continuity:** resuming a PR from a different environment (desktop/remote/browser) than the one that opened it — note the switch in `CODING_MEMORY.md` and verify the branch tip matches the remote before pushing. The session with the most recent push is the most up to date.
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

- Track PR status per repository in `CODING_MEMORY.md` (pointer) and `coding-memory/pr-tracking.md` (detail).
- Per repo, record: repo identifier, branch name, remote name/URL, PR URL or number, whether it's currently open, the `session_origin` that created the PR, and the `session_origin` of the most recent push.
- Maintain a branch-specific implementation log (`coding-memory/branches/<branch>.md`) capturing what's already implemented, what's pending, and the latest checkpoint.
- Commit and push these memory updates as part of the same branch, so continuity context ships inside the PR itself.

## Before Requesting Review

- **Tests pass first:** never approve or request a PR generation unless local tests pass successfully.
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
