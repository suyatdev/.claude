# Observability verdict — `feat/tracking-feature-state` (architecting, advisory)

- **Repo:** `tracking-feature-state` (worktree of `~/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `128e79c0f3d5a243252262b41ab6001f71d41875`
- **Base:** `main` · **Stage:** `architecting` — advisory, blocks nothing
- **Predecessor:** round 12 (`7ba5e0f`), `coding-memory/observability-judge/2026-08-10-feat-tracking-feature-state-round12.md`
- **Artifact:** the pair `docs/features/tracking-feature-state.md` (216 lines) +
  `docs/features/tracking-feature-state.spec.md` (1473 lines), read in full from source, plus a
  direct check of the built code (`task-tracker/server.py`, `analyze.py`, `store.py`) the design
  describes

## What was changed

Think of this card as a building's blueprint that keeps getting redlined by inspectors, and the crew
keeps pouring concrete on parts everyone already agreed on while the blueprint is still being marked
up. Since round 12 (two days ago), the crew has: built the control server (694 lines — the guarded
front door to a Claude session with full permissions), vendored all nine local copies of the six
remote assets so the page no longer phones home to `unpkg.com`/Google Fonts, run the real
browser-verification criterion twice, and closed the five dangling cross-file citations round 12
flagged. Then a compliance-judge round caught something new: the card had flipped back to
`phase: planning` to legally revise the spec, but left the branch and nine ticked tasks in place —
looking, on paper, like a spec edit made mid-implementation without permission. The commit at `HEAD`
(`128e79c`) closes that by writing down, in the card itself, that this is a deliberate, temporary
"paused for revision" state — not a fourth phase the field can express, so the convention is
documented instead of invented.

## Does it do what you wanted?

Yes, on the two things that matter most for a component this card itself calls "the highest-value
target this repo has ever exposed." I checked both against the code, not the prose:

| Check | Method | Result |
|---|---|---|
| Toolchain pins | ran every command in §Toolchain | **exact match** — Python 3.9.6, uv 0.11.28, node v26.5.0, cmux 0.64.20, pytest 9.1.1 |
| Test suite | `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` | **54 passed**, 0 skipped (`node` present, so criterion 5's JS oracle genuinely ran) |
| Task-number sync | `python3 hooks/lib/feature_tasks.py <.md> <.spec.md> tracking-feature-state` | **exit 0** |
| The five round-12 dangling pointers | grepped `PORTS.md`, ADR 0022, ADR 0023, both test-file docstrings | **all five now correctly point at `.spec.md`** |
| Spec-vs-code for the trust boundary | grepped `server.py` for `STATIC_MANIFEST`, `path_escape`, `X-Tracker-Token`, `Cache-Control: no-store`, `frame-ancestors` | present and matching the wire contract as written |

The design's central discipline — derive counts, don't pin them; run real browsers instead of
grepping for asset references — is not just stated, it is followed: the manifest, the reason enum,
and the CSP all cross-check against the live server rather than against each other's prose.

## What could go wrong / what I'm unsure about

**Nothing here is a `fail`.** This is still a paused-for-revision design with real, already-tested code
behind part of it. Five things are worth a second look, three of them repeats.

**1. `server.py` has no automated test yet, and it is the component the whole card calls the new trust
boundary.** Task 9 (`test_server.py`) is unticked. Task 8's own note says the wire contract was
"smoke-verified against a cmux shim" — a manual pass, not a suite. Until task 9 lands, the allowlist
enforcement, the collapsed `403`, the DNS-rebinding `Host` check, path-traversal refusal, and the
surface re-resolution that stops keystrokes reaching the wrong session are all currently validated by
inspection and one afternoon's smoke test, not by anything that reruns. This is honestly tracked (the
box is unticked, not silently claimed done) — but it is the gap with the most consequence if skipped.

**2. Three spec-text defects round 12 found are still open, unfixed, across several more editing
rounds that touched the surrounding text for other reasons:**

- `.spec.md:437` still says a failed `cmux send`'s exit code is "logged server-side," but the
  structured audit-log format two paragraphs later (`.spec.md:479`) still has no field for it. I
  checked the actual code: it *is* logged, but as an ad-hoc `sys.stderr.write` outside the structured
  line (`server.py:273`), not through the mechanism the card describes. This is the exact
  described-but-uncheckable shape the card's own `path`/`errno` warning two paragraphs below it exists
  to prevent — happening again, next to the warning about it.
- `.spec.md:1285` still calls the reason/status relationship a "bijection," though `403` maps to four
  reasons and `502` to three — not one-to-one. The correct property is stated right after it ("every
  row has a value, every value has a row"), so a careful reader is fine; a literal one is not.
- `.spec.md:415`'s `405` row — "Any method other than `GET` on `/` ..., or `POST`/`OPTIONS` on
  `/command`" — still reads ambiguously enough that a literal parse makes `POST /command` a `405`,
  contradicting the only state-changing route eleven lines below it.

  None of the three is functionally wrong — the implementation already does the right thing — but all
  three have now survived at least one more full compliance round (round 2, `HEAD`) without being
  caught, which is worth noticing on its own: the compliance judge's rubric (writing-specs,
  core-conduct) doesn't cover "does this match a prior observability finding," so nothing currently
  closes the loop between the two judges' finding-lists.

**3. A size overrun the card itself would flag if it applied its own rule to itself.** `server.py` is
built at **694 lines**. Task 8's spec entry (`.spec.md:1228-1230`) still says, prospectively, it
"will land near the 400-line target. If it crosses, the split is `task-tracker/serve_static.py`;
raise it rather than taking it as a drive-by." Task 8 is now ticked — the file has landed, 73% past
that target, in the same territory as `analyze.py` (792/800). `analyze.py`'s overrun gets an explicit,
present-tense "not scheduled — a structural split is a human-owned call" note right below its own
line count. `server.py`'s entry never got the update from future tense to present tense once the file
existed. Same pattern the card diagnoses elsewhere in itself, not yet caught here.

**4. The `.spec.md` size waiver may be resting on a stale number.** I traced the actual commit where
the user accepted the `.spec.md` overrun (`2c66fab`, 2026-08-10): at that commit the file was **1278**
lines. It is now **1473** — **+195 lines (+15%)** across the subsequent rounds that added the
`path_escape` fix, the criterion-13 babel resolution, and the phase-mismatch note. The card's own text
states the tripwire for exactly this situation: *"if the gap widens much beyond a handful of lines,
raise the cap in an ADR amending 0017 rather than letting this waiver quietly cover an unbounded
section."* 195 lines is not a handful, and nothing in the current text flags that the accepted figure
has drifted this far past what was signed off.

**5. The phase/branch state is now well-documented, not just left contradictory** — this is the one
item that improved rather than persisted. Round 2's `gates/phase-branch-mismatch` finding is closed by
writing the convention down in the card's own preamble rather than inventing a fourth phase value, and
the note is worded to name its own exit condition (`gate confirmed`). This is the right fix for a
three-state field that genuinely cannot express "paused for revision" — worth flagging only because it
is a textual convention, not a mechanism; nothing computational currently distinguishes this state from
an actual phase violation.

## What I'd double-check before merging

Advisory stage — this gates nothing, but here is what I'd want closed or explicitly deferred before
the implementation gate reopens:

1. **Land task 9 before trusting `server.py` in anything beyond a manual smoke test.** This is the
   component the card itself calls the highest-value target in the repo; it currently has zero
   automated coverage.
2. **Fix the three carried-forward spec-text defects in one pass** — add an exit-code field to the
   audit format (or drop the "logged server-side" claim from `:437`), replace "bijection" with the
   sentence that already states the real property, and add one comma to the `405` row.
3. **Update task 8's entry from future to present tense now that the file exists**, and either
   schedule the `serve_static.py` split or explicitly defer it the way `analyze.py`'s is deferred —
   silence here is the one inconsistency-with-itself this card would flag anywhere else.
4. **Re-confirm the `.spec.md` size waiver against the current 1473, not the 1278 it was granted
   against** — a one-line "still accepted at N lines" costs nothing and keeps the waiver honest by the
   card's own stated standard.

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | **pass** | Design matches the stated goal exactly; spot-checked against the live code (manifest, `path_escape`, token handling, CSP) and it matches what the spec describes |
| `execution` | **concern** | 54/54 tests pass, toolchain pins exact, sync check exit 0 — but the trust-boundary component (`server.py`) has no automated test yet; only manual smoke verification |
| `trajectory` | **pass** | Derivation-over-pinning discipline is real and followed; 12+ observability rounds and a dozen-plus compliance rounds with genuine defects found, fixed, and independently reverified — not luck |
| `regression` | **pass** | All five round-12 dangling cross-file pointers (`PORTS.md`, ADR 0022, ADR 0023, two test docstrings) are now fixed and verified; no new dangling references found |
| `context_budget` | **concern** | `.md` half 216 vs ADR 0017's ≤200 (marginal, user-waived); `.spec.md` 1473 vs ≤800 (waived at 1278, now +195 lines/+15% past the accepted figure with no fresh acknowledgment) |
| `traceability` | **concern** | Internally strong — citations resolve, code cross-checks match — but three round-12 spec-text defects (exit-code field, "bijection" label, `405` ambiguity) persist unfixed across further rounds, and `server.py`'s size overrun is undocumented where `analyze.py`'s equivalent is |
| `success_masking` | **pass** | Design actively engineers against it — set-equality browser checks catch both under- and over-serving, explicit falsification instructions on the mapping test, honest "not verified" (not "skipped, therefore fine") language for node-guarded tests |
| `intent_drift` | **pass** | Every commit since round 12 addresses a named, tracked finding (security, vendoring, dangling pointers, phase documentation); no drive-by edits found |
| `checkpoint` | **pass** | Clean tree at `HEAD`, discrete atomic commits, `Doc-Exempt` trailers used correctly on docs-only commits |
| `audit_trail` | **pass** | Exceptional ADR/commit/verdict discipline (0017, 0022, 0023, 0024; `Claude-Session` links; `Co-Authored-By` trailers); the one soft spot is that the two judges' finding-lists don't currently cross-check each other, which is how item 2 above survived unnoticed |

**Risk: low.** **Confidence: high** — every factual claim above was independently re-derived: the test
suite was actually run, the toolchain pins actually re-checked, the sync checker actually invoked, the
dangling-pointer fixes actually grepped, the size-waiver drift actually traced through git history to
the exact commit and line count, and the exit-code claim actually checked against `server.py`'s source
rather than trusted from the spec's own words.

## Concerns

1. `server.py` (694 lines, the card's own "highest-value target") has no automated test yet — task 9 is open; current coverage is a manual smoke test against a cmux shim
2. `.spec.md:437` claims a failed `cmux send` exit code is "logged server-side" but the structured audit format at `:479` has no field for it; the code logs it via a separate ad-hoc `stderr.write` (`server.py:273`), not the mechanism described — carried forward from round 12, unfixed across two more editing rounds
3. `.spec.md:1285` calls the reason/status relationship a "bijection" where `403`→4 reasons and `502`→3; the correct property is stated in the same sentence, so a literal-reading test-writer is the only one at risk — carried forward from round 12, unfixed
4. `.spec.md:415`'s `405` row reads ambiguously enough that a literal parse makes `POST /command` a `405`, contradicting the state-changing route eleven lines below — carried forward from round 12, unfixed
5. Task 8's spec entry (`.spec.md:1228-1230`) still describes `server.py`'s size in future tense ("will land near the 400-line target") though task 8 is ticked and the file is built at 694/800 — the same species of unremarked overrun the card explicitly flags and defers for `analyze.py`, not yet applied to itself
6. The `.spec.md` size waiver was accepted at 1278 lines (`2c66fab`, 2026-08-10); the file is now 1473 (+195/+15%) — past the card's own stated "much beyond a handful of lines" tripwire for re-raising with a human, with no fresh acknowledgment recorded
7. The `phase: planning` / populated-branch / ticked-tasks state is now documented as a deliberate convention rather than a contradiction — improved from round 2's finding, but remains a textual convention with no computational check distinguishing it from an actual phase violation
8. No cross-check currently exists between the observability judge's own carried-forward findings and the compliance judge's rubric, which is how items 2–4 survived a full compliance round unnoticed
