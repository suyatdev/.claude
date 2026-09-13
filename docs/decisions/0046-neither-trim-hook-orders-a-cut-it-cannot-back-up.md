# 0046 — Neither trim hook orders a cut it cannot back up

- **Status:** Accepted (2026-09-12). The decision below was made by the **user** and is
  recorded as **D18** in the spec's Decisions table; this ADR records its shape and
  consequences, not the choice.
- **Context:** `hooks/handoff/live-handoff.sh` (`UserPromptSubmit`) and
  `hooks/handoff/pre-compact-handoff.sh` (`PreCompact`) both embed the filing rule and the
  `[KEEP]`-heading list produced by `keep_trim_directive()` in
  `hooks/handoff/lib/handoff-keep-reinject.sh`. Full design, the numbered user decisions and
  the task list: `docs/features/handoff-trim-safety.spec.md` and
  `docs/features/handoff-trim-safety.md` (task 8). Standalone — does not amend a prior ADR.
- **Note:** ADR number **0046** confirmed free 2026-09-12, after fetching `origin`, by two
  independent checks: `origin/main` — the deciding ref — tops out at `0044`, and a
  history-wide `git log --all --diff-filter=A --name-only -- 'docs/decisions/004*'` lists
  nothing above `0045` (this branch's own). No branch count is stated here on purpose: it
  goes stale the moment anyone pushes, and a stale count reads as audited.
- **Filename history:** first committed at `f7d570f` as
  `0046-the-two-trim-directive-hooks-fail-in-opposite-directions.md`. Renamed because that
  title asserted something the accepted decision made false — see *What the first draft got
  wrong* below.

## Decision

When a hook cannot produce the filing rule and the protected-heading list — because the
reinject library is missing, unreadable, corrupt, or does not define `keep_trim_directive` —
**both hooks instruct the model to append only and remove nothing**, and neither withholds
its output entirely.

They arrive there by different routes, and that is the only asymmetry left:

- `live-handoff.sh` **suppresses its trim directive** and falls back to the append-mode
  directive it already emits under the cap, carrying a suppression warning that names this
  failure distinctly from a snapshot failure. `REINJECT_LIB_OK` is a second gate beside the
  existing `SNAPSHOT_OK`.
- `pre-compact-handoff.sh` has no such fallback to reach for — its only directive is a
  rewrite order — so it emits a purpose-built append-only directive instead, naming the
  library that failed, and deliberately emits **no line target**, because a target invites a
  cut.

Measured at `79523fd` with a corrupt reinject library and a 204-line notepad: both hooks exit
`0`, both emit a directive, both order append-only, both name the failed library. The routes
differ; the instruction the model receives does not.

## Why

Withholding output entirely was rejected for `pre-compact-handoff.sh` and would be wrong
there. It fires once, immediately before compaction, and the notepad is the only memory that
survives. Suppressing its directive does not defer a cut — it forfeits the handoff, which is
the original bug this card exists to fix. `live-handoff.sh` is under no such pressure: it
fires again on the very next prompt, so dropping one trim directive costs a single turn.

What neither hook may do is order a removal it cannot back up. That is spec finding O-C, and
before this decision it held for one hook and not the other.

## Rejected: fail open

The first implementation had `pre-compact-handoff.sh` emit its **full rewrite** directive in
this situation, with a warning standing in for the heading list. The compliance judge failed
it in round 9 and was right on both counts:

- Ordering a rewrite while unable to list what must survive is exactly the unbacked promise
  O-C forbids for the sibling hook. Accepting it here traded the rule away rather than
  satisfying it.
- The trade-off was accepted in this ADR's own voice, with no acceptor named and no user
  decision recorded — the same shape D16 was routed out for. `rules/core-conduct.md` keeps
  architecture trade-offs human-owned.

It carried two further costs. The directive told the model to `REWRITE it completely` while
its embedded warning said `Nothing under any [KEEP] heading may be removed.` — two
instructions the model had to reconcile. And it needed a hand-copied paragraph of the filing
rule, which had **already drifted** from the library's wording (em dash to `--`, closing
clause dropped) in the same commit whose card text argued against stating one rule twice.

## What the first draft of this ADR got wrong

It was titled *"The two trim-directive hooks fail in opposite directions"* and its Decision
opened by asserting that asymmetry. That was true of the **rejected** fail-open design and
false of the accepted one: once `pre-compact-handoff.sh` orders append-only, both hooks
deliver the same instruction, as measured above. Two code comments repeated the claim and
told a future reader to preserve it, which would have meant restoring the rejected behaviour.
Recorded here rather than quietly rewritten, because the card's own task-8 entry *had* cited
those comments (at `f7d570f`) as the
guard against exactly that mistake.

## Consequences

- The remaining difference is a *route*, not a direction. A reader who finds the two branches
  written differently should not harmonise them into one: `live-handoff.sh`'s fallback is its
  ordinary under-cap directive, and giving `pre-compact-handoff.sh` the same fallback would
  mean giving it a line target, which is the thing that must not appear on this path.
- The suppression warnings in `live-handoff.sh` must stay distinguishable in wording, since
  two independent causes now lead to the same append-mode output. A test pins that the
  snapshot wording never appears in a reinject-only failure.
- ⚠️ **There is no mechanical backstop running today.** `hooks/handoff/handoff-keep-guard.sh`
  — the `Stop` hook that would detect a vanished `[KEEP]` line regardless of what any
  directive said — is written and tested but **registered in neither `settings.json`**
  (measured 2026-09-12: zero matches for `handoff-keep-guard` in that file; arming it is the
  card's open task 12). Until then every guarantee here is carried by directive text a model
  may ignore.

## What this ADR does not claim

It does not claim either hook is protected against a library that fails to **parse** by the
`if [ -r "$LIB" ] && . "$LIB"` guard alone. Measured 2026-09-12: under `set -euo pipefail`
that guard does not intercept a parse error — the shell terminates at `rc=2` and the statement
after the `if` never runs, so the hook emits nothing at all. Both hooks therefore wrap their
sourcing in `set +e` / `set -e`, and that toggle — not the `if` — is what makes either branch
above reachable. Falsified per hook by stripping only the bare toggle lines from a scratch
copy (`live-handoff.sh` has two pairs, `pre-compact-handoff.sh` one): in both, the patched
copy exits `0` with a full directive and the stripped copy exits `2` having emitted **zero
bytes**. No byte figure is recorded for the patched copies — the directive embeds absolute
paths, so its length varies with the fixture path and any number here would be a receipt
nobody could re-derive.

Neither hook is a security boundary. Both are momentum guardrails against accidental loss, and
with task 12 open, guardrails made of text rather than enforcement.
