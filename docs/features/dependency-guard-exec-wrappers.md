---
phase: planning
model_tier: high
branch: none
---

# Dependency guard: `yarn exec`, `pnpm exec` and nested yarn wrappers

Planned 2026-10-23 on `docs/dependency-guard-yarn-exec`, cut from `origin/main` @ `a1a7cc8`
(PR #116 merge). Follow-up of `docs/features/dependency-guard-yarn-workspaces.md`, whose
observability judge found both yarn holes. Mark asked for this card on 2026-10-23 and chose
(same day) to include `pnpm exec`, which the planning probe found has the same hole.
Model routing (Mark, 2026-10-23): plan on Opus max; implement with inline Sonnet-high workers;
judges on Opus high. Nothing here is built until Mark types `gate confirmed`.

## Why

`hooks/dependency-guard.sh` denies an unvetted `npm i x`, but three ways of saying the same thing
pass with no output at all:

1. **`yarn exec <command>` runs `<command>`.** So `yarn exec npm i x` installs `x` unvetted. The
   classifier reads `exec` as a yarn subcommand it does not know and returns nothing.
2. **`pnpm exec <command>` does the same** in pnpm.
3. **A yarn workspace wrapper inside another one is unwrapped once.** `_yarn_workspace_inner`
   (`hooks/lib/classify-install-command.py:354`) peels off one `workspace <name>` or
   `workspaces foreach [opts]`; if what is left starts with another wrapper, `_node_manager`
   (`:372`) sees `workspace`/`workspaces` as the subcommand and returns nothing.

The parent card's Known-gaps row (`docs/features/dependency-vetting-guard.md:1067-1072`) records
1 and 3. This is a speed bump, not a security boundary, as for the whole guard.

## Evidence — measured 2026-10-23 on `a1a7cc8` (re-measure in Task 0)

PreToolUse payloads (with `hook_event_name`) fed to this worktree's `hooks/dependency-guard.sh`,
state in a `mktemp -d` directory. Controls: `npm install left-pad` → deny (rc 2), `npm update` →
ask, `ls` → allow.

| Command | Today | Same command typed directly |
|---|---|---|
| `yarn exec npm i x` | allow, silent | deny |
| `yarn exec npm update` | allow, silent | ask |
| `yarn exec yarn add x` | allow, silent | deny |
| `yarn exec npx cowsay` | allow, silent | deny |
| `yarn exec 'npm i x'` | allow, silent | deny (yarn 4 runs the string, see R2) |
| `yarn workspace web exec npm i x`, `yarn workspaces foreach -A exec npm i x` | allow, silent | deny |
| `yarnpkg exec npm i x`, `corepack yarn exec npm i x` | allow, silent | deny |
| `yarn workspace web workspaces foreach -A add x` | allow, silent | deny |
| `yarn workspace a workspace b add x` | allow, silent | deny |
| `yarn workspaces foreach -A workspace b add x` | allow, silent | deny |
| `yarn workspace web workspaces foreach -A up` | allow, silent | ask |
| `pnpm exec npm i x` | allow, silent | deny |
| `yarn exec echo hi` | allow (correct) | allow |
| `yarn workspace web add x` | deny (already handled) | — |
| `npm exec -- npm i x` | deny (already handled, a runner) | — |
| `bun exec 'npm i x'` | allow, silent | out of scope (Known gaps) |

Probe script: a loop over one command per line, building the payload with `json.dumps`, reading
rc 2 as deny and `"ask"` on stdout as ask.

## What the tools actually do — read 2026-10-23 (re-read in Task 0)

Read from tarballs/source in a `mktemp -d` directory, never installed or run.

- **yarn 1.22.22** (`yarn@1.22.22`, `lib/cli.js:84251-84262`): `exec` takes the first argument as
  a program and the rest as its arguments, `spawn(execName, rest)` — no shell. No options of its own.
- **yarn 4.18.1** (`@yarnpkg/cli-dist@4.18.1`, `bin/yarn.js`, class with `paths=[["exec"]]`):
  `commandName = String`, `args = Proxy` — no options of its own. `execute()` calls
  `executePackageShellcode(locator, commandName, args)`, which runs `commandName` as **shell code**
  through yarn's portable shell (`pC`): it parses the string, and unless the script refers to its
  own positional arguments, appends `args` to the **last** command of the parsed script. Its own
  help gives `yarn exec "tsc & babel src --out-dir lib"` as an example. So `yarn exec npm i x` runs
  `npm i x`, and so does `yarn exec "npm i x"`.
- **pnpm 12.15.0** (a Rust binary; read from `pnpm/pnpm` @ `v12.15.0`,
  `pnpm/crates/cli/src/cli_args/exec.rs:29-39`): `command` is a trailing list (the first word is the
  program, hyphen words after it are its own), plus one option, `-c`/`--shell-mode` (boolean), which
  runs the command through `/bin/sh`. `RecursiveExecutionArgs`
  (`cli_args/recursive/execution_args.rs`) are all `#[clap(skip)]`, not command-line options of
  `exec`. Not yet read: how shell mode joins the words, and whether a global option (`--filter`,
  `-r`) is accepted *after* `exec` — Task 0.

## Scope

In: the classifier change, its tests, and the parent card's Known-gaps rows.
Out: `bun exec` (takes one quoted shell string — the `bash -c` gap, already in Known gaps);
`bash -c`/`sh -c`/`eval`; `yarn run <bin>`, `yarn <bin>` and `yarn node …` (run local programs,
never fetch); npm runners (`npm exec`, `npx`), which are already handled.

## Requirements

"Yarn programs" are `yarn`, `yarnpkg`, and `corepack yarn`; "pnpm programs" are `pnpm`, `pn`,
and `corepack pnpm` — as the classifier already recognises them.

R1. **`yarn exec` runs what follows.** For a yarn program, `exec <cmd> <args…>` gets the same
decision (allow / ask / deny) and the same reason text as the command line `<cmd> <args…>` typed
on its own. `yarn exec` takes no options, so `<cmd>` is the first word after `exec`, even if it
starts with `-`.

R2. **The command word is read as shell code.** `<cmd>` is lexed with the existing
`shell_segments.segments()`, and `<args…>` are appended to the argv of the **last** segment that
lexing produces; then every segment is classified as an ordinary command. This copies yarn 4
(see above). For a plain word like `npm` it gives exactly `npm <args…>`. For a string like
`'npm i x'` or `'cd web && npm i x'` it finds the install. In yarn 1 such a string would fail to
run, so reading it as an install only ever adds an ask/deny to a command that errors anyway.
- If `<cmd>` cannot be lexed (`segments(cmd) == []` with non-blank `cmd`): when it names an install
  tool (`mentions_install_tool`), return one indirect intent for the yarn program — the same ask the
  `xargs` rule gives; otherwise nothing.
- A script that refers to its own positional arguments (`$@`, `$1`) is not special-cased: the
  arguments are still appended. Disclosed in Known gaps; it can only add an ask/deny.

R3. **`pnpm exec` the same way.** For a pnpm program, `exec [options] <cmd> <args…>`:
- Options before `<cmd>`: `-c`/`--shell-mode` stand alone; a flag in `NODE_VALUE_FLAGS` takes the
  next word; any other word starting with `-` stands alone. The first word left is `<cmd>`.
  (Task 0 confirms or corrects this against pnpm 12.15.0's global options.)
- Without `-c`: as R1/R2 (lex `<cmd>`, append `<args…>`). pnpm spawns without a shell, so the
  lexing only matters for a quoted string, which would fail to run — same argument as R2.
- With `-c`: `<cmd> <args…>` joined with single spaces, lexed as one shell string, every segment
  classified (Task 0 confirms that pnpm joins them this way).
- `pnpm -r exec …`, `pnpm --filter web exec …`: global options before `exec` are already skipped by
  `_subcommand`; R3 applies to what follows.

R4. **Wrappers are unwrapped until none is left.** After a yarn `workspace <name>`,
`workspaces foreach [opts]` or `exec` is removed, if what remains starts with another one, it is
removed too, in any order and any number of times. Each step consumes at least one word, so this
ends. `yarn workspace a workspace b add x` → like `yarn add x`;
`yarn workspace web exec npm i x` → like `npm i x`.

R5. **Reason text.** Workspace wrappers keep the parent card's convention: the update-form words
in the log and the ask keep each wrapper in order, never the workspace name
(`workspace workspaces foreach up`). Once `exec` is reached, the inner command is a separate
command and its words are its own, with no yarn/pnpm wrapper words: `yarn exec npm update` logs
and asks exactly as `npm update` does. (Claude's call, 2026-10-23: the ask's job is to name what
will change, and that is the inner command.)

R6. **Unchanged.** An `exec` whose inner command installs nothing (`yarn exec tsc`,
`pnpm exec eslint .`, `yarn exec echo hi`) stays allowed silently; so does an `exec` with nothing
after it (`yarn exec`, `pnpm exec -c`), and every R6/R7 case of the yarn-workspaces card.

R7. **Pins and Known gaps.** Any existing ALLOW assertion that pins one of the Evidence-table
holes is replaced by its deny/ask assertion (Task 1 lists them; none is known today). In the
parent card, the `yarn exec`/nested-wrapper Known-gaps row is removed, `bun exec '<string>'` is
added to the `bash -c` row, and the `$@` over-read (R2) gets one line; one line under its
Verification points to this card.

R8. `hooks/lib/classify-install-command.py` (679 lines today) stays under the 800-line cap, and
the change is one small helper plus edits to `_node_manager`, not a new module.

## Scenarios

```gherkin
Scenario: yarn exec of an unvetted install is denied like the install itself
  Given x has no vetting report
  When Claude runs "yarn exec npm i x"
  Then the guard denies with the same reason as "npm i x"

Scenario: yarn exec of an update asks like the update
  When Claude runs "yarn exec npm update"
  Then the guard asks, with the same text as "npm update"

Scenario: the quoted shell-string form is read
  When Claude runs "yarn exec 'cd web && npm i x'"
  Then the guard denies like "npm i x"

Scenario: arguments are appended to the last command of the string
  When Claude runs "yarn exec 'cd web && npm' i x"
  Then the guard denies like "npm i x"

Scenario: an unreadable exec string that names an install tool asks
  When Claude runs a yarn exec whose command word has an unbalanced quote and contains "npm"
  Then the guard asks

Scenario: exec of a harmless command is still allowed
  When Claude runs "yarn exec tsc" or "pnpm exec eslint ."
  Then the guard allows it silently

Scenario: exec inside a workspace wrapper
  When Claude runs "yarn workspaces foreach -A exec npm i x"
  Then the guard denies like "npm i x"

Scenario: nested workspace wrappers
  When Claude runs "yarn workspace web workspaces foreach -A add x"
  Then the guard denies like "yarn add x"

Scenario: nested wrappers keep every wrapper word in an update ask
  When Claude runs "yarn workspace web workspaces foreach -A up"
  Then the guard asks, naming "yarn workspace workspaces foreach up"

Scenario: pnpm exec
  When Claude runs "pnpm exec npm i x" or "pn exec npm i x" or "pnpm -r exec npm i x"
  Then the guard denies like "npm i x"

Scenario: pnpm exec in shell mode
  When Claude runs "pnpm exec -c 'npm i x'" or "pnpm exec -c npm i x"
  Then the guard denies like "npm i x"

Scenario: other spellings are covered
  When Claude runs "yarnpkg exec npm i x" or "corepack yarn exec npm i x"
  Then the guard denies like "npm i x"

Scenario: an exec with nothing after it is allowed
  When Claude runs "yarn exec" or "pnpm exec -c"
  Then the guard allows it silently
```

## Tasks

- [ ] 0. Re-measure on the branch base: re-run every Evidence-table probe. Re-read the three
  sources above at the pinned versions and record file:line for each. Settle the two open pnpm
  questions (shell-mode joining; global options after `exec`) from `pnpm/pnpm` @ `v12.15.0` and
  correct R3 if they differ. A different result is a finding, not an error. Source is read only as
  a tarball or via `gh api` into a `mktemp -d` directory, never installed or run.
- [ ] 1. Tests first, in `hooks/dependency-guard.test.sh` (hook level) and the classifier's own
  suite: one assertion per Evidence-table row and per scenario, using the existing
  `deny_cmd`/`ask_cmd`/`allow_cmd` helpers, and replace any pin found under R7. Run: the new
  assertions fail, nothing else does. Commit the red suite on its own (`TEST_EXEMPT`, since a red
  suite writes no marker).
- [ ] 2. Classifier change (R1–R6, R8). Re-run both suites: green; the pre-existing assertion count
  is unchanged apart from replaced pins. Re-run the Evidence-table probes.
- [ ] 3. Parent card Known-gaps edits and the pointer line (R7).
- [ ] 4. Verification section; observability judge (implementation stage, Opus high); PR.

## Gotchas

- Probe payloads need `"hook_event_name": "PreToolUse"`; without it the hook can allow without
  inspecting. Prove each probe harness with deny and ask controls first.
- Point the suite's state dir (`DEPENDENCY_GUARD_STATE_DIR`) at a scratch directory, never the
  real `hooks/state/`.
- The hook runs from the primary checkout; a merge is live only after `~/.claude` pulls it.
- This session's worktree isolation refuses compound Bash (`$(( ))`, `&&` chains with variables):
  put probe loops in a script file.

## Verification

(empty until implementation)
