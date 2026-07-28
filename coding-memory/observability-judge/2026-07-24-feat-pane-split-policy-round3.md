# Observability judge — implementation — feat/pane-split-policy — RUN 3

**ts:** 2026-07-25T00:11:24Z · **repo:** `.claude` · **branch:** `feat/pane-split-policy`
**head_sha:** `2454d1d9c343089fa2c44dd0179b5cc8ae9649f8` · **base:** `main` (merge-base `7854ae3`)
**stage:** implementation (gates the PR) · **risk:** medium · **confidence:** high

Supersedes RUN 1 (`b38aa24`) and RUN 2 (`2418e5b`), both in
`2026-07-24-feat-pane-split-policy.md`. Subject of this run: `9073b2b` (the streak fix) and
`2454d1d` (docs only).

Verified myself, not taken on report: all seven suites re-run on `/bin/bash` 3.2.57
(`34/103/45/81/34/10/9 = **316 passed, 0 failed**` — the controller's claim confirmed exactly);
`shellcheck -x` rc=0; the full `2418e5b..HEAD` diff read; the locked spec blob confirmed still
`cdc777a` (last touched by `2815bba`, unmodified on this branch); **and three independent repros
built against the shipped dispatcher with a fake adapter**, including one counterfactual. The
repros are where this round's findings came from — two written claims about shipped behavior are
falsifiable, and the suite does not cover either.

## What was changed

RUN 2 found that the previous fix could make panes multiply without limit: every time the
dispatcher failed to open a *tab*, it "retired" a pane from its own headcount, which freed a slot,
which made the next worker open a brand-new pane — forever, silently, against an adapter that can
split panes but can't tab.

This round adds a **three-strikes rule**. One failed tab is still treated as "that one pane is
stale" — retire it, run this spawn in-process, carry on. But three *consecutive* failed tabs are
treated as "this adapter can't tab at all," which is a real adapter failure: write the session
cooldown and allow in-process for the rest of the session. Only a *successful tab* resets the
count — deliberately not a successful pane-open, because in the runaway loop a pane-open succeeds
between every pair of tab failures, which would have made the limit unreachable. That last detail
is the subtle half and it is correctly reasoned.

Same commit closed RUN 2's three documentation findings: SKILL.md's degrade-path list (which was
actively wrong about shipped code) is now split per-verb and accurate, ADR 0009 gained a
consequence with the threshold rationale, and `<run-dir>/route` got its first reader-facing
mention. `2454d1d` is a memory checkpoint, no source change.

Analogy: RUN 2's complaint was that a restaurant kept building new tables every time a waiter
failed to add a chair. Now the manager is told to stop after three failed chairs. He does stop
*declaring* it — but he never actually stops building tables, and he sometimes fires a waiter who
was doing nothing wrong. Both of those are below.

## Does it do what was intended?

The headline fix is real and I confirmed it: against a genuinely tab-incapable adapter the cooldown
now **does** arrive (repro: `max=2`, cooldown lands on the 7th dispatch, streak=3). RUN 2's "the
cooldown never arrives" is closed. The three documentation items are closed and I checked SKILL.md
line by line against shipped code — it is now correct.

But two claims written into the durable record do not hold, and I falsified both by repro.

**F1 — "the leak stops dead when the cooldown lands" is false.** The branch log states the
under-trigger cost is "at most `TAB_FAIL_LIMIT-1` = 2 surplus panes, which are visible on screen
and stop dead when the cooldown lands." Repro against the exact adapter the spec names
(opens panes, cannot tab), `max=2`, 10 dispatches:

```
d1 rc=0 realpanes=1   d6  rc=0 realpanes=4
d3 rc=3 realpanes=2   d7  rc=4 realpanes=4 cooldown=YES
d4 rc=0 realpanes=3   d8  rc=0 realpanes=5 cooldown=YES   <-- after the cooldown
d5 rc=3 realpanes=3   d10 rc=0 realpanes=6 cooldown=YES   <-- still growing
```

`max=2` requested, **6 real panes opened**, two of them *after* the cooldown was written. Cause,
confirmed by grep: `hooks/pane-dispatch-guard.sh:105` is the **sole reader** of
`adapter-failed-<sid>`; `panes/dispatch-pane-agent.sh` only ever *writes* it (lines 254, 257) and
never consults it. So the dispatcher does not stop — the *guard* stops routing work to it. The
growth is bounded in the normal flow by a component the ADR does not credit, and is unbounded for
any direct `dispatch` invocation. The branch itself already declares that direct invocation happens
(known-open item 7). So the bound is emergent, not mechanical, and the durable record describes it
as mechanical. That is the same shape of incomplete convergence argument as RUN 1 and RUN 2 — an
unstated assumption, this time "something else stops calling me."

**F2 — "3 tolerates … a cmux restart" is false at N≥3.** Both the code comment
(`dispatch-pane-agent.sh:40-42`) and the branch log claim the threshold of 3 tolerates the benign
multi-stale case, naming a cmux restart. Repro: `max=3`, a healthy adapter that tabs fine into live
surfaces, plus 3 phantom run dirs (a restart — panes gone, markers left, the root cause that is
still open):

```
d1 rc=3 target=surface:GHOST1     d4 rc=0 (opens a pane)
d2 rc=0 (opens a pane)            d5 rc=4 cooldown=YES  "adapter 'cmux' failed 3 consecutive
d3 rc=3 target=surface:GHOST2          open_tab calls — treating it as tab-incapable"
```

A perfectly healthy cmux is declared tab-incapable, the user's explicit `panes max=3` is silently
discarded for the rest of the session, and the stderr line **blames the wrong component**. A full
restart at N=3 produces exactly 3 ghosts and the limit is 3, so this is not a corner — it is the
named case, falsified. This re-opens RUN 1's original finding (stale local state → session-wide
cooldown blaming the adapter) in bounded, rarer form.

**F3 — RUN 2's "cosmetic" NIT 1 is the *cause* of F2, and is no longer cosmetic.** RUN 2 graded
"the round-robin index still advances on a failed `open_tab`" as cosmetic because rotation still
visits every pane. That grading was made *before* the streak existed and was never re-made after.
Counterfactual repro — same restart scenario, index pinned so it does not advance past a failure:

```
d1 rc=3 target=surface:GHOST1     <-- one ghost retired
d3..d6 rc=0 target=surface:REAL1  <-- tabs succeed, streak resets, NO cooldown ever
```

Pinning the index makes the scenario **self-heal completely**. The advancing index is what marches
the selector through every ghost in turn, systematically skipping the healthy panes whose success
would reset the streak. Two changes that were each individually defensible interact; nothing in the
review or the fix's own analysis re-graded the nit after the thing that changed its consequence
landed.

**On the spec-amendment reasoning I was asked to check rather than accept.** The claim is "no spec
amendment needed: the Gherkin says an adapter that cannot tab writes the cooldown — it still does,
only the timing changes." Partially sound, but it frames a deviation as compliance. The scenario is
written as a single-dispatch Then-clause (spec 242-246): *When an overflow governed worker is
dispatched / Then … / And it writes the session cooldown flag*. At HEAD the 1st and 2nd such
dispatch do **not** write the flag. What is true is that the outcome arrives within three overflows.
That is a genuine improvement on RUN 2 (where it never arrived) and the spec is correctly left
locked at `cdc777a` — editing it would invalidate two compliance verdicts. The right record is an
explicit *declared timing deviation*, which is nearly what ADR 0009 says; it just calls it
compliance instead of deviation. Worth one sentence, not a blocker.

## What could go wrong / what I'm unsure about

All three findings above share one root: **the deferred exit trap.** Nothing writes `agent-exit`
when a pane dies abnormally, so phantom live runs persist — declared as known-open item 1 and
deferred to a follow-up branch. F2 and F3 are *unreachable* if that root cause is fixed. RUN 2
judged the deferral defensible because retiring made phantoms "self-healing at a cost of one
in-process spawn." At N≥3 that is no longer true — phantoms now deterministically trip a spurious
session-wide cooldown. **The deferral is now carrying more weight than RUN 2 priced it at.** I still
think deferring is the right call at the tail of a 40-commit branch, but it should be deferred
knowingly at the new price, not the old one.

Severity, honestly: every failure here degrades, none blocks or destroys. F1's surplus panes are
visible on screen and mitigated in the normal guard-mediated flow. F2 costs a session its pane
policy and prints a misleading line; state is clearable. Nothing hangs, nothing is lost. Medium.

**What genuinely improved, verified not taken on report.** The test work this round is the strongest
on the branch and I want to be specific, because 316 green is exactly the kind of number that can be
theater and here largely isn't: RED was 101/2 with *only* the two discriminating assertions failing
(the streak-1/streak-2 guards passing vacuously by design, and said so), and **three independent
mutants each killed 2 assertions** — `TAB_FAIL_LIMIT=99`, dropping the tab-success reset, and
resetting on *any* adapter success. That third mutant is precisely the subtle failure mode, and
someone deliberately built a test that dies on it. That is real mutation discipline. SKILL.md is now
accurate per-verb against shipped code, and the exit 3-vs-4 gloss is a genuine readability win.

**The gap it doesn't close:** those 8 new assertions test the *mechanism* (the streak fires at 3),
not the *property* RUN 2 actually raised (the real pane count stays bounded / `max=N` is honored).
No assertion anywhere counts panes against `max`. That is why F1 passed 316 green tests, and it is
the exact shape this dimension exists to catch — for the second round running.

**Smaller / carried, all self-declared and correctly so:** `dispatch-pane-agent.sh` is now 492 lines
against the 400 soft limit (410 → 450 → 492 across three rounds — it grew again with each fix); I
agree with deferring the split to the first move of the next dispatcher task rather than reshuffling
a file every reviewer signed off against, but three consecutive rounds of growth is a trend, not a
one-off. No live end-to-end run of N panes filling and overflowing on real cmux (ADR 0008 trap,
substantially but not fully closed — and F1/F2 are precisely the class a live run would have caught).
Skill description unverified by measurement. `doc-guard.sh` classifying `CLAUDE.md` as source.
Under `inline` the dispatcher still opens a pane if invoked directly. The four uncommitted
`coding-memory/compliance-judge/` files are unrelated and pre-existing across all three runs.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | concern | Improved on RUN 2 — the cooldown now arrives and SKILL.md is accurate. Residual: the locked-spec Gherkin's single-dispatch Then-clause is still literally false for the first two overflows, and ADR 0009 frames that timing deviation as compliance. Spec correctly left locked at `cdc777a`. |
| `execution` | concern | 316/0 verified by me, `shellcheck -x` rc=0, mutation testing genuinely strong. But the headline safety property claimed by the fix is falsifiable by a 10-line repro the suite does not cover (F1), and the code comment's named tolerance case is falsified (F2). |
| `trajectory` | concern | Third consecutive round whose convergence argument is incomplete in the same shape — an unstated assumption ("something else stops calling me"; "3 tolerates a restart"). Mitigating and not faint praise: the argument is *written down* each time, which is the only reason it is checkable at all. The tab-success-only reset is correctly and subtly reasoned. |
| `regression` | concern | New: a spurious session-wide cooldown on a *healthy* adapter at N≥3 stale panes, misattributing to cmux (F2) — re-opens RUN 1's finding in bounded form. RUN 2's NIT 1 re-graded from cosmetic to causal (F3). Carried: plan implementers move skill-routed → policy-governed. |
| `context_budget` | pass | Nothing always-on grew this round. SKILL.md +15 lines and ADR +11 are both on-demand; no new conf, no new deps. |
| `traceability` | concern | Substantially improved: SKILL.md per-verb and correct, `route` documented, exit 3-vs-4 glossed. Residual: the exit-4 message names the adapter as the culprit in the one case where the adapter is fine (F2), and the durable record overstates the bound (F1) — the failure that most needs explaining still explains itself wrongly. |
| `success_masking` | concern | The +8 assertions are real and mutation-verified, but they pin the mechanism, not the property RUN 2 raised: nothing anywhere asserts the pane count stays under `max`. F1 sailed through 316 green tests. Second round running for this dimension. |
| `intent_drift` | pass | Both commits trace directly to RUN 2 findings; `2454d1d` is docs-only. No scope creep, no drive-by edits, no new deps. The 492-line file is declared debt with a named next move. |
| `checkpoint` | pass | Fix isolated in one revertible commit (`9073b2b`), docs checkpoint separate (`2454d1d`), locked spec blob verifiably unchanged. `2454d1d` is a clean revert point; the four uncommitted files are pre-existing and unrelated. |
| `audit_trail` | concern | ADR 0009 amended, and the branch log is exceptionally self-critical — above bar for the branch. But the durable record states a safety bound my repro falsifies (F1) and frames a locked-spec deviation as compliance. A record that overstates a safety property is what this dimension is for. |

## Concerns

1. **F1 (verified by repro).** "The leak stops dead when the cooldown lands" is false. The
   dispatcher never reads `adapter-failed-<sid>` — `hooks/pane-dispatch-guard.sh:105` is its sole
   reader. Against a tab-incapable adapter at `max=2`, 10 dispatches opened 6 real panes, 2 of them
   *after* the cooldown. Growth is bounded in the normal flow only because the guard stops routing
   to the dispatcher; it is unbounded for direct invocation, which the branch declares happens.
   RUN 2's finding is mitigated, not eliminated, and the ADR credits the wrong mechanism.
2. **F2 (verified by repro).** At N≥3 stale panes (a cmux restart — exactly the case the code
   comment claims 3 tolerates), a healthy adapter is declared "tab-incapable": spurious session-wide
   cooldown, `panes max=N` silently discarded, stderr blames cmux. Re-opens RUN 1's original finding
   in bounded form. Untested.
3. **F3 (verified by counterfactual).** RUN 2's "cosmetic" NIT 1 — the round-robin index advancing
   on a failed `open_tab` — is the direct *cause* of F2's determinism. Pinning the index makes the
   same scenario self-heal with zero cooldowns. The nit was graded cosmetic before the streak
   existed and never re-graded after the change that altered its consequence.
4. The locked spec's Gherkin (lines 242-246) is still literally false for the first two overflows;
   ADR 0009 frames this as compliance ("only the timing changes") rather than as a declared
   deviation. Spec correctly left locked at `cdc777a` — the fix is one sentence of framing, not an
   edit.
5. No assertion anywhere counts real panes against `max=N` — the property RUN 2 actually raised.
   The 8 new assertions pin the streak mechanism instead, which is why F1 passes 316 green tests.
6. **ROOT CAUSE still open (declared), now more expensive than RUN 2 priced it.** Nothing writes
   `agent-exit` on abnormal pane death. F2 and F3 both dissolve if it is fixed. RUN 2 called
   phantoms "self-healing"; at N≥3 they are not — they deterministically trip a spurious cooldown.
   Deferral still defensible, but should be taken knowingly at the new price.
7. `panes/dispatch-pane-agent.sh` 410 → 450 → **492** lines across three rounds against a 400 soft
   limit. I agree with deferring the split off the tail of this branch; the three-round growth trend
   is the thing to note, not this round's 42 lines.
8. Carried, unchanged: no live end-to-end run of N panes filling and overflowing on real cmux (F1/F2
   are exactly the class a live run would catch); skill `description` unverified by measurement;
   `doc-guard.sh` classifies `CLAUDE.md` as source; under `inline` the dispatcher still opens a pane
   if invoked directly; plan implementers move to policy-governed routing on a shipped system.
