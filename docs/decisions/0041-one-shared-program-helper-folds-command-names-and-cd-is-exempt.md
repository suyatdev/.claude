# 0041 — One shared `program()` folds command names; `cd` is a named exception

- **Status:** Accepted (2026-09-01).
- **Context:** `hooks/lib/shell_segments.py` gains `program()`; ten command-position
  `argv[0]` comparisons across `classify-git-command.py`, `classify-commit-command.py`,
  `classify-pr-command.py`, `classify-secret-command.py`, `decide-commit-gate.py`,
  `secret_approval.py`, and inline python in `git-guard.sh` and `feature-sync-guard.sh` move
  onto it. **Six** Tier-1 hooks were measured affected through those classifiers —
  `git-guard.sh`, `doc-guard.sh`, `merge-guard.sh`, `secret-command-guard.sh`,
  `test-marker-guard.sh`, `judge-guard.sh`. `feature-sync-guard.sh` reads the same
  classifiers and its call site is in the same list, so it is fixed too, but it was **not
  probed** — that is inference from the code, not a measured row, and is recorded as such
  rather than folded into the six. Tests were written first
  and separately (`80e0318`, `b410df0`), before the implementation (`797663e`). Builds on
  **ADR 0013** (the shared lexer) and its amendments **0015** and **0040**; changes none of
  their decisions. Full measurement record:
  `docs/features/argv0-spelling-blindness.md`.
- **Note:** ADR number **0041** was confirmed free across **all 22 remote branches**
  (`git ls-remote --heads origin`, each tree searched with `git ls-tree`), not merely against
  local `main` — a number that collides on an unmerged branch merges cleanly, because the
  filenames differ, so nothing ever surfaces it. Highest number seen anywhere: `0040`.
  `0028` remains an unused gap and is left alone rather than backfilled.

## Context

Every Tier-1 guard in this repo decides whether to refuse by asking one question of a lexed
segment: *is `argv[0]` the program I police?* Each asked it with a literal string comparison
— `argv[0] == "git"`, `argv[0] != "gh"`, `argv[0] in ("env", "printenv")`.

A literal comparison is only as good as the assumption that there is one way to write the
name. There are two more, and both really execute:

- **Case.** This machine's filesystem is case-insensitive, so `PATH` resolution finds
  `/usr/bin/git` when the shell is asked for `Git` or `GIT`. Measured: `Git --version` and
  `GIT --version` both print `git version 2.50.1 (Apple Git-155)`; `GH --version` prints
  `gh version 2.96.0`.
- **Path.** `/usr/bin/git` is the same binary named a different way, on every platform.

Measured pre-fix, with a lowercase control that genuinely refused in every group, all six
affected guards allowed both spellings while refusing the lowercase bare name. The tracked
probe is `hooks/argv0-task6-guards.probe.sh` (four guards) and
`hooks/argv0-task9-guards.probe.sh` (the two that route through shared classifiers).

**`Git commit` is a plausible typo, not an attack**, which is what makes it the worse failure
mode: the guard is silent, so the user believes the checkpoint ran. This is a
**momentum-guardrail gap, not a security-boundary breach** — every one of these hooks already
ships a documented one-flag bypass, and this ADR does not claim otherwise. What changes is
whether an *accident* is caught.

## Decision — one shared helper, not ten local fixes

```python
def program(token):
    if token.endswith("/"):
        return ""
    return token.rsplit("/", 1)[-1].lower()
```

Ten sites, one definition. The alternative — folding at each call site — was rejected on the
ordinary DRY grounds, but also on a specific one: the sites do not agree on the *shape* of
their test (`==`, `!=`, `in` a tuple), so ten local folds would be ten opportunities for one
to be written differently, and the difference would be invisible until a guard went quiet.

### `program()` is **total** — it never raises

This is the load-bearing constraint, and it is not stylistic. The guards fail in **opposite
directions** when a classifier misbehaves:

| Site | Behavior on classifier failure |
|---|---|
| `hooks/git-guard.sh:75` | prints `failing closed`, `exit 2` — **refuses** |
| `hooks/secret-command-guard.sh:146` | `[ "$status" -eq 2 ] \|\| exit 0` — **allows** |

A `program()` that raised would therefore block git operations loudly while **silently
disarming the highest-value guard in the set** — the noisy symptom and the dangerous one
would arrive together, and the noisy one would get the attention. Totality is asserted
directly (`""`, `"/"`, `"///"`, `"foo/"`), not inferred from the callers passing.

This ADR does **not** change `secret-command-guard.sh`'s fail-open. That is a deliberate,
documented property of a hook sitting on nearly every Bash call. The obligation taken on here
is to not *depend* on it.

## Decision — `cd` is folded nowhere, and that is a fail-open being avoided

`OPAQUE_TARGETS = ("git", "cd")`, so the membership test at `classify-git-command.py:400`
(`:399` before this change) could not simply be folded — "fold the tuple test" and "never
fold `cd`" are contradictory instructions when the tuple contains `cd`. It is split
explicitly:

```python
# command position, so git folds and cd does not
if iargv and (program(iargv[0]) == "git" or iargv[0] == "cd"):
```

**Why `cd` must not fold, stated here because it is the part a future reader will otherwise
undo as an inconsistency:** measured, `CD /tmp && pwd` prints the **original** directory.
Capitalized `cd` resolves to `/usr/bin/cd`, a real binary on this system that changes
directory in a child process and exits, so the shell never moves. Folding `cd` would make the
guard believe a directory change happened that did not — introducing a **fail-open in a change
whose entire purpose is closing one**.

Confirmed at the classifier with the lowercase form as a control that *does* emit the fact:
`cd /other && git commit -m x` → `['COMMIT', 'SEG_CD\t0\t/other']`, while `CD /other && …`
and `/usr/bin/cd /other && …` both → `['COMMIT']`. Today's behavior is already correct here;
the change preserves it rather than producing it.

Subcommands and flags are likewise never folded, because they are genuinely case-sensitive at
runtime: `git COMMIT -m x` → `fatal: cannot handle COMMIT as a builtin`, `gh PR list` →
`unknown command "PR" for "gh"`. Folding them would invent refusals for commands that cannot
run. `classify-git-command.py:424` (`:423` before this change) also stays literal: it scans
`argv[1:]`, which is not command position, and folding there would contradict `program()`'s
own docstring.

## Accepted costs

- On a **case-sensitive** filesystem `GIT commit` cannot run at all, and the guard now refuses
  it anyway. That refusal is free — the command was going to fail with "command not found".
- A binary at `/tmp/mytools/git` is treated as git. Both are fail-closed by intent: a guard
  that refuses something harmless is cheap; one that allows something guarded is not.
- **`hooks/shell-segments-falsifier.sh` needed a shim.** Its differential harness pairs a
  pinned pre-fix `shell_segments.py` with today's rest-of-lib, and today's
  `classify-git-command.py` now imports `program` by name — which the pinned base does not
  define, so the classifier failed to import and git-guard fell back to failing closed on
  every row. The script's existing `has_grouping` shim documents exactly this failure mode;
  `program` gets the same treatment with one deliberate difference: `has_grouping` may be a
  constant because git-guard reads no fact it feeds, whereas `program()` decides whether a
  segment is git at all, so the shim must be the **real implementation verbatim** or it would
  move every row. This is a standing maintenance cost of the differential harness, recorded
  so the next symbol added to `shell_segments.py` is expected to pay it too.

## What this does not fix

Recorded so the change cannot imply a wider claim than it earns. Each is measured and pinned
as an ALLOW assertion, so widening is a deliberate edit rather than silent drift.

- **`SEG_OPAQUE` fails open** — `env git commit -m x` is allowed, and is allowed for the
  **lowercase** form too. Unrelated to spelling, pre-existing, and **the larger hole of the
  two**. Its own card.
- **Interpreter strings** — `sh -c 'git commit -m x'` is invisible to a lexer by construction.
- **Capitalized wrapper words** — `TIME git commit` lands in the `SEG_OPAQUE` hole above
  rather than in a guard. Fixing wrappers without fixing `SEG_OPAQUE` buys nothing.
- **Unicode case folding** is measured and closed rather than left open: the dotted capital-I
  spelling `GİT` (U+0130) does not resolve to the git binary on this machine's APFS
  (`command not found` under both zsh and bash), and independently `'GİT'.lower()` on
  Python 3.9.6 returns `'gi̇t'` — four codepoints, including U+0307 COMBINING DOT ABOVE —
  which is **not** `'git'`. A gap requires both preconditions; neither holds, so no assertion
  is pinned for a behavior that cannot be observed running.

## Verification

- Tests written first and in a **separate commit** from the implementation, then falsified
  against an always-allow and an always-deny stub: the both-pass intersection was **empty**,
  so no assertion discriminates nothing.
- Full suite after the change: **22 suites, 2059 passed, 0 failed.** Two suites report in an
  `N/N passed` format the count parser cannot read; both were run and read by hand (27/27,
  37/37) and are included in that total, rather than being silently dropped.
- The tracked probe's `UNMEASURED` precondition — which aborts rather than printing a clean
  table when a lowercase control fails to refuse — was itself falsified by substituting an
  always-allow stub for one guard: that group reported `UNMEASURED (rc=0)`, the other three
  still printed full tables, and the probe exited 1. A guard clause that has never fired is
  indistinguishable from one that cannot.
- **Three of the first-written assertions were wrong and were corrected in their own commit**
  (`5d66395`): they expected hook exit `4` for the capitalized env-dump forms, but exit 4 is
  the classifier's *internal* status and the hook translates it to exit `2`, which is what the
  lowercase controls in the same file had always asserted. The correction is kept separate
  from the implementation so the record shows a wrong baseline being fixed rather than a fix
  being fitted to its own exam.
