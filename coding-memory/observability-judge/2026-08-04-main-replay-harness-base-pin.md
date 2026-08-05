# Observability verdict — replay harness base pin (architecting)

- **repo:** `.claude`
- **branch:** `main` (slug `main`)
- **head_sha:** `c461e4cd2dfb493a0b0e5d92e10ade7b98c99416`
- **stage:** `architecting` (design doc `docs/features/replay-harness-base-pin.md`)
- **ts:** 2026-08-05T02:36:47Z
- **risk:** high — **confidence:** high
- **advisory run** — does not block.

> **Filename note.** The convention name `2026-08-04-main.md` was already taken by an unrelated
> architecting verdict (verification-marker gate round 5, head `00583c21`). Writing there would have
> destroyed that record. This file carries the spec slug to disambiguate; the JSONL `branch` field is
> the raw `main`. Two architecting runs on `main` in one day is a collision the slug rule does not
> cover.

---

> **Lead with the failures.** `intent` and `traceability` are both `fail`, and neither is a
> style quibble — I measured both.
>
> **1. The retraction in Part 3 is aimed at measurements that were real.** All four cited figures
> came from runs where the two sides genuinely differed. Stamping "this proves nothing" on them
> would put a false claim into an ADR this repo can never edit.
>
> **2. The spec writes the right rule and then does not implement half of it.** Spec line 102:
> a harness "must state its baseline **in its output**." The refusal contract (lines 152-158)
> applies that only to the refusal. Passing runs stay anonymous — which is the exact failure mode
> that made this defect expensive.

---

## What was changed

Nothing yet — this is a design.

`hooks/git-guard.replay.sh` is a **comparison scale**. You put main's guard on one pan and your
branch's guard on the other, run 63 commands through 6 repo states, and it tells you whether your
branch ever lets something through that main would have blocked.

The bug: the scale is bolted to `main` and has no way to tell you it just weighed the *same box
twice*. On `main` with a branch that hasn't touched those files, both pans hold the identical
program, so "no difference" is guaranteed. I reproduced it:

```
$ bash hooks/git-guard.replay.sh .
63 commands x 6 states = 378 pairs: 378 identical, 0 stricter, 0 relaxed
VACUOUS_RUN_EXIT=0
```

The design proposes three things: **(1)** a third argument so you can pick the baseline, **(2)** a
refusal when all three compared files are byte-identical on both sides, and **(3)** a retraction of
the figure, via a new ADR 0016 plus correction notes on three feature-file citations.

## Does it do what you wanted?

**Parts 1 and 2: yes, and the reasoning behind them is good.** The "refuse only when *all three*
files match, not any one" decision is the sharpest thing in the spec, and it is correct — I checked
the blob hashes it rests on. Between `bc7da76` and `c461e4c`, `git-guard.sh` (`2b74507c`) and
`classify-git-command.py` (`2f8af693`) really are the same blob and only `shell_segments.py` moved.
A check keyed on "any file matches" would have refused that legitimate run. I also confirmed the
three-file set is the correct dependency closure today: `git-guard.sh` → `classify-git-command.py`
→ `shell_segments.py`, and `git-guard.sh` never touches `classify-pr-command.py`.

**Part 3: no.** The figures being retracted were not produced by vacuous runs.

- **`git-guard-empty-index.md`** — the spec calls this "the most wrong: it was not replayed against
  anything." It reports **162, 52, and 32 relaxed pairs** for its three candidates. A run comparing a
  program with itself cannot produce a single relaxed pair, let alone 162. The spec read the phrase
  "378 pairs" (the matrix *size*, 63×6) as "378 identical" (the vacuous *result*). The breakdown
  table showing 215/326/346 identical sits directly under the sentence it quotes.
- **`shell-segments-redirects.md` ×2 and `ADR 0015`** — the `378 identical` figure entered the file
  at `64ba2fa`, **2026-08-04 15:45:33**. The fix merged to `main` at `cc035d2`, **16:53:55** — sixty-eight
  minutes *later*. At run time the baseline was pre-fix and the worktree was post-fix. Two different
  programs. I re-ran that exact pair myself (`base=c461e4c`, `candidate=bc7da76`) and got `378
  identical` — the correct answer, for precisely the reason those documents *already* give: the
  matrix contains zero redirect shapes.

The only vacuous run in evidence is the one the spec performed today on `main` @ `c461e4c`, *after*
the merge, when the two sides converged. That is the reproduction, not the cited evidence.

## What could go wrong / what I'm unsure about

**The provenance hole does not close.** This is your central question, and the answer is: it only
closes today's hole. I ran the harness twice — once vacuous, once genuinely differential — and
diffed the result lines:

```
IDENTICAL OUTPUT LINE (vacuous run vs genuinely-differential run)
  63 commands x 6 states = 378 pairs: 378 identical, 0 stricter, 0 relaxed
```

A meaningful comparison and a meaningless one print the *same sentence*. The refusal catches the
meaningless one at the gate, but the line that gets copied into a document six months from now is
still unlabelled. Your instinct is right: **every run should name its resolved baseline**, and the
spec already says so at line 102 — it just never made it into the fix. The repo even has the
pattern: `shell-segments-falsifier.sh` prints `base=$BASE` on every run, pass or fail.

**Part 1 makes the existing output actively false.** Line 134 is
`printf 'DISTINCT COMMANDS main BLOCKS and %s ALLOWS:\n'` — a **fourth** hard-coded `main`, in the
output. Task 2 replaces only the three at lines 13-15. Ship it as tasked and a run with
`BASE_REV=bc7da76` announces "DISTINCT COMMANDS **main** BLOCKS". The one `main` that carries
provenance is the one the task list misses.

**Scenario B asserts something I measured to be false.** It expects "stricter is greater than zero,
because the redirect fix made the guard catch more." Measured on that exact pair: **0 stricter, 0
relaxed**. It cannot be otherwise — the spec says so itself twenty lines earlier (line 109-110: the
matrix "still contains zero redirect shapes"). The spec contradicts itself. B's *primary* job
(prove the refusal can stay silent) still works; its substantive claim does not.

**Scenario E does not discriminate as much as it claims.** It rules out the two crude cheats
(always-refuse fails B and C; never-refuse fails A). But consider the implementation the spec
explicitly rejects at line 87 — refusing on a **rev-string** match rather than content. Trace it:
A refuses ✓, B doesn't ✓, C doesn't ✓, D unaffected ✓. **All five scenarios pass on the wrong
implementation.** The missing falsifier is one line: base given as the *SHA of main*
(`c461e4c`) with candidate `worktree` must still refuse.

**Honest uncertainty.** I cannot rule out that the spec's author meant "these figures were never
*accompanied* by a statement of what they compared" — which would be true and useful. But the text
says "it was not replayed against anything" and "not evidence of no regression either." That is
void, not unverified.

**A drift risk worth naming.** An implementer treating Scenario B as an acceptance criterion, on
hitting 0 stricter, may "fix" it by adding redirect shapes to the matrix — walking straight into an
explicit non-goal.

## What I'd double-check before merging

1. **Re-verify the retraction table before writing ADR 0016.** Non-zero `relaxed` proves a run was
   differential; `git log -S` against the merge SHA settles the rest. Both take a minute. The spec
   used blob-SHA verification correctly for Scenarios B and C — apply the same rigour one section up.
2. **Decide what ADR 0016 actually says.** The *rule* is sound and worth recording — it has bitten
   twice. The retraction attached to it is not. The honest finding is stronger anyway: *these figures
   were valid, and it took archaeology to prove it, because the harness never stated what it
   compared.* That argues directly for the provenance line.
3. **Print the resolved base on every run**, not just the refusal — and fix line 134 in the same
   breath.
4. **Add the rev-string falsifier scenario** (base = SHA-of-main → must still refuse).
5. **Correct Scenario B's expected result** to `0 stricter, 0 relaxed`, and say why: the matrix
   cannot see the redirect fix.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | **fail** | Parts 1-2 on target; Part 3 retracts four measurements that were real, and enshrines it in an amend-only ADR. |
| `execution` | concern | Verification-by-execution is the right approach, but Scenario B's expectation is measurably false and Scenario E has a hole. |
| `trajectory` | concern | Root-cause split, the all-three-vs-any-one argument, and the non-goals are excellent. The retraction table asserts what four docs compared without checking — the very error the ADR codifies. |
| `regression` | concern | Tiny code blast radius (`git-guard.sh` untouched; replay is a manual harness, not in `settings.json` or CI). The risk is a *documentation* regression: false notes on four correct records. |
| `context_budget` | pass | No always-on rule, skill, or `CLAUDE.md` change. ADR 0016 loads on demand. |
| `traceability` | **fail** | Spec line 102 requires the baseline be stated "in its output"; the contract applies it only to the refusal path. Measured: vacuous and valid runs print a byte-identical line. |
| `success_masking` | concern | The total-tautology case genuinely closes. A green still masks the unlabelled baseline and a matrix with zero redirect shapes. Runtime bounded (~46s/run). |
| `intent_drift` | pass | Scope user-confirmed, three explicit non-goals, sibling deferred, no new deps. |
| `checkpoint` | pass | Clean tree at `c461e4c`, no branch yet, `phase: planning` / `branch: none` correct. Task 1 is a red-reproduce step. |
| `audit_trail` | concern | Single canonical file, line-cited, ADR immutability respected (0016 not editing 0015) — but the content it would permanently record is wrong. |

## Concerns

1. Part 3 retracts valid measurements: `git-guard-empty-index.md` reports 162/52/32 **relaxed** pairs — arithmetically impossible from a vacuous run; the spec misread "378 pairs" (matrix size) as "378 identical".
2. The `shell-segments-redirects` and ADR 0015 figures were recorded at `64ba2fa` (15:45:33), **68 minutes before** the fix merged to main at `cc035d2` (16:53:55); base and candidate genuinely differed, and the existing hedge is already correct.
3. ADR 0016 would permanently record a false retraction in a series this repo never edits, only amends.
4. Spec line 102 requires stating the baseline "in its output"; the refusal contract applies it only to the refusal path, so passing runs stay anonymous.
5. Measured: a vacuous run and a genuinely differential run (`base=c461e4c`, `cand=bc7da76`) print a **byte-identical** result line — the quoted-figure failure mode survives the fix.
6. Line 134 hard-codes `main` in the output header; task 2 replaces only lines 13-15, so a non-default base would falsely print "main BLOCKS".
7. Scenario B asserts `stricter > 0`; measured 0 stricter / 0 relaxed for that exact pair, contradicting the spec's own line 109-110 (matrix has zero redirect shapes).
8. The scenario set cannot falsify a rev-string vacuity check — the implementation the spec rejects at line 87 passes all five scenarios.
9. Drift risk: an implementer treating Scenario B as acceptance may add redirect shapes to the matrix to force `stricter > 0`, breaching an explicit non-goal.
