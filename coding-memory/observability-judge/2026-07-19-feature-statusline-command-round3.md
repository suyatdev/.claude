# Observability Judge — feature/statusline-command (round 3)

- **repo:** .claude
- **branch:** feature/statusline-command
- **head_sha:** 29d61313f64a2f3968e3f61404d793ab7cdcdea4
- **base:** main (merge-base 54b9b265f91c7b259e29f8193c9c589005e3eec5)
- **stage:** implementation
- **ts:** 2026-07-19T19:00:42Z
- **risk:** low — **confidence:** high
- **round 1:** `2026-07-19-feature-statusline-command.md` @ f0902ed (low/medium)
- **round 2:** `2026-07-19-feature-statusline-command-round2.md` @ c06737b (low/high)

> Filename note: continues the `-roundN` suffix precedent so rounds 1 and 2 survive in the
> working tree rather than only in git history.

## What was changed

Since round 2, the half-finished escape fix was finished and a real test suite was added.

The status line script now strips control characters out of all four values that come from
outside it (directory, model name, token count, branch) using plain bash text replacement. That
closes the door round 2 found open: a real escape byte smuggled in through a JSON ``
sequence used to walk straight through to the terminal. A new `statusline-command.test.sh` with
15 assertions now guards this, and the docs were corrected.

## Does it do what was asked

Yes, and the method used to get there is the strongest thing in this change.

I re-ran the falsification myself against all three versions of the script and got **exactly the
claimed numbers**: `f0902ed` → 8/15, `925c310` → 9/15, current → **15/15**. The middle row is the
one that matters and it holds up: `925c310` is the state round 1 called clean, and this suite
fails it on five assertions.

More important than the counts: **every one of the seven injection assertions fails against at
least one unfixed script.** That is empirical proof they aren't passing vacuously — a test that
can't fail proves nothing, and these demonstrably can. This is the right way to validate a
harness and it is not common practice.

Both files are byte-level clean. I scanned them with `od`: the only byte below 32 in either file
is newline, no DEL, and every high byte is legitimate UTF-8 (`✗`, `│`, `➜`, `—`). All 11 test
payloads parse under `jq` — I checked each one individually — and the route-2 payloads decode to
1–2 genuine control bytes each. The self-reported contamination really was repaired.

Two claims I checked and can confirm: no fork was added (12 command substitutions before and
after, ~50 ms/render both), and `${v//[[:cntrl:]]/}` actually strips more than advertised — it
removes C1 controls like U+009B CSI too, which the comment doesn't claim credit for.

## What could go wrong

**One injection door is still open, and the suite doesn't cover it.** The strip runs on line 31;
the `$PWD` fallback runs on line 32:

```bash
cwd="${cwd//[[:cntrl:]]/}"     # line 31 — strips
[ -z "$cwd" ] && cwd="$PWD"    # line 32 — assigns unstripped
```

So when the JSON carries no usable directory, `$PWD` is used raw. I reproduced the full original
symptom through it — from a directory whose name contains an OSC sequence, with `{}` on stdin,
the bytes `ESC ] 0 ; H I J A C K BEL` arrive at the terminal intact. That is the *exact* sequence
the suite asserts is stripped, entering through a door the suite never knocks on. Four stdin
shapes reach it: `{}`, non-JSON, `{"cwd":null}`, `{"workspace":{}}` — and round 1 already
observed that malformed stdin genuinely falls back this way.

Think of it as fitting locks to the front, back and side doors, testing all three, and leaving
the cellar hatch — the one you only use when the front door jams — unbolted.

Severity stays low: it needs the user's shell to be sitting in a hostile directory name *and*
stdin to arrive without a cwd. Worst case is still a garbled bar or a hijacked terminal title —
no execution, no data loss. The fix is swapping two lines.

**This is the third round in a row where the write-up ran ahead of the code.** The script comment
says "Every value below originates outside this script, so each is stripped"; the branch log says
"stripping C0 controls and DEL from every externally-sourced value". `$PWD` is externally sourced
and is not stripped. Smaller: the branch log's Checkpoint section still says "Two commits" when
there are three, and doesn't mention the round-3 fix commit or the round-2 verdict.

## What I'd double-check before merging

1. **Move the strip below the `$PWD` fallback** (or strip again after it) and add one assertion
   covering the no-cwd path. One line of code, one test. Until then, soften the two "every
   external value" claims — a wrong record is worse than a known gap.
2. **Update the branch log Checkpoint** from "Two commits" to three, and mention `29d6131`.
3. Note for the record: this branch has **three** commits, not four. The partition itself is
   clean — I verified `925c310` carries only the `statusLine` block, `c06737b` only model+theme,
   `29d6131` only the fix and harness.

## Verification I ran myself

Nothing below is taken from the report on faith.

- **Falsification re-run:** extracted all three blobs with `git cat-file` (verified the current
  extract's SHA matches the worktree) and ran the current suite against each: 8/15, 9/15, 15/15 —
  matches the claim exactly. First attempt gave a false 7/15 across all three because `git show
  sha:path` was intercepted by the rtk proxy and returned commit logs; caught it because the
  failure output was empty, and redid the extraction.
- **Non-vacuity:** all 7 Group-2 assertions fail against at least one unfixed script. The CR
  assertion fails on both unfixed versions with `esc=8 base=8 cr=1` — i.e. only the newly added
  `cr` counter catches it, confirming the reported weakness #4 was real and its fix load-bearing.
- **Byte scan:** `od` histogram of both files — only byte 0x0a below 32, no 0x7f. High bytes are
  valid UTF-8 glyphs. (Validated my `grep -P` with a positive control before trusting it.)
- **Payloads:** all 11 extracted from the test file parse under `jq -e`; route-2 payloads decode
  to real control bytes (OSC = 2, ESC/CR/NL = 1 each), literal-`\x1b` payload = 0, as intended.
- **Residual hunt:** `$PWD` fallback confirmed open (4 stdin shapes, OSC reproduced end-to-end).
  C1 controls confirmed *stripped* both in isolation and through the full JSON path. awk token
  path confirmed leak-proof — `\033[5m`, `1e400`, a 21-digit number, `0;rm -rf /` and `-v x=1`
  all render as plain numbers with no surplus control bytes. `user`/`host` are unstripped but
  come from `whoami`/`hostname -s`, outside the threat model.
- **Regression:** `hooks/memsearch-nudge.test.sh` and `hooks/judge-guard.test.sh` both PASS.
  `settings.json` valid, `hooks/` untouched, both scripts mode 100755, `bash -n` clean, no
  `eval`/backticks, no `printf %b` outside a comment.
- **State:** nothing pushed, no remote branch, working tree carries only untracked `chrome/`.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Round 2's central finding genuinely closed for the JSON route; harness added after re-consulting the user with new evidence; docs corrected. |
| execution | concern | 15/15 verified independently and the falsification numbers are exact; but a reproducible injection path remains via the unstripped `$PWD` fallback, uncovered by the suite. Low severity, one-line fix. |
| trajectory | pass | Best round of the three. Validated the harness by falsification rather than by passing, discovered two real weaknesses in its own tests that way, self-reported the control-byte contamination, and reversed a user decision by returning with evidence instead of acting unilaterally. Reasoning, not luck. |
| regression | pass | Both sibling suites pass; settings partition verified per-commit; hooks untouched; modes correct; render timing unchanged at ~50 ms; no added fork. |
| context_budget | pass | No always-on rule or prompt growth. Test file is on-demand; README +1 clause. |
| traceability | concern | Branch log is strong and honest about residual risk. Undercut by two claims that every external value is stripped (false for `$PWD`) and a stale "Two commits" checkpoint. Third consecutive round where docs assert more than the code does. |
| success_masking | concern | A green 15/15 coexists with an open path in the exact defect class the suite exists to close — the suite never exercises the no-cwd fallback. Materially better than rounds 1-2 (assertions now provably falsifiable), but the coverage gap is real. `render()` also swallows stderr, hiding jq parse errors. |
| intent_drift | pass | Harness reversal was user-approved after being re-presented with evidence, not a unilateral scope grab. No new dependencies. `chrome/` drive-by still declined. Fix commit stays on-topic. |
| checkpoint | pass | Three coherent commits, each independently revertible and standalone-meaningful; nothing pushed; clean partition verified per-file. |
| audit_trail | pass | Attributable; rounds 1-2 preserved via the `-roundN` convention; no-ADR call still correct (presentation-only). |

## Concerns

- `$PWD` fallback (line 32) is assigned *after* the strip on line 31, so an unstripped directory name reaches the terminal — OSC title-hijack reproduced end-to-end via `{}` on stdin
- Four stdin shapes reach that fallback (`{}`, non-JSON, `{"cwd":null}`, `{"workspace":{}}`); the test suite exercises none of them
- Script comment ("Every value below ... each is stripped") and branch log ("every externally-sourced value") both over-claim — `$PWD` is external and unstripped
- Branch log Checkpoint says "Two commits"; the branch has three, and it omits `29d6131` and the round-2 verdict
- Caller's summary says "four commits"; there are three on the branch (the fourth is `54b9b26`, an unrelated commit on `main`)
- `render()` in the test harness discards stderr, so jq parse errors during a test run are invisible
- Cosmetic, unchanged from round 2: `1e400` renders `infk tokens`; no bound on rendered line length
- `✗` dirty marker still permanently lit because `chrome/` stays untracked (flagged, undecided)
- Committing this verdict moves HEAD and re-stales judge-guard's strict check, forcing a round 4 before `gh pr create`
