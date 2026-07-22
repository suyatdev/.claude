# Observability Judge Verdict — cmux-version-gate (implementation, gating) — ROUND 2

- **Repo:** `.claude` · **Branch:** `feature/cmux-version-gate`
- **HEAD:** `758b1fa8ff18486d03befcc7ae5269170d5a066a` (pushed; `origin` matches)
- **Base:** `main` (merge-base `34914644801fa0454a7bc2da1b2beb99a390e583`)
- **Delta under review:** `git diff 9797191..HEAD` — one commit, 5 files, +66/−19
- **Round 1:** `2026-07-22-feature-cmux-version-gate.md` (HEAD `9797191`) — passed, held
  `success_masking` at `concern` for one named, probed reason
- **Risk:** low · **Confidence:** high
- **Blocks the PR:** no. No dimension fails.

**Headline: `success_masking` moves to `pass`.** The named blocker is genuinely closed and I proved
it myself. **`traceability` moves the other way, `pass` → `concern`**: the branch log now
*contradicts* the code it documents on the exact point that was fixed.

## Test evidence — run by me, not taken on report

| Suite | Result | Round 1 |
|---|---|---|
| `cmux-exec.test.sh` | **77** / 0 | 70 |
| `cmux-layout.test.sh` | 34 / 0 | 34 |
| `adapters.test.sh` | 24 / 0 | 24 |
| `dispatch-pane-agent.test.sh` | 39 / 0 | 39 |
| `run-pane-agent.test.sh` | 10 / 0 | 10 |
| `terminal-detect.test.sh` | 9 / 0 | 9 |
| **total** | **193 passed, 0 failed** | 186 |

`shellcheck -x` on all four named scripts exits 0, silent. The five untouched suites are
byte-identical to round 1 — no adjacent breakage. Live binary is `cmux 0.64.20 (100) [14e3400b9]`,
matching the pin, as claimed.

### 28 parser probes — I widened the boundary as instructed

Driven end-to-end through the real adapter against the fake binary (harness lifted from the suite,
run outside the repo). "receipt" = contents of `$PANE_STATE_DIR/cmux-version-mismatch`.

| `cmux version` first line | stderr | receipt |
|---|---|---|
| `cmux 0.64.20 (100) [14e3400b9]` (the pin) | silent | none ✅ |
| `cmux 0.64.20 (100) [sha] EXTRA` / trailing space / double space | silent | none ✅ |
| `cmux 0.65.0 (101)` · `cmux 1.0.0 (200)` | **WARN** | mismatch ✅ |
| **`cmux 0.65.0-rc1`** · **`cmux 0.64.20-beta`** (round 1's hole) | **WARN** | mismatch ✅ |
| `cmux 0.64.20-rc1` · `cmux 0.64.20-dirty` · `cmux 9.9.9-SNAPSHOT+build.7` | **WARN** | mismatch ✅ |
| **`cmux 2026.07.01` (date-style)** | **WARN** | mismatch ✅ |
| `cmux 0.65` · `cmux 0.64.2` · `cmux 0.64.200` · `cmux 0.64.20.1` | **WARN** | mismatch ✅ |
| `cmux 0abc.1def` | **WARN** | mismatch (loose, but errs loud) |
| **`cmux 100` (bare integer)** | silent | unreadable ⚠️ |
| **`cmux v0.65.0`** | silent | unreadable ⚠️ |
| `cmux 0` · `cmux 1.` · `cmux .1` | silent | unreadable ✅ |
| `cmux version 0.65.0` · `0.65.0` (no prog name) · `cmux` | silent | unreadable ✅ |
| `garbage` · empty output · non-zero exit | silent | unreadable ✅ |

Every row dispatched normally (`rc=0`, `out=surface:51`) — warn-never-degrade holds throughout.

**Rulings on the three boundaries you asked about:**

- **Bare `100` → unreadable is the RIGHT side.** cmux's own output already carries a bare integer
  (`(100)`, the build number). Accepting a bare integer as a version would mean the parser cannot
  tell a version scheme change from a field-order change. Silent + receipt is correct.
- **`2026.07.01` → mismatch is the RIGHT side.** A date-based scheme differs from `0.64.20` and
  should warn. It does.
- **`v0.65.0` → unreadable is the WEAKEST boundary, and I accept it anyway.** A `v` prefix is an
  extremely common cosmetic release-time change, so this is the one remaining shape where a real
  version bump stays off-screen. But accepting it is not free: `v0.64.20` would then compare
  unequal to the pin `0.64.20` and cry wolf on *the same release* — precisely the fail-open case
  the design exists to avoid. Correct fix is normalization (strip a leading `v` before comparing),
  not widening the shape test. It is a one-liner, it is not a blocker, and unlike round 1 the case
  now leaves a receipt.

### Falsification — re-run independently, and one row does not reproduce

| Mutation | Claimed | My result |
|---|---|---|
| never clear a stale receipt (`rm -f` → `:`) | 76/1 | **76 / 1 RED** ✅ exact |
| no receipt on unreadable (redirect to `/dev/null`) | 75/2 | **75 / 2 RED** ✅ exact |
| revert to the version-CLEAN filter | 73/4 | **75/2** or **71/6**, never 73/4 ⚠️ |

The third does not reproduce at the stated count under either natural reading. Reverting only the
filter (`''\|*[!0-9.]*)`) while keeping the unreadable receipt → **75/2**. Reverting the whole
round-1 parser (clean filter *and* no receipt) → **71/6**, failing all six of the right assertions.
73/4 is only reachable via a *two-part* mutation (clean filter **plus** a receipt that omits
`$line`) — which violates the branch log's own stated "each verified to change exactly one anchor"
methodology. **The mutation is genuinely RED and genuinely discriminating either way**; the number
is what I can't verify. Restores confirmed with `git diff --quiet` after every run.

**This surfaced a real test-quality finding.** The two `"$v leaves a mismatch receipt"` assertions
use `grep -qF "$v" "$VER_MARKER"`, and the *unreadable* receipt embeds the whole raw line — which
contains `0.65.0-rc1`. So those two assertions **pass even under the reverted clean filter**. They
read as if they prove mismatch-classification; they don't. Only the sibling stderr assertions
discriminate (and they do — that's the 75/2). Two of six new assertions are weaker than they look.

### One new noise path I found and the suite doesn't cover

With an **unwritable `PANE_STATE_DIR`**, the unreadable path's advertised "stay silent on stderr"
breaks: `2>/dev/null` does not suppress a *redirection* failure, so bash emits
`…/cmux-version-mismatch: Permission denied` to stderr once per dispatch. Verified directly. This
is **new to this commit** — before it, the unreadable path wrote nothing at all. Impact is one
extra stderr line and `rc=0` (no `set -e` in `cmux.sh`, only `set -u`, so nothing aborts); the
dispatcher creates and owns that directory, so likelihood is low. Remedy is
`{ printf … > "$marker"; } 2>/dev/null`.

## Dimension table

| Dimension | Score | Δ | Basis |
|---|---|---|---|
| intent | **pass** | = | Built exactly the two-line fix named, plus both adjacent gaps and all three doc items. Nothing else. |
| execution | **pass** | = | 193/0 re-run by me; shellcheck 0; 28 probes confirm the boundary; 2 of 3 mutations reproduce exactly and the third is RED at the right assertions. |
| trajectory | **pass** | = | The commit message volunteers that its *first* attempt at mutation 3 was invalid — deleting the line broke the `case`, so 61 failures were a parse error, not discrimination — and records the corrected redirect form. Self-caught bad evidence, reported unprompted. That is the strongest signal on this delta. |
| regression | **pass** | = | Five untouched suites byte-identical. Adds one `mkdir -p` + `dirname` subshell and one `rm -f` to the happy path; both rc-safe with no `set -e`. One new unwritable-dir noise path (concern 3). |
| context_budget | **concern** | = | `CODING_MEMORY.md` 379 → **382** vs its own ≤200. Not "net-neutral" as reported — +3, on top of an inherited 173-line overage (`main` is 373). Trim tracked separately. |
| traceability | **concern** | ⬇ from pass | The branch log now contradicts the code — see concern 1. Code comments and the commit message are excellent; the durable doc is not. |
| success_masking | **pass** | ⬆ from concern | The named blocker is closed and independently proved across 28 probes. Every remaining silent-on-stderr case now leaves a receipt, so nothing is *totally* silent any more. See ruling 1. |
| intent_drift | **pass** | = | Exactly the 5 expected files. No new deps, no drive-by edits, no scope creep. |
| checkpoint | **pass** | = | One self-contained, revertible commit; `origin` matches HEAD; working tree clean apart from this judge's own artifacts. |
| audit_trail | **pass** | = | Commit message attributes the finding to the round-1 judge by name, records the rejected mutation and why it was invalid, and states the corrected form. ADR 0008 is incomplete on the new behaviour but not contradicted. |

## Rulings on the four questions

### 1. Does `success_masking` move to `pass`? — **Yes.**

Round 1's commitment was explicit: *"If only the first [unfixable half] existed, I would score this
`pass`."* The second half is now gone, and I did not take that on report.

- `0.65.0-rc1` and `0.64.20-beta` **warn and leave a mismatch receipt**, probed directly.
- So do `0.64.20-rc1`, `0.64.20-dirty`, `9.9.9-SNAPSHOT+build.7`, `2026.07.01`, `0.65`, `0.64.2`.
- `garbage`, empty output, and a non-zero exit stay silent — the fail-open property is intact, not
  traded away for the fix.
- Reverting the filter turns the pre-release stderr assertions RED, so the fix is load-bearing on a
  discriminating test, not an untested claim.
- The stderr/receipt asymmetry round 1 called out is resolved: silence on screen no longer implies
  silence on disk.
- The receipt is now self-clearing, so its presence means "there is a problem *now*."

**What would keep it at `concern` if it were still true** — none of these are: (a) any readable,
unambiguously-different version producing neither a warning nor a receipt; (b) the fix passing on a
non-discriminating assertion only; (c) the fail-open path becoming so wide that a routine upgrade
lands in it. I checked all three.

**Residuals I am explicitly *not* holding the score for:** `v0.65.0` (concern 2 — a different
class, output-reshape, which round 1 already ruled acceptable-by-design, and its prescribed remedy
of a marker-on-unreadable is exactly what landed); and the two weak receipt assertions (concern 4 —
redundant, not load-bearing).

### 2. Is a write-only receipt acceptable? — **Yes for merge, no for calling the loop closed.**

Grepped again: `$PANE_STATE_DIR/cmux-version-mismatch` is written by `cmux.sh`, read by the test,
and *pointed at* by `cmux-layout.sh:71` and ADR 0008. **No code reads it.**

It is acceptable now because notification is not its job — the two stderr lines are, and
`dispatch-pane-agent.sh` does not redirect adapter stderr, so they land in the tool output at the
moment of dispatch. The receipt's job is to survive scrollback, and self-clearing upgrades it from
"a fault happened once" to "a fault exists now," which is the difference between a log line and
state. The new `cmux-layout.sh` back-pointer also makes it *discoverable by a human debugging pane
placement*, which is the actual retrieval path.

It does **not** count as closing the loop, and I'd resist any wording that says it does. A
write-only file is forensics, not observability — it helps only someone who already suspects the
problem. **Cheapest real reader, in order of value:** the statusline (already renders per-session
state, one `[ -e ]` test, zero new plumbing) > a dispatcher startup check > the handoff pane.
Follow-up, not a blocker: the *unreadable* receipt in particular is the one nobody will ever see
unaided, because by construction it prints nothing to screen.

### 3. Alarm fatigue with no acknowledge path — **the right trade, and I'd defend it.**

Warn-every-dispatch is correct here for three reasons. The warning must reach *the dispatch that
placed a pane wrongly*, and a once-per-session suppression hides it from exactly that event.
Suppression state would live in the same directory whose contents get swept on a 7-day timer, so
"acknowledged" and "forgotten" would be indistinguishable. And the cost of over-warning is two
lines of text, while the cost of under-warning is a silently mis-placed pane — the asymmetry the
whole branch exists to respect.

The friction is real but it is *correctly placed*: clearing the alarm requires re-running
`cmux-layout-probe.sh` and editing the pin, which is precisely the re-verification the warning is
asking for. An ack that didn't require re-verification would be worse than no alarm. One caveat
worth naming: `0.64.20-rc1` now warns permanently against the `0.64.20` pin, so anyone tracking a
pre-release channel gets a standing warning. That is the intended conservative side of exact
equality, but it's the most likely route to habituation in practice.

### 4. `context_budget` — **stays `concern`; the reported figure is slightly off.**

`CODING_MEMORY.md` went 379 → **382**, not net-neutral: +3. On a 200-line ceiling that's 91% over,
and the branch has now added 9 lines total to an always-on file. I'm not escalating it — `main` was
already 173 lines over before this branch existed, the rewrite genuinely replaced stale content
rather than appending, and the trim is tracked as its own task. But "roughly net-neutral" should
read "+3, still 182 over."

## Concerns

1. **The branch log contradicts the code it documents.** `coding-memory/branches/cmux-version-gate.md`
   lines 39–40 still read *"accepted only if it matches `[0-9.]+`. Anything else is treated as
   unreadable, never as a mismatch"* — the exact behaviour this commit removed as a bug. Line 51
   still says 54 → 70 / 170 → 186. The mutation table is still round 1's four mutations; none of
   the three new ones appear. A reader opening the log — the artifact this dispatch itself points
   at — would conclude the pre-release hole is still open. Only the "scope correction" bullet was
   added. **The single highest-value fix on this list.**
2. **`v0.65.0` still goes silent on stderr.** The one remaining shape where a real version bump
   stays off-screen (receipt is written). Remedy is normalization, not widening — see ruling above.
3. **New stderr noise on an unwritable state dir.** `2>/dev/null` doesn't suppress a redirection
   failure, so the "silent" unreadable path emits `Permission denied` once per dispatch. Verified.
   New to this commit. Low likelihood, low impact, one-brace fix.
4. **Two of six new assertions don't discriminate.** `grep -qF "$v" "$VER_MARKER"` passes against
   the *unreadable* receipt too, since that receipt embeds the raw line. Proved by mutation. Assert
   the receipt *kind*, not just that the version string appears somewhere in it.
5. **Mutation row 3's `73/4` doesn't reproduce** (I get 75/2 or 71/6). RED either way, so the
   falsification stands; the count doesn't, and reaching it needs a two-part mutation that breaks
   the log's own one-anchor rule.
6. **The receipt is still write-only** (ruling 2). Nothing surfaces it; the *unreadable* receipt is
   invisible by construction.
7. **`CODING_MEMORY.md` 382 lines vs 200** (ruling 4).
8. **ADR 0008 wasn't updated.** Not contradicted — "fails open on unreadable output" is still true
   for stderr — but it doesn't mention the receipt-on-unreadable or the self-clearing, so the ADR
   describes a weaker detector than the one that shipped.
9. **Both rounds' verdict artifacts are uncommitted** (`verdicts.jsonl` modified, round-1 `.md`
   untracked). Deliberate, to keep HEAD stable for `judge-guard` — but a `git clean -fd` right now
   destroys the audit trail for two judge rounds. Commit immediately after `gh pr create`.
10. **`PANE_DRYRUN` still unchecked** — accepted in round 1, unchanged, still fine.

## What was changed

Round 1 found the smoke alarm had a deaf spot. It only recognised a version made of digits and
dots, so a beta or release-candidate build — `0.65.0-rc1`, `0.64.20-beta` — got filed under "I
can't read this" and the alarm said nothing at all. Beta builds are one of the most likely ways to
end up on a cmux whose behaviour moved, so the alarm was deafest to exactly the case that mattered.

This fixes it by asking a looser question: instead of "is this made only of digits and dots?", it
now asks "does this *look like* a version — starts with a digit, has a dot in it?" A `-rc1` on the
end no longer disqualifies it, so those builds now trigger the warning like any other mismatch.

Two related repairs came with it. When the alarm genuinely can't read the output it still stays
quiet on screen — the deliberate choice, so a cosmetic change to cmux's output doesn't nag you
every dispatch — but it now leaves a note on disk saying "I couldn't read this," so an alarm going
permanently quiet at least leaves a trace. And when the version goes *back* to matching, the old
note gets deleted, so finding that file now means "something is wrong right now" rather than
"something was wrong once."

The rest is signposting: the pane-layout code now has a comment pointing at the check that guards
it, and the branch notes walk back an overstatement about how much this fixes.

## Does it do what you wanted?

**Yes — and I checked the thing I complained about rather than taking the fix on faith.** I fed the
parser 28 version strings, three times as many as last round. `0.65.0-rc1` and `0.64.20-beta` now
warn and leave a receipt. So do `-dirty` builds, `SNAPSHOT+build` strings, date-style versions like
`2026.07.01`, and near-misses like `0.64.2`. Genuine garbage and empty output still stay quiet, so
the fix didn't buy loudness by making the alarm jumpy. Reverting the fix turns the tests red at the
right place, so it's really tested, not just really written.

**`success_masking` moves to `pass`.** That was the only thing holding it, and it's gone.

Two small honest asterisks. `cmux v0.65.0` — with a `v` in front — still slips past the on-screen
warning, though it now leaves a receipt. I'd leave that alone: accepting `v` would make
`v0.64.20` look *different* from the pin `0.64.20` and cry wolf on the very same release, which is
worse. And the number in one row of the falsification table doesn't reproduce for me — the test
still goes red, so the check is real, just not by the count written down.

## What could go wrong / what I'm unsure about

- **The branch notes now describe a bug that no longer exists.** They still say versions are
  "accepted only if they match digits-and-dots… never a mismatch" — the exact thing this commit
  deleted. They also still show the old test counts and the old mutation table. Someone reading
  those notes in three months learns the wrong thing about their own code. This is my biggest
  gripe with the change.
- **Two of the six new tests are softer than they read.** They check that the version string
  appears *somewhere* in the receipt file — but the "can't read this" receipt copies the whole
  line, which contains the version string. So those two tests pass even with the bug put back. The
  tests that actually catch it are the ones checking the on-screen warning.
- **If the state folder is ever read-only, the "silent" path stops being silent** — you'd get a
  `Permission denied` line every dispatch. Small, and unlikely since the dispatcher makes that
  folder itself, but it's new with this commit.
- **Still nobody reads the receipt file.** It's better than it was — it cleans itself up now, and
  the layout code points at it — but it only helps someone already looking. The "can't read this"
  receipt is the one nobody will ever see unaided, since it prints nothing.
- **Any mismatch nags forever until a human edits and commits the pin.** I think that's right —
  the nag is asking you to re-run the probe, which is what actually needs doing — but if you ever
  run a cmux beta channel, you're signing up for a permanent warning.
- **The memory file is 382 lines against its own 200 limit**, and grew by 3 here rather than
  staying flat.

## What I'd double-check before merging

1. **Nothing blocks the PR.** No dimension fails; `success_masking` cleared. Open it.
2. **Fix the branch log before it calcifies** — it is currently the only artifact stating the old,
   wrong parsing rule as fact. Update lines 39–40, the 54 → 70 / 170 → 186 counts, and add the
   three new mutations to the table. Five minutes, highest value on this list.
3. **Tighten the two soft receipt assertions** — assert the receipt *kind* (`mismatch` vs
   `unreadable`), not just that the version string appears in it.
4. **Either reproduce the `73/4` row or correct it** to the single-anchor result (75/2).
5. **Wrap the receipt write in braces** — `{ printf … > "$marker"; } 2>/dev/null` — so an unwritable
   state dir can't make the silent path noisy.
6. **Add the receipt to ADR 0008's paragraph**, so the ADR describes the detector that shipped.
7. **Commit both rounds' verdict artifacts immediately after `gh pr create`** — right now they're
   uncommitted and one `git clean` from gone.
