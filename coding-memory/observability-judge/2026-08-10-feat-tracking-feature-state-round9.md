# Observability verdict — round 9 (architecting, advisory)

- **repo:** `tracking-feature-state` (worktree of `~/.claude`)
- **branch:** `feat/tracking-feature-state`
- **head_sha:** `4775afd4e09392415a074a4c2dde6e34db6f0521`
- **base:** `main` (11 ahead / 5 behind)
- **stage:** `architecting` — advisory, does not block
- **ts:** 2026-08-10T15:28:51Z
- **artifact:** `docs/features/tracking-feature-state.md` (1204 lines, ~22.5k tokens)

> ⚠️ **Leads with a `fail`:** `context_budget`. Nothing about the design's correctness or safety
> is failing — that part is the strongest it has ever been. What is failing is the container.

---

## What was changed

Two compliance findings were closed in the feature card, both spec-only:

1. **Task 14's vendoring was unbounded**, so a correct implementation would have failed the card's
   own acceptance test. It now carries a recorded scope decision (`.woff2` only, `latin` only) and
   nine enumerated manifest rows, mirrored exactly into criterion 13's expected request set.
2. **The send-time identity check had no failure behaviour.** It is now anchored to the inherited
   `$CMUX_SURFACE_ID`, with three startup aborts, three tabulated send-time outcomes, two new audit
   `reason` values, and six matching assertions added to task 9 *in the same edit*.

Round 8's four bare `file:NN` citations were also repaired. No source file was touched, no
dependency added, no test changed.

## Does it do what was intended?

Yes, and the evidence is unusually good. **I re-ran every measurement the round claims and all eight
reproduced exactly**, against live sources, today, from a different session:

| Claim in card | My independent check | Result |
|---|---|---|
| Phosphor declares 4 `src` formats per stylesheet | `curl` unpkg regular + fill `style.css` | ✅ `woff2`, `woff`, `ttf`, `svg` |
| Font filenames `Phosphor.woff2` / `Phosphor-Fill.woff2`, relative `./` | same fetch | ✅ exact, manifest rows match |
| Inter: 28 references → 7 distinct files | `curl` with browser UA + `sort -u` | ✅ 28 and 7 |
| `$CMUX_SURFACE_ID` is a bare UUID | `echo $CMUX_SURFACE_ID` | ✅ `F825C3D3-…` |
| appears exactly once in `cmux tree --id-format both` | `grep -c` | ✅ `1` |
| `read-screen` exits 0 against it | ran it | ✅ `exit=0` |
| `support.js` is the page's first script, line 6 | `grep -n '<script'` | ✅ line 6 |
| phosphor `<link>`s at lines 13–14 | `grep -n phosphor` | ✅ 13, 14 |
| suite reports 53 passed | `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` | ✅ **53 passed in 3.86s** |
| Toolchain pins | `python3 -V`, `uv --version`, `node --version`, `cmux --version` | ✅ 3.9.6 / 0.11.28 / v26.5.0 / 0.64.20 (100) [14e3400b9] |

Not one overclaim. After a card whose recurring defect species was *a stored result that had gone
stale*, this is the round where the measurements are simply correct.

**Answering the three questions put to me:**

- **Are the new error tables observable?** Yes — cleanly. Behind the single `502` the log
  distinguishes `reason=confirm_failed`, `reason=confirm_timeout` and `reason=send_failed`, and
  `sent=` adds a second independent discriminator (`no` for both confirm failures, because nothing
  was invoked; `unknown` only when `cmux send` actually ran and did not exit 0). An operator can
  reconstruct which of the three happened from one line. This is the best-designed part of the round.
- **Is criterion 13's font framing honest?** Yes, and correctly stated. "A browser fetches a
  `@font-face` file only when a glyph in that face is actually laid out" is accurate, and the
  consequence is stated without softening: an absent row means *either* the file is missing *or* no
  such glyph rendered, and set equality cannot tell them apart. One residual gap below.
- **`analyze.py` at 792/800:** confirmed. The split is named (`git_facts.py`) and correctly left
  unscheduled as a human-owned call. Fine as-is; it is 8 lines from a hard stop, so the next edit to
  that file forces the decision.

## What could go wrong / what I'm unsure about

### 1. `context_budget` — **fail**

The card has grown on **every single commit** since planning opened, fourteen in a row, never once
net-negative:

```
189 → 222 → 262 → 283 → 286 → 544 → 662 → 752 → 851 → 901 → 933 → 1001 → 1080 → 1204
```

This round is the diagnostic one. A deliberate, judge-requested trim *was* applied (~55 lines of
round-forensics prose removed, revision history compressed to 8 lines) — **and the file still grew
124 lines.** The corrective action was taken and the metric moved the wrong way. Six consecutive
judges have scored this `concern`; a signal sent six times that changes nothing has stopped being a
signal, which is why I am escalating it rather than repeating it.

The cost is concrete, not theoretical. `rules/gates.md` restore discipline loads the active feature
file on every restore. That is now **~22.5k tokens, every session, with 7 of 14 tasks left to go** —
roughly 15× the entire handoff budget (≤1,500 tokens) that the same rule imposes on the document
whose job is to be short.

To be fair about cause: **the content added this round was justified.** Nine enumerated manifest
rows and two error tables were exactly what the compliance findings required, and writing less would
have been worse. That is precisely why "add less" is not the remedy. The remedy is structural, and
the repo's own one-canonical-file rule already authorises it — a `<name>.spec.md` split **MAY** be
taken "when the checklist file stops reading comfortably in one pass." At 1204 lines that condition
was met several rounds ago, and the escape hatch has gone unused through six flagged rounds. The
`fail` is for the unexercised remedy, not for the prose.

### 2. `success_masking` — concern (repeat, second consecutive round)

Two specified controls have **zero assertions anywhere** — no criterion, no task-9 bullet:

- **`X-Content-Type-Options: nosniff`** — specified at card:281, built per task 8 at card:931, and
  checked by nothing. Criterion 13 asserts `Content-Type` and does not mention `nosniff`.
- **The unmapped-extension startup abort** (card:287–291) — "a manifest row whose extension is
  absent from that map … **aborts at startup**". Round 8 flagged this by name. It is unchanged.

This is the card's own named recurring shape — *a control described in prose and never once run* —
still open one paragraph away from the reasoning that says such controls must be asserted. The round
got this right for the six new surface-binding controls and missed it for these two.

There is also a **log-format gap that makes a task-9 assertion unwritable.** The audit line format
(card:388) carries exactly `id`, `surface`, `sent`, `status`, `reason`. But card:362 says
`asset_unreadable` must "Log the path and the `errno`", and task 9 (card:946) requires "an audit line
naming the path and `errno`" — **two fields the specified format does not have.** Relatedly, the
`reason` enumeration is written as closed ("Values: …") but is not exhaustive against the wire
contract: `not_found` (404), `method_not_allowed` (405) and `asset_unreadable` (500) have no value,
while "one line per request" guarantees those lines exist. Criterion 13's run (a) *expects two 404s*
(`/tracker-data.js`, `/favicon.ico`), so the very first accepted run of this server emits two audit
lines whose `reason=` the card does not define. This round edited that exact enumeration (adding
`confirm_failed`/`confirm_timeout`) and did not close it. The risk is the classic one: with no
contract to assert against, the test gets written to match whatever the implementation happened to
do, and passes by construction.

Finally, the standing structural risk: **criterion 13 is the linchpin of four rounds of fixes and is
the check least likely to actually get run.** It needs an operator, a connected browser extension,
two store states, and the right view on screen; it does not run under `pytest` and does not run
unattended. The card is admirably honest about this cost. The consequence still stands — the suite
can be fully green with the manifest wrong, the content types wrong and the CSP unverified.

### 3. A specific hole in criterion 13's expected set

`/vendor/phosphor/fill/Phosphor-Fill.woff2` is expected `200` in **both** runs. Reading the source,
`ph-fill` appears in only four places in `Task Tracker.dc.html` — the "Nothing left — run complete"
empty state (:243), *done* checklist items (:394), the *copied* button state (:399), and *resolved*
questions (:437). So that font is fetched only if one of those specific states renders.

I checked `tracker-data.sample.js`: it does contain `"done": true` and `"resolved": true`, so run (a)
will probably request it. But the card's instruction to the operator says only "the icon-bearing view
on screen" — which is satisfiable with regular icons alone, leaving the fill row absent and criterion
13 failing on something that is not a vendoring defect. Given set equality is the pass condition,
that instruction should name the *fill*-bearing state specifically.

### 4. Minor traceability residual

Round 8's four bare `file:NN` citations are genuinely fixed — I grepped, there are none. One
decorative line number remains without a re-find command: card:1020, "inserted **ahead of line 6's
`support.js`**". Task 14's own action (inserting a script above line 6) guarantees that number goes
wrong. It is low-severity — the instruction is relative ("ahead of `support.js`") so it is
self-correcting, and card:296 carries the grep — but it is the same species the card names as its
own recurring failure.

## What I'd double-check before merging

1. **Take the `<name>.spec.md` split before task 8 starts.** Frontmatter + the 14-item checklist stay
   in the `.md`; §Design, §Security, §Injection route, §Acceptance criteria move to the `.spec.md`,
   read on demand. This is a MAY in the rules and I would exercise it now — every remaining task is
   an implementation task that will re-read this file from a fresh session.
2. **Add two assertions to task 9**: `nosniff` on a static response, and the startup abort for a
   manifest row whose extension is not in the map. Both are one line each and both have now been
   flagged twice.
3. **Fix the audit-line contract before task 8**: add `path=`/`errno=` fields (or say explicitly that
   `asset_unreadable` logs a second detail line), and extend the `reason` enumeration to cover
   `not_found`, `method_not_allowed` and `asset_unreadable` — otherwise task 9's own bullet cannot be
   satisfied against a contract.
4. **Name the fill-icon state in criterion 13's operator instruction**, not just "the icon-bearing
   view".
5. **Get explicit user sign-off on the `latin`-only Inter subset** at the gate. It is a visible
   product trade (non-Latin glyphs fall back to the system stack), correctly recorded with its
   alternative, but it is a user-owned call, not an implementation one. Carried from round 8.

## Dimension table

| Dimension | Verdict | Reasoning |
|---|---|---|
| `intent` | **pass** | Both escalated compliance ids closed with substantive, measured content — not paraphrase. Task 14's scope is now a decision with its measurement; the send-time check has real failure behaviour. |
| `execution` | **pass** | Upgraded from round 8's concern. 53/53 pass on the pinned invocation. All eight card measurements reproduced independently against live sources; every toolchain pin matches this host exactly. |
| `trajectory` | **pass** | Sound, not lucky. The round replaced a placeholder manifest row *because* it reasoned that a placeholder makes the acceptance test a transcript of the implementation and cannot fail — the right species of reasoning. Six task-9 assertions landed in the same edit as the controls they cover, which is the correct fix for the card's own named recurring failure. |
| `regression` | **pass** | Docs and memory only (`git diff --stat ca3e079..HEAD`); no source, no tests, no deps. Suite green. Round 8's concern that task 14 would append to the manifest mid-implementation — a spec edit the phase gate forbids — is closed: the nine rows are fixed in advance. |
| `context_budget` | **fail** | 1080 → 1204 (~22.5k tokens), fourteenth consecutive growth commit, sixth consecutive judge flag. A targeted trim was applied this round and the file still grew 124 lines. Loaded on every restore per restore discipline, with 7 of 14 tasks remaining. The repo's own rules authorise a `.spec.md` split; it has not been taken. |
| `traceability` | **pass** | Upgraded from round 8's concern. Round 8's four bare `file:NN` citations are gone — verified by grep — and every citation I checked carries a `grep` that re-finds it and resolves correctly against source. Residual: one decorative "line 6" at card:1020 with no re-find, which task 14 guarantees will go stale. |
| `success_masking` | **concern** | `nosniff` and the unmapped-extension startup abort are specified and asserted nowhere (the latter flagged in round 8, unchanged). The audit format cannot carry the `path`/`errno` that task 9 requires it to assert, and the `reason` enumeration omits three wire outcomes including two that criterion 13 expects on first run. Criterion 13 remains the linchpin check that does not run under `pytest` or unattended. |
| `intent_drift` | **pass** | Strictly scoped to the two escalated ids plus the round-8 citation repairs. No dependency added, no source edit, no drive-by cleanup. The `latin`-only trade is *proposed* in a planning-phase spec with its alternative named — the right shape, pending the gate. |
| `checkpoint` | **pass** | Working tree clean, HEAD stable at `4775afd` throughout this review (unlike round 8, where HEAD moved mid-read). One concern per commit; `git revert 4775afd` is a clean docs-only rollback that leaves tasks 1–7 and the task-1 probe evidence intact. |
| `audit_trail` | **pass** | Strong. ADRs 0022/0023/0024 carry the structural decisions; both judges' verdicts and the compliance markdown are committed; §Revision history correctly delegates to git rather than keeping an eleventh copy of a fact that has gone stale ten times. Task 1's mis-delivery incident is recorded rather than tidied away — the single most valuable line in the document. |

## Concerns

1. `context_budget` **fail** — card grew 1080→1204 (~22.5k tokens) *after* an applied trim; 14th consecutive growth commit, 6th consecutive flag; loaded every restore with 7 of 14 tasks left; the authorised `.spec.md` split remains untaken
2. `X-Content-Type-Options: nosniff` is specified (card:281, :931) and asserted by no criterion and no task-9 bullet
3. Unmapped-extension startup abort (card:287–291) still asserted nowhere — flagged in round 8, unchanged
4. Audit line format (card:388) has no `path=`/`errno=` field, so task 9's required "audit line naming the path and errno" for `asset_unreadable` cannot be asserted against a contract
5. `reason` enumeration is written closed but omits `not_found`, `method_not_allowed`, `asset_unreadable` — criterion 13 run (a) expects two 404s whose `reason=` the card does not define
6. Criterion 13's `Phosphor-Fill.woff2` row depends on a done/resolved/copied/empty state rendering; the operator instruction says only "icon-bearing view", which regular icons satisfy
7. Criterion 13 — the linchpin of four rounds of fixes — does not run under `pytest`, does not run unattended, and needs a connected browser extension
8. One decorative line number without a re-find command (card:1020), which task 14's own edit guarantees will go stale
9. Inter `latin`-only subsetting is a visible product trade needing explicit user sign-off at the gate (carried from round 8)
10. `analyze.py` at 792/800 lines — the next edit to that file forces the named-but-unscheduled `git_facts.py` split

**risk=medium confidence=high**

Rationale for `medium` despite a `fail`: the failing dimension is maintainability and context cost,
not correctness or safety. The design's security reasoning — the trust boundary, the identity-based
surface binding, the collapsed `403` with a precise server-side `reason`, the `sent=unknown` honesty
— is the strongest part of this card and is getting stronger each round. But the context failure is
not cosmetic: an oversized document that no session can hold in one pass is exactly the mechanism
that produced the ten stale facts this card has already had to correct.
