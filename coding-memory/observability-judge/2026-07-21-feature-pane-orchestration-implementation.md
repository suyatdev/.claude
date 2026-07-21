# Observability Judge Verdict — pane orchestration (implementation, gating)

- **Repo:** `.claude` · **Branch:** `feature/pane-orchestration`
- **HEAD:** `5c846b21145518b65495cea5ed0138c5c5cc2ff0`
- **Stage:** implementation (gates the PR)
- **Base:** `main` (merge-base `c1e1b84`; 21 commits, 3,828 insertions across 40 files)
- **Artifacts:** `panes/` (dispatcher, runner, 4 adapters, detect ladder, redirect conf),
  `hooks/pane-dispatch-guard.sh`, `hooks/context-handoff-watch.sh`, 4-line
  `CLAUDE_PANE_AGENT` early-exits in the five `hooks/handoff/` scripts,
  `skills/dispatching-pane-agents/SKILL.md`, `agents/pane-echo.md`, gate stubs, docs/memory.
- **Test command (run by me, this session):**
  `panes/adapters.test.sh` (24) + `panes/dispatch-pane-agent.test.sh` (33) +
  `panes/run-pane-agent.test.sh` (6) + `panes/terminal-detect.test.sh` (9) +
  `hooks/pane-dispatch-guard.test.sh` (14) + `hooks/context-handoff-watch.test.sh` (19)
  — **105 passed, 0 failed, exit 0**. `shellcheck` 0.11.0 clean on every pane script and
  both hooks. Live cmux smoke (real pane, PONG, DONE sentinel) recorded in `747a715`;
  not re-run here.
- **Risk:** low · **Confidence:** high

## What was changed

Substantial subagents — the two judges today, plan implementers by skill instruction — no
longer run invisibly inside the main Claude session. A PreToolUse hook denies their
in-process dispatch when a real terminal is available and points at a dispatcher script
that opens a visible pane (cmux/tmux/iTerm2/Terminal.app, picked by a priority ladder)
running the agent headlessly. The pane writes its answer to a uniquely-named result file
ending in an exact `DONE`/`FAILED` sentinel line; the main session polls that file with a
timeout. A second hook watches every tool call and, once per session at ≥75k context
tokens, nudges the freshness checkpoint and prepares a press-Enter handoff pane. Every
failure path degrades to today's behavior (fail open, per-session cooldown after an
adapter failure) — this is a momentum redirect, not a security boundary, and the code says
so. One unrelated rider: commit `79495c5` flips global `settings.json`
`defaultMode` from `acceptEdits` to `bypassPermissions` (user-requested 2026-07-21).

## Does it do what you wanted?

Yes. Every component the approved spec names exists, behaves as specified, and is tested:
the four-condition deny matrix, the injection boundary (adapters re-validate title
allowlist + launcher path themselves; `%q`-quoted mode-700 launchers), the atomic
result-file contract, the flag-first watcher ordering, and the `CLAUDE_PANE_AGENT`
recursion guards. Notably, **all five residual concerns from the round-2 architecting
verdict are closed in code with the finding cited at the fix site**: fired-flag-before-
transcript ordering, dual-source (stdin/env) session-id cooldown plumbing with divergence
warning, run-id uniqueness via atomic `mkdir` retry, run-dir/launcher 700 posture, and
stale-state cleanup. A final whole-branch review wave (`ad5e59f`) fixed five more
self-found defects (result-file uniqueness and canonicalization, nosession cooldown key,
wait sleep-on-fail, watcher overclaim) before the docs checkpoint. The one spec deviation
— `--dangerously-skip-permissions` in the runner — is user-approved, dated, and justified
in a comment (skips prompts, not hooks). This is a trajectory of verified decisions, not luck.

## What could go wrong / what I'm unsure about

No dimension fails. Concerns, largest first:

1. **`bypassPermissions` rides this branch** (`intent_drift`). The decisions summary calls
   `79495c5` "landed separately," but it is a commit *on this branch* and merges with this
   PR. It is user-requested and attributable, yet it is a machine-wide security-posture
   loosening unrelated to pane orchestration, documented only in a commit message — no
   ADR. Combined with the runner's `--dangerously-skip-permissions`, headless panes run
   with no permission prompts anywhere; the Tier-1 hooks are now the only guardrail.
2. **Only cmux is verified live** (`success_masking`). tmux/iTerm/Terminal adapters are
   green via `PANE_DRYRUN=1` assertions only. The iTerm AppleScript path needs a one-time
   macOS Automation grant; its first real failure writes the session cooldown and silently
   sends every later dispatch in-process for that session — green tests today could hide a
   permanently-degraded experience on non-cmux terminals.
3. **Shared `nosession` cooldown key** (accepted debt, documented): one adapter failure in
   an env-less session suppresses pane redirect for *all* env-less sessions until the flag
   ages out (7-day stale cleanup) or is hand-deleted.
4. **Every-tool-call watcher cost** (`regression`): until the 75k flag exists, each
   PostToolUse in every repo pays a jq parse + transcript tail + jq slurp. Bounded (200
   lines) and ordered cheapest-first, but it is a new global always-on hook.
5. **Handoff-trio edits are untested**: the five `CLAUDE_PANE_AGENT` early-exits are
   4-line, spec-anticipated, and shellcheck-clean, but no test covers those five scripts.

## What I'd double-check before merging

- Confirm you (the user) still want `defaultMode: bypassPermissions` merging via this PR
  rather than its own commit to a settings branch — and consider a one-paragraph ADR,
  since it changes the security posture of every future session.
- Open one real pane on a non-cmux terminal (tmux is cheapest) to convert one dryrun-only
  adapter into a live-verified one before relying on the fallback matrix.
- After merge, watch the first `adapter-failed-nosession` flag appearance — that is the
  accepted-debt path activating.
- Nothing else: tests, shellcheck, docs, ADR 0007, and the branch log are in order.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Every spec component built; sole deviation user-approved and dated |
| execution | pass | 105/105 tests re-run by judge; shellcheck clean; live cmux smoke on record |
| trajectory | pass | All 5 round-2 obs residuals + 5 self-found review findings closed, cited at fix sites |
| regression | concern | New global every-call PostToolUse hook; 5 handoff scripts edited untested; global settings flip |
| context_budget | pass | 1 catalog line + 2 gate stubs; procedure lives in an on-demand skill |
| traceability | pass | Exemplary — obs findings F1–F5/advisories referenced inline where fixed |
| success_masking | concern | 3 of 4 adapters dryrun-only; watcher swallows all failures by design (wording now honest) |
| intent_drift | concern | `bypassPermissions` settings flip is an unrelated, security-material rider (user-ratified) |
| checkpoint | pass | 21 focused commits, clean revert at merge-base, docs checkpoint last |
| audit_trail | pass | Branch log, ADR 0007, judge verdicts committed; bypassPermissions ADR gap noted above |

## Concerns (JSONL mirror)

1. bypassPermissions global flip (79495c5) rides this feature branch — user-requested but security-material, commit-message-only rationale, no ADR; with runner's --dangerously-skip-permissions, Tier-1 hooks are the only remaining guardrail in panes
2. only cmux adapter verified live; tmux/iTerm/Terminal green via PANE_DRYRUN only — first real iTerm failure cools down pane dispatch for the whole session silently
3. shared "nosession" cooldown key: one env-less adapter failure suppresses pane redirect for all env-less sessions for up to 7 days (accepted debt)
4. context-handoff-watch pays jq + transcript tail on every tool call in every repo until the per-session 75k flag exists
5. five hooks/handoff/ early-exit edits have no test coverage (4-line, spec-anticipated, shellcheck-clean)
