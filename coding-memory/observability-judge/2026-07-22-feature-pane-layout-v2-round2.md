# Observability Judge Verdict — pane-layout-v2 (implementation, gating) — ROUND 2

- **Repo:** `.claude` · **Branch:** `feature/pane-layout-v2`
- **HEAD:** `ec03621b3efd56dce434015188c16596258263ed` (pushed; `origin` matches)
- **Base:** `main` (merge-base `98faa38e4c21bc354ca98c79dfc7560c96e71573`)
- **Stage:** implementation (gates the PR)
- **Round 1:** `2026-07-22-feature-pane-layout-v2.md` @ HEAD `e12dc06` — passed, risk=low,
  concerns `success_masking` + `audit_trail`. Read first; this verdict scores only the delta
  and re-confirms the unchanged surface.
- **Risk:** low · **Confidence:** high

> **Filename note.** Round 1 occupies `2026-07-22-feature-pane-layout-v2.md` — same date, same
> branch slug. ADR 0008 cites that file *by name*, so overwriting it would delete the audit
> trail this round exists to credit, and would break the ADR's only inbound reference. This
> round is therefore suffixed `-round2` inside the same mandated directory.
> `hooks/judge-guard.sh` keys on `verdicts.jsonl` (`repo`+`branch`+`head_sha`+`stage`), never on
> the markdown filename, so the suffix cannot affect the gate.

## Delta verification — checked, not trusted

The claim was "docs-only." Verified via `git diff --name-status e12dc06..HEAD`:

| File | Change |
|---|---|
| `docs/decisions/0008-aux-column-position-over-height.md` | **A** (+69) |
| `CODING_MEMORY.md` | **M** (+34 / −1) |
| `coding-memory/observability-judge/2026-07-22-feature-pane-layout-v2.md` | **A** (+180) |
| `coding-memory/observability-judge/verdicts.jsonl` | **M** (+1) |

One commit (`ec03621`). **No source, test, or fixture file touched** — claim holds. Full branch
diff is 23 files, +4600 / −67.

## Test evidence — run by me, not taken on report

All six suites re-executed against this tree: `cmux-exec` 54/0, `cmux-layout` 34/0, `adapters`
24/0, `dispatch-pane-agent` 39/0, `run-pane-agent` 10/0, `terminal-detect` 9/0 — **170 passed, 0
failed**. `shellcheck -x` on the four named scripts exits 0, silent. Counts are identical to
round 1, which is exactly what a docs-only delta must produce; a divergence here would have
falsified the claim. Round 1's three independent falsification re-runs are not repeated — they
pin source that provably did not change.

## Dimension table

| Dimension | Round 1 | Round 2 | Basis |
|---|---|---|---|
| intent | pass | **pass** | The delta is precisely what round 1 asked for, and nothing else. |
| execution | pass | **pass** | 170/0 re-run by me; shellcheck clean. |
| trajectory | pass | **pass** | Strengthened. Two highest-value items actioned; the rest deferred *with stated reasons*; one suggestion correctly rejected on standing user instruction. Rejecting a judge with a reason is better trajectory than complying without one. |
| regression | pass | **pass** | Zero source touched (verified by name-status, not asserted); suite counts unchanged. |
| context_budget | pass | **concern** | **Downgraded — new information.** See concern 3. |
| traceability | pass | **pass** | Improved: ADR 0008 adds a durable *why* plus an explicit supersede trigger. |
| success_masking | concern | **concern** | **Unchanged.** See concern 1. |
| intent_drift | pass | **pass** | Docs-only, responsive, no scope creep, no new deps. |
| checkpoint | pass | **pass** | Single clean docs commit, revertible, pushed, `origin` matches HEAD. |
| audit_trail | concern | **pass** | **Cleared.** See below. |

### `audit_trail`: concern → **pass**

Round 1's basis was two-part, and both parts are discharged:

1. *No ADR for a frozen spec assumption failing live.* ADR 0008 now exists in the durable
   numbered series. It is substantive, not ceremonial: it records the position-over-height trade,
   the three independent grounds for unfixability (flat `panes` array with no geometry;
   `new-split`/`new-pane` both pane-relative so height follows the anchor; `--placement dock`
   disabled by cmux itself), **two rejected alternatives** (anchor-on-main, and the Correction-28
   `focus-pane`+`new-pane` route — rejected as racier and not a height fix), and a supersede
   trigger. That last item is what makes it an ADR rather than a note: it tells a future
   maintainer the exact condition under which to reopen it.
2. *`CODING_MEMORY.md` stopped at Task 7.* Resumes #8–#9 now cover Tasks 7–9, probe P8,
   corrections 27–28, and the round-1 verdict.

**Does it merely restate the problem?** For `audit_trail`, no — attributability is the whole
axis, and the record is now durable, dated, cross-referenced, and reopenable. But the ADR
improves a maintainer's odds of *understanding* the failure once noticed; it does not improve
the odds of *noticing* it. That is `success_masking`, which is a different dimension and stays
where it was. Documentation cannot discharge a detection gap. Splitting these two honestly is
the core finding of this round.

## Concerns

1. **`success_masking` is unmoved, and correctly so.** No code or test changed, so all four
   round-1 items stand verbatim: the undetectable `layout_rightmost_surface` heuristic; the
   never-live-executed verify-after-rename *repair* path; "missing run dir = finished" now paired
   with reuse-by-`send` (types `bash <launcher>` into whatever process lives there); and the thin
   one-stderr-line degrade signal. The ADR names the first of these as the main latent risk in my
   own framing — accurate, and still not a detector.

2. **The "procedural mitigation only" call is defensible in principle but under-built in
   practice — and I can name what would suffice.** A *geometric* self-check is genuinely
   impossible: with a flat array carrying no orientation or geometry, nothing at runtime can
   verify "max-index is actually rightmost." That is the same limitation that makes option 3
   unreachable, so "procedural" is forced, not lazy — this half of the rejection is sound.
   **But the trigger condition is trivially detectable and was not wired up.** The validated
   version, cmux **0.64.20**, is recorded in the spec, in ADR 0008, and in a `cmux-layout.sh`
   comment — yet no runtime path compares against it, and `panes/cmux-layout-probe.sh:26`
   *already* shells `cmux version`, so the mechanism exists and is proven cheap. Pinning that
   string as a constant and emitting a distinct stderr line (or a state file) on mismatch
   converts "remember to re-run the probe after an upgrade" from an unenforced human habit into
   a machine-detected event — and the same signal widens the degrade breadcrumb, so **one small
   detector answers both round-1 item 3 and item 4**. Not a merge blocker; the single highest-
   value follow-up on the list.

3. **`CODING_MEMORY.md` is 369 lines against an explicit ≤200 budget, and this delta added 34 to
   it.** `managing-session-memory` line 17 is unambiguous — *"Keep it an index, ≤200 lines … Move
   PR history, session logs, decisions, branch logs … into `coding-memory/<topic>.md` files,
   linked by path — never inlined back into the index."* Resume #9 is a ~23-line narrative whose
   content already lives in `coding-memory/branches/pane-layout-v2.md` §P8 and now, a second
   time, in ADR 0008. This file is restored at session start, so the overrun is paid every
   session. Round 1 did not weigh this because its delta was +6 on-demand skill lines; this
   delta's centre of mass is the always-restored index, so the dimension is scored fresh rather
   than inherited. The added content is high-value and trimming is tracked as its own task — but
   "tracked, not attempted" is the exact mechanism by which budgets are blown, and the file is
   now 84% over. Remedy is small: replace #9's narrative with a two-line pointer to the ADR and
   the branch log, which are the durable homes the rule names.

4. **The dirty-files rejection is right on the merits but stops one step short.** The standing
   instruction not to commit `chrome/chrome-native-host` and `settings.json` is correct and I
   withdraw the round-1 "commit or stash." **But `git ls-files -v` reports `H` for both — they
   are plain tracked files with no `skip-worktree` and no `assume-unchanged`, and
   `git check-ignore` confirms neither is ignored.** So "never commit these" is enforced by
   discipline alone: a single `git commit -a` or `git add -A` sweeps them in, and their diff
   matches absolute-path/credential-shaped patterns, which core-conduct forbids in committed
   files. "Expected to stay dirty indefinitely" is therefore not a safe resting state for a
   *tracked* file. Cheapest correct fix: `git update-index --skip-worktree` on both. Fuller fix:
   untrack, gitignore, commit a `.template` alongside. Outside this branch's scope and not a
   blocker — but it should not be recorded as settled. This is also what the doc-guard warning
   at session start was firing on.

5. **Round-1 follow-ups carried post-merge are appropriately classified.** The wider degrade
   signal was a follow-up in round 1 and remains one; nothing about the delta changed its
   severity. Concur.

6. **Procedural trap: committing this verdict before `gh pr create` restarts the staleness
   loop.** Round 1 was invalidated by committing its own audit trail. `CODING_MEMORY.md`'s NEXT
   ACTION already encodes the fix — open the PR with the verdict uncommitted, commit the audit
   trail immediately after. Flagged because the failure mode is self-similar and silent: each
   round-N verdict, if committed first, invalidates itself and summons round N+1.

## What was changed

Nothing that runs. Round 1 left five homework items; this commit does the two paperwork ones. A
decision record (ADR 0008) now explains, in the repo's permanent numbered series, why the
side-agent column sits in the right *place* even though it sometimes comes out the wrong
*height* — including the three reasons it can't be fixed with today's cmux, the two alternatives
that were tried and rejected, and the one future change that would make it worth revisiting. The
long-term memory index was also brought up to date from Task 7 to Task 9. Think of it as filing
the incident report and updating the logbook after the repair was already signed off: the machine
is untouched, but the next person now knows why it was left that way.

## Does it do what you wanted?

Yes. The docs-only claim is true — I checked file by file rather than trusting it, and re-ran all
170 tests plus shellcheck to confirm the source really is untouched.

**`audit_trail` moves to `pass`.** ADR 0008 is a real ADR, not a restatement. The thing that
convinced me is the supersede trigger: it tells a future maintainer exactly when to reopen the
decision (if cmux re-enables dock placement or exposes pane geometry). A note says "this is
broken"; an ADR says "this is broken, here's what we chose instead, here's what we rejected, and
here's the signal that means go fix it." This is the second.

**`success_masking` stays `concern`, and that is not a technicality.** You asked whether the ADR
discharges it. It doesn't, and it can't — no document can. The risk is that a future cmux
upgrade silently puts your column in the wrong place while all 170 tests stay green. Writing
that sentence down in an ADR helps someone *diagnose* it after they've noticed their panes look
odd; it does nothing to help them *notice*. Understanding and detection are different problems,
and only the first one got solved here.

**`context_budget` slipped from `pass` to `concern`** — new, and not carried over from round 1.
The memory index is now 369 lines against its own documented 200-line ceiling, and this commit
added 34 of them in exactly the inlined-narrative form the rule says to keep out. Small fix,
worth doing before it compounds.

## What could go wrong / what I'm unsure about

- **The one real gap is still a missing smoke alarm, not a missing manual.** You now have an
  excellent manual. But if cmux changes how it walks its panes, your aux column lands in the
  wrong spot, every test still passes, and the only symptom is that your screen looks slightly
  off. The ADR says the mitigation is "re-run the probe after any cmux upgrade," which is a
  reminder living in a file that nobody reads on upgrade day.
- **That reminder can be automated, and I want to be specific rather than hand-wave.** You
  can't check the *geometry* — the pane list is flat, so there's genuinely nothing to compare
  against; that part of the "procedural only" argument is correct. But you *can* check the
  **version**: you already know the good one is 0.64.20, it's written in three places, and your
  probe script already runs `cmux version` on line 26. Pin it, compare it at layout time, and
  say something loud when it differs. That turns "hope someone remembers" into "the tool tells
  you," and the same message doubles as the louder degrade signal you deferred. One small change
  closes two open items.
- **The two "machine-local" files are tracked, which is the part I'd push back on.** You're
  right not to commit them — I withdraw that suggestion. But git still considers them yours to
  commit: no skip-worktree, not ignored. Leaving a *tracked* file permanently dirty means one
  absent-minded `git commit -a` publishes local paths and credential-shaped strings. `git
  update-index --skip-worktree` on both takes seconds and makes the rejection actually stick.
- **The memory file is drifting past its own limit** while pointing at two files that already
  hold the same story.
- **Don't commit this verdict before opening the PR.** That's what invalidated round 1 and
  created round 2. Your own memory note already says so.

## What I'd double-check before merging

1. **Nothing blocks the PR.** No dimension fails; both concerns are documented, bounded, and
   non-corrupting. Open it.
2. **Open the PR with this verdict file uncommitted**, then commit the audit trail right after —
   otherwise HEAD moves and the gate demands a round 3.
3. **Post-merge, first follow-up: the cmux version gate.** Highest value-per-line item left, and
   it retires two round-1 concerns at once.
4. **Two minutes now: `git update-index --skip-worktree chrome/chrome-native-host settings.json`.**
   Makes "never commit these" real instead of aspirational.
5. **Trim Resume #9 to a pointer** when you get to the tracked memory-trimming task; the detail
   is already in the branch log and ADR 0008.
