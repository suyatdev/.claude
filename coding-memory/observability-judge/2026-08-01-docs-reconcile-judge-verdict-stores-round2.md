# Observability judge RUN 2 — `docs/reconcile-judge-verdict-stores`

- **repo:** `.claude` · **branch:** `docs/reconcile-judge-verdict-stores` · **HEAD:** `d4aecf0976dfb20097ef88296df791023199b854`
- **stage:** implementation · **base:** `origin/main` @ `525d95b` · **4 commits, 8 files, +2642 / −21**
- **ts:** 2026-08-01T16:00:11Z · **risk:** low · **confidence:** high
- **spec:** none (repair of an audit store) · **test command:** none applicable — see *Execution* below
- **filename note:** written as `-round2` rather than overwriting RUN 1's writeup at the unsuffixed
  path. Same directory, repo's existing `-roundN` convention (see `…-phase-guard-hook-round8.md`).
  Overwriting a prior round's audit record on a branch that exists to stop audit-record loss would
  have been the wrong reading of the filename rule.

## What was changed

Last round I said the paperwork was fixed but the *notes about* the paperwork were flattering the
judge. This commit responds to that. Three things happened:

1. **The self-serving rule got taken away from the agent and given to the user.** The earlier
   carve-out — "a verdict-landing commit doesn't count against the round" — had been quietly written
   by the agent into a policy the file itself credits to the human. It was escalated instead of
   patched over, the user ruled "narrow it", and the rule now exempts only the mechanical act of
   filing the verdict. If the round's findings caused a real fix, the round still counts as rework
   even if the fix rides in the same commit.
2. **The one flattering data point was destroyed.** Under the narrowed rule the final round of PR #33
   flips `clean` → `rework`, because the commit that filed it also fixed a wrong cross-reference and
   added a third, less flattering latency measurement. PR #33 now reads ten rework, zero clean.
3. **Three counts were re-measured and corrected**, and two known problems were written down as debt
   rather than pretended away.

## Does it do what you wanted?

Mostly yes, and the hard part is genuinely right. I re-derived every number from the git objects
myself rather than trusting the commit message:

| Claim in `d4aecf0` | Verified |
|---|---|
| 26 lines added across 24 distinct `head_sha` | ✅ exactly 26 / 24 |
| union 13 → 39, nothing lost | ✅ 13 base all present, 0 dropped, 0 malformed, ts strictly ascending |
| store re-measured: 70 lines, 22 null, 0 malformed | ✅ exact at `8143f29` |
| null breakdown 19 implementation / 3 architecting, per-branch list | ✅ matches the store row for row |
| old "17" reconciles as 17 + cmux-version-gate ×3 + gate-checks ×2 | ✅ those two groups are precisely the difference; the other seven match one-for-one |
| PR #33 now ten `rework`, zero `clean` | ✅ 10 rows, all `rework` |
| the flip changed one token on one line | ✅ line 70, `outcome` only, nothing else differs |
| `origin/main` already carries 49 absolute paths, 5 in this store | ✅ 49 / 5 |
| RUN 9's flip rests on `7e0b9b1`, not `8390a52` | ✅ `8390a52` (07-29) is an *ancestor* of `0f54622` (08-01) so it cannot be RUN 9 fallout; `7e0b9b1` is the descendant that lands the verdict |
| `7e0b9b1`'s ADR edits are substantive, not cosmetic | ✅ it adds a third measurement (52.6 → 138 ms) that widens the reported spread, and replaces a cross-reference that pointed at the wrong bullet |

**The `rework` flip is correct and it is not an over-correction.** Store-wide the ledger reads
**34 `clean` / 14 `rework` / 23 null** — the positive class is alive and `clean` is still reachable
(a final round that finds nothing substantive still earns it). "Zero clean" is a fact about one
ten-round PR, not about the ledger. A ten-round grind where every round changed something is
exactly what `rework` is for.

**The escalation was the right move.** An agent asked to score itself found a rule it had written in
its own favour and handed the decision to the human rather than re-deciding it. That is the
behaviour the whole gate exists to produce.

## What could go wrong / what I'm unsure about

Nothing here can break a build — no source, hook, or skill is touched, `judge-guard.sh` never reads
the `outcome` field at all (so the flip is inert for gating), both stores parse, the tree is clean,
and every commit reverts for free. The problems are all in the *record*.

1. **Two new unverified claims entered the docs — in the commit written to stop that.** This is the
   headline finding, because it is the branch's own thesis failing at the meta level.
   - `CODING_MEMORY.md:1548` says the 26-vs-24 gap is because "**two SHAs carry a second round**".
     It is **one** SHA (`6d8c675`, `Snatch-Bracket`) carrying **three** rounds. The arithmetic
     survives (26 − 24 = 2 either way); the explanation is invented. It reads as measured and isn't.
   - `CODING_MEMORY.md:1561` says "**19 absolute `/Users/marksuyat` paths** ride in on the rescued
     verdicts". Measured from the blobs: **18** ride in on the rescued verdicts, and **22** are
     net-new across the branch at this HEAD. I cannot construct a metric that yields 19 (occurrences:
     18/22; lines: 18/22; distinct path strings: 2). RUN 1 said "21" — also wrong. The number was
     silently replaced with a different wrong one, with nothing recording that the judge's figure
     had been revised.

   Note the pattern, because it is the actionable part: **every claim that was mechanically
   re-measured is exactly right; both claims that were narrated as explanation are wrong.** The
   corrective was applied to the specific counts RUN 1 named, not to the habit that produced them.

2. **"Pre-existing pattern, not introduced here" is not quite true at this HEAD.** 18 of the 22 ride
   in on rescued historical records — for those the reasoning is *sound, not self-serving*: rewriting
   an audit record to satisfy a style rule aimed at code and config would falsify the record, and
   declining to do that is the right call. But 4 are authored by this branch: 1 in `CODING_MEMORY.md`
   (harmless — it's the rule being quoted), 2 in RUN 1's writeup, 1 in RUN 1's verdict line. Those
   last three are the judge writing its own cwd — the root cause the item itself names, deferred with
   no owner and no ticket, while the branch keeps adding instances of it.

3. **Item 6's corrected count is already stale at the commit that writes it.** "70 lines, 22 null" is
   true at `8143f29` but the store is 71/23 at this HEAD, and 72/24 once this verdict lands. It is
   anchored to a date, not a SHA, so the next reader re-measures and finds a mismatch — the same
   defect class as the "17 nulls" it fixes, one order smaller. Anchor it (`as of <sha>`) or phrase it
   as "excluding in-flight verdicts".

4. **The narrowed rule has a real gray band.** "Mechanical landing" vs "substantive change" is crisp
   at the extremes and arguable in the middle. `7e0b9b1` bundled one clearly substantive change (the
   third measurement — new evidence that made the reported number worse) with two that a motivated
   reader could call cosmetic (a cross-reference, a garbled sentence). The flip stands because of the
   measurement. A future round that fixes *only* a wrong pointer can be argued either way, and the
   rule supplies no tie-break. The conflict was narrowed honestly; it was not eliminated.

5. **The ledger now blends two calibration regimes with no marker.** The 34 existing `clean` values
   were assigned under the looser reading; only PR #33 was re-scored under the narrowed one. Nothing
   in a store row records which rule judged it, so anyone computing "how often does the judge prompt
   rework" is averaging two different questions. Not re-auditing 34 rows here is a defensible scope
   call; leaving it undisclosed is not.

6. **Self-judgment, again, and the bias has a direction this time.** My verdict enters the store this
   change edits, and the policy I am scoring governs my own future `outcome`. Under the narrowed
   rule, if the main agent fixes the two wrong counts I just found, **this round becomes `rework`** —
   so I had a standing incentive to find nothing. Read finding #1 knowing that, and knowing I cannot
   check it from inside this position. What I *can* verify — that every number reduces to a git
   object — I did, and I'm giving you the commands so you don't have to take my word for it.

## What I'd double-check before merging

1. **Fix `CODING_MEMORY.md:1548`** — one SHA carries three rounds, not two SHAs carrying two.
   `python3 -c "import json,collections,subprocess; …"` or just read the three `Snatch-Bracket`
   rows with `head_sha` `6d8c675…`.
2. **Fix or drop the "19"** at `:1561`. 18 on the rescued records, 22 net-new at HEAD; and say that
   RUN 1's "21" was also wrong, so the next reader doesn't think the judge is being overruled
   silently.
3. **Anchor item 6's counts to `8143f29`**, or they rot on the next verdict — including mine.
4. **Add one sentence to item 2b** stating that pre-narrowing `clean` values were not re-audited, so
   the ledger isn't read as one calibrated series.
5. **Decide the tie-break** for a pointer-only fix: default-to-`rework` is the conservative reading
   and matches the 07-22 rationale (a ledger that under-reports rework is useless for tuning).
6. Optional, and the real fix: stop the judge writing an absolute cwd into verdicts, which retires
   debt #2 at the source instead of one branch at a time.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Did what the user ruled — narrowed, re-attributed, applied, and disclosed the finding it chose not to fix. No finding was quietly dropped. |
| execution | concern | No test command applies (docs/data only); I re-derived all integrity claims by hand and they pass. But the product of this change *is* its claims, and two of the newly written ones are false, plus one stale-on-arrival. |
| trajectory | concern | Escalating the policy conflict instead of self-amending is exactly right, and the wrong `8390a52` attribution was caught before landing. But the same prose habit that produced the counts being fixed produced two more — the corrective didn't generalize past the specific items named. |
| regression | pass | `judge-guard.sh` never reads `outcome`, so the flip cannot affect gating; schema unchanged; both stores parse, 0 malformed, ts strictly ascending; no source/hook/skill touched; tree clean. |
| context_budget | concern | `CODING_MEMORY.md` is always-on. This branch now nets ~+25 lines there, including a paragraph about a superseded draft of its own item and an aside about superseded wording — historiography that belongs in `coding-memory/branches/`, not the index. The durable ruling itself belongs. |
| traceability | concern | Provenance and attribution are much improved (`DECIDED 2026-08-01, user`). Against that: item 6's counts are unanchored and already stale, and two prose claims cannot be reproduced from the store. |
| success_masking | concern | The masking RUN 1 found is genuinely fixed — the flattering data point was destroyed, not defended. Remaining: 34 pre-narrowing `clean` values sit unmarked beside 10 post-narrowing `rework`, so the aggregate reads more consistent than it is. |
| intent_drift | pass | Scope held to the five findings. No drive-by edits, no deps, no source. Debts recorded rather than smuggled in as riders. |
| checkpoint | pass | One focused commit atop three; the flip is one token on one line, byte-diffed against a pre-flight backup; independently revertable; tree clean. |
| audit_trail | concern | Attribution fixed. Still: the narrowing is not an ADR despite ADR 0012 covering comparable judge infrastructure, the store has no README and no policy-version field, and the judge's cited "21" was replaced by "19" with no note that either was measured wrong. |

## Concerns

- `CODING_MEMORY:1548` "two SHAs carry a second round" is false — one SHA (`6d8c675`) carries three; a new unverified claim in the commit that exists to stop them
- `CODING_MEMORY:1561` "19 absolute paths" is false — 18 ride in on rescued records, 22 net-new at HEAD; silently replaces RUN 1's (also wrong) "21" with no note
- pattern: every mechanically re-measured number is exact; both narrated explanations are wrong — the fix didn't generalize past the named items
- item 6's "70 lines, 22 null" is anchored to a date not a SHA and is already 71/23 at this HEAD; same defect class it fixes
- narrowed rule leaves a gray band: a pointer-only fix is arguable either way, no tie-break stated
- ledger blends two calibration regimes — 34 pre-narrowing `clean` were not re-audited or marked
- "not introduced here" understates: 4 of 22 absolute paths are authored by this branch, 3 of them the judge's own cwd, root cause deferred with no owner
- self-judgment with a directional incentive: under the narrowed rule, fixing my findings makes this round `rework`, so I was incentivised to find nothing
