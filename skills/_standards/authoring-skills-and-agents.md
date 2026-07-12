# Authoring Skills and Agents

> **Reference document.** Load this when authoring or editing a skill or an agent. It is not a triggerable skill: `skill-creator` and `superpowers:writing-skills` own the authoring *workflow*. This file states the *standards* the resulting skill must meet, and the bar it must clear before it is allowed to act.

## The Description Field Is the Routing Algorithm

- **The only routing signal:** the description is all the model sees when deciding whether to load a skill. Everything else in the file is invisible until that decision has already been made, so the description earns more time than the rest of the file combined.
- **Say when not to use it:** state what the skill does, when to use it, and explicitly when *not* to. The exclusion is what prevents over-triggering — a skill with no stated boundary fires on adjacent tasks it was never designed for, and crowds out the skill that should have run.
- **Front-load trigger keywords:** open with the action ("Generate a commit message…"), and keep it near 200 characters. A description that buries its trigger words behind throat-clearing gets matched less reliably.
- **Six trigger phrases:** write three positive and three negative triggers for every skill, and verify all six route correctly before shipping. If you cannot write three cases that should *not* fire it, its scope is not yet defined.
- **Frontmatter must lint clean:** an unparseable skill never routes at all, however good its body is.

## One Skill, One Job

- **"And" means two skills:** if the description needs an "and" between unrelated capabilities, it is two skills. Split along team-ownership boundaries, so the people who own the underlying expertise own the file.
- **A single owner per skill:** give ownership to the domain team that already owns the knowledge, rather than centralizing skill-writing in a platform team that then becomes the bottleneck for every change.

## Writing the Body

- **Explain the reason, not just the rule:** models generalize to edge cases when they understand *why* a rule exists. A rule stripped to a bare imperative is context debt — reaching for a capitalized ALWAYS or NEVER is a signal to stop and write the rationale instead, because models learn to ignore rationale-free imperatives exactly as humans learn to ignore a wall of warning text.
- **No paths, no secrets:** never hard-code either inside a skill; skills get committed and shared.
- **Progressive disclosure:** metadata is always loaded, the `SKILL.md` body loads on trigger, and `references/` loads only when needed. This layering is what lets a library grow large without every skill taxing every turn (see `rules/context-and-token-discipline.md`).
- **Skills are dependencies:** version them, pin them, and review changes to them in pull requests, exactly as with any other library.

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

Verify all of the following before a skill ships:

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
