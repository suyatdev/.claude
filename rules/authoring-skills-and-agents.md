# Authoring Skills and Agents

`skill-creator` and `superpowers:writing-skills` own the authoring workflow; this file states the standards any skill must meet.

## The Description Field Is the Routing Algorithm

- **The only routing signal:** the description is all the model sees when deciding whether to load a skill, so it earns more time than the rest of the file. State what it does, when to use it, and explicitly when *not* to — the exclusion prevents over-triggering.
- **Front-load trigger keywords:** open with the action ("Generate a commit message…"), near 200 characters.
- **Six trigger phrases:** three positive and three negative triggers per skill; verify all six route correctly before shipping.
- **Frontmatter must lint clean:** an unparseable skill never routes.

## One Skill, One Job

- **"And" means two skills:** if the description needs an "and" between unrelated capabilities, it is two skills. Split along team-ownership boundaries.

## Writing the Body

- **Explain the why:** models generalize better to edge cases when they understand why a rule exists. Typing ALWAYS or NEVER in caps is a signal to stop and explain the rationale instead.
- **No paths, no secrets:** never hard-code either inside a skill, which gets committed and shared.
- **Progressive disclosure:** metadata always loaded, `SKILL.md` body on trigger, `references/` only as needed — what keeps a large library cheap (rules/context-and-token-discipline.md).

## Skill Smells

Revise on sight: over 5,000 words; two domain teams could own it; you can't write three test cases for it; it references no other resource; you keep adding "edge cases" sections; its description starts with "a helpful skill for…".

## The Read → Draft → Act Authority Ladder

- **Three tiers:** read-only may query but not mutate. Draft-only may produce content for human review but not send or commit. Action-allowed may execute irreversible operations.
- **Promote via a new skill:** higher authority means a separate, more heavily reviewed skill, not a tier bump; the old review never examined the new scope.
- **Agent-authored starts at draft:** anything an agent wrote or edited enters at the draft tier regardless of its confidence, with a human reading the diff; an agent grading its own work optimizes for an easily gamed metric.

## Installing Someone Else's Skill

- **Trust follows the source:** first-party, trust but pin. Org-curated, review on adoption. Community, audit before adopting and pin aggressively — a skill is code running in your context.
