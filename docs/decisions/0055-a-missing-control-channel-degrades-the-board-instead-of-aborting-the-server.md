# 0055 — A missing control channel degrades the board instead of aborting the server, and no surface is ever deduced

- **Status:** Accepted (2026-10-30)
- **Context:** `treko/channel.py` (new), `treko/server.py`, `treko/Treko.dc.html`. Full design,
  scenarios, acceptance criteria and measurements: `docs/features/treko-degraded-no-cmux.md`
  (criterion 16 is this record). Reverses the startup refusal that card 1
  (`treko-store-location`) deliberately left in place and flagged as deferred.
- **Note:** ADR number **0055** was confirmed free before writing:
  `git fetch -q origin && git log --all --name-only --pretty=format: -- 'docs/decisions/0055*'`
  prints nothing across every ref. This branch's own `docs/decisions/` stops at 0037 because it
  branched earlier; the highest number on any ref is 0054. Recorded as the command rather than a
  ref tally, because a tally ages the moment anyone fetches.

## Context

Before this change Treko could not run outside cmux. `bind_surface` raised `StartupAbort` on any of
four conditions and `main()` wrote the reason to stderr and returned `2`: nothing was served and
the browser never opened. The user asked which cards are in flight and got an exit code.

That withholds the part of Treko that carries its value — the board, the merge order, the blocked
filter, none of which needs a control channel — to protect two keystroke buttons (`clear`,
`handoff`). The page already knew how to degrade: it falls back to copyable text when it has no
token, and the `file://` path exercises that daily. Only the server half was missing.

The change is direction-pivoting because it **widens what the server does when it cannot verify its
control channel**: it binds a port and serves in a state it used to refuse. That is the whole risk.

## Decision

**1. A startup abort becomes a served, degraded page.** `bind_surface` (now in
`treko/channel.py:63`) raises `SurfaceUnavailable`, a subclass of `StartupAbort`
(`treko/channel.py:50`), carrying a `Reason`. `main()` catches only that subclass around only that
call (`treko/server.py:713-719`), writes the original message and a second
`degraded -- no control channel (<reason>)` line to stderr, and continues with `surface = None`.
Every other `StartupAbort` still reaches the handler at `treko/server.py:729` and exits `2`.

**2. All four conditions degrade, not just the unset case.** `surface_unset`, `probe_timeout`,
`probe_failed` and `cmux_unrunnable` (`treko/channel.py:31`). From the user's seat each means
"no control channel", and serving in all of them is what makes the board always appear. The
distinct reasons exist because "you are not in cmux" and "cmux is broken" have different fixes, so
the page names which one fired. The user ruled on this on 2026-08-23. The dispatch brief had named
three; the fourth (`OSError` from running the binary) is the same class of condition and is
included — if the user meant three, that is the line to correct.

**3. `clear` and `handoff` are refused by the server with `503 no_channel`.** The guard is the
first statement of `_run_send` (`treko/server.py:613-621`), keyed off `config["surface"] is None`
and placed before `confirm_surface`, so a degraded server spawns no `cmux` subprocess. It goes
through `_fail` (`treko/server.py:396`), so the body is `{"ok": false, "error": "no_channel"}` and
echoes no request content. `reanalyze` is a local command and stays live under the same token.
A hidden button is not an authorization control — the token is in the DOM and `POST /command` is
reachable by anything that can read the page — so the refusal lives on the server, not only in the
rendering.

**4. `503`, because every other candidate says something false.** `403` collapses with
`bad_token`, which the page answers with "reload", and reloading cannot help. `409` tells the user
their session ended when none ever existed. `501` is excluded by the existing status table
(`treko/server.py:373-374`). `502` means "tried and could not confirm"; nothing was tried. `503`
was unused and means what happened: the capability is absent from this server for its lifetime.

**5. No surface is ever deduced.** When `bind_surface` cannot prove the inherited UUID is a
terminal, `config["surface"]` is `None` — not a guess, not the first available surface, not the
parent's. The rationale at `treko/channel.py:66` is unchanged: a send aimed at a deduced surface
once reached a different live Claude session at exit 0, and the fix was to delete the inference.
Degraded mode serves with no surface rather than a plausible one.

**6. The page learns the state from a closed-enum meta.** `_serve_index` injects a second
`<meta name="tracker-channel">` beside the token (`treko/server.py:467-471`), whose content is
`CHANNEL_OK` (`treko/channel.py:47`) or a `Reason` member's `.value` — one of five fixed strings.
The page treats `channelOk` as a strict `=== 'ok'` (`treko/Treko.dc.html:610`) and maps the
reason through a `hasOwnProperty`-guarded table with a fixed fallback (`:464-466`), rendering
nothing from the attribute. `Reason` is a plain `Enum`, not a `str` mixin (`treko/channel.py:31`),
so `.value` is required at every boundary rather than correct by accident.

## Alternatives considered

- **Keep aborting, or degrade only the unset case.** Rejected: the first withholds the survey for a
  garnish; the second leaves a broken cmux or a wedged probe as an exit code with no board.
- **Deduce a surface so the buttons keep working.** Rejected outright, not deferred: it
  reintroduces the cross-session delivery this design exists to prevent.
- **Hide the buttons and leave the server unguarded.** Rejected: not an authorization control
  (see Decision 3).
- **Other ways to tell the page** — a capability field in the run payload (a persisted file would
  report whichever launch last wrote it), a `GET /channel` route (grows a deliberately closed
  surface and makes first render depend on a round-trip), or injecting the live id set (gives the
  page *what* but not *why*, so a reason meta returns). Detail in the card's D4.
- **Put the server's human message in the meta.** Rejected: those strings interpolate `CMUX_BIN`,
  `strerror` and a UUID, all environment-influenced, so the meta would be an injection gadget.
  The closed enum makes that unreachable by construction.

## Consequences

- **Added trust-boundary fact:** the page now receives one new server-generated value, and it is
  one of five fixed tokens. Auth, CSP, host and origin checks, the manifest, the audit format, the
  allowlist (`treko/server.py:70-79`) and the watchdog (`treko/server.py:660`) are unchanged: a
  narrower server, not a looser one. No route, manifest row or verb is added.
- **Fatal stays fatal** — bad or busy port, unmapped extension, unreadable index, store directory
  that is a file, corrupt legacy store. The property rests on one `except SurfaceUnavailable`;
  widening it to `StartupAbort` would silently turn all of those into served broken pages, so the
  card pins nine cases as the guard.
- **Risk — server guard skipped:** if the `503` guard were removed or moved after
  `confirm_surface`, every page-level test would still pass; only the "no subprocess was invoked"
  assertion can tell. Tests: `treko/test_degraded.py`.
- **Cost:** the 5-second probe now precedes a working board instead of an exit. Not a defect.
- **Operator visibility:** a degraded launch is announced on stderr twice and in the banner
  (`surface=none reason=…`, `treko/server.py:777-784`); the healthy banner is byte-identical to
  before.
- **Reversal cost:** adding a fifth reason is a spec change; re-introducing inference is
  prohibited by this record, not merely discouraged.
