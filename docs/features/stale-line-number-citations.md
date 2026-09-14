---
phase: planning
model_tier: high
branch: none
---

# Line numbers cited as durable anchors have rotted repo-wide

Queued 2026-09-05 out of what was meant to be a three-line bookkeeping fix. The handoff for
`fix/secret-filename-case-blindness` named three stale `classify-secret-command.py:189`
references and called them a known follow-up. Auditing them turned up a population two orders
of magnitude larger, with a majority-stale sample.

Docs and code comments across this repo cite helper internals by line number —
`git-guard.sh:292`, `phase-guard.sh:285`, `classify-git-command.py:152`. Code moves; the
citations do not. A reader who follows one lands on an unrelated comment or a blank line, with
no signal that they have been misdirected. Several of these live in ADRs and feature cards that
later sessions read as authoritative.

## Measured

All counts below were measured in this session at `860d4a9` (branch
`chore/card-closeout-and-stale-citations`, whose only content change is a frontmatter
close-out, so these hold at `origin/main` `59f91e2` too). Re-derive rather than trusting the
figures; the command is given for each.

### Population

`coding-memory/**` is excluded throughout. Those are judge verdict ledgers — an immutable
record of what was true at a past SHA, where a stale-looking line number is *correct*. They
hold a further 222 matching lines (136 compliance + 86 observability) that must never be
"fixed".

```
git grep -nE '[A-Za-z0-9_-]+\.(py|sh):[0-9]+' -- . ':!coding-memory/'
```

| Measure | Value |
|---|---|
| Lines containing at least one citation | 564 |
| Citation **occurrences** (a line may hold several) | 676 |
| Distinct citing files | 69 |
| Distinct cited target files | 68 |
| Occurrences targeting the 16 guard/lib files below | 230 |

The 16-file subset is `classify-secret-command.py`, `classify-git-command.py`,
`classify-pr-command.py`, `classify-commit-command.py`, `decide-commit-gate.py`,
`shell_segments.py`, `secret_approval.py`, `write-test-marker.py`, and the `.sh` guards
`secret-command-guard`, `git-guard`, `doc-guard`, `merge-guard`, `worktree-guard`,
`phase-guard`, `judge-guard`, `test-marker-guard`.

Heaviest citing files, **counted as citing lines, not occurrences** (`cut -d: -f1 | uniq -c`;
the two differ because a line may carry several): `treko-degraded-no-cmux.md` 62,
`memsearch-freshness.md` 61, `2026-08-20-judge-verdict-tier-and-query-time-weight.md` 50,
`verification-marker-gate.md` 46, `argv0-spelling-blindness.md` 42,
`global-option-blindness.md` 25.

### Sample audited

A dispatched sub-session opened **32** citations from the 16-file subset — the citing sentence
*and* the cited line — and judged **19 STALE, 13 OK, 0 unclear**. Its own enumeration of that
subset came to 181 rather than the 230 measured here; the gap is unresolved and is most likely
lines carrying more than one citation. It is recorded rather than reconciled because it does
not change the finding.

**This sample is not random.** It is whatever that session reached before it was told to stop,
weighted toward `docs/decisions/*` and a handful of feature cards. The 19-of-32 rate must not
be projected onto the remaining population as an estimate. What it establishes is only that
stale citations are common and are not confined to one document.

**Verified independently by the main session** (6 of the 19, re-opened at `860d4a9` rather
than copied from the report — 5 stale rows reproduced exactly, and 1 row the sub-session marked
OK was confirmed OK):

| Cited as | Prose claims it holds | Actually at that line now | Correct line |
|---|---|---|---|
| `doc-guard.sh:149` | the `docs/*` allowlist arm | `exit 0` | `:175` |
| `git-guard.sh:292` | `has_fact COMMIT && on_main` | a comment about `..` path components | `:379` |
| `merge-guard.sh:39-43` | the `printf` + `exit 2` for missing python3 | range ends before the printf | `:42-46` |
| `phase-guard.sh:288` | the exempt-path list | a comment about `rules/*`, `skills/*` | `:295` |
| `classify-git-command.py:152` | where the `COMMIT` fact is raised | blank line | `:544-545` |
| `git-guard.sh:59-72` | inline python that parses the JSON payload | that block (off by one at each end) | — (OK) |

The three references the handoff originally named are confirmed stale by direct measurement:
`classify-secret-command.py:189` is cited at `docs/features/argv0-spelling-blindness.md:235`
and `:471` and at `hooks/secret-command-guard.test.sh:956`; the
`argv[0] in ("env","printenv")` test it describes is at **`:191`**.

### Not measured

- **198 of the 230** occurrences in the 16-file subset were never opened (230 measured minus
  the 32 audited; every audited row targeted a file in the subset). Fully unaudited citing
  files include `docs/features/argv0-spelling-blindness.md` (51 occurrences on 42 lines),
  `docs/features/verification-marker-gate.md` (54 on 46) and
  `docs/features/global-option-blindness.md` (28 on 25) — note these totals span all cited
  targets, not only the 16-file subset.
- The 446 occurrences targeting files outside the 16-file subset are entirely unaudited.
- The `docs/features/argv0-spelling-blindness.md` sentence claiming "six of them have in fact
  moved" was **not** located or checked. The prior handoff already warns that an exact-text
  oracle reports the argv0-rewritten lines as GONE and would publish a confident wrong figure,
  so no corrected count exists and none should be written without a per-member check.

## Why this is not a find-and-replace

Three failure modes make a blanket rewrite actively worse than the rot:

1. **Many stale-looking citations are correct history.** A sentence recording what a line held
   at a named SHA is true; "repairing" it falsifies the record. This already has a scar —
   `[[feedback_a_blanket_rewrite_corrupts_historical_claims]]`: a regex fixing 36 stale anchors
   also falsified the sentences recording what they were at the baseline.
2. **One document cites a file more than one way.** `[[feedback_one_document_cites_a_file_two_ways]]`
   — a repair regex matched only the backticked form and 8 long-form anchors survived, and the
   same violation was re-reported for two more rounds.
3. **A repaired number rots again on the next commit.** Fixing 230 anchors buys until the next
   edit of any guard. `[[feedback_store_the_derivation_not_the_number]]` is the governing
   lesson: eleven line numbers went stale inside their own implementation phase.

So the design question this card must answer is *not* "what are the right numbers" but **"what
should a durable citation anchor to instead"** — a symbol name, a grep-able unique string, a
SHA-anchored quote, or a generated-and-checked reference. Only once that is decided does a
migration make sense.

## Open questions for the gate

- What replaces a bare line number? Candidates: symbol/function name only; a quoted unique
  substring the reader can grep; an explicit `at <SHA>` anchor for genuinely historical claims;
  or a checked-in script that re-resolves anchors and fails CI when one no longer resolves.
- Is the fix retroactive (migrate 676 occurrences) or forward-only (new writing uses the new
  form; old citations get a blanket "line numbers below are as-of their commit" disclaimer)?
  Forward-only is far cheaper and avoids failure mode 1 entirely.
- Should a hook or CI check enforce it, and can such a check distinguish a live claim from a
  historical one? If it cannot, it will fire on the ledgers and on every SHA-anchored sentence.
- Does this deserve an ADR? It changes a documentation convention used in every card and ADR in
  the repo, which reads as structural.

## Task sketch — NOT a plan, gate not confirmed

1. Decide the replacement anchor form, and whether the fix is retroactive or forward-only.
2. Write the convention into the authoring standards so new cards and ADRs comply.
3. Build a resolver that, given a citation, reports resolves / moved / gone — and prove it can
   fail before trusting a clean run (`[[feedback_confirm_the_check_can_fail]]`).
4. Run the resolver over all 676 occurrences to get a real count, replacing the 19-of-32 sample.
5. Classify live-claim vs historical-record before touching anything.
6. Migrate whatever step 1 decided, in reviewable batches, never as one regex.
7. Decide whether to enforce, and where.

## Related

- `docs/features/secret-filename-ligature-blindness.md` — the other open card off this thread.
- The three `:189` references are deliberately **left stale** by
  `chore/card-closeout-and-stale-citations`; fixing 3 of 676 would make the docs read as
  audited while the rest stayed wrong.
