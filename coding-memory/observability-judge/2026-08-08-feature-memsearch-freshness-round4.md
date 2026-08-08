# Observability verdict (round 4) — `feature/memsearch-freshness` @ `367126e`

- **stage:** implementation (gates the PR)
- **repo:** `.claude` · **base:** `main` @ `b78eae8` · **25 commits**
- **judged:** 2026-08-08T06:36:12Z
- **head_sha:** `367126edba85180fbd5f348c9d432ed02ba0053f`
- **spec:** `docs/features/memsearch-freshness.md` (`phase: review`)
- **supersedes:** `…-round3.md` @ `1be05b5` (risk=medium, confidence=high)

---

## What was changed

Docs-only, confirmed. `git diff --name-only 1be05b5..HEAD` returns exactly four files, zero code,
zero config, zero test:

```
CODING_MEMORY.md
coding-memory/observability-judge/2026-08-08-feature-memsearch-freshness-round3.md
coding-memory/observability-judge/verdicts.jsonl
docs/features/memsearch-freshness.md
```

Nothing about the software has moved since round 2. All four test commands re-run and match their
declarations **exactly**: `pytest -q` → 74 passed / 23 deselected · `-m golden` → 16 passed ·
`-m measurement` → 3 failed, 4 passed · `nudge.test.sh` → 27/27.

**But the change is not the one line I was told about.** The feature-doc diff has *two* additions:

1. **The threshold widening** (~6 lines) — what round 3 asked for. ✓
2. **A ~30-line block at `:1740`** recording the counterfactual harness as a rebuild recipe, plus two
   new findings about `hooks/phase-guard.sh`. **This was not disclosed in the invocation**, which
   described the round as "one line" and named only `CODING_MEMORY.md` and the round-3 verdict as
   the other changed files.

That undisclosed block is where this round's finding lives.

## 1. Does the widened threshold fix what I flagged? — Yes, substantially

New text at `:1832`:

> **Threshold:** if R9 drops **below 2 of 5**, *or if the same 2 of 5 is reached by a different set of
> queries*, the accepted cost has changed shape… A monitor watching only the count would have watched
> that happen and stayed silent. **Record which queries pass, not how many.**

The in-line proof is **factually correct against the table printed 120 lines above it** (`:1704-1710`)
— I checked the exact thing that failed twice on this branch:

| claim in the new threshold text | table at `:1704-1710` |
|---|---|
| `falsifier-base-pin` regressed | ✓ `**FAIL (1)**` … `**regressed** (was PASS/PASS)` |
| `git-guard-empty-index` improved | ✓ `**PASS (2)**` … `**improved** (was FAIL/PASS)` |
| held at 2 of 5 | ✓ two full passes; `:1711` says the same |

**The signature failure species did not recur here.** The summary sentence and the table agree.

**Residual, minor and non-blocking.** Read literally, the enumerated trip-wire covers a count *drop*
and a *same-count* recomposition, but not a composition change at a **higher** count — R9 going to
3 of 5 while a currently-passing query regresses is the same compensating-moves shape, and neither
clause fires. The closing imperative ("Record which queries pass, not how many") covers it in spirit,
and the trigger already says "record the delta", so a human reading the record would see it. My
round-3 wording ("any change in which queries pass") was broader. **One line if the doc is touched
again; it should not gate the PR.**

## 2. The new undisclosed block — one claim is right, one is wrong ⚠️

The block ends with two findings about `hooks/phase-guard.sh`, which denied a commit of
`memsearch/tests/counterfactual.py`.

### Finding (2), "the guard has no `review` arm" — **TRUE, and a genuinely useful catch**

`phase-guard.sh:387`:

```sh
if [ "$file_phase" = "implementation" ] && [ -n "$file_branch" ]; then
    claimed_branches="$claimed_branches$file_branch
```

Only `implementation` registers a branch claim. A feature file at `review` recording this branch
does **not** authorize source writes — so a branch in review cannot write source at all. (Note the
asymmetry the doc implies: at `:448` the *supersession* path does accept
`implementation|review`. The two paths disagree, which is exactly the kind of thing worth a
planning-pass ticket.) Accurate finding, correctly deferred.

### Finding (1), "that `planning` file is **stale** — its feature **shipped**" — **FALSE**

This is the round's finding. `docs/features/verification-marker-gate.md` has not shipped; it has not
*started*. Six independent checks, all pointing one way:

| check | result |
|---|---|
| Checklist (`:1108-1153`) | **All 15 items unchecked `- [ ]`** — including #7 "Green: `hooks/test-marker-guard.sh`", #13 "Register in `settings.json`", #15 "Obs judge … → PR" |
| `hooks/test-marker-guard.sh` | does not exist (`ls hooks/`) |
| `hooks/lib/classify-commit-command.py`, `write-test-marker.py` | do not exist |
| `git log --all -- 'hooks/*verification*' 'hooks/*marker*'` | **empty** — no commit on any branch |
| Frontmatter | `phase: planning`, **`branch: none`**, `revision: 5` |
| Repo-wide grep for `verification.marker` | one hit only: `measurement_queries.json` |

**Both pieces of evidence the doc cites are non-probative of "shipped":**

- *"it is one of R9's own measurement targets"* — R9's membership rule is
  `test_measurement_queries.py:56`, `belongs()`, which resolves to `docs/features/F.md` or
  `.spec.md`. Being a target means **a document exists to retrieve**. It says nothing about
  implementation. The doc's own table at `:1708` lists it at 53 chunks — that is 53 chunks of *spec*.
- *"with a compliance verdict dated 2026-08-01"* — that file's own header reads
  `Spec: docs/features/verification-marker-gate.md · repo .claude · branch main`. The compliance
  judge judges **specs before user review** (`rules/gates.md`, spec-compliance gate). It is evidence
  the spec was finished, not the feature.

**Why this matters more than a docs typo — it inverts the finding.** If the feature never started,
the planning card is **correctly active**, not stale, and phase-guard denying that write was the hook
doing its one job, not collateral damage. The doc is right to refuse to act ("Advancing or deleting
another feature's file is not this branch's call") — but it hands the next planning pass the label
"stale", which pre-judges that pass toward **advancing or deleting a card that is legitimately
guarding unstarted work**. That would disarm the guard for the one feature it is currently holding.

This repo has precedent for exactly this confusion: `rules/gates.md` already documents four **dormant
hooks** that "exist and pass their tests but are not registered in `settings.json` — they never run."
Written ≠ active is a known local failure mode, and this claim repeats it.

**It is also the third instance of the branch's signature species** — a summary sentence outrunning
the evidence beneath it. Rounds 1, 2, and 3 each caught one. This round's came in the *undisclosed*
scope, which is the observability point: the described change and the delivered change diverged, and
the divergence is precisely where the defect landed.

**Recommended fix — one clause.** Strike "its feature shipped" and replace with the checkable fact:
*"that file has never entered implementation — all 15 checklist items are unchecked, `branch: none`,
and no `test-marker-guard.sh` exists — so the card is correctly active; the real finding is (2)."*
That keeps the useful half and removes the misleading instruction.

## 3. Nothing else moved that shouldn't have — confirmed

- Always-on context untouched across the **entire** branch: `git diff --stat b78eae8..HEAD --
  CLAUDE.md rules/ skills/ settings.json` is **empty**.
- The harness-as-derivation decision itself is **good practice** and I want to say so — it matches
  "store the derivation, not the number", and the citations are sound: `search.py:44-58` (the two
  retriever branches), `CANDIDATES = 200` / `RRF_K = 60` at `:18-19`, `belongs()` at
  `test_measurement_queries.py:56`, and the non-optional no-op guard. Minor: the `search.py:60-66`
  citation covers the RRF sum only — the `× weight` it describes in the same breath is at `:80` and
  the sort/`[:k]` at `:82-86`. Reconstructable, and the no-op guard catches a mis-rebuild. Noted, not
  a finding.

## Carried, unchanged — re-verified, not re-read

R9 red at merge (3 of 5) and deselected by `pyproject.toml:26`; golden suite presence-only and
structurally blind to ranking regressions; `falsifier-base-pin` clause 1 a live user-accepted
R10-caused regression; not cleanly revertible (257 archive chunks survive `git revert`, 4h51m34s
`--full` to remove); `RUN_MAX_HOURS=6` at 81% of measured cold run; zero-files corpus reads fresh
(user-settled non-goal); no index lock; falsifier window not open. All disclosed, all disclosures
still accurate. Not re-litigated.

Another session's `coding-memory/compliance-judge/*` files remain in the tree and were correctly left
alone. Mechanical hazard only: `git commit -a` would sweep them in. Every commit here has been
pathspec-scoped.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| `intent` | **concern** | The primary ask — widen the threshold — is delivered and correct. But the change is ~5x its described scope: a ~30-line undisclosed block accompanied the "one line", and it carries the round's factual error. |
| `execution` | **concern** | All four commands re-run, all match exactly (74 / 16 / 3F-4P / 27-27). Zero drift from round 3. R9 still red at merge and deselected by `pyproject.toml:26`. Carried, unchanged. |
| `trajectory` | **pass** | The threshold fix is sound and grounded in the table beneath it — the failure species did **not** recur in the part I asked for. Recording the harness as a rebuild derivation rather than a dead `/tmp` path is the right instinct. |
| `regression` | **concern** | No code changed, so nothing new. Carried: `falsifier-base-pin` clause 1 live and accepted; detection gap persists (golden can't see ranking, R9 deselected). |
| `context_budget` | **pass** | `CLAUDE.md`, `rules/`, `skills/`, `settings.json` untouched across the whole branch — verified empty diff. |
| `traceability` | **concern** | Ten claims re-checked; nine hold. "Its feature shipped" is contradicted by six independent checks in this repo, and both cited evidences (R9 target, compliance verdict) are non-probative — an R9 target is a *document*, a compliance verdict is a *spec* judgment. |
| `success_masking` | **concern** | Materially improved: the count-only trip-wire I flagged is fixed and proved in-line. Residual literal hole at *rising* counts. Carried: `addopts` deselects the red bar, golden green over a live ranking regression, `RUN_MAX_HOURS` at 81%. |
| `intent_drift` | **concern** | 30 lines beyond the described one-line fix, undisclosed at invocation — and that is exactly where the defect landed. No new deps, no code, no config; other session's files correctly untouched. |
| `checkpoint` | **concern** | 25 clean pathspec-scoped commits; this commit is trivially revertible. Carried: `git revert` does not undo 257 live archive chunks, and the index remains stale against HEAD. |
| `audit_trail` | **pass** | Still the strongest dimension. The three-layer correction chain is preserved visibly, the phase-guard denial is reported honestly rather than worked around, and the doc correctly refuses to touch another feature's file. The wrong label sits inside an otherwise exemplary record. |

## Concerns

1. **`docs/features/memsearch-freshness.md:1755` claims `verification-marker-gate`'s "feature shipped" — it has not started.** All 15 checklist items unchecked, `branch: none`, no `test-marker-guard.sh`, no commit on any branch. Inverts finding (1): the planning card is correctly active, not stale
2. Both evidences cited for "shipped" are non-probative — an R9 measurement target is a *document* (`belongs()`, `test_measurement_queries.py:56`); the 2026-08-01 compliance verdict is a **spec** judgment
3. Mislabeling the card "stale" risks the next planning pass advancing/deleting a card that legitimately guards unstarted work — disarming phase-guard for that feature
4. Round-4 scope was ~5x its description (30 undisclosed lines vs "one line"), and the defect landed in the undisclosed part
5. Widened threshold retains a literal blind spot at *rising* counts (3 of 5 masking one regression); the closing "record which queries pass" covers it in spirit — non-blocking
6. `search.py:60-66` citation backs only the RRF sum; the `× weight` (`:80`) and sort/`[:k]` (`:82-86`) described alongside it fall outside the range — non-blocking
7. R9 remains red at merge (3 of 5); `pyproject.toml:26` deselects it so default `pytest -q` reports 74 passed
8. `falsifier-base-pin` clause 1 is a live, user-accepted R10-caused ranking regression
9. Golden suite presence-only — structurally cannot detect this class of ranking regression
10. Not cleanly revertible: 257 archive chunks persist after `git revert`; removal costs a measured 4h51m34s `--full`
11. `RUN_MAX_HOURS=6` at 81% of measured cold run, margin explicitly non-durable
12. Zero-files corpus renders fresh indefinitely — declared non-goal
13. No index lock: manual and scheduled runs can race on `status.json`
14. Falsifier window not open — post-landing re-check owed
15. Index stale against HEAD; working tree carries another session's compliance-judge files (`git commit -a` would sweep them in)

**risk = medium · confidence = high**
