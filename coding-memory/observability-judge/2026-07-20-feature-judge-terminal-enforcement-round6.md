# Observability Judge Verdict — round 6 (architecting, advisory)

- **Repo:** `suyatdev/.claude` · **Branch:** `feature/judge-terminal-enforcement`
- **HEAD:** `d77c26d737183667ec4c7b7619521461ae1a600c`
- **Stage:** architecting (advisory — does not block)
- **Artifact:** one spec in two files —
  `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-design.md` (§1–§5, §8–§12) and
  `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-contracts.md` (§6, §7)
- **Test command:** none runnable; nothing is implemented. Not a concern at this stage — §10 names the
  harnesses and two blocking spikes. Instead of a suite, I re-ran the design's own git claims against
  real git 2.50.1 and simulated its parser against its own two files.
- **Risk:** low · **Confidence:** high

---

## What was changed

Think of this design as installing a bouncer on the door of `git commit`. If the commit is carrying a
spec file, the bouncer stops it, sends the spec off to be graded in its own terminal window, waits for
the grade to land in a ledger, and only then opens the door. A second bouncer already exists on
`gh pr create`; this adds the missing one and moves both graders out of the main chat so they stop
eating its memory.

This round is a re-read after four fixes. The spec is now two files that count as **one artifact** —
because the design got long enough to split, and a split spec created a loophole: edit half of it, and
the other half's old passing grade still looks valid. The fix is to hash both halves together so
touching either one invalidates the grade.

## Does it do what you wanted?

Yes. All four fixes landed, and I verified each one myself rather than taking the summary's word:

- **The parser rule works.** I wrote the parser as specified and ran it on the design's own two files.
  Root resolves ROOT, companion resolves PART. I also ran the mutation §10 demands (scan the whole
  file instead of just the header) and confirmed it breaks — the root then shows 3 declaration blocks
  and is refused.
- **The `U` (conflicted-file) row is right.** I built a real merge conflict: entry is `UU`, dry-run
  exits 1, and `git rev-parse ":<path>"` exits **128** exactly as claimed. Routing it into the record
  branch really would block every commit during a rebase.
- **The "never a hang" claim is now correctly qualified** for ladder rung 3.
- **The stale line-count sentence is gone**, replaced by the invariant. Both files measure 748 and 737
  — under the 800 ceiling.

Every other measurable claim also checks out: all six pinned tool versions, the "211 / 144" hook line
counts, "ten of seventeen hooks at 10s" (exactly right), `judge-runs/` absent from `.gitignore`, and
the ~10ms dry-run (I measured 14.7ms). The "exactly two added agent inputs" fix is consistent in all
five places it appears.

**And the five-form commit table is correct.** I initially could not reproduce two rows — both times
that was my harness, not the spec. Stated so it isn't mistaken for a finding.

## What could go wrong / what I'm unsure about

**The pattern moved rather than broke.** You asked me to weigh this most. The specific sentence the
last round cited was fixed; the class was not. Three live instances:

1. **The whole-file-scan rationale names the wrong rule** (§5.3, §10's falsification target, and §7's
   scenario comment all say the same thing). They claim a whole-file scan makes this spec "resolve as
   a companion of itself" and get refused by "its own bidirectional and depth-1 rules." I simulated
   it: the root has **3** blocks, so the resolution table's **"two or more blocks → exit 2"** row fires
   first. Resolution never reaches the parts/part_of classification at all. Same exit code, different
   mechanism — the rationale was written when the table had 3 rows, the table was made total, and the
   rationale was never re-derived. This matters more than cosmetics: a falsification test written to
   the *stated* mechanism would assert the wrong branch and could pass for the wrong reason, which is
   the exact failure §10's mandate exists to catch.
2. **§6.2.2's "must not become an eighth entry"** — the list it points at now has eight items. The ack
   would be the ninth. A stale ordinal from when the amendment was one input.
3. **§11 still says "leaving 657 and 472 lines."** Git history shows the pair went 1101/0 → 684/696 →
   748/737. **657/472 was never true of any commit.** This sits in a document whose header now declares
   that measured numbers belong in `wc -l`, not prose. The repudiation was applied to the instance that
   was cited, not to the class.

**A new implementability hazard with no falsification target.** §5.2 shows
`git commit --dry-run --porcelain -z <same args>` — flags *before* the user's arguments. That position
is load-bearing and never called out. The prose reads additively ("the gated command's arguments
unchanged … **plus** those three flags"), and an implementer building argv naturally appends. I tested
appending:

- `git commit -- docs/superpowers/specs/s.md` → the flags are eaten as pathspecs, exit 1, no entries →
  §5.2 routes exit 1 to **allow**. A real spec commit walks straight through the gate. **Silent
  fail-open on the gate's core case.**
- `git commit -i -- other.txt` → exit 128 → fail-closed → blocks a legitimate commit.

§10 lists eight falsification mutations and none covers flag position, despite this being the highest
blast-radius error available in the detection core.

**A smaller residual in the new parse rule.** The header region is bounded by "the first `## `
heading," but the rule never says whether that scan is fence-aware. On these two files naive and
fence-aware agree (I ran both). A future spec with a fenced markdown example containing a `## ` line
above its declaration would lose its declaration under a naive scan. It fails toward standalone —
the direction §5.3 calls acceptable — but it is the same context-sensitivity bug class the fix just
closed, one level up.

**Still open and correctly disclosed:** S1 and S3 remain unmeasured. S3's worst case is the bad one —
a harness cap below 840s makes the gate fail open silently precisely when the judge is slow. The
design blocks implementation on both, which is the right call.

## What I'd double-check before merging

1. **Pin the flag-splice position** as a stated contract in §5.2, and add "append the dry-run flags
   after the user's argv instead of splicing them after `commit`" to §10's falsification list.
2. **Re-derive the whole-file-scan rationale** in all three places to name the "two or more blocks"
   row, so the test asserts the branch that actually fires.
3. Fix "eighth entry" → ninth, and delete or re-measure §11's 657/472.
4. Say whether the `## ` boundary scan is fence-aware.
5. Run S1 and S3 before any code — S3 especially, since its failure is silent.

---

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | Targets both stated problems; closes ADR-0003's deferral. All four cited fixes independently verified. |
| `execution` | concern | Nothing implemented (expected). Test plan is strong — falsification mandate, real-git requirement, run-dir-count assertions — but the highest-blast-radius detection error (flag position) has no falsification target. |
| `trajectory` | pass | Fixes attack root causes, not symptoms: the prior-violations hand-off was deleted rather than re-sequenced; the table was made total rather than given one more row; the region rule is structural rather than a convention. Corrections recorded, not quietly kept. |
| `regression` | pass | Additive nullable field, no migration, standalone path byte-for-byte unchanged, backward compat asserted against a pre-existing stored row. `git commit` blast radius is real but analyzed. |
| `context_budget` | concern | 1485 lines across the pair for one design; both halves under 800 individually. Not always-on context (loaded on demand), but a large share is meta-commentary on prior revisions, which taxes an implementer's attention. |
| `traceability` | pass | Every correction recorded with its reason; cross-refs resolve across both halves; §12 lists ADR obligations. |
| `success_masking` | concern | Three prose claims no longer match the mechanism they describe. The whole-file-scan one can produce a test that passes for the wrong reason. Separately, the flag-position error fails open silently. |
| `intent_drift` | pass | Scope stable. The two invariant amendments are declared, justified, bounded ("must not grow past those two"), and consistent across five sections. No drive-by edits, no new deps. |
| `checkpoint` | pass | Docs-only branch, one commit per round, cleanly revertible. No code written yet. |
| `audit_trail` | pass | Round-by-round history in the header, branch log, prior verdicts, escalations all attributable. |

## Concerns

- Whole-file-scan rationale names the wrong resolution rule in §5.3, §10 and §7 — simulated: 3 blocks
  trips "two or more blocks → exit 2" before parts/part_of is ever classified; a test written to the
  stated mechanism would pass for the wrong reason
- §5.2's dry-run flag position is load-bearing but unstated; appending instead of splicing makes
  `git commit -- <spec>` exit 1 → routed to ALLOW → silent fail-open on the gate's core case (verified
  on real git 2.50.1), and `-i` → exit 128 → false block
- No falsification target for flag position, despite §10 carrying eight other mutations
- Recurring "prose ahead of mechanism" pattern moved rather than broke: §11 still carries "657 and 472
  lines," a pair that matches no commit in history, in a document whose header now repudiates exactly
  that practice
- §6.2.2's "must not become an eighth entry" is an off-by-one — the list it references now holds eight
- Header-region boundary ("first `## ` heading") does not state whether the scan is fence-aware; naive
  and fence-aware agree on these two files but diverge on a spec with a fenced `## ` above its
  declaration
- §4.1 and §6.2.2 enumerate the compliance agent's pre-existing declared inputs with different
  membership (§4.1 omits base branch, which `agents/compliance-judge.md` does declare)
- S3 unmeasured: a harness cap below 840s makes the gate fail open silently exactly when the judge is
  slow; only observed precedent is 10s and the design asks for 900 (disclosed and blocking)
- S1 unmeasured: without `--bare`, hooks run inside the judge session and the design is deadlock-shaped
  if `JUDGE_SESSION=1` does not reach them (disclosed and blocking)
