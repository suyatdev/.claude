# Parallel Agent Guardrails & Multi-Session Architecture

## [CRITICAL] Core Multi-Session Invariants

- MULTIPLE CLAUDE INSTANCES RUN CONCURRENTLY VIA GIT WORKTREES.
- NEVER touch files outside of your explicitly requested feature domain or assigned directory.
- If you encounter a build, compilation, or linting error in a file you did NOT modify, DO NOT try to fix it. Wait 30 seconds and re-run your verification tool - another parallel agent may be modifying it mid-build.

## State & Contract Rules (Avoiding Conflicts)

1. Shared Schema Changes: If your task requires modifying shared models (e.g., prisma.schema, shared interfaces, db migrations, or `types/index.ts`):
   - Check the global git state or `main` branch to ensure no structural drift has occurred.
   - Extend or add new exported interfaces rather than altering existing core properties.
2. Package Dependencies: Do NOT add, remove, or upgrade dependencies via `package.json` / `cargo.toml` / `requirements.txt` independently.
   - Ask the user before modifying shared configuration files.

## Delegation Mode

- **Match the mode to the task.** Conductor mode (real-time, keystroke-level) fits exploration, debugging, unfamiliar codebases, where each change must be understood. Orchestrator mode (async, goal-level delegation) fits well-defined work: bug fixes, migrations, test generation, features on established patterns. Defaulting to one mode wastes the other. An orchestrator routes; keep domain depth in specialists, not the orchestrator.
- **A specialist agent is not a fire-and-forget tool call.** A tool is bounded (one request, one response); an agent works in an unbounded space and may need multi-turn clarification. Wrapping that as a tool is the architectural equivalent of an uncontrolled `GOTO`: control flow leaves the structured context and may never return.
- **Give agents success criteria, not step-by-step instructions;** let them iterate.
