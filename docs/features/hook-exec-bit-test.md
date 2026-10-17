---
phase: implementation
model_tier: low
branch: feat/hook-exec-bit-test  # to be cut from docs/guard-followups (7a1e8b3) in a new worktree after the /clear
---

Gate opened 2026-10-16 on the literal user phrase `gate confirmed`; Mark then chose "Quick fixes
only" — this card's gate only. The yarn card's gate is NOT open. Mark asked to clear the session
before any implementation; branch and task 0 start in the next session.

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
  (`hooks/verify-hook-wiring.sh:149`). A local `chmod +x` makes it pass while git still stores
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
(`git ls-files -s`), not the filesystem. JSON parsing and word splitting use the system `python3`
run as `python3 -I`; no new dependency. Versions when planned (2026-10-16): Python 3.9.6, git
2.50.1 (Apple Git-155); Task 0 re-records them.

R1a. **Which repo is checked.** The check is one function, `check_repo <repo-root>`, that runs
every git command as `git -C <repo-root> …`. The suite calls it once for each fixture repo (R6),
then once for the real repo: the root of the repository that contains the suite file itself
(`git -C "$(dirname "$0")" rev-parse --show-toplevel`), never the caller's current directory.

R2. **Which commands are checked.** Each registered command is split into words shell-style
(`shlex.split`, POSIX mode). Leading `NAME=value` words are dropped. The command is *checked* when
the next word starts with `$HOME/.claude/`, `${HOME}/.claude/` or `~/.claude/`; the repo-relative
path is what follows that prefix. Paths are de-duplicated: a script registered on several events
is checked once and its failure message names every event it is registered on. Each checked path
must exist in the index and have mode `100755`.

R3. A command whose first word (after assignments) is an interpreter (`bash`, `sh`, `zsh`,
`python3`, `python`, `node`) **and** that passes the script as a file argument is *skipped*, since
it does not need the bit. An interpreter given `-c` (e.g. `bash -c "…"`) is not an interpreter
skip: it is an *other* command, so R4's `.claude/` rule applies to it. Any other command (e.g. the
inline Orca one-liner) is *skipped*. A hook entry with no `command` field (a non-command hook type)
is *skipped* with reason "no command", never a crash. The suite prints every skipped entry with
its reason on its own line, so a check that silently stops covering something is visible.

R4. **Fail closed.** The suite fails, with a message naming the cause, when: `settings.json` is
missing from the index; it is not valid JSON; a command cannot be split (unbalanced quotes);
parsing finds zero checked scripts ("found no registered hook scripts — the parser is broken, not
the repo clean"); a *skipped* non-interpreter command contains `.claude/` anywhere — a likely
repo path in a shape R2 does not read, which must be taught to the parser or explained, never
silently skipped; the target is not a git repository; or `mktemp -d` fails. Fixture directories
are removed on exit (`trap`). Known limit, accepted: a parser regression that loses some but not
all scripts (say 23 → 20) still passes; the printed counts and Task 4's hand check are the only
guard against it.

R5. The suite covers every hook event key in `settings.json` `hooks` plus `statusLine`, without a
hard-coded list of event names. It prints the number of entries read, of checked scripts
(distinct), and of skipped commands.

R6. Fixture cases run against throwaway git repos built in `mktemp -d` (never a fixed path), so
the suite proves it can both fail and pass. Each case builds its own repo and sets its own modes
(no case may inherit state from another). Cases: a `100644` registered script fails; the same
script at `100755` passes; `100644` in the index but executable on disk fails; an
interpreter-invoked `100644` script passes; a registered path missing from the index fails; a
non-path command registered beside one valid `100755` script passes and is listed as skipped; a
`bash -c "$HOME/.claude/x.sh"` command fails under R4; an entry with no `command` field is listed
as skipped; a `VAR=1 $HOME/.claude/x.sh` command is checked; the
`~/.claude/` and `${HOME}/.claude/` forms are checked; one script on two events is checked once and
both events are named; invalid JSON fails; missing `settings.json` fails; zero checked scripts
fails; a skipped command containing `.claude/` fails.

R7. `hooks/handoff/handoff-keep-guard.sh` is stored as `100755` in git, with no content change.
How (Task 2): `chmod +x` on disk first, then `git add -- <path>`. `git update-index --chmod=+x`
alone is **not** enough: it changes only the index, and the house habit `git commit -- <path>`
re-stages the file from disk, putting `100644` back (reproduced by the design judge in a scratch
repo, 2026-10-16).

R7a. The suite is run by hand, like every other suite here: there is no CI, and nothing runs it
when a hook is added. The PR and the card say so; adding a runner is out of scope.

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

Scenario: an assignment prefix and the other path spellings are still checked
  Given settings.json registers "VAR=1 $HOME/.claude/hooks/a.sh", "~/.claude/hooks/b.sh"
    and "${HOME}/.claude/hooks/c.sh", each 100644 in the index
  When the suite runs
  Then it fails and names a.sh, b.sh and c.sh

Scenario: one script on two events
  Given "$HOME/.claude/hooks/x.sh" is registered on PreToolUse and on Stop, 100644 in the index
  When the suite runs
  Then it reports hooks/x.sh once, naming both PreToolUse and Stop

Scenario: broken or missing settings
  Given settings.json in the index is not valid JSON, or is absent from the index
  When the suite runs
  Then it fails and says which

Scenario: a path the parser cannot read is not skipped silently
  Given settings.json registers "exec \"$HOME/.claude/hooks/x.sh\""
  When the suite runs
  Then it fails, naming the command as an unread .claude/ path

Scenario: the real repo after the fix
  Given handoff-keep-guard.sh is 100755 in the index
  When the suite runs against this repo
  Then it passes and prints its counts
  And (checked by hand in Task 4, not asserted by the suite) the distinct checked count equals
    Task 0's distinct-script count
```

## Tasks

- [x] 0. Re-measure on the branch base: the 37/14/27/23/1 counts above, by listing rows (not
  `grep -c`), and the `python3 --version` used. Record the numbers and the base SHA here. A
  different count is a finding, not an error.
  - Measured 2026-10-17 on branch base `e93790c` (settings.json read via `git show e93790c:settings.json`,
    rows listed by walking `hooks.<event>[].hooks[]`, modes from `git ls-tree -r e93790c`):
    37 hook entries, 14 event keys, 10 inline-command entries (the Orca `if [ -f ... ]` one-liner, none
    containing `.claude/`), 27 repo-script entries by direct path, 23 distinct scripts, 22 at `100755`
    and 1 at `100644` (`hooks/handoff/handoff-keep-guard.sh`, registered on `Stop`). All match the card.
    `statusLine` is `bash "$HOME/.claude/statusline-command.sh"` (interpreter + file, to be skipped).
  - Tool versions: Python 3.9.6, git 2.50.1 (Apple Git-155).
- [ ] 1. Write `hooks/registered-hooks-executable.test.sh` (R1–R7a). Run it against this repo
  before Task 2: it must fail, naming exactly `hooks/handoff/handoff-keep-guard.sh`, and every
  fixture case must behave as R6 says. Commit the failing suite on its own, staging this card's
  Task 1 note in the same commit so `doc-guard` sees documentation staged.
- [ ] 2. Fix the mode (R7): run `hooks/handoff/handoff-keep-guard.test.sh` in this worktree first
  (the repo's test-marker gate will likely refuse a commit staging that file otherwise — not yet
  tried), then `chmod +x hooks/handoff/handoff-keep-guard.sh`, `git add -- <path>`, commit.
  **After** the commit: `git ls-tree HEAD hooks/handoff/handoff-keep-guard.sh` shows `100755`,
  `git show --stat HEAD` shows a mode change and no content change, and the new suite is green.
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
