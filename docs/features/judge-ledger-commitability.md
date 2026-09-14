---
phase: implementation
model_tier: xhigh
branch: chore/judge-ledger-commitability
---

# Judge ledgers: make the two tracked ledgers committable again, and auto-merge their appends

Planned 2026-08-21 on `main` @ `a2a6022`, immediately after PR #59 merged.

## Problem — an unintended interaction inside PR #59, not a decision to revisit

ADR 0031 deliberately kept exactly two files tracked under the retired tree:
`coding-memory/observability-judge/verdicts.jsonl` and
`coding-memory/compliance-judge/verdicts.jsonl`. Its stated reason: they are the accumulated
judge record, and untracking would fragment it per worktree.

The **same** change narrowed `git-guard`'s default-branch allowlist to `docs/*.md` alone
(`hooks/git-guard.sh:386` — the only allow arm; every other path sets `allowed=0`).

Those two decisions cannot both hold. A file that is tracked but cannot be committed on `main`
can only accumulate uncommitted drift. ADR 0031 chose to keep them tracked; it never chose to make
them un-committable.

## Evidence — measured 2026-08-21, re-run before acting

Observed on this machine while pulling `a2a6022` into the shared checkout:

| Ledger | base `7fcfd95` | `origin/main` | local working tree | true union |
|---|---|---|---|---|
| compliance | 123 | 133 (+10) | 146 (+23) | **156** |

Both sides had appended. Neither was a superset. `git pull` aborted with
"Your local changes would be overwritten", and the union had to be rebuilt by hand and verified
in both directions (0 rows lost, 0 invented).

The record is genuinely cross-project, which is why fragmenting it is the wrong fix:

| Ledger | rows | rows with `outcome` backfilled | distinct repos |
|---|---|---|---|
| observability | 199 | 69 | 15 |
| compliance | 156 | 5 | 10 |

Derivation (run it, do not copy the number):
`python3 -c "import json;r=[json.loads(l) for l in open(P) if l.strip()];print(len(r),sum(1 for x in r if x.get('outcome')),len({x.get('repo') for x in r}))"`

> **Superseded 2026-08-23 — these counts are stale.** Re-run in the `rule-surface-trim` worktree
> with the derivation above. See *Re-measured 2026-08-23* below for the current figures and for a
> caveat on what the "distinct repos" column actually counts.

## Re-measured 2026-08-23

Re-run from source in `.claude/.claude/worktrees/rule-surface-trim` @ `c762562`, using the card's
own derivation — not copied from the hand-off that requested this check.

| Ledger | card claimed (2026-08-21) | re-measured (2026-08-23) |
|---|---|---|
| observability | 199 rows / 69 `outcome` / 15 repos | **203 / 69 / 16** |
| compliance | 156 / 5 / 10 | **161 / 5 / 11** |

**Caveat on the third column — it does not count what its heading says.** The derivation counts
distinct values of the `repo` field, and that field is unnormalized: it holds worktree basenames
(`phase-guard-hook`, `statusline-followups`, …), one bare project name, and one absolute path
(`/Users/…/worktrees/tracking-feature-state`, which also appears as the basename
`tracking-feature-state` — the same checkout counted twice). Distinct *projects* is far lower:
observability spans `.claude` and its worktrees plus `Snatch-Bracket`; compliance adds
`mtg-wizard` and `vibe-scape`. Report 16 and 11 as **distinct `repo` values**, not repositories.

The structural claim survives this correction and is in fact strengthened by it: the ledger
already spans a dozen-plus checkouts of the *same* repo, which is precisely the state that
per-worktree fragmentation would shatter. Keeping one shared record is the right call; the reason
is the checkout spread, not a large project count.

### Live drift, measured 2026-08-23

Row counts (non-blank lines) in every checkout on this machine, against `origin/main` @ `e6a9bb6`.
This is the card's "neither side is a superset" case happening in six places at once:

| checkout | observability | compliance |
|---|---|---|
| `origin/main` (`e6a9bb6`) | 210 | 170 |
| `.claude` (shared) | **212** | **165** |
| `rule-surface-trim` | 203 | 161 |
| `treko-ui-update` | 212 | 170 |
| `hook-wiring-health-check` | 212 | 161 |
| `settings-split` | 204 | 161 |
| `jlc-guard` | 203 | 161 |
| `jlc-union` | 203 | 161 |

`jlc-guard` and `jlc-union` are the two sibling worktrees for this feature; they did not exist when
the drift table was requested. Every other row reproduced the requested figures exactly.

The shared checkout is **ahead of `origin/main` on one ledger and behind on the other** — 212 vs 210
observability, 165 vs 170 compliance. A set comparison (not just row counts) sharpens this:

| | rows only in `origin/main` | rows only in `.claude` | union |
|---|---|---|---|
| observability | 3 | 5 | 215 |
| compliance | 5 | 0 | 170 |

So observability is *genuinely divergent* — each side holds rows the other lacks, and no
fast-forward can reconcile it without a merge. Compliance is currently a clean subset (behind
only). One ledger diverged and one lagged, in the same working tree, at the same moment: exactly
the failure this card exists to stop.

## Scope

Two changes. Nothing else.

1. **`hooks/git-guard.sh`** — allow the ledger path(s) on the default branch, alongside `docs/*.md`.
2. **`.gitattributes`** (does not exist yet) — `merge=union` for the ledgers, so concurrent appends
   from two branches concatenate instead of conflicting. Git's built-in driver; no custom script.

**Explicitly out of scope:** widening the allowlist beyond the ledgers, un-retiring anything,
changing what the judges write, and backfilling `outcome` values.

## Open questions — decide before implementing

- **Exact literals or a pattern?** Two exact paths is tightest. `coding-memory/*/verdicts.jsonl`
  admits future judges — but note `*` spans `/` in a `case` pattern (the file says so at
  `git-guard.sh:384`), so that pattern matches any depth. **Recommendation: two exact literals**,
  since a third judge is hypothetical and the guard should be as precise as the rule it enforces.
- **Does `merge=union` risk duplicate rows?** Yes, if both sides contain a byte-identical line.
  Rows carry distinct `ts`/`head_sha`, so this should not occur — but the test must prove it.
- **`merge=union` does not fix the case that actually bit us.** Today's abort was uncommitted local
  changes on a *fast-forward*, where no merge runs. The allowlist change is what removes the reason
  drift accumulates; the union driver is for branch-vs-branch. Both are wanted; neither alone.

## Tasks

- [x] 0. Branch `chore/judge-ledger-commitability` + worktree. **Only after `gate confirmed`.**
- [x] 1. Re-run the evidence above; confirm the counts still hold at the then-current `main`.
- [x] 2. **Red:** add `git-guard.test.sh` cases asserting a commit of each ledger on `main` is
      currently REFUSED, and that `coding-memory/other.md` and a traversing
      `coding-memory/../src/x.sh` stay refused after the change. Watch them fail for the right reason.
- [x] 3. **Green:** add the allow arm(s) at `git-guard.sh:386`; update the `:391` refusal message,
      which currently names only `docs/*.md`.
- [x] 4. Update `hooks/git-guard.replay.sh` expected values — the two ledger commands move from
      `stricter` to `identical` vs. the pre-#59 base. Confirm the run still reports **63 commands**;
      a mutation that drops a case from `CMDS` proves nothing.
- [x] 5. `.gitattributes` with `merge=union`, scoped to the ledger paths.
- [x] 6. Test the union driver for real: two branches each append a row, merge, assert both survive
      and no duplicate appears. This is the claim that must not be asserted without running it.
- [x] 7. Update `rules/gates.md` (default-branch safety stub names the allowlist verbatim),
      `hooks/README.md`, and `skills/managing-session-memory` where they state `docs/*.md` alone.
      > **Correction 2026-08-23 — this task names the wrong skill, and undercounts the sites.**
      > `skills/managing-session-memory` contains **zero** occurrences of `docs/*.md`; the real
      > third file is `skills/preparing-pull-requests/SKILL.md`. There are **five** sites, not
      > three, verified by re-opening each reference at `c762562`:
      > `rules/gates.md:12`, `hooks/README.md:76`, `hooks/README.md:81`,
      > `hooks/README.md:291` (cited as `:292` in the hand-off — it had moved by one), and
      > `skills/preparing-pull-requests/SKILL.md:12`. A sixth site,
      > `hooks/doc-guard.sh:166`, is a comment describing itself as "broader than git-guard.sh's
      > `docs/*.md`" — stale once the allowlist grows, so it was corrected too (comment only).
      > `docs/decisions/0031-one-tracked-record-and-the-guards-that-follow-it.md:93` states the old
      > allowlist inside a mermaid diagram and is **deliberately left alone**: ADR 0031 is merged
      > and is the historical record, to be amended by the new ADR in task 9, not edited.
- [x] 8. Full suite green — record counts run, not counts read.
      > **2026-09-14 — 38 suites run, 37 exit 0, 1 exit non-zero. Not a clean sweep; say so.**
      > The suite list was re-enumerated from the filesystem *after* the merge rather than reused:
      > merging `main` added **13 suites** (38 now, 25 before) that a stale hand-list would have
      > skipped in silence, reporting a green run over two thirds of the tree.
      > The red one is `hooks/lib/write-test-marker.test.py` (63 passed, 2 failed), pre-existing on
      > `main` and not reachable from this branch: both failures say
      > `panes/dispatch-pane-agent.test.sh` and `panes/run-pane-agent.test.sh` never call the
      > marker-write helper. Measured — `origin/main`'s own copy of the first contains **0**
      > occurrences of `hooks/lib/write-test-marker.py`, and `git diff origin/main` over `panes/`
      > plus both writer files is **empty**, so the bytes under test are byte-identical to main's.
      > One receipt was written by hand: `hooks/test-marker-guard.test.sh` passed **249/0** against
      > these exact bytes but never calls the writer for its own subject, so no marker appeared —
      > the same wiring species as the two `panes` suites. Recorded, not fixed — that gap belongs to
      > `docs/features/verification-marker-gate.md`, which already records leaving
      > `hooks/test-marker-guard.test.sh` unwired. Named here rather than left as "its own card",
      > which asserts a card exists without saying which.
- [x] 9. ADR under `docs/decisions/` amending ADR 0031: state that keeping the ledgers tracked and
      excluding them from the allowlist were incompatible, and which one moved.
- [x] 10. Observability judge, then draft PR.
      > **2026-09-14 — judge `risk=low confidence=high`; draft PR #104.** The judge reproduced every
      > claim rather than reading it, and returned five findings, all acted on here:
      > (a) `hooks/git-guard.sh:234` was a dead citation — corrected to a name-based anchor;
      > (b) a stale "docs/*.md alone" comment in `hooks/git-guard.test.sh`;
      > (c) "its own card" named no card — now names `verification-marker-gate.md`;
      > (d) **nothing invokes `git-guard.replay.sh`** — no hook, runner or CI; added to ADR 0047 as
      >     a bound on every claim it makes. Pre-existing, open work, its own card;
      > (e) emptying `EXPECTED_RELAXED` crashes under bash 3.2 `set -u` rather than reporting.
      > It also **strengthened** finding 2 beyond what this card claimed, and the correction was
      > re-measured here before being written down: injecting the two ledger rows into `origin/main`'s
      > own harness yields `8 relaxed`, `REPLAY FAILED`, rc=1. So the old gate was **sound** — blind
      > only in its population. "The ratchet was blind" was an overstatement and has been fixed in
      > ADR 0047.
      > PR opened *before* these commits by design: `judge-guard.sh` requires `head_sha == HEAD`,
      > and committing the verdict moves HEAD and invalidates it.

## Also worth fixing while here — decide separately, do not silently bundle

PR #59's card claims "nothing is deleted from disk". That is **true only in the worktree where
`git rm --cached` ran.** Six judge rounds confirmed it, all six looking at that worktree. In any
other checkout, pulling `a2a6022` fast-forwards and **deletes 213 files** (`CODING_MEMORY.md` +
212 under `coding-memory/`); being gitignored does not protect a file tracked at the old commit.
Proved in an isolated repo, not assumed. Recovery, verified:
`git archive 7fcfd95 CODING_MEMORY.md coding-memory | tar -x -C <repo> --exclude='*/verdicts.jsonl'`
(the `--exclude` is load-bearing — without it the old ledgers overwrite the live ones).

This is a factual error in a merged document and will mislead the next person who pulls on another
machine. It is a docs-only fix and could ship as its own small PR ahead of this one.

> **Decided 2026-08-23 by the user: bundle it into this PR instead.** The correction ships inside
> `chore/judge-ledger-commitability` rather than as the separate pre-PR suggested above. Recorded
> explicitly so a later reader does not read the suggestion as having been overlooked — it was
> considered and overridden. The correction is now in place at
> `docs/features/rule-surface-trim.md`, as a dated note beside the false claim rather than a
> rewrite of it, since that card is the record of PR #59.

## Decisions

- **2026-08-23, user — exact literals, not a pattern.** The allowlist gains
  `coding-memory/observability-judge/verdicts.jsonl` and
  `coding-memory/compliance-judge/verdicts.jsonl` as two exact paths, resolving the first open
  question above in line with its recommendation. A third judge is hypothetical, and the guard
  should be exactly as wide as the rule it enforces — `coding-memory/*/verdicts.jsonl` would also
  match at any depth, since `*` spans `/` in a `case` pattern. All rule and documentation text was
  written against these two literals.
- **2026-08-23, user — bundle the PR #59 correction into this PR** rather than shipping it ahead
  as its own docs-only PR. See the note directly above.

## RATIFIED 2026-09-14 — the replay contract change, and what it cost to confirm

**`hooks/git-guard.replay.sh` gained an `EXPECTED_RELAXED` list, changing that file's headline
contract** from *"never weaker than main"* to *"never weaker than main **except where declared**"*.
The user ratified this on 2026-09-14. It is recorded as a named decision in
`docs/decisions/0047-a-tracked-file-that-cannot-be-committed-is-the-defect.md`, which supplies the
reasoning and the residual risk; this section keeps only the measurements.

Task 4's premise was false and this is the fallout. The two ledger commands were **never in
`CMDS`**, so nothing could "move from `stricter` to `identical`".

**Re-measured 2026-09-14 against `origin/main` (`270a0b9`), run not read.** The earlier figures in
this card were taken at `b0250b4` against a `main` that has since advanced 496 commits, so they
were re-derived rather than carried forward:

| Harness version | Guard under test | Result |
|---|---|---|
| `origin/main`'s copy | this branch (widened) | 63 cmds x 6 = **378 pairs, 378 identical, 0 relaxed**, exit 0 |
| this branch's copy | this branch (widened) | 65 cmds x 6 = **390 pairs, 382 identical, 0 stricter (0 unexpected), 8 relaxed (2 distinct, 0 undeclared)**, exit 0 |

The first row is the finding, not a control: the old harness, pointed at a guard that genuinely
allows two commands the baseline blocks, reports a clean sheet and exits 0. The narrowing in PR #59
was invisible to every replay run that ever executed.

**The gate still discriminates — proven by mutation, not by observing a pass:**

```
MUTANT rc=1
REPLAY FAILED: 4 undeclared relaxed (of 8 total), 0 unexpected stricter
```

⚠️ **The first falsifier attempt was itself wrong, and passed.** The entry text appears **twice**
in `hooks/git-guard.replay.sh` — once in `CMDS`, once in `EXPECTED_RELAXED`. A plain string
replacement edits both, leaves the declaration count unchanged, and the run exits 0 — reading as
*"the gate is fine"* when nothing had been mutated. It was caught only by an assertion on the
occurrence count, not by the result looking wrong. Any future mutation of this file must be scoped
to the declaration block **and must assert the block shrank**.

## Carried forward — deliberately not fixed in this round

- `hooks/git-guard.sh`, the `commit)` arm of the remedy `case` inside `refuse()` — it still reads
  "or stage only documentation". Changing it would break the exact-string assertion in
  `hooks/git-guard.test.sh`, and the refusal line directly above it now prints both ledger paths
  in full.
  > **Corrected 2026-09-14 (observability judge, verified).** This entry cited
  > `hooks/git-guard.sh:234`, which is `return 1` in an unrelated helper; the remedy line is ~35
  > lines further down. The number was right when written and died in the 496-commit merge. Anchors
  > here are now **function and case-arm names**, per ADR 0047's own rule — the same rule ADR 0044
  > adopted after every `:NNN` in a card died at once.
  > This is the six-site drift the ADR warns about, arriving inside the change that documented it.
- `docs/features/git-guard-detached-head.md:341` and `:732` quote the refusal message as
  `(CODING_MEMORY.md, coding-memory/*, docs/*.md)` — stale since PR #59, now stale twice over.
  Outside every worker's assigned file set this round.
