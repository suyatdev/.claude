# Observability judge verdict — verification-marker-gate, round 7 (architecting, advisory)

- repo: `/Users/marksuyat/.claude/.claude/worktrees/tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `90924db35be52adb240454f9477d58271827e2b7`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`)
- ts: `2026-08-13T23:26:33Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 14, blob `ca8a372404213bb79b2cf5a9bd461429227f9d1b`,
  2,085 lines, `wc -l` and `git hash-object` both confirmed against the working tree)
- prior verdict: `2026-08-13-docs-post-merge-53-round6.md` (head `3f068d9`, architecting, risk=medium)

## What was changed

Revision 14 applies ADR 0026 (`docs/decisions/0026-the-gate-does-no-json-parsing.md`, Accepted): the
JSON wire contract that stood through revision 13 — bash parsing the classifier's JSON stdout at node
`CO`, then re-parsing each on-disk marker's JSON at node `M` — is deleted outright, not deprecated.
Classification, path collection, pairing, marker reading and blob comparison now run inside **one
`python3` process** (`hooks/lib/decide-commit-gate.py`), which emits **one tab-separated line, four
fields, never empty**, that bash consumes with `read -r`. The opt-in boundary (node `G`, "has this repo
installed the writer") is unmoved — bash still clears it before the one decision call runs — but
everything downstream of it, including the bash-ERE `TEST_EXEMPT` check pinned in revisions 11–12,
moved into Python and both bash forms were deleted. Diff since round 6 (`git diff --stat 3f068d9..HEAD`)
touches only the spec, the new ADR, round-6's own verdict files, and `CODING_MEMORY.md` — no drive-by
edits.

## Does it do what you wanted?

Mostly. My round-2 read ranked the decision log's earlier removal as the more damaging gap — the
`TEST_EXEMPT` reason was validated and then thrown away, making bypass rate permanently unmeasurable.
Revision 9 restored the log; this round's job was to check whether folding everything into one TSV line
still lets that restored log distinguish `EXEMPT` from `BLOCK` from a silent `ALLOW`.

**The data survives the merge.** I traced the fields by hand against §3's contract:

- Field 1 (`outcome`) is `ALLOW`/`BLOCK`/`EXEMPT` — the log is only ever written on the last two
  (flowchart node `DEC`), so `$verdict` is derivable from `$f1` unambiguously.
- Field 4 (`pair`) is identically named and identically shaped in both the TSV and the log schema — no
  ambiguity.
- Field 2 (`door`) carries the `MSG_*` constant for `BLOCK`; field 3 (`detail`) carries the validated
  `TEST_EXEMPT` reason for `EXEMPT`. Both values the log needs are present somewhere on the wire.

**But the mapping that bridges them is never written down as a single, explicit rule — and this spec
has burned five prior revisions finding exactly this shape of gap.** §"Decision logging" (`:1601-1613`)
states the log's four fields, then jumps straight to a `printf '%s\t%s\t%s\t%s\n' "$ts" "$verdict"
"$reason" "$pair"` sample using variables that are never assigned anywhere in that section. Reconstructing
where `$reason` comes from requires cross-referencing two other places:

- The top flowchart, node `LB`: `"BLOCK: the door named in field 2, logged"` (`:75`) — this is the only
  place that says a `BLOCK` log line's reason is `$f2`, not `$f3`.
- §3's field-domain table (`:536-543`), where `EXEMPT`'s field 3 is described as *"the validated
  `TEST_EXEMPT` reason"* — the same phrase used for the log's own field 3 — implying `$reason = $f3`
  for `EXEMPT` only.

So the source flips between `$f2` and `$f3` depending on outcome, and nothing in the section that
`printf` sample lives in says so. This is not hypothetical confusion: for most `BLOCK` doors, TSV field
3 is **not** `-` (it holds a trigger name for `MSG_UNSUPPORTED_FORM`, a remedy command for
`MSG_NO_MARKER`) — an implementer who wired `$reason=$f3` uniformly, the more natural reading of
"detail" sitting next to "door", would log a remedy string or a trigger name in place of the `MSG_*`
constant the log schema promises. One canonical scenario (`:1353-1357`, "a block is logged with the
message constant that fired") would catch this for `MSG_NO_MARKER` specifically, because it asserts the
log line *names* the constant — but no scenario independently asserts field 3's content for the other
seven `BLOCK` doors, and the `MSG_UNSUPPORTED_FORM` scenario at `:1359-1363` checks only field 4.

A second, smaller instance of the same class: the log's field 1 is specified only as *"ISO-8601 UTC
timestamp"* (`:1596`) — no `date` invocation is pinned anywhere, unlike literally every other
bash-version-sensitive construct in this file (the `printf`/`echo` split, the `mkdir -m`/`chmod` pair,
the locale-independent byte regex). `date -u +%Y-%m-%dT%H:%M:%SZ` is portable between BSD and GNU date,
so this one is lower-risk than the `$reason` gap, but it is the same unpinned-construct shape the
document's own ⚠️ callout at `:1622-1629` names as *"this spec keeps naming a behaviour... without
pinning the construct that produces it, and each instance has been found inside the fix for the one
before it."* That callout sits eleven lines above the `printf` sample that itself has the gap.

## What could go wrong / what I'm unsure about

- **The log-line write mapping ($f1..$f4 → $ts/$verdict/$reason/$pair) is nowhere stated as a single
  rule in the section that owns the log's format.** It is reconstructible correctly by a careful reader
  who cross-references the top flowchart's node `LB` annotation with §3's field-domain table, but §"How
  the line is written" — the section this spec explicitly says pins the requirement, not leaves it to
  implementation — does not itself say where `$reason` comes from, or that it flips source field by
  outcome. Given this spec's own count of five prior instances of "behaviour named, construct not
  pinned," this reads as a sixth, found in the same section revision 9 restored specifically because the
  round-2 judge flagged its predecessor's silence.
- The `$ts` timestamp's generating command is likewise never pinned, though the risk here is lower —
  `date -u +%Y-%m-%dT%H:%M:%SZ` behaves the same under BSD and GNU date, unlike the `echo`/`printf` trap
  this document already found and fixed.
- Task 6's Gherkin coverage of the log's field 3 content is uneven: one scenario (`MSG_NO_MARKER`)
  explicitly asserts the constant name; the `MSG_UNSUPPORTED_FORM` scenario asserts only field 4. A
  uniform `$reason=$f3` bug would be caught by the first and missed by the second unless task 6 is
  written more thoroughly than the checklist text currently demands.
- Latency: the four budget rows are correctly held as **targets, not measurements** — the document says
  so explicitly and repeatedly (`:1008-1013`), and checklist task 10 is where they get measured against
  real code. Not treated as a defect here, per the round's own framing.
- Everything above is a property of the plan. Checklist is 0/15; nothing has run.

## What I'd double-check before merging

- Add one explicit code sample to §"Decision logging" — mirroring the `printf`/`echo` and `mkdir`/`chmod`
  pattern already used four times in this file — showing exactly how `$verdict`, `$reason`, and `$ts`
  are derived from `$f1`/`$f2`/`$f3` (and from `date`), including the field-2-for-`BLOCK` /
  field-3-for-`EXEMPT` asymmetry by name.
- When task 6 is written, confirm every `BLOCK` door scenario that names a log line asserts field 3's
  *content* against the specific `MSG_*` constant (not just field 4), not only the `MSG_NO_MARKER` case.
- Re-confirm at implementation time that `decide-commit-gate.py`'s TSV emission and
  `test-marker-guard.sh`'s log-writing `printf` are exercised by the same commit (task 7 already treats
  them as one behaviour split by ADR 0026) so the mapping gap above can't ship half-wired.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | pass | The revision-14 merge preserves every datum the restored decision log needs — outcome, door, reason, pair are all present on the four-field wire; the round-2 finding is structurally still closed. |
| execution | concern | No code exists yet (expected at this stage); the write-side mapping from the TSV's four fields to the log's four fields is not pinned anywhere as an explicit rule, which is exactly the shape of gap this document has shipped incorrect code from five times before. |
| trajectory | concern | ADR 0026's reasoning is sound and its rejected-alternatives table is genuine engineering, but the same "pin the construct, not just the behaviour" sweep that fixed revisions 11–13 was not re-applied to the log-write section this round rewrote around — the sixth instance of a defect class the document's own prose names and warns against two paragraphs above where this instance sits. |
| regression | pass | No code exists; diff since round 6 touches only the spec, the new ADR, and memory/verdict files. |
| context_budget | pass | `docs/features/`, read on demand; file grew 1,721→2,085 lines since round 6 under the already-granted, measurement-backed waiver — legitimate new contract content (the TSV rewrite), not padding. |
| traceability | concern | The `$reason`/`$ts` mapping is reconstructible only by cross-referencing the top flowchart's node `LB` text against §3's field-domain table; the section that claims to be the sole authority for the log line's construction does not state it. |
| success_masking | concern | A uniform `$reason=$f3` implementation bug would pass most `BLOCK`-door log scenarios (which check field 4, not field 3's content) and only fail the one `MSG_NO_MARKER` scenario that happens to assert the constant name explicitly. |
| intent_drift | pass | `git diff --stat 3f068d9..HEAD` touches only the spec, ADR 0026, and prior-round memory/verdict files — no unrelated edits. |
| checkpoint | pass | Four isolated, well-labelled commits on a clean chain; working tree clean; trivially revertible (docs only, no code to leave half-applied). |
| audit_trail | pass | ADR 0026 documents the decision, the rejected alternatives, the amendment, and names its own highest-risk consequence (the opt-in ordering re-verification) as explicitly open until revision 14 — which this round confirms it addressed for ordering, if not fully for the log-write mapping. |

## Concerns

- The TSV-to-decision-log field mapping (`$f1..$f4` → `$verdict`/`$reason`/`$ts`/`$pair`) is not pinned
  as an explicit rule anywhere in §"Decision logging," despite the section's own stated discipline of
  pinning every construct rather than just naming the behaviour; the asymmetric source (field 2 for
  `BLOCK`, field 3 for `EXEMPT`) is only inferable by cross-referencing the top flowchart's node `LB`
  with §3's field-domain table.
- Task 6's current Gherkin coverage would catch a uniform mis-mapping for `MSG_NO_MARKER` (which asserts
  the constant name) but not for the other seven `BLOCK` doors (which assert only field 4).
- The `$ts` field's generating command is unpinned too, though lower risk since `date -u
  +%Y-%m-%dT%H:%M:%SZ` is BSD/GNU-portable, unlike the `echo`/`printf` trap already found in this file.
- This is the sixth instance, by the document's own count of the class, of "a behaviour required without
  pinning the construct that produces it" — found in the same section that was restored specifically
  because round 2 flagged its predecessor's silence.
- Latency budgets remain correctly framed as targets, not measurements (checklist task 10) — not scored
  as a defect.
- Still 0/15 implemented; every finding above is a property of the plan, not of running code.

risk=medium confidence=high
