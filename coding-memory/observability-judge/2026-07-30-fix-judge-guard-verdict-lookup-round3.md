# Observability Judge Verdict — judge-guard verdict lookup + chained detection (implementation, ROUND 3)

- **Date:** 2026-07-30 (ts 2026-07-30T17:44:05Z)
- **Repo:** judge-guard-fix (worktree `/Users/marksuyat/.claude/.claude/worktrees/judge-guard-fix`)
- **Branch:** `fix/judge-guard-verdict-lookup`
- **HEAD:** `772affe09568d33f5066dbfddbc98f9a212e6549`
- **Base:** `main`, merge-base `8dfe05c` — 8 files, +785/−23
- **Stage:** implementation (PR #32 already open; this verdict is audit trail, not a gate)
- **Rounds superseded:** `…-fix-judge-guard-verdict-lookup.md` (`97752e6`), `…-round2.md` (`88ccb59`)
- **Delta since round 2:** `f461f1f` (8 red tests) → `e79749a` (fix + ADR) → `772affe` (memory)
- **Design doc:** `docs/decisions/0012-judge-guard-repo-local-verdicts-and-chained-detection.md` (read in full)
- **Test command run by me:** `bash hooks/judge-guard.test.sh` → **48 passed, 0 failed** (exit 0)
- **Lint run by me:** `shellcheck -x hooks/judge-guard.sh` → exactly SC2016 (line 66) + SC2181 (line 194), as claimed

## What was changed (plain English)

The doorman (`judge-guard.sh`) stops you opening a pull request until a fresh review verdict exists
for the exact commit you're shipping. Rounds 1 and 2 taught him to hear the order when it's chained
(`git push && gh pr create`) and when it's on a second line.

This round teaches him five more accents. A backslash at the end of a line is a *continuation*, so
the two lines are glued back together before he listens — that routes it into the chain he already
understood, instead of teaching him a new phrase. Backticks are the old-fashioned way of running a
command inside another one, so they now open a new listening slot exactly like `$( )` does. `gh` may
now carry global flags before the subcommand (`gh -R owner/repo pr create`), matched as an adjacent
`pr create` pair. And `time` / `eval` / `command` / `builtin` / `exec` / `nohup` join `rtk` on the
list of words that stand in front of the real command and get stripped off, in a loop so they stack.

## Does it do what you wanted?

For the shapes it set out to close: **yes, and it is well built.** For the claim that only two limits
remain: **no — that claim is measurably too narrow, and one of the two "corrections" of round 2 is
itself wrong.**

Verified by me at this HEAD, by running the hook against ~60 hand-built command lines (not by
reading the diff):

- **Suite 48/0, re-run by me.** Every newly pinned shape genuinely blocks.
- **TDD order is real:** `f461f1f` touches only the test file (+35 lines, 8 red), `e79749a` only the
  hook + ADR. Separately revertible.
- **The mechanism claims are true.** The `\`+newline deletion really does happen before the
  newline→`;` rewrite, and the ordering really is load-bearing — I reproduced the tokenization.
- **The three false-positive probes still pass** (`gh pr list`, `echo gh pr create`, a commit message
  with a backticked phrase).

### Q1 — Is the completeness claim honest? Partly. The general disclaimer is; the specific one is not.

ADR 0012 says clearly and prominently: *"This does not make the gate exhaustive, and it must not be
read that way… Matching shell command shapes by token position cannot be made complete without
reimplementing bash's grammar… momentum guardrail, not a security boundary."* That paragraph is
honest, well placed, and does the main job.

But the very next sentence — *"Two known limits remain by design"* — is repeated verbatim in
`CODING_MEMORY.md` and `pr-tracking.md`, and it is wrong. **At this HEAD I measured eight further
shapes that still pass (exit 0), and round 2 had already enumerated most of them by name:**

| shape | exit | note |
|---|---|---|
| `PR_URL="$(gh pr create --fill)"` | **0** | the canonical way to capture a PR URL; unquoted `$( )` blocks, double-quoted does not |
| `{ gh pr create; }` | **0** | **the exact string round 2 named** — see Q4 |
| `git push && { gh pr create; }` | **0** | brace group where `gh` leads |
| `! gh pr create` | **0** | round 2 named it |
| `if true; then gh pr create; fi` | **0** | `then` occupies the command position — same class as `time`, and *more* plausible than `builtin`/`exec` |
| `for i in 1; do gh pr create; done` | **0** | `do` occupies the command position |
| `env gh pr create`, `timeout 60 gh pr create`, `stdbuf -o0 …`, `xargs gh pr create` | **0** | wrapper-list misses |
| `bash -c 'gh pr create'`, `/opt/homebrew/bin/gh pr create` | **0** | round 2 named both |

**The sixth shape you asked me to find:** `PR_URL="$(gh pr create --fill)"`. It is the one I would
rank first. The ADR's shape table lists `$(gh pr create)` under "blocked | unchanged" without
qualification, and the in-code comment says a `$(…)`-substituted invocation "is likewise caught,
since it too really runs." Both are true only for the **unquoted** spelling. I measured
`echo "$(gh pr create)"`, `url="\`gh pr create\`"` and `PR_URL="$(gh pr create --fill)"` — all exit
0, at base, at round 2, and at this HEAD. This matters more than the others because capturing the
URL into a variable is a *normal* shape of this command, not an evasion — the same argument that
justified closing the `&&` gap in the first place.

There is a precise, statable reason, and the ADR states only half of it: *inside a double-quoted
string, shlex keeps the substituted character inside the token.* The ADR cites that property as the
**false-positive protection** for backticks and newlines. It is simultaneously the **false-negative
mechanism** for every real substitution written inside double quotes. One property, two consequences;
only the flattering one is written down.

### Q2 — False-positive surface: yes, I made it fire on something it should ignore, and it is new this round.

```bash
cat > /tmp/body.md <<'EOF'
Bypass via `gh pr create` is guarded
EOF
```
→ **exit 2 (blocked).** Attributed across three HEADs: base `8dfe05c` = 0, round 2 `88ccb59` = 0,
this HEAD = **2**. The backtick→`;` translation introduced it.

A heredoc body is quoted *by the delimiter*, which shlex does not model, so its text is naked tokens.
Any heredoc line whose backticked phrase lands at a segment start now matches. The realistic victim
is **this repo's own documentation**: ADR 0012's shape table contains `` `gh pr create` `` inside a
markdown table row, and writing that table through a heredoc would be blocked. A markdown `|`
separator makes it worse, since `|` is also a segment break.

A sibling of the same class exists from round 2 and was never named either: a heredoc body line that
merely *starts* with `gh pr create` (no backticks) blocks at round 2 and at this HEAD (base = 0).

Both fail **closed**, so nothing unjudged can ship through them — this is friction, not a hole. But
note the escape hatch does not reach it: `JUDGE_EXEMPT` is parsed per-segment, and the offending
segment is the heredoc line, which cannot carry the prefix. You would have to switch tools.

**Why the round's own 16 probes could not catch this:** all three false-positive probes chosen
(`gh pr list`, `echo gh pr create`, a backticked commit message) exercise the *same* mechanism —
quoted text stays one token. Three samples of one mechanism is one sample. The heredoc class is the
first shape where the text is unquoted from shlex's point of view, and no probe covered it.

The adjacent-pair loosening (`gh -R … pr create`) I could **not** break: `gh` must still hold the
command position and quoted text is one token, so I found no false positive from it. That half is
well controlled, exactly as the commit message argues.

### Q3 — The wrapper denylist: right shape for now, but the ADR never weighs the alternative.

A denylist is defensible here, and the honest evidence is in my table above: `then`, `do`, `env`,
`timeout`, `stdbuf` are all missing while `builtin`, `exec`, `nohup` — words nobody would plausibly
write in front of `gh` — are present. The list was populated from what a review happened to name,
not from what an agent plausibly emits. That is the failure mode of a denylist, visible on day one.

The positional alternative — match an adjacent `gh pr create` **triple** anywhere in a segment
rather than requiring `gh` at position 0 — would close `time`, `env`, `timeout`, `then`, `do`, `!`,
`{`, and the wrapper class in one rule instead of an enumeration. It has a real cost, which is why I
am not calling the current choice wrong: `echo gh pr create` would then match, and that false
positive is one the current design deliberately buys the denylist to avoid.

So: the tradeoff is genuine and the chosen side is defensible. What is missing is that **ADR 0012's
"Options weighed" section was not extended for any of this round's four fixes.** The newline fix
recorded its rejected alternative (per-line split, rejected because it fails open) and that record is
exactly why round 2 could evaluate it. The wrapper list records no alternative at all, so the next
reader cannot tell whether a positional rule was considered and rejected, or never considered.

### Q4 — Round 2's two errors: the correction mechanism is exemplary; one correction is wrong.

Loud revision beats quiet rightness, and this round does the loud part properly — the correction sits
in the commit message, `CODING_MEMORY.md`, `pr-tracking.md`, and ADR 0012 Consequences, with the
generalized lesson ("judge findings get re-measured before they are acted on"). That is the behaviour
I want to see and I want it on the record as a positive.

**But the `{ …; }` correction tested a different command than round 2 named.**

- Round 2's markdown, line 80, names: `` `{ gh pr create; }` `` — `gh` first in the group.
- The artifacts record: *"RUN 2 claimed `{ …; }` bypasses and it does not"*, and the ADR table pins
  `{ git push; gh pr create; }` as blocked.

Measured at this HEAD:

```
{ gh pr create; }            -> exit 0   (round 2's exact string: BYPASS, round 2 was right)
{ git push; gh pr create; }  -> exit 2   (the string actually tested: blocks)
git push && { gh pr create; } -> exit 0  (also bypass)
```

The two differ because `{` occupies the command slot of the first segment; when `gh` leads the group
it never reaches position 0. So a correct finding was overturned on evidence about a neighbouring
string, and the erroneous overturn is now recorded as settled fact in four places. A later reader
following the audit trail will conclude brace groups are covered. They are not.

The `time`/`eval` half of the correction is fully verified and correct — round 2 did list them (under
its item 3) but ranked them out of scope, and closing them was right.

### Q5 — Carried concerns: does the enlarged change move any of them?

- **Classifier fails OPEN, silently — unmoved, re-proved at this HEAD.** A stub interpreter that
  fails only the classify call makes a bare `gh pr create` with no verdict store exit **0**, with
  empty stderr. Round 2's reasoning for deferring (fail-closed here would block *every* Bash command
  on a classifier hiccup) still holds and I endorse it. What *has* moved: the classifier grew three
  more string operations and a second loop this round, so the surface that can throw grew while the
  handler (`except ValueError` + `2>/dev/null`) did not.
- **Python ≥3.6 requirement on a fail-open path while still falling back to plain `python` —
  unmoved.** Still undisclosed in the ADR; the PR body does disclose it (and disclosed it well).
- **Gate reads the working-tree verdict file — unmoved, and still correctly NOT-A-DEFECT** (strict
  freshness makes a committed-blob requirement unsatisfiable by construction).
- **`git-guard.sh` / `merge-guard.sh` share the chained gap — moved, and worse.** `merge-guard.sh`
  still does `shlex.split` + `toks[0]`. Three hooks now advertise the same "momentum guardrail"
  tradeoff with materially different reach: judge-guard understands continuations, backticks,
  wrappers and segments; the other two understand none of it. The divergence roughly doubled this
  round and there is still no opened follow-up.

### The apostrophe trap: documentation is a disproven control, not a sufficient one.

The evidence is in this round's own record. After the first incident, the control installed was a
comment inside the block: `# NOTE: no apostrophes in this block`. The second incident happened
**inside the very block carrying that comment**, while editing it, and cost 22 spurious test
failures. A control that fails on its first live test is not a control — it is a note.

`shellcheck -x` is the thing that actually worked, twice, in one line. The durable fix is to make the
class impossible: extract the classifier to `hooks/lib/classify-pr-command.py`. That removes the
quoting trap permanently, shrinks the hook, and — the part I care about most as a judge — makes the
classifier **directly unit-testable**. Every probe in this verdict and every case in the 48-test
suite has to drive the whole hook (JSON payload, git repo fixture, verdict store) to assert one
tokenization fact. That is why bypass shapes keep being found by ad-hoc probing instead of by the
suite. It is a refactor and correctly out of scope for this branch; it should be the next task, paired
with the git-guard/merge-guard alignment, since all three hooks embed the same style of block.

### One stale artifact worth fixing before merge

**PR #32's body has not been updated for this round.** It still says `bash hooks/judge-guard.test.sh
# 32 passed, 0 failed`, still presents the four now-closed shapes in a table headed "**passes —
bypass**", and still pins the review verdict to `88ccb59`. A reviewer reading the PR sees a change
description contradicted by the shipped code in both directions.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | concern | All five named shapes verified closed and the mechanisms are as described; but one shape round 2 correctly reported (`{ gh pr create; }`) was dismissed as a non-defect on evidence from a different command string, so a reported defect was closed without being fixed |
| execution | concern | Suite 48/0 and shellcheck re-run by me and matching the claim; but a new false positive shipped untested (heredoc body with a backticked phrase: base 0 → round 2 0 → this HEAD **2**), and eight shapes still pass, including `PR_URL="$(gh pr create)"` and `{ gh pr create; }` |
| trajectory | concern | Genuinely strong reasoning — TDD red→green in separate commits, each fix removes a special case, the `\`+newline-before-translation ordering is a real insight and is explained where it is load-bearing. Marked down because the round's own stated virtue is "I measure, I don't infer," and the one measurement that overturned a prior judge's finding was of the wrong string; the 16 probes also sampled one false-positive mechanism three times |
| regression | concern | Diff confined to hook + tests + ADR + memory + pr-tracking; all pre-existing tests still green. One behavioural regression, proved by bisecting the hook across three HEADs: the backtick→`;` translation newly blocks a heredoc body mentioning the phrase. Fails **closed**, so it cannot leak unjudged code — friction, not a hole |
| context_budget | pass | Hook code and docs, not always-on context. No rule or skill text added; +39 lines to CODING_MEMORY's Active Session block, which is that file's purpose |
| traceability | concern | ADR/commits/comments explain every mechanism and the load-bearing ordering — above average. But "Two known limits remain by design" understates by eight measured shapes; the `$(…)`-is-caught claim is true only unquoted; and "Options weighed" was not extended for any of this round's four fixes, so the denylist has no recorded rejected alternative |
| success_masking | concern | 48 green tests coexist with eight verified bypasses, one new false positive, and a classifier fail-open no test asserts (re-proved here with a stub interpreter: exit 0, silent stderr). The suite's false-positive cases all exercise the single "quoted text is one token" mechanism, so they are structurally blind to the heredoc class |
| intent_drift | pass | No drive-bys, no new dependencies (stdlib `shlex`/`re` only), pre-existing shellcheck findings correctly left alone, sibling hooks deliberately deferred with a stated reason. The batch was explicitly user-authorized, and batching over splitting is justified in the record |
| checkpoint | pass | Three commits — test-only, then fix+ADR, then memory — separately revertible, clean working tree apart from this judge's own artifacts |
| audit_trail | concern | Attributable and unusually thorough; the *mechanism* of loud revision is exemplary and worth keeping. Two defects: the round-2 `{ …; }` correction is itself wrong and is now recorded as fact in four places, and PR #32's body is stale (says 32 tests, lists the closed shapes as open bypasses, pins `88ccb59`) |

## Roll-up

- **Risk:** medium — unchanged from rounds 1 and 2, for a different reason each time. Nothing here
  can let unjudged code ship that could not before: every open shape is pre-existing and every new
  false positive fails closed. The medium is earned by a wrong correction recorded as settled fact,
  a completeness claim narrower than the measurements, and a new false positive that shipped untested.
- **Confidence:** high — suite and lint run by me at this HEAD; every finding measured against the
  live hook and attributed by re-running base `8dfe05c`, round 2 `88ccb59`, and `772affe`.

## Concerns

1. `PR_URL="$(gh pr create --fill)"` and `` url="`gh pr create`" `` pass (exit 0) — the canonical
   URL-capture shape. ADR 0012 lists `$(gh pr create)` as blocked without the double-quote caveat,
   and the in-code comment makes the same unqualified claim. Same "quoted text stays in the token"
   property the ADR cites as false-positive protection; only the flattering half is documented.
2. The recorded correction of round 2 is wrong: `{ gh pr create; }` — round 2's exact string —
   exits 0. Only `{ git push; gh pr create; }` blocks. `git push && { gh pr create; }` also exits 0.
   The erroneous overturn is now stated in the commit message, CODING_MEMORY, pr-tracking and ADR 0012.
3. New false positive introduced this round, untested: a heredoc body containing a backticked
   `gh pr create` now blocks (base 0 → round 2 0 → this HEAD 2), including this repo's own ADR text
   written through a heredoc. A sibling from round 2 (heredoc line starting with the bare phrase)
   is also unnamed. Both fail closed, and `JUDGE_EXEMPT` cannot reach the offending segment.
4. "Two known limits remain by design" (ADR, CODING_MEMORY, pr-tracking) understates by eight
   measured shapes, several of which round 2 enumerated by name: `!`, `if…then`, `for…do`, `env`,
   `timeout`, `bash -c`, absolute path, brace-group-with-gh-first. The general "not exhaustive"
   disclaimer is honest and prominent; the specific count is not.
5. The wrapper denylist was populated from what a review named, not from what an agent emits — it
   carries `builtin`/`exec`/`nohup` while missing `then`, `do`, `env`, `timeout`. The positional
   alternative (adjacent `gh pr create` triple anywhere in a segment) has a real cost
   (`echo gh pr create` would match) and the current choice is defensible, but ADR "Options weighed"
   was not extended, so no rejected alternative is on record for any of this round's four fixes.
6. Classifier failure still fails OPEN and silently — re-proved at this HEAD with a stub
   interpreter (exit 0, empty stderr). The deferral reasoning still holds, but the classifier grew
   three string ops and a second loop this round while the `except ValueError` + `2>/dev/null`
   handler did not.
7. Documentation is a disproven control for the apostrophe trap: the second incident (22 failures)
   happened inside the very block carrying the "no apostrophes" comment. Extracting the classifier
   to its own file would remove the class and make it directly unit-testable — which is also why
   bypass shapes keep being found by ad-hoc probing rather than by the suite.
8. PR #32's body is stale: it reports "32 passed, 0 failed", tables the four now-closed shapes as
   "passes — bypass", and pins the verdict to `88ccb59`.
9. `git-guard.sh` / `merge-guard.sh` divergence roughly doubled this round (merge-guard still
   `shlex.split` + `toks[0]`), with no follow-up opened. Three hooks now share one "momentum
   guardrail" phrase with materially different reach.
