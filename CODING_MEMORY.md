# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-18
- last_active_branch: main (synced to origin/main @ 417e8e7)
- current work: post-merge housekeeping, two PRs. **PR #14 (memsearch) MERGED** 2026-07-18T16:57Z
  (commit 7015369). **PR #15 (verifying-subagent-commits) MERGED** 2026-07-18T17:41Z (commit
  417e8e7). Both feature branches deleted, local + remote; both judge verdicts backfilled
  `outcome: clean`. Full history: `coding-memory/branches/memory-rag-index.md`,
  `coding-memory/pr-tracking.md`.
- PR #15 origin: a parallel session's commit (`00705b7`) had landed directly on local `main` with
  no PR, violating default-branch safety — reconciled onto its own branch, rebased, then finished
  (missing "not for X" description clause added, then length-trimmed per judge feedback; no ADR,
  since this skill is explicitly not hook-enforced — see `coding-memory/pr-tracking.md` for detail).
- Model gate: this session (docs/git housekeeping + a small skill-description fix) routed to
  **Sonnet 5**, per user; the memsearch feature work itself ran on Fable 5.

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
- feature/memory-rag-index (2026-07-17→18) — `memsearch`: local SQLite (sqlite-vec + FTS5) RAG over
  session transcripts + curated docs, Qwen3-Embedding-0.6B embeddings, qwen3.6:35b-mlx digests,
  hybrid retrieval, silent SessionStart nudge. 15-task plan, subagent-driven (Sonnet 5 implementers/
  reviewers), 60-test suite green, full backfill 228 sources / 2332 chunks / 0 errors / p95 149ms,
  golden bar 16/16, digest audit 11/12 supported. **PR #14 MERGED 2026-07-18** (merge commit
  7015369); branch deleted. Judge (impl): risk=low conf=high, outcome=clean.
  Detail: `coding-memory/branches/memory-rag-index.md`.
- feature/verifying-subagent-commits (2026-07-18) — new skill: after a dispatched implementer/fix
  subagent reports DONE with a commit SHA, the controller independently confirms via `git log -1`
  in the target checkout that it actually landed there, before trusting the report. Harvested from
  a real trace (a subagent committed to the wrong checkout 3x in one session, despite an explicit
  dispatch-prompt self-check instruction). Not hook-enforced by design. **PR #15 MERGED
  2026-07-18** (merge commit 417e8e7); branch deleted. Judge (impl, head 367da77): risk=low
  conf=high, outcome=clean.

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
1. **memsearch debt (recorded, not blocking; ledger `.superpowers/sdd/progress.md` has detail):**
   `index` exits 0 even when errors>0 (fix before wiring automation to exit codes); validate
   `ollama_url` is loopback; busy_timeout PRAGMA; fail-fast on Ollama-down backfill; `--since`
   format validation; README sentence that digest-chunk line numbers are digest-relative.
   Also live-verify the memsearch-nudge SessionStart line fires in a FRESH session.
2. **Live-verify** doc-guard's SessionStart/PreCompact injection fires end-to-end in a FRESH session
   (hooks load at startup); logic is tested (15-case harness), the event wiring is not yet confirmed
   against a real `/clear` + `/compact`.
3. (Optional) Have the `.claude` repo itself adopt `docs/decisions/` (it now has ADRs 0001-0002 but
   `coding-memory/decisions.md` still serves as the older equivalent); add diagramming pointers to
   `designing-agentic-architecture` / `writing-specs`.
4. (Optional) Backfill `outcome` for the remaining `null` judge verdicts now that results are known:
   `feature/observability-judge` @ fdbd7b9 and @ 381bd79 (PR #13 merged clean), and the memsearch
   *architecting*-stage verdict @ c2b23fe (superseded by the implementation-stage verdict, also
   clean). See `coding-memory/observability-judge/verdicts.jsonl`.

**Merged 2026-07-16:** `.claude` PR #10 (documentation-enforcement) + PR #11 (PORTS.md reconcile) +
PR #12 (diagramming-technical-docs skill); vibe-scape (Tayvyx-Lab/VibeSpace) PR #6 (ADR backfill
0001-0003 + template) + PR #7 (Plan 4a-1 + memory reconcile). No orphans outstanding.

**Merged 2026-07-17:** `.claude` PR #13 (observability judge — agent + judge-guard hook + skill +
gate/catalog + verdict store; merge commit 82d7b9b). Judge + gate now live and global.

**Merged 2026-07-18:** `.claude` PR #14 (memsearch — local RAG index; merge commit 7015369) + PR #15
(verifying-subagent-commits skill — controller-side subagent-checkout verification gate; merge
commit 417e8e7). Both feature branches deleted, local + remote. No orphans outstanding.
