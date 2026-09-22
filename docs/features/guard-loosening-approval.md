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

**Task 0 is half resolved as of 2026-09-21. Its checkbox stays unticked: the design's exit
condition is the interactive half, and that half is still unmeasured.** No claim about how the
*feature* behaves has been demonstrated — nothing is built. What follows measures the **existing**
`ask` machinery the design depends on.

Probe shape: `git-guard.sh` has exactly one `ask` emission site (line 480), reachable only through
Guard 3 / `SCOPE_UNKNOWN`. `lib/classify-git-command.py:185-189` shows `_walk_globals` returns
blocking for bucket 2 (`GLOBAL_REDIRECT`) *and* bucket 3 (unrecognised), so a read-only
`git -c core.pager=cat status --short` reaches it. That command is the only shape proven to reach
the ask site **unshadowed** — a commit probe is invalid, because another hook's `deny`
(`doc-guard`, `test-marker-guard`) outranks an `ask` and the run would measure nothing.

| # | Claim | Evidence |
|---|---|---|
| 1 | Synthetic `PreToolUse` payload for that command → `permissionDecision: ask`, exit 0 | payload piped to the hook directly |
| 2 | Control `git status --short` → no output, exit 0 | discriminates; claim 1 is not a constant |
| 3 | **In a bypass-permissions session the ask command RAN** (printed `?? .local/`) | the `ask` did not block |
| 4 | Claim 3 is not "the hook never ran" — the hook is live on `Bash` | a deliberately unlexable command was **blocked** by Guard 0 `SEG_UNPARSED` (exit 2), refusal text surfaced |
| 5 | All four guards are registered `PreToolUse`/`Bash`; `settings.json` `permissions.defaultMode` is `default` | the bypass is a session runtime flag, not configuration |
| 6 | On the exit-0 `ask` path stderr was **not** surfaced; on the exit-2 deny path it **was** | scoped to bypass mode only — says nothing about the interactive case |

**What this settles.** Spec §4's second scenario is answered: under a pane subagent the `ask` is
**silently allowed**. The settled decision "refuse outright when unattended" (§2, 2026-09-16) now
rests on a measurement rather than an assumption. The sharpest consequence for §7: fail-closed must
mean **exit 2**, never `ask`, on any path required to hold under bypass mode — claims 3 and 4
together show a `deny` blocks and an `ask` does not, in the same session, from the same hook.

**What remains open.** Whether `ask` blocks in an interactive session at normal permissions. It
cannot be measured from inside a bypass-mode session, and no subagent lane substitutes: in-process
agents inherit the parent's mode, pane agents skip permissions by design. Put to the user
2026-09-21; not yet answered — their reply reported an unrelated `Stop hook` failure
(`hooks/handoff/handoff-keep-guard.sh` is registered at `settings.json:165,175` but has no execute
bit), which fires after the turn and therefore carries no information about whether a prompt
appeared. **Do not infer the outcome from it.**
