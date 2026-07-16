# Observability Judge — Design

**Date:** 2026-07-16
**Status:** Approved (design). Awaiting spec review before implementation planning.
**Branch:** `feature/observability-judge`

## Problem

The `.claude` config carries *guidance* for evaluations (`evaluating-agents-and-skills`)
and for agent observability (`securing-agentic-systems`, Pillar 7), but neither runs
during real work. There is no agent that applies those rubrics to a change, no plain-
language readout of the result, and no accumulated record to calibrate against. The user
wants all three — evaluation lens, observability lens, and a judge that ties them together —
to run automatically when changes are made, to explain itself in junior-developer terms
before a PR is opened, and to persist verdicts so the margin of error can be tuned over time.

## Scope and honesty caveat

There is **no runtime trace instrumentation** in this environment (the `evaluating-agents-and-skills`
skill says so explicitly, and it must stay honest about it). This judge therefore evaluates the
**development trajectory of a change** — its design, its diff, the decisions taken to produce it,
and its test evidence — **not** a live production "vibe trajectory." That is real and useful, but it
is dev-time reflection, and every artifact must say so rather than imply live observability exists.
Ingesting real OpenTelemetry traces later is an explicit non-goal of this design (see Future work).

## Decisions (locked)

1. **Enforcement:** hook-blocked. A PreToolUse hook blocks `gh pr create` until a fresh verdict
   exists for the exact commit being PR'd. Matches the `git-guard` / `doc-guard` philosophy:
   an instruction degrades under long sessions; a hook is code that runs every time.
2. **Scope:** dev trajectory now (design + diff + decisions + test evidence). No live traces.
3. **Storage:** JSONL (machine-readable, for aggregate calibration) **plus** a dated markdown
   writeup per verdict (human-readable).
4. **Freshness:** strict. A verdict is fresh only if `repo` and `branch` match **and**
   `head_sha == current HEAD`. Any commit added after judging invalidates the verdict and
   requires a re-run — so the gate always judges exactly what will ship.

## Components

| File | Type | Responsibility |
|------|------|----------------|
| `agents/observability-judge.md` | Subagent | Scores a change against both rubrics, writes the verdict (JSONL + markdown), returns the layman summary. |
| `skills/running-the-observability-judge/SKILL.md` | Skill | The procedure the main agent follows: when to invoke the judge, what context to feed it, how to relay its result. |
| `rules/gates.md` (new stub) | Gate | 1–2 lines making the judge un-skippable, pointing at the skill. |
| `hooks/judge-guard.sh` | Hook (Tier 1) | Blocks `gh pr create` unless a fresh implementation-stage verdict exists for HEAD. Fails closed; honors an explicit exempt hatch. |

Storage root: `coding-memory/observability-judge/` (global, like the rest of `coding-memory/`).
Because verdicts are keyed by `repo` + `branch` + `head_sha`, they are correct even though the
store is shared across every project the user works in.

## Rubrics (what the judge scores)

Each dimension is scored **pass / concern / fail**, then rolled into an overall **risk**
(low / medium / high) and the judge's **confidence** (low / medium / high).

**Rubric A — Evaluation** (from `evaluating-agents-and-skills`):
- **Intent satisfaction** — did it build what was *meant*, not merely what was literally said.
- **Execution correctness** — does it actually work; are there tests, do they pass.
- **Trajectory quality** — sound reasoning vs. a right answer reached by luck or bad sequence.
- **Regression risk** — did it break, or plausibly break, adjacent behavior.
- **Context-budget health** — for rule/skill/prompt changes: does it bloat always-on context.

**Rubric B — Observability & Governance** (from `securing-agentic-systems`, Pillar 7):
- **Traceability** — can "why did it do that?" be answered; is the change explained/documented.
- **Success-masking risk** — could a green test hide a real problem; any unbounded or expensive
  loop (the Denial-of-Wallet analog) introduced.
- **Intent drift** — scope creep, drive-by edits, unauthorized dependency changes.
- **Checkpoint / rollback** — is there a clean revert point; was checkpoint-before-modify honored.
- **Audit-trail attribution** — is the change attributable and documented; is it ADR-worthy.

## What the judge reads

The judge is a **stateless subagent** — it cannot see the main agent's session, so the main agent
feeds it the trajectory. Inputs:
- **Diff:** `git diff $(git merge-base <default-branch> HEAD)..HEAD` for the implementation
  (gating) stage, where `<default-branch>` is the repo's default branch (here `main`);
  the design doc for the architecting (advisory) stage.
- **Decisions summary:** a short block the main agent writes into the invocation prompt, describing
  the key choices and why (this *is* the trajectory the judge scores).
- **Design/spec doc:** path passed in when one exists.
- **Test evidence:** the judge **re-runs the test command itself** for independent verification
  rather than trusting a pasted result.

Judge tool access: `Read, Grep, Glob, Bash, Write`. Bash is for `git`/tests and read-only inspection;
Write is restricted **by instruction** to `coding-memory/observability-judge/` only.

## Trigger points

- **After architecting** (a spec/design is produced): advisory verdict on the *design*. Surfaced to
  the user, **not** gated.
- **After implementing** (change committed on the feature branch): the **gating** verdict on the
  *diff*. This is the verdict `judge-guard.sh` requires before a PR.

The skill instructs the main agent to run the gating verdict **as the last step before opening a PR**,
so HEAD does not move afterward (which would invalidate it under strict freshness).

## Junior-developer layman report

After every run the main agent relays a short, jargon-free writeup (analogies over jargon,
a few sentences per part):
- **What I changed** — plain English.
- **Does it do what you wanted?**
- **What could go wrong / what I'm unsure about** — the concerns, honestly.
- **What I'd double-check before merging.**

The full scored verdict goes to the log; the user sees the human version.

## Storage schema

**`coding-memory/observability-judge/verdicts.jsonl`** — one JSON object per line:

```json
{
  "ts": "2026-07-16T00:00:00Z",
  "repo": "dotclaude",
  "branch": "feature/observability-judge",
  "head_sha": "abc1234",
  "stage": "implementation",
  "dimensions": {
    "intent": "pass", "execution": "pass", "trajectory": "concern",
    "regression": "pass", "context_budget": "pass",
    "traceability": "pass", "success_masking": "pass",
    "intent_drift": "pass", "checkpoint": "pass", "audit_trail": "pass"
  },
  "risk": "low",
  "confidence": "medium",
  "concerns": ["short strings"],
  "outcome": null
}
```

`ts` is stamped by the judge via `date -u`. `repo` is the git top-level basename.
`stage` is `architecting` or `implementation`.

**`coding-memory/observability-judge/YYYY-MM-DD-<branch>.md`** — the human writeup: the four
layman sections above, plus the dimension table and the concern list.

## Calibration loop (the "margin of error" mechanism)

`outcome` starts `null`. When a PR's real result is known it is backfilled with one of
`clean` (merged, no rework, no post-merge bug), `rework` (needed changes before merge), or
`bug` (defect slipped past the judge). Aggregating `verdicts.jsonl` then answers: **where is the
judge mis-calibrated?** — e.g. a cluster of `risk: low` entries with `outcome: bug` means the
judge is over-confident and its thresholds need tightening. Backfilling `outcome` is manual for
now (edit the JSONL line); a `/judge-outcome` helper is deferred to Future work.

## Freshness model (strict)

`judge-guard.sh`, on an intercepted `gh pr create`, computes the current `repo`, `branch`, and
`head_sha`, then scans `verdicts.jsonl` for an entry with `stage == "implementation"` matching all
three. Match → allow. No match → block. Adding any commit after the verdict moves `head_sha` and
forces a re-run, so the gate always reflects exactly what is being PR'd.

## Hook behavior — `judge-guard.sh`

- **Fires:** PreToolUse on `Bash`, when `tool_input.command` contains a `gh pr create` invocation.
  Parsing of the PreToolUse JSON uses `python3` (consistent with the existing scanners), not `sed`.
- **Passes (exit 0):** any command that is not `gh pr create`; or a matching command with a fresh
  verdict; or a command carrying the exempt hatch.
- **Blocks (non-zero, per hook contract):** `gh pr create` with no fresh verdict. The message names
  the reason and tells the agent to run the observability judge, then retry.
- **Fails closed:** missing/unreadable `verdicts.jsonl`, unparseable entries, or an indeterminate
  repo/branch → block. A safety gate that cannot verify must not allow.
- **Exempt hatch:** `JUDGE_EXEMPT=<reason> gh pr create …` (mirrors `doc-guard`'s `Doc-Exempt:`).
  The reason is logged. Empty/missing reason does not exempt.
- **Not global-silent:** the hook is wired into `~/.claude/settings.json` (user scope) like the
  others, so it applies across repos; the exempt hatch is the per-PR escape.

## Error handling

- If the judge subagent errors or returns malformed output, the main agent **writes no verdict** and
  **fabricates none** — it reports the failure to the user. With no verdict, the hook blocks the PR.
  Fail-closed end to end.
- The judge writes the JSONL line and markdown file atomically enough for a single-writer personal
  workflow (append the JSONL line last, after the markdown is written).

## Testing

- `judge-guard.sh` is unit-tested by feeding **real PreToolUse JSON on stdin** (the code path that
  actually runs — per the hooks README's caught-defect lesson), covering: non-`gh` command passes;
  `gh pr create` with a fresh matching verdict passes; stale `head_sha` blocks; wrong branch blocks;
  missing `verdicts.jsonl` blocks (fail-closed); `JUDGE_EXEMPT` with a reason passes; empty
  `JUDGE_EXEMPT` blocks.
- The judge agent + skill are validated by a dry run on a sample diff, confirming a well-formed JSONL
  line, a readable markdown writeup, and a returned layman summary.

## Out of scope / future work

- **Live trace ingestion** (OpenTelemetry "vibe trajectory") — deliberately excluded; would require
  instrumentation that does not exist. The schema does not pretend to hold it.
- **`/judge-outcome` helper** to backfill `outcome` — deferred; manual JSONL edit for now.
- **Automatic outcome detection** (watching PR merges/reverts) — deferred.

## File manifest

- `agents/observability-judge.md` (new)
- `skills/running-the-observability-judge/SKILL.md` (new)
- `hooks/judge-guard.sh` (new) + wiring into `settings.json`
- `rules/gates.md` (one new stub line)
- `CLAUDE.md` Skills Catalog (one new line)
- `coding-memory/observability-judge/` (new dir; `verdicts.jsonl` created on first verdict)
- Hook test fixtures alongside the other hook tests
