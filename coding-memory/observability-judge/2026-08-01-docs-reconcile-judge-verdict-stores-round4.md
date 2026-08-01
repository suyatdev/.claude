# Observability Judge — `docs/reconcile-judge-verdict-stores` (RUN 4)

- **Stage:** implementation (gating)
- **Repo:** `.claude` · **Branch:** `docs/reconcile-judge-verdict-stores` · **HEAD:** `0ff95feaebf153222297e7890195c087e3f8742e`
- **Base:** `origin/main` @ `525d95b` · 7 commits · 10 files, +3026/−21
- **Tests:** none applicable — docs/data only. Verified, not assumed: `git diff --name-only 525d95b..HEAD`
  returns 10 paths, all under `CODING_MEMORY.md` or `coding-memory/`. No source, hook, agent or skill.
  In place of tests, **every quantitative claim in `0ff95fe` was re-derived from git objects.**
- **Filename note:** written as `-round4` rather than the bare `<date>-<branch_slug>.md` the procedure
  specifies, because that path is already occupied by RUN 1's committed writeup. Overwriting a
  committed audit record to satisfy a naming rule would be the exact failure this branch exists to
  repair. Follows the `-round2`/`-round3` convention already established here.

---

## Lead finding — the arithmetic is flawless; the habit produced a fifth instance anyway

**All thirteen quantitative claims in `0ff95fe` are exact.** I re-derived every one independently and
none moved. The commit's own headline claim — that its figures were measured for this commit rather
than carried from the RUN 3 report — cannot be verified as *process*, but its *outputs* survive
re-measurement without exception. That is the strongest evidence the branch has produced.

And in the sentence that corrects instance four, there is a fifth.

`CODING_MEMORY:1563` (and the commit message) now says **"both judge READMEs have been tracked since
`72b868f`"**. `72b868f` (2026-07-18) added only the compliance README. The observability README was
added at `2da53fc` (2026-07-16), two days earlier:

```
git log --diff-filter=A --format='%h %ad' --date=short -- coding-memory/observability-judge/README.md
  → 2da53fc 2026-07-16
git log --diff-filter=A --format='%h %ad' --date=short -- coding-memory/compliance-judge/README.md
  → 72b868f 2026-07-18
git merge-base --is-ancestor 2da53fc 72b868f   # true
```

This is **milder than instances 1–4 and I will not inflate it**: because `2da53fc` is an ancestor of
`72b868f`, the sentence "both have been tracked since `72b868f`" is *literally true* — from that
commit onward, both are tracked. It is not false. It is imprecise, and it loses a fact the branch
had already measured correctly: RUN 3's report carried both SHAs separately; the correcting commit
collapsed them into one.

But the *shape* is identical to instance 1 ("two SHAs carry a second round"): a measured fact about
one object, extended by narration to a second object that was not measured. Item 2c line 95 gets it
right for the compliance README alone. The word that broke it is "both".

**Why this matters more than its size:** item 2c was written to close this habit, and the habit
appeared inside the same commit, roughly forty lines from the rule forbidding it. That is direct
evidence for the question you asked me to answer.

---

## Answers to the five questions put to this round

### 1. Re-derive every figure. — **All exact. Every command below is rerunnable.**

| Claim | Where | Measured | |
|---|---|---|---|
| 26 verdict lines across 24 distinct `head_sha` | item 2 | 39−13 = 26 added; 24 distinct | ✅ |
| 23 SHAs × 1 round, one SHA `6d8c675` × 3 | item 2 | `{1: 36, 3: 1}` store-wide; multi = `6d8c675` | ✅ |
| Union-merged 13 → 39, no-loss, 0 malformed | item 2 | 13→39; `set(base) ⊆ set(head)` True; `ts` ascending; 0 malformed | ✅ |
| 18 absolute paths on the rescued compliance records | item 2 | 18 added lines in `compliance-judge/verdicts.jsonl` | ✅ |
| `origin/main` already carries 49, incl. 5 in this store | item 2 | 49 lines total; 5 in `coding-memory/compliance-judge` | ✅ |
| 23 net-new absolute paths **at `d4aecf0`** | item 2c | 23 (and 25 at HEAD — the SHA anchor is doing its job) | ✅ |
| "no metric yields 19" | item 2c | 18 / 23 / 25 / 49 — none is 19 | ✅ |
| Nulls 32 → 22 at `8143f29` | item 2b | base 32 → `1ea3599` 22 | ✅ |
| 34 clean / 14 rework / 23 null at `d4aecf0` | 2c inst. 3 | exactly that | ✅ |
| PR #33: 10 entries, all `rework`, zero `clean` | item 2b | 10 entries on `fix/judge-guard-fail-closed-classifier`, `{rework: 10}` | ✅ |
| All 34 `clean` are pre-narrowing; zero assigned since | item 2b | HEAD 34 clean = the base 34 exactly; the one `clean` written on-branch (`0f54622` at `1ea3599`) was flipped to `rework` at `d4aecf0` | ✅ |
| 0 hits for "narrow"/"verdict-landing" in SKILL + store README | item 2b | 0 / 0 in both | ✅ |
| `coding-memory/observability-judge/README.md:32-35` | item 2b | `## Calibration` at line 32; file is 35 lines | ✅ |
| `compliance-judge/README.md` exists since `72b868f` | item 2 | ✅ (but see lead finding re "both") | ⚠️ |

The one intermediate measurement that "returned 0 spuriously and was caught by re-running" is
disclosed in the commit message and is unverifiable after the fact. Disclosing it was correct;
it is worth noting that the disclosure is itself an unverifiable process claim of the same class
as instance 3.

### 2. Is deferring the policy propagation legitimate, or the third consecutive misfile? — **Both. Split the question.**

**The SKILL edit: deferring it is legitimate, and this is a real improvement over the previous two
rounds.** "Own branch, own gates — editing the judge's own instructions changes how every future
round scores itself" is a correct senior call, not paperwork. A named owner-shaped assignment with a
stated reason is materially better than a vague to-do, and refusing to smuggle a behaviour change
into a docs branch mid-audit is exactly the discipline the branch is arguing for.

**The missing ADR: this is a genuine misfile, and the "own branch, own gates" reasoning does not
cover it.** Writing an ADR changes no judge behaviour, costs nothing on a docs branch, and is the
durable discoverable artifact the gate rules already require for direction-pivoting decisions.
Instead:

```
grep -rli "outcome" docs/decisions/   → 0001, 0003, 0009, 0012  (none records the policy)
docs/decisions/0001-observability-judge.md:23
  → "Verdicts accumulate an `outcome` field (backfilled: clean/rework/bug)"
```

So `docs/decisions/` is alive and actively maintained (12 ADRs), and **ADR 0001 now actively
contradicts the recorded policy.** Four rounds have flagged this. The branch merges with a live
decision record stating the superseded rule and no record stating the current one.

**Blunt version:** the branch's headline deliverable is a policy that is not in force anywhere an
agent reads. Two user-owned rulings governing a PR-gating metric currently exist only in a memory
index, and:

```
grep -rl "CODING_MEMORY" skills/running-the-observability-judge/ agents/   → no hits
```

The judge reads neither. At merge, the narrowed policy is an intention, not a behaviour.

### 3. Does item 2c change the habit, or document it more thoroughly? — **Documents it. A catalogue is not a control.**

Item 2c produces three good, generalisable rules. Nothing enforces any of them — no hook, no
checklist entry, no template field, no line in the judge SKILL or agent. They live in the same
restore-time index that this branch has now demonstrated four separate times is *not* where
behaviour comes from. Item 2b makes precisely this argument about the calibration policy and does
not apply it to item 2c.

**The empirical answer is the lead finding: a fifth instance appeared in the commit that wrote the
catalogue.** Nothing structural prevents a sixth.

The cheapest control that would actually bite is not another rule: it is a pre-commit or
judge-checklist step that greps a staged commit message and memory diff for uncited counts and
existence claims, or simply a convention that every count in `CODING_MEMORY` carries the command
that produced it. Item 2c's own numbers mostly do carry SHA anchors — which is why they held up.

### 4. Is the branch coherent for a cold reader at the merge commit? — **Reconstructable, but expensive.**

A reader with none of this conversation can rebuild the story: seven commit messages are unusually
explicit, three round writeups are committed alongside the data they judge, and item 2c narrates
the arc. The SHA anchoring means the numbers can be re-checked years later. That is genuinely
better than most audit repairs.

The cost is that the reconstruction now requires a **95-line** memory item plus three writeups.
Items 2..2c went from **5 lines to 95** while `CODING_MEMORY.md` went **1600 → 1696 lines**
(+1,360 words) — in a file read at every session restore. RUN 3 flagged this at 57 lines; it grew
to 95 after being flagged. A large share of the growth is methodological commentary about the
branch's own process, which belongs in a writeup or an ADR, not in always-on context.

There is also a small internal inconsistency for that cold reader: item 2b line 54 describes the
34 `clean` values as "set under the wide reading" of the 07-22 policy, while line 74 glosses the
same 34 as pre-narrowing meaning "the PR merged". Two different semantics for one set of rows,
twenty lines apart. The **verifiable** core — that all 34 predate the narrowing and none has been
assigned since — is true and I confirmed it. The gloss about *which policy governed each row* is
not checkable from the store at all, because nothing records when an outcome was assigned. It is a
narrated explanation sitting inside the item that catalogues narrated explanations.

### 5. Self-judgment. — **Stated plainly.**

Under the rule `12ee640` put in force, findings I raise that get fixed make this round `rework`.
I am scored on a metric I am also incentivised to keep quiet. I found five things. Every figure in
this writeup is a command the reader can rerun without trusting me.

---

## Dimensions

| Dimension | Verdict | Why |
|---|---|---|
| `intent` | **pass** | Fixed the false claim in place, annotated forward, recorded the deferred debts with an owner shape. All three stated goals landed, precisely. |
| `execution` | **concern** | Thirteen of thirteen figures exact; store integrity verified (no-loss, ordered, 0 malformed). But a fresh precision defect shipped inside the correction ("both READMEs since `72b868f`"), and the store this branch just proved can silently fork still has no automated parse/no-loss check. |
| `trajectory` | **concern** | Reasoning is genuinely strong — the not-force-pushing call is correct and well-argued, the annotate-forward instrument is right, the spurious-0 disclosure is exactly right. But the process still produced a new imprecision in the correcting commit, and the catalogue rests on no control. |
| `regression` | **pass** | Nothing executable touched (verified by `--name-only`). All 13 base compliance lines preserved, `ts` ascending, 0 malformed, store shape unchanged, `judge-guard.sh` reads only `stage`/`repo`/`branch`/`head_sha`. |
| `context_budget` | **concern** | Items 2..2c: 5 → 95 lines; `CODING_MEMORY.md` 1600 → 1696 in a restore-time index. Flagged at 57 lines in RUN 3 and grew after. Much of it is process commentary that belongs in a writeup or ADR. |
| `traceability` | **concern** | Claims are SHA-anchored and rerunnable; commit messages are exemplary. But the narrowed policy is unreadable by the agent it governs — 0 hits in the SKILL and store README, no `CODING_MEMORY` reference in `skills/` or `agents/`. |
| `success_masking` | **concern** | The branch scores itself with the judge whose scoring policy it rewrites, and that policy is not in force — so future rounds keep scoring under the old rule while the index claims the new one. "Four instances" reads like closure on a habit that produced a fifth. "Every figure re-derived for this commit" is a self-attested process claim of the same class as instance 3. |
| `intent_drift` | **pass** | Docs/data only, entirely within the audit-repair remit. No deps, no drive-by source edits. The one plausible scope creep (the SKILL edit) was explicitly refused and assigned elsewhere. |
| `checkpoint` | **pass** | Seven small, individually revertible commits; nothing force-pushed; clean working tree; reverting the branch restores the base store exactly (verified by set containment). |
| `audit_trail` | **concern** | Attributable throughout, rulings dated and credited to the user. But two user-owned rulings governing a PR-gating metric still have no ADR after four rounds, and ADR 0001:23 now actively contradicts the recorded policy. Unlike the SKILL edit, an ADR changes no behaviour — the deferral rationale does not cover it. |

**Risk: medium. Confidence: high.**

Not `low`: I will not certify a habit as fixed when a fresh instance of it appears in the commit
that catalogues it, and three findings raised in every previous round persist — one of them now
contradicted by a live ADR. Not `high`: nothing here can break anything that runs; blast radius is
one memory file and an audit ledger, and the data integrity is verified sound.

## Concerns

1. `CODING_MEMORY:1563` and `0ff95fe`'s message say "both judge READMEs have been tracked since
   `72b868f`" — the observability README was added at `2da53fc`, two days earlier. Literally true,
   materially imprecise; a fifth instance of the branch's failure mode, inside the correcting commit.
2. No ADR for the 07-22 policy or either 08-01 ruling, after four rounds flagging it — while
   `docs/decisions/0001-observability-judge.md:23` still states the superseded rule and now
   contradicts the index.
3. The narrowed policy is inert: 0 hits for "narrow"/"verdict-landing" in
   `skills/running-the-observability-judge/SKILL.md` or `coding-memory/observability-judge/README.md`,
   and neither the skill nor `agents/` references `CODING_MEMORY`. Documentation, not behaviour.
4. Item 2c is a catalogue, not a control — no hook, checklist, or template enforces its three rules;
   they live in the same index the branch proved is not where behaviour comes from.
5. Items 2..2c grew 5 → 95 lines (`CODING_MEMORY.md` 1600 → 1696) in an always-read restore index,
   after RUN 3 flagged it at 57.
6. Internal inconsistency on the 34 `clean` values: "set under the wide reading" (line 54) vs
   pre-narrowing meaning "the PR merged" (line 74); neither gloss is checkable, since the store
   records no assignment time or policy version.
7. All 34 `clean` remain unmarked beside post-narrowing rows — one column, two meanings, no marker;
   anyone aggregating the ratio mixes two policies.
8. `outcome` now encodes a process signal while both READMEs document risk-vs-outcome calibration
   over a result signal — the consumer of the metric that gates `gh pr create` was never updated.
