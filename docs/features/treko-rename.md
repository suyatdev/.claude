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

- [ ] 3. `git mv task-tracker treko` and `git mv skills/tracking-feature-state skills/treko`. Fix
      `SERVE_ROOT`-relative paths, `conftest.py`, `server_harness.py` and the five test modules until
      the suite is green again at the same count as task 2.
- [ ] 4. Rename the four environment variables in `server.py`. Assert the old names are **not** read
      (criterion 5) — a silent fallback is the failure mode here.
- [ ] 5. `git mv "treko/Task Tracker.dc.html" treko/Treko.dc.html`; update `INDEX_FILE` and
      `check_index_injectable`'s message.
- [ ] 6. Port **only the branding** from the prototype page: Treko icon, sidebar title, retinted
      accent palette. Swap the three CDN references back to vendored paths and re-add the two script
      tags (§Re-vendoring). Copy `treko-icon.png` in; add its manifest row and `.png` type entry.
      **Do not port the nested feature → story → task rows or the Rally links** — see
      §"The nested rows are not portable yet". Porting them is card 3, after the schema conversation.
- [ ] 7. **Prove no network egress** (criterion 10). A grep for `http` in the page is not sufficient
      evidence — load the served page with the network down, or assert on the request log. State
      which check was run and what it cannot see.
- [ ] 8. Implement auto-launch: `--open`, no-path repo resolution via `git rev-parse --show-toplevel`,
      first-run-only analysis, and the busy-port probe that reports and exits without opening.
      `webbrowser.open()` is called from inside the server process after bind, never as a forked
      child — criterion 16 asserts the resulting process tree and stderr, not the intent.
      **The repo path is an argv element, never shell-interpolated.** Every `git` and `analyze.py`
      invocation on this path uses a `subprocess` argument list with `shell=False`; no f-string, no
      `os.system`, no `shell=True`. A directory name is attacker-controllable in the general case,
      and the launcher now runs unattended, which is the pairing that turns a quoting bug into
      command execution. See `writing-secure-code`.
- [ ] 9. Rewrite `skills/treko/SKILL.md`: `name: treko`, the description, the single launch command,
      and the trigger phrases. Keep the two "both fail silently" warnings about detaching and
      redirecting stderr — auto-launch does not retire either.
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
