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

## Decisions (clarifying Q&A — COMPLETE 5/5, 2026-07-21)

1. **Role classification — DECIDED: implementers only → quadrant.** The 2x2 quadrant is
   reserved for plan-task implementers/reviewers. The two judges (compliance/observability),
   the context-handoff pane, and user-requested extra sessions ALL route to the far-right
   "additional" pane (tabbing there when full). User explicitly chose this over the
   recommended "all agents → quadrant" option.
2. **Slot reclamation — DECIDED: reuse finished slots.** A quadrant slot whose agent has
   exited (result file written) is fair game — the next implementer dispatch replaces that
   surface. Scrollback is lost; `state/runs/<id>/` result files + transcripts remain the
   durable record. Quadrant never overflows from finished work.
3. **Construction timing — DECIDED: progressive splits.** 1st implementer = one middle pane;
   2nd splits it into a stack; 3rd/4th complete the 2x2. Deterministic split sequence, no
   empty panes; single-implementer runs stay a clean two-pane layout.

4. **Adapter scope — DECIDED: cmux-only.** Only `cmux.sh` learns slot/role placement;
   tmux/iterm/kitty keep today's dumb `new-split down` and ignore any new contract hint.
   (User took the recommended default.)
5. **Quadrant overflow — DECIDED: tabs on a quadrant pane.** A 5th+ concurrent implementer
   opens as a new surface (tab) on an existing quadrant pane via `new-surface --pane`.
   Implementers never leave the quadrant; far-right stays judges/handoff/extras. Accepted
   visibility cost: a tabbed implementer is hidden until its tab is clicked.

## cmux recon round 2 (verified 2026-07-21 checkpoint session)

- `cmux --json tree --all` exposes per-surface `title`, `tty`, refs, `index_in_pane`, plus
  workspace titles — VERIFIED live (the handoff pane's title was visible in the output).
- **Pane list is FLAT — no geometry.** No x/y, no split-tree structure in the JSON. Which
  pane is "the quadrant" or "far-right" CANNOT be inferred from position; role/slot identity
  must be carried by surface titles (a naming convention) and/or stored pane refs.
- `rename-tab [--surface <ref>] <title>` sets a surface title programmatically — so
  create-then-rename works without relying on in-shell OSC escapes.
- `new-split <left|right|up|down> [--workspace] [--surface] [--focus]` — help shows NO
  output of the created pane/surface refs. UNVERIFIED whether it prints them; live-probe
  next session before designing around ref capture. Fallback: diff `tree --json` before/after.
- `new-surface` confirms the tab mechanism: `--pane <ref>`, `--working-directory`, `--focus`.
  (Also offers `--type agent-session --provider claude` — noted, likely out of scope.)

## cmux recon round 3 — live probe (2026-07-21, fresh session; scratch workspace, cleaned up)

- **`--json new-split` RETURNS REFS** — verified live: `{"pane_ref": "pane:30",
  "surface_ref": "surface:51", "type": "terminal", "window_ref": "window:1",
  "workspace_ref": "workspace:7"}`. Plain form prints `OK surface:50 workspace:7`.
  Ref capture is direct; the tree-diff fallback is unnecessary.
- `--focus false` respected on `new-split` and `new-workspace` (no focus steal).
- Full command sweep — slot-REUSE primitives exist: `close-surface --surface <ref>`,
  **`respawn-pane [--surface <ref>] [--command <cmd>]`** (relaunch a command in an existing
  surface, in place — likely THE reuse mechanism), `send`/`send-key` (typing into the idle
  zsh — fragile, avoid). Also available: `new-pane --direction`, `move-surface`,
  `tab-action`, `set-status`/`set-progress`/`notify` (out of scope, noted).
- Refs are app-session-scoped shorts (`pane:30`; UUIDs via `--id-format both`). Either form
  dies with the cmux app process → **any persisted ref map must revalidate against live
  `tree` anyway** — directly undermines a persistent-slot-map approach.

## Approaches proposed (2026-07-21 — awaiting user pick)

**A. Smart cmux adapter, live-derived layout (RECOMMENDED).** Dispatcher exports an optional
role hint env var (e.g. `PANE_AGENT_ROLE=implementer|aux`); only `cmux.sh` reads it. Per
dispatch the adapter derives layout from `cmux --json tree` + a title convention (set via
`rename-tab --surface` at creation, e.g. `[impl:run-id] task`), then: reuse a finished slot
(`respawn-pane`/`close-surface`+`new-surface`), split progressively (1 → stack → 2x2), or
tab overflow (`new-surface --pane`). No persistent state; tree is ground truth; self-heals
on manual pane closes. Env-var hint = zero changes to other adapters and no `common.sh`
arg-validation churn. Cost: cmux.sh grows significantly; title convention is load-bearing;
needs jq (or python) for tree parsing.

**B. Persistent slot map in `state/workspaces/<ws>/slots.json`.** Explicit slot→ref map
written from `--json new-split` output. Killed by the round-3 finding: refs die on app
restart, so every read must revalidate against live tree — B degenerates into A plus a
cache with staleness bugs, plus the new-state/stale-cleanup burden, plus desync when the
user closes panes manually.

**C. Layout policy in dispatcher + new adapter primitives** (`open_pane_at <slot>`,
`open_tab_in <pane>`, `query_layout`). Adapter-agnostic policy, testable without cmux — but
widest blast radius (dispatcher + 4 adapters + both suites) and builds generality Q4
explicitly declined (cmux-only). YAGNI.

Recommendation rationale: A is the only option with zero new persistent state, honors Q4's
cmux-only scope, and the probe confirmed every primitive it needs.

## Constraints to carry into the design

- Degrade-never-block invariant from PR #23 stands (adapter failure → cooldown → in-process).
- Adapter contract change touches `dispatch-pane-agent.sh`, all 4 adapters' arg validation
  (`common.sh`), and both test suites.
- Per-workspace layout state (slot map) is new state — needs the same stale-cleanup treatment
  as `state/runs/`.
- Model-switch gate: user implicitly stayed on Fable 5 for the brainstorm (2026-07-21); the
  pre-implementation gate must still be asked separately when this reaches code.
