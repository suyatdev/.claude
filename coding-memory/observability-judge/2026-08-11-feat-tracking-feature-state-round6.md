# Observability judge — tracking-feature-state — architecting (advisory) — round 6

- **repo:** tracking-feature-state
- **branch:** feat/tracking-feature-state
- **head_sha:** 15cc372b5deac779294ed7b613e2be26d7819212
- **stage:** architecting (ADVISORY — verdict/outcome is `null`; this read does not satisfy `judge-guard.sh`, which requires a fresh *implementation*-stage verdict)
- **ts:** 2026-08-11T21:53:21Z

## What was changed

One commit, `15cc372`, docs-only, two hunks in one file (`docs/features/tracking-feature-state.md`) plus a `CODING_MEMORY.md` session log:

1. The frontmatter flipped `phase: planning → implementation` and `model_tier: high → low` — the user gave the literal `gate confirmed` and picked the lower model tier at the model-switch checkpoint.
2. The preamble paragraph explaining why a `planning`-phase card carried a real branch and ticked tasks was rewritten, because that explanation went false the instant the frontmatter said `implementation` — an ordinary card being mid-implementation is no longer an anomaly needing an excuse.

`docs/features/tracking-feature-state.spec.md` (the design/security/criteria half) is **untouched** — I independently re-hashed it at both the parent commit and HEAD and got the identical blob (`ca31bb8d…`) both times, matching the commit message's claim exactly. I also independently re-derived the three hashes the commit message cites (pair `2da12308→511b6d5e`, `.md` `4bccdca9→2ab92441`) with `git hash-object` and they matched to the character. This is one of the more scrupulously self-verifying commit messages I've checked on this card.

## Does it do what you wanted?

Yes. The stated intent — open the gate, and keep the one paragraph that referenced the old phase from lying — is exactly what the diff does, nothing more. I checked for scope creep (no design/task/criterion text moved, confirmed by the unchanged spec hash) and found none.

I also checked the thing this stage-change actually puts at risk: **whether the card now reads correctly as an instruction to a builder**, since it's live on `implementation` and pinned to the low tier. The one open action-item I was pointed at — task 8 owes a `server.py` edit (`confirm_surface()` collapses a timeout and a non-zero exit into one `"unrunnable"` state, so `confirm_timeout` can never actually be emitted) — is real. I read `server.py` directly:

```
236: def confirm_surface(surface, timeout=CMUX_TIMEOUT_SECS):
247:     except subprocess.TimeoutExpired:
248:         return "unrunnable"
250:     except OSError:
251:         return "unrunnable"
...
575:  return self._fail(502, "send_failed", "confirm_failed", command_id=command_id,
```

`confirm_timeout` appears nowhere in `server.py` today (`grep -n confirm_timeout task-tracker/server.py` → nothing) even though it's in the `reason` enum in three places in the spec. The card is right that this is the first thing to do, sequenced correctly (its own commit, before task 9's test, never in the same step — the user's own decision, recorded).

I checked whether the *same shape* (specified, asserted-in-prose, not actually emittable) exists anywhere else in the wire contract, per the prompt's specific ask. I re-derived the full reason-coverage set from source using both emitting shapes the card itself warns about (`_fail(...)` and the bare `audit(...)` call):

```
$ { grep -oE '_fail\([0-9]+, "[a-z_]+", "[a-z_]+"' task-tracker/server.py | sed -E 's/_fail\(([0-9]+), "[a-z_]+", "([a-z_]+)"/\1 \2/'
    grep -oE 'audit\("[a-z]+", [0-9]+, reason="[a-z_]+"' task-tracker/server.py | sed -E 's/audit\("[a-z]+", ([0-9]+), reason="([a-z_]+)"/\1 \2/' ; } | sort -u
```

Result: 15 distinct `(status, reason)` pairs, covering every enum value in the spec **except** `confirm_timeout` — which is exactly the one gap the card names, and no others. `sent=unknown` (the field the security section calls "the worst failure this feature has") *is* already wired correctly: `send_keys()` returns `"unknown"` on both `TimeoutExpired` and a non-zero exit, and both paths reach `audit(..., sent=sent)`. So the one real gap is the one the card names — I found no second, undisclosed one.

## What could go wrong / what I'm unsure about

- **The blocking prerequisite is real and not yet done.** `confirm_timeout` cannot currently be produced by the running server. This is correctly sequenced ahead of task 9 in both halves of the card, but as of this HEAD the code edit hasn't landed — so the very next action on this branch is a source change, not the test task the checklist's next unchecked box (`9`) would suggest to someone skimming only the checklist. The `.md` half does carry the warning inline on task 8's own line (session-start reading), which mitigates this, but a reader working from a lower-tier model and moving fast could still start `test_server.py` first.
- **`server.py` — the feature's entire new trust boundary — still has no automated test.** Task 9 is open; everything today is "smoke-verified against a cmux shim," per the card's own words. Not a defect of this commit, just the standing state at this HEAD.
- **Both size waivers on this card are still live.** `.spec.md` is 1,537 lines against its waived ≤800 cap; the `.md` half is 216 lines against its waived ≤200 cap (I re-ran `wc -l` on both — matches the card's own numbers exactly). Both are disclosed, user-accepted, and re-confirmed 2026-08-11, and this commit didn't add to either (the rewritten paragraph is a line shorter, not longer). Still worth a periodic gut-check that growth hasn't resumed.
- **This commit moved the compliance judge's own freshness key.** The card's convention ties a compliance PASS to a `pair` hash of both files; this commit's `.md` edit moves that hash (`2da12308 → 511b6d5e`), which the commit message states plainly and reasons through (the gate the compliance judge blocks — `writing-plans` ahead of user review — is already past; a genuine spec-half edit would still force re-entry). That's a defensible, disclosed judgment call, not a hidden gap, but it's a human call worth a second look rather than something I can validate mechanically.
- **The rewritten preamble does not add a new self-correction layer.** I compared old vs. new text directly: the new paragraph is a plain historical update (what happened, when, why the convention exists), not another "an earlier version said X and was wrong" clause stacked on top. Given this card's history of exactly that pattern recurring, this is worth noting as a clean edit, not a concern.

## What I'd double-check before merging

- That the `confirm_timeout` split lands in `server.py` as its own commit, genuinely before any `test_server.py` code — not folded into the same commit as the tests (the card is explicit that this must stay a separate step, and I'd want to see the commit boundary, not just trust the message).
- After that edit, re-run the reason-coverage derivation above (both shapes, not just `_fail`) and confirm `confirm_timeout` now appears and no new reason silently overwrote an existing mapping.
- Whether the compliance judge should, in fact, be re-run given the `.md` pair-hash moved — even though the reasoning for skipping it holds up, it's a judgment call about *this* pair, not something a hook is enforcing here.

## Dimension table

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Diff matches the stated intent exactly; independently re-verified via hash. |
| execution | concern | `server.py` (trust boundary) has no automated tests yet; the blocking `confirm_timeout` code fix is specified but not yet written. |
| trajectory | pass | Every cited hash, line count, and code claim I re-derived matched exactly. |
| regression | pass | Docs-only commit; no source touched. |
| context_budget | concern | Both halves remain over their ADR-0017 caps (waived, disclosed, unchanged by this commit). |
| traceability | pass | Commit message and CODING_MEMORY entry are exact and independently verifiable; I found no discrepancy. |
| success_masking | pass | Sequencing (code fix before test) actively prevents a self-fulfilling test for `confirm_timeout`. |
| intent_drift | pass | No design/security/task/criterion text moved; spec.md blob unchanged. |
| checkpoint | pass | Clean, atomic, easily revertible commit. |
| audit_trail | pass | Attributed, hash-lineage recorded, reasoning for skipping compliance re-entry stated plainly. |

## Concerns

- `confirm_timeout` is specified in the `reason` enum in three places but is not yet emittable by `server.py` (`confirm_surface()` collapses `TimeoutExpired` and a non-zero exit into one `"unrunnable"` state); the fix is correctly sequenced but not yet landed as of this HEAD.
- `server.py`, the card's own highest-value target (694 lines), still has zero automated tests — task 9 remains open.
- Both size waivers (`.md` ≤200, `.spec.md` ≤800) remain live and substantially exceeded, though undisclosed growth is not occurring at this commit.
- This commit's `.md` edit moved the pair hash the last compliance-judge PASS was measured against; skipping re-entry is a reasoned, disclosed call but not mechanically enforced.

## Risk / confidence

risk=low confidence=high
