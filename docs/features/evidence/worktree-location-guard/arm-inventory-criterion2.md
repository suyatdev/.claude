# Arm inventory and criterion 2 — worktree-location-guard

Scope: enumerate every arm label the *live* code can write into `hooks/state/worktree-guard.log`
(layer 1) and `hooks/state/reference-transaction.log` (layer 2), from the code — not from the log
— then decide criterion 2 ("every arm has recorded at least one `would-deny`") per arm. Read-only;
no hook, source file, or feature card was modified.

## Summary table

| Arm | Layer | Emitted at (file:line) | Ever fired (whole log) | Fired post-fix (≥ `2026-09-14T20:41`) | Log-field test coverage |
|---|---|---|---|---|---|
| `A` | 1 | dispatch: `hooks/worktree-guard.sh:543`; direct literal refusals: `worktree-guard.sh:602,635,648,709,730,773`; via `$ARM` in shared preconditions (`require_home` `:365-375`, `deny_version` `:377-390`, `require_git_present` `:398-400`) reached from Arm A's own call sites `:580,683,688` | Yes — 391 (381 `would-deny` + 10 `deny`) | Yes — 1 | Yes — `G1` (`worktree-guard.test.sh:1856`), `G4` (`:1928`) assert the log line's arm field literally equals `A` |
| `B2D` | 1 | dispatch: `hooks/worktree-guard.sh:544` (`Bash) ARM=B2D`); propagated via `$ARM` through every shared-precondition and line/segment-scoped refusal in `hooks/lib/worktree_guard_bash_arms.sh`: `deny_lexer` `:38`, `refuse_command`'s default arm `:115-128,167`, `SEG_UNPARSED` `:147`, `SEG_SCOPE_OPT/SEG_ENV/SEG_OPAQUE` (via `deny_segment`'s `${4:-$ARM}` default) `:190-207`, `SEG_GROUPED` `:255`, every `resolve_effective_repo` failure `:336,348,378,397`; also reached via `require_home`/`require_git` `:80-81` | Yes — 1670 (1665 `would-deny` + 5 `deny`) | Yes — 74 | **No.** `grep -c B2D hooks/worktree-guard.test.sh` = 0. The label never appears in the test file. |
| `B2` | 1 | literal `"B2"` passed as the arm argument (`$4`) to `deny_segment` in `hooks/lib/worktree_guard_bash_arms.sh:420,433,442,464,485,495` — the `git worktree add`-specific refusals, reached only once a repository has been resolved | Yes — 10 (all `would-deny`) | **No — 0** in the 76-line post-fix extract | Behavior-tested (e.g. test case `'B2 add anywhere else'`, `worktree-guard.test.sh:737`) but **never at the log-arm-field level** — the `deny()` test helper (`:120-137`) checks only exit code and stderr text, never the log file |
| `D` | 1 | literal `"D"` passed to `refuse_command` in `hooks/lib/worktree_guard_bash_arms.sh:528` — the HEAD-move-in-primary-checkout refusal, reached only once a repository is resolved and confirmed primary (`EFF_PRIMARY=1`) | Yes — 46 (43 `would-deny` + 2 `deny` + 1 `bypass`) | Yes — 1 | **Partial.** `D50` (`worktree-guard.test.sh:1432`) asserts `arm D` at the log level, but only for the **bypass** decision. `D40`–`D49` (`:1266-1416`), which exercise the ordinary deny path, use the same stderr-only `deny()` helper and never assert `arm=D` in the log for a `deny`/`would-deny` line. |
| `D-L2` | 2 | single hardcoded constant: `hooks/reference-transaction:143` (`ARM='D-L2'`); written at the log-append call, `:265-266`. No other assignment to `ARM` exists in this file (`grep -n "ARM=" hooks/reference-transaction` returns exactly this one line). | Yes — 1226 (all `WOULD-DENY`) | N/A — layer 2's criterion 2 is not date-windowed; the whole log is in scope per `docs/features/evidence/worktree-location-guard/README.md` | **No.** `grep -c D-L2 hooks/reference-transaction.test.sh` = 0. `assert_log_has`'s `log_clauses()` (`:138-141`) reads `CLAUSE_FIELD=5` (`:137`) — the decision+reason field — and never field 3 (arm). Lower severity than the layer-1 gaps: there is only one possible value, so there is no mislabeling risk a test could catch that isn't already implied by every other passing assertion. |

Commands run to produce every count above are given inline below each job.

## Job 1 — the complete arm set, from the code

**Layer 1** (`hooks/worktree-guard.sh` + `hooks/lib/worktree_guard_bash_arms.sh`): four labels —
`A`, `B2D`, `B2`, `D`. Confirmed by reading every call site of `append_log`/`refuse`/`refuse_command`
(see table above for citations). `ARM` is assigned exactly twice in the whole codebase:

```
$ grep -n "ARM=" hooks/worktree-guard.sh
359:ARM=''
543:  Edit|Write|NotebookEdit) ARM=A ;;
544:  Bash)                    ARM=B2D ;;
$ grep -n "ARM=" hooks/lib/worktree_guard_bash_arms.sh
(no output)
```

`B2` and `D` are never assigned to `$ARM` — they are passed as **literal string arguments** at
the specific call sites named in the table, overriding the dispatch-time `$ARM` (which stays
`B2D`) only for those two arm-specific violations, once a repository has been resolved. This
matches the code comment at `worktree-guard.sh:355-358` exactly: *"`B2D` is the value for a
refusal that is the shared PRECONDITION of both Bash arms … Naming either arm alone would claim a
judgement the guard never reached."*

**Layer 2** (`hooks/reference-transaction`): one label — `D-L2`, a single constant, never
reassigned.

## Job 2 — the `D` puzzle

**Verdict: `D` is a currently-live arm label. The card's claim that it is not is wrong.**

`hooks/lib/worktree_guard_bash_arms.sh:528` calls `refuse_command D "$EFF_ROOT"` today, on this
branch, with no diff against `origin/main`:

```
$ git status --short              # clean
$ git diff origin/main -- hooks/worktree-guard.sh hooks/lib/worktree_guard_bash_arms.sh
(no output)
```

That is the actual "this command would move HEAD in the primary checkout" refusal — Arm D's
entire reason for existing — and it is reached whenever a Bash segment resolves to a primary
checkout and carries a `SEG_BRANCH_MOVE` fact (`:498-529`). It is not dead code, not a stale
branch, and not reachable only from a test harness: it sits in the arm's main judgment path.

I checked the specific `D` line the post-fix extract carries in full:

```
2026-09-14T20:41:44Z  28ddd1b0-befd-4bcc-a6b8-0cbaeb150f3a  D  log  would-deny  /Users/marksuyat/.claude  git merge origin/main --no-edit 2>&1 | tail -6
```

`git merge` matches `SEG_BRANCH_MOVE` in the classifier and the repo (`/Users/marksuyat/.claude`)
is the primary checkout — an ordinary, correctly-attributed Arm D refusal from the current code,
not an artifact of anything else.

**Why the card's "predate the consolidation" explanation doesn't hold up, checked against git
history rather than the card's own prose:**

```
$ git log --diff-filter=A --format='%H %ci %s' -- hooks/lib/worktree_guard_bash_arms.sh
77ccbcf 2026-08-26 15:37:02 -0400 refactor(worktree-guard): the Bash arms move to hooks/lib/, verbatim
$ git log --oneline -- hooks/lib/worktree_guard_bash_arms.sh
22ef0ec fix(worktree-guard): task 10 -- a leading ~ names what the shell would name
77ccbcf refactor(worktree-guard): the Bash arms move to hooks/lib/, verbatim
```

Only two commits ever touch this file, and the second moved it "verbatim" out of
`worktree-guard.sh`. Tracing back further:

```
$ git log --oneline -- hooks/worktree-guard.sh | tail -3
09e30ab feat(worktree-guard): Arms B2 and D judge the Bash command line
10c600f feat(worktree-guard): Arm A refuses writes into a primary checkout
```

`09e30ab` (2026-08-26 14:39:58 -0400) is the **very first commit that introduced Arms B2 and D at
all**, and its diff already contains exactly today's scheme — literal `"B2"` and `refuse_command D`
alongside `ARM=B2D` for the shared preconditions:

```
$ git show -s --format='%ci' 09e30ab
2026-08-26 14:39:58 -0400
$ git show 09e30ab -- hooks/worktree-guard.sh | grep -n 'ARM=B2D\|" B2 "\|refuse_command D'
290:+  Bash)                    ARM=B2D ;;
695:+        "$idx" B2 ""
...
803:+    refuse_command D "$EFF_ROOT"
```

The card dates the evidence window's start at task 9's registration commit `b466252`,
2026-08-26 **18:16:58** -04:00 — almost four hours *after* `09e30ab`. There is no earlier commit
that used a different scheme (a fully-merged single `B2D`-only label, or fully-separate `B2`/`D`
with no shared-precondition label) — `09e30ab` is the origin of this file's arm logic, full stop.
**There was never a "pre-consolidation" era inside the logging window, because the window didn't
start until after this scheme already existed.**

The more mundane, code-consistent explanation for why `D` and `B2` are rare next to `B2D`: `B2D`
covers a wide, frequently-hit set of *shared precondition* failures (unlexable commands, an
unaccountable `argv[0]`, a `GIT_` env assignment, a global option, an unresolvable `cd`/`-C`,
`$HOME` missing, git absent or too old) that fire on ordinary, non-worktree-related Bash calls
across every repo on the machine. `D` and `B2` only fire on the much narrower, specific shape of
an actual HEAD-move or an actual hand-rolled `worktree add` **after** a repository has already
been resolved. Fewer matching commands, fewer log lines — not staleness.

**Recommendation:** correct `docs/features/worktree-location-guard.md`'s 2026-09-01 and
2026-09-04 progress notes (the "27 `D` and 5 `B2` lines predate the code consolidating those two
arms into `B2D`" / "the 36 `D` / 7 `B2` legacy lines still count for neither arm" claims). Based on
the history above, those lines are ordinary live `D`/`B2` refusals, not legacy ones, and per the
whole-log counts in Job 3 they should currently count *for* criterion 2, not for neither arm. I
did not edit the card — that edit is yours to make.

## Job 3 — criterion 2 per arm

Counts, whole log (each layer's log read directly under `/Users/marksuyat/.claude/hooks/state/`,
read-only):

```
$ awk -F'\t' '{print $3, $5}' /Users/marksuyat/.claude/hooks/state/worktree-guard.log | sort | uniq -c | sort -rn
1665 B2D would-deny
 381 A would-deny
  43 D would-deny
  10 B2 would-deny
  10 A deny
   5 B2D deny
   2 D deny
   1 D bypass
```
(2117 lines total at query time)

```
$ awk -F'\t' '{print $3, $4}' docs/features/evidence/worktree-location-guard/layer2-would-deny.tsv | sort | uniq -c
1226 D-L2 log
```
(matches the raw log's `WOULD-DENY primary-HEAD-lock-held` count of 1226 exactly — the extract is
the complete, unfiltered set of layer 2's `would-deny` lines, per its own README.)

Layer 1, post-fix window (`≥ 2026-09-14T20:41`), re-derived from the committed extract:

```
$ awk -F'\t' '{print $3}' docs/features/evidence/worktree-location-guard/layer1-post-fix-would-deny.tsv | sort | uniq -c
   1 A
  74 B2D
   1 D
```

This reproduces the user's stated counts (74 `B2D`, 1 `D`, 1 `A`) exactly. **Note on
reproducibility:** re-running the same filter directly against the *live* `worktree-guard.log`
returned 77 lines instead of 76 — one extra `B2D` line, timestamped after the extraction, from a
session other than the ones already in the extract (two other agents are working in this same
worktree on the per-line review of these same logs right now, and the log file is a single,
globally shared path under `$HOME`, not scoped to this worktree). A `diff` confirmed the extra
line is a clean append at the end, not a discrepancy in the first 76 lines. This means the raw log
is not a stable basis for re-derivation while other sessions are active; the committed,
hash-pinned extract (`README.md`'s stated sha256, which matched the live file's hash at the moment
I first read it) is the reproducible artifact and is what the counts above are based on.

**Per-arm verdict:**

- **Whole log:** all five arms (`A`, `B2D`, `B2`, `D`, `D-L2`) have recorded at least one
  `would-deny`. Criterion 2 is **MET** for both layers over the whole-log window.
- **Layer 1, post-fix window only:** `A` and `B2D` and `D` have fired; **`B2` has not fired even
  once** since the tilde fix went live (`2026-09-14T20:41`) through the extraction on
  `2026-09-16`. Criterion 2, read strictly against *this* window alone, **fails for `B2`** —
  though the card's stated criterion is phrased over the whole log, not a rolling window, so
  whether the post-fix window is the right one to grade `B2` against is a scoping question for
  whoever flips the switch, not one this audit can settle unilaterally.

**Consequence, stated carefully (per the card's own framing at `worktree-location-guard.md:4085`
and the task instructions):** criterion 2 fails safe — a missing observation can only delay
arming, never wrongly permit it. But it cuts differently for `B2`: with only 10 lifetime
`would-deny` lines and none in the ~2-day post-fix window, `B2`'s refusal message, its "outside the
centralized store" remediation text, and its exit path have collectively been exercised far less
than `A`'s (391) or `B2D`'s (1670). An arm that has fired 10 times total is not "unproven" the way
an arm that has fired zero times would be, but it is the thinnest-evidenced of the four live
layer-1 arms, and it is also the one arm layer 2 provides **no backstop** for (per the code
comment at `worktree-guard.test.sh:1343`: "Arm B2 has no layer-2 backstop"). That combination —
least-fired arm, no second layer behind it — is worth flagging explicitly to whoever decides
whether to flip `B2` (or the whole guard) to `deny`.

## Job 4 — what criterion 2 does not establish

As the card itself already states (`worktree-location-guard.md:4085-4100`): the logs record only
what the guard **turned away**. A shape the guard cannot recognize leaves no line at all, so a
guard blind to an entire class of command produces a log that looks flawless for that class. An
arm firing proves it *can* fire and that its message and exit path are real; it says nothing about
how often it *should* have fired and silently didn't. That is what `hooks/worktree-guard.test.sh`
and `hooks/reference-transaction.test.sh` are for — they assert behavior against shapes chosen
deliberately, not shapes that happened to occur.

Checking that coverage specifically **for the arm-label dimension** (not overall guard behavior,
which the suites clearly exercise heavily) surfaced a real gap:

- **`B2D` has zero log-field-level test coverage.** `grep -c B2D hooks/worktree-guard.test.sh` is
  0. It is by far the most frequently firing arm (1670 lifetime, 74 post-fix) and every one of its
  many call sites (`deny_lexer`, `SEG_UNPARSED`, `SEG_GROUPED`, three `SEG_*` per-segment refusals,
  four `resolve_effective_repo` failure paths, plus `require_home`/`require_git` reached from the
  Bash side) is exercised for **behavior** (exit code 2, a specific stderr substring, via the
  `deny()` helper at `worktree-guard.test.sh:120-137`), but no test ever asserts that the resulting
  log line's arm field is literally `B2D`. A regression that mislabeled any of these as `A`, `B2`,
  or `D` would pass the entire suite today.
- **`B2` has the same gap.** Its behavior is well tested (e.g. `'B2 add anywhere else'` at `:737`
  and several neighbors), but again only through stderr, never through the log.
- **`D`'s ordinary deny path has the same gap.** `D40`–`D49` (`:1266-1416`) test the actual
  HEAD-move refusal thoroughly but only via stderr; only the **bypass** variant (`D50`, `:1432`)
  checks `arm D` at the log-field level.
- **`A` is the one arm with real log-field coverage** (`G1`, `G4`), and **`D-L2` has none**, though
  its single hard-coded value makes that a much lower-severity gap than the three above — there is
  no branch that could mislabel it.

This is a coverage gap in the test suite, not a defect the running code has been observed to have
— everything measured in Jobs 2 and 3 was consistent with the arm labels being attributed
correctly. It means the *specific* claim "this would-deny line came from arm X" — which is exactly
what criterion 2 depends on — currently rests on reading the code (as this report did) rather than
on any test asserting it, for three of the five live arm labels.

## What I could not verify

I did not attempt to determine whether any `would-deny` line in either log came from a
now-superseded *version* of the guard predating some other change (only the specific "does D
predate a B2/D→B2D consolidation" claim was checked, since that was the puzzle posed). Given the
guard's arm-labeling scheme has been unchanged since its very first commit (`09e30ab`), and the
committed post-fix extract's window starts strictly after `270a0b9`/PR #103 landed with a matching
file mtime, I have no reason to suspect a version-mismatch explanation for any line in the post-fix
window, but I did not separately audit every historical `D`/`B2` line in the *pre*-fix portion of
the whole log for that question — only the specific post-fix `D` line the task asked me to trace.
