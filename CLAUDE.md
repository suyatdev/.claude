# Global Engineering Conventions

These instructions apply to every project. Project-level CLAUDE.md files layer on top of this and take precedence when they conflict.

Where the standards literature says AGENTS.md, this setup uses CLAUDE.md. They are equivalent; the guidance applies unchanged.

@rules/general-engineering.md

@rules/session-state-management.md

@rules/pr-requests.md

@rules/parallel-agent-guardrails.md

@rules/context-and-token-discipline.md

@rules/zero-trust-and-agent-safety.md

@rules/local-port-registry.md

# Tip: as this file grows, you can split sections into separate files and
# pull them in with @imports, e.g. @rules/git-workflow.md

@RTK.md

## Skills Catalog

These skills load on demand, not on every turn. Read the one whose trigger matches the work in front of you.

- `writing-specs` — writing a spec an agent will build from: BDD/Gherkin, contracts, pinned versions.
- `designing-agentic-architecture` — single-agent-with-skills vs. multi-agent, splitting a monolith, orchestrator routing, DAG workflows.
- `integrating-mcp` — connecting to or building an MCP server: transports, trust tiers, scoping, debugging.
- `securing-agentic-systems` — sandboxing, supply chain, agent identity, tool-call policy gating, agent observability.
- `designing-agent-interop` — A2A (Agent Cards, registries, monetization) and A2UI (generative UI).
- `designing-agent-commerce` — UCP ordering and AP2 payment mandates for agents that transact.
- `evaluating-agents-and-skills` — whether an agent, skill, or AI output is actually good enough to ship.
- `setting-up-a-new-project` — the blocking opt-in register for a new repo.

When authoring or editing any skill or agent, read skills/_standards/authoring-skills-and-agents.md first.
