# feature/cmux-version-gate

Post-merge follow-up to PR #25 (pane-layout-v2), and the round-2 observability judge's
top-ranked item: *"the trigger is trivially detectable and wasn't wired up… one small detector
closes two open items."*

## Why

`layout_rightmost_surface` anchors the aux column on the max-`index` pane. Probe P8 falsified the
belief that `index` is visual left-to-right order — it is traversal order over a flat pane array
(Correction 27). The anchor held in every observed case and nothing better is exposed, so it
shipped as an acknowledged heuristic (ADR 0008).

The problem was never that the heuristic is wrong today. It is that **nothing could tell you when
it became wrong**: every one of the 170 adapter assertions drives a *fake* cmux binary, so a real
cmux that walks panes differently would mis-place the aux column with the entire suite green.

The geometry cannot be self-checked — the tree exposes none. The **release** can.

## What landed

`check_cmux_version` in `panes/adapters/cmux.sh`, plus `LAYOUT_VERIFIED_CMUX_VERSION="0.64.20"`.

- Runs **once per dispatch**, before the derive/execute retry loop — the retry arm re-derives, and
  a second identical warning would read as two separate problems.
- On mismatch: a **two-line** stderr warning naming both the found and the verified version, plus
  a durable marker at `$PANE_STATE_DIR/cmux-version-mismatch`. The marker is the part that
  survives the scrollback.
- **Scope correction.** The round-2 judge framed this as *"one detector closes two open items"* and
  this log repeated it. It closes **one item and part of a second**: a *version-driven* degrade now
  leaves a persistent signal, but every other degrade path (`tree call failed`, `tree unparseable`,
  `derivation failed`, `jq missing`) still emits one stderr line and no receipt. The judge flagged
  its own wording as the source of the overstatement — recorded here so it does not calcify.
- **Warns, never degrades.** An upgrade silently switching the layout off is precisely the failure
  this guards against, and a version bump is not itself evidence of breakage.
- **Fails open** on anything unreadable — non-zero exit, empty output, or a field 2 that no longer
  looks like a version. A changed `version` output shape must not cry wolf on every dispatch.

Parsing is deliberately narrow: `cmux 0.64.20 (100) [14e3400b9]` → field 2, accepted only if it
matches `[0-9.]+`. Anything else is treated as *unreadable*, never as a *mismatch*.

## Deliberately NOT done

**The check does not run on the `PANE_DRYRUN` path.** Moving it before that early-exit would call
the real binary during `adapters.test.sh` on machines where `PANE_CMUX_BIN` is unset — the exact
cross-machine fragility the dryrun block's own comment documents. `panes/cmux-layout-probe.sh`
already prints the cmux version, so the preview case is covered by the tool built for it.

## Verification

16 new assertions in `cmux-exec.test.sh` (54 → 70; suite total 170 → 186), shellcheck clean.

The setup for these cases is a **genuinely succeeding layout path** (slot 1 created, stamped, and
verified against the second tree read), not the legacy floor. The first draft used `T_EMPTY` +
`split_ok`, which degraded to legacy and returned `surface:42` — so "a version mismatch still
dispatches" passed while proving nothing. A `version-gate baseline reaches the layout path` case
now guards that: if it ever fails, every assertion below it is measuring the legacy floor.

**Falsified with four mutations, each verified to change exactly one anchor and produce a
non-empty diff** (a no-op mutation reads exactly like a passing falsification — this branch's
recurring trap):

| Mutation | Result |
|---|---|
| pin `0.64.20` → `0.65.0` | 66/4 RED |
| drop the durable marker write | 68/2 RED |
| drop the second (louder) warning line | 69/1 RED |
| never call the check | 66/4 RED |

Restored from a `cp` backup, **never `git checkout --`** (which restores from HEAD and once
destroyed uncommitted work mid-falsification on the parent branch).

Live sanity: the real binary reports `cmux 0.64.20 (100) [14e3400b9]`, matching the pin, so real
dispatches stay silent.
