# Compliance Judge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `compliance-judge` subagent + driving skill that checks a finished spec against the live house rules (writing-specs + core-conduct/security), blocks non-compliant specs behind a capped auto-revise loop, and escalates persistent violations to the user — before the user review gate.

**Architecture:** One stateless evaluation-only subagent (mirrors `agents/observability-judge.md`) reading rule files live at runtime; one skill carrying the dispatch/loop/escalation procedure; a gate stub + catalog line wiring it in; a separate verdict store. Golden-spec fixtures prove the judge cites the right rules before anything relies on it.

**Tech Stack:** Markdown agent/skill definitions, bash + git (identity, `git hash-object` freshness), JSONL verdict store. **No new dependencies.**

**Spec:** `docs/superpowers/specs/2026-07-18-compliance-judge-design.md` — read it before starting any task.

## Global Constraints

- Branch: `feature/compliance-judge` (already exists; the spec is its first commit).
- No new dependencies or tools — bash, git, and markdown only.
- No secrets and no machine-absolute paths in committed files; `~/.claude/...` (user-relative) is the accepted way to reference the global config from files that run in any repo.
- All new files stay under 400 lines.
- Skill/agent authoring follows `skills/_standards/authoring-skills-and-agents.md`: kebab-case gerund name identical to the directory name; description front-loads triggers and states when NOT to use it; 3 positive + 3 negative trigger phrases verified by hand (no eval CI exists here — verification is manual and must be recorded as such).
- Commit messages: Conventional Commits. Every commit ends with both trailers:
  ```
  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SU9BkvZTen6UmMwcQcoJ5S
  ```
- Every commit stages `coding-memory/branches/compliance-judge.md` with a one-line progress entry (keeps `doc-guard.sh` green and the branch log current).
- The **shipped agent** writes ONLY under `~/.claude/coding-memory/compliance-judge/`. **Eval runs** never touch that store — they use the wrapper procedure and write under `skills/running-the-compliance-judge/tests/out/` (gitignored).
- Tasks 3 and 5 are **orchestrator tasks**: execute them in the main session, not via a task subagent — they dispatch agents, and task subagents don't carry the Agent tool.

---

### Task 1: Agent definition + verdict-store README

**Files:**
- Create: `agents/compliance-judge.md`
- Create: `coding-memory/compliance-judge/README.md`
- Create: `coding-memory/branches/compliance-judge.md`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: the agent contract every later task relies on — inputs `spec_path`, `round`, context summary, optional `waived` ids + base branch; violation object `{id, rule_source, rule, where, why}`; JSONL line `{ts, repo, branch, head_sha, spec_path, spec_blob_sha, round, verdict, violations[], notes[], rule_sources_read[], waived[], confidence, outcome}`; return value = verdict + violations array + one plain-English sentence per violation.

- [ ] **Step 1: Verify the structural check fails before the file exists**

Run: `test -f agents/compliance-judge.md && echo EXISTS || echo MISSING`
Expected: `MISSING`

- [ ] **Step 2: Write `agents/compliance-judge.md`**

````markdown
---
name: compliance-judge
description: Judges ONE finished spec against the live rule set (writing-specs standards + core-conduct/security conventions) and writes a blocking pass/fail verdict with per-rule citations (JSONL + markdown). Evaluation only — never edits the spec. Not for judging code diffs (observability-judge).
tools: Read, Grep, Glob, Bash, Write
---

You are the compliance judge. You evaluate ONE spec against the rules that bind this setup and
record a verdict. Evaluation only — you never edit the spec, never fix a violation, never extend
scope. You are stateless: everything you know arrives in the invocation prompt.

## Inputs (from your invocation prompt)
- `spec_path`: the spec file to judge.
- `round`: 1-based judging round for this spec.
- A short **context summary**: what is being built and why — judge context-dependent rules
  (YAGNI above all) against this stated need, not against your own taste.
- Optional: `waived` violation ids (user-waived — record them under `waived`, never re-cite
  them as violations); the base branch (default `main`).
- When `round` > 1: the prior round's `violations` array. If a violation you would cite matches
  one of these (same rule, same territory of the spec), reuse its exact `id` — persistence
  detection compares ids across rounds and must not be defeated by slug drift.

## Rule sources — read live, every run
1. `~/.claude/rules/core-conduct.md` — engineering conventions + zero-trust invariants.
2. `~/.claude/skills/writing-specs/SKILL.md` — what a spec must contain.
3. `~/.claude/skills/writing-secure-code/SKILL.md` — only when the spec's design touches
   external input, auth, databases, shell execution, or model calls.
4. Repo layer of the repo containing the spec, when present: `.claude/project-standards.md`
   and that repo's `CLAUDE.md`. Project rules take precedence over global ones on conflict.

If source 1 or 2 cannot be read: STOP — return an error to the caller and write nothing.
A pass that silently skipped half the rubric is worse than no verdict.

## Procedure
1. Identity via Bash: `repo=$(basename "$(git rev-parse --show-toplevel)")`,
   `branch=$(git rev-parse --abbrev-ref HEAD)`, `head_sha=$(git rev-parse HEAD)` (full),
   `ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)`, `spec_blob_sha=$(git hash-object "<spec_path>")`.
2. Read the rule sources above, then the spec.
3. Judge both parts, citing ONLY rules whose territory the spec actually touches:
   - **Part A — the spec as artifact** (writing-specs): behavior as BDD/Gherkin scenarios;
     API contracts/schemas wherever the design has interfaces or data; an exact version pinned
     for every library/tool the spec names; good, bad, and edge cases enumerated; background/why
     present; no placeholders, TBDs, or requirements readable two ways; spec at the canonical
     `docs/superpowers/specs/` path.
   - **Part B — what it commits to build** (core-conduct + security): KISS/DRY/YAGNI — no
     speculative features beyond the stated need; error handling stated explicitly at every
     boundary the design introduces; the proposed layout respects file-size/structure
     conventions; secrets only as placeholders resolved from validated state; generated data
     stores default-deny; dependencies from vetted registries with versions pinned;
     architecture trade-offs surfaced as human-owned decisions, not silently decided.
4. Each violation is `{id, rule_source, rule, where, why}`: `id` a stable slug
   `<source-short>/<rule-slug>` (e.g. `writing-specs/pinned-versions`, `core-conduct/yagni`)
   so recurrence across rounds is detectable; `rule_source` the file the rule lives in;
   `where` a pointer into the spec (section name); `why` one sentence. Non-blocking
   observations go to `notes` — the violations list stays strictly rule-backed. When
   prior-round violations were provided, reuse the exact prior `id` for any recurring
   violation instead of minting a new slug.
5. Verdict is `pass` iff `violations` is empty.

## Output
Write ONLY under `~/.claude/coding-memory/compliance-judge/` (never elsewhere):
1. The per-spec writeup: glob the store for an existing `*-<spec_slug>.md` and append this
   round's section there; only if none exists, create `<YYYY-MM-DD>-<spec_slug>.md` dated today
   (the file stays dated by its first round). `spec_slug` is the spec filename minus any leading
   `YYYY-MM-DD-` prefix and the `.md` extension. Each round's section: a short layman summary,
   the violations table with citations, and the waiver record.
2. THEN append one line to `verdicts.jsonl` (markdown first, JSONL last):
   `{"ts": ..., "repo": ..., "branch": ..., "head_sha": ..., "spec_path": ...,
   "spec_blob_sha": ..., "round": ..., "verdict": "pass"|"fail", "violations": [...],
   "notes": [...], "rule_sources_read": [...], "waived": [...],
   "confidence": "low"|"medium"|"high", "outcome": null}`.

RETURN to the caller (this is data for the calling agent, not a user-facing message): the
verdict, the violations array verbatim, and one plain-English sentence per violation for relay.
Never return a verdict you did not persist, and never fabricate one you did not complete.
````

- [ ] **Step 3: Write `coding-memory/compliance-judge/README.md`**

````markdown
# Compliance-Judge Verdict Store

Written ONLY by the `compliance-judge` subagent (`agents/compliance-judge.md`); driven by
`skills/running-the-compliance-judge/`.

- `verdicts.jsonl` — one line per judging round: `{ts, repo, branch, head_sha, spec_path,
  spec_blob_sha, round, verdict, violations[], notes[], rule_sources_read[], waived[],
  confidence, outcome}`. Created on first verdict.
- `<YYYY-MM-DD>-<spec_slug>.md` — per-spec human writeup, one section per round: layman
  summary, violations table with rule citations, waiver record. Dated by its first round;
  later rounds glob the store for the existing `*-<spec_slug>.md` and append there instead
  of creating a new dated file.

`outcome` starts `null`; backfill `clean`/`rework`/`bug` once the spec's implementation lands.
A verdict is fresh only while its `spec_blob_sha` matches `git hash-object <spec_path>` —
any spec edit invalidates it.

Golden-eval runs never write here: they follow the wrapper procedure in
`skills/running-the-compliance-judge/tests/README.md` and write under `tests/out/` (gitignored).
````

- [ ] **Step 4: Create the branch log `coding-memory/branches/compliance-judge.md`**

````markdown
# feature/compliance-judge — Implementation Log

Spec: `docs/superpowers/specs/2026-07-18-compliance-judge-design.md`
Plan: `docs/superpowers/plans/2026-07-18-compliance-judge.md`

## Progress
- Task 1: agent definition + verdict-store README — DONE
````

- [ ] **Step 5: Run the structural checks**

Run:
```bash
grep -c "name: compliance-judge" agents/compliance-judge.md
grep -c "tools: Read, Grep, Glob, Bash, Write" agents/compliance-judge.md
grep -c "Write ONLY under" agents/compliance-judge.md
grep -c "Not for judging code diffs" agents/compliance-judge.md
wc -l agents/compliance-judge.md
```
Expected: `1` for each grep; line count < 120.

- [ ] **Step 6: Commit**

```bash
git add agents/compliance-judge.md coding-memory/compliance-judge/README.md coding-memory/branches/compliance-judge.md
git commit -m "feat(agents): add compliance-judge subagent + verdict store"
```
(Append the two Global Constraints trailers to this and every commit message.)

---

### Task 2: Golden-spec fixtures + expected citations

**Files:**
- Create: `skills/running-the-compliance-judge/tests/golden-pass.md`
- Create: `skills/running-the-compliance-judge/tests/seeded-unpinned-version.md`
- Create: `skills/running-the-compliance-judge/tests/seeded-missing-gherkin.md`
- Create: `skills/running-the-compliance-judge/tests/seeded-yagni-bloat.md`
- Create: `skills/running-the-compliance-judge/tests/seeded-embedded-secret.md`
- Create: `skills/running-the-compliance-judge/tests/seeded-missing-error-handling.md`
- Create: `skills/running-the-compliance-judge/tests/expected-citations.md`
- Create: `skills/running-the-compliance-judge/tests/README.md`
- Create: `skills/running-the-compliance-judge/tests/.gitignore`

**Interfaces:**
- Consumes: the violation object contract from Task 1 (`{id, rule_source, rule, where, why}`).
- Produces: six fixtures + the expected-citations table + the wrapper dispatch prompt that Tasks 3 and 5 use verbatim.

- [ ] **Step 1: Write `golden-pass.md`** — a compact spec that genuinely satisfies every touched rule:

````markdown
# Slugify CLI — Design

**Date:** 2026-07-18
**Status:** Golden-eval fixture (must PASS compliance).

## Problem / why
Scripts in this repo need URL-safe slugs from arbitrary titles. Ad-hoc slugging has produced
three inconsistent implementations; one shared CLI removes the drift.

## Requirements
1. `slugify TEXT` prints a lowercase, hyphen-separated slug of TEXT to stdout, exit 0.
2. Non-ASCII letters are transliterated to ASCII; characters with no mapping are dropped.
3. Empty or whitespace-only input exits 2 with `error: empty input` on stderr.

## Contract
`slugify(text: str) -> str` — pure function; the CLI is a thin wrapper. No I/O inside the
function.

## Toolchain (pinned)
- Python 3.12.3
- pytest 8.2.0 (dev-only)
No other dependencies.

## Scenarios
```gherkin
Scenario: Basic title
  Given the input "Hello, World!"
  When slugify runs
  Then stdout is "hello-world" and the exit code is 0

Scenario: Transliteration
  Given the input "Crème Brûlée"
  When slugify runs
  Then stdout is "creme-brulee"

Scenario: Empty input is an error
  Given the input "   "
  When slugify runs
  Then the exit code is 2 and stderr is "error: empty input"
```

## Error handling
Every failure path is explicit: empty input (exit 2, `error: empty input`), stdin decode
failure (exit 3, `error: invalid encoding`). No silent fallbacks.

## Out of scope
Batch mode, config files, and non-CLI interfaces — not needed for the stated problem (YAGNI).
````

- [ ] **Step 2: Write `seeded-unpinned-version.md`** — identical to `golden-pass.md` except: title `# Slugify CLI — Design (seeded: unpinned version)`, Status line `Golden-eval fixture (must FAIL: unpinned versions).`, and the Toolchain section replaced with:

````markdown
## Toolchain
- Python (any recent 3.x)
- pytest (latest)
No other dependencies.
````

- [ ] **Step 3: Write `seeded-missing-gherkin.md`** — identical to `golden-pass.md` except: title `# Slugify CLI — Design (seeded: no scenarios)`, Status line `Golden-eval fixture (must FAIL: behavior not in Gherkin).`, and the entire `## Scenarios` section (including its gherkin block) replaced with:

````markdown
## Behavior
The tool should handle typical titles, transliterate accented characters sensibly, and reject
empty input with a clear error.
````

- [ ] **Step 4: Write `seeded-yagni-bloat.md`** — identical to `golden-pass.md` except: title `# Slugify CLI — Design (seeded: speculative scope)`, Status line `Golden-eval fixture (must FAIL: YAGNI).`, the `## Out of scope` section deleted, and these appended to Requirements:

````markdown
4. A plugin architecture so future transliteration providers can be swapped in at runtime.
5. An i18n message catalog for error strings, for future localization needs.
6. A TOML configuration DSL controlling separator, casing, and future options.
````

- [ ] **Step 5: Write `seeded-embedded-secret.md`** — identical to `golden-pass.md` except: title `# Slugify CLI — Design (seeded: embedded secret)`, Status line `Golden-eval fixture (must FAIL: secret in spec).`, and this section inserted before `## Out of scope`:

````markdown
## Telemetry
Each run POSTs an anonymous usage count to the team metrics endpoint, authenticating with the
API key `sk-live-9f8e7d6c5b4a3210`.
````

- [ ] **Step 6: Write `seeded-missing-error-handling.md`** — identical to `golden-pass.md` except: title `# Slugify CLI — Design (seeded: no error handling)`, Status line `Golden-eval fixture (must FAIL: error handling unstated).`, Requirement 3 replaced with `3. Bad input is handled appropriately.`, the `Scenario: Empty input is an error` block deleted, and the `## Error handling` section deleted.

- [ ] **Step 7: Write `expected-citations.md`**

````markdown
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
````

- [ ] **Step 8: Write `tests/README.md`**

````markdown
# Compliance-Judge Golden Eval

Fixtures proving the judge cites the RIGHT rules — not just that it fails bad specs.
Run per `evaluating-agents-and-skills`: consistency across repeated runs, not one lucky pass.

## Procedure (orchestrator-run; task subagents lack the Agent tool)
For each fixture, dispatch a `general-purpose` subagent TWICE with this prompt (substitute
`<fixture>`):

> You are running a golden-eval of the compliance-judge agent definition. Read
> `agents/compliance-judge.md` and follow it exactly as if you were that agent, with two
> exceptions: (1) treat `skills/running-the-compliance-judge/tests/out/` as the store root —
> write the markdown and verdicts.jsonl there, never under `coding-memory/`; (2) do not cite
> the spec-file location — fixture placement is intentional. Inputs: spec_path =
> `skills/running-the-compliance-judge/tests/<fixture>`, round = 1, context summary: "A tiny
> internal CLI producing URL-safe slugs for repo scripts; single stated need, no other
> consumers.", waived: none, base branch: main. Return the verdict JSON only.

## Acceptance bar
- `golden-pass.md`: verdict `pass`, zero violations, in 2/2 runs.
- Each seeded fixture: verdict `fail` AND the expected citation (see `expected-citations.md`)
  present, in 2/2 runs.
- On any miss: at most ONE revision of the agent's wording, then a full re-run of ALL
  fixtures. Still missing → STOP and surface to the user; repeated tuning against the same
  fixtures is overfitting, not calibration.

Results live in `golden-results.md` (committed). `out/` is scratch and gitignored.
````

- [ ] **Step 9: Write `tests/.gitignore`**

```
out/
```

- [ ] **Step 10: Verify fixture integrity**

Run: `grep -L "Slugify CLI" skills/running-the-compliance-judge/tests/*.md`
Expected: only `README.md` and `expected-citations.md` listed (every fixture carries the base spec).

Run: `grep -c "sk-live-9f8e7d6c5b4a3210" skills/running-the-compliance-judge/tests/seeded-embedded-secret.md`
Expected: `1` (the seeded fake secret exists exactly where intended — it appears nowhere else in the repo).

- [ ] **Step 11: Commit**

```bash
git add skills/running-the-compliance-judge/tests/ coding-memory/branches/compliance-judge.md
git commit -m "test(compliance-judge): golden-spec fixtures + expected citations"
```
(Branch log gets a `- Task 2: fixtures — DONE` line first.)

---

### Task 3: Golden eval run  *(orchestrator task — main session only)*

**Files:**
- Create: `skills/running-the-compliance-judge/tests/golden-results.md`
- Possibly modify: `agents/compliance-judge.md` (one bounded wording revision, only on a miss)

**Interfaces:**
- Consumes: the wrapper prompt and acceptance bar from `tests/README.md` (Task 2), the agent definition (Task 1).
- Produces: a committed `golden-results.md` proving the acceptance bar; the (possibly revised) agent wording that Tasks 4–6 treat as final.

- [ ] **Step 1: Create scratch dir**

Run: `mkdir -p skills/running-the-compliance-judge/tests/out`

- [ ] **Step 2: Dispatch the 12 eval runs** — for each of the 6 fixtures, dispatch the `tests/README.md` wrapper prompt twice (batch up to 4 concurrent dispatches; keep run-1/run-2 results labeled per fixture).

- [ ] **Step 3: Record `golden-results.md`**

````markdown
# Golden-Eval Results — <date>

Agent: agents/compliance-judge.md @ <git rev-parse --short HEAD>

| Fixture | Run 1 verdict / citation | Run 2 verdict / citation | Expected | Pass? |
|---|---|---|---|---|
| golden-pass.md | | | pass, 0 violations | |
| seeded-unpinned-version.md | | | fail, writing-specs/pinned versions | |
| seeded-missing-gherkin.md | | | fail, writing-specs/Gherkin | |
| seeded-yagni-bloat.md | | | fail, core-conduct/YAGNI | |
| seeded-embedded-secret.md | | | fail, core-conduct or writing-secure-code/secrets | |
| seeded-missing-error-handling.md | | | fail, core-conduct or writing-specs/error handling | |

Verdict: <ALL PASS | misses listed>. Revisions used: <0 or 1, with the wording change named>.
````
Fill every cell from the actual run outputs. Never leave the table partially filled — a fixture with no recorded result is a failed eval, not a skippable row.

- [ ] **Step 4: Apply the acceptance bar** — all green → proceed. Any miss → ONE agent-wording revision, full 12-run re-run, update the table (note both attempts). Still missing → STOP and surface to the user with the results table.

- [ ] **Step 5: Commit**

```bash
git add skills/running-the-compliance-judge/tests/golden-results.md agents/compliance-judge.md coding-memory/branches/compliance-judge.md
git commit -m "test(compliance-judge): golden eval green (2 runs x 6 fixtures)"
```

---

### Task 4: Skill + gate stub + catalog line

**Files:**
- Create: `skills/running-the-compliance-judge/SKILL.md`
- Modify: `rules/gates.md` (insert one stub after the **Subagent-commit verification gate** bullet)
- Modify: `CLAUDE.md` (insert one catalog line after the `running-the-observability-judge` line)

**Interfaces:**
- Consumes: the agent contract (Task 1) — dispatch inputs and return shape.
- Produces: the loop/escalation procedure Task 5 rehearses; the gate wording that makes the judge un-skippable.

- [ ] **Step 1: Write `skills/running-the-compliance-judge/SKILL.md`**

````markdown
---
name: running-the-compliance-judge
description: Use when a spec/design doc is finished — after its self-review, before the user reviews it — to dispatch the compliance-judge subagent alongside the observability judge's architecting read, drive the capped auto-revise loop, and escalate persistent violations. Not for judging code diffs (see running-the-observability-judge) or reviewing PRs (see /review).
---

# Running the Compliance Judge

A rule violation caught in a spec costs a paragraph; the same violation caught after
implementation costs the implementation. This skill is the procedure the main agent follows at
spec-done: judge the spec against the live rules, silently fix what a revision can fix, and put
anything persistent in front of the user — so the user always reviews a spec that already
complies, and no violation is ever silently dropped.

## When to run
After a spec/design doc is written and self-reviewed, before the user reviews it — whatever
flow produced the spec. **Freshness:** a verdict is fresh only while its `spec_blob_sha`
matches `git hash-object <spec_path>`. Any later edit — including edits the user requests
during their review — invalidates it; re-run the loop before `superpowers:writing-plans`
proceeds.

## The loop
1. Dispatch BOTH judges in parallel, in one message: `compliance-judge` (blocking) and
   `observability-judge` with `stage: architecting` (advisory, unchanged). Give the compliance
   judge: the spec path, the round number, a short context summary of what is being built, any
   user-waived violation ids, and the base branch.
2. Verdict `pass` → proceed to the user review gate, bundling the observability advisory read
   (if that advisory run failed, say so — an advisory failure never blocks).
3. Verdict `fail` → YOU revise the spec to address each cited violation — the judge never
   edits, and you hold the brainstorm context it cannot see — then re-dispatch both judges at
   round+1 (the spec changed, so the advisory read refreshes too), passing the prior round's
   violations — the judge reuses their exact ids for recurring violations, keeping persistence
   detection sound — along with all waived ids.
4. Escalate to the user — with the judge's citation and what your revision attempted — when
   either:
   - the same violation `id` is cited in two consecutive rounds (it survived the revision that
     tried to fix it — "not being fixed" by definition), or
   - round 3 completes with any violation outstanding (the oscillation tripwire: fixing one
     violation keeps re-introducing another; the cap hands the decision to the user, it never
     drops anything).
   The user either directs a different fix (loop continues) or waives the violation; pass all
   waived ids into every subsequent dispatch so the judge records rather than re-cites them.
5. Nothing is waived silently: every waiver comes from an explicit user decision and is
   recorded and attributed in the verdict.

## Fail closed
If the compliance judge errors or returns malformed output: no verdict exists, none is
fabricated, the spec stays blocked, and the user is told. Same contract as the sibling judge.

## Calibration
Verdicts carry `outcome: null`. Once the spec's implementation lands, backfill
`clean`/`rework`/`bug` in `coding-memory/compliance-judge/verdicts.jsonl` — over time the
ledger shows whether compliance-passed specs actually implement cleanly. Golden-eval fixtures
and procedure: `tests/README.md`.

<!-- Triggers (verified before shipping):
positive: "the spec is finished, run the compliance check", "judge this spec against our rules
before I review it", "I edited the spec during review — re-run the compliance judge"
negative: "judge the implementation before the PR" (running-the-observability-judge), "review
this pull request" (/review), "verify the subagent's commit landed" (verifying-subagent-commits) -->
````

- [ ] **Step 2: Insert the gate stub into `rules/gates.md`** — add this bullet immediately after the **Subagent-commit verification gate** bullet:

````markdown
- **Spec-compliance gate:** after a spec/design doc is written and self-reviewed — and again after
  any later spec edit — run the compliance judge before the user review gate; a failing or missing
  verdict blocks `superpowers:writing-plans`. Persistent violations escalate to the user, never silently waived.
  Not hook-enforced (a `spec-guard` hook is deferred until this gate is observed being skipped).
  Procedure: `running-the-compliance-judge`.
````

- [ ] **Step 3: Insert the catalog line into `CLAUDE.md`** — add this line immediately after the `running-the-observability-judge` line in the Skills Catalog:

````markdown
- `running-the-compliance-judge` — judging a finished spec against writing-specs + core-conduct/security rules before the user reviews it: parallel dispatch with the observability judge, capped auto-revise loop, escalation, waivers.
````

- [ ] **Step 4: Structural checks**

Run:
```bash
grep -c "name: running-the-compliance-judge" skills/running-the-compliance-judge/SKILL.md
grep -c "Not for judging code diffs" skills/running-the-compliance-judge/SKILL.md
grep -c "Spec-compliance gate" rules/gates.md
grep -c "running-the-compliance-judge" CLAUDE.md
wc -l skills/running-the-compliance-judge/SKILL.md
```
Expected: `1`, `1`, `1`, `1`; line count < 90.

- [ ] **Step 5: Verify the six trigger phrases by hand** — for each phrase in the SKILL.md trigger comment, state which skill should route and confirm the descriptions distinguish them (no eval CI exists; this is the manual check the authoring standard requires). Record the six one-line judgments in `coding-memory/branches/compliance-judge.md`.

- [ ] **Step 6: Commit**

```bash
git add skills/running-the-compliance-judge/SKILL.md rules/gates.md CLAUDE.md coding-memory/branches/compliance-judge.md
git commit -m "feat(skills): running-the-compliance-judge + gate stub + catalog line"
```

---

### Task 5: Loop dry-run  *(orchestrator task — main session only)*

**Files:**
- Create: `skills/running-the-compliance-judge/tests/dry-run-log.md`

**Interfaces:**
- Consumes: the loop procedure (Task 4), the wrapper prompt (Task 2), fixtures (Task 2).
- Produces: committed evidence that fix→re-judge converges and that persistence triggers escalation.

- [ ] **Step 1: Convergence rehearsal** — copy `tests/seeded-unpinned-version.md` to `tests/out/dryrun-spec.md`. Round 1: dispatch the wrapper (spec_path pointed at the copy) → expect `fail` citing pinned versions. Revise the copy exactly as the loop's step 3 prescribes (pin `Python 3.12.3`, `pytest 8.2.0`). Round 2: re-dispatch → expect `pass`, and confirm no violation id repeats.

- [ ] **Step 2: Escalation rehearsal** — copy `tests/seeded-embedded-secret.md` to `tests/out/dryrun-esc.md`. Round 1: dispatch → expect `fail` citing secrets. Apply a deliberate NON-fix (reword the Telemetry sentence, keep the key). Round 2: re-dispatch → expect the same violation id again → per loop step 4 this is the escalation trigger. Do NOT prompt the user — record that the escalation condition fired correctly.

- [ ] **Step 3: Write `tests/dry-run-log.md`** — for each rehearsal: rounds run, verdicts, violation ids per round, and the loop decision taken (`revise` / `escalate`), ending with `Convergence: OK` and `Escalation trigger: OK` (or the failure, verbatim — a failed rehearsal is surfaced, not smoothed over).

- [ ] **Step 4: Commit**

```bash
git add skills/running-the-compliance-judge/tests/dry-run-log.md coding-memory/branches/compliance-judge.md
git commit -m "test(compliance-judge): loop dry-run — convergence + escalation evidence"
```

---

### Task 6: Memory, judge verdict, PR

**Files:**
- Modify: `CODING_MEMORY.md` (Active Session + repo section + Exact Next Steps)
- Modify: `coding-memory/pr-tracking.md` (new PR entry)
- Modify: `coding-memory/branches/compliance-judge.md` (final status)

**Interfaces:**
- Consumes: everything prior; the real `observability-judge` agent (registered).
- Produces: the merged-ready PR.

- [ ] **Step 1: Update memory** — branch log: all tasks DONE + final state. `CODING_MEMORY.md`: compliance-judge implemented, eval green, PR pending; fold the live-verify item below into Exact Next Steps. `pr-tracking.md`: repo, branch, remote, PR number/URL once created, session_origin.

- [ ] **Step 2: Add the live-verify next step** — the golden eval exercised the agent *file* via wrapper dispatches; agent *registration* (dispatch by `subagent_type: compliance-judge`) loads at session start and cannot be proven mid-session. Record in `CODING_MEMORY.md` Exact Next Steps: "Live-verify: in a FRESH session, dispatch compliance-judge by subagent type against `tests/golden-pass.md` (wrapper store-root exception does not apply — expect a verdict in `coding-memory/compliance-judge/`; delete the eval verdict after confirming)."

- [ ] **Step 3: Commit memory**

```bash
git add CODING_MEMORY.md coding-memory/pr-tracking.md coding-memory/branches/compliance-judge.md
git commit -m "docs(memory): compliance-judge implementation complete"
```

- [ ] **Step 4: Run the observability judge (implementation stage)** — dispatch `observability-judge` with `stage: implementation`, a decisions summary (separate parallel judge; live rule reads; wrapper-based golden eval, 2×6 green; procedure gate, no hook; persistence escalation + round-3 cap), the spec path, base branch `main`, no test command (evidence is `golden-results.md` + `dry-run-log.md`). Relay its layman summary to the user. This is the LAST step before the PR — any commit after it invalidates the verdict.

- [ ] **Step 5: Push and create the PR**

```bash
git push
gh pr create --title "feat: compliance judge — spec-vs-rules gate before user review" --body "<PR template per preparing-pull-requests: plain-language what/why; related PRs: #13 (observability judge); screenshots: N/A - non-UI change; testing: golden eval 2x6 green (tests/golden-results.md) + loop dry-run (tests/dry-run-log.md) + manual trigger check; change summary + risk: new agent/skill/gate-stub/catalog/store, no hooks touched, biggest risk is judge miscalibration — mitigated by the golden bar and outcome backfill.>"
```
Expected: `judge-guard.sh` allows it (fresh implementation verdict from Step 4). Save the PR number/URL into `coding-memory/pr-tracking.md` (amend the memory commit is NOT allowed post-verdict — put it in the PR-tracking update that the *next* session's merge housekeeping commits, per existing practice).

---

## Self-Review (performed at plan-writing time)

- **Spec coverage:** agent (Task 1), store + README (Task 1), fixtures/eval (Tasks 2–3), skill + gate stub + catalog (Task 4), loop + escalation evidence (Task 5), calibration/backfill + PR (Task 6). Deferred per spec: `spec-guard` hook, plan-judging, auto-backfill. The mid-session registration limit is honest-listed as a live-verify next step (Task 6 Step 2).
- **Placeholder scan:** every file has full content; the only `<...>` tokens are runtime-substituted values (dates, SHAs, PR body assembled from the named template parts).
- **Type consistency:** violation object `{id, rule_source, rule, where, why}` and the JSONL field list are identical in Task 1 (agent), Task 2 (expected table), and Task 4 (skill); store root and freshness wording match the spec.
