---
phase: implementation
model_tier: high
branch: feat/tracking-feature-state
---

# Feature-state tracking with a browser UI

Across this repo there are eight feature cards in four phases, three live worktrees, and a set of
branches whose merge order is currently reconstructed by hand every session — session 46 wrote that
survey as a markdown table into `.claude/session-state.md` and it went stale the same day. The
information needed to build it is all mechanical: card frontmatter, checklist state, `git worktree
list`, ahead/behind counts. Nothing derives it on demand.

This adds a skill that derives that survey for a given repo, writes it as a versioned run into a data
file, and drives an **already-built** browser UI that renders it — with a control channel that lets
the UI drive the Claude session that launched it.

## Evidence this is the actual gap

Derivations, not pinned line numbers — re-run them, they move:

- `grep -c '' .claude/session-state.md` against `git log -1 --format=%cr` on the same file — the
  hand-written "Strand survey" table carries a date because it cannot be recomputed.
- `ls docs/features/*.md | wc -l` vs. `grep -l '^phase: planning' docs/features/*.md` — the phase
  spread that `phase-guard.sh` depends on is only ever read one card at a time.
- `git worktree list` — three worktrees, two of them holding branches for cards whose own frontmatter
  says `branch: none`. That drift is exactly what the analysis is for.

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

Localhost only. This is the component the security section governs; it does not exist until task 1
resolves how injection actually works.

### 4. Skill (`skills/tracking-feature-state/SKILL.md`)

The activity-triggered entry point: when to run an analysis, how to read the waves, how to launch and
stop the UI. Per `triaging-new-instructions` step 4 this is one skill because it is one activity;
the UI and server are its subject, not additional skills. It **points at**
`managing-session-memory` for phase rules rather than restating them.

## Injection is unproven — task 1 is a spike

The chosen control model (UI → server → keys into the live session) has no working precedent here:

- Every adapter in `panes/adapters/` implements `send_launcher()` — *open a new pane and run a
  command*. None sends input to an existing pane.
- `TMUX` is unset in this environment (`TERM_PROGRAM=ghostty`), so `tmux send-keys` — the one clean
  route — is unavailable as things stand.
- `panes/handoff-wrapper.sh` records that the handoff spec **deliberately rejected** "pre-typed
  keystroke tricks", so osascript keystroke injection would reverse a prior decision, not extend one.

Task 1 therefore decides the route before anything is built on it, and has a defined fallback:
**if no route survives the spike, the server degrades to serving commands for the UI to copy to the
clipboard, and the feature still ships.** That fallback is not a lesser version of the feature; it is
the same feature minus one verb.

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
- Port comes from `allocating-local-ports` and is recorded in `PORTS.md` before first bind.

## Acceptance criteria

1. **Given** a repo with N feature cards, **when** the analyzer runs, **then** `features[]` has N
   entries and each `meta` matches `feature_tasks.py`'s own done/total count for that card.
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
8. **Given** the spike's fallback path, **then** the UI still renders every run and still offers each
   allowlisted command — as clipboard text rather than injection.

## Tasks

- [ ] 1 — **Spike:** determine whether keys can be sent to this live session (cmux exec verb? a tmux
      server started under Ghostty? Ghostty AppleScript?). Time-box it. Record the answer and the
      chosen route in `## Verification`; if none works, mark the fallback in criterion 8 as the
      shipping path and say so explicitly. **No other task starts first.**
- [ ] 2 — Vendor the UI: copy the Nocturne export to `task-tracker/`, preserving `_ds/`. Verify the
      copied `Task Tracker.dc.html` opens and renders from the bundled `tracker-data.js`.
- [ ] 3 — `task-tracker/analyze.py`: features + branches only, importing `hooks/lib/feature_tasks.py`.
      Emit schema-valid JSON. No waves yet.
- [ ] 4 — `task-tracker/analyze.test.py`: criteria 1 and 2 against a fixture repo, not this one.
- [ ] 5 — Waves, constraints and graph derivation, including the `## Depends on` reader and the
      "undetectable dependency becomes a question" rule.
- [ ] 6 — `task-tracker/store.py`: atomic emit of `tracker-data.js`, run upsert by id. Criteria 3-5.
- [ ] 7 — `PORTS.md` entry for the control server, per `allocating-local-ports`, before any bind.
- [ ] 8 — `task-tracker/server.py`: localhost bind, token, allowlist, custom-header requirement.
      Route from task 1.
- [ ] 9 — `task-tracker/server.test.py`: criteria 6 and 7, including the negative cases. A test that
      only proves the happy path does not close this task.
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

_(to be filled during implementation — spike result and chosen injection route first, then
before/after test counts per suite)_

## Card corrections required (found by lanes A and D, verified by the orchestrator)

Four factual errors in this card, all of the same species — **a fact asserted from a grep I did not
falsify**. Per the standing rule about repeat findings of one class, the fix is to re-derive every
factual claim here, not to patch these four. That audit is the next task.

1. **"Injection is unproven" is wrong.** `send_launcher()` (`panes/adapters/cmux.sh:163-165`) sends to
   an *existing* surface via `cmux send --surface`, and the reuse branch (`cmux.sh:302-312`) is
   commented "v1-proven here (user-approved deviation 2026-07-21)". My original claim came from
   pooling function names across all four adapter files with `sort -u` — an artifact of the grep, not
   a property of the code. `cmux send` exists and is documented.
2. **Evidence bullet 3 is stale.** There are now 6 worktrees, exactly 2 cards say `branch: none`
   (`falsify-harness-signatures`, `verification-marker-gate`), and **no worktree branch is named for
   either** — so criterion 2's drift scenario does not currently occur in this repo. The test builds
   it in a fixture, which is correct; the *evidence* bullet overclaimed.
3. **Criterion 1 overstates `feature_tasks.py`.** That module deliberately discards the checkbox
   marker (`feature_tasks.py:11-14`) because task identity must survive a tick — so it has no
   done/total to match. Reword to: total from `task_ids()`, done read off the same `STRICT_RE`-matched
   lines. One parser still holds.
4. **Test filenames cannot be collected.** Tasks 4, 6 and 9 name `*.test.py`; pytest collects
   `test_*.py`. Implemented as `test_analyze.py` / `test_store.py`; task 9 must be reworded before
   anyone starts it.

Also open: `analyze.py` is 792 lines — under the 800 hard max, over the 400 target. The clean split is
a `task-tracker/git_facts.py`, which needs an explicit ownership grant.

Security addition for task 8, from the spike: `cmux.sh:168-172` records that an unresolvable ref falls
through to the **focused** tab without erroring. Task 8 must re-resolve and verify the target surface
at send time and refuse rather than send an unconfirmed ref. Separately — the cmux socket has **no
authentication** beyond its 0600 permission, so injection is already available to any process running
as the user; the new risk this feature introduces is the HTTP hop, which is what the Security section
above defends. Do not weaken any of it.
