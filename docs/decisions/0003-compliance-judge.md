# ADR 0003 — Compliance Judge

**Status:** Accepted (2026-07-18)

## Context
Before implementation, a spec was checked twice — the brainstorm's self-review (the same model
checking its own work, against no rule set) and the observability judge's architecting read
(explicitly advisory) — but nothing verified a finished spec against the rules this setup
actually enforces (`rules/core-conduct.md`, `writing-specs`, the security invariants).
Non-compliant specs reached `superpowers:writing-plans`, and the rules only bit at diff/PR
time — the expensive place to discover a design-level violation.

## Decision
Add a compliance judge: a separate stateless subagent (`agents/compliance-judge.md`) that judges
ONE finished spec against the **live rule files** (never a baked rubric — single source of
truth) and writes a blocking pass/fail verdict with per-rule citations to its own store
(`coding-memory/compliance-judge/`, JSONL + per-spec markdown, dated-by-first-round with a
date-anchored append glob). It dispatches **in parallel** with the observability judge's
architecting read at spec-done — deliberately a sibling, NOT an extension of that judge (one
agent, one purpose; the shipped judge stays untouched; extending it was weighed and rejected as
rubric bloat plus advisory/blocking semantics tangled in one agent). The skill
`running-the-compliance-judge` drives the loop: the main agent revises (the judge never edits),
re-judges with the prior round's violations passed for exact id reuse, escalates on
same-id-two-consecutive-rounds or a 3-round cap, and records user waivers attributed and never
silent. Procedure-gated via a `rules/gates.md` stub; a `spec-guard` hook is deliberately
deferred until the gate is observed being skipped — unlike ADR-0001's `judge-guard.sh`, there is
no single script-decidable command to intercept at spec-done.

## Consequences
- The user always reviews a spec that has already passed compliance; persistent violations
  reach them as explicit escalations.
- Any spec edit invalidates the verdict (`spec_blob_sha` freshness) — the judge re-runs before
  `superpowers:writing-plans` proceeds; loop re-entry restarts at round 1 with waived ids
  re-passed.
- Verdicts accumulate an `outcome` field (backfilled clean/rework/bug) for calibration, like
  the sibling store.
- Two judges now run at spec-done (compliance blocking, observability advisory); rubrics and
  stores stay disjoint.
- Enforcement is procedural only; if the gate is skipped in practice, the recorded next step is
  the deferred `spec-guard` hook.
