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

## `.gitignore` changes

- **Remove** line 23 `settings.json`.
- **Add** `settings.local.json`.
- **Keep** `settings.json.bak` (line 20) and `stats-cache.json` — a genuine runtime cache, correctly
  untracked by `9cc792f`; this card does not re-track it.

## Tasks

- [ ] 0. Branch `chore/settings-split` + worktree. **Only after `gate confirmed`.**
- [ ] 1. **Answer the merge-vs-replace question by experiment.** Record the probe and its output in
      this card. If it replaces, stop and re-plan — do not proceed to task 3.
- [ ] 2. **Red:** confirm the three registration tests fail for the stated reason (absent file), not
      some other one. They are the acceptance criteria; watch them fail first.
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
