# Compliance-Judge Golden Eval

Fixtures proving the judge cites the RIGHT rules — not just that it fails bad specs.
Run per `evaluating-agents-and-skills`: consistency across repeated runs, not one lucky pass.

## Procedure (orchestrator-run; task subagents lack the Agent tool)
For each fixture, dispatch a `general-purpose` subagent TWICE with this prompt (substitute
`<fixture>`):

> You are running a golden-eval of the compliance-judge agent definition. Read
> `agents/compliance-judge.md` and follow it exactly as if you were that agent, with two
> exceptions: (1) treat `skills/running-the-compliance-judge/tests/out/` as the store root —
> write the markdown and verdicts.jsonl there, never under `coding-memory/`; (2) do not cite
> the spec-file location — fixture placement is intentional. Inputs: spec_path =
> `skills/running-the-compliance-judge/tests/<fixture>`, round = 1, context summary: "A tiny
> internal CLI producing URL-safe slugs for repo scripts; single stated need, no other
> consumers.", waived: none, base branch: main. Return the verdict JSON only.

## Acceptance bar
- `golden-pass.md`: verdict `pass`, zero violations, in 2/2 runs.
- Each seeded fixture: verdict `fail` AND the expected citation (see `expected-citations.md`)
  present, in 2/2 runs.
- On any miss: at most ONE revision of the agent's wording, then a full re-run of ALL
  fixtures. Still missing → STOP and surface to the user; repeated tuning against the same
  fixtures is overfitting, not calibration.

Results live in `golden-results.md` (committed). `out/` is scratch and gitignored.
