# Branch Implementation Log: feature/new-project-memory-scaffold

**Status:** implemented, not yet pushed/PR'd.

## What changed

- `skills/setting-up-a-new-project/SKILL.md`, "Recording the Answers" step 3: new repos now get their
  own `CODING_MEMORY.md` (lean index) plus a `coding-memory/` directory for history from the first
  commit, instead of accumulating one flat file that needs a later cleanup pass like PR #5 did for
  this repo.

## Why

The modular-memory rule in `rules/session-state-management.md` (added in PR #5) already applies to
every project automatically — it's a global rule. But it only kicks in reactively, once a project's
`CODING_MEMORY.md` grows large enough to need splitting. Wiring the scaffold into the new-project setup
gate means new repos start correctly instead of drifting into the same monolith-then-split cycle.

## Impact

- Only affects repos that run the `setting-up-a-new-project` skill going forward. No effect on existing
  repos or this session's changes.
- No existing project on this machine currently has a `CODING_MEMORY.md` (checked via filesystem
  search), so there was nothing to retroactively migrate.

## Next steps

1. User confirms pushing the branch and opening the PR.
