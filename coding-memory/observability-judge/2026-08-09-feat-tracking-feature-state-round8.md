# Observability judge — `feat/tracking-feature-state`, round 8 (architecting)

- **Repo:** `tracking-feature-state` (worktree of `suyatdev/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **Judged range:** `fe55b2d..ca3e079` (two commits: `c2c2542` closes task 1, `ca3e079` closes the compliance-round-7 violations)
- **HEAD at write time:** `18740d026fa539395f750beec130f061df828131` — moved during this review; `18740d0` is a `CODING_MEMORY.md`-only commit and both judged artifacts are **byte-identical** to `ca3e079` (`shasum` on `git show <ref>:<path>` for the card and ADR 0024)
- **Base:** `origin/main` (`git merge-base origin/main HEAD` = `fe55b2d`); local `main` is stale and was not used. Branch is **3 ahead / 5 behind** `origin/main`
- **Stage:** architecting — advisory, non-blocking
- **Artifact:** `docs/features/tracking-feature-state.md` (**1080 lines**), `docs/decisions/0024-…md` (80 lines, unchanged this round)
- **Timestamp:** 2026-08-10T02:49:29Z

---

## What was changed

Two things, and the first is the bigger one.

**The team finally ran the experiment the whole design was resting on.** For six rounds this card
described a feature where a web page can type commands into a running Claude session — without ever
having tried typing into one. Task 1 ran four real probes. Two of them changed the design:

- Aiming at a session that doesn't exist gives a clean error (exit 1), not a silent misfire. Good
  news, and it deletes a fear the card had been designing around for five rounds.
- Aiming at a session that *does* exist but is the **wrong one** delivers the keystrokes and reports
  success. It happened, live, to somebody else's Claude session. The card now records this rather
  than tidying it away.

Think of it like a courier: the old plan was "check the address is real before sending." The probe
showed a real address is not the same as *your* address — the parcel arrived, at a stranger's house,
and the receipt said "delivered." So the check changed from *does this address exist* to *is this the
person I meant*.

**Second, three defects a compliance judge found were closed** — each against re-read source, not
against the judge's summary:

- Files served by the little local web server now declare what type they are (a stylesheet sent as
  plain text still returns "200 OK", but the browser silently throws it away — you'd get a page that
  loads and looks broken, and the test would pass).
- The one file that redirects the page's third-party downloads to local copies got a name,
  `vendor-resources.js`, and a place on the list — it had been assumed into existence.
- The Google Fonts link was found to be a *doorway*, not a file: it hands back a list of **28** more
  font files from a second server. I re-ran that measurement myself and got exactly 28.

## Does it do what was asked?

Yes — this round did precisely the work that was directed, and did it honestly. But it is a design
document, not working software, and three of the things it fixed are still only *described*, never
*run*.

## What could go wrong

**1. The card is now 1080 lines, and the promised trim didn't happen — again.**

Growth by round: 222 → 544 → 662 → 752 → 901 → 933 → 1001 → **1080**. Seven consecutive growth
rounds; the task list has stayed at 14 the whole time. Round 7 asked for a ~60-line trim of
"here's how a previous round got it wrong" prose *before* the gate transition. Round 8 added 147
lines instead.

**Was keeping the trim out of this diff the right call? Yes.** Mixing a 60-line deletion into a
147-line substantive change would have made this round genuinely harder to judge, and the author
declared the deferral in the commit message and in `CODING_MEMORY.md` rather than hiding it. That is
the correct handling of a deferral.

**Is it still only advisory? No — it is now blocking-adjacent, and specifically it blocks on the
gate, not on this verdict.** The card sits at `phase: planning`. The moment the user says
`gate confirmed`, `rules/gates.md` makes editing the spec and checklist out-of-phase work. So the
trim is not "owed before the branch lands" (as `CODING_MEMORY.md` puts it) — it is **owed before the
gate opens**, and after that it becomes either a rule violation or a permanently bloated document
that gets re-read on every restore across seven remaining tasks. There is no line in the card or its
checklist that says so; the only commitment lives in a memory file. *A fourth consecutive
growth-without-trim round should be scored `fail`, not `concern`.*

**2. A new masking channel, created by this round's own fix.**

The new rules — every static file declares its type, plus `X-Content-Type-Options: nosniff` — are
asserted in **exactly one place**: criterion 13. The card itself says criterion 13 "does not run
under `uv run pytest`, does not run unattended, and needs an operator with the extension connected."
Task 9 lists the content-type rule as an *instruction to the implementer* with no test behind it.

So `uv run pytest` will be green while a security header and every content type are unasserted. I ran
the pinned suite myself: **53 passed in 4.27s**, exactly the recorded number — and it says nothing
about anything this round added.

Worse, the *startup abort* for an unmapped file extension has **no assertion anywhere**. Note that
`EADDRINUSE` — added in the same commit — explicitly got one, with the card's own reasoning attached:
*"left unasserted it would be this card's recurring shape exactly: a control described in prose and
never once run."* One paragraph later, the round did that exact thing again.

**3. The favicon problem from round 7 is untouched, and now doubled.**

Criterion 13 passes only if the browser's requests **exactly equal** a written list, and
`/favicon.ico` is a mandatory row in run (a) — inherited by run (b) via "the same set with two
changes." Chrome caches favicon results separately and aggressively; two back-to-back loads of the
same URL can easily produce the request once and not twice. Correct server, failed criterion. Round 7
gave the one-clause fix (permitted, not required). It was not applied.

**4. Inter's second hop got measured; Phosphor's did not — and I checked.**

The card warns that the icon stylesheets are also doorways, then never counts what's behind them. I
fetched both:

```
url("./Phosphor.woff2")  url("./Phosphor.woff")  url("./Phosphor.ttf")  url("./Phosphor.svg#Phosphor")
url("./Phosphor-Fill.woff2")  …-Fill.woff  …-Fill.ttf  …-Fill.svg
```

Eight files, four formats. The new fixed extension map is `.js`, `.css`, `.html`, `.woff2` — so
`.woff`, `.ttf` and `.svg` are **absent**, and by the card's own new rule an unmapped manifest row
*aborts the server at startup*. Task 14 as written ("the icon font files they reference must come
along") therefore reads as an instruction to break startup. It fails loudly, which is the right
direction, but it is the same unmeasured-second-hop shape the round just fixed for Inter, left in
place for Phosphor.

## What I'd double-check before the gate

1. **Do the ~60-line trim before saying `gate confirmed`**, and put it on the checklist so it can't
   be stranded by the phase gate.
2. **Demote `/favicon.ico` to permitted-but-not-required** in both criterion-13 runs (one clause,
   round 7 already wrote it).
3. **Give the content-type/`nosniff` rule and the unmapped-extension startup abort a pytest
   assertion in task 9**, the way `EADDRINUSE` got one. Both are trivially testable against a local
   server; neither needs a browser.
4. **Measure Phosphor's second hop and make a scope call** the way Inter got one (`woff2` only is
   almost certainly right — browsers take the first supported format — but say so).
5. **Decide how task 14 records its vendored paths.** The card still says it appends them to the
   §Design 3 manifest mid-implementation, which the phase gate forbids and the card does not
   pre-authorize. Round-7 concern, still open.
6. **Sign off explicitly on the Inter `latin`-only decision** — it's a visible product trade
   (non-Latin text falls back to system fonts), correctly proposed in a planning-phase spec, but it
   is a user call, not an implementation one.

## What I verified myself (not taken from the diff)

| Claim in the diff | How I checked | Result |
|---|---|---|
| `support.js` is the page's first script, line 6 | `grep -n '<script' 'task-tracker/Task Tracker.dc.html'` | **True** — line 6, next is line 12 |
| Google Fonts returns **28** `woff2` URLs, browser UA load-bearing | re-ran the card's own `curl … \| grep -c woff2` | **28**, exact |
| ADR 0024 records "on the idle timer" as a corrected first-draft error, poll is 5s | read `0024-…md` | **True**, `TASK_TRACKER_POLL_SECS`, min 1s |
| Suite reports 53 passed | `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` | **53 passed in 4.27s** |
| Toolchain table (`cmux`, Python, `uv`, `node`) | ran all four version commands | all four reproduce **exactly** |
| Phosphor stylesheets' second hop | fetched both `style.css` files | 4 formats each; 3 of 4 extensions unmapped |

**Not verified, deliberately:** the four `cmux send` probes. Re-running a `send` at a live surface is
the exact hazard this design exists to prevent, and it is not a judge's action. The mis-delivery
report is evidence recorded *against* the author's interest, which is the credible direction for a
claim like this — but it remains the one load-bearing fact in this round I took on trust.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | **pass** | Exactly the directed work: the round-7 compliance triple plus the task-1 spike that had been outstanding since round 2. Nothing else. |
| `execution` | **concern** | Round-7's `/favicon.ico` defect survives untouched and is now inherited by run (b); Phosphor's second hop is warned about but unmeasured, with 3 of its 4 file extensions absent from the new map whose rule is a startup abort. New manifest rows themselves are consistent and both criterion-13 tables remain runnable. |
| `trajectory` | **pass** | Confirmed, not taken on faith: the first-script line, the woff2 count, the ADR wording and the test count each re-derived from source by me and each correct. The probe that *contradicted* the design was recorded rather than reconciled — the strongest available signal of real reasoning over luck. |
| `regression` | **pass** | Docs-only; no source touched; pinned suite green at 53, matching the recorded number; ADR 0024 unchanged and now the single authority on the poll interval. |
| `context_budget` | **concern** | 1080 lines, seventh consecutive growth round (+386% since `37a8e38`), task count unchanged. Deferring the trim out of *this diff* was right; deferring it past `gate confirmed` is not, because the phase gate then forbids the edit. Commitment exists only in `CODING_MEMORY.md`, not in the card or checklist. A fourth such round is a `fail`. |
| `traceability` | **concern** | *Downgraded from round 7's pass, on new facts.* Four bare `file:NN` citations still violate the card's own rule at line 18–19; three were flagged in round 7 and left. And this round *guarantees* one of them goes stale — pinning a new `<script>` above line 6 shifts the `Task Tracker.dc.html:15` citation at card:735. The card creates the exact defect species it names as its own recurring failure. New citations added this round do carry their commands. |
| `success_masking` | **concern** | The old channel is genuinely closed — the transport probe ran. A new one opened in its place: content types, `nosniff` and `vendor-resources.js` are asserted only in criterion 13, which by the card's own statement does not run under `pytest`; and the unmapped-extension startup abort is asserted nowhere at all, one paragraph from the reasoning that says such controls must be. |
| `intent_drift` | **pass** | No dependencies, no source edits, no drive-by cleanup — including the trim, which was correctly excluded rather than smuggled in. The `latin`-only font scope reduction is a trade, but it is *proposed* in a planning-phase spec with its alternative named, which is the right shape; it needs the user's sign-off at the gate. |
| `checkpoint` | **pass** | Clean working tree; one concern per commit; `git revert ca3e079` is a clean rollback that leaves the task-1 evidence intact. Noted, not charged: HEAD moved under this review (`ca3e079` → `18740d0`), so another session is committing to this branch concurrently. |
| `audit_trail` | **pass** | Exemplary. Both commit messages name the rejected alternative, the re-verified source, and the *unaddressed* growth; the `CODING_MEMORY.md` entry repeats the debt rather than closing the book on it; the mis-delivery is recorded where it hurts. |

**Risk:** medium — **Confidence:** high

Confidence is high because five independent facts in this diff reproduced exactly under my own
commands, and the one I could not check is recorded against the author's interest. Risk stays medium
rather than low because three controls added this round are described and unasserted, the criterion
that would catch them cannot run unattended, and a criterion that can fail a correct server is now
two rounds old.

## Concerns

1. `/favicon.ico` is still a required observation under criterion 13's set equality (run (a), inherited by run (b)); Chrome's favicon cache can legitimately omit it and fail a correct server — round-7 fix not applied
2. Content-Type and `X-Content-Type-Options: nosniff` are asserted only in criterion 13, which the card states does not run under `uv run pytest`; task 9 lists them as instructions with no test
3. The unmapped-extension startup abort has no assertion anywhere, unlike `EADDRINUSE` added in the same commit — the card's own "control described in prose, never run" shape, repeated one paragraph later
4. Phosphor's second hop is unmeasured while Inter's was measured: both stylesheets reference `.woff2/.woff/.ttf/.svg` (verified live), and 3 of those 4 extensions are absent from the fixed map
5. Card at 1080 lines, seventh consecutive growth round; the ~60-line trim is owed before `gate confirmed`, not "before the branch lands", because the phase gate then forbids card edits — and it is on no checklist
6. Four bare `file:NN` citations violate the card's own line-18 discipline; `Task Tracker.dc.html:15` (card:735) is now guaranteed stale by this round's decision to insert a script above line 6
7. Task 14 still appends vendored paths to the §Design 3 manifest mid-implementation — a spec-body edit the phase gate forbids and the card does not pre-authorize (round-7 concern, unaddressed)
8. Inter `latin`-only subsetting is a visible product trade needing explicit user sign-off at the gate, not just a recorded decision
9. HEAD moved from `ca3e079` to `18740d0` during this review (memory-only; judged artifacts verified byte-identical) — a concurrent session is committing to this branch
