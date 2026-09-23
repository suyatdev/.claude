---
phase: planning
model_tier: high
branch: none
---

# test-marker-guard reads its opt-in from the session's cwd, not the commit's repo

Filed 2026-09-22 from the `fix/phase-guard-root-markdown` slice, where the gate silently did not
judge a commit that it would have blocked. **Nothing here is fixed — this card is the register
entry.** Planning phase; no branch; the measurement below is the whole of what is known.

## What happened

`78e2dab` on this branch staged `hooks/phase-guard.test.sh` at a version its suite had never
passed (150/3 by design — red tests, per test-driven-development). It was committed with
`TEST_EXEMPT='red tests only, no source staged, suite 150/3 by design'`, the shape
`rules/gates.md` prescribes and the shape `80e0318` set as precedent.

The gate never ran. The commit was issued from a session whose working directory was a **different
repository** (`~/.worktrees/Snatch-Bracket/bracqueen-rebrand`), via `cd <target-worktree> && git
add … && TEST_EXEMPT=… git commit …`.

## Measured, 2026-09-22

| what was run | result |
|---|---|
| the real guard, real payload (`cwd` = the Snatch-Bracket worktree) | **rc 0, no log row** — never judged |
| `hooks/lib/decide-commit-gate.py`, same command text, `cwd` = the `.claude` worktree, no flag | `BLOCK  MSG_UNSUPPORTED_FORM  FOREIGN_REPO` |
| …same, with `TEST_EXEMPT` set in the command text | `EXEMPT  -  red tests only, …` |
| `~/.claude/hooks/state/test-marker.log` | 81 rows, newest `2026-09-09T02:58:30Z` |
| `<this worktree>/hooks/state/test-marker.log` | 17 rows, newest `2026-09-21T19:58:36Z` |

So the decision helper would have blocked, and would have honoured the exemption; the guard
script exited before calling it.

## Why

`hooks/test-marker-guard.sh:75-79` — the target resolution and node G, the opt-in signal:

```sh
toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -n "$toplevel" ] || exit 0
[ -r "$toplevel/hooks/lib/write-test-marker.py" ] || exit 0
```

`$cwd` is the payload's `cwd`, i.e. the **session's** working directory. The repository the commit
actually lands in is never consulted — not by node G, and not by `STATE_DIR`/`LOG`
(`:81-82`), which are derived from the same `$toplevel`, so the audit log a reader would check
is the *session's* repo's log, not the target's.

Snatch-Bracket has no `hooks/lib/write-test-marker.py`, so the guard read the whole commit as
happening in a non-opted-in repo and stood down.

## Why it matters, stated honestly

- **The gate is a momentum guardrail, not a security boundary** (`rules/gates.md`), and this does
  not change that — anyone who wants around it already has `TEST_EXEMPT`.
- The real cost is the **audit trail**. A `TEST_EXEMPT` reason in a commit message reads as "the
  gate judged this and I waived it". Cross-repo it is a claim about an event that did not occur,
  and no log row anywhere contradicts it. `78e2dab`'s message is exactly this; the correction is
  recorded on `docs/features/phase-guard-root-markdown.md` under task 3 rather than by amending a
  pushed commit (Mark's call, 2026-09-22).
- Cross-repo commits are **normal** in this setup, not exotic: one session routinely works a slice
  in `~/.worktrees/.claude/<wt>` while rooted in another project.
- The related-but-different `FOREIGN_REPO` case — cwd *is* an opted-in repo, target is elsewhere —
  is already visible: 14 of 24 `EXEMPT` rows counted 2026-09-21 name it
  (`docs/features/phase-guard-root-markdown.md`, task 2 gotcha).

## Open questions for planning — none of these is decided

1. Should the opt-in be resolved from the **target** repo (the one the `git commit` runs in, which
   the classifier already has to determine) rather than the session cwd? What does that cost when
   the two agree, which is the common case?
2. `STATE_DIR`/`LOG` follow the same `$toplevel`. If the opt-in moves to the target, does the log
   move with it — and is a per-repo log still right when the deciding session is elsewhere?
3. Is the quiet `exit 0` at node G the correct posture for "cannot tell", or should an
   unresolvable target be visible (logged, not blocked)? Note the sibling guards split both ways:
   `secret-command-guard.sh` fails open, `scan-secrets.sh` fails closed.
4. Does anything else key off the session cwd the same way? `hooks/lib/decide-commit-gate.py`'s
   own `FOREIGN_REPO` branch is evidence the layers already disagree about which repo is "this"
   one.
5. Is a fix worth it at all, or is the honest resolution a documentation change — say so in
   `rules/gates.md`, and stop writing `TEST_EXEMPT` rationales into cross-repo commit messages?
   This is a live option, not a strawman.

## Spec

<Not written. Planning has not run; the questions above are its input.>

## Tasks

- [x] 1. **Measure** — the table above. *(done 2026-09-22, at `557d52c`)*
- [ ] 2. Planning: answer the five questions, choose between a code fix and a documentation-only
  resolution, then write the spec.

## Verification

<Appended during review.>
