---
phase: implementation
model_tier: low
branch: feat/memory-system-split
---

# Split live memory from archived memory

Planned on `main` @ `ecdc223`, session 16 (2026-08-06); revised session 17 after compliance judge
round 1 returned `fail` (5 violations, all addressed). Model-switch checkpoints 1 and 2: **asked and
answered** — see task 1.

Full spec, decisions, design, contracts and Gherkin scenarios: **`memory-system-split.spec.md`** —
read on demand only, never at session start (decision 6's pair shape, executed by task 5). The
`## Tasks` list below mirrors that file's task list by identity (the leading text before each
task's em dash); this file carries the terse form, the spec half carries the same tasks at full
completion-note detail.

## Tasks

Model per task follows the checkpoint-2 answer (2026-08-06): **Sonnet 5 throughout, Opus 5 for
task 4 only.**

- [x] 1 — Model-switch checkpoints — checkpoint 1 (entering planning) is moot: planning ran on
      Opus 5. Checkpoint 2 asked and answered 2026-08-06.
- [x] 11 — Exclude `*.spec.md` from the `docs/features/*.md` glob in `phase-guard.sh`; extend
      `phase-guard.test.sh` accordingly. *(Sonnet 5)*
- [x] 2 — Write `hooks/handoff/slim-session-start.sh` + tests; register at SessionStart. *(Sonnet 5)*
- [x] 3 — Rewrite `managing-session-memory` §CODING_MEMORY.md and §Restore for the new roles.
      *(Sonnet 5)*
- [x] 4 — Write `hooks/feature-sync-guard.sh` + tests; register at PreToolUse Bash. **Opus 5.**
- [x] 12 — Add a registration assertion to `slim-session-start` and `feature-sync-guard` test
      files. *(Sonnet 5)*
- [x] 5 — Split **this file** into the pair shape (decision 7). The other 8 feature files are not
      migrated, now or later. *(Sonnet 5)* — done: this file plus `memory-system-split.spec.md`.
- [ ] 6 — ADR: supersedes ADR 0006 rows 1 and 15; records the decision-6 departure from
      one-canonical-file **and** decision 7's permanent mixed-shape repo. *(Sonnet 5)*
- [ ] 7 — Rewrite `preparing-pull-requests`:12 (append-to-archive, not inherit-context). *(Sonnet 5)*
- [ ] 8 — Update `rules/gates.md` one-canonical-file stub for the pair shape (the MAY, decision 8).
      *(Sonnet 5)*
- [ ] 9 — Observability judge (implementation stage), then PR. *(Sonnet 5)*
- [ ] 10 — **Phase 2** memsearch work — separate branch, after Phase 1 merges.

Each completed task's full rationale, gotchas, and mutation-check detail live in
`memory-system-split.spec.md`'s mirrored `## Tasks` section — this file intentionally does not
repeat them.
