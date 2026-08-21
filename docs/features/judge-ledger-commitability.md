---
phase: implementation
model_tier: xhigh
branch: chore/judge-ledger-commitability
---

# Judge ledgers: make the two tracked ledgers committable again, and auto-merge their appends

Planned 2026-08-21 on `main` @ `a2a6022`, immediately after PR #59 merged.

## Problem — an unintended interaction inside PR #59, not a decision to revisit

ADR 0031 deliberately kept exactly two files tracked under the retired tree:
`coding-memory/observability-judge/verdicts.jsonl` and
`coding-memory/compliance-judge/verdicts.jsonl`. Its stated reason: they are the accumulated
judge record, and untracking would fragment it per worktree.

The **same** change narrowed `git-guard`'s default-branch allowlist to `docs/*.md` alone
(`hooks/git-guard.sh:386` — the only allow arm; every other path sets `allowed=0`).

Those two decisions cannot both hold. A file that is tracked but cannot be committed on `main`
can only accumulate uncommitted drift. ADR 0031 chose to keep them tracked; it never chose to make
them un-committable.

## Evidence — measured 2026-08-21, re-run before acting

Observed on this machine while pulling `a2a6022` into the shared checkout:

| Ledger | base `7fcfd95` | `origin/main` | local working tree | true union |
|---|---|---|---|---|
| compliance | 123 | 133 (+10) | 146 (+23) | **156** |

Both sides had appended. Neither was a superset. `git pull` aborted with
"Your local changes would be overwritten", and the union had to be rebuilt by hand and verified
in both directions (0 rows lost, 0 invented).

The record is genuinely cross-project, which is why fragmenting it is the wrong fix:

| Ledger | rows | rows with `outcome` backfilled | distinct repos |
|---|---|---|---|
| observability | 199 | 69 | 15 |
| compliance | 156 | 5 | 10 |

Derivation (run it, do not copy the number):
`python3 -c "import json;r=[json.loads(l) for l in open(P) if l.strip()];print(len(r),sum(1 for x in r if x.get('outcome')),len({x.get('repo') for x in r}))"`

## Scope

Two changes. Nothing else.

1. **`hooks/git-guard.sh`** — allow the ledger path(s) on the default branch, alongside `docs/*.md`.
2. **`.gitattributes`** (does not exist yet) — `merge=union` for the ledgers, so concurrent appends
   from two branches concatenate instead of conflicting. Git's built-in driver; no custom script.

**Explicitly out of scope:** widening the allowlist beyond the ledgers, un-retiring anything,
changing what the judges write, and backfilling `outcome` values.

## Open questions — decide before implementing

- **Exact literals or a pattern?** Two exact paths is tightest. `coding-memory/*/verdicts.jsonl`
  admits future judges — but note `*` spans `/` in a `case` pattern (the file says so at
  `git-guard.sh:384`), so that pattern matches any depth. **Recommendation: two exact literals**,
  since a third judge is hypothetical and the guard should be as precise as the rule it enforces.
- **Does `merge=union` risk duplicate rows?** Yes, if both sides contain a byte-identical line.
  Rows carry distinct `ts`/`head_sha`, so this should not occur — but the test must prove it.
- **`merge=union` does not fix the case that actually bit us.** Today's abort was uncommitted local
  changes on a *fast-forward*, where no merge runs. The allowlist change is what removes the reason
  drift accumulates; the union driver is for branch-vs-branch. Both are wanted; neither alone.

## Tasks

- [ ] 0. Branch `chore/judge-ledger-commitability` + worktree. **Only after `gate confirmed`.**
- [ ] 1. Re-run the evidence above; confirm the counts still hold at the then-current `main`.
- [ ] 2. **Red:** add `git-guard.test.sh` cases asserting a commit of each ledger on `main` is
      currently REFUSED, and that `coding-memory/other.md` and a traversing
      `coding-memory/../src/x.sh` stay refused after the change. Watch them fail for the right reason.
- [ ] 3. **Green:** add the allow arm(s) at `git-guard.sh:386`; update the `:391` refusal message,
      which currently names only `docs/*.md`.
- [ ] 4. Update `hooks/git-guard.replay.sh` expected values — the two ledger commands move from
      `stricter` to `identical` vs. the pre-#59 base. Confirm the run still reports **63 commands**;
      a mutation that drops a case from `CMDS` proves nothing.
- [ ] 5. `.gitattributes` with `merge=union`, scoped to the ledger paths.
- [ ] 6. Test the union driver for real: two branches each append a row, merge, assert both survive
      and no duplicate appears. This is the claim that must not be asserted without running it.
- [ ] 7. Update `rules/gates.md` (default-branch safety stub names the allowlist verbatim),
      `hooks/README.md`, and `skills/managing-session-memory` where they state `docs/*.md` alone.
- [ ] 8. Full suite green — record counts run, not counts read.
- [ ] 9. ADR under `docs/decisions/` amending ADR 0031: state that keeping the ledgers tracked and
      excluding them from the allowlist were incompatible, and which one moved.
- [ ] 10. Observability judge, then draft PR.

## Also worth fixing while here — decide separately, do not silently bundle

PR #59's card claims "nothing is deleted from disk". That is **true only in the worktree where
`git rm --cached` ran.** Six judge rounds confirmed it, all six looking at that worktree. In any
other checkout, pulling `a2a6022` fast-forwards and **deletes 213 files** (`CODING_MEMORY.md` +
212 under `coding-memory/`); being gitignored does not protect a file tracked at the old commit.
Proved in an isolated repo, not assumed. Recovery, verified:
`git archive 7fcfd95 CODING_MEMORY.md coding-memory | tar -x -C <repo> --exclude='*/verdicts.jsonl'`
(the `--exclude` is load-bearing — without it the old ledgers overwrite the live ones).

This is a factual error in a merged document and will mislead the next person who pulls on another
machine. It is a docs-only fix and could ship as its own small PR ahead of this one.
