# Observability verdict — replay harness base pin, revision 8 (architecting, round 6)

- **repo:** `.claude` · **branch:** `main` · **head_sha:** `5bc39b917832d209ff4e2dca873d666c2fc9d402`
- **stage:** architecting (advisory — does not gate the PR)
- **spec:** `docs/features/replay-harness-base-pin.md` revision 8, blob `5577a48e` (matches dispatch)
- **ts:** 2026-08-05T13:11:19Z
- **risk: medium · confidence: high**

> **filename note:** rounds 1–2 at `2026-08-04-main-replay-harness-base-pin*.md`, rounds 3–5 at the
> `…-round3/4/5.md` siblings. Spec slug + round suffix kept so the six reads stay contiguous and no
> read overwrites another on the same date+branch. JSONL `branch` stays the raw `main`.

> **Method note — a measurement artifact I caught in my own tooling.** My first history sweep
> reported `0 of 66` commits referencing `lib/`, which would have made Scenario L's premise false.
> It was wrong: `git show "$c:hooks/git-guard.sh"` in this shell is mangled to `.ooks/git-guard.sh`
> (verified: the `h` after the colon is eaten), so every `git show` silently produced nothing and
> every count came back 0. The brace form `"${c}:hooks/…"` — the workaround the round-3/4 reads
> already recorded — is unaffected, and I proved it can *fail* before trusting it (absent path →
> `fatal: path … does not exist`, rc≠0; HEAD guard → 3 matches). All numbers below are from the
> brace form. Every `cmp` probe likewise shown able to return all three outcomes.

---

## What was changed

Still a spec — no code, no branch. `phase: planning`, `branch: none`, working tree **clean** (round
5's stray `agents/pane-echo.md` deletion is resolved). Hooks are byte-identical between the plan base
`c461e4c`, round-5 HEAD `2d865fd`, and today's `5bc39b9` (verified: empty diff over `hooks/`), so all
line citations and measured rows carry forward. Re-confirmed against the live harness: `WT="$1"` at
`:6`, `UNDER_TEST` at `:7`, the three `git show main:` at `:13-15`, the comparison at `:125-131`, the
hard-coded `main` in the header at `:134`, and `grep -cE 'BASE_REV|getopts|\$\{3'` → **0**.

Revision 8 is a single fix on top of the round-7 compliance pass, taken knowing it voids that pass:

1. **A side's file set is now *defined*** — part 2's required set (guard always; the two helpers only
   if that side's guard references `lib/`), with presence on disk explicitly *not* conferring
   membership. Part 2 now says part 3 **reuses** the rule rather than paralleling it.
2. **Membership is read from the executing bytes** — for `UNDER_TEST=worktree`, from the on-disk
   guard, not `git show HEAD:`.
3. **Scenario L added** as the falsifier for the disk reading; Scenario H updated to cover it.
4. **Two history counts re-measured**, `629` → `631`, and deferred item 2's weakened rationale
   recorded in the non-goals.

## Does it do what you wanted?

**Yes — this is exactly the one sentence round 5 asked for, and the fix is correct.** Verified
directly rather than read:

- **Scenario L genuinely falsifies the disk reading** (the dispatch's question 2 — and the answer is
  not the same as for A–K). Under raw-presence membership, L's base set is `{guard, lib/a, lib/b}`
  and the candidate's is `{guard}`; the sets differ, the refusal never fires, and the matrix runs one
  program against itself under a valid 40-character SHA. Under the referenced-set rule, both sets are
  `{guard}`, the bytes match, and the run is refused. L asserts the refusal, so the two readings give
  opposite results. It discriminates.
- **L's premise holds against the full history, re-measured myself.** Of **632** commits, 492 carry a
  self-contained guard; **66** carry the guard alongside at least one helper and **all 66** reference
  `lib/`; symmetrically **66** guards reference `lib/` and **all 66** carry both helpers. Exactly two
  clean populations, **zero** commits of either mixed shape — so Scenario J's and Scenario L's bases
  must be synthesized, as the spec says.
- **The load-bearing measured facts reproduce.** `cmp -s`: identical → 0, differ → **1**, both absent
  → **2**, one absent → **2**. `e3b09ba`'s guard: **0** `lib/` occurrences, helper genuinely absent
  (rc 128). `286fd5a`: guard itself absent (rc 128), so Scenario E is independent of the helper rule.
  `f5c5689` vs HEAD: all three blobs identical (`2b74507c` / `2f8af693` / `b8fed461`) — the
  rev-string falsifier is real.
- **Round-5 follow-ups closed:** `CODING_MEMORY.md` revision pin and the `:56` → `:74-77` pointer
  were both fixed at `60faae1`; the round-3/4/5 verdicts are committed; the working tree is clean.

## What could go wrong / what I'm unsure about

**The dispatch's headline question — did the fix introduce the next hole? — the honest answer is
yes, three times, all smaller than the one it closed, and none of them a rule hole.**

### 1. The disk rule is now stated twice, and revision 8's own remedy was not applied to it

Revision 8 correctly diagnosed the drift mechanism — *a rule stated in two places drifts* — and fixed
the part-2/part-3 duplication by defining membership once and pointing at it. Then, in the same
revision, it created a **new duplication inside part 3**:

- `:141-142` — membership is read from the executing bytes; for `worktree`, from the on-disk guard.
- `:167-170` — byte comparison is read from the executing bytes; for `worktree`, from disk.

That is one principle at two sites, 26 lines apart. The spec asserts "so the two cannot diverge"
(`:464`) — but that is an argument about implementation consistency, not about the prose, and the
prose is what drifted for five straight rounds. The "one definition + an explicit *reuses* pointer"
treatment was applied to the part-2/part-3 pair and **not** to this pair, in the same edit. It is one
invariant today; nothing in the document keeps it one.

Worse: **neither site is pinned by any scenario.** The on-disk-is-truth claim only becomes observable
when the worktree is dirty, and a dirty-worktree scenario is deferred item 1 ("still untested. The
strongest of the five"). Revision 8 added a **second consumer** of the spec's single most-argued,
least-tested claim. The non-goals record that item 2 got *cheaper*; they do not record that item 1
got *heavier*. That asymmetry is the finding.

### 2. Part 3 now asserts a guarantee that is false in the default mode

`:152-155`, presented as the load-bearing justification:

> part 2 has already proved every member of each side's set extracted non-empty, and `cmp` runs only
> once the two sets are found equal, so it is only ever called on paths present on both sides.

Part 2's scope is stated at `:105-106` as **six `git show` calls — three for the base, three for a
rev candidate**. In the *default* `worktree` mode there is no candidate `git show` at all, and
deferred item 2 says so explicitly: the candidate's own helpers are **not** validated. So the premise
does not hold on the one side that runs by default.

Traced concretely: worktree guard references `lib/`, `$WT/hooks/lib/shell_segments.py` missing. Both
sets are `{guard, a, b}` — membership is by *requirement*, and presence is explicitly irrelevant — so
the sets are equal and `cmp` is invoked on a path absent on one side. I measured that case: `cmp -s`
with one path absent exits **2** (the spec only ever states the both-absent case). 2 ≠ 0, so "not
identical", so not vacuous, so the matrix runs — and the candidate exits 2 on every command, so
`relaxed` is 0 by construction, exit 0, now decorated with a valid 40-character SHA.

**The behaviour is unchanged from revision 7** (the presence reading reached the same false pass by a
different route), and the underlying gap is recorded as deferred item 2 / limit 2. What is new is the
*claim* that it cannot happen. An implementer who believes that sentence has no reason to add a
guard, and a reviewer who believes it has no reason to look.

### 3. Scenario L is not in the task that verifies scenarios

Task 7 (`:441`) still reads **"Verify scenarios A-K by execution"**. Scenario H was updated to include
L; task 7 was not. The scenario added *specifically* to kill the disk reading is absent from the
acceptance step, so an implementer working the checklist would never execute it. Task 4 does say to
synthesize L's base, so a careful implementer would notice — but "the scenario list and the
verification task disagree within one revision" is precisely the failure class this spec exists to
name.

### 4. Answering the dispatch's third question: no, the output is not sufficient — and the SHA does help it look audited

After part 5, the **five enumerated routes are distinguishable**: 1 refuses, 2/3/4 raise named errors
with no pair-count line and non-zero exit, and 5 is closed by printing the resolved SHA. That much
works. But:

- **The candidate side is still anonymous.** `:134` prints the literal `$UNDER_TEST` — `worktree` —
  so a number carries base provenance and *no* candidate provenance, in the mode where the candidate
  is a mutable, possibly dirty worktree. Meanwhile part 3 now silently depends on inspecting that
  unrecorded side's files. Deferred item 4, but its load rose with revision 8.
- **"Five routes" is now an undercount.** The measured default-mode false pass (§2 above) is a sixth
  way to print a pass that could not have failed, filed under "limits in the comparison logic"
  (`:280-288`) rather than in the route list. A reader who counts "five routes, all closed" concludes
  the harness can no longer print an unfalsifiable pass. It can, and that pass will now carry a
  correct SHA. Deferred item 5 predicts exactly this; the taxonomy split makes it easier to miss.

### 5. Smaller

- **The freshly corrected count is already stale.** `629` → `631` was re-measured one commit ago; at
  the sha under review it is **632 / 66 / 66**. The *claim* (both shapes absent from all of history)
  reproduces exactly and is what matters — but pinning an absolute commit count into a document that
  gains commits guarantees the next reader finds a wrong number. State the invariant, not the tally.
- **`CODING_MEMORY.md:854` went stale again in one commit.** Fixed at `60faae1` to say "revision 7 —
  **compliance PASSED round 7**", it now describes a revision that no longer exists and a pass the
  spec itself says is void (`:16`). A session restoring from memory would believe this spec is
  compliance-clean. Same class as the round-4/5 finding, freshly re-created by revision 8.
- **Scenario D's comment is still stale** — "Identical to Scenario A's counts" (`:334`), but A now
  refuses and prints no counts. Flagged in round 5, not fixed; revision 8 was scoped elsewhere.
- **Exit 0 still printed on a run reporting relaxations** (recorded, queued). The new refusal exits
  make `0` newly readable as "safe to merge" when it means only "the instrument ran".
- **Scenario I's `234/82/62` remain author-measured**, accepted via the verified-unchanged-hooks
  chain rather than re-run this round. Stating the chain is what makes that honest rather than assumed.

## What I'd double-check before merging

1. **Give the on-disk rule the same treatment membership just got** — one statement, referenced from
   the other site — or note in deferred item 1 that it now has two consumers and its scenario is
   overdue. Right now the spec's own anti-drift remedy is applied unevenly within one part.
2. **Fix `:152-155`.** Either scope the claim ("for the base and a rev candidate, part 2 has already
   proved…") or close deferred item 2 and make it true. As written it asserts a guarantee the default
   mode does not have.
3. **Change task 7 to A-L.** One character; without it the scenario revision 8 exists to add is never run.
4. **Refresh `CODING_MEMORY.md:854`** to revision 8 / compliance restarted — it currently advertises a
   voided pass.
5. **Replace the absolute commit counts with the invariant they support** ("no commit in history
   carries either mixed shape"), so the figure cannot go stale a third time.
6. **Fix Scenario D's stale comment** (carried from round 5).

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | Revision 8 is precisely round 5's recommendation and nothing more: membership defined as the referenced set on both sides, stated once with part 2 pointing at it, plus the falsifier scenario that recommendation implied. Verified L discriminates between the two readings; verified its premise (0 of 632 commits carry either mixed shape). |
| execution | concern | Every measured claim reproduces (cmp triple + one-absent case, blob identity, `e3b09ba`/`286fd5a` premises, both populations 66/66, hooks unchanged since plan base). Against that: task 7 still says "A-K" and omits the new falsifier; part 3's justification at `:152-155` asserts a part-2 guarantee that does not cover the default worktree side; the re-measured 631/65 is already 632/66. |
| trajectory | pass | Correct diagnosis (a rule in two places drifts), correct remedy (define once, point at it), cost stated openly — the round-7 pass was voided deliberately, on a dated user decision recorded in the spec. Reasoning is explicit and falsifiable throughout; this is not luck. |
| regression | pass | No source touched. Hooks byte-identical to the plan base and to round-5 HEAD; working tree clean (round 5's stray deletion resolved); L does not invalidate A-K; the dominant historical population (492 of 632 self-contained) is still accepted, not narrowed. |
| context_budget | pass | One script, one ADR, four provenance notes; no always-on rule/skill/prompt surface. The feature file is 566 lines with the changelog now ~40% of it, but it loads on demand and the newest-first ordering keeps the live spec on top. |
| traceability | concern | Base side is fully auditable after part 5 (resolved SHA, anti-gaming clause, Scenario A pins the default run). Candidate side is still the literal `worktree` with no identity or dirty flag, while part 3 now depends on reading that side's files; and the "five routes" taxonomy omits the sixth measured false-pass route, which is filed under "limits" instead. |
| success_masking | concern | The measured default-mode false pass stands: helpers missing → exit 2 on every command → `relaxed` 0 by construction → exit 0, and now with a valid SHA beside it. Revision 8 built more of the machinery that would detect it (worktree-side set inspection) and still deferred, which is a recorded user decision — but it also newly asserts the case cannot arise, and my `cmp -s` one-absent measurement (exit 2 → fail-open) shows it can. Plus the unconditional exit 0 on runs that report relaxations. |
| intent_drift | pass | Revision 8 changed only the membership definition, Scenario L, Scenario H, two counts and one non-goal note. No scope creep, no new dependencies, no source edits, the three queued tally defects still cleanly out of scope. |
| checkpoint | pass | `phase: planning`, `branch: none`, no gate transition, clean working tree, and revision 8 is a single self-contained docs commit (`5bc39b9`) on top of a committed verdict trail — a clean revert point in both directions. |
| audit_trail | concern | The spec's own record is exemplary: newest-first changelog, the voided round-7 pass stated in the opening paragraph, all five deferrals carrying the round that raised them and the user decision that deferred them. But `CODING_MEMORY.md:854` — repaired one commit ago — now advertises "revision 7, compliance PASSED round 7" for a revision that no longer exists and a pass the spec says is void. |

## Concerns

- Revision 8 fixed the part-2/part-3 duplication but created a new one inside part 3: the on-disk-is-truth rule is stated at `:141-142` (membership) and `:167-170` (bytes), 26 lines apart, without the "one definition + reuses pointer" treatment it just applied elsewhere
- Both sites of that rule are unpinned by any scenario — it is only observable with a dirty worktree, which is deferred item 1; revision 8 added a second consumer of the spec's least-tested claim and recorded only that item 2 got cheaper, not that item 1 got heavier
- Part 3's justification at `:152-155` ("cmp is only ever called on paths present on both sides", because part 2 pre-validated every member) is false in the default `worktree` mode, whose candidate part 2 explicitly does not validate; measured, `cmp -s` with one path absent exits 2, so the run fail-opens into the recorded false pass
- Task 7 still reads "Verify scenarios A-K" — Scenario L, the entire point of revision 8, is missing from the acceptance step even though Scenario H was updated
- The five-route enumeration now undercounts: the measured default-mode false pass is a sixth route, filed under "limits in the comparison logic" rather than the route list, so "five routes, all closed" reads as stronger than it is
- The candidate side is still anonymous in the output (`worktree`, no identity, no dirty flag) while part 3 now depends on reading that side's files — provenance is closing on the base side only, exactly as deferred item 5 warns
- `CODING_MEMORY.md:854`, repaired at `60faae1`, is stale again one commit later: it advertises "revision 7 — compliance PASSED round 7" for a pass revision 8 deliberately voided
- The freshly corrected 629→631 is already 632 at the reviewed sha (66/66, not 65/65); the underlying claim — zero commits of either mixed shape in all of history — reproduces exactly, but an absolute commit count pinned in prose will go stale every commit
- Scenario D's comment still reads "Identical to Scenario A's counts" though A now refuses and prints none (carried unfixed from round 5)
- Scenario I's `234/82/62` are author-measured, accepted via the verified-unchanged-hooks chain rather than re-run this round
