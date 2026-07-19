# Observability Judge — feature/statusline-command (round 5)

- **repo:** .claude
- **branch:** feature/statusline-command
- **head_sha:** e8826597d8c4cf869bc8a2747d6a74f43eb0f1e9
- **base:** main (merge-base 54b9b265f91c7b259e29f8193c9c589005e3eec5)
- **stage:** implementation
- **ts:** 2026-07-19T19:20:30Z
- **risk:** medium — **confidence:** high
- **round 1:** `2026-07-19-feature-statusline-command.md` @ f0902ed (low/medium)
- **round 2:** `2026-07-19-feature-statusline-command-round2.md` @ c06737b (low/high)
- **round 3:** `2026-07-19-feature-statusline-command-round3.md` @ 29d6131 (low/high)
- **round 4:** `2026-07-19-feature-statusline-command-round4.md` @ 4d63b09 (low/high)

> Filename note: continues the `-roundN` suffix precedent so rounds 1-4 survive in the working
> tree rather than only in git history.

## Headline — not ready to open a PR

**The commit that was meant to close round 4's findings introduced a new terminal-escape leak,
and no test in the suite can see it.** The fix for finding #2 re-checks for an empty `cwd` after
the strip and then assigns `$PWD` — *unstripped*. That is the identical mistake round 3 found at
the first fallback, repeated five lines below it, inside the commit that was supposed to be the
last one.

```bash
[ -z "$cwd" ] && cwd="$PWD"    # line 35 — then stripped by line 36. Correct.
cwd="${cwd//[[:cntrl:]]/}"     # line 36
[ -z "$cwd" ] && cwd="$PWD"    # line 40 — NEW. Nothing strips this.
```

I reproduced it. With a payload whose `cwd` is nothing but control bytes, run from a directory
whose name carries an OSC sequence, the bytes `ESC ] 0 ; HIJACK BEL evil` reach the terminal
intact — `bel=1`, and the raw output literally contains `\x1b]0;HIJACK\x07evil`. Round 4 measured
this exact input at `4d63b09` as **esc=6, bel=0 — clean**. So this commit turned a path the
previous judge round verified as leak-free into a leaking one.

Severity of the leak itself is genuinely tiny, and I want to be precise rather than alarming:
line 40 only fires when `cwd` is non-empty but strips to empty, i.e. a string of pure control
bytes. Any real absolute path keeps its `/` characters and survives stripping, so **Claude Code
cannot produce an input that reaches this line.** It needs a hand-crafted payload. The code risk
alone would be low.

What raises this to medium is the other two facts: the suite cannot detect it, and the permanent
record now states the opposite.

## What was changed

Three round-4 leftovers were addressed in one commit (`e882659`):

1. `user` and `host` are now stripped of control bytes. **This one is correct** — I re-ran round
   4's `PATH`-shim attack (hostile `whoami` and `hostname -s` emitting a blink SGR and an OSC
   title-rewrite) and the control bytes are gone: `esc=6, bel=0` against a baseline of 8. The
   hijack round 4 demonstrated is genuinely closed.
2. The empty-`cwd` check now runs again after the strip. **This one is defective**, as above.
3. The falsification harness is committed as `statusline-command.falsify.py`. **Correct and
   genuinely useful** — it asserts an expected pass count per version rather than printing them,
   so an assertion that becomes unfalsifiable fails the run.

Stale counts in `CODING_MEMORY.md` and the branch log were partly corrected.

## Does it do what was asked

Two of three fixes, yes. The third is wrong, and the docs requirement — the caller's stated top
priority — is not met.

**Falsification, independently reproduced.** I did not reuse the committed harness. Mine shells
out to `/usr/bin/git cat-file blob` from Python, asserts each blob starts with `#!`, and
recomputes the git blob SHA locally to compare against `git rev-parse <rev>:<path>`, so a
substituted or truncated blob cannot pass. My numbers and the committed harness's agree exactly:

| Version | Blob | Passes |
|---|---|---|
| `f0902ed` | `ce854930` | 8/19 |
| `925c310` | `d28a0895` | 9/19 |
| `c06737b` | `d28a0895` | 9/19 (shares blob — settings-only commit, correct) |
| `29d6131` | `e30dcd0a` | 15/19 |
| `4d63b09` | `b5a07163` | **19/19** |
| `e882659` (HEAD) | `4b6be5a9` | **19/19** |
| worktree | `4b6be5a9` | 19/19 — identical to HEAD |

The harness is honest and well built. But look at the last two rows: **`4d63b09` and HEAD both
score 19/19.** The suite contains no assertion that can distinguish the commit under review from
its parent. All three of this commit's changes are invisible to it — and the one that is broken
is the one it cannot see. The harness prints `falsification intact` and exits 0 while certifying
a commit it structurally cannot evaluate.

The harness's own `EXPECTED` map stops at `4d63b09`; HEAD is covered only by the "working tree
must pass everything" sanity floor, which by construction cannot fail for a defect no assertion
covers.

## Docs vs. code — the exact check that was asked for

Requested: confirm the docs match the code **exactly**. They do not. Eleven discrepancies, of
which the first is a false statement about security behaviour:

1. **Branch log line 167 and the `e882659` commit message both say the all-control-`cwd` case is
   "Cosmetic, no leak."** After this commit it *is* a leak — demonstrated above. The permanent
   record asserts the opposite of the code's behaviour. Fifth consecutive round of a write-up
   over-claiming a security property.
2. **`statusline-command.sh` line 15** still says *"Every value below originates outside this
   script, so each is stripped."* `$PWD` at line 40 is external and unstripped. Round 4 asked for
   this claim to be made true "without a carve-out"; the same commit that stripped `user`/`host`
   to honour it introduced a fresh violation of it.
3. **Branch log line 181: "Four commits on the branch."** There are five.
4. **Branch log line 186: commit 4 still carries no SHA** (`4d63b09`) — round 4's finding #4,
   not fixed. Commit 5 (`e882659`) is absent from the list entirely.
5. **Branch log line 188: "Observability judge ran three rounds"** — the table immediately below
   it lists four. The file contradicts itself, structurally the same defect as round 4's
   "15 vs 19 assertions".
6. **Branch log line 171: "identical result for all three versions"** — four were tested. Round
   4's finding #5, not fixed.
7. **Branch log line 176 still cites `scratchpad/falsify.py`**, which does not exist. Line 154
   correctly names `statusline-command.falsify.py`, so the same file cites both the real path and
   the phantom one. Round 4's finding #3, only half fixed.
8. **`CODING_MEMORY.md` line 94: "the write-up ran ahead of the code three rounds running"** —
   the branch log line 197 says four. The two permanent records disagree, and four is correct.
9. **`statusline-command.falsify.py` line 16: `Run: python3 statusline-command.falsify.sh`** —
   wrong extension; the file is `.py`. Copy the line and it fails.
10. **The falsify docstring claims it "checks each one fails exactly the assertions covering the
    defect it still carries."** It only compares pass *counts*; it never checks *which*
    assertions failed. A compensating pair of failures would pass.
11. **README** gained a row for `statusline-command.sh` but not for `statusline-command.falsify.py`,
    now a tracked top-level file. Every other top-level tracked file has a row.

Corrections that did land: the "15 assertions" and "8/15 / 9/15" counts are fixed in both files,
and `CODING_MEMORY.md` now says "4 rounds" in the sentence the caller flagged.

## Commit partition and staging — clean

This part is exactly right, and the caller's phrasing needs one correction. `settings.json` **does**
appear in the committed diff — legitimately, in `925c310` (the `statusLine` block) and `c06737b`
(model + theme). What must not appear, and does not, is the **Orca hook block**. I verified the
committed `settings.json` at HEAD contains zero occurrences of `orca` and only the four
pre-existing guard hooks; the 112-line Orca addition sits entirely in the unstaged working tree
(`M settings.json`, 10 `orca` matches). Nothing unintended is staged. Five commits partition
cleanly with no file-level overlap.

## Scope — yes, this has overrun, and it should go to the user

The user asked to document and push a status line they had already written. That has become:

- 5 commits, 4 of them judge-driven
- 113 lines of deliverable vs. 276 lines of test + falsification harness
- a 205-line branch log and ~600 lines of verdict files — **1,230 insertions total**

Rounds 1-2 were unambiguously worth it: they found a real escape-injection defect reachable from
an untrusted repo's directory name. That is in scope for "ship this safely."

Rounds 3-5 have been chasing progressively narrower variants, and the trend is the point. Round 3
needed a hostile directory name plus one of four routine stdin shapes. Round 4's `user`/`host`
needed control of the hostname or `PATH` — by its own assessment "already game over". Round 5's
line-40 path needs a payload Claude Code is structurally incapable of sending. Each fix has been
cheaper than the argument about it, but each has also been an unreviewed change to a script the
user wrote, and **this round the ratchet actually made the code worse.** That is the strongest
possible argument for stopping.

My recommendation: fix line 40 (one strip), correct the eleven doc items, and stop. Do not open
round 6 over anything narrower than what is already known.

## What I'd double-check before merging

1. **Strip after line 40** — `cwd="${cwd//[[:cntrl:]]/}"` once more, or simplest: drop line 40
   entirely and instead guard the git block with `[ -n "$cwd" ]`, since `git -C ""` was the only
   reason line 40 exists. One line either way.
2. **Add one assertion covering it**, so the commit stops being invisible to the suite. Then add
   `e882659` (or its successor) to the falsify `EXPECTED` map with a pass count of 20 — otherwise
   the harness will keep certifying HEAD without testing it.
3. **Fix the eleven doc items**, starting with the two that state "Cosmetic, no leak" and the
   line-15 comment. A record that misstates a security property is worse than a known gap.
4. **Take the scope question to the user** before round 6.

## Verification I ran myself

Nothing below is taken from the report on faith.

- **Independent falsification:** own Python harness, `git cat-file blob`, `#!` prefix check,
  `git rev-parse` object-id match, and locally recomputed `sha1("blob <len>\0" + content)` per
  blob. Six revisions + worktree. Numbers match the committed harness exactly; five distinct
  blobs; worktree blob `4b6be5a9` == `HEAD:statusline-command.sh`.
- **Committed harness re-run:** `python3 statusline-command.falsify.py` → all rows `ok`,
  `falsification intact`, exit 0. Suite direct → 19/19, exit 0.
- **Leak reproduction (probe A):** payload `{"cwd": "\x1b\x07\r\x01"}` executed from a directory
  named `<ESC>]0;HIJACK<BEL>evil` → `esc=7, bel=1`, raw output contains the intact OSC sequence.
  Control (probe B): same directory, `{}` on stdin → `esc=6, bel=0`, clean — confirming line 35's
  path is fine and isolating the defect to line 40.
- **`user`/`host` fix confirmed (probe C):** `PATH` shim with hostile `whoami` (`ESC[5mroot`) and
  `hostname` (`ESC]0;VIAHOST BEL box`) → `esc=6, bel=0`. Round 4's demonstrated hijack is closed.
- **Coverage gap:** `4d63b09` and `e882659` both 19/19 — no assertion distinguishes them.
- **Commit partition, per file:** five commits, no overlap. Committed `settings.json` at HEAD has
  0 `orca` matches and retains all four guard hooks; Orca's 112 lines are unstaged only.
- **Regression:** `hooks/memsearch-nudge.test.sh` PASS, `hooks/judge-guard.test.sh` PASS.
  `bash -n` clean on both shell files, `py_compile` clean on the harness, all three mode 100755,
  worktree `settings.json` parses.
- **Byte hygiene:** zero non-newline control bytes in the script, test, harness, and branch log.
- **State:** nothing pushed, no remote branch, no PR.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | concern | Fixes 1 and 3 landed and are correct — the `user`/`host` strip provably closes round 4's demonstrated `PATH`-shim hijack, and the harness is committed and well designed. Fix 2 is defective, and the caller's explicitly stated top priority (docs matching code exactly) is not met on eleven counts. |
| execution | concern | 19/19 independently confirmed with hash-verified blobs; falsification numbers exact across six revisions; sibling suites pass. But the commit under review introduces a reproducible escape leak at line 40 that did not exist at its parent. Not `fail` only because the path is unreachable from any input Claude Code can generate. |
| trajectory | concern | The reasoning repeated, five lines apart and in the same commit, the exact defect round 3 identified — assigning `$PWD` without stripping it. The commit message asserts "Cosmetic, no leak" without re-probing after the change, and no falsification was run against the new commit. Committing the harness and stripping `user`/`host` were the right calls; the self-check that would have caught the regression was not performed. Downgraded from round 4. |
| regression | concern | Adjacent breakage introduced by this change: round 4 measured the all-control-`cwd` input at `4d63b09` as `esc=6, bel=0`; at HEAD the same input yields `bel=1` with an intact OSC sequence. Partition, hooks, modes, syntax and sibling suites are all clean. Downgraded from round 4. |
| context_budget | pass | No always-on rule or prompt growth. Branch log, test and harness are on-demand. README +1 row (though the new harness file is missing its row). |
| traceability | fail | Two permanent records — branch log line 167 and the `e882659` commit message — state "Cosmetic, no leak" about a path that now leaks. Script line 15 still claims every external value is stripped while line 40 does not. Branch log self-contradicts (three rounds vs. a four-row table; "Four commits" vs. five), still cites the phantom `scratchpad/falsify.py`, still says "all three versions", still omits commit 4's SHA and commit 5 entirely; `CODING_MEMORY.md` says "three rounds running" where the branch log says four; the harness docstring gives the wrong filename and over-claims what it checks. Two of round 4's four itemized findings are unfixed and new ones were added. Fifth consecutive round; escalated from concern. |
| success_masking | fail | The clearest instance yet. `19/19` and `falsification intact` both report green on a commit whose three changes no assertion can distinguish from its parent — `4d63b09` and HEAD score identically — and one of those unseen changes is broken. The harness's `EXPECTED` map stops before HEAD, so the only check covering it is a sanity floor that cannot fail for an uncovered defect. Green certifying the untested. Downgraded from round 4. |
| intent_drift | concern | The Orca `settings.json` block was correctly left uncommitted — verified, zero `orca` in the committed file. No new dependencies, `chrome/` drive-by still declined. But the brief was "document and push an existing script": 4 of 5 commits are judge-driven, test+harness (276 lines) now exceed the deliverable (113 lines), and rounds 3-5 modified the user's script three times without re-consulting them. Round 5 made the code worse. Surfacing per the caller's own request. |
| checkpoint | pass | Five coherent commits, each independently revertible and standalone-meaningful; partition verified per file; nothing pushed; `4d63b09` is a clean revert target if the line-40 change is backed out. |
| audit_trail | concern | Attributable; rounds 1-4 preserved via `-roundN`; `Doc-Exempt` trailer used appropriately; no-ADR call still correct (presentation-only). Undercut by a false security claim ("Cosmetic, no leak") and a missing commit SHA entering the permanent record. |

## Concerns

- Line 40's new `[ -z "$cwd" ] && cwd="$PWD"` assigns `$PWD` unstripped — reproduced an intact `ESC ] 0 ; HIJACK BEL` OSC sequence reaching the terminal (`bel=1`); the same input measured clean (`bel=0`) at `4d63b09`, so this commit regressed a previously-verified path
- Identical defect to the one round 3 found, reintroduced five lines below it in the commit meant to be final
- `4d63b09` and HEAD both score 19/19 — no assertion distinguishes them, so all three of this commit's changes are untested and the harness prints "falsification intact" over a commit it cannot evaluate
- Falsify `EXPECTED` map stops at `4d63b09`; HEAD is covered only by a sanity floor that cannot fail for an uncovered defect
- Branch log line 167 and the `e882659` commit message both say "Cosmetic, no leak" about a path that now leaks — a false security claim in the permanent record
- Script line 15 still claims every external value is stripped; `$PWD` at line 40 is external and unstripped — fifth consecutive round of this over-claim
- Branch log says "Four commits on the branch"; there are five, and commit 5 is absent from the list
- Branch log commit 4 still lacks its SHA (`4d63b09`) — round 4 finding, unfixed
- Branch log line 188 says "three rounds" while the table below lists four — self-contradiction, same shape as round 4's 15-vs-19
- Branch log line 176 still cites `scratchpad/falsify.py`, which does not exist, while line 154 cites the real committed path — round 4 finding, half fixed
- Branch log line 171 still says "all three versions"; four were tested — round 4 finding, unfixed
- `CODING_MEMORY.md` says "three rounds running"; the branch log says four — the two records disagree
- `statusline-command.falsify.py` line 16 says `Run: python3 statusline-command.falsify.sh` — wrong extension
- Falsify docstring claims it checks *which* assertions fail; it only compares pass counts, so compensating failures would pass
- README omits a row for `statusline-command.falsify.py`, now a tracked top-level file
- Scope: user asked to "document and push"; 4 of 5 commits are judge-driven, 1,230 insertions for a 113-line script, and the user's script was modified three times across rounds 3-5 without re-consultation
- Cosmetic, unchanged: `1e400` renders `infk tokens`, `not-a-number` renders `0.0k tokens`, no bound on rendered line length
- `✗` dirty marker still permanently lit because `chrome/` stays untracked, compounded by the uncommitted Orca `settings.json` block
- Committing this verdict moves HEAD and re-stales judge-guard's strict check, forcing a round 6 before `gh pr create`

## Advisory — Orca `settings.json` write (NOT part of this diff, not judged)

Unchanged from round 4 and still correctly uncommitted; re-verified this round that the committed
`settings.json` contains zero `orca` references and all four guard hooks remain registered. The
round-4 advisory stands: `claude-hook.sh` line 10 sources `$ORCA_AGENT_HOOK_ENDPOINT` *before* the
`ORCA_*` gate on line 12, and only stderr is redirected — so the sourced file's stdout becomes a
`PreToolUse` hook's stdout, which can block or alter a tool call. Worth raising with the user
independently of this branch.
