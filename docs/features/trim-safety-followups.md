---
phase: planning
model_tier: high
branch: none
worktree: ~/.worktrees/.claude/trim-safety-followups
---

# Three follow-ups the handoff-trim-safety card recorded and did not fix

**Status:** planning. Card written 2026-09-18 on `fix/trim-safety-followups` (the branch exists
only to carry this card's docs commits from an isolated worktree — the primary checkout is
off-limits to every session; it is not recorded above until the gate opens).

## Background

`docs/features/handoff-trim-safety.md` (merged, PR #105) closed with three things it measured and
deliberately left out of scope. Each is small; together they are one card because they were found
together, share a reviewer, and none earns a card alone. Ordered smallest first.

**A. A machine-specific path in a committed comment.** `hooks/handoff/handoff-keep-guard.sh`'s
contract header names the binary the Stop contract was measured against as
`/Users/marksuyat/.local/bin/claude` (grep `measured against the installed binary`). The prior
card kept it on purpose as a measurement record. `rules/core-conduct.md` forbids absolute paths
in committed files, and the identifying fact is the **version** (`2.1.267 (2026-09-10)`), which
the same sentence already carries — the path adds a username and nothing else.

**B. A card in `review` locks its own branch.** `hooks/phase-guard.sh` collects the branches a
card has claimed with `if [ "$file_phase" = "implementation" ] && [ -n "$file_branch" ]` (step 7).
A card at `phase: review` claims nothing, so while any un-superseded `planning` card exists
elsewhere in the repo — eight cards read `planning` on this branch, measured 2026-09-18 with
`grep -l '^phase: *planning' docs/features/*.md | wc -l` — every source `Edit`/`Write` on the
review branch is refused. Review is exactly when judge findings are fixed, and those are source edits:
the last feature flipped `implementation`↔`review` three times in one day to get past it
(memory `reference_review_phase_card_blocks_source_edits`). The same file's step 8 already
treats `review` as "the gate opened" when deciding which planning cards are superseded; step 7
and step 8 disagree with each other, and step 8 is right.

**C. The test receipt does not cover split test parts.** `hooks/lib/write-test-marker.py`
writes a receipt naming two blobs — the subject and its `.test.sh`/`.test.py` runner
(`PAIR_SUFFIXES`). The handoff-trim-safety card split four runners into a thin `X.test.sh` plus
an `X.test.d/NN-*.sh` folder sourced by `hooks/handoff/lib/test-parts.sh`
(`source_test_parts`, glob `[0-9][0-9]-*.sh`). Four such folders exist today:
`hooks/handoff/{live-handoff,pre-compact-handoff,slim-session-start}.test.d` and
`hooks/handoff/lib/handoff-archive.test.d`. A part's basename ends in `.sh`, so
`decide-commit-gate.py`'s `_classify_role` reads it as a **subject** whose derived sibling
`NN-*.test.sh` does not exist — "no sibling test at all, never gated". So a part can be edited,
never re-run, and committed with a still-valid receipt for its runner. ADR 0027 defines the
receipt as proof the suite ran against *these exact bytes*; today the bytes it proves are not
the bytes that run.

**Not in scope, recorded so the next reader does not re-derive it:**
- `hooks/phase-guard.test.sh` (1242 lines) and `hooks/test-marker-guard.test.sh` (1122) are
  both over the 800-line hard cap. Already enumerated by
  `docs/features/pane-dispatch-test-suite-split.md`, which fixes only its own file on purpose.
  This card adds one assertion to the first and one to the second, and splits neither.
- `hooks/lib/decide-commit-gate.py` has no Python sibling suite; it is exercised only through
  the bash hook suite. Task 6 gives it one because the new part-comparison tests need a home
  and the oversize bash file is the wrong one — the side effect that the decider itself becomes
  receipted is welcome but was not the reason.
- Which guards the *approval* design should watch (`project_guard_loosening_approval_pending`)
  is a different, unapproved card.

## Spec

Toolchain, pinned as measured 2026-09-18: Python 3.9.6, git 2.50.1 (Apple Git-155). Hooks run
under `#!/usr/bin/env bash` as today. No new dependencies.

### A. The comment

```gherkin
Scenario: the contract header names the binary without a machine path
  Given hooks/handoff/handoff-keep-guard.sh's Stop-hook contract header
  When it names the binary the contract was measured against
  Then it reads "~/.local/bin/claude, version 2.1.267 (2026-09-10)"
  And no line of the file contains "/Users/"
```

No test: a comment. The card's verification records the `grep -c '/Users/'` = 0 measurement.

### B. `review` claims its branch

One rule change in `hooks/phase-guard.sh` step 7: a card claims `branch:` when its phase is
`implementation` **or** `review`. Nothing else moves — step 8's supersession rule already says
the same thing, and the deny message stays word-for-word.

```gherkin
Scenario: a review card unlocks the branch it names
  Given a planning card P (un-superseded) and a card R at phase review with branch: b
  And the current branch is b
  When a source file is written
  Then the write is allowed

Scenario: a review card does not unlock any other branch
  Given the same P and R
  And the current branch is c
  When a source file is written
  Then the write is denied naming P

Scenario: a review card with no branch claims nothing
  Given P and a card at phase review with branch: none
  And the current branch is b
  When a source file is written
  Then the write is denied
```

Spec amendment, made by this card and said so in the row: `docs/features/phase-guard-hook.md`'s
decision table gains the row "A file is `review` with `branch: B` | `B` | **allow**", and the
existing row "All files `review`, or `implementation` on other branches | any | allow" is left as
it is (it was already true). The `planning`-permissions table in
`skills/managing-session-memory/SKILL.md` is unchanged: review still forbids *new feature
work*; fixing findings on the review branch was always permitted work that the hook alone
refused.

### C. The receipt names every part

**Receipt schema (writer, `hooks/lib/write-test-marker.py`).** Version stays `1`. A new
top-level key `parts` is written **only when** the runner has a parts folder: for runner
`<stem>.test.sh`, the folder is `<stem>.test.d/` and its parts are the files matching
`[0-9][0-9]-*.sh` in filename order — the exact glob `source_test_parts` sources, so the receipt
and the runner agree on what "the suite" is. Each entry is `{"path": <repo-relative>, "blob":
<git hash-object>}`, ordered by path. A folder that exists but holds no matching file writes
`"parts": []`. A runner with no folder writes no `parts` key at all, so every receipt on disk
today stays valid for a runner that has no parts. The decider reads an absent key and `[]` as
the same thing — the empty set — so the two never need telling apart. A `.test.py` runner never
has parts (nothing sources them); the writer does not look.

```yaml
# hooks/state/test-markers/hooks%2Fhandoff%2Flive-handoff.sh — after this card
version: 1
subject: {path: hooks/handoff/live-handoff.sh, blob: <sha>}
test:    {path: hooks/handoff/live-handoff.test.sh, blob: <sha>}
parts:                                   # present only when live-handoff.test.d/ exists
  - {path: hooks/handoff/live-handoff.test.d/10-snapshot-and-keep-envelope.sh, blob: <sha>}
  - {path: hooks/handoff/live-handoff.test.d/20-….sh, blob: <sha>}
written_at: 2026-09-18T…Z                # informational, never decided on (unchanged)
```

**Classification (decider, `hooks/lib/decide-commit-gate.py` `_classify_role`).** The step-1
table in `docs/features/verification-marker-gate.md` gains a row **before** row 3, because the
match is on the path, not the basename, and a part's basename would otherwise take row 3:

| # | path matches | role | derived pair |
|---|---|---|---|
| 2a | `<stem>.test.d/[0-9][0-9]-*.sh` (last two components) | part | test `<stem>.test.sh`, subject `<stem>.sh` |

A part joins the pair set exactly as its runner would (step 2: the subject must be tracked; the
three orphan-suite exclusions apply unchanged). A file under `.test.d/` that does not match the
glob (`README.sh`, `helper.sh`) is **not** a part — `source_test_parts` never sources it — and
falls through to the rows below as today.

**Comparison (decider, per pair, after the existing subject and test blob checks).** The parts
*being committed* are enumerated by the same three commit forms the existing members use
("Which paths, and which content" in the marker card): `PLAIN` reads the index
(`git ls-files --stage -- <folder>/`); `PATHSPEC` and `ALL` take each part in the path set from
disk (`hash-object`) and every other part from `<base>` (`git ls-tree <base> -- <folder>/`),
with `ALL` also dropping a base part that is missing on disk (a deletion). The result is a set of
`(path, blob)`. It is compared to the receipt's `parts` as a set; `absent key` counts as the
empty set. Any difference blocks with the new door **`MSG_STALE_PART`**, field 3 naming the
first differing path in sort order, field 4 the pair as today.

```gherkin
Scenario: a changed part with a stale receipt is blocked
  Given runner R.test.sh with folder R.test.d/ holding parts 10-a.sh and 20-b.sh
  And a receipt written after the suite last ran, naming both parts' blobs
  And 20-b.sh is edited and staged, nothing else
  When git commit runs
  Then the decision is BLOCK MSG_STALE_PART with detail R.test.d/20-b.sh and pair R.sh|R.test.sh

Scenario: re-running the suite after the edit clears it
  Given the same state
  When the suite is re-run (the receipt is rewritten) and git commit runs again
  Then the decision is ALLOW

Scenario: a new part the receipt has never seen is blocked
  Given a receipt naming 10-a.sh and 20-b.sh
  And a new 30-c.sh is added and staged
  When git commit runs
  Then BLOCK MSG_STALE_PART with detail R.test.d/30-c.sh

Scenario: a deleted part is blocked until the suite reruns
  Given a receipt naming 10-a.sh and 20-b.sh
  And 20-b.sh is deleted (git rm) and the deletion staged
  When git commit runs
  Then BLOCK MSG_STALE_PART with detail R.test.d/20-b.sh

Scenario: a pre-card receipt for a runner that HAS parts is stale by definition
  Given a version-1 receipt with no parts key, for a runner whose folder holds parts
  And the runner itself is staged unchanged
  When git commit runs
  Then BLOCK MSG_STALE_PART — the parts were never receipted

Scenario: a pre-card receipt for a runner with NO parts stays valid
  Given a version-1 receipt with no parts key, for a runner with no .test.d folder
  When its subject is committed at the receipted blob
  Then ALLOW — nothing on disk today is invalidated

Scenario: a non-part file inside the folder is not gated
  Given R.test.d/helper.sh (no NN- prefix) is edited and staged alone
  When git commit runs
  Then it is classified by the rows below 2a, exactly as before this card

Scenario: the pair is formed from the part alone
  Given only R.test.d/20-b.sh is staged (neither R.sh nor R.test.sh is in the path set)
  When git commit runs
  Then the pair R.sh|R.test.sh is formed and the receipt is read for it

Scenario: a .test.py runner never has parts
  Given a receipt for X.py|X.test.py and a folder X.test.d/ someone created by hand
  When X.py is committed
  Then the folder is ignored — no parts key is written and none is compared
```

**Door table.** `docs/features/verification-marker-gate.md`'s field-2 domain grows by one:
count the `_emit("BLOCK", "MSG_` call sites in the decider rather than trusting the word
"eight" (it becomes nine). `hooks/test-marker-guard.sh` prints the new door in the style of
`MSG_STALE_TEST`: `MSG_STALE_PART -- <pair> would ship test part <detail> that was never run.`
Its "door this version of the gate does not recognise" fallback keeps catching anything else.

**Fail direction, unchanged.** A part folder the decider cannot enumerate (a `git ls-tree` that
fails) raises `_GitFailure` → `MSG_GIT_FAILED`, as every other git failure in the file does.

## Tasks

Order is the spec's: A, B, C. RED and GREEN are separate commits (`rules/core-conduct.md`:
never tests and implementation in one step). Every commit is `git commit -F <msg> -- <paths>`.

- [ ] Task 1 — A: rewrite the header line in `hooks/handoff/handoff-keep-guard.sh` to
  `~/.local/bin/claude`, keep the version; record `grep -c '/Users/'` = 0 in Verification.
- [ ] Task 2 — B RED: add the three review-claims scenarios to `hooks/phase-guard.test.sh`,
  next to the existing `B5` supersede assertion; run, confirm the first fails and the other two
  pass **as written** (the falsifier must be the allow, not a typo).
- [ ] Task 3 — B GREEN: the one-line step-7 change in `hooks/phase-guard.sh`; suite green;
  the decision-table row in `docs/features/phase-guard-hook.md`, marked "added by
  trim-safety-followups".
- [ ] Task 4 — C RED (writer): in `hooks/lib/write-test-marker.test.py`, a runner with a
  `.test.d/` folder gets `parts` in path order with the folder's `[0-9][0-9]-*.sh` only; a
  runner without one gets no `parts` key; a `.test.py` runner never gets one.
- [ ] Task 5 — C GREEN (writer): `write_marker` enumerates the folder with the
  `source_test_parts` glob and writes `parts`; suite green.
- [ ] Task 6 — C RED (decider): new sibling `hooks/lib/decide-commit-gate.test.py`, throwaway
  repos in the `write-test-marker.test.py` pattern, one assertion per scenario above, each of
  the three commit forms for the changed-part case. Runs red on the unchanged decider.
- [ ] Task 7 — C GREEN (decider): `_classify_role` row 2a, the per-form part enumeration, the
  set comparison, `MSG_STALE_PART`; suite green.
- [ ] Task 8 — C hook: `hooks/test-marker-guard.sh` prints `MSG_STALE_PART`; one hook-level
  assertion in `hooks/test-marker-guard.test.sh` (a staged part with a stale receipt blocks
  through the real hook). RED then GREEN as two commits.
- [ ] Task 9 — C docs: row 2a and the door count in `docs/features/verification-marker-gate.md`
  (marked as this card's amendment); ADR `docs/decisions/0048-*.md` — the receipt covers the
  parts the runner sources, amending 0027's "two blobs".
- [ ] Task 10 — re-run every suite this card touched so their receipts are fresh, then run the
  observability judge; retire memory `reference_review_phase_card_blocks_source_edits` (it
  documents the workaround B removes) — a `~/.claude/projects/…/memory/` edit, outside git.

## Verification

<Appended during review: pass/fail per area and open issues only.>
