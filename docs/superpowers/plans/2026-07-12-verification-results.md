# Verification Results — VibeCodingRules Standards Integration

**Task 18 of 19.** Branch: `feature/vibe-coding-standards-integration`. Date: 2026-07-12.

Every number below is observed command output, not an estimate. Where a check failed, the failure is
recorded alongside the fix; where it could not be fixed, it is recorded as an open defect.

**Verdict: 5 of 6 steps PASS as run. Step 2 (coverage) FAILED on first pass — 15 distinct pieces of
source content had landed nowhere. 13 were fixed during this pass. The remaining 2 were recorded as
open defects, blocked on the always-on word budget.**

**Update (2026-07-12, follow-up pass): D-1 and D-2 are now CLOSED.** The user resolved the budget
question by choosing a **skills destination over always-on** — both rules are load-on-demand rather
than resident in `rules/general-engineering.md`, so they cost zero always-on words and the ceiling
did not have to move. The always-on total is still **3,473**. All 15 gaps are now closed.

---

## Step 1 — Always-on token budget: **PASS**

```
$ wc -w CLAUDE.md rules/*.md RTK.md
     213 CLAUDE.md
     345 rules/context-and-token-discipline.md
     854 rules/general-engineering.md
     280 rules/parallel-agent-guardrails.md
     765 rules/pr-requests.md
     463 rules/session-state-management.md
     415 rules/zero-trust-and-agent-safety.md
     138 RTK.md
    3473 total
```

**3,473 / 3,500.** PASS, with **27 words of headroom** (0.8%).

Re-run after this task's fixes: still **3,473** — all fixes landed in skills (load-on-demand), so the
always-on footprint is unchanged. That headroom is the binding constraint behind the two open defects
in Step 2.

---

## Step 2 — Coverage audit: **FAILED on first pass, 13 of 15 gaps fixed**

38 source files; 5 are `index.md` (navigational); **33 content files** audited against the coverage map
in `docs/superpowers/specs/2026-07-12-vibe-coding-standards-integration-design.md`.

### Method

Shell `grep` returned empty for patterns known to be present (the `rtk` hook mangles it), so the audit
was run in Python with a control check first — 25 destination files loaded, control strings
(`slopsquatting`, `Agent Card`, `pass^k`, `references/seven-pillars.md`) all hit. Only then were the
negative results trusted.

### The 33 rows

| # | Source file | Destination | Represented? |
|---|---|---|---|
| **Day 1 — The New SDLC** ||||
| 1 | `context-engineering.md` | `rules/context-and-token-discipline.md` | **yes** (after fix) |
| 2 | `verification-and-testing.md` | `rules/general-engineering.md` + `skills/evaluating-agents-and-skills` | **yes** (after fix) |
| 3 | `harness-engineering.md` | `rules/context-and-token-discipline.md` + `hooks/` + `skills/designing-agentic-architecture` | **yes** (after fix) |
| 4 | `architecture-and-human-oversight.md` | `rules/general-engineering.md` + `rules/zero-trust-and-agent-safety.md` | yes |
| 5 | `developer-workflow-and-roles.md` | `rules/parallel-agent-guardrails.md` | yes — 3 human-practice bullets not carried |
| 6 | `team-and-organizational-practices.md` | `rules/pr-requests.md` + opt-in register | yes |
| 7 | `ai-development-economics.md` | `rules/context-and-token-discipline.md` | yes |
| **Day 2 — Agent Tools & Interop** ||||
| 8 | `mcp-consumption-and-configuration.md` | `skills/integrating-mcp` | yes |
| 9 | `mcp-debugging-and-governance.md` | `skills/integrating-mcp` | yes |
| 10 | `agentic-architecture-and-specialization.md` | `skills/designing-agentic-architecture` + `rules/parallel-agent-guardrails.md` | yes |
| 11 | `a2a-interoperability-and-monetization.md` | `skills/designing-agent-interop` | yes |
| 12 | `a2ui-interoperability.md` | `skills/designing-agent-interop` | yes |
| 13 | `agent-commerce-ap2-and-ucp.md` | `skills/designing-agent-commerce` | yes |
| **Day 3 — Agent Skills** ||||
| 14 | `skill-authoring-and-structure.md` | `skills/_standards/authoring-skills-and-agents.md` | **yes** (after fix — was the worst gap) |
| 15 | `evaluation-and-testing.md` | `skills/evaluating-agents-and-skills` | yes |
| 16 | `governance-and-deployment.md` | `skills/_standards/...` + `skills/evaluating-agents-and-skills` | yes — 1 org-strategy bullet not carried |
| 17 | `context-and-token-management.md` | `rules/context-and-token-discipline.md` | yes |
| 18 | `composition-and-architecture.md` | `skills/designing-agentic-architecture` | **yes** (after fix) |
| 19 | `meta-skills-and-self-improvement.md` | `skills/_standards/authoring-skills-and-agents.md` | **yes** (after fix) |
| 20 | `skill-sourcing-and-security.md` | `skills/_standards/...` + `rules/zero-trust-and-agent-safety.md` | yes |
| **Day 4 — Security & Evaluation** ||||
| 21 | `infrastructure-and-sandboxing.md` | `skills/securing-agentic-systems` + `rules/zero-trust-and-agent-safety.md` | yes |
| 22 | `data-security.md` | `skills/securing-agentic-systems` | yes |
| 23 | `application-security.md` | `skills/securing-agentic-systems` + `rules/zero-trust-and-agent-safety.md` | yes |
| 24 | `identity-and-access-management.md` | `skills/securing-agentic-systems` + `rules/zero-trust-and-agent-safety.md` | yes |
| 25 | `security-operations-and-red-blue-green-teaming.md` | `skills/securing-agentic-systems` + `hooks/` + `rules/general-engineering.md` | yes |
| 26 | `observability-and-governance.md` | `skills/securing-agentic-systems` + `rules/zero-trust-and-agent-safety.md` | yes |
| 27 | `evaluation.md` | `skills/evaluating-agents-and-skills` | yes |
| **Day 5 — Spec-Driven Development** ||||
| 28 | `spec-driven-development.md` | `skills/writing-specs` | yes |
| 29 | `instruction-and-context-management.md` | `rules/context-and-token-discipline.md` + `CLAUDE.md` + `skills/writing-specs` | **yes** (after D-1 fix) |
| 30 | `prompting-by-use-case.md` | `rules/general-engineering.md` + `skills/writing-specs` + `skills/integrating-mcp` | **yes** (after D-1/D-2 fix) |
| 31 | `mcp-integration.md` | `skills/integrating-mcp` | yes |
| 32 | `team-culture-and-code-review.md` | `rules/pr-requests.md` + opt-in register | yes — 3 org-culture bullets not carried |
| 33 | `testing-and-evaluation.md` | `rules/general-engineering.md` + `skills/evaluating-agents-and-skills` | yes — 1 minor bullet not carried |

**Score: 33/33 files represented at their destination. 29/33 fully; 4 carry residual bullet-level
gaps, none of which are open defects — D-1 and D-2 are closed (see below).**

Days 2 and 4 are effectively complete transcriptions — every bullet of all 13 files traced to a
destination. The gaps clustered entirely in Day 1, Day 3 authoring, and Day 5 prompting.

### Gaps found and FIXED during this pass (13)

The Day 3 authoring gap was the most serious: `skill-authoring-and-structure.md` had lost its **entire
`Naming` section** and its **`Folder Anatomy` section** — and `skills/_standards/authoring-skills-and-agents.md`
is the file that exists specifically to hold them. The 8 new skills happen to follow gerund naming, but
the standard requiring it was written down nowhere.

| Content that had landed nowhere | Source | Now lives in |
|---|---|---|
| Skill naming: gerund form, kebab-case names, snake_case dirs, no generic names, no vendor prefixes, no jargon | D3 `skill-authoring` | `skills/_standards/authoring-skills-and-agents.md` |
| Folder anatomy: `SKILL.md` mandatory; `scripts/`, `references/`, `assets/` roles | D3 `skill-authoring` | `skills/_standards/...` |
| "Cut any line that doesn't earn its place" | D3 `skill-authoring` | `skills/_standards/...` |
| "Make every instruction verifiable" | D3 `skill-authoring` | `skills/_standards/...` |
| "Be pushy in the description if it under-triggers" | D3 `skill-authoring` | `skills/_standards/...` |
| "Blanket always-do-X rules belong in CLAUDE.md, not a skill" | D3 `skill-authoring` | `skills/_standards/...` |
| "Don't reinvent MCP as scripts" | D3 `skill-authoring` | `skills/_standards/...` |
| Meta-skill sequencing: manual loop before meta-skills; prefer harvesting from a real trace | D3 `meta-skills` | `skills/_standards/...` |
| The **Six Types of Context** (Instructions, Knowledge, Memory, Examples, Tools, Guardrails) | D1 `context-engineering` | `skills/designing-agentic-architecture` |
| "MCP is reach, a Skill is know-how — compose, don't compete" | D3 `composition` | `skills/designing-agentic-architecture` |
| "Harness drives the automated test-fix loop" | D1 `harness-engineering` | `skills/designing-agentic-architecture` |
| Continuous review tiers: Managed / Hybrid / Custom, escalate on failure severity | D5 `team-culture` | `skills/setting-up-a-new-project` (Q2) |
| "AI is a first-pass reviewer, not a replacement for human design review" | D1 `verification-and-testing` | `skills/setting-up-a-new-project` (Q2) |
| Isolated/incognito browser profile for agent-driven UI debugging | D5 `prompting-by-use-case` | `skills/securing-agentic-systems/references/seven-pillars.md` |

All 14 rows verified present by post-fix Python grep. Every fix landed in a **load-on-demand** file, so
the always-on budget stayed at 3,473 — confirmed by re-running Step 1.

The Six Types of Context deserve a note: `designing-agentic-architecture` already carried the six
*harness* components, which is a **different list**. The two were not interchangeable, and the context
taxonomy had simply been lost. The fix states the distinction explicitly so they are not conflated later.

### DEFECTS D-1 and D-2 — **CLOSED** (follow-up pass, 2026-07-12)

Both were originally held open because the coverage map promised them to `rules/general-engineering.md`
and the always-on budget had only **27 words of headroom** — enough to land them, but only by consuming
the entire safety margin (3,500/3,500, zero room for a future edit). That was a budget call the
verification pass declined to make silently.

**The user made the call: put them in skills, not always-on.** A load-on-demand skill costs zero
always-on words, and both rules are topically at home in a skill that already owns the surrounding
concern. The always-on ceiling never had to move and the total is unchanged at **3,473**.

| # | Content | Source | Map originally promised | Now lives in | Status |
|---|---|---|---|---|---|
| **D-1** | **Structured docstrings** — Google style for Python, JSDoc for TypeScript, so a function's contract is readable without reading its logic. Carried alongside the adjacent docs/code-sync rule (`README.md` / `CHANGELOG.md` updated in the change that makes them wrong). | D5 `prompting-by-use-case`, D5 `instruction-and-context-management` | `rules/general-engineering.md` | `skills/writing-specs/SKILL.md` → *The Spec Is the Source of Truth, Not the Code* | **CLOSED** |
| **D-2** | **Show the exact query** — when a tool queries tables or moves files, display the SQL/command that produced the output, not just the output. | D5 `prompting-by-use-case` | `rules/general-engineering.md` | `skills/integrating-mcp/SKILL.md` → *Governance — Do* | **CLOSED** |

Placement rationale: `writing-specs` already argues that documentation is the contract and that
spec/code drift causes hallucination — docstrings are that same argument one level down, at the
function. `integrating-mcp` already requires validating a query's type before execution and showing
tool *inputs* to a human before the call — showing the query that ran is the same human-oversight
concern on the output side.

The coverage map in
`docs/superpowers/specs/2026-07-12-vibe-coding-standards-integration-design.md` was corrected in the
same pass: the Day 5 rows for `instruction-and-context-management.md` and `prompting-by-use-case.md`
now name these skill destinations instead of asserting a `rules/general-engineering.md` landing that
never happened.

### Still uncarried (lower value, same original budget cause)

- "Require tests, documentation, and logging in every scaffold" (D5 `prompting-by-use-case`) — `general-engineering.md` has *Never scaffold in YOLO mode* and *Pin exact versions*, but not this.
- "Manually confirm changes across multiple files" (D5 `prompting-by-use-case`).
- "Don't duplicate instructions across all three layers" — the *instructional fragmentation* warning (D5 `instruction-and-context-management`). `CLAUDE.md` states the layering but not the anti-duplication rule.

**Remedy for these three:** either raise the ceiling above 3,500, trim words from an always-on file,
or — as with D-1 and D-2 — find them a load-on-demand home. Still a user call.

### Recorded, deliberately NOT carried (no agent-actionable surface)

These are organizational and human-career practices. They have no behavior an agent can execute, so
carrying them into an agent config would be cargo. Listed here so the "nothing is silently dropped"
claim in the spec stays honest — they were dropped, and this is the disclosure.

- Digital Quiet Hours; Agent Insight Sessions; "attribute integration failures to the process, not the individual" (D5 `team-culture`)
- "Invest in the skills library as the durable strategic asset" (D3 `governance-and-deployment`)
- The 80%-problem framing; "prototype one workflow as an agent, then graduate it"; "maintain your own foundational skills through practice" (D1 `developer-workflow-and-roles`)
- "Use AI to expand test coverage beyond manual capacity" (D5 `testing-and-evaluation`)

---

## Step 3 — Skill trigger routing collisions: **PASS**

```
$ grep -A8 'Trigger Phrases' skills/*/SKILL.md
```

All 8 skills declare 3 positive + 3 negative triggers = **24 positive phrases, all distinct**.
**No phrase is a positive trigger for two skills.** PASS.

Negative triggers all route to the correct owner:

| Skill | Defers to |
|---|---|
| `designing-agent-commerce` | `integrating-mcp`, `designing-agent-interop` |
| `designing-agent-interop` | `integrating-mcp`, `designing-agent-commerce`, `frontend-design` |
| `designing-agentic-architecture` | `skills/_standards/authoring-skills-and-agents.md`, `integrating-mcp`, `/code-review` |
| `evaluating-agents-and-skills` | `rules/general-engineering.md`, `/code-review`, `superpowers:systematic-debugging` |
| `integrating-mcp` | `designing-agent-interop`, `securing-agentic-systems`, `writing-specs` |
| `securing-agentic-systems` | `/security-review`, `rules/zero-trust-and-agent-safety.md`, `designing-agentic-architecture` |
| `setting-up-a-new-project` | routine work, `rules/pr-requests.md`, `skills/writing-specs` |
| `writing-specs` | `superpowers:writing-plans`, `superpowers:brainstorming`, `rules/general-engineering.md` |

Cosmetic inconsistency (not a defect): `designing-agent-commerce` labels its lists `Fires on:` /
`Does not fire on:` while the other seven use `Positive — this skill should fire:` /
`Negative — this skill should *not* fire:`.

---

## Step 4 — Regression against existing skills: **PASS**

```
$ ls skills/
_standards                      integrating-mcp
designing-agent-commerce        securing-agentic-systems
designing-agent-interop         setting-up-a-new-project
designing-agentic-architecture  writing-specs
evaluating-agents-and-skills
```

**Zero name collisions** with `superpowers:brainstorming`, `superpowers:writing-plans`,
`superpowers:systematic-debugging`, `superpowers:test-driven-development`, `superpowers:writing-skills`,
`skill-creator`, `code-review`, `security-review`, `verify`, `run`, `dataviz`, `frontend-design`.

`_standards/` is a reference directory, not a skill — it has no frontmatter and cannot trigger. Correct
per the Task 3b amendment.

**"Not for …" clause present in all 8 descriptions — 8/8:**

```
YES designing-agent-commerce      YES integrating-mcp
YES designing-agent-interop       YES securing-agentic-systems
YES designing-agentic-architecture YES setting-up-a-new-project
YES evaluating-agents-and-skills  YES writing-specs
```

Each defers to the adjacent incumbent explicitly: `securing-agentic-systems` → `/security-review`;
`evaluating-agents-and-skills` → `rules/general-engineering.md`; `writing-specs` →
`superpowers:writing-plans` and `superpowers:brainstorming`; `designing-agentic-architecture` →
`skills/_standards/authoring-skills-and-agents.md`.

---

## Step 5 — The no-false-assurance sweep: **PASS**

### Always-on files (CLAUDE.md + rules/) — 2 hits, both legitimate

```
$ grep -inE 'sandbox|policy server|LLM firewall|SPIFFE|mTLS|CMEK|OpenTelemetry|circuit breaker' CLAUDE.md rules/*.md
CLAUDE.md:31: - `securing-agentic-systems` — sandboxing, supply chain, agent identity, tool-call policy gating, agent observability.
rules/zero-trust-and-agent-safety.md:32: This setup has no container sandbox, policy server, or LLM firewall. These rules are what Claude can enforce unaided; see skills/securing-agentic-systems for the infrastructure-level controls to build when designing a system that needs them.
```

- `rules/zero-trust-and-agent-safety.md:32` — this **is** the explicit disclaimer sentence. Qualifies under (a).
- `CLAUDE.md:31` — a **skills-catalog entry naming the skill's subject matter**, under a heading that
  reads "These skills load on demand… Read the one whose trigger matches the work in front of you."
  It lists what the skill is *about*; it makes no claim that the setup *has* these controls. Judged
  acceptable. **No line in any always-on file reads as though this setup has these protections.**

### Skills — every file carrying infra content also carries its own disclaimer

```
$ grep -icE 'sandbox|policy server|LLM firewall|SPIFFE|mTLS|CMEK|OpenTelemetry|circuit breaker' <skills>
skills/designing-agentic-architecture/SKILL.md              1
skills/securing-agentic-systems/SKILL.md                    7
skills/setting-up-a-new-project/SKILL.md                    4
skills/securing-agentic-systems/references/policy-server.md 6
skills/securing-agentic-systems/references/seven-pillars.md 12
(all others: 0)
```

`references/` files load independently of their SKILL.md, so each was checked for its **own** note
rather than assumed to inherit one. **All five carry one:**

| File | Disclaimer |
|---|---|
| `securing-agentic-systems/SKILL.md` | `## None of This Exists Here` — "no container sandbox, no policy server, no LLM firewall, no SPIFFE identities, no CMEK, no mTLS, and no OpenTelemetry tracing" |
| `securing-agentic-systems/references/seven-pillars.md` | Own blockquote: "None of it is present in this configuration: no sandbox, no registry gating, no CMEK, no SPIFFE…" |
| `securing-agentic-systems/references/policy-server.md` | Own blockquote: "No policy server exists in this configuration; nothing below is currently enforcing anything." |
| `evaluating-agents-and-skills/SKILL.md` | `## No Eval Harness Exists Here Yet` — "no eval harness, no golden datasets, no CI, no canary… no span-level tracing" |
| `evaluating-agents-and-skills/references/evaluation-dimensions.md` | Own blockquote: "None of it exists in this configuration… Read it as a specification to implement, never as an inventory." |

The two incidental hits are both explicitly framed as absent:

- `designing-agentic-architecture:67` — "These are the six components to deliberately build into a
  system you are designing; **treat each as absent until you have actually built it.**" → (b).
- `setting-up-a-new-project:54` — "*Default:* **host, unsandboxed.** *Why:* **this setup has no
  container sandbox, no policy server, and no LLM firewall.** Say that plainly rather than implying
  otherwise — a false 'yes, it's sandboxed' is worse than a truthful 'no'." → (b).

Content added during this task was held to the same bar: the new review-tier text in
`setting-up-a-new-project` says a Custom reviewer needs a policy gate — "**infrastructure this setup
does not have** (see `skills/securing-agentic-systems`)."

**No line anywhere reads as though this setup has protections it does not. Nothing to fix.**

---

## Step 6 — Frontmatter validity: **PASS**

Verified by reading each file in Python, **not** by trusting shell `head` (the `rtk` hook mangles it).

```
designing-agent-commerce        first_line='---'  keys=['name','description']  name matches dir
designing-agent-interop         first_line='---'  keys=['name','description']  name matches dir
designing-agentic-architecture  first_line='---'  keys=['name','description']  name matches dir
evaluating-agents-and-skills    first_line='---'  keys=['name','description']  name matches dir
integrating-mcp                 first_line='---'  keys=['name','description']  name matches dir
securing-agentic-systems        first_line='---'  keys=['name','description']  name matches dir
setting-up-a-new-project        first_line='---'  keys=['name','description']  name matches dir
writing-specs                   first_line='---'  keys=['name','description']  name matches dir

bad frontmatter: 0/8
```

All 8: first line is `---`, closing `---` at line 3, **exactly two keys** (`name`, `description`), and
`name` matches its directory. Re-verified after this task's edits: still **0/8 bad**.

### `settings.json` never committed on this branch — confirmed

```
$ git log --oneline --name-only main..HEAD | grep -c 'settings.json'
0
```

**Expected 0, observed 0.** The pre-existing unstaged change to `settings.json` was not touched.

---

## Skill body sizes after fixes (bar: < 5,000 words)

```
1458  skills/_standards/authoring-skills-and-agents.md
1869  skills/designing-agentic-architecture/SKILL.md
1522  skills/setting-up-a-new-project/SKILL.md
2476  skills/securing-agentic-systems/references/seven-pillars.md
```

All comfortably within budget.

---

## Summary

| Step | Check | Result |
|---|---|---|
| 1 | Always-on budget ≤ 3,500 | **PASS** — 3,473 (27 words spare) |
| 2 | 33/33 source files represented | **FAILED first pass** — 15 gaps found; 13 fixed in-pass; **D-1 and D-2 closed in follow-up** → 15/15 |
| 3 | No phrase positive-triggers two skills | **PASS** — 24 positives, all distinct |
| 4 | No name collision; "Not for" clause | **PASS** — 0 collisions, 8/8 clauses |
| 5 | No false assurance | **PASS** — 2 always-on hits, both legitimate; 5/5 skill disclaimers present |
| 6 | Frontmatter valid | **PASS** — 0/8 bad |
| — | `settings.json` uncommitted | **PASS** — 0 |

**Open defects: none.** D-1 (docstrings) and D-2 (show the exact query) were promised to
`rules/general-engineering.md` by the coverage map and were blocked on 27 words of always-on headroom.
The user chose the **skills destination over always-on**: D-1 landed in `skills/writing-specs/SKILL.md`
and D-2 in `skills/integrating-mcp/SKILL.md`, both load-on-demand and therefore free of always-on cost.
The budget is untouched at **3,473** and the coverage map now names the real destinations.

The honest headline: the coverage audit was the check that mattered, and it did not pass clean. The
authoring standards — the file governing how every future skill gets written — had lost an entire
named section. That is exactly the class of defect a verification pass exists to catch, and it would
not have surfaced from a spot check.
