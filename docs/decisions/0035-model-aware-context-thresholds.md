# 0035 — The context checkpoint threshold reads the live model, and the bar's four constants move as one

- **Status:** Accepted (2026-08-22), **amended 2026-08-23** — the anchors changed from
  150k/200k to **100k/130k** before this ADR ever merged. Amended in place rather than superseded
  by a new ADR precisely because it is unmerged: shipping a known-wrong decision plus its corrector
  in the same pull request would leave two records of one decision and no way to tell which binds.
  The superseding convention (0015 amending 0013 amending 0012) applies to ADRs already on `main`.
- **Context:** `hooks/context-handoff-watch.sh`, `statusline-command.sh`, and their two suites;
  `panes/handoff-wrapper.sh`, `rules/gates.md`, `hooks/README.md`,
  `skills/dispatching-pane-agents/SKILL.md` for the text that described the old fixed number.
  Card, tables and measurements: `docs/features/model-aware-token-thresholds.md`. Touches the
  watcher introduced by **ADR 0007** (pane orchestration) without reopening it.
- **Note:** this ADR was first written as **0034**, and the note here claimed that number had been
  confirmed free against every remote ref. **It had not been.** The check passed several refs to a
  single `git ls-tree`, which accepts one tree-ish and treats the rest as *pathspecs* — so only the
  first ref was ever examined, and the command reported clean while looking at almost nothing.
  `0034` was already taken by `origin/feat/treko-store-location`
  (`0034-the-store-leaves-the-repo-and-the-guard-is-repointed.md`, committed three hours earlier).
  Because the filenames differ, git would have merged both without a murmur — `origin/main` already
  carries two files numbered `0026` from exactly that failure. Renumbered to **0035** after a real
  `git fetch` and one `ls-tree` **per ref**: taken numbers are 0001-0027 and 0029-0034, with `0028` a
  pre-existing gap left alone rather than backfilled out of order. Caught by the observability
  judge, not by the author.

## Context

One hard-coded number — 75,000 tokens, the "this session is getting long, go checkpoint" mark —
lived in two places: the `PostToolUse` watcher that nudges the freshness checkpoint and prepares a
handoff pane, and the status line's orange tier. 75k is too conservative in practice, so the number
had to become a function of the model.

> **Amendment (2026-08-23): "once the window is much larger than that" was the wrong reason.**
> The original sentence justified raising the number by pointing at window size, and the first
> anchors were duly read off the window — 200,000 is exactly a non-1M Opus's window, 150,000 is
> three quarters of Sonnet's. That prices a checkpoint against the wrong quantity. A larger window
> holds more tokens; it does not buy more attention, and long-context evaluations
> (Chroma's *Context Rot* across 18 models; NoLiMa's non-literal retrieval) find quality decaying
> well below the advertised limit rather than near it. Two things in this repo already said as
> much and were contradicted by the constants: `rules/gates.md` asks for a checkpoint every ~35k
> of new conversation against a recorded ~100k session ceiling, while the Opus anchor did not fire
> until 200k; and `statusline-command.sh`'s own bar comment reads *"a 1M-context model gets
> unwieldy long before it is technically full"* directly above constants that scaled with the
> window anyway.
>
> The anchors are therefore **budgets for where answer quality decays**, and do not grow with the
> window: **Sonnet 100,000, Opus/Fable 130,000**, fallback 75,000 unchanged. The nudge is one-shot
> and non-blocking, so the costs are asymmetric — firing early costs one ignorable line, firing
> late means the whole overshoot was worked degraded.
>
> The 30k Sonnet/Opus spread is a **judgement call, not a measurement**: no per-model rot data for
> Opus 5 versus Sonnet 5 was gathered. Recorded so it is not later mistaken for a measured figure.

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
`THRESHOLD_TOKENS_RED` previously fixed at 100,000. Raising orange alone to any anchor at or above
that puts **orange above red**, which makes the orange tier unreachable and leaves the bar rendering
full-but-yellow across the gap, breaking the invariant that file documents: *a full bar and a red
bar mean the same thing.* The first draft's 150k/200k anchors made this obvious; the amended
100k/130k anchors do not make it go away — Sonnet's 100,000 lands exactly *on* the old fixed red,
and `orange == red` collapses the orange tier just as completely as `orange > red` does.

`THRESHOLD_TOKENS_YELLOW`, `THRESHOLD_TOKENS_RED` and `BAR_REFERENCE_TOKENS` are therefore derived
from the orange anchor at their original ratios (`2/3`, `4/3`, reference `==` red). The 75k fallback
reproduces the previous 50k/75k/100k ladder exactly, so the change is a no-op for any unrecognised
model.

### 3. The anchor is capped by the model's real context window

The family anchor is a fixed number; a model's window is not. If the anchor is at or above the
window, red sits at or past the wall: the bar can never redden and the checkpoint is never
signalled — the warning silently off precisely when it matters. The original `*opus*` → 200,000 was
exactly that case on a non-1M Opus, and the cap is what made it safe.

The status line payload reports `context_window.context_window_size` (verified live: `1000000` on
`claude-opus-5[1m]`). Where it is present, the anchor is capped so red (`4/3 × orange`) lands **at
or inside** the window rather than past it:

```
orange = min(family_anchor, context_window_size * 3/4)
```

The cap binds only when the window is genuinely too small, so every specified threshold survives
untouched wherever there is room for it:

| Model | window | anchor | after cap |
|---|---|---|---|
| Opus / Fable | 1,000,000 | 130,000 | 130,000 (unchanged) |
| Opus / Fable | 200,000 | 130,000 | 130,000 (unchanged) |
| Sonnet | 200,000 | 100,000 | 100,000 (unchanged) |
| unrecognised | 200,000 | 75,000 | 75,000 (unchanged) |
| Opus / Fable | 128,000 | 130,000 | **96,000** (capped) |

> **Amendment (2026-08-23): the cap survives, but its role changed.** At 100k/130k anchors it binds
> only below a ~133,333 (Sonnet) / ~173,333 (Opus) window — no model in the current lineup. The
> motivating case above is now historical: lowering the anchor removed the 200k-window collision
> rather than the cap removing it. It is kept as defence-in-depth because the anchors are a
> judgement call and could rise again, and because a narrower future model would need it. The test
> suite exercises it at a **128,000** window, where it genuinely binds, rather than at 200,000
> where it no longer does — a cap that no test can make bind is a cap nobody knows is broken.

## Consequences

- **Red lands exactly *at* the wall, not inside it,** whenever the cap binds. With
  `orange = window × 3/4`, red is `orange × 4/3 = window`, and the tier test is
  `n < red → orange, else red` — so red begins on the first token at the window. That is the
  intended reading of red ("you have reached the window"), but it is not the same claim as
  "inside", and an earlier draft of this ADR overstated it. The cap's guarantee is about orange,
  not about red having headroom. *(2026-08-23: at the lowered anchors nothing in the current
  lineup reaches a binding cap, so on every shipping model red now sits well inside the window —
  173,333 on a 200k-window Opus, 133,333 on Sonnet.)*
- The two halves each carry their own copy of the model→threshold mapping, and they read **different
  fields**: the hook matches on the model **id** from the transcript, the status line on the
  **display name** from its payload. They agree today only because both strings contain the family
  word. Nothing ties them together, and no test asserts they agree. Accepted for now; the honest
  description of the risk is that a future model naming its id and display name differently could
  split them.
- **The cap applies to the status line only.** The hook's payload does not carry the window size,
  and the transcript records it once near the top rather than on assistant turns — reading it would
  cost the hook the tail-only parse its header documents as load-bearing, for a value that can go
  stale if the model changes mid-session. This is a deliberate asymmetry, not an oversight.

  *(2026-08-23: this asymmetry used to have a real cost — on a 200k-window Opus the bar warned but
  the nudge never fired, because 200,000 of fill is the entire window and auto-compact intervenes
  first. The lowered anchor closes it without giving the hook a cap: 130,000 is reachable on every
  Opus window. Asserted by `opus at 130k fires below any 200k wall` in the hook suite. The
  structural asymmetry remains for a hypothetical model narrower than 173k.)*
- Text that quoted the old fixed number was corrected in four places, including
  `panes/handoff-wrapper.sh`, which printed "The main session crossed 75k tokens" to the user at the
  moment they decide whether to hand off. That wrapper is handed only a target directory, so rather
  than guess a number it now names no figure at all; the hook's own nudge carries the real one.
- Historical records — ADR 0007, the pane-orchestration plan under `docs/superpowers/plans/`, and
  the design spec `docs/superpowers/specs/2026-07-20-pane-orchestration-design.md` (ten mentions) —
  still say 75k and are deliberately **not** rewritten. They record what was true when written.
- At roughly 0.25% below red the bar rounds to full while the tier is still orange. The previous
  fixed ladder had the identical artefact; not introduced here, not fixed here.

## Alternatives considered

- **Derive everything from the window, dropping the family table.** Rejected: the three tiers are an
  explicit product decision (Sonnet 100k, Opus/Fable 130k, else 75k) and no single percentage
  reproduces them — on their respective windows they are 50%, 13% (1M Opus) or 65% (200k Opus), and
  37.5%. The 2026-08-23 amendment makes this more than an arithmetic objection: a percentage is the
  wrong *shape*, because the quantity being budgeted is attention, which does not grow with the
  window. The window enters exactly once, as the cap, and only to stop the anchor exceeding it.
- **Ship without the cap and log the risk.** Rejected: the failure is silent and disables the whole
  feature on a model the user can select today.
- **Cap both halves, with the hook scanning the transcript for the window size.** Rejected on the
  cost above; recorded as the known asymmetry instead.
