# Branch Implementation Log: feature/observability-judge

**Status:** MERGED (PR #13, 2026-07-17, merge commit 82d7b9b, branch `feature/observability-judge`
from `main`). Tree clean. Hook suite 17/17. Judge + gate now live and global.

## Why

User wanted three things running on every change: **evaluations**, **observability**, and an
**observability judge** that ties them together — plus a junior-dev layman explanation after each
architecting/implementation before a PR, stored for later margin-of-error calibration. Prior state:
`.claude` carried evaluation guidance (`evaluating-agents-and-skills`) and observability guidance
(`securing-agentic-systems` Pillar 7) but neither ran during real work, and there was no judge.
Routed through `triaging-new-instructions` → judge = subagent, "run it" = gate stub + skill,
"before a PR" enforcement = hook, storage = reference convention.

## Key decisions (locked with the user)

- **Dev-time scope, not live traces.** No runtime trace instrumentation exists, so the judge scores
  the *development trajectory* of a change (design + diff + decisions + test evidence), never a live
  production trace. This honesty caveat is threaded through every artifact.
- **Hook-blocked enforcement** with **strict freshness**: a verdict counts only if `stage=="implementation"`
  and `repo`+`branch`+full `head_sha` all match the current checkout.
- **Storage:** JSONL (calibration) + dated markdown (human), under `coding-memory/observability-judge/`,
  with an `outcome` field backfilled later (clean/rework/bug) to find where the judge is mis-calibrated.

## What was built

- `agents/observability-judge.md` — subagent scoring 10 dimensions (5 evaluation + 5 observability),
  writes verdict, returns 4-section layman summary. Write-scoped to the verdict store.
- `hooks/judge-guard.sh` + `hooks/judge-guard.test.sh` (17 stdin-driven cases) + `settings.json` wiring —
  Tier-1 PreToolUse hook blocking `gh pr create` until a fresh verdict matches HEAD; classification via
  python `shlex`; `JUDGE_EXEMPT=<reason>` escape hatch; fails closed.
- `skills/running-the-observability-judge/SKILL.md` — when/how the main agent invokes the judge.
- `rules/gates.md` gate stub + `CLAUDE.md` catalog line.
- `docs/decisions/0001-observability-judge.md` (ADR) + `coding-memory/observability-judge/README.md`
  (schema) + two dogfood verdicts in the store.

## Review history worth remembering

- **Hook command-detection took two review-driven security fixes.** (1) The initial substring regex
  matched the phrase *anywhere* — it blocked its own commit and live diagnostics; anchored it (user
  chose anchor-like-git-guard). (2) The anchored bash regex still couldn't parse shell quoting, so a
  quoted-space env prefix (`FOO="a b" gh pr create`) *silently bypassed* the gate — moved classification
  to python `shlex`. Each fix landed test-first with RED/GREEN.
- **Final whole-branch review (Opus)** caught 2 Important issues the per-task reviews missed: the verdict
  markdown filename broke on slashed branch names (`feature/` → stray subdir / collisions) — now sanitizes
  `/`→`-`; and `hooks/README.md` still falsely claimed only `git-guard` was installed — corrected to name
  all three installed hooks. Both fixed + verified.
- Judge dogfooded itself twice (partial branch: risk=low conf=medium; complete: risk=low conf=high);
  trigger routing verified 6/6.

## Bootstrap gotcha (the judge gating its own repo)

Because the verdict store lives **in this repo**, committing a verdict re-stales its `head_sha` vs the
tip — so this branch trips its own gate. Unique to developing the judge inside its own store; judging
*other* repos has no such circularity (store is in `~/.claude`, separate from the PR'd repo). This
bootstrap PR is opened with `JUDGE_EXEMPT=<reason>`.

## Follow-ups (non-blocking)

- `hooks/README.md` has no dedicated `doc-guard.sh` section (pre-existing gap, predates this branch).
- Accepted momentum-guardrail gaps (same as git-guard's `^git`): chained `foo && gh pr create` and
  `;`-separated forms aren't caught; shlex-unparseable commands fail open. Documented in the hook.
- Agent write-scope + Bash access are enforced by instruction only (fine for a single-user dev tool).
- `outcome` backfill is manual for now; an automated `/judge-outcome` helper is future work (per ADR).
