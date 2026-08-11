# Observability verdict — git-guard detached HEAD (architecting, round 6)

- **repo:** memsearch-freshness
- **branch:** `HEAD` (detached worktree at `/Users/marksuyat/.claude/memsearch-freshness`)
- **head_sha:** `0819db75229b2b31a98a080b3edf56bef5720603`
- **stage:** architecting — advisory, non-blocking
- **spec:** `docs/features/git-guard-detached-head.md`, blob `240f345dc0f2a8fbf75eeb989354cd35b791163a` (609 lines)
- **ts:** 2026-08-11T02:40:11Z
- **risk:** medium · **confidence:** high

---

## What was changed

A safety hook currently asks "which branch am I on?" with a question that answers `HEAD` when there
is no branch. It reads that as "not main", shrugs, and lets the commit through. This design swaps in a
question that either names a branch or admits it can't — and when it can't, the guard now refuses
instead of waving you past. Think of a bouncer who only checks IDs from people who hand one over:
the fix is to stop letting the ID-less walk in, while still letting through the people the bouncer
already knows are mid-way through something (a rebase, a merge) that git itself is waiting on.

## Does it do what you wanted?

Yes, and the reasoning is unusually well evidenced for a design doc. I rebuilt the proposed hook and
re-ran the three fence rows myself: a rebase from `main` (exit 0 today → **2**), a `rebase --apply`
from `master` (0 → **2**, head-name reads `refs/heads/master` exactly as claimed), and a named `main`
mid-merge (2 → 2). I also built the "messages before logic" step in isolation and ran the existing
suite against it: **77 passed, 0 failed** — the reordering you made this round is genuinely
behaviour-neutral, as advertised.

## What could go wrong / what I'm unsure about

**Yes, there is a fifth mutation, and it is the worst one yet.** You closed `master` in the *fence*
last round. The same word is missing a test in the *primary* check — the line this change rewrites by
hand:

```bash
case "$b" in
  main|master) return 0 ;;   # <- delete `master` here
```

I built that mutant and measured it:

| | named `master`, source staged | named `master`, `--force-with-lease` | existing suite | rows 15/16/17 |
|---|---|---|---|---|
| original hook | 2 | 2 | 77/0 | — |
| spec's hook | 2 | 2 | — | 2 / 2 / 2 |
| **`master`-dropped mutant** | **0** | **0** | **77 passed, 0 failed** | **2 / 2 / 2 — all pass** |

A source commit walks onto `master`, the force-push guard stops existing, and every one of the 94
cases (77 existing + your 17) reports green. Row 17 doesn't catch it because its checkout is
*detached* — `master` only ever appears there inside `head-name`, so `case "$b"` is never exercised
with `b=master` anywhere in the suite. Your own note that `grep -c master hooks/git-guard.test.sh`
returns 0 is the tell; row 17 half-closed it. **Fix is one line plus one row:** `git -C "$REPO" branch
master` in the harness setup, then row 18 — `on_branch master`, source staged, exit 2 before *and*
after.

**Three operability states still have no usable remedy** (you asked me to walk them all):

1. **Plain detached HEAD, no operation running — the headline refusal of this entire spec (rows 1 and
   2) — has no row in the four-row remedy table.** The table covers named main/master ±sequencer,
   detached-mid-rebase-to-main, and not-a-repo. The most common new refusal is the one left to the
   implementer, in the same section that says the remedy is "specified per state rather than left to
   the implementer". Measured: `git switch -c rescue` from a plain detached HEAD works and keeps the
   file staged, so the true text exists — it just isn't written down.
2. **The mid-rebase remedy hands the operator into state 1.** Measured: `git rebase --quit` from the
   row-15 state leaves HEAD **still detached** with the work staged, and the very next `git commit`
   is refused again (exit 2). Refuse → follow the advice → refuse, with no remedy the second time.
   The row-3 text needs `git rebase --quit`, *then* `git switch -c <name>`.
3. **The remedy table is written in commit language and then handed to Guard 2.** "Guard 2 … uses the
   same table" emits, verbatim, for a *push*: "or stage only documentation"; "Let the rebase make
   this **commit**"; "git-guard cannot judge **a commit** from here" — that last one in exactly the
   state the "Leased force-push from a non-repository directory" scenario builds.

**The most likely thing to actually go wrong is a false green in the harness.** `run_case` hardcodes
`( cd "$REPO" && … )` (`hooks/git-guard.test.sh:55`). Rows 3 and 4 need a cwd that is *not* a
repository; rows 5 and 7 need a *different* repository (unborn branch — `$REPO` already has a commit).
No "state helper" can change where `run_case` cds, yet the spec tells the implementer the helpers
"already exist" and lists "a non-repository cwd" among the helpers. The predictable outcome: the row
runs inside `$REPO` on whatever branch was last checked out, and if that's `main` with source staged
it **exits 2 and reports a pass for entirely the wrong reason**. Specify `run_case_in <dir> …` (or a
`CWD` variable defaulting to `$REPO`) in step 3.

**The message contract is never proven able to fail.** Exit codes get must-fail evidence (step 4 red →
step 6 green). The stderr assertions land in step 7, *after* step 5 wrote the messages, so no
assertion is ever observed failing. Two rounds of judging went into that wording and nothing tests the
test. One sentence in step 7 fixes it: revert one `printf` and confirm the matching assertion fails.

Smaller, but real: the **empty-index message** has exact replacement text, is recorded in the cost
matrix as 0 → 2, and has **no row** among the 17 (carried from round 4). The **bare-force message**
(`git-guard.sh:143`) still says "Use --force-with-lease instead (still blocked while main/master is
checked out)" — from a detached HEAD that advice is now a two-step dead end, and that line appears in
neither table despite the section opening with "Four stderr paths". And the document **still miscounts
its own lists**: "Three constraints on that table" is followed by four bullets; "Four stderr paths" by
a three-row table. That is the same species as last round's 16-vs-17, and the reader is a lower-tier
model that will trust the number over the list.

## What I'd double-check before merging

1. Add row 18 (named `master`, source staged, 2 → 2) and `git -C "$REPO" branch master`. Non-optional
   in my view — it is the only thing standing between a hand-retyped `case` and a dead Tier-1 guard.
2. Add the fifth remedy row (plain detached HEAD), amend row 3 to chain `--quit` → `switch -c`, and
   give Guard 2 push-shaped wording instead of the commit table verbatim.
3. Specify how a test case runs in a cwd other than `$REPO`, or rows 3/4/5/7 are untrustworthy.
4. Add the "revert a printf, confirm the assertion fails" line to step 7, and one row for the
   empty-index detached message.
5. Checklist step 2 lands the planning scripts under `hooks/`. Round 4 recorded that they hardcode
   `REPO=/Users/marksuyat/.claude/memsearch-freshness`; committing that violates the no-absolute-paths
   invariant. **I could not verify this — the scripts are not in this repository.** Say explicitly in
   step 2 that paths must be derived, and whether anything runs them once landed.
6. Fix the two self-counts.

## Positive evidence I ran (so it isn't re-litigated)

- Step 5 messages-before-logic built and executed: **77 passed, 0 failed**, renders
  `the checkout is branch 'main'` correctly. The reorder is sound.
- Rows 15 / 16 / 17 reproduce exactly as the spec states, including `head-name` = `refs/heads/master`.
- `git rev-parse --git-path` returns a **relative** path (`.git/rebase-apply`; `../../.git/…` from a
  subdirectory) and the guard still resolves the marker from a subdirectory cwd — exit 2. No hidden
  cwd dependency in the carve-out.
- The two-loops arrangement (`rebase_head_name` vs `sequencer_in_progress`) is adequately fenced:
  rows 15 and 17 assert the *stderr* string, so dropping a marker from the message loop alone fails
  row 17 — **provided** the stderr assertions actually get written (see step 7 above).
- Partial application of step 6 fails **closed**: with `on_main`'s `case` landed but
  `sequencer_in_progress` missing, the call returns 127, `&& return 1` short-circuits, `return 0`
  runs, and the guard engages. No intermediate checklist state is weaker than `main`. (Reasoned from
  the code shape plus the `set -u`-only header at `git-guard.sh:42`; not separately executed.)
- Honesty note on my own method: my first row-17 probe reported "all three exit 0" because a
  `$(basename …)` inside the reporting string overwrote `$?`. Every number above was re-measured with
  the exit code captured first.

## Dimensions

| Dimension | Verdict | Why |
|---|---|---|
| intent | pass | Fixes the named defect at both call sites; carve-out is principled and class-shaped, not instance-shaped. |
| execution | concern | Fifth mutation untested; rows 3/4/5/7 cannot be expressed with the helper the spec points at; empty-index cell has exact text and no row. |
| trajectory | pass | Six rounds of measured reasoning, each finding reproduced before adoption, two explicit self-corrections stated at true size. Sound, not lucky. |
| regression | concern | Dropping `master` from `on_main` disables both Tier-1 guards on a `master` trunk and passes all 94 cases — measured. |
| context_budget | pass | A `docs/features/` spec, loaded on demand; the `rules/gates.md` edit is two stub sentences. |
| traceability | concern | Measurement scripts still absent from the repo (no table is auditable by a second reader yet); two self-counts misdescribe the document. |
| success_masking | concern | 94 green under a guard-disabling mutant; stderr assertions written after the code with no must-fail evidence; `run_case`'s fixed cwd can pass a non-repo row from inside a repo. |
| intent_drift | pass | "Out of scope — do not widen" is explicit and held; the one adjacent edit (`rules/gates.md`) is required because this change falsifies it. |
| checkpoint | pass | Stepwise, independently revertible, every intermediate state fails closed; step 5's neutrality verified by execution. |
| audit_trail | pass | ADR 0026 specified with content including the five-command residual hole by name; gates.md falsification located by quoted text; judge-guard verdict timing noted. |

**risk = medium · confidence = high**
