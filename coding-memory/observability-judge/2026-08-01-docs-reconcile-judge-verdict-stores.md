# Observability judge — `docs/reconcile-judge-verdict-stores`

- **repo:** `.claude` · **branch:** `docs/reconcile-judge-verdict-stores` · **HEAD:** `8143f290d01c5152e647eb89a9b6c1f4bbc1bbee`
- **stage:** implementation · **base:** `origin/main` @ `525d95b` · **3 commits, 7 files, +2484 / −15**
- **ts:** 2026-08-01T07:25:48Z · **risk:** low · **confidence:** high
- **spec:** none (repair of an audit store) · **test command:** none applicable — see *Execution* below

## What was changed

Two filing cabinets of judge paperwork had drifted apart. One copy lived in the working folder and
had a week of newer paperwork in it; the other copy — the one everybody actually checks out — had
paperwork the working copy was missing. Neither cabinet was a superset of the other, so filing
either one over the other would have shredded real records.

This branch does three things:

1. **Merges both cabinets instead of picking one** (`cdfc018`). The ledger goes 13 → 39 entries.
   Nothing from either side was dropped.
2. **Fills in the "how did it turn out?" column** for ten entries belonging to a pull request that
   has genuinely shipped (`1ea3599`) — nine "needed rework", one "shipped clean".
3. **Writes down a rule about a chicken-and-egg problem** (`8143f29`): the act of committing a
   judge's verdict changes the code fingerprint that verdict was pinned to, so the verdict
   technically expires the moment it's filed.

## Does it do what you wanted?

Yes, and the mechanical work is unusually clean — I re-checked every number myself rather than
trusting the summary:

| Claim | Verified |
|---|---|
| 39 lines after merge, 0 dropped | ✅ all 13 base lines present; 26 added; 39 unique |
| 0 malformed, sorted by timestamp | ✅ all parse as JSON; strictly ascending; no duplicate timestamps |
| Markdown merges were pure appends | ✅ new profile writeup literally starts with the old one, +343 lines |
| Stale worktree copy discarded, not kept | ✅ `2026-07-25-phase-guard-hook.md` untouched — main's 3-round version survives |
| Every added ledger entry has a writeup | ✅ all 26 map to a round in an existing or added file |
| Backfill touched only `outcome` | ✅ exactly 10 lines, one field each; nulls 32 → 22 |
| The PR being scored actually merged | ✅ PR #33 merged 2026-08-01T05:17:03Z as `525d95b` |
| All 10 backfilled entries are real | ✅ every `head_sha` exists in the PR's 46 branch commits |

The merge direction was decided by **exact-prefix containment**, not by "whichever file is longer" —
and it shows: the one case where the working copy was *shorter* is the one case where the working
copy was correctly thrown away. That is reasoning, not luck.

## What could go wrong / what I'm unsure about

Nothing here can break a build — no source, hook, or skill is touched, and every commit reverts for
free. The concerns are all about **the record being slightly kinder to the judge than the evidence
is**, which matters because this ledger's whole job is to tell you when the judge needs tightening.

1. **The final round is filed as "clean" although it raised six concerns and caused fixes.** The last
   verdict (`0f54622`) flagged a wrong ADR cross-reference and a stale line-number pin, and the very
   next commit is titled *"land the RUN 9 verdict and fix the pointers it caught."* Findings moved
   docs before merge. The 07-22 policy has two clauses that genuinely collide here — "the final round
   that shipped is `clean`" vs. "rounds whose findings changed code or docs are `rework`" — and this
   change resolves the collision in favour of `clean`. The underlying worry is real (otherwise *no*
   PR could ever record a clean final round). But the rule was **written in the same change that
   applied it**, it applies to exactly one entry, and it moves the only metric in the direction that
   flatters the judge. Anyone later computing "how often did the judge find something real" will
   under-count by one, with nothing in the ledger line saying why.
2. **A user-owned decision was amended by the agent.** `CODING_MEMORY.md:1582` reads "CALIBRATION
   POLICY DECIDED 2026-07-22 **(user)**". The new carve-out at item 2b carries no such attribution
   and was not escalated as a question. Substantively defensible; procedurally it is the agent
   re-deciding something the human had decided.
3. **A fresh unverified number entered the docs.** `CODING_MEMORY.md` says "**24** verdicts … lived
   only in the working tree." The merge commit adds **26** lines. Both are true of different things
   — 24 is the count of distinct `head_sha` values, 26 is the count of rounds — but the document
   doesn't say which it means, and an auditor comparing the note to the diff sees a mismatch. On a
   branch whose entire purpose was to stop unverified counts from entering docs, this is the exact
   failure mode recurring.
4. **The file now contains two contradictory null counts.** Item 6 still says "**17 nulls remain**"
   and lists which ones; item 2b says the "17 nulls" figure was stale and the real move was 32 → 22.
   Item 6 — the canonical home for this ledger — was left uncorrected and unannotated. A reader
   landing there first gets the wrong number and a wrong list.
5. **Nothing stops the fork recurring.** The repair is one-shot. There is no check that every line
   parses, that timestamps ascend, or that a checkout isn't sitting on 26 uncommitted verdicts — and
   the absence of exactly that check is why this drifted for a week across two session clears. The
   "always union, never pick a side" rule is recorded in session memory but **not** in
   `coding-memory/compliance-judge/README.md`, which is where a future agent editing the store will
   actually look, and not as an ADR despite this repo keeping ADRs for judge infrastructure (0012).
6. **Self-judgment, stated plainly.** This change edits the very ledger my verdict is appended to,
   and it amends the policy under which my own verdict's `outcome` will later be filled in by the
   same agent lineage. I can verify that the ten backfilled judgements were applied *consistently*
   and that they describe a real, merged PR. I cannot independently verify the *intent* behind them,
   and no amount of checking from inside this position would fix that. Treat concern #1 as coming
   from a judge with a stake in the answer.

Minor, non-blocking: 21 new `/Users/marksuyat/...` absolute paths land in committed files. This is
pre-existing practice in this store (5 already on main), and rewriting a historical record to hide
them would be worse, but it is drift against "no absolute paths in committed files."

## What I'd double-check before merging

1. **Confirm the calibration carve-out with the user** — it modifies a decision the file itself
   attributes to them. One sentence of sign-off turns concern #2 into a non-issue.
2. **Reconcile "24" with the 26 lines in `cdfc018`**, or say in the note which one is being counted.
3. **Fix item 6's "17 nulls remain"** in place, or annotate it — don't leave two counts arguing.
4. **Move "always union, never pick a side" into the store's README**, where the next agent will see
   it before it edits the store.
5. Optionally, decide whether `clean` on a findings-producing final round needs its own value so the
   ledger stops flattening two different outcomes into one.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Built exactly what the summary describes; every mechanical claim re-derived from git and confirmed. |
| execution | pass | No test command applies — the change is docs/data-only. A meaningful test here would assert JSONL parse-validity, ts ordering and no-loss against both pre-images; I performed all three by hand and they pass. |
| trajectory | pass | Prefix-containment beat line-count heuristics, and the shorter-side-kept case proves the method was actually used. |
| regression | pass | No source, hook, or skill touched. Obs-store schema unchanged (values only), so `judge-guard.sh`'s parser is unaffected; all 70 lines still parse. |
| context_budget | pass | +17/−5 to `CODING_MEMORY.md`, replacing a now-false item. The 1801-line writeup sits in an on-demand store, not always-on context. |
| traceability | concern | `git show cdfc018` *is* a clean provenance record, but the written note's "24" disagrees with its 26 lines, and the union rule isn't recorded where the store is edited. |
| success_masking | concern | Final round recorded `clean` despite six concerns and pointer fixes landing before merge, under a rule authored in the same change; no guard added against the fork recurring. |
| intent_drift | concern | Commit 3 amends a user-attributed policy without attribution or escalation; the stale "17 nulls" at item 6 left contradicting the new figure. |
| checkpoint | pass | Three commits, one concern each, independently revertable; working tree clean; zero source touched. |
| audit_trail | concern | Two durable rulings live only in session memory — not in the store README, not as an ADR, despite ADR 0012 covering comparable judge-infrastructure decisions; carve-out unattributed. |

## Concerns

- final round filed `clean` despite 6 concerns and pointer fixes landing pre-merge, under a rule written in the same commit that applied it
- calibration policy attributed to the user (CODING_MEMORY:1582) amended by the agent without attribution or escalation
- CODING_MEMORY says "24 verdicts" but the merge commit adds 26 lines (24 = distinct head_shas); undisclosed, and the branch existed to stop exactly this
- item 6 still reads "17 nulls remain" with a stale list, contradicting item 2b's 32 → 22
- no guard added against the store forking again: no parse/ordering/no-loss check, and the union rule is absent from the store README and from ADRs
- self-judgment: this change edits the ledger this verdict enters and the policy governing its own future `outcome`; consistency verifiable, intent not
- 21 new absolute `/Users/marksuyat` paths in committed files (pre-existing pattern; rewriting history would be worse)
