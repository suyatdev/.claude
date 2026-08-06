# Observability verdict — `fix/replay-harness-base-pin` (implementation, round 5)

> **Round 5 — implementation stage, GATING.** This is the verdict `judge-guard.sh` reads before
> `gh pr create`. Rounds 1–4 are preserved in
> `coding-memory/observability-judge/2026-08-05-fix-replay-harness-base-pin.md`; rounds 1–2
> (implementation, at `e86ddb5`/`a5ee297`) are **void** — revision 10 added implementation work after
> them. This round supersedes them.

- **repo:** `.claude`
- **branch:** `fix/replay-harness-base-pin`
- **head_sha:** `f6242c27dfa38f984ec81827986e308176720c91`
- **stage:** implementation
- **ts (UTC):** 2026-08-06T01:07:00Z
- **base:** `main` @ `56f1dfd` — HEAD is 12 ahead; working tree clean (`git status --porcelain` empty)
- **change under review:** task 11 — commits `797dbc4` (dead `rm -f` deleted) and `d5151da`
  (`require_on_disk` wired into the worktree branch); `f6242c2` is docs-only
- **spec:** `docs/features/replay-harness-base-pin.md`, task 11 (`:797`)
- **ADR:** `docs/decisions/0016-differential-harness-must-prove-difference.md` (amended, `:37-56`)
- **measurement run by the judge:** one `/tmp` clone, five full matrix runs plus four refusal runs.
  The user's real worktree was never modified.

---

## What was changed

The repo has a comparison tool (`hooks/git-guard.replay.sh`). You point it at two versions of the
commit guard, it runs 63 commands in 6 different repo states against both, and it tells you every
place the old one said "blocked" and the new one says "allowed". That report is the evidence used to
claim a guard change never made things weaker.

The tool already refused to run if the *old* side's files were missing or empty. It did **not** check
the *new* side when you run it the normal way (pointing at your working copy). So if your working
copy was missing a file the guard needs, the tool happily ran the whole 378-command matrix against a
guard that couldn't actually start, and printed a clean-looking scorecard with **zero** problems
found — because a guard that can't start refuses everything, and "refuses everything" scores zero
relaxations by definition.

Two commits fixed it:

1. `797dbc4` deletes a dead `rm -f` line. It never did anything (it only ever ran against a throwaway
   temp directory), but the very next commit was about to point that code path at your **real**
   repository, where the same line would have deleted `hooks/lib/*.py` off your disk. Removed first,
   alone, with the reference measurement re-run to prove nothing moved.
2. `d5151da` adds `require_on_disk` — a read-only twin of the existing check — and wires it into the
   default working-copy path, before the "are these two actually different programs?" comparison.

## Does it do what you wanted?

**Yes, and it closes slightly more than it claims.** I did not take the summary's word for it; I
cloned the repo to `/tmp` and ran it.

| what I ran | before the fix | after the fix |
|---|---|---|
| working copy with `hooks/lib/` deleted | `260 identical, 118 stricter, **0 relaxed**`, **exit 0** — the silent false pass | `REPLAY ERROR: … does not contain hooks/lib/classify-git-command.py`, **exit 1** |
| working copy with a 0-byte `hooks/lib/shell_segments.py` | (same false-pass shape) | `REPLAY ERROR: … has an empty hooks/lib/shell_segments.py`, exit 1 |
| working copy with a **0-byte `hooks/git-guard.sh`** | `247 identical, 0 stricter, **131 relaxed** (58 commands)` — a loud, entirely fictional result | `REPLAY ERROR: … has an empty hooks/git-guard.sh`, exit 1 |
| healthy working copy vs a differing base (`8099d0a`) | `247/130/1` | `247/130/1` — **unchanged, no over-fire** |
| healthy working copy vs `main` | vacuity refusal | vacuity refusal (correct — this branch doesn't touch `git-guard.sh`) |
| `bash hooks/git-guard.test.sh` | — | **77 passed, 0 failed, exit 0** (run by me at this HEAD) |
| `shellcheck -S warning hooks/git-guard.replay.sh` | — | clean, no output |

The third row is the notable one: the 0-byte-guard case was flagged as an **open gap with no
falsifier** by my own round-4 read. The implementation closes it (the same `require_on_disk` call
covers the guard file itself), even though no scenario in A–O is named for it. The ordering claim is
also real — the check sits at `replay.sh:90-94`, the vacuity comparison at `:130`.

The blast radius matches the disclosure exactly. `git diff main HEAD -- hooks/git-guard.sh
hooks/lib/ settings.json rules/ skills/` is **empty**. The live guard was not touched.

## What could go wrong / what I'm unsure about

Nothing here is a `fail`. Three honest concerns, in order of how much they'd bite you:

1. **The green scorecard can still lie, just not this way.** The check verifies files are *present and
   non-empty*. It cannot see a file that is present, non-empty, and broken. If `python3` isn't on
   `PATH`, or a helper has a syntax error, or the candidate guard legitimately blocks everything, the
   guard fails closed on all 378 pairs, `relaxed` is `0` by construction, and you get the same
   reassuring "0 relaxed, exit 0". The ADR says this plainly — *"the example closes; the limit does
   not"* — which is the right way to write it, but it means **`0 relaxed` is still not by itself proof
   of anything**. (I infer this from the fail-closed behaviour the test suite pins — "no classifier,
   commit → FAIL CLOSED exit 2" — not from a `PATH`-stripped run I performed.)
2. **The mode people actually run still reports less than the other mode.** I ran the same
   self-contained-guard case both ways: as a rev candidate it prints
   `NOTE: the candidate at e3b09ba… is a self-contained guard …`; as the default worktree candidate it
   prints **no NOTE at all**, though both produce the identical `213/137/28` matrix. The new code
   duplicated the validation but not the announcement. Harmless to the numbers, but this branch exists
   because the harness didn't say what it compared — and the default mode still says less than the
   other one.
3. **Small duplication invites future drift.** `require_on_disk` (`:55-62`) repeats
   `extract_required`'s two error messages verbatim, and the `grep -q 'lib/'` test at `:91` repeats
   the one at `:68`. Edit one message and the two sides drift apart silently. Also, that `grep 'lib/'`
   remains a comment-blind heuristic — the spec correctly records that this change gives it a **third**
   dependent (`:1035-1036`).

Unchanged and correctly disclosed, not introduced here: the harness exits `0` even when it *does*
report relaxations (so it is unsafe as a CI pass/fail step); any exit code outside `{0,2}` is still
tallied as agreement; invoking with no arguments still dies with a raw bash `$1: unbound variable`
instead of the named error. There is no test-suite sibling for the harness — its correctness rests on
the Gherkin scenarios being re-run by hand, so ADR 0016 is the only thing standing between this defect
class and a fourth recurrence.

## What I'd double-check before merging

- Nothing blocking. The dimension I'd watch is **restore cost**, not correctness: the feature file is
  now **1286 lines** (it was 1112 when I flagged it in round 4) and `CODING_MEMORY.md` is 2476 lines,
  and both are read on every restore.
- If you want the last cheap win, add the self-contained NOTE to the worktree branch so both modes
  narrate identically (concern 2). It's three lines and it's the same "say what you compared"
  principle the branch is named after. Not a merge blocker.
- Confirm you're content that the 0-byte-worktree-guard behaviour ships **unpinned by a named
  scenario** — it works today (I measured it), but nothing in A–O will catch it if it regresses.

---

## Dimensions

| dimension | verdict | why |
|---|---|---|
| `intent` | **pass** | Task 11 as specified: worktree candidate validated, read-only, before the vacuity comparison. Verified by execution, not by reading. |
| `execution` | **pass** | Red reproduced exactly (`260/118/0`, exit 0); green refuses with the right message and exit 1; no over-fire on a healthy run; `git-guard.test.sh` 77/0 run by the judge at this HEAD; `shellcheck` clean. |
| `trajectory` | **pass** | Deliberate, not lucky: dead `rm -f` removed in isolation *before* the code path was aimed at the real repo, with a reference row re-measured unchanged; ordering vs. the vacuity check reasoned and correct; red measured before green. Closes round-4's unfixed 0-byte-guard gap as a by-product. |
| `regression` | **pass** | `hooks/git-guard.sh`, `hooks/lib/`, `settings.json`, `rules/`, `skills/` all untouched (empty diff). Healthy-path matrix byte-identical to rev-candidate mode. Test suite unaffected. |
| `context_budget` | **concern** | No always-on surface changed (no `rules/`, `skills/`, `CLAUDE.md`). But the mandatory-on-restore feature file grew 1112 → 1286 lines and `CODING_MEMORY.md` is 2476 lines; the restore budget keeps climbing round over round. |
| `traceability` | **concern** | ADR amended, fifteen-scenario table recorded, commit messages carry measured figures — strong. Two gaps: the default worktree mode prints no self-contained NOTE where rev mode does (verified both ways); the empty-worktree-guard refusal ships with no named scenario. |
| `success_masking` | **concern** | Explicitly and correctly disclosed ("the example closes; the limit does not"). Residual: any fail-closed candidate still scores `0 relaxed` exit 0; the harness exits 0 while reporting relaxations. Pre-existing, none introduced. |
| `intent_drift` | **pass** | Diff is exactly the disclosed set; the two one-line provenance notes in adjacent feature files are from an earlier task on this branch and disclosed. No new dependencies. |
| `checkpoint` | **pass** | Two small commits, dead-code deletion isolated specifically to keep the behaviour-changing commit a clean revert point. Working tree clean. `Doc-Exempt` used as sanctioned, with a stated reason. |
| `audit_trail` | **pass** | ADR 0016 amended in place (legitimate — it has never existed on `main`), feature file, `CODING_MEMORY.md`, and commit messages all attributable and consistent. Carried wart: rounds 1–2's `292/86/0` still stands in the append-only JSONL; corrected in the spec and in this line's concerns rather than rewritten, which is the right call. |

**risk:** low **confidence:** high

## Concerns

- Residual false pass: any candidate that fails closed on every command still yields `0 relaxed`, exit 0 (`python3` off `PATH`, a present-but-broken helper, a legitimately block-everything guard). Disclosed in ADR 0016; the file-presence check cannot see it.
- Harness still exits 0 while reporting relaxations — unsafe to wire into CI as a pass/fail step; unchanged and disclosed.
- Default `worktree` mode prints no self-contained-guard NOTE where rev-candidate mode does; judge measured both at `213/137/28` — reporting asymmetry only, but in the mode people actually run.
- The 0-byte worktree `git-guard.sh` case is now refused (judge measured pre-fix `247/0/131`, post-fix exit 1), closing round 4's flagged gap — but no named scenario in A–O pins it.
- `require_on_disk` duplicates `extract_required`'s two error strings verbatim, and `grep -q 'lib/'` is duplicated at `:68` and `:91` — silent drift risk on a future message edit.
- The `grep -q 'lib/'` membership test remains comment-blind; this change adds a third dependent, recorded at spec `:1035-1036`.
- No test-suite sibling for the harness (stated non-goal): correctness rests on hand-run Gherkin scenarios, with ADR 0016 as the only guard against a fourth recurrence of this defect class.
- Mandatory-on-restore feature file grew 1112 → 1286 lines; `CODING_MEMORY.md` at 2476 lines.
- Invoking with no arguments still dies with a raw bash `$1: unbound variable` instead of the named REPLAY ERROR — pre-existing, unchanged.
- Correction carried forward: rounds 1–2's `292/86/0` does not reproduce (`260/118/0` is the true figure, re-confirmed by this judge); it remains in the append-only JSONL and is corrected in the spec, the compliance record, and here.
