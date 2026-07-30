# Observability Judge Verdict — RUN 11 (implementation)

- **Date:** 2026-07-29 (ts 2026-07-29T23:20:02Z)
- **Repo:** phase-guard-hook (worktree `/Users/marksuyat/.claude/.claude/worktrees/phase-guard-hook`)
- **Branch:** `feature/phase-guard-hook`
- **HEAD:** `218118b03c6ce0e6558025f29f647b700322dfa8` (clean, pushed)
- **Base:** `main`, merge-base `8f0f16dc33d23ef07bd8cf75951df88223ba0e35`
- **Stage:** implementation (gates the PR)
- **Delta judged:** `31ebca7..218118b` — `78e542b` (memory, docs only), `a00fd3e` (doc + one
  comment line, no behavioural change), `218118b` (memory, docs only). Full branch context
  re-verified against `main...HEAD`.

## What was changed (plain English)

RUN 10 gave this branch its first low-risk verdict but left two paperwork defects: one sentence
in the design doc still described the malformed-payload exit as *silent* (the code, the audit
table, and the tests all had it *speaking* — once per session, only when the session's cwd is an
opted-in repo), and a code comment listed only 2 of the 9 warning reasons as if that were the
whole set. This delta fixes exactly those two things and nothing else, bracketed by two memory
checkpoints. Think of it as correcting the last two wrong lines in the instruction manual so the
manual, the machine, and the test bench all say the same thing.

## Does it do what you wanted?

Yes — verified independently at this HEAD, not taken on faith:

- Suite **130 passed / 0 failed** (my run). `shellcheck -x hooks/phase-guard.sh` **clean** (my run).
- The rewritten step-3 item (doc :220–:230) now matches the shipped behaviour at
  `phase-guard.sh:189` (`warn_if_cwd_opted_in nopayload "$NOPAYLOAD_MSG"`), which sits under the
  code's `# --- Step 3 ---` header (:155–:191) — the doc's step placement is correct. Tests
  A1.4/A1.5 pin the audible behaviour (`allow_audible … "$OPTED"`), converted from
  asserted-silent by the fail-open audit, exactly as the new sentence says.
- The `warn_once` comment (:109) no longer enumerates reasons; it points to the call sites, which
  is where tripwire D3 derives the set — closing the "enumeration lags the audit" class at the
  one comment surface Group D could not see. The Flag contract row (doc :490) remains the single
  enumerated list, and D3 keeps it honest.
- The hook diff since RUN 10 is **one comment line** — no behavioural change, so RUN 10's
  red-first reproduction and all four Group D mutation checks remain valid for this code.
- The doc carries a correction note preserving the drift history (round 4 asserted silent →
  round 9 fixed the `noparse` twin → round 10 caught this one) instead of silently rewriting it.

## What could go wrong / honest concerns

- **Structural, disclosed, unchanged:** Group D's tripwires are grep-scoped — they catch wrong
  step counts, wrong names, and dropped reasons, but not a wrong *sentence*. Semantic prose drift
  in a 1,766-line doc stays green; D3 fails open if reason extraction ever misses a call-site
  form. The last three rounds each found exactly this class. Nothing at this HEAD is known to be
  wrong, but the blindness persists by construction.
- **Adjacent blocker, out of scope, carried not rediscovered:** `hooks/judge-guard.sh` resolves
  identity from cwd and reads the primary checkout's `verdicts.jsonl`; this verdict lands in the
  worktree's ledger, so `gh pr create` from this worktree may still fail closed regardless of
  this verdict. Parked on `fix/judge-guard-verdict-lookup`; RUN 10 memory records the decided
  route (`JUDGE_VERDICTS_FILE` at the worktree ledger, not `JUDGE_EXEMPT`).
- **Owed to the PR body:** supersession reads `refs/heads/` only — a remote-only implementation
  branch does NOT supersede a planning file; and out-of-repo writes cost one `dirname` fork per
  path level. Both doc-disclosed; both must reach the PR description.

## What I'd double-check before merging

1. The PR body actually states the two owed disclosures above (remote-only supersession gap,
   per-level dirname cost).
2. The `gh pr create` path from this worktree — resolve the judge-guard ledger route
   (`JUDGE_VERDICTS_FILE`) before or alongside opening the PR, not by `JUDGE_EXEMPT`.
3. That no further doc edits land after this verdict without re-running the judge — the guard is
   strict on HEAD, and prose fixes have been this branch's recurring drift source.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Delta is exactly RUN 10's two residual items; nothing else moved |
| execution | pass | 130/0 and shellcheck clean, both re-run by me at this HEAD |
| trajectory | pass | Root-cause fix (de-enumerate, point at derived truth) over re-enumeration; history preserved in a correction note |
| regression | pass | Hook diff = one comment line; Group D all green; D3 derivation unaffected |
| context_budget | pass | Hook + doc, not always-on context; +5 net doc lines; standard memory checkpoints |
| traceability | pass | Step-3 item ↔ code :189 ↔ audit `nopayload` row ↔ Flag contract :490 ↔ A1.4/A1.5 now all agree; RUN 10's full step-ref sweep stands (only this sentence changed since) |
| success_masking | concern | Standing disclosed class: grep tripwires can't see wrong sentences; D3 fails open on extraction misses; 130 green tests are structurally blind to prose drift |
| intent_drift | pass | No drive-bys, no dependency changes, scope pinned to the flagged items |
| checkpoint | pass | Clean, pushed, one concern per commit, memory checkpoints bracket the fix — clean revert points |
| audit_trail | pass | Attributable commits with rationale; correction note names the rounds; continuous verdict ledger; ADR 0011 covers the design |

## Roll-up

- **Risk:** low
- **Confidence:** high

## Concerns

1. Group D limit unchanged and disclosed: grep-scoped tripwires catch wrong counts/names, not
   wrong sentences; D3 fails open on extraction misses — semantic prose drift stays green.
2. Adjacent blocker carried, out of scope: judge-guard reads the primary checkout's
   verdicts.jsonl from cwd identity; this verdict is in the worktree ledger — resolve via
   `JUDGE_VERDICTS_FILE` (parked branch `fix/judge-guard-verdict-lookup`), not `JUDGE_EXEMPT`.
3. Owed to the PR body: refs/heads/-only supersession (remote-only branch does not supersede) and
   per-level dirname cost on out-of-repo writes.
4. Verified by me at this HEAD: suite 130/0, shellcheck -x clean, hook diff since RUN 10 is one
   comment line, step-3 sentence matches code/tests/contract; RUN 10's behavioural evidence
   (red-first 128/2, four mutations each 129/1) remains valid because the hook is byte-identical
   but for that comment.
