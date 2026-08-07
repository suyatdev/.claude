# Observability judge — memsearch-freshness (architecting, loop 2 round 5)

- **ts (UTC):** 2026-08-07T04:32:16Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `9ad778099a6cc647942baecf9f01a32849355a87`
- **stage:** `architecting` (advisory — does not gate a PR)
- **artifact:** `docs/features/memsearch-freshness.md`, committed on `main` @ `9ad7780`, clean tree
- **test command:** none supplied; no implementation code exists. `execution` is scored on
  design-verifiability against the live tree, not on a run — stated plainly rather than implied.

## ⚠️ Lead finding — `execution` is **fail**

**R9's acceptance bar of "each hit scoring ≥0.30" is arithmetically unreachable. Every one of the
five measurement queries will fail, on any corpus, for reasons that have nothing to do with
retrieval quality or with R10.**

`memsearch` does not score by cosine similarity. It scores by weighted reciprocal-rank fusion —
`search.py:64,80`:

```
score = ( Σ over the 2 rankers of 1/(RRF_K + rank + 1) ) × weight,  RRF_K = 60  (search.py:19)
```

The theoretical ceiling is rank 0 in **both** the vector and FTS rankers, at the highest weight in
the config: `(1/61 + 1/61) × 1.5 = 0.0492`. **R9's bar is 6.1× the highest number this function can
ever emit.** Three live queries confirm it — top hits scored **0.0484**, **0.0464**, **0.0454**,
right against the computed ceiling.

The spec records the evidence and misses the inference. Line 269 states the baseline as *"the 4 hits
that did return scored ~0.02"* — the same scale — and sets a 15× bar two sentences later without
noting the two figures are commensurable. This is the **fourth measurement trap**, in the section
that catalogues three: a threshold imported from a scoring regime the tool does not use.

**The damage is worse than a useless test, because the misdiagnosis is pre-loaded.** Line 432-435
declares *"R9 is the instrument… if narrative chunks crowd feature files out of the top hits, R9
fails and says so"*, and task 10(b) pre-commits the reader: *"A failure here is a real result about
R10's noise cost."* So a guaranteed 0/5 arrives with a wrong explanation already attached to it, on
a user-directed change (R10) whose reversal costs a multi-hour `--full` rebuild by the spec's own
exit-cost paragraph.

**The fix is narrow.** Two of R9's three clauses — ≥2 hits belonging to the feature, and top hit
belonging — are rank-based and sound. Only the score floor is broken. Drop it, rescale it against
the measured ceiling, or express it relative to the top score. But it must land before task 8
commits the queries, because falsifier clause (d) forbids modifying them afterwards.

## What was changed

The memory index froze for 19 days and the session-start line kept cheerfully vouching for it. This
design fixes both halves: a `launchd` job re-indexes every 6 hours, and the one line you see at
session start reports what it actually knows — fresh, running, stuck, abandoned, stale, degraded,
error-count-unreadable, or age-unknown — and never claims freshness it cannot prove.

Round 5's change is structural rather than cosmetic. Rounds 3 and 4 each closed their findings while
introducing new ones of the same species, because the eight states were *restated* in five places and
a new state never got swept through all of them. This round made R3's table the single source of
truth and had every other surface derive from it. **That worked** — I checked all five derived
surfaces (the Contracts classification, the data-flow `OUT` node, the Scenarios, falsifier clauses
(f)/(g)/(h), task 4's test list) and they are consistent, with all eight states plus both silent
paths covered by scenarios.

## Does it do what was intended?

Mostly yes — and the evidence discipline is the best I have seen in this loop. I verified every
material claim against the live tree rather than accepting the document's account:

| Claim in spec | Verified |
|---|---|
| `config.py:56` `excludes = …` must survive; `57-60` is the guard | exact ✅ |
| `db.py:16` `SOURCE_TYPES` (no `archive_doc`), `:17` `RECALL_TYPES` has `episodic`, no CHECK | exact ✅ |
| `chunk.py:111` `recall = "decision" … else "doc"`; `:140-141` digests already `episodic` | exact ✅ |
| `index.py:43-51` `_iter_docs` hardcodes type per bucket; `:57-67` `_write_status`; `:67` non-atomic `write_text`; `:73/74` unlink-then-connect; `:88` `cfg.weights[st]`; `:100` unconditional stamp; `:125-127` early return; `:135-137` catch-and-continue | **all exact** ✅ |
| `status.py:27` prints `last_indexed` as the freshness answer | exact ✅ |
| `test_golden_queries.py:37-41` presence-in-top-k only; `:47-52`/`:57-60` warn-only | exact ✅ |
| golden counts 11 `must` / 3 `stretch` / 2 `negative`; `pyproject.toml:23` deselects; file is marked `pytest.mark.golden` | exact ✅ |
| **Golden entry 11 (file line 12)** is the mid-july/`.jsonl`/`episodic`+`since` query | exact ✅ (round 4 called it "12"; the spec's 1-based-entry / file-line phrasing is now precise) |
| plan sweep returns **fourteen** hits at 19, 41, 152, 205, 211, 282, 284, 318, 1484, 1519, 2828, 2890, 2942, 3067 | **all fourteen exact** ✅ |
| test line map — five move (`84,106,135,149,160`), four don't (`105,117,136,161`), `:93` compound, `:58` fixture | **all correct** ✅ |
| `:117` is the changed-file test, `:149` is limit-scoped (round 4's swap) | **corrected** ✅ |
| four stale inline comments at `:84`, `:135`, `:148`, `:160` | exact text ✅ |
| seven failing test *functions* from eight failing assertions | **arithmetic checks out** ✅ (`:84`+`:93` share `test_full_run…`) |
| 911 sources, 187 @ 2026-07-18 / 724 @ 2026-08-06 | exact ✅ |
| `session-log.md` frozen 2026-07-16, `decisions.md` 2026-07-19 | exact ✅ |
| `last_indexed` live value/format `2026-08-06T23:56:46+00:00` | exact ✅ |
| `CODING_MEMORY.md` "299,422 chars / 3,433 lines — treat as a floor" | now **303,173 / 3,484** — the caveat was correct and honest ✅ |
| `reindex.log` 63,568 bytes from one run | exact ✅ |

**A latent trap round 4 flagged is closed structurally, and the spec did not need to say so:**
`cfg.weights["archive_doc"]` would `KeyError` in the fixtures — except `write_cfg`
(`test_config.py:11-16`) builds every test config from the **real** `config.json`, so R10 part 1's
weight addition flows into all of them automatically. The single-commit mandate holds.

### Round-4 concerns: eight of ten closed

Closed: the abandoned-first-run silent line (new state 3, with ⚠ and a log pointer); the
contradicted concurrency non-goal (now stated as a bounded trade at 901-909); golden entry 11 named
with a pre-registered prediction; `-m golden` over-credited (now split into two named instruments);
"eleven hits" → fourteen; the `:117` mislabel; log rotation (now an explicit non-goal with rationale);
`RUN_ABANDON_HOURS` vs cold-run duration (now gated by task 9 with an explicit stop-and-ask).

**Not closed — a directly cited finding that survived a round dedicated to closing findings.** The
decay scenario at lines 622-627 still reads *"Given run_started is 30 hours ago **and is later than
last_run** / And last_run is 30 hours ago."* Both cannot be 30h ago with one later than the other.
Low severity — I traced the table and the outcome is `stale` under either ordering — but it was named
in round 4 and is unchanged.

## New findings this round

1. **A run that walks zero sources reads as `fresh`.** This is the sharpest remaining
   success-masking hole. `status.json` records *whether a run happened* (`last_run`) and *whether it
   errored* (`last_run_errors`), and nothing about whether it **saw anything** — no `processed`, no
   `sources_walked`. A run whose walk finds nothing (a `curated_docs` path typo'd, a directory moved,
   a mount missing) completes with 0 errors, stamps `last_run`, and classifies as **state 8, fresh**,
   forever, over frozen content. That is the original defect one field over — and the spec's own R10
   evidence proves the class is live *today*: `~/.claude/CODING_MEMORY.md` produced 0 rows silently
   because it was off every walked path, and `docs/features/` read 0 and was misdiagnosed in the
   parent spec as a config gap. The one field that would expose it, `last_indexed`, is deliberately
   excluded from the nudge (R5, decision 2) — and decision 2's reasoning against the *naive* version
   is sound, so this is a real gap rather than an easy fix. Requires a second fault to manifest, so:
   concern, not fail.

2. **"Usable" is defined twice, and the two copies already disagree — inside the very paragraph that
   explains the authoritative table.** Line 137-139 defines it formally: *parses and is not in the
   future*. Line 162-166 then says past `RUN_ABANDON_HOURS` the `run_started` stamp *"becomes
   unusable, exactly as a future one is."* Under the formal definition it does not — the decay comes
   from rows 1 and 2's age bounds. Worse, an unusable stamp is *"treated exactly as absent"*, which
   would make **row 3 unreachable by its own condition** (`run_started` **present**, in the past,
   age ≥ `RUN_ABANDON_HOURS`). The table's formal conditions are self-consistent and correct; only
   the explanatory prose contradicts them. Named precisely because round 5's thesis is
   one-definition-one-place, and this is the last restatement.

3. **State 4 remains the one abnormal state with no marker and no pointer.** Round 5 rescued the
   first-run case into state 3. The residue is a *future-dated* `last_run` — genuine clock skew,
   a real anomaly — rendering as a calm `age unknown` line. The no-⚠ choice is defensible because
   state 4 also covers the benign one-time upgrade window (an old `status.json` with neither field),
   so this is a trade rather than an oversight; it is just an undocumented one.

4. **Silence still equals health** (carried, structural). Absent `status.json`, `chunks == 0`, an
   unregistered hook, and an unreadable `status.json` mid-rebuild all render identically as nothing
   at all, by R4's contract. There is no heartbeat. The rebuild case is now explicitly disclosed
   (lines 491-493). Inherent to "one line at session start is the only monitor"; recorded as the
   standing cost.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | **pass** | All round-4 directed fixes present and reasoned; the structural rewrite is the right correction and it demonstrably held across all five derived surfaces. |
| execution | **fail** | R9's ≥0.30 score floor is 6.1× the scoring function's arithmetic ceiling (`search.py:19,64,80`; confirmed against three live queries). The feature's headline instrument cannot return a pass, and task 10(b) pre-assigns the guaranteed failure to R10's noise cost. |
| trajectory | **concern** | The method is right and applied rigorously nearly everywhere — but the one number the whole feature is judged by was set without measuring the scale it lives on, in a document whose central discipline is "measure, don't remember". Decision 6 asked whether the bar was expressible *in the existing test*; it never asked whether the bar was expressible *at all*. |
| regression | **concern** | R10's test map verified complete and correct, and the `KeyError` risk closes structurally. But the archive becomes the corpus's largest source by 2.3×, only entry 11 is forecast, and the strict half of the regression net (R9) is inert until the floor is fixed. |
| context_budget | **pass** | Feature doc, not always-on rule content. Session-start output stays at one line, roughly today's length even in the warning states. Corpus growth is retrieval budget — which R9 was meant to measure, hence the coupling to the finding above. |
| traceability | **pass** | Restored from round 4. Every ⚠ state carries a pointer (2, 3, 6, 7 → the log; 5 → the index command); the contradicted non-goal is fixed; wrong prior figures are named rather than silently corrected; the weakened falsifier (d) and the "treat as a floor" caveat are both disclosed, and the floor caveat proved correct. Only state 4's future-timestamp case lacks a pointer. |
| success_masking | **concern** | A run that walks zero sources reads as fresh; silence still equals health. Both structural, one newly identified. The R9 floor is the inverse failure — a guaranteed red whose cause is pre-misattributed — and is scored under execution. |
| intent_drift | **pass** | R10 is user-directed and traces to the parent spec's item 1. Non-goals are unusually disciplined — six of them, each naming a cost rather than dodging one. Round 5 added only what was asked. |
| checkpoint | **concern** | Spec committed on `main` @ `9ad7780`, clean tree; branch pending task 1 by design (not a finding). `--uninstall` is a first-class removal path. But **nothing reverts embedded chunks** — `git revert` undoes the config, not the vectors, and the stated exit is a multi-hour `--full`. Now fully disclosed as the exit price; disclosure is not coverage. |
| audit_trail | **pass** | ADR 0018 (task 2) and ADR 0019 (task 7) both mandated with options-weighed content; the `archive_doc` weight-tier call is dated and attributed to the user. |

**risk: high · confidence: high** — confidence is high because the ceiling was computed from
`search.py` and then confirmed against three live queries landing within 2% of it; and because every
other citation in the spec was checked against the working tree rather than accepted.

Risk is high despite this being an advisory, pre-implementation verdict: the broken bar sits on the
feature's stated success criterion (*"not 'memsearch works' — 'we finally know whether it does'"*),
and the spec pre-commits to reading its guaranteed failure as evidence against a user-directed
change. Cheap to fix now; expensive to discover at task 10.

## Concerns

1. **R9's ≥0.30 score floor is unreachable** — `search.py` scores by weighted RRF with `RRF_K=60`, ceiling `(2/61)×1.5 = 0.0492`; live top hits measure 0.045–0.048. All five measurement queries fail unconditionally.
2. **The guaranteed R9 failure has a wrong explanation pre-attached** — line 432-435 and task 10(b) both instruct the reader to read an R9 failure as R10's noise cost, on a change whose reversal costs a multi-hour rebuild.
3. Fix the floor before task 8, not after — falsifier clause (d) forbids modifying the queries once committed.
4. **A run that walks zero sources classifies as state 8, fresh** — no `processed`/`sources_walked` in `status.json`, and `last_indexed` is deliberately not printed by the nudge. The spec's own R10 evidence shows this failure class is live today.
5. **"Usable" is defined twice and the copies disagree** (137-139 formal vs 162-166 prose); read literally, the prose makes state 3 unreachable by its own condition.
6. State 4 is the one abnormal state with no ⚠ and no log pointer — a future-dated `last_run` renders as a calm "age unknown" line.
7. Silence still equals health: absent `status.json`, `chunks == 0`, an unregistered hook, and an unreadable status file mid-rebuild are indistinguishable. No heartbeat; structural.
8. The decay scenario's two Givens remain mutually inconsistent (both 30h ago, one "later than" the other) — cited in round 4, unchanged in round 5.
9. No prune path: re-excluding `CODING_MEMORY.md` after a failing R9 leaves its chunks scored and returned until a multi-hour `index --full` (disclosed and accepted).
10. `RUN_ABANDON_HOURS` (24h) still clears an **unmeasured** cold-run duration; past it, the stale line hands a live run the index command with no lock. Gated by task 9 with an explicit stop-and-ask — the right mitigation, still an open number.
11. `scheduled-index.log` is unbounded and is now the destination of four of eight nudge lines (disclosed as a non-goal; rotation needs task 9's size figure).
