# Observability verdict — `fix/replay-harness-base-pin` (implementation)

> **Round 2 (current, at `a5ee297`).** Round 1's verdict, at `e86ddb5`, is preserved verbatim at the
> bottom of this file under "Superseded — round 1". Same branch, same day, so both rounds share this
> filename by the naming rule; nothing from round 1 was discarded.

- **repo:** `.claude`
- **branch:** `fix/replay-harness-base-pin`
- **head_sha:** `a5ee297f182e01568045f5f0fd046dc3f97c5771`
- **stage:** implementation
- **ts (UTC):** 2026-08-05T21:19:32Z
- **base:** `main` (merge-base `56f1dfd`)
- **test command run by the judge:** `/bin/bash hooks/git-guard.test.sh` → **77 passed, 0 failed,
  exit code 0** (exit code captured before anything else ran)
- **previous verdict:** round 1 @ `e86ddb5` — `risk=low confidence=high`

## What was changed

Nothing about the actual fix. `git diff e86ddb5..a5ee297 -- hooks/` is **empty** — not one byte of
code moved since round 1. The single new commit is bookkeeping: it corrects two records that
disagreed with the repo.

Think of it as a lab notebook, not the experiment. The experiment (the replay harness that used to
compare a program against an identical copy of itself and call that a pass) was already done and
already checked. Round 1 found the notebook had two wrong entries. This commit fixes the entries.

The two fixes, both verified against the repo rather than taken on trust:

1. **The `phase: review` flag is now actually committed.** Round 1 judged a dirty working tree; the
   frontmatter flip was sitting uncommitted on disk. It is in `a5ee297` now, so the recorded head
   covers the on-disk state.
2. **The "blast radius" note no longer lies about its own size.** It said the change touched 3 files.
   `git diff --stat` says 6. The note now reads "measured pre-task-9, at `e5d1403`… final diff after
   task 9 is 6 files" and names the three files task 9 added. I counted: the real diff is exactly 6
   files, and the three named are exactly the three that appeared.

Plus `CODING_MEMORY.md` — the file that survives a session clear — was five tasks stale ("tasks 1-4
done, next is task 5"). It now says all nine are done at `e86ddb5`, records round 1's verdict, and
names the next step.

## Does it do what was intended?

Yes. Both corrections landed exactly as claimed, and my read of the fix itself is **unchanged from
round 1** — I say that on evidence, not to save effort: the hooks directory is byte-identical between
the two heads, so round 1's live reproductions (old harness false-passes at `378/0/0` exit 0; new one
refuses and names the SHA; Scenario I's `234/82/62` exact) carry forward untouched.

I still re-ran the two cheap things that gate freshness at this head:

| check I ran at `a5ee297` | result |
|---|---|
| `/bin/bash hooks/git-guard.test.sh` | **77 passed, 0 failed, exit 0** |
| Harness against base `main` (the old false-pass shape) | **REFUSED**, names base `56f1dfdf…`, **exit 1** |
| `git diff e86ddb5..a5ee297 -- hooks/` | empty — no code changed |
| Diff really is 6 files, as the corrected note now claims | confirmed |
| Task 8's three newly-named files match the actual additions | confirmed (ADR 0016, `git-guard-empty-index.md`, `shell-segments-redirects.md`) |

The deliberately-deferred item is handled correctly. Round 1 reproduced, live, that the default
`worktree` mode still prints `0 relaxed` / exit 0 for a candidate that is simply broken. That is
non-goal 2 in both the spec and ADR 0016 — disclosed before I found it, not discovered by me. This
session did **not** quietly widen scope to fix it; it is being put to the user as an open question.
Given this exact branch's own history (the two prior branches in this class each shipped a second
defect by widening mid-flight), refusing to self-authorize the fix is the right call, and I am not
scoring the deferral as a defect.

## What could go wrong / what I'm unsure about

No dimension is a `fail`. The honest residue:

**1. The known gap is still a gap, and disclosure doesn't change the mechanics.** Deferring it is
legitimate; what does not change is that in the mode people actually run, `0 relaxed` still is not by
itself proof of anything. A broken candidate that blocks everything scores zero relaxations and exits
0 — the pass shape. The only tell is a non-zero `stricter` count sitting next to it, and nothing forces
a reader to look. Keep quoting this tool as *base SHA + identical/stricter/relaxed*, never "0 relaxed".

**2. A committed file now points at an uncommitted one.** `CODING_MEMORY.md` cites
`coding-memory/observability-judge/2026-08-05-fix-replay-harness-base-pin.md` as the round-1 verdict.
That file is **untracked** (`git ls-files` → "Did you forget to `git add`?"), as is the `verdicts.jsonl`
change. So the memory index, which is the thing designed to survive a clear, currently points into
thin air from git's perspective. This is the same shape of defect round 1 flagged (a record that
disagrees with the repo), just one layer out — and it resolves the moment the judge artifacts are
committed, which has to happen before the PR anyway.

**3. Small wording imprecision in the checklist.** Task 9 reads "provenance notes on the four sites in
the part-6 table". The table has five rows: three got inline notes, one (`falsifier-base-pin.md:145`)
was already correct, one (ADR 0015) is amended by ADR 0016 instead per this repo's amend-by-new-record
convention. The sub-bullets underneath spell all of that out correctly, so the record is complete —
only the one-line headline is loose. Not worth a commit on its own; worth not propagating into the PR
description.

**4. Unchanged from round 1, still open, all disclosed:** the harness exits 0 even when it *does*
report relaxations (measured: 32 relaxed → exit 0), so it is unsafe to wire into CI as-is; there is no
test sibling guarding the harness (stated non-goal), so only ADR 0016 prevents a third recurrence of
this defect class; the `grep -q 'lib/'` membership probe matches comment lines (fails closed, so it is
loud, not silent); a no-argument invocation still dies with a raw `$1: unbound variable` instead of the
named `REPLAY ERROR`.

## What I'd double-check before merging

1. **Commit the judge artifacts** (this file and `verdicts.jsonl`) so `CODING_MEMORY.md`'s pointer
   resolves in a fresh clone. `doc-guard` already flagged the dirty tree at session start.
2. **Get the user's answer on the deferred non-goal 2** before the PR text is written, so the PR says
   "deliberately deferred, decision recorded" rather than going silent on a limit a judge reproduced live.
3. **In the PR description, quote the harness properly** — base SHA plus all three counts. A PR that
   cites "0 relaxed" alone from this tool would be repeating the exact mistake the branch exists to fix.
4. Optionally tidy task 9's "four sites" wording if the spec is touched again for any other reason.

## Dimensions

| dimension | verdict | note |
|---|---|---|
| intent | pass | Both round-1 corrections landed exactly as claimed and were verified against the repo, not the summary. Fix itself unchanged. |
| execution | pass | Judge re-ran the dependent suite at this head (77/0, exit 0 captured first) and re-confirmed the headline refusal live (exit 1, names `56f1dfd…`). |
| trajectory | pass | Targeted docs-only response to review findings; the tempting in-flight widening was explicitly escalated to the user rather than self-authorized — the correct lesson from this branch's own two prior failures. |
| regression | pass | `git diff e86ddb5..a5ee297 -- hooks/` is empty; `git-guard.sh` untouched; harness unregistered in `settings.json`; 3rd positional still defaults to `main`. |
| context_budget | pass | No rule/skill/prompt changes. `CODING_MEMORY.md` +23/−13 for a now-complete feature entry. |
| traceability | pass | Upgraded from round 1's `concern`: the blast-radius note now carries its measurement point (`e5d1403`) and the true 6-file count; memory index current. |
| success_masking | concern | Unchanged and disclosed: default `worktree` mode prints `0 relaxed`/exit 0 for a broken candidate (round 1 reproduced `292/86/0`), and a 32-relaxation run also exits 0. Recorded as non-goal 2 / ADR 0016 and deliberately deferred — not scored as a defect of this branch. |
| intent_drift | pass | `a5ee297` is docs-only and does precisely the two named fixes plus the memory sync. No new deps, no drive-by code edits, no silent scope growth. |
| checkpoint | pass | Single clean, revertible docs commit on top of nine granular ones; working tree now clean except the judge's own output. |
| audit_trail | pass | Commit message names round 1's verdict as its cause and states both slips; `CODING_MEMORY.md` records the verdict, the reproduced gap, and the next step. Nit: it cites an untracked file (concern 2). |

## Concerns (short form)

- Default `worktree` mode still prints the pass shape (`0 relaxed`, exit 0) for a broken candidate — disclosed non-goal 2, deliberately deferred to the user; mechanics unchanged by the disclosure.
- Harness exits 0 even when it reports relaxations (measured: 32 relaxed → exit 0); unsafe to wire into CI as-is.
- `CODING_MEMORY.md` (committed) cites the round-1 verdict file, which is untracked — the pointer dangles until the judge artifacts are committed.
- No test sibling for the harness (stated non-goal), so only ADR 0016 prevents a third recurrence of this defect class.
- Task 9's headline says "four sites"; the plan table lists five (3 annotated, 1 already-correct, 1 amended via ADR 0016). Sub-bullets reconcile it; the headline does not.
- `grep -q 'lib/'` membership test matches comment lines — fails closed, but is a heuristic.
- No-argument invocation dies with a raw `$1: unbound variable` instead of the named `REPLAY ERROR`.

**risk=low confidence=high** — the two record defects round 1 raised are genuinely closed and I verified
each against the repo; no code moved, so the earlier live evidence stands; the one substantive gap left
is pre-existing, disclosed, reproduced, and consciously deferred rather than overlooked.

---
---

## Superseded — round 1 (at `e86ddb5`), preserved verbatim

# Observability verdict — `fix/replay-harness-base-pin` (implementation)

- **repo:** `.claude`
- **branch:** `fix/replay-harness-base-pin`
- **head_sha:** `e86ddb5631235a2e38e7453de6b3d703ebe6c06c`
- **stage:** implementation
- **ts (UTC):** 2026-08-05T21:08:17Z
- **base:** `main` (merge-base `7bf2520`'s parent chain; diff taken vs `git merge-base main HEAD`)
- **test command run by the judge:** `/bin/bash hooks/git-guard.test.sh` → **77 passed, 0 failed** (5.7s wall)

## What was changed

`hooks/git-guard.replay.sh` is the repo's "did this change to the git guard make it weaker?" tool. It
runs two copies of the guard — an old one and the new one — over the same 63 commands in 6 repo
states, and reports every command the old one blocked but the new one lets through.

The problem: the "old one" was hard-wired to the word `main`. On `main` itself, or on any branch that
never edits the guard, the tool was quietly comparing the guard **against an identical copy of
itself** — and printing `378 identical, 0 relaxed, exit 0`, which is exactly what a hard-won genuine
pass looks like. Like weighing yourself twice on the same scale and announcing you haven't gained
weight.

This branch: adds a third argument so you can name the old version; refuses to run at all when both
sides are provably the same program; fails with a plain-English named error when a file it needs is
missing, empty, or the folder path doesn't resolve; and prints the real 40-character commit id of the
baseline in both the header and the summary instead of the word "main". Plus ADR 0016 recording the
rule, and one-line "which baseline was this measured against" notes on three older documents that
quoted a number from this tool.

## Does it do what was intended?

Yes, and I checked it myself rather than taking the summary's word for it:

| check I ran | result |
|---|---|
| Old harness (from `main`), relative path `.` | `378 identical, 0 stricter, 0 relaxed` — **the false pass reproduces exactly**, so the defect was real |
| New harness, same branch, absolute path, base `main` | **REFUSED**, names base `56f1dfd…`, exit **1** |
| New harness, relative path `.` | **REFUSED**, identical message — the relative-path route is genuinely closed |
| New harness vs a genuinely older base (`a9986b9~1`) | `346 identical, 0 stricter, 32 relaxed`, base printed as `b9b59e37…` at both sites |
| Self-contained base predating the helper split (`ac5afa2~1`) | `234 identical, 82 stricter, 62 relaxed` + the NOTE — **matches the claimed numbers exactly** |
| Missing worktree / unresolvable rev | named error, exit 1, correct invocation printed |
| `hooks/git-guard.test.sh` (the one dependent suite) | **77/0** |

The live hook `hooks/git-guard.sh` is untouched, the harness is not registered in `settings.json`, and
the third argument defaults to `main`, so old two-argument invocations still work. Production blast
radius is effectively zero — this is a developer tool.

## What could go wrong / what I'm unsure about

**1. The default mode can still print the pass shape for a broken candidate — I demonstrated it.**
I cloned the repo, deleted the two `hooks/lib/*.py` helpers the guard needs, and ran the harness in its
default `worktree` mode against a real older base. It printed:

```
378 pairs: 292 identical, 86 stricter, 0 relaxed (0 distinct commands)   exit=0
```

A candidate that is simply broken — it can't classify anything, so it blocks everything — scores **zero
relaxations and exits 0**, which is the headline "pass" criterion. The 86 "stricter" is the only hint,
and nothing forces a reader to look at it. This is disclosed (ADR 0016's "what this does not close",
non-goal item 2, and an in-code comment saying the worktree candidate is deliberately not validated),
so it is not a hidden defect — but it means "0 relaxed" is *still* not by itself proof of anything in
the mode people actually use. The summary's framing "closes four of five routes" is accurate on its own
terms and does not claim otherwise, but a reader could easily come away more reassured than the tool
earns.

**2. A run that finds real relaxations still exits 0.** Captured directly: the 32-relaxation run
returned exit code 0, indistinguishable from a clean run to any script or CI step. Disclosed in the ADR;
still a live foot-gun for anyone who wires this into automation.

**3. The blast-radius claim is stale at HEAD.** Task 8 in the spec (and the summary given to me) says
`git diff --stat main...HEAD` shows "only the harness, this feature file, and CODING_MEMORY.md". At
HEAD that is false — task 9 then added the ADR and edited two other feature docs, so the real diff is
**6 files**. The measurement was true when taken and the extra edits are one-line, disclosed, and
directly caused by the ADR's own rule; but the record now contradicts the repo, which is precisely the
"a number without its provenance" failure this branch exists to fix.

**4. `CODING_MEMORY.md` at HEAD is five tasks stale.** It says *"Tasks 1-4 done … Next: task 5"* and
pins the branch at `aa0420f`. All nine tasks are done at `e86ddb5`. That file is the thing that
survives a session clear, so a restore here would resume from a wrong picture of the branch.

**5. Nothing guards the fix.** There is no test sibling for the harness (a stated, reasoned non-goal),
so the only thing preventing this exact defect from returning is the ADR. That is a judgment control,
not a mechanical one — and this is the *second* time the class has bitten.

**6. Minor:** the "does this side use the helpers?" test is `grep -q 'lib/'` over the guard's bytes;
2 of the 3 matches in today's guard are comment lines. A guard that only *mentions* `lib/` in a comment
would be asked for helper files it doesn't use — that direction fails closed with a named error, so it
is loud, not silent. Also, invoking the script with no arguments still dies with a raw bash
`$1: unbound variable` rather than the nice `REPLAY ERROR:` message.

**7. Working tree was dirty when I judged.** `docs/features/replay-harness-base-pin.md` has an
uncommitted `phase: planning → review` frontmatter flip, so this verdict's `head_sha` does not cover
the current on-disk state. Docs-only, but the judge-guard match is against `e86ddb5`.

## What I'd double-check before merging

1. Commit the `phase: review` frontmatter flip, and refresh `CODING_MEMORY.md` to say tasks 1-9 done at
   `e86ddb5` — otherwise the next restore reads a branch that is five tasks behind.
2. Annotate task 8's blast-radius line ("measured before task 9; final diff is 6 files") so the spec
   stops disagreeing with `git diff --stat`.
3. Decide consciously whether item 2 in the non-goals (validate the worktree candidate's own helpers)
   should ride along. It is now a genuinely small change — the membership check already opens those
   files — and it is the difference between "0 relaxed" meaning something and not. Deferring is a
   defensible call given the last two branches shipped a second defect by widening mid-flight; just
   defer it *knowing* I reproduced the false-pass shape, not on the assumption it's theoretical.
4. When citing this harness in a future PR, quote **base SHA + identical/stricter/relaxed**, never
   "0 relaxed" alone — a nonzero `stricter` next to `0 relaxed` is the broken-candidate signature.

## Dimensions

| dimension | verdict | note |
|---|---|---|
| intent | pass | Built exactly the four routes scoped; the fifth is refused-by-record, not forgotten. |
| execution | pass | Judge re-ran the suite (77/0) and reproduced pre-fix false pass, post-fix refusal, real differential, and Scenario I's 234/82/62 exactly. |
| trajectory | pass | Red test first (`85bc35c`), one commit per task, self-corrected the two-clone setup mistake and recorded it as a setup error rather than a harness defect. |
| regression | pass | `git-guard.sh` untouched; harness unregistered in `settings.json`; 3rd positional defaults to `main`, so the old 2-arg call is preserved. |
| context_budget | pass | No rule/skill/prompt changes; `CODING_MEMORY.md` +6 net lines. |
| traceability | concern | Task 8's blast-radius record is contradicted by HEAD (3 files claimed, 6 actual); `CODING_MEMORY.md` five tasks stale. |
| success_masking | concern | Demonstrated: broken worktree candidate → `0 relaxed`, exit 0; and a 32-relaxation run also exits 0. Disclosed in ADR 0016, not closed. |
| intent_drift | pass | Two drive-by doc edits are one-line provenance notes, mandated by the ADR's own rule and listed in the checklist. No new deps. |
| checkpoint | pass | Nine granular, individually revertible commits; working tree dirty at judgment (docs-only frontmatter) is the only smudge. |
| audit_trail | pass | ADR 0016 states the rule, its limits, and a five-site provenance table; every task has a commit. |

## Concerns (short form)

- Default `worktree` mode still prints the pass shape (`0 relaxed`, exit 0) for a broken candidate — reproduced by the judge with the helpers deleted (`292/86/0`); disclosed as non-goal 2, not closed.
- Harness exits 0 even when it reports relaxations (measured: 32 relaxed → exit 0); unsafe to wire into CI as-is.
- Task 8 / summary blast-radius claim ("only 3 files") is false at HEAD — the real diff is 6 files after task 9.
- `CODING_MEMORY.md` at HEAD says "tasks 1-4 done, next task 5"; all 9 are done — the file that survives a clear is stale.
- No test sibling for the harness (stated non-goal), so only ADR 0016 prevents a third recurrence of this defect class.
- `grep -q 'lib/'` membership test matches comment lines (2 of 3 matches today) — fails closed, but is a heuristic.
- No-argument invocation dies with a raw `$1: unbound variable` instead of the named `REPLAY ERROR`.
- Working tree dirty at judgment time (`phase: review` uncommitted), so `head_sha` does not cover current on-disk state.

**risk=low confidence=high** — merging strictly reduces risk versus the status quo and the headline
route is independently falsified as closed; "low" refers to the merge, not to the harness being
trustworthy by default.
