---
name: running-the-observability-judge
description: Use after architecting a design and after implementing a change, before opening a PR — invoke the observability-judge subagent to score the change against the evaluation and observability rubrics, relay its junior-dev summary, and record a verdict. Not for production runtime tracing or ordinary unit testing.
---

# Running the Observability Judge

A verdict that only lives in a session is a verdict that never calibrates anything. This skill is
how the main agent runs the `observability-judge` subagent at the two moments that matter and turns
its output into something you can act on and learn from. The judge scores the *development
trajectory* of a change; it cannot see a live production trace, and neither can you here — do not
imply otherwise.

## When to run it
- **After architecting** — once a design/spec exists, run the judge with `stage: architecting` for an
  advisory read on the design. Not gated; surface it and move on.
- **After implementing** — once the change is committed on the feature branch, run the judge with
  `stage: implementation`. This verdict gates the PR.

Run the implementation verdict as the **last step before opening the PR**, after the final commit.
Freshness is strict: any commit added afterward moves HEAD and invalidates the verdict, and
`judge-guard.sh` will block `gh pr create` until you re-run it.

## How to invoke
Dispatch the `observability-judge` subagent (Agent tool, `subagent_type: observability-judge`). In the
prompt, give it: the `stage`, a short **decisions summary** (the key choices and why — this is the
trajectory it scores, and it cannot see your session), the design/spec doc path if one exists, the
project's test command if there is one, and the base branch.

## How to relay the result
The subagent's return value is data, not a user-facing message. Relay its four layman sections to the
user in plain language — *what changed · does it do what you wanted · what could go wrong · what I'd
double-check* — and state the `risk`/`confidence`. The full scored verdict is already persisted under
`coding-memory/observability-judge/`.

## Fail closed
If the subagent errors or returns malformed output, write no verdict and fabricate none — report the
failure to the user. With no verdict the hook keeps the PR blocked, which is correct.

To bypass the gate for a genuinely exempt PR, `judge-guard.sh` honors
`JUDGE_EXEMPT=<reason> gh pr create ...` (logged) — use it sparingly, and only when a verdict
genuinely cannot or should not be produced, not as a routine shortcut.

## Calibration
Verdicts carry `outcome: null`. When a PR's real result is known, backfill it (`clean`/`rework`/`bug`)
in `verdicts.jsonl` so the risk-vs-outcome history shows where the judge needs tightening.

<!-- Triggers (verified before shipping):
positive: "run the observability judge", "score this change before the PR", "judge the design I just wrote"
negative: "set up OpenTelemetry tracing" (no runtime tracing here), "write unit tests for this function"
(that's core-conduct testing), "review this PR on GitHub" (that's /review) -->
