# Observability verdict — git-guard detached HEAD (architecting, round 2)

- **repo:** memsearch-freshness (worktree, detached HEAD `0819db7`)
- **spec:** `docs/features/git-guard-detached-head.md` (blob `0ae6c632…`, verified)
- **stage:** architecting — advisory only, does not block
- **ts:** 2026-08-10T20:19:07Z
- **risk:** medium — **confidence:** high

## What was changed

The repo has a bouncer at the door of `main` — a hook that refuses to let source code be
committed straight onto the default branch. The bouncer works by asking one question: *which
branch am I on?* It asked that question with a command that answers with the literal word
`HEAD` when there's no branch checked out. `HEAD` isn't `main`, so the bouncer shrugged and
waved everything through. That is how two commits actually reached `main` in this worktree —
the guard didn't approve them, it was never asked.

This design swaps the question for one that has only one meaning (`git symbolic-ref`), which
either names a real branch or admits it can't tell. When it can't tell, the guard now refuses
instead of shrugging. It also rewrites four refusal messages so they say what the guard
actually saw ("a detached HEAD" vs "not a git repository") rather than asserting a branch.

## Does it do what you wanted?

Yes. I rebuilt three versions of the hook — today's, an obvious `--abbrev-ref`-based patch,
and this design — and ran ten real scenarios through each. Every load-bearing claim in the
spec reproduced:

- The six-state table is exact on git 2.50.1, including the non-obvious one: an unborn branch
  gets *named* by `symbolic-ref` but reads as `HEAD` under `--abbrev-ref`.
- The suite baseline is genuinely 77 passed / 0 failed.
- ADR 0026 is the correct next number (0025 is highest); the `rules/gates.md` text the spec
  says to edit is present.
- The `git-guard.sh:164` empty-index citation lands on the right line.
- There is no bypass variable, so accepted-cost #1's "no escape" is true.

**The discriminator claim is right, with a caveat.** `git init -b feat/x` + staged source:

| variant | exit |
|---|---|
| today's hook (broken) | 0 |
| an `--abbrev-ref`-based fix | **2** ← over-blocks |
| this design (`symbolic-ref`) | 0 ✓ |

So it does separate this design from the tempting patch. But it does *not* separate it from
doing nothing at all — the unfixed hook also returns 0. It is an **over-block detector**, not
a fix detector. The *suite as a whole* pins the design (the detached scenarios fail under
today's hook; the discriminator fails under the abbrev fix), so the conclusion holds — but the
sentence as written credits one scenario with work that only the set does.

## What could go wrong / what I'm unsure about

**1. A fourth accepted cost is missing, and it's the one that will actually bite.** The spec
has a section headed *"Why this does not block rebases."* Measured, that is only true of the
shape it tests. `git rebase -i` stopping at an `edit` leaves HEAD detached, and the documented
next step is `git commit --amend` — which **does** raise a COMMIT fact and **is** blocked:

```
--- state during rebase edit stop ---
symref: []  rc=128          rebase-merge dir exists: YES
--- git commit --amend --no-edit ---
  today: exit 0     this design: exit 2
```

There is no bypass variable. Worse, the remedy line the operator is shown reads *"Create a
feature branch instead (git switch -c <name>)"* — following that advice mid-rebase derails the
rebase. This repo runs detached worktrees for real (`git worktree list` shows this very one
detached), so it is not a theoretical shape.

**2. `checkout_desc()` is sound but one distinction short.** Running the extra `git rev-parse
--git-dir` on the refusal path only is the right call — the hook fires on every Bash call, and
the allow path stays untouched. Distinguishing detached-vs-not-a-repo is real diagnostic value.
But the distinction the operator most needs at that moment is *plain detached* vs *mid-rebase*,
because it decides whether the remedy line is good advice or a trap. That check is available
on the same refusal path for one more test — I measured
`test -d "$(git rev-parse --git-path rebase-merge)"` returning YES during the edit stop.

**3. The residual hole is a class, not a rebase.** The spec asks ADR 0026 to record that a
rebase replaying onto `main` is unguarded. True — but measured on `main` with this design
applied, so is everything else that makes a commit without being spelled `commit`:

```
git commit -m msg    exit=2
git merge feat/x     exit=0   <- unguarded
git cherry-pick …    exit=0   <- unguarded
git revert …         exit=0   <- unguarded
git am patch.mbox    exit=0   <- unguarded
git rebase …         exit=0   <- unguarded
```

**Deferring the fix is the right call** — a PreToolUse hook runs *before* the command and
cannot know what a merge or rebase will replay, so closing this is a different spec, not a
line in this one. But recording it as *"the rebase hole"* would leave a future reader believing
merge, cherry-pick, revert and am are covered. Name the class. (This is pre-existing, not a
regression this change introduces.)

## What I'd double-check before merging

1. Add the rebase-`edit` / `commit --amend` block as accepted cost #4, and soften the section
   heading — it does not block `rebase --continue`, which is not the same as not blocking rebases.
2. Decide the remedy text for a mid-rebase refusal before implementing, not after someone loses
   a rebase to it.
3. Reword the discriminator sentence to credit the scenario set, so nobody later trims the
   detached scenarios believing the `feat/x` case covers them.
4. Have ADR 0026 enumerate the commit-creating subcommands the allowlist never sees.

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Targets the measured defect, reaches both call sites; round-1 advice adopted in full |
| execution | pass | Design verified by rebuilding 3 variants over 10 shapes; correct exit code in all |
| trajectory | pass | Alternatives rejected on measurement, not taste; phase-guard precedent correctly distinguished by citation |
| regression | concern | `git commit --amend` at a rebase `edit` stop is blocked, no bypass, misleading remedy — unenumerated |
| context_budget | pass | No always-on context added; gates.md edits correct existing text |
| traceability | concern | ADR obligation names one instance (rebase) of a wider unguarded class |
| success_masking | concern | Discriminator sentence over-credits one scenario; only the set proves detection landed |
| intent_drift | pass | Out-of-scope list explicit and disciplined; gates.md edit is required, not creep |
| checkpoint | pass | One-helper change, trivially revertible; checklist never mixes tests and implementation |
| audit_trail | pass | ADR 0026 mandated and correctly numbered; incident evidence quoted from reflog, not from a prior session's report |

## Concerns

- `git commit --amend` at a `rebase -i` edit stop is blocked with no bypass; unenumerated cost
- Refusal remedy advises `git switch -c`, which derails a rebase in the case that triggers it
- `checkout_desc()` cannot distinguish plain-detached from mid-rebase, the distinction that matters
- ADR 0026 records the residual hole as rebase-specific; merge/cherry-pick/revert/am are equally unguarded
- Discriminator scenario returns exit 0 under the unfixed hook too; only the suite as a set proves the fix
