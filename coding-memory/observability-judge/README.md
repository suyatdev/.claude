# Observability Judge — verdict store

Written by the `observability-judge` agent. Global store (like the rest of `coding-memory/`);
verdicts are keyed by `repo` + `branch` + `head_sha`, so entries stay correct across repos.

## `verdicts.jsonl` — one JSON object per line

| field | type | notes |
|-------|------|-------|
| `ts` | string | UTC, `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `repo` | string | `basename` of the git top-level |
| `branch` | string | current branch |
| `head_sha` | string | **full** `git rev-parse HEAD` |
| `stage` | string | `architecting` (advisory) or `implementation` (gating) |
| `dimensions` | object | each of the 10 rubric keys → `pass` / `concern` / `fail` |
| `risk` | string | `low` / `medium` / `high` |
| `confidence` | string | `low` / `medium` / `high` |
| `concerns` | string[] | short concern strings |
| `outcome` | string\|null | backfilled later: `clean` / `rework` / `bug` |

Dimension keys: `intent`, `execution`, `trajectory`, `regression`, `context_budget`,
`traceability`, `success_masking`, `intent_drift`, `checkpoint`, `audit_trail`.

## `YYYY-MM-DD-<branch>.md` — human writeup
The four layman sections (what changed / does it do what you wanted / what could go wrong /
what I'd double-check), plus the dimension table and concern list.

## Calibration
`outcome` starts `null`. Backfill it when a PR's real result is known. Aggregating the JSONL by
`risk` vs `outcome` shows where the judge is mis-calibrated (e.g. `risk: low` clustering with
`outcome: bug` → thresholds too loose). Only the `implementation` stage gates a PR.
