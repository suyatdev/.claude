---
phase: implementation
model_tier: low
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
**Update 2026-11-03 (compliance round 2: fail, 3):** two ids repeated and went to him. His answers
are D13-D15. The spec is being revised for round 3.
**Update 2026-11-03 (compliance rounds 3 and 4):** round 3 failed with 2 new ids, answered by D16-D18;
round 4 failed with 1 new id, answered by D19, alongside D20-D21 from the observability read. Per D22,
round 5 is the last automatic round: its findings go to him as one list. §Tasks is still unwritten.
**Update 2026-11-05:** rounds 5 and 6, D27's waiver, his spec review (D28, D29) and his
confirmations (D30) are done, and the checklist is written: one line per task under §Tasks, with
the detail in the spec's closing section "Tasks, in detail (2026-11-05)". His answers from the
checklist review are D31–D34. Next: `gate confirmed`, then task 1.

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
*Correction (2026-11-05, my call):* `server.py:650-652` resets the idle timer once per accepted
**connection**, not on every request; the spec corrected this at round 3 (its §2, default 2). The
default itself is unchanged.

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

**D13 — The board keeps its address; the Ledger gets its own, and launch opens it.** (user,
compliance round 2, 2026-11-03) The first spec draft served the Ledger at `/` and moved the board to
`/board`. That was a (spec call), not his. Compliance round 2 cited `core-conduct/file-size` for the
second time, because the move forces edits to tests that load the board at `/`, one of them
`treko/test_nontext_contrast.py` (1,054 lines). He chose to keep the board at `/` unchanged, serve
the Ledger at its own address, and have launch open the Ledger. D1 still holds.

**D14 — A job can never stay "running" for ever.** (user, compliance round 2, 2026-11-03)
`core-conduct/explicit-error-handling` was cited twice in a row: a crash while combining per-repo
results, or an analyzer that cannot start (`server.py:330-331`), had no defined outcome. He chose
two specific failure messages, plus a catch-all that marks any crashed job failed and frees the
queue and the idle exit.

**D15 — Task 1 tests switching file filters off on a real LFS repo, then he decides.** (user,
compliance round 2, 2026-11-03) His earlier acceptance of the file-filter risk stands for now. The
observability read found that blanking a filter driver stopped it in a toy repo. Task 1 tries that on
a real Git LFS repo and shows him the result. If LFS-backed scanning still works, filters go off;
otherwise the accepted risk stays.
*Superseded by D20 (2026-11-03): filters stay on, decided without the test.*

**D16 — Close the two measured program routes; say plainly what is untested.** (user, compliance
round 3, 2026-11-03) Both judges measured a scanned repo's own config running a program with every
§2 protection on: `gpg.program` under `log.showSignature`, and a promisor lazy fetch. He chose to
close both (one setting each, each with a test) and to have the spec state that git's other config
keys have not been checked one by one.

**D17 — Git LFS is vetted and pinned as a test-only tool.** (user, compliance round 3, 2026-11-03)
Task 1's D15 test needs a real Git LFS repo, and `git-lfs` is not installed here. Vetted 2026-11-03:
Homebrew `git-lfs` 3.8.1, 0 stop / 0 caution, every check `not_run` for Homebrew (report:
`~/.claude/hooks/state/vetting/homebrew/git-lfs/3.8.1.md`). It is installed only in task 1, only
with his approval at the prompt.
*Superseded by D20 (2026-11-03): no LFS test, so git-lfs is not installed.*

**D18 — A repo whose `git status` fails shows "unknown", not "no changes".** (user, compliance round
3, 2026-11-03) Today the analyzer reports such a repo as clean. He chose "unknown" with a short note,
with the rest of that repo still shown.

**D19 — A box value that cannot be written as UTF-8 is refused like any other bad value.** (user,
compliance round 4, 2026-11-03) The round-4 compliance judge found that a request holding a lone
surrogate (for example `"/tmp/\ud800x"`) passes every field check and then crashes the byte-length
check, so the server hangs up with no code and no audit line. Re-measured here on `/usr/bin/python3`
3.9.6: `json.loads` accepts it and `.encode("utf-8")` raises `UnicodeEncodeError`. He chose the fix:
such a value answers `422 invalid_input` (`400 malformed` for `run`), with a §10 row and a criterion.

**D20 — File filters stay on, decided now; no Git LFS test, no git-lfs install.** (user, compliance
round 4, 2026-11-03) **Supersedes D15 and D17.** The round-4 observability read measured, with a
fake LFS-shaped driver, that switching filters off makes a stat-dirty LFS file read as modified, so
D15's test had a predictable answer ("keep them on"), and its falsifier wrapped `.clean`, which git
ignores when `.process` is set. He chose to decide now: filters stay on and remain the accepted risk
(his own `git status` in a terminal runs the same filters), and task 1 drops the LFS test and the
git-lfs install, so no tool whose vetting checks did not run gets installed.

**D21 — Two more "cannot check" cases get honest labels.** (user, compliance round 4, 2026-11-03)
Extends D18. A partial clone whose diff cannot be computed shows "unknown" with a short note instead
of an empty diff, and a worktree whose folder was deleted by hand shows "folder missing" instead of
"clean".

**D22 — One more judge round, then he picks.** (user, compliance round 4, 2026-11-03) After the
round-4 fixes, both judges run once more (round 5). Whatever they find goes to him as one list, and
only what he chooses gets fixed, with no further automatic rounds.

**D23 — A safety net for any request that crashes, plus two named refusals.** (user, round-5 list,
2026-11-03) The round-5 compliance judge measured two more inputs that make the server drop the
connection with no answer and no audit line, on code the Ledger reuses from `/command`: a token header
holding a non-ASCII byte (`hmac.compare_digest` raises `TypeError`; no valid token needed) and a body of
1024 `[` (`RecursionError`, which `server.py:589`'s `except (ValueError, UnicodeDecodeError)` does not
catch). Both re-measured here on `/usr/bin/python3` 3.9.6. He chose a request-thread catch-all that
answers `500` with one audit line, plus a refusal for each case (the token one stays inside the
collapsed `403 forbidden`; the bracket one is `400 malformed`). Because the code is shared, `/command`
gets the same protection.

**D24 — The shutdown put-back stays, written fully into the job lifecycle.** (user, round-5 list,
2026-11-03) Against my recommendation to drop it. A job whose first launch (its scan) is refused by
the closed registry puts its item back to `waiting`. Both round-5 reads found this exit missing from
§5.2's diagram, the "three exits" sentence, the `last_job_end` list and §5.6's write table, and D6's
falsifier unable to fire. He chose to keep the rule and write it in everywhere, with a failure rule for
the put-back write and a test that can tell the check from the put-back.

**D25 — "diff unknown" asks a question only for a branch a card names.** (user, round-5 list,
2026-11-03) Refines D21. The label stays wherever a diff cannot be measured, but a question is added
only when a card names that branch, since a diff is shown only on a card's tasks. The round-5
observability read measured a 12-branch blobless clone going from 2 questions to 14 without this.

**D26 — A narrow final check.** (user, round-5 list, 2026-11-03) After the round-5 fixes, the
compliance judge checks only whether those fixes were made correctly (round 6), not the whole spec
again. Whatever it finds goes to him; no loop.

**D27 — Fix round 6's five findings, then his review; further judge passes waived.** (user, round-6
list, 2026-11-03) The narrow round-6 check failed with five new ids, all inside the round-5 fixes:
`core-conduct/audit-sent-unsourced` (the catch-all logs `sent=no` on `/command` even when keystrokes
landed; fix: `sent=unknown` there, plus a hang-up test), `writing-specs/two-way-command-unchanged`
(§3.5 still says `/command` is unchanged), `writing-specs/a2-falsifier-outcome` (A2's sample value
lacks a trailing newline), `writing-specs/two-way-poll-banner` (the new banner has no clearing rule)
and `writing-specs/card-needs-a-task` (the new scenario and E7 need a card with a task). He chose to
have all five fixed and to **waive any further compliance or observability pass on the spec**: he
reviews it himself next, and the spec's own criteria catch what is left at build time. This waiver is
his explicit decision, recorded here as the spec-compliance gate requires.

**D28 — His spec review.** (user, 2026-11-04, sixteen questions, each with a recommendation; all
answered as recommended except the one in D29) Confirmed: `sent=unknown` for `/command`'s request
catch-all, widening the old spec's `unknown`; a request target such as `http://[` stays with the
catch-all's generic `500 internal_error`, with no code of its own; a status line `send_response` has
only buffered is dropped before the catch-all answers; the status-poll `internal_error` banner clears
at the next poll answered `200`; one `internal_error` code for a failed job and a failed request; the
catch-all logs `status=500` even after a client hang-up, with the hang-up in `errno`; the two new
`internal_error` messages as worded; the four (my call) answers OQ-1, OQ-3, OQ-7 and OQ-8's
tightening half; the spec's "Until round N" notes stay. Changed: the board's leftover
`reanalyze_failed` error entry, which `/command` can no longer return, is deleted with the Re-analyze
change; the "diff unknown" question is asked only when a card **with at least one task** names the
branch (refines D25); §15's two Python 3.9.6 rows become one; §8.3's row cache is dropped and rows
are computed on every request, added back only if measured slow (YAGNI); task 1 gains a bounded
check of git's config keys that can name a program, against the commands the scan and analyzer run.

**D29 — A tidy shutdown on SIGTERM and SIGHUP, in this card.** (user, 2026-11-04) Against my
recommendation to park it. A plain stop request (`kill`, logout) or a closed terminal runs the same
shutdown path as `Ctrl-C` (§5.3): registry closed, subprocess groups killed, the running item marked
`interrupted`. Until now both were a hard kill, which can leave a running analyzer behind as an
orphan in its own process group. He chose both signals over SIGTERM alone. D29 is new design added
after D27's waiver; asked, he chose no extra judge pass on it (user, 2026-11-04): D27's waiver covers
it, and its own criteria test it at build.

**D30 — The six calls made while folding D28 and D29, confirmed.** (user, 2026-11-04, each as
recommended) SIGTERM and SIGHUP get `signal.default_int_handler`, so they raise exactly what `Ctrl-C`
raises (measured 0.01 s to a tidy exit; the `httpd.shutdown()` thread route took 0.26 s, 1.8 s
before `serve_forever`). A second signal during shutdown, `Ctrl-C` included, is ignored, so a double
`Ctrl-C` no longer force-quits (measured: without it the item stays `running`). An inherited ignore
is respected, so under `nohup` SIGHUP does nothing and the parent-death check ends the server. C12
stays strict: it fails when git leaves its pin, until task 1's check is re-run, like the Chrome pin.
The board's `analysis_failed` message and tone go with the `reanalyze_failed` entry
(`Treko.dc.html:428`, `:535`; nothing else reaches them). The "two new messages" of D28 are §9.2's
request-answer row and §9.4's Re-analyze string, and OQ-1's confirmation covers its per-copy reading.

**D31 — The gate holds back only what a browser can reach.** (user, 2026-11-05) Against my
recommendation that every later task wait for task 1d's passing verdict, he chose "only the
screens wait". My reading, flagged to him: everything a browser can reach waits for that verdict,
meaning the new routes (`POST /ledger`, `GET /ledger`, `GET /ledger/status`), `/command`'s
changes, the Ledger page and the board's changes. The three splits, the analyzer's options, the
scan, the merge, the state module and the job runner may start right after `gate confirmed`,
before or alongside task 1. Task 1c's outcome can still change the protective-settings table
(D34), so the task that closes criterion C8 also waits for 1c.

**D32 — The task-1 ADR gets one judge round, then his list.** (user, 2026-11-05) One compliance
round, with the observability judge's architecting read alongside; the fixes it asks for; then
anything still open goes to him as one list, with no further automatic round.

**D33 — With git older than 2.45 the Ledger starts no analysis and says so.** (user, 2026-11-05)
The Ledger refuses to start an analysis and shows a clear message ("git 2.45 or newer needed"); the
board works exactly as today. The spec designs it in full: where and when the check runs, its
code, its rows and its criterion (spec §2 default 3, §3.5, §9.2, criterion A9).

**D34 — A task-1 finding that needs a spec change comes to him first.** (user, 2026-11-05) If task
1c finds a config key that fires, or task 1d's judge asks for a spec change, the builder stops and
brings it to him; the spec changes only with his OK.

**D35 — Split 1 edits `treko/test_analyze_options.py`, once.** (user, 2026-11-05, asked during task 3)
The spec said split 1 needs no test edit. That was wrong: E2's falsifier reads the `"docs" / "features"`
literal from `analyze.py`, and the move put it in `cards.py`, so two falsifier tests failed. He chose to
edit that one test (it now reads the literal from `cards.py` and writes a mutant `cards.py` beside the
real `analyze.py`). Task 3 and Z3 are amended in the spec by a dated note; no other test changed.

**D36 — `filter.<driver>.process` is covered by the accepted risk D20.** (user, 2026-11-05, asked
during task 1c) Task 1c measured that this key still runs a program from a scanned repository under
every section 9 setting (the analyzer ran it once per checkout; the scan's three commands did not).
He accepted it as the same class as `filter.<driver>.clean`, which D20 already accepts. No new
protective setting. ADR 0056's row for the key records this.

**D37 — ADR 0056 may exceed the 800-line cap.** (user, 2026-11-05, asked after task 1b) The 265-row
config-key table makes it 813 lines. Task 41's budget test must name this one file as an exception.
**Update 2026-11-06:** after task 1d's corrections the ADR is 843 lines (a new paragraph on branch
names in section 10 and wording corrections); task 41's exception names the file, not a size.

**D38 — Branch names from a scanned repository are never read as git options.** (user, 2026-11-06,
asked after task 1d) Both judges found that `analyze.py` passed branch names to git as bare
arguments, so a branch named `--output=<file>` overwrote that file (reproduced by hand). He chose to
fix it now: `--end-of-options` before every repository-sourced ref in the analyzer's four such
calls (commit `de5d087`, test `treko/test_analyze_refs.py` red at `25fbe00`), ADR 0056 section 10
records it, and the spec gains criterion C13.

**D39 — File filters stay on (D20 re-confirmed).** (user, 2026-11-06, asked after task 1d) The
observability judge reported that the filter does run for a repository unpacked from an archive
(0 runs in the original checkout, 1 after a `tar` round trip; not re-run by the builder). He kept the
risk accepted. ADR 0056 section 11 records it. This was the last item on task 1d's list, so task 1d
is closed on his answers and browser-reachable work (D31) may proceed.

**D40 — E7 lives in a new file.** (user, 2026-11-06, asked before task 8) `treko/test_analyze_options.py`
is 750 lines after task 7 (cap 800) and E7 needs about 150. He chose a new file,
`treko/test_analyze_diff_unknown.py`, reusing the old file's helpers by import, instead of the file
name the spec's task 8 gives (`test_analyze_options.py`). Criterion E7 and task 8 are otherwise as written.

**D41 — Task 9 names its public functions.** (user, 2026-11-08, asked before task 9) The spec named
`ledger_state.py` and the shapes it holds but no function a test could call. He approved:
`run_id(directory, repo, branch, worktree)` (the §8.1 recipe), `run_name`, `run_dir`, `queue_label`
and `run_rows(runs, hidden)`; a figure whose key a run lacks is the string `"—"`, never `None`
or `0`; `canDelete` is true when more than one run is visible, hidden runs excluded first; ties and a
missing `analyzedAt` sort as §8.3 already says. Directory canonicalising (`expanduser`, then
`realpath`, §3.4) stays with the caller. Criteria G1, G4 and task 9 are otherwise as written.

**D42 — Task 10 fixes what the merge is handed, and five small readings of §7.** (user,
2026-11-09, asked before task 10; recorded on Opus 5.5 max) §7 said only that a part is "one
family's analyzer run and root, or that family's failure". He approved, as recommended:
1. **A part** is `{"root", "label", "questions", "run"}` for a family the analyzer finished, and
   `{"root", "label", "questions", "failure": {"exit", "timedOut", "stderr"}}` for one it did not.
   `root` is the family's canonical primary checkout, `label` its folder name (§4.4's family label),
   `questions` §4.4's per-family scan questions as `{"q", "ctx"}`, `run` the analyzer's run, `exit`
   the exit status or `null`, `timedOut` a boolean, `stderr` the analyzer's last stderr line.
   `request` is §5.1's `{"directory", "repo", "branch", "worktree"}`; `scan_questions` is §4.4's
   list of `{"q", "ctx"}`, already worded by the scan.
2. **Graph spacing.** A family's top row sits one empty row below the previous family's bottom
   row: its first `y` is the previous family's largest `y` plus `2 * analyze.GRAPH_DY`. A family
   with no nodes, a failed one included, takes no space.
3. **The overlap check** (F2) pins that no two nodes share an `(x, y)` and the spacing in item 2.
   It pins no box size, since §7.4 says 188 and the board's CSS says 180.
4. **Colliding folder names** (OQ-3) change only the three places §7.1 lists, `tasks[].repo`,
   `branches[].repo` and the kanban `m` prefix, plus the `<label>` in §7.2's failed-family question.
   Question text the analyzer wrote keeps the folder name.
5. **The merged cycle wave** is numbered one past the longest family's layered waves, or `"1"`
   when no family has a layered wave.
6. **Question order** is §7.1's, with each family's `questions` placed just before that family's
   analyzer questions; then all are renumbered `q1…qN`.
Criteria F1-F3 and task 10 are otherwise as written.

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

One line per task. The detail of each (files, the criteria it owns, the existing-test edits it
carries, its proof and what it waits for) is in the spec's closing section, "Tasks, in detail
(2026-11-05)". The text before each em dash is the task's identity and must match the spec's list
(`hooks/lib/feature_tasks.py`). In both lists a bare "D1"–"D15" or "F1"–"F3" is a criterion of
spec §11; a card decision is written "decision D10", and a round-2 fix "fix F4".

- [x] 1 — Write the decision record (ADR) that lets the page send the server a directory (decision D10's gate) (done, 055f367)
- [x] 1a — Write the test that checks the ADR's config-key table covers git's documented list (C12, red) (done, a331275)
- [x] 1b — Read every candidate config key once and sort it (done, 11ce571)
- [x] 1c — Measure each remaining key in a scratch repository; stop and ask on any that fires (C12 green) (done, b96ffa0)
- [x] 1d — Have the ADR judged: one round, its fixes, then his list (decisions D32, D34) (done, his answers D38 and D39)
- [x] 2 — Prove the analyzer unchanged with a byte-for-byte comparison, before anything moves (E2) (done, 9fcc4c4)
- [x] 3 — Move the analyzer's card-reading code into `cards.py`, changing nothing (split 1) (done, 4df4a97)
- [x] 4 — Move the server's keystroke-sending code into `channel.py`, changing nothing (split 2) (done, ec50497)
- [x] 5 — Move the board's button logic into `board-commands.js`, changing nothing (split 3; Z3) (done, b36c4fd)
- [x] 6 — Teach the analyzer to report each finished stage and to read a given list of cards (E1, E5) (done, cff838d)
- [x] 7 — Make the analyzer say "changes unknown" and "folder missing" instead of a false "clean" (E6, E8) (done, red 3e1b0db, green dd6607e)
- [x] 8 — Make the analyzer say "diff unknown", and ask why only where the value shows (E7) (done, red cc87e18, green 12fafb9)
- [x] 9 — Give each run a stable id, a name and a list row computed from its own data (G1, G4) (done, red 780f7ad and e9e3f3c, green 24f3a1b, Ledger tests a8241d3)
- [x] 10 — Combine several repositories' results into one run (F1, F2, F3) (done, red a1bdcab, green f657f5e)
- [x] 11 — Find every repository in and around a typed directory, each counted once (C1, C2, C3, C6) (done, red 5d78199, green e44336c; tests in treko/test_ledger_scan_more.py)
- [ ] 12 — Narrow the scan by repo, branch or worktree, and pick each card's live copy (C4, C5)
- [ ] 13 — Start every scan and analyzer one safe way: protected, in its own group, time-limited, stoppable (C7)
- [ ] 14 — Serve the Ledger page and its status answer beside the unchanged board (A1, A7)
- [ ] 15 — Keep the queue in a file that survives restarts, with one server per store folder (D5)
- [ ] 16 — Refuse every bad request to POST /ledger before it touches the disk or git (A3)
- [ ] 17 — Accept an analysis: scan at once, then queue it, or refuse it with a reason (A5, G7)
- [ ] 18 — Remove a waiting item, retry a failed one, hide a run (G5)
- [ ] 19 — Run queued analyses one at a time, with progress that moves only on real stages (E4, D7)
- [ ] 20 — Give each way a job can fail its own code and reason (D12, D13)
- [ ] 21 — Make sure no job can stay "running" for ever (D14, D15)
- [ ] 22 — After a restart, mark the interrupted job and start the waiting ones; polling alone never keeps the server awake (D3, D4, B2)
- [ ] 23 — Stop cleanly: no new work, every process killed, the job marked interrupted (D6)
- [ ] 24 — Shut down as tidily on a stop request or a closed terminal as on Ctrl-C (B3)
- [ ] 25 — Check that every way a job ends restarts the idle clock and keeps its reason (B1, D11)
- [ ] 26 — Decide, case by case, what happens when the queue file cannot be written (D10)
- [ ] 27 — Check the queue's order, its state changes, and two tabs racing (D1, D2, D9)
- [ ] 28 — Hidden runs leave both pages and come back on re-analysis; old-style runs re-analyze (G2, G3, G6)
- [ ] 29 — First launch queues the launch repository, and launching opens the Ledger (D8)
- [ ] 29a — With git older than 2.45, start no analysis and say so (A9; decision D33)
- [ ] 30 — Prove the protected environment cannot be bypassed (C8)
- [ ] 31 — Prove the token never leaks, and that everything runs on Python 3.9.6 (A6, Z1)
- [ ] 32 — Prove a scanned repository cannot make git run its programs or write into it (C9, C10, C11)
- [ ] 33 — Write the Ledger page's messages and progress logic as small testable pieces (H1, H9, H11, E3)
- [ ] 34 — Show the queue and the finished runs on the Ledger (H5, H8)
- [ ] 35 — Let the user type a directory and press Analyze, with pop-ups and the no-server notice (H2, H3)
- [ ] 36 — Link the board's Treko icons back to the Ledger, and size its graph to fit (H4, H7)
- [ ] 37 — Move the board's Re-analyze onto the Ledger queue, then re-pin the fence (H6, H10)
- [ ] 38 — Take Re-analyze off the command route (A4)
- [ ] 39 — Answer and log any request that crashes, and check every refusal both ways (A8, A2)
- [ ] 40 — Update the Treko skill to describe the Ledger as built (I)
- [ ] 41 — Turn the file-size budgets into a test (Z2)
- [ ] 42 — Run the whole suite once on the finished branch and record it
- [ ] 43 — Have the finished change judged before the pull request

## Verification

Appended during review.
