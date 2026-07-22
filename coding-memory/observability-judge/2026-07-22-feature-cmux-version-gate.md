# Observability Judge Verdict — cmux-version-gate (implementation, gating)

- **Repo:** `.claude` · **Branch:** `feature/cmux-version-gate`
- **HEAD:** `9797191b8c6cedbbb4b2fcda5f1320562c324533` (pushed; `origin` matches)
- **Base:** `main` (merge-base `34914644801fa0454a7bc2da1b2beb99a390e583` = PR #25 merge)
- **Stage:** implementation (gates the PR)
- **Predecessor:** `2026-07-22-feature-pane-layout-v2-round2.md`. This branch builds that verdict's
  top-ranked follow-up, so the standing bias is toward approving my own suggestion. The probes
  below exist to counteract that, not to confirm it.
- **Risk:** low · **Confidence:** high

## Test evidence — run by me, not taken on report

| Suite | Result |
|---|---|
| `cmux-exec.test.sh` | **70** / 0 |
| `cmux-layout.test.sh` | 34 / 0 |
| `adapters.test.sh` | 24 / 0 |
| `dispatch-pane-agent.test.sh` | 39 / 0 |
| `run-pane-agent.test.sh` | 10 / 0 |
| `terminal-detect.test.sh` | 9 / 0 |
| **total** | **186 passed, 0 failed** (170 → 186, +16 as claimed) |

`shellcheck -x` on the four named scripts exits 0, silent. Working tree clean; the round-2
`skip-worktree` recommendation was applied — `git ls-files -v` now reports `S` for both
`chrome/chrome-native-host` and `settings.json`.

### Falsification re-run independently

| Mutation | My result | Claimed |
|---|---|---|
| pin `0.64.20` → `0.65.0` | 66 / **4 RED** | 66/4 ✅ |
| remove the `check_cmux_version` call | 66 / **4 RED** | 66/4 ✅ |
| drop the marker write entirely | 69 / **1 RED** | (see note) |
| drop only the `> "$marker"` redirect | 68 / **2 RED** | 68/2 ✅ |
| drop the second warning line | 69 / **1 RED** | 69/1 ✅ |

The branch log's "marker write dropped → 68/2" reproduces **exactly** once I match the mutation it
actually used (dropping the redirect, which sends the marker `printf` to *stdout* and corrupts the
surface-ref contract, killing a second assertion). My broader mutation kills one. The record is
accurate, not inflated. All restores verified with `git diff --quiet`.

### The vacuous-setup guard is real — verified, not assumed

I reverted `ver_setup` to the discarded first-draft form (`T_EMPTY` + `split_ok`) and re-ran.
`version-gate baseline reaches the layout path` is the **first** assertion to fail
(`out=surface:42`, `degraded (plan target vanished…)`), followed by five more. The guard bites, and
it bites at the right place. This is the single strongest thing on the branch.

### Nine parser probes I wrote myself (not in the suite)

| `cmux version` output | warns? | marker? |
|---|---|---|
| `cmux 0.64.20 (100) [14e3400b9]` (the pin) | no | no |
| `cmux 0.65.0 (101)` | **yes** | **yes** |
| `cmux 1.0.0 (200)` | **yes** | **yes** |
| `cmux 0.65.` | **yes** | **yes** |
| `cmux 0.65.0-rc1 (101)` | **no** | **no** |
| `cmux 0.64.20-beta (100)` | **no** | **no** |
| `cmux version 0.65.0` | **no** | **no** |
| `0.65.0` (bare) | **no** | **no** |
| *(empty / rc≠0)* | no | no |

Also verified: the check fires on the **legacy floor** path too (tree read forced to fail →
`out=surface:42`, warned, marker written, exactly **1** `version` call); the `PANE_DRYRUN` path is
silent as documented; and after a mismatch is *resolved* the marker **is not cleared**.

## Dimension table

| Dimension | Score | Basis |
|---|---|---|
| intent | **pass** | Builds precisely the named follow-up. Two commits, both declared up front. |
| execution | **pass** | 186/0 re-run by me; shellcheck 0; four mutations RED; guard falsified; live pin matches the installed binary. |
| trajectory | **pass** | The author caught their own vacuous first draft, named it in the log, and converted it into a standing guard. Mutations checked for non-empty diffs; restore via `cp`, not `git checkout --`. Reasoning, not luck. |
| regression | **pass** | One function + one call site before the loop. Other five suites byte-identical (34/24/39/10/9). Legacy floor output unchanged. `/panes/state/` is gitignored, so the marker can't be committed. Cost: one extra subprocess per dispatch. |
| context_budget | **concern** | `CODING_MEMORY.md` 369 → **379** lines against its own stated ≤200. Round 2 flagged this; the delta moved the wrong way. |
| traceability | **pass** | The `check_cmux_version` header is unusually good — what's calibrated, why it can't self-check, why warn-not-degrade, why fail-open, pointer to ADR 0008. ADR updated and keeps the honest "trigger, not defect" sentence. Nits in concern 8. |
| success_masking | **concern** | Materially improved but **not discharged** — one *achievable* miss remains. See concern 1. |
| intent_drift | **pass** | No drive-by edits (file list diffed), no new deps, docs commit separately labelled with a `Doc-Exempt` trailer. |
| checkpoint | **pass** | Two independently revertible commits; `aedf3d1` is purely additive source; `origin` matches HEAD; tree clean. |
| audit_trail | **pass** | Commit messages carry the rejected alternatives and attribute the calibration decision to the user. One stale spot, concern 6. |

## Rulings on the four judgment calls

### 1. Does this move `success_masking`? — It moves it, but not off `concern`, and the reason is specific

**It is not detection theatre.** Theatre would be a check that cannot fail, cannot be observed, or
was never wired in. All three are falsified: removing the call turns four assertions red, the live
binary genuinely matches the pin, a real bump genuinely warns, and the warning genuinely reaches a
human — `dispatch-pane-agent.sh:69` calls the adapter *without* redirecting stderr, so the two
lines land in the tool output at the moment of dispatch. It also fires on the legacy floor, which I
did not expect and which widens its coverage.

**But my probes found a hole that is not a platform limitation.** `0.65.0-rc1` and `0.64.20-beta`
are *readable, unambiguously different* versions, and the `*[!0-9.]*` filter classifies them as
**unreadable** and stays completely silent. A pre-release or nightly is a perfectly plausible way to
land a pane-walk change, and the gate is blind to exactly that. The fail-open rationale — "a changed
`version` shape must not cry wolf" — justifies suppressing *stderr*; it does not justify suppressing
the *marker*, which is a single idempotent file write with zero noise cost. That asymmetry is
unaddressed in the design.

So the residual splits in two: the part that genuinely cannot be fixed (no geometry in the tree →
no self-check of the defect), and the part that can be fixed in about two lines (widen the accepted
shape so a suffixed version reads as a *mismatch*, and/or write a marker on unreadable output while
staying silent on stderr). **If only the first existed, I would score this `pass`.** The second
exists, so it is `concern` — and I would be failing at my job if I waved through my own suggestion
while my own probe shows `0.65.0-rc1` sailing past it.

**Related: the "closes two open items" claim is overstated, and that overstatement is mine.** My
round-2 wording ("one small detector closes two open items") was inherited into the commit message
and branch log. It closes item 3 fully. It closes only the *version-caused slice* of item 4: a
degrade from any other cause — missing `jq`, a tree-shape change on the same release, workspace
resolution failure — still leaves exactly one `degraded (…)` stderr line and **no** marker. I
verified the marker is written on version mismatch only. Correct the record rather than inherit it.

### 2. Warn, never degrade — **right call, and I'd have pushed back on the opposite**

Degrading on an unknown version would convert a routine auto-update into a silent feature-off, which
is the precise failure being guarded against; it would act on a *proxy* (release string) as though it
were evidence of breakage; and the blast radius of being wrong is asymmetric — a mis-placed pane is
cosmetic, while a self-inflicted degrade is a real loss of the feature every dispatch. The "fail
closed on validation failure" invariant governs security-material validation of targets; a
compatibility hint is not a trust boundary. The weak half of the pairing is the marker (below), not
the warn decision.

### 3. The `PANE_DRYRUN` gap — **acceptable**

I confirmed the dryrun block exits at line 210, before the check, and that its own comment documents
why reaching the real binary from `adapters.test.sh` is unacceptable. Dryrun is a preview, not a
dispatch, and `cmux-layout-probe.sh` already prints the version. Noting only that a cheap variant
existed and wasn't taken: the check could sit *inside* the dryrun branch guarded on
`[ -n "${PANE_CMUX_BIN:-}" ]`, which is the same guard that block already uses. Low value, low risk,
not a blocker.

### 4. The literal pin in the adapter — **right call**

The ~10 other `0.64.20` mentions are not duplicates of the same fact. A spec or plan pinning a
toolchain records *what was probed on a date*; the adapter constant records *what the running code
is calibrated against*. Coupling them would make a historical record load-bearing at runtime and
would add a source-able dependency to a script that must run standalone, for zero runtime benefit.
The genuine gap is the reverse direction — see concern 8.

### Bonus ruling: the calibration policy — **I agree with it**

"Every round on a merged PR is clean" would encode that the judge never prompted rework, which is
factually false: `e12dc06`'s findings produced ADR 0008 and the memory update *before* round 2
passed. The chosen rule reads `outcome` as *what this verdict caused*, which is the only reading
that makes the data useful for tuning. Verified the edit is surgical: 30 lines before and after,
exactly two `outcome` fields changed, every other field byte-identical, 17 nulls remaining. Leaving
the architecting sub-policy undecided is the right conservative call. One refinement: write down how
`rework` should be *read*, so a future consumer doesn't misinterpret it as "this verdict was wrong"
— round 1's dimensions were mostly `pass`; the `rework` records its effect, not its quality.

## Concerns

1. **Suffixed versions fail open silently — the one achievable miss.** `0.65.0-rc1` and
   `0.64.20-beta` produce no warning and no marker (probed). A readable mismatch is being treated as
   unreadable. Two-line remedy.
2. **A `version` output reshape silences the detector permanently.** `cmux version 0.65.0` → field 2
   is `version` → silent forever. Accepted by design, but note the correlation: the output shape is
   most likely to change *at* a substantial release, i.e. the detector's likeliest silent-failure
   mode co-occurs with the risk it guards. Writing a marker (no stderr) on unreadable output costs
   nothing and preserves the trail.
3. **The marker is write-only.** Nothing in `panes/`, `hooks/`, or the statusline reads
   `$PANE_STATE_DIR/cmux-version-mismatch` (grepped). Its value is post-hoc forensics, which is real
   — but it is not notification, and the branch log's "the marker is the part that survives the
   scrollback" oversells it slightly. Its *only* cleanup is `dispatch-pane-agent.sh:36`'s 7-day
   `STALE_DAYS` sweep, which is an undocumented cross-file dependency: it is what saves the marker
   from lingering forever after a mismatch is resolved (I verified the adapter never clears it), and
   nothing records that anyone depends on it.
4. **"Closes two open items" is overstated** — see ruling 1. Non-version degrades are untouched.
5. **No acknowledge path.** Exact equality means every dispatch warns until a human edits a source
   constant and commits. If cmux auto-updates, this becomes background noise within days —
   habituation is the classic way a working detector stops working. An ack file written by
   `cmux-layout-probe.sh` on re-verification would close the loop at the right end.
6. **`CODING_MEMORY.md` is 379 lines against its own 200-line budget** (+10 here), and its Active
   Session block still reads "**PR #25 OPEN** … NEXT ACTION … **First post-merge follow-up: the cmux
   version gate**" — both now false, and the same commit edited that file lower down.
7. **`PANE_DRYRUN` unchecked** (accepted, ruling 3); the guarded in-branch variant wasn't taken.
8. **Cross-reference gaps.** `cmux-layout.sh`, home of the `layout_rightmost_surface` heuristic this
   gate exists to protect, has no back-pointer to `check_cmux_version` — a reader starting at the
   heuristic will not learn a detector exists. `coding-memory/branches/cmux-version-gate.md` is not
   linked from the memory index.

## What was changed

Your pane layout has one guess baked into it: it picks the *rightmost* pane by assuming the
highest-numbered pane is the one furthest right. That happens to be true on the exact cmux you have.
Nothing in the code could tell you if a future cmux stopped making it true — all 170 tests drive a
*fake* cmux, so they'd stay green while your side panel quietly landed in the wrong place.

This adds a smoke alarm. The adapter now writes down the one cmux version everything was checked
against (`0.64.20`), and before every dispatch it asks the real cmux what version it is. Same? Total
silence. Different? Two loud lines on screen naming both versions and telling you to re-run the
probe, plus a small file left behind in the state directory as a receipt. It never turns the layout
*off* — an upgrade silently disabling your feature is the exact thing this is guarding against.

The second commit is bookkeeping: PR #25's two judge verdicts got their real outcomes filled in, and
the rule for how to fill those in from now on got written down.

## Does it do what you wanted?

Mostly yes, and I checked it hard because it was my idea. I tried to break it five different ways —
removing the check, moving the pin, deleting the receipt, deleting the second warning line, and
rewinding the tests to their broken first draft — and every single time the tests went red at
exactly the right assertion. That is the opposite of theatre.

**But it does not move `success_masking` off `concern`, for one concrete reason.** I fed it nine
different version strings myself. `cmux 0.65.0` warns. `cmux 1.0.0` warns. But
`cmux 0.65.0-rc1` and `cmux 0.64.20-beta` produce **nothing at all** — no warning, no receipt. The
code only accepts digits and dots, so anything with a `-rc1` or `-beta` on the end gets filed under
"I can't read this" and stays quiet. A beta build is a very normal way to end up on a version that
changed behaviour, and the alarm is deaf to it. That's not a limit of what's possible here — it's
about two lines of code.

## What could go wrong / what I'm unsure about

- **The alarm is deaf to pre-release versions.** Verified by probe, not theory. Widen the accepted
  shape so a suffixed version reads as a *mismatch* rather than as noise.
- **If cmux ever changes how it prints its version, the alarm goes silent forever** and you'd never
  know it stopped working. That's a deliberate trade — the alternative was warning on every single
  dispatch — but the trade only needed to apply to the *on-screen* warning. Writing the receipt file
  anyway costs nothing and keeps a trail.
- **Nobody reads the receipt.** No code anywhere opens that file; it only helps if you happen to
  look in the state folder. It also never gets deleted when the problem is fixed — the only thing
  that eventually cleans it up is an unrelated 7-day sweep in the dispatcher that nobody has written
  down as load-bearing.
- **The claim that this closes two old problems is one-and-a-bit, not two.** It fully solves "you
  can't tell when cmux changed." It only partly solves "a degrade leaves no trace" — a degrade from
  *anything other than* a version change still leaves one line of stderr and no receipt. That
  overstatement started in my own round-2 wording; correct it in the log rather than inherit it.
- **Alarm fatigue.** Any version difference warns on every dispatch until someone edits and commits
  a constant. If cmux updates itself often, this becomes wallpaper fast.
- **The memory index is now 379 lines against its own 200 limit**, and its top block still says PR
  #25 is open and that this gate is the next thing to build — both stale as of this branch.

## What I'd double-check before merging

1. **Nothing blocks the PR.** No dimension fails. Open it.
2. **Two-line fix worth doing now, not later:** make a suffixed version (`0.65.0-rc1`) warn instead
   of being swallowed. This is the difference between `success_masking` staying `concern` and going
   `pass`, and it is the only thing standing between them.
3. **Correct "closes two open items" to "closes one and part of another"** in the branch log and, if
   you touch it, the ADR. Don't let my overstatement calcify.
4. **Add one comment line in `cmux-layout.sh`** next to `layout_rightmost_surface` pointing at
   `check_cmux_version`, so the guard is discoverable from the thing it guards.
5. **Refresh `CODING_MEMORY.md`'s Active Session block** — PR #25 is merged and this gate is built;
   both lines currently say otherwise. And it's still 179 lines over budget.
6. **Open the PR with this verdict file uncommitted**, then commit the audit trail immediately
   after. Committing it first moves HEAD and re-triggers `judge-guard` staleness — that is what
   produced round 2 on the parent branch.
