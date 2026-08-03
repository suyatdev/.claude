---
phase: implementation
model_tier: low
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

### The trap — "empty index → allow" is a fail-open

An unconditional allow-on-empty would open a real hole, because three command shapes commit
content the index does not show:

| Shape | What actually gets committed | Index at hook time |
|---|---|---|
| `git commit -m m -- docs/x.md` | the **worktree** content of the pathspec | may be empty |
| `git commit -a -m m` | all tracked **worktree** modifications | may be empty |
| `git commit --amend` | HEAD's tree, re-written | may be empty |

The pathspec row is measured, not assumed — the same finding blocks the marker-gate spec
(`CODING_MEMORY.md:557`): `git commit -- <path>` commits the worktree, not the index. It matters
doubly here because this repo's own standing rule mandates `-- <path>` on **every** commit, so the
guard's most common input is exactly the shape it reads wrongly.

`-a` today fails **closed** on `main` (empty index → deny), which is safe. A naive fix would turn
it into a silent allow for source files — a new fail-open in a Tier 1 guard, on the branch whose
purpose is removing friction.

### Required behaviour

When the index is empty, derive the file set from the command instead of denying:

- **Pathspec present** (`git commit … -- a b`, or trailing paths) → evaluate **those paths**
  against the documentation allowlist.
- **`-a` / `--all` present** → evaluate tracked worktree modifications (`git diff --name-only`).
- **`--amend` present** → evaluate the files in HEAD's commit.
- **None of the above** → **allow**. Such a commit has nothing to commit and git fails it on its
  own; a guard that refuses it reports the wrong reason for the wrong thing.

The allowlist itself is unchanged: `CODING_MEMORY.md`, `coding-memory/*`, `docs/*.md`.
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
- [ ] 8. Observability judge (implementation stage), then `gh pr create`. User merges in the
      GitHub UI.

## Verification

**Suites — all green.** `git-guard` 33/0 → **40/0** · `phase-guard` 130/0 → **134/0** ·
`classify-git-command` 47/0 → **55/0**. Unaffected neighbours re-run and unchanged: `judge-guard`
101/0, `doc-guard` 16/0, `context-handoff-watch` 19/0, `pane-dispatch-guard` 34/0,
`classify-pr-command` 51/0, `panes/*` 45+113+10+9, `memsearch-nudge` 5/5, `statusline-command` 50/50.

**shellcheck 0.11.0** — zero findings on `git-guard.sh` and `phase-guard.sh`, on this branch *and*
on `main`. No net-new.

**The tests detect the bug, proven two ways rather than asserted.**
- Replayed against the pre-fix hook: exactly the 3 intended reds, no more.
- **Mutation — the naive fix.** Replacing the derivation with a blanket "empty index → allow"
  leaves the suite at **36/4**: source pathspec, `-a` with source, `--amend`, and the no-separator
  case all fire. That mutant is the plausible wrong fix, and it cannot pass.

**End-to-end against the real repo, live hook vs fixed hook:**

| Case | Live (`main`) | Fixed |
|---|---|---|
| Write to `projects/*/memory/…` mid-planning | **2** blocked | **0** allowed |
| `git add -- docs/x.md && git commit … -- docs/x.md` on `main` | **2** blocked | **0** allowed |
| same shape with `hooks/x.sh` on `main` | 2 blocked | **2** still blocked |

**Open, deliberately not fixed here — Defect C, `git-guard.sh:88`.** `current_branch` runs
`git rev-parse` in the *hook's own* working directory, which is the session's, not the directory
the command will run in. Measured: the same payload exits 2 from the primary checkout and 0 from a
worktree, so **work in any worktree is judged against `main`**. It bit twice during this branch.
Not widened into this diff — the payload `cwd` is also pre-`cd` (`CODING_MEMORY.md:713`), and
`phase-guard`'s trick of resolving from the file being written has no analogue for a commit, so
this needs a decision rather than a patch. Same "identity-from-cwd" class already fixed in
`phase-guard` and still open in `judge-guard`; enumerated across the live guards, it is
**git-guard, judge-guard, and partially doc-guard**.
