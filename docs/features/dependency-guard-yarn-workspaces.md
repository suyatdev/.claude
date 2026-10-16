---
phase: planning
model_tier: low
branch: none
---

# Dependency guard: yarn workspace forms, and who answered the two unexplained asks

Planned 2026-10-16 on `docs/guard-followups`, cut from `origin/main` @ `f83e490` (PR #111 merge).
Follow-ups (1) and (4) of `docs/features/dependency-vetting-guard.md` (the parent card, phase
`review`). Code is written by a Sonnet implementer; judges run on Opus. Nothing here is built
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

**Part B — two asks resolved with no recorded yes.** The parent card's Verification
(`dependency-vetting-guard.md:1367-1392`) records two `ask` decisions in `bypassPermissions` mode
that went through without a yes from Mark on record, and names two untested suspects: bypass mode
answering the ask itself, and `~/.orca/agent-hooks/claude-hook.sh` on `PermissionRequest`.
A read-only survey on 2026-10-16 found evidence against both (below) and two suspects the card does
not name. The cause is still unknown, so the parent card's wording ("cause unproven") stays true;
this card settles it by experiment.

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

Part B (read-only):
- The Orca hook posts the payload to the Orca app, discards the reply (`>/dev/null`), prints
  nothing and always exits 0, so it cannot return a decision. The session's own hook summary
  timed it at 17 ms.
- Both unexplained asks waited before running: 9 min 48 s and 30 s (npm itself took ~250 ms).
  cmux logged "Claude needs your permission" about 6 s after each ask, so a prompt was shown.
- Not yet considered by the parent card: cmux registers its own `PermissionRequest` hook ("cmux
  hooks feed"), and the session had a claude.ai remote-control link, which can answer a prompt
  from another device. Mark answering without noticing is also possible.

## Scope

In: Part A classifier change and its tests; the parent card's yarn Known-gaps row; Part B's
experiment and its recorded result.
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

## Requirements — Part B

R9. Run the experiment below with Mark present. In every run, Mark keeps his hands off the
keyboard, mouse and phone for the whole **watch window: 12 minutes** (longer than the longest
observed hold, 9 min 48 s). Record per run, before it starts: `claude --version` (2.1.301 when
planned), the cmux version (0.64.22 when planned), mode, terminal, the live hook list (the output
of `/hooks` in that session) and whether remote control is connected. Record when it ends: whether
a prompt appeared, how long the command waited, and which R10 outcome it was. Any Known-gaps row
this produces names those versions.

Experiment (no real install happens): a throwaway settings file passed with `--settings`, in a
`mktemp -d` directory, registering a PreToolUse hook that returns `ask` only for
`echo ASKTEST-<nonce>`. Every run is in bypass mode. Each run removes exactly one more suspect than
the one before, in this fixed order:

| Run | Setup | Suspect removed |
|---|---|---|
| 1 | cmux, remote control connected, user settings loaded (Orca hook present) — the original setup | none |
| 2 | as run 1, remote control disconnected | the claude.ai remote link |
| 3 | as run 2, in plain Terminal.app instead of cmux | cmux's own permission hook |
| 4 | as run 3, started with `--setting-sources` set to exclude `user` (flag present in 2.1.301's `--help`), so the Orca hook in `~/.claude/settings.json` does not load; `/hooks` must confirm it is absent | the Orca hook |

R10. Each run ends in exactly one outcome:

| Outcome in a run | Consequence |
|---|---|
| A. No prompt appears; the command runs at once | Bypass mode itself skips the ask. Stop. Known-gaps row in the parent card naming the mode and versions. |
| B. A prompt appears and is still pending when the window ends | Mark answers **no**. If this is run 1: stop — nothing automatic answers in the original setup, so later runs (which only remove suspects) cannot either; record "not reproduced; who answered on 2026-10-16 is still unknown". If this is run 2, 3 or 4: the suspect that run removed is the answerer — stop and add a Known-gaps row naming it and the versions. |
| C. A prompt appears and the command runs inside the window, hands off | Something automatic answered. Go to the next run. If this is run 4: every named suspect is removed and the ask is still answered automatically — record "answered automatically by an unidentified component; all four named suspects excluded", add a Known-gaps row saying exactly that with the versions and run 4's `/hooks` list, and stop. |

Never record "Mark answered" for any run: nothing here can prove it. When the experiment ends in
"not reproduced", there is no Known-gaps row and the parent card's "cause unproven" wording stays.
Passing `--settings` or `--setting-sources` may change which hooks load; that is why every run
records `/hooks`, and a run whose `/hooks` list does not match its row in the table above is
invalid and is repeated, not counted.

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
- [ ] 4. Part B experiment with Mark (R9), then record (R10).
- [ ] 5. Verification section; observability judge (implementation stage); PR.

## Gotchas

- Probe payloads need `"hook_event_name": "PreToolUse"`; without it the hook can allow without
  inspecting. Prove each probe harness with a deny control and an ask control first.
- Point any state or log variable the test suite uses at a scratch directory, never the real
  `hooks/state/`.
- The hook runs from the primary checkout; a merge is live only after `~/.claude` pulls it.
