---
phase: implementation
model_tier: low
branch: chore/treko-chrome-156-repin
---

# Re-pin Treko's browser tests to Chrome `156.0.8078.79`

Opened 2026-10-31. Chrome auto-updated on this machine from `152.0.7977.65`, the build
`treko/cdp_harness.py:70` pins, to `156.0.8078.79`. `cdp_harness.Chrome.__init__` checks the pin
before it launches anything (`:204-211`), so every browser-driven test in `treko/` now fails before
it reaches a page: **35 failed and 14 errored of 310** (§Verification, step 3). The pinned build is
gone from disk, so the pin has to move.

Since card D, moving it is a re-measurement and not a one-line edit:
`treko/test_nontext_contrast.py` stores 104 values read out of a rendered page. **All 104 have been
re-measured on `156.0.8078.79` and reproduce exactly, and so do the three figures quoted in
`treko/test_theme.py`'s comments** (§Verification, step 4). That is Path A: the implementation is
the pin, its dated comment, and the bookkeeping in two closed cards.

Background lives in card A (`treko-theme-and-layout.md` §"Pinned versions", `:789-825`) and card D
(`treko-non-text-contrast.md` §"Pinned versions" `:859-875`, and its re-pin record `:1025-1056`).
None of it is restated here.

## Why a card at all

Both earlier re-pins rode inside an open card. `54c84e1` (2026-08-24, to `152.0.7977.54`) landed in
card A mid-task-7, recorded at card A `:800-825`. `03e17ae` (to `.65`) landed in card D as criterion
10's one declared exception, recorded at card D `:1025-1056` by `4a4d2ed`. Both cards are now
`phase: review` with `branch: none`, and `treko-card-d-followups.md:36` says not to reopen card D's
branch.

`treko/cdp_harness.py` is not on `phase-guard.sh`'s exempt list (`hooks/phase-guard.sh:303-312`
exempts `docs/*`, not `treko/*`). The guard therefore denies the write on any branch that no
`implementation` or `review` card records, while an un-superseded `planning` card exists, and
`origin/main` carries ten `phase: planning` cards. This card is how that mechanism is satisfied, for
the same reason `treko-card-d-followups.md` exists (its §"Why a card at all", `:22-30`).

## Scope

**In:**

- `treko/cdp_harness.py`: `PINNED_VERSION` at `:70` becomes `"156.0.8078.79"`, and the comment at
  `:49-69` gains a third dated paragraph. Both existing paragraphs stay word for word, including
  `:61-69`'s warning that the 2026-08-24 rationale "no longer covers a re-pin on its own".
- The two live pin rows: `treko-theme-and-layout.md:800` and `treko-non-text-contrast.md:867`
  (task 5).
- This card.
- **Conditional, and not needed on the step-4 measurement:** recorded values in
  `test_nontext_contrast.py` (Path B only), and the comment figures at `test_theme.py:324`/`:377`
  (only if they moved).

**Off limits:** `Treko.dc.html`, `nocturne.css`, `_ds/`, `conftest.py`, `server_harness.py`, and
both page-walk scripts (`NONTEXT_WALK_JS` at `test_nontext_contrast.py:82-333`, `CONTRAST_CHECK_JS`
at `test_theme.py:220-318`). Also off limits: every assertion, `PIN_FLOOR`, `DEBT_TOLERANCE`, the
palette (card D §D5 says a repair needs its own card), ADR 0037, and every historical pin mention
listed in task 5.

## Constraints

- Work in worktree `treko-chrome-156-repin`, branch `chore/treko-chrome-156-repin`, cut from
  `origin/main` at `dddd183`. Scope every commit with `-- <paths>`.
- Run every Chrome-driven command from `treko/` with `TREKO_CHROME_DENY_BIRD=1`, and bracket it with
  `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version`. Discard any run whose
  two readings differ.
- Scratch scripts live outside the repo, run with `python3 -B`, and are never committed.
- `server_harness.py`'s fake `cmux` writes the full environment to its log (`:58-62`). Never print
  `Server.cmux_calls()`, that log, or an environment.
- When grepping pytest output for a failure message, set `COLUMNS=400`. With output redirected,
  pytest cuts each short-summary line at 80 columns and the message drops off (step 3).

## Inventory: every value a Chrome build can move

Each row was verified against `dddd183` on 2026-10-31. `tnc` = `treko/test_nontext_contrast.py`.

| values | where | n | asserted by |
|---|---|---|---|
| scored marks, dark 334 / light 347 | `tnc:42` | 2 | `test_scored_mark_count_is_exact`, `tnc:431-446` |
| exclusions: blurred fills 1, gradient-painted elements 5, marks over a background image 0 | `tnc:58`, `:59`, `:60` | 3 | `test_enumerated_exclusions_are_at_their_recorded_counts`, `tnc:473-505` |
| colour strings, exactly as Chrome serialises them | `ALLOWLIST`, `tnc:535-752`. Most fragile: the `color(srgb …)` at `:655`, and the alpha `rgba()` strings at `:626`, `:628`, `:636`, `:638`, `:645`, `:647`, `:657` and `:749` (two) | 47 | `test_every_scored_key_maps_to_exactly_one_entry`, `tnc:835-874` |
| per-entry mark counts (334 + 347 = 681) | the `"marks"` field of each `ALLOWLIST` side | 46 | `test_every_entry_sits_at_its_recorded_mark_count`, `tnc:880-897`, via `_entry_counts` (`:775`); a miss prints the `:786` delta table |
| DEBT minima, 4 dp | `tnc:590`, `:592`, `:600`, `:602`, `:618`, `:620` | 6 | `test_debt_tokens_sit_at_their_recorded_ratio`, `tnc:1016-1054`, via `_token_minimum` (`:922`); the walk rounds at `:312` |
| **stored, in total** | | **104** | |
| colour-parse failures = 0 | `tnc:466` | invariant | `test_no_colour_parse_failures`, `tnc:452-470`. Non-zero means the walk itself must change: out of scope, so STOP |
| comment figures 902 / 851 / 368 | `test_theme.py:324` (902); `:377` (851 and 368) | 3 | nothing; this is prose, and the assertion at `:382` is `>= 200` |
| `test_theme.py`'s colour reader | `parseColor`, `test_theme.py:222-229`: matches `rgba?(…)` and splits on `,`; anything else becomes transparent (`:225`) | risk | **silent** if Chrome ever drops the commas: a space-separated `rgb()` parses to `NaN` channels, `NaN < floor` is false, and nothing fails |
| full-viewport overlay = window size (no classic scrollbar) | `test_drawer.py:110` and `:149` (the scrim is matched on `window.innerWidth`/`innerHeight`); `:277` (panel flush right) | assumption | fails **loudly** |

**Not build-dependent (checked):**

- `PIN_FLOOR = 3.0` (`tnc:533`) and `DEBT_TOLERANCE = 0.0005` (`tnc:915`) are constants.
- The drawer width and height checks (`test_drawer.py:281-288`) derive their expectation from the
  live viewport.
- The sidebar's 300 (`test_sidebar.py:274`, `:278`) is the drag target the test feeds in.
- `test_drawer_sections.py` compares against the page's own resolved tokens (`:24`, `:269-286`).
- `test_guards.py`'s sha256s hash file bytes (`:185`, `:190`).
- No test reads a screenshot or a pixel.
- Card A's Proof B hashes are an archived `151` receipt that is never re-derived (card A
  `:815-817`).

**Already stale before this card:** card A `:800` and card D `:867` still name `152.0.7977.54`.
Card D `:867` also cites `cdp_harness.py:60`, which was right at `54c84e1`; the pin has sat at `:70`
since `03e17ae`. Task 5 fixes both rows.

## Decisions

- **D1: re-pin to `156.0.8078.79` (the user, 2026-10-31).** Not Chrome-for-Testing and not a
  downgrade: `152.0.7977.65` is gone from disk. `Google Chrome Framework.framework/Versions/` holds
  `155.0.8059.85`, `156.0.8078.49` and `156.0.8078.79` (checked 2026-10-31).
- **D2: afterwards, merge `origin/main` into `feat/treko-degraded-no-cmux` once (the user,
  2026-10-31).** Do it after this card's PR merges. No cherry-pick, and no rebase, because that
  branch's commits are pushed. The merge is `treko-degraded-no-cmux.md`'s work: that card carries
  the blocker note this card clears (`:1495-1498` on its branch).
- **D3: no ADR (the approved plan, 2026-10-31).** Neither earlier re-pin wrote one: `54c84e1` and
  `03e17ae` touch nothing under `docs/decisions/`. The record is this card plus the dated paragraph
  in `cdp_harness.py`. ADR 0037's `:15` ("Measured at … Chrome `152.0.7977…`") stays as history.

## Risks

1. **156 moves a value (Path B).** Measured: it did not (step 4). If task 1's run disagrees with
   that measurement, stop and name the cause of each change from the walk output before
   re-recording anything. A pure re-serialisation of a known token's colour is re-recordable: one
   unmatched key plus one entry matching nothing, with the same count on the same elements. A new
   colour, a parse failure, or a `test_theme.py` contrast violation means stop and ask. Never
   repaint the palette here.
2. **Chrome updates again mid-card.** Going by the `Versions/` directory dates, `.49` arrived
   2026-10-27 and `.79` arrived 2026-10-29. This is the third forced re-pin in ten weeks
   (`54c84e1`, `03e17ae`, and this card). The pin check is an exact build match, so any move fails every
   browser test at construction. Check the version around every run. If it moves, step 4's
   measurement is void: re-measure before moving the pin again.
3. **The bird hang** (`cdp_harness.py:75-101`). macOS is now 26.6.2; the hatch was written on 26.5.2
   (`:83`). On 2026-10-31 `com.apple.bird` was healthy (`state = running`, `runs = 1`,
   `last exit code = (never exited)`), and a measurement run *without* `TREKO_CHROME_DENY_BIRD`
   launched and agreed byte for byte. If a launch hangs, follow the message at
   `cdp_harness.py:236-240`. `/usr/bin/sandbox-exec` is present.
4. **The drawer's no-scrollbar assumption** (`test_drawer.py:110`, `:149`, `:277`) could break on a
   new build. It would fail loudly: stop and ask. An in-process prediction passed all 9
   `test_drawer.py` tests on 156 (step 4, last subsection). That is a forecast, not task 1's receipt.
5. **The version check is a substring test** (`cdp_harness.py:205`,
   `if PINNED_VERSION not in version`), so `156.0.8078.790` would pass it too. Out of scope; noted.
6. **A grep for a failure message reads 0 when pytest truncated it.** At the old pin,
   `grep -c 'Chrome version mismatch'` over the redirected short summary read **0**, although all 49
   failures were exactly that (step 3). A fully green run prints no summary section at all, so the
   count is 0 there by construction. Always set `COLUMNS=400`, and always read the tally line too.

## Acceptance criteria

1. `PINNED_VERSION` is `"156.0.8078.79"` at `cdp_harness.py:70`. The comment at `:49-69` keeps all
   three existing paragraphs unchanged (the undated `:49-51` lead-in and the two dated re-pin
   notes) and gains a new dated paragraph. On Path A that is the only change under `treko/`
   (`git diff --stat dddd183 -- treko/` names one file; `dddd183` is this branch's base, which
   unlike `origin/main` does not move).
2. On `156.0.8078.79`, with the version unchanged across the run, the five browser files report
   **64 passed, 0 failed, 0 errors**. A `COLUMNS=400` short-summary grep for
   `Chrome version mismatch\|devtools endpoint` reads 0; the same recipe read 49 at the old pin.
3. The full suite reports **310 passed** on two runs, and both runs' node-ID set hashes to
   `c1c4d1d9…539e`, step 3's value.
4. Task 4 shows the suite can fail on 156: at the old pin, on each single-value perturbation, and on
   card D's planted faults 3, 5, 9 and 12. For each, caught/total and the catching test are
   recorded. **Pass rule:** every case in task 4 is caught by the test task 4 names for it, except
   the DEBT ±0.0004 case, which must pass; at the old pin, construction fails with
   `Chrome version mismatch` and no Chrome process starts. A case caught only by some *other* test
   does not meet this criterion. A miss is handled as task 4 says, never recorded and passed over.
5. The two live pin rows name `156.0.8078.79` and point at `cdp_harness.PINNED_VERSION` rather than
   a line number. Every historical mention is untouched, and
   `git grep -n 'cdp_harness.py:60' -- ':!*.jsonl' ':!docs/features/treko-chrome-156-repin.md'`
   is empty. (This card quotes the string itself, so without the second exclusion the grep can
   never come back empty.)
6. An observability-judge verdict is recorded before the PR.

## Tasks

The planning-phase steps are done, and their results are §Verification: the worktree, this card,
the baseline, and the 156 measurement. The tasks below are the implementation phase, labelled
with the approved plan's step numbers 6-11.

- [x] 1 — **Pin commit (plan step 6).** Change `cdp_harness.py:70` to
      `PINNED_VERSION = "156.0.8078.79"`. Add a third paragraph, dated 2026-10-31, to the comment at
      `:49-69`. It should say: re-pinned from `152.0.7977.65` after an auto-update; 49 browser tests
      were failing at construction; every recorded figure was re-measured on this build, as card
      D's §"Pinned versions" requires; all 104 stored values and the 3 comment figures reproduced
      exactly, with byte-identical walks; approved by the user 2026-10-31; detail in this card.
      Keep all three existing paragraphs verbatim. Tick this task in the same commit, because doc-guard
      wants `docs/` staged alongside a source change. Verify, from `treko/`:
      ```
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version   # before
      TREKO_CHROME_DENY_BIRD=1 COLUMNS=400 python3 -m pytest -q test_nontext_contrast.py \
          test_theme.py test_drawer.py test_drawer_sections.py test_sidebar.py > out.txt 2>&1
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version   # after
      tail -1 out.txt                                    # Path A: 64 passed
      awk '/short test summary info/{f=1;next} f' out.txt \
          | grep -c 'Chrome version mismatch\|devtools endpoint'                 # 0
      ```
      On Path B the run must show exactly the failures §Verification predicts, and nothing else.
- [ ] 2 — **Re-record values in place (plan step 7). Path B only, and not needed on the step-4
      measurement.** Only if task 1's run disagrees: edit just the moved values in
      `test_nontext_contrast.py`, each with its named cause recorded here. Change no line counts:
      the degraded card cites `tnc:42`, `:432-442`, `:443` and `:400-401` on its branch. Verify: 64
      passed, and `git diff -U0` touches only the predicted values.
- [ ] 3 — **Comment figures (plan step 8). Only if they moved, and they did not:** 902 / 851 / 368
      on 156 (step 4). Had they moved, this would be a separate, comment-only commit to
      `test_theme.py:324`/`:377`.
- [ ] 4 — **Prove the suite can fail (plan step 9).** Scratch only, no tracked edits.
      - a. Move the pin back to `152.0.7977.65` in-process. Chrome must not start, and
        `pgrep -fl "Google Chrome.*remote-debugging"` must find nothing.
      - b. On one captured walk, call each `tnc` test body with one value changed. The expected
        catcher is named after each arrow (all in `test_nontext_contrast.py`):
        - each scored total ±1 → `test_scored_mark_count_is_exact` (`:432`);
        - each exclusion count ±1 → `test_enumerated_exclusions_are_at_their_recorded_counts`
          (`:474`);
        - one entry's mark count ±1, where the `:786` delta table must name the entry →
          `test_every_entry_sits_at_its_recorded_mark_count` (`:881`);
        - one colour string altered → `test_every_scored_key_maps_to_exactly_one_entry` (`:836`);
        - each DEBT ratio ±0.0006 → `test_debt_tokens_sit_at_their_recorded_ratio` (`:1017`)
          fails; ±0.0004 → the same test passes;
        - one PIN floor set just above its measured minimum → `test_pin_tokens_clear_their_floor`
          (`:979`). The lowest is `--color-accent` in light at 4.6292.
      - c. In a private tree copy, re-run card D's planted faults 3, 5, 9 and 12 (card D `:1070`,
        `:1072`, `:1076`, `:1079`). First confirm each one targets an element the 156 walk
        actually counts; card D `:1085-1091` shows what happens otherwise. Expected catchers,
        from card D's "what actually fired" column: 3 → `test_debt_tokens_sit_at_their_recorded_ratio`
        (dark); 5 → `test_every_entry_sits_at_its_recorded_mark_count` (`--hair`, both themes);
        9 → `test_no_colour_parse_failures` (`:453`); 12 →
        `test_enumerated_exclusions_are_at_their_recorded_counts` (the over-background-image
        count, both themes).
      Record caught/total and the catching test for each. **On a miss:** first check whether the
      fault touched an element outside the 156 walk's population (card D case 5's first
      attempt). If it did, re-point it at a counted element and re-run, recording both attempts.
      If a correctly targeted fault is still not caught by its named test, **stop and ask the
      user**: that means a check is blind on 156, which is outside a re-pin's scope to fix.
- [ ] 5 — **Old-card bookkeeping (plan step 10). Docs only.** Change card A `:800` and card D
      `:867` to `156.0.8078.79`. Cite `cdp_harness.PINNED_VERSION` instead of a line number, and
      add a dated pointer to this card. Leave the historical mentions alone: ADR 0037 `:15` and
      `:130`; card A `:803` and `:1841`; card D `:114`, `:721` and `:1028`;
      `treko-card-d-followups.md:64`. Verify:
      `git grep -n 'cdp_harness.py:60' -- ':!*.jsonl' ':!docs/features/treko-chrome-156-repin.md'`
      is empty. Excluding this card is required because it quotes the string itself. The `*.jsonl`
      exclusion is required too: `coding-memory/compliance-judge/verdicts.jsonl` quotes that
      citation in several historical rows, and the count grows whenever a new verdict quotes it
      (count it with `git grep -c`, don't trust a figure here). A judge ledger is append-only, and without the exclusion the
      grep can never come back empty.
- [ ] 6 — **Full suite twice, then the judge, the PR, and review (plan step 11).** From `treko/`,
      run twice, bracketing each run with `--version`:
      - `TREKO_CHROME_DENY_BIRD=1 COLUMNS=400 python3 -m pytest -q` must report `310 passed`;
      - `python3 -m pytest --collect-only -q | grep '::' | sort | shasum -a 256` must give
        `c1c4d1d945b66c9f74d9bb56d781930dcaad0761a3854c228c48410c947d539e`.
      Then run the observability judge, open the PR, and move this card to `phase: review`.

## Not in scope

- The DEBT repair (card D §D5) and any palette change.
- Hardening the substring check at `cdp_harness.py:205` (risk 5).
- A Chrome-for-Testing pin, which would end forced re-pins. D1 rejects it for this card.
- The `feat/treko-degraded-no-cmux` merge (D2). That card does it, after this PR merges.

## Verification

### Step 3: baseline at the old pin, no edits (2026-10-31, `dddd183`)

Collection, which involves no Chrome:

```
$ python3 -m pytest --collect-only -q | tail -2

310 tests collected in 0.21s
$ python3 -m pytest --collect-only -q | grep '::' | sort | shasum -a 256
c1c4d1d945b66c9f74d9bb56d781930dcaad0761a3854c228c48410c947d539e  -
```

Two runs gave identical output, matching the expected `c1c4d1d9…539e`. That expected value is the
degraded card's task-1 baseline, taken at `76348c4`. `git diff --stat 76348c4 dddd183 -- treko/` is
empty, so the comparison is like for like.

The full run, with the version checked on both sides:

```
$ "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
Google Chrome 156.0.8078.79
$ TREKO_CHROME_DENY_BIRD=1 python3 -m pytest -q > baseline-full.txt 2>&1     # rc 1
$ tail -1 baseline-full.txt
35 failed, 261 passed, 14 errors in 131.71s (0:02:11)
$ "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
Google Chrome 156.0.8078.79
```

That matches the expected 35 / 261 / 14. The mismatch count is where the recipe mattered. **This is
a finding, not a failure**; the expected value was 49:

```
$ awk '/short test summary info/{f=1;next} f' baseline-full.txt | grep -c 'Chrome version mismatch'
0
$ grep -c '^E *AssertionError: Chrome version mismatch' baseline-full.txt
49
```

The 0 comes from truncation, not absence. The summary lines are cut at 80 columns
(`FAILED test_drawer.py::test_criterion12_the_gear_opens_the_drawer - Assertion...`). All 49
traceback lines name `installed 'Google Chrome 156.0.8078.79'`. With the width lifted, the summary
carries the message. On the five browser files alone:

```
$ TREKO_CHROME_DENY_BIRD=1 COLUMNS=400 python3 -m pytest -q test_nontext_contrast.py test_theme.py \
      test_drawer.py test_drawer_sections.py test_sidebar.py > b5.txt 2>&1
$ tail -1 b5.txt
35 failed, 15 passed, 14 errors in 10.08s
$ awk '/short test summary info/{f=1;next} f' b5.txt | grep -c 'Chrome version mismatch\|devtools endpoint'
49
```

By file: 12 failed in `test_theme.py`, 11 in `test_drawer_sections.py`, 8 in `test_sidebar.py` and
4 in `test_drawer.py`; `test_nontext_contrast.py` had 14 errors. Both runs failed on the same 49
node IDs: their sorted `FAILED|ERROR <node>` lists both hash to `e51abf3e…65b1af`.

### Step 4: the re-measurement on `156.0.8078.79` (2026-10-31)

**Recipe.** A scratch script (`measure156.py`, not committed) imports `cdp_harness`,
`server_harness`, `test_nontext_contrast` and `test_theme` from `treko/`, and reuses their code
throughout. It refuses to run unless `--version` reads exactly `Google Chrome 156.0.8078.79` and the
on-disk pin reads `152.0.7977.65`. It then sets `cdp_harness.PINNED_VERSION = "156.0.8078.79"` on
the imported module, in memory only; nothing is written. It builds a private tree
(`server_harness.build_tree`), starts `server_harness.launch` and one `cdp_harness.Chrome`, and for
each theme:

1. runs `_apply_theme` (`tnc:363`), then takes walk 1 with `chrome.evaluate(NONTEXT_WALK_JS)`
   (`tnc:82`);
2. calls `chrome.reload()` and `_wait_for_mount`, re-asserts `data-theme`, and takes walk 2;
3. runs `CONTRAST_CHECK_JS` (`test_theme.py:220`), counts elements with rendered area (the two
   walks' shared first gate, alone), and reads `document.querySelectorAll('body *').length`;
4. collects every distinct colour string on the page and runs each through **both** colour
   readers, which are extracted byte for byte from their JS constants rather than re-implemented.
   It reads computed `color`, `background-color`, the four border colours, SVG `fill`/`stroke`,
   and box-shadow colours, over `html`, `body` and every `body *` element;
5. last, appends a probe element, reads how Chrome serialises each of the 23 tokens, and removes
   the probe.

Finally it calls the 16 `tnc` test bodies on walk 1 (a prediction, not a pass), closes Chrome,
stops the server, and deletes the private tree, which holds the fake `cmux`'s environment log.

There were two runs. Each was bracketed by `--version` = `Google Chrome 156.0.8078.79`, and CDP
`Browser.getVersion` reported `Chrome/156.0.8078.79` in both.

- `denybird-1` ran with `TREKO_CHROME_DENY_BIRD=1`, so Chrome ran under `sandbox-exec`.
- `nodenybird-1` ran with the variable removed by `env -u`, so Chrome launched normally.

**Result: Path A. No STOP condition.**

- 0 of 104 stored values moved.
- In both themes the two walks were byte-identical, with 0 parse failures.
- The run without `DENY_BIRD` matched exactly: the same four walk hashes, counts, contrast results,
  colour inventory and token probe.
- All 16 `tnc` bodies pass on the captured walk.

#### Totals and exclusions (5 values)

| stored value | where | recorded | dark | light |
|---|---|---|---|---|
| `SCORED_MARKS` | `tnc:42` | 334 / 347 | 334 | 347 |
| `EXCLUDED_BLURRED_FILLS` | `tnc:58` | 1 | 1 | 1 |
| `GRADIENT_PAINTED_ELEMENTS` | `tnc:59` | 5 | 5 | 5 |
| `MARKS_OVER_BACKGROUND_IMAGE` | `tnc:60` | 0 | 0 | 0 |

#### Allowlist: 47 colour strings and 46 mark counts

A ✓ means the recorded string is `==` to a key in the walk (within the entry's `kinds`) **and** to
the token probe's reading. Marks are shown as recorded / measured, via `_entry_counts`. This table
was generated from the saved measurement and the imported, unedited module, not typed by hand.

| token | class | dark colour | ok | dark marks | light colour | ok | light marks |
|---|---|---|---|---|---|---|---|
| `--color-accent` | PIN | `rgb(56, 196, 227)` | ✓ | 34 / 34 | `rgb(0, 116, 146)` | ✓ | 34 / 34 |
| `--color-accent-300` | PIN | `rgb(130, 216, 240)` | ✓ | 2 / 2 | `rgb(0, 109, 136)` | ✓ | 2 / 2 |
| `--ok` | PIN | `rgb(130, 223, 169)` | ✓ | 4 / 4 | `rgb(18, 121, 74)` | ✓ | 4 / 4 |
| `--warn` | PIN | `rgb(216, 176, 108)` | ✓ | 7 / 7 | `rgb(138, 97, 19)` | ✓ | 7 / 7 |
| `--bad` | PIN | `rgb(232, 150, 142)` | ✓ | 7 / 7 | `rgb(176, 58, 48)` | ✓ | 7 / 7 |
| `--info` | PIN | `rgb(137, 180, 242)` | ✓ | 1 / 1 | `rgb(40, 86, 159)` | ✓ | 1 / 1 |
| `--color-accent-700` | DEBT | `rgb(34, 122, 147)` | ✓ | 21 / 21 | `rgb(164, 226, 243)` | ✓ | 21 / 21 |
| `--color-neutral-700` | DEBT | `rgb(89, 93, 108)` | ✓ | 35 / 35 | `rgb(110, 114, 126)` | ✓ | 35 / 35 |
| `--color-neutral-800` | DEBT | `rgb(63, 66, 77)` (fill) | ✓ | 22 / 22 | `rgb(227, 230, 239)` (fill) | ✓ | 22 / 22 |
| `--hair` | EXEMPT | `rgba(255, 255, 255, 0.06)` | ✓ | 42 / 42 | `rgba(15, 18, 35, 0.09)` | ✓ | 42 / 42 |
| `--hover` | EXEMPT | `rgba(255, 255, 255, 0.05)` | ✓ | 30 / 30 | `rgba(15, 18, 35, 0.05)` | ✓ | 30 / 30 |
| `--hover-soft` | EXEMPT | `rgba(255, 255, 255, 0.03)` | ✓ | 2 / 2 | `rgba(15, 18, 35, 0.03)` | ✓ | 2 / 2 |
| `--color-divider` | EXEMPT | `color(srgb 0.913725 0.913725 0.929412 / 0.16)` | ✓ | 40 / 40 | `rgba(15, 18, 35, 0.12)` | ✓ | 40 / 40 |
| `--color-bg` | EXEMPT | `rgb(22, 24, 38)` | ✓ | 18 / 18 | `rgb(245, 246, 250)` | ✓ | 18 / 18 |
| `--color-surface` | EXEMPT | `rgb(28, 30, 43)` | ✓ | 14 / 14 | `rgb(255, 255, 255)` | ✓ | 14 / 14 |
| `--rail` | EXEMPT | `rgb(18, 19, 30)` | ✓ | 1 / 1 | `rgb(236, 238, 245)` | ✓ | 1 / 1 |
| `--color-neutral-900` | EXEMPT | `rgb(41, 43, 49)` | ✓ | 11 / 11 | `rgb(240, 242, 248)` | ✓ | 11 / 11 |
| `--ok-bg` | EXEMPT | `rgb(18, 53, 38)` | ✓ | 5 / 5 | `rgb(219, 243, 230)` | ✓ | 5 / 5 |
| `--warn-bg` | EXEMPT | `rgb(58, 45, 21)` | ✓ | 5 / 5 | `rgb(250, 238, 210)` | ✓ | 5 / 5 |
| `--bad-bg` | EXEMPT | `rgb(66, 32, 29)` | ✓ | 6 / 6 | `rgb(251, 226, 223)` | ✓ | 6 / 6 |
| `--info-bg` | EXEMPT | `rgb(22, 41, 74)` | ✓ | 3 / 3 | `rgb(223, 233, 251)` | ✓ | 3 / 3 |
| `--color-accent-900` | EXEMPT | `rgb(16, 56, 69)` | ✓ | 11 / 11 | `rgb(226, 246, 252)` | ✓ | 11 / 11 |
| `--shadow-sm` | EXEMPT | `rgb(63, 66, 77)` (shadow-outset) | ✓ | 13 / 13 | `rgba(15, 18, 35, 0.06)`, `rgba(15, 18, 35, 0.07)` (shadow-outset) | ✓ | 26 / 26 |

All 47 colour strings and all 46 counts match. The measured per-entry marks sum to 334 dark and
347 light, equal to the scored totals, so no mark is claimed twice or left unclaimed.

#### DEBT minima (6 values, 4 dp; shown as recorded / measured)

| token | dark | light | the minimum comes from |
|---|---|---|---|
| `--color-accent-700` | 2.8791 / 2.8791 (`:590`) | 1.2718 / 1.2718 (`:592`) | its one outset shadow (borders: 3.3648 dark, 1.3182 light) |
| `--color-neutral-700` | 2.5253 / 2.5253 (`:600`) | 4.8042 / 4.8042 (`:602`) | a tie: all six kinds are equal at 4 dp |
| `--color-neutral-800` | 1.6519 / 1.6519 (`:618`) | 1.2477 / 1.2477 (`:620`) | fills, its only kind |

`--color-neutral-700`'s reason string (`tnc:596-598`) and card D §D2 both say "an SVG stroke".
Measured at 4 dp, nothing tells the stroke apart from the borders or fills. The same holds for
`--bad` below. The DEBT value itself is unaffected.

#### PIN minima (not stored; the floor is 3.0)

| token | dark | light | card D §D2, 2 dp, on `152.0.7977.54` |
|---|---|---|---|
| `--color-accent` | 8.0107 | 4.6292 | 8.01 / 4.63 |
| `--color-accent-300` | 10.2599 | 5.9272 | 10.26 / 5.93 |
| `--ok` | 10.2972 | 5.4410 | 10.30 / 5.44 |
| `--warn` | 8.1470 | 5.5264 | 8.15 / 5.53 |
| `--bad` | 7.2319 | 6.0104 | 7.23 / 6.01 |
| `--info` | 7.7753 | 7.1869 | 7.78 / 7.19 |

All twelve round to card D's figures. The lowest is `--color-accent` in light, 4.6292 (a
`border-left`), which is the input for task 4b's floor probe.

#### test_theme.py comment figures (3 values)

| figure | where | dark | light |
|---|---|---|---|
| `body *` count at mount (`_wait_for_mount`'s return; also 902 before the walks, after them, and after the probe was removed) | `:324`, 902 | 902 | 902 |
| elements with rendered area (the area-only count; the walk's `elementsWithArea` agrees) | `:377`, 851 | 851 | 851 |
| `CONTRAST_CHECK_JS` `elementCount` | `:377`, 368 | 368 | 368 |
| `CONTRAST_CHECK_JS` `violationCount` | criterion 5 asserts 0, in light only | 18 | **0** |

Dark's 18 is not asserted, and it is not new. Card A `:1388` records the same narrowed check at
"104 → 18", and card D `:404` repeats it. All 18 are one pair: `rgb(89,93,108)` text on
`rgb(28,30,43)`, at 2.53:1.

#### Per-kind breakdown of the scored marks

| kind | dark | light |
|---|---|---|
| `fill` | 135 | 135 |
| `border-top` | 64 | 64 |
| `border-bottom` | 39 | 39 |
| `border-left` | 36 | 36 |
| `border-right` | 35 | 35 |
| `shadow-outset` | 16 | 29 |
| `svg-fill` | 5 | 5 |
| `svg-stroke` | 4 | 4 |
| **total** | **334** | **347** |

There are 174 borders per theme, the count card D §Background 2 records. There are 22 distinct
scored colour strings in dark and 24 in light. That is card D §Background 1's 24 / 26, less the two
marks it explains: the `<svg>` root and the header fill. There are 52 / 53 distinct
`(colour, kind)` keys.

#### Every colour string on the page, through both readers

| | dark | light |
|---|---|---|
| distinct strings | 33 | 35 |
| `rgb(r, g, b)`, comma-separated | 27 | 27 |
| `rgba(r, g, b, a)`, comma-separated | 4 | 7 |
| `color(srgb r g b / a)` | 2 | 1 |
| strict reader (`tnc`) returns null | 0 | 0 |
| lenient reader (`test_theme.py`) disagrees with the strict one | 2 | 1 |

The disagreements are exactly the `color(srgb …)` strings, which the comma-split reader treats as
transparent:

- the sticky header's fill: `color(srgb 0.0862745 0.0941176 0.14902 / 0.9)` in dark and
  `color(srgb 0.960784 0.964706 0.980392 / 0.9)` in light. The walk excludes it as the one blurred
  fill.
- dark `--color-divider`, `color(srgb 0.913725 0.913725 0.929412 / 0.16)`, on 40 borders and 2
  backgrounds.

That blindness predates this card: `:655` recorded the same serialisation on 152, and it matches on
156 byte for byte. Every `rgb()`/`rgba()` string still carries its commas, so the silent-`NaN` risk
in §Inventory did not fire.

#### Walk hashes, for the next re-pin

The JSON hash is
`hashlib.sha256(json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")).hexdigest()`,
where `result` is what `chrome.evaluate(NONTEXT_WALK_JS)` returns (CDP JSON parsed by
`json.loads`). The dump hash is over `("\n".join(result["dump"]) + "\n").encode("utf-8")`.

| theme | canonical-JSON sha256 | dump sha256 | dump lines |
|---|---|---|---|
| dark | `416a61086aee849620cee70f9c0f15a37ee56fbfbe6fdc05c331a0c0a4573680` | `e1c8f6adf97ff51e5426442cfc7b57be08c51a9df98a34665de52b140b3969a4` | 334 |
| light | `6e73f9b95a14e2c31d64808d580664e6f686ad3bdc8db1df652dce5c29122962` | `607ffa381dbf85e1df5dc50db6769d40600dbb53aac9cdfe7c355ebe16b4e870` | 347 |

Each value was produced four times per theme (two walks in each of two runs), and the four agree.
`shasum -a 256` over the saved files reproduces them. **These hashes are valid only for `treko/` as
of `dddd183`.** Any change to `Treko.dc.html`, `nocturne.css` or the sample store moves them for
reasons unrelated to Chrome. A next re-pin can compare like with like only on an unchanged tree;
otherwise, compare the 104 values, not the hashes.

#### Forecast for task 1 (in-process; not a pass)

A scratch pytest plugin rebound `cdp_harness.PINNED_VERSION` in memory. With it, the five browser
files reported **64 passed in 29.36s** on `156.0.8078.79`, with the version unchanged across the
run. That includes all 9 `test_drawer.py` tests (risk 4). The same files without the plugin gave
the step-3 result above, so the override is what turned them green. This forecasts task 1; it is
not task 1's receipt.

### Corrections made while verifying the plan's inventory

- `treko-card-d-followups.md` says not to reopen card D's branch at `:36`, not `:39`. Its "Why a
  card at all" section is `:22-30`.
- On its branch, the degraded card cites `test_nontext_contrast.py:432-442` four times, plus `:443`,
  `:42` and `:400-401`. It does not cite `:432-443`.
- The alpha-bearing colour strings sit at `:626-657` and `:749`, not only `:626-647`.
- `grep -c 'Chrome version mismatch'` over a redirected pytest summary reads 0, because of the
  80-column truncation. Getting 49 needs `COLUMNS=400` or the traceback lines, so tasks 1 and 6 use
  the wide form.
- `git grep 'cdp_harness.py:60'` can never come back empty, because the compliance-judge ledger
  quotes it in 7 rows (counted at `a5b32e2`; the round-1 compliance verdict added another). Task 5
  excludes `*.jsonl`, and, after that verdict found this card quoting the string four times
  itself, excludes this card too.
