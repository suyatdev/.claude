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
- Task 5: runner + result contract, 6/6. Deviation: 2 `# shellcheck disable=SC2016` directives on deliberate single-quoted stub bodies (repo convention; meets brief's shellcheck-clean bar).
- Task 6: dispatcher dispatch+wait, conf, gitignore, 26/26. Applied the 2 user-ruled test corrections (dropped the mangled `$RF2`-before-assign line, keeping the correct `RF2=...`/write pair; `touch`ed the pre-existing result file so the exit-65 refusal path is exercised). Deviation: found + fixed a 3rd brief-test defect — the "sanitized title" assertion read `sed -n '1p'` (=`open_pane`, the subcommand) but the title is argv[2] since the dispatcher must pass `open_pane <title> <launcher>` to satisfy Task 4's adapter contract; corrected to `2p` (test-only, verifies real behavior). Deviation: file-level `# shellcheck disable=SC2015` (safe `[c] && ok || bad` harness — ok/bad always return 0), 2 inline SC1007 on deliberate `CMUX_PANEL_ID=` env-prefixes, 1 inline SC2015 in the dispatcher's `&& shift ||` line (repo convention; meets shellcheck-clean bar).
- Task 7: handoff wrapper + subcommand. handoff-wrapper.sh (press-Enter then exec claude, no CLAUDE_PANE_AGENT); dispatcher handoff arm reuses Task 6 launcher/open_pane machinery, 30/30. Two test-only plan deviations (both brief defects): repeated the `1p`→`2p` title bug from Task 6 (title is adapter argv[2]); and `find -newer adapter-args | head -n1` was flaky (~75% fail) since earlier r2/r3/r4 dispatches also leave newer launchers — fixed with a fresh `handoff-marker` touched just before the handoff dispatch so the handoff launcher is the only newer match. shellcheck clean.
