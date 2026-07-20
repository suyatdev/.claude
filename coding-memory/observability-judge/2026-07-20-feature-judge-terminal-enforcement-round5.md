# Observability Verdict — judge terminal enforcement (architecting, round 5)

- **Repo:** `.claude` (`suyatdev/.claude`) · **Branch:** `feature/judge-terminal-enforcement`
- **HEAD:** `8de76f9d41d4eaf2c1545edb3daef7a94c926314`
- **Stage:** architecting (advisory — does not block)
- **Timestamp:** 2026-07-20T19:15:15Z
- **Artifact:** two-file spec unit —
  `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-design.md` (684 lines) +
  `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-contracts.md` (696 lines)
- **Filename note:** written as `-round5` rather than the bare branch slug, following this store's
  established round-suffix convention. The bare slug is taken by the round-1 verdict; overwriting it
  would destroy an audit record this gate exists to preserve.

---

## What was changed

Imagine a building inspector who is *supposed* to sign off on blueprints, but signing off is
currently on the honour system — the architect can just walk past the office. This design bolts the
inspector's door onto the corridor: from now on, saving a blueprint (`git commit` on a file under
`docs/superpowers/specs/`) physically cannot complete until the inspector has stamped it. A new
`hooks/spec-guard.sh` is that door.

Two supporting changes come with it. First, the inspector now works in his own office instead of
sitting in your room using your desk space — both judges move out of the main chat session into
their own terminal panes via `bin/judge-launch.sh` plus five small libraries. Second, and new this
round: a blueprint is now allowed to be *several sheets of paper*. The stamp covers the whole set,
so you cannot edit sheet 2 and still wave sheet 1's stamp at the door.

That last part exists because this very design became two files, and in doing so broke its own gate.

## Does it do what you wanted?

Yes. The three things you asked for are all here and are load-bearing rather than decorative:

- **The gate is deterministic.** It closes ADR-0003's deferral honestly — a commit recording a spec
  genuinely is a script-decidable "spec is done" moment.
- **Terminal output is never trusted.** The verdict store is the only authority, re-read after the
  judge signals completion. This is stated as security invariant #1 and the whole architecture obeys it.
- **The unit model fixes the hole the split opened.** Edit the companion alone and the root's verdict
  correctly reads stale. §10 names this as "the single highest-value case" and it is right to.

I independently re-ran the detection evidence against real git 2.50.1 rather than reading the tables.
**§5.2's claims hold.** `git commit -i -- other.txt` does record a staged spec (the hole a hand-written
form table missed). `--amend` does re-list the whole file set. An untracked spec does produce a `??`
entry with exit 1 and must not read as detection. Delegating to git's own parser instead of
enumerating commit forms deletes the bug class rather than patching its instances — that is the
right call and it survives contact with the real tool.

I also probed nine git states looking for a way this gate could jam the most-run command in the repo.
**Good news: no ordinary state trips the fail-closed branch.** Unresolved merge conflict, rebase in
progress, cherry-pick in progress, unborn branch, detached HEAD, clean merge pending — all return
exit 0 or 1, never the exit > 1 that would block every commit. The blast radius is smaller than the
design's own framing fears.

## What could go wrong / what I'm unsure about

**1. The spec-unit declaration has no parse rule, and the design's own file breaks the obvious ones.**
This is my main finding and it sits exactly where you asked me to look — the newest, least-reviewed
logic. §5.3 says each file declares its role in "a fenced `yaml` block near the top." *Near the top*
is not script-decidable. Worse, the root spec contains **three** blocks matching `spec_unit:`:

| Line | Block | Role |
|---|---|---|
| 39 | `spec_unit: parts: [contracts.md]` | the real declaration |
| 400 | `spec_unit: parts: [...]` | an **illustration** inside §5.3 |
| 407 | `spec_unit: part_of: <the root itself>` | an **illustration** inside §5.3 |

A parser that scans all yaml blocks — a natural implementation, and the defensible one given how
vague "near the top" is — sees the root declaring both `parts:` *and* `part_of: <itself>`. Under
§5.3's own bidirectional-consistency and depth-1 rules that is a broken unit, and the gate refuses
the commit with "broken spec unit," launching nothing. The root spec states at line 34 that "the
design's first user is the design itself." Under a plausible reading of its own rules, its first
user is refused. The fix is small (pin the rule: first fenced yaml block containing a `spec_unit`
key, before the first `##` heading — or require a dedicated marker), but it must be written down,
because right now the implementer picks it and no test catches a wrong pick.

**2. §5.2's decision table has an undefined case, in a state this workflow produces.** I reproduced
it: conflict on a spec file yields exit 1 with entry `UU docs/superpowers/specs/s.md` — column 1 is
`U`. Walk the table: row 1 needs `X` in `M A R C` (no); the `D` row (no); the exit-0-or-1 row requires
*no spec entry outside `??`/`!!`*, but there is one (no); the exit > 1 row (no). **No row matches.**
The benign reading is exit 0 — git refuses an unmerged commit anyway — but nothing says so. And if an
implementer instead routes `U` into the record branch, the precondition itself breaks: I confirmed
`git rev-parse ":<path>"` fails on an unmerged path with *"is in the index, but not at stage 0."*
Rebasing or merging a spec branch is routine here, so this is reachable, not exotic.

**3. S3 remains the sharpest edge, and its framing is correct.** If the harness caps hook timeouts
below 840s, the gate fails open *silently* precisely when the judge is slow — a commit that looks
judged and never was. The 10s-observed vs 900s-requested gap is a 90× extrapolation. The design
blocks implementation on measuring it and pre-commits to the design fork (blocking-and-retrying)
rather than quietly lowering the deadline. That is the right handling of a known unknown; I have no
correction to offer, only agreement that it must be measured first.

**4. Rung 3 can block a commit for the full 840 seconds.** The Terminal/`osascript` rung has no
liveness probe (§6.1's ladder table says so plainly). §8 asserts every path ends in "a closed gate or
a clear message — never a hang," but a SIGKILLed Terminal pane on rung 3 leaves no trap, no sentinel,
and no probe — you wait out the entire deadline. Bounded, not infinite, and only on a freshness miss.
Still, 14 minutes on `git commit` deserves a caveat in §8 rather than an unqualified "never a hang."

**5. Self-reporting: substantially better, still not verified-by-default.** You asked me to judge this
with the branch's recurring failure mode in view. The improvement is real and I can point at it: the
`dbf48ae` round *reproduced my prior finding before accepting it*, and caught that its own first
reproduction was measuring `tr`'s exit code rather than git's. That is genuine falsification
discipline. §2's scope table now names both amended invariants.

But the pattern recurred at HEAD. The header states *"Final: 672 and 693 lines."* The actual files are
**684 and 696**, and `git show` confirms they were 684/696 *in the very commit that wrote that
sentence*. The number was never true — it was estimated, presented as measured, and round 4's process
did not catch it. Consequence: cosmetic. Signal: the same shape as finding #1 — prose written as
though a mechanism were pinned down when it is not. Minor artifact of the same edit: §2's out-of-scope
column now lists "rubric or scoring" and "rubric, scoring, or reasoning" as two separate rows.

**Does §10's falsification mandate cover the new unit logic?** Mostly yes, and better than I expected —
there are explicit mutation targets for keying on `spec_blob_sha` instead of `spec_unit_sha`, counting
rounds per member instead of per unit root, and letting the judge recompute rather than echo. Those
are the three ways the unit model could rot, and each is covered. **The gap is the declaration parser**:
there are test *cases* for malformed declarations, but no mutation target for block selection — which
is unsurprising, since finding #1 shows there is no contract to mutate against.

## What I'd double-check before merging

1. **Pin the `spec_unit` block-selection rule in §5.3**, then confirm this design's own two files
   resolve correctly under it. Add a falsification target: select the *last* matching block instead
   of the first and confirm a test fails.
2. **Add the `U` (unmerged) row to §5.2's table** — almost certainly "exit 0, git refuses it anyway" —
   and add a probe to the harness. My repro is above.
3. **Run S1 and S3 before writing any launcher code**, exactly as §10 sequences them. S3 especially:
   if the cap is under 840s, take the §6.5 fork rather than trimming the deadline.
4. **Caveat §8's "never a hang"** for the rung-3 no-liveness case.
5. **Correct the line-count sentence, or delete it** — and where the spec cites a measured number,
   have it come from a command rather than an estimate.

None of these is a redesign. Items 1 and 2 are specification holes in logic that is otherwise sound;
items 3–5 are honesty and sequencing.

---

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| `intent` | pass | Deterministic spec gate, judges out of session, store as sole authority — all three delivered. §2 now names both amended invariants (duplicate out-of-scope row is cosmetic). |
| `execution` | concern | No code yet (correct for this stage; no test command runnable). Two specification holes in the newest logic: unit-declaration parse rule undefined and self-breaking on this file; §5.2 `U` case unmatched by any table row. |
| `trajectory` | pass | Reproduce-before-accept on the prior finding, including catching its own bad first reproduction. Split→break→unit cascade recorded as consequences, not one clean decision. Rejected alternatives stated. Residual: unverified assertions, not faulty reasoning. |
| `regression` | concern | Store change is additive/nullable with fallback and a backward-compat test against a pre-existing row; round counter keyed on unit root preserves this spec's four stored rounds; nine git states probed, none fail closed. Offset by the `U` gap and rung 3's 840s no-probe path on `git commit`. |
| `context_budget` | pass | Always-on footprint barely moves (a `rules/gates.md` stub edit, two skill edits). Spec length is on-demand. Runtime cost is a python spawn gated behind a substring pre-filter that can only skip work. |
| `traceability` | pass | Header records the cascade and the two corrected claims; §11 records what the unit model cost; §12 mandates a new ADR covering it plus an ADR-0003 update. |
| `success_masking` | concern | Strong falsification mandate with real mutation targets, incl. three for the unit model; escalation cap bounds the revise loop; "no automated test exercises a real judge" disclosed, not implied away. But S3's silent fail-open is unmeasured, and the declaration parser has neither contract nor mutation target. |
| `intent_drift` | pass | Unit model (~170 lines) was forced by the user's split decision and kept minimal — one nullable field, one declared agent input. iTerm2 rung dropped (scope reduction). No new deps; "no `jq` dependency is introduced" stated explicitly. |
| `checkpoint` | pass | Docs-only, per-round commits, verdicts stored each round; trivially revertible. §12 requires the `.gitignore` entry to land *before* any run dir is written. |
| `audit_trail` | pass | New ADR mandated specifically because the unit model amends invariants four rounds were scored against. Every bypass key logged to stderr; ack recorded in the manifest. |

## Concerns

1. `spec_unit` declaration block-selection rule is not script-decidable; root spec holds 3 matching blocks incl. `part_of: <self>`, so its own gate may refuse it
2. §5.2 table has no row for a spec entry with `X`=`U` (unmerged); reproduced on real git, and `git rev-parse ":<path>"` fails on unmerged paths
3. S3 unmeasured: a harness cap below 840s makes the gate fail open silently exactly when the judge is slow
4. Rung 3 has no liveness probe — a killed pane blocks `git commit` for the full 840s, contradicting §8's "never a hang"
5. Header's "Final: 672 and 693 lines" was false in the commit that wrote it (actual 684/696) — the write-up-ahead-of-artifact pattern recurring, cosmetic in consequence
6. No falsification target for unit-declaration parsing, the one piece of new logic with no written contract
7. §2 out-of-scope column duplicates the rubric/scoring row — edit artifact

**Risk:** medium · **Confidence:** high
