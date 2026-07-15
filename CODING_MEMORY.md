# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See rules/session-state-management.md for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-14
- last_active_branch: feature/new-project-memory-scaffold
- Note: prior session was `/clear`'d before its checkpoint save; orphaned work was reconciled and
  committed on 2026-07-15 — see `coding-memory/session-log.md`.

## Repositories

### suyatdev/.claude
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR #4 (feature/vibe-coding-standards-integration) — MERGED 2026-07-12.
- PR #3 (feature/standards-extractor-agent) — MERGED.
- PR #5 (feature/modular-coding-memory) — MERGED 2026-07-14. `main` fast-forwarded to include it.
- PR #6 (feature/new-project-memory-scaffold) — open, awaiting review.
- Full detail: `coding-memory/pr-tracking.md`

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
1. **Rules-to-skills restructure (next task):** approved design at
   `docs/superpowers/specs/2026-07-14-rules-to-skills-restructure-design.md` (committed on
   feature/new-project-memory-scaffold). Next step: invoke `superpowers:writing-plans` to create the
   implementation plan — re-confirmed staying on Sonnet for this per the Hard Model Gate (2026-07-15).
   Implementation gets its own feature branch off main. The restructure replaces the 7 rules files with
   core-conduct.md + gates.md, 5 new skills (agentskills.io-conformant), and a git-guard PreToolUse
   hook. This also supersedes the old "trim pass on rules budget" note — the restructure IS the trim.
2. Wait for PR #6 review/merge (branch also now carries the restructure spec commits plus the
   2026-07-15 reconciliation commits — local port registry, Hard Model Gate, Session Freshness
   Checkpoint, settings.json tweaks, .gitignore cleanup).
