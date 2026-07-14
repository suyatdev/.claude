# Brainstorm: VibeCodingRules Standards Integration (2026-07-12)

Goal: apply the 38 extracted-standards markdown files (Days 1-5, ~16.6k words, at
`~/Other Docs/AI/Resources/VibeCodingRules/extracted-standards/`) into how Claude actually operates —
updating `CLAUDE.md`, `rules/*.md`, and adding a `skills/` layer.

Approved design (see spec at `docs/superpowers/specs/2026-07-12-vibe-coding-standards-integration-design.md`):

- **Three-tier architecture, dictated by the standards themselves.** The papers are explicit that active
  context is a budget (a 1M window still degrades at ~50K of active content) and that AGENTS.md/CLAUDE.md
  should stay tight and act as a router. Flattening 16.6k words into always-on rules would violate the
  standards in the act of adopting them. So: `CLAUDE.md` = router; `rules/*.md` = only every-turn behavior
  (~1,950 -> ~3,350 words); `skills/*/SKILL.md` = everything task-specific, zero cost until triggered.
- **Enterprise/product material becomes on-demand design skills, not a dead reference shelf.** A2A, A2UI,
  AP2/UCP, the 7 security pillars, and agent evaluation load when we brainstorm/architect a system that
  needs them, so they translate into future app designs.
- **Reinforce existing tooling, do not duplicate it.** Where superpowers/built-ins already own a workflow
  (systematic-debugging, test-driven-development, skill-creator, /code-review), the whitepaper's specific
  additions go into always-on rules instead of a competing skill — avoiding the trigger-collision/regression
  failure mode Day 3 warns about.
- **Rules layer:** extend the 4 existing files; add 3 new — `context-and-token-discipline.md`,
  `zero-trust-and-agent-safety.md`, `authoring-skills-and-agents.md`.
- **Skills layer (7 new + 1 setup skill):** designing-agentic-architecture, integrating-mcp,
  securing-agentic-systems, designing-agent-interop (A2A+A2UI), designing-agent-commerce (AP2+UCP),
  evaluating-agents-and-skills, writing-specs, setting-up-a-new-project.
- **Hooks: designed, not installed.** Scripts written and documented (secret scan, zero-width-Unicode /
  homoglyph scan per Day 4's invisible-payload rule, checkpoint-before-modify) but `settings.json` left
  untouched pending user review.
- **Project opt-in register (blocking gate).** New repos — and existing repos on first substantial touch —
  get a blocking setup checklist whose answers are written to that repo's `.claude/project-standards.md`
  and pointed to from `CODING_MEMORY.md`. Covers: rigor tier (prototype vs production), Conditional LGTM,
  which hooks to install, spec folder, sandboxing, `security:scan`, MCP server scoping, eval-in-CI, model
  routing, project `CLAUDE.md`. This exists because an opt-in that is only documented is an opt-in that
  gets forgotten.

Resolved conflicts:
- Existing rules keep their current ALWAYS/NEVER voice (not rewritten to Day 3's "explain the why" style);
  only *new* rules adopt it. The superpowers plugin is third-party and is not modified.
- `AGENTS.md` (papers) == `CLAUDE.md` (this setup); noted once, not duplicated.
- `writing-specs` defers to superpowers' existing `docs/superpowers/specs/` path rather than opening a
  competing `specs/` convention.
- Sandboxing / policy servers / LLM firewalls / SPIFFE identities are infrastructure this setup does NOT
  have. They stay as design guidance inside skills, phrased "when you build X, do Y" — no rule may imply
  the current setup has protections it does not.
- Day 5's "Conditional LGTM" (auto-merge on green) is opt-in per project, never a default, since it sits
  awkwardly with the existing default-branch-safety and tests-pass-before-PR rules.
