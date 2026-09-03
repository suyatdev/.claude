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
| `re` | stdlib of the above; flags **`re.IGNORECASE \| re.ASCII`** | `classify-secret-command.py` |

⚠️ **The flag is `re.IGNORECASE | re.ASCII`, not `re.IGNORECASE` alone, and this is a
measured requirement rather than a style preference.** `re.IGNORECASE` on `str` patterns is
Unicode-aware by default in Python 3, so bare folding matches far more than capitalisation.
Measured on python3 3.9.6 at HEAD `7e3f802`, three genuinely different filenames become
newly BLOCKED under bare `re.IGNORECASE`:

| Token | Why it matches | bare `IGNORECASE` | `IGNORECASE \| ASCII` |
|---|---|---|---|
| `.zſhrc` | U+017F LATIN SMALL LETTER LONG S folds to `s` | blocked (wrong) | allowed |
| `credentıals.json` | U+0131 dotless i folds to `i` | blocked (wrong) | allowed |
| `credentİals.json` | U+0130 dotted capital I folds to `i` | blocked (wrong) | allowed |

Adding `re.ASCII` removes all three while keeping every intended block — `.ENV`, `.Env`,
`~/.ZSHRC`, `CREDENTIALS.json`, `.zShrc` and `APPLICATION SUPPORT/…/credentials` all still
refuse. A 10-case probe over both flag sets returns *all as desired* only for
`IGNORECASE | ASCII`.

This is exactly the surprise the predecessor card (`argv0-spelling-blindness`) found by
pinning the same interpreter, and it was found here only because round 1 of the compliance
judge required the pin. Without it this card would have shipped a homoglyph over-block.

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
    # Regression guard for task 4: folding the patterns without folding the
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

  Scenario Outline: a Unicode homoglyph is NOT swept up by the fold
    Given the command "cat <path>"
    When the guard classifies it
    Then it is ALLOWED

    Examples:
      | path              | homoglyph                          |
      | .zſhrc            | U+017F long s folds to s           |
      | credentıals.json  | U+0131 dotless i folds to i        |
      | credentİals.json  | U+0130 dotted capital I folds to i |

    # These are the assertions that force re.ASCII. Measured: all three are
    # BLOCKED under bare re.IGNORECASE and ALLOWED under IGNORECASE|ASCII.
    # If a future refactor drops re.ASCII, these three go red and nothing else does.

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
- [ ] 3. **Ship the probe first.** A committed script that emits table A and both counts in
      Task 1, so every number above is re-derivable instead of retyped prose. It must print
      **a per-pattern case count**, not just a verdict — the round-1 error was a row with
      zero test cases printing identically to a row that passed. Moved ahead of the code
      change on both judges' advice: a probe that ships after the fix can never reproduce
      the "before" numbers that justified the decision.
- [ ] 4. **Red tests**, in `hooks/secret-command-guard.test.sh`, in their own commit before
      any implementation edit — every scenario above, controls included.
- [ ] 5. Fold **both** case-sensitive comparisons, not just the obvious one:
      - `DOTFILE_RE` (`classify-secret-command.py:147`) — the gap itself. Compile with
        **`re.IGNORECASE | re.ASCII`** (see Pinned versions; `re.ASCII` is load-bearing, not
        decorative). Keep this the **single** compile site — do not let the probe or the
        tests compile the patterns a second time, or that second site is where a future
        refactor drops a flag. Export the compiled list and import it everywhere else.
      - `tok.endswith(ENV_EXEMPT_SUFFIXES)` (`:159`) — the committed-template exemption.
        Fold it with the same ASCII discipline as the patterns (`str.lower()` is
        Unicode-aware; if the two halves disagree about what "same letter" means, a token
        can match the pattern and miss the exemption, which is the exact shape of the bug
        being fixed).
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
- [ ] 7. ADR recording the decision, the rejected filesystem-probe alternative, and the
      deliberate widening of the `Application Support` pattern.

## Out of scope

- The `argv[0]` program-name fold. Done: ADR 0041.
- `ENV_DUMP_RE` (`classify-secret-command.py:131`), the `os.environ`/`process.env` check.
  Deliberately **not** folded: neither expression is valid in its language when capitalised,
  so folding buys no real coverage while widening a check that already substring-matches raw
  command text and already false-positives on prose.
- `secret-command-guard.sh`'s fail-open on classifier error. Depended on, not changed.
- The other known gaps listed in `docs/features/secret-command-guard.md` (count them
  there; see task 4).
