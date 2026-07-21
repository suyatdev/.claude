# feature/pane-orchestration — branch log

Implements `docs/superpowers/specs/2026-07-20-pane-orchestration-design.md`
(approved as-is 2026-07-21; compliance PASS r2, obs risk=low at 468387a).
Plan: `docs/superpowers/plans/2026-07-21-pane-orchestration.md`. ADR 0007.

Three obs r2 advisories folded into the implementation (not the spec):
watcher fired-flag-first ordering; CLAUDE_CODE_SESSION_ID as dispatcher
session-id source + guard-side divergence warning; ADR 0007 "four"→"six".

Planning-time findings (2026-07-21):
- cmux `new-split` verified live from a non-TTY process: lands in the calling
  workspace (env-targeted), prints `OK surface:N workspace:M`.
- `CLAUDE_CODE_SESSION_ID` env var confirmed present and equal to the
  scratchpad path's session segment.
- jq is `/usr/bin/jq` (1.7.1), not Homebrew.
- SPEC ADDITION (needs user eyes at review): pane invocations pass
  `--dangerously-skip-permissions` — matches the machine-wide posture (shell
  alias + cmux launch argv); without it headless panes auto-deny tool calls.
  Hooks/guards still fire.
- Stale-state housekeeping decision: dispatcher deletes `panes/state` entries
  older than 7 days on every invocation.

## Progress

- Task 2: toolchain verified (shellcheck 0.11.0); pane-echo fixture; --agent spike PASSED headless.
- Task 3: terminal-detect.sh (9/9).
- Task 4: adapter layer, 24/24 dry-run.
