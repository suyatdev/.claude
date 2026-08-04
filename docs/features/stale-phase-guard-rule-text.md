---
phase: review
model_tier: low
branch: fix/stale-phase-guard-rule-text
---

> **CLOSED.** Merged to `main` 2026-08-04 as PR #37 (merge commit `beb7e33`). Finished record — do
> not reopen. Follow-ups it deliberately did not do are on the queue, not here.

# Correct the stale "phase-guard is dormant" claim in the live rule set

## Why

`rules/gates.md` is read at the start of every session. It currently states twice that
`hooks/phase-guard.sh` is **not registered in `settings.json`** and therefore never runs. That is
false: the hook was registered when PR #30 merged and has been live since. A rule file that
understates its own enforcement is worse than a silent one — every session plans around a guard it
believes is absent, and the first surprise is a denial nobody expected.

`CODING_MEMORY.md` carries the same claim in its own words ("FIVE OF THE 17 SCRIPTS … ARE NOT
REGISTERED"), with a "Live hooks are…" list that omits phase-guard.

This is a documentation-accuracy fix. **No hook, script, or setting changes.**

## Verified state (measured 2026-08-04, not inferred)

| Fact | Evidence |
|---|---|
| `phase-guard.sh` is registered | `settings.json:42-49` — PreToolUse, matcher `Edit\|Write\|NotebookEdit` |
| Dormant hooks number **four** | `checkpoint-before-modify`, `require-project-standards`, `scan-invisible-unicode`, `scan-secrets` — zero occurrences each in `settings.json` |
| `hooks/` holds **twelve** non-test scripts | `ls hooks/*.sh` minus `.test.`/`replay` |
| **Eight** are registered | git-guard, doc-guard (×2), judge-guard, merge-guard, pane-dispatch-guard, context-handoff-watch, memsearch-nudge, phase-guard |
| Committed vs live `settings.json` | Differ **only** in the machine-local `model` line; all hook registrations byte-identical. ⚠️ First measured with `git status --porcelain`, which is **unsound here** — `skip-worktree` is set (`git ls-files -v` → `S`), so status is blind to this file by design. Re-measured with `git show HEAD:settings.json \| diff - settings.json` |

## The correction must not overshoot

Only the **planning half** of the phase gate is hook-enforced: source writes are denied while an
un-superseded `phase: planning` feature file exists and no `implementation` file records the current
branch. The **implementation half** — refusing spec and checklist edits once implementation starts —
is a deliberate non-goal of the hook and remains judgment-only.

Rewriting the text as a flat "the phase gate is enforced" would replace an understatement with an
overstatement. Both halves must be named explicitly.

Scope note: `phase-guard.sh` exempts `CODING_MEMORY.md|coding-memory/*|docs/*|.claude/*|
settings.json` (`:288`). `rules/` is absent from that list, which is why this branch needs this
feature file to be able to edit `rules/gates.md` at all. Whether `rules/` belongs in the exempt list
is a real question — deliberately **not** settled here; logged to the queue instead.

## Tasks

- [x] 1. `rules/gates.md:5` — drop the "⚠️ Judgment-only in both halves right now … not registered"
      sentence; state that the planning half is hook-enforced and the implementation half is not.
      · Also names the exempt list and flags that `rules/` is absent from it — the reason this
      branch needed a feature file at all.
- [x] 2. `rules/gates.md:15` — remove `phase-guard.sh` from the Dormant-hooks bullet; five → four.
- [x] 3. `CODING_MEMORY.md:980-989` — "FIVE OF THE 17" → four of twelve; add phase-guard to the
      "Live hooks are…" list; keep the entry's open-work point about the unwired scanners.
      · Also records that the committed≠armed split behind the original entry is now closed.

## Verification

| Check | Result |
|---|---|
| No stale dormancy claim left in `rules/`, `CODING_MEMORY.md`, `CLAUDE.md` | **Pass** — re-grep for `not registered\|never run\|dormant\|judgment-only in both` returns only the three corrected passages plus two unrelated uses (`CODING_MEMORY.md:521`, `:2053`) |
| `CODING_MEMORY.md:2053` (separate dormant-hook list) | **Already correct** — names the same four, omits phase-guard. Untouched |
| `phase-guard.sh` enforcement observed | **Indirect.** Registration read at `settings.json:42-49`; no denial observed this session, because the `implementation` feature file was created *before* the first `rules/` edit. Prior direct observation is the Defect B block of 2026-08-03 |

**Out of scope, found while verifying — not fixed, logged instead:**

- `CODING_MEMORY.md:2048-2051` asserts `git-guard.sh`, `merge-guard.sh` and `doc-guard.sh` have **no
  test suite at all**. PR #36 reported git-guard at 77/0, so that entry is likely stale itself.
- `CODING_MEMORY.md:2052-2054` says of the four dormant hooks "unverified which; verify before
  designing anything." This branch verified it — all four have zero occurrences in `settings.json`.
- Whether `rules/` belongs in `phase-guard.sh`'s exempt list is a genuine open question. Editing the
  rule set is not source work, but it is also not obviously docs. Deliberately left undecided.
