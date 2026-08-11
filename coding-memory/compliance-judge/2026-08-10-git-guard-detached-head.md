# Compliance judge — `docs/features/git-guard-detached-head.md`

Spec: `docs/features/git-guard-detached-head.md`
Repo: `memsearch-freshness` (worktree, detached HEAD) · base branch `origin/main`

---

## Round 1 — 2026-08-10T17:32:00Z

- **Verdict: FAIL** (4 violations)
- head_sha: `0819db75229b2b31a98a080b3edf56bef5720603`
- spec_blob_sha: `f10fad59c258d7de6dd75a7c3acf44f18fba3ea0`
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
  (no `.claude/project-standards.md` in this repo — the repo layer is `CLAUDE.md` + `rules/`;
  `rules/core-conduct.md` in the worktree **differs from** `~/.claude/rules/core-conduct.md` and
  the worktree copy was the one judged)
- Confidence: **high** — every finding was executed against a patched copy of the hook, not inferred.
- Waived: none.

### Layman summary

This spec found a real hole and closed it correctly. I tried hard to break the diagnosis and could
not. The bug is exactly as described: when a checkout is detached, `git rev-parse --abbrev-ref HEAD`
answers with the literal word `HEAD`, so `on_main()` says "not main" and both Tier 1 guards stand
down. I reproduced it — and the irony is that this judging session is itself running from a detached
HEAD in the very worktree the spec's reflog evidence comes from.

I checked every claim the spec makes rather than taking its word:

- **The classifier claim holds.** I ran `git add -- src/app.sh && git rebase --continue` through
  `lib/classify-git-command.py` and it emits **zero facts** — `classify()` line 152 tests
  `subcommand == "commit"`, so `rebase`, `cherry-pick --continue`, `revert --continue` and
  `merge --continue` all produce nothing. Guard 1 is never reached. The whole fail-closed argument
  rests on this and it is sound.
- **A branch cannot be named `HEAD`.** `git branch HEAD` → `fatal: 'HEAD' is not a valid branch name`.
  No shadowing risk.
- **git-guard really has no bypass variable.** `grep -c EXEMPT hooks/git-guard.sh` → `0`, while
  `merge-guard.sh`, `judge-guard.sh` and `feature-sync-guard.sh` each have one.
- **`rules/gates.md` line 13 is genuinely falsified** — it reads "`--force-with-lease` is allowed on
  feature branches, blocked on `main`/`master`", and line 288 of `phase-guard.sh` confirms `rules/`
  is in neither exempt list. ADR 0025 is indeed the highest.
- **All four version pins are exact**: bash 3.2.57(1) `arm64-apple-darwin25`, git 2.50.1
  (Apple Git-155), Python 3.9.6, jq-1.7.1-apple. That is rare.
- **All eight Gherkin scenarios pass** against a copy of the hook with the spec's `case` form
  patched in — the four new ones exit 2/0/2/2 as written, and all four regressions stay green.

So the design is right and I am not asking for rework. The four failures are all defects in the spec
*text*, each fixable in a paragraph.

**The one that matters** is in Accepted costs. The spec writes, as settled fact, that the `""` arm
costs nothing: *"A commit made in a directory that is not a git repository is now refused. It would
have failed on its own, so nothing that previously worked stops working."* That last clause is false,
and I measured it. From a working directory that is not a repo, the command
`cd /some/real/repo && git commit -m msg -- src/app.sh` — a source commit on a **feature branch** in a
perfectly healthy repo — exits **0** today and exits **2** under the new `on_main()`. The hook reads
the ambient cwd, so it asks the wrong repo, gets no answer, and now fails closed on a command that
was always legitimate. The spec dismisses this exact shape in Out of scope as "Pre-existing,
unrelated" — but the change is what makes it *blocking*, so it is neither. Worse, the stated escape
hatch (`git switch -c <branch>`) only rescues the `HEAD` arm; on the `""` arm there is no branch to
switch to and no bypass variable, so there is no escape at all. I am not asking for the bypass
variable — fail-closed is the right call and core-conduct backs it. I am asking for the sentence to
be true.

The other three: the `""`/`HEAD` arm's edges are under-enumerated (a fresh `git init` repo returns
`HEAD`, **not** `""` as the Background claims, and its first source commit flips 0 → 2 — I ran it);
the two stderr messages are required to change and required to be asserted in tests, but their new
text is never given and "must also cover detached" reads either as one static combined string or as
state-dependent wording; and checklist step 5 edits the hook and its tests in a single step, which
steps 2–4 scrupulously avoid.

### Violations

| # | id | rule_source | where | why |
|---|---|---|---|---|
| 1 | `core-conduct/verification-before-write-down` | `rules/core-conduct.md` | Accepted costs (2nd bullet), reinforced by Out of scope bullet 2 | "nothing that previously worked stops working" is recorded as settled fact and is measurably false — from a non-repo cwd, `cd /real/repo && git commit -m msg -- src/app.sh` on a feature branch goes exit 0 → exit 2. |
| 2 | `writing-specs/good-bad-edge-cases` | `skills/writing-specs/SKILL.md` | Scenarios → "New behavior", and Background para 2 | The cannot-tell arm has one scenario (not-a-repo) and leaves two measured behavior changes unenumerated: the cross-repo commit above, and a freshly-initialised repo whose unborn HEAD returns `HEAD` (not `""`, contradicting the Background) and whose first source commit flips exit 0 → 2. |
| 3 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | Messages table + Checklist step 5 + Scenario "Source file committed from a detached HEAD" | The two stderr strings are the hook's output contract and are required to be asserted by tests, yet the replacement text is never stated, and "must also cover detached / unknown checkout" is readable as one static combined string or as state-dependent messages — different code, different assertions. |
| 4 | `core-conduct/tests-and-implementation-separate` | `rules/core-conduct.md` | Checklist step 5 | "Reword the two stderr messages. Assert the new wording in the tests." edits implementation and tests in one step, which steps 2–4 explicitly refuse to do ("Tests only — no hook edit in this step"). |

**Rule text cited**

1. `rules/core-conduct.md:9` — "Verification precedes both the claim and the write-down — never state
   that something works, is fixed, or is done, and never record that claim in a durable artifact
   (ADR, memory file, commit message, PR body, handoff, spec), until you have actually run it and
   re-read the output. … When something is unverified, write what you checked and what you did not."
2. `skills/writing-specs/SKILL.md:28` — "Good, bad, and edge-case scenarios: state explicitly what
   correct looks like, what wrong looks like, and enumerate the edges. Anything you leave implicit,
   the agent infers — and inference is where the defects come from."
3. `skills/writing-specs/SKILL.md:25` — "Database schemas and API contracts: these give the agent the
   real data structures and interface boundaries to build against, instead of letting it improvise
   shapes that other components then fail to match." With `:20` — "a requirement you cannot phrase as
   Given/When/Then is usually a requirement you have not actually decided yet."
4. `rules/core-conduct.md:19` — "Never edit tests and implementation in the same step — the test is
   the unbiased baseline."

### Measurements

Patched a copy of `hooks/git-guard.sh` with the spec's `case` form (`/tmp/ggj/new/`), kept an
unpatched copy (`/tmp/ggj/old/`), drove both with real `PreToolUse` payloads.

| Probe | old | new |
|---|---|---|
| S1 source staged, detached, `git commit -m msg` | — | **2** ✓ (stderr still says "to main/master") |
| S2 docs only, detached | — | **0** ✓ |
| S3 `git push --force-with-lease origin HEAD:main`, detached | — | **2** ✓ |
| S4 not a git repository, `git commit -m msg` | — | **2** ✓ |
| S5 `git add -- src/app.sh && git rebase --continue`, detached | — | **0** ✓ (classifier emits no facts) |
| S6/S7/S8 feature-branch regressions | — | **0 / 0 / 2** ✓ |
| non-repo cwd, `cd /real/repo && git commit -m msg -- src/app.sh` | **0** | **2** ← violation 1 |
| fresh `git init`, unborn HEAD, `git commit -m init` (src staged) | **0** | **2** ← violation 2 |

`current_branch()` under every failure mode I could build: unborn branch → `HEAD` (git exits 128 but
prints `HEAD`); not a repo → `""`; corrupt `.git/HEAD` → `""`; HEAD pointing at a nonexistent ref →
`HEAD`. **Every one lands inside the spec's closed set `{main, master, HEAD, ""}`** — the design is
airtight; only the Background's story about *which* failure yields *which* answer is wrong.

### Notes (non-blocking)

- **Canonical path is correct.** `writing-specs:54` says specs live in `docs/superpowers/specs/`, but
  this repo's `rules/gates.md` One-canonical-file discipline mandates `docs/features/<name>.md`, and
  project rules take precedence. Frontmatter (`phase: planning`, `branch: none`) matches ten sibling
  feature files. Not a violation.
- **"0819db7 is 4 commits behind" is now wrong — it is 9.** `origin/main` moved from `c87dedb` to
  `1b983d9` since the spec was written, so the number was likely true when recorded and has since
  decayed. The instruction it supports ("cut from fetched `origin/main`, not this worktree's HEAD")
  is correct and self-sufficient without the number. Storing the derivation
  (`git rev-list --count HEAD..origin/main`) instead of the integer would stop this recurring. Not
  cited — it was verified at write time.
- **Out-of-scope items 1, 3 and 4 are legitimately deferrable; item 2 is not** (that is violation 1).
  I confirmed item 1 stays open post-fix: `git push --force-with-lease origin HEAD:main` from
  `feat/x` still exits 0. Worth noting that Scenario S3 uses that same refspec form in a detached
  context, where the block comes from the *checkout*, not the refspec — a reader could mistake S3 for
  refspec coverage. One clause would prevent that.
- **A rebase replaying onto main still creates commits the allowlist never sees**, because
  `git rebase --continue` produces no `COMMIT` fact. That is pre-existing, unchanged by this spec,
  and is the price of the (correct) decision that keeps rebases unblocked. Not cited; worth a line in
  ADR 0026 so the next reader does not rediscover it as a new bug.
- **YAGNI is exemplary.** Four explicit refusals to widen, a one-function change, no speculative
  machinery. The Mermaid diagram matches the `case` statement branch for branch. 222 lines / 1650
  words with no redundant Given/When/Then — token economy is fine.
- **`writing-secure-code` was read and found clean.** The spec touches shell-command parsing, so the
  skill applies; the change adds no parsing, no external input path, no secrets. Its §4
  "error-feedback loop first" is actively satisfied by checklist step 3 (write the tests, run them,
  confirm they fail before touching the hook).
- Checklist step 8's warning — keep the judge verdict uncommitted until the PR is open, because
  `judge-guard` compares `head_sha` to HEAD — is correct and matches this repo's recorded experience.

### Waivers

None requested, none applied.

---

## Round 2 — 2026-08-10T20:19:05Z — FAIL (3 violations)

`spec_blob_sha` `0ae6c6320105fe0dc1ce59e20f672a5255e0d3ad` · `head_sha` `0819db75229b2b31a98a080b3edf56bef5720603`
· branch `HEAD` (detached worktree — fittingly, the very state this spec is about)

### Layman summary

The redesign is a real improvement and the central engineering call is now right: swapping
`rev-parse --abbrev-ref` for `symbolic-ref` is correct, and I reproduced the six-state table on this
machine, on git 2.50.1, cell for cell. Three of round 1's four findings are genuinely closed. What is
still wrong is the same thing that was wrong in round 1, in new places: **the spec states as measured
fact several things that measurement contradicts.**

The big one: the spec has a section headed *"Why this does not block rebases."* It does block them. A
real `git rebase -i` stopped at an `edit` step leaves you on a detached HEAD, and the way you finish
that step is `git commit --amend`. I built that exact state and ran both hooks against it — the
current hook allows the amend (exit 0), the proposed hook refuses it (exit 2), and git-guard has no
bypass variable, so the operator is stuck mid-rebase. The spec's argument only considered
`git rebase --continue`, which really is invisible to the classifier; it never considered the amend.

The second: the spec's own headline piece of evidence — "the last scenario is the discriminator, it
passes only under `symbolic-ref`" — is false. I ran that scenario against the *current, unfixed* hook
and it already exits 0. So it proves nothing about which detection is installed, and checklist step 3
("run them and confirm each fails") is impossible to satisfy for 2 of the 6 scenarios.

### Measurements taken (all on this machine, git 2.50.1, bash 3.2.57)

| Claim in spec | Result |
|---|---|
| Six-state `abbrev-ref` vs `symbolic-ref` table | **Reproduces exactly**, all 6 rows incl. exit codes |
| Suite is "77 passing, 0 failing" | **True** — `git-guard: 77 passed, 0 failed` |
| Toolchain table (bash 3.2.57 / git 2.50.1 / py 3.9.6 / jq 1.7.1-apple) | **All four match installed** |
| `git branch HEAD` is refused | **True** — `fatal: 'HEAD' is not a valid branch name` |
| `classify-git-command.py:152` raises COMMIT only on literal `commit` | **True**, exact line |
| `git-guard.sh:164` is the empty-index message | **True**, exact line |
| Highest existing ADR is 0025 | **True** |
| `rules/gates.md` force-push stub text | **True**, verbatim at `gates.md:13` |
| phase-guard fails open on detached HEAD | **True** — `phase-guard.sh:515` exits 0 |
| `rules/` in neither allowlist nor exempt paths | **True** |
| Reflog shows `checkout … to origin/main` then 2 commits | **True**, verbatim |
| git-guard has no bypass environment variable | **True** — no `EXEMPT` in the file |
| S1/S3/S4/S5 fail before the fix, pass after | **True** (0→2 each) |
| S2, S6 "must fail before the fix" | **FALSE — both already exit 0 on the unfixed hook** |
| "Three things that work today stop working" | **FALSE — at least five cells change; two unlisted** |
| "Why this does not block rebases" | **FALSE — `git commit --amend` at an `edit` stop goes 0→2** |

Method: two copies of the hook (unmodified, and patched with the spec's exact `case` form), driven
through the production stdin path with `jq`-built PreToolUse payloads, against fixture repos whose
HEAD state was verified with `symbolic-ref`/`rev-parse` *before* each result was read. The rebase
finding used a genuine `GIT_SEQUENCE_EDITOR` interactive rebase stopped at `edit`, not a synthetic
detach.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `core-conduct/verification-before-write-down` *(persistent — round 1)* | `rules/core-conduct.md` | Verification precedes both the claim and the write-down | Decision → "Why this does not block rebases" + "Accepted costs — measured, not estimated" | The spec asserts rebases are unaffected and that exactly three behaviours change; measured, `git commit --amend` at an interactive-rebase `edit` stop flips 0→2 with no bypass, and a plain `git push --force-with-lease` from a non-repository cwd also flips 0→2 — neither is listed. |
| `core-conduct/verification-before-write-down-discriminator` | `rules/core-conduct.md` | Verification precedes both the claim and the write-down | Scenarios → "New behavior — must fail before the fix" + Checklist step 3 | "The last scenario is the discriminator: it passes only under `symbolic-ref`" is false — the unborn-`feat/x` scenario already exits 0 against the current `--abbrev-ref` hook (as does the detached-docs scenario), so the section heading and the instruction to "confirm each fails" are unsatisfiable for 2 of 6. |
| `writing-specs/good-bad-edge-cases` *(persistent — round 1)* | `skills/writing-specs/SKILL.md` | Good, bad, and edge-case scenarios — enumerate the edges | Scenarios → both blocks | Round 1's named gaps (unborn HEAD, cross-repo) are closed, but the enumeration is still not systematic: no scenario covers `git commit --amend` from a detached HEAD or `--force-with-lease` from a non-repository cwd, so a fully green suite would not detect either regression. |

### Notes (non-blocking)

- **`checkout_desc()` is sound for every reachable state I could construct.** Bare repo, cwd inside
  `.git`, unborn branch, and an exported `GIT_DIR` from a non-repo cwd all resolve through
  `symbolic-ref` and never reach the `""` arm, so the `rev-parse --git-dir` probe only runs where it
  is actually needed and answers correctly. Calling it on the refusal path only is the right call.
- The one state that fools it is unreachable by porcelain: `git symbolic-ref HEAD refs/remotes/...`
  yields `branch 'origin/main'` and stands the guards down. `git checkout origin/main` detaches
  instead, so the incident in the Background is not this shape. Recorded so it is not re-derived.
- **Cross-repo messages describe the cwd, not the target.** Scenario 4's `not a git repository` is
  true of the cwd while a repository *is* being committed to; the same applies to a detached cwd
  targeting another repo. Defensible ("the checkout is…"), but one clause would stop an operator
  reading it as a statement about where the commit lands.
- **The spec path is correct for this repo.** `writing-specs` defers to `docs/superpowers/specs/`,
  but the repo layer's one-canonical-file discipline (`rules/gates.md`) puts feature-scale work with
  frontmatter + checklist at `docs/features/<name>.md`. Project rules win; not cited.
- **Round 1 findings 3 and 4 are closed.** Four exact stderr strings with a named `%s` binding, and
  the checklist now separates hook edits (steps 4, 5) from test edits (steps 2, 3, 6).
- **YAGNI, KISS and security remain clean.** One helper swapped, one helper added, four refusals to
  widen. `writing-secure-code` re-read and applied: the refusal strings take the branch name as a
  `printf` *argument*, not as part of the format, so a `%`-bearing branch name cannot inject.
- Suggested fix order: correct the rebase claim first (it is the one that would bite a user), then
  demote S2/S6 into the regression block where they belong, then close the matrix — three guards ×
  three branchless states is a table small enough to enumerate exhaustively rather than by example.

### Waivers

None requested, none applied.

---

## Round 3 — 2026-08-10T22:56:50Z — FAIL (3 violations)

- **spec blob:** `33cb04d9f4f14090fc05e752e1ff390a2a7dbc3c` · **repo:** memsearch-freshness (worktree)
- **HEAD:** `0819db75229b2b31a98a080b3edf56bef5720603` · **branch:** detached (`phase: planning`, no branch cut yet)
- **rule sources read:** `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md` (shell-execution territory), `rules/gates.md`, `CLAUDE.md`.
  No `.claude/project-standards.md` exists in this worktree.

### Layman summary

The design itself is sound, and this round I could finally prove it rather than take its word. I
rebuilt the author's experiment from scratch with **four** versions of the hook — today's, the one the
spec proposes, the proposed one with the rebase escape hatch removed, and a cruder alternative fix —
and ran every scenario against all four. The proposed design is the only one that gets every row
right. That is the strongest evidence any round has produced, and the two claims that were false last
round are now genuinely true.

What is still wrong is smaller and of one kind: **the spec says it measured more than it measured.**
One table announces that every cell in it was executed, not reasoned about. Nine cells; six were
executed. I ran the missing ones myself and they are all correct — so nothing in the design is wrong,
but the sentence promising evidence is writing a cheque the experiment did not cash, and that is the
third round running that this exact habit has been the finding.

Two smaller things. The escape hatch has one safety rail — *a checkout that is plainly named `main`
stays guarded even mid-rebase* — and that rail is written in prose with no test behind it. I built the
case and confirmed the rail holds today, but if someone later moves one line of code the rail
disappears silently and none of the fourteen planned tests notice. And the spec is 436 lines for a
twenty-line change; about fifty of those lines are test scenarios rewritten in longhand from a table
that already says the same thing — which the spec itself, two paragraphs earlier, promises not to do.

### What I re-ran (nothing below is taken from the spec or the caller)

Independent four-variant harness, fresh fixture directory per row (no reuse, so no fixture can
inherit a prior row's state): `/tmp/judge-audit/audit.sh`. git 2.50.1 (Apple Git-155), bash
3.2.57(1), python3 3.9.6, jq 1.7.1-apple.

| Fixture / command | ORIG | SPEC | no carve-out | crude `--abbrev-ref` fail-closed |
|---|---|---|---|---|
| detached · `git commit` (src staged) | 0 | **2** | 2 | 2 |
| detached · `push --force-with-lease` | 0 | **2** | 2 | 2 |
| non-repo · `cd /elsewhere/repo && git commit -m msg -- src/app.sh` | 0 | **2** | 2 | 2 |
| non-repo · `push --force-with-lease` | 0 | **2** | 2 | 2 |
| unborn `main` · `git commit` (src staged) | 0 | **2** | 2 | 2 |
| unborn `feat/x` · `git commit` (src staged) | 0 | **0** | 0 | **2 ← fails** |
| rebase `edit` stop · `git commit --amend --no-edit` | 0 | **0** | **2 ← fails** | 0 |
| cherry-pick conflict · `git commit` | 0 | **0** | **2 ← fails** | 0 |
| `feat/x` · commit / lease-push / bare force-push | 0/0/2 | 0/0/2 | 0/0/2 | 0/0/2 |

The author's own script (`scratchpad/measure-matrix.sh`) also re-ran clean: 12 rows `ok`, empty-index
probe 0 → 2. Its patch anchor matches `hooks/git-guard.sh` exactly (the script asserts on drift), and
its patched body is semantically identical to the spec's Decision block.

**Fixture audit — the specific failure mode the caller flagged.** Both suspect fixtures genuinely
reach the state they are named for; neither pre-creates the state under test nor silently no-ops:

| Fixture | `symbolic-ref` | marker on disk | staged |
|---|---|---|---|
| `rebase_edit` | *fatal: not a symbolic ref* | `rebase-merge` | `src/f1.sh` (source) |
| `cherry_conflict` | *fatal: not a symbolic ref* | `CHERRY_PICK_HEAD` | `src/app.sh` (source) |
| `unborn_main` | `main` | — | `src/app.sh` |

**No row passes for a reason other than the one claimed.** Rows 8 and 9 flip to 2 the moment the
carve-out is removed, so they are testing the carve-out and not something incidental; row 7 flips to
2 under the crude alternative, so it is testing `symbolic-ref` specifically.

**The carve-out marker table (spec:110-119) is correct in all six rows** — re-derived independently:
rebase-conflict → `rebase-merge`; `git rebase --apply` conflict → `rebase-apply`; detached revert
conflict → `REVERT_HEAD`; detached merge conflict → `MERGE_HEAD`; all four branchless. This is the
table whose predecessor was false at round 2.

**Other measured claims, all verified:** suite is `77 passed, 0 failed`; ADR high-water is 0025 so
0026 is free; `classify-git-command.py:152` is exactly `if subcommand == "commit":`; the quoted
`rules/gates.md` force-push stub exists verbatim; `git branch HEAD` → `fatal: 'HEAD' is not a valid
branch name`; bash 3.2.57(1), git 2.50.1, python3 3.9.6, jq 1.7.1-apple all match the pinned table;
no absolute or home paths anywhere in the spec.

### Violations

| # | id | rule source | where | why |
|---|---|---|---|---|
| 1 | `core-conduct/verification-before-write-down` **(PERSISTENT r1→r2→r3)** | `rules/core-conduct.md` — Session Defaults | "What changes — measured, not estimated" (spec:161-176) | "Every cell below was **run** … not reasoned about. All twelve reproduced" describes a nine-cell table of which the referenced script runs six; the op-in-progress row's empty-index and `--force-with-lease` cells were never executed, and the non-repo × staged-source cell is unconstructable because no index exists outside a repository. |
| 2 | `writing-specs/good-bad-edge-cases` **(PERSISTENT r1→r2→r3)** | `skills/writing-specs/SKILL.md` — "Good, bad, and edge-case scenarios" | "Scenarios" coverage matrix (spec:260-275) and checklist step 3 (spec:420) | The carve-out's only stated bound — "a *named* `main`/`master` checkout stays guarded whether or not a sequencer is running" (spec:141-146) — has no matrix row and no scenario, so no planned test fails if a later edit hoists `sequencer_in_progress` above the `case` and opens the guard on `main`. |
| 3 | `writing-specs/tokenization-economy` *(new this round)* | `skills/writing-specs/SKILL.md` — "Tokenization Is a Hard Constraint" | "Regressions — green before and after" (spec:324-378) | 54 lines of Gherkin restate matrix rows 6-14 while adding zero assertions (the block contains no `stderr contains` line at all), which is the redundant-Given/When/Then bloat the rule names by name and contradicts the spec's own policy at spec:257-258. |

**Detail on 1.** I grepped the referenced script: its only pushes are in the `detached`, `nonrepo` and
`feature` fixtures, and its only empty-index probe is `detached` + `git reset` — there is no
sequencer fixture in either column. I then ran the two missing cells myself: `rebase_edit_empty ·
git commit` → 0 → 0, `rebase_edit · push --force-with-lease` → 0 → 0, `cherry_conflict · push
--force-with-lease` → 0 → 0. **Every value in the table is true.** The defect is the provenance
sentence, not the design — and the count "twelve" belongs to the twelve-row Scenarios measurement,
not to this nine-cell table. Fix is one clause: say which cells were run and which follow from the
code path, exactly as the spec already does for revert and merge at spec:196-200.

**Detail on 2.** Round 2's two named cells are genuinely **closed** — amend-from-detached is now row 8
and leased-push-from-non-repository is now row 4, both measured. This is a *new* cell created by the
round-3 carve-out. I built it (merge conflict on a named `main`, source staged) and it exits 2 under
all four variants, so the property holds today; it is simply unpinned. One `run_case` closes it.

**Detail on 3.** Nine of the fourteen scenarios are longhand restatements of a table row — e.g.
"Source on a feature branch stays allowed / Given branch feat/x is checked out / And src/app.sh is
staged / When … / Then it exits 0" is row 11 verbatim. The five *new-behaviour* scenarios do carry
stderr assertions and earn their space; the regression block does not. The rest of the 436 lines is
load-bearing and should not be cut.

### Closed since round 2

- **`core-conduct/verification-before-write-down-discriminator` — CLOSED, verified true.** The
  replacement reasoning ("no single row proves the design; rows 7, 8 and 9 held green together with
  1-5 are what pin it") is correct on measurement. Rows 8 and 9 fail under a no-carve-out
  implementation; row 7 fails under the cruder `--abbrev-ref` fail-closed alternative; rows 1-5 pass
  under both. One nit, not cited: "7 fails under an `--abbrev-ref` implementation" is true of the
  *cruder alternative* named in the preceding sentence and false of the *status quo* (under which
  row 7 exits 0 and passes). The referent is recoverable from context; a two-word qualifier would
  remove the second reading.
- **The rebase section is genuinely fixed.** Round 2's finding — that `git commit --amend` at a
  `rebase -i` `edit` stop was blocked — is now both true and handled: measured 0 → 0 under the
  carve-out, 2 without it.
- **The missing lease-push-from-non-repository cell is now present** as cost 3 and Scenarios row 4,
  and measured.

### Notes (non-blocking)

- **The class-level carve-out is *not* a YAGNI violation, and I checked rather than assumed.** With
  the carve-out removed, a detached revert conflict and a detached merge conflict both exit 2 — so
  the widening from rebase-only to the five markers fixes demonstrated instances, not hypothetical
  ones. It is also surfaced for the user rather than silently decided (spec:148-151), which is what
  the human-owned-trade-offs rule asks for. My recommendation to the user: **approve the widening.**
- **Stale marker → permanently disarmed guard.** `sequencer_in_progress` trusts on-disk state, which
  is the right instinct, but a crashed or abandoned rebase leaves `.git/rebase-merge` behind and the
  guard then stands down for *every* branchless commit in that repo until someone runs
  `git rebase --abort`. Low probability and self-inflicted; worth one sentence in ADR 0026 so it is
  a known bound rather than a surprise.
- **The hook header keeps its "'cannot tell' must not mean 'allow'" line** (`git-guard.sh:36-38`),
  which the spec quotes as its own premise and the carve-out now excepts. Not cited, because the
  spec's proposed inline comment already says "except while git has an operation in progress (see
  the file header)" — the in-file signal exists. Amending the header sentence would still be tidier.
- **The matrix's non-repo × "staged source" cell cannot exist.** Outside a repository there is no
  index, so that column collapses into the empty-index column; cost 1's example is in fact the
  pathspec/empty-index form. Cosmetic, but it is one of the cells the provenance sentence covers.
- **Housekeeping, unrelated to the spec but relevant to the caller's fixture worry.** The worktree
  index right now holds a leaked fixture from an *earlier* measurement script: a staged path named
  `"On branch main\n\nInitial commit\n…/tmp/wtaEky/det/src/app.sh"`, plus a matching untracked
  directory. Something before round 3 escaped its sandbox into the real repo. `measure-matrix.sh` and
  my own harness are both clean (`mktemp -d`, `cd || exit 99`), but this should be unstaged and
  removed before the branch is cut.
- **Spec path is correct.** `writing-specs` defers to `docs/superpowers/specs/`; the repo layer's
  one-canonical-file discipline puts feature-scale work at `docs/features/<name>.md`. Project rules
  win. Not cited, as in rounds 1 and 2.
- **Security clean.** `writing-secure-code` re-read; nothing in its territory changes. Refusal
  strings still pass the branch name as a `printf` argument rather than as format, so a `%`-bearing
  branch name cannot inject.
- **Suggested fix order:** (1) rewrite the provenance sentence to name the six executed cells and
  mark the rest as following from the code path; (2) add one `run_case` row for named-`main` +
  sequencer; (3) delete the nine redundant regression scenarios, keeping the matrix and the five
  stderr-bearing new-behaviour scenarios. All three are edits to prose and one test line — the
  design needs no change.

### Waivers

None requested, none applied.

---

## Round 4 — 2026-08-11T01:45:26Z — FAIL (3 violations)

- **spec blob:** `be836773dcf21eeffcbfbd8f6e893651280b833c` · **repo:** memsearch-freshness (worktree)
- **HEAD:** `0819db75229b2b31a98a080b3edf56bef5720603` · **branch:** detached (`phase: planning`, no branch cut)
- **rule sources read:** `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md` (shell-execution territory), `rules/gates.md`, `CLAUDE.md`.
  No `.claude/project-standards.md` exists in this worktree.
- **Confidence: high** — every finding below was executed on this machine against four hook variants,
  not inferred.

### Layman summary

The engineering is now genuinely good, and this round I could prove the two findings that had survived
three rounds are actually closed rather than reworded. The new safety rail works: I built a rebase
started from `main`, staged a source file, and ran the commit past four different versions of the
hook — today's hook lets it through, the version without the rail lets it through, and the version
the spec proposes blocks it. I then let the rebase finish and confirmed the file really does land on
`main` when nothing blocks it. So the hole the sibling judge found was real and the fix closes it.

What is still wrong is one thing wearing two faces, plus a broken pointer.

**The cost table was not updated when the rail was added.** The spec has a table headed "What changes
— measured, not estimated" whose middle row says that while a git operation is in progress, nothing
changes: `0 → 0` in all three columns. That is now false in exactly the case the new rail creates. I
measured a rebase started from `main` in all three columns — staged source, empty index, and
`--force-with-lease` — and every one of them goes `0 → 2`. The spec's own scenario row 15 says `0 → 2`
for that same state, so the document contradicts itself, and the list of four "accepted costs" never
mentions that a hand-written commit during a rebase on `main` is now refused with no bypass and with
remedy advice git itself rejects. That is a real cost to a real operator, and it is the only one that
is not written down.

**One sentence about `git am` is wrong.** The spec says `git am` "runs on a named branch, so it never
reaches this arm at all". I ran `git am` from a detached HEAD; it stops with a `rebase-apply` marker,
no `head-name`, and an empty `symbolic-ref` — it reaches the arm and stands the guard down. The
*outcome* is safe for the same reason cherry-pick is safe (nothing moves a branch), so no design
change is needed; the stated reason is simply false, and it is the sentence that bounds the new rail.

**And the evidence has been deleted.** The spec names three scripts as the provenance for thirteen
measured rows and tells the reader to "re-run it rather than trusting this table". `scratchpad/` does
not exist, is not in `.gitignore`, has never been committed on any branch, and none of the three
filenames exists anywhere on this machine. The round-3 judge could re-run `measure-matrix.sh`; I
could not. I reproduced every row myself and they are all correct — so nothing in the table is wrong,
but the auditability the spec advertises is not there.

### What I re-ran (nothing below is taken from the spec or the caller)

Four hook variants driven through the production stdin path with `jq`-built `PreToolUse` payloads,
each fixture in its own `mktemp -d` and each asserted into its claimed state *before* any result was
read (`/tmp/cj4/audit.sh`, `audit2.sh`, `audit3.sh`). Variants: **orig** (unmodified),
**spec** (the Decision block verbatim), **loose** (spec minus the `head-name` clause),
**hoist** (spec with `sequencer_in_progress` moved above the `case`).

Fixture-state assertions, printed before every probe:

| Fixture | `symbolic-ref` | marker | `head-name` |
|---|---|---|---|
| plain detached | *none* | — | absent |
| rebase from `feat/x` | *none* | `rebase-merge` | `refs/heads/feat/x` |
| rebase from `main` | *none* | `rebase-merge` | `refs/heads/main` |
| `rebase --apply` from `main` | *none* | `rebase-apply` | `refs/heads/main` |
| cherry-pick conflict detached | *none* | `CHERRY_PICK_HEAD` | absent |
| `git am` conflict **detached** | *none* | `rebase-apply` | **absent** |
| rebase started **detached** | *none* | `rebase-merge` | `detached HEAD` |
| named `main` + merge conflict | `main` | `MERGE_HEAD` | absent |

Exit codes, `orig / spec / loose`:

| Row | orig | spec | loose |
|---|---|---|---|
| 1 detached, source staged, commit | 0 | **2** | 2 |
| 2 detached, lease-push | 0 | **2** | 2 |
| 3 non-repo, `cd /elsewhere/repo && git commit … -- src/app.sh` | 0 | **2** | 2 |
| 4 non-repo, lease-push | 0 | **2** | 2 |
| 5 unborn `main`, commit | 0 | **2** | 2 |
| 6 detached, docs only | 0 | 0 | 0 |
| 7 unborn `feat/x`, commit | 0 | 0 | 0 |
| 8 rebase-from-`feat/x` edit stop, `commit --amend` | 0 | 0 | 0 |
| 9 cherry-pick conflict detached, commit | 0 | 0 | 0 |
| 10 detached mid-rebase, `add && rebase --continue` | 0 | 0 | 0 |
| 11/12/13 `feat/x` commit / lease-push / bare force | 0/0/2 | 0/0/2 | 0/0/2 |
| 14 `main`, docs only | 0 | 0 | 0 |
| **15 rebase-from-`main`, source staged** | 0 | **2** | **0 ← rail works** |
| **16 named `main` + `MERGE_HEAD`** | 2 | 2 | 2 |
| `rebase --apply` from `main`, commit | 0 | **2** | 0 |
| `git am` **detached**, commit | 0 | **0** | 0 |
| rebase started **detached**, commit | 0 | 0 | 0 |

**Both persistent findings are genuinely closed, and I mutation-tested the closures rather than
reading them.** Row 15 flips `2 → 0` the moment the `head-name` clause is dropped, so it really does
pin bound 1. Row 16 flips `2 → 0` against a purpose-built **hoist** variant with
`sequencer_in_progress` moved above the `case`, so it really does pin bound 2 — the spec's claim about
what row 16 detects is measurably true. The regression Gherkin is down from nine scenarios to four,
rows 6/7/10–14 carry a stated reason for having none, and all four survivors have non-obvious setup.

**End-to-end, the defect the rail closes is real:** with the loose variant I committed `src/leak.sh`
during a `rebase -i` started on `main`, ran `--continue`, and `git ls-tree -r main` lists the file.
Unreviewed source reaches `main`. The spec's claim is exact.

**Both corrected sentences are now true.** `git switch -c` mid-rebase → `fatal: cannot switch branch
while rebasing`, the `rebase-merge` marker survives, and `--continue` afterwards succeeds and lands on
`main`. Named `main` + `MERGE_HEAD` → hook exits 2 and `git switch -c` → `fatal: cannot switch branch
while merging`. Both were false-in-the-other-direction in an earlier draft; both are now stated at
their true size.

**Repo facts, all verified this round:** suite is `git-guard: 77 passed, 0 failed`; ADR high-water is
`0025-verification-precedes-the-write-down.md`, so 0026 is free; `classify-git-command.py:152` is
exactly `if subcommand == "commit":`; `git-guard.sh:164` is the empty-index message; `gates.md:13`
carries the quoted force-push stub verbatim; bash 3.2.57(1) `arm64-apple-darwin25`, git 2.50.1
(Apple Git-155), Python 3.9.6, jq-1.7.1-apple all match the pinned table; the six-state HEAD table
spot-checks correct (unborn → `HEAD`/rc 128 vs `main`; orphan → `HEAD` vs `brandnew`; non-repo → both
fail); no absolute or home paths anywhere in the spec. My harness left the real index untouched.

### Violations

| # | id | rule source | where | why |
|---|---|---|---|---|
| 1 | `core-conduct/verification-before-write-down` **(PERSISTENT r1→r2→r3→r4)** | `rules/core-conduct.md:9` | "What changes — measured, not estimated" (spec:206–231) | The row `detached, operation in progress → 0 → 0 (carve-out)` is false for the sub-case the round-4 rail creates: measured, a rebase whose `head-name` is `refs/heads/main` goes `0 → 2` in all three columns, the closing sentence claiming exactly one further changed cell outside the matrix misses three inside it, and none appears in accepted costs 1–4 — while the spec's own scenario row 15 states `0 → 2` for the same state. |
| 2 | `core-conduct/verification-before-write-down-git-am` *(new this round)* | `rules/core-conduct.md:9` | `sequencer_in_progress` comment (spec:152–154) | "`git am` writes no head-name but runs on a named branch, so it never reaches this arm at all" is false — a `git am` stopped on a conflict from a detached HEAD writes `rebase-apply` with no `head-name`, reaches the `""` arm and stands the guard down (measured); the outcome is safe for the cherry-pick reason, but the sentence bounding the new clause is wrong. |
| 3 | `writing-specs/version-control-not-chat` *(new this round)* | `skills/writing-specs/SKILL.md:53,55` | Provenance notes (spec:212–213 and spec:348–350) | The per-row provenance added this round rests on `scratchpad/measure-matrix.sh`, `verify-carveout-hole.sh` and `measure-headname.sh`, and the spec instructs "re-run it rather than trusting this table" — none of the three exists in the worktree, in `.gitignore`, in `git log --all`, or anywhere on this machine, so the evidence cannot be indexed, diffed or verified against. |

**Rule text cited**

1. & 2. `rules/core-conduct.md:9` — "Verification precedes both the claim and the write-down — never
   state that something works, is fixed, or is done, and never record that claim in a durable artifact
   (ADR, memory file, commit message, PR body, handoff, spec), until you have actually run it and
   re-read the output. … When something is unverified, write what you checked and what you did not."
3. `skills/writing-specs/SKILL.md:53` — "Version control, not chat: … a committed spec can be indexed,
   diffed, and verified against." With `:55` — "Reference specs by path — point the agent at the
   committed file rather than re-pasting its contents, so a single stored version stays authoritative."

**Detail on 1.** Measured on the rebase-from-`main` fixture: staged source `0 → 2`, empty index
`0 → 2`, empty index + pathspec `0 → 2`, `--force-with-lease` `0 → 2`. The stated reasoning under the
table — "both follow from `on_main` returning false" — is true only where the carve-out applies;
`on_main` returns **true** here, which is the whole point of bound 1. The operator-facing cost is real
and unlisted: a hand-written `git commit` during `git rebase -i` on `main` is refused, git-guard has
no bypass variable, and `git switch -c` is rejected by git — the exact "stranded operator with
unfollowable advice" harm the spec catalogues two sections earlier. Fix is a fourth matrix row
(`detached, rebase whose head-name is main/master → 2 / 2 / 2`) plus a fifth accepted cost. The spec
already knows the fact (spec:194–196 and spec:305–307); only the cost section is stale.

**Detail on 2.** Constructible in five commands: `format-patch`, `checkout --detach`, a conflicting
commit, `git am`. One clause fixes it — a detached `am` *does* reach this arm and is safe for the same
reason cherry-pick is, because it moves no branch.

**Detail on 3.** Not a truth defect: I reproduced all thirteen rows independently and every
Before/After pair is correct. It is an auditability defect — the round-3 judge could re-run
`measure-matrix.sh` and I could not, which is the decay the rule names. Either commit the scripts or
drop the "re-run it" instruction and state the rows as recorded planning results; checklist steps 2–3
already convert them into durable `run_case` rows, which is the better home.

### Closed since round 3

- **`writing-specs/good-bad-edge-cases` (persistent r1→r2→r3) — CLOSED, mutation-tested.** Both
  carve-out bounds now have a matrix row *and* a scenario, and each row measurably fails under exactly
  the mutation it claims to detect (row 15 under **loose**, row 16 under **hoist**). Not a rewording.
- **`writing-specs/tokenization-economy` (r3) — CLOSED.** Nine regression scenarios cut to four; the
  survivors all have non-obvious setup and two carry assertions beyond the exit code; rows 6, 7 and
  10–14 state why they have no Gherkin. The file grew 436 → 493 lines, but every added line is
  load-bearing (per-row provenance, the `head-name` clause and its measurement table, rows 15/16, two
  corrections).
- **The provenance sentence itself is fixed.** Round 3's blanket "every cell was run" is gone; three
  of nine cells are marked not-executed with their grounds, and the two delegated to my predecessor
  match what that card actually recorded (`0 → 0`). The remaining defect is the *values* in one row,
  not the provenance prose.

### Notes (non-blocking)

- **No new unbounded case from the `head-name` clause.** I enumerated every shape that reaches it: a
  rebase started detached writes `head-name = detached HEAD` (stands down, moves no branch); `git am`
  writes none (stands down, moves no branch); `rebase --apply` from `main` writes
  `refs/heads/main` and is correctly guarded; a rebase from `feat/x` moves only `feat/x`. The clause
  matches two exact strings, so no glob or partial-name widening is possible.
- **The lease-push half of the carve-out is disclosed but not justified.** The stated rationale is
  "let the operator finish the operation" — and finishing an operation never requires a force-push.
  Standing Guard 2 down mid-sequencer follows only from `on_main` being one shared helper. Harmless
  (reachable only while branchless) and honestly recorded in the matrix, but one sentence would
  explain why the widening is accepted rather than incidental.
- **The stale-marker bound is still unrecorded** — round 3 flagged it, and the ADR obligations still
  do not mention it. An abandoned `.git/rebase-merge` disarms the guard for every branchless commit in
  that repo until `git rebase --abort`. With bound 1 a stale marker *from main* now keeps the guard
  on, which narrows it. Still worth one sentence in ADR 0026.
- **Fixture-integrity warning for the implementer.** `git reset` clears `CHERRY_PICK_HEAD` — I hit
  this building an empty-index cherry-pick fixture and the row silently became a plain-detached row
  (`0 → 2` instead of `0 → 0`). Checklist step 2 already demands each helper assert the state it
  claims; this is the concrete way that assertion earns its keep.
- **Security clean.** `writing-secure-code` re-read (shell-execution territory). The new code adds
  `cat "$dir/head-name"` and `git rev-parse --git-path`, both quoted; the `case` subject is data and
  the patterns are literals, so a crafted `head-name` cannot inject; `checkout_desc` passes the branch
  name as a `printf` argument, never as a format. No secrets, no new external input, no dependencies.
- **KISS/DRY/YAGNI clean.** One helper swapped, one added, `git-guard.sh` grows ~198 → ~223 lines
  (limit 400). Four explicit refusals to widen; the deliberate fail-open is surfaced as a human-owned
  decision rather than silently taken.
- **Spec path is correct**, as in rounds 1–3. `writing-specs:54` defers to `docs/superpowers/specs/`;
  the repo layer's one-canonical-file discipline puts feature-scale work at `docs/features/<name>.md`
  and project rules win.
- **Suggested fix order:** (1) add the fourth matrix row and the fifth accepted cost — that is the one
  that would bite an operator; (2) correct the `git am` clause; (3) either commit the scratch scripts
  or drop the "re-run it" instruction. All three are prose edits; the design needs no change.

### Waivers

None requested, none applied.

---

## Round 5 — 2026-08-11T02:06:28Z — FAIL (2 violations)

- **spec blob:** `0eaab98ba1e74056f262af79d05f842ca2afaacf` · **repo:** memsearch-freshness (worktree)
- **HEAD:** `0819db75229b2b31a98a080b3edf56bef5720603` · **branch:** detached (`phase: planning`, no branch cut)
- **rule sources read:** `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md` (shell-execution territory), `rules/gates.md`, `CLAUDE.md`.
  No `.claude/project-standards.md` exists in this worktree.
- **Confidence: high** — every closure claim below was re-measured on this machine; nothing is taken
  from the caller's summary.

### Layman summary

All three of last round's findings are genuinely fixed, not reworded — I checked each one by hand.
The cost table now carries the missing fourth row and a fifth accepted cost for the operator who gets
refused mid-rebase, and the labels, the row and the cost list finally agree. The `git am` comment now
describes what git actually does: I ran an `am` from a detached HEAD and it does write a
`rebase-apply` marker with **no** `head-name` file, so it falls through exactly as the new comment
says, and it is safe for the reason the comment now gives. And the spec has stopped claiming its
tables can be re-run — it says plainly they are reports until the scripts land, which is the honest
version and the only one available while the phase gate forbids writing to `hooks/`.

What is still wrong is one thing, twice: **the spec's newest requirements never reached the part of
the document the implementer actually works from.**

The first is the brand-new test row 17 — the one added because the sibling judge proved row 15 cannot
see a dropped `rebase-apply`. It is in the scenario table, and the prose says it must fail before the
fix. But the checklist still says "add all 16 matrix rows", still tells the implementer to confirm
"rows 1–5 and 15 fail while 6–14 and 16 pass", never asks for a `rebase --apply` fixture, and the
carve-out section still says the bounds have "a test row (matrix rows 15 and 16)". Someone building
from the checklist ships 16 rows and the one row that catches that mutation quietly never exists.

The second is the message the operator sees. The spec now argues — correctly — that a detached HEAD
mid-rebase and a plain detached HEAD must not print the same sentence, and that the remedy line must
say *finish or abort the operation* when git would refuse a branch switch. Neither of those exists in
the contract that follows: the `checkout_desc` function printed in the spec has two cases, not three,
and the table headed "Replacement text (exact)" gives one unconditional remedy string and no wording
at all for the third case. No scenario asserts either. That is the same defect round 1 cited on this
same section — the output contract is required to change and its text is not stated — recurring on
the new material.

Neither is a design problem. Both are paragraph-sized edits, and the engineering underneath is sound.

### What I re-ran (nothing below is taken from the spec or the caller)

| Claim checked | Method | Result |
|---|---|---|
| `git am` from detached HEAD reaches the carve-out arm | built the conflict in `/tmp`, listed the marker dir | `symbolic-ref` empty, `rebase-apply` present, **no `head-name` file** (`0001 abort-safety apply-opt … utf8`) → falls to `return 0`. Comment is now **true** |
| row 17 state (`rebase --apply` from `main`) | `git rebase --apply up` after a conflicting `main` commit | `symbolic-ref` empty, `abbrev-ref` = `HEAD`, `rebase-apply` present, `head-name` = `refs/heads/main` → tightened returns 1, `on_main` true, exit 2. **0 → 2 confirmed by construction** |
| HEAD-state table, all six rows | fresh repos in `/tmp` | unborn `main` → `symbolic-ref` `main`, `abbrev-ref` exits 128; orphan → `brandnew`; non-repo → both exit 128; `git branch HEAD` → `fatal: 'HEAD' is not a valid branch name`. **All correct** |
| suite is "77 passing, 0 failing" | ran `hooks/git-guard.test.sh` | `git-guard: 77 passed, 0 failed` ✓ |
| pinned toolchain matches what is installed | `--version` on each | bash 3.2.57(1)-release (arm64-apple-darwin25), git 2.50.1 (Apple Git-155), python3 3.9.6, jq-1.7.1-apple ✓ all four exact |
| `classify-git-command.py:152` | read the file | line 152 is `if subcommand == "commit":` ✓ |
| `git-guard.sh:164` empty-index path | read the file | line 164 is the `nothing is staged yet` printf ✓ |
| "phase-guard exempts `docs/*` but not `hooks/*`" | read `phase-guard.sh:287-290` | `CODING_MEMORY.md\|coding-memory/*\|docs/*\|.claude/*\|settings.json` and `projects/*/memory/*` — `hooks/` absent ✓ |

**Round-4 closure verdict, item by item:**

| Round-4 id | Status | Evidence |
|---|---|---|
| `core-conduct/verification-before-write-down` (rounds 1–4) | **CLOSED** | Matrix now has four rows; `head-name`-is-main row reads `0 → 2` in all three columns; first two columns labelled *intended*, third *collateral*; cost 5 added and names the refusal, the absent bypass and the unfollowable remedy. Matrix ↔ labels ↔ cost list are mutually consistent. |
| `core-conduct/verification-before-write-down-git-am` (round 4) | **CLOSED** | Re-measured; the rewritten comment states the real mechanism and the real safety reason. |
| `writing-specs/version-control-not-chat` (round 4) | **CLOSED** | The "re-run it" instruction is gone; the spec twice marks the tables as reports rather than reproducible evidence, and the first checklist step lands the scripts under `hooks/` with per-fixture assertions. The `phase: planning` gate makes any stronger fix impossible today. |

### Violations

| # | id | rule_source | where | why |
|---|---|---|---|---|
| 1 | `writing-specs/unambiguous-requirements` | `skills/writing-specs/SKILL.md` | Checklist steps 3–5 + the carve-out's "Two bounds" paragraph, against Scenarios row 17 | Row 17 is in the matrix and in the must-fail list, but the checklist still says "Add all **16** matrix rows", still verifies only "rows 1–5 and 15 fail while 6–14 and 16 pass", lists no `rebase --apply` fixture helper, and the bounds paragraph still reads "each has a test row (matrix rows 15 and 16)" — so the implementer builds 16 rows and the mutation row 15 provably cannot see stays uncovered. |
| 2 | `writing-specs/api-contracts` *(recurrence of round 1, same section)* | `skills/writing-specs/SKILL.md` | "The message contract" → `checkout_desc` code block + "Replacement text (exact)" table + Checklist step 6 | The section requires a third rendering (`a detached HEAD mid-rebase that will update '<branch>'`) and a sequencer-aware remedy line, but the normative `checkout_desc` body has two cases, the exact-text table gives one unconditional remedy string and no third-case format, and no scenario asserts either — the output contract is again required to change with its text unstated. |

**Rule text cited**

1. `skills/writing-specs/SKILL.md:28` — "Good, bad, and edge-case scenarios: state explicitly what
   correct looks like, what wrong looks like, and enumerate the edges. Anything you leave implicit,
   the agent infers — and inference is where the defects come from." With `SKILL.md:24`
   ("Requirements … the agent can satisfy and you can check") and `SKILL.md:13-14` (a spec is
   maintained with production rigor; drift is a correctness problem, not tidiness).
2. `skills/writing-specs/SKILL.md:25` — "Database schemas and API contracts: these give the agent the
   real data structures and interface boundaries to build against, instead of letting it improvise
   shapes that other components then fail to match." The four stderr strings are this hook's output
   contract and are asserted by tests.

### Notes (non-blocking)

- **Cost 2's escape hatch is false for one cell it now covers.** The new third matrix row makes
  `--force-with-lease` from a detached HEAD *during a rebase from `main`* a `0 → 2` collateral cell;
  cost 2 covers "from a detached HEAD" and offers `git switch -c <branch>`, which git refuses while a
  rebase is running (the spec establishes this elsewhere). One clause on cost 2, or a pointer to cost
  5, would settle it.
- **The carve-out measurement table under-records row 17.** Its `rebase --apply` row shows `—` for
  loose and a prose state description for tightened, while the scenario table asserts a measured
  `0 → 2`. The numbers exist; putting them in both tables removes the appearance of two provenance
  standards.
- **532 lines, under the 800 cap, but the carve-out rationale now appears in five places** (Decision
  prose, the code comment, the two-bounds list, the matrix commentary, the scenario commentary) plus
  a sixth in the ADR obligation. Not cited — every copy was demanded by an earlier round's finding —
  but the ADR is the right home for the long-form version once written.
- **The spec file is still untracked** (`?? docs/features/git-guard-detached-head.md`). Checklist
  step 1 cuts the branch, which is where it lands; committing it early would make each judged blob
  diffable against the last.
- **Security clean.** `writing-secure-code` re-read (shell-execution territory). No new external
  input, no secrets, no dependencies; `case` subjects are data and patterns are literals; `printf`
  format strings stay literal with the branch name passed as an argument. §4's error-feedback-loop
  is satisfied by the write-tests-first, confirm-they-fail step ordering.
- **Tests and implementation stay in separate checklist steps** — round 1's
  `core-conduct/tests-and-implementation-separate` finding remains closed.
- **Suggested fix order:** (1) propagate row 17 into the three checklist steps and the bounds
  paragraph — that is the one that loses real coverage; (2) give `checkout_desc` its third case and
  the remedy line its exact alternate text in the contract table, plus one stderr assertion.
  Both are prose edits; the design needs no change.

### Waivers

None requested, none applied.

---

## Round 6 — 2026-08-11T02:17:01Z — FAIL (3 violations)

`spec_blob_sha` `240f345dc0f2a8fbf75eeb989354cd35b791163a` · `head_sha`
`0819db75229b2b31a98a080b3edf56bef5720603` · branch `HEAD` (detached worktree) · base `origin/main`
`1b983d9`
Rule sources read: `rules/core-conduct.md` (worktree copy — the judged layer),
`skills/writing-specs/SKILL.md`, `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`.
No `.claude/project-standards.md` in this repo. Confidence: **high** — every finding below was
executed against patched copies of the hook in purpose-built repositories, not inferred.

### Layman summary

The engineering is right and I could not break it. I rebuilt the hook three ways — the spec's version,
one with `master` dropped from the fence, one with `rebase-apply` dropped from the loop — and drove all
of them with real fixtures. Every exit code the spec reports reproduced exactly, including the new
round-6 measurement: a `rebase --apply` started from `master` leaves HEAD branchless with
`head-name = refs/heads/master`, the current hook lets a source commit through (`0`), the fixed hook
blocks it (`2`), and a fence that lists only `main` lets it through again (`0`). `grep -c master
hooks/git-guard.test.sh` really is `0`, the suite really is 77/0, and all four toolchain pins match
what is installed. The design does not need to change.

**What is wrong is a claim about the tests, and it costs real coverage.** The spec says row 17 was
chosen so it *fails* under two mutations: dropping `master` from the fence, and dropping `rebase-apply`
from the marker loop. The first is true. The second is backwards. Dropping `rebase-apply` makes the
carve-out never fire for an apply-backend rebase, so the guard becomes *stricter*, and row 17 — which
expects a block — still gets its block and reports green. I ran every row in the matrix against that
mutation and **not one of them fails.** The row that would catch it is a `rebase --apply` started from
a *feature* branch, which must stay allowed: I measured it at `0` with the fence intact and `2` with
`rebase-apply` dropped. That row does not exist in the spec, and checklist step 3 tells the implementer
to build only the `master` variant — so the gap gets baked in.

The second real problem is the remedy table, cited for the third round running. It now has four rows,
but the state it leaves out is the headline one: a **plain detached HEAD with no operation running** —
matrix rows 1 and 2, the exact incident this spec exists to fix. There is no exact text for it, and the
implementer will improvise the sentence in the single most common new refusal. (For the record, that is
the one branchless state where `git switch -c` actually works — I measured it succeeding there and
being refused `fatal: cannot switch branch while rebasing` / `while merging` in the two states the
table does cover.) The same table is also mandated for Guard 2, a *push* guard, while every row is
worded for a commit ("or stage only documentation", "cannot judge a commit from here").

The third is small and is the third instance of one habit: a stated count that does not match the list
under it. "Three bounds" is followed by two numbered items; "Three constraints on that table" is
followed by four bullets. Round 5 cited this same paragraph for saying "two bounds" when there were
three. All three findings are prose edits plus one test row — no design change, and nothing here
argues for reworking the fix.

### Measurements taken (this machine, git 2.50.1, bash 3.2.57)

Three hook variants built from `hooks/git-guard.sh`: **fenced** = the spec's `symbolic-ref` +
`sequencer_in_progress` with `main|master`; **nomaster** = fence lists `refs/heads/main` only;
**noapply** = `for marker in rebase-merge` only. Driven with real `PreToolUse` payloads.

| Fixture (state verified before the run) | row | orig | fenced | nomaster | noapply |
|---|---|---|---|---|---|
| `rebase --apply` from `master`, `head-name=refs/heads/master` | 17 | 0 | **2** | **0** ← caught | 2 |
| `rebase -i` from `main`, `head-name=refs/heads/main` | 15 | 0 | **2** | 2 | 2 |
| `rebase -i` `edit` stop from `feat/x`, `commit --amend` | 8 | 0 | 0 | 0 | 0 |
| cherry-pick conflict while detached | 9 | 0 | 0 | 0 | 0 |
| plain detached HEAD, source staged | 1 | 0 | **2** | 2 | 2 |
| named `main` + `MERGE_HEAD` | 16 | 2 | 2 | 2 | 2 |
| **`rebase --apply` from `feat/x` — no such row in the spec** | — | 0 | **0** | 0 | **2** ← caught |

Other cells re-run and reproduced: row 2 (plain detached, `--force-with-lease`) 0 → 2; row 3 (non-repo,
pathspec commit into another repo) 0 → 2; row 4 (non-repo, leased push) 0 → 2; row 5 (unborn `main`,
source staged) 0 → 2; row 6 (detached, docs only) 0 → 0.

| Other claim in the spec | Result |
|---|---|
| `grep -c master hooks/git-guard.test.sh` = 0 | **True** (grep exits 1, no match) |
| Suite is 77 passing, 0 failing | **True** — `git-guard: 77 passed, 0 failed` |
| Toolchain pins (bash 3.2.57(1) arm64-apple-darwin25 / git 2.50.1 Apple Git-155 / py 3.9.6 / jq 1.7.1-apple) | **All four exact** |
| Six-state `abbrev-ref` vs `symbolic-ref` table | **Reproduces**: unborn `main` → `HEAD`(rc 128) vs `main`; orphan → `HEAD` vs `brandnew`; detached → `HEAD` vs *fails*; non-repo → both fail |
| Both rebase backends write `head-name` | **True** — `rebase-apply/head-name` and `rebase-merge/head-name` both present |
| `git am` from a **detached** HEAD writes `rebase-apply` with **no** `head-name` | **True** — dir present, `head-name` absent, so the fence falls through to `return 0` as the spec argues |
| `rebase --continue` raises no `COMMIT` fact (`classify-git-command.py:152`) | **True** — classifier emits nothing; line 152 is `if subcommand == "commit":` |
| `git switch -c` refused mid-rebase / mid-merge | **True** — `fatal: cannot switch branch while rebasing` / `while merging` |
| `git switch -c` on a **plain** detached HEAD | **Succeeds** — which is why that state needs its own remedy row |
| Guard 2 currently prints no remedy line (`git-guard.sh:147`) | **True** |

### Violations

| # | id | rule_source | where | why |
|---|---|---|---|---|
| 1 | `core-conduct/verification-before-write-down` | `rules/core-conduct.md` | Scenarios → row 15/16/17 mutation rationale, and the "deliberately asymmetric" paragraph after the must-fail Gherkin | "Row 17 … fails under *two* mutations … dropping `rebase-apply` from the loop" is recorded as confirmed and is measurably false — that mutation makes the guard stricter, row 17 still exits 2 and reports green, and no row in the 17-row matrix detects it. |
| 2 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | The message contract → state-dependent remedy table | The four-row table omits the plain-detached-HEAD-with-no-operation state (matrix rows 1 and 2, the spec's headline case), and every row is worded for a commit while the same table is mandated for Guard 2's push refusals. |
| 3 | `writing-specs/unambiguous-requirements` | `skills/writing-specs/SKILL.md` | The in-progress-operation carve-out → bounds list; The message contract → constraints list | "Three bounds … (matrix rows 15, 16 and 17)" is followed by two numbered items with row 17's bound missing, and "Three constraints on that table" is followed by four bullets — the third round a stated count has disagreed with its own list. |

**Rule text cited**

1. `rules/core-conduct.md:9` — "Verification precedes both the claim and the write-down — never state
   that something works, is fixed, or is done, and never record that claim in a durable artifact
   (… spec), until you have actually run it and re-read the output. … When something is unverified,
   write what you checked and what you did not." The spec reports a measurement for the `master` half
   ("`orig=0`, fenced `=2`, fence-without-`master` `=0`" — reproduced) and none for the `rebase-apply`
   half, while the sentence introducing both says "each was confirmed to fail under it".
2. `skills/writing-specs/SKILL.md:25` — "API contracts: these give the agent the real data structures
   and interface boundaries to build against, instead of letting it improvise shapes that other
   components then fail to match." With `SKILL.md:28` — "enumerate the edges. Anything you leave
   implicit, the agent infers." The stderr text is this hook's output contract and is asserted by
   tests; the spec's own words are "specified per state rather than left to the implementer".
3. `skills/writing-specs/SKILL.md:24` — "Requirements, not one-liners: … concrete requirements the
   agent can satisfy and you can check", with `SKILL.md:13-14` (a spec carries production rigor; drift
   is a correctness problem). A list that announces three members and shows two is not checkable.

### How to close them (all prose, plus one test row)

1. Either drop the `rebase-apply` half of row 17's rationale and say plainly that row 17 detects the
   `master` mutation only — **or** add the row that actually detects the loop mutation: a
   `git rebase --apply` stopped from a **feature** branch, expected **0**, must stay green (measured
   `fenced=0`, `noapply=2`). The second is the better fix; it is the only row in either variant that
   distinguishes the two loops. Whichever is chosen, checklist step 3's fixture list needs the same
   edit.
2. Add a fifth remedy row — plain detached HEAD, no operation — whose text may safely advise
   `git switch -c <name>` (measured to work there). Give Guard 2 its own column or its own three
   rows, since "or stage only documentation" and "cannot judge a commit from here" are false on a
   push refusal.
3. Make the two counts match their lists.

### Notes (non-blocking)

- **The fix itself is sound and I tried to break it.** `symbolic-ref` + the `head-name` fence behaves
  exactly as specified in all eleven cells I rebuilt, and the carve-out's `git am` argument holds on
  measurement rather than on reasoning alone.
- **`rebase_head_name()` vs `sequencer_in_progress()` — the drift hazard is real but honestly
  surfaced.** The spec's argument that neither can substitute for the other is correct (empty is
  ambiguous in one and decisive in the other), so this is not a DRY violation of the kind
  core-conduct forbids. But the only thing keeping the two marker lists in step is a comment, in a
  spec whose own thesis is "prose is not a rail" — and finding 1 shows the divergence is invisible to
  the suite. Extracting a shared `rebase_marker_dir()` that both call would make divergence
  structurally impossible and would cost fewer lines than either rail. Recommended, not required.
- **Length: 609 lines / 5,772 words, still under the 800-line cap; not cited, because prior rounds
  demanded most of the growth.** Three duplications are now cuttable without losing a fact: the
  ⚠️ "measurement scripts are not committed" warning appears twice in near-identical form (Background
  to the matrix, and again after the scenario table); the rows 15/16/17 rationale appears twice (bounds
  list and scenario commentary); and "The remedy line is not always followable" restates the carve-out
  limits plus the constraints list a third time. Roughly 60–80 lines, and the long-form version belongs
  in ADR 0026 anyway.
- **Provenance accounting in "What changes" is tighter than it reads.** Six executed cells maps exactly
  onto the six I could reconstruct; the four unmarked cells (plain-detached × empty index,
  rebase-from-`main` × empty index, rebase-from-`main` × lease, non-repo × empty index) all follow
  mechanically from `on_main` returning true, and the spec marks the two structurally similar ones.
  Worth one clause for symmetry; not cited.
- **The loose/tightened table's `rebase --apply` row still says "from `main`"** while row 17 now uses
  `master`, and its cells hold prose where the others hold exit codes. Harmless, but it reads as if it
  were row 17's fixture.
- **Canonical path is correct.** `writing-specs:54` points at `docs/superpowers/specs/`; this repo's
  `rules/gates.md` One-canonical-file discipline mandates `docs/features/<name>.md`, and the project
  layer wins. Frontmatter (`phase: planning`, `branch: none`) is consistent with its siblings, and
  checklist step 1 owns the transition.
- **Security clean.** `writing-secure-code` re-read (shell-execution territory). The new code adds one
  file read (`cat "$dir/head-name"`) whose path comes from `git rev-parse --git-path`, not from user
  input; `printf` format strings stay literal with the branch name passed as an argument, so a branch
  name containing `%` is inert; `case` subjects are data and patterns are literals. Outside a
  repository `git rev-parse --git-path` prints nothing, `[ -e "" ]` is false, and the guard fails
  closed — measured.
- **Tests and implementation remain in separate checklist steps**, and the round-6 swap of steps 5 and
  6 (messages before logic) is the right order: I confirmed the intermediate state it avoids is real —
  `git-guard.sh:191`'s current text says "commits to main/master are blocked" and would print that on a
  detached-HEAD refusal.
- **Checklist step 2 remains the most important step in the document.** Every provenance claim in the
  spec, including the ones I reproduced, rests on scripts that are not in the repository yet.

### Waivers

None requested, none applied. The user has declined every waiver across six rounds.
