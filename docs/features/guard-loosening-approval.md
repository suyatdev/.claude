---
phase: implementation
model_tier: high
branch: feat/guard-loosening-approval
---

# Guard-loosening stops and asks for approval

Spec: `docs/superpowers/specs/2026-09-20-guard-loosening-approval-design.md` — **read it for the
design.** This card carries frontmatter, status and the task list only; the two are deliberately not
duplicated, because two documents describing the same work means a reader cannot tell which is wrong.

**Status 2026-09-20: GATE CONFIRMED by the user. Phase is `implementation`, branch
`feat/guard-loosening-approval` (cut from the spec commit `1d0f03c`). No code written yet — the
transition was made and the session cleared immediately after, which is the mandatory `/clear`
point the gate calls for.**

⚠️ **No DESIGN content in the spec has been amended since it was written.** Two *status* lines were
corrected on 2026-09-21 — its header and §12 still said "no implementation branch exists" and "no
branch, no code until the user types `gate confirmed`", both of which the gate transition itself had
made false. A reader arriving at the spec would have concluded the gate was still shut. The
correction is marked in place in the spec.

If the user's reading produces changes to the **design**, those re-trigger the compliance gate
before more code is written. A status line falsified by a transition is bookkeeping, not redesign —
do not use that distinction to smuggle a design change through.

## The one-line problem

Widening a security guard's permission list is caught today only by `hooks/git-guard.replay.sh`,
which **nothing runs** — 0 registrations in `settings.json`, no CI (measured 2026-09-20). This makes
a loosening stop and ask a human in the moment.

## Decisions settled — do not relitigate

Six, recorded with dates in the spec's §2: what to check (targeted, not a 164-second replay); which
three guards; refuse when unattended; approval lifetime; **one shared watcher hook** (2026-09-20);
**reuse `secret_approval.py` but prove the key shape first** (2026-09-20).

## ⚠️ Read before planning any task

- **This gates a loosening being *proposed*, never the moment it goes live.** Hooks run from the
  primary checkout, so a loosening on a branch is inert until merge. PR review stays the last line.
  Never describe this as the final defence.
- **Momentum guardrail, not a security boundary** — the approval record is agent-written and
  therefore forgeable from inside a session.
- **Two of the three guards cannot prompt at all** (`permissionDecision` count: git-guard 3,
  secret-command-guard 0, worktree-guard 0 — re-measured 2026-09-20).
- **Pane subagents run with `--dangerously-skip-permissions`**, which is *why* unattended refuses.

## Tasks

⚠️ **Task 0 is a blocking gate with a real stop condition, not a warm-up.**

- [ ] **0. Prove the `ask` path actually blocks a commit.** Spec §4. Never live-verified; a comment
      in `git-guard.sh` records it as a pending manual acceptance test. Measure both the interactive
      case and the pane-subagent case.
      **If the prompt does not block → STOP and return to the user. The design needs rethinking,
      not patching.** Nothing below starts until this resolves.
- [ ] 1. Answer open question §9.2: define, **per guard**, what "the permission list" actually is,
      and verify each extraction against the real file rather than assuming a shape. Three different
      shapes across the three guards.
- [ ] 2. Put open question §9.1 (merge commits) to the user. Do not guess a default.
- [ ] 3. Prove the `secret_approval.py` key shape discriminates (spec §8) — falsified against an
      always-match and a never-match stub, since a non-discriminating key fails permissively.
- [ ] 4. Write the failing tests for §6.1/§6.2/§6.3, including the always-allow and always-deny stub
      falsifiers required by §10. Tests and implementation never in the same step.
- [ ] 5. Implement the watcher hook (spec §5), fail-closed per §7.
- [ ] 6. Make `EXPECTED_RELAXED` a record written by the approval rather than hand-edited (§5.4).
- [ ] 7. Register it in `settings.json` beside `doc-guard.sh` / `test-marker-guard.sh`.
- [ ] 8. ADR under `docs/decisions/` — the fail-closed direction is deliberately opposite to
      `secret-command-guard.sh` and needs its reasoning recorded. ⚠️ Check the next free ADR number
      against **every remote head**, not just `origin/main`; unmerged branches claim numbers.
- [ ] 9. Update `rules/gates.md` and `hooks/README.md` in the same change that makes them wrong.

## Verification

Not started. Nothing here has been run, and no claim in the spec about how the feature *behaves* has
been demonstrated — only the §3 measurements of the existing code have, on 2026-09-20.
