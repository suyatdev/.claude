---
name: designing-agentic-architecture
description: Use when designing or refactoring a multi-agent or agent-plus-tools system — choosing single-agent-with-skills vs. multi-agent, splitting a monolithic agent, routing through an orchestrator, or wiring multi-step agent workflows. Not for authoring an individual skill (see skills/_standards/authoring-skills-and-agents.md) or for MCP server setup (see integrating-mcp).
---

# Designing Agentic Architecture

Most agentic systems are over-architected before they are over-loaded. The questions that actually matter: does this need to be more than one agent at all; if so, where do the boundaries fall; how do the pieces hand work to each other without corrupting each other's context; and when something misbehaves, which part of the harness was missing. This skill covers the shape of the system, not the contents of any one skill or tool.

## Don't Default to Multi-Agent

- **Single-agent-with-skills is the baseline:** many systems built multi-agent by default can be simplified to one general-purpose agent with a skills library, shrinking the operational surface — fewer deployments, fewer evaluation surfaces, less routing complexity, and so fewer things that can break or drift.
- **Multi-agent needs a genuine architectural reason:** reach for it only on real parallelism, real capability or security boundaries (different access, different security postures, different external systems), hierarchical decomposition where the abstraction layers actually differ, adversarial check-and-balance setups, sub-agent intercommunication, or heterogeneous models. Skills do not eliminate the need for multi-agent here — but absent one of these, the extra topology only costs coordination.
- **Scope each sub-agent's skill library:** if you do go multi-agent, give each specialist its own scoped library rather than duplicating the whole library into every agent. A sub-agent does not need skills for domains it will never touch, and carrying them only widens its search space.

## Skills, MCP, and CLAUDE.md Are Not Competitors

- **MCP is reach; a skill is know-how:** MCP connects the agent to an external system — Drive, Salesforce, BigQuery. A skill teaches it how to *think* about a kind of work. They compose: when a skill needs data, it calls a tool, and that tool is usually one an MCP server provides. Treating them as alternatives forces a choice that the architecture never actually poses.
- **`CLAUDE.md` is the always-loaded index; skills load on demand:** keep the conventions file tight and use it as a router into the skills library, rather than duplicating skill content into it. Everything in it is paid for on every turn whether or not it is relevant.

## Symptoms a Monolith Has Hit Its Ceiling

- **Decision quality degrades as tools accumulate:** the next-action search space grows too large, and the agent starts hallucinating parameters and calling the wrong tool. It is the clearest signal, because it worsens with every tool added.
- **Contextual overload:** system instructions, dozens of tool schemas, and conversation history all compete inside one prompt. You cannot tune one domain's logic — say, database queries — without risking confusion in another sharing that prompt, such as UI rendering.
- **A single point of failure:** one bad tool or one badly worded instruction can corrupt the whole agent's reasoning, because there is no boundary for the damage to stop at.

## Specialization as the Scaling Mechanism

- **Partition into purpose-built sub-agents:** give each a focused system prompt and a restricted subset of tools. A smaller tool set means a smaller search space and fewer tool-call errors; a single-domain prompt means less attention dilution.
- **Let an orchestrator route:** the orchestrator dispatches each task to the specialist that owns it, so no sub-agent has to process the full logic tree to find its own slice of it.

## Build vs. Buy

- **Prefer official specialist agents:** for a third-party platform, use the vendor-maintained agent rather than building your own equivalent.
- **Bespoke specialists carry a maintenance tax:** build your own and you now own keeping its prompt logic and tool definitions in sync with every upstream product update and API schema change — indefinitely, on someone else's release schedule.
- **Standardize the wire protocol:** in a distributed ecosystem each specialist may be built on a different framework, language, and transport. A common agent-to-agent protocol beats writing custom integration and error-correction code per specialist.

## Bounded Tools vs. Unbounded Agents

- **A tool is bounded; an agent is not:** a tool or API expects one well-formed request and returns one response. A specialist agent operates in an unbounded problem space where requirements arrive ambiguous, contradictory, or incomplete, and may need multi-turn clarification to complete at all.
- **Don't wrap an agent as a fire-and-forget tool call:** a collaborative agent must be able to pause, request more information, negotiate with the calling orchestrator, and resume without losing conversational state. Forcing that into a tool wrapper is the architectural equivalent of an uncontrolled `GOTO` — control flow leaves the structured context and may never return.
- **Split the layers:** keep the tool layer (MCP) clean, predictable, and strictly structured, and isolate collaborative multi-turn interaction in the agent-to-agent layer. Mixing them means the structured layer inherits the unbounded layer's failure modes.

## Delegation Mode: Conductor vs. Orchestrator

- **Match the mode to the task.** Conductor mode — real-time, keystroke-level — fits exploration, debugging, and unfamiliar codebases, where each change must be understood as it happens. Orchestrator mode — async, goal-level delegation — fits well-defined work: bug fixes, migrations, test generation, features built on established patterns. Defaulting to one mode wastes the other.
- **An orchestrator routes; it doesn't do the domain work itself.** Keep domain depth in the specialists it dispatches to, not in the orchestrator's own reasoning.
- **Give agents success criteria, not step-by-step instructions**, and let them iterate — the same reasoning as "bounded tools vs. unbounded agents" above: an agent needs room to reach the goal its own way, not a script to execute literally.

## DAG Orchestration, Not Prompt Chaining

- **Naive chaining compounds errors:** a hallucination in an early stage is carried faithfully into every stage after it, and nothing in the chain is positioned to catch it. Use a directed acyclic graph for multi-step or multi-skill workflows instead.
- **Decouple state from the prompt:** routing state in a DAG should not depend on execution history accumulating inside the prompt — that makes correctness a function of how much history still fits in the window.
- **Pass schema references, not raw outputs:** hand off between nodes via structured schema references on a file message bus, rather than piping one node's raw LLM output into the next node's prompt.
- **Draw the graph, don't just describe it:** a DAG that exists only as prose forces every reader to rebuild the node-and-edge shape in their head, and mis-wired routing is exactly what hides in that gap. Render it as a Mermaid `flowchart` in the design doc — see `diagramming-technical-docs`.
- **Abstract the payload away from the text input:** keeping data out of the model's text input protects its attention, prevents context-window bloat, and preserves effective capacity for the reasoning you want.

## Node Roles in the Graph

- **Generator:** converts user intent into structured artifacts — the entry point where ambiguity becomes something downstream nodes can validate.
- **Reviewer & Gate:** a deterministic gate that blocks execution when validation fails. Deterministic is the operative word — the gate is the part of the graph that cannot be talked out of its answer.
- **Pipeline:** orchestrates the linear paths inside the broader DAG, for the stretches where the work genuinely is sequential.
- **Inversion & Recovery:** forces the agent to clarify its assumptions before executing, surfacing ambiguity while it is still cheap rather than after artifacts are built on top of it.
- **Domain Context Wrapper:** a reference node that teaches domain conventions, so specialist knowledge is a node in the graph rather than a paragraph glued onto every prompt.

## Capability Profiles

- **Package the execution state, not just the tools:** a Capability Profile is a modular, swappable, version-controlled bundle of active skills and tool access, system instructions and operational guardrails, automated workflows and sub-agent topologies, and LLM parameters such as model choice and temperature. Versioning the whole bundle is what makes a persona reproducible rather than hand-assembled once.
- **Tear down fully before loading the next:** unload the previous profile's system instructions and flush stale variables before swapping in the new one. A partial teardown leaks state between execution states — the new persona inherits instructions it was never meant to have, and the failure then looks like a model problem rather than the packaging problem it is.

## Reduce Context Debt

- **Capitalized imperatives don't buy determinism:** bloating prompts and skill descriptions with shouted rules to force deterministic behavior at runtime does not work. Models learn to ignore them exactly as a human learns to ignore a wall of unreadable warning text — so the shouting costs tokens and buys nothing.
- **Shift intelligence left:** rather than hoping the model interprets a complex rule correctly at runtime, distill the subjective judgment into the skill and push deterministic logic out of the prompt into standard, testable scripts. Logic in a script can be unit-tested; logic in a prompt can only be hoped at.
- **Write software, not rules:** wherever an invalid action can be made structurally impossible, make it impossible instead of instructing against it. A constraint the system enforces cannot be forgotten, misread, or argued with.

## Diagnose the Harness, Not the Model

- **The harness is the system:** the model is only the reasoning engine. The harness is everything around it — instructions and rule files, tools, sandboxes and execution environments, orchestration logic, guardrails and hooks, and observability. These are the six components to deliberately build into a system you are designing; treat each as absent until you have actually built it.
- **Most failures are configuration failures:** when an agent misbehaves, examine the harness before blaming the model. The cause usually turns out to be a missing tool, a vague rule, an absent guardrail, or a context window stuffed with noise.
- **Hooks are where unforgettable rules live:** enforce hard constraints deterministically at lifecycle points — before a tool call, after a file edit, before a commit — for the rules the agent should never forget but reliably does.
- **Without observability you cannot see drift:** logs, traces, evaluations, and cost/latency metering are what let you audit why an agent made a specific decision. Uninstrumented, a system is not one you know is working — only one whose failures you cannot see.
- **Configure the harness before the code:** instructions, tool access, and architectural constraints belong in the requirements and architecture phase. Configure them after implementation and the agent has already been improvising inside a boundary you had not drawn yet.
- **Let the harness drive the test-fix loop:** during testing, orchestration should capture failing test output and route it back to the model for another attempt, rather than making a human relay the error by hand. A loop a human has to close is a loop that stops closing the moment they get busy.

## The Six Types of Context

Design what the agent can see, not just what it can do. Omitting any one of these is a recurring source of agent failure — and each fails differently, so a missing one is rarely diagnosed as missing.

- **Instructions** — the agent's role, goals, and operational boundaries.
- **Knowledge** — retrieved documents, architectural diagrams, domain data.
- **Memory** — short-term session logs and long-term persistent state.
- **Examples** — few-shot demonstrations and reference patterns from the codebase.
- **Tools** — precise definitions of the APIs, scripts, and services it can invoke.
- **Guardrails** — hard constraints, formatting rules, safety validations.

These are the six *context* types, and they are a different list from the six *harness* components above: the harness is the machinery around the model, this is what it gets to see.

## Trigger Phrases

Positive — this skill should fire:

- "should this be one agent or several?"
- "our agent has 30 tools and keeps calling the wrong one"
- "how should I orchestrate these sub-agents?"

Negative — this skill should *not* fire:

- "write a SKILL.md for this" → `skills/_standards/authoring-skills-and-agents.md`
- "connect this agent to BigQuery" → `integrating-mcp`
- "review this PR" → `/code-review`
