# Observability verdict — statusline wrap + worktree name (round 3, delta only)

- **Repo:** statusline-wrap-worktree (isolated linked worktree)
- **Branch:** `feat/statusline-wrap-worktree`
- **HEAD:** `64e66220bfa67e8910345b49d8930254b7c9bc0f`
- **Stage:** implementation
- **Judged:** 2026-08-07T04:22:10Z
- **Delta under review:** `64e6622` (four follow-ups from the round-2 pass at `66cb17e`)
- **Prior rounds:** `dbf1bbc` (round 1), `66cb17e` (round 2) — both risk=low/confidence=high
- **Tests:** 68/68, run twice by me on a clean tree

---

## What was changed

Four follow-ups from the last review, and only those.

Exactly **two lines of executable code** were deleted: a counter called `lines_emitted` that
used to enforce a maximum row count. The cap itself was removed a commit earlier, so the counter
had been quietly counting into the void ever since. Nothing read it. It is gone.

Everything else in the commit is words and tests: a new test that checks the status line never
uses more rows than it has pieces to show, an ADR paragraph replacing a specific number ("38
cells") with the rule that number came from, an ADR paragraph saying out loud that a missing
`wt:()` badge must never be read as "you are safe", and the two previous review verdicts
finally committed to the repo.

## Does it do what was intended?

Yes, on all four counts, and I checked each one rather than taking the commit message's word.

**The counter deletion is behaviour-neutral — measured, not assumed.** I extracted the script
from the previous commit and from HEAD and ran both against the same input across 77 terminal
widths each (every width 0–70, plus 100, 150, 999, and the degenerate values `abc`, empty and
`-5`) for two shapes: a plain directory and a real linked worktree with a long head. That is
**154 paired runs, compared byte-for-byte including stderr** (`od -An -c` on the combined
streams). **Zero mismatches.** This is consistent with reading the code: the variable was
written twice and read nowhere, the script has no `eval`, no indirect `${!var}` expansion, and
no `set -u`, so its removal cannot be observed.

**The ADR's new rule is correct in a third fixture.** The ADR now says the real bound is "the
width of the widest single segment", with 38 and 44 marked as fixture-specific. In my fixture
the widest segment is the 29-cell head; I swept widths 14–46 measuring the widest rendered line
and the overflow stops **exactly at 29**. The rule generalises; the numbers do not, which is
precisely what the ADR now says.

## What could go wrong

**The new row assertion is real but loose, and I can prove both halves.**

It is *not* vacuous. I mutated the packing loop so a segment gets split across rows — the exact
failure the bound exists to forbid — and the assertion fired (11 rows > 8). Good canary.

But it has two rows of slack, because the fixture it uses only produces **six** segments while
the assertion allows **eight**. To size that gap I introduced a plausible off-by-one: dropping
the `[ $i -gt 0 ]` guard, which makes the first segment trigger a break and emit a spurious
blank leading row at narrow widths. That mutant produces 7 rows — and **passes all 68 tests**,
the new assertion included. I ran the full suite against it to confirm.

| script | rows at COLUMNS=24 | assertion `rows <= 8` |
|---|---|---|
| HEAD (unmodified) | 6 | passes |
| mutant A — `i > 0` guard dropped (blank leading row) | 7 | **passes** (full suite 68/68) |
| mutant B — segment split across rows | 11 | fails, correctly |

The claim in the commit message that width 24 "forces the maximum number of breaks" is **true
for that fixture** — I swept every width and rows plateau at 6 across widths 14–31 — but 6 is
the fixture's ceiling, not the asserted one. The case where the bound is genuinely tight is a
payload carrying `session_id` and `rate_limits.seven_day`, which produces all eight segments; I
measured that shape hitting **exactly 8 rows at COLUMNS 14–20**. The bound holds there. No test
goes there.

So the assertion is a useful guard against gross breakage and a weak guard against off-by-one.
That is a smaller claim than "the row bound is now asserted rather than claimed" implies.

**Documentation drift, small but reader-facing.** The feature file was not touched by this
commit, so at HEAD its checklist still says task 7 "**66/66**" (the suite is 68) and leaves task
8b unticked although round 2 finished and its verdict is committed in the same commit. Not
editing a checklist mid-implementation is what the phase rule asks for, so this is a merge-time
reconciliation item, not a violation. Related: the commit body says the `wt:()` safety caveat
"was missing from both the spec and the ADR" and then adds it to the ADR only — defensible,
since feature-file task 10 already carries the substance and the ADR is the durable artifact,
but the commit says "both" and fixed one.

**Carried, untouched by this delta.** `COLUMNS` longer than 19 digits still prints
`/path/statusline-command.sh: line 741: [: …: integer expression expected` to stderr on every
render — I reproduced it at HEAD. Stdout is unaffected (1 row, correct fallback), so it fails
safe, and it fails safe by evaluation order rather than by design. Raised in rounds 1 and 2,
still open. Injection cases also remain pinned to `COLUMNS=400`, so injection × wrapping stays
untested in-suite (round 2 probed it externally clean). Tasks 9 and 10 are deferred with written
rationale and are not re-reported here.

## What I'd double-check before merging

1. Decide whether the row assertion should be tightened — asserting against the fixture's own
   segment count (6) rather than the global ceiling (8), or adding the full eight-segment
   payload where the bound is tight. Either closes the 7-row blind spot. Cheap; not blocking.
2. Reconcile the feature-file checklist (66/66 → 68/68, tick 8b) when the branch moves to
   review, so the merge-time reader is not looking at stale counts.
3. Confirm you are content that the `wt:()` caveat lives in the ADR alone.
4. The stderr noise on absurd `COLUMNS` values is cosmetic and safe, but it has now survived
   three rounds unlogged as a task. Either triage it or write it down.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| `intent` | pass | All four named follow-ups applied; each verified independently, not read off the commit message. |
| `execution` | pass | 68/68 run twice by me on a clean tree; `shellcheck -x` clean on the script (rc=0); 154-run byte-level differential old-vs-new, 0 mismatches. |
| `trajectory` | pass | Reasoning is explicit and mostly correct; the "maximum breaks" claim is true of the fixture but conflates its 6-segment ceiling with the 8-row bound asserted. |
| `regression` | pass | Output byte-identical across 154 width/payload pairs incl. stderr; only statusline files and docs touched; `git revert HEAD` applies cleanly. |
| `context_budget` | pass | Nothing always-on added. ADR, tests and 336 lines of verdict markdown all live in on-demand paths. |
| `traceability` | pass | Commit body explains every change and its reason; ADR now states the rule instead of a fixture number, verified correct in a third fixture. |
| `success_masking` | **concern** | New assertion has 2 rows of headroom: a plausible off-by-one yielding a spurious blank row (7 rows) passes all 68 tests — measured. The tight 8-segment case is untested. Injection × wrapping still pinned to COLUMNS=400. |
| `intent_drift` | pass | Exactly the four follow-ups plus the verdict files `doc-guard` flagged. No drive-by edits, no dependency changes. |
| `checkpoint` | pass | Clean working tree, single self-contained commit, revert verified to apply without conflict, 2-line code footprint. |
| `audit_trail` | pass | Attributable commit with `Co-Authored-By`; both prior verdicts committed; `verdicts.jsonl` parses (105/105 lines valid JSON); the two new verdict files carry **no** absolute `/Users/...` paths, avoiding a recurring repo defect. |

**Risk:** low **Confidence:** high

## Concerns

- New row assertion has 2 rows of slack: fixture yields 6 segments, bound asserts ≤8; a mutation dropping the `i > 0` guard (spurious blank leading row) gives 7 rows and passes all 68 tests — measured, full suite run against the mutant
- The tight case is untested: an 8-segment payload (`session_id` + `rate_limits.seven_day`) hits exactly 8 rows at COLUMNS 14–20; no test exercises it
- Commit's "width 24 forces the maximum number of breaks" is true of the fixture (rows plateau at 6, widths 14–31) but that ceiling is the fixture's, not the asserted bound's
- Feature-file checklist stale at HEAD: task 7 still reads 66/66 (now 68), task 8b unticked though round 2 completed and is committed in this same commit
- `wt:()` safety caveat landed in the ADR only; the commit body says it was missing from the spec too and the spec still does not state it (task 10 carries the substance)
- Carried, reproduced at HEAD, unaddressed: COLUMNS >19 digits prints `[: integer expression expected` to stderr from :741 every render; stdout fails safe to 1 row, by evaluation order not design; raised rounds 1 and 2
- Carried from round 2: injection cases pinned to COLUMNS=400, so injection × wrapping remains untested in-suite
- VERIFIED BY ME at 64e6622: `lines_emitted` deletion is behaviour-neutral — 154 paired runs across widths 0–70/100/150/999/`abc`/empty/`-5` and absent-COLUMNS, two payloads, stdout+stderr compared byte-for-byte, 0 mismatches; no `eval`, no `${!var}`, no `set -u` in the script
- VERIFIED BY ME: ADR 0018's new rule ("bound = widest single segment") holds in a third fixture — widest segment 29 cells, overflow stops exactly at COLUMNS=29
