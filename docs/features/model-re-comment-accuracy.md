---
phase: review
model_tier: low
branch: none  # merged via PR #73 (ab39635) 2026-08-24; fix/model-re-comment-accuracy
              # branch auto-deleted on merge; tip 92564dd verified ancestor of origin/main
---

# Fix misleading `MODEL_RE` comment in `dispatch-pane-agent.sh`

Follow-up to `pane-dispatch-model-flag` (merged PR #71, `330030f`). The observability judge flagged,
and the user confirmed in conversation, that the comment above `MODEL_RE` at
`panes/dispatch-pane-agent.sh:38-44` overstates what the regex does: it claims to "reject
shell-hostile input" but a leading `-` passes the shape check, so `--model
"--dangerously-skip-permissions"` is accepted (rc=0, pane opens) and reaches the real `claude` CLI
as `--model`'s own argument. Verified directly in the prior session, not shell injection (the
launcher's `%q` boundary holds regardless).

Scoped straight to `implementation` — this is a comment-only correction already designed and
approved in conversation, not new design work. No planning cycle needed for a one-block comment fix.

## Change

Reword the comment block to state the actual behavior (leading `-` is not excluded) instead of the
inaccurate "rejects shell-hostile input" claim. **No regex change** — a leading `-` is inside the
card's stated character class from `pane-dispatch-model-flag`, so excluding it would be a spec
change, out of scope here.

## Tasks

- [x] 1 — Reword the comment block at `panes/dispatch-pane-agent.sh:38-44`.
- [x] 2 — Run `bash panes/dispatch-pane-agent.test.sh` and `bash panes/run-pane-agent.test.sh` —
      confirm no assertion depends on comment text and counts are unchanged (119/0, 12/0).

## Out of scope

- Tightening `MODEL_RE` to exclude a leading `-`.
- Anything else in `pane-dispatch-model-flag`, already merged and closed.

## Verification

- `run-pane-agent.test.sh`: 12/0 (unchanged).
- `dispatch-pane-agent.test.sh`: 119/0 (unchanged).
- `shellcheck -x panes/dispatch-pane-agent.sh`: clean, rc=0.
- Comment-only diff; no test asserts on comment text, so an unchanged count confirms no
  behavioral regression, not that the comment itself is now accurate — that's a human read of
  the diff.
- PR #73 opened via `JUDGE_EXEMPT="comment-only diff, no behavior change; suites unchanged
  12/0 119/0, shellcheck clean"` — comment-only change, no source-behavior diff to judge.
