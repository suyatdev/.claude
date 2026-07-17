# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-17
- last_active_branch: feature/memory-rag-index (spec committed; not yet pushed)
- current work: memory RAG index (`memsearch`) — brainstorm APPROVED, spec written. Local
  SQLite (sqlite-vec + FTS5) RAG over transcripts + curated docs; Qwen3-Embedding-0.6B
  embeddings, qwen3.6:35b-mlx digests (keep_alive=0), newest-first backfill, `rename` cmd,
  hybrid retrieval, silent SessionStart nudge. Store-choice decision (SQLite over Qdrant) +
  revisit trigger (>500k chunks or p95 >500ms) recorded in spec. Next: observability judge
  (design stage), then writing-plans.
  Spec: `docs/superpowers/specs/2026-07-17-memory-rag-index-design.md`.

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
  `setting-up-a-new-project`, gates stub. Verified (15-case harness). **PR #10 MERGED (2026-07-16).**
  Detail: `coding-memory/branches/documentation-enforcement.md`.
- PR #11 (chore/ports-registry-snatch-8001) — MERGED 2026-07-16. Reconciled the orphaned PORTS.md
  edit (snatch-bracket backend on port 8001) as its own commit, per user's commit-only-my-work call.
- PR #12 (feature/diagramming-skill) — MERGED 2026-07-16. New `diagramming-technical-docs` skill
  (Mermaid docs standard: SKILL.md + references/assets/scripts validator; Mermaid-not-PlantUML).
  Detail: `coding-memory/branches/diagramming-skill.md`.
- feature/observability-judge (2026-07-16) — the observability judge (16 commits, 17/17 tests):
  `agents/observability-judge.md` (subagent scoring 10 dims → JSONL+markdown verdict + junior-dev
  layman summary), `hooks/judge-guard.sh` (+17-case test + settings.json) blocking `gh pr create`
  without a fresh strict-freshness verdict, `skills/running-the-observability-judge/`, `rules/gates.md`
  stub + `CLAUDE.md` catalog, ADR `docs/decisions/0001-observability-judge.md`, spec
  `docs/superpowers/specs/2026-07-16-observability-judge-design.md`, verdict store. Command detection
  took 2 review-driven security fixes (substring→anchored→python shlex, closing a quoted-env-prefix
  bypass); Opus whole-branch review fixed the verdict-filename-on-slashed-branches bug + a stale
  `hooks/README.md` "only git-guard installed" claim. **PR #13 MERGED 2026-07-17 (bootstrap self-gate → JUDGE_EXEMPT).**
  Detail: `coding-memory/branches/observability-judge.md`; PR status: `coding-memory/pr-tracking.md`.

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
1. **Live-verify** doc-guard's SessionStart/PreCompact injection fires end-to-end in a FRESH session
   (hooks load at startup); logic is tested (15-case harness), the event wiring is not yet confirmed
   against a real `/clear` + `/compact`.
2. (Optional) Have the `.claude` repo itself adopt `docs/decisions/` (it uses
   `coding-memory/decisions.md` as its equivalent today); add diagramming pointers to
   `designing-agentic-architecture` / `writing-specs`.

**Merged 2026-07-16:** `.claude` PR #10 (documentation-enforcement) + PR #11 (PORTS.md reconcile) +
PR #12 (diagramming-technical-docs skill); vibe-scape (Tayvyx-Lab/VibeSpace) PR #6 (ADR backfill
0001-0003 + template) + PR #7 (Plan 4a-1 + memory reconcile). No orphans outstanding.

**Merged 2026-07-17:** `.claude` PR #13 (observability judge — agent + judge-guard hook + skill +
gate/catalog + verdict store; merge commit 82d7b9b). Judge + gate now live and global.
