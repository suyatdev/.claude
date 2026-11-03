<!--
The spec half of docs/features/treko-ledger.md (ADR 0017's synced pair). It carries no
frontmatter because it is not a card: the analyzer selects cards by filename and skips every
`*.spec.md` (`grep -n SPEC_SUFFIX treko/analyze.py`). It also carries no checkbox lines on
purpose: `hooks/lib/feature_tasks.py` `compare()` matches task numbers between the two halves,
and the card's ## Tasks is not written yet. The checklist and the verification record stay in
the .md; this file is design, contracts, scenarios and acceptance criteria.
-->

# Treko Ledger — build spec

**What this builds.** A home page for Treko, the **Ledger**. The user types a directory; Treko
finds every git repository in and around it, analyzes them on the server one job at a time with a
progress bar that moves only when real work finishes, and lists every finished run with Open and
Delete. The card is `docs/features/treko-ledger.md`. Its decisions are cited here by number (D1–D12,
"Builder check results", and the correction about `analyze.py` at the end of that section; D13–D15,
the user's decisions after compliance round 2, are cited as U1–U3, and D16–D18, his decisions after
round 3, as U4–U6: U1 = D13, U2 = D14, U3 = D15, U4 = D16, U5 = D17, U6 = D18; see the last two
sections). This file turns them into contracts and tests. It does not reopen them.

**Tags.** **(spec call)** marks a detail the card left open that this spec settles with the
simplest safe option; the reviewer can overturn any of them. **OQ-n** marks a choice that changes
what the user sees or touches safety. Those waited for the user, in the last section, "Open
questions — resolved 2026-11-03". Where behaviour below depended on one, the text first said
"pending OQ-n" and described the recommended answer. Since 2026-11-03 it names the answer and its
tag, as the card does: **(user)** when he decided it, **(my call)** when the planning session
settled it and told him.

**Ground truth.** Written 2026-11-03 against `feat/treko-ledger` @ `5f194df`. Every `file:line`
was opened at that commit. Lines move, so each citation also names the symbol to `grep -n` for.
Revised the same day for compliance round 1 at `6331b5d`. The code files had not changed, so the
citations still hold, and the sizes in §1.1 were measured there.
Revised again the same day for compliance round 2 and the user's decisions after it (U1–U3, listed
at the end) at `d85eabd`. `git diff --stat 5f194df..HEAD -- treko skills/treko` still prints
nothing, so every citation and size above still holds. Round 2's new measurements are each given
with the command or scratch probe that produced them; the probes ran in scratch copies, never in
this repository.
Revised a third time the same day for compliance round 3 and the user's decisions after it
(U4–U6) at `50c0f44`; the same `git diff --stat 5f194df..HEAD -- treko skills/treko` still prints
nothing. Round 3's probes are `probe_r3.sh` and `probe_partial_clone.sh` in the round-3 scratch
folder, run against a `git archive HEAD treko hooks/lib` export of the real `analyze.py` on
`/usr/bin/python3`. Their fixtures make git commits inside those scripts, in scratch repositories
only; no guard refused them.

**Size (user, 2026-11-03).** He accepted this half running over ADR 0017's 800-line cap.

## 1. Shape of the change

```mermaid
flowchart LR
  subgraph browser["Browser: same origin, token read from the page"]
    L["Ledger page, GET /ledger"]
    B["Board, GET /, unchanged"]
  end
  subgraph srv["server.py: the trust boundary"]
    R["POST /ledger and GET /ledger/status"]
    C["POST /command: clear, handoff"]
    Q[("ledger.json: queue, hide list, requests")]
    J["job runner: one job at a time"]
  end
  S["ledger_scan.py, subprocess"]
  A["analyze.py --progress, one subprocess per repo"]
  M["ledger_merge.py"]
  T[("tracker-data.js store")]
  L -->|"poll every 2 s"| R
  L -->|"analyze, remove, retry, delete"| R
  B -->|"reanalyze the run on screen"| R
  B --> C
  R --> Q --> J
  J --> S
  J --> A
  J --> M --> T
  T -->|"GET /tracker-data.js, hidden runs removed"| B
```

| File | New or changed | Owns |
|---|---|---|
| `treko/Ledger.dc.html` | new | the Ledger page, ported from the prototype (§9) |
| `treko/ledger_scan.py` | new | directory scan, worktree families, D11 card choice, narrowing (§4) |
| `treko/ledger_merge.py` | new | one run from several per-repo runs (§7) |
| `treko/ledger_state.py` | new | `ledger.json`, run ids, run rows, the hide list (§5, §8) |
| `treko/ledger_jobs.py` | new | the job runner and its subprocesses (§5, §6) |
| `treko/ledger_routes.py` | new | the `/ledger` and `/ledger/status` handlers: field validation, op dispatch, the status payload (§3) |
| `treko/cards.py` | new | split 1: the analyzer's card-reading layer, moved unchanged (§1.1) |
| `treko/board-commands.js` | new, one manifest row | split 3: the board's node-loadable command slice, moved unchanged, then the Re-analyze change (§1.1, §9.4) |
| `treko/server.py` | changed | routes, validation, idle rule, startup, the launch address (§3, §3.2); split 2 moves its send path out (§1.1) |
| `treko/channel.py` | changed | split 2: receives `confirm_surface`, `send_keys` and `CONFIRM_REFUSAL_REASONS` unchanged (§1.1) |
| `treko/analyze.py` | changed | two optional inputs: the progress report (§6) and `--card` (§4.3; OQ-1, (my call)); and since round 3 one behaviour change, a worktree whose `git status` fails shows "changes unknown" instead of "clean" (§6.3; U6). Nothing else. Split 1 also moves its card layer out, with no change in behaviour (§1.1) |
| `treko/Treko.dc.html` | changed | two icon links, Re-analyze, graph svg size, the Re-analyze pop-up (§9.4); split 3 moves its command slice out (§1.1) |
| `treko/server_harness.py` | changed | an `interpreter` parameter for criterion Z1 (§11) |
| `skills/treko/SKILL.md` | changed | routes, the Ledger, the new files in the store directory, the auto-opened address (§3.2) |
| existing test modules | changed | exactly the edits §12 lists, each module measured ≤ 800 lines (§1.1) |

**(spec call)** The work lands in new modules rather than in `server.py`, which is 793 lines
today (`wc -l treko/server.py`) against the house limit of 800 (`rules/core-conduct.md`). The
server stays the HTTP boundary and imports the others.

**(spec call)** No row is added to `STATIC_MANIFEST` (`server.py:83-101`, 17 rows, pinned by
`test_guards.py:560` `EXPECTED_MANIFEST_ROWS`) for the Ledger page. The Ledger page is served by a
route, like the board today, and every asset it loads is already on the manifest. **Split 3
(§1.1) adds exactly one row, `board-commands.js`, for the board**, so the manifest goes from 17
rows to 18.

### 1.1 Line budgets and the three planned splits

The house limit is 800 lines a file (`rules/core-conduct.md`: "<400 lines, 800 max"). Three files
this card changes start within 17 lines of it, so each gets a budget and, where the card's growth
would cross 800, a split decided now. Sizes are `wc -l` at `6331b5d`:

| File | At `6331b5d` | Budget after this card | How |
|---|---|---|---|
| `treko/analyze.py` | 797 | ≤ 740 | split 1 |
| `treko/cards.py` (new) | — | ≤ 200 | receives split 1 |
| `treko/server.py` | 793 | ≤ 780 | split 2; all Ledger logic in the new modules, server.py only routes and delegates |
| `treko/channel.py` | 95 | ≤ 200 | receives split 2 |
| `treko/Treko.dc.html` | 783 | ≤ 720 | split 3 |
| `treko/board-commands.js` (new) | — | ≤ 250 | receives split 3 |
| `treko/Ledger.dc.html` (new) | — | ≤ 600 | its logic stays in an in-page slice (§9.1) |
| `treko/ledger_*.py` (five new) | — | ≤ 400 each | the house target |
| `treko/server_harness.py` | 339 | ≤ 400 | |
| `treko/test_server.py` | 789 | ≤ 800 | no new tests here: new behaviour is tested in new modules |
| `treko/test_analyze.py` | 599 | unchanged | E1, E2 and E5 go in a new `test_analyze_options.py` |
| `treko/test_guards.py` | 599 | ≤ 800 | split 3's edits, then the re-pin (§12) |
| `treko/test_ui_commands.py` | 468 | ≤ 800 | §12 |
| `treko/test_degraded.py` | 620 | ≤ 800 | §12 |
| `treko/test_autolaunch.py` | 418 | ≤ 800 | §12 |
| `treko/test_store_writer.py` | 78 | ≤ 800 | §12 |
| any other file the card edits | its size | ≤ 800 | Z2's catch-all; §12 names none |
| every new test module | — | ≤ 800, target 400 | |
| `skills/treko/SKILL.md` | 235 | ≤ 400 | |

The six test-module rows were added in round 2 from §12's list, sized with `wc -l treko/test_*.py`
at `d85eabd` (the same bytes as `6331b5d`). **Two files in `treko/` are over 800 lines, and this
card edits neither:** `treko/test_nontext_contrast.py` (1054) and `treko/support.js` (1911), the
only two above 800 in `wc -l treko/*.py treko/*.js treko/*.html | sort -n`. Until round 2 the
card had to edit the first, because serving the Ledger at `/` broke its board load at `:405`. The
board now stays at `/` (U1, §3.2), so no line of it changes, and Z2 can pass. Measured, not
inferred: §12 records a scratch run of that module, with split 3 and the two icon links applied,
passing unchanged.

**`analyze.py`'s 740 still holds with U6 (round 3; spans measured, additions estimated).** Split 1
removes the card layer, `analyze.py:189-291` (103 lines, `sed -n 189,291p treko/analyze.py | wc
-l`), and 15 constant lines (`:36-47` less `MINUS` at `:44`, and `:70-73`), and adds an import
back of a few lines: about 682 of today's 797, before blank-line adjustments. Three additions
share the remaining ~58 lines: `--progress` (four report calls and an argument), `--card` (an
argument and a path list), and U6's failure branch (§6.3: a `try`/`except` around one call, one
`note` branch and one question, about ten lines). Criterion Z2 enforces the figure.

**The three splits (spec call each).** Each is a move with no change in behaviour. Each lands as
its own commit **before** any behavioural change to the file it leaves, so the existing suite
proves the move by itself:

1. **`analyze.py` → `cards.py`.** The card-reading layer moves verbatim: `_card_paths`,
   `_parse_frontmatter`, `_checklist`, `_depends_on`, `_normalize_target` and `Card`
   (`analyze.py:189-291`), with the constants they use from `:36-47` and `:70-73`, and the
   `feature_tasks` import they need. `MINUS` (`:44`) stays, because only `_diffstat` uses it
   (`:170`). `NO_VALUE`, `SPEC_SUFFIX` and `UNPARSEABLE_META` are used on both sides
   (`grep -n -w` each in `analyze.py`): they move to `cards.py` and `analyze.py` imports them
   back, so each is still defined once. `analyze.py` imports back what else it uses. That is one
   unit, "what a card is", and it is also the unit that `--card` and the scan's D11 choice
   depend on: the scan imports `cards`, not the whole analyzer. **Proof:** `test_analyze.py`
   passes unchanged (it reaches the module only through `analyzer.analyze`, measured with
   `grep -o 'analyzer\.[a-z_]*' treko/test_analyze.py | sort -u`), and criterion E2's
   byte-for-byte differential against blob `8b805d1…` passes.
2. **`server.py` → `channel.py`.** `CONFIRM_REFUSAL_REASONS`, `confirm_surface` and `send_keys`
   (`server.py:263-311`) move verbatim into `channel.py`, whose job is already "the cmux control
   channel and its closed reason set" (`server.py:38`) and which already owns `CMUX_BIN` and
   `CMUX_TIMEOUT_SECS`, so the move adds no dependency. This one goes into an existing module,
   not a new one, because a new module would split the cmux channel across two files.
   `server.py` imports the three names back, so `server.CONFIRM_REFUSAL_REASONS` (used by the
   tests) still resolves. **Proof:** `test_server.py`, `test_degraded.py` and
   `test_server_lifetime.py` pass unchanged. If `server.py` would still exceed its 780 budget after
   split 2, the next extraction is the startup checks (`read_timeout` through `probe_listener`,
   `server.py:150-257`) into a new `server_startup.py`. No other split is planned.
3. **`Treko.dc.html` → `board-commands.js`.** The node-loadable slice, from the "slice begins"
   marker to the "slice ends" marker (`Treko.dc.html:402-525`), moves verbatim, markers included,
   into a served file loaded by `<script src="./board-commands.js"></script>` right after
   `support.js`. The slice was written to need no React, no DOM and no `window`
   (`Treko.dc.html:403-409`), so as a classic script its names become the globals the page's
   component already uses. **This needs one new `STATIC_MANIFEST` row**: `board-commands.js`,
   `text/javascript`, an extension already in `EXTENSION_TYPES`. `EXPECTED_MANIFEST_ROWS`
   (`test_guards.py:560`) becomes 18. **Proof:** at the move commit, `test_guards.py`'s fence
   check, pointed at the new file, still matches its pinned sha256 (`bfe17645…`, 6692 bytes,
   `test_guards.py:29`), because the marker-inclusive bytes are unchanged. `test_ui_commands.py`
   passes with only its loader's path changed. The Re-analyze change then re-pins the fence
   deliberately (§12). The slice's own comment says it "cannot live in its own .js file",
   because a new row is a spec change (`Treko.dc.html:405-407`). This card is that spec change.
   The comment sits inside the hashed region, so it stays verbatim in the move commit, keeping
   the proof byte-exact, and is corrected in the Re-analyze commit.
   **Measured in round 2, by simulation.** The move was applied to a scratch export of `HEAD`
   (`git archive HEAD treko hooks/lib`): the slice's 124 lines, markers included, cut into
   `board-commands.js`, the script tag added after `support.js`, the manifest row added. With
   no test edited, 39 tests failed: 15 in `test_guards.py`, 22 in `test_ui_commands.py`, and 2 in
   `test_server.py` that fail identically on an unsplit export, because a scratch export is not a
   git repository and `reanalyze` runs git there. With exactly the edits Z3 lists applied, both
   modules passed, 50 of 50, and the fence pin matched in `board-commands.js` unchanged.
   `test_drawer.py`, `test_drawer_sections.py`, `test_sidebar.py`, `test_theme.py`,
   `test_nontext_contrast.py` and `test_rename.py`, which load or read the board, passed
   unchanged, and still did with the two icon links of §9.4 also applied. **Count, corrected at
   round 3:** those six modules collect 85 tests; the 135 that passed on both the split export and
   the unsplit one is those six plus `test_guards.py` and `test_ui_commands.py`, with Z3's edits
   applied (`pytest --collect-only -q` at `50c0f44`: 85 for the six, 50 for the other two).

**Card 5's line citations move too.** Card 5 cites `analyze.py` at seven distinct places and
`Treko.dc.html` at six (`grep -o -E '(analyze\.py|Treko\.dc\.html):[0-9-]+'
docs/features/treko-branch-graph-traversal.md | sort -u`). Split 1 moves `analyze.py:36-41` into
`cards.py` and shifts every later line. Split 3 shifts every `Treko.dc.html` line after the head
scripts. All are re-checked when card 5 resumes, as the card already records for `analyze.py`.

Criterion Z2 checks every budget above, and Z3 checks the splits' proofs.

## 2. Task 1 gate: the wire-contract amendment (D10)

Today the page may send only `{"id": <one of three names>}`
(`tracking-feature-state.spec.md:404-411`; the allowlist at `:691-703`; "Command arguments of any
kind" out of scope at `:1101`). `server.py:592-598` enforces it: exactly one key, `id`, a string.
**This spec amends the rule "commands take no arguments, in v1 or after".** The amendment is
deliberately narrow:

- `POST /command` keeps the rule unchanged: no arguments, ever. Its allowlist **shrinks** to
  `clear` and `handoff`. **(spec call)** `reanalyze` leaves `/command`. The card moves the board's
  Re-analyze to "re-queue the run on screen" (builder check), which needs a run id, and an
  argument on the route that types into the session is exactly what the old rule forbids. Keeping
  the old `reanalyze` beside the queue would leave a second writer of the store racing the job
  runner, still minting the folder-name ids D12 replaces.
- Arguments are allowed **only** on the new `POST /ledger`, which never reaches the session: no
  `/ledger` operation invokes `cmux` (criterion A5).
- ADR 0034 accepted the store move partly because "the browser cannot name" a path and no verb
  "takes a filesystem path". `/ledger` reverses that for **reads**: the browser names a directory
  the server scans and runs read-only git in. It never names a directory the server writes or
  serves. The store directory still comes only from the process environment, and D8 shows it
  read-only.
- Old criterion 15 (`tracking-feature-state.spec.md:1079-1096`) loses its `500` row for
  `reanalyze` and the board's reload after a successful Re-analyze. `reanalyze` leaves `/command`,
  and after a `200` the board goes to the Ledger instead (§9.4; OQ-5, (user)).
- `STATIC_MANIFEST` gains one row, `board-commands.js` (split 3, §1.1). Old criterion 13's
  expected request sets (`tracking-feature-state.spec.md:933-1064`) describe the board at `/`.
  The board stays at `/` (U1), so they still describe it there, now with `/board-commands.js` in
  both runs. Criterion 13 is an agent-run browser enumeration, not a pytest test
  (`test_server.py:16-20`), so no test module pins those sets.
- ADR 0024's "one audit line per request" gains one exception: an accepted status poll (default
  4 below).

**Task 1 writes an ADR** recording the routes, ops, argument shapes and validation of §3, the
amendments above, and D10's defaults below. Take its number from `origin/main` at write time,
not from a local listing. It is judged the way a spec is: the compliance judge, with the
observability judge's architecting read alongside (`running-the-compliance-judge`). **No Ledger
screen task starts until that verdict passes.** The card's order (Ledger, then card 5, then the
relations card) is unchanged.

D10's defaults, as requirements: the card's three, and a fourth from the observability judge's
round-1 read (O3):

1. **Existing directories only.** `directory` must name an existing directory once expanded
   (§3.4). Nothing is created.
2. **Status polling never resets the idle timer.** Today every accepted **connection** resets it
   (`ControlServer.process_request`, `server.py:650-652`, which runs once per connection; the
   handler speaks HTTP/1.1, `server.py:360`, so further requests on a kept-alive connection do not
   reset it again; read, not run; corrected at round 3 from "every request"), so a polling tab
   that opens connections as it polls would keep the server alive for ever. The reset moves to the point where the request line has been parsed and is
   skipped only when the path is `/ledger/status`, whatever the outcome. A request whose line
   cannot be parsed still resets it, as today.
3. **Git in scanned repos runs with `core.fsmonitor` off.** Measured 2026-11-03 on git 2.50.1: in a
   scratch repo whose own config set `core.fsmonitor` to a script that writes a marker file, a
   plain `git status --porcelain` ran the script, and `git -c core.fsmonitor=false status
   --porcelain` did not. `git help config` documents that `GIT_CONFIG_COUNT` pairs "override
   values in configuration files", and the analyzer's `_git` (`analyze.py:92-103`) passes no
   `env=`, so its git children inherit whatever the scan and analyzer processes are given, with no
   change to `analyze.py`.
   **Every scan and analyzer subprocess gets the variables in this table, unconditionally.** In
   the rest of this spec, "the protective settings" means exactly the table's rows, and nothing
   counts them. The fsmonitor and `core.hooksPath` rows and `GIT_OPTIONAL_LOCKS` date from round
   2; the `log.showSignature` row and `GIT_NO_LAZY_FETCH` were added at round 3 (U4), which raised
   `GIT_CONFIG_COUNT` from `2` to `3`. If task 1's filter outcome adds pairs (below), the count
   rises with them and the table gains their rows.

   | Variable | Value | Stops |
   |---|---|---|
   | `GIT_CONFIG_COUNT` | `3` | |
   | `GIT_CONFIG_KEY_0`, `GIT_CONFIG_VALUE_0` | `core.fsmonitor`, `false` | a repo-named fsmonitor program |
   | `GIT_CONFIG_KEY_1`, `GIT_CONFIG_VALUE_1` | `core.hooksPath`, `/dev/null` | a repo-named hook |
   | `GIT_CONFIG_KEY_2`, `GIT_CONFIG_VALUE_2` | `log.showSignature`, `false` | a repo-named `gpg.program`, which `git log` runs to check a signed commit when the repo sets `log.showSignature=true` (probes 17–20) |
   | `GIT_OPTIONAL_LOCKS` | `0` | `git status`'s optional index write, and the `post-index-change` hook it fires |
   | `GIT_NO_LAZY_FETCH` | `1` | a lazy fetch from a promisor remote, which runs the repo-named `remote.<name>.uploadpack` and downloads objects into the scanned repo (probes 21–26) |

   **The round-2 settings**, which several probes below were run with, are the same table without
   the `log.showSignature` row and `GIT_NO_LAZY_FETCH`, and with `GIT_CONFIG_COUNT=2`.

   Until round 2 the `core.hooksPath` pair and `GIT_OPTIONAL_LOCKS` were conditional on task 1
   confirming a route. They are not any more, because the routes are measured. Probes: `probe_git.sh` (probes 1–11),
   `probe_analyzer_writes.sh` (12–14) and `probe_count_overwrite.sh` (15–16), in the round-2
   scratch folder, on git 2.50.1, in scratch repositories; each group has a baseline that had to
   fire, and did:

   | Probe | Setup | Result |
   |---|---|---|
   | 1 | repo config names an fsmonitor script; plain `git status --porcelain` (baseline) | script ran |
   | 2 | plus the fsmonitor pair | did not run |
   | 3 | plus an inherited `GIT_CONFIG_PARAMETERS` naming the script | **ran** |
   | 4 | as probe 3, with `GIT_CONFIG_PARAMETERS` removed | did not run |
   | 5 | script named only in a `GIT_CONFIG_GLOBAL` file (baseline) | script ran |
   | 6 | that file plus the fsmonitor pair | did not run |
   | 7 | an inherited `GIT_CONFIG_COUNT` family naming the script, no protective pair | **ran** |
   | 8 | repo-set `core.hooksPath` with a `post-index-change` hook, a stat-dirty file, fsmonitor pair only (baseline) | hook ran, index rewritten |
   | 9 | plus `GIT_OPTIONAL_LOCKS=0` | neither |
   | 10 | plus the `core.hooksPath=/dev/null` pair, no `GIT_OPTIONAL_LOCKS` | hook did not run, **index rewritten** |
   | 11 | the round-2 settings | neither |
   | 12 | the real `analyze.py` (`/usr/bin/python3`) over a repo with one worktree, a stat-dirty file in each checkout, the same hook; no protection (baseline) | hook ran; `.git/index` and `.git/worktrees/wt-feat/index` rewritten |
   | 13 | fsmonitor pair only, the plan until round 2 | the same as probe 12 |
   | 14 | the round-2 settings | hook did not run; every file under `.git` identical in content and mtime; exit 0, run complete |
   | 15 | inherited `GIT_CONFIG_COUNT=3` whose `KEY_2` names the script (baseline) | script ran |
   | 16 | that, with `GIT_CONFIG_COUNT`, `KEY_0`/`VALUE_0` and `KEY_1`/`VALUE_1` overwritten by the round-2 settings | did not run |

   **Round 3 (U4).** Both judges' round-3 reads found two more routes open under the round-2
   settings; these probes reproduce them through the real `analyze.py` and measure each fix
   (`probe_r3.sh`, `probe_partial_clone.sh`; "all settings" means the table above):

   | Probe | Setup | Result |
   |---|---|---|
   | 17 | branch `feat` whose tip carries a `gpgsig` header; repo config `log.showSignature=true`, `gpg.program` = a marker script; plain `git log -1 --format=%cr feat` (baseline) | marker ran once |
   | 18 | the real analyzer, the round-2 settings | **marker ran twice**, exit 0 |
   | 19 | the real analyzer, all settings | did not run, exit 0 |
   | 20 | all settings except the `log.showSignature` pair (falsifier) | ran twice |
   | 21 | a `--filter=blob:none` clone (`remote.origin.promisor=true`) with a local `feat` whose blobs are missing; `remote.origin.uploadpack` = a marker script; plain `git diff --shortstat main...feat` (baseline) | marker ran, exit 128 |
   | 22 | the real analyzer, the round-2 settings | **marker ran**, exit 0 |
   | 23 | the real analyzer, all settings | did not run, exit 0 |
   | 24 | all settings except `GIT_NO_LAZY_FETCH` (falsifier) | ran |
   | 25 | a working partial clone (the real upload-pack), all settings | `feat`'s `diff` is `""`; the 2 missing objects are still missing |
   | 26 | the same clone, the round-2 settings | `feat`'s `diff` is `"+3 −1"`; the analyzer downloaded both missing objects into the scanned repo |
   | 27 | `diff.external` = a marker script; plain `git diff main...feat` (baseline) | ran |
   | 28 | the same, `git diff --shortstat main...feat` (the analyzer's form, `analyze.py:163`), round-2 settings | did not run |
   | 29 | `.gitattributes` `diff=x` and `diff.x.textconv` = a marker script; plain `git diff main...feat` (baseline) | ran |
   | 30 | the same, `git diff --shortstat main...feat`, round-2 settings | did not run |
   | 31 | `filter.x.clean` = a marker script, `.gitattributes` `filter=x`, a stat-dirty tracked file; `git status --porcelain`, all settings | **ran**: no setting in the table stops a filter |
   | 32 | the same, with `filter.x.clean`, `.smudge` and `.process` set empty and `.required=false` | did not run |
   | 33 | an ordinary repo with a worktree: the real analyzer, round-2 settings versus all settings | stdout byte-identical (2182 bytes) |

   **What a partial clone shows (U4, measured, probes 25 and 26).** With `GIT_NO_LAZY_FETCH=1` the
   analyzer never fetches. A branch whose changed blobs are not local gets an empty diffstat,
   `""`, which the board already shows for a branch with no diff; every other field of the run is
   unchanged. In the two-run comparison the only other difference was the relative commit age, a
   clock artefact of fixtures made seconds apart. Under the round-2 settings the same run fetched
   over the network and wrote the downloaded objects into the scanned repository's `.git`, which
   §13's "git writes nothing in a scanned repository" did not allow for, so the setting closes a
   write as well as a program route. Version floor: git(1) says `--no-lazy-fetch` "is equivalent
   to setting the `GIT_NO_LAZY_FETCH` environment variable to `1`", and the earliest release notes
   that name it are 2.45.0's ("`git --no-lazy-fetch cmd` allows to run `cmd` while disabling lazy
   fetching of objects from the promisor remote"); 2.44.0's name nothing of the kind (read from
   `Documentation/RelNotes/2.44.0.adoc` and `2.45.0.adoc` in git's repository on 2026-11-03).
   The variable's own first release was not separately established. §15's git is 2.50.1, which
   honours it (probes 23 and 25), so the pin does not predate it; §15's stated floor rises from
   2.31 to 2.45.

   **Which config routes were tried, and which were not (U4).** Tried, by probes in this file or
   by the judges' reads that these probes reproduce: `core.fsmonitor` (1–7), hooks through
   `core.hooksPath` (8–14), `gpg.program` through `log.showSignature` (17–20), a promisor lazy
   fetch through `remote.<name>.uploadpack` (21–26), `diff.external` and `diff.<driver>.textconv`
   (27–30, neither runs on the analyzer's `--shortstat`), and file filters (31–32, which the table
   does not stop; task 1, below). **Not enumerated:** git's other config keys that can name a
   program have not been checked one by one, against the analyzer's git commands or the scan's.
   The routes closed here are therefore a lower bound on what exists, not a list of it, and each
   review round so far has found more (fsmonitor first, hooks at round 2, these two at round 3).

   Probe 3 reproduces the observability judge's round-2 finding: the environment the server was
   launched with can carry config that beats the pairs. A scanned repository cannot set that
   environment, so this is not a remote route, but it made the sentence this paragraph used to
   end with false. Probe 7 shows an inherited `GIT_CONFIG_COUNT` family can name a program too,
   but only where nothing overwrites it: once the builder sets its own count, an inherited pair
   numbered at or above that count is ignored and one below it is overwritten (probes 15 and 16,
   measured with the round-2 count of 2), because git reads only as many pairs as the new count
   says. So
   dropping `GIT_CONFIG_PARAMETERS` is what the protection depends on; dropping the count family
   is hygiene, kept **(my call, round 2)** because it makes the child's `GIT_CONFIG_*` set exactly
   the builder's own.
   **One builder, from an explicit base (spec call, O5; base and drops round 2).** The child
   environment is built by one function in `ledger_jobs.py`, and every scan and analyzer launch
   goes through it, the submit-time scan included. Its **base** is the server's own environment,
   read once in `server.py` `main()`, the one place the server already reads its environment
   (`read_timeout` and `read_port`, `server.py:156` and `:172`, default to `os.environ`), and
   passed to `ledger_jobs` as a plain dict. The builder copies that base, **removes**
   `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT` and every `GIT_CONFIG_KEY_<n>` and
   `GIT_CONFIG_VALUE_<n>`, whatever `<n>`, and then sets the protective settings above. Everything else
   in the base passes through, because git needs `PATH` and `HOME` and the analyzer is the same
   process tree today. The only way to run without the protection is to pass a different builder
   **as a parameter in code**, which is what criterion C8's falsifier does in-process. No request
   field, command-line flag or repository config key can switch it off; neither can the two
   environment routes measured above, which the builder drops, nor a config file, which the pairs
   override (probe 6). **Not measured:** other git environment variables that change what git runs
   or where it looks, such as `GIT_EXEC_PATH` or `GIT_DIR`. They pass through from the server's
   launch environment, which only the person launching the server sets.
   **File filters (user; task-1 obligation revised by U3, 2026-11-03, and made able to fail at
   round 3).** A scanned repository's own config can name a filter program that `git status`
   runs; none of the protective settings stops it (probe 31; the observability judge's round-2
   read first). The user's accepted risk stands, but task 1 must now test switching filter
   drivers off by name **on a real Git LFS repository**, and show the user the result before any
   Ledger screen task starts. The observability judge's round-2 read found that blanking a driver
   by name stopped it in a toy repository; probe 32 measured the same here, with `.clean`,
   `.smudge` and `.process` emptied and `.required=false`. Its round-3 read found that blanking
   `.process` stopped a fake `.process` driver. LFS itself has not been measured anywhere. **The test must be able to fail (round 3):**
   - **Blank every key of each driver:** `filter.<driver>.clean`, `.smudge` and `.process` set to
     empty, and `.required` set to `false`. The observability judge's round-3 read, with a fake
     LFS-shaped driver, found that blanking only the first three made `git status` exit 128 on a
     `required=true` driver with a stat-dirty file, which today's analyzer then reported as clean
     (now "changes unknown", §6.3; U6). Not re-measured here.
   - **Read driver names per worktree, from every config file git reads:** in each worktree of
     the family, `git -C <worktree> config --includes --get-regexp
     '^filter\..*\.(clean|smudge|process|required)$'`, with no `--local` or other file option,
     so that system and global config, `include.path` targets and the worktree's own
     `config.worktree` are all read; the names are the union over the family's worktrees.
     Reading runs no program (the observability judge's round-2 read; the round-3 probe's driver
     values name no real program, so it does not show this). Measured (`probe_r3.sh`, rows R1–R4), with one driver in an
     included file, one in a `GIT_CONFIG_GLOBAL` file and one in a worktree's `config.worktree`:

     | Read | Drivers found |
     |---|---|
     | primary checkout, `--local` | none |
     | primary checkout, no file option | the global and the included one |
     | primary checkout, `--includes`, no file option | the same two |
     | the worktree, `--includes`, no file option | all three |

   - **A fixture where a filter really would run:** the LFS repository has an LFS-tracked file
     that is stat-dirty (mtime changed, content not) in a worktree the job analyzes, because a
     fresh clone is stat-clean and `git status` then runs no clean filter at all (the
     observability judge's round-3 read), and `GIT_OPTIONAL_LOCKS=0` means the analyzer never
     refreshes that state itself. The same worktree also holds one really modified file, so the
     comparison below can see a change that a failing `git status` would hide.
   - **A falsifier:** `filter.lfs.clean` is pointed at a wrapper that writes a marker and then
     runs git-lfs's own clean command. With the drivers not blanked, the job must write the
     marker; with them blanked, it must not.

   "Works" means: with the drivers blanked, the run's cards, branches and worktrees match a run
   without blanking, the really modified file still shows as uncommitted, and no branch shows
   "changes unknown". Three outcomes are defined, and this spec claims none:
   - **LFS-backed scanning still works with the drivers off:** each family's analyzer
     environment also blanks every driver read as above, as further `GIT_CONFIG_KEY_<n>` pairs
     after the table's, with a C9 row that a filter's marker never appears.
   - **It does not:** the drivers stay on, and the ADR records filters as the accepted risk, as
     the user accepted it. §16 keeps the risk.
   - **`git-lfs` cannot be installed** (the user refuses the install at the permission prompt, or
     it fails): the test does not run, file filters stay the accepted risk exactly as in the
     second outcome (D15's fallback), and the ADR records that the test did not run and why
     (U5, round 3).

   **`git-lfs` is a test-only tool, pinned (U5, 2026-11-03).** Measured 2026-11-03: `command -v
   git-lfs` finds nothing on this host. Task 1 installs Homebrew `git-lfs` 3.8.1 (§15), only with
   the user's approval at the permission prompt. It was vetted 2026-11-03 with 0 stop and 0
   caution, but the report also says the vetting was incomplete: all eight of its checks are
   `not_run` for Homebrew (`~/.claude/hooks/state/vetting/homebrew/git-lfs/3.8.1.md`, read
   2026-11-03). Nothing the server, the scan or the analyzer runs depends on it.
   Repositories that use Git LFS are never skipped **(user)**.
4. **An accepted status poll writes no audit line (spec call, O3).** ADR 0024's one line per
   request would let a Ledger tab's 2-second poll add up to 1,800 lines an hour to the only record
   of what the server did. The other requests are still audited exactly as today, including every
   refused poll: "a run of refusals is the only evidence a hostile page ever probed the endpoint"
   (`tracking-feature-state.spec.md:503-504`).

## 3. Wire contract

### 3.1 Routes

| Path | GET | POST | OPTIONS | Any other method |
|---|---|---|---|---|
| `/` | the board page, exactly as today (U1) | 405 | 405 | 405 |
| `/ledger` | the Ledger page | the five ops | 204 | 405 |
| `/ledger/status` | status JSON | 405 | 204 | 405 |
| `/command` | 405 | `clear`, `handoff` | 204 | 405 |
| a `STATIC_MANIFEST` row | the asset, as today | 405 | 405 | 405 |
| anything else | 404 | 404 | 405 | 405 |

Routing reads only the path (`urllib.parse.urlsplit`), as today, so a query string never changes
the route. A `204` carries no `Access-Control-Allow-*` header, as `/command` does today.

### 3.2 The two pages

**The board keeps `/` (user, 2026-11-03, U1).** `GET /` serves `treko/Treko.dc.html` the way it
does today: the same file, the same one meta substitution and the same headers. The file's own
bytes do change, by split 3 and §9.4, so the response is not byte-identical to today's; it is
the file as it stands after this card, served as today (criterion A1; corrected at round 3 from
"the same bytes"). `GET /ledger` serves
`treko/Ledger.dc.html`. **(spec call)** for the `/ledger` path: it is the address the page's own
ops already post to (§3.1), the way a form posts to its own page, so the page and its API share
one name and no second one is invented. A `GET` never reaches an op, and a `POST` still needs the
token and a JSON body (§3.4), so sharing the path widens nothing. Until round 2 this section moved
the board to `/board` and served the Ledger at `/`; that forced edits to five test modules that
load the board at `/`, one of them 1054 lines (§1.1, §12), and the user chose to keep the board's
address instead.

The Ledger is served exactly as `_serve_index` serves the board today (`server.py:452-476`):
`Host` must be `127.0.0.1:<port>` (else `403 host_mismatch`); one substitution injects the
`tracker-token` and `tracker-channel` metas after `<head>`; headers `Cache-Control: no-store`, the
existing `CSP` (`server.py:115-119`) unchanged, and `X-Content-Type-Options: nosniff`.
**(spec call)** Both pages get both metas, through one function that takes the file, so the
board's file is served exactly as today's code serves it (criterion A1). `check_index_injectable`
(`server.py:197-209`) checks both files at startup.

**D1 still holds: launching opens the Ledger, and the icon goes back to it.**

- **Launch address.** Today `--open` calls `webbrowser.open(config["origin"])` (`server.py:768`),
  and `origin` is `"http://%s:%d" % (HOST, port)` with no path (`server.py:677`), so the browser
  lands on the board. That call becomes `webbrowser.open(config["origin"] + "/ledger")`. `origin`
  itself is unchanged, because the `Origin` check compares against it (`server.py:532`).
- **The banner is unchanged.** `server: http://127.0.0.1:<port>/ surface=…`
  (`server.py:776` and `:780`) names the server, and `/` is still the board.
  `test_server_lifetime.py:209` reads it by the prefix `server: http://`, and
  `skills/treko/SKILL.md:66` quotes it; both stay true.
- **The skill.** `skills/treko/SKILL.md:89-90` says "The auto-opened tab is
  `http://127.0.0.1:8422/`". It becomes `http://127.0.0.1:8422/ledger`, the Ledger, and the
  paragraph adds that the board is at `/` and the Treko icon returns to the Ledger (criterion I).
  Found with `grep -rn '127\.0\.0\.1:8422' treko skills/treko`, which prints exactly two lines,
  `SKILL.md:66` and `:90`.
- **The icon** on the board links to `/ledger` (§9.4), and the Ledger's Open and Open the board
  go to `/` (§9.1).

### 3.3 `GET /ledger/status`

Checks, in order: `Host`; `Origin` and `Sec-Fetch-Site`, each only when present (the rule at
`server.py:531-536`); `X-Tracker-Token` by `hmac.compare_digest`. Every failure is the collapsed
`403 forbidden`. Success is `200`, `Content-Type: application/json`, `Cache-Control: no-store`,
`nosniff`:

```json
{
  "ok": true,
  "storeDir": "~/.local/state/treko",
  "queue": [
    {"item": "9f2c4a1b7d3e5f60", "state": "running", "label": "~/dev · repo memsearch",
     "queuedAt": "2026-11-03T09:12:44Z", "run": "r3fa9c2d17b40e815",
     "stage": {"done": 3, "total": 11, "label": "memsearch (1 of 2): reading cards"}},
    {"item": "0a7e1c55d2b94f31", "state": "failed", "label": "~/work", "queuedAt": "…",
     "run": "r…", "error": "analysis_failed",
     "detail": {"stage": "branches", "repo": "memsearch", "exit": 1, "timedOut": false,
                "errno": null}}
  ],
  "runs": [
    {"id": "r3fa9c2d17b40e815", "name": "dev · repo memsearch", "dir": "~/dev",
     "analyzedAt": "2026-11-03T09:13:20Z", "repos": 1, "branches": 6, "worktrees": 2,
     "features": 9, "tasksDone": 31, "tasksTotal": 58, "unreadableCards": 0, "canDelete": true}
  ],
  "runsError": null
}
```

`stage` appears only on the running item, and `stage.total` is `null` until the scan has finished
(§6.2). `error` appears only on a failed item, and `detail` (§5.1, O2) on a failed or an
interrupted one. `runs` is `null` and `runsError` is
`"store_unreadable"` when the store cannot be parsed. **(spec call)** The queue is still returned
then, so a running job stays visible. `storeDir` is the server's store directory, home-collapsed
the way `analyze._home_collapse` does it (`analyze.py:116-119`), for D8.

### 3.4 `POST /ledger`

Checks, in order. Each failure answers once and writes one audit line:

1. `Host` (`403 host_mismatch`), then `Origin` and `Sec-Fetch-Site` (`403 origin_mismatch`),
   then the token (`403 bad_token`). Same code as `_handle_command` (`server.py:524-556`).
2. `Content-Type` is `application/json` (`415`).
3. The body: `Transfer-Encoding` refused, `Content-Length` required, at most
   `LEDGER_MAX_BODY_BYTES = 4096` bytes read (`413`), the same mechanics as `_read_body`
   (`server.py:558-599`). **(spec call)** 4096, not `/command`'s 1024: a macOS path alone can be
   1024 bytes, and JSON quoting can double it. `/command` keeps 1024.
4. The body is a JSON object with a string `op` (`400 malformed`).
5. `op` is one of the five below (`403 forbidden`, reason `unknown_op`). As with `/command`, an
   unknown op is indistinguishable from a bad token.
6. The key set is exactly the op's own keys, every value a string (`400 malformed`). Unknown keys
   are refused, never ignored.
7. The field rules below (`422`).
8. The op itself.

| `op` | Keys: required, optional | Effect |
|---|---|---|
| `analyze` | `directory`; `repo`, `branch`, `worktree` | runs the scan (§4) at once; if it finds work, queues the request (§5) |
| `reanalyze` | `run` | queues the request recorded for that run (§8.2; a run from before the Ledger: OQ-7, (my call)) |
| `remove` | `item` | removes a waiting, failed or interrupted item |
| `retry` | `item` | puts a failed or interrupted item back to waiting, unless another item for the same run is waiting or running (§3.5 `already_queued`, round 2) |
| `delete` | `run` | adds the run to the hide list (D12) |

| Field | Rule, checked before anything touches the filesystem or git |
|---|---|
| `directory` | at most 1024 UTF-8 bytes. No U+0000–U+001F or U+007F (`422 invalid_input`). After `os.path.expanduser` (a leading `~` only, the `store_location` rule) it is absolute (`422 relative_path`). Its `os.path.realpath` is an existing directory (`422 no_such_directory`). That real path is the canonical directory |
| `repo` | `""` means absent. At most 255 bytes, no control characters, no `/` (`422 invalid_input`). Only ever compared with folder names |
| `branch` | `""` means absent. At most 255 bytes, no control characters (`422 invalid_input`). Only ever compared with card `branch:` values |
| `worktree` | `""` means absent. At most 1024 bytes, no control characters (`422 invalid_input`). Only ever compared with worktree paths and folder names |
| `item` | matches `^[0-9a-f]{16}$` (`400 malformed`: the page only ever sends ids the server gave it) |
| `run` | 1–255 bytes, no control characters (`400 malformed`), and equal to the `id` of a run in the store (`404 no_such_run`) |

No value reaches a shell. `repo`, `branch`, `worktree`, `item` and `run` never reach git at all.
The canonical directory reaches git only as `git -C <absolute path>`, which cannot begin with
`-`. The scan subprocess receives the request as one JSON object on stdin, never as argv
**(spec call)**, so no value can be read as a flag.

Success bodies: `analyze` and `reanalyze` return
`{"ok": true, "op": "<op>", "item": "<id>", "started": <bool>}`, where `started` is true when no
other item was running or waiting. `remove`, `retry` and `delete` return
`{"ok": true, "op": "<op>"}`.

**`reanalyze` re-runs the submit-time path (spec call: codes and wording).** It takes the request
recorded for the run (§8.2) and puts it through exactly what `analyze` does at submit: the field
rules above, so the recorded directory must still be an existing directory, then the scan (§4).
A run whose directory has been deleted gets `422 no_such_directory`. A run narrowed to a worktree
that has since been removed, which is routine here because worktrees go after a merge, gets
`422 no_such_worktree` (§4.2). Either way nothing is queued, and the board shows the pop-up of
§9.4. The other scan outcomes (`no_repository`, `no_matching_repository`, `nothing_matched`)
refuse the same way.

Every op that queues an item also records `requests[run] = request` in the same ledger write
(§5.6). Because the id is a hash of the request (§8.1), that mapping is already true before the
run exists.

### 3.5 Every failure, with its audit reason

The body is always `{"ok": false, "error": "<error>"}` and echoes nothing from the request.
**Every row has a reason and every reason has a row**; criterion A2 checks both directions.

| Status | `error` | Cause | Audit `reason` |
|---|---|---|---|
| 400 | `malformed` | §3.4 steps 3, 4, 6; a bad `item` or `run` shape | `malformed` |
| 403 | `forbidden` | host, origin, token, unknown op | `host_mismatch`, `origin_mismatch`, `bad_token`, `unknown_op` |
| 404 | `no_such_item` | `remove`/`retry`: no item with that id | `no_such_item` |
| 404 | `no_such_run` | `delete`/`reanalyze`: no run with that id | `no_such_run` |
| 405 | `method_not_allowed` | §3.1 | `method_not_allowed` |
| 409 | `item_running` | `remove` of the running item | `item_running` |
| 409 | `not_retryable` | `retry` of a waiting or running item | `not_retryable` |
| 409 | `already_queued` | `analyze`/`reanalyze`: an item with the same run id is already **waiting or running**; `retry`: **another** item with the retried item's run id is waiting or running. Checked under the ledger lock (§5.6). **(spec call)**, revised at round 1 from "waiting" only, so that two identical submits racing always leave exactly one item, and at round 2 to cover `retry` (F8), so that no op can make two live items for one run | `already_queued` |
| 409 | `queue_full` | the queue already holds `MAX_QUEUE_ITEMS = 20` items, any state **(spec call)** | `queue_full` |
| 409 | `last_run` | `delete` of the only visible run (§8.4) | `last_run` |
| 413 | `too_large` | body over 4096 bytes | `too_large` |
| 415 | `unsupported_media_type` | not `application/json` | `unsupported_media_type` |
| 422 | `invalid_input` | a field length or character rule | `invalid_input` |
| 422 | `relative_path` | `directory` not absolute after expansion | `relative_path` |
| 422 | `no_such_directory` | not an existing directory; for `reanalyze`, the run's recorded directory no longer exists | `no_such_directory` |
| 422 | `no_repository` | the scan found no repository (D2) | `no_repository` |
| 422 | `no_matching_repository` | repositories found, none with that `repo` folder name | `no_matching_repository` |
| 422 | `no_such_worktree` | `worktree` names no worktree of any repository the scan found; for `reanalyze`, the run's narrowing worktree has been removed (§4.2). A pop-up, nothing queued | `no_such_worktree` |
| 422 | `nothing_matched` | no card matches `branch`/`worktree`: a pop-up at submit, nothing queued (OQ-4, (user)) | `nothing_matched` |
| 500 | `scan_timeout` | the scan passed `TREKO_SCAN_SECS` | `scan_timeout` |
| 500 | `scan_failed` | the scan exited non-zero or printed something that is not its contract | `scan_failed` |
| 500 | `launch_failed` | `analyze`/`reanalyze`: the submit-time scan subprocess could not be started at all (an `OSError` from the spawn, today's branch at `server.py:330-331`). Nothing is queued (U2) | `launch_failed` |
| 500 | `ledger_write_failed` | the request's own write of `ledger.json` failed, so nothing changed (§5.6) | `ledger_write_failed` |
| 500 | `store_unreadable` | `delete`/`reanalyze`: the store does not parse | `store_unreadable` |

`GET /` and `GET /ledger` keep today's `500 asset_unreadable` for an unreadable page. `/command` is
unchanged apart from its allowlist: `{"id": "reanalyze"}` is now `403`, reason `unknown_id`.

**Codes only a failed item carries (U2, round 2).** These never answer a request. They are the
`error` of a failed queue item (§5.4), written to `ledger.json` and shown from it (§9.2). A2 does
not drive them over HTTP; criteria D7 and D12–D14 do, through the job runner.

| `error` | Cause | `detail.stage` |
|---|---|---|
| `analysis_failed` | every family's analyzer failed (OQ-2) | the first failure's stage |
| `store_write_failed` | `store.emit_run` raised | `write` |
| `merge_failed` | `ledger_merge.merge` raised: the per-repo results could not be combined into one run | `merge` |
| `launch_failed` | a job's scan or analyzer subprocess could not be started at all (an `OSError` from the spawn). Also a request answer, above | `scan`, or `worktrees` for an analyzer (the stage it would have run first) |
| `internal_error` | any other exception on the job thread, caught by the catch-all of §5.4 | the stage it had reached, or `null` |

`ledger_write_failed` and the scan outcomes (`no_such_directory` through `scan_failed` above) are
both: a request answer at submit, and an item's `error` at job time.

### 3.6 Audit lines and diagnostics

The audit format (`server.py:134-147`) is unchanged: one line per request, except an accepted
status poll, which writes none (§2, default 4; O3). A refused poll is audited.
**(spec call)** `id=` carries the op for `/ledger`, `status` for the poll, and `-` for the pages
and for an op that failed before it was read. **Field values are never logged.** The directory is
request content, and the old spec bans logging request bodies "in whole or in part"
(`tracking-feature-state.spec.md:547-551`).
Job events go to stderr as `server: job <item> <event>` and name item and run ids only. An
analyzer's or scan's own last stderr line may follow, as `_reanalyze_failed` does today
(`server.py:348-351`). **(spec call, round 2)** A failed job's line names its code and
`detail.stage`; for `merge_failed` and `internal_error` it also names the exception's **class**
(`ValueError`, `KeyError`), never its message, which can carry a path or a field value. For
`launch_failed` it names the errno's symbolic name.

The volume is why. At the 2-second poll, auditing every accepted poll would write up to 1,800
lines an hour while a Ledger tab is open. Until round 1 this spec accepted that as the cost of
keeping "one line per request", on the ground that polling alone cannot keep the server alive
(§2, default 2). The observability judge's O3 replaced that with the exception above, because
those lines would bury the state-changing ones in the only record.

### 3.7 `GET /tracker-data.js` and the hide list (D12)

The containment check stays first, exactly as today (`server.py:486-501`). Then:

- **Empty hide list:** the file's bytes are served unchanged, so today's path is byte-identical.
- **Otherwise:** the server parses the store (`store.read_store`), removes runs whose `id` is
  hidden, and serves `store.dumps` of the result. A parse failure is the existing
  `500 asset_unreadable`.

Both pages therefore see only visible runs, and the board needs no hide logic. Over `file://`
there is no server, the board falls back to the bundled sample (`SKILL.md`, "Opening the vendored
file over file:// no longer shows your survey"), and nothing hidden exists to leak.

## 4. Directory scan (D2, D3 as confirmed, D11)

`ledger_scan.py` runs as a subprocess, launched with the server's own `sys.executable` like the
analyzer (§5.4), with the request on stdin, and prints one JSON object on stdout. It runs under
`TREKO_SCAN_SECS = (30, 5)` (default, floor), with the same no-"never" rule
as the other timeouts (`read_timeout`, `server.py:153-168`), in its own process group, which is
killed when the bound passes. Each git call inside it has `GIT_TIMEOUT_SECS = 5` (`server.py:61`).
**(spec call)** Out of process for the reason `run_reanalyze` gives (`server.py:317-321`): a
directory listing that blocks cannot be interrupted inside a thread. The same scan runs twice:
at submit, to decide whether anything is queued at all (D2: nothing found means nothing queued),
and again as the job's first stage, because the tree may have changed in between.

**The submit-time scan is killed at shutdown too (spec call, round 2, F7).** It runs on a
request thread, not the job thread, so until round 2 nothing stopped it when the server exited,
and a hung scan in its own process group could outlive the server. Every scan and analyzer
subprocess, from either thread, is now added to one **child registry** in `ledger_jobs.py` when
it starts and removed when it is reaped. The registry is a set guarded by its own lock, never the
ledger lock, so a shutdown kill never waits on a slow ledger write. Shutdown kills every
registered process group (§5.3). A scan that cannot be started at all answers
`500 launch_failed` (§3.5) and is never registered.

**The registry closes at shutdown, and it is the only way to launch (spec call, round 3).** The
registry holds a `closed` flag. Every scan and analyzer launch in the ledger modules goes through
one registry method that, under the registry's lock, checks `closed`, starts the process with
`env=` set to the builder's output (§2 default 3) and registers it, all before the lock is
released. Shutdown, under the same lock, sets `closed` first and then kills every registered
group. So no process can start after the sweep, and none can start without the protective
settings: a launch the closed registry refuses starts nothing, and the code that asked for it
treats the refusal as the server stopping (§5.3), never as a failure. Until round 3 a family
could start after the sweep, because §5.4 step 3 reads a killed analyzer as a failed family and
carries on (the observability judge's round-3 read, reasoned there, not measured).

### 4.1 Finding repositories

- **Down (D2).** List the canonical directory's subdirectories, breadth-first, to depth 5. The
  directory itself is depth 0. A depth-5 folder is checked but never listed. A folder holding a
  `.git` entry (directory or file) is a candidate and is not descended into. That includes the
  directory itself: when it holds a `.git` entry, nothing below it is listed. First launch relies
  on this (OQ-6): scanning the launch repo must not pull in repositories nested inside it.
  Skipped: `node_modules`;
  hidden folders, meaning a name beginning with `.` **or** the OS hidden flag
  (`st_flags & stat.UF_HIDDEN`); and symlinked folders, which are never followed. **(spec call)**
  for the hidden flag. Measured 2026-11-03: `~/Library` carries it and `~/Documents` and
  `~/Desktop` do not, so typing `~` skips `~/Library`, which Finder also hides. A folder that cannot
  be listed is skipped and counted.
  **(spec call, O1)** Two more counts: every depth-5 folder that is not a repository (cut off at
  the depth limit, so whatever it holds was never looked at), and every symlinked folder skipped.
  All three counts feed the "Were repositories missed?" question (§7.2), so a repository at depth
  6 is never silently absent. Hidden folders and `node_modules` are not counted: skipping them is
  D2's decision, and counting them would raise the question on every scan of `~`.
- **Up (D2, accepted reading).** `git -C <dir> rev-parse --show-toplevel`. The result counts only
  if it is the directory itself or one of its 5 nearest ancestors.
- **Confirm.** Each candidate runs `git rev-parse --path-format=absolute --git-common-dir
  --show-toplevel`. A candidate git refuses (a stale worktree pointer, a repo another user owns)
  is skipped and named in a scan-level question (§7.2).
- **Families.** Candidates are grouped by their resolved common directory, so a repo reached
  directly and again through a worktree counts once (anti-goal 4). Each family's worktrees come
  from `git worktree list --porcelain`, not from the scan, so a worktree under a hidden folder is
  still pulled in (D2: "look at the related repos and other worktree"). Entries marked `prunable`
  or whose path no longer exists are left out. The **primary checkout** is the first listed
  worktree. **(spec call)** If that entry is `bare`, the first non-bare worktree takes its place.
- **Order.** Families are sorted by primary checkout path, so the same tree always yields the same
  run.

### 4.2 Narrowing (D3 as confirmed)

- **Repo** keeps the families whose primary checkout's folder name equals `repo` exactly. If
  families were found but none matches: `no_matching_repository`.
- **Branch** keeps, in each family, the cards whose chosen copy (§4.3) has `branch:` equal to
  `branch` exactly. The value is normalized as `Card.branch` does it (`analyze.py:273-274`).
- **Worktree** names a worktree of a family: either its resolved path equals the expanded,
  resolved `worktree`, or its folder name equals `worktree` **(spec call: both forms; the
  prototype's placeholder is a path)**. It keeps the cards whose chosen copy names that worktree's
  checked-out branch. Branch and Worktree together must both hold. **(spec call, round 1)** If no
  family the scan found has a worktree matching `worktree` either way: `no_such_worktree`, a
  pop-up, with nothing queued. That is distinct from `nothing_matched`, where the worktree exists
  but no card names its branch. It is also what a `reanalyze` gets when the run's narrowing
  worktree has been removed since (§3.4).
- **Closure.** Every card a kept card names in `## Depends on`, transitively, within its family, is
  kept too ("so the merge order stays true"). Edges come from `cards.Card(...).depends_on` (the
  analyzer's own parser, in `cards.py` after split 1), imported rather than rewritten.
- Under Branch or Worktree, a family with no kept card is dropped from the run **(spec call)**. If
  every family is dropped: `nothing_matched`. At submit that is a pop-up and nothing is queued
  (OQ-4, (user)).
- `branches[]` and `questions[]` of every family that remains are kept whole. Narrowing removes
  cards and nothing else **(spec call: D3 speaks of cards only)**.

### 4.3 Which copy of a card counts (D11)

Each card name appears once. Its copies are `docs/features/<name>.md`, excluding `*.spec.md`, in
every worktree of the family. A copy is **on its branch** when its own `branch:` names the branch
checked out in the worktree it sits in. The chosen copy is:

1. the copy that is on its branch. If several are, the first in `git worktree list` order, and a
   question names the disagreement;
2. otherwise the primary checkout's copy;
3. otherwise, when the primary has none, the first listed worktree's copy.

**(spec call, also raised in OQ-1; its 2026-11-03 answer did not cover this reading)** "When a card
names a `branch:`" is read per copy, because copies can disagree about `branch:`. A planning card
on `main` may still say `branch: none` while its worktree copy names the branch, and D11's purpose
is the live copy. Copies are parsed with `cards.Card` (`analyze.Card` before split 1); a copy
that cannot be read is never on its branch.

**Mechanism: OQ-1, answered (my call).** D11 needs the analyzer to read the chosen copies, which
sit in several folders, while `_card_paths` reads exactly one (`analyze.py:192-198`). The answer,
first recommended here, is one more optional input to `analyze.py`: `--card PATH`, repeatable.
When given, the analyzer reads exactly those files, ordered by file name and then path, instead of
`<root>/docs/features/*.md`. When absent, behaviour is byte-identical to today: the same
"unchanged without the options" test as the progress report covers it (criterion E2), and
criterion E5 checks the option itself.
Narrowing then needs no post-filtering: the analyzer is handed only the kept cards and derives
waves, graph and constraints from them itself.

### 4.4 The scan's output

```json
{"outcome": "ok",
 "families": [{"root": "/Users/x/dev/memsearch", "label": "memsearch",
               "cards": ["/Users/x/wt/digest-reindex/docs/features/digest-reindex.md", "…"],
               "questions": [{"q": "…", "ctx": "…"}]}],
 "questions": [{"q": "…", "ctx": "…"}],
 "missed": {"unreadable": 0, "depthLimit": 3, "symlinks": 1}}
```

`outcome` is `ok`, `no_such_directory`, `no_repository`, `no_matching_repository`,
`no_such_worktree` or `nothing_matched`. Each of these is a result, printed with exit 0.
`no_such_directory` happens only at job time, when the directory went away while the item waited;
at submit, §3.4's field rules catch it first. A crash is a non-zero exit and becomes
`scan_failed`. `missed` holds §4.1's three counts.

### 4.5 Nothing found (D2)

When `outcome` is not `ok` at submit time, nothing is queued and the page shows a **pop-up**, not
inline text. The `no_repository` wording is the card's: "No git repository found in or around that
directory." The other wordings are in §9.2.

## 5. The queue and the job runner (D4, D5, builder check)

### 5.1 `ledger.json`

Lives at `<store dir>/ledger.json`, beside the runs (D5). It is written atomically (temp file in
the same directory, `fsync`, `os.replace`, the `store.write_store` pattern at `store.py:160-186`)
at mode `0o600` **(spec call)**, on every change of queue, hide list or requests. Stage progress is
never written; it lives in memory. §5.6 says who writes the file, under which lock, and what each
write does when it fails.

```json
{"version": 1,
 "queue": [{"item": "9f2c4a1b7d3e5f60", "state": "waiting", "queuedAt": "2026-11-03T09:12:44Z",
            "request": {"directory": "/Users/x/dev", "repo": "memsearch", "branch": "",
                        "worktree": ""},
            "run": "r3fa9c2d17b40e815", "error": null, "detail": null}],
 "hidden": ["r0c4d…"],
 "requests": {"r3fa9c2d17b40e815": {"directory": "/Users/x/dev", "repo": "memsearch",
                                    "branch": "", "worktree": ""}}}
```

`state` is one of `waiting`, `running`, `interrupted`, `failed`. `error` is a §5.4 code when
`failed`, and `null` otherwise. Since round 2 that set includes `launch_failed` (the scan or an
analyzer could not be started at all), `merge_failed` (the per-repo results could not be
combined) and `internal_error` (the catch-all), each recording in `detail.stage` the stage named
in §3.5's second table (U2). `request.directory` is the canonical directory. `run` is the D12 id
(§8.1). `queuedAt` uses `store.TIMESTAMP_FORMAT` (`store.py:41`).

**`detail` (spec call, O2)** is `null` unless the item is failed or interrupted. Then it holds:
`stage`, one of `start`, `scan`, `worktrees`, `branches`, `cards`, `order`, `merge`, `write`, or
`null` when unknown; `repo`, the label of the repository being analyzed, or `null`; `exit`, the
subprocess's exit status, or `null`; `timedOut`, a boolean; and `errno`, a symbolic name such as
`ENOSPC`, or `null`. **Where the request lives (rewritten at round 2, F4).** The request is
stored **twice, by design**: as `queue[].request`, the item's own copy, and as `requests[run]`,
written in the same ledger write when the item is queued (§3.4), which outlives the item so the
board's Re-analyze can find it after the job has gone. Until round 2 this paragraph said the
request was "stored once", which stopped being true when round 1 moved the `requests` write to
queue time. `detail` copies no request field. Its one string that can coincide with one is
`detail.repo`: that is the scan's label for the family that failed (§7.1), which equals the
Repo box's value whenever the job was narrowed by it, because Repo matches a folder name exactly
(§4.2). `detail` never holds text a subprocess printed, since that goes to stderr and into the
run's questions (§7.2). The Ledger builds each message from it (§9.2), because the server's log
is gone after a restart and this is not.

**On load,** an absent file is an empty ledger. A file that does not parse, carries a `version`
other than 1, or breaks any rule above **aborts startup** with exit 2, naming the file
**(spec call)**. This is the legacy-store posture the skill documents: a silent empty start would
drop waiting work and un-hide every deleted run.

**One server per store directory (spec call).** After the bind succeeds, so today's busy-port
messages are unchanged, the server takes `fcntl.flock(LOCK_EX | LOCK_NB)` on
`<store dir>/.treko-server.lock` (mode `0o600`, never deleted) and holds it for its lifetime. If
the lock is held, it aborts with exit 2: "another Treko server is using <store dir>". Without this,
two servers on different `TREKO_PORT`s would both start the same waiting item at launch, and the
store's read-modify-write could drop a run.

### 5.2 Item lifecycle

```mermaid
stateDiagram-v2
  [*] --> waiting: Analyze accepted
  waiting --> running: oldest waiting item, nothing running
  waiting --> failed: start could not be recorded (ledger_write_failed, §5.6)
  waiting --> [*]: remove
  running --> [*]: run written
  running --> failed: job failure
  running --> interrupted: server stopped mid-job
  failed --> waiting: Retry
  interrupted --> waiting: Retry
  failed --> [*]: remove
  interrupted --> [*]: remove
```

- **One job at a time, oldest first (D4).** "Oldest" means queue order, which is enqueue order. A
  retried item keeps its place, so it runs next.
- **Analyze starts now or queues (D4).** There is no per-item Analyze button. The runner starts
  the oldest waiting item whenever nothing is running.
- **A running item cannot be removed (D4)**: `409 item_running`.
- **Failed items stay listed** with their reason, Retry and remove, like interrupted ones
  **(spec call)**. A failure seen only by a page that was open when it happened would be invisible
  to the user D5 describes, who leaves and comes back.
- **No item stays `running` for ever (U2, round 2).** Every job leaves `running` by one of the
  diagram's three exits: the run written, `failed` (including the catch-all's `internal_error`,
  §5.4), or `interrupted` at shutdown. So `busy` (§5.5) always clears and the idle exit can
  follow.
- **One live item per run (round 2, F8).** `retry` is refused with `409 already_queued` when
  another item with the same run id is waiting or running, checked under the ledger lock like
  `analyze` (§5.6). Without it, a failed item retried while a fresh submit of the same request
  waited would run the same analysis twice.

### 5.3 Restart and shutdown

- **At startup,** after the lock: every `running` item becomes `interrupted`, the file is
  persisted, and the runner starts. Waiting items then start on their own (builder check, "After a
  server restart"). Interrupted items wait for Retry and are never restarted silently (D5). After
  a hard kill the stage and repo are unknown, so `detail.stage` and `detail.repo` are `null`. If
  this write fails, startup aborts (§5.6, write 4).
- **First launch with an empty store (OQ-6, (user)).** Today `--open` runs the analyzer on the
  launch repo before it opens the browser (`server.py:756-763`). Instead, once the runner has
  started, the server submits `{"directory": <launch repo root>}` exactly as an `analyze` op
  would: the same validation, the same submit-time scan, the same D12 id. Then it opens the
  browser at `/ledger` (§3.2; U1), where the Ledger shows the job. The condition is unchanged: the store holds no
  runs. **(spec call)** Nothing is submitted when an item for that request is already waiting or
  running, for example one carried over from the previous launch. A refusal, such as `--repo`
  naming a folder that is not a repository, is written to stderr, nothing is queued, and the
  server still serves. `run_reanalyze` (`server.py:314-345`) is then left with no caller and goes,
  and the `--repo` help text (`server.py:694-696`) stops naming `reanalyze`.
- **On shutdown** (idle, parent death, `Ctrl-C`): the server **closes** the child registry first
  (§4; round 3), so nothing can start after this point: no new family of the running job and no
  new job. It then kills the process group of every subprocess in the registry: the job's
  current one, and since round 2 any submit-time scan still running on a request thread (F7).
  The runner marks the item `interrupted` with the stage and repo it had reached in `detail`, and
  persists. An analyzer that ends because shutdown killed it is never read as a failed family
  (§5.4 step 3), so a one-family job stopped mid-run is `interrupted`, not `analysis_failed`. A request whose scan was killed this
  way gets no answer; the server is exiting. If that write fails, stderr says so and the server exits anyway (§5.6, write 5).
  This must fit inside the existing
  bound, exit within `TREKO_POLL_SECS` + 1 s of parent death (old criterion 14). A hard kill skips
  this, and the next startup's recovery reaches the same state.

### 5.4 One job

1. Mark the item `running` and persist. Stage label: "scanning <dir>". If that write fails, the
   job does not start (§5.6, write 1).
2. **Scan** (§4). An outcome other than `ok` fails the job with that code. A scan subprocess that
   cannot be started at all fails the job with `launch_failed`, `detail.stage = "scan"` and the
   errno (U2).
3. **Per family, in order:** `analyze.py <primary checkout> --progress`, plus one `--card` per
   chosen copy (§4.3; OQ-1, (my call)), run with `sys.executable` like `run_reanalyze`
   (`server.py:322-327`). It runs in its own process group, under `ANALYZE_SECS`
   (`server.py:56`) **per repo**, with D10's environment. stdout is drained by a second thread so
   a large run cannot fill the pipe and deadlock the stderr reader **(spec call)**. stdout must
   parse as a JSON object holding the run keys of ADR 0023's schema. A family that times out,
   exits non-zero or prints a bad run has **failed**. The job carries on, and the run gets a
   visible question naming that repo and why (§7.2). Only if every family fails does the job fail
   `analysis_failed` (OQ-2, (user)).
   **Shutdown stops the loop (round 3).** Before each family the job checks the registry; when it
   is closed (§4, §5.3), or when the analyzer ended because shutdown killed it, the job starts no
   further family and the item becomes `interrupted`, never a failed family.
   **Progress reports pass through one handler (round 3).** The job thread reads the analyzer's
   `treko-progress <stage>` lines (§6.1) and hands each to a report handler, a function passed in
   code that by default records the stage in memory (§6.2). An exception raised while handling a
   report records, as `detail.stage`, the stage that report names (the stage that just finished,
   §6.1). Criterion D14 replaces the handler to raise.
   **An analyzer that cannot be started at all** (an `OSError` from the spawn, the branch that
   today's `run_reanalyze` handles at `server.py:330-331`) **fails the whole job at once** with
   `launch_failed`, `detail.stage = "worktrees"`, `detail.repo` the family's label and `detail.errno`
   its symbolic name (U2). **(spec call)** It is not a family failure under OQ-2: it says nothing
   about the repository, since the cause is the interpreter or the process table, and every later
   family's launch would meet the same error and end as a misleading `analysis_failed`.
4. **Merge** (§7). **Any exception `ledger_merge.merge` raises** fails the job with
   `merge_failed`, `detail.stage = "merge"` (U2). Nothing is written to the store. The merge is a
   pure function over analyzer output that already passed step 3's key check, so a raise here is
   a merge bug or an analyzer run whose values have a shape the merge did not expect; either way
   the per-repo results could not be combined, and the code says exactly that.
5. **Write**: `store.emit_run(store_path, run)` (`store.py:189-211`), which upserts by id, keeps
   position and stamps `analyzedAt`. Failure: `store_write_failed`.
6. **Success:** remove the item, take `run` off the hide list (D12), persist (§5.6, write 2), and
   record the end time for the idle rule (§5.5). Until round 1 this step also set
   `requests[run] = request`. That is now recorded when the item is queued (§3.4), so a failed
   write here cannot leave a run whose request is unknown.

**Every end records `last_job_end` (round 3).** Until round 3 only step 6 recorded the end time,
so a long job that failed could let the server exit at once. Now every way an item leaves
`running` sets `last_job_end` (§5.5) in the same step that changes its state: success (step 6),
every failure code (steps 1 to 5), the catch-all below, and interruption at shutdown (§5.3).

**The catch-all (U2, round 2).** Steps 1 to 6 run inside one handler on the job thread that
catches **any** other exception (`except Exception`). It:

1. **kills the process group of every subprocess this job has in the child registry** and waits
   for each to be reaped, so no analyzer or scan keeps running beside the next job (round 3; the
   compliance judge's round-3 note);
2. marks the item `failed` with `internal_error` and `detail.stage` set to the stage the job had
   reached (`null` if it had not reached one), the rest of `detail` as far as known;
3. persists that under the §5.6 lock, as runner-side write 3, whose failure rule applies
   unchanged: memory records the failure even if the file cannot;
4. clears the running item and records `last_job_end`, so `busy` (§5.5) is false unless another
   item is waiting, and the idle exit can proceed once the idle period passes;
5. writes `server: job <item> internal_error <ExceptionClass> at <stage>` to stderr (§3.6);
6. lets the runner go on to the next waiting item.

An exception in the runner loop outside any item (choosing the next item, say) has no item to
mark. It is written to stderr the same way, and the runner **pauses** exactly as after write 1
(§5.6), so a loop that keeps raising cannot spin and a paused runner does not count as busy.
Only `Exception` is caught: `KeyboardInterrupt` and `SystemExit` belong to the main thread's
shutdown (§5.3).

Job failure codes, as `error` on a failed item: `no_such_directory`, `no_repository`,
`no_matching_repository`, `no_such_worktree`, `nothing_matched`, `scan_timeout`, `scan_failed`,
`launch_failed`, `analysis_failed`, `merge_failed`, `store_write_failed`, `internal_error`, and
`ledger_write_failed` when the start could not be recorded (§5.6, write 1). The three added at
round 2 are `launch_failed`, `merge_failed` and `internal_error` (U2), listed with their stages in
§3.5. A failed job writes nothing to the store, so the previous run stays intact, and its item
carries `detail` (§5.1). The one exception is an `internal_error` raised after step 5's write
succeeded: the run is then in the store, and Retry replaces it in place (D12).

### 5.5 The idle exit

The watchdog's idle test (`server.py:668`) becomes a pure function, so it can be tested with an
injected clock:

```
idle  ⇔  not busy  and  now − max(last_request, last_job_end) ≥ idle_secs
busy  ⇔  an item is running, or an item is waiting and the runner is not paused (§5.6)
```

A paused runner's waiting items do not count, or a broken disk would keep the server alive for
ever **(spec call, round 1)**. An item cannot hold `busy` true for ever either: every job leaves
`running`, the catch-all included (§5.2, §5.4; U2). And every job's end, not only a success's,
moves `last_job_end` (§5.4, round 3), so the rule below reads the same whichever way a job ended:
the idle exit comes no sooner than `idle_secs` after the last job's end.

A running job counts as activity (D5's ⚠️), and so does its end **(spec call)**: without that, a
job that outlasts the idle period ends with the server exiting at once, under the user who just
watched it finish. `last_request` follows §2 default 2, so polls never move it. The parent-death
check is unchanged and still ends the server mid-job; the job becomes `interrupted` (§5.3).

### 5.6 `ledger.json`: one lock, and what each write does when it fails

**One lock (spec call, from the observability judge's round-1 read).** `ledger_state.py` holds
the ledger in memory and guards it with one `threading.Lock`. Every read-modify-write runs under
that lock, from a request thread or from the job thread alike: read the state, decide, change it,
write the file. Status reads take the same lock to copy a consistent snapshot. The submit-time
scan is slow, so it runs **before** the lock is taken. The checks that depend on the queue
(`already_queued`, `queue_full`) and the enqueue itself run under the lock, after the scan.
`retry`'s `already_queued` check (another live item for the same run, F8) runs under the same lock
as its state change. The runner takes the same lock to pick the next item and mark it running.

So two identical requests that race both scan, then queue one after the other under the lock. The
first is queued; the second finds it waiting or running and gets `409 already_queued`. Across
processes, the `flock` of §5.1 keeps a second server away from the file.

**Every write** goes to a temp file in the store directory, is `fsync`ed, and is moved into place
with `os.replace` (`store.write_store`'s pattern). A failed write therefore leaves the previous
file whole and removes its temp file. The file always holds the whole in-memory state, so the next
successful write also carries any change an earlier failed write missed. Each failure writes
`server: ledger write failed: <errno name>` to stderr, never a field value.

**Request-side writes** (`analyze`, `reanalyze`, `remove`, `retry`, `delete`) are all-or-nothing.
The change is made on a copy, the copy is written, and it replaces the in-memory state only once
`os.replace` has succeeded. A failed write answers `500 ledger_write_failed` and changes nothing,
in memory or on disk.

**Runner-side writes record what has already happened, so each has its own rule (spec call):**

| # | Write | If it fails |
|---|---|---|
| 1 | job start: `waiting` → `running` | The job does not start: no subprocess runs. In memory the item becomes `failed`, with `ledger_write_failed` and `detail.stage = "start"`; the file still says `waiting`. The runner **pauses**: it starts nothing more until a later write succeeds (any request-side op, such as Retry), then resumes. After a restart the file's `waiting` item starts normally, because it never ran |
| 2 | success: item removed, run taken off the hide list | The run is already in the store, so memory records the success. The file keeps `running` and the old hide list until the next successful write. If the server stops first, the item comes back `interrupted`. Retry then re-runs it and replaces the run in place (D12). A run that was hidden before this re-analysis stays hidden until then |
| 3 | job failure: `running` → `failed` with its code and `detail`, including the catch-all's `internal_error` (§5.4) | Memory records the failure, so `busy` clears either way. If the server stops before a later write succeeds, the item comes back `interrupted`, and the failure's code and detail are lost |
| 4 | startup recovery: `running` → `interrupted` | Startup aborts with exit 2, naming the file and the errno, as for a corrupt `ledger.json` (§5.1). The server cannot keep D5's restart rule without recording it |
| 5 | shutdown: `running` → `interrupted` with `detail` | stderr says so, and the server exits anyway, inside its exit bound. At the next startup the file's `running` becomes `interrupted` (write 4), without the detail |

`ledger_write_failed` is therefore two things, worded consistently in §3.5, §5.1, §5.4 and §9.2:
the inline answer to a request whose own write failed, and a failed item's `error` after write 1.

## 6. Real progress (D6 and the correction)

### 6.1 The analyzer's one optional report

`analyze()` (`analyze.py:463`) gains an optional `progress` callable, defaulting to `None`. `main()`
(`analyze.py:778-793`) gains `--progress`, which passes a writer that prints
`treko-progress <stage>\n` to **stderr** and flushes. Stages are reported when they **finish**, in
this order:

| Key | Reported after (`analyze.py`, `5f194df`) | Label while it runs |
|---|---|---|
| `worktrees` | the repo check and `_worktrees(root)` (`:468`, `:472`) | reading worktrees |
| `branches` | `_base_branch` and `_collect_branch_facts` (`:473-481`) | reading branches |
| `cards` | the `Card(...)` list and `_ask_about_cards` (`:483-486`) | reading cards |
| `order` | everything from `_declared_edges` to `_build_kanban` (`:487-516`) | deriving merge order |

Nothing else in `analyze.py` changes, beyond `--card` (§4.3; OQ-1, (my call)) and, since round 3,
the one behaviour change of §6.3 for a worktree whose `git status` fails (U6). **The correction's
promise is a test (E2):** without `--progress` and `--card`, stdout, stderr and exit status are
byte-identical to today's analyzer for every repository whose `git status` succeeds in each of
its worktrees, which is every E2 fixture. With `--progress`, stdout is byte-identical too, and stderr
adds exactly the four lines on success. `--card` has its own check (E5). Card 5 cites
`analyze.py` by line at seven distinct places
(`grep -o -E 'analyze\.py:[0-9-]+' docs/features/treko-branch-graph-traversal.md | sort -u`). As
the card records, those citations are re-checked when card 5 resumes. Split 1 (§1.1) moves
`:36-41` into `cards.py` and shifts every later line, and split 3 shifts card 5's six
`Treko.dc.html` citations, so the recheck covers those as well.

### 6.2 The job's stage list and the bar

For a job over N families: 1 scan stage, 4 per family, 1 merge, 1 store write, so
`total = 4N + 3`. `done` counts finished stages only. Until the scan finishes, N is unknown, so
`total` is `null` and the bar is empty with the label "scanning <dir>". A failed family's
unreported stages count as done, so the bar keeps moving honestly.

**(spec call)** The label names the stage now running: the one after the last reported finish,
which the fixed order makes known. That is how bar and label stay in step, as D6 asks. Labels:
`scanning <dir>`, then `<label> (<i> of <N>): <stage label>` (the `(i of N)` part is dropped when
N is 1), then `merging the runs`, then `writing the store`.

The bar's width is `done / total`, recomputed only when a status response changes it. There is no
timer, no indeterminate animation, and no easing between polls apart from a CSS transition that
plays out a real change. Criterion E3 proves that nothing moves between reports.

### 6.3 A worktree whose `git status` fails shows "changes unknown" (U6, round 3)

**Today.** For each local branch that has a worktree, `_collect_branch_facts` runs
`_git(worktree, "status", "--porcelain", allow_failure=True)` and counts the non-blank lines
(`analyze.py:437-438`). `_git` returns `""` for any failure when `allow_failure` is set
(`analyze.py:92-103`), so a `git status` that exits non-zero counts as **0**. `_branch_entries`
then turns 0 into `"dirty": false` (`:421`) and, unless the branch is behind or ahead, the note
`"clean"` with tone `"ok"` (`:405-413`). The board colours the branch's dot red only when
`b.dirty`, otherwise by `TONES[b.tone]` (`Treko.dc.html:714`), and shows `b.note` as text
(`:264`). Measured (`probe_r3.sh`, rows S0–S2): a fixture worktree whose index file was
overwritten with junk makes `git status --porcelain` exit 128 ("index file smaller than
expected"), and today's analyzer, with all the protective settings, reports that branch exactly
as it reports the intact fixture: `dirty: false`, note `"clean"`, tone `"ok"`, exit 0.

**The change, the smallest that keeps the schema (spec call for the shape and the words).**

- **Field shape: unchanged.** No key is added and no value type changes. `dirty` stays a
  boolean, `false`, because ADR 0023 forbids redesigning the schema ("If the analyzer needs a
  field the schema does not have, that is a `questions[]` entry … never an ad-hoc extension");
  `test_analyze.py:40` pins the branch key set and `:556` asserts `dirty` is a `bool`, and both
  stay true. A `null` `dirty` was considered and rejected for that reason.
- **The note and tone carry "unknown".** `_collect_branch_facts` calls `_git(worktree, "status",
  "--porcelain")` without `allow_failure` and catches the `GitError` it raises on a non-zero
  exit; the branch's count becomes "unknown". `_branch_entries` checks that first, before
  behind and ahead, and writes `note: "changes unknown"` with `tone: "neutral"`. Unknown takes
  the slot "N uncommitted" would have taken, since a status that could not be read might have
  hidden exactly that. `ahead`, `behind`, `last`, the diffstat, the commits and every other field
  of the branch and the repo are computed as today.
- **One question says why.** The run gains one question per such worktree: "Why could git not
  read the changes in `<worktree>`?", with the `GitError`'s text as its context, after the
  analyzer's existing questions. A question is the channel ADR 0023 names, and it is where the
  exit status and git's message go, since the note has room for neither.
- **Board rendering: no code change.** `tone: "neutral"` is in the board's `TONES`
  (`Treko.dc.html:375`) and in `test_analyze.py`'s `UI_TONES` (`:32`), so the dot is the neutral
  colour, not red, not green, and the pill reads "changes unknown". The question shows in the
  board's questions list like any other.
- **Byte-for-byte guarantee kept.** Only the failure branch changes: for a repository whose
  `git status` succeeds in every worktree, stdout, stderr and exit status are byte-identical to
  today's (E2's fixtures all succeed). Criterion E6 checks the failure branch and its falsifier.

## 7. One run from several repos (D9)

`ledger_merge.merge(request, parts, scan_questions) -> run`. It is a pure function. Each part is
one family's analyzer run and root, or that family's failure. Every job goes through it, one family
or many, so there is one code path.

### 7.1 Section by section

| Section | Rule |
|---|---|
| `id`, `name`, `dir` | from the request (§8.1). `analyzedAt` is `""`, stamped by the store |
| `features`, `branches` | concatenated in family order |
| `questions` | scan-level questions first, then the merge's own (failed families, OQ-2, (user)), then each family's; renumbered `q1…qN` (the analyzer restarts at q1: `analyze.py:306-310`) |
| `constraints` | concatenated; renumbered `C1…Cn` (`analyze.py:697-705`) |
| `waves` | **layered** waves merged by index: wave k is every family's wave-k items in family order, with the analyzer's own note for k. Every family's **cycle** wave, which the analyzer always emits last with the note `cycle — order undetermined, see questions` (`analyze.py:684-691`), merges into one final wave numbered after the longest layered run. The merge module holds that note as a constant, and criterion F2 pins it to the analyzer's real output |
| `graph` | nodes renumbered in family order with `analyze._node_id` (`analyze.py:333-338`); edges remapped. Each family keeps its x (column). Its y is shifted below the previous family's bottom row plus one empty row (`analyze.GRAPH_DY`) |
| `kanban` | the four columns (titles and tones are analyzer constants, `analyze.py:756-761`), items concatenated per column |

Repos are independent in this card: cross-repo dependencies belong to the relations card. So
merging waves by index claims nothing false: wave 1 of two repos can land in parallel.

**Repo labels and card names in multi-repo runs: OQ-3, answered (my call) as recommended.** Card
names stay exactly as the analyzer emits them, since every task row and kanban card already shows
its repo.
When two families share a folder name (`~/dev/foo` and `~/work/foo`), both families' repo label
becomes the home-collapsed primary-checkout path, in `tasks[].repo`, `branches[].repo` and the
kanban `m` prefix. Otherwise the board's branch grouping (`Treko.dc.html:715`, grouping by `repo`)
would fuse them.

### 7.2 Merge-level questions (spec call: wording)

- Unreadable folders, when the count is above zero: "Were repositories missed under `<dir>`?",
  context "N folders could not be listed during the scan, so any repository inside them is missing
  from this run." **(spec call, O1)** The question also reports §4.1's other two counts, and is
  asked when any of the three is above zero. Its context names each count that is not zero: "N
  folders could not be listed, M folders at depth 5 were not looked inside, and K symlinked
  folders were not followed, so any repository inside them is missing from this run."
- Candidates git refused: "Why could git not read `<path>`?", one per path, with git's message.
- Failed families (OQ-2, (user): visible, naming the repo and why): "Why could `<label>` not be
  analyzed?", with the exit status or timeout and the analyzer's last stderr line.
- Copies that disagree (§4.3): "Which copy of `<card>` is current?", naming the worktrees.

### 7.3 Two properties the tests pin

- **Identity.** One family, no narrowing: `merge()` returns the analyzer's run with only `id`,
  `name` and `dir` replaced. This is what proves the merge invents nothing.
- **Schema.** Every merged run has exactly the key set and value types of an analyzer run (ADR
  0023: the schema is not ours to change). Node, question and constraint ids are unique, every
  edge names existing nodes, and no two node boxes overlap.

### 7.4 The board's graph must grow with it

Measured 2026-11-03 on the pinned Chrome `156.0.8078.79`, with markup copied from
`Treko.dc.html:220` (`<svg width="700" height="260" style="position:absolute;inset:0">`): the svg's
box is 700×260 and its computed `overflow` is `hidden`. A stroke at y=400 does not hit-test; one at
y=100 does. So **any graph taller than 260px or wider than 700px loses edges today**, including a
single repo with more than three cards in one wave, and stacking families makes it certain. D9 asks
that multi-repo runs render correctly, so the svg's `height` binds to the computed `graphH`
(`Treko.dc.html:710`) and its `width` to the larger of 700 and the rightmost node's x + 188. No
data field is added.

## 8. Runs, ids and Delete (D7, D12)

### 8.1 Id, name, dir

- **id** = `"r"` + the first 16 hex digits of the SHA-256 of
  `json.dumps([directory, repo, branch, worktree], ensure_ascii=False, separators=(",", ":"))`,
  encoded as UTF-8. `directory` is canonical (§3.4). `worktree` is canonicalized the same way when
  it contains `/` or starts with `~`, and is otherwise used as given. Absent fields are `""`.
  `~/dev/foo` and `~/work/foo` differ; the same folder typed two ways does not (D12).
  **(spec call)** for the format.
- **name** = the canonical directory's last component, plus ` · repo <r>`, ` · branch <b>`,
  ` · worktree <w>` for each narrowing used **(spec call)**. Two runs of one folder must not look
  alike in the list.
- **dir** = the home-collapsed canonical directory.
- The **queue label** is the same, built on `dir` instead of the last component: the prototype's
  `parts.join(' · ')` (`Ledger.dc.html:176-177`).

### 8.2 Replace in place; requests

Re-analysis writes the same id, and `store.upsert_run` (`store.py:127-143`) replaces it in place.
`requests[id]` records the request each run was last written from, and the board's Re-analyze
re-queues exactly that request (builder check). Since round 1 it is written when the item is
first queued, because the id already determines the request (§3.4, §5.6). Re-analyze puts that
request through the submit-time path again, so a recorded directory or narrowing worktree that
has since gone is refused, with nothing queued (§3.4). Runs written before this card have a
folder-name id and no recorded request. For those, Re-analyze queues
`{"directory": <the run's dir, with ~ expanded>}` with no narrowing. It lands as a new run under a
D12 id, and the old run stays, untouched, until the user deletes it (OQ-7, (my call)).

### 8.3 The row (D7: computed from the run's own data only)

| Shown | Derivation from the run object |
|---|---|
| name, analyzed-at, dir | `name`, `analyzedAt` as stored (an ISO timestamp, no relative time), `dir` |
| repos | distinct `branches[].repo` values (the prototype's derivation, `Ledger.dc.html:189`) |
| branches | `len(branches)` |
| worktrees | branches whose `wt` is neither `""` nor `—`. The prototype counts `b.wt` truthiness (`Ledger.dc.html:190`), but the analyzer writes `—` when a branch has no worktree (`analyze.py:443`), so that count equals every branch. Detached worktrees are not in the run's data and are not counted |
| features | `len(features)` |
| tasks-done bar | sums of `done` and `total` over features whose `meta` matches `^(\d+)/(\d+)$`. Label `<done> / <total> tasks done`, plus ` · <n> unreadable` when n features carry `?/?` (`analyze.py:47`), so the bar never reads as covering cards it skipped **(spec call)** |

Rows are sorted by `analyzedAt` descending, with ties in store order **(spec call)**. They are
computed server-side in `ledger_state.py` and cached on the store file's
`(st_mtime_ns, st_size)` **(spec call)**.

### 8.4 Delete

The prototype's dialog and wording are kept (D7): "Delete run?" / "“<name>” will be removed from
the ledger and the board. The analysis files on disk are not touched." / Cancel / Delete run
(`Ledger.dc.html:124-135`). Delete adds the id to `hidden`. Nothing on disk is erased (D12), and
the store's bytes are unchanged (criterion G3).

**(spec call, confirmed by the user 2026-11-03)** The ✕ shows only while more than one run is
visible (`canDelete`), as in the prototype (`Ledger.dc.html:196`, `canDel: runsAll.length > 1`),
and the server refuses the last one with `409 last_run`. The board cannot render zero runs:
`Treko.dc.html:649-650` reads `run.id` of `data.runs[0]`.

## 9. The pages (D1, D8, `file://`, Re-analyze)

### 9.1 The Ledger page

A port of the prototype, not an adoption (`treko-rename.md:746-751`). Copy the prototype's
structure and wording; take the board's conventions for everything else:

- **Assets:** the board's served set only (`vendor-resources.js` first, `support.js`, `_ds`,
  local phosphor regular and fill, `treko-icon.png`). **No `tracker-data*.js` script tag**, so
  `file://` can never pull in the sample.
- **Theme:** the board's token `<style>` block copied byte for byte, read from `taskTracker.theme`
  at mount **(spec call)**. A guard test pins the two copies equal. No colour literals outside the
  block; the prototype's hex values become the board's tokens.
- **Logic:** pure functions in a node-loadable slice between start and end markers, cut out and
  tested in node the way `test_ui_commands.py` tests the board's slice (`Treko.dc.html:402-525`).
  **(spec call)** This keeps the manifest closed. The board's own slice moves out to
  `board-commands.js` (split 3) only because the board would cross 800 lines. The Ledger keeps
  its slice in the page because it sits well under its 600-line budget (§1.1).
- **Header:** icon, "Run ledger", "Every analysis this Treko instance has on disk.", and **Open
  the board**, which opens the most recent run (D1): the first row, by §8.3's order. It is
  disabled while there are no rows **(spec call)**, so the Ledger never leads to the board's
  sample data.
- **Form:** Directory path (placeholder `~/dev`); Repo, Branch, Worktree marked "· optional"; the
  subtitle "directory is required — repo, branch and worktree narrow the scan". One **Analyze**
  button (D4), disabled while its request is in flight. The page trims each box and sends `""`
  for empty ones. A blank directory never leaves the page ("Directory path is required." as in
  the prototype). On success the four boxes clear, as in the prototype.
- **D8:** under the form, "Artifacts path · where snapshots are written" and `storeDir` as
  monospace **text**. No `<input>`, no Save, no "Saved".
- **Queued:** shown when the queue is not empty, one row per item: label, a sub-line, and per
  state, running (bar and stage label, no ✕), waiting (✕), interrupted or failed (Retry and ✕).
- **Runs on disk:** count and rows (§8.3), each with Open and the ✕ when `canDelete`.
- **Polling:** `GET /ledger/status` on load, then every `LEDGER_POLL_MS = 2000` **(spec call)**.
  Polling stops on `403` and on a rejected fetch, both terminal (§9.2).
- **Open / Open the board:** write `taskTracker.run` to the run's id, then go to `/`, where the
  board stays (U1). That is the prototype's handoff (`Ledger.dc.html:198`) and the key the board
  already reads at mount (`Treko.dc.html:540`).
- `Esc` closes either dialog.

### 9.2 What the Ledger shows (the page never renders response text)

The board's three rules (`tracking-feature-state.spec.md:462-468`) hold here: every outcome
reaches a visible state; the page maps `error` codes to its own fixed strings and never displays
response text; an unknown code shows "Unexpected error." Data from the status response (names,
paths, stage labels, run rows) is rendered as **text content only**, never as HTML, an attribute
or a URL. Wording is **(spec call)** except where a source is named.

| Code or event | Where | Shown |
|---|---|---|
| `no_repository` | pop-up | "No git repository found in or around that directory." (D2) |
| `no_matching_repository` | pop-up | "No repository with that folder name was found in or around that directory." |
| `no_such_worktree` | pop-up | "No worktree with that path or folder name was found in those repositories." |
| `nothing_matched` | pop-up (OQ-4, (user)) | "No card matches that branch or worktree." |
| `relative_path` | inline | "Use a full path, or one starting with ~." |
| `no_such_directory` | inline | "No directory exists at that path." |
| `invalid_input` | inline | "Treko cannot use one of those values: check for stray characters." |
| `already_queued` | inline | "That analysis is already queued or running." (since round 1 the code covers a running item too, §3.5) |
| `queue_full` | inline | "The queue is full. Remove an item first." |
| `scan_timeout` | inline / item | "The directory scan took too long. Try a smaller directory." |
| `scan_failed` | inline / item | "The directory scan stopped with an error." On an item, plus " (exit status <exit>)" |
| `launch_failed` | inline | "Treko could not start the directory scan, so nothing was queued." (U2) |
| `launch_failed` | item | "Treko could not start the directory scan (<errno>)." when `detail.stage` is `scan`; otherwise "Treko could not start the analyzer for <repo> (<errno>)." Both end " This analysis stopped and nothing was saved. Retry it once the problem is fixed." (U2; round 3 replaced "Nothing was analyzed.", which is false once an earlier family has finished: §5.4 step 3 fails the whole job, so finished families are discarded, not saved) |
| `analysis_failed` | item | "No repository could be analyzed. The first to fail was <repo>, while <stage>, with exit status <exit>." Or "…, while <stage>, after the time limit." when `timedOut` |
| `merge_failed` | item | "The results for each repository could not be combined into one run, so nothing was saved. Retry runs it again." (U2) |
| `store_write_failed` | item | "The run could not be saved to the store folder (<errno>)." |
| `internal_error` | item | "Treko hit an unexpected error while <stage>, so this analysis stopped. Retry runs it again." With `detail.stage` `null`: "Treko hit an unexpected error, so this analysis stopped. Retry runs it again." (U2) |
| `ledger_write_failed` | inline | "The queue file could not be written, so nothing changed." |
| `ledger_write_failed` | item | "The queue file could not be written (<errno>), so this analysis did not start. Retry it once the disk can be written again." |
| `no_such_item` | inline | "That item is no longer in the queue." (round 2, F6) |
| `no_such_run` | inline | "That run is no longer on the Ledger." (round 2, F6) |
| `item_running` | inline | "That analysis has already started, so it can no longer be removed." (round 2, F6: routine when ✕ is clicked inside the poll gap as the item starts) |
| `not_retryable` | inline | "That item is already waiting or running." (round 2, F6) |
| `last_run` | inline | "The last run on the Ledger cannot be deleted." (round 2, F6: reachable only through a race, since the ✕ is hidden, §8.4) |
| `store_unreadable` | inline | "The runs file in the store folder cannot be read, so nothing changed." (round 2, F6: `delete` or `reanalyze` while the store does not parse) |
| `200` analyze, `started` true / false | inline | "Started." / "Queued — it starts when the running analysis finishes." |
| interrupted item | item | "Interrupted when the server stopped. Retry to run it again." With `detail.stage` known: "Interrupted while <stage> <repo> when the server stopped. Retry to run it again." |
| `forbidden` (`403`) on any request | banner, terminal | "This page's token is stale — reload to reconnect." (the board's string) |
| fetch rejected | banner, terminal | "The control server is no longer running." (the board's string) |
| `runsError` | runs list | "The runs file in <storeDir> cannot be read, so no runs can be listed." (rewritten at round 2, F5) |
| `malformed` (`400`), `method_not_allowed` (`405`), `too_large` (`413`), `unsupported_media_type` (`415`) | inline | "Unexpected error." These are page bugs; the page cannot produce them by following this contract |

The pop-up uses the delete dialog's frame, with one **OK** button and the title "Nothing found".

**Every code has a row (round 2, F6).** Until round 2, six codes a request can really get
(`no_such_item`, `no_such_run`, `item_running`, `not_retryable`, `last_run`, `store_unreadable`)
had no row and fell to "Unexpected error.", and nothing compared the lists. Now every `error`
in §3.5's two tables and §5.4's code list has a row above, and criterion H11 checks both
directions mechanically. `asset_unreadable` is the one §3.5 names without a row: it answers the
two page loads, never a fetch the Ledger makes.

**`runsError` no longer points at a log (round 2, F5).** It used to say "The server's log says
why.", but nothing writes such a line: an accepted status poll writes no audit line (§2, default
4), and no other path logs a store that does not parse. **(spec call)** The message now names
the file's folder, `storeDir`, which the status response already carries (§3.3), and claims
nothing more. That was chosen over adding a log line, because a line written per poll would undo
default 4, and one written only on a change of state is new state to get right for a pointer the
user would still have to go and find.

**Each code has its own message, built from the item's `detail` (spec call, O2).** Until round
1, four codes shared "That did not work. The server's log says why." That log is gone after a
restart, and `detail` (§5.1) is not. `<repo>` and `<exit>` are data, rendered as text. `<errno>`
is the symbolic name. `<stage>` maps the closed set of stage keys to fixed words (`start` →
"starting", `scan` → "scanning the directory", `worktrees` → "reading worktrees", `branches` →
"reading branches", `cards` → "reading cards", `order` → "deriving merge order", `merge` →
"merging the runs", `write` → "writing the store"). A part whose value is `null` or unknown is
left out, never guessed. A job-time failure with one of the pop-up codes, or with
`no_such_directory`, shows that code's string on its item, not in a pop-up.

### 9.3 `file://`

No `tracker-token` meta means no server. The page shows the header without Open the board, and a
notice: "No Treko server is running, so this page cannot analyze or list runs. Start one from the
repository with:" followed by `python3 treko/server.py --open` (the skill's launch command).
**(spec call)** for the wording and for hiding Open the board, which would lead to sample data. There
is no form, no queue and no run list. It makes no request for any `tracker-data*.js` file, so the
bundled sample is never listed (builder check). The board's own copy-only `file://` mode
(`Treko.dc.html:543-545`) is unchanged.

### 9.4 Board changes, and only these

1. **Icons (D1).** The two Treko icons, collapsed rail `Treko.dc.html:61` and expanded sidebar
   `:78`, are wrapped in `<a href="{{ ledgerHref }}" title="Back to Ledger">`, as the prototype
   wraps them (`Task Tracker.dc.html:55`, `:75`). `ledgerHref` is `/ledger` when the token meta
   is present and `Ledger.dc.html` otherwise (U1; `/` until round 2). The missing-data icon
   (`:50`) stays unlinked **(spec call)**.
2. **Re-analyze.** It posts `{"op": "reanalyze", "run": <on-screen run id>}` to `/ledger` and never
   posts to `/command`. After a `200` the board goes to `/ledger`, where the job's progress is
   (OQ-5, (user); U1). That replaces today's reload after a successful `reanalyze` (`shouldReload`,
   `Treko.dc.html:483`, acted on at `:641`) and retires old criterion 15's `500` row
   (`tracking-feature-state.spec.md:1085-1087`), which has no server path left once `reanalyze`
   leaves `/command`. The board maps `403` to its stale-token string, a rejected fetch to its
   server-gone string, `no_such_run` to "This run is no longer on the Ledger.", `already_queued`
   and `queue_full` to the §9.2 strings, and every other code to "Re-analysis could not be queued,
   and nothing changed." **(spec call)** That small set avoids a second full copy of the Ledger's
   table. **Reworded at round 3:** the string used to end "Open the Ledger to see why.", but for
   every code in this bucket nothing was queued, so the Ledger had nothing to show. "Nothing
   changed" holds for each of them: each is a refusal before anything is queued, and a failed
   ledger write changes nothing (§5.6). In copy mode (no token) the `python3 treko/analyze.py .` chip stays as it is.
   The transport and the mapping live in `board-commands.js` after split 3 (§1.1).
   **When the run can no longer be analyzed (spec call, round 1).** For `no_such_directory`,
   `no_such_worktree`, `no_repository`, `no_matching_repository` and `nothing_matched`, nothing
   was queued (§3.4). The board stays on the board and shows a pop-up with one **OK** button and
   the title "Cannot re-analyze":
   - `no_such_directory`: "This run's directory no longer exists, so it cannot be analyzed again.
     Nothing was queued."
   - `no_such_worktree`: "The worktree this run was narrowed to no longer exists (worktrees are
     removed after a merge), so it cannot be analyzed again. Nothing was queued."
   - the other three: "This run's directory no longer holds what it was analyzed from. Nothing
     was queued."

   These five are taken out of "every other code" above.
3. **Graph svg size** (§7.4).

## 10. Scenarios

```gherkin
Scenario: a directory holding repositories is analyzed while nothing runs
  Given ~/dev holds repos alpha and beta, and the queue is empty
  When  the user types ~/dev and clicks Analyze
  Then  the response is 200 with started true and one item is running
  And   its stage total becomes 11 (4×2+3) once the scan has finished
  And   on success one run named "dev" lists repos 2 and replaces any earlier "dev" run in place

Scenario: Analyze while a job runs queues the request
  Given an item is running
  When  the user clicks Analyze for ~/work
  Then  the response is 200 with started false and the item is waiting
  And   it starts by itself once the running item finishes

Scenario: nothing found
  Given ~/empty holds no repository within 5 levels down and none within 5 levels up
  When  the user clicks Analyze
  Then  the response is 422 no_repository and the queue is unchanged
  And   a pop-up reads "No git repository found in or around that directory."

Scenario: a subfolder of a repo analyzes the repo
  Given ~/dev/memsearch is a repo
  When  the user analyzes ~/dev/memsearch/docs
  Then  the run covers memsearch

Scenario: a worktree pulls in its family, counted once
  Given ~/dev/foo has a worktree at ~/wt/foo-x, and the user analyzes ~
  When  the scan reaches both ~/dev/foo and ~/wt/foo-x
  Then  the run holds one family, foo, and its branches list both worktrees

Scenario: the worktree's copy of a card wins
  Given card x on main says "branch: none" and the copy in feat/x's worktree says "branch: feat/x"
  When  the repo is analyzed
  Then  features[] holds x once, with the ticks and phase of the feat/x copy

Scenario: Branch narrowing keeps the dependencies
  Given card b depends on a, and only b names branch feat/b
  When  the user analyzes the repo with Branch feat/b
  Then  the run holds a and b, and waves order a before b

Scenario: a refresh does not stop the job
  Given an item is running
  When  the page reloads, or every tab closes for longer than the poll interval
  Then  the item is still running and finishes, and no request was needed for it to finish

Scenario: the server stops mid-job, then restarts
  Given item 1 is running and item 2 is waiting
  When  the server is stopped and started again
  Then  item 1 is interrupted and does not run until Retry
  And   item 2 starts by itself

Scenario: removing items
  Given item 1 is running and item 2 is waiting
  When  the page sends remove for item 1, then for item 2
  Then  the first is 409 item_running and the second is 200, leaving only item 1

Scenario: Delete hides, and re-analysis brings the run back
  Given runs A and B are visible
  When  the user deletes A
  Then  status no longer lists A, GET /tracker-data.js omits A, and the store's bytes are unchanged
  When  the user analyzes A's directory again and the job succeeds
  Then  A is listed again

Scenario: the last visible run cannot be deleted
  Given only run A is visible
  Then  its row has no ✕, and delete A returns 409 last_run

Scenario: progress moves only on real stages
  Given an analyzer that reports "worktrees" and then sleeps 6 s
  When  the page polls three times during the sleep
  Then  stage.done is the same in all three responses

Scenario: polling alone does not keep the server alive
  Given no job and TREKO_IDLE_SECS=60
  When  a client polls /ledger/status every 2 s and sends nothing else
  Then  the server exits within 60 s + TREKO_POLL_SECS of the last other request

Scenario: a long job keeps the server alive
  Given TREKO_IDLE_SECS=60, TREKO_ANALYZE_SECS=120, and a one-repo job lasting 90 s, no requests
  Then  the server is alive when the job ends, and exits no sooner than 60 s after that

Scenario: a scanned repo's fsmonitor program never runs
  Given a repo whose .git/config sets core.fsmonitor to a marker-writing script
  When  a Ledger job analyzes it
  Then  no marker file exists

Scenario Outline: hostile and malformed requests are refused before git or cmux runs
  Given a valid token
  When  POST /ledger carries <body>
  Then  the answer is <status> <error>
  And   no git or cmux process was started

  Examples:
    | body                          | status | error         |
    | an unknown key                | 400    | malformed     |
    | an unknown op                 | 403    | forbidden     |
    | 5000 bytes                    | 413    | too_large     |
    | directory "dev/x"             | 422    | relative_path |
    | a directory containing a tab  | 422    | invalid_input |

Scenario: file:// shows no runs
  Given treko/Ledger.dc.html is opened as a file, with the sample data beside it
  Then  the no-server notice and the launch command show, with zero run rows
  And   no tracker-data*.js request is made

Scenario: the board returns to the Ledger
  Given the board is open at /
  When  the user clicks either Treko icon
  Then  the browser is at /ledger

Scenario: the board keeps its address
  Given a running server
  When  a client requests GET /
  Then  the response is Treko.dc.html as it stands, with today's one meta substitution and today's headers

Scenario: launching opens the Ledger
  Given the store holds runs
  When  server.py --open starts
  Then  the browser opens at <origin>/ledger and nothing is queued

Scenario: Re-analyze from the board
  Given the board at / shows run R, recorded with request Q
  When  the user clicks Re-analyze
  Then  POST /ledger {"op":"reanalyze","run":R} queues Q, and /command receives nothing
  And   the browser is then at /ledger, where the job shows

Scenario: Branch matches no card
  Given ~/dev holds repositories, and no card in them names branch feat/none
  When  the user clicks Analyze with Branch feat/none
  Then  the response is 422 nothing_matched and the queue is unchanged
  And   a pop-up reads "No card matches that branch or worktree."

Scenario: one repo of two fails
  Given ~/dev holds repos alpha and beta, and beta's analyzer exits non-zero
  When  the job runs
  Then  the run holds alpha, plus a visible question naming beta with its exit status and why
  When  both analyzers fail instead
  Then  nothing is written and the item fails with analysis_failed

Scenario: two repos share a folder name
  Given the scan finds ~/dev/foo and ~/work/foo
  When  the job runs
  Then  their repo labels are ~/dev/foo and ~/work/foo, and every card name is unchanged

Scenario: first launch with an empty store
  Given the store holds no runs
  When  server.py --open starts inside the repo ~/dev/memsearch
  Then  one item for ~/dev/memsearch is queued, then the browser opens at /ledger
  And   the run it writes carries a D12 id, never the folder name

Scenario: Re-analyze of a run from before the Ledger
  Given run "memsearch" has a folder-name id and no recorded request
  When  the user clicks Re-analyze on the board
  Then  its directory is queued with no narrowing, and the result lands under a new D12 id
  And   the old run's bytes in the store are unchanged

Scenario: Re-analyze a run whose directory has been deleted
  Given the board at / shows run R, recorded with directory ~/dev/gone, which no longer exists
  When  the user clicks Re-analyze
  Then  the response is 422 no_such_directory and the queue is unchanged
  And   the board stays at / and shows the no_such_directory pop-up of §9.4, word for word

Scenario: Re-analyze a run whose narrowing worktree was removed after its merge
  Given the board at / shows run R, narrowed to the worktree ~/wt/feat-x, which has been removed
  When  the user clicks Re-analyze
  Then  the response is 422 no_such_worktree and the queue is unchanged
  And   the board stays at / and shows the no_such_worktree pop-up of §9.4, word for word

Scenario: two identical submits race
  Given nothing is queued or running
  When  two tabs send the same analyze request at the same moment
  Then  exactly one item exists for that run id
  And   one request gets 200 and the other gets 409 already_queued

Scenario: the queue file cannot be written when a job would start
  Given an item is waiting and ledger.json cannot be written
  When  the runner would start it
  Then  no analyzer or scan process starts, and the item shows ledger_write_failed
  And   nothing else starts until a later ledger write succeeds

Scenario: a repository below the depth limit is reported, not silently absent
  Given ~/deep holds one repository 2 levels down and another 6 levels down
  When  the user analyzes ~/deep
  Then  the run holds the first repository only
  And   it asks "Were repositories missed under ~/deep?", counting 1 folder at depth 5

Scenario: a failed job's reason survives a restart
  Given an item failed with analysis_failed: beta, at branches, exit status 1
  When  the server is stopped and started again
  Then  the item's message still names beta, "reading branches" and exit status 1 (§9.2)

Scenario: an accepted status poll writes no audit line
  Given a Ledger tab polls every 2 s for a minute
  Then  stderr holds no audit line for an accepted poll
  When  a poll arrives with a wrong token
  Then  stderr holds one refused audit line for it

Scenario: the per-repo results cannot be combined
  Given ~/dev holds repos alpha and beta, both analyzed, and the merge raises
  When  the job reaches its merge stage
  Then  the item is failed with merge_failed and detail.stage "merge"
  And   the store's bytes are unchanged, no item is running, and the next waiting item starts

Scenario: the analyzer cannot be started at all
  Given the interpreter the job launches the analyzer with cannot be executed
  When  a job over ~/dev reaches its first family
  Then  the item is failed with launch_failed, detail.stage "worktrees" and the errno's name
  And   no later family is attempted, and no item is running

Scenario: the directory scan cannot be started at submit
  Given the interpreter the scan is launched with cannot be executed
  When  the user clicks Analyze
  Then  the response is 500 launch_failed and the queue is unchanged

Scenario: anything else that goes wrong ends the job, never strands it
  Given a job whose handler for the analyzer's "cards" report raises an exception nothing else catches
  When  the job runs
  Then  the analyzer's process group is gone before the item shows failed
  And   the item is failed with internal_error and detail.stage "cards"
  And   stderr names the exception's class and not its message
  And   no item is running, so with nothing waiting the server exits once the idle period passes

Scenario: Retry cannot make a second live item for one run
  Given item 1 for run R has failed, and item 2 for the same request R is waiting
  When  the page sends retry for item 1
  Then  the response is 409 already_queued and item 1 stays failed

Scenario: shutdown kills a submit-time scan that hangs
  Given an Analyze request whose scan hangs
  When  the server shuts down before the scan's time limit
  Then  the scan's process group is gone within the server's exit bound

Scenario: config from the server's own environment cannot re-enable fsmonitor
  Given the server was launched with GIT_CONFIG_PARAMETERS naming a marker-writing fsmonitor script
  When  a Ledger job analyzes a repo
  Then  no marker file exists

Scenario: git writes nothing in a scanned repo
  Given a repo with a worktree, a stat-dirty file in each checkout, and a repo-set post-index-change hook
  When  a Ledger job analyzes it
  Then  the hook never runs, and every file under its .git is unchanged in content and mtime

Scenario: a repo-named gpg program never runs
  Given a repo whose branch tip is a signed commit, and whose config sets log.showSignature=true and gpg.program to a marker-writing script
  When  a Ledger job analyzes it
  Then  no marker file exists, and the job succeeds

Scenario: a partial clone is never fetched from
  Given a partial clone whose remote.origin.uploadpack is a marker-writing script, with a branch whose blobs are missing
  When  a Ledger job analyzes it
  Then  no marker file exists, no object is downloaded, and that branch's diff is empty

Scenario: a worktree whose git status fails shows changes unknown
  Given a repo with a worktree whose git status exits 128
  When  the repo is analyzed
  Then  that worktree's branch reads "changes unknown" with tone neutral, and dirty stays false
  And   one question names that worktree and git's message
  And   every other branch, and that branch's ahead, behind and last, read as they would anyway

Scenario: shutdown in the middle of a two-repo job
  Given a job over ~/dev with repos alpha and beta, and alpha's analyzer is running
  When  the server shuts down
  Then  beta's analyzer never starts, alpha's process group is gone within the exit bound
  And   the item is interrupted, not failed

Scenario: a failed job's end keeps the server up for the idle period
  Given TREKO_IDLE_SECS=60 and a one-repo job that fails after 90 s, with no requests
  Then  the server is alive when the job fails, and exits no sooner than 60 s after that
```

## 11. Acceptance criteria

Each criterion names its test module; new modules are in `treko/`. Every new test module is shown
able to fail: run it against a stub that always allows and one that always refuses, then keep only
assertions that tell the two apart.

**A. Wire contract** (`test_ledger_routes.py`, server-level through `server_harness`)
- A1. `GET /ledger` serves the Ledger with both metas, the CSP, `no-store` and `nosniff`, and
  refuses a foreign `Host` with 403. `GET /` is the board exactly as today (U1): its body equals
  `Treko.dc.html` with today's one meta substitution, and its status and headers equal today's,
  with only the token's value different. `srv.token` (`server_harness.py:164`) still reads the
  token from `GET /`, unchanged.
- A2. Every row of §3.5's first table is driven. Each returns its status and exact body, and writes
  one audit line with its reason. The test compares the table's reasons with the code's, both
  directions. Its `launch_failed` row is driven by a scan launcher passed in code that raises
  `OSError(ENOENT)`. The second table, codes only an item carries, is D7's and D12–D14's.
- A3. For each op, one unknown key gives 400. A 4097-byte body gives 413, and `/command` still gives
  413 at 1025.
- A4. `POST /command {"id":"reanalyze"}` gives `403` (`unknown_id`) and the store is untouched.
- A5. Across every `/ledger` and `/ledger/status` test, the fake cmux log stays empty.
- A6. The token appears in no file under the store directory (`ledger.json` and the lock
  included), in no child's environment or argv, and nowhere on stderr. This extends old
  criterion 10 (`tracking-feature-state.spec.md:889-899`).
- A7. O3: an accepted `GET /ledger/status` writes no audit line. A refused one (bad token, foreign
  `Host`, wrong `Origin`) writes one, with its reason. Every other accepted request still writes
  one.

**B. Lifetime** (`test_ledger_lifetime.py`)
- B1. The idle predicate (§5.5), as a table over injected clocks: busy is never idle, and the idle
  period counts from the later of the last request and the last job end. Since round 3 the table
  has a row per way a job ends (success, a failure code, `internal_error`, interruption), and in
  each `last_job_end` is the end's time; its falsifier is a runner that records the end only on
  success, under which the failure rows go idle at once.
- B2. End to end: a status-only poller does not keep the server alive (slow: the 60 s floor is
  never lowered to make it fast).

**C. Scan** (`test_ledger_scan.py`, on fixture trees)
- C1. Depth: a repo at depth 5 is found and one at 6 is not. Descent stops at a repo, including at
  depth 0: when the typed directory is itself a repo, a repo nested inside it is not found (OQ-6
  relies on this). Dot folders, `chflags hidden` folders (macOS only, skipped elsewhere),
  `node_modules` and symlinked folders are skipped. O1: every depth-5 folder that is not a
  repository, and every skipped symlinked folder, is counted. A tree holding one repository 2
  levels down and another 6 levels down gives a run with the first, plus a "Were repositories
  missed?" question counting the folder at depth 5.
- C2. Up: a directory 5 levels under a repo root finds it; 6 levels does not.
- C3. Families: a repo reached directly and through a worktree is one family. The family lists
  worktrees outside the scanned tree. Prunable entries are left out.
- C4. Narrowing: Repo by folder name; Branch; Worktree by path and by name; both together; the
  transitive closure; every non-`ok` outcome of §4.4, including `no_such_worktree` for a worktree
  no found repository has.
- C5. D11: each branch of §4.3's three-step rule, including disagreeing copies and their question.
- C6. Unreadable folders are counted, and refused candidates are named. The question's context
  carries the three counts of §4.1 as §7.2 words it, leaving out any count that is zero.
- C7. A scan that hangs is killed at `TREKO_SCAN_SECS` with its process group, and the result is
  `scan_timeout`.
- C8. D10 default 3, in two halves that must disagree: a job over a repo whose fsmonitor writes a
  marker leaves no marker, and the same run with the environment override removed (a test-only
  hook) writes one. O5: that hook is a different environment builder **passed as a parameter in
  code**, in-process. **Round 2 (F2) adds three rows**, each with the server launched with an
  extra variable in its own environment, and each must leave no marker: `GIT_CONFIG_PARAMETERS`
  naming the marker script for `core.fsmonitor` (probe 3); a `GIT_CONFIG_COUNT=3` family
  whose `KEY_2` names it (probe 15); and a `GIT_CONFIG_GLOBAL` file naming it (probe 6). Only the
  first row has an end-to-end falsifier: a builder passed in code that keeps
  `GIT_CONFIG_PARAMETERS` writes the marker (probe 3). The other two pass even without the drop,
  because the builder's own `GIT_CONFIG_COUNT` already overwrites or ignores an inherited pair
  (probe 16, measured at the round-2 count) and the pairs override a file (probe 6); they guard
  against a regression in the builder's overwrite, not the drop. So a unit row checks the drop
  directly: given a base holding `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT=3` and
  `GIT_CONFIG_KEY_0`…`_2`/`VALUE_0`…`_2` naming other keys, the result holds none of the base's
  values for those variables and no `GIT_CONFIG_PARAMETERS`; its `GIT_CONFIG_*` variables,
  `GIT_OPTIONAL_LOCKS` and `GIT_NO_LAZY_FETCH` are exactly the rows of §2 default 3's table; and
  every other base key is unchanged. Its falsifier is a builder that keeps them. (Corrected at
  round 3: this row used to say the result held "none of those" while also keeping
  `GIT_CONFIG_COUNT`, and named the table by a count.) **The AST check, widened at round 2:** in `ledger_jobs.py`, `ledger_scan.py` and
  `ledger_routes.py` (which starts the submit-time scan), no `ast.Name` or `ast.Attribute` is
  named `environ`, `environb`, `getenv` or `getenvb`, and no `from os import` names one. That
  catches whole-environment copies such as `os.environ.copy()`, `dict(os.environ)`,
  `{**os.environ}` and `environ` bound by an import, which the round-1 list of
  `os.environ[...]`, `os.environ.get(...)` and `os.getenv(...)` missed. Every value those modules
  use is passed in; the base environment is read only in `server.py` `main()` (§2, default 3).
  **The launch check, added at round 3.** The marker rows cannot see the submit-time scan: the
  scan's own git commands run no fsmonitor even with no protection at all (the observability
  judge's round-3 read, 0 hits), so they pass whether or not that launch uses the builder, and a
  launch that simply omits `env=` reads no environment and inherits all of it. So the same AST
  pass also checks every call that starts a process (`subprocess.Popen`, `.run`, `.call`,
  `.check_call`, `.check_output`, `os.system`, `os.popen`, and any `os.spawn*`, `os.exec*` or
  `os.posix_spawn*`):
  - in `ledger_jobs.py` and `ledger_routes.py`, there is exactly one such call, inside the child
    registry's launch method (§4), and it passes an `env=` keyword whose value is the builder's
    output; a process-starting call anywhere else, or that call with no `env=`, fails the check;
  - in `ledger_scan.py`, which runs inside a child that already has the builder's environment,
    its git calls pass **no** `env=`, so they inherit it, as `analyze.py`'s `_git` does
    (`analyze.py:92-103`); an `env=` there fails the check, since it could only replace the
    protective settings.

  Falsifier: copies of those modules with the scan launch's `env=` removed, and with a second
  `subprocess.run` added outside the registry, each make the check fail.
- C9. **Unconditional since round 2 (F3).** A job over a fixture repo with a worktree, a
  stat-dirty tracked file in each checkout, and a repo-set `core.hooksPath` whose
  `post-index-change` hook writes a marker: no marker, and every file under the repo's `.git`
  identical in content and mtime after the job (probe 14). Falsifier: a builder passed in
  code that sets only the fsmonitor pair writes the marker and rewrites both index files (probe 13).
  **The filter rows wait for task 1 (D15/U3, §2 default 3).** If task 1 finds LFS-backed
  scanning survives blanked drivers, a fixture whose config names a clean filter writing a marker
  leaves no marker. Whatever task 1 finds, a repository whose `.gitattributes` names
  `filter=lfs` is found and analyzed like any other (user: LFS repos are never skipped).
- C10. **`gpg.program` never runs (U4, round 3).** A job over a fixture repo whose branch tip is a
  commit carrying a `gpgsig` header, with repo config `log.showSignature=true` and `gpg.program`
  set to a marker-writing script: no marker, and the job succeeds (probe 19). Falsifier: a
  builder passed in code that sets every protective setting except the `log.showSignature` pair
  writes the marker (probe 20). The fixture's baseline, a plain `git log -1 --format=%cr` on that
  branch, must write it too (probe 17), or the fixture proves nothing.
- C11. **No lazy fetch (U4, round 3).** A job over a `--filter=blob:none` clone of a fixture
  origin, with a local branch whose blobs are missing and `remote.origin.uploadpack` set to a
  marker-writing script: no marker, the job succeeds and that branch's `diff` is `""` (probe 23),
  and `git rev-list --objects --missing=print` counts the same missing objects before and after
  (measured on the working clone of probe 25). Falsifier: a builder that sets every protective setting except
  `GIT_NO_LAZY_FETCH` writes the marker (probe 24). Baseline: a plain `git diff --shortstat` on
  that branch writes it (probe 21). A second row on a clone with the real upload-pack checks the
  same `""` and unchanged missing count, against a falsifier run that downloads the objects and
  shows `+3 −1` (probes 25 and 26).
- C12. **Other routes are named, not claimed (U4, round 3).** Not a test: the ADR task 1 writes
  lists the config routes tried (§2 default 3, "Which config routes were tried") and says that
  git's other config keys were not enumerated.

**D. Queue and jobs** (`test_ledger_jobs.py`, with fake analyzers dropped into the harness tree the
way `HANGING_ANALYZER` is, `server_harness.py:77`)
- D1. Start-or-queue; first in, first out; a retried item keeps its place.
- D2. The lifecycle of §5.2, every transition, and each refused one.
- D3. A restart turns running into interrupted and waiting into started; nothing restarts silently.
- D4. A job with no client connected runs to completion.
- D5. `ledger.json` survives a mid-write kill with the old or new content. A corrupt or
  wrong-version file aborts startup naming it. A second server on the same store directory aborts
  naming the lock.
- D6. Shutdown mid-job kills the analyzer's process group, so no orphan outlives the server's exit
  bound, and marks the item interrupted. Since round 2, shutdown while an `analyze` request's
  submit-time scan hangs (a fake scan dropped into the harness tree) also kills that scan's
  process group inside the same bound, and the queue is unchanged (§4, §5.3). **Since round 3,
  the closed state:** a two-family job whose first fake analyzer sleeps, with shutdown sent while
  it runs: the second family's analyzer never starts (the fake writes a start marker, and
  there is none for the second family), the first's process group is gone inside the bound, and
  the item is `interrupted` with the first family in `detail`, not `analysis_failed`. A launch
  asked of the registry after it closed starts nothing. Falsifier: a registry with no `closed`
  flag, under which the second family starts after the sweep.
- D7. OQ-2 (user): a two-repo job whose second analyzer exits non-zero writes a run holding the
  first repo, plus one question naming the second with its exit status and the analyzer's last
  stderr line. A job whose analyzers all fail writes nothing, and its item fails with
  `analysis_failed`.
- D8. OQ-6 (user), in `test_autolaunch.py`. With `--open` and an empty store, one item for the
  launch repo is queued before the browser opens, and no run carries a folder-name id. With runs
  in the store nothing is queued: the meaning `test_existing_run_is_not_reanalyzed_on_launch`
  (`test_autolaunch.py:284`) keeps. With `--repo` naming a folder that is not a repository,
  stderr says so, nothing is queued and the server still serves. With an item for that request
  already waiting or running, no second one is queued. In every case the browser recorder sees
  exactly one open, of `<origin>/ledger` (§3.2; U1). The existing
  `test_no_path_launch_opens_the_browser_at_the_bound_url` (`test_autolaunch.py:268-276`) checks
  only that `127.0.0.1:<port>` is a substring of the opened URL, so it passes unchanged and this
  exact-path assertion is new.
- D9. The ledger lock (§5.6). Two threads send the same `analyze` through `ledger_routes`,
  released together by one barrier, 50 times. Every round leaves exactly one item for that run
  id, and the other request gets `409 already_queued`. In the same way, a `remove` racing the
  runner's start of the same item ends with the item either running (the remove refused with
  `item_running`) or removed and never started, never both. Since round 2, `retry` of a failed
  item raced, the same way, against an `analyze` of the same request: every round leaves exactly
  one live item for that run id, and the loser gets `409 already_queued`. A plain `retry` while a
  same-run item waits is refused the same way.
- D10. Each of §5.6's five runner-side writes, and one request-side write, is made to fail by a
  writer passed in code. Each ends in the state §5.6's table gives. stderr carries one
  `server: ledger write failed` line naming the errno and no field value. The file on disk is
  the previous one, byte for byte. After write 1 fails, no subprocess starts until a later write
  succeeds, and the server can still go idle (§5.5). After write 4 fails, the server exits 2.
- D11. O2: a failed item and an interrupted item each carry the `detail` their failure had
  (stage, repo, exit status or timeout, errno). `ledger.json` holds no other text: none of the
  fixture's stderr lines appears in it. **Rewritten at round 2 (§5.1):** request field values
  appear only under `queue[].request` and `requests`, and nowhere in `detail` except
  `detail.repo`, which must equal the label of a family the job's scan found (so it may equal
  `request.repo` when the job was narrowed by Repo, as the fixture's narrowed case checks). The
  detail, and so the message, survives a restart.
- D12. `merge_failed` (U2). A two-family job with a merge function passed in code that raises
  `ValueError`: the item is `failed` with `merge_failed` and `detail.stage = "merge"`; the store's
  bytes are unchanged; stderr's job line names `ValueError` and not the exception's message; no
  item is `running`, so a waiting item starts next, and with none waiting the idle predicate
  (§5.5) turns true once the idle period passes.
- D13. `launch_failed` (U2). With an analyzer launcher passed in code that raises
  `OSError(ENOENT)` on the first family's spawn: the item is `failed` with `launch_failed`,
  `detail.stage = "worktrees"`, `detail.repo` that family's label and `detail.errno = "ENOENT"`,
  and no second family's launch is attempted. With a scan launcher that raises the same way: at
  job time the item fails `launch_failed` with `detail.stage = "scan"`, and at submit the request
  gets `500 launch_failed` with nothing queued. In each, no item is left `running`.
- D14. `internal_error`, the catch-all (U2). A report handler (§5.4 step 3) passed in code that
  raises `RuntimeError("secret /Users/x/path")` when it receives the analyzer's `cards` report,
  with a fake analyzer that sleeps after printing that report. **The seam was corrected at
  round 3:** it used to be "a stage function at the `cards` stage", but that stage runs inside the
  analyzer subprocess, where a raise is only a non-zero exit; the report handler runs on the job
  thread. The analyzer's process group is gone before the item shows `failed` (round 3; the
  catch-all's first step), the item is `failed` with
  `internal_error` and `detail.stage = "cards"`, persisted under the lock; stderr's job line names
  `RuntimeError` and does not contain the message's text; no item is `running`; the next waiting
  item starts; and with none waiting the idle predicate turns true once the idle period passes.
  If the failure's own write is made to fail as well (D10's writer), memory still records the
  failure and `busy` is still false. An exception raised in the runner loop outside any item
  pauses the runner (§5.4) and is written to stderr the same way.

**E. Progress** (`test_analyze_options.py` and `test_ledger_jobs.py`; `test_analyze.py` stays
unchanged, §1.1)
- E1. `--progress` prints exactly the four lines, in order, and stdout is byte-identical without
  it. Each line arrives as its stage ends: with a `git` wrapper first on `PATH` that delays
  `for-each-ref` by 2 s, the `worktrees` line is read at least 1.5 s before exit.
- E2. **"Unchanged", as a differential.** The baseline is blob
  `8b805d1f826cae5c22fdcb23de3a57e56049a734` (`git rev-parse 5f194df:treko/analyze.py`; last
  changed in `7028052`). It is materialized with `git cat-file -p`, beside a `hooks/lib` link as
  `build_tree` does (`server_harness.py:85-107`). Baseline and new analyzer run without `--progress`
  and without `--card` (OQ-1, (my call): one test covers both options) over three fixtures: a
  repo with worktrees, a depends-on chain, a cycle and a spec half; a directory that is not a repo
  (the exit-1 path); and a card with an id-less task. Fixtures commit
  with fixed dates, so git's relative times match. stdout, stderr and exit status must be equal
  byte for byte, both plain and with `--pretty`. Every E2 fixture's `git status` succeeds in each
  worktree, which is the scope §6.3 keeps byte-identical (round 3). A falsifier runs the same comparison on a copy
  with one default-path byte changed and must see it fail. Both analyzers run under the pinned
  runtime interpreter, `/usr/bin/python3` (3.9.6), not the test runner's (§15). That makes E2
  also split 1's proof (§1.1).
- E3. Between two progress reports, repeated polls return the same `stage`. The node slice's bar
  width is a pure function of `stage` alone.
- E4. `total` is `null` until the scan ends, then `4N + 3`. A failed family's remaining stages
  count as done.
- E5. `--card` (OQ-1, (my call)). Given every default card path of a fixture, stdout is
  byte-identical to a run without it. Given a subset, `features[]` holds exactly that subset,
  ordered by file name. A copy from another worktree is compared with its own spec half
  (`_ask_about_spec_half`, `analyze.py:573-582`).
- E6. **A failing `git status` shows "changes unknown" (U6, round 3), in `test_analyze_options.py`.**
  The fixture is a repo with two branches, one checked out in a second worktree whose index file
  is overwritten with junk, so `git status --porcelain` there exits 128 (`probe_r3.sh` row S1).
  The new analyzer, run plainly: that branch has `dirty: false`, `note: "changes unknown"`,
  `tone: "neutral"`, and the same `ahead`, `behind` and `last` as the baseline gives; the run has
  exactly one more question than the baseline's, naming that worktree, with git's message in its
  context; every other branch, feature and section equals the baseline's output byte for byte.
  The fixture asserts its own precondition first: `git status` in that worktree really exits
  non-zero. **Falsifier:** the same assertions run against the baseline analyzer (blob
  `8b805d1…`, as in E2) must fail, because it reports that branch as `"clean"` with tone `"ok"`
  and no question (measured: `probe_r3.sh` row S2). And with the index restored, the new and
  baseline analyzers agree byte for byte, which is E2's guarantee on this fixture.

**F. Merge** (`test_ledger_merge.py`)
- F1. Identity on one family (§7.3).
- F2. Two and three families: unique ids, remapped edges, no overlapping node boxes, waves merged
  by index with the cycle waves last, and the schema property. `CYCLE_NOTE` equals the note the
  real analyzer emits for a cycle fixture.
- F3. Colliding folder names (OQ-3, (my call)). When two families share a folder name, both are
  labelled by their home-collapsed paths in `tasks[].repo`, `branches[].repo` and the kanban `m`
  prefix, and every card name is unchanged. Without a collision, labels stay folder names.

**G. Runs, ids, Delete** (`test_ledger_state.py`)
- G1. Ids: one folder typed as `~/x`, `/abs/x` and through a symlink gives one id. `~/dev/foo` and
  `~/work/foo` give two. Every narrowing changes the id.
- G2. Re-analysis replaces in place, and every other run is byte-identical (old criterion 4's
  shape).
- G3. Delete: hidden in status and in `GET /tracker-data.js`, the store's bytes unchanged,
  un-hidden by a successful re-analysis and not by a failed one. With an empty hide list,
  `GET /tracker-data.js` is byte-identical to the file.
- G4. Row fields from fixture runs, including a `?/?` card, a `—` worktree and an empty run.
- G5. `last_run` (the spec call the user confirmed on 2026-11-03).
- G6. OQ-7 (my call): Re-analyze of a run with no recorded request queues its directory, `~`
  expanded, with no narrowing. The result lands under the D12 id, and the old run's bytes in the
  store are unchanged.
- G7. Re-analyze re-runs the submit-time path (§3.4). A run whose recorded directory has been
  deleted gets `422 no_such_directory`. A run whose narrowing worktree has been removed with
  `git worktree remove` gets `422 no_such_worktree`. In both, `ledger.json` is byte-identical
  before and after. `analyze` with a `worktree` that no found repository has also gets
  `422 no_such_worktree`.

**H. Pages** (`test_ledger_page.py`: node slice plus CDP on the pinned Chrome; set
`TREKO_CHROME_DENY_BIRD=1` on this machine, as `treko-degraded-no-cmux.md` records)
- H1. Slice: every §9.2 row, an unknown code, and a hostile `error` string such as `"constructor"`
  or markup all reach fixed strings only. O2: each code's message is built from a `detail` with
  every part present, and again with each part `null`, and an unknown stage key is left out.
  Round 2: the `runsError` message contains the response's `storeDir` as text and does not
  contain the word "log" (F5, §9.2).
- H2. Served: form, queue and rows render from a seeded store. Analyze on an empty folder shows the
  pop-up with the exact D2 wording and queues nothing. Analyze with a Branch that no card names
  shows the "No card matches that branch or worktree." pop-up and queues nothing (OQ-4).
- H3. `file://`: §9.3, with zero `tracker-data*.js` requests observed.
- H4. Board icons: `/ledger` when served, `Ledger.dc.html` over `file://` (U1).
- H5. Open and Open the board land on `/`, the board, showing that run (U1).
- H6. Re-analyze posts to `/ledger` and never to `/command`. After a `200` the browser is at
  `/ledger` (OQ-5; U1). The transport lives in `board-commands.js` after split 3.
- H7. On a merged two-family run, the board's svg box contains every node box.
- H8. D8: the store directory is text, and the DOM has no input or Save for it.
- H9. The Ledger's token block equals the board's byte for byte.
- H10. On the board at `/`, a Re-analyze answered `no_such_directory` or `no_such_worktree` shows
  the §9.4 pop-up word for word, keeps the browser at `/`, and sends nothing to `/command`. The
  slice test stubs the fetch; the CDP test uses a really deleted directory.
- H11. **Every code has a message, checked both ways (round 2, F6).** Two halves, both mechanical,
  neither hand-listed. (1) Code: the set of `error` values `ledger_routes` can answer with, plus
  `ledger_jobs`'s job failure codes, each read from the module's own constants, equals the set of
  codes the Ledger slice's message table maps, in both directions. (2) This spec: the backticked
  lower-case codes in the `error` column of §3.5's first table, the first column of its second
  table, and the codes after "failed item:" in §5.4's "Job failure codes" sentence, equal the
  backticked lower-case codes in the first column of §9.2's table, leaving out the `200` row,
  whose `started` is a field and not a code; in both directions. The test reads this file between
  those headings. Each half has a falsifier: a message key deleted, and a code added to one list
  only. **Measured on this revision** with a scratch script doing exactly that
  (`h11_spec_half.py` in the round-2 scratch folder): 28 codes on each side, no difference. On
  the spec as it stood before round 2 the same script exits 1 and names 11 codes with no row: the
  six of §9.2's F6 note, `method_not_allowed`, and four (`forbidden`, `malformed`, `too_large`,
  `unsupported_media_type`) that were covered only by status number.

**Z. Whole-card checks**
- Z1. **The pinned runtime interpreter.** One test in `test_ledger_jobs.py` launches `server.py`
  with `/usr/bin/python3`, through a new `interpreter` parameter of `server_harness.launch`. It
  is passed in code, and its default stays `sys.executable` (`server_harness.py:296`). The test
  first asserts that `/usr/bin/python3 -V` prints `Python 3.9.6`. It then runs one two-family
  `analyze` job end to end and checks the run in the store against §7.3's schema property. The
  server starts the scan and every analyzer with its own `sys.executable` (§4, §5.4), so this one
  test runs the server, all five `ledger_*` modules, `cards.py` and `analyze.py` on 3.9.6,
  whatever interpreter pytest itself runs on.
- Z2. **File sizes.** A new `test_file_budgets.py` holds §1.1's table and fails when any listed
  file exceeds its budget, or when any file this card creates or changes exceeds 800 lines by
  `wc -l`. The card's own two documents are left out: ADR 0017 governs them, and the user
  accepted this half's overrun on 2026-11-03. "Changes" is measured, not listed: the files in
  `git diff --name-only origin/main...HEAD -- treko skills/treko docs/decisions`. The path
  filter leaves out the card's two documents and the shared judge ledgers under `coding-memory/`,
  which every judged card appends to (307 and 399 lines at `d85eabd`, by `wc -l`), so they are
  no card's files. **Can pass since round 2:** the two files in
  `treko/` over 800 lines, `test_nontext_contrast.py` (1054) and `support.js` (1911), are not on
  §12's list, and with the board kept at `/` (U1) nothing in this card edits them (§1.1).
- Z3. **The splits change nothing.** At each split's own commit (§1.1), the existing suite passes,
  and the only test edits allowed in that commit are the ones the split forces. For splits 1
  and 2 there are none. For split 1, E2 passes too. **For split 3, exactly these, measured by
  simulation (§1.1) and nothing else:**
  1. `test_ui_commands.py:38`: `HTML` points at `board-commands.js` instead of `Treko.dc.html`.
     The node loader cuts the same marker-delimited slice from it.
  2. `test_guards.py`: a `BOARD_COMMANDS_PATH` beside `HTML_PATH` (`:108`); criterion 15's four
     tests (`:193`, `:208`, `:252`, `:272`) read it instead of the page, and the pinned
     `BASE_FENCE_SHA256` and `BASE_FENCE_BYTES` (`:130-131`) are unchanged, because they still
     match.
  3. `test_guards.py`: criterion 16's id extraction (`:337`) and its falsifier test (`:383-384`)
     read `board-commands.js`, where `var TRACKER_COMMAND_IDS` now lives
     (`Treko.dc.html:410` today, inside the slice).
  4. `test_guards.py`: the two tests that use `CMD_BUTTONS_RE` (`:308`; tests at `:342` and
     `:422`) read `board-commands.js` followed by the page, in that order. The regex spans both:
     `function trackerLiveIds` (`Treko.dc.html:453`) moves with the slice, while
     `const liveIds=trackerLiveIds(…)`, `buttonIds` and `cmdButtons:` (`:611`, `:614`, `:619`)
     stay in the page, so it matches neither file alone. The board loads `board-commands.js` as
     a head script, before the page's component code, so that order is the load order.
     `CMD_COPIES_RE` (`:315`) still matches the page alone.
  5. `test_guards.py:560`: `EXPECTED_MANIFEST_ROWS` 17 → 18. Without it,
     `test_criterion17_static_manifest_row_count` fails, and so does
     `test_criterion17_static_manifest_falsifiers_are_caught` (`:595`), whose one-row-short
     falsifier then has 17 rows and matches.

  Nothing else changes at split 3: no assertion, no other constant, no other module.

**I. Docs.** `skills/treko/SKILL.md` describes the Ledger, the routes, `ledger.json` and the lock
file in "Where the survey is stored", the new startup aborts, and drops "`reanalyze` … is the only
thing that writes `tracker-data.js`". Its launch paragraph says first launch with an empty store
queues the launch repo on the Ledger rather than analyzing it before the browser opens (OQ-6).
Since round 2 (U1): the auto-opened tab (`SKILL.md:89-90`) is `http://127.0.0.1:8422/ledger`, the
board stays at `http://127.0.0.1:8422/`, and the board's Treko icon returns to the Ledger. The
banner example at `SKILL.md:66` is unchanged, because the banner is (§3.2).
`test_autolaunch.py:401` (`test_the_skill_documents_a_launch_command_that_does_not_detach`) reads
every `SKILL.md` line naming `server.py`; the edit must keep those lines free of `nohup`,
`setsid`, a stderr redirect and a trailing `&`.

## 12. Existing tests this changes (decided here, so no task discovers it)

**How this list was derived (rewritten at round 2, F1).** Round 1's list named one root-URL load
and called itself complete; compliance round 2 counted 22 such lines in five modules, four of them
outside §15's suite command. This list covers **all 16 test modules** (`ls treko/test_*.py | wc
-l`) plus `server_harness.py`, `cdp_harness.py` and `conftest.py`, by two methods:

1. **Greps for everything the card changes**, each re-runnable:
   - root-URL loads: `grep -n -F '127.0.0.1:%d/"' treko/test_*.py` (22 lines: `test_sidebar.py`
     7, `test_drawer.py` 5, `test_drawer_sections.py` 5, `test_theme.py` 4,
     `test_nontext_contrast.py` 1) and `grep -n -E "get\(['\"]/['\"]" treko/test_*.py
     treko/server_harness.py` (`test_degraded.py:353`, `test_server.py:224` and `:297`,
     `test_server_lifetime.py:115`, `server_harness.py:164` and `:317`, and `test_autolaunch.py:188`);
   - changed symbols, one at a time: `grep -c -E -- '<pattern>' treko/test_*.py
     treko/server_harness.py treko/cdp_harness.py treko/conftest.py | grep -v ':0$'` for
     `reanalyze`, `run_reanalyze`, `HANGING_ANALYZER`, `shouldReload`, `LOCAL_COMMANDS`,
     `send_keys|confirm_surface|CONFIRM_REFUSAL_REASONS`,
     `_card_paths|_parse_frontmatter|_checklist|_depends_on|_normalize_target|analyzer\.Card`,
     `width="700"|height="260"`, `webbrowser|BROWSER`;
   - page-text readers: `grep -n -E 'Treko\.dc\.html|INDEX_FILE' treko/test_*.py`.
2. **A simulation of split 3 and the two icon links** in a scratch export, with the result in
   §1.1: which tests a mechanical change actually breaks, rather than which a grep suggests.

**Under U1 no root-URL load changes.** All 22 lines, and every `GET /` above, expect the board,
and the board stays at `/`. Until round 2 every one of them had to move to `/board`.

**Changed** (each module's size is in §1.1; each stays ≤ 800):

- `test_server.py` (789). Tests that use `reanalyze` as the cmux-free command (18 matching lines,
  `grep -c reanalyze treko/test_server.py`) move to a Ledger job or to `clear` with the fake
  cmux; the bullets below name each one.
  - `REASON_STATUS` (`:56-74`) loses `"reanalyze_failed": 500` (`:69`).
    `test_the_enum_and_the_status_table_cover_each_other` (`:771`) compares it with
    `reasons_emitted_in_source()` (`:756-768`), which scans `server.py`'s text, and that reason
    leaves `server.py` with `run_reanalyze`. `/ledger`'s reasons live in `ledger_routes.py`, which
    that scan does not read; criterion A2 covers them. `CONTRACT_STATUSES` (`:78`) still holds,
    because `asset_unreadable` keeps the 500.
  - `test_the_token_never_leaves_the_served_page` (`:290`): its `reanalyze` precondition
    (`:300-302`) becomes "a Ledger job completed". Its clause (3) (`:319-326`) asserts `"env="`
    appears in neither `server.py` nor `channel.py`, under a comment that a child's environment
    is the server's verbatim. Ledger children get the built environment of §2 default 3, so the
    comment is rewritten and the clause also checks the builder's output for the token.
    **Watch:** the plain substring check would also trip on any keyword argument ending in `env`
    (`base_env=`) in `server.py`, so the builder's argument is passed positionally there, or the
    clause is narrowed; either way in this same edit.
  - `test_reanalyze_succeeds_without_invoking_cmux_at_all` (`:445`) becomes the `/command` half of
    criterion A4: `{"id": "reanalyze"}` gets `403 unknown_id`, and the fake cmux log is unchanged.
  - `test_a_hanging_analyzer_times_out_and_leaves_the_store_intact` (`:732`) moves to
    `test_ledger_jobs.py`: a one-family job whose analyzer is `HANGING_ANALYZER`
    (`server_harness.py:76`) is killed at `ANALYZE_SECS`, the item fails `analysis_failed` with
    `timedOut`, and the store's bytes are unchanged.
  - The module docstring's "the `reanalyze` timeout" (`:7`) is updated.
  - Unchanged here: both `GET /` loads (`:224`, `:297`); the manifest test (`:105`), which is
    parametrized over `server.STATIC_MANIFEST` and so covers `board-commands.js` with no edit;
    the off-manifest list (`:361-368`), which names no new path; `server.CONFIRM_REFUSAL_REASONS`,
    which still resolves after split 2 through the import back. New tests go in the new modules.
- `test_guards.py` (599): Z3's edits 2 to 5 at split 3's commit. (`EXPECTED_MANIFEST_ROWS`: the
  first draft said it stays 17, which holds for the Ledger page alone, since that page adds no
  row. Split 3 adds `board-commands.js`, so the constant becomes 18.) Then, in the Re-analyze task: the
  fence pins are re-pinned deliberately with the new figures recorded: both pairs, since the
  slice change moves both spans: `BASE_FENCE_BYTES` and `BASE_FENCE_SHA256` (`:130-131`; 6692
  bytes, `bfe17645…`), and, added at round 3, `BASE_FENCE_NODE_BRIDGE_BYTES` and
  `BASE_FENCE_NODE_BRIDGE_SHA256` (`:136-137`; 6569 bytes, `4f1f1179…`), the marker-exclusive
  span `test_ui_commands.py`'s loader actually loads. The slice's own comment about living in the
  page is corrected, and so (round 3) is `test_ui_commands.py`'s module docstring (`:9-16`), which
  gives the same reason: "It cannot live in a `.js` file of its own". **(spec call)** In the same task, criterion 17's external-fetch scan
  (`:496-498`) also reads `board-commands.js`: after split 3 it reads only the page and would no
  longer see the slice. The manifest falsifier's two messages (`:598-599`, "18-row" and "16-row")
  are corrected to 19 and 17 rows; their assertions already pass at 18. `EXPECTED_COMMAND_IDS`
  (`:318`) is unchanged: `TRACKER_COMMAND_IDS` keeps all three ids, because the Re-analyze button
  stays and only its transport moves.
- `test_ui_commands.py` (468): Z3's edit 1 at split 3. Then, with the Re-analyze change, which
  after a `200` now goes to `/ledger` instead of reloading (OQ-5; U1), and whose outcome table is
  §9.4:
  - `ROW_OUTCOMES` (`:43-53`) loses `"analysis_failed"` (`:48`, "500 reanalyze_failed"), and
    `test_500_leaves_the_displayed_analyzed_at_byte_identical` (`:288`) retires with old
    criterion 15's `500` row, which no server path can produce once `reanalyze` leaves
    `/command`. Without both, `test_zz_every_table_row_was_driven_by_a_real_response` (`:460`)
    fails.
  - `test_the_page_partition_matches_the_servers` (`:377-384`) compares the page's local ids with
    `server.LOCAL_COMMANDS` (`:383`), which goes with `run_reanalyze`. **(spec call)** It becomes:
    the page's send ids equal `server.SEND_COMMANDS` and `server.ALLOWED_IDS`, and the page's
    local ids are exactly `["reanalyze"]` (`var TRACKER_LOCAL_IDS=['reanalyze'];`,
    `Treko.dc.html:413`), which is not in `server.ALLOWED_IDS`, because it posts to `/ledger`.
  - Re-analyze's §9.4 outcome table gets its slice tests here (criteria H6 and H10's slice half).
  - Unchanged: `test_the_handler_slice_is_fenced_exactly_once_and_loads_standalone` (`:227`,
    the three ids) and `test_live_ids_resolve_for_all_four_token_and_channel_combinations`
    (`:356`), since `TRACKER_LOCAL_IDS` stays `['reanalyze']`: Re-analyze still needs no channel.
- `test_degraded.py` (620): `test_reanalyze_still_succeeds_on_a_degraded_server` (`:519-527`)
  sends `{"id": "reanalyze"}` to `/command`, which becomes `403`. It becomes: on a degraded
  server, `POST /ledger {"op": "reanalyze", …}` queues the run, since `/ledger` needs no channel.
  The unreadable-index abort test (`:415-421`) is unchanged: the board's file and message are as
  today, and the Ledger's file gets its own check in criterion A1's module.
- `test_store_writer.py` (78): `test_reanalyze_writes_the_configured_store_and_never_the_tree`
  (`:47`) sends `reanalyze` to `/command` (`:67`). It becomes a Ledger job that writes the
  configured store and never the tree. The module docstring (`:1-22`), which names
  `run_reanalyze`, is rewritten.
- `test_autolaunch.py` (418): `test_no_path_launch_analyzes_the_repo_root_once` (`:256-265`)
  reads the store as soon as the server serves (`:262-263`). With OQ-6 (user) the launch queues
  a job instead, so the test waits for that job to finish, then checks one run under a D12 id
  (criterion D8). `test_existing_run_is_not_reanalyzed_on_launch` (`:284`) keeps its meaning.
  `test_no_path_launch_opens_the_browser_at_the_bound_url` (`:268-276`) passes unchanged, since
  it checks a substring; criterion D8 adds the exact `/ledger` path.
- `server_harness.py` (339): `launch` gains an `interpreter` parameter, defaulting to
  `sys.executable` (Z1). The docstring and comment that name `reanalyze` (`:14`, `:263`) are
  updated. `srv.token` (`:164`) and the readiness probe (`:317`) still `GET /` and still get the
  board: no change there.

**Unchanged, by measurement:**

- `test_theme.py` (all four root loads, `:523` included), `test_nontext_contrast.py` (`:405`),
  `test_sidebar.py`, `test_drawer.py`, `test_drawer_sections.py`: they load or read the board at
  `/`, which stays, and they passed unchanged on the scratch export with split 3 and the two icon
  links applied (§1.1). The links there were a literal `href="/ledger"`, not the
  `{{ ledgerHref }}` binding; criterion H4 covers the binding.
- `test_rename.py`: passed on the same export. Its check at `:165` reads `analyze.py` for
  Rally-shaped fields, and after split 1 it does not read `cards.py`; the card layer emits no
  run field, so it still guards what it was written for.
- `test_server_lifetime.py`: the banner prefix (`:209`) is unchanged (§3.2); its second-server
  test (`:100-113`) reuses the first server's port, so the bind fails before §5.1's lock is
  taken, and the message is today's.
- `test_analyze.py`: unchanged (§1.1). The analyzer's new tests (E1, E2, E5) go in a new
  `test_analyze_options.py`. It reaches the analyzer only through `analyzer.analyze` (26 uses,
  `grep -o 'analyzer\.[A-Za-z_]*' treko/test_analyze.py | sort | uniq -c`).
- `test_store.py`, `test_store_location.py`, `cdp_harness.py`, `conftest.py`: no match for any
  pattern above except one docstring mention of `Treko.dc.html` (`cdp_harness.py:9`).

**Not simulated:** splits 1 and 2 (the existing suite, and E2 for split 1, prove them at their own
commits, Z3), and every behavioural change in this list. Those are derived from the greps and from
reading each named test.

## 13. Security delta

`server.py` remains the whole trust boundary. What this card adds:

- **The page can make the server read any directory the user can read**, and show what it finds:
  repo, card and branch names and paths. The token limits this to pages the server itself served.
  Inputs are validated before any syscall (§3.4). Reads are bounded in depth and time (§4). The
  server writes only inside the store directory: the store, `ledger.json`, the lock. **And git
  writes nothing in a scanned repository (round 2, F3).** Until round 2 that sentence was untrue:
  with only `core.fsmonitor` off, a real analyzer run rewrote the index of the repo and of its
  worktree, because the analyzer runs `git status --porcelain` in each worktree
  (`analyze.py:437`), and that rewrite fired a repo-set hook (probes 12 and 13, §2). With the
  round-2 settings of §2 default 3, the same run left every file under `.git` identical in content
  and mtime (probe 14). That covers the analyzer's git commands on that fixture; criterion C9 makes it
  a test. **Round 3 found one more write:** under the round-2 settings a partial clone's lazy
  fetch downloaded objects into the scanned repository's `.git` (probe 26); `GIT_NO_LAZY_FETCH=1`
  stops it (probe 25, C11). The scan's own git calls are `rev-parse` and `worktree list` (§4.1),
  and they run with the same protective settings. That they write nothing is reasoned, not
  measured, since the scan does not exist yet; C9's whole-job check covers them once it does.
  **Not covered:** a file filter, if task 1 leaves filters on, and any config route not yet tried
  (next bullet).
- **Git runs in repositories the user did not explicitly name.** `core.fsmonitor`, repo-named
  hooks, the optional index write, `gpg.program` through `log.showSignature`, and a promisor lazy
  fetch are off, unconditionally and measured (§2, C8–C11; the last two since round 3, U4).
  **What was tried, and what was not (rewritten at round 3, U4).** The config routes tried are
  fsmonitor, hooks, `gpg.program`/`log.showSignature`, the lazy fetch, `diff.external` and
  `diff.<driver>.textconv` (neither runs on the analyzer's `git diff --shortstat`), and file
  filters (§2 default 3, probes 1–33). Git's other config keys that can name a program have
  **not** been enumerated, so the routes closed are a lower bound, and a scanned repository with
  a hostile `.git/config` may still have one this card does not know of. Until round 3 this
  bullet said "Other config-driven programs: OQ-8, answered", which overclaimed: OQ-8 covered
  hooks and filters only. Config the server's own environment carries cannot re-enable the routes
  that are closed: the builder drops `GIT_CONFIG_PARAMETERS` and the `GIT_CONFIG_COUNT` family
  (§2, C8). File filters: task 1 tests switching them off on a real LFS repository and the user
  decides from the result (D15/U3, §2 default 3); until then, and if `git-lfs` cannot be
  installed (U5), they are the accepted risk the ADR records (user). LFS repositories are never
  skipped (user).
- **Nothing new reaches the session.** `/command` shrinks. `/ledger` never invokes cmux (A5).
- **Unchanged:** the token's lifetime and handling, the collapsed `403`, no CORS headers, the CSP,
  `frame-ancestors 'none'`, the `Host` guard, failure bodies that echo nothing, one audit line per
  request (apart from an accepted status poll since round 1: §2, default 4), and the parent-death
  check.
- **Rendering:** status data and run data come partly from scanned repositories, which may be
  hostile, and both pages render them as text only (§9.2, H1).

## 14. Non-goals

Carried from the card: PR data, branch ancestry and `## Depends on` traversal (card 5); sub-tasks,
`parent:`, spec and ADR links, `blocked-by:` and cross-repo dependencies (the relations card); an
LLM doing the analysis; the Configuration drawer (card 3, `treko-store-location.md:88-92`); a
working Save for the store path (D8). Also out: any new board data field (D9), and changing where
the store lives. Launching `server.py` outside a repository still aborts as today
(`resolve_repo`, `server.py:212-235`); the card does not ask to change it.
Recorded at round 2, not built: **stopping a running job** (D4 lets a waiting item be removed and
nothing more; a running one ends only by finishing, failing, or the server stopping), and **a cap
on repositories per job** (only the queue is capped, `MAX_QUEUE_ITEMS`). Both are risks in §16.

## 15. Pinned versions

Measured on this host 2026-11-03.

| Tool | Version | Re-read with |
|---|---|---|
| Python | 3.9.6 | `python3 -V`. Stdlib only: no `match`, no `X \| Y` annotations |
| Python, runtime (round 1) | 3.9.6 at `/usr/bin/python3` (the Command Line Tools interpreter) | `/usr/bin/python3 -V`. The skill launches `server.py` with it, so the server, the scan and every analyzer run on it. Z1 and E2 run on it |
| Python, test runner | **3.11.15**, uv's own managed CPython, pinned with `--python 3.11.15` **(user, 2026-11-03)**; unpinned at round 1 | `uv run --python 3.11.15 --no-project python -V`; see "The test runner's interpreter" below |
| pytest | 9.1.1 | `uv run --python 3.11.15 --with pytest==9.1.1 --no-project pytest --version` |
| uv | 0.11.28 | `uv --version` |
| node | v26.5.0 | `node --version` (the slice tests) |
| git | 2.50.1 (Apple Git-155) | `git --version`. Needs 2.45 or later: 2.31 for `GIT_CONFIG_COUNT` and `--path-format`, and, since round 3, 2.45 for `GIT_NO_LAZY_FETCH`, whose earliest release notes are 2.45.0's (§2 default 3). This host's 2.50.1 honours it (probes 23, 25) |
| git-lfs, **test-only** (round 3, U5) | 3.8.1, from Homebrew | Not installed today (`command -v git-lfs` finds nothing). Task 1 installs it, only with the user's approval at the permission prompt, then re-reads it with `git lfs version`. Vetted 2026-11-03: 0 stop, 0 caution, and incomplete, since all eight checks are `not_run` for Homebrew (`~/.claude/hooks/state/vetting/homebrew/git-lfs/3.8.1.md`). Nothing at runtime uses it |
| Chrome | 156.0.8078.79 | `cdp_harness.PINNED_VERSION` (`cdp_harness.py:78`) |
| Nocturne export | `73641b21-c7ad-488a-8264-a28262dfe83e`, schema `version: 1` | the `_ds/` directory name; ADR 0023 |
| Phosphor | 2.1.1, vendored | `treko/vendor/phosphor/` |

No new runtime dependency: the server, the scan and the analyzer use the standard library and
git only. One **test-only tool** is new, `git-lfs` 3.8.1 (the row above), installed in task 1 only,
and only if the user approves it at the permission prompt; if he refuses or the install fails,
task 1 takes §2 default 3's third outcome and file filters stay the accepted risk (U5; reworded at
round 3 from "No new dependency."). Run the card's suite with
`TREKO_CHROME_DENY_BIRD=1 uv run --python 3.11.15 --with pytest==9.1.1 --no-project pytest treko -q`:
the whole directory, every existing module and every new one.
**(spec call, round 2, F1)** Until round 2 the command named a list: `treko/test_ledger_*.py
treko/test_analyze.py treko/test_server.py treko/test_ui_commands.py treko/test_guards.py`, to
which round 1 added `treko/test_analyze_options.py`, `treko/test_file_budgets.py`,
`treko/test_autolaunch.py`, `treko/test_degraded.py`, `treko/test_store_writer.py` and
`treko/test_theme.py`. Four modules that load the board (`test_sidebar.py`, `test_drawer.py`,
`test_drawer_sections.py`, `test_nontext_contrast.py`) were outside it, so a builder could see
green while they broke, and split 3 and the icon links change the page all four load. A list has
to be kept in step with §12 by hand; the directory cannot fall out of step, and new modules join
it by living in `treko/` as `test_*.py`. Measured at `d85eabd` on this host: the command passes
360 tests in 226 s, with nothing skipped or deselected (there is no `pytest.ini`,
`pyproject.toml`, `setup.cfg` or `tox.ini` at the root or in `treko/`, and `treko/conftest.py`
sets no `addopts` or collection hook).

**The test runner's interpreter (measured 2026-11-03, round 1).** The command above does not run
on the pinned 3.9.6. Output follows, with the home directory shown as `~`:

```
$ uv run --with pytest==9.1.1 --no-project python -c "import sys, pytest; print(sys.executable); print(sys.version.split()[0]); print('pytest', pytest.__version__)"
~/.cache/uv/builds-v0/.tmpOflwHJ/bin/python
3.11.15
pytest 9.1.1

$ uv run --with pytest==9.1.1 --no-project --python /usr/bin/python3 --no-python-downloads pytest --version
  × No solution found when resolving `--with` dependencies:
  ╰─▶ Because the current Python version (3.9.6) does not satisfy Python>=3.10
      and pytest==9.1.1 depends on Python>=3.10, we can conclude that
      pytest==9.1.1 cannot be used.
      And because you require pytest==9.1.1, we can conclude that your
      requirements are unsatisfiable.
exit=1
```

`--python 3.9.6 --no-python-downloads` gives the same refusal. `uv python find` names
`~/.local/share/uv/python/cpython-3.11-macos-aarch64-none/bin/python3.11`. So, before the pin
below, the suite ran on whatever uv's default was, and pytest 9.1.1 cannot run on 3.9.6 at all. **No dependency version was
changed.**

**Answered (user, 2026-11-03): option (a).** The runner is pinned to `--python 3.11.15` in the table
and the suite command above; pytest stays 9.1.1 and the runtime stays 3.9.6, proven by Z1 and E2.
No dependency changed. The options as they were put to him:

- (a) Pin the runner explicitly to that 3.11.15 with `--python 3.11.15`, keeping pytest 9.1.1
  and the runtime at 3.9.6.
- (b) Move pytest to a release that still supports 3.9 and run everything on 3.9.6. That is a
  dependency change and needs the vetting gate.
- (c) Move the runtime to 3.11, which changes the skill's launch command.

**Recommended: (a).** It changes nothing that runs today, it makes the runner reproducible, and Z1
and E2 already prove the code on 3.9.6. Until the choice was made, Z1 and E2 were what tied this
suite to the runtime pin; they still are what prove the code on it.

## 16. Risks

- **Typing `~`.** Even with hidden folders skipped, depth 5 reaches `~/Documents`, `~/Desktop` and
  `~/Downloads`. macOS may ask the terminal app for folder access the first time. Not measured:
  probing it would raise the prompt. A large home folder may hit `TREKO_SCAN_SECS`, which then
  gives a clear failure rather than a hang.
- **Card 5's line citations into `analyze.py`** shift (§6.1), and so do its `Treko.dc.html` ones
  after split 3 (§1.1).
- **Two pages share strings.** The board copies only five of the Ledger's messages (§9.4) to keep
  the drift surface small.
- **The Ledger's contrast is unguarded.** `test_theme.py` and `test_nontext_contrast.py` score the
  board only.
- **The card's `.md` half is over ADR 0017's 200-line cap** (`wc -l docs/features/treko-ledger.md`).
  That is pre-existing, and for the reviewer.
- **O1 covers runs, not the nothing-found pop-up.** A refusal body carries only its code (§3.5),
  and D2 fixed the pop-up's wording. So when the scan finds nothing at all, a repository below
  the depth limit is not reported. Once anything is found, the run's question reports it (§7.2).
- **File filters (OQ-8, user; D15/U3).** If task 1 cannot switch them off without breaking
  LFS-backed scanning, a scanned repository's own config can still name a filter program that
  `git status` runs. The user accepted that risk; task 1 now tests the off switch on a real LFS
  repository and shows him the result (§2 default 3), and its ADR records whichever outcome holds.
  `git-lfs` is not installed on this host (`command -v git-lfs` finds nothing). Since round 3
  (U5) it is pinned as a test-only tool, Homebrew 3.8.1 (§15), installed in task 1 only with his
  approval at the permission prompt; if he refuses or the install fails, the test does not run
  and filters stay this accepted risk (§2 default 3, third outcome).
- **Config routes not yet tried (round 3, U4).** The config routes tried are fsmonitor, hooks,
  `gpg.program`/`log.showSignature`, the lazy fetch, `diff.external`, `diff.<driver>.textconv`
  and file filters (§2 default 3, "Which config routes were tried"); all but filters are closed
  or did not fire on the analyzer's commands. Git's other config keys that can name a program
  were not enumerated. A scanned repository whose `.git/config` is hostile, such as an unpacked
  archive, may still name a program through one of them (a plain `git clone` does not carry the
  source's `.git/config`, per the compliance judge's round-3 note; not measured here). Each review
  round so far has found more routes, so this is a known gap, not a closed list.
- **A running job cannot be stopped (round 2).** Only waiting items can be removed (D4). A job
  ends by finishing, failing, or the server stopping, which marks it interrupted.
- **Job length is uncapped in repositories (round 2).** Each family gets `ANALYZE_SECS` (default
  read by `read_timeout`, `server.py:153-168`), and the number of families a scan finds has no
  cap, so a job can run for N × that bound, with N whatever the directory holds. The queue is
  capped (`MAX_QUEUE_ITEMS`); a job's width is not.
- **The depth-5 count will likely raise its question on every scan of `~` (round 2; reasoned,
  not measured).** §4.1 leaves hidden folders and `node_modules` uncounted so that the "Were
  repositories missed?" question does not appear on every `~` scan, but it does count every
  depth-5 folder that is not a repository, and a home folder almost certainly has some. Not
  measured, because scanning `~` here would raise macOS folder-access prompts (the first risk
  above). If it proves noisy, the wording or the count changes in review; the count itself is
  what keeps a depth-6 repository from being silently absent.

## Open questions — resolved 2026-11-03

Each has a recommendation. Where the spec above depends on one, it describes the recommended
answer. All eight were answered on 2026-11-03. Each answer follows its question with its tag,
**(user)** or **(my call)**, and names the places in this file it changed.

1. **OQ-1 — D11 contradicts the analyzer correction.** The correction allows `analyze.py` "one
   small optional progress report and nothing else". D11 needs it to read card copies from
   several worktrees, and `_card_paths` reads one folder (`analyze.py:192-198`). The other routes
   are re-implementing `analyze()`'s assembly in a new module, or patching its private
   `_card_paths` at run time. **Recommend:** allow a second optional input, `--card PATH`
   (§4.3), under the same byte-for-byte test (E2). It is the only route with no duplicate logic,
   and Branch/Worktree narrowing rides on it for free. Also confirm §4.3's reading: when copies
   disagree about `branch:`, the copy sitting in its own branch's worktree wins.

   **Answer (my call), 2026-11-03; the user was told.** Allow the second optional input,
   `--card PATH`. It falls under the same byte-for-byte "unchanged without the options" test as
   the progress report (E2), and E5 checks the option itself. Places changed: §1's file table,
   §4.3, §5.4 step 3, §6.1, criteria E2 and E5. **Not covered by this answer:** the confirmation
   asked for above, of §4.3's per-copy reading of D11. That reading stays a (spec call).
   Settled as **(my call)**, 2026-11-03: it is the reading that serves D11's stated purpose, the
   live copy.
2. **OQ-2 — one repo fails in a multi-repo job.** **Recommend:** write the run without it, plus a
   question naming the failure, and fail the job only when every repo fails. That is the
   analyzer's own "degrade, never die mid-repo" rule. The alternative fails the whole job, so one
   broken repo blocks a directory's survey.

   **Answer (user), 2026-11-03.** Keep the run with the repos that worked, plus a visible question
   naming the repo that failed and why. The job fails only if every repo fails. Places changed:
   §5.4 step 3, §7.1, §7.2, a new scenario, criterion D7.
3. **OQ-3 — telling repos apart in one run.** **Recommend:** leave card names as emitted, and
   when two repos share a folder name, label both by their home-collapsed path. The alternative
   prefixes every card with its repo, which is clearer for clashing names and noisier everywhere
   else.

   **Answer (my call), 2026-11-03.** As recommended: card names stay as the analyzer writes them,
   and repos are labelled by path only when two share a folder name. Places changed: §7.1, a new
   scenario, criterion F3.
4. **OQ-4 — Branch or Worktree matches no card.** **Recommend:** refuse at submit with a pop-up,
   "No card matches that branch or worktree.", and queue nothing. That matches D2's
   nothing-found rule. The alternative writes an empty run that he then has to delete.

   **Answer (user), 2026-11-03.** As recommended: no Branch or Worktree match is a pop-up at
   submit, and nothing is queued. Places changed: §3.5, §4.2, §9.2, a new scenario, criterion H2.
5. **OQ-5 — the board after Re-analyze is queued.** **Recommend:** go to the Ledger, where the
   progress is. The alternative is a notice on the board, which then needs its own polling to say
   when the run is ready.

   **Answer (user), 2026-11-03.** As recommended: after Re-analyze is queued, the board goes to the
   Ledger. Places changed: §9.4, the "Re-analyze from the board" scenario, criterion H6, §12.
6. **OQ-6 — first launch with an empty store.** Today `--open` analyzes the launch repo before
   opening the browser (`server.py:756-763`), writing a folder-name id. **Recommend:** queue that
   directory as an ordinary Ledger job, so the Ledger opens showing it running, with a D12 id.
   The alternatives are to open an empty Ledger, or to keep the old synchronous write.

   **Answer (user), 2026-11-03.** As recommended: first launch with an empty store queues the
   launch repo as an ordinary Ledger job. Places changed: §4.1 (depth 0 made explicit, so that job
   cannot pull in repos nested inside the launch repo), §5.3, a new scenario, criteria C1, D8 and
   I, §12.
7. **OQ-7 — runs from before the Ledger** carry a folder-name id and no recorded request.
   **Recommend:** Re-analyze queues `{directory: <their dir>}`. That lands as a new run with a D12
   id, and the old one stays until he deletes it, so nothing is rewritten. The alternative writes
   under the old id, after which the same folder analyzed from the form makes a second run anyway.

   **Answer (my call), 2026-11-03.** As recommended. Places changed: §3.4, §8.2, a new scenario,
   criterion G6.
8. **OQ-8 — other programs a scanned repo's config can start.** D10 switches off one key. Not
   measured here: other repo-config entries may make the analyzer's read-only git commands run a
   program, such as a clean filter that `git status` applies, or a hook run when `git status`
   rewrites the index. **Recommend:** task 1's ADR tests and, if confirmed, also sets
   `GIT_OPTIONAL_LOCKS=0` and `core.hooksPath=/dev/null`, and records filters as an accepted
   residual. Both settings are cheap and change nothing for a normal repo.

   **Answer, 2026-11-03.** The tightening as recommended: task 1's ADR tests hooks and optional
   lock writes and switches them off if confirmed. That half is **(my call)**: it only
   tightens safety, so it needed no user decision. File filters **(user)**: if task 1 finds
   they cannot be switched off without breaking the scan, the scan still runs and the ADR records
   them as an accepted risk. Repositories that use Git LFS are not skipped **(user)**. Places
   changed: §2 default 3, §13, §16, criterion C9.

   **Superseded in part at round 2 (2026-11-03).** The (my call) half is no longer conditional:
   hooks and the optional index write were measured as real routes, so `GIT_OPTIONAL_LOCKS=0` and
   `core.hooksPath=/dev/null` are set unconditionally (§2 default 3, C9). The (user) half now has
   a task-1 test on a real LFS repository, with both outcomes defined, before he decides (D15/U3).
   The text above is kept as the answer given at the time.

   **Superseded in part again at round 3 (2026-11-03, U4).** OQ-8 asked about hooks and filters
   only, so it never answered "other programs a scanned repo's config can start" in general, and
   §13 should not have called it answered. Since round 3 the config routes tried are fsmonitor,
   hooks, `gpg.program` through `log.showSignature`, a promisor lazy fetch, `diff.external`,
   `diff.<driver>.textconv` and file filters; the first four are closed by the protective
   settings (§2 default 3, C8–C11), the two diff routes did not fire on the analyzer's
   `--shortstat`, and filters wait for task 1 (now with a third outcome if `git-lfs` cannot be
   installed, U5). Git's other config keys that can name a program have **not** been enumerated,
   so these routes are a lower bound (§16).

**Also decided on 2026-11-03.** The user confirmed the spec call that the last visible run cannot
be deleted (§8.4, criterion G5). He accepted this file running over ADR 0017's 800-line cap
(recorded at the top).

## Revised after compliance round 2 (2026-11-03)

Round 2 failed with three violations (file size, explicit error handling, verify before
claiming), and the observability judge's architecting read raised more. The user decided three
things; the card records them as D13–D15. The planning session settled the rest as **(my call)**.
The labels below are how the text above cites each change.

**The user's decisions (user, 2026-11-03).**

- **U1 = D13. The board keeps `/`; the Ledger is at `/ledger`; launch opens the Ledger.** D1 still
  holds. Places changed: §1's diagram, §1.1, §2, §3.1, §3.2, §3.5, §5.3, §9.1, §9.4, seven
  scenarios (two new, five edited), criteria A1, D8, H4, H5, H6, H10, I, Z2, §12, §15.
- **U2 = D14. No job stays `running` for ever.** Two specific codes, `merge_failed` and
  `launch_failed` (names: spec call), and a catch-all, `internal_error`. Places changed: §3.5,
  §3.6, §5.1, §5.2, §5.4, §5.5, §5.6, §9.2, four scenarios, criteria A2, D12, D13, D14.
- **U3 = D15. File filters: task 1 tests the off switch on a real LFS repository**, shows him
  the result, and the outcome decides. Places changed: §2 default 3, §13, §16, criterion C9, the
  OQ-8 note.

**Fixes from the verdicts (my call, 2026-11-03).**

- **F1.** §12 rederived across all 16 test modules with the commands shown; Z3 lists exactly the
  edits split 3 forces, measured by simulation; §15 runs the whole `treko/` directory.
- **F2.** The child environment's base is named, and `GIT_CONFIG_PARAMETERS` and the
  `GIT_CONFIG_COUNT` family are dropped from it; §2's false sentence is corrected; C8's AST
  check catches whole-environment copies.
- **F3.** `GIT_OPTIONAL_LOCKS=0` and `core.hooksPath=/dev/null` are unconditional; §13's "writes
  only inside the store directory" is made true and measured.
- **F4.** §5.1 and criterion D11 say where the request really lives (twice, by design).
- **F5.** `runsError` names the store folder instead of a log nothing writes.
- **F6.** Every code has a §9.2 row; criterion H11 checks both directions.
- **F7.** The submit-time scan is killed at shutdown (the child registry, §4, §5.3, D6).
- **F8.** `retry` cannot create a second live item for one run (§3.4, §3.5, §5.2, §5.6, D9).
- Recorded, not built: a running job cannot be stopped; repositories per job are uncapped; the
  depth-5 count will likely raise its question on every `~` scan (§14, §16).

**Not changed at round 2**, though the compliance verdict's notes raised them: §1.1 split 2's
"would still pass its 780 budget" wording; §15's two sentences written before the runner was
pinned; §9.4's board fallback "Open the Ledger to see why" for codes where nothing was queued;
the outcome when one git call passes `GIT_TIMEOUT_SECS`; `flock` open errors and a `ledger.json`
read error other than a parse failure (§5.1); §9.1's reason for copying the token block; §8.3's
row cache. They were outside this revision's brief. (Round 3 fixed the first three; see below.)

## Revised after compliance round 3 (2026-11-03)

Round 3 failed with two new violations: a scanned repository could still make git run a program
under every round-2 setting (`core-conduct/state-unverified-gaps`), and `git-lfs` had no pinned
version (`writing-specs/pinned-versions`). The observability judge's third read raised more. The
user decided three things; the card records them as D16–D18. The rest are fixes the planning
session proposed and the user approved.

**The user's decisions (user, 2026-11-03).**

- **U4 = D16. Close both measured program routes; say plainly what is untested.**
  `log.showSignature=false` joins the config pairs and `GIT_NO_LAZY_FETCH=1` the environment,
  each with a falsifier criterion; the git floor rises to 2.45; what a partial clone shows is
  measured; the routes tried are listed and the rest are called not enumerated. Places changed:
  §2 default 3, §13, §15, §16, OQ-8's note, three scenarios, criteria C8, C10, C11, C12.
- **U5 = D17. `git-lfs` is a test-only tool, pinned:** Homebrew 3.8.1, vetted (0 stop, 0
  caution, incomplete: every check `not_run` for Homebrew), installed in task 1 only with his
  approval at the prompt; a refused or failed install is task 1's third outcome. Places changed:
  §2 default 3, §13, §15 (a row and the "No new dependency." sentence), §16.
- **U6 = D18. A worktree whose `git status` fails shows "changes unknown".** The schema is
  unchanged (`dirty` stays a boolean, ADR 0023); `note` and `tone` carry it, one question says
  why, and the board needs no code change. Places changed: §1's file table, §1.1, §6.1, a new
  §6.3, a scenario, criteria E2 and E6.

**Small fixes (my call, approved by the user, 2026-11-03).**

1. Task 1's filter test can fail: `.required` is blanked too, driver names are read per worktree
   with includes, global and per-worktree config (measured), the fixture has a stat-dirty
   LFS-tracked file and one really modified file, and a falsifier must see the marker (§2 default
   3).
2. Shutdown closes the child registry first: no new family and no new job after that, and a
   killed analyzer is never a failed family (§4, §5.3, §5.4, D6, a scenario).
3. The catch-all kills the job's live subprocess groups before marking the item failed (§5.4,
   D14).
4. Every server-side launch goes through the registry with `env=` from the builder, and the AST
   check flags a launch without it, with a falsifier (§4, C8).
5. §9.4's "Open the Ledger to see why" is reworded: nothing was queued, so it pointed nowhere.
6. `last_job_end` is set at every job end, not only on success; §5.5 reads the same either way
   (§5.4, §5.5, B1, a scenario).
7. `launch_failed`'s "Nothing was analyzed" became "This analysis stopped and nothing was saved"
   (§9.2).
8. D14's seam is the job thread's report handler, not a stage function inside the analyzer
   (§5.4 step 3, D14, its scenario).
9. §12's re-pin names `BASE_FENCE_NODE_BRIDGE_BYTES` and `_SHA256` (`test_guards.py:136-137`).
10. §1.1's "135 passed" is scoped correctly: 85 for the six named modules, 135 with
    `test_guards.py` and `test_ui_commands.py`.
11. Plain factual errors from the round-3 notes: the board's response is not byte-identical to
    today's (§3.2, the scenario); §2 default 2's "every request" is "every connection"; C8's unit
    row contradicted itself; §1.1 split 2's "pass" meant "exceed"; §15's two pre-pin sentences;
    §12 now also names `test_ui_commands.py`'s docstring; §5.5's "every job ends `running`"
    meant "leaves".

**Not changed at round 3**, because each is a design change for the planning session to decide,
not a factual fix: a SIGTERM handler (`server.py` installs none, so SIGTERM is §5.3's hard kill
and a child in its own process group can outlive the server); a catch-all for request threads
(an unexpected exception there drops the connection, which §9.1 reads as the server gone);
§8.3's rows over a store run holding only `id` and `name` (as `test_autolaunch.py` seeds);
whether Z3's forced test edits belong in a separate commit from split 3's move; having task 1
check each git command the analyzer runs against the config keys that can name a program, rather
than waiting for review to find the next route; and stating in §15 where `TMPDIR` must be for
`test_autolaunch.py`, which no one has measured. Also still open from round 2: the outcome when
one git call passes `GIT_TIMEOUT_SECS`, `flock` open errors and a non-parse `ledger.json` read
error, §9.1's token-block reason, §8.3's row cache.
