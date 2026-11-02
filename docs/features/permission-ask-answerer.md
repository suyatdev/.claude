---
phase: planning
model_tier: low
branch: none
---

# Who answered the two unexplained permission asks — a supervised experiment

Planned 2026-10-16 on `docs/guard-followups`, cut from `origin/main` @ `f83e490`. Follow-up (1) of
`docs/features/dependency-vetting-guard.md` (the parent card, phase `review`). Split out of
`docs/features/dependency-guard-yarn-workspaces.md` (where it was "Part B") on 2026-10-16 at Mark's
direction, so the yarn fix is not held up by an experiment that needs him at the keyboard. Its
requirement numbers R9/R10 are kept from that card so the judges' round-1–3 verdicts still map.
No code is written; the deliverable is a recorded result and, possibly, one Known-gaps row in the
parent card. Nothing is run until Mark types `gate confirmed` and sets aside ~30–50 minutes.

## Why (moved from the yarn card, 2026-10-16)

**Part B — two asks resolved with no recorded yes.** The parent card's Verification
(`dependency-vetting-guard.md:1395-1420`) records two `ask` decisions in `bypassPermissions` mode
that went through without a yes from Mark on record, and names two untested suspects: bypass mode
answering the ask itself, and `~/.orca/agent-hooks/claude-hook.sh` on `PermissionRequest`.
A read-only survey on 2026-10-16 found evidence against both (below) and two suspects the card does
not name. The cause is still unknown, so the parent card's wording ("cause unproven") stays true;
this card settles it by experiment.

## Evidence
Part B (read-only):
- The Orca hook posts the payload to the Orca app, discards the reply (`>/dev/null`), prints
  nothing and always exits 0, so it cannot return a decision. The session's own hook summary
  timed it at 17 ms.
- Both unexplained asks waited before running: 9 min 48 s and 30 s (npm itself took ~250 ms).
  cmux logged "Claude needs your permission" about 6 s after each ask, so a prompt was shown.
- Not yet considered by the parent card: cmux registers its own `PermissionRequest` hook ("cmux
  hooks feed"), and the session had a claude.ai remote-control link, which can answer a prompt
  from another device. Mark answering without noticing is also possible.
- Added 2026-10-16 (read by the round-3 judges, re-read by the main session): cmux's launcher
  `/Applications/cmux.app/Contents/Resources/bin/cmux-claude-wrapper:932-936` says its
  `PermissionRequest` hook has a 125 s timeout and "under bypassPermissions it does not fire, and
  PreToolUse is the needs-input fallback". So cmux also injects a `PreToolUse` hook, whose effect
  on an `ask` is not known. The wrapper merges any user `--settings` into its own single
  `--settings` (`:945-956`), so a throwaway `--settings` file still loads cmux's hooks inside cmux.
  This makes cmux's `PermissionRequest` hook an unlikely answerer of the 9 min 48 s ask, but the
  experiment still tests all cmux hooks together (run 3).
- Added 2026-10-29: an informal supervised run recorded in the parent card
  (`dependency-vetting-guard.md`, the entry after `:1420`) showed that in bypass mode an `ask`
  shows a prompt, waits for it, and a No stops the command. Suspect 1 (bypass mode answering by
  itself) did not happen in that session. cmux's hooks and the remote-control link were not
  isolated, so this card's question about the two original asks is still open.
- Versions when planned: Claude Code 2.1.301, cmux 0.64.22, Orca 1.4.146
  (`/Applications/Orca.app/Contents/Info.plist` `CFBundleShortVersionString`).

## Requirements — Part B

R9. Run the experiment below with Mark present. In every run, Mark keeps his hands off the
keyboard, mouse and phone for the whole **watch window: 12 minutes** (longer than the longest
observed hold, 9 min 48 s). Record per run, before it starts: `claude --version`, the cmux
version, the Orca version, the permission mode shown by the session, terminal, the live hook list
(the output of `/hooks` in that session) and whether remote control is connected. Record when it
ends: whether a prompt appeared, how long the command waited, and which R10 outcome it was. Any
Known-gaps row this produces names all three versions.

R9a. **Mode.** Every run is started with `--permission-mode bypassPermissions` (Mark's settings
default to normal mode and only *allow* bypass, so the mode must be set explicitly). A run whose
recorded mode is not bypass is invalid: it is repeated, not counted.

Experiment (no real install happens): a throwaway settings file passed with `--settings`, in a
`mktemp -d` directory, registering a PreToolUse hook that returns `ask` only for
`echo ASKTEST-<nonce>`. Each run removes exactly one more suspect than the one before, in this
fixed order:

| Run | Setup | Suspect removed |
|---|---|---|
| 1 | cmux, remote control connected, user settings loaded (Orca hook present) — the original setup | none |
| 2 | as run 1, remote control disconnected | the claude.ai remote link |
| 3 | as run 2, in plain Terminal.app instead of cmux | every cmux-injected hook (its `PermissionRequest` hook and its `PreToolUse` fallback) |
| 4 | as run 3, started with `--setting-sources` set to exclude `user` (flag present in 2.1.301's `--help`) | all user-level settings — the Orca hook is the only permission hook among them (checked 2026-10-16); `/hooks` must confirm it is absent |

R10. Each run ends in exactly one outcome:

| Outcome in a run | Consequence |
|---|---|
| A. No prompt appears; the command runs at once | If this is run 1: bypass mode itself skips the ask — stop; Known-gaps row in the parent card naming the mode and versions. If this is run 2, 3 or 4: the prompt appeared in run 1, so the cause is the change that run made, not the mode — stop, record that, and bring it to Mark before writing any Known-gaps row. |
| B. A prompt appears and is still pending when the window ends | Mark answers **no**. If this is run 1: stop — nothing automatic answers in the original setup, so later runs (which only remove suspects) cannot either; record "not reproduced; who answered on 2026-10-16 is still unknown". If this is run 2, 3 or 4: the suspect that run removed is the likely answerer — repeat the previous run once (it must again be answered automatically) to confirm, then stop and add a Known-gaps row naming it and the versions. If the repeat does not reproduce, record both runs and stop with "not settled". |
| C. A prompt appears and is answered automatically inside the window, hands off — either the command runs (yes) or the prompt closes and the command does not run (no) | Something automatic answered; record which answer. Go to the next run. If this is run 4: every named suspect is removed and the ask is still answered automatically — record "answered automatically by an unidentified component; all named suspects excluded", add a Known-gaps row saying exactly that with the versions and run 4's `/hooks` list, and stop. |

Never record "Mark answered" for any run: nothing here can prove it. When the experiment ends in
"not reproduced" or "not settled", there is no Known-gaps row and the parent card's "cause
unproven" wording stays. Passing `--settings` or `--setting-sources` may change which hooks load;
that is why every run records `/hooks`, and a run whose `/hooks` list does not match its row in the
table above is invalid and is repeated, not counted. A single run is a lead, not proof — which is
why outcome B confirms by repeating once.

## Tasks

- [ ] 0. Re-check on the day: the three versions, `claude --help` still lists
  `--permission-mode` and `--setting-sources`, and `~/.claude/settings.json` still registers no
  permission hook other than Orca's. A difference is a finding: bring it to Mark before running.
- [ ] 1. Build the throwaway settings file and `ask` hook in a `mktemp -d` directory; prove it in a
  normal-mode session first (the prompt must appear for `echo ASKTEST-<nonce>` and not for
  `echo other`). Nothing is committed.
- [ ] 2. Runs 1–4 with Mark (R9, R9a, R10), stopping as R10 says.
- [ ] 3. Record the per-run table and the conclusion in a `## Verification` section here; if R10
  calls for it, add the Known-gaps row to the parent card.
- [ ] 4. Observability judge; docs-only PR.
