# Observability verdict — `feat/tracking-feature-state` round 11 (architecting, advisory)

- **repo:** `tracking-feature-state` (worktree `/Users/marksuyat/.claude/.claude/worktrees/tracking-feature-state`)
- **branch:** `feat/tracking-feature-state`
- **head_sha:** `7be4aec8b2337bf1b67190e16f96a72e5046cd45`
- **base:** `main` (merge-base `fe55b2d5052d85deb87283eab6c6545e17b56e40`)
- **stage:** `architecting` — advisory, does not block
- **judged artifacts:** `docs/features/tracking-feature-state.md` (326 lines, 26,308 bytes) +
  `docs/features/tracking-feature-state.spec.md` (986 lines, 72,938 bytes), both read in full from
  source
- **risk:** low · **confidence:** high

> Numbering note: the dispatch called this "round 10", but
> `2026-08-10-feat-tracking-feature-state-round10.md` already exists on disk and judges `3ca4daf`.
> This is a new judgment of a new HEAD, so it is filed as round 11 rather than overwriting that one.

---

## What was changed

Think of the feature card as a workshop manual that had grown to 1,204 lines and was being re-read
cover to cover at the start of every session, even though only the first two pages were ever needed.
Last round it was cut in half: the checklist and the "what we measured" record stay in the thin file
you always open, and the design, security rules and acceptance tests moved into a thick file you open
only when a task sends you there. This commit is the follow-up — it closes the three defects the
previous verdict named:

1. The split had **snapped a cross-reference**. The verification section said "run the pinned
   invocation above", but the pinned command had moved to the other file. The command is now written
   out in the thin half, with the thick half named as the tiebreaker if the two ever disagree.
2. A **60-second timeout on `reanalyze`** existed in one sentence, in no task and no test. It now has
   a test that makes it actually fire.
3. The **audit log's `reason` field** had no value for three of the situations it was supposed to
   record (`404`, `405`, unreadable asset), so the tests for those would have been written to match
   whatever the code happened to print — a test that cannot fail. The list is now complete and task 9
   must check the list and the status table against each other.

Diff is docs-only: two files, +43/−10.

## Does it do what was asked?

Yes, and I checked each claim rather than taking the summary's word for it.

**The split is real and lossless.** Set-differencing the pre-split card (`4775afd`) against the two
halves shows 11 lines "missing" — and every one of them has an obviously-corresponding rewritten line
in the added set (e.g. `an audit line naming the path and errno` → `whose path= carries the manifest
path and whose errno= carries the symbolic name`). Nothing was dropped in the move; the deltas are
the edits made in the same commit:

```
$ comm -23 <(sorted pre-split) <(sorted post-split halves) | wc -l   # 11, all rewritten lines
$ wc -l  → pre 1204 · post-split 303+976 · today 326+986 = 1312
```

**Session-start cost is genuinely down.** 1,204 → 326 lines (−73%), 90,079 → 26,308 bytes (−71%).
Round 9's `context_budget` **fail** stays cleared. Honest counterweight: the total across both halves
is now 1,312, i.e. **+108 lines above the pre-split card** — the split bought headroom and two
commits have already spent some of it.

**The split's own biggest risk is empirically clean.** A `<name>.spec.md` matches the
`docs/features/*.md` glob, so it could have been miscounted as a fifteenth feature card. I ran the
real analyzer against this worktree:

```
feature count: 14        # files carrying a `phase:` key: 14
spec halves counted as cards: []
files matching the glob: 16   (the 2 extras are memory-system-split.spec.md, tracking-feature-state.spec.md)
```

Criterion 1's "a spec half carries no frontmatter and is not a card" holds against the live repo, not
just on paper. `hooks/phase-guard.sh` reads the same `phase:` key between fences
(`phase-guard.sh:328,448`), so it too ignores the new file.

**The five fixes the dispatch claimed all exist in source.** `path=`/`errno=` on the audit format
(`.spec.md:399`, rationale `:402-409`); `nosniff` and the unmapped-extension abort now have task-9
assertions, the latter proven by "a `GET /` that gets no answer" (`.md:109-116`); criterion 13 now
requires a regular **and** a fill icon on screen plus a record of which view was used
(`.spec.md:865-875`); `reanalyze` timeout (`.spec.md:374`, asserted `.md:117-121`); latin-only scope
carries the user's sign-off and the `unicode-range` inversion warning (`.md:245-261`).

**Evidence I ran myself:**

```
$ uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q
53 passed in 3.95s            (exit 0 — matches the recorded 2026-08-09 measurement)

$ python3 -V → 3.9.6   uv --version → 0.11.28
$ node --version → v26.5.0   cmux --version → 0.64.20 (100) [14e3400b9]
```

All four pinned tool versions match the §Toolchain table exactly. `git status` is empty.

## What could go wrong / what I'm unsure about

**The split's reference sweep stopped at the two files, and three pointers outside them now dangle.**
This is the cross-file coherence failure the dispatch asked me to hunt, and it is outside the card:

| File | Says | Reality |
|---|---|---|
| `PORTS.md:26` | "see the Security section of `docs/features/tracking-feature-state.md`" | §Security is `.spec.md:573` |
| `docs/decisions/0022:5` | "`docs/features/tracking-feature-state.md` §Design 3 and §Security" | both moved to `.spec.md` |
| `docs/decisions/0023:5` | "`docs/features/tracking-feature-state.md` §"The output contract already exists"" | moved to `.spec.md:51` |

Low blast radius — the `.md`'s first paragraph names the spec half, so a reader recovers in one hop —
but two of the three are **ADRs**, the durable decision record, and an ADR citing a section absent
from the file it names is precisely the staleness this card exists to prevent.

**One log-format contradiction of the same species as the one just fixed is still open.**
`.spec.md:386` — "A non-zero exit is `502` with **the exit code logged server-side** (not returned)".
The one-line audit format (`.spec.md:399`) has fields for `outcome id surface sent status reason path
errno` and **no field for an exit code**, and §Audit log allows only one line per request. Task 9
mentions no exit code at all (`grep -n 'exit code' .md` → nothing). This is the identical shape as the
`path`/`errno` gap that was correctly called the best finding of round 10: a control demanded in prose
with nowhere in the contract to put it, so the test gets written to match whatever the code emits.
Pre-existing (traces to `badd4f8`), not introduced this round — but it was adjacent to the sentence
being fixed and survived the sweep.

**The `405` row is literally self-contradictory.** `.spec.md:369` — "Any method other than `GET` on
`/` or on a static-closure path, **or `POST`/`OPTIONS` on `/command`**". Read as a list of permitted
pairs it is right; read literally it makes `POST /command` — the only state-changing route in the
feature — a `405`, and it sits three lines above "`OPTIONS /command` returns `204`". A careful
implementer picks the sensible reading. This card's whole method is refusing to rely on that.

**"Bijection" is the wrong word for what is being asserted** (`.md:122`). `403` maps to four `reason`
values and `502` to three, so no bijection exists; the clause immediately after it ("each row's
`reason` a defined value, every value reachable") is the correct operational definition. Harmless if
read to the end of the sentence, a failing or quietly-weakened test if not. Related: only
`host_mismatch` is explicitly mapped to its cause in the `403` row — `bad_token`, `unknown_id` and
`origin_mismatch` are inferred by name rather than tabulated.

**Two round-10 concerns are unfixed, now on their second round:**
- `.md:199` still cites "**line 6's `support.js`**" with no re-find command, while `.spec.md:306`
  carries one. I confirmed `support.js` *is* line 6 today — and task 14 inserts a `<script>` tag
  **ahead of it**, which makes the number wrong during the very task that reads it. The bare copy is
  the one in the always-loaded half.
- `phase: planning` still coexists with tasks 1–7 `[x]` and shipped code, with no sentence in either
  half explaining it. `planning` is what permits these spec edits, so it isn't wrong — but a reader
  restoring this branch has to reconstruct that from `CODING_MEMORY.md`, and the phase gate is a
  CRITICAL gate.

**Load-bearing constants now live in both halves with no stated authority.** `8422` (md 2 / spec 5),
`30-minute` idle, `TASK_TRACKER_POLL_SECS`, `TASK_TRACKER_ANALYZE_SECS`, the 5-second timeouts, and
the pytest invocation all appear on both sides. Only the pytest line got an explicit "§Toolchain is
authoritative" tiebreak; the timeouts got none. Verbatim duplication is small (3 lines >40 chars), so
this is a drift risk rather than a present defect — but it is the "two documents describing the same
work" shape `gates.md` warns about, and the port at least has `PORTS.md` named as its source of truth.

**Ledger gap, and it is mine, not the author's:** `verdicts.jsonl` has **no entry for `3ca4daf`** —
round 10's markdown exists but its JSONL line was never appended (the run hit a spend-limit stop). I
have not fabricated a replacement line, since I did not produce that verdict and cannot honestly stamp
its timestamp. The ledger therefore under-reports this branch's judging history by one round.

**Carried, unchanged:** `analyze.py` at **792/800** lines — 8 from the hard maximum, with the
`git_facts.py` split named and deliberately unscheduled as a human-owned call (correct per
core-conduct, but the next bug fix in that file crosses the line). Criterion 13 still needs a
connected browser extension, does not run under `uv run pytest`, and does not run unattended — a
stated, accepted cost.

## What I'd double-check before merging

1. **Sweep outside the card for the split.** `grep -rn 'tracking-feature-state\.md' --include='*.md'`
   outside `docs/features/` and `coding-memory/` — three hits, all needing `.spec.md`. The two ADRs
   matter more than `PORTS.md`.
2. **Give the `cmux send` exit code a field, or delete the claim.** Either add it to the audit format
   beside `path`/`errno`, or change `.spec.md:386` to say the exit code is *not* recorded. Leaving
   both sentences standing reproduces exactly the defect this round was praised for catching.
3. **Rewrite the `405` row as an allow-list** ("`GET` on `/` and static paths; `POST`/`OPTIONS` on
   `/command`; everything else is `405`") so no literal reading turns the main route into an error.
4. **Replace "bijection"** with "total and onto in both directions", and tabulate which `reason` each
   of the four `403` causes emits.
5. **Two one-line fixes carried from round 10:** add the re-find command beside `.md:199`'s line 6,
   and add one sentence saying why the card sits at `phase: planning` with seven tasks done.
6. **Name an authority for the duplicated timeouts**, the way the pytest invocation just got one.

---

## Dimension table

| Rubric | Dimension | Verdict | Basis |
|---|---|---|---|
| Evaluation | `intent` | **pass** | All three named round-10 defects closed, each verified in source; the earlier five fixes also verified present rather than taken on trust |
| Evaluation | `execution` | **concern** | Pinned suite green (53 passed, exit 0) and all four tool pins match reality; analyzer empirically skips the spec half — but the exit-code field contradiction and the literal `405` reading are unclosed contract holes |
| Evaluation | `trajectory` | **pass** | Fixes traced to source before being made; the enum check was run against a value that should not exist to prove it could fail; +33 growth volunteered in the commit message |
| Evaluation | `regression` | **concern** | Internal refs all resolve and the split is provably lossless, but `PORTS.md:26`, ADR `0022:5` and ADR `0023:5` still point at moved sections |
| Evaluation | `context_budget` | **pass** | Session-start load 1204 → 326 lines / 90,079 → 26,308 bytes; round-9 **fail** stays cleared. Trend noted: total across halves is +108 over the pre-split card |
| Observability | `traceability` | **concern** | Derivations carry re-find commands and every `§` resolves, but `.md:199`'s bare line 6 goes stale inside task 14 itself, and `phase: planning` vs 7 shipped tasks is explained only outside the card |
| Observability | `success_masking` | **concern** | The two self-fulfilling-test traps from round 10 are properly closed; the `cmux send` exit code with no field to hold it is the same shape, still open |
| Observability | `intent_drift` | **pass** | Docs-only, two files, +43/−10; no scope creep, no drive-by edits, no dependency changes |
| Observability | `checkpoint` | **pass** | Clean tree, one focused commit, cleanly revertible; the split is verifiable as a move rather than a retype |
| Observability | `audit_trail` | **concern** | Commit message accurate and names its own falsification check, but ADRs 0022/0023 now cite sections absent from the file they name, and `verdicts.jsonl` is missing round 10's entry |

No dimension is `fail`. Round 9's `context_budget` fail remains cleared.

## Concerns

1. `PORTS.md:26`, ADR `0022:5` and ADR `0023:5` cite `§Security`/`§Design 3`/`§"The output contract"` in `tracking-feature-state.md`; all three moved to `.spec.md` — the split's sweep stopped at the card
2. `.spec.md:386` requires the `cmux send` exit code "logged server-side" while the one-line audit format has no field for it and task 9 never mentions it — same species as the `path`/`errno` gap just fixed
3. `.spec.md:369`'s `405` row read literally makes `POST /command` a `405`, contradicting the only state-changing route and the `204` OPTIONS line three lines below
4. `.md:122` says "bijection" where `403`→4 reasons and `502`→3 make one impossible; the correct definition follows in the same sentence, so a literal implementation either fails or gets weakened
5. Only `host_mismatch` is mapped to its cause in the `403` row; `bad_token`/`unknown_id`/`origin_mismatch` are inferred by name, not tabulated
6. `.md:199` still carries a bare "line 6's `support.js`" with no re-find command — and task 14 inserts a script tag ahead of it, guaranteeing the number goes stale mid-task (round-10 concern, unfixed)
7. `phase: planning` with tasks 1–7 `[x]` and shipped code is still explained only in `CODING_MEMORY.md`, not in either half (round-10 concern, unfixed)
8. Duplicated tunables across halves (`8422`, 30-min idle, poll/analyze/send timeouts) with an authority named only for the pytest invocation
9. `verdicts.jsonl` has no entry for `3ca4daf`; round 10's markdown exists but its ledger line was never appended — not reconstructed here rather than fabricate a timestamp
10. Total across both halves is 1312 vs 1204 pre-split (+108): the split bought headroom and two commits have already spent part of it
11. `analyze.py` at 792/800 lines, unchanged; `git_facts.py` split named and deliberately unscheduled
12. Criterion 13 still needs a connected browser extension, does not run under `uv run pytest`, and does not run unattended — stated, accepted cost
