# Observability verdict — feature/statusline-token-bar @ b24d422

- **Stage:** implementation (gates the PR)
- **Repo:** `.claude` · **Base:** `main` @ f574213 · **HEAD:** b24d42274a7d21af735c60e6f0a11a58416fb6f7
- **Judged:** 2026-07-19 (2026-07-20T00:42:38Z)
- **Risk: high** · **Confidence: high**

> Lead finding: **the committed test suite is red and nobody ran it.** `statusline-command.test.sh`
> fails 3 of 20 assertions at this HEAD, the failure is disclosed nowhere in the commit or the
> memory docs, and the suite's escape-injection assertions silently got *weaker* than they were on
> `main`. The shipped script is genuinely robust — I verified that myself — but the record claims a
> level of verification the repo cannot reproduce.

---

## What was changed

The status line at the bottom of the terminal got four new pieces of information: the model name in
orange, a ten-block bar showing how full the conversation's context is, a running total of tokens
used this session (the `Σ`), and how much of the weekly usage allowance is gone plus a countdown to
when it resets. A dollar-cost display was also built and then deliberately deleted before shipping.

Think of it like adding a fuel gauge, an odometer, and a "days until your monthly pass expires"
readout to a car dashboard. The gauge and odometer work. The problem is with the workshop's
inspection checklist, not the dashboard: the checklist still describes the old dashboard, it was
never re-run, and it was filed as if it had been.

## Does it do what was asked?

Mostly yes, and the two places it deliberately *didn't* are the best decisions in the change.

The bar, the `Σ` counter and the weekly segment all render correctly — I fed the script about a
dozen payload shapes and they behaved. Two requests were refused on purpose:

- **Cost display: built, then removed.** The account is on a subscription, so no real dollar figure
  exists in the data. Any number shown would have been guessed from a hand-typed price list while
  looking like an actual bill. Deleting it was right. Shipping it behind the "disabled" flag the
  subagent left would have been *worse* than either option: sixteen empty price constants sitting
  in the file is an open invitation for a future session to "just fill these in," which
  reintroduces the hazard without anyone re-making the decision. Deleting the code and writing the
  reasoning into `decisions.md` is the version that survives.
- **Weekly quota shows a percentage, not "tokens left."** The data genuinely only contains a
  percentage. Inventing a token allowance to divide by would have produced an authoritative-looking
  fiction. Correct call, correctly documented.

## What could go wrong / what I'm unsure about

**1. The test suite is red at this commit (fail).** I ran it: 17/20, exit code 1.

```
FAIL — baseline segments missing
FAIL — expected raw token count
FAIL — expected k-formatted tokens
```

All three break for the same benign reason — the assertions look for the text `100 tokens`, and the
new bar renders `░░░░░░░░░░ 100` without the word "tokens". The *behaviour* is fine. The problem is
that the suite is now red in the repo, and a red suite trains everyone to stop reading it. Searching
the entire diff for the word "test" returns nothing: not the commit message, not
`coding-memory/branches/statusline-token-bar.md`, not `decisions.md`. The branch doc says
"Degradation paths (all verified by execution)" — true of the manual checks, but a reader will take
it to mean the tests pass.

**2. The escape-injection assertions silently got weaker (fail).** This is the one I'd want looked at
even if everything else were clean. Those assertions work by comparing escape-byte counts against a
baseline render. Measured against the pre-change script:

| | baseline escapes | injection-payload escapes | slack |
|---|---|---|---|
| `main` @ f574213 | 8 | 8 | **0** |
| this HEAD | 14 | 10 | **4** |

The baseline payload now renders an extra bar segment (more colour codes) while the injection
payloads don't, so the `esc <= BASE_ESC` check gained four bytes of headroom — roughly two complete
colour sequences could now leak and the test would still print `ok`. The test file's own header
records that this exact defect "regressed once during development after being fixed by only one of
its two routes." The guard against that is now looser, and it reports success while being looser.

To be clear: **I found no actual injection hole in the script.** Every externally-sourced value is
stripped (`model_name`, `week_used_pct`, `week_resets_at`, `session_id`), the numeric ones are
additionally forced through `awk` and digit-validated, and `session_id` is `tr -cd`'d before touching
a path. I confirmed a `../` in `session_id` stays inside the state directory. The weakness is in the
detector, not the thing detected.

**3. The `Σ` counter loses updates when renders overlap (concurrency — the question asked).** Not
safe. Reproduced:

```
seed cum=200, then two distinct calls (1000 and 1400 tokens) rendered concurrently
result: cum_tokens = 1200      (serial would be 2600 — one whole call lost)
```

The atomic temp+`mv` write is correct but solves a *different* problem: it prevents a reader seeing a
half-written file (torn read). It does nothing about two renders both reading `cum=200` and both
writing back their own total — last writer wins, the other call vanishes. The in-script comment
conflates the two. Worse, the surviving write also stores the *loser's* `sig`, so the counter stays
desynced afterwards rather than self-correcting on the next render.

How likely in practice: a render takes ~97ms here against Claude Code's ~300ms throttle, so the
window is narrow — but `git status --porcelain` is in that path, and in a large or cold repo it can
blow well past 300ms. The failure is undercount-only and cosmetic, never corrupting real work. A
`mkdir`-based lockfile, or simply documenting the undercount, would close it.

**4. Silent-failure surface (the other question asked).** Yes, the "omit the segment when the field
is missing" design is the right default here — a status line that errors is worse than one showing
fewer segments, and it must never blank the prompt. But the trade is being paid twice already: the
summary notes this is the *second* schema guess that failed closed and looked identical to the
feature being switched off (`resets_at` was epoch seconds, not ISO, and the countdown would simply
never have appeared).

Something cheap that would fix it without any render risk: the script currently collapses two
different situations into the same output — *field absent* (normal, expected) and *field present but
unparseable* (always a bug). Separating those costs almost nothing. Under a `STATUSLINE_DEBUG` env
guard, append one line per unparseable-but-present field to `$STATE_DIR/debug.log`. It never touches
stdout, so it cannot break the prompt, and it would have surfaced the epoch bug on the first render
instead of at the end of the session.

**5. Minor.** No cleanup of `statusline-state/session-*.json` — one file per session forever (they're
~70 bytes, so nuisance rather than problem). The script forks `jq` 15 times, 11 of them re-parsing
the same stdin, on a path that runs on every render; ~97ms total, dominated by the git calls.

### What I verified myself

Path traversal in `session_id` contained; corrupt state file falls back to zero and self-heals;
`current_usage: null` holds the prior total instead of resetting; negative, zero, and absurd token
counts all render; no temp files leaked; sequential accumulation exact; re-rendering the same payload
does not double-count; weekly countdown renders for **both** epoch and ISO `resets_at`. The
robustness claims in the branch doc hold up.

## What I'd double-check before merging

1. **Update and run `statusline-command.test.sh`.** Change the three `"N tokens"` assertions to match
   the bar format. This is a ten-minute mechanical fix and it clears the lead finding.
2. **Restore the injection assertion's tightness.** Give the injection payloads the same segment set
   as `BASE_PAYLOAD` (add `context_window`) so the slack returns to zero, or assert an exact count
   rather than `<=`.
3. **Add test cases for the new segments.** The ~15 hand-built payloads used for manual verification
   are exactly the cases worth keeping — right now they exist only in a session transcript, which is
   the one place a future maintainer cannot run them from.
4. **Decide on the `Σ` race:** lockfile, or document the undercount in the script comment. Either is
   fine; silently believing the `mv` handles it is not.
5. **Correct the "all verified by execution" wording** in the branch doc to say what was actually run
   (manual payloads) and what wasn't (the suite).

Nothing here requires redesign. The feature is sound; the verification record needs to match reality
before it merges.

---

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | Four segments delivered; both deviations (cost removed, quota as %) are data-driven and documented |
| `execution` | **fail** | Committed suite red 17/20, never run, undisclosed; reproduced lost-update in the new counter |
| `trajectory` | pass | Real reasoning, not luck: bar-denominator fix, measured cache-token exclusion, sig-vs-prompt_id, schema check that caught the epoch bug |
| `regression` | **fail** | Adjacent test file broken; injection-assertion headroom widened 0 → 4 bytes on the guard built for exactly this defect class |
| `context_budget` | pass | `CODING_MEMORY.md` net +11 lines while compacting merged-PR history into a pointer; detail pushed to a branch file |
| `traceability` | pass | Unusually strong — every non-obvious choice carries a *why* comment, plus branch doc and `decisions.md` entry |
| `success_masking` | **fail** | Security assertions print `ok` while strictly weaker than `main`; docs assert verification while the suite sits red and unmentioned; absent-vs-unparseable collapse already caused two silent failures |
| `intent_drift` | pass | Tight scope, `settings.json` correctly left uncommitted, no new deps; the cost removal is documented scope *reduction* |
| `checkpoint` | pass | Single clean revertable commit; unrelated dirty files untouched |
| `audit_trail` | concern | Attribution excellent (even corrects a prior misattribution), but omits the test state — a material fact for a reviewer. "Never render a metric the payload cannot source" is arguably ADR-worthy beyond `decisions.md` |

## Concerns

1. `statusline-command.test.sh` fails 3/20 at HEAD (exit 1) and was never run; the word "test" appears nowhere in the diff, while the branch doc reads "all verified by execution"
2. Escape-injection assertion headroom widened from 0 to 4 escape bytes (BASE_ESC 8 → 14, injection 8 → 10) because BASE_PAYLOAD gained a bar segment the injection payloads lack — the guard reports `ok` while strictly weaker than `main`
3. `Σ` counter loses updates under overlapping renders: reproduced 200 + 1000 + 1400 → 1200 instead of 2600, and the surviving write stores the loser's `sig` so the counter stays desynced
4. The atomic-write comment conflates torn reads (solved by `mv`) with lost updates (not solved) — a future reader will trust it covers both
5. New segments have zero regression coverage; the ~15 manual payloads exist only in a session transcript, not in a runnable file
6. Absent vs. present-but-unparseable are collapsed into the same "segment missing" output — already the proximate cause of two silent failures across two statusline efforts
7. No cleanup path for `statusline-state/session-*.json`; grows one small file per session indefinitely
8. 15 `jq` forks per render (11 re-parsing the same stdin) on an every-render hot path

**No live security defect found** — all externally-sourced values are stripped, numerics are awk-coerced and digit-validated, and `session_id` path traversal is contained (verified). Concern 2 is about detection strength, not an open hole.
