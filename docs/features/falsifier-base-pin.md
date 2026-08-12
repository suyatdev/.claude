---
phase: review
model_tier: high
branch: none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted
---

> **Frontmatter correction (2026-08-12):** this card read `phase: implementation` /
> `branch: fix/falsifier-base-pin` for every session since the work merged as **PR #39** (`cbb9f60`),
> with all 6 tasks ticked. The named branch existed in neither the local repo nor `origin`. A card
> claiming to be mid-implementation on a branch that does not exist is the shape the phase gate is
> least able to survive: the survey reported it as live work, and `phase-guard.sh` reads `phase` to
> decide what may be written. Corrected to `review` / `none`. Verified with
> `git log origin/main --merges --grep=falsifier-base-pin` and a local+remote `rev-parse` of the branch.

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
- [x] 6. Observability judge on `d0dac2e` — **`risk=low confidence=high`**, 9/10 pass, one
      `success_masking` concern (the replay harness below). Verdict:
      `coding-memory/observability-judge/2026-08-04-fix-falsifier-base-pin.md`. **PR #39** opened at
      that commit.

## What the judge added, and the one thing it found

It did not take the probe on trust. It extracted **every version of `shell_segments.py` that has ever
existed** and ran the self-check against each — no disagreements — then measured *why* the leading
redirect is the right probe: of the five command shapes the rig tests, it is the **only** one whose
behaviour differs before and after the fix. The other four are identical in both worlds and would
have made a useless probe. It also fed four broken baselines (syntax error, wrong return shape,
missing function, noisy import); all four are refused.

It also said plainly that it passed PR #38 at `risk=low` and **did not catch** that the baseline was
a moving ref — a human found that post-merge. Worth keeping: the judge is a check, not a proof.

### 🆕 The same class is alive in `git-guard.replay.sh` — NOT fixed here

`git-guard.replay.sh:13-15` hard-codes `git show main:…` for all three files it compares, with **no
override parameter** (`grep -c 'BASE_REV|${1:-|getopts'` → 0). Confirmed independently on this
branch: `git-guard.sh`, `classify-git-command.py` and `shell_segments.py` are all **byte-identical to
`main`** right now, so its `378 identical, 0 relaxed, 0 stricter` is a tautology — **a false green**.

Same class, **quieter direction, which is worse**: the falsifier screamed in red, replay smiles and
says nothing. The argument for part 2 of this change applies to it word for word.

Deliberately left for its own branch — widening a fix mid-branch is how this repo has shipped a
second defect alongside the first, and replay needs a *different* remedy (a "base and candidate are
identical, this proves nothing" assertion, plus the base parameter it lacks). Queued.
