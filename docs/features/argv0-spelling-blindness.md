---
phase: implementation
model_tier: high
branch: fix/argv0-spelling-blindness
---

# Every Tier-1 guard trusts one exact spelling of a command name

Queued 2026-09-01, out of the "still open" section of
`docs/features/shell-lexer-comment-blindness.md` (PR #92, merged 2026-09-01). That card
recorded one shape — `Git commit` with a capital G — as pre-existing and deliberately
unfixed. Measurement here found the defect is **two spellings across four guards**, not
one shape in one guard.

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

Probe: `hooks/…` invoked with a `PreToolUse` payload (`hook_event_name`, `tool_name`,
`tool_input.command`, `cwd`, `session_id`).

| Guard | lowercase (control) | `Git` | `GIT` | `/usr/bin/git` |
|---|---|---|---|---|
| `git-guard.sh` | **rc=2 refused** | rc=0 | rc=0 | rc=0 |
| `doc-guard.sh` | **rc=2 refused** | rc=0 | rc=0 | rc=0 |
| `merge-guard.sh` ¹ | **rc=2 refused** | rc=0 | — | rc=0 |
| `secret-command-guard.sh` ² | **rc=2 refused** | rc=0 | — | rc=0 |

¹ `gh pr merge 5` / `Gh pr merge 5` / `/opt/homebrew/bin/gh pr merge 5`.
² `env` and `printenv` / `ENV` and `Printenv` / `/usr/bin/env`.

**`test-marker-guard.sh` is UNMEASURED.** Its lowercase control also returned rc=0 in this
fixture (no sibling-test pair staged), so the probe could not discriminate and its rows say
nothing. `judge-guard.sh` and `feature-sync-guard.sh` read the same classifiers but were not
probed. Do not read this table as covering them.

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

As of 2026-09-01 that returns **19 lines**, of which **5 are prose** -- two docstrings
(`classify-git-command.py:272`, `:326`), two comments in `shell_segments.py` (`:50`,
`:287`) and one in `worktree_guard_bash_arms.sh:185`. The remaining **14 are real
tests**. (Revision 1 wrote "14 lines"; the command emits 19 and 14 is the count after
the prose is dropped by eye. Re-measured task 1, 2026-09-01, with `command grep` --
a bare `grep` on this machine is ugrep and honours `.gitignore`.)

Of those 14, these are **command-position program tests that must move onto
`program()`**:

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

Recorded so the PR cannot imply a wider claim than it earns. **Three rows are measured and
pinned as ALLOW assertions; the fourth is unmeasured and is deliberately NOT pinned** —
pinning a behavior nobody has observed would assert a guess. Count the rows here rather
than trusting any number written in prose.

| Shape | Measured | Pinned? | Why out of scope |
|---|---|---|---|
| `env git commit -m x` | `git-guard.sh` rc=0; facts `SEG_OPAQUE 0 env` | yes | Fails open for the **lowercase** form too. A pre-existing `SEG_OPAQUE` hole, unrelated to spelling. Its own card. |
| `sh -c 'git commit -m x'` | `git-guard.sh` rc=0 | yes | A command inside an interpreter string is invisible to a lexer by construction. Long-standing, documented. |
| `TIME git commit`, `Time git commit` | facts `SEG_OPAQUE 0 TIME` / `Time` | yes | A capitalized `WRAPPERS` entry is not stripped, so the segment lands in the `SEG_OPAQUE` hole above rather than in a guard. Fixing wrappers without fixing `SEG_OPAQUE` buys nothing. |
| Unicode case folding, e.g. `GİT` | **not measured** | **no** | `str.lower()` on Python 3.9.6 is Unicode-aware, but whether its folding agrees with APFS's own case-folding table is unknown and untested. Task 8 decides: measure it, or say plainly it is untested. |

**`SEG_OPAQUE` failing open is the larger hole of the two.** It is not made worse by this
change, and it is not made better. Anyone reading "the guards now catch misspelled command
names" should read this table alongside it.

## Tasks

- [x] 1. **Done 2026-09-01.** Re-ran the derivation on this branch (base `6444871`).
      19 lines out, 5 prose, 14 tests. All 14 are already in the two tables: the 10
      must-move rows and 4 of the 5 must-NOT-move rows. The 5th must-not-move row,
      `classify-git-command.py:423`, is **not matched by the command at all** -- it
      tests `argv[1:]`, and the pattern anchors on `argv[0]`; confirmed present and
      unchanged by reading the file. **Zero unclassified sites.** Every line number
      in both tables still resolves to the stated code on this base -- no drift.
- [ ] 2. Red first: add case, path, `cd`-not-folded, and `program()`-is-total assertions to
      `hooks/lib/shell_segments.test.py` and each affected classifier's `.test.py`.
      Confirm each fails for the right reason before writing `program()`.
- [ ] 3. Falsify the new assertions against an always-allow and an always-deny stub; any
      assertion passing under both discriminates nothing and must be rewritten.
- [ ] 4. Add `program()` to `hooks/lib/shell_segments.py` with its Google-style docstring.
      Assert totality directly — `""`, `"/"`, `"///"`, `"foo/"` — because
      `secret-command-guard.sh:146` fails OPEN on a crash. (No `__all__` entry: verified
      2026-09-01 that `shell_segments.py` defines none; consumers import by name.)
- [ ] 5. Move the ten command-position sites onto `program()`, `OPAQUE_TARGETS:399` in the
      split form shown above. Leave every row of the "must NOT move" table untouched.
- [ ] 6. Commit the hook-level probe as a tracked script beside the existing
      `hooks/*.probe.sh`, with "the lowercase control refuses" as a hard precondition that
      aborts the run rather than reporting a clean table. Record before/after here.
- [ ] 7. Confirm — do not assume — that `hooks/shell-segments-falsifier.sh:78` must stay
      literal, by checking what it measures against.
- [ ] 8. Decide the Unicode row: measure `GİT` against APFS resolution, or state in the
      card that it is untested. Do not pin an assertion either way until measured.
- [ ] 9. Establish whether `test-marker-guard.sh` and `judge-guard.sh` are affected, with a
      fixture whose control actually refuses. Record the answer; fix only if affected.
- [ ] 10. Run the full suite. Record pass/fail counts **and the deselected count**.
- [ ] 11. ADR under `docs/decisions/` — the fail-closed trade, the `cd` exception, and the
      `OPAQUE_TARGETS` split are all direction-setting, and the `cd` reasoning is the part
      a future reader will otherwise undo.
- [ ] 12. Close out `docs/features/shell-lexer-comment-blindness.md`: `phase: review`,
      `branch: none  # merged via PR #92 (115e244) 2026-09-01`.

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
