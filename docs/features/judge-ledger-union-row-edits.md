---
phase: planning
model_tier: high
branch: none
---

# `merge=union` silently duplicates a judge verdict when a row is edited in place

Queued 2026-09-17, from a measured corruption rather than a review comment. Split out of
`docs/features/judge-ledger-commitability.md` (PR #104) at the user's direction so that the
detection work does not grow a PR that was otherwise finished and already reviewed.

## What happened

PR #104 adds a `.gitattributes` rule marking the two judge ledgers `merge=union`, so that two
branches each appending a verdict row concatenate instead of conflicting. That is the right call for
the case it was chosen for, and it is not in question here.

While PR #104 was in its second review round, PR #106 merged to `main`. Merging `main` back into the
branch produced a **clean auto-merge with zero conflict markers** and a **corrupted ledger**: five
verdict rows present twice.

PR #106 was a **backfill**. It set the `outcome` field on five rows that already existed
(`null` → `"rework"` ×4, `null` → `"clean"` ×1); it appended nothing. The branch carried the
pre-backfill copies. `union` keeps both sides' lines by definition, so both the stale row and the
rewritten row survived.

## Why nothing caught it

This is the part that makes it worth its own card. Every cheap check passes:

| Check | Result on the corrupted file |
|---|---|
| merge exit code | 0 — clean |
| conflict markers | none |
| every row parses as JSON | yes |
| `sort \| uniq -d` (duplicate **lines**) | 0 — the two copies differ textually |
| row count | plausible; it grew by exactly the number of new verdicts plus five |

It is visible only by grouping rows on an **identity** — `(ts, head_sha, stage)` — and counting
groups with more than one member. The corruption is semantic, not textual, which is precisely why a
line-oriented merge driver cannot see it and a line-oriented check cannot either.

⚠️ **And a count alone is not enough.** The compliance ledger carries **2** duplicate identities
that are present on `origin/main` itself, so a bare "are there duplicates" check reports a
pre-existing problem and a newly-introduced one identically. Distinguishing them required
differencing the identity set against `origin/main` **and** against the pre-merge branch tip — 0 on
main, 0 pre-merge, 5 after. Any detector has to make that distinction or it will cry wolf on day one.

## What is already done, and must not be redone here

- The five duplicated rows were repaired in PR #104 (`4accdd0`), by rebuilding the ledger as an
  explicit union — every row from `origin/main` in order, then only the pre-merge branch rows whose
  identity `main` does not have — rather than by deleting lines. `main` wins an identity present on
  both sides, because `main` carries the backfill.
- The false "append-only" premise was removed from the `.gitattributes` comment, and the in-place
  edit limit recorded there with the measurement that falsified it.
- The shape is **pinned by a test**: `gitattributes.test.sh` section 10 reproduces the incident in a
  throwaway repo (clean merge, stale copy survives, duplicate-line check blind) and was falsified by
  mutating the fixture to drop the `merge=union` rules, which turns it red.
- The two **pre-existing** compliance-ledger duplicates were deliberately left alone. Repairing
  another branch's data inside a merge commit is how the provenance of a bad row gets lost.

## Open questions — none of these are decided

1. **Where does the check live?** A `PreToolUse` hook on `Bash` cannot see a merge's *effect*, only
   its command text, which is the same blindness `worktree-guard.sh` has on the Bash surface. A git
   hook (`post-merge`) sees the result but runs after the damage is in the tree. A test in the suite
   sees nothing about the real ledger. These have different failure directions and the choice is not
   obvious.
2. **Is the identity actually `(ts, head_sha, stage)`?** That triple was sufficient to find these
   five, which is not the same as it being the schema's real key. Verify the field names and their
   types against the writer before building on them; a guessed key fails closed, and failing closed
   is indistinguishable from the check being switched off.
3. **Repair, or only report?** Automatic repair has to pick a winner between two rows with the same
   identity, and "newer `ts`" is not available — the whole point is that both copies share a `ts`.
4. **Does `union` stay at all?** The alternative considered and rejected for PR #104 was dropping the
   rule, which restores a conflict on every concurrent append. Recorded here because a future reader
   will ask, not because it is reopened.
5. **Is the compliance ledger's pair the same bug or a different one?** Unmeasured. They predate this
   branch; nothing has established how they got there.

## Not in scope

Deduplicating the existing history of either ledger, and the two known compliance duplicates.
Those are data questions with their own provenance problem, not merge-safety questions.
