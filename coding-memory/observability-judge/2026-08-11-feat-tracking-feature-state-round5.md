# Observability verdict — `feat/tracking-feature-state` (architecting, advisory) — round 5

- **Repo:** `tracking-feature-state` (worktree of `~/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `224174247735630246d0a71d348217fcad533240`
- **Base:** `main`
- **Stage:** `architecting` — **advisory, `verdict: null` always; blocks nothing.** Only a fresh
  *implementation*-stage verdict satisfies `hooks/judge-guard.sh`, and none has run for this branch.
- **Prior read judged:** round 4 (`b2ed7bb`, `coding-memory/observability-judge/2026-08-11-feat-tracking-feature-state-round4.md`).
  Two commits since: `c4c3349` (touches the spec pair) and `2241742` (memory archive, out of scope).

## What was changed

One docs-only commit, one line of edit inside one bullet: `c4c3349` swaps a bare, uncounted number
("six commits") for two commit SHAs plus the shell command that is supposed to reproduce the gap
between them (`git diff --stat`: `docs/features/tracking-feature-state.spec.md` only, +7/-5, one
hunk). This is a fix-of-a-fix: round 2's compliance FAIL caught task 4's stale prose; the commit that
fixed it (`b2ed7bb`) introduced "for six commits after it landed" without counting it; round 3
PASSED that commit; this round's predecessor (round 4, reviewing `b2ed7bb`) flagged the paragraph's
growing self-narration but did not catch the fabricated number itself; `c4c3349` is the correction.

## Does it do what you wanted?

**Mostly — but I ran the command it embeds, and re-derived the number the commit's own message
argues from, and neither survives full re-derivation cleanly.**

**1. The core claim ("no reading of the log yields six") is itself wrong.** I re-ran every variant:

| Scope | Range | Result |
|---|---|---|
| Bare, whole repo | `3d5a2ff..b2ed7bb` | 18 |
| Bare, minus catching commit | `3d5a2ff..b2ed7bb^` | 17 |
| "The spec pair" (both files) | `3d5a2ff..b2ed7bb` | 11 |
| "The spec pair", minus catching commit | `3d5a2ff..b2ed7bb^` | 10 |
| **`.spec.md` only — the command actually shipped** | `3d5a2ff..b2ed7bb -- …spec.md` | **8** |
| `.spec.md` only, minus `b2ed7bb` | `3d5a2ff..b2ed7bb^ -- …spec.md` | 7 |
| **`.spec.md` only, ending at `bd73da6`** (the commit compliance round 2 actually judged) | `3d5a2ff..bd73da6 -- …spec.md` | 7, **including `bd73da6`** |
| Same, excluding `bd73da6` itself | `3d5a2ff..bd73da6^ -- …spec.md` | **6** |

That last row is an exact match for "six," and it is not a contrived reading: `bd73da6` is the
literal commit compliance round 2 evaluated and rejected for this exact staleness — "the commit that
caught it stale" is a more natural referent for `bd73da6` than for `b2ed7bb` (which *fixed* the
staleness, in the same edit that happened to introduce the wrong count). The round-3 compliance
verdict's own notes computed this same range and got "seven including `bd73da6`" without taking the
last step (`coding-memory/compliance-judge/2026-08-09-tracking-feature-state.md:1947-1953`) — one
subtraction away from the number `c4c3349`'s commit message says no reading produces.

This does not make the old text *right* — "six" was still asserted without being counted, which is
the actual defect, and a number that only holds under one specific, contestable choice of endpoint is
exactly the "boundary-sensitive" fragility this card's own standing rule warns against (the round-3
verdict said as much and still passed it). Deleting the bare number was the correct call regardless of
which reading is "right." But the commit fixing a fabricated-number defect should not itself assert a
falsifiable universal ("no reading … yields six") that a five-minute re-derivation contradicts — that
is the same species of unverified claim this whole passage exists to prevent, one level up.

**2. The embedded command measures a narrower thing than the commit message's own working.** The
commit message investigates "the spec pair" (both `.md` and `.spec.md`, giving 11) as one of four
candidate readings before settling on "no reading gives six." The command actually written into the
document scopes to `.spec.md` alone (giving 8) — a tighter, arguably more defensible scope (the
entry lives only in `.spec.md`), but it is not the scope the commit message reasoned about, and a
reader who runs it will get a number (8) that matches none of the four the commit message cites.
Nothing false is stated in the shipped text (it names two SHAs and a command, no number), so this is
an internal-consistency gap between the commit's rationale and its artifact, not a defect in what
ships.

**3. "No new explanatory layer" — checked against the diff, and it holds on its literal terms.** This
is an in-place edit of the existing `⚠️` bullet (7 insertions, 5 deletions, one hunk) — not a new
bullet stacked below it, which is the shape round 4 warned about. But this is the bullet's third
distinct revision in three commits (round-11 fix → `b2ed7bb`'s "six commits" narration → this
commit's SHA-and-command version), each one correcting a defect the previous revision introduced, and
this revision's own commit message contains a fresh miscount (item 1 above). The pattern round 4
flagged — "if this repeats a third time … it has crossed from instruction into self-narration" — has
in substance repeated, even though structurally no *new* bullet was stacked on top. My recommendation:
now that task 4 is stably closed and independently tested (`test_analyze.py`, 4 grep citations all
verified again this round), stop patching this paragraph and let it read as history. A fourth revision
here would not be a coincidence.

**4. The `confirm_timeout` gap (this round's assigned focus) is correctly and consistently recorded,
with no other contract-table gap of the same shape found.** Re-verified against source, not prose:

```
grep -c 'confirm_timeout' task-tracker/server.py   -> 0   (still unemittable)
{ grep -oE '_fail\([0-9]+, "[a-z_]+", "[a-z_]+"' server.py | sed …
  grep -oE 'audit\("[a-z]+", [0-9]+, reason="[a-z_]+"' server.py | sed … ; } | sort -u | wc -l
                                                     -> 15  (matches the doc's own claim exactly)
403 -> 5 distinct reasons, 502 -> 2 distinct reasons (both re-derived, both match)
```

Every citing location agrees: the wire contract (`:428`), the reason enum (`:513-514`), the security
outcome table (`:830`), task 8's note (`:1253-1257`, its one open edit), and task 9's blocking note
(`:1373-1387`, which correctly keeps task 9 unticked on it). The user's 2026-08-11 decision — split
`confirm_surface()`'s `TimeoutExpired` case before writing the test, code changes not the spec — is
recorded once, referenced everywhere else. `test_server.py` does not exist yet (`ls` confirms), so
nothing claims test coverage it doesn't have. I did not find a second contract row in the same
unreachable-but-specified shape; every other status/reason pair in the enum has a live emission site.

## What could go wrong / what I'm unsure about

1. **The commit message's central factual claim is false under a reading its own compliance history
   already computed most of the way to.** See table above. Low consequence (the shipped text states
   no number), but it repeats the exact failure mode — an assertion of certainty ("no reading … yields
   six") that a direct re-derivation contradicts — one commit after fixing the same failure mode.
2. **The shipped command's scope (`.spec.md` only) is not the scope the commit message reasoned with
   ("the spec pair," both files).** Not a defect in the document, but a loose end in the audit trail:
   the commit's own investigation and its own artifact don't agree on what "the gap" is scoped to.
3. **This paragraph is on its third revision in three commits and just produced a fresh, if minor,
   inaccuracy in the commit fixing the previous one.** Structurally not a new stacked layer (round 4's
   specific trigger), but in substance the same fatigue pattern. Recommend leaving it alone now.
4. **Standing, unchanged from every recent round:** `.spec.md` is 1537 lines against the `≤800` target
   waived at 1278 (`2c66fab`, 2026-08-10) — now +259 lines / +20% past the accepted figure, with no
   fresh re-confirmation on record since `686057d`'s check-in at 1493.
5. **`server.py` still has zero automated coverage** (task 9 open); this round did not re-check that
   finding in depth since round 4/the last full pass already covers it and nothing here changed it.

## What I'd double-check before merging (or before the next round)

- Before citing "six commits" as definitively unfounded anywhere else (a future verdict, an ADR), use
  the table above rather than the commit message's own "no reading yields six" — that line is not
  accurate as written.
- Leave task 4's `⚠️` bullet alone. It has been rewritten three times fixing its own prior rewrite;
  the actionable content (re-derive when the halves disagree) is already there and any further edit is
  more likely to introduce a fourth small error than to remove the last one.
- Re-confirm the `.spec.md` size waiver against the current 1537 (last confirmed at 1493), the same
  ask carried forward from prior rounds and still open.
- This read is advisory and gates nothing; a fresh implementation-stage verdict is still required
  before `gh pr create`, and none exists for this branch.

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | pass | The commit's stated goal — stop asserting an uncounted number — was substantively achieved; the bare "six" is gone from the document |
| `execution` | concern | Docs-only, clean diff; but the shipped command scopes to `.spec.md` only (8), not "the spec pair" (11) the commit message reasons about — an unreconciled gap between rationale and artifact |
| `trajectory` | concern | Sound general direction (delete a fragile number rather than re-pin it), but the commit's own supporting claim ("no reading yields six") is itself false under a reading the compliance history already came within one subtraction of — the third revision of this exact paragraph, this time miscounting in the fix rather than the original text |
| `regression` | pass | `git show --stat` confirms exactly one file touched (`.spec.md`); no source, no other doc moved |
| `context_budget` | concern | `.spec.md` now 1537 lines vs the `≤800` target waived at 1278 (+259/+20% past the accepted figure, last re-confirmed at 1493) — standing, not new this round |
| `traceability` | concern | Every code-facing claim I re-ran (reason coverage 15 pairs, 403→5, 502→2, `confirm_timeout` unemittable, sync check, acceptance-criteria count 15, `server.py` 694 lines) matched exactly — but the commit's own historical claim about "six" does not survive re-derivation |
| `success_masking` | pass | Nothing here optimizes a green result; the change is honest about not knowing an exact count, even where its own replacement reasoning overclaims |
| `intent_drift` | pass | Single bullet, single file, no drive-by; diff scope matches the commit's stated purpose exactly |
| `checkpoint` | pass | One atomic, `Doc-Exempt`-tagged commit; clean working tree at HEAD; trivial, clean revert point |
| `audit_trail` | concern | Same finding as traceability, stated at the commit-message level: the investigatory numbers cited (18/17/11/10) don't include the scope actually shipped (8), and the message's blanket refutation of "six" is contradicted by a re-derivable, textually plausible reading (6) that this round found in about two minutes |

**Risk: low. Confidence: high** — every number in this verdict was independently re-run against
source or git history in this session, including the reading that reproduces "six" exactly, the
`confirm_timeout` unemittable-state check against current `server.py`, the 15-pair reason-coverage
re-derivation, and the diff scope of both commits since the last read. Risk stays low because nothing
shipped states a false claim (the fabricated number is gone, not replaced by a different wrong one)
and no source code changed; the concerns are about the audit trail's internal consistency, not about
anything a user of the feature would ever see.

## Concerns

1. `c4c3349`'s commit message asserts "no reading of the log yields six" — false. `git rev-list --count 3d5a2ff..bd73da6^ -- docs/features/tracking-feature-state.spec.md` yields exactly 6, using `bd73da6` (the commit compliance round 2 actually judged and rejected) as the "catching" endpoint rather than `b2ed7bb` (the commit that fixed it). The round-3 compliance verdict's own notes computed the same range and stopped one subtraction short of finding this.
2. The command embedded in the shipped spec text scopes to `.spec.md` only (giving 8), which does not match "the spec pair" framing (giving 11) the commit message uses in its own investigation — an unreconciled gap between the commit's rationale and its artifact, though nothing false is stated in the document itself.
3. Task 4's `⚠️` bullet is now on its third revision across three commits, each fixing a defect the previous revision introduced (including a fresh one in this round's own commit message); recommend leaving it alone rather than revising again.
4. `.spec.md` is 1537 lines against the `≤800` target waived at 1278 (2026-08-10, `2c66fab`) — now +259/+20% past the accepted figure, last re-confirmed at 1493 (`686057d`); no fresh acknowledgment on record at the current size.
5. `server.py` (694 lines, the card's own "highest-value target") still has no automated test — task 9 remains open; unchanged from prior rounds, not reintroduced or worsened here.
