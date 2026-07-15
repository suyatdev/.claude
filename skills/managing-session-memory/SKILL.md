---
name: managing-session-memory
description: Use at the start of every session to restore context from CODING_MEMORY.md, after completing a major task or before context compaction to save it, and before starting planning, implementation, or any code/branch/PR work to run the model-switch gate. Not for writing the PR description itself (see preparing-pull-requests) or routine mid-task edits.
---

# Managing Session Memory

An agent's context resets between sessions; a repo's `CODING_MEMORY.md` is the only thing that survives that reset. Every procedure below exists to keep that file trustworthy — accurate about what's actually done, small enough to read in full every session, and never the reason a later session repeats work or contradicts an earlier decision.

## The CODING_MEMORY.md Index

- **Continuous tracking:** maintain a running summary of progress in `CODING_MEMORY.md` at the repo root.
- **Event-based saves:** update it immediately after completing a major task, resolving a significant bug, or making a structural/architectural decision.
- **Pre-compaction save:** if the conversation is growing long, or before a `/compact`, update it first — compacting with unsaved state is how context gets lost.
- **Structure:** each update concisely covers a session summary, key decisions/conventions, and exact next steps.
- **Keep it an index, ≤200 lines:** active session, repo/PR pointers, next steps only. Move PR history, session logs, decisions, branch logs, and brainstorm write-ups into `coding-memory/<topic>.md` files, linked by path — never inlined back into the index. An index that re-accumulates history is one that stops getting read in full.
- **Plain-language summaries:** session summaries, PR descriptions, and any diff/architecture/error output shown in chat should be major-changes-only, in language a non-engineer or junior developer can follow. Skip routine or local steps; cover only what affects other files, systems, or components.

## Session Startup

- At the start of every session, silently read `CODING_MEMORY.md` to restore context before doing any work.
- If the repo has none, ask — before substantive work — whether to initialize it (index + `coding-memory/` structure). Create it only on yes, and don't re-ask later in the same session if declined.
- Record `session_origin` (`desktop`/`remote`/`browser`), `session_started_at`, and `last_active_branch` under the active session block.
- **Resuming in a different environment than the one that started the work:** read `CODING_MEMORY.md` first, note the `session_origin` switch explicitly, and confirm the branch is up to date before continuing — never assume local state matches remote state across environments.
- **Most-recent session wins:** the session block with the latest `session_started_at` is authoritative. Older in-progress work that conflicts with it defers to the newer one.
- **If the working tree has uncommitted changes memory doesn't account for** — e.g. a prior session was `/clear`'d before it could checkpoint — reconcile before proceeding: verify the content, confirm with the user how to handle it, then commit and log it. Don't silently carry it forward, and don't silently discard it.

## The Model-Switch Gates

Every one of these pauses and asks the user whether to switch model tier before proceeding. None of them are satisfied by inference from an earlier answer in the session — each is its own checkpoint:

- **Pre-session planning check:** if the next task starts in planning mode, ask before planning begins.
- **Per-task planning check:** right before any new task that needs planning, brainstorming, or similar ideation, inform the user and ask.
- **Pre-task implementation check:** right after planning/brainstorming completes and immediately before implementation begins, ask again — a plan being written on one model doesn't answer which model should implement it.
- **Hard Model Gate [CRITICAL, unskippable]:** before writing ANY code, creating ANY branch or PR, or starting ANY implementation-adjacent work — including implementation plans containing code, docs-only PRs, "small" follow-ups, and housekeeping commits — pause and ask. This applies mid-session even when a frontier model is already warmed up on the task: the default assumption is that code-adjacent output does not need a frontier model unless the user says otherwise.

**Model-routing guidance for the answer itself:** route architecture, requirements analysis, and complex initial implementation to frontier models; route test generation, code review, and CI monitoring to smaller, cheaper, faster ones. The largest model on deterministic, low-complexity work spends tokens without buying quality.

## Session Freshness Checkpoint [ENFORCED]

Save memory and offer a session clear on two triggers:

1. After completing any major task (a feature, a significant bugfix, or an architecture/brainstorm/spec/plan milestone).
2. After roughly every ~4K tokens of new conversation since the last save/clear checkpoint — incremental growth since the last checkpoint, not the absolute context total, and an estimate rather than an exact measurement.

On either trigger, in this order: finish the current step cleanly, update `CODING_MEMORY.md` (index + relevant `coding-memory/*.md`) and push, **then** prompt the user to clear the session. Never prompt to clear before the save+push — a `/clear` run mid-checkpoint is a session gone before its state was captured, and the next session inherits an out-of-sync memory file.

## Token-Limit Checkpoint

When the token limit is close to being reached, pause and ask the user whether to continue spending credits now or stop and resume after the limit refreshes. Don't continue high-token work until they answer.

## Trigger Phrases

Positive — this skill should fire:

- "let's pick up where we left off" (start of a session)
- "we just finished the big feature, let's checkpoint"
- "should we switch models before I start implementing this?"

Negative — this skill should *not* fire:

- "write the PR description" → `preparing-pull-requests`
- "what port is this project using?" → `allocating-local-ports`
- "review this diff for bugs" → `/code-review`
