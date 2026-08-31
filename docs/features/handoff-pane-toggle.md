---
phase: implementation
model_tier: low
branch: handoff-pane-toggle
---

# Handoff pane toggle

## Spec

Bounded task, approved in chat (no separate spec doc — brainstorming skill's
bounded path). `hooks/context-handoff-watch.sh` always opens a side pane
(`dispatch-pane-agent.sh handoff`) once per session when context crosses its
model-dependent threshold. Add an opt-out: `HANDOFF_PANE_MODE` env var
(`settings.json` `env`, same mechanism as `WORKTREE_GUARD_MODE`). `off`
disables the pane dispatch; unset or any other value keeps today's behavior.
Either way the `additionalContext` freshness-checkpoint nudge still fires —
only the pane-dispatch call and the trailing sentence of the nudge change.

## Tasks

- [x] Gate the `"$DISPATCH" handoff --cwd "$cwd"` call in
      `hooks/context-handoff-watch.sh` on `HANDOFF_PANE_MODE != off`; when off,
      skip dispatch and use a disabled-mode `pane_note`.
- [x] Extend `hooks/context-handoff-watch.test.sh` with `HANDOFF_PANE_MODE=off`
      (dispatch never called, nudge still fires, disabled wording present, no
      pane-ready/failure wording) and an explicit `on`/mistyped-value case
      confirming today's behavior is unchanged.
      - `dispatch-calls` already exists by that point in the suite from earlier
        cases, so "not called" is asserted by diffing against a pre-call
        snapshot, not by asserting the file's absence.
- [x] Document the toggle and its default in `rules/gates.md`'s
      "Context-handoff watch" bullet.
- [x] Run the test suite, verify, commit.

## Verification

`bash hooks/context-handoff-watch.test.sh` — 43 passed, 0 failed. `shellcheck`
clean on both `hooks/context-handoff-watch.sh` and its test.
