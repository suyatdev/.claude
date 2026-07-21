# ADR 0007 — Pane orchestration supersedes judge-terminal-enforcement

**Status:** Accepted (2026-07-21)

## Context

Two designs, brainstormed one day apart, solved overlapping problems with different
mechanisms. **Judge-terminal-enforcement** (branch `feature/judge-terminal-enforcement`,
design approved 2026-07-20, two-file spec with judge verdicts through round 6, never
implemented) put
both judges in their own terminal sessions via a shared launcher, triggered at *gate
moments* by verify-store-else-spawn+wait hooks on `git commit` (spec files staged) and
`gh pr create`. **Pane orchestration** (spec
`docs/superpowers/specs/2026-07-20-pane-orchestration-design.md`) generalizes the same
pane machinery to all substantial agents — judges *and* plan implementers — plus a 75k
context-handoff pane, triggered at *dispatch time* by a PreToolUse redirect hook. Shipping
both meant two parallel terminal-spawn stacks with overlapping four-terminal adapters.

## Options weighed

1. **Rescope new on old** — resume the nearly-done judge spec, shrink the new design to
   implementers + handoff. Preserves six rounds of judged work; keeps the gate-moment
   always-run guarantee; but ships the judge-only launcher first and the generalization
   second, with the adapter layer split across two artifacts.
2. **Absorb old into new (chosen)** — one unified system under the new spec; the old
   branch retires. Discards the gate-moment trigger model and the judged spec text, but
   keeps its transferable research.
3. **Keep both** — permanent duplication; rejected without much argument.

## Decision

The user chose absorption (2026-07-21). The pane-orchestration spec is the single system.
Absorbed from the superseded spec: the `--agent` headless-invocation research (its
`--bare` flag was later rejected at the new spec's compliance round 1 — on CLI 2.1.216 it
skips hooks/CLAUDE.md and restricts auth to API keys, which would disable the Tier-1
guards in implementer panes and fail OAuth auth on this machine), the
hook-timeouts-fail-open platform fact, the done-sentinel/wait pattern, the four-terminal
detection ladder. Dropped with it: the verify-store-else-spawn+wait gate-moment
enforcement.

## Consequences

- **The always-run guarantee does not improve.** Judges are pane-bound when dispatched,
  but dispatch remains skill-driven, backstopped only by `judge-guard.sh` blocking
  `gh pr create`. The compliance judge still has no deterministic trigger — the exact gap
  judge-terminal-enforcement existed to close. If a skipped compliance run is observed,
  the remedy is the deferred `spec-guard` hook (gates.md), resurrected from the superseded
  spec's §3 — not a reopening of this decision.
- **ADR-0003's deferral stands again**: the "script-decidable spec-done moment" that the
  superseded design claimed to resolve (commit staging `docs/superpowers/specs/*.md`)
  returns to unresolved status.
- **Branch `feature/judge-terminal-enforcement` is retired, not deleted** — ~3,400 lines
  of unmerged judged work; deletion is an explicit user cleanup decision. Its spec remains
  the reference text for anything later resurrections need.
- `CODING_MEMORY.md` item 0b now marks the parked project superseded, pointing here.
