# Observability judge verdict — global-option-blindness (architecting, advisory)

- repo: `global-option-blindness`
- branch: `feature/global-option-blindness`
- head_sha: `b9c5c9c331ad66a68ad2a3d97270e745589c4565`
- stage: `architecting` (advisory — no code has been written; checklist 0/11, `phase: planning`)
- ts: `2026-08-17T18:22:42Z`
- doc judged: `docs/features/global-option-blindness.md`, **revision 4.1**
- prior rounds: this design was judged twice before, on a different worktree/branch, while the spec
  lived on `feature/verification-marker-gate` before being rescued onto its own branch (`4c9a431`).
  Round 1 raised four advisories; round 2 (verdict at `2026-08-17-global-option-blindness.md` in
  this same directory) found three of the four substantively fixed and one (`PRINTS_AND_EXITS` had
  no contract/task/test) still open, plus a minor citation drift. This round re-reads the full spec
  and independently re-derives the load-bearing claims rather than trusting the revision-4.1
  changelog note.

## What was changed

Same underlying design throughout: four PreToolUse guard hooks decide what a Bash command does by
reading its first two words, but both `git` and `gh` accept options before the subcommand, so
`git -C . push --force` and `gh -R o/r pr merge 5` are invisible to every guard — measured
end-to-end. Two revisions happened since the last judge round. Revision 3 closed round 2's one open
finding (`PRINTS_AND_EXITS` now has a task, message-only wiring, and Gherkin coverage including a
hand-run mutation scenario) and fixed the `doc-guard.sh:27`→`:127` citation. Revision 4 added
groundwork tasks (0a–0c) after a self-diagnosed pattern: three straight revisions had stated a
requirement — "the `ask` decision travels on stdout" — with no harness in this repo able to check
it. Revision 4.1 is a pre-dispatch sweep that caught its **own** premise wrong (every one of
revision 4's four measured claims about the harnesses turned out incorrect on re-count) plus several
requirements-with-no-failing-scenario, and replaced the acceptance measure with the pair `(exit
code, stdout decision)` after finding three of six defect-table rows still read `rc=0` after the fix.

## Does it do what you wanted?

Yes, and the self-correction pattern is the strongest part of this trajectory. I independently
re-derived essentially every load-bearing citation and measurement in the current spec against the
real files rather than trusting the document's own claims:

- **`classify-git-command.py:150/152/169`** (`subcommand, rest = argv[1], argv[2:]`; the `commit`/
  `push` gates) — match exactly.
- **`merge-guard.sh:82`** (`toks[i:i+3] == ["gh","pr","merge"]`) — matches.
- **`classify-pr-command.py:39`** ("global flags are legal before the subcommand") — matches (cited
  as `:38-45`, the comment block spans that range).
- **`classify-git-command.py:31`** (GRANTING vs DENYING facts) and **`:91-104`** (`UNRECOGNISED`
  reasoning / `COMMIT_SAFE_FLAGS`) — both match (cited as `:31-40` and `:90-105`).
- **`git-guard.test.sh:224`** (`_run_case_common`), **`:252`** (`assert_stderr`), **`:254`**
  (`2>&1 1>/dev/null`, discarding stdout) — all match exactly, correcting revision 4's wrong `:226`/
  `:347`.
- **`doc-guard.test.sh:66-76`** (`run_case`), **`:68`** (`>/dev/null 2>&1`, discarding both channels)
  — matches, correcting revision 4's `:70`.
- **`hooks/merge-guard.test.sh` does not exist** — confirmed (`ls` errors `No such file or
  directory`).
- **`classify-git-command.test.py` is 224 lines** — confirmed via `wc -l`, correcting revision 4's
  236.
- **18 hook scripts, 8 `*.test.sh` suites** — confirmed (26 `*.sh` matches total, 8 of them
  `*.test.sh`).
- **`classify-git-command.py` is 198 lines** — confirmed, under the house 400-line limit task 2 must
  respect.
- **ADR numbering** — highest ADR on `origin/main` is `0026`; `0027` is real and already taken by
  the paused marker-gate branch (`9783956 docs(decisions): ADR 0027 — the marker is a receipt, not a
  grade`), confirming `0029` is the correct next number for this card.

I found no citation or measurement error in this revision. That is a meaningfully different state
than round 2, which found one (`doc-guard.sh:27`, now fixed) and an unbuilt requirement
(`PRINTS_AND_EXITS`, now built — task 3b wires the set into `git-guard.sh`'s message only, and lands
both the print-and-exit Examples Outline and a hand-run mutation scenario proving the message and the
decision never move together). The task-7 "regression signal" gap round 2 flagged — a human-run
table comparison with no automated counterpart — is now explicitly closed: task 7 requires the
defect-table rows to be encoded as permanent cases in the task-0a/0b hook-level harnesses, not left
as a ritual.

## What could go wrong / what I'm unsure about

- **The stderr-surfacing question is real and still open by design.** The spec states, in its own
  words, that it does not know whether stderr from an exit-0 hook (the new `ask` path) is surfaced
  anywhere at all, as opposed to stderr from `exit 2`, which is proven. It assigns the answer to task
  3 rather than guessing. At this design stage that is the right call — asserting an answer without
  running the check would be exactly the kind of fabricated certainty this house's own conventions
  forbid — but it means the "traceability" story (prompt text *plus* a stderr line) could collapse to
  "prompt text only" once task 3 actually runs, and nothing in the design revisits bucket 2's
  cost/benefit if that happens. Worth a one-line contingency note, not a blocker.
- **Task 9 is an irreducible manual gate.** It is now blocking, specific (two named sub-checks), tied
  to the actual permission mode this repo's sessions launch under, and requires pasting the
  observation rather than asserting a pass — genuinely strong scoping. But it remains a single
  point-in-time human check with no mechanism to notice if Claude Code's prompt behaviour later
  changes (version bump, alias edit, mode change). That risk is inherent to the claim being tested,
  not a design flaw, but it means `execution` can't be a clean pass at this stage.
- **Task 0c is itself an open question at judgment time.** "Confirm where these suites actually run…
  If nothing runs them automatically, say so plainly" is honest, but it means the regression-signal
  story task 7 just strengthened (rows becoming permanent test cases) still rests on an unconfirmed
  assumption — that anything executes those test files without a human remembering to. This is
  scoped correctly as groundwork, not deferred indefinitely, so I'm not flagging it as a design gap,
  just an open item worth watching when task 0c lands.
- **`audit_trail` is a reasoned trade-off, not a closed gap.** The "no log file" decision is backed by
  real citations (`merge-guard.sh:93`, `judge-guard.sh:230`, `feature-sync-guard.sh:136` — I did not
  re-verify these three this round since round 2 already confirmed them and nothing in this revision
  touched that section) and a sound volume argument (these hooks run on every Bash call). It will be
  captured in ADR 0029. But six months from now, "how often did `SCOPE_UNKNOWN` fire, and on what"
  still has no queryable answer — only a one-time prompt string and a stderr line whose own
  surfacing is unverified. That is an accepted limit, stated as one, which is the correct way to ship
  it — but it is still a limit.
- **Asymmetric risk is correctly weighted, and that is worth naming as a positive, not a concern.**
  Only `merge-guard.sh` fails silently (under-blocking, a merge that should be refused just works);
  `git-guard.sh` and `doc-guard.sh` fail loud. The design routes the most scrutiny at the one hook
  that fails quietly — a from-scratch test suite (0b) pinning today's behaviour before the rewrite,
  and task 6 explicitly proving the *old* behaviour survives before accepting the new cases. This is
  exactly the right place to spend extra proof, and it's a repeat of the same pattern round 2 already
  credited, still intact.

## What I'd double-check before merging (i.e., before task 11 / PR)

- When task 3 runs, record the stderr-surfacing answer plainly, and if it comes back "swallowed,"
  revisit whether bucket 2's `ask` framing needs a caveat about what the user actually has to rely on
  (the prompt text alone).
- When task 0c runs, if the answer is "nothing runs these automatically," treat that as a follow-up
  worth its own line in the ADR — the task-7 automation work is only a regression signal if something
  executes it.
- Task 9's fallback path (drop to `deny` and revisit bucket 2) is written but never rehearsed — worth
  a one-line gut-check on what `deny`'s message would actually say for `SCOPE_UNKNOWN`, since today's
  `deny` messages are hand-written per guard and this path doesn't have one yet.
- Nothing else — the citation and measurement layer is unusually solid this round; I would not spend
  further judge time re-deriving what's already been re-derived twice.

## Dimension table

| dimension | verdict | why |
|---|---|---|
| intent | pass | Same measured defect throughout; every prior-round finding (round 1's four advisories, round 2's `PRINTS_AND_EXITS` gap and citation drift) was engaged with directly and closed, not reworded or deferred. |
| execution | concern | Task 9 (does `ask` really prompt) is well-scoped but inherently unautomatable; task 0c (do the suites run automatically at all) is an open question at judgment time, not yet answered. Neither is a design flaw, but neither can be called "works" before it runs. |
| trajectory | pass | Four straight revisions plus a self-run pre-dispatch sweep, each one naming its own prior wrong measurement rather than silently overwriting it (the revision-4.1 table is a model example); every citation and count I independently re-checked this round matched exactly. |
| regression | pass | Task 8 dependent suites (including the new `merge-guard` suite), task 5 proves `pr create` unchanged before switching callers, task 3 keeps existing `exit 2` paths byte-identical, task 6 proves *old* `merge-guard` behaviour before accepting new cases. |
| context_budget | pass | Lives in `docs/features/*`, loaded on demand, not an always-on rule/skill/prompt; the one code file that grows (`classify-git-command.py`, 198 lines today) is explicitly bounded under the house 400-line limit in task 2. |
| traceability | pass | Every file:line citation checked this round (11 distinct locations across 5 files, 2 test-count claims) matched the real repo exactly; the one drift round 2 found (`doc-guard.sh:27`→`:127`) is fixed. |
| success_masking | concern | Task 9's manual step and task 0c's unresolved "do these suites run automatically" both mean a green plan could still hide a real gap; mitigated by task 9's blocking/paste-observed framing and by the revision-4.1 fix that stopped an exit-code-only re-run from reporting three still-broken rows as fixed. |
| intent_drift | pass | Entirely responsive to prior findings; out-of-scope section stays honest about what belongs on the paused marker-gate branch instead. |
| checkpoint | pass | Explicit per-hook, independent rollback story: each of the three changed hooks reverts on its own without touching the others; task 7's re-run is the acceptance gate and the later regression signal. |
| audit_trail | concern | Real, reasoned trade-off (no log file, citations accurate, will be captured in ADR 0029) rather than a silent omission — but the underlying gap (no queryable record of how often `SCOPE_UNKNOWN` fires) is unchanged from round 2, and still hinges on the still-unverified stderr-surfacing question. |

## Concerns

- Whether stderr from an exit-0 (`ask`) hook is surfaced anywhere is stated as unverified and
  deferred to task 3 — the right call for a design doc, but it means the traceability story could
  collapse to "prompt text only" once measured, and nothing revisits bucket 2 if it does.
- Task 9 (does `ask` actually raise a prompt under this repo's real permission mode) is a blocking,
  well-scoped, but irreducibly manual, one-time check with no mechanism to notice if permission
  behaviour later changes.
- Task 0c (do the test suites run automatically at all) is an open question at judgment time; task
  7's new automated-regression-signal story is only as strong as that answer turns out to be.
- `audit_trail` remains a stated, ADR-bound trade-off rather than a closed gap — no queryable record
  of how often the new cannot-tell case fires exists or is planned.
- Positive, not a concern: the asymmetric-risk routing (extra proof at `merge-guard.sh`, the one
  silently-failing hook, via tasks 0b and 6) and the revision-4.1 correction of the acceptance measure
  (exit code alone would have called three still-broken rows fixed) are both exactly the right
  instincts and worth preserving as the house pattern for future guard-hook features.

## Risk / confidence

risk=medium confidence=high
