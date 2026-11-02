---
phase: planning
model_tier: high
branch: feat/treko-ledger
---

# Treko: the Ledger — a home page, a real analysis queue, and directory scanning (card 2)

Brainstormed 2026-11-01/02 with the user, on Opus 5.5 at xhigh (model-switch checkpoint 1, entering
planning: asked and answered, his standing routing). Branch `feat/treko-ledger` was created at
planning time from `origin/main` @ `3f2a939`, following the `chore/treko-chrome-156-repin` precedent,
because the standing worktree rule needs a branch for the worktree to hold.

**State of this file.** The brainstorm is finished and recorded below. Still to do, in this order: the
builder check (a fresh reader looking for gaps), the `writing-specs` pass (Gherkin, contracts, pinned
versions), the compliance judge, the user's review, and then the task checklist. **Nothing under
§Spec or §Tasks has been written yet.** They are placeholders, not omissions to infer from.

Every decision below is tagged **(user)** when he decided it in the brainstorm, or **(my call)** when
the planning session settled it and he has not yet seen it written down. A builder must not promote a
(my call) to (user).

## Why

The user's own statement of what Treko is for (2026-11-02, verbatim):

> The purpose of treko is mostly for seeing the works done in a particular directory given, and it's
> relation to other cards/tasks / repos / stories. To help me determine what works are done and are
> left as well as the order of works needed to be done and what is a dependency and blockers.

Today none of that starts from a place he can point at. Treko opens straight onto one repo's board,
surveyed from wherever it was launched. The prototype he designed has a **Ledger** in front of the
board: a page where he types a directory, queues an analysis, watches it run, and opens any finished
run. It was always meant to exist (`treko-rename.md:746-751` names it "card 2 … the Ledger list and
its persistent queue", and records that no Ledger file exists in this repo). This card builds it.

## The three-card split (user, 2026-11-02)

The brainstorm covered more than one card. Agreed order:

1. **This card: the Ledger.** It works with today's analyzer and is built so the next two cards add
   data to a run without reworking the page.
2. **Card 5, already planned:** `docs/features/treko-branch-graph-traversal.md` (phase `planning`):
   branch ancestry, card-to-card `## Depends on`, and PR data.
3. **A new "relations" card, not yet written.** Its decisions are recorded in §Decisions carried to
   the relations card so they are not lost. It builds on card 5's `## Depends on`, which is why it
   comes last.

## Source of truth for the look

The user's latest prototype, `~/Other Docs/AI/AI_Projx/Prototypes/Treko/` (as of 2026-11-01 19:44):

- `Ledger.dc.html`: the page. A header with "Run ledger" and "Open the board"; the **Queue a new
  analysis** card (Directory path, Repo, Branch, Worktree, then Artifacts path with Save); a
  **Queued** list with a progress bar and step label on the running item; a **Runs on disk** list
  (name, analyzed-at, dir, counts for repos/branches/worktrees/features, a tasks-merged bar, Open,
  Delete with a confirm dialog).
- `Task Tracker.dc.html:55` and `:75`: both Treko icons on the board are wrapped in
  `<a href="Ledger.dc.html" title="Back to Ledger">`.

**Where the prototype is not the spec.** Its queue lives in browser `localStorage`, its progress is a
320 ms timer cycling six invented step names, and a finished run is a fake object reading
"snapshot pending — simulated run". All three are replaced (D5, D6). It also makes each queued item
wait for its own Analyze click; the user does not want that (D4).

## Goals

- Launching Treko lands on the Ledger. The board's Treko icon goes back to it (D1).
- He types a directory and gets an analysis of every repo in and around it (D2, D3).
- An analysis runs on the server, so leaving the page, opening other runs, refreshing or closing the
  browser never stops it (D5).
- The progress bar shows only real progress (D6).
- Finished runs are listed and each opens its own board (D7).

## Non-goals

- PR data, branch ancestry, `## Depends on`: card 5.
- Sub-tasks, `parent:`, spec/ADR links, `blocked-by:`, cross-repo dependencies: the relations card.
- An LLM agent doing the analysis. **(user):** "It doesnt have to be an agent. As long as the script
  can do that analysis." The analysis stays a script.
- The Configuration drawer: card 3 of the numbered set (`treko-store-location.md:88-92`).

## Anti-goals: failures even if it technically works

- **A progress bar that moves when nothing happened.** That is a number the data cannot source (the
  core-conduct rule), and it is exactly what the prototype does.
- **An analysis that dies because the page went away.** He named this one directly (D5).
- **A guessed relationship.** Treko's analyzer refuses to infer from prose (`analyze.py` docstring:
  "guessing produces a confident wrong merge order, which is worse than an admitted gap"). Nothing in
  this card weakens that.
- **The same repo counted twice** because it was reached once directly and once through a worktree.

## Decisions

**D1 — The Ledger is the landing page.** (user) It is the first page Treko shows on launch, and
clicking the Treko icon on any board returns to it. (my call) Both board icons get the link, as the
prototype has them. "Open the board" in the Ledger header opens the most recent run.

**D2 — The directory does not have to be a repo; Treko scans around it.** (user, revised mid-brainstorm;
this supersedes his earlier "only analyze directories that are repositories")

- **Down:** (user) scan the directory's child folders for repositories. (my call) Stop descending into
  a folder once it is a repo; skip hidden folders and `node_modules`; cap the depth at **5** levels so
  typing `~` cannot crawl the disk.
- **Up:** (user) scan upward up to **5** parent directories. (my call, his reading unconfirmed) Its
  purpose is to find the repo the directory sits inside, so `~/dev/memsearch/docs` analyzes
  `memsearch`.
- **Worktrees:** (user) "If it's a work tree, it should look at the related repos and other worktree."
  A worktree directory pulls in its main repo and every other worktree of that repo. (my call) A
  worktree is grouped under its main repo by git's common directory, so the same repo is never
  counted twice (anti-goal 4).
- **Nothing found:** (user) a **pop-up**, not inline text, and nothing is queued. (my call) Wording:
  "No git repository found in or around that directory." His first wording ("that directory is not a
  git repository") stopped being accurate once D2 widened the search.

**D3 — The other three boxes narrow the scan.** (my call, unconfirmed: he was asked what the Repo box
is for and answered by redefining D2 instead) **Repo** picks one of the discovered repos by folder
name. **Branch** and **Worktree** narrow within it, matching the prototype's subtitle "directory is
required — repo, branch and worktree narrow the scan". The builder check should confirm this reading
with him.

**D4 — Analyze starts now or queues.** (user) Clicking Analyze starts the analysis if nothing is
running, or adds it to the queue if something is. There is no per-item Analyze button. (my call) The
queue runs one at a time, oldest first; a waiting item can be removed (the prototype's ✕), a running
one cannot.

**D5 — The analysis runs on the server and outlives the page.** (user) "while an analysis is currently
active, the user should be able to go to the dashboard/ other runs, and when it goes back to the ledger
page, that analysis should still be going … a refresh doesnt stop the analysis". So the server owns
the queue and runs the job; the page only asks it for status and draws the answer. (my call) The queue
is stored on disk beside the runs, so waiting items survive a server restart. A job that was running
when the server stopped is shown as **interrupted** and is not silently restarted. ⚠️ The server
already exits after an idle period (`idle=1800s` in its banner); a running analysis must count as
activity, or the server can exit mid-job.

**D6 — Progress is real steps, never a timer.** (my call, from the anti-goal) The bar advances only
when the analyzer finishes a real stage, and the label names that stage. It may move in uneven jumps.
The stage list comes from what the analyzer actually does, never the prototype's invented one, which
includes "linking Rally stories" (there is no Rally, see below).

**D7 — The runs list.** (user) A finished analysis joins the list, and **Open** takes him to that run's
board. (my call) Each row shows what the prototype shows (name, analyzed-at, directory; counts of
repos, branches, worktrees and features; a tasks-done bar), computed from the run's own data only.
Delete keeps the prototype's confirm dialog and wording: the run leaves the Ledger and the board, and
"the analysis files on disk are not touched".

**D8 — The Artifacts path box.** (inherited) `treko-store-location.md:84-86` deferred "an `Artifacts
path · where snapshots are written` field, placeholder `~/.treko/runs` — placeholder text, not the
default" to this card. It is built as specified there.

**D9 — The run page has room for what comes next.** (my call) Card 5's fact 1 records that the board is
already wired for PR fields and only the producer is missing. This card adds no new board fields; it
makes sure a run that spans several repos (D2) renders correctly, since `branches[].repo` already
exists in the schema.

## Decisions carried to the relations card (user, 2026-11-02)

Recorded here so the relations card inherits them. **Not in this card's scope.**

- **No Rally.** "There is no rally stories. Only repo cards." A "story" is a repo card.
- **Spec and ADR links.** A card links to its split `.spec.md`, if any, and (my call) to each ADR it
  names by number ("ADR 0055" → `docs/decisions/0055-*.md`).
- **Parents, children, siblings mean both levels.** (user: "both")
  - Inside a card, from task numbering: 9 is the parent of 9a/9b/9c, and those three are siblings. No
    change to how cards are written.
  - Between cards, from a new optional frontmatter line `parent: <card-name>`. Children and siblings
    are derived. Cards without it show no family. The obvious existing pairs get backfilled, and the
    card template gains the optional line. (played back in full; he answered "Nope" to "anything
    wrong or missing?")
- **Blockers are task-level.** (user: "a test needs to be done or a fix has to be done before a test")
  A task line carries `blocked-by: <card>`, `<card>#<task>` or `<repo>:<card>#<task>`. Treko shows it
  **Blocked**, naming what it waits on, until that target is ticked or its card merged, then clears
  it by itself. `## Depends on` stays the card-level input to merge order. Neither is ever read from
  prose. (played back in full; he answered "Looks good")
- **Cross-repo dependencies.** (my guess, played back, not contradicted) `## Depends on` may name a
  card in another repo.

## Open for the builder check

- D2-up: confirm "up to 5 parents" means find the enclosing repo, not also scan the parents' other
  children.
- D3: confirm what the Repo box does.
- How one run covers several repos: run the analyzer per repo and merge, or teach it a directory. The
  emitted schema is "not ours to change" (`analyze.py` docstring), so either way the result has to
  fit the existing `run` object.
- What the Ledger shows when opened as `file://` (no server, so it cannot queue).
- The exact stage list for D6, read off the analyzer.

## Spec

Not yet written. See the "State of this file" note at the top.

## Tasks

Not yet written. The checklist follows the spec and the compliance judge.

## Verification

Appended during review.
