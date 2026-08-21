# 0032 — Track `settings.json` whole, churn and all

**Status:** Accepted
**Date:** 2026-08-21
**Supersedes in part:** `9cc792f` ("untrack settings.json and stats-cache.json")
**Feature card:** `docs/features/settings-split-tracked-and-local.md`

## Context

`9cc792f` untracked `settings.json` on the grounds that it is a machine-specific runtime file.
The churn it named is real: `/model` rewrites `model` and `effortLevel` in place, so the file goes
dirty every time the session model changes.

But `settings.json` is also the only thing that registers the scripts in `hooks/`. Untracked, a
clone gets `git-guard.sh`, `doc-guard.sh`, `phase-guard.sh`, `judge-guard.sh` and the rest as
files on disk with nothing switching them on — and nothing announces their absence. It is the same
"advertised protection that is not protecting" shape `rules/gates.md` already calls out for the
four dormant hooks, except this version disables guards that *were* working. Three registration
suites failed for that reason, and `SETUP.md` told a new machine the file would arrive with the
clone, which had stopped being true.

The obvious repair was to split the file: wiring in a tracked `settings.json`, preferences in a
gitignored `settings.local.json`. That is what the feature card planned.

## Decision

**Track `settings.json` whole.** No split. The ten `.orca/agent-hooks` entries are rewritten from
the hardcoded `/Users/marksuyat` path to `"$HOME/.orca/agent-hooks/claude-hook.sh"`, which
satisfies `core-conduct`'s no-absolute-paths rule inside the tracked file. `model` and
`effortLevel` stay in it, and the resulting churn is accepted.

## Why not the split

Three experiments, in the order that killed the alternatives.

**1. The destination is not a settings source.** Claude Code has four settings scopes —
`userSettings` (`~/.claude/settings.json`), `projectSettings` (`<project>/.claude/settings.json`),
`localSettings` (`<project>/.claude/settings.local.json`) and `policySettings`. The local tier has
no user-scope member. A file at `~/.claude/settings.local.json` containing
`{"model": "claude-haiku-4-5-20251001"}` left the session running `claude-opus-5[1m]`; the
identical file at `<cwd>/.claude/settings.local.json` switched it to haiku. A hook registered in
the user-scope local file never fired, and a deliberately malformed one raised no parse error at
all, so the file is not merely ignored — it is never opened.

The card's supporting evidence for the split (`strings … | grep -c settings.local.json` → 103)
counted a project-scope feature and read it as a user-scope one. String presence in a binary is
not evidence about which path is resolved.

**2. Nothing would have stayed split anyway.** `/model` writes `model` and `effortLevel` into
`~/.claude/settings.json`. Observed on this machine: both keys changed there at 12:31 on
2026-08-21 when the session moved from `sonnet`/`medium` to `opus[1m]`/`xhigh`. Hand-moving them
into another file lasts exactly until the next `/model`. The writer targets the tracked file by
design; relocating the keys does not redirect the writer.

**3. A `.gitattributes` clean filter is not a safe substitute.** It does work for the visible
symptom: with a clean script deleting `model`/`effortLevel`, the stored blob really loses them and
`git status` reads clean while the working copy keeps them. But a clean filter with no smudge half
means the stored blob *is* the checkout content, so any operation that materialises a new version
of the file overwrites the local values. Confirmed in a throwaway repo for both `git checkout` and
`git merge` when the incoming branch changed `settings.json`. Registering a new hook is exactly
that operation — the failure fires on the one workflow this decision exists to enable, and fires
silently.

**Recorded so it is not re-proposed:** the filter idea looks correct right up to the first branch
that edits the file. Anyone reaching for it again needs the smudge half and a second file, which is
the generate-from-source design, with its own drift surface and its own tests.

## What the churn actually costs

Only a deliberate `/model` rewrites the file. Measured: `settings.json` was last modified at 12:31
and still untouched at 13:49, across roughly eight intervening headless sessions. So the cost is a
two-line diff after an intentional model switch, not continuous noise.

Hooks merge rather than replace — three distinct hooks registered in user, project and
project-local settings all fired for one `SessionStart`. That was the card's original worry and it
turned out to be unfounded, but it is worth recording: adding a project-scope
`.claude/settings.json` to a repo does not endanger the user-scope guards. `policySettings` was not
exercised; the claim covers the three scopes actually tested.

## Consequences

- A fresh clone gets working guards. The three registration suites go 29/1 → 30/0, 26/27 → 27/27
  and 28/29 → 29/29.
- Hook registration regains an audit trail: switching a guard off is a reviewable diff again.
- The first commit bakes in whatever model is selected. Today that is `opus[1m]` at `xhigh`, which
  is the right default for a new machine — the card's original fear was `sonnet`, and the value is
  re-read from the staged blob rather than trusted. A future re-track done while a throwaway model
  is selected would commit that instead.
- **A pull will refuse to land this file** on any checkout holding an untracked
  `~/.claude/settings.json` whose bytes differ — which the `$HOME` rewrite guarantees. `SETUP.md`
  carries the move-aside step.
- The failure mode to watch is a stray `git commit -a` sweeping someone's model choice into the
  repo. No guard covers that; it is a two-line revert when it happens.
- `~/.claude/.claude/settings.local.json` — project scope, already gitignored by `.gitignore:78`
  (`/.claude/`), already holding `permissions.allow` grants and `outputStyle` — is untouched. It
  remains the right home for preferences that only apply to sessions rooted in this repo, and the
  wrong home for anything that must apply everywhere.
