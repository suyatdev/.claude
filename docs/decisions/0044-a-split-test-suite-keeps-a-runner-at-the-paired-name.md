# 0044 — A split test suite keeps a runner at the paired name, or the gate it feeds goes silent

- **Status:** Accepted (2026-09-09).
- **Context:** `panes/dispatch-pane-agent.test.sh` (now a 60-line runner), the six concern
  suites `panes/dispatch-pane-agent.{dispatch,policy,routing,cleanup,scratch,subcommands}.test.sh`,
  and `panes/test-lib.sh`. The pairing rules this decision turns on live in
  `hooks/lib/write-test-marker.py` (`PAIR_SUFFIXES`, `derive_subject`) and
  `hooks/lib/decide-commit-gate.py` (`_classify_role`, `_form_pairs`). Full design, the
  measurement record and the checklist: `docs/features/pane-dispatch-test-suite-split.md`.
- **Note:** ADR number **0044** was confirmed free against `origin/main` on 2026-09-09;
  the highest present there is `0043`. Filenames differ even under a same-day collision, so a
  racing `0044` from another branch would merge cleanly rather than conflict.
- **Note on anchors:** this ADR deliberately cites **function and constant names**, not line
  numbers. The card it belongs to has a standing rule that every `:NNN` in it died when the
  963-line suite was deleted, and repeating that mistake here would be gratuitous.

## Context

`panes/dispatch-pane-agent.test.sh` reached 963 lines against a stated 800-line hard maximum,
and was split into six concern files. The obvious final step — delete the original — turns out
to disarm a Tier-1 guard, silently.

The verification-marker gate pairs a source file with its test by **name and name only**:
`X.sh` ↔ `X.test.sh`, `X.py` ↔ `X.test.py`. Two consequences follow, and neither was in the
card's plan, which had assumed "six files where there was one means six markers":

1. Each concern file is named `dispatch-pane-agent.<concern>.test.sh`, so `derive_subject`
   yields `dispatch-pane-agent.<concern>.sh` — a file that does not exist. Every one of the six
   prints `marker skipped: … has no tracked subject` and writes **no marker at all**. Six files
   where there was one means *zero* markers, not six.

2. More seriously, `_form_pairs` skips a staged subject whose sibling test is neither tracked
   nor present on disk, with the comment `no sibling test at all -- never gated, per Scope`.
   Deleting the original therefore leaves `panes/dispatch-pane-agent.sh` — 545 lines of
   production dispatcher — paired with nothing.

Measured against the real `_form_pairs`, both conditions on the same function, no commit made:

| Condition | pairs formed for staging `panes/dispatch-pane-agent.sh` |
|---|---|
| sibling test present (before the split) | `[('panes/dispatch-pane-agent.sh', 'panes/dispatch-pane-agent.test.sh')]` |
| sibling test absent (after the split) | `[]` |

The failure mode is the one this repository's rules keep naming: **a guard that has stopped
guarding is indistinguishable from a guard that is working.** No error is raised, no commit is
refused, and the only visible signal — `marker skipped` on stderr of a suite nobody reads the
stderr of — reports the symptom rather than the consequence.

## Decision

**A test suite that is split into concern files keeps a runner at the original, paired name.**

`panes/dispatch-pane-agent.test.sh` is now a 60-line runner holding no assertions of its own.
It:

- invokes the six by **explicit name**, not by glob — a glob cannot distinguish "this suite was
  deleted" from "this suite never existed", and a shrinking glob still reports green;
- **re-emits each child's assertion lines verbatim** on its own stdout, so the runner's output
  is the complete RUN-SET and the label-set proof works against it unchanged;
- **counts those lines itself** rather than trusting a child's summary line;
- **folds any child's non-zero exit into `fail`**, so `tl_finish` cannot write a marker for a
  run in which a bucket file died partway — the "receipt for work not done" failure the split
  exists to avoid;
- emits a label **only on failure**, so a green run is exactly the 139 the proof expects.

Verified after the change: the marker for `panes/dispatch-pane-agent.sh` is written again and
its recorded `test` blob is the runner's blob.

## Alternatives considered

**Teach the pairing rules an `X.<concern>.test.sh → X.sh` rule.** Correct in the long run, and
it would generalise to any future split. Declined for this branch because it edits two Tier-1
scripts that every commit in the repository passes through, which deserves its own card, its
own falsification suite and its own review — not a rider on a refactor. If a second suite is
ever split, this becomes the better answer and should be reopened.

**Accept the loss and record it as a residual.** Declined. The whole argument for the marker
gate is that a receipt is worth having; a residual that says "the receipt is no longer produced
and nothing will tell you" converts a guard into decoration while leaving its documentation
intact, which is worse than never having had it.

## Consequences

- The 800-line problem is fixed: 445 / 195 / 140 / 131 / 130 / 79, plus the 60-line runner and
  a 63-line shared `panes/test-lib.sh`. `routing` at 445 is over the 400 preferred and is a
  stated residual on the card.
- One more file exists than a naive split would produce, and adding a seventh concern file
  means editing the runner's `SUITES` list. That is deliberate: the edit is the point at which
  a human notices a suite was added or removed.
- **Residual, stated rather than discovered later:** the six concern files remain orphan
  suites that write no marker of their own, exactly as the three pre-existing orphan suites in
  this repository do. The gate is armed through the runner, not through them. Editing one
  concern file without touching the dispatcher does not by itself invalidate the marker — the
  gate's guarantee has always been about the *subject's* bytes — but the narrowing is real and
  is named here so nobody has to rediscover it.
- The runner's own `bad` labels (`concern suite present: …`, `concern suite exited 0: …`) are
  outside the 139-label set by construction, since they are emitted only when something has
  already gone wrong. A green run's label count is therefore still exactly 139, which is what
  the task-8 count check asserts.
