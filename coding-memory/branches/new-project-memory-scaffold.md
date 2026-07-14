# Branch Implementation Log: feature/new-project-memory-scaffold

**Status:** implemented, not yet pushed/PR'd.

## What changed

- `skills/setting-up-a-new-project/SKILL.md`, "Recording the Answers" step 3: new repos now get their
  own `CODING_MEMORY.md` (lean index) plus a `coding-memory/` directory for history from the first
  commit, instead of accumulating one flat file that needs a later cleanup pass like PR #5 did for
  this repo.
- `rules/session-state-management.md`, "Session Startup" bullet: extended to cover repos that *never*
  run the setup skill. If a repo has no `CODING_MEMORY.md` when a session starts there, ask the user
  before doing substantive work whether to initialize it — create it only on yes, and don't re-ask
  within the same session if declined.

## Why

The modular-memory rule in `rules/session-state-management.md` (added in PR #5) already applies to
every project automatically — it's a global rule. But it only kicks in reactively, once a project's
`CODING_MEMORY.md` grows large enough to need splitting, and the setup-skill scaffold (above) only
fires for repos that actually run that skill. The session-startup prompt is the catch-all: any repo —
old, new, skill-configured or not — gets asked once per session until it has memory tracking or the
user opts out for that session.

## Impact

- Every future session start, in any repo, now includes a one-time check: does this repo have
  `CODING_MEMORY.md`? If not, the user gets asked before work begins, not silently skipped.
- No existing project on this machine currently has a `CODING_MEMORY.md` (checked via filesystem
  search), so there was nothing to retroactively migrate.
- Always-on rules budget moved from 3,538 to 3,567 words (67 over the prior 3,500 target). See
  coding-memory/decisions.md.

## Next steps

1. User confirms pushing the branch and opening the PR.
