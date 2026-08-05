# Observability verdict — replay harness base pin, revision 2 (architecting, round 2)

- **repo:** `.claude` · **branch:** `main` · **head_sha:** `c461e4cd2dfb493a0b0e5d92e10ade7b98c99416`
- **stage:** architecting (advisory — does not gate the PR)
- **spec:** `docs/features/replay-harness-base-pin.md` revision 2
- **ts:** 2026-08-05T03:06:54Z
- **filename note:** `2026-08-04-main.md` and `2026-08-04-main-replay-harness-base-pin.md` already exist
  and belong to other verdicts. Used the repo's established round-suffix disambiguation rather than
  overwrite a prior verdict with the bare `<date>-<branch_slug>.md` form.

## What was changed

A spec, not code yet. There is a script (`hooks/git-guard.replay.sh`) whose only job is to run two
versions of a safety check side by side and shout if the new one lets through something the old one
blocked. The spec says: that script can print a clean "all good" in five different situations where
it never actually compared anything, and its output gives you no way to tell those apart from a real
result. The fix adds a way to name what you're comparing against, refuses to run when both sides are
the same code, errors out instead of shrugging when it can't read a file, resolves the folder path
properly, and prints what it compared on every run.

Think of it as a scale that reads 0.0 kg. That's a correct reading if the pan is empty *and* a
correct reading if the scale is broken *and* a correct reading if you weighed a feather against a
feather. The spec is about making the scale print what was on the pan.

Revision 2 also **deletes a wrong claim from revision 1**. Revision 1 wanted to retract three
published measurements as fake. I checked: they were real, and the retraction would have been the
false statement — permanently, inside an ADR.

## Does it do what you wanted?

Mostly yes, and the corrections you asked me to check all hold. I re-ran everything.

**Verified independently (not taken on trust):**

| claim | result |
|---|---|
| harness has no base parameter | ✅ `grep -cE 'BASE_REV\|getopts\|\$\{3'` → `0` |
| row 1 — default base on main | ✅ ran it: `378 identical, 0 stricter, 0 relaxed`, exit 0, 74s |
| row 2 — `bc7da76` | ✅ `378 identical, 0, 0` |
| row 3 — `b17a666` | ✅ `358 identical, 20`, matches (ran mirrored, stricter↔relaxed swap) |
| row 5 — `286fd5a` | ✅ `118 identical, 260`, matches; `relaxed=0` by construction confirmed |
| row 6 — `WT=.` | ✅ `378 identical`, exit 0, **and the candidate exits 127 every time** — proved directly |
| `f5c5689` blobs identical to HEAD | ✅ `2b74507c 2f8af693 b8fed461` on both |
| `bc7da76` — only `shell_segments.py` differs | ✅ |
| `b17a666` — all three differ | ✅ |
| `64ba2fa` @ 15:45:33 vs `cc035d2` @ 16:53:55 | ✅ 68 min; `64ba2fa^`'s `shell_segments.py` = `7197eb08` (pre-fix) — the run *was* differential |
| `git-guard-empty-index.md` reports 162/52/32 relaxed, never "378 identical" | ✅ revision 1 misread the matrix size |
| toolchain pins (bash 3.2.57, git 2.50.1, py 3.9.6, jq 1.7.1-apple, BSD `cmp`) | ✅ all match this host |
| ADR 0016 number free | ✅ |

The retraction reversal is correct and the evidence for it is now stronger than the claim it
replaced. Route 3 (the relative-path 127) is real and I reproduced the mechanism in isolation.

## What could go wrong / what I'm unsure about

### 1. Two wrong implementations pass all eight scenarios — one of them is a false green

You asked me to try to build one. I built two.

**(a) Key the vacuity check on `shell_segments.py` alone.** Walk the scenarios: A refuses (matches),
B refuses (matches), C reports (`b17a666`'s differs), D reports (`bc7da76`'s differs), E/F error on
extraction, G is a path fix. **All eight pass.** It is wrong: a branch that changes only
`git-guard.sh` gets refused as "proves nothing" when it is a perfectly real run.

Why the scenario set can't catch it: I enumerated the three files' blob hashes across **the entire
commit history**. There is **no commit** where `git-guard.sh` differs from HEAD while both libs match
HEAD. Every single-file-differs base that exists is a `shell_segments`-only base. So the one file the
scenarios happen to vary is exactly the one a lazy comparator would key on, and no in-repo base can
falsify it. Scenario D does real work — it kills the `git-guard.sh`-only comparator, the
classify-only comparator, and the "all three must differ" (AND) comparator. It just can't kill this
one.

Fix: a scenario needing a base where **only `git-guard.sh` differs**. None exists, so it has to be
synthesized (scratch commit or a dirty worktree).

**(b) Compare the candidate via `git show HEAD:` instead of on-disk bytes.** The spec spends its
longest bullet arguing for on-disk bytes — and **no scenario pins it**, because A–H all run against a
clean worktree where the two readings are identical. On a dirty worktree they diverge, and the
divergence reopens route 1:

> base ≠ `HEAD` → vacuity check says "differential, proceed" → the matrix then runs `NEW`, the
> **on-disk** file, which the uncommitted edit has made identical to base → `378 identical, 0
> relaxed`, exit 0. Route 1 restored, now with a vacuity check vouching for it.

This is the more dangerous of the two, because the harness's normal habitat is a feature branch
mid-work, i.e. a dirty worktree. Fix: a Scenario I with an uncommitted edit to one of the three files.

**Scenario H is narrower than it reads.** "No implementation hard-wired to refuse, or to pass,
satisfies both halves" is true and only rules out the two *constant* implementations. It is not a
general discrimination proof, and the spec's phrasing invites reading it as one.

### 2. Route 3 is closed as an instance, not as a class

The actual defect at lines 125–131 is: **any exit code that isn't 0 or 2 falls to `else` and is
tallied as agreement.** The relative path is one way to produce 127. A missing `python3`, a syntax
error in an extracted file, a base script that aborts — all produce the same silent `same++`. Route 2
is the same bug from the other side (an empty base always exits 0, so `relaxed=0` by construction).

Fix part 4 resolves the path. Fix part 2 validates extraction. Neither states the invariant that
covers the ones nobody has found yet: *every one of the 756 invocations must exit 0 or 2; anything
else is an error, print no pair-count line, exit non-zero.* That is ~3 lines at 125–131 and it closes
routes 2, 3, and their unfound siblings at once. Your own recorded lesson — "when review rounds keep
finding new instances of one class, stop patching and enumerate" — points here. This is the third
instance of this class in three rounds.

### 3. "Print the resolved base" is not enough (your question 2)

No — and the reason is the exact one that produced revision 1's error.

- **`main` is a moving ref.** If the harness had printed `base: main` on 2026-08-04 at 15:45, that
  string would be just as uninterpretable today, because `main` then ≠ `main` now. The requirement
  must be the **resolved 40-char SHA**, with the ref name as given alongside it. The spec says "the
  resolved base" but Scenario C says "naming `b17a666`" — a short rev string, not a resolution. That
  ambiguity is enough for an implementer to print the input string and call it done.
- **Parity with the sibling is not the bar.** `shell-segments-falsifier.sh:100` prints
  `base=$BASE` — the *given* string, unresolved. Citing it as the parity target imports the gap.
- **The candidate side needs equal treatment.** For `UNDER_TEST=worktree` the candidate isn't a rev
  at all. Its auditable identity is worktree path + `git rev-parse HEAD` + a dirty marker.
- **Cheapest complete answer:** fix part 3 already reads all six files' bytes for the vacuity check.
  Print their six short content hashes. That is the *precise* datum the revision-1 archaeology needed
  — it would have resolved the whole retraction question in one line of output — and it costs nothing
  extra to compute.
- **Timestamp: no.** The commit that records the figure already carries one, and an in-output
  timestamp makes runs non-reproducible and diff-noisy. **Matrix size: already printed** (`63 commands
  x 6 states = 378 pairs`) — that line is what revision 1 misread, so putting the base beside it is
  well targeted.

### 4. Fix part 2 makes the spec's own measured row 4 unrunnable

`e3b09ba` has `git-guard.sh` but neither lib. Under part 2 ("each of the three `git show` calls must
succeed and yield a non-empty file") that base becomes a hard error. Row 4's `234 / 82 / 62` can never
be reproduced again — while the non-goals section still cites those 62 relaxed rows as future work
("Investigating them is its own task"). The spec doesn't acknowledge the conflict, and **no scenario
covers partial absence** (guard present, libs absent), which is the most common shape an old base
takes in this repo. E only covers total absence.

### 5. "The three citing documents" — there are four

`grep -rl 378` finds `git-guard-empty-index.md`, `shell-segments-redirects.md`, ADR 0015, and
`falsifier-base-pin.md`. ADR 0015 is explicitly not edited. So task 9 is under-specified: name the
files. (`falsifier-base-pin.md:145`'s "tautology / false green" claim is about row 1 and is correct
as written — it needs no note.)

### 6. Smaller notes

- After this fix the **default `main` always refuses on `main`** (Scenario A). That is correct
  behaviour, but it means the default's only valid use is on a feature branch — worth saying plainly
  so the next person doesn't file the refusal as a bug.
- **Runtime measured: ~74s per full matrix run.** Task 7's eight scenarios ≈ 10 minutes. Bounded and
  acceptable — but the relative-path run finished in **47s**, and that 27-second gap was the only
  observable signal that 378 comparisons never happened. Nothing in the output said so.
- Scenario G's "the candidate hook is actually executed" forbids an otherwise-reasonable design
  (reject relative paths with a named error). Minor over-constraint.

### Your question 3 — one change or two?

**One coherent change. Not overloaded.** Parts 1–5 are one 137-line file with one theme: *prove the
comparison was real, then say what it compared.* Part 6 is the documentation tail that any change of
this kind carries. Ten tasks looks like a lot, but 1, 7, 8 and 10 are verification and process, not
new surface. The non-goals are drawn tightly and correctly — no test sibling, matrix untouched,
`git-guard.sh` untouched, row 4's 62 relaxations deferred. I would not split it. I would *add* two
scenarios (§1a, §1b) and one invariant (§2), which grows the diff by a few lines, not a task.

## What I'd double-check before merging

1. **Add Scenario I: dirty worktree.** An uncommitted edit to one of the three files, asserting the
   comparison follows on-disk bytes. Without it the spec's most-argued bullet is unpinned and a false
   green survives.
2. **Add a "only `git-guard.sh` differs" scenario.** No such base exists in history — synthesize one.
   Until it exists, a `shell_segments`-keyed vacuity check ships undetected.
3. **State the exit-code invariant** at lines 125–131: only 0 or 2 is a comparison; anything else is
   an error. Close the class, not the instance.
4. **Make part 5 say "resolved 40-char SHA"**, add the candidate identity (worktree path + HEAD +
   dirty flag), and print the six content hashes the vacuity check already computes.
5. **Reconcile part 2 with row 4** — say out loud that a pre-lib base is now unusable, and add a
   partial-absence scenario or drop row 4's follow-up claim.
6. **Name the citing documents by path** in task 9, and say where ADR 0015's note lives.
7. Re-confirm Scenario C's `358 / 20 / 0` in the base-side orientation. I verified it mirrored
   (base=HEAD, cand=`b17a666` → `358 / 0 / 20`); the swap is sound but it is not literally the run the
   scenario names.

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | Addresses the queued defect and more; the revision-1 retraction is correctly reversed with evidence I reproduced. |
| execution | pass | Every measured row I re-ran reproduced exactly; blob hashes, timestamps and all six toolchain pins verified on this host. |
| trajectory | pass | Corrected its own premise after measurement, reported its own failed reproduction honestly, fixed a scenario expectation that measurement falsified. Weak spot: instance-fix over class-fix on route 3. |
| regression | concern | Fix part 2 silently makes measured row 4 (`e3b09ba`) unrunnable while the non-goals still cite it; no scenario covers partial file absence. |
| context_budget | pass | One script, one ADR, provenance notes. No always-on rule/skill/prompt surface touched. |
| traceability | concern | "Print the resolved base" under-specified: `main` is a moving ref, Scenario C names a short rev, and the cited parity target prints an unresolved string. Candidate identity unaddressed. |
| success_masking | concern | Two wrong implementations pass A–H — one keyed on `shell_segments.py` (unfalsifiable across the full history), one comparing `git show HEAD:` (unfalsifiable because every scenario runs clean, and it reopens route 1 as a false green). Non-0/2 exit codes still tally as agreement. |
| intent_drift | pass | Tight, explicit non-goals; no new dependencies; deferred work named rather than absorbed. |
| checkpoint | pass | Planning phase, `branch: none`, base `main` @ `c461e4c`. No branch cut, no gate transition taken. Clean revert point. |
| audit_trail | pass | ADR 0016 planned with a quotable rule; "What changed from revision 1" is exemplary; amend-by-new-ADR honored with citations. Nit: "three citing documents" when four exist. |

**risk: medium · confidence: high**

Confidence is high because I re-ran the harness (five of six rows reproduced exactly, the sixth
unrun), proved route 3's 127 mechanism directly, verified every blob hash and both commit timestamps,
and constructed the falsifiers against the full commit history rather than by argument.

Risk is medium, not low: nothing here ships a broken guard, and nothing here is a false statement
headed for an immutable ADR (revision 1's `high` is genuinely resolved). But the scenario set is the
artifact that will be used to declare this done, and it demonstrably admits a wrong implementation —
including one that restores the exact false green the change exists to remove.

## Concerns

- Scenario set admits a vacuity check keyed on `shell_segments.py` alone; verified across full history that no base exists where only `git-guard.sh` differs, so it cannot be falsified in-repo
- No scenario has a dirty worktree, so the spec's on-disk-bytes bullet is unpinned; a `git show HEAD:` implementation passes A-H and reopens route 1 as a false green
- Lines 125-131 tally any exit code other than 0/2 as agreement; fix part 4 closes the relative-path instance, not the class (third instance in three rounds)
- "Print the resolved base" does not say 40-char SHA; `main` is a moving ref, so the ref name reproduces the exact ambiguity that caused revision 1's error
- Candidate-side identity unspecified for `UNDER_TEST=worktree` (path + HEAD + dirty flag); the six content hashes the vacuity check already computes would close it free
- Cited parity target `shell-segments-falsifier.sh:100` prints the given string, not a resolved SHA — importing the gap
- Fix part 2 makes the spec's own measured row 4 (`e3b09ba`) unrunnable while the non-goals still cite its 62 relaxed rows as follow-up work
- No scenario covers partial file absence (guard present, libs absent) — the most common old-base shape; E covers only total absence
- Task 9 says "the three citing documents" but four cite 378 and ADR 0015 is explicitly un-editable; name the paths
- Scenario H rules out only the two constant implementations, but reads as a general discrimination proof
- Scenario C's `358/20/0` verified only in the mirrored orientation (base=HEAD, cand=b17a666 → 358/0/20), not the base-side run it names
- Scenario G's "candidate is actually executed" forbids rejecting relative paths with a named error, an otherwise reasonable design
- After the fix the default base always refuses on `main`; correct, but unstated, and reads as a bug
