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
**Update 2026-11-02:** the builder check is done (see §Builder check results); D8 is still his to
answer, and the (my call) items listed there still need playing back to him.
**Update 2026-11-03:** D8 and the playback are done. The spec is now written, in
`treko-ledger.spec.md` (the user accepted its going over ADR 0017's 800-line cap), and its
open questions are answered in that file. **§Tasks is still unwritten.** Next: the compliance judge,
then his review, then the checklist.

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
**Confirmed (user, builder check 2026-11-02):** Repo picks which found repos to analyze, by folder
name. Branch and Worktree show only the matching cards **plus every card those depend on**, so the
merge order stays true.

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
**Decided (user, 2026-11-02):** the box shows the real store directory as read-only text, with no
Save. A working Save needs its own safety design first (`treko-store-location.md:104-107`) and is
not in this card.

**D9 — The run page has room for what comes next.** (my call) Card 5's fact 1 records that the board is
already wired for PR fields and only the producer is missing. This card adds no new board fields; it
makes sure a run that spans several repos (D2) renders correctly, since `branches[].repo` already
exists in the schema.

**D10 — Loosening the server's safety rule is this card's first task.** (user, builder check
2026-11-02) Today the page may send only one of three fixed command names and never any text
(`tracking-feature-state.spec.md:406-411` and `:689-693`; enforced at `server.py:592-598`). The
Ledger must send a directory plus the optional narrowing boxes, and ids to remove, delete or retry.
That rule says loosening it is a spec change plus a judge round, so task 1 writes an ADR for the new
commands and their arguments and gets it judged **before any Ledger screen is built**. The agreed
card order is unchanged. (my call) Defaults the ADR starts from: accept only a directory that
exists; status polling must not reset the idle timer (`server.py:650-652` resets it on every request
today, so a polling tab would keep the server alive indefinitely); git runs in scanned repos with
`core.fsmonitor` switched off, since a scanned repo's own config can name a program for git to run.

**D11 — Which copy of a card counts.** (user, builder check 2026-11-02) Each worktree holds its own
copy of every card, with its own phase and ticks, and today cards are read only from the folder the
analyzer was pointed at (`analyze.py:192-198`). Instead, cards are read from every worktree of the
repo. When a card names a `branch:` and that branch has a worktree, that worktree's copy wins;
otherwise the primary checkout's copy wins. Each card appears once.

**D12 — A run is refreshed in place; Delete hides it.** (user, builder check 2026-11-02) One run per
directory plus narrowing; analyzing it again replaces it. Today the store already replaces by id
(`store.py:127-143`), but the id is only the repo's folder name (`analyze.py:504`), so `~/dev/foo`
and `~/work/foo` would overwrite each other. (my call) The id is built from the full directory plus
any narrowing. Delete puts the run on a hide list the server keeps; analyzing it again takes it off.
Nothing on disk is erased, so the prototype's dialog wording ("the analysis files on disk are not
touched") stays true.

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

## Builder check results (2026-11-02)

A fresh Opus reader with no access to the brainstorm read this card and the code and returned seven
ranked questions. The planning session re-opened the citations below before writing them here. The
user answered four (D10, D11, D12, and D3's confirmation). **Still his: D8**, the Artifacts path box
(the builder found that its source, `treko-store-location.md:104-107`, keeps it display-only or
absent until its own design exists). Settled as (my call), not yet played back to him:

- **Several repos in one run.** Run `analyze.py` once per repo, unchanged, and merge in a new module
  that renumbers ids so they cannot collide: node ids (`analyze.py:333-338`), question ids
  (`:306-310`) and constraint ids (`:697-705`) all restart for each analysis. Leaving `analyze.py`
  untouched also keeps card 5's line citations valid.
- **`file://`.** The Ledger says there is no server and shows the launch command. It never lists the
  bundled sample as runs on disk. The board already treats `file://` as a supported copy-only mode
  (`Treko.dc.html:543-545`).
- **D6 stages.** The analyzer's real steps (`analyze()` at `analyze.py:463`), plus the Ledger's own
  directory scan, the per-repo loop and the store write. The analyzer prints nothing until it
  finishes and the server captures its output whole (`server.py:322-327`), so it has to learn to
  report each stage as it completes.
- **D2-up.** Finding the repo a directory sits inside is `git rev-parse --show-toplevel`, which the
  server already uses (`server.py:212-235`). The card's reading stands unless he says otherwise.
- **The board's Re-analyze button** re-queues the run on screen with its original request, instead
  of re-surveying the repo Treko was launched from (`server.py:601-603`).
- **After a server restart**, waiting items start on their own, since D4 removed the per-item
  Analyze click. An item that was interrupted mid-run waits for a Retry.

**Played back 2026-11-02:** the user accepted all six as written ("All six are fine"), and answered
D8 (read-only, above). ⚠️ **Correction, found after his answer (my call, to be told to him):** the
first bullet says `analyze.py` stays unchanged, but the D6 bullet needs the analyzer to report each
stage as it finishes, which it cannot do unchanged. Resolution: `analyze.py` gains one small optional
progress report and nothing else. Its emitted `run` object and its behaviour without that option stay
exactly as today. Card 5 cites `analyze.py` by line number and is still in planning, so those
citations must be re-checked when card 5 resumes.
**Update 2026-11-03 (after compliance round 1):** "nothing else" no longer holds. `analyze.py` also
gains `--card PATH` (OQ-1), and its card layer moves to a new `cards.py` to keep the file under 800
lines (a pure move). Both are covered by the byte-for-byte test. The spec also adds a fourth D10
default: status polls write no audit line. Details are in the spec, §1.1 and §2.

## Spec

Split into [`treko-ledger.spec.md`](treko-ledger.spec.md): design, wire contract, scenarios, acceptance criteria and open questions.

## Tasks

Not yet written. The checklist follows the spec and the compliance judge.

## Verification

Appended during review.
