# Observability Judge Verdict — feature/add-claude-code-handoff (implementation)

- **Date:** 2026-07-20T21:34:50Z
- **Repo:** .claude
- **Branch:** feature/add-claude-code-handoff
- **HEAD:** a9a84b740ccb34c3c143ad0c697305156d8d4eee
- **Stage:** implementation (gates the PR)
- **Base:** main (merge-base 69ecd127c17fd071304969f55465feab2cfa3bdb)
- **Design doc:** docs/decisions/0006-handoff-cherry-pick.md; execution detail in coding-memory/branches/add-claude-code-handoff.md
- **Verdict:** risk=medium, confidence=high

## What was changed

The previous commit installed a second, third-party "session memory" system
(claude-code-handoff) alongside the house one, running both in full. This commit is
the referee's whistle: the user decided, feature by feature (15 rows), which system
keeps each job, and the commit executes those picks.

Think of it as two overlapping alarm systems in one house — this commit assigns each
door to exactly one alarm. Concretely:

1. **settings.json** — two hook registrations removed: the handoff system's
   session-start restore (house wins that job) and doc-guard's pre-compaction check
   (the handoff trio wins that event). Doc-guard keeps its other two jobs
   (commit-blocking and session-start surfacing).
2. **hooks/handoff/live-handoff.sh** — a deliberate 1-line patch away from the pinned
   upstream: its file template now contains the HTML-comment marker that the file-edit
   tracker's `sed` needs. Upstream has a race where this script creates the state file
   without the marker, and the tracker then silently does nothing forever.
3. **skills/managing-session-memory/SKILL.md** — absorbs the "write for the NEXT
   context window" philosophy, names `/handoff` as the manual checkpoint command
   (complementing, never replacing, the committed CODING_MEMORY save+push), and adds a
   per-repo gitignore duty for the handoff state files.
4. **ADR 0006** — the full decision table, an event-ownership diagram, and the
   accepted risks, in writing.

## Does it do what was wanted?

Yes — verified, not assumed. Every check in the stated test evidence was re-run
independently by the judge:

- `jq empty` passes on both the worktree settings.json **and** the committed blob.
- `bash -n` passes on all six handoff scripts (not just the patched one).
- **Purity check reproduced:** stripping the Orca hook entries from the worktree
  settings.json and excluding the model line yields a byte-identical normalized JSON
  to the committed blob. Committed model is the generic `opus[1m]`; the machine-local
  `claude-fable-5[1m]` stays uncommitted, per standing policy.
- **Committed hook registrations match ADR 0006's diagram exactly** (SessionStart:
  doc-guard + memsearch-nudge; PreCompact: the handoff trio only; UserPromptSubmit:
  live-handoff; PostToolUse: post-edit-hook; PreToolUse: rtk/git-guard/doc-guard/judge-guard).
- **Tracker fix confirmed end-to-end:** the patched marker string in live-handoff.sh's
  INIT template is character-identical to the `sed` target in proactive-handoff.sh
  (lines 76–136), and the live state file `.claude/session-state.md` contains six real
  appended file entries with timestamps — the pre-fix behavior was a confirmed no-op.
- Every touched file maps to a decision-table row; no scope creep, no new dependencies,
  git-guard/judge-guard untouched as the ADR claims.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | All 15 picks executed exactly as decided; registrations match the ADR diagram |
| execution | pass | All stated checks re-run and reproduced; tracker fix verified live with real entries |
| trajectory | pass | Root-cause fix (marker in template) not a workaround; per-row decision table; honest handling of the lost-picks incident |
| regression | concern | rules/gates.md now makes a false claim about doc-guard; pre-compact git-status surfacing genuinely gone (see below) |
| context_budget | concern | live-handoff injects a 12–27 line directive on EVERY prompt — permanent always-on cost, accepted knowingly with a revisit trigger |
| traceability | pass | ADR + branch log + provenance header on the patched script + commit message all cross-reference |
| success_masking | concern | ADR wording overstates the PreCompact replacement; AskUserQuestion during unattended autocompaction can silently stall the "guaranteed" save |
| intent_drift | pass | Every change maps to a pick; local upstream divergence documented and necessary |
| checkpoint | pass | Vendor commit then cherry-pick commit — each a clean revert point; machine-local material kept out of the blob |
| audit_trail | pass | ADR 0006, branch log, CODING_MEMORY, attributed commit with co-author trailer |

## Concerns (honest, in priority order)

1. **Stale always-on rule file (found by the judge, not disclosed):** `rules/gates.md`
   line 10 still says doc-guard "surfaces uncommitted work before a `/compact`". This
   commit removed doc-guard's PreCompact registration and gates.md was not touched on
   the branch — so a rule file loaded into every session now documents an enforcement
   behavior that no longer exists. One-line fix; should land before merge.
2. **The pre-compact uncommitted-work warning is gone, not transferred.** ADR 0006 says
   "pre-compact warnings about uncommitted work now ride on the handoff trio" — but
   none of the three trio scripts runs `git status` or mentions uncommitted work at
   all (verified by reading all three). The trio preserves *conversation* state; the
   *git working tree* check is simply gone at that event. The remaining backstop is
   doc-guard's next-session-start surfacing. The decisions summary was honest about
   this loss; the ADR's phrasing is optimistic.
3. **Unattended autocompaction can stall or lose the save.** pre-compact-handoff.sh
   directs AskUserQuestion in task/bug modes; at an unattended context-limit
   compaction there may be nobody to answer. Accepted knowingly in the ADR — accepted
   does not mean absent.
4. **Per-prompt injection cost is permanent** while registered — a standing tension
   with the Context Discipline rule, accepted with a documented revisit condition.
5. **Tracker fix verified in this repo only**, not re-verified in a scratch repo where
   live-handoff wins the creation race from a cold start (this repo's state file was,
   however, created by exactly that race — so the tested scenario is the right one).
6. **This repo gitignores all of nested `/.claude/`** while the new skill rule says
   "specific files, not all of `.claude/`". The exception is documented in the
   .gitignore comment (this repo is itself the toplevel), but it's the kind of
   pattern that gets copy-pasted into project repos where it would swallow committed
   settings.

## What to double-check before merging

- Fix the gates.md line about doc-guard's `/compact` surfacing (concern 1) — or
  consciously log it as a follow-up.
- Decide whether the ADR's "warnings now ride on the trio" sentence should be tightened
  to "session-state is saved by the trio; the git-status warning now happens only at
  next session start."
- Watch the first real autocompaction with an active task/bug file for the
  AskUserQuestion stall.
