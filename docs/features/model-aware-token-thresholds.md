---
phase: review
model_tier: low
branch: feat/model-aware-token-thresholds
---

# Model-aware token thresholds

The 75k checkpoint threshold is too conservative for larger-context models. Both the
context-handoff-watch hook and the statusline context bar now scale with the model tier:

- Sonnet: 100k tokens
- Opus/Fable: 130k tokens
- Other/unknown: 75k tokens (unchanged default)

## The anchors are rot budgets, not window fractions

> **Revised in review (2026-08-23), user decision.** The first cut set Sonnet to 150k and
> Opus/Fable to 200k. Both numbers were read off the *window* — 200k is exactly a non-1M Opus's
> window, 150k is three quarters of Sonnet's — and window size is the wrong quantity to price a
> checkpoint against. A larger window holds more tokens; it does not buy more attention. Published
> long-context work is consistent on this: Chroma's *Context Rot* study (18 models) finds
> degradation setting in well below the advertised limit and non-uniformly, and NoLiMa finds most
> models below half their short-context baseline by ~32k on non-literal retrieval.

Two things in this repo already said so and were contradicted by the numbers:

- `rules/gates.md` asks for a freshness checkpoint every ~35k tokens of new conversation, and the
  memory `feedback_offer_session_clear_after_tasks` records a ~100k per-session ceiling with the
  reason attached: *"a 1M-token window can already degrade badly around ~50K tokens of active
  content, so window capacity is the wrong thing to optimize against."* The old Opus anchor fired
  at 200k — twice that ceiling. Measured on this branch: 201,677 tokens.
- `statusline-command.sh` carries the same argument in its own bar comment — *"a 1M-context model
  gets unwieldy long before it is technically full"* — directly above constants that scaled with
  the window anyway.

The nudge is one-shot and non-blocking, so the costs are asymmetric: firing early costs one
ignorable line, firing late means the session was already degraded for the whole overshoot. The
anchors are set accordingly.

**The 30k Sonnet/Opus spread is a judgement call, not a measurement.** No per-model rot data for
Opus 5 vs Sonnet 5 was gathered; stronger models are generally observed to degrade more gracefully,
and that is the whole basis. Recorded here so a later reader does not mistake it for a measured
figure.

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
`Claude Opus 5 (1M context)` both resolve to 130k.

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
| Sonnet | 66,666 | 100,000 | 133,333 |
| Opus / Fable | 86,666 | 130,000 | 173,333 |

Verified by running the shell's own integer arithmetic, not by hand: `a*2/3` and `a*4/3` truncate,
so the yellow values are 66,666 and 86,666 rather than the rounded thirds.

Known, pre-existing: at ~0.25% below red the bar rounds to full while still orange. The old
fixed ladder had the same rounding artefact; not introduced here, not fixed here.

## Tasks

- [x] Update `hooks/context-handoff-watch.sh` with model detection — transcript-sourced
- [x] Update `statusline-command.sh` — all four constants scale off the orange anchor
- [x] Test with different model settings
  - `hooks/context-handoff-watch.test.sh` — 33 passed, 0 failed (measured: `origin/main` scores 19, so
    14 assertions are new; the model group drives the
    model through the transcript, not the payload). Written red-first: the 5 discriminating
    assertions failed against the payload-based implementation.
  - `statusline-command.test.sh` — 113 passed, 0 failed (70 pre-existing + 43 new, the last 16
    covering the window cap). The 70
    pre-existing assertions, including the control-byte injection group, pass unchanged against
    the modified script. Falsifier confirmed: pinning red back to 100k reddens 17 of 113,
    including both ladder-ordering checks. (Measured after the clamp group landed; it was 8
    before those 16 assertions existed, and the card said 8 for one round too long.)
  - `statusline-command.falsify.py` — "falsification intact". The current suite still fails the
    right named control-byte-injection cases against all four historical script versions.
  - Verified live: the modified hook fired at **201,677 tokens** against the 200k Opus threshold
    while this branch was being prepared.
- [x] Commit and verify hooks still work — `bb42a87`, exactly 5 files. Both suites green after
  the commit; the modified hook ran on every tool call of this session without error.

## Review round (observability judge, `b2e5f3c`)

Verdict: no dimension failed, `risk=medium confidence=high`. It independently re-ran both suites
(33/0, 97/97) and confirmed the clobbered statusline suite was fully recovered — `main` scores
70/70 and that file's diff shows zero deleted lines. Four findings were acted on:

1. **Four places still quoted the old fixed 75k.** All verified against the cited `file:line` and
   corrected: `panes/handoff-wrapper.sh` (runtime, user-facing — it told the user "crossed 75k
   tokens" while firing at 200k), `rules/gates.md` (always-on), `hooks/README.md`, and
   `skills/dispatching-pane-agents/SKILL.md`. The wrapper is handed only a target directory, so it
   now names no figure rather than guessing one.
2. **Latent bug: `*opus*` → 200k is exactly a non-1M Opus's window**, so neither the bar nor the
   nudge would ever fire there. Confirmed real. Probing the live statusline payload showed it
   reports `context_window.context_window_size` (1,000,000 here), so the anchor is now capped at
   `window * 3/4`. Every specified threshold is unchanged wherever the window has room for it; only
   the 200k-window Opus case moves (200k → 150k). User decision, 2026-08-22: clamp the statusline
   only. ADR 0035.
3. **The mapping is duplicated and the two copies read different fields** (hook: model id from the
   transcript; statusline: display name from its payload). Recorded as a known risk in ADR 0035
   rather than fixed — they agree today because both strings carry the family word.
4. **No ADR for the payload→transcript pivot.** Written: `docs/decisions/0035-model-aware-context-thresholds.md`.

Historical records that still say 75k — ADR 0007 and the pane-orchestration plan — are deliberately
left alone.

## Revision round (2026-08-23) — anchors lowered to rot budgets

User decision after review: `150k/200k` → **`100k/130k`**, fallback 75k unchanged. Reasoning in
*The anchors are rot budgets, not window fractions* above. Tests were rewritten to the new spec
**first** and both suites confirmed red before either source file was touched — 28 failures in
`statusline-command.test.sh`, 9 in `hooks/context-handoff-watch.test.sh`, every one of them a tier
boundary that moves and nothing else.

- `hooks/context-handoff-watch.sh` — `100000` / `130000`; comment now states the rot-budget framing.
- `statusline-command.sh` — same anchors; the cap comment records its demotion to defence-in-depth.
- New assertions: the Sonnet/Opus **spread** itself (at 110,000 fill Sonnet is orange, Opus still
  yellow), and `opus at 130k fires below any 200k wall`. The window-cap group moved from a
  200k window (no longer binding) to a **128k** window, where `128000 * 3/4 = 96000` does bind and
  red lands at exactly 128,000 — so the cap is still exercised rather than merely present.

Verified after the change:

- `bash statusline-command.test.sh` → **122/122 passed**
- `bash hooks/context-handoff-watch.test.sh` → **34 passed, 0 failed**
- `python3 statusline-command.falsify.py` → **falsification intact** (all four historical script
  versions still fail the right named cases)

- **Live fire observed.** During this same revision session the modified hook fired against the new
  threshold: `context-handoff-watch: session context is at 130495 tokens (>= 130000)`, on
  `claude-opus-5[1m]`, with the handoff pane prepared. Not a replay of the earlier 201,677-token
  observation — that one was against the 200k threshold on the pre-revision code.

## Known limitations

- Red lands exactly **at** the window under a binding cap, not inside it. Orange — the tier that
  signals the checkpoint — still fires with headroom. Reasoned in ADR 0035.
- The window cap applies to the statusline only, and it is now **defence-in-depth rather than
  load-bearing**: at 100k/130k anchors it binds only below a ~133k (Sonnet) / ~173k (Opus) window,
  which no current model has. Under the previous 200k Opus anchor it was doing real work on any
  non-1M Opus. Kept, not removed — the anchors are a judgement call and could rise again.
- ~~On a 200k-window Opus the hook's nudge never fires.~~ **Closed by the 2026-08-23 revision.**
  It never fired because 200k of fill is the whole window and auto-compact intervenes first; 130k
  is reachable on any Opus window, and the hook needs no cap to get there. Asserted by
  `opus at 130k fires below any 200k wall` in `hooks/context-handoff-watch.test.sh`.
- No test asserts the hook and the statusline resolve the same model to the same threshold.
- At ~0.25% below red the bar rounds to full while still orange. Pre-existing; unchanged.

## Out of scope on this branch

`settings.json` `modelSettings` and `treko/tracker-data.js` are modified in the working tree by
unrelated work and are deliberately not staged here.
