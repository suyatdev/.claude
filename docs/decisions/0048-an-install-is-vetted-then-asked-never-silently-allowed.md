# 0048 — An install is vetted, then asked about, and never silently allowed

- **Status:** Accepted (2026-10-15).
- **Context:** `hooks/dependency-guard.sh` (new), `hooks/lib/decide-dependency.py`,
  `hooks/lib/classify-install-command.py`, `hooks/lib/classify-manifest-edit.py`,
  `hooks/lib/vetting_record.py`, `hooks/lib/vet_checks.py` and `hooks/bin/vet-dependency`
  (all new), registered in `settings.json` under `PreToolUse` on `Bash` and on
  `Edit|Write|NotebookEdit`; `skills/vetting-dependencies/SKILL.md`; a stub in `rules/gates.md`.
  Full design, scenarios, Known gaps and the task record:
  `docs/features/dependency-vetting-guard.md`. Another consumer of the shared shell-segment lexer
  (**ADR 0013**, amended by **ADR 0015** and **ADR 0040**). It is a speed bump in the same family
  as **ADR 0039**'s secret-command guard, and it shares that ADR's honesty about what such a guard
  does not stop.
- **Note on anchors:** this ADR cites file, constant, function and heading names, never line
  numbers. The card's own spec cites some, and several went stale during the work. The
  `MSG_…` names (`MSG_UNPINNED`, `MSG_VET_FIRST`, `MSG_RUNNER_INSTALLER`) are the card's names
  for the deny messages, not code constants: `hooks/lib/decide-dependency.py` builds each one in
  the matching `msg_…` function (`msg_unpinned`, `msg_vet_first`, `msg_runner_installer`).
- **Note on the number:** `0048` was checked against every local and remote ref with
  `git log --all -- docs/decisions/0048*` (and `0049*`) on 2026-10-15 and no ref carries either.

## Context

Mark asked (2026-10-09) that anything installed or added as a dependency be vetted and scanned
first. The card's "Why" section records what existed at the time: no hook matched a package-manager
command, the only always-on text was two lines in `rules/core-conduct.md` (vetted registries and
pinned versions; never add or upgrade a dependency unilaterally), and no skill held a vetting
procedure. Of the scanners the card tried (`osv-scanner`, `pip-audit`, `snyk`, `cargo-audit`,
`socket`), none was on `PATH`; only `npm` was.

Prose had not enforced this, so the guard sits at `PreToolUse`, judging command text before it
runs, as ADR 0039 did for secrets.

## What the guard does

For every install the hook can see, it decides in order:

0. A runner that fetches a package manager: deny (`MSG_RUNNER_INSTALLER`, below).
1. Not an exact version: deny (`MSG_UNPINNED`).
2. No vetting record from the last 7 days: deny (`MSG_VET_FIRST`), printing the vetter command to run.
3. Otherwise: ask, with a one-line summary of the record.

A non-registry source (`file:`, a git URL, a local path) and `pip -r <file>` are asked about
instead of denied, because there is no registry version to pin or vet, and a deny would have no way
through. Every package in a command is decided on its own; the strongest decision wins.

## Decision 1 — the choices Mark made (D1–D8)

The card's Decisions table is the source for D1–D7; D8 has its own section in the card. "Rejected"
is what the table lists. Where the card gives no reason for a choice, none is invented here.

| # | Chosen | Rejected | Why, where the card says |
|---|---|---|---|
| D1 | Ask every time, after a scan whose results and a recommendation are shown first | block-unless-vetted; log only | The card does not state a reason for D1 itself. It does say Mark's approval is the control the hook makes unavoidable. |
| D2 | Add `osv-scanner`, pinned, vetted through this same flow | built-in scanners only; checklist only | No reason stated beyond the choice. It is installed from the GitHub release asset after its SHA-256 matches, not Homebrew, because Homebrew installs whatever is current stable and so cannot hold 2.6.0. |
| D3 | Pillars 2–4 of the request (malicious logic, error leakage, least privilege, risk disclosure) become a separate small change | same card | No reason stated; this ADR covers only pillar 1 and the scanner-list half of pillar 4. |
| D4 | Vet, then install: the hook stops the first attempt, Claude runs the vetter, shows the report and a recommendation in chat, retries, and the retry reaches the permission prompt | the hook scans inline; instructions only | No reason stated. |
| D5 | A report is good for 7 days, in any project, keyed on ecosystem, name and exact version | fresh every time; forever | No reason stated. |
| D6 | Exact versions only; a range is refused | ranges with a lockfile | No reason stated. Mark chose it over ranges on 2026-10-09, knowingly narrowing pillar 1's "(or version ranges)". |
| D7 | The hook's own failure falls back to `ask` with a "guard is broken" warning | fail open; fail closed | The card's reasoning: "Broken → ask" costs one prompt per Bash call while broken, and that noise is the signal, preferred over a silent allow. |
| D8 | Homebrew skips the pin check; the vetter keys the record on the `stable` version `brew info` reports | deny every `brew install` | `brew install` cannot generally select an old formula version, and denying all of them would leave no way through. Proposed by Claude and approved by Mark 2026-10-13. |

Two details of D6 and D7 are easy to misread, so they are stated here.

**D6 has one definition.** `is_exact_version` in `hooks/lib/vetting_record.py` is the only thing
that decides whether a version is pinned. It matches a whole-value positive pattern per ecosystem
with `re.fullmatch(..., re.ASCII)`; the tool-specific spelling only locates the value. The
patterns and their examples are in the card, not repeated here.

**D7 governs the hook's own failure, not a vetting result.** A vetter that cannot reach OSV, or a
registry that returns 404 for the name, writes no record and exits non-zero, so the install stays
denied. That is "not vetted", not a broken guard.

## Decision 2 — D9 was adopted, narrowed, and dropped

**What it was.** D9 (2026-10-12) would have allowed a bare `npx <tool>` when the tool was already
installed locally, since npx runs `node_modules/.bin/<tool>` without contacting the registry (the
card's Measured inputs: npm 12.0.1, local fake `.bin` script, registry unreachable). Mark decided
it. Its rejected alternatives were "ask every time" and "keep refusing".

**How it was narrowed.** The review rounds it lived through (3 to 7) kept finding shapes it
wrongly allowed. Round 3 found it wrongly covered `pnpx`, which always downloads. After round 4 Mark
reduced it to an allowlist of the single plainest shape. After round 6 Mark added a stop rule, and
D9 shipped switched off pending a working-directory measurement.

**The stop rule.** If round 7 found another D9 hole, D9 would be dropped without asking again.

**What round 7 found.** Both judges found holes: `npx NPM` (letter case on a case-insensitive
filesystem), installer aliases (`yarnpkg`, `pn`, `pnx`), a local `node` running another npx, and a
`.npmrc` `package=` setting. The stop rule fired and D9 was dropped, together with the reclassification
of `npx <installer>` that had come with it.

**Why dropping was right, as far as the card supports.** Across rounds 3 to 7 each version of the
shortcut was defeated by a shape it did not list (the card's "D9 — dropped" paragraph enumerates them:
`pnpx`, `npx -p`, `npx --prefix`, grouped or repeated `cd`, `eval` and `"$(…)"`, a project-local
installer, letter case, installer aliases, a local `node`, a `.npmrc`). Each narrowing exposed another
hole instead of converging, and the stop rule was written to end that loop. The card does not claim
the shortcut was provably unfixable, only that it did not converge in the rounds spent and Mark set
the cutoff in advance.

**What replaced it.** Every member of `RUNNERS` (a constant in `classify-install-command.py`) is
always an install intent for the package it names, with no exception for a local copy. A versionless
`npx tsc` is denied by step 1, and `MSG_UNPINNED` adds one sentence in a narrow case, pointing at
`node_modules/.bin/<tool>`. `local_copy_advice` in `decide-dependency.py` decides when that sentence
appears: only for an npm-registry runner, only for the first non-option package (not one taken from
`-p`/`--package`), not for a scoped name, and not for a package manager. Calling the project's own
copy directly is not an install, unless the tool is itself a package manager: `program()` takes the
lowercased basename, so `node_modules/.bin/npm install x` is still `npm install x`.

## Decision 3 — a runner that names a package manager is refused (`MSG_RUNNER_INSTALLER`)

When the package a runner names is itself a package manager (its lowercased name is in
`INSTALL_TOOL_WORDS`), the intent is denied, pinned or not, and `VET_EXEMPT` does not change that.
In `decide-dependency.py` it is the first check in `decide_intent`, and `msg_runner_installer`
builds the text: `<runner> would fetch the package manager <name> — run <name> directly so the guard
can check what it installs.`

Why: `npx npm@12.0.1 install left-pad` would otherwise vet only npm, while left-pad is installed
unchecked (round-8 compliance judge, per the card). There is no reason to fetch a package manager
through a runner to install something, and calling the manager directly lets the guard see the real
install. Claude proposed it after round 8 and Mark approved it on 2026-10-13. The message gives no
example command because the guard never reads what the package manager was asked to install.

It checks only the package's name. A package manager the guard does not know (the card's example is
`cnpm`) is vetted as a package while what it installs is not. That is in Known gaps.

## Decision 4 — the cannot-read rule

`segments()` in `hooks/lib/shell_segments.py` returns `[]` for a command it cannot lex. When it does
so for non-blank text, the rule is:

- If the raw text contains an `INSTALL_TOOL_WORDS` member as a whole word, matched
  case-insensitively, the hook asks: "dependency-guard cannot read this command; it may install a
  package — check it before approving". Case-insensitive because macOS file names ignore case, so
  `NPM` runs npm (round 7).
- If it contains no such word, the hook allows with no output, but appends one `allow-unreadable`
  line to `hooks/state/dependency-guard.log`, so a later miss is findable.

The word list is one constant, `INSTALL_TOOL_WORDS`, shared by the classifier and the decider so the
two cannot drift, and a unit test asserts that every program in the install-forms table is in it.

Why ask rather than deny: this matches D7, and `classify-git-command.py` refuses instead, which the
card notes as the difference. Why allow without a tool word: the card's reason is that a prose
heredoc that happens not to lex, such as a commit message with an apostrophe, is not an install, and
asking on every one would bury the real prompts. Mark approved the rule on 2026-10-13; it was added
after the round-1 judges found the gap.

## Decision 5 — a speed bump, not a security boundary

The vetting record is written by the agent, so it is forgeable from inside the session. The
load-bearing control is Mark's approval at the permission prompt, which the hook makes unavoidable
for every install it can see. The hook reads command text and manifest edits, so the card's Known gaps
include an install inside a script, a Makefile, `bash -c`, variable indirection, or a manifest edited
through Bash, and npm configuration that changes what a runner fetches without changing the command.

`VET_EXEMPT=<reason>` is the bypass for a missing record (step 2), logged, and it is the human's
bypass, never one the agent issues on its own authority, as the gate stub in `rules/gates.md` says.
It is read only from the owning segment's own assignments and only when the value matches a plain-word
allowlist (`EXEMPT_VALUE_RE` in `classify-install-command.py`). It does not rescue step 0 or step 1,
and an exempt install still reaches the prompt with `VET_EXEMPT: <reason>` in the ask text.

The full list of shapes the guard does not see is the card's **Known gaps** section. This ADR does
not restate it, and states no count of its rows; read them there.

## Consequences

- Installing a package through a visible command now takes three steps: pin an exact version, run
  `vet-dependency` and show the report and a recommendation, then approve at the prompt. A bare
  `npx tsc` is refused even when the project has `tsc`; run `node_modules/.bin/tsc` instead.
- A broken guard asks on every `Bash` call until fixed (D7). That is intended.
- Every Homebrew record is `complete: false`, because OSV has no Homebrew ecosystem (D8).
- `transitive_vulns` is `not_run` outside npm in v1 (the card's Q1 and Q2 measured negative or could
  not be measured), so those records are `complete: false`. A clean but incomplete record is shown
  as incomplete at the prompt.
- Nothing is live until the branch merges, because hooks load from the primary checkout. The card's
  Task 11 verifies liveness after merge, and this ADR claims none.
- Pillars 2–4 of Mark's request are not delivered by this change (D3).

## Alternatives considered

D1–D8's rejected options are in the table above. For D9, "keep refusing" is what shipped after the
stop rule fired. The card records no other alternatives for the hook design.
