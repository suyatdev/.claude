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

**Status 2026-10-28: task 1 DONE. Still no implementation code.** The branch was merged up to
`origin/main` first (it was 192 commits behind, and `git-guard.sh` had moved 71 lines and
`classify-git-command.py` 83 since, when ADR 0051 / PR #119 landed — so the September measurements
no longer held for that guard). Answer recorded in
`docs/decisions/0052-the-permission-list-is-not-in-the-guard-file.md`.

⚠️ **Task 1 falsified three statements in the spec. Do not read §5 or §9.2 as current.**
1. §5.1's "fires only when the commit stages one of the three watched guard files" — the watch set
   is **fourteen** files. `secret-command-guard.sh` holds **zero** permission entries; all eight
   patterns are in `hooks/lib/classify-secret-command.py:137`. A watcher keyed on the three guard
   filenames fails **open, silently**.
2. §5.1's flowchart has two outcomes after a successful parse. A **third** is required —
   *changed, but direction unknowable* — and it must prompt. Direction is derivable only for
   whole-entry add/remove in a recognised list.
3. §5.2's "tightening passes silently" therefore holds for list-entry edits only.

⚠️ **Two requirements the task list does not yet carry.** Recorded here rather than inserted into
the list, because the phase gate forbids checklist edits under `phase: implementation` — fold them
into tasks 4/5 at the next phase boundary, or on the user's say-so:
- **Extract the git file mode alongside the blob.** A `100755` → `100644` flip leaves content
  byte-identical and a `100644` hook cannot start, so no content diff can see it.
- **Human review of the direction tables** (ADR 0052, decision 4) is a gate before the watcher
  ships. ALLOW/BLOCK is hand-assigned in all three extractors, never derived from the code, and a
  mis-tag fails permissively. Nobody has reviewed that mapping.

Also discharged: the "second active card may overlap" warning. `feat/git-guard-quiet` is fully
merged into `origin/main` (its card is `phase: review`), so it is part of the baseline now, not a
competing edit to `git-guard.sh`.

**Status 2026-10-28 (second block): tasks 2 and 3 DONE. Still no implementation code.**

**Task 2 — §9.1 answered → ADR 0053.** The watcher skips a merge whose incoming content is already
an ancestor of `origin/main`, and prompts otherwise; **any non-zero exit of
`git merge-base --is-ancestor` prompts**, including `128` for a missing ref. Measured live on a
fixture repo: pull-main-into-branch → silent, branch-into-branch → prompt, no `origin/main` →
prompt. ⚠️ **The historical noise split is NOT recoverable** — two proxies disagree (0 of 76 vs 16
of 39) because git does not retain `origin/main`'s past position. An earlier "33 silent, 6 asked"
figure came from commit subject lines and is **withdrawn**; do not reuse it. 37 of the 76 watched-file
merges are GitHub server-side and unreachable by any local hook.

**Task 3 — the state key discriminates, conditional on a serializer that does not exist yet.**
Probe: `hooks/secret-approval-state-key.probe.sh`, re-run with `bash hooks/secret-approval-state-key.probe.sh`
from the worktree root. 33 assertions over S1 = the HEAD blobs **and git modes** of all fourteen
watch-set files. Real 33/33; always-match stub 6/33; never-match stub 25/33; **passed by both: 0**.

⚠️ **Read the three caveats before building on that, in this order.**
1. **The "real" column tests a serializer written inside the probe.** `secret_approval.py` holds no
   state-keyed function — verified: zero hits for `watch`/`ls-tree`/`100755`/`state_id`/`serial`, and
   every one of its twelve functions is command-oriented. So the verdict is "yes, for that
   serializer", **never** "yes for `secret_approval.py` as shipped".
2. **`0 passed by both stubs` is structural, not evidence.** A single-direction assertion can only be
   passed by both stubs if it is vacuous. The **degraded controls** are what actually discriminate:
   `guard-file-only` (spec §5.1 as first worded) fails **17** assertions, and `name-only` fails 24 —
   ADR 0052's prediction that a filename-keyed watcher fails open, now measured.
3. **Mode must be in the key.** The `no-mode` control fails exactly one assertion, M17 — the
   `100755` → `100644` flip with byte-identical content. One row is the whole margin, so a
   content-only digest is blind to a hook being disarmed.

**Requirement task 3 adds (recorded here, not in the list, per the phase gate — fold into task 5):**
`secret_approval.py` needs **one new entry point**, e.g. `state-id <guard>`, that digests the
guard's watch-set bytes **plus git modes** and hashes directly. It must bypass `canonical_text()`
and `unapprovable_reason()`, and exit non-zero when a watched file is unreadable. Both existing
paths fail on real list text: `id` mode exits **3** ("more than one segment joined by a separator"),
and `fingerprint()` collides — `fp(T) == fp(T + trailing whitespace)` and
`fp(T) == fp("SECRET_EXEMPT=x " + T)`, both measured. `grant`/`consume`/session-scoping/single-use
need no change.

⚠️ **A whole-file digest over-prompts: a comment-only edit gives NO MATCH (measured), and flipping
`WORKTREE_GUARD_MODE` invalidates all three guards' approvals because `settings.json` is in every
file set.** Fails closed, but it contradicts spec §5.2's "tightening passes silently". The entry-level
extractors (ADR 0052, decision 3) are what resolve this, in tasks 4/5.

**Probe defect found and fixed by this session, not by the subagent that wrote it:** the probe
printed `PROBE VALIDITY: INVALID` while **exiting 0**, so a caller checking only the status read an
invalid probe as a pass. Falsified in both directions after the fix — clean run `rc=0`, and a run
with one mutation target deliberately corrupted `rc=1` with `INVALID — 1 mutation(s) missed their
target`. That corrupted run is also the first time the probe's own MISS gate was ever shown to fire;
the subagent listed it as unmeasured. The probe also fails closed (`rc=1`, named reason) when run
from outside `hooks/`.

**Not measured by task 3:** direction classification and the ALLOW/BLOCK tables (ADR 0052 decision
4 — still unreviewed by a human, still a gate before shipping), the watcher itself, a
reordering-only edit, staged-vs-HEAD as the baseline (HEAD was used, not `origin/main`), concurrent
or broken approval stores, and squash/octopus merges.

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

- [x] **0. Prove the `ask` path actually blocks a commit.** Spec §4. Never live-verified; a comment
      in `git-guard.sh` records it as a pending manual acceptance test. Measure both the interactive
      case and the pane-subagent case.
      **If the prompt does not block → STOP and return to the user. The design needs rethinking,
      not patching.** Nothing below starts until this resolves.
- [x] 1. Answer open question §9.2: define, **per guard**, what "the permission list" actually is,
      and verify each extraction against the real file rather than assuming a shape. Three different
      shapes across the three guards.
      **Answered 2026-10-28 → `docs/decisions/0052-the-permission-list-is-not-in-the-guard-file.md`.**
      It falsified three things the spec asserts; see the status block below before reading §5.
- [x] 2. Put open question §9.1 (merge commits) to the user. Do not guess a default.
      **Answered 2026-10-28 → `docs/decisions/0053-a-merge-prompts-only-when-the-content-is-not-already-on-main.md`.**
- [x] 3. Prove the `secret_approval.py` key shape discriminates (spec §8) — falsified against an
      always-match and a never-match stub, since a non-discriminating key fails permissively.
      **Measured 2026-10-28 → `hooks/secret-approval-state-key.probe.sh`. Verdict: YES, but
      conditional — see the status block below. The store works unchanged; the key does not
      exist yet, so task 5 must add one entry point to `secret_approval.py`.**
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

### Task 0 RESOLVED 2026-10-27 — the interactive half

The user ran `git -c core.pager=cat status --short` in a fresh session at normal permissions (this
session cannot: it is runtime-bypassed, re-confirmed 2026-10-27 by `touch /tmp/claude-perm-probe`
creating a file unprompted against **0 allow-rules**). **An approval box appeared and held the
command, and it carried the word `git-guard`.**

⚠️ **The wording is the whole discriminator, and this is why.** `settings.json` `permissions` holds
**0 allow / 0 deny / 0 ask** rules with `defaultMode: default`, so a normal session prompts for
*every* Bash command — "a box appeared" alone would have been consistent with the ordinary
permission prompt and proved nothing. Only the hook emits the string `git-guard`, so its presence
is what shows the `ask` decision reached the human rather than being swallowed.

**Scope this honestly — two things were NOT demonstrated.** The planned control (plain
`git status --short` producing a *generic* box) was never cleanly run: the user's attempt used the
`!` prefix, which goes straight to the shell and never becomes a tool call, so no hook saw it. The
control turned out to be unnecessary — the guard-specific sentence cannot be produced by a generic
prompt — but it was not run, and the §4 clause "declining must leave the working tree and HEAD
unchanged" is only trivially true here, since the probe command is read-only. A mutating command
was deliberately never used: another hook's `deny` would shadow the `ask` (see above).

**Exit condition met: the prompt blocks. Proceed to spec §5 / task 1.**

**History of the open half, for anyone auditing the gap between 2026-09-21 and 2026-10-27.** The
question could not be measured from inside a bypass-mode session, and no subagent lane substitutes:
in-process agents inherit the parent's mode, pane agents skip permissions by design. It was put to
the user 2026-09-21 and went unanswered for five weeks. The first reply reported only an unrelated
`Stop hook` failure (`hooks/handoff/handoff-keep-guard.sh` was registered at `settings.json:165,175`
with no execute bit — fixed by `chmod u+x` on 2026-09-21 after its suite passed 61/61, though that
mode is recorded as `100644` in git and so is **not** durable); a Stop hook fires after the turn and
carried no information about whether a prompt appeared. A second attempt on 2026-10-27 used the `!`
prefix and bypassed the hook. Neither was an answer, and neither was treated as one.
