---
phase: review
model_tier: low
branch: feat/pane-agent-model-flag
pr: 71
---

# `--model` passthrough for pane dispatch

A paned agent currently runs whatever model the user's default happens to be. There is no way to say
"run this worker on Sonnet" — so the choice between *a separate visible session* and *a cheaper model*
is forced, and session 46 had to give up the pane to honour a Sonnet request.

This adds one optional flag end to end: `dispatch --model <M>` → launcher → `run-pane-agent.sh` →
`claude -p … --model <M>`. Nothing else changes; omitting it must behave exactly as today.

## Evidence this is the actual gap

Derivations, not pinned line numbers — re-run them, they move:

- `grep -n 'CLAUDE_BIN" -p' panes/run-pane-agent.sh` — the invocation is
  `"$CLAUDE_BIN" -p "$(cat "$prompt_file")" --agent "$agent_type" --output-format json
  --dangerously-skip-permissions`. No `--model`, so the pane inherits the user default.
- `grep -n 'run-pane-agent.sh' panes/dispatch-pane-agent.sh` — the generated launcher is two
  `printf` lines with **no environment prefix**, which is why the documented `PANE_CLAUDE_BIN`
  override cannot reach a pane. Verified in session 46: a wrapper pinning `--model sonnet` works when
  invoked directly (`modelUsage: claude-sonnet-5`) and does nothing for a pane.

## Design

**Pass the model as an optional 5th positional to the runner, not as an env prefix.** The launcher is
the injection boundary and every argument crossing it is already `%q`-quoted; adding a positional
keeps that boundary identical in shape. An `ENV=v bash …` prefix would introduce a second, differently
-quoted channel for no benefit, and `PANE_ARGS_OUT` — the existing test seam that captures the
runner's argv — already covers the positional path.

- `dispatch-pane-agent.sh`, `dispatch` verb: accept `--model <M>` alongside `--prompt-file`/
  `--cwd`/`--role`. Validate against `^[A-Za-z0-9._:\[\]-]{1,64}$` and `die` on a mismatch, matching
  how `--role` and `AGENT_TYPE_RE` already fail fast on caller bugs. Emit the extra `%q` argument
  **only when non-empty**, so an unflagged dispatch produces a byte-identical launcher to today's.
- `run-pane-agent.sh`: read `model="${5:-}"`. The existing 4-arg validation stays untouched, so every
  current caller — including the handoff launcher, which is a separate code path — keeps working.
  When `model` is non-empty, append `--model "$model"` to the `claude` call; when empty, the argv must
  be byte-identical to today's.
- Validation lives in the **dispatcher**, not the runner: the dispatcher is where a human-supplied
  flag enters, and the runner already trusts its `%q`-quoted argv.

## Acceptance criteria

1. **Given** a dispatch with `--model sonnet`, **then** the runner's captured argv contains
   `--model sonnet` (assert via `PANE_ARGS_OUT`).
2. **Given** a dispatch with no `--model`, **then** the captured argv contains no `--model` token at
   all — not an empty one. This is the regression that matters; assert absence explicitly.
3. **Given** `--model "a b"` or any value failing the regex, **then** `dispatch` exits non-zero with a
   usage error and **no pane is opened** (fail before the adapter call, like `--role`).
4. **Given** `run-pane-agent.sh` called with exactly 4 positionals (today's contract), **then**
   behaviour is unchanged and no `--model` is passed.
5. The dispatcher's own usage string names `--model`.

## Tasks

- [x] 1 — `panes/run-pane-agent.sh`: optional 5th positional, conditional `--model` on the `claude`
      invocation. Do not touch the 4-arg validation or the usage string's required args.
- [x] 2 — `panes/run-pane-agent.test.sh`: add cases 1, 2 and 4 above using the existing
      `PANE_ARGS_OUT` + `PANE_CLAUDE_BIN` stub seam.
- [x] 3 — `panes/dispatch-pane-agent.sh`: `--model` parsing, regex validation, usage string, and the
      conditional extra `%q` in the launcher.
      - The Design's regex, `^[A-Za-z0-9._:\[\]-]{1,64}$`, silently rejects every valid model id
        (confirmed: `claude-sonnet-5` failed). POSIX bracket expressions have no backslash-escape, so
        `\]` mid-bracket closes the bracket early rather than matching a literal `]`. Fixed as
        `^[]A-Za-z0-9._:[-]{1,64}$` — same character class, `]` moved first and `-` moved last, both
        the only positions where they're literal in a POSIX bracket. Implementation-detail fix, not a
        design change: the intended character class is unchanged.
- [x] 4 — `panes/dispatch-pane-agent.test.sh`: assert the launcher contains the model when flagged and
      is unchanged when not (case 3's fail-fast included).
- [x] 5 — `skills/dispatching-pane-agents/SKILL.md`: document `--model` in the Procedure step that
      shows the `dispatch` command line. One line; do not restate the design here.
- [x] 6 — Run both suites (`bash panes/run-pane-agent.test.sh`, `bash panes/dispatch-pane-agent.test.sh`)
      and record pass counts in `## Verification`. **Both must pass before and after** — capture the
      before-counts first so a pre-existing failure is not mistaken for a regression.

## Out of scope

- Any change to which model a *judge* pane uses, or to the judges' lane rules.
- The handoff launcher path.
- Changing the default model for panes. Absent the flag, the pane keeps inheriting the user default —
  that is deliberate, and criterion 2 pins it.

## Verification

- Before (true merge-base `6734027`, verified in a throwaway worktree — the branch's own first
  commit already carried tasks 1-2, so `80328f3` was not actually a "before"): `run-pane-agent.test.sh`
  **10/0**, `dispatch-pane-agent.test.sh` **113/0**.
- After (all tasks): `run-pane-agent.test.sh` **12/0** (+2), `dispatch-pane-agent.test.sh` **119/0**
  (+6: 2 from tasks 1-2, plus shape reject on `--model "a b"`, no-pane-opened on that same call,
  launcher unchanged when unflagged, and the 5th-positional passthrough case).
- Criteria 1, 2, 4, 5 asserted directly in the suites above. Criterion 3 (`--model "a b"` dies with
  no pane) asserted at `dispatch-pane-agent.test.sh` — see "no pane opened" case.
- Observability-judge (implementation stage): no dimension failed, risk=low confidence=high.
  Confirmed findings, fixed here: (a) SC2038 on the `find | xargs grep -l` in the new unflagged-launcher
  test — switched to `find -exec … +`; (b) this Verification section's before-counts were captured
  mid-implementation (`80328f3`), not at the true branch point — corrected above. Open, deliberately
  not fixed: `MODEL_RE` has no anchor against a leading `-`, so a value shaped like another CLI flag
  (e.g. `--dangerously-skip-permissions`) passes the shape check — confirmed via direct dispatch (rc=0,
  pane opened). Not shell injection (the `%q`/array boundary holds); the exposure is that the value
  becomes `--model`'s *own* argument to the real `claude` CLI, which is the actual authority on
  whether it's a valid model id. Excluding leading `-` isn't in the card's stated regex or acceptance
  criteria — flagged to the user rather than silently expanding scope during review.
