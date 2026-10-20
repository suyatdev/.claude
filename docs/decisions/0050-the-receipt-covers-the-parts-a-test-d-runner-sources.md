# 0050 — The receipt covers the parts a `.test.d/` runner sources

- **Status:** Accepted (2026-10-17). Amends **ADR 0027** (§1, the rule that a marker records the
  blobs of two files); does not supersede it. The decision was specified as item C of
  `docs/features/trim-safety-followups.md`, whose planning-to-implementation gate was confirmed on
  2026-10-15.
- **Context:** `hooks/lib/write-test-marker.py` (`PARTS_GLOB`, `parts_folder_for`, `is_part`,
  `build_marker`), `hooks/lib/decide-commit-gate.py` (`_classify_role`, the part enumeration, the
  new door `MSG_STALE_PART`), `hooks/test-marker-guard.sh`, and the four parts folders under
  `hooks/handoff/`. Full design, scenarios and the measurement record:
  `docs/features/trim-safety-followups.md` § "C. The receipt names every part". The gate's own
  card, amended in the same change: `docs/features/verification-marker-gate.md`.
- **Note on the number — it moved twice, and the second time is the instructive one.** The card
  names `0048`; that was already taken on `origin/main` by
  `0048-an-install-is-vetted-then-asked-never-silently-allowed.md`. So this was written as **`0049`**
  on 2026-10-17, after `git log --all --remotes --name-only -- 'docs/decisions/0049*'
  'docs/decisions/0050*'` returned nothing on any ref. **That check was correct and still went
  stale:** on 2026-10-19, merging `origin/main` brought in
  `0049-a-pr-is-refused-while-a-registered-hook-is-stored-non-runnable.md` — a concurrent card took
  `0049` during this branch's life. Git saw no conflict, because the two files have different names.
  Renumbered to **`0050`**, re-verified free on every ref at merge time.
  **The lesson is not "check against the deciding ref" — that was done.** It is that a reserved
  number is only reserved until something else merges, so the check belongs **at merge time** as well
  as at write time, and a number collision is invisible to git. See
  `docs/features/trim-safety-followups.md` § Verification for the measurement.
- **Note on anchors:** this ADR cites **function, constant and file names**, not `:NNN` line
  numbers, apart from the single line of ADR 0027 it amends, which was re-read on the day of
  writing.

## Context

A test receipt (`hooks/state/test-markers/<urlencoded-subject-path>`) records that a suite exited 0
against specific file bytes, and `hooks/test-marker-guard.sh` refuses a `git commit` whose staged
pairs have no matching receipt. ADR 0027 states what the receipt records, at `0027…md:27`:

> A marker records `git hash-object` of the subject **and** the test file at the moment a suite
> reported zero failures.

That is two files, and for most suites it is the whole suite. It is not the whole suite for a bash
runner that splits its assertions into a folder of parts that the runner **sources**:
`<stem>.test.sh` sources `<stem>.test.d/NN-*.sh` (the glob in `hooks/handoff/lib/test-parts.sh`).
Four runners under `hooks/handoff/` do this, and their folders hold 18 parts today (5, 4, 5 and 4),
measured with `git ls-files | grep '\.test\.d/'`.

Those parts sat **outside the receipt**. A part is a `.sh` file, so the gate classified it as a
*subject* and looked for a `<part>.test.sh` that does not exist; no pair formed from a part alone.
Editing a part and committing it therefore shipped bytes that no suite had been run against, with
no error and no signal. That is the failure mode this repository keeps naming: a guard that has
stopped guarding is indistinguishable from a guard that is working.

(The phrase "two blobs" is the **writer's docstring**, `hooks/lib/write-test-marker.py`, not ADR
0027's wording. ADR 0027's wording is the sentence quoted above; the amendment is to that sentence.)

## Decision

**The receipt covers the parts a `.test.d/` runner sources.** The marker records a blob for the
subject, a blob for the test file, **and** a blob for every part in the runner's parts folder.

- **The receipt.** Version stays `1`. A new top-level key `parts` is a list of
  `{"path": <repo-relative>, "blob": <git hash-object>}` ordered by path. It is written **only when**
  the runner has a parts folder: `"parts": []` for a folder that holds no matching file, and **no
  `parts` key at all** for a runner with no folder, so every receipt already on disk stays valid for
  a runner without parts. A `.test.py` runner never has parts and the writer does not look. The
  decider reads an absent key and `[]` as **the same thing, the empty set**.
- **One glob, in one Python place.** `PARTS_GLOB` (`[0-9][0-9]-*.sh`) lives in
  `hooks/lib/parts_convention.py` beside `PARTS_DIR_SUFFIX`, `parts_folder_for` and `is_part`; the
  writer and the decider both import it through their existing loaders rather than restating the
  glob. The bash copy in `test-parts.sh` cannot share a constant, so a writer test asserts its glob
  string equals `PARTS_GLOB`. *(Amended in implementation: the convention first lived in
  `write-test-marker.py` and the decider imported it from there, which made every gate call load
  `tempfile`, `datetime` and `glob` for two pure-string helpers — a measured ~18 ms of a ~27 ms
  regression. The module keeps the "one Python place" property while costing only `fnmatch` and
  `os`. It has no sibling test by design: a `.test.py` sibling would create a pair the gate then
  demands a receipt for, and the convention is covered by the writer suite's parts assertions and
  the live-checkout cross-check below. One literal is mirrored rather than shared —
  `RUNNER_SUFFIX = ".test.sh"`, because the module cannot import the writer's `PAIR_SUFFIXES`
  without recreating the cycle — and nothing pins the two together.)*
- **Classification.** A new row `2a` in the gate's step-1 table, **before** row 3:
  `<stem>.test.d/[0-9][0-9]-*.sh` (last two path components) is a *part*, whose pair is test
  `<stem>.test.sh`, subject `<stem>.sh`. A part therefore forms the same pair its runner would, and
  step 2 (the subject must be tracked) applies unchanged. It is numbered `2a` so every existing row
  number keeps its meaning. A file under `.test.d/` that does not match the glob (`README.sh`,
  `helper.sh`) is not a part and falls through as before.
- **Comparison.** After the existing subject and test blob checks, the decider enumerates the parts
  the commit would ship, per commit form (`PLAIN` from the index; `PATHSPEC` and `ALL` from disk for
  paths in the set and from `<base>` for the rest, `ALL` also dropping a part missing on disk) and
  compares them to the receipt's `parts` **as a set**. Any difference blocks with a new door,
  **`MSG_STALE_PART`**, field 3 naming the first differing path in sort order, field 4 the pair.
- **A malformed `parts` is a malformed receipt.** Present but not a list, an entry that is not an
  object, a missing or non-string `path` or `blob`, a `blob` failing the existing blob regex, a path
  not under this pair's `<stem>.test.d/` folder or not matching the glob, a duplicate path, and (an
  addition found in implementation) a non-empty `parts` on a `.test.py` pair's receipt, all land on
  the existing `MSG_BAD_MARKER`, before any comparison.
- **The hook's message says only what is known.** `MSG_STALE_PART -- <pair>: the receipt's part
  list differs from what this commit ships (first difference: <path>). Re-run: bash <test>`.
  Three of the shapes the door blocks did not ship an unrun part at all (a deletion ships nothing; a
  receipt written before this change never recorded parts that did run), so the message states the
  disagreement and does not claim a cause.

The door count the decider can emit rises from eight to nine distinct constants, and the gate's
total from thirteen to fourteen. The recipe is the marker card's own:
`grep -o '_emit("BLOCK", "MSG_[A-Z_]*' hooks/lib/decide-commit-gate.py | sort -u | wc -l`, which
counts distinct constants rather than call sites (`MSG_GIT_FAILED` is emitted from two places).

### What the receipt asserts about a part

The same thing it asserts about the runner, and no more: *these bytes were present when the suite
exited 0.* That the folder beside a runner is sourced **by** that runner is a convention, not
something the writer observes. It holds for all four folders today, and a separate check (task 9b of
the card) compares the writer's part count against the integer each runner passes to
`source_test_parts`, which is what would notice the convention failing.

## Not covered, and the reason

**The `dispatch-pane-agent.<concern>.test.sh` convention stays outside the receipt.** ADR 0044
splits `panes/dispatch-pane-agent.test.sh` differently: six sibling suites, each a complete `.test.sh`
file in `panes/`, invoked **by explicit name** from a runner that keeps the paired name. That is not a
`.test.d/` folder of sourced parts, it has no `NN-` prefix and no glob, and this ADR's mechanism does
not read it. It is a different splitting convention with its own settled answer (ADR 0044), and
nothing here changes it.

## Limitations

Both are already recorded in the card's Verification (tasks 7 and 8) and restated here as measured
there, not as newly found.

1. **A part whose own basename ends in `.test.sh` is ungated.** Row 1 of the step-1 table (basename
   ends `.test.sh` → test) claims it before row 2a is reached. Measured in the card's task 7:
   `tools/R.test.d/10-a.test.sh` classifies as `('test', 'tools/R.test.d/10-a.sh')`, a subject that
   does not exist, so it forms no pair, while `source_test_parts` would still source it. **Latent, not
   live:** all 18 parts across the 4 real folders were checked and none is named that way. No fixture
   covers it and the implementation deliberately does not special-case it: "before row 3" is the
   specified position, and moving row 2a ahead of row 1 would be a spec decision, so it is left for a
   follow-up card rather than slipped in.
2. **A lone part deletion is not gated.** A commit staging only the removal of a part forms no
   pair, so no receipt is read. This is the marker card's standing rule, unchanged: every path
   collector passes `--diff-filter=d` and the marker card states "removing a file needs no test run"
   and pins it with its own scenario. Removing the runner itself is ungated for the same reason. The
   deletion **is** caught when the part's subject is also in the commit (`PLAIN` and `ALL` forms), and
   deliberately not under a `PATHSPEC` that names the part, where the base tree still holds it.

## Consequences

- Editing a part and re-running the suite refreshes the receipt; committing the edit without
  re-running blocks with `MSG_STALE_PART` and a remedy. This is the gap the decision exists to close.
- **Receipts written before this change are stale by definition for a runner that has parts.** A
  version-1 receipt with no `parts` key reads as the empty set, so the first commit touching such a
  pair blocks once and is cleared by re-running that suite. For a runner with no folder, an absent key
  is exact, and nothing on disk is invalidated.
- The receipt is still a receipt and not a grade (ADR 0027 §1): a part gutted to `exit 0` earns a
  valid receipt. This decision widens *which bytes* the receipt names, not what a green run proves.
- The step-1 table gains its first row that matches on two path components instead of the basename;
  the marker card says so beside the table.
- `docs/features/verification-marker-gate.md` carries every figure this changes (row 2a, the field-2
  domain, the doors table, the Scenario Outline, the receipt schema), each marked as this card's
  amendment with the prior figure kept beside it. Its v1 mutation floor of 25 was **not** re-derived
  and says so.
