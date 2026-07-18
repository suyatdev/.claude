# feature/compliance-judge — Implementation Log

Spec: `docs/superpowers/specs/2026-07-18-compliance-judge-design.md`
Plan: `docs/superpowers/plans/2026-07-18-compliance-judge.md`

## Progress
- Task 1: agent definition + verdict-store README — DONE
- Task 1 fix: verdict filename globs existing spec_slug file across rounds — DONE
- Task 2: golden fixtures + expected citations — DONE
- Task 3: golden eval green 12/12 (2x6, Sonnet 5 wrappers); id-stability amendment (prior-round violations passed for exact id reuse) — DONE
- Task 4: skills/running-the-compliance-judge/SKILL.md + gate stub in rules/gates.md + catalog line in CLAUDE.md — DONE

## Task 4 trigger verification (manual — no eval CI exists for skill routing; this is the authoring-standard's required hand check)
1. "the spec is finished, run the compliance check" → routes to `running-the-compliance-judge`: matches its "spec/design doc is finished... before the user reviews it" trigger clause exactly; no other skill's description mentions spec-finished timing.
2. "judge this spec against our rules before I review it" → routes to `running-the-compliance-judge`: "judge"+"spec"+"rules"+"before...review" line up with the description verbatim, and its "Not for... reviewing PRs (see /review)" clause rules out /review since this names a spec, not a PR.
3. "I edited the spec during review — re-run the compliance judge" → routes to `running-the-compliance-judge`: the SKILL.md's own Freshness note ("edits the user requests during their review — invalidates it; re-run the loop") covers this exact re-entry case; no other skill addresses spec re-verification after an edit.
4. "judge the implementation before the PR" → routes to `running-the-observability-judge`: "implementation"+"before the PR" matches that skill's "after implementing a change, before opening a PR" trigger, and running-the-compliance-judge's own description explicitly excludes "judging code diffs (see running-the-observability-judge)".
5. "review this pull request" → routes to `/review`: names a PR directly, matching /review's "Review a GitHub pull request" description; running-the-compliance-judge explicitly excludes "reviewing PRs (see /review)", and running-the-observability-judge is for scoring a change pre-PR, not reviewing an already-opened PR.
6. "verify the subagent's commit landed" → routes to `verifying-subagent-commits`: "subagent" + "commit... landed" matches that skill's description ("subagent reports DONE with a commit SHA... confirm the commit landed") word for word; neither judge skill mentions subagent dispatch or commit verification.
- Task 4 fix: gate stub namespaces superpowers:writing-plans (house convention; plan block matched) — DONE
- Task 5: loop dry-run — convergence OK (3 rounds, note-promotion pattern recorded), escalation trigger OK (exact id reuse verified) — DONE
