# Branch: feature/writing-project-readmes-skill

Started 2026-07-19. Brainstorm/triage: `coding-memory/brainstorms/writing-project-readmes.md`
(committed to main @ fe1b03b before branching).

## What this branch delivers

User-requested README standard: every project gets a README following the user's supplied
template; fires on demand AND automatically for new projects; the README's Roadmap section
stays current as features land.

- `skills/writing-project-readmes/SKILL.md` — check-then-create procedure (existence check
  first, facts gathered from manifest/license/CI/remote, no fabricated badges/links/logos,
  placeholder-grep verification) + Roadmap maintenance rules (features get lines,
  fixes/refactors/chores don't; updated on the feature branch before review).
- `skills/writing-project-readmes/assets/readme-template.md` — the user's template, kept
  structurally intact. One mechanical fix, flagged to the user: GitHub doesn't render
  markdown badge syntax inside block-level HTML, so the badge row became centered HTML
  `<img>` shields with real OWNER/REPO URL patterns.
- Trigger wiring: `setting-up-a-new-project` step 5 (README scaffold in the register),
  `preparing-pull-requests` Before-Requesting-Review bullet (feature PRs update the
  Roadmap), `CLAUDE.md` Skills Catalog line.
- No hook: feature-vs-refactor isn't script-decidable. Escalate to a gates stub/hook only
  if the PR-time check is observed being skipped (same deferred pattern as spec-guard).

## Test evidence (writing-skills TDD)

- RED (no skill, Sonnet subagent, fixture Node project `pulse-board` in scratchpad):
  competent generic README — no house header block, no badges, no Built With, wrong section
  order, **no Roadmap section at all**.
- GREEN (same fixture, skill + template loaded): exact template structure; all facts real
  (pinned dep versions, real env vars, real endpoint example); logo + license badge
  correctly omitted (assets don't exist); docs link pointed at README itself; no invented
  roadmap items; verification grep empty.
- Routing: 8/8 forced-choice phrases correct (3 positive, 3 negative, plus new-repo →
  setting-up-a-new-project and "standardize" → this skill).

## Judge round 1 (@ 3c5a826): risk=low conf=medium, one actionable finding

The skill's verification grep couldn't catch the template's bracketed guidance prose (only
OWNER/REPO, [Project Title], and literal "placeholder"), so leftover template text could
pass the skill's own check. Fixed at the root: every template placeholder now carries a
`[TODO: …]` marker and the verify step greps `OWNER/REPO|\[TODO:` — greppable by
construction, no false positives on markdown links/checkboxes. Deterministic re-verify:
25 marker hits in the raw template, 0 in the GREEN-generated fixture README.

## Status

- Judge round 2 @ 0d23feb: risk=low confidence=high, nothing blocking.
- **PR #17 OPEN**: https://github.com/suyatdev/.claude/pull/17 (created 2026-07-19; verdict
  matched HEAD at create time; verdict-store audit trail committed as follow-up push, which
  is docs-only and post-gate by design).
- Follow-up: dogfood the skill on the .claude repo itself (no README yet); backfill this
  verdict's outcome when the PR's real result is known.
