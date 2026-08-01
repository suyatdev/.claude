# Observability judge — RUN 3 · `fix/judge-guard-fail-closed-classifier`

- **repo:** `jg-failclosed` (worktree `~/.claude/.claude/worktrees/jg-failclosed`)
- **branch:** `fix/judge-guard-fail-closed-classifier`
- **head_sha:** `1d3b4ed0bca26cc8c4909e248eb963a6401bdfb1`
- **stage:** implementation
- **base:** `origin/main` = `2b8564b` · **delta judged:** `59a8963..HEAD` (RUN 2 → now)
- **ts:** 2026-07-31T17:01:35Z
- **risk:** medium · **confidence:** high

> Filed as `-round3`. RUN 1 (`…-classifier.md`) and RUN 2 (`…-classifier-round2.md`) are already
> committed; overwriting either would erase the audit trail this branch exists to protect, and
> `-roundN` is the established convention in this directory.

---

## What was changed

Think of the bouncer and the ID scanner again. Round 1 taught the bouncer "if the scanner is
*missing*, refuse everyone." Round 2 taught him "if the scanner gives me *gibberish*, refuse
everyone." This round closes the last cheap gap: the scanner could **say a valid word and then fall
over** — print a clean `NO`, then crash or exit with an error. The bouncer heard a legal word and
waved everyone through.

The fix is two tokens wide. The hook now checks the scanner's *exit status* alongside its answer:
`case "$classify_rc:$kind" in 0:PR|0:NO)`. It also pins one classifier property: the bypass variable
`JUDGE_EXEMPT` is matched by **exact name**, never by suffix, so another guard's `MERGE_EXEMPT`
can't quietly become a judge bypass.

Two commits, correctly separated: `b095c0a` writes the failing tests only, `1d3b4ed` makes them
pass and touches no test file.

## Does it do what you wanted?

**Yes, and this is a clean delta.** I verified rather than trusted, and I tried hard to break it.

- **Suites re-run by me at `1d3b4ed`:** `judge-guard.test.sh` **64 passed / 0 failed**,
  `classify-pr-command.test.py` **51 passed / 0 failed** — exactly matching the dispatch note.
  `shellcheck -x` reports only the pre-existing SC2181 (at **line 158**, not 151 as the note said —
  cosmetic drift in the note, not in the diff).
- **The red commit really was red.** I replayed `b095c0a`'s tests against the *pre-fix* hook
  (`59a8963`'s `judge-guard.sh`): **62 passed / 2 failed**, and the two failures are exactly the two
  new shapes. The TDD claim holds; this is not a test written after the fact.
- **Mutation tests — the new assertions pin behaviour, not implementation.**
  - **M1**, reverting to the shape-only `case "$kind" in PR|NO)` → **exactly 2 failures**, both new
    cases. Dropping `classify_rc` is caught.
  - **M2**, a *subtler* over-permissive variant `0:PR|0:NO|1:NO)` → **2 failures**. The tests pin
    `rc == 0` specifically, not merely "some status is consulted."
  - **M3**, `name == "JUDGE_EXEMPT"` → `name.endswith("EXEMPT")` → **exactly 1 failure**, the new
    case, with a readable diagnostic. Precisely targeted, no collateral.
- **`$?` genuinely holds the classifier's status.** I did not take the comment's word for it: with
  no `set -e` and no `pipefail` (I grepped — line 20 is `set -u` and nothing else), a
  `var=$(printf … | python3 …)` assignment carries the *pipeline's* status, which is the last
  command's. Built a classifier that prints a well-formed answer and exits 7, with an intervening
  comment line exactly as in the hook: **captured rc=7**. Correct.
- **12 hand-built classifier shapes, beyond anything in the suite.** Blocked (fail-closed):
  answer-then-`os._exit(1)`, answer-then-**SIGKILL** (so the check survives an unclean death, not
  just a tidy `SystemExit`), answer on **fd 3** only, trailing whitespace (`"NO "`), **CRLF** line
  endings, exit-0-with-no-output, junk line before the answer. Correctly allowed: answer plus
  stderr noise; answer without reading stdin (a **SIGPIPE** on the hook's `printf` does not corrupt
  the status, as predicted).
- **The main agent's RUN 2 item-5 measurement is correct — I confirm it, no correction needed.**
  `classify-pr-command.py:95` uses exact equality; `MERGE_EXEMPT=x gh pr create` classifies `PR`
  with an empty reason, so it **blocks**. It was a coverage gap, not a live bypass. RUN 2's
  parenthetical read stronger than the facts; RUN 3 does not inherit it.

## What could go wrong / what I'm unsure about

**No live defect in this diff.** All of the below is residual risk, in severity order.

1. **`0:PR|0:NO` is not a third variant of the same mistake — but it does not close the whole
   class, and the ADR's deferral list is missing one member.** Of my 12 probes, **two** still pass
   silently: a **hang** (documented as deferred) and an **always-`NO` stub that exits 0** (measured
   at this HEAD: **ALLOW, gate open, 64 tests still green**). RUN 2 named that stub explicitly as
   one of three proved shapes; two of the three were closed this round, and the ADR now says
   "**Two** failure modes are knowingly deferred" — listing the hang and first arming, **not** the
   stub. A reader takes that sentence as the complete residual set, and it isn't. This is the one
   place the amended ADR **overclaims**, by omission rather than assertion. Mitigating: RUN 2's
   verdict file, which names the stub, is committed in the same directory, so the record exists —
   it just isn't consolidated where a future reader will look. Fixing the *behaviour* needs a
   different mechanism entirely (a canary — feed the classifier a known `gh pr create` and require
   `PR`), which costs a second interpreter launch on every Bash call; deferring that is reasonable.
   **Naming it in the ADR costs one sentence and should not have been dropped.**
2. **First arming: I confirmed the exposure and it is sharper than "untested".** The registered hook
   is `$HOME/.claude/hooks/judge-guard.sh` — the *primary* checkout's working file, currently on
   `feat/pane-split-policy`, **pre-extraction** (0 occurrences of `CLASSIFIER`, no `lib/`) and
   **pre-PR-#32** (it hardcodes `$HOME/.claude/coding-memory/…/verdicts.jsonl`). So the gate that
   will actually judge this PR is **not the code being judged**. Concretely, I dry-ran both hooks
   against a `gh pr create` payload from this worktree: both exit 2 today. After this verdict lands
   in the *worktree's* store, the branch hook will pass and **the live hook will still block** — it
   reads the primary checkout's store, which is dated Jul 27 and contains **0** `jg-failclosed`
   entries. The live gate cannot ever match this branch. **That is the risk: the operator hits a
   block that looks like "judge not run", reaches for `JUDGE_EXEMPT`, and ships the fail-closed
   branch through a bypassed gate.** An `VAR=x` env prefix cannot fix it either — the hook is a
   separate process and never sees the prefix (the ADR says so itself).
3. **Blast radius is unchanged and machine-wide.** By design, an unusable classifier blocks *every*
   Bash command in *every* repo for *every* concurrent agent. Documented and accepted, but it is
   why item 2 is not academic: the first arming of this code is the moment that trade is cashed,
   and it has never been rehearsed. Consequence high, probability low, no written smoke test.
4. **The hang is real and I re-measured it: 5-second watchdog, killed, no message, no timeout.**
   Honestly deferred in the ADR, and the ADR is candid that its own "loud, self-describing halt"
   promise does not cover this shape. Proportionate deferral — a timeout is genuinely larger than
   the remaining scope.
5. **Carried coverage gap: the exempt-value newline normalisation is still unpinned.** I removed
   `val.replace("\n", " ")` and the suite stayed **51/0**. I checked the direction before rating it:
   dropping it makes the hook *stricter* (a leading-newline reason yields an empty line 2 → blocks),
   so it is cosmetic-to-fail-closed, not a bypass. Low.
6. **`CODING_MEMORY.md`: 1356 lines against the 200-line cap on its own line 3, +24 this round.**
   Judged as a decision, as asked. **The deferral is honest and proportionate** — it is recorded in
   the file *and* the reason is recorded, the trim is scheduled as its own branch, and a drive-by
   consolidation mid-branch would be exactly the "fix only the root cause" violation this repo
   enforces elsewhere. **On leaving the stale "778" uncorrected: I think the call is defensible, but
   only because of what surrounds it.** The file now says, in the file, that the number is
   known-wrong and stale by ~550. A wrong number *plus* a loud adjacent correction cannot mislead a
   reader; a silently-patched number in a file 6.7× its cap would have. If that surrounding sentence
   is ever dropped, the number becomes a real defect. Seventh consecutive verdict to flag the size.
7. **Minor:** the fail-closed block is now ~14 lines of comment above an 8-line `case`. The prose is
   good and earns most of its space, but two of those paragraphs now say the same thing in three
   places (hook comment, test comment, ADR). Watch it in round 4.

## Trajectory — scored honestly, as requested

**Converging, not thrashing — but the recurrence has a structural cause worth naming.**

The evidence for converging: the check has gotten *smaller and more general* each round (file
exists → output is well-formed → output is well-formed **and** the process succeeded), each round
was red-then-green in separate commits, each round's claim was re-measured before being written
down (including this round correcting RUN 2's own overstatement), and the accepted-open set is
written into an ADR rather than left in a head. Three rounds of a judge finding one more layer is
what a working review loop *looks like*; a patched symptom would show the check growing extra
special cases, and this one shrank.

The uncomfortable part: the reason the same class kept reappearing is not the check's logic, it is
the hook's **dependency shape**. Every Bash command's fate depends on the health of one Python file,
so *every* health-check bug is automatically machine-wide, and "is the helper healthy?" is only ever
answerable by proxy — existence, then shape, then status, and the next proxy after that is a canary.
A two-tier design (a coarse, dependency-free bash tripwire that only consults the classifier when
the command plausibly mentions `gh … pr … create`) would collapse the blast radius from "every
command in every repo" to "commands that look like PR commands", and would make the hang harmless
for everything else. That is an architecture trade-off, which is human-owned — **I name it, I do not
decide it, and it is not a reason to hold this branch.** The branch is a correct local fix; the
observation is about what round 4 should be *about*.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | Closes RUN 2's severity-1 item exactly, and nothing beyond it. |
| `execution` | pass | 64/0 and 51/0 re-run by me; 3 mutants caught with precise failure counts; `$?` mechanism verified empirically (rc=7); 12 extra shapes probed. |
| `trajectory` | pass | Red/green separated and replay-verified; RUN 2's own overstatement measured and corrected rather than inherited. Structural caveat above. |
| `regression` | pass | 9 lines of hook change; no other consumer of the classifier; no new deps; shellcheck clean but for pre-existing SC2181. |
| `context_budget` | concern | `CODING_MEMORY.md` 1356 lines vs its stated 200 cap, +24 this delta; deferral is ruled and recorded, trend still wrong. |
| `traceability` | pass | ADR + memory + verdict files explain the *why*, not just the *what*. |
| `success_masking` | concern | 64 green tests coexist with 2 of 12 probed shapes passing silently: an always-`NO` stub (ALLOW) and a hang (silent, indefinite, machine-wide). |
| `intent_drift` | pass | Delta touches only the hook, its tests, the classifier test, ADR 0012, memory, and the verdict store. |
| `checkpoint` | pass | `b095c0a` tests-only (replayed red), `b095c0a`→`1d3b4ed` clean revert points, worktree clean. |
| `audit_trail` | pass | Amended ADR is attributable and ADR-worthy; the one gap is the missing third deferral (item 1). |

## Concerns

- ADR 0012's "**Two** failure modes are knowingly deferred" is incomplete: an always-`NO` classifier
  stub that exits 0 still ALLOWs silently (re-measured at this HEAD), and RUN 2 named it. One
  sentence, not one line of code.
- First arming is not merely untested — the live registered hook is pre-extraction *and*
  pre-PR-#32, reads a store with 0 matching entries, and will block this very PR for a **path**
  reason that looks like a freshness reason, inviting a `JUDGE_EXEMPT` bypass on the fail-closed
  branch itself.
- No timeout: a hung classifier blocks every Bash command indefinitely with no message (re-measured).
- `CODING_MEMORY.md` at 1356/200 lines, grew again this round; stale self-measurement deliberately
  left, flagged loudly in-file (which is what makes it acceptable).
- Exempt-value newline normalisation remains unpinned (51/0 with it removed); direction verified as
  fail-closed, so low severity.
