---
name: verifying-subagent-commits
description: Use when a dispatched implementer or fix subagent reports DONE with a commit SHA, before trusting that report, generating a review diff, or advancing to the next task — subagents given the correct worktree path and a self-check instruction have still committed to the wrong git checkout. Not for judging whether the commit's contents are correct (see /code-review or the task-reviewer step in superpowers:subagent-driven-development) — only for confirming it landed in the right checkout.
---

# Verifying Subagent Commits

## Overview

A subagent's "DONE, committed as `abc1234`" is a claim, not a fact. Independently confirm it in the target checkout before acting on it. This is a **REQUIRED checkpoint inside `superpowers:subagent-driven-development`'s per-task loop** — run it immediately after an implementer/fix subagent reports back, before "Write diff file, dispatch task reviewer subagent."

## Why this exists

Real trace, one session, three occurrences: an implementer/fix subagent committed to the root repo checkout instead of the isolated worktree it was dispatched into. Once because the worktree genuinely lacked the (untracked) files the task needed, and the subagent fell back silently instead of stopping to ask. Twice — for the *same* task, on a *second* attempt — despite the dispatch prompt explicitly instructing: "run `git rev-parse --show-toplevel` and confirm it prints `<worktree path>`, and `git branch --show-current` and confirm it prints `<branch>`; if either doesn't match, STOP and report BLOCKED." The subagent's self-report claimed success both times anyway. The instruction was in the prompt; it did not change the outcome.

**A self-check instruction inside the dispatch prompt is not a substitute for the controller checking.** The subagent that fails the check is the same subagent that would fail to report the check failing.

## The check

After any implementer/fix subagent reports DONE with a commit, before doing anything else with that commit:

1. In the **target checkout** (the worktree the task was supposed to modify), run `git log --oneline -1` and confirm the reported SHA (or its short form) is HEAD.
2. If it isn't there, check whether it landed somewhere else — most commonly the root/main checkout of the same repo: `cd <root repo> && git log --oneline -3`.
3. Found it in the wrong place → this is a process failure, not a task failure. Fix it before continuing:
   - Check whether it was already pushed (`git rev-list --left-right --count origin/<branch>...HEAD` on whichever checkout has it). If not pushed, it's a purely local fix.
   - Cherry-pick the commit onto the correct branch in the target checkout.
   - Reset the wrong checkout back to its prior commit (`git reset --hard <sha-before>`) — only after confirming nothing else in that checkout depends on keeping it.
   - Note the correction in the task's report file so the record stays accurate (the report's claimed SHA is now stale; don't silently edit it away — annotate it).
4. Only once the commit is confirmed on the correct branch: generate the review package and dispatch the task reviewer.

This is a single `git log --oneline -1` call in the common case — cheaper than discovering, after generating a review package, that the diff is empty or wrong.

## Red flags — stop and check

- About to call `review-package` or dispatch a task reviewer without having run `git log` yourself in the target checkout this task cycle.
- An implementer's report names a commit SHA you haven't independently seen.
- The dispatch prompt told the subagent "work from `<path>`" rather than the subagent running in a directory the harness itself pinned — prose instructions about *where* to work are exactly what this failure mode slips through.
- Multiple checkouts of the same repo exist (a worktree plus the root checkout) — the more checkouts, the more places a stray commit can silently land.

## Rationalization table

| Excuse | Reality |
|---|---|
| "The subagent already ran `git rev-parse` and confirmed" | Two of three real occurrences had that exact self-check instruction and still committed to the wrong checkout. The subagent's own report is not evidence. |
| "It's just a docs/asset commit, low risk" | A commit in the wrong checkout silently diverges the diff under review from what's actually on the branch, regardless of how trivial the change is. |
| "Checking costs an extra tool call" | The check is one `git log --oneline -1`. Finding out later, after generating a review package against an empty or wrong diff, costs more. |

## If the worktree may lack the files a task needs

The one occurrence that *wasn't* a self-check failure had a root cause worth naming separately: a worktree only checks out **tracked** content, so files that are untracked in the checkout it branched from (e.g. loose files never yet `git add`ed) will not exist in a freshly created worktree at all. Before dispatching a task that touches such files, either commit/stage them on the base branch first, or tell the implementer explicitly that they don't exist yet in the worktree and that finding them missing means STOP-and-ask, not "fall back to wherever they do exist."
