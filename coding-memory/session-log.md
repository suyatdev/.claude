# Session Log

Chronological session summaries. Entries before 2026-07-13 predate the plain-language/impact-only
standard in rules/session-state-management.md and are kept verbatim for history. New entries should
follow that standard: major architectural changes only, no routine steps, plain language.

## 2026-07-12 — VibeCodingRules standards integration

- Refactored the large CLAUDE.md into a compact root file that imports focused rule files under the rules directory.
- Moved broad engineering guidance into dedicated rule files for maintainability.
- Moved PR-related workflow and PR memory requirements into rules/pr-requests.md.
- Added Automated Testing Guardrails to the engineering rules, including strict contract validation tests and local SAST scan requirements.
- Added a prompt sanitization guardrail requiring sensitive data redaction/masking before AI model calls.
- Added branch continuity rules: branch-scoped implementation memory, resume-from-memory behavior, and main-to-feature branching before brainstorming/implementation.
- Added session origin tracking rules: session environment (desktop/remote/browser) is recorded at session start; cross-environment resume requires reading memory and verifying branch state; most recent session timestamp is source of truth.
- Updated global MCP config for Atlassian under the /Users/marksuyat project scope to use direct HTTP (`https://mcp.atlassian.com/v1/mcp/authv2`) instead of the `mcp-remote` launcher.
- Brainstormed and approved the design for a new global subagent, `standards-extractor`: extracts development guidelines/architectural constraints/coding standards from provided PDF(s) into structured, actionable Markdown rule files (categorized, matching this repo's `rules/*.md` style). Extraction-only scope (no enforcement). Output directory is always supplied by the caller, never hardcoded.
- Correction: initially noted a `VibeCodingRules/` directory with 5 candidate source PDFs, but verified this does not actually exist in the repo (not on disk, not tracked by git) — that was a bad tool-output read, not a real finding. The agent's design does not depend on those files; verification instead used a synthetic test PDF.
- `standards-extractor` agent confirmed working end-to-end against a real PDF (not just the earlier synthetic test): correctly loads from the global agent registry in a fresh session, chunks long PDFs via the `pages` parameter, infers a document-specific taxonomy instead of a fixed one, and produces output matching this repo's `rules/*.md` conventions.
- Ran `standards-extractor` against all remaining PDFs in `vibeCodingrules/` (3 in parallel), completing full coverage of the 4-PDF set: `Agent Skills_Day_3.pdf` → `extracted-standards/agent-skills-day-3/` (7 categories), `The New SDLC With Vibe Coding_Day_1.pdf` → `extracted-standards/the-new-sdlc-with-vibe-coding-day-1/` (7 categories), `Agent Tools & Interoperability_Day_2.pdf` → `extracted-standards/agent-tools-and-interoperability-day-2/` (6 categories). All outputs verified present on disk (`ls` per directory).
- A 5th PDF (`Spec-Driven Production Grade Development in the Age of Vibe Coding Day_5.pdf`) was found in the same folder and also run: → `extracted-standards/spec-driven-production-grade-development-day-5/` (7 categories: spec-driven development, instruction/context management, prompting by use case, MCP integration, team culture/code review, zero-trust guardrails, testing/evaluation). Verified present on disk. All 5 source PDFs in `vibeCodingrules/` now have structured extracted-standards output — full coverage of that folder.

## 2026-07-13 — Modular CODING_MEMORY.md

- `CODING_MEMORY.md` was a single 180-line file mixing active state with full PR/branch/brainstorm
  history — heading toward unbounded growth and read in full every session.
- Split it into an index (`CODING_MEMORY.md`, ≤200 lines: active session, repo/PR pointers, next
  steps) plus a `coding-memory/` directory holding the full history (PR tracking, session log,
  decisions, branch logs, brainstorms), linked by path instead of inlined.
- Added standing rules (`rules/session-state-management.md`) requiring future session summaries and
  PR descriptions to be plain-language, impact-focused, and free of routine-step detail.

## 2026-07-14 — Rules-to-skills restructure design approved

- Wrote the missing auto-memory file explaining the ~4K session-freshness checkpoint (why incremental
  growth, not an absolute ceiling, triggers the save+clear prompt). A proposed 5K hard ceiling was
  discussed and rejected: a single task plus the memory-save itself would regularly blow past a 1K buffer.
- Brainstormed and approved a full restructure of the always-loaded rules: the 7 rules/*.md files will be
  replaced by two static files (core-conduct.md invariants, gates.md critical-gate stubs), five new
  on-demand skills (managing-session-memory, preparing-pull-requests, writing-secure-code,
  allocating-local-ports, triaging-new-instructions), and a deterministic git-guard hook blocking
  commits/force-pushes to main. Cuts always-loaded context from ~5.2K to ~1.8K tokens per turn.
- All new skills must conform to the agentskills.io specification (validated with skills-ref; body under
  500 lines; description ≤1,024 chars stating what/when/when-not).
- Approved spec: docs/superpowers/specs/2026-07-14-rules-to-skills-restructure-design.md (3 commits on
  feature/new-project-memory-scaffold). Implementation not started — next step is the implementation
  plan on a cheaper model per the Hard Model Gate.

## 2026-07-15 — Resumed after mid-checkpoint /clear, reconciled orphaned work

- Session opened with a plain "continue" right after a `/clear`. Restoring from `CODING_MEMORY.md`
  surfaced work in the tree that the prior session never logged or committed before being cleared:
  new Hard Model Gate + Session Freshness Checkpoint rules, a new local port registry
  (`PORTS.md` + `rules/local-port-registry.md`), and `settings.json` permission/effort changes.
  Also found several untracked Claude Code runtime directories (`daemon/`, `jobs/`, `plans/`,
  `paste-cache/`, `file-history/`, `gh-pr-status-cache.json`) with no relation to any documented task.
- Confirmed with the user before acting: committed the pending rule/config changes to
  `feature/new-project-memory-scaffold` (PR #6) as four scoped commits, and added the runtime
  directories to `.gitignore` without inspecting their contents (some could hold pasted secrets).
  Detail: `coding-memory/branches/new-project-memory-scaffold.md`.
- Confirmed staying on Sonnet (already the configured model) before starting the rules-to-skills
  implementation plan, per the Hard Model Gate.
- Always-on rules budget is now 4,030/3,500 words (~15% over) — see `coding-memory/decisions.md`.
  Not trimming piecemeal: the approved rules-to-skills restructure replaces this whole budget and is
  the very next task.
- Wrote the 12-task implementation plan (`docs/superpowers/plans/2026-07-15-rules-to-skills-restructure.md`)
  via `superpowers:writing-plans`, self-reviewed it, and caught several real issues before execution:
  a word-count overshoot in the drafted `core-conduct.md` (771 vs. a 450-550 target — rewritten as
  denser prose to 489), a Markdown nested-fence bug in one skill's embedded content that would have
  desynced the rest of the plan document, and a `.gitignore` bug the reconciliation work had just
  introduced (an unanchored `plans/` pattern silently blocking `docs/superpowers/plans/`).
- Discovered mid-session that PR #8 had merged before two more commits (the gitignore fix + this
  plan doc) were pushed — the same "orphaned after merge" pattern as PR #6/#7. Opened PR #8 for the
  first batch of orphaned commits earlier; this second batch was later recovered via cherry-pick
  onto the implementation branch rather than a 4th PR.
- Executed the plan via `superpowers:subagent-driven-development` (fresh implementer + independent
  reviewer per task, all 12 tasks). Task 11 (deleting the 7 old rule files) is where real gaps
  surfaced: a "Guiding Principle" paragraph silently dropped during the `core-conduct.md` rewrite,
  and ~12 other live files still naming the deleted rule files — neither of which the plan itself
  had scoped, both caught by task review before merge. A first fix pass introduced a second-order
  misattribution (2 references repointed to a real-but-wrong file), caught by a third review pass.
  Opened PR #9. Always-on content: 4,030 → 1,151 words. Full log:
  `coding-memory/branches/rules-to-skills-restructure.md`.

## 2026-07-16 — Documentation audit + enforcement backstop

- Audited how the four active projects document decisions. Content is strong
  (business-logic and direction-pivoting decisions, with reasoning, are captured),
  but the ADR pattern is uneven — Snatch-Bracket has `docs/decisions/`, vibe-scape
  has none — and capture depends on checkpoint discipline that slipped once.
- Per user request, broadened the mandatory-documentation criteria (business-logic +
  direction-pivoting changes now explicit save triggers, each earning an ADR) and
  built a backstop: `hooks/doc-guard.sh` (block substantial undocumented source
  commits; surface uncommitted work before compaction and at the next session start),
  plus skill edits, an ADR template, and a `gates.md` stub. Verified the hook with a
  15-case harness (all green).
- Branch `feature/documentation-enforcement`. Next: vibe-scape ADR backfill (its own
  repo/PR), then PR this branch. Full log:
  `coding-memory/branches/documentation-enforcement.md`.
