# 0053 — A merge prompts only when the incoming content is not already on main

- **Status:** Accepted (2026-10-28). This record **answers open question §9.1** of
  `docs/superpowers/specs/2026-09-20-guard-loosening-approval-design.md` — task 2 on
  `docs/features/guard-loosening-approval.md`. It lands here rather than in the spec because no
  design content in that spec is edited under `phase: implementation`; the spec's §9.1 keeps a
  status-only pointer to this number, the same treatment §9.2 received in ADR 0052.
- **Decided by the user**, 2026-10-28, from the three options below with the measurements in hand.
  The open question was explicitly "must not be guessed", so the numbers were gathered first and the
  question was put with them.
- **Note on the number:** `0053` was checked free on 2026-10-28 by listing `docs/decisions/` across
  **all 49 remote heads** and all local heads, not just `origin/main`; the highest found anywhere was
  `0052`. Per ADR 0050's lesson, re-check at merge time.

## Context

A merge brings a guard change in without anyone editing the guard. Spec §9.1 states the dilemma and
leaves it open: prompting on every such merge may be noise, and not prompting is a hole.

## Decision

The watcher **skips a merge whose incoming content is already on `main`, and prompts otherwise.**
The deciding test, run at the moment of the commit:

```sh
git merge-base --is-ancestor "$(cat "$GIT_DIR/MERGE_HEAD")" origin/main
```

- exit 0 → the content is already on `main`, so it has already been through PR review → **silent**.
- **any non-zero exit → prompt.** Not only `1`. A bad or unreadable `MERGE_HEAD` exits `128`, and
  that must prompt, not allow; a hook that special-cases `1` and treats other codes as success
  inverts the fail direction §7 requires.

### Precedence over §7 — added 2026-10-29, after task 4 surfaced the gap

**§7 is checked first, and §7 wins.** As first written, the bullet above read "a missing
`origin/main` ref exits 128, and that must prompt", which contradicts §6.3's row
*`origin/main` is unreachable → REFUSE* and §7's row *baseline unobtainable → REFUSE*. Both cannot
hold for the same state.

The contradiction dissolves once the order is stated: without `origin/main` there is no baseline to
extract a permission list from, so the commit is **REFUSED** before the merge question is ever
reached. The `128` case this ADR governs is therefore the narrower one — **`origin/main` present,
`MERGE_HEAD` absent or unreadable** — and that prompts. A missing `origin/main` refuses.

Task 4's suite already encodes this split (`E8c` pins the true 128 case to ask; `E8d` accepts either
for the missing-baseline case). The wording here, not the suite, was what needed correcting.

This is a rule rather than a heuristic: it reads git's own reachability, never the commit subject.

## What was measured

### The rule's behaviour — live, on a throwaway fixture repo

Three real merges were created and the check run while `MERGE_HEAD` existed, which is exactly what
the hook will do. Fixture under the session's job tmp dir, `GIT_CONFIG_GLOBAL=/dev/null` so the real
global config could not leak in.

| Shape | `MERGE_HEAD` | rc | Verdict |
|---|---|---|---|
| A — feature branch merges `origin/main` in | identical to `origin/main` | 0 | **SILENT** |
| B — branch into branch, content never on `main` | side-branch commit | 1 | **PROMPT** |
| C — `origin/main` ref absent entirely | side-branch commit | **128** | **PROMPT** |

Case A is silent by construction, not by luck: `git merge origin/main` sets `MERGE_HEAD` to
`origin/main` itself, so the ancestor test is reflexive. Case C is why the rule reads "any non-zero".

### Why this shape of merge dominates here

Over all 1,915 commits on `origin/main` (measured 2026-10-28):

| | Count |
|---|---|
| Merge commits on `origin/main` | 180 |
| …whose diff against the first parent touches a file in ADR 0052's watch set | **76** |
| → committed by `GitHub <noreply@github.com>` (the server-side "Merge pull request" button) | **37** |
| → committed locally by Mark Suyat | 39 |
| Non-merge commits touching a watched file | 91 |

The 37 server-side merges are **structurally unreachable** by this or any local hook: they execute
on GitHub's servers, where no `PreToolUse` hook and no git hook of this machine runs. Firing on
merges therefore cannot catch the moment a loosening lands on `main`. This is the same boundary ADR
0052 and the card already state — the feature gates a loosening being **proposed**, and PR review
remains the last line — and it is the strongest single argument against "always ask": the thorough-
looking option buys no coverage at the point that matters.

## What was NOT measured, and cannot be

**The historical silent/prompt split is not recoverable from git history.** Two defensible proxies
were run and they disagree:

| Proxy | Result | Known bias |
|---|---|---|
| Is `MERGE_HEAD` an ancestor of **today's** `origin/main`? | 0 of 76 would prompt | Over-permissive: a branch merged branch-to-branch became an ancestor of `main` *later*, so a merge that should have prompted reads as silent today. |
| Is `MERGE_HEAD` on `origin/main`'s **first-parent chain** (323 commits)? | 16 of 39 local merges would prompt | Under-counts silence: where `main`'s first-parent chain passes through a feature branch, genuine older `main` tips fall off the chain and read as "never on main". |

The question "was this content on `main` at that moment" needs `origin/main`'s position at that
time. Git does not retain it for past merges — a reflog would, and none covers this range. So the
expected noise is bounded, **between 0 and 16 of the 39 local merges**, and is not a point estimate.

⚠️ An earlier draft of this decision quoted "33 silent, 6 asked". That figure came from reading
commit **subject lines** — a self-reported label, not a run of the rule — and is withdrawn. It is
recorded here rather than deleted because it was the number the question was first framed with.

Also not measured: the watcher itself does not exist, so nothing here demonstrates the feature's
behaviour. No `git rerere`, octopus merge (three or more parents), or `git merge --squash` case was
tested; a squash merge produces no `MERGE_HEAD` at all and so falls to the ordinary non-merge path,
which is correct but untested.

## Residual holes, stated rather than closed

1. **Server-side PR merges (37 of 76) are out of reach.** Nothing local sees them.
2. **A fast-forward `git pull` of `main` creates no commit**, so the watcher — keyed on `git commit`
   — never fires when an already-merged loosening arrives in the working checkout.
3. **"Already on `main`" means "passed PR review" only as far as PR review actually looked.** The
   rule inherits the review's thoroughness; it does not add any.
4. **A stale `origin/main` errs toward prompting**, which is the safe direction, but means the rule
   is noisier right after someone else pushes and before the next fetch.
5. The approval record remains agent-written and therefore forgeable from inside a session. This is
   a momentum guardrail, not a security boundary — unchanged by this decision.

## Consequences

- Spec §9.1 is answered; §9.1's text is left standing and points here, per the phase gate.
- Spec §5 must fold in the merge branch of the flowchart. It is already out of date on two other
  counts (ADR 0052, decisions 1 and 2), so §5 is revised once, at the next phase boundary.
- Task 9 must state hole 1 and hole 2 in `rules/gates.md` and `hooks/README.md`. The deny/prompt
  message must not claim merges are covered.
