# Observability verdict — replay harness base pin, revision 7 (architecting, round 5)

- **repo:** `.claude` · **branch:** `main` · **head_sha:** `2d865fde895c9e07cc2efb26c8e9412c568729a3`
- **stage:** architecting (advisory — does not gate the PR)
- **spec:** `docs/features/replay-harness-base-pin.md` revision 7, blob `56cc3693` (matches dispatch)
- **ts:** 2026-08-05T12:20:09Z
- **risk: medium · confidence: high**

> **filename note:** rounds 1–2 at `2026-08-04-main-replay-harness-base-pin*.md`, rounds 3–4 at the
> `…-round3.md` / `…-round4.md` siblings. Spec slug + round suffix kept so the five reads stay
> contiguous. JSONL `branch` stays the raw `main`.

> **Method:** per the round-3/4 notes — absolute paths, braces on every `"${var}:hooks/…"` ref,
> `$?` captured before anything else, and every probe demonstrated able to both find and fail to
> find (`cmp -s`: identical→0, **differ→1**, absent→2 — the differ row is the falsifier).

---

## What was changed

Still a spec — no code, no branch. `phase: planning`, `branch: none`. Hooks are byte-identical
between the plan base `c461e4c` and today's HEAD `2d865fd` (verified: empty diff over `hooks/`), so
every measured row and all 13 line citations remain valid without re-running the matrix.

Revision 7 is a consolidation, not a point fix. Three things moved since round 4:

1. **Scenarios I, J, K added** (my round-4 headline finding: "the rule changed but the tests
   didn't"), and Scenario H now covers them.
2. **Part 3 rewritten set-first, then bytes** (the compliance judge's finding — same root): a path
   absent on *both* sides counts as agreement and never reaches `cmp`, because `cmp -s` on two
   absent paths exits 2, not 0, which silently disarmed the vacuity refusal for self-contained
   guards.
3. **The record was repaired**: all five deferred judge recommendations now live in the spec's
   non-goals with the round that raised each and the user decision that deferred it; the round-3
   and round-4 verdicts (markdown + JSONL) are committed at `2d865fd`.

## Does it do what you wanted?

**Yes. The three holes round 4 named are closed, and each closure was checked against the actual
harness source, not just the prose.**

The dispatch asked specifically whether a reversion to "all six required", a dropped helper check,
and an "all three" vacuity phrasing each now fail at least one scenario. Verified:

- **"All six required" fails Scenario I.** `e3b09ba`'s guard has **0** `lib/` occurrences (grep
  count re-run: 0) and its helper genuinely absent at that rev (`git show` rc 128). An all-six
  implementation raises an extraction error there; I asserts none is raised and that the pair-count
  line prints. Closed.
- **"No helper check" fails Scenario J — robustly.** With the check dropped, the harness's
  unchecked redirect (`:14-15`) stages *empty* helper files beside a guard that references `lib/`.
  Whether that base then fails closed (exit 2 everywhere → loud relaxations) or fails open (exit 0
  everywhere → spurious stricter rows), **a pair-count line prints either way**, and J's assertion
  is on the refusal *shape* (no pair-count line, non-zero exit), not on specific counts. So J
  discriminates regardless of which way an empty classifier breaks. That is good scenario design.
- **"All three match" fails Scenario K.** Verified live: `cmp -s` on two absent paths exits **2**
  on this host, so the revision-6 phrasing can never fire for a self-contained side; the set-first
  rule refuses `e3b09ba`-vs-itself correctly. Closed.

Scenario premises also re-verified at HEAD: Scenario B's `f5c5689` carries the same three blobs as
HEAD (`2b74507c` / `2f8af693` / `b8fed461` on both sides — the rev-string falsifier is real);
Scenario E's `286fd5a` is missing `hooks/git-guard.sh` itself (rc 128), so its named error is
independent of the helper rule. The toolchain correction is honest and now measured: `cmp --quiet`
exits 0 here, `readlink -f /tmp` → `/private/tmp` rc 0 — "portability choice, not capability
limit" is now the true statement it claims to be.

**Round-4 items resolved:** deferrals recorded (grep now finds all five in the non-goals), the
provenance-vs-validity concern restated in full, verdict trail committed.

## What could go wrong / what I'm unsure about

### 1. The newest prose has the next ambiguity: what counts as a side's "file set"?

Part 3 (i) says the sides are vacuous only if "exactly the same paths are present on both sides" —
but **"present" is never defined for a helper the guard does not reference.** Two readings, both of
which pass every scenario A–K:

- **Raw on-disk/in-rev presence.** Then this corner reopens route 1: a worktree candidate whose
  guard has been reverted to a self-contained version (byte-identical to a self-contained base like
  `e3b09ba`) while the now-unreferenced `hooks/lib/*.py` still sit on disk — exactly the shape of
  testing a revert of the helper split against its pre-split base — has a *different* file set, so
  the refusal does not fire, the matrix runs one program against itself, and prints `378 identical,
  0 relaxed` **decorated with a correct 40-char SHA**. A vacuous pass dressed as an audited one is
  the precise harm this spec exists to abolish.
- **Referenced-set presence** (`{guard} ∪ {helpers iff the guard references lib/}`). Then the
  corner is refused correctly, consistent with part 3's own "compare the bytes that will actually
  execute" principle.

The spec's history is four consecutive revisions each shipping the next round's finding in its
newest prose; this is the round-5 instance, though the narrowest yet. One sentence fixes it: define
a side's set as the referenced set, on both the rev and worktree sides.

### 2. Deferred item 2 became more load-bearing — the dispatch asked, and the answer is yes

The worktree-candidate helper check (deferred, non-goals item 2) was "a one-line omission" after
revision 6. After revision 7 it is stranger than that: **part 3's set comparison must already stat
`$WT/hooks/lib/*.py`** to build the candidate's file set — there is no other way to compare sets —
yet part 2 still never validates what it finds there. The machinery the check needs now exists as a
side effect of the vacuity rule, and the measured silent false pass it would close (guard present,
helpers missing → exit 2 on every command including `echo hi` → `relaxed` 0 by construction → exit
0, plus a freshly printed valid base SHA) remains open in the **default** mode. Deferred by
explicit user decision and on the record — but the cost of closing it has dropped again, and the
ambiguity in §1 and this check would be resolved by the same predicate. Items 3, 4 and 5 are
unchanged in load; item 5's concern is now restated in the spec itself, which is what round 4
asked for.

### 3. Smaller

- **Scenario D's comment is stale**: "Identical to Scenario A's counts" — A no longer prints
  counts; it refuses. Cosmetic, but it sits in the acceptance artifact an implementer will read.
- **`CODING_MEMORY.md:854` still pins the spec at "revision 5"** (it is 7) — flagged in round 4,
  not fixed — and `:868` in the same entry still cites `git-guard.sh:56`, the pointer revision 6
  corrected to `:74-77`. The memory entry is drifting from the spec that supersedes it.
- **Exit 0 is still printed on a run that reports relaxations** (recorded honestly in non-goals,
  queued). The new refusal exits make 0 newly readable as "safe to merge" when it only means "the
  instrument ran".
- **The working tree carries an unrelated unstaged deletion** (`agents/pane-echo.md`) — not this
  spec's doing; tidy it before cutting the feature branch so the checkpoint is clean.
- **Scenario I's counts (`234/82/62`) are author-measured, not re-run this round.** Accepted
  because hooks are verified byte-unchanged since the plan base, so the prior rounds' verification
  chains forward; stating that chain is what makes this honest rather than assumed.

## What I'd double-check before merging

1. **Add one sentence to part 3 defining a side's file set as the *referenced* set** — guard plus
   helpers only if that side's guard references `lib/` — on both the rev and worktree sides. It
   closes §1's corner and makes §2's check nearly free.
2. **Consider un-deferring the worktree helper check** now that part 3 must stat those paths
   anyway; if it stays deferred, no action — the record is in order.
3. **Fix Scenario D's stale comment** (A refuses now; the comment predates that).
4. **Refresh `CODING_MEMORY.md:854`** (revision 5 → 7) and the `:56` pointer at `:868` (→ `:74-77`).
5. **Restore or commit the `agents/pane-echo.md` deletion** before branch creation.

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | All three round-4/round-6 findings correctly implemented. I/J/K each verified to discriminate against the specific wrong implementation they exist to kill; J is robust to both failure modes of an empty-helper base. Deferrals recorded as asked. |
| execution | concern | Every checked claim reproduced (cmp exit triple with falsifier; `f5c5689` blob identity; `e3b09ba`/`286fd5a` premises; toolchain corrections; hooks unchanged since plan base). Remaining: part 3's "paths present" is undefined for unreferenced helpers, both readings pass A–K, and the raw-presence reading reopens route 1 in the revert-testing corner. Narrowest gap of the five rounds, but the same class. |
| trajectory | pass | The consolidation directive (enumerate every site of each breaking invariant, fix in one pass) is the correct response to four rounds of point-fix whack-a-mole, and it worked: invariants 1 and 2 now agree at every site I checked. Prose that was recalled rather than measured was re-measured and corrected against the spec's own interest. |
| regression | pass | No source touched, hooks byte-identical since plan base, manual harness not registered in `settings.json`. Scenarios I/J/K accept the dominant historical base class (492/629 self-contained) rather than narrowing it. |
| context_budget | pass | One script, one ADR, four provenance notes. No always-on rule/skill/prompt surface. |
| traceability | concern | Base side is now fully auditable (40-char SHA, anti-gaming clause, Scenario A pins the default run). Candidate side is still the literal `worktree` with no identity or dirty flag (deferred item 4, on record), while part 3 now silently depends on inspecting that side's unrecorded file set. |
| success_masking | concern | The default-mode silent false pass stands, measured: helpers missing → exit 2 on everything → 0 relaxed by construction → exit 0 with a valid printed SHA. User-deferred and recorded — but revision 7 built the very machinery (worktree-side set inspection) that would detect it, and chose not to use it. Plus §1's corner and the queued unconditional exit 0. |
| intent_drift | pass | Revision 7 changed only what the consolidation covered. Deferrals honored, no new dependencies, no source edits, three queued tally defects still cleanly out of scope. |
| checkpoint | pass | `phase: planning`, `branch: none`, no gate transition, verdict trail committed at `2d865fd`. One unrelated unstaged deletion (`agents/pane-echo.md`) noted for tidying before branch creation. |
| audit_trail | pass | Upgraded from round 4: the compounding pattern is broken — all five deferrals recorded with round + user decision, provenance-vs-validity restated in the spec, rounds 3–4 verdicts committed. Residue is two stale lines in `CODING_MEMORY.md` (`:854` "revision 5", `:868` the superseded `:56` pointer). |

## Concerns

- Part 3's "paths present on a side" is undefined for unreferenced helpers; the raw-presence reading passes all of A–K yet reopens route 1 when a self-contained candidate guard sits beside stale `lib/*.py` (e.g. testing a revert of the helper split against its pre-split base) — a vacuous 378/0/0 printed with a correct 40-char SHA
- No scenario pins that corner; fifth consecutive revision whose newest prose carries the next unpinned ambiguity, though the narrowest yet — one defining sentence closes it
- Deferred item 2 (worktree-candidate helper check) is now more load-bearing: part 3's set comparison must already stat `$WT/hooks/lib/*.py`, so the measured default-mode silent false pass (exit 2 on everything → 0 relaxed → exit 0 + valid SHA) is unguarded by choice, not by cost
- Scenario D's comment still reads "Identical to Scenario A's counts" but A now refuses and prints no counts — stale text in the acceptance artifact
- `CODING_MEMORY.md:854` still pins the spec at "revision 5" (it is 7; flagged round 4, unfixed), and `:868` still cites `git-guard.sh:56`, the pointer revision 6 corrected to `:74-77`
- A run reporting relaxations still exits 0 (recorded, queued); refusal exits make 0 newly readable as "safe to merge" when it means only "the instrument ran"
- Working tree carries an unrelated unstaged deletion (`agents/pane-echo.md`); tidy before cutting the branch
- Scenario I's `234/82/62` counts are author-measured, accepted via the verified-unchanged-hooks chain rather than re-run this round
