# Brainstorm — Session Pane-Split Policy (2026-07-22)

Design provenance for the spec at
`docs/superpowers/specs/2026-07-22-pane-split-policy-design.md`. Written before a session clear;
this file is the durable record of *why* the design is shaped as it is.

## User's original ask (verbatim intent)

> "a hook that before any session starts would ask me if I want to split the sub-agents/spawns into
> panes, the max limit I want the panes to split to, or if I want to just do inline."

## Key reframing surfaced in triage

The literal request is **not buildable as stated**: Claude Code hooks are non-interactive — a
SessionStart hook can inject context or exit, but it cannot present a menu and capture a selection.
So the design splits the ask into: a **hook** as the deterministic *trigger* (the existing PreToolUse
`hooks/pane-dispatch-guard.sh`) + **model behavior** (`AskUserQuestion`) for the actual asking +
a **per-session state file** the pane machinery reads.

Triage verdict: this is a multi-tier change (hook + model behavior + dispatch-subsystem
implementation), classified via `triaging-new-instructions`, then brainstormed via
`superpowers:brainstorming`.

## Brainstorm Q&A (4/4, all user-answered)

1. **When is the preference collected?** → **Lazy, at first pane-eligible dispatch.** (Rejected:
   ask-every-session-start = friction on throwaway sessions; also not mechanically possible as a hook.)
2. **Which spawns does the policy govern?** → **Worker fan-out, not read-only.** Governed: judges,
   plan implementers, general-purpose/workers, parallel fan-out. Always in-process: `Explore`, `Plan`,
   search helpers. (Rejected: "only the current two judges" too small; "every spawn" would drag cheap
   read-only helpers into panes.)
3. **What does "max panes" mean + overflow behavior?** → User's own answer: **max CONCURRENT panes;
   extra spawns open as TABS inside existing panes** (round-robin), not inline, not blocked. (This was
   a better model than any of the three offered — I had offered overflow-to-inline / overflow-to-wait /
   total-per-session.)
4. **Terminal target?** → **cmux primary** (confirmed the user runs cmux — `terminal-detect.sh` →
   `cmux`, `CMUX_PANEL_ID` set). tmux buildable; iTerm/Terminal degrade to "tab in same window".

## Two accepted trade-offs (user confirmed via "Looks good. Continue")

- **Plan implementers move from skill-routed judgment → hook-governed.** Today they are deliberately
  *not* in `redirect-agents.conf` ("substantial is a judgment call the skill owns"). The worker-fan-out
  scope pulls them under the guard. User accepted.
- **Build cmux properly; let iTerm/Terminal/tmux degrade** to "tab in same window" rather than hold
  the feature to strict cross-terminal parity.

## Eligibility model change

Flip today's **include-list** (`redirect-agents.conf` lists types TO redirect) to an **exclude-list**
(everything governed except read-only `Explore`/`Plan`). Whether to repurpose `redirect-agents.conf`
or add a new `panes/inprocess-agents.conf` is deferred to the plan.

## Gate decisions recorded this session (do NOT re-ask)

- **Hard Model Gate:** answered **stay on Opus 4.8 (1M)** for the spec (architecture/requirements).
  Implementation-tier choice explicitly deferred — re-ask before shell-script implementation/tests.
- **Freshness checkpoint:** user chose **write spec, then clear**. Spec + memory committed and pushed;
  fresh session resumes from the committed spec.

## NEXT STEPS (fresh session — in order)

1. **Spec-compliance gate (BLOCKING, deferred to here on purpose):** run the compliance judge on the
   spec (pane-dispatched, alongside the observability judge's architecting read) via
   `running-the-compliance-judge`. A passing verdict is required before `writing-plans`. This was NOT
   run in the writing session to avoid firing two pane judges at 78k tokens mid-checkpoint.
2. **User review gate:** ask the user to review the committed spec; apply changes + re-judge if any.
3. **Model gate (implementation):** re-ask model tier before planning/implementation.
4. **`superpowers:writing-plans`** → implementation plan (TDD; cmux tab primitive probed FIRST, same
   as pane-layout-v2's live-probe-first discipline).

## Provenance of related work

Follows PR #23 (pane orchestration), PR #25 (pane layout v2, cmux 2×2 quadrant), PR #26 (cmux version
gate). Same fail-open / session-id-keyed / fake-binary-tested conventions as the rest of `panes/`.
