# Brainstorm: writing-project-readmes (2026-07-19)

## What the user asked for

1. Every project gets a GitHub README following a provided template (logo/banner header,
   badges, About, Built With, Getting Started, Usage, Roadmap). Check whether one exists;
   create it if missing.
2. Fires **both** on demand ("write a README") **and** automatically for every new project.
3. The README's **Roadmap section stays current**: whenever a new feature or implementation
   lands in a project, the roadmap gets updated.

The full template was supplied by the user in-session and is preserved verbatim-in-spirit in
`skills/writing-project-readmes/assets/readme-template.md` (see "Template fidelity" below).

## Triage classification (`triaging-new-instructions`)

- **README creation** → judgment work during a specific activity → **new skill**
  `writing-project-readmes`, template stored as an asset (templates belong in `assets/`,
  loaded only when reached for).
- **Automatic on new projects** → the trigger already exists: the new-project setup gate
  (`setting-up-a-new-project`) fires on every new repo and on first substantial work in an
  unconfigured one. **Extend that skill's scaffold steps** — extend, don't duplicate a trigger.
- **Roadmap-on-feature-landing** → not script-decidable (no script can tell a feature from a
  refactor or fix), so **not a hook**. Procedure lives in the new skill; a one-line check is
  added to `preparing-pull-requests` (Before Requesting Review), which already loads at the
  moment a feature PR is prepared. If this is ever observed being skipped, escalate to a
  gates.md stub or hook — same deferred pattern as the spec-compliance gate.

## Decisions

- **Name:** `writing-project-readmes` — gerund, kebab-case, matches house style
  (`writing-specs`, `writing-secure-code`). Creation + roadmap upkeep are one job (one
  artifact, one owner), not an "and" of unrelated capabilities.
- **Template fidelity:** the user's template is kept structurally intact. One mechanical fix:
  GitHub does not render markdown image/badge syntax inside block-level HTML (`<div>`), so
  badges move outside the centered div using standard shields.io badge markdown. Flagged to
  the user rather than silently changed.
- **No fabrication rule carried into the skill:** badges, links, and Built With entries must
  reflect the actual repo (real CI, real license, real stack) — placeholder URLs from the
  template must never ship unresolved.
- **Model gate:** user chose Opus 4.8 for this work at the session's AskUserQuestion
  checkpoint (session had been running Fable 5; switch is user-side via /model).

## Test plan (writing-skills TDD)

- RED: subagent in a scratchpad repo, no skill → README deviates from template (documented).
- GREEN: same scenario with SKILL.md + template in context → conforming output.
- Routing: 3 positive + 3 negative trigger phrases verified against the description.
