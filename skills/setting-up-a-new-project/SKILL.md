---
name: setting-up-a-new-project
description: Use when setting up a new project or repo, or on first substantial work in an existing repo that has no .claude/project-standards.md. Runs the blocking opt-in register — rigor tier, review gate, hooks, sandboxing, MCP scoping, eval-in-CI, model routing — and records the answers in the repo. Not for routine work in an already-configured repo.
---

# Setting Up a New Project

Most of this setup's stronger controls are opt-in: hooks, sandboxing, spec-first development, eval-in-CI, Conditional LGTM. An opt-in that lives only in a document is an opt-in that gets forgotten, and a control nobody remembers to enable is indistinguishable from a control that does not exist. This skill is the register that forces the decision to be made once, explicitly, per repo — and then writes it down where the next session will find it.

## This Is a Blocking Gate

Stop before writing project code. The order is: ask the questions, get the user's answers, write `.claude/project-standards.md`, then proceed to the work.

The gate is worth blocking on because these choices are cheap now and expensive later. Deciding the rigor tier before the first commit costs a sentence; discovering after three months of prototype-grade work that the thing is in production costs a rewrite. Retrofitting a secret-scanning hook onto a repo that has already leaked a key is not the same operation as installing it on day one.

The gate fires once per repo. Once `.claude/project-standards.md` exists, routine work proceeds without re-running this skill.

## Do Not Answer on the User's Behalf

The failure mode this skill exists to prevent is an agent that reads the ten questions, picks sensible defaults for all of them, writes a tidy file, and reports the project as configured. That produces a document nobody agreed to, recording decisions nobody made.

- **Suggesting a default is correct; adopting one silently is the failure.** State the default, explain the tradeoff, and wait.
- **Do not infer answers from the codebase.** A repo with a CI file is not thereby a production-tier repo. The tier is a statement of intent, and only the user holds it.
- **If the user declines to answer a question, record that** as `Undecided` with the reason — an honest gap is auditable; a fabricated answer is not.

## How to Run the Register

Ask **one question at a time**. Use `AskUserQuestion` wherever the options are enumerable (which is most of them), and free text only where the answer is a list the user must supply, such as which MCP servers to wire up.

**Question 1 gates the rest.** Ask it first and let the answer shape the remaining nine:

- **Prototype / vibe-coding tier** — several later questions have obvious cheap answers. Offer questions 3–6 and 8–9 as a single batch default for the user to confirm or amend in one pass, rather than walking through each. Speed is the point of the tier; a nine-question interrogation defeats it.
- **Production / agentic-engineering tier** — ask each question individually. At this tier the cost of a wrong default is real, and a batch confirmation is where wrong defaults hide.

## The Ten Questions

**1. Rigor tier — prototype/vibe-coding, or production/agentic-engineering?**
*Default:* none. Ask; do not assume. *Why:* teams that leave this blurry ship prototypes into production by accident — the code was written under one set of assumptions and is now serving traffic under another. Naming the tier makes the later corner-cutting a decision rather than a drift, and it gates every question below.

**2. Review gate — human approval on every PR, or Conditional LGTM (auto-merge on green)?**
*Default:* human gate. *Why:* auto-merge sits in direct tension with the default-branch-safety and tests-pass-first rules in `rules/gates.md`. It can be the right call for a low-stakes repo with strong tests, but it has to be a deliberate opt-in that a human chose, not a habit the repo slid into.

*If an automated reviewer is wanted, pick the lowest tier that catches what actually matters.* **Managed** — a vendor-hosted reviewer, no infrastructure, generic criteria; enough when the criteria are generic. **Hybrid** — your own review skill triggered by CI (a GitHub Action running a coding-agent CLI); the right call when criteria are team- or repo-specific but need no memory across runs. **Custom** — a dedicated agent with durable sessions; only when the reviewer must hold context across a multi-PR refactor. Escalate on failure severity, not preference: if the worst case is a noisy comment, any tier does. If the worst case is a merged regression or a leaked secret, the reviewer needs a policy gate in front of every tool call it makes — infrastructure this setup does not have (see `skills/securing-agentic-systems`).

Whichever tier: an automated reviewer is a *first pass* — good at bugs, style violations, known vulnerability shapes, and performance smells. It does not replace human review for the context-dependent calls: design, maintainability, strategic fit. Letting it do so converts review into a formality with a green check on it.

**3. Hooks to install in the repo's `.claude/settings.json` — secret scan, invisible-Unicode scan, checkpoint-before-modify?**
*Default:* none; opt in per hook. *Why:* rule files are instructions, and instructions are guidance a model can be talked out of. Hooks are deterministic and run outside the model's judgment, which is why they are the only real enforcement available here. They are not installed by default because they belong to the repo's `.claude/settings.json`, and that is the user's file to change.

**4. Is a spec required before implementation — is BDD/Gherkin mandated?**
*Default:* yes at production tier; optional at prototype tier. *Why:* without a spec the agent is guessing from a vibe, and every gap it infers is a place a defect gets in. See `skills/writing-specs`.

**5. Sandboxing — do agent-written scripts run in a container, or on the host?**
*Default:* **host, unsandboxed.** *Why:* this setup has no container sandbox, no policy server, and no LLM firewall. Say that plainly rather than implying otherwise — a false "yes, it's sandboxed" is worse than a truthful "no", because it buys confidence that nothing is backing. If the project needs real isolation, that is infrastructure to build; see `skills/securing-agentic-systems`. Until then, treat every agent-written script as running with the user's full privileges, because it is.

**6. Is a `security:scan` script actually wired up?**
*Default:* required — verify it exists rather than assuming. *Why:* `writing-secure-code` already demands a `security:scan` script. This question checks that reality matches the rule, which is the only way a written requirement stays a real one. Confirm the script runs, not merely that a line exists in `package.json` or its equivalent.

**7. MCP servers — which ones, scoped read-only, pointed at non-production data?**
*Default:* none. *Why:* an unscoped MCP server with write access to production data is the standing risk in this whole setup — the agent treats tool output as data, but the tool's *permissions* are real. Add servers one at a time, read-only until proven otherwise, and against non-production data wherever a non-production copy exists. See `skills/integrating-mcp`.

**8. Eval-as-unit-test in CI?**
*Default:* mandatory at production tier. *Why:* deterministic tests catch regressions in code. Only evals catch behavioral drift — the prompt that quietly got worse, the skill that stopped triggering. A repo with LLM-shaped behavior and no evals has no way to notice it degrading. See `skills/evaluating-agents-and-skills`.

**9. Model routing — which tiers handle which work in this repo?**
*Default:* frontier models for architecture, design, and gnarly debugging; cheaper models for mechanical work like renames, test scaffolding, and formatting. *Why:* running a frontier model on every trivial fix burns spend with no quality benefit, and the reverse — a cheap model on an architectural decision — is where the expensive mistakes come from.

**10. Is the project `CLAUDE.md` populated?**
*Default:* required. *Why:* every project needs one, and it should start small: the stack, the conventions, the hard rules, the workflow. Grow it by adding a rule each time the agent repeats a mistake — a project `CLAUDE.md` that was written once and never touched is a sign nobody is feeding corrections back into it.

## Recording the Answers

1. Copy `assets/project-standards-template.md` into the target repo as `.claude/project-standards.md`.
2. Fill in every section with the user's actual answers, including the `Decided on:` date and the `Revisit when:` trigger. An unfilled section is a question that was skipped, and skipping is the thing this skill exists to prevent.
3. Create the repo's own `CODING_MEMORY.md` as a lean index (active session, PR pointers, next steps — see `managing-session-memory`) with a `coding-memory/` directory alongside it for history, from the first commit. Add a pointer line there for this setup register so future sessions know it has run and where the answers live.
4. Commit both files with the repo's setup work. They are project artifacts, not scratch notes.

Then proceed to the actual work.

## Trigger Phrases

Positive — this skill should fire:

- "let's start a new repo for the billing service"
- "set up this project"
- "I'm about to start building X" — in a repo with no `.claude/project-standards.md`

Negative — this skill should *not* fire:

- "add a function to this existing service" → routine work in a configured repo; proceed normally
- "open a PR" → `preparing-pull-requests`
- "write a spec" → `skills/writing-specs`
