# CODING_MEMORY

## Active Session
- session_origin: desktop (CLI)
- session_started_at: 2026-07-12
- last_active_branch: main (branching to feature/standards-extractor-agent for implementation)

## Session Summary
- Refactored the large CLAUDE.md into a compact root file that imports focused rule files under the rules directory.
- Moved broad engineering guidance into dedicated rule files for maintainability.
- Moved PR-related workflow and PR memory requirements into rules/pr-requests.md.
- Added Automated Testing Guardrails to the engineering rules, including strict contract validation tests and local SAST scan requirements.
- Added a prompt sanitization guardrail requiring sensitive data redaction/masking before AI model calls.
- Added branch continuity rules: branch-scoped implementation memory, resume-from-memory behavior, and main-to-feature branching before brainstorming/implementation.
- Added session origin tracking rules: session environment (desktop/remote/browser) is recorded at session start; cross-environment resume requires reading memory and verifying branch state; most recent session timestamp is source of truth.
- Updated global MCP config for Atlassian under the /Users/marksuyat project scope to use direct HTTP (`https://mcp.atlassian.com/v1/mcp/authv2`) instead of the `mcp-remote` launcher.
- Brainstormed and approved the design for a new global subagent, `standards-extractor`: extracts development guidelines/architectural constraints/coding standards from provided PDF(s) into structured, actionable Markdown rule files (categorized, matching this repo's `rules/*.md` style). Extraction-only scope (no enforcement). Output directory is always supplied by the caller, never hardcoded.
- Noted `VibeCodingRules/` in this repo already contains 5 candidate source PDFs (Agent Skills, Agent Tools & Interoperability, Spec-Driven Development, The New SDLC, Vibe Coding Security) that this agent is intended to process.

## Key Decisions And Conventions
- CLAUDE.md now acts as a lightweight entry point with @imports.
- PR process and PR-memory logic are centralized in rules/pr-requests.md.
- Session-state requirements are maintained in a dedicated rules/session-state-management.md file.
- Security workflow now explicitly requires malicious-payload contract tests and a local `security:scan` step before accepting complex refactors.
- Prompting workflow now requires least-data sharing and explicit redaction of secrets/PII before sending model prompts.
- PR workflow now requires branch implementation memory to be committed with the branch/PR and requires brainstorming on feature branches instead of `main`/`master`.
- PR memory fields now include the session origin that opened the PR and the session origin of the most recent push, enabling cross-environment PR continuity.
- New global subagent `standards-extractor` (tools: Read, Write, Bash, Glob; no model override) will live at `~/.claude/agents/standards-extractor.md`, one Markdown file per inferred rule category plus an `index.md`, styled after existing `rules/*.md` files.

## Exact Next Steps
1. Keep adding future policy updates to focused files under rules/ instead of expanding CLAUDE.md.
2. If PR workflow rules change again, update rules/pr-requests.md first.
3. Keep CODING_MEMORY.md updated after major structural or policy changes.
4. If needed, add/align a real `security:scan` script in active project repositories to match the new guardrail.
5. Apply prompt redaction placeholders consistently in future AI-assisted tasks when sensitive data appears.
6. When resuming any branch, read and update that branch's implementation memory before coding further.
7. At the start of each session, record `session_origin` (desktop/remote/browser) and `session_started_at` in `CODING_MEMORY.md` under the active session block.
8. Create and switch to `feature/standards-extractor-agent`, then implement `~/.claude/agents/standards-extractor.md` per the approved design.
9. Verify the new agent by running it against one of the `VibeCodingRules/*.pdf` files before opening a PR.
10. Open a PR for the new agent file (repo has remote `origin` at `git@github.com:suyatdev/.claude.git`); record PR metadata here once created.
