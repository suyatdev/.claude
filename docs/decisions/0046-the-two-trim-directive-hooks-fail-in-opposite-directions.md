# 0046 — The two trim-directive hooks fail in opposite directions

- **Status:** Accepted (2026-09-12).
- **Context:** `hooks/handoff/live-handoff.sh` (`UserPromptSubmit`) and
  `hooks/handoff/pre-compact-handoff.sh` (`PreCompact`) both embed the shared filing rule and
  `[KEEP]`-heading list produced by `keep_trim_directive()` in
  `hooks/handoff/lib/handoff-keep-reinject.sh`. Full design, the user decisions D1-D17 and the
  task list: `docs/features/handoff-trim-safety.spec.md` and
  `docs/features/handoff-trim-safety.md` (task 8). Standalone — does not amend a prior ADR.
- **Note:** ADR number **0046** confirmed free 2026-09-12, after fetching `origin`, by two
  independent checks: `origin/main` — the deciding ref — tops out at `0044`, and a
  history-wide `git log --all --diff-filter=A -- 'docs/decisions/004*'` lists nothing above
  `0045` (this branch's own). No branch count is stated here on purpose: it goes stale the
  moment anyone pushes, and a stale count reads as audited.

## Decision

When a hook cannot produce the filing rule and the protected-heading list — because the
reinject library is missing, unreadable, corrupt, or does not define `keep_trim_directive` —
the two hooks do **opposite** things, and each is correct for its own position:

1. **`live-handoff.sh` fails closed.** `REINJECT_LIB_OK` becomes a second suppression gate
   beside the existing `SNAPSHOT_OK`. No trim directive is emitted, whatever the line count;
   the append-mode directive goes out instead, carrying a warning that names *this* failure
   rather than the snapshot one.
2. **`pre-compact-handoff.sh` fails open.** The rewrite directive is still emitted, with a
   warning standing in for the unavailable heading list.

## Why

The asymmetry follows from what each hook can still do after it declines to act.

`live-handoff.sh` fires on **every** user prompt. Withholding one trim directive costs a
single turn of notepad growth, and the hook gets another attempt moments later. Ordering a cut
while unable to say where the text must be filed or which headings are untouchable is the
exact unbacked promise this card exists to stop making — the same reasoning that already
governs a failed snapshot (spec finding O-C).

`pre-compact-handoff.sh` gets **one** chance. Compaction is about to happen and the notepad is
the only memory that survives it. Suppressing the directive there does not defer the cut; it
forfeits the handoff entirely. An incomplete listing of protected headings is strictly better
than no handoff, so this hook warns and proceeds.

Both files carry a comment naming the other and this ADR, because the natural instinct on
finding them different is to make them agree — which would break whichever one got changed.

## Consequences

- A reader must not "harmonise" the two branches. The comment at each site says so; this ADR
  is the reason.
- `pre-compact-handoff.sh` can emit a directive that orders a rewrite while listing no
  protected headings. The `Stop`-hook keep-guard remains the mechanical backstop for that
  case; the directive was never the enforcement.
- The suppression warnings in `live-handoff.sh` must stay distinguishable in wording, since
  two independent causes now lead to the same append-mode output. A test pins that the
  snapshot wording never appears in a reinject-only failure.

## What this ADR does not claim

It does not claim either hook is protected against a library that fails to **parse** by the
`if [ -r "$LIB" ] && . "$LIB"` guard alone. Measured 2026-09-12: under `set -euo pipefail`
that guard does not intercept a parse error — the shell terminates at `rc=2` and the statement
after the `if` never runs, so the hook emits nothing at all. Both hooks therefore wrap both
source calls in `set +e` / `set -e`, and that toggle — not the `if` — is what makes either
decision above reachable. The fix was falsified by stripping only the toggle lines from a
scratch copy: patched `rc=0` with 1,057 bytes of directive, stripped `rc=2` with 0 bytes.
Neither hook is a security boundary; both are momentum guardrails against accidental loss.
