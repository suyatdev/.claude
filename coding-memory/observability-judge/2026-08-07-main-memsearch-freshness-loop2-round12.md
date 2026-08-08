# Observability judge — memsearch-freshness, round 12 (architecting)

- **repo:** `.claude`
- **branch:** `main` (slug `main`)
- **head_sha:** `937a919713fab84ae53d296a43946b144cf24799`
- **spec:** `docs/features/memsearch-freshness.md` @ blob `c148cda8875e9610674ce4f66decc0a21bd9ee92` — **verified, matches the invocation**
- **stage:** architecting · **round:** 12 · **ts:** 2026-08-07T20:02:08Z
- **file naming:** the per-round suffix follows the convention already established by rounds 1–11 in
  this directory. The bare `<date>-<branch_slug>.md` form would have collided rounds 10, 11 and 12
  onto one path and destroyed two prior verdicts.

## What was changed

The spec had a rule meant to stop someone from cheating a measurement, and the rule had a soft spot.

R9 measures whether stuffing the big `CODING_MEMORY.md` archive into the search index makes search
*worse*. Five test queries, each aimed at one feature's docs. The obvious cheat is to aim all five at
the biggest, easiest-to-find features — you'd pass while measuring nothing. So the spec added a
spread rule: at least one query must aim at a **small** feature, at least one at a **big** one.

"Small" meant "bottom third". Round 11 pinned *which group* you measure thirds against. It never said
what "third" **means**. Two readings existed:

- **Value span** — take the smallest and biggest, split that distance in three.
- **Rank tertile** — line all the features up smallest-to-biggest and take the bottom slice of the line.

Round 12 picks rank tertile and says so in all four places the rule appears. One commit,
25 lines added, 6 removed, nothing else touched.

## Does it do what you wanted?

**Yes — and I checked rather than took its word for it.**

I measured the real per-feature chunk counts from the source files, using the project's own chunker
(`split_markdown`, `MIN_SECTION_CHARS=200`, `MAX_SECTION_CHARS=2000`) — the exact "from source, never
from the index" method R9 demands:

```
 1    6  stale-phase-guard-rule-text      6   37  memory-system-split
 2    9  falsifier-base-pin               7   53  verification-marker-gate
 3   13  git-guard-chained-command        8   66  memsearch-freshness
 4   13  shell-segments-redirects         9   70  replay-harness-base-pin
 5   24  git-guard-empty-index           10   91  phase-guard-hook
```

N = 10 features (11 files — `memory-system-split` spans two), so ⌊N/3⌋ = 3.

My round-11 counterexample sample was `{git-guard-empty-index, verification-marker-gate,
memsearch-freshness, replay-harness-base-pin, phase-guard-hook}` — four large targets plus one
medium, the exact shape falsifier (i) declares a falsification.

- **Old value-span reading:** span 6–91, bottom third ≤ 34.3. `git-guard-empty-index` at 24 clears
  it; `phase-guard-hook` at 91 clears the top. **The sample passes.** Worse, that reading puts
  **five of ten features — half the population — inside its own "bottom third."**
- **New rank-tertile reading:** bottom third = ranks 1–3 = `{6, 9, 13}`. `git-guard-empty-index` is
  **rank 5**. No sample member is in the bottom third. **The sample fails.**

**The counterexample is dead, and the fix is load-bearing rather than cosmetic** — it changes the
verdict on a real sample and shrinks the bottom third from 50% of the population to 30%.

I also checked for a surviving *third* reading. Percentile interpolation (the 33.3rd percentile of
the value distribution ≈ 13) admits at most `{6, 9, 13, 13}` — it still excludes rank 5. Every
plausible tertile convention kills the counterexample. The `⌈N/3⌉` variant likewise. **No third
reading stands.**

Corroboration of the spec's own self-criticism: at 66 chunks this spec is **rank 8 of 10 — squarely
in its own top third**. Round 8 pinned it at 14 chunks (bottom third) from the stale index. The
spec's claim that the stale index "would have let this very file qualify as the small target while
actually being one of the large ones" is now confirmed by measurement.

Load-bearing code citations spot-checked and all correct: `config.py:56` is the `excludes = …`
assignment that must survive and `:57-60` is the guard to delete; `test_golden_queries.py:37-41`
asserts only `any(expect_path_contains in p for p in paths)` with no score floor and no top-hit
check; stretch and negative cases `warnings.warn` and pass unconditionally;
`pyproject.toml:23` is `addopts = "-m 'not golden'"`; `chunk.py:111` is the `recall =` derivation.

## What could go wrong / what I'm unsure about

**1. There is a live tie exactly on the bottom-third boundary, and the rule does not say how to break
it.** `git-guard-chained-command` and `shell-segments-redirects` are both **13 chunks** — ranks 3 and
4. "The lowest ⌊N/3⌋ entries" does not resolve which one is the third entry.

This is **not exploitable**: the two tied features are identically sized, so a tie-break cannot
smuggle a fat target into the bottom third — the only thing the guard exists to prevent. But it makes
the answer **non-reproducible**: an implementer could pick `shell-segments-redirects` as their small
target and a later reviewer, ranking the other way, would read a rank-4 target claimed as
bottom-third and call it a violation. A false accusation, not a false pass. One sentence fixes it —
*"a tie spanning the boundary places both entries in the third."*

**2. The rule is now sharper than the instrument that feeds it.** R9 says the counts are "computed
from the source files at task-8 time, never read from the index" — and names **no command**. Chunk
count is not a `wc`: it is heading-structure-driven (split on markdown headings, merge sections under
200 chars, hard-split over 2,000). A feature with many small headings yields more chunks than a
same-sized feature with few. An implementer approximating with characters or lines could get a
different rank order, and under a sharp rank cut a one-position error flips membership where under
the old value-span reading it rarely would.

**In this corpus the two orderings happen to agree exactly** (I checked — character rank and true
chunk rank are identical), so the risk is **latent, not live**. This is finding 2 from round 11
appearing in a second place: the rule is prose where R10.6 hands the implementer a literal
`grep -n CODING_MEMORY`. The mechanization for *this* surface is one command, and it is the one I
ran — see the layman summary.

**3. Terminology drift survives in two of the four surfaces.** R9's authority says "the
**population**". Falsifier (i) still says "the chunk-count **range**" and the scenario is titled "The
measurement queries span the corpus size **range**" — "range" being a value-span word for the concept
the round-12 edit exists to reject. Meaning is pinned in all four by the explicit tertile clause, so
this is cosmetic. It is noted because it is exactly the class task 1b's sweep exists to catch, which
makes it a useful live test of that sweep.

**4. The arithmetic reached two surfaces, not four.** `⌊N/3⌋` appears in R9 (`:346-350`) and task 8b
(`:1272-1274`). The scenario (`:1057`) and falsifier (i) (`:1103-1104`) say only "rank tertiles".
Immaterial to the counterexample — every convention excludes rank 5 — but it is not the verbatim
identity this spec holds itself to ("the strict wording, identical to R9").

**5. Carried, unchanged, not re-litigated.** The zero-files gap (a run whose corpus vanished renders
as state 8, **fresh**, indefinitely) remains the one place the design cannot tell a true green from a
false one. It is a user-settled non-goal and is stated plainly in the spec rather than hidden — which
is the best that can be said of it, but documented is not the same as absent, and it is the original
defect one field over. Also carried: task 9's cold-run duration is still unmeasured and could
invalidate `RUN_MAX_HOURS` (falsifier (j) and task 9 both stop-and-ask, so it is trapped); R9 is
measured once at landing and never again; `scheduled-index.log` is deliberately unbounded; R10 has no
prune path, so undoing it costs a multi-hour `--full` rebuild.

**6. Round-11 finding 2 (task 1b's hand sweep) is unchanged and unmechanized.** The carrier is
correctly closed (`git commit --allow-empty`); the mechanism is not. It still demands finding things
no grep can find — *"a state named in prose, without its number, is still a surface"*. Escalation
also still leaves no artifact: `"GATE: Spec change needed"` is a spoken announcement, and the phase
guard exempts `docs/*`.

## The two direct asks

**Does the rank tertile close the gaming vector completely?** **Yes.** Verified against measured
chunk counts, not assumed. No third reading admits the counterexample. The only residual is the
boundary tie in finding 1, which costs reproducibility, not integrity.

**Does anything block opening the implementation gate?** **No. Open it.** Compliance passed at round
11 with zero violations; the one finding I would have called gate-relevant is closed and verified.
Findings 1–4 are implementation-time notes, not design defects; 5 and 6 are carried with named
mitigations.

**And I am reversing my round-11 position on the reorganization — deferring it is the right call, not
merely an acceptable one.** My round-11 recommendation was to move ~85 lines to ADR 0019 before the
gate. Two things I did not weigh then: re-cutting the document now would churn all four spread-rule
surfaces **immediately before task 1b's sweep has to verify they agree** — and that sweep is the
weakest link in the plan, so handing it a freshly-reorganized document is the worst possible input.
Doing it after the gate is phase-illegal. So the window is *now* or *after this branch lands*, and
after is strictly better. The structural finding stands as real and should be a separate planning
pass once the branch is done; it is not a blocker and I no longer think it should have been one.

## What I'd double-check before merging

1. At task 8b, use the project's own chunker rather than a proxy. This command is the mechanization
   finding 2 asks for:
   `uv run python -c "from pathlib import Path; from memsearch.chunk import split_markdown; ..."` —
   aggregate `len(split_markdown(f.read_text()))` per feature stem over `docs/features/*.md`,
   folding `X.spec.md` into `X`.
2. Decide the tie rule before ranking, and write the chosen tie-break down beside the counts.
   Recommendation: a tie spanning the boundary places both entries in the third.
3. Recount N at task-8 time. It is 10 today; any feature added between now and then moves the
   ⌊N/3⌋ boundary. Do not reuse the numbers in this verdict.
4. Have task 1b's sweep specifically report on the "range" vs "population" wording (finding 3) and
   the missing `⌊N/3⌋` in two surfaces (finding 4). If the sweep does not surface at least these two,
   that is evidence about the sweep, not about the spec.
5. Task 9's `--full` timing is the one number that can still invalidate a constant. Confirm it is
   timed explicitly as a cold run, and that `RUN_ABANDON_HOURS` clears it by a margin the user sets.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | Round 12's stated intent was to close finding 1. It did, verifiably, and adopted the recommended reading. |
| `execution` | concern | No code exists and no test command applies at this stage. Task 9's cold-run duration remains unmeasured and can still invalidate `RUN_MAX_HOURS`; trapped by falsifier (j) and a stop-and-ask. |
| `trajectory` | pass | "Surfaces agreeing is not the same as a rule being defined" is the correct generalization and is why this was found by reading the rule rather than diffing its copies. Sound reasoning, not luck. |
| `regression` | pass | No code touched. R10's test-assertion table remains accurate against the live files; `config.py:56/57-60` boundaries re-verified. |
| `context_budget` | concern | 1,317 → 1,336 lines; 66 chunks, rank 8 of 10 in its own ranking population. Not always-on context, but it is mandatory implementer reading and it degrades the reliability of task 1b's hand sweep. Deferral is now judged correct — see the asks. |
| `traceability` | pass | The reasoning is documented in both the commit message and a "Why this needed saying" paragraph; the superseded reading is named rather than silently replaced. |
| `success_masking` | concern | The new content strictly improves failability (bottom third 50% → 30% of population). Residual accepted false-green paths: zero-files run renders fresh; R9 never re-measured after landing; `scheduled-index.log` unbounded. All disclosed, none hidden. |
| `intent_drift` | pass | Diff is exactly the four named surfaces plus rationale. 25 insertions, 6 deletions, one file, no drive-by edits, no dependency changes. |
| `checkpoint` | concern | Clean commit and clean tree, so the revert point is sound. Task 1b's escalation still leaves no artifact, and the phase guard exempts `docs/*`, so "no in-place spec edit during implementation" stays discipline rather than enforcement. |
| `audit_trail` | pass | Commit message is itself ADR-grade; co-authorship recorded; the round-11 finding it answers is named explicitly. |

**risk:** medium · **confidence:** high

Medium is driven by the carried items, not the new work: the zero-files false green is the original
defect one field over and is live in the shipped design, and R10 is a genuinely risky change (largest
source in the corpus, no prune path, multi-hour rebuild to undo). Nothing here blocks the gate.

## Concerns

1. Live tie at the bottom-third boundary (git-guard-chained-command and shell-segments-redirects both 13 chunks, ranks 3/4); no tie-break stated — non-exploitable, but non-reproducible between implementer and reviewer
2. Rank tertile is sharper than its instrument: R9 names no command for computing chunk counts from source; chunk count is heading-structure-driven, not a `wc`, and a sharp rank cut amplifies proxy error
3. Terminology drift survives: falsifier (i) says "chunk-count range" and the scenario title says "corpus size range" where R9's authority says "population"
4. `⌊N/3⌋` reached only 2 of 4 surfaces (R9, task 8b); scenario and falsifier (i) say only "rank tertiles" — immaterial here but not the verbatim identity the spec demands of itself
5. Task 1b sweep still unmechanized and its escalation leaves no artifact; phase guard exempts `docs/*`
6. Carried: zero-files run renders as state 8 fresh indefinitely (user-settled non-goal, disclosed)
7. Carried: task 9's cold-run duration unmeasured; `RUN_MAX_HOURS`/`RUN_ABANDON_HOURS` not yet validated against it
8. Carried: R10 has no prune path — undoing it after a failing R9 requires a multi-hour `index --full`
9. Spec at 1,336 lines; R4-R8 and R10 remain heading-less under R3/R9's `####` subsections — deferral now judged correct, but it degrades task 1b's reliability
