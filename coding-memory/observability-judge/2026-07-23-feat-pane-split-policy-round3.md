# Observability verdict — pane-split-policy design (architecting, round 3)

**Date:** 2026-07-23 · **Repo:** .claude · **Branch:** feat/pane-split-policy
**HEAD:** 2815bbadcf9e62168daa4b140e17a39c9d04f4d7 · **Stage:** architecting (advisory — does not gate a PR)
**Spec:** docs/superpowers/specs/2026-07-22-pane-split-policy-design.md
**Round:** 3 — re-scored fresh. Rounds 1 (14727b9) and 2 (9bd9966) both returned risk=low / confidence=high.
Written to a `-round3` path to preserve the round-2 verdict that occupies the default same-day filename
(repo `-round2`/`-round3` collision precedent).

## What changed since round 2

Round 2's only delta was a gherkin reformat. This revision (`2815bba`, "judges keep always-on panes,
outside the session policy (user review)") is a **material design change** driven by two user
review-gate decisions:

1. **`inline` must NOT silence the two judges.** They keep today's always-on pane redirect regardless
   of policy.
2. **`max=N` caps the worker fan-out only.** Judge panes are not counted against N and sit on top.

This turns the earlier **two-lane** model (read-only excluded / everything-else governed) into a
**three-lane** model:

- **Read-only** (`Explore`/`Plan`/search) → always in-process.
- **Judges** (`compliance-judge`, `observability-judge`) → always paned, **outside** the policy (never
  asked, never inline, not counted against N). Preserves their existing hook-enforced behavior.
- **Worker fan-out** (implementers, workers, parallel) → policy-governed (`inline` / `panes max=N`
  with overflow-to-tabs).

Guard: two carve-outs (read-only, judges) evaluated **before** the policy check. `redirect-agents.conf`
is *narrowed* to the judges rather than flipped to an exclude-list. Dispatcher: judges bypass
count/overflow, and each run's lane must now be tagged so judge runs are excluded from the worker
count (folded into flagged assumption 1, with a degrade path). Acceptance scenarios, the testing
matrix, and open-questions were all updated; the one open review question is resolved.

## What this design proposes (plain English)

The pane system decides which sub-agents get pushed into real terminal panes. This revision keeps a
narrow always-paned list for the two governance judges, adds a small always-in-process list for
read-only helpers, and routes everything else (the "worker fan-out": implementers, workers, parallel
spawns) through a per-session choice you make the first time a worker would spawn: run workers
**inline**, or use **up to N panes** and open the overflow as extra **tabs** inside the panes you
already have. Crucially, choosing `inline` only quiets the workers — the two judges still get their
own panes, and those panes don't eat into your N. Nothing ever blocks or vanishes: any failure
(no terminal, adapter can't tab, parse error) quietly falls back to in-process, exactly like today.

## Does it do what was wanted?

Yes — and the two review decisions made it *more* correct, not just different. Sweeping the judges
into "everything-else governed" (the old two-lane framing) had a latent bug: `inline` would have
silenced the judges' panes, and the judges are the very thing `hooks/judge-guard.sh` gates a PR on.
Splitting the judges into their own always-paned lane **preserves that hook-enforced governance
invariant**. So the third lane isn't an accreting special-case — it maps to a real distinction
(governance infrastructure vs. worker fan-out) and it fixes a real problem. The user's stated need is
met: worker placement is user-controlled; judge placement stays fixed. The four design-time unknowns
(pane liveness, cmux tab primitive, overflow selection, session-id survival across `/compact`) remain
flagged as assumptions with named fallbacks. Reasoning, not luck.

## What could go wrong / what I'm unsure about

- **The plan-implementer routing change persists (regression = concern, unchanged).** Decision 2 still
  moves plan implementers from *skill-routed judgment* (today's deliberate stance) to *policy-governed*.
  The user confirmed this and it degrades-never-blocks, so it isn't a landmine — but it is a genuine
  change to how a shipped system routes. The always-on gate stub still reads "plan implementers are
  skill-routed"; that clause is now **stale** and must be **corrected in place**, not appended.
  (Good news specific to the three-lane model: the stub's other clause, "the two judges are
  hook-enforced," stays **true** — so the stub edit is *narrower* than a pure include→exclude flip
  would have forced.)
- **Still no ADR named for a governance-model change (audit_trail = concern, reinforced).** The
  doc-touch list names only `dispatching-pane-agents` + `rules/gates.md`. The design now *explicitly*
  says "this is not a clean single include→exclude flip" — a narrowed-include lane + a new in-process
  exclusion + a fall-through policy is a change to the **governance model** of a shipped, hook-enforced
  system. Repo convention (ADR 0007, "pane-orchestration supersedes judge-terminal-enforcement") says
  that earns an ADR. It should be on the doc list.
- **Assumption 1 now carries two unproven jobs (watch at implementation).** It must both (a) derive
  live worker-pane count from `state/runs/` and (b) **tag each run's lane** so judge runs are excluded
  from that count. Both feed the same number that decides pane-vs-tab. It's correctly flagged with a
  degrade (conservative count / overflow-inline), and the lane tag is cheap deterministic logic (the
  dispatcher knows `subagent_type` at dispatch), so it's low masking risk — but it is the
  least-proven piece and now does double duty.
- **Test the judge-not-counted scenario against real state, not faked liveness (success_masking
  watch).** Scenario "A judge pane is not counted against the worker max" is the acceptance test for
  the user's specific new decision. It depends on both the liveness predicate and the lane tag. If it's
  validated only through fake-binary/faked-liveness fixtures, a green test can exercise the arithmetic
  while never touching the real `state/runs/` derivation — the ADR 0008 masking pattern. Build it on
  real run-dir fixtures. The standing fake-binary risk on the new `open_tab` verb is separately, and
  correctly, mitigated by the mandated live cmux probe recorded as a fixture.

## What I'd double-check before building

1. Add an ADR to the doc-touch list capturing the three-lane governance model (why judges are a lane
   apart, why `inline` doesn't silence them, why they're uncounted — and what it supersedes).
2. Make the `rules/gates.md` stub edit a **correction** of "plan implementers are skill-routed"
   (→ policy-governed), leaving the still-true "the two judges are hook-enforced" clause intact.
3. Prove the `state/runs/` liveness predicate **and** the worker/judge lane tag early (Phase 1), on
   real run-dir fixtures — the judge-not-counted scenario rides on both.
4. Keep the live cmux `open_tab` probe a blocking precondition before the cmux adapter is coded; land
   the recorded probe fixture with it.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | The two review decisions sharpen intent: workers governed, judges preserved. Built what was meant. |
| execution | pass | Design stage, no code — every path degrades; testing matrix updated to cover judge-under-inline/panes/no-policy and judge-not-counted. |
| trajectory | pass | Three-lane split is principled, not accreting: it maps to governance-vs-worker and fixes a latent "inline silences the judges" bug. Sound reasoning, absorbed the review cleanly. |
| regression | concern | Plan implementers still move skill-routed → policy-governed on a shipped system; stale gate-stub clause must be corrected in place. Judge lane specifically avoids a regression (preserves always-on judge panes). |
| context_budget | pass | Touches one on-demand skill + one always-on gate stub. Three-lane description is marginally longer, but the judge clause stays true, so stub churn is smaller than a pure flip. No always-on bloat if corrected in place. |
| traceability | pass | "Not a clean flip" nuance documented; assumption 1 updated for the lane tag; open review question resolved and struck through with its resolution recorded. |
| success_masking | pass | Fake-binary risk named + mitigated (live cmux probe fixture). Lane tag/liveness count is deterministic and unit-testable on real run-dir fixtures; judge-not-counted scenario must use real state, not faked liveness. |
| intent_drift | pass | Judge lane is not scope creep — it preserves a hook-enforced invariant and is exactly the user's review choice. No unauthorized deps; two-phase note framed as sequencing. |
| checkpoint | pass | Additive, reversible; extends existing state/degrade machinery; `redirect-agents.conf` content barely changes (already only the two judges). Clean revert point. |
| audit_trail | concern | Now an explicit governance-model change ("not a clean flip") to a shipped hook-enforced system, still with no ADR named in the doc-touch list (ADR 0007 precedent). |

## Concerns (short)

- Plan implementers still move skill-routed → policy-governed on a shipped system; user-confirmed and degrades-never-blocks, but a real routing change, and the always-on gate stub's "plan implementers are skill-routed" clause is now stale and must be corrected in place (its "judges are hook-enforced" clause stays true under the three-lane model).
- Still no ADR named in the doc-touch list, now for an explicit governance-model change ("not a clean include→exclude flip"); repo convention (ADR 0007 precedent) says a direction-pivoting change to a shipped hook-enforced system earns one.
- Assumption 1 now does double duty — derive live worker count from state/runs/ AND tag each run's lane so judge runs are excluded; both feed the pane-vs-tab number. Correctly flagged with a conservative-count / overflow-inline degrade; least-proven piece.
- Judge-not-counted acceptance scenario must be tested on real run-dir fixtures, not faked liveness, or a green test masks the state derivation (ADR 0008 pattern). Separate open_tab fake-binary risk correctly mitigated by the mandated live cmux probe fixture.
- The three-lane revision is a net correctness improvement over the two-lane framing: splitting the judges into their own always-paned lane preserves the judge-guard governance invariant that inline would otherwise have silenced.

**risk=low confidence=high**
