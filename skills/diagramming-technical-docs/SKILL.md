---
name: diagramming-technical-docs
description: Use when writing technical documentation, a system/architecture design, a data pipeline, an implementation plan, or a decision/ADR/tradeoff analysis that a picture would make clearer — embeds rendered Mermaid diagrams (flowchart, sequence, state, ER for structure; mindmap for decisions). Not for non-technical prose, slide graphics, or diagrams that must ship as PlantUML.
---

# Diagramming Technical Docs

A paragraph describing a request lifecycle, a service topology, or a set of tradeoffs forces the reader to rebuild the shape in their head. A diagram hands them the shape directly. Embed one whenever the thing being documented *has* a structure — components and their connections, a sequence over time, a lifecycle of states, or a branching decision — because those are exactly the cases where prose is slowest to read and easiest to get subtly wrong.

## Use Mermaid, never PlantUML

Everything here is Mermaid, in a native ` ```mermaid ` fenced block. The reason is that the docs live in GitHub, VS Code previews, and Claude Artifacts, and **Mermaid renders in all three natively while PlantUML does not.** A PlantUML `@startmindmap` block placed in ` ```text ` shows as plain indented text in every one of those surfaces — the reader gets no picture. The only ways to render PlantUML are a local Java+Graphviz toolchain or POSTing the diagram source to a public `plantuml.com` server, and the latter sends private architecture and decision content to a third party. Mermaid avoids all of that and covers the mind-map case too (it has a native `mindmap` type), so there is no diagram category that needs PlantUML.

## Which diagram for which job

Two families. Match the diagram to what you are documenting — the wrong type is as unhelpful as no diagram.

**Structure and flow** — use when documenting *how parts connect or move*:

- **System architecture** (clients, gateways, services, datastores) → `flowchart` (`graph TD`/`LR`)
- **Multi-party interaction over time** (auth handshakes, request/response lifecycles) → `sequenceDiagram`
- **Data pipeline / ETL** (source → validation → warehouse) → `flowchart LR`
- **Lifecycle with states** (order Pending→Paid→Shipped, job states) → `stateDiagram-v2`
- **Data model / entities** (tables and their relationships) → `erDiagram`

**Decisions and analysis** — use when *weighing options or breaking a problem down*:

- **Tradeoff analysis** (SQL vs NoSQL, build vs buy), **root-cause trees**, **scope/epic breakdown**, **requirement gathering** → `mindmap`

Full syntax per type, with the gotchas that break rendering, is in `references/diagram-types.md`. Copy-paste starting points for each are in `assets/templates.md`.

## Output rules

- **Diagram first, then prose.** When asked to design or analyze a system, put the diagram immediately after the one-line summary — before the detailed explanation, not buried under it.
- **Don't narrate the diagram.** If the nodes and labels already say `Client → Auth Gateway → Session Cache`, do not restate that in a sentence below. Spend the surrounding text on what the diagram *cannot* show: why this shape, the failure modes, the constraints, the next decision.
- **Balanced syntax or it won't render.** Every `[ ]`, `( )`, `[( )]`, and `{ }` must close, and the first line must be a valid diagram header. An unbalanced bracket makes the whole block render as an error box — worse than plain text. Run `scripts/validate-diagrams.sh <file.md>` before shipping a doc; it catches the common render-breakers (bad header, unbalanced brackets, empty block).
- **One idea per diagram.** A diagram that needs a legend to be understood is two diagrams. Split it.

## Resources

- `references/diagram-types.md` — per-type syntax, when to use each, and the specific gotchas that break rendering (the `end` keyword trap, labels with special characters, cardinality syntax). Load when picking or debugging a diagram.
- `assets/templates.md` — fill-in-the-blank templates for all six diagram types above.
- `scripts/validate-diagrams.sh` — extracts ` ```mermaid ` blocks from a Markdown file and lints each for a recognized header and balanced brackets. A render pre-check, not a full Mermaid parser.

## Trigger phrases

Positive — this skill should fire:

- "design the auth flow for this service" / "map out how these services connect"
- "document the order state machine" / "diagram this ETL pipeline"
- "help me weigh Postgres vs DynamoDB for this" (a tradeoff mind map)

Negative — this skill should *not* fire:

- "write the API error-message copy" → non-technical prose, no structure to draw
- "make a polished slide graphic for the deck" → presentation design, not in-repo docs
- "render this as a PlantUML `.puml` file" → explicit non-Mermaid tooling request
