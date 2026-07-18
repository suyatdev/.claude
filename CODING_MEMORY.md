# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-17
- last_active_branch: feature/memory-rag-index (7 commits; commits 1-6 PUSHED, commit 7 = settings chore a3de623 local; no PR yet — next is writing-plans)
- current work: memory RAG index (`memsearch`) — brainstorm APPROVED, spec written + judged.
  Local SQLite (sqlite-vec + FTS5) RAG over transcripts + curated docs; Qwen3-Embedding-0.6B
  embeddings, qwen3.6:35b-mlx digests (keep_alive=0), newest-first backfill, `rename` cmd,
  hybrid retrieval, silent SessionStart nudge. SQLite-over-Qdrant decision + revisit trigger
  (>500k chunks or p95 >500ms) recorded. CODING_MEMORY.md excluded from index (ephemeral).
  Design-stage observability judge: risk=low, confidence=medium (advisory, not gating).
  Spec: `docs/superpowers/specs/2026-07-17-memory-rag-index-design.md`.
  Verdict: `coding-memory/observability-judge/2026-07-17-feature-memory-rag-index.md`.
- MODEL SETTLED: writing-plans runs on **Fable 5**. Default committed to settings.json
  (chore be44ca2, opus[1m]→claude-fable-5[1m]).
- RESUME 2026-07-17 (session C): reconciled a /clear-orphaned verdicts.jsonl append (docs 8e4251d —
  Snatch-Bracket impl-stage verdict landed in the global store before that session checkpointed).
  Then EXECUTED the memsearch plan (subagent-driven, Sonnet 5 implementers/reviewers).
- MEMSEARCH EXECUTION (2026-07-17→18): Tasks 1-14 COMPLETE, all task-reviewed Approved; Task 15
  Steps 1-2 committed (golden set + acceptance test), Step 3 full backfill (~69 sessions, hours)
  RUNNING in background. 60-test suite green. Live index: 154 sources / 2041 chunks / 0 errors,
  qwen3-embedding:0.6b 1024-dim, provenance + digest audits passed, idle RAM zero verified.
  Review loops fixed 5 plan-inherited defects (all logged as plan deviations in the SDD ledger
  + branch log): JSONDecodeError escape (ollama), user list-content text dropped + non-dict crash
  (extract), vacuous subagents-exclusion test (indexer), LIKE-wildcard count inflation (rename),
  oversized-section embed 400 + venv pollution (chunk/config, found live in Task 14).
  Ledger: .superpowers/sdd/progress.md. Branch log: coding-memory/branches/memory-rag-index.md.
  PARALLEL-WORK NOTE: uncommitted changes by another session sit in the working tree (CLAUDE.md,
  rules/gates.md, verdicts.jsonl append, untracked skills/verifying-subagent-commits/) — left
  alone by this session; reconcile whenever that session checkpoints.
  REMAINING: Task 15 Steps 4-6 (golden bar, digest audit, final commit) after backfill; Task-15
  task-review; final whole-branch review; observability judge (implementation stage); PR.
- RESUME 2026-07-17 (session B): reconciled a /clear-orphaned settings.json (chore a3de623),
  user switched session to Fable 5, then **writing-plans COMPLETED**: 15-task implementation plan
  written + self-reviewed at `docs/superpowers/plans/2026-07-17-memory-rag-index.md` (3,079 lines,
  full TDD code per task). All 5 judge flags mapped: (a) golden bar T15, (b) digest audit T10+T15,
  (c) ADR 0002 T13, (d) dep sign-off T1-Step-0, (e) one-line hook T12. Self-review fixed: chunk_digest
  H2-split, negative-golden semantics (warn-not-fail — RRF has no absolute confidence floor),
  vec0 LIMIT inlining, task renumbering. Verified live: qwen3-embedding:0.6b NOT yet pulled
  (T14 pulls it), 72 main transcripts + 578 subagent files (subagents excluded from indexing).
  NEXT: user picks execution mode + confirms sqlite-vec/uv dep sign-off, then execute the plan.

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
1. **memsearch — EXECUTE THE PLAN (all gates cleared 2026-07-17):** plan at
   `docs/superpowers/plans/2026-07-17-memory-rag-index.md` (15 tasks, TDD, complete code).
   User decisions recorded: (i) execution = **subagent-driven** (superpowers:subagent-driven-development);
   (ii) **dep sign-off APPROVED** — sqlite-vec==0.1.9 + uv/Python 3.12 + pytest==8.3.4 dev-only;
   cite "user approved at plan approval (2026-07-17)" in Task 1's commit body; (iii) Hard Model Gate
   answered = **Sonnet 5 for implementation** — orchestrate from this session, dispatch task subagents
   with model: sonnet; do NOT re-ask. Start at Task 1. Task 14 (live bring-up) + Task 15 Step 3
   (full backfill, hours) run in the main session, not a subagent.
2. **Live-verify** doc-guard's SessionStart/PreCompact injection fires end-to-end in a FRESH session
   (hooks load at startup); logic is tested (15-case harness), the event wiring is not yet confirmed
   against a real `/clear` + `/compact`.
3. (Optional) Have the `.claude` repo itself adopt `docs/decisions/` (it uses
   `coding-memory/decisions.md` as its equivalent today); add diagramming pointers to
   `designing-agentic-architecture` / `writing-specs`.

**Merged 2026-07-16:** `.claude` PR #10 (documentation-enforcement) + PR #11 (PORTS.md reconcile) +
PR #12 (diagramming-technical-docs skill); vibe-scape (Tayvyx-Lab/VibeSpace) PR #6 (ADR backfill
0001-0003 + template) + PR #7 (Plan 4a-1 + memory reconcile). No orphans outstanding.

**Merged 2026-07-17:** `.claude` PR #13 (observability judge — agent + judge-guard hook + skill +
gate/catalog + verdict store; merge commit 82d7b9b). Judge + gate now live and global.
