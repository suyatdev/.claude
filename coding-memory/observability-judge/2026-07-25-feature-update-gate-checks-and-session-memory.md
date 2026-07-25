# Observability Judge Verdict — feature-update-gate-checks-and-session-memory

- **Repo:** .claude
- **Branch:** feature-update-gate-checks-and-session-memory
- **HEAD:** 98e732c42822ba6c2c4398caa723b07f19989197 (2 commits ahead of main: `22fb409` feature, `98e732c` docs-only checkpoint)
- **Stage:** implementation
- **Timestamp:** 2026-07-25T05:12:34Z

## What was changed

Where "am I allowed to write code right now?" used to live only in the conversation — which
forgets everything on `/clear` — it now lives in a file. Every feature-scale piece of work gets one
committed document (`docs/features/<name>.md`) with a small header (`phase`, `model_tier`,
`branch`) that says what's currently allowed. `rules/gates.md` and
`skills/managing-session-memory/SKILL.md` were rewritten to check that header first thing on every
restore, to require the literal words "gate confirmed" (not "yes"/"continue") before planning can
turn into implementation, and to cap handoff notes at ~1,500 tokens so they point at files instead
of re-explaining them. A new ADR (0010) records why, and what was deliberately rejected.

## Does it do what you wanted?

Yes, faithfully. Every piece named in the decisions summary is present in the diff and matches it
line for line — the five new `rules/gates.md` stubs, the rewritten skill, the template, the ADR,
the one-line catalog update. I independently checked two of the ADR's factual claims rather than
taking them on faith: the doc-guard hook really does treat `docs/*` (and so `docs/features/*`) as
satisfying the documentation requirement (`hooks/doc-guard.sh:149`), and ADR 0009 really is already
claimed by the still-open PR #28, so numbering this one 0010 avoids a real collision. Both checked
out true.

## What could go wrong / what I'm unsure about

- **It's never been used.** No `docs/features/<name>.md` exists anywhere in the repo yet — not
  even for this branch, which is itself feature-scale work and tracked its own state in
  `CODING_MEMORY.md` / a machine-local `session-state.md` instead. The mechanism this change
  introduces has zero worked examples and has not been rehearsed end to end (create → gate →
  restore → mismatch handling). The ADR itself names this as the open question ("Revisit when: the
  first feature runs end-to-end under this workflow").
- **It contradicts a skill it's about to be used with.** `skills/preparing-pull-requests/SKILL.md`
  (line 45) still says to "maintain a branch-specific implementation log
  (`coding-memory/branches/<branch>.md`)" — exactly the artifact this change just retired for new
  work. That's not a stale historical reference; `preparing-pull-requests` is the very skill this
  branch will invoke next to open its own PR. The ADR's "new overrides old on conflict" rule
  covers this in principle, but no skill states that precedence explicitly at the point of
  conflict, so a session following `preparing-pull-requests` literally would recreate the retired
  artifact.
- **The permission is still advisory-only.** A `phase-guard.sh` hook was deliberately deferred
  (reasonable, documented reasoning: "which feature file is active" is ambiguous mid-planning). But
  that means nothing computationally stops a session from acting out of phase — the improvement is
  that the *record* now survives a `/clear`, not that violations are caught. The ADR names this
  itself as a consequence, which is the right way to disclose it, but it's worth restating plainly:
  don't read "permission now derives from a file" as "permission is now enforced."
- **Always-on cost went up.** `rules/gates.md` is imported unconditionally into every session
  (`CLAUDE.md` → `@rules/gates.md`). Its word count rose from 707 to 989 (+40%) in this change; the
  single stub this replaces was 42 words, the five stubs that replace/extend it are 320. Separately,
  `CODING_MEMORY.md` is already 397 lines against its own stated 200-line ceiling (this branch adds
  4 more) — a pattern prior verdicts on other branches have flagged repeatedly as trending the wrong
  way.
- **Scope boundary is disclosed, not hidden** — worth noting as a strength, not a knock: the
  decisions summary states plainly that ~12 other files referencing the old
  spec-then-plan/`coding-memory/branches` workflow were left untouched, and that `writing-specs` /
  `writing-plans` were not reconciled. I confirmed the count is in that range for live,
  non-cache/non-fixture files.

## What I'd double-check before merging

1. Before this branch's own PR step, resolve (or at least flag in the PR description) the
   `preparing-pull-requests` vs. retired-`coding-memory/branches` contradiction, so it doesn't
   silently fire on this branch's own PR prep.
2. Create the first real `docs/features/<name>.md` on the next feature-scale branch soon, and treat
   any friction in the create → gate → restore cycle as a fast-follow, not a someday item — right
   now the design is unexercised.
3. Confirm the uncommitted `coding-memory/compliance-judge/*` files sitting in the working tree
   (flagged in this branch's own `session-state.md` as other sessions' shared-store writes) are
   genuinely not this branch's to commit, so they don't get swept into the next commit here.
4. Watch `rules/gates.md` and `CODING_MEMORY.md` size on the next few branches — both are
   always-loaded-or-near-it and both grew again this round.

## Dimension scores

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Every described piece present in the diff, matching the summary exactly. |
| execution | concern | No test command applies (docs-only, correctly so); two factual claims verified true; but the mechanism is undogfooded and collides with `preparing-pull-requests`. |
| trajectory | pass | ADR documents four alternatives actually weighed and rejected, with rationale checked against real repo facts (PR #28's ADR slot, doc-guard.sh line). |
| regression | concern | New, live contradiction with `preparing-pull-requests/SKILL.md`'s branch-log instruction — introduced by this change, not pre-existing. |
| context_budget | concern | Always-loaded `rules/gates.md` word count +40%; `CODING_MEMORY.md` still well over its own 200-line ceiling and grew again. |
| traceability | pass | Thorough commit messages, ADR with rejected alternatives and a named revisit trigger, consistent status across `CODING_MEMORY.md`/`session-state.md`. |
| success_masking | concern | Permission now survives `/clear` but remains fully advisory/unenforced (hook deferred by design) — self-disclosed by the ADR, real risk regardless. |
| intent_drift | pass | Scope held to the four binding decisions; "deliberately not done" list is honest and independently verified. |
| checkpoint | pass | Two clean, separate, well-described commits (feature, then a docs-only checkpoint); pushed. |
| audit_trail | pass | Proper commit attribution; ADR correctly numbered to avoid a real collision. |

## Overall

- **Risk:** medium
- **Confidence:** high

## Concerns

- New, live contradiction: `skills/preparing-pull-requests/SKILL.md:45` still instructs maintaining
  `coding-memory/branches/<branch>.md`, which this change retires for new work — and this branch
  will hit that exact skill next.
- The new phase-frontmatter mechanism has never been exercised: no `docs/features/*.md` exists
  anywhere in the repo yet, not even for this feature-scale branch itself.
- Permission is file-persisted but still unenforced (no hook); self-disclosed in the ADR as a
  deferred risk, not a hidden one.
- `rules/gates.md` (always-loaded) grew ~40% in word count; `CODING_MEMORY.md` remains well over
  its own 200-line ceiling and grew again this branch, continuing a pattern flagged on prior
  branches.
- Scope boundary (≈12 unreconciled files, `writing-specs`/`writing-plans` left as-is) is honestly
  disclosed and was independently spot-checked as accurate.
