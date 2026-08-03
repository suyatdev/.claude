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
- [ ] 2. **Red** — add failing cases to `hooks/git-guard.test.sh`. At minimum: docs pathspec commit
      whose only `git add` is *inside* the command string (must allow); bare `git commit` with an
      empty index (must allow); `-a` with a source file modified and nothing staged (must block);
      `--amend` with an empty index (must block for source). No helper staging in the first case.
- [ ] 3. **Green** — implement the empty-index file-set derivation in `hooks/git-guard.sh`, reusing
      `hooks/lib/shell_segments.py` for flag and pathspec extraction.
- [ ] 4. **Red** — add a failing case to `hooks/phase-guard.test.sh`: a write under
      `projects/*/memory/*` while a `planning` feature file exists must be allowed.
- [ ] 5. **Green** — add `projects/*/memory/*` to the exempt list at `hooks/phase-guard.sh:285`.
- [ ] 6. Write the owed memory file `feedback_fixture_must_not_pre_create_state` and its
      `MEMORY.md` line. This doubles as the end-to-end check of Defect B; text is drafted in
      `.claude/session-state.md`.
- [ ] 7. Run both suites plus the neighbouring hook suites and `shellcheck -x`; record pass/fail
      in `## Verification`.
- [ ] 8. Observability judge (implementation stage), then `gh pr create`. User merges in the
      GitHub UI.

## Verification

_Not started._
