# Observability verdict — memsearch freshness (architecting, loop 2 round 3)

- **Repo:** `.claude` · **Branch:** `main` · **HEAD:** `24e6e29e0a37ccfcf484f85518787c9fecf02b67`
- **Stage:** `architecting` (advisory — does not gate the PR)
- **Design:** `docs/features/memsearch-freshness.md` (working tree, uncommitted), blob
  `391c4cba3bda6f6203e6187eece8b620431e74b3`
- **Judged:** 2026-08-07T02:52:55Z
- **Risk:** medium · **Confidence:** high

Baseline evidence run (no test command was supplied; no implementation exists yet):
`uv run pytest -q` in `memsearch/` → **63 passed, 16 deselected in 0.23s**. The 16 deselected are
exactly the golden retrieval tests, confirming the spec's `pyproject.toml:23 addopts = "-m 'not
golden'"` claim first-hand.

---

## What was changed

Nothing has been built yet — this is a blueprint, not code. The blueprint fixes a problem where the
memory index quietly stopped updating for 19 days while the message at the top of every session kept
cheerfully announcing how many chunks were indexed. It was vouching for a two-week-old index.

The blueprint has two halves that must ship together:

- **A timer.** A macOS background job (`launchd`) re-runs the indexer every 6 hours, and can be both
  installed *and* uninstalled from a script in the repo.
- **A truthful status line.** The session-start message now says *when* the indexer last finished,
  and refuses to say "fresh" unless it can prove it. It has six things it can say: fresh, stale,
  a run is in progress, a run looks stuck, the last run had errors, or "I don't know how old this
  is."

Think of it as a milk carton. Before, the fridge just said "milk present." Now it prints the
sell-by date, and if the date is missing or smudged it says "date unknown" rather than "fresh."

A third piece rides along: the big `CODING_MEMORY.md` session diary finally gets indexed, at a new
lower priority tier so it never outranks a real decision record.

## Does it do what you wanted?

Mostly yes, and the freshness half is in good shape. Six things were fixed since the last review and
I verified all six landed:

| Prior finding | Status now |
|---|---|
| Golden retrieval tests silently skipped | **Closed** — task 10 now runs `-m golden` |
| Task 9 timed a warm run, not the worst case | **Closed** — task 9 now times a cold `--full` run |
| No prune path when you undo the diary indexing | **Disclosed**, not fixed — cost is now stated up front |
| Entry-time status write would zero the chunk count | **Closed** — carry-over rule, and I confirmed `--full` really does delete the DB before reconnecting |
| Torn status file from a killed run | **Closed** — both writes now atomic (today's `write_text` is genuinely non-atomic) |
| Test fixture pre-created the state under test | **Closed** — new case gets its own config, not the shared fixture |

Every one of roughly fifteen code references I spot-checked in the spec is accurate — line numbers,
function behaviour, even the note that this machine has no `timeout` binary (I hit that myself).
That is unusually high precision and it is why my confidence is high.

**The gap is on the diary half.** The spec's reason for indexing `CODING_MEMORY.md` is that "three
weeks of *decisions and history*" live only there. But I verified `chunk.py:111`: a chunk is tagged
`decision` only if the word "decisions" appears in its path — otherwise `doc`. So the diary's chunks
get filed as generic `doc`. The session-start line you read every day advertises
`--type decision|episodic|doc`. Ask it for `--type decision` — the natural way to ask "why did we
decide X" — and the diary never comes back. Same for its date: every one of ~30 sessions gets
stamped with the file's last-modified date, so it all looks like it happened today.

So R10 half-delivers: plain searches will find the diary, typed searches won't. That's been raised
three rounds running and still isn't in the spec or in its non-goals.

## What could go wrong / what I'm unsure about

**You asked directly: is one session-start line enough, and does the log file close the gap?**
My answer is that the log and the error count **narrow** the gap a lot but do **not** close it.

1. **The monitor can't prove it's alive.** The line stays silent on every error — that's deliberate,
   so it never breaks a session start. But it means "the timer died," "the status file was deleted,"
   and "the hook isn't wired up" all look identical: nothing at all. A smoke alarm that goes quiet
   when its own battery dies. There *is* a registration test planned, which catches the wiring case;
   at runtime, silence stays unfalsifiable.
2. **A dead timer after a crashed run says the wrong thing.** A killed run leaves a permanent "run in
   progress" marker. Normally the next run clears it — but if the timer is dead there *is* no next
   run. So you get "⚠ index run stuck, check for a running memsearch index" forever. You check, find
   no process, and are never told the actual problem: the scheduler is gone. That's the load-bearing
   monitor pointing at the wrong cause in exactly the failure it exists to catch. The spec's own
   falsifier (c) — "the agent stops and nothing surfaces it" — would read as *passed*, because
   something did surface. It just lied.
3. **The log exists but nothing points at it.** `scheduled-index.log` with unbuffered output is a
   genuinely good call and will hold the real cause. But every remediation string says "run
   memsearch index" or "check for a running one" — never "read the log." The one alert with a root
   cause sitting in a file doesn't route you to the file. Third round raised; it's a one-string fix.
4. **The error warning can never be dismissed.** One permanently-broken file makes ⚠ fire on every
   session forever. The spec argues eloquently (decision 1) that a warning firing most sessions
   "trains the reader to ignore it — strictly worse than silence." That argument is never applied to
   its own error row.
5. **The line-number list has been wrong twice.** The spec names plan-file lines 19 and 2828 to
   correct. I confirmed 2890 and 2942 also restate the retired rule, inside the indexed corpus — so
   by the spec's own standard ("a missed line becomes a retired rule the index serves as current"),
   the list is incomplete again. Hand-listed line numbers in a 3,079-line file also shift the moment
   you start editing it. Stop patching the list; `grep -rn CODING_MEMORY` at implementation time.
6. **The measuring instrument runs once, on a target that keeps growing.** R9 scores retrieval after
   the diary lands. The diary is already 294,558 characters — bigger than the 285,187 the spec
   measured — and grows every session. Re-measuring on any cadence is an explicit non-goal.
7. Minor: `scheduled-index.log` has no rotation (one full run already produced 63KB); `RUN_MAX_HOURS`
   is still picked from the refresh interval rather than a measurement, so task 9 can still come back
   above 6h and force a late re-decision.

**What I am *not* worried about:** the false-green found two rounds ago is genuinely fixed. Adding
the file to `curated_docs` is the part that makes it reachable, and I confirmed `~/.claude` is not
otherwise walked. The fresh line now carries an age, so the positive case proves its own claim —
that alone is the core defect closed.

## What I'd double-check before merging

1. Decide, on purpose, whether the diary should answer `--type decision`/`episodic` queries. If yes
   it's a small change to how chunks are tagged; if no, write it into the non-goals so it stops
   surfacing every review.
2. Add one sentence: what happens when `last_run_errors` is missing or isn't a number. Usability is
   currently defined for timestamps only.
3. Put `scheduled-index.log` in the degraded and stuck lines. One string, closes the evidence loop.
4. Make "stuck" decay into "stale" after some multiple of `RUN_MAX_HOURS`, so a dead scheduler can't
   hide behind a stuck marker forever.
5. Replace the hand-listed plan-file line numbers with a grep sweep at implementation time.
6. Task 9's cold-run figure gates `RUN_MAX_HOURS` — hold the constant open until that number exists.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | concern | Freshness half is on target; R10's stated purpose ("decisions and history") only half-lands because the archive is typed `doc` and dated by mtime |
| `execution` | concern | No code yet; baseline suite verified green (63/16). Test plan is unusually strong. `RUN_MAX_HOURS` still rests on an unmeasured run |
| `trajectory` | pass | ~15 code claims spot-checked, all accurate; three measurement traps and two of the spec's own prior errors recorded rather than quietly corrected; the `--full`-unlinks-before-connect catch is real and non-obvious |
| `regression` | concern | Guard deletion touches every `load_config` caller — correctly pre-identified, as are the +1 `processed` counts and the split compound assertion. Plan-file enumeration still incomplete; `cfg.weights[st]` KeyError on a partial apply is swallowed to exit 0 |
| `context_budget` | pass | Nothing added to always-on context; nudge stays one line, one `python3` call, no CLI invocation. Actively protected by R4 |
| `traceability` | concern | Design documentation is exemplary (two ADRs, falsifier written before code). Runtime side thins out: the one alert with a waiting root cause never names the log holding it |
| `success_masking` | concern | Several real masks named and closed (exit-0-on-failure, fixture premise, deselected golden tests). Remaining: no unusable-value rule for `last_run_errors`; falsifier (c) self-certifies via the stuck line; R9 measures a growing corpus once |
| `intent_drift` | pass | Scope disciplined and argued; item 6 excluded on stated principle; seven non-goals, two of them admissions rather than exclusions |
| `checkpoint` | concern | R7's `launchd` uninstall is first-class precisely because `git revert` can't reach `~/Library/LaunchAgents` — excellent. R10's revert cost is now disclosed but not solved: no prune path, only a multi-hour `index --full` purges |
| `audit_trail` | pass | Two ADRs planned, dated evidence, user decisions attributed by date, prior errors preserved in the text |

## Concerns

- `recall_type` for the archive is `doc` (`chunk.py:111` verified); `--type decision|episodic` never
  returns the history R10 exists to expose (3rd round)
- `session_date` for the archive is the file mtime (`_mtime_date`), so ~30 sessions of narrative date
  to the run; `--since` mis-filters it (3rd round)
- the degraded line still points at re-running the indexer, never at `scheduled-index.log`, the
  evidence R6 creates (3rd round)
- a permanently-failing source pins the degraded warning on forever — decision 1's own alert-fatigue
  argument is never applied to its own error row (3rd round)
- `last_run_errors` still has no unusable/missing rule; usability is defined for timestamps only
  (3rd round)
- a dead scheduler after a crashed run reads "stuck", not "stale", so falsifier (c) self-certifies
  while the monitor names the wrong cause
- plan-file line list still names only 19 and 2828; 2890 and 2942 verified as restating the retired
  premise inside the indexed corpus
- hand-listed line numbers across a 3,079-line file shift on edit; enumerate by grep at
  implementation time rather than patching the list a third time
- the monitor has no runtime liveness signal: dead scheduler, deleted `status.json`, and an
  unregistered hook all render identically as silence
- `scheduled-index.log` has no rotation or size cap; 4 runs/day append forever (`reindex.log` is
  already 63KB from a single run)
- `RUN_MAX_HOURS=6` is still chosen against the refresh interval rather than a measurement; task 9
  can still return a cold figure above it
- R9 measures a monotonically growing corpus exactly once; re-measurement is an explicit non-goal
  (`CODING_MEMORY.md` is already 294,558 chars vs the spec's measured 285,187)
