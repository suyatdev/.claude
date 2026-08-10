# 0025 — Verification precedes the write-down, as a static rule in `core-conduct.md`

- **Status:** Accepted (2026-08-09)
- **Context:** `rules/core-conduct.md` § Session Defaults; extends the existing "verify before calling
  it done" invariant to cover durable artifacts. Procedure delegated to
  `superpowers:verification-before-completion`.
- **Note:** ADR numbers 0022, 0023 and 0024 are taken by unmerged PR #48
  (`feat/tracking-feature-state`), which already cites them by number. This decision takes 0025 rather
  than collide or renumber another branch's records mid-flight — the same courtesy ADR 0019 extended to
  `memsearch-freshness` task 2 over 0018.
- **Follows:** ADR 0019, which established that a standing expectation about *how the assistant works*
  belongs in `core-conduct.md` rather than auto memory, and that such a change earns a decision record
  answering *"does this belong in always-on context?"*

## Context

The existing rule said: verify your own and subagents' outputs before calling something done. It
governed the **claim** — what the assistant says in conversation. It said nothing about the
**write-down**.

That gap has been paid for repeatedly, and always in the same shape: a claim entered a durable artifact
before it was checked.

- A commit message asserted "eight `risk=low` verdicts" — a statistic nobody counted. The real figure
  was 6 `low` / 2 `medium`. The self-verification had been meticulous about *which rows* changed and
  silent about the number claimed about them.
- Eleven stored line numbers went stale inside their own implementation phase.
- A merge audit whose arithmetic balanced still shipped a conflict marker.
- A PR body claimed four fixes; `git show --stat` showed one file touched.

A spoken wrong claim is corrected in the next sentence. A **written** one reads as *settled*: every
later decision that trusts it inherits the error, and the cost of undoing it exceeds the cost of the
original mistake. That asymmetry — not the error rate — is what justifies a rule.

## Options weighed

| Option | Verdict | Why |
|---|---|---|
| **Static rule in `core-conduct.md`** | **Chosen** | The invariant must hold on *every* turn, before any skill loads and independent of task shape. A durable write happens in commits, handoffs and PR bodies that no skill is guaranteed to gate. |
| A hook that blocks claim-words | Rejected | Keying on "works / fixed / done" fires on every Conventional-Commits `fix:` prefix — a false-positive class this repo has already paid for. A hook cannot tell a verified claim from an unverified one; only the author knows whether the output was re-read. |
| Skill-only (`superpowers:verification-before-completion`) | Rejected as the *sole* home | A skill loads on trigger. The failure mode here is not knowing the procedure — it is not pausing to ask whether the thing was checked. That has to be always-on. **The procedure still lives in the skill**; only the invariant is promoted. |
| Auto-memory entry | Rejected | ADR 0019 retired auto-memory copies of always-on conduct for exactly this class. Repeating that mistake would split one invariant across two systems. |

This was triaged with `triaging-new-instructions` at authoring (2026-07-31); this ADR records the
result rather than re-deriving it.

## Consequences

- **It charges rent on every turn.** `CLAUDE.md` loads `rules/core-conduct.md` unconditionally. The
  file grows 628 → 733 words (**+17%**) for this. Accepted deliberately: roughly two of the five new
  sentences are rationale rather than instruction, and rationale is what makes a rule survive
  paraphrase — but it is the honest cost, and a future trim should start here.
- **It creates an explicit reporting obligation, not just a prohibition.** "Write what you checked and
  what you did not" means an unverified item must be *named* as unverified. An explicit gap is cheap; a
  false certainty is not.
- **It is self-applying, and was tested that way immediately.** While landing this very change the
  author reported the `triaging-new-instructions` gate as never run; the permanent record showed it had
  run at authoring. The observability judge caught the disagreement between a summary and the record —
  the exact failure this rule exists to prevent, surfacing in the rule's own paperwork. Left in the
  record rather than edited away.
- **Not enforceable by tooling.** Nothing in the repo tests rule prose, and no hook can verify that an
  output was re-read. This is a judgment rule; its only enforcement is the reviewer and the calibration
  record in `coding-memory/observability-judge/verdicts.jsonl`.
