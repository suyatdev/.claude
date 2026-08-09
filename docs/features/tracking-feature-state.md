---
phase: implementation
model_tier: high
branch: feat/tracking-feature-state
---

# Feature-state tracking with a browser UI

This repo carries more feature cards, phases and live worktrees than one session holds in its head —
run `ls docs/features/*.md`, `awk '/^phase:/{print $2}' docs/features/*.md | sort -u` and
`git worktree list` for the current spread. Every one of those counts moved during this feature's own
implementation, which is the argument for the feature rather than an aside: the merge order across
them is reconstructed by hand every session, and session 46 wrote that survey as a markdown table
into `.claude/session-state.md` where it went stale the same day. The information needed to build it
is all mechanical: card frontmatter, checklist state, `git worktree list`, ahead/behind counts.
Nothing derives it on demand.

**No count, line number, or phase tally is pinned anywhere in this card.** Two audit passes found nine
factual defects here, every one of them a stored result that had gone stale — twice inside the
corrections written to fix the previous round. Claims are written as derivations to re-run.

This adds a skill that derives that survey for a given repo, writes it as a versioned run into a data
file, and drives an **already-built** browser UI that renders it — with a control channel that lets
the UI drive the Claude session that launched it.

## Evidence this is the actual gap

Derivations, not pinned line numbers — re-run them, they move:

- `.claude/session-state.md` is gitignored (`/.claude/`, `.gitignore:72`) and rewritten every session
  by `hooks/live-handoff.sh`, so a survey written there has no history and no lifetime — session 46's
  "Strand survey" table is already gone. A hand-maintained survey cannot live in the one file the
  harness is designed to overwrite.
- `ls docs/features/*.md | wc -l` vs. `grep -l '^phase: planning' docs/features/*.md` — the phase
  spread that `phase-guard.sh` depends on is only ever read one card at a time.
- `git worktree list` against `grep -l '^branch: *none' docs/features/*.md` — the two sets are
  maintained independently and nothing cross-checks them. They may or may not conflict on any given
  day, and that is the point: **nothing would report it if they did.** Criterion 2 therefore tests the
  drift against a fixture rather than relying on this repo to keep exhibiting it.

## The output contract already exists — do not invent one

`/Users/marksuyat/Other\ Docs/AI/AI_Projx/Task Progress Analysis UI` holds a Nocturne design-system
export: `Task Tracker.dc.html`, `Task Tracker Directions.dc.html` (a 4-direction options canvas),
`nocturne.css`, `support.js`, `_ds/`, and `tracker-data.json` — **`task-tracker v0.4.1`, schema
`version: 1`**. Its own `github.md` records that it was modeled on real features in this repo by
reading `hooks/lib/feature_tasks.py` vocabulary.

⚠️ That directory is under `Other\ Docs` — a sibling of `Other Docs` whose name contains a **literal
backslash**. Both exist in `$HOME`. Every path reference must be single-quoted with the one backslash
intact, or it silently resolves to the wrong (space-named) directory, which has no such project.

The analyzer emits objects conforming to that schema. Read it, do not redesign it:

```
version, tool, generatedAt, repoUrls{}
runs[]                                   ← multiple analyses; switching is selecting one
  id, name, dir, analyzedAt
  features[]{name, meta, tasks[]}
  waves[]{n, note, items[]}              ← the merge / execute order
  constraints[]{id, title, pair, body}   ← why a wave is ordered that way
  branches[]{repo, branch, wt, ahead, behind, dirty, note, tone, last}
  graph{nodes[], edges[]}                ← dependency DAG
  kanban[]{title, tone, items[]}
  questions[]{id, q, ctx, resolved}
```

Task identity follows `hooks/lib/feature_tasks.py`: `STRICT_RE = ^\s*-\s\[[ xX]\]\s+(.+)$`, id is the
leading integer before the em dash. Reuse that module — do not write a second checklist parser.

## Design

Four components, in dependency order.

### 1. Analyzer (`task-tracker/analyze.py`)

Pure read. Given a repo root, produce one `run` object:

- **features** — parse `docs/features/*.md` frontmatter (`phase`, `branch`, `model_tier`) and
  checklists via `feature_tasks.py`. `meta` is `"<done>/<total>"`.
- **branches** — `git worktree list --porcelain`, `git for-each-ref`, and
  `git rev-list --left-right --count` for ahead/behind; `git status --porcelain` for `dirty`.
- **waves / constraints / graph** — derived, and this is the only judgment-bearing part: a card is
  wave 1 when its branch exists, is not behind its base, and no other card's card-text names it as a
  prerequisite. Constraints are read from an explicit `## Depends on` section in a card, never
  inferred from prose. **An undetectable dependency must surface as a `questions[]` entry, not as a
  confident ordering** — a wrong merge order is worse than an admitted gap.

### 2. Store + emit (`task-tracker/tracker-data.js`)

The UI loads `tracker-data.js`, not the JSON. Emit `window.TRACKER_DATA = {...}`. Runs are keyed by
`id`; re-analysis **replaces the run with that id and preserves the others**, so switching between
analyses and re-analyzing one are the same operation on different keys. Write atomically (temp file +
`os.replace`) so a crashed run cannot truncate the store.

### 3. Control server (`task-tracker/server.py`)

Localhost only. This is the component the Security section governs. Its send path is
`cmux send --surface`, resolved — see §"Injection route".

### 4. Skill (`skills/tracking-feature-state/SKILL.md`)

The activity-triggered entry point: when to run an analysis, how to read the waves, how to launch and
stop the UI. Per `triaging-new-instructions` step 4 this is one skill because it is one activity;
the UI and server are its subject, not additional skills. It **points at**
`managing-session-memory` for phase rules rather than restating them.

## Injection route: `cmux send --surface` — resolved, do not re-spike

The control model (UI → server → keys into the live session) **has** a working precedent here. This
card's first draft claimed the opposite; that claim came from pooling function names across all four
adapter files with `sort -u` and reading the union as a property of each — an artifact of the grep,
not of the code.

`panes/adapters/cmux.sh` `send_launcher()` sends to an **existing** surface:

```sh
"$CMUX_BIN" send ${WS_ARGS[@]+"${WS_ARGS[@]}"} --surface "$1" -- "bash $launcher_q\n"
```

and the pane-reuse branch is commented "v1-proven here (user-approved deviation 2026-07-21; the
spec's intent is unchanged)". Tasks 8–10 build on that verb. **Task 1's spike has already run — the
route is decided and re-running it is wasted work.**

Two constraints ride along, both load-bearing for task 8:

- **A stale ref may not error.** `cmux.sh` documents the resolution chain
  `--tab` → `--surface` → `$CMUX_TAB_ID`/`$CMUX_SURFACE_ID` → **the focused tab**, with an
  unresolvable ref falling through it *without erroring* — probe P6, proven live against
  `surface:9999` at exit 0. ⚠️ That comment documents **`rename-tab`, not `send`.** `send` takes the
  same `--surface` flag and very likely shares the chain, but no probe has shown that it does.
  Task 8 must therefore (a) verify empirically whether `send` inherits the fall-through, and
  (b) re-resolve and confirm the target surface at send time and **refuse** an unconfirmed ref
  regardless of the answer. Keystrokes landing in the focused tab is the worst failure this feature
  can have.
- **The rejected routes stay rejected.** `TMUX` is unset here (`TERM_PROGRAM=ghostty`), so
  `tmux send-keys` is not available; and `panes/handoff-wrapper.sh:5` records that the handoff spec
  deliberately rejected "pre-typed keystroke tricks", so osascript keystroke injection would reverse a
  prior decision rather than extend one. `cmux send` is the one sanctioned route.

Still genuinely unproven, and worth 15 seconds on a scratch surface before task 8 starts: every proven
use of `cmux send` targets a **shell prompt**. None targets a live Claude TUI.

**Clipboard is a supported runtime mode, not a fallback.** `panes/terminal-detect.sh` prints `none`
under SSH or headless (`terminal-detect.sh:14`), where no injection route exists by construction. In
that mode the UI offers every allowlisted command as copyable text. That is the same feature minus one
verb, and criterion 8 tests it as a first-class path rather than a degradation.

## Security

The server can drive a Claude session holding full tool permissions. It is the highest-value target
this repo has ever exposed, so it is default-deny:

- **Bind `127.0.0.1` explicitly.** Never `0.0.0.0`, never a hostname that could resolve outward.
- **Allowlisted commands only.** A fixed map of id → command (`clear`, `handoff`, `reanalyze`, …).
  The wire carries the *id*; the command text never crosses the network. An endpoint accepting an
  arbitrary string is a remote shell and is out of scope permanently, not just for v1.
- **Per-launch bearer token**, generated with `secrets.token_urlsafe`, baked into the emitted
  `tracker-data.js` and required on every POST. Compare with `hmac.compare_digest`.
- **Require a custom request header.** CORS does not stop a hostile page from *sending* a simple
  cross-origin POST — it only hides the response. A required non-simple header forces a preflight
  that the server refuses. Also reject on `Origin`/`Sec-Fetch-Site` mismatch.
- **Bound lifetime.** The server exits with the session and on idle timeout; no daemon, no launchd.
- **Confirm the target surface at send time**, per §"Injection route" — refuse an unconfirmed ref
  rather than risk keystrokes reaching the focused tab.
- Port comes from `allocating-local-ports` and is recorded in `PORTS.md` before first bind.

**What this feature does and does not add to the threat model.** The cmux socket has no
authentication beyond its `0600` permission, so surface injection is *already* available to any
process running as this user — this feature does not create that exposure. What it does create is the
**HTTP hop**: a network-reachable endpoint in front of a capability that was previously reachable only
by a local process holding the user's uid. Every bullet above defends that hop specifically. None of
them is redundant with the socket's file permission, and none may be weakened on the argument that
"injection was possible anyway."

## Acceptance criteria

1. **Given** a **named working tree** — the criterion must name which one, because the main checkout
   and each worktree hold different card sets — **when** the analyzer runs against it, **then**
   `features[]` has exactly one entry per `docs/features/*.md` file *in that tree* whose frontmatter
   carries a `phase:` key (a split `<name>.spec.md` half carries none and is not a card), and each
   `meta` is `"<done>/<total>"` where `total` is `len(task_ids(...))` from `hooks/lib/feature_tasks.py`
   and `done` is the count of `[xX]` markers on the same `STRICT_RE`-matched lines.
   ⚠️ `feature_tasks.py` has no done/total of its own to compare against: `identity()` deliberately
   consumes only `match.group(1)`, the text *after* the bracket, so task identity survives a tick.
   The done count is therefore read off the raw matched lines, by this feature, using that module's
   regex — one parser still holds.
2. **Given** a card whose frontmatter says `branch: none` while a worktree holds a branch named for
   it, **then** that drift appears in `questions[]` — not silently resolved in either direction.
3. **Given** two analyses of different directories, **then** both persist in `runs[]` and switching
   between them changes no data on disk.
4. **Given** a re-analysis of an existing run id, **then** that run's `analyzedAt` advances and every
   other run is byte-identical.
5. **Given** an interrupted write, **then** the previous `tracker-data.js` is still valid JS —
   assert by killing mid-write and reloading.
6. **Given** a POST with no token, a wrong token, or a command id outside the allowlist, **then** the
   server responds 403 and **no command reaches the session**.
7. **Given** a cross-origin POST from a page the user did not open, **then** it is rejected on the
   preflight or the Origin check.
8. **Given** a host where `panes/terminal-detect.sh` prints `none` (SSH, headless), **then** the UI
   still renders every run and still offers each allowlisted command — as copyable text rather than
   injection.
9. **Given** a `send` whose target surface ref no longer resolves, **then** the server refuses and
   reports, and **no keystroke reaches any surface** — specifically not the focused one.

## Tasks

- [x] 1 — **Spike — done, do not re-run.** Route is `cmux send --surface`; see §"Injection route" for
      the evidence, the two constraints it carries, and the one probe still outstanding (`send` into a
      live Claude TUI, owed before task 8).
- [x] 2 — Vendor the UI: copy the Nocturne export to `task-tracker/`, preserving `_ds/`. Verify the
      copied `Task Tracker.dc.html` opens and renders from the bundled `tracker-data.js`.
- [x] 3 — `task-tracker/analyze.py`: features + branches only, importing `hooks/lib/feature_tasks.py`.
      Emit schema-valid JSON. No waves yet.
      - `analyze.py` is over the 400-line target though under the 800 hard max (`wc -l` it). The clean
        split is a `task-tracker/git_facts.py` holding the worktree/ahead-behind/dirty readers. **Not
        scheduled** — a structural split is a human-owned call, not a drive-by; raise it if the file
        grows again.
- [x] 4 — `task-tracker/test_analyze.py`: criteria 1 and 2 against a fixture repo, not this one.
      (Named `test_*.py`, not `*.test.py` — pytest collects only the former.)
- [x] 5 — Waves, constraints and graph derivation, including the `## Depends on` reader and the
      "undetectable dependency becomes a question" rule.
- [x] 6 — `task-tracker/store.py` + `task-tracker/test_store.py`: atomic emit of `tracker-data.js`,
      run upsert by id. Criteria 3-5.
- [ ] 7 — `PORTS.md` entry for the control server, per `allocating-local-ports`, before any bind.
- [ ] 8 — `task-tracker/server.py`: localhost bind, token, allowlist, custom-header requirement, and
      send-time surface confirmation. Route is settled (task 1); run the outstanding Claude-TUI probe
      first.
- [ ] 9 — `task-tracker/test_server.py`: criteria 6, 7 and 9, including the negative cases. A test
      that only proves the happy path does not close this task.
- [ ] 10 — Wire the UI's command buttons to the server (or clipboard, per task 1).
- [ ] 11 — `skills/tracking-feature-state/SKILL.md`, following
      `skills/_standards/authoring-skills-and-agents.md`. Points at `managing-session-memory`; does
      not restate phase rules.
- [ ] 12 — Add the skill to the Skills Catalog in `CLAUDE.md`.
- [ ] 13 — Run every suite, record before/after counts in `## Verification`. Capture before-counts
      first so a pre-existing failure is not read as a regression.

## Out of scope

- An endpoint that accepts arbitrary command text. Permanently, not just v1.
- Any daemon, launchd job, or server outliving the session.
- Writing to the analyzed repo. The analyzer is read-only; it never edits a card to fix drift it
  found — it reports it in `questions[]`.
- Multi-machine or remote access. Localhost only.
- Redesigning the UI or its schema. If a field is missing, that is a `questions[]` entry and a
  conversation, not an ad-hoc schema extension.

## Verification

**Task 1 — injection route.** Resolved: `cmux send --surface`, evidence in §"Injection route". One
probe remains outstanding and is owed before task 8 opens: `cmux send` into a live **Claude TUI**, as
every proven use to date targets a shell prompt.

**Tasks 2–6 suites.** `uv run --with pytest --no-project pytest task-tracker/ -q` → **53 passed**
(re-run 2026-08-09 during the spec revision; this is the only invocation that works here, as there is
no system pytest). Re-run the command rather than trusting this number.

⚠️ **Task 13 must not use a bare `pytest -q`.** `addopts` in `pyproject.toml` deselects the `golden`
and `measurement` marks, so the bare invocation reports green while those suites are unrun. Capture
before-counts per suite, with marks explicitly re-enabled, before touching anything — otherwise a
pre-existing failure reads as a regression introduced by this feature.

## Revision history

**2026-08-09 (session 49) — nine defects repaired, corrections sections removed.** Two audit passes
(sessions 47 and 48) found nine factual errors in this card, every one the same species: a stored
result that went stale, twice inside the corrections written to fix the previous round. All nine are
fixed in the body above and the corrections sections are deleted — a spec plus a list of ways the spec
is wrong is two documents disagreeing, and a reader cannot tell which to believe. Git holds the
detail; `a854e99` is the last commit carrying the unrepaired text.

The structural fix, applied throughout: **claims are written as derivations to re-run, not as stored
counts or line ranges.** The one number retained above is stamped with the date it was measured and
the command that reproduces it.

One defect was found *in the audit itself* during this revision and is recorded here rather than
silently dropped: the audit asserted that tasks 4, 6 and 9 named uncollectable `*.test.py` files.
Tasks 4 and 9 did; **task 6 never did** — it names `store.py`, an implementation file. The correction
inherited "6" from the adjacent list without re-reading the task. Separately, the audit attributed
cmux's non-erroring ref fall-through to `send`; the source comment documents it for **`rename-tab`**.
That distinction is now carried explicitly into §"Injection route" and criterion 9, because assuming
`send` shares the chain is the same unfalsified-inference error a third time.
