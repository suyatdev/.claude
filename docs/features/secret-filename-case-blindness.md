---
phase: planning
model_tier: high
branch: none
---

# `secret-command-guard` matches secret file names case-sensitively

Queued 2026-09-01 out of the observability judge's round-2 read of
`docs/features/argv0-spelling-blindness.md` (branch `fix/argv0-spelling-blindness`, HEAD
`eb02618`). That card folded the **program** name so `Git commit` is caught like
`git commit`. The judge asked the obvious next question and measured it: nobody folded the
**file** name.

Gate: **not confirmed.** No branch, no code. Designed 2026-09-03 — task 1 is measured and
task 2 is decided (see **Decision**); the remaining tasks below are a plan, not a sketch.

## Measured

Through `hooks/secret-command-guard.sh` with a real `PreToolUse` payload
(`hook_event_name`, `tool_name`, `tool_input.command`, `cwd`, `session_id`). **Nothing was
executed** — the guard decides from command text, which is the whole point; a planning judge
on the predecessor card ran an env-dump row through a real shell "to verify" it and leaked a
live API key.

| Command | rc | verdict |
|---|---|---|
| `cat .env` | 2 | blocked (control) |
| `cat .ENV` | 0 | **allowed** |
| `cat .Env` | 0 | **allowed** |
| `cat ~/.zshrc` | 2 | blocked (control) |
| `cat ~/.ZSHRC` | 0 | **allowed** |
| `cat credentials.json` | 2 | blocked (control) |
| `cat CREDENTIALS.json` | 0 | **allowed** |

Every lowercase control refuses, so the group is measured rather than blind.

Cause: `hooks/lib/classify-secret-command.py`, `DOTFILE_PATTERNS` (`:137`) compiled into
`DOTFILE_RE` (`:147`) — plain `re.compile` with no `re.IGNORECASE`, e.g.
`(r"(^|/)\.zshrc$", "~/.zshrc")`. On this machine's case-insensitive APFS, `cat ~/.ZSHRC`
opens the same file.

**Not a regression from `fix/argv0-spelling-blindness`.** That branch changes exactly two
lines in `classify-secret-command.py`, both on the `argv[0]` test (`797663e`). This is
pre-existing.

## Why it is not obviously a one-line fix

`re.IGNORECASE` is the tempting answer and needs thinking about first:

- **Blast radius.** `secret-command-guard.sh` sits on nearly every Bash call, and it
  **fails open** on a classifier error (`:146`) — the opposite direction from `git-guard.sh`.
  A false denial here is expensive; the existing `grep -o` carve-out was removed whole rather
  than narrowed (ADR 0039) precisely because this hook's precision matters.
- **False positives are real.** A path a user legitimately names in caps — a directory
  `ENV/`, a file `Credentials.json` in someone else's project — would start refusing.
  *Measured since, and this concern did not survive contact:* zero such names exist across
  789,829 scanned. See **Task 1**, section B. Kept here as the reasoning the decision had
  to answer, not as a live claim.
- **The filesystem is the actual variable.** The gap exists because APFS is
  case-insensitive. On a case-sensitive volume `cat .ENV` reads a *different* file, and
  folding would invent a refusal. Whether to key the behavior on the filesystem, or fold
  unconditionally and accept the false positives, is a genuine design question.
- **The `Application Support` pattern is already unanchored** and so behaves differently
  from the other seven. Any change here must not silently widen it further.

## Task 1 — per-pattern fold impact, measured

Measured at HEAD `7e3f802` by importing `DOTFILE_PATTERNS` out of the live classifier (the
list is never retyped) and comparing `re.compile(p)` against `re.compile(p, re.IGNORECASE)`.
Nothing was executed and no file contents were read; the probe matches **names** only.

**A. Which patterns change behavior.** All eight flip on a capitalised spelling.

| Pattern label | Flips under folding? |
|---|---|
| `~/.terminal_aliases` | yes |
| `~/.bash_profile` | yes |
| `~/.zshrc` | yes |
| `~/.zprofile` | yes |
| `~/.zshenv` | yes |
| `.env / .env.*` | yes |
| `credentials.json` | yes |
| `*/Application Support/*/credentials*` | **yes** — 4 of 5 sampled spellings flip: `.../Application Support/foo/CREDENTIALS`, `.../APPLICATION SUPPORT/foo/credentials`, `.../APPLICATION SUPPORT/foo/CREDENTIALS`, `.../application support/foo/credentials` |

⚠️ **This row read "no" in the first draft of this card, and that was wrong.** Both judges
caught it independently and it was then reproduced here directly against the pattern. The
cause is worth recording, because it is a failure mode this repo keeps paying for: the
variant generator derived its test spellings from each pattern's *human label*, and for this
row — label `*/Application Support/*/credentials*` — that derivation produced an **empty**
variant list. The row was never tested. Zero flips out of zero cases printed as `flips=[]`,
which is indistinguishable from a genuine "does not flip". **A check that cannot fire reads
exactly like a check that passed.** The replacement probe (task 3) must print a per-pattern
case count, not just a verdict, so an untested row is visibly untested.

**Consequence for the design, stated rather than buried:** this row is the unanchored one,
and folding it *does* widen the widest pattern — which the risk section above specifically
warned against. Accepted, deliberately: `APPLICATION SUPPORT` and `Application Support` are
the same directory on this volume, so the widening closes a real bypass rather than inventing
reach. But it is a widening, and it is not to be described as anything else.

**B. What folding would newly block on this machine — the false-positive question.** Two
walks, both comparing every real path against both compiled forms:

| Scan root | Exclusions | Names scanned | Newly matching |
|---|---|---|---|
| repo worktree + `$HOME` | `.git`, `node_modules`, `Library`, depth ≥ 4 | 29,773 | **0** |
| `~/Library` | none, full depth | 760,056 | **0** |

The `~/Library` walk exists because the first scan excluded it, and `Application Support` —
the one pattern whose breadth is in question — lives nowhere else. Excluding it would have
made the check blind exactly where it mattered.

⚠️ **This scan counts the wrong population, and the number must not be quoted as if it did
not.** The observability judge's round-1 read caught this and it reproduces: **the guard
never looks at the filesystem.** It decides from the *text of the command*, so a name that
exists nowhere on disk can still be typed and still be refused. Reproduced against the
classifier: `Credentials.json` does not exist anywhere in the scan, matches nothing today,
and **is newly blocked under folding**. A disk census cannot see that case, because the case
is not on the disk.

So the two counts above establish a narrower fact than "folding is free":

- **What they do show:** no *existing* file or directory on this machine would newly be
  refused — so folding breaks no path anyone here already uses. That is worth having.
- **What they do not show:** anything about capitalised spellings typed into a command for a
  path that does not exist, which is the population that actually reaches the guard. The
  honest characterisation of the residual false-positive risk is not "zero" but "a
  capitalised spelling of one of these eight names, appearing in a command" — e.g.
  `Credentials.json` in a project that uses that casing.

**Scope the counts to what they measured:** 789,829 names, on *this* machine, at HEAD
`7e3f802`, matched by name. Nothing about a case-sensitive volume, and nothing about
command text.

The filesystem premise is confirmed by direct test rather than assumed: a file written as
`casetest.txt` in the scratchpad read back as `CASETEST.TXT`. `diskutil info /` reports
APFS and prints no `Case-sensitive` line.

## Decision

**Fold unconditionally.** User call, 2026-09-03.

The decision was taken on the round-1 draft, which claimed the false-positive cost was zero.
Round 1 of the compliance and observability judges then showed that claim measured the wrong
population (above). **The decision is retained on the corrected evidence**, restated here so
no reader inherits the superseded reasoning: the residual false-positive is a capitalised
spelling of one of eight specific names typed into a command, it fails in the direction of an
over-refusal with a printed reason and a documented override, and it is not zero.

Rejected: keying the fold on a filesystem probe. It is the technically precise answer, and
it was rejected because the guard runs on nearly every Bash call and is deliberately built
to **fail open** — adding a live filesystem probe inside it buys a correctness win in an
environment this repo is not currently in, and pays for it in the one place where extra
moving parts are most expensive.

Rejected: document-and-close. The gap is a real bypass of a Tier-1 guard on the machine it
actually runs on.

**Residual risk, stated at full strength.** On a case-sensitive volume `cat .ENV` reads a
genuinely different file, and folding would refuse it wrongly. That refusal is not a
one-off annoyance: `secret-command-guard` has **no permitted read shape** and its bypass is
gated on a human typing the literal phrase `secret-gate override` (`rules/gates.md`,
Secret-gate override). So the cost of a false positive is a human in the loop **on every
single occurrence**, not once. That is the accepted trade, and it is accepted because this
repo runs on a case-insensitive volume — verified by direct test, not assumed.

## Pinned versions

The correctness of this change rests entirely on one interpreter's case-folding semantics,
so the interpreter is pinned rather than assumed:

| Tool | Pinned version | How the guard reaches it |
|---|---|---|
| `python3` | **3.9.6** (`python3 --version`, this machine, 2026-09-03) | `hooks/secret-command-guard.sh:78` — `py=$(command -v python3 \|\| command -v python)`, i.e. whatever `python3` is first on `PATH` |
| `re` | stdlib of the above; flag **`re.IGNORECASE`** alone — see below | `classify-secret-command.py` |

## Flag choice — the widest-match question, measured

⚠️ **Round 2 of this card prescribed `re.IGNORECASE | re.ASCII`. That was wrong, and it was
wrong in the dangerous direction.** The reasoning was that bare `re.IGNORECASE` is
Unicode-aware in Python 3 and would newly block three "genuinely different filenames". The
observability judge checked one of those three against the actual volume and it is **not** a
different file: `.zſhrc` (U+017F LATIN SMALL LETTER LONG S) opens the real `.zshrc`. Round 2
would have shipped a green test asserting a live bypass was correct behavior. Recorded rather
than quietly amended, because the failure was *reasoning about the filesystem instead of
asking it*.

**Derivation.** Two independent oracles, neither used to check the other:

- **Ground truth** — write a decoy file under the ASCII name in a scratch directory, then try
  to open it under the substituted spelling. If the decoy content comes back, the volume
  considers them the same file. Scratch directory only; no real dotfile is created, read or
  touched.
- **Guard verdict** — match the substituted spelling against `DOTFILE_PATTERNS` under each
  candidate flag set.

**The population took three rounds to get right, and every earlier figure in this card's
history was understated.** Recording the three holes, because each one produced a confident
wrong table and each was found by a different reader:

1. **Candidates from NFKD alone** (my round 2) — no entry for U+0131 dotless i, which
   casefolds to itself. Fixed by taking the **union** of (a) codepoints whose NFKD + casefold
   lands on one of the ASCII letters in the seven names and (b) codepoints Python's own
   `re.IGNORECASE` matches against those letters.
2. **First occurrence only** (compliance judge, round 3) — `name.find(run)` substituted only
   the first instance of each letter, missing `.terminal_aliaseſ` and `credentials.jſon`,
   both same-file, both live bypasses. Fixed by sweeping **every** position.
3. **Single substitutions only** (observability judge, round 3) — nobody had tried two
   homoglyphs in one name. `.baſh_proﬁle` opens the real file. Fixed by composing every
   non-overlapping combination of confirmed same-file substitutions within a name.

**Result** — 2,336 variants tested on this volume at HEAD `7e3f802`, python3 3.9.6:

| Strategy | Bypasses (of 12 same-file spellings) | False refusals (of 2,324 different-file spellings) |
|---|---|---|
| plain — today | 12 | 0 |
| **`re.IGNORECASE`** | **3** | **10** |
| `re.IGNORECASE \| re.ASCII` | 12 | 0 |
| NFKD + `re.IGNORECASE` | 0 | hundreds — **see below, figure deliberately not published** |

⚠️ **The NFKD false-refusal count is deliberately absent.** Two independent measurements
disagree: this card's sweep returns 577 of 2,324, the compliance judge's round-3 sweep
returned 1,881 of 1,901 on its own population. Both agree the answer is *hundreds*, and the
rejection below does not depend on which is right — so the number is deleted rather than a
third one published. If a future reader needs it, re-derive it; do not resurrect either
figure from this paragraph.

**The 12 breaks down as 9 single-character spellings plus 3 two-character combinations.** The
observability judge independently reported 9; that count is correct for singles and the two
figures reconcile exactly.

Every one of the three fixes closes the ASCII capitalisation gap identically. They differ
**only** on the homoglyph axis, and that axis is a *pre-existing* gap this card discovered —
today's guard misses all 7, so no option here is a regression.

All twelve same-file spellings, and which strategy catches each:

| Protected name | Same-file spelling | Codepoints | plain | `IC` | `IC\|A` | NFKD+`IC` |
|---|---|---|---|---|---|---|
| `.bash_profile` | `.bash_proﬁle` | U+FB01 | · | · | · | ✓ |
| `.bash_profile` | `.baſh_profile` | U+017F | · | ✓ | · | ✓ |
| `.bash_profile` | `.baſh_proﬁle` | U+017F U+FB01 | · | · | · | ✓ |
| `.terminal_aliases` | `.terminal_aliaſes` | U+017F | · | ✓ | · | ✓ |
| `.terminal_aliases` | `.terminal_aliaseſ` | U+017F | · | ✓ | · | ✓ |
| `.terminal_aliases` | `.terminal_aliaſeſ` | U+017F U+017F | · | ✓ | · | ✓ |
| `.zprofile` | `.zproﬁle` | U+FB01 | · | · | · | ✓ |
| `.zshenv` | `.zſhenv` | U+017F | · | ✓ | · | ✓ |
| `.zshrc` | `.zſhrc` | U+017F | · | ✓ | · | ✓ |
| `credentials.json` | `credentialſ.json` | U+017F | · | ✓ | · | ✓ |
| `credentials.json` | `credentials.jſon` | U+017F | · | ✓ | · | ✓ |
| `credentials.json` | `credentialſ.jſon` | U+017F U+017F | · | ✓ | · | ✓ |

The three `re.IGNORECASE` misses are exactly the three rows containing U+FB01 — the `ﬁ`
ligature is a *decomposition*, not a case fold, so no regex flag reaches it.

**Decision: bare `re.IGNORECASE`.** User call, 2026-09-03, taken on a smaller table (7
spellings, 8 false refusals) and **retained on the corrected one**: it closes **9 of the 12**
live bypasses on top of the capitalisation fix, at a cost of **10** false refusals, each of
which is U+0130 or U+0131 (Turkish dotted / dotless i) inside one of four filenames. A false
refusal here is a printed message with a documented override, not a leak. The correction
moved every number in the same direction, so the decision does not turn on it.

Rejected: `re.IGNORECASE | re.ASCII` — closes **zero** of the 12, measured. Its only merit is
avoiding the 10 false refusals, which is not worth leaving twelve written-down bypasses open
in a Tier-1 guard.

Rejected: NFKD normalisation — the only strategy that closes all 12, at a cost of hundreds of
false refusals (see the ⚠️ above on why no exact figure is published). In a guard whose every
false refusal costs a human typing `secret-gate override`, that is unshippable at any of the
measured magnitudes.

**Residual, carried forward deliberately:** the three U+FB01 `ﬁ`-ligature spellings remain
live bypasses. They are pre-existing, they are now written down, and closing them needs
normalisation, which the table above rules out at this price. They become a Known-gaps row
(task 6) and a follow-up card (task 8), not a silent omission.

**Observability, stated rather than implied:** at runtime, *nothing* reports that the fold is
still working. This guard is silent when it works and silent when it is broken, and it fails
open. The only signal is the test suite, and only when someone runs it. That is the honest
answer to "how would we know", and it is why task 3 ships a probe before task 5 changes any
code.

## Scenarios

```gherkin
Feature: secret-command-guard recognises secret file names regardless of capitalisation

  Background:
    Given the repository is on a case-insensitive volume
    And the guard is invoked with a PreToolUse payload, never a real shell

  Scenario: the lowercase control still refuses
    Given the command "cat .env"
    When the guard classifies it
    Then it is BLOCKED
    # Every scenario below is paired with this control. A group whose control
    # does not refuse is measuring nothing.

  Scenario Outline: a capitalised spelling of a secret file is refused
    Given the command "cat <path>"
    When the guard classifies it
    Then it is BLOCKED
    And the reported label is <label>

    Examples:
      | path              | label               |
      | .ENV              | ".env / .env.*"     |
      | .Env              | ".env / .env.*"     |
      | ~/.ZSHRC          | "~/.zshrc"          |
      | CREDENTIALS.json  | "credentials.json"  |

  Scenario Outline: the widest pattern folds too
    Given the command "cat ~/Library/<dir>/app/<file>"
    When the guard classifies it
    Then it is BLOCKED

    Examples:
      | dir                 | file        |
      | Application Support | CREDENTIALS |
      | APPLICATION SUPPORT | credentials |
      | application support | credentials |

  Scenario: the committed-template exemption survives folding
    Given the command "git add .env.example"
    When the guard classifies it
    Then it is ALLOWED
    # Regression guard for task 5: folding the patterns without folding the
    # exemption check turns this class of path into a false refusal.

  Scenario Outline: a capitalised template is exempt after the fold
    Given the command "git add <path>"
    When the guard classifies it
    Then it is ALLOWED

    Examples:
      | path            |
      | .ENV.EXAMPLE    |
      | .env.Template   |
      | .Env.SAMPLE     |

  Scenario Outline: a homoglyph that opens the SAME file is refused
    Given a decoy file proves "<path>" and "<real>" are the same file on this volume
    And the command "cat <path>"
    When the guard classifies it
    Then it is BLOCKED

    Examples:
      | path                | real               |
      | .zſhrc              | .zshrc             |
      | .zſhenv             | .zshenv            |
      | .baſh_profile       | .bash_profile      |
      | .terminal_aliaſes   | .terminal_aliases  |
      | .terminal_aliaseſ   | .terminal_aliases  |
      | .terminal_aliaſeſ   | .terminal_aliases  |
      | credentialſ.json    | credentials.json   |
      | credentials.jſon    | credentials.json   |
      | credentialſ.jſon    | credentials.json   |

    # U+017F LONG S. These nine are the bypasses bare re.IGNORECASE closes, and
    # they are the assertions that go red if a future refactor adds re.ASCII.
    # Three of them substitute TWO positions -- the shape no round of this card
    # tested until the observability judge asked for it.
    #
    # The Given is NOT a comment. It must execute: write a decoy under <real> in
    # a scratch dir, open it as <path>, assert the decoy content comes back. A
    # scenario that assumes the volume's behaviour instead of asking it is the
    # exact error round 2 of this card shipped.

  Scenario Outline: a known-gap homoglyph stays allowed, and is pinned as a gap
    Given a decoy file proves "<path>" and "<real>" are the same file on this volume
    And the command "cat <path>"
    When the guard classifies it
    Then it is ALLOWED

    Examples:
      | path           | real           |
      | .bash_proﬁle   | .bash_profile  |
      | .baſh_proﬁle   | .bash_profile  |
      | .zproﬁle       | .zprofile      |

    # U+FB01 LIGATURE FI -- a decomposition, not a case fold, so no regex flag
    # reaches it. These are LIVE BYPASSES pinned as ALLOW so the gap is visible
    # rather than forgotten, the same contract as every other Known-gaps row.
    #
    # This is only honest while the Given actually runs. A pinned-ALLOW row whose
    # ground-truth check is a comment asserts nothing and lets a green suite
    # coexist with a hole nobody re-verifies. Closing these needs NFKD, which the
    # Flag choice table rules out.

  Scenario Outline: an accepted false refusal, recorded so it is not a surprise
    Given a decoy file proves "<path>" is a DIFFERENT file from "<real>"
    And the command "cat <path>"
    When the guard classifies it
    Then it is BLOCKED

    Examples:
      | path                   | real               |
      | credentıals.json       | credentials.json   |
      | credentİals.json       | credentials.json   |
      | .termınal_aliases      | .terminal_aliases  |
      | .termİnal_aliases      | .terminal_aliases  |
      | .terminal_alıases      | .terminal_aliases  |
      | .terminal_alİases      | .terminal_aliases  |
      | .bash_profıle          | .bash_profile      |
      | .bash_profİle          | .bash_profile      |
      | .zprofıle              | .zprofile          |
      | .zprofİle              | .zprofile          |

    # U+0131 / U+0130 Turkish dotless and dotted i. These ten are the entire
    # priced cost of bare re.IGNORECASE -- the complete list, not a sample.
    # Asserted so that if the count ever moves, a test says so rather than a
    # number in prose going quietly stale.

  Scenario: an unrelated path is unaffected
    Given the command "cat foo.zshrc"
    When the guard classifies it
    Then it is ALLOWED
    # Pre-existing known gap, pinned so the fold does not silently close or widen it.
```

## The work

- [x] 1. Per-pattern fold impact, derived by command. **Done, then corrected in round 1** —
      see Task 1 and the ⚠️ on table A.
- [x] 2. Decide the filesystem question. **Done** — fold unconditionally; decision retained
      on corrected evidence.
- [ ] 3. **Ship the probe first**, as `hooks/secret-filename-fold.probe.sh` (+ its python
      helper). It must source **every** number this card states, or the number is deleted:
      - table A (which patterns flip), with **a per-pattern case count** printed — the
        round-1 error was a row with zero test cases printing identically to a row that
        passed;
      - the two disk-census counts (29,773 / 760,056);
      - the full flag-choice table: all four strategies side by side, both columns
        (bypasses and false refusals), over the **union** candidate population. After the
        single-compile-site rule lands, nothing else can reproduce this comparison.

      It must use the **two-oracle** structure: filesystem ground truth via decoy files in
      a scratch directory, guard verdict via the imported patterns. It must never create,
      read, or name a real secret-bearing file. Ordered ahead of the code change on both
      judges' advice — a probe that ships after the fix can never reproduce the "before"
      numbers that justified the decision.

      Its candidate population must sweep **every letter position** and **every
      non-overlapping combination** of confirmed same-file substitutions. Three separate
      rounds of this card each shipped a confident table built on a population with a hole
      (see Flag choice); the per-name coverage print exists so the fourth hole is visible.

      ⚠️ **No contradiction with task 5's single-compile-site rule.** That rule governs the
      *production* path: `matches_dotfile` reads exactly one compiled list. The probe
      imports `DOTFILE_PATTERNS` — the raw source list — and compiles its own alternates,
      because comparing four strategies is the one job that genuinely needs four
      compilations. It must additionally import `DOTFILE_RE` and assert the production list
      agrees with its own `re.IGNORECASE` column, so the two cannot silently drift.
- [ ] 4. **Red tests**, in `hooks/secret-command-guard.test.sh`, in their own commit before
      any implementation edit — every scenario above, controls included.
- [ ] 5. Fold **both** case-sensitive comparisons, not just the obvious one:
      Write it exactly as below — the two halves must share **one** flags constant, so they
      cannot disagree about what "the same letter" means:

      ```python
      FOLD_FLAGS = re.IGNORECASE          # single source; see Flag choice

      DOTFILE_RE = [(re.compile(p, FOLD_FLAGS), label) for p, label in DOTFILE_PATTERNS]
      ENV_EXEMPT_RE = re.compile(r"\.(example|template|sample)$", FOLD_FLAGS)
      ```

      and in `matches_dotfile`, replace

      ```python
      if label == ENV_LABEL and tok.endswith(ENV_EXEMPT_SUFFIXES):
      ```
      with
      ```python
      if label == ENV_LABEL and ENV_EXEMPT_RE.search(tok):
      ```

      - `DOTFILE_RE` (`classify-secret-command.py:147`) — the gap itself. This is the
        **single** compile site; the probe and the tests import `DOTFILE_RE`, they never
        recompile `DOTFILE_PATTERNS`, because a second compile site is where a future
        refactor drops a flag.
      - `ENV_EXEMPT_RE` replaces `tok.endswith(ENV_EXEMPT_SUFFIXES)` (`:159`). **A regex,
        not `tok.lower().endswith(...)`** — `str.lower()` is Unicode-aware with its own
        table, so a `lower()`-based exemption and an `re.IGNORECASE` pattern can disagree,
        which is precisely the class of bug this card exists to fix. `ENV_EXEMPT_SUFFIXES`
        becomes dead and is removed.

      Verified before prescribing: this exact form scores **20/20** on a case list covering
      every capitalisation row, both committed-template forms, the long-s bypasses, the
      ligature gap, `.envexample` (allow) and `.env.examples` (block).
      `program(argv[0])` (`:189`) already folds via ADR 0041 and needs no change.

      ⚠️ **Corrected premise, round 1.** The first draft justified this by saying folding
      the patterns alone would newly block `.env.EXAMPLE`. That is false and was measured:
      `matches_dotfile(".env.EXAMPLE")` already returns the block label **today**, at HEAD
      `7e3f802`, before any change — the exemption is a case-sensitive `endswith`, so an
      uppercase suffix already misses it. The pre-existing false positive is
      `.env.EXAMPLE`; the one this card would *newly* introduce by folding only half is
      `.ENV.EXAMPLE` (`matches_dotfile` returns `None` for it today). **The prescription is
      unchanged — both halves still move together — only the reason was wrong.** Folding
      both also fixes the pre-existing `.env.EXAMPLE` refusal as a side effect, which is in
      scope precisely because it is the same root cause.
- [ ] 6. Update the Known-gaps table in `docs/features/secret-command-guard.md`. Counted
      from the artifact at HEAD `7e3f802` by parsing the table and discarding the separator
      row: **10 data rows** (lines 99–108), independently re-derived by the compliance judge
      at round 1. That agrees with the "ten rows as of 2026-08-31" figure in `rules/gates.md`,
      so that figure needs no repair. Whether this shape earns a *new* row is a judgement for
      whoever does the task: once folded it is no longer a gap, so the honest edit may be no
      new row, or one row recording the *residual* (a case-sensitive volume over-refuses).
      Decide from the fixed code, and re-count from the artifact at that point rather than
      trusting the 10 above.

      One row is **required** regardless: the three U+FB01 `ﬁ`-ligature spellings
      (`.bash_proﬁle`, `.baſh_proﬁle`, `.zproﬁle`) that open the real file and are still
      allowed after this card. They are pre-existing, they are now measured, and a measured
      bypass that is not in the table is worse than one nobody found.
- [ ] 7. ADR recording: the fold decision, the rejected filesystem-probe alternative, the
      flag choice with its measured bypass/false-refusal table, the two rejected flag
      alternatives, and the deliberate widening of the `Application Support` pattern.
- [ ] 8. Queue a follow-up card for the `ﬁ`-ligature bypasses — Unicode normalisation of the
      token before matching. Plain NFKD costs hundreds of false refusals (Flag choice; the
      exact figure is deliberately unpublished because two sweeps disagreed), so this needs
      a narrower approach than "normalise everything" — most likely folding only the
      specific ligature codepoints that appear in these seven names. Placeholder only; not
      designed here, and the first task on that card is to re-derive the cost.

## Out of scope

- The `argv[0]` program-name fold. Done: ADR 0041.
- `ENV_DUMP_RE` (`classify-secret-command.py:131`), the `os.environ`/`process.env` check.
  Deliberately **not** folded: neither expression is valid in its language when capitalised,
  so folding buys no real coverage while widening a check that already substring-matches raw
  command text and already false-positives on prose.
- `secret-command-guard.sh`'s fail-open on classifier error. Depended on, not changed.
- The other known gaps listed in `docs/features/secret-command-guard.md` (count them
  there; see task 6).
