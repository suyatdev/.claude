# ADR 0008 — Aux column: correct position over correct height

**Status:** Accepted (2026-07-22)

## Context

The `pane-layout-v2` spec (`docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md`,
blob `aeb0074`, frozen because prior judge verdicts key off it) states assumption 4: dispatched
side agents — judges, the handoff pane, anything not a plan implementer — land in a **full-height
far-right column**.

That assumption **failed live**, twice, in two different ways:

1. **Task 8's smoke check** (2026-07-21): `new-pane --direction right` has no anchor flag and
   splits off the *current* pane, which is the caller's own far-left main session. The aux column
   landed **2nd from left**. Task 9 fixed the position by anchoring an explicit
   `new-split right --surface <max-index pane>`.
2. **Probe P8** (2026-07-22) exercised what Task 9 could not: aux creation against a *populated*
   2x2 implementer quadrant. Position was correct, but the anchor resolves to the max-`index`
   pane — the **bottom**-right quadrant cell — and a split inherits its anchor's container, so the
   column came out **half-height, bottom-right**. Confirmed visually by the user.

Aux height is therefore **ordering-dependent**: full-height when the column is created before any
quadrant exists (anchored on full-height main), half-height when created after.

## Options weighed

1. **Anchor on main (`new-pane` off the full-height leftmost pane)** — height always correct,
   position always wrong (2nd from left). This is Task 8's observed behaviour.
2. **Anchor on the rightmost pane (chosen)** — position always correct; height correct when the
   aux column predates the quadrant, half when it does not.
3. **Fix it properly — split at the workspace root so the column spans full height.** Not
   reachable from the cmux 0.64.20 CLI, on three independent grounds established by P8:
   - `workspace.panes` is a **flat** array (`index`, `ref`, `selected_surface_ref`,
     `surface_refs`, `surface_count`, `surfaces`). No nesting, no orientation, no geometry — so no
     pane can be identified as a root-level, hence full-height, child.
   - `new-split` and `new-pane` are both **pane-relative**; the new pane inherits its anchor's
     container, so height always follows the anchor.
   - `--placement dock`, the one true right-sidebar mechanism, is **disabled**:
     `Error: invalid_params: Dock placement is disabled`.
4. **`focus-pane` + `new-pane`** — P8's Correction 28 found `new-pane` *is* anchorable this way
   (it follows focus, contradicting Task 8's "unanchorable" note). Rejected: racier than
   `new-split --surface` because it mutates user-visible focus, and it does **not** solve height.

## Decision

Accept option 2 and treat half-height aux as a **documented limitation, not a defect**.

Position beats height because position is *always* wrong under option 1 while height is only
*sometimes* wrong under option 2 — and wrong only in the less common ordering, since the handoff
pane and both judges normally open before any implementer quadrant exists. The spec itself already
authorises this posture ("imperfect geometry, functional"). The frozen spec file is deliberately
left unedited; the deviation lives in `coding-memory/branches/pane-layout-v2.md` (probe P8) and
in the `layout_rightmost_surface` header comment.

## Consequences

- The far-right anchor is an **unverifiable heuristic**. P8 also falsified the earlier
  "`index` is left-to-right order" claim — with a real quadrant the order is impl.1, impl.**3**,
  impl.**2**, impl.4, a left-column pane sorting after a right-column one. `index` is traversal
  order over a flat array. Max-index landed in the rightmost column in every observed case and
  nothing better is exposed, so the logic is unchanged and only the misleading comment was fixed.
- **This is the change's main latent risk** (flagged by the implementation-stage observability
  judge, verdict `2026-07-22-feature-pane-layout-v2.md`): if a future cmux alters how it walks
  panes, the column quietly lands wrong and **all 170 tests still pass**, because every test
  drives a fake binary. Mitigation is procedural, not automated — re-run
  `panes/cmux-layout-probe.sh` after any cmux upgrade.
- Revisit if cmux ever re-enables dock placement or exposes pane geometry/nesting in
  `--json tree`; either one makes option 3 reachable and this ADR supersedable.
