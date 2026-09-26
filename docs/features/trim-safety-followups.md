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
contract header names the binary the Stop contract was measured against by its absolute path
under the user's home directory (locate it with `grep -n 'measured against the installed
binary'`; the path is deliberately not repeated here, or this card would carry what it removes).
The prior card kept it on purpose as a measurement record. `rules/core-conduct.md` forbids absolute paths
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
(`PAIR_SUFFIXES`; ADR 0027 puts it as "the subject **and** the test file"). The handoff-trim-safety card split four runners into a thin `X.test.sh` plus
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
  This card grows **neither** `test-marker-guard.test.sh` (C's hook-level assertion lives in the
  new Python sibling, task 6, which runs the real bash hook) **nor** any other oversize file,
  with one exception: B's three assertions have no home but `phase-guard.test.sh` — there is no
  sibling suite and no parts convention for it — so they go there, roughly fifteen lines. That
  growth is a **user-granted waiver** recorded in the compliance verdict, not a silent deferral;
  splitting that suite is the test-split card's work.
- `hooks/lib/decide-commit-gate.py` has no Python sibling suite; it is exercised only through
  the bash hook suite. Task 6 gives it one because the new part-comparison tests need a home
  and the oversize bash file is the wrong one — the side effect that the decider itself becomes
  receipted is welcome but was not the reason. The decider is 392 lines; C adds to it and it
  will pass the 400-line preference while staying well under the 800 maximum. Accepted: the
  alternative is a third module with its own sibling suite for ~40 lines.
- **A second split convention has the same gap and is not fixed here.**
  `panes/dispatch-pane-agent.test.sh` fans out to six `panes/dispatch-pane-agent.<concern>.test.sh`
  files through its `SUITES` list (ADR 0044's residual). Those basenames end in `.test.sh`, so the
  decider reads each as a runner whose subject `dispatch-pane-agent.<concern>.sh` is untracked —
  skipped, never gated, today. Row 2a does not match them and this card does not claim to. The
  ADR in task 9 is scoped to the `.test.d/` convention by name, so that its title is true.
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
  Given P and a card at phase review whose frontmatter has NO branch: line at all
  And the current branch is b
  When a source file is written
  Then the write is denied
```

The third scenario's fixture omits the `branch:` line rather than writing `branch: none`.
`FRONTMATTER_AWK` accepts any non-space token (`/^branch:[[:space:]]*[^[:space:]]+/`), so
`none` parses as a branch *literally named* `none` and the deny would come from `b != none`,
not from the `-n "$file_branch"` guard — an implementation that dropped that guard would pass
all three. An absent line is what makes the guard the thing under test. (This card's own
frontmatter says `branch: none`; that is the house convention for "not yet gated" and is
unaffected — it only means this card claims a branch nobody is on.)

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

What the receipt asserts about a part is **the same thing it asserts about the runner** — these
bytes were present when the suite exited 0 — and no more. That a folder beside a runner is
sourced *by* that runner is a convention, not something the writer observes; it holds for all
four folders today (each runner passes `$HOOK_DIR/<stem>.test.d` to `source_test_parts`), and
task 9b's count check is what would notice if it stopped holding.

**The glob lives in one Python place.** `write-test-marker.py` defines `PARTS_GLOB` (and the
`parts_folder_for(test_rel)` / `is_part(path)` helpers beside `PAIR_SUFFIXES`); the decider
imports them through its existing `_load()` rather than restating them. The bash copy in
`test-parts.sh` cannot share a constant, so a writer test reads that file and asserts its glob
string equals `PARTS_GLOB` — a drifted copy fails a test instead of silently receipting a
different set of files than the runner sources.

**A malformed `parts` is a malformed receipt.** The receipt is a file read from disk, and every
other bad shape already lands on `MSG_BAD_MARKER`; `parts` joins that rule. Malformed means:
present but not a list; an entry that is not an object; a missing or non-string `path` or
`blob`; a `blob` failing the existing `_BLOB_RE`; a `path` that is not under this pair's
`<stem>.test.d/` folder or does not match the glob; a duplicate `path`. All → `MSG_BAD_MARKER`,
before any comparison, exactly as a bad `subject` or `test` does today.

The block below is an **illustration in YAML for readability**; the writer emits JSON
(`json.dumps(…, indent=2, sort_keys=True)`), unchanged.

```yaml
# hooks/state/test-markers/hooks%2Fhandoff%2Flive-handoff.sh — after this card (illustration)
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

Scenario: a deleted part is blocked when the pair is in the commit
  Given a receipt naming 10-a.sh and 20-b.sh
  And 20-b.sh is deleted (git rm), and R.sh is also staged
  When git commit runs
  Then BLOCK MSG_STALE_PART naming R.test.d/20-b.sh

Scenario: a lone part deletion is NOT gated
  Given a receipt naming 10-a.sh and 20-b.sh
  And only the deletion of 20-b.sh is staged
  When git commit runs
  Then ALLOW — no path in the set forms a pair, so none is read

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

Scenario Outline: a malformed parts key is a bad receipt, not a stale one
  Given a receipt whose parts is <shape>
  When git commit runs for its pair
  Then BLOCK MSG_BAD_MARKER, before any part is enumerated or compared
  Examples:
    | shape                                                   |
    | a string instead of a list                              |
    | a list holding a string                                 |
    | an entry with no blob                                   |
    | an entry whose blob is not 40 or 64 hex characters      |
    | an entry whose path is outside <stem>.test.d/           |
    | an entry whose path is inside the folder but not NN-*.sh|
    | two entries with the same path                          |
```

**Door table.** `docs/features/verification-marker-gate.md`'s field-2 domain grows by one
door. The count that matters is **distinct** constants the decider can emit, not call sites
(`MSG_GIT_FAILED` is emitted from two places): measured 2026-09-21 with
`grep -o '_emit("BLOCK", "MSG_[A-Z_]*' hooks/lib/decide-commit-gate.py | sort -u | wc -l` = 8
against 9 call sites. After this card the recipe gives 9. The word "eight" appears on ten lines
of the marker card (`grep -nw eight`), plus one Scenario Outline row per door; task 9 updates
every one it finds by that grep, not a remembered list. `hooks/test-marker-guard.sh` prints the
new door **saying only what is known** — the receipt and the commit disagree — because three of
the blocked shapes did not "ship an unrun part" at all (a deletion ships nothing; a pre-card
receipt never recorded parts that did run). It carries its remedy the way `MSG_NO_MARKER` does:
`MSG_STALE_PART -- <pair>: the receipt's part list differs from what this commit ships (first
difference: <detail>). Re-run: bash <test>`. Its "door this version of the gate does not
recognise" fallback keeps catching anything else.

**A lone deletion stays ungated — deliberately, and not this card's call to change.** All four
collectors in `_collect_path_set` pass `--diff-filter=d`, and
`docs/features/verification-marker-gate.md` states the rule in Scope ("removing a file needs no
test run") and pins it with its own scenario. So a commit staging *only* the removal of a part
forms no pair and is allowed, exactly as removing the runner itself is. A deleted part is caught
the moment the pair forms through any other staged path — the committed set then lacks it and
the sets differ. Widening `--diff-filter` is a change to the marker card's rule, not a
follow-up this card may make on its own.

**Fail direction, unchanged.** A part folder the decider cannot enumerate (a `git ls-tree` that
fails) raises `_GitFailure` → `MSG_GIT_FAILED`, as every other git failure in the file does.

### How these commits get past the marker gate

Measured 2026-09-21, before any task runs — the card must not assume a receipt it cannot get:

| suite | today | writes its own receipt? |
|---|---|---|
| `bash hooks/phase-guard.test.sh` | 147 passed, 0 failed | yes (`phase-guard.test.sh` calls the writer at rc 0) |
| `python3 hooks/lib/write-test-marker.test.py` | 70 passed, **2 failed** | only at rc 0 — so **no**, today |
| `bash hooks/test-marker-guard.test.sh` | 249 passed, 0 failed | **no** — it only `cp`s the writer into fixtures; it never calls it on itself |

The writer suite's two failures are a **known false positive on `origin/main`** (commit
`a668c2f`, 2026-09-17): its `wired` check greps each runner's body for a writer call, and the two
`panes/` runners write theirs through `panes/test-lib.sh`'s `tl_finish`, which a body grep cannot
see. Fixing that check is its own card, not this one.

So: **task 3 and task 5 are the only commits that can carry a fresh receipt**, and task 5's
depends on the writer suite going green, which it will not. Every commit in this card that
stages a file with a sibling test therefore carries `TEST_EXEMPT='<reason>'`, with the reason
naming which of the three rows above applies — a RED commit by construction cannot have a
receipt, and neither can a subject whose suite never writes one. This is the prior card's
precedent (`docs/features/handoff-trim-safety.md`, the RED commits), written down here rather
than rediscovered per task. Task 10 re-runs the suites for freshness where a receipt exists
and says plainly, in Verification, which pairs still have none.

## Tasks

Order is the spec's: A, B, C. RED and GREEN are separate commits (`rules/core-conduct.md`:
never tests and implementation in one step). Every commit is `git commit -F <msg> -- <paths>`,
with `TEST_EXEMPT` per the table above.

- [ ] Task 1 — A: rewrite the header line in `hooks/handoff/handoff-keep-guard.sh` to
  `~/.local/bin/claude`, keep the version; record `grep -c '/Users/'` = 0 in Verification.
- [ ] Task 2 — B RED: add the three review-claims scenarios to `hooks/phase-guard.test.sh`,
  next to the existing `B5` supersede assertion; run, confirm the first fails and the other two
  pass **as written** (the falsifier must be the allow, not a typo).
- [ ] Task 3 — B GREEN: the one-line step-7 change in `hooks/phase-guard.sh`; suite green;
  the decision-table row in `docs/features/phase-guard-hook.md`, marked "added by
  trim-safety-followups".
- [ ] Task 4 — C RED (writer): in `hooks/lib/write-test-marker.test.py`, a runner with a
  `.test.d/` folder gets `parts` in path order with the folder's `[0-9][0-9]-*.sh` only; an
  empty folder gets `[]`; a runner without one gets no `parts` key; a `.test.py` runner never
  gets one; and `PARTS_GLOB` equals the glob string read out of
  `hooks/handoff/lib/test-parts.sh` (the bash copy that cannot import it).
- [ ] Task 5 — C GREEN (writer): `PARTS_GLOB`, `parts_folder_for`, `is_part` beside
  `PAIR_SUFFIXES`; `write_marker` enumerates the folder and writes `parts`; suite green apart
  from the two pre-existing `wired` failures named above (record the before/after counts —
  70/2 must stay 2, not grow).
- [ ] Task 6 — C RED (decider): new sibling `hooks/lib/decide-commit-gate.test.py`, throwaway
  repos in the `write-test-marker.test.py` pattern, one assertion per scenario above (the
  malformed-parts outline included), each of the three commit forms for the changed-part case,
  and one hook-level assertion that runs the real `hooks/test-marker-guard.sh` with a
  PreToolUse payload and sees `MSG_STALE_PART` on stderr with exit 2 — here, not in the
  oversize bash suite. Runs red on the unchanged decider and hook.
- [ ] Task 7 — C GREEN (decider): `_classify_role` row 2a via the imported `is_part`, the
  per-form part enumeration, `MSG_BAD_MARKER` for a malformed `parts`, the set comparison,
  `MSG_STALE_PART`; suite green except the hook-level assertion.
- [ ] Task 8 — C hook GREEN: `hooks/test-marker-guard.sh` prints `MSG_STALE_PART`; the task-6
  hook-level assertion goes green. No change to `hooks/test-marker-guard.test.sh`.
- [ ] Task 9 — C docs: row 2a, and every "eight" the door-table grep finds, in
  `docs/features/verification-marker-gate.md` (each marked as this card's amendment); ADR
  `docs/decisions/0048-*.md`, titled and scoped to the `.test.d/` convention — "the receipt
  covers the parts a `.test.d/` runner sources" — amending ADR 0027's rule that "a marker records `git hash-object` of the subject **and** the
  test file" (`0027…md:27` — the phrase "two blobs" is the writer's docstring, not the ADR's),
  and naming the
  `dispatch-pane-agent.<concern>.test.sh` convention as still outside the receipt.
- [ ] Task 9b — the differential check the two new suites cannot give each other: writer and
  decider derive `<stem>.test.d/` the same way, so a wrong derivation makes both agree on "no
  parts" and both suites stay green. Assert against the four **real** runners that the receipt's
  `len(parts)` equals the count each runner hard-codes in its own `source_test_parts "<dir>" N`
  call — an oracle neither new module produces.
- [ ] Task 10 — re-run every suite this card touched so their receipts are fresh, then run the
  observability judge; retire memory `reference_review_phase_card_blocks_source_edits` (it
  documents the workaround B removes) — a `~/.claude/projects/…/memory/` edit, outside git.

## Verification

<Appended during review: pass/fail per area and open issues only.>
