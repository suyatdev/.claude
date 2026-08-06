# Observability verdict — memsearch freshness (round 4, architecting)

- **Repo:** `.claude` · **Branch:** `main` · **HEAD:** `51c5dee8734cffd26ee8d9ab4a4cff88c32eb6b6`
- **Stage:** `architecting` (advisory — blocks nothing)
- **Spec:** `docs/features/memsearch-freshness.md` @ blob `50ad053a5a11402833614f54d410edcd390d18f8`
- **Diff scored:** none — `phase: planning`, `branch: none`, no implementation code exists
- **Timestamp:** 2026-08-06T22:20:33Z
- **Prior rounds:** round 1 (`risk=high`) · round 2 (`risk=medium`, `success_masking=fail`) · round 3 (`risk=medium`)

> Filename keeps the `<date>-<branch_slug>-<feature>-round<N>` convention used by rounds 1–3 on this
> branch. A bare `2026-08-06-main.md` would overwrite them and destroy the audit trail this gate exists
> to keep.

---

## Lead finding: my round-3 top concern was wrong, and I am retracting it

Round 3's headline was *"the scheduler will not actually fire every 6h, and the stale line will cry
wolf … most mornings."* The man-page half of that is right and I re-read it to be sure:

> `StartInterval` — *"If the system is asleep during the time of the next scheduled interval firing,
> that interval will be missed due to shortcomings in kqueue(3)."*

The half I never checked — and should have, since the whole finding hung on it — is whether **this
machine sleeps**. Measured just now:

| Probe | Result |
|---|---|
| `sysctl hw.model` | `Mac16,9` — a desktop. `pmset -g batt` reports AC only; there is no battery profile. |
| `pmset -g custom` | `sleep 0` (system sleep disabled on AC), `standby 0`, `autorestart 1`. Only `displaysleep 120` is set. |
| `pmset -g log`, 2026-07-30 → now | **zero** `Entering Sleep` / `Wake from` / `DarkWake` events across 17,103 lines |
| `uptime` | **18 days, 2:13** — no reboot since 2026-07-19 |

So the premise "an overnight-asleep laptop misses the 4am run" — restated in the round-4 brief as the
concern to judge — **does not describe the host this ships to**. On a desktop configured never to
sleep, `StartInterval` firings land, and decision 1's argument ("the threshold sits above the
interval so it fires only when a run has genuinely been missed") holds as written. `RunAtLoad: true`
covers the remaining discontinuity, a reboot.

What survives is much smaller and is documentation, not design: **nothing in the spec records that
`StartInterval` is safe here *because* the host never sleeps.** Decision 4 picks `launchd` and names
one weakness (it runs blind). The sleep caveat is not mentioned, so the day this plist is installed on
a laptop — or the day `pmset sleep` is re-enabled — the alarm channel quietly degrades with no note
anywhere saying why. One sentence next to decision 4, and the `pmset` evidence above, closes it.
`StartCalendarInterval` (which the same man page documents as firing on wake and coalescing missed
events) remains the portable choice if that matters; on this host it buys nothing.

I am recording this prominently because a judge's job is to be checkable, and round 3's finding drove
the risk rating for two rounds on an unverified premise. That is the same error class the spec itself
catalogues three times — a plausible proxy accepted for the quantity you actually want.

---

## The two "addressed" claims verify

**The fabricated duration — genuinely fixed, and fixed at the level of the class.** The spec no
longer states a duration. It names the wrong number, explains *why* it was wrong ("a stopwatch glance
recorded as a finish time"), files it alongside the three other measurement traps, says the true
duration is unmeasured and may exceed `RUN_MAX_HOURS`, and routes the constant to the user via task 8
rather than quietly widening it. That is better than a correction; it is a retraction with a
mechanism. Live check, same run, right now: **PID 30022 at `02:23:51` elapsed, still running**, 708
`sources` rows (196 at `2026-07-18`, 512 at `2026-08-06`), `status.json` still reading `Jul 18 /
228 sources / 2332 chunks`. The number the spec now refuses to claim is still un-claimable.

That live state is also, again, direct proof the core fix is right: this session's own `SessionStart`
line announced *"2332 chunks"* while the DB holds 708 sources, because `_write_status` runs only at
`run_index`'s exit (`index.py:100`, verified). `run_started` is exactly the missing stamp.

**R8's removal — verified, and the cross-repo reach is gone with it.** `R8` is now the README
obligation; `memsearch/config.json` is untouched; the exclusion scenario asserts survival rather than
removal. Every load-bearing claim in the new non-goal checks out against source:
`config.py:56-59` raises `ConfigError` when no exclude pattern contains `CODING_MEMORY.md`;
`test_config.py::test_coding_memory_exclusion_is_mandatory` and `test_index.py:93` pin it. The golden
query (`golden_queries.json:4`, *"why is CODING_MEMORY.md excluded…"* → `memory-rag-index-design`) is
now correct rather than green-over-a-false-premise, which dissolves round-3 concern 8, and the design
doc is no longer falsified, which dissolves concern 9. The non-goal also carries an honest
counterpoint — that the "ephemeral working index" rationale may have expired — recorded for the next
person instead of assumed here. Round-3 concerns 7, 8 and 9: closed by scope reduction.

---

## New this round

**1 — `last_run_errors` has no unusable-value rule, and its natural default fails toward
reassurance.** R2 establishes *fail toward doubt* and the classification table applies it to both
timestamps: *"a timestamp is usable only if it parses and is not in the future; an unusable one is
treated exactly as absent."* Nothing says anything about `last_run_errors`. If it is absent, `null`,
a string, or negative, the obvious implementation — `int(status.get("last_run_errors", 0))` inside a
`try` — yields **0**, and row 6 prints the **fresh** line. That is a false green in the one channel
this feature exists to build, arriving through the field round 2 marked `fail`. Cheap: state that an
unusable `last_run_errors` is treated as unknown and suppresses the fresh line.

**2 — the degraded line can become permanent noise, which is decision 1's failure mode through a
different door.** `_index_one` catches per-file exceptions and continues (`index.py:135-137`), so one
permanently unprocessable source — a transcript that fails digest, a file over the context cap —
errors on **every** run forever. `last_run_errors` stays at 1, the degraded line fires at every
session start forever, and its remediation is *"run `memsearch index`"*, which reproduces the error.
Decision 1 argues at length that a warning firing on ordinary days is *"strictly worse than
silence"*; R3's degraded row has no protection against exactly that. (Not currently live: the running
backfill shows 247 `indexed` lines and **0** `ERROR` lines.)

**3 — the degraded line points at the wrong evidence.** R6 creates `scheduled-index.log` specifically
"so a failed run leaves evidence." The one line that reports a failed run never mentions it, and
tells the reader to re-run the indexer instead. For the Ollama-down case the actionable step is
reading the log, not a 2h+ re-run. A design that builds an evidence trail and then routes the reader
past it is worth one word of the line's budget.

---

## Round-3 items still open (7 of 11)

| # | Item | Status |
|---|---|---|
| 1 | `StartInterval` misses firings during sleep | **Retracted as a defect** (host never sleeps); survives only as an unrecorded assumption |
| 2 | Morning false-stale carries the remediation | Falls with 1 |
| 3 | `RUN_MAX_HOURS=6` justified by an overlap the man page says cannot happen | **Open, unchanged.** Re-read at line 352: *"If the job is running during an interval firing, that interval firing will likewise be missed."* The spec still says a run outlasting the interval is *"by definition the pathological overlap."* The measurement paragraph beside it was rewritten; the rationale was not |
| 4 | The 1h26m partial elapsed | **Closed** |
| 5 | In-progress/stuck outranks degraded, no marker | **Open** — but smaller than I said. Round 3 assumed 2–3h runs; that is the *backfill*. Steady state is ~25 new sources/day against 6h ticks ≈ minutes per run, so the masking window is minutes, not hours. It stays open **indefinitely** only after a crashed run, where `run_started > last_run` persists and rows 1–2 win forever |
| 6 | Stale-vs-degraded tie-break pinned by no scenario | **Open** — 14 nudge scenarios still cover no precedence pair, and precedence is where a 6-row table's bugs live |
| 7–9 | R8's cross-repo reach, the "will now fail correctly" prediction, the falsified design doc | **All closed by R8's removal** |
| 10 | Non-atomic `write_text`, now twice per run | **Open** — `index.py:67` is still a bare `write_text`; neither fixed nor non-goaled. A torn file lands in the malformed-JSON branch → **silence**, not the unknown-age line |
| 11 | Falsifier (c) mis-describes its own signal | **Open** — an agent that dies *mid-run* surfaces as **stuck**, never stale, so (c) reads as failed while the design worked |

Smaller, new, one line each: the contract does not say what the completion write does with
`run_started` (leaving it is correct — `run_started < last_run` falls through — but it is unstated),
and it does not say what the entry write does if the existing `status.json` is unreadable and the
prior `last_run` cannot be preserved (harmless: the run reads as in-progress, then re-stamps).

## Evidence I ran myself

- `bash hooks/memsearch-nudge.test.sh` → **5/5 passed, exit 0**. The 14 new scenarios are additive to
  a harness that works. Hook registration confirmed at `settings.json:71`.
- `man launchd.plist` lines 348–369 re-read for both `StartInterval` and `StartCalendarInterval`.
- `pmset -g custom` / `-g log` / `-g batt`, `sysctl hw.model`, `uptime` — the sleep retraction above.
- `ps` on PID 30022 (`02:23:51`, running), `sqlite3` source counts (708; 196 old / 512 new),
  `reindex.log` (247 indexed, 0 errors), live `status.json` (Jul 18, 228, 2332).
- `config.py:50-60`, `test_config.py`, `test_index.py:93`, `golden_queries.json:4`, `index.py:57-67`,
  `index.py:85-137`, `hooks/memsearch-nudge.sh` read in full.
- `launchctl print gui/501/local.memsearch-index` → not found; `~/Library/LaunchAgents` holds no
  memsearch job. Nothing installed yet; the checkpoint story is clean.
- Scenario count 27 and the "fourteen nudge scenarios" in task 4 both verified by count.

---

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | pass | Up from concern. The deduction that held it at concern for two rounds is retracted on measured evidence: this host is a desktop with sleep disabled and 18 days of uptime, so `StartInterval` delivers the property decision 1 claims. Everything else intended is delivered — run recency split from content recency, a reader for every field written, `status.py` fixed in the same change, uninstall first-class. Residual is documentation: the sleep caveat and the always-on assumption appear nowhere |
| `execution` | concern | No code exists (architecting). Ran the real harness: **5/5 pass, exit 0**. Deductions: `RUN_MAX_HOURS` is still unmeasured — its reference run is at 2h24m, unfinished, 708 sources — and `last_run_errors` has no unusable-value rule, so the obvious implementation prints *fresh*. Task 8's stop-and-ask gate mitigates the first; nothing mitigates the second |
| `trajectory` | pass | The strongest round yet. The headline act is retracting the spec's *own* fabricated number, naming it as the same trap species it already catalogued, and refusing to substitute a guess. The second is deleting a requirement rather than building on a premise the compliance judge broke — scope reduced, with the counter-argument preserved for whoever revisits it. Reasoning, not luck |
| `regression` | pass | Up from concern. R8's substring reach into two other repos is gone with R8. The enforced `ConfigError` invariant is now respected and cited accurately (verified in source and three tests). Existing `status.json` keys pinned unchanged; the nudge contract preserved. Residual: the non-atomic double `write_text` |
| `context_budget` | pass | Still at most one line at session start; the longest new line adds ~10 tokens. No always-on rule or skill growth; single canonical spec file, unsplit |
| `traceability` | concern | Seven numbered decisions each state *why*; ADR 0018 is sequenced as task 2 *before* code; the falsifier predates implementation; the measurement retraction is recorded with its cause. Deductions, all unchanged from round 3: `RUN_MAX_HOURS` still borrows an overlap rationale the man page contradicts; falsifier (c) still names the wrong signal; and the sleep behaviour of `StartInterval` — the thing that makes or breaks the schedule on a different host — is recorded nowhere |
| `success_masking` | concern | The round-2 hole stays shut and stays asserted *as a line*. Residuals: no unusable-value rule for `last_run_errors` and the natural default prints fresh (new, and the most serious); a sticky one-file error makes the degraded line permanent, which is decision 1's own failure mode (new); degraded stays hidden behind in-progress — minutes in steady state, indefinitely after a crash; a torn `status.json` yields silence rather than unknown-age; no scenario pins precedence |
| `intent_drift` | pass | This round **shrank** scope, on a recorded user decision, and moved the removed work to Non-goals with its rationale and its counter-argument. Seven non-goals, each naming its residual risk. No drive-by edits: the commit touches one file |
| `checkpoint` | pass | Verified: no `local.memsearch-index` job loaded, no plist in `~/Library/LaunchAgents`, `phase: planning`, `branch: none`, tree clean of spec changes. `--uninstall` remains first-class with its own exit codes and a "never touches `memory-index/`" guarantee — the one artifact `git revert` cannot reach |
| `audit_trail` | pass | The commit message is the exemplar: it names the user decision and its date, cites both compliance violations by id, explains why removal beat reversal, and volunteers the fabricated measurement and its correction unprompted. ADR 0018 required for both structural decisions. Prior verdicts cited |

**Risk:** low · **Confidence:** high

Down from `medium`. Round 3's medium rested chiefly on finding 1, and finding 1's premise is now
disproved by measurement. No dimension fails; the load-bearing defect class from round 2 remains
closed and triply pinned; scope shrank rather than grew; and the worst realistic outcome of the
remaining items is a noisy or missing status line — not a recurrence of the silent freeze. Everything
open is pre-code and cheap. It is not lower than `low` because one residual, the missing
unusable-value rule for `last_run_errors`, is a genuine false-green path in the exact channel this
feature exists to build. Confidence is `high`: every claim above was re-verified against source, the
man page, the live machine, and the running indexer, and the existing test harness was executed.

---

## Concerns

1. `last_run_errors` has no unusable-value rule; the natural default (0) prints the fresh line
2. A single permanently-failing source makes the degraded warning fire forever — decision 1's own failure mode
3. The degraded line's remediation is "re-run the indexer", never `scheduled-index.log`, the evidence R6 creates
4. `RUN_MAX_HOURS=6` still justified by a launchd overlap the man page says cannot happen (round 3, open)
5. `RUN_MAX_HOURS` still unmeasured; its reference run is at 2h24m, 708 sources, unfinished
6. `StartInterval`'s sleep behaviour is recorded nowhere — harmless on this desktop, latent on any laptop
7. Non-atomic `write_text`, now twice per run; a torn file is silent, not unknown-age (round 2, open)
8. Falsifier (c) names the stale line; a mid-run death surfaces as *stuck*, so (c) misreads as failed
9. Precedence between the six classification rows is pinned by no scenario
10. After a crashed run, `run_started > last_run` persists, so stale is unreachable and degraded stays hidden

## Recommended before implementation (advisory — none of this blocks)

- Give `last_run_errors` the same fail-toward-doubt rule the timestamps have, and add a scenario.
- Decide what the degraded line does about a persistent error, even if the decision is "accept it".
- Point the degraded line at `scheduled-index.log`.
- Give `RUN_MAX_HOURS` its own rationale, or delete the overlap sentence and let task 8 supply one.
- Add one sentence to decision 4: `StartInterval` misses firings during sleep; safe here because the
  host is a desktop with sleep disabled (`pmset sleep 0`, 18 days uptime, zero sleep events).
- Fix or non-goal the non-atomic `status.json` write; reword falsifier (c) to name the stuck line.
