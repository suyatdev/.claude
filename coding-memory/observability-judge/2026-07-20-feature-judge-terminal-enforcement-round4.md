# Observability Judge Verdict — feature/judge-terminal-enforcement (round 4)

- **ts:** 2026-07-20T18:08:26Z
- **repo:** `.claude` · **branch:** `feature/judge-terminal-enforcement` · **head:** `4f846ff8f9547c1cc7d37994c2b72f3eee8730bc`
- **stage:** architecting · **artifact:** `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-design.md` (1096 lines)
- **base:** `main` (merge-base `69ecd12`) · **prior rounds:** round 1 `8aed77a` (medium), round 2 `ccd02fc` (medium/high), round 3 `60abc86` (medium/high)
- **test command:** none supplied (spec phase). I independently re-ran the spec's git evidence instead — see below.

## What was changed

Round 4 of the spec for making both judge gates deterministic (hook-enforced) and running judges in
their own terminal panes. Two user-directed fixes from escalation #2, plus corrections:

1. **Prior-violations hand-off deleted, not re-sequenced.** Rounds 1–3 each failed on the same
   `writing-specs/api-contracts` violation at increasing depth (no caller → no data source → a
   destination that could not yet exist). Round 4 removes the hand-off entirely: the launcher itself
   extracts the prior round's `violations` array from the compliance store after creating the run
   dir. No caller passes the file; the flag survives only as an ad-hoc override.
2. **Detection stops enumerating commit forms.** Two consecutive rounds leaked a form (`-a`, then
   `-i`). §5.2 now delegates to git's own parser: `git commit --dry-run --porcelain -z <same args>`
   resolves the recorded file set; column-1 `M/A/R/C` on a spec path means the gate applies; `D` and
   `??` are excluded. The index==worktree precondition becomes universal for every form, deleting
   the per-form "effective blob" analysis where both prior bugs lived.
3. **§6.5 factual correction:** ten of seventeen live hooks set `timeout: 10` (the round-3 claim of
   none was false). The correction sharpens spike S3: 900s is a 90x extrapolation past the only
   observed precedent.
4. Four round-3 judge notes fixed; trim pass; the 800-line ceiling breach is named in §11 as a
   question for the user.

## Independent verification performed this round

The last two rounds each contained a claim that "passed review by being read rather than run," so I
re-ran the evidence rather than trusting the tables:

| Claim | My result |
|---|---|
| Five commit forms' column-1 values (plain, `-a`, pathspec, `-i`, `--only`) | **All match §5.2's table exactly**, including the `-i` hole (`M` for a staged spec past `-- other.txt`) |
| Untracked spec shows `??`, never reads as recorded | Confirmed |
| Dry-run mutates neither index nor worktree (incl. `-a`) | Confirmed — index blob identical before/after, `other.txt` still unstaged |
| Nothing-to-commit: exit 1, empty output (stderr included) | Confirmed |
| Rename `-z` field order: recorded path, then source as an extra NUL field | Confirmed via `od -c` |
| `--amend` lists the amended commit's whole file set | Confirmed (over-block as designed) |
| `git commit -ma "x"` parses as `-m a` (flag-scanning unsound) | Confirmed — `"x"` became a pathspec |
| Dry-run cost ~10ms | Confirmed — 9ms |
| 10 of 17 hooks in `settings.json` set `timeout: 10` | Confirmed by parsing `settings.json` — exactly 17 hooks, exactly 10 with timeout, all `10`, all Orca machine-local |
| `api-contracts` persisted rounds 1–3 in the compliance store | Confirmed — 3 stored fail rounds cite it |

One new gap found: **exit 1 with non-empty output is real and uncovered.** A commit attempt with
only untracked files present yields exit 1 plus a `??` entry — matching neither the
"exit 1, empty output → allow" row nor cleanly the "any other nonzero exit → fail closed" row. Read
as ordered predicates, a strict implementer fails closed on a commit git itself would refuse —
harmless in effect but a confusing block. The M/A/R/C whitelist must be stated as the decision
procedure (entries first, exit codes only when no entry answers the question). Also, row 3's phrase
"no spec entry with non-space `X` — including `??`" is literally self-contradictory (`?` is
non-space); the whitelist in row 1 is what disambiguates it.

## Does it do what was wanted?

Yes — this is the strongest round of the four, and the first whose load-bearing claims all survive
independent re-execution. Both user-directed fixes are structural deletions of the failing pattern
rather than patches to it: detection no longer contains a table that can leak a sixth form, and the
prior-violations path no longer contains a hand-off that can be dropped. The false §6.5 claim was
corrected in the direction that *worsens* the stated risk, which is the honest direction. The four
round-3 notes are all fixed in the text (verified at §6.1.2, the prompt template's `design_doc`
line, the §3 flowchart ordering, and the §10 header).

## What could go wrong

- **S3 is still the design's biggest unknown, and its failure shape is the worst available:** if
  the harness caps hook timeouts below 840s, the gate fails open silently exactly when the judge is
  slow. Correctly held as a blocking spike with a pre-committed fork (blocking-and-retrying), but
  nothing between 10s and 900s has ever been observed here.
- **S1 likewise:** without `--bare`, hooks run inside the judge session; if `JUDGE_SESSION=1` does
  not reach them, the design is deadlock-shaped. Correctly blocking.
- **The gate sits on `git commit`, the repo's most-run command.** Classification ambiguity fails
  open by stated posture (named, accepted); an implementation bug fails closed on every commit.
- **`SPEC_ESCALATION_ACK` remains re-suppliable** by the agent every round — the release is
  advisory and audited, not enforced, and the spec now says so plainly (§6.4, §11).
- **The spec grew, not shrank:** 1036 → 1096 lines despite the trim pass, ~37% past the 800-line
  ceiling. §11 puts the split question to the user honestly, but the trajectory of the number is
  worth noticing at review.
- The §5.2 result-table gap above (exit 1 + non-empty output; row-3 wording) — one paragraph fix.

## What to double-check before proceeding

1. Run S1 and S3 first, as §10 orders — nothing else in the design is worth building before those
   two answers, and S3's answer may fork the design.
2. Fix the §5.2 result table before implementation: state the decision procedure (spec entries
   first; exit codes only decide when no entry does) and reword row 3 so `??` is excluded by the
   whitelist, not by a self-contradictory "non-space" clause.
3. Decide the split question §11 asks — before implementation, since it determines what the
   spec-guard's own gate will judge.
4. At implementation, hold §10 to its own falsification mandate — especially the two detection
   mutations (form-table reintroduction, staged-only listing), which encode this branch's two
   actual bugs.

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| `intent` | pass | Both user-directed fixes present and structural; corrections and four notes all landed as claimed |
| `execution` | concern | Spec phase — nothing built, no runnable test; S1/S3 remain unmeasured by design. This round's own evidence, however, fully reproduces |
| `trajectory` | pass | First round scored pass here. Root-cause deletion over re-sequencing; evidence run, not read; the false claim corrected in the risk-sharpening direction |
| `regression` | concern | Unchanged in kind: most-run-command blast radius, fail-open ambiguity posture, 840s inline block, `--amend` over-block — all stated, none yet exercised |
| `context_budget` | pass | Always-on delta ~1 line in `rules/gates.md`; skills on-demand; the change reduces main-window cost by design |
| `traceability` | pass | Every reversal called out in-text ("corrected, not quietly patched"); evidence dated and versioned; ADR obligations listed |
| `success_masking` | concern | The rounds 1–3 silent-cap-no-op is genuinely closed (launcher-derived). Residual: S3's silent-fail-open shape; advisory ack; both named, neither closed |
| `intent_drift` | pass | Diff touches only the spec and memory docs; round stayed on the two directed fixes plus corrections; ceiling breach surfaced, not absorbed |
| `checkpoint` | pass | Docs-only commit on the feature branch; each round its own commit; trivially revertible |
| `audit_trail` | pass | Commit message attributes the user-directed fixes; branch log and compliance store carry the full escalation history; §11 defers with reasons |

## Concerns

1. S3 unmeasured: a harness cap below 840s fails the gate open silently exactly when the judge is slow — correctly blocking, all of §6.5 rests on it
2. S1 unmeasured: without `--bare` hooks run inside the judge session; deadlock-shaped if `JUDGE_SESSION=1` does not reach them
3. §5.2 result-table rows are not disjoint: exit 1 with non-empty output (untracked-only commit) is uncovered, and row 3's "non-space X including ??" contradicts the M/A/R/C whitelist that actually governs — verified against real git
4. `SPEC_ESCALATION_ACK` re-suppliable by the agent every round; the cap's release is advisory by stated design (§6.4, deferred §11)
5. Gate sits on the repo's most-run command; classifier ambiguity fails open by stated posture; a freshness miss blocks `git commit` inline for up to 840s
6. Spec grew 1036 → 1096 lines despite the trim pass, past the 800-line ceiling; split decision correctly put to the user in §11
7. No automated test exercises a real judge; cmux and Terminal rungs rest on a manual checklist (named in §11)
8. `--amend` atop a spec commit always re-gates (deliberate fail-closed over-block; a friction cost the user should confirm)
