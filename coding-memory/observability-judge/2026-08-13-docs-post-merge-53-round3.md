# Observability judge verdict — verification-marker-gate, round 3 (architecting, advisory)

- repo: `tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `925121815ac31994aa13ecaec128fbcee8782943`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`, `branch: none`)
- ts: `2026-08-13T04:44:36Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 9, 1539 lines, verified against `wc -l`;
  waived past the 800-line ceiling by explicit user decision, measured in §Standing decisions → O3)
- prior verdict: `2026-08-13-docs-post-merge-53-round2.md` (head `0294809`, architecting, risk=medium)

## What was changed

Still a design document, no code. Since round 2, one thing happened: **the decision log came back.**
Round 2 recommended restoring it before `--status`, on the ground that `TEST_EXEMPT` was validated and
then discarded, leaving bypass usage permanently unmeasurable. The user took that recommendation, and
restored it *by git*, not by rewriting — `git show 36a0880:...` pulled the exact revision-7 text back
in, rather than someone re-typing a "similar" version from memory. That is the right way to undo a cut:
the restored section is provably identical to what a prior, already-judged revision specified.

What's new this round is the log's own self-description. It ships in v1 with a writer and **no
reader** — `--status` is still deferred to follow-up 1 — and the spec is explicit about that being a
"stated gap," not a silent one: *"a log nothing reads is the same defect as no log."* It also rewrote
the inertness note into an asymmetry claim: *"a non-empty log proves the gate is armed and firing; an
empty one proves nothing."* Both of those claims were the assignment for this round, and I checked them
against the actual regex, the actual line counts, and the actual tools named to read the file back.

## Does it do what you wanted?

Mostly yes, and the size-measurement discipline this document was burned by twice already held up this
time — I re-derived every commit's line count myself rather than trusting the table:

```
36a0880 -> 1448   fa44399 -> 1402   0294809 -> 1413   17d2379 -> 1434
```

All four match the §Standing decisions → O3 table exactly, and the current file is 1539 lines against
the table's claimed 1,539 for "decision log restored to v1." No stale number this round.

Point by point, against what round 3 was asked to check:

1. **Is the asymmetry framing correct and adequately disclosed?** Correct as far as it goes, but
   narrower than its own wording. "Proves the gate is armed and firing" is true only as of the log's
   *last* entry — a non-empty log from a repo where nothing has been touched in a month is not live
   proof the gate is still armed today; it could have gone inert the day after that last line was
   written. The document already knows this: the exact caveat lives two sections earlier, in §Scope's
   accepted-cost callout ("a gate that goes inert *later*... is still invisible until someone re-runs
   task 14 by hand"). It just isn't repeated or cross-referenced next to the asymmetry claim itself, so
   a reader who only reads §Decision logging could walk away over-trusting a stale-but-nonempty log.
   Not an overclaim so much as a claim that needs its neighbor paragraph to be fully honest.
2. **Is bypass-rate erosion actually measurable in practice, or only in principle?** This is where I'd
   push back hardest. The spec's literal claim is that until `--status` lands, "the log is read with
   `wc -l` and `cut`." `wc -l` gives a total line count; it cannot tell `EXEMPT` from `BLOCK`. `cut`
   extracts a field but needs `sort`/`uniq -c` (or similar) to turn that into a count, and needs the
   timestamp field bucketed by date to answer the actual stated question — *"am I leaning on
   `TEST_EXEMPT` weekly or hourly."* Neither of those two named tools alone answers that question. This
   isn't fatal — any engineer can write the one-liner in thirty seconds — but it's the one place in this
   document where a measured claim isn't backed by the literal, re-runnable command the Latency section
   and the O3 size table both now provide, right after this document's own history shows what happens
   when a derivation isn't written down (two stale-count incidents, both caught by a prior judge round).
3. **Does `--status` now deserve to block v1, or does follow-up 1 still stand?** Follow-up 1 still
   stands, and if anything the log's return strengthens that call rather than weakening it. Task 14 was
   already round 2's partial substitute for the arming question; the log (even read manually, per
   concern 2 above) now gives at least a real, if clumsy, answer to the erosion question round 2 ranked
   first. Neither remaining gap is a *zero*-substitute situation anymore. I'd flag one internal tension
   worth tightening, not fixing: the sentence "a log nothing reads is the same defect as no log" is
   immediately followed by a paragraph explaining that the log *can* be read and *does* answer the
   round-2 question — the two sentences pull in different directions about how bad the gap actually is.
4. **Is the `TEST_EXEMPT` logging surface adequate for an artifact meant to be read back?** I tested the
   regex directly rather than reasoning about it:

   ```
   tab   -> rejected   newline -> rejected   ESC -> rejected   DEL -> rejected
   ZWSP (U+200B)      -> accepted
   RTL override (U+202E) -> accepted
   ```

   `^[^\x00-\x1f\x7f]{1,200}$` correctly blocks tabs and newlines (protects the TSV column structure)
   and blocks ESC (protects a terminal reading the log with `cat`). It does **not** block non-ASCII
   invisible or bidi-override Unicode. That's exactly the class of defect this same repo already has a
   name for — `hooks/scan-invisible-unicode.sh`, written and tested but explicitly listed in
   `rules/gates.md` as a dormant hook that "never runs." This spec doesn't cross-reference that gap for
   its own newly-created, human-read free-text field. Real-world severity is low here — the log is
   `0600`, local-only, and the only person who can write a `TEST_EXEMPT` reason is the same developer
   who reads it back — so this is a documentation gap, not an active exploit path, but it's worth one
   sentence in §Decision logging rather than silence.

## What could go wrong / what I'm unsure about

- The erosion question's "answered by `wc -l` and `cut`" claim is asserted, not demonstrated — no
  literal command, no test, unlike every other measured claim in this document post-round-2.
- A stale-but-nonempty log can be misread as current proof of arming; the caveat that prevents that
  misreading exists, but two sections away from the claim it should sit beside.
- `TEST_EXEMPT` free text can carry invisible/bidi Unicode the regex doesn't filter, in a repo that
  already has an unwired scanner built for exactly this. Low severity (local, single-writer, `0600`),
  but undisclosed.
- Still 100% unimplemented (checklist 0/15, `phase: planning`) — everything above is a property of the
  *plan*, not of anything running.

## What I'd double-check before merging

- Add the actual one-liner for reading the log (e.g. `cut -f2 test-marker.log | sort | uniq -c`, plus a
  date-bucketed variant) into §Decision logging, mirroring what §Latency already does for its own
  measured figure — cheap, and closes the one place this round found the derivation-storage habit
  didn't carry over.
- Either fold the asymmetry claim's temporal caveat in beside it, or add a one-line pointer back to
  §Scope's accepted-cost callout so the two don't read as contradictory in isolation.
- Decide, as a explicit user call (not a drafting default), whether the `TEST_EXEMPT` regex should also
  exclude non-ASCII format/bidi characters, or whether the low-severity, single-writer threat model is
  accepted as-is — either answer is fine, but right now it's simply unaddressed.
- Confirm task 1's ADR, when written, captures the log's restoration and the reasoning that reversed
  revision 8's cut — the standing-decisions section is currently the only record of *why* the log came
  back, and that section lives in a document whose own checklist expects it to eventually be pruned.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | pass | Round 2's recommendation was taken faithfully and restored via `git show` from the exact prior revision rather than re-typed — provably the same text, not a fresh guess at it. |
| execution | concern | The design's own claim that the log "answers the erosion question" via `wc -l` and `cut` isn't fully true of those two tools alone — the stated question (weekly vs. hourly `TEST_EXEMPT` use) needs field-splitting and date-bucketing neither tool does by itself. |
| trajectory | pass | Sound, evidence-driven revision: prior judge finding → restored from the exact commit that had it → re-measured and re-verified line counts rather than re-asserting them. |
| regression | pass | No code exists yet; the change is additive prose restoring a previously-specified, previously-judged section. |
| context_budget | pass | Lives under `docs/features/`, read on demand, not always-on context; the file-size waiver is scoped to this file alone and its own justification is re-measured this round, not merely asserted. |
| traceability | concern | The asymmetry claim's temporal limit (proves arming *as of the last entry*, not now) is disclosed, but two sections away from the claim itself; the log-reading recipe lacks the literal derivation the rest of the document now insists on. |
| success_masking | pass | The design is explicit that a green marker or a green mutation run never certifies test *quality*, only that a suite ran against these exact bytes — no inflated claim of coverage found. |
| intent_drift | pass | The restoration is scoped exactly to what round 2 asked for (the log), nothing else was rewritten or expanded; `--status` and the `INCLUDE`/`FOREIGN` fold stay deferred as before. |
| checkpoint | pass | Clean, atomic, individually-revertable commits per revision (`36a0880` → `fa44399` → `0294809` → `17d2379` → `9251218`); the checklist's revert-pair table for the eventual code is already drafted. |
| audit_trail | pass | The round-2 concern (bypass usage has zero durable record) is now structurally resolved by the log's return; the standing-decisions section documents the restoration's own rationale and date. |

## Concerns

- The claim that the decision log's erosion question is answerable today via "`wc -l` and `cut`" is
  asserted rather than demonstrated — those two tools alone don't distinguish `EXEMPT` from `BLOCK` or
  bucket by time, which is the actual question the log exists to answer; add the literal one-liner.
- The asymmetry claim ("non-empty log proves armed and firing") is true only as of the log's last entry,
  not as a live/current guarantee — the caveat exists but lives in a different section than the claim.
- `TEST_EXEMPT` free text is validated against `^[^\x00-\x1f\x7f]{1,200}$` (verified: blocks tab,
  newline, ESC, DEL; does not block ZWSP or RTL-override Unicode) — a known, named, unwired risk class
  in this same repo (`scan-invisible-unicode.sh`) that isn't cross-referenced for this new artifact.
  Severity is low (local, `0600`, single writer/reader) but currently undisclosed.
- "A log nothing reads is the same defect as no log" is immediately undercut by the next paragraph
  explaining the log *can* be read manually and does answer round 2's top-ranked question — worth
  tightening the wording so the two sentences agree on how large the remaining gap actually is.
- `--status` remaining deferred to follow-up 1 (not blocking v1) still looks like the right call: task
  14 substitutes for the arming question, the log now substitutes (weakly) for the erosion question —
  neither gap is a zero-substitute situation anymore.
- Everything above scores the plan; zero implementation exists yet (checklist 0/15).

risk=medium confidence=high
