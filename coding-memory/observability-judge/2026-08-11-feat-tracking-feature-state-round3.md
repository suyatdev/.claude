# Observability verdict — `feat/tracking-feature-state` (architecting, advisory) — round 3

- **Repo:** `tracking-feature-state` (worktree of `~/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `bd73da6060fc6483e42d85a8c6b700e6576deaf2`
- **Base:** `main`
- **Stage:** `architecting` — **advisory, `outcome: null` always; does not gate a PR on its own.**
  Only a fresh *implementation*-stage verdict satisfies `hooks/judge-guard.sh`.
- **Prior read judged:** `01f0c45` (round 2, 2026-08-11T18:32:13Z). This round covers the one
  commit since: `bd73da6` — "close the re-entry violation, and fix the derivation that undercounts."

## What was changed

One docs-only commit (`git show --stat bd73da6`: `docs/features/tracking-feature-state.md` +2/-2,
`docs/features/tracking-feature-state.spec.md` +30/-8 net, plus memory ledgers; no `task-tracker/*`
line moved). Three edits:

1. Task 8's entry stopped predicting `server.py` "will land near the 400-line target" in the future
   tense on a task already ticked closed. It now states the built size (694 lines), an explicit
   **Not scheduled**, and the named split (`serve_static.py`) — matching task 3's `analyze.py`
   precedent. This closes compliance round 1 (re-entry)'s `core-conduct/file-size-decision-unsurfaced`
   violation.
2. Task 8 gained a visible residual-work marker in both halves: ticked, but owing the
   `confirm_timeout` split in `confirm_surface()` as its own `server.py` commit before task 9's test.
3. **Replaced the reason-coverage derivation round 2 found broken.** The old form matched only
   `_fail("status", "error", "reason")` call sites and returned 14 pairs against 15 the server
   actually emits, silently dropping `502 send_failed` (a direct `audit(...)` call at
   `server.py:582`) — and the sentence after it pre-rationalized that exact blind spot. The new form
   reads both emitting shapes.

## Does it do what I wanted?

Yes, on both counts, and I re-derived every number myself rather than taking the commit's word:

- **Reason-coverage derivation, re-run from the card's own two-shape command:** 15 distinct
  `status reason` pairs, `403` → five (`bad_token`, `host_mismatch`, `origin_mismatch`,
  `path_escape`, `unknown_id`), `502` → two (`confirm_failed`, `send_failed`). Exact match to the
  commit's claim. `grep -n 'audit(' task-tracker/server.py` confirms `send_failed` really does go
  out through a bare `audit(...)` call at line 582, invisible to the old `_fail`-only pattern.
- **The `confirm_timeout` gap is real and precisely as described.** `confirm_surface()`
  (`server.py:236-252`) returns the single string `"unrunnable"` for both `subprocess.TimeoutExpired`
  and a non-zero `cmux tree` exit; the one call site that consumes it (`server.py:575`) maps
  `"unrunnable"` → `reason="confirm_failed"` unconditionally. `confirm_timeout` does not appear
  anywhere in the 15 emitted pairs — consistent with "specified in four places, cannot currently be
  emitted." The task-8 marker added this round accurately describes an open, correctly-scoped defer.
- **Acceptance-criteria count, re-run:** `awk` over `## Acceptance criteria` → **15**, matching the
  `.md` half's claim.
- **Line counts, re-run with the correct glob:** `.md` = 216 (over the ≤200 waived cap by 16 lines,
  "a handful"), `.spec.md` = 1530 (over the ≤800 waived cap; +24 lines since round 2's 1506 reading —
  continued incremental growth under a live, twice-reconfirmed waiver, not a fresh violation).
- Spot-checked line citations against source and all landed exactly: `BABEL_URL` at
  `support.js:1147`; two `new Function` sites (`support.js:844,1218`); `ensureBabel()` reachable only
  via `kind === "jsx"`; zero `x-import` occurrences in the served HTML and the `_ds` bundle (so
  `babel.min.js` genuinely cannot be requested by any current view); manifest table = 16 rows,
  extensions = `js`×9, `css`×4, `woff2`×3 (no `html`), matching the card's claims exactly.

## What could go wrong / what I'm unsure about

Weighting "the text that was just edited to fix something," per this card's own repeated lesson —
here is what I found there:

1. **The new two-shape derivation still has a blind spot: it is line-oriented, not call-oriented.**
   Both regexes require the status/error/reason arguments to appear on the *same source line* as the
   opening paren (`_fail\([0-9]+, "…", "…"` / `audit\("…", [0-9]+, reason="…"`). I confirmed several
   real `_fail(...)` calls in `server.py` already wrap onto a second line (e.g. lines 427, 450, 463,
   466, 560, 572, 575) — every one of them currently keeps its first three arguments on the *opening*
   line, so today's count is unaffected. But nothing enforces that convention: a future edit that
   wraps before the third argument (e.g. `self._fail(\n    500, "…", "…", …)`) would silently vanish
   from this derivation exactly the way `send_failed` silently vanished from the old one — same
   species of bug, one level down. This is not a live defect, but it is the same class of risk the
   card explicitly names elsewhere ("a text search can only ever approximate a runtime/code
   property... a wrongly-scoped one returns cleanly and looks exactly like a correct result") and
   this specific derivation was never checked against that standard.
2. **Task 13's plan for criterion 15 has no computational floor — it can pass while under-reporting.**
   The `.md` half correctly instructs that on a node-less host task 13 must report criterion 15 as
   "not verified," not "skipped-therefore-fine," because (unlike criterion 5) it has no unguarded
   Python sibling. I checked for any enforcement mechanism (a script, a marker, a hook) that would
   force that distinction into the record — there is none. `pytest`'s own output is just "N passed, M
   skipped"; nothing stops task 13 from pasting that bare number without the required qualitative
   sentence, which is exactly the "green suite implying coverage" failure the card warns against one
   paragraph earlier. The design is correct about what *should* happen; nothing yet makes it happen.
3. Both size waivers remain live and both halves continue growing under them — not disqualifying
   (the waivers were re-confirmed twice on the stated ground that only the session-start half's size
   controls the actual budget), but worth a fresh look if growth continues past "a handful of lines."
4. The compliance judge has not yet re-run against this exact commit (`bd73da6`); its last verdict
   (round 1 re-entry, `01f0c45`) is the one this commit's first edit was written to satisfy, but that
   closure is unverified by the compliance judge itself as of this read. Not a defect of this commit,
   but an open loop before the next gate.

## What I'd double-check before merging (or before the next round)

- Before trusting the reason-coverage derivation again, re-run it and specifically diff it against a
  manual read of every `_fail(`/`audit(` call site — the way I just did — rather than trusting a
  clean return; the class of bug here is a scope failure that returns cleanly.
- Task 9, when written, should assert `confirm_timeout` is actually emittable (post the code fix) and
  should not merely read the enum prose.
- Task 13 should be given (or should give itself) an explicit written line distinguishing "criterion
  5: partially verified without a JS-engine oracle" from "criterion 15: not verified" rather than a
  bare pass/skip count, on any host missing `node`.
- Run the compliance judge against `bd73da6` to close the loop this commit opened.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Fixes exactly the compliance violation and the prior observability finding, nothing else |
| execution | pass | Docs-only (`Doc-Exempt`, legitimate); every re-derivable claim checked out against source |
| trajectory | pass | Root-cause fix (read both emitting shapes) not a patched list; verified before writing per the card's own discipline |
| regression | pass | No source touched |
| context_budget | concern | Both halves remain over ADR 0017 caps under a live, twice-reconfirmed waiver; `.spec.md` +24 lines since last read — incremental, not alarming, but the waiver's own text says to re-raise if this continues |
| traceability | pass | Every claim carries a re-derivation command; commit message names the exact prior verdict it responds to |
| success_masking | concern | (1) the new two-shape derivation has an unaddressed line-wrap blind spot, latent not live; (2) task 13's criterion-15 reporting plan has no computational enforcement — it can under-report a real coverage gap and nothing would catch it |
| intent_drift | pass | No unrelated edits, no drive-by changes, no new dependency |
| checkpoint | pass | Single coherent commit, trivially revertible |
| audit_trail | pass | Commit message attributes reasoning to the specific prior verdict; no fresh structural decision needing its own ADR |

**Risk: low. Confidence: high** — every cited number, line, and code claim was independently re-run
from source this round, not taken from the commit or from the prior verdict.

## Concerns

- New two-shape reason-coverage derivation is line-oriented and would silently undercount again if a
  future `_fail(`/`audit(` call wraps before its third argument — not live today, but unguarded.
- Task 13's criterion-15 "not verified" reporting requirement has no computational check; a bare
  pytest skip count could satisfy the letter of the task while omitting the required distinction.
- Both size waivers (`.md` 216/≤200, `.spec.md` 1530/≤800) remain live; `.spec.md` grew +24 lines
  since the last read — watch the trend, not a fresh violation this round.
- Compliance judge has not yet re-verified `bd73da6` itself; its round-1-re-entry FAIL is the one this
  commit's first edit closes, but that closure is self-reported until re-run.
