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
- [ ] 2. Re-run both suites at the branch base and re-read the output. Record the counts here.
  Do not carry §Baseline forward on trust.
- [ ] 3. Write `panes/label-set.py` — the escape-aware **source** extractor of Decision 3,
  taking file paths as `sys.argv` and printing one label per line to stdout. Capture
  `SOURCE-SET` before to `panes/.label-baseline` (untracked). Write the **`RUN-SET`** reader
  too: it reads a suite's stdout and strips **both** the `ok   — ` and `FAIL — ` prefixes.
  **Falsify both**: delete one label from a source copy and confirm the diff names that exact
  label; feed the run reader a stdout containing one `FAIL — ` line and confirm that label is
  still counted as having run; and run the source extractor against the naive `[^"]*` rule to
  confirm the 138-with-duplicate result it must not reproduce. Record all three outcomes.
- [ ] 4. **Harden line 45** with a `touch` marker + `-newer`, matching `:140`. Own commit,
  before any code moves. Re-run: still 139/0. Do **not** touch `:761` — it is safe by its
  content filter, and adding a marker there would be a change with no measured cause.
- [ ] 5. Create `panes/test-lib.sh` per the Decision 2 contract, including `tl_finish`, the
  `|| exit 1` on `MARKER_ROOT`, and the library-owned EXIT trap. Assert the fail-closed
  behaviour directly: source it from a directory outside any repository and confirm the caller
  **stops** rather than continuing with `MARKER_ROOT` unset. No behavior change to any suite yet.
- [ ] 6. Convert `panes/run-pane-agent.test.sh` to source it and end with `tl_finish`. Re-run:
  still 18/0. Assert that a caller omitting `tl_finish` writes no marker. This proves the
  skeleton under a second caller before the big file depends on it.
- [ ] 7. Run the Decision 1 derivation script; all three asserts must pass. Then split
  `dispatch-pane-agent.test.sh` into the six files by the published header mapping, each
  sourcing the library with its own domain fixtures. **Move the `read_policy` wrap case
  (`:697-703`, the block headed `# NEW-A (pair pin)`) into `policy.test.sh`, not
  `routing.test.sh`** — that move is what keeps `RP_DIR` and
  `call_read_policy` from crossing a file boundary. Delete the original. Then grep each new
  file for a variable it uses but never assigns; `set -u` makes any such crossing fatal, and
  `RP_DIR` was found only because someone looked for it.
- [ ] 8. Run all six plus `run-pane-agent`. Assert, in this order:
  (a) each of the six named files ran — **by name, not by glob count**;
  (b) each exited 0;
  (c) `SOURCE-SET` after is **set-equal** to the task-3 baseline;
  (d) `RUN-SET` after is set-equal to `SOURCE-SET` after;
  (e) the emitted label **count** is exactly 139.
  Order matters: (c) alone cannot distinguish a lost label from a crashed file, and (e) is the
  only check that catches a duplicate introduced by copy-and-delete — 140 emissions of 139
  distinct labels satisfies every set comparison above it.
- [ ] 9. `wc -l` every new file. Assert each under 800; record which exceed the 400 preferred
  (`routing.test.sh` is expected to, at ~453) as a named residual with its measured number.
- [ ] 10. Six files where there was one means six markers. Verify `write-test-marker.py` is
  invoked once per file, that `MARKER_SELF` resolves to the sourcing script and not to
  `test-lib.sh`, and that `hooks/test-marker-guard.sh` passes for a commit staging all six.
  `test-lib.sh` itself has no sibling test — confirm the guard does not demand one.
- [ ] 11. Grep the repo for `panes/dispatch-pane-agent.test.sh` by name — CI wiring, docs,
  ADRs, other cards — and update every hit. A stale reference to a deleted file fails closed
  and reads as the tests being switched off.
- [x] 12. File `docs/features/oversized-source-files.md`. **Done 2026-09-07 during planning**,
  so the measurement is not lost if this card stalls. Judge round 1 passed it clean, 0
  violations. Re-read at task 13 and correct anything the split proved wrong.
- [ ] 13. Observability judge (Opus) on the diff; act on findings.
- [ ] 14. Open the PR. Update this card to `review` when it merges.

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
