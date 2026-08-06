# Observability verdict — `fix/replay-harness-base-pin` (architecting, round 4)

> **Round 4 (current, at `e5b6f0b`) — architecting stage, ADVISORY.** This read does not gate the
> PR; the implementation-stage verdict does, and rounds 1–2 (both `implementation`) remain **void**
> because revision 10 adds implementation work. Rounds 3, 2 and 1 are preserved verbatim below.
>
> ⚠️ **This round corrects an error of my own.** Round 3 told the author that an empty helper
> "flips the candidate to allow-everything — a *different* failure direction from absent." Revision
> 10 wrote that into Scenario O in good faith. **It is wrong for the file Scenario O names**, and
> the correction is measured below.

- **repo:** `.claude`
- **branch:** `fix/replay-harness-base-pin`
- **head_sha:** `e5b6f0b036d1f63701d6441d1906f23f7c3ea4cf`
- **stage:** architecting (advisory — compliance judge is the blocking one)
- **ts (UTC):** 2026-08-05T22:31:07Z
- **spec:** `docs/features/replay-harness-base-pin.md` @ blob `5a7739fd` (1112 lines), revision 10 + round-1 compliance fixes — blob verified against the invocation, exact match
- **base:** `main` @ `56f1dfd` — HEAD is 16 ahead; working tree carries only judge artifacts
- **measurement run by the judge:** five `/tmp` clones, never the real worktree

## What was changed

Nothing executable, again. `7bed4d0` and `e5b6f0b` are spec-only: revision 10 plus its round-1
compliance fixes (the `:73-77` pointer, and the blast-radius criterion restated as a named set).
Since round 3 the spec gained Scenarios N and O, and moved the `rm -f` deletion from a warning into
task 11 as a build step. `git diff main HEAD -- hooks/` is unchanged since `97aef27`.

## Focus item 1 — are N and O buildable, and do they falsify what they claim?

**Scenario N: buildable exactly as written, and it already passes.** I built its fixture from task
11's recipe verbatim — orphan branch, 0-byte `hooks/git-guard.sh`, committed in the candidate's own
clone:

```
git show scenN:hooks/git-guard.sh  ->  rc=0  size=0        # SUCCEEDS and returns nothing — the E-distinction holds
REPLAY ERROR: the base at 5b64ae7e7e69da7fd4598893ff9fc70f7dd9259b has an empty
hooks/git-guard.sh — an empty file cannot execute as intended...      exit=1, no pair-count line
```

All four of N's assertions hold today. That is because the base-side non-empty check has existed
since task 3 (`extract_required:47-49`). **N is a regression fence, not a red.** Task 11 lists "M, N
and O (the new ones)" together; only M and O are red. Worth stating so a green N is not read as
evidence that the worktree half of the rule works.

**Scenario O: buildable, and a genuine red** — `: > hooks/lib/shell_segments.py` in a clone, default
mode, HEAD harness: no error, `260 identical, 118 stricter, 0 relaxed`, exit 0. It falsifies the
worktree-side non-empty rule. Its base requirement ("a non-vacuous base") is a property rather than
a pinned value, unlike Scenario G's `b17a666`; harmless here, because the empty helper differs from
`main`'s, so even the default base is non-vacuous for this fixture.

### But O's stated reason is false — measured, four shapes

O says: *"Empty fails in the OPPOSITE direction from missing here… so M does not cover this by
accident."* Every worktree-breakage shape, HEAD harness, default mode, `$?` on the next line:

| worktree shape | harness result | exit | direction | scenario |
|---|---|---|---|---|
| helpers **missing** | `260 identical, 118 stricter, 0 relaxed` | 0 | silent | M |
| `shell_segments.py` **empty** | `260 identical, 118 stricter, 0 relaxed` | 0 | silent | **O** |
| `classify-git-command.py` **empty** | `118 identical, 0 stricter, 260 relaxed` | 0 | loud | none |
| `git-guard.sh` **empty** | `118 identical, 0 stricter, 260 relaxed` | 0 | loud | none |

For the file O actually names, empty and missing are **byte-identical in output**. Mechanism probed
directly, not inferred: an empty `shell_segments.py` breaks the classifier's import, so
`git-guard.sh:74-77` fails closed — `exit 2` on `ls -la`, `git push`, `git commit`, bare `echo`,
exactly as the missing case does. The genuine opposite-direction case is the **other** helper: an
empty `classify-git-command.py` is a valid empty Python program, exits 0 with no stdout, `facts` is
empty, and the guard **allows everything**.

**This does not weaken O.** M and O probe different *predicates* in the implementation — presence
versus non-emptiness — so an implementation testing only `[ -f ]` passes M and fails O. O is still
the only falsifier for the non-empty half on the worktree side, and it happens to pin the *silent*
helper, which is the more dangerous one. The conclusion is right; the sentence explaining it is an
invented mechanism, which is the one thing this spec exists to forbid. One sentence to fix.

## Focus item 2 — delete the `rm -f` or fence it?

**Deleting is right.** I re-verified deadness by reading, not by trust: `replay.sh:61` sits in the
`else` of `extract_helpers_if_referenced` (`:59-63`), taken only when the guard references no
`lib/`; the sole writer of those two paths is `extract_required` at `:57-58` in the *other* branch;
and `$3` is always a fresh `mktemp -d` subdir (`$TMP/base` or `$TMP/cand`, each `mkdir -p …/lib`).
In that branch the paths have never existed. Deleting it is a no-op for the base and rev sides.

Fencing leaves a live `rm -f` beside a variable that task 11 is about to make `$WT`, protected by
prose in three places — and `checkpoint-before-modify.sh` is unregistered, so nothing computational
would stop it. Removing the landmine beats documenting it. **Endorsed as written.**

One caveat on the phrasing: task 11 says "before **sharing that function** with the worktree side",
but the function's other half is git-only (`git -C "$WT" show "$1:$3"`), so it cannot be shared
verbatim — the validator has to be split from the extractor. The refactor shape is left to the
implementer. A botched share fails loudly (M, O and the whole accepting sweep), so this is a wording
nit, not a risk.

## Focus item 3 — are deferrals 3 and 5 honest, or a dodge?

**Honest.** Both sit in their own slots with the increment named, the failure direction stated, the
cost re-priced *downward*, and the decision rule cited — un-deferring is the user's call, the same
rule that governed item 2, whose slot was kept visible after it was taken. Both end "raise it at the
gate". A dodge would quietly restate the cost as unchanged; this does the opposite.

Item 3's factual claim verified exactly: `grep -n 'lib/' hooks/git-guard.sh` → three hits, `:21` and
`:29` are comment lines, `:44` is the live `CLASSIFIER=` assignment. "2 of its 3 matches are
comments" is correct, and the under-firing direction it names is the quiet one.

Item 5: the *substance* is already in ADR 0016 `:37-56`, which discloses the `else → same` tally,
`relaxed`'s one-sided definition, the unconditional `exit 0`, and the block-everything false pass.
What is missing is only the meta-point — that after this fix a false pass prints a valid 40-character
SHA and therefore *looks* audited. Real, cheap, correctly flagged, and the residual is small because
the limit itself is already on the record.

## Focus item 4 — what revision 10 broke that A–O would not catch

**One thing: a 0-byte `$WT/hooks/git-guard.sh` has no falsifier.** Line 27's existing guard is
`[ ! -f "$WT/hooks/git-guard.sh" ]`, and `-f` is true for a 0-byte file, so part 4 passes it
through. Task 11's text *requires* the check ("`$WT/hooks/git-guard.sh` non-empty"), but no scenario
in A–O tests its omission: M is missing helpers, O is an empty helper, L is a self-contained guard,
and A/C/D/G/I are all healthy. Measured at HEAD: `118 identical, 0 stricter, 260 relaxed`, exit 0,
no error — the **loud** direction, so severity is low.

The shape of the gap is worth naming, because it is not symmetric with the base side. On the base
side, guard-empty and helper-empty flow through the *same* function (`extract_required:47-49`), so
Scenario N pins both. On the worktree side they will be **two distinct call sites** — a direct check
on the guard, and a conditional check on the helpers — so Scenario O pins only one of them. The
newest rule, on the newest side, has half a falsifier.

Nothing else found. Ordering (M's insertion point at `:73-77` precedes the vacuity block at `:113`)
still holds; L still reaches the refusal rather than a validation error; the accepting direction is
covered five ways.

## Also carried forward

- **Blast radius, one notch smaller than round 1's finding.** The criterion names
  `git diff --name-only main HEAD` (measured 8) as its instrument, then names a **6-path** allow-set.
  Run the stated command and it flags task 9's `git-guard-empty-index.md` and
  `shell-segments-redirects.md` as widening — both legitimate. The prose is task-11-scoped ("task 11
  must touch nothing outside"), the measurement sentence is branch-scoped. Repairable by anyone who
  reads it carefully; still the same class of defect the criterion was rewritten to remove.
- **`292/86/0`** remains uncorrected in three durable records (round-1 verdict md, both
  `verdicts.jsonl` lines) while corrected in the spec. Unchanged from round 3.
- **The spec is now 1112 lines / ~21k tokens** and the restore discipline makes it mandatory reading
  after every `/clear`. It has grown a revision-history section per round for ten rounds.

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | Revision 10 does what the summary claims: N and O added, `rm -f` moved from warning to build step, items 3 and 5 recorded not taken, round-1 compliance fixes verified correct (`:73-77` + comment at `:74` confirmed by reading). |
| execution | concern | I built and ran the design's own fixtures. N buildable and green; O buildable and a genuine red. But O's documented mechanism is falsified by measurement, and one required check (worktree guard non-empty) has no falsifier in A–O. |
| trajectory | pass | Re-measured the judge's `292/86` instead of inheriting it, refused to invent a reconciliation, and replaced a drifting count with a named set. Sound reasoning, not luck — the one wrong sentence originated in my round-3 read. |
| regression | pass | No code moved: `git diff main HEAD -- hooks/` unchanged since `97aef27`; `hooks/git-guard.sh` untouched; HEAD harness behaviour reproduced unchanged across five clones. |
| context_budget | concern | Not always-on context, but 1112 lines / ~21k tokens of mandatory-on-restore reading — over half the ~35k freshness budget before any work begins. |
| traceability | concern | Scenario O's rationale is false as measured; a reader trusting it believes M and O probe different directions when today they produce identical output. |
| success_masking | concern | Unchanged and correctly disclosed: `relaxed` is 0 by construction for any block-everything candidate (re-measured twice this round). Revision 10 closes two entries, not the limit. Separately, N is green on day one and could be misread as the rule being done. |
| intent_drift | pass | Scope grew only by explicit user decision, with the cost (voided verdicts, compliance restart) stated up front; items 3 and 5 explicitly not taken. |
| checkpoint | pass | Commit-per-task history; revision 10 isolated in `7bed4d0`/`e5b6f0b`; clean revert point. Only judge artifacts uncommitted. |
| audit_trail | concern | `292/86/0` still asserted as judge-reproduced in three durable records. Newly: my round-3 empty-helper claim is wrong and is now quoted in the spec — this entry is the correction, but the round-3 record stands. |

**risk: low — confidence: high** (every claim above was built and run; nothing is inferred from totals).

## Concerns

1. Scenario O's stated rationale is falsified by measurement — for `shell_segments.py`, empty and missing produce byte-identical output (`260/118/0`, exit 0); the judge's own round-3 read is the source of the error.
2. The true opposite-direction case is the other helper: an empty `classify-git-command.py` makes the guard allow everything (`118/0/260`); no scenario covers it.
3. A 0-byte `$WT/hooks/git-guard.sh` has no falsifier in A–O — `-f` passes it, measured `118/0/260` exit 0 with no error; task 11 requires the check, nothing tests its omission.
4. Coverage is asymmetric: base-side guard-empty and helper-empty share one code path so N pins both; worktree-side they are two call sites and O pins only one.
5. Scenario N passes today (base-side `[ -s ]` exists since task 3) — a regression fence, not a red, while task 11 groups it with the reds.
6. Task 11's blast-radius criterion names a branch-scoped instrument (`git diff --name-only main HEAD`, 8 files) against a task-scoped 6-path set; the stated command flags task 9's two provenance files as widening.
7. `292/86/0` stands uncorrected in three durable records while corrected in the spec.
8. Feature file is 1112 lines / ~21k tokens and is mandatory reading on every restore.
9. `relaxed` is 0 by construction for any block-everything candidate — unchanged, queued, correctly disclosed.
10. Verified and endorsed: `replay.sh:61`'s `rm -f` is dead as specified, so deleting it beats fencing it.

---

# Observability verdict — `fix/replay-harness-base-pin` (architecting, round 3)

> **Round 3 (current, at `7bed4d0`) — architecting stage, ADVISORY.** This read does not gate the
> PR; the implementation-stage verdict does, and rounds 1–2 (both `implementation`) are **void**
> because revision 10 adds implementation work. Rounds 2 and 1 are preserved verbatim below.

- **repo:** `.claude`
- **branch:** `fix/replay-harness-base-pin`
- **head_sha:** `7bed4d0aa3493f91866105068976ac036662eea3`
- **stage:** architecting (advisory — compliance judge is the blocking one)
- **ts (UTC):** 2026-08-05T22:14:03Z
- **spec:** `docs/features/replay-harness-base-pin.md` @ blob `915e331c` (996 lines), revision 10
- **base:** `main` @ `56f1dfd` — HEAD is 15 ahead, 0 behind; working tree clean
- **measurement run by the judge:** the red reproduction, in a `/tmp` clone, never the real worktree

## What was changed

Nothing executable. HEAD is spec-only: revision 10 rewrites part 2 from "validate every extraction"
to "validate every side", adds Scenario M, generalises the refusal contract's identity clause,
tightens Scenario L, and adds task 11. The code change it describes has not been written yet.

## Reproduction — the spec's figure is right, mine matches, the round-2 figure does not

Cloned this repo `--no-hardlinks` to `/tmp`, created a local `main` from `origin/main`,
`rm -rf hooks/lib` in the clone's worktree, ran the DEFAULT invocation, `$?` captured on the next
line. Wall clock 61s for the 378-pair matrix (756 hook invocations).

```
base=56f1dfdf6f4a70b3ee3ad3263c7e29c0444ac9c9 (main) — 63 commands x 6 states = 378 pairs:
260 identical, 118 stricter, 0 relaxed (0 distinct commands)      exit=0
```

**`260 / 118 / 0`, exit 0 — exact match with the spec.** The round-2 verdict's `292 / 86 / 0` does
not reproduce, and this is the third independent placement of the real guard at 118 allows / 260
blocks (spec row 5's mirror, the spec's session-14 re-measure, and this run).

### Assessing the "no explanation offered" call — the spec is right, and I can narrow it

**Declining to reconcile was the correct call, and I would not change it.** A spec written because a
harness printed numbers that could not be traced must not itself carry a mechanism nobody measured.
Keep the refusal.

But "no explanation" and "no constraint" are different things, and a *measured* constraint is
available. I ruled out the two cheap hypotheses directly:

- **Partial deletion is ruled out.** `hooks/lib/classify-git-command.py:68` does
  `from shell_segments import segments` at module scope. Probed on a fixture repo: deleting *either*
  helper, or both, makes the guard exit **2 on all of** `ls -la`, `echo hi`, `git push`,
  `git commit -m msg`, `git commit -m msg -- docs/tracked.md`. There is no deletion shape that
  produces a partly-working candidate.
- **Emptied helpers are ruled out too, and flip the direction.** A present-but-**0-byte**
  `classify-git-command.py` runs, exits 0, emits no facts — and the guard **allows every command**
  (probed: exit 0 on all five, including `git commit -m msg`). That configuration would print a
  flood of `relaxed` rows, not `0 relaxed`. *(Side finding: part 2's non-empty clause is therefore
  load-bearing on the candidate side, and in the opposite direction from the absent case.)*

That leaves arithmetic. With `relaxed = 0` and `stricter = 86` over 378 pairs, only two shapes fit:

| shape | requires |
|---|---|
| block-everything candidate | the **base** allowed **86** of 378 pairs |
| healthy candidate (118 allows, ⊆ base's allows, since `relaxed = 0`) | the **base** allowed **204** |

`main` allows **118**. So `292/86/0` **cannot have come from `main` as base against a
helper-deleted candidate, under any deletion or truncation shape.** It requires a different base —
or a candidate that was not broken in the way the round-2 verdict reported.

**Which one, I did not measure, and I will not invent it.** The most economical reading consistent
with the arithmetic is that the round-2 run's base was not the `main` the spec assumes (a clone
whose `main` resolves elsewhere is the obvious candidate, and the spec's own task-4 note records
`git clone` checking out the source repo's current branch rather than `main` as a live gotcha on
this very branch). That is a **hypothesis, not a finding** — flagged as such, exactly as the spec's
own discipline demands.

**Recommendation (advisory, one line):** the spec may add the constraint above. It is arithmetic on
figures the spec already carries, it converts "unexplained" into "provably a different
configuration", and it is falsifiable. It is not an obligation, and the spec is not deficient
without it.

## Answering the four focus questions

### 1. Does the fix make the *output* trustworthy, or improve provenance faster than validity?

**Provenance still outruns validity, and I measured the residual.** Deferral 5's concern is live
after revision 10:

```
present, non-empty, syntactically broken helper (6-byte `def (` in shell_segments.py)
→ guard exits 2 on `ls -la` AND on `git commit -m msg`
→ blocks everything → relaxed = 0 by construction → clean pass, exit 0
```

That passes part 2's rule on all three sides (present, non-empty, referenced) and still prints a
valid 40-character SHA beside a meaningless number. So **revision 10's "closes the example, not the
limit" is not hedging — it is exactly, measurably correct**, and the distinction is sound.

Is deferring the ADR sentence still defensible? **Weakly.** It was defensible when the ADR was
finished; it is less so now, because **task 11 already opens ADR 0016 `:37-56` to edit**. The
marginal cost of one sentence — *a printed base attests provenance, not validity* — in a file
already being edited is close to zero, and the reader most at risk is the one who sees a 40-char SHA
and stops looking. I score this a **concern, not a fail**: the limit is disclosed in the ADR's own
"what it does not prove" section, queued, and user-decided.

### 2. Are the three open limits honestly scoped?

**Yes — this is the strongest part of the revision.** `else → same`, `relaxed`'s one-sided
definition, and the unconditional `exit 0` are each stated with their mechanism, their line numbers,
and their independence from one another. The correction that limit 2 is *not* a case of limit 1
(the exit code is inside `{0,2}`) is right. The new distinction is sound and I verified both halves:
the missing-helpers entry really is closed by part 2 (validation fires at `replay.sh:73-77`, before
the vacuity block at `:87`), and the limit really does stay open (the syntax-error probe above).

### 3. Is task 11's verification plan sufficient?

**Sufficient in coverage; heavy in cost, and that cost is not stated.**

- Coverage is right. Scenario M pins the rejecting direction *and* the ordering; L pins the
  self-contained worktree candidate (the mirror of I); A, C, D, G, I pin the accepting direction. An
  over-firing rule breaks five scenarios. A red-first re-confirm guards against a moved premise.
- **Gap: nothing falsifies the `[ ! -s ]` (present-but-empty) half of part 2 on *any* side.**
  Scenario E is *absent* files; Scenario M is *absent* helpers. My probe shows the empty case has a
  **different failure direction** (allow-everything, a relaxation flood) — so it is not covered by
  the absent-case scenarios by implication. In a spec whose entire discipline is one falsifier per
  rule, that is a real hole, and revision 10 extends the unfalsified half to a third side.
- **Cost:** ~18 matrix runs × ~60s, plus two synthesised bases that do not survive a `/clear`. The
  most skippable step — the accepting-direction sweep — is the one that catches over-firing. Worth
  saying so in the task, so an implementer under time pressure knows which corner *not* to cut.
- **Unrecorded new dependency:** revision 10 makes the worktree validation depend on
  `grep -q 'lib/'` — deferral 3's comment-blind heuristic (3 matches at HEAD, 2 of them comments,
  verified). The spec scrupulously records that the on-disk-bytes rule went from two dependents to
  three; the identical increment on deferral 3 goes unrecorded. Under-firing is the silent direction
  here: a guard resolving its classifier without the literal `lib/` would be validated as
  self-contained and its helpers never checked.

### 4. Is the destructive-trap warning enough?

**It is as loud as prose gets — and prose is not a mechanism.** The trap is real and I confirmed the
path shape: `replay.sh:61` does `rm -f "$3/lib/*.py"`, and the worktree side's directory is
`$WT/hooks` (`CAND_LIB="$WT/hooks/lib"`, `:77`), so a verbatim reuse deletes the user's real
helpers. The spec warns three times. Note also that `hooks/checkpoint-before-modify.sh` — the hook
that would catch this class — is **dormant and unregistered** per `rules/gates.md`, so nothing
computational stops it.

Two cheap hardenings, in preference order (advisory; the judge does not decide scope):

1. **Delete the `rm -f` outright.** Verified dead: `mkdir -p "$BASE/lib"` creates the directory
   empty and `extract_required` only writes helpers in the *referenced* branch, so in the `else`
   branch those paths never exist. Removing the trap beats documenting it, and it is one line in a
   function task 11 already touches.
2. **Or fence it:** refuse to delete outside `$TMP` (`case "$3" in "$TMP"/*) ;; *) fail …`). That
   turns the warning into a guard that survives a future editor who never reads this spec.

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | Revision 10 closes exactly the gap that was reproduced, at the third side, with the ordering constraint correctly derived. |
| execution | concern | Red reproduces exactly (`260/118/0`, exit 0) and the plan is executable — but no scenario falsifies part 2's non-empty half on any side, and the empty case has a different failure direction from the absent case. |
| trajectory | pass | Re-measured rather than inherited; refused to invent a reconciliation; named the destructive trap before writing it; distinguished closing an example from closing a limit — verified correct by probe. |
| regression | pass | Spec-only at HEAD; blast radius pinned at 6 files with a re-check; over-firing falsifiers named (L + A, C, D, G, I). |
| context_budget | pass | Feature file, loaded on demand, not always-on context. 996 lines with ~40% revision log is heavy but is the one-canonical-file rule working as designed. |
| traceability | pass | Every figure carries its base; every pointer I spot-checked (`:61`, `:73-77`, `:68`, `:44`, `:53-57`, `:74-77`) is correct. |
| success_masking | concern | Provenance outruns validity: a false pass now prints a valid 40-char SHA. Measured live residual — a present, non-empty, syntax-broken helper blocks everything → `0 relaxed`, exit 0. Disclosed, queued, user-decided; not scored as a defect of the revision. |
| intent_drift | pass | Scope growth is user-authorised, recorded with its cost (voids two verdicts, restarts compliance at round 1), and bounded by a blast-radius re-check. This is the pattern that shipped a second defect twice before in this class — governed here about as well as it can be. |
| checkpoint | pass | Clean tree, revision 10 committed at `7bed4d0`, 15 ahead / 0 behind `main`. Clean revert point before task 11's code lands. |
| audit_trail | concern | `292/86/0` is asserted as judge-reproduced in three durable records (round-1 verdict md, both `verdicts.jsonl` lines) and corrected only in the spec. This round-3 entry is the correction; the older records remain unannotated. |

**risk: low — confidence: high.**

## Concerns

1. Provenance outruns validity: after revision 10 a false pass still prints a valid 40-char SHA.
   Measured residual — a present, non-empty, syntax-broken helper exits 2 on every command, so
   `0 relaxed`, exit 0. Deferral 5 stays deferred while ADR 0016 `:37-56` is being edited anyway.
2. No scenario in A–M falsifies part 2's non-empty half on any of the three sides. Measured: an
   empty helper flips the candidate to allow-everything — a *different* failure direction from
   absent, so the absent-case scenarios do not cover it by implication.
3. Revision 10 silently adds a dependent to deferral 3's comment-blind `grep -q 'lib/'`. The spec
   records the identical increment for deferral 1 but not this one; under-firing is the silent
   direction.
4. `292/86/0` is unreproducible. Measured `260/118/0`, exit 0. Partial deletion ruled out
   (`classify-git-command.py:68` imports `shell_segments` at module scope); empty helpers ruled out
   (they allow everything). The arithmetic requires a base allowing 86 or 204 of 378 — `main` allows
   118 — so a different configuration, not a different reading of the same run.
5. That unreproducible figure stands uncorrected in three durable records where it is asserted as
   judge-reproduced.
6. The destructive `rm -f` at `replay.sh:61` is guarded only by prose in three places; it is dead
   code in its own branch, and `checkpoint-before-modify.sh` is unregistered, so nothing
   computational stops a verbatim reuse against `$WT`.
7. Task 11 costs ~18 matrix runs at ~60s each plus two synthesised bases that do not survive a
   `/clear`; the accepting-direction sweep is both the most skippable step and the one that catches
   over-firing.
8. The harness still exits 0 when it reports relaxations — unsafe as a CI pass/fail step. Unchanged,
   queued, correctly disclosed.
9. Verified independently: the red reproduces exactly (`260/118/0`, exit 0, 61s); the ordering claim
   holds (sets compare equal, `cmp` on the absent candidate helper reports not-identical, the run
   proceeds); the natural insertion point at `replay.sh:73-77` already precedes the vacuity block.

---

# Observability verdict — `fix/replay-harness-base-pin` (implementation)

> **Round 2 (current, at `a5ee297`).** Round 1's verdict, at `e86ddb5`, is preserved verbatim at the
> bottom of this file under "Superseded — round 1". Same branch, same day, so both rounds share this
> filename by the naming rule; nothing from round 1 was discarded.

- **repo:** `.claude`
- **branch:** `fix/replay-harness-base-pin`
- **head_sha:** `a5ee297f182e01568045f5f0fd046dc3f97c5771`
- **stage:** implementation
- **ts (UTC):** 2026-08-05T21:19:32Z
- **base:** `main` (merge-base `56f1dfd`)
- **test command run by the judge:** `/bin/bash hooks/git-guard.test.sh` → **77 passed, 0 failed,
  exit code 0** (exit code captured before anything else ran)
- **previous verdict:** round 1 @ `e86ddb5` — `risk=low confidence=high`

## What was changed

Nothing about the actual fix. `git diff e86ddb5..a5ee297 -- hooks/` is **empty** — not one byte of
code moved since round 1. The single new commit is bookkeeping: it corrects two records that
disagreed with the repo.

Think of it as a lab notebook, not the experiment. The experiment (the replay harness that used to
compare a program against an identical copy of itself and call that a pass) was already done and
already checked. Round 1 found the notebook had two wrong entries. This commit fixes the entries.

The two fixes, both verified against the repo rather than taken on trust:

1. **The `phase: review` flag is now actually committed.** Round 1 judged a dirty working tree; the
   frontmatter flip was sitting uncommitted on disk. It is in `a5ee297` now, so the recorded head
   covers the on-disk state.
2. **The "blast radius" note no longer lies about its own size.** It said the change touched 3 files.
   `git diff --stat` says 6. The note now reads "measured pre-task-9, at `e5d1403`… final diff after
   task 9 is 6 files" and names the three files task 9 added. I counted: the real diff is exactly 6
   files, and the three named are exactly the three that appeared.

Plus `CODING_MEMORY.md` — the file that survives a session clear — was five tasks stale ("tasks 1-4
done, next is task 5"). It now says all nine are done at `e86ddb5`, records round 1's verdict, and
names the next step.

## Does it do what was intended?

Yes. Both corrections landed exactly as claimed, and my read of the fix itself is **unchanged from
round 1** — I say that on evidence, not to save effort: the hooks directory is byte-identical between
the two heads, so round 1's live reproductions (old harness false-passes at `378/0/0` exit 0; new one
refuses and names the SHA; Scenario I's `234/82/62` exact) carry forward untouched.

I still re-ran the two cheap things that gate freshness at this head:

| check I ran at `a5ee297` | result |
|---|---|
| `/bin/bash hooks/git-guard.test.sh` | **77 passed, 0 failed, exit 0** |
| Harness against base `main` (the old false-pass shape) | **REFUSED**, names base `56f1dfdf…`, **exit 1** |
| `git diff e86ddb5..a5ee297 -- hooks/` | empty — no code changed |
| Diff really is 6 files, as the corrected note now claims | confirmed |
| Task 8's three newly-named files match the actual additions | confirmed (ADR 0016, `git-guard-empty-index.md`, `shell-segments-redirects.md`) |

The deliberately-deferred item is handled correctly. Round 1 reproduced, live, that the default
`worktree` mode still prints `0 relaxed` / exit 0 for a candidate that is simply broken. That is
non-goal 2 in both the spec and ADR 0016 — disclosed before I found it, not discovered by me. This
session did **not** quietly widen scope to fix it; it is being put to the user as an open question.
Given this exact branch's own history (the two prior branches in this class each shipped a second
defect by widening mid-flight), refusing to self-authorize the fix is the right call, and I am not
scoring the deferral as a defect.

## What could go wrong / what I'm unsure about

No dimension is a `fail`. The honest residue:

**1. The known gap is still a gap, and disclosure doesn't change the mechanics.** Deferring it is
legitimate; what does not change is that in the mode people actually run, `0 relaxed` still is not by
itself proof of anything. A broken candidate that blocks everything scores zero relaxations and exits
0 — the pass shape. The only tell is a non-zero `stricter` count sitting next to it, and nothing forces
a reader to look. Keep quoting this tool as *base SHA + identical/stricter/relaxed*, never "0 relaxed".

**2. A committed file now points at an uncommitted one.** `CODING_MEMORY.md` cites
`coding-memory/observability-judge/2026-08-05-fix-replay-harness-base-pin.md` as the round-1 verdict.
That file is **untracked** (`git ls-files` → "Did you forget to `git add`?"), as is the `verdicts.jsonl`
change. So the memory index, which is the thing designed to survive a clear, currently points into
thin air from git's perspective. This is the same shape of defect round 1 flagged (a record that
disagrees with the repo), just one layer out — and it resolves the moment the judge artifacts are
committed, which has to happen before the PR anyway.

**3. Small wording imprecision in the checklist.** Task 9 reads "provenance notes on the four sites in
the part-6 table". The table has five rows: three got inline notes, one (`falsifier-base-pin.md:145`)
was already correct, one (ADR 0015) is amended by ADR 0016 instead per this repo's amend-by-new-record
convention. The sub-bullets underneath spell all of that out correctly, so the record is complete —
only the one-line headline is loose. Not worth a commit on its own; worth not propagating into the PR
description.

**4. Unchanged from round 1, still open, all disclosed:** the harness exits 0 even when it *does*
report relaxations (measured: 32 relaxed → exit 0), so it is unsafe to wire into CI as-is; there is no
test sibling guarding the harness (stated non-goal), so only ADR 0016 prevents a third recurrence of
this defect class; the `grep -q 'lib/'` membership probe matches comment lines (fails closed, so it is
loud, not silent); a no-argument invocation still dies with a raw `$1: unbound variable` instead of the
named `REPLAY ERROR`.

## What I'd double-check before merging

1. **Commit the judge artifacts** (this file and `verdicts.jsonl`) so `CODING_MEMORY.md`'s pointer
   resolves in a fresh clone. `doc-guard` already flagged the dirty tree at session start.
2. **Get the user's answer on the deferred non-goal 2** before the PR text is written, so the PR says
   "deliberately deferred, decision recorded" rather than going silent on a limit a judge reproduced live.
3. **In the PR description, quote the harness properly** — base SHA plus all three counts. A PR that
   cites "0 relaxed" alone from this tool would be repeating the exact mistake the branch exists to fix.
4. Optionally tidy task 9's "four sites" wording if the spec is touched again for any other reason.

## Dimensions

| dimension | verdict | note |
|---|---|---|
| intent | pass | Both round-1 corrections landed exactly as claimed and were verified against the repo, not the summary. Fix itself unchanged. |
| execution | pass | Judge re-ran the dependent suite at this head (77/0, exit 0 captured first) and re-confirmed the headline refusal live (exit 1, names `56f1dfd…`). |
| trajectory | pass | Targeted docs-only response to review findings; the tempting in-flight widening was explicitly escalated to the user rather than self-authorized — the correct lesson from this branch's own two prior failures. |
| regression | pass | `git diff e86ddb5..a5ee297 -- hooks/` is empty; `git-guard.sh` untouched; harness unregistered in `settings.json`; 3rd positional still defaults to `main`. |
| context_budget | pass | No rule/skill/prompt changes. `CODING_MEMORY.md` +23/−13 for a now-complete feature entry. |
| traceability | pass | Upgraded from round 1's `concern`: the blast-radius note now carries its measurement point (`e5d1403`) and the true 6-file count; memory index current. |
| success_masking | concern | Unchanged and disclosed: default `worktree` mode prints `0 relaxed`/exit 0 for a broken candidate (round 1 reproduced `292/86/0`), and a 32-relaxation run also exits 0. Recorded as non-goal 2 / ADR 0016 and deliberately deferred — not scored as a defect of this branch. |
| intent_drift | pass | `a5ee297` is docs-only and does precisely the two named fixes plus the memory sync. No new deps, no drive-by code edits, no silent scope growth. |
| checkpoint | pass | Single clean, revertible docs commit on top of nine granular ones; working tree now clean except the judge's own output. |
| audit_trail | pass | Commit message names round 1's verdict as its cause and states both slips; `CODING_MEMORY.md` records the verdict, the reproduced gap, and the next step. Nit: it cites an untracked file (concern 2). |

## Concerns (short form)

- Default `worktree` mode still prints the pass shape (`0 relaxed`, exit 0) for a broken candidate — disclosed non-goal 2, deliberately deferred to the user; mechanics unchanged by the disclosure.
- Harness exits 0 even when it reports relaxations (measured: 32 relaxed → exit 0); unsafe to wire into CI as-is.
- `CODING_MEMORY.md` (committed) cites the round-1 verdict file, which is untracked — the pointer dangles until the judge artifacts are committed.
- No test sibling for the harness (stated non-goal), so only ADR 0016 prevents a third recurrence of this defect class.
- Task 9's headline says "four sites"; the plan table lists five (3 annotated, 1 already-correct, 1 amended via ADR 0016). Sub-bullets reconcile it; the headline does not.
- `grep -q 'lib/'` membership test matches comment lines — fails closed, but is a heuristic.
- No-argument invocation dies with a raw `$1: unbound variable` instead of the named `REPLAY ERROR`.

**risk=low confidence=high** — the two record defects round 1 raised are genuinely closed and I verified
each against the repo; no code moved, so the earlier live evidence stands; the one substantive gap left
is pre-existing, disclosed, reproduced, and consciously deferred rather than overlooked.

---
---

## Superseded — round 1 (at `e86ddb5`), preserved verbatim

# Observability verdict — `fix/replay-harness-base-pin` (implementation)

- **repo:** `.claude`
- **branch:** `fix/replay-harness-base-pin`
- **head_sha:** `e86ddb5631235a2e38e7453de6b3d703ebe6c06c`
- **stage:** implementation
- **ts (UTC):** 2026-08-05T21:08:17Z
- **base:** `main` (merge-base `7bf2520`'s parent chain; diff taken vs `git merge-base main HEAD`)
- **test command run by the judge:** `/bin/bash hooks/git-guard.test.sh` → **77 passed, 0 failed** (5.7s wall)

## What was changed

`hooks/git-guard.replay.sh` is the repo's "did this change to the git guard make it weaker?" tool. It
runs two copies of the guard — an old one and the new one — over the same 63 commands in 6 repo
states, and reports every command the old one blocked but the new one lets through.

The problem: the "old one" was hard-wired to the word `main`. On `main` itself, or on any branch that
never edits the guard, the tool was quietly comparing the guard **against an identical copy of
itself** — and printing `378 identical, 0 relaxed, exit 0`, which is exactly what a hard-won genuine
pass looks like. Like weighing yourself twice on the same scale and announcing you haven't gained
weight.

This branch: adds a third argument so you can name the old version; refuses to run at all when both
sides are provably the same program; fails with a plain-English named error when a file it needs is
missing, empty, or the folder path doesn't resolve; and prints the real 40-character commit id of the
baseline in both the header and the summary instead of the word "main". Plus ADR 0016 recording the
rule, and one-line "which baseline was this measured against" notes on three older documents that
quoted a number from this tool.

## Does it do what was intended?

Yes, and I checked it myself rather than taking the summary's word for it:

| check I ran | result |
|---|---|
| Old harness (from `main`), relative path `.` | `378 identical, 0 stricter, 0 relaxed` — **the false pass reproduces exactly**, so the defect was real |
| New harness, same branch, absolute path, base `main` | **REFUSED**, names base `56f1dfd…`, exit **1** |
| New harness, relative path `.` | **REFUSED**, identical message — the relative-path route is genuinely closed |
| New harness vs a genuinely older base (`a9986b9~1`) | `346 identical, 0 stricter, 32 relaxed`, base printed as `b9b59e37…` at both sites |
| Self-contained base predating the helper split (`ac5afa2~1`) | `234 identical, 82 stricter, 62 relaxed` + the NOTE — **matches the claimed numbers exactly** |
| Missing worktree / unresolvable rev | named error, exit 1, correct invocation printed |
| `hooks/git-guard.test.sh` (the one dependent suite) | **77/0** |

The live hook `hooks/git-guard.sh` is untouched, the harness is not registered in `settings.json`, and
the third argument defaults to `main`, so old two-argument invocations still work. Production blast
radius is effectively zero — this is a developer tool.

## What could go wrong / what I'm unsure about

**1. The default mode can still print the pass shape for a broken candidate — I demonstrated it.**
I cloned the repo, deleted the two `hooks/lib/*.py` helpers the guard needs, and ran the harness in its
default `worktree` mode against a real older base. It printed:

```
378 pairs: 292 identical, 86 stricter, 0 relaxed (0 distinct commands)   exit=0
```

A candidate that is simply broken — it can't classify anything, so it blocks everything — scores **zero
relaxations and exits 0**, which is the headline "pass" criterion. The 86 "stricter" is the only hint,
and nothing forces a reader to look at it. This is disclosed (ADR 0016's "what this does not close",
non-goal item 2, and an in-code comment saying the worktree candidate is deliberately not validated),
so it is not a hidden defect — but it means "0 relaxed" is *still* not by itself proof of anything in
the mode people actually use. The summary's framing "closes four of five routes" is accurate on its own
terms and does not claim otherwise, but a reader could easily come away more reassured than the tool
earns.

**2. A run that finds real relaxations still exits 0.** Captured directly: the 32-relaxation run
returned exit code 0, indistinguishable from a clean run to any script or CI step. Disclosed in the ADR;
still a live foot-gun for anyone who wires this into automation.

**3. The blast-radius claim is stale at HEAD.** Task 8 in the spec (and the summary given to me) says
`git diff --stat main...HEAD` shows "only the harness, this feature file, and CODING_MEMORY.md". At
HEAD that is false — task 9 then added the ADR and edited two other feature docs, so the real diff is
**6 files**. The measurement was true when taken and the extra edits are one-line, disclosed, and
directly caused by the ADR's own rule; but the record now contradicts the repo, which is precisely the
"a number without its provenance" failure this branch exists to fix.

**4. `CODING_MEMORY.md` at HEAD is five tasks stale.** It says *"Tasks 1-4 done … Next: task 5"* and
pins the branch at `aa0420f`. All nine tasks are done at `e86ddb5`. That file is the thing that
survives a session clear, so a restore here would resume from a wrong picture of the branch.

**5. Nothing guards the fix.** There is no test sibling for the harness (a stated, reasoned non-goal),
so the only thing preventing this exact defect from returning is the ADR. That is a judgment control,
not a mechanical one — and this is the *second* time the class has bitten.

**6. Minor:** the "does this side use the helpers?" test is `grep -q 'lib/'` over the guard's bytes;
2 of the 3 matches in today's guard are comment lines. A guard that only *mentions* `lib/` in a comment
would be asked for helper files it doesn't use — that direction fails closed with a named error, so it
is loud, not silent. Also, invoking the script with no arguments still dies with a raw bash
`$1: unbound variable` rather than the nice `REPLAY ERROR:` message.

**7. Working tree was dirty when I judged.** `docs/features/replay-harness-base-pin.md` has an
uncommitted `phase: planning → review` frontmatter flip, so this verdict's `head_sha` does not cover
the current on-disk state. Docs-only, but the judge-guard match is against `e86ddb5`.

## What I'd double-check before merging

1. Commit the `phase: review` frontmatter flip, and refresh `CODING_MEMORY.md` to say tasks 1-9 done at
   `e86ddb5` — otherwise the next restore reads a branch that is five tasks behind.
2. Annotate task 8's blast-radius line ("measured before task 9; final diff is 6 files") so the spec
   stops disagreeing with `git diff --stat`.
3. Decide consciously whether item 2 in the non-goals (validate the worktree candidate's own helpers)
   should ride along. It is now a genuinely small change — the membership check already opens those
   files — and it is the difference between "0 relaxed" meaning something and not. Deferring is a
   defensible call given the last two branches shipped a second defect by widening mid-flight; just
   defer it *knowing* I reproduced the false-pass shape, not on the assumption it's theoretical.
4. When citing this harness in a future PR, quote **base SHA + identical/stricter/relaxed**, never
   "0 relaxed" alone — a nonzero `stricter` next to `0 relaxed` is the broken-candidate signature.

## Dimensions

| dimension | verdict | note |
|---|---|---|
| intent | pass | Built exactly the four routes scoped; the fifth is refused-by-record, not forgotten. |
| execution | pass | Judge re-ran the suite (77/0) and reproduced pre-fix false pass, post-fix refusal, real differential, and Scenario I's 234/82/62 exactly. |
| trajectory | pass | Red test first (`85bc35c`), one commit per task, self-corrected the two-clone setup mistake and recorded it as a setup error rather than a harness defect. |
| regression | pass | `git-guard.sh` untouched; harness unregistered in `settings.json`; 3rd positional defaults to `main`, so the old 2-arg call is preserved. |
| context_budget | pass | No rule/skill/prompt changes; `CODING_MEMORY.md` +6 net lines. |
| traceability | concern | Task 8's blast-radius record is contradicted by HEAD (3 files claimed, 6 actual); `CODING_MEMORY.md` five tasks stale. |
| success_masking | concern | Demonstrated: broken worktree candidate → `0 relaxed`, exit 0; and a 32-relaxation run also exits 0. Disclosed in ADR 0016, not closed. |
| intent_drift | pass | Two drive-by doc edits are one-line provenance notes, mandated by the ADR's own rule and listed in the checklist. No new deps. |
| checkpoint | pass | Nine granular, individually revertible commits; working tree dirty at judgment (docs-only frontmatter) is the only smudge. |
| audit_trail | pass | ADR 0016 states the rule, its limits, and a five-site provenance table; every task has a commit. |

## Concerns (short form)

- Default `worktree` mode still prints the pass shape (`0 relaxed`, exit 0) for a broken candidate — reproduced by the judge with the helpers deleted (`292/86/0`); disclosed as non-goal 2, not closed.
- Harness exits 0 even when it reports relaxations (measured: 32 relaxed → exit 0); unsafe to wire into CI as-is.
- Task 8 / summary blast-radius claim ("only 3 files") is false at HEAD — the real diff is 6 files after task 9.
- `CODING_MEMORY.md` at HEAD says "tasks 1-4 done, next task 5"; all 9 are done — the file that survives a clear is stale.
- No test sibling for the harness (stated non-goal), so only ADR 0016 prevents a third recurrence of this defect class.
- `grep -q 'lib/'` membership test matches comment lines (2 of 3 matches today) — fails closed, but is a heuristic.
- No-argument invocation dies with a raw `$1: unbound variable` instead of the named `REPLAY ERROR`.
- Working tree dirty at judgment time (`phase: review` uncommitted), so `head_sha` does not cover current on-disk state.

**risk=low confidence=high** — merging strictly reduces risk versus the status quo and the headline
route is independently falsified as closed; "low" refers to the merge, not to the harness being
trustworthy by default.
