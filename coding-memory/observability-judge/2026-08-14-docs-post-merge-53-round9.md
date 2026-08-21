# Observability judge verdict — verification-marker-gate, round 9 (architecting, advisory)

- repo: `/Users/marksuyat/.claude/.claude/worktrees/tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `859f303f107dfc57170ce4620d5ff040b2d0e039`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`, verified: 15 unchecked, 0 checked)
- ts: `2026-08-14T01:39:51Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 16, blob
  `bfe7ad457022ae582726bcbbee1a10f83ee3ac37`, working tree matches HEAD exactly — `git diff HEAD` empty)
- prior verdict: `2026-08-14-docs-post-merge-53-round8.md` (head `263e430`, architecting, risk=medium)

## What was changed

The entire diff between round 8's HEAD and this one is 151 lines, and I read all of it — it is exactly
the two things the round description claims, nothing else. First: the single Gherkin scenario that
asserted the log's field 3 for `MSG_NO_MARKER` alone is deleted and replaced by one `Scenario Outline`
with two `Examples` tables — 8 rows for the doors the Python decision call reports (read from TSV field
2) and 4 rows for the doors bash raises on its own before any TSV line exists — each row asserting both
field 3 (the door constant) and field 4 (pair or `-`). A parallel `printf` line and a "twelve doors write
a line, not eight" paragraph were added to §Decision logging naming the literal text the four bash-native
doors write. Second, unrelated: the size-measurement `awk` script was replaced with one that classifies
every line into exactly one bucket and prints a `sum` that must equal `total`, and every floor/prose
figure recorded before revision 16 is restated using the corrected command.

## Does it do what you wanted?

Yes, on both counts, and I verified rather than trusted the prose.

**The round-8 gap is closed.** Round 8 found 11 of 12 loggable doors had no test asserting what their
log line's field 3 contains — a classic case where a green suite could mask 11 wrong or blank reason
strings. I read the new outline (`:1393-1429`) against §The doors and §3's field-domain table: the first
`Examples` table's 8 rows are exactly the 8 constants TSV field 2 can carry (`MSG_UNSUPPORTED_FORM`,
`MSG_NO_MARKER`, `MSG_BAD_MARKER`, `MSG_STALE_SUBJECT`, `MSG_STALE_TEST`, `MSG_NOTHING_RUNNABLE`,
`MSG_BAD_EXEMPT`, `MSG_GIT_FAILED`), and the second table's 4 rows are exactly the 4 bash raises itself
(`MSG_CLASSIFIER_MISSING`, `MSG_BAD_PAYLOAD`, `MSG_CLASSIFIER_FAILED`, `MSG_CLASSIFIER_BAD_OUTPUT`) —
the gap round 8 named by name. `MSG_NO_PYTHON` is correctly excluded with its own separate scenario
(`:1447-1453`) asserting the absence of a line, not a wrong one. I confirmed the old single-door scenario
is fully gone (no duplicate left behind — `grep MSG_NO_MARKER` shows it now only appears in the outline's
table and in unrelated exit-code scenarios, not in a second log-assertion). 8 + 4 = 12, matching the
frontmatter's own count.

**The size-measurement fix is real, and I re-derived it independently rather than trusting the prose.** I
ran the new `awk` script against `git show HEAD:...` myself: `total=2239 floor=1140 prose=1099 sum=2239`
— matches the document exactly, and `sum == total` confirms the classification has no double-count. I
then checked out revision 15's blob (`263e430`) and ran the same corrected script against it:
`total=2163 floor=1089 prose=1074` — matches this revision's claimed correction (`1,089`/`1,074`, not
the `1,127`/`1,036` revision 15 was committed with) exactly. The waiver's conclusion is unaffected either
way (floor still clears 800 by a wide margin), but the correction itself is accurate, not asserted.

**Re-checked per this round's instruction: round-2 (bypass rate unmeasurable) and round-7 (log field
mapping unstated) both still hold closed.** The `case "$f1" in EXEMPT) reason=$f3 ;; BLOCK) reason=$f2
;; esac` mapping from round 7 is untouched by this diff, still present, still correctly distinguishes the
two log-writing paths.

## The round's actual question: does 12/12 coverage change the `--status` deferral, and is anything left untraced?

**It doesn't resolve the deferral, but it changes what the deferral now costs — for the better.** Before
this round, even a hypothetical reader of the log (a human running the documented `awk`/`cut` queries, or
a future `--status`) could not have trusted 11 of 12 door types' field 3 — the write side itself was
unverified. Now that the write side is tested for all 12, the accepted gap narrows to exactly what the
spec already claims it is: nobody automatically consults a log that, when consulted, will now say the
right thing. That is a real, still-open observability gap, but it is the *disclosed* one, not a hidden
second one stacked underneath it. The spec is honest about this in its own words (`:1765-1770`, "a real
half-measure, recorded as one rather than presented as complete") and prioritizes closing it
(`:2221-2225`, follow-up 1, "raises its priority above where revision 8 left it"). At an advisory,
architecting-stage review with 0/15 implemented, I read this as an acceptable, well-disclosed v1 scope
line — not a defect to hold up implementation over.

**One decision in the whole flowchart still leaves zero durable trace: `MSG_NO_PYTHON`.** It blocks (exit
2) but writes no log line anywhere, because no `<repo>` has been resolved yet to write into (`:1756-1760`).
This is not new to this revision and not hidden — the spec names it as "the thirteenth door" and argues
it mirrors identical behaviour already live in three sibling guards (`git-guard.sh`, `judge-guard.sh`,
`merge-guard.sh`), all of which block globally on a missing `python3` with no log either. I did not find
a plausible fix within this feature's scope (there is genuinely no repo-scoped file to append to before
the toplevel resolves, and a machine-global log is a different, unscoped design decision this feature
correctly declines to make unilaterally). I'm noting it as the literal answer to "any remaining decision
with no durable trace" rather than treating it as a new finding — it is pre-existing, disclosed, and
consistent with established precedent elsewhere in this account's hook family.

Every `ALLOW` path is also unlogged, but that is stated as deliberate ("logging every allow would bury
the two rates the log exists to expose") and is the correct call for a log whose entire purpose is
erosion signal, not a full audit trail — the spec is explicit that this log is "instrumentation, not
evidence" (`:1805`) and should not be read as more than that.

## What could go wrong / what I'm unsure about

- The `--status` deferral is still real: nothing in v1 automatically distinguishes "armed and quiet" from
  "armed but silently never pairing" between runs of checklist task 14. This round doesn't change that —
  it only makes the log worth reading once someone does. Not a new concern; tracked as follow-up 1 at
  raised priority.
- `MSG_NO_PYTHON` remains untraceable by construction (no repo resolved yet to log into). Pre-existing
  across three sibling guards, not introduced or worsened here — flagged for completeness, not as a
  defect of this feature.
- Everything above is still a property of the plan. Checklist is 0/15; nothing has run. Task 6 (the
  suite that will actually implement this outline) is the place a real gap could still be introduced
  even with the spec now correct.

## What I'd double-check before merging

- When task 6/14 are implemented, confirm the outline's 12 rows are literally what the test suite
  parametrizes over — not re-derived by hand into 12 separate assertions that could quietly drift from
  the table again.
- Confirm follow-up 1 (`--status`) actually lands early post-v1, since this round's fix is precisely what
  makes that follow-up valuable rather than merely aspirational.
- Nothing else outstanding from this round; round-2 and round-7 findings re-verified closed, round-8
  finding verified closed with independently reproduced measurements.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | pass | Round 8's specific finding (field-3 tested for 1 of 12 doors) is closed correctly and completely — verified against the outline's two Examples tables and §The doors, not just read. |
| execution | concern | No code exists yet (expected at this stage, 0/15) — carried as a stage marker, not a new defect; the spec itself is now internally consistent for all 12 doors. |
| trajectory | pass | Both changes are independently re-derived and confirmed: the outline's row count matches the door inventory, and the corrected size-measurement script reproduces the claimed 1,140/1,099 (rev 16) and 1,089/1,074 (rev 15, corrected) exactly. |
| regression | pass | Diff is 151 lines, spec-only, exactly the two changes described — no drive-by edits elsewhere in a 2,239-line file. |
| context_budget | pass | `docs/features/`, loaded on demand; growth stays under the already-granted, measurement-backed waiver; the outline itself *reduces* future growth pressure (12 cases cost roughly two prose paragraphs) rather than adding to it. |
| traceability | pass | The log's field-3 contract is now documented and test-enforced for all 12 loggable doors, closing the exact gap round 8 named — a genuine improvement over round 8's partial state. |
| success_masking | concern | Writer-side masking (wrong/blank reason for 11/12 doors) is closed. Residual, disclosed masking risk remains: nothing computational catches the log going silently unread — only a human running the documented queries or re-running task 14 would notice erosion. Unchanged by this round; not new. |
| intent_drift | pass | The diff is exactly the round-8 fix plus the size-measurement correction; no unrelated edits found on inspection of the full diff. |
| checkpoint | pass | Single labelled commit (`859f303`) on a clean chain; working tree matches HEAD exactly; trivially revertible (docs only). |
| audit_trail | pass | Dated, attributed to round 8 and the compliance judge by name, and the size correction is self-critical (names its own prior overstatement, corrects it, explains why the waiver's conclusion is unaffected) — independently reproduced by me against two separate git blobs. |

## Concerns

- The `--status` deferral (follow-up 1) is unresolved by this round — it was never this round's target,
  and closing the write-side coverage gap makes that follow-up more valuable, not less necessary. Still
  the single largest residual observability gap in this design.
- `MSG_NO_PYTHON` writes no durable trace anywhere (by construction — no repo is known yet). Pre-existing
  across three sibling guards; not a new or worsened risk from this feature, but it is the literal answer
  to "any decision with no durable trace" and is recorded here for completeness.
- Round-2 (bypass rate unmeasurable) and round-7 (log field mapping unstated) findings re-checked and
  remain closed.
- Round-8 finding (field-3 untested for 11/12 doors) verified closed — independently confirmed the
  outline's 8+4 rows match the door inventory exactly, with no duplicate or orphaned old scenario left
  behind.
- The size-measurement correction was independently re-derived against both the revision-16 and
  revision-15 blobs and matches the document's claims exactly (2,239/1,140/1,099 and 1,089/1,074
  respectively); the waiver's conclusion is unaffected by the correction.
- Latency budgets remain correctly framed as targets, not measurements (checklist task 10) — not scored
  as a defect, per this round's own framing.
- Still 0/15 implemented; every finding above is a property of the plan, not of running code.

risk=low confidence=high
