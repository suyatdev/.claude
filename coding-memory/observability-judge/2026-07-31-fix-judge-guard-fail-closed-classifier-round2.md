# Observability judge — RUN 2 · `fix/judge-guard-fail-closed-classifier`

- **repo:** `jg-failclosed` (worktree `~/.claude/.claude/worktrees/jg-failclosed`)
- **branch:** `fix/judge-guard-fail-closed-classifier`
- **head_sha:** `59a89634a724d2b7effeb1da814573accda71ebc`
- **stage:** implementation
- **base:** `origin/main` = `2b8564b` · **delta judged:** `bd2621c..HEAD` (RUN 1 → now)
- **ts:** 2026-07-31T16:30:05Z
- **risk:** medium · **confidence:** high

> Filed as `-round2` rather than overwriting `2026-07-31-fix-judge-guard-fail-closed-classifier.md`,
> which holds RUN 1 and was committed at `59a8963`. Overwriting it would erase the audit trail this
> branch exists to protect; `-roundN` is the established convention in this directory.

---

## What was changed

Imagine a bouncer whose job is to check IDs at the door. Last round we found the bouncer had a rule
that said "if my ID scanner is *missing*, refuse everyone." Sensible. But if the scanner was
*present and broken* — unplugged, cracked screen, jammed — the bouncer waved everyone through
without a word. That is the exact opposite of the one thing the bouncer exists to do.

This round replaces "is the scanner *there*?" with "did the scanner *give me an answer*?" The
scanner can only ever say one of two words, `PR` or `NO`. Anything else — silence, gibberish, a
half-sentence — now means "I could not check," and everyone is refused until the scanner is fixed.

The new rule is **shorter than the one it replaced**. The complete fix deleted a special case
instead of adding one. Three commits: tests first that failed (`df1918e`), then the fix that turned
them green (`ec1fa1c`), then the paperwork (`59a8963`).

## Does it do what you wanted?

Yes. This is a clean delta, and I want to say that plainly rather than manufacture a finding.

I re-ran both suites myself at `59a8963`: **62 passed / 0 failed** and **50 passed / 0 failed**,
matching the dispatch note exactly. Then I tried to break it:

- **I mutated the fix four ways.** Making it fail open again → 6 tests fail. Changing the exit code
  from 2 to 1 → 6 tests fail. Making it also block the normal "not a PR command" case → 11 tests
  fail. Deleting the repair-instructions line from the message → **exactly 1** test fails. These
  assertions pin real behaviour; they are not restating the code.
- **I invented five output shapes the tests do not cover** — a blank first line, a warning printed
  before the answer, `PR ` with a trailing space, a byte-order mark, and the classifier replaced by
  a directory. **All five block.** The new rule is genuinely more complete than the old one, not a
  differently-shaped guess.
- The repair-route test greps case-insensitively for `write tool|unregister`. That is a weak
  coupling — it pins that a keyword is present, not that the route works. But mutation M4 shows it
  is load-bearing and precisely targeted (one failure, no collateral), and no text assertion can do
  better without pinning the whole sentence and becoming brittle. **Proportionate, not too weak.**
- The rejected bypass variable is **correctly** rejected. I verified the mechanism claim: the hook
  receives the command as a *string* in a separate process, so a `VAR=x` prefix genuinely never
  reaches its environment. That is not a rationalisation; it is why the classifier has to parse
  `JUDGE_EXEMPT` out of the string itself in the first place.

RUN 1 raised eight substantive findings. Four are closed outright (the fail-open check, the
blast-radius understatement in the ADR, the dead-end repair message, the unpinned adjacency
property). The rest are carried, and named below.

## What could go wrong / what I'm unsure about

**Nothing here is a live defect. All of it is residual risk.** In severity order:

1. **The new rule checks the answer's *shape*, not whether the scanner actually worked.** I proved
   three shapes that still pass silently: a classifier that prints `NO` then exits non-zero, one
   that prints `NO` then crashes, and a two-line stub that always says `NO`. All three → **exit 0,
   gate silently disarmed, 62 tests still green.** Today this is unreachable, because the real
   classifier writes its answer as its very last act. But that safety comes from the *current
   classifier's shape*, not from the hook — a future refactor that emits a default early, or a bad
   merge leaving a stub, re-opens the exact defect this branch exists to close. Checking the
   classifier's exit status is roughly one line and would make the invariant structural instead of
   incidental.
2. **First arming is still untested, and the stakes went up this round.** I confirmed the live
   registered hook at `~/.claude/hooks/judge-guard.sh` is pre-PR-#32 and `~/.claude/hooks/lib/` does
   not exist. The framing "out of scope for this branch" is **honest** — the diff cannot fix an
   installation — but it is *incomplete*, because this branch strictly widens what a bad arming
   costs. Mitigating facts I verified: `origin/main` already carries
   `hooks/lib/classify-pr-command.py` (PR #32 is merged), git writes files by atomic rename so a
   branch switch has no torn window, and only Claude's Bash tool is gated — a human's own terminal
   still works. Net: low probability, high consequence, no written arming check anywhere.
3. **A hung classifier hangs every Bash call forever, silently.** Measured: I gave it a classifier
   that sleeps, and the hook waited indefinitely with no message. The ADR promises "a loud,
   self-describing halt recoverable in seconds"; this one shape is neither loud nor
   self-describing. Low probability, partly pre-existing (the payload parser has no timeout either).
4. **`CODING_MEMORY.md` is 1332 lines against the 200-line ceiling stated on its own line 3**, and
   grew again this round (1267 → 1332 across the branch, +16 in this delta). Its own self-flag at
   line 904 still reads *"This index is 778 lines"* — now wrong by 554 lines. I will not soften
   this because the growth is documentation: an index 6.7× its own cap, carrying a stale
   self-measurement, is a record-keeping failure by the exact standard this branch spends three
   commits enforcing on a shell script. **The branch does not practise what it preaches.** This is
   at least the sixth verdict to say so.
5. **Two of the three unpinned classifier properties RUN 1 named are still unpinned.** Adjacency got
   its two cases (I confirmed: dropping adjacency now fails 2 tests). But I mutated
   `name == "JUDGE_EXEMPT"` to `name.endswith("EXEMPT")` — **50/0, escapes** — which would let
   `MERGE_EXEMPT=x gh pr create` silently claim a judge exemption. And dropping the exempt-value
   newline normalisation also escapes at 50/0. Coverage gaps, not live bugs.
6. **The safety-gate / momentum-guardrail contradiction is unmoved.** `judge-guard.sh:10` declares a
   *safety gate* that fails CLOSED on any inability to verify; `classify-pr-command.py:67,77`
   justify fail-OPEN because it is a *momentum guardrail*. Same subsystem, opposite defaults, still
   no written deciding rule. Sharper now: the classifier's `except ValueError: return ("NO", "")` is
   a deliberate silent fail-open that the new `case` **cannot** catch, because `NO` is a valid
   answer. This round hardened one half of the contradiction and left the other untouched.
7. **`sudo gh pr create` and `xargs gh pr create` remain undocumented** in ADR 0012's enumerated
   accepted-open set (grep: 0 hits). Carried from RUN 1, unchanged; the ADR's general
   "not exhaustive" disclaimer still stands.

## What I'd double-check before merging

1. **Have an arming check, even if it is one line in the PR body.** After the merge lands in the
   primary `~/.claude` checkout, run
   `printf '%s' '{"tool_input":{"command":"gh pr create"}}' | bash ~/.claude/hooks/judge-guard.sh; echo $?`
   and confirm it is `2` **with a readable message**, not a silent `0` or a hang. Thirty seconds
   retires most of concern #2.
2. **Decide on the one-line exit-status check** (concern #1) — take it now or write it down as
   knowingly deferred. Leaving it undecided is what turns an incidental invariant into the next
   round's finding.
3. **Confirm the block message actually reaches you.** The whole recovery plan is "the operator
   reads the message and uses the Write tool." That has never been observed under the real harness.
   If a PreToolUse denial renders somewhere you would not look, the mitigation is theoretical.
4. **Trim `CODING_MEMORY.md`, or amend line 3 to the real policy.** One or the other. A cap that has
   been violated by 6.7× for six verdicts is not a cap, and the stale "778 lines" self-flag actively
   misleads the next reader.

---

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | Addressed RUN 1's finding exactly, including adopting the *smaller* general fix it recommended; reproduced independently before acting. |
| `execution` | pass | 62/0 and 50/0 re-run by me. 4 hook mutants all caught (6/6/11/1 failures). 5 extra output shapes I invented all block. shellcheck: only pre-existing SC2181/SC2016. |
| `trajectory` | pass | Genuine red (5 failing) → green → docs. Chose the general fix over patching the special case. ADR frames it as a correction, not a clean result. Adjacency cases disclosed as green-on-arrival. Reasoning, not luck. |
| `regression` | pass | Confined to `judge-guard.sh` + its two suites + docs. No other file references the classifier. The `NO` allow-path is unchanged and pinned by 11 tests. No deps. Worktree clean. |
| `context_budget` | **concern** | `CODING_MEMORY.md` 1332 lines vs its own stated 200-line cap; grew again this round; its own self-flag stale by 554 lines. Repeat, unmoved. |
| `traceability` | pass | ADR 0012 updated in place, records the correction, the machine-wide blast radius, and the rejected bypass with its mechanism. Commit messages accurate. Repair-route grep is weak but load-bearing. |
| `success_masking` | **concern** | 62/0 green while `NO`-then-crash and always-`NO`-stub classifiers still pass silently (proved). Output-shape validation ≠ correctness validation, and the invariant is upheld by the classifier's shape, not the hook. Plus no timeout: a hung classifier blocks everything with no message, contradicting the ADR's "loud, self-describing halt." |
| `intent_drift` | pass | Delta is exactly the RUN 1 finding plus its paperwork. The +2 classifier cases are declared in the commit as green-on-arrival — adjacent scope, disclosed, not smuggled. No drive-bys, no deps. |
| `checkpoint` | pass | Clean red → green → docs sequence; `git revert ec1fa1c` restores the prior check cleanly. Worktree clean at HEAD. |
| `audit_trail` | pass | ADR + `CODING_MEMORY` + RUN 1 verdict persisted; the correction is attributed to the judge run that found it and says so in the ADR. |

## Concerns

1. Output-shape validation only: a classifier printing `NO` then crashing, or an always-`NO` stub,
   still exits 0 silently (3 shapes proved at this HEAD); the fix's invariant is upheld by the
   current classifier's shape, not structurally — an exit-status check is ~1 line.
2. First arming untested and now higher-consequence; live `~/.claude/hooks/` is pre-PR-#32 with no
   `lib/`; no smoke test written anywhere. Framing as out-of-scope is honest but incomplete.
3. No timeout on the classifier: a hung one blocks every Bash call indefinitely with no message,
   contradicting the ADR's "loud, self-describing halt" (measured; partly pre-existing).
4. `CODING_MEMORY.md` 1332 lines vs its own 200-line cap, grew again this round, self-flag at line
   904 stale by 554 lines — sixth-ish verdict to flag it, unmoved.
5. Two of three RUN 1-named unpinned classifier properties remain unpinned: `JUDGE_EXEMPT` name
   equality (`endswith("EXEMPT")` escapes 50/0 → `MERGE_EXEMPT=x` would wrongly exempt) and
   exempt-value newline normalisation.
6. Safety-gate vs momentum-guardrail contradiction unmoved; the classifier's `except ValueError ->
   ("NO","")` is a silent fail-open the new `case` structurally cannot catch.
7. `sudo gh pr create` / `xargs gh pr create` still absent from ADR 0012's accepted-open set.
8. Repair-route assertion is a case-insensitive keyword grep — proportionate and load-bearing
   (mutation M4 → exactly 1 failure), but it pins wording, not that the route works.
9. Verified by me at this HEAD: suites 62/0 and 50/0; 4 hook mutants + 3 classifier mutants run;
   9 classifier output shapes probed directly; shellcheck baseline unchanged; `origin/main` confirmed
   to carry `hooks/lib/`; PR #32 confirmed merged; worktree clean; no new dependencies.
