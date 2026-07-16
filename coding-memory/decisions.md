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

2026-07-14 update: folding the memory-bootstrap prompt into the existing "Session Startup" bullet
(instead of a new bullet) brought the total to 3,567/3,500 — 67 words over. Still well under the ~50K
active-token context-rot threshold (~9.5%). See coding-memory/branches/new-project-memory-scaffold.md.
If this keeps climbing, the next always-on edit should trim before adding, not just accept more drift.

2026-07-15 update: reconciling uncommitted work from a session that got `/clear`'d before its checkpoint
save added rules/local-port-registry.md (new file, always-on via CLAUDE.md import) plus the Hard Model
Gate and Session Freshness Checkpoint bullets in rules/session-state-management.md. Total is now
4,030/3,500 words — 530 over (~15%), still well under the ~50K-token context-rot threshold but the
largest overshoot yet. Not trimming now: the approved rules-to-skills restructure
(coding-memory/session-log.md, 2026-07-14 entry) replaces this whole always-on budget with a ~1.8K-token
design and is the next task in the queue — trimming this budget piecemeal first would be wasted work.

## Documentation enforcement (decided 2026-07-16)

Broadened the mandatory-documentation criteria and added a mechanical backstop, in three tiers:
(1) `managing-session-memory` now names business-logic changes and direction-pivoting technological
implementations as mandatory save triggers — not just architectural ones — each earning a durable ADR
under `docs/decisions/`; (2) `setting-up-a-new-project` scaffolds `docs/decisions/` + an ADR template so
the home exists before the first decision; (3) `hooks/doc-guard.sh` blocks a substantial source commit
that stages no docs (`Doc-Exempt: <reason>` trailer bypasses) and surfaces uncommitted work before a
`/compact` and at the next session start.

A hook can only enforce the mechanical proxy (source changed without a doc change), never verify the
*reasoning* was written — so this is deliberately not sold as semantic enforcement; the guarantee is the
combination of criteria + durable ADR home + backstop. `/clear` is non-blockable by any hook, so the
next-session-start surfacing is the catch for the slip that actually happened (2026-07-15 reconciliation).
See `coding-memory/branches/documentation-enforcement.md`.
