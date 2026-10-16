---
phase: planning
model_tier: low
branch: none
---

# Registered hooks must be executable in git, and the vetting skill's stale status lines

Planned 2026-10-16 on `docs/guard-followups`, cut from `origin/main` @ `f83e490` (PR #111 merge).
Follow-up (2) and (3) of `docs/features/dependency-vetting-guard.md`. Code is written by a Sonnet
implementer; judges run on Opus. Nothing here is built until Mark types `gate confirmed`.

## Why

A hook script that git stores as `100644` (not executable) cannot be started by Claude Code
(exit 126), and the hook it implements silently does nothing. This already happened once:
`hooks/dependency-guard.sh` merged as `100644` in PR #109, and the guard was inactive until PR #110
set `100755`. Nothing in the repo catches it in general:

- `hooks/verify-hook-wiring.sh` (SessionStart) checks the exec bit **on the filesystem**
  (`hooks/verify-hook-wiring.sh:151`). A local `chmod +x` makes it pass while git still stores
  `100644`, so a fresh clone or pull loses the bit with no warning. That is exactly how the second
  case below hid.
- `hooks/dependency-guard.test.sh` checks the git mode, but only for its own hook.

The second case is live today: `hooks/handoff/handoff-keep-guard.sh` (registered on `Stop`) has
been `100644` in git since it was added (`ecd3ba0`, 2026-09-10). It runs on this Mac only because
of an uncommitted local `chmod`.

Separately, `skills/vetting-dependencies/SKILL.md` still describes the pre-merge world:
line 10 says the hook "is not registered in `settings.json` until Task 9 … Until then nothing stops
an install", and line 51 says "`osv-scanner` is not installed on this machine until Task 8".
Both tasks are done and merged, so the skill now tells an agent something false.

## Evidence — measured 2026-10-16 on `origin/main` @ `f83e490` (re-measure in Task 0)

- `settings.json` registers 37 hook entries under 14 event keys. 10 are one inline Orca shell
  command with no repo script. The other 27 run a repo script by direct path (no `bash`/`python3`
  prefix) and resolve to 23 distinct scripts. 22 are `100755`; 1 is `100644`:
  `hooks/handoff/handoff-keep-guard.sh`. None is missing from the tree.
- `statusLine` runs its script through `bash …`, so its exec bit does not matter (it is `100755`).
- `git ls-tree origin/main hooks/handoff/handoff-keep-guard.sh` → `100644 blob aa653cab…`.
- There is no CI and no test runner; suites are run by hand.

Full table (machine-local, not committed): the read-only survey report from 2026-10-16.

## Scope

In: one new repo-wide test, the mode fix for `handoff-keep-guard.sh`, and the two stale lines in
`skills/vetting-dependencies/SKILL.md`.

Out (decide separately, do not bundle): teaching `verify-hook-wiring.sh` to read the git mode;
adding CI; any other hook's behaviour.

## Requirements

R1. A new suite `hooks/registered-hooks-executable.test.sh` reads `settings.json` **from the git
index** (`git show :settings.json`), not the working tree, and reads modes **from the index**
(`git ls-files -s`), not the filesystem.

R2. A registered command is *checked* when its first word is a path under `$HOME/.claude/` or
`~/.claude/` (after any leading `VAR=value` assignments). The path maps to the repo-relative path
after that prefix. Each checked path must exist in the index and have mode `100755`.

R3. A command whose first word is an interpreter (`bash`, `sh`, `zsh`, `python3`, `python`,
`node`) is *skipped*, since it does not need the bit. Any other command (e.g. the inline Orca
one-liner) is *skipped*. The suite prints every skipped command on its own line, so a check that
silently stops covering something is visible in the output.

R4. Fail closed: if parsing finds zero checked commands, the suite fails ("found no registered
hook scripts — the parser is broken, not the repo clean"). It also fails if `settings.json` is
not valid JSON.

R5. The suite covers every hook event key in `settings.json` `hooks` plus `statusLine`, without a
hard-coded list of event names.

R6. Fixture cases run against a throwaway git repo built in `mktemp -d` (never a fixed path), so
the suite proves it can both fail and pass: a `100644` registered script fails; the same script at
`100755` passes; an interpreter-invoked `100644` script passes; a registered path missing from the
index fails; a non-path command is skipped and listed. The fixture repo must not pre-create the
state under test (each case sets its own mode).

R7. `hooks/handoff/handoff-keep-guard.sh` is set to `100755` in git
(`git update-index --chmod=+x`), with no content change.

R8. `skills/vetting-dependencies/SKILL.md` line 10 states that `dependency-guard.sh` is registered
in `settings.json` and runs from the primary checkout once merged, without naming card task
numbers. Line 51 stops claiming `osv-scanner` is absent; instead it tells the agent to check with
`osv-scanner --version` and, if the command is missing, say so rather than imply a scan ran.
No other line of the skill changes.

## Scenarios

```gherkin
Scenario: a registered hook stored without the exec bit fails the suite
  Given settings.json registers "$HOME/.claude/hooks/x.sh" on Stop
  And the index stores hooks/x.sh as 100644
  When registered-hooks-executable.test.sh runs
  Then it fails and names hooks/x.sh, the event Stop and the mode 100644

Scenario: a local chmod does not hide the problem
  Given hooks/x.sh is 100644 in the index but -rwxr-xr-x on disk
  When the suite runs
  Then it still fails for hooks/x.sh

Scenario: an interpreter-invoked script does not need the bit
  Given statusLine is "bash $HOME/.claude/statusline-command.sh" and that file is 100644
  When the suite runs
  Then it does not fail for statusline-command.sh and lists the command as skipped (interpreter)

Scenario: a registered script missing from the index
  Given settings.json registers "$HOME/.claude/hooks/gone.sh"
  And the index has no hooks/gone.sh
  When the suite runs
  Then it fails and names hooks/gone.sh as missing

Scenario: the parser finds nothing
  Given settings.json has no command that starts with a $HOME/.claude/ path
  When the suite runs
  Then it fails with "found no registered hook scripts"

Scenario: the real repo after the fix
  Given handoff-keep-guard.sh is 100755 in the index
  When the suite runs against this repo
  Then it passes, and its checked count equals the distinct-script count from Task 0
```

## Tasks

- [ ] 0. Re-measure on the branch base: the 37/14/27/23/1 counts above, by listing rows (not
  `grep -c`). Record the numbers and the base SHA here. A different count is a finding, not an
  error.
- [ ] 1. Write `hooks/registered-hooks-executable.test.sh` (R1–R6). Run it against this repo
  before Task 2: it must fail, naming exactly `hooks/handoff/handoff-keep-guard.sh`. Commit the
  failing suite on its own.
- [ ] 2. `git update-index --chmod=+x hooks/handoff/handoff-keep-guard.sh` (R7). Re-run: green.
  Confirm `git diff --cached --stat` shows a mode change and no content change.
- [ ] 3. Edit the two lines in `skills/vetting-dependencies/SKILL.md` (R8). Diff must touch
  exactly lines 10 and 51.
- [ ] 4. Verification section; observability judge (implementation stage); PR.

## Gotchas

- After merge, Mark's primary `~/.claude` already has the bit set locally but uncommitted. A plain
  `git pull` may refuse to overwrite that local change; `git pull --ff-only --autostash` is the
  form used before. Check `git status` there after the pull rather than assuming.
- A hook change is live only once the primary checkout has pulled it; compare the primary's mode
  with `git ls-files -s` there after the pull.
- Bash `grep` on this machine is ugrep and honours `.gitignore`; use `git ls-files`/`git show`
  for anything the suite reads.
