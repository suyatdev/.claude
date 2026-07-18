# Global Engineering Conventions

These instructions apply to every project. Project-level CLAUDE.md files layer on top of this and take precedence when they conflict.

Where the standards literature says AGENTS.md, this setup uses CLAUDE.md. They are equivalent; the guidance applies unchanged.

@rules/core-conduct.md

@rules/gates.md

# Tip: as this file grows, you can split sections into separate files and
# pull them in with @imports, e.g. @rules/git-workflow.md

@RTK.md

## Skills Catalog

These skills load on demand, not on every turn. Read the one whose trigger matches the work in front of you.

- `writing-specs` — writing a spec an agent will build from: BDD/Gherkin, contracts, pinned versions.
- `diagramming-technical-docs` — embedding rendered Mermaid diagrams (architecture, sequence, state, ER, mindmap) in technical docs, designs, plans, and ADRs.
- `designing-agentic-architecture` — single-agent-with-skills vs. multi-agent, splitting a monolith, orchestrator routing, DAG workflows.
- `integrating-mcp` — connecting to or building an MCP server: transports, trust tiers, scoping, debugging.
- `securing-agentic-systems` — sandboxing, supply chain, agent identity, tool-call policy gating, agent observability.
- `designing-agent-interop` — A2A (Agent Cards, registries, monetization) and A2UI (generative UI).
- `designing-agent-commerce` — UCP ordering and AP2 payment mandates for agents that transact.
- `evaluating-agents-and-skills` — whether an agent, skill, or AI output is actually good enough to ship.
- `running-the-observability-judge` — scoring a change against the evaluation + observability rubrics, relaying a junior-dev summary, and recording a verdict before a PR.
- `running-the-compliance-judge` — judging a finished spec against writing-specs + core-conduct/security rules before the user reviews it: parallel dispatch with the observability judge, capped auto-revise loop, escalation, waivers.
- `setting-up-a-new-project` — the blocking opt-in register for a new repo.
- `managing-session-memory` — restoring/saving CODING_MEMORY.md, and the model-switch/freshness/token-limit gates.
- `preparing-pull-requests` — branch naming, commits, PR descriptions, PR memory tracking.
- `writing-secure-code` — injection/XSS/secrets/IDOR guardrails, prompt sanitization.
- `allocating-local-ports` — checking/updating PORTS.md before a new local port or service.
- `triaging-new-instructions` — classifying a proposed new rule/hook/skill before writing it anywhere.
- `verifying-subagent-commits` — independently confirming a subagent's reported commit actually landed in the right checkout, before trusting it.

When authoring or editing any skill or agent, read skills/_standards/authoring-skills-and-agents.md first.
