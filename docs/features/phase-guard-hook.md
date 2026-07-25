---
phase: planning
model_tier: high
branch: none
---

# phase-guard.sh — computational enforcement of the phase gate

> First feature to run under the `docs/features/` workflow introduced by ADR 0010 (PR #29).
> Friction in the create → gate → restore cycle is itself a finding worth recording here.

## Problem

ADR 0010 moved permission for a class of work out of the conversation and into a file's `phase`
frontmatter, so it survives a `/clear`. It stopped there deliberately: **the permission is
recorded, not enforced.** Nothing prevents a session from writing implementation code while
`phase: planning`. Both observability-judge rounds on PR #29 flagged this, and the ADR discloses
it as a consequence rather than hiding it.

This feature asks whether to close that gap with a `PreToolUse` hook, and if so, how.

## The objection this design must answer

ADR 0010 rejected the hook on one specific ground, quoted verbatim:

> Resolving "which feature file is active" is ambiguous during planning (`branch: none`), so the
> hook would have to fail open in exactly the phase it most needs to hold.

That is the crux. A design that cannot answer it should not be built — "we'll fail open when
unsure" reduces to a hook that is silent precisely when `phase: planning` is being violated, which
is worse than no hook because it *looks* like enforcement.

## Open questions — planning must resolve these before any spec is frozen

1. **Has the trigger condition actually been met?** ADR 0010 says build this "when the gate is
   observed being skipped, not before" (the `spec-guard` precedent). No skipped phase gate has been
   observed to date. Building now overrides the ADR's own stated deferral rule — a legitimate
   choice, but it must be a deliberate one, and it amends ADR 0010 rather than merely extending it.
2. **How does the hook identify the active feature file?** Candidates, none yet chosen:
   `branch:` reverse-lookup (works in `implementation`, useless at `branch: none`); a
   machine-local pointer written at the gate transition (doesn't ship, so a fresh clone is
   unguarded); "exactly one file whose `phase` is not `review`" (breaks on concurrent features);
   most-recently-modified. Each fails differently — the choice *is* the design.
3. **Fail open or fail closed on ambiguity?** `judge-guard.sh` fails closed (safety gate);
   `doc-guard.sh` fails open (momentum guardrail). Which is this? Failing closed on an
   unresolvable active-file lookup would block *all* writes in any repo lacking a feature file —
   almost certainly unacceptable, which is what makes question 2 load-bearing.
4. **What exactly is a guarded write?** Presumably `Edit`/`Write`/`NotebookEdit` whose `file_path`
   is a source path, excluding `docs/**`, the feature file itself, and machine-local `.claude/**`.
   The source/doc split already exists at `hooks/doc-guard.sh:149` (`CODING_MEMORY.md`,
   `coding-memory/*`, `docs/*`) and should be reused, not re-invented.
5. **Multi-repo behavior.** These hooks are global (`~/.claude/hooks/`) and fire in every repo.
   Most repos have no `docs/features/` at all. Absence must be unambiguously "not applicable",
   never "blocked".
6. **Does it supersede or complement the escape hatch pattern?** Both existing guards carry a
   logged env-var bypass (`JUDGE_EXEMPT`, `MERGE_EXEMPT`). Consistency argues for `PHASE_EXEMPT`.

## Prior art in this repo (read before designing — do not re-derive)

| File | Why it matters |
|---|---|
| `hooks/judge-guard.sh` | Fail-closed safety gate; `PreToolUse`, python payload parsing, strict-equality freshness check, logged env bypass. The closest structural sibling. |
| `hooks/doc-guard.sh` | Fail-open momentum guardrail; owns the source-vs-docs path classification this hook should reuse (`:149`). |
| `hooks/git-guard.sh` | The inline-regex parser trap documented in both files — regexes live in variables, never inline in `[[ ]]`. |
| `docs/decisions/0010-*.md` | The deferral being revisited, and its four rejected alternatives. |

## Spec

<Not yet written. Blocked on open questions 1–3, which are user decisions, not derivable from the
codebase. `writing-specs` governs the form once they are settled; the compliance judge gates it
before the user review.>

## Tasks

- [ ] <Not yet built. The checklist is written during planning and frozen at the gate; adding
      tasks after the gate opens is forbidden by the phase rules.>

## Verification

<Appended during review.>

## Notes for the next session

- Created in an isolated worktree (`.claude/worktrees/phase-guard-hook`, branch
  `worktree-phase-guard-hook`) because a **concurrent Claude session** was mid-rebase on
  `feat/pane-split-policy` in the primary checkout. That branch exists for parallel-session
  isolation only — it is **not** this feature's implementation branch, and `branch:` stays `none`
  until the gate opens.
- Unrelated loose end in the primary checkout: four `coding-memory/compliance-judge/*` files
  (other sessions' shared-store writes) were dropped from the working tree by that session's
  branch switch. Byte-verified backups are in this session's scratchpad under
  `other-session-files/`. They belong on `main`, not here.
