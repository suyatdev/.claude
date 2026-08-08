# Observability judge — `feature/memsearch-freshness` (round 5, implementation)

- **repo:** `.claude` · **branch:** `feature/memsearch-freshness` · **HEAD:** `5ff613d3311cc96413511f4da35ec6bf6765cf76`
- **base:** `main` @ `b78eae82e39b05f011dd118f19c40f5e4c69f48d` · **stage:** `implementation`
- **ts:** 2026-08-08T06:43:01Z
- **supersedes:** `…-round4.md` @ `367126e` (risk=medium, confidence=high)
- **why this round exists:** `hooks/judge-guard.sh` matches HEAD strictly. One commit landed
  (`5ff613d`), applying round 4's single blocking finding. No new feature work.

---

## What was changed

Round 4 caught a sentence in the feature doc that said another feature — the verification-marker
gate — had already shipped. It hadn't. This commit deletes that claim and replaces it with the
opposite: the gate has *never started*, so the guard card sitting in front of it is doing real work,
not left over. One citation was also widened to cover a line it had been skipping.

Think of it as a fire-alarm panel. The doc had labelled one alarm "false — building already
evacuated". Someone checked: the building was never evacuated. The label is now corrected, and the
correction says out loud why the wrong label was the dangerous part — the next person could have used
it to justify silencing a live alarm.

**No code, config, or test changed.** Verified: `git diff --name-status 367126e..HEAD` is exactly
three files — the feature doc (+28/−6), the round-4 verdict (new), and `verdicts.jsonl` (+1).

## Does it do what you wanted?

**Yes.** The one blocking fix was asked for, and it is the one thing that landed.

Better than that: the author didn't take round 4's word for it. Every fact in the new note is
independently checkable, and I checked all six:

| claim in the corrected note | my check | result |
|---|---|---|
| `phase: planning`, `branch: none` | frontmatter of `docs/features/verification-marker-gate.md` | ✓ both |
| 15 of 15 checklist items unchecked | `grep -c '^\s*- \[ \]'` = 15, `- [x]` = 0 | ✓ |
| no `hooks/test-marker-guard.sh` | `ls hooks/ \| grep -i marker` | ✓ none |
| no implementation commit on any branch | `git log --all -- docs/features/verification-marker-gate.md` → 5 commits, all `docs(features):` spec revisions; `git log --all -- 'hooks/*marker*'` empty | ✓ |
| an R9 target is only a *document* | `belongs()` at `test_measurement_queries.py:56-59` matches `docs/features/F.md` / `F.spec.md` and nothing else | ✓ |
| the 2026-08-01 verdict judged the *spec* | its header line 3 reads ``Spec: `docs/features/verification-marker-gate.md` · branch `main` `` | ✓ |

**Overcorrection check: none.** "It has not shipped; it has not started" is exactly what the
evidence supports — no stronger.

**Scope disclosure: complete.** Round 4's fair criticism was a ~30-line undisclosed block. This round
discloses both hunks and the diff contains only those two. Fixed.

**Tests, run by me at HEAD, not reported second-hand:**

| command | result |
|---|---|
| `pytest -q` | **74 passed**, 23 deselected |
| `pytest -q -m golden` | **16 passed** |
| `pytest -q -m measurement` (R9) | **3 failed, 4 passed** — 2 of 5 queries pass |
| `hooks/memsearch-nudge.test.sh` | **27/27** |
| `memsearch/bin/install-schedule.test.sh` | **19/19** |

Every number matches round 4 exactly. Zero drift.

## What could go wrong / what I'm unsure about

**1. The surviving finding is worded in a way a reader can falsify in one grep.** The doc says
"`phase-guard.sh` has no `review` arm". It has one — `hooks/phase-guard.sh:448` matches
`^phase:[[:space:]]*(implementation|review)`, with a comment at `:422-423` explaining that review
*must* count "or a finished feature whose main copy still reads planning blocks forever".

The gap is real but narrower than stated. It lives in the **branch-claim** path: `:387` collects a
branch as authorized only when `[ "$file_phase" = "implementation" ]`, and step 9 (`:522-527`) tests
membership against that list. So the supersession arm accepts `review`; the authorization arm does
not. Naming `:387` would make the finding precise and non-falsifiable.

Second, smaller: "a branch in review cannot write source **at all**" holds only while some
*unsuperseded planning card exists elsewhere* — `:418` and `:502` both `exit 0` when
`planning_files` is empty. The sentence immediately before it does supply that condition
(`while docs/features/verification-marker-gate.md still sits at phase: planning`), so the paragraph
is right; the summary sentence read alone is not.

This is the fifth round with the same species — a summary sentence outrunning the evidence beneath it.
I am calling it out because the pattern is what matters. But I will not inflate it: this one misstates
a guard's internal *structure* inside a finding explicitly deferred to another phase. It cannot cause
an action. Rounds 1–4 each misstated a *causal* claim, one of which nearly licensed disarming a live
safety card. This is a different order of magnitude.

**2. On length — my answer to the direct question: no, don't compress the retractions, and the
length problem is not where you think it is.**

The three retractions are ~40 lines of 1,898. Compressing them saves ~2% and destroys the single most
valuable thing in the document. Keep them verbatim.

But the length cost you flagged is real, and I have it measured rather than asserted. This doc is not
merely "rank 1 on two of R9's queries" — it is the **displacing top hit in two of the three R9
failures**, from my live run:

```
verification-marker-gate: clause 2 FAIL (top=.../docs/features/memsearch-freshness.md)
phase-guard-hook:         clause 2 FAIL (top=.../docs/features/memsearch-freshness.md)
```

In both, the correct feature's own doc is pushed to rank 4 and rank 3 by this one. 1,898 lines /
135 KB / 91 chunks — far past the 400-line house guidance, in a repo whose SessionStart hook
advertises memsearch on every single session.

**And the fix is not free either — the doc itself proves it.** Its own counterfactual at `:1786-1791`
shows `git-guard-empty-index` goes PASS(2) → FAIL(1) with this file removed. Shrink it carelessly and
R9 goes from 2 of 5 to 1 of 5. So "just compress it" is a change that moves the very metric under
test, in an unknown direction, and would need its own re-run. That makes it planning-pass work — the
`.spec.md` split under one-canonical-file discipline — not a pre-merge tidy-up.

**3. Green tests over a red bar (carried, disclosed, not re-litigated — but stated plainly).**
`pytest -q` prints **74 passed** while the feature's own retrieval bar is **2 of 5**, because
`pyproject.toml:26` sets `addopts = "-m 'not golden and not measurement'"`. A user-accepted decision
with a monitor, and fully documented — but anyone who runs the default suite sees green over a red
quality bar. That is the definition of success masking, however well disclosed.

**4. Carried, verified still true, not re-argued:** `falsifier-base-pin` clause 1 is a live
R10-caused ranking regression, accepted by the user 2026-08-08; the golden suite is presence-only and
structurally cannot see a ranking regression; the index is stale against HEAD so these numbers move at
the next scheduled run; `git revert` leaves ~257 archive chunks in the live DB (removal = a measured
4h51m `--full`); `RUN_MAX_HOURS=6` sits at 81% of the measured cold run; no index lock; zero-files
renders fresh forever (declared non-goal); ADR 0021 deferred.

## What I'd double-check before merging

1. **One-line precision fix, non-blocking:** change "no `review` arm" → "the branch-claim arm
   (`phase-guard.sh:387`) accepts only `implementation`; the supersession arm (`:448`) already accepts
   `review`", and keep the "while a planning card is active" condition attached to the summary
   sentence. If you'd rather not reopen the doc a sixth time, carry it into the planning-pass card
   instead — that is where the fix lands anyway.
2. **Stage with an explicit pathspec.** The working tree holds `M coding-memory/compliance-judge/
   verdicts.jsonl` and an untracked `2026-08-08-falsify-harness-signatures.md` from another session's
   feature. Correctly untouched — but `git commit -a` would sweep them in, and `git-guard` reads the
   *index*, not your pathspec, so unstage foreign paths before committing.
3. **Re-run R9 after the next scheduled index.** The recorded numbers were taken against a stale
   index; they reproduced exactly today, but they will move.
4. **Book the `.spec.md` split as a planning-pass task**, with the counterfactual re-run afterwards.
   Do not do it on this branch.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| `intent` | **pass** | The one blocking fix was asked for and is the only thing that landed. Round 4's `concern` (5× scope) is resolved: diff = exactly the two disclosed items. |
| `execution` | **concern** | All five commands re-run by me; all five match round 4 exactly (74 / 16 / 3F-4P / 27-27 / 19-19). Zero drift. Carried: R9 red at merge, deselected by `pyproject.toml:26`. |
| `trajectory` | **pass** | The author checked round 4's claim against six independent facts rather than deferring to the judge, found it right, recorded the conclusion *flipping*, and named why the old wording was the dangerous part. That is reasoning, not luck. |
| `regression` | **concern** | No code changed since `367126e`; nothing new. Carried: `falsifier-base-pin` clause 1 live and accepted; detection gap persists. |
| `context_budget` | **concern** | *Re-scoped from round 4's `pass`, on measurement not on a new fact.* Always-on files are untouched branch-wide (`CLAUDE.md`, `rules/`, `skills/`, `settings.json` — empty diff, verified). But the retrieval index **is** an attention surface here, advertised at every SessionStart, and this 1,898-line doc is the displacing top hit in 2 of R9's 3 failures. Not a `fail`: removing it makes R9 *worse* (2/5 → 1/5), per its own control. |
| `traceability` | **concern** | The corrected note is exemplary — six checkable facts, all six hold, no overcorrection. The residual: "no `review` arm" is contradicted by `phase-guard.sh:448`; the true gap is `:387`. Fifth instance of the summary-outruns-evidence species, but the first that cannot cause an action. |
| `success_masking` | **concern** | Carried, unchanged: `addopts` hides the red bar behind 74 green; golden is presence-only and cannot see ranking. Disclosed and user-accepted, which mitigates but does not remove it. |
| `intent_drift` | **pass** | Round 4's `concern` resolved. `git diff --name-status 367126e..HEAD` = 3 files, all disclosed; feature-doc diff = exactly 2 hunks, both described. No deps, no code, no config. Another session's files correctly left alone. |
| `checkpoint` | **concern** | Single clean doc-only commit, trivially revertible. Carried: `git revert` does not unwind 257 live archive chunks; index stale against HEAD. |
| `audit_trail` | **pass** | The strongest dimension, and stronger than round 4. The correction is dated, attributed to round 4, states its evidence inline, records the conclusion flipping rather than quietly editing, and refuses to touch another feature's file. |

**risk = medium · confidence = high**

## Concerns

1. `phase-guard.sh` **does** have a `review` arm (`:448`, supersession); the real gap is the
   branch-claim arm at `:387` — the doc's wording is falsifiable by one grep
2. "a branch in review cannot write source at all" drops the "while an unsuperseded planning card
   exists" condition (`:418`, `:502` both `exit 0` otherwise) — condition is supplied one sentence
   earlier, so the paragraph is correct and the summary alone is not
3. Fifth consecutive round with a summary sentence outrunning its evidence — first one that cannot
   cause an action, but the pattern is the finding
4. `docs/features/memsearch-freshness.md` (1,898 lines / 91 chunks) is the **displacing top hit** in
   2 of R9's 3 failures, pushing each target's own doc to rank 3–4
5. Compressing the doc is not free: its own control shows removal takes R9 from 2/5 to 1/5 — any
   shrink needs a counterfactual re-run, so it is planning-pass work, not a pre-merge tidy
6. The three retractions should **not** be compressed — ~2% of length, ~100% of the audit value
7. R9 red at merge (3 of 5 fail); `pyproject.toml:26` deselects it, so default `pytest -q` reports
   74 passed over a red bar
8. `falsifier-base-pin` clause 1 is a live, user-accepted R10-caused ranking regression
9. Golden suite is presence-only — structurally cannot detect this class of ranking regression
10. Not cleanly revertible: ~257 archive chunks persist after `git revert`; removal costs a measured
    4h51m34s `--full`
11. `RUN_MAX_HOURS=6` at 81% of the measured cold run; margin explicitly non-durable
12. Zero-files corpus renders fresh indefinitely — declared non-goal
13. No index lock: manual and scheduled runs can race on `status.json`
14. Falsifier window not open — post-landing re-check owed
15. Index stale against HEAD; working tree carries another session's `compliance-judge` files —
    correctly untouched, but `git commit -a` would sweep them in
