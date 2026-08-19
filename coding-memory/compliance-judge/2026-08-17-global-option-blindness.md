# Compliance verdict — A global option in front of the subcommand hides the command from every guard

Spec: `docs/features/global-option-blindness.md`
Slug: `global-option-blindness`

## Round 1 — 2026-08-17

**Verdict: FAIL** (confidence: high)

### Layman summary

Four safety hooks in this repo decide what a `git`/`gh` command really does by
looking at its first two words. Both tools let you put extra options *before*
the real subcommand (`git -C . push --force`), and when that happens the hooks
go blind and let the command through — including a bare force-push to `main`
and a server-side PR merge. This spec fixes that by teaching the git-command
reader to walk past global options one at a time, sorting each into "safe to
skip," "might redirect to a different repo — ask the user," or "never seen
this one — ask the user," and by generalizing the `gh` reader (which already
handled this correctly for `pr create`) to also cover `pr merge`.

I re-ran essentially every falsifiable claim in this spec against the live
repo and the installed tools rather than taking them on faith: all six rows
of the "measured defect" table reproduced exactly against the real hooks
(plain form blocks, global-option form silently allows); every pinned version
(git 2.50.1, Python 3.9.6, bash 3.2.57, shellcheck 0.11.0, awk 20200816,
Claude Code 2.1.233) matched the installed tool; every `file:line` citation
into `classify-git-command.py`, `merge-guard.sh`, and `classify-pr-command.py`
pointed at the text quoted; the `--exec-path` bare-vs-`=` behavior and the
four value-consuming options' space/`=` forms all reproduced as claimed; and
both quoted strings said to come from "the installed binary's own validation
error" (`Valid types are: allow, deny, ask, defer` and the
`permissionMode 'bypassPermissions'` sentence) are verbatim present in the
Claude Code 2.1.233 binary on this machine. This is an unusually
well-derived spec — almost nothing in it is asserted without a shown
derivation.

Two things don't hold up, though, and both are the kind of gap that costs a
lot more once code has been built on top of them:

1. The contract table says `merge-guard.sh` will **ask** the user on a
   cannot-tell case, the same way `git-guard.sh` does. But the "cannot-tell"
   fact (`SCOPE_UNKNOWN`) is defined, in this same spec, as belonging only to
   the *git* reader. `merge-guard.sh`'s actual fix (Tasks 5–6) uses a
   completely different mechanism — the `gh` reader's adjacent-pair scan,
   which has no "I don't know" state and gets no new ask-emitting code in any
   task. Nothing in the spec says what would make `merge-guard.sh` ask, or
   what it should say. An implementer literally cannot build the row the
   table promises.
2. An "Out of scope" bullet says `--untracked-files`/`-S` on `git commit` is
   "already safe in practice... Measured, not assumed" because neither is in
   the two flag tables. I ran it: `-S` **is** in the safe-flags table — it's
   `--gpg-sign`'s short form, unrelated to `--untracked-files` (whose real
   short form is `-u`). Measuring the flag actually named produces the
   opposite of the claimed result. The underlying scoping decision still
   turns out fine once you test the right flag (`-u` does block, as
   intended) — but the sentence that says "Measured" wasn't run against what
   it names, which is exactly the failure mode the house verification rule
   exists to catch.

Full details, file:line citations, and what a fix needs to change are in the
violations table below.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/ambiguous-merge-guard-ask` | `skills/writing-specs/SKILL.md` | "What a Spec Must Contain" — API contracts wherever the design has interfaces, and no requirement left readable two ways | "Contract — how a refusal reaches the user" (the "which guards ask" table, row `merge-guard.sh \| ask \| same, for gh pr merge`), cross-referenced by "Existing hard blocks are unchanged" ("Only the new cannot-tell case becomes an ask") | `SCOPE_UNKNOWN` is defined exclusively as a fact emitted by `classify-git-command.py` (§ "Contract — the new fact"). `merge-guard.sh`'s actual fix (Tasks 5–6, "Where the code lives") instead generalizes `classify-pr-command.py`'s adjacent-pair scan for `gh`, a mechanism that has no "cannot tell" state (it returns `MERGE` or `NO`, never "unknown") and gains no ask-JSON emission path in any task. The table nonetheless promises `merge-guard.sh` will "ask" — a trigger condition and JSON-emission step that exist nowhere else in the spec. The Gherkin scenario for merge-guard hedges around this ("does not exit 0 silently," never "asks") rather than asserting a mechanism, which is the tell that this requirement was never actually decided. A fix must either (a) remove `merge-guard.sh` from the ask table and state plainly that `gh pr merge` behind global options is closed by direct detection, keeping its existing hard `exit 2` — consistent with "Existing hard blocks are unchanged" — or (b) if an ask path really is wanted for `gh`, add the missing pieces: what condition triggers it, which task builds the JSON emission, and a scenario that asserts `permissionDecision: "ask"` for it specifically. |
| `core-conduct/unverified-untracked-files-claim` | `rules/core-conduct.md` | "Verification precedes both the claim and the write-down... never state that something works... until you have actually run it and re-read the output." | "Out of scope" — bullet `` `--untracked-files`/`-S` on `git commit` `` | The bullet claims `-S` is "neither in `COMMIT_VALUE_FLAGS` nor `COMMIT_SAFE_FLAGS`," labeled "Measured, not assumed." It is measurably wrong: `-S` is in `COMMIT_SAFE_FLAGS` at `classify-git-command.py:104` as `--gpg-sign`'s short form (confirmed by `git commit -h` and `man git-commit`), and it has nothing to do with `--untracked-files`, whose real short form is `-u`. Run against the classifier: `git commit -m x -S -- app.js` → `COMMIT`, `COMMIT_PATH`, `COMMIT_PATHSPEC` (scoped/safe) — not `COMMIT_BARE_ARGS` (blocked) as the bullet asserts. Running the *actual* short form instead (`git commit -m x -u -- app.js`) does yield `COMMIT_BARE_ARGS`, so the scoping conclusion ("no behaviour change required") happens to be correct — but the specific evidence offered for it was not run against the symbol it names. Fix: replace `-S` with `-u` in the bullet, or re-derive and re-state the check against the flag actually meant. |

### Notes (non-blocking)

- **Option-table completeness, safely absorbed.** The Bucket-1 "no value" list is sourced from `git --help`'s abbreviated usage synopsis, not the full `man git` OPTIONS section, which documents six more global options: `--literal-pathspecs`, `--glob-pathspecs`, `--noglob-pathspecs`, `--icase-pathspecs`, `--list-cmds=<group>`, `--attr-source=<tree-ish>`. I confirmed none of them redirect the target repo, and confirmed `--list-cmds`/`--attr-source` are attach-only (space form errors: `unknown option: --list-cmds`), matching the `--exec-path` pattern the spec already handles correctly. Because Bucket 3's catch-all ("unrecognised → ask, never allow") is unconditional, none of this missing coverage produces a silent allow — worst case is one unnecessary prompt on a rare command. But "Enumerated from git's own usage line (`git --help`), not from memory" overclaims completeness relative to the more authoritative `man git`; worth citing the fuller source or acknowledging the synopsis is partial.
- **Scenario 6 ("force-push protection survives a global option") under-specifies.** It asserts only "it either refuses or asks, never exits 0 with no output," weaker than the contract table's unconditional "ask" for git-guard.sh on `SCOPE_UNKNOWN`. A wrong implementation that hard-denies this case instead of asking would still pass. Likely low practical risk, since a natural implementation shares one `SCOPE_UNKNOWN` handler with the tightly-specified commit-side Scenario 2 — but tightening this scenario to assert `ask` specifically would remove the gap outright rather than rely on that inference.
- **No scenario exercises `SCOPE_UNKNOWN` on a non-`main` branch.** The contract prose ("its job is safety; it cannot tell which repo or branch is targeted") implies git-guard should ask unconditionally, regardless of the *current* branch. But if an implementer nests the new check inside the existing `has_fact COMMIT && on_main` block instead of placing it ahead of both existing guards, `git -C /other/repo commit -m x` run from a feature branch would be silently allowed again — reopening exactly the hole this spec exists to close, just gated on the wrong branch. A "Given a repository whose current branch is a feature branch" scenario would pin this down and remove the reliance on inference.
- **Task-list granularity is inconsistent but not wrong.** Task 3 folds "Red then green" into one bullet, while the same discipline for the classifier itself is split across Tasks 1 (red) and 2 (green). Not a rule violation — both steps are still named — but worth aligning for consistency.
- **Everything else checked out.** All six rows of the measured-defect table, all pinned tool versions, both binary-derived quoted strings, and every `file:line` citation reproduced exactly as claimed against the live repo and installed tools. The three-bucket design's fail direction is sound everywhere I could construct a probe: unrecognised and value-consuming edge cases (combined short forms like `-cname=value`, `-C.`) are rejected by git itself before they could reach the classifier, and the bucket-3 catch-all covers everything else.

### Waivers

_None recorded (round 1)._

## Round 2 — 2026-08-17

**Verdict: FAIL** (confidence: high)

### Layman summary

Revision 2 fixes both round-1 problems for real, not just in wording. I
independently re-ran every falsifiable claim rather than trusting the
revision note: all six rows of the measured-defect table still reproduce
exactly against the live hooks; the git global-option grammar (which options
take a value, which are attach-only, which print-and-exit) matches actual
`git 2.50.1` behavior in every case I probed, including the six options the
spec found by diffing `man git` against `git --help`'s synopsis; the
corrected `-u`/`-S` table is now right (`-u` really does block,
`-S` really is safe and unrelated); and every `file:line` citation I checked
(`git-guard.sh:142`, `:152`; `merge-guard.sh:82,93`;
`classify-pr-command.py:38-49`; `classify-git-command.py:104`) points at the
text quoted. The merge-guard "ask" ambiguity from round 1 is gone throughout
the document — every remaining mention of "ask" near `merge-guard.sh` now
explicitly negates it, and the new Gherkin scenario pins `exit 2` plus *no*
`permissionDecision` for it.

Revision 2 also added a new, genuinely useful piece in response to the
observability judge: a `PRINTS_AND_EXITS` set of six global options that
don't actually run the subcommand at all (`--version`, `-h`/`--help`,
`--html-path`, `--man-path`, `--info-path`, and bare `--exec-path`), so that
when one of them precedes `commit` on `main`, the refusal message doesn't
falsely claim the commit ran and got blocked for touching main — it explains
that nothing would have been committed in the first place. The idea is
sound and clearly stated in prose ("used only to select the message, never
to change the decision"). But it never made it into the buildable contract:
no task builds it, and the one Scenario Outline that happens to exercise
`--exec-path` (a `PRINTS_AND_EXITS` member) asserts the generic main-branch
message this new rule says must *not* be used for that option. That is a new
instance of the same defect class round 1 already found once in this spec —
a requirement stated in prose that the Scenarios/Tasks contract doesn't
actually carry.

### Round-1 violations — verification of the fix

Both re-checked in substance, not just re-read:

- **`writing-specs/ambiguous-merge-guard-ask` — CLOSED.** Grepped every
  remaining "ask" occurrence in the file (23 hits): every one near
  `merge-guard.sh` now reads "never asks," "no trigger and no emission exist
  for it," or is the earlier accurate mention that only `git-guard.sh` asks.
  The "how a refusal reaches the user" table now lists `merge-guard.sh` as
  "never asks — keeps `exit 2`" with an explanatory block naming this as the
  round-1 correction. The Gherkin scenario "the merge guard sees through
  globals and through chaining" asserts `exit 2` and explicitly "does NOT
  write a permissionDecision to stdout" for all three example commands
  (`gh pr merge 5`, `gh -R o/r pr merge 5`, `echo hi && gh pr merge 5`) — the
  last of which I reproduced live against the current `merge-guard.sh`
  (`rc=0`, i.e. still a real, currently-open bug this task closes). A new
  scenario also pins `MERGE_EXEMPT` surviving the rewrite. No sentence
  anywhere still implies the merge guard asks.
- **`core-conduct/unverified-untracked-files-claim` — CLOSED.** The bullet
  now states plainly that revision 1's number was true but its explanation
  invented, and replaces it with a two-row measured table. I ran both
  commands against the live classifier: `git commit -m x -u -- app.js` →
  `COMMIT`, `COMMIT_BARE_ARGS` (blocked); `git commit -m x -S -- app.js` →
  `COMMIT`, `COMMIT_PATH app.js`, `COMMIT_PATHSPEC` (allowed, scoped) — both
  match the spec's table exactly. `-S` is confirmed present in
  `COMMIT_SAFE_FLAGS` at `classify-git-command.py:104`, `-u` confirmed absent
  from both flag tables. The surviving conclusion ("no behaviour change
  required") is correct and now actually backed by the evidence offered for
  it.

### Non-blocking round-1 findings — verified applied

- Six omitted global options (`--literal-pathspecs`, `--glob-pathspecs`,
  `--noglob-pathspecs`, `--icase-pathspecs`, `--attr-source`, `--list-cmds`)
  are now enumerated in a table with a stated derivation ("Found by diffing
  the manual page's option list against the synopsis"). I re-ran `man git`'s
  OPTIONS section against `git --help`'s synopsis independently: the diff is
  exactly these six, no more, no fewer. The four pathspec-modifying options
  are bucketed 2/ask with a stated reason (`git-guard`'s docs-only exemption
  is decided from pathspec strings, and these options change what those
  strings mean); I confirmed `--attr-source` consumes a space-separated
  token (`git --attr-source HEAD rev-parse ...` → `true`, i.e. it consumed
  `HEAD` and ran `rev-parse`) and `--list-cmds` is attach-only (space form:
  `unknown option: --list-cmds`) — both match the spec's bucket-1
  classification.
- Scenario 6 now asserts `ask` specifically (not the earlier "refuses or
  asks") and that the reason names `-C`.
- A new Scenario Outline pins `SCOPE_UNKNOWN` asking on both `main` and
  `feature/example`, and Task 3 now explicitly forbids nesting the check
  inside the `on_main` block.

All of the above independently re-derived, not re-read from the spec's own
revision note.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/prints-and-exits-no-enforcing-scenario` | `skills/writing-specs/SKILL.md` | "What a Spec Must Contain" — Good, bad, and edge-case scenarios: state explicitly what correct looks like, what wrong looks like, and enumerate the edges; anything left implicit is where defects come from. Also: no requirement left readable two ways. | "Accepted limits" → the `PRINTS_AND_EXITS` paragraph (the "the refusal must not lie about why" MUST, naming `--version`, `-h`/`--help`, `--html-path`, `--man-path`, `--info-path`, and bare `--exec-path`), vs. `## Tasks` (items 1–11) and the Gherkin `Scenario Outline: a harmless global option is skipped and the command is still seen` (whose Examples table includes `--exec-path`) | The Accepted Limits section states a build requirement, not just a caveat: on `main`, a refusal triggered by one of these six options must carry a *different* message ("the command carries a git option that prints and exits, so nothing would have been committed") rather than the standard "blocked for targeting main" text, because for these options the commit never actually ran. Nothing in Tasks 1–11 builds this — Task 2 lists only the three buckets plus `SCOPE_UNKNOWN`, Task 3 covers only the `ask` path and says existing exit-2 paths stay byte-identical, and no other task mentions a `PRINTS_AND_EXITS` set or a second message. Worse, the one Scenario that happens to include a `PRINTS_AND_EXITS` member (`--exec-path`, in the bucket-1 Examples table) asserts the shared `Then` clause "git-guard refuses with exit 2 for committing to main" for every row including that one — the exact generic wording the Accepted Limits paragraph says must not be used for it. I confirmed empirically that bare `--exec-path` does not run the subcommand at all (`git --exec-path commit -m x -a` on a throwaway repo leaves the branch with no commits), so "for committing to main" is the specific claim the new rule exists to prevent. A fix must either add a task building the `PRINTS_AND_EXITS` message swap plus a scenario asserting the differentiated text for at least one of the six options, or split `--exec-path` out of the shared-`Then` Outline into its own scenario with the correct assertion — an implementer following only the Scenarios/Tasks contract currently has no path to the behavior the prose promises, and where the contract does touch this option it points the wrong way. |

### Notes (non-blocking, round 2)

- **"No log file" decision is adequately justified, not a dodge.** Cross-checked all three cited precedents (`merge-guard.sh:93`, `judge-guard.sh:230`, `feature-sync-guard.sh:136`) — all three really are `printf ... >&2` exemption-logging lines, confirming stderr is the established house convention this decision follows rather than invents. The one open question (whether stderr from an exit-0 hook is actually surfaced) is explicitly flagged as unverified with a task (3) assigned to resolve it, rather than asserted — correct per the verification-precedes-the-claim rule.
- **Task ordering / red-before-green is intact for the pieces it covers.** Task 1 (red) → Task 2 (green) for the classifier; Task 3 is explicitly "Red then green" for git-guard.sh's new path; Tasks 5–6 require proving old behavior first before accepting new cases, which correctly targets `merge-guard.sh` as the one silent-failure-mode change. Tasks 4 and 5 don't spell out "red then green" as explicitly as Tasks 1–3 do, mirroring the same granularity inconsistency round 1 already noted as non-blocking; not re-cited as a new violation.
- **All six rows of the measured-defect table reproduced live, again**, against the current (still-buggy, pre-fix) hooks: plain forms block (`rc=2`) for `git-guard.sh` (default-branch commit, bare force-push), `doc-guard.sh` (undocumented commit), and `merge-guard.sh` (`gh pr merge`); every global-option / chained form silently allows (`rc=0`) as claimed, confirming rows (a)–(e) are still live, real bugs as of this HEAD, not stale claims.
- **Pinned versions re-confirmed**: `git --version` on this machine reports `2.50.1 (Apple Git-155)`, matching the spec exactly; the full synopsis text I pulled from `git --help` and `man git` is byte-for-byte identical to the block quoted in "Measured git 2.50.1 global-option grammar."

### Waivers

_None recorded (round 2) — nothing offered as a waiver by the dispatching context._

## Round 3 — 2026-08-17

**Verdict: FAIL** (confidence: high) — ⚠️ escalation tripwire: third consecutive FAIL, goes to the user.

### Layman summary

Revision 3's own fix for round 2's finding holds up: the `--exec-path` row is out of
the shared harmless-option table, its own new Scenario Outline asserts the
differentiated "prints and exits" message correctly, and the message/decision
split is no longer contradicted anywhere. That specific defect is closed.

But this round's brief was to sweep the *whole* spec for the same failure shape —
"a MUST with no task and no scenario that can actually fail on it" — rather than
just re-checking the one line item that was fixed, and that sweep turned up three
new problems, all introduced by revision 3's own ~50 added/changed lines, two of
them concrete factual errors I could reproduce, not judgment calls:

1. **The replacement option is itself wrong.** Revision 3 swapped `--exec-path`
   out of the shared "harmless option" Scenario Outline and put `--attr-source`
   in. But `--attr-source` is documented three paragraphs earlier in this same
   spec as *value-consuming* — and the spec's own flowchart says a value-consuming
   harmless option must skip one extra token. Plugged into the Outline's shared
   template, that means the literal word `commit` gets eaten as `--attr-source`'s
   value, not read as the subcommand. I ran the actual command: `git --attr-source
   commit -m x -- app.js` does not commit anything and git itself errors out
   (exit 129, "unknown option: -m") — nothing like the "blocked for committing to
   main" outcome the Scenario asserts. A classifier built exactly to the spec's
   own rules would emit `SCOPE_UNKNOWN` here (ask), which is the opposite of what
   the row promises. This is the same species of bug round 2 found in
   `--exec-path` — a Scenario asserting the wrong outcome for one specific listed
   option — just relocated to the option that replaced it.
2. **Task 7 points the automated regression test at a file that can't hold it.**
   Revision 3 rewrote Task 7 to require the six-row measured-defect table become
   automated cases "in the automated suite from task 1"
   (`classify-git-command.test.py`). I read that file: its own docstring says it
   pins the classifier's *fact* output only, never a hook's exit code, and it
   never invokes `git-guard.sh`, `doc-guard.sh`, or `merge-guard.sh` at all. Five
   of the six rows are about exactly those hooks' exit codes. Worse,
   `merge-guard.sh` — the guard this spec itself calls the one "silent
   under-blocking" risk — has no test file in `hooks/` at all
   (`merge-guard.test.sh` does not exist), and Task 8's "dependent suites green"
   list doesn't mention merge-guard either. As written, an implementer cannot do
   what Task 7 asks for five of its six rows.
3. **The two new Task-3b scenarios have no suite that can express them.** Both
   need to check the exact *message text* `git-guard.sh` writes, and one of them
   ("emptying `PRINTS_AND_EXITS` and re-running the suite") also needs some way
   to override that internal set from outside the script. I checked both existing
   suites for this code path: `classify-git-command.test.py` never runs
   `git-guard.sh` and asserts facts only; `git-guard.test.sh`'s own `run_case`
   helper explicitly throws away both stdout and stderr
   (`bash "$HOOK" >/dev/null 2>&1`) and checks only the exit code. Task 3b says
   to "land the two scenarios above" but names neither a suite nor a mechanism
   for either requirement.

Findings 2 and 3 are the exact pattern this spec has now shipped three times in a
row (round 1: the merge-guard ask row; round 2: the print-and-exit message; round
3: the defect-table suite target and the message/decision-invariance scenarios) —
a requirement stated as settled with no buildable path to it. Finding 1 is a new
species: not a missing mechanism, but a factually wrong assertion, provable by
running the actual command.

### Round-2 violation — verification of the fix

`writing-specs/prints-and-exits-no-enforcing-scenario` — **substantively CLOSED**
for the exact defect round 2 named. Re-checked, not re-read: Task 3b now exists
and explicitly assigns building the `PRINTS_AND_EXITS` message swap; the new
`Scenario Outline: a print-and-exit option is still refused, but told the truth
about why` correctly asserts the differentiated message for all six
`PRINTS_AND_EXITS` members, including `--exec-path`, and explicitly asserts the
generic main-brank message is *not* used; `--exec-path` is no longer in the
harmless-skip Outline's Examples table (`--attr-source` took its place — see
finding 1 above, a new defect, not a reopening of this one). No sentence anywhere
still asserts the generic message for a `PRINTS_AND_EXITS` member. Not reused as
an id this round because the specific defect it named is gone; the new problems
in the same territory are distinct enough (a wrong option choice, a wrong test
target, an unbuilt harness capability) to need their own ids for the record to
stay accurate about what actually recurred versus what is new.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/attr-source-consumes-subcommand` | `skills/writing-specs/SKILL.md` | "What a Spec Must Contain" — no requirement left readable two ways; good/bad/edge-case scenarios must state explicitly what correct looks like | Scenarios → `Scenario Outline: a harmless global option is skipped and the command is still seen`, Examples row `--attr-source` (added in revision 3, replacing `--exec-path`) | `--attr-source` is classified in this same spec's "six more from man git" table as `consumes` (value-consuming), and the spec's own flowchart node for a bucket-1 option says "skip it (+1 more token if it consumes one)". Substituted into the Outline's shared template `git <option> commit -m x -- app.js`, that extra skip eats the literal token `commit` as `--attr-source`'s value, leaving `-m` as the next token — which the same flowchart routes to bucket 3 (unrecognised) and emits `SCOPE_UNKNOWN`, contradicting the row's asserted `Then git-guard refuses with exit 2 for committing to main / And no SCOPE_UNKNOWN fact is emitted`. Verified empirically in a throwaway repo: `git --attr-source commit -m x -- app.js` commits nothing and git itself exits 129 with "unknown option: -m" — not a main-branch-block. Fix: give `--attr-source` its own scenario with an explicit value token before `commit` (mirroring the existing `--git-dir` value-consuming scenario), or drop it from this shared-template Outline. |
| `writing-specs/defect-table-wrong-test-suite` | `skills/writing-specs/SKILL.md` | "What a Spec Must Contain" — requirements concrete enough for the agent to satisfy and the reader to check; no requirement left readable two ways | `## Tasks`, item 7 (rewritten in revision 3) | Task 7 requires the six-row measured-defect table be encoded "as cases in the automated suite from task 1" — `hooks/lib/classify-git-command.test.py`. That file's own docstring states it pins only the classifier's fact output and explicitly defers hook-level pass/fail behaviour to `git-guard.test.sh`/`doc-guard.sh`'s own suites; it never invokes any of the three hooks as a subprocess. Rows (a)-(e) of the defect table are about `git-guard.sh` and `doc-guard.sh` exit codes (a-c) and `merge-guard.sh` exit codes (d-e) — none expressible there. `merge-guard.sh` additionally has no test file anywhere in `hooks/` (`merge-guard.test.sh` does not exist), and Task 8's "dependent suites green" list omits merge-guard entirely — the single guard this spec calls its one silent-failure risk has no automated regression coverage named in any task. Fix: route rows (a)-(b) into `git-guard.test.sh`, row (c) into `doc-guard.test.sh`, add a task creating `merge-guard.test.sh` for rows (d)-(e), and correct Task 7's wording (and Task 8's list) accordingly. |
| `writing-specs/message-assertions-no-test-harness` | `skills/writing-specs/SKILL.md` | "What a Spec Must Contain" — good/bad/edge-case scenarios stated explicitly with a buildable path; no requirement left readable two ways | Scenarios → `Scenario Outline: a print-and-exit option is still refused, but told the truth about why` and `Scenario: the print-and-exit set changes the message only, never the decision`, tied to Task 3b | Both scenarios require asserting on `git-guard.sh`'s stderr *message text*; the second additionally requires a way to empty the internal `PRINTS_AND_EXITS` set from outside the script ("When PRINTS_AND_EXITS is emptied and the suite is re-run"). Neither existing suite for this code path supports either: `classify-git-command.test.py` never runs `git-guard.sh`; `git-guard.test.sh`'s `run_case` helper discards stdout and stderr (`bash "$HOOK" >/dev/null 2>&1`, checks only exit code — confirmed by reading it). Task 3b says to "land the two scenarios above" but names no suite and no override mechanism for either requirement — the same "MUST with no buildable mechanism" pattern this spec has now shipped three revisions running, just moved one level deeper (a task and a scenario exist this time, but the scenario's own preconditions are unbuildable against the harness that exists). Fix: extend `git-guard.test.sh` to capture and assert on stderr text, and either expose `PRINTS_AND_EXITS` as an overridable value (e.g. an env var, in the spirit of the existing `MERGE_EXEMPT` pattern) or replace the "empty the set" scenario with concrete before/after message assertions the existing black-box harness can actually express. |

### Notes (non-blocking, round 3)

- **`SCOPE_UNKNOWN`'s "first triggering option only" rule has no multi-trigger scenario.** "Accepted limits" and the Contract section both state that when more than one `SCOPE_UNKNOWN`-triggering option appears on one line (their own example: `git -c a=b -C /x commit`), only the first is named. No Scenario or Example exercises two triggering options together. Low stakes — the ask-vs-allow decision is unaffected either way, only which option name appears in the prompt text — so not cited as a blocking violation, but worth a dedicated example given how much of this spec's rigor is going toward exactly this class of message-content precision elsewhere.
- **Task 3b still doesn't carry an explicit Red/Green label**, unlike Tasks 1-3. Same granularity inconsistency rounds 1 and 2 already noted as non-blocking; not re-cited as a new violation.
- **Everything re-derived this round, not re-read, holds:** all five pinned tool versions (`git 2.50.1 (Apple Git-155)`, `Python 3.9.6`, `bash 3.2.57`, `shellcheck 0.11.0`, `awk 20200816`) match the installed tools exactly; `doc-guard.sh:127` — corrected in revision 3 from `:27` — really does carry the quoted phrase "a missing note is not worth blocking work over"; the new ADR number 0029 is genuinely free (origin/main's `docs/decisions/` tops out at 0026; this worktree's own local `0027-the-marker-is-a-receipt-not-a-grade.md` is exactly the "paused marker-gate branch" the spec's comment names, and no local `0028` exists — the reservation and the choice of 0029 are both accurate as of this HEAD).
- **The `--exec-path` fix itself (finding closed above) is otherwise sound**: the differentiated-message Outline's six Examples are all genuinely no-value or attach-only options (verified against the spec's own value-consumption tables), so no sibling contradiction was found there.

### Waivers

_None recorded (round 3) — nothing offered as a waiver by the dispatching context, and none of the three findings above are being waived on this judge's own initiative._

## Round 4 — 2026-08-17

**Verdict: FAIL** (confidence: high) — 4th consecutive FAIL; round 3 already tripped the
escalation-to-user tripwire, so this is a status update on an already-escalated card, not a new
escalation.

### Layman summary

Revision 4/4.1 genuinely fixes all three problems round 3 found. I re-derived every one of them
against this branch's live files rather than trusting the spec's own "corrected" notes: `--attr-source`
is out of the shared harmless-option table and now has its own two scenarios, and I ran the actual
command (`git --attr-source commit -m x -a`) and confirmed it errors `unknown option: -m` and commits
nothing, exactly as the spec now says. Task 7 now routes each row of the defect table to the hook
whose exit code it actually is, and task 0b adds the `merge-guard.test.sh` suite that never existed —
confirmed still absent from `hooks/` today, so the gap this task closes is real. And the message
scenarios' harness gap is closed two ways: a stdout-capturing helper is now explicitly scoped as new
groundwork (task 0a), while the exit-2 message path can already use `assert_stderr`, which I confirmed
really exists at `git-guard.test.sh:252-259` and really discards stdout via the `2>&1 1>/dev/null` swap
at line 254 — both exactly where the spec's own revision-4.1 table says. The runtime-override risk in
the "empty `PRINTS_AND_EXITS`" scenario — round 3's other half — is now explicitly a hand-mutate-and-
restore round with no new env var, matching the house's own precedent at
`git-guard-detached-head.md:743-785`, which I opened and confirmed really does describe that pattern.

I also independently re-ran the git-behavior claims the round 4 brief flagged by name: `--bare` really
does make git read the cwd as the repo (`fatal: not a git repository`, confirmed live); `--list-cmds`
really does print a command list in the `=` form and error `unknown option: --list-cmds` bare, neither
ever reaching `rev-parse`; `--attr-source`'s space form really does consume the next token (confirmed
with a valid tree-ish, `HEAD`); `--exec-path` bare really doesn't commit while `--exec-path=<path>`
does. Every pinned tool version and both binary-extracted strings (`Valid types are: allow, deny, ask,
defer`; the `bypassPermissions` sentence) matched the installed tools exactly. The counts "18 hook
scripts / 8 `*.test.sh` suites," "224 lines," and "198 lines" all reproduced exactly.

But one thing doesn't hold up, and it's a genuine, checkable defect rather than a judgment call: two
`git-guard.sh` line citations are stale for the branch actually being judged.

### Round-3 violations — verification of the fix

All three **CLOSED**, re-derived rather than re-read:

- **`writing-specs/attr-source-consumes-subcommand` — CLOSED.** `--attr-source` no longer appears in
  the shared harmless-skip Examples table (confirmed by reading the table: 8 rows, none is
  `--attr-source`). It now has two dedicated scenarios ("a value-consuming harmless option takes the
  next token, not the subcommand" and "a consuming option with the subcommand as its value commits
  nothing"). I ran both underlying commands live: `git --attr-source commit -m x -a` → `unknown option:
  -m`, exit 129, no commit created (matches the second scenario exactly); `git --attr-source HEAD
  commit -m x -a` (a valid tree-ish, since `.gitattributes` in the spec's own example only fails later
  at attribute-resolution time, not at option-parsing time — I checked this distinction directly) →
  commits normally, confirming the option really does consume a value and the subcommand really does
  resolve to `commit` (matches the first scenario's intent).
- **`writing-specs/defect-table-wrong-test-suite` — CLOSED.** Task 7 now reads "encode the rows as
  cases in the **hook-level** harnesses from 0a/0b — rows (a)(b) in `git-guard.test.sh`, row (c) in
  `doc-guard.test.sh`, rows (d)(e) in the new `merge-guard.test.sh`, and row (f) as a control in
  `classify-pr-command.test.py`. **Not** in the task-1 suite." Task 0b creates `merge-guard.test.sh`,
  and I confirmed it genuinely does not exist yet anywhere in `hooks/` (`find hooks -maxdepth 1 -name
  "*.test.sh"` returns 8 files, none named `merge-guard.test.sh`), so the gap this task exists to close
  is real and the fix gives it a concrete, buildable home.
- **`writing-specs/message-assertions-no-test-harness` — CLOSED**, in two parts. First (harness
  existence): task 0a adds a **stdout** assertion helper modeled on the existing `assert_stderr`, and
  gives `doc-guard.test.sh` both channels it currently lacks — I confirmed `doc-guard.test.sh`'s
  `run_case` (`:66-76`, discarding both channels at `:68`) has no sibling message-asserting helper
  anywhere in the file (`grep` for `assert_std`/`assert_stderr` returns nothing). Second (the runtime-
  override risk): the "empty `PRINTS_AND_EXITS`" scenario is now explicitly framed as "a MUTATION
  ROUND, not a runtime switch," with task 3b saying plainly "do NOT add an env var or any other runtime
  seam to empty the set" and pointing at the house's existing hand-mutate/restore pattern. I opened
  `git-guard-detached-head.md:743-785` and `memsearch-freshness.md:1282` and confirmed both really do
  describe exactly that pattern (mutate the source by hand, confirm the expected assertions go red and
  nothing else does, restore, diff clean) — legitimate precedent, not an invented one.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `core-conduct/stale-line-citation` | `rules/core-conduct.md` | "Verification precedes both the claim and the write-down — never state that something works... until you have actually run it and re-read the output." | "Measured defect" background ("Guard logic confirmed at `git-guard.sh:142` (`has_fact PUSH_FORCE`) and `:152` (`has_fact COMMIT && on_main`)") and Task 3 ("the check must NOT be nested inside the `on_main` block at `:152`") | This branch (`feature/global-option-blindness`) was created (`4c9a431`) **after** PR #52 (`fix/git-guard-detached-head`) merged into `main`, which added ~140 lines to `hooks/git-guard.sh` (the new `checkout_desc()` helper and its surrounding comments). On this branch's actual HEAD, `git-guard.sh:142`/`:152` fall inside `checkout_desc()` — confirmed by reading them directly, they contain none of the cited code. The real locations, confirmed by `grep -n`, are `has_fact PUSH_FORCE` at `:280` and `if has_fact COMMIT && on_main; then` at `:292`. This citation was correct when it was independently re-derived in round 2 (`git-guard.sh:142`, `:152` — both verified then) but that verification ran on a *different* branch/worktree (`feature/verification-marker-gate`, per this round's own branch note); when the spec was "rescued" onto this branch it carried the citation forward unchanged rather than re-deriving it against the file this branch actually ships. This is not cosmetic: Task 3 uses `:152` to tell the implementer *where the block is that the new check must not be nested inside* — on this branch that line is `checkout_desc`'s case statement, not `on_main`'s block, so an implementer following the citation literally would look in the wrong place. Fix: update both citations to `:280` and `:292` (or re-run `grep -n` at implementation time and stop hardcoding either, given how much this file has moved once already). |

### Notes (non-blocking, round 4)

- **"The exhaustive membership is the union of the two Examples tables" (bucket 1, "The rule" section)
  is not quite true as written**, and it's new text from the 4.1 sweep itself. The same paragraph
  assigns `--attr-source` to bucket 1 by prose two sentences earlier, but `--attr-source`'s behavior is
  tested by two standalone `Scenario:` blocks, not by either of the two `Scenario Outline` + `Examples:`
  tables the sentence points at — so the claim "enumerated by test, never by prose" technically doesn't
  hold for that one member, ironically the same defect shape the sweep just fixed for bucket 2 (options
  assigned by prose but missing from the Examples table). Not blocking: the behavior itself *is*
  scenario-backed (just not via an "Examples table" specifically), so no implementer loses a buildable
  path — but worth tightening the sentence (e.g. "the two Examples tables plus the two `--attr-source`
  scenarios") the next time this section is touched.
- **Task 1's "the Examples-driven cases above" could be read narrowly.** Read literally it might seem
  to scope `classify-git-command.test.py`'s new cases to only the `Scenario Outline`/`Examples:` blocks,
  which would silently drop ~8 standalone `Scenario:` blocks that are equally fact-level and equally
  new (the two `--attr-source` scenarios, the abbreviated-option scenario, the two multi-segment
  scenarios, etc.). I don't think this is the intended reading — Task 2 explicitly says "both halves
  have scenarios above, and both were previously contract-only," referring to the whole Scenarios
  section, not just Outline tables — and the closing "Fixtures must be built..." paragraph uses
  "Examples tables" the same loose way even for bucket 3, which has no literal Examples table at all.
  Consistent informal usage throughout, not a real gap, but the phrase is doing double duty and a
  future revision could tighten it.
- **Everything else re-derived this round, independently, matches:** all 5 pinned tool versions (git
  2.50.1 (Apple Git-155), Python 3.9.6, bash 3.2.57, shellcheck 0.11.0, awk 20200816) match the
  installed tools exactly, including a fresh check of the user's shell alias carrying
  `--allow-dangerously-skip-permissions` (Task 9's own claim); both binary-extracted strings (`Valid
  types are: allow, deny, ask, defer` at one `strings` offset, the full `bypassPermissions` sentence at
  another) are verbatim present in the installed Claude Code 2.1.233 binary; `--bare`, both spellings of
  `--list-cmds`, `--attr-source`'s value-consuming behavior, and `--exec-path`'s bare-vs-`=` split all
  reproduced exactly as the spec states; the "18 hook scripts / 8 `*.test.sh` suites" count, and the
  224-line / 198-line file counts, are exact as of this HEAD (`a5de681` and current HEAD agree, since
  neither sweep commit touched the hooks); ADR 0029 is genuinely free against both `origin/main` (tops
  out at 0026) and the local `0027`-holding marker-gate worktree; every other `file:line` citation I
  checked (`doc-guard.sh:91-100`, `:127`; `merge-guard.sh:82`, `:93`; `classify-pr-command.py:38-45`;
  `classify-git-command.py:79-110`, `:90-105`, `:31-40`, `:104`; `judge-guard.sh:230`;
  `feature-sync-guard.sh:136`) points at the text quoted, exactly.

### Waivers

_None recorded (round 4) — no waived ids were provided, and none of the finding above is being waived
on this judge's own initiative._

## Round 5 — 2026-08-17

**Verdict: FAIL** (confidence: high) — 5th consecutive FAIL. Already escalated to the user after
round 3; this is a status update on that escalation, not a new trip.

### Layman summary

Round 4's single problem — two `git-guard.sh` line numbers that pointed at the wrong code because
this branch pulled in ~140 unrelated lines from another PR — is genuinely fixed. I re-derived both
from scratch rather than trusting the spec's own "corrected" note: `has_fact PUSH_FORCE` really is
at line 280 and `if has_fact COMMIT && on_main; then` really is at line 292 on this branch's current
HEAD, Task 3 now names the block by its literal source text as a second, line-number-independent
anchor, and the neighbouring `classify-git-command.py` citations (`:150`, `:152`, `:169`) still hold
exactly. The round-4 non-blocking note is also applied correctly: the bucket-1 paragraph no longer
claims every harmless option lives in "the union of the two Examples tables" — it now explicitly
carves out `--attr-source`, which is scenario-backed but not table-backed.

I then did what this round's brief asked and re-checked the file's *other* citations rather than
assuming the one named fix was the only thing that needed eyes, since it's a small delta but the
brief says to judge the whole spec. Almost everything held: I independently reproduced every listed
git 2.50.1 behavior (`--bare` making git read the cwd itself as the repo, both spellings of
`--list-cmds`, `--attr-source`'s space-form value-consumption, `--exec-path`'s bare-vs-`=` split),
confirmed both binary-extracted strings from the Claude Code 2.1.233 executable itself (`Valid types
are: allow, deny, ask, defer`; the `bypassPermissions` sentence), confirmed the user's shell alias
really does carry `--allow-dangerously-skip-permissions` (Task 9's premise), confirmed all five other
pinned tool versions, confirmed the "18 hook scripts / 8 `*.test.sh` suites" count and both file line
counts (224, 198) are exact as of this HEAD, confirmed ADR 0029 is free against `origin/main` and
against the sibling `feature/verification-marker-gate` worktree that actually holds ADR 0027, and
walked every remaining `file:line` citation in the document (`doc-guard.sh:91-100`/`:127`,
`git-guard.test.sh:226`/`:252-259`, `doc-guard.test.sh:66-76`/`:68`, `merge-guard.sh:82`/`:93`,
`classify-pr-command.py:38-45`, `classify-git-command.py:31-40`/`:79-110`/`:90-105`/`:104`,
`judge-guard.sh:230`, `feature-sync-guard.sh:136`, and the cross-branch citation
`verification-marker-gate.md:781-796`) — all point exactly at the text the spec quotes or describes.

One did not hold, and it's the same species of defect as round 4's, just relocated. The Scenarios
section still says: *"The house already solves this by hand-mutating the source and restoring it
(`docs/features/git-guard-detached-head.md:743-785`, `memsearch-freshness.md:1282`)."* The first
citation is accurate — I opened it and it really does narrate mutate-the-hook / confirm-red /
`git checkout --` restore / diff-clean. The second is not: `memsearch-freshness.md`'s line 1282, as
it stands right now, reads *"wedged-run all render their intended state. The live file has no run
stamps yet, so the"* — the middle of a **live-smoke-test** bullet, not a mutate-and-restore bullet.
The nearest bullet that actually is about mutation testing sits just above it (lines 1276–1280,
"Mutation check: 8 mutations, 7 caught") but doesn't itself narrate a restore step either; the
passage that actually matches the claim — revert, observe both tests fail, restore, 74 pass — is much
further down, at lines 1347–1348 and 1380. I also checked whether this could be explained the way
round 4's citation drift was (the cited file moved after the citation was written): it isn't — that
file's last commit is 2026-08-08, nine days before this citation was written on 2026-08-17, so the
citation was wrong the moment it was added, not made wrong by later drift elsewhere. This is a small,
non-load-bearing citation (the paired `git-guard-detached-head.md` citation already carries the
claim on its own, and Task 3b's actual requirement — hand-mutate, no env var — is unambiguous with or
without it), but it is the identical rule this card has now failed a round over once already: a
citation written down and not verified before being asserted as fact.

### Round-4 violation — verification of the fix

`core-conduct/stale-line-citation` — **CLOSED** for the citation it named, re-derived rather than
re-read:

- `grep -n "has_fact PUSH_FORCE"` → `280:if has_fact PUSH_FORCE; then`, matching the spec's updated
  `:280` exactly.
- `grep -n "has_fact COMMIT && on_main"` → `292:if has_fact COMMIT && on_main; then`, matching the
  spec's updated `:292` exactly, and Task 3 now also names this block by its literal source text
  (`if has_fact COMMIT && on_main; then`) so an implementer isn't solely dependent on the number.
- The neighbouring `classify-git-command.py` citations (`:150` `subcommand, rest = argv[1], argv[2:]`,
  `:152` `if subcommand == "commit":`, `:169` `elif subcommand == "push":`) all still hold on this
  HEAD, confirming these weren't touched by the same drift.
- The bucket-1 paragraph's over-claim (round 4's non-blocking note) is fixed: it now reads "the two
  Examples tables in the Scenarios section carry all of them ... except `--attr-source`, which
  consumes a value and so cannot use either table's shared template; it has two standalone scenarios
  instead," closing the exact gap the note identified.

Not reused as a violation id this round for that specific citation — it's genuinely fixed. Reused
below for a *different* citation in the same document, since it's the identical rule and the identical
failure shape (an unverified `file:line` reference asserted as fact).

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `core-conduct/stale-line-citation` | `rules/core-conduct.md` | "Verification precedes both the claim and the write-down — never state that something works... until you have actually run it and re-read the output." | Scenarios section, comment above `Scenario: the print-and-exit set changes the message only, never the decision` — "The house already solves this by hand-mutating the source and restoring it (`docs/features/git-guard-detached-head.md:743-785`, `memsearch-freshness.md:1282`)." | `memsearch-freshness.md:1282`, read on the live file today, is `wedged-run all render their intended state. The live file has no run stamps yet, so the` — the middle of a **"Live smoke against the real 7,631-chunk index"** bullet (lines 1281–1283), not a mutate-and-restore bullet. The file's nearby "Mutation check: 8 mutations, 7 caught" bullet (lines 1276–1280) doesn't narrate a restore step either; the passage that actually matches the claimed pattern (revert `chunk.py`'s episodic branch and `_doc_source_type` → both fail; restore → 74 pass; "Original restored byte-identical after both") sits at lines 1347–1348 and 1380. Ruled out drift as the explanation: the cited file's last commit (`e255b2d`, 2026-08-08) predates this citation's addition (`b9c5c9c`, 2026-08-17) by nine days, so the citation did not become stale after the fact — it was never checked against the line it names. The paired `git-guard-detached-head.md:743-785` citation is independently accurate and already carries the underlying claim, so no requirement is left unbuildable, but a second citation next to a verified one that itself turns out unverified is exactly the failure this same spec's own revision-4 note (two paragraphs earlier in this document) calls "a copied citation is laundered, not verified." Fix: repoint to `memsearch-freshness.md:1347-1348` (or `:1380`), or drop the second citation and let the `git-guard-detached-head.md` precedent stand alone. |

### Notes (non-blocking, round 5)

- **Everything else re-derived this round, independently, holds.** Git 2.50.1 behavior for `--bare`
  (`fatal: not a git repository: '<cwd>'`), both spellings of `--list-cmds` (`=main` prints the command
  list and exits 0 without reaching `rev-parse`; bare errors `unknown option: --list-cmds`, exit 129),
  `--attr-source`'s space-form value consumption (`--attr-source HEAD rev-parse …` → `true`;
  `--attr-source commit -m x -a` → `unknown option: -m`, exit 129, no commit), and `--exec-path`'s
  bare-vs-`=` split (bare prints the exec path and commits nothing; `=/tmp` commits normally) all
  reproduced exactly as the spec states. Both binary-extracted strings (`. Valid types are: allow,
  deny, ask, defer`; the full `bypassPermissions` sentence) are verbatim present in the installed
  Claude Code 2.1.233 executable (`/Users/marksuyat/.local/bin/claude`). All five other pinned
  versions match (`git 2.50.1 (Apple Git-155)`, `Python 3.9.6`, `bash 3.2.57 (arm64-apple-darwin25)`,
  `shellcheck 0.11.0`, `awk 20200816 (BSD)`), including a fresh check that the user's shell alias
  really does carry `--allow-dangerously-skip-permissions` (Task 9's premise). The "18 hook scripts /
  8 `*.test.sh` suites" count (`ls hooks/*.sh` minus `*.test.sh` = 18; `ls hooks/*.test.sh` = 8) and
  both file line counts (`classify-git-command.test.py` = 224, `classify-git-command.py` = 198) are
  exact on this HEAD. ADR 0029 is genuinely free: `origin/main`'s `docs/decisions/` tops out at 0026,
  and the sibling `feature/verification-marker-gate` worktree confirms 0027 is taken
  (`0027-the-marker-is-a-receipt-not-a-grade.md`) with no local 0028 anywhere.
- **Every remaining `file:line` citation checked, all hold:** `doc-guard.sh:91-100` (the
  `case "$event" in ... *) exit 0 ;; esac` dispatch, confirmed spanning exactly those lines) and
  `:127` (`# fails OPEN throughout, because a missing note is not worth blocking work over.`,
  verbatim); `git-guard.test.sh:226` (`_run_case_common`) and `:252-259` (`assert_stderr`, whose body
  really does run `2>&1 1>/dev/null` at what is now line 254); `doc-guard.test.sh:66-76`/`:68`
  (`run_case`, whose body discards both channels at `>/dev/null 2>&1`); `merge-guard.sh:82`
  (`toks[i:i+3] == ["gh", "pr", "merge"]`) and `:93` (the `MERGE_EXEMPT` stderr `printf`);
  `classify-pr-command.py:38-45` (the "global flags are legal before the subcommand" comment plus the
  adjacent-pair scan loop); `classify-git-command.py:31-40` (the GRANTING vs DENYING rule), `:79-110`
  (the value/safe-flag tables), `:90-105` (the UNRECOGNISED-means-block comment plus
  `COMMIT_SAFE_FLAGS`), `:104` (`-S`, `--gpg-sign`'s short form); `judge-guard.sh:230` and
  `feature-sync-guard.sh:136` (both `printf … >&2` exemption lines); and the cross-branch citation
  `docs/features/verification-marker-gate.md:781-796`, opened in the sibling
  `feature/verification-marker-gate` worktree — the `UNRESOLVED — user-waived` block starts at line
  781 and the "blocked on that decision landing" sentence ends the block at line 796, exactly as
  cited.
- **The revision-4.1 table's self-corrections also still hold**, checked as history rather than live
  fact since the spec frames them that way: `git-guard.test.sh:347` really is fixture code unrelated
  to the exit-code runner (correctly superseded by `:226`), and `doc-guard.sh:27` (the round-3
  correction) was never the right line for the quoted phrase, which lives at `:127` as the spec now
  states throughout.

### Waivers

_None recorded (round 5) — no waived ids were provided, and the finding above is not being waived on
this judge's own initiative._

## Round 6 — 2026-08-17

**Verdict: PASS** (confidence: high) — first PASS after 5 consecutive FAILs.

### Layman summary

Round 5's finding was a small but real citation error: the spec pointed at a second document
(`memsearch-freshness.md:1282`) to back up "the house already solves this by hand-mutating and
restoring," and that line didn't say what the spec claimed. This round's fix doesn't repoint the
citation — it drops it, and explains why dropping is the right call rather than patching: that
line only ever half-supported the claim (it showed a mutation, never a restore), and worse, it was
a citation into a *different branch's* live document, which reads differently depending on which
checkout of this repo the reader has open — no amount of re-deriving fixes that kind of instability.
The single citation that remains, `git-guard-detached-head.md:743-785` (`:755` for the explicit
restore step), already carries the whole claim on its own and is a document already merged to
`main`, so it can't drift out from under a reader the way the dropped one could.

I independently re-derived every citation and factual claim in the document this round, not just
the one that changed, working entirely from this worktree
(`/Users/marksuyat/.claude/.claude/worktrees/global-option-blindness`) as instructed — the round-5
mistake was reading `$HOME/.claude`'s copy of a same-named path on another branch, and I confirmed
the two checkouts really do diverge (this worktree's `docs/decisions/` tops out at 0026 same as
`origin/main`; `$HOME/.claude` itself is on `feature/memsearch-freshness` and tops out at 0021 —
a different history entirely, never used as ground truth here). Everything held:

- **The dropped citation is genuinely gone.** `grep -n memsearch-freshness` on the live spec returns
  only the one historical sentence explaining *why* it was dropped — no remaining citation into that
  file anywhere.
- **The replacement citation is exact.** `docs/features/git-guard-detached-head.md` is 866 lines in
  this worktree, byte-identical to `origin/main`'s copy of the same file (`diff` on lines 740-790
  empty). Line 755 reads verbatim "Restored the file after each mutation and confirmed `diff`
  against the pre-mutation copy" — exactly the quoted text — and it sits inside the larger
  743-785 mutation-and-restore narrative the spec points at.
- **Every other `file:line` citation in the document re-derived from scratch, all exact:**
  `classify-git-command.py:150` (`subcommand, rest = argv[1], argv[2:]`), `:152`
  (`if subcommand == "commit":`), `:169` (`elif subcommand == "push":`), `:31-40` (the GRANTING/
  DENYING rule), `:104` (`-S`/`--gpg-sign`); `git-guard.sh:280` (`has_fact PUSH_FORCE`), `:292`
  (`if has_fact COMMIT && on_main; then`); `git-guard.test.sh:224` for the `_run_case_common`
  function and `:226` for its exit-code-only line (`>/dev/null 2>&1`, discarding both channels
  before `got=$?` on the next line — the spec's `:226` citation targets that specific line, and it's
  exact), `:252-259` (`assert_stderr`, opening to closing brace), `:254`
  (`2>&1 1>/dev/null`); `doc-guard.test.sh:66` (`run_case`) and `:68`
  (`>/dev/null 2>&1`); `doc-guard.sh:91-100` (the `case "$event" in ... *) exit 0 ;;` dispatch) and
  `:127` ("a missing note is not worth blocking work over," verbatim); `merge-guard.sh:82`
  (`toks[i:i+3] == ["gh","pr","merge"]`) and `:93` (the `MERGE_EXEMPT` `printf … >&2`);
  `classify-pr-command.py:38-45` (the "global flags are legal before the subcommand" comment and
  adjacent-pair scan); `judge-guard.sh:230` and `feature-sync-guard.sh:136` (both `printf … >&2`
  exemption lines); and the cross-branch `docs/features/verification-marker-gate.md:781-796`,
  opened in the worktree that actually holds `feature/verification-marker-gate`
  (`worktrees/tracking-feature-state`, not the old `verification-marker-gate` path — `git worktree
  list` shows it moved) — the "UNRESOLVED — user-waived" block starts at 781 and "blocked on that
  decision landing" ends the block at 796, exactly as cited, and that file's frontmatter really does
  carry `revision_status: complete`.
- **All git 2.50.1 behavior claims reproduced live, in a fresh throwaway `git init -b main` repo:**
  `--bare` makes git read the cwd itself as the repo (`fatal: not a git repository: '<cwd>'`);
  `--list-cmds=main` prints the full command list and exits 0 without ever reaching `rev-parse`,
  bare `--list-cmds` errors `unknown option: --list-cmds` (exit 129); `--attr-source HEAD rev-parse
  --is-inside-work-tree` consumes `HEAD` and returns `true`, while `--attr-source commit -m x -a`
  errors `unknown option: -m` and leaves the repo's commit log unchanged (confirmed via `git log
  --oneline` before/after); `--exec-path commit -m x -a` bare prints the exec path and commits
  nothing (log unchanged), `--exec-path=/tmp commit -m x -a` commits normally (new commit appears).
- **All five pinned tool versions match**, confirmed live: `git 2.50.1 (Apple Git-155)`, `Python
  3.9.6`, `bash 3.2.57(1)-release (arm64-apple-darwin25)`, `shellcheck 0.11.0`. The sixth,
  **Claude Code 2.1.233**, is no longer the *active* installed version — the environment auto-updated
  to `2.1.234` earlier today (`/Users/marksuyat/.local/bin/claude` now symlinks to the `2.1.234`
  build, timestamped after this spec's last edit). This is not a spec defect: the exact `2.1.233`
  binary is still archived at `/Users/marksuyat/.local/share/claude/versions/2.1.233`, and both
  strings the spec quotes as "verbatim from the same binary" — `Valid types are: allow, deny, ask,
  defer` and the full `bypassPermissions` sentence — are confirmed present, verbatim, in that exact
  archived binary. The spec's claim is about what `2.1.233` says, and it still says it; it is simply
  no longer the version a reader gets by running `claude --version` today. Noted below as a
  non-blocking observation, since the next revision that touches this section will need to re-pin or
  re-verify against whatever is current then.
- **File-size and count claims all exact:** `hooks/lib/classify-git-command.py` is 198 lines,
  `hooks/lib/classify-git-command.test.py` is 224 lines, `hooks/` holds 18 non-test hook scripts and
  8 `*.test.sh` suites, and `hooks/merge-guard.test.sh` still does not exist (confirming task 0b's
  premise is still live, not already done).
- **ADR 0029 is still free.** `origin/main`'s `docs/decisions/` tops out at 0026, this worktree's
  local copy matches; the worktree holding `feature/verification-marker-gate` (now at
  `worktrees/tracking-feature-state`) confirms ADR 0027 is taken there and no local 0028 exists
  anywhere. (That worktree's *own* `0026-the-gate-does-no-json-parsing.md` collides with
  `origin/main`'s already-merged `0026-symbolic-ref-not-abbrev-ref-names-the-branch.md` — a
  pre-existing numbering conflict on that other branch, unrelated to and not caused by this spec,
  and not this card's problem to fix.)

Nothing failed re-derivation. No new defect of any kind — citation, factual claim, buildability gap,
or scope creep — was found anywhere in the document this round.

### Round-5 violation — verification of the fix

`core-conduct/stale-line-citation` — **CLOSED**, by removal rather than repair, and the removal
itself checks out:

- `grep -n memsearch-freshness docs/features/global-option-blindness.md` returns exactly one line —
  the historical sentence recording *why* the citation was dropped — and no live citation into that
  file remains anywhere in the document.
- The surviving citation, `git-guard-detached-head.md:743-785`/`:755`, was independently re-derived
  against this worktree's copy (confirmed byte-identical to `origin/main`'s merged copy over the
  cited range) and matches exactly, including the newly-added exact quote at `:755`.
- The new house rule the spec records — "cite precedent from THIS worktree, and prefer a document
  already merged to main" — is not just stated but satisfied by its own remaining citation: the doc
  it points to actually is on `main`.

Not reused as a violation id this round; nothing recurred.

### Violations

_None._

### Notes (non-blocking, round 6)

- **Claude Code version drift since round 5.** The environment's active `claude` binary is now
  `2.1.234`, not the pinned `2.1.233`. The spec's binary-derived claims still verify exactly against
  the archived `2.1.233` build, so this is not a defect in the spec as written — but if a future
  revision re-touches the "Contract — how a refusal reaches the user" section, re-pin against
  whatever is current then rather than assuming `2.1.233` is still installed.
- **A numbering collision exists on a different, unrelated branch** (`feature/verification-marker-gate`,
  now checked out at `worktrees/tracking-feature-state`): its local `0026-the-gate-does-no-json-
  parsing.md` collides with `origin/main`'s already-merged `0026-symbolic-ref-not-abbrev-ref-names-
  the-branch.md`. This spec's own ADR 0029 claim is unaffected and correctly checked against both
  `origin/main` and that branch's real occupant of 0027 — flagged here only so it isn't rediscovered
  as a surprise when that other branch resumes.
- **Task list, scenarios, and contract sections are otherwise unchanged from round 5** (confirmed via
  `git show --stat 21f9b37` and a full diff: only the one 12-line comment block changed), so every
  structural finding closed in rounds 1-5 — the merge-guard ask ambiguity, the untracked-files
  measurement, the print-and-exit enforcement gap, the `--attr-source` table placement, the defect-
  table test-suite routing, the message-assertion harness gap, and the first stale `git-guard.sh`
  citation — remains closed, independently reconfirmed rather than assumed stable.

### Waivers

_None recorded (round 6) — no waived ids were provided, and there is nothing to waive: zero
violations found._
