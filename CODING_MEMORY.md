# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-16
- last_active_branch: main (diagramming skill PR #12 merged; tree clean)

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
- feature/observability-judge (2026-07-16, in progress) — `hooks/judge-guard.sh` landed: PreToolUse
  gate blocking `gh pr create` without a fresh implementation-stage verdict (9/9 tests passing),
  wired into settings.json. Follow-up fix: anchored the PR-create detection regex (was matching
  the phrase anywhere in a command string, e.g. inside a commit message) to start-of-command only,
  same pattern as git-guard's `^git` anchor (12/12 tests passing). Round-2 fix: replaced the flat
  bash regex with python shlex-based classification — a quoted-space env-assignment prefix (e.g.
  `FOO="a b" ...`) had defeated the regex and silently bypassed the fail-closed gate (15/15 tests
  passing). Task 3: added `agents/observability-judge.md` (subagent that scores changes and writes
  verdicts to JSONL + markdown).
- Task 4: added `skills/running-the-observability-judge/SKILL.md` (tells main agent when to invoke judge and relay results).
- Task 5: wired the gate stub (`rules/gates.md`) and catalog entry (`CLAUDE.md`) — feature landed
  (agent + skill + `judge-guard.sh` hook + verdict store). ADR: `docs/decisions/0001-observability-judge.md`;
  spec: `docs/superpowers/specs/2026-07-16-observability-judge-design.md`.
- Full detail: `coding-memory/pr-tracking.md`

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
