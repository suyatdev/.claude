# Observability verdict — session pane-split policy (architecting)

- **Stage:** architecting (design read — advisory, does not gate a PR)
- **Repo:** `.claude` · **Branch:** `feat/pane-split-policy` · **HEAD:** `14727b961a447f14b652a3152d56a5404e88f557`
- **Design doc:** `docs/superpowers/specs/2026-07-22-pane-split-policy-design.md`
- **Provenance:** `coding-memory/brainstorms/2026-07-22-pane-split-policy.md` (4/4 Q&A, all user-answered)
- **Verdict timestamp (UTC):** 2026-07-23T02:42:54Z

## What was changed (plain English)

A design (no code yet) for letting the user decide, per session, how heavyweight helper agents
get placed: run them all **inline** (in-process), or split them into **panes** with a max count —
and when you'd exceed that max, open a new **tab inside** an existing pane instead of blocking or
silently going inline. The prompt fires lazily the first time a "real work" agent would spawn.
Read-only helpers (`Explore`, `Plan`, search) are never governed. It flips today's rule from an
**include-list** ("redirect these named agents") to an **exclude-list** ("govern everything except
read-only"), which pulls plan implementers under hook control for the first time.

## Does it do what you wanted?

Yes, and honestly. The literal ask ("a hook that asks at session start") isn't buildable — hooks
can't hold an interactive conversation — and the design says so out loud, then splits the job into
hook-as-trigger + `AskUserQuestion` + a per-session state file. I verified every claim it makes
about the existing machinery (the include-list guard, the dispatcher's `state/runs/` + cooldown +
session-id triple, the adapter contract) against the real code: they all match. The overflow-to-tabs
model was the user's own idea, and both notable trade-offs were explicitly surfaced and confirmed.

## What could go wrong / what I'm unsure about

- **It reverses a deliberate prior decision.** Today `redirect-agents.conf` *deliberately* leaves
  plan implementers out ("substantial is a judgment call the skill owns"), and the always-on gate
  stub says "plan implementers are skill-routed." The exclude-list flip makes both of those stale
  and governs plan implementers by hook. It's user-confirmed and every path still degrades to
  in-process, so it isn't silent — but it changes the behavior of a shipped, hook-enforced system.
- **The fake-binary test trap has bitten this repo twice already** (ADR 0008: cmux behaved
  differently live than the fake binary, and *all tests stayed green*). The new `open_tab` and
  live-pane-count logic will again be tested against fake binaries. The design's mitigation — probe
  the real cmux tab primitive first and record it as a fixture before trusting the adapter — is
  exactly the right answer, but the residual masking risk is real and lands at implementation.
- **"Count live panes" is a genuinely new mechanism.** The dispatcher today has no explicit
  "pane is finished" marker it reads; the design infers liveness from `state/runs/`. It's flagged
  as assumption #1 with a degrade path, which is the right posture for a design, but it's the least
  proven piece.
- **No ADR is named for the governance flip.** Changing include→exclude on a shipped system is
  exactly what this repo writes ADRs for (cf. ADR 0007). The doc-touch list names the skill and the
  gate stub but not a `docs/decisions/` entry.

## What I'd double-check before merging

1. Plan to **correct** (not just append to) the gate stub's now-false "plan implementers are
   skill-routed" line, and keep the always-on edit to a single clause.
2. **Write an ADR** for the include→exclude governance flip before or with implementation.
3. Treat the **live cmux tab-primitive probe** as a hard gate before the adapter code is trusted —
   record the probe output as a fixture, same as `cmux-layout-probe.sh`.
4. Prove the **liveness predicate** against a real multi-pane session, not just the fake binary; if
   shaky, fall back to overflow-to-inline (the design's own degrade).
5. Confirm the open question the spec leans "yes" on: should `inline` also suppress the two judges'
   existing always-on pane redirect?

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Verbatim intent captured; unbuildable literal ask honestly reframed; all Q&A user-answered. |
| execution | pass | No code (design stage); claims verified against real guard/dispatcher/adapters. Liveness predicate is the one unproven mechanism, correctly flagged. |
| trajectory | pass | Every decision has a rationale + rejected alternatives; probe-first discipline learned from real prior failures (ADR 0008). Sound, not lucky. |
| regression | concern | Flips governance model of a shipped system; pulls plan implementers from skill-routed to hook-governed, reversing a deliberate stance. Surfaced + confirmed + degrades never-blocks, but genuine adjacent-behavior change. |
| context_budget | pass | On-demand skill (64 lines) + one always-on gate stub. Stub carries a now-stale claim that must be corrected, not appended. Keep edit to a clause. |
| traceability | pass | Brainstorm provenance doc + full spec + verbatim intent + flagged assumptions w/ degrade paths + acceptance scenarios. Highly explainable. |
| success_masking | pass | No unbounded/expensive loop (overflow is bounded, degrades). Confronts the fake-binary masking risk head-on with a live probe fixture — the exact mitigation ADR 0008 established. Residual masking is inherent and carried forward, not papered over. |
| intent_drift | pass | No new deps (explicit); scope disciplined; two-phase framed as sequencing not a cut; open questions deferred to planning, not silently decided. |
| checkpoint | pass | Spec + brainstorm + memory committed on a feature branch, not main. Additive with clear file boundaries; two-phase gives a clean intermediate revert point. |
| audit_trail | concern | Governance-model flip is ADR-worthy (cf. ADR 0007) but no `docs/decisions/` entry is named in the doc-touch list. Provenance otherwise strong. |

## Concerns (short)

- Governance-model flip (include→exclude) of a shipped, hook-enforced system; reverses the deliberate "plan implementers are skill-routed" stance. User-confirmed, degrades never-blocks, but a real adjacent-behavior change — implementation must also correct the stale gate-stub claim.
- No ADR named for the governance flip; repo convention (ADR 0007 precedent) says a direction-pivoting change to a shipped system earns one.
- Standing fake-binary masking risk: `open_tab` + live-pane-count will be fake-binary-tested; ADR 0008 documents this exact trap biting twice. Live cmux probe-as-fixture must be a hard gate before trusting the adapter.
- Liveness predicate for "concurrent panes" is a new mechanism with no existing completion-marker read; least-proven piece, correctly flagged with an overflow-to-inline degrade.
