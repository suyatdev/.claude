# Observability judge — tracking-feature-state — architecting (advisory) — round 7

- **repo:** tracking-feature-state
- **branch:** feat/tracking-feature-state
- **head_sha:** 22cae86e149c81cee71df338e828617a3cead159
- **stage:** architecting (ADVISORY — verdict/outcome is `null`; this read does not satisfy `judge-guard.sh`, which requires a fresh *implementation*-stage verdict)
- **ts:** 2026-08-11T22:10:22Z

## What was changed

One commit under review, `22cae86`, docs-only, one file (`docs/features/tracking-feature-state.md`), one paragraph plus the frontmatter:

1. Frontmatter flips back `phase: implementation → planning`, `model_tier: low → high`, because compliance round 1 (re-entry) found the preamble's evidence broken and the fix is a spec edit, which `implementation` forbids.
2. The preamble paragraph is rewritten to fix two defects: a citation that verified nothing, and wording that would have gone false the moment the frontmatter changed (again).

(`92c450f`, the commit immediately before it, only records judge memory — the round-1 FAIL and my prior round-6 read. It touches none of the reviewed artifact.)

## Does it do what you wanted?

Yes, on both counts I re-derived rather than trusted.

**Defect 1 — the broken citation.** The old paragraph cited one command, `grep -m1 '^phase:\|^branch:' docs/features/*.md`, as proof "every other `planning` card carries `branch: none`." I ran it: `-m1` stops at the first match per file, and `phase:` sorts above `branch:` in every card's frontmatter, so that command can only ever return `phase:` lines — it structurally cannot reach a `branch:` value. The claim was true; the citation proved nothing, and had proved nothing through a prior PASS.

The fix replaces it with two field-scoped commands. I ran both against the live repo:

```
$ grep -m1 '^phase:' docs/features/*.md | grep planning
docs/features/falsify-harness-signatures.md:phase: planning
docs/features/tracking-feature-state.md:phase: planning
docs/features/verification-marker-gate.md:phase: planning
$ grep -m1 '^branch:' docs/features/*.md
docs/features/falsify-harness-signatures.md:branch: none
...
docs/features/verification-marker-gate.md:branch: none
$ grep -c '^\- \[x\]' docs/features/falsify-harness-signatures.md docs/features/verification-marker-gate.md
docs/features/falsify-harness-signatures.md:0
docs/features/verification-marker-gate.md:0
```

The claim — "every *other* `planning` card carries `branch: none` and zero ticked tasks" — is true and now actually re-derivable from the cited commands, which is the whole point of a citation. I also confirmed the commit message's stated reason for keeping `-m1` at all: dropping it makes the `branch:` pattern also match `falsifier-base-pin.md:144`, a body line beginning `branch:` — verified, that line exists and reads as claimed.

**Defect 2 — the self-invalidating wording.** The old paragraph narrated the card's *current* phase ("reopened to `implementation` on 2026-08-11"), so it went stale at every transition — it had just been rewritten for exactly that reason one commit earlier, and this return to `planning` would have falsified it again. I read the new paragraph clause by clause: it now describes the *convention* only ("when a mid-implementation spec revision is needed the card returns to `phase: planning`...") and explicitly defers to the frontmatter ("**Read `phase:` above for where the card is now** — this paragraph deliberately does not restate it"). No clause in the new text asserts a specific current phase. This closes the defect class, not just this instance.

## What could go wrong / what I'm unsure about

- **The paragraph grew, and the growth is only partly earned.** I measured both versions directly rather than trusting the prompt's count (which said 12 vs 9): `sed -n '9,21p'` on the new file gives **13** lines; the old paragraph at the parent commit is **9**. Two lines of that growth are the necessary cost of replacing one broken citation with two correct ones — earned. But the new text also adds a clause explaining *why* it doesn't restate the current phase ("...because one that names the current phase goes stale at the very next transition, which is how it has broken before") — this is narration about the paragraph's own defect history, the exact accretion pattern this paragraph has been flagged for twice before (rounds 3 and 4). The commit does show real pruning discipline elsewhere — it dropped a redundant `phase-guard.sh` sentence for this same reason, which is a genuine improvement — but then added a smaller instance of the same pattern back. Net: `docs/features/tracking-feature-state.md` is now **220 lines**, up from 216, further past its already-waived ≤200 cap.
- **`confirm_timeout` is still unemittable, unchanged from round 6.** `server.py` was not touched by this commit (confirmed: `git diff --stat 15cc372..22cae86` touches only the one `.md` file), so I did not need to re-derive this from scratch, only re-confirm it still holds. It does: `confirm_surface()` (`server.py:236-253`) still returns the single state `"unrunnable"` for both a non-zero `cmux tree` exit and a `TimeoutExpired`, and the only caller maps that state to `reason="confirm_failed"` (`server.py:575`). I re-ran the two-shape reason-coverage derivation the spec itself prescribes and got **15** distinct `(status, reason)` pairs — `confirm_timeout` is not among them, matching the spec's own claim and my round-6 finding exactly. The spec now documents this gap and its required fix in three places (task 8's `.md` line, task 8's §Tasks detail, task 9's §Tasks "Blocking prerequisite"), all mutually consistent and all still accurate. I found no second, undisclosed instance of a specified-but-unemittable status anywhere else in the contract.
- **The next actionable step lives on a *ticked* checklist item.** Task 8 (`.md` line 71) is `[x]` but carries the warning that it "owes one edit" before task 9 can proceed. A reader skimming the terse `.md` for "what's next" conventionally skips over checked boxes; the warning icon mitigates this but doesn't eliminate the risk that a fast-moving lower-tier builder opens task 9 first. This is unchanged from round 6's finding, not new, and the sequencing itself (code fix as its own commit, strictly before task 9's test) is unambiguous once read.
- **Both size waivers remain live and, this round, one of them grew.** `.md` 220/≤200 (was 216; +4, all from this commit), `.spec.md` 1537/≤800 (untouched this commit). Disclosed, previously re-confirmed, but the `.md` growth direction is the wrong one given the standing feedback to compress this exact paragraph.

## What I'd double-check before merging

- That the pruning instinct shown here (dropping the `phase-guard.sh` sentence) gets applied to the new "which is how it has broken before" clause the next time this paragraph is touched — it explains the paragraph's own history rather than telling a reader what to do, and this card has repeatedly been warned about exactly that shape.
- That when `gate confirmed` reopens this card, the very first action is the `server.py` edit splitting `confirm_timeout` out of `"unrunnable"` — as its own commit, strictly before any `test_server.py` code — not folded together, and not skipped because task 9 is the checklist's next unchecked box.
- Whether the compliance judge has been re-run against this exact `22cae86` blob pair before any further spec edit — its round-1 (re-entry) FAIL was against the pre-fix text; I did not re-run compliance myself, only independently confirmed the specific citation defect it found is closed.

## Dimension table

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Both stated defects (broken citation, self-invalidating wording) are genuinely closed; re-derived both independently. |
| execution | concern | Unchanged, real, correctly-sequenced: `confirm_timeout` still unemittable in `server.py`, task 9 (the trust boundary's only test) still open. Not new to this commit. |
| trajectory | pass | Root-caused the sort-order bug precisely rather than patching around it; reasoning in the commit message matches what I independently re-derived. |
| regression | pass | Docs-only; `git diff --stat` confirms no source file touched. |
| context_budget | concern | `.md` grew 216→220 lines against an already-waived ≤200 cap; the growth is partly a new narration clause of the exact kind flagged twice before, though the same commit also pruned a different redundant sentence. |
| traceability | pass | Commit message states both defects, the fix, and the reasoning; every claim in it checked out against source. |
| success_masking | pass | The fix un-masks a vacuous self-check (a citation that always "passed" without proving anything) rather than adding a new one. |
| intent_drift | pass | Change stays within the one paragraph and frontmatter it says it touches; the dropped sentence is disclosed and reasoned, not a silent drive-by. |
| checkpoint | pass | Single-file, clean, easily revertible commit. |
| audit_trail | pass | Attributed (Co-Authored-By, session link); not obviously ADR-worthy on its own, but a third recurrence of the same accretion pattern in this paragraph would be. |

## Concerns

- `.md` preamble paragraph grew 9→13 lines; part of the growth is a new self-referential "why this doesn't restate itself" clause, the same accretion shape flagged in rounds 3 and 4, even though this commit also pruned a different sentence for that reason.
- `docs/features/tracking-feature-state.md` is now 220 lines against its waived ≤200 cap (was 216), moving further past it, not toward it.
- `confirm_timeout` remains specified but unemittable in `server.py` (unchanged from round 6); correctly sequenced as the first action on reopen, but not yet landed.
- The actionable next step is flagged on an already-ticked task-8 line, which a reader scanning only unchecked boxes could skip past.

## Risk / confidence

risk=low confidence=high
