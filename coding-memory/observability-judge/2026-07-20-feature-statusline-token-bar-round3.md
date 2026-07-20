# Observability Judge — feature/statusline-token-bar (implementation, round 3)

- **Repo:** `.claude`
- **Branch:** `feature/statusline-token-bar`
- **HEAD:** `f8cd83b7e46391b9a921205cd39c8bcee850e73a`
- **Base:** `main` (merge-base `f574213`)
- **Stage:** implementation
- **Timestamp:** 2026-07-20T01:45:36Z
- **Commits scored this round:** `cbae4db`, `96f8143`, `9fea760`, `f8cd83b`
- **Prior verdicts:** R1 `2026-07-19-feature-statusline-token-bar.md` (risk=high),
  R2 `2026-07-20-feature-statusline-token-bar.md` (risk=medium)
- **Test command:** `bash statusline-command.test.sh` — **run by me: 45/45 passed**
- **Filename note:** written as `-round3` because the R2 verdict already occupies
  `2026-07-20-feature-statusline-token-bar.md`. Overwriting a committed prior verdict —
  the very record this round is judged against — would have destroyed evidence.

---

## What was changed

Think of the token counter as a shared notebook that only one person may write in at a
time. To claim it you put a physical token on the desk (`mkdir`) — the desk only has room
for one, so only one person wins.

Round 2 found the problem was not claiming the token, it was *clearing an abandoned one*.
When someone walked off still holding it, everyone else would sweep the desk clear at
once — and a sweep could land right after somebody new had legitimately put their token
down, knocking it off. Two writers in the notebook again.

This round fixes that:

1. **Sweeping is now "pick it up and carry it away", not "brush it off the desk"** — an
   atomic rename. You only ever throw away the token you are actually holding, never
   whatever happens to be on the desk now.
2. **Only one person may sweep at a time**, enforced by a second desk-token
   (`$lock.break`). This was the change that mattered: renaming alone barely moved the
   failure rate (the author measured 4-in-8 to 4-in-10 and, to their credit, *said so*
   rather than declaring victory). The real cause was twenty people all sweeping on a
   judgement already out of date.
3. **You only pick your own token back up** when you leave (`release_state_lock`).
4. **A backstop** (`force_break_aged_lock`) for a token whose owner *looks* alive but
   isn't — process IDs get recycled. Without it, one session's counter jams forever.
5. The ADR's "totals are exact under concurrency" claim was walked back to the truth.

## Does it do what you wanted?

**Yes on the main path, and I verified it rather than taking the summary's word.**

| What I did | Result |
| --- | --- |
| Ran the suite | 45/45, stable |
| Removed the breaker serialisation (the headline fix) | fails — but only **2 runs in 6** |
| Removed `release_state_lock`'s ownership check | **45/45 — not caught** |
| Deleted `force_break_aged_lock` entirely | **45/45 — not caught** |
| Planted an aged lock with a live PID, ran renders | backstop works: lock cleared, next render counted correctly |

The R2 headline finding is genuinely fixed, not merely narrowed. In `clear_stale_lock`
the judgement now cannot go stale, because the only things that can remove the state lock
are its live owner (ownership-checked) and the single serialised breaker. The author's
declared "two-syscall residual" for that path is, as far as I can construct it, *more
pessimistic than necessary* — I could not build a reachable interleaving through
`clear_stale_lock`. Their honesty overshot in the safe direction.

The PID-reuse wedge (R2 finding 3) is also really fixed — I planted an aged lock owned by
a live PID and watched the counter recover on the following render.

## What could go wrong / what I'm unsure about

**The new backstop reintroduces the same defect class it was added to help fix.**
`force_break_aged_lock` judges the lock's age *before* taking the breaker lock, never
re-checks it inside, and has no `kill -0` guard at all. So a break authorised by a stale
age judgement can destroy a lock a different render legitimately acquired in the interim.
The identity check does not save it: that compares the capture against the PID read
*inside* the breaker lock, not against the state that justified the break.

I reproduced it (delay injected to widen the window, which I state plainly — the natural
window is a few milliseconds):

```
[probe] R1 judged lock aged
[test]  another render breaks it; a FRESH render acquires -> live lock present
[probe] R1 breaking lock whose pid it read as: 999999
[test]  fresh live lock present after R1 ran? no      <- live lock destroyed
```

**The second lock was added without the protections the first lock had just been given.**
Its stale-clearing is a raw `rm -rf` on the live breaker path — literally the R2 bug, one
level up — and both `clear_stale_lock` and `force_break_aged_lock` release it with an
unconditional `rm -rf`, no ownership check. I reproduced two renders holding the breaker
lock simultaneously, which defeats the serialisation that *is* the fix:

```
[probe] 51907 TOOK breaker
[probe] 51910 TOOK breaker
[probe] !! 51907 holds the breaker but owner file now reads '(gone)'
        -> MUTUAL EXCLUSION BROKEN
```

**Every new safety mechanism this round is untested.** Deleting `force_break_aged_lock`
outright, or stripping `release_state_lock`'s ownership check, both leave the suite at
45/45. And the headline serialisation fix is caught only 2 runs in 6 — the new RED test is
a real guard but a *probabilistic* one, reported as a binary pass. The author's "0 failures
in 20 runs" is a stronger claim about the fix than the suite can enforce going forward.

**Minor:** a render killed between the rename and the cleanup leaks a `$lock.dead.$$`
directory, and nothing ever reaps those. Harmless (gitignored, no correctness effect), but
it contradicts the "no leftover artifacts" claim in the general case.

**On the declared residual:** I agree it is acceptable *as scoped*, and I did not find it
reachable through `clear_stale_lock`. My disagreement is that the declaration is pointed at
the wrong function — the reachable version of that window lives in `force_break_aged_lock`,
which the declaration does not mention.

**Answering (b) directly — no new deadlock or permanent wedge.** There is no circular wait
(the breaker is never held while acquiring the state lock, and `mkdir` fails fast). An
orphaned breaker disables breaking for at most one minute, and recovery is documented.

**Process notes, both good:** `settings.json` and the untracked `chrome/`, `telemetry/`,
`stats-cache.json` remain uncommitted and were staged by explicit path throughout — the R2
staging hazard was handled correctly. The R1 "also worth doing" was escalated to the user
rather than absorbed, which is the right call on a branch that already overran scope once.
I restored the working tree to exactly its prior state after my mutations.

## What I'd double-check before merging

1. **Move the age check inside the breaker lock in `force_break_aged_lock`**, and add a
   `kill -0` guard there. This is a few lines and closes the reproducible live-lock
   deletion.
2. **Give the breaker lock the same treatment the state lock got** — an ownership-checked
   release, and something better than `rm -rf` on the live path for clearing an orphan.
   Right now the fix's own mutual exclusion is breakable.
3. **Decide whether an untested backstop is worth shipping.** `force_break_aged_lock` is
   the least-exercised and most defect-dense code in the diff. Covering it is one test:
   aged lock + live PID + assert recovery.
4. **Note the flaky guard.** Consider running the break test in a small loop, or record in
   the ADR that it detects the regression roughly one run in three.
5. Nothing here is a merge-blocker on its own — impact is a wrong cosmetic total that
   self-heals — but items 1 and 2 are cheap and close a class this branch has now hit
   three times.

---

## Dimension scores

| Dimension | Score | Note |
| --- | --- | --- |
| `intent` | pass | R2's findings addressed; the main-path fix and the PID-reuse backstop both independently verified working by me. |
| `execution` | concern | 45/45 run by me and the headline race genuinely closed, but I reproduced a live-lock deletion in `force_break_aged_lock` and two concurrent breaker-lock holders. |
| `trajectory` | pass | RED committed before GREEN; the measurement showing the obvious fix was insufficient (4-in-8 → 4-in-10) was reported, not buried; root cause correctly re-diagnosed as the stampede. Reasoning, not luck. |
| `regression` | pass | Suite green and stable; injection, legacy-migration and adjacent segments intact; no deadlock introduced; tree restored clean. |
| `context_budget` | pass | `CODING_MEMORY.md` trimmed back under 200 lines; script is not always-on context. |
| `traceability` | pass | ADR 0005 updated with the measured numbers, the corrected exactness claim, and the residual; comments carry the rationale. |
| `success_masking` | concern | Deleting `force_break_aged_lock` → 45/45. Removing `release_state_lock`'s ownership check → 45/45. The headline fix's own regression test catches removal only 2 runs in 6. |
| `intent_drift` | pass | Scope held to the R2 findings; R1 extra escalated to the user; no new dependencies; staged by explicit path, `settings.json` correctly left uncommitted. |
| `checkpoint` | pass | RED (`cbae4db`) precedes GREEN (`96f8143`); commits separately revertable. |
| `audit_trail` | pass | Prior verdict persisted, ADR overclaim corrected in the document itself, fully attributable. |

**Risk:** medium
**Confidence:** high

## Concerns

- `force_break_aged_lock` judges lock age outside the breaker lock and never re-validates inside it, with no `kill -0` guard; reproduced it deleting a live lock another render had acquired.
- The breaker lock's orphan clearing is an unconditional `rm -rf` on the live path; reproduced two renders holding the breaker simultaneously, defeating the serialisation that is the fix.
- Neither `clear_stale_lock` nor `force_break_aged_lock` ownership-checks its release of the breaker lock — the protection just added to `release_state_lock` was not applied to the new lock.
- Zero test coverage for `force_break_aged_lock`: deleting the function entirely leaves the suite at 45/45.
- Zero test coverage for `release_state_lock`'s ownership check: removing it leaves the suite at 45/45.
- The new stale-break regression test is probabilistic — removing the serialisation is caught only 2 runs in 6, but reported as a binary pass.
- `$lock.dead.$$` graves leaked by a render killed mid-break have no reaper; contradicts the "no leftover artifacts" claim in the general case.
- The declared residual window is pointed at `clear_stale_lock`, where I could not reach it; the reachable instance is in `force_break_aged_lock` and is undeclared.
