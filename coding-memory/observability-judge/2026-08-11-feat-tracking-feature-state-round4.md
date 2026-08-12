# Observability verdict — `feat/tracking-feature-state` (architecting, advisory) — round 4

- **Repo:** `tracking-feature-state` (worktree of `~/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `b2ed7bbd0a1e425624cd901920b81fa709d1ff2f`
- **Base:** `main`
- **Stage:** `architecting` — **advisory, `outcome: null` always; does not gate a PR on its own.**
  Only a fresh *implementation*-stage verdict satisfies `hooks/judge-guard.sh`, and none has run for
  this branch.
- **Prior read judged:** `bd73da6` (round 3, 2026-08-11T19:56:04Z). This round covers the one commit
  since: `b2ed7bb` — "close round 2's stale claim, and name the derivation's second blind spot."

## What was changed

One docs-only commit (`git diff --stat bd73da6..b2ed7bb`: only `docs/features/tracking-feature-state.spec.md`
touched among tracked source/docs, +25/-20; the `.md` half and `task-tracker/*` did not move). Two edits:

1. **Closed compliance round 2's violation.** Task 4's `§Tasks` detail had gone on describing
   criterion 1's converse-selector work as unfinished ("these two assertions are the whole of what
   is missing") for six commits after `3d5a2ff` actually landed it — while the `.md` half's terse
   entry already read it as closed, and the paragraph's own cited `grep` had by then flipped to
   proving the opposite of what it was quoted for. Rewritten to past tense against the landed test.
2. **Named the reason-coverage derivation's second blind spot**, the one this judge's round 3 read
   surfaced: the two-shape `grep` is line-oriented, so an emitting call whose status and `reason`
   land on different source lines is invisible to it, on top of the already-named risk of a third
   emitting shape appearing later.

## Does it do what I wanted?

Yes on both counts, and every citation was re-run against source rather than trusted:

- **Task 4's rewritten entry, verified word-for-word against the landed test.** All four `grep`s it
  cites resolve exactly where claimed: `if phase is not None` at `test_analyze.py:104` (the
  fixture's `card()` helper, matching the new "`phase=None` omits the key" claim);
  `frontmatter.get("phase"` at `analyze.py:266`; `No closing\|not in PHASE_MAP` at `analyze.py:528,530`;
  `a_card_without_a_phase_key` naming `test_criterion_1_a_card_without_a_phase_key_is_still_a_card`
  at `test_analyze.py:181`. I read the test itself (`test_analyze.py:181-206`): it asserts
  `"alpha" in {f["name"] for f in run["features"]}`, then `"What phase is \`alpha\` in?" in asked`
  **and** `"Does \`alpha\` have valid frontmatter?" not in asked` — exactly the two-branch assertion
  the entry describes, and both question strings match `analyze.py:527` and `:532` verbatim. Ran
  `task-tracker/test_analyze.py` directly: **24 passed**, including this test. The entry's claim is
  accurate, not just plausible.
- **The derivation's new two-blind-spot warning, checked against current `server.py`.** Re-ran the
  two-shape command myself: **15** distinct `(status, reason)` pairs, `403` → five, `502` → two
  (`confirm_failed` at `server.py:575` via `_fail()`, `send_failed` at `server.py:582` via a bare
  `audit()` call) — exact match to the commit's re-derived numbers. I checked for a live "wrapped
  call" today (`grep -n '_fail($\|audit($' server.py` → no hits) — the blind spot is correctly framed
  as latent, not live, consistent with what round 3 already established. I also checked for a live
  third emitting shape by reading every `reason=` site in `server.py`: the only two that produce a
  non-`"-"` reason are the `_fail()` literal call sites and the one bare `audit()` call at line 582,
  both already counted — so "a third emitting shape" is also correctly framed as hypothetical, not
  a defect being hidden today.
- **`confirm_timeout` gap still open, and still correctly recorded as such.** `confirm_surface()`
  (`server.py:236-252`) still collapses `TimeoutExpired` and a non-zero exit into one `"unrunnable"`
  string; task 8's `.md` entry still carries its `⚠️ Ticked but owes one edit` marker unchanged. This
  commit didn't touch it — it wasn't in scope — but nothing here masks it either.
- Acceptance-criteria count re-run: `awk` over `## Acceptance criteria` → **15**. Task-number sync
  (`hooks/lib/feature_tasks.py docs/features/tracking-feature-state.md docs/features/tracking-feature-state.spec.md tracking-feature-state`) → exit 0. `git status --short` → clean.

## What could go wrong / what I'm unsure about

1. **The task-4 meta-commentary bullet is where I'd draw the "narration vs. instruction" line, per
   this round's own question.** The new text is two bullets: the rewritten fix summary (accurate,
   useful, keep it) and a five-line `⚠️` bullet re-narrating that the stale claim survived six
   commits and which `grep` had flipped. Its only forward-looking clause is one sentence: "the two
   halves are one document — when they disagree, re-derive from source rather than believing either
   one's prose." Everything before that sentence is history that already lives in the commit message
   (`b2ed7bb`), in `CODING_MEMORY.md`, and in this judge's own round-3 verdict — three other places
   the same fact is now recorded. That's the repo's own "delete the duplicate, don't sync it"
   pattern, applied to itself: a fact that lives in N places should have one authoritative home, and
   git history (not a spec paragraph) is supposed to be that home for implementation narrative. I
   would not block on this — the actionable sentence is real and generalizes usefully — but if this
   pattern repeats a third time (a bullet re-narrating why a previous bullet was wrong), it has
   crossed from instruction into self-narration and should be cut to the one-sentence rule.
2. **Both size waivers remain live.** `.spec.md` = 1535 lines (waived `≤800`), `.md` = 216 (waived
   `≤200`, unchanged, not touched this commit). Growth this round is small — `.spec.md` +5 net lines
   (1530→1535) — well inside the "handful of lines" tolerance the waiver itself sets, so this is not
   a fresh violation. But the file is now essentially **2× its waived cap**, and part of what keeps
   pushing it there is exactly the narration pattern in concern 1 — worth naming even though this
   round's increment is small.
3. **The compliance judge has not yet re-verified `b2ed7bb` itself.** `d366c63` recorded compliance
   round 3 as PASS and "the cap," but that verdict is pinned to `bd73da6`'s blob, not this commit's.
   Not a defect in what shipped — the fix is exactly what round 2 asked for — but the loop this
   commit closes is still self-reported until compliance re-runs against the new SHA.
4. Task 13's criterion-15 reporting plan (flagged round 3, unchanged) still has no computational
   floor forcing the "not verified" distinction on a node-less host — carried forward, not
   reintroduced or worsened by this commit.

## What I'd double-check before merging (or before the next round)

- If another round adds a bullet re-narrating why a *previous* narration bullet was stale, stop and
  compress: keep the one-sentence rule, cut the blow-by-blow, and point at the commit SHA that
  already carries the history.
- Run the compliance judge against `b2ed7bb` before treating round 2's violation as closed by
  anything other than self-report.
- Nothing here blocks continuing — advisory read, net improvement, no new defect found in either
  edit.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Fixed exactly the compliance violation and the prior observability finding, nothing else |
| execution | pass | Docs-only (no `task-tracker/*` line moved); every re-derivable claim checked against source and matched, including running the actual test (24 passed) |
| trajectory | pass | Rewrote to past tense against the landed test rather than patching the stale prose; every citation re-run before being written down, per the commit's own claim, which I verified rather than trusted |
| regression | pass | No source touched; confirmed via diff scope and a clean `git status` |
| context_budget | concern | `.spec.md` now ~2× its waived `≤800` cap (1535 lines); this round's growth is small (+5) and within tolerance, but part of the file's growth pressure is the self-narrating bullets flagged under intent_drift-adjacent concern 1 below |
| traceability | pass | Every claim carries a re-derivation command; all four re-run this round resolved exactly where cited |
| success_masking | pass | The derivation's own blind spots (third shape, wrapped call) are now named explicitly rather than hidden; the still-open `confirm_timeout` gap and task-13 floor are correctly left recorded as open, not glossed |
| intent_drift | concern | In scope, but the added meta-commentary bullet is now the second layer of "here's what we got wrong last time" narrative on this same task entry, most of it duplicating the commit message and CODING_MEMORY.md rather than adding new instruction — see concern 1 |
| checkpoint | pass | Single coherent, `Doc-Exempt`-tagged commit; clean revert point; working tree clean |
| audit_trail | pass | Commit message attributes reasoning to the exact prior verdict and finding it responds to; no fresh structural decision needing its own ADR |

**Risk: low. Confidence: high** — every number, line citation, and test claim in this commit was
independently re-derived from source this round, including actually running `test_analyze.py`
(24 passed) rather than trusting the commit's word for it.

## Concerns

- Task 4's new `⚠️` bullet is mostly historical narration (six commits, which `grep` flipped) with
  one generalizable instruction buried in it; that fact already lives in the commit message and
  `CODING_MEMORY.md`. Not disqualifying now; would be if a third layer of "why the last bullet was
  wrong" gets added on top.
- `.spec.md` is now ~2× its waived `≤800` cap (1535 lines); this round's increment is small (+5) and
  inside tolerance, but the trend is real and part of its driver is exactly the narration above.
- Compliance judge has not yet re-verified `b2ed7bb`; round 3's PASS is pinned to the prior SHA
  (`bd73da6`).
- `confirm_timeout` code gap and task 13's criterion-15 computational floor remain open, unchanged
  from round 3 — correctly still recorded, not this commit's scope to fix.
