---
name: managing-session-memory
description: Use at the start of every session to restore the active feature file and check its phase before any work, at each phase boundary to run the model-switch gate, and after a major task or before compaction to save memory and write the handoff. Not for writing the PR description itself (see preparing-pull-requests) or routine mid-task edits.
---

# Managing Session Memory

An agent's context resets between sessions. What survives is what was written down — so every procedure here exists to keep that written record trustworthy: accurate about what is done, small enough to read in full, and never the reason a later session repeats work or contradicts a decision.

Two artifacts carry it. The **feature file** (`docs/features/<name>.md`) is the single canonical document for one feature — frontmatter, spec, task checklist. **`CODING_MEMORY.md`** is the cross-feature index that points at them.

Feature-scale work earns a feature file. A typo fix or a one-line config change does not — forcing ceremony onto small work is how the ceremony gets abandoned for the work that needed it.

## The Feature File

Every feature file opens with frontmatter:

```
---
phase: planning | implementation | review
model_tier: high | low
branch: <name or "none">
---
```

**`phase` is the single source of truth for what work is permitted.** It survives session clears, which is the entire point: a cleared session has no memory of what it agreed to, so the permission has to live in the file rather than in the conversation. Read it on every restore **before doing anything else** — acting first and checking after is precisely how a session writes implementation code during planning.

Template: `assets/feature-file-template.md`. If feature-scale work starts and no feature file exists, create one from the template before planning proceeds.

### Phase permissions

| Phase | Permitted | Forbidden |
|---|---|---|
| `planning` | Brainstorming, clarifying questions, writing the spec, building the task checklist | Writing or editing implementation code; creating a branch |
| `implementation` | Executing checklist tasks, subagents, tests, commits | Modifying the spec; adding or removing checklist tasks |
| `review` | Verification, judges, PR preparation, recording results | New feature work; silent spec or checklist edits |

Asked to implement while `phase: planning`, refuse and reply: **"Phase is 'planning' — complete the gate first."** The refusal *is* the mechanism; softening it into "I'll just sketch it out" is the exact failure it exists to prevent.

If during implementation the spec proves wrong or incomplete, **stop.** Note the issue as a bullet under the affected task and announce: **"GATE: Spec change needed — switch back to the high-tier model to revise."** Never work around a wrong spec silently — a silent workaround makes the file and the code disagree, and the file is what the next session trusts.

## The Gate Transition (planning → implementation)

Trigger only when the spec and the checklist are both complete.

1. **Announce:** "GATE: Planning complete. Switch to the lower-tier model with `/model`, then say 'gate confirmed'."
2. **HARD STOP.** Do not create the branch, do not begin any task. "continue", "go ahead", and "yes" are **not** permission — only the literal phrase `gate confirmed` opens the gate. A gate that accepts a paraphrase is a gate that opens on momentum, which is the one thing it was put there to stop.
3. **On confirmation:** update the frontmatter (`phase: implementation`, `model_tier: low`), create the branch, record it under `branch:`, then begin the first unchecked task.

This is also a **mandatory `/clear` point.** After confirmation, instruct the user to clear; the next session restores from the feature file alone. Carrying a full planning conversation into implementation spends the context budget on discussion the file already captured.

## The Model-Switch Checkpoints

Three, one per phase boundary. Each is its own checkpoint — none is satisfied by inference from an earlier answer in the session.

1. **Entering planning** — before planning or brainstorming begins, ask whether to switch tier.
2. **Planning → implementation** — the gate transition above. This is the **[CRITICAL, unskippable]** one: it covers writing any code, creating any branch or PR, and all implementation-adjacent work, including docs-only PRs and "small" housekeeping. It applies mid-session even on an already-warmed-up frontier model.
3. **Implementation → review** — after implementation completes and before verification, judges, or the PR, ask again.

**Routing guidance for the answer itself:** architecture, requirements analysis, and complex initial implementation go to frontier models; test generation, code review, and CI monitoring go to smaller, cheaper, faster ones. The largest model on deterministic, low-complexity work spends tokens without buying quality.

## Documentation Discipline

- **One canonical file per feature.** `docs/features/<name>.md` holds the frontmatter, the spec, and the checklist. Update tasks in place — tick the box, append a one-line completion note. **Never create a separate "progress", "implementation summary", or "state of branch" document.** A second document describing the same work is a second document that can be wrong, and a reader cannot tell which of the two to believe.
- **Git is the record of implementation.** Do not write prose summaries of code changes into the docs; write descriptive commit messages per task instead. (PR descriptions and the plain-language summaries relayed in chat are separate artifacts and are unaffected — see `preparing-pull-requests`.)
- **Record only non-obvious decisions and gotchas**, as 1–3 line bullets under the relevant task.
- **Verification results** go in a short `## Verification` section appended to the feature file: pass/fail per area and open issues only.
- **ADRs still stand for the big three.** A decision that is (a) structural/architectural, (b) affects business logic, or (c) pivots a feature's technological direction earns its own numbered, immutable record under `docs/decisions/` — the options weighed, why this one won, the consequences. Task bullets carry ordinary gotchas; they are the wrong home for a rationale that has to outlive the feature file being trimmed. When the decision has structure or a tradeoff space, embed a rendered Mermaid diagram — `diagramming-technical-docs`.

## CODING_MEMORY.md

The cross-feature index, **≤200 lines**: active feature pointers, repo/PR pointers, next steps. Not a log — history, session write-ups, and decision detail live in the feature file, in git, or in an ADR, and never get inlined back into the index. An index that re-accumulates history is one that stops getting read in full.

Update it immediately after completing a major task, resolving a significant bug, or making a decision in class (a), (b), or (c). "It was a small change" does not exempt a decision that moved the product's behavior or direction.

If a repo has no index and no `docs/features/`, ask before substantive work whether to initialize them. Create only on yes, and don't re-ask in the same session if declined.

## Restore (on "continue")

1. Read the handoff, then the active feature file's **frontmatter and checklist**.
2. Run `git status` and `git log main..HEAD --oneline`.
3. **Verify the frontmatter matches reality before any work:** the branch named in `branch:` exists and matches `git branch --show-current`, and the phase is what the handoff claims. **A mismatch is a stop-and-report, not something to guess at** — a disagreement is evidence that some session ended somewhere unexpected, and guessing which side is right is how work lands on the wrong branch.
4. **Do not read the full spec, the full diff, or any code files** until the current task requires them, and **never load more than the active feature's file at session start.** Loading everything "for context" is what leaves no budget for the actual task. Reach for `CODING_MEMORY.md` only when the handoff does not identify which feature is active.

Also on restore:

- **Uncommitted changes the record doesn't account for** — e.g. a prior session cleared before it could checkpoint — get reconciled before proceeding: verify the content, confirm with the user how to handle it, then commit and log it. Never silently carry it forward, never silently discard it.
- **Resuming in a different environment than the one that started the work:** note the switch explicitly and confirm the branch is up to date before continuing. Local state does not track remote state across environments.
- **Handoff state files are machine-local:** the claude-code-handoff hooks write per-repo state under `.claude/` — `session-state.md`, `context.md`, `current-task.md`, `current-bug.md`, `bug-test-log.md`, `recent-prompts.md`, `tasks.md`, `task-history.md`, `mode`. On first work in a repo, confirm `.gitignore` covers those files specifically, not all of `.claude/`, since committed project settings live there too. They never substitute for the committed record.

## Handoff (pre-clear)

**Max ~1,500 tokens.** It contains only:

- A header naming the current **phase** and **model_tier**, so the next session can cross-check the frontmatter.
- The current task and the exact next step.
- Blocking gotchas.
- File/section pointers.

**Never restate spec or plan content — point to it.** A handoff that re-summarizes the spec is a second copy that will drift from the original, and it spends the budget the next session needs for actual work. When trimming to fit, cut narrative before facts: exact commands run, verbatim results, and user-stated intent cannot be re-derived.

## Session Freshness Checkpoint [ENFORCED]

Save and offer a clear on two triggers: after completing a major task, or after roughly every ~35k tokens of new conversation since the last checkpoint — incremental growth, estimated, not the absolute context total.

In this order: finish the current step cleanly, update the feature file and `CODING_MEMORY.md`, push, **then** prompt the user to clear. Never prompt to clear before the save+push — a `/clear` run mid-checkpoint is a session gone before its state was captured, and the next session inherits an out-of-sync record.

`/handoff` is the user-facing manual checkpoint command; it captures the machine-local session state and complements the save+push, never replaces it.

## Token-Limit Checkpoint

When the token limit is close to being reached, pause and ask whether to keep spending now or stop and resume after the limit refreshes. Don't continue high-token work until they answer.

## Trigger Phrases

Positive — this skill should fire:

- "let's pick up where we left off" (start of a session)
- "planning's done, let's start building"
- "we just finished the big feature, let's checkpoint"

Negative — this skill should *not* fire:

- "write the PR description" → `preparing-pull-requests`
- "what port is this project using?" → `allocating-local-ports`
- "review this diff for bugs" → `/code-review`
