---
phase: implementation
model_tier: low
branch: feat/hook-exec-bit-pr-guard
---

# Refuse a pull request while a registered hook is stored non-runnable

Planned 2026-10-17 on `docs/hook-exec-bit-pr-guard`, cut from `origin/main` @ `61d69dd` (PR #112
merge). Follow-up of `docs/features/hook-exec-bit-test.md` (phase `review`), which left its check
hand-run (its R7a) and set "teaching `verify-hook-wiring.sh` to read the git mode" and "adding CI"
aside as separate decisions. Code is written by a Sonnet implementer; judges run on Opus. Nothing
here is built until Mark types `gate confirmed`.

## Why

A hook script that git stores as `100644` cannot be started by Claude Code (exit 126), and the
hook silently does nothing. It has happened twice, and both came in through a PR:
`hooks/dependency-guard.sh` (#109, fixed in #110) and `hooks/handoff/handoff-keep-guard.sh`
(added `ecd3ba0`, registered `da18d30`, merged in #105, fixed in #112).

What exists today catches it too late or only by hand:

- `hooks/verify-hook-wiring.sh` (SessionStart) checks the bit **on disk** in the main checkout
  (`os.access(path, os.X_OK)`, `hooks/verify-hook-wiring.sh:149`). It speaks only after the merge
  and pull, when the guard is already dead, and never when the disk copy is executable but git
  stores `100644`.
- `hooks/registered-hooks-executable.test.sh` checks the git mode of every registered script, but
  only when someone runs it.

## Decisions

Mark (2026-10-17):

- **Catch it when a pull request is opened**, by refusing `gh pr create`. Chosen over a SessionStart
  warning (fires after the merge), a global git `pre-commit` hook (runs in every repo on the
  machine, needs its own install step) and GitHub CI (new infrastructure; set aside earlier).
- **This repository only**: the main checkout `~/.claude` and its worktrees. In every other repo
  the guard does nothing.

Mine, open to Mark's review (each marked "(my call)" where it appears below): the guard checks the
branch's last commit, not the index; it checks every registered hook, not only changed ones; one
shared checker serves the suite and the guard; the bypass variable is `HOOK_EXEC_EXEMPT`; scope
is decided before anything else runs, and only in scope does broken machinery fail closed, as
`judge-guard.sh` does; a payload with no command passes. Triage (`triaging-new-instructions`): a script
decides it from the command string and the commit, so it is a hook.

## Evidence — measured 2026-10-17 on `61d69dd` (re-measure in Task 0)

- `bash hooks/registered-hooks-executable.test.sh` → `27 passed, 0 failed`; real repo `entries read
  38 | checked scripts (distinct) 23 | skipped commands 11`. Every registered script is `100755`.
- No non-test hook reads a git file mode (`git grep` for `ls-files -s|ls-tree|100755|100644` under
  `hooks/`, tests and probes excluded, finds one unrelated `ls-tree --name-only`).
- Nine hooks are registered on `PreToolUse` `Bash`; `judge-guard.sh` and `merge-guard.sh` already
  read `gh` commands through `hooks/lib/classify-pr-command.py`. Its `classify(src, subcommand,
  exempt_var)` takes the exempt variable as an argument; `merge-guard.sh` imports it with
  `importlib` to pass its own (`hooks/merge-guard.sh:62-69`).
- From this worktree, `git rev-parse --path-format=absolute --git-common-dir` →
  `/Users/marksuyat/.claude/.git`, the main checkout's git dir.
- Versions: Python 3.9.6, git 2.50.1 (Apple Git-155), gh 2.96.0, bash 3.2.57 (`/bin/bash`, the
  only bash on `PATH`; version measured by the round-1 compliance judge). The guard and both suites
  run under it, so no bash-4 constructs (associative arrays, `mapfile`, `${var,,}`).

## Scope

In: a shared checker module, a new `PreToolUse` `Bash` hook and its suite, its registration, the
existing suite switched onto the shared checker, an ADR, a gate stub.

Out: other repositories; a SessionStart or `pre-commit` check; CI; changing any other hook.

## Design

```mermaid
flowchart TD
  A[Bash command] --> C{session repo's git common dir = ~/.claude/.git? bash + git only}
  C -- no / unknowable --> OK[allow, silent]
  C -- yes --> B{classifier: does it run gh pr create?}
  B -- python3 missing, payload unreadable, classifier unusable --> X[refuse: name the cause, fail closed]
  B -- no, or no command --> OK
  B -- yes --> D{non-empty HOOK_EXEC_EXEMPT on that segment?}
  D -- yes --> E[allow, print the reason]
  D -- no --> F[shared checker on HEAD]
  F -- PASS --> OK
  F -- FAIL --> R[refuse: every problem + the fix]
  F -- crashed / no result line --> X2[refuse: checker unusable]
```

### Units

| File | Role |
| --- | --- |
| `hooks/lib/registered_hook_modes.py` (new) | The checker, moved out of the suite's heredoc. |
| `hooks/registered-hooks-executable.test.sh` | `check_repo` calls the module; gains the `--rev` cases. |
| `hooks/hook-exec-pr-guard.sh` (new, `100755`) | The guard. |
| `hooks/hook-exec-pr-guard.test.sh` (new) | Its suite. |
| `settings.json` | One new `PreToolUse` `Bash` registration. |
| `docs/decisions/00NN-*.md` (new) | The ADR (number taken from `origin/main` in Task 5). |
| `rules/gates.md` | A stub line under the existing gates. |

## Requirements

R1. **Shared checker.** `python3 -I hooks/lib/registered_hook_modes.py <repo-root> [--rev <commit>]`
holds today's `check_repo` logic (registered-command parsing, skips, fail-closed rules, counts,
`result: PASS|FAIL…`, exit 0 clean / 1 problems). Without `--rev` it reads the index exactly as
today (`git show :settings.json`, `git ls-files -s -z`), and its output lines are byte-identical
to today's. With `--rev <c>` it reads both `settings.json` (`git show <c>:settings.json`) and the
modes (`git ls-tree -r -z <c>`) from that commit, never mixing in the index, and every line that
names its source says `commit <c>` where today's names the index (e.g. "missing from commit
HEAD", "settings.json is missing from commit HEAD"). A `<c>` that does not resolve to a commit is
a `FAIL` naming it. Any exit other than 0 or 1, or no final `result:` line, means the checker did
not run. Standard library only.

R2. **Suite on the shared checker.** `check_repo` becomes a one-line call to R1 without `--rev`.
Every existing fixture case stays, unchanged, and must pass. Added cases, each in its own repo:
(a) a script `100755` in the index but `100644` in HEAD fails with `--rev HEAD`, and the message
says `commit HEAD`; (b) the reverse passes with `--rev HEAD` and fails without it; (c)
`settings.json` in HEAD registers a `100644` script that the index's `settings.json` does not
register — fails with `--rev HEAD`, passes without it (catches a build that reads modes from HEAD
but settings from the index); (d) `--rev nosuchref` fails naming `nosuchref`.

R3. **Which commands.** After R4 says the repo is in scope, the guard reads the payload's
`tool_input.command` with `python3 -I` and classifies it with `classify(...,
subcommand=("pr","create"), exempt_var="HOOK_EXEC_EXEMPT")`, loaded by `importlib` from
`hooks/lib/classify-pr-command.py` under `python3 -I`, and accepted only when that call exits 0
**and** its first line is exactly `PR` or `NO` — `judge-guard.sh`'s two checks (status and shape),
not `merge-guard.sh`'s call, which skips `-I` and the status check. `NO` → exit 0, silent. A
payload whose `tool_input.command` is missing, not a string, or blank → exit 0, silent: there is
no command to classify, so it cannot be a PR creation (my call; `judge-guard.sh` refuses this
case, `merge-guard.sh:60` allows it). Accepted-open shapes are the classifier's own (ADR 0012).

R4. **Which repository — decided first.** Before any Python runs, the guard decides scope with
bash and git only: an empty stdin → exit 0; then the session's working directory must be inside a
git work tree whose `git rev-parse --path-format=absolute --git-common-dir`, resolved with
`cd -P … && pwd -P`, equals `$HOME/.claude/.git` resolved the same way. That covers the main
checkout and all its worktrees. Not in a repo, a different repo, `$HOME` unset, `git` missing, or
any of those commands failing → exit 0, silent (Mark's scope decision; `judge-guard.sh` still
applies to every PR). Because scope comes first, nothing this guard does can block a command in
any other repository.

R5. **What is checked (my call).** R1 with `--rev HEAD`, run against `git rev-parse
--show-toplevel`: HEAD is what `gh pr create` publishes, and the index can hold staged work that
is not in the PR. Every script the branch's own `settings.json` registers is checked, changed or
not, so an old mistake blocks the next PR until fixed.

R6. **Decision.** Allow (exit 0, silent) only when R1 exits 0 **and** its last line is exactly
`result: PASS`. R1 exiting 1 with a final `result: FAIL…` line → exit 2, stderr: one line per
`FAIL` from R1, then the fix for a mode problem — `chmod +x <path>`, `git add -- <path>`, commit —
then the bypass line. Every stderr line starts `hook-exec-pr-guard:`. Anything else from R1 is R8.

R7. **Bypass (my call).** `HOOK_EXEC_EXEMPT=<reason>` as a leading assignment on the segment that
runs `gh pr create` (the classifier reads only that segment) allows the PR and prints
`hook-exec-pr-guard: exempted (HOOK_EXEC_EXEMPT=<reason>)` to stderr. An empty value is no
bypass. The same assignment on another segment of a chained command is no bypass. `JUDGE_EXEMPT`
and `MERGE_EXEMPT` never satisfy it, and it never satisfies them.

R8. **Machinery failures, in scope only (my call).** Once R4 says the repo is in scope: no
`python3`, a payload that is not valid JSON, or a classifier that exits non-zero or prints
anything but `PR`/`NO` → exit 2 for every Bash command in this repo and its worktrees, naming the
cause and a repair route that survives the block (the Write tool, or unregistering the hook). For
a `gh pr create`, an R1 that did not run (R1's definition) → exit 2 naming the module. Outside
this repo none of these can fire (R4). In this repo, `judge-guard.sh` already blocks every Bash
command on a missing `python3`, an unreadable payload (`judge-guard.test.sh`: "truncated JSON ->
block") or an unusable classifier, so the only blocked state this guard adds is a broken R1, and
only for `gh pr create`.

R9. **Registration.** `settings.json` runs `$HOME/.claude/hooks/hook-exec-pr-guard.sh` as a bare
command under `PreToolUse` `Bash`, after `dependency-guard.sh`. The file is `100755` in git, so
the suite's real-repo count becomes 24 distinct scripts.

R10. **Records.** An ADR under `docs/decisions/` records the choice of the PR moment over the three
alternatives. `rules/gates.md` gains a two-line stub naming the hook, its bypass, and that it only
runs in this repo. The suite's header keeps "run by hand" for the suite and adds that the guard
now runs the same check at `gh pr create`.

## Scenarios

```gherkin
Feature: hook-exec-pr-guard

  Background:
    Given $HOME/.claude is a git repo with a worktree, and settings.json registers
      $HOME/.claude/hooks/a.sh on PreToolUse

  Scenario: a registered script stored non-runnable blocks the PR
    Given the worktree's HEAD stores hooks/a.sh as 100644
    When the session in that worktree runs "gh pr create --fill"
    Then the hook exits 2
    And stderr names hooks/a.sh, its events, mode 100644, the chmod/add/commit fix, and HOOK_EXEC_EXEMPT

  Scenario: a clean branch is allowed
    Given HEAD stores every registered script as 100755
    When "gh pr create" runs
    Then the hook exits 0 and prints nothing

  Scenario: an executable copy on disk does not hide the commit
    Given HEAD stores hooks/a.sh as 100644 and the file on disk is executable
    When "gh pr create" runs
    Then the hook exits 2

  Scenario: a staged fix that is not committed does not help
    Given HEAD stores hooks/a.sh as 100644 and the index stores 100755
    When "gh pr create" runs
    Then the hook exits 2

  Scenario: an unchanged old mistake still blocks
    Given hooks/a.sh was stored 100644 in an earlier commit and the branch never touches it
    When "gh pr create" runs
    Then the hook exits 2

  Scenario: a registered script missing from HEAD blocks
    Given settings.json at HEAD registers hooks/gone.sh and HEAD has no such file
    When "gh pr create" runs
    Then the hook exits 2 naming hooks/gone.sh as missing

  Scenario: another repository is untouched
    Given the session is in a different git repo whose HEAD stores a registered script as 100644
    When "gh pr create" runs
    Then the hook exits 0 and prints nothing

  Scenario: outside any repository, or with HOME unset
    When "gh pr create" runs
    Then the hook exits 0

  Scenario: the main checkout itself is in scope
    Given the session is in $HOME/.claude and HEAD stores hooks/a.sh as 100644
    When "gh pr create" runs
    Then the hook exits 2

  Scenario Outline: commands that are not a PR creation pass
    When "<cmd>" runs in scope with a 100644 registered script at HEAD
    Then the hook exits 0
    Examples:
      | cmd                                  |
      | gh pr view 5                         |
      | git commit -m "gh pr create later"   |
      | echo gh pr create                    |

  Scenario: a chained or wrapped PR creation is still read
    When "git push && gh pr create --fill" or "time gh -R o/r pr create" runs in scope with a bad HEAD
    Then the hook exits 2

  Scenario: the bypass allows and is printed
    When "HOOK_EXEC_EXEMPT=docs-only gh pr create" runs in scope with a bad HEAD
    Then the hook exits 0 and stderr carries the reason

  Scenario Outline: what is not a bypass
    When "<cmd>" runs in scope with a bad HEAD
    Then the hook exits 2
    Examples:
      | cmd                                                |
      | JUDGE_EXEMPT=x gh pr create                        |
      | HOOK_EXEC_EXEMPT= gh pr create                     |
      | HOOK_EXEC_EXEMPT=x true && gh pr create --fill     |

  Scenario: a payload with no command passes
    Given a valid PreToolUse payload whose tool_input has no "command", or a blank one
    When the hook runs in scope
    Then the hook exits 0

  Scenario Outline: broken machinery fails closed in scope
    Given <broken>
    When "ls" runs in scope
    Then the hook exits 2 naming <cause> and a repair route
    Examples:
      | broken                                  | cause                 |
      | the classifier file is empty            | the classifier path   |
      | python3 is not on PATH                  | the missing python3   |
      | the payload is truncated JSON           | the unreadable payload |

  Scenario: broken machinery never reaches another repository
    Given the classifier file is empty and python3 is not on PATH
    When "gh pr create" runs in a different git repo
    Then the hook exits 0 and prints nothing

  Scenario: a broken settings.json at HEAD fails closed
    Given settings.json at HEAD is not valid JSON
    When "gh pr create" runs in scope
    Then the hook exits 2 naming the JSON error

  Scenario Outline: an unusable checker fails closed
    Given <broken>
    When "gh pr create" runs in scope
    Then the hook exits 2 naming the module
    Examples:
      | broken                                                         |
      | the checker module is empty                                    |
      | the checker exits 0 but its last line is not "result: PASS"    |
```

Each guard-suite case builds its own fixture: a fake `$HOME` in `mktemp -d` holding `.claude` as a
git repo (plus a worktree where the scenario needs one), `GIT_CONFIG_GLOBAL=/dev/null`,
`GIT_CONFIG_NOSYSTEM=1`, and the hook run with that directory as its working directory. The
payload carries `hook_event_name: PreToolUse`, as `judge-guard.test.sh` builds it. The suite also
asserts the hook file is executable on disk, `100755` in git, and runs with no `bash` prefix (the
#110 assertions).

## Known gaps — disclosed, not fixed

| Gap | Why accepted |
| --- | --- |
| A PR opened outside a session (GitHub web, Mark's own terminal), or a push straight to main. | Mark chose the PR moment; CI was set aside. |
| `gh pr create --head <other-branch>` checks the session checkout's HEAD, not that branch. | Same as `judge-guard.sh`; PRs here are opened from the branch's own worktree. |
| A session rooted in one checkout that `cd`s to another before `gh pr create` checks the session's repo (hooks resolve git from the session cwd). | Same as `judge-guard.sh`; house practice is `EnterWorktree` with `path:`. |
| Command shapes the classifier does not read (backticks, heredoc bodies, a command built by expansion). | ADR 0012's accepted-open shapes. |
| A fresh clone of this repo that is not a worktree of `~/.claude` is out of scope. | Mark's scope decision. |
| If this guard's own file loses its bit it cannot run to say so (exit 126 does not block). | `verify-hook-wiring.sh` reports the disk bit at session start; R9 puts the file under the suite's check. |
| The guard is live only after merge and pull into the main checkout. | True of every hook here. |
| In this repo and its worktrees, a missing `python3`, an unreadable payload or a broken classifier blocks every Bash command, not just `gh pr create`. | `judge-guard.sh` already blocks every Bash command in those three states (R8), so no new blocked state; outside this repo R4 makes it impossible. |
| A `gh pr create` without `HOOK_EXEC_EXEMPT` is still blocked by `judge-guard.sh` until a verdict exists; the two refusals are independent. | Intended: each guard answers one question. |

## Tasks

- [ ] 0. Re-measure on the branch base: the Evidence list (suite counts by its own output, the
  common-dir answer from a worktree and from the main checkout, the four versions) and the next
  free ADR number on `origin/main` and on open PR branches. A different count is a finding.
- [ ] 1. Suite first (R2): add cases (a)–(d) and point `check_repo` at the not-yet-existing
  module. Run it and record which cases fail (every case that expects a `FAIL`/`ok` line should;
  a pure "must not contain" check may pass with the module missing — that is expected, not a
  defect). Commit red, with this card's Task 1 note staged.
- [ ] 2. Write `hooks/lib/registered_hook_modes.py` (R1) by moving the heredoc body, plus `--rev`.
  Suite green: every old case plus (a)–(d); real-repo counts unchanged (38/23/11).
- [ ] 3. Guard suite first: `hooks/hook-exec-pr-guard.test.sh` with every Scenario above and the
  three file-mode assertions. Run it red against a stub that always allows and one that always
  denies; record which cases each stub passes. Commit red.
- [ ] 4. Write `hooks/hook-exec-pr-guard.sh` (R3–R8), `chmod +x`, `git add --`. Guard suite green;
  exec-bit suite still green.
- [ ] 5. Register (R9); exec-bit suite shows 24 distinct scripts, all `100755`. Write the ADR and
  the gates stub, and update the suite header (R10).
- [ ] 6. Verification section; observability judge (implementation stage); open the PR, then
  commit the verdict.
- [ ] 7. After merge and Mark's pull: confirm the main checkout's hook blob and mode equal the
  merge commit's. Then, with Mark's OK, one live check in a throwaway local worktree whose HEAD
  stores a registered script as `100644`, through the Bash tool:
  `JUDGE_EXEMPT=live-check gh pr create --help`. `JUDGE_EXEMPT` takes `judge-guard.sh` out of the
  result, and `--help` does nothing if it does run (`--dry-run` was rejected: the round-1
  observability judge quotes gh's manual as saying it "may still push git changes"; not
  re-read here, because reading `gh pr create --help` is itself refused by `judge-guard.sh`). Pass = refused **and** the refusal text names
  `hook-exec-pr-guard`. Remove that worktree and its branch after.

## Gotchas

- Bash `grep` here is ugrep and honours `.gitignore`; use `git ls-files`/`git show` for anything
  the suites read.
- `git update-index --chmod=+x` alone is undone by `git commit -- <path>`; `chmod +x` then
  `git add -- <path>` (hook-exec-bit-test R7).
- `test-marker-guard.sh` will want `hooks/hook-exec-pr-guard.test.sh` run against the exact bytes
  of `hooks/hook-exec-pr-guard.sh` before a commit stages the guard.
- A worktree-isolated session refuses `git -C <main checkout>`; measure the main checkout's side
  of Task 0 and Task 7 by asking Mark or from a session rooted there.

Test-proof gaps from the round-2 observability read (architecting, risk low), left out of the
requirements because Mark gated without a spec revision; apply them while writing the tests:

- Task 3: the guard suite must set `GIT_CEILING_DIRECTORIES` (and `GIT_CONFIG_GLOBAL=/dev/null`,
  `GIT_CONFIG_NOSYSTEM=1`) as the exec-bit suite does, or a scratch dir under `$HOME` can resolve
  to this repo and the out-of-scope scenarios pass for the wrong reason.
- Task 3: the no-`python3` fixture must keep `git` on `PATH` — both live in `/usr/bin`, so
  dropping `/usr/bin` also makes R4 decide "out of scope" and the case never reaches R8.
- Task 1: case (a) checks `commit HEAD` wording on one message; also assert it on the other
  source-naming messages (the suite's index-naming lines, ~65, 69, 71, 168 at `61d69dd`).
- Task 7: run the live check from a session rooted in the throwaway worktree — hooks resolve git
  from the session cwd, so a `cd` from this session tests the wrong checkout. `man gh-pr-create`
  reads the manual without tripping `judge-guard.sh`, if the `--dry-run` quote needs checking.
- `judge-guard.sh:45` also accepts `python`, not only `python3`; decide whether R8's
  "no `python3`" message should say so. Per-Bash-call cost: one `git rev-parse` everywhere,
  plus Python starts inside this repo — note it in the ADR.
- Compliance notes: a payload that is valid JSON but not an object (e.g. `[]`) has no stated
  outcome — treat it as unparseable (R8); load both helper files from the hook's own directory,
  not `$HOME/.claude/hooks`.
