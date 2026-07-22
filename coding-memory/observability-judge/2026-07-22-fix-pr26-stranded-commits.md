# Observability Judge Verdict — fix/pr26-stranded-commits (implementation, gating)

- **Repo:** `.claude` · **Branch:** `fix/pr26-stranded-commits`
- **HEAD:** `2d5528ac15b4ded8d9de02bf060252e222e19999` (pushed; `origin` matches exactly)
- **Base:** `main` (merge-base `6291edcd4a7d6934fccda3c7d4c8dce799bc4a19` — the PR #26 merge itself)
- **Delta under review:** `git diff 6291edc..HEAD` — 4 commits, 8 files, +915/−15
- **Related:** `2026-07-22-feature-cmux-version-gate-round3.md` (`0ecec9a`) — its sole finding is
  the thing commit `bff9d8c` closes
- **Risk:** low · **Confidence:** high
- **Blocks the PR:** no. No dimension fails.

**Headline: the recovery is exact and the recovered test is real.** Content parity holds by two
independent methods, and the round-3 finding is closed by *measurement* — I reproduced the claimed
`80/1` RED exactly, then ran the counterfactual the author did not: the pre-fix test under the same
mutation is `79/0` fully green. The net had a hole; it does not now.

**The pushback is on the third question.** The root-cause analysis is *structurally correct at its
core and over-generalized at its edges*, and its mitigation is a fourth advisory lesson in a file
that already records three failed advisory lessons. Details in Ruling 3 — including the option the
analysis never considers.

## Test evidence — run by me, not taken on report

| Suite | HEAD `2d5528a` |
|---|---|
| `adapters.test.sh` | 24 / 0 |
| `adapters/cmux-exec.test.sh` | **81** / 0 |
| `adapters/cmux-layout.test.sh` | 34 / 0 |
| `dispatch-pane-agent.test.sh` | 39 / 0 |
| `run-pane-agent.test.sh` | 10 / 0 |
| `terminal-detect.test.sh` | 9 / 0 |
| **total** | **197 / 0** |

`shellcheck -x panes/adapters/cmux-exec.test.sh panes/adapters/cmux.sh` → exit 0, silent. Working
tree clean; `HEAD == origin/fix/pr26-stranded-commits`. Every number matches what was claimed.

### 1. Content parity — verified two ways, independently

The originals are still local, so I did not have to trust the reported empty diff.

| Check | Result |
|---|---|
| `git merge-base --is-ancestor <tip> main` for `9107345`, `dbe9289`, `27d3877` | **all NO** — genuinely stranded, not already in `main` |
| `git diff feature/cmux-version-gate..HEAD~1` (tree parity at the recovery tip) | **empty** ✅ |
| `git diff 9107345..bff9d8c`, `dbe9289..4c8b280`, `27d3877..d10e384` (per-step trees) | **all empty** ✅ |
| `git patch-id --stable` per commit, recovered vs original | **all three identical** ✅ |
| `git diff feature/cmux-version-gate..HEAD` | 1 file, +20 — exactly the new 4th commit, nothing else |

Per-commit patch-id parity is stronger than the reported end-state empty diff: it rules out two
errors cancelling across commits. They don't. The recovery is byte-exact.

### 2. Does the recovered test actually close the round-3 finding? — **Yes. Proven, not asserted.**

Run in a pristine `git archive HEAD` copy under `/tmp` (working tree never touched), each mutation
applied alone, `bash -n` checked, restored from backup between runs.

| Scenario | Result | Verdict |
|---|---|---|
| Baseline, scratch tree | 81 / 0 | control |
| **Unbrace the `unreadable` write** + **new** test | **80 / 1** | ✅ exact match to the claim |
| **Unbrace the `unreadable` write** + **old** test (as merged to `main`) | **79 / 0 green** | ✅ the hole round 3 found, confirmed real |
| Unbrace the `mismatch` write + new test | 80 / 1 | ✅ the other half still guarded — no coverage traded away |
| Flip the loop order (`garbage` first) + new test | 80 / 1 | ✅ the ordering guard is load-bearing, not decorative |

The failing assertion under the headline mutation is named precisely, and carries the real leak:

```
FAIL — unwritable state dir leaks nothing (unreadable write)
       (…/cmux.sh: line 63: …/ro-state/cmux-version-mismatch: Permission denied)
```

That is the exact `Permission denied` leak round 2 reported and round 3 proved was still
unguarded. The 79/0-vs-80/1 pair is the whole finding, discharged.

The third new assertion — *"the last loop iteration was the unreadable half"* — deserves note. It
is a guard-the-guard: it exists so the standalone on-screen-warning check below it cannot silently
start reading a stale `$ERR`. I mutated the loop order to see whether it could ever fire, and it
does (80/1). Cheap, non-vacuous, and the kind of thing that usually gets skipped.

## Ruling 3 — is the root-cause analysis right?

Asked to be skeptical of a party with an interest in "structural." I read `hooks/judge-guard.sh`
rather than reasoning from the summary. Verdict in three parts.

### 3a. The structural core is CORRECT — and I'd have reached it independently.

judge-guard compares the stored full `head_sha` against current `HEAD` exactly (its own header:
*"strict freshness … so any commit added after judging forces a re-run"*). That yields a genuine
fixed point:

- Judge at `X` → commit the verdict → `HEAD = Y ≠ X` → `gh pr create` is **blocked**.
- Re-judge at `Y` → `gh pr create` **passes** → commit that verdict → `HEAD = Z`. Window shifted,
  not closed.

There is **no ordering** in which "the audit trail is committed" and "a fresh verdict matches HEAD"
hold simultaneously. Committing the artifact invalidates the artifact. That is unsatisfiable by
construction, not by carelessness, and the entry is right to say so. The second half — that a user
merging a green PR from the GitHub UI is behaving correctly — is also plainly right; nothing warns
them, and nothing should require them to guess.

The repo's own history corroborates the pattern rather than the excuse: PR #23's entry already
records *"PR created BEFORE committing the audit trail (strict freshness), trail committed to the
branch immediately after"*. The window is opened deliberately and routinely. Three of those have
now been merged through.

### 3b. But the analysis over-claims at the edges, in the direction that flatters it.

Only **one** of the three stranded commits is structurally forced.

- `dbe9289` (the verdicts + tracking entry) — **forced.** 3a applies in full.
- `9107345` (the round-3 test fix) — **not forced.** The same file says so in its own words:
  *"PR created BEFORE the r3 follow-up landed, **deliberately**: judge-guard.sh gates
  `gh pr create` only, so the one-line test fix was pushed to the open PR rather than spending a
  fourth judge round."* That is a discretionary choice that uses the gate's create-only scope to
  land a substantive test change the gate never saw — against judge-guard's stated purpose, *"the
  gate always reflects exactly what will ship."* Defensible on cost grounds; it is not the
  freshness rule's fault.
- `27d3877` (memory corrections) — also discretionary, could have preceded the PR.

Filing all three under one "structural" heading makes the record read as blameless when a third of
it was a judgment call that deliberately routed around the gate. The distinction matters precisely
because the next reader will use this entry to decide whether to do the same thing again.

### 3c. The mitigation is inadequate — and one option is missing entirely.

The proposed remedy is *"state explicitly in the reply that more commits are coming."* Two problems.

**First, it is the fourth advisory lesson in a row.** `pr-tracking.md` already carries:

- PR #22 (line 222): *"the verdict files belong in the same commit train as the source, or in a
  follow-up before merge."*
- PR #24 (line 256): *"after `gh pr create`, any further branch commit must be pushed AND confirmed
  present in the PR before the user merges."*

Both are advisory. Both were written after an incident. Both were followed by another incident.
Advisory mitigations are **0 for 3** by this file's own evidence, and the new one is delivered
through the weakest available channel — a chat message — while the merge decision happens in the
GitHub UI, possibly in a later session, possibly on a phone. The entry concedes this itself
("would make it visible in the UI, where the merge decision is actually made") and then defers it.

**Second, the escalation threshold is internally inconsistent.** The heading says *"3rd occurrence
of this failure mode."* The mitigation says the UI-visible fix is *"worth doing if this recurs a
4th time."* By the entry's own framing the threshold has already been met. Setting the trigger one
occurrence beyond the present one is how a pattern stays unfixed indefinitely.

**Third — the option never considered: `gh pr create --draft`.** I grepped `skills/`, `hooks/`,
`rules/`, `CLAUDE.md`: drafts appear nowhere. Yet:

- I read judge-guard's classifier — it matches `toks[i:i+3] == ["gh","pr","create"]`, so
  `gh pr create --draft` passes through the **identical** gate with no change to the hook.
- GitHub **blocks merging a draft PR**. The merge affordance is removed from the UI, where the
  decision is actually made — no reliance on the user reading a message.
- `gh pr ready` when the trail is in. Total cost: one flag and one command.

The analysis's premise is *"the freshness rule cannot move, so the signal has to."* That is a false
dichotomy: the third option is to **make the PR unmergeable while the window is open**. That is
enforceable, free, and closes the failure mode rather than narrating it. I would adopt it now, not
at occurrence four — and note that "create as draft" is a candidate for judge-guard itself to
require, which would make it a rule rather than another lesson.

**Net ruling: structural — yes, at its core, and I verified it against the hook source rather than
taking it on report. Blameless — no, not for all three commits. Adequate mitigation — no.**

## Dimension table

| Dimension | Score | Basis |
|---|---|---|
| intent | **pass** | Re-lands exactly the three stranded commits, byte-identical by patch-id and per-step tree diff, plus one disclosed new docs commit. A recovery branch that recovers, and nothing more. |
| execution | **pass** | 197/0 and shellcheck-0 re-run by me. The headline mutation reproduces at exactly the claimed 80/1, and the counterfactual (old test, same mutation → 79/0 green) confirms the claim is about a real gap, not a restated one. |
| trajectory | **pass** | Cherry-pick with parity proved before trusting it; the original branch deliberately kept local as an independent reference. The round-3 fix was verified by mutation, not by inspection, and its guard-the-guard assertion is itself non-vacuous. Reasoning, not luck. |
| regression | **concern** | No source file changed, five suites untouched — but `feature/judge-terminal-enforcement` holds `CODING_MEMORY.md` at **198** lines while this branch takes it to **386**. `git merge-tree` confirms 3 files changed in both (`CODING_MEMORY.md` + both `verdicts.jsonl`). The jsonl conflicts are append-and-keep-both; the memory-index one is a real content conflict, and neither branch documents the ordering hazard. |
| context_budget | **concern** | `CODING_MEMORY.md` **386** lines against its own stated ≤200 ceiling (93% over), `main` is 382 — this branch adds 4 and moves the wrong way for the third consecutive branch. Always-on context. Mitigating: a sibling branch has it at 198, so the trim is genuinely in flight. |
| traceability | **concern** | The tracking entry is detailed, dated, sha-precise and mostly accurate — but its "structural" framing covers all three stranded commits when only `dbe9289` is forced; `9107345` is described in the same file as a *deliberate* post-creation push. The record therefore reads as blameless where it should read as one-third judgment call. See 3b. |
| success_masking | **pass** | The dimension this branch exists to improve, and it measurably does. `79/0 green → 80/1 RED` under the identical mutation, both halves independently proved guarded, the ordering guard proved able to fail. Round 3's only finding is closed by execution, not assertion. |
| intent_drift | **pass** | Exactly 8 files, all accounted for. No source change, no dependency, no drive-by edit. The one new commit was disclosed as new before review. |
| checkpoint | **pass** | Four small, self-contained, individually revertible commits; clean working tree; `origin` matches HEAD; the stranded branch retained locally so the parity claim stays independently checkable. Strong revert story. |
| audit_trail | **concern** | Attributable and thorough in content, but a workflow failure now in its **third** occurrence lives only in `pr-tracking.md` — no ADR under `docs/decisions/`, despite two prior lessons on the same failure mode both having failed. The escalation trigger is set at occurrence four while the heading reads occurrence three. See 3c. |

## Concerns

1. **The mitigation is the fourth advisory lesson for the same failure mode; the prior three failed.**
   `--draft` + `gh pr ready` closes the window enforceably, passes judge-guard unchanged (I read the
   classifier), and is considered nowhere in the repo. Adopt now, not at occurrence four.
2. **The "structural" framing covers commits it doesn't apply to.** `9107345` was a deliberate
   post-creation push exploiting judge-guard's create-only scope — the file says so itself.
   Separate the forced commit from the discretionary ones or the next reader repeats the choice.
3. **Escalation threshold is internally inconsistent** — heading says 3rd occurrence, remedy waits
   for a 4th.
4. **Guaranteed merge conflict with `feature/judge-terminal-enforcement`** on `CODING_MEMORY.md`
   (198 vs 386) and both `verdicts.jsonl`, undocumented on either branch. Decide the merge order
   deliberately.
5. **`CODING_MEMORY.md` at 386 lines vs its own 200 ceiling**, +4 on this branch — third
   consecutive branch to move it the wrong way while calling the trim out of scope.
6. **No ADR for a three-time structural workflow failure.** `docs/decisions/` is where a
   "judge-guard freshness vs. audit-trail ordering" decision belongs, especially if `--draft`
   becomes the rule.
7. **The audit trail for *this* branch will hit the very same window** the moment its PR is opened —
   the verdict you are reading cannot be committed before `gh pr create` without invalidating
   itself. Open as a draft and it is a non-event.

## What was changed

Think of it as re-posting three letters that fell behind the mailbox.

PR #26 was merged while three more commits were still in the air. They never made it into `main`.
This branch picks up exactly those three and re-sends them, unaltered — I checked the envelopes two
different ways and they are the same letters, not retyped copies.

One of the three matters more than the others. The last review found that a safety net had a hole:
the code correctly silenced an error message on *two* different paths, but the test only tugged on
*one* of them. Someone tidying the untested line in six months would have got no warning at all.
That commit widens the net to cover both. The other two are paperwork — the review write-ups
themselves, and two corrections to a memory file that pointed at a branch that no longer existed
and stated a test count two different ways four lines apart.

The fourth commit is new: a written-down account of *why* letters keep falling behind the mailbox.
This is the third time it has happened.

## Does it do what you wanted?

**Yes — and the important half is proved, not claimed.**

The claim was that the new test catches a bug the old one missed. I didn't take that on trust. I
took a clean copy of the code, deliberately reintroduced the exact bug, and ran both tests against
it. The old test: **79 passed, 0 failed** — completely happy, bug and all. The new test: **80
passed, 1 failed**, and the failure message contains the real `Permission denied` leak. That pair of
numbers is the entire point of the change, and it holds.

I also checked the new test didn't fix one half by breaking the other (it didn't — the other half
still fails when I break it), and that a small bookkeeping assertion inside it isn't just decoration
(it isn't — I made it fail on purpose). Full suite: **197 passed, 0 failed**. Shellcheck silent.

## What could go wrong / what I'm unsure about

- **The "it's structural, not carelessness" story is about two-thirds true, and the missing third
  is the interesting one.** The core is genuinely unavoidable: the gate demands the review be fresh
  for the *exact* commit you're shipping, so committing the review paperwork immediately makes it
  stale. You literally cannot have both. I checked the hook's source, not just the summary — that
  part is right. **But one of the three stranded commits was a test fix that was deliberately
  pushed after the PR opened, to dodge a fourth review round.** The write-up admits this in its own
  words, then files it under the blameless heading. That's the bit I'd push back on.
- **The proposed fix is "remember to say it out loud," and that has now failed three times.** The
  same file already contains two earlier versions of that same promise, written after the two
  earlier incidents. A message in a chat window doesn't reach the person clicking Merge on GitHub
  next Tuesday.
- **There is a free, enforceable fix nobody mentioned: open the PR as a draft.** GitHub won't let
  anyone merge a draft. The review gate accepts `gh pr create --draft` with no change at all — I
  read the code that decides. Then flip it to ready when the paperwork's in. The write-up says "the
  rule can't move so the signal must" — but the third option is to take the Merge button away while
  the window is open.
- **Two branches are fighting over the same memory file.** This one grows it to 386 lines; a
  sibling branch has trimmed it to 198. Whichever merges second gets a messy conflict, and neither
  branch mentions the other.
- **That memory file is still nearly double its own stated 200-line limit**, and this is the third
  branch running to nudge it upward while calling the cleanup someone else's job.
- **This verdict will hit the exact same trap.** It can't be committed before the PR is opened
  without invalidating itself. Open the PR as a draft and the problem disappears.

## What I'd double-check before merging

1. **Nothing blocks the PR.** No dimension fails; the recovery is exact and the test is proved.
2. **Open it with `gh pr create --draft`.** Then commit this verdict, push, and `gh pr ready`.
   That closes the window this branch exists to document, on this very branch, at zero cost — and
   is far better evidence the lesson landed than another sentence about it.
3. **Split the root-cause entry into "forced" and "chosen."** One line. `dbe9289` was forced;
   `9107345` and `27d3877` were choices. Otherwise the next reader inherits the shortcut along with
   the excuse.
4. **Move the escalation trigger to now.** The heading says third occurrence; don't wait for a
   fourth to do the enforceable thing.
5. **Decide the merge order against `feature/judge-terminal-enforcement`** before either lands —
   `CODING_MEMORY.md` conflicts hard (198 vs 386) and both `verdicts.jsonl` files overlap.
6. **Consider an ADR** for the judge-guard-freshness vs. audit-trail-ordering tradeoff, especially
   if `--draft` becomes the standing rule rather than another lesson.
