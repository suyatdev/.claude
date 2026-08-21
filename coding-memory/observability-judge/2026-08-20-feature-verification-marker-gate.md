# Observability verdict — feature/verification-marker-gate (implementation)

- **ts:** 2026-08-20T23:54:30Z
- **repo:** tracking-feature-state (worktree checkout of `~/.claude`)
- **branch:** `feature/verification-marker-gate`
- **head_sha:** `e0fd411c81a7b98cfa585abe18f1e0391cfdc813`
- **base:** `main` (merge-base `ee98bae89e7d6b4f7d5b462b337d984b11b4895c`)
- **stage:** implementation
- **risk:** low — **confidence:** high

## What was changed

A new doorman for `git commit`. Before a commit goes through, the hook asks: *"this file has a
test next to it — has that test ever actually passed against these exact bytes?"* If no, the
commit is refused. The proof is a small receipt file (a blob hash) that each test suite writes
when it finishes green. This session finished tasks 9–16: mutation floor, latency measurement,
shellcheck audit, docs, a sweep re-checking every "must/never" claim in the spec against real
code, two real bug fixes, global registration, and a fresh-clone arming check.

## Does it do what was intended?

Yes. All 15 buildable checklist items are ticked; task 16 is this verdict. Every test count in the
decisions summary reproduced exactly when I ran the suites myself.

## What could go wrong / unsure about

- Merging arms a **machine-global** hook. If `python3` disappears from PATH, *every* commit in
  *every* repo on this machine is blocked (`MSG_NO_PYTHON`, no bypass). If
  `hooks/lib/decide-commit-gate.py` becomes unreadable, every commit in this repo is blocked
  (`MSG_CLASSIFIER_MISSING`) — `TEST_EXEMPT=...` is the escape hatch, but only if the user
  remembers it exists. Both are deliberate fail-closed choices and documented.
- `rules/gates.md` gained the **longest bullet in the file** (1608 chars vs. the previous max
  1242); the file grew 1507 → 1747 words (+16%) and it loads on every turn.
- Two of four latency budgets were **revised upward to fit the measurement** rather than the code
  changed. Both misses are decomposed and explained (a bash prologue that runs before the
  pre-filter; a heavier second interpreter start), so this reads as honest re-baselining, not
  goalpost-moving — but it is still budget-follows-reality.
- v1 ships no `--status`. A silent allow is indistinguishable from an inert gate; the only proofs
  are the one-off arming run and a non-empty `hooks/state/test-marker.log`. Accepted in the spec.

## Evidence I ran myself

| suite | result |
|---|---|
| `bash hooks/test-marker-guard.test.sh` | 246 passed, 0 failed |
| `python3 hooks/lib/classify-git-command.test.py` | 114 passed, 0 failed |
| `python3 hooks/lib/shell_segments.test.py` | 35 passed, 0 failed |
| `python3 hooks/lib/classify-pr-command.test.py` | 59 passed, 0 failed |
| `python3 hooks/lib/classify-commit-command.test.py` | 52 passed, 0 failed |
| `python3 hooks/lib/write-test-marker.test.py` | 59 passed, 0 failed |
| `shellcheck -x hooks/test-marker-guard.sh` | clean apart from accepted SC2174 |

**Anti-success-masking checks (my own mutations, both reverted, tree clean after):**

1. Removed `-I` from the inline `cwd` read (`test-marker-guard.sh:59`) → **244 passed, 2 failed**.
2. Reverted the kind dispatch to `if result.kind != "COMMIT":` (`decide-commit-gate.py:298`) →
   **244 passed, 2 failed**.

Both of this session's claimed bug fixes are genuinely pinned by tests that can fail. The green
suite is not hiding them.

## Dimensions

| dimension | verdict | note |
|---|---|---|
| intent | pass | tasks 9–15 delivered as scoped; registration matches sibling guards' shape |
| execution | pass | all six suites run by me, counts match the claim exactly; shellcheck clean |
| trajectory | pass | bugs reproduced before fixing, red-then-green, fixes re-verified in both directions; task 14 deliberately run against a fresh clone |
| regression | pass | adjacent guard suites green; `settings.json` adds one array entry, structure preserved; markers are gitignored, nothing sensitive committed |
| context_budget | concern | longest bullet in always-on `rules/gates.md`; file +240 words (+16%) |
| traceability | pass | two ADRs, a 2940-line canonical feature file, per-task ✅ evidence with measured numbers |
| success_masking | pass | independently mutation-verified above; latency budget revisions are disclosed, not buried |
| intent_drift | pass | large diff is a full 16-task feature plus main merges; the deleted `docs/marker-gate-defect-checklist.md` is consolidation into the canonical file, not a drive-by; no new deps |
| checkpoint | pass | clean per-task commits, parallel work merged serially, revert point per task |
| audit_trail | pass | subagent SHAs independently re-verified; ADR 0026/0027 cover the structural decisions |

## Concerns

- `rules/gates.md` bullet is the largest in an always-on file (+16% file growth)
- merging arms a machine-global fail-closed hook; `MSG_NO_PYTHON` blocks non-adopting repos too
- no `--status`: an allowed commit cannot be distinguished from an inert gate (accepted in v1)
- two latency budgets revised upward to match measurement; ~7 ms now paid by every Bash call
