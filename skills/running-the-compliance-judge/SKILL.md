---
name: running-the-compliance-judge
description: Use when a spec/design doc is finished — after its self-review, before the user reviews it — to dispatch the compliance-judge subagent alongside the observability judge's architecting read, drive the capped auto-revise loop, and escalate persistent violations. Not for judging code diffs (see running-the-observability-judge) or reviewing PRs (see /review).
---

# Running the Compliance Judge

A rule violation caught in a spec costs a paragraph; the same violation caught after
implementation costs the implementation. This skill is the procedure the main agent follows at
spec-done: judge the spec against the live rules, silently fix what a revision can fix, and put
anything persistent in front of the user — so the user always reviews a spec that already
complies, and no violation is ever silently dropped.

## When to run
After a spec/design doc is written and self-reviewed, before the user reviews it — whatever
flow produced the spec. **Freshness:** a verdict is fresh only while its `spec_blob_sha`
matches `git hash-object <spec_path>`. Any later edit — including edits the user requests
during their review — invalidates it; re-run the loop before `superpowers:writing-plans`
proceeds. A re-entry after such an invalidation restarts at round 1; re-pass all previously
waived ids from the spec's prior verdicts so the judge records rather than re-cites them.

## The loop
1. Dispatch BOTH judges in parallel, in one message: `compliance-judge` (blocking) and
   `observability-judge` with `stage: architecting` (advisory, unchanged). Give the compliance
   judge: the spec path, the round number, a short context summary of what is being built, any
   user-waived violation ids, and the base branch.
2. Verdict `pass` → proceed to the user review gate, bundling the observability advisory read
   (if that advisory run failed, say so — an advisory failure never blocks).
3. Verdict `fail` → YOU revise the spec to address each cited violation — the judge never
   edits, and you hold the brainstorm context it cannot see — then re-dispatch both judges at
   round+1 (the spec changed, so the advisory read refreshes too), passing the prior round's
   violations — the judge reuses their exact ids for recurring violations, keeping persistence
   detection sound — along with all waived ids.
4. Escalate to the user — with the judge's citation and what your revision attempted — when
   either:
   - the same violation `id` is cited in two consecutive rounds (it survived the revision that
     tried to fix it — "not being fixed" by definition), or
   - round 3 completes with any violation outstanding (the oscillation tripwire: fixing one
     violation keeps re-introducing another; the cap hands the decision to the user, it never
     drops anything).
   The user either directs a different fix (loop continues) or waives the violation; pass all
   waived ids into every subsequent dispatch so the judge records rather than re-cites them.
5. Nothing is waived silently: every waiver comes from an explicit user decision and is
   recorded and attributed in the verdict.

## Fail closed
If the compliance judge errors or returns malformed output: no verdict exists, none is
fabricated, the spec stays blocked, and the user is told. Same contract as the sibling judge.

## Calibration
Verdicts carry `outcome: null`. Once the spec's implementation lands, backfill
`clean`/`rework`/`bug` in `coding-memory/compliance-judge/verdicts.jsonl` — over time the
ledger shows whether compliance-passed specs actually implement cleanly. Golden-eval fixtures
and procedure: `tests/README.md`.

<!-- Triggers (verified before shipping):
positive: "the spec is finished, run the compliance check", "judge this spec against our rules
before I review it", "I edited the spec during review — re-run the compliance judge"
negative: "judge the implementation before the PR" (running-the-observability-judge), "review
this pull request" (/review), "verify the subagent's commit landed" (verifying-subagent-commits) -->
