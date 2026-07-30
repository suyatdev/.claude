# Observability judge — implementation — feat/pane-split-policy — RUN 4

**ts:** 2026-07-27T22:54:07Z · **repo:** `.claude` · **branch:** `feat/pane-split-policy`
**head_sha:** `e6e2e3e52a195114b38339ed5497231c58db5d03` · **base:** `main` (merge-base `7854ae3`)
**stage:** implementation (gates the PR) · **risk:** medium · **confidence:** high

Supersedes RUN 3 (`2454d1d`, `...-round3.md`) and RUNS 1–2 (`2026-07-24-feat-pane-split-policy.md`).
Subject of this run: `cbc3c4e` (+10 assertions), `5cee1e8` (record corrections), `e6e2e3e` (memory).

Verified myself, nothing taken on report: all 7 suites re-run (`45/81/34/113/10/9/34` = **326 passed,
0 failed** — the controller's number confirmed exactly); dispatcher suite run 3× for flake, stable;
`shellcheck -x` rc=0 on the dispatcher, its suite and the guard; the `86a1974..HEAD` diff read; the
spec blob confirmed still `cdc777a`; **three mutants applied to the shipped dispatcher by me**; and
**five independent repros against the shipped dispatcher with a fake adapter**, including an
exhaustive 81-configuration sweep and a re-implementation of the change RUN 3 asked for.

## What was changed

Nothing that runs. The dispatcher's only source delta since RUN 3 is comment — I checked, and there
is not one non-comment changed line in `panes/dispatch-pane-agent.sh`. What changed is the *written
record* (one of my three prior findings accepted and corrected in three places, two rejected with
evidence) and the *tests* (+10 assertions pinning the property I said nothing covered).

Analogy: last round I filed three bug reports about a machine. The team fixed one, and for the other
two came back with the machine's blueprints and a bench test showing my rig had the parts installed
backwards. I rebuilt their bench test from scratch. They're right.

## Adjudicating my own RUN 3 findings

**F1 — I was right, and the correction is accurate.** Verified twice over: `grep` confirms
`hooks/pane-dispatch-guard.sh:105` is the only reader of `adapter-failed-<sid>` and the dispatcher
holds two writes and no read; and my repro reproduces the corrected comment *to the digit* — `max=2`,
a tab-incapable adapter, 10 direct dispatches → **6 real panes, cooldown at d7, panes still opened at
d8 and d10**. ADR 0009, the `TAB_FAIL_LIMIT` comment and the branch log now all say the bound is
emergent (the guard stops routing work here), not mechanical, and that a direct dispatch is
unbounded. The requested "declared timing deviation, not compliance" sentence is in ADR 0009 and the
branch log, and the spec is correctly still locked at `cdc777a`.

**F2/F3 — the rejection is correct, and my RUN 3 finding was substantially wrong.** I did not take
the glob-order argument on report; I tested it.

1. `date +%s` is 10 digits; a bash glob over `<epoch>-<pid>-<random>` dirs sorts by epoch first in
   both the default locale and `LC_ALL=C`. Glob order **is** creation order. A letter-prefixed
   fixture name (`GHOST1`) sorts *after* every epoch-named dir — which is exactly how my RUN 3
   fixtures inverted production ordering without my noticing.
2. Re-running my own restart repro under both namings, with a healthy adapter that tabs into anything
   still alive, `max=3`, 12 dispatches:

   | ghost run-dir order | HEAD (advance at selection) | my RUN 3 proposal (advance on success only) |
   |---|---|---|
   | ghosts sort **last** (my RUN 3 fixtures) | cooldown @ d5 — my F2 trace, reproduced | no cooldown |
   | ghosts sort **first** (a real restart) | **no cooldown**, self-heals | **cooldown @ d5** |

3. Then the part neither side had done — an **exhaustive sweep**, since "a hand-closed pane" and
   "interleaved ghosts" were the cases I was told to check. Every ghost/healthy layout at `max=3` and
   `max=4` (all 2^N−1 masks) × every starting round-robin index, production naming, 12 dispatches,
   81 configurations per variant:

   | variant | spurious cooldowns on a **healthy** adapter |
   |---|---|
   | HEAD (advance at selection) | **2 / 81** |
   | my RUN 3 proposal | **8 / 81** |

The proposed fix is four times worse in the ordering production actually produces. The mechanism the
rebuttal gives is the right one and I confirmed it: retiring a ghost frees a slot, the next dispatch
opens a real pane, that pane sorts *last*, and only an advancing cursor ever reaches it to clear the
streak. **RUN 3's F2 was a fixture artifact and F3's counterfactual was measuring the artifact. The
advance is load-bearing; leaving it alone and pinning it by test is the correct call.**

## What could go wrong / what I'm unsure about

**F4 (new, mine, verified by repro) — the corrected record still contains one unqualified claim that
is false, and it is the same shape as the one it just corrected.** `dispatch-pane-agent.sh:53-55` and
the matching branch-log bullet say "3 does tolerate the benign multi-stale case (panes closed by
hand, a cmux restart)". Unqualified. It holds at N=3 — I swept 12 starting rr indices there and HEAD
never cools down, so the new test pins a genuinely robust property. It stops holding above that.
Full-restart, healthy adapter, production naming, spurious cooldowns by starting index:

| max=N | HEAD | my RUN 3 proposal |
|---|---|---|
| 3 | 0 / 3 | 1 / 3 |
| 4 | **1 / 4** | 3 / 4 |
| 5 | **2 / 5** | 5 / 5 |
| 6 | **4 / 6** | 6 / 6 |

`set-policy panes --max` accepts 1..16 and the skill documents that range, so N≥4 is supported, not
exotic. The persisted `pane-rr-<sid>` index survives a cmux restart (state is only swept at 7 days),
so "unlucky index" is an ordinary mid-session state. Concretely: `max=4`, four panes lost to a
restart, rr index at 3 → three ghost hits in a row → **exit 4, "adapter 'cmux' failed 3 consecutive
open_tab calls", session-wide cooldown, the user's `panes max=4` silently discarded — on a perfectly
healthy cmux.** So my RUN 3 *conclusion* ("stale panes can declare a healthy adapter tab-incapable")
survives; only my diagnosis and proposed fix were wrong. HEAD is the best of the two designs and
still not immune, and nothing in the record says so.

**F5 (precision, minor).** The branch log says my fixtures "sorted the ghosts last, which cannot
happen in production." Ghosts-last *is* producible — close the two newest panes by hand and the
survivors are older. What genuinely cannot happen is a *newly opened* pane sorting before an older
ghost, which is what the argument needs and what makes it correct. As written a reader can take away
"stale panes are always at the front of the live list," which is false; my `HGGG` and `GHGG` sweep
rows are exactly that layout, and one of HEAD's two failing configurations is `GHGG`.

**Success-masking, mild but real.** The new restart assertions are set at `max=3` — the one value at
which the documented tolerance holds for every rr index. At `max=4` the same scenario fails and no
assertion anywhere covers it. Green stays green while the comment above the constant is wrong.

**What genuinely improved, verified not taken on report.** This is the strongest round on the branch
and the rebuttal is a model of how to answer a judge: a mechanism-level argument, a counterfactual
implementation, and a test that makes the rejected change fail loudly. I re-ran the mutants myself on
a copy of the tree — `-ge`→`-gt` on the overflow gate gives **96/17** (their number exactly), and
applying my own RUN 3 fix gives **111/2**, killing precisely the two restart assertions and nothing
else. My third check (making the dispatcher honor its own cooldown flag) gave 109/4 against their
claimed 108/5; the gap is my mutant sitting one block earlier than theirs, not a discrepancy — the F1
boundary assertion dies either way. RUN 3's structural complaint is closed: `panes max=2` bounding
real `open_pane` calls is now asserted directly, which is the property nothing covered for two
rounds. The true-positive path is untouched — I confirmed a genuinely tab-incapable adapter at
`max=3` behaves identically under both variants (cooldown @ d8, 5 real panes), so the advance costs
the real detection nothing.

**Carried, declared, and correctly excluded from this run's scope:** the abnormal-pane-death root
cause (no `agent-exit` on a killed pane — `run-pane-agent.sh`'s only EXIT trap cleans temp files)
dissolves F1, F2 and F4 alike and is deferred to a follow-up branch by decision; the ordering
dependence being emergent from a naming convention two functions away; `dispatch-pane-agent.sh` at
517 lines against a 400 soft limit (+25 this round, all comment), split owed as the first move of the
next dispatcher change. Also carried: no live end-to-end run on real cmux (F1/F2/F4 are all the class
a live run catches); skill `description` unverified by measurement; `doc-guard.sh` classifies
`CLAUDE.md` as source; under `inline` a direct dispatch still opens a pane.

Severity, honestly: everything here degrades, nothing blocks or destroys. F4 costs a session its pane
policy and prints a line blaming the wrong component; the flag is a file the user can delete. Medium,
at the low end of it — down from RUN 3 in substance if not in label, because the source is unchanged
and the two findings I filed as bugs turned out not to be.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | Did exactly what the round was for: F1 corrected in all three records, F2/F3 adjudicated on evidence, the missing property asserted. The locked-spec deviation is now declared as a deviation rather than framed as compliance — RUN 3's item 4, closed. |
| `execution` | pass | 326/0 verified by me, 3× stable, `shellcheck -x` rc=0, spec blob unchanged, source delta is comment-only (checked line by line). Two of three mutation claims reproduce exactly on my own copy. |
| `trajectory` | pass | The best reasoning on the branch: a judge finding was rejected only after the mechanism was traced to `new_run_dir`'s naming, the counterfactual was implemented, and the coupling was pinned by test. My exhaustive sweep says they were right by 4×. Docked nothing, but note the argument was verified at N=3 and generalized to all N without checking (see F4). |
| `regression` | pass | No executable line changed. True-positive detection verified identical under both variants. All seven suites green. |
| `context_budget` | pass | Nothing always-on grew this round; the branch's total always-on delta is two rewritten lines in `CLAUDE.md` and `rules/gates.md`. |
| `traceability` | concern | Much improved — F1's mechanism, the ADR consequence and the rebuttal's evidence table are all durable and legible. Residual: the `TAB_FAIL_LIMIT` comment's tolerance claim is false at N≥4 (F4) and the exit-4 message still names the adapter as the culprit in exactly the case where the adapter is healthy. Third round running that the failure needing the most explanation explains itself wrongly — but far narrower now. |
| `success_masking` | concern | The +10 assertions are real, mutation-verified and close RUN 3's structural gap. But the restart test is set at `max=3`, the only N where the property holds for every rr index; the same scenario at `max=4` cools down a healthy adapter and nothing asserts it. |
| `intent_drift` | pass | Comment and test only, every line traceable to a RUN 3 finding. No new deps, no drive-by edits, spec untouched at `cdc777a`. The 517-line file is declared debt with a named next move. |
| `checkpoint` | pass | Three clean, separately revertible commits (tests / record correction / memory). The uncommitted `coding-memory/compliance-judge/` files are another workstream's, pre-existing across all four runs (now six, was four). |
| `audit_trail` | concern | Exceptional in the main: the rebuttal records what was tested, how, and what would falsify it, and the record now corrects itself in place rather than appending. Two residual overstatements of the same kind it just fixed — "3 tolerates a cmux restart" (false at N≥4) and "ghosts sorting last cannot happen in production" (it can; what cannot is a new pane sorting before an old ghost). |

## Concerns

1. **F4 (new, verified by repro and by a 12-index sweep).** `dispatch-pane-agent.sh:53-55` and the
   branch log claim without qualification that a threshold of 3 tolerates a cmux restart. True at
   N=3 (0/3 indices cool down); false above it — N=4: 1/4, N=5: 2/5, N=6: 4/6 spurious cooldowns on a
   *healthy* adapter, with `--max` supported to 16 and the rr index surviving the restart. My RUN 3
   conclusion survives at N≥4 even though my diagnosis and proposed fix were wrong.
2. **F2/F3 rejection ADJUDICATED CORRECT.** Verified independently: glob order is creation order
   (10-digit epoch, both locales); my RUN 3 fixtures inverted it via letter-prefixed names; and an
   exhaustive 81-config sweep gives HEAD 2 spurious cooldowns against the proposed fix's 8. Leaving
   the advance in place and pinning it by test is right; RUN 3 F2/F3 should be treated as withdrawn.
3. **F1 correction verified accurate.** Sole reader confirmed by grep; the "10 dispatches → 6 real
   panes, 2 after the flag" figure reproduced to the digit. Nothing left open here.
4. Test coverage for the restart property exists only at `max=3` — the value where it holds. The
   failing N≥4 case is untested and undocumented.
5. Precision: "ghosts sorting last cannot happen in production" is too strong (hand-closing the
   newest panes produces it); the true, sufficient claim is that a newly opened pane can never sort
   before an older stale one.
6. **ROOT CAUSE still open (declared).** Nothing writes `agent-exit` on abnormal pane death;
   `run-pane-agent.sh`'s only EXIT trap removes temp files. F1, F2 and F4 all dissolve if fixed.
   Deferral to a follow-up branch remains defensible; F4 is one more item on its bill.
7. `panes/dispatch-pane-agent.sh` 410 → 450 → 492 → **517** lines against a 400 soft limit. This
   round's +25 is entirely comment and no executable line changed — verified — but the split is now
   four rounds owed.
8. Carried unchanged: no live end-to-end run of N panes filling and overflowing on real cmux (F1/F2/
   F4 are exactly that class); skill `description` unverified by measurement; `doc-guard.sh`
   classifies `CLAUDE.md` as source; under `inline` a direct dispatch still opens a pane.
