# Observability verdict — `feature/phase-guard-hook` @ `0ee4bac` (round 7)

- **Repo:** `phase-guard-hook` (linked worktree at `.claude/worktrees/phase-guard-hook`)
- **Branch:** `feature/phase-guard-hook` · **HEAD:** `0ee4bac51f000777ac02b53d868a13665172ed8f`
- **Base:** `main` @ `8f0f16d` (true merge-base; `origin/main` deliberately not used)
- **Stage:** implementation · **Judged:** 2026-07-28T23:49:02Z
- **Filename note:** written as `-round7` rather than the bare slug because
  `2026-07-28-feature-phase-guard-hook.md` already holds today's round-1 verdict. Overwriting a
  committed audit record to satisfy a naming rule would destroy the evidence this file exists to
  preserve; rounds 2–6 set the same convention.

## Evidence I gathered myself

- `bash hooks/phase-guard.test.sh` → **122 passed, 0 failed** (run, observed, not taken on report).
- `shellcheck -x hooks/phase-guard.sh hooks/phase-guard.test.sh` → **exit 0**.
- `settings.json` parses; `PreToolUse` matchers are `['Bash', 'Task|Agent', 'Edit|Write|NotebookEdit', '*']` — a fourth block, as specified. Hook committed `100755`. Working tree clean.
- Three throwaway-repo probes of my own (all cleaned up, all outside this repo).

## What was changed

A new tripwire on the "don't start building before the plan is approved" rule. Until now that rule
was an honour system: a note at the top of the feature card said `phase: planning`, and everyone was
trusted to read it. This adds `hooks/phase-guard.sh`, which the editor consults before every file
write. If the project has a feature card still sitting at `planning`, and the branch you're on isn't
recorded by any card as its build branch, the write is refused with a message explaining the two
legitimate ways to unblock it. Documentation is never refused — including the card itself, so you
can always open the gate. The big fix on this branch: the guard used to ask "which project am I
standing in?" when it should have asked "which project does this file belong to?" Those differ
constantly here, and wherever they differed the guard was quietly switched off.

## Does it do what you wanted?

Yes, and it is materially better than it was at round 6. The suite is genuinely green, the shell is
clean, the registration is correct, and the reorder that fixes the wrong-repo bug is real — I
confirmed the guard now judges the *target's* repo. The first live run is a real step up in evidence
quality, and it did the honest thing: it **falsified its own document** and the stale number was
superseded in place rather than deleted.

Three things fall short of the standard this branch set for itself.

**1. The superseded cost figure left dangling reasoning — confirmed, in two places, unmarked.**
The supersession note at line 1574 is exemplary in form, but it only marks the table row where the
number appears. It even says the reasoning built on it "is cited elsewhere" — and then doesn't go
mark the citations. Both live at line ~820–866, roughly 740 lines *upstream* of the correction:

- The paragraph justifying withdrawal of the whole performance budget still reasons from "two
  operations are mandatory *before* step 3's early exit" with a 12.3 ms floor. Under the shipped
  code there are three, and the floor is understated by the ~22 ms `python3` startup its own table
  lists in a separate column as *excluded*.
- "The real lever is the ~22 ms `python3` startup … **larger than the entire non-opted-in path**"
  is now false (41.8 > 22). And: "**It does not burden the common case: step 4 runs after step 3's
  early exit, so a repo that never opted in never starts python. That is … the one performance
  claim here that rests on structure rather than on a stopwatch.**" I falsified this directly with a
  counting shim: **a never-opted repo invokes `python3` exactly once, every write.** The doc's only
  explicitly *structural* performance claim is now backwards, with no marker.

The ~41.8 ms itself **is** disclosed plainly and well ("what every repo on this machine pays on
every write, forever"). So the number is honest; the contradiction around it is unresolved.

**2. The reordered step sequence is internally consistent in the code and the test *names*, and
inconsistent in the doc.** The hook's own comments are right. The suite's labels were re-pointed
(`A1.2`/`A1.3` → step 4, `A1.4`/`A1.5` → step 3, `A2.1` → step 2). But the doc's canonical **Order
of operations** list (lines 202–249) still encodes the *old* order verbatim and unmarked — step 2 as
`git rev-parse`, step 3 as "Q5's cheap early exit … deliberately **after** step 2", step 4 as the
interpreter — and the fail-open audit tables' Step column is wrong in 5 rows. Only the narrative at
377–381 describes the new order. Two contradictory orderings in one canonical file is exactly what
the one-canonical-file discipline exists to prevent. (Minor: two suite *comments* still say "step 4"
for the interpreter, one of them directly above a label that says "step 2".)

**3. The fail-open enumeration still has a gap, and it is the same class, one step upstream again.**
Reproduced at HEAD, in a throwaway repo: an opted-in repo, un-superseded `planning` card, unclaimed
branch, `.git` unreadable → **exit 0, stdout empty, stderr empty**, while the control on the same
fixture denies. Byte-identical to a healthy allow. `git` reports this the same way it reports
"not a repo", so the audit's *Justifiably silent* row "Not a git repo / no root — out of scope
entirely" silently absorbs a second condition: git *refusing* (unreadable `.git`, `safe.directory`
dubious-ownership, corruption). The `cd`-failure exit **one line earlier** is in the identical
epistemic position and does speak, via `warn_if_cwd_opted_in` — so the machinery exists and THE RULE
is applied inconsistently across adjacent lines.

This is not a new finding. The round-5 *and* round-6 verdicts, both committed in this repo, list
"unreadable `.git` in an opted-in repo is silent" as carried and re-verified. It is neither fixed
nor recorded: `grep` finds no mention of `.git`, `safe.directory`, or dubious ownership anywhere in
the 1,668-line doc. Same for two other repeat findings — a dangling `docs/features` *directory*
symlink reads as "never opted in" (silent, whole repo), and the `awk length()` byte-vs-character
question raised in rounds 4–6 with no locale pinned anywhere in hook or doc.

The audit is a genuine improvement over reactive patching and it closed six-plus instances with
enforcing tests. But "the surface is now enumerated" is not fully earned while one instance survives
at HEAD, twice-reported and undocumented.

**Attribution.** The doc (line 370) — and the decisions summary given to me — state the cwd bug was
found by self-review and that "six judge rounds read that line without seeing it." The committed
round-6 verdict names it explicitly (`round6.md:101`) and prescribes the fix. Round 6 *did* see it.
The record credits the finding in the flattering direction, in the file that is the feature's
canonical account.

## What could go wrong / what I'm unsure about

- Every write in every repo on this machine now costs ~42 ms, forever, and only this branch's repo
  has opted in. Disclosed and user-accepted with measured numbers — but the section a reader would
  consult for cost still argues the opposite.
- A guard that goes silently dead when git can't read a repo is precisely the failure mode this
  branch spent six rounds hunting. Reach is low (permissions, shared/container checkouts,
  `safe.directory`), but the shape is the headline class.
- The hook is **registered but not armed** — nothing has run under the real harness beyond direct
  invocation. Day-one blast radius is genuinely nil (`origin/main` has no `docs/features/`; this
  branch's only card is at `review`), so arming denies nothing initially. The exposure is later,
  when the first `planning` card lands.
- Rollback path 3 is correctly withdrawn, and whether the harness reads exit 126 as *deny* is still
  unknown. Not verifying it is the right call — the experiment risks locking the machine — but it
  means the "worst case" branch of the rollback story is unproven, by choice.
- The parallel-worktree collision is a real governance contradiction with `core-conduct.md`,
  recorded not resolved. It belongs in the PR description, not just in this file.

## What I'd double-check before merging

1. Mark or fix the two stale Cost passages (lines ~823 and ~859–866). The "never starts python"
   sentence is the one to fix first — it is stated as structural, and it is false.
2. Reconcile the doc's Order-of-operations list and audit-table Step column with the shipped order,
   or stamp them superseded the way the cost row was. Same for the two suite comments.
3. Decide the unreadable-`.git` exit: route it through `warn_if_cwd_opted_in` like its neighbour, or
   write it into the *Justifiably silent* table as a knowingly-accepted conflation. Either is fine;
   silence in both the code and the record is not.
4. Correct the round-6 attribution at line 370.
5. Carry the parallel-worktree collision and the unarmed-until-merge status into the PR body.

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | pass | Builds the branch-scoped guard ADR 0011 specifies; the cwd fix moves toward intent, not away. |
| `execution` | concern | 122/0 verified by me, shellcheck clean, live run done — but one fail-open of the branch's own headline class reproduced at HEAD, and nothing has run under the real harness. |
| `trajectory` | pass | Instance-patching → systematic audit; a 3.4× cost accepted on measured numbers; a live run that falsified its own doc; rollback path 3 withdrawn on measurement rather than asserted. Reasoning, not luck. |
| `regression` | pass | Purely additive: 4th `PreToolUse` matcher (JSON validated, others untouched), new files, one gitignore line, one-sentence rules stub. Tree clean. |
| `context_budget` | pass | `rules/gates.md` grows one sentence inside an existing bullet — proportionate for a Tier 1 hook. The 1,668-line doc is on-demand, not always-on. |
| `traceability` | concern | The canonical Order-of-operations list and audit tables describe the pre-reorder hook, unmarked; the Cost section's structural claim is false with the correction 740 lines away. A reader of the canonical section gets the wrong picture. |
| `success_masking` | concern | 122 green is real but covers none of: the unreadable-`.git` route I reproduced, a dangling `docs/features` directory symlink, or locale-dependent `awk`. Green again means "everything enumerated passes", and the enumeration is what has been incomplete six rounds running. No unbounded or expensive loops; `cat-file --batch` cost measured and flat. |
| `intent_drift` | pass | Every hunk serves the feature; no unauthorized deps (bash/git/python3/awk are the sibling hooks' existing toolchain); no drive-by edits. |
| `checkpoint` | pass | Tests committed before implementation in every pair; rollback paths 1–2 verified; `settings.json` exempted so the guard can never block its own off switch; revert is one JSON block. |
| `audit_trail` | concern | Nine verdicts persisted, ADR 0011 written, round history tabulated — strong. But the cwd discovery is misattributed away from the committed round-6 verdict, and two prior-judge findings are neither fixed nor recorded. |

**Risk: medium · Confidence: high**

Medium, not low: a reproduced silent fail-open of the branch's headline class survives at HEAD, the
canonical doc contradicts the shipped code on step order and on a load-bearing performance claim,
and the hook has still never run under the real harness. Medium, not high: nothing is a `fail`, the
tests are real and I ran them, the cwd fix is correct, day-one blast radius is nil, and every
residual is either disclosed or one line from being disclosed.

High confidence: I ran the suite and shellcheck, validated the JSON and mode bits, confirmed the
control denies at HEAD, and falsified two doc claims with direct experiments in throwaway repos.

## Concerns

- Withdrawn 12.4 ms figure leaves two unmarked live citations at doc ~823 and ~859–866; the "a repo that never opted in never starts python" structural claim is false — falsified with a counting shim (1 invocation per write)
- Doc's canonical Order-of-operations list (202–249) and audit-table Step column still encode the pre-reorder order, unmarked, contradicting the narrative at 377–381 in the same file
- Silent fail-open reproduced at HEAD: opted-in repo, active planning card, unclaimed branch, unreadable `.git` → exit 0, empty stderr, control denies — same class the audit claims to have enumerated
- That exit was reported by the round-5 and round-6 verdicts and is neither fixed nor mentioned anywhere in the doc
- Adjacent exits treated inconsistently: `cd`-failure warns via `warn_if_cwd_opted_in`, the git-failure one line later is silent in the identical epistemic position
- Dangling `docs/features` *directory* symlink reads as "never opted in" (silent, whole repo); uncovered and undisclosed
- `awk length()` byte-vs-character portability raised rounds 4–6; no locale pinned in hook or doc, no record of the decision
- Doc line 370 misattributes the cwd discovery to self-review; the committed round-6 verdict names it explicitly
- Two suite comments still say "step 4" for the interpreter check, one directly above a label reading "step 2"
- ~42 ms per write in every repo on the machine, forever; disclosed at line 1598 but contradicted by the Cost section at line 818
- Hook registered but not armed; no evidence under the real harness, and whether it reads exit 126 as deny is deliberately unverified
- Parallel-worktree collision contradicts `core-conduct.md`'s parallel-agent invariant; recorded, unresolved, owed to the PR description
