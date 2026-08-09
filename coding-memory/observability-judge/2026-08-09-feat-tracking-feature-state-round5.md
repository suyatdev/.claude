# Observability judge — `feat/tracking-feature-state`, round 5 (architecting)

- **Repo:** `tracking-feature-state` (worktree of `suyatdev/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `b9ad3943939cc6034c922a7fecfa8c27c263cbc0`
- **Base:** `origin/main` (merge-base `65ebf819e2307f76e3abce1f090ff936f0507ecf`)
- **Stage:** architecting — advisory, non-blocking. The compliance judge holds the gate.
- **Artifact:** `docs/features/tracking-feature-state.md` (851 lines, 60,226 bytes), ADRs `0022`, `0023`, `0024`
- **Timestamp:** 2026-08-09T19:52:33Z

> Filename note: the dispatch named `2026-08-09-tracking-feature-state.md`, which does not exist —
> the branch slug is `feat-tracking-feature-state`, and rounds 2–4 were each recorded as their own
> `-roundN` file in this directory. This round follows that precedent.

---

## What was changed

Think of the card as the blueprint for a doorbell wired into a room where Claude has every tool
switched on. For four rounds running, one blueprint line kept being wrong in the same way: *"here is
the list of files the server is allowed to hand out."* Each round the author fixed it by widening a
text search — look in one file, then the whole folder, then also the JavaScript — and each time a new
gap opened just past the new edge. Round 4 found the next one: stylesheets pull in fonts using a
syntax (`url(...)`) that none of those searches ever matched.

Round 5 stopped widening and changed the method. The list is now **a written-out table** of six files
with a column saying *which file asks for each one* (Card:256–264), and a **new test, criterion 13,
that proves the table by actually loading the page with the network switched off and following every
request it makes** (Card:638–648). The reasoning is stated plainly and is correct: *"what does this
page request" is a runtime property, and a text search can only ever approximate it* (Card:250–253).
The old grep survives, demoted in writing to a drafting aid.

Three smaller things came in alongside: **criterion 14** now tests that the server actually dies when
the session that launched it dies, with a real number on the check (5 seconds, `TASK_TRACKER_POLL_SECS`,
Card:483–488); **criterion 11** now also proves that `analyze.py`, `store.py` and `tracker-data.json`
are unreachable, not just files outside the folder (Card:613–624); and **§Security now says how the
server must be launched** — a plain child process with its error output inherited (Card:490–498),
because two of the security controls silently stop working if it is launched any other way.

## Does it do what you wanted?

Yes on all four. I checked the file, not the commit message.

| Item | Verdict | Evidence I ran |
|---|---|---|
| Shutdown acceptance criterion + a number for the poll | **Closed** | Criterion 14 (Card:649–657) has all three clauses — parent exits → server exits within `POLL_SECS + 1s` **and the port is free**; idle exit; and a log line reaching the parent's stderr. Interval is `5` seconds with a 1s floor and no "never" value (Card:483–488). |
| Criterion 11 extended to in-directory paths | **Closed** | Card:613–624 names `/store.py`, `/analyze.py`, `/tracker-data.json`, `/test_server.py`, `/_ds/nocturne-<uuid>/readme.md` → `404`. I confirmed `readme.md` genuinely exists in `_ds/` (`find task-tracker/_ds -type f` → 5 files). |
| Launch method stated | **Closed** | §Security bullet (Card:490–498) and task 11 (Card:714–718): non-detached direct child, `stderr` inherited, no `nohup`/`setsid`/`&`/launchd, with the failure mode written beside the instruction. |
| CSS `url()` fixed structurally, not by widening | **Closed, and this is the right call** | Manifest table (Card:256–268) + criterion 13 (Card:638–648), which states in the card that a source search **is not an acceptable substitute**. |

**The manifest table is factually correct.** I verified every row against the actual page:

```
$ grep -nE '(src|href)=' 'task-tracker/Task Tracker.dc.html'
6:  <script src="./support.js">
11: <link href="_ds/nocturne-73641b21-.../styles.css">
12: <script src="_ds/nocturne-73641b21-.../_ds_bundle.js">
15: <script src="tracker-data.js">
16: <script src="tracker-data-fallback.js">
$ sed -n '19p' task-tracker/tracker-data-fallback.js
  document.write('<script src="tracker-data.sample.js"><\/script>');
```

Six rows, six matches. `_ds/` really does hold five files and the table really does list only the two
the page loads — the "a glob is not an enumeration" fix landed. `nocturne.css` is correctly excluded
(only `Task Tracker Directions.dc.html:12` loads it, and that file is not served).

And the measurements hold: `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` →
**53 passed in 4.43s**; Python `3.9.6`, uv `0.11.28`, node `v26.5.0`, cmux `0.64.20 (100) [14e3400b9]`
— all five pins exact.

## What could go wrong / what I'm unsure about

### 1. Criterion 13 cannot catch the one file it was written to catch

This is the finding I would act on first, and it is uncomfortable because it is the *same defect class
recurring inside the fix for that class*.

The card's own worked example for why a list is not enough is `tracker-data.sample.js` (Card:278–284):
the fallback shim `document.write`s it **only on the first run, when no analysis exists yet**. I read
the shim — it returns early if data is already present:

```js
// task-tracker/tracker-data-fallback.js:16-19
if (window.TRACKER_DATA) return;
window.TRACKER_DATA_SOURCE = 'sample';
document.write('<script src="tracker-data.sample.js"><\/script>');
```

Criterion 13 pins the opposite state: *"the UI reaches its rendered state **with data from
`tracker-data.js`**"* (Card:642). And `task-tracker/tracker-data.js` exists today, 38 KB, populated.
So under criterion 13 as written, `window.TRACKER_DATA` is set, the shim returns early, and
**`tracker-data.sample.js` is never requested** — a server that `404`s it passes.

The manifest row that four rounds of greps missed is the exact row the new runtime check does not
verify. One extra clause fixes it: *run criterion 13 a second time with `tracker-data.js` absent, and
require the first-run path to render from the sample with zero `404`s.*

### 2. "Run criterion 13 before task 14" is unsatisfiable as written

Criterion 13 requires **no network access** and **no request to a host other than `127.0.0.1`**
(Card:638–641), and the card instructs: *"Run it both before and after task 14; before, it is the
proof the manifest is complete"* (Card:645–646).

Before task 14 the page fetches six remote assets. I confirmed all six sources:

```
task-tracker/support.js:1143  REACT_URL     = https://unpkg.com/react@18.3.1/...
task-tracker/support.js:1145  REACT_DOM_URL = https://unpkg.com/react-dom@18.3.1/...
task-tracker/support.js:1147  BABEL_URL     = https://unpkg.com/@babel/standalone@7.29.0/...
task-tracker/Task Tracker.dc.html:13,14   two @phosphor-icons stylesheets
task-tracker/_ds/.../styles.css:2         Google Fonts @import
```

With the network blocked and no vendoring, React and Babel never load, so the UI cannot reach a
rendered state and the `127.0.0.1`-only clause fails by construction. The "before" run is therefore a
**known-failing test**, and a known-failing test is the one an implementer rationally weakens or
defers — which puts the round's headline control back in exactly the position it was rescued from.

The fix is small: split the clauses. Before task 14, assert *zero `404`s from the local server*
(manifest completeness) and let remote hosts through. After task 14, add *zero non-`127.0.0.1` hosts*.

### 3. Criterion 13 has no mechanism, no tool, and needs a dependency the card does not name

Criterion 13 is now the load-bearing proof of the servable set, and the card never says **how** to
follow the requests a page makes at runtime. That needs a headless browser. I checked: there is no
`node_modules`, no `package.json`, and no mention of `playwright`, `puppeteer` or `selenium` anywhere
in the repo. §Toolchain pins Python, uv, pytest, cmux and node — nothing that can drive a page.

Two consequences. Task 9 is asked to write a test with no stated way to write it, which is precisely
where a source-search "equivalent" gets substituted back in. And adding a browser driver is a **new
dependency**, which `rules/core-conduct.md` says is never taken unilaterally — so this is a decision
owed to the user before task 9, not an implementation detail.

### 4. The three items you already know are open — my view, unchanged and one shifted

- **The `cmux send` → live Claude TUI probe** (owed since round 2). **My view has hardened.** New
  criterion 12 asserts `cmux send` is invoked exactly once (Card:631–637), and task 9 instructs *"Fake
  the binary rather than typing into a real session"* (Card:705). Faking is right for a unit test — but
  it means the suite will now go green **displaying positive evidence that the send path works**, while
  the only thing ever proven is that the server called a stub. Before criterion 12 the send path was
  visibly untested; after it, it is invisibly untested, which is worse. The probe is cheap (15 seconds
  on a scratch surface, by the card's own estimate) and it gates task 8's design.
- **The two self-contradictions.** Both survive byte-for-byte; I re-read them rather than diffing.
  Card:152–153 promises *"Every case below yields a `questions[]` entry … and the run still emits"*,
  and Card:157 immediately says *"Abort this run … Nothing is written."* Card:174–176 still says the
  store has no token access *"by construction, since the token exists only inside the running server
  process"* — but `reanalyze` runs the store **inside that very process** (Card:454), so the stated
  reason argues against the claim. The narrower true statement (`store.py` never reads the token)
  is verifiable and would cost one line.
- **The phase-gate regression record.** Still nowhere. `grep -rn 'implementation → planning\|phase
  regression'` across the card and ADRs 0022/0024 returns nothing. Frontmatter is `phase: planning`
  with 7 of 14 tasks `[x]` and ~1,000 lines of committed Python, and the hook still denies the next
  file task 8 creates:

  ```
  $ printf '{"tool_name":"Write","tool_input":{"file_path":".../task-tracker/server.py"}}' | bash hooks/phase-guard.sh
  phase-guard: write blocked — task-tracker/server.py
  There is no bypass environment variable; this guard ships without one by design.
  EXIT=2
  ```

### 5. ADR 0024 was not updated and now disagrees with the card

`git log -- docs/decisions/0024-*.md` shows its last touch was `81d98dc` (round 4). Two of its lines
are now stale against the card they record:

- ADR 0024:38 — *"A parent-death check **on the idle timer**"*. The card now runs it on a separate
  5-second poll timer.
- ADR 0024:55 — *"costs at most **one timer tick** of overrun"*. That is the exact unbounded phrasing
  the card fixed this round by giving the tick a number.

Neither the poll interval nor the launch contract — both structural security decisions, and the card's
own rule sends structural decisions to ADRs (Card:123–125) — is recorded in any ADR. This is the card's
recurring defect species (a stored fact going stale in a second copy) reappearing across the
card/ADR boundary rather than inside the card.

### 6. Criterion 14's idle half has a 60-second floor

§Security sets `TASK_TRACKER_IDLE_SECS` to a **minimum of 60s** with no disable (Card:470–472).
Criterion 14 says to "drive both with short overrides so the test does not take 30 minutes"
(Card:651–653) — but the floor means the idle clause cannot run in under a minute. Dropped into a
suite that currently completes in 4.43 seconds, that is the test that gets marked `skip` first. Worth
deciding now whether the floor is a security invariant (then accept a slow test, and say so) or a
sanity guard (then let the test set it lower).

### 7. Two audit-log gaps from last round: one changed shape, one open

- **`sent=` for an accepted `reanalyze` is now a contradiction rather than a gap.** Criterion 12
  requires `reanalyze` to log `sent=no` (Card:636–637), while §Design 3 defines `no` as *"the refusal
  happened before invocation (every `409`, every `403`)"* (Card:368–369). An accepted `reanalyze` is
  not a refusal. The criterion picked the right value; the definition did not follow it.
- **Still open:** `sent=no` enumerates only `403`/`409`, omitting `400`/`404`/`405`/`413`/`415`/`500`;
  and `outcome` still has no mapping to status codes (is `502` `failed` or `refused`? is `409`?).

### 8. Context budget: third consecutive growth round

| | Round 3 | Round 4 | Round 5 |
|---|---|---|---|
| Lines | 662 | 752 | **851** |
| Bytes | 45,121 | 52,146 | **60,226** |

Up 33% in three rounds, largest it has ever been, read at session start, still `phase: planning`. The
additions are substantive, not padding — but the manifest table, the six-asset table and the four-round
narrative in §Design 3 (Card:243–284, ~40 lines of history about *why previous versions were wrong*)
are the blocks that belong in ADR 0024 with a pointer left behind.

### 9. `analyze.py` is still 8 lines from the ceiling

`wc -l task-tracker/analyze.py` → **792**, against the 800 hard max. Unchanged. The `git_facts.py`
split is correctly left as a human-owned call, but there is no headroom for task 8's neighbours.

## What I'd double-check before merging

1. **Add a first-run clause to criterion 13** — run it once with `tracker-data.js` absent. As written
   it cannot catch `tracker-data.sample.js`, the file it exists because of.
2. **Split criterion 13's clauses across task 14** so the "before" run is not a known failure:
   zero local `404`s before, zero non-`127.0.0.1` hosts after.
3. **Decide the browser-driver dependency now**, before task 9. No such tool exists in this repo and
   §Toolchain pins none; this is a user decision, not an implementation one.
4. **Run the `cmux send` → live Claude TUI probe.** Criterion 12's faked binary makes the untested
   send path *look* tested, which is the more dangerous state.
5. **Fix the two self-contradictions** (analyzer table intro; §Design 2's "by construction").
6. **Record the `implementation → planning` regression somewhere that exists**, and expect to reopen
   the gate with the literal phrase `gate confirmed` before task 8.
7. **Update ADR 0024** for the 5-second poll and the launch contract; it currently contradicts the card.
8. **Reconcile `sent=no`'s definition with criterion 12**, and map `outcome` to status codes.
9. Optional: move §Design 3's four-round narrative into ADR 0024 to make the card stop growing.

---

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| `intent` | pass | All four items verified against the file, not the claim. Criterion 14 carries all three clauses plus a port-free assertion; the poll has a number, a floor and no disable; criterion 11's five in-directory paths all resolve to real files; the launch contract appears in both §Security and task 11 with its failure mode written beside it. The CSS-`url()` item was fixed by replacing the method rather than widening the search — the stronger of the two available fixes. |
| `execution` | concern | Measurements reproduce exactly (53 passed in 4.43s; all five pins byte-exact) and the manifest table matches the real page row-for-row. But criterion 13, the round's load-bearing control, has no stated mechanism, no pinned tool, and requires a browser driver that does not exist in this repo and would be a new dependency. |
| `trajectory` | pass | The round diagnosed the recurrence correctly at the level of method — "what does this page request" is a runtime property a text search can only approximate — and refused a fifth widening. Criterion 12 came from a class-level observation (criteria 6–11 were all refusals) rather than an instance fix. The reasoning is written into the card as a warning to the next reader, not just applied. |
| `regression` | concern | Three previously-flagged items survive byte-for-byte: the analyzer failure-table intro vs. its own first row, §Design 2's "by construction" reason, ADR 0023's unresolvable owner pointer. ADR 0024 was not updated and now contradicts the card on both the poll timer and the "one timer tick" bound. Phase-guard denial reproduced at exit 2. |
| `context_budget` | concern | 752 → 851 lines, 52 KB → 60 KB; third consecutive growth round, up 33% since round 3, largest it has ever been, read at session start. Additions are substantive, but ~40 lines of "why previous versions were wrong" narrative in §Design 3 belong in the ADR. |
| `traceability` | concern | Criterion 13 states in the card that a source search is not an acceptable substitute and why, and the manifest names the requester per row — both genuinely improve explainability. Against that, the two structural decisions added this round (5s poll, launch contract) live only in the card, and ADR 0024 still records the superseded versions of both. |
| `success_masking` | concern | Materially improved — criteria 12–14 exist precisely because a server that refused everything passed the whole suite. Three masking paths remain: criterion 13 pins the populated state so a `404` on `tracker-data.sample.js` passes it; its "before task 14" run is unsatisfiable and will be weakened or deferred; and criterion 12's faked `cmux` binary turns an obviously-untested send path into an apparently-tested one. Criterion 14's idle clause has a 60s floor in a 4.43s suite. |
| `intent_drift` | pass | Every change maps to an accepted advisory item, a compliance finding, or a recorded user decision. No dependency added, no `.spec.md` split proposed, no drive-by edits — the diff touches one card plus judge records. The latent drift is that criterion 13 *will* require a dependency, which is flagged above rather than taken. |
| `checkpoint` | pass | Single clean commit `b9ad394`, working tree clean, obvious revert point at `81d98dc`. The commit message enumerates each change with its rationale and names the root cause it is fixing. |
| `audit_trail` | concern | Commit is fully attributable and unusually well-reasoned. But the `implementation → planning` frontmatter regression remains recorded nowhere — `grep` across the card and ADRs 0022/0024 returns nothing — and the ADR that should hold this round's two structural decisions was not touched. |

**Risk:** medium — the method change is the right one and is the strongest single decision this card
has made, but the new runtime check does not cover the case it was written for, is unsatisfiable at the
point the card says to first run it, and has no tool to run it with. All three are cheap to fix at
`planning`, and none is fixable once task 9 has been written around them.

**Confidence:** high — suite re-run, five pins verified exactly, manifest table checked row-for-row
against the real HTML and the fallback shim read in full, `_ds/` enumerated, criterion 11's cited
paths confirmed to exist, phase-guard denial reproduced, ADR 0024 read in full and its git history
checked, repo searched for browser-automation tooling.

## Concerns

- criterion 13 pins the populated state, so `tracker-data.sample.js` — the file it was written for — is never requested and a 404 on it passes
- criterion 13's "run before task 14" is unsatisfiable: unpkg React/ReactDOM/Babel plus two phosphor links violate the no-remote-host clause by construction
- criterion 13 has no mechanism and no pinned tool; a headless browser is a new dependency, absent from the repo and from §Toolchain
- criterion 12 fakes the cmux binary, turning the unproven live-Claude-TUI send path from visibly untested into apparently tested
- `cmux send` into a live Claude TUI still unproven, owed since round 2, gates task 8's design
- analyzer failure table's "every case yields questions[] and the run still emits" still contradicted by its own first row
- §Design 2's "store has no access to the token by construction" still argues against its own claim; reanalyze runs the store in-process
- implementation→planning frontmatter regression still recorded nowhere; phase-guard denies `task-tracker/server.py` (verified exit 2)
- ADR 0024 not updated: still says the parent-death check is "on the idle timer" and costs "one timer tick", both superseded by the card
- the 5s poll interval and the launch contract are structural security decisions living only in the card, in no ADR
- `sent=no` is defined as a refusal but criterion 12 requires it for an accepted `reanalyze` — definition and criterion now conflict
- `sent=no` omits 400/404/405/413/415/500; `outcome` still has no mapping to status codes
- criterion 14's idle clause has a 60s floor against a 4.43s suite — the first test to be skipped
- ADR 0023's "whoever owns the export" still unresolvable; `task-tracker/github.md` would close it
- card grew 752 → 851 lines (60 KB), third consecutive growth round, largest ever, read at session start
- `analyze.py` at 792 lines, 8 below the 800 hard max
