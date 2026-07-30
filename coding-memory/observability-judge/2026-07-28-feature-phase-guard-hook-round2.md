# Observability verdict — `feature/phase-guard-hook` (implementation, RUN 2)

- **ts:** 2026-07-28T19:33:14Z
- **repo:** `phase-guard-hook` (worktree of `~/.claude`)
- **branch:** `feature/phase-guard-hook`
- **head_sha:** `f963b766c1dbf4a6120316f0e02fca18e15563df`
- **stage:** implementation (gates the PR)
- **base:** `main` (merge-base `8f0f16d`)
- **prior verdict:** RUN 1 at `01f011e` — `2026-07-28-feature-phase-guard-hook.md`
- **risk:** medium · **confidence:** high

> **Filename note.** RUN 1 occupies the canonical `<date>-<branch_slug>.md` path and was untracked
> (unrecoverable from git if overwritten). This round therefore takes the `-round2` suffix already
> used by every prior multi-round series in this directory (`…-round2/3/4`). The branch field in
> `verdicts.jsonl` stays the raw, unsanitized `feature/phase-guard-hook`.

## Evidence actually gathered

- `bash hooks/phase-guard.test.sh` — **run by me at this HEAD: 95 passed, 0 failed.**
- `shellcheck -x hooks/phase-guard.sh hooks/phase-guard.test.sh` — **run by me: clean, exit 0.**
- **Mutation testing (mine, 3 mutants targeting the delta): all 3 caught.** Working tree restored
  and verified clean via `git diff --stat` afterwards.
  - delete `|| nbranch > 1` → fails **A3.5b** (2 assertions). RUN 1 finding 3 genuinely closed.
  - narrow back to `nfiles > 0 && nparsed == 0` → fails **A2.15** alone.
  - widen to `nfiles > 0` → fails **A2.17 (×2), A1.7 (×2), B2**.
  - Every claim the decisions summary made about mutation coverage reproduced exactly.
- **Direct behavioural probes (mine, 4):** the RUN 1 fail-open re-run against the fix (now warns);
  a supersession-path probe (**new residual found**); a non-card-`.md` noise probe (**new
  regression found**); live-arming state re-verified.
- Delta `01f011e..HEAD`: 4 files, +131/−12. Substantive: `hooks/phase-guard.sh` (+12/−8),
  `hooks/phase-guard.test.sh` (+48), spec (+42/−2), memory (+31/−2).

---

## What was changed

Three things, all in response to RUN 1, plus one thing deliberately *not* changed.

RUN 1 found that this new safety guard could quietly switch itself off. The guard's whole promise is
that if it ever *can't* do its job it will say so out loud — because a guard that's working and a
guard that's dead look identical from the outside. The bug: it only spoke up if **every** feature
card was unreadable. One good card plus one typo'd card meant total silence.

The fix is one comparison: warn if **any** card was skipped, not only if **all** were. A failing test
was written and committed on its own first, verified red against the old code, and only then fixed —
textbook discipline. A second test was added pinning the opposite direction so the fix can't later be
mutated into warning about everything. A misleading code comment was reworded. A third gap (a
never-tested rule about duplicate `branch:` lines) was closed with a test that genuinely bites.

Deliberately *not* fixed: RUN 1's finding that this guard collides with the repo's parallel-agent
workflow. That was written down as an open governance question for the user instead of being decided
unilaterally.

## Does it do what you wanted?

Mostly yes, and the discipline behind it is excellent — but the fix is narrower than the problem.

The headline bug is genuinely fixed. I re-ran RUN 1's exact scenario against the new code and it now
warns correctly. All three mutation claims in the summary reproduced. The `nbranch` gap is properly
closed. Refusing to decide the parallel-agent question alone is, in my judgement, the **right** call:
the repo's own conduct rules say architecture trade-offs stay human-owned, and this is a conflict
between two rules, so it belongs to you, not to the implementer.

But the fix patched the *instance*, not the *class* — and I found the same bug still alive one step
further down. See below.

## What could go wrong / what I'm unsure about

**1. The same silent fail-open still exists, one step later. I reproduced it.** The new warning lives
*inside* the branch that runs when no planning card is found. But there is a second way to end up
with no planning cards: the guard also drops cards that have been "superseded" (a stale `planning`
card on `main` whose real copy on a feature branch has moved on). That drop happens **after** the
warning check. So:

- one stale-but-superseded `planning` card, plus one unreadable card → **exit 0, complete silence.**
- the same unreadable card alone → warns correctly.

Both measured, side by side, just now. This is RUN 1's bug in a new spot. It's narrower — it needs a
specific two-card shape — but the shape isn't exotic: a stale card on `main` is exactly what the
supersession logic was built for, and a typo in the card you're editing is the everyday mistake.

Consequence of the same tests-can't-see-it kind: no fixture combines a skipped card with the
supersession path, so the suite is structurally blind here too, exactly as it was before.

**2. The reworded comment still over-claims.** It now says a skip "cannot cost it *silently*". Per
finding 1, it still can. The wording is more honest than before, but it's still stated as an
absolute the code doesn't deliver.

**3. The fix introduced new false-positive noise, and the message it prints is untrue in that case.**
Because *any* unreadable file now warns, an ordinary `README.md` or template sitting in
`docs/features/` triggers the warning **every session, forever**, in every opted-in repo. I verified
this. The line claims "the gate cannot be fully evaluated" — for a README that is simply false; the
gate evaluated fine. The hook's own comment says the once-per-session limit exists so the warning
isn't "noise the reader learns to skip past"; this reintroduces that risk from the other end. Under
the old code a README was silent. This is a real behavioural regression from the fix.

**4. The spec now contradicts the shipped code.** The delta documented the fix in the narrative
section near the end, but the **normative contract section was not updated**. It still states the
old rule verbatim: the warning "requires **at least one file present and all present files
skipped**." That is the bug, described as the specification. A maintainer reading the authoritative
section would "correct" the code straight back to RUN 1's finding. Two sections of one document now
disagree — the failure mode the repo's own one-canonical-file rule exists to prevent.

**5. Carried from RUN 1, unchanged and still true:** it has never actually run. I re-verified —
`phase-guard.sh` does not exist in the live checkout, `phase-guard` appears **0** times in the live
`settings.json`, and the live repo has no `docs/features/` at all. It arms machine-wide at merge with
zero live mileage. Also unchanged: the branch-granularity hole, the withdrawn rollback path 3, and
the second-order cost of `main` keeping cards at `planning`.

**Merge-time self-lock: checked and clear.** The one card that goes live parses cleanly and reads
`phase: review` with its branch recorded, so merging will not lock the machine. I checked this
specifically because the spec was edited twice since RUN 1.

## What I'd double-check before merging

1. **Close finding 1 properly** — move the skip check so it also covers the supersession exit (and
   ideally the git fail-opens), rather than sitting in one branch. Then add the fixture that pairs a
   skipped card with a superseded planning card. This is the same one-line class of fix as last time.
2. **Fix the spec contradiction (finding 4)** before anything else — it's the cheapest and it's the
   one that will actively re-create the bug later.
3. **Decide what a non-card file in `docs/features/` means (finding 3).** Either exclude obvious
   non-cards, or soften the message so it isn't false. As-is, the first README anyone adds turns a
   safety alarm into background hum.
4. **Answer the parallel-agent question (RUN 1 #4).** Recording it was the correct call, but it's
   recorded inside a ~1,400-line spec — make sure it actually reaches you as a decision, because it
   changes behaviour for every concurrent agent the moment this merges.
5. **Watch the first day after merge.** Rollback path 2 (delete the `settings.json` block) is
   verified reachable — keep it handy.

Nothing here is a design flaw, and nothing causes a false *block*. Findings 1 and 4 are the ones I'd
hold for; 3 is cheap and worth doing at the same time.

---

## Dimension table

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | **pass** | The delta does what RUN 1 asked on findings 1–3, and records finding 4 rather than deciding it. All three mutation claims reproduced exactly; no claim in the summary was found overstated. |
| `execution` | **concern** | 95/0 and shellcheck clean, both run by me; 3/3 mutants caught. But the same fail-open class is still reproducible via the supersession path, the fix added a false-positive surface, and the hook has still never run live. |
| `trajectory` | **pass** | Reproduced independently before changing anything; failing test committed alone and verified red; fix mutation-checked in both directions; an over-claiming comment reworded rather than defended; a governance conflict escalated rather than unilaterally decided. Reasoning, not luck — the strongest dimension here. |
| `regression` | **concern** | New: any non-card `.md` in `docs/features/` now emits a per-session warning whose text is false in that case — silent before this change. Carried: the unreconciled parallel-worktree collision. No false denies; merge-time self-lock re-verified clear. |
| `context_budget` | **pass** | The delta adds no always-on content — hook, tests and spec are all load-on-demand; `rules/gates.md` untouched since RUN 1. |
| `traceability` | **concern** | **Downgraded from RUN 1's pass.** The spec's normative "two exits that must not be silent" section still specifies the pre-fix rule ("all present files skipped") while the code and the narrative section say otherwise. The authoritative description of the shipped behaviour is now wrong. |
| `success_masking` | **concern** | 95 green tests coexist with a reproducible residual silent skip. The fixture design still cannot reach it: no scenario pairs a skipped card with the supersession path, the same structural blind spot as RUN 1, one step over. |
| `intent_drift` | **pass** | Delta tightly scoped to the four judge findings. No new dependencies, no drive-by edits, no scope creep. |
| `checkpoint` | **pass** | Test-before-fix separation honoured across `72b5622` → `f22bb10`; granular, revertible commits. Minor hygiene: RUN 1's own verdict artifacts sit uncommitted in the worktree. |
| `audit_trail` | **pass** | The fix is attributed to the judge finding with mechanism and mutation evidence recorded; ADR 0011 stands; the deliberately-undecided item is written down as open rather than dropped. |

## Concerns

1. Reproduced: the noparse warning sits inside the `[ -z "$planning_files" ]` branch, but step 8's supersession filter can empty that list *after* the check (`phase-guard.sh:301`), so a repo holding one superseded `planning` card plus one unreadable card allows the write in complete silence — exit 0, no output. Control (same unreadable card alone) warns correctly. This is RUN 1's concern 1 in a new location: the fix patched the instance, not the class. The git fail-opens at :265/:287 and detached-HEAD at :311 share the shape.
2. No test fixture pairs a skipped card with a superseded planning card, so the suite is structurally blind to concern 1 — the same fixture-shape gap that hid RUN 1's finding, one step over.
3. `hooks/phase-guard.sh:143-145` still asserts an absolute ("a skip … cannot cost it SILENTLY") that concern 1 disproves. More honest than the pre-fix wording, still not true as stated.
4. The spec's normative section (`docs/features/phase-guard-hook.md:286-294`) still specifies the pre-fix rule — "the `noparse` exit therefore requires at least one file present and **all present files skipped**" — contradicting both the shipped code (`nfiles > nparsed`) and the fix narrative at :1264+. A maintainer trusting the contract section would revert the fix.
5. New false-positive surface from the widening: any non-card `.md` in `docs/features/` (README, template, index) now triggers the once-per-session warning permanently in every opted-in repo, with a message ("the gate cannot be fully evaluated") that is false in that case. Verified by direct invocation. Silent under the old code; erodes the signal value the once-per-session cap was designed to protect.
6. Carried unchanged from RUN 1 and re-verified at this HEAD: committed ≠ armed — `phase-guard` appears 0 times in the live `~/.claude/settings.json`, `~/.claude/hooks/phase-guard.sh` does not exist, and the live repo has no `docs/features/`. Arms globally at merge with no live exercise. Merge-time self-lock re-checked and clear (the sole card parses, `phase: review`, branch recorded).
7. Carried from RUN 1, correctly recorded rather than decided: the branch-scoped deny collides with the parallel-worktree invariant, and the sanctioned fix is forbidden to the blocked agent. Accepting the deferral as in-policy (architecture trade-offs are human-owned), but it is a live decision the user must make before merge, not a closed item.
8. Carried from RUN 1, unchanged: branch-granularity hole (a claimed branch may write another still-planning feature's source); rollback path 3 withdrawn on the unverified premise that exit 126 may read as deny; `main` keeping cards at `planning` denies writes on unrelated hotfix branches until the PR merges.
