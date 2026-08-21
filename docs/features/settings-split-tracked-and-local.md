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

Split by *what the file is for*, not by convenience:

| Stays tracked in `settings.json` | Moves to gitignored `settings.local.json` |
|---|---|
| `permissions` | `model`, `effortLevel` — churn on every `/model` |
| `hooks` (the repo's own guards, all `$HOME`-relative) | the `.orca/agent-hooks/` entries — **10 hardcoded `/Users/marksuyat` paths**, which `core-conduct` forbids in committed files |
| `statusLine` (already `$HOME`-relative) | `theme`, `editorMode`, `tui`, `preferredNotifChannel`, `remoteControlAtStartup`, `inputNeededNotifEnabled`, `agentPushNotifEnabled`, `skipDangerousModePermissionPrompt` |
| `enabledPlugins` | |

`settings.local.json` is genuinely supported — verified against the installed binary
(`strings ~/.local/bin/claude | grep -c settings.local.json` → 103), not from memory.

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

What still needs a decision: `model` and `effortLevel` are written into `~/.claude/settings.json`
by `/model`, and there is no user-scope override file to divert them to. Either the churn is
accepted in the tracked file, or it is hidden with a `.gitattributes` clean filter that strips
those keys on the way into the index.

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
- **Add** `settings.local.json`.
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
- [ ] 3. Write `settings.local.json` with the machine-specific keys; strip them from `settings.json`.
      Verify `model`/`effortLevel` still take effect and the orca hooks still fire.
- [ ] 4. `.gitignore` per above. Re-track with `git add -f settings.json` (still ignored at that
      point) or after the ignore line is removed — confirm which, do not guess.
- [ ] 5. **Assert no absolute path survives** in the tracked file:
      `command grep -c '/Users/' settings.json` → 0. Use `command grep`; the bare `grep` here is
      ugrep with `--ignore-files` and honours `.gitignore`.
- [ ] 6. Three suites green; then the full suite — expect **817/0**. Record counts run, not read.
- [ ] 7. Fix `SETUP.md:28` and `README.md:42` (describes `settings.json` as "Hooks, enabled plugins,
      and TUI preferences" — TUI prefs move out).
- [ ] 8. ADR under `docs/decisions/`: why the wiring is tracked and the preferences are not, and
      that `9cc792f` solved a real churn problem the wrong way round.
- [ ] 9. Observability judge, then draft PR.

## Risks

- **Re-tracking commits whatever is on this machine today.** Task 3 must strip the machine-specific
  keys *before* task 4, or the first commit bakes in `model: sonnet` as everyone's default.
- **A stale `settings.local.json` on another machine** could shadow a future tracked change. Out of
  scope here; note it in the ADR.
- This card touches the file that configures the hooks that guard the repo. A mistake disables the
  guards silently — which is why task 1 is an experiment and task 2 is a red test.
