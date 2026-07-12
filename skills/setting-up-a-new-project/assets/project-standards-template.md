# Project Standards

The opt-in register for this repo, decided once and recorded here. Every section
records what was chosen, and why. `Undecided` is a legitimate answer — a recorded
gap is auditable; a fabricated answer is not.

- **Project:** <name>
- **Decided on:** <YYYY-MM-DD>
- **Decided by:** <who answered the register>
- **Revisit when:** <the event that makes these answers stale — e.g. "before the
  first external user", "when this leaves prototype", "if an MCP server gains
  write access", "at the next dependency upgrade">

---

## 1. Rigor Tier

**Chosen:** prototype / vibe-coding — or — production / agentic-engineering

**Why:** <what this project is for, and what breaks if it fails>

This tier gates every answer below. Moving between tiers means re-running the
register, not quietly editing one line.

## 2. Review Gate

**Chosen:** human gate on every PR — or — Conditional LGTM (auto-merge on green)

**If Conditional LGTM:** which branches, which checks must be green, and what is
excluded (e.g. dependency bumps, migrations, anything touching auth):

**Why:** <auto-merge is in tension with default-branch safety; record the reason
it was accepted here>

## 3. Hooks Installed in `.claude/settings.json`

| Hook | Installed? | Notes |
|---|---|---|
| Secret scan | yes / no | |
| Invisible-Unicode scan | yes / no | |
| Checkpoint-before-modify | yes / no | |
| <other> | | |

**Why:** <hooks are the only deterministic enforcement available; record what was
declined and why>

## 4. Spec Before Implementation

**Chosen:** required / optional / not used

**BDD-Gherkin mandated:** yes / no

**Where specs live:** `docs/superpowers/specs/` — or — <path>

## 5. Sandboxing

**Where agent-written scripts run:** host (unsandboxed) / container / other

> Default and current reality: **host, unsandboxed.** This setup has no container
> sandbox, no policy server, and no LLM firewall. Agent-written scripts run with
> the user's full privileges.

**If anything other than host, state what actually provides the isolation:**

**Compensating controls in place:** <e.g. checkpoint-before-modify hook, no
production credentials on the host, review before any script is executed>

## 6. `security:scan` Script

**Wired up:** yes / no

**Command:** <e.g. `npm run security:scan`>

**Verified to run on:** <YYYY-MM-DD — confirmed executed, not merely present in
the manifest>

## 7. MCP Servers

| Server | Purpose | Scope | Data it points at | Approved? |
|---|---|---|---|---|
| | | read-only / read-write | production / non-production | |

**Default is none.** Each server added is one more set of real permissions the
agent holds. Record the justification for every write-capable server, and every
server pointed at production data.

## 8. Eval-as-Unit-Test in CI

**Chosen:** required / optional / not applicable (no LLM-shaped behavior in this
repo)

**Eval suite location:**

**Minimum pass threshold:**

**Runs on:** every PR / nightly / manually

## 9. Model Routing

| Work type | Model tier |
|---|---|
| Architecture, design, gnarly debugging | frontier |
| Mechanical work (renames, scaffolding, formatting) | cheaper tier |
| <other> | |

**Why:** <any project-specific deviation from the default split>

## 10. Project `CLAUDE.md`

**Populated:** yes / no

**Location:** `CLAUDE.md` (repo root)

**Covers:** stack / conventions / hard rules / workflow

Grow this file by adding a rule each time the agent repeats a mistake. A project
`CLAUDE.md` that has not changed since it was created is a sign corrections are
not being fed back into it.

---

## Change Log

| Date | What changed | Who |
|---|---|---|
| | Register first completed | |
