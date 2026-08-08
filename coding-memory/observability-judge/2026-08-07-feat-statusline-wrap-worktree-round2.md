# Observability verdict — `feat/statusline-wrap-worktree` @ `66cb17e` (round 2)

- **Stage:** implementation (gates the PR)
- **Repo:** `statusline-wrap-worktree` (isolated worktree of `~/.claude`)
- **Base:** `29ac070` (docs-only) / merge-base with `main` = `124b504`
- **Judged:** 2026-08-07T03:54:57Z
- **Round 1:** `dbf1bbc` — risk=low, confidence=high, one real defect
- **Risk:** low · **Confidence:** high

> Filed with a `-round2` suffix rather than overwriting
> `2026-08-07-feat-statusline-wrap-worktree.md`. The round-1 verdict is the evidence this round
> is judged against; clobbering it would destroy the audit trail this judge exists to keep.
> Matches existing precedent in this directory (`…-round2.md`, `…-round3.md`).

---

## What was changed

Round 1 found one real defect: the status line's **head** — the `➜ user@host dir git:(branch)
wt:(name)` part — was built as one indivisible string and therefore never wrapped. In this very
worktree at a 60-column terminal it measured **120 cells**, twice the terminal. The feature's own
spec promised "no line exceeds COLUMNS", and that promise was false for the longest part of the
line.

This round fixes it. Think of the status line as a shelf you're packing books onto. Previously the
first "book" was actually four books glued together, so it never fit and always hung off the edge.
Now they're four separate books, and the same packing rule applies to every book on the shelf:

1. **The head is split into four segments** (`user@host`, directory, `git:(branch)`, `wt:(name)`),
   each carrying its own preceding separator, so one loop packs the whole line.
2. **The 4-row cap was removed.** With six-to-eight books instead of four, a 4-shelf limit meant
   the leftovers got stacked onto the last shelf — which overflowed. The cap was *causing* the very
   bug it was meant to bound.
3. **`push_segment` now takes text and width in one call**, so a segment can no longer be added
   without its width (round 1's lockstep concern, now structurally impossible).
4. **The width test is re-pointed** at a real linked-worktree fixture — the shape that actually
   overflows. Round 1's version rendered `/tmp`, which isn't a repo, so it tested the one shape
   that could never fail.
5. **ADR 0018** records the reversal of the old "output is never split across lines" invariant,
   which had been load-bearing in the security argument.

## Does it do what you wanted?

**Yes.** I verified the claims myself rather than reading the report, and the ones I tried hardest
to break held up.

- **Test suite: 67/67, run by me.**
- **The round-1 defect is genuinely fixed.** Same payload, same worktree, `COLUMNS=60`: the old
  commit `dbf1bbc` emits a 122-cell first row; `66cb17e` emits 4 rows of 54/37/29/46. Nothing over
  60.
- **I could not find a payload that overflows except the documented one.** I built my own git
  fixtures — a main repo, a normal linked worktree, and one with a deliberately long branch *and*
  directory name — and fuzzed **every width from 1 to 200** against all three. Every single
  overflow was one atomic segment sitting alone on its own row, which is the case the design
  explicitly refuses to break. Zero mid-segment cuts.
- **The escape-sequence guarantee still holds, including where the suite doesn't test it.** The
  suite pins its injection cases at `COLUMNS=400`, so injection × wrapping is untested there. I
  tested it: 8 hostile payloads (raw `ESC[`, embedded newline, carriage return, OSC title-set,
  `ESC[2K` erase, BEL, tab, mixed) × 11 widths from 12 to 400 × 2 injection routes (model name and
  directory) = **176 combinations, zero leaked control bytes**. The reason it holds is structural:
  the loop only concatenates whole pre-built strings and only ever breaks *between* them. Splitting
  the head added four more strings to that list; it added no index arithmetic, so it added no place
  a cut could land.
- **The "at most eight rows" bound is real.** I counted the segment sites: 4 git-side + 4
  Claude-side = 8, and a segment only starts a new row when it doesn't fit. Measured worst case in
  the real worktree: 6 rows at 30–40 columns, 3 rows at 80.
- **`shellcheck -S style` is clean.** Degenerate `COLUMNS` (`0`, `-1`, `abc`, `+5`, `007`, empty,
  absent) all fall back to a single line.

**On removing the cap — you asked me to argue the other side.** The removal is correct, but the
ADR's reason isn't quite the strongest one. "Rows are already bounded at eight" answers *is it
unbounded?*, not *is eight rows acceptable?* The real argument is sharper: a cap can only be
implemented two ways — overflow the last row (what the old one did, i.e. the original bug) or drop
segments (i.e. truncation, the bug this feature exists to fix). Both are the defect. So no cap.

That said, the honest counter stands: at 40 columns this eats **6 of 24 rows**, a quarter of a
split pane, redrawn on every message. That is a worse *look* than a truncated line, even though it
is better *behaviour*. And nobody has verified what Claude Code actually does with an 8-row status
line — if the harness reserves a fixed region and clips, it clips the trailing rows, which after
packing are exactly the token count and quota clock the feature exists to preserve. That would
reintroduce the original defect through a new mechanism, invisibly. I can't test that from here.

## What could go wrong / what I'm unsure about

- **Nothing tests the row count now.** The cap was the only bound and it's gone; "at most eight"
  lives in a comment, not an assertion. `lines_emitted` is still assigned and incremented in the
  loop but **never read** — dead code left over from the removal, which will read to a future
  maintainer as if a bound still exists somewhere.
- **The "38 cells" figure is fixture-specific, and the ADR states it unqualified.** ADR 0018 says
  "at 38 cells and above nothing overflows." With a longer branch name my fuzz found overflow up to
  **width 44**. The commit message correctly qualifies this ("against the real worktree"); the ADR
  drops the qualifier, and the ADR is what gets read in six months. The true invariant — already
  stated correctly one bullet above it — is "nothing overflows above the width of the widest single
  segment", which a long branch name can push arbitrarily high.
- **The suite can't catch an injection-at-wrapping-width regression.** Pinning injection cases to
  `COLUMNS=400` is well-argued (it isolates data-borne newlines from structural ones) and I agree
  with it, but it leaves the interaction uncovered. My 176-combination probe passed; nothing in the
  repo would notice if that stopped being true.
- **Green tests carry less signal this round than last.** `statusline-command.falsify.py` is still
  `FALSIFICATION BROKEN` (task 9), so this diff merges with no differential coverage — on the round
  that restructured the head assembly, all four Claude-segment sites *and* the packing loop. That's
  the largest structural change on the branch landing with the mutation harness dark.
- **Pre-existing, still unfixed, not in tasks 9/10:** a `COLUMNS` value over 19 digits makes
  `statusline-command.sh:741` print `[: … integer expression expected` to **stderr** on every
  render. It fails *safe* (wrapping switches off), but by accident of evaluation order rather than
  by design — the `[ -gt 0 ]` guard errors out before the arithmetic runs, and that arithmetic
  silently wraps to `7766279631452241917` if it ever did run. Raised in round 1, untriaged.
- **CJK / wide glyphs still over-draw.** Every glyph counts as one cell, so a path with CJK
  characters draws roughly twice its measured width and can visually overflow. This is disclosed in
  both the code comment and ADR 0018 as an accepted cost, and it is not new — but it now applies to
  the *directory* segment, which is the likeliest place for one.

### On deferring tasks 9 and 10 — I agree, with one caveat each

- **Task 9 (broken falsify harness):** agree. It's dated (2026-08-20), the cost is stated plainly,
  and fixing it is a separate design question. Note only that the risk is *higher* this round than
  last, for the reason above.
- **Task 10 (a missed worktree renders as "main checkout"):** agree that the *fix* is out of scope —
  it changes what the segment means. But the caveat is one line of documentation, not a design
  change: neither the spec nor ADR 0018 says plainly that **`wt:()` is a convenience indicator, not
  a safety mechanism, and its absence must never be relied on.** Given the motivating incident was a
  session changing a shared checkout's branch under another session, someone will eventually read
  "no `wt:()`" as "safe". Worth adding before merge; not worth blocking on.

## What I'd double-check before merging

1. **Look at it on a real narrow terminal** — split your pane to ~40 columns and confirm Claude Code
   renders 6 rows rather than clipping them. This is the one claim I can't test from here, and it's
   the one that would silently reinstate the original bug.
2. **Delete `lines_emitted`** (statusline-command.sh:754, 764) — dead since the cap came out.
3. **Qualify the "38 cells" line in ADR 0018** to say it was measured against this worktree, and
   that the general bound is the widest single segment.
4. **Add the one-line "not a safety mechanism" caveat** for `wt:()` (task 10 caveat above).
5. **Open the PR from this worktree.** `judge-guard` derives the repo as
   `basename(show-toplevel)` = `statusline-wrap-worktree`; from the shared `~/.claude` checkout it
   would look for `repo=.claude`, find no matching verdict, and block. Already recorded as task 8b.
6. **Commit the judge artifacts.** `verdicts.jsonl` is modified and both round markdown files are
   untracked — `doc-guard` already flagged this at session start.

---

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | **pass** | Round-1 defect fixed at the root, not exempted; spec's Gherkin now actually holds (122 → 54 cells, verified). |
| `execution` | **pass** | 67/67 run by me; shellcheck clean; overflow + escape claims independently reproduced across 200 widths and 176 injection combos. |
| `trajectory` | **pass** | Rejects the cheaper "exempt the head" option with a stated reason; correctly root-causes the cap as the *source* of overflow rather than a bound on it. |
| `regression` | **pass** | Wide rendering unchanged, all degenerate `COLUMNS` still fall back, injection behaviour unchanged. Row count is the only adjacent behaviour change. |
| `context_budget` | **pass** | Not an always-on context surface (script + tests + docs). Screen real estate is noted separately. |
| `traceability` | **concern** | ADR 0018 states "at 38 cells and above nothing overflows" unqualified; measured 44 with a longer branch name. Durable artifact drops the qualifier the commit message keeps. |
| `success_masking` | **concern** | Row count now unasserted (cap gone, bound is comment-only, `lines_emitted` dead); falsify harness still broken on the branch's largest refactor; injection × wrapping untested in-suite. |
| `intent_drift` | **pass** | 4 files, all in-domain. No drive-by edits, no dependency changes. |
| `checkpoint` | **pass** | Clean incremental commit on `dbf1bbc`; reverting round 2 alone restores a known-good state. |
| `audit_trail` | **pass** | ADR 0018 written for the invariant reversal; spec carries an explicit "Revised after round 1" section; deferrals recorded as dated tasks; commit message fully attributable. |

**Risk: low · Confidence: high**

## Concerns

- ADR 0018's "at 38 cells and above nothing overflows" is fixture-specific; measured overflow to width 44 with a longer branch name
- no test bounds the row count now that WRAP_MAX_LINES is gone; "at most eight" is comment-only
- `lines_emitted` is dead code (assigned/incremented at :754/:764, never read) left over from the cap removal
- injection cases pinned to COLUMNS=400, so injection × wrapping is untested in-suite (probed clean externally: 176 combos, 0 leaks)
- falsify.py still FALSIFICATION BROKEN (task 9) on the round that restructured head assembly, all four Claude-segment sites and the packing loop
- COLUMNS >19 digits prints `[: integer expression expected` to stderr from :741 every render; fails safe by evaluation order, not design; raised round 1, untriaged
- 6 of 24 rows consumed at COLUMNS=40; Claude Code's behaviour with an 8-row status line is unverified and would clip exactly the trailing segments the feature preserves
- CJK/wide glyphs counted as one cell now applies to the directory segment (disclosed, accepted, not new)
- neither spec nor ADR states that `wt:()` absence must not be relied on as a safety signal (task 10 caveat)
