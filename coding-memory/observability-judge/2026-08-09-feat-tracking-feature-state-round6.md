# Observability judge — `feat/tracking-feature-state`, round 6 (architecting)

- **Repo:** `tracking-feature-state` (worktree of `suyatdev/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `73f9475f750e8d24c2cdfb21738270114be7e578`
- **Base:** `origin/main` (merge-base `65ebf819e2307f76e3abce1f090ff936f0507ecf`)
- **Stage:** architecting — advisory, non-blocking. The compliance judge holds the gate.
- **Artifact:** `docs/features/tracking-feature-state.md` (901 lines, 64,942 bytes), ADR `0024`
- **Round-6 commit:** `126f5eb` (card + ADR 0024); `73f9475` archives session memory
- **Timestamp:** 2026-08-09T20:16:51Z

---

## ⚠️ Lead finding — `success_masking` is a **fail**

**Criterion 13 run (a) cannot pass. It is forbidden by the wire contract edited in the same commit.**

Round 6 split criterion 13 into two runs. Run (a) is the important one: move `tracker-data.js` aside
so the fallback shim fires and requests `tracker-data.sample.js` — the row four rounds of greps
missed (Card:645, 649–656). Correct diagnosis, correct fix.

But the page hard-codes the script tag unconditionally:

```
$ grep -n 'tracker-data' 'task-tracker/Task Tracker.dc.html'
15:<script src="tracker-data.js"></script>
16:<script src="tracker-data-fallback.js"></script>
```

The shim's own header comment says so: *"The page hard-codes `<script src="tracker-data.js">`"*
(`task-tracker/tracker-data-fallback.js:3`).

So in run (a) the browser **requests `tracker-data.js` and the server returns `404`** — the card says
this twice, in rows added by this very commit:

- Card:322 — `404 not_found` … *"`tracker-data.js` before the first analysis"*
- Card:327 — `500 asset_unreadable` … *"**Exception, and it is the normal case, not an error:**
  `tracker-data.js` absent is `404`"*

And criterion 13 forbids it:

- Card:643 — *"in both runs every request returns `200` except `/favicon.ico`, **no other request
  returns `404`**"*
- Card:658–661 — *"It is the one expected `404`; **any other is a failure**."*

There is no carve-out. I grepped every `tracker-data.js` mention (20 hits); none exempts it from
criterion 13. The contradiction is hard, not a matter of reading.

**Why this is a `fail` and not a `concern`.** The same commit withdrew the *"run criterion 13 before
task 14"* instruction, with this reasoning written into the card:

> *"a criterion whose first directed run must fail is a criterion that gets weakened until it
> passes"* (Card:759–760)

Round 6 diagnosed that failure mode, removed one instance of it, and created another one four
paragraphs earlier — in the same commit, in the same criterion. The predictable outcome is exactly
what the card warns of: the operator relaxes the `404` clause to get run (a) green, and a server that
`404`s `tracker-data.sample.js` passes again. That is the identical blind spot rounds 1–4 had, now
reached by a third route.

The fix is one clause: *"`/favicon.ico` and, in run (a) only, `/tracker-data.js` are the expected
`404`s; any other is a failure."*

---

## What was changed

Think of the card as the wiring plan for a doorbell that rings inside a room where Claude has every
tool switched on. The plan has one line that has now been wrong five rounds running: *"here is the
exact list of files the server may hand out."*

Round 5 stopped trying to find that list with a text search and made it a **written table proved by
loading the page for real**. Round 6 fixed three things the previous judge round found in that new
check, and did most of it well:

1. **The check now runs twice** — once with the data file present, once with it moved aside — because
   the interesting file is only ever requested on the first run (Card:645–656).
2. **The check now says how to run it.** It needs a real browser; the user decided to use the Claude
   browser extension rather than add Playwright to a repo with almost no dependencies. §Toolchain
   states the cost in plain words: *"criterion 13 does not run under `uv run pytest`, does not run
   unattended, and needs an operator with the extension connected"* (Card:819–826).
3. **Task 14 moved in the running order** — it now happens right after task 8, so the manifest is
   never leaned on while unproven (Card:755–762).
4. **Task 9 now says plainly that faking `cmux` proves nothing about keystrokes arriving**
   (Card:733–737).
5. **ADR 0024** now records the 5-second parent-death poll (ADR 0024:38–44).

## Does it do what you wanted?

Four and a half of five. I checked the file, not the commit message.

| Round-5 item | Verdict | Evidence I ran |
|---|---|---|
| 1. Criterion 13 runs in both store states | **Closed in shape, broken in detail** | Two runs exist (Card:645–647); run (a) is unsatisfiable — see lead finding |
| 2. "Run before task 14" withdrawn; 14 reordered | **Closed** | Card:755–762 withdraws it and states why; task 14 now runs after 8, before 9 and 10 |
| 3. Mechanism + tool + cost stated | **Closed, and honestly** | Card:663–672 and 819–826. Task 9 explicitly de-scoped (Card:723–725). See note below |
| 4. ADR 0024 agrees with the card | **Half closed** | Poll corrected (ADR 0024:38–44). **The launch contract is still in no ADR** |
| 5. Task 9's faked `cmux` | **Closed** | Card:733–737 — strong wording, and it forbids reading criterion 12 as closing the live path |

**On the browser-extension trade — I was asked to judge whether its cost is recorded honestly, and it
is.** This is the strongest writing in the round. The card does not hide behind "an agent verifies
it": it names the tool (`read_network_requests`), names what is lost (no `pytest`, not unattended,
needs an operator), names who does *not* own it (task 9), pins Chrome as *recorded at run time*
rather than pretending to pin it, and requires both request lists into §Verification as evidence
rather than a conclusion. That is exactly the honest-weaker-measurement discipline this card claims.
No further comment on the decision; it is settled and well documented.

**Measurements reproduce exactly.** `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q`
→ **53 passed in 4.80s**. Python `3.9.6`, uv `0.11.28`, node `v26.5.0`, cmux `0.64.20 (100)
[14e3400b9]` — four pins byte-exact against §Toolchain. Working tree clean.

## What could go wrong / what I'm unsure about

### 1. The recurring defect recurred a fourth time — and the dispatch pointed me at the right rock

I was asked to check whether round 5's **two** new controls arrived with their own assertions. Split
answer:

- **Criterion 13's two-state form: yes.** Task 14 owns it and closes by running both states and
  recording both request lists plus the browser version in §Verification (Card:778–781). It has an
  owner, a mechanism and an evidence requirement. Good. (It just cannot pass — see lead finding.)
- **`500 asset_unreadable`: no.** `grep -n 'asset_unreadable'` returns **exactly one line** in the
  whole card — the table row itself (Card:327). No acceptance criterion asserts it. The only cover is
  task 9's pre-existing sweep phrase *"each status code in the contract table"*, which is not new and
  was already covering `405`/`413`/`415`/`502`.

  Worse, its **deliberate exception** — *`tracker-data.js` absent is `404`, not `500`* — is the one
  clause that genuinely needs a directed test, since it is a hand-written carve-out in an otherwise
  uniform rule. The only place in the card where that state exists is criterion 13 run (a), which
  **forbids** the `404` the exception mandates. So the exception is simultaneously unasserted and
  contradicted by the only criterion that touches it.

That makes four instances of the pattern: audit log → parent-death shutdown → criterion 12 vs task
9's fake → `500 asset_unreadable`. The card's own ADR 0024 closes with *"a control that creates a
risk and ships without the test for that risk is how the audit log itself got into this card
unasserted"* (ADR 0024:71–73). The lesson is written down and was not applied one control later.

### 2. ADR 0024 still does not record the launch contract

The dispatch told me item 4 was closed for *"the 5-second poll and the launch contract"*. The poll
is closed. The launch contract is not — and the commit message does not claim it is, so this is the
dispatch summary overstating, not the commit.

I read ADR 0024 in full. It records the parent-death check (`getppid()` poll, 5s, floor 1s, no
disable) at 0024:38–44, and it says the audit log goes to *"stderr, the stream the launching session
already captures"* at 0024:31. **It never states the launch requirement itself** — non-detached
direct child, `stderr` inherited, no `nohup`/`setsid`/`&`/launchd. That lives only in the card
(Card:490–499) and task 11 (Card:746–750).

This matters more than a normal doc gap, and the card says why: *"Detaching disables the parent-death
shutdown silently; redirecting `stderr` sends the audit log nowhere. Both leave the code looking
correct."* An implementer working from ADR 0024 alone builds both controls exactly as specified and
gets two inert controls. The ADR records the mechanism without the precondition that makes the
mechanism work.

*One item I am closing that round 5 raised:* ADR 0024:61's *"costs at most one timer tick of
overrun"* is now bounded, because 0024:38 gives the tick a number in the same document. Not a defect
any more.

### 3. New this round: the execution order is discoverable only from the bottom of the list

Task 14 now runs second, but keeps the number 14 for a good reason (renumbering breaks references,
Card:755–756). The problem is *where the instruction lives*: only inside task 14's own body. A
session working the checklist top-down reaches task 9 first. Task 8 does not mention it. Task 9
mentions task 14 only to say criterion 13 *belongs* there (Card:723–724) — not that it must *run*
first.

Cheap fix: one line on task 8's tail — *"then do task 14 before 9 and 10."*

### 4. The items you told me were open — my view, mostly unchanged, one hardened

- **`cmux send` → live Claude TUI probe** (owed since round 2). **Unchanged, and now well-guarded in
  writing.** Card:733–737 is the right wording — it forbids reading criterion 12's green as closing
  the live path. That converts an invisible gap back into a visible one, which was my round-5 ask.
  The probe itself is still owed and still gates task 8's design (Card:685–687, 714).
- **The two self-contradictions.** Both survive byte-for-byte. Card:152–153 *"Every case below yields
  a `questions[]` entry … and the run still emits"* vs. Card:157 *"Abort **this run** … Nothing is
  written."* And Card:174–176 still says the store has no token access *"by construction, since the
  token exists only inside the running server process"*, while `reanalyze` runs the store inside that
  process (Card:455). One line each.
- **Phase-gate regression record.** Still nowhere. `grep -rn 'implementation → planning|phase
  regression|phase: implementation'` across the card and `docs/decisions/` returns one unrelated hit
  in ADR 0011. Frontmatter is `phase: planning`, 7 of 14 tasks `[x]`, ~1,500 lines of committed
  Python, and the hook still denies the next file task 8 creates — reproduced at exit 2:

  ```
  phase-guard: write blocked — task-tracker/server.py
  Still at planning:
    - docs/features/tracking-feature-state.md — phase: planning
  There is no bypass environment variable; this guard ships without one by design.
  EXIT=2
  ```

  Expect to reopen the gate with the literal phrase `gate confirmed` before task 8.
- **`sent=no` enumeration.** Unchanged at Card:369 — still *"every `409`, every `403`"*, still
  omitting `400`/`404`/`405`/`413`/`415`/`500`, still conflicting with criterion 12's requirement
  that an **accepted** `reanalyze` log `sent=no` (Card:638). The new `500 asset_unreadable` row makes
  the omission one row longer.
- **Criterion 14's 60-second idle floor.** Unchanged (Card:471 vs. Card:676) against a 4.80s suite.
- **`analyze.py` at 792 lines**, 8 below the 800 hard max. Human-owned, correctly left alone.

### 5. Context budget: fourth consecutive growth round

| | R3 | R4 | R5 | **R6** |
|---|---|---|---|---|
| Lines | 662 | 752 | 851 | **901** |
| Bytes | 45,121 | 52,146 | 60,226 | **64,942** |

+36% since round 3, largest it has ever been, read at session start, still `phase: planning`. The
additions are substantive. The blocks that would move without loss are still the same ones: §Design
3's four-round narrative about *why previous versions were wrong* (Card:243–284) belongs in ADR 0024
with a pointer left behind — which would also give the launch contract somewhere to live.

## What I'd double-check before merging

1. **Carve `/tracker-data.js` out of criterion 13 run (a)'s `404` rule.** As written the run is
   unsatisfiable, and the card itself predicts what happens next to an unsatisfiable directed run.
2. **Give `500 asset_unreadable` a criterion** — specifically its `tracker-data.js`-absent exception,
   which is the hand-written carve-out in an otherwise uniform rule. Fixing (1) does this for free if
   run (a) is made to *assert* the `404` rather than merely tolerate it.
3. **Put the launch contract in ADR 0024** — non-detached child, `stderr` inherited. The ADR
   currently records both controls without the precondition that makes either one fire.
4. **Move the "task 14 runs second" instruction to task 8's tail**, where a top-down reader hits it.
5. **Run the `cmux send` → live Claude TUI probe** before task 8. Still the one unproven assumption
   under the whole control channel.
6. **Fix the two self-contradictions** (analyzer table intro; §Design 2's "by construction").
7. **Record the `implementation → planning` regression**, and expect `gate confirmed` before task 8.
8. **Reconcile `sent=no`** — its definition, criterion 12's accepted `reanalyze`, and the six status
   codes it omits.
9. Optional, and increasingly overdue: move §Design 3's four-round narrative into ADR 0024.

---

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| `intent` | concern | Four of five accepted items closed and closed well; the browser-extension trade in particular is documented with its cost stated plainly rather than glossed (Card:819–826). But the flagship item — criterion 13's first-run state — landed in a form that cannot pass, and item 4 is half done (ADR 0024 got the poll, not the launch contract). |
| `execution` | concern | Suite reproduces exactly (53 passed in 4.80s), four pins byte-exact, tree clean, both commits well-formed. Against that: criterion 13 run (a) is contradicted by the wire-contract rows added in the same commit, and the new `500 asset_unreadable` row appears exactly once in the card with no criterion behind it. |
| `trajectory` | concern | Per-decision reasoning stays high — the two-state split, the ordering withdrawal and the fake-`cmux` caveat are all correct at the level of method, and each is written into the card as a warning to the next reader. But the card is still being repaired one instance at a time: criterion 13 was rewritten without re-reading the status table it was edited beside, in the same commit. Five rounds of one-instance-at-a-time on the same defect class argues for enumerating the surface, not patching the next hit. |
| `regression` | concern | Both self-contradictions survive byte-for-byte. ADR 0024 half-updated. The `404 tracker-data.js` clause added this round newly contradicts criterion 13(a). `sent=no`'s omission list grew by one row. Phase-guard denial reproduced at exit 2. |
| `context_budget` | concern | 851 → 901 lines, 60,226 → 64,942 bytes; fourth consecutive growth round, +36% since round 3, largest ever, read at session start, still `phase: planning`. Additions substantive, but ~40 lines of "why previous versions were wrong" still belong in the ADR. |
| `traceability` | concern | Materially better: criterion 13 now names its tool, its API, what it cannot do, who does not own it, and what evidence must be recorded. Against that, the launch contract — a structural security decision the card itself says fails silently — lives in no ADR, and ADR 0024 records the two controls it protects without it. |
| `success_masking` | **fail** | Criterion 13 run (a) is forbidden by the card's own wire contract (Card:322, 327 vs. Card:643, 658–661), so the one check that closes a five-round defect must fail on its only directed run — the exact dynamic this commit withdrew four paragraphs earlier. Weakening the clause restores the `tracker-data.sample.js` blind spot. Compounding it: `500 asset_unreadable` ships with nothing asserting it, the fourth instance of "a control added by the fixing round arrives unasserted". Criterion 12's faked `cmux` is now honestly labelled; criterion 14's idle clause still has a 60s floor against a 4.80s suite. |
| `intent_drift` | pass | Every change maps to an accepted advisory item, a compliance finding, or the user's recorded decision. No dependency added — the round's headline decision was explicitly *not* to add one. Diff is two documentation files; no drive-by edits, no `.spec.md` split. |
| `checkpoint` | pass | Two clean commits, working tree clean, obvious revert point at `b9ad394`. `126f5eb`'s message enumerates each change against its violation id and names the root cause. |
| `audit_trail` | concern | The commit message is unusually detailed and self-critical, and attributable. But the `implementation → planning` frontmatter regression is still recorded nowhere after five rounds, and one structural decision from round 5 (the launch contract) still has no ADR. |

**Risk:** high — not because a documentation line is catastrophic, but because of recurrence. This is
the fifth consecutive round in which the servable-manifest control is defective, the fourth in which
a control added by the fixing round ships unasserted, and the first in which the round reintroduced a
failure mode it had diagnosed and removed in the same commit. The card is one gate away from task 8
writing `server.py`, and every one of these is free to fix now and expensive once task 9 is written
around them.

**Confidence:** high — suite re-run (53 passed in 4.80s), four pins verified exactly, the HTML script
tags and the fallback shim read in full, all 20 `tracker-data.js` mentions in the card enumerated to
confirm no carve-out exists, `asset_unreadable` grepped card-wide, ADR 0024 read in full and diffed,
phase-guard denial reproduced at exit 2, line/byte counts measured rather than carried forward.

## Concerns

- criterion 13 run (a) is unsatisfiable: the page hard-codes `<script src="tracker-data.js">` and the card's own wire contract 404s it when absent, while criterion 13 permits only `/favicon.ico` to 404
- round 6 withdrew one "directed run must fail" criterion and created another in the same commit, four paragraphs apart
- `500 asset_unreadable` appears exactly once in the card, in its own table row; no acceptance criterion asserts it — fourth instance of a control shipping unasserted
- the `tracker-data.js`-absent-is-404 exception is both unasserted and contradicted by the only criterion that reaches that state
- ADR 0024 still does not record the launch contract (non-detached child, stderr inherited) — it records both controls that fail silently without it
- the "task 14 runs second" instruction lives only inside task 14, at the bottom of a list read top-down; tasks 8 and 9 do not carry it
- `cmux send` into a live Claude TUI still unproven, owed since round 2, gates task 8's design
- analyzer failure table's "every case yields questions[] and the run still emits" still contradicted by its own first row
- §Design 2's "store has no access to the token by construction" still argues against its own claim; reanalyze runs the store in-process
- implementation→planning frontmatter regression still recorded nowhere; phase-guard denies `task-tracker/server.py` (verified exit 2)
- `sent=no` still defined as a refusal while criterion 12 requires it for an accepted reanalyze; omits 400/404/405/413/415/500, now one row longer
- criterion 14's idle clause has a 60s floor against a 4.80s suite — the first test to be skipped
- card grew 851 → 901 lines (64,942 bytes), fourth consecutive growth round, largest ever, read at session start
- `analyze.py` at 792 lines, 8 below the 800 hard max
