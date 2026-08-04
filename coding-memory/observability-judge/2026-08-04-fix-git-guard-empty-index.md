# Observability verdict — RUN 4 (implementation)

- **repo:** `git-guard-empty-index` (worktree of `~/.claude`)
- **branch:** `fix/git-guard-empty-index`
- **HEAD:** `5154decadc504b79d7698a7043f04253b0aeed75`
- **base:** `main` (merge-base `9fb2f64`)
- **ts:** 2026-08-04T02:29:29Z
- **risk:** medium · **confidence:** high

---

## What was changed

Two guard scripts that sit between the agent and git got fixed.

The first is a doorman. His job: nobody commits code straight to `main`, only documentation.
He checked the rule by looking at the tray of files waiting to be committed. Trouble is, he
checks the tray *before* anyone puts anything in it — so the tray was always empty, and an empty
tray read as "refuse everything". Even a pure documentation commit got turned away.

The fix stops him guessing what will end up in the tray and instead makes him **ask the commit
one question: which files do you name for yourself?** (`git commit -m msg -- <paths>`). If it
names documentation and nothing on the line can widen that, he lets it through. If it names
nothing checkable, he refuses — exactly as before.

The second is a smaller fix: another guard was blocking writes to the assistant's own memory
folder. One line added to its exempt list.

## Does it do what you wanted?

Yes, and the two holes RUN 3 found are genuinely closed — I re-measured them myself rather than
trusting the checklist:

- **Multi-commit lines.** `git commit -m a -- docs/a.md && git commit -m b` used to let the
  second, unrestricted commit ride in on the first one's documentation pass. Now blocked, and
  blocked across every separator I tried (`&&`, `;`, `||`, newline), and when the sibling carries
  `-a`, `--amend` or `-i`. Only genuinely documentation-only lines relax.
- **`..` traversal.** `docs/../hooks/evil.sh` used to satisfy the docs allowlist. Now blocked —
  quoted, single-quoted, backslash-escaped, `$'\x2e\x2e'`-encoded, absolute, `:(top)` pathspec
  magic. A `..` inside a *filename* (`docs/v1..v2.md`) still correctly passes.

All four named commands pass: git-guard **77/0**, phase-guard **134/0**, classifier **78/0**,
`shellcheck -x` clean. All six neighbouring suites unchanged (judge-guard 101/0, doc-guard 16/0,
context-handoff-watch 19/0, pane-dispatch-guard 34/0, memsearch-nudge 5/5, classify-pr 51/0).
I also checked the red-test discipline was real rather than claimed: I ran RUN 3's tests-only
commit (`b17a666`) against the hook as it stood *before* the fix and got **5 genuine failures**.
The tests did detect the bug.

## What could go wrong / what I'm unsure about

**A new allow-direction gap, verified end-to-end.** This is the fourth consecutive round in which
a green suite has concealed one, so I went looking outside the tested shapes and found one:

> The guard assumes a pathspec token names a *file*. It can name a **directory**.

The docs exception is deliberately by file *type* — the hook's own header says "an executable
dropped under `docs/` must not inherit a free ride onto `main`", and the test file says the same
at line 320. But a directory named `docs/anything.md` matches the `docs/*.md` pattern, and git
commits everything underneath it. Measured on a scratch repo checked out on `main`:

| command | `main`'s hook | this HEAD |
|---|---|---|
| `git commit -m m -- docs/sneaky.md` (a **directory**) | 2 | **0** |

I then ran the real command and `docs/sneaky.md/evil.sh` — a shell script — landed in a commit on
`main`. `docs/nested` and `docs` both correctly block; it is specifically the `.md` suffix on a
directory name that defeats the check.

**Why I scored this a concern and not a failure, stated plainly:** it is latent, not live. There
are **zero** directories under `docs/` ending in `.md` in this repo, and zero symlinks. Unlike
rounds 1–3 — whose holes were reachable by commands an agent types on autopilot
(`git add -A && git commit -m msg`) — this one needs someone to deliberately create a directory
with a misleading name. These guards are stated to be momentum guardrails, not security
boundaries, and this is not a momentum-reachable shape. It is still a real relaxation of a stated
design intent, and it should not ship undocumented.

The root cause is a **class the ADR already names and then only half-fixes**. ADR 0014 has a
section headed *"A path is not the file it names"* — correct diagnosis — but the implementation
refuses only `..` components. A directory pathspec is the same sentence with a different
instance. The fix was narrowed to the instance RUN 3 happened to find.

**Other honest caveats:**

- **The load-bearing evidence is not reproducible.** The 63 × 6 = 378-pair replay (346 identical,
  0 stricter, 32 relaxed) is the single strongest claim in the ADR, and **no replay harness is
  committed to the tree**. A reviewer cannot re-run it. The matrix has now been found incomplete
  in three consecutive rounds — including by me, just now — so "0 stricter, all relaxations are
  documentation" is a property of that command set, not a proof.
- **The line-wide rule is only as good as the lexer's eyesight.** `git commit -m a -- docs/a.md
  && bash -c "git commit -m b"` measured `main`=2 → HEAD=0: the hidden commit is invisible to the
  lexer, so the visible documentation pathspec answers for the whole line. The blind spot itself
  is pre-existing and accepted (`bash -c "git commit -m b"` alone is exit 0 on `main` too, per
  ADR 0013), and the ADR does say "the accepted-open lexing shapes from ADR 0013 are unchanged" —
  but it does not say that the *new granting rule inherits that limit*, which is the sentence a
  future reader needs.
- **Defect C is real and I reproduced it.** Same payload committing `hooks/evil.sh`: exit **2**
  when the hook runs from a `main` checkout, exit **0** when it runs from this worktree. While
  the session's directory is a feature-branch checkout the guard does not fire at all. **The
  deferral is nonetheless correct** — it is pre-existing on `main`, identical in kind, and the
  payload `cwd` is recorded pre-`cd`, so it genuinely needs a design decision rather than a patch.
  I verified the claim that its blast radius shrank: `commit_pathspec_files` makes no git calls,
  so cwd again affects only the branch name and the index read, exactly as on `main`.
- **Housekeeping, fourth round running:** `settings.json` is still modified-uncommitted in the
  worktree (1 line, model selector). It is outside the diff, but it should not drift into the PR.
- **`gh pr create` must run from this worktree.** `judge-guard.sh` derives
  `repo=$(basename $(git rev-parse --show-toplevel))` and reads
  `$repo_root/coding-memory/observability-judge/verdicts.jsonl`. This verdict is written with
  `repo: git-guard-empty-index` under this worktree. From the primary `~/.claude` checkout the
  guard computes `repo=.claude` and will match none of the four rows.

## What I'd double-check before merging

1. **Decide on the directory-pathspec gap.** Either refuse a pathspec that names an existing
   directory, or — cheaper and truer to the ADR's own principle — accept it explicitly in the
   *Known open* list the way `git -C` and `--amend` already are. What must not happen is it
   shipping unmentioned, because the header comment and the test file both promise the opposite.
2. **Commit the replay harness**, or downgrade how the 378-pair figure is presented. As it stands
   the strongest sentence in the ADR is the one a reviewer cannot check.
3. **Add the one missing sentence** to ADR 0014: the line-wide granting rule holds only for
   segments the lexer can see.
4. **Deal with `settings.json`** before opening the PR, and open the PR **from this worktree**.

---

## Dimension table

| Rubric | Dimension | Score | Note |
|---|---|---|---|
| Evaluation | `intent` | pass | Both defects fixed; the mandated `git add -- X && git commit -m m -- X` shape now passes; RUN 3's two holes independently confirmed closed. |
| Evaluation | `execution` | concern | All 4 named commands green, 6 neighbours unchanged, red-tests verified genuinely red (5 fails pre-fix). Offset by a new allow-direction gap measured end-to-end. |
| Evaluation | `trajectory` | concern | The narrowing from "enumerate what stages" to "ask the commit" is sound and the ADR is unusually honest about retracting its own claims. But the "a path is not the file it names" class was fixed only for `..`, not for the class. |
| Evaluation | `regression` | concern | No adjacent breakage; all neighbouring suites clean. One new `main`=2 → HEAD=0 relaxation (directory pathspec), latent-only: zero triggering paths exist in the repo. |
| Evaluation | `context_budget` | pass | Hooks, tests and docs only. No always-on rule/prompt growth; `rules/gates.md` untouched. |
| Observability | `traceability` | concern | ADR 0014 is excellent and self-correcting; feature file `## Verification` is detailed. The load-bearing 63×6 replay harness is not a committed artifact. |
| Observability | `success_masking` | concern | 77/0 + 134/0 + 78/0 green while an untested allow-direction shape exists, and the replay matrix again did not contain the shape I found — the fourth consecutive round of this pattern. |
| Observability | `intent_drift` | pass | Tight scope: two defects, no drive-by edits, no dependency changes. Defect C explicitly deferred with reasoning rather than silently. |
| Observability | `checkpoint` | pass | Clean test-commit-then-fix-commit pairs throughout; every round has a discrete revert point. |
| Observability | `audit_trail` | pass | ADR 0014 accepted, CODING_MEMORY updated, RUN 1–3 verdicts committed, feature file moved to review. Fully attributable. |

## Concerns

- NEW allow-direction gap verified end-to-end: a pathspec naming a **directory** whose name ends
  `.md` matches the file-type allowlist and commits everything under it — `git commit -m m --
  docs/sneaky.md` measured main=2 → HEAD=0 and put `docs/sneaky.md/evil.sh` on `main`. Latent
  (zero such directories exist), but it defeats the hook header's stated intent.
- Same class as ADR 0014's own *"a path is not the file it names"* section, which was implemented
  for `..` components only — the fix was narrowed to the instance RUN 3 found, not the class.
- The 63×6 = 378-pair replay (346 identical / 0 stricter / 32 relaxed) has **no committed
  harness**; the strongest evidence claim in the ADR is not reproducible by a reviewer, and the
  matrix has now been found incomplete in three consecutive rounds including this one.
- The line-wide granting rule inherits the lexer's blind spot: `git commit -m a -- docs/a.md &&
  bash -c "git commit -m b"` measured main=2 → HEAD=0. Blind spot is pre-existing and accepted by
  ADR 0013, but ADR 0014 does not state that the new granting rule depends on it.
- Defect C reproduced: identical payload exits 2 from a `main` checkout and 0 from this worktree,
  so the guard does not fire while the session sits in a feature-branch checkout. Deferral is
  correct and the "blast radius shrank" claim verified true — `commit_pathspec_files` makes no git
  calls.
- `settings.json` still modified-uncommitted in the worktree, fourth round running.
- `gh pr create` must be run from this worktree: `judge-guard` computes
  `repo=git-guard-empty-index` here and `repo=.claude` from the primary checkout, where none of
  the four verdict rows would match.
- CLOSED and re-verified by me: multi-commit line-wide granting (all separators + `-a`/`--amend`/
  `-i`/source-path siblings), `..` traversal (quoted, escaped, `$'..'`-encoded, absolute,
  pathspec-magic), push-guard lease still correctly segment-bound, red-test discipline genuine
  (5 fails at `b17a666^`).
