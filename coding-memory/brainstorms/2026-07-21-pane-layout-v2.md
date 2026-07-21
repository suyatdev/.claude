# Brainstorm: pane-layout v2 (structured workspace layout)

**Status: INTAKE ONLY — clarifying questions not yet asked.** Captured at the 2026-07-21
~82k-token freshness checkpoint so a fresh session can resume the brainstorm without re-deriving
anything. Follow-on to pane orchestration (PR #23, `docs/superpowers/specs/2026-07-20-pane-orchestration-design.md`).

## User requirements (verbatim intent, 2026-07-21)

All panes live in ONE workspace; split direction depends on what triggered the dispatch:

1. Sub-agent implementation tasks → 5-pane layout: far-left = main session, each subagent in a
   quadrant (2x2) to the right of it.
2. Any additional pane opens to the right of the quadrant, as a new session.
3. Full layout: far-left pane = main session · middle pane = 2x2 quadrant of subagents/spawns ·
   far-right pane = additional.
4. Sessions past the 6th always open as a new tab ON the 6th (far-right) pane.
5. Hard cap: 6 panes per workspace.

```
+--------+-----------+-----------+
|        | SA1 | SA2 |           |
|  main  |-----+-----| additional|
|        | SA3 | SA4 | (tabs >6) |
+--------+-----------+-----------+
```

## Current-system facts (verified this session)

- `panes/adapters/cmux.sh` is layout-blind: every dispatch is `new-split down` targeting the
  calling workspace via `$CMUX_WORKSPACE_ID`/`$CMUX_SURFACE_ID`. No slot/position awareness.
- `panes/dispatch-pane-agent.sh` (209 lines) keeps per-run state only (`state/runs/<id>/`);
  no per-workspace layout state exists. Adapter contract is `open_pane <title> <launcher>` —
  no role/slot parameter.
- Panes stay open after the agent exits (`exec /bin/zsh -i` in the launcher) — slot
  reclamation is therefore a real design question, not hypothetical.

## cmux CLI recon (confirmed via --help, 2026-07-21)

The layout is fully expressible:

- `new-split <left|right|up|down> [--workspace] [--surface] [--panel]` — directional splits
  targeting a specific surface → can build main | quadrant | right column.
- `new-surface [--type terminal] [--pane <ref>]` — adds a surface (tab) to an EXISTING pane →
  the ">6 opens a tab in pane 6" mechanism.
- `list-panes`, `list-pane-surfaces`, `tree` — inspect live layout (reconcile state vs. panes
  the user closed manually).
- Also available if needed: `move-surface --pane`, `swap-pane`, `split-off`, `focus-pane`,
  `resize-pane`, and `new-workspace --layout <json>` (upfront JSON layout — only for NEW
  workspaces, so likely irrelevant: the main session already lives in an existing workspace).

## Open clarifying questions (ask ONE at a time, next session)

1. **Role classification:** which dispatch types map to the quadrant vs. the far-right pane?
   Implementers → quadrant per requirement 1. But the two judges (compliance/observability)?
   The context-handoff pane? User-requested extra sessions? "Additional" needs a precise list.
2. **Slot reclamation:** panes stay open for inspection after an agent exits. Does the next
   dispatch reuse a finished agent's quadrant slot (replacing its surface), or do finished
   panes keep their slot until closed manually (pushing new dispatches toward overflow)?
3. **Construction timing:** does the quadrant build progressively (1st implementer = one
   middle pane, splitting into 2x2 as more spawn) or are all 4 quadrant panes created upfront
   when the first implementation dispatch fires?
4. **Adapter scope:** layout smarts cmux-only (the only live-proven adapter), with tmux/iterm
   keeping today's dumb `new-split down`? (Recommended default: yes, cmux-only.)
5. **Quadrant overflow:** a 5th concurrent implementer — far-right pane first, then tabs? Or
   straight to tabs on a quadrant pane?

## Constraints to carry into the design

- Degrade-never-block invariant from PR #23 stands (adapter failure → cooldown → in-process).
- Adapter contract change touches `dispatch-pane-agent.sh`, all 4 adapters' arg validation
  (`common.sh`), and both test suites.
- Per-workspace layout state (slot map) is new state — needs the same stale-cleanup treatment
  as `state/runs/`.
- Model-switch gate: user implicitly stayed on Fable 5 for the brainstorm (2026-07-21); the
  pre-implementation gate must still be asked separately when this reaches code.
