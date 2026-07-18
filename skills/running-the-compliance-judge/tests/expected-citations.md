# Golden-Eval Expected Citations

A seeded fixture passes the eval when the judge returns `fail` AND cites a violation whose
`rule_source` matches the primary (or acceptable alternate) below with a topically matching
`rule`/`id`. Extra minor violations on seeded fixtures are tolerated; `golden-pass.md` must
return `pass` with zero violations.

| Fixture | Verdict | rule_source (primary; alternate) | Violation topic |
|---|---|---|---|
| golden-pass.md | pass | — | — |
| seeded-unpinned-version.md | fail | skills/writing-specs/SKILL.md | pinned versions |
| seeded-missing-gherkin.md | fail | skills/writing-specs/SKILL.md | BDD/Gherkin scenarios |
| seeded-yagni-bloat.md | fail | rules/core-conduct.md | YAGNI / speculative features |
| seeded-embedded-secret.md | fail | rules/core-conduct.md; skills/writing-secure-code/SKILL.md | secrets as placeholders |
| seeded-missing-error-handling.md | fail | rules/core-conduct.md; skills/writing-specs/SKILL.md | explicit error handling / edge cases |
