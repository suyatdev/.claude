# Observability verdict — `fix/git-guard-empty-index` @ `5aa220e`

- **repo:** `git-guard-empty-index` (git worktree of `$HOME/.claude`, at
  `/Users/marksuyat/.claude/.claude/worktrees/git-guard-empty-index`)
- **branch:** `fix/git-guard-empty-index` · **head:** `5aa220e7cfbcac64c9078e198a6c2ee3b083780e`
- **base:** `main` @ `9fb2f64` · 8 commits · 7 files, +420/−7
- **stage:** implementation · **ts:** 2026-08-03T06:50:41Z
- **risk: high · confidence: high**

> ⚠️ **Leading with the failures.** `regression` = **fail** and `success_masking` = **fail**.
> This change closes two real defects and, in doing so, opens a new hole in the same Tier-1
> guard: a source file can now be committed to `main` in a shape that `main` blocks today.
> Measured live, twice, on the real repository.

---

## What was changed

Two guard scripts had bugs that were getting in the way every session, and this branch fixes both.

**Bug A — the commit guard read "nothing staged" as "refuse".** The guard that stops you
committing code straight to `main` decided by looking at the staging area. But the hook runs
*before* your command does, so when you type `git add X && git commit -m m -- X` — the exact form
this repo tells you to use — the staging area is still empty at the moment the guard looks. It saw
nothing, assumed the worst, and refused, even for a plain documentation file. The fix: when the
staging area cannot answer, ask the *command* what it will commit — the paths after `--`, the
worktree edits for `-a`, HEAD's files for `--amend`.

**Bug B — the phase guard forgot the memory folder.** One line listed the folders that are always
allowed to be written to. It missed the folder the assistant's own memory tool writes into, so
every memory save was refused whenever any feature file sat in `planning`. One line added.

Along the way two faults in the *test harness itself* were found and fixed in their own commits:
the staging helper pre-created the very state that hid Bug A, and a branch switch that failed was
being ignored so later tests silently ran on the wrong branch.

## Does it do what you wanted?

Yes for both named bugs — and every number claimed was independently re-measured and came out
exact:

| Claim | Re-measured | Result |
|---|---|---|
| `git-guard.test.sh` → 40/0 | ran it | **40 passed, 0 failed** ✔ |
| `phase-guard.test.sh` → 134/0 | ran it | **134 passed, 0 failed** ✔ |
| `classify-git-command.test.py` → 55/0 | ran it | **55 passed, 0 failed** ✔ |
| `shellcheck -x` both hooks → zero | ShellCheck 0.11.0 | **0 findings**, and 0 on `main` too — no net-new ✔ |
| New cases RED against pre-fix hook → 37/3 | replayed new suite against `main:hooks/git-guard.sh` | **37/3**, exactly the 3 named reds ✔ |
| Naive "empty → allow" mutant → 36/4 | built the mutant, ran it | **36/4**, exactly the 4 named cases ✔ |
| phase-guard: memory write 2 → 0 mid-planning | live, `verification-marker-gate.md` at `planning` | `main` **2**, fixed **0** ✔ (and source still **2**) |
| git-guard: chained docs commit on `main` 2 → 0 | live, from the primary checkout | **2 → 0** ✔ |
| git-guard: chained source commit still 2 | live | **2 → 2** ✔ |

The evidence discipline here is genuinely above average: red and green live in separate commits,
the fixture fixes are separate again, the fail-open trap was identified *before* coding, and the
plausible wrong fix was built and shown to fail. That is not luck.

## What could go wrong / what I'm unsure about

**1. A new fail-open in the guard this branch is fixing — the one shape nobody enumerated.**

The design lists three ways a commit can carry content the index does not show (pathspec, `-a`,
`--amend`) and handles all three. It misses a fourth: **the chain's own `git add`.** When the
command is `git add <source> && git commit -m msg` — with no pathspec on the `commit` — the
classifier emits only `COMMIT`, the derivation finds nothing, and the guard **allows** it. But the
`git add` runs first, so the commit is not empty at all: the source file lands on `main`.

Measured on the real repository, on `main`, with an empty index:

```
main=2  fixed=0   <-  git add -- hooks/x.sh && git commit -m msg
main=2  fixed=0   <-  git add -A && git commit -m msg          (scratch repo)
main=2  fixed=0   <-  git add . && git commit -m msg           (scratch repo)
```

The `main=2` column is the point: today these are blocked. After this change they are allowed.
The spec's justification for allowing an empty derivation — *"Such a commit has nothing to commit
and git fails it on its own"* — is simply false when a sibling `git add` precedes it in the same
chain, and that chained shape is the entire reason this branch exists. The same false premise is
copied into the hook's own comment, so a future reader is actively misled.

This is fixable squarely inside the design that was chosen: the classifier already lexes every
segment, so `ADD_PATH<tab><path>` / `ADD_ALL` facts from the `git add` segment would close it with
no second parser, exactly as `COMMIT_PATH` does.

**2. The green suite hides it.** 40/0 passes while the hole is untested. The new test section
explicitly says "three shapes commit content the index does not show. Each gets a case pinning it
blocked" — the enumeration in the comment *is* the enumeration in the code, so the suite can only
ever confirm the author's own list. The one existing test using this shape
(`git add -- src/app.sh && git commit -m msg`) sits on the `feature` branch, where the expected
answer is allow, so it cannot catch the `main` case.

**3. Same class, narrower: `--amend` abbreviations and `--pathspec-from-file`.**
`git commit --amen --no-edit` is accepted by git (verified: it ran, printed `On branch main`), but
the classifier does a literal `"--amend" in rest` and misses it → empty derivation → **allow**, so
an amend of a source-bearing HEAD passes on `main`. Likewise `git commit --pathspec-from-file=list`
yields no facts and is allowed. The abbreviation class (`--amen/--ame/--am`) was already raised
against the sibling classifier in the 2026-08-02 verdict; it was not carried forward here.

**4. `commit_target_files` inherits Defect C and widens its blast radius.** The new
`git diff --name-only` and `git diff-tree … HEAD` calls run in the *hook's* working directory, same
as `current_branch()`. Defect C previously meant only the *branch* was read from the wrong place;
now the *file list* is too. Deferring Defect C was the user's explicit ruling and I agree it needs
a design decision rather than a patch — but the deferral got slightly more expensive with this
commit, and that is not noted in the feature file.

**5. No ADR.** "An empty index means ask the command" and "unaccountable arguments fail closed" are
policy decisions about a Tier-1 guard, in the same family as the allowlist change that the
2026-08-03 `fix/fix-l1` verdict already flagged as ADR-worthy. Nothing under `docs/decisions/`.

**6. Verdict-store split.** This file is written to the *worktree's* copy of the tracked verdict
store. `judge-guard` resolves the store from `git rev-parse --show-toplevel`, so it will find it
if `gh pr create` runs here — but the primary checkout's copy will not have it until this branch
merges, and `repo` is recorded as `git-guard-empty-index` (the worktree directory name), not
`.claude` as every prior verdict on this repo. A judge run from the primary checkout would not
match this row.

**Minor:** `settings.json` is uncommitted in this worktree (`"claude-fable-5[1m]"` → `"sonnet"`).
It carries `skip-worktree` and is out of scope per the spec, so it is noise rather than drift — but
it should not ride along into the PR.

## What I'd double-check before merging

1. **Close the `git add` hole, or consciously accept it in writing.** Add `ADD_PATH`/`ADD_ALL`
   facts to `classify-git-command.py` and fold them into `commit_target_files`, plus a test
   pinning `git add -- src/x.sh && git commit -m msg` on `main` as **block**. If it is instead
   accepted for now, the spec's "git fails it on its own" sentence and the matching hook comment
   must be corrected — a wrong stated reason is worse than a known gap.
2. **Decide on `--amend` abbreviations and `--pathspec-from-file`** — either match prefixes or
   route unrecognised long options into `COMMIT_BARE_ARGS` so they fail closed like everything
   else the table cannot account for.
3. **Re-run the red replay after any of the above**, so the three intended reds are still exactly
   three and no case starts passing for the wrong reason — this suite has already produced two
   false-premise fixtures.
4. **Add a short ADR** for the empty-index policy and the bare-args fail-closed rule.
5. **Note the Defect C widening** in the feature file's open-issue section, so the next reader
   knows the deferral now covers the derived file list, not just the branch name.
6. **Confirm which checkout `gh pr create` will run from** and that the verdict row's `repo` value
   matches what `judge-guard` will compute there; drop the stray `settings.json` edit.

---

## Dimension table

| Dimension | Verdict | Why |
|---|---|---|
| `intent` | concern | Both named defects fixed and verified. But the spec's own stated non-goal — "a naive fix would turn it into a silent allow for source files, a new fail-open in a Tier 1 guard" — is violated in a shape the enumeration missed. |
| `execution` | concern | All four suites run by me, all green, all claims re-measured exact. The shipped artifact nonetheless allows a source commit to `main` that `main` blocks. |
| `trajectory` | concern | Reasoning is strong and documented (trap identified up front, `-a` accident caught, mutant built). But the justification for the allow branch is a stated premise that is measurably false for the chained case — a reasoning error, not just an omission. |
| `regression` | **fail** | Measured on the live repo: `git add -- hooks/x.sh && git commit -m msg` on `main` goes **2 → 0**. Also `git add -A/. && git commit -m msg`, and `git commit --amen`. Previously-blocked source-to-`main` paths are now allowed. |
| `context_budget` | pass | No change to `CLAUDE.md`, `rules/*.md`, or any always-on file. `rules/gates.md` deliberately left alone. |
| `traceability` | concern | Feature file, checklist rationale, Verification table, and in-code comments are excellent — but one load-bearing explanation ("git fails it on its own") is wrong, and is duplicated into the hook comment. |
| `success_masking` | **fail** | 40/0 green while a newly-opened fail-open is untested. The suite's enumeration mirrors the code's, so it can only confirm the author's own list; the one test using the shape sits on `feature`, where allow is correct. |
| `intent_drift` | pass | Harness fixes were necessary for the new cases and committed separately with rationale. Defect C and the `gates.md` wording correctly left out per the user's ruling. No new deps. Uncommitted `settings.json` is skip-worktree noise. |
| `checkpoint` | pass | 8 clean commits, red/green split, fixture fixes isolated, work done in a worktree so the live hooks stay on `main`. Revert = drop the branch; nothing is armed until merge. |
| `audit_trail` | concern | Commits attributable and well-messaged, feature file points at `CODING_MEMORY.md` lines. No ADR for two Tier-1 guard policy decisions. Verdict lands in a worktree-local store under `repo: git-guard-empty-index`, diverging from every prior `.claude` row. |

## Concerns

1. NEW FAIL-OPEN, measured live on `main`: `git add -- hooks/x.sh && git commit -m msg` was blocked (2) and is now allowed (0) — the chain's own `git add` is the fourth content source the design never enumerated
2. `git add -A && git commit -m msg` and `git add . && git commit -m msg` are allowed the same way on `main`
3. The spec's and the hook comment's justification for the allow branch — "such a commit has nothing to commit and git fails it on its own" — is false for any chained `git add`, i.e. the case this branch exists to serve
4. 40/0 green with the new hole untested; the test enumeration mirrors the code enumeration, so it can only confirm the author's own list
5. `git commit --amen --no-edit` is a valid git abbreviation, is missed by the literal `"--amend" in rest` check, and allows an amend of a source-bearing HEAD on `main` — the abbreviation class was already raised in the 2026-08-02 verdict on the sibling classifier
6. `git commit --pathspec-from-file=list` yields no facts and is allowed on `main` with an empty index
7. `commit_target_files` widens Defect C: `git diff --name-only` and `git diff-tree` now also run in the hook's cwd, so a worktree's file list is read from the wrong checkout; the deferral is unchanged but its cost grew, and the feature file does not say so
8. No ADR for "empty index means ask the command" or "unaccountable arguments fail closed" — Tier-1 guard policy, the same class already flagged as ADR-worthy on `fix/fix-l1`
9. Verdict written to the worktree-local copy of the tracked store, with `repo` = `git-guard-empty-index` rather than `.claude`; a judge run from the primary checkout would not match this row
10. Uncommitted `settings.json` (model selector) sitting in the worktree — skip-worktree noise, but should not ride into the PR

---
---

# Observability verdict — `fix/git-guard-empty-index` @ `833e3eb` — **ROUND 2**

- **repo:** `git-guard-empty-index` (git worktree of `$HOME/.claude`, at
  `/Users/marksuyat/.claude/.claude/worktrees/git-guard-empty-index`)
- **branch:** `fix/git-guard-empty-index` · **head:** `833e3ebeceb5e8cfb35db02a631e38ee97c3b288`
- **base:** `main` @ `9fb2f64` · 11 commits · 10 files, +931/−12 (round-2 delta: 3 commits, +533/−27)
- **stage:** implementation · **ts:** 2026-08-03T19:11:21Z
- **risk: medium · confidence: high** (round 1 was `high`)

> ⚠️ **Leading with the failures.** `regression` = **fail** and `success_masking` = **fail**.
> Round 1's blocker **is genuinely closed** — I re-measured all of it and found no false positives.
> But closing it did not close the *class*. The fix taught the classifier about `git add`
> specifically, and still treats "the chain stages something" as meaning "the chain contains a
> `git add`". **Nine other index-writing git commands are invisible**, and `main` blocks all nine
> today. Measured live; four verified end-to-end putting a source file into a commit on `main`.
>
> Round 1's own lesson — "the enumeration was short" — is restated in ADR 0014 as a general
> principle, and then the enumeration is short again, one level out.

---

## What was changed

Think of the guard as a bouncer who has to decide whether a commit is allowed onto `main`. He used
to check the staging area — but he stands at the door *before* the command runs, so for the form
this repo mandates (`git add X && git commit`) the staging area is still empty when he looks.
Round 1 changed him to read the command itself instead.

Round 1's problem was that he only read the `commit` half of the sentence. `git add hooks/x.sh &&
git commit -m msg` looked empty to him, so he waved it through — while `main` blocks it. Four
previously-blocked source commits became allowed.

**This round fixes exactly that.** Three commits, deliberately separated:

- **red first** (`aedaf38`) — 21 new failing cases, plus a fixture leak fix: earlier test sections
  were leaving stray untracked files behind, which `git add -A` then swept up, so a case claiming
  "only docs modified" was quietly handing a source file to the `-A` cases.
- **green** (`8099d0a`) — the bouncer now also reads the `git add` half. Named paths are read off
  the command; an unbounded add (`-A`, `-u`, `.`) is resolved by asking git. A `--` pathspec on the
  `commit` is treated as *exclusive* and overrides the add. And anything he can't parse — an
  unknown option, a stray word — now **blocks** instead of sailing through, which catches a whole
  family at once (`--amen`, `--pathspec-from-file`, `-i`, `-o`, `-Skeyid`).
- **ADR 0014** (`833e3eb`) — writes down the policy and, unusually and to its credit, writes down
  the mistake and *why* it was made.

## Does it do what you wanted?

**For the named blocker, yes — completely, and I re-measured every claim rather than accepting it.**

| Claim | Re-measured | Result |
|---|---|---|
| `git-guard.test.sh` → 50/0 | ran it | **50 passed, 0 failed** ✔ |
| `phase-guard.test.sh` → 134/0 | ran it | **134 passed, 0 failed** ✔ |
| `classify-git-command.test.py` → 66/0 | ran it | **66 passed, 0 failed** ✔ |
| `shellcheck -x` both hooks | ShellCheck 0.11.0 | **0 findings** ✔ |
| All 4 round-1 regressions now block | live, scratch repo on `main`, empty index | all **r1=0 → HEAD=2** ✔ (plus `add -u`, `add .`, untracked source, unknown option — 8/8) |
| No false positives appeared | 11 probes | docs via `--`, docs via `-A`, `coding-memory` via `-A`, clean repo, `--no-edit`, `-q --signoff --no-verify`, bare `commit -m`, non-git → **all allow** ✔ |
| New tests RED against pre-fix code | swapped in `5aa220e`'s two files, ran the new suites | **45/5** and **53/13** — exactly 5 and 13 ✔ |
| The 5 changed expectations strengthen, not weaken | read every one | ✔ — each only **added** `ADD_PATH\tx` beside the existing `COMMIT`. No fact removed, no block flipped to an allow. The claim is correct. |
| A commit pathspec is exclusive | ran it for real | ✔ commit contained only `docs/x.md`; the separately-staged `hooks/x.sh` stayed in the index |
| Safe-flag list is not a fail-open | built the mutant that adds `-i`/`-o` to it | ✔ **still blocks** — the bare-token rule backstops the list independently |
| Mutation testing | built 10 mutants | **9 of 10 caught** by at least one suite |

The engineering discipline this round is high: red before green in separate commits, a fixture leak
found and fixed rather than worked around, the pathspec-exclusivity rule *measured* rather than
assumed, and — best of all — the shift from patching named bad options to a general "if I can't
parse it, block" rule. That last one is the right instinct and it independently closes options
nobody listed.

**For the underlying class, no.** See below.

## What could go wrong / what I'm unsure about

**1. `regression` = FAIL — the same hole, one level out.**

The fix asks: *"does this command line contain a `git add`?"* The question it needed to ask is
*"can anything on this command line put something in the index?"* Nine other git commands can.
Measured on a scratch repo, on `main`, index empty (`main` = today's guard, `HEAD` = this branch):

```
main=2  HEAD=0   git rm hooks/x.sh && git commit -m msg
main=2  HEAD=0   git mv hooks/x.sh hooks/y.sh && git commit -m msg
main=2  HEAD=0   git reset --soft HEAD~1 && git commit -m msg
main=2  HEAD=0   git checkout HEAD~1 -- hooks/x.sh && git commit -m msg
main=2  HEAD=0   git restore --source=HEAD~1 --staged hooks/x.sh && git commit -m msg
main=2  HEAD=0   git apply --cached p.diff && git commit -m msg
main=2  HEAD=0   git stash pop --index && git commit -m msg
main=2  HEAD=0   git cherry-pick -n <sha> && git commit -m msg
main=2  HEAD=0   git revert -n HEAD && git commit -m msg
```

`main=2` is the point: blocked today, allowed after this branch. I then **ran** the first four for
real and confirmed the resulting commit on `main` contains a source file:

```
git rm hooks/x.sh && git commit                -> HEAD commit touches: hooks/x.sh
git mv hooks/x.sh hooks/y.sh && git commit     -> HEAD commit touches: hooks/y.sh
git reset --soft HEAD~1 && git commit          -> HEAD commit touches: hooks/x.sh
git checkout HEAD~1 -- hooks/x.sh && git commit-> HEAD commit touches: hooks/x.sh
```

**There is no backstop.** I fired the same three at `doc-guard.sh` as well: it returns 0 too.

These are not exotic. `git rm X && git commit` and `git reset --soft HEAD~1 && git commit` (the
standard "redo the last commit") are ordinary developer chains.

*In fairness:* these were only ever blocked as collateral of the over-broad empty-index deny that
this branch exists to remove — the same argument the spec itself makes about `-a` ("`-a` today
fails closed on `main` only by accident"). And the guard is self-declared a momentum guardrail, not
a security boundary. That is why this is `medium` and not `high`. But it is still *blocked today,
allowed tomorrow*, and it is **written down nowhere**.

The fix is cheap and sits inside the design already chosen: emit one more fact (say
`STAGES_UNKNOWN`) for any segment running `rm`/`mv`/`reset`/`restore`/`checkout`/`apply`/`stash`/
`cherry-pick`/`revert`/`merge`, and treat it exactly like `COMMIT_BARE_ARGS` — fail closed. One
parser, no new lexer.

**2. `success_masking` = FAIL — 50/0 green with all nine untested.** ADR 0014 states the diagnosis
precisely: *"the test comment's enumeration was the code's enumeration… a suite built that way can
only confirm the cases its author thought of."* The suite was rebuilt from the same enumeration
again. My mutation matrix is genuinely good (9/10 mutants caught), but mutation testing validates
assertions against the fixture's premise — which is the ADR's own point.

**3. Both documents claim the enumeration is complete, and it isn't.** ADR 0014: *"Four shapes
commit content an empty index does not show. All four are consulted."* The feature file says the
same. That is a stated completeness that I measured to be false — and "a wrong stated reason is
worse than a known gap" is a heading in this very ADR. This is the part I'd insist on regardless of
whether the code changes.

**4. A second wrong-reason in the ADR, this one harmless today.** ADR 0014 says renames from
`git status --porcelain` *"read as `old -> new`, match no allowlist entry, and therefore block."*
The allowlist patterns are `case` globs and `*` spans everything, so I checked all four shapes:

```
coding-memory/m.txt -> hooks/evil.sh    ALLOW   <- would let ANY file through
docs/a.md -> hooks/evil.md              ALLOW
docs/a.md -> docs/b.md                  ALLOW
hooks/x.sh -> docs/y.md                 BLOCK
```

It is **unreachable today** — I verified an `R` line only appears when the index is populated
(with an empty index a rename shows as ` D old` + `?? new`, which `cut -c4-` splits into two clean
paths), and a populated index takes the real staged-file path, which I confirmed blocks (exit 2).
So: right outcome, wrong reason, in an accepted ADR. If anyone later reroutes this derivation, it
goes live.

**5. A residual false positive of exactly the class this branch exists to remove.**
`git status --porcelain` C-quotes paths with spaces or non-ASCII, and `cut -c4-` keeps the quotes,
so the string is `"docs/a b.md"` and no longer matches `docs/*.md`:

```
HEAD=2  git add -A && git commit -m msg   with untracked  docs/a b.md      <- should allow
HEAD=2  git add -A && git commit -m msg   with untracked  docs/naïve.md    <- should allow
HEAD=0  git add -A && git commit -m msg   with untracked  docs/aXb.md      (control)
```

`main` blocks these too, so it is not a regression — the fix is just incomplete for those names.
Safe direction, but a documentation file with a space in its name still can't be committed.

**6. `has_fact` is not a fact test — it is word-splitting over a string that carries file paths.**
Facts are `ADD_PATH<tab><path>`, and tab is in bash's default `IFS`, so the unquoted `for f in
$facts` splits the path out as its own "fact". A path that collides with a fact name is therefore
read as that fact:

```
HEAD=0   git add -- COMMIT_PATHSPEC && git commit -m msg          (main=2)
HEAD=0   git add -- 'd/a COMMIT_PATHSPEC b.sh' && git commit      (main=2)
HEAD=2   git add -- ADD_ALL && git commit -m msg
HEAD=2   git add -- COMMIT && git commit -m msg
```

`COMMIT_PATHSPEC` is the dangerous collision because it is the one fact that *narrows* the file
set: the code takes the exclusive-pathspec branch, greps for real `COMMIT_PATH` lines, finds none,
and allows. Absurd as a filename — but it means the mechanism that decodes the fact stream depends
on an undocumented property of `IFS`, in a Tier-1 guard.

**7. Load-bearing by absence, pinned by nothing.** `-i`/`-o`/`--include`/`--only` block correctly —
I confirmed live, and confirmed they are *doubly* defended (unrecognised option **and** bare
token), so even the mutant that adds them to `COMMIT_SAFE_FLAGS` still blocks. Good. But no test
mentions them, so the property is not pinned.

**8. Known-open items — I agree with all three.** Identity-from-cwd (`git-guard.sh:88`) with its
now-wider blast radius is correctly recorded in both the feature file and ADR 0014, and needs a
design decision across three guards rather than a patch here. `--amend` with a populated index is
pre-existing and correctly not widened. `rules/gates.md:5` belongs to the other branch. No
disagreement.

**Minor:** `settings.json` (`"claude-fable-5[1m]"` → `"sonnet"`) is still uncommitted in this
worktree — `skip-worktree` noise, but it should not ride into the PR. And per round 1, the verdict
store here is worktree-local with `repo: git-guard-empty-index`; `gh pr create` **must** run from
this worktree or `judge-guard` will compute `repo=.claude` and not match either row.

## What I'd double-check before merging

1. **Decide the nine shapes, in writing, one way or the other.** Either add the `STAGES_UNKNOWN`
   fact (small, in-design, ~10 lines) with a test pinning `git rm hooks/x.sh && git commit -m msg`
   as **block** — or accept them explicitly in ADR 0014's *Known open* section with the measured
   `main=2 → HEAD=0` table. What must not ship is the current state: an undocumented reduction in
   coverage sitting under a claim of completeness.
2. **Fix the two completeness claims either way.** "Four shapes… all four are consulted" in ADR
   0014 and the feature file must stop asserting the enumeration is closed.
3. **Correct the rename sentence in ADR 0014**, and add the one-line reason it is actually safe
   (an `R` line requires a populated index, which never reaches this branch).
4. **Add a test pinning `-i`/`-o`/`--only`/`--include` as blocked**, so the double defense is a
   pinned property rather than a happy accident.
5. **Consider `git status --porcelain -z`** (or unquoting) so a docs file with a space in its name
   stops being blocked — the friction this branch exists to remove.
6. **Quote the fact stream in `has_fact`** (or match on line-anchored greps throughout) so a file
   path can never be read as a fact token.
7. **Re-run the red replay after any of the above** — the reds must stay exactly 5 and 13, with no
   case starting to pass for a new reason. This suite has already produced two false-premise
   fixtures.
8. **Run `gh pr create` from this worktree**, and drop the stray `settings.json` edit.

---

## Dimension table

| Dimension | Verdict | Why |
|---|---|---|
| `intent` | concern | Round 1's blocker is fully closed and verified with zero false positives — real, measurable progress. But the spec's own stated non-goal ("a naive fix would turn it into a silent allow for source files, a new fail-open in a Tier 1 guard") is still violated by nine unenumerated shapes. |
| `execution` | concern | All four suites run by me and exact (50/0, 134/0, 66/0, shellcheck 0). Replay exact at 5 and 13. 9 of 10 mutants caught. The shipped artifact nonetheless allows source onto `main` in nine measured shapes, four verified end-to-end. |
| `trajectory` | concern | Strong and improving: red/green split, fixture leak found, exclusivity measured not assumed, and the shift to a general "cannot parse → block" rule is the right generalisation. But ADR 0014 articulates the exact meta-lesson ("the missed shape was the one not part of the `commit`") and then stops one step short of applying it to every index-writing command. |
| `regression` | **fail** | Nine shapes measured `main=2 → HEAD=0`; `git rm`, `git mv`, `git reset --soft`, `git checkout <tree> -- <path>` verified end-to-end placing a source file in a commit on `main`. `doc-guard` returns 0 on all three probed, so there is no backstop. Undocumented. |
| `context_budget` | pass | No change to `CLAUDE.md`, `rules/*.md`, or any always-on file. ADR and feature file are load-on-demand. `rules/gates.md` correctly untouched. |
| `traceability` | concern | Genuinely excellent in most respects — task 8 reproduces the round-1 blocker before accepting it, ADR 0014's "a wrong stated reason is worse than a known gap" section is instructive, in-code comments corrected and the false "git fails it on its own" line removed. Undercut by two stated-but-false claims: the enumeration completeness, and the rename/allowlist reasoning. |
| `success_masking` | **fail** | 50/0 green with all nine shapes untested. The ADR names this failure mode explicitly and the suite reproduces it. Mutation testing (mine, 9/10 caught) cannot help — it validates assertions against the fixture's premise, never the premise. |
| `intent_drift` | pass | Three tightly-scoped commits (red / green / ADR). No new dependencies. Defect C and the `gates.md` wording correctly left out per the user's ruling. The fixture-leak fix was necessary for the new cases and is explained. `settings.json` is uncommitted skip-worktree noise, not in the diff. |
| `checkpoint` | pass | 11 clean commits, red before green in separate commits, round 1's verdict itself committed and preserved. Work isolated in a worktree so the live hooks stay on `main`; revert = drop the branch, nothing armed until merge. |
| `audit_trail` | concern | Round 1's missing-ADR concern is closed — 0014 exists and is unusually good, including the Defect C blast-radius note. Remaining: the nine shapes appear in no open-issues list, and the verdict store is worktree-local under `repo: git-guard-empty-index`, so `gh pr create` must run from this worktree. |

## Concerns

1. NEW FAIL-OPEN, same class as round 1 one level out: only `git add` is modelled, so every other index-writing porcelain is invisible — `git rm`, `git mv`, `git reset --soft`, `git checkout <tree> -- <path>`, `git restore --staged`, `git apply --cached`, `git stash pop --index`, `git cherry-pick -n`, `git revert -n`; nine shapes measured `main=2 → HEAD=0`
2. Four of those verified end-to-end putting a source file into a commit on `main`; `doc-guard` returns 0 on all three probed, so nothing backstops them
3. ADR 0014 and the feature file both assert the enumeration is complete ("Four shapes… All four are consulted") — measurably false, and stated completeness is the exact failure mode the ADR warns against one paragraph earlier
4. 50/0 green with none of the nine tested; the suite's enumeration is again the code's enumeration, as the ADR itself predicts
5. ADR 0014's rename claim ("`old -> new` matches no allowlist entry, therefore blocks") is false — `coding-memory/x -> hooks/evil.sh` and `docs/a.md -> hooks/evil.md` both ALLOW under the `case` globs; unreachable today (an `R` line needs a populated index, which takes the staged path — confirmed exit 2), so a wrong reason for a right outcome
6. `git status --porcelain` C-quotes paths with spaces/non-ASCII and `cut -c4-` keeps the quotes, so `docs/a b.md` and `docs/naïve.md` staged via `git add -A` are BLOCKED — a residual false positive of the exact class this branch exists to remove (not a regression; `main` blocks them too)
7. `has_fact` word-splits an untrusted path-bearing string (tab is in the default `IFS`), so a file named `COMMIT_PATHSPEC`, or any path containing that token as a whitespace-delimited word, takes the exclusive-pathspec branch and ALLOWS
8. `-i`/`-o`/`--only`/`--include` are load-bearing by their absence from `COMMIT_SAFE_FLAGS` and no test pins them (they do block today, and doubly — confirmed by mutant M11)
9. Identity-from-cwd (`git-guard.sh:88`) with its widened blast radius remains open — agreed, correctly documented in both the feature file and ADR 0014, out of scope per the user's ruling
10. Verdict store is worktree-local with `repo: git-guard-empty-index`; `gh pr create` must run from this worktree or `judge-guard` computes `repo=.claude` and matches neither round
11. Uncommitted `settings.json` model-selector edit still sitting in the worktree
