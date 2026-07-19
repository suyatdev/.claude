---
name: writing-project-readmes
description: Use when a repo has no README.md, when asked to write or standardize a project README, or when a feature or implementation lands and the README's Roadmap section needs updating. Not for session memory docs (see managing-session-memory), PR descriptions (see preparing-pull-requests), or specs (see writing-specs).
---

# Writing Project READMEs

The README is a project's front door: the one file every visitor reads before deciding
whether to install, contribute, or leave. Every project gets one, and every one follows the
same house template — a shared structure means anyone can open any of our repos and find the
same things in the same places. The template is the contract; the facts come from the repo.

## When This Fires

- **On demand** — any request to create or standardize a README.
- **Automatically for new projects** — `setting-up-a-new-project` scaffolds the README as
  part of its register (that gate covers every new repo and every unconfigured existing one).
- **When a feature lands** — the Roadmap upkeep below; `preparing-pull-requests` carries the
  check at PR time.

## Creating a README

1. **Check for an existing one first:** look for `README*` (any case) at the repo root. If
   one exists, leave it alone — restructuring someone's existing README to the template is
   its own explicitly-requested task, never a drive-by.
2. **Gather facts before writing:** the manifest (name, description, scripts, dependencies),
   the license file, CI config, and the git remote (for OWNER/REPO). The template's example
   stack, commands, and code snippet are placeholders — every one gets replaced with what
   this repo actually uses.
3. **Copy the structure of `assets/readme-template.md` exactly** — section order, emoji
   headers, separators — and fill every placeholder from the gathered facts.
4. **Nothing fabricated:** a badge, link, logo, or screenshot only appears if its target is
   real. No LICENSE file → no license badge; no `images/logo.png` → drop the `<img>` and keep
   the centered title; no docs site → "Explore the docs" points at the README itself. A
   plausible-looking dead link costs more trust than an omitted one.
5. **Verify before committing:** `grep -nE 'OWNER/REPO|\[.*[Pp]laceholder|\[Project Title\]'
   README.md` must come back empty, and every remaining link must have a real target.

## Maintaining the Roadmap

The Roadmap section is a living record, not launch-day decoration — a roadmap that still
shows a shipped feature as unchecked tells visitors the project is unmaintained.

- **Seed it honestly:** shipped features as `- [x]`, known next steps as `- [ ]` (from the
  issue tracker, project memory, or the user — never invented).
- **When a feature or implementation lands:** update the Roadmap in the same branch, before
  review — check off the delivered item, or add it as `- [x]` if it was never listed. Add
  newly planned work as `- [ ]` while you're there.
- **Fixes, refactors, and chores don't get roadmap lines:** the Roadmap tracks capabilities a
  user can see, not internals. (Whether a change is a feature is exactly the judgment call a
  hook can't make — which is why this lives here and in the PR checklist, not in a script.)

## Trigger Phrases

Positive — this skill should fire:

- "this repo needs a README"
- "create a README for the project"
- "we shipped dark mode — update the roadmap"

Negative — this skill should *not* fire:

- "update CODING_MEMORY for this session" → `managing-session-memory`
- "write the PR description" → `preparing-pull-requests`
- "write a spec for the parser" → `writing-specs`
