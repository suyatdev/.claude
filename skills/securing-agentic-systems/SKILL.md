---
name: securing-agentic-systems
description: Use when designing security for a system that runs autonomous agents — sandboxing agent-written code, supply-chain defence, agent identity and least privilege, gating tool calls through a policy server, human approval of high-stakes actions, and agent observability. Not for ordinary application security review of a diff (see /security-review).
---

# Securing Agentic Systems

Security for a system whose code is written, and whose actions are chosen, by a non-deterministic process. The threat model is not "a developer made a mistake" but "an agent was talked into it" — by a poisoned RAG chunk, a forged tool server, a comment in a fetched page. Guardrails that live inside the prompt are advice; the controls below are the ones that hold when the advice fails.

## None of This Exists Here

**Read this before applying anything below.** This configuration has no container sandbox, no policy server, no LLM firewall, no SPIFFE identities, no CMEK, no mTLS, and no OpenTelemetry tracing. Every control in this skill is guidance for a system *being designed* — "when you build X, do Y" — never a description of a protection that is already in place. Treat each one as absent until someone has actually built and verified it. Reading this file changes nothing about what this environment enforces, and mistaking it for a description of existing defences produces false confidence, which is worse than having no document at all.

The always-on companion rule, `rules/zero-trust-and-agent-safety.md`, carries what an agent can enforce unaided. This skill carries the infrastructure that rule cannot build for itself.

## The Seven Pillars

### 1. Infrastructure and Sandboxing

Run agent-generated code inside an ephemeral, network-isolated sandbox — a dedicated container, VM, or kernel-level environment such as gVisor — that fully resets state between runs and blocks raw host access. Never run agent-written scripts alongside the root agent on host infrastructure: a container escape or a merely careless script then reaches the node everything else depends on. Depth: `references/seven-pillars.md`.

### 2. Supply Chain

Pull dependencies only from vetted providers or internal registries, never arbitrary public indexes — this is what guards against *slopsquatting*, where an attacker publishes malware under a name matching a package the model hallucinated. Enforce cryptographic version pinning so a newly published malicious release cannot silently arrive. Gate production on SBOM and signature verification as a mandatory deterministic CI/CD check, not an advisory one. Depth: `references/seven-pillars.md`.

### 3. Data

Encrypt at rest with customer-managed keys and in transit with mTLS. Scope every agent's data access to what the current task requires rather than granting standing access to the whole store. Partition vector stores by tenant, so a payload poisoned by one tenant can never surface in another tenant's similarity search — Cross-Tenant Vector Poisoning turns shared long-term memory into a delivery mechanism. Depth: `references/seven-pillars.md`.

### 4. Application

Treat system instructions, prompt templates, and rule files as sensitive, cryptographically attested artifacts: they are the new de facto source code, and an edit to one is an edit to behaviour. Keep API keys, password validation, and session or permission flags out of client-side code, where dev tools can read and rewrite them. Enable default-deny access controls — row-level security and equivalents — on every generated data store, and verify staging is not exposed publicly; a generated backend's default configuration is not evidence that it is closed. Never trust an MCP or tool-server response by default: a forged or compromised server can pose as legitimate, inject a payload, or demand excessive privileges. Depth: `references/seven-pillars.md`.

### 5. Identity and Access

Give every agent a unique cryptographic identity (e.g. a SPIFFE ID) rather than a shared, long-lived service account. Never let an agent operate under the human's delegated credentials — that is precisely what makes the *Confused Deputy* attack work, where a prompt injection tricks an over-privileged agent into acting on the attacker's behalf with the human's authority. Enforce zero ambient authority, issue just-in-time credentials hyper-restricted to the exact sources the task needs and expiring when it concludes, and apply deny-by-default file-tree allowlists that block secrets, build scripts, and production manifests. Depth: `references/seven-pillars.md`.

### 6. SecOps — Red, Blue, Green

Run continuous automated red-teaming rather than periodic pen tests: inject "adversarial vibes" — roleplay jailbreaks, and malicious instructions hidden in RAG context or forum posts — at the speed the agents themselves move. Baseline expected execution paths with Agent Behavioural Analytics and flag deviations; traditional UEBA is built for deterministic actors and is ineffective against a non-deterministic one. Quarantine a compromised agent *statefully* — revoke its tool access and freeze its ability to act while preserving short-term memory for forensics — rather than killing the container, which can leave connected APIs corrupted mid-transaction. Scan repositories for zero-width Unicode and homoglyphs that hide instructions in plain sight and pass human review unseen. Depth: `references/seven-pillars.md`.

### 7. Observability and Governance

Instrument a unified "vibe trajectory" trace — API calls, tool inputs and outputs, retrievals, latency — so the question "why did the agent do that?" has an answer. A success status code is not proof of safe execution: an HTTP 200 can mask a hallucination loop, and Denial-of-Wallet attacks work by driving infinite expensive API loops that all return cleanly. Track intent drift and treat trust as a degradable asset. Create a version-control checkpoint before any codebase modification, and trip an automated circuit breaker that rolls back when the trust score falls below threshold. Maintain an immutable audit trail tying every action to an agent identity and to the human who approved or deployed it. Depth: `references/seven-pillars.md`.

## The Tool-Call Gate

Every proposed tool call should pass a two-layer policy gate before it reaches an external system: fast deterministic structural rules first, then a semantic layer that inspects what the call actually contains. Structural rules answer "is this tool allowed"; they cannot answer "is *this specific use* of an allowed tool a violation." Full design, including output sanitization and placeholder resolution: `references/policy-server.md`.

## Where the Friction Goes

Put advisory, non-blocking linters in the IDE and unyielding, deterministic enforcement in CI/CD. Hard-blocking in the IDE is both trivially bypassed and expensive: it interrupts legitimate iteration, so developers route around it, and the control ends up protecting nothing while costing everyone. SAST and SCA in the pipeline cannot be argued with, cannot be skipped under deadline, and run against the artifact that is actually about to ship. Friction belongs at the boundary that matters, not at the keystroke.

## Trigger Phrases

Positive — this skill should fire:

- "how do we safely let this agent run code it wrote?"
- "design the permission model for our agent platform"
- "what stops a prompt injection from making our agent exfiltrate data?"

Negative — this skill should *not* fire:

- "review this branch for vulnerabilities" → `/security-review`
- "is my API key in this file?" → `rules/zero-trust-and-agent-safety.md`
- "should this be one agent or three?" → `designing-agentic-architecture`
