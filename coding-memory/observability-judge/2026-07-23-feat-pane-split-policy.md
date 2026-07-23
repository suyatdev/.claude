# Observability verdict — pane-split-policy design (architecting, round 2)

**Date:** 2026-07-23 · **Repo:** .claude · **Branch:** feat/pane-split-policy
**HEAD:** 9bd99665c0d729424364e5503a2757d14eb6865c · **Stage:** architecting (advisory — does not gate a PR)
**Spec:** docs/superpowers/specs/2026-07-22-pane-split-policy-design.md
**Round:** 2 — re-scored fresh. Prior (round 1, 14727b9) returned risk=low / confidence=high.

## What changed since round 1

Exactly one thing: the "Acceptance scenarios" section was reformatted from arrow-prose bullets
into a fenced `gherkin` Feature/Scenario block. I diffed 14727b9..HEAD on the spec — all six
scenarios map 1:1 onto the six prior bullets, wording preserved verbatim. **No design change.** If
anything, this is a small traceability *improvement* (structured BDD per the `writing-specs`
discipline the repo already follows), so no dimension moves in a negative direction.

The design's trajectory is unchanged, so this verdict re-states round 1 unchanged.

## What this design proposes (plain English)

Right now the pane system decides *which* subagents get pushed out into real terminal panes using an
**allow-list** (only listed types are redirected). This design does two things: (1) it flips that to a
**block-list** — everything is pane-governed except read-only helpers (`Explore`/`Plan`/search); and
(2) it lets you choose per session, the first time a worker would spawn, between "run everything
inline" or "use up to N panes, and once N are full, open the overflow as extra tabs inside the panes
you already have." Nothing ever blocks or silently vanishes: if any step can't work (no terminal,
adapter can't tab, parse fails), it quietly falls back to running in-process, exactly like today.

## Does it do what was wanted?

Yes. The user's literal ask ("a hook that asks at session start") isn't buildable — hooks can't ask
interactive questions — and the design says so honestly, then reaches the real intent by a sound
route: the existing guard is the *trigger*, the model does the *asking* via `AskUserQuestion` at first
spawn. The four brainstorm decisions are all present and each is justified. The four things that can't
be known until code time (pane liveness detection, the cmux tab primitive, overflow selection,
session-id survival across `/compact`) are explicitly flagged as assumptions, each with a named
fallback. That is reasoning, not luck.

## What could go wrong / what I'm unsure about

- **A real behavior flip on a shipped system (regression = concern).** Moving from allow-list to
  block-list means **plan implementers become hook-governed**, reversing today's *deliberate*
  "plan implementers are skill-routed" stance. The user confirmed this and it degrades-never-blocks,
  so it's not a landmine — but it is a genuine change to how an existing system decides, not a pure
  addition. The always-on gate stub in `rules/gates.md` still says "plan implementers are
  skill-routed"; that line must be **corrected**, not appended to, or the always-on context will
  carry a claim that is no longer true.
- **No ADR named for the governance flip (audit_trail = concern).** The doc-touch list names only
  `dispatching-pane-agents` + `rules/gates.md`. Repo convention (ADR 0007, "pane-orchestration
  supersedes judge-terminal-enforcement", is the direct precedent) says a direction-pivoting change
  to a shipped system earns an ADR. The flip of the governance model is exactly that. It should be on
  the doc list.
- **Standing fake-binary masking risk (not new, correctly pre-empted).** The new `open_tab` verb and
  live-pane-count logic will again be tested with fake-binary adapters — the same setup that let a
  real cmux quirk slip past green tests on a prior branch (documented as an ADR). The design's
  mitigation is right: **probe the live cmux tab primitive and record it as a fixture before the
  adapter code is trusted.** That must be a hard gate at implementation, not a nice-to-have.
- **The liveness predicate is the least-proven piece.** "Count live panes from `state/runs/`" is a
  new inference — the dispatcher has no explicit completion-marker read today. Correctly flagged as
  assumption 1 with an overflow-to-inline degrade, but it's the part most likely to need rework.

## What I'd double-check before building

1. Add an ADR to the doc-touch list capturing the include→exclude governance flip (why, and what it
   supersedes).
2. Make the `rules/gates.md` pane-dispatch-redirect stub edit a **correction** of the stale
   "plan implementers are skill-routed" line, not an append.
3. Treat the live cmux `open_tab` probe as a blocking precondition before the cmux adapter is coded;
   land the recorded probe fixture with it.
4. Prove the `state/runs/` liveness predicate early (Phase 1), before overflow-to-tabs depends on it.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Reframes an unbuildable literal ask into its real intent, honestly and correctly. |
| execution | pass | Design stage, no code — but every path has a concrete degrade; testing plan is specific. |
| trajectory | pass | Decisions justified; four unknowables flagged as assumptions with fallbacks. Sound, not lucky. |
| regression | concern | Include→exclude flip changes a shipped system's routing; plan implementers move to hook-governed; stale gate-stub claim must be corrected. |
| context_budget | pass | Touches one skill + one gate stub; no always-on bloat if the stub is corrected in place. |
| traceability | pass | Well-documented; assumptions and trade-offs surfaced. Gherkin reformat improves this slightly. |
| success_masking | pass | Fake-binary masking risk named and mitigated (live cmux probe fixture before trusting the adapter). |
| intent_drift | pass | Scope stays on the ask; two-phase suggestion framed as sequencing, not a scope cut; no unauthorized deps. |
| checkpoint | pass | Additive, reversible; extends existing state/degrade machinery; clean revert point. |
| audit_trail | concern | Governance-flip change to a shipped system, but no ADR named in the doc-touch list (ADR 0007 precedent). |

## Concerns (short)

- Include→exclude governance flip reverses the deliberate "plan implementers are skill-routed" stance; user-confirmed and degrades-never-blocks, but a real adjacent-behavior change, and the always-on gate stub's now-stale claim must be corrected in place, not appended.
- No ADR named in the doc-touch list for the governance flip; repo convention (ADR 0007 precedent) says a direction-pivoting change to a shipped system earns one.
- Standing fake-binary masking risk: new open_tab + live-pane-count logic will again be fake-binary-tested (the trap that bit live cmux on a prior branch). Mitigation (probe real cmux tab primitive, record as fixture) is correct and must be a hard gate before the adapter is trusted.
- Liveness predicate for "concurrent panes" is a new mechanism inferred from state/runs/ with no completion-marker read today; least-proven piece, correctly flagged as assumption 1 with an overflow-to-inline degrade.
- Round-2 change is a verbatim gherkin reformat of the acceptance scenarios only; design trajectory unchanged from round 1. Unprovable-at-design-stage items (cmux tab primitive, liveness feasibility) correctly deferred to an implementation-time probe.

**risk=low confidence=high**
