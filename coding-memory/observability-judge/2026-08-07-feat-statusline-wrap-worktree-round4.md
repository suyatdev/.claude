# Observability verdict — statusline wrap + worktree name (round 4, delta only)

- **Repo:** statusline-wrap-worktree (isolated linked worktree)
- **Branch:** `feat/statusline-wrap-worktree`
- **HEAD:** `5024f9c12e956726f8c025aff7eeeda0e9746ea8`
- **Stage:** implementation
- **Judged:** 2026-08-07T04:15:00Z
- **Delta under review:** `5024f9c` (test tightening + docs; no runtime code)
- **Prior rounds:** `dbf1bbc` (1), `66cb17e` (2), `64e6622` (3) — all risk=low/confidence=high
- **Tests:** 68/68, run by me on a clean tree
- **Filename note:** the `-round4` suffix follows the convention rounds 2 and 3 established in
  this directory. Writing the bare `<date>-<branch_slug>.md` would overwrite round 1 and destroy
  the audit trail this branch has been building.

---

## What was changed

Three things, all of them words or tests. **Not one byte of the actual status-line script
changed** — I confirmed that structurally, not by sampling: `git diff 64e6622..5024f9c --
statusline-command.sh` is empty, and the commit touches exactly four files, none of them the
script.

1. A test that said "the status line must not use more than **8** rows" now says "must not use
   more than **6**" — 6 being the number of pieces this particular test's status line actually
   has. The old number let a bug through; the new one doesn't.
2. The feature checklist was brought up to date (it still claimed 66 tests; there are 68).
3. A known cosmetic wart — a bash warning printed on absurd terminal widths — was written down
   as a task instead of staying an unrecorded observation.

## Does it do what was intended?

**Yes on all three, and the headline claim survives independent checking.**

**Question 1a — is 6 the real segment count, or fitted to observed output?** It is the real
count, and it comes from the code's structure rather than from the output. I traced the script
(`bash -x`) against a freshly built linked-worktree fixture: the packing loop terminates at
`[ 6 -lt 6 ]`, so `${#seg_text[@]}` genuinely is 6, matching the six `push_segment` call sites
this payload activates (arrow+`user@host`, dir, `git:()`, `wt:()`, model+effort, token bar) out
of the eight that exist. So this is **not** the "test fitted to whatever came out" failure mode.

**Question 1b — is it still non-vacuous?** On this machine, yes, provably. I rebuilt your mutant
independently (deleting the `[ $i -gt 0 ]` guard, byte-verified as the only difference), ran the
whole suite against it in an isolated directory, and got **67/68 with exactly
`row count exceeded this payload's segment count (rows=7>6)`**. The commit message's claim is
literally true.

## What could go wrong

**The assertion's ability to fail depends on your username and hostname — which the test does
not control.** This is the substantive finding.

Segment 0 is `➜  $(whoami)@$(hostname -s)`, built at `statusline-command.sh:160-162` from the
machine, not the fixture. The mutant only misbehaves when segment 0 *alone* is wider than
`wrap_at` (= `COLUMNS - 2` = 22 here); if it fits, the spurious blank row is never emitted at
all. So the detection threshold is `len(user) + len(host) > 18`. This machine:
`marksuyat` + `Marks-Mac-Studio` = 9 + 16 = 25, comfortably over. A CI container with `root` and
a 12-character hostname = 16, comfortably under.

I measured both sides by putting a `whoami`→`u` / `hostname`→`h` shim on `PATH`:

| environment | real script, rows @ COLUMNS=24 | mutant A, rows | suite vs mutant A |
|---|---|---|---|
| this machine (`marksuyat@Marks-Mac-Studio`, 25 cells) | 6 (bound exactly tight) | 7 | **67/68 — caught** |
| short `u@h` (6 cells) | 5 (one row of slack returns) | 5 | **68/68 — green against the mutant** |

So the delta closes the hole *here* and it reopens anywhere `user@host` is short. That is a
smaller guarantee than "the slack is closed," and nothing in the test or its comment tells a
future reader that the assertion's power hinges on their hostname. Row sweeps confirm the
mechanism: rows plateau at 6 across widths 14–31 on this machine, but at 14–21 only (then 5)
under the short shim.

**Secondary slack, one-directional.** `-le` bounds rows from above only. A regression that
*drops* a segment renders 5 rows and passes. `wt:()` presence is asserted elsewhere, but at the
default width, not at wrapping widths.

**Question 2 — is hard-coding brittle? Yes, and it misdiagnoses.** I added a plausible new
always-on segment (a clock `push_claude_segment`) to a copy of the script. The assertion fails
with `row count exceeded this payload's segment count (rows=7>6)` — a sentence that is now
**false**, because the payload's segment count is 7. The message accuses the packing loop when
the correct action is bumping a constant, which is the kind of red test that gets "fixed" in the
wrong file.

**What it should assert instead.** Make the head width fixture-controlled and the bound
two-directional: put a `whoami`/`hostname` shim on `PATH` inside the test so segment 0 is
guaranteed wider than `wrap_at` regardless of machine, then assert **equality**
(`rows -eq EXPECTED_ROWS`) rather than `-le` — at that width every segment must start its own
row, so equality is exactly correct, catches a dropped segment as well as an extra one, is
machine-independent, and fails with an honest message. If you would rather not hard-code at all,
derive the count from a wide single-line render; the shim plus `-eq` is simpler and stronger.

**Question 3 — anything else this delta broke?** No. Runtime unchanged (empty script diff, so
this is structural, not sampled); suite 68/68 on a clean tree; `shellcheck -f gcc -x` findings
**byte-identical** between parent and HEAD (two pre-existing info-level SC2015, neither in the
changed region); `verdicts.jsonl` 106/106 valid JSON; no new absolute `/Users/...` paths (the
grep hits are pre-existing rows plus one quoted mention inside the round-3 verdict);
`git revert --no-commit HEAD` applies cleanly and the tree is clean. Feature-file claims all
check out: 68/68 corrected, 8b and 8c ticked, task 11 logged, 8d left open with the correct
`judge-guard` repo-basename and strict-freshness caveat.

## What I'd double-check before merging

1. Decide whether to make the row assertion machine-independent — shim `whoami`/`hostname` in
   the test and switch `-le` to `-eq`. Without it, this assertion is a guard that works on your
   laptop and quietly stops working in a container. Cheap; not blocking.
2. If you keep the hard-coded 6, add one line to the comment saying the assertion is only tight
   while `len(user)+len(host) > 18`, so the next reader isn't misled by a green run.
3. Consider making the failure message name the constant (`EXPECTED_ROWS`) so a legitimate new
   segment sends the reader to the right line.
4. Carried and unchanged by this delta: injection cases are still pinned to `COLUMNS=400`, so
   injection × wrapping stays untested in-suite.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| `intent` | pass | All three stated items done. The headline claim verified independently: segment count is genuinely 6 (traced from `${#seg_text[@]}`, not read off output), and the rebuilt mutant fails with exactly `rows=7>6`. |
| `execution` | pass | 68/68 on a clean tree, run by me. `shellcheck` findings identical to parent. Mutant reproduction matches the commit message exactly. |
| `trajectory` | pass | Mutation-driven tightening is the right method and the reasoning is explicit, not lucky. It missed one dependency — that the mutant's visibility rests on an uncontrolled `whoami`/`hostname` — but the conclusion is correct as far as it goes. |
| `regression` | pass | Zero runtime bytes changed (empty script diff, verified structurally). Lint parity exact. Revert applies cleanly; tree clean. |
| `context_budget` | pass | Nothing always-on. ~8 lines of test comment plus on-demand verdict markdown and a checklist line. |
| `traceability` | pass | Commit body states the change, the evidence and the reasoning; the test comment explains why the ceiling was wrong. Feature file reconciled to reality. |
| `success_masking` | **concern** | The assertion's power depends on `whoami`/`hostname -s`, which the fixture does not control: measured **68/68 green against the very mutant this commit exists to catch** under a short `user@host` (threshold `len(user)+len(host) > 18`). Separately, `-le` cannot catch a dropped segment. |
| `intent_drift` | pass | Exactly the three declared items across four files, all test/docs. No dependencies, no drive-by edits, no runtime change. |
| `checkpoint` | pass | Clean working tree, single self-contained commit, revert verified, four-file footprint. |
| `audit_trail` | pass | `Co-Authored-By` present; round-3 verdict committed alongside; `verdicts.jsonl` 106/106 parses; no new absolute paths. |

**Risk:** low **Confidence:** high

## Concerns

- Assertion tightness depends on an uncontrolled environment input: segment 0 is `whoami@hostname -s` (statusline-command.sh:160-162), so mutant A is only visible when `len(user)+len(host) > 18`; MEASURED with a `u@h` PATH shim, the same fixture gives 5 rows, mutant A gives 5 rows, and the full suite is 68/68 GREEN against the mutant this commit exists to catch
- Bound is one-directional: `-le 6` cannot catch a DROPPED segment (5 rows passes); `wt:()` presence is asserted only at default width, never at wrapping widths
- Hard-coded EXPECTED_ROWS misdiagnoses a legitimate change: MEASURED by adding a 7th always-on segment — fails with "row count exceeded this payload's segment count (rows=7>6)", a now-false sentence pointing at the packing loop when the fix is a constant
- Neither the test comment nor the commit body discloses that the assertion's sensitivity is hostname-dependent, so a green run on a short-hostname machine reads as coverage it does not have
- Carried from round 2, untouched: injection cases pinned to `COLUMNS=400`, so injection x wrapping remains untested in-suite
- VERIFIED BY ME at 5024f9c: EXPECTED_ROWS=6 is the genuine segment count, not fitted to output — `bash -x` shows the packing loop terminating at `[ 6 -lt 6 ]`, matching the six active `push_segment` sites of eight
- VERIFIED BY ME: the rebuilt mutant (byte-diff confirmed as the sole `[ $i -gt 0 ]` deletion) fails with exactly `rows=7>6`, suite 67/68 — the commit message's central claim is literally true on this machine
- VERIFIED BY ME: no runtime change — `git diff 64e6622..5024f9c -- statusline-command.sh` empty, four files touched, `shellcheck -f gcc -x` findings byte-identical to parent, `verdicts.jsonl` 106/106 valid JSON, `git revert --no-commit HEAD` clean, no new absolute `/Users/...` paths
- VERIFIED BY ME: feature-file claims all true — 68/68 corrected, 8b and 8c ticked, task 11 logged, 8d open with the correct judge-guard repo-basename and strict-freshness caveat
