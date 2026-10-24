---
phase: implementation
model_tier: low
branch: fix/dependency-guard-exec-wrappers
---

# Dependency guard: `yarn exec`, `pnpm exec` and nested yarn wrappers

Planned 2026-10-23 on `docs/dependency-guard-yarn-exec`, cut from `origin/main` @ `a1a7cc8`
(PR #116 merge). Follow-up of `docs/features/dependency-guard-yarn-workspaces.md`, whose
observability judge found both yarn holes. Mark asked for this card on 2026-10-23 and chose
(same day) to include `pnpm exec`, which the planning probe found has the same hole.
Model routing (Mark, 2026-10-23): plan on Opus max; implement with inline Sonnet-high workers;
judges on Opus high. Nothing here is built until Mark types `gate confirmed`.
Stop rule (Mark, 2026-10-24): round 4 is the last judge round. A further finding of the same
kind (how an option's width is read) is recorded as a Known gap, and the card goes to Mark's
review instead of a fifth round.
Round 4 outcome (Mark, 2026-10-24): fix all five round-4 points in place rather than log them,
with no fifth round. They were: the R3 wording that pointed at the wrong R9 rule, a reading cap
of 64 (R3), bun kept out of R9, two misplaced Task 1 rows, and an npm over-read pin. This revision
was not re-judged.

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

Added 2026-10-24 (round-2 compliance finding, Mark chose to fold the pre-existing pnpm bugs in), same
harness:

| Command | Today | What pnpm runs |
|---|---|---|
| `pnpm --shell-mode exec npm i x` | allow, silent | `npm i x` in `/bin/sh` |
| `pnpm -c exec npm i "'x"`, `pnpm exec -c npm i "'x"` | allow, silent | the string `npm i 'x` in `/bin/sh` |
| `pnpm -w add x`, `pn -w add x`, `pnpm -w exec npm i x` | allow, silent | an add of `x` at the workspace root |
| `pnpm add -w x`, `pnpm add -w x@1.0.0`, `pnpm i -w x` | allow, silent | the same |
| `pnpm add --workspace x`, `pnpm --workspace add x` | allow, silent | an add of `x` |
| `pnpm add --config x`, `pnpm add --config x@1.0.0` | allow, silent | an add of `x` |
| `pnpm m add x`, `pnpm multi add x`, `pnpm recursive add x`, `pnpm m exec npm i x` | allow, silent | `pnpm --recursive add x` |
| `pnpm --workspace-root add x`, `pnpm --filter web add x`, `pnpm -r add x` | deny (correct) | — |
| `pnpm m`, `pnpm recursive` | allow (correct) | nothing is installed |
| `npm -w web install x` | deny (correct: npm's `-w` takes a value) | — |
| `yarn -w add x` | allow, silent | not examined; R9's before-the-subcommand rule denies it either way |

Added 2026-10-24 (round-3 findings), measured on 824ab6c with the same harness:

| Command | Today | Why |
|---|---|---|
| `pnpm --reporter silent add x`, `pnpm --store-dir /s add x`, `pnpm --state-dir /s add x` | allow, silent | a value option missing from `NODE_VALUE_FLAGS`; its value is read as the subcommand |
| `yarn --mutex file:/tmp/m add x` | allow, silent | the same, for yarn |
| `pnpm --reporter=silent add x`, `pnpm add --store-dir /s x` | deny (correct) | `=` form; an unknown option among the subcommand's words over-reads its value |
| `pnpm dlx -w cowsay`, `pnpm dlx -c cowsay` | allow, silent | the runner scan reads `-w` and `-c` as taking a value |
| `pnpm dlx cowsay` | deny (correct) | — |
| `pnpm -w web add x`, `pn -w web add x`, `pnpm --workspace web add x`, `pnpm --config foo add x`, `pnpm add -w --filter x` | deny | must **stay** denied (R9 keeps today's reading) |
| `pnpm -w web update`, `pnpm -w foo audit --fix`, `pnpm -r up` | ask | must stay asked |
| `pnpm m up` | allow, silent | R10: asks like `pnpm -r up` |
| `pnpm -r run add x`, `pnpm --filter add test` | allow (correct) | R9's accepted over-read makes these ask/deny (Known gaps) |
| `yarn add -w x` | allow, silent | not examined; stays allowed (Known gaps) |

Note: `pnpm -c exec cd web '&&' npm i x` is already denied today, but only because the shared lexer
splits at a quoted `&&` (`segments()` gives `[pnpm -c exec cd web]`, `[npm i x]`) — an accident,
not a reading of shell mode. The `"'x"` rows above are the ones where shell mode changes the
result.

Probe script: a loop over one command per line, building the payload with `json.dumps`, reading
rc 2 as deny and `"ask"` on stdout as ask.

## What the tools actually do — read 2026-10-23 (re-read in Task 0)

Read from tarballs/source in a `mktemp -d` directory, never installed or run. Everything below is
settled for this card; Task 0 only re-checks it (see Task 0 for what a difference means).

- **yarn 1.22.22** (`yarn@1.22.22`, `lib/cli.js:84251-84262`): `exec` takes the first argument as
  a program and the rest as its arguments, `spawn(execName, rest)` — no shell. No options of its own.
  **`--`:** yarn splits its whole argv at the first `--` (`lib/cli.js:89283-89288`) and re-appends
  what follows *without* the `--` (`:88866`, `endArgs.slice(1)`), so `yarn exec -- npm i x` runs
  `npm i x`.
- **yarn 4.18.1** (`@yarnpkg/cli-dist@4.18.1`, `bin/yarn.js`, class with `paths=[["exec"]]`):
  `commandName = String`, `args = Proxy` — no options of its own. `execute()` calls
  `executePackageShellcode(locator, commandName, args)`, which runs `commandName` as **shell code**
  through yarn's portable shell (`pC`): it parses the string, and unless the script refers to its
  own positional arguments, appends `args` to the **last** command of the parsed script. Its own
  help gives `yarn exec "tsc & babel src --out-dir lib"` as an example. So `yarn exec npm i x` runs
  `npm i x`, and so does `yarn exec "npm i x"`. **`--`:** clipanion's `registerOptions` maps a `--`
  token to `inhibateOptions` (consumed, not kept as a positional) on the nodes before
  `commandName`, so `yarn exec -- npm i x` also runs `npm i x`. (Read in minified source, not run.)
- **pnpm 12.15.0** (a Rust binary; read from `pnpm/pnpm` @ `v12.15.0`):
  - `pnpm/crates/cli/src/cli_args/exec.rs:29-39`: `command` is a trailing list
    (`trailing_var_arg`, `allow_hyphen_values`: the first word is the program, hyphen words after
    it are its own), plus `-c`/`--shell-mode` (boolean). `RecursiveExecutionArgs` are all
    `#[clap(skip)]`.
  - `exec.rs:135-147`: a leading `--` left in `command` is removed.
  - `exec.rs:209-221`: shell mode runs `command.join(" ")` — the words joined with single spaces,
    no escaping — through `/bin/sh`.
  - `cli_args/cli_command.rs:109-300`: 28 lines there declare an option `global = true` (38 in the
    file), so clap accepts them after `exec` too, before the command word. Several take a value
    (`-C`/`--dir`, `-F`/`--filter`, `--filter-prod`, `--store-dir`, `--state-dir`, `--registry`,
    `--reporter`, `--loglevel`, …). The card therefore does not rely on a list of them (R3).
  - `cli_command.rs:266-267`: `-w` is `--workspace-root`, a **boolean**.
  - `cli_args/add/arguments.rs:101-102` and `:106-107`: `add`'s `--config` and `--workspace` are
    **booleans**. The classifier's shared `NODE_VALUE_FLAGS` (`classify-install-command.py:101-104`)
    lists `-w`, `--workspace` and `--config` as taking a value (true for npm), so for pnpm the
    package after them is read as their value and lost.
  - `flag_relocation.rs:1-29`, `:110-137`: an option that belongs to the subcommand's own grammar,
    typed before the subcommand, is moved to just after it. So `pnpm -c exec …` is
    `pnpm exec -c …`.
  - `flag_relocation.rs:139-158`: a leading `recursive`, `multi` or `m` followed by another
    positional is rewritten to `--recursive`, repeatedly. So `pnpm m add x` is
    `pnpm --recursive add x`; `pnpm m` alone is left as it is.

## Scope

In: the classifier change, its tests, and the parent card's Known-gaps rows; and two pre-existing
pnpm bugs the round-2 judge found (R9, R10), folded in at Mark's choice on 2026-10-24.
Out: `bun exec` (takes one quoted shell string — the `bash -c` gap, already in Known gaps);
`bash -c`/`sh -c`/`eval`; `yarn run <bin>`, `yarn <bin>` and `yarn node …` (run local programs,
never fetch); npm runners (`npm exec`, `npx`), which are already handled.

## Requirements

"Yarn programs" are `yarn`, `yarnpkg`, and `corepack yarn`; "pnpm programs" are `pnpm`, `pn`,
and `corepack pnpm` — as the classifier already recognises them.

R1. **`exec` runs what follows.** For a yarn or pnpm program, `exec [options] [--] <cmd> <args…>`
gets the same decision (allow / ask / deny) and the same reason text as the command line
`<cmd> <args…>` typed on its own. What counts as `[options]` and `<cmd>` is R3; how `<cmd>` is read
is R2.

R2. **The command word is read as shell code.** `<cmd>` is lexed with the existing
`shell_segments.segments()`, and `<args…>` are appended to the argv of the **last** segment that
lexing produces; then every segment is classified as an ordinary command. This copies yarn 4
(see above). For a plain word like `npm` it gives exactly `npm <args…>`. For a string like
`'npm i x'` or `'cd web && npm i x'` it finds the install. In yarn 1 and in pnpm without `-c` such
a string would fail to run, so reading it as an install only ever adds an ask/deny to a command
that errors anyway.
- **pnpm `-c`:** when `-c`/`--shell-mode` is among the options, `<cmd> <args…>` are instead joined
  with single spaces (as pnpm does, `exec.rs:220`) and that one string is lexed; every segment is
  classified.
- **A string the lexer cannot read** — the lexed text (`<cmd>`, or the `-c` joined string) is
  non-blank and `segments()` returns `[]`: when `<cmd> <args…>` names an install tool
  (`mentions_install_tool`), the result is the guard's existing **cannot-read ask** — the same text
  (`CANNOT_READ_TEXT`, `decide-dependency.py:43-44`) and the same log word (`cannot-read`) a
  top-level unreadable command gets (`decide-dependency.py:319-321`); otherwise nothing. This needs a
  new intent source in the classifier and one branch in `decide_intent` (R8). The `xargs` message is
  not reused: it names `xargs`.
  - The new intent carries ecosystem `npm`, the yarn/pnpm program as its name, `form: "add"` and
    a new `source` (`"cannot-read"`), because `decide_intent` validates the ecosystem before
    anything else (`decide-dependency.py:275`). `form` must be `"add"`: its name (`yarn`/`pnpm`)
    is in `INSTALL_TOOL_WORDS`, so `form: "run"` would be caught by the runner-installer check at
    `:277` and denied with the wrong text. The new branch goes after that check, with the
    `source` branches (`:279-286`), and before the unpinned deny (`:287`).
  - Its log line therefore shows `npm` and the program name in the ecosystem and name fields,
    where a top-level cannot-read line shows `- - -` (`:321`). Only the text and the log *word*
    must match; tests check those two and nothing else about the line.
- A script that refers to its own positional arguments (`$@`, `$1`) is not special-cased: the
  arguments are still appended. Disclosed in Known gaps; it can only add an ask/deny.
- **`VET_EXEMPT`:** a prefix assignment on the outer segment (`VET_EXEMPT=r yarn exec npm i x`)
  applies to the intents found inside it, as it does for the workspace wrappers today. An
  assignment *inside* the exec'd string (`yarn exec 'VET_EXEMPT=r npm i x'`) is not read — the
  intents get no exemption, so the guard denies. Fail-safe, and pinned by a test.

R3. **Finding `<cmd>`: options, `--`, and unknown option widths.** After `exec`:
- One `--` directly before `<cmd>` is dropped — yarn 1, yarn 4 and pnpm all drop it (see above).
- Words starting with `-` (other than `--`) before `<cmd>` are options. yarn's `exec` has none of
  its own, and pnpm accepts its own `-c` plus its global options there, several taking a value;
  the card does not keep a list of them. Instead, a word that starts with `-`, has no `=`,
  and is followed by a word not starting with `-` is read **both ways**: as standing alone (the
  next word is `<cmd>`), and as taking that next word as its value (the search continues after
  it). Every reading's intents are combined: for each distinct intent, keep the **largest number
  of copies any one reading produced**. So duplicates are dropped only across readings, never
  within one: `npm i x x` gives two intents, and `yarn exec npm i x x` must give two as well, or
  it would not match the plain command. If one reading gives `[x, x]` and another `[x]`, two
  copies survive. (R9 combines its readings the same way.) Over-reading can only add an ask/deny; it can
  never hide one, which a wrong guess at an option's width could. Example:
  `pnpm exec --filter web npm i x` is read as `web npm i x` (nothing) and as `npm i x` (deny), so
  it is denied.
- **Within one scan the readings grow linearly:** the "stands alone" reading ends the option
  scan at once (the next word is `<cmd>`), so only the "takes a value" reading continues. `k`
  ambiguous options give at most `k + 1` readings **per scan**. Across scans they multiply: each
  reading of an `exec` starts a fresh command (R4) with its own scans, so nesting compounds them
  (round 4 modelled `yarn exec -y exec yarn exec -y exec …` doubling every four words).
- **Reading cap (Mark, 2026-10-24, round 4):** the classifier counts every reading it starts for
  one command, across all scans and all nesting, against a named constant `MAX_READINGS = 64`.
  When starting one more would pass the cap, it stops and returns, in place of the intents found
  so far, the single cannot-read intent of R2 (ecosystem `npm`, name = the outer program,
  `form: "add"`, source `"cannot-read"`), so the guard gives the cannot-read ask. Asking is the
  fail-safe answer: an ask can never hide a deny, and a command past 64 readings is almost
  certainly crafted. No decider change beyond R2's branch.
- **`-c`/`--shell-mode` switches on R2's pnpm `-c` rule wherever it is typed before `<cmd>`:**
  after `exec`, or — for a pnpm program — before `exec`, since pnpm moves it there
  (`flag_relocation.rs:110-137`). `pnpm -c exec …` and `pnpm --shell-mode exec …` are read exactly as
  `pnpm exec -c …`. For a yarn program `-c` is just an option.
- `pnpm -r exec …`, `pnpm --filter web exec …`: options before `exec` are words before the
  subcommand, so R9's **before-the-subcommand** rule reads them (every option without `=` followed
  by a non-hyphen word, both ways); R3 applies to what follows `exec` in each reading. So
  `pnpm --reporter silent exec npm i x` is denied like `npm i x`. `pnpm -w exec …` and
  `pnpm m exec …` reach R3 only once R9 and R10 are in.

R4. **Workspace wrappers are unwrapped until none is left, and `exec` ends the chain.** After a yarn
`workspace <name>` or `workspaces foreach [opts]` is removed, if what remains starts with another
one, it is removed too, in any order and any number of times; each step consumes at least one
word, so this ends. If what remains starts with `exec`, R1–R3 apply to what follows it, and what
follows is a fresh command, not more yarn arguments. `yarn workspace a workspace b add x` → like
`yarn add x`; `yarn workspace web exec npm i x` → like `npm i x`.

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
added to the `bash -c` row, and the `$@` over-read (R2) and the both-ways option reading (R3) get
one line each; one line under its Verification points to this card. Each new or changed Known-gaps
line that names a command is pinned by an assertion, as the parent card's other gaps are:
`bun exec 'npm i x'` stays allowed silently; `yarn exec 'npm i "$@"' x` is denied (yarn 4 would
substitute rather than append; either way `x` is installed); the both-ways reading:
`pnpm exec --filter npm i x` is denied; the R9 over-read: `pnpm -r run add x`,
`pnpm --filter add test` and `npm --prefix add test` are no longer allowed; `yarn add -w x` stays
allowed silently (yarn's own subcommand words keep one reading, and yarn's `-w` was not examined
against yarn source); `bun --cwd add x` stays allowed silently (bun is outside R9); and the R3
reading cap gives the cannot-read ask for a command past 64 readings.
One more line names no command, so it has no pin: among a pnpm subcommand's words, only `-w`,
`--workspace`, `--config` and the runner's `-c` were checked against pnpm; any other
`NODE_VALUE_FLAGS` entry that is a boolean in pnpm still swallows the package after it there.

R8. **Size and shape.** `hooks/lib/classify-install-command.py` (679 lines today) stays under the
800-line cap; the classifier change is one small helper plus edits to `_node_manager`, not a new
module. `hooks/lib/decide-dependency.py` gets only the R2 cannot-read branch in `decide_intent` (a
few lines, reusing `CANNOT_READ_TEXT` and `LOG_CANNOT_READ`); no other decider change. R3's and
R9's readings share one small helper (enumerate readings, combine as in R3); R9 adds a pnpm width
set and a call to it at each scan site it names; R10 is a few lines in `_node_manager`. No new
module. If the classifier would pass 800 lines, stop and announce "GATE: Spec change needed".

R9. **Option widths: add readings, never replace one.** Mark's ruling (2026-10-24, round-3
escalation): one rule for npm, yarn and pnpm. The principle is that **today's reading is always
one of the readings**, so nothing denied or asked today can become an allow — every other reading
can only add intents. (Round 3 showed why: an earlier draft *replaced* pnpm's widths, and
`pnpm -w web add x`, `pnpm add -w --filter x` and six more went from deny/ask to allow.)
Readings are combined as in R3: for each distinct intent, keep the largest number of copies any
one reading produced.
- **Programs covered:** npm, yarn and pnpm (and their spellings `yarnpkg`, `corepack yarn`,
  `pn`), as Mark named them. bun is in the same node-manager table
  (`classify-install-command.py:90`), so it also goes through `_node_manager`, but it keeps today's single reading everywhere, so
  `bun --cwd add x` stays allowed silently (measured on 451194f). Pinned (R7).
- **Before the subcommand** — every `_subcommand` call a covered program's words go through
  (`_node_manager`, `_yarn_workspace_inner`, npm's `audit fix` in `_audit_fix`): R3's both-ways
  rule, for **every** option word that has no `=` and is followed by a word not starting with `-`.
  It is read as today (taking a value if it is in `NODE_VALUE_FLAGS`, otherwise standing alone)
  and the other way too. Either way one branch ends at once (the next word is the subcommand), so
  `k` such options give at most `k + 1` readings. This covers value options missing from the list
  (`pnpm --reporter silent add x`, `pnpm --store-dir /s add x`, `yarn --mutex file:/tmp/m add x`)
  and list entries that are booleans for this tool (`pnpm -w add x`, `yarn -w add x`), with no
  per-tool list to keep up to date.
- **Among a pnpm subcommand's own words** — the install-positional scan in `_node_manager`,
  `_plain_update`, pnpm's `audit --fix` in `_audit_fix`, and `_runner_intents` for `pnpm dlx`/
  `pn dlx`: two readings, today's widths and pnpm 12.15.0's. pnpm's widths are today's value set
  minus `-w`, `--workspace` and `--config` (booleans: `cli_command.rs:266-267`,
  `add/arguments.rs:101-102`, `:106-107`) and, for the runner scan, also minus `-c` (pnpm's
  `dlx -c` is the boolean `--shell-mode`, `dlx.rs:79-80`; npm's `-c` is `--call`, which takes a
  value). So `pnpm add -w x`, `pnpm add --workspace x`, `pnpm add --config x`, `pnpm dlx -w cowsay`
  and `pnpm dlx -c cowsay` are read like `pnpm add x` / `pnpm dlx cowsay`, while
  `pnpm add -w --filter x` stays denied through today's reading.
- npm's and yarn's own subcommand words keep today's single reading (`npm -w web install x` must
  stay denied naming `x`).
- **Not covered: the `workspaces foreach` option loop** in `_yarn_workspace_inner` (its own loop
  over `FOREACH_VALUE_FLAGS`, not a `_subcommand` call). It keeps its single reading: the
  yarn-workspaces card ruled that the word after a bare `--since` is the command, pinned by
  `hooks/dependency-guard.test.sh:511-512` (`yarn workspaces foreach --since main up` and
  `… --since main add lodash` are allowed). A both-ways reading there would flip both.
- If any pre-existing assertion changes result under R9, that is a spec problem, not a test to
  edit: stop and announce "GATE: Spec change needed".
- **Accepted over-read** (Known gaps, R7): before the subcommand, the extra reading can turn a
  value or a non-installing subcommand into an install. `pnpm -r run add x` (a script named `add`),
  `pnpm --filter add test` (a package named `add`) and `npm --prefix add test` (a directory named
  `add`) would be denied or asked. All three are allowed today (measured on 451194f). This needs a
  value word, or the word after a boolean option, that is spelled like an install, update or
  runner subcommand. On a command already denied or asked, the extra reading can also add names
  to the message (`npm --prefix add install x` would also name `install`); the decision does not
  change.

R10. **pnpm's `recursive`/`multi`/`m` alias.** For a pnpm program, while the subcommand word is
`recursive`, `multi` or `m` and another positional follows it, that word is skipped as pnpm's
`--recursive` and the next positional is the subcommand (`flag_relocation.rs:139-158`). So
`pnpm m add x` and `pnpm recursive add x` are read like `pnpm -r add x`, and `pnpm m exec npm i x`
like `pnpm -r exec npm i x`. `pnpm m` and `pnpm recursive` with nothing after them stay as today
(allowed). The alias word is read as the option it stands for, not as a wrapper: it adds no word
to an update ask, so `pnpm m up` asks exactly as `pnpm -r up` does (today `pnpm -r up` asks and
`pnpm m up` is allowed, both measured on 824ab6c).

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

Scenario: an unreadable exec string that names an install tool gets the cannot-read ask
  When Claude runs "yarn exec \"npm i 'x\"" (the command word has an unbalanced quote)
  Then the guard asks with the same text as a top-level command it cannot read
  And the log line's decision word is "cannot-read"

Scenario: an unreadable pnpm shell-mode string gets the cannot-read ask
  When Claude runs "pnpm exec -c \"npm i 'x\""
  Then the guard asks with the same text as a top-level command it cannot read

Scenario: an unreadable exec string with no install tool is allowed
  When Claude runs "yarn exec \"echo 'hi\""
  Then the guard allows it silently

Scenario: a -- before the command is dropped
  When Claude runs "yarn exec -- npm i x" or "pnpm exec -- npm i x"
  Then the guard denies like "npm i x"

Scenario: a pnpm global option after exec, with or without a value
  When Claude runs "pnpm exec --filter web npm i x" or "pnpm exec -r npm i x" or "pnpm exec --dir=web npm i x"
  Then the guard denies like "npm i x"

Scenario: an exemption on the outer command covers the exec'd install
  Given x@1.0.0 has no vetting report
  When Claude runs "VET_EXEMPT=reason yarn exec npm i x@1.0.0"
  Then the guard asks like "VET_EXEMPT=reason npm i x@1.0.0"

Scenario: an exemption inside the exec'd string is not read
  Given x@1.0.0 has no vetting report
  When Claude runs "yarn exec 'VET_EXEMPT=reason npm i x@1.0.0'"
  Then the guard denies like "npm i x@1.0.0"

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

Scenario: pnpm shell mode typed before exec
  When Claude runs "pnpm -c exec npm i \"'x\"" or "pnpm --shell-mode exec npm i \"'x\""
  Then the guard gives the exact result of "pnpm exec -c npm i \"'x\"" (the cannot-read ask)

Scenario: pnpm's boolean -w, --workspace and --config no longer swallow the package
  When Claude runs "pnpm -w add x" or "pnpm add -w x" or "pnpm add --workspace x" or "pnpm add --config x"
  Then the guard denies like "pnpm add x"

Scenario: a value option the guard does not know, before the subcommand
  When Claude runs "pnpm --reporter silent add x" or "pnpm --store-dir /s add x" or "yarn --mutex file:/tmp/m add x" or "yarn -w add x"
  Then the guard denies like "pnpm add x" or "yarn add x"

Scenario: pnpm dlx with pnpm's boolean -w or -c
  When Claude runs "pnpm dlx -w cowsay" or "pnpm dlx -c cowsay"
  Then the guard denies like "pnpm dlx cowsay"

Scenario: a value option the guard does not know, before exec
  When Claude runs "pnpm --reporter silent exec npm i x"
  Then the guard denies like "npm i x"

Scenario: a command past the reading cap gets the cannot-read ask
  When Claude runs "yarn exec -y exec " repeated 7 times, followed by "npm i x"
    (2^7 = 128 readings under the round-4 model; the classifier test also asserts the cap was hit,
    and if 7 does not pass it, Task 1 uses the smallest repeat count that does)
  Then the guard asks with the same text as a top-level command it cannot read
  And the log line's decision word is "cannot-read"

Scenario: bun keeps today's reading
  When Claude runs "bun --cwd add x"
  Then the guard allows it silently

Scenario: today's reading is kept, so nothing denied today is allowed
  When Claude runs "pnpm -w web add x" or "pn -w web add x" or "pnpm --workspace web add x" or "pnpm --config foo add x" or "pnpm add -w --filter x"
  Then the guard still denies
  When Claude runs "pnpm -w web update" or "pnpm -w foo audit --fix"
  Then the guard still asks

Scenario: npm's -w still takes a value
  When Claude runs "npm -w web install x"
  Then the guard denies naming x, not web

Scenario: pnpm's recursive alias
  When Claude runs "pnpm m add x" or "pnpm multi add x" or "pnpm recursive add x"
  Then the guard denies like "pnpm -r add x"
  When Claude runs "pnpm m" or "pnpm recursive"
  Then the guard allows it silently
  When Claude runs "pnpm m up"
  Then the guard gives the exact result of "pnpm -r up"

Scenario: other spellings are covered
  When Claude runs "yarnpkg exec npm i x" or "corepack yarn exec npm i x"
  Then the guard denies like "npm i x"

Scenario: an exec with nothing after it is allowed
  When Claude runs "yarn exec" or "pnpm exec -c"
  Then the guard allows it silently
```

## Tasks

- [ ] 0. Re-measure on the branch base: re-run every Evidence-table probe and re-check each
  file:line under "What the tools actually do" at the pinned versions. Nothing in the spec is
  edited here: if any result differs, stop and announce "GATE: Spec change needed" (the phase gate
  forbids spec edits during implementation). Source is read only as a tarball or via `gh api` into
  a `mktemp -d` directory, never installed or run.
- [ ] 1. Tests first, in `hooks/dependency-guard.test.sh` (hook level) and the classifier's own
  suite: one assertion per Evidence-table row, per scenario, and per R7 pin, and replace any pin
  found under R7. Every "like `<plain command>`" row uses the existing `same_result`
  (`hooks/dependency-guard.test.sh:444`), which compares exit code, stdout and stderr with the plain
  command and refuses a silently-allowed control; the cannot-read rows compare with a top-level
  unreadable command and check the log word; allow rows use `allow_cmd`. Before committing, list
  the new assertions in two groups and run the suite:
  - **must fail before the fix:** every row of the three Evidence tables marked "allow, silent"
    except `bun exec` and `yarn add -w x`; every deny/ask scenario that goes through `exec`, a
    nested wrapper, R9 or R10 except the "today's reading is kept" and "npm's -w still takes a
    value" scenarios; the `$@` pin (`yarn exec 'npm i "$@"' x`, allowed today); the both-ways pin
    (`pnpm exec --filter npm i x`); the reading-cap scenario (allowed today); and the three
    over-read pins (`pnpm -r run add x`, `pnpm --filter add test`, `npm --prefix add test`,
    allowed today);
  - **already pass, pinning behaviour the fix must keep:** the allow rows (`yarn exec echo hi`,
    `yarn exec tsc`, `pnpm exec eslint .`, `yarn exec`, `pnpm exec -c`, `pnpm m`,
    `pnpm recursive`, the unreadable string with no install tool), the already-handled rows
    (`yarn workspace web add x`, `npm exec -- npm i x`, `pnpm --workspace-root add x`,
    `pnpm --filter web add x`, `pnpm -r add x`, `npm -w web install x`,
    `pnpm -c exec cd web '&&' npm i x`, `pnpm --reporter=silent add x`,
    `pnpm add --store-dir /s x`, `pnpm dlx cowsay`, `pnpm -r up`), every command of the "today's
    reading is kept" scenario (`pn -w web add x` included), and the `bun exec`, `yarn add -w x`
    and `bun --cwd add x` Known-gaps pins.

  Pass condition: exactly the first group fails, and nothing else does. Commit the red suite on
  its own (`TEST_EXEMPT`, since a red suite writes no marker).
- [ ] 2. Classifier change (R1–R6, R8–R10) and the R2 decider branch. Re-run both suites: green; the pre-existing assertion count
  is unchanged apart from replaced pins. Re-run the Evidence-table probes.
- [ ] 3. Parent card Known-gaps edits and the pointer line (R7).
- [ ] 4. Verification section; observability judge (implementation stage, Opus high); PR.

## Gotchas

- Probe payloads need `"hook_event_name": "PreToolUse"`; without it the hook can allow without
  inspecting. Prove each probe harness with deny and ask controls first.
- Point the suite's state dir (`DEPENDENCY_GUARD_STATE_DIR`) at a scratch directory, never the
  real `hooks/state/`.
- The shared lexer splits at a quoted `&&`/`;` (`segments("a '&&' b")` gives two segments), so a
  test meant to exercise shell-mode joining must not rely on a quoted operator — it would pass
  before the fix. Use a quote character inside an argument instead (`npm i "'x"`).
- The hook runs from the primary checkout; a merge is live only after `~/.claude` pulls it.
- This session's worktree isolation refuses compound Bash (`$(( ))`, `&&` chains with variables):
  put probe loops in a script file.

## Verification

Task 0 (2026-10-24, on `50060ec`; `hooks/` unchanged since `a1a7cc8` and identical to
`origin/main`):

- Evidence probes: the controls (`npm install left-pad` deny, `npm update` ask, `ls` allow) and all
  72 commands of the three Evidence tables plus the Task 1 pins re-measured with the same harness:
  75 of 75 match, 0 differ.
- Source re-read at the pinned versions (yarn 1.22.22, `@yarnpkg/cli-dist` 4.18.1, pnpm
  `v12.15.0`) and the local file:line refs: all hold except one wording point, recorded here
  at Mark's choice instead of a spec edit (it changes no behaviour). "What the tools actually do"
  says `RecursiveExecutionArgs` are "all `#[clap(skip)]`". The struct is defined in
  `cli_args/recursive/execution_args.rs`, flattened into exec at `exec.rs:37-38`. Three fields
  are `#[clap(skip)]` (lines 6, 11, 17) and three are `#[clap(skip = true)]` (`sort`, `reverse`,
  `parallel`, lines 20, 23, 26). None of the six is a command-line option, so the card's
  conclusion holds.
