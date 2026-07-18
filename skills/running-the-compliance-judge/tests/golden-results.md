# Golden-Eval Results — 2026-07-18

Agent: `agents/compliance-judge.md` @ 44340bf (evaluated via the wrapper procedure in
`tests/README.md`, Sonnet 5 dispatches, per-run store subdirs under `tests/out/`).

| Fixture | Run 1 verdict / citation | Run 2 verdict / citation | Expected | Pass? |
|---|---|---|---|---|
| golden-pass.md | pass, 0 violations | pass, 0 violations | pass, 0 violations | YES |
| seeded-unpinned-version.md | fail — `writing-specs/pinned-versions` | fail — `writing-specs/pinned-versions` | fail, writing-specs/pinned versions | YES |
| seeded-missing-gherkin.md | fail — `writing-specs/bdd-gherkin-form` | fail — `writing-specs/bdd-gherkin-scenarios` | fail, writing-specs/Gherkin | YES |
| seeded-yagni-bloat.md | fail — `core-conduct/yagni` | fail — `core-conduct/yagni` | fail, core-conduct/YAGNI | YES |
| seeded-embedded-secret.md | fail — `core-conduct/no-hardcoded-secrets` | fail — `writing-secure-code/hardcoded-secrets` + `core-conduct/secrets-as-placeholders` | fail, core-conduct or writing-secure-code/secrets | YES |
| seeded-missing-error-handling.md | fail — `core-conduct/explicit-error-handling` + `writing-specs/good-bad-edge-cases` | fail — `core-conduct/explicit-error-handling` + `writing-specs/good-bad-edge-cases` | fail, core-conduct or writing-specs/error handling | YES |

Verdict: **ALL PASS (12/12 runs on the acceptance bar).** Revisions used: 1 — not
accuracy-driven. The runs exposed **id-slug drift across independent dispatches** for the same
underlying rule (`bdd-gherkin-form` vs `bdd-gherkin-scenarios`; `no-hardcoded-secrets` vs
`secrets-as-placeholders`). The loop detects persistence by comparing ids across rounds, so
drift would break it silently. Amendment applied after the runs: re-judge dispatches (round > 1)
pass the prior round's violations, and the judge reuses the exact prior `id` for any violation
that recurs — making the spec's "deterministic persistence detection" claim actually hold.
Accuracy results above were unaffected (all runs were round-1 dispatches).

Tolerated extras observed (per `expected-citations.md`): secondary citations on seeded fixtures
(stdin-ambiguity on unpinned/yagni; YAGNI + no-dependencies contradiction on secret; ambiguity on
errors). One watch item for future calibration: the base fixture's stdin decode-failure line drew
a violation in some seeded runs but only a note in golden-pass runs — golden-pass still passed
2/2; if a future golden run cites it as a violation, tighten `golden-pass.md`'s Error handling
section to tie exit 3 to an explicit stdin requirement rather than tuning the judge.

## Addendum — HEAD spot-check (agent @ 87b2d37, 2026-07-18)

Final-review closure: the 12/12 table above ran against the agent @ 44340bf; two later
amendments (id-stability, glob date-anchor) changed the shipped bytes. Spot-check at HEAD:
`golden-pass.md` → **pass 2/2** (the stdin line again held as a non-blocking note in both runs —
one run explicitly reasoned from this file's watch item), `seeded-missing-gherkin.md` → **fail**
citing `writing-specs/bdd-gherkin-scenarios`. The shipped agent text is now directly evidenced;
a full 12-run re-baseline was judged unnecessary since the amendments are round>1-scoped and
naming-scoped. (Loop-path evidence at post-amendment wording: `dry-run-log.md`, five dispatches.)
