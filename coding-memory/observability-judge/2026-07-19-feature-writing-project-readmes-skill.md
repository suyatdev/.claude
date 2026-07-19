# Observability Judge Verdict — feature/writing-project-readmes-skill (implementation)

- **Repo:** .claude
- **Branch:** feature/writing-project-readmes-skill
- **HEAD:** 3c5a826e248ee55ba38d864b7c49359f29e581b9
- **Stage:** implementation
- **Timestamp:** 2026-07-19T06:08:18Z

## What was changed

One commit (`3c5a826`, 7 files, +236/−6) adds a house standard for project READMEs. Think of it
as a recipe card added to the kitchen binder: a new skill `writing-project-readmes` holds the
procedure (check for an existing README first, gather real facts from the repo, fill the user's
template, never invent badges/links/logos, grep for leftover placeholders before committing) and
the user's template lives beside it as `assets/readme-template.md`. Three small wires connect it
to existing workflows: `setting-up-a-new-project` gained a step 5 (scaffold the README during the
new-project register, old step 5 renumbered to 6), `preparing-pull-requests` gained one
Before-Requesting-Review bullet (feature PRs update the README Roadmap in the same branch), and
`CLAUDE.md`'s Skills Catalog gained one line. The rest is the required memory documentation
(CODING_MEMORY index update + new branch log).

## Does it do what you wanted?

Yes, on all three user asks, and I verified each against the actual files rather than the
summary:

- **Template-based creation on demand** — the skill body and description cover it; the template
  preserves the user's structure (centered header div, badge row, emoji section headers, section
  order ending at Roadmap). The disclosed mechanical fix is real: GitHub does not render markdown
  badge syntax inside block-level HTML, and the shipped fix (HTML `<img>` shields in a centered
  `<p>`) renders correctly while keeping the badges centered.
- **Automatic for new projects** — correctly implemented as an extension of the existing
  new-project register rather than a new trigger; I checked the renumbering (5→6) and grepped for
  stale step-number cross-references: none exist.
- **Roadmap upkeep on feature landing** — procedure in the skill plus the PR-checklist bullet.
  The no-hook call is sound and matches house precedent (spec-guard's deferred-hook pattern):
  feature-vs-refactor is a judgment a script cannot make.

The trajectory is disciplined: triage per `triaging-new-instructions` was done and committed to
main (`fe1b03b`) *before* branching, the skill meets the authoring standards (gerund kebab-case
name matching its directory, description with explicit exclusions, template in `assets/`, 65-line
body, no absolute paths or secrets), and the anti-fabrication rules directly serve the standing
zero-trust convention.

## What could go wrong / what I'm unsure about

- **The skill's own placeholder safety net has holes (success_masking: concern).** I ran the
  skill's step-5 verification grep against the template itself. It catches `OWNER/REPO` leftovers
  and `[Project Title]`, but it does NOT match the multi-line bracketed guidance blocks (the
  About/Built With/Usage/Roadmap prompts like `[A clear, brief overview paragraph…]`) because
  those lines contain neither the word "placeholder" nor the full trigger pattern on one line. So
  a generated README could pass the skill's own check while still containing template prose. The
  primary instruction ("fill every placeholder") plus the GREEN evidence mitigate this; the net
  is real but roughly half-meshed.
- **Behavioral evidence is second-hand.** The RED/GREEN subagent runs and 8/8 routing results are
  documented in the branch log, but the fixture lived in a session scratchpad and no test log was
  committed, so I could not re-run any of it. Everything statically checkable checked out; the
  behavioral claims I have to take on the record.
- **Minor plan-vs-shipped divergence, accurately recorded at HEAD.** The brainstorm on main says
  badges would move *outside* the div as markdown badges; the shipped template instead uses HTML
  `<img>` shields *inside* a centered `<p>`. Both fix the same rendering problem and the final
  approach is better (keeps centering); the branch log and decisions summary describe the shipped
  mechanism correctly, so the audit trail is consistent — the brainstorm just reflects the
  earlier idea.
- **Standing item:** the uncommitted `settings.json` working-tree mod persists — pre-existing,
  disclosed, not in the branch diff, and structurally unable to ride into a PR.

## What I'd double-check before merging

1. Consider widening the verification grep (or adding a second pattern for any remaining
   `^\[` / `\]$` bracketed guidance lines) so the safety net matches the template's actual
   placeholder style — a one-line follow-up, not a blocker.
2. Skim the template once more as the user: it is their supplied artifact, and the badge-row
   HTML conversion is the one deviation they should sign off on having seen rendered.
3. Nothing else — the wiring edits are additive and I found no stale cross-references.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | All three asks delivered; template structure preserved |
| execution | pass | Static checks clean; grep/wiring/renumbering verified by hand |
| trajectory | pass | Triage-first, extend-don't-duplicate, deferred-hook per precedent |
| regression | pass | Additive edits only; no stale step references |
| context_budget | pass | +1 always-on CLAUDE.md line; everything else on-demand |
| traceability | pass | Brainstorm on main pre-branch + branch log; deviation disclosed |
| success_masking | concern | Verification grep misses bracketed guidance placeholders |
| intent_drift | pass | No drive-bys; memory edits are the required documentation |
| checkpoint | pass | Clean single commit; brainstorm committed before branching |
| audit_trail | pass | Attributable; no-ADR classification recorded with rationale |

## Concerns

1. Skill's placeholder-verification grep cannot catch the template's multi-line bracketed
   guidance text (no "placeholder" keyword, pattern is line-bound) — the skill's own check can
   pass with template prose remaining in a generated README. Low severity, cosmetic blast radius.
2. RED/GREEN/routing evidence is subagent-reported prose in the branch log; fixtures were
   session-scratchpad and no test log was committed, so the behavioral claims are not
   independently re-runnable.
3. Brainstorm's badge-fix mechanism (markdown badges outside the div) differs from the shipped
   one (HTML shields in a centered `<p>`); final records are accurate, brainstorm is superseded.
4. Pre-existing uncommitted `settings.json` mod still in the working tree — disclosed,
   unrelated, cannot enter the PR.

**risk=low confidence=medium**
