# Observability Judge — RUN 10 (implementation)

- **Repo:** phase-guard-hook (worktree `/Users/marksuyat/.claude/.claude/worktrees/phase-guard-hook`)
- **Branch:** `feature/phase-guard-hook` · **HEAD:** `31ebca7488776e7d964271c7f24ac4f9b7451b52` · clean, pushed
- **Base:** `main`, merge-base `8f0f16d` · **Stage:** implementation (gates the PR)
- **Date:** 2026-07-29 · **Judge round:** 10 (delta since RUN 9 @ `33bc6ae`)

## What was changed

RUN 9 found no behavioural defect — every finding was in the explanatory record (the feature doc
describing the hook), and it was the fourth consecutive round where 126+ green tests coexisted
with a stale record. This round's answer: instead of hand-patching the record a fifth time, the
suite was taught to **read the document**.

- `1b79e2a` (test-only, red-first) — **Group D**, four doc↔code drift tripwires: D1 step
  count/order (doc list vs the code's `# --- Step N ---` headers), D2 one keyword per step per
  side, D3 the Flag contract's reason set derived from the `warn_once` call sites, D4 the Output
  contract's audible counts computed rather than asserted.
- `8390a52` (record fix) — the three undercounting contract statements corrected with derived
  numbers (11 audible rows / 9 reasons), the Flag contract's Path row now names all nine reasons
  and quotes `${HOME:-}` as shipped, the three stale step refs (`:426` 5→4, `:449` 3→4, `:1015`
  4→3) fixed, and A5.6's comment answers RUN 8's `:976` on the reasoning axis (old sentence kept,
  marked pre-`508c55b`). Test-file changes in this commit are comment-only — no assertion was
  edited while going green.
- `95fffa1`/`71d8284`/`31ebca7` — memory/verdict bookkeeping only (71d8284 corrects a
  misstatement in 95fffa1 — self-caught, in-branch).

No line of `hooks/phase-guard.sh` changed since RUN 9. Behavioural surface identical.

## Evidence (all run by me at HEAD `31ebca7`)

| Check | Result |
|---|---|
| `bash hooks/phase-guard.test.sh` | **130 passed, 0 failed** |
| `shellcheck -x hooks/phase-guard.sh` | clean |
| Red-first claim (temp worktree at `1b79e2a`) | **verified**: 128/2, failing exactly D3 (7 of 9 reasons missing) and D4 (0 phrase hits) — precisely RUN 9's two contract findings; D1/D2 green there, as claimed |
| Mutation M1 — stale count ("11"→"10" in doc) | D4 alone fails, 129/1 |
| Mutation M2 — renumbered doc item (5→6) | D1 alone fails, 129/1 |
| Mutation M3 — reworded code step header (step 6 "guarded"→"handled") | D2 alone fails, 129/1 |
| Mutation M4 — dropped reason (`nolist` removed from Path row) | D3 alone fails, 129/1 |
| D3 extraction vs code | call-site grep yields exactly the 9 shipped reasons (`nogitbin nopython nopayload noresolve noreporead nolist noparse nogit detached`); no call site passes a variable; comment lines excluded |
| D4 anchor | "Why it must speak" occurs once in the doc (`:337`); table has 11 rows, matching the derived sentence |
| RUN 9's three stale step refs | fixed as claimed (`:424`, `:447`, `:1015` at HEAD) |
| Full step-ref sweep (doc 58 hits, suite 36, hook 27) | all consistent with the shipped numbering or explicitly marked historical/pre-`508c55b` — **except the one residual below** |
| `${HOME:-}` doc claim | matches `phase-guard.sh:62` |

## Does it do what you wanted?

Yes. All four items RUN 9 was owed have landed, exactly as owed, and the trajectory is the right
one: the recurring failure ("the record rots while tests stay green") got a *mechanical* answer,
not another round of care. Red-first discipline was real (independently reproduced), the
mutation-verification claim was real (independently reproduced, each tripwire fails only its own
test), and the fix commit touched no test assertion. The previously undisclosed boundaries
(remote-only supersession; per-level `dirname` cost on out-of-repo writes) are now disclosed in
the doc's round-9 section and owed to the PR body.

## What could go wrong / honest concerns

1. **One residual record defect of exactly the class the tripwires can't see** (semantic prose,
   not numbering/counts): the canonical Order-of-operations step 3 item still says
   malformed-but-non-empty stdin exits "**silently**" and "stays **silent**, unlike step 2's
   exits" (doc `:223`, `:227`) — but the shipped exit is *conditionally audible* via
   `warn_if_cwd_opted_in nopayload` (`phase-guard.sh:189`), the audit table's own row says it
   "must speak" (pinned by A1.4/A1.5), and A1.4/A1.5 assert "says so". Same class RUN 9's fix
   corrected at `:294` for `noparse`; this instance survived. 130 green tests sit on top of it.
2. **`warn_once`'s signature comment** (`phase-guard.sh:109`) still reads `# $1 reason
   (nopython|noparse)` as if exhaustive — 2 of 9 reasons. Code-comment surface Group D does not
   cover; same rot class, trivial fix.
3. **Tripwire scope is deliberately narrow** (and honestly labelled so in the test comments):
   grep checks over the surfaces that demonstrably rotted. Semantic drift stays green (see #1).
   D3 fails open for extraction misses — a future reason passed via variable or containing a
   non-`[a-z]` character would silently drop out of the derived set rather than fail. Acceptable
   as designed; worth knowing.
4. **Owed to the PR body** (now doc-disclosed, must actually appear there): supersession reads
   `refs/heads/` only — a gate opened on a remote-only branch does not supersede; and the
   per-level `dirname` cost on writes landing outside any repo, which no recorded figure covers.
5. **Adjacent blocker, unchanged and out of scope** (parked branch
   `fix/judge-guard-verdict-lookup`): `judge-guard.sh` resolves identity from cwd and reads the
   primary checkout's `verdicts.jsonl` — this verdict lands in the *worktree's* ledger, so
   `gh pr create` from this worktree may still fail closed until that fix merges. Not a defect of
   this diff; operational note only.
6. Standing, previously verified, unchanged: branch-granularity hole; stale-card lockout of
   `main`/hotfix branches until merge; rollback path 3 (exit 126) deliberately unverified;
   parallel-worktree collision user-owned; hook registered but not armed until merge.

## What I'd double-check before merging

- Fix the two residuals (#1 doc `:223`/`:227`, #2 `phase-guard.sh:109` comment) — both are
  five-minute edits, and #1 sits in the doc's *normative* list, the exact surface a reader
  navigates by.
- The PR body carries the remote-only-supersession boundary and the out-of-repo `dirname` cost
  (concern #4) — the doc discloses them now; the PR must too.
- The `judge-guard` ledger-location mismatch (#5) before attempting `gh pr create` from this
  worktree.

## Dimension table

| Dimension | Score | Note |
|---|---|---|
| intent | pass | The four owed items landed exactly as owed; the branch matches its design |
| execution | pass | 130/0 + shellcheck clean, run by me; red-first and mutations independently reproduced |
| trajectory | pass | Structural fix for a recurring failure instead of a fifth care-pass; test/fix commits properly split |
| regression | pass | Zero behavioural-surface change since RUN 9; delta is tests/docs/memory |
| context_budget | pass | Nothing always-on grows; gates stub unchanged this delta |
| traceability | **concern** | Residual: doc `:223`/`:227` contradicts the audit table's `nopayload` row; `phase-guard.sh:109` comment stale |
| success_masking | **concern** | 130 green over one live semantic-drift instance; tripwires are honest about this limit, but the limit is real |
| intent_drift | pass | Delta is exactly the owed items + memory; no drive-bys, no dep changes |
| checkpoint | pass | Clean commit sequence, red commit isolated, fix commit's test edits comment-only, worktree clean and pushed |
| audit_trail | pass | Red counts, mutation results, session links in commit messages; doc records the round; 95fffa1's error self-caught by 71d8284 |

## Verdict

**risk=low confidence=high**

The medium-risk driver of rounds 6–9 — a record that rots invisibly under green tests — now has a
verified mechanical tripwire on every surface that had actually rotted. No behavioural defect in
three consecutive rounds; the behavioural code is untouched this round. What remains is two small
record edits and two PR-body disclosures, none of which threaten the hook's behaviour.
