# Observability verdict — `feat/statusline-wrap-worktree` @ `dbf1bbc`

- **Stage:** implementation (gates the PR)
- **Repo:** `statusline-wrap-worktree` (isolated worktree of `~/.claude`)
- **Base:** `29ac070` (docs-only) / merge-base with `main` = `124b504`
- **Judged:** 2026-08-07T03:41Z
- **Risk:** low · **Confidence:** high

---

## What was changed

The status line — the one-line prompt Claude Code draws at the bottom of the screen — used to be
printed as a single long string. On a narrow terminal it ran off the edge, and the things that got
cut off first were the ones you actually watch: the running token count and the weekly quota.

Two changes:

1. **It now folds onto more than one row.** Think of it like packing a suitcase: the script has a
   handful of pre-packed blocks (model name, token bar, Σ total, quota clock). It drops blocks into
   the current row until the next one wouldn't fit, then starts a new row. It never cuts a block in
   half. Capped at 4 rows, after which the leftovers share the last row.
2. **It now shows `wt:(name)` when you're in a linked git worktree** — a second checkout of the same
   repo. Parallel agent sessions live in worktrees, and until now nothing on screen told you which
   checkout you were in.

Both behaviours have a deliberate "chicken exit": if the terminal width (`COLUMNS`) is anything
other than a sane positive number, wrapping switches off entirely and you get exactly the old
single line.

## Does it do what you wanted?

**Mostly yes — with one honest gap.**

Confirmed by running it myself, not by reading the report:

- **Test suite: 66/66 passed.** I ran it. The claimed 50 → 66 growth is real.
- **The "never cut mid-escape-sequence" claim holds.** This was the thing you most wanted broken.
  I fuzzed every terminal width from 1 to 160 cells with a full four-segment payload and checked
  every emitted row for a dangling `ESC`. **Zero** hits. The reason it holds is structural, not
  lucky: the loop only ever concatenates whole pre-built strings and only ever breaks *between*
  them. There is no index arithmetic anywhere in it, so there is no place a cut could land.
- **The width tracking is exact.** I measured the rendered head against the arithmetic at five
  independent sites (plain dir, main repo, linked worktree, nested, dirty marker) — computed and
  measured agreed to the cell every time: 33/33, 35/35, 49/49, 79/79, 81/81. And `extras` /
  `extras_width` are genuinely in lockstep: 5 push sites, 5 width sites, paired inside the same
  `if`/`else` branches. No orphan.
- **Worktree detection is sound, including a failure mode the code comments don't name.** I built a
  real git **submodule** — whose git-dir is `super/.git/modules/mysub`, the most plausible
  false-positive for a "`gitdir` file inside the git-dir" test — and it correctly reports *not* a
  worktree. Bare repos likewise. The two rejected alternatives (`--git-dir` vs `--git-common-dir`,
  and a `*/worktrees/*` path match) really are wrong for the reasons stated.

**The gap:** the git-prompt head — `➜ user@host dir git:(branch) ✗ wt:(name)` — is treated as one
indivisible block and is **never wrapped**. In this very worktree at `COLUMNS=60`, row one measures
**120 visible cells** — twice the terminal. That is the exact symptom the feature was opened to
fix, just relocated to the first row. And because `wt:(name)` *lengthens* the head, this change
makes row one slightly worse on a narrow terminal while making the tail better.

That is consistent with the **design** ("packing at the existing ` │ ` boundaries, never
mid-segment" — the head is one segment). It is **not** consistent with the **Gherkin**, which
asserts "no line's visible width exceeds 60." The spec overclaims and nobody wrote down that the
head is exempt.

## What could go wrong / what I'm unsure about

**1. The width test can't fail for the case that actually overflows.** The assertion reads
`no wrapped line exceeds COLUMNS (widest=46<=60)` — which sounds universal. But its payload uses
`current_dir: /tmp`, which is not a git repo, so the head is a stubby 33 cells with no branch and no
`wt:()`. The 120-cell head is never rendered by any test. This is the classic shape: a green
assertion whose fixture avoids the condition under test. It does not make the code wrong — it makes
the *evidence* narrower than it reads.

**2. `statusline-command.falsify.py` reports `FALSIFICATION BROKEN`, so the repo's strongest
verification tool gave zero signal on this diff.** I confirmed the assessment: `EXPECTED` hard-codes
absolute pass counts written when the suite held **20** cases (`9/20`, `20/20`); the suite now holds
**66**. Every added test shifts all five historical versions at once. **I agree with the decision not
to "fix" it by rewriting the numbers** — and more strongly than the feature file argues it. This
repo already has **ADR 0016, "A differential harness must prove its two sides differ"**, written
against exactly this class of bug. Rewriting `EXPECTED` to match observation would convert a loud,
honest failure into precisely the silent rubber stamp that ADR forbids. Leaving it loudly broken and
tracked (task 9) is the correct call. The residual cost is real though: this diff merges without
differential coverage.

**3. A missed worktree fails silently *into the dangerous reading*.** If detection ever breaks — a
git layout change, a `rev-parse` failure, a permissions problem — `wt:()` simply doesn't render. And
"no `wt:()` segment" is defined to mean "you are in the main checkout." So a broken detector looks
identical to the state the feature exists to warn you away from. There is no `wt:(?)` or any other
marker distinguishing "not a worktree" from "couldn't tell." Given the motivating incident was a
session switching branches in the shared checkout while another session worked in it, that's the
failure direction you'd least want.

**4. No ADR for a reversed invariant.** The file's header comment used to state that the output can
never be split across lines, and that statement was load-bearing in the *injection* rationale. This
change reverses it. The replacement in-file comment is genuinely good — it draws the right
distinction between a structural break the script chose and a data-borne one an attacker chose — but
per this repo's own gates, reversing a documented structural/security-adjacent invariant belongs in
`docs/decisions/`, not only in a feature file that will be archived.

**5. Minor, verified, low-impact:**
   - `${#var}` counts **bytes** in a `C` locale and **characters** in UTF-8 (measured: 5 vs 4 for
     `café`). A non-ASCII directory or branch name in a `C` locale over-counts, so the line wraps
     *earlier* than needed. Safe direction — it can never cause an overflow — but it means wrap
     behaviour is locale-dependent and nothing pins the locale.
   - `COLUMNS` values that are all-digits but exceed `int64` (e.g. `9999...9`, 23 digits) make bash's
     `[` emit `integer expression expected` on **stderr**. The `&&` then short-circuits and wrapping
     correctly stays off — so it fails *safe*, but noisily. The degenerate-`COLUMNS` test loop covers
     `0`/``/`abc`/`-1`, all of which the digit guard rejects; it does not cover an all-digit value
     that breaks the arithmetic.

**What I checked and found clean:** the injection pinning, the regression surface, and the rollback
point. Pinning the old tests to `COLUMNS=400` *strengthens* rather than relaxes them — at a width
where no structural break can occur, any observed newline must be data-borne, so `nl=0` isolates the
original property more sharply than before. Wide-terminal output is byte-identical to the old join
(separator strings `"  ${DIM}│ ${RESET}"` and `"${DIM} │ ${RESET}"` are unchanged and applied at the
same positions). Three files touched, all in domain, no dependencies added, shared checkout
untouched. One implementation commit on top of a docs-only commit, so `git revert dbf1bbc` is a
complete, clean rollback.

## What I'd double-check before merging

1. **Decide what the head should do on a narrow terminal**, then make spec and code agree. Either
   amend the Gherkin's "no line exceeds COLUMNS" to exempt the git prompt and record it under
   Non-goals, or let the head break at its own spaces. Don't ship a criterion the code doesn't meet.
2. **Re-point the width test at a real repo path** — ideally the linked worktree fixture the file
   already builds — so `widest <= COLUMNS` is measured against a head that can actually overflow.
   Expect it to fail; that failure is the finding.
3. **Confirm which checkout the PR gets opened from.** `judge-guard.sh` derives `repo` as
   `basename(git rev-parse --show-toplevel)`, which is `statusline-wrap-worktree` here — so this
   verdict is recorded under that name, in *this worktree's* `verdicts.jsonl`. Open the PR from
   `~/.claude` instead and the guard will look for `repo=".claude"`, find no match, and block
   (fail-closed, safe, but confusing). Open it from this worktree, or re-judge from there.
4. **Eyeball it live at a genuinely narrow width** before merge. `settings.json` runs
   `$HOME/.claude/statusline-command.sh`, i.e. the shared checkout — so nothing here takes effect
   until this lands, and the first real-terminal render will be post-merge.
5. **Give task 9 a date.** A permanently-`BROKEN` harness stops being read, and this repo's own
   ADR 0016 is about harnesses that stop telling the truth. The proposed fix — assert *which named
   cases* fail per version rather than a count — is right and survives adding tests.

---

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| `intent` | **concern** | Stated goal (tail segments stop disappearing) met. But the Gherkin's "no line's visible width exceeds COLUMNS" is not satisfied — the head measures 120 cells at `COLUMNS=60` in this worktree, and `wt:()` lengthens it further. Spec and code disagree; neither Non-goals nor a comment records the exemption. |
| `execution` | **pass** | 66/66 run by me. Mid-escape guarantee fuzzed across widths 1–160: zero breaks. Width arithmetic verified against measurement at 5 sites, exact each time. `extras`/`extras_width` lockstep verified — 5 push sites, 5 width sites, correctly paired. Red phase evidenced. |
| `trajectory` | **pass** | Two wrong worktree tests tried and rejected with stated reasons; a vacuous test caught and falsified; measuring-vs-tracking trade-off named with its accepted cost; `format_duration` bound to a variable specifically to avoid a second run returning a different answer. Reasoning, not luck. |
| `regression` | **pass** | All 50 prior cases green. `COLUMNS=400` pinning preserves — and arguably sharpens — the injection guarantee. Wide-terminal output byte-identical to the previous join. Empty-`extras` path unchanged. |
| `context_budget` | **pass** | Not a rule/skill/prompt change; nothing added to always-on context. Packing loop is bounded by `${#extras[@]}` ≤ 4 and forks no new processes. |
| `traceability` | **pass** | Commit message is ADR-grade: every non-obvious choice, both rejected alternatives, and the falsify state are all narrated. In-file comments explain the structural-vs-data-borne newline distinction where a reader will hit it. |
| `success_masking` | **concern** | Two instances. (a) `widest=46<=60` reads universal but its `/tmp` payload has no repo, so the overflowing head is never exercised — the assertion cannot fail for the real case. (b) `falsify.py` is `BROKEN`, so the repo's differential harness contributed zero signal to this diff. Both disclosed, neither hidden. |
| `intent_drift` | **pass** | Three files, all in domain. No deps. No drive-by edits. Actively resisted the adjacent temptation to rewrite `falsify.py`'s counts — restraint, not drift. |
| `checkpoint` | **pass** | Single implementation commit `dbf1bbc` atop docs-only `29ac070`; `git revert dbf1bbc` is a complete rollback. Isolated worktree; shared `~/.claude` checkout untouched, as the feature file required. |
| `audit_trail` | **concern** | Attribution clean (`Mark Suyat` + `Co-Authored-By`). But the change reverses a documented, security-adjacent invariant ("output can never be split across lines") with no ADR under `docs/decisions/` — which this repo's gates require for structural decisions. The feature file is not a durable home for it. |

## Concerns

1. Git-prompt head is unbreakable — 120 visible cells at `COLUMNS=60` in this worktree; the Gherkin's "no line exceeds COLUMNS" overclaims.
2. `wt:(name)` lengthens the head, so row one is slightly *worse* on a narrow terminal than before this change.
3. Width test payload uses `/tmp` (not a repo), so the overflowing head is never rendered by any test — the assertion can't fail for the real case.
4. `statusline-command.falsify.py` is `BROKEN` (absolute counts written at 20 cases, suite now 66), so the repo's differential harness gave zero signal on this diff. Not fixing it is the right call — ADR 0016 forbids exactly that rubber stamp — but task 9 needs a date.
5. No ADR for reversing the documented "output is never split across lines" invariant, which was load-bearing in the injection rationale.
6. A failed worktree detection renders identically to "you are in the main checkout" — silent, and into the dangerous reading. No `wt:(?)` or unknown-state marker.
7. `${#var}` counts bytes in a `C` locale, chars in UTF-8 (measured 5 vs 4): non-ASCII names over-count and wrap early. Safe direction, but wrap behaviour is locale-dependent and the locale is unpinned.
8. All-digit `COLUMNS` beyond `int64` emits a bash `integer expression expected` warning to stderr; fails safe (no wrap) but is untested — the degenerate loop only covers values the digit guard already rejects.
9. Verdict is recorded under `repo="statusline-wrap-worktree"`; opening the PR from `~/.claude` instead would make `judge-guard.sh` look for `repo=".claude"` and block.
