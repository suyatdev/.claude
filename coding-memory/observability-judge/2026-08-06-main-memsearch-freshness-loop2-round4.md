# Observability judge — memsearch-freshness (architecting, round 4)

- **ts (UTC):** 2026-08-07T03:40:47Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `24e6e29e0a37ccfcf484f85518787c9fecf02b67`
- **stage:** `architecting` (advisory — does not gate the spec)
- **artifact:** `docs/features/memsearch-freshness.md`, working tree, blob `7266fea3231dc030095ae43957e63cfded9fd489` (uncommitted; scored as-is)
- **test command:** none supplied; no implementation code exists. `execution` is scored on
  design-verifiability, not on a run — stated plainly rather than implied.

## What was changed

The memory index froze for 19 days and the session-start line kept saying it was fine. This design
fixes both halves at once: a background job (`launchd`) re-indexes every 6 hours, and the one line
you see at session start now reports *what it actually knows* — fresh, stale, running, stuck,
degraded, error-count-unreadable, or age-unknown — and never claims freshness it cannot prove.

Round 4 folded in three fixes I asked for in round 3. Think of the session-start line as the
dashboard light on a car with no other gauges:

- **The "check engine" light now times out.** Before, a run killed mid-flight left the light stuck
  on "still working…" forever, so a *dead* scheduler looked busy. Now after 24 hours that claim
  expires and the light switches to "stale — here's the command to fix it."
- **A blank gauge no longer reads as zero.** A missing error count used to render as "0 errors,
  all good." Now it says the count is unreadable and points at the log.
- **The archive is filed in the right drawer.** `CODING_MEMORY.md` will answer
  `--type episodic` (the natural "what happened in session 27" query), not sit in a generic bucket
  where nobody looks.

## Does it do what was intended?

Yes. All three directed fixes are present and correct, and I verified them against the real code
rather than the spec's own account:

| Claim in spec | Verified |
|---|---|
| `chunk.py:111` is the `recall = "decision" … else "doc"` line | exact ✅ |
| `chunk.py:141` digests already use `episodic` | exact ✅ |
| `db.py:16/17` `SOURCE_TYPES` / `RECALL_TYPES` (contains `episodic`, no CHECK) | exact ✅ |
| `config.py:56` `excludes = …` must survive; `57-60` is the guard | exact ✅ |
| `index.py:57-67` `_write_status`, `:67` non-atomic `write_text`, `:73/74` unlink-then-connect, `:100` stamp | exact ✅ |
| `status.py:27` prints `last_indexed` as the freshness answer | exact ✅ |
| `golden_queries.json` **line 4** is the CODING_MEMORY query; line 2 is the sqlite/qdrant one | exact ✅ |
| `pyproject.toml:23` `addopts = "-m 'not golden'"` | exact ✅ |
| test line map — five move (`84,106,135,149,160`), four don't (`105,117,136,161`), `:93` compound, `:58` fixture | **all nine correct** ✅ |

The test-count enumeration that was wrong twice is now right, and it is stated as a *rule*
(`processed` +1 per indexing run, `skipped` +1 per re-scan) with the derived list as illustration.
That is the correct structural fix.

## The question you asked: is the monitor now adequately observable?

**Round 3's answer still holds — narrowed materially, not closed.** The residue has changed shape:
it is no longer *stuck*-shaped. It is now **first-run-shaped** and **silence-shaped**.

**Genuinely closed by this round:** the stuck-forever hole *when `last_run` exists*; the
missing-error-count-reads-as-clean mask; the archive being invisible to the obvious filter.

**Three gaps remain.**

1. **The decay lands somewhere safe only if `last_run` exists.** Past `RUN_ABANDON_HOURS` the
   `run_started` stamp goes unusable and classification falls to row 3 or 4. If `last_run` is
   present → row 4 → `stale ⚠` with working remediation. That is the fix, and it works. But
   **row 3 is the landing zone when `last_run` is absent** — the first run after install/upgrade
   that was killed and never completed, which is precisely the case R3 row 1 exists to cover. R2
   fixes that line's wording as `memsearch: 2332 chunks, age unknown — query with: …`: **no ⚠, no
   remediation, no log pointer.** A scheduler that died before ever finishing a run therefore
   renders as a calm, unremarkable line. That is the original defect's silhouette in the one window
   the new code path creates.

2. **Past 24h the design starts recommending the thing it declared unsafe at 23h — and says it
   doesn't.** Decision 5 forbids the remediation command while a run may be alive ("invites a
   second concurrent indexer… a safety behaviour, not a nicety"), and R3's stuck line honours that
   by pointing at the log. The decay routes to the **stale** line, which per R1 *does* carry
   `run ~/.claude/memsearch/bin/memsearch index`. There is no lock or pidfile (explicit non-goal).
   So if a genuinely long cold run exceeds 24h, the nudge tells the reader to start a second
   indexer against a live one. The presumption "24h is far past any plausible run" is reasonable
   but **unmeasured** — by the spec's own admission the true full-run duration is unknown (the
   "1h26m" figure was a stopwatch glance on an unfinished run; the same run was at 2h17m/683
   sources later, and the corpus is about to gain its largest file). Two things follow:
   - The **non-goal at line 809-811 is now false**: "R3 stops the nudge from *inviting* one —
     neither the in-progress nor the stuck line carries the remediation command." True of those two
     lines; the decay's *stale* line does carry it. A doc whose defining virtue is stating costs
     rather than smoothing them should not have its own risk register contradicted by the fix.
   - Task 9 does hold `RUN_ABANDON_HOURS` open against the measured cold run — the right
     mitigation, and it is why this is a concern and not a fail.

3. **Silence is still indistinguishable from health** (unchanged from round 3, structural).
   Absent `status.json`, `chunks == 0`, and an unregistered hook all render identically as *nothing
   at all*, by R4's contract. There is no heartbeat and no liveness probe. This is inherent to
   "one line at session start is the only monitor" and the design accepts it consciously; I record
   it as the standing cost, not as an oversight.

## New findings this round

- **Golden query 12 is a likely casualty, and the spec never names it.**
  `{"query": "what were we working on in mid july 2026", "expect_path_contains": ".jsonl",
  "filters": {"rtype": "episodic", "since": "2026-07-01"}}` is a **`must`** query. R10 makes
  `CODING_MEMORY.md` `episodic`, with `session_date` = file mtime (today → passes `since`), at
  weight 1.0 — **tied with `transcript_digest`** — and it is the corpus's largest source by 2.5×.
  Its content is literally "what we were working on." Query 12's premise (episodic ≈ transcripts)
  is altered by R10 in the *same way* query 4's premise was falsified — the spec reasons carefully
  about query 4 and is silent on 12. Task 10's `-m golden` run would catch it, so this is
  detectable, not hidden; but an implementer meeting a red query 12 with no forewarning is likelier
  to "fix" the expectation than to record it as R10's measured cost.
- **`-m golden` is a weaker net than task 10 implies.** `test_golden_queries.py:39` asserts
  `any(expect in p for p in paths)` — *presence in top-k*, not top hit, no score floor. The archive
  can push a decision record from rank 1 to rank 5 and all sixteen golden tests stay green. Task 10
  calls golden "the noise-regression net R10 is being measured against"; the strict instrument is
  actually R9's own five queries (top hit + ≥0.30). Worth saying so, or the green suite over-reads.
- **`scheduled-index.log` still has no rotation or size cap**, and this round *raised* its
  importance: two of the seven nudge lines now point at it as the evidence store. Measured:
  `reindex.log` is 63,568 bytes from one run. Unbounded, 4 runs/day, `PYTHONUNBUFFERED`.
- **Recorded-evidence slip:** the spec says the plan sweep "returns eleven hits." `grep -n
  CODING_MEMORY docs/superpowers/plans/2026-07-17-memory-rag-index.md` returns **14**
  (19, 41, 152, 205, 211, 282, 284, 318, 1484, 1519, 2828, 2890, 2942, 3067). The **four** named as
  asserting the retired rule (19, 2828, 2890, 2942) are correct, and the instruction to re-run the
  sweep at implementation time routes around the stale count — but a wrong number in a doc built on
  "measure, don't remember" is worth correcting.
- **`:117 (limit-scoped)` is mislabelled** — `:117` is `test_changed_file_reindexes_only_itself`;
  `:149` is the limit test (and *does* move). The move/don't-move classification is right; only the
  parenthetical rationale is swapped. Cosmetic, but this list's accuracy is load-bearing.
- **Decay scenario is internally inconsistent:** "Given run_started is 30 hours ago **and is later
  than last_run** / And last_run is 30 hours ago." Both cannot be 30h ago with one later than the
  other. An implementer will guess (e.g. `-30h` / `-31h`); say which.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | **pass** | All three directed fixes present, correct, and reasoned — not merely inserted. |
| execution | **concern** | No runnable artifact at this stage (stated, not implied). Two enumerated evidence claims are wrong against the live tree (11 vs 14 hits; the `:117` label), and the concurrent-run consequence of the decay is undesigned. |
| trajectory | **pass** | The decay bullet reasons from the falsifier's own blind spot ("clause (c) would read as passed… the wrong label"). Replacing a twice-wrong line list with a generative rule is the right structural correction. |
| regression | **concern** | Golden query 12's premise is changed by R10 and unnamed; decay can invite a concurrent indexer with no lock; `cfg.weights[st]` still KeyErrors on a partial R10 (mitigated by the single-commit mandate). |
| context_budget | **pass** | Feature doc, not always-on rule content. Session-start output stays at one line. The 285k-char corpus growth is retrieval budget, and R9 measures it. |
| traceability | **concern** | Outstanding overall — traps, the misread duration, and the weakened falsifier (d) all recorded rather than smoothed. Demoted only because the fix has left its own non-goal (line 809-811) asserting something no longer true. |
| success_masking | **concern** | Two masks closed. Remaining: post-decay `age unknown` reads benign for a never-completed scheduler; total silence still equals health; `-m golden` is presence-in-top-k, so ranking decay stays green. |
| intent_drift | **pass** | R10 is user-directed and traces to the parent spec's item 1. Non-goals are unusually disciplined; this round added only what was asked. |
| checkpoint | **concern** | `git revert` covers config/code, `--uninstall` covers `launchd`, **nothing covers embedded chunks** — re-excluding leaves them scored and returned until a multi-hour `--full`. Now explicitly disclosed as the exit price (documented, not solved). Spec itself is uncommitted on `main`, branch pending task 1. |
| audit_trail | **pass** | ADR 0018 (task 2) and ADR 0019 (task 7) both mandated with options-weighed content; the weight-tier call is dated and attributed to the user. |

**risk: medium · confidence: high** — confidence is high because every code citation was checked
against the working tree, not accepted from the document.

## Concerns

1. Post-decay with `last_run` absent lands on R2's `age unknown` line — no ⚠, no remediation, no log pointer; a scheduler that died before completing its first run renders as a calm line.
2. Past `RUN_ABANDON_HOURS` the stale line carries the remediation command decision 5 forbids while a run may be alive; no lock exists and 24h is unmeasured.
3. The non-goal at 809-811 ("R3 stops the nudge from inviting one") is contradicted by the decay it now sits beside.
4. Golden query 12 (`rtype: episodic`, `since`, expects `.jsonl`) is a `must` query whose premise R10 changes — unnamed, though task 10 would surface it.
5. `test_golden_queries.py:39` asserts presence in top-k, not top hit — ranking degradation from the archive stays green; task 10 over-credits `-m golden` as the noise net.
6. `scheduled-index.log` has no rotation or cap, and this round made it the destination of two of seven nudge lines (`reindex.log`: 63,568 bytes from one run).
7. Silence still equals health: absent `status.json`, `chunks == 0`, and an unregistered hook are indistinguishable — no heartbeat, structural to the design.
8. Spec records "eleven hits" for the plan sweep; the live sweep returns 14 (the four asserting the retired rule are correct).
9. `:117` is labelled "limit-scoped" but is the changed-file test; `:149` is the limit test. Classification right, rationale swapped.
10. The decay scenario's two Givens are mutually inconsistent (both 30h ago, one "later than" the other).
11. No prune path: re-excluding `CODING_MEMORY.md` after a failing R9 leaves its chunks scored and returned until a multi-hour `index --full` (disclosed and accepted).
