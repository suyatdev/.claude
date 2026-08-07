# 0018 — The status line may span multiple rows

Status: accepted
Date: 2026-08-06
Scope: `statusline-command.sh`, `statusline-command.test.sh`

## Context

`statusline-command.sh` rendered exactly one line, and its header comment said so as a
*safety* property, not merely a layout one. The rationale for using `printf '%s'` over
`printf '%b'`, and for stripping control bytes from every externally-sourced value, was
written in those terms:

> a directory or model name containing a literal `\x1b` or `\n` would inject a live terminal
> escape or **split the status line across two lines**.

So "the output is one line" was load-bearing in the injection argument. The test suite
encoded it directly: the injection cases assert the rendered output contains **zero
newlines**, which is how they prove a hostile payload cannot split the line.

The line also truncated. On a narrow terminal the rightmost segments — cumulative tokens and
the weekly quota, the two that exist to be watched — were the first to disappear.

Fixing the truncation requires emitting newlines, which directly contradicts the invariant
the security argument was resting on.

## Decision

**The status line may span multiple rows, and the invariant is restated rather than dropped.**

The old invariant conflated two things. The replacement separates them:

- **Structural newlines** are emitted by the packing loop, at a separator it chose, from
  data it computed. These are now permitted and are the feature.
- **Data-borne newlines** — a newline arriving inside a directory name, a model name, or any
  other external value — remain impossible. Nothing about that changed; the stripping that
  prevented them is untouched.

"Data cannot split the line" is exactly as true as it was. "The output is one line" is not,
and was never the property actually worth having.

The injection tests are therefore **pinned to a wide `COLUMNS`** rather than relaxed. At a
width where no structural break can occur, any newline in the output must be data-borne, so
`nl=0` isolates the property more sharply than it did before wrapping existed. Relaxing them
to tolerate newlines would have retired a security assertion in order to pass a cosmetic
feature — the failure mode ADR 0016 exists to forbid.

## Consequences

- A break is only ever taken **at a separator**. The packing loop never inspects a segment's
  interior and does no index arithmetic on one, so there is no position at which it could cut
  an escape sequence in half. Verified by fuzzing every width from 1 to 160 cells: zero
  dangling escapes.
- **The git prompt is no longer atomic.** It was originally one indivisible string, which made
  it the one thing that could not wrap — and it is the longest part of the line: in a worktree
  it carries `user@host`, the directory, the branch and the worktree name, measuring 120 cells
  against a 60-cell terminal. Its parts are now separate segments.
- **There is no maximum row count.** An earlier draft capped it at four rows; once the git
  prompt was split, six segments could not fit in four rows and every width from 24 to 52
  cells overflowed. The count needs no cap because it is already bounded — a segment starts a
  new row only when it does not fit, so rows can never exceed segments, at most eight.
- **A single segment wider than the terminal still overflows**, intentionally. Breaking it is
  what the escape-sequence guarantee forbids. Measured: at 38 cells and above nothing
  overflows; below that, only an atomic segment ever does.
- Widths are **tracked as segments are built, not measured afterwards**. Measuring would mean
  stripping colour codes back out and then deciding how many cells a glyph like `⏱` occupies —
  unanswerable without a character-width table, in a script that re-renders on every message.
  Every glyph counts as one cell; a terminal drawing one wider overflows by that much.
- `COLUMNS` is the only usable signal, because Claude Code captures stdout and `tput`
  therefore reads a pipe. It is not trustworthy alone — a non-interactive shell reports `0`,
  measured — so anything that is not a positive integer disables wrapping and restores the
  previous single-line output. A bad width costs the feature, never the line.

## Alternatives rejected

- **Exempt the head from wrapping** (keep the git prompt atomic, note it as a non-goal). This
  was the cheaper reading of "never break mid-segment", but it defeats the purpose: the head
  is the part that overflows, so the feature would not solve the problem it was built for.
- **Hard character-level wrapping.** Would break mid-escape and produce garbage.
- **Relax the injection tests to tolerate newlines.** Rejected under ADR 0016 — it converts a
  live assertion into one that cannot fail.
