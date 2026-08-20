---
phase: review
model_tier: high
branch: fix/statusline-wrap-worktree-followups
---

# statusline — width-aware wrapping and worktree name

Opened session 29 (2026-08-06) on `main` @ `124b504`, at the user's `gate confirmed`.

Separate track from `memsearch-freshness.md`, which stays at `phase: planning` awaiting its
round-2 judges. This file exists so `phase-guard.sh` can tell the two apart: it records this
branch, which is what authorizes source edits here without touching the memsearch gate.

**Runs in an isolated worktree** — `.claude/worktrees/statusline-wrap-worktree`, following the
existing convention. A second Claude session was found live in the shared `~/.claude` checkout,
mid-flight on the memsearch compliance judge. Both halves of this feature are therefore
non-negotiable: never commit from the shared checkout, never stage a path outside this domain.

## Problem

Two independent defects in `statusline-command.sh`, one cosmetic and one informational.

1. **The line truncates.** It renders as a single line and is cut off on a narrow terminal —
   the docs' own warning is that long output "may get truncated or wrap awkwardly". The
   right-hand segments (cumulative tokens, weekly quota) are the first to disappear, and they
   are the ones that exist to be watched.
2. **Worktree sessions are indistinguishable.** Parallel agents run in worktrees by design
   (`rules/core-conduct.md`, "Parallel-Agent Invariants"), and the status line gives no way to
   tell which checkout a session is in. This session hit exactly that hazard: it switched the
   shared checkout onto a feature branch while another session was working in it.

## Measured facts

Established before any code was written; each is a fact about the environment, not an assumption.

| Fact | Evidence |
|---|---|
| Multi-line output is supported | Docs: "each `echo` or `print` statement displays as a separate row." |
| `COLUMNS`/`LINES` are exported to the script | Docs: Claude Code captures stdout, so `tput cols` cannot work; it sets these instead. Requires v2.1.153+. Installed: **2.1.223**. |
| `COLUMNS` reads `0` in a non-interactive shell | Measured directly. `[ -n "$COLUMNS" ]` is the wrong guard — it would wrap every line to nothing. |
| Baseline suite is green | `statusline-command.test.sh` → **50/50 passed** on the unmodified script. |
| Injection tests assert **zero** newlines | They prove data cannot split the line. Wrapping emits newlines by design. |

### The worktree test that looked right and was wrong

Comparing `rev-parse --git-dir` against `--git-common-dir` **false-positives inside any
subdirectory of the main tree**: from `main-repo/sub/dir` they read `/abs/.git` and `../../.git` —
different strings, same tree. Caught by probing before implementing.

The correct test is `[ -f "$(git rev-parse --absolute-git-dir)/gitdir" ]`: a linked worktree's
git-dir contains a `gitdir` file, a main `.git` never does. Verified against five cases:

| Case | Expected | Result |
|---|---|---|
| main worktree, at root | main | ✅ |
| main worktree, in a subdirectory | main | ✅ |
| linked worktree, at root | linked | ✅ |
| linked worktree, deeply nested | linked | ✅ |
| plain repo under a dir literally named `worktrees` | main | ✅ (a `*/worktrees/*` path pattern fails this) |

## Behaviour

```gherkin
Feature: width-aware status line

  Scenario: a wide terminal is unchanged
    Given COLUMNS is 200
    When the status line renders
    Then the output is a single line
    And it is byte-identical to the pre-change output

  Scenario: a narrow terminal wraps at segment boundaries
    Given COLUMNS is 60
    When the status line renders
    Then the output spans more than one line
    And no line's visible width exceeds 60
    And no line is broken in the middle of an ANSI escape sequence

  Scenario: an absent or zero COLUMNS never wraps
    Given COLUMNS is unset, empty, "0", or non-numeric
    When the status line renders
    Then the output is exactly one line

  Scenario: an over-wide single segment is not hard-broken
    Given a segment whose own width exceeds COLUMNS
    When the status line renders
    Then that segment occupies its own line intact

Feature: worktree name

  Scenario: a linked worktree shows its name
    Given the current directory is inside a linked worktree named "feature-alpha"
    When the status line renders
    Then it contains "wt:(feature-alpha)"

  Scenario: the main checkout shows no worktree segment
    Given the current directory is in the main working tree
    When the status line renders
    Then it contains no "wt:(" segment

  Scenario: a worktree name carrying control characters is stripped
    Given a worktree whose directory name contains a control byte
    When the status line renders
    Then the rendered name contains no control characters
```

## Design

- **Width tracking, not width measuring.** Each segment is built as a (text, known-width) pair;
  width accumulates as the segment is assembled. This sidesteps counting ANSI escapes and the
  ambiguous display widths of `➜ ✗ █ ░ Σ ⏱ │` entirely. No locale dependency, no extra forks.
- **Greedy packing** at the existing ` │ ` separator boundaries, never mid-segment.
- **Fail to today's behaviour.** Any doubt about `COLUMNS` → one line, exactly as now.
- **`wt:(name)`** rendered after `git:(branch)`, matching the robbyrussell idiom. Linked
  worktrees only — in the main checkout the existing `dir` segment already says it.
- Name is stripped of control characters **at its source**, per the rule the file's header
  comment already establishes for every externally-sourced value.

### Non-goals

- No change to what the existing segments mean or how they are computed.
- No hard character-level wrapping. Segment granularity only.
- No `LINES`-based vertical clamping.

### Revised after the observability judge (round 1)

The judge found the design's own Gherkin unmet: **the head never wrapped.** It was one
indivisible string, so in this worktree at `COLUMNS=60` it measured 120 cells — and the width
assertion could not catch it, because that case rendered `/tmp`, which is not a repo and
produced a stubby 33-cell head with no branch and no `wt:()`.

Both were fixed rather than exempted. Exempting the head would have defeated the feature: the
head is the longest part of the line and therefore the part that overflows.

- The git prompt's parts are now **separate segments** (`user@host`, directory, `git:(branch)`,
  `wt:(name)`), each carrying its own preceding separator, so one packing loop handles the
  whole line uniformly.
- The **4-row cap was removed.** With the head split, six segments could not fit in four rows,
  and every width from 24 to 52 cells overflowed by sharing the remainder onto the last row.
  No cap is needed: a segment starts a new row only when it does not fit, so rows are already
  bounded by segment count (at most eight).
- The width assertion is **re-pointed at the real linked-worktree fixture**, which produces the
  long head. It was confirmed to fail first (`widest=79>60`).
- Measured after the fix, fuzzing every width from 12 to 200: **at 38 cells and above nothing
  overflows.** Below that only an atomic segment ever does, which is the documented
  never-break-mid-segment case. Below 12, wrapping is off by design.
- `push_segment` takes text and width in **one call**, so the judge's "a segment pushed without
  its width would mis-measure silently" concern is now structurally impossible.

Rationale for reversing the documented "output can never be split across lines" invariant:
**ADR 0018**.

## Tasks

Reopened 2026-08-20 on `fix/statusline-wrap-worktree-followups` (off `main` @ `7fcfd95`) to close
tasks 9-12, which PR #43 shipped without. The original `feat/statusline-wrap-worktree` branch is
gone (merged, deleted); this is a fresh branch for the remainder.

- [x] 1. Write the wrap + worktree tests against the **unmodified** script; confirm they fail.
      Red phase: 4 failures, `widest=83>60` proving the overflow.
- [x] 2. Pin the existing injection tests to a wide `COLUMNS` so `nl=0` stays a real assertion
      rather than being relaxed to accommodate wrapping.
- [x] 3. Implement worktree detection and the `wt:(name)` segment.
- [x] 4. Implement width tracking at each `extras+=` site.
- [x] 5. Replace the join/render block with greedy packing.
- [x] 6. Update the file's header comment — the "Target look" block and the newline rationale,
      which stated that output can never be split across lines.
- [x] 7. Full suite green: **68/68**, against a real linked worktree, not a simulated one.
- [x] 8a. Observability judge, round 1: **risk=low, confidence=high**, with one real defect —
      the head never wrapped and the width test could not catch it. Both fixed above.
- [x] 8b. Observability judge, round 2: **risk=low, confidence=high**. Verified the round-1
      fix with its own long-branch fixtures, widths fuzzed 1–200, and 176 injection
      combinations at wrapping widths the suite does not reach — zero leaks. Follow-ups
      applied: dead `lines_emitted` removed, row bound asserted, ADR's "38 cells" qualified as
      fixture-specific, `wt:()`-is-not-a-safety-mechanism recorded.
- [x] 8c. Observability judge, round 3 (delta): **risk=low, confidence=high**, all dimensions
      pass. Proved the counter deletion behaviour-neutral across 154 paired runs compared
      byte-for-byte including stderr. Found the new row assertion carried two rows of slack and
      demonstrated it with a mutant emitting a spurious blank leading row — 7 rows, passing all
      68 tests. Assertion tightened to the fixture's own segment count; the mutant now fails it.
- [x] 8d. Observability judge, round 4: **risk=low, confidence=high**. Traced the segment count
      through `bash -x` to confirm the tightened bound comes from code structure (six active
      `push_segment` sites) rather than being fitted to observed output, and independently
      rebuilt the mutant to confirm the assertion still fails on it. **PR #43 open.** **Open the PR
      from this worktree** — `judge-guard` matches on `repo` = `basename(show-toplevel)`, which
      is `statusline-wrap-worktree` here and `.claude` from the shared checkout, where it would
      look for the wrong verdict and block. Freshness is strict: the stored `head_sha` must
      equal current HEAD, so any commit after judging forces another round.
- [x] 9. **`statusline-command.falsify.py` fixed — root cause was worse than documented.**
      Re-measured at the start of this task: the harness no longer reported the documented
      count mismatch at all. It hard-errored — `f0902ed: extraction returned a non-script
      (b'')` — because `f0902ed` does not exist in this repository, reachable or unreachable
      (`git fsck --unreachable`, empty; `gh api repos/.../commits/f0902ed`, 422). It was never
      pushed: almost certainly a local commit amended away before this branch's first push on
      2026-07-19, later garbage-collected. Unrecoverable.

      Measuring 925c310 directly (the earliest commit this repo still has, confirmed via
      `git log --diff-filter=A`) showed it is actually the unfixed original the old `f0902ed`
      label described — every Group 2 case fails except the one that passes "for the right
      reason" regardless of stripping. Its old "route-1 fix only" label was wrong; corrected
      in the harness.

      Fixed the deeper design flaw from the same root, per this task's own open question:
      switched from asserting whole-suite pass **counts** to asserting **which named Group 2
      (control-byte injection) cases fail**, scoped to that group only via new
      `@@GROUP2-START@@`/`@@GROUP2-END@@` sentinels in the test file. Group 1 (rendering) grows
      every time an unrelated feature lands and none of those tests existed in these historical
      versions — that's what forced three recalibrations (20→50→66→68). Scoping to Group 2 and
      matching by name is structurally immune to Group 1's growth.

      Falsifiability proven both directions: the harness reports `falsification intact` against
      the real historical shas, and correctly reports `MISMATCH` with a precise expected/actual
      diff when a `EXPECTED` entry is deliberately corrupted (tested, then reverted — see commit).
- [x] 10. **A missed worktree fails into the dangerous reading — fixed with `wt:(?)`.**
      `git_dir=$(git ... rev-parse --absolute-git-dir 2>/dev/null)` can come back empty for
      reasons unrelated to "this is the main checkout" (transient failure, permissions, a git
      bug) while the outer `--is-inside-work-tree` check already confirmed we ARE in a work
      tree. Previously that emptiness was indistinguishable from a real main checkout — both
      rendered no `wt:()` segment at all. Now: `git_dir` empty *despite* being confirmed inside
      a work tree renders `wt:(?)`; `git_dir` resolved with no `gitdir` file (a real main
      checkout) still renders nothing, unchanged.

      TDD: red test first, via a PATH shim that fails only the `rev-parse --absolute-git-dir`
      call and passes every other git invocation through to the real binary (first version of
      the shim had a shell-semantics bug — `PATH=... printf ... | bash "$SCRIPT"` scopes the
      assignment to `printf` alone, not the pipeline; fixed to `export PATH=...` inside the
      subshell). Confirmed the test fails against the unfixed script, then implemented. 69/69.
- [x] 11. **Absurd `COLUMNS` values print bash arithmetic noise to stderr — fixed.** The
      degenerate-value guard rejected non-digit and non-positive strings but never bounded
      digit COUNT, so a value past bash's signed 64-bit ceiling reached `[ "$COLUMNS" -gt 0 ]`
      unfiltered and printed `integer expression expected` to stderr. Fixed by rejecting
      16+-digit strings in the same case pattern, before either comparison runs.

      One dead end during verification, recorded because it cost real time: `bash`'s own
      `checkwinsize` startup behavior *also* prints `number truncated after 19 digits` for an
      absurd `COLUMNS` in the environment — but only when the enclosing shell is interactive.
      Confirmed by reproducing with a nested non-interactive script (`bash outer.sh` invoking
      `bash statusline-command.sh`, matching how Claude Code actually runs this script): the
      bash-startup noise disappears entirely, and only the script's own `[: ... integer
      expression expected` error remained on the unfixed blob. Verified the fix against that
      same non-interactive harness, not the interactive shell that showed the unrelated noise.
- [x] 12. **The row assertion's mutation-sensitivity is environment-dependent — fixed.** Pinned
      `whoami`/`hostname` behind a `PATH` shim in the row-bound fixture, returning fixed
      `fixture-user`/`fixture-host-name` values instead of the real machine's — same technique
      as the judge used to measure both sides, and the same one used for task 10's git shim.
      Segment 0's width no longer depends on who or where the suite runs, so the off-by-one
      mutant's detectability doesn't either.

      Proved it matters, not just changed it: temporarily reintroduced the actual mutant
      (dropped `[ $i -gt 0 ]`), confirmed the shimmed assertion fails correctly
      (`rows=7>6`), then reverted. Real script still passes (`rows=6<=6`) — segment 0 always
      opens line 1 regardless of its width, so widening the fixture's user/host changes nothing
      about correct behavior, only the mutant's visibility.
