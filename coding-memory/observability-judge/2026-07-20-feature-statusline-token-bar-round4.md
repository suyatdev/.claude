# Observability Judge — feature/statusline-token-bar (implementation, round 4)

- **Repo:** `.claude`
- **Branch:** `feature/statusline-token-bar`
- **HEAD:** `28770fcacee06c5b6392985e7ec9989528c701c7`
- **Base:** `main` (merge-base `f574213`)
- **Stage:** implementation
- **Timestamp:** 2026-07-20T02:03:54Z
- **Commits scored this round:** `9d8ee66`, `05175ca`, `1317514`, `28770fc`
- **Prior verdicts:** R1 `2026-07-19-...md` (high), R2 `2026-07-20-...md` (medium),
  R3 `2026-07-20-...-round3.md` (medium)
- **Test command:** `bash statusline-command.test.sh` — **run by me: 50/50 passed, 6.47s**
- **Filename note:** `-round4` suffix so the R3 record survives, as requested.

---

## What was changed

Two rounds ago the bug was "everyone sweeps the desk at once". Round 3 fixed that but
left the *sweeper* itself sloppy. This round tightens the sweeper.

1. **A break is now checked against the reason it was ordered.** Previously the code
   said "this lock is over a minute old, break it" and then, holding the thing it had
   picked up, checked *whose name was on it* — a different question. If someone new had
   legitimately taken the lock in between, the name check passed and a live lock was
   destroyed. Now age-justified breaks are verified by age and PID-justified breaks by
   PID: `break_lock_verified "$dir" "age" | "pid:<n>"`.
2. **The second lock got the protections the first one had.** Both locks now share one
   break implementation and one release implementation (`release_lock_if_owned`), on the
   correct reasoning that two implementations of one protocol is how the second lock
   came to lag behind.
3. **The safety machinery is now actually tested** — black-box for the PID-reuse
   backstop, plus direct helper calls in a subshell for the guards no render can reach.

## Does it do what you wanted?

**Yes. Both R3 findings are genuinely fixed, and I checked rather than trusting the summary.**

| What I did | Result |
| --- | --- |
| Ran the suite | 50/50, 6.47s |
| Grepped every remaining `rm -rf` | all on captured graves or ownership-gated — no live-path `rm -rf` remains |
| Stripped the ownership check from release | **49/50 — caught**, named reason |
| Broke age-verification inside `break_lock_verified` | **44/50 — caught hard** |
| Deleted the `force_break_aged_lock` backstop | **48/50 — caught** |
| Tested `mv`'s mtime behaviour directly | **the author's reasoning is correct** |

**On (a), the mtime reasoning — it holds.** I confirmed empirically that `mv` preserves a
directory's mtime across the rename, so the age of a capture really is the age that was
judged. I also enumerated every path that could touch a lock's mtime after creation. There
is exactly one (below), and it moves the mtime in the *safe* direction — it makes a lock
look younger, so it errs toward not breaking. The core premise of this round is sound.

**On (b), sharing one implementation between two locks — no mismatch found.** The breaker
is held for milliseconds and the state lock across a ~3ms critical section; both are far
below the 1-minute staleness threshold, so one shared constant is fine. `break_aged_breaker`
is deliberately unserialised and that is correct, because the atomic capture plus age
verification is self-sufficient there. No circular wait, no new wedge from the sharing.

## What could go wrong / what I'm unsure about

**The code assumes `mv` is "rename or fail". For directories it is not — it nests.** This
is the one real finding of the round, and it makes two comments untrue rather than merely
generous:

```
mv "$grave" "$lock" 2>/dev/null || rm -rf "$grave" 2>/dev/null    # line 334
```

When `$lock` already exists as a directory, `mv` does not fail — it moves the grave
*inside* it and returns 0. I verified this. Two consequences:

- **The `|| rm -rf "$grave"` fallback is dead code**, and
- **ADR 0005 lines 99–101 describe a failure mode the code cannot produce.** You asked
  whether the framing is still too generous. It is worse than generous — it is
  mechanically wrong. The capture is never "dropped"; it is silently nested inside the
  live lock. The *correctness* impact is identical (two holders in the critical section),
  so the severity claim survives, but the next person to read that ADR will look for the
  wrong thing.

**The same nesting turns R3's "harmless" grave leak into a real, if rare, defect.** R3
flagged that a render killed mid-break leaks `$lock.dead.$$` and judged it cosmetic. With
nesting understood, it isn't. I reproduced this:

```
before: live lock present? yes
after : live FRESH lock still present? yes
/s.lock/pid          <- now contains 'OLDDEAD', the leaked grave's pid file
/s.lock/s.lock/pid   <- the real holder's lock, nested one level down
```

A leaked grave at `$lock.dead.<pid>` plus PID reuse to that same pid means the next
capture nests into the leaked grave, and the restore puts the *grave's* `pid` file at the
live lock path. The true owner then fails its own ownership check and never releases; the
lock looks pid-less and fresh, so nothing breaks it for up to a minute. Every render in
that window pays the full ~390ms spin. It self-heals on the age path afterwards. Needs a
kill inside a few-millisecond window plus PID wraparound, so this is rare — but it is no
longer zero-impact, and it is undeclared.

**On (c), the subshell unit tests — sound, with one gap and one wart.** They assert only
behaviour the implementation really produces; I re-derived each assertion. No `exit` exists
in the sourced script, so the command-substitution subshell cannot be terminated early into
a false `ok`. Two notes: the block reports `ok` when `UNIT_ERR` is empty *and* status is
zero, which is correct, but a `set -u` abort during sourcing would report `bad` with an
empty reason — diagnosable only by re-running. And `UNIT_HOME` is `mktemp -d`'d inside the
function and is **not** in the suite's `EXIT` trap; I measured temp dirs going 39 → 40 per
run. Harmless, but it contradicts the "zero leftover artifacts" claim.

**The untested branch is the one that turned out to be mis-documented.** The unit test
exercises the age-mode restore only when the target path is *free*. The occupied-path
restore — the nesting case, the actual residual — has no coverage.

**One mutation still slips through.** The *call site*'s choice of mode is unguarded. If I
reintroduce the exact R3 bug at the call site rather than in the helper —

```
break_lock_verified "$lock" "pid:$(cat "$lock/pid" 2>/dev/null)"   # in force_break_aged_lock
```

— the suite stays at **50/50**. The helper-level mutation you cited is caught, hard (44/50),
so your claim is honest; the gap is narrower than R3's but the same shape. The black-box
test cannot see it because in the non-racing case PID verification also succeeds.

**On (d), wedges.** No deadlock and no permanent wedge. I traced the double-orphan case
(state lock and breaker both orphaned): `clear_stale_lock` bails, the spin exhausts,
`force_break_aged_lock` clears the aged breaker and then breaks the lock — recovery one
render and one minute later, as documented. The only wedge I found is the ~1-minute one
above, and it clears itself.

**On the ~6.5s runtime — that is a good trade, keep it.** Two deliberate give-up paths and
two 20-way concurrency cases buy the only coverage that has ever caught a real defect on
this branch. A pre-commit suite is not on the hot path. I would not shrink it.

**Process notes, all good.** `settings.json` and the untracked `chrome/`, `telemetry/`,
`stats-cache.json` are still correctly uncommitted; I restored the working tree to exactly
its session-start state after my mutations. `CODING_MEMORY.md` is at exactly 200 lines —
at the limit, not under it, so the next entry forces a trim. R1's `STATUSLINE_DEBUG` extra
remains escalated rather than absorbed, which is right.

## What I'd double-check before merging

1. **Fix ADR 0005 lines 99–101** to describe what `mv` actually does. This is the cheapest
   and most valuable item here: the document currently misdirects.
2. **Make the capture fail closed when the grave path already exists** — one `[ -e "$grave" ]
   && return 0` before the `mv`, or a grave name that cannot collide. That closes the
   leaked-grave corruption without needing a reaper.
3. **Either delete the dead `|| rm -rf "$grave"` or make it reachable.** A fallback that
   cannot fire reads as protection that isn't there.
4. **Add `UNIT_HOME` to the `EXIT` trap.**
5. Optional: a unit case for the occupied-path restore, which would have caught items 1–3
   at once.
6. None of this is a merge blocker. The impact ceiling is one wrong cosmetic total plus a
   rare one-minute slow-render window, both self-healing. The two R3 findings are closed.

---

## Dimension scores

| Dimension | Score | Note |
| --- | --- | --- |
| `intent` | pass | Both R3 findings genuinely fixed; verified structurally (no live-path `rm -rf` remains) and by three mutations. Generalised rather than patched, as claimed. |
| `execution` | concern | 50/50 run by me and the R3 defects closed, but `mv`-onto-existing-directory nests rather than fails; I reproduced a live lock's pid file being replaced, wedging the counter for ~1 min. Rare and self-healing. |
| `trajectory` | pass | "Verify against whatever justified the break" is the correct abstraction, not a spot fix. The mtime premise is load-bearing and I confirmed it is true. Sharing one release/break implementation is correctly argued from the R3 root cause. |
| `regression` | pass | 50/50 stable, `bash -n` clean, no deadlock, adjacent segments intact, tree restored to session-start state. |
| `context_budget` | pass | `CODING_MEMORY.md` at exactly 200 lines (at the limit); script is not always-on context. |
| `traceability` | concern | ADR 0005's declared residual describes a mechanism the code cannot produce — the restore nests, it does not lose and drop. Being wrong about the failure mode is worse than being too generous about it. |
| `success_masking` | concern | Reintroducing the R3 bug at the *call site* leaves 50/50 (helper-level is caught at 44/50). The occupied-path restore — the actual residual — is untested. Stale-break RED test still probabilistic, honestly declared. |
| `intent_drift` | pass | Scope held to R3 findings; R1 extra escalated to the user, not absorbed; no new dependencies; `settings.json` and untracked dirs correctly left uncommitted. |
| `checkpoint` | pass | Fix (`9d8ee66`), tests (`05175ca`) and docs (`1317514`, `28770fc`) are separate, revertable commits. |
| `audit_trail` | pass | R3 verdict preserved via the round suffix; ADR and branch memory updated; fully attributable. |

**Risk:** medium
**Confidence:** high

## Concerns

- `mv` of a directory onto an existing directory nests rather than failing; the code assumes rename-or-fail in two load-bearing places.
- ADR 0005 lines 99–101 describe a residual mechanism the code cannot produce (capture is nested, never dropped).
- `|| rm -rf "$grave"` on the restore path is dead code — unreachable for a directory target.
- A leaked `$lock.dead.<pid>` grave plus PID reuse lets a capture nest into the grave and replace the live lock's pid file, wedging the counter for ~1 minute; R3 judged this leak harmless, it is not.
- The occupied-path restore — the actual residual and the source of the above — has no test coverage.
- Reintroducing the R3 age-justified/pid-verified bug at the call site leaves the suite at 50/50; only the helper-level mutation is caught.
- `UNIT_HOME` is not in the suite's `EXIT` trap; each run leaks one temp dir (measured 39 → 40).
- A `set -u` abort while sourcing the script in the unit block reports `bad` with an empty reason.
- `CODING_MEMORY.md` is at exactly 200 lines, not under — the next entry forces a trim.
