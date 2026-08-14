# Observability judge verdict — verification-marker-gate, round 8 (architecting, advisory)

- repo: `/Users/marksuyat/.claude/.claude/worktrees/tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `263e430ec8767f73503f0be63d41092f83d6d2f1`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`)
- ts: `2026-08-14T00:55:40Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 15, blob
  `7965f387dbd549be3bae09dfb5708209eb16c11c`, 2,163 lines / 66 scenarios per the document's own O3
  measurement, confirmed against `git rev-parse HEAD:docs/features/verification-marker-gate.md`)
- prior verdict: `2026-08-13-docs-post-merge-53-round7.md` (head `90924db`, architecting, risk=medium)

## What was changed

Two things landed since round 7. First, the round-7 finding — the log's `reason` field was written as
a uniform `$f3` copy from the TSV line, which is wrong for a `BLOCK` (the door name lives in wire field
2, not field 3) — is now closed with an explicit WRONG/CORRECT code pair (`:1662-1677`): a `case "$f1"
in EXEMPT) reason=$f3 ;; BLOCK) reason=$f2 ;; esac`, quantified against the actual damage ("logs the
door name for zero of the eight" doors field 2 can carry), plus a new requirement that the scenarios
pinning this section assert field 3's value **per door**, not just that a line was written (`:1679-1685`).
The `$ts` command is now pinned too (`date -u +%Y-%m-%dT%H:%M:%SZ`, with an inline note that it never
crosses the wire). Second, and unrelated: the `TEST_EXEMPT` validator moved from `re.match` to
`re.fullmatch`, because Python's `$` anchor admits one trailing newline — a defect that survived four
revisions restated as fixed. Two new Gherkin scenarios discriminate it (newline-last vs. the pre-existing
embedded-newline case, which is explicitly marked as *not* the regression test), and a 200-bytes-plus-
newline case pins the length bound against the same escape.

## Does it do what you wanted?

Mostly, and the `re.fullmatch` fix is clean — correctly diagnosed, correctly scoped, correctly tested.
The round-7 fix is also genuinely closed for what round 7 flagged: I traced the WRONG/CORRECT pair and
the "assert field 3 per door" requirement against §3's field-domain table, and they cover exactly the
**eight** doors that can appear in TSV field 2 (`MSG_UNSUPPORTED_FORM`, `MSG_NO_MARKER`, `MSG_BAD_MARKER`,
`MSG_STALE_SUBJECT`, `MSG_STALE_TEST`, `MSG_NOTHING_RUNNABLE`, `MSG_BAD_EXEMPT`, `MSG_GIT_FAILED`) —
precisely the set round 7's finding was about.

**But that scope is also the gap.** Thirteen doors exist; one (`MSG_NO_PYTHON`) explicitly writes no log
line at all (`:1709-1713`, "there is no `<repo>` to write to"). The field-4-total accounting (`:1702-1707`)
confirms the other **twelve** all write a log line — which means the four bash-native
"component-liveness" doors (`MSG_CLASSIFIER_MISSING`, `MSG_CLASSIFIER_FAILED`, `MSG_CLASSIFIER_BAD_OUTPUT`,
`MSG_BAD_PAYLOAD`) also log a `BLOCK` line, but for none of them is there a TSV line to read `$f2` from —
these are bash's own doors, raised before or without a well-formed decision-call output at all. Nothing
in §Decision logging says what text bash writes as the reason for these four, and I checked every
Gherkin scenario that mentions each of the four doors (`:1235-1251` for the two `CLASSIFIER_*` scenarios,
`:1268-1281` for the two `BAD_OUTPUT` edge scenarios, `:1469-1474` for `BAD_PAYLOAD`) — none of them
assert a log line. Applying this document's own diagnostic to itself (`:1858-1861`, "which stated
behaviours have no enforcing command at all?"): the log's general field-3 definition, *"the `MSG_*`
constant that fired"* (`:1636-1638`), is a MUST-shaped claim spanning all 13 doors, but is now
scenario-enforced for only 8 of them. This is the same defect shape round 7 fixed — a blanket derivation
that silently produces the wrong (or here, unspecified/unverified) text for a subset of doors — recurring
one layer further out, exactly the pattern this spec's own revision-11-through-14 chain repeatedly named
and then found again inside its own fix.

Practical stakes: these four rows also feed the erosion query `awk -F'\t' '$2=="BLOCK" {print $3}'`
(`:1735`), the canonical "which doors actually fire" read-back this section exists to support. A wrong
or blank reason on these rows corrupts that query's output specifically for infrastructure-failure
events — lower frequency than the eight routine doors, but the same class of silent corruption the
round-7 fix was written to prevent.

Re-checked per this round's instruction: the round-2 finding (bypass rate permanently unmeasurable) is
still closed. The log, its read-back commands, mode/format pins, and the round-7 mapping fix are all
present, reasoned, and — for the eight doors they cover — now test-required.

## What could go wrong / what I'm unsure about

- The four bash-native doors' log content is unspecified and untested: no WRONG/CORRECT pair, no stated
  literal reason text, no Gherkin scenario. An implementer following the spec exactly could log the
  wrong string, an empty field, or nothing at all for these four, and task 6 as currently worded would
  not catch it (it requires the log line "wherever a scenario names one," and no scenario names one
  here).
- This narrows, rather than reopens, round 7's finding — the eight doors round 7 was about are now
  solidly fixed and test-required. The residual risk is scoped to component-liveness failures, which are
  rarer than the routine block/bypass doors this control mostly exists to measure.
- The `re.fullmatch` fix is sound on its own terms; I did not find a further escape in the same family
  (e.g., embedded-vs-trailing placement is now correctly distinguished, and the byte-vs-character bound
  is independently re-verified).
- Latency: the four budget rows remain correctly framed as targets, not measurements — checklist task 10
  is where they get measured against real code. Not scored as a defect here, per the round's own framing.
- Everything above is a property of the plan. Checklist is 0/15; nothing has run.

## What I'd double-check before merging

- Add a third line to the `case "$f1" in ... esac` pattern — or a parallel statement immediately after
  it — naming the literal reason text each of the four bash-native doors writes (most naturally: the
  literal `MSG_*` constant bash itself already used to print the message), so the log's field-3
  contract is stated for all 12 loggable doors, not 8.
- When task 6 is written, add log-content assertions for `MSG_CLASSIFIER_MISSING`, `MSG_CLASSIFIER_FAILED`,
  `MSG_CLASSIFIER_BAD_OUTPUT`, and `MSG_BAD_PAYLOAD` alongside the existing per-door requirement for the
  eight in-band doors — otherwise a green suite built to spec still can't prove these four log correctly.
- Re-confirm at implementation time that the four bash-native log-writes and the TSV-sourced log-writes
  are exercised by the same commit (task 6/7, as already planned for the rest of this feature) so this
  gap can't ship half-wired even after it's specified.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | concern | Round 7's specific finding (uniform `$f3` copy) is fully and correctly closed for the eight in-band doors; the same defect class remains open, undocumented, for the four bash-native doors that also log a reason. |
| execution | concern | No code exists yet (expected at this stage); the test plan as specified (task 6) does not require covering the four-door gap, so a suite built exactly to spec would not catch it. |
| trajectory | pass | The round-7 fix and the independent `re.fullmatch` fix are both correctly diagnosed, quantified against real damage, and tied to discriminating scenarios — sound reasoning, not luck. |
| regression | pass | Diff is spec-only; no evidence of adjacent breakage. |
| context_budget | pass | `docs/features/`, read on demand; growth continues under the already-granted, measurement-backed size waiver — legitimate new contract content, not padding. |
| traceability | concern | Nothing in §Decision logging states what the four bash-native doors write as their log reason — the exact kind of unpinned-construct gap this document's own prose repeatedly names as its recurring defect class. |
| success_masking | concern | A test suite built exactly to task 6's current wording would go green while leaving the reason field wrong or blank for four doors — the same success-masking shape round 7 fixed, recurring one layer out. |
| intent_drift | pass | The `re.fullmatch` fix and its two new scenarios are tightly scoped to the newline-anchoring defect; no drive-by edits. |
| checkpoint | pass | Single, well-labelled commit (`263e430`) on a clean chain; working tree clean; trivially revertible (docs only). |
| audit_trail | pass | Revision 15's changes are dated, attributed to the round-7 advisory, quantified ("zero of the eight," "never errors"), and the size/scenario counts are re-derived from the staged blob rather than recalled. |

## Concerns

- The round-7 fix (explicit `case`-based `reason` mapping, plus "assert field 3 per door") is scoped to
  the eight doors TSV field 2 can carry; it does not extend to the four bash-native
  "component-liveness" doors (`MSG_CLASSIFIER_MISSING`, `MSG_CLASSIFIER_FAILED`,
  `MSG_CLASSIFIER_BAD_OUTPUT`, `MSG_BAD_PAYLOAD`), which also write a `BLOCK` log line per the
  field-4-total accounting but have no stated reason text and no scenario pinning one.
- Applying the document's own audit method to itself — "which MUST-shaped sentences have no enforcing
  command or scenario?" — finds this gap directly: the log's general field-3 definition spans 13 doors
  but is scenario-enforced for 8.
- These four doors' rows also feed the `awk -F'\t' '$2=="BLOCK" {print $3}'` erosion query; a wrong or
  blank reason here would silently corrupt that query's output for infrastructure-failure events
  specifically, narrower in frequency than the eight routine doors but the same failure class.
- Round-2 finding (bypass rate unmeasurable) re-checked and remains closed — the decision log, its
  read-back commands, and its mode/format pins are all present and reasoned.
- The independent `re.fullmatch` fix (this round's second change) is sound: correctly diagnosed,
  correctly scoped by newline placement, and backed by scenarios that actually discriminate the
  regression from the pre-existing embedded-newline case.
- Latency budgets remain correctly framed as targets, not measurements (checklist task 10) — not scored
  as a defect.
- Still 0/15 implemented; every finding above is a property of the plan, not of running code.

risk=medium confidence=high
