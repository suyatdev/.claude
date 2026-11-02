# 0047 — A tracked file that cannot be committed is the defect, and the ratchet gains a declared-exception list

- **Status:** Accepted (2026-09-14). Amends **ADR 0031**; does not supersede it.
- **Context:** `hooks/git-guard.sh` (the default-branch allowlist), `hooks/git-guard.replay.sh`
  (`CMDS`, `EXPECTED_STRICTER`, `EXPECTED_RELAXED`), `.gitattributes`, and the two tracked
  ledgers `coding-memory/observability-judge/verdicts.jsonl` and
  `coding-memory/compliance-judge/verdicts.jsonl`. Full design, task list and the measurement
  record: `docs/features/judge-ledger-commitability.md`.
- **Note on the number:** `0047` was confirmed free on 2026-09-14 against **every remote head**,
  not only `origin/main`. `origin/main` tops out at `0044`, but `0045` and `0046` are already
  claimed by unmerged branches — checking `main` alone would have collided.
- **Note on anchors:** this ADR cites **function, constant and file names**, never `:NNN` line
  numbers. The branch it lands on merged 496 commits of `main` in one step; every line number
  written before that merge was wrong after it.

## Context

ADR 0031 retired the `coding-memory/` tree but deliberately kept exactly two files tracked: the
two judge verdict ledgers. PR #59, implementing it, narrowed the `git-guard.sh` default-branch
allowlist to `docs/*.md` alone.

Those two decisions are individually reasonable and jointly incoherent. A file that is tracked
but cannot be committed on `main` does not stay still — it accumulates uncommitted drift in
whichever worktree touched it last, and the drift is invisible to everyone else. The judges
append a row per verdict, so this is not a hypothetical.

Nothing caught it. That is the more important half of this decision.

## The ratchet was blind, and that is why it stayed quiet

`hooks/git-guard.replay.sh` exists to prove one property: run the baseline guard from `main` and
this branch's guard over the same command matrix in the same fixture states, and no case may
exist where the base blocks and the branch allows. *Never weaker than main.*

The two ledger commands were **never in `CMDS`**. Measured on `origin/main`'s own copy of the
harness: `verdicts.jsonl` appears **0 times**. The allowlist narrowing in PR #59 was therefore
invisible to every replay run that has ever executed — the single failure mode the harness exists
to prevent, produced by the harness silently not covering the thing that changed.

This is not an inference from the source. It was demonstrated live on 2026-09-14 by extracting
`origin/main`'s version of the harness and pointing it at **this branch's already-widened guard** —
the exact situation the ratchet is supposed to catch:

```
base=270a0b9 (origin/main) — 63 commands x 6 states = 378 pairs:
378 identical, 0 stricter (0 unexpected), 0 relaxed (0 distinct commands)
```

A clean sheet. The guard under test allows two commands the baseline blocks, and the old harness
reports **nothing**, with exit 0. The same run under the harness in this branch reports 8 relaxed
cases across 2 distinct commands. The difference is entirely the two rows added to `CMDS`.

**Say precisely what was broken, because "the ratchet was blind" overstates it.** The gate *logic*
was correct the whole time; only its **population** was incomplete. Measured 2026-09-14 by taking
`origin/main`'s harness, injecting the two ledger rows into `CMDS` and changing nothing else — no
`EXPECTED_RELAXED`, which that version does not have:

```
65 commands x 6 states = 390 pairs: 382 identical, 0 stricter, 8 relaxed (2 distinct commands)
REPLAY FAILED: 8 relaxed, 0 unexpected stricter
rc=1
```

The old gate would have caught PR #59 the day it landed, had anyone given it the commands to
replay. This matters for what to conclude: the fix is not "the gate was weak and we strengthened
it" but "a correct gate was asked the wrong question." A differential check inherits every blind
spot of its input matrix, and reports a clean sheet for each one.

This is the standing hazard with any differential check: it goes quiet when the population is
wrong, and a run that reports nothing is indistinguishable from a run that found nothing.

## Decision

**1. The allowlist moved, not the tracking.** `git-guard.sh` re-allows the two ledgers on the
default branch, named as **exact literals** rather than as `coding-memory/*/verdicts.jsonl`. A
third judge is hypothetical; the allowlist should be exactly as wide as the rule it enforces and
no wider. ADR 0031's retirement of the rest of the tree is untouched.

**2. Appends merge instead of conflicting.** `.gitattributes` marks both ledgers `merge=union`,
scoped to those two paths. Two branches each appending a verdict row is the normal case, and a
conflict there is pure friction with no signal in it.

**3. The ratchet's contract changes, by ratification rather than by drift.**
`hooks/git-guard.replay.sh` gains `EXPECTED_RELAXED`. Its headline promise moves from

> never weaker than `main`

to

> never weaker than `main`, **except where declared**.

This is a real weakening of a safety property and is recorded here as a named decision, ratified
by the user on 2026-09-14, precisely so that it is visible to whoever reads this file later
rather than buried in a diff.

### Why this, and not the alternatives

- **Leave the ledgers un-committable.** Rejected: that is the defect, restated.
- **Delete the relaxation gate.** Adding the two commands to `CMDS` (63 → 65; set-compared,
  0 dropped, 2 added, 0 duplicates) makes the run fail by design, because the harness had no way
  to express an *intended* relaxation. Removing the gate to fix this retires weakening-detection
  for all 63 other commands in order to accommodate 2. Rejected as plainly disproportionate.
- **A declared-exception list.** Accepted. It is not a new idea in this file: `EXPECTED_STRICTER`
  already exists on `origin/main` (4 occurrences) for the identical stated reason in the opposite
  direction. The change makes the two directions symmetric rather than inventing a mechanism.

## Consequences

**The gate still discriminates, and this was proven rather than assumed.** Falsifier: drop one of
the two entries from `EXPECTED_RELAXED` in a scratch copy and re-run. Result, measured 2026-09-14
against `origin/main` (`270a0b9`):

```
MUTANT rc=1
REPLAY FAILED: 4 undeclared relaxed (of 8 total), 0 unexpected stricter
```

The unmutated run on the same base is clean:

```
65 commands x 6 states = 390 pairs: 382 identical, 0 stricter (0 unexpected),
8 relaxed (2 distinct commands, 0 undeclared)
```

⚠️ **The falsifier is only trustworthy because of a trap it fell into first.** The entry text
appears **twice** in the file — once in `CMDS`, once in `EXPECTED_RELAXED`. A plain string
replacement edits both, leaves the declaration intact, and the run passes — which reads as *"the
gate is fine"* while nothing was actually mutated. The first attempt did exactly this and was
caught only by an assertion on the occurrence count. Any future mutation of this file must be
scoped to the declaration block and must assert that the block shrank.

**Nothing invokes this harness.** Raised by the observability judge on 2026-09-14 and confirmed:
`hooks/git-guard.replay.sh` is wired to no hook, no runner and no CI step. It is run when a person
remembers to run it. That is true both before and after this change and is not introduced here, but
it bounds every claim on this page: the ratchet protects nothing on its own, declared exceptions or
not. Wiring it is open work and belongs to its own card.

**A degenerate `EXPECTED_RELAXED` crashes rather than reports.** Emptying the list entirely trips
`set -u` on bash 3.2 (the macOS system bash) when the array is expanded, exiting 1 as a crash rather
than as a verdict. Exit 1 is still the safe direction, but the message is a shell error, not a
finding. Removing *entries* — the realistic edit — behaves correctly, as the falsifier above shows.

**The residual risk is human, and is not mitigated by anything here.** A ratchet with a
declared-exception list is exactly as strong as the discipline of whoever maintains the list.
Nothing computational distinguishes a well-considered entry from a careless one; `EXPECTED_RELAXED`
records that a relaxation was *declared*, never that it was *justified*. It is a receipt, not a
grade — the same distinction ADR 0027 draws for test markers. Each entry carries a comment naming
the decision that put it there, and that convention is the whole of the protection.

**The allowlist is now stated at five sites plus a comment**, all corrected together:
`rules/gates.md`, `hooks/README.md` (three places), and
`skills/preparing-pull-requests/SKILL.md`, with `hooks/doc-guard.sh`'s self-describing comment
updated for accuracy. `docs/decisions/0031-…` states the old allowlist inside a mermaid diagram
and is **deliberately left alone**: it is the historical record, amended by this file, not edited.

**A fact that now lives in six places drifts.** That is the known cost of the correction and the
reason each site was re-opened and verified rather than pattern-replaced.
