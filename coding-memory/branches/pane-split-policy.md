# Branch: feat/pane-split-policy

Session pane-split policy. At the first pane-eligible dispatch the model asks once:
`inline` (all in-process this session) or `panes max=N` (N concurrent worker panes;
spawns beyond N open as **tabs inside existing panes**, round-robin — never inline/blocked).
Three-lane governance model: read-only `Explore`/`Plan` always in-process; the two judges
always paned, *outside* the policy; only the worker fan-out is policy-governed.

- Spec: `docs/superpowers/specs/2026-07-22-pane-split-policy-design.md` (locked, blob `cdc777a`)
- Plan: `docs/superpowers/plans/2026-07-23-pane-split-policy.md` (8 TDD tasks)
- Gates answered (do not re-ask this branch's execution): Opus 4.8 (1M) implementation,
  subagent-driven execution (pane-routed implementers, inherit `opus[1m]` from settings.json).

## Task 1 — cmux tab probe (2026-07-23, live on real cmux, operator-run) — PASS

**`new-surface --pane <pane-ref>` IS the `open_tab` primitive: an in-pane tab, not a new
window or workspace.** So the spec's core mechanism ("spawns beyond N open as tabs inside
existing panes") is achievable with cmux as-is.

- Probe: `panes/cmux-tab-probe.sh` (re-runnable; run it after any cmux upgrade before trusting
  `cmux.sh open_tab`).
- Fixture: `panes/adapters/fixtures/tab-live.json` (scratch-workspace tree; titles `Terminal`
  + `tab-probe-scratch` only — no real paths/titles).
- cmux at probe time: `0.64.20 (100) [14e3400b9]` (matches the version pinned in the sibling
  orchestration / layout-v2 specs). Bin: `/Applications/cmux.app/Contents/Resources/bin/cmux`.

### The exact primitive Task 5 must use
- **Create the tab:** `cmux --json new-surface --pane <pane-ref> --workspace <ws-ref>`
  → returns JSON `{"pane_ref":"pane:N","surface_ref":"surface:M","type":"terminal",
  "window_ref":"window:N","workspace_ref":"workspace:N"}`. Extract `.surface_ref` for the new tab.
- **Launch the agent in the tab:** `cmux send --workspace <ws-ref> --surface <new-surface-ref> -- "<launcher>\n"`
  — confirmed live (Q3 below). Same send-to-surface path layout-v2's reuse (P4) already proved.

### Evidence (two live runs)
- Run 1 tree AFTER new-surface: `pane:31 / surface:64` (base) + `pane:31 / surface:65` (new) —
  both share `pane:31`, `window:1`, `workspace:9`.
- Run 2 (captured as the fixture): `pane:36 / surface:77` + `pane:36 / surface:78` — same,
  both in `pane:36`.
- Visual confirmation (run 2 VISUAL CHECK, operator-reported):
  - **Q1:** exactly ONE new workspace appeared (`tab-probe-scratch`).
  - **Q2:** pane `pane:36` shows TWO tabs.
  - **Q3:** `TAB_SEND_OK` printed inside the new tab.

### GOTCHA for re-runners (cost the first run a misread)
The probe creates a scratch workspace in T1 and cmux may not auto-focus it, so the new tab
appears "in a new workspace" from the operator's seat. That workspace IS `tab-probe-scratch`
— NOT evidence that `new-surface` spawns a workspace per tab. Switch into `tab-probe-scratch`
and count tabs in the pane (Q2). The VISUAL CHECK block in the probe was added after run 1
misread exactly this way.

### Feeds Task 4/5 — surface→pane resolution (decide in `validate_open_tab_args`)
`new-surface --pane` needs a **pane-ref**, but the overflow round-robin (`pane-rr-<key>`, Task 7)
selects a target *worker*, which the dispatcher tracks by its **surface** (`CMUX_SURFACE_ID`).
So `open_tab` must resolve the target's surface-ref → its `pane_ref` (the `norm` selector
already yields `pane_ref` per surface) before calling `new-surface --pane <pane_ref>` — unless
Task 4 chooses to accept a pane-ref directly. Either way the adapter call ends in
`new-surface --pane <pane_ref>`, and the caller-supplied ref stays under the frozen
no-interpolation + allowlist boundary the spec inherits from the orchestration spec.
