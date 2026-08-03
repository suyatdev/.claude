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
