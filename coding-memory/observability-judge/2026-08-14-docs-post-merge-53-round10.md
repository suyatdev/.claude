# Observability judge verdict — verification-marker-gate, round 10 (architecting, advisory)

- repo: `/Users/marksuyat/.claude/.claude/worktrees/tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `c6bf55665b5eb0b23efceb065e58bd7003f3edd8`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`, verified: all 15 tasks unchecked, `git status --short` and `git diff HEAD` both empty)
- ts: `2026-08-14T02:49:04Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 18, blob `f596c35f62cdd1a9eb2092f44a90b8479eb6c825`)
- prior verdict: `2026-08-14-docs-post-merge-53-round9.md` (head `859f303`, architecting, risk=low)

## What was changed

Two commits since round 9, 130 diff lines total, and I read the entire diff — nothing outside it.

- **Revision 17** (`86fc460`): closes the one item round 9 flagged as still unenforced —
  `written_at` was declared, in prose, unable to influence any decision, but no scenario varied it.
  A new `Scenario Outline` (3 rows) now asserts independence in **both** directions: a marker
  timestamped 1970 or 2099 with matching blobs still allows; a current timestamp with mismatched
  blobs still blocks.
- **Revision 18** (`c6bf556`): an **unprompted exhaustive sweep**, explicitly framed by the author
  as round 9's own suggestion carried out in full — every `MUST`-shaped sentence and bolded
  never/always claim in the file, checked for an enforcing scenario, not just the text the last fix
  touched. Three had none, all in §The marker: (1) the store is resolved from `git rev-parse
  --show-toplevel`, **never `$HOME`**; (2) the linked-worktree corollary of the same rule; (3) the
  store's `0700`/marker files' `0600` permissions. Three new scenarios close all three.

## Does it do what you wanted?

Yes, on both counts, and I verified rather than trusted the prose.

**The written_at gap is closed correctly.** I read the new outline (`:1053-1069`) — it varies the
timestamp independently of the blobs in both directions, which is the only shape that actually
tests independence; a single-direction scenario (e.g. only "ancient timestamp still allows") would
have been satisfied by an implementation that reads the clock in the other direction.

**The three revision-18 additions are genuine differentiating tests, not restatements of prose I
already had.** I checked each Given/When/Then for whether a plausible wrong implementation could
still pass it:
- `$HOME` scenario: a repo's own store is valid; `$HOME`'s store for the same path is deliberately
  made **stale**. An implementation that reads `$HOME` by mistake would block; this scenario forces
  the two stores to disagree, so it cannot be satisfied by accident the way an "agreeing store"
  scenario could.
- linked-worktree scenario: mirrors the same trap with a different resolver (main checkout vs.
  linked worktree), correctly treated as a separate assertion rather than assumed to follow from
  the first.
- permissions scenario: asserts `0700`/`0600` directly rather than relying on a umask default,
  closing exactly the gap the spec's own commit message names ("nothing else here would notice a
  0755 umask default").

**The size re-measurement is accurate.** I ran the file's own `awk` classifier (`:2193-2203`)
against `git show HEAD:docs/features/verification-marker-gate.md` myself:

```
total=2311 floor=1188 prose=1123 sum=2311
```

This matches the document's revision-18 claim exactly (`sum == total` also confirms no
double-count), and the scenario count (`grep -c '^Scenario'`) independently returns **70**, matching
"67 → 70." Working tree matches HEAD exactly, so nothing was measured against a moving target.

## Answering this round's three questions

**1. Do the three security-adjacent additions ($HOME/worktree resolution, store permissions) change
my read of the design's observability posture?** Yes, and for the better, specifically on
*success-masking* risk rather than on runtime tracing. Before revision 18, these were exactly the
kind of claim that erodes silently: a correct-looking implementation that read `$HOME`'s copy, or
left `hooks/state/` at a `0755` umask default, would have passed all 67 prior scenarios — the
$HOME failure mode is not hypothetical, it is the literal defect `fix/judge-guard-verdict-lookup`
existed to fix, and the same defect is what makes this very judge invocation carry an explicit
repo-path override in its prompt. Closing that with a scenario is the right fix at this stage;
these are structural, setup-time invariants (which repo's store gets read, what mode a directory
lands at), and belong as test assertions rather than as a per-decision log field — I don't think
the decision log needs to grow a new field for them, and the design doesn't propose one, which I
read as correct scoping rather than an omission.

**2. Do revisions 17–18 move either standing open item (`--status` deferral, `MSG_NO_PYTHON`), or
leave any *decision* newly untraced?** No to both, and I confirmed by re-reading the unchanged
text rather than assuming. §Follow-ups (`:2288-2296`) still lists `--status` as follow-up 1,
deferred, wording unchanged from round 9. `MSG_NO_PYTHON` references (`:58, 79, 154, 590, 1637,
1661, 1771`) are unchanged — it remains the sole flowchart leaf that writes no durable trace,
because no `<repo>` is known yet when it fires. Neither revision added a new flowchart branch or
decision path; both are enforcement additions for **existing** claims, not new behaviour. So the
answer to "any decision that leaves no record" is the same single answer as round 9:
`MSG_NO_PYTHON`, pre-existing and disclosed, not worsened or newly introduced here.

**3. Are the Examples tables now clear enough to drive tests from, rather than be hand-copied?**
Unchanged from round 9's carried-forward concern, in both directions. The spec still doesn't state
a bridge from a Gherkin `Examples` table to a parametrized bash/Python test construct (there's no
native Gherkin runner in this stack), so task 6/7 implementers still have to translate the two
Outlines (12-row door mapping, 3-row `written_at`) into real parametrized assertions by hand — the
risk round 9 flagged (re-derived into separate assertions that drift from the table) is not
foreclosed by prose alone. This round doesn't make it worse: the three new revision-18 scenarios
are plain `Scenario`s, not `Outline`s, so there's no new table to drift from — only the two
pre-existing outlines carry that risk, unchanged.

## What could go wrong / what I'm unsure about

- `--status` deferral: still real, still the single largest residual observability gap in this
  design. Unchanged by this round.
- `MSG_NO_PYTHON`: still untraceable by construction. Pre-existing, disclosed, unchanged.
- Task 6/7 risk (carried from round 9, unchanged): nothing yet forces the 12-row and 3-row
  `Examples` tables to become genuinely data-driven test parametrization rather than hand-copied
  assertions that can silently drift from the table.
- Everything above remains a property of the plan — 0/15 implemented, nothing has run.

## What I'd double-check before merging

- At task 6/7: confirm both Outlines (door mapping, `written_at`) are implemented as literal
  parametrizations over the tables, and confirm the three new single scenarios ($HOME, worktree,
  permissions) land as three distinct test cases rather than folded together.
- At task 14: the arming check is still the only proof of "gate is live" between runs — unaffected
  by this round, still worth re-confirming post-merge.
- Round 9's own open items (`--status`, `MSG_NO_PYTHON`) re-verified unchanged, not re-litigated.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | pass | Both of round 9's explicit or implied gaps (unenforced `written_at`, "sweep the whole file" recommendation) are closed correctly — verified against the new scenarios' actual Given/When/Then, not just their existence. |
| execution | concern | Still 0/15, no code — expected at this stage, carried as a stage marker, not a new defect. |
| trajectory | pass | The exhaustive sweep is a considered, self-attributed response to round 9's own finding (a fix-adjacent search misses defects elsewhere); size and scenario-count figures independently re-derived and match exactly. |
| regression | pass | Diff is 130 lines across two commits, confined to §The marker enforcement + size addendum — full diff read, no drive-by edits elsewhere in a 2,311-line file. |
| context_budget | pass | `docs/features/`, on-demand; growth stays inside the already-granted, measurement-backed waiver; three concrete scenarios plus one small outline is proportionate to three previously-unenforced claims. |
| traceability | pass | Three previously-silent security-adjacent guarantees ($HOME-vs-repo resolution, worktree resolution, store permissions) now have enforcing scenarios; decision-log mapping (unaffected by this diff) remains internally consistent. |
| success_masking | concern | The specific masking risk this round targeted (wrong store, wrong permissions, latent staleness rule) is now closed by falsifiable scenarios. Held at concern, not upgraded to pass, because the round-9 residual gap is unchanged: nothing computational catches the log going silently unread between `--status` runs. |
| intent_drift | pass | Diff is exactly the two described changes; no unrelated edits found on full-diff inspection. |
| checkpoint | pass | Two labelled, self-explaining commits (`86fc460`, `c6bf556`); working tree matches HEAD exactly; trivially revertible (docs only). |
| audit_trail | pass | Both commit messages are unusually thorough and self-critical, name precedent (`fix/judge-guard-verdict-lookup`) and even the live workaround this session needed for the same defect class; all cited measurements independently reproduced against the committed blob. |

## Concerns

- `--status` (follow-up 1) remains deferred — the largest residual observability gap, unchanged by
  this round.
- `MSG_NO_PYTHON` remains untraceable by construction (no repo resolved yet to log into) —
  pre-existing across sibling guards, unchanged, not newly introduced.
- Task 6/7 implementation risk, carried from round 9: the two `Examples` tables (12-row door
  mapping, 3-row `written_at`) still need to become genuine parametrized tests, not hand-copied
  assertions that can drift from the table — nothing in this round forecloses that risk, but nothing
  worsens it either.
- Still 0/15 implemented; every finding above is a property of the plan, not of running code.

risk=low confidence=high
