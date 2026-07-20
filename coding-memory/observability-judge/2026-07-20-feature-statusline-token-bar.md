# Observability Judge — feature/statusline-token-bar (implementation, judge-fix round)

- **Repo:** `.claude`
- **Branch:** `feature/statusline-token-bar`
- **HEAD:** `74fa622081323a181181f57fdb1fad12ebe5d788`
- **Base:** `main` (merge-base `f574213`)
- **Stage:** implementation
- **Timestamp:** 2026-07-20T01:29:18Z
- **Commits scored:** `fc67ab1`, `888449e`, `d7a2861`, `d302479`, `cc0a853`, `74fa622`
- **Prior verdict this branch:** `coding-memory/observability-judge/2026-07-19-feature-statusline-token-bar.md` (risk=high)
- **Test command:** `bash statusline-command.test.sh` — **run by me: 44/44 passed**

---

## What was changed

The statusline is the little status bar at the bottom of the editor. One piece of
it, the `Σ` segment, keeps a running count of tokens used this session. This round
fixed three problems an earlier review found.

1. **The tests were lying.** The test file had never actually been run against this
   change — it was red at 17/20, and several checks were still expecting an old
   display format that had been deleted. Those were fixed, and about fifteen test
   cases that only existed as scratch commands in a chat transcript were written
   properly into the suite.

2. **The counter was losing updates.** Think of two people updating a shared
   whiteboard total: both read "200", both add their own number, both write back —
   and the second one erases the first. That is what was happening. The fix is a
   lock: before touching the total, a render claims a directory (`mkdir`, which the
   filesystem guarantees only one process can win), re-reads the total *while
   holding it*, then writes and releases. The state file also changed from JSON to
   two lines of plain text, so the locked section no longer has to launch `jq`.

3. **A security test had gone slack.** The test that checks hostile text can't
   inject escape codes into the prompt used one global upper bound for all cases.
   That bound had drifted 4 bytes above what was actually needed, meaning a real
   leak could have slipped in unnoticed. It is now a per-case comparison against a
   harmless twin payload.

## Does it do what you wanted?

Largely, yes — and the evidence behind it is unusually good. I did not take the
summary's word for anything; I re-ran the suite and broke the code four ways to
check the tests actually notice:

| Mutation I applied | Result |
| --- | --- |
| Make lock acquisition a no-op | concurrency test fails, total 226 of 510 |
| Restore the PID read-clobber bug | 5 assertions fail (39/44) |
| Delete the `model_name` escape strip | injection test fails at `esc=11 limit=10` |
| Check out `888449e` (the RED commit) | genuinely red: 36/37, total 1216 of 20410 |

That last row matters most. The claim "I committed the failing test before the fix"
is true, and the failure it recorded is the real severity — the counter was storing
the seed plus exactly one writer, not a mild undercount. The third row confirms
finding (c) is really closed: under the *old* ceiling of 14 that leak would have
passed silently.

## What could go wrong / what I'm unsure about

**I found a lost update the fix does not cover.** The lock is correct in normal
operation, but its *cleanup* path is not. When a render is killed while holding the
lock, it leaves a stale lock behind. The next renders each independently decide the
lock is stale and each run `rm -rf` on it — so one render can delete a lock another
render has just legitimately taken, putting two writers in the critical section at
once. There is no ownership check: the holder's own release is also an unconditional
`rm -rf`, not "remove it if it is still mine."

I reproduced this. Planting one aged, pid-less lock and then starting 20 concurrent
renders:

```
trial 1: got=390 expected=410  LOST 20
trial 6: got=392 expected=410  LOST 18
trial 7: got=373 expected=410  LOST 37
trial 8: got=399 expected=410  LOST 11
```

Four of eight trials lost tokens. The same window exists on the dead-PID path,
though I could not trigger it there in six trials (that path does not fork `find`,
so the window is much narrower).

Scope, honestly: this needs a stale lock to *already* exist — i.e. a previously
killed render — plus concurrent renders in that same moment. It self-heals after one
round, and the damage is a wrong number on a cosmetic display. It is not the
order-of-magnitude failure this branch fixed. But it is the same failure *class*, in
the mechanism built to eliminate it.

**Consequence for the ADR:** `docs/decisions/0005-statusline-counter-lock.md` states
"Totals are exact under concurrency." That is overclaimed — it is true only when no
stale lock is present. The document should say so.

**A related gap the summary did not name:** `clear_stale_lock` has no age fallback
for a numeric PID. If a stale lock's recorded PID is later reused by an unrelated
live process, `kill -0` succeeds forever and the lock is never cleared — that
session's counter stops updating permanently, with no recovery but deleting the
directory by hand. PID reuse is rare; the failure is silent and unbounded.

**Declared gaps I agree are correctly declared** (not held against the branch):
the give-up-time assertion is coarse, a lock timeout can genuinely lose usage under
sustained contention, and legacy `session-*.json` files go inert once. All three are
written down in the ADR and the script.

**On the give-up assertion specifically:** it measured `0s` against a `<= 2s` bound
because it uses whole-second granularity. It cannot distinguish the intended ~390ms
from 1.9s. The author says so plainly. It is close to vacuous, but it does still
catch a spin that never terminates, which is its stated job.

**Does any test assert something the implementation cannot produce?** Yes, one, and
it is deliberate and disclosed: the writer always emits a trailing newline, so the
"no trailing newline" PID case tests a shape only a *future* writer change could
create. That is defensive, not false — and the author's own account of how the
first version of this test failed to catch its own bug (planting a newline the
buggy writer could not produce, so the mutation passed 43/43) is exactly the kind of
disclosure that makes the rest of the evidence credible.

**Outside the diff, but a merge hazard:** the working tree has an uncommitted
`settings.json` change that wires a third-party `~/.orca/agent-hooks/claude-hook.sh`
into eleven hook events, plus untracked `chrome/`, `telemetry/`, `stats-cache.json`.
None of it belongs to this branch, and none of it is committed — but a `git commit
-a` or a blanket `git add` at PR time would sweep it in, and an unvetted external
hook on every tool call would breach the supply-chain rule in `core-conduct.md`.

## What I'd double-check before merging

1. **Fix or explicitly accept the stale-lock recovery race.** The minimal fix is to
   make breaking a stale lock atomic — `mv` the stale directory to a unique name and
   only proceed if the rename succeeded, so exactly one recoverer wins. Releasing
   should likewise verify the lock is still ours (compare the pid file) before
   removing it.
2. **Soften the ADR's "Totals are exact under concurrency"** to state the
   stale-lock caveat, so the document does not outrun the evidence.
3. **Decide on the reused-PID case** — even a "lock older than N minutes is cleared
   regardless of PID" backstop removes the permanent-wedge outcome.
4. **Stage deliberately.** Commit by explicit path; do not let `settings.json`,
   `chrome/`, `telemetry/`, or `stats-cache.json` ride along.
5. Optional: `statusline-command.sh` is now 483 lines, past the <400 preference
   (under the 800 max). Much of the growth is high-value rationale comments, so this
   is a note, not an objection.

---

## Dimension scores

| Dimension | Score | Note |
| --- | --- | --- |
| `intent` | pass | All three findings genuinely addressed; each fix independently verified by mutation. |
| `execution` | concern | Suite is green (44/44, run by me) and the primary race is fixed, but I reproduced a lost update via the stale-lock recovery path (4/8 trials). |
| `trajectory` | pass | RED committed before GREEN and verified red; tests and implementation never in one commit; lock budget sized by measurement with the rejected 10-attempt option recorded; two self-found bugs disclosed. |
| `regression` | pass | Injection ceiling tightened, not loosened; legacy-state migration covered; adjacent segments still asserted. |
| `context_budget` | pass | `CODING_MEMORY.md` actively trimmed to 199 lines (under the 200 limit). Script is not always-on context. |
| `traceability` | pass | ADR 0005, branch memory, and in-script comments carry measured numbers and rejected alternatives. |
| `success_masking` | concern | 44/44 green while a reproducible lost-update path exists that no test covers — every stale-lock test is single-render. Give-up assertion is admittedly near-vacuous. ADR overclaims exactness. |
| `intent_drift` | pass | Scope held to the three findings; earlier "also worth doing" deferred with a stated reason; no new dependencies. |
| `checkpoint` | pass | Six clean, separately revertable commits; RED checkpoint precedes the fix. |
| `audit_trail` | pass | ADR-worthy and recorded as an ADR; commit messages state RED/GREEN explicitly; fully attributable. |

**Risk:** medium
**Confidence:** high

## Concerns

- Stale-lock recovery has an unguarded break-then-acquire window; reproduced losing 11–37 tokens in 4 of 8 trials.
- Lock release is an unconditional `rm -rf` with no ownership check, so a holder can delete another render's lock.
- No age fallback for a numeric-but-stale PID: PID reuse wedges that session's counter permanently.
- ADR 0005 claims "Totals are exact under concurrency"; my probe falsifies this when a stale lock is present.
- No test exercises stale-lock recovery under concurrency — all such tests are single-render, which is what let the defect stay green.
- Give-up-time assertion has whole-second granularity; cannot distinguish 390ms from 1.9s (declared by author).
- Uncommitted `settings.json` wiring an unvetted third-party hook into 11 events is a staging hazard at PR time.
