---
phase: implementation
model_tier: high
branch: fix/falsifier-base-pin
---

# The falsifier's baseline moved when its own fix merged

Branched from `main` @ `e0d8546`. User confirmed the gate 2026-08-04 (session 9), immediately after
PR #38 merged. Model-switch checkpoint answered: stay on Opus 5.

This file exists for the same mechanical reason PR #37's did: `phase-guard.sh:288` exempts `docs/*`
but not `hooks/*`, and `docs/features/verification-marker-gate.md` is still at `phase: planning`, so
no source edit is permitted without an `implementation` feature file naming this branch.

## Spec

### Root cause

`hooks/shell-segments-falsifier.sh:14` is `BASE="${1:-main}"`. The script is a **differential**
harness: it materialises two checkouts of `hooks/lib/`, one from `$BASE` and one from the working
tree, runs the same command line through the real `git-guard.sh` against each, and asserts a
per-row `old`/`new` exit-code pair.

That works only while `$BASE` does not contain the fix. `main` is a **moving** ref, and the entire
purpose of the branch that introduced this script was to merge into `main`. So the harness was
guaranteed to invalidate itself on merge — which it did, at `cc035d2`, roughly forty minutes after
being written.

**A differential harness's baseline must be a fixed commit.** A branch that will eventually contain
the change under test is not a baseline; it is the thing being tested, twice.

### The failure it produced

Measured on `main` @ `e0d8546`, the default invocation:

```
FAIL  (a) false denial from 2>&1              old=0 new=0   (want old=2 new=0)
FAIL  (c) leading redirect hid the commit     old=2 new=2   (want old=0 new=2)
FAIL  (c) mid-command redirect                old=2 new=2   (want old=0 new=2)
FAIL  ACCEPTED fail-open: bare digit pathspec old=0 new=0   (want old=2 new=0)
falsifier: 4 row(s) UNEXPECTED                                          # exit 1
```

Every `new=` column is **correct**. Only the `old=` column moved. But nothing in that output says so,
and the four lines read exactly like the fix regressed — the most alarming possible presentation of
a harness problem.

Two properties make this worse than its size suggests:

1. **It fails noisily and permanently.** A check that is always red teaches its reader to skip it.
2. **ADR 0015 cites this script as the evidence the fix works** — deliberately, because
   `git-guard.replay.sh`'s 63-command matrix contains zero redirect shapes and cannot see this defect
   class at all. So the one piece of load-bearing evidence is the piece that broke.

### The fix

Two parts. The pin alone is insufficient — it fixes today's symptom and leaves the failure *mode*
(a silently invalid baseline reported as four content failures) fully intact.

1. **Pin the default** to `bc7da76`, the commit `fix/shell-segments-redirects` branched from, with the
   rule stated in the source: the default base must be a fixed commit, never a branch.
2. **Self-check the baseline before running any row.** Assert the resolved base actually predates the
   fix. If it does not, print one plain sentence naming the problem and how to fix it, and exit
   non-zero — instead of four rows that impugn the implementation.

The probe for "predates the fix" is the defect itself, asked directly of the base lexer: the pre-fix
`segments()` splits on a redirection, so `> out.txt git commit` yields no segment whose `argv[0]` is
`git`. A base where it does is a base that already has the fix.

> **Accepted limit, stated not discovered.** A pinned SHA can become unreachable — a shallow clone, a
> rewritten history, a fresh clone with `--depth`. The script already exits 1 with a named error when
> `git show "$BASE:…"` fails, so that degrades to a clear message rather than a wrong answer. Pinning
> trades a baseline that *silently* went wrong for one that can go *loudly* missing. That is the
> right direction and it is the reason part 2 exists.

### Scenarios

```gherkin
Scenario A: the default base predates the fix
  When bash hooks/shell-segments-falsifier.sh
  Then every row is as expected
   And the exit code is 0

Scenario B: a base that already contains the fix is refused, not misreported
  When bash hooks/shell-segments-falsifier.sh main
  Then the output names the baseline as the problem
   And no row-level FAIL line is printed
   And the exit code is non-zero

Scenario C: an unreachable base is still a named error
  When bash hooks/shell-segments-falsifier.sh 0000000
  Then the output names the unreadable base
   And the exit code is non-zero

Scenario D: an explicit valid base still works
  When bash hooks/shell-segments-falsifier.sh bc7da76
  Then every row is as expected
   And the exit code is 0
```

## Checklist

- [x] 1. Red, reproduced on the unfixed script at `main` @ `e0d8546`: **exit 1, 4 `FAIL` rows, and
      zero mention of the baseline anywhere in the output.** That last part is the actual defect —
      the exit code was arguably right, the explanation was absent.
- [x] 2. Green: default pinned to `bc7da76`; baseline self-check added before any row runs.
- [x] 3. Scenarios A-D verified by execution, `$?` captured immediately (a `$(…)` in the reporting
      line has overwritten it here before):
      | scenario | base | exit | `FAIL` rows | output |
      |---|---|---|---|---|
      | A | default | 0 | 0 | all rows as expected |
      | B | `main` | 1 | **0** (was 4) | names the baseline, says HARNESS not regression, gives the fix |
      | C | `0000000` | 1 | 0 | `cannot read 0000000:hooks/lib/shell_segments.py` |
      | D | `bc7da76` | 0 | 0 | all rows as expected |
      B against A/D is the falsification: the self-check fires on a fixed base and stays silent on a
      pre-fix one, so it is discriminating rather than always-on.
- [x] 4. Third branch (base lexer unreadable/unparseable) confirmed **reachable**, not dead code:
      probed with a deliberately broken module → `ERR SyntaxError: …` → named-error branch. Without
      this the branch would have been untested by all four scenarios.
- [x] 5. Dependent suites unchanged: **492 checks, 0 failed** (35·77·16·134·101·78·51). `bash -n`
      clean. No file outside `hooks/shell-segments-falsifier.sh` changed.
- [ ] 6. Observability judge, then PR.
