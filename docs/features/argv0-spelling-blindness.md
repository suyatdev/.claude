---
phase: implementation
model_tier: high
branch: fix/argv0-spelling-blindness
---

# Every Tier-1 guard trusts one exact spelling of a command name

Queued 2026-09-01, out of the "still open" section of
`docs/features/shell-lexer-comment-blindness.md` (PR #92, merged 2026-09-01). That card
recorded one shape — `Git commit` with a capital G — as pre-existing and deliberately
unfixed. Measurement here found the defect is **two spellings, in the shared classifiers
every Tier-1 guard reads**, not one shape in one guard. How many guards that is, and which
ones were probed rather than inferred, is stated in the measurement tables below — this
sentence deliberately does not restate it.

⚠️ **Corrected 2026-09-01 (compliance judge, round 4).** This line said "across four
guards", which was true when the card was opened (`b6628fa`) and went stale the moment
**task 9 measured `test-marker-guard.sh` and `judge-guard.sh` affected as well** — inside
this same document, three judge rounds before anyone noticed. It is the same species as the
two ADR failures rounds 2 and 3 caught: a count derived elsewhere, retyped where it cannot
be kept in step. Fixed the same way — the count is gone, not corrected.

Gate: **confirmed 2026-09-01.** Branch `fix/argv0-spelling-blindness`, from `origin/main` (6444871).

Round 1 of both judges returned against an earlier revision of this card and is folded in
below: compliance `fail` (4 violations), observability `risk=medium`. Every finding
reproduced. What changed is recorded in "Round-1 corrections" at the end — including three
factual claims this card stated and got wrong.

## Why this matters

Every Tier-1 guard in this repo decides whether to refuse by asking the same question of a
lexed command segment: *is `argv[0]` the program I police?* Each asks it with a literal
string comparison — `argv[0] == "git"`, `argv[0] != "gh"`, `argv[0] in ("env", "printenv")`.

A literal comparison is only as good as the assumption that there is one way to write the
name. There are two more, and both really execute:

- **Case.** This machine's filesystem is case-insensitive, so `PATH` resolution finds
  `/usr/bin/git` when the shell is asked for `Git` or `GIT`.
- **Path.** `/usr/bin/git` is the same binary named a different way, on every platform.

Neither is exotic. `Git commit` is a plausible typo, not an attack, which is what makes it
the worse failure: the guard is silent, so the user believes the checkpoint ran.

## Toolchain, pinned

| Tool | Version | Why it is pinned here |
|---|---|---|
| `python3` | 3.9.6 (`/usr/bin/python3`, Apple) | The helper's case folding is `str.lower()`; folding semantics are interpreter-version behavior, and this card reasons about them. |
| `git` | 2.50.1 (Apple Git-155) | Subcommand and flag case-sensitivity is measured against this build. |
| `gh` | 2.96.0 | Same, for `gh pr` parsing. |

## Measured: the current behavior

All rows below ran the **real hook scripts** against a scratch repo on `main` with a
120-function source file staged, so the lowercase row is a control that is *known* to
refuse. A group whose control allows is reported as unmeasured, never as a clean result.

Probe: `hooks/argv0-task6-guards.probe.sh`, tracked (task 6), invoked with a `PreToolUse`
payload (`hook_event_name`, `tool_name`, `tool_input.command`, `cwd`, `session_id`). The
lowercase control's refusal is a hard precondition in that script: it aborts the group
(prints `UNMEASURED`, exits 1) rather than printing rows for a fixture that never engaged
the guard.

**Before** — pre-fix, measured during planning (throwaway probe, not committed):

| Guard | lowercase (control) | `Git` | `GIT` | `/usr/bin/git` |
|---|---|---|---|---|
| `git-guard.sh` | **rc=2 refused** | rc=0 | rc=0 | rc=0 |
| `doc-guard.sh` | **rc=2 refused** | rc=0 | rc=0 | rc=0 |
| `merge-guard.sh` ¹ | **rc=2 refused** | rc=0 | — | rc=0 |
| `secret-command-guard.sh` ² | **rc=2 refused** | rc=0 | — | rc=0 |

¹ `gh pr merge 5` / `Gh pr merge 5` / `/opt/homebrew/bin/gh pr merge 5`.
² `env` and `printenv` / `ENV` and `Printenv` / `/usr/bin/env`.

**After** — re-measured task 6, 2026-09-01, `hooks/argv0-task6-guards.probe.sh` against
commit `566d1f7` (task 7, HEAD of this branch at the time of the run). Every lowercase
control refused (verified before any spelling row for that guard was reported), so all four
groups are measured, not blind:

| Guard | lowercase (control) | `Git`/`Gh`/`ENV` | `GIT`/`Printenv` | path form |
|---|---|---|---|---|
| `git-guard.sh` | **rc=2 refused** | rc=2 | rc=2 | rc=2 |
| `doc-guard.sh` | **rc=2 refused** | rc=2 | rc=2 | rc=2 |
| `merge-guard.sh` ¹ | **rc=2 refused** | rc=2 | — | rc=2 |
| `secret-command-guard.sh` ² | **rc=2 refused** | rc=2 | rc=2 | rc=2 |

Every previously-blind row (`Git`, `GIT`, `/usr/bin/git`, `Gh`, `ENV`, `Printenv`,
`/usr/bin/env`) now refuses, matching its lowercase control. No row failed to flip.

**`test-marker-guard.sh` and `judge-guard.sh` are now measured, and both are affected.**
Fixture and controls (`hooks/argv0-task9-guards.probe.sh`, tracked): a scratch repo with a
`foo.py`/`foo.test.py` sibling pair staged and no marker written gives
`test-marker-guard.sh` a control that refuses (`MSG_NO_MARKER`); a scratch repo with an
initial commit and no verdict store gives `judge-guard.sh` a control that refuses (no
verdict store). Both controls **do** refuse, so the group is measured, not blind like the
first round.

| Guard | lowercase (control) | `Git`/`Gh` | `GIT`/`GH` | path form |
|---|---|---|---|---|
| `test-marker-guard.sh` | **rc=2 refused** (`MSG_NO_MARKER`) | rc=0 | rc=0 | rc=0 (`/usr/bin/git`) |
| `judge-guard.sh` | **rc=2 refused** (no verdict store) | rc=0 | rc=0 | rc=0 (`/opt/homebrew/bin/gh`) |

Both guards are affected, but through call sites **already in the must-move table** above:
`test-marker-guard.sh` classifies via `decide-commit-gate.py` → `classify-commit-command.py`,
whose `argv[0] != "git"` at `:213` is already row 4 of the must-move table. `judge-guard.sh`
classifies via `classify-pr-command.py`, whose `argv[0] != "gh"` at `:55` is already row 5.
Neither guard has its own separate literal-comparison site — task 5 fixing those two shared
classifiers closes both guards for free. No new row is added to the must-move table.

`feature-sync-guard.sh` reads the same classifiers but was not probed this round; its call
site (`argv[0] == "git"` inline python, `:130`) is already in the must-move table too, so the
same reasoning applies, but this is inference from the code, not a measured row — flagged
here rather than silently claimed as measured.

**The first probe round was blind and is recorded here as the reason for the payload note
above.** It omitted `hook_event_name`, and `secret-command-guard.sh` exits 0 at its event
check before doing any work — so `env`, `ENV`, `printenv` and `/usr/bin/env` all returned
rc=0 and the group read as *uniformly allowed*, which is a different and wrong conclusion
from *uniformly unchecked*. Caught only because the lowercase control failed to refuse.

### That the capitalized forms really run

| Command | result |
|---|---|
| `Git --version`, `GIT --version` | `git version 2.50.1 (Apple Git-155)` |
| `GH --version` | `gh version 2.96.0 (2026-07-02)` |

Verified through `zsh -c` and `bash -c`, not only through Python's `execvp`.

⚠️ **Do not verify the `ENV` / `Printenv` row by running it.** Doing so prints the real
environment. A judge did exactly that during round 1 and dumped a live API key into its
context; the key was rotated. The classifier-level assertion (`classify-secret-command.py`
returns the env-dump status) establishes the same fact without executing anything.

### What is already correct, and must stay correct

The lexer handles the rest of the family. These classify correctly today and are
regression surface, not work:

| Spelling | facts from `classify-git-command.py` |
|---|---|
| `\git commit -m x -- foo.sh` | `COMMIT`, `COMMIT_PATH foo.sh`, `COMMIT_PATHSPEC` |
| `'git' commit …`, `gi't' commit …` | same |
| `command git commit …`, `exec git commit …` | same |

Subcommands and flags are genuinely case-sensitive in the real tools, so folding them would
invent refusals for commands that cannot run. **git's message depends on the arguments** —
both forms were measured, and the card quotes each against the invocation that produced it:

| Command | real result |
|---|---|
| `git COMMIT -m x` | `fatal: cannot handle COMMIT as a builtin` |
| `git COMMIT --help`, `git Commit --help` | `git: 'COMMIT' is not a git command.` |
| `gh PR list`, `gh Pr list` | `unknown command "PR" for "gh"` |
| `git rev-parse --Abbrev-ref HEAD` | flag not recognized, echoed back literally |

## Design

One helper, in the file every call site already imports.

```python
# hooks/lib/shell_segments.py

def program(token):
    """Canonical program name for a token in COMMAND POSITION.

    Strips any directory component and folds case, so `/usr/bin/Git`, `GIT` and
    `git` all answer `git`.

    Total by contract: never raises, for any str input. Callers are Tier-1 guards
    whose fail directions differ (see "Fail direction"), so a raising helper would
    disarm one guard while blocking another. A non-str input is the caller's bug
    and is allowed to raise.

    Use ONLY where the token is in command position -- never for subcommands,
    flags, `cd`, or a scan over `argv[1:]`, all of which are case-sensitive or
    position-sensitive at runtime (see the measurement tables).

    Args:
        token: the raw argv[0] string from `segments()`.

    Returns:
        The lowercased basename, or "" for a token that cannot name an
        executable (empty, or ending in "/").
    """
```

### Call sites — derived, not remembered

The earlier revision said "five call sites" from memory and was wrong. The list is
**derived by this command**, and task 1 re-runs it so the count cannot go stale:

```
grep -rn -E 'argv\[0\][^=!]*(==|!=|[[:space:]]in[[:space:]])' hooks \
  --include=*.py --include=*.sh | grep -v '\.test\.'
```

At the task-1 base `6444871` that returns **19 lines**, of which **5 are prose** -- two docstrings
(`classify-git-command.py:272`, `:326`), two comments in `shell_segments.py` (`:50`,
`:287`) and one in `worktree_guard_bash_arms.sh:185`. The remaining **14 are real
tests**. (Revision 1 wrote "14 lines"; the command emits 19 and 14 is the count after
the prose is dropped by eye. Re-measured task 1, 2026-09-01, with `command grep` --
a bare `grep` on this machine is ugrep and honours `.gitignore`.)

**Re-run at HEAD during the round-5 sweep: still 19 lines.** The ten sites were edited in
place, so nothing shifted, and the three call-site citations quoted in the task-9 paragraphs
above (`classify-commit-command.py:213`, `classify-pr-command.py:55`,
`feature-sync-guard.sh:130`) were re-opened and all three still resolve to the stated code.
That is luck rather than design — re-run the command rather than trusting them.

Of those 14, these are **command-position program tests that must move onto
`program()`**.

⚠️ **Every line number in both tables below is as measured at the task-1 base,
`6444871` — the pre-change tree.** They are deliberately NOT updated to HEAD: the tables
record where the defect was found, and a citation pinned to a fixed tree cannot go stale,
whereas one chased to HEAD goes stale on the next edit. Six of them have in fact moved since
(`:437`→`:438`, `:520`→`:521`, `:399`→`:400`, `:434`→`:435`, `:423`→`:424`, and the
falsifier's `:78`→`:101`); ADR 0041 annotates its copies of two of these, which is itself the
one-statement-two-homes shape this card kept failing on. To locate a site at HEAD, re-run the
derivation command above rather than trusting either number. (Flagged as a non-blocking note
by the compliance judge, round 5.)

| File:line | Test | Note |
|---|---|---|
| `hooks/lib/classify-git-command.py:437` | `argv[0] == "git"` | |
| `hooks/lib/classify-git-command.py:520` | `argv[0] != "git"` | |
| `hooks/lib/classify-git-command.py:399` | `iargv[0] in OPAQUE_TARGETS` | see below — **partial** |
| `hooks/lib/classify-commit-command.py:213` | `argv[0] != "git"` | |
| `hooks/lib/classify-pr-command.py:55` | `argv[0] != "gh"` | |
| `hooks/lib/classify-secret-command.py:189` | `argv[0] in ("env","printenv")` | |
| `hooks/lib/decide-commit-gate.py:76` | `argv[0] != "git"` | **missed in revision 1** |
| `hooks/lib/secret_approval.py:422` | `argv[0] in WRAPPERS` | **missed in revision 1** |
| `hooks/git-guard.sh:358` | `argv[0] != "git"` (inline python) | **missed in revision 1** |
| `hooks/feature-sync-guard.sh:130` | `argv[0] == "git"` (inline python) | |

And these are **command-position tests that must NOT move**:

| File:line | Test | Why it stays literal |
|---|---|---|
| `classify-git-command.py:434` | `argv[0] == "cd"` | `cd` is not folded — see below |
| `classify-commit-command.py:210` | `argv[0] == "cd"` | same |
| `decide-commit-gate.py:73` | `argv[0] == "cd"` | same |
| `classify-git-command.py:423` | `tok in OPAQUE_TARGETS for tok in argv[1:]` | **not command position** — a scan over the rest of the line. Folding here would contradict `program()`'s own docstring. |
| `hooks/shell-segments-falsifier.sh:78` | `argv[0] == "git"` | A falsifier that pins pre-fix behavior. Changing it would change the thing it measures against. Task 7 confirms this rather than assuming it. |

### `OPAQUE_TARGETS` is the one genuinely ambiguous site

`OPAQUE_TARGETS = ("git", "cd")` (`classify-git-command.py:199`). "Fold the membership test"
and "never fold `cd`" are contradictory instructions if written as one line — round 1's
compliance judge was right to call that unbuildable. The resolution is explicit:

```python
# classify-git-command.py:399 -- command position, so git folds and cd does not
if iargv and (program(iargv[0]) == "git" or iargv[0] == "cd"):
```

`:423` is left exactly as it is: it scans `argv[1:]`, which is not command position.

### Deliberately not folded

- **`cd`.** Measured: `CD /tmp && pwd` prints the **original** directory. Capitalized `cd`
  resolves to `/usr/bin/cd` — a real binary on this system, which changes directory in a
  child process and exits, so the shell never moves. (Revision 1 said `/bin/cd`; that path
  does not exist here. `command -v cd` resolves to the shell builtin.) Folding `cd` would
  make the guard believe a directory change happened that did not — a fail-*open*
  introduced by a fix meant to close one.

  Confirmed at the classifier, with the lowercase form as a control that *does* emit the
  fact: `cd /other && git commit -m x` → `['COMMIT', 'SEG_CD\t0\t/other']`, while
  `CD /other && …` and `/usr/bin/cd /other && …` both → `['COMMIT']`. Today's behavior is
  already correct here; the change must preserve it, not produce it.

- **Subcommands and flags** — case-sensitive at runtime, per the table above.

### Fail direction — the requirement round 1 added

The guards do **not** fail the same way when a classifier misbehaves:

| Site | Behavior on classifier failure |
|---|---|
| `hooks/git-guard.sh:75` | prints `failing closed`, `exit 2` — **refuses** |
| `hooks/secret-command-guard.sh:146` | `[ "$status" -eq 2 ] \|\| exit 0` — **allows** |

So a `program()` that raises would block git operations loudly while silently disarming the
highest-value guard in the set. This is the same shape as the defect the previous card
closed, and it is why `program()` is specified as total. Task 4 asserts it directly rather
than trusting the implementation.

This card does **not** change `secret-command-guard.sh`'s fail-open. That is a deliberate,
documented property of that hook (its blast radius is nearly every Bash call). The card's
obligation is to not depend on it.

### Behavior change, stated as a cost

On a case-sensitive filesystem, `GIT commit` cannot run at all, and after this change the
guard refuses it anyway. That refusal is free: the command was going to fail with
"command not found". A binary at `/tmp/mytools/git` is likewise treated as git. Both are
fail-closed by intent — a guard that refuses something harmless is cheap, one that allows
something guarded is not.

## Scenarios

```gherkin
Scenario: a capitalized name is refused like its lowercase form
  Given the checkout is on main with a substantial source change staged
  When the Bash command is "Git commit -m x"
  Then git-guard.sh exits 2
  And its message is the one "git commit -m x" produces for that same checkout state

Scenario: an absolute path is refused like a bare name
  Given the checkout is on main with a substantial source change staged
  When the Bash command is "/usr/bin/git commit -m x"
  Then git-guard.sh exits 2

Scenario: a capitalized environment dump is refused
  Given classify-secret-command.py is called directly, so nothing is executed
  When the command text is "ENV"
  Then it reports the bare-environment-dump status
  And "Printenv" and "/usr/bin/env" report the same status

Scenario: a capitalized wrapper is not approvable
  Given secret_approval.py is asked whether a command may be approved
  When the command is "Nohup cat .env"
  Then it refuses for the same wrapper reason "nohup cat .env" refuses for

Scenario: cd is NOT folded, because capitalized cd does not change directory
  Given the segment list for "CD /other && git commit -m x"
  When classify-git-command.py classifies it
  Then no SEG_CD fact is emitted for the "CD" segment
  And the control "cd /other && git commit -m x" DOES emit SEG_CD

Scenario: a case-sensitive subcommand is not folded into a match
  When the Bash command is "git COMMIT -m x"
  Then no COMMIT fact is emitted
  And git-guard.sh exits 0, because git itself rejects the subcommand

Scenario: program() is total, so no guard is disarmed by a helper crash
  When program() is called with any str, including "", "/", "///", and "foo/"
  Then it returns a str and never raises

Scenario: the already-correct spellings do not regress
  When the Bash command is any of "\git commit", "'git' commit", "command git commit"
  Then the facts are identical to those for "git commit"
```

## Known gaps — measured, and NOT closed by this change

Recorded so the PR cannot imply a wider claim than it earns. **All five rows are measured.
Three are pinned as ALLOW assertions; two are deliberately NOT pinned** — not because
they are unmeasured. The Unicode row is unpinned because what task 8 measured is that the
shape *cannot run here at all*, and an assertion for a behavior nobody can observe would
assert a guess; the filename row is unpinned because it belongs to another card and pinning
it here would imply this branch owns it. Count the rows here rather than trusting any number
written in prose.

⚠️ **Corrected 2026-09-01 (compliance judge, round 2).** This preamble read "three rows are
measured … the fourth is unmeasured", which was true when it was written and went stale the
moment task 8 measured the Unicode row inside this same document. Worse, row 3
(`TIME`/`Time git commit`) said `Pinned? yes` while **no assertion for that shape existed
anywhere in the repo** — a claim about a test that had never been written. Both are now
true: the row is pinned at `hooks/lib/classify-git-command.test.py`, in
`ARGV0_SPELLING_CASES`, as two ALLOW rows plus a lowercase `time git commit` control that
reaches `COMMIT` — without that control the two ALLOW rows could pass for an unrelated
reason.

| Shape | Measured | Pinned? | Why out of scope |
|---|---|---|---|
| `env git commit -m x` | `git-guard.sh` rc=0; facts `SEG_OPAQUE 0 env` | yes | Fails open for the **lowercase** form too. A pre-existing `SEG_OPAQUE` hole, unrelated to spelling. Its own card. |
| `sh -c 'git commit -m x'` | `git-guard.sh` rc=0 | yes | A command inside an interpreter string is invisible to a lexer by construction. Long-standing, documented. |
| `TIME git commit`, `Time git commit` | facts `SEG_OPAQUE 0 TIME` / `Time` | yes | A capitalized `WRAPPERS` entry is not stripped, so the segment lands in the `SEG_OPAQUE` hole above rather than in a guard. Fixing wrappers without fixing `SEG_OPAQUE` buys nothing. |
| Unicode case folding, e.g. `GİT` (dotted capital I, U+0130) | **measured, task 8** | **no** | Neither precondition for a gap holds. (1) `zsh -c "GİT --version"` and `bash -c "GİT --version"` both → `command not found` (rc=127) on this machine's APFS — it does not resolve to the git binary at all, so nothing is owed on that ground alone. (2) Independently, Python 3.9.6's `'GİT'.lower()` → `'gi̇t'` (4 codepoints: `g`, `i`, U+0307 COMBINING DOT ABOVE, `t`), which is **not equal** to `'git'` — confirmed `'GİT'.lower() == 'git'` is `False`. So even on a filesystem where this spelling did resolve, a `program()` built on `str.lower()` would not catch it. Per the card's own decision rule, a gap requires BOTH preconditions; here neither holds, so this is not an unclosed gap on this toolchain, and no assertion is pinned for a behavior that cannot be observed running. |
| **Secret FILE names are not case-folded** -- `cat .ENV`, `cat .Env`, `cat ~/.ZSHRC`, `cat CREDENTIALS.json` | **measured 2026-09-01** | **no** | This change folds the **program** name (`argv[0]`); `classify-secret-command.py`'s `DOTFILE_PATTERNS` (`:137`-`:147`) match the **file** name and were never folded -- untouched by this branch (`797663e` changes exactly two lines in that file: the `from shell_segments import` line and the `argv[0]` test itself — an earlier version of this cell said both were on the `argv[0]` test, which is off by one). Pre-existing and **not widened here**, but on the same case-insensitive filesystem and behind the same guard, so a reader who takes "the guards now catch misspelled names" to cover `cat ~/.ZSHRC` would be wrong. Measured through the hook with a `PreToolUse` payload, executing nothing: `.env`/`~/.zshrc`/`credentials.json` block (rc=2), all four capitalized spellings allow (rc=0). Deliberately NOT pinned and NOT fixed here -- folding filenames is a different decision with a different blast radius (it would also fold every path a user legitimately names in caps), and it belongs to `secret-command-guard`'s own card. Found by the observability judge, round 2. |

**`SEG_OPAQUE` failing open is the largest hole in this table** — it is not made worse by
this change, and it is not made better. (This sentence read "the larger hole of the two"
until round 2 added a fifth row; the ranking survived, the arithmetic did not.) Anyone
reading "the guards now catch misspelled command names" should read this whole table
alongside it — and the filename row in particular, because it is the one a reader is most
likely to assume this change covered.

Follow-up card for the filename row: `docs/features/secret-filename-case-blindness.md`.

## Tasks

- [x] 1. **Done 2026-09-01.** Re-ran the derivation on this branch (base `6444871`).
      19 lines out, 5 prose, 14 tests. All 14 are already in the two tables: the 10
      must-move rows and 4 of the 5 must-NOT-move rows. The 5th must-not-move row,
      `classify-git-command.py:423`, is **not matched by the command at all** -- it
      tests `argv[1:]`, and the pattern anchors on `argv[0]`; confirmed present and
      unchanged by reading the file. **Zero unclassified sites.** Every line number
      in both tables still resolves to the stated code on this base -- no drift.
- [x] 2. **Done 2026-09-01.** Red-first assertions added to `hooks/lib/shell_segments.test.py`
      (`PROGRAM_CASES`/`check_program()` -- 16 rows, all fail on ABSENCE of `program()`),
      `classify-git-command.test.py` (`ARGV0_SPELLING_CASES` -- 13 rows), 3 rows each in
      `classify-commit-command.test.py` and `classify-pr-command.test.py`, 4 rows in
      `hooks/secret-command-guard.test.sh` (3 env-dump fold + 1 `Nohup` wrapper fold), and
      3 rows in `hooks/test-marker-guard.test.sh` calling `decide-commit-gate.py`'s
      `_unsupported_trigger()` directly (isolated from `classify-commit-command.py:213`,
      a separate call site). **Every new assertion except the `program()` rows fails on a
      WRONG CLASSIFICATION** (verbatim failure text recorded below); the `program()` rows
      fail on ABSENCE, the only correct failure mode before the helper exists. That split
      is the claim worth making, and it is the one recorded; a headcount of assertions is
      not (see the correction note below). No `os.environ`/`process.env`/bare
      `env`/`printenv` was ever executed -- the `ENV`/`Printenv`/path rows are asserted
      through `classify-secret-command.py`'s exit code via the hook's normal JSON-on-stdin
      path, per the card's warning. Full suite counts: shell_segments 59/1,
      classify-git-command 212/4, classify-commit-command 54/3, classify-pr-command 60/3,
      secret-command-guard 164/4, test-marker-guard 248/1.

      ⚠️ **Corrected 2026-09-02 (compliance judge, round 5).** This entry carried two
      assertion tallies and both were wrong: "42 fail on a wrong classification" (42 is the
      *total*, not that subset) and "61 new assertions total (16 `program()` + 45
      classifier/hook-level)" (which adds the 16 a second time). The enumeration one
      sentence earlier -- 16 + 13 + 3 + 3 + 4 + 3 -- comes to 42, not 61. **The tallies are
      deleted rather than corrected.** Two independent recounts, the judge's and one written
      here, disagreed with each other as well as with the card, and a hand-rolled counter
      across four different test-file styles is exactly the kind of derivation that produces
      a confident wrong number; replacing one unverified figure with another is not a fix.
      The suite before/after counts above and in task 10 come from real runs and stand.
      **Completion pass, 2026-09-01:** the first pass's prompt omitted two of the ten
      must-move sites -- `hooks/git-guard.sh:358` and `hooks/feature-sync-guard.sh:130`,
      both inline python embedded in a shell script, so neither has an importable
      module the way `decide-commit-gate.py` does. Both are gated behind
      `classify-git-command.py:520`'s own COMMIT-fact bug: pre-fix, a capitalized/path
      `git` invocation never sets COMMIT at all, so the guard body containing each site
      is never entered end to end, regardless of the site's own bug. Isolated the same
      way task 2 isolated `decide-commit-gate.py`'s own check -- by extracting just the
      function/assignment from the REAL script text (awk, start/end markers rather than
      a hardcoded line range, so extraction survives drift) and sourcing it, so the
      assertions run the actual bytes of the hook, not a copy. 3 RED rows each in
      `hooks/git-guard.test.sh` (`prints_and_exits_option()`) and
      `hooks/feature-sync-guard.test.sh` (the `exempt_reason` assignment), plus one
      lowercase control per file that is asserted to pass today (confirmed: git-guard's
      control reports `--version`, feature-sync-guard's reports `reason`) -- 8
      assertions total, 6 new failures. Full suite counts after: git-guard 168/3
      (was 167/0), feature-sync-guard 31/3 (was 30/0). No new must-move row: both sites
      were already in task 1's table.
- [x] 3. **Done 2026-09-01.** Falsified every non-`program()` new assertion (the
      `program()` rows are pinned separately against the stand-in allow/deny functions
      described below, since `program()` itself does not exist yet) against an always-allow
      stub (returns "nothing detected": `[]` / `"OTHER"` / `"NONE"` / `("NO","")` / exit 0 /
      `""`) and an always-deny stub (returns a fixed maximal/triggered value: a superset
      fact list / `"COMMIT"` / `"UNSUPPORTED"` / `("PR","")` / exit 2 / `"git"`).
      **Intersection (pass under BOTH stubs): empty** -- every assertion falsified fails
      against at least one stub, which is the result that matters and does not depend on a
      headcount. The rows that pass under the allow-stub are the deliberate negative and
      control rows (`git COMMIT`, `timeout 5 GIT commit`, `gh PR create`,
      `CD /other && ...` for `classify-git-command`); each still fails under deny, proving
      none is vacuous.

      ⚠️ **Corrected 2026-09-02 (compliance judge, round 5).** This entry read "all 45
      non-`program()` assertions ... 38 fail against allow, 34 against deny; the 7 that pass
      under allow". Those three figures were derived from task 2's wrong base of 45 and are
      deleted with it. The empty intersection and the named control rows were separately
      re-checked and stand.
      Full per-assertion scorecard recorded in the branch's task report to the user,
      not duplicated here -- see PR/commit history for this branch.
- [x] 4. **Done 2026-09-01.** Added `program()` to `hooks/lib/shell_segments.py` with the
      card's docstring verbatim. `shell_segments unit: 60 passed, 0 failed` (was 59/1) --
      the 16 `PROGRAM_CASES` rows, including the four totality rows (`""`, `"/"`, `"///"`,
      `"foo/"`), now pass against the real implementation instead of failing on absence.
      No `__all__` entry added.
- [x] 5. **Done 2026-09-01.** Moved all ten command-position sites onto `program()`:
      `classify-git-command.py:400,438,521` (`:400`'s `OPAQUE_TARGETS` test split exactly as
      shown -- `program(iargv[0]) == "git" or iargv[0] == "cd"`), `classify-commit-command.py:213`,
      `classify-pr-command.py:55`, `classify-secret-command.py:189`, `decide-commit-gate.py:76`
      (via `_CLASSIFIER.program`, since that module loads `classify-commit-command.py`
      dynamically and now inherits its `program` import), `secret_approval.py:422`,
      `git-guard.sh:358` and `feature-sync-guard.sh:130` (both inline python, via
      `mod.program` / a added `program` import inside the embedded script). Every row of the
      "must NOT move" table -- the two `argv[0] == "cd"` checks in `classify-git-command.py`
      and `classify-commit-command.py`, `decide-commit-gate.py`'s `cd` check, the
      `any(tok in OPAQUE_TARGETS for tok in argv[1:])` scan, and the falsifier's
      `argv[0] == "git"` baseline sentinel -- confirmed untouched by re-reading the file
      after the edit. (Named by the code they contain rather than by line number: a citation
      into a file this branch edits is self-invalidating, and the same anchors were already
      caught stale once.)

      Before/after, the eight suites named in the dispatch. ⚠️ **These are an audit-trail
      entry, measured at `797663e` — the tasks 4/5 commit — and deliberately not updated
      since.** Two rows have moved on purpose in later commits and would otherwise read as
      contradictions of task 10: `classify-git-command` 216 → **219** (round 2's three
      wrapper-gap assertions, `7b2db03`) and `secret-command-guard` 165/3 → **168/0** (the
      three wrong-exit-code assertions corrected in `5d66395`). **Task 10 carries the
      current figures; this table records what that one commit measured.** Rewriting an
      audit trail to fix a footnote corrupts the record.


      | Suite | Before | After |
      |---|---|---|
      | shell_segments | 59/1 | 60/0 |
      | classify-git-command | 212/4 | 216/0 |
      | classify-commit-command | 54/3 | 57/0 |
      | classify-pr-command | 60/3 | 63/0 |
      | secret-command-guard | 164/4 | 165/3 |
      | test-marker-guard | 248/1 | 249/0 |
      | git-guard | 168/3 | 171/0 |
      | feature-sync-guard | 31/3 | 34/0 |

      **3 of the 22 assertions red at `b410df0` did not turn green, and this was a test bug,
      not an implementation gap.** (22 is the red count measured at that commit, before the
      round-2 additions; it is an audit-trail figure, not a current one.) `hooks/secret-command-guard.test.sh`'s three new
      `argv0-spelling` rows for `ENV`/`Printenv`/`/usr/bin/env` (lines ~972-977) assert the
      *outer hook's* exit code is `4`. But `secret-command-guard.sh:134-144` documents and
      implements exit 4 as an *internal classifier* status that the hook always translates
      to `exit 2` before returning -- exactly like the already-passing lowercase controls at
      lines 773-774, which assert `2` for bare `env`/`printenv`. Manually confirmed: after
      this fix, `ENV` piped through the real hook now exits `2` with stderr
      `blocked -- a bare 'ENV' with no arguments dumps the full inherited environment` --
      byte-for-byte the same shape as the lowercase case, which is exactly what this card
      requires. The test's own `want=4` is inconsistent with its neighbor assertions and was
      not corrected here per instructions not to edit test files; flagging for the
      orchestrator rather than silently working around it. Every other suite run under
      `hooks/` and `hooks/lib/` (18 `.test.sh` + 6 `.test.py`, full list in commit) passed
      with no new failures and no count regression.
- [x] 6. **Done 2026-09-01.** Committed `hooks/argv0-task6-guards.probe.sh`, covering the
      card's original four guards (`git-guard.sh`, `doc-guard.sh`, `merge-guard.sh`,
      `secret-command-guard.sh`) and spellings, following `argv0-task9-guards.probe.sh`'s
      shape. The lowercase control's refusal is a hard precondition per guard
      (`assert_control_refuses`): a control that does not refuse aborts that group as
      `UNMEASURED` and sets the script's overall exit to 1, rather than printing a table
      that would look clean. Never executes the env-dump forms -- `env`/`printenv`/`ENV`/
      `Printenv`/`/usr/bin/env` are passed only as JSON command text. Before/after recorded
      above in "Measured: the current behavior": all four lowercase controls refused, and
      every after-row flipped from rc=0 to rc=2 -- no row failed to flip.
- [x] 7. **Done 2026-09-01. Confirmed: it must stay literal — and the fix broke the
      harness around it, which is the more important finding.**

      *The comparison itself:* the site (now `:101`, moved by the shim below) is the
      falsifier's own **baseline sentinel**. It asks the *pinned pre-fix lexer* whether a
      leading redirect still hides the command — `PRE-FIX` if no segment starts with `git`,
      `FIXED` if one does — and aborts the whole run when the baseline turns out to already
      contain the change under test. Folding it would call `program()` on a `shell_segments`
      copy from `bc7da76`, which predates the function. Left literal.

      *What running it exposed:* the falsifier reported **3 rows UNEXPECTED**, including its
      own BASELINE row (`old=2`, want `old=0`) — and its header says that when BASELINE or
      CONTROL differ, the harness is broken and no other row means anything. Diagnosed, not
      guessed: the OLD arm pairs the pinned `shell_segments.py` with **today's** rest-of-lib,
      today's `classify-git-command.py:114` now imports `program` by name, and the pinned
      base defines it zero times (measured). The import fails, git-guard cannot run its
      classifier, and it **fails closed** — so every row read "block" for a reason with
      nothing to do with redirections. This is precisely the failure mode the script's own
      `has_grouping` comment was written to prevent, arriving through a second symbol.

      Fixed the way the script already established: append a `program` shim to the old lib.
      **Unlike `has_grouping`, a constant would be a fabrication** — `program()` decides
      whether a segment is git at all, so a stub would move every row. The shim is the real
      implementation copied verbatim, which is what keeps the two trees differing only in
      redirect handling. After the shim: **all rows as expected.**

      ⚠️ This was invisible to the task-10 suite run, which globs `*.test.sh` / `*.test.py`;
      the falsifier is neither. It has to be run by hand.
- [x] 8. **Done 2026-09-01.** Measured: `GİT` (U+0130) resolves to `command not found` on
      this machine's APFS (zsh and bash both rc=127), and independently
      `'GİT'.lower() != 'git'` on Python 3.9.6. Neither precondition for a gap holds, so
      no assertion is pinned.
- [x] 9. **Done 2026-09-01.** Both `test-marker-guard.sh` and `judge-guard.sh` are affected
      — measured against a fixture whose control actually refuses
      (`hooks/argv0-task9-guards.probe.sh`). Both classify through call sites already in
      the must-move table (`classify-commit-command.py:213`, `classify-pr-command.py:55`),
      so task 5 closes them; no new must-move row added.
- [x] 10. **Done 2026-09-01.** Every suite under `hooks/` and `hooks/lib/`:
      **22 suites, 2062 passed, 0 failed**, every suite exiting 0. There is no pytest
      `addopts` and therefore no deselected count in this repo -- the analogue is a suite
      whose count line cannot be parsed, and that was checked rather than assumed: two
      suites (`memsearch-nudge.test.sh`, `verify-hook-wiring.test.sh`) report in an
      `N/N passed` format instead of `N passed, M failed`, and both were run and read by
      hand -- 27/27 and 37/37. Their 64 tests are included in the 2062. No suite ran zero
      tests.

      ⚠️ **This total is pinned to a commit, and is re-measured whenever a test changes.**
      Measured at **`7b2db03`**. It was `2059` at `eb02618`; the three assertions added in
      `7b2db03` to close the compliance judge's round-2 finding moved
      `classify-git-command` from 216 to 219, and the total with it. The first version of
      this line was not re-measured after that edit — caught by the compliance judge, round
      3. A pass total is a measurement of one tree, never a property of the branch.

      Per-suite (at `7b2db03`): context-handoff-watch 43, create-worktree 89, doc-guard 27,
      feature-sync-guard 34, git-guard 171, install-layer2 40, judge-guard 101,
      classify-commit-command 57, classify-git-command 219, classify-pr-command 63,
      shell_segments 60, write-test-marker 65, memsearch-nudge 27, merge-guard 10,
      pane-dispatch-guard 34, phase-guard 147, reference-transaction 182, scan-secrets 17,
      secret-command-guard 168, test-marker-guard 249, verify-hook-wiring 37,
      worktree-guard 222.
- [x] 11. **Done 2026-09-01.** `docs/decisions/0041-one-shared-program-helper-folds-command-names-and-cd-is-exempt.md`.
      Number confirmed free across **all 22 remote branches** (`git ls-remote --heads
      origin`, each tree searched with `git ls-tree`) rather than against local `main` alone
      — a number that collides on an unmerged branch merges cleanly, because the filenames
      differ, so nothing would ever surface it.

      Every factual claim in it was re-run before it was written down, and two were wrong:
      the `OPAQUE_TARGETS` split is at `:400` post-change (not `:399`) and the `argv[1:]`
      scan at `:424` (not `:423`); both now cite the post-change number and name the
      pre-change one. `git-guard.sh:75` was checked and is correct — it is the `if !` that
      opens the fail-closed block, whose body runs to `:78`. The ADR also scopes "six Tier-1
      hooks affected" to the six actually **probed**, and records `feature-sync-guard.sh`
      separately as inference.
- [x] 12. **Done 2026-09-01.** `docs/features/shell-lexer-comment-blindness.md` moved from
      `phase: implementation` / `branch: fix/shell-lexer-comment-blindness` to
      `phase: review` / `branch: none  # merged via PR #92 (115e244) 2026-09-01`.

### Judge round 2 — what the two judges found after implementation

Both ran on the finished branch at `eb02618`. Every finding was reproduced before it was
acted on; one was reproduced and found **wrong**, and is recorded here rather than quietly
dropped.

1. **Compliance judge, `fail`, 1 violation — upheld.** The Known-gaps table said the
   `TIME`/`Time git commit` row was `Pinned? yes` while **no assertion for that shape existed
   anywhere in the repo**, and the preamble still called the Unicode row "unmeasured" after
   task 8 had measured it inside this same document. ADR 0041 then flattened both into "each
   is measured and pinned", a universal false in both halves. Fixed: the row is now genuinely
   pinned (two ALLOW rows plus a lowercase `time git commit` control that reaches `COMMIT`,
   without which the ALLOW rows could pass for an unrelated reason), and both the preamble
   and the ADR sentence now state what is actually true.

2. **Observability judge, `risk=low` — one finding upheld and promoted to a table row.**
   Secret **file** names are not case-folded, so `cat .ENV`, `cat .Env`, `cat ~/.ZSHRC` and
   `cat CREDENTIALS.json` all allow while their lowercase forms block. Reproduced through the
   hook with a `PreToolUse` payload, executing nothing. Pre-existing and untouched by this
   branch, but on the same filesystem and behind the same guard — exactly the thing a reader
   would assume this change covered. Now the fifth row above, with its own follow-up card.

3. **Observability judge's second finding — upheld, and annotated rather than removed.** The
   `timeout 5 GIT commit -m x` row expects an **empty** fact set, which also passes if the
   classifier stopped emitting facts entirely. The fact it pins is a real decision, so the
   row stays; it now carries a warning that it pins an accepted fail-open and is not
   coverage.

4. **Observability judge's third finding — NOT upheld.** It reported that "two files now
   disagree about what counts as a wrapper word". Checked: there is exactly **one**
   `WRAPPERS` definition, `shell_segments.py:70`, and every consumer imports it —
   `classify-commit-command.py:35`, `classify-pr-command.py:25`, `secret_approval.py:216`.
   No copy exists to drift.

   What is real, and is probably what the judge saw imprecisely, is an **asymmetry in how two
   sites consult that one list**: the lexer strips wrappers with a literal test
   (`shell_segments.py:330`, `seg[0] in WRAPPERS`) while `secret_approval.py:422` now folds
   (`program(argv[0]) in WRAPPERS`). So `Nohup cat .env` is refused approval while
   `TIME git commit` is still not stripped. That asymmetry is **deliberate and fails
   closed** in both directions: the approval refusal is the safe answer, and the unstripped
   wrapper is Known-gaps row 3, which this card explicitly declines to fix because doing so
   without fixing `SEG_OPAQUE` buys nothing. `shell_segments.py:330` is not in the must-move
   table — it tests `seg[0]` in a stripping loop, not a command-position program test.

### Task 6 addendum — the probe's precondition was itself falsified

The probe reported every lowercase control refusing, so its `UNMEASURED` abort path **never
fired** — and a guard clause that never fires reads identically to one that *cannot* fire.
Falsified by substituting an always-allow stub for one guard's script and re-running:
`merge-guard.sh` reported `UNMEASURED -- lowercase control did not refuse (rc=0, expected
2)`, the other three groups still printed their full `rc=2` tables, and the probe exited 1.
So the precondition fires, is scoped to the group whose control failed, and does not suppress
the groups that are still measurable.

## Implementation corrections

Recorded for the same reason as the round-1 list below: a spec that quietly fixes its own
errors teaches the next reader nothing.

1. **Three of task 2's assertions asserted the wrong exit code.** The capitalized
   `ENV` / `Printenv` / `/usr/bin/env` rows in `hooks/secret-command-guard.test.sh` were
   written expecting hook exit **4**. Exit 4 is the *classifier's internal* env-dump status;
   `secret-command-guard.sh` translates it to hook exit **2** (its `if [ "$status" -eq 4 ]`
   branch ends in `exit 2`), so 4 is unreachable at the hook boundary. The lowercase controls
   twenty lines above have always asserted 2, and the failing rows' own comment said they
   must behave "exactly like the lowercase controls" -- the stated intent was right and only
   the number was wrong. Corrected to 2 in a commit of its own, separate from the
   implementation commit, so the record shows a baseline being fixed rather than a fix being
   fitted to its own exam.

   Verified independently before the edit, by invoking the hook with a `PreToolUse` payload
   and reading its exit code -- **nothing was executed**: `env`, `printenv`, `ENV`,
   `Printenv` and `/usr/bin/env` all return rc=2 with the identical message
   `blocked -- a bare '<name>' with no arguments dumps the full inherited environment`,
   differing only in the quoted name. That identity is the actual proof the fold works.

2. **Two of the ten must-move sites were initially left untested** -- `git-guard.sh:358` and
   `feature-sync-guard.sh:130`, the two inline-python sites. The omission was in the task-2
   dispatch's file list, not in the card. Closed by a separate completion pass (`b410df0`)
   before any implementation was written.

## Round-1 corrections

Recorded because a spec that quietly fixes its own errors teaches the next reader nothing.

1. **Three factual claims were wrong.** `/bin/cd` does not exist on this machine
   (`/usr/bin/cd` does); `git COMMIT -m x` prints `fatal: cannot handle COMMIT as a builtin`,
   not the `--help` form's message; and `str.lower()` was described as "ASCII-correct" when
   Python 3.9.6's is Unicode-aware. The underlying behavioral claims survived — capitalized
   `cd` still does not change directory, subcommands are still case-sensitive — but the
   evidence cited for them did not.
2. **The call-site count was wrong** — "five", derived from memory, against ten. The list is
   now derived by a command that task 1 re-runs.
3. **`OPAQUE_TARGETS` was unbuildable as written**, instructing both "fold" and "never fold
   `cd`" for a tuple containing `cd`.
4. **The fail-direction asymmetry was absent**, and it is the finding with real teeth.
5. **The probe was untracked** and the Unicode row was to be pinned while unmeasured.

## Out of scope

- `rules/gates.md` gets no new text (user decision, 2026-09-01). That file is already
  carrying ~489 words in one always-loaded bullet and has a trim owed from PR #89.
- The `SEG_OPAQUE` fail-open, and the interpreter-string blindness. Both above.
- `secret-command-guard.sh`'s fail-open on classifier error. Depended on, not changed.
