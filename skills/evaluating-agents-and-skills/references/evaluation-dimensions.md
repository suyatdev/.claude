# The Evaluation Dimensions in Full

> Reference for `evaluating-agents-and-skills`. Everything below is guidance for an evaluation system **being built** — "when you build the harness, do this." None of it exists in this configuration: no eval harness, no golden datasets, no CI gates, no canary deployment, no span tracing. Read it as a specification to implement, never as an inventory of measurement you already have.

---

## Foundational Assumptions

Three assumptions have to be abandoned before any of the dimensions below can be scored honestly. Each one is something traditional testing gets to take for granted and agent evaluation does not.

**There is no upfront specification.** Vibe coding starts with a sentence, not a spec. Treat the *session prefix* — the user's first one or two messages — as the closest thing to a specification that exists, and derive acceptance criteria from it automatically. Do not build an evaluation method that assumes a rigid, pre-written test case is waiting somewhere; in the sessions you most need to score, it isn't.

**The user cannot validate the output.** A non-technical user cannot review hundreds of lines of generated code line by line, and an experienced engineer cannot do it in real time either. Whatever the interface implies, user review is not the safety net. Evaluation exists to close that gap, so any design that quietly routes the hard judgment back to the user has not solved the problem — it has renamed it.

**Turns are not independent.** Each turn modifies real files, and bad early decisions compound: a wrong abstraction chosen in turn two is still being extended in turn eleven. Evaluation must cover the full arc of a session against the living codebase's conventions, dependencies, and history, not just whether one turn considered in isolation was correct.

---

## The Seven Dimensions

Score every session against all seven. They fail independently, and a session can be excellent on several while being unshippable on one.

### 1. Intent Satisfaction

Did the agent build what the user *meant*, not merely what they literally said? This is the dimension the user ultimately judges the agent on, and it is the one no test suite can see. A change that satisfies every stated word of the request and misses its point is a failure, and the user will experience it as one immediately.

### 2. Functional Correctness

Does the code build, run, and pass its tests? This is the floor, not the ceiling — and it is gameable. Tests can be deleted or mocked to turn a red build green without anything being fixed, and an agent under pressure to produce a passing suite will find that path. Treat a green build as necessary and nowhere near sufficient, and never as the summary statistic for the session.

### 3. Visual and Behavioural Correctness

For agents producing web apps or UI, judge the *rendered output* — does the page look right and behave right. Code-level metrics miss this dimension entirely: a component can be idiomatic, well-typed, fully covered, and visibly broken in the browser. If the artifact is something a human looks at, the evaluation has to look at it too.

### 4. Cost and Efficiency

Track token spend, wall-clock latency, tool-call count, and iteration count — how many corrections the user issued before the agent converged. A session that reaches the right answer after eleven corrections and a six-figure token bill is a different product from one that reaches it in two turns, even though a pass/fail scorer records both as a pass.

### 5. Code Quality and Convention Matching

Does the code match the project's idioms, patterns, and conventions? A diff that passes every test but violates the codebase's style is still a failure — it is maintenance debt that a human now has to pay, and the whole premise of the agent was that it would not create that debt.

### 6. Trajectory Quality

Did the agent take a sensible reasoning path — reading related files before editing them, sequencing edits coherently, picking the right tool or skill at each step? Correct output produced by bad reasoning is a fragile success and should not be scored as fully passing: the reasoning, not the output, is what gets reused on the next input.

### 7. Self-Repair Behaviour

When a build fails, a test breaks, or the user rejects a change, does the agent recover — or compound the failure? Self-repair is where a mediocre agent becomes an expensive one, looping on a wrong hypothesis and dragging the codebase with it. Score the recovery, not just the initial error.

### Transversal: Safety and Responsible AI

Code vulnerabilities, secrets and credential leakage, license and IP exposure, refusal behaviour, and output content safety are evaluated *alongside* every other dimension — not as a separate, one-off gate at the end. A one-off gate is a single point in a session that produced dozens of writes; safety that is only checked once is safety that was only true once.

---

## How to Evaluate

Each method has a cost and a coverage. Use the cheap ones broadly and the expensive ones as calibration for the cheap ones.

- **Automated functional testing — the cheapest signal.** Run the build, the test suite, and the linters (pytest, jest, eslint, mypy) in CI. This covers functional correctness and the rule-checkable parts of code quality, and nothing else.

- **Static analysis plus adversarial probing — for security and safety.** Static scanners (Snyk, Semgrep) for vulnerabilities, credential-leak detectors (git-secrets) for secrets, and scripted red-team suites that test whether the agent refuses clearly harmful requests. Rules find known-shape problems; probing finds whether the model can be talked out of the rules.

- **LLM-as-judge / agent-as-judge — for rubric-based dimensions.** Score against explicit rubrics for the dimensions rules cannot capture: intent satisfaction, code quality and style, trajectory quality. Calibrate the judge (see the parent skill: swap reference and actual output positions to remove ordering bias, and calibrate against human ratings to 90% agreement) before trusting its numbers.

- **Browser-based testing — for UI-producing agents.** Run multi-step workflows against the deployed app: Playwright scripts for interactivity, plus a multimodal judge scoring the rendered page for layout and styling. The assertions catch broken interactivity; the judge catches the visual and design issues the assertions cannot express. Judge the rendered artifact, not the diff.

- **Trajectory inspection — for internal reasoning dimensions.** Span-level traces that bind each model invocation to the actions that followed are what make trajectory quality and self-repair behaviour observable at all. Without instrumentation, agent failures arrive as inexplicable monolithic events, and the only available diagnosis is a guess. Instrument before attempting to evaluate.

- **Human review — as calibration, not as the primary method.** Reserve qualified human reviewers for intent satisfaction, code quality, and nuanced safety judgment calls. Human review does not scale; its job is to calibrate the automated methods that do, and a program that leans on it as the main line of defence has simply not built an evaluation system.

- **Online evaluation with biased sampling.** Sample live traffic and score it against the same offline rubrics — but bias the sampling toward high-cost sessions, sessions with many corrections, and sessions the user abandoned. A flat 1% sample is a sample of the ordinary, and the failures live in the long tail. Tail-based sampling also keeps storage bounded: evaluate the full trace after completion, drop routine successes, and retain traces containing errors or excessive self-repair loops.

---

## Sessions, Not Turns

**Evaluate session convergence, not turn-level accuracy.** Track whether the user converged on something they actually wanted, how many corrections it took, and whether the session was abandoned. An abandoned session is a far more informative failure than an isolated turn-level error: the turn-level error may have been recovered from, while abandonment means the whole arc failed and the user gave up rather than telling you why.

**Mine user corrections as labeled failure data.** Every "no, not like that" is a free human label on a real failure. Cluster them — embeddings plus clustering is enough — to surface a prioritized list of the agent's systematic failure modes. This is a better failure benchmark than a synthetic one built from scratch, because it is made of failures that actually happened to real users, weighted by how often they happened.

---

## Benchmarks Calibrate, They Do Not Certify

Standardised benchmarks — Vibe Code Bench, SWE-bench Verified, LiveCodeBench, Kaggle standardised agent exams — compare an agent against the field on a shared task set. That is useful for cognitive calibration: it tells you roughly where the agent sits.

It does not certify production readiness. Agents can be overfit to top benchmark scores while still failing on the messy, contradictory realities of real user intent, and a benchmark task set is by construction a set of problems someone already knew how to state clearly. Real intent arrives half-stated and self-contradicting. Do not rely on benchmark performance alone to decide anything ships.
