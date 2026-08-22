---
phase: implementation
model_tier: low
branch: feat/treko-rename
---

# Treko: rename the tracker, and launch it without being asked

This is **card 1 of 5** in the Treko series. It renames the feature-state tracker to Treko across
every layer this repo owns, ports the Treko-branded page in from the design prototype, and makes the
skill start the server and open the browser itself instead of printing instructions.

It deliberately ships **no new tracker behaviour**. The Ledger list, the dashboard upgrades, the
agent panel and the analyzer's up/down traversal are cards 2–5; see §Deferred.

## Why

The tool is called Treko now. Today it is called `tracking-feature-state` as a skill,
`task-tracker` as a directory, `TASK_TRACKER_PORT` as an environment variable, and "Task Tracker" on
its own page. Four names for one thing is four chances to look up the wrong one, and the four
remaining cards all touch these files — renaming later means renaming a moving target.

The launch change has a separate reason. The skill currently ends by printing a command for a human
to run and a URL for a human to paste. That is a survey tool asking you to do three steps before it
answers the question you asked. Every one of those steps is a place to stop.

## What already exists, measured

The design prototype at `~/Other Docs/AI/AI_Projx/Prototypes/Treko/Treko/` is **ahead of this repo**.
Re-derive rather than trusting this paragraph:

```sh
diff "$PROTO/Task Tracker.dc.html" task-tracker/"Task Tracker.dc.html"
```

On 2026-08-21 that diff was **422 changed lines** over two files of near-identical length (repo
639 lines, prototype 637). The prototype's side carried: the Treko icon in place of the
`ph-crosshair` glyph, the sidebar title "Treko", nested feature → story → task rows with Rally
links, a per-run delete affordance, a re-analyze button, and a retinted accent palette
(`--color-accent:#38c4e3`). Of those, this card adopts **only the icon, the title and the palette**;
the rest have no backend and the nested rows have no data at all (§"The nested rows are not portable
yet").

**The two pages are sibling revisions, not superset and subset.** This correction matters because
the first draft of this card got it backwards. The agent panel, the resizable sidebar and the
resolved-toggle are **already in this repo's committed page** — they did not arrive with the
prototype:

```sh
for k in agentOpen agentMsgs agentH agentQ agentHandleDown resolved; do
  printf '%-18s %s\n' "$k" "$(grep -c "$k" task-tracker/'Task Tracker.dc.html')"; done
# 2026-08-21: agentOpen 7, agentMsgs 8, agentH 8, agentQ 5, agentHandleDown 3, resolved 4
```

So cards 3 and 4 are **backend-only** work behind front-end markup this repo has carried all along.
Card 1 adopts none of it either way — it changes branding and nothing behavioural.

Two requested behaviours exist in **neither** place, and are named as future work rather than
silently assumed: renaming a run (`grep -ci 'pencil\|rename'` over the prototype page returns `0`)
and the agent token counter (`grep -oi 'token[a-z]*'` returns nothing).

The prototype's `Ledger.dc.html` has no counterpart in this repo at all. It is card 2.

## Decision: the data contract does not get renamed

**ADR 0023** records that the `tracker-data` shape — the file `tracker-data.js`, the global
`window.TRACKER_DATA`, and the `runs[]`/`features[]`/`branches[]`/`waves[]` schema inside it — is
owned by the Nocturne export, not by this repo, and that this repo's analyzer is a *producer*
conforming to it. Its stated rule is "read the schema, do not redesign it."

The owner has not moved. A bare occurrence count here would not be a measurement — it changes with
the file set you count over, and the first draft of this card printed one without saying which set
it used. The command is therefore part of the claim:

```sh
cd "$PROTO" && grep -o -h 'tracker-data\.js' *.html *.js | wc -l          # top-level pages + scripts
```

| identifier | occurrences | scope |
|---|---|---|
| `tracker-data.js` | 11 | `$PROTO/*.html` + `$PROTO/*.js`, top level only |
| `tracker-data.js` | 8 | `Ledger.dc.html` + `Task Tracker.dc.html` only |
| `tracker-data.js` | 13 | `grep -ro` over the whole `$PROTO` tree |
| `window.TRACKER_DATA` | 7 | top level only |
| `taskTracker.*` keys | 24 over 7 distinct keys | top level only |

All three scopes say the same thing, which is the only thing the decision rests on: **the external
owner still uses these names, everywhere, with no deprecation in sight.**

Of the 7 keys, three (`sidebar`, `agentH`, `resolved`) are **not** new — they are already in this
repo's committed page, as §"What already exists" shows. The keys new to the prototype are
`deletedRuns`, `localRuns` and `queued`, and they arrive with `Ledger.dc.html`, the card-2 page. So
the owner is **extending** the old namespace with new features, not retiring it — which is the
inference that matters, and it survives the corrected attribution.

Renaming these on our side would therefore not complete the rename; it would fork us from the design
source and turn every future export into a manual merge — the exact cost ADR 0023 exists to prevent.
**The data contract keeps its current names.** Card 1 records this in a new ADR and moves on.

## Scope: the rename map

Four layers change. Everything is `git mv` so history follows the file.

| Layer | From | To |
|---|---|---|
| Skill directory | `skills/tracking-feature-state/` | `skills/treko/` |
| Skill frontmatter | `name: tracking-feature-state` | `name: treko` |
| Code directory | `task-tracker/` | `treko/` |
| Served page | `Task Tracker.dc.html` | `Treko.dc.html` |
| Port variable | `TASK_TRACKER_PORT` | `TREKO_PORT` |
| Idle timeout | `TASK_TRACKER_IDLE_SECS` | `TREKO_IDLE_SECS` |
| Poll interval | `TASK_TRACKER_POLL_SECS` | `TREKO_POLL_SECS` |
| Analyzer timeout | `TASK_TRACKER_ANALYZE_SECS` | `TREKO_ANALYZE_SECS` |

Unchanged, by the decision above: `tracker-data.js`, `tracker-data-fallback.js`,
`tracker-data.sample.js`, `tracker-data.json`, `window.TRACKER_DATA`, every `taskTracker.*`
localStorage key, and the `store.py` constants `ASSIGNMENT` and `SCHEMA_VERSION`.

`store.py`'s `TOOL` string (`"task-tracker v0.4.1"`) is a **producer identifier written into the
store**, so it is part of the contract's payload, not its shape. Change it to `"treko v0.5.0"` only
after confirming no consumer reads it; if in doubt it stays and becomes a `questions[]` note. Do not
guess — `grep -rn 'TOOL\|tool' ` the prototype before deciding.

### Files that change

Re-derive the set; do not trust a count written here:

```sh
git grep -l -iE 'task[-_ ]tracker' | grep -vE '^(docs/decisions/|coding-memory/|docs/features/(tracking-feature-state|readme-roadmap-upkeep))'
```

That is the in-scope set. It resolved to the `task-tracker/` tree plus
`skills/tracking-feature-state/SKILL.md`, `PORTS.md` and a `.gitignore` comment on 2026-08-21.
`CLAUDE.md`'s skills-catalog line and `README.md`'s roadmap entry also change; neither contains the
literal string, so neither appears in that grep — check both by hand.

### Files that deliberately do NOT change

| Path | Why |
|---|---|
| `docs/decisions/0022`, `0023`, `0024`, `0025` | An ADR records what was decided when it was decided. Rewriting the name inside a merged decision falsifies the record. The rename gets its own ADR instead. |
| `coding-memory/*/verdicts.jsonl` | The frozen, append-only judge ledgers (ADR 0031). Never edited in place. |
| `docs/features/tracking-feature-state.md` / `.spec.md` | That card is `phase: implementation` on branch `fix/tracker-frontmatter-comment`. It belongs to that branch. Touching it here guarantees a conflict and violates the phase gate. |
| `docs/features/readme-roadmap-upkeep.md` | `phase: review` on `docs/readme-roadmap-task-tracker`. Same reason. |
| `task-tracker/tracker-data.js` content | Generated. It moves with the folder; its contents are rewritten by the next analysis, not by hand. |

This leaves the repo with correct-but-old names in its decision history and in two in-flight cards.
That is intended and is recorded here so a later reader does not "fix" it.

## Design: auto-launch

```mermaid
flowchart TD
  A["skill invoked"] --> B{"path argument given?"}
  B -- yes --> C["repo := that path"]
  B -- no --> D["repo := git rev-parse --show-toplevel of cwd"]
  D --> E{"inside a git repo?"}
  E -- no --> F["abort 2: not a git repository"]
  E -- yes --> C
  C --> G{"CMUX_SURFACE_ID set?"}
  G -- no --> H["abort 2: no terminal surface (see Deferred)"]
  G -- yes --> I{"bind 127.0.0.1:TREKO_PORT"}
  I -- "in use" --> J["probe the listener"]
  J --> K["abort 2, naming whether it is another session's Treko"]
  I -- ok --> L{"store has a run for this repo?"}
  L -- no --> M["run analyze.py, write the store"]
  L -- yes --> N["leave the store alone"]
  M --> O["open browser at the bound URL"]
  N --> O
  O --> P["serve_forever"]
```

Three points on that flow are load-bearing.

**Resolving no-path.** `git rev-parse --show-toplevel` run in the cwd, not `$PWD` itself — a skill
invoked from a subdirectory should survey the repo, not the subdirectory. Outside a repository it is
an abort with that reason named, never a survey of an arbitrary directory.

**First-run analysis.** A no-path launch into a repo with no run would otherwise open an empty page,
which reads as "nothing is in flight" rather than "nothing has been measured". The analyzer runs
first in that case only. A repo that already has a run is **not** re-analyzed on launch — that would
make every launch pay the analyzer's cost and would silently overwrite a survey the user was reading.
Re-running is what the existing `reanalyze` button is for.

**The busy port does not auto-open.** When the bind fails because something already holds the port,
the server probes it and reports what it found, then exits `2`. It does **not** open a browser at the
existing server. That server belongs to a different Claude session and its command buttons type into
*that* session — opening it would hand the user a control channel aimed at a session they did not
launch. The skill's own docs record the precedent: a send at a *deduced* surface once reached a
different live Claude session at exit `0`. Naming the situation is the fix; routing around it is not.

The probe is `GET /` with a 2s timeout, and it may only distinguish two outcomes: *a Treko page came
back* or *it did not*. It must not attempt to identify **which** session owns it — nothing in the
response can answer that, and a confident-sounding guess there is worse than none.

### The nested rows are not portable yet

The prototype's page renders a three-level feature → story → task list with links out to Rally. It
is the most visible improvement in that file, and it is the one piece of its markup this card must
**not** take, because the data behind it does not exist:

```sh
# every identifier the prototype's nested rows read:
grep -o 'f\.rally[A-Za-z]*\|f\.stories\|st\.tasks' "$PROTO/Task Tracker.dc.html" | sort | uniq -c
#   5 f.rally   1 f.rallyId   1 f.rallyUrl   4 f.stories   2 st.tasks
# and what the producer side actually has:
grep -c '"rally"\|"rallyId"\|"rallyUrl"\|"stories"\|"story"' task-tracker/tracker-data.js
#   0        (same for tracker-data.sample.js, and for analyze.py)
```

Measured 2026-08-21. The analyzer emits no Rally field and no story level — its features contain
tasks directly. Beware one false positive when re-deriving: a case-insensitive `grep rally` over
`analyze.py` returns one hit, and it is the word "lite**rally**" in a comment on line 11.

Shipping that markup has exactly two outcomes and both break a promise this card makes. Either the
section renders empty — a UI element that looks like a measurement and reports nothing, which
`rules/core-conduct.md` names directly ("never render a metric the payload cannot source") — or
someone extends the store to fill it, which is the ad-hoc schema extension **ADR 0023 forbids**
without a `questions[]` entry and a conversation with the export's owner.

Note that this card already leaves out the prototype's per-run delete and re-analyze affordances for
the same reason: no backend. The nested rows are the same class of thing and get the same treatment.
Card 3 owns them, and its first task is the schema conversation, not the markup.

### Auto-launch must start the server the way the docs tell a human to

The skill's two "both fail silently" warnings — **never detach the process**, **never redirect
stderr** — currently govern a command a human types. Auto-launch makes that command something the
code issues, and a warning aimed at a reader does not bind a caller. Restate it as a requirement:

- The launcher **must** leave the server as a direct child of the Claude session: no `nohup`, no
  `setsid`, no `&` into a disowned shell, no launchd job. The parent-pid watchdog is what makes the
  control channel die with the session, and detaching silently disables it — `os.getppid()` never
  changes again, so the check never fires.
- The launcher **must not** redirect or capture stderr into a file or `/dev/null`. Every request
  writes one audit line there naming the outcome, the resolved surface, and whether a keystroke was
  sent. That stream is the only record of where keystrokes went.
- Opening the browser **must not** fork a process that becomes the server's new parent. Call
  `webbrowser.open()` from inside the already-running server process, after a successful bind and
  before `serve_forever`, so the process tree is unchanged.

This is the same failure class the card is built to avoid, one level removed: a control that is
present in the code and inert, where neither a code read nor the test suite notices.

### Serving a `.png`

`server.py` serves a closed list (`STATIC_MANIFEST`) and refuses to start if any entry's extension is
absent from `EXTENSION_TYPES` (`check_manifest_types`). `treko-icon.png` therefore needs **both** a
manifest row and an `.png: image/png` type entry. Copy only `treko-icon.png` (~91 KB);
`treko-logo.png` is ~1.2 MB and is used by the prototype's landing page, which is out of scope.

### Re-vendoring the ported markup

The prototype loads Phosphor from `unpkg.com` and Inter from `fonts.googleapis.com`. This repo
vendors both. Porting the prototype's page must swap those back:

| prototype | repo |
|---|---|
| `https://unpkg.com/@phosphor-icons/web@2.1.1/src/regular/style.css` | `vendor/phosphor/regular/style.css` |
| `https://unpkg.com/@phosphor-icons/web@2.1.1/src/fill/style.css` | `vendor/phosphor/fill/style.css` |
| `@import url('https://fonts.googleapis.com/css2?family=Inter…')` | `@import url('vendor/inter/inter.css')` |

and must re-add the two script tags the prototype does not have: `./vendor-resources.js` and
`tracker-data-fallback.js`.

A launched page that reaches the network at all is a defect, not a cosmetic issue: the server binds
`127.0.0.1` precisely so a survey of a private repo never leaves the machine.

## Acceptance criteria

1. **Given** the repo at this card's merge commit, **when** `git grep -iE 'task[-_ ]tracker'` runs
   excluding `docs/decisions/`, `coding-memory/` and the two out-of-scope cards, **then** it returns
   no results.
2. **Given** the same commit, **when** `ls skills/` runs, **then** `treko/` exists and
   `tracking-feature-state/` does not.
3. **Given** the same commit, **when** `git log --follow treko/server.py` runs, **then** it shows
   commits predating this card — the move preserved history.
4. **Given** the five existing test modules, **when** the suite runs from `treko/`, **then** every
   test that passed before the rename passes after it, with the same count. Record the count from a
   run, not from this document.
5. **Given** `TREKO_PORT=9001`, **when** the server starts, **then** it binds 9001; **and given**
   `TASK_TRACKER_PORT=9001` with `TREKO_PORT` unset, **then** it binds the default 8422 — the old
   name is dead, not silently honoured.
6. **Given** a repo with no run in the store and a valid cmux surface, **when** the skill is invoked
   with no path from a subdirectory of that repo, **then** the analyzer runs once against the repo
   root, the store gains exactly one run, and a browser opens at the bound URL.
7. **Given** a repo that already has a run, **when** the skill is invoked with no path, **then** the
   analyzer does **not** run and the store's `generated_at` is unchanged.
8. **Given** the cwd is not inside a git repository, **when** the skill is invoked with no path,
   **then** the server exits `2` with a message naming that reason, and no browser opens.
9. **Given** `TREKO_PORT` is already held by another process, **when** the server starts, **then** it
   exits `2`, its message states whether a Treko page answered the probe, and **no browser opens**.
10. **Given** the served page, **when** it is loaded with the network unavailable, **then** it renders
    with correct icons and typography — no request leaves `127.0.0.1`.
11. **Given** `STATIC_MANIFEST` contains `treko-icon.png`, **when** the server starts, **then**
    `check_manifest_types` passes; **and when** `GET /treko-icon.png` is requested, **then** the
    response carries `Content-Type: image/png`.
12. **Given** the renamed page, **when** the server starts, **then** `check_index_injectable` finds a
    `<head>` in `Treko.dc.html` and the per-launch token is injected at request time — never written
    to disk.
13. **Given** the store written by the renamed tool, **when** the prototype's unmodified
    `Ledger.dc.html` and `Task Tracker.dc.html` load it over `file://`, **then** the contract holds by
    these four checks, not by eyeball: (a) `window.TRACKER_DATA` is defined and `runs` is a non-empty
    array; (b) the browser console reports zero uncaught errors; (c) the board's run count and the
    Ledger's `runCount` both equal `TRACKER_DATA.runs.length`; (d) for the first run, `features`,
    `branches` and `waves` each render at least one row when the store has at least one. A page that
    renders its chrome while silently dropping a section passes an eyeball check and fails (c)/(d),
    which is the failure this criterion exists to catch.
14. **Given** this card's branch, **when** `docs/decisions/` is listed, **then** exactly one new ADR
    exists recording the rename and the ADR 0023 ruling, and ADRs 0022–0025 are byte-identical to
    their state on `main`.
15. **Given** `CMUX_SURFACE_ID` is unset, **when** the skill auto-launches, **then** the server exits
    `2` naming that reason and no browser opens — the pre-rename behaviour, asserted rather than
    assumed, because auto-launch is what turns this from a rare path into a common one. This is the
    behaviour §Deferred proposes to change later; pinning it now means that later change has a test
    to flip rather than a gap to fill.
16. **Given** the running server, **when** its process tree and file descriptors are inspected,
    **then** its parent is the Claude session (not `1`), and its stderr is a terminal or the
    session's captured stream — not a file and not `/dev/null`. Auto-launch must satisfy the same
    contract the docs impose on a human (§"Auto-launch must start the server the way the docs tell a
    human to").
17. **Given** the ported page at this card's merge commit, **when** it is searched for the five
    identifiers the prototype's nested rows read (`f.rally`, `f.rallyId`, `f.rallyUrl`, `f.stories`,
    `st.tasks`), **then** none appear. **What this proves and what it does not:** it catches the
    realistic failure — task 6 copying the prototype's rows verbatim — and nothing more. It is a
    string match against five names the prototype uses today, so it would not see the same feature
    re-implemented under different bindings, nor a hardcoded placeholder that reads no data at all.
    Those need someone to work around task 6 rather than slip past it, so the guard is sized to the
    mistake, not to the space of all mistakes. Do not cite a pass here as evidence of the broader
    claim.


## Deferred

Named here so cards 2–5 inherit them explicitly, and so no reader mistakes them for oversights.

- **Treko cannot run outside cmux.** The server exits `2` when `CMUX_SURFACE_ID` is unset, because the
  keystroke surface is inherited and never deduced. Auto-launch does not change this, so
  "always launches" is true inside cmux and **false** outside it. Making Treko serve a
  degraded, no-control-channel page outside cmux — buttons become copy-chips, `reanalyze` still
  works because it sends no keystroke, `POST /command` returns `503` — is agreed follow-up work and
  is not in this card. Decided 2026-08-21.
- **The nested feature → story → task rows and their Rally links** (card 3). The markup exists in
  the prototype; the `rally`/`stories` fields it reads exist nowhere on the producer side. Card 3
  must open the ADR 0023 conversation with the schema owner **before** the markup lands, not after.
  See §"The nested rows are not portable yet".
- **Renaming a run** (card 3) exists in neither the repo nor the prototype.
- **The agent panel's token counter** (card 4) has **no data source today**. The cmux channel is
  write-only: it types characters at a terminal and cannot read a token count back. Any number shown
  in that top bar while the panel drives the launching session would be fabricated. Card 4 must
  resolve this before the counter is built — see `rules/core-conduct.md`, "never render a metric the
  payload cannot source".
- **Agent-panel persistence past session close** (card 4) contradicts the server's parent-pid
  watchdog, which exists so a channel that can type into a full-permission session cannot outlive
  that session. Card 4 must decide this deliberately; the likely shape is a separate Claude process
  Treko owns rather than the borrowed cmux surface.
- **The Ledger list and its persistent queue** (card 2), **the dashboard upgrades** (card 3), and
  **the analyzer's up/down traversal with PRs** (card 5).

## Pinned versions

| Tool | Version | Where it is fixed |
|---|---|---|
| Python | 3.9.6 | the interpreter this repo's suite runs under; `server.py` targets stdlib only |
| pytest | 8.4.2 | test runner |
| Phosphor Icons | 2.1.1 | already vendored under `vendor/phosphor/` — do not re-fetch |
| Inter | vendored `inter-latin.woff2` | `vendor/inter/` — no version upstream; the file is the pin |
| Nocturne export | `73641b21-c7ad-488a-8264-a28262dfe83e`, schema `version: 1` | `_ds/` directory name; ADR 0023 |

No new dependency is added by this card. Adding one would need a separate ask
(`rules/core-conduct.md`, Parallel-Agent Invariants).

## Tasks

- [x] 0. Branch `feat/treko-rename` + worktree. **Only after `gate confirmed`.**
      Gate confirmed 2026-08-21. Branched from `treko-uddate` @ `29503ff`, which already
      carries this spec and its judge verdicts, so spec and implementation land in one PR.
      Reused the existing `treko-ui-update` worktree rather than cutting a new one — it is
      already an isolated checkout and nothing else is in flight in it.
- [x] 1. **Red first.** Add the failing tests for criteria 5, 6, 7, 8, 9, 11 and 16 against the
      *current* names, and confirm each fails for the stated reason. Do not touch implementation in
      this step.

      **Criteria 15 and 17 are green today and are pinned, not driven.** Write both, record that
      each passes on the pre-change tree, and say why rather than manufacturing a red state:

      - 15 (no cmux surface → exit `2`) is today's behaviour, pinned so the §Deferred change to it
        has a test to flip rather than a gap to fill.
      - 17 (the page contains none of `f.rally`, `f.rallyId`, `f.rallyUrl`, `f.stories`, `st.tasks`)
        is a **regression guard**, not a driver. Verified 2026-08-21: all five are `0` in
        `task-tracker/Task Tracker.dc.html` today. It exists to fail the moment task 6 ports more of
        the prototype's page than branding — which is precisely the mistake this card's own first
        draft made.
      **Done.** Two new modules: `test_rename.py` (criteria 5, 11, 17) and
      `test_autolaunch.py` (criteria 6, 7, 8, 9, 15, 16). Measured: **25 failed, 4 passed**.
      The 4 passing are exactly the ones documented green-and-pinned — criterion 15, criterion
      17, the producer-side premise 17 rests on, and `check_manifest_types` — none manufactured
      red.
      - **Spec slip, implemented against reality:** criterion 7 names the store key
        `generated_at`; the real key is `generatedAt` (`store.py`, `new_store`). The tests use
        the real key. Not treated as a spec gate — a field-name slip changes no design — but
        recorded because a guessed name fails closed, and failing closed is indistinguishable
        from the check being switched off.
      - **Two criteria could not be red alone and are asserted as conjunctions.** Criterion 7
        ("the analyzer does *not* run") and criterion 16's process-tree half are both vacuously
        true while auto-launch does not exist. Each is paired with the browser-opened half, so
        neither can pass on an empty feature. Two further tests that first passed vacuously —
        the two "no browser opens" aborts — now re-assert the abort *reason*, because any abort
        at all opens no browser, argparse usage errors included.
      - **Criterion 5's negative half is a unit test, not a launch.** A server that ignores the
        retired override binds `DEFAULT_PORT`, and asserting on 8422 in a test would collide
        with any real Treko holding it. `read_port` takes an `environ` mapping, so the claim is
        provable with no port at all.
      - **What this red run did NOT establish:** 8 of the 9 `test_autolaunch.py` failures share
        one upstream cause — no `--open`, so the process dies in argparse before reaching any
        behaviour under test. Eight tests agreeing is one cause repeated. Task 8 must observe
        each failing for its *own* reason before making it pass.
      - **Wording the spec left open is now pinned by the tests**: `NO_REPO_RE` and `PROBE_RE`
        in `test_autolaunch.py` are the contract for the two abort messages.

- [x] 2. Record the pre-rename suite count from an actual run; paste the output into §Verification.
      **Done.** `161 passed in 112.09s`, exit 0, run 2026-08-21 — see §Verification.

- [x] 3. `git mv task-tracker treko` and `git mv skills/tracking-feature-state skills/treko`. Fix
      `SERVE_ROOT`-relative paths, `conftest.py`, `server_harness.py` and the five test modules until
      the suite is green again at the same count as task 2.
      **Done. `161 passed in 111.29s`, exit 0 — same count as the task-2 baseline.** Both
      directories moved with `git mv`, so history follows. `__pycache__` was deleted repo-wide
      before the move so no import could resolve to the old tree and pass for the wrong reason.
      Ten files needed path fixes; the load-bearing one was `server_harness.py`'s
      `REAL_TREE = REPO_ROOT / "task-tracker"`, which every server test resolves through.
      - **`store.py`'s `TOOL` string stays `"task-tracker v0.4.1"`.** The card said to change it
        only after confirming no consumer reads it. One does: the page renders it as
        `toolLabel` (`grep -n 'data.tool' treko/`). So it stays, per the card's own "if in
        doubt it stays".
      - **`server.py`'s `server_version` HTTP header** changed to `"treko"`. Checked first that
        no test asserts it — this is the server's own identity, not store payload.
      - **`Task Tracker Directions.dc.html` left untouched, filename included.** It is the
        historical four-direction design canvas, is not on `STATIC_MANIFEST`, and is never
        served. Editing it would falsify a record the same way editing a merged ADR would.
      - **Criteria 2 and 3 verified here rather than deferred.** `skills/treko/` exists and
        `skills/tracking-feature-state/` does not. `git log --follow treko/server.py` returns 3
        commits, two of which (`8e16f74`, `b2e9bab`) predate this card.
      - ⚠️ **GATE: criterion 1 is unsatisfiable alongside §Decision.** Criterion 1 requires
        `git grep -iE 'task[-_ ]tracker'` to return **nothing** outside `docs/decisions/`,
        `coding-memory/` and the two out-of-scope cards. But §Decision deliberately preserves the
        data contract, and that contract *contains the string*. After every remaining task
        finishes, this residue survives by design:

        | file | why it must stay |
        |---|---|
        | `treko/store.py:28` | `TOOL = "task-tracker v0.4.1"` — written into the store, rendered by the page as `toolLabel` |
        | `treko/store.py:6`, `treko/analyze.py:4` | prose naming the external export version |
        | `treko/tracker-data.json:3` | the schema document's own `tool` value |
        | `treko/tracker-data.sample.js:3` | the sample payload's `tool` value |
        | `treko/test_store.py:145` | asserts that `TOOL` value |
        | `treko/tracker-data.js` | generated store; contains `"tool": "task-tracker v0.4.1"` |
        | `treko/Task Tracker Directions.dc.html` | historical design canvas — filename included |

        Criterion 1's exclusion list omits exactly what the card's central decision protects.
        **Not worked around and not silently narrowed** — the fix is a spec edit widening that
        exclusion list, which `phase: implementation` forbids. Tasks 4 onward do not depend on
        it, so work continues; criterion 1 cannot be evaluated at task 13 until this is resolved.

- [x] 4. Rename the four environment variables in `server.py`. Assert the old names are **not** read
      (criterion 5) — a silent fallback is the failure mode here.

      **Done 2026-08-21.** Renamed `PORT_ENV` and the third element of the `IDLE_SECS` /
      `POLL_SECS` / `ANALYZE_SECS` spec tuples in `treko/server.py`. Collateral updated in
      `treko/server_harness.py` (env-pop list, `launch()`'s port override) and, as the narrow
      test-collateral exception, `treko/test_server.py:600` and `treko/test_server_lifetime.py`
      (docstring prose, two `overrides={}` dicts, and the floor-warning stderr assertion, which
      reads the env var name straight from `server.py`'s own tuple — no assertion value, timeout,
      or `pytest.mark` was changed). `test_rename.py::test_read_port_ignores_the_retired_port_name`
      and the full 8-test `-k "read_port or timeout_spec"` selection pass; full suite holds at 161
      passed. `git grep -n 'TASK_TRACKER_' -- treko/` now returns only `test_rename.py`, the
      data-contract oracle that tests for the retired names' absence.
- [x] 5. `git mv "treko/Task Tracker.dc.html" treko/Treko.dc.html`; update `INDEX_FILE` and
      `check_index_injectable`'s message.

      **Done 2026-08-21.** `git mv "treko/Task Tracker.dc.html" treko/Treko.dc.html`, then
      `INDEX_FILE = "Treko.dc.html"` in `treko/server.py:55`. Lines 194, 198, 200, 432 and 436 all
      interpolate the constant and needed no edit — confirmed by reading each, not by trusting the
      grep. Collateral: `treko/test_ui_commands.py:36`'s hardcoded `HTML` path, a comment in
      `treko/test_analyze.py:30`, and the table row in `treko/github.md:15`. `test_rename.py:147`
      and `test_server_lifetime.py:102` reach the page through `server.INDEX_FILE` and needed no
      edit — confirmed by grepping both files for `INDEX_FILE`. Full suite holds at 161 passed;
      `test_rename.py` is 4 failed (all `treko-icon.png`, task 6's job), 15 passed. `git grep -n
      'Task Tracker\.dc\.html' -- treko/ skills/` now returns only `skills/treko/SKILL.md:105`,
      task 9's scope. Criterion 12 (no dedicated test) is verified only by the server starting and
      `test_server_lifetime.py::test_an_index_with_no_head_aborts_before_serving` passing through
      `server.INDEX_FILE` — this proves the abort path still resolves the renamed file, not that a
      real `<head>` scan against `Treko.dc.html`'s actual bytes was separately exercised beyond
      what that test already covers.
- [x] 6. Port **only the branding** from the prototype page: Treko icon, sidebar title, retinted
      accent palette. Swap the three CDN references back to vendored paths and re-add the two script
      tags (§Re-vendoring). Copy `treko-icon.png` in; add its manifest row and `.png` type entry.
      **Do not port the nested feature → story → task rows or the Rally links** — see
      §"The nested rows are not portable yet". Porting them is card 3, after the schema conversation.

      **Done 2026-08-22. The repo page was a sibling revision, not an older one — re-verified
      before editing, not assumed.** Four of the card's rows were already satisfied by prior
      tasks: the `--color-accent*` values are byte-identical between the two `styles.css` files
      (`diff` returns exactly one line, the font `@import`); the page already links vendored
      `vendor/phosphor/{regular,fill}/style.css` with no `unpkg.com` reference; the Inter
      `@import` lives in `styles.css:2`, not the page, and is already
      `vendor/inter/inter.css`; and both `./vendor-resources.js` and `tracker-data-fallback.js`
      script tags are already present. None of these were touched.

      Actual work: copied `treko-icon.png` (91,124 bytes, prototype mtime 2026-08-21 15:46:37)
      into `treko/`; replaced the three `<i class="ph ph-crosshair">` glyphs (empty state,
      collapsed rail, expanded header) with the prototype's `<img src="treko-icon.png">` markup
      at matching sizes (48px/30px/26px); changed the sidebar title `Task Tracker` → `Treko`;
      changed two prose strings (`Treko.dc.html`, empty-state and agent-panel copy) from
      "task-tracker skill" to "treko skill"; fixed the `reanalyze` copy-command from
      `python3 task-tracker/analyze.py .` to `python3 treko/analyze.py .` — a real bug, not a
      cosmetic rename, since `task-tracker/` stopped existing at task 3 and nothing in the test
      suite asserted the string; added `treko-icon.png` to `STATIC_MANIFEST` and `.png:
      image/png` to `EXTENSION_TYPES` in `server.py`. CSP already carried `img-src 'self'
      data:` — confirmed, not changed.

      `store.py`'s `TOOL` and the page's `toolLabel:data.tool||'task-tracker'` fallback
      (`Treko.dc.html:634`) were deliberately left alone, per task 3's prior ruling — the UI
      must not disagree with the store's producer identifier.

      `test_rename.py -q`: **19 passed** (was 15 passed / 4 failed before this task; all four
      icon tests, criterion 11, now green; criterion 17's
      `test_page_contains_no_nested_row_identifiers` still passes — no nested rows ported).
      Full baseline suite: **163 passed** in 112.13s, not 161 — the two extra are
      `test_server.py`'s table-driven `@pytest.mark.parametrize("relative",
      server.STATIC_MANIFEST)` tests (`test_every_manifest_row_is_served_with_its_mapped_type`,
      `test_every_manifest_row_carries_nosniff`), whose own docstring says "a row added later is
      covered unedited" — one new manifest row is exactly one new instance per parametrized
      test, not a new test. No test was added or removed by hand.

      `git grep -n -i 'task[-_ ]tracker' -- treko/Treko.dc.html` returns only
      `Treko.dc.html:634`'s `toolLabel` fallback, as expected. `grep -rn
      'fonts.googleapis\|unpkg.com' treko/` returns only the four pre-existing hits named in the
      dispatch (the `vendor-resources.js` URL→local map, its comment, `support.js`'s fallback
      URLs, a `test_server.py` comment, and `vendor/inter/inter.css`'s own comment) — nothing new
      in the page or `styles.css`. This is a smoke check only, not proof of criterion 10; task 7
      owns that proof.
- [x] 7. **Prove no network egress** (criterion 10). A grep for `http` in the page is not sufficient
      evidence — load the served page with the network down, or assert on the request log. State
      which check was run and what it cannot see.

      **Done 2026-08-21. Two static checks run; the decisive runtime check (real browser,
      network log) is separate and outstanding — see §Verification.** Check A confirmed the
      `window.__resources` fallback map in `vendor-resources.js` matches `support.js`'s three
      CDN URL constants by exact set equality (not length, not "looks similar"), that each
      mapped value is a real file under `treko/` and a `STATIC_MANIFEST` row, and that
      `vendor-resources.js` loads before `support.js` (`Treko.dc.html:6-7`). Check B resolved
      every `src=`/`href=`/`@import`/`url(...)` reference transitively from `Treko.dc.html`,
      including into the two CSS files that themselves have nested `@import`/`url()`
      (`_ds/nocturne-*/styles.css` → `vendor/inter/inter.css`, and both Phosphor
      `style.css` files → their `.woff2`) — all 13 local assets resolve to files on disk and to
      `STATIC_MANIFEST` rows; the only absolute scheme+host references found were the three
      gated CDN URLs and the per-task `{{ t.prHref }}` GitHub links, which are user-clicked
      hyperlinks rendered from `tracker-data.js`, not page-load fetches. Neither check proves
      the browser actually honors the fallback map — see §Verification for what is and is not
      established. Full baseline suite unaffected: no test added, removed, or edited.
- [x] 8. Implement auto-launch: `--open`, no-path repo resolution via `git rev-parse --show-toplevel`,
      first-run-only analysis, and the busy-port probe that reports and exits without opening.
      `webbrowser.open()` is called from inside the server process after bind, never as a forked
      child — criterion 16 asserts the resulting process tree and stderr, not the intent.
      **The repo path is an argv element, never shell-interpolated.** Every `git` and `analyze.py`
      invocation on this path uses a `subprocess` argument list with `shell=False`; no f-string, no
      `os.system`, no `shell=True`. A directory name is attacker-controllable in the general case,
      and the launcher now runs unattended, which is the pairing that turns a quoting bug into
      command execution. See `writing-secure-code`.

      **Done 2026-08-21.** Step-1-only red run (`--open` added, nothing else) confirmed every one
      of the 8 `test_autolaunch.py` failures now dies for its own reason, not the shared argparse
      cause from task 1 — see the table below. `test_autolaunch.py`: **10 passed**. `test_rename.py`
      stays **19 passed**. Full baseline: **163 passed in 112.63s**, same count as task 6.
      `grep -n 'shell=True\|os.system' treko/server.py` returns nothing.

      | test | own failure after `--open` alone |
      |---|---|
      | `test_outside_a_git_repository_the_server_aborts` | `wait()` returned `None` (timeout) — with no repo validation the old default (`--repo` = `SERVE_ROOT.parent`) accepted the bogus cwd and the server kept serving instead of aborting |
      | `test_outside_a_git_repository_no_browser_opens` | stderr held the normal startup banner, not `NO_REPO_RE` — same missing-validation cause as above, asserted from the browser side |
      | `test_no_path_launch_analyzes_the_repo_root_once` | store had 0 runs, not 1 — no first-run analysis existed yet |
      | `test_no_path_launch_opens_the_browser_at_the_bound_url` | `browser_log.opens == []` — no `webbrowser.open()` call existed yet |
      | `test_existing_run_is_not_reanalyzed_on_launch` | same — conjoined on the browser half, so it failed there too |
      | `test_busy_port_aborts_and_reports_the_probe` | stderr held the old static EADDRINUSE message ("a server from another session is probably still holding it") — `PROBE_RE` needs "probe" + "answered"/"did not answer", and no probe was made |
      | `test_busy_port_opens_no_browser` | same old static message — this test's own claim (no browser on a busy port) was actually already true, but it re-asserts the reason first per its own docstring, so it failed on the message |
      | `test_opening_the_browser_does_not_reparent_the_server` | `browser_log.opens == []` — no browser call existed yet |

      Two pairs share an upstream cause honestly: the two no-repo tests both trace to "no repo
      validation existed," and `test_busy_port_opens_no_browser` shares its message assertion with
      `test_busy_port_aborts_and_reports_the_probe`. Each still failed on its *own* specific
      assertion (a different `assert` line, not a collection error), so none of the eight were
      failing for the single upstream `--open`-missing reason anymore.

      **Design decision not spelled out in the card, made and recorded here:** first-run analysis
      and `webbrowser.open()` are gated on `args.open_browser` (`--open`), not unconditional
      whenever the store has no runs. The first attempt ran them unconditionally and broke two
      baseline tests that start the server without `--open` against a deliberately emptied or
      symlinked `tracker-data.js` (`test_tracker_data_absent_is_404_not_500`,
      `test_a_manifest_row_that_symlinks_out_of_the_tree_is_403`) — the server silently ran the
      real analyzer against the real repo and overwrote their fixture. Repo resolution
      (`resolve_repo`) is *not* gated the same way — it always applies when `--repo` is omitted,
      matching the card's mermaid flow — but every baseline test passes `--repo` explicitly
      (`server_harness.py`'s `launch()` always does), so this never engages outside
      `test_autolaunch.py`.

      **A pre-existing baseline test constrained the busy-port message wording.**
      `test_server_lifetime.py::test_a_second_server_on_the_same_port_aborts_and_leaves_the_first_intact`
      (not owned by this task, not editable) asserts the literal substring `"Not probing for a free
      port"` is still present. The final message satisfies both that literal string and `PROBE_RE`
      in the same sentence, e.g. `"...the probe answered as a Treko page already serving there. Not
      probing for a free port.\n"`.

      **The probe's signature check.** `probe_listener()` reads the responding server's own
      `Server` header (`server_version = "treko"`, set at `treko/server.py:392`) and checks for
      `"treko"` case-insensitively. This does not identify *which* session owns the port — it only
      confirms the process holding it is a Treko server at all, which is the one fact the card
      permits reporting.

      **Criterion 16 (process tree + stderr).** Proven by
      `test_opening_the_browser_does_not_reparent_the_server`, which spawns a real server with a
      real `BROWSER` recorder script, waits for it to serve, and asserts
      `ps -o ppid= -p <server pid>` equals the *test process's* own pid — i.e. the server's parent
      is whoever launched it, not `1` and not the browser-open call. Stderr was captured throughout
      by opening a file and handing it to `Popen(..., stderr=handle)` (the harness's own pattern);
      `server.py` never reassigns or closes its own stderr, and no new code path in this task writes
      to anything but `sys.stderr`.

      **Not independently verified beyond the test suite:** that a *real* OS browser (not the
      `BROWSER`-env recorder) opens correctly end-to-end — the recorder proves `webbrowser.open()`
      was called with the right URL, which is what `webbrowser` itself execs, but this task did not
      manually launch Chrome/Safari against a live server.
- [x] 9. Rewrite `skills/treko/SKILL.md`: `name: treko`, the description, the single launch command,
      and the trigger phrases. Keep the two "both fail silently" warnings about detaching and
      redirecting stderr — auto-launch does not retire either.

      **Done 2026-08-22.** Frontmatter `name: treko`, description rewritten for the new name and
      auto-launch behaviour. Title `# Tracking Feature State` → `# Treko`. `task-tracker/` →
      `treko/` at the three anchor lines; env vars `TASK_TRACKER_PORT`/`TASK_TRACKER_IDLE_SECS` →
      `TREKO_PORT`/`TREKO_IDLE_SECS`; the no-`<head>` message → `Treko.dc.html has no <head>`.
      The launch section now documents one command, `python3 treko/server.py --open`, with
      `--repo` noted as optional (resolved via `git rev-parse --show-toplevel` when omitted) —
      replacing the old two-step "run this, then paste this URL" instructions. Kept both
      "both fail silently" warnings verbatim, with their reasoning, and added a sentence stating
      auto-launch makes them *stronger* rather than retiring them, per the card's own wording.
      The busy-port table row was split into the two real messages read from `server.py:743-748`
      (probe answered / probe did not answer) rather than paraphrased, and a new row was added for
      the not-a-git-repo abort, since that path is new. Trigger phrases updated ("launch Treko for
      this repo").

      **The trap:** the launch command and the two redirect/detach prohibitions are still on
      separate lines — `test_the_skill_documents_a_launch_command_that_does_not_detach` filters on
      lines containing `server.py` and only one such line exists (`python3 treko/server.py --open`),
      carrying no `nohup`/`setsid`/`2>`/trailing `&`.

      Verified: `test_autolaunch.py` 10 passed, `test_rename.py` 19 passed, full baseline
      (`test_analyze.py test_store.py test_server.py test_server_lifetime.py test_ui_commands.py`)
      163 passed in 113.10s. `git grep -n -i 'task[-_ ]tracker' -- skills/` returns nothing.
      Sanity-ran the documented command directly (`TREKO_IDLE_SECS=60 TREKO_PORT=8434 python3
      treko/server.py --open`, no `nohup`/`&`): it printed the startup banner, served the page and
      its assets (request log shows 17 accepted requests, one 404 for `favicon.ico`), bound with
      `ppid` = the invoking shell (not 1), and left no process running after `kill`.
- [ ] 10. `PORTS.md` row, `README.md:62` roadmap entry, `CLAUDE.md` skills-catalog line, `.gitignore`
      comment.
- [ ] 11. Verify criterion 13: load the prototype's two unmodified pages against the store this tool
      writes and run all four checks (a)-(d). Record which check caught what; "both rendered" is not
      an acceptable entry in §Verification.
- [ ] 12. ADR `docs/decisions/0033-…` — the rename, and why the data contract was exempted. Confirm
      `0033` is still free against `origin/main` **and** every other ref at the moment of writing;
      `0032` is already taken on another branch, `0028` is a gap, and `0030` exists on `origin/main` but
      not in this worktree — so the next number is not derivable from a local `ls`.
- [ ] 13. Full suite green; record the post-rename count run, not read. Fill §Verification.
- [ ] 14. Observability judge, then draft PR.
- [ ] 15. Close the card: set `phase: review`, and record here which of §Deferred card 2 inherits.

## Risks

- **A silent env-var fallback.** Renaming a variable while leaving `os.environ.get` reading the old
  name too is the easy, invisible mistake: everything passes, and the rename is half-done in the one
  layer nobody re-reads. Criterion 5 asserts the negative deliberately.
- **The suite passing for the wrong reason.** After a directory move, an import that silently resolves
  to the *old* tree still on disk would pass. Task 3 must run from a clean checkout, or delete the old
  path before running.
- **Forking the data contract by accident.** A find-and-replace over `task.tracker` case-insensitively
  will also hit `taskTracker.*` and `tracker-data`. Scope every replacement; criterion 13 is the
  backstop that catches it.
- **The prototype moving underneath us.** It is a live design source outside this repo and outside
  version control here. Task 6 should record the prototype's file mtimes it ported from, so a later
  reader can tell whether the source has changed since.

## Verification

_Nothing here is written before the command that produces it has been run and its output re-read._

### Pre-rename baseline (task 2, 2026-08-21)

Criterion 4 compares against this. It is the output of a run, not a count read from anywhere:

```
$ python3 -m pytest test_analyze.py test_store.py test_server.py \
      test_server_lifetime.py test_ui_commands.py -q
161 passed in 112.09s (0:01:52)          # exit 0
```

Per module, from `--collect-only` so a post-rename mismatch names a file rather than a total.
26 + 30 + 81 + 9 + 15 = 161, and the total was re-derived from the collection rather than summed
by hand:

| module | tests |
|---|---|
| `test_analyze.py` | 26 |
| `test_store.py` | 30 |
| `test_server.py` | 81 |
| `test_server_lifetime.py` | 9 |
| `test_ui_commands.py` | 15 |
| **total** | **161** |

**What this baseline excludes, deliberately.** The two modules task 1 added
(`test_rename.py`, `test_autolaunch.py`) are **not** in it — they are red by design, and folding
them in would make the "same count" comparison meaningless. Criterion 4 is about the five modules
that existed before this card. Their own expected end state is separate: 25 failed / 4 passed at
task 1, all green by task 13.

**What it does not prove.** A passing suite before a directory move says nothing about whether the
move preserved the layout the suite depends on. `analyze.py` resolves `hooks/lib` as
`__file__/../../hooks/lib`, and the harness reproduces that relative layout under `tmp_path`; a
move that breaks it would surface as a collection error, not a count mismatch. Task 3 must run
from a clean checkout, or delete the old path first — an import that silently resolves to the old
tree still on disk would pass for the wrong reason.

### Criterion 10 — no network egress (task 7, 2026-08-21)

Two static checks were run against a throwaway script (not committed, not part of the test
suite). Neither is the decisive check; both are named as static-only below.

**Check A — the CDN→vendor fallback map, byte for byte.**

```
CDN URL constants from support.js:
  REACT_URL = 'https://unpkg.com/react@18.3.1/umd/react.production.min.js'
  REACT_DOM_URL = 'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js'
  BABEL_URL = 'https://unpkg.com/@babel/standalone@7.29.0/babel.min.js'

cdn_urls (set):      ['https://unpkg.com/@babel/standalone@7.29.0/babel.min.js', 'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js', 'https://unpkg.com/react@18.3.1/umd/react.production.min.js']
resource_keys (set): ['https://unpkg.com/@babel/standalone@7.29.0/babel.min.js', 'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js', 'https://unpkg.com/react@18.3.1/umd/react.production.min.js']

PASS: set equality holds between support.js CDN URLs and vendor-resources.js keys

Checking mapped values resolve to real files and are STATIC_MANIFEST rows:
  https://unpkg.com/react@18.3.1/umd/react.production.min.js             -> vendor/react.production.min.js           exists=True in_manifest=True
  https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js     -> vendor/react-dom.production.min.js       exists=True in_manifest=True
  https://unpkg.com/@babel/standalone@7.29.0/babel.min.js                -> vendor/babel.min.js                      exists=True in_manifest=True

PASS: all three mapped values are real files and STATIC_MANIFEST rows
```

Load order confirmed by reading `Treko.dc.html:6-7`: `<script src="./vendor-resources.js">`
precedes `<script src="./support.js">`, so the map exists in `window.__resources` before
`support.js`'s `cdnScriptFor` reads it.

**Check B — recursive local-asset resolution from `Treko.dc.html`.** Every `src=`, `href=`,
`@import` and `url(...)` was followed transitively, including into the two CSS files that
themselves nest further references:

```
src=/href= in Treko.dc.html:
  6:  src="./vendor-resources.js"
  7:  src="./support.js"
  12: href="_ds/nocturne-73641b21-c7ad-488a-8264-a28262dfe83e/styles.css"
  13: src="_ds/nocturne-73641b21-c7ad-488a-8264-a28262dfe83e/_ds_bundle.js"
  14: href="vendor/phosphor/regular/style.css"
  15: href="vendor/phosphor/fill/style.css"
  16: src="tracker-data.js"
  17: src="tracker-data-fallback.js"
  30/41/58: src="treko-icon.png"
  139: href="{{ t.prHref }}"   <- template binding, not a static reference (see below)
No @import / url() at the page level.

_ds/nocturne-*/styles.css:2   @import url('../../vendor/inter/inter.css')
vendor/phosphor/regular/style.css:3   url("./Phosphor.woff2")
vendor/phosphor/fill/style.css:3      url("./Phosphor-Fill.woff2")
vendor/inter/inter.css:16,26,36,46    url("./inter-latin.woff2")  (four @font-face blocks)

_ds_bundle.js: 0 matches for src=/href=/url(/@import
support.js: only the 3 CDN URLs already covered by Check A; no other absolute URL literal

All 13 resolved local assets: in_manifest=True exists=True for every one
  (vendor-resources.js, support.js, both _ds/nocturne-* files, both phosphor style.css,
   tracker-data.js, tracker-data-fallback.js, treko-icon.png, vendor/inter/inter.css,
   both .woff2 files)
```

The one non-local reference Check B found, `Treko.dc.html:139`'s `href="{{ t.prHref }}"`
(rendered from `tracker-data.js`'s GitHub PR URLs, e.g.
`https://github.com/suyatdev/.claude/pull/91`), is a user-clicked `<a href>` link to an
external site — a navigation a person triggers, not a fetch the page issues on load. It is
named here rather than silently excluded.

**What each check cannot see.**

- Neither check is the decisive one. A static check of source text cannot see a URL a script
  builds at runtime by string concatenation — nothing here rules that out for `support.js`'s
  other logic, only for the three named CDN constants.
- Neither check proves the *browser* actually honors `window.__resources` at request time —
  only that the map's keys equal the CDN constants and that the map is defined before
  `support.js` runs. Proving the browser follows it requires a real network log, which is a
  runtime check, not a static one.
- Check A covers exactly the three dc-runtime CDN scripts (React, ReactDOM, Babel). It says
  nothing about any other fetch the page's own code, `_ds_bundle.js`, or a future change might
  make — those weren't shown to make any (0 matches in `_ds_bundle.js`, only the 3 known URLs
  in `support.js`), but that absence is itself a static-text result, not a runtime guarantee.
- Check B follows every static markup and CSS reference reachable from the page's own files.
  It cannot see a reference injected by JavaScript at runtime (e.g. a `document.createElement`
  with a computed `.src`), and it does not execute `_ds_bundle.js`, `support.js`, or any inline
  script — it reads their source text for literals only.

**Criterion 10 is not proven by this task.** What is established: the fallback map is
byte-correct and ordered first, and every statically-discoverable local asset resolves to a
real, manifest-listed file with no undeclared absolute reference beyond the three gated CDN
URLs and the one user-facing external hyperlink. What remains open is whether a real browser,
loaded against this served page with the network unavailable, issues zero requests off
`127.0.0.1` — that is a runtime observation this task did not make.

**Runtime network-log check — run 2026-08-22, orchestrator session, real Chrome.**

Method: started the server on a non-default port (`TREKO_PORT=8433`) against this worktree,
loaded `http://127.0.0.1:8433/` in Chrome, enabled request tracking, then forced an **uncached**
reload (`cmd+shift+r`) and read the full request log. This is the card's *"assert on the request
log"* branch, **not** the *"network down"* branch — the machine's network was deliberately left
up rather than disabled.

Result: **42 requests across two full page loads, 21 each. Every request either targets
`http://127.0.0.1:8433/` or is a `chrome-extension://` content script belonging to the
operator's own browser. Zero requests to `unpkg.com`, `fonts.googleapis.com`, or any other
host.**

The load fetched, all from `127.0.0.1`: the page, `vendor-resources.js`, `support.js`,
`_ds/nocturne-*/styles.css`, `_ds/nocturne-*/_ds_bundle.js`, both Phosphor stylesheets,
`tracker-data.js`, `tracker-data-fallback.js`, `treko-icon.png`, `vendor/react.production.min.js`,
`vendor/react-dom.production.min.js`, `vendor/inter/inter.css`, `vendor/inter/inter-latin.woff2`,
`vendor/phosphor/regular/Phosphor.woff2`, `vendor/phosphor/fill/Phosphor-Fill.woff2`, and
`favicon.ico` (404 — the browser's automatic request, refused locally, so still no egress).

**This closes the gap task 7's static checks could not:** React and React-DOM were fetched from
`vendor/`, not from unpkg. That is the fail-open path in `support.js:1149-1153` observed *not*
firing at runtime, which no static check could establish.

A screenshot confirms the criterion's rendering half: the Treko icon, the "Treko" sidebar title,
Phosphor glyphs and Inter typography all render correctly with no network available to them.

**What this check cannot see:**
- **`vendor/babel.min.js` was never requested.** The page rendered without it, so the third
  `window.__resources` entry was **not exercised at runtime** — its key correctness rests on
  check A's static comparison alone. If a later change makes the page compile `text/x-dc` blocks
  in the browser, that entry becomes live and untested.
- It observed the two page loads inside the capture window only. A request fired later, or one
  fired only by a user interaction not performed here, would not appear.
- `Treko.dc.html:139`'s `href="{{ t.prHref }}"` GitHub PR link is deliberate, user-initiated
  egress and was not clicked. Criterion 10 concerns page load, not user navigation.
- The network was up. This proves nothing about *graceful degradation* if a fetch were attempted
  and failed — only that no such fetch is attempted.

**Criterion 10 is met on the request-log branch**, with the babel caveat above stated rather
than rounded away.
