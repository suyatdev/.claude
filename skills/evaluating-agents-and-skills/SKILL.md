---
name: evaluating-agents-and-skills
description: Use when deciding whether an agent, a skill, or AI-generated output is actually good enough to ship — trigger accuracy, output vs. trajectory scoring, eval-driven development, pass^k consistency, and LLM-as-judge calibration. Not for ordinary unit testing of deterministic code (see rules/general-engineering.md).
---

# Evaluating Agents and Skills

An Agent Skill without a test is a hope, not a capability. Benchmarking has found that 19% of skills perform *worse* than no skill at all — they don't add neutral noise, they actively subtract capability. The only way to tell which kind you wrote is to measure it, and measuring generated behaviour needs a different instrument than measuring a function.

This skill supplies the graduation criteria that the Read → Draft → Act ladder in `skills/_standards/authoring-skills-and-agents.md` points at. That file says *what bar* a skill must clear at each tier; this one says *how you find out* whether it cleared it.

## No Eval Harness Exists Here Yet

**Read this before applying anything below.** This configuration has no eval harness, no golden datasets, no CI, no canary or shadow deployment, and no span-level tracing. Everything below is guidance for a system *being built* — "when you build the harness, do this" — never a description of machinery already running. Nothing in this repository currently scores a skill, blocks a merge, or catches a regression. Treat every gate described here as absent until someone has actually built and verified it; a document mistaken for an inventory produces false confidence, which is worse than having no document at all.

## Tests and Evals Are Different Instruments

A test checks that a given input produces a given output, and it is checked by code. An eval checks whether the agent took the right trajectory, chose the right tools, and produced a final response that clears a quality bar — and it is checked by a labelled dataset, a scoring rubric, or an LM judge. Deterministic behaviour needs the first; non-deterministic behaviour needs the second. A practice that skips either mechanism is vibe coding, however sophisticated its prompts are.

Write both *before* generating code, not after. Together they form the contract with the model, and they communicate intent far more precisely than a natural-language prompt can.

## Score the Trajectory, Not Just the Output

Test the final output (what the agent says) and the tool trajectory (what the agent does) separately. Output-only scoring can pass 20–40% more cases than trajectory-aware scoring, because it masks an incorrect sequence of tool calls that happened to arrive at the right answer anyway. Correct output produced by bad reasoning is a fragile success: the reasoning is what will be reused on the next input, and it is already broken. Do not score it as fully passing. A fluent answer that skipped its own verification steps is a more dangerous failure than one with a visible error, because nothing about it looks wrong.

## Match Trajectory Strictness to Authority

Strictness should track blast radius, not taste. Read-only skills may be validated with ANY_ORDER matching (the expected tool calls appear as an unordered subset), because a harmless lookup done out of order is still harmless. Action-allowed skills require IN_ORDER or EXACT matching, because an incorrect tool sequence there can cause irreversible side effects — refunding before validating, deleting before backing up — and "it got there eventually" is no comfort once the write has landed.

## The Four Failure Modes

Cover all four, because they fail independently:

- **Trigger failure** — the wrong skill fires, or the right one doesn't.
- **Execution failure** — it triggers correctly but produces wrong output or errant tool calls.
- **Token-budget failure** — the body crowds the context window and degrades performance on turns that have nothing to do with it.
- **Regression** — a newly added skill overlaps an existing one and breaks routing that used to work.

A skill can pass any three of these and still be a net negative in production.

## Eval Coverage Checklist

A skill counts as "evaluated" only once all four of these hold:

1. **Trigger accuracy** — positive *and* negative cases, target 90%.
2. **Execution correctness** — across a representative range of inputs, not the demo input.
3. **Zero regressions** — no drops anywhere in the existing library suite.
4. **No token-budget degradation** — measured when co-loaded with 5–15 other frequently-active skills.

Failing any single one holds the skill at the draft tier, regardless of how well it performs on the happy path. The happy path is the one case you were already thinking about while writing it, so it is the least informative case you can measure.

## Isolation Is a Trap

Production agents co-load 5 to 15 skills simultaneously. A skill body under 5,000 tokens that works perfectly alone can still cause context rot in company — competing for attention, overlapping another description, or simply consuming budget that a different skill needed. So do not evaluate a skill purely in isolation.

Start with a Single-Skill Sub-Agent pattern (Agent + 1 Skill, compared against a Base Agent) to isolate the skill's own effect and simplify calibration. Then test multi-skill co-loading. When a multi-skill trajectory test fails, separate execution logic from routing: validate the underlying tool code independently, and separately audit the description across multiple model families — a description that only routes on one model is brittle and architecture-locked, and over-engineering it for that model hides the problem instead of fixing it.

## Measure Consistency, Not Single-Run Luck

Use pass^k — success on every one of k repeated runs — rather than pass^1. On tau-bench, GPT-4o scored 61% at pass^1 and dropped below 25% at pass^8. The model did not get worse; the metric got honest. A single-run success tells you the agent *can* do the task, which is a much weaker claim than that it *will*, and production only cares about the second one.

## Evaluation-Driven Development

Write three JSON evaluation cases — input, expected tool calls, expected output format, rubric — *before* drafting the `SKILL.md` body. This forces a clear functional spec upfront and surfaces ambiguities in the description early, while the description is still cheap to change. If you cannot write three cases, the scope is not defined yet, and writing the body will only bury that fact under prose.

## Calibrate the Judge

An LLM judge is an instrument, and an uncalibrated instrument produces confident numbers about nothing. When scoring at scale, swap the positions of the reference and the actual output to eliminate ordering bias, and calibrate the judge against human ratings until it reaches 90% agreement.

Even a calibrated judge is optimistic. Simulation-based evaluations can carry up to 9% optimistic bias, and production performance typically drops 20–30% against offline pass@1 benchmark numbers. So require human review of representative outputs before graduating any skill to action-allowed status — the tier where the optimism gets paid for in irreversible writes.

## Deterministic Pass/Fail Is Insufficient for Generated Behaviour

An agent, or any ML-driven component — classifier, summarizer, retriever — can pass 100 unit tests on its tools and still choose the wrong tool, paraphrase a critical answer, or hallucinate a fact. That error margin is an inherent property of the model, not a defect to be eliminated; the testing strategy has to accommodate it rather than pretend it away.

So replace binary assertions with scored judgments and tolerance bands: a 0–5 LLM-judge score, an "at least as good as baseline" comparison, a trajectory check that tolerates reasonable ordering variance instead of a rigid step-by-step assertion. Gate on a quality threshold dropping below a configurable margin, not on a single assertion flipping. Deterministic tests catch regressions; only evaluation catches behavioural drift, and drift is what a rewritten prompt or an upgraded model actually produces.

## Functional Correctness Is the Floor, Not the Ceiling

A green build proves less than it appears to. Tests can be deleted or mocked to make a red build look green without anything having been fixed, and an agent optimizing for a passing suite will find that shortcut before you do. Builds-runs-passes-tests is the floor of the scoring model, not its summary. `references/evaluation-dimensions.md` carries the full model: intent satisfaction, functional correctness, visual and behavioural correctness, cost and efficiency, code quality and convention matching, trajectory quality, self-repair behaviour, and safety evaluated across all of them.

## The Evaluation Toolkit

- **Eval-as-unit-test in CI** — run on every change, with a failing eval blocking the merge. Required for every skill, on every change.
- **A curated, versioned golden dataset** — representative (input, expected output) pairs, stored alongside the skill directory so they version with it. Required from the draft tier upward; 20+ cases is the draft-tier bar.
- **Adversarial / red-team probing** — at least one rephrasing case and one negative boundary case for every positive trigger, before graduating a skill to action-allowed.
- **Canary / shadow-mode deployment** — before each action-allowed release, run a parallel offline shadow comparison, then monitor a small live canary (e.g. 1% of traffic) for regressions before full rollout.

Wire these into a repeating cycle rather than a one-off gate: evaluate against the suite, cluster the failures by root cause, fix the prompt or tool that caused them, verify against the regression suite, and monitor production for new failure modes. Each pass should compound on the last.

Match the rigor to the stakes, not to habit. A disposable prototype can reasonably stay in vibe-coding mode. Anything acting on real systems earns the full ladder.

## Trigger Phrases

Positive — this skill should fire:

- "is this skill actually working or did I get lucky?"
- "how do I know the agent is good enough to ship?"
- "set up evals for our coding agent"

Negative — this skill should *not* fire:

- "write unit tests for this parser" → `rules/general-engineering.md` testing rules
- "review this diff" → `/code-review`
- "why is this test failing?" → `superpowers:systematic-debugging`
