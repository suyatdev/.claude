---
phase: implementation
model_tier: high
branch: feat/statusline-wrap-worktree
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

- [x] 1. Write the wrap + worktree tests against the **unmodified** script; confirm they fail.
      Red phase: 4 failures, `widest=83>60` proving the overflow.
- [x] 2. Pin the existing injection tests to a wide `COLUMNS` so `nl=0` stays a real assertion
      rather than being relaxed to accommodate wrapping.
- [x] 3. Implement worktree detection and the `wt:(name)` segment.
- [x] 4. Implement width tracking at each `extras+=` site.
- [x] 5. Replace the join/render block with greedy packing.
- [x] 6. Update the file's header comment — the "Target look" block and the newline rationale,
      which stated that output can never be split across lines.
- [x] 7. Full suite green: **66/66**, against a real linked worktree, not a simulated one.
- [x] 8a. Observability judge, round 1: **risk=low, confidence=high**, with one real defect —
      the head never wrapped and the width test could not catch it. Both fixed above.
- [ ] 8b. Observability judge, round 2 (a fresh verdict must match HEAD or `judge-guard`
      blocks the PR), then PR. **Open it from this worktree** — `judge-guard` derives the repo
      as `basename(show-toplevel)`, which is `statusline-wrap-worktree` here and `.claude`
      from the shared checkout, where it would look for the wrong verdict and block.
- [ ] 9. **`statusline-command.falsify.py` reports `FALSIFICATION BROKEN` — pre-existing.**
      Verified at HEAD *before* any change here: `f0902ed` scores 8/50 against `want 9`, and
      `925c310` scores 9/50 against `want 10`. The harness runs the current suite against five
      historical script versions and asserts exact pass counts, so every added test shifts all
      five; the counts were written when the suite held 20 cases and it held 50 by the time this
      branch opened. This branch takes it to 66 and moves them again.

      **Deliberately not "fixed" here.** Rewriting `EXPECTED` to match what is observed would
      turn a falsification harness into a rubber stamp, and the two mismatches that predate this
      branch are a real signal nobody has read yet. Needs its own task: decide whether the
      harness should assert counts at all, or assert *which* named cases fail per version — the
      latter survives adding tests, which is the whole reason it keeps going stale.

      **Owed by 2026-08-20.** A permanently-broken harness stops being read, which is the
      failure mode ADR 0016 was written about. The cost of leaving it: this diff merges with
      no differential coverage at all.
- [ ] 10. **A missed worktree fails into the dangerous reading.** Absence of `wt:()` is
      *defined* as "you are in the main checkout", so a detector that silently broke would look
      identical to the state this feature exists to warn about — and given the motivating
      incident (a session switching the shared checkout's branch while another worked in it),
      that is the worst direction to fail in. Raised by the judge; not fixed here because the
      fix is a design question, not a patch: it needs a distinguishable "unknown" rendering,
      which is a change to what the segment *means*, and that was an explicit non-goal of this
      branch.
