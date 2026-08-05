---
phase: implementation
model_tier: low
branch: fix/replay-harness-base-pin
---

# The replay harness never says what it compared

Planned on `main` @ `c461e4c`, session 10. Model-switch checkpoint 1 answered: stay on Opus 5 for
planning. **Revision 9** — rounds 1-6 all failed compliance, each on something genuinely new, and
round 1 additionally drew `risk=high` from the architecting read. Every round was right, and one of
them overturned this spec's original premise. Revisions 3-6 each *introduced* the next round's
finding, so revision 7 was a consolidation rather than another point fix, and it **passed round 7**.
Revision 8 is one fix on top of that pass: the 5th architecting read found that part 3 never said
whether an unreferenced helper counts, and both readings satisfied all 11 scenarios. Taken by user
decision on 2026-08-05, knowing it voids the round-7 verdict and restarts compliance at round 1.
Revision 9 answers that round-1 fail. What changed is recorded at the end, newest first.

Queued from `docs/features/falsifier-base-pin.md:140-152`, which found this while fixing its sibling.

## Spec

### Root cause

`hooks/git-guard.replay.sh` is a **differential** harness. Its job, per its own header: run `main`'s
`git-guard.sh` and the branch's over one 63-command × 6-state matrix in identical fixture states, and
report every case where main blocks and the branch allows. That set being empty is what "never weaker
than main" means.

It takes two parameters, `WT` (line 6) and `UNDER_TEST` (line 7), and hard-codes the baseline at lines
13-15 (`git show main:…`, three times) plus **a fourth time in its own output header at line 134**.
There is no way to set the base: `grep -cE 'BASE_REV|getopts|\$\{3' hooks/git-guard.replay.sh` → `0`.

The defect is not the *choice* of `main` — for the stated contract, `main` is the correct default.
It is that **the harness has five distinct ways to print a pass that could not have failed, and its
output cannot distinguish any of them from a real result.** All five are measured below.

### What was measured

Every row run on this host against `main` @ `c461e4c`, `$?` captured before anything else. The probe
was a scratchpad copy of the harness with a base parameter added; the repo's own file was not touched.

| base | what it is | identical | stricter | relaxed | exit |
|---|---|---|---|---|---|
| `main` (default) | **the same code as the candidate** | 378 | 0 | 0 | 0 |
| `bc7da76` | only `shell_segments.py` differs | 378 | 0 | 0 | 0 |
| `b17a666` | all three differ, matrix can see it | 358 | **20** | 0 | 0 |
| `e3b09ba` | old self-contained guard, both libs absent | 234 | 82 | **62** | 0 |
| `286fd5a` | **all three absent** → three empty files | 118 | 260 | **0** | 0 |
| `main`, `WT` given as `.` | relative worktree path | 378 | 0 | 0 | 0 |

Read the first row against the second: **identical output, opposite meaning.** Row 1 is vacuous — 378
runs of one program against itself. Row 2 is a genuine differential run that legitimately found
nothing, because the matrix contains no redirect shapes. Nothing in the output tells them apart.

The five false-pass routes:

1. **Vacuous baseline.** Base and candidate are the same code (row 1). True on `main` after any
   merge, and on any branch that does not touch those three files.
2. **Degenerate baseline.** `git show` failures at lines 13-15 are unchecked and there is no `set -e`,
   so a missing file becomes a **0-byte** base script. `bash <empty file>` exits 0, so the base
   "allows" everything, so `relaxed` — the number the whole harness exists to report — is **0 by
   construction**. Row 5 is a clean `0 relaxed` pass manufactured from three empty files. **The
   vacuity check in part 3 below cannot catch this, because empty ≠ candidate.**
3. **Relative worktree path.** `run()` does `cd "$REPO"` before invoking the hook, and for
   `UNDER_TEST=worktree` the candidate is `$WT/hooks/git-guard.sh`. With `WT=.` that path does not
   resolve after the `cd`, every candidate run exits **127**, and the comparison at lines 125-131
   counts `a=2,b=127` as neither relaxed nor stricter — it falls to the `else` branch and is tallied
   **`same`**. Row 6 is 378 "identical" pairs in which the candidate never ran at all.
4. **Unreachable rev**, once a base parameter exists — same unchecked-`git show` path as route 2.
5. **The output names no base.** Line 134 prints the literal string `main` regardless, so a figure
   copied into a document carries no record of what produced it.

Routes 1 and 3 were both live today. Route 3 is the one that caught the author of this spec: the
first reproduction was run as `bash hooks/git-guard.replay.sh .` and measured route 3 while appearing
to confirm route 1.

### What is NOT wrong — a correction to revision 1

Revision 1 claimed the harness's `378` figure was cited as false evidence in four committed documents
and proposed retracting it. **That claim was wrong, and writing it into an immutable ADR would have
made a false retraction permanent.** Re-measured:

- `docs/features/git-guard-empty-index.md:314-318` never reports "378 identical". It reports 378
  **pairs** — the matrix *size* — and a table of three candidates at **215 / 326 / 346** identical
  with **162 / 52 / 32** pairs allowed where `main` blocks. A program compared with itself cannot
  produce one relaxation, let alone 162. That run was genuinely differential. Revision 1 read the
  matrix size as a vacuous result.
- The `shell-segments-redirects.md` and ADR 0015 figure was recorded at `64ba2fa`, **2026-08-04
  15:45:33**; PR #38 merged at `cc035d2`, **16:53:55** — 68 minutes later. At recording time `main`
  did not contain the fix, so that comparison was real. Re-running that exact pair today (`bc7da76`
  vs HEAD, row 2) reproduces `378 identical, 0, 0` — the same figure, from a valid run that found
  nothing for the reason those documents already state.

**The true finding is stronger than the retraction it replaces:** those figures were valid, and
establishing that took blob-hash and commit-timestamp archaeology — *because the harness never said
what it compared*. The remedy is not to retract the numbers. It is to make every future number carry
its baseline, and to annotate the existing citations with the base they were measured against.

### The fix

**1. Add the missing base parameter.** A third positional, `BASE_REV="${3:-main}"`, replacing the
hard-code at lines 13-15. The default stays `main`; parts 2-4 are what make a default safe to have.

**2. Validate every extraction.** Six `git show` calls — three for the base (lines 13-15) and three
for a rev candidate (lines 20-22) — but they are **not all required**, and the split is load-bearing:

- **`hooks/git-guard.sh` is mandatory on both sides.** It must extract successfully and be
  non-empty. Failure: name the **resolved base SHA** and the path, print no matrix, exit non-zero.
  (Extraction happens after `rev-parse` has already succeeded, so a SHA always exists here — the
  refusal contract's rev-string exemption does *not* reach this case.)
- **The two `hooks/lib/*.py` helpers are required only if that side's extracted `git-guard.sh`
  actually references `lib/`.** If it does, both must extract and be non-empty, same failure
  contract. If it does not, their absence is *expected* — record it in the output as a
  self-contained guard and continue.

Requiring all six would reject legitimate baselines. Measured: `e3b09ba` predates the helper split
— `git show e3b09ba:hooks/lib/classify-git-command.py` fails because the path does not exist at that
commit, and that revision's `git-guard.sh` contains **0** occurrences of `lib/`. It is a valid,
self-contained guard, and it is one of this spec's own reference rows (`234/82/62`). An all-six rule
would make the spec's own measurement unrunnable.

**Part 3 does not merely parallel this rule — it reuses it.** The set part 3 compares is exactly the
set part 2 validated here: one definition of "this side's files", used by both parts. Stating it
twice is what let revision 6 make helpers conditional in part 2 while part 3 still assumed three.
Closes routes 2 and 4.

The two sides fail in opposite directions, and both are covered deliberately: an empty *base* exits 0
and "allows" everything, so `relaxed` is 0 by construction — a silent false pass. An empty *candidate*
"allows" everything too, so every case where the base blocks becomes a **relaxation** — a loud false
alarm. The silent one is why this spec exists; the loud one is one line further and is not worth
leaving open.

**3. Refuse a vacuous run.** Before the fixture repo is built, compare base and candidate. **Compare
the file *sets* first, then the bytes** — part 2 makes each side's helper files conditional, so "the
three files" is not a safe assumption and must not be written as one.

**A side's file set is part 2's required set, and nothing else:** `hooks/git-guard.sh` always, plus
the two `hooks/lib/*.py` helpers **only if that side's `git-guard.sh` references `lib/`**. A helper
that exists on disk but is not referenced is **not a member** of that side's set — it cannot execute,
so it cannot change an outcome. Membership is decided by **the bytes that will actually execute** —
the same single rule that governs byte comparison, stated once in its own bullet below and
deliberately not restated here.

The two sides are **vacuously identical** iff (i) the two sets are equal, **and** (ii) every path in
them is byte-identical. Only then: print the refusal, print no matrix, exit non-zero. Closes route 1.

- **A non-member is never passed to `cmp`.** This is the load-bearing sentence, not a detail.
  Measured on this host: `cmp -s` on two non-existent paths exits **2**, not 0 — so a rule phrased as
  "if all three match" silently fails to fire whenever a side is self-contained, because two of its
  three comparisons return an error that is not a match. Concretely, `e3b09ba` compared against
  itself is vacuous and must be refused; under the "all three" phrasing it produced
  `378 identical / 0 relaxed`, exit 0 — route 1, reopened by the very revision that made helpers
  optional. Under the set rule that error cannot arise **from a non-member**: `cmp` runs only after
  the two sets are found equal, so a path outside both sets is never an operand.
  ⚠️ **This is not the stronger claim that `cmp` always receives two files that exist**, and revision
  8 wrongly implied it was. Part 2 proves every member extracted non-empty for the base and for a
  *rev* candidate, but it does not run against the default `worktree` candidate (non-goals, deferral
  2) — so in default mode a member of the candidate's set can be absent from disk. `cmp` then
  reports "not identical", the run is correctly judged non-vacuous, and what follows is governed by
  limit 2: that candidate exits 2 on every command, so `relaxed` is 0 and the pass is silent.
  Recorded, not closed — and the reason deferral 2 is the next one to take.
- **Different *sets* are a real difference; different *files on disk* are not.** This distinction is
  the entire reason membership is defined above. A base whose guard uses the helpers, against a
  candidate whose guard is self-contained, has genuinely different sets — that is Scenario I, and it
  proceeds to the matrix. But a base carrying **unreferenced** `lib/*.py` against a candidate without
  them is the *same program twice*: both sets are `{git-guard.sh}`, and if those bytes match the run
  is vacuous and must be refused. Reading membership off the disk instead of off the guard reopens
  route 1 in the precise shape a future run will hit — testing a revert of the helper split — and
  prints a clean `identical / 0 relaxed` under a valid SHA. The same holds when unreferenced helpers
  are present on *both* sides but differ: bytes neither guard loads cannot make a run differential.
  Part 2 has separately rejected the case where an absence is a *broken extraction* rather than a
  genuine self-contained guard, so by the time part 3 runs, a set difference is signal.
- **Read the bytes that will actually execute — for membership and for comparison alike.** One rule,
  two uses, stated in exactly one place: revision 8 exists because a rule stated twice drifted apart,
  and revision 9 declines to repeat that mistake in the same section. For `UNDER_TEST=worktree` the
  harness runs the on-disk file (`NEW="$WT/hooks/git-guard.sh"`), so the candidate side is read
  **from disk, not `git show HEAD:`** — both when deciding whether its guard references `lib/` and
  when comparing bytes. The two readings diverge the moment the worktree has uncommitted edits, and
  the on-disk one is the truth. For a rev candidate, both sides are `git show`. ⚠️ **Two rules now
  depend on this one**, and the scenario that would test it is **deferral 1** (the dirty worktree) —
  already the strongest of the five deferred items, and more so now.
- **"Nothing differs", not "something matches".** A branch touching only `shell_segments.py` is a
  legitimate run — PR #38 was exactly that, and it is verifiable: between `bc7da76` and `c461e4c`,
  `git-guard.sh` and `classify-git-command.py` are the same blobs (`2b74507c`, `2f8af693`) and only
  `shell_segments.py` moved. A check keyed on "any file matches" would refuse row 2, a real run.
- **Compare content, not rev strings.** `main` and the SHA it resolves to are different strings and
  the same code; a worktree with uncommitted edits is the same rev string and different code.

**4. Resolve the worktree path to an absolute path** before use, and fail with a named error if it
cannot be resolved to a directory containing `hooks/git-guard.sh`. Closes route 3.

**5. State the baseline in every run's output** — passing runs included. Replace the hard-coded
`main` at line 134 with the resolved base, and repeat it on the summary line, so a figure copied into
a document carries its provenance. Closes route 5, and is the part that makes the harness's history
auditable without archaeology.

**"Resolved base" means the 40-character commit SHA that `git rev-parse "$BASE_REV^{commit}"`
produces — not the rev string as typed.** This is the whole point of the part: `base=main` printed
into a document is exactly route 5 still open, because `main` names a different commit every week and
a future reader is back to archaeology. Print the SHA; the rev string may accompany it
(`base=c461e4c… (main)`) but never replaces it.

**Do not copy the sibling's format here.** `hooks/shell-segments-falsifier.sh` prints the literal
`$BASE` string. It gets away with it because its base is a pinned SHA by construction; replay's
default is a moving branch, so the same format would defeat this part.

**6. ADR 0016 + provenance notes.** The ADR records the rule, which has now bitten twice:

> A differential harness must prove its two sides differ before reporting agreement, and must state
> its resolved baseline — as a fixed commit id — in its output. Agreement between a program and
> itself, or between two empty files, is not evidence; and a number that does not carry its baseline
> cannot be audited later without archaeology.

**The ADR must state the limit it does not close, in the same breath.** This change proves each side
*loaded* only for the causes it addresses: a failed extraction (part 2) and an unresolvable worktree
path (part 4). It does **not** make the harness robust to an arbitrary broken candidate, because the
`else → same` tally at lines 125-131 still counts any exit code outside `{0,2}` as agreement — see
non-goals. An ADR that claimed "proves each side actually loaded" would be over-claiming, and this
repo's ADRs are permanent.

Five citation sites exist across four files. Each gets a one-line provenance note naming the base its
figure was measured against — **annotation, not retraction**; the figures stand:

| file | site | base that figure was measured against |
|---|---|---|
| `docs/features/git-guard-empty-index.md` | `:311` (and the table at `:314-318`) | per-row candidates `27c5ac5` / `4be542b` / the fix, vs `main` as it then stood |
| `docs/features/shell-segments-redirects.md` | `:118` | `main` @ `bc7da76`, 68 min pre-merge |
| `docs/features/shell-segments-redirects.md` | `:140` | same |
| `docs/features/falsifier-base-pin.md` | `:145` | already correct — states the tautology; note that it refers to *today's* post-merge run, not the recorded figures |
| `docs/decisions/0015-…` | `:110` | **NOT edited** — ADR 0016 carries this one |

**ADR 0015 is not edited**: this repo amends by writing a new ADR (stated in `0009:105`, `0011:4-6`,
`0013:5`), so ADR 0016 restates 0015's figure with its provenance rather than touching the file.

### Pinned toolchain

Measured on this host, not recalled. The harness must keep running under exactly these:

```yaml
bash:    "3.2.57(1)-release"   # macOS system bash — no associative arrays, no ${x^^}, no mapfile
git:     "2.50.1"              # Apple Git-155
python3: "3.9.6"               # the classifier's interpreter
jq:      "1.7.1-apple"         # /usr/bin/jq, hard-coded at line 35
cmp:     "BSD"                 # NO --version; --quiet IS accepted here, see below
shasum:  "6.02"
```

Byte comparison uses **`cmp -s`** — POSIX, and portable to a GNU host. Path resolution uses
**`cd … && pwd -P`**.

**These are portability choices, not capability limits, and the distinction was previously stated
wrongly.** Re-measured on this host: `cmp --quiet` exits 0, `diff -q --no-dereference` exits 0, and
`readlink -f /tmp` prints `/private/tmp` and exits 0. All three *work* here. They are nonetheless
forbidden in the harness because they are not guaranteed on every BSD/macOS host the hook set is
expected to run on, and the POSIX spellings cost nothing. An earlier revision labelled them
"GNU-only" and annotated `cmp` as "NO --quiet"; both claims were recalled rather than measured, in a
block whose own heading promises the opposite.

### Deliberate non-goals

- **No `git-guard.replay.test.sh`.** Neither harness in `hooks/` has a test sibling; both are verified
  by recorded execution, as PR #39 was. Inventing a test-for-a-test convention mid-fix is unearned
  scope. (Round 1 judge: this reasoning holds.)
- **The 63-command matrix is unchanged** — still zero redirect shapes, a real and separate gap
  recorded in ADR 0015.
- **Five architecting-read recommendations were reviewed and deferred, not forgotten.** Recorded
  here because a deferral that appears nowhere is indistinguishable from an oversight, which is the
  same failure mode this spec exists to fix. Raised across the round-3 and round-4 reads; user
  decision 2026-08-05 was to fix only the baseline-rejection contradiction and defer these:
  1. **A dirty-worktree scenario** — part 3's most-argued claim (on-disk bytes, not `git show HEAD:`)
     is still untested. The strongest of the five; take it first.
  2. **Applying the extraction check to the default `worktree` mode too**, so the candidate's own
     helpers are validated. Now a one-line omission rather than an unavoidable one, since part 2's
     rule reads file contents and an on-disk file reads as easily as one from git history. **Revision
     8 makes this cheaper again and the deferral correspondingly weaker:** part 3 now reads the
     on-disk guard to decide the candidate's set membership, so those files are already being opened.
     Still deferred — widening scope mid-flight is what shipped a second defect on the last two
     branches in this class — but it is the next-strongest of the five after the dirty-worktree
     scenario.
  3. **Making the `lib/` reference check ignore comments** — at HEAD, 2 of its 3 matches are comment
     lines, so the check is weaker than it looks.
  4. **Printing the candidate's identity** alongside the base. The six file hashes are already
     computed, so the cost is a printf.
  5. **An ADR 0016 sentence stating that a printed base attests *provenance, not validity*.** The
     concern behind it is real and is worth restating here: after this fix, a false pass will print
     a correct 40-character SHA beside it and therefore look audited. Provenance is improving faster
     than validity.
- **Two further limits in the comparison logic are NOT closed — queued as their own item. They are
  independent, and fixing either one does not close the other.**

  1. **The `else → same` tally (lines 125-131)** counts any exit code outside `{0,2}` as agreement.
     That is the mechanism behind route 3, where the candidate exits 127 and is tallied `same`.
     Part 4 closes only route 3's *cause* (the unresolved relative path), not the tally.
  2. **The definition of `relaxed` (line 125)** is `base = 2 && candidate = 0`, so a candidate that
     **blocks everything** can never register a single relaxation, and the harness's headline number
     is 0 by construction. Measured: a candidate missing `hooks/lib/*.py` exits **2 on every
     command** — including `ls -la` — because `git-guard.sh:74-77` fails closed when it cannot run
     the classifier it resolved at `:44`. (Not `:56`, which is the separate python3-not-on-PATH
     guard at `:53-57`; both exit 2, which is why the two are easy to confuse.) Result: `0 relaxed`, exit 0, a false pass dressed as legitimate hardening.

  Note the exit code is **inside** `{0,2}`, so limit 2 is *not* a case of limit 1 — an earlier
  revision of this bullet said it was, and that was wrong. Both are pre-existing comparison logic
  this spec does not otherwise modify, and the last two branches in this class shipped a second
  defect by widening mid-flight. **User decision, session 10:** record honestly, queue separately.
  ADR 0016 states both limits rather than leaving them implicit.

- **The harness's exit code carries no signal today** and this change only partly fixes that: it
  exits 0 unconditionally, so the `e3b09ba` row's 62 relaxations exit 0 exactly as a clean run does.
  After parts 2-4, refusals and named errors exit non-zero, but a run that *reports relaxations*
  still exits 0. Queue beside the two limits above.
- **`hooks/git-guard.sh` is not touched.** Row 4's 62 relaxed rows against `e3b09ba` are genuine
  historical policy differences accumulated across the repo's life, not defects surfaced by this
  change. Investigating them is its own task.

### Scenarios

```gherkin
Scenario A: base and candidate are the same code — refused
  Given the default base on main, where all three files match the worktree
  When the harness runs
  Then the output names the resolved base as a 40-character SHA, not the string "main"
   And it says the run proves nothing
   And no pair-count line is printed
   And the exit code is non-zero
  # The SHA assertion is what makes part 5 testable on a DEFAULT-base run — the one case
  # every other scenario passes an explicit base and therefore cannot check.

Scenario B: same code under a different rev string — still refused
  Given f5c5689, a different rev whose three blobs are identical to HEAD's (verified)
  When the harness runs with that base
  Then it refuses exactly as in Scenario A
  # Falsifies the rev-string shortcut: comparing rev names instead of bytes passes A and fails here.

Scenario C: a difference the matrix can see — reported normally
  Given b17a666, where all three files differ
  When the harness runs with that base
  Then the pair-count line is printed, naming b17a666 as the base
   And the counts are 358 identical, 20 stricter, 0 relaxed

Scenario D: a difference the matrix cannot see — still reported, not refused
  Given bc7da76, where only shell_segments.py differs
  When the harness runs with that base
  Then the pair-count line is printed, naming bc7da76 as the base
   And the counts are 378 identical, 0 stricter, 0 relaxed
   And the run's HEADER names the same resolved base as the summary line, not the literal "main"
  # Identical to Scenario A's counts. Only the named base distinguishes a real run from a vacuous one.
  # The header assertion is what makes part 5's "both the header and the summary line" testable on a
  # SUCCESSFUL run: line 134's hard-coded "main" is a separate site from the summary, and without
  # this line an implementation that fixes only the summary passes every scenario in this file.

Scenario E: a base whose files do not exist — named error, not a pass
  Given 286fd5a, where all three files are absent
  When the harness runs with that base
  Then the output names the resolved base as a 40-character SHA, not the string "286fd5a"
   And the output names the path that could not be read
   And no pair-count line is printed
   And the exit code is non-zero
  # Today this prints "0 relaxed" and exits 0 — a clean pass from three empty files.

Scenario F: an unresolvable rev — named error
  When the harness runs with base 0000000
  Then the output names the rev string as typed, "0000000", labelled as unresolved
   And no 40-character SHA is printed, because rev-parse produced none
   And the exit code is non-zero

Scenario G: a relative worktree path — resolved, never silently counted
  Given the base b17a666, so the run is NOT vacuous and part 3 cannot refuse it first
  When the harness runs with the worktree given as "." and that base
  Then the candidate hook is actually executed
   And the counts match Scenario C exactly: 358 identical, 20 stricter, 0 relaxed
  # Today this reports 378 identical: every candidate run exits 127 and is tallied "same".
  # The base MUST be non-vacuous here, or the part-3 refusal fires before route 3 is reached
  # and the scenario silently tests nothing.

Scenario I: a self-contained baseline is accepted, not rejected
  Given e3b09ba, which predates hooks/lib/ and whose git-guard.sh contains 0 occurrences of "lib/"
  When the harness runs with that base and the worktree candidate
  Then no extraction error is raised for the two absent lib/*.py paths
   And the pair-count line is printed, naming the resolved SHA of e3b09ba
   And the counts are 234 identical, 82 stricter, 62 relaxed
  # Pins part 2's conditional-helper rule in the ACCEPTING direction. An implementation that
  # reverts to "all six required" fails here.

Scenario J: helpers absent while the guard still needs them — named error
  Given a base whose git-guard.sh DOES reference lib/ but whose lib/*.py are absent
  When the harness runs with that base
  Then the output names the resolved base SHA and the path that could not be read
   And no pair-count line is printed
   And the exit code is non-zero
  # Pins the same rule in the REJECTING direction. No such commit exists in history: measured at
  # 5bc39b9 (632 commits), all 66 whose guard references lib/ carry both helpers. So this base must
  # be synthesized. An implementation that drops the helper check entirely passes I but fails here.

Scenario K: a self-contained base against itself is still vacuous
  Given e3b09ba as both base and candidate
  When the harness runs
  Then the refusal is printed and no pair-count line appears
   And the exit code is non-zero
  # Pins part 3's set-then-bytes rule. On a probe copy carrying revision 6's "all three match"
  # phrasing, this ran to completion — 378 identical, 0 relaxed, exit 0 — instead of refusing.
  # 378 is the matrix size (63 commands x 6 states), i.e. everything, as a self-comparison must be.
  # Cause, verified directly on this host: cmp -s on two ABSENT paths exits 2, so "all three match"
  # is never true for a self-contained side and the refusal never fires.
  # An implementation phrased as "all three" fails here.

Scenario L: an unreferenced helper is not part of the comparison
  Given a base whose git-guard.sh is self-contained (0 occurrences of "lib/")
    but which still carries hooks/lib/*.py in its tree
   And a candidate whose git-guard.sh is byte-identical to that base's
    and which carries no lib/*.py at all
  When the harness runs with that base
  Then the refusal is printed and no pair-count line appears
   And the exit code is non-zero
  # Both sides' sets are {git-guard.sh} and those bytes match: the same program twice.
  # An implementation reading membership off the DISK sees {guard, lib/a, lib/b} vs {guard},
  # calls the sets different, and reports a clean "identical / 0 relaxed" under a valid SHA.
  # That is route 1, in the one shape a future run will hit: testing a revert of the helper split.
  # Both readings of revision 7 passed A-K, which is why this scenario exists.
  # No such base exists in this repo's history. Measured at 5bc39b9 (632 commits): of the 66
  # carrying the guard alongside at least one helper, all 66 reference lib/. Zero mixed-shape
  # commits, so this base must be synthesized, as Scenario J's is.
  # The count moves with every commit; it is pinned to a SHA for the same reason part 5 exists.

Scenario H: the refusal is discriminating
  Then A, B, E, F, J, K and L refuse or error; C, D, G and I report
   And no implementation hard-wired to refuse, or to pass, satisfies both halves
```

### Error and refusal contract

Every refusal and every named error: exit **non-zero**, print **no** `DISTINCT COMMANDS` header and
**no** pair-count line, and state in one plain sentence what was wrong, **the resolved base SHA** it
concerned (not the rev string — the letter of this contract must not be satisfiable by printing
`base main`, which Scenario A forbids), and the corrected invocation. Every *successful* run: print the resolved base in both the header and the
summary line.

**The one exception, and it is the only one:** when the rev *cannot be resolved at all* (Scenario F),
there is no SHA to name, so the error names **the rev string as typed** and says it could not be
resolved. This is not a licence to fall back to the rev string elsewhere — every other named error
happens *after* a successful `rev-parse`, so a SHA exists and the clause above binds unchanged.
Concretely: an unresolvable base is the only case in which output may contain a bare rev string, and
even then it must be visibly labelled as unresolved rather than presented as a base.

## Tasks

- [x] 1. Red — record the six measured rows above against the unfixed script, exit codes captured
      first, as the reproduction. Do not delete the probe.
      - ✅ 2026-08-05: all six rows reproduced exactly, including exit codes. Table, mechanism
        evidence, and the probe's regeneration recipe are under `## Verification`.
- [x] 2. Add the `BASE_REV` third positional; replace the three hard-coded `main:` refs.
      - ✅ 2026-08-05: repo harness now differs from the Red probe in comments only; re-measured
        rows 1/3/4 at `378/0/0`, `358/20/0`, `234/82/62` — unchanged, so the parameter is inert
        against the default and live against a real base.
      - The file's header comment claimed the harness "runs main's git-guard"; that became false
        once the base was parameterized, so it was corrected here rather than left stale.
      - `rev-parse` resolution deliberately **not** added here — it belongs with task 3, where the
        error contract that must name a *resolved base SHA* lives.
- [x] 3. Validate extractions: `git-guard.sh` mandatory both sides (success + non-empty); the two
      `lib/*.py` helpers required only when that side's `git-guard.sh` references `lib/`. Named
      error on failure; self-contained guards recorded, not rejected. Cover `e3b09ba`.
      - ✅ 2026-08-05, all under `/bin/bash` 3.2.57 explicitly (not `env bash`): **E** names the
        resolved SHA + path, no header, no pair-count, exit 1. **F** names `'0000000'` as typed,
        prints **zero** 40-char SHAs, exit 1. **I** accepts `e3b09ba`, prints the self-contained
        NOTE, `234/82/62`, exit 0. Regressions: default `378/0/0`, `b17a666` `358/20/0` with no
        spurious NOTE — the rule fires in the accepting direction without over-firing.
      - ⚠️ `resolve_rev` runs inside `$( )`, so a `fail` inside it exits only the **subshell** — the
        script would continue with an empty SHA. Both call sites carry `|| exit 1`. Errors go to
        stderr, which `$( )` does not capture, so the message still reaches the user.
      - Scenario J (same rule, rejecting direction) exercises this code but its base must be
        synthesized; the checklist assigns that to task 4, so it is verified there.
- [x] 4. Add the vacuity refusal: a side's set is part 2's required set (guard always, helpers only
      when that side's guard references `lib/`, read from the bytes that will execute); compare sets
      first, then bytes, and never `cmp` a non-member. Synthesize Scenario J's and Scenario L's
      bases — neither shape exists in history (measured at `5bc39b9`, 632 commits, zero in both
      directions).
      - ✅ 2026-08-05: **A** refuses naming `56f1dfd…` (not `main`); **B** refuses under a different
        rev string with identical blobs; **K** refuses (was `378/0/0` exit 0 under the "all three
        match" phrasing); **J** named error citing `hooks/lib/classify-git-command.py`; **L**
        refuses. Non-vacuous side unaffected: **C** `358/20/0`, **D** `378/0/0`, **I** `234/82/62`,
        all exit 0, none refused — so the refusal discriminates (Scenario H).
      - **L's falsifier actually bit:** its base tree carries both helpers while the candidate's disk
        has none. A disk-based membership reading sees different sets, proceeds, and prints a clean
        `identical / 0 relaxed` under a valid SHA. Reading membership off the guard's bytes refuses.
      - ⚠️ **Synthesis gotcha:** `git clone` checks out the source repo's *current branch*, not
        `main`, so `git checkout -B synthL main` fails and the next commit silently lands on the
        previous synthetic branch — L's base came out with 0 helpers instead of both, which is the
        shape that makes L pass for the wrong reason. Use `origin/main` and assert the shape
        (`grep -c 'lib/'` on the guard, `ls-tree` for the helpers) before trusting a run.
      - Synthetic bases live in a scratchpad clone and **do not survive a `/clear`**. Recipe:
        clone with `--no-hardlinks`, then from `origin/main` — **J** = `rm -rf hooks/lib` + commit;
        **L** = overwrite `hooks/git-guard.sh` with `git show e3b09ba:hooks/git-guard.sh` + commit
        (helpers stay in the tree), then `rm -rf hooks/lib` in the worktree for the candidate.
- [x] 5. Resolve `WT` to an absolute path; named error if it does not contain `hooks/git-guard.sh`.
      - ⚙️ **Model switch happened here.** Gate answer, 2026-08-05: Opus 5 for tasks 1-4 — the red
        reproduction and the comparison logic, where every silent false pass in this spec's history
        actually lived — then `/model` down to Sonnet 5 for tasks 5-10, which are mechanical.
        `model_tier: low` set in the frontmatter at the same time.
      - `WT_INPUT="$1"` keeps the as-typed string for the error message; `WT="$(cd "$WT_INPUT"
        2>/dev/null && pwd -P)"` resolves it, per the pinned toolchain (not `readlink -f`). Fails if
        empty or `$WT/hooks/git-guard.sh` doesn't exist. Verified by execution under `/bin/bash`
        3.2.57: Scenario G now reports 358/20/0 exit 0 (was 378/0/0 exit 0 — the candidate silently
        exiting 127 was being tallied `same`); Scenarios A, C, F re-verified unregressed; the named
        error also fires for `/tmp` (real dir, no guard) and a nonexistent path.
- [x] 6. Print the resolved base in the header (line 134) and the summary line.
      - Both sites now print `base=$BASE_SHA ($BASE_REV)` — 40-char SHA never replaced by the rev
        string, per part 5. Re-verified by execution: C (`358/20/0`), D (`378/0/0`), G (`358/20/0`),
        I (`234/82/62`) all print the resolved SHA at both the header and the summary line, matching
        each other; all exit 0; no regression from task 5. E/F/J/K refuse or error before reaching
        either printf, so this change doesn't touch them.
- [x] 7. Verify scenarios A-L by execution — **all twelve, L included** — `$?` captured immediately,
      results as a table. L is the falsifier for part 3's membership rule; a run that skips it has
      exactly revision 7's coverage.
      - ✅ 2026-08-05, single pass under `/bin/bash` 3.2.57, `$?` captured on the line immediately
        after each run:

        | scenario | result | exit |
        |---|---|---|
        | A | refuses, names `56f1dfd…` (not `main`) | 1 |
        | B | refuses under `f5c5689` (different rev, identical blobs) | 1 |
        | C | `base=b17a666…` header+summary, `358/20/0` | 0 |
        | D | `base=bc7da76…` header+summary, `378/0/0` | 0 |
        | E | names `286fd5a2…` + the missing path | 1 |
        | F | names `'0000000'` as typed, zero 40-char SHAs | 1 |
        | G | `base=b17a666…`, `.` resolved, `358/20/0` (was vacuous `378/0/0`) | 0 |
        | I | self-contained NOTE, `base=e3b09ba…`, `234/82/62` | 0 |
        | J | names resolved SHA + missing `classify-git-command.py` | 1 |
        | K | self-contained NOTE, then refuses (was `378/0/0` exit 0 pre-task-4) | 1 |
        | L | refuses — same bytes, disk-based membership would have reported clean | 1 |
        | H | holds: A,B,E,F,J,K,L refuse/error; C,D,G,I report — confirmed by the rows above | — |
      - J's and L's bases don't survive `/clear` (scratchpad); regenerated per task 4's recipe.
        **L's base and candidate must live in one clone** — the base commit only needs to exist in
        the object database (an orphaned branch is enough), not be checked out, since `resolve_rev`
        and `extract_required` both run `git -C "$WT" ...` against the candidate's own repo. A
        two-clone setup (base in one clone, candidate in another) makes the base SHA unresolvable
        from the candidate's worktree — caught by F's own error message, not a real failure of L.
      - K's candidate is `e3b09ba` checked out standalone in its own clone; `BASE_REV=e3b09ba`
        resolves there directly since it's the same repo's own history.
- [ ] 8. Confirm no dependent suite moved and no file outside the harness changed.
- [ ] 9. ADR 0016; provenance notes on the four sites in the part-6 table (ADR 0015 untouched).
- [ ] 10. Observability judge, then PR at the judged sha.

## Revision 9 — round-1 compliance (new cycle) + sixth architecting read

Round 1 of the new cycle cited **one** violation; the architecting read (advisory, `risk=medium`)
raised three more as non-blocking. All four are fixed here, because three of them are the same
class of defect revision 8 was written to fix, and one was introduced *by* revision 8.

- **BLOCKING — `writing-specs/task-list-scenario-drift`. Task 7 still said "verify scenarios A-K".**
  Revision 8 added Scenario L and updated Scenario H and task 4, but not the checklist step that
  actually runs the scenarios — so an implementer working the list would have reproduced revision
  7's coverage exactly and never run the falsifier the whole revision exists to add. Now A-L, with
  the count spelled out. The same drift, one document later: a rule updated in three places out of
  four.
- **Revision 8's own over-claim, narrowed.** Its `cmp` bullet asserted that part 2 "has already
  proved every member of each side's set extracted non-empty". That is true for the base and for a
  *rev* candidate, and **false for the default `worktree` candidate**, which part 2 never validates
  (deferral 2). Both judges flagged it independently. The bullet now claims only what it can — a
  non-member is never an operand — and states the residual: in default mode a member can be absent
  from disk, `cmp` reports "not identical", the run proceeds, and **limit 2** governs the outcome
  (candidate exits 2 on every command → `relaxed` 0 → a silent pass). A false safety claim is worse
  than the gap it conceals, because it stops the next reader looking.
- **The disk-reading rule de-duplicated.** Revision 8 fixed a drifted pair of rules and then created
  a smaller one beside it: "read from disk, not `git show HEAD:`" was stated once for membership and
  again for byte comparison. Now stated **once**, covering both uses, with the membership paragraph
  pointing at it instead of restating it. Noted there: two rules now depend on it, and the scenario
  that would test it is deferral 1 (the dirty worktree), which is correspondingly stronger again.
- **Part 5's header half is now falsifiable.** No scenario asserted the base in a *successful* run's
  header — only in refusals (A, E) and on the summary line (C, D) — so an implementation that fixed
  the summary and left line 134's hard-coded `main` alone passed every scenario in the file. That is
  route 5 surviving the part written to close it. Scenario D now asserts the header too.
- **The history counts pinned to a SHA.** `631`/`65` were already `632`/`66` by the time the judges
  measured — the spec's own commit moved them, and any commit will. They are now stated **as
  measured at `5bc39b9`**, which is what the rest of this spec demands of every other number: a
  figure that does not carry its baseline cannot be audited later. Re-measured at that commit, in
  both directions: of 632 commits, 66 carry the guard alongside at least one helper and all 66
  reference `lib/`; 66 guards reference `lib/` and all 66 carry both helpers. **Zero mixed-shape
  commits either way** — the substantive claim behind Scenarios J and L is unchanged and exact.

## Revision 8 — fifth architecting read (advisory, `risk=medium`)

Revision 7 **passed compliance round 7** — the first pass in seven rounds. This revision voids that
verdict deliberately, on a user decision taken with that cost stated: compliance re-enters at round 1.

- **Invariant 2 tightened once more — a side's file set is now *defined*, not assumed.** Revision 7
  said "exactly the same paths are present on both sides" without saying what makes a path count.
  Both readings — files present on disk, versus files the guard actually uses — satisfied all 11
  scenarios, so nothing in the spec pinned either. Under the disk reading, a base carrying
  **unreferenced** `lib/*.py` against a candidate without them has "different sets", proceeds to the
  matrix, and compares a program against itself: `identical / 0 relaxed`, exit 0, **stamped with a
  valid 40-character SHA** — route 1 restored in the one shape this spec's own fix invites, a run
  testing a revert of the helper split. Part 3 now defines membership as part 2's required set
  (guard always; helpers only when that side's guard references `lib/`) and says so once, with part 2
  amended to state that part 3 *reuses* the rule rather than paralleling it. Stating it in two places
  is precisely how revision 6 left part 2 conditional while part 3 still assumed three files.
- **Membership is read from the executing bytes.** For `UNDER_TEST=worktree` the candidate's set is
  decided by the on-disk guard, not `git show HEAD:` — the same on-disk-is-truth rule part 3 already
  applied to byte comparison, now applied to set membership too, so the two cannot diverge.
- **The unreferenced-helper case is symmetric**, and the spec now says so: helpers present on *both*
  sides but differing in bytes are equally irrelevant, because bytes neither guard loads cannot make
  a run differential. One rule covers presence and content.
- **Scenario L added** — the falsifier for the disk reading, which A-K could not distinguish.
  Scenario H updated to include it.
- **Two history counts re-measured on 2026-08-05 and corrected `629` → `631`.** Scenario J's base and
  Scenario L's base are both absent from the full history: of 631 commits, 65 carry `git-guard.sh`
  alongside at least one helper and **all 65** reference `lib/`; symmetrically, 65 commits' guards
  reference `lib/` and **all 65** carry both helpers. (Superseded by revision 9, which pins these to
  a SHA: `632`/`66` as measured at `5bc39b9`. Zero mixed-shape commits either way, then and now.)
  The repo holds exactly two clean populations
  and no mixed shape, so both bases must be synthesized. The earlier `629` was measured at an older
  HEAD; leaving it beside a fresh figure is the kind of drift rounds 3-6 kept surfacing.

## Revision 7 — round-6 compliance + fourth architecting read (consolidation)

Rounds 3, 4, 5 and 6 each found an error created by the previous revision's own fix. The user
directed a consolidation pass rather than a fifth point fix: instead of editing the cited instance,
enumerate every place the spec states each of the two invariants that kept breaking, and make them
agree in one edit.

- **Invariant 1 — how a base is identified in output — reconciled at every site.** The contract
  required the resolved 40-char SHA and forbade the bare rev string, but three other places
  contradicted it. Revision 6 fixed only Scenario F, which is why the id recurred. Now: part 2's
  extraction-failure clause names the resolved SHA (extraction runs *after* `rev-parse`, so a SHA
  always exists there); Scenario E names the resolved SHA rather than "the rev"; Scenario F is the
  sole exemption and now says explicitly that no SHA is printed because `rev-parse` produced none.
- **Invariant 2 — how many files a side has — reconciled, closing a hole revision 6 opened.**
  Making the helpers conditional (revision 6) left part 3 still saying "compare the three files … if
  all three match". Measured: `cmp -s` on two *absent* paths exits **2**, not 0, so "all three
  match" is never true for a self-contained side and the vacuity refusal never fires. On a probe
  copy carrying revision 6's phrasing, `e3b09ba` against itself ran to completion —
  `378 identical / 0 relaxed`, exit 0 — instead of refusing. Route 1, reopened by the fix for a
  different route. The `cmp -s` behaviour was re-verified directly on this host, not taken on
  report. Part 3 became **set-first, then bytes**: same paths present on both sides, and
  every shared path byte-identical; absent-on-both is agreement and never reaches `cmp`.
  ⚠️ **Refined by revision 8 above**, which defines *which* paths count as a side's set — this
  phrasing left that open, and the disk reading of it reopened route 1 a third time.
- **Scenarios I, J and K added**, because the rule changed and nothing tested it — an implementation
  reverting to "all six required" (fails I), dropping the helper check entirely (fails J), or
  phrasing vacuity as "all three" (fails K) would otherwise have passed every scenario. J's base
  does not exist in 629 commits and must be synthesized. Scenario H updated to cover them.
  (`629` was the history size when revision 7 was written; re-measured as **631** in revision 8.)
- **The pinned-toolchain block corrected.** It claimed "measured on this host, not recalled" while
  asserting `cmp --quiet`, `diff -q --no-dereference` and `readlink -f` were GNU-only. Re-measured:
  all three work here. The POSIX spellings remain mandatory, but as a portability choice, now stated
  as one. The figures in this spec were always honest; this was prose around them that was not.
- **The five deferred architecting recommendations are now written into the non-goals**, with the
  round that raised them and the user decision that deferred them, so "decided against" is
  distinguishable from "forgot".

## Revision 6 — round-5 compliance + third architecting read

- **⚠️ Supersedes the "all six `git show` calls" rule below (revision 3).** Requiring all six would
  reject a legitimate baseline: `e3b09ba` predates the `hooks/lib/` split, its `git-guard.sh` has
  **0** occurrences of `lib/`, and it is one of this spec's own reference rows (`234/82/62`). Part 2
  now makes `git-guard.sh` mandatory on both sides and the two helpers conditional on that side's
  guard actually referencing `lib/`. Scenario E is unaffected — `286fd5a` is missing
  `hooks/git-guard.sh` itself, so its named error still fires. Found by the architecting read.
- **The classifier pointer corrected, `:56` → `:74-77`.** The limit-2 bullet described the right
  behaviour (a candidate missing `hooks/lib/*.py` exits 2 on every command, `ls -la` included) and
  cited the wrong branch: `:56` is the `exit 2` of the python3-not-on-PATH guard at `:53-57`, while
  the classifier guard is `:74-77`, resolving `CLASSIFIER` at `:44`. Both exit 2, which is how they
  were confused. This bullet is routed verbatim into ADR 0016 by part 6, so the wrong pointer would
  have been permanent. Third consecutive round to find a distinct error in this one bullet;
  escalated to the user, who directed the targeted fix after an audit showed **12 of the spec's 13
  code pointers were already correct** and this was the only wrong one.
- **Scenario F exempted from the resolved-SHA clause.** The refusal contract required every named
  error to print the resolved base SHA "not the rev string", but Scenario F is the case where
  `rev-parse` cannot produce a SHA at all — the two could not both be satisfied. The contract now
  names the unresolvable rev as the single exception, and says why it cannot generalise: every other
  named error occurs after a successful `rev-parse`.

## Revision 3 — round-2 compliance findings

- **Scenario G pinned to a non-vacuous base.** As written it named no base, inherited the default
  `main`, and would have been refused by part 3 before route 3 was ever reached — testing nothing
  while appearing to pass. Now uses `b17a666` and asserts Scenario C's exact counts.
- **The citation sites are enumerated** — five sites across four files, in a table, with ADR 0015
  marked not-edited. "The three citing documents" was never a list, and one of the four was the file
  the spec forbids touching.
- **Extraction validation covers all six `git show` calls**, not three, with the opposite failure
  directions of base and candidate stated.

## What changed from revision 1

- **Part 3 reversed.** Revision 1 proposed retracting the cited `378` figures as false evidence. They
  are valid; the retraction would have been the false statement, and permanent. Replaced by
  provenance annotation plus "state the base in every run's output" — the finding the architecting
  read identified as the stronger one.
- **Three false-pass routes added** that revision 1 did not know about: the degenerate 0-byte
  baseline (compliance violation 2, confirmed by measurement — though its predicted rev behaved
  differently than the judge expected, the mechanism is real), the relative-path 127 route (found
  while re-measuring), and the unnamed baseline in the output.
- **Scenario B's expectation corrected** from `stricter > 0` to `0 stricter, 0 relaxed` — revision 1
  predicted a number that measurement shows is zero, and contradicted its own non-goals doing it.
- **Scenario B repurposed** as the rev-string falsifier; scenario set grew to A-H so that no
  implementation hard-wired to refuse or to pass can satisfy it.
- **Toolchain pinned** with versions read off this host, and the BSD `cmp` trap named.
- **The worktree-side ambiguity resolved**: on-disk bytes, not `git show HEAD:`.

## Verification

### Task 1 — Red reproduction (2026-08-05, unfixed script)

**PASS — all six rows reproduce the spec's table exactly, exit codes included.** `$?` captured on the
line immediately after each run, before any other command; no command substitution intervenes.

| row | base | `WT` | identical | stricter | relaxed | exit | vs. spec |
|---|---|---|---|---|---|---|---|
| 1 | `main` (default, arg omitted) | absolute | 378 | 0 | 0 | 0 | ✅ |
| 2 | `bc7da76` | absolute | 378 | 0 | 0 | 0 | ✅ |
| 3 | `b17a666` | absolute | 358 | 20 | 0 | 0 | ✅ |
| 4 | `e3b09ba` | absolute | 234 | 82 | 62 | 0 | ✅ |
| 5 | `286fd5a` | absolute | 118 | 260 | 0 | 0 | ✅ |
| 6 | `main` (default) | `.` | 378 | 0 | 0 | 0 | ✅ |

Mechanisms confirmed directly, not inferred from the totals:

- **Route 1 (vacuous, row 1)** — base and candidate are the same bytes: `hooks/git-guard.sh` is blob
  `2b74507` at both `main` and `HEAD`, and `git diff main HEAD -- hooks/` is empty. Row 2 differs from
  row 1 only in `shell_segments.py` (`b8fed46` → `7197eb0`) yet prints the identical `378/0/0`.
- **Route 2 (degenerate, rows 4-5)** — the unchecked `git show` failures are visible on stderr: three
  `fatal:` lines for `286fd5a`, two for `e3b09ba`. `bash <empty file>` measured at exit **0**, so the
  base allows everything and `relaxed` is 0 by construction in row 5 — while the harness still exits 0.
- **Route 3 (relative `WT`, row 6)** — `bash ./hooks/git-guard.sh` from a non-repo cwd measured at
  exit **127**; `run()` swallows it (`2>&1` to `/dev/null`) and the `else` branch tallies `a=2,b=127`
  as `same`. Row 6's 378 "identical" pairs are 378 pairs in which the candidate never executed.
- **Route 5 (no base in output)** — every row's header printed `worktree`, never the base rev.

Falsifier: rows 3-5 returned non-zero `stricter`/`relaxed`, so the probe was genuinely varying the
base. A uniform `378/0/0` across all six would have meant the base parameter was inert.

⚠️ **`main` moved during the branch's life** (`c461e4c` → `56f1dfd`, two docs-only commits), but
`git-guard.sh`, `classify-git-command.py`, and `shell_segments.py` are **byte-identical at both** — so
these rows remain comparable to the spec's. Re-check that before trusting any later re-run.

**Probe** — `git-guard.replay.probe.sh` in the session scratchpad; tasks 2-7 re-run it. It is the
unfixed harness plus a base parameter and nothing else (`diff` = 4 lines). **A `/clear` discards the
scratchpad**, so regenerate it from the repo file with:

```sh
sed -e '7a\BASE_REV="${3:-main}"' -e 's|show main:hooks/|show "${BASE_REV}:hooks/|' \
    hooks/git-guard.replay.sh > "$PROBE"
perl -0pi -e 's{show "\$\{BASE_REV\}:(hooks/\S+)(\s+)>}{show "\${BASE_REV}:$1"$2>}g' "$PROBE"
```

Then `diff hooks/git-guard.replay.sh "$PROBE"` must show exactly those four lines and nothing else —
if it shows more, the probe has acquired a fix and is no longer the Red baseline.
