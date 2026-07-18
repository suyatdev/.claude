# PR Tracking

Full detail for every repo/branch. The index (`CODING_MEMORY.md`) keeps only a one-line pointer per repo.

## suyatdev/.claude

### feature/observability-judge
- branch: feature/observability-judge (MERGED into main via PR #13; branch DELETED 2026-07-17 local + remote)
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR: https://github.com/suyatdev/.claude/pull/13 (MERGED 2026-07-17, merge commit 82d7b9b)
- opened_by session_origin: desktop (VSCode)
- last_push session_origin: desktop (VSCode)
- implementation status: complete; hook suite 17/17. The observability judge: `agents/observability-judge.md`
  + `hooks/judge-guard.sh` (+test, settings.json) + `skills/running-the-observability-judge/` + `rules/gates.md`
  stub + `CLAUDE.md` catalog + ADR + verdict store. Built via subagent-driven development (per-task reviews +
  Opus whole-branch review; 2 security fixes to command detection, 2 Important final-review fixes). Opened with
  `JUDGE_EXEMPT` (bootstrap self-gate — the judge's own introducing PR can't carry a committed verdict matching
  its tip; this circularity recurs only for `~/.claude` self-PRs, not when judging other repos).
- detail: coding-memory/branches/observability-judge.md

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

### feature/new-project-memory-scaffold (DELETED 2026-07-15)
- PR #6: https://github.com/suyatdev/.claude/pull/6 (MERGED 2026-07-14) — CODING_MEMORY scaffold + bootstrap prompt.
- PR #7: https://github.com/suyatdev/.claude/pull/7 (MERGED 2026-07-15) — rules-to-skills restructure design spec + memory checkpoint.
- PR #8: https://github.com/suyatdev/.claude/pull/8 (MERGED 2026-07-15) — reconciliation: local port registry, Hard Model Gate, Session Freshness Checkpoint, settings.json tweaks, .gitignore cleanup.
- implementation status: all 3 PRs merged; 2 trailing commits pushed after PR #8 merged were
  cherry-picked onto `feature/rules-to-skills-restructure` and landed via PR #9 instead. Branch
  (local + remote) deleted 2026-07-15, fully superseded. See coding-memory/branches/new-project-memory-scaffold.md.

### feature/rules-to-skills-restructure (DELETED 2026-07-15)
- PR #9: https://github.com/suyatdev/.claude/pull/9 (MERGED 2026-07-15, fast-forward — merged
  locally to `main` at the user's request rather than via GitHub review) — the rules-to-skills
  restructure: 7 always-loaded rule files → rules/core-conduct.md + rules/gates.md + 5 new skills
  + hooks/git-guard.sh. Always-on content 4,030 → 1,151 words (~71% reduction).
- opened_by session_origin: desktop (VSCode)
- last_push session_origin: desktop (VSCode)
- implementation status: all 12 plan tasks complete via superpowers:subagent-driven-development,
  each with an independent task-reviewer pass, plus a final whole-branch review (Opus). Task 11's
  review caught and fixed real gaps across 3 review rounds; final review found 2 Minor items, both
  fixed. Merged to main, branch (local + remote) deleted. See
  coding-memory/branches/rules-to-skills-restructure.md for the full log.

### PR #14 — feature/memory-rag-index (memsearch)
- repo: suyatdev/.claude · remote: origin (git@github.com:suyatdev/.claude.git)
- PR: https://github.com/suyatdev/.claude/pull/14 · status: MERGED 2026-07-18T16:57Z (merge commit 7015369)
- opened_by session_origin: desktop (VSCode) · last push: desktop (VSCode)
- branch (local + remote) deleted post-merge.
- judge verdict: implementation, risk=low confidence=high, head 6f2d4e3, outcome=clean (backfilled 2026-07-18).
- detail: coding-memory/branches/memory-rag-index.md

### feature/verifying-subagent-commits (MERGED 2026-07-18)
- repo: suyatdev/.claude · remote: origin (git@github.com:suyatdev/.claude.git)
- PR: https://github.com/suyatdev/.claude/pull/15 · status: MERGED 2026-07-18T17:41Z (merge commit 417e8e7)
- opened_by session_origin: desktop (VSCode) · last push: desktop (VSCode)
- branch (local + remote) deleted post-merge.
- origin: a parallel session's commit (`00705b7`, `feat(skills): add verifying-subagent-commits
  gate` — CLAUDE.md + rules/gates.md + skills/verifying-subagent-commits/SKILL.md) had landed
  directly on local `main` with no PR. A later session preserved it on this branch, rebased onto
  current main, then picked it up: added a missing "not for X" description boundary clause, then
  trimmed the resulting description from ~488→~348 chars per judge feedback (verified against the
  repo's other 15 skill descriptions, 275–414 char range). No ADR written — this skill is
  explicitly not hook-enforced, unlike ADR-0001's judge-guard.sh; closer precedent is the no-ADR
  feature/diagramming-skill (PR #12).
- judge verdict: implementation, risk=low confidence=high, head 367da77, outcome=clean (backfilled 2026-07-18).

### feature/compliance-judge (MERGED 2026-07-18)
- repo: suyatdev/.claude · remote: origin (git@github.com:suyatdev/.claude.git)
- PR: https://github.com/suyatdev/.claude/pull/16 · status: MERGED 2026-07-18T22:15Z (merge
  commit 4c2abec). Created and merged outside the authoring session (user/parallel), after the
  passing implementation verdict @ 85d8982.
- opened_by session_origin: desktop (VSCode) · last push: desktop (VSCode)
- branch (local + remote) deleted post-merge.
- scope: compliance judge — agent + running-the-compliance-judge skill + gates stub + catalog +
  store; golden eval 12/12 + HEAD spot-check; loop dry-run (convergence + escalation); ADR 0003.
- post-merge live-verify (fresh session, 2026-07-18): real `subagent_type: compliance-judge`
  dispatch on the golden-pass fixture wrote writeup + JSONL to the real store — confirmed, test
  artifacts removed. Bonus signals: the judge flagged a deliberate caller-context mismatch as a
  non-blocking note and treated fixture instruction-text as data.
- judge verdict: implementation, risk=low confidence=high, head 85d8982, outcome=clean (backfilled 2026-07-18).
- detail: coding-memory/branches/compliance-judge.md
