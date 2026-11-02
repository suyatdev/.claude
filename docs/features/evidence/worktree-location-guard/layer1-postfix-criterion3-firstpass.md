# Layer 1 post-fix criterion-3 first pass

Reviewer scope: layer 1 (`hooks/worktree-guard.sh` + `hooks/lib/worktree_guard_bash_arms.sh` +
`hooks/lib/classify-git-command.py`) only. Layer 2 (`hooks/reference-transaction`) is out of
scope and was not touched.

Population: `docs/features/evidence/worktree-location-guard/layer1-post-fix-would-deny.tsv`,
committed at `7be03dc`, 76 lines — every line in `hooks/state/worktree-guard.log` at or after
2026-09-14T20:41:44Z, i.e. every line written by the guard carrying the merged tilde fix
(`270a0b9`).

Methodology note, stated once: this log's fields are `timestamp, session_id, arm, mode,
decision, repo-root, command`. Field 6 is the **repo-root the guard resolved**, not the
session's cwd — it is populated only when a refusal survives to the point the guard has
identified a repository (Arm A after Step A3, or Arm D/B2 after `resolve_effective_repo()`).
For every line below where field 6 is empty, the refusal fired at a **shared precondition or
segment-level check that runs before any repository is resolved** (`SEG_UNPARSED`, or the
`SEG_SCOPE_OPT` / `SEG_ENV` / `SEG_OPAQUE` loop) — so for those lines the log alone cannot say
which repository, if any, the command targeted. To classify each line's real-world danger I
therefore (a) ran every one of the 76 commands through the guard's own
`hooks/lib/classify-git-command.py` (the exact lexer/classifier the hook uses) to get the
segment-indexed facts, and (b) read the reconstructed command text for every line (in full, or
via the specific fact-token the classifier flagged, which for most of the heredoc-driven hits
is itself a large verbatim chunk of the command) to judge what it would actually have done.
Reconstruction un-escapes the log's literal `\n` back to real newlines
(`field.replace('\\n','\n')`); this is lossy where the original command legitimately contained
a literal `\n` two-character sequence (e.g. inside a Python string literal) rather than a
folded newline, but it does not change the safety-relevant classification for any line checked
below.

## Headline counts (re-derived)

```
wc -l docs/features/evidence/worktree-location-guard/layer1-post-fix-would-deny.tsv
```
→ 76 lines.

```
awk -F'\t' '{print $5}' layer1-post-fix-would-deny.tsv | sort | uniq -c
```
→ `76 would-deny` (all 76; no other decision value appears).

```
awk -F'\t' '{print $3}' layer1-post-fix-would-deny.tsv | sort | uniq -c
```
→ `1 A`, `74 B2D`, `1 D`.

This **confirms** the figures I was given (76 lines, all would-deny, split 74/1/1 by arm). I
found no discrepancy in those specific counts.

All 76 commands are textually distinct (`sort -u | wc -l` → 76): there are no exact-duplicate
lines, so "shapes" below are grouped by refusal **mechanism + real-world danger**, not by exact
text match, per the task's instruction.

## Job 1 — every line judged, by shape

| # | Shape (mechanism) | Lines (by line #) | Count | Verdict |
|---|---|---|---|---|
| 1 | Arm D: a bare `git merge origin/main --no-edit` run directly (not wrapped) with cwd/repo-root resolved to `/Users/marksuyat/.claude`, confirmed a real primary checkout (`.git` is a directory, not a `gitdir:` pointer) | 1 | 1 | **CORRECT** |
| 2 | Arm A: a Write/Edit target physically under `/Users/marksuyat/.claude` (a pane-state scratch file), not matching any of Arm A's exempt paths (`docs/*`, `.claude/*`, `coding-memory/*`, `settings.json`, `rules/*`, `skills/*`, `projects/*/memory/*`) | 36 | 1 | **CORRECT** (per the guard's literal, documented contract — Arm A denies by physical location alone, tracked-or-not; this is the design's stated "accepted blast radius," not a bug) |
| 3 | `SEG_OPAQUE` from a genuine env-style wrapper (`env …` / a bare leading assignment) immediately preceding a real `git commit`, in the `dc17a9f0` session working the `handoff-trim-safety` card (commit-message file paths and later commands in the same session all name the linked worktree `/Users/marksuyat/.worktrees/.claude/handoff-trim-safety`) | 3, 4 | 2 | **UNDETERMINABLE** (real HEAD-changing command; the payload cwd is not captured anywhere in this log format, so primary-vs-worktree cannot be settled from this evidence — see note below) |
| 4 | `SEG_UNPARSED` (total lex failure) on a heredoc that nonetheless chains a real `git add && git commit && git log && git show` after it, same session/card context as #3 | 52 | 1 | **UNDETERMINABLE** (same reasoning as #3) |
| 5 | `SEG_BRANCH_MOVE` + `SEG_OPAQUE` together: a real `git switch -c feat/season-archive origin/main` on segment 0, with an unrelated `$(git branch --show-current)` inside a later `echo` (segment 2) tripping the opaque check first, so the branch-move-specific repo check in Step 7 is never reached | 41 | 1 | **UNDETERMINABLE** (real HEAD move; same cwd gap as #3/#4 — the surrounding commands in this `358b4337` session are all Snatch-Bracket feature-branch bookkeeping, consistent with a worktree cwd, but not proof) |
| 6 | `SEG_UNPARSED`, and manual reading of the full reconstructed text shows **no** real `git`/`cd` invocation anywhere — pure heredoc file writes (commit-message drafts, session-state/compliance-judge markdown appends) or a SQL+docker probe | 5, 23, 33, 47, 54, 60, 64 | 7 | **WRONG** under the strict "would this really have endangered a checkout" test — but this is the guard's documented fail-closed contract for a line the lexer cannot parse at all ("an empty answer is not an allow"); not a new defect, not tilde-related |
| 7 | `SEG_OPAQUE` on the literal JSON payload of a self-test probe that exercises the **fixed** guard's own tilde-cd/tilde-add handling in an isolated scratch `STATE_DIR` (mentions "git" only inside a JSON string being piped to python/bash) | 2 | 1 | **WRONG** under the strict test (the outer line itself does no real git/cd work — see Job 2, where I independently re-ran both inner probes) |
| 8 | Real, literal `cd` into a path I independently confirmed is a genuine linked worktree, combined with an unrelated `SEG_OPAQUE`/`SEG_GROUPED` token elsewhere on the same compound line (an echo string mentioning "(git grep)", or `if`/`then`/`do` from a `for` loop) — no HEAD move, no worktree-add, anywhere on the line | 21, 22, 31, 76 | 4 | **WRONG** (the `cd` itself targets a confirmed real worktree; the line is refused for an unrelated, harmless token before that `cd`'s safety is ever evaluated) |
| 9 | `SEG_OPAQUE` on a real, **read-only** `git -C "$W" …` (rev-parse --short, status -sb) where `$W` is set via `W=~/.worktrees/mtg-wizard/ui-redesign-visual-restyle` — a genuine tilde-store path. Directly replayed through the live fixed hook (see Job 2): refusal fires at Step 5 with the message *"the guard cannot hold this segment's command accountable for the git or cd it runs"* — **not** a tilde-resolution message, and `resolve_effective_repo()`/`expand_tilde()` are never reached | 62, 65, 68, 70 | 4 | **WRONG** (confirmed real worktree, confirmed read-only command, confirmed the tilde-fix code path was never exercised) |
| 10 | `SEG_OPAQUE`, remaining instances: either a real **read-only** git call reached only through a `$(...)` substitution or a `for`/`if`/`do` keyword wrapper (`rev-parse`, `hash-object`, `status --short`, `branch --show-current`, `diff --stat`/`--no-index`, `log`, `for-each-ref`, `rev-list`, `ls-tree`, `cat-file -e`, `merge-base`, `merge-tree`), or a pure textual mention of the word "git"/"cd" inside markdown/judge-verdict prose, a `grep` pattern, or heredoc content with no invocation at all | 6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,24,25,26,27,28,29,30,32,34,35,37,38,39,40,42,43,44,45,46,48,49,50,51,53,55,56,57,58,59,61,63,66,67,69,71,72,73,74,75 | 54 | **WRONG** under the strict test on every one I read — see the discipline note below |

Total: 1+1+2+1+1+7+1+4+4+54 = **76**. Every line is accounted for.

**Discipline note on row 10 (54 lines):** I did not re-derive the ground-truth danger of every
one of these 54 independently from scratch with equal depth. What I *did* do for all 54: ran
the real classifier and confirmed the refusal mechanism is `SEG_OPAQUE` in every case (ground
truth, not sampled); then ran an automated text search for the git verbs that actually change
state or move HEAD (`git commit`, `git merge`, `git rebase`, `git reset`, `git checkout`,
`git switch`, `cherry-pick`, `git revert`, `stash pop`, `stash apply`, `push --force`,
`branch -f/-D`, `worktree add`) across the reconstructed text of all 54; that flagged 5
candidates (10, 12, 53, 71, 75), and I read every one of those 5 in full — all five were false
alarms from substring overlap (`git merge-base`/`git merge-tree` are read-only plumbing that
neither move HEAD nor merge anything; the rest were prose or test-fixture strings mentioning
`git commit` without executing it). The other 49 of the 54 I read via the classifier's own
extracted token (for the majority, the flagged fact-token *is* a large verbatim chunk of the
line's substantive content, since the opaque hit comes from heredoc prose) plus a full read of
roughly half of them individually during this review. I am confident none of the 54 contains a
real HEAD move, worktree-add, or primary-checkout write, but I have not individually eyeballed
literally all 54 word-for-word, and I am stating that gap rather than papering over it.

### What "CORRECT" vs "WRONG" is measuring here, precisely

Rows 6–10 (70 of 76 lines) are **WRONG** only against the narrow, literal test the task gave me
("did the command really do dangerous git work in a primary checkout, or really misplace a
worktree, or really write to a primary checkout's tracked files") — none of them did. But every
one of those 70 traces to one of two **pre-existing, documented** mechanisms
(`SEG_UNPARSED`'s "an unreadable command line… cannot be allowed", or `SEG_OPAQUE`'s "a command
that merely MENTIONS git lands here too; that false denial is accepted and stated") that the
guard's own source comments name as an accepted cost, not to anything the tilde fix touched or
could have touched. I am reporting them as WRONG under the letter of the given test because the
task explicitly asked me not to let the guard's own "this is accepted" framing substitute for
an independent judgment, and because the volume matters directly for criterion 1 (see the
window-sizing section): if armed today, this same mechanism would block the large majority of
the compound diagnostic/reporting/heredoc commands actually used in this window, not just the
edge cases it was designed for.

Rows 3–5 (4 lines: 3, 4, 41, 52) are **UNDETERMINABLE** rather than WRONG because they contain
a *real* HEAD-changing command and I cannot rule out that it ran in a primary checkout — the
circumstantial evidence (scratch-path naming, sibling commands in the same session, and in one
case an explicit dispatched-agent instruction "Work from: `.../bracqueen-rebrand` (a git
worktree; never cd to another checkout)") all points toward a linked-worktree cwd, which would
make these WRONG too, but the log format does not capture payload cwd for a refusal that never
reaches repo resolution, so I cannot prove it. What would settle it: the original session
transcripts' recorded cwd at the time of each Bash call, which I did not have access to.

## Job 2 — tilde-regression hunt

Every line whose command field contains a literal `~` (15 of 76, found with
`awk -F'\t' '$7 ~ /~/'`) was examined individually:

| Lines | What the `~` actually is | Regression-relevant? |
|---|---|---|
| 2 | `~/.worktrees/.claude/worktree-guard-tilde` and `~/.worktrees/.claude/probe` — literal test-probe payloads exercising the fix itself | See below — independently re-ran both |
| 24, 25, 28, 33 | `~/.claude/rules/core-conduct.md`, `~/.claude/skills/…` — file-citation paths **inside markdown prose** (compliance-judge verdict text), never a shell operand | No — not a path any shell ever evaluates |
| 26, 39, 40, 63 | `~40`, `~50`, `~1500` — an approximation tilde ("about 40 citations"), not a path at all | No |
| 44 | `~~\`CLAUDE.md\`…~~` — Markdown strikethrough syntax | No |
| 45 | `~/.claude/panes/run-pane-agent.sh:93` — a file-citation path inside prose | No |
| 62, 65, 68, 70 | `W=~/.worktrees/mtg-wizard/ui-redesign-visual-restyle` then `git -C "$W" …` — a **real** shell tilde-expansion into a centralized-store path | Yes — examined in depth |

So of the 15 tilde-bearing lines, **4 (62, 65, 68, 70) actually exercise a real tilde path
handed to `cd`/`-C`-shaped logic**; the other 11 are prose/markdown/approximation uses of `~`
that no shell ever expands. This is a materially smaller number than "15 tilde lines" would
suggest, and it matters: it means this window offers very little raw material for a tilde
regression even before mechanism is considered.

**For the 4 real cases:** I confirmed `~/.worktrees/mtg-wizard/ui-redesign-visual-restyle`
is a genuine linked worktree —

```
$ ls -la ~/.worktrees/mtg-wizard/ui-redesign-visual-restyle/.git
gitdir: /Users/marksuyat/Other Docs/mtg-wizard/.git/worktrees/ui-redesign-visual-restyle
```

— then replayed line 62's exact reconstructed command through the live, fixed
`hooks/worktree-guard.sh` (scratch `WORKTREE_GUARD_STATE_DIR`, `WORKTREE_GUARD_MODE=deny`, no
real command executed — the hook only judges the string):

```
rc = 2
worktree-guard: command blocked — the guard cannot hold this segment's command accountable
for the git or cd it runs.
  segment: segment 1
  token: HEAD:   $(git -C $W rev-parse --short HEAD)
This is a redirect the guard cannot follow: … `cd` and `-C` are the only two redirects
resolved rather than refused.
```

This is the `SEG_OPAQUE` message, not a tilde-resolution message ("outside the centralized
store" / "cannot be entered" never appear), and it fires at Step 5 — strictly before Step 6
(cwd) and Step 7 (`resolve_effective_repo()`, where `expand_tilde()` actually lives). **The
fixed function was never invoked for any of these 4 lines.** They are false positives (row 9
above), but of the pre-existing opaque-wrapper kind, not of the tilde-fix kind.

**Direct verification that the fix itself works, independent of the log:** line 2's inner
probes are exactly the two shapes the 2026-09-07/08 review found broken. I re-ran both against
the live, fixed guard myself (same scratch-STATE_DIR technique, `WORKTREE_GUARD_MODE=deny`):

```
=== tilde-cd rc=0 ===      # cd ~/.worktrees/.claude/worktree-guard-tilde && git merge x
=== tilde-add rc=0 ===     # git worktree add ~/.worktrees/.claude/probe -b probe
```

Both allow (rc=0), and I independently confirmed `~/.worktrees/.claude/worktree-guard-tilde`
is a real, existing linked worktree of `.claude` before treating rc=0 as correct. This is
direct, reproducible evidence the fix behaves correctly for the exact two shapes that were
broken before — obtained by me re-running it now, not by trusting the earlier session's
(refused, unlogged-reason) attempt at the same test.

**Job 2 bottom line:** I examined all 15 tilde-bearing lines (not just the 4 "real path" ones).
Of those, 4 reach a real shell tilde-expansion into a centralized-store path, and I traced all
4 to a confirmed non-tilde refusal mechanism via direct replay of the actual hook, plus
independently re-verified the fix's own two originally-broken shapes both now allow. **No live
tilde regression is visible in this window.** This is a much weaker claim than "the fix is
proven safe" — it says only that the small number of tilde-bearing commands that appeared
naturally in 40 hours of real work happened to be intercepted by an unrelated, earlier check
before the fixed code ever ran, and that a direct, independent replay of the fix's own target
shapes still passes.

## Job 3 — window size and spread, honestly

**Elapsed vs. required:** the fixed guard has been live since 2026-09-14T20:41:44Z. The last
line in this population is 2026-09-16T12:50:17Z; my own replay runs during this review added a
line at 2026-09-16T13:14:07Z. That is **~40.1–40.5 hours elapsed of the 7-day (168-hour)
requirement — about 24%.** This is explicitly a first look, not a completed criterion 3 pass;
roughly three-quarters of the required observation window has not happened yet.

**Session/repo spread** (`awk -F'\t' '{print $2}' … | sort | uniq -c`):

- **14 distinct session ids** contributed the 76 lines. The largest single session
  (`9ade8e70…`) contributed 16 of 76 (21%); the next two contributed 11 and 10. No session
  dominates the population — this is not "74 of 76 lines from one session doing one thing."
- Timestamps split **41 lines on 2026-09-14, 23 on 2026-09-15, 12 on 2026-09-16** — spread
  across all three calendar days the window has so far covered, not a single burst.
- **Repository spread:** the log's own repo-root field is populated for only 2 of 76 lines
  (both resolve to `/Users/marksuyat/.claude`, since those are the only two that survived to
  repo resolution). Reading the actual command text, the underlying work spans at least
  **three different repositories**: `.claude` itself (the tilde-fix self-test),
  `Snatch-Bracket/bracqueen-rebrand` (a season-archive feature, worked from
  `/Users/marksuyat/.worktrees/Snatch-Bracket/bracqueen-rebrand`), and `mtg-wizard` (a UI
  restyle, worked from `~/.worktrees/mtg-wizard/ui-redesign-visual-restyle`). All three funnel
  through the same log because hooks are registered globally and always execute the copy of
  the guard script living in the primary `.claude` checkout, regardless of which repository's
  Bash tool call triggered them — so a single log with a single dominant repo-root value does
  not mean a single repository was actually being worked on.

**Job 3 bottom line:** the population is reasonably diverse (14 sessions, 3 days, ≥3
repositories) rather than a narrow repeat of one shape, which is a point in favor of what
precision *has* been measured. But only ~24% of the required 7-day window has elapsed, so this
pass should be read as an early regression check, not as satisfying criterion 1's time
requirement or criterion 3's own "every would-deny line reviewed" bar for the full window —
only this partial window's lines have been reviewed.

## What this review cannot establish (stated once, not implied away)

This log records only what the guard actually turned away. A command shape the guard has gone
blind to (whether from the pre-existing lexer/opaque limitations documented above, or from
anything else) produces **no line at all**, and a failed append in `log` mode is silently
dropped by design. Nothing in this document should be read as a coverage claim — only a
precision claim about the 76 lines that were in fact recorded: **of the 76 lines recorded and
reviewed, 2 were judged correct refusals, 4 are undeterminable (real HEAD-changing work, but
the log does not capture enough to place it in a primary checkout or a worktree), and 70 were
judged incorrect refusals under the letter of the test — all 70 tracing to two pre-existing,
documented, non-tilde mechanisms, and none of the 76 showing evidence of a tilde-expansion
regression.**
