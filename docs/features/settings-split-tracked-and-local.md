---
phase: implementation
model_tier: xhigh
branch: chore/settings-split
---

# Split settings.json: track the wiring, keep the machine-specific parts local

Planned 2026-08-21 on `main` @ `c4abf65`. **Blocks `judge-ledger-commitability`** — the suite is
not green until this lands.

## Problem

`9cc792f` untracked `settings.json` and `stats-cache.json` as "machine-specific runtime files".
The reason was real: `model` and `effortLevel` rewrite on every `/model`, producing constant churn
and merge friction. But `settings.json` is also **the only thing that turns the hooks on** — the
scripts in `hooks/` are inert until it registers them.

Consequences, all measured on `c4abf65`:

1. **A fresh clone gets the guard scripts and none of the guards.** No default-branch block, no
   phase gate, no doc checkpoint, no judge gate — and nothing announces their absence. This is the
   "advertised protection that is not protecting" pattern `rules/gates.md` already names for the
   four dormant hooks.
2. **`SETUP.md:28` is now false**, verbatim: "`settings.json` is tracked and will be cloned
   automatically." It is the new-machine checklist, wrong at the step that matters.
3. **Hook registration lost its audit trail.** PR #58 adding `test-marker-guard` was a reviewable
   4-line diff. A guard being switched off now leaves no diff and no history.
4. **Three suites fail**, same assertion each: `feature-sync-guard` 29/30, `memsearch-nudge` 26/27,
   `slim-session-start` 28/29 (under `env -u CLAUDE_PANE_AGENT`). Total 814/3, was 817/0.
   Each asserts its hook is registered in `settings.json`, which no longer exists in a worktree.

## Fix

> **Superseded 2026-08-21.** The split below cannot be built: `~/.claude/settings.local.json` is
> not a settings source, and `/model` writes `model` into the tracked file by design, so no split
> would hold even if it were. Kept for the record; the design that ships is **Fix (revised)**.
> Evidence: "Task 1 outcome" below.

<details>
<summary>Original plan — split by <em>what the file is for</em>, not by convenience</summary>

| Stays tracked in `settings.json` | Moves to gitignored `settings.local.json` |
|---|---|
| `permissions` | `model`, `effortLevel` — churn on every `/model` |
| `hooks` (the repo's own guards, all `$HOME`-relative) | the `.orca/agent-hooks/` entries — **10 hardcoded `/Users/marksuyat` paths**, which `core-conduct` forbids in committed files |
| `statusLine` (already `$HOME`-relative) | `theme`, `editorMode`, `tui`, `preferredNotifChannel`, `remoteControlAtStartup`, `inputNeededNotifEnabled`, `agentPushNotifEnabled`, `skipDangerousModePermissionPrompt` |
| `enabledPlugins` | |

`settings.local.json` is genuinely supported — verified against the installed binary
(`strings ~/.local/bin/claude | grep -c settings.local.json` → 103), not from memory.
*(That count is a project-scope feature misread as a user-scope one — see finding 2.)*

</details>

## Fix (revised)

**There is no split.** `settings.json` goes back under version control whole, with the ten
`/Users/marksuyat` orca paths rewritten to `"$HOME"` so nothing absolute is committed. `model` and
`effortLevel` stay in it and are committed at their current values.

Why no split, in one line each:

- **The destination is not read.** `~/.claude/settings.local.json` containing
  `{"model": "claude-haiku-4-5-20251001"}` had no effect — the session still ran
  `claude-opus-5[1m]`. The identical file at `<cwd>/.claude/settings.local.json` did switch it to
  haiku. The key is fine; the location has no reader.
- **Nothing would stay split anyway.** `/model` writes `model` and `effortLevel` into
  `~/.claude/settings.json`. Measured on this machine: both keys changed there at 12:31 on
  2026-08-21 when the session moved from `sonnet`/`medium` to `opus[1m]`/`xhigh`. Hand-moving them
  out lasts until the next `/model`.
- **A `.gitattributes` clean filter is not a safe substitute.** It works for `git status` — the
  stored blob really does lose `model`/`effortLevel` and the tree reads clean — but with no smudge
  half, any checkout or merge that *changes* `settings.json` materialises the stripped blob over
  the working copy and silently wipes the local values. Confirmed in a throwaway repo for both
  `git checkout` and `git merge`. Registering a new hook is exactly such a change, so the failure
  fires on the one operation this card exists to enable.

**The churn is accepted, and it is smaller than it looked.** Only a deliberate `/model` rewrites
the file: `settings.json` was last modified at 12:31 and was still untouched at 13:49 across
roughly eight intervening headless sessions. So the cost is a two-line diff after an intentional
model switch, not continuous noise.

**The card's stated top risk has inverted.** It warned that re-tracking would "bake in
`model: sonnet` as everyone's default". The value that gets committed today is `opus[1m]` at
`xhigh` — the correct default for a fresh clone. Re-check this before committing rather than
trusting this sentence.

What *does* still hold from the original: the ten orca entries are all the same one-line command
and are `$HOME`-substitutable, so `core-conduct`'s no-absolute-paths rule is satisfied inside the
tracked file with no second file involved. Note the paths sit inside **single** quotes today, which
suppress expansion — they must become double quotes.

`~/.claude/.claude/settings.local.json` — project scope, already gitignored by `.gitignore:78`
(`/.claude/`), already holding `permissions.allow` grants and `"outputStyle": "Concise"` — is the
real local-settings file and is left exactly as it is. It is out of scope here because it applies
only to sessions whose project root is `~/.claude`; every worktree is its own root with its own
copy, and sessions in other repositories read none of them.

## ⚠️ The open question that gates the whole design

**Do `hooks` in `settings.local.json` MERGE with `settings.json`, or REPLACE the key?** The split
above puts guard hooks in one file and orca hooks in the other. If the local file replaces rather
than merges, that silently disables every repo guard — the exact failure this card exists to
prevent, caused by the fix.

**This must be answered by experiment before task 3, never by assumption or by reading docs.**
Design the probe so it can fail: register a hook in each file, trigger both, and confirm *both* fire.
If it replaces, fall back to keeping all hooks in the tracked file and accepting the orca absolute
paths as a separate problem (or templating them via `$HOME`).

### Task 1 outcome — answered, and it is a STOP

Run 2026-08-21 against `claude 2.1.238` (`~/.local/share/claude/versions/2.1.238`) on branch
`chore/settings-split` @ `fcbcba6`. Probe: give each settings file a `SessionStart` hook that
appends a distinct marker to a log, point `CLAUDE_CONFIG_DIR` at a scratch dir, run
`claude -p … --allow-dangerously-skip-permissions`, then read the log. `SessionStart` hooks fire
*before* the login check, so every case below reports `claude exit 1 · Not logged in` and the
marker log is still the full answer — the sandbox config dir has no credentials of its own
(Keychain services are `Claude Code-credentials-<hash-of-config-dir>`).

| case | settings files present | markers that fired |
|---|---|---|
| A | user `settings.json` | `TRACKED` |
| B | user `settings.local.json` | **(none)** |
| C | user `settings.json` + user `settings.local.json` | `TRACKED` |
| D | user `settings.json` + **malformed** user `settings.local.json` | `TRACKED`, and **no parse error** |
| E | user `settings.json` + project `<cwd>/.claude/settings.local.json` | `TRACKED` + `LOCAL` |
| F | E plus project `<cwd>/.claude/settings.json` | `TRACKED` + `PROJECT` + `LOCAL` |
| G | **real `~/.claude`**: `~/.claude/settings.local.json` + project `<cwd>/.claude/settings.local.json` | `LOCALPROJ` only |

Case G exists because cases B and D had a confound: `CLAUDE_CONFIG_DIR` demonstrably relocates
`settings.json` (case A), but if the *local* user-scope file were resolved from a literal
`~/.claude` the sandbox would have been blind and would have looked exactly like "not supported".
G runs against the real config dir with no sandbox — fully authenticated, `exit 0`, replied
`DONE` — with a marker hook in `~/.claude/settings.local.json` and in
`<cwd>/.claude/settings.local.json` at the same time. Only the project-scope one fired. The
user-scope file was created for that one run and removed in an `EXIT` trap; the run's own cleanup
check confirms it is gone.

**Two findings, and the second one kills the design in the table above.**

1. **`hooks` MERGE — they never replace.** Case F fired three hooks for one event from three
   different scopes. The feared failure mode does not exist.
2. **There is no user-scope `settings.local.json`.** Case G is the load-bearing one: against the
   real `~/.claude`, with a marker hook in `~/.claude/settings.local.json` and one in
   `<cwd>/.claude/settings.local.json` simultaneously, only the project-scope hook fired. Cases B
   and E say the same thing in the sandbox, and E is what makes B's silence mean something — the
   probe is demonstrably *able* to see a `settings.local.json` hook. Case D adds that the file is
   never even opened: a deliberately malformed `~/.claude/settings.local.json` produces no warning
   at all. The binary agrees — its settings scopes are `userSettings` / `projectSettings` /
   `localSettings` / `policySettings`, and every path string for the local scope is
   `.claude/settings.local.json`, i.e. project-relative. The card's own supporting evidence
   (`strings … | grep -c settings.local.json` → 103) counted a **project**-scope feature and read
   it as a user-scope one.

   `~/.claude/settings.json` *is* the user-scope settings file — that part of the card is right.
   It is the `.local.json` variant specifically that has no user-scope member. A fifth source
   exists, `claude --settings <file-or-json>`, but it does not help: `/model` still writes back to
   `~/.claude/settings.json`, and the flag only reaches sessions launched through the shell alias,
   not desktop/IDE/cmux-spawned ones.

So `~/.claude/settings.local.json` is not a quieter place to put `model`/`effortLevel` — it is
`/dev/null`. Moving them there would silently drop the model default, the effort level, the theme
and all ten orca hooks. **Stopped before task 3, per this card's own instruction.**

What survives the finding: the orca hooks' 10 hardcoded `/Users/marksuyat` paths are all the same
one-line command and are `$HOME`-substitutable, so the "no absolute paths in committed files" rule
can be satisfied inside the tracked file, with no second file involved.

**Decided 2026-08-21 by the user: accept the churn, no split.** See **Fix (revised)**. Two further
experiments backed the decision:

*The model demo* — the card's plan, run end to end. Same key, same value, two locations, one
`claude -p … --output-format json` per row:

| `model` set in | model the session actually used |
|---|---|
| nothing (baseline, `settings.json` says `opus[1m]`) | `claude-opus-5[1m]` |
| `~/.claude/settings.local.json` = `claude-haiku-4-5-20251001` | `claude-opus-5[1m]` — **ignored** |
| `<cwd>/.claude/settings.local.json` = `claude-haiku-4-5-20251001` | `claude-haiku-4-5-20251001` |

*The clean-filter test* — a throwaway repo, `settings.json filter=prefs`, clean script deleting
`model`/`effortLevel`. Storage and status behave: the committed blob is `{"hooks": "GUARDS"}` and
`git status` is clean with the keys still in the working copy. Branch switches that leave
`settings.json` alone are harmless. But a branch that *changes* `settings.json` — the whole point
of tracking it — wipes the local keys on both `git checkout` and `git merge`, because a clean
filter with no smudge half materialises the stored blob over the working file. Reproduce with
`.probe-tmp/filter-test2.sh`.

### The probe, reproduced

```bash
CFG=$(mktemp -d); CWD=$(mktemp -d); LOG=$(mktemp)
cp ~/.claude.json "$CFG/.claude.json"          # otherwise: "Not logged in" even earlier
hook () { printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo %s >> %s"}]}]}}\n' "$2" "$LOG" > "$1"; }
hook "$CFG/settings.json"               TRACKED
hook "$CWD/.claude/settings.local.json" LOCAL    # mkdir -p "$CWD/.claude" first
cd "$CWD" && CLAUDE_CONFIG_DIR="$CFG" claude -p 'reply DONE' --allow-dangerously-skip-permissions
sort "$LOG" | uniq -c                            # both markers => hooks merge across scopes
```

Swap which files `hook` writes to reproduce cases A–F. The control that matters is running it once
with the marker in `$CFG/settings.local.json` (silent) and once in
`$CWD/.claude/settings.local.json` (fires).

For case G, drop `CLAUDE_CONFIG_DIR` and the `.claude.json` copy, write the two markers to
`~/.claude/settings.local.json` and `$CWD/.claude/settings.local.json`, and guard the real file
with `[ -e ] && exit 1` on the way in and an `EXIT` trap on the way out.

## `.gitignore` changes

- **Remove** line 23 `settings.json`.
- ~~**Add** `settings.local.json`.~~ Dropped with the split — there is no user-scope file of that
  name to ignore, and the project-scope one at `.claude/settings.local.json` is already covered by
  `.gitignore:78` (`/.claude/`).
- **Keep** `settings.json.bak` (line 20) and `stats-cache.json` — a genuine runtime cache, correctly
  untracked by `9cc792f`; this card does not re-track it.

## Tasks

- [x] 0. Branch `chore/settings-split` + worktree. **Only after `gate confirmed`.**
      Worktree `.claude/worktrees/settings-split`; `origin/main` merged in at `fcbcba6` (the branch
      had been cut from a local `main` that was 27 commits behind).
- [x] 1. **Answer the merge-vs-replace question by experiment.** Record the probe and its output in
      this card. If it replaces, stop and re-plan — do not proceed to task 3.
      → Hooks merge; but the destination file does not exist at user scope. **Stopped.** See
      "Task 1 outcome" above.
- [x] 2. **Red:** confirm the three registration tests fail for the stated reason (absent file), not
      some other one. They are the acceptance criteria; watch them fail first.
      Run on `fcbcba6`, counts read off the runs, not off this card:
      `feature-sync-guard` **29 passed, 1 failed**; `memsearch-nudge` **26/27**;
      `slim-session-start` (under `env -u CLAUDE_PANE_AGENT`) **28/29**. All three name the same
      cause — `settings.json` not found in the worktree — and each suite's paired
      "registration check can fail" case still passes, so the assertions are not stuck-green.
Tasks 3–8 were rewritten on 2026-08-21 when the split was dropped. The originals assumed a second
file; they are replaced, not merely reworded.

- [x] 3. Bring the live `~/.claude/settings.json` into the worktree unchanged, then rewrite the ten
      orca entries from `'/Users/marksuyat/.orca/…'` to `"$HOME/.orca/…"`. **Double quotes** — the
      current single quotes suppress expansion. Nothing else about the file changes; `model` and
      `effortLevel` stay.
      Copied byte-identical first (`sha256 8b633a53…` on both). The substitution replaced **40**
      occurrences, not 10 — the path appears four times per entry (`-f`, `-r`, `-x`, then the
      invocation). A key-by-key comparison of the parsed JSON against the live file reports zero
      keys added, zero removed, and exactly 10 values changed — the 10 command strings, which now
      collapse to **one** distinct string.
- [x] 4. Confirm the rewritten orca hook still fires before trusting the substitution. A silent
      no-op looks identical to a hook that was never registered.
      Run through Claude Code's own hook runner, not `sh -c`: the rewritten guard reported
      `ORCA-REACHED`, a control hook of identical shape pointing at a non-existent file reported
      `CONTROL-MISSED`, and a third printed `HOME-IS=/Users/marksuyat`. The control is what makes
      the first result mean something. Reproduce: `.probe-tmp/home-expand.sh`.
- [x] 5. `.gitignore`: remove line 23 `settings.json`, then `git add settings.json`. Confirm which
      order actually works rather than guessing — `git add -f` while still ignored is the fallback.
      Plain `git add` sufficed once the line was gone (`git check-ignore -v settings.json` → exit 1,
      no match). `-f` was not needed. The removed line is replaced by a comment saying why the file
      is tracked, so the next reader does not re-ignore it.
- [x] 6. **Assert no absolute path survives** in the tracked file:
      `command grep -c '/Users/' settings.json` → 0. Use `command grep`; the bare `grep` here is
      ugrep with `--ignore-files` and honours `.gitignore`.
      **0**, measured against the staged blob (`git show :settings.json | command grep -c '/Users/'`),
      not the working file.
- [x] 7. Confirm the committed `model` is the one a fresh clone should boot on — expected
      `opus[1m]` / `xhigh`. Read it out of the staged blob, not out of this card.
      Staged blob: `model = opus[1m]`, `effortLevel = xhigh`, 12 hook events registered.
- [x] 8. Three suites green; then the full suite — expect **817/0**. Record counts run, not read.
      Three suites: `feature-sync-guard` **30/0** (was 29/1), `memsearch-nudge` **27/27** (was
      26/27), `slim-session-start` **29/29** (was 28/29). Exactly +3 pass / −3 fail.
      **The 817 figure could not be reproduced and should not be quoted.** There is no committed
      full-suite runner; 817 was summed by hand before the 27 merged commits landed. Measured here
      with a runner that prints every file it ran (`.probe-tmp/run-all-tests.sh`):
      - 19 `*.test.sh` suites — **1198 passed, 0 failed**
      - 5 `hooks/lib/*.test.py` — **319 passed, 0 failed**
      - `memsearch` pytest, repo default config — **104 passed, 0 failed, 23 deselected**
        (`pyproject.toml:26` sets `addopts = "-m 'not golden and not measurement'"`)
      - those 23 run explicitly — **2 passed, 21 failed**, every failure
        `index database is at schema version 0, this build needs …`. **Pre-existing, not this
        branch**: the identical `21 failed, 2 passed` reproduces in the `rule-surface-trim`
        worktree, which carries the same post-PR-#60 memsearch code and none of these changes.
        It is PR #60's documented post-merge migration pass.
- [x] 9. Fix `SETUP.md:28` (claims the file is tracked — true again once this lands) and
      `README.md:42` ("Hooks, enabled plugins, and TUI preferences" — now accurate as written,
      re-read before editing).
      Both sentences were already true once this lands, so both were extended rather than
      corrected: `SETUP.md` now says *why* the file is tracked and carries the move-aside step;
      `README.md` says the same in one row and names the `/model` churn.
- [x] 10. ADR under `docs/decisions/`: why the whole file is tracked rather than split, the three
      experiments that ruled out the alternatives, and that `9cc792f` solved a real churn problem
      by disabling the guards. Record the checkout/merge hazard so the clean filter is not
      re-proposed later.
      `docs/decisions/0032-track-settings-json-whole.md`. Number checked free against `origin/main`
      and against every ref (`git log --all --diff-filter=A -- 'docs/decisions/0032*'` → empty),
      not against the local `main`, which is 27 commits behind.
- [x] 11. Rollout note: a checkout that pulls this commit will refuse to overwrite an existing
      untracked `~/.claude/settings.json` unless the bytes match exactly, and the `$HOME` rewrite
      guarantees they will not. Document the move-aside step.
      In `SETUP.md` § 3, with the `diff` reconciliation line.
- [ ] 12. Observability judge, then draft PR.

## Risks

- ~~**Re-tracking commits whatever is on this machine today.** Task 3 must strip the machine-specific
  keys *before* task 4, or the first commit bakes in `model: sonnet` as everyone's default.~~
  **Inverted.** There is nowhere to strip them to, and the value on this machine is now `opus[1m]`
  / `xhigh` — the right default for a fresh clone. Task 7 re-reads it from the staged blob rather
  than trusting that. The residual risk is the opposite one: a future re-track done while a
  throwaway model is selected would commit *that*.
- **A pull will refuse to land this commit** on any checkout holding an untracked
  `~/.claude/settings.json` whose bytes differ from the committed blob — which the `$HOME` rewrite
  guarantees. Task 11 documents the move-aside.
- ~~**A stale `settings.local.json` on another machine** could shadow a future tracked change.~~
  Moot with the split dropped — no such file is created.
- **The next `/model` on any machine dirties the tracked file.** Accepted, and bounded: only a
  deliberate switch writes it (measured — untouched 12:31 → 13:49 across ~8 sessions). The failure
  mode to watch is a stray `git commit -a` sweeping someone's model choice into the repo.
- This card touches the file that configures the hooks that guard the repo. A mistake disables the
  guards silently — which is why task 1 is an experiment, task 2 is a red test, and task 4 fires
  the rewritten orca hook instead of eyeballing the substitution.
