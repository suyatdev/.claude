# Observability Judge — `docs/reconcile-judge-verdict-stores` (RUN 3)

- **Stage:** implementation (gating)
- **Repo:** `.claude` · **Branch:** `docs/reconcile-judge-verdict-stores` · **HEAD:** `12ee6407746149f72f52dd6682eb0269d23ed404`
- **Base:** `origin/main` @ `525d95b` · 6 commits · 9 files, +2817/−21
- **Tests:** none applicable — docs/data only; no source, hook, agent or skill touched (verified by `git diff --name-only`).
  In place of tests, **every quantitative claim on the branch was independently re-measured from git objects.**

---

## Lead finding — the pattern produced a fourth instance, live at HEAD

`565071d`'s message says it fixed the two narrated claims "**along with the habit that produced
them**". The habit is not fixed. Item 2 of `CODING_MEMORY.md` at HEAD says the union rule lives in
the index rather than in `coding-memory/compliance-judge/README.md` — "**(which does not exist)**".

It exists. It is tracked. It has existed since `72b868f`, long before this branch:

```
git log --diff-filter=A -- coding-memory/compliance-judge/README.md  → 72b868f
git cat-file -e origin/main:coding-memory/compliance-judge/README.md → exists
```

So does `coding-memory/observability-judge/README.md` (since `2da53fc`). Both are tracked; neither
is gitignored. The parenthetical was introduced at `d4aecf0`, survived the commit that claimed to
fix the habit, and — this matters — **RUN 2 repeated it** ("the store has no README", round-2
writeup line 142) instead of catching it. One `git ls-files` would have settled it.

The blast radius is small but real: the recorded remedy now points at the wrong artifact. A future
agent reads "create the README" when the actual task is "add the union/no-loss rule to the README
that is already there".

---

## What was changed — plain English

Two commits since RUN 2, on a branch that repairs an audit ledger:

- **`565071d`** corrects two sentences that had been *narrated* rather than *measured*: how many
  rescued verdict lines share a commit ID, and how many absolute paths ride in. It also re-anchors a
  count to a commit ID instead of a date, and writes down two things the earlier fix did not resolve.
- **`12ee640`** closes one of those two: the user ruled that when a judging round catches only a
  typo or a stale pointer, the round is scored `rework`.

Nothing that runs was touched. Think of it as correcting the footnotes and the counting rules in a
logbook — not changing the machine the logbook describes.

## Does it do what you wanted?

Yes, on the narrow task, and the arithmetic is **exact**. Everything I could check, I checked:

| Claim | Measured | |
|---|---|---|
| 26 verdict lines across 24 distinct `head_sha` | 26 added, 0 removed, 24 distinct | ✅ |
| 23 SHAs × 1 round, one SHA `6d8c675` × 3 | `Counter({1: 23, 3: 1})`, multi = `6d8c6755…` | ✅ |
| Union-merged 13 → 39 lines | 13 → 39, all 13 base lines present, `ts` ascending, 0 malformed | ✅ |
| 18 absolute paths in the rescued compliance records | 18 lines, 18 occurrences | ✅ |
| `origin/main` already carries 49, incl. 5 in this store | 49 lines (79 occurrences), 5 in store | ✅ (line-count metric, consistent with the 18) |
| Item 6: at `8143f29` — 70 lines, 22 null, 0 malformed | exactly that; enumeration sums to 22; 19 impl / 3 arch | ✅ |
| `565071d` msg: 34 clean / 14 rework / 23 null at `d4aecf0` | exactly that | ✅ |
| `12ee640` msg: 10 PR #33 entries, 10 rework, 0 clean | exactly that (`fix/judge-guard-fail-closed-classifier`) | ✅ |
| `judge-guard.sh` never reads `outcome` | no match; it parses only `stage`/`repo`/`branch`/`head_sha` | ✅ |

The disclosed retroactive claim ("Store-wide context checked, not assumed") turned out **numerically
correct**. RUN 2's central complaint — invented explanations — did not recur *in the numbers*. It
recurred in prose, once, as above.

## What could go wrong / what I'm unsure about

**1. The policy is written where the next agent won't look.** Two user rulings now govern the
`outcome` column. They live **only** in `CODING_MEMORY.md`. The three durable, discoverable places
all still state the older, looser rule:

- `coding-memory/observability-judge/README.md` → "Backfill it when a PR's real result is known."
- `skills/running-the-observability-judge/SKILL.md:45` → same wording.
- ADR 0001 → "backfilled: clean/rework/bug", no policy.

The judge agent reads the SKILL, not the memory index. This is the **third consecutive round** this
has been raised (RUN 1 §4, RUN 2 audit_trail) and the third time the fix went into the index instead.
Combined with the "README does not exist" error, the branch actively steers the next reader away
from the one file that would fix it.

**2. `clean` is technically reachable, but is now two different words in one column.** At HEAD:
72 lines — **34 clean / 14 rework / 24 null**. All 34 `clean` are pre-narrowing. **Zero `clean` has
been assigned under the new policy**; the only clean written on this branch (`0f54622`) was flipped
to `rework` at `d4aecf0`. So `clean` is not being squeezed out arithmetically — a round that finds
nothing and lands its verdict alone still earns it — but the column now mixes "the PR merged" (34
old rows) with "the judge had nothing to say" (all future rows), **with no marker in the store
itself**. Item 2b admits the mixing; it does not propose a schema field, and no in-store note warns
a reader. Anyone aggregating this column later gets a number that means nothing.

**3. The column's documented consumer was not updated.** The README defines calibration as
*`risk` vs `outcome`* — "`risk: low` clustering with `outcome: bug` → thresholds too loose". That is
an **outcome** signal. The 07-22/08-01 policy redefines `outcome` as *did this round prompt a
change* — a **process** signal. Feeding a process variable into a calibration designed for an
outcome variable will mis-tune the gate that blocks `gh pr create`. This is the deepest issue on the
branch and it is not recorded anywhere.

**4. The retroactive-verification claim is still uncorrected in the record.** I judge the
*decision not to force-push* as **sound, not self-serving** — the branch is fully pushed
(`origin/… = 12ee640`), so history is shared and rewriting it to repair a phrase would be worse. But
"don't rewrite" does not imply "don't annotate". A one-line note in item 2b would have cost nothing.
As it stands the committed record contains an unqualified false process claim, and the only
correction lives in a gitignored, machine-local memory file — invisible to every future reader.
That half of the reasoning **is** convenient, and I'm calling it.

**5. Context cost.** `CODING_MEMORY.md` went 1600 → 1658 lines; items 2 + 2b went from 5 lines to
57 in a file restored at the start of every session. Some of that is durable state. Some is
methodological reflection ("*A count that its own sentence changes is a count that will be wrong by
the next commit*") that reads like a lesson, not an index entry — and the durable half belongs in
the README anyway, which is loaded on demand.

**6. Coherence — good, better than most.** A reader arriving at the merge commit can reconstruct
this: commit messages carry rationale, corrections are layered in place with the old wording quoted,
both prior judge writeups are committed, and "LEFT OPEN DELIBERATELY" is explicit. What's missing is
an **ADR**: two user-owned policy rulings that change how a gating metric is computed, recorded
nowhere in `docs/decisions/` despite ADR 0012 covering comparable judge infrastructure.

**7. Self-judgment cost, stated plainly.** My verdict enters the store this branch edits; under the
rule just ruled, findings I raise that get fixed make this round `rework`. I raised seven. I have no
way to prove that disclosure removed the bias, only to make the evidence checkable — every figure
above is a command anyone can rerun. Note also the standing recursion: landing this verdict changes
HEAD, which invalidates it under `judge-guard`'s strict freshness rule. That is item 2b's known
problem, not a new one.

## What I'd double-check before merging

1. **Delete "(which does not exist)"** from item 2 — it's false. Rephrase the debt as "the union
   rule is absent from the existing README".
2. **Put the calibration policy in `coding-memory/observability-judge/README.md`** (and ideally one
   line in the SKILL). One paragraph. It ends a three-round finding.
3. **Decide whether the `outcome` column still serves the calibration the README describes** —
   if not, say so in the README, because the mismatch will quietly mis-tune a PR gate.
4. **Consider a one-line note** that `565071d`'s "checked, not assumed" was verified after the fact.
   Do **not** force-push; annotate forward.
5. Optional: an ADR for the two rulings, and a schema marker distinguishing pre/post-narrowing
   `clean`.

---

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | Both RUN 2 findings fixed exactly; the open tie-break closed with recorded user authority. Scope matched the stated task. |
| execution | concern | Every measurable figure is exact (9/9 re-verified). But the deliverable states a fact about the repo that is false and trivially checkable — `compliance-judge/README.md` exists. No tests apply; verification was by re-measurement. |
| trajectory | concern | Reasoning quality is genuinely high (anchoring counts to SHAs, refusing to pin a self-falsifying total, asking rather than assuming on a user-owned policy). But `565071d` claims to have fixed "the habit" and the habit produced a new instance in the same file — and RUN 2 propagated it. Instances fixed; pattern not yet demonstrated fixed. |
| regression | pass | No source/hook/skill/agent touched. `judge-guard.sh` never reads `outcome` (verified). Both stores: 0 malformed, `ts` ascending, no base line lost, 13→39 and 70→72. Working tree clean. |
| context_budget | concern | `CODING_MEMORY.md` 1600→1658; items 2/2b 5→57 lines in a restore-time index, including methodological commentary. The durable half belongs in the on-demand README. |
| traceability | concern | The operative rule is discoverable only from a 1658-line index; README, SKILL and ADR 0001 all still state the older rule, and the record asserts the README doesn't exist. Third round this has been raised. |
| success_masking | concern | Confident verification language ("checked, not assumed", "verified before claiming it") is the only green light here, and one instance was retroactive. Separately: 34 pre-narrowing `clean` sitting unmarked beside post-narrowing `rework` makes the ledger read more calibrated than it is — a green-looking metric over two incompatible definitions. |
| intent_drift | pass | Docs/memory only; no deps, no source, no drive-by edits. The policy extension carries explicit user authorization, which is the exact defect this branch exists to correct. |
| checkpoint | pass | Six clean, individually revertible commits; store edits are the schema's intended backfill, not destructive; branch pushed and matching remote; clean revert point at every step. |
| audit_trail | concern | Attribution is now exemplary (`DECIDED 2026-08-01 (user)` + rationale on both rulings). Still no ADR for two gating-metric policy decisions, and the retroactive-verification correction exists only in a gitignored file. |

**Risk: medium** — nothing executes, nothing broke, and every number is exact; the risk is that an
audit ledger whose whole purpose is trustworthiness now carries two undocumented meanings in one
column, with its policy recorded away from its readers.
**Confidence: high** — small, fully static surface; every claim mechanically re-measured from git
objects rather than accepted from a commit message.

## Concerns

- `CODING_MEMORY` item 2 asserts `coding-memory/compliance-judge/README.md` "does not exist" — it exists and is tracked since `72b868f`; 4th narrated-not-measured instance, live at HEAD, propagated by RUN 2
- Calibration policy (07-22 + both 08-01 rulings) lives only in `CODING_MEMORY.md`; store README, `running-the-observability-judge/SKILL.md:45` and ADR 0001 still state the looser "backfill when the result is known" rule — third round raised
- All 34 `clean` values are pre-narrowing; zero assigned under the new policy — one column now carries two definitions with no in-store marker
- `outcome` now encodes a process signal ("did this round prompt a change") while the README documents `risk`-vs-`outcome` calibration over a result signal — the consumer was not updated
- `565071d`'s "Store-wide context checked, not assumed" was written before verification (figures later proved exact); left uncorrected in the pushed record, correction only in a gitignored memory file
- `CODING_MEMORY` items 2/2b grew 5 → 57 lines in a 1658-line restore-time index, incl. methodological commentary
- Two user-owned policy rulings governing a PR-gating metric still have no ADR after three rounds flagging it
