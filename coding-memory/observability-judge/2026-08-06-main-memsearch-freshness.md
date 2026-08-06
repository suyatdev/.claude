# Observability judge — `memsearch-freshness` (architecting, advisory)

- **repo:** `.claude`
- **branch:** `main`
- **head_sha:** `9475034edc496f9c9ab8cf95f630e16deb878204`
- **stage:** `architecting` (advisory — does not gate a PR)
- **spec:** `docs/features/memsearch-freshness.md` (251 lines, `phase: planning`, `branch: none`)
- **spec blob sha:** `4e217ec323dd37701b2bc32b1c5a60e0cfefb6a7` (verified — matches invocation)
- **test command:** none supplied; no implementation code exists. Evidence below is read-only
  inspection of the live index and the `memsearch` package source.
- **judged:** 2026-08-06T20:33:25Z

> **Filename deviation, stated for the record.** The agent definition specifies
> `<date>-<branch_slug>.md`, which here resolves to `2026-08-06-main.md` — a file that **already
> exists** and holds a different architecting verdict (`memory-system-split` @ `0e70522`,
> 05:15:58Z). Writing to the literal path would have destroyed a prior audit record, the exact
> outcome the naming rule exists to prevent. I followed the directory's established
> disambiguation convention (cf. `…-round5/6/7.md`) and appended the feature name. The JSONL
> `branch` field remains the raw, unsanitized `main`.

**`execution` and `success_masking` are `fail`.** The design's central mechanism — reading
freshness from `status.json`'s `last_indexed` — does not measure index-run recency. It measures
*content-change* recency. Built as specified, the stale warning will fire during normal healthy
operation and its own stated remediation will not clear it. This is cheap to fix now, at design
time, which is the whole value of an architecting read. Everything else in this design is strong.

---

## What was changed

Nothing is built yet. This is a plan to fix a monitoring failure.

Think of a smoke detector that has been chirping "battery OK, battery OK" for nineteen days —
while the battery was flat the whole time. The memory search index froze on 18 July. Every
session start since then cheerfully announced *"2332 chunks of past-session memory indexed"*.
That number was true. It was also useless, because nothing was checking the thing that mattered:
**how old** the index was.

The plan has two halves, deliberately shipped together:

1. **Tell the truth about age.** The one-line session-start message gains an age: `indexed 3h ago`
   when fresh, `⚠ stale … run <command>` past 8 hours, or `age unknown` when it genuinely cannot
   tell. It is designed to *fail toward doubt* — never claim freshness it cannot prove.
2. **Actually refresh it.** A background `launchd` job re-indexes every 6 hours.

The second half is blind — if a refresh fails (Ollama down, job unloaded) it does not report
anything. So the age line in half one **is** the only alarm for half two. That is the design's own
stated load-bearing claim, and it is the right thing to have flagged for scrutiny.

## Does it do what you wanted?

**In intent, yes. In mechanism, no — and the gap is the whole ballgame.**

The design asks the alarm to answer *"is the index being refreshed?"* But the signal it reads
answers a different question: *"when did any indexed file last change?"*

Those two come apart badly. I confirmed this in the source, not by guessing:

- `last_indexed` is computed as `SELECT max(indexed_at) FROM sources` (`memsearch/db.py:156`).
- `indexed_at` is written in exactly two places, both inside `replace_source`
  (`db.py:121`, `db.py:125`).
- `replace_source` is only called when a file's content hash has **changed**. If the hash matches,
  `_index_one` counts a skip and returns without touching the row (`index.py:125-127`).

So **a perfectly successful refresh that finds nothing new does not move `last_indexed` at all.**

Play that forward. You stop work at 11pm. The 6-hour job runs at 1am and 7am, both succeed, both
find nothing changed. You start a session at 8am. Age is computed from last night's final file
change — about nine hours. The line reads **`⚠ stale — run ~/.claude/memsearch/bin/memsearch
index`**. You obey. It skips everything, changes nothing, and **the warning does not go away.**

That is the design's own falsifier (b) — *"a stale line is emitted while the index is younger than
`STALE_HOURS`"* — firing on an ordinary Tuesday morning, with no way for the user to silence it.
And it is precisely the outcome decision 1 argues is *"strictly worse than silence, because it
burns the one channel that reports the failure."* The threshold reasoning is sound; the signal
underneath it is not.

**On the specific questions asked:**

- **Is a session-start line an adequate monitor for a blind scheduler?** In principle yes — it is
  cheap, it is seen, and it is on the path of the person who cares. But only if it is *specific*.
  As designed it collapses three very different conditions into one identical message:
  (1) the scheduler is dead, (2) every source errored, (3) nothing changed and all is well.
  Case 3 is the common one, so the alarm's precision is poor by construction.
- **Is fresh/stale/unknown the right granularity?** It is missing a fourth real state:
  **in progress**. `_write_status` is called once, at the very end of `run_index`
  (`index.py:100`). During a run, `status.json` still shows the *previous* value. I verified this
  live: an index run has been going since 16:01 today and has written 315 rows dated 2026-08-06,
  while `status.json` still reads `2026-07-18T06:18:01+00:00`. Under this design that session
  would print "stale" and tell the user to launch a *second* concurrent indexer.
- **Does "fail toward doubt" hold on every path?** On the paths the spec enumerates, yes — absent,
  unparseable and future-dated all correctly route to unknown, and the exactly-8h boundary is
  pinned. The principle is well applied. The problem is the path the spec does not enumerate: a
  *valid, parseable, past-dated* `last_indexed` that is simply not a measure of what is being
  asked. It fails toward doubt about the wrong quantity.
- **Is the 8h-vs-6h reasoning sound?** The alert-fatigue argument is correct and well made, and
  putting the threshold above the interval is the right instinct. Two caveats. First, it assumes
  runs are instantaneous; the run in flight right now has been going 30+ minutes, which eats into a
  2-hour margin. Second, and decisively, the margin is irrelevant while the signal tracks content
  churn rather than run completion.
- **Is the blind measurement sound?** As a *protocol*, genuinely yes — committing queries before
  the rebuild is real methodological discipline and the acceptance bar (≥2 hits ≥0.30, top hit
  from the named feature, against a stated 0-hit / ~0.02 baseline) is specific, pre-registered and
  losable. It is not self-satisfying. But **the ordering has already been broken in the real
  world**: the rebuild is happening *now*, during `phase: planning`, and the five queries do not
  exist yet (task 6 is unstarted). All 11 `docs/features/` files are already indexed. Whoever
  writes those queries will be writing them against an index they can already query — which is
  exactly the bias blindness exists to exclude. Falsifier (d) only catches queries edited *after*
  the rebuild commit, so it does not detect this inverse ordering.

**What the design got right, and it is a lot.** I independently reproduced both documented
measurement traps and both are real: `memory.db`'s mtime reads today against a 18 July index
(because `log_query` writes on every query), and the unescaped `LIKE '%CODING_MEMORY%'` returns
**169** false hits versus **0** for the correctly escaped form. The item-2 "no-op" finding is
also correct — `~/.claude/docs` is already a `curated_docs` root and all 11 `docs/features/` files
have been picked up with no config change. Revising a parent spec on measured evidence, declining
item 6 because it depends on a result not yet in hand, and writing the falsifier before the code
are all senior moves.

## What could go wrong / what I'm unsure about

The irony worth naming: the spec carefully documents two traps of the form *"a proxy that looks
like the quantity you want but isn't"* — and then builds its central mechanism on a third one of
exactly the same species. It warns *"freshness must be read from `last_indexed`, never from a file
mtime."* But `last_indexed` is itself a proxy that does not track runs either. The reasoning
process was right; it stopped one step early.

Beyond that:

- **A totally failed run still exits 0.** `cli.py` collects per-source errors, prints them, and
  returns 0 regardless (`cli.py:60-66`); `_index_one` swallows every per-source exception and
  continues by design. With Ollama down, every source errors, the run "succeeds", `launchd` sees
  success, and the exit code carries no signal at all.
- **R4's "a failed run leaves evidence" is weaker than stated.** I confirmed the running indexer
  has fds 1 and 2 on `reindex.log`, and that log sat at **0 bytes for 30+ minutes** before
  flushing at 8202 bytes — classic 8KB block buffering. A graceful failure will flush and leave a
  traceback, so evidence mostly survives; but on a hard kill (OOM, `bootout` mid-run, power loss)
  the last buffer-full of progress is simply lost. No `PYTHONUNBUFFERED` is specified.
- **Concurrent runs are unguarded.** There is no lock, pidfile, or "already running" check
  anywhere in the package — I grepped for all of them. Today only humans start runs. This design
  adds an automated 6-hourly runner *and* a message that actively instructs the human to start
  one, with no mutual exclusion between them.
- **What still fails silently after this lands:** the index quietly indexing *nothing useful*
  (chunk count and age both look healthy while retrieval is garbage — R7 measures this once, at
  landing, and then never again); embedding-model drift; and a run that errors on every source but
  updates nothing, which is indistinguishable from a quiet period.

I am not certain how often a >8h quiet gap occurs in this user's actual pattern — that governs how
loud the false-stale problem is in practice. Transcripts change on every session, so during an
active day the signal will look fine. It is overnight and weekends where it misfires, which is
also when it is least likely to be investigated properly.

## What I'd double-check before merging

This is advisory and blocks nothing. There is no PR here and no code — the point is to fix these
on paper, where it is nearly free.

1. **Record run-completion time as its own fact.** Have `_write_status` write a distinct field
   (e.g. `last_run`) set to "now" when `run_index` completes, and read *that* for staleness. Keep
   `last_indexed` for content recency. They are two different questions and the spec currently has
   one field answering both.
2. **Add an "indexing in progress" state**, or write `status.json` at run start as well as at
   completion. Without it the nudge tells users to start a second concurrent indexer against a
   live SQLite database.
3. **Distinguish "ran and failed" from "ran and found nothing."** Persist the error count from
   `report["errors"]`, and consider making a run with zero processed sources and non-zero errors
   exit non-zero.
4. **Commit the five measurement queries before anything else touches the index** — and, since a
   rebuild has already run ahead of them, either re-run the measurement against a clean rebuild or
   state plainly in `## Verification` that the blindness guarantee was weakened. An honest
   downgrade is fine; a blindness claim that is not true is not.
5. **Add `PYTHONUNBUFFERED=1`** to the plist's `EnvironmentVariables` so the log is useful during
   a run and survives a hard kill.
6. **Re-check the spec's opening premise.** It states all 228 `sources` rows carry 18 July. As of
   now the table holds 511 rows with 315 dated today, from an out-of-band run. The diagnosis was
   right when written, but task 7's experiment has already been consumed.

---

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | **concern** | Goal, scope and framing are right; but R1's "the index's true age" is not achievable via the contract specified, which silently substitutes content recency for run recency. |
| `execution` | **fail** | Specified mechanism provably cannot satisfy R1/R2. A no-change run leaves `last_indexed` untouched (`db.py:121,125` via `index.py:125-127`), so a healthy scheduler yields false "stale" after any >8h quiet gap — and the stated remediation cannot clear it. Fires the design's own falsifier (b). |
| `trajectory` | **pass** | Genuinely evidence-led: both documented traps independently reproduced (mtime; 169 vs 0 on escaped `LIKE`), parent spec revised on measurement, item 2 correctly called a no-op, falsifier written before code. Flaw is real but is one step short of a sound chain, not luck. |
| `regression` | **concern** | Introduces an automated 6-hourly runner plus a human-directed remediation with no lock/pidfile anywhere in the package; concurrent runs against one SQLite DB become reachable. |
| `context_budget` | **pass** | At most one SessionStart line, unchanged from today. Explicitly bounded; no always-on rule growth. |
| `traceability` | **pass** | Strong: mermaid flow naming the load-bearing edge, per-file contracts, pinned toolchain measured not remembered, explicit "what success means". |
| `success_masking` | **fail** | Three conditions collapse to one identical alarm (scheduler dead / all sources errored / nothing changed). `memsearch index` exits 0 even when every source fails, so the exit code is not a signal. R4's "leaves evidence" is weakened by 8KB stdout buffering on hard kill. |
| `intent_drift` | **pass** | Unusually disciplined. Item 6 excluded with reason; four temptations explicitly listed as non-goals; no drive-by edits. |
| `checkpoint` | **pass** | Clean revert point: tree clean at `9475034`, planning phase, no branch, no code. Install path is idempotent (`bootout`/`bootstrap`) and fail-closed on `plutil -lint`. |
| `audit_trail` | **concern** | Excellent in-spec provenance, but R7's blindness ordering is already compromised in reality — the rebuild is in flight before the queries exist, and falsifier (d) does not detect that direction. |

**Risk:** high · **Confidence:** high

Confidence is high because every finding was verified against source or live state rather than
inferred: the two writers of `indexed_at`, the single end-of-run `_write_status` call, the absent
locking, the exit-0-on-all-errors path, and the buffered log with open fds.

## Concerns

1. `last_indexed` is `max(indexed_at)` = last *content change*, not last *run*; a healthy no-change run leaves it frozen, so false "stale" fires after any >8h quiet gap
2. The stated remediation (`run memsearch index`) cannot clear that false stale — a skip-everything run does not advance the field
3. No "indexing in progress" state; `_write_status` runs only at completion, so a live run reads as stale and invites a second concurrent indexer
4. No lock, pidfile or already-running guard anywhere in `memsearch/`, while the design adds an automated runner alongside human-triggered ones
5. `memsearch index` exits 0 even when every source errors, so `launchd` sees success and the exit code carries no signal
6. R4's "a failed run leaves evidence" weakened by 8KB stdout block buffering; a hard kill loses the last buffer-full. No `PYTHONUNBUFFERED` specified
7. Scheduler-dead, all-sources-errored, and nothing-changed are indistinguishable in the one alarm the design provides
8. R7 blindness already compromised: rebuild in flight during `phase: planning`, before the five queries exist; falsifier (d) does not catch this ordering
9. 8h-vs-6h margin analysis assumes instantaneous runs; the observed run has exceeded 30 minutes
10. Spec's opening premise (228 rows, all 2026-07-18) is now stale — 511 rows, 315 dated today; task 7's experiment already consumed by an out-of-band run
