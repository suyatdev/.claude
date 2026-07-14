# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See rules/session-state-management.md for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-13
- last_active_branch: feature/new-project-memory-scaffold

## Repositories

### suyatdev/.claude
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR #4 (feature/vibe-coding-standards-integration) — MERGED 2026-07-12.
- PR #3 (feature/standards-extractor-agent) — MERGED.
- PR #5 (feature/modular-coding-memory) — MERGED 2026-07-14. `main` fast-forwarded to include it.
- feature/new-project-memory-scaffold — in progress, PR not yet opened.
- Full detail: `coding-memory/pr-tracking.md`

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
1. Open a PR for `feature/new-project-memory-scaffold` once the user confirms pushing.
2. `feature/modular-coding-memory` is merged but not yet deleted locally/on origin — ask before
   deleting (destructive git op).
3. Nothing else outstanding — the VibeCodingRules integration and standards-extractor agent are both
   shipped and merged.
