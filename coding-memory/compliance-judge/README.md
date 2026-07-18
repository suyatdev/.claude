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
