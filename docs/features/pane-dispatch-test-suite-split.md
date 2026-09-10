---
phase: implementation
model_tier: high
branch: refactor/pane-dispatch-test-suite-split
---

# `panes/dispatch-pane-agent.test.sh` is 957 lines, past the 800-line hard maximum

Queued 2026-09-07 out of round 4 of the compliance judge and the final implementation-stage
observability judge on `docs/features/pane-agent-scratch-isolation.md`
(branch `fix/pane-agent-scratch-isolation`, HEAD `81f58d5`).

**Planned 2026-09-07** on `chore/pane-scratch-card-closeout` @ `1b213a1`, after PR #97 and
PR #98 merged. **Revised 2026-09-08 after compliance judge round 1 returned FAIL with six
violations** — all six accepted, none waived. What changed is recorded in §Revision history.

> **Gate status: OPEN.** The user gave the literal phrase `gate confirmed` on 2026-09-09,
> after reading the spec. Branch `refactor/pane-dispatch-test-suite-split` cut from `656a09e`,
> which carries the three planning commits (`f0d8a53`, `6efcb0c`, `c0da316`) plus this one, so
> the plan and its implementation travel in one PR.
> Model-switch checkpoint 2 asked and answered 2026-09-07: **Sonnet high** for the
> implementation, **Opus** for both judges.
>
> **Compliance ledger: round 1 FAIL (6), round 2 FAIL (3), round 3 PASS (0).** Nine findings
> accepted, zero waived. Verdicts in `coding-memory/compliance-judge/`.

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

**Settled by execution 2026-09-09** (task 2), at branch base `8a26ab5`, run from the worktree
`~/.claude/.claude/worktrees/secret-command-guard`:

| Suite | Exit | Summary line | `ok   — ` emissions | `FAIL — ` emissions |
|---|---|---|---|---|
| `panes/dispatch-pane-agent.test.sh` | 0 | `139 passed, 0 failed` | 139 | 0 |
| `panes/run-pane-agent.test.sh` | 0 | `18 passed, 0 failed` | 18 | 0 |

The emission columns are counted from the captured stdout, not read off the summary line, so
the summary and the actual number of `ok` calls corroborate each other rather than one being
taken on trust. The `1b213a1` figures above are reproduced exactly at the branch base.

---

## Decisions

### Decision 1 — split axis: concern-per-file, **six** files

The file has **31** `# ---` headers and **2** `# ===` banner blocks (four `# ===` rule lines,
at 768/774 and 866/877): **33 sections**. Each bucket is summed from its section start to the
next section start; the last runs to 954, where the footer begins.

**The mapping is published as header line numbers, not as prose.** Judge round 1 could not
re-derive it from concern descriptions — judging blind it scored the `--model passthrough`
section (`:736`) into routing rather than dispatch, producing 69/606 instead of 101/574. The
sums close for exactly one assignment, so the assignment *is* the spec.

| File | Concern | Section headers | Body | + skeleton |
|---|---|---|---|---|
| `dispatch-pane-agent.dispatch.test.sh` | happy path, launcher shape, `--role`/`--model`/validation, F1/F4 regressions | 38, 60, 72, 151, 167, 736 | 101 | 142 |
| `dispatch-pane-agent.policy.test.sh` | no-terminal + adapter-failure cooldown, set-policy, read_policy (incl. the `NEW-A (pair pin)` wrap case moved in), lane/session markers, live worker count, at/over-max overflow | 83, 90, 175, 202, 228, 259, 279, 288, 295 **+ `:697-703`** | 162 | 203 |
| `dispatch-pane-agent.routing.test.sh` | surface-ref fixtures, round-robin, tab targeting, degrade paths, open_tab failure streaks, final-review carry-forwards | 316, 333, 364, 382, 398, 412, 435, 475, 533, 674 **− `:697-703`** | 412 | 453 |
| `dispatch-pane-agent.cleanup.test.sh` | `cleanup_stale` / run-dir + work-child retention | 96, 866 | 97 | 138 |
| `dispatch-pane-agent.scratch.test.sh` | work-child dir, `prompt.md` preamble | 768, 794, 820, 849 | 98 | 139 |
| `dispatch-pane-agent.subcommands.test.sh` | `wait`, `handoff` | 105, 127 | 46 | 87 |

**Derivation, reproducible — the numbers above are the output of this, not hand-arithmetic:**

```sh
python3 - panes/dispatch-pane-agent.test.sh <<'EOF'
import sys
lines = open(sys.argv[1]).read().split("\n")
starts = sorted([i for i,l in enumerate(lines,1) if l.startswith("# ---")] + [768, 866])
END = 954
span = {s: (starts[j+1] if j+1 < len(starts) else END) - s for j,s in enumerate(starts)}
BUCKET = {
 "dispatch":    [38,60,72,151,167,736],
 "policy":      [83,90,175,202,228,259,279,288,295],
 "routing":     [316,333,364,382,398,412,435,475,533,674],
 "cleanup":     [96,866],
 "scratch":     [768,794,820,849],
 "subcommands": [105,127],
}
allsec = sorted(x for v in BUCKET.values() for x in v)
assert allsec == starts, set(starts) ^ set(allsec)   # exactly-once partition
tot = 0
for k, secs in BUCKET.items():
    n = sum(span[s] for s in secs); tot += n
    print(f"{k:12s} {n:4d} body  {n+41:4d} with skeleton")
print("body", tot, "+ 37 preamble + 4 footer =", tot+41)
assert tot + 41 == 957
# The one sub-section move: the read_policy wrap case leaves routing for policy.
# Content is :697-703 (7 lines); the move carries the blank separator at :696, so 8.
WRAP = 703 - 697 + 1 + 1                  # 7 content + 1 separator blank
print("after the wrap move -> policy", 154 + WRAP, " routing", 420 - WRAP)
assert 154 + WRAP == 162 and 420 - WRAP == 412
EOF
```

The `assert allsec == starts` is what makes this a **partition** rather than a plausible
grouping: it fails if any section is dropped or claimed twice. The final assert pins the total
against `wc -l`. Both must pass before task 7 begins.

**A sixth concern exists that the original card did not name.** `wait` and `handoff` are
independent dispatcher subcommands belonging to none of the four buckets that card listed.

**Why routing was cut from policy** (this reverses the first revision). That draft kept all
574 routing-and-policy lines in one file at ~615 and justified it by an intra-bucket fixture
chain. Measured, the `CSID` chain spans sections 228, 259, 279, 288, 295 — lines 228–315,
**88 lines**. **Seventeen** session keys are assigned in the file
(`grep -cE '^[A-Z][A-Z0-9_]*SID='` = 17, at `:157, 177, 237, 299, 339, 368, 387, 402, 417,
425, 448, 487, 514, 559, 593, 647, 686`). **The load-bearing fact is narrower than "every
other section defines its own key"** — 17 sections define none at all, so that phrasing was
false and is corrected here: what is true, and what the cut rests on, is that **no line outside
228–297 references `CSID`** (`grep -n CSID`, last use `:297`). `UMAX_SID` (`:299`) sits inside
the claimed chain and defines its own key, so the true dependency ends at `:297`, not `:315`;
the cut at `:316` is unaffected. The chain justified keeping 228–315 together, never all 574.

**The cut is engineered to cost zero relocations.** Judge round 2 measured that the naive cut
crossed twice, not once: `call_read_policy` (`:207`) **and** `RP_DIR` (assigned `:206`,
consumed at `:701-702`). Under the file's `set -u`, a `routing.test.sh` holding `:701-702`
would abort with `RP_DIR: unbound variable`. Rather than relocate either symbol, **the
`read_policy` wrap case moves to `policy.test.sh`**, where its five sibling `read_policy`
cases already live. That is where it belongs on the concern axis anyway. After the move both
symbols are policy-local, `call_read_policy` does **not** enter the shared library, and no
variable crosses a file boundary.

**The block is `:697-703`** — the comment beginning `# NEW-A (pair pin)` through the
`read_policy: 64-bit-wrapping N -> empty` assertion. Seven content lines; the move takes
**8**, carrying the blank separator at `:696` with it, which is why the delta below is 8 and
not 7. (An earlier revision cited the range as `:696-703`, whose first line is blank — the
arithmetic was right, the citation was not.)

| | Section body | `:697-703` delta | Final body | + skeleton |
|---|---|---|---|---|
| `policy.test.sh` | 154 | **+8** | **162** | **203** |
| `routing.test.sh` | 420 | **−8** | **412** | **453** |

**Remaining residual, stated not hidden:** `routing.test.sh` lands at **453 lines with the
skeleton** — under the 800 hard maximum, over the 400 preferred. No further cut is proposed
because no measurement supports a boundary yet; if it is cut again it should be on a measured
fixture boundary, the way this cut was. The first revision's 615-line residual was
under-argued in the same shape as the residual that created this card, which is why it did not
survive review.

**One placement is a judgment call, recorded so a reviewer can disagree cheaply:** the
`cleanup_stale` work-child section (`:866`) is scored to cleanup because the function under
test is `cleanup_stale`. If the axis is "the feature owns its tests" it belongs in scratch,
making cleanup 9 lines and scratch 186 — both still under 400, so the choice does not change
compliance either way.

### Decision 2 — shared harness: `panes/test-lib.sh`

Measured: **`ok()` and `bad()` are the only helpers called from more than one bucket.** Every
other helper — `call_read_policy`, `mk_run`, `mk_run_ref`, `tf_dispatch`, `tr_dispatch`,
`mk_stale_run`, `call_count_workers`, `call_cleanup_stale`, `ts_hours_ago`, `ts_days_ago` — is
used inside exactly one bucket once the `:697-703` move of Decision 1 lands. **No variable
crosses a file boundary either** — judge round 2 caught `RP_DIR` (`:206` → `:701-702`) doing
so, which under `set -u` would have aborted `routing.test.sh` with `RP_DIR: unbound variable`;
the move removes the crossing rather than papering it with a relocation.

#### Contract

The library is **sourced, not executed**. It defines and exports nothing else.

| Symbol | Kind | Contract |
|---|---|---|
| `MARKER_SELF` | var | absolute path of the **sourcing** script. Built from `$0`, which under `source` is the caller — this is correct but subtle, and is why it must live in the library rather than be passed in. |
| `MARKER_ROOT` | var | `git rev-parse --show-toplevel`, and **`\|\| exit 1` — not `return 1`.** Measured by the judge: `return 1` from a sourced file is **fail-open** — the caller keeps running with `MARKER_ROOT` unset and exits 0, so a suite outside a repo would report green. `exit` from a sourced file exits the *caller*, preserving today's fail-closed `:12` semantics. |
| `TMP` | var | fresh `mktemp -d`, per sourcing script. **The library also owns the `trap 'rm -rf "$TMP"' EXIT`** — it creates the directory, so it installs the cleanup. No caller may install its own EXIT trap (see the `tl_finish` note below). |
| `pass`, `fail` | var | initialised to 0. |
| `ok "<label>"` | fn | prints `ok   — <label>`, increments `pass`. |
| `bad "<label>" [detail]` | fn | prints `FAIL — <label> (detail)`, increments `fail`. |
| `tl_finish` | fn | prints the `%s passed, %s failed` summary, writes the test marker when `fail` is 0, and returns `fail -eq 0`. |

**Caller contract, in order:** `. "$(dirname "$0")/test-lib.sh"` as the first executable line
after `set -u`; then domain fixtures; then assertions; then **`tl_finish` as the last line**,
and the script's exit status is `tl_finish`'s.

**⚠️ The footer cannot simply move into the library.** At `:954-957` it is a top-level
statement that runs *last*. In a sourced file it would run at source time — first, with
`pass=0 fail=0` — reporting a green empty suite and writing a test marker for a suite that
never ran. That is the exact failure class this card is trying to prevent: a receipt for work
not done. Hence `tl_finish` is an explicit call, not top-level code. A `trap … EXIT` was
considered and rejected: the file already installs `trap 'rm -rf "$TMP"' EXIT`, and a second
EXIT trap would replace it and leak the temp dir.

The library carries **no domain fixtures** — `detect.sh`, the recording adapter, `PROMPT` and
the `PANE_*` exports stay per-file. The adapter stub alone is overwritten by section-specific
bodies at 18 further points in the file, and cleanup never dispatches through the CLI at all.

#### The second consumer, and the limit of that claim

`panes/run-pane-agent.test.sh` duplicates the skeleton byte-for-byte today — verified with
`diff`: `:5,6,8,9,17` against `dispatch-pane-agent.test.sh:11,12,15,16,34`, and `:191-194`
against `:954-957`. Converting it is part of this card.

**But it defines no `ok()`/`bad()`** — it uses a five-argument `check()` at `:18` plus 15
inline `printf 'ok …'; pass=$((pass+1))` pairs. So sourcing the library hands it two functions
it never calls. **The honest claim is: the skeleton has two consumers; `ok`/`bad` have one.**
Converting `run-pane-agent.test.sh` proves the skeleton and `tl_finish` work under a second
caller — which is the part that carries risk — and proves nothing about the assertion helpers.

### Decision 3 — what the "nothing was lost" check does and does not prove

A total that still adds to 139 is not proof; an unchanged count can hide a swap. The check is
**set equality over the 139 assertion labels**, before against after.

Measured 2026-09-07 at `1b213a1`: **139 `ok` calls, 139 `bad` calls, 139 distinct labels,
zero duplicates.** No label repeats today, so a set diff is not defeated by collision *at the
baseline* — but see the duplicate row in the blind-spot table, which is about the after-set.

#### Two label sets, not one — they answer different questions

Judge round 2 found the first revision used "the label set" to mean source extraction in the
checklist and runtime emission in the scenarios, and never defined the runtime side. They are
both needed and they prove different things:

| | `SOURCE-SET` | `RUN-SET` |
|---|---|---|
| How | `panes/label-set.py <files…>` parses the `ok "…"` literals out of the **source** | capture each suite's **stdout**, strip the `ok   — ` and `FAIL — ` prefixes |
| Proves | no assertion was **deleted from the source** during the move | every assertion **actually executed** |
| Blind to | whether the code ever ran | an assertion deleted from a file the runner never invoked |

`RUN-SET` must strip **both** prefixes — a label emitted as `FAIL — <label>` still ran, and
counting only `ok   — ` would make a genuinely failing assertion look like a lost one.
Task 8 compares `SOURCE-SET` before against `SOURCE-SET` after, **and** asserts
`RUN-SET after == SOURCE-SET after`. The first catches a deletion; the second catches a file
that never ran or died partway.

**⚠️ The extractor must understand escaped quotes.** Two labels contain them:

```
753:[ "$rc" -ne 0 ] && ok "--model \"a b\" (shape-invalid) -> non-zero exit" \
755:[ "$before_count" = "$after_count" ] && ok "--model \"a b\" -> no pane opened" \
```

A naive `grep -o 'ok "[^"]*"'` stops at the first escaped quote, collapses both to `--model \`,
and reports **138 distinct with one duplicate** — a false finding, measured 2026-09-07 and
independently reproduced by the judge. Use a string rule of `(?:[^"\\]|\\.)*`.

#### What this proof CANNOT see

Stated because `rules/core-conduct.md` requires naming what was not checked, and because the
heading on the previous revision ("proof that the split lost nothing") claimed more than the
method delivers:

| Failure | Detected? |
|---|---|
| A label disappears | **yes** — set difference names it |
| A label is added or renamed | **yes** |
| Two test **bodies** swapped between labels | **no** — the label set is unchanged |
| A body edited to pass unconditionally | **no** |
| An assertion that goes **vacuous** after the reorder | **no**, and it reports green |
| One of the six files never invoked by the runner | **no** by `SOURCE-SET`; **yes** by `RUN-SET` |
| A label **substituted** for another — one deleted, another duplicated in its place | **no**, and this is where the class now sits. 139 emitted, 138 distinct: the count check passes, `RUN-SET` vs `SOURCE-SET` passes because both sides changed together, and only a comparison against the **pre-split** `panes/.label-baseline` catches it. That file is **untracked and gitignored**, so from a clean clone nobody but the author can re-run that comparison. Measured by the round-3 judge. |
| A **duplicate** label introduced by the split | **no** — set equality is blind in the opposite direction from the count it warns against: copy-and-delete yields 140 emissions of 139 distinct labels and passes green. Task 8 therefore asserts the emitted **count** is 139 as well as the set. |

The third and fifth rows are not hypothetical: **vacuity is the exact hazard this card
documents at line 45** (§Hazard). Hardening line 45 closes one instance; the class survives
the split with the label set intact and a green count. The four unscoped difference pairs
(`:749/752`, `:837/839`) and every fixture-order dependency remain order-safe **by argument,
not by this proof.** Anyone reading a green task-8 result must read it as "the label set is
identical", never as "the tests still test what they tested".

### Decision 4 — the `ok`/`bad` label divergence is NOT fixed in this pass

48 of 135 pairs spell the two labels differently, defeating matching a failure by its pass
text. It is a separate change to the same file, and bundling it would make Decision 3's
set-equality meaningless — the label set is exactly what that change rewrites. Its own card,
its own branch, after this one lands.

---

## The hazard this split creates, and the order it must be fixed in

**Hardening comes first, in its own commit, before a single line moves.** Splitting reorders
execution, and one existing assertion is safe only by accident of position.

All 14 `find` calls over `$PANE_STATE_DIR`, classified 2026-09-07, judge-verified 2026-09-08:

| Lines | Scoping | Order-safe? |
|---|---|---|
| **45** | **none**; asserts non-empty at `:46` | **NO — the one real hazard** |
| 140, 271, 285, 462, 782, 803, 857, 860 | `-newer "$TMP/<marker>"` | yes |
| 761 | `-newer "$PROMPT"` **plus** an `-exec grep -l 'model4.md'` content filter | yes — **by the content filter, not the marker** |
| 749 / 752, 837 / 839 | none; before/after **difference** pairs | yes, by construction |

**Line 45 is the single genuinely order-sensitive lookup**, and its failure mode is the
dangerous one: it asserts only that *some* `launch.sh` exists anywhere under the run tree. It
works today because it is the first dispatch in the file and nothing else has written one yet.
After a reorder, a `launch.sh` left by any earlier test satisfies it — the assertion does not
break, it goes **vacuous**, passing whether or not the dispatch under test created a launcher.
A green count would report success while the assertion measured nothing. The file's own
authors hit this hazard twice and fixed it both times with a `touch` marker plus `-newer`
(comments at `:131-137` and `:262-268`); line 45 never got the same treatment.

**Line 761 is order-safe for a different reason than the rest, and the distinction matters.**
`$PROMPT` is written once in the preamble at `:32`, so `-newer "$PROMPT"` excludes almost
nothing; what actually makes it safe is `grep -l 'model4.md'`. An implementer hardening from a
table that lumps it with the `$TMP`-marker rows would preserve the wrong invariant. The suite's
own comment at `:262-268` records that keying a search off a preamble-era file is what made an
assertion vacuous once already.

**One section inherits an adapter stub from across a bucket boundary, and it is safe.**
Section `:736` (`--model` passthrough, assigned to `dispatch.test.sh`) runs today against
whichever stub the routing sections last installed. Judge round 3 chased this down: inside
`dispatch.test.sh` the in-effect stub becomes the one at `:169`, which succeeds for every verb,
and no assertion in `:736` reads the surface ref or the verb — **so it does not break.** It is
the only such case across all six files. Recorded here so the implementer does not have to
re-derive it, and so that a future change to `:169` is known to have a second consumer.

Two further pieces of shared, cross-section-mutable state to preserve when relocating:

- `$PANE_STATE_DIR/{panes,tabs,tabtargets}` are ad-hoc counter files explicitly `rm -f`d
  immediately before use at **three** sites (`:561`, `:597`, `:652`) — all inside the **one**
  section headed `:533`, so they relocate as a unit. Evidence the authors know these are not
  zeroed by the preamble. (An earlier revision said "two sections"; it was three sites in one
  section. Note "section" is used strictly in Decision 1 — a `# ---` header block — and that
  is the sense meant here.)
- The cleanup bucket's `CS_25H` fixture deliberately leaves a stray `launch.sh` behind after
  pruning (to prove sibling files survive), and its own comment (`:872-876`) says it calls
  `cleanup_stale` directly precisely so an unrelated dispatch cannot disturb it. Cleanup is
  last today by position, not by design. Once each bucket is its own file with its own `TMP`
  this resolves — but it must be verified, not assumed.

---

## Scenarios

### Good — the split is clean

```gherkin
Given panes/dispatch-pane-agent.test.sh at the branch base runs 139 passed, 0 failed
  And the escape-aware extractor captured a before-set of 139 distinct labels
When the six bucket files and panes/test-lib.sh replace it
  And every bucket file is run
Then each of the six exits 0
  And the union of their emitted labels is set-equal to the before-set
  And the union has 139 members
  And every one of the six files is under 800 lines
```

### Bad — a label is lost

```gherkin
Given a before-set of 139 labels
When the union of the six after-sets has 138 members
Then task 8 fails and names the missing label by its exact text
  And the implementer restores that section rather than adjusting the expected count
```

### Bad — the extractor is naive

```gherkin
Given an extractor whose string rule is [^"]*
When it runs against the two --model labels containing escaped quotes
Then it reports 138 distinct with one duplicate
  And that is a defect in the extractor, not evidence of a lost test
```

### Edge — a bucket file dies partway

```gherkin
Given one bucket file exits non-zero before emitting its remaining labels
When the union is compared to the before-set
Then the union is short and looks identical to "a label was lost"
  And task 8 MUST therefore assert each file's exit status separately, before comparing sets
```

### Edge — a bucket file is never invoked

```gherkin
Given the runner enumerates bucket files by glob
When one file is misnamed and matches no glob
Then it contributes no labels and the union is short
  And task 8 MUST assert the count of files that ran is exactly 6, by name, not by glob count
```

### Edge — the marker is written for a suite that never ran

```gherkin
Given test-lib.sh is sourced
When tl_finish is never called because the caller forgot the final line
Then no summary prints and no marker is written
  And the caller exits with the status of its last assertion, which may be 0
  So task 6 MUST assert that a caller without tl_finish writes no marker
```

### Edge — vacuity survives the proof

```gherkin
Given line 45 asserts only that some launch.sh exists anywhere
When it is relocated after any other dispatching section
Then it passes whether or not its own dispatch created a launcher
  And the label set is unchanged and task 8 reports success
  So task 4 MUST harden it BEFORE task 7 moves anything
```

---

## ⚠️ Every line number in this document dies at task 7

All 30 `:NNN` citations above point into `panes/dispatch-pane-agent.test.sh` **as it stands at
the branch base `656a09e`**. Task 7 deletes that file. From that moment every citation in this
card is an anchor into something that no longer exists — it will not error, it will silently
point at nothing, which is the failure mode that is expensive rather than loud.

**Rules that follow, and they are not optional:**

- **Before task 7**, these citations are live and were audited: 29 of 30 resolve to the line
  they claim (verified 2026-09-09 by resolving each one); the exception was `:696`, corrected
  above. Re-run that audit if you doubt one — do not trust this sentence over the file.
- **After task 7**, cite by **content anchor**, never by line: the assertion's label text, or a
  comment marker like `# NEW-A (pair pin)`. Labels are unique (139 distinct, measured) and
  survive a move; line numbers do not.
- **Do not "update" these citations to their new homes.** Rewriting 30 anchors in place is how
  a document gets a confident set of numbers nobody re-derived — and it corrupts the sentences
  that record what the file looked like *at the baseline*, which is the whole point of this
  section. They are historical, and the heading above says so.
- Anything written **after** task 7 — commit messages, the PR body, the observability judge
  brief — takes content anchors from the start.

## Checklist

- [x] 1. Cut the branch, record it in this file's frontmatter, move `phase` to
  `implementation`. **Done 2026-09-09** — branch `refactor/pane-dispatch-test-suite-split`
  from `656a09e`.
- [x] 2. Re-run both suites at the branch base and re-read the output. Record the counts here.
  Do not carry §Baseline forward on trust. **Done 2026-09-09** at `8a26ab5` — 139/0 and 18/0,
  both exit 0, recorded in §Baseline with emission counts.
- [x] 3. Write `panes/label-set.py` — the escape-aware **source** extractor of Decision 3,
  taking file paths as `sys.argv` and printing one label per line to stdout. Capture
  `SOURCE-SET` before to `panes/.label-baseline` (untracked). Write the **`RUN-SET`** reader
  too: it reads a suite's stdout and strips **both** the `ok   — ` and `FAIL — ` prefixes.
  **Falsify both**: delete one label from a source copy and confirm the diff names that exact
  label; feed the run reader a stdout containing one `FAIL — ` line and confirm that label is
  still counted as having run; and run the source extractor against the naive `[^"]*` rule to
  confirm the 138-with-duplicate result it must not reproduce. Record all three outcomes.
  **Done 2026-09-09.** `panes/label-set.py` (116 lines), `panes/run-set.py` (138 lines),
  baseline `panes/.label-baseline` = **139 labels, 139 distinct**. All three falsifications
  were re-run by the main session rather than taken from the worker report:

  | Falsification | Observed |
  |---|---|
  | delete `ok "prints RESULT_FILE"` from a copy | extractor drops to 138; the diff names exactly `prints RESULT_FILE` |
  | feed the run reader a stdout with `FAIL — ` lines | those labels are still emitted as having run, detail suffix stripped |
  | naive `ok "[^"]*"` rule over the real suite | **139 matches, 138 distinct, duplicate `--model \`** — the false finding reproduced exactly |

  Two rules were decided while building it and are recorded in the files: `ok` is matched only
  where it is not glued to a preceding identifier character, and the emitted label is the
  **unescaped** value, so `SOURCE-SET` is directly diffable against `RUN-SET` (bash has already
  removed the backslashes by the time `ok()` sees `$1`). The `FAIL — ` detail suffix is
  stripped by a depth-counting scan from the end rather than a regex, because one real `bad()`
  detail contains nested parentheses. Its stated limit: a bare label that genuinely ends in
  `)` is indistinguishable from a label plus detail. Checked — no single-argument `bad()` call
  in the suite has such a label today, so the limit is not live-wrong, only a future risk.

  **⚠️ Task 3 found a hole in Decision 3 that Decision 3 does not name.** `SOURCE-SET` and
  `RUN-SET` **cannot** be set-equal at the baseline, and the reason is not a defect in either
  reader. One assertion interpolates a shell variable into its own label:

  ```
  :570  [ "$pc_panes" -le 2 ] && ok "panes max=2 bounds real panes: 6 workers opened $pc_panes pane(s), never more than 2" \
  ```

  `SOURCE-SET` necessarily reads the literal `$pc_panes`; `RUN-SET` reads the substituted `2`.
  Measured at the branch base: the diff is exactly one line, that line, and nothing else —
  139 vs 139, one substitution. Verified it is the **only** `ok` label in the file containing
  a `$` (`grep` over the captured baseline: one hit, line 99 of `.label-baseline`).
  Task 8 step (d) cannot be written as a bare set comparison until this is settled; the
  resolution is recorded at §Task 8 resolution below.
- [x] 4. **Harden line 45** with a `touch` marker + `-newer`, matching `:140`. Own commit,
  before any code moves. Re-run: still 139/0. Do **not** touch `:761` — it is safe by its
  content filter, and adding a marker there would be a change with no measured cause.
  **Done 2026-09-09.** A `touch "$TMP/dispatch-marker"` immediately before the section
  dispatch, and `-newer "$TMP/dispatch-marker"` on the `find`. Re-run: **139 passed, 0 failed**,
  exit 0, and `SOURCE-SET` is byte-identical to the task-3 baseline. `:761` untouched.

  **The marker was falsified, not assumed.** A scratch mutant moving the `touch` to *after*
  the dispatch — so the launcher is no longer newer than the marker — runs **133 passed, 6
  failed**, failing `launcher created`, `launcher mode 700`, `run dir mode 700`, `launcher runs
  runner`, `launcher carries agent type` and `prompt copied into run dir`. That is what makes
  the green run above mean something: the `-newer` clause is load-bearing, not decorative.
  The mutant was written under a scratch name, run, and deleted; the tree is clean of it.

  **Cost: +6 lines, and every line number in this card below `:41` moved.** 957 → 963. The
  re-derived mapping is at §Post-task-4 mapping.
- [x] 5. Create `panes/test-lib.sh` per the Decision 2 contract, including `tl_finish`, the
  `|| exit 1` on `MARKER_ROOT`, and the library-owned EXIT trap. Assert the fail-closed
  behaviour directly: source it from a directory outside any repository and confirm the caller
  **stops** rather than continuing with `MARKER_ROOT` unset. No behavior change to any suite yet.
  **Done 2026-09-09**, 66 lines. Measured, and re-run independently by the main session rather
  than taken from the worker's report:

  | Probe | Observed |
  |---|---|
  | real library sourced from a non-repo dir | the line after `source` never printed; caller exit **1** |
  | same probe, library mutated to `\|\| return 1` | the line after `source` **did** print; caller exit **0** |
  | `ok`/`bad`/`tl_finish` smoke inside the repo | `ok   — `, `FAIL — <label> (<detail>)`, `\n2 passed, 1 failed`; `tl_finish` returned 1 |
  | `bash -n` / `shellcheck` | both clean (`shellcheck shell=bash` directive added, no shebang — the file is sourced) |

  The mutation row is what makes the first row mean something: it proves the probe can fail.
  The smoke deliberately forced `fail=1` so `tl_finish` would not write a real test marker —
  a grader must not manufacture the receipt it is grading. Neither suite is converted yet.
- [x] 6. Convert `panes/run-pane-agent.test.sh` to source it and end with `tl_finish`. Re-run:
  still 18/0. Assert that a caller omitting `tl_finish` writes no marker. This proves the
  skeleton under a second caller before the big file depends on it.
  **Done 2026-09-09.** 24 insertions, 30 deletions. Stdout captured before and after the edit:
  the diff is **empty**, `18 passed, 0 failed`, exit 0. `bash -n` clean; `shellcheck` output
  byte-identical to the pre-edit run once the house `# shellcheck source=/dev/null` directive
  was added for the dynamically-resolved source path.

  **The no-marker assertion was run, not reasoned.** `hooks/lib/write-test-marker.py` writes
  under `hooks/state/test-markers/<encoded-subject>`, and is reached only from inside
  `tl_finish`. A scratch suite that sources the library, calls `ok` once and then just ends
  leaves that directory listing byte-identical, and prints no summary line.

  **21 of 32 emitting call sites converted to `ok`/`bad`; 11 deliberately left as inline
  `printf`.** The 11 all interpolate a dynamic detail into the FAIL branch, and `bad` renders
  an *empty* detail differently from the original — it omits the parentheses where the
  original always prints `()`. That divergence is invisible today because those branches do
  not execute on a green run, which is exactly why converting them would be an unmeasured
  change to an untested path. Leaving them inline is sound: `pass`/`fail` are plain shell
  variables in the same shell, so an inline `printf` still counts correctly.
- [x] 7. Run the Decision 1 derivation script **in its §Post-task-4 mapping form** — the
  pre-task-4 numbers in Decision 1 no longer resolve. All three asserts must pass. Then split
  `dispatch-pane-agent.test.sh` into the six files by that mapping, each
  sourcing the library with its own domain fixtures. **Move the `read_policy` wrap case
  (`:703-709` post-task-4, the block headed `# NEW-A (pair pin)`) into `policy.test.sh`, not
  `routing.test.sh`** — that move is what keeps `RP_DIR` and
  `call_read_policy` from crossing a file boundary. Delete the original. Then grep each new
  file for a variable it uses but never assigns; `set -u` makes any such crossing fatal, and
  `RP_DIR` was found only because someone looked for it.
- [x] 8. Run all six plus `run-pane-agent`. Assert, in this order:
  (a) each of the six named files ran — **by name, not by glob count**;
  (b) each exited 0;
  (c) `SOURCE-SET` after is **set-equal** to the task-3 baseline;
  (d) `RUN-SET` after is set-equal to `SOURCE-SET` after;
  (e) the emitted label **count** is exactly 139.
  Order matters: (c) alone cannot distinguish a lost label from a crashed file, and (e) is the
  only check that catches a duplicate introduced by copy-and-delete — 140 emissions of 139
  distinct labels satisfies every set comparison above it.
- [x] 9. `wc -l` every new file. Assert each under 800; record which exceed the 400 preferred
  (`routing.test.sh` is expected to, at ~453) as a named residual with its measured number.
- [x] 10. Six files where there was one means six markers. Verify `write-test-marker.py` is
  invoked once per file, that `MARKER_SELF` resolves to the sourcing script and not to
  `test-lib.sh`, and that `hooks/test-marker-guard.sh` passes for a commit staging all six.
  `test-lib.sh` itself has no sibling test — confirm the guard does not demand one.
- [x] 11. Grep the repo for `panes/dispatch-pane-agent.test.sh` by name — CI wiring, docs,
  ADRs, other cards — and update every hit. A stale reference to a deleted file fails closed
  and reads as the tests being switched off.
- [x] 12. File `docs/features/oversized-source-files.md`. **Done 2026-09-07 during planning**,
  so the measurement is not lost if this card stalls. Judge round 1 passed it clean, 0
  violations. Re-read at task 13 and correct anything the split proved wrong.
- [x] 13. Observability judge (Opus) on the diff; act on findings. **Round 1 done 2026-09-09,
  `risk=low confidence=medium`, four findings acted on, none waived.** The judge independently
  re-derived the 139-label equality, the six file sizes, and the pairing claim, and then found
  what the card had missed.

  | Finding | Action |
  |---|---|
  | the runner catches a crashing child but not a quiet one — an early `exit 0` or a truncated file exits 0 and the marker is written for a partial run | **fixed** — completion sentinel + count reconciliation; falsified against all three shapes |
  | the ADR and card both claim the gate "has always been about the subject's bytes"; it compares the test blob too (`MSG_STALE_TEST`) | **fixed** — both sentences corrected, and the real narrowing named |
  | `TMP="$(mktemp -d)"` in `test-lib.sh` has no `\|\| exit 1` while its sibling `MARKER_ROOT` was hardened for that exact reason | **fixed** |
  | a concern file added to `panes/` but never added to `SUITES` would silently never run | **fixed** — glob-superset drift check, falsified with a stray file |

  **The quiet-exit finding was reproduced before being fixed, on the real runner:**

  | Mutated child | before the fix | after |
  |---|---|---|
  | early `exit 0` partway | `rc=0`, `130 passed, 0 failed` ← green, 9 assertions lost | `rc=1`, 1 failed |
  | truncated before `tl_finish` | `rc=0`, `130 passed, 0 failed` ← green | `rc=1`, 1 failed |
  | crash under `set -u` | `rc=1`, 1 failed (already caught) | `rc=1`, 2 failed |
  | unmutated baseline | `139 passed, 0 failed` | `139 passed, 0 failed` |

  The two new checks were each falsified on their own: a stray `dispatch-pane-agent.bogus.test.sh`
  is reported by name, and a child emitting a label it does not count is caught as
  `child reported 11/0, runner counted 12/0`.

  **⚠️ The round-1 tally above said "four findings" and that understated the verdict — round 2
  caught it.** Round 1 recorded **ten** concerns. Four were acted on in `4db65eb`; the full
  accounting, so none is silently dropped:

  | # | Round-1 concern | Disposition |
  |---|---|---|
  | 1 | a child ending normally before `tl_finish` writes the marker for a partial run | fixed |
  | 2 | the runner discards the child summary line, the one available sentinel | fixed (it is now required) |
  | 3 | no executable artifact pins 139 | **initially declined, then fixed in round 2** — see below |
  | 4 | the marker test blob now binds only the runner | documented in ADR 0044; **the follow-up work is unscheduled — no card exists for it yet**, and saying "deferred to the pairing-rule card" implied one did |
  | 5 | `mktemp -d` has no `\|\| exit 1` | fixed |
  | 6 | the hazard audit enumerated `find` calls only, not a whole-tree sweep | **open, declined** — the audit's population was `find` over `$PANE_STATE_DIR`; a wider sweep is a different measurement and belongs to whoever makes it, not to a refactor |
  | 7 | the three label tools ship with no sibling test | **open, declined for this branch** — they are proof scaffolding, not shipped behaviour; named here so it is a decision rather than an oversight |
  | 8 | a seventh concern file added without editing `SUITES` has no detector | fixed |
  | 9 | a failing child's stderr is flattened and then deleted by the EXIT trap | fixed — stderr is now surfaced before `$TMP` is removed |
  | 10 | the judge did not run the suites, by instruction | **inherent** — a grader must not write the marker it is grading; the runs are the author's, and round 2 corroborated them by hashing the marker |

- [x] 13b. **Observability judge round 2 (Opus) on `4db65eb` — `risk=low confidence=high`,
  11 concerns.** Round 2 verified the round-1 fixes by rebuilding them on a synthetic replica,
  and independently confirmed the green run by hashing the test marker against the commit's own
  post-image — evidence round 1 could not produce. Eight items were actionable and all eight are
  fixed:

  | Round-2 concern | Action |
  |---|---|
  | a child reaching `tl_finish` with its assertion block skipped reconciles at 0/0 and the marker is written on 92 of 139 labels | **fixed** — `EXPECTED_LABELS=139` total pin plus a per-suite zero-label check |
  | `label-diff.py` already ships `--count/--expect-count`, so the round-1 decline understated how cheap the pin was | **accepted** — the decline is withdrawn, and the reasoning is corrected rather than left standing |
  | the sentinel is stated as "if and only if"; the only-if half is false | **partly fixed in `f69a327`, completed in round 3** — the runner comment and one of the ADR's two copies were reworded; `0044:124` kept the phrase for a round, so the ADR carried a claim and its own refutation. This row previously said "both", which was wrong. |
  | "four findings, all acted on" understates round 1's ten | **fixed** — the table above |
  | the dispatcher is called 545 lines; it is 618 | **fixed** — 618 measured at HEAD and at `origin/main`; 545 was its size on 2026-08-24 and was copied forward without re-measurement |
  | `test-lib.sh` called 63 lines at task 5; it is 66 | **fixed** |
  | drift check treats a concern name spanning a space as listed, since it substring-matches the joined `SUITES` | **fixed** — element-wise comparison; falsified with `dispatch-pane-agent.policy routing.test.sh`, now reported by name |
  | a NUL byte on child stdout puts `Binary file … matches` into the summary variable | **fixed** — `grep -a`; proven load-bearing by removing the flag and reproducing the unreadable message |

  **Falsification of the round-2 fixes, all re-run by the main session:**

  | Mutated child | Result |
  |---|---|
  | runs **no** assertions, reaches `tl_finish` | `rc=1`, caught twice — zero-label check *and* total |
  | runs **some** assertions, reaches `tl_finish` | `rc=1`, caught by the total alone — nothing else can see this |
  | concern filename spanning a space | `rc=1`, reported by name |
  | NUL byte on stdout, `grep -a` removed | reconcile message reads `Binary file … matches` |
  | NUL byte on stdout, `grep -a` present | clean, `139 passed, 0 failed` |
  | unmutated baseline | `139 passed, 0 failed` |

- [x] 13c. **Observability judge round 3 (Opus) on `f69a327` — `risk=low confidence=high`,
  13 concerns, no dimension `fail`.** This is the first round in which **139 stopped being the
  author's number**: the judge re-derived it from source itself (28/31/47/8/14/11, all distinct,
  no assertion inside a loop) and hashed the on-disk test marker against the commit's own
  post-image. Because a green run now *requires* the total to be 139, that receipt asserts the
  count rather than merely reporting it. It also re-ran every row of the round-2 falsification
  table on a synthetic replica and attacked the new drift loop four ways — a glob character in a
  filename, a glob that would match a real suite, an empty list, and round 2's spanning-space
  name — and found no hole in it.

  | Round-3 concern | Action |
  |---|---|
  | **a defect this branch introduced:** the total counted the runner's *own* failure labels as assertions | **fixed** — a separate `child_total` accumulates only the six suites' labels |
  | the ADR still said "if and only if" at `:124`, 58 lines below the paragraph explaining why it is wrong | **fixed** — the ADR carried a claim and its own refutation for one round |
  | the card recorded that fix as "reworded in **both**" when one of two copies was reworded | **fixed** |
  | "Six items were actionable" sat above a table of eight rows | **fixed** — the third round running where a count understated its own evidence, and the second time inside the paragraph correcting the previous one |
  | one disposition pointed at a "pairing-rule card" that does not exist | **fixed** — the follow-up is named as unscheduled, with no card |
  | the pin counts *how many*, never *which* — a substituted label gives 139 emitted, 138 distinct, and passes | **documented, not fixed** — added to the blind-spot table with the reason it cannot be closed here |
  | `panes/.label-baseline` is gitignored, so the one check that catches a substitution cannot be re-run from a clean clone | **documented** in the same row |

  **The introduced defect was reproduced before being fixed**, and the mirror direction matters
  more than the noisy one:

  | Case | before | after |
  |---|---|---|
  | a runner diagnostic fires, nothing has drifted | false second failure, `emitted 140` | drift reported alone; the total stays silent |
  | a real shortfall | caught | caught, `emitted 130` |
  | **a real shortfall *and* a runner diagnostic** | **the two cancelled and the pin went silent** — in exactly the case it exists for | both reported independently |
  | unmutated baseline | `139 passed, 0 failed` | `139 passed, 0 failed` |

  Everything stayed red and no marker was written in any of those cases, so this was a
  wrong-message defect rather than a safety one — but the third row is a check going quiet
  under load, which is the failure this card keeps being about.

  **Left open, stated:** round 2's own concerns 10 and 11 — the `MSG_STALE_TEST` narrowing
  (recorded in ADR 0044 as declined for this branch; **the follow-up is unscheduled and has no
  card**) and the observation that 139 is ultimately
  the author's count. The second is now weaker than it was: the number is pinned in the runner,
  so a green run asserts it rather than merely reporting it.
- [ ] 14. Open the PR. Update this card to `review` when it merges.

## Post-task-4 mapping

Task 4 inserted 6 lines inside the first section (`# --- dispatch happy path`, header `:38`),
so **`:38` is unmoved and every later section start is +6**. Derived mechanically by zipping
the ordered `# ---` header list of the pre-task-4 blob against the post-task-4 file — not by
hand-arithmetic. 31 headers on both sides; the set of observed deltas is exactly `{0, 6}`.

| File | Section headers (post-task-4) | Body |
|---|---|---|
| `dispatch` | 38, 66, 78, 157, 173, 742 | 107 |
| `policy` | 89, 96, 181, 208, 234, 265, 285, 294, 301 **+ `:703-709`** | 162 |
| `routing` | 322, 339, 370, 388, 404, 418, 441, 481, 539, 680 **− `:703-709`** | 412 |
| `cleanup` | 102, 872 | 97 |
| `scratch` | 774, 800, 826, 855 | 98 |
| `subcommands` | 111, 133 | 46 |

The two non-header section starts move with their neighbours: `768 → 774`, `866 → 872`, and
the footer boundary `954 → 960`. Only `dispatch` changed size (101 → 107, the +6); the
`policy` 154 / `routing` 420 pre-move figures and the ±8 wrap delta are unchanged, so the
`162` / `412` finals are the same numbers Decision 1 published.

Derivation, run against the post-task-4 file with all three asserts passing:

```sh
python3 - panes/dispatch-pane-agent.test.sh <<'EOF'
import sys
lines = open(sys.argv[1]).read().split("\n")
starts = sorted([i for i,l in enumerate(lines,1) if l.startswith("# ---")] + [774, 872])
END = 960
span = {s: (starts[j+1] if j+1 < len(starts) else END) - s for j,s in enumerate(starts)}
BUCKET = {
 "dispatch":    [38,66,78,157,173,742],
 "policy":      [89,96,181,208,234,265,285,294,301],
 "routing":     [322,339,370,388,404,418,441,481,539,680],
 "cleanup":     [102,872],
 "scratch":     [774,800,826,855],
 "subcommands": [111,133],
}
allsec = sorted(x for v in BUCKET.values() for x in v)
assert allsec == starts, set(starts) ^ set(allsec)   # exactly-once partition
tot = 0
for k, secs in BUCKET.items():
    n = sum(span[s] for s in secs); tot += n
    print(f"{k:12s} {n:4d} body")
print("body", tot, "+ 37 preamble + 4 footer =", tot+41)
assert tot + 41 == 963
WRAP = 709 - 703 + 1 + 1                  # 7 content + 1 separator blank
print("after the wrap move -> policy", 154 + WRAP, " routing", 420 - WRAP)
assert 154 + WRAP == 162 and 420 - WRAP == 412
EOF
```

**The pre-task-4 numbers in Decision 1 are kept as written.** They were correct against the
blob they were measured on and rewriting them would falsify the record of what was measured
when. This section supersedes them for task 7 and nothing else.

## Task 8 resolution — the one label that cannot be set-compared

**Decided by the user 2026-09-09: teach the comparison about placeholders.** Not an exclusion,
and not an edit to the assertion — the test file stays the unbiased baseline, and all 139
labels stay inside the check.

`panes/label-diff.py` converts a source label into an anchored pattern in which each `$name` /
`${name}` reference becomes a wildcard and every other character is escaped literally. Literal
labels are resolved first by plain set membership; only the placeholder-bearing remainder is
then matched against the remaining unclaimed run labels, and a pattern matching more than one
run label (or a run label matched by more than one pattern) is reported as an **ambiguity**,
never silently accepted.

**The wildcard is `\S+?`, not `.*`, and that is the load-bearing choice.** With `.*` a pattern
whose placeholder sits at the end has nothing to anchor against, so `result: $x` full-matches
`result: 2 and something else entirely different` — the check degrades into "the prefix
matches, accept anything after it". `\S` cannot cross the space, so it rejects that.
Falsified both ways: the shipped rule reports the pair unmatched (exit 1); a throwaway copy
patched to `.*` reports `OK: 1 distinct labels matched` (exit 0). Its stated limit, accepted:
a substituted value containing whitespace will never match and is reported as unmatched.

The count check is a **separate** mode (`--count … --expect-count N`) on raw line count with no
dedup, because set equality is structurally blind to a duplicate. Demonstrated on 140 emissions
of 139 distinct labels: the set comparison passes green and the count check fails — both halves
shown, which is exactly the blind-spot row Decision 3 warns about.

## Task 7-11 results, measured

**Task 7 — the split was performed by a slicing script, not by transcription.** It builds each
file as a list of source line numbers, asserts the six lists are an **exact partition of body
lines 38-959** by line number with nothing claimed twice, and only then writes. Body sizes came
out at exactly the derivation's figures: dispatch 107, policy 162, routing 412, cleanup 97,
scratch 98, subcommands 46 — 922 total.

The `set -u` crossing check was run statically as well as by execution. Seven names were
flagged and **all seven are false positives**, confirmed by reading each in context: five occur
only inside comments, `$d` in two files is the `sed '/^cmd=/,$d'` command rather than a shell
variable, `$PANE_AGENT_ROLE` is the deliberately-unexpanded stub text (and carries a `:-unset`
default), and `$d` in `routing` is `local` to `mk_run_ref`. No variable crosses a file boundary.

**Task 8 — all five checks, in the card's order:**

| Check | Result |
|---|---|
| (a) each of the six named files ran, by name | yes — the runner names them explicitly; per-suite lines on stderr |
| (b) each exited 0 | yes, all six |
| (c) `SOURCE-SET` after set-equal to the task-3 baseline | `OK: 139 distinct labels matched (1 via placeholder)` |
| (d) `RUN-SET` after set-equal to `SOURCE-SET` after | `OK: 139 distinct labels matched (1 via placeholder)` |
| (e) emitted label count is exactly 139 | `OK: emits exactly 139 labels` |

Per-suite emission: dispatch 28, policy 31, routing 47, cleanup 8, scratch 14, subcommands 11.

**Task 9 — sizes.** All under the 800 hard maximum. One residual over the 400 preferred:

| Lines | File |
|---|---|
| 445 | `panes/dispatch-pane-agent.routing.test.sh` ← the stated residual |
| 195 | `panes/dispatch-pane-agent.policy.test.sh` |
| 140 | `panes/dispatch-pane-agent.dispatch.test.sh` |
| 131 | `panes/dispatch-pane-agent.scratch.test.sh` |
| 130 | `panes/dispatch-pane-agent.cleanup.test.sh` |
| 79 | `panes/dispatch-pane-agent.subcommands.test.sh` |
| 66 | `panes/test-lib.sh` |
| 142 | `panes/dispatch-pane-agent.test.sh` (runner) |

`routing` landed at **445**, not the 453 Decision 1 projected. Decision 1 already flagged its
`+41 with skeleton` column as an upper bound that assumed each file re-carries the whole
preamble; ~11 lines went to the library instead, so the real figure is 8 lower. The direction
was the safe one.

## ⚠️ Task 10 found that the split disarms a Tier-1 guard, and how it was closed

**This is the most important finding on the branch and it was not anticipated by the spec.**
Checklist task 10 assumed "six files where there was one means six markers". Measured, the
truth is the opposite: **six files where there was one means *zero* markers, and the production
dispatcher stops being gated at all.**

`hooks/lib/write-test-marker.py` derives a test's subject by the `X.test.sh → X.sh` rule
(`PAIR_SUFFIXES`). Each concern file therefore derives `dispatch-pane-agent.<concern>.sh`,
which does not exist, and each run printed `marker skipped: … has no tracked subject`.
Symmetrically, `hooks/lib/decide-commit-gate.py` `_form_pairs` skips a staged subject whose
sibling test is neither tracked nor on disk (`continue  # no sibling test at all -- never
gated, per Scope`).

Measured against the real `_form_pairs`, both conditions on the same function:

| Condition | `_form_pairs` for staging `panes/dispatch-pane-agent.sh` |
|---|---|
| sibling test present (before the split) | `[('panes/dispatch-pane-agent.sh', 'panes/dispatch-pane-agent.test.sh')]` |
| sibling test absent (after the split) | `[]` — **never gated** |

So deleting the file outright would have silently switched off the verification-marker gate for
a 618-line production script, and nothing would have reported it — a guard that has stopped
guarding is indistinguishable from one that is working.

**Closed by the user decision of 2026-09-09: keep a runner at the original name.**
`panes/dispatch-pane-agent.test.sh` is now a **142-line runner** that invokes the six by
explicit name, re-emits their assertion lines verbatim as its own stdout, counts them itself
rather than trusting a child summary line, folds any child's non-zero exit into `fail`, and —
after the judge showed the exit status alone was not enough — **requires each child's summary
line as a completion sentinel and reconciles its counts**, so `tl_finish` cannot write a marker
for a partial run whether the child crashed or stopped quietly. Verified: the marker for
`panes/dispatch-pane-agent.sh` is written again, and its `test.blob` is the runner's blob.

The alternative — teaching `write-test-marker.py` and `decide-commit-gate.py` an
`X.<concern>.test.sh → X.sh` rule — was considered and declined for this branch: it edits two
Tier-1 scripts every commit in the repo depends on, which deserves its own card and review.

**Residual, stated — and corrected after the judge read it.** The six concern files remain
orphan suites that write no marker of their own, exactly as the three pre-existing orphan
suites do. The gate is armed through the runner, not through them.

The first version of this paragraph said the gate's guarantee "is about the *subject's* bytes,
which is what it has always been". **That is wrong.** `hooks/lib/decide-commit-gate.py`
compares the **test** blob as well, and blocks with `MSG_STALE_TEST` when it has moved. Before
the split that check covered all 963 lines of assertions; it now covers only the 142-line
runner. Editing a concern file no longer invalidates the receipt, where before it would have —
six of seven test files have left that check's scope. Recorded in ADR 0044 as the cost of
declining the pairing-rule change.

**Task 11 — references.** One live reference outside documentation:
`panes/dispatch-pane-agent.sh:225` cited the deleted file by name for the "three panes lost to
a cmux restart" assertions; repointed to `dispatch-pane-agent.routing.test.sh`, where those
assertions now live (verified by grep — `:376`). **No CI wiring exists** (no `.github/`), so
there was nothing to rewire. The remaining ten hits are historical records — merged cards, old
plans under `docs/superpowers/plans/`, and judge verdict stores — and are **deliberately left
unedited**: they record what was true when written, and rewriting them would falsify the
measurements they exist to preserve. `docs/features/oversized-source-files.md` gets a
resolution note appended below its dated table for the same reason.


## Not in scope

- The `ok`/`bad` label divergence (Decision 4) — its own card.
- The other eleven oversized files — `docs/features/oversized-source-files.md`.
- Cutting `routing.test.sh` below 400 — no measurement supports a boundary yet (Decision 1).

## Revision history

**2026-09-08, after compliance judge round 1 (FAIL, 6 violations, all accepted):**

1. `writing-specs/no-ambiguity` — the section→bucket mapping was prose only. Now published as
   header line numbers plus a runnable derivation whose assert fails on a non-partition.
2. `writing-specs/api-contracts` — `test-lib.sh` had no contract. Now a symbol table, a caller
   ordering contract, and the reason the footer must be `tl_finish` rather than top-level code.
3. `core-conduct/verification-before-writedown` — Decision 3 was headed "proof that the split
   lost nothing". It is now scoped to label membership, with a table of what it cannot see and
   the note that vacuity is the card's own line-45 hazard.
4. `core-conduct/no-unsourced-metric` — three figures did not reproduce: "30 `# ---` headers"
   was **31**; the find table filed `:761` under `-newer "$TMP/<marker>"` when it is
   `-newer "$PROMPT"` plus a `grep -l` content filter; and the `set-policy panes --max 1` call
   was cited at `:228` when it is at **`:261`**. All three corrected and re-verified by command.
5. `core-conduct/file-size` — the 615-line residual was under-argued. The `CSID` chain covers
   88 of 574 lines, not all of them, so routing is now cut from policy at `:316` (154 / 420),
   costing one 1-line helper relocation. Five files became six.
6. `writing-specs/edge-cases` — no Gherkin. Six scenarios added, including the two the judge
   named (a bucket dying partway, and a file never invoked) which drove the task-8 rewrite.

**2026-09-08, after compliance judge round 2 (FAIL, 3 violations; four of six round-1 findings
confirmed fixed). All three accepted.**

7. `writing-specs/api-contracts` — three measured holes. **`RP_DIR`** (`:206` to `:701-702`)
   crossed the cut, so the naive split cost two relocations, not one, and `routing.test.sh`
   would have died under `set -u` with `RP_DIR: unbound variable`. Resolved by **moving the
   `read_policy` wrap case (`:697-703`, headed `# NEW-A (pair pin)`) into policy**, where its
   five siblings already live —
   after which neither `RP_DIR` nor `call_read_policy` crosses, and the library needs neither.
   The library's `return 1` on `MARKER_ROOT` was **fail-open** (judge measured: caller
   continues, variable unset, exit 0); it is now `|| exit 1`, which from a sourced file exits
   the caller and preserves the fail-closed semantics of `:12`. The `rm -rf "$TMP"` EXIT trap
   now has a stated owner: the library, because it creates `TMP`.
8. `core-conduct/no-unsourced-metric` — "fifteen distinct keys" was wrong; **seventeen** are
   assigned. The parenthetical omitted `F1SID` (`:157`) and `UMAX_SID` (`:299`), and
   `UMAX_SID` matters because its section sits inside the claimed `CSID` chain — so the true
   dependency ends at `:298`, not `:315`. The cut at `:316` is unaffected.
9. `writing-specs/no-ambiguity` — the document used "the label set" to mean **source
   extraction** in the checklist and **runtime emission** in every scenario, and never
   specified the runtime reader. Split into `SOURCE-SET` and `RUN-SET` with a table of what
   each proves and is blind to; `RUN-SET` must strip `FAIL — ` as well as `ok   — `.
   Also added the blind spot the judge named unprompted: **a duplicate label introduced by
   copy-and-delete** passes every set comparison, so task 8 now asserts the emitted count.

**2026-09-08, compliance judge round 3: PASS, zero violations, none waived.** All three
round-2 findings verified resolved by independent measurement — the zero-crossing result by
exhaustive enumeration of every assignment, reference, definition and call site across all 957
lines (11 apparent crossings, all 11 opened and all false positives: comments, a single-quoted
`printf` format, a single-quoted `grep -oE` pattern, and `sed`'s `$d`). The judge was asked
directly whether it was correcting prose rather than defects and answered **yes, proceed**. Its
three residuals are folded in above anyway — two were false sentences (the session-key phrasing
and "two sections" for what is three sites in one), and the third is the `:736` stub
inheritance, run to ground and recorded as safe rather than filed as a maybe.

**Not verified by any round:** neither judge ran either suite, because a green run writes a
test marker and a judge must not cause that side effect. `139/0` and `18/0` are corroborated
statically only — task 2 exists to settle them by execution. And no code exists yet, so the
zero-crossing result is static enumeration, not a built `routing.test.sh`.
