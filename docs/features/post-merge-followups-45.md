---
phase: implementation
model_tier: low
branch: docs/post-merge-followups-45
---

# Post-merge follow-ups for PR #45

Four record-keeping items that PR #45 (`65ebf81`, merged 2026-08-08) left behind. No behaviour
changes, no code. This card exists for one reason beyond tracking: two of the four paths are **not**
`phase-guard`-exempt, so the writes are denied until a feature file records the working branch at
`phase: implementation`. That is the mechanism the hook itself names, not a workaround.

Feature detail lives in `docs/features/memsearch-freshness.md` and ADR 0021 — nothing is restated here.

## Why a card at all

`managing-session-memory` says a one-line fix does not earn a feature file, and on its own none of
these would. But `phase-guard.sh` denies `memsearch/README.md` and root `README.md` from any branch
while an un-superseded `planning` card exists (currently `verification-marker-gate.md` and
`falsify-harness-signatures.md`, both legitimately active) and no card claims the current branch at
`implementation` — the branch-claim arm at `phase-guard.sh:387` counts `implementation` only, never
`review`. Precedent for a small card exists: `git-guard-empty-index.md`, `replay-harness-base-pin.md`,
and `stale-phase-guard-rule-text.md` are all one-fix cards.

## Constraints

- **Branch off `origin/main`, do not check out `main`** — it is held by the worktree
  `.claude/worktrees/statusline-followups` (stale at `8d79094`); `git checkout main` fails here.
- **Do not reopen `feature/memsearch-freshness`.** It is merged; its card stays at `phase: review`.
- `coding-memory/compliance-judge/*` in the working tree belongs to another session's
  `falsify-harness-signatures` work. Never `git commit -a`; scope every commit with `-- <paths>`,
  and on any rename include the **old** path in the pathspec (session 45's duplicate-ADR trap).

## Tasks

- [x] 1 — `memsearch/README.md:36`: repoint the broken ADR link. The file it names
      (`0018-launchd-agent-and-run-recency-split.md`) no longer exists; it was renumbered to
      `0021-*` in `e255b2d`. Replacement text, including the provenance clause so a reader who
      finds "ADR 0018" in the append-only archive can reconcile it:
      ``Design: `../docs/decisions/0021-launchd-agent-and-run-recency-split.md` (written as 0018; renumbered 2026-08-08 because `main` had already landed a different ADR 0018).``
- [x] 2 — Root `README.md`, under `## 🗺️ Roadmap` immediately after the `#14` line, add:
      `- [x] Scheduled index refreshes with honest staleness reporting — a launchd agent plus an eight-state session line that separates "a run happened" from "the content is current" (#42, #45)`
- [x] 3 — `coding-memory/pr-tracking.md:790,794`: PR #45 still reads **open**. Mark it merged at
      `65ebf81`, dated 2026-08-08.
- [x] 4 — `coding-memory/observability-judge/verdicts.jsonl`: backfill `outcome` on the round-5 row
      (`head_sha` `5ff613d`, ts `2026-08-08T06:43:01Z`), currently `null`. **Proposed value:
      `rework`**, not `clean` — after that verdict the branch still needed a `main` merge, an ADR
      renumber forced by a duplicate 0018, and removal of a conflict marker committed in `08b779d`.
      Vocabulary in use across 127 rows: `clean` ×34, `rework` ×16, `null` ×77 (`bug` documented,
      never used). Edit that row only; the file is append-only otherwise.

## Verification

- [x] `grep -rn "0018-launchd" .` returns only the intentional provenance mentions (ADR 0021's own
      header, this card, the feature card, `CODING_MEMORY.md`'s archive) — never a live link.
- [x] `python3 -c "import json;[json.loads(l) for l in open('coding-memory/observability-judge/verdicts.jsonl')]"`
      parses, and the row count is still 127.
