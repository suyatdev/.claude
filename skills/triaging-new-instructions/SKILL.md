---
name: triaging-new-instructions
description: Use when the user wants to add a new always/never-do-X rule, a new hook, or a new skill. Classifies the proposal into hook, static rule, gate stub, skill, or reference file, then hands off to the matching authoring path. Not for editing an existing skill's content once its category is already decided (see skills/_standards/authoring-skills-and-agents.md).
---

# Triaging New Instructions

An opt-in or a new rule that only lives in a document is a rule that gets forgotten. This skill is the decision tree that classifies a proposed instruction *before* it gets written anywhere, so it lands in the tier that will actually hold it.

## The Decision Tree

Walk these as guided questions, one at a time, stopping at the first "yes":

1. **Can a script decide it from observable facts** — a command string, the current branch, a file path, staged files? → It's a **hook**. Author it with the `update-config` skill, optionally leaving a one-line explanatory stub in `rules/gates.md` pointing at it.
2. **Must it hold on every turn, or is its applicability unpredictable from task type** — identity, safety invariants, parallel-agent rules? → It's a **static rule**. Add it to `rules/core-conduct.md`.
3. **Is it judgment-based but must never be missed** — a gate? → **Stub it in `rules/gates.md`** (1-2 lines, pointing at the skill that carries the actual procedure), and put the full procedure in a skill — an existing one if it fits, otherwise a new one.
4. **Is it needed only during a specific activity?** → It's a **skill**. First check whether an existing skill should own it instead of a new one — extend rather than duplicate. If the natural description needs an "and" between unrelated capabilities, that's two skills, not one.
5. **Is it rarely-needed reference data** — a registry, a lookup table, a one-off procedure? → A **reference file** that a skill points at. Never preload it into a rule or a skill body.

## Handing Off

Once classified:

- **Hook** → `update-config` writes the script and wires it into `settings.json`.
- **New or extended skill** → `skill-creator` or `superpowers:writing-skills`, after loading `skills/_standards/authoring-skills-and-agents.md` — naming, description, and folder-anatomy standards live there, not here.
- **Static rule or gate stub** → edit `rules/core-conduct.md` or `rules/gates.md` directly; both are short enough that a full authoring workflow is overkill.
- **Reference file** → create it under the owning skill's `references/`, and add one line to that skill's body pointing at it.

## Trigger Phrases

Positive — this skill should fire:

- "from now on, always run the linter before committing"
- "can we add a rule that blocks force-pushes to main?"
- "I want Claude to always ask before touching the schema"

Negative — this skill should *not* fire:

- "fix this specific bug" → `superpowers:systematic-debugging`
- "write a SKILL.md for the thing we just decided" (category already decided) → `skills/_standards/authoring-skills-and-agents.md`
- "update the PORTS.md registry" → `allocating-local-ports`
