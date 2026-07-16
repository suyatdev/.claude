# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-16
- last_active_branch: feature/documentation-enforcement (doc-enforcement backstop; PR #10 OPEN)

## Repositories

### suyatdev/.claude
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR #4 (feature/vibe-coding-standards-integration) — MERGED 2026-07-12.
- PR #3 (feature/standards-extractor-agent) — MERGED.
- PR #5 (feature/modular-coding-memory) — MERGED 2026-07-14. `main` fast-forwarded to include it.
- PR #6, #7, #8 (feature/new-project-memory-scaffold) — all MERGED. Branch deleted 2026-07-15
  (fully superseded — see `coding-memory/branches/new-project-memory-scaffold.md`).
- PR #9 (feature/rules-to-skills-restructure) — MERGED 2026-07-15 (fast-forward, user's choice to
  merge locally rather than wait for GitHub review). Branch deleted. The rules-to-skills
  restructure: 7 always-loaded rule files → core-conduct.md + gates.md + 5 new skills + git-guard
  hook. Always-on content: 4,030 → 1,151 words (~71% cut).
- feature/documentation-enforcement (2026-07-16) — documentation-enforcement backstop:
  `hooks/doc-guard.sh` (block substantial undocumented source commits + surface uncommitted
  work before compaction / at next session start), broadened `managing-session-memory` criteria
  (business-logic + direction-pivoting changes → mandatory + ADR), ADR standard/template in
  `setting-up-a-new-project`, gates stub. Verified (15-case harness). **PR #10 OPEN (2026-07-16).**
  Detail: `coding-memory/branches/documentation-enforcement.md`.
- Full detail: `coding-memory/pr-tracking.md`

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
1. **Review/merge two open PRs:** `.claude` PR #10 (documentation-enforcement backstop) and
   vibe-scape PR #6 (`docs/backfill-decisions-adrs` — ADRs 0001-0003 + template, at
   github.com/Tayvyx-Lab/VibeSpace).
2. **Live-verify** doc-guard's SessionStart/PreCompact injection fires end-to-end — logic is tested
   (15-case harness), but the event wiring needs a real `/clear` + `/compact` in a fresh session
   (hooks load at startup) to confirm.
3. **Orphaned work still uncommitted, left per user's call (2026-07-16):** this repo's `PORTS.md`
   (snatch port 8001); vibe-scape's `CODING_MEMORY.md` edit + untracked plan4a1 doc. Reconcile
   when ready. Detail: `coding-memory/branches/documentation-enforcement.md`.
