# Authoring Skills and Agents

> **Reference document.** Load this when authoring or editing a skill or an agent. It is not a triggerable skill: `skill-creator` and `superpowers:writing-skills` own the authoring *workflow*. This file states the *standards* the resulting skill must meet, and the bar it must clear before it is allowed to act.

## None of This Machinery Exists Here Yet

**Read this before applying anything below.** This configuration has no CI, no unit tests for skill scripts, no eval suite, no automated security scan, no linter wired to a merge gate, and no org-level provisioning. The Deployment Checklist and the graduation criteria on the authority ladder describe **the bar to build toward**, not gates that currently run — nothing in this repository will stop a skill from shipping unverified today. Every check named here is **absent until someone builds it**; a document mistaken for an inventory produces false confidence, which is worse than having no document at all. Where a gate is claimed but not built, the honest move is to run the check by hand and say so.

## Folder Anatomy

- **`SKILL.md` is the only mandatory file:** every skill is a directory anchored by one. `scripts/`, `references/`, and `assets/` are optional and exist to hold what does not need to be in the body — deterministic code in `scripts/`, on-demand domain knowledge in `references/`, templates and schemas in `assets/`.
- **Move it to `references/` once the body gets long:** a paragraph that only matters after the skill is already running — domain principles, definitions, edge-case handling — is paying a body-sized token cost for reference-sized value. `references/` loads only when reached for.
- **Bundle repeated deterministic work into `scripts/`:** helper code the agent would otherwise re-derive every time (parsing, math, formatting) belongs in an executable script, not in prose. Code in a script can be unit-tested; the same logic in instructions can only be hoped at.

## Naming

- **Gerund form for skill names:** `managing-databases`, `processing-pdfs` — not `pdf-processor`. A skill names an activity the agent is doing, and the routing model matches on it.
- **kebab-case for both the directory and the skill name, and they must be identical:** `securing-agentic-systems/` holding a `SKILL.md` whose frontmatter says `name: securing-agentic-systems`. Claude Code resolves a skill by matching the directory name to the frontmatter `name`, so a mismatch means the skill never loads at all — no error, it is simply not there. (**Divergence from the source paper, deliberate:** it specifies *snake_case for directories, kebab-case for names*. That is correct for the harness it describes and wrong for this one — `securing_agentic_systems/` with `name: securing-agentic-systems` would break loading here. The rule follows the harness that actually runs the skill.)
- **No generic names:** `utils`, `tools`, `helper`, `data` give the routing model nothing to match against, so the skill either never fires or fires on everything.
- **No vendor prefixes:** `claude-*`, `gemini-*`, `anthropic-*` — portability is part of a skill's value, and the prefix buys nothing the description does not already say.
- **No internal jargon** an outsider would not recognize: a name only your team can parse is a name only your team can route to.

## The Description Field Is the Routing Algorithm

- **The only routing signal:** the description is all the model sees when deciding whether to load a skill. Everything else in the file is invisible until that decision has already been made, so the description earns more time than the rest of the file combined.
- **Say when not to use it:** state what the skill does, when to use it, and explicitly when *not* to. The exclusion is what prevents over-triggering — a skill with no stated boundary fires on adjacent tasks it was never designed for, and crowds out the skill that should have run.
- **Front-load trigger keywords:** open with the action ("Generate a commit message…"), and keep it near 200 characters. A description that buries its trigger words behind throat-clearing gets matched less reliably.
- **Six trigger phrases:** write three positive and three negative triggers for every skill, and verify all six route correctly before shipping. If you cannot write three cases that should *not* fire it, its scope is not yet defined.
- **Frontmatter must lint clean:** an unparseable skill never routes at all, however good its body is.
- **Be pushy if it under-triggers:** if testing shows the skill failing to fire on cases it should own, strengthen the description rather than accepting the miss. An under-triggering skill is indistinguishable from an absent one.

## One Skill, One Job

- **"And" means two skills:** if the description needs an "and" between unrelated capabilities, it is two skills. Split along team-ownership boundaries, so the people who own the underlying expertise own the file.
- **A single owner per skill:** give ownership to the domain team that already owns the knowledge, rather than centralizing skill-writing in a platform team that then becomes the bottleneck for every change.

## Writing the Body

- **Explain the reason, not just the rule:** models generalize to edge cases when they understand *why* a rule exists. A rule stripped to a bare imperative is context debt — reaching for a capitalized ALWAYS or NEVER is a signal to stop and write the rationale instead, because models learn to ignore rationale-free imperatives exactly as humans learn to ignore a wall of warning text.
- **No paths, no secrets:** never hard-code either inside a skill; skills get committed and shared.
- **Progressive disclosure:** metadata is always loaded, the `SKILL.md` body loads on trigger, and `references/` loads only when needed. This layering is what lets a library grow large without every skill taxing every turn (see `rules/context-and-token-discipline.md`).
- **Skills are dependencies:** version them, pin them, and review changes to them in pull requests, exactly as with any other library.
- **Cut any line that does not earn its place:** keep the gotchas, the exact commands, the business logic, the anti-patterns. Delete boilerplate the model already knows — "always validate output" teaches nothing and costs attention on every turn the skill is loaded.
- **Make every instruction verifiable:** if the agent cannot tell whether it followed a rule, the rule is too vague to keep as written. Rewrite it as something checkable, or cut it.
- **Blanket "always do X" rules belong in `CLAUDE.md`, not in a skill:** a skill is loaded conditionally, so a rule that must always hold cannot live in one. Project-wide conventions go in the project-level conventions file.
- **Don't reinvent MCP as scripts:** reaching an external system is a tool's job — use an MCP server. The skill's job is teaching the agent how to *think* about the task. A skill that re-implements a connector has taken on maintenance that a server was already carrying.

## Meta-Skills: Sequencing

- **Get the manual authoring loop working first:** pointing an agent at an empty folder and asking it to generate a library is the fastest route to a bad one. Author skills by hand until the loop is understood, then automate it.
- **Prefer harvesting a skill from a real trace:** when a trace of a successfully completed task exists, harvest the skill from it rather than asking an agent to author one from a described workflow. The human's job then shifts from writing the skill to confirming the harvested version captured the right steps — a much easier thing to get right.

## Skill Smells

Revise on sight:

- over 5,000 words
- two domain teams could own it
- you can't write three test cases for it
- it references no other resource
- you keep adding "edge cases" sections
- its description starts with "a helpful skill for…"

## The Read → Draft → Act Authority Ladder

Each tier widens the blast radius, so each carries its own review bar. A skill does not sit at a tier because it wants to — it sits there because it has earned it.

- **Read-Only** — may fetch, query, or describe data; may not mutate state. *Graduates on:* an LLM-as-judge eval and 90% trigger accuracy, reviewed by the domain team.
- **Draft-Only** — may produce content for human review; may not send or commit anything itself. *Graduates on:* a golden dataset of 20+ cases plus explicit human approval, reviewed by the domain team and whoever owns the output format.
- **Action-Allowed** — may execute irreversible operations on real systems. *Graduates on:* full adversarial red-teaming, sustained success across multiple runs rather than a single lucky pass, and zero rollback events; reviewed by the domain team plus security and compliance, with executive sign-off.

Supporting rules:

- **Promote via a new skill:** higher authority means a separate, more heavily reviewed skill, not a tier bump on the existing one — the review that cleared the old scope never examined the new one. A read-only return-policy skill that later needs to issue refunds becomes a distinct skill.
- **Agent-authored starts at draft:** anything an agent wrote or edited enters at the draft tier regardless of how confident the agent is, with a human reading the diff. An agent grading its own work optimizes for a metric it can trivially game.

## Deployment Checklist

Verify all of the following before a skill ships. **None of these gates exist in this repository** (see the note at the top): there is no CI, no eval suite, and no security scan to fail. Read this as the bar to build toward, and until it is built, run what you can by hand and state plainly which items were not checked.

- Frontmatter validates (lint passes).
- The description says what the skill does, when to use it, and when not to.
- Any scripts it carries have unit tests passing in CI.
- The eval suite passes in CI against a defined minimum-pass threshold.
- A security scan comes back clean — no secrets, no untrusted dependencies.
- The description has been reviewed by someone other than its author.
- Cross-tool install paths have been tested, if it ships publicly.
- Org-level admin provisioning is updated, if applicable.

## Installing Someone Else's Skill

- **Trust follows the source:** first-party — trust, but still pin. Org-curated — review on adoption. Community — audit before adopting, and pin aggressively. A skill is code that runs in your context, and it arrives carrying whatever intent its author had.
