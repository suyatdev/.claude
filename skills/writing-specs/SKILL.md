---
name: writing-specs
description: Use when writing a specification an agent will build from — BDD/Gherkin scenarios, API contracts, database schemas, pinned library versions, and good/bad/edge cases. Not for implementation plans (see superpowers:writing-plans) or for brainstorming an idea from scratch (see superpowers:brainstorming).
---

# Writing Specs

A specification is the architectural north star an agent builds from. Its job is to convert ambiguous human intent into a design precise enough that the agent has nothing left to guess at — and precise enough that a human can find the logic flaws in it before a single line of code exists. This skill covers what belongs in a spec, how to shape it, and where it lives.

## The Spec Is the Source of Truth, Not the Code

- **Code becomes disposable:** a rock-solid spec lets the codebase be regenerated on demand, which inverts the usual value ordering — the spec is the durable artifact and the implementation is the derivative one.
- **Maintain it with production rigor:** because both humans and the agent build from the spec, it earns the same care you would give production code — review, versioning, and updates when reality changes.
- **Drift causes hallucination:** when the spec and the code fall out of sync, the agent starts describing and extending behavior that no longer exists. Keeping them aligned is not tidiness; it is correctness. The same obligation runs down to `README.md` and `CHANGELOG.md` — update them in the change that makes them wrong, not later.
- **Docstrings are the code-level contract:** use Google-style docstrings for Python and JSDoc for TypeScript. A structured docstring lets the agent — and the next human — know what a function does without reading every line of its logic, which is the same bargain the spec makes at the design level.

## Write Scenarios in BDD/Gherkin Form

- **Force State → Action → Outcome:** `Scenario / Given / When / Then` makes the author name the starting state, the trigger, and the expected result. Intent that survives that structure is intent an agent can build without inventing the missing parts.
- **Ambiguity surfaces early:** a requirement you cannot phrase as Given/When/Then is usually a requirement you have not actually decided yet — the format exposes the gap while it is still cheap to close.

## What a Spec Must Contain

- **Requirements, not one-liners:** "make a login page" is a vibe, not a design. Break the feature into concrete requirements the agent can satisfy and you can check.
- **Database schemas and API contracts:** these give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes that other components then fail to match.
- **Diagrams and the required toolchain:** include visual aids plus the specific tools and libraries the implementation must use, so the agent is choosing within your architecture rather than picking its own.
- **Background — the *why*:** explaining the reasoning behind a requirement lets the agent anticipate the follow-on work rather than satisfying the literal ask and stopping there.
- **Good, bad, and edge-case scenarios:** state explicitly what correct looks like, what wrong looks like, and enumerate the edges. Anything you leave implicit, the agent infers — and inference is where the defects come from.

## Pin Exact Versions

- **An unpinned dependency is a time machine:** with no version stated, the agent falls back on its training data and proposes something already outdated, because its knowledge cutoff has passed. Pin the exact version of every library and tool.
- **Verify the agent's suggestions:** double-check any version number the agent proposes against current documentation. It is reporting what it remembers, not what is released.

## Choose Format by Structural Depth

- **Markdown for narrative:** clean Markdown headers are what anchor an LLM's attention best, so prose instructions, background, and scenarios belong there.
- **YAML past three levels of nesting:** for structured configuration or data schemas nested more than three levels deep, deeply nested YAML parses meaningfully more accurately than the equivalent JSON or XML.
- **Mix by structure, not by habit:** pick the format per section based on how structured that section is, rather than defaulting to one format for the whole document. The mix improves both accuracy and token economics.

## Tokenization Is a Hard Constraint

- **Every character costs budget and latency:** whitespace, indentation, and repetitive boilerplate — redundant Given/When/Then blocks being the usual offender in specs — inflate cost directly.
- **Bloat degrades reasoning:** the damage is not only financial. Padding can degrade reasoning quality even under a generous context window, so trimming a spec makes it work better, not just cheaper. See `rules/core-conduct.md`.

## A Human Reviews the Spec Before the Agent Generates Code

- **Catch flaws at the design layer:** a logic error found in a design document costs a paragraph to fix. The same error found after the agent has built thousands of lines on top of it costs all of them.
- **The review gate is the whole point:** the reason a spec is worth writing is that it creates an artifact small enough for a human to actually read end to end. Skipping the read forfeits the benefit.

## Where Specs Live

- **Version control, not chat:** the chat window is for short-lived orchestration ("generate the failing tests for Scenario 3"), not durable design. A spec pasted into a conversation decays with that conversation; a committed spec can be indexed, diffed, and verified against.
- **Defer to `docs/superpowers/specs/`:** `superpowers:brainstorming` already writes specs there, and that is the path this skill uses. Do not open a competing `specs/` convention — two spec locations means the agent indexes one and silently misses the other, which is exactly the fragmentation a spec is supposed to prevent.
- **Reference specs by path:** point the agent at the committed file rather than re-pasting its contents, so a single stored version stays authoritative instead of forking into per-session copies.

## Trigger Phrases

Positive — this skill should fire:

- "write a spec for the payments service"
- "turn this into Gherkin scenarios"
- "what should the API contract for this endpoint be?"

Negative — this skill should *not* fire:

- "write the implementation plan" → `superpowers:writing-plans`
- "help me brainstorm a new feature" → `superpowers:brainstorming`
- "write the tests for this function" → the testing rules in `rules/core-conduct.md`
