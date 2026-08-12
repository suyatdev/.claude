# Observability judge — `feat/tracking-feature-state`, round 7 (architecting)

- **Repo:** `tracking-feature-state` (worktree of `suyatdev/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `fe55b2d5052d85deb87283eab6c6545e17b56e40`
- **Base:** `origin/main` — branch is **0 ahead / 0 behind** (tasks 1–7 merged via PR #48); local `main` is stale and was not used
- **Stage:** architecting — advisory, non-blocking
- **Artifact:** `docs/features/tracking-feature-state.md` (933 lines, 67,335 bytes), ADR `0024`
- **Round-7 commit:** `9812a37` (card + ADR 0024)
- **Prior rounds:** `badd4f8`, `41b586c`, `81d98dc`, `b9ad394`, `73f9475`
- **Timestamp:** 2026-08-10T01:58:17Z

---

## What was changed

The one thing that changed since round 6 is how criterion 13 decides whether it passed.

It used to say *"every request the page makes comes back `200`, except the favicon."* That was
wrong, and wrong in a way nobody could see by reading it — the criterion's own setup deletes
`tracker-data.js`, and the server is **supposed** to answer `404` for a file that doesn't exist
yet. So a perfectly correct server failed the check on its very first request.

The user rejected the small patch (add one more allowed `404`) and asked for the class fix. The
criterion now carries a literal table: run (a) and run (b), each with a full list of *which path*
and *what status*, and it passes only if what the browser actually did **exactly equals** that
list. That closes both directions — a missing `200` fails, and so does a surprise `200` from a
server that quietly started serving more than it should.

Two smaller things rode along: the `404` row in the wire contract was corrected (it said criterion
13 allows "the one expected `404`"; the new table makes two), and ADR 0024 gained the launch
contract it was missing.

Think of it like a packing list. The old rule was "nothing in the bag should be broken" — true, but
it never noticed a missing passport or a stranger's suitcase. The new rule is "the bag contains
exactly these nine things." Much harder to fool.

## Does it do what was wanted?

Yes. This is a genuine class fix, not another instance of the pattern.

I checked the two derived surfaces the commit moved, and **both are correct**:

- Criterion 13's run tables match the real files. `Task Tracker.dc.html:15` does request
  `tracker-data.js` unconditionally; `tracker-data-fallback.js:16` is the early return; `:19` is the
  `document.write` of the sample; `:18` sets `TRACKER_DATA_SOURCE = 'sample'`. The `_ds/` directory
  holds exactly the two requested files plus three the page never asks for, as the card says.
- The corrected `404` row (Card:322) says "they are the only two" and scopes that claim to **run
  (a)** — which is right. Run (b) has only one expected `404`. Scoping it to (a) is the detail that
  would have made it stale, and it was got right.

I also confirmed the exclusion reasoning behind the table: `support.js:158` issues a *second*
token-bearing `GET /`, but only `if (!window.__resources)` — which task 14 defines. The commit's
claim checks out.

Independently: I re-ran the pinned suite. **53 passed in 4.15s**, `node v26.5.0` present so none of
the three node-guarded tests skipped. That matches the figure recorded in §Verification exactly.

```
$ uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q
53 passed in 4.15s
```

## What could go wrong / what I'm unsure about

### 1. The favicon row can fail a correct server — round 6's mistake, mirrored

Set equality is bidirectional, and that is its whole value. It also means every row is now
**mandatory**, including this one:

> `/favicon.ico` | `404` — every browser requests it unprompted…

Under the old negative form, favicon was *permitted*. Under set equality it is *required to be
observed*. Chrome keeps favicons in a separate cache keyed by page URL, and runs (a) and (b) load
the same URL back to back — so it is entirely plausible that run (a) shows `/favicon.ico` and run
(b) does not. Set inequality. Correct server, failed criterion.

This is milder than round 6 (which failed always, on the first request; this fails sometimes, and
is obvious when it does). But it is the same species in mirror image, and it sits in the pass
condition — the exact surface this round was rewriting. The card's own warning applies to it: *"a
criterion whose first directed run must fail is a criterion that gets weakened until it passes."*

**Fix, one clause:** the browser-initiated unprompted request is *allowed but not required*.
State the expected set as exact over page-initiated requests, with `/favicon.ico` a permitted
extra. Do not delete the row — the `404` status is still worth asserting when it does appear.

### 2. Three new bare line citations — the habitat, reintroduced

Card:18–19 is the discipline this whole card is built on:

> **No count, test total or phase tally is pinned anywhere in this card**, and every code citation
> carries the command that re-finds it.

There are four bare `file:NN` citations with no re-finding command. **Three of them were added by
this commit:**

```
$ grep -nE '`[^`]+\.(js|py|sh|html|css|md)[^`]*:[0-9]+`' docs/features/tracking-feature-state.md
281:  `task-tracker/tracker-data-fallback.js:19`      ← pre-existing (round 2)
649:  `Task Tracker.dc.html:15`                       ← new
665:  `tracker-data-fallback.js:19`                   ← new
673:  `tracker-data-fallback.js:16`                   ← new
```

All four are correct **today** — I verified each. But `Task Tracker.dc.html:15` will go stale during
**task 14**, which is the task that runs criterion 13. Task 14 must define `window.__resources`
*before* `support.js` loads, and `support.js` is line 6 — so a script inserted above it shifts line
15 downward. Near-certain, self-inflicted, inside the feature's own execution.

Severity is low in consequence (all three sit in explanatory prose, not in the pass-condition table,
so staleness misleads a reader without breaking a check) but it is the eleventh instance of the
species the card names as its one recurring defect, written by the commit fixing the tenth. Replace
with the re-finding command the card's own discipline demands, e.g.
`` grep -n 'tracker-data' 'task-tracker/Task Tracker.dc.html' ``.

### 3. The `cmux send` → live Claude TUI probe is still open, at round 7

Unmoved since round 2. Every proven use of `cmux send` targets a **shell prompt**; none targets a
live Claude TUI. This is the single empirical unknown on the feature's highest-consequence path —
keystrokes landing in the wrong surface — and the card estimates it at "15 seconds on a scratch
surface."

The card handles it honestly: it is gated before task 8 (Card:709–711, 740), recorded in
§Verification, and task 9 explicitly warns that faking the binary for criterion 12 moves the live
path *"from visibly untested to apparently tested."* That warning is exactly right and is the reason
this is a `concern` and not a `fail`.

But observe where five rounds of effort went: **the card grew 389 lines (544 → 933) while the one
cheap empirical check stayed undone.** The tests will be green without it.

### 4. Compaction is now owed — yes, plainly

| Round | Lines | Δ |
|---|---|---|
| `badd4f8` | 544 | — |
| `41b586c` | 662 | +118 |
| `81d98dc` | 752 | +90 |
| `b9ad394` | 851 | +99 |
| `73f9475` | 901 | +50 |
| `9812a37` (HEAD) | 933 | +32 |

Growth is decelerating but still monotonic, and 933 lines is roughly 13k tokens re-read on every
session restore for the seven tasks still to come. Section sizes: Design 304, Acceptance criteria
153, Security 113, Tasks 111.

**This is not a `.spec.md` split.** The card's refusal to split (Card:924–927) is well argued and
should stand. What is owed is deletion of duplication:

1. **Round narrative, ~120–160 lines.** Nine ⚠️ blocks whose content is *the history of which round
   discovered what*: Card:25–29, 243–254, 278–284, 484–489, 503–515, 646–653, 676–680. The card's
   own §Revision history already rules that this belongs in git and the verdict files — and then the
   body carries it inline anyway. Keep the one-line *warning* ("a text search cannot answer a runtime
   question"); delete the round number, the count of previous attempts, and the retelling.
2. **The launch contract, stated four times.** Card:491–499 (§Security), 697–705 (criterion 14),
   778–782 (task 11), plus ADR 0024. One normative statement and three pointers.
3. **Remote assets, stated twice.** The table at Card:518–525 and task 14's bullets at 802–813.
4. **Re-argued ADR rationale.** Card:184–189 re-derives ADR 0022's "the server serves its own page."

Target ~600 lines. Every deletion above is a *copy*, not a fact.

### 5. Task 14 must edit the spec during the implementation phase

Criterion 13 says the vendored row is "completed by task 14 before this criterion runs, with the
exact paths it wrote, **appended to the §Design 3 manifest**." That is a spec-body edit while
`phase: implementation` — which `rules/gates.md` forbids ("implementation forbids spec and checklist
edits"), judgment-enforced, not hook-enforced. The card doesn't pre-authorize it.

**Cleaner fix, and it matches this card's own instinct:** make the vendored set a *derivation*
rather than a list to append — "the vendored assets are exactly the files task 14 writes under
`task-tracker/vendor/`". Then nothing needs editing, and the rule cannot go stale.

### 6. Minor

- `support.js:158`'s exclusion from the table is load-bearing and is reasoned **only in the commit
  message**, not in the card. Harmless (set equality over `(path, status)` pairs wouldn't catch a
  duplicate `/` anyway) but a reader of the criterion can't tell why it's absent.
- Set equality is over a **set**, not a multiset — "invoked exactly once" style counting is out of
  scope for it. Criterion 12 covers the one place that matters (`cmux send` invocation count), so
  this is fine, just worth knowing.
- Task 8's text doesn't say *"the server must not daemonize itself"*; the non-detached requirement is
  carried by §Security, task 11 and ADR 0024. Adequately covered, marginally split.
- Card frontmatter is `phase: planning` with tasks 1–7 ticked. Correct and intentional (the design is
  under review; `phase-guard.sh` will block `task-tracker/` writes until the gate transition), but a
  fresh reader can't tell that from the card.

**On the round's headline question — are tasks 8–14 specified well enough to prevent the two
silently-inert failure modes?** Yes. The detached-parent and redirected-`stderr` traps are now named
with their mechanism and their symptom in §Security (491–499), criterion 14's three clauses
(697–705), task 11 (778–782), and ADR 0024. Criterion 14 explicitly rejects a mocked `getppid()`.
An implementer following the card builds both controls live.

## What I'd double-check before merging

1. **Run the `cmux send` → live Claude TUI probe.** It is 15 seconds and it is the highest-value
   unknown in the feature. Nothing else should start until it is recorded in §Verification.
2. **Demote `/favicon.ico` to permitted-not-required** in both run tables (concern 1).
3. **Replace the three new `file:NN` citations with their re-finding commands** (concern 2) — at
   minimum `Task Tracker.dc.html:15`, which task 14 will invalidate.
4. **Do the compaction pass** before the gate transition, not after (concern 4). A 933-line card is
   re-read on every restore across seven remaining tasks.
5. **Decide how task 14 records its vendored paths** without a mid-implementation spec edit
   (concern 5).

---

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | **pass** | The user directed a class-level fix over a one-clause patch; the card delivers exactly that — per-run enumerated tables, bidirectional pass condition. Both moved surfaces verified accurate against source. |
| `execution` | **concern** | Design is testable and the suite is green (53 passed, re-run by me, matching the recorded figure). But criterion 13's mandatory `/favicon.ico` row can fail a correct server. |
| `trajectory` | **pass** | Reasoning is sound and independently reproducible. Correct root diagnosis ("a runtime property needs a runtime check"), correct escalation call, correct rejection of the instance patch. |
| `regression` | **pass** | Docs-only diff; no source touched; suite green; the `404`-row correction is accurate and correctly scoped to run (a). ADR 0024 updated consistently in the same commit. |
| `context_budget` | **concern** | 933 lines / ~13k tokens, fifth consecutive growth round, +71% across six rounds while the task list stayed at 7. Roughly 150 lines are round narrative the card's own §Revision history says belongs in git. |
| `traceability` | **pass** | Exceptional. Every row derived from source, ADRs 0022–0024 carry the structural decisions, warnings sit beside the thing that would reproduce the error. One gap: the `support.js:158` exclusion is reasoned only in the commit message. |
| `success_masking` | **concern** | Two channels. The `cmux send` → live-TUI probe is unclosed at round 7 and the suite is green without it (the card warns about this explicitly, which is why it is not a fail). And a criterion that fails a correct server is the pressure that gets criteria weakened. |
| `intent_drift` | **pass** | Exactly the directed fix plus two previously-advised items and one navigational pointer. No deps, no drive-by source edits, no scope creep. |
| `checkpoint` | **pass** | Docs-only, merged via PR #48, clean working tree, trivially revertible. No source modified. |
| `audit_trail` | **pass** | Commit message names the user decision, the rejected alternative, the class, each derivation, and self-reports the unaddressed 933-line growth. ADR updated alongside. |

**Risk:** medium — **Confidence:** high

Confidence is high because every derived fact in the round-7 diff was checked against source and the
recorded test count was re-run, not trusted. Risk is medium rather than low because the feature's
highest-consequence path (keystrokes into a live Claude TUI) remains empirically unproven at round 7,
and the criterion rewritten this round can still fail a correct implementation.

## Concerns

1. Criterion 13 set equality makes `/favicon.ico` a *required* observation; Chrome's favicon cache can
   legitimately omit it on run (b), failing a correct server — round 6's shape mirrored
2. Three new bare `file:NN` citations (Card:649, 665, 673) carry no re-finding command, contradicting
   the card's own discipline at Card:18–19
3. `Task Tracker.dc.html:15` will go stale during task 14 itself, which must insert a script above
   `support.js` (line 6)
4. `cmux send` → live Claude TUI probe still outstanding since round 2; card grew 389 lines while the
   15-second empirical check stayed undone
5. Card at 933 lines, fifth consecutive growth round; ~150 lines of round narrative duplicate what
   §Revision history says belongs in git; launch contract stated four times
6. Task 14 must append vendored paths to the §Design 3 manifest — a spec-body edit during
   `phase: implementation`, which `rules/gates.md` forbids and the card does not pre-authorize
7. `support.js:158`'s deliberate exclusion from criterion 13's table is reasoned only in the commit
   message, not in the card
8. Task 8 does not itself forbid the server self-daemonizing; the non-detached requirement lives in
   §Security, task 11 and ADR 0024
