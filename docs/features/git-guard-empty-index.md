---
phase: review
model_tier: high
branch: fix/git-guard-empty-index
---

# git-guard empty-index regression + phase-guard memory path

Two live Tier-1 guard defects, both found 2026-08-03, both friction rather than safety holes.
They ship together because both are guard friction the user hits every session, and both are
small. Full discovery record: `CODING_MEMORY.md` lines **790** (regression) and **805**
(memory path).

## Defect A — an empty staging area is read as "deny"

`hooks/git-guard.sh:112-115`. Guard 1 blocks non-documentation commits to `main`. It decides by
reading `git diff --cached --name-only`, and treats an **empty** result as `allowed=0`.

PreToolUse fires *before* the command runs. So in `git add X && git commit -m m -- X` the `git
add` has not happened yet at hook time, the index is empty, and the commit is refused **even when
`X` is documentation**. Pre-L1 the chained form fail-opened and never reached this branch; L1
(`67598b2`) made chained commands visible, and this branch became reachable for the first time.

Live workaround in use today: run `git add` and `git commit` as two separate tool calls.

### Why the existing tests could not see it

33 tests, a 24,016-case fuzz run and a mutation round all passed. The suite's `stage …` helper
runs **before** invoking the hook, so the hook always saw a populated index. Chained-ness was
tested; *staging inside the chain* never was. Fuzzing and mutation both validate assertions
against the fixture's premise and can never question the premise itself.

**This constrains the fix:** at least one new case must do its `git add` **only inside the command
string**, with no helper staging.

### The trap — "empty index → allow" is a fail-open, and so is enumerating the alternatives

An unconditional allow-on-empty would open a real hole, because plenty of command shapes commit
content the index does not show at hook time. **This spec twice tried to list them, and both lists
were measured short** — see tasks 8 and 9:

| Round | The list | What it missed |
|---|---|---|
| 1 | pathspec, `-a`, `--amend` | the chain's own `git add` — 4 commands `main` blocks were allowed |
| 2 | …plus `git add` | `rm`, `mv`, `reset --soft`, `checkout HEAD~1 -- <p>`, `restore --staged`, `apply --cached`, `stash pop --index`, `cherry-pick -n`, `revert -n` |

⚠️ **Do not add a tenth row.** A list of the ways an index gets filled cannot be shown to be
complete, and every omission grants permission it should not — short in the **allow** direction.
The two rounds are evidence about the *approach*, not about the entries.

The pathspec behaviour is measured, not assumed — the same finding blocks the marker-gate spec
(`CODING_MEMORY.md:557`): `git commit -- <path>` commits the worktree, not the index, and commits
**only** those paths, leaving anything else staged in the index. It matters doubly here because this
repo's own standing rule mandates `-- <path>` on **every** commit.

### Required behaviour

When the index is empty, judge the commit by **the paths it names for itself**, and deny otherwise:

| Shape, with nothing staged | Answer |
|---|---|
| commit names paths after `--`, and nothing on the line can widen them | check those paths against the allowlist |
| anything else — bare commit, `-a`, `--amend`, `-i`, `--only`, an unseparated path, any chain | **block**, exactly as `main` does today |

Four things veto the pathspec, because each commits more than the paths given: `-a`/`--all`
(tracked worktree edits), `--amend` (HEAD's tree), `-i`/`--include` (**the index as well** — measured:
it committed a staged source file alongside the named doc), and a command that cannot be understood
at all — a bare token the flag table cannot account for, an unrecognised option (git honours
abbreviations, so `--amen` amends), or `--pathspec-from-file`, whose paths live in a file this hook
cannot read. `-o`/`--only` is unrecognised, so it blocks with that last group.

**Why this shape:** it only ever grants permission for paths the hook has read off the command
line, so it is **measured never weaker than `main`** by replay — where "is this enumeration
complete?" is not checkable at all. *Measured, not proven:* round 3 found two ways it was weaker
that the matrix of the day did not contain — path facts from one segment answering for a whole
line, and a `..` component making the string matched and the file committed two different things.
Both are fixed and both are now in the matrix. Accepted cost: `git add X && git commit -m msg`
with no pathspec stays denied, which is today's behaviour and what the house rule already forbids.

⚠️ **Do not restate the block case as "git refuses such a commit anyway".** That is false whenever
a sibling `git add` precedes it, and believing it is exactly what produced the fail-open in task 8.

The allowlist entries themselves are unchanged — `CODING_MEMORY.md`, `coding-memory/*`,
`docs/*.md` — but a path carrying a `..` **component** is refused before they are consulted,
because the string matched and the file git resolves are then not the same thing (round 3).
Flag detection reuses the existing segment lexer (`hooks/lib/shell_segments.py`) the way
`doc-guard.sh` reads `-a` — **no third lexer.**

## Defect B — every auto-memory write is refused

`hooks/phase-guard.sh:285`. The exempt-path list is
`CODING_MEMORY.md|coding-memory/*|docs/*|.claude/*|settings.json`. It omits
`projects/*/memory/*`, where the harness's own memory tool writes.

So while any feature file sits at `phase: planning` — i.e. the entire remaining marker-gate
register, roughly 8 branches — **every memory write is denied**, while `rules/gates.md` promises
that docs and memory paths are never blocked.

**Reproduced live 2026-08-03**, not inferred: a Write to
`projects/-Users-marksuyat--claude/memory/…` was refused with the planning-phase message while
`docs/features/verification-marker-gate.md` sat at `phase: planning`.

Fix: add `projects/*/memory/*` to that list. One line.

## Gotchas

- ⚠️ **This repo *is* `$HOME/.claude`, so editing `hooks/*.sh` edits the LIVE hook immediately.**
  A half-finished `git-guard.sh` blocks the session's own commits, and a half-finished
  `phase-guard.sh` blocks its own writes. **Work in a git worktree** so the live copies stay on
  `main` until merge — the precedent set by `fix/judge-guard-verdict-lookup`.
- `settings.json` carries `skip-worktree`; committed and live are different files. This change
  touches no registration, so it needs no settings edit — but do not "verify" the fix by reading
  the committed `settings.json`.
- `phase-guard.sh` **is** registered and live (grepped from the live file 2026-08-03). Wording in
  `rules/gates.md` and `CODING_MEMORY.md:812` still calls it unregistered; that correction is a
  **separate, already-approved branch** — do not widen this one for it.

## Task checklist

- [x] 1. Create the worktree and branch; record the branch in this file's frontmatter.
      · Worktree `.claude/worktrees/git-guard-empty-index` (the `/.claude/` dir is gitignored at
        `.gitignore:72`), branch `fix/git-guard-empty-index` off `main` @ `9fb2f64`.
      · ⚠️ **Task 6 cannot run before merge.** The live hook is the *primary* checkout's
        `hooks/phase-guard.sh`, on `main`; fixing it here does not arm it. The memory write is
        blocked until this PR lands. Pre-merge, Defect B is verified by its test only (task 4);
        do the real write after merge.
- [x] 2. **Red** — add failing cases to `hooks/git-guard.test.sh`. At minimum: docs pathspec commit
      whose only `git add` is *inside* the command string (must allow); bare `git commit` with an
      empty index (must allow); `-a` with a source file modified and nothing staged (must block);
      `--amend` with an empty index (must block for source). No helper staging in the first case.
      · Baseline before touching anything: **33/0**. After: **37 pass, 3 fail** — the three reds are
        the docs pathspec, the bare commit, and `-a` with only docs modified. Seven cases added:
        the other four pin the fail-CLOSED answers a naive "empty → allow" would break.
      · Needed a tracked, **committed** pair (`src/tracked.sh`, `docs/tracked.md`); `stage`-created
        files are untracked and `commit -a`/`--amend` never pick those up, so the `-a` cases would
        otherwise have passed for the wrong reason.
      · ⚠️ **Harness fidelity gap found and fixed in the same step:** `on_branch` ignored
        `git checkout`'s exit status. My cases leave tracked files modified, `feature` does not carry
        them, so the checkout refused and **two force-push cases silently ran on `main`** — reporting
        a real-looking FAIL for the wrong reason. `on_branch` now aborts loudly; the section resets
        `--hard` on the way out. Same class as the `tool_name` harness gap that let a false premise
        survive five judge rounds on `judge-guard`.
      · No-`--` pathspec (`git commit -m msg docs/x.md`) is pinned **blocked**, not allowed: telling
        a path from an option value needs a table of which git flags take arguments, and this file's
        stated fail direction is that "cannot tell" means block.
      · ⚠️ **Second fixture defect, found by the implementation and fixed separately:** `empty_index`
        used a plain `git reset`, which clears the index but leaves the *previous* case's worktree
        edits in place — so "only docs modified" silently also had source modified and `commit -a`
        read the leftover. Now `reset --hard`. Same lesson as the bug under repair: **a fixture must
        establish the whole state it claims.** Verified against the pre-fix hook that this did not
        mask the defect — still exactly 3 reds.
- [x] 3. **Green** — implement the empty-index file-set derivation in `hooks/git-guard.sh`, reusing
      `hooks/lib/shell_segments.py` for flag and pathspec extraction.
      · Extraction went into `lib/classify-git-command.py` (which already owns the lexer) rather
        than the hook, so there is still exactly one parser. New facts: `COMMIT_AMEND`,
        `COMMIT_PATHSPEC`, `COMMIT_BARE_ARGS`, and `COMMIT_PATH<tab><path>` per path. The tab keeps
        a path with spaces in one piece through the hook's word splitting. Classifier unit
        **47 → 55/0**.
      · Needed a small table of which `git commit` flags consume the next token — otherwise
        `git commit -m msg` (allow) is indistinguishable from `git commit -m msg docs/x.md` (block).
        Scoped to pathspec detection only: `-a` detection still ignores option values, so the
        pinned `git commit -m '-a'` → `COMMIT_ALL` case is unchanged.
      · An unknown flag is assumed to take no value, so its value looks like a stray path and the
        commit fails closed. Deliberate — it matches the fail direction this hook states for itself.
- [x] 4. **Red** — add a failing case to `hooks/phase-guard.test.sh`: a write under
      `projects/*/memory/*` while a `planning` feature file exists must be allowed.
      · Baseline **130/0** → **132/2**. Two reds (a memory file and `MEMORY.md` itself) plus two
        deny pins, so the fix cannot over-exempt: `projects/p/app.sh` and `projects/p/memory.sh`
        must both stay blocked. The exemption is the memory *directory*, not `projects/` at large.
- [x] 5. **Green** — add `projects/*/memory/*` to the exempt list at `hooks/phase-guard.sh:285`.
      · **132/2 → 134/0.** Its own `case` arm rather than an extra alternation on the existing one,
        so the comment explaining *why* memory is exempt sits against the pattern it explains.
      · `rules/gates.md:5`'s parenthetical "(docs and memory paths never blocked)" becomes true
        with this commit — it was describing intent, not behaviour. The *other* stale claim in that
        same line, that the hook is "not registered in `settings.json`", is measurably false and
        deliberately **left alone**: it belongs to the already-approved wording branch.
- [ ] 6. Write the owed memory file `feedback_fixture_must_not_pre_create_state` and its
      `MEMORY.md` line. This doubles as the end-to-end check of Defect B; text is drafted in
      `.claude/session-state.md`.
      · ⏸ **Blocked until merge, by design** — the live hook is `main`'s copy, so the fix is not
        armed on this machine yet. The fixed hook was verified to allow that exact path directly
        (see `## Verification`); the real write happens on `main` after the PR lands.
- [x] 7. Run both suites plus the neighbouring hook suites and `shellcheck -x`; record pass/fail
      in `## Verification`.
- [x] 8. Observability judge (implementation stage), then `gh pr create`. User merges in the
      GitHub UI.
      · ✅ **RUN 4 → PR #36 is open** — https://github.com/suyatdev/.claude/pull/36. Verdict
        `coding-memory/observability-judge/2026-08-04-fix-git-guard-empty-index.md`, pinned
        `5154dec`, **`risk=medium confidence=high`**. It re-derived rounds 1–3's closures rather
        than trusting this checklist, and confirmed them.
      · **Ordering that made the gate pass, worth reusing:** the judge writes its verdict but commits
        nothing, `gh pr create` runs while HEAD still equals the judged sha, and the verdict is
        committed *after* the PR exists. `judge-guard` reads the store from disk, not from git, so an
        uncommitted verdict satisfies it — while a committed one moves HEAD and invalidates itself.
        That is what bit RUN 3 (`f182def`).
      · ⚠️ **Defect C bit a fourth time, on `gh pr create` itself.** `cd <worktree> && gh pr create`
        fails: PreToolUse fires before the `cd`, so the hook judged `.claude@main`. The shell's cwd
        must already be the worktree in a *previous* call.
      · 🟡 **RUN 4 found a fourth instance of the "a path is not the file it names" class** — a
        pathspec naming a **directory** (`docs/sneaky.md/`) matches the `docs/*.md` allowlist and
        commits everything under it. Measured 2 → 0. Latent (nothing under `docs/` ends in `.md`).
        Shipped documented rather than patched — user decision, 2026-08-04 — so the class gets one
        fix instead of a fifth round. Recorded in ADR 0014 *Known open* and in PR #36's body.
      · **RUN 1 IS IN — `risk=high`, `confidence=high`, and it did NOT clear the branch.** Verdict
        `coding-memory/observability-judge/2026-08-03-fix-git-guard-empty-index.md`, pinned
        `5aa220e`. Every number I claimed re-measured exact (40/0, 134/0, 55/0, 37/3 replay, 36/4
        mutant, all three end-to-end rows, shellcheck) — **and the branch is still wrong.**
      · 🔴 **THE BLOCKER, reproduced by me before being accepted: I INTRODUCED A FAIL-OPEN.**
        The design enumerates three shapes that commit content the index does not show. There is a
        **fourth: the chain's own `git add`** — the very shape this branch exists for. With no
        pathspec on the `commit`, the derivation finds nothing and ALLOWS, but the `git add` runs
        first, so the index is not empty by then. Measured on the real repo, `main` vs branch:

        | command | `main` | this branch |
        |---|---|---|
        | `git add -- hooks/x.sh && git commit -m msg` | 2 | **0** |
        | `git add -A && git commit -m msg` | 2 | **0** |
        | `git commit --amen --no-edit` | 2 | **0** |
        | `git commit --pathspec-from-file=list` | 2 | **0** |

        All four are **regressions**, not uncovered cases: blocked today, allowed by this branch.
      · **The stated reason is false, and that is worse than the gap.** *"git refuses such a commit
        itself"* holds only with no sibling `git add`. It is written into this spec **and** into the
        hook comment, so it actively misleads the next reader. Fix the sentence wherever the gap is
        closed or accepted.
      · **The suite could never have caught it:** the test comment's enumeration *is* the code's
        enumeration, so 40/0 only ever confirmed my own list. Same shape as the fixture defect this
        branch already documents — the check inherits the blind spot of the thing being checked.
      · `--amen` is a valid git abbreviation and `--pathspec-from-file=list` hides its paths in a
        file; both slip the literal `"--amend" in rest` test and the flag table, so the fail-closed
        pins are weaker than they look.
      · **Defect C's blast radius GREW and the feature file must say so:** `commit_target_files`
        adds `git diff` / `git diff-tree` calls that also run in the hook's cwd, so the cwd bug now
        corrupts the *file list*, not just the branch name. Deferral still right; the cost is higher.
      · Also owed: an ADR for the empty-index policy and the bare-args rule (two Tier-1 guard policy
        decisions with no record), and `gh pr create` must run **from this worktree** — the verdict
        row records `repo: git-guard-empty-index` and a run from the primary checkout will not match.
      · ✅ **ALL RUN 1 ITEMS ADDRESSED — written, measured, left UNCOMMITTED for human review**
        (user asked to stage and commit these personally, 2026-08-03).
        · The chain's own `git add` is now the **first** of four shapes, in code, spec and ADR.
          New facts `ADD_PATH<tab><path>` and `ADD_ALL`; an unbounded add (`-A`, `-u`, `.`) resolves
          via `git status --porcelain` rather than off the command line. A commit pathspec is
          **exclusive** and suppresses the add, because git commits only the named paths.
        · Unrecognised options now fail closed (`COMMIT_BARE_ARGS`), which covers git's
          abbreviations (`--amen`) and `--pathspec-from-file`. A curated safe-list keeps
          `--no-edit`/`--no-verify`/`-q`/`--signoff` from becoming false positives.
        · **The false sentence is corrected in all three places** — spec, hook comment, and ADR 0014
          — and each now states the allow is justified by *no shape naming a file*, not by git's
          own behaviour.
        · ADR **0014** written. Defect C's grown blast radius recorded in `## Verification`.
        · Five pre-existing separator tests had their expected value **updated, not weakened**:
          they used `git add -- x` purely as a lexing fixture, and now also assert the staged path
          is seen through each separator form.
        · Re-measured: git-guard **50/0**, classifier **66/0**, phase-guard 134/0, ten neighbours
          unchanged, shellcheck clean. Replayed against the pre-fix code: **5** and **13** genuine
          reds. All four RUN 1 regressions re-probed on a dirty scratch repo — source via `-A`/`.`/
          `-u` blocks, docs-only allows, untracked source blocks.
        · **Still owed: obs judge RUN 2** at whatever SHA these land on, then the PR.

- [x] 9. **RUN 2 → the design was narrowed.** Verdict appended to the same file, pinned `833e3eb`,
      `risk=medium confidence=high`. RUN 1's blocker genuinely closed — every number re-measured
      exact, 8/8 shapes probed, and the five changed test expectations confirmed to have only
      **added** facts. But the *class* was not closed: **nine further staging commands** were all
      regressions (blocked on `main`, allowed by the branch), and ADR 0014's "all four are
      consulted" was a false completeness claim — the same error the ADR itself diagnoses.
      · ✅ **User decision, 2026-08-03: stop predicting what a command stages.** Relax only where the
        commit names its own paths; restore `main`'s behaviour everywhere else. Two short lists are
        evidence about the approach, not about the entries. Rationale, both rounds and the rejected
        design: **ADR 0014**, rewritten. `### Required behaviour` above is the current policy.
      · Dropped `ADD_PATH`/`ADD_ALL`/`add_scan` and the `git status --porcelain` resolution;
        `commit_target_files` → `commit_pathspec_files`, which makes no git calls at all.
      · **Two defects found while narrowing, both measured, both fixed here:**
        `git commit -i -m msg -- docs/x.md` was a **live fail-open** — `-i` commits the index as
        well, and the classifier returned the paths on seeing `--` before consulting the flag table,
        so a staged source file rode in behind a documentation pathspec. And `has_fact` word-split
        a fact stream whose paths ride after a **tab**, so committing a file named `PUSH_FORCE`
        blocked an unrelated `git push` in the same line.

- [x] 10. **RUN 3 → two more shapes, both fixed here.** Verdict appended to the same file, pinned
      `4be542b`, `risk=medium confidence=high`, `regression: fail`, `success_masking: fail`.
      Rounds 1 and 2 confirmed genuinely closed — the judge re-measured rather than trusting the
      write-up. Two new shapes were weaker than `main`, both now red-tested (`b17a666`) and fixed:
      · **The line was judged by one segment.** Facts are a flat set with no segment identity, so
        `git commit -m a -- docs/a.md && git add -- src/b.sh && git commit -m b` allowed a second
        commit that really carries `src/b.sh`. The classifier now withholds `COMMIT_PATHSPEC` and
        its paths unless **every** commit on the line names its own and none is widened. Stated as
        a rule for any fact added later: **granting facts must hold line-wide, denying facts may
        hold per segment** — which is what `PUSH_FORCE` already did.
      · **A path was matched as a string.** `coding-memory/../src/app.sh` satisfied
        `coding-memory/*`; `docs/../notes.md` satisfied `docs/*.md` from anywhere in the repo. A
        `..` **component** is now refused before the allowlist, rather than resolved — resolving
        asks "relative to which directory?", which is Defect C's open question. `docs/v1..v2.md`
        traverses nothing and stays allowed.
      · ADR 0014's two proof claims softened to what was measured, and `git -C <dir> commit`
        (invisible to the classifier, both hooks exit 0, **not** widened here) added to its open list.

## Verification

**Suites — all green.** `git-guard` 33/0 → **77/0** · `phase-guard` 130/0 → **134/0** ·
`classify-git-command` 47/0 → **78/0**. Unaffected neighbours re-run and unchanged: `judge-guard`
101/0, `doc-guard` 16/0, `context-handoff-watch` 19/0, `pane-dispatch-guard` 34/0,
`classify-pr-command` 51/0, `memsearch-nudge` 5/5.

**shellcheck 0.11.0** — zero findings on `git-guard.sh` and `git-guard.test.sh`. No net-new.

**The tests detect the bug**, each round measured at its own tests-only commit and green after the
fix that follows it: **21 of 67 hook and 12 of 73 unit** cases red at `5545f64` (the narrowing),
then **5 of 77 hook and 6 of 78 unit** red at `b17a666` (round 3's two shapes).

**The load-bearing claim, replayed rather than asserted — 63 commands × 6 index/worktree states,
378 pairs, `main`'s hook vs the candidate, comparing exit codes.** The matrix grew from 51 commands
to 63: round 3's two shapes were not in it, which is why it passed them.

| Candidate | identical to `main` | stricter | **allowed where `main` blocks** |
|---|---|---|---|
| the rejected enumerate-what-gets-staged design (`27c5ac5`) | 215 | 1 | **162 pairs / 44 distinct commands** |
| the narrowed fix as RUN 3 received it (`4be542b`) | 326 | 0 | **52 pairs / 13 distinct commands** |
| this fix | 346 | 0 | **32 pairs / 8 distinct commands** |

*Provenance ([ADR 0016](../decisions/0016-differential-harness-must-prove-difference.md)): base was
`main` as it stood when each row was measured — this predates `BASE_REV`, so no fixed SHA was
recorded at the time.*

All eight relaxations name **only** documentation after a `--` (`docs/*.md`, `CODING_MEMORY.md`,
`coding-memory/*`), which is the entire intended change; one of them is the newly-legal
`git commit -m a -- docs/x.md && git commit -m b -- docs/x.md`. The five that left the list between
`4be542b` and here are exactly round 3's two defects — three multi-commit lines and two `..` paths.
The 44 include `git rm`, `git commit -a`, `git commit --amend` and a bare `git commit -m msg`.

**Git's own behaviour, measured directly rather than read off the manual** — the premise the whole
policy rests on. With `src/a.sh` staged:

| command | files in the resulting commit |
|---|---|
| `git commit -m msg -- docs/b.md` | `docs/b.md` only; `src/a.sh` still staged afterwards |
| `git commit -i -m msg -- docs/b.md` | `docs/b.md` **and** `src/a.sh` |

The second row is why `-i` now blocks: pre-fix it exited **0**, post-fix **2**.

**Open, deliberately not fixed here — Defect C, `git-guard.sh:88`.** `current_branch` runs
`git rev-parse` in the *hook's own* working directory, which is the session's, not the directory
the command will run in. Measured: the same payload exits 2 from the primary checkout and 0 from a
worktree, so **work in any worktree is judged against `main`**. It bit three times during this
branch — twice on a commit and once on a probe that merely *contained* the string `git commit`.
Not widened into this diff — the payload `cwd` is also pre-`cd` (`CODING_MEMORY.md:713`), and
`phase-guard`'s trick of resolving from the file being written has no analogue for a commit, so
this needs a decision rather than a patch. Same "identity-from-cwd" class already fixed in
`phase-guard` and still open in `judge-guard`; enumerated across the live guards, it is
**git-guard, judge-guard, and partially doc-guard**.

✅ **Its blast radius no longer grows here — corrected.** The rejected design added
`git status --porcelain`, `git diff` and `git diff-tree` calls that also ran in the hook's own
directory, so a wrong directory produced a wrong *file list* and not just a wrong *branch name*.
`commit_pathspec_files` makes **no git calls at all**, so cwd again affects only the branch name
and the index read, exactly as on `main`. The deferral stands and the cost is back to where it was.

**Also open, pre-existing and NOT widened into this diff:** `--amend` with a *populated* index
evaluates only the staged files, not HEAD's tree as well. Unchanged by this work; recorded so it
is not mistaken for something this branch introduced.

🟡 **Open, found by RUN 4 and NEW to this diff — a pathspec can name a directory.** The allowlist
matches by file *type*, so a **directory** named `docs/anything.md` satisfies `docs/*.md` and git
commits everything beneath it. Measured end-to-end: exit **2** on `main`, exit **0** here, with a
shell script in the resulting commit. **Latent, not live** — no directory under `docs/` ends in
`.md`, no symlinks — so it needs a deliberately misleading name to reach. Shipped documented rather
than patched (user decision, 2026-08-04): it is the third member of the "a path is not the file it
names" family (`..` ✅ fixed, directory ❌, symlink ❌ untested), and rounds 1–3 established that
patching the instance found is what keeps the class open. Its fix must enumerate the family and
carry a test that a directory whose *name* ends in `.md` is refused. ADR 0014 *Known open*.

**The replay harness is now committed** at `hooks/git-guard.replay.sh` (63 commands × 6 states) —
previously it lived only in a session scratchpad, so the strongest claim in this file could not be
re-run by a reviewer. Note its own limitation, which RUN 4 named: the matrix has missed a shape in
three consecutive rounds, including the directory case above. It is evidence, not proof — a command
absent from the matrix is not a command that passed.
