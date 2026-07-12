# CODING_MEMORY

## Active Session
- session_origin: desktop (CLI)
- session_started_at: 2026-07-12
- last_active_branch: feature/vibe-coding-standards-integration

## PR Tracking

### repo: suyatdev/.claude
- branch: feature/standards-extractor-agent (merged into main, deleted locally and on origin)
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR: https://github.com/suyatdev/.claude/pull/3 (merged, commit 16dd601)
- opened_by session_origin: desktop (CLI)
- last_push session_origin: desktop (CLI)
- implementation status: standards-extractor agent file + design spec merged to main and pulled locally. Verified manually against a synthetic test PDF; real end-to-end invocation via the Agent tool still pending a fresh session that reloads the agent registry.

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
- Correction: initially noted a `VibeCodingRules/` directory with 5 candidate source PDFs, but verified this does not actually exist in the repo (not on disk, not tracked by git) — that was a bad tool-output read, not a real finding. The agent's design does not depend on those files; verification instead used a synthetic test PDF.

- `standards-extractor` agent confirmed working end-to-end against a real PDF (not just the earlier synthetic test): correctly loads from the global agent registry in a fresh session, chunks long PDFs via the `pages` parameter, infers a document-specific taxonomy instead of a fixed one, and produces output matching this repo's `rules/*.md` conventions.
- Ran `standards-extractor` against all remaining PDFs in `vibeCodingrules/` (3 in parallel), completing full coverage of the 4-PDF set: `Agent Skills_Day_3.pdf` → `extracted-standards/agent-skills-day-3/` (7 categories), `The New SDLC With Vibe Coding_Day_1.pdf` → `extracted-standards/the-new-sdlc-with-vibe-coding-day-1/` (7 categories), `Agent Tools & Interoperability_Day_2.pdf` → `extracted-standards/agent-tools-and-interoperability-day-2/` (6 categories). All outputs verified present on disk (`ls` per directory).
- A 5th PDF (`Spec-Driven Production Grade Development in the Age of Vibe Coding Day_5.pdf`) was found in the same folder and also run: → `extracted-standards/spec-driven-production-grade-development-day-5/` (7 categories: spec-driven development, instruction/context management, prompting by use case, MCP integration, team culture/code review, zero-trust guardrails, testing/evaluation). Verified present on disk. All 5 source PDFs in `vibeCodingrules/` now have structured extracted-standards output — full coverage of that folder.

## Brainstorm: VibeCodingRules Standards Integration (2026-07-12)

Goal: apply the 38 extracted-standards markdown files (Days 1-5, ~16.6k words, at
`~/Other Docs/AI/Resources/VibeCodingRules/extracted-standards/`) into how Claude actually operates —
updating `CLAUDE.md`, `rules/*.md`, and adding a `skills/` layer.

Approved design (see spec at `docs/superpowers/specs/2026-07-12-vibe-coding-standards-integration-design.md`):

- **Three-tier architecture, dictated by the standards themselves.** The papers are explicit that active
  context is a budget (a 1M window still degrades at ~50K of active content) and that AGENTS.md/CLAUDE.md
  should stay tight and act as a router. Flattening 16.6k words into always-on rules would violate the
  standards in the act of adopting them. So: `CLAUDE.md` = router; `rules/*.md` = only every-turn behavior
  (~1,950 -> ~3,350 words); `skills/*/SKILL.md` = everything task-specific, zero cost until triggered.
- **Enterprise/product material becomes on-demand design skills, not a dead reference shelf.** A2A, A2UI,
  AP2/UCP, the 7 security pillars, and agent evaluation load when we brainstorm/architect a system that
  needs them, so they translate into future app designs.
- **Reinforce existing tooling, do not duplicate it.** Where superpowers/built-ins already own a workflow
  (systematic-debugging, test-driven-development, skill-creator, /code-review), the whitepaper's specific
  additions go into always-on rules instead of a competing skill — avoiding the trigger-collision/regression
  failure mode Day 3 warns about.
- **Rules layer:** extend the 4 existing files; add 3 new — `context-and-token-discipline.md`,
  `zero-trust-and-agent-safety.md`, `authoring-skills-and-agents.md`.
- **Skills layer (7 new + 1 setup skill):** designing-agentic-architecture, integrating-mcp,
  securing-agentic-systems, designing-agent-interop (A2A+A2UI), designing-agent-commerce (AP2+UCP),
  evaluating-agents-and-skills, writing-specs, setting-up-a-new-project.
- **Hooks: designed, not installed.** Scripts written and documented (secret scan, zero-width-Unicode /
  homoglyph scan per Day 4's invisible-payload rule, checkpoint-before-modify) but `settings.json` left
  untouched pending user review.
- **Project opt-in register (blocking gate).** New repos — and existing repos on first substantial touch —
  get a blocking setup checklist whose answers are written to that repo's `.claude/project-standards.md`
  and pointed to from `CODING_MEMORY.md`. Covers: rigor tier (prototype vs production), Conditional LGTM,
  which hooks to install, spec folder, sandboxing, `security:scan`, MCP server scoping, eval-in-CI, model
  routing, project `CLAUDE.md`. This exists because an opt-in that is only documented is an opt-in that
  gets forgotten.

Resolved conflicts:
- Existing rules keep their current ALWAYS/NEVER voice (not rewritten to Day 3's "explain the why" style);
  only *new* rules adopt it. The superpowers plugin is third-party and is not modified.
- `AGENTS.md` (papers) == `CLAUDE.md` (this setup); noted once, not duplicated.
- `writing-specs` defers to superpowers' existing `docs/superpowers/specs/` path rather than opening a
  competing `specs/` convention.
- Sandboxing / policy servers / LLM firewalls / SPIFFE identities are infrastructure this setup does NOT
  have. They stay as design guidance inside skills, phrased "when you build X, do Y" — no rule may imply
  the current setup has protections it does not.
- Day 5's "Conditional LGTM" (auto-merge on green) is opt-in per project, never a default, since it sits
  awkwardly with the existing default-branch-safety and tests-pass-before-PR rules.

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
9. Verify the new agent by running it against a synthetic test PDF (no real standards PDFs exist in this repo) before opening a PR. — done
10. Open a PR for the new agent file. — done, see PR Tracking above (PR #3).
11. PR #3 merged to main (commit 16dd601); local main pulled and in sync. `feature/standards-extractor-agent` deleted (local + remote). In a fresh session, confirm `standards-extractor` appears in the Agent tool's available list and run a real end-to-end invocation.
12. Real end-to-end test of `standards-extractor` completed successfully in this fresh session: invoked on `/Users/marksuyat/other docs/ai/resources/vibeCodingrules/Vibe Coding Agent Security and Evaluation_Day_4.pdf` (user's choice, not the Day_3 PDF originally planned), output dir `/Users/marksuyat/other docs/ai/resources/vibeCodingrules/extracted-standards/vibe-coding-agent-security-and-evaluation-day-4/`. Agent read all 41 pages (chunked 20/20/1) and wrote `index.md` + 7 category files (infrastructure-and-sandboxing, data-security, application-security, identity-and-access-management, security-operations-and-red-blue-green-teaming, observability-and-governance, evaluation), inferring the doc's own "7-pillar" architecture as the taxonomy. Output verified on disk and spot-checked for format compliance (H1 + intro + H2 sections + bold imperative bullets) — matches the `rules/*.md` style as designed. Note: that `vibeCodingrules` folder already contained 3 unrelated loose `.md` files from some prior, non-agent process — untouched by this run.
