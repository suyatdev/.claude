# Compliance verdict — `docs/features/falsify-harness-signatures.md`

Spec slug: `falsify-harness-signatures` · repo `statusline-followups` (worktree of `~/.claude`)

---

## Round 1 — 2026-08-08T05:07:00Z — **FAIL** (4 violations)

Branch `main` · head `aa464ff127155feaf217f5fde84b4c159802fa11` · spec blob `3154a383f145cabe96737d6cdf45154a509adab3`

### Layman summary

The spec fixes a real problem well: the falsification harness currently asserts "version X must
pass exactly 19 tests", which is a fact about how big the suite is rather than about the bug, so
it breaks every time somebody writes a better test. Swapping that for "these named assertions must
fail on version X" is the right call, and the reasoning-before-running discipline in §4 is the
part that keeps this from becoming a rubber stamp. Background, non-goals, risk, pinned versions,
and Gherkin scenarios are all present and genuinely good.

The blocking problem is that the spec picks a name for each test case that the test suite does not
actually print. The design says a case is identified by "the description string the suite already
prints as `ok — <desc>` / `FAIL — <desc>`", as though the pass line and the fail line carry the
same text. They do not. Checking the suite directly: a passing case prints
`ok   — baseline renders model and context-bar segments` while its failing twin prints
`FAIL — baseline segments missing: <the whole rendered output>`
(`statusline-command.test.sh:103-104`). Even the spec's own worked example is affected — the
injection helper prints `ok   — <desc> (esc=0<=0 …)` on success but
`FAIL — <desc> injected control bytes (esc=… …)` on failure (`statusline-command.test.sh:556-558`),
so the signature name `"real ESC in display_name is stripped"` never appears verbatim on any FAIL
line. Under a plain string match, every signature would trip the brand-new "this case no longer
exists" hard error, and the harness would be broken in a new way on day one. The spec needs to
state the matching rule (and whether the suite must emit a stable case id) explicitly.

Three smaller gaps: version `4d63b09` currently passes *everything* — its signature would be an
empty list, which under "extra failures are allowed" asserts nothing at all, and the spec never
says what an empty signature means; the working-tree sanity floor that the harness runs first is a
count check (`passed == total`) and the spec never says whether it survives the removal of counts;
and the new third outcome (ERROR) has no stated exit status, even though §5 commits the harness to
being run at PR time next to a hook-enforced judge.

The deliberate deviation on spec location is **accepted**. `writing-specs` defers to
`docs/superpowers/specs/`, but this repo's own `one-canonical-file` rule (`rules/gates.md`,
imported by this repo's `CLAUDE.md`) puts feature-scale work in `docs/features/<name>.md`, project
rules win on conflict, the file has the required frontmatter + spec + checklist shape, and prior
compliance rounds accepted the same path for `memsearch-freshness`, `memory-system-split`, and
`verification-marker-gate`.

### Violations

| # | id | rule source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | "Database schemas and API contracts: give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes" | Design §1 "Signatures replace counts" (with §3 and Non-goals) | The suite's `ok —` and `FAIL —` lines carry *different* text for the same case (`statusline-command.test.sh:103-104`, `556-558`, `319-321`) and fail lines embed runtime output, so "identified by the description string the suite already prints" is not implementable without a stated matching rule. |
| 2 | `writing-specs/edge-cases-empty-signature` | `skills/writing-specs/SKILL.md` | "Good, bad, and edge-case scenarios … Anything you leave implicit, the agent infers — and inference is where the defects come from" | Design §2 "Extra failures are allowed" / Scenarios | `4d63b09` passes 20/20 today (`statusline-command.falsify.py:54`), so its `must_fail` list is empty; combined with "extra failures are allowed" that version would be asserted about not at all, silently dropping the one check the count scheme gave it. |
| 3 | `writing-specs/unstated-working-tree-floor` | `skills/writing-specs/SKILL.md` | Same — behavior left implicit is behavior the agent invents; the spec calls out the `#!` check it preserves but not this one | Tasks §4 / Design §1 (nothing states it) | The harness's first action is a working-tree sanity floor asserting `passed == total` (`statusline-command.falsify.py:99-107`) — a count check the spec neither preserves nor replaces, so task 4's rewrite of `EXPECTED` and `run_suite` leaves its fate to the implementer. |
| 4 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | "Handle errors explicitly, never swallow them" (Code Style) | Design §3 "A signature naming a case that no longer exists is a hard error" / §5 "It runs at PR time" | §3 introduces a third outcome (ERROR) on top of intact/FAIL but never states its process-boundary contract; the current harness returns a binary `0`/`1` (`statusline-command.falsify.py:120-121`), so an ERROR could exit `0` and read as green to whatever runs it at PR time. |

### Notes (non-blocking)

- **Spec location — accepted, not a violation.** `docs/superpowers/specs/` does exist here with ten
  specs dated 2026-07-12…07-22, so the "second location" the skill warns about is historical
  rather than hypothetical; the current convention is `docs/features/`, the repo rule is explicit,
  and prior rounds in this store accepted it. The header's reasoning holds as written.
- **Pinned versions verified live on this machine:** `Python 3.9.6`, `GNU bash 3.2.57(1)-release`,
  `git 2.50.1` — all three match the "Toolchain — pinned" table exactly. No third-party imports.
- **Four of five signatures deliberately unfilled** is *not* treated as a placeholder/TBD
  violation: §4 and task 1 require reasoning them out before any run (user decision 2), and
  pre-filling them in the spec would defeat that. Worth flagging only that the single worked
  example inherits violation 1.
- **No commit hook (§5)** is a stated user decision with the residual risk written down rather
  than hidden — compliant with "architecture trade-offs stay human-owned".
- **KISS/DRY/YAGNI clean.** Non-goals explicitly refuse generalising the harness, changing the
  five commits, changing what the 68 tests assert, and adding a hook.
- **Security: nothing to cite.** Blob extraction stays an argv-list `subprocess` call with no
  shell, the `#!` guard is preserved as Scenario 5, no secrets or absolute paths appear, and the
  scratch dir is `tempfile.TemporaryDirectory` (0700).

### Waivers

None. No violation ids were waived by the user for this round.

---

## Round 2 — 2026-08-08T05:25:42Z — **FAIL** (1 violation)

Branch `main` · head `38188ecdd29ef8ac127880346dfc4d01e8fb818d` · spec blob `7d7d67c04d20c3aa279f70a7ea6e1cffaac0dd99`

### Layman summary

Revision 2 fixes all four round-1 problems, and fixes them well. Each test now carries a short
stable name (an "id") that the suite prints whether the test passes or fails, so the harness can
recognise a case by identity instead of by a sentence that changes wording between the two
outcomes — that was the blocking defect. A version whose list of must-fail tests is empty is now a
hard error rather than a free pass; the "the suite must be green right now" floor is explicitly
kept; and the three outcomes now have three distinct exit codes with the rule that an error can
never exit 0. The new vacuity ratchet — recording which 23 assertions still pass against a script
that prints nothing, and refusing to let that set grow — is a genuinely good addition and its
scope is correctly recorded as a user decision.

One thing still blocks. The identity contract assumes one id per place the suite calls `ok()` or
`bad()`, but eleven of the sixty-eight assertions are produced inside `for` loops, where a single
call site emits three or four separate results:

```sh
for shape in '{}' 'garbage' '{"cwd":null}' '{"workspace":{}}'; do
  ...
    ok "\$PWD fallback stripped for stdin '$shape' (esc=$esc<=$limit bel=$bel)"
```
(`statusline-command.test.sh:606-617`; the same shape at `524-535` for quota `resets_at`, and
`710-717` for degenerate `COLUMNS`.)

Passing the id as the first argument of `ok()`/`bad()` gives those four iterations *one* id, which
collides with the spec's own "unique within the suite" rule. Deriving an id per iteration is the
obvious fix, but the loop values are `{}`, `garbage`, `{"cwd":null}`, `{"workspace":{}}`, `0`, the
empty string, `abc` and `-1` — none of which can appear inside the `[a-z0-9-]+` the harness parses,
so the mapping has to be invented by whoever implements it. That matters beyond tidiness: the spec
names "all four `$PWD fallback stripped` cases" as members of the vacuous set, and `KNOWN_VACUOUS`
is keyed by id — if the four share one id, the ratchet cannot tell which of them has been fixed, at
exactly the safety-critical spot the ratchet exists to watch. One added sentence in §1 (the id
derivation rule for iterated assertions, plus what the harness does if a duplicate id appears in a
single run) closes it.

The id is reused from round 1 because it is the same rule in the same section of the spec (§1, the
identity contract), not because the round-1 instance persists — **that instance is fixed**. Recorded
this way so the persistence check sees that this territory has now failed twice.

### Round-1 violations — all four verified fixed

| round-1 id | how revision 2 resolves it | verified |
|---|---|---|
| `writing-specs/api-contracts` | §1 replaces description-matching with kebab-case ids emitted on both outcomes, parsed by `^(ok\|FAIL)\s+\[([a-z0-9-]+)\]`; all suite output already funnels through `ok()`/`bad()` (`statusline-command.test.sh:43-44`), so the contract is enforceable at one place | fixed for the described defect; new instance cited below |
| `writing-specs/edge-cases-empty-signature` | §3 makes an empty `must_fail` exit 2, task 4 forces add-an-assertion or remove-with-rationale, and a Gherkin scenario pins it | fixed |
| `writing-specs/unstated-working-tree-floor` | new §6 preserves `falsify.py:99-107` unchanged with its rationale and binds failure to exit 1 | fixed |
| `core-conduct/explicit-error-handling` | §4 defines 0/1/2 with a table and a flowchart, plus the explicit "an ERROR must never exit 0" against today's binary `0`/`1` (`falsify.py:120-121`) | fixed |

### Violations

| # | id | rule source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | "Database schemas and API contracts: these give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes that other components then fail to match" | Design §1 "Stable case ids — the identity contract" (knock-on in §5 `KNOWN_VACUOUS`, task 1) | Eleven of the 68 assertions are emitted from inside `for` loops (`statusline-command.test.sh:524-535`, `606-617`, `710-717`), so one `ok()`/`bad()` call site yields three or four results, and the spec states no per-iteration id rule — while the loop values (`{}`, `garbage`, `{"cwd":null}`, `{"workspace":{}}`, `0`, empty, `abc`, `-1`) cannot appear in the `[a-z0-9-]+` id the harness parses, leaving both "unique within the suite" and the per-id granularity of the four `$PWD fallback` entries in `KNOWN_VACUOUS` for the implementer to invent. |

### Notes (non-blocking)

- **A stale `KNOWN_VACUOUS` entry has no stated error path**, unlike a signature naming a removed id
  (§4, exit 2). The asymmetry is defensible — a stale entry can only permit an id that no longer
  exists, and the subset check still catches every new vacuous assertion — so it fails safe. Worth
  one sentence if §1 is being edited anyway.
- **Exit-code precedence is unstated** when a run hits both a missing id (2) and a lost
  falsification (1). Both are non-zero and the "ERROR must never exit 0" invariant holds either way,
  so this is cosmetic for CI but affects what a human reads first.
- **`esc-literal-inert` appears in both** `f0902ed`'s `must_fail` (§2) and `KNOWN_VACUOUS` (§5).
  That is legitimate — a "count of bad bytes ≤ limit" assertion passes on silence and still fails on
  a version that leaks — but the spec never says the overlap is expected, and a reader may take it
  for a contradiction.
- **The `...` in `KNOWN_VACUOUS` and the four unfilled signatures are not TBD placeholders.** The
  vacuous set is seeded from measurement (task 7) and the signatures are deliberately withheld until
  reasoned out (§7, task 3) — pre-filling either would defeat the mechanism. Same call as round 1.
- **Pinned versions re-verified live on this machine:** `Python 3.9.6`, `GNU bash 3.2.57(1)-release`,
  `git 2.50.1` — all three match the toolchain table exactly. Still stdlib-only, no new dependencies.
- **Scope growth is human-owned, not silently decided.** The vacuity ratchet is attributed to a dated
  user decision in the header, with "fixing the 23" listed as an explicit non-goal and the reason
  given (two half-reviewed changes instead of one reviewed one). Compliant with "architecture
  trade-offs stay human-owned"; not relitigated here.
- **Security: nothing to cite, unchanged from round 1.** Blob extraction stays an argv-list
  `subprocess.run` with no shell (`falsify.py:61-72`), the `#!` guard survives as a Gherkin scenario,
  the scratch dir remains `tempfile.TemporaryDirectory` (0700), and no secrets or absolute paths
  appear. The stub is a new generated artifact but lands in that same 0700 dir; "executable" in §5 is
  belt-and-braces since the suite invokes the script through `bash <path>`.
- **File-size convention holds:** `falsify.py` is 125 lines today; signatures, the three-state check
  and the ratchet leave it far inside the 400-line guidance.
- **Spec location unchanged and still accepted** — `docs/features/` per this repo's
  `one-canonical-file` rule, which wins over `writing-specs`' `docs/superpowers/specs/` default.

### Waivers

None. No violation ids were waived by the user for this round.

---

## Round 3 — 2026-08-08T06:00:12Z — **FAIL** (1 violation)

Branch `main` · head `c3314d5b6242c64c38d6d082f9b99d8d7f40e121` · spec blob `c698538b3cf02ca59cf321f61ff21a4be7a4b211`

### Layman summary

Revision 3 fixes the round-2 blocker properly. Eleven of the tests are produced inside `for` loops,
so one line of code emits three or four results; §1 now says each loop walks a list of
hand-written `name:value` pairs and builds the id as `<family>-<name>`, never from the value and
never from its position, and it makes a repeated id a hard error. Verified against the real files:
the quota loop already uses exactly that `label:value` shape
(`statusline-command.test.sh:524-535`), the two other loops (`606-617`, `710-717`) do not, and
3 + 4 + 4 is the eleven the spec claims. The Risk section's "91 call sites, not 68" is also exact —
45 `ok` and 46 `bad` invocations, counted. Every `falsify.py` line reference in the spec resolves
correctly, and all three pinned tool versions match this machine.

One thing blocks, and it is the spec's own headline defect hiding in a second location. The spec
says the stale pass counts live in `EXPECTED` at `falsify.py:44-57`. They also live at
`falsify.py:9-18`, in the module docstring — the first thing anyone reads:

```
Expected, and asserted below:

    f0902ed   9/20   printf '%b'; both injection routes open, plus $PWD
    925c310  10/20   route 1 closed; route 2 and $PWD open
    ...
These are the single source of truth alongside EXPECTED below; if the two ever
disagree, EXPECTED is what runs.
```

Those numbers are already wrong (they are 20-case-era counts in a 68-case suite, and the spec's own
Background table shows `f0902ed` at 8, not 9). Task 6 rewrites `EXPECTED` into signatures, which
leaves the docstring declaring itself "the single source of truth" for counts that no longer exist
anywhere in the file, with a tie-break clause pointing at a field that no longer holds counts. Task
10 does touch the docstring — but only to "document the PR-time run" — so an implementer following
the spec literally ships the exact rot this feature exists to delete, in the most-read paragraph of
the file. Naming it costs one clause in task 6 or 10.

Everything else I looked hard at came out non-blocking and is recorded below, including three
things I deliberately did **not** cite: the 23-vs-24 wobble, the missing empty-`must_pass` guard,
and the five newer behaviors that have no Gherkin scenario. Each is real; none of them leaves a
build decision undetermined, and citing them on the tripwire round would be judge drift rather than
a converging process.

### Round-2 violation — verified fixed

| round-2 id | how revision 3 resolves it | verified |
|---|---|---|
| `writing-specs/api-contracts` | §1 "Loop-generated assertions": loops iterate authored `id-suffix:value` pairs, id is `<family>-<suffix>`, suffixes never derived from the value and never positional, plus duplicate ids exit 2 | fixed — the prescribed shape matches the pre-existing idiom at `test.sh:524-535` (`"absent:" "elapsed:$PAST" …`), `${case%%:*}`/`${case#*:}` handle the colon-bearing timestamp and the empty-string `COLUMNS` case correctly, and the four `$PWD fallback` cases now get distinct ratchet keys |

### Violations

| # | id | rule source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `writing-specs/stale-docstring-counts` | `skills/writing-specs/SKILL.md` | "Drift causes hallucination: when the spec and the code fall out of sync, the agent starts describing and extending behavior that no longer exists… update them in the change that makes them wrong, not later"; "Docstrings are the code-level contract" | Background §"Defect 1 — pass counts go stale by design" (defect inventory), Tasks 6 and 10 | The stale pass counts exist in two places, not one: `falsify.py:9-18` repeats them and declares "These are the single source of truth alongside EXPECTED below; if the two ever disagree, EXPECTED is what runs", but the spec attributes Defect 1 only to `falsify.py:44-57`, task 6 rewrites only `EXPECTED`, and task 10 edits the docstring only to add the PR-time run — so the literal build leaves five already-wrong counts self-declared as authoritative in a file whose purpose is to delete them. |

### Notes (non-blocking)

- **23 vs 24, in the same section.** §6 spends a paragraph resolving this ("The seeded number is 24,
  not 23… Recorded here so task 7 seeds from the defined stub and the discrepancy is not
  rediscovered as a defect"), then closes with "It starts at the measured 23 and is expected to
  fall… those are 23 separate assertion rewrites"; Background §Defect 2 and Non-goals also still say
  23. Not cited because the operative instruction is unambiguous — task 1 measures, task 7 seeds
  from that measurement — so no build decision hangs on it. Worth one sweep anyway: with two stubs
  the vacuous population is at least the 30 of `STUB_ONE_LINE`, which makes "the 23 vacuous
  assertions" in Non-goals understate its own scope.
- **Three cross-references went stale when revision 3 inserted §3.** §1 "With §5's ratchet list"
  → the ratchet is §6; Non-goals "No commit hook (§8)" → the hook is discussed in §9; Risk "If §7
  shows a label misdescribes its commit" → reasoning-before-running is §8 (§7 is the working-tree
  floor). Headings are named, so a reader recovers; still the same species of unread-pointer rot the
  document is about.
- **`raise SystemExit("<message>")` exits 1, not 2.** `falsify.py:82` (suite produced no tally) and
  `61-72` (non-`#!` blob) both raise `SystemExit` with a *string*, which Python maps to exit 1 — so
  under the new taxonomy a crashed suite would report as "FALSIFICATION LOST" rather than "HARNESS
  ERROR". §5's exit-2 row lists three causes and does not include "the suite produced no tally". Not
  cited: task 6 says implement the three exit codes, "harness error" plainly covers it, and task 8's
  falsifier "truncate a stub run (expect 2)" walks straight into this path during implementation.
- **`must_pass` has no empty-list guard**, though §4 makes an empty `must_fail` exit 2 and §6 adds a
  full-case-count check for exactly the "an empty set satisfies everything" shape. Not cited because
  unlike `4d63b09`'s genuinely-empty `must_fail`, an empty `must_pass` is not reachable from the
  data — the weakest version still passes 8 of 50 — so demanding the guard would be symmetry for its
  own sake. Round 1's `writing-specs/edge-cases-empty-signature` stays fixed.
- **Five behaviors added in revisions 2-3 have no Gherkin scenario:** a failing `must_pass` anchor, a
  duplicate id, `STUB_ONE_LINE`, growth of `SIGNATURE_RESTS_ON_VACUOUS`, and the full-case-count
  check. Not cited: task 8 pins an expected exit code for each, so nothing is left undecided, and
  `writing-specs` warns specifically that redundant Given/When/Then blocks are the usual bloat
  offender. If any two are added, make them the `must_pass` anchor and the duplicate id — those are
  the two whose *semantics*, not just exit code, a reader could misread.
- **§5's exit-1 row is not exhaustive** — it lists lost detection, working-tree floor, ratchet
  growth, but not a failing `must_pass`, which §3 does state exits 1. Cosmetic.
- **The second vacuity list is unnamed.** §6 shows only `KNOWN_VACUOUS` but requires two lists with
  "its own list" each; task 7 says "seed each list". The implementer invents the second name.
- **Facts verified against the files, not taken on trust:** 45 `ok` + 46 `bad` = 91 call sites
  (exact); 11 loop-emitted results across `test.sh:524-535` (3), `606-617` (4), `710-717` (4)
  (exact); `ok()`/`bad()` are a single funnel at `test.sh:43-44`, so the id contract is enforceable
  in one place; `falsify.py` is 125 lines and every cited line range resolves (`44-57` EXPECTED,
  `54` the 4d63b09 entry, `61-72` extraction, `99-107` floor, `120-121` binary exit). Live versions:
  `Python 3.9.6`, `GNU bash 3.2.57(1)-release`, `git 2.50.1` — all three match the pinned table.
  Still stdlib-only, no new dependencies.
- **The two stub measurements (24 and 30 of 68) I did not independently reproduce** — running the
  suite five-plus times has side effects and cost. They are labelled "Measured" and task 1 re-derives
  them before any edit, which is the right ordering.
- **The re-baselining carve-out is sound.** §6 distinguishes seeding a ratchet from re-baselining a
  signature ("a vacuity list encodes no belief; it is a starting position for a ratchet whose only
  permitted direction is down") against §Risk's blanket "never re-baseline". That is the correct
  line, and it is drawn explicitly rather than assumed.
- **Scope growth stays human-owned.** Revision 3's additions each cite a measurement and a dated user
  decision. The one worth a cost/benefit glance is `SIGNATURE_RESTS_ON_VACUOUS`: it is the third
  hand-maintained shrink-only list, it tracks a state the spec itself calls legitimate, and its
  unique detection power is narrow (a *newly added* signature id that rests on a vacuous measure —
  the underlying overlap can otherwise only shrink on its own). Surfaced, not silently decided, so
  not a YAGNI citation; if the user wants to trim revision 3, this is the piece to trim.
- **Security: nothing to cite, unchanged from rounds 1-2.** Blob extraction stays an argv-list
  `subprocess.run` with no shell (`falsify.py:61-72`), the `#!` guard survives as a Gherkin scenario,
  both stubs are generated into the same `tempfile.TemporaryDirectory` (0700), and no secrets or
  absolute paths appear.
- **File-size convention holds.** `falsify.py` at 125 lines plus signatures, the three-state check,
  two stub ratchets and the overlap list stays well inside the 400-line guidance.
- **Spec location unchanged and still accepted** — `docs/features/` per this repo's
  `one-canonical-file` rule, which wins over `writing-specs`' `docs/superpowers/specs/` default.

### Waivers

None. No violation ids were waived by the user for this round.

---

## Round 4 — 2026-08-10T02:33:37Z — **FAIL** (6 violations)

Branch `main` · head `df8d1d6341141ceb1b6c928741d9bb164b72d726` · spec blob `574b16d2962499ffcf0b25466e16d54168c64708`

### Layman summary

Revision 4 is a genuine redesign and a good one. The old design pinned a list of tests that must
fail on each old version; the new one pins a small table — one row per test that actually changes
behaviour somewhere along the chain, with a `P` or a `.` for each of the five versions. Because the
table records the passes as well as the failures, it holds itself in place, which is why the
separate `must_pass` list could be deleted. It also removes the bug that revision 3 would have
shipped: a version that *introduced* a regression had an empty "what did this fix" list, and the
old design treated that as a fatal error.

I did not take the numbers on trust. I re-ran the suite against all five historical versions and
both stubs myself, and **every measured figure in this spec reproduces exactly** — the five
baselines (19/20/28/33/32), the working tree at 68/68, the two stub counts (24 and 31), the union
of 31 vacuous, the 15/18/35 partition, the 13-of-15 vacuity split, the per-version pass counts
`1, 2, 10, 15, 14`, ordinal 47 as the only assertion that flips twice with the pattern `P P . P .`,
the per-transition fractions 1/1, 7/9, 5/5, 1/1, the 91 call sites as 45 `ok` + 46 `bad`, and all
three pinned tool versions. That is unusually well-grounded work and it is the reason the remaining
findings are about the *writing*, not the measurements.

The round-3 blocker is properly closed: §Background now names both places the stale counts live
(`falsify.py:44-57` **and** the docstring at `falsify.py:8-18`, including its "single source of
truth" sentence) and task 5 deletes the docstring block in the same commit that replaces `EXPECTED`.
I confirmed both line ranges resolve to exactly that content.

Six things still block, and they cluster in one place: the document knows more than it says, and
in four spots it says two different things. The document counts its own error exits four different
ways (3 in the flowchart, 5 in the table beside it, "four" in task 5, 5 exercised in task 7), so a
builder cannot tell how many to implement. The flip matrix — the whole feature — is shown by
example only, with no rule for how wide a row must be or what happens when one is malformed; a row
typed with four states instead of five would shift every version's expectation by one and be
reported as "FALSIFICATION LOST" rather than as the authoring error it is. One section still
instructs revision 4 on what it "must" do and leaves two questions "open for that revision" that
revision 4 already answered. One count (23) is stale against the spec's own 31. `MATRIX_RESTS_ON_VACUOUS`
is a third hand-kept list whose contents §6b already computes, and no task builds it. And the one
sentence explaining *why* dropping `must_pass` is safe names the wrong safety net — the full-count
assertion cannot catch a wholesale collapse (a collapsed run still emits all 68 results, as §6b
itself says); the empty-column guard is what catches it.

None of these change the design. All six are edits to the document, and the design underneath them
survived every check I could run against the real files.

### Round-3 violation — verified fixed

| round-3 id | how revision 4 resolves it | verified |
|---|---|---|
| `writing-specs/stale-docstring-counts` | §Background §"Defect 1" now cites both sites explicitly and quotes the "single source of truth alongside EXPECTED below" sentence; task 5 requires deleting the docstring block **in the same commit** as the `EXPECTED` replacement, and states why (§9's docstring edit is additive and does not cover it) | fixed — `falsify.py:9` is the `Expected, and asserted below:` heading, `11-15` the five `n/20` lines, `17-18` the self-declared-authority sentence; all inside the cited `8-18`, and `EXPECTED` resolves at `44-58`. Task 5's wording closes the loophole round 3 found in tasks 6/10. |

### Rounds 1-2 violations — still fixed

| id | status |
|---|---|
| `writing-specs/api-contracts` | still fixed — §1's id contract, `^(ok\|FAIL)\s+\[([a-z0-9-]+)\]` parse rule, authored `id-suffix:value` loop rule and duplicate-id exit 2 are unchanged and complete. Violations 1-2 below sit in adjacent territory but are **new sections introduced by revision 4 (§2/§5)**, not a regression of this fix. |
| `writing-specs/edge-cases-empty-signature` | dissolved — under the matrix `4d63b09` is simply the `15/15 P` column, not an empty signature needing resolution (§4). |
| `writing-specs/unstated-working-tree-floor` | still fixed — §7, `falsify.py:99-107` preserved, exits 1. |
| `core-conduct/explicit-error-handling` | still fixed — §5 states the three states, the exit-code precedence rule, and the `SystemExit(2)`-not-a-bare-string requirement (correct: a string argument to `SystemExit` exits 1). |

### Violations

| # | id | rule source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `writing-specs/exit-path-enumeration` | `skills/writing-specs/SKILL.md` | "precise enough that the agent has nothing left to guess at"; "Anything you leave implicit, the agent infers — and inference is where the defects come from" | §5 "Three states, three exit codes" (flowchart and table), Tasks 5 and 7 | The spec enumerates its own exit-2 conditions four incompatible ways — the §5 flowchart shows 3 (short run, missing id, unpinned flip), the §5 table beside it names 5 (adding the empty column and the non-script blob), §1 adds a 6th (duplicate id), task 5 says "the four exit paths", and task 7 exercises 5 — so a builder cannot determine how many error paths to implement or which four task 5 means. |
| 2 | `writing-specs/matrix-row-schema` | `skills/writing-specs/SKILL.md` | "Database schemas and API contracts: these give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes"; core-conduct "Validate all input at system boundaries" | §2 "The flip matrix replaces counts *and* per-version lists" | `FLIP_MATRIX` is this feature's central artifact but its value format is given only by example (`"  .    P    P    P    P "`), with no stated parse rule, no required width, no legal alphabet and no defined exit path for a malformed row — a row typed with four states instead of five would silently shift every version's expectation by one and surface as exit 1 "FALSIFICATION LOST" rather than the exit 2 harness error §5's own precedence rule demands. |
| 3 | `writing-specs/superseded-open-questions` | `skills/writing-specs/SKILL.md` | "Drift causes hallucination: when the spec and the code fall out of sync, the agent starts describing and extending behavior that no longer exists"; "Maintain it with production rigor" | §"The finding that reframes this feature" | The section closes with "**Revision 4 must be designed from this table.** Open for that revision: whether signatures become differential by definition, and whether 'fix the vacuous assertions' can still be a non-goal" — both are answered inside this same revision (§2's "Differential by construction", and §Non-goals' dated user decision) — yet unlike its sibling section marked "*(superseded by §2)*" it carries no marker, so it reads as live undecided scope to anyone building from the file. |
| 4 | `writing-specs/internal-count-contradiction` | `skills/writing-specs/SKILL.md` | "precise enough that the agent has nothing left to guess at"; "Drift causes hallucination" | §6 "The vacuity ratchet" (final paragraph) against §Non-goals | §6 calls the deferred work "23 separate assertion rewrites" one clause after stating the union is "31 of 68", and §Non-goals calls it "the 31 vacuous assertions" — I measured the union at exactly 31, so 23 is a stale figure (the silent stub without its `exit 0`) surviving inside the document whose entire thesis is that stale counts are the defect. |
| 5 | `core-conduct/dry` | `rules/core-conduct.md` | "KISS, DRY, YAGNI" | §6 "The vacuity ratchet" — `MATRIX_RESTS_ON_VACUOUS` | The list is fully determined by state the spec already declares — `set(FLIP_MATRIX) ∩ (VACUOUS_AGAINST_SILENT ∪ VACUOUS_AGAINST_ONE_LINE)`, which I computed as exactly the 13 vacuous discriminating ids — and §6b already computes and prints that same intersection per transition, so declaring it as a third hand-maintained shrink-only list duplicates derived state, adds a third surface that can go stale, and is scheduled by no task. |
| 6 | `core-conduct/verified-before-write-down` | `rules/core-conduct.md` | "Verification precedes both the claim and the write-down — never state that something works… A claim in an audit trail reads as *settled*, so a wrong one costs more to undo than the error it describes" | §2, "Stated honestly" paragraph | The rationale for deleting `must_pass` asserts "§4's full-count assertion is what actually catches a wholesale collapse on the two oldest versions", but a wholesale collapse still emits every result — §6b's own sentence says "silence, NUL bytes and 200KB of junk all held the count at 68", and I confirmed all five versions and both stubs emit 68 regardless of pass count — so the named check provably cannot catch that case; §4's empty-column guard is what does, and the load-bearing justification for removing `must_pass` names the wrong mechanism. |

### Notes (non-blocking)

- **Independent re-measurement: every figure reproduced, none refuted.** I ran the current suite
  against all five blobs (extracted from Python, per §Scenarios' `rtk` caveat) and both stubs:
  baselines `19/20/28/33/32` and working tree `68/68`; `STUB_SILENT` 24/68 and `STUB_ONE_LINE`
  31/68 from the literal bytes §6 pins; union of vacuous 31; partition discriminating 15 /
  constant-pass 18 / constant-fail 35; vacuity by class 13 / 15 / 3; per-version `P` among the
  discriminating set `1, 2, 10, 15, 14`; ordinal 47 the only double-flip, `P P . P .`; the §6b
  fractions 1/1, 7/9, 5/5, 1/1; the §"differential" table's fix/regression directions 1·9·5·0 and
  0·1·0·1 with non-vacuous 0·2·0·0; ordinals 37 / 38-42,66,67 / 43-46 / 47 / 48,49 matching the
  §2 id table row for row; 91 call sites as 45 `ok` + 46 `bad`; `python3 3.9.6`, `bash 3.2.57(1)`,
  `git 2.50.1`. Round 3 declined to reproduce the stub numbers on cost grounds — they are correct.
- **A candidate violation I raised and then withdrew.** The Baselines table describes the one-line
  stub as `printf 'x'` + `exit 0`, while §6 pins *different* bytes (`cat >/dev/null 2>&1` +
  `printf 'statusline\n'` + `exit 0`), so the pinned "31 of 68" appeared to be a count measured on
  a different script — the precise error §6 exists to prevent. I ran both: both pass 31/68. The
  claim is correct; only the provenance sentence should name the pinned bytes.
- **Stale cross-reference.** §Risk says "If **§7** shows a label misdescribes its commit" — the
  reasoning-first section is **§8**; §7 is the working-tree floor. One-token fix, worth doing in the
  same pass as violations 1-4.
- **Dangling colon.** §6's "Both stubs are run, each with its own list:" is followed by a new bolded
  paragraph, not the promised list.
- **Why `MATRIX_RESTS_ON_VACUOUS` moved from note to violation.** Round 3 raised its predecessor
  (`SIGNATURE_RESTS_ON_VACUOUS`) as non-blocking, on the grounds that it had *some* unique detection
  power. Revision 4 removes that ground: §6b now computes the overlap in order to print the
  per-transition fraction, so the membership is derived anyway and the declared copy adds only a
  divergence risk. The change in verdict tracks a change in the spec, not a change of judge opinion.
- **Caller question 3 — did dropping `must_pass` leave a gap?** The design is covered, the
  explanation is not. `f0902ed`'s column is genuinely `1/15 P` and that entry is vacuous, so a
  wholesale collapse there flips one `P` to `.` and trips §4's **empty-column guard** (exit 2). The
  gap is only in §2's sentence crediting the full-count assertion instead — violation 6.
- **Caller question 5 — is "report, don't fix" adequately owned?** Yes, and this is not a violation.
  It carries a dated user decision in two places (§6b "Decided 2026-08-09: report, do not fix";
  §Non-goals "Confirmed as a non-goal by user decision 2026-08-09"), a stated reason (strengthening
  them means editing the suite this harness exists to measure, and the suite is the unbiased
  baseline — consistent with core-conduct's testing rule), a mechanism that keeps it visible (§6b's
  printout plus the ratchet), and an owning artifact (task 10 opens it as its own feature file
  carrying the measured table). That is deferral with ownership, not deferral by omission.
- **File-size convention.** `falsify.py` at 125 lines has ample room for the matrix, closure check
  and two ratchets. `statusline-command.test.sh` is already **845 lines**, above core-conduct's 800
  maximum, and this feature edits all 91 call sites in it — but the id edits are in-line and add
  almost no lines, and splitting the suite would be a drive-by cleanup, which core-conduct says is
  its own task. Correctly out of scope; the spec simply never acknowledges the ceiling.
- **Security: nothing to cite, unchanged from rounds 1-3.** Blob extraction remains an argv-list
  `subprocess.run` with no shell, the `#!` guard survives as a Gherkin scenario, stubs are written
  into a `tempfile.TemporaryDirectory` (0700), stdlib only with no new dependencies, and no secrets
  or absolute paths appear in the spec.
- **Spec location unchanged and still accepted** — `docs/features/` under this repo's
  `one-canonical-file` gate, which takes precedence over `writing-specs`' `docs/superpowers/specs/`
  default. Documented in the spec's own Location note.

### Waivers

None. No violation ids were waived by the user for this round.

### Round 4 — re-dispatch verification, 2026-08-10T02:43:35Z — **no new verdict written**

A second compliance-judge dispatch arrived for round 4 on the identical target (`head_sha`
`df8d1d6341141ceb1b6c928741d9bb164b72d726`, `spec_blob_sha`
`574b16d2962499ffcf0b25466e16d54168c64708`). The round-4 verdict above and its `verdicts.jsonl`
row (`ts` `2026-08-10T02:33:37Z`, the only round-4 row for this spec) were already fully persisted
~90 seconds earlier. **Deliberately not duplicated** — a second round-4 section and a second JSONL
row for the same blob would break the cross-round persistence check this store exists to support.

Independently re-verified in this pass, against the live files rather than taken on trust:

- All six violations reproduce from the spec text as written: §5's exit-2 enumeration is 3
  (flowchart nodes `E2`/`E`/`E3`) vs 5 (table, `falsify-harness-signatures.md:374`) vs a 6th in §1
  (duplicate id, `:265`) vs "the four exit paths" (task 5, `:662`) vs 5 exercised (task 7,
  `:669-673`); `FLIP_MATRIX` (`:296-302`) is example-only with no width/alphabet/malformed-row rule;
  "The finding that reframes this feature" (`:189-199`) still instructs revision 4 and leaves two
  questions "open for that revision" with no *superseded* marker, unlike its sibling at `:121`;
  "23 separate assertion rewrites" (`:491`) contradicts "union 31 of 68" (`:489`) and Non-goals'
  "the 31 vacuous assertions" (`:619`); `MATRIX_RESTS_ON_VACUOUS` (`:476-482`) is the intersection
  §6b already computes and no task builds it; §2's "§4's full-count assertion is what actually
  catches a wholesale collapse" (`:319`) is refuted by §6b's own "silence, NUL bytes and 200KB of
  junk all held the count at 68" (`:474`) — the empty-column guard is the mechanism that catches it.
- Round-3 closure confirmed a second time: `falsify.py:9` is the `Expected, and asserted below:`
  heading, `:11-15` the five `n/20` lines, `:17-18` the "single source of truth alongside EXPECTED
  below" sentence — all inside the `8-18` the spec now cites; `EXPECTED` resolves at `44-58`.
  `writing-specs/stale-docstring-counts` is genuinely closed.
- File facts: 45 `ok` + 46 `bad` = **91** call sites (exact); `statusline-command.test.sh` is 845
  lines; `falsify.py` is 125 lines with `SystemExit` at `:68` and `:82`, floor at `:99-107`, binary
  exit at `:120-121`. Every cited range resolves.

**Not re-run in this pass:** the ten suite executions behind the round-4 note "every measured figure
reproduced". Those measurements stand on the earlier run's record, not on a second confirmation.

Housekeeping for the caller: `verdicts.jsonl` is modified and this card is untracked — both need a
commit before the session clears.

---

## Round 5 — 2026-08-10T03:26:00Z — **FAIL** (2 violations)

Branch `main` · head `631a72fff45b88980f3a95178854fb5e89dea9ab` · spec blob `4a94081592842874b88fd64c2db932369e122703`

### Layman summary

Five of the six round-4 problems are properly closed, and the sixth — the exit-code table — is
closed *at the table* but not everywhere the table is quoted. §5 now says a newly-discriminating
test exits `3` (REVIEW NEEDED), and the flowchart, task 5 and task 7 were all updated to agree.
Three other places were missed: §3's closure bullet (`:373`) still says "`exit 2` — review needed",
task 8 (`:786`) still says "confirm exit 2", and — worst — the Gherkin block now contains **two
scenarios with the identical Given and different Thens**: "adding a discriminating test demands
review … Then the harness exits 2" (`:622-626`) sitting eleven lines above "an unpinned flip is
review … Then the harness exits 3" (`:671-674`). Scenarios are the part a builder turns straight
into tests, so this is the one place the contradiction is most likely to be built rather than
noticed. This is the **first violation id in this spec to recur across rounds** — the premise the
user's decision to continue past the escalation cap rested on no longer holds, and that is worth
saying plainly rather than burying.

The second finding is new, and it comes from text added after round 4. The spec now says the total
number of test cases must never be written down as a literal but derived: "It is
`len(working_tree_results)` from the floor run" (`:337-339`). But §4, §5's table and task 5 all
promise that *every* run — "working tree, all five versions, **and** both stubs" (`:393`) — is
checked against that count. For the working-tree run that check can never fail: it is being
compared against its own length. And there is no other source of truth available — I checked, and
the suite's own tally prints `pass+fail` as the denominator (`statusline-command.test.sh:844`), so
a run that dies halfway reports `30/30 passed` and looks perfect. I reproduced the truncation
live: a script that crashes mid-run emits exactly **30 of 68** results, the same number §6b
quotes. So a working-tree run truncated at 30 all-passing cases would set the count to 30, satisfy
the "must be all-pass" floor, let all five version runs clear the guard, and exit `0` — the
harness reporting "falsification measured" while the suite it measures against is broken. That is
precisely the class of defect this whole feature exists to end, one level up, and it is the same
argument §4 already makes for stub runs.

Everything else I could check came out right, including things no earlier round had verified. The
five newly pinned blob SHAs are **exact**, all five byte counts too — and I confirmed them the way
§Toolchain demands, from Python, after my Bash-tool `git rev-parse` reproduced the documented `rtk`
proxy rewrite live (it handed back the commit object). §5's table really is ten conditions: three
exit-1, six exit-2, one exit-3, counted. §6b's corrected row 2 (10 ids, 8-of-10) derives correctly
from the spec's own id table. The hollow-out non-goal is properly owned, not a defect being
shipped.

### Round-4 violations — five verified fixed, one recurs

| round-4 id | how `631a72f` resolves it | verified |
|---|---|---|
| `writing-specs/exit-path-enumeration` | §5's table declared the single enumeration (`:405-407`), ten conditions across four codes, REVIEW NEEDED promoted to its own exit `3`; flowchart, task 5 ("all ten exit conditions") and task 7 (ten falsifiers) rewritten to match | **partial — recurs.** Table/flowchart/task 5/task 7 agree exactly. §3 `:373`, Scenarios `:625` and task 8 `:786` were not updated. Cited below under the same id. |
| `writing-specs/matrix-row-schema` | §2 `:322-335` adds the parse contract — alphabet `P`/`.` only, width exactly `len(VERSIONS)`, key must exist in suite output and be unique, whitespace meaningless — each violation exit `2`, plus the rationale for why width is load-bearing | fixed — the four properties are stated as a table with an exit code each, and §5's exit-2 row and the Gherkin at `:661-664` both carry the malformed-row path |
| `writing-specs/superseded-open-questions` | heading `:189` marked *(answered by §2 and §Non-goals — no longer open)*; closing paragraph `:198-202` rewritten to state both answers and "nothing here is live scope" | fixed |
| `writing-specs/internal-count-contradiction` | `:572` now reads "31 separate assertion rewrites" | fixed — 31 is consistent across `:113`, `:285-288` (13+15+3), `:491`, `:570-572`, `:715`; no surviving 23 |
| `core-conduct/dry` | `MATRIX_RESTS_ON_VACUOUS` deleted; §6b `:557-563` states the overlap is computed as `FLIP_MATRIX.keys() & (both stub lists)` and explains why the declared copy was wrong | fixed — the two stub lists are now the only declared vacuity state |
| `core-conduct/verified-before-write-down` | §2 `:356-361` credits §4's empty-column guard, quotes the measurement (`silent+exit emitted 68 passes 24`); §6b `:546-549` corrected to "That was wrong, and round 4 demonstrated it" with the SEGV evidence | fixed — and I reproduced the SEGV run independently: **30 of 68**, exact |

### Violations

| # | id | rule source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `writing-specs/exit-path-enumeration` | `skills/writing-specs/SKILL.md` | "precise enough that the agent has nothing left to guess at"; "Anything you leave implicit, the agent infers — and inference is where the defects come from"; "Ambiguity surfaces early" (BDD section) | §3 closure bullet (`:373`), Scenarios "adding a discriminating test demands review" (`:622-626`), Task 8 (`:786`) — against §5's single-enumeration table (`:414`) | §5 gives REVIEW NEEDED its own exit `3`, but three derived sites still assign exit `2` to the same condition, and the Gherkin block now self-contradicts: `:625` and `:673` share the Given "a test is added whose state differs across the five versions" and assert different exit codes, so a builder generating tests from the Scenarios block cannot determine what the closure check returns. |
| 2 | `writing-specs/derived-count-self-reference` | `skills/writing-specs/SKILL.md` | "Good, bad, and edge-case scenarios: state explicitly what correct looks like, what wrong looks like, and enumerate the edges. Anything you leave implicit, the agent infers"; with `rules/core-conduct.md` "Handle errors explicitly, never swallow them" | §2 "The full case count is derived, never a literal" (`:337-339`) against §4 "A run that did not finish" (`:391-395`), §5's exit-2 row (`:413`) and Task 5 (`:769-770`) | The full case count is defined as `len(working_tree_results)` from the floor run, yet the same run is one of those the harness must assert "emitted the full case count" — an unfalsifiable comparison against its own length — and no independent bound is available (the suite's tally denominator is `pass+fail`, `statusline-command.test.sh:844`, also self-derived), so a working-tree run truncated at 30 all-passing results (reproduced live via `kill -SEGV $$`: **30 of 68**) sets the count to 30, satisfies the all-pass floor, lets all five version runs clear the guard, and exits `0`. |

### Notes (non-blocking)

- **Caller question 2 — the ten conditions, counted.** §5's table (`:411-414`) holds exit-1: three
  (row no longer matches / working-tree floor failed / a vacuity list grew); exit-2: six (short
  run, id not in suite, duplicate id, malformed row, empty column, blob-SHA mismatch); exit-3: one
  (discriminating set ≠ pinned set). **Ten.** The caller's claim is exact, and `:416`'s "exactly six
  exit-2 conditions and one exit-3 condition" holds. Task 5's "all ten exit conditions" matches;
  task 7's list is ten items with the right codes (1,1,1,2,2,2,2,2,2,3).
- **The flowchart agrees on codes but is a partial view.** All six exit-2 conditions are present
  (node `A` = short run; node `B` = the other five). Only **one of the three** exit-1 conditions is
  drawn — the working-tree floor and vacuity-list growth appear nowhere in it, and the floor's
  position relative to the `2 > 3 > 1 > 0` precedence is therefore unstated. Not cited: §5 declares
  the table authoritative over the flowchart, and an omission is not a contradiction. Two extra
  nodes would close it.
- **Task 7 says "one falsifier per row of §5's table"** (`:776-777`) — the table has four rows and
  the list has ten items. Not cited: the list is explicitly enumerated with an exit code per item,
  so nothing is left undetermined. "Per condition" is the word.
- **Caller question 3 — the hollow-out non-goal is adequately scoped.** It names the limit, carries
  the working exploit, states *why* it cannot be closed here (per-row margins means editing the
  suite — the same boundary as the vacuity non-goal), attributes it to a dated user decision, and
  hands it to task 10 as the stronger of two motivations. The banner rename from "intact" to
  "measured" (`:531-534`) removes the over-claim that would have made it read as a shipped defect.
  Its premise checks out against the suite: `statusline-command.test.sh:601-602` says in its own
  comment that the benign twin puts "the ceiling 8 escapes above what the hostile payload can
  legitimately emit", so the slack is real and **pre-existing in the suite as shipped** — this
  feature neither creates nor widens it. That is disclosure of a measurement harness's limit, not a
  defect being shipped. Not a violation.
- **Blob SHAs — all five exact, verified the hard way.** From Python: `f0902ed`
  `ce85493054775cb7917fc71b95d14792d80d4213` (2845), `925c310`
  `d28a0895dddb4fdae81853c21766f4fda213d1e8` (3310), `29d6131`
  `e30dcd0a9d872fe9fdbc978584174de785739df4` (4520), `4d63b09`
  `b5a071634f48e21abf206df89dfe6f0002b8a65d` (4811), `e882659`
  `4b6be5a94eb016ed925b603093ee56e877f89664` (5407) — every SHA and every byte count matches §2
  `:303-309`. My first attempt went through the Bash tool and **reproduced the documented `rtk`
  rewrite live**: `git rev-parse f0902ed:statusline-command.sh` returned the *commit* object
  `f0902ed82880e9e793b40a4576c5cd1d7bd3055e`. §Toolchain's "invoked from Python, never via the Bash
  tool" (`:709`) is not folklore; it is the only route that works on this machine today.
- **§6b row 2 (10 ids, 8-of-10) is arithmetically correct.** Derived from §2's id table
  (`:177-181`) across `925c310 → 29d6131`: ids 38-42/66/67 flip `.`→`P` (7), id 47 flips `P`→`.`
  (1, the regression), ids 48/49 flip `.`→`P` (2) = **10**; vacuous among them 7 + 1 = **8**. The
  old `9`/`7-of-9` was the fix direction only, and `:147`'s differential table still correctly
  shows 9 for that column because it is explicitly the fix-direction table.
- **One provenance clause is off.** `:517-518` says of that correction "round 4 caught it" —
  compliance round 4 recorded the *old* 7/9 as reproducing exactly (see this card, round 4 notes);
  per the caller the correction came from the advisory judge. If "round 4" means the round rather
  than this judge the sentence reads fine, but `:361` uses "Round 4 cited it as
  `core-conduct/verified-before-write-down`", which is this judge specifically. Two usages, one
  word. Not cited — no build decision hangs on it — but the audit trail now carries the correction.
- **Id-spelling drift on ordinal 47.** `pwd-fallthrough-stripped` in §1 (`:242-243`) and §6
  (`:457`), `pwd-fallthrough` in §2 (`:317`), §6b (`:515`) and the Gherkin (`:635`) — the same
  assertion under two ids inside the document that defines the identity contract. Not cited: the
  ids do not exist yet (task 2 authors them, task 3 writes the matrix from what the suite actually
  emits), so nothing is undetermined. Worth one sweep since §1 is the contract.
- **Two stale cross-references survive from earlier rounds.** §Risk `:738` "If **§7** shows a label
  misdescribes its commit" → reasoning-first is §8; §Non-goals `:733` "No commit hook (§8)" → the
  hook is §9. Flagged non-blocking in rounds 3 and 4; still there. Also `falsify.py:44-57` for
  `EXPECTED` is off by one — it closes at `:58`.
- **Pinned versions re-verified live:** `Python 3.9.6`, `GNU bash 3.2.57(1)-release`,
  `git 2.50.1` — all three match the toolchain table. Still stdlib-only, no new dependencies.
- **Security: nothing to cite, unchanged from rounds 1-4.** Blob extraction stays an argv-list
  `subprocess.run` with no shell (`falsify.py:61-72`), the `#!` guard survives as a Gherkin
  scenario, stubs are generated into a `tempfile.TemporaryDirectory` (0700), no secrets or absolute
  paths appear. The new blob-SHA pinning is a supply-chain **improvement** — core-conduct's "vetted
  registries, pinned versions" applied to historical artifacts, and it closes the one gap the `#!`
  check alone left open (a wrong-but-script-shaped blob).
- **File-size convention.** `falsify.py` 125 lines. `statusline-command.test.sh` is **845** lines,
  above core-conduct's 800 maximum; this feature edits all 91 call sites in it but adds
  approximately no lines, and splitting it would be a drive-by cleanup, which core-conduct makes
  its own task. Correctly out of scope; the spec still never acknowledges the ceiling.
- **Spec location unchanged and still accepted** — `docs/features/` under this repo's
  `one-canonical-file` gate, which takes precedence over `writing-specs`' `docs/superpowers/specs/`
  default.
- **What I ran this round, and what I did not.** Ran: the five blob-SHA/size extractions from
  Python; one suite execution against a `kill -SEGV $$` stub (30 of 68); `python3`/`bash`/`git`
  versions; every cited line range in `falsify.py` (`44-58`, `68`, `82`, `99-107`, `120-121`) and
  `statusline-command.test.sh` (`524-535`, `606-617`, `710-717`, `844`). **Not re-run:** the ten-run
  measurement matrix — the five baselines, both stub counts, the 15/18/35 partition, the 13-of-15
  vacuity split. Those stand on round 4's independent reproduction, not on a second confirmation
  here. The 91 call sites (45 `ok` + 46 `bad`) I also did not re-derive; my quick grep patterns
  under-counted and rounds 3 and 4 both counted it exactly.

### Waivers

None. No violation ids were waived by the user for this round. **Escalation note for the caller:**
round 4 already exceeded the round-3 escalation cap, and the user chose to continue on the stated
grounds that no violation id had ever recurred. Violation 1 above breaks that premise — it is the
first recurring id in this spec's history. The design is not in question; both findings are edits
to three sentences and one paragraph.
