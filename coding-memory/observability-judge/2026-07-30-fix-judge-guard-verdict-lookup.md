# Observability Judge Verdict — judge-guard verdict lookup + chained detection (implementation)

- **Date:** 2026-07-30 (ts 2026-07-30T13:07:56Z)
- **Repo:** judge-guard-fix (worktree `/Users/marksuyat/.claude/.claude/worktrees/judge-guard-fix`)
- **Branch:** `fix/judge-guard-verdict-lookup`
- **HEAD:** `97752e6ed6c548e21311cc27a87351eb87ba0588` (clean tree)
- **Base:** `main`, merge-base `8dfe05c3cba0bc0f97c3b32a9f98dfa8de59f31a`
- **Stage:** implementation (gates the PR)
- **Delta judged:** `23f662b` (red tests) → `f77d222` (fix + ADR) → `bc76aeb` (merge of main) →
  `7f8d5d5` (ADR renumber) → `97752e6` (memory). Diff vs merge-base touches 4 files only:
  `hooks/judge-guard.sh`, `hooks/judge-guard.test.sh`, ADR 0012, `CODING_MEMORY.md`.
- **Design doc:** `docs/decisions/0012-judge-guard-repo-local-verdicts-and-chained-detection.md` (read in full)
- **Test command run by me:** `bash hooks/judge-guard.test.sh` → **26 passed, 0 failed** (exit 0)

## What was changed (plain English)

The repo has a doorman (`judge-guard.sh`) that refuses to let you open a pull request until a fresh
review verdict exists for exactly the commit you're shipping. Two things were wrong with the
doorman, and both are fixed here.

First, the doorman was checking the wrong guest list. Verdicts are written into *the project you are
working in*, but the doorman always walked over to `~/.claude`'s list. Those are the same list only
when the project *is* `~/.claude` — so in every other project the door could never be opened by any
amount of correct reviewing. It now reads the list belonging to the repo it is standing in (resolved
from the repo root, so it behaves the same from any subdirectory), and when the list is missing it
prints the exact path it looked at instead of a vague complaint.

Second, the doorman only looked at the *first* thing you said. `gh pr create` on its own was
challenged; `git push && gh pr create` — two orders in one breath, which is how the command is
normally actually issued — walked straight past. The command line is now split on shell operators
(`&&`, `||`, `;`, `|`, `&`, subshells, `$(...)`) and every part is challenged. Quoted text is still
left alone, so the phrase inside a commit message is not mistaken for a real command.

## Does it do what you wanted?

Mostly yes, and I checked rather than took it on faith:

- I ran the suite myself: **26 passed / 0 failed**, including the five new chained-shape cases and
  the three new "read the repo's own store" cases.
- I probed the classifier directly with 14 hand-built command lines. Correctly **blocked**:
  `gh pr create`, `git push -u origin br && gh pr create`, unspaced `git push&&gh pr create`,
  `;`-chained, `||`-chained, piped, `(gh pr create)`, `echo $(gh pr create)`, and
  `JUDGE_EXEMPT=x git push && gh pr create` (the exemption correctly does *not* carry across the
  `&&`, mirroring bash). Correctly **ignored**: `git commit -m "fix && gh pr create"`,
  `echo gh pr create`, `git log | head`.
- I verified the two `shellcheck -x` findings are genuinely pre-existing: SC2016 (line 65) blames to
  `3e78cac`, SC2181 (line 161) to `aaa2abb`, and `git merge-base --is-ancestor` confirms **both are
  ancestors of the merge-base**. Leaving them is correct, not laziness.
- I verified the ADR numbering is now unique: `docs/decisions/` holds exactly one 0011 (main's
  branch-scoped-write-permission) and one 0012 (this one).
- TDD order holds and is visible in the history: `23f662b` touches only the test file; `f77d222`
  touches only the hook and the ADR. Clean red-then-green, separately revertible.
- **The inverted assertion is legible cold** — the question that was asked. The test file carries a
  six-line comment above the new cases naming the old assertion by its exact description string, the
  motivating incident (vibe-scape PR #25 shipping unjudged), and why the reversal is safe; ADR 0012's
  Consequences repeats it as its own bullet. A reader hitting `git log -p` on that line will not
  mistake it for a silent behaviour flip.

## What could go wrong / honest concerns

1. **The same bypass shape survives with a newline instead of `&&`.** I tested this: a Bash call of
   `git push` NEWLINE `gh pr create --fill` exits **0** — allowed, no verdict required. `shlex` with
   `whitespace_split` treats a newline as ordinary whitespace, so the two commands collapse into one
   segment and `gh` never sits at position 0. Multi-line command strings are a very common shape from
   the Bash tool, arguably as common as `&&`. This is not a regression (it leaked before too), but it
   is the *same defect class the ADR says it closed*, it has no test, and it is not listed in the
   ADR's Consequences — unlike the git-guard/merge-guard deferral, which is disclosed. Same for
   `if true; then gh pr create; fi` and `for … do gh pr create; done` (segment starts with
   `then`/`do`) — exotic, lower priority, same class.
2. **A classifier crash fails OPEN, silently.** I proved this with a stub interpreter that fails only
   the classify call: the guard exits **0** and prints nothing. The classify block catches
   `ValueError` deliberately, but any other failure (interpreter crash, OOM-kill, incompatible
   Python) is swallowed by `2>/dev/null` and read as "not a PR command". This change *adds* a
   Python ≥3.6 requirement to that path — `shlex.shlex(punctuation_chars=…)` does not exist in
   Python 2, and the hook's own fallback is `command -v python3 || command -v python`. On a box where
   `python` resolves to 2.x, the gate would turn itself off with no message. (Not reachable on this
   machine: no `python` on PATH, `python3` is 3.9.6.) Note the asymmetry — *no* interpreter fails
   closed, but a *broken* one fails open.
3. **`JUDGE_VERDICTS_FILE` is an unlogged bypass.** It is described in-code as a test override, but
   `CODING_MEMORY.md`'s own "Next" plan uses it in the real PR flow. Unlike `JUDGE_EXEMPT`, which
   prints its reason to stderr, redirecting the store leaves no trace. (In this worktree the override
   is now unnecessary — the default already resolves to the worktree's store.)
4. **The gate reads the working tree, not the committed blob.** A verdict satisfies the door while
   still uncommitted, and a hand-edited `verdicts.jsonl` would too. Consistent with the hook's stated
   "momentum guardrail, not a security boundary" nature, but it means "the PR was judged" is not a
   fact the merge commit can prove by itself.
5. **Ordering wrinkle created by strict freshness + a repo-local store.** Committing this verdict
   moves HEAD and immediately invalidates it. The workable order is judge → `gh pr create` → *then*
   commit the verdict artifacts, which leaves the PR's opening commit without its own verdict in
   tree. Not wrong, but it is a non-obvious dance and the skill text does not describe it.
6. **Deferring `git-guard.sh` / `merge-guard.sh` is defensible, but it does leave the system
   inconsistent.** Three hooks now use the same "momentum guardrail" phrasing with materially
   different chained-command behaviour; `merge-guard.sh` gating `gh pr merge` genuinely deserves its
   own reproduction. Acceptable as a deferral because ADR 0012 states it explicitly — provided it
   becomes a tracked follow-up rather than a paragraph nobody re-reads.
7. **Repo identity is still a directory basename.** The store now follows the worktree, and `repo` is
   `judge-guard-fix` here versus `.claude` in the primary checkout. A verdict judged in a worktree
   will not satisfy the gate if the PR is opened from the primary checkout of the same repo. That
   fails in the safe direction (blocks), so it is friction, not a hole — but it is friction that will
   be met again.

## What I'd double-check before merging

1. **Decide, out loud, on the newline case (concern 1).** Either add a test asserting the current
   behaviour and a Consequences bullet saying "newline-separated chaining remains open", or split on
   newlines too (one extra line: treat `\n` as a segment break before `whitespace_split`). Shipping
   it undocumented is the only thing here that reads as an accident rather than a decision.
2. **Consider failing closed on empty classifier output (concern 2)** — an empty `kind` currently
   means "allow". For a hook whose header says it fails CLOSED, treating "the classifier said
   nothing" as "no PR command here" is the one place the header and the code disagree.
3. **Open the tracking task for `git-guard.sh` / `merge-guard.sh`** before the ADR bullet goes cold.
4. **Confirm the PR body carries the workflow warning** from ADR 0012's first Consequence: this gate
   starts genuinely blocking in every repo for the first time, and people will meet it as a surprise.
5. **Open the PR from this worktree**, and expect to commit the verdict artifacts *after*
   `gh pr create` (concern 5).

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Both defects fixed as specified; store resolution and per-segment matching do exactly what the ADR says |
| execution | concern | Suite 26/0 re-run by me and probes confirm the `&&`/`;`/`\|`/`$()` shapes; but a newline-separated `git push`⏎`gh pr create` still exits 0 — same defect class, untested, undocumented |
| trajectory | pass | Root-caused two mutually-masking defects, disproved the settings-shadowing hypothesis, weighed and rejected the dual-path fallback with reasons, TDD order in separate commits, shellcheck blames verified before deferring |
| regression | pass | Diff confined to hook + test + ADR + memory; every pre-existing false-positive case still green in my own probes; increased enforcement is intended and disclosed |
| context_budget | pass | Hook code, not always-on context; no rule/skill text added; +25 lines to CODING_MEMORY's Active Session, within that file's purpose |
| traceability | pass | ADR 0012 states context, options, rejections, consequences; hook comments explain why `punctuation_chars` is load-bearing and why there is no fallback path; the absent-store error now names the exact path |
| success_masking | concern | 26 green tests coexist with a newline-shaped bypass; a classifier crash fails open silently (proved with a stub interpreter) and this change adds a py≥3.6 requirement on that path; `JUDGE_VERDICTS_FILE` redirection is unlogged |
| intent_drift | pass | No drive-bys (shellcheck findings deliberately left with verified blames), no new dependencies (`shlex` is stdlib), sibling hooks deliberately deferred; the ADR renumber is merge hygiene, not scope creep |
| checkpoint | pass | Four small commits, red-then-green split, fix isolated to `f77d222` — a clean revert point at every step; tree clean at HEAD |
| audit_trail | pass | ADR + CODING_MEMORY + commit messages agree; the inverted assertion is documented in both the test comment (naming the old case and PR #25) and the ADR; the duplicate-ADR-number lesson is recorded as a reusable rule |

## Roll-up

- **Risk:** medium
- **Confidence:** high

## Concerns

1. Newline-separated chaining (`git push`⏎`gh pr create`) still bypasses the gate — verified exit 0.
   Same class as the defect being fixed; no test, not in ADR Consequences.
2. Classifier failure fails OPEN and silently (proved with a stub interpreter); this change adds a
   Python ≥3.6 requirement on that path while the hook still falls back to `python`.
3. `JUDGE_VERDICTS_FILE` is an unlogged bypass used in the real PR flow, unlike the logged
   `JUDGE_EXEMPT`.
4. The gate reads the working-tree verdict file, so a verdict need never be committed to open a PR.
5. Strict freshness + repo-local store means committing the verdict invalidates it — the
   judge → PR → commit-artifacts order is non-obvious and undocumented in the skill.
6. `git-guard.sh` / `merge-guard.sh` keep the identical chained gap; deferral is disclosed in ADR
   0012 but needs a tracked follow-up to stay honest.
7. `repo` identity remains a directory basename, so a worktree verdict will not satisfy the gate from
   the primary checkout (fails safe, but recurring friction).
