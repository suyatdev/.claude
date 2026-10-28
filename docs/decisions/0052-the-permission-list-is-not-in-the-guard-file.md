# 0052 — The permission list is not in the guard file

- **Status:** Accepted (2026-10-28). This record **answers open question §9.2** of
  `docs/superpowers/specs/2026-09-20-guard-loosening-approval-design.md` — task 1 on
  `docs/features/guard-loosening-approval.md`. The answer lands here rather than in the spec because
  no design content in that spec is edited under `phase: implementation`; the spec carries a
  status-only pointer to this number, the same treatment task 0 received in commit `74aa218`.
- **Context:** the three guards the feature watches — `hooks/secret-command-guard.sh`,
  `hooks/git-guard.sh`, `hooks/worktree-guard.sh` — plus the eleven other files their permission
  data actually lives in (table below).
- **Note on the number:** `0052` was checked free on 2026-10-28 by listing `docs/decisions/` across
  **all 43 remote heads**, not just `origin/main`; the highest found anywhere was `0051`. Per ADR
  0050's lesson, re-check at merge time.
- **Provenance of the claims below.** Measured against `origin/main`, which was first confirmed
  byte-identical to the live primary checkout (`$HOME/.claude/hooks/`) for all three guards — so
  `origin/main` is both the comparison baseline the feature uses and the code that actually runs.
  Three subagents built and ran one extractor per guard. **Everything in "What I verified directly"
  I re-opened and re-ran myself. The entry counts, the falsification diffs and finding M8 are the
  subagents' measurements, relayed, not independently reproduced** — they are labelled as such.

## Context

The design made two assumptions, both stated in §5.1 and §5.2, and measurement falsified both.

The first: the watcher "fires **only** when the commit stages one of the three watched guard files."
The second: once extraction succeeds there are two outcomes — loosened, so prompt; or not loosened,
so pass silently.

## Decision 1 — the watch set is fourteen files, not three

| File | Holds | Guard(s) |
|---|---|---|
| `hooks/lib/classify-secret-command.py` | all 8 secret-path patterns, the env-dump regex, the `.env` exemption, the case-fold flag | secret |
| `hooks/secret-command-guard.sh` | no list; the fail-open exits and the exit-2/exit-4 dispatch | secret |
| `hooks/lib/secret_approval.py` | the hatch value allowlist, the policy refusals | secret |
| `hooks/git-guard.sh` | the `main` commit allowlist (`docs/*.md`, the two judge ledgers), branch checks, sequencer stand-down | git |
| `hooks/lib/git_quiet_class.py` | `READ_SUBCOMMANDS` — the quiet-mode read-only allowlist (ADR 0051) | git |
| `hooks/lib/git_guard_quiet.py` | blocking facts, protected branches, the `-C` folder checks | git |
| `hooks/lib/classify-git-command.py` | commit/push/force flag tables; Arm D HEAD-move subcommands | git, worktree |
| `hooks/worktree-guard.sh` | the Arm A path-exemption list, mode logic, preconditions | worktree |
| `hooks/lib/worktree_guard_bash_arms.sh` | Arm B2 and Arm D logic, the refusal-fact loop | worktree |
| `hooks/lib/worktree_guard_liveness.sh` | the layer-2 liveness check | worktree |
| `hooks/reference-transaction` | layer 2 — gated ref, backend, bypass | worktree |
| `hooks/reference-transaction.mode` | layer 2 mode switch, independent of layer 1 | worktree |
| `hooks/lib/shell_segments.py` | `WRAPPERS` and the lexer — read by **eight** guards | all three |
| `settings.json` | `env.WORKTREE_GUARD_MODE`; the registrations that decide whether a guard runs at all | all three |

**Why this is the load-bearing finding.** For `secret-command-guard.sh` the guard file contains
**zero** permission entries. All eight patterns are in `classify-secret-command.py:137`
(`DOTFILE_PATTERNS`). The only mentions of a secret path inside the `.sh` are four **comments**, at
lines 6, 55, 60 and 61. A watcher keyed on the three guard **filenames**, exactly as §5.1 words it,
would see a guard file staged, find no list to compare, and allow the commit. That is a silent
fail **open** — the one direction §7's contract forbids, and indistinguishable from the feature
being switched off.

## Decision 2 — three outcomes, not two

Add a third state: **CHANGED, DIRECTION UNKNOWN**, and make it prompt.

Direction is derivable only when a **whole entry** is added to or removed from a recognised list.
All three extractors converged on this independently. Everything below changes the extraction but
carries no direction, so under §7 it must prompt:

- a regex narrowed or widened in place (a `$` anchor dropped), which reads as one line removed and
  one added inside the same list;
- a case-fold added or removed (`FOLD_FLAGS = re.IGNORECASE` → `= 0`);
- a fail-closed branch flipped to fail-open (`sys.exit(1)` → `sys.exit(0)`; `exit 2` → `exit 0`);
- an exemption written as an `if` inside a function rather than held in any list;
- a precondition call deleted (`require_home`);
- a list rebuilt by comprehension or expansion, which erases the entries entirely;
- any edit to a shared lexer or classifier function.

**Consequence, stated plainly: §5.2's promise that "tightening passes silently, only loosening
prompts" holds for entry-level list edits and nothing else.** Refactors and some genuine tightenings
will prompt. That cost was not priced in the spec and is accepted deliberately here, because the
alternative — guessing a direction — fails permissively.

**Decision 2a — how the third state prompts (user decision, Mark, 2026-10-28).** It **blocks**, so
§7's fail-closed contract is untouched, but it carries its **own distinct message** saying the
change could not be classified — it must **not** claim a loosening it has not established. The two
alternatives were put and declined: reusing the confirmed-loosening message for everything (*"a
prompt that is often wrong is a prompt you stop reading"* — it would report a loosening for a
variable rename), and prompting only on confirmed loosenings while logging the rest (declined
because the unclassifiable set contains precisely the subtle weakenings — a dropped case-fold, an
anchor removed — that human review also misses, so it leaves the hole where it hurts most).
Implementations must therefore carry **two** refusal messages, not one, and the suite must
discriminate between them.

## Decision 3 — parse per file type; never diff text

- **Python:** parse with `ast`. Module-level constants emit one line per element, so quote style and
  element order cannot matter. Function bodies become docstring-stripped digests.
- **Shell:** a quote-aware lexer that strips comments and message prose. Each `case` arm and
  `for … in` word list becomes an entry; function bodies become digests with already-extracted list
  lines excluded.
- **`settings.json`:** the `WORKTREE_*` env keys and each guard registration.
- **The git file mode, alongside the blob.** A `100755` → `100644` flip leaves file content
  byte-identical, and a `100644` hook cannot start. No content diff can see it.

Fail closed on a parse error, a missing expected name, or a renamed canary list.

## Decision 4 — the direction tables are hand-assigned and need one human review

Every extractor assigns ALLOW/BLOCK from a **hand-written table**, not from the code. That mapping
is the feature's trust root and has never been reviewed by anyone. Record it as a required review
step before the watcher ships, not as an assumption. A mis-tagged list fails in the permissive
direction.

## Measured results (relayed from the three reads, not re-reproduced)

| Guard | Files | Entries | Add allow | Remove block | Cosmetic edit |
|---|---|---|---|---|---|
| secret-command-guard | 5 | 34 in the classifier | changes, loosening | changes, loosening | identical |
| git-guard | 5 | 318, 0 unclassified | LOOSEN | LOOSEN | identical, 2 deliberate exceptions |
| worktree-guard | 8 + git mode | 351 (82 ALLOW / 115 BLOCK / 154 REVIEW) | changes, loosening | changes, tightening | identical, 8 of 8 |

The git-guard read also checked **behaviour**, not only extraction text: in a scratch repo on `main`
with a third judge ledger staged, the guard exited 2 before the mutation and 0 after.

## Honest limits, measured rather than assumed

- **An unbalanced quote did not fail closed (M8).** A stray `"` paired with a later quote; `bash -n`
  accepted the result as a different but valid program; the extractor exited 0 and silently dropped
  roughly 13 scalar entries plus the `exit 2` in `hard_deny`. The diff still read as a loosening, so
  the gate would have held — by luck, not by design. **The quote-balance check is a heuristic.**
- **Statement reordering is invisible.** Moving `require_home` above the exemption check — which
  reverses task 17 on the worktree-guard card — left the extraction output unchanged, because
  entries are a set and digests are sorted.
- **Shared files cross-talk.** `shell_segments.py` is read by eight guards and
  `classify-git-command.py` by two, so a change in either prompts for reasons unrelated to the guard
  being edited.
- **Three secret-guard claims are read from code, not run.** The subagent's own probe commands
  contained `.env.local` and were blocked by `secret-command-guard` itself; it did not reach for
  `SECRET_EXEMPT` to get around it. Correct call, and the gap is recorded rather than papered over.

## What no diff of tracked content can reach

- Flipping `env.WORKTREE_GUARD_MODE` from `deny` to `log` disarms worktree-guard entirely with no
  list change. In reach **only** because `settings.json` is in the watch set.
- **Layer 2 runs from outside the repository.** `core.hooksPath` is
  `/Users/marksuyat/.config/git/hooks` (measured 2026-10-28), and `hooks/install-layer2.sh` copies
  the hook there. An edit to the tracked file is inert until the installer re-runs, and unsetting
  `core.hooksPath` disarms layer 2 with no file change at all.
- `settings.local.json`, a project-level `.claude/settings.json`, and the environment —
  `WORKTREE_EXEMPT`, `WORKTREE_GUARD_LIB`.
- Runtime state: approval records, and the quiet-mode session flag written by `git-quiet-toggle.sh`.

These confirm §1.1: this gates a loosening being **proposed**. It is a momentum guardrail, and PR
review remains the last line.

## Three pre-existing defects found on the way, deliberately not fixed here

Each is its own task, per `rules/core-conduct.md` — a drive-by fix is a separate change.

1. **`GLOBAL_REDIRECT` is inert.** At `classify-git-command.py:281-283` the "known to redirect"
   branch and the "unrecognised" branch return byte-identical tuples, so membership decides nothing.
   A watcher will prompt on edits to a list that cannot loosen anything.
2. **A comment contradicts its code.** `git-guard.sh:327` states `PRINTS_AND_EXITS` is "message
   selection ONLY, never a decision input"; `:383-386` runs `exit 2` off it.
3. **A duplicated exemption list.** `phase-guard.sh:309-311` is byte-identical to
   `worktree-guard.sh:676-678`. Two copies of one rule can drift.

## What I verified directly

Re-opened and re-run by this session, not relayed: `origin/main` is byte-identical to the live
primary checkout for all three guards; `DOTFILE_PATTERNS` is at `classify-secret-command.py:137` and
the four `.sh` mentions are comments; `READ_SUBCOMMANDS` holds 14 entries at `git_quiet_class.py:38`;
the `PRINTS_AND_EXITS` comment/code contradiction; the identical `GLOBAL_REDIRECT` return tuples;
all fourteen files exist on `origin/main` with the modes recorded; `core.hooksPath`; the
`phase-guard` duplicate across all three lines; `0052` free across 43 remote heads;
`feat/git-guard-quiet` fully merged into `origin/main`.

## Consequences

- §5.1 must be re-read as "stages any file in the watch set", and the set is data the watcher owns.
- The feature cannot promise silence on tightenings. It can promise it on list-entry tightenings.
- Tasks 4 and 5 inherit a fourth requirement beyond the spec's three: extract the git **file mode**
  alongside the blob.
- Decision 4's direction-table review is a gate before the watcher ships.
