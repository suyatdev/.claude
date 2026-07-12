# Context and Token Discipline

Context rot, not window size, is the real constraint: accuracy on a fixed task degrades as input grows, and the decay begins before the window fills.

## Active Context Is a Budget

- **A budget, not a vessel to fill:** every token in front of the model takes attention away from every other token.
- **A bigger window is not a smaller footprint:** a 1M-token window still degrades badly around 50K tokens of active content, so capacity is the wrong metric to optimize — what is live now is.

## Static vs. Dynamic Context

- **The boundary is an architectural decision:** static context — rule files, global memory, persona — costs tokens every turn regardless of relevance; dynamic context — skills, tool results, retrieved files — only when a task calls for it. Too much static wastes tokens and dilutes signal; too little and the agent forgets critical rules.
- **Task-specific knowledge belongs in a skill, not a rule file:** loading on demand keeps the per-turn cost proportional to what the work needs.

## State Outside the Prompt

- **The context window is not a database:** pass pointers or URIs through the filesystem instead of accumulating execution history in the prompt: history never read again still costs attention every turn.
- **No whole-repo dumps:** feeding entire repositories or unstructured files into a prompt is financially unviable at scale and produces a low-first-pass-success prompting loop, each noisy attempt buying another.

## Model Routing

- **Match model tier to task complexity:** frontier models earn their cost on architecture, requirements analysis, and complex implementation; test generation, code review, and CI monitoring are deterministic enough for a cheaper, faster model. The largest model on trivial work spends tokens without buying quality.

## Diagnose the Harness First

- **Suspect the harness before the model:** most misbehavior traces to a missing tool, a vague rule, an absent guardrail, or a context window stuffed with noise. Those are configuration failures; rewording the prompt will not fix them.

See also: rules/session-state-management.md for the model-switch checkpoints that enforce routing.
