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
  panes, the column quietly lands wrong and **all tests still pass**, because every test drives a
  fake binary.
- **Mitigated 2026-07-22 by a version gate** (`check_cmux_version` in `panes/adapters/cmux.sh`,
  round-2 judge's top follow-up). `LAYOUT_VERIFIED_CMUX_VERSION` pins the one release all of this
  was verified against; every dispatch compares the live `cmux version` against it and, on a
  mismatch, prints a two-line warning naming both versions and writes a receipt at
  `$PANE_STATE_DIR/cmux-version-mismatch`. A **matching** version deletes that receipt, so its
  presence means "wrong now", not "wrong once"; an **unreadable** version stays silent on stderr
  (a changed `version` shape must not cry wolf every dispatch) but still leaves a receipt, because
  an alarm that goes quiet forever is indistinguishable from a happy one. The version test is
  deliberately *shaped* (`[0-9]*.[0-9]*`) rather than *clean*: an earlier `[0-9.]`-only filter
  silently swallowed `0.65.0-rc1` and `0.64.20-beta`, the pre-release builds most likely to have
  moved behaviour. It **warns and never degrades** — an upgrade silently switching the layout off
  is the failure being guarded against, and a version bump is not itself evidence of breakage.
  Nothing yet *reads* the receipt; it is forensics, not notification (open follow-up: a statusline
  reader). This detects the *trigger*, not the *defect*: a geometric
  self-check remains impossible while the tree exposes no geometry, so re-running
  `panes/cmux-layout-probe.sh` after an upgrade is still the confirming step.
- Revisit if cmux ever re-enables dock placement or exposes pane geometry/nesting in
  `--json tree`; either one makes option 3 reachable and this ADR supersedable.
