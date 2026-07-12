---
name: designing-agent-interop
description: Use when making agents interoperate — exposing or consuming an agent over A2A (Agent Cards, registries, executors, Agent-as-a-Service monetization), or having an agent generate dynamic UI via A2UI. Not for MCP tool integration (see integrating-mcp) or agent payments (see designing-agent-commerce).
---

# Designing Agent Interop

An agent that only its author can call is a private function with extra steps. Interoperability turns it into a service — something another team's orchestrator can discover, evaluate, invoke, and pay for, and something a human can actually see and interact with. Two protocols carry that weight. A2A (Agent-to-Agent) is the horizontal edge: how an agent advertises what it does, how it gets found, how a remote caller reaches it, and how money changes hands. A2UI (Agent-to-UI) is the vertical edge: how an agent that produced something worth *looking at* gets it rendered without handing the frontend executable code it has no business trusting. This skill covers A2A supply side, demand side, and monetization, then the UI surface — the order the decisions arrive in.

## Start With the Agent Card

- **The card comes before the ecosystem:** every agent needs a machine-readable "CV" before it is exposed to anything outside its own codebase. Without one, the only way another system can learn what the agent does is for a human to read the source and write a bespoke integration — which is precisely the coupling A2A exists to dissolve.
- **Three things the card must state:** *Capabilities* — what tasks the agent can actually perform, so a caller can judge fit before invoking. *Security & Compliance* — its data handling policies and permission requirements, so a caller can judge whether it is allowed to send this data at all. *Interaction Schemas* — how other agents should communicate with it over A2A, so the call can be constructed without guesswork. A card missing any one of these leaves the caller to fill the gap by assumption, and assumptions are where integrations break.

## Register for Discovery

- **A card without a registry is still private:** once an agent has an Agent Card, register it in an Agent Registry. Registration is what converts it from a hardwired dependency — reachable only by whoever hardcoded its address — into a discoverable service that callers can find without a prior relationship.
- **Public registry when the expertise is the product:** a public registry (marketplace) is the right home when the goal is to license a specialist agent's expertise to external orchestrators, because reach is the point and the marketplace supplies it.
- **Private registry when the boundary matters:** a private registry is the right home when the goal is to share an internal workflow specialist across departments without compromising security. The agent is still discoverable, but only inside a perimeter you control — which is what makes internal sharing viable at all.

## Exposing an Agent (Supply Side)

- **Three steps, in order:** define the formal Agent Card specification; implement an Agent Executor; establish that executor as an A2A-compliant endpoint. Skipping straight to the endpoint produces something that answers HTTP but says nothing about itself, which no orchestrator can safely use.
- **The executor is a translation layer:** it converts incoming A2A requests and outgoing responses into the specific calls the underlying agentic framework needs — ADK, LangGraph, or bespoke code. Keeping that translation in one named layer is what lets the framework underneath change without every remote caller changing with it; the A2A contract is what you promised, the framework is an implementation detail you did not.

## Consuming a Remote Agent (Demand Side)

- **Direct instantiation for known counterparties:** point-to-point instantiation with a hardcoded endpoint is appropriate for a specific vendor integration or a private agent, where the counterparty is fixed and known in advance. The cost is that the address is now baked in, which is acceptable exactly when the address is not going to change.
- **Registry instantiation for dynamic discovery:** indirect instantiation via an Agent Registry resolves resource names and handles authentication validation, which is what you want when the set of agents is not known at build time. The registry absorbs both the naming indirection and the auth check, so the calling code does not reimplement either.
- **The orchestrator holds intent, not domain depth:** let the orchestrator stay focused on user intent and workflow management, delegating specific domain tasks to remote specialists rather than embedding deep domain knowledge itself. An orchestrator that absorbs domain logic becomes the single thing every domain change has to touch, and the specialists it was supposed to coordinate become decorative.

## Token and Cost Discipline on the A2A Channel

Every message between two deployed agents is billed context. Unlike a human conversation, nothing about an A2A exchange naturally terminates, and nobody is watching it run. Design the channel with a budget, or discover the budget after the invoice.

- **Pass pointers, not payloads:** hand off structured schema references — a URI, an object key, a row id — rather than piping one agent's raw output into the next agent's prompt. This is the file message bus rule from `designing-agentic-architecture` applied to the A2A layer: raw-output chaining inflates every downstream message and compounds a hallucination introduced at an early stage into everything that follows it.
- **Meter the conversation, not just the agent:** track token spend, tool-call count, and turn count per A2A conversation, not only per agent. Cost that is invisible per-message becomes unbounded in aggregate, and an exchange between two agents has no human in the loop to notice it running long.
- **Cap the turns:** set a hard maximum on how many rounds two agents may exchange before the conversation terminates and escalates to a human. Two agents that each politely ask the other for clarification will do so indefinitely — an unbounded multi-turn negotiation has no natural stopping point, which is exactly the property that separates a specialist agent from a bounded tool call.
- **A success status is not proof of a bounded cost:** an exchange that completes without error can still have burned an enormous amount of context getting there. Watch specifically for **Denial-of-Wallet**, where an adversary deliberately triggers infinite, computationally expensive agent-to-agent or API loops to bankrupt cloud and LLM billing. `securing-agentic-systems` (and its `references/seven-pillars.md`) owns the detection and circuit-breaker side of this.
- **Budget the channel at design time:** decide before deploying what a single agent-to-agent conversation is allowed to cost, and instrument that ceiling. This is the same discipline as routing complex reasoning to frontier models and mechanical work to cheap ones — see `rules/context-and-token-discipline.md`.

RTK (see `RTK.md`) is the local instance of this same instinct: a `PreToolUse` hook on `Bash` that filters verbose CLI output before it reaches the model's context. It is a useful mental model — shrink the payload at the boundary — but be clear about the layer. RTK sits between one agent and its local shell. It is not in the A2A path, cannot be "installed" on the channel between deployed agents, and does nothing about inter-agent message cost. The A2A equivalent is not a shell filter; it is the pointer-passing, metering, and turn-capping described above, built into the transport.

## Monetization

- **Use A2A Extensions for commercial logic:** A2A Extensions are the mechanism for advertising, negotiating, and executing optional higher-order functionality such as billing, beyond basic message passing. Building bespoke commercial logic on top of raw A2A messages means inventing a private protocol that no counterparty knows how to speak, which forecloses the interoperability that motivated A2A in the first place.
- **Marketplace listing as an AaaS channel:** listing a specialist agent on a cloud marketplace is an Agent-as-a-Service monetization channel that puts an independent developer in front of an existing enterprise customer base and lets the marketplace handle billing complexity — including hybrid models such as "flat fee with usage." The complexity is real, and it is not the differentiating part of the agent.
- **x402 for permissionless machine-to-machine payment:** where microtransactions should occur without user accounts at all, the x402 (or L402) pattern can be implemented via A2A Extensions: the server returns `HTTP 402 Payment Required` with a machine-readable invoice when a request is unpaid, and the calling agent executes payment autonomously and retries with a cryptographic proof-of-payment token. The point is that the invoice is machine-readable — an account-based flow requires a human to have signed up first, which is a step an autonomous caller cannot take.

## A2UI: Never Ship Executable UI

- **Generated code is an injection surface:** an agent that emits raw HTML/JS for a client to execute is emitting attacker-influenceable code into a trusted rendering context. That is code injection and XSS with uncontrolled side effects, and no amount of prompt hardening makes running arbitrary LLM output safe — the defence has to be structural, not persuasive.
- **Declare intent, don't emit markup:** have the agent declare UI intent in a framework-agnostic declarative format and let a trusted client-side renderer perform it. The same agent output then renders natively on web, mobile, or wearable without the agent knowing or caring what the target platform is, which is only possible because the agent never described *how* to draw anything.
- **A trusted catalog bounds what can be asked for:** the agent may only request components the renderer already trusts — buttons, text fields, cards, charts — and the client assembles the final structure from its own component library. Agent decides arrangement, catalog defines what is available, client renders. That separation of concerns is the thing that makes A2UI safe; without the catalog bound, "declarative" is just a slower way to hand over control.
- **Bring your own production catalog:** the bundled "basic" catalog (18 components, renamed from "standard" between v0.8 and v0.9) exists for prototyping and demos. A production frontend should map its own design-system components to A2UI types instead, so generated interfaces inherit the design system rather than approximating it.

## A2UI: Choose the Generation Pattern

- **Reach for UI only when it earns its place:** use A2UI when interaction or visualization adds value beyond the raw data — comparisons, dashboards. Return plain data or text for a simple factual query, because wrapping a one-line answer in a rendered surface costs tokens and latency to deliver nothing the sentence did not already say.
- **LLM-generated is the default pattern:** let the model generate the A2UI directly when it must own the layout decision and adapt it to varying user intent — "compare these regions" and "show me trends" want different interfaces, and only the model knows which one was asked for.
- **Tool-generated templates are the specialization pattern:** use a fixed, tool-generated A2UI template when the layout is deterministic from the inputs — when every region's dashboard looks the same. No tokens are spent generating UI, and the output is fully predictable, which is worth more than flexibility nobody is using.
- **Bind data, don't interpolate strings:** when a tool generates an A2UI structure, build it with data bindings (path references) rather than string or f-string interpolation of values. The tool stays a plain function whose response the framework converts into an A2UI part — and values that flow through a binding never get a chance to be parsed as structure.

## A2UI: Validate Before Rendering

- **Schema-validate every generated payload:** LLM output is stochastic, so validate all generated A2UI against the catalog's JSON-Schema validator before it reaches the renderer. The validator is the only thing standing between a plausible-looking hallucinated component and a renderer that was promised the payload would be well-formed.
- **Retry with the specific error, bounded:** on a validation failure, feed the exact error back to the model and retry, with a maximum retry count. The specific error is what makes the retry more than a re-roll; the bound is what stops a systematically-wrong model from looping forever.
- **Always have a text fallback:** wrap UI generation in try/except and fall back to a plain text response in production. The renderer must never receive a malformed payload, and a degraded answer the user can read beats a broken surface they cannot.
- **Keep the model's context clean:** limit the LLM's context to its own structured tool response, not the rendered UI output. Feeding the rendered interface back turns the model's attention toward the UI it just produced when it should be reasoning about the next action.

## A2UI: Serve Both Consumers

- **Ship `data` and `ui` side by side:** provide both fields in the agent response so each consumer takes the representation it needs — API and machine clients ignore `ui` and read `data`; human-facing clients render the A2UI message. One response shape then serves both audiences without a second endpoint drifting out of sync with the first.
- **Treat the canvas as two-way:** when A2UI is combined with a persistent canvas or workspace, the UI is a communication medium rather than a one-time render. The agent can update sections in response to further instructions, the user can edit the canvas directly, and both sets of changes reflect in real time — which is what makes the surface a shared workspace instead of a printout.

## Trigger Phrases

Positive — this skill should fire:

- "expose our research agent so other teams' agents can call it"
- "how should the agent render a comparison dashboard?"
- "write the Agent Card for this service"

Negative — this skill should *not* fire:

- "connect the agent to Salesforce" → `integrating-mcp`
- "let the agent buy things" → `designing-agent-commerce`
- "build me a React dashboard" → `frontend-design`
