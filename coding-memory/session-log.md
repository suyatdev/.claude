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
