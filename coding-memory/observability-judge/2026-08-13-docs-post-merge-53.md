# Observability judge verdict — verification-marker-gate, round 6 (architecting, advisory)

- repo: `tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `287add5bd94cc07c1bf433be55e011ec4e752fda`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`, `branch: none`)
- ts: `2026-08-13T01:41:08Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 6, 1420 lines)

## What was changed

This isn't code — it's a design document for a future commit-blocking hook, and round 6 is the
sixth pass of fixing holes a judge found in earlier passes. The part this run was asked to focus on
is new in round 6: a **decision log**. Every time the future hook would block a commit or wave it
through on an exemption, it's supposed to write one line to a file (`hooks/state/test-marker.log`)
saying what happened and why. Before round 6, only exemptions got written down — you could tell
"how often did someone bypass this," but not "does this thing ever actually fire." Round 6 adds
logging for blocks too, and a `--status` command that prints the tallies.

## Does it do what you wanted?

Mostly yes, with two real gaps in the new logging design and one old, still-unresolved number.

**The good part.** Field 3 of every log line is the specific reason code (e.g.
`MSG_STALE_TEST`), and there are 14 distinct reason codes, one per way the gate can refuse a
commit — so "which of the 14 doors fired" is cleanly answerable by grepping the log. That's the
core ask, and it's solid.

**Gap 1 — the log can't tell you the denominator.** Only blocks and exemptions get a line; allowed
commits don't. That's a defensible choice for the stated goal ("am I leaning on the exemption
weekly or hourly") — but it means the log can never distinguish "the gate is healthy and nothing
needed blocking" from "the gate is switched on but is silently never finding anything to check"
(e.g. a bug that always computes zero pairs). Both look like an empty log forever. The design
already solved the sibling problem — "is the gate even installed" — with `--status` printing
`ACTIVE`/`INERT`. It doesn't extend that same instinct to "active, but never actually firing."

**Gap 2 — field 4 ("the pair") isn't always something the code has yet.** The design's own
flowchart checks the exemption (`TEST_EXEMPT`) *before* it ever works out which files are being
committed or pairs them with their tests. So when the spec says an exempted commit logs "the pairs
skipped," that information doesn't exist yet at the point the log line is written — and for the
"exemption rescues a commit aimed at another repo" scenario (§3, `FOREIGN`), it's worse than
missing: the whole reason that case is `FOREIGN` is that *which repo* is unknowable, so there is no
way to compute "the pairs" at all. The same gap exists on the block side: only 4 of the 14 reason
codes (the ones about a stale or missing marker) fire at a point where a specific pair is actually
known. The other 10 — a broken Python helper, an unreadable payload, an unsupported command shape,
an unresolvable target repo, a failed git command — all fire *before* any pair exists, and the spec
never says what goes in that field for them. None of the document's own example scenarios exercise
one of those 10 doors with a logged line, so nothing forces this to get resolved before it's coded.

**The old number.** The latency section still states "python3 startup at ≥56 ms," attributed to
"the observability judge." I checked my own prior verdicts on this exact document: that number was
measured at 56.3 ms on 2026-08-02, then re-measured by this same judge at 20–30 ms on 2026-08-04
(flagged as a `fail` on `success_masking` then, precisely because an inflated floor makes the ≤80 ms
budget impossible to fail). I re-measured it again just now, fresh, on this machine: `python3 -I -c
'import json'` averages **~40 ms** across 5 runs. So the "true" number has read 56, then 20–30, then
40 across three separate points in time — it's genuinely noisy, not a fixed constant — but round
6's changelog claims to have closed "all seven" open items and doesn't mention this one, even
though it was explicitly flagged as unresolved as recently as round 5. The design does have a
safety net (checklist task 10 says "measure and record all three [budgets]... revise a budget if a
figure exceeds it"), so this isn't silently swept under the rug at implementation time — but the
document, as written today, still asserts a figure this same judge already found to be wrong once.

## What could go wrong / what I'm unsure about

- If the field-4 gap ships uncaught, the two most likely outcomes are (a) an implementer picks
  something ad hoc and inconsistent for the 10 pre-pairing doors and the `FOREIGN`-exempt case, or
  (b) the code throws trying to serialize a pair that was never computed. Neither is catastrophic —
  this is a momentum guardrail, not a security control, and it's still in `phase: planning` with no
  code — but it's exactly the kind of thing that should be nailed down in the spec, not discovered
  mid-implementation.
- The "gate is active but silently checks nothing" blind spot (Gap 1) only matters once this is
  live in a real repo for a while. It's not testable pre-merge in the usual sense (the checklist's
  unit tests separately verify pairing logic works), but it means the *log itself*, once running,
  can't be trusted as evidence the gate is doing anything.
- I did not re-run any code — there is none yet. Everything above is a documentation-only read plus
  fresh, first-party timing measurements I ran myself on this machine.

## What I'd double-check before merging (i.e., before this goes to the compliance judge / task 6)

- Add explicit scenarios (or an explicit "N/A" convention) for what field 4 contains on the 10
  pre-pairing block doors, and resolve the `FOREIGN`+exempt contradiction — either compute the pair
  set before logging (extra cost, but honest) or change the spec's own claim about what that field
  holds.
- Decide, and write down, whether the log needs *any* signal for "the gate ran and found nothing to
  check" (even a low-noise one, distinct from full allow-logging) so `--status` can eventually
  answer "is this thing actually doing anything" the same way it already answers "is it installed."
- Re-derive the `≥56 ms` / `≤80 ms` figures on the actual implementation machine at task 10 rather
  than trusting the number currently in the prose, and note in the ADR (task 1) that this number has
  moved three times across three measurements — that's worth a sentence for whoever reads it next.

## Dimension table

| dimension | verdict | why |
|---|---|---|
| intent | pass | Round 6 does what it says: closes seven prior judge-flagged items, and the new decision-logging feature is exactly what was asked for (log blocks, not just exemptions). |
| execution | concern | Design-internal gaps found above (field-4 schema unsatisfiable/underspecified for most doors; unreconciled latency figure) — sound as prose, not yet internally consistent as a spec an implementer can follow without guessing. |
| trajectory | pass | Very strong measurement discipline throughout (G1-G9, M3-M5, N1/N2) and honest self-correction of prior overclaims. The two gaps found here sit in the newest, least-scrutinized surface (D4/D5), which is exactly what this judge pass exists to catch. |
| regression | pass | Docs-only change; no code exists to regress. Corrections to prior rounds are each backed by a fresh, cited measurement. |
| context_budget | pass | 1420-line spec is large and self-acknowledges the debt ("O3 — the shrink, still owed"), but it's a `docs/features/*` file loaded on demand, not an always-on rule/skill/prompt. |
| traceability | concern | The `≥56 ms` figure is attributed to this judge but contradicts this judge's own later re-measurement (20-30ms, 2026-08-04) and a fresh measurement just now (~40ms); round 6's "closed all seven" summary doesn't surface this as still-open. |
| success_masking | concern | Allow-path is never logged, so a healthy-and-quiet gate is indistinguishable from an active-but-broken one that always finds zero pairs; ties to the still-unresolved risk that the latency budget could be unfalsifiable at task 10. |
| intent_drift | pass | Round 6 stays inside its own stated scope (the seven named items); folding the separate defect checklist into this file is exactly the one-canonical-file discipline, not scope creep. |
| checkpoint | pass | Docs-only commit on a feature branch, `phase: planning`, `branch: none` recorded — nothing irreversible done, clean revert point. |
| audit_trail | concern | Field 3 (reason code) is solid and gives door-level attribution for all 14 doors. Field 4 (the pair) is well-defined for only 4 of the 14 block doors and is unsatisfiable-by-construction for the `FOREIGN`-exempt scenario; the infrastructure-failure doors (broken classifier, missing python3, git call failure) also carry no stderr/detail field, which is precisely the class most useful to capture for debugging a spurious block. |

## Concerns

- Log field 4 ("the pair") is undefined for 10 of 14 block doors and self-contradictory for the
  `FOREIGN`+`TEST_EXEMPT` scenario, where the target repo — and therefore any pair — is unknowable
  by the design's own definition of `FOREIGN`.
- No allow-path signal at all means the log can never distinguish "gate healthy, nothing to block"
  from "gate active but silently never forming pairs" — a blind spot the design already solved for
  installed-vs-not (`--status` ACTIVE/INERT) but not extended to firing-vs-not.
- The `≥56 ms` python3-startup figure, attributed to this judge, is the third different number this
  judge has recorded for the same quantity on this document across three dates (56.3ms → 20-30ms →
  ~40ms just now); round 6's "closed all seven" framing does not surface this as still open, though
  checklist task 10 does provide a re-measurement safety net before merge.
- None of the document's own Gherkin scenarios exercise a logged BLOCK line for any of the 10
  pre-pairing doors, so the field-4 gap above has no test pressure forcing it to be resolved before
  task 6 is written.
- (Pre-existing, self-acknowledged by the document itself, not new): `hooks/state/`'s permission
  mode depends on which of the writer or the gate creates the directory first — already flagged in
  the doc's own text, carried forward here for completeness only.

## Risk / confidence

risk=medium confidence=high
