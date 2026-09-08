---
phase: planning
model_tier: high
branch: TBD
---

# `panes/dispatch-pane-agent.test.sh` is 957 lines, past the 800-line hard maximum

Queued 2026-09-07 out of round 4 of the compliance judge and the final implementation-stage
observability judge on `docs/features/pane-agent-scratch-isolation.md`
(branch `fix/pane-agent-scratch-isolation`, HEAD `81f58d5`).

**Planned 2026-09-07** on `chore/pane-scratch-card-closeout` @ `1b213a1`, after PR #97 and
PR #98 merged. The four open questions below are now **decided from measurement**; the
measurements are recorded inline so a later reader can re-derive rather than re-trust.

> **Gate status: CLOSED.** No branch, no source edit. The planning → implementation
> transition opens only on the literal user phrase `gate confirmed` (`rules/gates.md`).
> Model-switch checkpoint 2 asked and answered 2026-09-07: **Sonnet high** for the
> implementation, **Opus** for both judges.

## What is wrong

`rules/core-conduct.md` Code Style sets **<400 lines preferred, 800 max**. Measured
2026-09-07 with `wc -l`:

| Ref | Lines |
|---|---|
| branch base `3ab2d57` | 771 |
| `fix/pane-agent-scratch-isolation` HEAD `81f58d5` | 957 |

The scratch-isolation card's twenty new assertions (its tasks 2 and 4) carried the file 157
lines past the ceiling. Nothing in that card's Contracts, checklist or first three judge
rounds noticed; the compliance judge raised it in round 4 and it is recorded there as a
knowingly-shipped residual rather than fixed on that branch.

### This file is not an outlier — it is the 10th worst of 12

Enumerated 2026-09-07 over `git ls-files`, excluding `docs/` and `vendor/`, at `1b213a1`:

| Lines | File |
|---|---|
| 1924 | `hooks/worktree-guard.test.sh` |
| 1911 | `treko/support.js` |
| 1470 | `hooks/reference-transaction.test.sh` |
| 1242 | `hooks/phase-guard.test.sh` |
| 1229 | `hooks/secret-command-guard.test.sh` |
| 1122 | `hooks/test-marker-guard.test.sh` |
| 1071 | `statusline-command.test.sh` |
| 1054 | `treko/test_nontext_contrast.py` |
| 959 | `hooks/git-guard.test.sh` |
| **957** | **`panes/dispatch-pane-agent.test.sh`** ← this card |
| 864 | `hooks/lib/classify-git-command.test.py` |
| 833 | `statusline-command.sh` |

Ten of the twelve are test suites. **This card deliberately fixes only its own file** —
`rules/core-conduct.md` says fix the root cause and only the root cause, and a drive-by
cleanup is its own task. The pattern is filed separately as
`docs/features/oversized-source-files.md`; the shared library this card builds (§Decision 2)
is intended as the template that card reuses.

## Why it was not fixed there

Splitting the suite is a mechanical change to the one file that is the unbiased baseline for
every other change on that branch. `rules/core-conduct.md` Testing forbids editing tests and
implementation in the same step, and doing the split in the same breath as the feature the
suite validates is exactly that. Deferring is the cheaper error.

## Baseline, measured before any edit

At `1b213a1`, both suites run green:

| Suite | Result |
|---|---|
| `panes/dispatch-pane-agent.test.sh` | **139 passed, 0 failed** |
| `panes/run-pane-agent.test.sh` | **18 passed, 0 failed** |

This is the "before" the split is proved against. Re-run and re-read it at the branch base;
do not carry these numbers forward on trust.

---

## Decisions

### Decision 1 — split axis: concern-per-file, five files

Measured 2026-09-07 by assigning all 30 `# ---` headers and 2 `# ===` banners to buckets and
summing each bucket from its section start to the next section start. The five bucket totals
plus the 37-line preamble plus the 4-line footer sum to **957**, matching `wc -l` exactly —
so no section was dropped or double-counted.

| # | File | Concern | Body lines | With preamble+footer |
|---|---|---|---|---|
| A | `dispatch-pane-agent.dispatch.test.sh` | happy path, launcher shape, `--role`/`--model`/validation failures, F1/F4 regressions | 101 | 142 |
| B | `dispatch-pane-agent.routing.test.sh` | set-policy, read_policy, lane/session markers, live worker count, overflow, round-robin, open_tab streaks, cooldowns, degrade paths | **574** | **615** |
| C | `dispatch-pane-agent.cleanup.test.sh` | `cleanup_stale` / run-dir + work-child retention | 97 | 138 |
| D | `dispatch-pane-agent.scratch.test.sh` | work-child dir, `prompt.md` preamble | 98 | 139 |
| E | `dispatch-pane-agent.subcommands.test.sh` | `wait`, `handoff` | 46 | 87 |

**A fifth concern exists that the original card did not name.** `wait` and `handoff` are
independent dispatcher subcommands belonging to none of the four buckets the card listed.
They get their own file rather than being forced into one.

**B stays whole at ~615 lines** — within the 800 hard maximum, over the 400 preferred. This
is a **knowing residual, recorded not hidden.** Splitting B further is deferred because B
carries a real intra-bucket order dependence: the "worker at/over max" assertions
(`# ---` at line 288) consume the two live-worker fixtures and the `set-policy panes --max 1`
call made earlier in the Task 6 section (line 228) under the same session key. Cutting
between them would require re-creating that fixture, which is the kind of duplication this
split exists to reduce. Revisit only if B grows again.

**Two placements are judgment calls, recorded so a reviewer can disagree cheaply:**

- The `no terminal` and `adapter failure writes the cooldown flag` sections (lines 83, 90,
  ~13 lines) are scored to **B** because the card names cooldowns as routing. They are
  equally defensible as A (basic dispatch error paths).
- The `cleanup_stale` work-child section (line 866) is scored to **C** because the function
  under test is `cleanup_stale`. If the axis is "the feature owns its tests" rather than "the
  function owns its tests" it belongs in **D**, making C 9 lines and D 186 — both still under
  400 either way, so the choice does not change compliance.

### Decision 2 — shared harness: `panes/test-lib.sh`, skeleton only

Measured: **only `ok()` and `bad()` are called from more than one bucket.** Every other
helper — `call_read_policy`, `mk_run`, `mk_run_ref`, `tf_dispatch`, `tr_dispatch`,
`mk_stale_run`, `call_count_workers` (all B), `call_cleanup_stale`, `ts_hours_ago`,
`ts_days_ago` (all C) — is used exclusively inside the one bucket that defines it. A
whole-bucket-per-file split therefore relocates no helper except the two counters.

The library carries **only the skeleton**:

- `MARKER_SELF` / `MARKER_ROOT` resolution
- `TMP=$(mktemp -d)` and the `trap 'rm -rf "$TMP"' EXIT`
- `pass=0; fail=0` and the `ok()` / `bad()` definitions
- the `%s passed, %s failed` summary and the `write-test-marker.py` footer

It carries **none of the domain fixtures** — `detect.sh`, the recording adapter, `PROMPT`,
and the `PANE_*` exports stay per-file, because the adapter stub alone is overwritten by
section-specific bodies at 18 further points in the file and bucket C never dispatches
through the CLI at all.

**This library already has a second consumer today.** `panes/run-pane-agent.test.sh`
duplicates roughly ten lines of exactly this skeleton byte-for-byte — the marker resolution,
the mktemp/trap pair, the counter init, the summary line and the three-line marker footer are
character-identical between the two files. Converting it to source the library is part of
this card, and is what proves the library is genuinely shared rather than a one-file
abstraction. `run-pane-agent.test.sh` keeps its own five-argument `check()` helper and its
`claude`-binary stub; those are not skeleton and do not move.

### Decision 3 — proof that the split lost nothing: set membership, with a falsifier

A total that still adds to 139 is not proof; an unchanged count can hide a swap.

The check is **set equality over the 139 assertion labels**, before against after.

Measured 2026-09-07 at `1b213a1`: **139 `ok` calls, 139 `bad` calls, 139 distinct labels,
zero duplicates.** Set membership is therefore viable — no label is repeated, so a
before/after set diff cannot be defeated by collision.

**⚠️ The extractor must understand escaped quotes, or the proof reports a loss that never
happened.** Two labels contain escaped inner quotes:

```
753:[ "$rc" -ne 0 ] && ok "--model \"a b\" (shape-invalid) -> non-zero exit" \
755:[ "$before_count" = "$after_count" ] && ok "--model \"a b\" -> no pane opened" \
```

A naive `grep -o 'ok "[^"]*"'` stops at the first escaped quote, collapses both to the string
`--model \`, and reports **138 distinct with one duplicate** — a false finding, measured
2026-09-07. Use an extractor whose string rule is `(?:[^"\\]|\\.)*`, and record the exact
extraction command in the commit so the proof is reproducible.

**The proof must itself be falsified before it is trusted:** delete one label from the
"after" set and confirm the check names that specific label. A comparison that has never been
observed failing is not evidence. Also assert the four non-`&&`/`||`-shaped call sites are
still counted — verified 2026-09-07 to be exactly four (lines 163, 348, 662–663 as `case`
arms; 762–765 as an `if`/`else`), confirming the figure the original card carried.

### Decision 4 — the `ok`/`bad` label divergence is NOT fixed in this pass

48 of 135 pairs spell the two labels differently, which defeats matching a failure by its
pass text. It is a separate change to the same file, and bundling it would make the set-equality
proof of Decision 3 meaningless — the label set is exactly what that change rewrites. It gets
its own card and its own branch, after this one lands.

---

## The hazard this split creates, and the order it must be fixed in

**Hardening comes first, in its own commit, before a single line moves.** Splitting reorders
execution, and one existing assertion is safe only by accident of position.

Enumerated 2026-09-07 — every `find` over `$PANE_STATE_DIR`, classified by whether it scopes
to a timestamp marker:

| Line | Scoped? | Shape |
|---|---|---|
| **45** | **no** | `launcher=$(find … -name launch.sh \| head -n 1)`; asserts non-empty |
| 140, 271, 285, 462, 761, 782, 803, 857, 860 | yes | `-newer "$TMP/<marker>"` |
| 749 / 752 | no | before/after **difference** pair |
| 837 / 839 | no | before/after **difference** pair |

Five calls are unscoped, but **four of them are difference pairs and are order-safe by
construction** — they measure a delta between two adjacent reads, not an absolute.

**Line 45 is the single genuinely order-sensitive lookup**, and its failure mode is the
dangerous one: it asserts only that *some* `launch.sh` exists anywhere under the run tree. It
works today because it is the first dispatch in the file and nothing else has written one
yet. After a reorder, a `launch.sh` left by any earlier test satisfies it — so the assertion
does not break, it goes **vacuous**, passing whether or not the dispatch under test created a
launcher. A green count would report success while the assertion measured nothing.

This is not hypothetical: the file's own authors hit this exact hazard twice and fixed it
both times with a `touch` marker plus `-newer` (their comments at lines 131–137 and 262–268
record it). Line 45 was never given the same treatment.

Two further pieces of shared, cross-section-mutable state to preserve when relocating:

- `$PANE_STATE_DIR/{panes,tabs,tabtargets}` are ad-hoc counter files that two sections
  explicitly `rm -f` immediately before use (lines 561, 652) — evidence the authors know
  these are not zeroed by the preamble.
- Bucket C's `CS_25H` fixture deliberately leaves a stray `launch.sh` behind after pruning
  (to prove sibling files survive), and its own comment (lines 872–876) says it calls
  `cleanup_stale` directly precisely so an unrelated dispatch cannot disturb it. C is last
  today by position, not by design. Once each bucket is its own file with its own `TMP`, this
  resolves — but it must be verified, not assumed.

---

## Checklist

- [ ] 1. Cut the branch, record it in this file's frontmatter, move `phase` to
  `implementation`. (Gate transition — `gate confirmed` only.)
- [ ] 2. Re-run both suites at the branch base and re-read the output. Record the counts.
  Do not carry §Baseline forward on trust.
- [ ] 3. Write the label-extraction script (escape-aware, per Decision 3) and capture the
  "before" label set. **Falsify it**: delete one label from a copy and confirm the check names
  that label. Record the command and the falsifier result.
- [ ] 4. **Harden line 45** with a `touch` marker + `-newer`, matching the pattern at lines
  140 and 271. Own commit, before any code moves. Re-run: still 139/0.
- [ ] 5. Create `panes/test-lib.sh` with the skeleton from Decision 2. No behavior change yet.
- [ ] 6. Convert `panes/run-pane-agent.test.sh` to source it. Re-run: still 18/0. This proves
  the library works before the big file depends on it.
- [ ] 7. Split `dispatch-pane-agent.test.sh` into the five files of Decision 1, each sourcing
  the library and carrying its own domain fixtures. Delete the original.
- [ ] 8. Run all five new files plus `run-pane-agent`. Assert the union of their labels is
  **set-equal** to the "before" set from task 3 — not merely the same total.
- [ ] 9. `wc -l` every new file. Assert each is under 800; record which are over the 400
  preferred (B is expected to be, at ~615) as a named residual.
- [ ] 10. Check the test-marker mechanism: five files where there was one means five markers.
  Verify `hooks/test-marker-guard.sh` still passes for a commit staging them, and that
  `write-test-marker.py` is invoked once per file, not once for the set.
- [ ] 11. Grep the repo for references to `panes/dispatch-pane-agent.test.sh` by name — CI
  wiring, docs, ADRs, other cards — and update every one. A stale reference to a deleted file
  fails closed and reads as the tests being switched off.
- [x] 12. File `docs/features/oversized-source-files.md` recording the twelve-file table and
  naming this card's library as the template. **Done 2026-09-07 during planning** — written
  before the branch exists, so the measurement is not lost if this card stalls. Re-read it at
  task 13 and correct anything the split proved wrong.
- [ ] 13. Observability judge (Opus) on the diff; act on findings.
- [ ] 14. Open the PR. Update this card to `review` when it merges.

## Not in scope

- The `ok`/`bad` label divergence (Decision 4) — its own card.
- The other eleven oversized files — `docs/features/oversized-source-files.md`.
- Splitting bucket B below 400 lines — deferred with a stated reason (Decision 1).
