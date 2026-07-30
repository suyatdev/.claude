# Observability verdict — `feature/phase-guard-hook` (implementation)

- **ts:** 2026-07-28T19:15:37Z
- **repo:** `phase-guard-hook` (worktree of `~/.claude`)
- **branch:** `feature/phase-guard-hook`
- **head_sha:** `01f011eab9839294293ad261e1ec88b9523287cf`
- **stage:** implementation (gates the PR)
- **base:** `main` (merge-base `8f0f16d`)
- **risk:** medium · **confidence:** high

## Evidence actually gathered

- `bash hooks/phase-guard.test.sh` — **run by me at this HEAD: 88 passed, 0 failed.**
- `shellcheck -x hooks/phase-guard.sh hooks/phase-guard.test.sh` — **run by me: clean, exit 0.**
- **Mutation testing (mine, 5 mutants):** 3 caught, **2 survived** — see concerns. Working tree
  restored and md5-verified identical afterwards.
- **Direct behavioural probes (mine):** deny-message contract verified live; the malformed-file
  fail-open reproduced; cost measured across four feature-file counts and three trials.
- Diff `main...HEAD`: 14 files, +3664/−1. Substantive: `hooks/phase-guard.sh` (346),
  `hooks/phase-guard.test.sh` (681), `settings.json` (+9). Rest is doc/ADR/memory.

---

## What was changed

A safety catch for a rule the repo already had on paper but never enforced.

The workflow says: a feature's card (`docs/features/<name>.md`) carries a `phase:` field, and while
it reads `planning` nobody is allowed to write real code yet. Until now that was an honour system —
a session could ignore it and start coding, and nothing would notice.

This adds `hooks/phase-guard.sh`, which runs before every file edit. Think of it as a door badge
reader. It does **not** try to work out which feature your edit belongs to — that turned out to be
unanswerable. It asks one simpler question: **does this branch have permission?** If some feature is
still sitting at `planning` and no feature card names your current branch, the edit is refused with
a message that names the offending file and tells you the two legitimate ways out. Docs, memory
files and `settings.json` are never blocked — so you can always unlock yourself.

## Does it do what you wanted?

Yes, and the central design idea genuinely holds up.

The previous ADR (0010) had **rejected** this exact hook, because during planning there's no way to
tell which feature is active. This change doesn't solve that — it sidesteps it by asking the
question backwards. I checked the load-bearing assumption independently: `rules/gates.md` really
does forbid creating a branch during planning, so a planning session is *by construction* on a
branch no card claims. The reasoning is sound, not lucky.

I ran the tests myself (88/0), ran shellcheck (clean), and drove the hook by hand to confirm the
refusal message is complete and genuinely actionable. The build discipline is the strongest I've
reviewed here: tests and implementation never in the same commit, problems found mid-build were
escalated rather than quietly patched, and one proposed fix was **measured, found wrong, and
redone** rather than assumed.

## What could go wrong / what I'm unsure about

**1. The guard can switch itself off silently — I reproduced this.** The design has a section
promising that if the guard *can't* evaluate a repo it will say so out loud, because "a working
guard and a dead one are otherwise byte-identical." That promise has a hole. The warning only fires
when **every** card is unreadable. If you have one finished card that's fine and one active
`planning` card with a small frontmatter slip — I used a forgotten closing `---`, an ordinary
hand-edit mistake — the guard skips the broken card, finds nothing at `planning`, and **allows the
write with no output at all.** Control case denies correctly; broken case exits 0 in silence.

This is the most likely real-world version of the failure the section exists to prevent. The
narrowing was justified only to avoid firing in empty repos, and the `nfiles > 0` check already
handles that — so the narrowing goes further than its own reasoning needs.

The tests can't see this, structurally: every malformed-file case deliberately pairs the bad card
with a *good* `planning` card, so something always remains to deny on. Sound for isolating *which
file gets named*, but it means no test ever exercises "the only planning card is the broken one."

**2. A documented safety property the code doesn't have.** The code comment says a `phase:
plannning` typo "must not read as *not planning, therefore allow* and silently switch a CRITICAL
gate off" — but per above, that is exactly what happens. Same for the design's line "a skipped file
in a repo that *has* opted in is the 'cannot evaluate' case, so it is one of the two exits that
print." A comment asserting a guarantee the code doesn't provide will mislead the next maintainer.

**3. Mutation testing found an untested contract clause.** The frontmatter rules say "at most one
`branch:` line," but deleting that check leaves all 88 tests green. The malformed-file tests cover
duplicate `phase:` lines and miss duplicate `branch:` lines. Effect if wrong: a card with two
`branch:` lines silently grants permission from the last one. Low likelihood, fail-open direction.

**4. It collides with the parallel-worktree workflow, and the escape hatch is off-limits.** This
repo explicitly runs several agents at once in worktrees. Once merged, agent A opening *any* new
feature at `planning` blocks agent B's source writes on B's unclaimed branch. The design lists this
as intended. But the sanctioned fix — "edit the offending feature file" — is forbidden to agent B by
`core-conduct`'s "never touch files outside your assigned feature domain," and the other fix
disarms the hook machine-wide. So a blocked parallel agent's only in-policy move is to stop and
escalate. The two rules aren't reconciled anywhere I could find.

**5. It has never actually run.** The registration is committed, but the harness reads the *primary*
checkout's `settings.json` — which is on another branch, and where `hooks/phase-guard.sh` doesn't
exist at all (I verified both). Enforcement starts the moment this merges, in **every repo on the
machine**, having never been live once. All evidence is direct invocation, not real use.

**6. A known-broken rollback path was withdrawn, not fixed.** `chmod -x` on the hook yields exit
126, not "skipped," and 126 might read as *deny* — turning the last-resort escape into a
machine-wide lock. The session chose not to test that, because testing it risks the machine. I think
**withdrawing beat verifying here**: the two remaining paths are sound (I confirmed `settings.json`
is exempt from guarding, so the off switch is always reachable), so the risky experiment buys a path
nobody needs.

**Retracted:** my first cost readings (107ms, 242ms per write) suggested the hook slowed down as
feature files accumulate. Controlled re-measurement across three trials contradicts that — it's a
flat **~35–40ms** whether the repo has 2 cards or 101, because only *planning* cards enter the
expensive step and there's normally one. My initial numbers were machine-load artifacts. The
design's cost analysis is correct; I was wrong.

## What I'd double-check before merging

1. **Fix the silent fail-open (#1)** — the one thing I'd actually hold the merge for. It's a small
   change: warn when *any* card is skipped, not only when *all* are, then add the missing test
   (sole `planning` card malformed, no other planning card, expect a warning).
2. **Reword the two doc claims (#2)** so they describe what the code does. Cheap, and prevents a
   future maintainer trusting a guarantee that isn't there.
3. **Add the duplicate-`branch:` test (#3).** One line next to the duplicate-`phase:` case.
4. **Decide the parallel-agent question (#4)** before this goes live — even just a sentence saying a
   blocked parallel agent escalates rather than edits another agent's card.
5. **Watch the first day after merge (#5).** It arms globally on merge with zero live mileage.
   Rollback path 2 (delete the block from `settings.json`) is verified reachable — keep it handy.

None of these is a design flaw. #1 is a real bug in a safety property the design itself promises.

---

## Dimension table

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | **pass** | Artifacts match the spec table exactly. The branch-scoped reframing genuinely dissolves ADR 0010's objection — I verified its load-bearing premise (planning forbids branch creation) in `rules/gates.md`. |
| `execution` | **concern** | 88/0 and shellcheck clean, both run by me; deny message verified live. But a contract clause is untested (surviving mutant), a silent fail-open is reproducible, and the hook has never run live. |
| `trajectory` | **pass** | Strict TDD, escalate-don't-patch, a wrong fix guess measured and corrected, two false claims withdrawn rather than repaired, an unsafe experiment declined. Reasoning, not luck. |
| `regression` | **concern** | Unreconciled collision between the branch-scoped deny and the parallel-worktree invariant: the sanctioned fix is forbidden to the blocked agent. Merge-time self-lock checked and clear (main's only card is at `review`). |
| `context_budget` | **pass** | `rules/gates.md` 989 → 1053 words (+6.5%), a clause not a new bullet; no new always-on file. Hook and 1334-line spec are not always-on. |
| `traceability` | **pass** | Spec, ADR 0011 amending 0010, and per-decision rationale including withdrawn claims. Exceptional. Internal inconsistency logged under `success_masking`, not here — a careful reader can reconstruct actual behaviour from the spec. |
| `success_masking` | **concern** | 88 green tests coexist with a reproducible silent fail-open. The malformed-file fixture design structurally cannot see it. 2 of 5 mutants survived. |
| `intent_drift` | **pass** | Scope confined to the spec's artifact table. No new dependencies (bash/awk/git/python3 all pre-existing), no drive-by edits; the `gates.md` clause is in-scope documentation of the new enforcement. |
| `checkpoint` | **pass** | Granular commits, tests and implementation never mixed. Rollback paths 1–2 verified reachable (`settings.json` exempt, confirmed by mutation M5). Revert's limitation on the live working copy is documented. |
| `audit_trail` | **pass** | ADR 0011 amends 0010 and records the deliberate override of the defer-until-observed rule; prior judge rounds and memory retained. |

## Concerns

1. Reproduced: a lone malformed `planning` card alongside any well-formed card silently disables the gate — no warning, exit 0. The `noparse` warning requires *all* cards unreadable; its stated justification (don't fire on empty dirs) is already met by the `nfiles > 0` check, so the narrowing overshoots.
2. The malformed-file test fixture pairs every bad card with a good `planning` card, so no test can ever exercise "sole planning card malformed" — the blind spot that produced concern 1.
3. `hooks/phase-guard.sh:142-143` and spec line 276-277 both assert a protection ("must not silently switch a CRITICAL gate off") that concern 1 disproves.
4. Mutation `nphase != 1 || nbranch > 1` → `nphase != 1` survives all 88 tests: the "at most one `branch:` line" clause is unverified. A duplicate `branch:` line would grant a claim from the last one (fail-open).
5. Branch-scoped denial collides with the parallel-worktree invariant: agent B blocked by agent A's planning card cannot use rollback path 1 without violating "never touch files outside your assigned feature domain"; path 2 disarms machine-wide. Unreconciled.
6. Committed ≠ armed (verified: absent from live `settings.json`; `~/.claude/hooks/phase-guard.sh` does not exist). Arms globally at merge with no prior live exercise.
7. Rollback path 3 withdrawn on an unverified premise (exit 126 may read as deny). Judged the correct call — the remaining paths are sound — but the harness's treatment of 126 stays unknown for every hook in this repo.
