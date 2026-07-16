# ADR 0001 — Observability Judge

**Status:** Accepted (2026-07-16)

## Context
The config carried evaluation guidance (`evaluating-agents-and-skills`) and observability
guidance (`securing-agentic-systems`, Pillar 7) but ran neither during real work. There was
no agent applying those rubrics to a change, no plain-language readout, and no record to
calibrate against. No runtime trace instrumentation exists, so a true production observability
judge is not possible here.

## Decision
Add a dev-time observability judge: a subagent that scores each change against both rubrics,
relays a junior-dev summary before a PR, and persists verdicts (JSONL + markdown) under
`coding-memory/observability-judge/`. Enforce it with a Tier-1 PreToolUse hook
(`judge-guard.sh`) that blocks `gh pr create` until a fresh implementation-stage verdict
matches the current repo+branch+HEAD (strict freshness). Invocation is driven by a skill
(`running-the-observability-judge`) and a gate stub; the hook only enforces.

## Consequences
- Every change gets a scored, human-readable verdict before it can become a PR.
- Adding a commit after judging invalidates the verdict (strict) — the judge must run last.
- Verdicts accumulate an `outcome` field (backfilled: clean/rework/bug) enabling margin-of-error
  calibration.
- Scope is dev-time only; live-trace ingestion is explicit future work and the schema does not
  pretend to hold it.
- Escape hatch: `JUDGE_EXEMPT=<reason> gh pr create ...` (logged).
