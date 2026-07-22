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
it became wrong**: every adapter assertion drives a *fake* cmux binary, so a real cmux that walks
panes differently would mis-place the aux column with the entire suite green.

The geometry cannot be self-checked — the tree exposes none. The **release** can.

## What landed

`check_cmux_version` in `panes/adapters/cmux.sh`, plus `LAYOUT_VERIFIED_CMUX_VERSION="0.64.20"`.

- Runs **once per dispatch**, before the derive/execute retry loop — the retry arm re-derives, and
  a second identical warning would read as two separate problems.
- **Mismatch** → a two-line stderr warning naming both versions, plus a receipt at
  `$PANE_STATE_DIR/cmux-version-mismatch` reading `found <v>, verified <pin>`.
- **Match** → the receipt is *deleted*. Its presence therefore means "wrong **now**", not "wrong
  once".
- **Unreadable** → silent on stderr, but a receipt reading `unreadable version output: <line>`.
  Screen silence exists so a changed `version` output shape cannot cry wolf every dispatch; going
  silent *forever* is how an alarm dies unnoticed, so the receipt is written regardless.
- **Warns, never degrades.** An upgrade silently switching the layout off is precisely the failure
  this guards against, and a version bump is not itself evidence of breakage.

### Parsing: version-SHAPED, not version-CLEAN

`case "$found" in [0-9]*.[0-9]*)` — starts with a digit and contains a dot.

**The first implementation got this wrong** and required `[0-9.]` only. Its round-1 judge probed
nine version strings and found `0.65.0-rc1` and `0.64.20-beta` produced **no warning and no
receipt**: a suffixed version was filed under *unreadable* rather than *mismatch*, making the
alarm deafest to pre-release builds — one of the likeliest ways to land on a cmux whose behaviour
moved. Round 2 re-probed with 28 strings and confirmed the fix: `-rc1`, `-beta`, `-dirty`,
`SNAPSHOT+build.7`, date-style `2026.07.01` and near-miss `0.64.2` all warn; garbage and empty
stay quiet.

Deliberate boundary calls, both endorsed by the round-2 judge:

- bare `100` → *unreadable*. Correct: cmux's own version line already contains a bare integer
  (the build number), so accepting one would misparse.
- `v0.65.0` → *unreadable*, left as-is. Accepting a `v` prefix would make `v0.64.20` compare
  unequal to the pin `0.64.20` and cry wolf on the very release that is verified. If this ever
  matters, fix it with **normalization**, not a wider shape test.

### Receipt writes are braced

`{ printf … > "$marker"; } 2>/dev/null`, not `printf … > "$marker" 2>/dev/null`. The latter does
**not** suppress a failing *redirection* — the shell reports it before the trailing `2>/dev/null`
applies — so an unwritable state dir printed `Permission denied` on every dispatch, on the one
path documented as silent. Found by the round-2 judge. `run-pane-agent.sh:81` already documents
this exact trap; the first implementation walked into it anyway.

## Scope: one item and part of a second

The round-2 judge on the parent branch framed this as *"one detector closes two open items"*, and
an earlier draft of this log repeated it. It closes **one item and part of a second**: a
*version-driven* degrade now leaves a persistent signal, but every other degrade path
(`tree call failed`, `tree unparseable`, `derivation failed`, `jq missing`) still emits one stderr
line and no receipt. The judge flagged its own wording as the source — recorded so it does not
calcify.

## Deliberately NOT done

- **Not wired into the `PANE_DRYRUN` path.** Moving the check before that early exit would call the
  real binary during `adapters.test.sh` wherever `PANE_CMUX_BIN` is unset — the cross-machine
  fragility that block's own comment documents. `panes/cmux-layout-probe.sh` already prints the
  version, so the preview case is covered by the tool built for it. Judge-endorsed.
- **No reader for the receipt.** Nothing opens `$PANE_STATE_DIR/cmux-version-mismatch`; it is
  forensics, not notification, and the *unreadable* receipt is invisible by construction. Both
  judges flagged this; the cheapest real reader is the statusline. **Open follow-up.**
- **No once-per-session suppression.** Any mismatch warns on every dispatch until a human edits the
  pin. Deliberate: suppression would hide the warning from exactly the dispatch that mis-placed a
  pane. Judge-endorsed. Caveat: `0.64.20-rc1` warns forever against a `0.64.20` pin.

## Verification

**Suite 170 → 195** (`cmux-exec.test.sh` 54 → 79), shellcheck clean.

The setup for these cases is a **genuinely succeeding layout path** (slot 1 created, stamped, and
verified against the second tree read), not the legacy floor. The first draft used `T_EMPTY` +
`split_ok`, which degrades to legacy and returns `surface:42` — so "a version mismatch still
dispatches" passed while proving nothing. A `version-gate baseline reaches the layout path` case
now guards that: if it ever fails, every assertion below it is measuring the legacy floor.

Two receipt assertions were later **tightened from substring to kind** (`^found <v>, verified …`
and `^unreadable version output:`). As written first they checked only that the version string
appeared *somewhere* in the receipt — and the unreadable receipt copies the whole version line,
which contains it, so both passed with the bug reinstated. Round-2 judge's catch.

The unwritable-state-dir case also passed **vacuously** on first write: `PANE_STATE_DIR` was
repointed without moving the launcher, so `validate_open_pane_args` rejected the path and the run
aborted before the version check ever executed.

### Falsification — all six single-anchor, syntax-valid, non-empty diff

Regenerated after the round-2 fixes; an earlier table in this file quoted a `73/4` row that did
not reproduce, because that mutation was compound.

| Mutation | Result (baseline 79/0) |
|---|---|
| pin `0.64.20` → `0.65.0` | **73/6** RED |
| check never called | **65/14** RED |
| filter back to version-CLEAN (the round-1 bug) | **75/4** RED |
| stale receipt never cleared | **78/1** RED |
| no receipt on unreadable output | **77/2** RED |
| mismatch receipt write unbraced | **78/1** RED |

Restored from a `cp` backup, **never `git checkout --`** (which restores from HEAD and once
destroyed uncommitted work mid-falsification on the parent branch). A seventh mutation — deleting
the unreadable-receipt line outright — was **discarded, not recorded as evidence**: it broke the
enclosing `case` statement, so its 61 failures were a parse error rather than discrimination.

Live: the real binary reports `cmux 0.64.20 (100) [14e3400b9]`, matching the pin, so every real
dispatch this session stayed silent — including the ones that launched the judges.
