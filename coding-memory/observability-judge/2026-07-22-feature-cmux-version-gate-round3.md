# Observability Judge Verdict — cmux-version-gate (implementation, gating) — ROUND 3

- **Repo:** `.claude` · **Branch:** `feature/cmux-version-gate`
- **HEAD:** `0ecec9a76450a19bcf01ba63b932fec925895442` (pushed; `origin` matches)
- **Base:** `main` (merge-base `34914644801fa0454a7bc2da1b2beb99a390e583`)
- **Delta under review:** `git diff 758b1fa..HEAD` — one commit, 4 files, +36/−11
- **Prior rounds:** `2026-07-22-feature-cmux-version-gate.md` (`9797191`),
  `…-round2.md` (`758b1fa`)
- **Risk:** low · **Confidence:** high
- **Blocks the PR:** no. No dimension fails.

**Headline: `traceability` returns to `pass`.** I spot-checked roughly twenty discrete claims in the
rewritten branch log against the code and **re-ran all six falsification rows myself — every one
reproduces exactly**, including the `75/4` that replaces round 2's non-reproducing `73/4`. This is
the most accurate durable artifact this branch has produced.

**`success_masking` moves the other way, `pass` → `concern`, on a finding I made myself:** the
brace fix landed on *both* receipt writes, but the new regression test only exercises *one* of
them — and the one it skips is the path the bug was originally reported on.

## Test evidence — run by me, not taken on report

| Suite | HEAD `0ecec9a` | `758b1fa` (r2) | `main` |
|---|---|---|---|
| `cmux-exec.test.sh` | **79** / 0 | 77 | 54 |
| `cmux-layout.test.sh` | 34 / 0 | 34 | 34 |
| `adapters.test.sh` | 24 / 0 | 24 | 24 |
| `dispatch-pane-agent.test.sh` | 39 / 0 | 39 | 39 |
| `run-pane-agent.test.sh` | 10 / 0 | 10 | 10 |
| `terminal-detect.test.sh` | 9 / 0 | 9 | 9 |
| **total** | **195 / 0** | 193 | **170** |

I extracted `main` into a scratch tree and ran it, so `170 → 195` and `54 → 79` are measured, not
quoted. `shellcheck -x` on all four named scripts exits 0, silent. Live binary is
`cmux 0.64.20 (100) [14e3400b9]`, matching the pin.

### Falsification — I re-ran all six rows independently. All six reproduce.

Run against a pristine `git archive HEAD` copy in `/tmp` (repo working tree never touched), each
mutation applied alone, `bash -n` checked, non-empty diff confirmed, restored from a `cp` backup.

| Mutation | Log claims | My result |
|---|---|---|
| pin `0.64.20` → `0.65.0` | 73/6 | **73 / 6** ✅ exact |
| check never called | 65/14 | **65 / 14** ✅ exact |
| filter back to version-CLEAN | 75/4 | **75 / 4** ✅ exact |
| stale receipt never cleared | 78/1 | **78 / 1** ✅ exact |
| no receipt on unreadable | 77/2 | **77 / 2** ✅ exact |
| mismatch receipt write unbraced | 78/1 | **78 / 1** ✅ exact |

Round 2's finding is visibly closed: under the version-CLEAN mutation the two failures are now
`pre-release/major 0.65.0-rc1 is a MISMATCH, not unreadable` **and**
`0.65.0-rc1 leaves a MISMATCH-kind receipt`. Before the tightening the second one passed. The
kind assertions are load-bearing, proven, not asserted.

### Boundary re-probe — driven end-to-end through the real adapter

| `cmux version` first line | stderr | receipt |
|---|---|---|
| `0.64.20` (pin) · `0.64.20 ` (trailing space) | silent | none ✅ |
| `0.65.0` · `0.65.0-rc1` · `2026.07.01` · `0abc.1def` | **WARN** | `found …` mismatch ✅ |
| `v0.65.0` · `100` | silent | `unreadable …` ✅ |
| `cmux` alone · empty output · `cmux version 0.65.0` | silent | `unreadable …` ✅ |

Every row `rc=0`, `out=surface:51` — warn-never-degrade intact. Matches the branch log's stated
boundary calls exactly.

### NEW — I found one thing nobody has raised yet

**The brace fix is only half-covered by its own regression test.** The new case at
`cmux-exec.test.sh:446-456` sets the fake version to `0.65.0`, which takes the **mismatch** branch.
The bug round 2 reported was on the **unreadable** branch — the one documented as silent.

Proven by mutation:

- Unbrace the *mismatch* write → **78/1**, caught. ✅
- Unbrace the *unreadable* write → **79 / 0, fully green.** ❌

And it is not a harmless line. With the unreadable write unbraced I drove an unwritable
`PANE_STATE_DIR` with `garbage` version output and got back, on stderr:

```
cmux.sh: line 63: …/ro-state2/cmux-version-mismatch: Permission denied
```

— the exact leak round 2 reported, reintroduced with the suite still all-green. At HEAD that same
probe returns empty stderr, so **the shipped code is correct on both paths**; only the net has a
hole. The commit message pairs "Both receipt writes are now braced" with "A regression test drives
an unwritable state dir", which invites the reading that both are guarded. One is.

**One-line remedy:** loop the RO case over two versions — `0.65.0` and `garbage` — so each branch
gets its own unwritable-dir assertion.

## Branch-log spot-check — the `traceability` question

Every claim below I verified against the code or by execution.

| Log claim | Verdict |
|---|---|
| "Runs once per dispatch, before the derive/execute retry loop" | ✅ `cmux.sh:302`, immediately above `while :` |
| Mismatch → 2-line stderr + `found <v>, verified <pin>` | ✅ `cmux.sh:72-76` |
| Match → receipt deleted | ✅ `cmux.sh:69` |
| Unreadable → silent + `unreadable version output: <line>` | ✅ `cmux.sh:63`, probed |
| `case "$found" in [0-9]*.[0-9]*)` | ✅ verbatim, `cmux.sh:55` |
| bare `100` → unreadable; `v0.65.0` → unreadable | ✅ both probed |
| "`run-pane-agent.sh:81` already documents this exact trap" | ✅ real, and it says exactly that |
| Braced form on both writes | ✅ both |
| "Nothing opens `$PANE_STATE_DIR/cmux-version-mismatch`" | ✅ grepped repo-wide: 1 writer, 1 test reader, 2 doc pointers, **0 code readers** |
| Not on the `PANE_DRYRUN` path | ✅ dryrun exits at `:213`, check is at `:302` |
| `version-gate baseline reaches the layout path` guard exists | ✅ test line 390 |
| Suite 170 → 195, `cmux-exec` 54 → 79 | ✅ measured against `main` |
| Live binary `cmux 0.64.20 (100) [14e3400b9]` | ✅ ran it |
| All six falsification rows | ✅ all six exact |

**Nothing in the log contradicts the code.** Round 2's finding is fully discharged. Three small
nits, none of which would mislead a reader about behaviour:

1. **Ambiguous "round-2 judge" in the opening.** Line 3 credits "the round-2 observability judge's
   top-ranked item" — that is the **parent branch's** (pane-layout-v2) round 2. Line 66 says "on the
   parent branch"; line 3 does not, and this branch now has its own round 2. One clarifying phrase.
2. **The falsification table implies coverage it doesn't have** — it lists "mismatch receipt write
   unbraced" without noting the unreadable one has no row. Not a false statement; an inviting
   inference. See the finding above.
3. **The commit message says "Suite 186 -> 195".** The prior HEAD measured **193** (I ran it); 186
   was round 1's total. The durable log's cumulative `170 → 195` is right; only the commit message
   skips a hop, which would read as "+9 tests" when this commit added 2.

## Dimension table

| Dimension | Score | Δ | Basis |
|---|---|---|---|
| intent | **pass** | = | All five round-2 items actioned; the three deliberate non-actions are named with reasons. Nothing else. |
| execution | **pass** | = | 195/0 and the 170 baseline both re-run by me; shellcheck 0; all six mutations reproduce exactly; boundary probes match the documented table. |
| trajectory | **pass** | = | The strongest signal on the branch. The leak was reproduced with a failing test *first*; a vacuous pass in that very test was self-caught and disclosed unprompted; a seventh mutation was discarded rather than counted because it broke the `case`; each mutation was syntax-checked before its number was recorded. That is the discipline, not luck. |
| regression | **pass** | = | Five untouched suites unchanged; delta is two brace pairs plus two assertions. No new failure mode found in probing. |
| context_budget | **concern** | = | `CODING_MEMORY.md` **382** lines vs its own ≤200 ceiling — 91% over. Untouched this round; `main` is 373, so the branch is net **+9**. Trim tracked separately; not escalating. |
| traceability | **pass** | ⬆ from concern | ~20 claims spot-checked against code, all six falsification rows re-run and exact, boundary table reproduces. The contradiction is gone. Three cosmetic nits above. |
| success_masking | **concern** | ⬇ from pass | A surviving mutant on the line this commit exists to fix: unbracing the *unreadable* write reintroduces the reported `Permission denied` leak at **79/0 green**. Code correct, net incomplete. Materially smaller than round 2's original concern. |
| intent_drift | **pass** | = | Exactly the 4 expected files. No deps, no drive-by edits, no scope creep. Scope was *narrowed* (the "two open items" overstatement walked back). |
| checkpoint | **pass** | = | One self-contained, revertible commit; `origin` matches HEAD; the RO test restores `chmod 700` and leaves no `/tmp` litter (verified: dir count unchanged across a run). |
| audit_trail | **pass** | = | Commit message names the round-2 judge, states the shell trap and its sibling precedent, discloses the vacuous pass unprompted, and records the discarded mutation. ADR 0008 now describes the detector that shipped *and names its own gap*. Nit 3 above. |

## Rulings on the questions asked

### 1. Does `traceability` return to `pass`? — **Yes.**

Round 2's charge was specific: the log stated a deleted rule as fact, carried stale counts, and
quoted an unreproducible mutation row. All three are gone, and I did not take that on report — I
re-ran every falsification row and got six exact matches, including the one that previously did not
reproduce under any reading. The log now also records things that make it *harder* to trust
uncritically in the right way: which mutation was thrown away and why, which test passed vacuously
and why, and which boundary is weakest.

### 2. Is shipping forensics-without-notification acceptable in *this* PR? — **Yes. Ship it.**

Four reasons, in order of weight:

- **Notification already exists where it matters.** The two stderr lines fire at the moment of
  dispatch and `dispatch-pane-agent.sh` does not swallow adapter stderr. The receipt's job was never
  to notify; it is to survive scrollback.
- **Self-clearing turned it from a log line into state.** "This file exists" now means "wrong now",
  which is the property a reader would need anyway. Adding the reader later costs nothing extra.
- **ADR 0008 now names the gap in the ADR itself** — *"Nothing yet reads the receipt; it is
  forensics, not notification (open follow-up: a statusline reader)"*. That is the disclosure that
  makes deferral safe rather than silent; a future reader cannot mistake this for a closed loop.
- **A reader lives in a different component** with its own test surface. Bundling a statusline
  change into an adapter PR widens the blast radius for no gain.

Two conditions I would attach, neither blocking: the follow-up stays tracked (it is, in two places),
and **the first reader shipped must surface both receipt kinds**. The `unreadable` receipt is the
one nobody will ever see unaided — by construction it prints nothing — so a reader that only checks
for `found …` would recreate the original blind spot in a new place.

### 3. `context_budget` — **`concern`, scored honestly.**

382 lines against a self-imposed 200. Untouched this round, but "untouched" is not "fine": it is
182 lines over, and this branch contributed 9 of them. It stays a `concern`, not a `fail`, because
the overage is inherited (`main` is 373), the branch's own additions replaced stale content rather
than piling on, and the trim is a tracked task. If the next branch also lands +9 while calling it
out-of-scope, that pattern is the thing to escalate, not this instance.

## Concerns

1. **The brace fix's regression test covers only one of the two braced writes.** Unbracing the
   *unreadable* write — the path the bug was reported on — leaves the suite 79/0 green and
   reintroduces the `Permission denied` leak. Proved by mutation and by direct probe. One-line fix:
   loop the RO case over `0.65.0` **and** `garbage`.
2. **The receipt is still write-only.** 0 code readers, confirmed by grep. Acceptable for merge
   (ruling 2); the `unreadable` receipt is invisible by construction and must be in the first
   reader's scope.
3. **`CODING_MEMORY.md` 382 lines vs its own 200 ceiling** (ruling 3).
4. **`v0.65.0` still goes silent on stderr** (receipt written). Unchanged, endorsed twice; remedy is
   normalization, not a wider shape test.
5. **Commit message's "186 -> 195" is stale by one hop** — the prior HEAD measured 193.
6. **The branch log's opening credits "the round-2 judge"** without saying which branch's; this
   branch now has its own round 2.
7. **Three rounds of judge artifacts are still uncommitted** — `verdicts.jsonl` modified and now
   *three* untracked verdict `.md` files. Deliberate, to keep HEAD stable for `judge-guard`, but one
   `git clean -fd` destroys the audit trail for the entire review. Commit immediately after
   `gh pr create`.
8. **A mismatch nags every dispatch until a human edits the pin** — endorsed, correct trade, but
   `0.64.20-rc1` warns permanently against a `0.64.20` pin.

## What was changed

Round 2 handed back five things. All five were done, and the interesting part is *how*.

The real bug was a shell trap: writing `printf … > "$file" 2>/dev/null` does **not** silence a
failure to *open* the file — the shell complains before the `2>/dev/null` takes effect. So if the
folder the note goes into was ever read-only, the one code path advertised as "stays quiet" would
print `Permission denied` on every single dispatch. Both note-writing lines are now wrapped in
braces, which does silence it. They wrote a failing test first, and when that test passed on the
first try for the *wrong* reason (a path check aborted the run before the version check even ran),
they noticed, fixed the setup, watched it fail properly, and then wrote that whole embarrassing
detour into the commit message.

Two tests that read stronger than they were got tightened. They used to check that the version
number appeared *somewhere* in the note file — but the "can't read this" note copies the whole line,
which contains the version number, so they passed even with the old bug put back. They now check
*which kind* of note it is.

The branch notes — round 2's biggest complaint, because they still described a bug that had already
been deleted — were rewritten end to end, and the sabotage table underneath them was regenerated
from scratch with six fresh checks. And ADR 0008 now describes the alarm that actually shipped,
including an honest line saying nothing reads the note file yet.

## Does it do what you wanted?

**Yes, and this is the best-evidenced round of the three.**

Think of it like a smoke alarm. Round 1 found it was deaf to certain smells. Round 2 fixed that but
left the manual describing the deaf alarm. Round 3 rewrote the manual — and I checked the manual
line by line against the wiring. Twenty-odd claims, all correct. I also re-ran all six "cut a wire
and confirm the alarm screams" tests myself and got the *exact* numbers written down, including the
one that refused to reproduce last round.

**`traceability` goes back to `pass`.** Nothing blocks the PR.

**But I found one new thing.** The fix has two halves — two places that write the note file — and
both were fixed correctly. The new test, though, only pokes one of them. I put the bug back into
the *other* half and the whole 79-test suite stayed green, then confirmed by hand that the
`Permission denied` message really does come back. So the code is right today; it's the safety net
that has a hole in it, over the exact spot the bug was originally reported. That's a one-line test
change, not a code change.

## What could go wrong / what I'm unsure about

- **Half the brace fix has no test guarding it.** Someone tidying that line in six months gets no
  warning. Low blast radius — one extra stderr line, nothing crashes — but it is the very line this
  commit exists to fix, and the commit message reads as though both halves are covered.
- **Still nobody reads the note file.** It cleans itself up and the layout code points at it, but it
  only helps someone already digging. The "can't read this" note is the one nobody will ever see on
  their own, since it prints nothing — so whoever builds the reader must handle *both* kinds, or the
  blind spot just moves house.
- **`cmux v0.65.0` — with a `v` — still slips past the on-screen warning.** Unchanged, and still the
  right call: accepting `v` would make `v0.64.20` look different from the pin `0.64.20` and cry wolf
  on the very release that was verified.
- **The memory file is 382 lines against its own 200 limit.** Not touched this round, but not fine
  either — it's nearly double, and this branch put 9 of those lines there.
- **Once a mismatch is showing, it nags every dispatch until a human edits the pin.** Deliberate and
  I'd defend it, but if you ever track a cmux beta channel you're signing up for a standing warning.
- **Three rounds of judge write-ups are sitting uncommitted.** One stray `git clean` and the whole
  review record is gone.

## What I'd double-check before merging

1. **Nothing blocks the PR.** No dimension fails; `traceability` cleared. Open it.
2. **Make the unwritable-dir test cover both writes** — loop it over `0.65.0` *and* `garbage`. One
   line, and it closes the only new finding in this round.
3. **Commit all three rounds' verdict artifacts immediately after `gh pr create`.**
4. **When the receipt reader lands, make it surface the `unreadable` kind too**, not just
   `found …`.
5. **Two cosmetics if you're touching the docs anyway:** say *which* branch's round-2 judge in the
   log's opening line, and correct the commit trailer's `186 -> 195` to `193 -> 195` in the PR
   description (rewriting the commit is not worth it).
