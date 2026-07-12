# Context and Token Discipline

Context rot, not window size, is the real constraint on agent reliability: accuracy on a fixed task degrades as input grows even when the task does not get harder, and the decay begins before the window fills.

## Active Context Is a Budget

- **Treat active context as a finite, deliberately allocated budget rather than a vessel to fill:** every token placed in front of the model takes attention away from every other token, the same way an infrastructure team treats memory as a scarce resource allocated on purpose.
- **Do not treat a larger context window as a substitute for a smaller active footprint:** a 1M-token window can still show significant degradation at around 50K tokens of active content, so capacity is the wrong metric to optimize. The number worth lowering is what is live now, not what could theoretically fit.

## Static vs. Dynamic Context

- **Treat the boundary between static and dynamic context as a first-class architectural decision:** static context — rule files, global memory, persona — is paid for on every turn regardless of relevance, while dynamic context — skills, tool results, retrieved files — is paid for only when a task calls for it. Too much static wastes tokens and dilutes signal; too little and the agent forgets critical rules.
- **Reach for a skill, not a rule file, when knowledge is task-specific:** loading it on demand keeps the recurring per-turn cost proportional to what the work needs.

## Decouple State from the Prompt

- **Do not use the context window as a database:** pass pointers or URIs through the filesystem instead of accumulating raw execution history inside the prompt, because history that is never read again still costs attention on every turn.
- **Avoid dumping whole repositories or unstructured files into a prompt:** it is financially unviable at scale and produces a low-first-pass-success prompting loop, where each noisy attempt buys another. A dense, high-signal payload beats a sprawling one.

## Route Work to the Right Model Tier

- **Match model tier to task complexity:** frontier models earn their cost on architecture, requirements analysis, and complex implementation; test generation, code review, and CI monitoring are deterministic enough that a cheaper, faster model does them just as well. The largest model on trivial work spends tokens without buying quality.

## Diagnose the Harness Before Blaming the Model

- **Look at the harness first when an agent misbehaves:** most failures trace back to a missing tool, a vague rule, an absent guardrail, or a context window stuffed with noise. Those are configuration failures, and rewording the prompt will not fix them.

See also: rules/session-state-management.md for the model-switch checkpoints that enforce routing.
