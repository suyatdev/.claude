---
phase: planning
model_tier: low
branch: none  # planning card on docs/git-guard-quiet-spec; implementation branch is created at `gate confirmed`
---

# git-guard quiet — a session toggle that lets known-safe `git -C` commands through without a prompt

> **Phase: planning — revision 5 (2026-10-26).** History: rev 1 (`64b6232`) silenced the `-C`
> prompt outright; round 1 measured that for a `-C` command the prompt is the **only** check, so a
> commit to `main` would have gone through. Revs 2–3 (`4bc66cb`, `8780b3f`) tried to give every
> `-C` command the real blocks in every session; the round-3 cap escalated to Mark. Rev 4
> (`5ff3fb3`) implemented Mark's rule "with quiet on, let every `-C` command through unless it
> would commit or push to `main`/`master` of any repository" as a **denylist** — round 4 measured
> seven ways to still land on `main` (a `switch main` earlier on the line, `merge`, `HEAD:main`,
> `--all`/`--mirror`, `export GIT_DIR=`, `pushd`, a bare push under `push.default=upstream`).
> Mark then approved (2026-10-26, "yes go with that") flipping it to an **allowlist**: quiet
> silences only a named set of read-only commands, `git add`, and a commit/push in the plain
> case; everything else still prompts, and **quiet never adds a deny**. No code exists.
> Next: judges round 5 → Mark reviews → `gate confirmed`.

## Why

`hooks/git-guard.sh` asks for confirmation whenever a git command carries an option ahead of the
subcommand that it cannot account for — in practice `git -C <dir> …`. Mark reports several prompts
per session, approved "almost all the time". His two most recent, verbatim in shape:

- `W=~/.worktrees/Snatch-Bracket/roadmap-lane-updater; git -C "$W" status --short; git -C "$W" hash-object docs/features/roadmap-lane-updater.md; …`
- `git -C /Users/marksuyat/.worktrees/Snatch-Bracket/round-config-validation-gaps cat-file -t <sha>`

Both are read-only. A prompt that is always approved trains approval without reading.

Measured on `origin/main` `9cc42f4` (`hooks/lib/classify-git-command.py:537-540`): a segment with a
blocking option gets **no** `COMMIT*`/`PUSH*` fact, so for `git -C <repo on main> commit` and
`git -C <repo> push --force` the ask is the only thing git-guard does. Silencing it naively would
open those. This card silences it only for the shapes listed below; every other shape keeps
today's prompt.

## Decisions

| # | Question | Decision | Whose |
|---|---|---|---|
| D1 | When anything changes | Only while quiet is on for the session. With quiet off, git-guard's behaviour is byte-for-byte today's | Mark ("every session starts on") |
| D2 | What quiet can do | Turn today's `-C` **ask** into an **allow**, for a line made only of the shapes in D3–D5. It never turns anything into a deny and never touches a decision today's guards already make — every existing deny runs first, unchanged | Mark (allowlist approved 2026-10-26); "never a new deny" is Claude's call, so quiet off and quiet on differ only by asks becoming allows |
| D3 | Read-only commands | A git segment whose subcommand is on the read list (§ The lists) passes, whatever folder `-C` names (including `"$W"`) | Mark (his two examples); list contents are Claude's call |
| D4 | `git add` | Passes, whatever folder — it stages, it cannot move a branch | Claude's call |
| D5 | Commit and push | Pass only when (a) **every** segment on the line is a git segment classed `read`, `add`, `commit` or `push` — no `cd`, `pushd`, `export`, assignment-only segment, script, wrapper, or other git subcommand anywhere on the line, so nothing on the line can switch branch or repository; (b) the segment has exactly one `-C` whose folder is checkable (D6); (c) that folder is on a branch other than `main`/`master` with nothing in progress (D7); (d) for a push, the push is one of the two allowed shapes (D8). Any condition unmet → ask | Mark's rule ("not to a main/master of any repository"); conditions (a)–(d) are Claude's call, each closing a measured round-4 hole |
| D6 | Checkable folder | Exactly one `-C`; its operand is an absolute path, `~`, `~/…`, or relative (resolved against the payload's `cwd`, valid because D5(a) forbids anything that changes directory); no `$`, backtick, glob character (`*?[`), and no other `~` form (`~user`, `~+`, `~-`, `~0` expand to other places) | Claude's call — deliberately narrower than worktree-guard's `resolve_effective_repo`, which round 3 measured exits the hook instead of returning |
| D7 | Branch check | `git -C <dir> symbolic-ref --short HEAD` must succeed and name neither `main` nor `master`, and none of `rebase-merge`, `rebase-apply`, `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `BISECT_LOG` may exist under `git -C <dir> rev-parse --git-path <name>`. Detached, not a repository, in progress, on `main`/`master`, or any error → ask | Claude's call |
| D8 | Allowed push shapes | Options only from `-u`, `--set-upstream`, `-q`, `--quiet`, `-v`, `--verbose`, `--force-with-lease` (bare, no `=`). Then either **no positional argument** — allowed only if `git -C <dir> rev-parse --symbolic-full-name @{push}` succeeds and its last path component is neither `main` nor `master` — or exactly **`<remote> HEAD`**, where `<remote>` matches `^[A-Za-z0-9._-]+$` (git documents `push <remote> HEAD` as "push the current branch to the same name", which D7 already proved is not `main`/`master`). Anything else — `--force`, `-f`, `-uf`, `--all`, `--mirror`, `--tags`, `--delete`, `--force-with-lease=…`, `--receive-pack`/`--exec`, `--repo=`, a refspec with `:` or `+`, a branch name, any other option → ask | Claude's call, from round-4 `writing-specs/edge-cases` |
| D9 | Other options and prefixes | Any non-`-C` blocking option anywhere on the line (`SEG_SCOPE_OPT`), any `GIT_*` assignment (`SEG_ENV`), any `SEG_OPAQUE`, or `SEG_GROUPED` → ask, read-only lines included | Claude's call, from rounds 1–4 |
| D10 | Switching on | Mark types the fixed phrase `git-guard quiet` | Mark |
| D11 | Switching back | The fixed phrase `git-guard on` | Claude's call, offered to Mark, not objected to |
| D12 | Default | Every session starts with the prompt **on**; nothing carried over can turn it off | Mark |
| D13 | Who flips the flag | A `UserPromptSubmit` hook that sees Mark's message — not Claude via a tool call | Claude's proposal; Mark chose the fixed phrase on that basis |
| D14 | Lifetime | Until `git-guard on` or the session ends; keyed to `session_id` | Mark (D12) |
| D15 | What counts as the phrase | The **whole** message, surrounding whitespace trimmed, equals the phrase exactly (case-sensitive) | Claude's call — a pasted document, or this card, contains the phrase and must not flip it |
| D16 | Trail | Each silenced ask appends one log line with the outcome and a hash of the command — **never** the command text | Claude's call, from round-1 `writing-secure-code/no-secret-logging` |
| D17 | Where state lives | `$HOME/.claude/hooks/state/git-guard-quiet/` (gitignored, `.gitignore:17`), directory `0700`, files `0600` | Claude's call, from round-1 `core-conduct/default-deny-data-store` |
| D18 | Shared facts | Existing facts keep exactly today's meaning; doc-guard (`:144`) and feature-sync-guard (`:111`) see no change. One new segment-indexed fact is added, emitted only on lines that already carry `SCOPE_UNKNOWN`, read only by git-guard | Claude's call, from round-2 `core-conduct/extend-not-alter-shared-interface` |

## The lists

Each git segment on a line carrying `SCOPE_UNKNOWN` is put in exactly one class. A subcommand is
matched by its exact name, so an alias (`git -C F st`) is never on a list and asks.

| Class | Subcommands and the argument rule |
|---|---|
| `read` | `status`, `log`, `diff`, `show`, `cat-file`, `rev-parse`, `ls-files`, `ls-tree`, `show-ref`, `merge-base`, `describe`, `blame`, `shortlog`, `for-each-ref` — with **no** argument starting `--output` (these write a file). `hash-object` without `-w`. `branch` with exactly `--show-current`, or with `--list`/`-l` (anything after is a pattern). `worktree list`. |
| `add` | `add`, any arguments |
| `commit` | `commit`, any arguments — D5/D6/D7 do the checking |
| `push` | `push` in a D8 shape |
| `other` | every other git segment, including a push not in a D8 shape and every subcommand not named above (`merge`, `switch`, `checkout`, `rebase`, `reset`, `pull`, `fetch`, `cherry-pick`, `revert`, `am`, `update-ref`, `symbolic-ref`, `config`, `branch -f`, `stash`, …) |
| `nongit` | a segment that is not a git command (`wc`, `cd`, `pushd`, `export`, an assignment-only `W=…`, a script) |

**Line rule.** With quiet on, the line passes if no D9 fact is present and:
- it has no `commit`/`push` segment, and every git segment is `read` or `add` (`nongit` segments
  allowed — they get exactly the treatment they would get on their own line); or
- it has a `commit`/`push` segment, every segment is `read`/`add`/`commit`/`push` (no `nongit`, no
  `other`), and every `commit`/`push` segment meets D6 and D7 (and D8 for push).

Otherwise: ask, exactly as today.

## Design

```mermaid
flowchart TD
    A[git-guard: every existing deny runs first, unchanged] --> B{SCOPE_UNKNOWN ask due?}
    B -->|no| OK[exit as today]
    B -->|yes| Q{quiet flag for this session_id?}
    Q -->|no| ASK[ask, as today]
    Q -->|yes| O{SEG_SCOPE_OPT, SEG_ENV, SEG_OPAQUE or SEG_GROUPED?}
    O -->|yes| ASK
    O -->|no| L{any commit or push segment?}
    L -->|no| R{every git segment read or add?}
    R -->|no| ASK
    R -->|yes| LOG[log line, allow]
    L -->|yes| P{every segment read/add/commit/push?}
    P -->|no| ASK
    P -->|yes| C{each commit/push: one checkable -C, branch not main/master, nothing in progress, push shape allowed?}
    C -->|no| ASK
    C -->|yes| LOG
```

### Classifier — one new fact (D18)

The class rules live in a new module `hooks/lib/git_quiet_class.py` (pure function: subcommand +
remaining argv → class), imported by `hooks/lib/classify-git-command.py`, which is 602 lines and
should not absorb them. On a line that carries `SCOPE_UNKNOWN`, the classifier emits, for **every**
segment `i`:

- `SEG_QUIET<tab><i><tab><class>` — `class` from § The lists; for `push` the fact is
  `push_default` (no positional) or `push_head` (`<remote> HEAD`), so git-guard knows whether the
  `@{push}` check applies.

Lines without `SCOPE_UNKNOWN` get no new fact. Every existing fact — `COMMIT*`, `PUSH*`,
`SCOPE_UNKNOWN`, `SEG_GIT_C`, `SEG_SCOPE_OPT`, `SEG_ENV`, `SEG_CD`, `SEG_OPAQUE`, `SEG_GROUPED`,
`SEG_BRANCH_MOVE`, `SEG_WORKTREE_ADD` — is emitted exactly as today. The `-C` operand for D6 comes
from the existing `SEG_GIT_C` (which is `UNRESOLVABLE` for two `-C`s).

### git-guard — the quiet decision

`hooks/git-guard.sh` (488 lines) sources a new `hooks/lib/git_guard_quiet.sh`, called once, at the
start of Guard 3, after every existing deny, and **only if** the flag for the payload's
`session_id` exists. It applies the line rule, running D7/D8's git calls with `-C <dir>` for each
`commit`/`push` segment. Allow → append the log line and `exit 0`. Anything else → fall through to
today's ask text, unchanged. With no flag, Guard 3 runs exactly as today.

### The toggle

`hooks/git-quiet-toggle.sh` (new, `UserPromptSubmit`). Reads the payload's `prompt` and
`session_id` (names confirmed in Task 0). On an exact `git-guard quiet` it creates
`$HOME/.claude/hooks/state/git-guard-quiet/<session_id>`; on an exact `git-guard on` it deletes it.
It then **re-checks** the flag and prints, on stdout as plain text (added to Claude's context;
Claude relays it to Mark), exactly one of:

- `git-guard quiet: ON for this session (read-only -C lookups, git add, and plain feature-branch commits/pushes pass without a prompt; everything else still asks).`
- `git-guard quiet: OFF for this session (the -C prompt is back).`
- `git-guard quiet: FAILED to change state — the prompt is <ON|OFF>. <error>`

The state printed is the one measured after the change. Any other message: no output, no file
touched.

### Log line

`$HOME/.claude/hooks/state/git-guard-quiet.log`, one line per silenced ask, tab-separated, in this
order: ISO-8601 UTC timestamp (`YYYY-MM-DDTHH:MM:SSZ`), `session_id`, `read` or `lands` (whether
any segment committed or pushed), SHA-256 of the raw command (hex). No command text. **If the
append fails, git-guard asks.**

## Requirements

`F` is a worktree on `feat/x`; `M` a repository on `main`; `U` a worktree on `feat/u` whose
upstream is `origin/main` with `push.default=upstream`; the session cwd is `~/.claude` on `main`.

With quiet **off**:
- R1. Every command in R2–R13 gets exactly today's decision (asserted against `origin/main`'s
  git-guard on the same fixtures).

With quiet **on** — allowed, one log line each:
- R2. Mark's first example (`W=…; git -C "$W" status --short; git -C "$W" hash-object <f>; wc -l <f>`)
  and `git -C F cat-file -t <sha>` → allowed, `read`.
- R3. `git -C F add -- f && git -C F commit -m x -- f && git -C F push -u origin HEAD` → allowed, `lands`.
- R4. `git -C F push` with an upstream of `origin/feat/x` → allowed, `lands`.

With quiet **on** — still asks (each was a measured or named round-4 route to `main`):
- R5. `git -C M commit -m x`; `git -C M push origin HEAD`.
- R6. `git -C F switch main && git -C F commit -m x`; `git -C M merge feat/x`;
  `git -C F symbolic-ref HEAD refs/heads/main`; `git -C F config core.hooksPath /dev/null`.
- R7. `git -C F push origin HEAD:refs/heads/main`; `git -C F push origin HEAD:main`;
  `git -C F push --all`; `git -C F push --mirror`; `git -C F push origin feat/x`.
- R8. `git -C U push` (its `@{push}` is `origin/main`).
- R9. `git -C F push --force`; `git -C F push -uf origin HEAD`; `git -C F push --force-with-lease=feat/x`.
- R10. `export GIT_DIR=M/.git; git -C F commit -m x`; `pushd M && git -C . commit -m x`;
  `cd M && git -C . commit -m x`; `git -C "$W" commit -m x`; `GIT_DIR=M/.git git -C F status`.
- R11. A commit folder that is detached, mid-rebase, mid-merge, or not a repository.
- R12. `git -C F -c core.hooksPath=/dev/null status`, `git -c core.hooksPath=/dev/null -C F status`,
  `git -C F status && git -c core.hooksPath=/dev/null status`; `git -C F st` (alias);
  `git -C F diff --output=/tmp/x`.

Unchanged existing decision:
- R13. `git -C F status && git commit -m y` → **denied**, as today (the plain commit is on `main`;
  Guard 2 runs before Guard 3).

Toggle and failure handling:
- R14. A flag for a **different** `session_id` has no effect.
- R15. `session_id` is validated (`^[A-Za-z0-9-]{1,128}$`) before becoming a path component, in
  both hooks. Invalid or missing ⇒ the toggle prints the FAILED line and changes nothing; git-guard
  behaves as if no flag exists.
- R16. Only a whole-message exact match flips the flag (D15).
- R17. The toggle hook never blocks Mark's message: on any error it prints the FAILED line, exits 0.
- R18. Any error reading the flag, running a D7/D8 git call, or writing the log makes git-guard ask.

## Scenarios

```gherkin
Scenario: quiet lets a read-only -C lookup through
  Given Mark has typed "git-guard quiet" in session S
  When Claude runs a line setting W and running "git -C \"$W\" status --short" in session S
  Then git-guard allows it without asking

Scenario: quiet lets a plain worktree commit and push through
  Given the flag is set for session S and F is on feat/x
  When Claude runs "git -C F commit -m x -- f && git -C F push -u origin HEAD" in session S
  Then git-guard allows it without asking

Scenario Outline: quiet still asks for anything that could land on main
  Given the flag is set for session S, F is on feat/x and M is on main
  When Claude runs "<line>" in session S
  Then git-guard asks
  Examples:
    | line                                              |
    | git -C M commit -m x                              |
    | git -C F switch main && git -C F commit -m x      |
    | git -C M merge feat/x                             |
    | git -C F push origin HEAD:refs/heads/main         |
    | git -C F push --mirror                            |
    | git -C \"$W\" commit -m x                         |
    | pushd M && git -C . commit -m x                   |

Scenario Outline: quiet never silences -c, wherever it sits
  Given the flag is set for session S
  When Claude runs "<line>" in session S
  Then git-guard asks
  Examples:
    | line                                                     |
    | git -C F -c core.hooksPath=/dev/null status              |
    | git -c core.hooksPath=/dev/null -C F status              |
    | git -C F status && git -c core.hooksPath=/dev/null status |

Scenario: a new session starts loud
  Given a flag exists for session S
  When session T runs "git -C F status"
  Then git-guard asks

Scenario: on restores the prompt
  Given the flag is set for session S
  When Mark types "git-guard on"
  Then the toggle prints the OFF line and the next -C command asks

Scenario: the phrase inside other text does nothing
  When Mark's message is "should I type git-guard quiet?"
  Then no flag is created and the toggle prints nothing
```

## Known gaps — disclosed, not fixed

- **Claude can forge the flag.** It is a plain file; a Bash or Write call can create it without
  Mark's phrase, and unlike `secret_approval.py` (one command, deleted on use) it covers the whole
  session. D13 makes the honest path the hook, not the only path. A momentum guardrail, not a
  security boundary.
- **doc-guard and feature-sync-guard never see `-C` commits** (`has_fact COMMIT || exit 0` at
  `doc-guard.sh:144`, `feature-sync-guard.sh:111`). True today, unchanged by this card; under quiet
  the git-guard prompt — the one moment a human sees such a commit — goes away for commits D5
  allows. Round 3 measured doc-guard passing a 400-line `-C .` commit (rc=0) that it refuses
  without `-C` (rc=2). Fixing that blind spot is a separate card.
- **`-C` commits are already refused in `~/.claude`** by test-marker-guard (`FOREIGN_REPO`,
  observed in this session), so R3's allow only shows in repos that haven't opted in to it.
- **Check-then-run race.** D7 reads the folder's branch when the hook runs; another session could
  switch that worktree's branch before the command executes. Nothing on the *same* line can
  (D5(a)); a parallel session can.
- **A hostile repository's own config still runs.** `git -C <dir> status` honours `<dir>`'s
  `core.fsmonitor`, external diff and textconv settings — the same exposure as
  `cd <dir> && git status`, which git-guard allows today without asking. Quiet removes the prompt
  that would have preceded it for `-C`.
- **`nongit` segments on a read-only line** (`git -C F status; ./script.sh`) lose the incidental
  prompt the `-C` used to give them; they are judged exactly as if they stood alone, which is
  today's treatment of `./script.sh` on its own line.
- **Stale flags accumulate** — one empty file per session that ever went quiet; harmless (they
  can never match again). Cleanup deferred unless the directory is measured growing.
- **Unmeasured:** whether in-process subagents report the parent's `session_id`; whether an open
  session runs a `UserPromptSubmit` hook registered after it started; whether a `UserPromptSubmit`
  hook's stdout is shown to Mark directly. All three: Task 0. git-guard's own change needs no
  restart — each hook call runs the script file fresh from `$HOME/.claude/hooks/`.

## Tasks

- [ ] 0. Measure the three unknowns above and the `UserPromptSubmit` payload field names; record
      each under Known gaps.
- [ ] 1. **Baseline update, as its own step:** the exact-equality fact sets in
      `hooks/lib/classify-git-command.test.py` (compare at `:839-840`) for lines carrying
      `SCOPE_UNKNOWN` gain the new `SEG_QUIET` facts. Re-locate those cases by content. Commit red.
- [ ] 2. Class tests, red, in a new `hooks/lib/git_quiet_class.test.py` (paired by name with the
      new module, so the marker gate covers it); falsify against always-`read` and always-`other`
      stubs. Implement `hooks/lib/git_quiet_class.py` and the `SEG_QUIET` emission to green; every
      existing classifier, git-guard, doc-guard and feature-sync-guard suite stays green with no
      further edits.
- [ ] 3. Quiet-decision tests, red, in a new `hooks/git-guard-quiet.test.sh` (R1–R14, R18), invoked
      from `hooks/git-guard.test.sh` so the paired runner covers them (ADR 0044; the existing suite
      is 1008 lines, past the 800 cap). Falsify against always-allow and always-ask stubs.
- [ ] 4. Implement `hooks/lib/git_guard_quiet.sh` and its one call in Guard 3 to green.
- [ ] 5. Toggle tests, red, in `hooks/git-quiet-toggle.test.sh` (R15–R17, last scenario).
- [ ] 6. Implement `hooks/git-quiet-toggle.sh` to green.
- [ ] 7. Register the toggle in `settings.json` (`UserPromptSubmit`), stored `100755`.
- [ ] 8. ADR under `docs/decisions/` (next free number checked against `origin/main`): the quiet
      rule, why an allowlist and not a denylist (round 4), why quiet never adds a deny, why D6 is
      narrower than worktree-guard's resolver.
- [ ] 9. `rules/gates.md`: amend the existing **Default-branch safety** text rather than add a new
      always-loaded bullet — the two phrases, what quiet lets through, that everything else still
      asks, the forge gap.
- [ ] 10. Observability judge, then PR.

## Verification

Live, after merge into the primary checkout:
1. Without quiet: `git -C <a worktree> status` — prompts, as today.
2. Type `git-guard quiet`, see the ON line; repeat step 1 — no prompt, one `read` log line.
3. `git -C <a worktree on a feature branch> commit …` in a repo without test-marker-guard — no prompt.
4. `git -C <a repo on main> commit -m x` — prompts.
5. `git -C <a worktree> merge <x>` — prompts.
6. Type `git-guard on`, see the OFF line; step 2's command prompts again.
