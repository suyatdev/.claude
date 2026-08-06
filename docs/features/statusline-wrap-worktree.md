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
- No `LINES`-based vertical clamping beyond a fixed maximum line count.

## Tasks

- [ ] 1. Write the wrap + worktree tests against the **unmodified** script; confirm they fail.
- [ ] 2. Pin the existing injection tests to a wide `COLUMNS` so `nl=0` stays a real assertion
      rather than being relaxed to accommodate wrapping.
- [ ] 3. Implement worktree detection and the `wt:(name)` segment (`statusline-command.sh:151-169`).
- [ ] 4. Implement width tracking at each `extras+=` site (`:542,544,581,586,609`).
- [ ] 5. Replace the join/render block with greedy packing (`:613-630`).
- [ ] 6. Update the file's header comment — the "Target look" block and the newline rationale,
      which currently states that output can never be split across lines.
- [ ] 7. Full suite green: 50 existing + new. Verify in a real linked worktree, not a simulated one.
- [ ] 8. Observability judge, then PR.
