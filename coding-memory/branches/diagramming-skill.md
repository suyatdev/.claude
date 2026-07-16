# Branch Implementation Log: feature/diagramming-skill

**Status:** MERGED (PR #12, 2026-07-16, branch `feature/diagramming-skill` from `main`). Tree clean.

## Why

User wants a documentation standard: embed rendered text-to-diagram code blocks in technical
docs, system plans, architecture designs, and decision/ADR docs. Routed through
`triaging-new-instructions` → classified as a **new cross-cutting skill** (used by specs,
architecture, ADRs, brainstorms — so one skill the others reference, not diagram guidance
duplicated into each), structured with `references/` + `assets/` + `scripts/` per
`authoring-skills-and-agents.md`.

## Key decision: Mermaid only, not PlantUML

The user's supplied standard paired Mermaid (structure) with **PlantUML** mind maps (decisions).
Flagged as a defect before building: PlantUML in a ` ```text ` block does **not render** in
GitHub, VS Code previews, or Claude Artifacts (it shows as plain indented text), and the only
ways to render it are a local Java+Graphviz toolchain or POSTing the diagram source to a public
`plantuml.com` server — which leaks private architecture/decision content. Mermaid renders
natively in all three surfaces **and** has a native `mindmap` type, so it covers the decision
case too. User chose **Mermaid-for-both**.

## What was built

- `skills/diagramming-technical-docs/SKILL.md` — when to diagram, which type per job, output
  rules (diagram-first, don't narrate nodes, balanced syntax), and the Mermaid-not-PlantUML
  rationale.
- `references/diagram-types.md` — per-type syntax + the render-breaking gotchas (the `end`
  reserved word, quoted labels, ER cardinality reading, one-root mindmap rule).
- `assets/templates.md` — fill-in templates for all six use cases (architecture, sequence, ETL,
  state machine, ER, decision + root-cause mindmap).
- `scripts/validate-diagrams.sh` — extracts ` ```mermaid ` blocks and checks each for a
  recognized header + balanced brackets. A heuristic pre-check, not a full parser (stated as
  such in the skill).
- `CLAUDE.md` catalog entry + a one-line pointer from `managing-session-memory`'s ADR bullet.

## Validator design notes worth remembering

- Self-test caught **two real bugs in the script** (not the templates): the asymmetric `>flag]`
  node-strip regex was also eating arrowheads (`-->`), corrupting bracket counts — fixed by
  requiring a word char before `>`; and ER cardinality (`o{`, `|{`) tripped the `{ }` count —
  fixed by skipping the brace check for `erDiagram`. Tested: all templates PASS (exit 0), a
  crafted bad file flags header/unbalanced/empty (exit 1), and no false positives on asymmetric
  nodes, brackets-in-quotes, or ER cardinality.

## Follow-ups

- Optional: add in-context pointers from `designing-agentic-architecture` and `writing-specs`
  (skipped to limit scope; the skill triggers on its own for those tasks, and the catalog lists it).
