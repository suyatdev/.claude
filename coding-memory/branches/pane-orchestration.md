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
- Task 9: 75k watcher, flag-first ordering, 13/13. Test transcribed verbatim, no test defects. Deviation (comments-only, repo convention per Tasks 5/6/8): file-level `# shellcheck disable=SC2016,SC2034` on the test (single-quoted deferred-eval `chk` assertions; `out` read only inside those strings) and one inline `# shellcheck disable=SC2016` in the hook (single-quoted jq program's `\($fill)` interpolation) to meet the brief's shellcheck-clean bar.
- Task 8: pane-dispatch-guard, 13/13. Deviation (impl-only, repo convention): 2 inline `# shellcheck disable=SC2016` on the two deny-message printf lines whose single-quoted format strings show `"$HOME"` literally to the model (expanding it would be wrong); brief code transcribed verbatim otherwise, directives added to meet the brief's shellcheck-clean bar (same pattern as Tasks 5/6). Test file transcribed verbatim, no test defects.
- Task 10: pane early-exit in 5 handoff hooks. Identical `CLAUDE_PANE_AGENT` guard inserted after `set -euo pipefail`, before first state-touching statement, in all 5. Verify: 5 ok early-exits + exit=0 no-regression. shellcheck: my insertion clean; proactive-handoff's 5 pre-existing `cleanup_state` findings (HEAD==WT) left untouched (not a drive-by task).
- Task 11: hooks wired, skill + gates + catalogs.
- Task 12: verification sweep — all suites green, shellcheck as expected, live cmux smoke PASSED.

## Task 12 — verification sweep (2026-07-21)

**Test suites (8, all `0 failed`, 117 assertions total):**

| suite | result |
| --- | --- |
| panes/terminal-detect.test.sh | 9 passed, 0 failed |
| panes/adapters.test.sh | 24 passed, 0 failed |
| panes/run-pane-agent.test.sh | 6 passed, 0 failed |
| panes/dispatch-pane-agent.test.sh | 30 passed, 0 failed |
| hooks/pane-dispatch-guard.test.sh | 13 passed, 0 failed |
| hooks/context-handoff-watch.test.sh | 13 passed, 0 failed |
| hooks/judge-guard.test.sh (regression) | 17 passed, 0 failed |
| hooks/memsearch-nudge.test.sh (regression) | 5 passed, 0 failed |

Both pre-existing regression suites still green — no collateral damage.

**shellcheck (`shellcheck -x panes/*.sh panes/adapters/*.sh hooks/pane-dispatch-guard.sh hooks/context-handoff-watch.sh hooks/handoff/*.sh`):**
Clean on every branch-authored/branch-touched script. The only findings are 5 pre-existing
ones in `hooks/handoff/proactive-handoff.sh` `cleanup_state()` (lines 122/129/131/138 SC2016 info
on single-quoted `sed`/`grep` regex programs, line 125 SC2034 `remove_count` unused). Confirmed
pre-existing: `git diff main -- hooks/handoff/proactive-handoff.sh` is only the 4-line
`CLAUDE_PANE_AGENT` guard at line 15 (Task 10); those `cleanup_state` lines are byte-identical to
`main`. Left unfixed per root-cause discipline — not a drive-by fix of vendored code (already noted
at Task 10).

**Live cmux smoke (acceptance scenario 1, real):**
- Dispatch: `panes/dispatch-pane-agent.sh dispatch pane-echo --prompt-file /tmp/pane-smoke-prompt.md --cwd "$HOME/.claude"` → exit 0, printed `TERMINAL: cmux`, `PANE_REF: surface:40`, `RESULT_FILE: .../scratchpad/pane-results/pane-echo-1784617055.md`.
- Pane opened in the **current** workspace (workspace:5, this session's). `cmux tree` shows
  `surface:40 [terminal] "pane: pane-echo" ... tty=ttys015` — a live interactive shell; the
  in-pane banner is run-pane-agent's `=== pane agent: pane-echo ===`.
- Wait: `panes/dispatch-pane-agent.sh wait --result-file <rf> --timeout 300` → exit 0; printed
  `PONG` then `PANE_RESULT: DONE`.
- Result file on disk: body `PONG`, final line exactly `PANE_RESULT: DONE\n` (od-verified). New run
  dir `1784617055-87037-30548` mode 700 with `launch.sh` (700) + `prompt.md`; launcher ends
  `exec /bin/zsh -i`, so the pane stays open for inspection.
- Timing: dispatch 02:57:35, result present by first `wait` poll at 02:57:45 (haiku pane-echo, far
  under the 300s timeout).

**SPEC ADDITION — flagged again for user review:** pane invocations pass
`--dangerously-skip-permissions` (`run-pane-agent.sh`). It matches the machine-wide posture (shell
alias `claude --allow-dangerously-skip-permissions` + cmux launch argv) and is required — without it
a headless pane auto-denies non-allowlisted tool calls and the agent dies mid-task. It skips
permission prompts, not hooks/guards (recursion guard `CLAUDE_PANE_AGENT` still exported; the smoke
run confirmed hooks/CLAUDE.md still load since `--bare` is deliberately not used). **Please confirm
this posture during review.**

**Live guard/watcher verification deferred to first NEW session after merge:** the
`pane-dispatch-guard` (PreToolUse) and `context-handoff-watch` (PreCompact/context) hooks load at
session start from `settings.json`; this session began before the Task 11 wiring landed, so it
cannot exercise them live. Their unit suites pass (13/13 each). First live proof is the
post-merge observability-judge dispatch: from a fresh session the guard should, for the first time
live, deny the in-process judge and route it through a pane — that dispatch is the guard's live
acceptance test. (Note: the 75k watcher already fired once mid-session after the wiring went live —
flag `panes/state/handoff-fired-93770c21-…` + run dir `1784616541-80835-24061` + the live
`surface:39 "handoff: press Enter"` pane — designed once-per-session behavior, not stale state;
left in place.)

## Final-review fix wave (2026-07-21)

Whole-branch review at HEAD 747a715 — one wave, 5 findings, TDD RED→GREEN each: F1 (Important) unique default result path `$agent-$(date +%s)-$$-$RANDOM.md`; F2 (Important) guard honors the `adapter-failed-nosession` cooldown key (env-drift deny loop); F3 wait `|| sleep "$POLL_SECS"` instead of `|| true` (no hot-spin); F4 relative `--result-file` canonicalized to absolute at parse time; F5 watcher conditions the pane-ready additionalContext on the handoff dispatch's exit. Suites green: dispatcher 33, guard 14, watcher 19; regression sweep 9/24/6; shellcheck clean on all six touched files. Report: `.superpowers/sdd/task-12-report.md`.
- Final review fix wave ad5e59f re-reviewed: all 5 confirmed fixed, READY TO MERGE (2026-07-21).
