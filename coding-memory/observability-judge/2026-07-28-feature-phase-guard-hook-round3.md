# Observability verdict — feature/phase-guard-hook (RUN 3)

- **repo:** `phase-guard-hook` (worktree of `~/.claude`)
- **branch:** `feature/phase-guard-hook` · **base:** `main` (merge-base `8f0f16d`)
- **head_sha:** `4a60aa04f8dd5737df2df7401522c47f3ae9950c`
- **stage:** `implementation` (gates the PR)
- **ts:** 2026-07-28T19:43:25Z
- **prior rounds:** RUN 1 (`01f011e`), RUN 2 (`f963b76`) — both read before scoring
- **evidence I ran myself:** `bash hooks/phase-guard.test.sh` → **96 passed / 0 failed**;
  `shellcheck -x hooks/phase-guard.sh hooks/phase-guard.test.sh` → clean (exit 0);
  four purpose-built probe repos under `/tmp/pgprobe` exercising skip-accounting shapes the
  suite does not cover.

---

## LEAD: I found the fourth route. The class is still open.

The round asked one question — is the third attempt a class fix or a third instance patch?
The honest answer is **both**. The fix genuinely closes every *exit* path: I traced all nine
`exit` statements downstream of the new check (lines 236, 281, 303, 317, 323, 324, 327, 337,
and the deny at 366) and every one of them is now below the warning. That part is a real
class fix and the reasoning behind it is correct.

But the class was drawn at **"exits"**, and the hole is one stage earlier — in the **skip
accounting itself**. Line 194:

```sh
for f in "$root"/docs/features/*.md; do
  [ -f "$f" ] || continue          # no match: the glob stayed literal, so the dir is empty
  nfiles=$((nfiles + 1))
```

`[ -f ]` is doing two jobs: detecting an empty directory (its documented job) and, silently,
discarding any card that exists but is not a regular file. A card dropped there is **never
counted**, so `nfiles > nparsed` stays false and the warning cannot fire. Reproduced, three
shapes, all against HEAD:

| `docs/features/` contains | result |
|---|---|
| mode-000 card (control — a real file awk cannot open) | exit 0, **warns** ✅ |
| dangling symlink `ghost.md -> /nonexistent/gone.md`, alone | exit 0, **silent** ❌ |
| dangling symlink + a readable `review` card | exit 0, **silent** ❌ |
| a directory named `weird.md` | exit 0, **silent** ❌ |

This is the identical failure to RUN 1 and RUN 2: a card the guard cannot read costs the gate
its opinion **silently**. And if that unreadable card was the only `planning` card, the write
is not merely un-warned — it is **allowed when it should have denied**. Same consequence, same
invisibility, one stage upstream of both previous instances.

Two things make this worse than a stray edge case:

1. **The code comment now asserts the invariant it does not honour.** "A skipped card is
   unreadable no matter which path the hook then takes" is exactly right — and a card dropped
   by `[ -f ]` is a skipped card that takes no path at all.
2. **The spec now normatively claims closure** ("Guarding exits one at a time produced the same
   defect twice"), which reads to a future maintainer as *this class is handled*.

Likelihood is genuinely lower than the previous two (those were ordinary shapes: one good card
plus one bad; a superseded card). A non-regular file in `docs/features/` needs a symlink whose
target moved, a sparse/partial checkout, or a stray directory. In a machine that runs feature
work out of **git worktrees**, a symlinked card is not exotic. Cost to close: two lines —
`[ ! -e "$f" ] && [ ! -L "$f" ] && continue` before the counter, which I verified distinguishes
the empty-glob case from a dangling symlink correctly.

---

## SECOND FAIL: the stale-spec defect RUN 2 raised is still present in three places

RUN 2 finding 2 was "the spec contradicts the shipped code". Escalation 9 records it as
corrected. It corrected the **Exits table and the paragraph beneath it** — the two places the
judge pointed at — and left the same stale rule standing in three others, including the most
canonical one:

- **Line 233, the numbered algorithm** (the section a maintainer reads first): *"Collect
  `planning_files`; empty → ⊘. If **every** file was skipped, ⊘ and print one line."* Both the
  old condition **and** the old placement — the exact two things this round fixed.
- **Lines 464–466, the Output contract:** *"the no-interpreter and **all-files-skipped** exits"*.
- **Line 549, the A2 Gherkin example:** *"**every** `docs/features/*.md` violates the
  frontmatter contract"*.

A maintainer restoring behaviour from the spec would reintroduce RUN 1's bug from line 233 and
RUN 2's bug from the same line. This is the second consecutive round where the fix addressed
the named instance rather than the pattern — the same meta-failure as the code finding above,
in the documentation.

Also stale, minor: line 544 asserts stderr "carries exactly one line in total". Not true on the
unopenable-file path — see below.

---

## Per-write stderr noise the green suite cannot see

On the mode-000 card, awk's own error escapes unredirected, on **every write**:

```
awk: can't open file /…/docs/features/locked.md
 source line number 10
phase-guard: a file in docs/features/ could not be read as a feature card…
```

Write 1: three lines. Writes 2 and 3: two lines each — `warn_once` correctly suppresses the
designed line, and does nothing about the noise beside it. Per-write output on the hottest hook
on the machine is the precise thing the once-per-session design exists to prevent.

The suite has 96 green tests and `allow_audible` *does* assert exactly one stderr line — it
never fires because every "unreadable" fixture in the suite is **malformed content**, which awk
parses quietly. The suite's vocabulary conflates *violates the contract* with *cannot be read*.
`awk … 2>/dev/null` closes it.

---

## What I checked and found genuinely sound

- **Every downstream exit is covered.** I traced all nine by hand. No fourth *exit-path* route
  exists. The upstream placement is the right call.
- **The deny contract survives the prepended warning.** Measured: plain deny = 16 lines;
  deny + skip = 17 lines, warning first, all four required elements intact, exit 2 preserved.
  A3's "stderr does not name bad.md" still holds because the warning names no file. I judge
  prepending **correct** — the "Still at planning:" list may be incomplete, and that is exactly
  when the reader needs to know the gate is partially blind. One cosmetic note: it buries the
  `write blocked` headline by one line; below the message would read slightly better.
- **RUN 2 finding 3 (false message) is properly fixed.** "could not be read as a feature card …
  if it is one" is true for a `README.md` and true for a real card. Leaving the underlying
  contract question open **is defensible**: guessing "non-card files don't count" would silently
  re-open the very hole this round is about, and guessing the other way spams every repo with a
  README. Recorded as open rather than settled by wording is the right disposition.
- **Checkpoint discipline is textbook.** `8b0f0ff` test alone (verified red), `4a60aa0` fix +
  spec. Clean revert point at either commit.
- **Tests are real.** I ran them; 96/0 is accurate, not reported.

## Open items I was asked to assess

- **Parallel-worktree collision** — leaving the *decision* to the user is correct
  (`core-conduct`: architecture trade-offs stay human-owned). Leaving it **buried at line ~1340
  of a 1,418-line spec while merging the thing that activates it machine-wide** is not. It
  belongs in the PR description, not only in the spec.
- **Non-card file in `docs/features/`** — defensible to leave open, as above.
- **Rollback path 3 (`chmod -x` → 126) withdrawn, unverified** — accepted. `settings.json` is
  guard-exempt by design, so a working rollback path exists.
- **A third silent "opted-in but could not evaluate" exit.** The header taxonomy says six exits
  mean "not applicable" and two mean "could not evaluate". Verified: in an opted-in repo holding
  a `planning` card, a truncated payload or one with no path key exits 0 **silently** at line 123
  — which is "opted in, could not evaluate", not "not applicable". Low likelihood (the harness
  generates the payload) and arguably correct to stay silent; flagged as a taxonomy inaccuracy,
  not a defect. Relatedly the header's "eight fail-open exits" no longer matches the 19 `exit 0`
  statements in the file.
- **`nosession` shared flag key** permanently silences every id-less session after the first —
  pinned by A2.12 as deliberate. Known residual, not a finding.
- **RUN 2 finding 4 (never run live) — still true.** Nothing in this branch has executed as a
  registered hook. Everything above, mine included, is direct-invocation evidence.

---

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | concern | Did what RUN 2 asked; neither the code class nor the spec correction was carried to completion. |
| `execution` | concern | 96/0 real, shellcheck clean, deny contract verified intact — with a reproduced silent-allow hole. |
| `trajectory` | concern | The upstream-of-every-exit reasoning is correct and well-argued; the class boundary was drawn one stage too low, for the third round running. |
| `regression` | pass | Deny message intact (16→17 lines, all four elements), no adjacent hook touched, suite green. |
| `context_budget` | pass | Always-on delta is one rewritten `rules/gates.md` bullet; the 1,418-line spec is on-demand. |
| `traceability` | **fail** | The numbered algorithm, the Output contract and the A2 Gherkin still document the pre-fix rule — the defect RUN 2 raised, recorded as closed. |
| `success_masking` | **fail** | 96 green tests over a reproduced silent allow; the suite never builds an *unreadable* card, only a malformed one, and that gap also hides per-write awk noise. |
| `intent_drift` | pass | Two tightly scoped commits, no drive-by edits, no dependency changes. |
| `checkpoint` | pass | Failing test committed alone and verified red before the fix; clean revert points. |
| `audit_trail` | pass | ADR 0011 present, escalations 7/8/9 written up with reproduction detail; attribution clear. |

**risk: high · confidence: high**

Confidence is high because every claim above is a command I ran against this HEAD, not a reading.
Risk is high not because the guard is dangerous — it fails open, so it cannot falsely block —
but because this is the third consecutive round of one defect class, the class is still open in
the code, and the spec that outlives the code teaches the old rule in its canonical section.
Both fixes are cheap: two lines in the loop, one `2>/dev/null`, three spec edits.

## Concerns

1. `[ -f ]` at line 194 drops a non-regular card before counting it — dangling symlink or
   directory named `*.md` yields a silent allow; reproduced three ways.
2. Spec still states the pre-fix rule at line 233 (numbered algorithm), 464–466 (Output
   contract) and 549 (A2 Gherkin) — the RUN 2 defect, recorded as closed.
3. awk's "can't open file" leaks to stderr on every write for an unopenable card, bypassing
   `warn_once`.
4. Suite never constructs an *unreadable* card, only a malformed one — the gap that hides 1 and 3.
5. Parallel-worktree collision activates machine-wide on merge and is buried in a 1,418-line spec.
6. Never executed as a registered hook; all evidence is direct invocation (carried from RUN 2).
7. Header taxonomy inaccurate: a third silent "opted-in, could not evaluate" exit at line 123;
   "eight fail-open exits" vs 19 `exit 0` statements.
