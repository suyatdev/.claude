# Observability verdict — global option blindness, three-bucket ask fix (implementation)

- **ts:** 2026-08-18T15:39:25Z
- **repo:** global-option-blindness
- **branch:** `feature/global-option-blindness`
- **head_sha:** 5c479a9b9a89cfbd209a9906992f8b1d729a320b
- **stage:** implementation (gates the PR)
- **base:** main (merge-base against local `main` = `da369be7…` is stale — missing an already-merged
  PR, so it pulls in ~14 unrelated prior-feature files as diff noise; re-scoped to `origin/main`
  merge-base = `6a2b7c519cd8b9b5c9969c32d89f131d9790ddaa`, which gives a clean 19-file, +3082/-67 diff)
- **re-scoring note:** this supersedes the same-day verdict recorded for `f0ba837` (one commit
  earlier). The only change since is `5c479a9`, a single-line, docs-only addition to README.md's
  Roadmap section, carrying its own `Doc-Exempt` trailer. Confirmed via `git diff f0ba837..5c479a9`
  before re-scoring — no code, test, spec, or ADR content changed.
- **test commands:** all nine re-run myself against the current HEAD, none trusted from the summary
  alone — `classify-git-command.test.py` 114/114, `classify-pr-command.test.py` 59/59,
  `shell_segments.test.py` 35/35, `git-guard.test.sh` 151/151, `doc-guard.test.sh` 19/19,
  `merge-guard.test.sh` 10/10, `judge-guard.test.sh` 101/101 (spot-check), `phase-guard.test.sh`
  141/141 (spot-check), `git-guard.replay.sh` 378/378 identical pairs, 0 relaxed — every count
  matched the decisions summary exactly
- **risk:** low · **confidence:** high

## What was changed

Three "guard" scripts sit in front of every `git`/`gh` command a session runs and decide whether to
allow it, block it, or ask first — one stops commits landing straight on `main`, one stops
undocumented commits, one stops a PR merge from the command line. All three read a command by
looking at its second word to figure out what it does. The bug: `git` and `gh` both let you put
extra options *before* that second word (`git --no-pager commit`, `git -C /other commit`, `gh -R
o/r pr merge 5`) — and when you do, the "second word" is that option, not the real action, so all
three guards silently saw nothing and let the command straight through. This had already happened
for real with `merge-guard` on two separate shapes.

The fix sorts every one of those leading options into three buckets: harmless ones to skip over (so
the guard still sees `commit`/`merge` normally), ones known to be able to point git at a different
repository or change what a file path means (refuse and ask a human), and anything unrecognised
(also refuse and ask, on the reasoning that git keeps adding options faster than any list can keep
up, so "don't know" must never mean "let it through"). "Refuse and ask" is a new, one-keystroke
interactive prompt rather than a hard block — deliberately, because the middle bucket includes
options that are usually completely fine (like an ordinary `git -c user.name=x commit`), and asking
is affordable in a way a hard wall wouldn't be. Two smaller pieces rode along in scope: merge-guard's
home-grown checker was swapped for the same shared reader the PR-merge guard already used correctly,
which closed two more real bypasses for free (a leading `gh -R o/r` flag, and a chained `echo hi &&
gh pr merge`), plus a stacked-wrapper gap found the same way; and a message-only fix so the "you
can't commit to main" refusal doesn't lie when the option in question (like `--version`) meant git
never reached a subcommand at all. The one commit added since the prior review is purely a README
Roadmap line documenting the already-shipped, already-ADR'd feature — no behaviour change.

## Does it do what you wanted?

Yes. I re-ran all nine test commands myself against the current HEAD rather than trusting the
reported counts, and every one matched exactly. I also read the core diff (the classifier,
`git-guard.sh`'s new ask guard, and the `merge-guard.sh`/`classify-pr-command.py` rewrite) directly
against `origin/main` line by line and confirmed it matches the decisions summary point for point:
the `resolve_subcommand()` 3-tuple return shape (not the earlier 2-tuple deviation), the three-bucket
tables, the new `SCOPE_UNKNOWN` fact emitted at most once per line, the `ask` JSON on stdout, Guard 3
running strictly after both pre-existing hard-block guards without altering their exit-2 codepaths,
the message-only `PRINTS_AND_EXITS` set kept out of the classifier by design, and `classify-pr-
command.py`'s generalisation with `judge-guard.sh`/`phase-guard.sh` confirmed byte-for-byte untouched
by diff. The hardest part to verify — does the new interactive "ask" prompt actually appear, and
does declining it really stop the command — was checked the honest way: a real human ran it under
their actual launch mode and pasted the verbatim prompt and outcome into the spec, after discovering
and working around a genuine environment trap (every session's hooks resolve through one shared
`$HOME/.claude` checkout, so a naive test would have silently exercised the old, unfixed code — which
is exactly what happened on the first attempt, disclosed rather than hidden).

## What could go wrong / what I'm unsure about

- **No test suite in this repo runs automatically.** Task 0c in the spec measured this directly (no
  CI workflow, no git hook, no wired-in runner) and disclosed it rather than assuming otherwise —
  honest, but it means the nine green results above are a snapshot from whoever last ran them by
  hand, not a standing guarantee that will catch a future regression on its own. Pre-existing
  repo-wide gap, not introduced by or specific to this feature.
- **No persistent record of the new "ask" firing.** By design (stated plainly in ADR 0029, not
  hidden), there is no log of how often, or on what commands, the new cannot-tell case triggers once
  this ships. If bucket 2/3 fires far more often than expected in real use, there's no queryable way
  to notice that pattern after the fact; someone would have to be watching prompts live.
- **The middle bucket will interrupt some genuinely harmless commands by design.** `git -c
  user.name=x commit` now prompts, because `-c` *can* redirect the repository even though this
  particular use never does. Explicit, reasoned trade-off in the ADR, not an oversight — worth
  knowing this could feel like friction until people get used to it.
- **The fix only protects sessions once the shared checkout is updated.** Every session on this
  machine resolves its hooks through one absolute `$HOME/.claude` path regardless of which branch its
  own files are on — until this branch is merged and that shared checkout picks it up, other
  concurrent sessions keep running the old, still-blind guard. A rollout fact, not a code gap, but
  easy to forget.
- **`git-guard.replay.sh`'s baseline silently defaults to local `main`, which is stale in this exact
  worktree** (missing an already-merged PR). I independently re-diffed against the fetched
  `origin/main` for this review and the finding held (a materially smaller, cleaner 19-file diff, no
  behaviour change) — but the replay tool itself gives no warning when its baseline is behind, so a
  future run in an unfetched worktree could quietly compare against the wrong thing.
- **Task 9's manual interactive-prompt verification is a one-time human check** with no
  re-verification path if Claude Code's own permission-prompt mechanism changes in a future version.

## What I'd double-check before merging

1. After merging, make sure the shared `$HOME/.claude` checkout that every live session actually runs
   hooks from gets updated promptly — until then the fix exists on disk but isn't protecting
   anything.
2. Consider whether `git-guard.replay.sh` should fetch or warn when its baseline ref is behind
   `origin`, so a future regression check doesn't silently compare against a stale `main`.
3. Keep an eye on how often the new "ask" prompt fires in the first week of real use, informally —
   there's no log to check later, so this is the only window to notice if bucket 2's inclusion of
   "usually harmless" options (like `-c`) turns out to be more disruptive than expected.
4. The manual, one-time human verification of the interactive prompt (task 9) has no re-verification
   mechanism — if Claude Code's permission-prompt behavior changes in a future version, nothing here
   will notice that on its own.

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Matches the spec and decisions summary exactly: three-bucket classification, `ask` (not allow or hard-deny) on cannot-tell, merge-guard rewritten onto the shared reader, doc-guard confirmed to need zero changes. The one new commit is a purely documentary Roadmap line for the already-shipped feature. |
| execution | pass | All nine test commands re-run independently against current HEAD, all match the claimed counts exactly; core diff read line-by-line against `origin/main` and matches every specific claim in the decisions summary (3-tuple shape, bucket tables, Guard 3 ordering, judge-guard/phase-guard untouched). |
| trajectory | pass | RED-then-GREEN commit pairs per task, a hand-run mutation round proving `PRINTS_AND_EXITS` is decision-independent, and a self-caught spec-shape deviation (2-tuple vs. pinned 3-tuple) fixed in its own small commit before later tasks built on it. |
| regression | pass | New ask guard runs strictly after both pre-existing hard-block guards, touching neither's exit-2 codepath; 378/378 replay pairs identical; `judge-guard.sh`/`phase-guard.sh` confirmed zero-diff. |
| context_budget | pass | No rule/skill/prompt file changed in this feature's actual scope — confirmed against `origin/main`: `rules/gates.md` is absent from this feature's real diff (it only appeared against the stale local `main`, belonging to an already-merged prior feature). |
| traceability | pass | ADR 0029 plus a 1,222-line spec with a measured defect table, full bucket derivation, and a dated Verification entry per task including task 9's verbatim pasted prompt transcript; commit messages name the task and RED/GREEN state. |
| success_masking | concern | No test suite in this repo runs automatically (pre-existing, disclosed, not fixed); no persistent log of the new `ask` firing in production, so an unexpectedly high prompt rate would go unnoticed unless someone is watching live. |
| intent_drift | pass | The two "for free" merge-guard bypass fixes and the message-only `PRINTS_AND_EXITS` fix are the same defect class, each given its own task/commit/tests. The trailing README commit is exactly the expected post-ship Roadmap update, not drive-by scope creep — no new dependency anywhere in the diff. |
| checkpoint | pass | Clean working tree at judgment time (aside from this judge's own in-progress verdict files), one commit per task, and the self-caught 2-tuple/3-tuple deviation was corrected in its own dedicated commit before anything else was built on it. |
| audit_trail | concern | Fully attributable (ADR + commits + spec + user-pasted transcript), and the no-log decision is stated plainly rather than hidden — but it remains a real gap: nobody can query after the fact how often or on what the new cannot-tell case fires. |

## Concerns

- No test suite in this repo executes automatically; all nine green results are hand-run snapshots, not a standing CI guarantee (pre-existing, disclosed).
- No persistent record of the new `ask` decision firing — an unexpectedly high real-world prompt rate on bucket 2/3 options would be invisible after the fact.
- The middle bucket (`-c`, `-C`, `--work-tree`, etc.) will interrupt some genuinely harmless commands by design; worth watching for friction, not a defect.
- The fix only protects sessions once the shared `$HOME/.claude` checkout is updated post-merge — a rollout fact, not a code gap, but easy to forget.
- `git-guard.replay.sh` silently compares against whatever local `main` happens to point to, with no staleness warning; this worktree's local `main` was in fact stale, though re-running the diff analysis against `origin/main` independently confirmed the result was unaffected.
- Task 9's manual interactive-prompt verification is a one-time human check with no re-verification path if Claude Code's own permission-prompt mechanism changes later.
