---
phase: review
model_tier: low
branch: fix/dependency-guard-yarn-workspaces
---

# Dependency guard: yarn workspace forms get the same decision as plain yarn

Planned 2026-10-16 on `docs/guard-followups`, cut from `origin/main` @ `f83e490` (PR #111 merge).
Follow-up (4) of `docs/features/dependency-vetting-guard.md` (the parent card, phase `review`).
Its former Part B (who answered two unexplained asks) moved to
`docs/features/permission-ask-answerer.md` on 2026-10-16, at Mark's direction, so this fix is not
held up by an experiment that needs him at the keyboard. Code is written by a Sonnet implementer; judges run on Opus. Nothing here is built
until Mark types `gate confirmed`.

## Why

**Part A — yarn workspace forms slip past the guard.** `hooks/dependency-guard.sh` denies an
unvetted `yarn add x` and asks before `yarn up`, but the same commands wrapped in yarn's workspace
forms pass with no output at all. The worst is `yarn workspace <name> dlx <pkg>`, which downloads
and runs a package in one step, while plain `yarn dlx <pkg>` is denied. The parent card's
Known-gaps row (`docs/features/dependency-vetting-guard.md:1067`) names only `add|up`.

Cause: `_node_manager` (`hooks/lib/classify-install-command.py:352`) reads `workspace` or
`workspaces` as the subcommand and returns no intent. Only `global` is unwrapped
(`classify-install-command.py:356`).

## Evidence — measured 2026-10-16 (re-measure in Task 0)

Part A, by feeding PreToolUse payloads to the live hook (controls first: `npm install left-pad`
denied, `npm update` asked):

| Command | Today | Same command at top level |
|---|---|---|
| `yarn workspace web add lodash` | allow, silent | `yarn add lodash` → deny |
| `yarn workspace web up` / `upgrade` (± package) | allow, silent | `yarn up` / `yarn upgrade` → ask |
| `yarn workspace web upgrade-interactive` | allow, silent | `yarn upgrade-interactive` → ask |
| `yarn workspace web install lodash` | allow, silent | `yarn install lodash` → deny |
| `yarn workspace web dlx x` | allow, silent | `yarn dlx x` → deny |
| `yarn workspace web global add lodash` | allow, silent | `yarn global add lodash` → deny |
| `yarn workspaces foreach [-A\|--all\|-pt] add\|up\|upgrade\|dlx …` | allow, silent | deny / ask as above |
| `yarn workspaces run add lodash`, `… run upgrade` (yarn 1) | allow, silent (correct: runs a script, R4) | `yarn run add` → allow |
| `yarnpkg …`, `corepack yarn …`, `VAR=1 yarn …`, `cd x && yarn …` spellings of the above | allow, silent | — |
| `yarn workspace web remove lodash`, `… run build`, `workspaces foreach run build`, `workspaces info` | allow (correct) | — |
| `yarn --cwd web add lodash` | deny (already handled) | — |

pnpm, npm and bun workspace forms are already denied or asked. Three ALLOW pins hold the gap in
place: `hooks/dependency-guard.test.sh:400-403`.

## Scope

In: Part A classifier change and its tests; the parent card's yarn Known-gaps row.
Out: any other Known-gaps row; changing how Claude Code, cmux or Orca handle prompts.

## Requirements — Part A

R1. **Same decision as top level.** For yarn programs (`yarn`, `yarnpkg`, and `corepack yarn`,
as the classifier already recognises them), a command of the form
`yarn workspace <name> <rest…>` gets the same decision (allow / ask / deny) and the same reason
text as `yarn <rest…>` would, with the one difference in R5.

R2. `yarn workspaces foreach [options] <rest…>` likewise gets the decision of `yarn <rest…>`.
Options before `<rest>`: the flags that take a value — `--from`, `--include`, `--exclude`,
`-j`/`--jobs` — consume the next word; every other word starting with `-` is a flag on its own
(this covers `-A`, `--all`, `-R`, `-W`, `-v`, `-p`, `-i`, `-t`, combined short flags like `-pt`,
and `--since`). The first word left is the start of `<rest>`.
**Version pin:** this option list is written from memory of yarn 4 and is checked in Task 0 against
the `workspaces foreach` command definition shipped in `@yarnpkg/cli-dist@4.18.1` (current on npm,
2026-10-16). If the shipped list differs, Task 0 corrects this paragraph before Task 1 starts.
A value-taking option missing from the list would make its value look like the subcommand; that
misreads toward a false ask/deny only when the value happens to be a subcommand word, and toward a
silent allow otherwise — which is why the list must come from the pinned source, not memory.

R3. **`--since`.** In yarn 4.18.1, `--since` takes a value only joined to it (`--since=main`), never
the next word (read from `@yarnpkg/cli-dist@4.18.1` by the round-2 design judge, 2026-10-16;
Task 0 re-reads it). So `--since` and `--since=<ref>` are each one standalone flag (R2), and the
word after a bare `--since` is the start of `<rest>`: `foreach --since main up` runs a script
named `main` and is allowed, while `foreach --since=main up` asks like `yarn up`.

R4. `yarn workspaces run <x…>` (yarn 1) is **not** a wrapper: yarn 1.22.22 runs it as
`yarn run <x…>` in each workspace (`lib/cli.js:88569` in the `yarn@1.22.22` tarball, read
2026-10-16), which runs a package script, never an install. It keeps the decision of
`yarn run <x…>`, which is allow. (By contrast `yarn workspace <name> <rest…>` runs `yarn <rest…>`,
`lib/cli.js:88349`, which is why R1 holds.)

R5. The update-form words recorded in the log and shown in the ask keep the wrapper, following the
`global` precedent (`words = ["global", sub]`): `workspace up`, `workspaces foreach up`.
The workspace *name* is never part of the form.

R6. Unchanged: anything that is not an install, update or runner form inside the wrapper
(`remove`, `run build`, `info`, a bare `yarn workspace web`) stays allowed silently.

R7. A wrapper with nothing after it (`yarn workspace web`, `yarn workspaces foreach -A`) is allowed
silently, as today.

R8. The three ALLOW pins at `hooks/dependency-guard.test.sh:400-403` are replaced by deny/ask
assertions, and the parent card's Known-gaps row for yarn workspaces is removed, with a one-line
note under the parent card's Verification pointing to this card.

## Scenarios — Part A

```gherkin
Scenario: an unvetted add inside a workspace is denied like a plain add
  Given lodash has no vetting report
  When Claude runs "yarn workspace web add lodash"
  Then the guard denies with the same reason as "yarn add lodash"

Scenario: dlx inside a workspace is denied like plain dlx
  When Claude runs "yarn workspace web dlx x"
  Then the guard denies with the same reason as "yarn dlx x"

Scenario: an update inside foreach asks, naming the wrapper
  When Claude runs "yarn workspaces foreach -A up"
  Then the guard asks, and the ask names "yarn workspaces foreach up everything"

Scenario: a value-taking foreach option is skipped
  When Claude runs "yarn workspaces foreach --include web add lodash"
  Then the guard denies like "yarn add lodash"

Scenario: a bare --since is a flag on its own
  When Claude runs "yarn workspaces foreach --since add lodash"
  Then the guard denies like "yarn add lodash"

Scenario: --since=ref is one word
  When Claude runs "yarn workspaces foreach --since=main up"
  Then the guard asks like "yarn up"

Scenario: the word after a bare --since is the command, even if it looks like a ref
  When Claude runs "yarn workspaces foreach --since main up"
  Then the guard allows it silently, like "yarn main up" (yarn runs a script named main)

Scenario: yarn 1's workspaces run is a script run, not a wrapper
  When Claude runs "yarn workspaces run add lodash"
  Then the guard allows it silently, like "yarn run add lodash"

Scenario: a script run inside a workspace is still allowed
  When Claude runs "yarn workspace web run build"
  Then the guard allows it silently

Scenario: a wrapper with nothing after it is allowed
  When Claude runs "yarn workspace web" or "yarn workspaces foreach -A"
  Then the guard allows it silently

Scenario: other spellings are covered
  When Claude runs "corepack yarn workspace web add lodash" or "yarnpkg workspace web add lodash"
  Then the guard denies like "yarn add lodash"
```

## Tasks

- [ ] 0. Re-measure on the branch base: re-run every probe in the Evidence table, both columns.
  Read the `workspaces foreach` option definitions in `@yarnpkg/cli-dist@4.18.1` and correct R2's
  list and R3 if they differ. Re-read `yarn@1.22.22`'s `lib/cli.js:88349` and `:88569` to confirm
  R1 and R4. Record each answer with the file and version read. A different result is a finding, not an
  error. Reading package source is offline-safe only if fetched as a tarball into a `mktemp -d`
  directory and never installed or executed.
- [ ] 1. Tests first: replace the three pins (R8) and add one assertion per Evidence-table row and
  per scenario, using the suite's `deny_cmd`/`ask_cmd`/`allow_cmd`. Run: the new assertions must
  fail and nothing else may. Commit the red suite on its own.
- [ ] 2. Classifier change in `_node_manager` (R1–R7), as one small helper in the same file
  (`hooks/lib/classify-install-command.py`, 656 lines today; it must stay under the 800-line cap). Re-run the full dependency-guard suite and
  the classifier's own suite: green, and the pre-existing assertion count unchanged apart from the
  three replaced pins.
- [ ] 3. Parent card: remove the yarn Known-gaps row, add the pointer line (R8).
- [ ] 4. Verification section; observability judge (implementation stage); PR.

## Gotchas

- Probe payloads need `"hook_event_name": "PreToolUse"`; without it the hook can allow without
  inspecting. Prove each probe harness with a deny control and an ask control first.
- Point any state or log variable the test suite uses at a scratch directory, never the real
  `hooks/state/`.
- The hook runs from the primary checkout; a merge is live only after `~/.claude` pulls it.

## Verification

All probes below fed PreToolUse payloads (with `hook_event_name`) to this worktree's
`hooks/dependency-guard.sh`, state pointed at a `mktemp -d` directory. Harness controls on the
base: `npm install left-pad` → deny (rc 2), `npm update` → ask, `ls` → allow.

**Task 0 — re-measure on the base `4442e53` (2026-10-22).** No commit. Every Evidence-table row
reproduced as recorded (56 commands, re-run twice: by the worker and independently by the main
session). Source read as tarballs in a `mktemp -d`, never installed or run:
- `@yarnpkg/cli-dist@4.18.1`, `package/bin/yarn.js` line 768 (`workspaces foreach` class): the
  options taking the next word are exactly `--from`, `--include`, `--exclude`, `-j/--jobs`; `--since`
  is a `String` with `tolerateBoolean`, built at line 132 with arity 0, so it never takes the next
  word; line 96's batch handling makes combined short flags (`-pt`) standalone. R2 and R3 hold.
- `yarn@1.22.22`, `lib/cli.js:88349` (`workspace` runs `yarn <rest>` in the workspace dir) and
  `:88569` (`workspaces run` runs `yarn run <args>`); `:88629-88640` register only `info` and `run`
  under `workspaces`. R1 and R4 hold.

**Task 1 — red suite `c085ab8`.** `hooks/dependency-guard.test.sh`: before `313 passed, 0 failed`;
after `342 passed, 91 failed`. The only pre-existing assertions gone are the three replaced pins;
none of the 91 failures is pre-existing. Committed with `TEST_EXEMPT`, since a red suite never
writes a marker.

**Task 2 — fix `2c1e1c8`.** `_yarn_workspace_inner` and `FOREACH_VALUE_FLAGS` in
`hooks/lib/classify-install-command.py` (now 679 lines). `dependency-guard: 433 passed, 0 failed`;
`classify-install-command unit: 1137 passed, 0 failed` (both re-run by the main session).
The same 56 commands after the fix: 25 deny, 17 ask, 14 allow. Every `yarn workspace <name> …` and
`yarn workspaces foreach … ` install, update, dlx and `global add` form matches its plain-yarn
decision; the allows are `workspaces run …`, `run …`, `remove`, `run build`, `workspaces info`, the
two bare wrappers, `foreach --since main up` and `yarn main up` (R3, R4, R6, R7).

**Task 3 — parent card `55dd2d3`.** The yarn workspace Known-gaps row was removed from
`docs/features/dependency-vetting-guard.md` (Mark approved the cut, 2026-10-22) and a pointer to
this card was added under its Verification.

Not verified here: the live hook in `~/.claude` — it changes only after the merge is pulled.

**After merge (2026-10-22).** PR #116 merged as `a1a7cc8`; `git merge-base --is-ancestor 378afa8
origin/main` → 0. The primary checkout was pulled (`--no-rebase`, Mark's approval) and the live
`~/.claude/hooks/dependency-guard.sh` probed: `yarn workspace web add lodash` → deny,
`yarn workspace web dlx x` → deny, `yarn workspace web up` → ask ("yarn workspace up everything"),
`yarn workspaces run add lodash` → allow; control `yarn add lodash` → deny.
