# The Seven Pillars in Full

> Reference for `securing-agentic-systems`. Every control below is guidance for a system **being designed** — "when you build X, do Y." None of it is present in this configuration: no sandbox, no registry gating, no CMEK, no SPIFFE, no behavioural analytics, no tracing. Read it as a specification to implement, never as an inventory of protections you already have.

---

## Pillar 1 — Infrastructure and Networking

### Ephemeral Sandboxing

- **Isolate all agent-generated code execution:** run any skill-generated or dynamically written code inside an ephemeral, network-isolated sandbox — a dedicated container, VM, or kernel-level environment such as gVisor. Agent-written scripts never run directly alongside the root agent or on standard host infrastructure; if they do, the blast radius of one bad script is the host.
- **Reset state between runs:** a sandbox must completely reset after each run and block raw host access, so a container-escape attempt or a severely vulnerable script cannot persist across invocations or reach the underlying node.
- **Low-privilege by default:** even with rigorous output filtering, an LLM can generate syntactically valid but logically malicious code. Isolate execution from the primary network and from sensitive file systems, so a destructive command is confined to a disposable instance that can be wiped without consequence.
- **Turn on platform sandboxing where it exists:** if the agent platform ships a terminal-sandboxing or equivalent kernel-level toggle, enable it by default for local use. For a portable team setup, containerize the agent workspace via a custom image built from the official sandbox base and force the CLI to run entirely inside it.

### Egress Governance and Non-Interactive Access

- **Domain allowlisting alone is not a network control:** an allowlist of approved domains cannot stop an indirect prompt injection hidden inside an approved third-party page. The page is on the list; the payload is in the page.
- **Restrict agents to non-interactive internet access:** have agents fetch external information exclusively through offline caches or dedicated, pre-sanitized crawling services rather than live interactive browsing.
- **Govern all outbound paths:** agent-generated data should travel only through authorised, governed pathways — offline caches or explicit internal proxies — so an agent cannot inadvertently exfiltrate data or push unverified code into a live environment.

---

## Pillar 2 — Supply Chain

- **Vetted registries only:** agents pull dependencies exclusively from vetted providers or internal enterprise registries, never directly from arbitrary public package indexes. This is the control that defeats **slopsquatting** — an attacker registers the package name an LLM hallucinated and waits for an agent to install it.
- **Cryptographic version pinning:** pin strictly, so a newly published malicious version cannot be silently pulled into a build that previously resolved to something safe.
- **SBOM and signature verification as a deterministic gate:** the CI/CD pipeline verifies Software Bill of Materials entries and digital signatures before any artifact advances to production (e.g. via Binary Authorization). Mandatory and blocking — an advisory supply-chain check is a supply-chain check that ships the compromised artifact with a warning attached.
- **SBOMs go stale; track the AgBOM too:** a static asset inventory is obsolete the moment an agent dynamically generates logic and pulls in new tools. Maintain a **Runtime Agent Bill of Materials** as a living document — the dynamic inventory of tools, models, and data sources an agent is *actively* using right now — so you know its actual blast radius rather than its blast radius at build time. Flag anomalies in it: an unusual number of external tool calls, an unbounded resource loop.

---

## Pillar 3 — Data

- **Encrypt at rest with Customer-Managed Encryption Keys (CMEK):** secure sensitive context and codebase data with keys you control, rather than provider-managed defaults. The distinction matters at exactly the moment you need to revoke access and cannot.
- **Protect data in transit with mutual TLS (mTLS):** require mTLS for all traffic between agents, tools, and data sources — both ends prove identity, which is what makes a spoofed tool server a detectable event rather than an invisible one.
- **Least privilege on data access:** scope each agent's data access strictly to what the current task requires. Broad standing access to the full context store means every prompt injection is a full-context exfiltration.
- **Tenant partitioning in vector databases:** long-term memory stores, particularly vector DBs, must partition by tenant, so a malicious payload ingested by one tenant can never be retrieved during another tenant's similarity search. This is **Cross-Tenant Vector Poisoning**: the attacker does not need to reach the victim's system, only to reach an index the victim's system searches.

---

## Pillar 4 — Model, Application, and Runtime

### Prompts and Instructions Are Source Code

- **Rule files are the new de facto source code:** treat system instructions, prompt templates, and rule files as highly sensitive, cryptographically attested artifacts — not disposable configuration. They are what the agent executes. An unreviewed edit to a rule file is an unreviewed production change.

### Vulnerabilities in Generated Code

- **Nothing sensitive on the frontend:** generated code must not handle API keys, password validation, or session/permission flags client-side. Route sensitive operations through a secure server, because anything in the browser is readable and manipulable in dev tools.
- **Default-deny on every data store:** whenever a database or admin dashboard is generated, explicitly configure strict default-deny access controls such as row-level security. A generated backend's default configuration is not evidence that it is closed — verify private data and staging environments are not exposed to the public internet.

### MCP Spoofing and Contextual Authorisation

- **Treat every MCP or tool server as a potential spoofing vector:** a forged or compromised server can pose as legitimate, inject payloads, or demand excessive privileges. An agent must not execute commands supplied by such a server without verification.
- **Deploy a runtime LLM firewall:** intercept opportunistic prompt injections arriving through tool/MCP responses before they reach the agent's reasoning loop.
- **Route every tool invocation through a centralised agent gateway:** one governed choke point evaluating Contextual Authorisation — does the requested action actually align with the developer's original intent — to prevent unauthorised lateral movement. See `policy-server.md` for the gate's internals.

### Where the Friction Goes

- **IDE linters are advisory:** implement shift-left security in the IDE as real-time, non-blocking Developer Advisory Linters. Do not hard-block insecure prompts there — it is trivially bypassed, and the friction lands on legitimate iteration, which teaches developers to route around the control entirely.
- **CI/CD enforcement is unyielding:** push all deterministic, non-negotiable enforcement into the pipeline. SAST and SCA scan every generated application for vulnerable dependencies and structural flaws before it reaches production. The pipeline cannot be argued with and cannot be skipped under deadline pressure.

---

## Pillar 5 — Identity and Access Management

### Unique Agentic Identity

- **One cryptographic identity per agent:** give each agent its own identity, such as a SPIFFE ID. Shared, long-lived service identities across agents create an unmanageable internal threat vector — when something acts maliciously, you cannot say which thing it was.
- **Never operate under the human's delegated credentials:** authenticate agents with a dedicated identity explicitly tagged as agentic and distinct from the human's, so permissions stay bound and audit logs stay granular. This is the mitigation for the **Confused Deputy** problem — a prompt injection tricking an over-privileged agent into executing an unauthorised command on the attacker's behalf, using authority the human lent it.

### Zero Ambient Authority and JIT Downscoping

- **Zero ambient authority:** an agent never inherits the developer's full ambient administrative privileges while executing a task.
- **Just-in-time, hyper-restricted credentials:** generate fresh credentials scoped only to the exact data sources the specific script or task requires, rather than inheriting the parent agent's broad permissions, and expire the tokens immediately when the task concludes.
- **Deny-by-default file-tree allowlists:** confine read/write operations to specific project directories, explicitly blocking secrets, build scripts, and production manifests by default.

### High-Stakes Action Approval

- **A bare approve/deny button is not a control:** for actions like modifying production databases, executing financial transfers, or altering IAM configuration, a simple approval gate produces confirmation fatigue — developers blindly authorise code they never understood. This is the **"It Works, Ship It" fallacy**, and it converts a security checkpoint into a formality. Require structured, context-aware elicitation instead.
- **Generate a plain-English "Vibe Diff" before critical tool execution:** have an Evaluator Quorum translate the generated code into a plain-English summary of what will actually happen, and require the developer's explicit cryptographic consent before proceeding. The same idea appears in governance as the **Logic Review**: do not assume generated code is safe merely because it compiles — translate complex generated syntax back into plain language *before* a human approves it. A human cannot meaningfully consent to a diff they did not read and could not have read in the time given.
- **Hardware MFA for critical actions:** mandate a physical multi-factor challenge — touching a hardware security key — before a high-risk operation executes. A physical action is the one thing a prompt injection cannot perform.

---

## Pillar 6 — SecOps: Red, Blue, and Green Teaming

### Repository and Payload Hygiene

- **Scan for invisible payloads:** actively scan codebases for zero-width Unicode characters and homoglyphs, which hide malicious instructions in plain sight and pass straight through human review. A single hidden payload can spread across hundreds of files within minutes once an agent starts replicating it.

### Red Team — the Agent Attacker

- **Continuous virtual red-teaming, not periodic pen tests:** run automated Red-Teaming Agents that proactively inject **adversarial vibes** — sophisticated roleplay jailbreaks, and hidden malicious instructions buried in RAG context or in dummy forum posts pasted into an IDE — to test whether the target agent gets distracted by poisoned context and produces an insecure solution. A quarterly pen test cannot keep pace with a system that rewrites itself daily.

### Blue Team — the Agent Defender

- **Agent Behavioural Analytics (ABA), not traditional UEBA:** User and Entity Behaviour Analytics assumes an entity with stable, learnable habits, which is exactly what a non-deterministic agent is not. Baseline expected *execution paths* with ABA and flag deviations from them.
- **Monitor the Runtime AgBOM continuously:** watch the live inventory of tools, models, and data sources in use, and flag anomalies such as an unusual number of external tool calls or an unbounded resource loop.

### Green Team — the Agent Fixer

- **Quarantine statefully; do not kill the container:** when a compromised agent is detected, revoke its specific tool access and freeze its ability to act while preserving its short-term memory intact for forensics. Abruptly terminating the host container can leave connected APIs in a corrupted, half-committed state — and destroys the evidence you need to understand what happened.
- **Auto-refactor and present fixes in the IDE:** where feasible, have the automated Green Team rewrite the insecure, vibe-coded script to patch the vulnerability and present the fix back to the developer in their editor, rather than requiring them to formulate it manually.

### Integrating the Triad with Small Batch Sizes

- **Restrict agent output to small batch sizes:** constrain output size per iteration, so agents cannot generate massive, unreviewable modifications. Review capacity is the binding constraint on safe velocity; a 4,000-line diff is not reviewed, it is skimmed.
- **Block simultaneous test-and-implementation edits:** use a test-driven loop that prevents an agent from modifying tests and implementation in the same step, so the test remains an objective, unbiased baseline for the Planner, Evaluator, and Executor phases. An agent allowed to edit both can always make the suite pass.

---

## Pillar 7 — Observability and Governance

### Tracing the Vibe Trajectory

- **Unified telemetry:** use a standard framework such as OpenTelemetry to aggregate API calls, tool inputs/outputs, RAG retrievals, and token latency into a single chronological **Vibe Trajectory**, so a security team can answer "why did the agent do that?" — a question that has no answer at all in an uninstrumented system.
- **Pair trajectory logs with centralised content scanning:** explicitly scan the dynamic code snippets and scripts an agent retrieves at runtime, in addition to logging them, binding the agent's reasoning to its physical actions.
- **A success status code is not proof of safe execution:** an HTTP 200 can mask an agent that has quietly cascaded into a hallucination loop. Monitor explicitly for **Denial-of-Wallet (DoW)** attacks, where an adversary triggers infinite, computationally expensive API loops to bankrupt cloud and LLM billing. Every one of those calls returns successfully.
- **Dynamic tail-based sampling:** do not capture 100% of production traces — it overwhelms storage budgets and buys little. Evaluate the full trace *after* completion, then drop routine successes and retain traces containing errors or excessive self-repair loops. Sampling on the head discards the interesting traces at random; sampling on the tail keeps the ones that were interesting.

### Intent Drift and Trust Decay

- **Treat trust as a degradable asset:** flag when an agent's internal chain of thought pursues sub-goals that diverge from the original human request — a request to "optimise the database query" drifting into downloading an unauthorised new library. Drift is gradual and each step looks locally reasonable, which is why it needs to be measured rather than noticed.

### Checkpoints and Circuit Breakers

- **Checkpoint before any codebase modification:** require a version-control checkpoint before an agent executes any change, so it can be rolled back cleanly.
- **Trip an automated circuit breaker on trust-score decay:** if detected instability drives the dynamic Agent Trust Score below a defined threshold, automatically roll back to the last checkpoint, revoke tool access, and freeze execution — without corrupting connected APIs — preserving state for forensic analysis.

### Governance and Compliance

- **Algorithmic Impact Assessments:** high-risk autonomous agents undergo Algorithmic Impact Assessments to satisfy the EU AI Act and manage the legal liabilities of automated decision-making.
- **Prioritise oversight by business impact:** continuously assess and rank which autonomous workflows carry the highest business impact if compromised, and secure those first. Security attention is finite; spreading it evenly across workflows guarantees the important ones are under-defended.
- **Immutable audit trail tied to identity:** every real-world action an agent takes must be attributable back to a specific agent identity *and* to the human who deployed or approved it.
- **Risk-Stratified Attestation:** bind digital signatures to agent outputs, creating a transparent, signed ledger that supports internal governance review and third-party audit.
