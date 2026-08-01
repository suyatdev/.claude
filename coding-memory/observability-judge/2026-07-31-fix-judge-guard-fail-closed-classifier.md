# Observability verdict — fix/judge-guard-fail-closed-classifier

- **repo:** `jg-failclosed` (worktree of `~/.claude`; `basename $(git rev-parse --show-toplevel)`, the
  same identity `judge-guard.sh` itself derives)
- **branch:** `fix/judge-guard-fail-closed-classifier`
- **head_sha:** `bd2621cfab719b62035a165df49c78baf2e9e90a`
- **stage:** implementation
- **base:** `2b8564b68f38e242c39b3cce368c41a81859cc3e` (merge-base with `origin/main`)
- **ts:** 2026-07-31T05:39:00Z
- **risk:** medium · **confidence:** high

---

## What was changed

The repo has a tripwire that stops the assistant from opening a pull request until a reviewer
(this judge) has signed off on exactly the code being shipped. Last month that tripwire's
"is this a PR command?" logic was moved out of the main script into a separate helper file.

Moving it created a new way to break it that couldn't exist before: **the helper file can go
missing.** And when it went missing, the tripwire didn't complain — it just quietly waved
everything through. Like moving your smoke detector's battery into a separate drawer, and the
detector's green light staying on when the drawer is empty.

This branch makes the missing-helper case stop everything instead. Six commits: a failing test
first, then the fix, then 48 unit tests for the helper, then three record-keeping commits
(backfilling old verdict outcomes, retracting a claim the author had got wrong, and a memory-file
update).

## Does it do what you wanted?

**For the exact case it names, yes — and I verified it myself rather than taking it on trust.**

- Both suites green at this commit: `57 passed, 0 failed` and `48 passed, 0 failed`.
- The test-first claim is real. I checked out the "red" commit, swapped in the *old* script, and
  got `53 passed, 3 failed` — the three new assertions and nothing else. Same suite against the
  fixed script: `56 passed, 0 failed`.
- I reproduced the original defect directly: with the helper absent, the old script exited `0`
  with an empty error stream for both `gh pr create` **and** an unrelated `git status`. The gate
  really was dead and silent.
- `shellcheck -x` shows only the two pre-existing informational findings (SC2181, SC2016) named
  in earlier verdicts. No new lint.

**But the fix covers one of five ways the helper can be broken.** See F1 — this is the finding
that sets the risk level.

## What could go wrong / what I'm unsure about

### F1 — The fail-closed guard checks "does the file exist", not "did it work" *(headline)*

I built five broken installs and fed each a `gh pr create`:

| helper state | exit | stderr | gate |
| --- | --- | --- | --- |
| absent | 2 | names the path | **closed** ✅ |
| dangling symlink | 2 | names the path | **closed** ✅ |
| a directory of that name | 2 | names the path | **closed** ✅ |
| **empty file (0 bytes)** | **0** | *(silent)* | **open** ❌ |
| **syntax error** | **0** | *(silent)* | **open** ❌ |
| **truncated mid-file** | **0** | *(silent)* | **open** ❌ |
| **unreadable (`chmod 000`)** | **0** | *(silent)* | **open** ❌ |

Four of those still exit `0` with empty stderr — a PR ships with no verdict, exactly the defect
this branch exists to remove. The author declared "a classifier *crash* fails open"; the reality
is broader, because `2>/dev/null` on line 81 swallows every one of these, including a permission
error that is not a crash at all.

This matters more than a normal deferral, because the ADR's own motivating scenario is *"a partial
checkout, or a hook copied on its own"* — and a partial checkout produces a **truncated** file at
least as readily as an absent one. The shipped guard covers the half of its own stated threat model
that is easier to test.

And the complete fix is *smaller* than the one shipped. After line 81, `kind` is either `PR`, `NO`,
or garbage. One check —

```sh
[ "$kind" = "PR" ] || [ "$kind" = "NO" ] || { printf 'judge-guard: classifier produced no usable output -- failing closed.\n' >&2; exit 2; }
```

— subsumes the `[ ! -f ]` branch and covers all five modes, at identical blast radius. Choosing the
narrow check over the general one is the questionable part of decision 1. The blocked-everything
trade itself is defensible and I would not argue against it.

### F2 — "Blocks all Bash commands" is machine-wide, and the ADR doesn't say so

`judge-guard.sh` is registered globally: `PreToolUse` / matcher `Bash` / `$HOME/.claude/hooks/judge-guard.sh`.
A missing helper therefore blocks **every Bash call, in every repo on this machine, for every
concurrent agent** — including the parallel-worktree instances `core-conduct.md` explicitly
anticipates. The ADR says "all Bash commands block until the install is repaired", which reads like
one session in one repo.

Recovery exists (the Write tool still works; the user's own terminal is unaffected), but the
obvious repair — `git checkout -- hooks/lib/` — is precisely what's denied, and the error message
says "Restore it (hooks/lib/)" without naming a route that still functions. Reconstructing the
helper by hand from memory risks a subtly different classifier. One clause in that message would
fix this.

### F3 — The one property the code calls load-bearing is the one the tests don't pin

I ran 11 mutations against the 48-case suite. **Eight were caught**, which is genuinely good — this
suite pins behaviour, it does not restate the implementation:

| mutation | result |
| --- | --- |
| drop `{`/`}` from `OPS` | 47/1 ✅ |
| shrink `WRAPPERS` to `("rtk",)` | 44/4 ✅ |
| drop backslash-continuation handling | 47/1 ✅ |
| drop newline→`;` translation | 46/2 ✅ |
| `punctuation_chars=False` | 40/8 ✅ |
| drop the `create` requirement | 46/2 ✅ |
| `rest[0] == "gh"` → `"gh" in rest` | 43/5 ✅ |
| drop env-assignment skipping | 42/6 ✅ |
| drop wrapper stripping | 43/5 ✅ |
| flip the `ValueError` fail-open | 47/1 ✅ |
| **drop the adjacency requirement** | **48/0** ❌ |
| **`JUDGE_EXEMPT` → `endswith("EXEMPT")`** | **48/0** ❌ |
| **drop exempt-value newline normalisation** | **48/0** ❌ |

The adjacency gap is the notable one. The comment at line 100 states adjacency is what *"keeps the
false-positive surface narrow"*. With adjacency dropped, the suite stays at **48/0** while
`gh pr list --search create` starts classifying as `PR` — a false positive that blocks legitimate
work, shipped green. The suite's stated purpose is to make closing an open shape a conscious
decision; the same protection is absent for the property that prevents over-blocking.

The two minor ones: `MERGE_EXEMPT=x gh pr create` would wrongly exempt under the loosened name
match (correct today, unpinned), and the newline normalisation exists solely to protect the
two-line stdout contract the hook reads with `sed -n '2p'` — also unpinned.

### F4 — Two plausible open shapes missing from the enumerated list

`sudo gh pr create` and `xargs gh pr create` both classify `NO`. Neither appears in the ADR's
accepted-open set (`env`, `timeout`, loop keywords, quoted `eval`, backticks, variable indirection).
Not introduced here, but this is the branch that claims to enumerate the open set, and `sudo` is a
plausible spelling. Also: `JUDGE_EXEMPT=$(cat reason.txt) gh pr create` classifies `PR` with an
*empty* reason — it fails closed, so the direction is safe, but the exemption silently doesn't
apply.

### F5 — Registered, not armed

The live hook blob is `3839140`; this branch's is `71c852e`; `main`'s is `5064c3d`. The primary
`~/.claude` checkout is on `feat/pane-split-policy` and has **no `hooks/lib/` directory at all**.
None of this has run under the real harness. Ordinary branch switches are safe (checkout swaps
script and helper atomically). The risk window is any state where the new script lands *without*
`hooks/lib/` — an interrupted rebase, a partial merge, a selective copy — which is a machine-wide
Bash lockout for however long it takes to notice.

### F6 — `CODING_MEMORY.md`: 1267 → 1316 lines against its own 200-line ceiling

Line 3 states the ≤200-line cap. Line 888 flags *"This index is 778 lines against its own 200-line
ceiling"* — that self-flag is now stale by 538 lines. Flagged on multiple prior verdicts; grew
again here. The individual entries are good; the container is 6.6× its stated limit in a repo whose
subject matter is keeping records honest.

### F7 — The subsystem holds two contradictory defaults, and the deciding rule is unwritten

`judge-guard.sh:10` — *"This is a safety gate … so it fails CLOSED: any inability to verify blocks."*
The classifier's comments justify three separate fail-**open** choices with *"the wrong direction
for a momentum guardrail."* Same subsystem, opposite defaults. This change picks fail-closed for
one inability-to-verify and leaves four fail-open. Which framing governs which code path is
decided case by case and written down nowhere.

### Carried, verified as stated rather than rediscovered

`python3` with no `python` fallback on the classifier path; the gate reads the **working-tree**
verdict file, so a verdict need never be committed; the same chained-command gap in `git-guard.sh`
and `merge-guard.sh` with no tracked follow-up; no feature file (branch is sub-feature-scale —
acceptable, the ADR and memory carry the record).

### Where the trajectory is genuinely strong

- The defect was **measured before it was fixed**, not assumed.
- The unit suite caught the author's own wrong assumption (`JUDGE_EXEMPT=a\nb gh pr create`) and
  the *test* was corrected, not the code. Recorded in the test file.
- A prior claim of the author's (ADR Consequences stale) was **retracted** as false rather than
  quietly dropped.
- The verdict backfill is surgical and I verified it: exactly 3 rows changed, only `outcome`
  `null → "rework"`, no rows added or removed, no other field touched.
- The predecessor branch yields **zero `clean` rows**. Rather than force-fit one to satisfy the
  recorded calibration policy, the gap was left honest and escalated as an open question. That is
  the right call and the correct instinct for this subsystem.

## What I'd double-check before merging

1. **Add the `kind` sanity check (F1).** One line, replaces the file-existence branch, closes four
   silent fail-opens. If it's deferred instead, the ADR sentence should read "a *missing* classifier
   fails closed; an *unusable* one still fails open" so the record doesn't overclaim.
2. **Pin adjacency with one test (F3):** `("gh pr list --search create", "NO", "", ...)`. Cheap, and
   it protects the property the code comment says is load-bearing.
3. **Widen the error message (F2)** to name a repair route that still works under the block, and
   say in the ADR that the blast radius is machine-wide across concurrent sessions.
4. **Watch the first live arming.** Nothing here has run under the real harness; the transitional
   window (new script, no `hooks/lib/`) is the failure mode to have a plan for.
5. **`CODING_MEMORY.md` (F6)** — the parked consolidation is now overdue enough that it is itself a
   trajectory signal.

## Dimensions

| dimension | verdict | note |
| --- | --- | --- |
| intent | pass | goal literally achieved; verified red→green independently |
| execution | **concern** | 4 of 5 broken-classifier modes still fail open silently (F1); smaller change covers all |
| trajectory | pass | measured before fixing, strict TDD, own wrong assumption caught by test, prior claim retracted |
| regression | pass | 56 pre-existing assertions green, classifier untouched, no drive-bys, no new deps |
| context_budget | **concern** | `CODING_MEMORY.md` 1267→1316 vs its stated 200-line cap; repeat finding (F6) |
| traceability | pass | ADR 0012 carries rationale, cost and scope caveat; comments explain the why |
| success_masking | **concern** | a test named "missing classifier → block" reads as complete while 4 modes pass silently; adjacency unpinned at 48/0 (F1, F3) |
| intent_drift | pass | 6 files, all in domain; doc-only commit closes a prior `Doc-Exempt` |
| checkpoint | pass | clean per-concern commits, each revertable; red/green split intact; tree clean |
| audit_trail | pass | backfill surgical and verifiable; retraction recorded; calibration gap escalated not papered over |

**risk:** medium — the headline fix is partial in a way its own test names advertise as complete,
and the new denial path is machine-wide and unexercised.
**confidence:** high — both suites, red-first, shellcheck, five broken-install probes, eleven
mutations and the verdict backfill were all re-measured here rather than taken from the brief.
