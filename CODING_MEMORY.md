# CODING_MEMORY

## Session Summary
- Refactored the large CLAUDE.md into a compact root file that imports focused rule files under the rules directory.
- Moved broad engineering guidance into dedicated rule files for maintainability.
- Moved PR-related workflow and PR memory requirements into rules/pr-requests.md.
- Added Automated Testing Guardrails to the engineering rules, including strict contract validation tests and local SAST scan requirements.
- Added a prompt sanitization guardrail requiring sensitive data redaction/masking before AI model calls.
- Added branch continuity rules: branch-scoped implementation memory, resume-from-memory behavior, and main-to-feature branching before brainstorming/implementation.

## Key Decisions And Conventions
- CLAUDE.md now acts as a lightweight entry point with @imports.
- PR process and PR-memory logic are centralized in rules/pr-requests.md.
- Session-state requirements are maintained in a dedicated rules/session-state-management.md file.
- Security workflow now explicitly requires malicious-payload contract tests and a local `security:scan` step before accepting complex refactors.
- Prompting workflow now requires least-data sharing and explicit redaction of secrets/PII before sending model prompts.
- PR workflow now requires branch implementation memory to be committed with the branch/PR and requires brainstorming on feature branches instead of `main`/`master`.

## Exact Next Steps
1. Keep adding future policy updates to focused files under rules/ instead of expanding CLAUDE.md.
2. If PR workflow rules change again, update rules/pr-requests.md first.
3. Keep CODING_MEMORY.md updated after major structural or policy changes.
4. If needed, add/align a real `security:scan` script in active project repositories to match the new guardrail.
5. Apply prompt redaction placeholders consistently in future AI-assisted tasks when sensitive data appears.
6. When resuming any branch, read and update that branch's implementation memory before coding further.
