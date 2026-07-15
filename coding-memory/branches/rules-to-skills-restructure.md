# Branch Implementation Log: feature/rules-to-skills-restructure

**Status:** MERGED 2026-07-15. All 12 plan tasks complete, final whole-branch review (Opus) passed
with only 2 Minor items (both fixed). PR #9 merged to `main` as a fast-forward, at the user's
request, rather than waiting for GitHub review. Branch deleted (local + remote).

## What changed

Implements `docs/superpowers/specs/2026-07-14-rules-to-skills-restructure-design.md` per the plan at
`docs/superpowers/plans/2026-07-15-rules-to-skills-restructure.md`, executed via
`superpowers:subagent-driven-development` (fresh implementer subagent + independent task-reviewer
subagent per task).

- Replaced 7 always-loaded rule files with `rules/core-conduct.md` (permanent invariants) and
  `rules/gates.md` (short stubs for judgment-based gates, each pointing at the skill with the
  procedure).
- Added 5 new skills: `managing-session-memory`, `preparing-pull-requests`, `writing-secure-code`,
  `allocating-local-ports`, `triaging-new-instructions`.
- Merged zero-trust rationale and delegation-mode content into the existing
  `securing-agentic-systems` and `designing-agentic-architecture` skills.
- Added `hooks/git-guard.sh`, a `PreToolUse` hook blocking commits to `main`/`master` (except a
  `CODING_MEMORY.md`-only brainstorm commit) and bare force-pushes; registered in `settings.json`.
- Deleted the 7 original rule files. Always-on context per turn: 4,030 → 1,151 words (~71% cut).

## Branch setup note

This branch forked from `main` at the PR #8 merge commit. Task 1's own `git checkout main` wiped
two commits from the working tree that had been pushed to `feature/new-project-memory-scaffold`
*after* PR #8 already merged (a `.gitignore` anchor fix + this restructure's own plan doc) — they
were orphaned off-branch the same way PR #6/#7's trailing commits had been earlier in the session.
Recovered via `git cherry-pick` onto this branch (commit `532bae2`) rather than re-authoring; both
files verified byte-identical to the originals.

## Review findings worth remembering

- **Task 11 (the deletion task) is where real gaps surfaced**, not in the individual skill-creation
  tasks — those were all byte-for-byte transcriptions from a plan that had already been through a
  self-review pass, and reviewed clean on the first pass every time.
- The Task 11 review caught two things the *plan itself* hadn't scoped:
  1. **Content loss:** the old `general-engineering.md`'s "Guiding Principle" paragraph (prioritize
     simplicity/maintainability, judge trade-offs on a 6-month horizon) was silently dropped during
     Task 10's rewrite of `core-conduct.md` and existed nowhere in the new structure. Restored.
  2. **Dangling references:** ~12 other live files (`README.md`, `SETUP.md`, `hooks/README.md`, 5
     skill files, `CODING_MEMORY.md`, `PORTS.md`) still named the 7 just-deleted filenames. The
     original plan only accounted for `CLAUDE.md`'s own imports — not other files in the repo that
     happened to reference the old rule files by path.
- The **first fix pass introduced a second-order bug**: `rules/pr-requests.md`'s content had
  fissioned into two different new homes during the restructure (`rules/gates.md` for the
  deterministic hook-enforced gates, `preparing-pull-requests` for the workflow/procedure content),
  and a uniform single-target repoint mapped 2 gate-specific sentences to the wrong one of the two —
  no longer dangling, but now factually inaccurate. A third review pass caught this before merge.
- **Lesson for future restructure-style plans:** an audit table that maps *source* content to
  *destinations* doesn't by itself catch *other files that reference the source by name* — that
  needs its own explicit sweep (a repo-wide grep for the old paths) as a planned step, not an
  incidental review catch.

## Final whole-branch review (Opus, post-Task-12)

Ready to merge: Yes, on first pass. Confirmed independently: 3-tier architecture matches the
design, a repo-wide dangling-reference sweep was completely clean, all 3 of Task 11's fix rounds
landed correctly, `git-guard.sh` is portable and sound, the skill library is internally consistent.
4 Minor findings:
- Fixed: the restored Guiding Principle sentence had dropped "reliability" and "cost and" from the
  original wording; `git-guard.sh`'s force-push guard scope (misses `+refspec` form) is now
  documented as an intentional momentum-guardrail limitation, not a gap.
- Accepted, no action: an audit-table wording gap on where the Conditional-LGTM note landed
  (content fully preserved, just organized differently than predicted); gitignored/untracked
  auto-memory files outside this repo still name old rule paths (follow-up housekeeping, not this
  PR's scope).

## Outcome

1. Merged locally to `main` as a fast-forward (`dd6f59f..097913f`) — the user chose to merge
   directly rather than wait for GitHub review, since the branch had already been through 12
   per-task reviews plus a final whole-branch review.
2. GitHub auto-detected the fast-forward and marked PR #9 as merged.
3. Both `feature/rules-to-skills-restructure` and the fully-superseded `feature/new-project-memory-scaffold`
   deleted (local + remote).
