# Observability verdict — git-guard-detached-head (round 5, architecting)

- **Repo:** memsearch-freshness (worktree; branch is detached, reads as `HEAD`)
- **HEAD:** `0819db75229b2b31a98a080b3edf56bef5720603`
- **Spec:** `docs/features/git-guard-detached-head.md` — blob `0eaab98ba1e74056f262af79d05f842ca2afaacf` (**verified**: `git hash-object` matches the SHA supplied)
- **Stage:** architecting — advisory, non-blocking
- **Risk:** medium · **Confidence:** high

## What was changed

Nothing is built yet — this is a plan. The plan fixes a lock on the front door that
quietly stopped locking whenever it could not read the nameplate.

`hooks/git-guard.sh` protects the `main` branch by asking one question: *which branch am
I on?* It asks with `git rev-parse --abbrev-ref HEAD`, and when git cannot name a branch
that command answers with the literal word `HEAD`. The guard compares `HEAD` to `main`,
sees no match, decides "not on main", and steps aside. So the one situation where you
most want the guard awake — a checkout with no branch name — is precisely the one where
it sleeps. The repo's own reflog shows this happening: two commits landed on `main` right
after a `git checkout origin/main`, with the allowlist never consulted.

The plan swaps in a question with only one meaning (`git symbolic-ref --short HEAD`),
which either names the branch or fails — it never answers with a decoy. Silence now means
"I cannot tell", and the guard blocks. One deliberate exception: while git is mid-rebase,
mid-cherry-pick or mid-merge, the guard stands down, because otherwise it strands you in
an operation git is waiting for you to finish. That exception has its own fence — a rebase
that will *move* `main` when it finishes stays guarded.

## Does it do what you wanted?

Yes, at the design level. All four of my round-4 findings were adopted honestly rather than
papered over, and the third bound (row 17) was re-measured by the author rather than
relayed from me. The reasoning is unusually disciplined: the spec repeatedly downgrades its
own earlier claims, marks which numbers were executed versus inferred, and states plainly
that its measurement scripts are not yet committed.

I verified the load-bearing claims myself rather than trusting the document:

| Claim in spec | My measurement | Result |
|---|---|---|
| suite is 77 passing, 0 failing | ran `hooks/git-guard.test.sh` | ✅ `77 passed, 0 failed` |
| `switch -c` refused mid-merge on named `main` | constructed it | ✅ `fatal: cannot switch branch while merging` |
| `switch -c` refused mid-rebase from `main` | constructed it | ✅ `fatal: cannot switch branch while rebasing`, head-name `refs/heads/main` |
| both backends write `head-name` | `rebase --apply` conflict | ✅ `rebase-apply` marker present with head-name |
| `--git-path` usable from a subdirectory | root vs `sub/deeper` | ✅ returns `../../.git/…`, relative to cwd, so `[ -e ]` still resolves |
| non-repo cwd is handled | `git rev-parse --git-path` outside a repo | ✅ exit 128, empty output → `[ -e "" ]` false → fails closed |

**But the design and the instructions have drifted apart.** Round 4's additions landed in
the analysis sections and did *not* propagate to the three artifacts a lower-tier
implementer actually copies from: the checklist, the `checkout_desc` code block, and the
"exact text" message table. See concerns 1–4.

## What could go wrong / what I'm unsure about

### 1. There IS a fourth mutation — `master` (the answer to the question asked)

The head-name fence reads:

```bash
case "$(cat "$dir/head-name" 2>/dev/null)" in
  refs/heads/main|refs/heads/master) return 1 ;;
esac
```

**Delete `|refs/heads/master` and rows 15, 16 and 17 all still pass.** Every one of them
uses `main`. I confirmed the state is real and reachable:

```
$ git init -b master … && git rebase -i HEAD~1     # stopped at an edit step
symref:    []
head-name: [refs/heads/master]
```

That is a branchless HEAD whose rebase will move `master` — the exact hole bound 1 exists
to close — and with the `master` clause dropped it falls straight through to `return 0`,
the guard stands down, and a source commit reaches `master` on `--continue`.

This is not a hypothetical asymmetry: `grep -c master hooks/git-guard.test.sh` returns
**0**. The existing 77-case suite never exercises `master` anywhere, so the `master` half
of `on_main` is unpinned today and the plan adds a *second* master-sensitive site without
pinning either. The spec's claim that "no bound here is prose" is true for `main` and false
for `master`.

**Cheapest fix, adds no rows:** make row 17 a `rebase --apply` from **`master`**. Row 15
then covers merge-backend + `main`, row 17 covers apply-backend + `master`, and a mutation
in either dimension is caught.

Lower-severity siblings: dropping `REVERT_HEAD` or `MERGE_HEAD` from the second loop is
also uncaught (only cherry-pick is pinned, by row 9) — but that direction over-blocks
rather than opening a hole, and the spec already concedes those two are "asserted by
construction, not separately measured".

### 2. The checklist never mentions row 17 — round 4's entire addition is invisible to it

- Step 4: *"Add all **16** matrix rows"* — the matrix has **17**.
- Step 4: *"confirm rows 1–5 and 15 fail while 6–14 and 16 pass"* — omits 17.
- Step 5: *"rows 1–5 and 15 go green, 6–14 and 16 stay green"* — omits 17.
- Step 3's fixture-helper list has **no `rebase --apply` helper** at all.

Meanwhile line 388 correctly says *"Rows 1–5, 15 and 17 are the new behavior"*. An
implementer working the checklist after a session clear ships 16 rows, the apply-backend
bound never exists, and nothing anywhere reports a problem.

Compounding it, the rationale section is stale too: line 190 still reads *"**Two** bounds …
and each has a test row (matrix rows 15 and 16)"* while line 370 reads *"Rows 15, 16 and 17
are the carve-out's **three** bounds."* The document contradicts itself on the count in the
very passage that explains why the code is shaped this way.

### 3. `checkout_desc`'s third case exists only as prose — no code, no test

The reference implementation (spec lines 298–306) has **two** cases. Twenty-five lines
later the spec mandates a **third**: `a detached HEAD mid-rebase that will update
'<branch>'`. An implementer copies code blocks, not prose. And no row asserts it — row 15's
Gherkin asserts only `Then it exits 2`, with no stderr assertion; row 17 has no Gherkin at
all. So the one refusal message that distinguishes the design's most confusing state
(cost 5) is unimplemented in the sample and unpinned by any test — in a document whose own
standard is "no bound here is prose".

It also needs `head-name`, which the two-argument `checkout_desc(branch)` signature cannot
reach; the implementer must invent that plumbing unaided.

### 4. The "exact text" table contradicts the remedy rule three paragraphs later

The table is headed **"Replacement text (exact)"** and gives:

> `Create a feature branch instead (git switch -c <name>), or stage only documentation.`

Then the prose says the remedy line *"must say finish or abort the operation rather than
advising a branch switch, whenever a sequencer marker is present"* — **without supplying
the replacement wording.** In a copy-paste, the exact-text table wins and the unfollowable
advice ships.

Worse, "abort" is dangerous guidance: `git rebase --abort` discards the operator's resolved
conflicts. Git itself prints the safe escape, and the spec never names it:

```
fatal: cannot switch branch while rebasing
Consider "git rebase --quit" or "git worktree add".
```

The remedy should name `--continue` (finish) or `--quit` (leave the work in place), never
`--abort`.

### 5. Operability walk — the operator can always tell, but is not always told what to do

I walked every reachable refusal. **Distinguishing a true block from a false one: passes**
— `checkout_desc` does its job, *provided case 3 ships*. **Knowing the next step: three
gaps**, and they land on exactly the two costs you singled out.

| # | Reachable refusal | Can they tell? | Next step? |
|---|---|---|---|
| a | Guard 2, named `main` | ✅ | ✅ switch branch |
| b | Guard 2, plain detached | ✅ | ⚠️ **no remedy line exists for Guard 2 at all** — cost 2's escape (`switch -c`) works but is never printed |
| c | Guard 2, non-repo | ✅ | ❌ no remedy, no escape |
| d | Guard 2, mid-`main`-rebase | ✅ (if case 3 ships) | ❌ no remedy |
| e | Guard 1, named `main` | ✅ | ✅ |
| f | Guard 1, plain detached | ✅ | ✅ `switch -c` works |
| g | **Guard 1, non-repo (cost 1)** | ✅ names "not a git repository" | ❌ **unfollowable** |
| h | **Guard 1, mid-`main`-rebase (cost 5)** | ✅ (if case 3 ships) | ⚠️ **unspecified**, and could be destructive |
| i | Guard 1, named `main` + `MERGE_HEAD` (row 16) | ✅ | ⚠️ rule covers it, no exact text |

**Cost 1** renders as *"the checkout is a directory that is not a git repository, where
commits are restricted to documentation (…)"* — the subordinate clause is nonsense in that
state, and the remedy `git switch -c <name>` cannot execute outside a repository. The
spec's remedy rule covers only sequencer states, so cost 1 keeps unfollowable advice by
design. The correct advice ("run this from inside the repository") is never printed. The
spec's own principle — *"a self-explaining refusal is the instrumentation"* — is not met
here.

**Cost 5** is followable *in principle* — `git rebase --continue` raises no `COMMIT` fact
and passes the guard — but the spec never says so, leaving the implementer to write it.

### 6. Checklist ordering is safe except one window: between steps 5 and 6

Walking each intermediate state, the guard is never left *weaker* than before, and the
red-suite window at step 4 is correct TDD (hook untouched, so behavior is identical to
`main`). One window is genuinely worse:

**After step 5 (hook logic) and before step 6 (messages)**, the guard refuses detached and
non-repo commits while still printing the old text:

- `git-guard: commits to main/master are blocked except documentation…`
- `git-guard: --force-with-lease is blocked while main/master is checked out.`

Both are **false** in that state — an operator on a detached HEAD is told they are on
`main`. That is precisely the confusion the message contract exists to prevent, shipped as
an intermediate commit.

**Fix: swap steps 5 and 6 — land the messages first.** It is behavior-neutral before the
logic change (pre-fix, `--abbrev-ref` returns `HEAD` for a detached checkout, which never
reaches a refusal; a non-repo returns `""`, which `checkout_desc` already renders
correctly), and it keeps the "no test edits in a hook step" rule intact.

### 7. Minor / low severity

- **`git bisect` is an unlisted collateral state.** Measured: branchless HEAD, and **none**
  of the six markers present, so a source commit during a bisect is refused. Direction is
  fail-closed and the remedy *works* (`git switch -c tmpfix` succeeds mid-bisect — warning
  only, exit 0), so this is benign — but it belongs in the accepted-cost list, since the
  design's stated principle ("stand down while git waits on the operator") describes bisect
  too, and its exclusion is a judgment the spec never records.
- **Row 17's fixture is ambiguous in the direction that silently loosens the guard.** I
  measured that `git rebase --apply main` from a feature branch yields
  `head-name: refs/heads/feat` — a *carve-out* row that exits 0, the opposite of what row 17
  expects. To get `refs/heads/main` you must be on `main` and rebase *it*. The row's
  parenthetical does disambiguate; the checklist step that builds fixtures does not mention
  row 17 at all. If the implementer builds it wrong, the row fails and the natural "fix" is
  to loosen the hook.
- **The carve-out table drops a measurement it has.** Row 5 shows `—` for the loose column
  and prose for the tightened column, where the numbers (loose 0, tight 2) exist.

## Dimension scores

| Dimension | Score | Note |
|---|---|---|
| `intent` | pass | Closes a real, reflog-confirmed fail-open at both call sites; goal and mechanism are correct and well argued. |
| `execution` | concern | Cannot run a design, and the measurement scripts are still uncommitted (spec concedes this). The artifacts that drive execution are stale: 16-vs-17 rows, missing apply-backend fixture, code block contradicting its own prose. |
| `trajectory` | pass | Five rounds of genuine correction; claims downgraded rather than defended; provenance marked per row. Sound reasoning, not luck. |
| `regression` | concern | `master` is unpinned at two sites and the existing suite has zero `master` coverage; the step-5/6 window regresses message accuracy. |
| `context_budget` | pass | Spec lives under `docs/`; the always-on `rules/gates.md` delta is a clause-level reword of two existing stubs. |
| `traceability` | concern | Documentation is excellent overall, but `checkout_desc` case 3 and the sequencer-aware remedy exist only as prose, and the doc contradicts itself on "two bounds" vs "three bounds". |
| `success_masking` | concern | Rows 15/16/17 all stay green with `refs/heads/master` deleted. A mis-built row 17 fails in the direction that invites loosening the hook. |
| `intent_drift` | pass | Explicit "Out of scope — do not widen" with four named deferrals and reasons; no new dependencies. |
| `checkpoint` | pass | Branch cut from fetched `origin/main` first, phase recorded, discrete revertable steps; the bad intermediate is on a feature branch, never `main`. |
| `audit_trail` | pass | ADR 0026 mandated with required content (residual hole enumerated by name), `rules/gates.md` edit mandated, verdict-before-commit ordering correctly noted for `judge-guard`. |

## Concerns (short form)

1. Fourth uncaught mutation: dropping `refs/heads/master` passes rows 15, 16 and 17; suite has zero `master` coverage
2. Checklist says "16 matrix rows" for a 17-row matrix; row 17 absent from steps 3, 4 and 5
3. Spec self-contradicts: "two bounds (rows 15 and 16)" vs "rows 15, 16 and 17 are the three bounds"
4. `checkout_desc` third case is prose-only — not in the code block, not asserted by any row
5. "Exact text" remedy table contradicts the sequencer remedy rule; no replacement wording given
6. Remedy risks advising `rebase --abort`, which discards resolved conflicts; `--quit`/`--continue` unnamed
7. Cost 1 (non-repo) refuses with a nonsensical clause and unfollowable advice; no bypass, no escape
8. Guard 2 has no remedy line for any of its three new branchless refusal states
9. Steps 5→6 ordering ships an intermediate commit that blocks with demonstrably false messages
10. `git bisect` is an unlisted collateral refusal state (benign — fails closed, remedy works)
11. Row 17's fixture is ambiguous; `rebase --apply main` from a feature branch yields the opposite outcome

## Recommendation

**Safe to implement after four cheap edits**, none of which change the design:

1. Retarget row 17 to `master` (kills concern 1 at zero row cost), or add row 18.
2. Fix the checklist: 17 rows, add the apply-backend fixture helper, include 17 in both
   must-fail lists.
3. Put case 3 into the `checkout_desc` code block, and add a stderr assertion to rows 15/17.
4. Give the sequencer remedy its exact text, naming `--continue`/`--quit` and never `--abort`;
   swap checklist steps 5 and 6.

This is advisory only and does not block. The underlying design is sound — the defects are
in the transmission layer, which matters more than usual here because the implementer is a
lower-tier model working from this document alone after a session clear.
