# Branch Implementation Log: feature/documentation-enforcement

**Status:** PR #10 OPEN (2026-07-16, branch `feature/documentation-enforcement` from `main`). Awaiting review/merge.

## Why

An audit of how the four active projects (`.claude`, mtg-wizard, vibe-scape,
Snatch-Bracket) document decisions found the *content* is strong — business-logic
and direction-pivoting decisions, with reasoning and user attribution, are
captured — but two gaps:

1. Capture depends on checkpoint discipline, which has slipped once (the 2026-07-15
   `/clear`-before-save reconciliation, where a session's decisions were orphaned
   uncommitted and had to be reconstructed).
2. The durable ADR pattern is uneven: Snatch-Bracket has `docs/decisions/` (11
   ADRs); vibe-scape has none, so its direction decisions live inside the trimmable
   `CODING_MEMORY.md` index.

User asked to (1) broaden the mandatory-documentation criteria beyond "major
architectural changes" to also cover business-logic and direction-pivoting changes,
and (2) guarantee these don't slip. Classified via `triaging-new-instructions`.

## What changed (this repo)

- **`hooks/doc-guard.sh`** (new, Tier 1, sibling to git-guard.sh):
  - *PreToolUse block-at-commit:* a `git commit` making a SUBSTANTIAL source change
    (≥3 files or ≥20 changed lines) with no staged doc (`CODING_MEMORY.md`,
    `coding-memory/`, `docs/`) is blocked. `Doc-Exempt: <reason>` trailer bypasses;
    trivial commits pass (keeps SDD's many small commits unblocked). Size thresholds
    are named constants at the top of the script.
  - *PreCompact:* injects a warning to save before compaction eats unsaved state.
  - *SessionStart:* surfaces uncommitted tracked changes into the next session — the
    reliable catch for the `/clear` slip, since `/clear` itself is non-blockable by
    any hook (confirmed via claude-code-guide against the Claude Code hooks docs:
    SessionEnd fires *after* the clear).
  - Fails OPEN (missing python / non-git cwd / unparseable payload → exit 0): a
    momentum guardrail, not a security boundary (contrast git-guard, which fails
    closed).
  - Registered in `settings.json` under PreToolUse.Bash, SessionStart, PreCompact.
  - Verified with a 15-case harness: block/allow thresholds, doc ride-along,
    Doc-Exempt bypass, rtk prefix, `commit -a` HEAD-diff path, advisory JSON shape,
    clean-tree silence. All green.
- **`skills/managing-session-memory`**: broadened event-based-save triggers to name
  three mandatory classes — (a) architectural, (b) business-logic, (c)
  direction-pivoting — and added a Durable Decision Records (ADR) bullet.
- **`skills/setting-up-a-new-project`**: step 4 now scaffolds `docs/decisions/` +
  the ADR template as part of recording the register.
- **`skills/setting-up-a-new-project/assets/adr-template.md`** (new): ADR format
  modeled on Snatch-Bracket's (status/decider, context+options+sources, decision
  with rejected alternatives, consequences).
- **`rules/gates.md`**: added the Documentation-checkpoint-safety stub.

## Design decisions worth remembering

- A hook can enforce only the MECHANICAL proxy (source changed without a doc
  change), never the SEMANTIC "was the reasoning actually written down." The
  guarantee is a triangle — broadened criteria (skill) + durable ADR home +
  mechanical backstop — and is not oversold as semantic enforcement.
- Block-at-commit is scoped by a size threshold so only substantial commits block:
  matches the user's chosen "occasional false-positive" tolerance and does not
  hostage SDD's small intermediate commits. Tunable via the two constants.
- `/clear` is non-blockable → SessionStart injection in the *next* session is the
  catch, not a (impossible) pre-clear block.

## Follow-ups

- **vibe-scape ADR backfill** (separate repo/branch, user-approved backfill-now):
  monolith-extension architecture, positive-only token/vote economy, public-opt-in
  privacy model — sourced from its existing `CODING_MEMORY.md`.
- **Live-verify** SessionStart/PreCompact injection fires end-to-end (script logic
  is tested; the event wiring needs a real `/clear` + `/compact` to confirm).
