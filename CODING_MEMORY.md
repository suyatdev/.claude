# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-14
- last_active_branch: feature/rules-to-skills-restructure

## Repositories

### suyatdev/.claude
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR #4 (feature/vibe-coding-standards-integration) — MERGED 2026-07-12.
- PR #3 (feature/standards-extractor-agent) — MERGED.
- PR #5 (feature/modular-coding-memory) — MERGED 2026-07-14. `main` fast-forwarded to include it.
- PR #6 (feature/new-project-memory-scaffold) — MERGED 2026-07-14.
- PR #7 (feature/new-project-memory-scaffold) — MERGED 2026-07-15. Design spec + memory checkpoint.
- PR #8 (feature/new-project-memory-scaffold) — MERGED 2026-07-15. Reconciliation: local port
  registry, Hard Model Gate, Session Freshness Checkpoint, settings.json, .gitignore.
- PR #9 (feature/rules-to-skills-restructure) — open, awaiting review. The rules-to-skills
  restructure itself: 7 always-loaded rule files → core-conduct.md + gates.md + 5 new skills +
  git-guard hook. Always-on content: 4,030 → 1,151 words.
- Full detail: `coding-memory/pr-tracking.md`

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
1. **Wait for PR #9 review/merge.** This is the rules-to-skills restructure itself — see
   `coding-memory/branches/rules-to-skills-restructure.md` for the full implementation log.
2. **Cleanup once PR #9 merges:** `feature/new-project-memory-scaffold` still carries 2 commits
   (a `.gitignore` fix + this same restructure's plan doc) that were pushed after PR #8 already
   merged, so they never landed on `main` via that PR. They were cherry-picked onto
   `feature/rules-to-skills-restructure` instead (see that branch's log) and will land via PR #9.
   Once #9 merges, `feature/new-project-memory-scaffold` can be deleted — nothing on it is still
   needed.
