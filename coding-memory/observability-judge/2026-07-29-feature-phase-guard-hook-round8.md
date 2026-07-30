# Observability verdict — RUN 8 · `feature/phase-guard-hook`

- **ts:** 2026-07-29T13:41:38Z
- **repo:** `phase-guard-hook` (linked worktree at `/Users/marksuyat/.claude/.claude/worktrees/phase-guard-hook`)
- **branch:** `feature/phase-guard-hook`
- **head_sha:** `5cb0985a48d581a7859c2f1fdd6f13a20f8f4561`
- **stage:** implementation (gates the PR)
- **base:** `main` @ `8f0f16d` (true merge-base; `origin/main` @ `c562594` deliberately not used)
- **risk:** medium · **confidence:** high

## Evidence I gathered myself

- `bash hooks/phase-guard.test.sh` → **125 passed, 0 failed** (10.3s wall). Run at this HEAD.
- `shellcheck -x hooks/phase-guard.sh hooks/phase-guard.test.sh` → **clean, exit 0**.
- Read `hooks/phase-guard.sh` in full (543 lines) and compared its ten `# --- Step N` headers
  against every step reference in the doc (52) and the suite (36).
- Raw diff of `7f2fc9e` through `rtk proxy` after confirming the default `git show` path was being
  filtered — the filtered read had shown *zero* table edits, which was wrong.
- Verified the self-disclosed limitations directly rather than accepting them.

---

## What was changed

A safety catch for the workflow. Every feature has a card with a `phase:` on it — `planning` means
"we're still deciding", `implementation` means "go ahead". Until now that was an honour system: the
card said planning, but nothing stopped anyone writing code anyway.

This branch adds `hooks/phase-guard.sh`, which runs automatically before every file write. If the
repo that owns the file being written has a card still sitting at `planning`, and the current branch
hasn't been named on any card as approved, the write is refused with an explanation. Docs, memory
files and the card itself are always writable, so you can never lock yourself out — the way to open
the gate is to edit the card, which is never blocked.

This round specifically was cleanup: closing the four problems the previous judge found.

## Does it do what you wanted?

Mostly yes. The **code** is in good shape — 125 tests pass, the shell linter is clean, and the
behaviour is correct as far as I can test it. Three of the four previous findings are genuinely and
thoroughly closed, one of them (the false performance claim) unusually well: the wrong text is left
in place with a "⚠️ superseded" stamp and a correction, rather than quietly deleted.

But the fourth one — the one you specifically asked me to hunt in — is **not closed, and the attempt
to close it introduced a new error.** Details below.

## What could go wrong / what I'm unsure about

### 1. F2 is reported as closed. It is not. (carried, unfixed)

The RUN 7 verdict named two sites verbatim: *"two suite comments still say 'step 4' for the
interpreter check, one directly above a label reading 'step 2'"*. Those are
`hooks/phase-guard.test.sh:649` and `:671`. **Both are unchanged at HEAD.**

```
649:  # ... awk/sed/head are included though step 4 exits before them ...
671:  # A2.1 — step 4, the no-interpreter exit. ...
673:  with_path "$NOPYBIN" allow_audible "A2.1 no interpreter says so (step 2)" \
```

Line 671 and line 673 contradict each other two lines apart. The commit that claims to close all
four findings, `7f2fc9e`, changed **one file** — `docs/features/phase-guard-hook.md`. It never
touched the suite where the reported defect lives. The no-interpreter exit is at code step 2
(`hooks/phase-guard.sh:149`).

### 2. The F2 fix introduced a new numbering error — the same shape as F2 itself

`7f2fc9e` remapped the audit table's Step column mechanically, applying the old→new mapping
(old 2 = repo resolution → new 4) row by row. It hit a row where that mapping does not apply:

```
-| No `git` on PATH | 2 | Guard off in *every* repo until PATH is fixed | A4.5 |
+| No `git` on PATH | 4 | Guard off in *every* repo until PATH is fixed | A4.5 |
```

That row's "2" referred to the `command -v git` **binary check**, which the reorder left *at* step 2
— it was never the `git rev-parse` call that moved. **The row was correct before the fix and is
wrong after it.** Three independent things in the repo contradict the new value:

- `hooks/phase-guard.sh:148` — `command -v git` sits under `# --- Step 2: the tools this hook
  cannot run without`.
- `hooks/phase-guard.sh:93` — the hook's own comment: *"It was silent purely because **step 2**
  predates the opt-in test."*
- The doc's own prose immediately above the table: *"a missing `git` or `python` speaks even though
  it is **upstream of the opt-in test**"* — the opt-in test is step 4, so "4" contradicts it.
- The very next table row, `| No python interpreter | 2 |`, describes the adjacent line of the
  **same step-2 block**. Two lines of one block cannot be steps 4 and 2.

This is worth naming precisely because the same commit records the lesson it violates: *"an
enumeration entry naming a `git` failure mode is one row per **condition**, not one per **exit**."*
The remap was applied per row, not per condition.

### 3. Two numbering schemes now coexist for steps 2–4

The doc's canonical Order-of-operations list and the code's own section headers disagree:

| | doc list | code headers |
|---|---|---|
| interpreter check | step 2 | step 2 |
| `command -v git` | *absent from the list entirely* | step 2 |
| payload JSON parse | step 2 | step 3 |
| walk-up + `pwd -P` (NORESOLVE) | step 3 | step 4 (first half) |
| `rev-parse` + opt-in test | step 4 | step 4 (second half) |

Steps 5–10 agree in both. The consequence is live: the audit table follows the **doc** numbering
(`Payload unreadable | 2`, `Write target unresolvable | 3`) while the tests it cites in its own
"Pinned by" column follow the **code** numbering (`A1.4 … (step 3)`, `A1.5 … (step 3)`). Follow the
table into the tests, or the tests into the doc, and you land on the wrong step either way.

### 4. Four further unmarked old-ordering sites in the suite, beyond the two RUN 7 named

- `:395` — *"otherwise **step 2**'s `rev-parse --show-toplevel`"* → now step 4.
- `:814` — *"the case would pass at **step 3** for entirely the wrong reason"* (the opt-in test) → now step 4.
- `:870` — *"docs/features/ exists, so **step 3** says the repo opted in"* → now step 4.
- `:976` — *"**step 3** has already passed, so the rule says it speaks."* This one is worse than a
  stale number: it states now-**wrong reasoning**. Under the shipped order the NORESOLVE exit is
  *upstream* of the opt-in test, and it speaks via `warn_if_cwd_opted_in`'s cwd fallback — not
  because any opt-in test passed.

(`:989` uses past tense to describe the bug and reads correctly as historical. Not counted.)

### 5. Secondary question — F3's fix is sound; its stated rationale is unpinned

The discrimination logic is correct. `hooks/phase-guard.sh:226-239` walks up testing
`[ -e "$probe/.git" ]`, which answers "is this a repo?" without reading it, terminates at `/`, and
emits a message (`NOREPOREAD_MSG`) distinct from every other reason. A7.2/A7.3 **do** assert the
absence of a flag file, not merely absence of output — the "silence is real" control is genuine as
claimed.

But the comment's central justification — that it *deliberately* avoids `warn_if_cwd_opted_in`
because that helper fails whenever cwd and target are the same unreadable repo, *"the common shape
of this case"* — has **no test**. A7.1 runs with cwd = `$OPTED`, a readable, opted-in repo. Swap the
walk-up for `warn_if_cwd_opted_in` and A7.1 still passes. The exact scenario the fix exists for is
untested.

Two minor notes: the walk-up stops before testing `/.git`, so a repo at filesystem root goes
undetected (negligible); and it forks one `dirname` per path level on every write that lands
**outside any repo** — a new cost on a path none of the recorded figures (11→38 ms, 35→41 ms, both
*inside* repos) covers.

### Limitations I verified rather than rediscovered — all confirmed as stated

- **Day-one impact nil.** `git ls-tree -d origin/main docs/` returns only `docs/decisions` and
  `docs/superpowers` — no `docs/features/`. The single card on this branch is `phase: review`.
  Confirmed: nothing denies on merge.
- **Registered, not armed.** `settings.json` adds a *fourth* `PreToolUse` block, no existing block
  edited. `.gitignore` scopes `/hooks/state/`.
- **No bypass variable.** Confirmed in code. `PHASE_GUARD_STATE_DIR` redirects the warn-once flag
  store only; it cannot suppress a deny.
- **Fails open everywhere but the final deny.** Confirmed by reading every exit. Nothing here can
  cause a false block.
- **Rollback path 3 (exit 126)** — I did not test it either. Correctly left open.

## What I'd double-check before merging

1. **Fix the `No git on PATH` audit row: `4` → `2`.** It is the only row wrong in *both* numbering
   schemes, and the previous fix put it there.
2. **Actually close F2** — `phase-guard.test.sh:649` and `:671`, the two sites RUN 7 named. Then
   `:395`, `:814`, `:870`, and especially `:976`, whose *reasoning* is now wrong.
3. **Pick one numbering and state it once.** Either renumber the doc's list to match the code's ten
   headers, or add a two-line mapping note. Three schemes in one feature is what produced findings
   F2, 2, 3 and 4.
4. **Add NOGITBIN to the Order-of-operations list.** A shipped audible exit with a test (A4.5) and a
   table row appears nowhere in the canonical algorithm.
5. **Add one A7 case with cwd inside the unreadable repo**, so the reason the F3 fix is shaped the
   way it is cannot be refactored away silently.
6. Before claiming a finding closed, `git show --stat` the closing commit and confirm it touched the
   file the finding named. Here it did not, and the claim reached this round as fact.

---

## Dimensions

| Rubric | Dimension | Verdict | Basis |
|---|---|---|---|
| Evaluation | `intent` | **concern** | 3 of 4 RUN 7 findings genuinely closed; F2 reported closed but its two named sites are unchanged at HEAD. |
| Evaluation | `execution` | pass | 125/125 tests pass and shellcheck is clean, both run by me at this HEAD. No behavioural defect found; every defect is in the explanatory layer. |
| Evaluation | `trajectory` | **concern** | The F2 remap was applied per-row rather than per-condition — the exact error the same commit records as its lesson — and introduced a new wrong row. "All four closed" was asserted without checking the named file. |
| Evaluation | `regression` | pass | No behavioural regression. Fourth `PreToolUse` block added without editing existing ones; `.gitignore` scoped; day-one impact verified nil. |
| Evaluation | `context_budget` | pass | +64 words to always-on `rules/gates.md` (1053 of a 2130-word always-on set). Dense but proportionate for a Tier 1 gate, and it correctly discloses the guardrail-not-boundary limit and the absence of a bypass. |
| Observability | `traceability` | **concern** | Strong in most respects — ADR 0011, superseded-in-place stamps, live-run record, judge history. Undercut by three mutually inconsistent step-numbering schemes across the doc, table, tests and code comments, which is the artifact a future maintainer navigates by. |
| Observability | `success_masking` | **concern** | 125 green tests coexist with a wrong audit row and six stale labels; the suite cannot detect doc/code numbering drift by construction. Second consecutive round where green tests accompany a doc contradicting the code. A7.1 would also pass under the implementation its own comment rejects. No unbounded or expensive loops. |
| Observability | `intent_drift` | pass | Tightly scoped. Every commit maps to a RUN 7 finding or a prior task. No drive-by edits, no new dependencies; the `rules/gates.md` touch is a one-line stub amendment the feature requires. |
| Observability | `checkpoint` | pass | Clean test→fix→docs commit triplets throughout; revert points obvious; rollback documented with path 3 honestly withdrawn rather than papered over. |
| Observability | `audit_trail` | **concern** | Attributable and ADR-backed, and the F4 credit correction cuts against self-interest. But the record asserts four findings closed when one is not — an accuracy defect on a branch whose value proposition is record integrity. |

## Concerns

1. F2 reported closed but unfixed: `phase-guard.test.sh:649` and `:671` — the two sites RUN 7 named verbatim — are unchanged at HEAD; `7f2fc9e` touched only the doc.
2. The F2 fix introduced a new error: the `No git on PATH` audit row was moved 2 → 4 by a mechanical remap; it was correct at 2 and is contradicted by `phase-guard.sh:148`, `:93`, the doc's own prose, and the adjacent table row.
3. Two coexisting numbering schemes for steps 2–4: the doc's Order-of-operations list vs the code's section headers; the audit table follows one and the tests it cites follow the other.
4. Four further unmarked old-ordering references in the suite (`:395`, `:814`, `:870`, `:976`); `:976` states now-wrong reasoning, not merely a wrong number.
5. `command -v git` / NOGITBIN is absent from the canonical Order-of-operations list despite having a test (A4.5) and an audit-table row.
6. F3's stated rationale for avoiding `warn_if_cwd_opted_in` is unpinned — A7.1 runs with cwd in a readable repo and would pass under the rejected implementation.
7. New unmeasured cost: one `dirname` fork per path level on every write landing outside any git repo; recorded figures cover only in-repo paths.
8. Carried and still open by design: rollback path 3 (exit 126) deliberately unverified; parallel-worktree collision unresolved; branch-granularity hole; stale-card lockout of `main` and hotfix branches until merge.
