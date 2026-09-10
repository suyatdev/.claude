---
phase: planning
model_tier: high
branch: TBD
---

# Twelve source files are over the 800-line hard maximum

Queued 2026-09-07 on `chore/pane-scratch-card-closeout` @ `1b213a1`, while planning
`docs/features/pane-dispatch-test-suite-split.md`. That card was written as if its file were
an isolated violation. Enumerating the repo showed it is the **tenth worst of twelve**.

This card is a **ledger entry, not a design.** Do not implement from it. Its purpose is that
the pattern has a file to be found in, rather than living only in one session's memory.

## What was measured

Command, run at `1b213a1`:

```sh
git ls-files | grep -v '^docs/' | grep -v 'vendor/' | while read f; do
  [ -f "$f" ] && n=$(wc -l < "$f") && [ "$n" -gt 800 ] && printf '%5d %s\n' "$n" "$f"
done | sort -rn
```

`rules/core-conduct.md` Code Style: **<400 lines preferred, 800 max.**

| Lines | File | Kind |
|---|---|---|
| 1924 | `hooks/worktree-guard.test.sh` | test |
| 1911 | `treko/support.js` | source |
| 1470 | `hooks/reference-transaction.test.sh` | test |
| 1242 | `hooks/phase-guard.test.sh` | test |
| 1229 | `hooks/secret-command-guard.test.sh` | test |
| 1122 | `hooks/test-marker-guard.test.sh` | test |
| 1071 | `statusline-command.test.sh` | test |
| 1054 | `treko/test_nontext_contrast.py` | test |
| 959 | `hooks/git-guard.test.sh` | test |
| 957 | `panes/dispatch-pane-agent.test.sh` | test — owned by `pane-dispatch-test-suite-split` |
| 864 | `hooks/lib/classify-git-command.test.py` | test |
| 833 | `statusline-command.sh` | source |

**Ten of twelve are test suites.** Two are production source: `treko/support.js` (1911) and
`statusline-command.sh` (833).

**Resolved since, one row.** `panes/dispatch-pane-agent.test.sh` was split on
`refactor/pane-dispatch-test-suite-split` (2026-09-09) into six concern files plus a runner.
Measured after: 445 / 195 / 140 / 131 / 130 / 79, plus a 134-line runner at the original name
and a 66-line shared `panes/test-lib.sh`. All under 800; one (`routing`, 445) is over the 400
preferred and is a stated residual on that card. **The table above is left as measured at
`1b213a1` and is not rewritten** — it records what was true then, and editing it would falsify
the measurement it exists to preserve.

## What this does and does not claim

- **Claimed, because measured:** these twelve files exceeded 800 lines at commit `1b213a1`,
  by `wc -l`, over tracked files outside `docs/` and `vendor/`.
- **Not claimed:** that any of them is *badly structured*. Line count is a proxy. A 1900-line
  suite of independent assertions is a different problem from a 1900-line function. Each file
  needs its own look before anyone proposes a cut.
- **Not claimed:** that the count is stable. It was 12 on 2026-09-07 and will drift. Re-run
  the command above rather than trusting this table.
- **Not measured:** the `docs/` tree, which has files far larger (up to 5365 lines) and which
  the Code Style rule was not written for. Excluded deliberately, not overlooked.

## Why nothing is being fixed here yet

`rules/core-conduct.md`: fix the root cause and only the root cause; a drive-by cleanup is its
own task. Twelve files across at least four unrelated features cannot be one change without
editing the unbiased baseline of every one of them simultaneously.

`docs/features/pane-dispatch-test-suite-split.md` handles exactly one of them and builds a
shared test skeleton (`panes/test-lib.sh`) plus a set-membership proof method. **If that
pattern works, it is the template the other nine test suites reuse** — and the honest test of
whether it works is whether the second file is cheaper than the first. Wait for it to land
before opening anything here.

## Open questions — decide before implementing, do not decide here

1. Is line count the right trigger at all, or should the rule bite on something structural
   (assertions per file, functions per file, maximum nesting)? Twelve simultaneous violations
   is as much evidence about the rule as about the files.
2. Do the two production-source files (`treko/support.js`, `statusline-command.sh`) get
   handled on the same axis as the test suites, or separately? They are the ones where an
   error is user-visible.
3. Should this be enforced by a hook at commit time, or stay a judgment rule? A hard block at
   800 would have refused the commit that created the current worst offender — which may be
   the point, or may be an unusable amount of friction. `triaging-new-instructions` decides
   where such a rule belongs before anyone writes it.

## Not started

No branch, no code. `phase: planning`; the gate transition needs the literal phrase
`gate confirmed`.
