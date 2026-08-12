# Observability verdict — `feat/tracking-feature-state` round 12 (architecting, advisory)

- **Repo:** `tracking-feature-state` (worktree of `~/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `7ba5e0f13993c16b00ed5e7bb1b37b58530f694b`
- **Base:** `main` · **Stage:** `architecting` — advisory, blocks nothing
- **Predecessor:** round 11 (`7be4aec`), `coding-memory/observability-judge/2026-08-10-feat-tracking-feature-state-round11.md`
- **Artifact:** the pair `docs/features/tracking-feature-state.md` (112) +
  `docs/features/tracking-feature-state.spec.md` (1261), read in full from source

## What was changed

Think of the feature card as a restaurant menu with a recipe book behind it. Until now the menu had
the recipes printed on it — you had to carry 326 lines of it every time you walked into the kitchen,
just to remember what dish you were making. This change moves the recipes into the book and leaves a
one-page menu: **112 lines**, the smallest it has ever been, and the smallest of the ten feature
cards in this repo.

Three commits, documentation only, no code touched:

1. `5b7cdcc` — fixed a factual error the previous review caught. The card had claimed in four places
   that the tool ignores the recipe book "because it has no `phase:` label". It actually ignores it
   **because of the filename** (`SPEC_SUFFIX = ".spec.md"`, `task-tracker/analyze.py:36,192`). The
   card now says so, and the acceptance test was corrected to check the real rule.
2. `bbaae5b` — the re-split itself. The first attempt put all fourteen task lines on the menu and
   none in the book, which broke the automatic checker that makes sure the two halves agree. Now both
   halves list tasks 1–14 and the detail lives in the book, which is the arrangement ADR 0017
   prescribes.
3. `7ba5e0f` — a session memory archive. No spec content.

## Does it do what you wanted?

Yes, and the risky part — moving a lot of text across a file boundary — came through clean. I checked
that four ways rather than taking it on trust:

| Check | Method | Result |
|---|---|---|
| Halves agree | ran the registered guard `hooks/lib/feature_tasks.py` on the real pair | **exit 0**, both halves yield `1`…`14` |
| Nothing lost in the move | diffed the *union* of both files before (`7be4aec`) and after | 16 lines gone, and all 16 are exactly the round-10 corrections. **No silent loss** |
| Cross-references still land | enumerated every `§` reference against every heading | **all resolve**; `§Verification` correctly stays in the `.md`, as the card claims |
| The most breakable content survived | compared the §Design 3 asset manifest against criterion 13's expected list | **exact set equality** — 16 manifest rows, plus only `/` and `/favicon.ico`. 9 `vendor/` rows, matching "nine local files" |

I also ran the card's own test command. **53 passed, 0 skipped, in 4.23s** — matching the figure
recorded in §Verification, and with `node v26.5.0` present, so criterion 5's JavaScript oracle
genuinely ran rather than being quietly skipped.

Every internal count I could check is correct: fourteen criteria, nine vendor files, exactly two
expected `404`s, seven controls in task 9's list (three startup aborts + four send-time outcomes).
For a card whose recurring defect is a stale count, that is a good result.

**Task 4's re-opening is real and correctly diagnosed.** I verified it against the code: the fixture
helper `repo.card()` always writes a `phase:` key (`task-tracker/test_analyze.py:94-99`), so
`test_criterion_1_n_cards_in_n_features_out` proves a spec half is skipped *despite* carrying one,
and nothing proves the converse. No test anywhere covers a card with no frontmatter. The card
diagnosed its own gap accurately instead of claiming closure — that is the behaviour you want.

## What could go wrong / what I'm unsure about

**Nothing here is a `fail`.** This is a documentation-only change to a card still in planning. But
five things are open, and two of them are repeats.

**1. The size question you asked about — my answer is "the 112 is the number that matters, but the
1261 needs a human to say so out loud."**

| | Before | After | ADR 0017 cap |
|---|---|---|---|
| `.md` (loads at session start) | 326 | **112** ≈ 2.0k tokens | ≤200 ✅ |
| `.spec.md` (on demand) | 986 | **1261** ≈ 24k tokens | ≤800 ❌ **+58%** |
| Union | 1312 | 1373 | — |

The split is genuinely real, not a paper exercise: `hooks/phase-guard.sh:372` explicitly skips
`*.spec.md`, so the big half is not read by the gate. And in repo context the card is now the
**best-behaved of the ten** on always-on cost — while `memsearch-freshness.md` (2390),
`phase-guard-hook.md` (1779) and `replay-harness-base-pin.md` (1303) blow the ≤200 cap by 6–12× on
the half that *does* load. So `context_budget` improved substantially and in the direction that costs
attention.

The real defect is not the number, it is the **silence**. At `.spec.md:1004` the card flags exactly
this species about its own source file — *"`analyze.py` is over the 400-line target though under the
800 hard max… Not scheduled — a structural split is a human-owned call, not a drive-by; raise it if
the file grows again."* That is the correct pattern, and the card applies it to `analyze.py` and
**not to itself**. A 1261-line spec against an ≤800 cap, unremarked, is a cap breach that no reader
is told about. My recommendation: add one bullet acknowledging it and deferring the trim to a human —
not a trim right now, mid-planning, which would churn the document a fourth time.

**2. Adjacent breakage the split caused, flagged at round 11, unfixed — and under-counted.** Round 11
named three dangling pointers. There are **five**. Every one names a section that now lives in the
other file:

| Location | Points at | Now actually in |
|---|---|---|
| `PORTS.md:26` | "the Security section of `…tracking-feature-state.md`" | `.spec.md:574` |
| `docs/decisions/0022-…:5` | "`…tracking-feature-state.md` §Design 3 and §Security" | `.spec.md:180`, `:574` |
| `docs/decisions/0023-…:5` | "`…tracking-feature-state.md` §"The output contract already exists"" | `.spec.md:52` |
| `task-tracker/test_analyze.py:1` | "criteria 1 and 2 of `…tracking-feature-state.md`" | `.spec.md:745` |
| `task-tracker/test_store.py:3` | "acceptance criteria 3, 4 and 5 of `…tracking-feature-state.md`" | `.spec.md:745` |

The only file that cites the `.spec.md` half correctly is `.claude/session-state.md` — which is
gitignored and rewritten every session, so the one correct pointer is the one that does not persist.
This matters more than it looks: `.spec.md:127` tells an implementer to read ADRs 0022 and 0023
*before proposing a different shape*, and those ADRs' own context lines now land in a 112-line file
with no §Design 3 and no §Security in it.

This is the "audit the surface after repeat findings" shape — the class was identified a round ago,
patched zero times, and is *still* being enumerated one instance at a time. The list above is
exhaustive as of `7ba5e0f`; fix it as a set, not one at a time.

**3. Three substantive spec defects carried forward from round 11, all still open.**

- `.spec.md:387` requires a non-zero `cmux send` exit code to be **"logged server-side"**, but the
  audit format at `:400` has no field to put it in and task 9 never asserts it. This is precisely the
  contradiction the card itself diagnoses at `:403-407` for `path`/`errno` — *"a test written against
  that pair would have been written to match whatever the code emitted and would have passed
  automatically."* Same shape, still live.
- `.spec.md:1088` says to assert `reason` and the status table are in **"bijection"**. They are not:
  `403` maps to four reasons, `502` to three, `500` to two. The clause immediately after it states the
  correct property ("each row's `reason` a defined value, every value reachable"), so a careful reader
  is fine — but a test author who implements the word literally writes a test that fails against a
  correct server, then weakens it.
- `.spec.md:370`'s `405` row is ambiguous: *"Any method other than `GET` on `/` or on a
  static-closure path, or `POST`/`OPTIONS` on `/command`."* The intended reading (a list of permitted
  pairs) is correct; a literal reading makes `POST /command` a `405`, contradicting the only
  state-changing route and the `204 OPTIONS` line eleven lines below. Ambiguity in a status-code
  table is worth one comma.

**4. The card says `phase: planning` while 2,063 lines of Python are committed and passing.**
`analyze.py` (792), `store.py` (212), `test_analyze.py` (524), `test_store.py` (535), tasks 1–3 and
5–7 ticked, 53 tests green. The gate rules say planning forbids implementation code and branch
creation; both exist. Flagged at rounds 10 and 11, unfixed. Nothing breaks, but the durable record
disagrees with the repo, and the phase field is the thing that is supposed to survive a session clear
and tell the next agent what is permitted.

**5. One small mechanism description is imprecise in the same way round 10's was.** Both halves say
the sync guard "keys on the task **number** only" (`.md:41-42`, `.spec.md:987`). It actually keys on
the *normalized text before the first em dash* (`feature_tasks.py:51-55`). For this card's
`<number> — <text>` line shape those are the same thing, so nothing is broken — but round 10's
violation was exactly this: describing a mechanism by what it happens to do on today's data rather
than by what it keys on. Worth one word.

## What I'd double-check before merging

This is advisory and blocks nothing, so "before merging" means before the implementation gate opens:

1. **Sweep all five dangling pointers in one commit** — the table above is the complete set. Repoint
   them at `tracking-feature-state.spec.md`.
2. **Add one line acknowledging `.spec.md` is 1261 against ADR 0017's ≤800**, deferring the trim to a
   human, in the same voice the card already uses for `analyze.py` at `:1004`.
3. **Fix the three carried-forward spec defects** — add an exit-code field (or drop the "logged
   server-side" requirement), replace "bijection" with the correct property, and disambiguate the
   `405` row.
4. **Resolve `phase: planning` against six ticked tasks and 2,063 committed lines** — either the
   frontmatter is wrong or the work was out of phase. This one is a question for the human, not a
   drive-by edit by an agent.
5. **Close task 4's one missing assertion** — a non-`.spec.md` file carrying no `phase:` key must land
   in `features[]` *and* raise a `questions[]` entry. It is one test.

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | **pass** | All three stated goals verified done: round-10 defects 2 & 3 closed against the real `SPEC_SUFFIX` mechanism, re-split on ADR 0017's axis, memory archived |
| `execution` | **concern** | 53 passed / 0 skipped, sync guard exit 0, set-equality intact — but three round-11 spec defects unfixed and task 4 knowingly re-opened |
| `trajectory` | **pass** | The re-split is the right structural call, verified against the registered guard, zero content loss, and task 4's gap was self-reported honestly rather than papered over |
| `regression` | **concern** | Five external pointers (`PORTS.md`, ADR 0022, ADR 0023, two test docstrings) dangle into moved sections; flagged a round ago, unfixed, and under-enumerated |
| `context_budget` | **concern** | Session-start load 326 → **112** (≈2.0k tokens), best in repo, well under ≤200. But `.spec.md` 986 → **1261** vs ADR 0017:39's ≤800, **unacknowledged** where the card flags the same species for `analyze.py` |
| `traceability` | **concern** | Internally excellent — every `§` resolves, citations carry re-find commands, counts are derivations not pins. Undercut by the five external pointers that no longer land |
| `success_masking` | **concern** | Strong by design (criteria 12–14 exist to defeat a refuse-everything server; the manifest is fixed in advance so task 14 cannot author its own acceptance test). But the exit-code field and "bijection" both invite a test written to match whatever the code emits |
| `intent_drift` | **pass** | Docs-only, three on-scope commits, no dependencies, no code touched, no drive-by edits |
| `checkpoint` | **pass** | Clean tree, three discrete revertable commits; `bbaae5b` isolates the text move from `5b7cdcc`'s content fix, which is exactly what makes the risky commit reviewable alone |
| `audit_trail` | **concern** | Precise, attributable commit messages; revision history correctly delegated to git rather than a third stale copy. But `phase: planning` contradicts 2,063 committed lines, and round 11 noted `verdicts.jsonl` still has no line for `3ca4daf` |

**Risk: low.** **Confidence: high** — both files read in full from source, every count re-measured,
the guard and the test suite actually run, and the external-citation set enumerated exhaustively
(after my first grep over-filtered and hid the very lines it was looking for).

## Concerns

1. `.spec.md` is 1261 lines against ADR 0017:39's ≤800 (+58%) and the card nowhere acknowledges it, though it applies exactly that pattern to `analyze.py` at `.spec.md:1004`
2. Five dangling cross-file citations into moved sections — `PORTS.md:26`, `docs/decisions/0022:5`, `docs/decisions/0023:5`, `task-tracker/test_analyze.py:1`, `task-tracker/test_store.py:3`; round 11 named three of the five, none fixed
3. `.spec.md:387` requires the `cmux send` exit code "logged server-side" but the audit format at `:400` has no field for it and task 9 never asserts it — the same contradiction the card diagnoses for `path`/`errno` at `:403-407`
4. `.spec.md:1088` says "bijection" where `403`→4 reasons, `502`→3, `500`→2; the correct property follows in the same sentence, so a literal test either fails or gets weakened
5. `.spec.md:370`'s `405` row read literally makes `POST /command` a `405`, contradicting the only state-changing route and the `204 OPTIONS` line below it
6. `phase: planning` while `analyze.py`/`store.py`/two test files (2,063 lines) are committed and 53 tests pass, tasks 1–3 and 5–7 ticked — flagged rounds 10 and 11, unfixed
7. Both halves describe the sync guard as keying "on the task number only"; it keys on the normalized text before the first em dash (`feature_tasks.py:51-55`) — same describe-the-data-not-the-mechanism shape as round 10's violation
8. Task 4 re-opened and confirmed accurate: criterion 1's selector is asserted in one direction only; no test covers a non-`.spec.md` file carrying no frontmatter
9. Criterion 13 needs a connected browser extension, does not run under `uv run pytest`, does not run unattended — a stated and accepted cost, carried forward
10. `analyze.py` at 792/800 lines, unchanged; the `git_facts.py` split is named and deliberately unscheduled
11. `verdicts.jsonl` still has no entry for `3ca4daf` (round 11 finding) — not reconstructed here rather than fabricate a timestamp
