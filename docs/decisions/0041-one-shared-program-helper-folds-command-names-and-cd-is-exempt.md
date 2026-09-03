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

Measured pre-fix, with a lowercase control that genuinely refused in every group: each guard
probed allowed both spellings while refusing the lowercase bare name. Which guards those are
is named once, in the Context bullet above, and the runnable evidence is
`hooks/argv0-task6-guards.probe.sh` and `hooks/argv0-task9-guards.probe.sh` — run them
rather than trusting a count here. (This sentence said "all six" until round 4; it is the
same restated arithmetic as the rest, one paragraph away from the list it restated.)

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

**The authoritative list is the card's Known-gaps table**
(`docs/features/argv0-spelling-blindness.md`), which records per row whether it was measured
and whether it is pinned. The bullets below carry the *decision rationale* for leaving each
one open — which the table does not — and deliberately carry no count, no ranking among
themselves, and no `all`/`each` quantifier. Four successive compliance rounds each found one
more restated count in these two documents; the fix is that they no longer restate.

Recorded so the change cannot imply a wider claim than it earns. Which of these are pinned
as ALLOW assertions, and which are deliberately not, is stated **per row in the card's
Known-gaps table** — see `docs/features/argv0-spelling-blindness.md`, which also tells the
reader to count the rows there rather than trust a figure in prose.

**This paragraph deliberately carries no count and no "all"/"each" quantifier.** Two
successive compliance rounds failed it here for exactly that: first a universal that was
false in both halves, then — in the very edit that fixed the universal — a count and a
singular "the fourth" left behind when a fifth bullet was added below. A sentence that
restates the table's arithmetic has to be re-derived every time the table changes, and it
has now been wrong twice. There is one place that number lives, and it is not here.

- **`SEG_OPAQUE` fails open** — `env git commit -m x` is allowed, and is allowed for the
  **lowercase** form too. Unrelated to spelling, pre-existing, and **a bigger hole than
  anything this change closes**. Its own card. (That comparison is against this change, not
  a rank among the bullets below it: this sentence said "the larger hole of the two" until
  round 4, having been written when there were two, and it is the same species of stale
  arithmetic the paragraph above this list now refuses to carry. The card's copy of the
  sentence was fixed in round 2 and this one was not — one statement, two homes, which is
  the class itself.)
- **Interpreter strings** — `sh -c 'git commit -m x'` is invisible to a lexer by construction.
- **Capitalized wrapper words** — `TIME git commit` lands in the `SEG_OPAQUE` hole above
  rather than in a guard. Fixing wrappers without fixing `SEG_OPAQUE` buys nothing.
- **Secret FILE names are not case-folded.** This ADR folds the **program** name;
  `classify-secret-command.py`'s `DOTFILE_PATTERNS` match the **file** name and are
  untouched, so `cat .ENV`, `cat .Env`, `cat ~/.ZSHRC` and `cat CREDENTIALS.json` all allow
  while their lowercase forms block (measured through the hook with a `PreToolUse` payload,
  executing nothing). Pre-existing and not widened here — but on the same case-insensitive
  filesystem and behind the same guard, which makes it the gap a reader is most likely to
  assume this change closed. Folding filenames is a **different decision with a different
  blast radius** (it would fold every path a user legitimately names in caps), so it is
  deliberately left to `secret-command-guard`'s own card:
  `docs/features/secret-filename-case-blindness.md`.
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
- Full suite after the change: measured green at `7b2db03`, with no failing suite in that
  run. (Scoped to a commit on purpose: "no failures in any suite" with no commit attached is
  an unpinned universal about a branch, and a suite total is a measurement of one tree.) The
  pass total
  itself is recorded once, in the card's task 10, pinned to the commit it was measured at —
  it is not repeated here, because a total copied into a second document goes stale the next
  time anyone adds an assertion, and that is precisely how this bullet was wrong on its
  first draft. Note when reading it: two suites report in an `N/N passed` format the runner's
  parser cannot read, so they are run and read by hand and are included deliberately rather
  than dropped silently.
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
