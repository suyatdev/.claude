---
phase: implementation
model_tier: low
branch: feat/model-aware-token-thresholds
---

# Model-aware token thresholds

The 75k checkpoint threshold is too conservative for larger-context models. Both the
context-handoff-watch hook and the statusline context bar now scale with the model tier:

- Sonnet: 150k tokens
- Opus/Fable: 200k tokens
- Other/unknown: 75k tokens (unchanged default)

## Changes

1. `hooks/context-handoff-watch.sh` — model-derived `THRESHOLD`, sourced from the transcript
2. `statusline-command.sh` — all four bar constants derived from the model's orange anchor

## Model detection

**Hook.** The live model is the last assistant turn's `.message.model` in the transcript the
hook already tails — one `tail`, one `jq`, no extra file read. `settings.json` `.model` is the
fallback when the transcript names no model.

> **The original plan's step 1 was wrong.** It specified reading `.model.id` /
> `.model.display_name` from the hook payload. A captured live PostToolUse payload has **no
> `model` key at all** — its keys are `cwd`, `duration_ms`, `effort`, `hook_event_name`,
> `permission_mode`, `prompt_id`, `session_id`, `tool_input`, `tool_name`, `tool_response`,
> `tool_use_id`, `transcript_path`. That branch would have been dead code silently falling
> through to `settings.json`, which holds the *configured default*, not the model actually
> generating tokens. Verified by temporarily dumping the payload from the registered hook.

**Statusline.** `.model.display_name` from its own stdin payload — present and already used to
render the model name.

Matching is case-insensitive on `sonnet` / `opus` / `fable`, so `claude-opus-5[1m]` and
`Claude Opus 5 (1M context)` both resolve to 200k.

## Statusline: the thresholds move as a set

> **The original plan's step 2 was incomplete.** Raising `THRESHOLD_TOKENS_ORANGE` alone leaves
> `THRESHOLD_TOKENS_RED` at 100k. The tier ladder is evaluated in order
> (`n<yellow → n<orange → n<red → else red`), so with orange above red the **orange tier becomes
> unreachable** and the bar sits full-but-yellow across 100k of headroom — breaking the
> documented "a full bar and a red bar mean the same thing" invariant.

Yellow, red and the bar reference are therefore derived from the orange anchor, holding their
original ratios (`2/3`, `4/3`, reference `==` red). The 75k fallback reproduces the previous
50k/75k/100k ladder exactly.

| Model | yellow | orange | red / bar-full |
|---|---|---|---|
| fallback | 50,000 | 75,000 | 100,000 |
| Sonnet | 100,000 | 150,000 | 200,000 |
| Opus / Fable | 133,333 | 200,000 | 266,666 |

Known, pre-existing: at ~0.25% below red the bar rounds to full while still orange. The old
fixed ladder had the same rounding artefact; not introduced here, not fixed here.

## Tasks

- [x] Update `hooks/context-handoff-watch.sh` with model detection — transcript-sourced
- [x] Update `statusline-command.sh` — all four constants scale off the orange anchor
- [x] Test with different model settings
  - `hooks/context-handoff-watch.test.sh` — 33 passed, 0 failed (was 14; model group drives the
    model through the transcript, not the payload). Written red-first: the 5 discriminating
    assertions failed against the payload-based implementation.
  - `statusline-command.test.sh` — 97 passed, 0 failed (70 pre-existing + 27 new). The 70
    pre-existing assertions, including the control-byte injection group, pass unchanged against
    the modified script. Falsifier confirmed: pinning red back to 100k turns 8 of the new
    assertions red, including both ladder-ordering checks.
- [x] Commit and verify hooks still work — `bb42a87`, exactly 5 files. Both suites green after
  the commit; the modified hook ran on every tool call of this session without error.

## Out of scope on this branch

`settings.json` `modelSettings` and `treko/tracker-data.js` are modified in the working tree by
unrelated work and are deliberately not staged here.
