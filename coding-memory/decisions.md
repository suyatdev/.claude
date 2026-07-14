# Key Decisions And Conventions

Standing policy lives in `rules/*.md` and is not repeated here once it's promoted to a rule. This file
keeps the historical record of decisions and context that led to those rules.

- CLAUDE.md acts as a lightweight entry point with @imports; rule content lives in `rules/*.md`.
- PR process and PR-memory logic are centralized in rules/pr-requests.md.
- Session-state requirements are maintained in a dedicated rules/session-state-management.md file.
- Security workflow requires malicious-payload contract tests and a local `security:scan` step before accepting complex refactors.
- Prompting workflow requires least-data sharing and explicit redaction of secrets/PII before sending model prompts.
- PR workflow requires branch implementation memory to be committed with the branch/PR and requires brainstorming on feature branches instead of `main`/`master`.
- PR memory fields include the session origin that opened the PR and the session origin of the most recent push, enabling cross-environment PR continuity.
- Global subagent `standards-extractor` (tools: Read, Write, Bash, Glob; no model override) lives at `~/.claude/agents/standards-extractor.md`, one Markdown file per inferred rule category plus an `index.md`, styled after existing `rules/*.md` files.

## Always-on rules budget (decided 2026-07-12, do not re-litigate)

`CLAUDE.md` + `rules/*.md` + `RTK.md` sit in the prompt-cached system prefix — billed at full rate once
per session, then at the cached-read rate (~10%) every turn after. At 3,473/3,500 words (~4,600 tokens,
~9% of the ~50K-active-token threshold where context rot begins), the budget is not a real constraint;
growth from 1,952 to 3,473 words costs roughly 200 extra tokens/turn.

Dynamic/conditional loading (deferring some rules via a hook) was considered and rejected: `@import`
resolves before the prompt exists, so a rule can't gate itself, and a hook could only safely defer the
non-safety rules — the ones you can't predict you'll need, which is exactly when you need them present.

2026-07-13 update: the modular-memory change (merged a redundant bullet to partly offset cost) brought
the total to 3,538/3,500 words — 38 words over. Still ~9% of the context-rot threshold, so left as is
rather than cut for the sake of a round number. See coding-memory/branches/modular-coding-memory.md.
