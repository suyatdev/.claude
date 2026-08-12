# Observability judge — tracking-feature-state — architecting (advisory) — round 8

- **repo:** tracking-feature-state
- **branch:** feat/tracking-feature-state
- **head_sha:** 88d524a08466e77be22613a2d460c8ceadc36364
- **stage:** architecting (ADVISORY — verdict/outcome is `null`; this read does not satisfy `judge-guard.sh`, which requires a fresh *implementation*-stage verdict)
- **ts:** 2026-08-11T22:33:03Z

## What was changed

One commit under review, `88d524a`, docs-only, one file (`docs/features/tracking-feature-state.md`),
one paragraph (the same one rounds 3, 4, 6 and 7 have all touched):

1. Deletes the clause "and zero ticked tasks" from the sentence about the other `planning` cards —
   the two field-scoped `grep -m1` commands cited beside it never counted checklist boxes, so that
   half of the claim had no re-derivable citation. Compliance round 2 (`fail`) cited exactly this.
2. Replaces the two field-scoped greps (`grep -m1 '^phase:' …` and `grep -m1 '^branch:' …`, meant to
   be "read together") with one command, `head -5 docs/features/*.md`.
3. Trims the sentence explaining why the paragraph doesn't restate the card's current phase — the
   narration layer both judges have flagged three times running.

Net: paragraph 9–19 goes from 13 lines to 11; the `.md` half from 220 to 218 lines.

## Does it do what you wanted?

Yes, on all three counts, each re-derived rather than trusted.

**1 — the deleted clause was genuinely unbacked, and the underlying fact survives its deletion.**
I ran `grep -c '^\- \[x\]' docs/features/falsify-harness-signatures.md
docs/features/verification-marker-gate.md` myself: both `0`. So "zero ticked tasks" is still true of
both other `planning` cards — the fix is right to delete the *claim*, not because it was false, but
because nothing in the paragraph could re-derive it. Deleting an unproven-but-true claim rather than
manufacturing a citation for it is the correct instinct: a citation bolted on after the fact to make
a true statement look re-derivable is exactly the "self-fulfilling assertion" this card's own §Audit
log paragraph warns against, applied to a different artifact.

**2 — the grep-ordering hazard is real, not a hypothetical the commit invented to justify a rewrite.**
This is the one claim in this round I could not take on faith even from a verified commit message, so
I tested it directly rather than reasoning about shell glob semantics in the abstract:

```
$ for i in 1 2 3 4 5; do grep -m1 '^branch:' docs/features/*.md | grep -E 'chained-command|falsifier-base-pin'; echo ---; done
docs/features/git-guard-chained-command.md:branch: fix/fix-l1
docs/features/falsifier-base-pin.md:branch: fix/falsifier-base-pin
---
docs/features/falsifier-base-pin.md:branch: fix/falsifier-base-pin
docs/features/git-guard-chained-command.md:branch: fix/fix-l1
---
... (3 of 5 runs: falsifier-base-pin first; 2 of 5: chained-command first)
```

The two files really do swap positions run-to-run on this machine. That means the *old* fix (two
separate `grep -m1` commands, captioned to be "read together") had a live pairing hazard: nothing
guarantees line N of one grep's output corresponds to line N of the other's. `head -5
docs/features/*.md` removes the hazard structurally rather than by convention — each block is printed
under its own filename, so there is no positional pairing to get wrong. I re-ran it: `branch:` sits
within the first five lines of all 16 cards in `docs/features/`, including both other `planning`
cards.

**3 — the narration trim is real, not just a word-count reduction.** I diffed the sentence directly:
the old text explained *why the paragraph doesn't restate the phase* ("because one that names the
current phase goes stale at the very next transition, which is how it has broken before" — pure
paragraph-self-history). The new text states the same operational fact in five words ("restating it
here would only go stale at the next transition") and drops the "which is how it has broken before"
clause entirely. That clause was the specific thing round 7 flagged; it is gone, not rephrased.

## What could go wrong / what I'm unsure about

- **`head -5` is currently correct for a reason the commit doesn't document: it assumes frontmatter
  field order.** Every card's frontmatter today is `phase:`, `model_tier:`, `branch:`, then zero or
  more extra keys — `branch:` is always the third field, so it always lands on line 4, well inside a
  5-line window even for `verification-marker-gate.md`, whose frontmatter is 6 lines long
  (`phase`/`model_tier`/`branch`/`revision`/`waived`/closing `---`) because the extra keys come
  *after* `branch:`, not before it. I confirmed this by reading that file's frontmatter directly. If
  a future card ever inserts a new key *before* `branch:` (say, `owner:` as the second field),
  `head -5` would silently print a truncated block with no `branch:` line and no error — the exact
  failure mode `head -5` was chosen to avoid for the *old* command, recurring in a different shape.
  Nothing in this repo enforces frontmatter field order; it's convention only. This is real but
  narrow — no card violates it today, and the fix is still a strict improvement over the pairing
  hazard it replaced — but it's an unstated assumption, not a proven invariant, so I'd call it
  acceptable-but-worth-a-one-line comment rather than closed.
- **`confirm_timeout` is still unemittable, unchanged from rounds 6 and 7.** This commit touches only
  the `.md` file (`git diff --stat 22cae86..88d524a` confirms one file, `.md`); I re-confirmed the gap
  still holds rather than assuming it: `confirm_surface()` (`server.py:236–253`) still collapses both
  a non-zero `cmux tree` exit and a `subprocess.TimeoutExpired` into the single return value
  `"unrunnable"`, and its only caller (`server.py:574–575`) maps that to `reason="confirm_failed"`
  only. `confirm_timeout` is specified in the `reason` enum (`tracking-feature-state.spec.md:513`) but
  no code path emits it. This next step is still recorded on task 8's *ticked* `.md` line
  (`docs/features/tracking-feature-state.md:69`) rather than as its own unchecked task — still the
  easiest thing for a fast-moving lower-tier builder to skim past, unchanged risk from round 7.
- **`server.py` — the card's own highest-value target, and its entire new trust boundary — still has
  zero automated tests.** Task 9 remains unchecked. Every route, refusal and startup abort is
  "smoke-verified against a cmux shim" per task 8's own note, not pinned as a regression test.
- **The audit log's `sent=unknown` case is still, by the spec's own words, "the worst failure this
  feature has."** I re-read §"What the page does with a failure" (`tracking-feature-state.spec.md:467`):
  "`sent=unknown` must never read as `sent`. A `502` may mean the keystroke landed." This is unchanged
  by this commit (spec half untouched) and is not this round's scope to fix, but it is the single
  highest-consequence gap in the whole design and is still only a documented contract, not a tested
  one — task 9 is the first place any of it becomes checkable by a machine rather than by reading.
- **`.md` is still over its waived ≤200-line cap** — 218 lines, down from 220 but still +18 over. This
  is the first round in a while where the direction is actually toward the cap rather than away from
  it; worth noting as the trend finally reversing, not just another instance of the standing gap.

## What I'd double-check before merging

- That the compliance judge re-runs against this exact `88d524a` blob before any further spec edit —
  its round 2 `fail` was against the parent `22cae86`, and this commit is the direct response to it;
  that closure is self-reported here until compliance confirms it independently.
- That when `gate confirmed` reopens this card, the very first action is still the `server.py` edit
  splitting `confirm_timeout` out of `"unrunnable"`, as its own commit, strictly before any
  `test_server.py` code — not skipped because task 9 reads as the next unchecked box.
- If a card ever adds a frontmatter key ahead of `branch:`, that `head -5` in this paragraph gets
  widened (or replaced) before it silently stops covering that card — nothing will flag the omission
  on its own.

## Dimension table

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Matches the user's stated decision exactly: delete the unbacked half of the claim rather than manufacture a citation for it. Re-derived: the underlying fact (0 ticked tasks on both other planning cards) is still true. |
| execution | concern | Unchanged, carried forward, not this commit's scope: `confirm_timeout` still unemittable in `server.py`; task 9 (the trust boundary's only test) still open; `sent=unknown` — the design's own "worst failure" — remains untested. |
| trajectory | pass | The grep-ordering hazard was independently tested, not just reasoned about, and it held: file order really does vary run-to-run. `head -5` fixes it structurally (self-labeled blocks) rather than by convention. |
| regression | pass | Docs-only, single file; `git diff --stat 22cae86..88d524a` confirms no source touched. |
| context_budget | concern | `.md` 218/≤200 lines (waived cap) — still over, but down from 220; first round this direction has actually reversed rather than grown. |
| traceability | pass | Every claim in the commit message checked out against source, including the least-obvious one (glob ordering instability), which I tested directly rather than accepting on the strength of the message. |
| success_masking | pass | The fix removes a claim that looked re-derivable but wasn't (a citation covering only half of what it was cited for) — un-masking, not masking. |
| intent_drift | pass | Stays within the one paragraph; each of the three changes is disclosed and matches the commit message exactly. |
| checkpoint | pass | Single-file, clean, easily revertible commit. |
| audit_trail | pass | Attributed (Co-Authored-By, session link); commit message explicitly names which judge/round each change closes. Not independently ADR-worthy — it's a citation-hygiene fix, not a design pivot. |

## Concerns

- `confirm_timeout` remains specified in the `reason` enum but unemittable in `server.py`
  (`confirm_surface()` collapses `TimeoutExpired` and a non-zero exit into one `"unrunnable"` state);
  unchanged from rounds 6–7, correctly sequenced as the first action on reopen but not yet landed, and
  still flagged only on an already-ticked task-8 line.
- `server.py` (the card's whole new trust boundary) still has zero automated tests — task 9 open.
- `sent=unknown` is documented as the design's worst failure mode and remains untested pending task 9.
- `head -5` is correct today only because every card's frontmatter puts `branch:` on line 3–4; nothing
  enforces that order, so a future card adding a key ahead of `branch:` would silently fall outside the
  window with no error signal — real but narrow, and still a strict improvement over the pairing
  hazard it replaced.
- `.md` half is still 218/≤200 lines against its waived cap, though this round moved toward the cap
  (220→218) rather than away from it.
- Compliance judge has not yet re-verified `88d524a` itself; that closure is self-reported here.

## Risk / confidence

risk=low confidence=high
