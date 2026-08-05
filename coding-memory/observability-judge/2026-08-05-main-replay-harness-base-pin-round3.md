# Observability verdict — replay harness base pin, revision 3 (architecting, round 3)

- **repo:** `.claude` · **branch:** `main` · **head_sha:** `ea088b55d5871ef1632911cc44a342ee68752aac`
- **stage:** architecting (advisory — does not gate the PR)
- **spec:** `docs/features/replay-harness-base-pin.md` revision 3, blob `30c8c3ec` (matches dispatch)
- **ts:** 2026-08-05T04:52:43Z
- **risk: medium · confidence: high**

> **filename note:** the canonical `2026-08-05-main.md` was free, but rounds 1 and 2 of this spec live
> at `2026-08-04-main-replay-harness-base-pin*.md`. Kept the spec slug + round suffix so the three
> reads stay contiguous and a second `main` verdict today cannot collide. JSONL `branch` stays `main`.

---

## What was changed

Still a spec — no code, no branch. `phase: planning`, `branch: none`, tree clean.

The script under discussion (`hooks/git-guard.replay.sh`) is a **scale for comparing two safety
checks**. Old guard on one pan, new guard on the other, 63 commands × 6 repo states = 378
weighings, and it shouts if the new one lets through something the old one blocked.

The defect: the scale never writes down *what it weighed*. Its baseline is the branch `main` — a
label that points at different code every week — and it prints nothing about which code that was.

Revision 3 makes three changes on top of revision 2, all of them things prior reads asked for:

1. **"Print the resolved base" is now nailed down to a 40-character commit SHA**, with `main` as a
   printed string explicitly forbidden, and a clause saying the rule "must not be satisfiable by
   printing `base main`."
2. **Scenario G is pinned to a non-vacuous base.** As written before, it inherited the default and
   would have been refused before it tested anything.
3. **The citation sites are enumerated in a table** — five sites across four files.

## Does it do what you wanted?

**Largely yes, and the movement since round 2 is real.** I re-ran the harness rather than reasoning
about it.

**Closed since round 2, verified:**

| round-2 item | status |
|---|---|
| "resolved base" under-specified | ✅ now 40-char SHA via `git rev-parse "$BASE_REV^{commit}"`; verified it yields 40 chars for `main`, `b17a666`, `f5c5689` |
| Scenario A can't test the default-base run | ✅ Scenario A now asserts the SHA form — the only scenario that can, since every other passes an explicit base |
| sibling's format imports the gap | ✅ spec now explicitly says *do not* copy `shell-segments-falsifier.sh` |
| Scenario G tested nothing | ✅ pinned to `b17a666`; I measured that this matters (below) |
| "three citing documents" when four exist | ✅ table of 5 sites / 4 files — I checked every line number, all accurate, and a full sweep finds no fifth file |
| Scenario C verified only mirrored | ✅ **I ran it in its named base-side orientation: `358 identical, 20 stricter, 0 relaxed`** — exactly as specified |
| exit-code tally limits left implicit | ✅ named in non-goals *and* the ADR is required to state them, with an explicit anti-over-claiming clause |

**Scenario G's fix is load-bearing, and I proved it.** Same base (`b17a666`), same everything —
only the worktree path form differs:

```
WT=/Users/marksuyat/.claude  ->  358 identical, 20 stricter, 0 relaxed   (exit 0)
WT=.                         ->  378 identical,  0 stricter,  0 relaxed   (exit 0)
```

Route 3 is live, and the two runs disagree while both look clean. Also visible in that output: the
header printed `DISTINCT COMMANDS **main** BLOCKS` while the base was `b17a666` — the fourth
hard-coded `main` is real, and task 6 covers it.

**A nice piece of unplanned evidence for part 5:** `main` resolved to `c461e4c` when this spec was
planned and resolves to `ea088b5` now. The moving-ref problem the design exists to fix moved
*during the spec's own authoring*. (The three guard files themselves did not move — I checked all
three blobs — so every measured row still reproduces at HEAD.)

## What could go wrong / what I'm unsure about

### 1. Round 2's top two recommendations were dropped, with no rationale recorded

Both are still open, and the revision-3 changelog lists only the three compliance findings — a
reader cannot tell whether these were considered and rejected or simply missed.

**(a) No dirty-worktree scenario.** The spec's longest, most-argued bullet is "compare the bytes
that will actually execute — on disk, not `git show HEAD:`". **No scenario pins it**, because A–H
all run against a clean tree (verified clean). An implementation using `git show HEAD:` passes all
eight and reopens route 1 as a false green the moment the worktree is dirty — which is the
harness's normal habitat, a feature branch mid-work.

**(b) No "only `git-guard.sh` differs" base.** A vacuity check keyed on `shell_segments.py` alone
passes all eight scenarios and is wrong. I re-enumerated the full history to check whether the
scenario set *could* catch it:

```
commits with all three files present:                    62
commits where ONLY shell_segments.py differs from HEAD:  18
commits where ONLY git-guard.sh differs from HEAD:        0
```

Zero. The one file the scenarios vary is exactly the one a lazy comparator would key on, and no
in-repo base can falsify it. It has to be synthesized.

> **Method note, because it nearly bit me.** My first enumeration returned "0 commits with all three
> files present" — which would have been a fabricated confirmation. This shell applies zsh's `:h`
> (dirname) modifier to `"$c:hooks/..."`, mangling the path to `.ooks/...`, so *every* lookup failed
> and the check could not have found anything. I only trusted the second run because it first
> demonstrated it could find things (62 and 18 above).

### 2. Part 2 would falsely refuse a valid base — and I sharpened why

Round 2 flagged that fix part 2 makes the spec's own measured row 4 (`e3b09ba`) unrunnable. It is
worse than a bookkeeping conflict. I checked what `e3b09ba` actually is:

```
$ git show e3b09ba:hooks/git-guard.sh | grep -E 'classify-git-command|shell_segments|lib/'
(no output — the old guard is self-contained and needs no libs)
```

So `e3b09ba` is a **valid, functioning base** whose libs simply did not exist yet — and its row is
mixed (234/82/62), proving it really ran. Part 2's blanket "all six `git show` calls must succeed
and yield non-empty" turns it into a hard error. That is a **false refusal**: the mirror image of
the false pass this spec exists to remove.

The spec reasons beautifully about all-vs-any for part 3's vacuity check ("only *nothing differs*
is vacuous") and then applies an undiscriminating all-must-exist to part 2. Meanwhile the non-goals
still cite row 4's 62 relaxed rows as follow-up work — work this change makes unreproducible. No
scenario covers **partial** absence (guard present, libs absent); E covers only total absence.

### 3. The default mode has no candidate-side integrity check at all — measured

This is my main new finding. Part 2 validates *extractions*. In the default `UNDER_TEST=worktree`
mode **there are no extractions for the candidate** — `NEW` is the on-disk file. Part 4 checks that
`$WT/hooks/git-guard.sh` exists, but not its libs. I measured what happens when they are missing:

```
rc=2  ls -la
rc=2  git status
rc=2  git commit -m x
rc=2  git push --force
```

`git-guard.sh:56` fails closed, so the candidate **blocks everything, including `ls -la`**. A
candidate that blocks everything can never register a relaxation, so the headline number is
`0 relaxed`, exit 0 — a silent false pass. The spec knows this shape (it is queued limit 2) and
queuing it is a legitimate user decision. The part worth stating is the **interaction**:

> After part 5, that false pass will print a correct, resolved 40-character base SHA beside it.

The figure will *look* audited. This design improves attribution faster than it improves validity,
and provenance on an invalid comparison is more persuasive than no provenance at all. That is a
real, if second-order, way to make things worse — and it is cheap to neutralise in wording.

### 4. Candidate-side identity is still unprinted

Part 5 pins the base immaculately and then records the candidate as the literal string `worktree`.
A figure six months from now reads "base = `<40-char SHA>`, candidate = worktree" — which commit,
and whether the tree was dirty, are exactly the facts revision 1's archaeology needed. Round 2's
free fix still stands: part 3 already reads all six files' bytes, so printing their six content
hashes costs nothing and closes both sides at once.

### 5. Smaller

- Scenario H ("no implementation hard-wired to refuse, or to pass, satisfies both halves") is true
  but rules out only the two *constant* implementations — it still reads as a general
  discrimination proof, and §1(a)/(b) are the counterexamples.
- Does the design's value depend on the three out-of-scope tally defects? **No.** It closes five
  named routes and adds real provenance regardless. But the *ADR's claim surface* does — hence §3.

## What I'd double-check before merging

1. **Add the dirty-worktree scenario.** Uncommitted edit to one of the three files, asserting the
   comparison follows on-disk bytes. Without it the spec's most-argued bullet is unpinned.
2. **Add a synthesized "only `git-guard.sh` differs" base.** Measured: no such base exists in 628
   commits, so this one cannot be borrowed from history.
3. **Reconcile part 2 with `e3b09ba`** — it is verifiably self-contained, so require the *guard*
   plus any lib it actually references, or say plainly that pre-lib bases are now out of support
   and drop the row-4 follow-up claim. Add a partial-absence scenario either way.
4. **Have ADR 0016 say the printed base attests provenance, not validity.** The ADR already has an
   exemplary anti-over-claiming clause about the tally; one more sentence covers §3.
5. **Print candidate identity too** (worktree path + `HEAD` + dirty flag, or the six content
   hashes part 3 already computes).
6. **Record why round-2's two scenario recommendations were not taken**, if that was deliberate.

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | Targets the queued defect precisely; all three revision-3 changes are prior findings correctly implemented; round-1's reversed premise re-verified and holds. |
| execution | concern | Every measured claim reproduced (C in its named orientation, G's route-3 flip, all five citation line numbers). But the scenario set is the artifact that declares this done and still admits two wrong implementations, both named a round ago. |
| trajectory | pass | Three rounds of measurement-driven self-correction: retraction reversed, Scenario B's number fixed, "limit 2 is not a case of limit 1" corrected, ADR forbidden from over-claiming. Reasoning, not luck. |
| regression | concern | Part 2 would falsely refuse `e3b09ba`, verified self-contained; non-goals still cite its 62 rows as future work. No partial-absence scenario. Blast radius otherwise tiny — manual harness, not in `settings.json`, `git-guard.sh` untouched. |
| context_budget | pass | One script, one ADR, four provenance notes. No always-on rule/skill/prompt surface. |
| traceability | concern | Base side is now closed properly — 40-char SHA, anti-gaming clause, testable on the default run. Narrower residual than round 2: the candidate side of the same figure is still unidentified, so part 5's own goal ("a figure carries its provenance") is half-met. |
| success_masking | concern | Two wrong implementations pass A–H; the `shell_segments`-keyed one re-confirmed unfalsifiable in-repo (0 of 628 commits). Measured silent false pass survives in default mode (libs missing → rc=2 everywhere → 0 relaxed, exit 0), and part 5 will now decorate it with a valid base SHA. |
| intent_drift | pass | Tight explicit non-goals, user decision to queue recorded, no new dependencies, deferred work named rather than absorbed. |
| checkpoint | pass | `phase: planning`, `branch: none`, tree clean at `ea088b5`, no branch cut, no gate transition taken. Task 1 is a red-reproduce step that forbids deleting the probe. |
| audit_trail | pass | Citation table verified accurate line-by-line and complete against a full sweep; ADR immutability honored (0015 untouched, 0016 free); the ADR is required to state its own limits — above bar. |

## Concerns

- No dirty-worktree scenario; the on-disk-bytes bullet stays unpinned, so a `git show HEAD:` implementation passes A–H and reopens route 1 as a false green on the harness's normal habitat
- No "only `git-guard.sh` differs" scenario; re-enumerated history with a corrected probe — 62 commits have all three files, 18 are shell_segments-only, **0** are guard-only, so this falsifier cannot be borrowed and must be synthesized
- Part 2's blanket "all six extractions non-empty" would falsely refuse `e3b09ba`, whose guard is verified self-contained — a valid base turned into a hard error, the mirror of the false pass
- Non-goals still cite row 4's 62 relaxed rows as follow-up work that part 2 makes unreproducible; no partial-absence scenario (E covers total absence only)
- Measured: in default worktree mode a candidate missing its libs exits 2 on every command incl. `ls -la` → `0 relaxed`, exit 0; part 2 cannot see it (no extraction in that mode) and part 4 checks only `git-guard.sh`
- Part 5 will print a correct 40-char base SHA beside that still-possible silent false pass — provenance improves faster than validity; ADR 0016 should say the base attests provenance, not comparison validity
- Candidate-side identity still unprinted (path + HEAD + dirty flag); the six content hashes part 3 already computes would close it for free
- Round-2's two scenario recommendations dropped without recorded rationale; the revision-3 changelog lists only the three compliance findings
- Scenario H rules out only the two constant implementations but still reads as a general discrimination proof
