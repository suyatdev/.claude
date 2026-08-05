---
phase: planning
model_tier: high
branch: none
---

# The replay harness never says what it compared

Planned on `main` @ `c461e4c`, session 10. Model-switch checkpoint 1 answered: stay on Opus 5 for
planning. **Revision 2** — round 1 failed compliance (4 violations) and drew `risk=high` from the
architecting read. Both were right, and one of them overturned this spec's original premise. What
changed is recorded at the end.

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

**2. Validate every extraction.** **All six** `git show` calls — three for the base (lines 13-15) and
three for a rev candidate (lines 20-22) — must succeed **and** yield a non-empty file. On failure:
name the rev and the path that could not be read, print no matrix, exit non-zero. Closes routes 2
and 4.

The two sides fail in opposite directions, and both are covered deliberately: an empty *base* exits 0
and "allows" everything, so `relaxed` is 0 by construction — a silent false pass. An empty *candidate*
"allows" everything too, so every case where the base blocks becomes a **relaxation** — a loud false
alarm. The silent one is why this spec exists; the loud one is one line further and is not worth
leaving open.

**3. Refuse a vacuous run.** Before the fixture repo is built, compare the three files byte-for-byte
between base and candidate. If **all three** match, print the refusal, print no matrix, exit
non-zero. Closes route 1.

- **Compare the bytes that will actually execute.** For `UNDER_TEST=worktree` the harness runs the
  on-disk file (`NEW="$WT/hooks/git-guard.sh"`), so the candidate side is read **from disk, not
  `git show HEAD:`**. The two readings diverge the moment the worktree has uncommitted edits, and
  the on-disk one is the truth. For a rev candidate, both sides are `git show`.
- **All three, not any one.** A branch touching only `shell_segments.py` is a legitimate run — PR #38
  was exactly that, and it is verifiable: between `bc7da76` and `c461e4c`, `git-guard.sh` and
  `classify-git-command.py` are the same blobs (`2b74507c`, `2f8af693`) and only `shell_segments.py`
  moved. A check keyed on "any file matches" would refuse row 2, a real run. Only "nothing differs"
  is vacuous.
- **Compare content, not rev strings.** `main` and the SHA it resolves to are different strings and
  the same code; a worktree with uncommitted edits is the same rev string and different code.

**4. Resolve the worktree path to an absolute path** before use, and fail with a named error if it
cannot be resolved to a directory containing `hooks/git-guard.sh`. Closes route 3.

**5. State the baseline in every run's output** — passing runs included. Replace the hard-coded
`main` at line 134 with the resolved base, and repeat it on the summary line, so a figure copied into
a document carries its provenance. The sibling `hooks/shell-segments-falsifier.sh` already prints its
base on every run; this brings replay to parity. Closes route 5, and is the part that makes the
harness's history auditable without archaeology.

**6. ADR 0016 + provenance notes.** The ADR records the rule, which has now bitten twice:

> A differential harness must prove its two sides differ before reporting agreement, must prove each
> side actually loaded, and must state its resolved baseline in its output. Agreement between a
> program and itself, or between two empty files, is not evidence — and a number that does not carry
> its baseline cannot be audited later without archaeology.

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
cmp:     "BSD"                 # NO --version, NO --quiet; POSIX -s only
shasum:  "6.02"
```

Byte comparison uses **`cmp -s`** (POSIX, present on BSD). GNU-only spellings — `cmp --quiet`,
`diff -q --no-dereference`, `readlink -f` — are forbidden; use `cd … && pwd -P` for path resolution.

### Deliberate non-goals

- **No `git-guard.replay.test.sh`.** Neither harness in `hooks/` has a test sibling; both are verified
  by recorded execution, as PR #39 was. Inventing a test-for-a-test convention mid-fix is unearned
  scope. (Round 1 judge: this reasoning holds.)
- **The 63-command matrix is unchanged** — still zero redirect shapes, a real and separate gap
  recorded in ADR 0015.
- **`hooks/git-guard.sh` is not touched.** Row 4's 62 relaxed rows against `e3b09ba` are genuine
  historical policy differences accumulated across the repo's life, not defects surfaced by this
  change. Investigating them is its own task.

### Scenarios

```gherkin
Scenario A: base and candidate are the same code — refused
  Given the default base on main, where all three files match the worktree
  When the harness runs
  Then the output names the resolved base and says the run proves nothing
   And no pair-count line is printed
   And the exit code is non-zero

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
  # Identical to Scenario A's counts. Only the named base distinguishes a real run from a vacuous one.

Scenario E: a base whose files do not exist — named error, not a pass
  Given 286fd5a, where all three files are absent
  When the harness runs with that base
  Then the output names the rev and the path that could not be read
   And no pair-count line is printed
   And the exit code is non-zero
  # Today this prints "0 relaxed" and exits 0 — a clean pass from three empty files.

Scenario F: an unresolvable rev — named error
  When the harness runs with base 0000000
  Then the output names the unreadable base
   And the exit code is non-zero

Scenario G: a relative worktree path — resolved, never silently counted
  Given the base b17a666, so the run is NOT vacuous and part 3 cannot refuse it first
  When the harness runs with the worktree given as "." and that base
  Then the candidate hook is actually executed
   And the counts match Scenario C exactly: 358 identical, 20 stricter, 0 relaxed
  # Today this reports 378 identical: every candidate run exits 127 and is tallied "same".
  # The base MUST be non-vacuous here, or the part-3 refusal fires before route 3 is reached
  # and the scenario silently tests nothing.

Scenario H: the refusal is discriminating
  Then A, B, E and F refuse or error; C, D and G report
   And no implementation hard-wired to refuse, or to pass, satisfies both halves
```

### Error and refusal contract

Every refusal and every named error: exit **non-zero**, print **no** `DISTINCT COMMANDS` header and
**no** pair-count line, and state in one plain sentence what was wrong, which rev it concerned, and
the corrected invocation. Every *successful* run: print the resolved base in both the header and the
summary line.

## Tasks

- [ ] 1. Red — record the six measured rows above against the unfixed script, exit codes captured
      first, as the reproduction. Do not delete the probe.
- [ ] 2. Add the `BASE_REV` third positional; replace the three hard-coded `main:` refs.
- [ ] 3. Validate all six extractions (success + non-empty); named error on failure.
- [ ] 4. Add the vacuity refusal, comparing executing bytes, all-three threshold.
- [ ] 5. Resolve `WT` to an absolute path; named error if it does not contain `hooks/git-guard.sh`.
- [ ] 6. Print the resolved base in the header (line 134) and the summary line.
- [ ] 7. Verify scenarios A-H by execution, `$?` captured immediately, results as a table.
- [ ] 8. Confirm no dependent suite moved and no file outside the harness changed.
- [ ] 9. ADR 0016; provenance notes on the four sites in the part-6 table (ADR 0015 untouched).
- [ ] 10. Observability judge, then PR at the judged sha.

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

<Appended during review.>
