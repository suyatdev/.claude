# 0034 — The context checkpoint threshold reads the live model, and the bar's four constants move as one

- **Status:** Accepted (2026-08-22)
- **Context:** `hooks/context-handoff-watch.sh`, `statusline-command.sh`, and their two suites;
  `panes/handoff-wrapper.sh`, `rules/gates.md`, `hooks/README.md`,
  `skills/dispatching-pane-agents/SKILL.md` for the text that described the old fixed number.
  Card, tables and measurements: `docs/features/model-aware-token-thresholds.md`. Touches the
  watcher introduced by **ADR 0007** (pane orchestration) without reopening it.
- **Note:** ADR number **0034** was confirmed free at the moment of writing against `origin/main`
  and every remote ref, not against a local `ls`.

## Context

One hard-coded number — 75,000 tokens, the "this session is getting long, go checkpoint" mark —
lived in two places: the `PostToolUse` watcher that nudges the freshness checkpoint and prepares a
handoff pane, and the status line's orange tier. 75k is too conservative once the window is much
larger than that, so the number had to become a function of the model.

Making it model-aware turned out to hinge on two facts that were not what the plan assumed, and one
that only surfaced under review.

## Decision

### 1. The hook reads the model from the transcript, not from its payload

The feature card specified reading `.model.id` / `.model.display_name` from the hook payload. Before
implementing it, the live registered hook was instrumented to dump its stdin and a tool call was
fired. **The `PostToolUse` payload has no `model` key.** Its complete key set is `cwd`,
`duration_ms`, `effort`, `hook_event_name`, `permission_mode`, `prompt_id`, `session_id`,
`tool_input`, `tool_name`, `tool_response`, `tool_use_id`, `transcript_path`.

That branch would have been dead code, silently falling through to `settings.json` `.model` — the
*configured default*, not the model actually generating the tokens. Since the two agree most of the
time, the failure would have been invisible.

The model is therefore taken from the last assistant turn's `.message.model` in the transcript the
hook already tails, folded into the **same** `tail`/`jq` invocation (emitted as `"<fill> <model>"` on
one line), so there is no extra file read and no extra process. `settings.json` remains a fallback
for a transcript that names no model.

This is the general rule at work: a threshold must be sourced from data that demonstrably exists,
and the way to establish that is to look at a real payload rather than at documentation.

### 2. The status line's four constants derive from one anchor

The tier ladder is evaluated in order — `n < yellow` → `n < orange` → `n < red` → else red — with
`THRESHOLD_TOKENS_RED` previously fixed at 100,000. Raising orange alone to 150k/200k puts **orange
above red**, which makes the orange tier unreachable and leaves the bar rendering full-but-yellow
across 100k of headroom, breaking the invariant that file documents: *a full bar and a red bar mean
the same thing.*

`THRESHOLD_TOKENS_YELLOW`, `THRESHOLD_TOKENS_RED` and `BAR_REFERENCE_TOKENS` are therefore derived
from the orange anchor at their original ratios (`2/3`, `4/3`, reference `==` red). The 75k fallback
reproduces the previous 50k/75k/100k ladder exactly, so the change is a no-op for any unrecognised
model.

### 3. The anchor is capped by the model's real context window

The family anchor is a fixed number; a model's window is not. `*opus*` → 200,000 is exactly the
window of a non-1M Opus, and on that model red would sit at or past the wall: the bar could never
redden and the checkpoint would never be signalled — the warning silently off precisely when it
matters.

The status line payload reports `context_window.context_window_size` (verified live: `1000000` on
`claude-opus-5[1m]`). Where it is present, the anchor is capped so red (`4/3 × orange`) still lands
inside the window:

```
orange = min(family_anchor, context_window_size * 3/4)
```

The cap binds only when the window is genuinely too small, so every specified threshold survives
untouched wherever there is room for it:

| Model | window | anchor | after cap |
|---|---|---|---|
| Opus / Fable | 1,000,000 | 200,000 | 200,000 (unchanged) |
| Sonnet | 200,000 | 150,000 | 150,000 (unchanged) |
| unrecognised | 200,000 | 75,000 | 75,000 (unchanged) |
| Opus / Fable | 200,000 | 200,000 | **150,000** (capped) |

## Consequences

- The two halves each carry their own copy of the model→threshold mapping, and they read **different
  fields**: the hook matches on the model **id** from the transcript, the status line on the
  **display name** from its payload. They agree today only because both strings contain the family
  word. Nothing ties them together, and no test asserts they agree. Accepted for now; the honest
  description of the risk is that a future model naming its id and display name differently could
  split them.
- **The cap applies to the status line only.** The hook's payload does not carry the window size,
  and the transcript records it once near the top rather than on assistant turns — reading it would
  cost the hook the tail-only parse its header documents as load-bearing, for a value that can go
  stale if the model changes mid-session. So on a 200k-window Opus the bar now warns correctly but
  the nudge still does not fire. This is a known, deliberate asymmetry, not an oversight.
- Text that quoted the old fixed number was corrected in four places, including
  `panes/handoff-wrapper.sh`, which printed "The main session crossed 75k tokens" to the user at the
  moment they decide whether to hand off. That wrapper is handed only a target directory, so rather
  than guess a number it now names no figure at all; the hook's own nudge carries the real one.
- Historical records — ADR 0007 and the pane-orchestration plan under `docs/superpowers/plans/` —
  still say 75k and are deliberately **not** rewritten. They record what was true when written.
- At roughly 0.25% below red the bar rounds to full while the tier is still orange. The previous
  fixed ladder had the identical artefact; not introduced here, not fixed here.

## Alternatives considered

- **Derive everything from the window, dropping the family table.** Rejected: the three tiers are an
  explicit product decision (Sonnet 150k, Opus/Fable 200k, else 75k) and no single percentage
  reproduces them — they are 75%, 20% and 37.5% of their respective windows.
- **Ship without the cap and log the risk.** Rejected: the failure is silent and disables the whole
  feature on a model the user can select today.
- **Cap both halves, with the hook scanning the transcript for the window size.** Rejected on the
  cost above; recorded as the known asymmetry instead.
