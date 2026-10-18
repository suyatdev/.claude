---
phase: implementation
model_tier: low
branch: fix/trim-safety-followups
worktree: ~/.worktrees/.claude/trim-safety-followups
---

# Three follow-ups the handoff-trim-safety card recorded and did not fix

**Status:** implementation. The gate opened on the literal phrase `gate confirmed`, 2026-10-15,
and the branch is now recorded in the frontmatter above. Card written 2026-09-18 on
`fix/trim-safety-followups` — the branch existed first only to carry this card's docs commits
from an isolated worktree, because the primary checkout is off-limits to every session. Rebased
onto `origin/main` at the gate: 14 commits, and both judge ledgers were checked row-for-row
afterwards (0 upstream rows lost, exactly this card's own 3 compliance + 3 observability rows
added, 0 duplicate lines) because they carry `merge=union`.

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

The third scenario's fixture omits the `branch:` line rather than writing `branch: none`,
because `FRONTMATTER_AWK` accepts any non-space token (`/^branch:[[:space:]]*[^[:space:]]+/`)
and `none` would parse as a branch *literally named* `none` — a different case from the one the
scenario means. **It is not a falsifier for the `-n "$file_branch"` guard**, and an earlier
draft of this card claimed it was: dropping that guard is unobservable, since an empty claim is
dropped by the unquoted word split in step 9's loop and could never match a branch name that
step 9 has already refused to let be empty (`phase-guard.sh:518`). The scenario earns its place
as the "claims nothing" case, not as a test of that line. (This card's own frontmatter says
`branch: none`; that is the house convention for "not yet gated" and is unaffected — it only
means this card claims a branch nobody is on.)

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
four folders today (each runner passes its own directory variable plus `<stem>.test.d` to
`source_test_parts` — `$HOOK_DIR` in three, `$LIB_DIR` in `handoff-archive.test.sh:74`), and
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

Scenario Outline: a deleted part is caught only where the form can see it
  Given a receipt naming 10-a.sh and 20-b.sh
  And 20-b.sh is deleted (git rm), and R.sh is also staged
  When git commit runs in <form>
  Then the decision is <outcome>
  Examples:
    | form                               | outcome                              |
    | PLAIN (git commit, no pathspec)    | BLOCK MSG_STALE_PART naming 20-b.sh  |
    | ALL (git commit -a)                | BLOCK MSG_STALE_PART naming 20-b.sh  |
    | PATHSPEC (git commit -- R.sh 20-b.sh) | ALLOW — the base tree still has it |

Scenario: a lone part deletion is NOT gated
  Given a receipt naming 10-a.sh and 20-b.sh
  And only the deletion of 20-b.sh is staged
  When git commit runs
  Then ALLOW — no path in the set forms a pair, so none is read

Scenario: a pre-card receipt for a runner that HAS parts is stale by definition
  Given a version-1 receipt with no parts key, for a runner whose folder holds parts
  And R.sh is staged with a change, so the pair forms
  When git commit runs
  Then BLOCK MSG_STALE_PART — the receipt records no part, the commit ships two

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

**A lone deletion stays ungated — deliberately, and not this card's call to change.** All
three diff arms in `_collect_path_set` — `PLAIN`, `PATHSPEC`, `ALL` — pass `--diff-filter=d`
(`decide-commit-gate.py:135,137,139`; a fourth `--diff-filter=d` at `:209` is a comment, which
is how an earlier draft of this card miscounted them as four), and
`docs/features/verification-marker-gate.md` states the rule in Scope ("removing a file needs no
test run") and pins it with its own scenario. So a commit staging *only* the removal of a part
forms no pair and is allowed, exactly as removing the runner itself is.

When the pair *does* form through another staged path, **two of the three forms catch the
deletion and one does not**: `PLAIN` reads the index (`ls-files --stage`), where the part is
already gone, and `ALL` hashes from disk and drops what is missing — both differ from the
receipt and block. `PATHSPEC` reads any member outside its path set from `<base>`, so
`git commit -- R.sh <deleted-part>` finds the part alive in the base tree, matching the
receipt, and **allows**. That is the existing collector's behaviour for every pair member, not
something this card introduces; the scenario list says so rather than implying a guarantee the
mechanism does not give. Widening `--diff-filter` is a change to the marker card's rule, not a
follow-up this card may make on its own.

**Fail direction, unchanged, on both sides.** In the decider, *any* git call the part
comparison makes — listing the folder (`ls-tree`, `ls-files --stage`) or hashing one part
(`hash-object`) — raises `_GitFailure` on a non-zero exit, exactly as the existing subject and
test reads do, and surfaces as `MSG_GIT_FAILED`. In the writer, a failed `hash-object` for a
part raises `WriterError` like a failed hash of the runner: **no receipt is written at all**,
rather than one silently missing a part — a partial receipt would read as "this suite has fewer
parts than it does" and pass the very check this card adds.

### How these commits get past the marker gate

Measured 2026-09-21, before any task runs — the card must not assume a receipt it cannot get:

| suite | today | writes its own receipt? |
|---|---|---|
| `bash hooks/handoff/handoff-keep-guard.test.sh` | 61 passed, 0 failed | **yes** — calls the writer at rc 0 (`:548`) |
| `bash hooks/phase-guard.test.sh` | 147 passed, 0 failed | **yes** — same shape (`:1240`) |
| `python3 hooks/lib/write-test-marker.test.py` | 70 passed, **2 failed** | only at rc 0 — so **no**, today |
| `bash hooks/test-marker-guard.test.sh` | 249 passed, 0 failed | **no** — it only `cp`s the writer into fixtures; it never calls it on itself |

⚠️ **Run task 1's suite as `env -u CLAUDE_PANE_AGENT bash hooks/handoff/handoff-keep-guard.test.sh`.**
`handoff-keep-guard.sh:62` exits 0 immediately when `CLAUDE_PANE_AGENT` is set, so inside a pane
agent the suite measures 19/61 instead of 61/61 — a worker would read that red and wrongly file
task 1 under "cannot have a receipt". Only this suite was checked for the interaction.

The writer suite's two failures are a **known false positive on `origin/main`** (commit
`a668c2f`, 2026-09-17): its `wired` check greps each runner's body for a writer call, and the two
`panes/` runners write theirs through `panes/test-lib.sh`'s `tl_finish`, which a body grep cannot
see. Fixing that check is its own card, not this one.

**The rule is: exempt only where a receipt is impossible, and name the reason.** Not "this card
runs on exemptions" — that reading is what the table is here to prevent. Concretely: **task 1
and task 3 must carry real receipts** (their suites write one, and both are GREEN commits); a
RED commit cannot, by construction, since the writer only runs at rc 0; **tasks 5, 7 and 9b cannot** — 5 because the
writer suite is red from a defect this card does not own, 7 and 9b because their commits land
while the decider suite is still red by construction; **task 8 cannot**, because the guard suite
never writes one at all. Any commit that *can* have a receipt and does not is a defect in
this card, not a row in the table. This follows the prior card's precedent
(`docs/features/handoff-trim-safety.md`, its RED commits), written down here rather than
rediscovered per task. Task 10 re-runs the suites for freshness and states, in Verification,
exactly which pairs still have no receipt and why.

## Tasks

Order is the spec's: A, B, C. RED and GREEN are separate commits (`rules/core-conduct.md`:
never tests and implementation in one step). Every commit is `git commit -F <msg> -- <paths>`,
with `TEST_EXEMPT` per the table above.

- [x] Task 1 — A: rewrite the header line in `hooks/handoff/handoff-keep-guard.sh` to
  `~/.local/bin/claude`, keep the version; record `grep -c '/Users/'` = 0 in Verification.
- [x] Task 2 — B RED: add the three review-claims scenarios to `hooks/phase-guard.test.sh`,
  next to the existing `B5` supersede assertion; run, confirm the first fails and the other two
  pass **as written** (the falsifier must be the allow, not a typo).
- [x] Task 3 — B GREEN: the one-line step-7 change in `hooks/phase-guard.sh`; suite green;
  the decision-table row in `docs/features/phase-guard-hook.md`, marked "added by
  trim-safety-followups".
- [x] Task 4 — C RED (writer): in `hooks/lib/write-test-marker.test.py`, a runner with a
  `.test.d/` folder gets `parts` in path order with the folder's `[0-9][0-9]-*.sh` only; an
  empty folder gets `[]`; a runner without one gets no `parts` key; a `.test.py` runner never
  gets one; and `PARTS_GLOB` equals the glob string read out of
  **line 43 of** `hooks/handoff/lib/test-parts.sh` — the `for part in "$parts_dir"/…` loop that
  actually runs. The same glob also sits in a comment at `:25`; a test taking the first match
  would stay green while the real loop drifted, so the assertion anchors on the `for` line.
- [x] Task 5 — C GREEN (writer): `PARTS_GLOB`, `parts_folder_for`, `is_part` beside
  `PAIR_SUFFIXES`; **split `build_marker(root, test_rel)` — enumerates the folder and returns
  the receipt dict, touching nothing on disk — from `write_marker`, which becomes the thin
  caller that persists what `build_marker` returns.** Task 9b depends on that split existing:
  calling the persisting half against the live checkout would stamp four real receipts for
  suites that never ran. Suite green apart
  from the two pre-existing `wired` failures named above (record the before/after counts —
  70/2 must stay 2, not grow).
- [x] Task 6 — C RED (decider): new sibling `hooks/lib/decide-commit-gate.test.py`, throwaway
  repos in the `write-test-marker.test.py` pattern, one assertion per scenario above (the
  malformed-parts outline included), each of the three commit forms for the changed-part case,
  and one hook-level assertion that runs the real `hooks/test-marker-guard.sh` with a
  PreToolUse payload and sees `MSG_STALE_PART` on stderr with exit 2 — here, not in the
  oversize bash suite. Runs red on the unchanged decider and hook. The new suite **calls the
  writer on itself at rc 0**, like `phase-guard.test.sh:1240` does — without that it would
  satisfy the inventory's `wired` text check merely by naming the writer in a fixture, which is
  exactly the false positive that leaves the writer suite red today.
- [x] Task 7 — C GREEN (decider): `_classify_role` row 2a via the imported `is_part`, the
  per-form part enumeration, `MSG_BAD_MARKER` for a malformed `parts`, the set comparison,
  `MSG_STALE_PART`; suite green except the hook-level assertion.
- [x] Task 8 — C hook GREEN: `hooks/test-marker-guard.sh` prints `MSG_STALE_PART`; the task-6
  hook-level assertion goes green. No change to `hooks/test-marker-guard.test.sh`.
- [x] Task 9 — C docs: row 2a, and every "eight" the door-table grep finds, in
  `docs/features/verification-marker-gate.md` (each marked as this card's amendment); ADR
  `docs/decisions/0048-*.md`, titled and scoped to the `.test.d/` convention — "the receipt
  covers the parts a `.test.d/` runner sources" — amending ADR 0027's rule that "a marker records `git hash-object` of the subject **and** the
  test file" (`0027…md:27` — the phrase "two blobs" is the writer's docstring, not the ADR's),
  and naming the
  `dispatch-pane-agent.<concern>.test.sh` convention as still outside the receipt.
- [x] Task 9b — the differential check the two new suites cannot give each other: writer and
  decider derive `<stem>.test.d/` the same way, so a wrong derivation makes both agree on "no
  parts" and both suites stay green. **One commit, not RED-then-GREEN**: it checks the
  derivation task 5 already shipped, so it passes on its first run and no red state is
  reachable — a RED commit here would be an empty one. What replaces the red step is a
  falsifiability check run by hand and recorded in Verification: point `parts_folder_for` at a
  wrong folder, confirm the assertion fails and names the runner, revert. It lives in
  `hooks/lib/write-test-marker.test.py` (the writer owns the derivation under test). It neither
  reads nor writes `hooks/state/`: receipts are gitignored, this worktree holds only
  phase-guard's, and **calling `write_marker` against the live checkout would stamp four real
  receipts for suites that never ran** — the check meant to strengthen the gate would punch a
  hole in it. So task 5 splits the payload out: `build_marker(root, test_rel)` returns the dict,
  `write_marker` stays the thin caller that persists it. Task 9b calls `build_marker` only, once
  per real runner, and asserts the returned `len(parts)` equals the integer that runner passes
  as `source_test_parts "<dir>" N`, read out of the runner file. That N is hand-maintained by a
  different author for a different purpose, which is what makes it an oracle neither new module
  produces; if a runner stops passing a literal N, the check fails loudly rather than skipping.
  **What it does not catch:** the four counts are 4, 5, 4, 5, so a derivation resolving to the
  wrong folder *of the same size* passes, and it exercises the writer's derivation only — the
  decider's is covered by task 6's fixtures. Recorded, not fixed: a stronger oracle would have
  to restate the folder contents, which is the duplication the shared constant exists to avoid.
- [x] Task 10 — re-run every suite this card touched so their receipts are fresh, then run the
  observability judge; retire memory `reference_review_phase_card_blocks_source_edits` (it
  documents the workaround B removes) — a `~/.claude/projects/…/memory/` edit, outside git.

**Judge round 1 (observability, implementation stage, `be9f489`): `risk=low` / `confidence=high`,
no failing dimension, two concerns.** It reproduced all five suite figures and re-ran two of this
card's own recorded mutations byte-exact. The three tasks below are its findings; Mark chose each
fix from alternatives that included "document it and move on" (2026-10-18).

- [ ] Task 11 — `traceability`: an **untracked** file in a parts folder enters the receipt (the
  writer hashes the folder from disk, and bash sources it too) but can never be in what the commit
  ships, so the pair blocks **and the printed remedy loops** — re-running the suite rewrites the
  identical receipt. Reproduced in-session: `BLOCK MSG_STALE_PART detail=…/90-scratch.sh` both
  before and after running the remedy; staging the file clears it. Fix: **keep the receipt honest
  and fix the message** — when the first differing part is untracked, the hook says stage-or-remove
  instead of only "Re-run". The door and the wire format do **not** change; a tenth door would
  cascade every count in the gate's card again. RED then GREEN, separate commits.
- [ ] Task 12 — `success_masking` (a): the amended MUST in
  `docs/features/verification-marker-gate.md` now requires field 3 asserted for "every one of the
  thirteen doors that writes a line", and **this change raised that figure**. But
  `grep -c MSG_STALE_PART hooks/test-marker-guard.test.sh` is **0**: that suite covers 13 of the
  hook's 14 real doors (its 14th name, `MSG_FROM_A_LATER_VERSION`, is a fixture constant, not a
  door), so 249 passes read as door-table coverage while blind to the newest door. Add the row.
  **A deliberate, user-approved departure from task 8's "no change to
  `hooks/test-marker-guard.test.sh`"**, because the same change raised the MUST governing it. One
  commit — it asserts behaviour the hook already has — plus a mutation showing the row can fail.
- [ ] Task 13 — `success_masking` (b): the gate's §Latency budget is **≤200 ms** and last measured
  **169.3 ms**, leaving ~31 ms. The judge measured the added cost at `ls-tree` 7.18 ms,
  `ls-files --stage` 6.41 ms, `hash-object` 6.29 ms — **one extra git subprocess per formed bash
  pair even when the runner has no parts folder**, since `parts_folder_for` returns a path whether
  or not it exists. ~5 pairs eats the slack and the repo has 40 tracked `.test.sh` runners. Neither
  this card nor ADR 0049 contains the word "latency". **Measure first, on a commit forming several
  pairs, and record it**; only then decide whether to skip the call when no folder exists — that
  shortcut has a deleted-folder case needing its own test.

## Verification

<Appended during review: pass/fail per area and open issues only.>

### Task 1 — A: the contract header names the binary without a machine path — PASS

Measured 2026-10-15 in `~/.worktrees/.claude/trim-safety-followups`.

| Check | Before | After |
|---|---|---|
| `grep -c '/Users/' hooks/handoff/handoff-keep-guard.sh` | 1 (line 11) | **0** |
| header phrase, read across the line 11/12 wrap | `/Users/<name>/.local/bin/claude, version 2.1.267 (2026-09-10)` | `~/.local/bin/claude, version 2.1.267 (2026-09-10)` |
| `env -u CLAUDE_PANE_AGENT bash hooks/handoff/handoff-keep-guard.test.sh` | 61/61 | **61/61** |

The phrase was checked by joining lines 11-12 and stripping the comment markers, **not** by a
line-based grep: the phrase wraps across the two lines, so a per-line grep for it reports 0 on a
correct file. The suite was baselined green *before* the edit so that a post-edit failure would
have been attributable; the `env -u CLAUDE_PANE_AGENT` prefix is required or the runner exits
early and scores 19/61 (`handoff-keep-guard.sh:62`).

**Receipt: real, and hand-checked.** Written by `hooks/lib/write-test-marker.py` immediately
after the green run. Its `subject.blob` is `01e11dc458576aa9e611e4baeacb128f6f3911b3` and its
`test.blob` is `8567dae95db315c7cd5b87b2b2c070faf8aa6238`; both equal the hash of the committed
bytes. The comparison discriminates — the pre-edit subject blob was
`aa653cab2b83b84e6bd4261ca3b1a3610e92727a`, so a receipt written before the edit would have
mismatched rather than silently agreed.

⚠️ **Deviation from the card, with the user’s explicit go-ahead (2026-10-15).** The card assumes
the implementation session is rooted in this worktree. It was not — task 1 was done from
`~/.worktrees/.claude/handoff-trim-safety`. Every operation aimed here from outside is refused by
`test-marker-guard` as `MSG_UNSUPPORTED_FORM (FOREIGN_REPO)`, so the commit carries
`TEST_EXEMPT`. That flag suppresses the guard’s **check**, never the receipt: the receipt above
is genuine and was verified by hand against the committed blobs. So the card’s requirement that
tasks 1 and 3 carry real receipts is met in substance, and what is absent is the guard’s
*independent* confirmation. The honest scope of this row: the receipt is real and matches; it was
not adversarially re-checked by the gate itself. Re-run the gate on these bytes from a session
rooted in this worktree if that independent check is wanted — and prefer to root task 3 here,
since it is the other receipt-bearing task.

### Task 2 — B RED: the suite fails in exactly one place, for the rule and not a typo — PASS

Measured 2026-10-16 in `~/.worktrees/.claude/trim-safety-followups`.

| Check | Result |
|---|---|
| `bash hooks/phase-guard.test.sh` | 158 passed, **1 failed** (rc 1) |
| the only `FAIL` line (`grep -c '^FAIL'` = 1) | `B5a a review card unlocks the branch it names (want exit 0, got 2)` |
| `B5b` deny, and its `err_has` on `docs/features/a\.md.*phase: planning` | both pass |
| `B5c` deny — a `review` card with no `branch:` key claims nothing | pass |

The split the card demands holds: the first scenario is red, the other two are green **as
written**. Because exactly one `FAIL` line exists and it is B5a, no pre-existing assertion broke.

⚠️ **Do not read `158` as a figure about this change.** The marker-gate table above recorded
`147 passed, 0 failed` on 2026-09-21; the suite has grown upstream since, and that growth was not
re-measured here. The claims this row makes are the failure *count* (1) and its *identity*.

**The falsifier is the rule, not the fixture.** A throwaway probe built the same fixture shape
twice and changed only the second card's phase word — `implementation` → rc 0, allow, empty
stderr; `review` → rc 2, denying with *"a feature file is still at…"*. Same repo layout, same
payload, one word apart, so B5a's red is step 7 refusing a `review` claim rather than a typo in
the `review_claim_repo` helper. The probe is deliberately **not** committed: once item B lands it
duplicates what B5a and the existing `B2 claimed branch -> allow` case assert between them.

**No receipt, by construction, and that is the card's own rule.** `hooks/phase-guard.test.sh`
calls the writer only at rc 0 — at `:1273` today, **not** the `:1240` the marker-gate table
recorded on 2026-09-21; the suite is now 1275 lines and that citation has drifted, which is the
same upstream growth the `158` caveat above is about. The old figure is left as written, since it
was true when measured. A RED commit is red by design — so this commit
carries `TEST_EXEMPT` for exactly the reason the marker-gate table names for RED commits. Task 3
is where this pair earns a real receipt, from a session rooted in this worktree.

### Task 3 — B GREEN: `review` claims its branch, suite green, receipt real — PASS

Measured 2026-10-16 in `~/.worktrees/.claude/trim-safety-followups`, from a session rooted here —
so unlike task 1 this pair was checked by the gate itself, not only by hand.

| Check | Result |
|---|---|
| `bash hooks/phase-guard.test.sh` | **159 passed, 0 failed** (rc 0) |
| the four B5a–B5c assertions | all `ok` |
| delta from the RED run | 158/1 → 159/0 — one assertion flipped, nothing else moved |

The change is the condition on `hooks/phase-guard.sh` step 7's claim collector: a card claims its
`branch:` when its phase is `implementation` **or** `review`. The deny message, step 8, step 9 and
the frontmatter contract are untouched, as the spec requires.

**Receipt: real, and the gate's own check passed.** `hooks/lib/write-test-marker.py` ran at rc 0
and wrote `hooks/state/test-markers/hooks%2Fphase-guard.sh` naming
`subject.blob 2242afba367c39ad90db0721227f030ba3c296c1` and
`test.blob 2ec7bb1483bcff8f3abf10b2c5c16b7cba99fbac`. Both equal `git hash-object` of the bytes in
this commit. The comparison discriminates: the pre-change subject blob was
`a247a308a7c4683ab201e960fe96265bfb937a08`, so a receipt written before the edit would have
mismatched rather than quietly agreed. No `TEST_EXEMPT` was needed or used.

**Two doc statements changed, not one — a deviation from the card, stated rather than absorbed.**
The card asked for the decision-table row in `docs/features/phase-guard-hook.md`. That file states
the same rule a second time, in step 9's prose — the sentence wraps across `:269-270`, with the
phase words on `:270`, so cite the pair and not one line. The change falsifies it, so it is now
corrected alongside the row (now at `:57`), and both carry a pointer to the other so they move
together next time. See
[[feedback_single_source_the_statement_that_keeps_drifting]].

**And one live rule file.** `rules/gates.md`'s Phase-gate stub said the hook denies "while an
un-superseded `planning` feature file exists and no `implementation` file records the current
branch". That is an always-loaded instruction every session reads, so leaving it would ship a rule
that contradicts the code; the clause now reads `implementation` **or `review`**, marked as added
by this card. It is inert until merge — hooks and rules load from the primary checkout
([[reference_hooks_load_scripts_from_primary_checkout]]).

**Deliberately left alone:** `docs/features/phase-guard-root-markdown.md:29` and
`docs/features/readme-roadmap-upkeep.md:12` each describe the old implementation-only rule in
passing. Both belong to other, closed cards and were true when written, so they are history rather
than live instruction. Recorded here so a later reader finds them on purpose rather than by
surprise. `docs/features/phase-guard-hook.md:1434` likewise narrates the old step-9 grep and stays
as written.

### Task 4 — C RED (writer): ten assertions, seven of them red for the missing feature — PASS

Measured 2026-10-16 in `~/.worktrees/.claude/trim-safety-followups`. Written by a dispatched
worker; every number below was **re-measured here** rather than copied from its report
([[feedback_a_copied_citation_is_laundered_not_verified]]).

| Check | Result |
|---|---|
| `python3 hooks/lib/write-test-marker.test.py` **before** | 70 passed, 2 failed |
| the same **after** | **73 passed, 9 failed** |
| totals | 72 → 82 assertions: 10 added, 3 pass, 7 red |
| `hooks/lib/write-test-marker.py` | byte-identical — `git diff --stat` on it is empty |
| files changed | `hooks/lib/write-test-marker.test.py` only |

The baseline was measured by restoring `HEAD`'s copy of the suite, running it, and restoring the
new one — blob `e61cbe04…` before and after, so the measurement put nothing at risk. 70/2 matches
the marker-gate table's 2026-09-21 figure independently.

**No previously-passing assertion was lost, by set membership and not by arithmetic**
([[feedback_a_balanced_total_is_not_a_verified_union]]). This suite prints only failures, so the
passing names cannot be diffed; instead, the old suite held 72 assertions and the `FAIL` list now
names exactly 9 — the same 2 pre-existing `wired` failures plus 7 names that did not exist before.
No old name appears among them, so the other 70 old assertions pass.

The two pre-existing failures are the known `wired` false positives (`panes/dispatch-pane-agent`
and `panes/run-pane-agent` write their receipts through `tl_finish`, which a body grep cannot
see). Still 2, still those two. They belong to another card.

**Three of the ten pass today, and that is recorded rather than counted as success.** "A runner
with no parts folder writes no `parts` key" and "a `.test.py` runner never gets one" assert *key
absence*, which today's writer satisfies vacuously because it writes no `parts` at all; the third
is the uniqueness guard on the `for` loop. They are guards that go red if task 5 over-writes
`parts`, not evidence the feature is missing. The discriminating pair is the one that demands a
real list and the one that demands `[]` for an empty folder — the latter is specifically what
would catch a lazy "always write `parts: []`" implementation.

**The glob anchor was verified, not trusted.** `hooks/handoff/lib/test-parts.sh:43` is the loop
that runs (`for part in "$parts_dir"/[0-9][0-9]-*.sh; do`) and `:25` is a comment carrying the
same glob — both line numbers as the card states. `grep -n 'for part in'` finds exactly **one**
line, and the assertion anchors on that shape and asserts the count is 1, so a second or reworded
loop fails loudly instead of being silently skipped. A first-match-on-the-glob test would have
read the comment and stayed green while the real loop drifted.

**No receipt, by construction.** A RED commit cannot have one — the writer runs only at rc 0 — so
this commit carries `TEST_EXEMPT`, the case the marker-gate table already names.

### Task 5 — C GREEN (writer): the receipt names the parts, and the split task 9b needs — PASS

Measured 2026-10-16 in `~/.worktrees/.claude/trim-safety-followups`. Written by a dispatched
worker; every figure re-measured here.

| Check | Result |
|---|---|
| `python3 hooks/lib/write-test-marker.test.py` **before** | 73 passed, 9 failed |
| the same **after** | **80 passed, 2 failed** |
| remaining failures | only `wired: panes/dispatch-pane-agent.test.sh` and `wired: panes/run-pane-agent.test.sh` |
| `hooks/lib/write-test-marker.test.py` | untouched — `git diff --stat` on it is empty |
| files changed | `hooks/lib/write-test-marker.py` only |

The 2 pre-existing failures stayed 2 and stayed the same two. The card's requirement was exactly
that they not grow to 3.

**The split exists, and `build_marker` touches nothing on disk.** `build_marker(root, test_rel)`
returns the receipt dict; `write_marker(test_path)` keeps its signature, its return value and its
`None`-for-no-subject behaviour, and is now the thin caller that persists what `build_marker`
returns. Every suite in the repo calls `write_marker`, so nothing else moves. Task 9b calls
`build_marker` only — had it called the persisting half against the live checkout it would have
stamped four genuine-looking receipts for suites that never ran.

**The falsifiability check was re-run here, not accepted from the report.** Two of task 4's new
assertions pass vacuously against a writer that emits no `parts` at all, so without a mutation
nothing shows they discriminate. `marker["parts"] = []` was added unconditionally in
`build_marker`, the suite re-run, and the implementation restored:

| State | Suite | The two key-absence assertions |
|---|---|---|
| implementation | 80 passed, 2 failed | pass |
| mutated | **78 passed, 4 failed** | both **red** — `want the key absent, got parts=[]` |
| reverted | 80 passed, 2 failed | pass |

`git hash-object` of the writer is `e2c02fc6af878bbd53b5506efc2a2c03b600df9a` both before the
mutation and after the revert, so the measurement left nothing behind. The mutated run was red, so
it wrote no receipt of its own.

⚠️ **Recorded, not fixed — those two assertion messages do not name the runner.** Under the
mutation they read `want the key absent, got parts=[]` with no path, although each fixture uses a
distinct runner (`hooks/foo.test.sh` and `hooks/foo.test.py`). The assertion *names* distinguish
them, so a reader can tell which failed; the detail line cannot. A green suite can never surface
this, since the format string runs only on failure
([[feedback_a_green_suite_cannot_validate_assert_messages]]). Left as task 4 committed it rather
than edited after the fact, and noted here so it is a choice rather than an oversight.

⚠️ **One latent fragility, and it fails closed.** The enumeration is
`glob.glob(os.path.join(root, folder_rel, PARTS_GLOB))`, so a checkout path containing a glob
metacharacter (`[`, `*`, `?`) would make the pattern misparse and find no parts. The consequence is
a receipt claiming `parts: []` while the commit ships real parts — which the decider reads as a
mismatch and **blocks** with `MSG_STALE_PART`. Loud and safe, not silent, which is why it is
recorded rather than changed; `glob.glob(..., root_dir=…)` is the fix if it ever bites.

**No receipt, exactly as the marker-gate table predicted for this task.** The suite still exits
non-zero because of the two `wired` false positives it does not own, and the writer only runs at
rc 0 — `hooks/state/test-markers/` holds no entry for `write-test-marker.py`, confirmed by listing
it. So this commit carries `TEST_EXEMPT`. This is the one GREEN commit in the card that legitimately
cannot have one.

### Task 6 — C RED (decider): 28 assertions, 17 red, and the harness proven able to speak — PASS

Measured 2026-10-16 in `~/.worktrees/.claude/trim-safety-followups`. Written by a dispatched
worker; counts re-measured here.

| Check | Result |
|---|---|
| `python3 hooks/lib/decide-commit-gate.test.py` | **11 passed, 17 failed** (rc 1), 28 assertions |
| `grep -c '^FAIL'` | 17 — 16 for the missing decider feature, 1 the hook-level case |
| crashes, tracebacks, harness errors | **none** — every red reads `got ALLOW`, never an error |
| `hooks/lib/decide-commit-gate.py`, `hooks/test-marker-guard.sh` | untouched |
| files added | `hooks/lib/decide-commit-gate.test.py` only |

**The 16 feature reds are one per gherkin scenario**, by name: the changed-part case in all three
commit forms; the re-run-clears-it pair; a new part; the deleted-part `PLAIN` and `ALL` rows; a
pre-card receipt for a runner that has parts; a part staged alone; and all seven malformed-`parts`
outline rows. Every one fails `got ALLOW`, because today `_classify_role` reads a part's `.sh`
basename as a *subject* whose sibling `20-b.test.sh` does not exist — so no pair forms and nothing
is read.

**The harness was shown able to produce both verdicts, not just the one the reds need.** Three
control assertions run first and pass: the real writer's receipt names both parts; a stale subject
yields `MSG_STALE_SUBJECT`; a fresh receipt yields ALLOW. Without those, 17 reds would be equally
consistent with fixtures that simply never build.

⚠️ **Red is proven here; *satisfiable* is not.** A suite demonstrated able to fail is not thereby
demonstrated able to pass ([[feedback_falsifiable_is_not_satisfiable]]). The worker reports writing
a throwaway minimal decider under `/tmp` (since deleted) against which all 28 passed, and the
repo's decider was not touched. **That half was not reproduced in this session** — task 7 is what
settles it, and its expected landing figure is **27 passed, 1 failed**.

⚠️ **The hook-level assertion stays red through task 7 and goes green only in task 8.** The hook's
fallback prints `MSG_CLASSIFIER_BAD_OUTPUT` for a door it does not recognise, so emitting
`MSG_STALE_PART` from the decider is not enough. Its docstring says so; do not read it as a task-7
regression.

⚠️ **The gherkin's `detail R.test.d/20-b.sh` is shorthand — task 7 must emit the full
repo-relative path.** The suite asserts `tools/R.test.d/20-b.sh`, matching the receipt's
`parts[].path` form. For `MSG_BAD_MARKER` it asserts detail `-` with the pair in field 4, which is
how the decider emits that door today.

**One assertion beyond the card**, flagged by the worker rather than slipped in: *a part of a
runner with no tracked subject → ALLOW*. The card's step-2 orphan rule implies it; no scenario
states it.

**The `wired` inventory interaction, measured rather than predicted.** That check enumerates
`git ls-files`, so an untracked file is invisible to it and the writer suite read `80 passed,
2 failed` while the new file sat untracked — a figure that said nothing. After `git add`, it reads
**81 passed, 2 failed**: one assertion added, and it *passed*, so the new suite's writer self-call
satisfies the check. The failures stayed the same two `wired` false positives. Had the self-call
been wrong this would have been `80 passed, 3 failed`.

**No receipt, by construction.** The suite is red, and its self-call fires only at rc 0 — which,
per the point above, is not until task 8. So `TEST_EXEMPT`, exactly as the marker-gate table
anticipates for a RED commit.

### Task 7 — C GREEN (decider): 17 reds become 1, and the comparison is shown to discriminate — PASS

Measured 2026-10-16 in `~/.worktrees/.claude/trim-safety-followups`. Written by a dispatched
worker; every figure re-measured here.

| Check | Result |
|---|---|
| `python3 hooks/lib/decide-commit-gate.test.py` **before** | 11 passed, 17 failed |
| the same **after** | **27 passed, 1 failed** |
| the one remaining failure | the hook-level assertion, as task 6 predicted |
| `python3 hooks/lib/write-test-marker.test.py` | 81 passed, 2 failed — unchanged |
| files changed | `hooks/lib/decide-commit-gate.py` only; no test file touched |

**Task 6's open half is now settled: the suite is satisfiable.** 27 of its 28 assertions pass
against the real decider, so the 17 reds were never fixtures that could not build
([[feedback_falsifiable_is_not_satisfiable]]).

**The remaining failure is evidence, not a defect.** Its text is
`got rc 2 stderr 'test-marker-guard: MSG_CLASSIFIER_BAD_OUTPUT -- the decision call named a door
this version of the gate does not recognise.'` The hook already exits 2 and is already refusing —
it simply cannot name the door yet. That fallback firing **proves the decider is emitting
`MSG_STALE_PART`**, since the hook only reaches it for a door it does not know. Task 8 replaces the
message.

**The comparison was mutated here, not accepted from the report.** A rule that blocks on every
difference is equally satisfied by one that blocks on everything, so the ALLOW guards are what
carry the claim. Forcing the set difference to be non-empty
(`… | {("zz", "x")}`) gives:

| State | Suite | Which ALLOW guards |
|---|---|---|
| implementation | 27 passed, 1 failed | all pass |
| mutated | **21 passed, 7 failed** | 6 ALLOW guards **red** — the `PATHSPEC` deleted-part case, the pre-card receipt for a runner with no parts, `helper.sh` beside a receipted `R.sh`, the `.test.py` hand-made folder, the rerun-clears pair, and the fresh-receipt control |
| reverted | 27 passed, 1 failed | all pass |

`git hash-object` of the decider is `c700e0cfd763b8c06c34756d87d25f9183c3cf4d` both before the
mutation and after the revert.

⚠️ **Two guards correctly stayed green under that mutation, and that is not a hole.** The lone part
deletion and `helper.sh` staged alone form **no pair**, so no receipt is read and the comparison
never runs. They guard the classifier, not the comparison. Reading their survival as "the mutation
was absorbed" would be the error ([[feedback_a_round_trip_guard_can_absorb_every_probe]]).

**Row 2a sits after rows 1-2 and before row 3**, exactly as the spec words it. Load-bearing,
because a part *is* a `.sh` file: row 3 would classify `20-b.sh` as a subject and look for
`20-b.test.sh`, so no pair would ever form from a part alone.

⚠️ **A latent gap the spec's own row order creates, measured not reasoned.** A part whose basename
itself ends in `.test.sh` matches the parts glob but is claimed by **row 1** first:

```
tools/R.test.d/10-a.sh          is_part=True   role=('part', 'tools/R.test.sh')
tools/R.test.d/10-a.test.sh     is_part=True   role=('test', 'tools/R.test.d/10-a.sh')
tools/R.test.d/helper.sh        is_part=False  role=('subject', 'tools/R.test.d/helper.test.sh')
```

So a part named `NN-*.test.sh` derives a subject that does not exist, forms no pair, and is
**ungated** — `source_test_parts` would still source it. **Latent, not live:** `git ls-files` finds
18 parts across the 4 real folders and **none** is named that way. No fixture covers it and the
worker did not special-case it, which is right: "before row 3" is what the card says, and changing
the row order is a spec decision rather than an implementation one. Recorded for a follow-up card.

**Two deliberate deviations from the card's letter, both flagged by the worker rather than slipped
in.** (1) `PARTS_GLOB` is **not** imported — only `parts_folder_for` and `is_part`, because
`is_part` already carries the glob and importing an unused name would be dead code. The card's
intent, that the glob live in one Python place, holds. (2) `_read_parts` rejects one shape the card
does not list: a non-empty `parts` on a `.test.py` pair's receipt. That follows from the listed rule
— such a pair has no folder, so every entry is outside it — and it is an addition, never a
weakening.

**No receipt.** The suite is red by one assertion until task 8, and the self-call fires only at
rc 0, so this commit carries `TEST_EXEMPT`. The card's marker-gate table names task 7 as a commit
that lands while the decider suite is still red by construction.

### Task 8 — C hook GREEN: the new door has a message, and item C's code is complete — PASS

Measured 2026-10-17 in `~/.worktrees/.claude/trim-safety-followups`. Done in-session, not
delegated: one `case` arm in `hooks/test-marker-guard.sh`.

| Check | Result |
|---|---|
| `python3 hooks/lib/decide-commit-gate.test.py` | **28 passed, 0 failed** (rc 0) — fully green |
| `bash hooks/test-marker-guard.test.sh` | **249 passed, 0 failed** — no regression, and the file is untouched |
| files changed | `hooks/test-marker-guard.sh` only |

**The suite's own assertion checks three things — rc 2, the door name, the pair — and stops there.**
It never reads the first-difference path or the remedy, both of which the card specifies. A passing
suite therefore says nothing about most of the sentence
([[feedback_a_green_suite_cannot_validate_assert_messages]]). So the shipped message was measured
directly, by driving the real hook through the **committed suite's own fixture builders** rather
than a hand-made copy of them:

```
rc = 2
test-marker-guard: MSG_STALE_PART -- tools/R.sh|tools/R.test.sh: the receipt's part list
differs from what this commit ships (first difference: tools/R.test.d/20-b.sh).
Re-run: bash tools/R.test.sh
```

That is the card's wording, with the pair in field 4, the first differing path from field 3, and a
remedy derived from the pair's second half (`${f4#*|}`) — the decider puts the differing path in
field 3, so unlike `MSG_NO_MARKER` the runner is not handed to the hook and has to be recovered.

**The wording says only what is known, deliberately.** Three of the shapes this door blocks did not
"ship an unrun part" at all — a deletion ships nothing, and a pre-card receipt never recorded parts
that *did* run — so the message states the disagreement itself. The `*)` fallback still catches any
door a future decider invents.

**A side effect worth recording: the decider now has a real receipt, written by the feature acting
on itself.** The green run's self-call produced
`hooks/state/test-markers/hooks%2Flib%2Fdecide-commit-gate.py` naming subject
`c700e0cf…` (the committed decider) and test `de2bc6ba…` — and **no `parts` key**, which is correct:
a `.test.py` runner never has parts, so the writer did not look. The store now holds three
receipts, for `handoff-keep-guard.sh`, `phase-guard.sh` and `decide-commit-gate.py`.

**No receipt for this commit, and the reason is structural rather than incidental.**
`hooks/test-marker-guard.test.sh` never runs the writer on itself — `grep -n write-test-marker`
finds three lines, one assigning `$WRITER` and two `cp`-ing it into fixtures, and no execution — so
the pair `test-marker-guard.sh`|`test-marker-guard.test.sh` can never have one. Verified rather
than assumed, and the store listing confirms no entry exists. `TEST_EXEMPT` is set for exactly the
reason the marker-gate table gives for task 8.

### Task 9 — C docs: the gate's card and ADR 0049, with every count re-derived — PASS

Measured 2026-10-17 in `~/.worktrees/.claude/trim-safety-followups`. Written by a dispatched
worker; every figure below re-measured here, and the arithmetic checked by **set membership**, not
by the totals balancing ([[feedback_a_balanced_total_is_not_a_verified_union]]).

| Check | Result |
|---|---|
| `grep -o '_emit("BLOCK", "MSG_[A-Z_]*' … \| sort -u \| wc -l` | **9** (was 8) |
| distinct doors in `hooks/test-marker-guard.sh` (`grep -o 'MSG_[A-Z_]*' \| sort -u`) | **14** (was 13) |
| the partition | 5 bash-raised + 9 decision-call = 14, and the two sets are disjoint — checked by name, not by subtraction |
| field-4 split | 5 pair-naming + 8 dash + `MSG_NO_PYTHON` (writes no line) = 14 |
| doors that write a line | 14 − 1 = **13**, of which the decision call reports 9 and bash the other 4 |
| `git grep -nw eight` on the card | **10 lines** before (the card's own figure, confirmed), 8 after |
| `grep -nw` vs `git grep -nw` | agreed exactly |

The 8 remaining `eight`s are all either `(eight through revision 21)` annotations — history, correct
as history — or the field-4 arithmetic at `:1680`/`:1683`, which **stays** eight because
`MSG_STALE_PART` names a pair and therefore joins the five, not the eight. Both were marked rather
than left bare.

**The card's instruction was incomplete, and the worker said so rather than following it
literally.** Updating only the word "eight" would have left the file contradicting itself: the total
of thirteen doors, "twelve doors write a line", "all twelve downstream of G", the 5/8 split and
"exactly four" pair-naming doors all *derive* from that count. Each was updated with the prior figure
kept beside it. This is the single-source problem this repo keeps meeting
([[feedback_single_source_the_statement_that_keeps_drifting]]) — one rule, many spellings, and a
grep for one spelling finds a subset.

**Edits in `docs/features/verification-marker-gate.md`:** row `2a` between rows 2 and 3 of the
step-1 table with a blockquote marking the amendment and recording the latent `.test.sh`-named-part
gap; the field-2 domain to nine; a field-3/4 row for `MSG_STALE_PART`; the doors table's row 14; a
`MSG_STALE_PART` row in the decision-call Scenario Outline; and a blockquote on the receipt schema
for the `parts` key.

**One flowchart label was wrong after the worker's own edit, and is fixed here.** It added
`MSG_STALE_PART` to node `W` but left node `N` reading *"Both blobs match post-commit content?"* —
which understates the comparison now that parts are read too. It now reads *"Blobs and parts
match"*. A diagram is exactly the kind of statement that keeps its old wording while the rule under
it moves.

**ADR `0049-the-receipt-covers-the-parts-a-test-d-runner-sources.md`**, 139 lines, in the house
format of 0044/0047. Its citations were checked individually, not as a block
([[feedback_a_copied_citation_is_laundered_not_verified]]):

- `docs/decisions/0027-the-marker-is-a-receipt-not-a-grade.md:27` holds the amended sentence
  verbatim — *"A marker records `git hash-object` of the subject **and** the test file at the moment
  a suite reported zero failures."* It wraps onto `:28`, so cite the pair.
- "two blobs" is at `hooks/lib/write-test-marker.py:8` — the **writer's docstring**, not ADR 0027's
  wording, exactly as the card warned.
- `MSG_GIT_FAILED` really is emitted from 2 places, which is why the recipe counts distinct
  constants rather than call sites.
- The ADR deliberately cites function, constant and file names rather than `:NNN` anchors, apart
  from that one line, which it re-read on the day of writing.

It carries both limitations as measured, not newly invented: the `.test.sh`-named part that row 1
claims first (latent — none of the 18 real parts is named that way), and the ungated lone deletion
(the marker card's standing rule). It also states that the `dispatch-pane-agent.<concern>.test.sh`
convention stays outside the receipt, citing ADR 0044.

⚠️ **The ADR number is 0049, not the 0048 the card names, and the card's instruction is stale.**
`0048-an-install-is-vetted-then-asked-never-silently-allowed.md` is on `origin/main`, claimed by the
dependency-vetting card. `git log --all --remotes` for `0049*` and `0050*` returns nothing, so
neither is claimed on any ref. The reason this was invisible from here is worth keeping: **this
branch is behind `origin/main`**, so a local check would have called 0048 free
([[feedback_check_uniqueness_against_the_deciding_ref]]).

⚠️ **Status is `Accepted (2026-10-17)`**, matching the house form in 0047 (`Accepted (2026-09-14)`).
The worker offered `Proposed` instead; `Accepted` is right because the code is implemented and the
gate was confirmed on 2026-10-15.

⚠️ **The v1 mutation floor of 25 was deliberately not re-derived**, and the card now says so: the
same "one per door" rule would give 26. Item C's door is asserted by
`hooks/lib/decide-commit-gate.test.py`, including one assertion that drives the real hook — not by a
re-run of the 25-mutant exercise. Raising the floor belongs to whoever owns that requirement.

**No suite reads this document's contents.** The worker flagged that it had not checked. Four files
mention the path — `classify-commit-command.py`, `classify-commit-command.test.py`,
`decide-commit-gate.py`, `test-marker-guard.sh` — and all four references are **prose comments**, so
no assertion anywhere depends on these figures and nothing needed re-running.

### Task 9b — the live-checkout oracle, and a falsifier the card's own one could not give — PASS

Measured 2026-10-17 in `~/.worktrees/.claude/trim-safety-followups`. Written by a dispatched
worker; re-measured here, and the falsifier **replaced** rather than reproduced.

| Check | Result |
|---|---|
| `python3 hooks/lib/write-test-marker.test.py` before | 81 passed, 2 failed |
| after | **86 passed, 2 failed** — 5 new passes (4 per-runner + 1 runner-count assertion) |
| failures | still exactly 2, still the inherited `wired` pair |
| `hooks/state/test-markers/` | **3 receipts before and after, unchanged** |
| the check's call | `build_marker` only — `write_marker` appears nowhere but a comment |

The oracle: each split runner hands `source_test_parts` a hand-maintained literal count, measured
at `handoff-archive.test.sh:74` → 5, `live-handoff.test.sh:135` → 4,
`pre-compact-handoff.test.sh:132` → 5, `slim-session-start.test.sh:94` → 4. That integer is kept by
a different author for a different purpose, which is what makes it an oracle **neither** new module
produces. Discovery found exactly 4 runners and the check asserts that count, so a discovery bug
finding zero cannot pass vacuously.

`hooks/handoff/lib/test-parts.test.sh` is excluded on both signals — its call is
`source_test_parts "$2" "$3"`, whose folder argument does not end in `.test.d`, and it has no
`.test.d/` folder. A count that stops being a literal (`"$N"`, `$((2+3))`, absent, or two
declarations) makes the check **FAIL naming the runner** rather than skip; the worker probed all
four shapes. A trailing comment after a literal is accepted.

⚠️ **The card's prescribed falsifier does not discriminate, and saying it passed would have
overstated this check.** Pointing `parts_folder_for` at a wrong folder took the suite to 76/12 — but
**6 of those were task 4's own fixture assertions**, because that mutation breaks the writer
outright. It proves the new check *can* fail; it says nothing about the new check catching anything
the existing suites miss ([[feedback_a_round_trip_guard_can_absorb_every_probe]]).

**So a discriminating mutation was run instead: change a real runner's declared count, which no
fixture can see.** `live-handoff.test.sh`'s `source_test_parts … 4` → `3`:

| State | Suite | Failures |
|---|---|---|
| as shipped | 86 passed, 2 failed | the 2 inherited |
| runner's N mutated 4 → 3 | **85 passed, 3 failed** | the 2 inherited **plus only** `build_marker parts count matches hooks/handoff/live-handoff.test.sh's source_test_parts N` — *"source_test_parts passes 3, build_marker listed 4 part(s)"* |
| reverted | 86 passed, 2 failed | the 2 inherited |

`git hash-object` of the runner is `d7e53d895cbc0c1d5d96c4af5259d3f566d55f2e` before and after. One
assertion moved and it was this one — so the check is coupled to the real repository's declared
counts, not to the fixtures. **That is the drift it exists to catch**: a part added to a real folder
without the runner's `N` being updated.

**It persisted nothing, which is the whole reason task 5 split the function.** The receipt store
holds the same three entries before and after every run above. Had this check called `write_marker`
against the live checkout it would have stamped four genuine-looking receipts for suites that never
ran — the check meant to strengthen the gate punching a hole in it.

**What it still does not catch**, as the card already says: the four counts are 5, 4, 5 and 4, so a
derivation resolving to a *different folder of the same size* passes; and it exercises the writer's
derivation only, the decider's being covered by task 6's fixtures.

⚠️ **The current writer-suite figure is 86/2.** The marker-gate table's `70 passed, 2 failed` is a
2026-09-21 measurement and correct as history — do not read it as current.

### Task 10 — every suite re-run, every receipt checked against HEAD, and the memory NOT retired

Measured 2026-10-17 in `~/.worktrees/.claude/trim-safety-followups`, in-session.

**The five suites this card touched:**

| Suite | Result | Receipt |
|---|---|---|
| `bash hooks/phase-guard.test.sh` | **159 passed, 0 failed** | yes — written at rc 0 |
| `bash hooks/handoff/handoff-keep-guard.test.sh` | **61/61 passed** | yes |
| `python3 hooks/lib/decide-commit-gate.test.py` | **28 passed, 0 failed** | yes |
| `bash hooks/test-marker-guard.test.sh` | **249 passed, 0 failed** | **never** — the suite does not call the writer on itself, by its own design |
| `python3 hooks/lib/write-test-marker.test.py` | **86 passed, 2 failed** | **no** — rc 1 from the two inherited `wired` false positives |

So two pairs still have no receipt, each for the reason the marker-gate table gave in advance, and
neither is this card's defect: `test-marker-guard.sh` structurally cannot have one, and
`write-test-marker.py` cannot until another card fixes the `wired` body-grep that cannot see a
receipt written through `tl_finish`.

**The four real parts-bearing suites were run too, though this card did not touch them** — they are
the only pairs where the new feature has anything to do on real data, and without them task 10's
receipts would all have `parts=0` and demonstrate nothing:

`live-handoff` 69/69, `handoff-archive` 79/79, `pre-compact-handoff` 77/77,
`slim-session-start` 97/97 — all rc 0.

**The feature now demonstrably works on the real repository.** `live-handoff.sh`'s receipt names its
four parts with blobs, ordered by path, beside the subject and test:

```json
"parts": [
  { "blob": "de04b7eb…", "path": "hooks/handoff/live-handoff.test.d/10-snapshot-and-keep-envelope.sh" },
  { "blob": "c9e5f781…", "path": "hooks/handoff/live-handoff.test.d/20-library-failure-and-suppression.sh" },
  { "blob": "847d39b8…", "path": "hooks/handoff/live-handoff.test.d/30-session-identity-and-strike-survival.sh" },
  { "blob": "7c3636c6…", "path": "hooks/handoff/live-handoff.test.d/40-preexisting-and-task-bug-wording.sh" }
]
```

**Every blob in every receipt was checked against `HEAD`, not against the working tree** — 7 receipts,
26 blob comparisons, **0 mismatches**. The four parts folders carry 5, 4, 5 and 4 entries, matching
both the runners' declared counts and `git ls-files`.

⚠️ **The checker was falsified before its 0 was recorded.** A check that cannot fail reports zero
either way ([[feedback_confirm_the_check_can_fail]]). One receipt's subject blob was overwritten with
forty zeroes: the checker reported `STALE subject`, 1 mismatch, exit 1. Re-running that suite
regenerated the receipt and it returned to 0 mismatches, exit 0.

⚠️ **The memory `reference_review_phase_card_blocks_source_edits` was NOT retired, and the card's
instruction to retire it here is premature by exactly one merge.** It documents the workaround item B
removes — but hooks load from the primary checkout, never from a branch
([[reference_hooks_load_scripts_from_primary_checkout]]), and the live copy still carries the old
rule: measured today, `/Users/marksuyat/.claude/hooks/phase-guard.sh:409` still reads
`if [ "$file_phase" = "implementation" ] && [ -n "$file_branch" ]`. Deleting the memory now would
remove a workaround that is still required. The file was **annotated instead** — appended, nothing
removed — with what landed, why it is not yet in effect, and the single grep that settles when it may
go. Retiring it is a post-merge step.
