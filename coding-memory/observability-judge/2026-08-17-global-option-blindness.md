# Observability judge verdict — global-option-blindness (architecting, advisory, ROUND 2)

- repo: `tracking-feature-state`
- branch: `feature/verification-marker-gate` (not this feature's branch — this feature has no branch
  yet; the spec was authored in the only available worktree because `main` is checked out elsewhere)
- head_sha: `bcd37fa2537a5135f7d2539e8cd841d0712161c6` (unchanged from round 1 — the spec file is
  still untracked/uncommitted, so no new commit exists between rounds)
- stage: `architecting` (advisory — no implementation exists; checklist 0/11, `phase: planning`)
- ts: `2026-08-17T13:29:07Z`
- doc judged: `docs/features/global-option-blindness.md` **revision 2**
- supersedes: round-1 verdict for this same spec (content below; round 1's JSONL line is preserved
  in `verdicts.jsonl` for history)

## What was changed

Same underlying design as round 1 — three guard hooks (`git-guard.sh`, `doc-guard.sh`,
`merge-guard.sh`) are blind to a command's real subcommand whenever a global option (`-C`,
`--git-dir`, `-c`, etc.) appears before it, so `git -C . push --force` and `gh -R o/r pr merge 5`
sail through checks their plain forms fail. Revision 2 is a response round: it applies the
compliance judge's two blocking findings from revision 1 (an `ask` contract for `merge-guard.sh`
that no task could build, and a "measured" claim about `--untracked-files`/`-S` that measured the
wrong flag) and all four of round 1's non-blocking observability advisories. I re-read the full
spec and independently re-verified the load-bearing claims rather than trusting the revision-2
changelog note.

## Does it do what you wanted?

Three of the four round-1 advisories got a substantive fix; the fourth is reasoned well in prose
but was never wired into the spec's own contract/task/test machinery, so I'm marking it partial.

1. **Task 9 (the unverified `ask` fact) — substantive.** It is now a BLOCKING task with two named
   sub-checks (prompt appears and names the option; declining actually stops the command), pinned to
   the permission mode the user's sessions actually launch under (their shell alias carries
   `--allow-dangerously-skip-permissions` — I cannot verify a personal shell alias from this repo,
   but the spec's own reasoning for why it matters is sound: testing under default permissions would
   prove the wrong thing), and it requires pasting what was observed rather than asserting a pass.
   Real teeth added.
2. **Traceability ("no durable trace") — substantive and honest.** The new section decides no log
   file, and every citation backing that decision checks out exactly against the real files:
   `merge-guard.sh:93`, `judge-guard.sh:230`, and `feature-sync-guard.sh:136` are all `printf … >&2`
   lines, confirmed by direct read. It also keeps an explicit `⚠️ Unverified` flag on whether stderr
   from an exit-0 hook is surfaced at all, deferred to task 3 rather than assumed — exactly the shape
   round 1 asked for ("say what should be logged, and why, rather than leaving it as an omission").
   The underlying gap (no queryable log) is *not* closed, but it is now a stated, reasoned trade-off
   instead of a silent one — see Concerns below on why I still score `audit_trail` a concern.
3. **Rollback/blast-radius — substantive.** A new per-hook table names which of the three changed
   hooks fails loud (`git-guard`, `doc-guard`) versus silently (`merge-guard`, the only one), and
   ties task 6 to proving the *old* `merge-guard` behavior before accepting the new cases — a direct,
   correctly-targeted response to the one hook whose failure mode is invisible. Rollback is stated as
   per-hook and independent (revert one file, that guard alone reverts).
4. **`PRINTS_AND_EXITS` message/decision separation — reasoned, but under-specified.** See "What could
   go wrong" — the prose is right, but the spec's own contract, task list, and Gherkin scenarios never
   actually build or test it.

## What could go wrong / what I'm unsure about

- **`PRINTS_AND_EXITS` has no contract, no task, and no test.** The "Accepted limits" section states
  a real requirement ("the refusal must not lie about why") and names six options
  (`--version --help --html-path --man-path --info-path`, bare `--exec-path`) whose message should
  change without changing the decision. But: the "Contract — the new fact" section defines only
  `SCOPE_UNKNOWN<tab><option>`, with nothing carrying a print-and-exit signal from the classifier to
  `git-guard.sh`; `resolve_subcommand()` is specified to return `(subcommand, rest, blocking_option)`
  — three values, no fourth for this; no task lists building it (task 2 emits `SCOPE_UNKNOWN` and the
  three buckets only; task 3 only requires exit-2 paths stay byte-identical, which is a decision
  check, not a message check); and no Gherkin scenario asserts the reason text for these six options.
  This is the same defect *shape* the compliance judge already caught once in this exact document
  (`writing-specs/ambiguous-merge-guard-ask` — "a contract row no task could build") recurring in a
  smaller, non-blocking corner. Concretely: an implementer could skip this entirely, or implement it
  wrong, and every task and every scenario in the plan would still go green. That is genuinely
  invisible — not a hypothetical.
- **The manual-verification gap is narrower but not gone.** Task 9 is now blocking and specific, which
  is real progress, but it is still a single point-in-time human check with no way to re-verify it
  later without a person doing it again. If Claude Code's permission-prompt behavior ever changes
  (version upgrade, alias edit, mode change), nothing in this design would notice.
- **"Re-run the defect table" is two different things, and only one of them is automatic.** Task 1
  turns the Examples tables into real cases in `classify-git-command.test.py` (236 lines today) — that
  part becomes a permanent, automatically-run regression test, assuming this repo's existing suites
  run in CI (plausible given task 8, not itself re-confirmed here). But task 7's defect-table rerun is
  an end-to-end, real-hook-invocation check with pasted exit codes — a one-time, human-run comparison,
  not a scheduled or wired-in signal. The spec's own words — "the same table re-run later is the
  regression signal" — describe a procedure a person has to remember to execute, not a mechanism that
  fires on its own. Months from now, only the unit-test half is guaranteed to still be running.
- **One citation drift, found by direct verification, not asserted.** The traceability section cites
  `doc-guard.sh:27` for the quote *"a missing note is not worth blocking work over."* Line 27 is real
  text but a different sentence ("fails OPEN … rather than block legitimate work"); the exact quoted
  phrase is at line 127. Minor — the underlying claim ("doc-guard already fails open by design") is
  true and the phrase does exist in the file — but it slightly undercuts the frontmatter's claim that
  "every citation … was re-derived independently and all matched," since this citation is new to (or
  at least active in) revision 2 and does not match at the line given.
- **`audit_trail` remains a real gap, now a documented one.** Deciding not to add a log file is a
  legitimate, well-reasoned trade-off (the citations backing it are accurate), and it will be recorded
  in ADR 0029. But the practical effect for someone six months from now asking "how often did
  `SCOPE_UNKNOWN` fire, and on what" is unchanged: there is still nothing to query, only a one-time
  prompt string and a stderr line whose own surfacing is still marked unverified pending task 3.

## What I'd double-check before merging (i.e., before task 11 / PR)

- Add `PRINTS_AND_EXITS` to the "Contract — the new fact" section with an actual signal name (e.g.
  a second, non-denying fact alongside `SCOPE_UNKNOWN`, or a fourth field on `resolve_subcommand()`),
  give it a task, and add at least one Gherkin scenario asserting the reason text differs for one of
  the six options versus the plain `main`-commit refusal — mirroring exactly how bucket 2/3 already
  got a fact, a task, and scenarios.
- When task 3 runs, also settle stderr-surfacing (already flagged) — this determines whether the
  "traceability" answer is "prompt + stderr" or "prompt only."
- Fix the `doc-guard.sh:27` → `:127` citation while touching this section for the item above.
- Confirm (outside this spec, since it's a repo-wide fact) that `classify-git-command.test.py` and the
  other "dependent suites" in task 8 actually run in CI or a pre-commit hook — if they only run when a
  person remembers to, the "regression signal months later" story is weaker than the design implies.

## Dimension table

| dimension | verdict | why |
|---|---|---|
| intent | pass | Matches the same measured defect as round 1; every round-1 advisory and both compliance-judge blocking findings were engaged with directly, not deferred or reworded. |
| execution | concern | Task 9 is now well-scoped but still fundamentally unautomatable; new finding this round — `PRINTS_AND_EXITS` has no contract, task, or test, so its correctness (or its existence) is unverifiable by the stated plan. |
| trajectory | pass | Reasoning is evidence-first throughout; every load-bearing code citation I independently re-checked this round (`classify-git-command.py:150/152/169`, `merge-guard.sh:82/93`, `judge-guard.sh:230`, `feature-sync-guard.sh:136`, `git-guard.sh:142/152`, ADR numbering against `origin/main` and the local branch) matched exactly, with one minor exception noted below. |
| regression | pass | Task 8 dependent suites, task 5 proves `pr create` unchanged before switching callers, task 3 keeps existing `exit 2` paths byte-identical, task 6 explicitly proves *old* `merge-guard` behavior before accepting new cases — the one silent-failure hook gets the strictest treatment. |
| context_budget | pass | Lives in `docs/features/*`, loaded on demand; `classify-git-command.py` explicitly bounded under the house 400-line limit (currently 198 lines). |
| traceability | pass | Exceptionally well cited; ~10 file:line citations independently re-verified and matched. One citation (`doc-guard.sh:27`, should be `:127`) is off — a real but minor slip in an otherwise very high-precision document. |
| success_masking | concern | Two distinct routes to a green-but-wrong result: task 9's inherently manual "ask really prompts" check, and the newly-found `PRINTS_AND_EXITS` gap where an unimplemented or wrong message would pass every stated task and scenario. |
| intent_drift | pass | Entirely responsive to round-1 findings; out-of-scope section is maintained and honestly extended (the `-S`/`--untracked-files` correction is a self-correction of revision 1's own claim, not scope creep). |
| checkpoint | pass | Upgraded from round 1's concern — the new per-hook blast-radius table gives an explicit, hook-scoped rollback story (loud-vs-silent failure mode named per file, reverting one file restores that guard alone). |
| audit_trail | concern | Improved from a silent gap to a stated, reasoned trade-off (no log file, citations for the house convention are accurate, and it will be captured in ADR 0029) — but the underlying gap (no queryable record of `SCOPE_UNKNOWN` firing) is unchanged, and the "traceability" answer still hinges on an unverified stderr-surfacing question deferred to task 3. |

## Concerns

- `PRINTS_AND_EXITS` (the message-clarity fix for `--version`/`--help`/`--html-path`/`--man-path`/
  `--info-path`/bare `--exec-path`) is described in prose only — no fact/signal in the "Contract"
  section, no task builds it, no Gherkin scenario tests it. Same defect shape the compliance judge
  already caught once in this document for the merge-guard `ask` contract; not blocking this round
  because the *decision* path is still covered (task 3, existing Examples), but the *message* path
  could ship unimplemented or wrong with everything else green.
- Task 9's manual "ask really prompts" verification is now blocking and well-scoped, which is real
  progress, but remains a one-time human check with no re-verification mechanism if the underlying
  permission behavior ever changes.
- "The same table re-run later is the regression signal" (task 7) is a manual, human-remembered
  procedure distinct from the automated unit tests task 1 adds; only the latter is guaranteed to keep
  running months from now without anyone deciding to re-run anything.
- Citation drift: `doc-guard.sh:27` should be `:127` for the quoted phrase "a missing note is not
  worth blocking work over" — minor, the underlying claim is true and the phrase exists in the file,
  but it's the one citation in this round that did not match exactly on independent re-check.
- `audit_trail` gap (no queryable record of a `SCOPE_UNKNOWN` refusal) persists; now a stated,
  ADR-bound trade-off rather than a silent omission, which is real progress, but the practical
  after-the-fact question ("how often, on what") remains unanswerable by design.
- Merge-guard's rewrite onto the shared `gh` reader is the one remaining silent-failure surface in
  this feature; task 6's ordering (prove old behavior, then accept new cases) is the correct mitigation
  and directly named as such — no further design gap found here.

## Risk / confidence

risk=medium confidence=high
