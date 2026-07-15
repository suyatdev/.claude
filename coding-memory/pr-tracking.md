# PR Tracking

Full detail for every repo/branch. The index (`CODING_MEMORY.md`) keeps only a one-line pointer per repo.

## suyatdev/.claude

### feature/vibe-coding-standards-integration
- branch: feature/vibe-coding-standards-integration (MERGED into main; branch still exists local + remote)
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR: https://github.com/suyatdev/.claude/pull/4 (MERGED 2026-07-12, merge commit 5904702)
- opened_by session_origin: desktop (CLI)
- last_push session_origin: desktop (CLI)
- implementation status: complete and verified. 27 commits. Always-on rules 3,473/3,500 words. 8 skills.
  4 hooks written but NOT installed (settings.json untouched by design).
- detail: coding-memory/branches/vibe-coding-standards-integration.md, coding-memory/brainstorms/2026-07-12-vibecoding-standards-integration.md

### feature/standards-extractor-agent
- branch: feature/standards-extractor-agent (merged into main, deleted locally and on origin)
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR: https://github.com/suyatdev/.claude/pull/3 (merged, commit 16dd601)
- opened_by session_origin: desktop (CLI)
- last_push session_origin: desktop (CLI)
- implementation status: standards-extractor agent + design spec merged to main. Verified against a
  synthetic PDF, then confirmed working end-to-end against real PDFs in a later session.
- detail: coding-memory/branches/standards-extractor-agent.md

### feature/modular-coding-memory
- branch: feature/modular-coding-memory (merged; not yet deleted locally/on origin)
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR: https://github.com/suyatdev/.claude/pull/5 (MERGED 2026-07-14)
- opened_by session_origin: desktop (VSCode)
- last_push session_origin: desktop (VSCode)
- implementation status: complete and merged — see coding-memory/branches/modular-coding-memory.md

### feature/new-project-memory-scaffold
- branch: feature/new-project-memory-scaffold (still open — reused across three PRs so far)
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR #6: https://github.com/suyatdev/.claude/pull/6 (MERGED 2026-07-14) — CODING_MEMORY scaffold + bootstrap prompt.
- PR #7: https://github.com/suyatdev/.claude/pull/7 (MERGED 2026-07-15) — rules-to-skills restructure design spec + memory checkpoint.
- PR #8: https://github.com/suyatdev/.claude/pull/8 (open) — 2026-07-15 reconciliation: local port registry, Hard Model Gate, Session Freshness Checkpoint, settings.json tweaks, .gitignore cleanup. Opened after discovering #6/#7 were already merged and these 5 commits had no open PR.
- opened_by session_origin: desktop (VSCode)
- last_push session_origin: desktop (VSCode)
- implementation status: PR #8 open awaiting review — see coding-memory/branches/new-project-memory-scaffold.md
