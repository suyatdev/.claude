# Observability verdict — `phase-guard.sh` design, round 2 (architecting)

- **Repo:** `phase-guard-hook` (worktree of `~/.claude`)
- **Branch:** `worktree-phase-guard-hook` @ `1befe03e2eb3b6b7b7782f3a10dddccb1bf61092`
- **Stage:** `architecting`, **round 2** — advisory, does not gate
- **Design judged:** `docs/features/phase-guard-hook.md` (732 lines, was 429)
- **Timestamp:** 2026-07-25T22:23:50Z
- **Verdict:** risk `medium`, confidence `high` — no `fail`. All five round-1 concerns are
  genuinely closed, not gestured at. Risk holds at `medium` because closing them opened three new
  gaps, and the task list has sequencing breaks that will bite an implementer working under a
  frozen checklist.

---

## What was changed

Nothing has been built yet. This is still a design document, revised after two judges reviewed it.

The thing being designed is a **safety catch for a traffic light**. Every feature in this repo gets
a planning document with a line at the top reading `phase: planning`, `phase: implementation`, or
`phase: review`. That is the light. Right now the light exists but nothing is wired to it — a
session can be told "you are still planning" and write production code anyway, and nothing stops it.
`phase-guard.sh` is the wiring: a script the editor runs *before* every file write, which refuses
the write if the light is still red.

The clever part (unchanged from round 1, and still the design's best idea) is how it decides. It
never tries to work out *which* feature a given file belongs to — that question has no reliable
answer. It asks a much simpler one: **does the branch I'm sitting on have permission?** Branches are
only created when a gate opens, so sitting on an unclaimed branch while a red light exists is itself
the signal.

Since round 1 the author added: a written contract for what a valid planning document looks like, a
rollback plan for turning the guard off, two places where the guard now speaks up instead of failing
silently, a fix so finished features stop blocking, and a concrete recipe for the performance test.
The document grew about 70%.

## Does it do what you wanted?

Mostly yes, and the revisions are real work rather than paperwork. I checked each of my five round-1
concerns against the actual text and each one is genuinely closed:

- The one-word `review` fix is in — a finished feature no longer blocks forever.
- The rollback section is real, with three escape routes, and `settings.json` was correctly moved to
  the unguarded side so the guard can never block edits to its own off-switch.
- The performance test now specifies a mechanism instead of hoping. **I built that mechanism and ran
  it** — a fake `git` on the PATH that tallies calls then hands off to the real one. It works
  exactly as described.
- The frontmatter contract is specified clause by clause, so a typo like `plannning` can no longer
  switch a critical safety gate off in silence.
- The always-on rules file is amended in place rather than gaining a new bullet — I confirmed the
  stub really is at `rules/gates.md:5`.

Two things I verified myself and one claim that does not hold up:

- Detached `HEAD` really does return the literal string `HEAD` — the new "allow silently during a
  rebase" rule is correctly grounded.
- The `git cat-file --batch` output asymmetry the parser depends on is exactly as documented.
- **The cited precedent is only half-real.** The design leans on
  `pane-dispatch-guard.sh:43-50` as the house pattern for its new "print once per session" flag.
  That file only ever *reads* such a flag; the flag is written by a completely different program
  (`panes/dispatch-pane-agent.sh:71`). **No hook in this repo writes session state today.** So the
  precedent covers half of what it is cited for, and the new half is the unspecified half.

## What could go wrong / what I'm unsure about

**1. The fix for "silent failure" can itself fail silently.** Round 1's complaint was that a working
guard and a dead one look identical. The fix is a once-per-session warning. But the design never
says *where that flag lives*, what happens *when it can't be written*, or whether the two different
warnings share one flag. On a hook whose entire philosophy is "when in doubt, allow", an unwritable
flag store lands you in one of two bad places: print on every single write (which the design itself
forbids as too noisy) or never print at all — which is exactly the round-1 problem, restored. There
is also no cleanup: the real precedent has stale-flag expiry, this design has none, so flag files
accumulate forever. And if the key is only the session id, one session moving between two repos
warns about the first and stays silent about the second.

**2. Three tasks in the "frozen" 13-task list cannot be completed as written.** This matters more
than usual because the workflow forbids adding tasks after the gate opens.
- Task 4 says "Green for A3", but every A3 scenario asserts a *deny* with a message — which needs
  steps 8–10, built in task 6. It cannot be green at task 4.
- Task 1 includes the no-local-branches scenario, which also asserts a deny. Same problem.
- A1 examples 7–10 are assigned to task 1 *and* again to task 5.

An implementer hits this at task 4, and their only outs are to break the freeze or quietly loosen
the criteria. Both are bad.

**3. Task 13's dogfood check proves less than it claims.** It says to confirm the guard denies a
write "while `phase: planning` still holds" — but by task 13 the gate has opened, so this feature's
own document reads `implementation` and the guard will correctly allow everything. The check is
unexecutable as literally written without a scratch planning file nobody has specified. Worse, task
10 does not say *which* `settings.json` to register in. The worktree's copy is inert — only
`~/.claude/settings.json` is live, and that file currently sits in a different checkout on a
concurrent session's branch. Editing it reaches outside this feature's domain; not editing it means
task 13 never exercises the real harness at all.

**4. Supersession is sticky, and round 1's `review` fix widened it.** A planning document stops
blocking if *any* branch records it as `implementation` or `review`. There is no recency check. So
one stale, never-deleted branch permanently disarms that document — including for a later re-planning
cycle on the same feature. This repo has 7 local branches and 3 worktrees; stale branches are the
normal state. The failure is silent and fails open.

**5. The "momentum guardrail, not a security boundary" framing is *mostly* earned — but its
supporting claim is not.** Writing files through the Bash tool (`sed -i`, `cat >`, `python -c`) is
completely unguarded, and the design is honest about it. I accept the framing: the threat model is a
session drifting, not an adversary. Two caveats. The `merge-guard.sh` comparison flatters it —
merge-guard misses an exotic chained form, this misses one of the most-used tools in a session. And
the reassurance that "`git-guard.sh` and `doc-guard.sh` still stand between that write and a commit"
**is not true in the case this feature is being built under**: git-guard only blocks commits to
`main`, and planning normally happens on a worktree-isolation branch, where it does nothing. The
backstop is real on `main` and largely absent elsewhere.

**6. Cost on the hot path is higher than the design's own trigger.** I measured the real sequence in
this repo: **~44ms per write** in an opted-in repo (7 branches, 1 feature file), of which ~23ms is
Python startup — before the flag check, the frontmatter scan, or the deny message. The design sets
"revisit above ~50ms" as its threshold; it is essentially there on day one and grows as feature
files accumulate. The good news, also measured: repos that never opted in cost only **~9ms**, so the
early-exit design genuinely works and the blast radius on unrelated repos is small.

**7. One repo-specific hole.** `.claude/*` is unguarded, and this repo's worktrees live at
`.claude/worktrees/`. From the primary checkout, every file in every worktree is therefore exempt.
Narrow, but unremarked.

**8. Minor:** `hooks/checkpoint-before-modify.sh` exists (executable, 6.9K) and is the closest thing
to a prior write-path guard, yet is absent from the prior-art table — it is currently registered
nowhere. And the "26th bullet" rationale in task 11 is off; `rules/gates.md` has 18 bullets. Neither
changes a conclusion.

## What I'd double-check before merging

This is a design, so "before merging" means "before the gate opens and the checklist freezes":

1. **Pin down the flag store** — path, behaviour when unwritable, one flag or two, and a cleanup
   rule. Say plainly which way it fails, because both ways are defensible and only one is chosen.
2. **Fix the task sequencing** — move the deny-asserting scenarios out of tasks 1 and 4, or restate
   those tasks' green criteria. Do it now; the freeze makes it expensive later.
3. **Decide the registration target for task 10** and rewrite task 13's dogfood into something
   actually executable (a scratch planning file, and a fresh session, since hooks are read at
   session start).
4. **Add one line about stale-branch supersession** so the sticky-disarm case is disclosed rather
   than discovered.
5. **Correct the two overstated claims** — the `pane-dispatch-guard` precedent (read-side only) and
   the git-guard/doc-guard backstop (absent on isolation branches). This document's credibility is
   its main asset; both are cheap to fix.
6. **Re-baseline the performance note** against the ~44ms whole-hook figure rather than the ~26ms
   `cat-file` slice.

---

## Dimension scores

| Dimension | Score | Basis |
|---|---|---|
| `intent` | pass | Answers ADR 0010's objection; all five round-1 concerns substantively closed, verified line by line. Bash-tool hole disclosed with a stated threat model. |
| `execution` | concern | No code yet, no test command to run. Task list has three verifiable sequencing breaks (tasks 1, 4, 5) under an explicit freeze; task 13's dogfood is unexecutable as written. |
| `trajectory` | pass | Strong reasoning throughout: the branch-scoped reframing, blast-radius-driven fail-open/fail-closed split, shim chosen over wall-clock with a stated reason, streaming cost recorded not hidden. |
| `regression` | concern | Global `PreToolUse` on every write across 3 worktrees + concurrent sessions; ~44ms measured in an opted-in repo vs. its own ~50ms threshold; ambiguous registration target on another session's branch; `.claude/*` exemption swallows worktree trees. |
| `context_budget` | pass | `rules/gates.md` amended in place at `:5` (verified), no new always-on bullet. Deny message bounded. 732-line feature file is a heavy per-restore read but is not always-on. |
| `traceability` | pass | Exceptional: numbered decisions, round-2 additions tagged with the citing rubric, prior art cited by line, judge rounds recorded inline with blob SHA. Blemish: one half-earned precedent citation, one wrong bullet count. |
| `success_masking` | concern | Round-1's audibility fix is defeatable by its own unspecified flag store; A3 scenarios assert deny while task 4 claims green; flag files have no TTL; backstop claim overstates protection on isolation branches. |
| `intent_drift` | pass | +70% length, but every addition traces to a numbered judge finding. No new deps; toolchain pinned to bash/python/git/awk/sed with dialect constraints. Non-goals widened, not scope. |
| `checkpoint` | concern | Rollback section is a real fix with a bulletproof exit (`chmod -x`) and `settings.json` correctly exempted. Residual: task 10's registration target is unspecified and the live one sits on a concurrent session's branch; no staged rollout between global registration (task 10) and validation (task 13). |
| `audit_trail` | pass | Task 12 writes ADR 0011 amending 0010, recording the overridden deferral and the disclosed non-goal. Judge rounds preserved in-file. |

**Roll-up:** risk `medium`, confidence `high`. No `fail`; 4 `concern`, 6 `pass`.

Confidence is `high` because the load-bearing claims were checked empirically rather than read:
the counting-`git` shim was built and run, detached-`HEAD` and `cat-file --batch` behaviour
reproduced, `rules/gates.md:5` / `doc-guard.sh:149` / the three `PreToolUse` matchers confirmed,
hot-path cost measured, and the `pane-dispatch-guard` precedent traced to its actual writer.

## Empirical checks performed

| Claim | Result |
|---|---|
| Counting-`git` PATH shim can intercept the hook's bare-name `git` calls | **Holds** — built and run; tallied `rev-parse`, `for-each-ref`, `cat-file --batch` and produced correct output via `exec` to the real binary |
| `rev-parse --abbrev-ref HEAD` returns literal `HEAD` when detached | **Holds** |
| `cat-file --batch` does not echo the request for present blobs | **Holds** — `<sha> blob <size>` + content |
| `rules/gates.md:5` is the `Phase gate` stub (task 11) | **Holds** |
| `doc-guard.sh:149` is the source/doc classification | **Holds** |
| `settings.json` `PreToolUse` has exactly 3 matchers, so this is a 4th | **Holds** (`Bash`, `Task\|Agent`, `*`) |
| `pane-dispatch-guard.sh:43-50` establishes the once-per-session flag pattern | **Half-holds** — read-side only; the writer is `panes/dispatch-pane-agent.sh:71`, and no hook writes session state |
| "`git-guard.sh` and `doc-guard.sh` still stand between that write and a commit" | **Does not hold generally** — git-guard only guards `main`/`master`, not isolation branches |
| Hot-path cost vs. the design's ~50ms revisit threshold | **~44ms** in an opted-in repo (~23ms Python startup); **~9ms** in a repo without `docs/features/` |
| `rules/gates.md` bullet count ("26th bullet") | **18 bullets** — rationale sound, count wrong |
