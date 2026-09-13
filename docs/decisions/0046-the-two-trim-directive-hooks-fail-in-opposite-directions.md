# 0046 — The two trim-directive hooks fail in opposite directions, and neither orders an unbacked cut

- **Status:** Accepted (2026-09-12). The fail-direction trade-off below was **decided by the
  user** on 2026-09-12 and is recorded as **D18** in the spec's Decisions table; this ADR
  records the shape and consequences, not the choice.
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

## Decision

When a hook cannot produce the filing rule and the protected-heading list — because the
reinject library is missing, unreadable, corrupt, or does not define `keep_trim_directive` —
the two hooks do **opposite** things with their output, and each is correct for its position:

1. **`live-handoff.sh` withholds the directive.** `REINJECT_LIB_OK` becomes a second
   suppression gate beside the existing `SNAPSHOT_OK`. No trim directive is emitted, whatever
   the line count; the append-mode directive goes out instead, carrying a warning that names
   *this* failure rather than the snapshot one.
2. **`pre-compact-handoff.sh` still emits a directive, but it orders append-only.** Write the
   handoff; remove nothing this run; here is the library that failed.

**What the two share, and what this ADR is really about:** neither hook ever authorises a cut
it cannot back up. They differ in *what they emit*, not in whether an unbacked removal may
proceed. That distinction is the whole decision — see the rejected alternative below.

## Why

The asymmetry follows from what each hook can still do after it declines to act.

`live-handoff.sh` fires on **every** user prompt. Withholding one trim directive costs a
single turn of notepad growth, and the hook gets another attempt moments later.

`pre-compact-handoff.sh` gets **one** chance. Compaction is about to happen and the notepad is
the only memory that survives it. Withholding its directive does not defer the cut; it
forfeits the handoff entirely — the original bug this card exists to fix. So it must speak.
Ordering *append-only* is how it speaks without authorising a removal it cannot verify.

Both files carry a comment naming the other and pointing here, because the natural instinct on
finding them different is to make them agree — which would break whichever one got changed.

## Rejected: fail open

An earlier revision had `pre-compact-handoff.sh` emit its **full rewrite** directive in this
situation, with a warning standing in for the heading list. The compliance judge failed it in
round 9 and was right on both counts:

- Ordering a rewrite while unable to list what must survive is exactly the unbacked promise
  spec finding O-C forbids for `live-handoff.sh`. Accepting it for the sibling hook traded the
  rule away rather than satisfying it.
- The trade-off was accepted in this ADR's own voice, with no acceptor named and no user
  decision recorded — the same shape D16 was routed out for. `rules/core-conduct.md` keeps
  architecture trade-offs human-owned.

It had two further costs that the append-only form simply does not incur: the directive
contained **self-conflicting instructions** ("REWRITE it completely" next to "do not remove
any"), leaving the model to reconcile them; and it needed a hand-copied paragraph of the
filing rule, which had **already drifted** from the library's wording (em dash to `--`,
closing clause dropped) in the same commit that argued against stating one rule twice.

## Consequences

- A reader must not "harmonise" the two branches. The comment at each site says so; this ADR
  is the reason.
- `pre-compact-handoff.sh` emits no line target on the degraded path, deliberately: a target
  invites a cut, and this path is the one where no cut is allowed.
- The suppression warnings in `live-handoff.sh` must stay distinguishable in wording, since
  two independent causes now lead to the same append-mode output. A test pins that the
  snapshot wording never appears in a reinject-only failure.
- ⚠️ **There is no mechanical backstop running today.** `hooks/handoff/handoff-keep-guard.sh`
  — the `Stop` hook that would detect a vanished `[KEEP]` line regardless of what any
  directive said — is written and tested but **registered in neither `settings.json`**
  (measured 2026-09-12: zero matches for `handoff-keep-guard` in that file; arming it is the
  card's open task 12). Until then every guarantee in this ADR is carried by directive text a
  model may ignore, and the earlier draft of this section describing the keep-guard as one
  that "remains the mechanical backstop" was asserting a protection that does not run.

## What this ADR does not claim

It does not claim either hook is protected against a library that fails to **parse** by the
`if [ -r "$LIB" ] && . "$LIB"` guard alone. Measured 2026-09-12: under `set -euo pipefail`
that guard does not intercept a parse error — the shell terminates at `rc=2` and the statement
after the `if` never runs, so the hook emits nothing at all. Both hooks therefore wrap their
sourcing in `set +e` / `set -e`, and that toggle — not the `if` — is what makes either
decision above reachable. The fix was falsified per hook by stripping only the bare toggle
lines from a scratch copy (`live-handoff.sh` has two pairs, `pre-compact-handoff.sh` one): in
both, the patched copy exits `0` with a full directive and the stripped copy exits `2` having
emitted **zero bytes**. No byte count is recorded for the patched copies, because the
directive embeds absolute paths and its length varies with the fixture path — a figure here
would be a receipt nobody could re-derive.

Neither hook is a security boundary. Both are momentum guardrails against accidental loss, and
with task 12 open, guardrails made of text rather than enforcement.
