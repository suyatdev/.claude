# Observability verdict — replay harness base pin, revision 6 (architecting, round 4)

- **repo:** `.claude` · **branch:** `main` · **head_sha:** `e6bdc21ee75215476aac7cdd5c7fc747c704b3dd`
- **stage:** architecting (advisory — does not gate the PR)
- **spec:** `docs/features/replay-harness-base-pin.md` revision 6, blob `52c605fe` (matches dispatch)
- **ts:** 2026-08-05T11:59:58Z
- **risk: medium · confidence: high**

> **filename note:** rounds 1–2 live at `2026-08-04-main-replay-harness-base-pin*.md`, round 3 at
> `2026-08-05-…-round3.md`. Kept the spec slug + round suffix so the four reads stay contiguous and a
> second `main` verdict today cannot collide. JSONL `branch` stays the raw `main`.

> **⚠️ Method correction to round 3, and it invalidated two of my own probes today.** Round 3's method
> note said to *quote* refs like `$sha:hooks/…`. **Quoting is not the fix.** zsh applies the `:h`
> (dirname) modifier to `"$var:hooks/…"` *inside double quotes* — it becomes `.ooks/…` and every
> lookup fails. It does **not** happen for a literal (`"HEAD:hooks/…"`, `"e3b09ba:hooks/…"`), which is
> why round 3's spot-checks looked fine. **Braces are the fix: `"${var}:hooks/…"`.** Two enumerations
> today returned all-zero buckets before I caught it; a third bug (`for c in $(…)` does not word-split
> in zsh) also silently reduced a 629-commit scan to one iteration. Every count below was re-run only
> after the probe demonstrated it could both find and fail to find.

---

## What was changed

Still a spec — no code, no branch. `phase: planning`, `branch: none`, no branch cut.

The script under discussion (`hooks/git-guard.replay.sh`) is a **scale for comparing two safety
checks**: old guard on one pan, new guard on the other, 63 commands × 6 repo states = 378 weighings,
and it shouts if the new one lets through something the old one blocked. The defect is that the scale
never writes down *what it weighed* — its baseline is the branch `main`, a label pointing at different
code every week, and it prints nothing about which code that was.

Revision 6 makes three changes, all of them prior findings:

1. **The helper rule is reconciled** (my round-3 finding). `hooks/git-guard.sh` is now mandatory on
   both sides; the two `lib/*.py` helpers are required only when that side's guard actually
   references `lib/`.
2. **The classifier pointer corrected** `:56` → `:74-77`.
3. **Scenario F exempted** from the resolved-SHA clause, since an unresolvable rev has no SHA.

## Does it do what you wanted?

**Yes — and the reconciliation is correct. I could not open the hole the dispatch asked about.**

The specific question was whether a candidate with helpers missing *and* a guard that does reference
`lib/` is still caught. It is, everywhere the rule applies:

- **The control side is fully protected.** The base is *always* a rev (`git show`), never the
  worktree, so it always passes part 2. A base that references `lib/` with a helper missing is caught.
- **A rev candidate is caught** by the same conditional.
- **Scenario E is genuinely unaffected**, as revision 6 claims. Verified: `286fd5a` is missing
  `hooks/git-guard.sh` *itself*, so its named error fires from the mandatory-guard rule, independent
  of the helper change.

**The fix is much larger than the spec claims.** It frames the change as rescuing "one of this spec's
own reference rows". Measured across all 629 commits:

| guard/helper shape | commits |
|---|---|
| refs `lib/` + both helpers present (modern base) | 63 |
| **self-contained (0 `lib/` refs, no helpers) — `e3b09ba` class** | **492** |
| refs `lib/` + a helper MISSING | **0** |
| no `lib/` ref but helpers exist | 0 |
| no guard at all (Scenario E class) | 74 |

Revision 3's all-six rule would have hard-rejected **492 of 629 commits (78%) as baselines**, not one
row. The false-refusal defect was far bigger than acknowledged, and closing it is the round's real win.

**The predicate has no in-repo blind spot.** I tested whether a guard could name a helper without
matching the literal `lib/` (which would silently classify it "self-contained"): **0 of 555** guard
revisions. Verified the probe was not vacuous — it matches 3× at HEAD, 0× at `e3b09ba`.

**Everything else reproduced at HEAD `e6bdc21`:**

| claim | result |
|---|---|
| `grep -cE 'BASE_REV\|getopts\|\$\{3'` → 0 | ✅ 0 |
| lines 6, 7, 13–15, 20–22, 125–131, 134 as cited | ✅ all exact, incl. the 4th hard-coded `main` at `:134` |
| classifier pointers `:44` / `:53-57` / `:74-77` | ✅ exact — `:56` is the python3 guard's `exit 2`, `:77` the classifier's |
| row 1 (vacuous default) | ✅ `378 identical, 0, 0`, **exit 0**, header prints literal `main` |
| Scenario C, mirrored orientation | ✅ `358 identical, 0 stricter, 20 relaxed` — exact mirror of C's `358/20/0` |

**Refusal paths are now properly distinguishable by a caller** — non-zero exit, *plus* no
`DISTINCT COMMANDS` header, *plus* no pair-count line. Two independent signals, not one. That is a
real answer to a question earlier rounds left open.

## What could go wrong / what I'm unsure about

### 1. The rule moved; the acceptance criteria did not. Both wrong implementations pass A–H.

This is the headline. Revision 6 rewrote part 2's helper rule, and **no scenario pins either branch
of it**:

- **`e3b09ba` is not a scenario.** It appears in the measured table (`234/82/62`) and in task 3
  ("Cover `e3b09ba`"), but task 7 verifies **scenarios A–H**, and there is no self-contained-base
  scenario among them. So an implementer who regresses to revision 3's rejected "all six must be
  non-empty" rule **passes all eight scenarios**. The finding this round exists to fix can be
  silently un-adopted and nothing catches it.
- **The catching branch is equally unpinned.** No scenario has guard-present-with-helpers-absent, so
  an implementer who simply **drops helper validation entirely** also passes all eight.

Round 3 asked for a partial-absence scenario "either way". The rule changed; the scenario did not.
And measured above: **0 of 629 commits** have the guard-refs-`lib/`-helper-missing shape, so like
round 3's guard-only falsifier, this one **cannot be borrowed from history — it must be synthesized.**

That makes three wrong implementations now admitted by A–H (the `git show HEAD:` one, the
`shell_segments`-keyed one, and this new pair).

### 2. The worktree gap is no longer inherited — revision 6 makes it gratuitous

This is the one item that became **more** load-bearing, so I am raising it rather than repeating it.

Part 2 explicitly scopes its six calls to "three for the base and three for **a rev candidate**". In
the **default** `UNDER_TEST=worktree` mode there are no extractions for the candidate, and part 4
checks only that `$WT/hooks/git-guard.sh` exists — not its helpers. Measured, on exactly that shape:

```
guard present (refs lib/ 3x), hooks/lib/ empty:
  rc=2  ls -la
  rc=2  git status
  rc=2  git commit -m x
  rc=2  git push --force
  rc=2  echo hi
```

The candidate blocks **everything, including `echo hi`**. Per `:125`, `relaxed` needs `base=2 &&
cand=0`, so with `cand=2` always, `relaxed` is **0 by construction** → exit 0 → a silent false pass
dressed as hardening.

Round 3 flagged this. What is new: **revision 6 removed the excuse.** The old rule was structural
("the extraction must succeed"), which genuinely has no meaning for an on-disk file. The new rule is
**content-derived** — *does this side's guard reference `lib/`?* — and content is equally readable
from disk with the same one-line grep. The predicate revision 6 just invented applies verbatim to the
worktree candidate at zero cost, and the spec does not apply it. The asymmetry is now a choice, not
an inheritance.

### 3. The output's per-side asymmetry widened, in the same revision that improved it

Part 2 now requires that a self-contained side be **recorded in the output**. That clause structurally
cannot apply to a worktree candidate (part 2 does not reach it). So after revision 6 the base side
gets a 40-char SHA *and* a capability annotation, while the candidate side is still the literal string
`worktree` with no annotation. Before revision 6 both sides were equally unannotated. Round 3's
"print candidate identity" recommendation is therefore cheaper to justify now than when it was
queued — the output format is already being extended on one side only.

### 4. The decision record is the one place the spec's own principle is not applied

The spec's governing rule is: *a number that does not carry its baseline cannot be audited later.*
Applied to the harness, rigorously. Not applied to the spec:

- The deferral rationale for **five** judge recommendations across rounds 2–3 (dirty-worktree
  scenario, synthesized guard-only base, ADR provenance-vs-validity sentence, candidate identity, and
  round-2's two) is recorded in **no durable artifact** — grep across `CODING_MEMORY.md` and the spec
  for `dirty.worktree|candidate identity|provenance, not validity|guard-only|synthes` returns **0
  hits**. The revision-6 changelog lists only the three *adopted* items.
- The dispatch tells me these were deliberately put to the user and queued. I believe it. But that
  decision lives only in a conversation, and this is the **second consecutive round** where declined
  recommendations vanish from the record. A future reader cannot distinguish "considered and
  declined" from "missed" — which is precisely the archaeology this spec exists to abolish.
- `CODING_MEMORY.md:854` still pins the spec at **"revision 5"** while it is revision 6.

### 5. Smaller

- **The `lib/` predicate is textual and matches comments.** At HEAD, 3 matches, but only **1**
  (`:44`) is functional — `:21` and `:29` are comments. A future self-contained guard that kept a
  historical comment would be falsely refused. **0 of 555** revisions are affected today, and it errs
  toward refusal (the safe direction), so this is low severity — but it is the same class of error
  revision 6 exists to remove. Keying on a non-comment line closes it.
- **Non-empty ≠ functional.** Part 2's byte-count check would accept a truncated stub guard with no
  `lib/` refs as a valid self-contained base. 0 such revs exist; the ADR's anti-over-claiming clause
  already covers the honesty of it.
- **Exit 0 is now semantically loaded.** Measured: a run reporting **20 relaxations exits 0**,
  identical to a clean run. That is stated in non-goals, honestly. The new risk is second-order: by
  giving refusals a meaningful non-zero exit for the first time, the design invites a caller to treat
  exit 0 as "safe to merge" when it only means "the instrument ran".
- **Does the design's value depend on the three queued tally defects? No.** It closes five named
  routes and the control side outright. The ADR's *claim surface* still does — round 3's §3 point.

## What I'd double-check before merging

1. **Add two scenarios for the rule you just changed** — a self-contained base (`e3b09ba`,
   `234/82/62`) and a synthesized guard-present/helpers-absent candidate. Without them the round-3
   fix is prose only, and its regression passes the suite.
2. **Apply the new `lib/` predicate to the worktree candidate too.** Same grep, same failure
   contract. It is one line, and it closes the only remaining measured silent false pass.
3. **Match the predicate on non-comment lines**, so a comment cannot force a false refusal.
4. **Record the five declined recommendations** — one line each, in the changelog, saying declined and
   why. Same standard the spec sets for the harness.
5. **Refresh `CODING_MEMORY.md:854`** from revision 5 to 6.
6. **Commit the round-3 verdict.** Its markdown is untracked and its JSONL line uncommitted — the
   verdict trail the PR gate reads currently exists only in the working tree.

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | All three revision-6 changes are prior findings correctly implemented. Reconciliation verified sound: control side always a rev so always validated; `286fd5a` confirmed missing the guard itself, so Scenario E fires independently. Classifier pointers `:44`/`:53-57`/`:74-77` exact. |
| execution | concern | Every measured claim reproduced at HEAD (vacuous `378/0/0` exit 0; C mirrored `358/0/20`; base-param grep 0; all 13 line citations). But the artifact that declares this done — scenarios A–H — pins neither branch of the new rule, so both the rejected all-six rule and a no-helper-check rule pass. |
| trajectory | pass | Fourth round of measurement-driven correction. The reconciliation is principled rather than patched: a content-derived predicate, verified to have no in-repo blind spot across 555 guard revisions, and erring toward refusal. |
| regression | pass | Upgraded from round 3. The false refusal is closed, and measured far larger than claimed: 492 of 629 commits are the self-contained class, not one row. No new hole — 0 of 629 commits have the shape that would exploit the conditional. Blast radius still tiny: manual harness, not in `settings.json`, `git-guard.sh` untouched. |
| context_budget | pass | One script, one ADR, four provenance notes. No always-on rule/skill/prompt surface. |
| traceability | concern | Base side excellent (40-char SHA, anti-gaming clause, testable on the default run). But part 2's new "record as self-contained in the output" clause cannot reach a worktree candidate, so revision 6 *widened* the per-side output asymmetry in the same stroke that improved it; candidate identity remains the literal `worktree`. |
| success_masking | concern | Measured: guard-present + helpers-missing candidate exits 2 on every command incl. `echo hi` → `relaxed` 0 by construction → exit 0, and part 5 will now print a valid base SHA beside it. Caught for the base and for a rev candidate; **not** in the default worktree mode, which revision 6 makes gratuitous rather than inherited. Three wrong implementations now pass A–H. |
| intent_drift | pass | Revision 6 changed only what was asked. Tight non-goals, three queued tally defects recorded in `CODING_MEMORY.md`, user's queueing decision honored, no new dependencies. |
| checkpoint | pass | `phase: planning`, `branch: none`, no branch cut, no gate transition taken, no source touched. Working tree holds only judge artifacts. Task 1 remains a red-reproduce step that forbids deleting the probe. |
| audit_trail | concern | Downgraded from round 3, on a compounding pattern rather than a one-off: declined recommendations from two consecutive rounds are recorded nowhere (0 grep hits), the revision-6 changelog lists only adopted items, and `CODING_MEMORY.md` is stale at "revision 5". The citation table and ADR-immutability handling remain exemplary. |

## Concerns

- Scenarios A–H pin neither branch of revision 6's conditional helper rule; both "always require all six" (the rejected rule) and "never check helpers" pass all eight, so the round-3 fix could be silently un-adopted
- `e3b09ba` is a measured row and a task instruction but not a scenario, and task 7 verifies scenarios
- The catching branch has no in-repo falsifier: 0 of 629 commits have guard-refs-`lib/` with a helper missing, so a partial-absence scenario must be synthesized, not borrowed
- Default worktree mode still has no candidate-side helper check; revision 6 makes this gratuitous, since its new predicate is content-derived and equally readable from disk
- Measured: guard-present + helpers-missing candidate exits 2 on every command incl. `echo hi` → 0 relaxed by construction, exit 0, and part 5 will decorate it with a valid 40-char base SHA
- Part 2's "record as a self-contained guard in the output" clause cannot apply to a worktree candidate, widening the per-side output asymmetry revision 6 otherwise improved
- Deferral rationale for five judge recommendations across rounds 2–3 recorded in no durable artifact (0 grep hits); the revision-6 changelog lists only adopted items
- `CODING_MEMORY.md:854` still pins the spec at "revision 5" while it is revision 6
- The `lib/` predicate is textual and matches comments (2 of 3 matches at HEAD are comments); 0 of 555 revisions affected today, but it errs toward the false refusal revision 6 exists to remove
- Measured: a run reporting 20 relaxations exits 0, identical to a clean run; the new refusal contract makes exit 0 newly semantically loaded and invites a caller to read it as "safe to merge"
- Round-3's verdict markdown is untracked and its JSONL line uncommitted — the verdict trail the PR gate reads is currently only in the working tree
- Method: zsh applies the `:h` modifier to `"$var:path"` even inside double quotes; quoting is not the fix, braces are — this silently blinded two probes this round and one last round
