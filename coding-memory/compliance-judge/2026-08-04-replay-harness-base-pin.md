# Compliance judge — `docs/features/replay-harness-base-pin.md`

Spec slug: `replay-harness-base-pin` · first judged 2026-08-04.

---

## Round 1 — 2026-08-04 — **FAIL** (4 violations)

**Repo:** `.claude` · **branch:** `main` · **head:** `c461e4cd2dfb493a0b0e5d92e10ade7b98c99416`
**Spec blob:** `6cda140e6f9cd7d5a309126844e7f9a433bdb6de` · **Confidence:** high
**Waived coming in:** none.

### Layman summary

The spec is diagnosing a real and well-evidenced bug, and most of it holds up under re-measurement.
I re-ran every factual claim rather than trusting it: the false green reproduces exactly
(`378 identical, 0 stricter, 0 relaxed`, `EXIT=0`), the `grep` count of `0` is right, the line
references are right, and both base commits behave as claimed at the blob level — `bc7da76` differs
from HEAD in `shell_segments.py` only (`git-guard.sh` and `classify-git-command.py` are the same
blobs `2b74507c` and `2f8af693`, exactly as written), and `b17a666` differs in all three. The ADR
immutability claim also checks out: 0011, 0013 and 0009 all record amend-by-new-ADR in their own
text, so declining to edit 0015 is correct. The decision to skip a `git-guard.replay.test.sh` also
holds — `hooks/` really does contain only two harnesses and neither has a test sibling, and Task 1
("Red — reproduce...") satisfies "reproduce before you fix", which the rule allows to be a recorded
repro rather than a unit test. The all-three-not-any threshold is correctly reasoned and correctly
justified by a verifiable example.

Four things block it.

**The big one: Scenario B expects a number that measurement says will be zero.** B is the spec's
designated falsification, and it expects `stricter > 0` "because the redirect fix made the guard
catch more". I ran the full matrix between those two lexers. Every one of the 378 pairs is
identical — the old and new lexers behave the same across the entire command set. So `stricter`
will be `0`, not greater than zero. Worse, the spec already knows this and says so twice in its own
text: the non-goals say the matrix "still contains zero redirect shapes", and the citation table
says the 378 figure "is not evidence the fix works" for precisely that reason. The spec contradicts
itself, and it does so in the one scenario it calls load-bearing. This is the same failure mode the
spec is written to fix — a plausible causal sentence attached to a number nobody measured.

**A new false-green path the fix opens and does not close.** Adding `BASE_REV` lets a caller name
any rev. If that rev resolves but predates one of the three files, `git show` fails, the script has
no `set -e` and never checks the exit code, and the redirection leaves a **zero-byte** base file. An
empty guard script exits `0`, meaning the baseline "allows everything" — so `relaxed` is `0` and the
harness prints a clean pass on its load-bearing claim from a baseline that is an empty file. The new
vacuity check cannot catch it, because an empty file differs from the candidate, so all three
"differ" and the run reports. Scenario D only covers an *unresolvable* rev; the natural way to
implement D (`git rev-parse --verify`) passes this case straight through.

**No pinned versions anywhere.** The spec names `bash` and `git` and depends on byte-comparison
without naming the tool. Both sibling specs in this repo that went through this gate were cited for
exactly this and both fixed it with a pinned toolchain table.

**One ambiguous sentence** about which side of the comparison is read from disk versus from git.

### Verification performed (not taken on trust)

| Claim | Method | Result |
|---|---|---|
| False green reproduces | `bash hooks/git-guard.replay.sh .`, `$?` captured first | ✅ `378 identical, 0 stricter, 0 relaxed`, `EXIT=0` |
| `grep -cE 'BASE_REV\|getopts\|\$\{3'` → 0 | re-ran | ✅ `0` |
| Line refs 6, 7, 13-15, 123-124 | read source | ✅ all correct |
| B: `bc7da76` — only `shell_segments.py` differs | `git rev-parse <rev>:<path>` ×3 | ✅ `2b74507c`/`2f8af693` SAME, `7197eb08`→`b8fed461` DIFF |
| C: `b17a666` — all three differ | `git rev-parse <rev>:<path>` ×3 | ✅ all DIFF |
| **B: `stricter > 0`** | full matrix, base=HEAD vs cand=`bc7da76` | ❌ **378 identical, 0 relaxed, 0 stricter** |
| ADRs immutable / amend-by-new | grep 0009:105, 0011:4-6, 0013:5 | ✅ convention is real |
| Neither harness has a `.test.sh` | `ls hooks/` | ✅ only `replay.sh` + `falsifier.sh`, no siblings |
| Four citations exist as quoted | read each at cited lines | ✅ all four accurate |
| Base-extraction error path | `git show ac5afa2~1:hooks/lib/shell_segments.py` | ❌ `rc=128`, 0-byte file, unchecked; empty script exits `0` |
| Any programmatic caller of replay.sh | repo-wide grep | none — prose references only |

### Violations

| # | id | rule source | where | why |
|---|---|---|---|---|
| 1 | `writing-specs/scenario-b-stricter-claim` | `skills/writing-specs/SKILL.md:28` | Scenarios, B (L124-131); "B is the falsification" (L147-150) | Expected outcome "stricter is greater than zero" is false by measurement — base=`bc7da76` vs HEAD yields 378 identical / 0 stricter / 0 relaxed — and it contradicts the spec's own non-goal (L109-110) and citation table (L69) that the 63-command matrix contains zero redirect shapes. |
| 2 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md:13,21` | The fix, part 1 (L78-80); Scenario D (L138-141) | `BASE_REV` is new user input at a system boundary, but a rev that resolves while predating one of the three files leaves an unchecked `git show` failure and a 0-byte base that exits `0` and "allows everything", producing a clean `0 relaxed` pass the new vacuity check cannot catch. |
| 3 | `writing-specs/pinned-versions` | `skills/writing-specs/SKILL.md:32`; `rules/core-conduct.md:21` | Whole spec — no pinned-toolchain section | No version is pinned for any tool the spec runs (`bash` 3.2.57, `git` 2.50.1, `python3` 3.9.6 here), and the byte-comparison tool is never named, though BSD/GNU dialect splits are the exact trap this repo's judged specs pin `bash` to avoid. |
| 4 | `writing-specs/ambiguity` | `skills/writing-specs/SKILL.md:28` | The fix, part 2 (L82-87) | "Extract the three files from both sides and compare them byte-for-byte" is readable two ways for the `worktree` side — live on-disk files (which is what the harness actually executes, `NEW="$WT/hooks/git-guard.sh"`) or `git show HEAD:` — and the two choices disagree whenever the worktree has uncommitted edits. |

### Notes (non-blocking)

- Spec path is correct for this repo. `writing-specs` defers to `docs/superpowers/specs/`, but the
  repo layer (`rules/gates.md`, one-canonical-file discipline) mandates `docs/features/<name>.md`
  for feature-scale work, and project rules take precedence. All seven siblings live there.
- Scenarios D and E are not well-formed Gherkin — D has no `Given` (defensible; state is
  irrelevant) and E is a meta-assertion over A/B/C with only a `Then`. The intent is clear and
  explained, so this is style, not a blocker.
- The refusal contract and Scenario D both specify only "non-zero" exit. Since no script invokes
  `replay.sh` programmatically (verified), distinct codes are not required — but two different
  failure modes sharing one undifferentiated code is worth a sentence.
- No Mermaid diagram. `writing-specs:26` asks for rendered visual aids; for a ~40-line shell change
  whose logic is fully carried by prose, omitting it reads as KISS rather than a gap.
- Violation 1 has a second-order effect worth surfacing to the author: with `stricter = 0`, Scenario
  B's pair-count line becomes *numerically identical* to the vacuous run's. B still discriminates —
  via the presence of the pair-count line and the absence of the refusal — but not via the counts,
  which is worth stating explicitly so the implementer does not read equal numbers as a failure.
- The non-goal reasoning on `git-guard.replay.test.sh` was checked against the testing rules and
  holds. "Never edit tests and implementation in the same step" is not in territory here (no tests
  are being edited), and "reproduce before you fix" is satisfied by Task 1 recording the red state
  before Tasks 2-3 change anything.

### Waiver record

None. No violation ids were waived by the user for this round, and this spec had no prior rounds.

---

## Round 2 — 2026-08-05 — **FAIL** (2 violations, both new; all 4 round-1 violations fixed)

**Repo:** `.claude` · **branch:** `main` · **head:** `c461e4cd2dfb493a0b0e5d92e10ade7b98c99416`
**Spec blob:** `d76419d07e986ad9cf473934d0cb75f175f531dc` · **Confidence:** high
**Waived coming in:** none.

### In layman's terms

Revision 2 is a large improvement and it is honest: every number in it that I could re-run, I
re-ran, and every one came back exact. The four round-1 findings are genuinely closed, not
papered over. What remains are two places where an implementer would have to guess, and where
guessing wrong produces a wrong result rather than a stylistic wobble.

The first is a contradiction inside the scenario list. Scenario A says "on `main`, with a clean
tree, the harness must refuse — this run proves nothing." Scenario G says "run it with the
worktree given as `.` and the candidate hook must actually execute," and Scenario H then files G
under "reports" rather than "refuses". But G names no base, so it inherits the default `main` —
which is exactly Scenario A's situation. Run literally against the fixed harness, G refuses, so
G and H both fail while A passes. Task 7 asks the implementer to verify A–H by execution; they
will hit a refusal on G and have no way to tell whether that is the right answer or a bug.

The second is the phrase "the three citing documents." It is never enumerated. Four committed
documents cite the `378` figure, and part 6 explicitly forbids editing one of them (ADR 0015).
So an implementer either edits a file the spec forbids, or silently substitutes a fourth file the
spec never mentions in that context. Naming the files closes it in one line.

### What I verified independently (the reversal the caller flagged as load-bearing)

**The reversal is correct.** Revision 1's proposed retraction would have been the false statement.

- `git-guard-empty-index.md:311-318` re-read: `378` appears as the matrix *size* ("63 commands ×
  6 states = 378 pairs"), and the results table reports **215 / 326 / 346 identical** with
  **162 / 52 / 32 pairs allowed where `main` blocks**. A program compared with itself cannot
  produce a single relaxation. That run was genuinely differential.
- Timestamps re-measured: `64ba2fa` = **2026-08-04 15:45:33 -0400**; `cc035d2` (the PR #38 merge)
  = **16:53:55 -0400**, 68 minutes later. `main`'s first-parent history confirms `bc7da76`
  (12:48:36) was the tip at recording time, and `git show bc7da76:hooks/lib/shell_segments.py`
  contains **zero** occurrences of `redirect` against **11** at `c461e4c` — so the base genuinely
  predated the fix and the comparison was real.

### Measurements I re-ran (probe in `/tmp`, repo file untouched)

| base | spec claims | I measured | verdict |
|---|---|---|---|
| `bc7da76` | 378 / 0 / 0, exit 0 | **378 / 0 / 0, exit 0** | exact |
| `b17a666` | 358 / 20 / 0 | **358 / 20 / 0** | exact |
| `286fd5a` | 118 / 260 / 0, exit 0 | **118 / 260 / 0, exit 0**, three `fatal:` lines on stderr | exact |

Blob identities all confirmed: `bc7da76` and `c461e4c` share `git-guard.sh` `2b74507c` and
`classify-git-command.py` `2f8af693`, differing only in `shell_segments.py`; `f5c5689`'s three
blobs are byte-identical to `c461e4c`'s (Scenario B's premise holds); `b17a666` differs in all
three; `e3b09ba` has `git-guard.sh` present with both libs absent; `286fd5a` has all three
absent. Toolchain re-read off this host: bash `3.2.57(1)-release`, git `2.50.1 (Apple Git-155)`,
python3 `3.9.6`, jq `jq-1.7.1-apple`, shasum `6.02`, `cmp` rejects `--version` and accepts `-s`.
Route 3 mechanism confirmed directly: `bash ./hooks/git-guard.sh` from a foreign cwd exits
**127**, and `replay.sh:125-131` tallies any pair that is not `2→0` or `0→2` as `same`.

### Round-1 violations — all four closed

| id | status | evidence |
|---|---|---|
| `writing-specs/scenario-b-stricter-claim` | **fixed** | Scenario D now asserts 378 / 0 / 0; I reproduced exactly that. |
| `core-conduct/explicit-error-handling` | **fixed** | Part 2 requires each base extraction to succeed *and* be non-empty; Scenarios E and F pin it. The 0-byte route is real — `286fd5a` gives a clean `0 relaxed`, exit 0. |
| `writing-specs/pinned-versions` | **fixed** | Pinned-toolchain block matches this host on every line; BSD `cmp -s` correctly identified and GNU spellings forbidden. |
| `writing-specs/ambiguity` | **fixed** | Part 3 states the candidate side is read from disk, with the `NEW="$WT/hooks/git-guard.sh"` justification. |

### Violations

| # | id | rule source | where | why |
|---|---|---|---|---|
| 1 | `writing-specs/scenario-g-vacuity-conflict` | `skills/writing-specs/SKILL.md:19-20,28` | Scenarios, G (L210-214) and H (L216-218), against A (L171-176) | Scenario G names no base so it inherits the default `main`, which on a clean worktree is exactly Scenario A's vacuous case — the part-3 refusal fires before the candidate hook runs, so G's "the candidate hook is actually executed" and H's classification of G as "report" cannot both hold with A. |
| 2 | `writing-specs/citing-documents-ambiguity` | `skills/writing-specs/SKILL.md:24,28` | The fix, part 6 (L136-139) and Task 9 (L239) | "The three citing documents" is never enumerated: four committed files cite the figure (`git-guard-empty-index.md:311`, `shell-segments-redirects.md:118,140`, `0015-redirections-are-part-of-a-command.md:110`, `falsifier-base-pin.md:145`) and part 6 forbids editing ADR 0015, so the implementer must either edit a forbidden file or substitute one the spec never names. |

### Notes (non-blocking)

- **Spec path remains correct for this repo.** `writing-specs:54` defers to
  `docs/superpowers/specs/`, but the repo layer (`rules/gates.md`, one-canonical-file discipline)
  mandates `docs/features/<name>.md` for feature-scale work and takes precedence. Unchanged from
  round 1; not a violation.
- **Part 2 says "Validate every extraction" but then "each of the three `git show` calls" — the
  file has six** (`replay.sh:13-15` base, `20-22` candidate). Not cited, for two reasons: the
  heading resolves toward all six, and a failed *candidate* extraction produces an empty script
  that exits 0 for every command, which turns every `a=2` pair into a **relaxed** row — a loud
  false alarm, not the silent false pass this spec exists to close. Worth one clarifying clause
  anyway, since the same unchecked pattern is what the spec is fixing three lines above.
- **Scenario G also does not state the working directory.** `git -C "$WT" show` with `WT="."`
  only resolves when the harness is invoked from the repo root; naming the cwd alongside the base
  would make G reproducible without inference.
- **Scenarios F, G and H omit `Given`.** Defensible under `writing-specs:43` (redundant
  Given/When/Then blocks are the named token offender) — the state is either irrelevant or
  carried by the `When`. H is a meta-assertion over the set rather than a scenario; its intent is
  clear and it does real work as an anti-hardwiring check.
- **No Mermaid diagram.** `writing-specs:26` asks for visual aids; for a ~30-line shell change
  whose control flow is fully carried by prose, omitting it reads as KISS rather than a gap.
- **Security skill read and found out of territory.** `BASE_REV` is a local developer-supplied
  rev interpolated into a quoted `git show`; no external input, no secrets, no data store, no
  model call. Nothing in `writing-secure-code` binds here.
- **The non-goals hold.** No test sibling exists for either harness in `hooks/`
  (`git-guard.replay.sh`, `shell-segments-falsifier.sh`), so declining to invent one is
  unearned-scope avoidance, not a testing-rule miss. The sibling falsifier does print `base=$BASE`
  on every run (`shell-segments-falsifier.sh:100`), so the parity claim in part 5 is accurate.
- **The ADR-amendment convention checks out:** `0011:4-6` and `0013:5` both amend by writing a new
  ADR and leave the amended one unedited, and `0009:105-107` states the same for a locked spec.
  Routing the provenance note into ADR 0016 rather than editing 0015 is the house pattern.

### Waiver record

None. No violation ids were waived by the user for round 2, and no round-1 violation recurred, so
nothing carries a persistence flag into round 3.

---

## Round 3 — 2026-08-05 — **FAIL** (1 violation, new; both round-2 violations fixed)

**Repo:** `.claude` · **branch:** `main` · **head:** `c461e4cd2dfb493a0b0e5d92e10ade7b98c99416`
**Spec blob:** `27798f3cb0500b9bb75158965c55a14cab01fc3b` · **Confidence:** high
**Waived coming in:** none.

### In layman's terms

Revision 3 closes both round-2 findings cleanly, and I confirmed them by running the matrix again
rather than reading the diff. Scenario G is now pinned to a base that actually differs, and I
measured both halves of its claim: with an absolute worktree path the run gives **358 / 20 / 0**
(matching Scenario C exactly, as G now asserts), and with the path given as `.` the same run gives
**378 / 0 / 0** — the candidate silently never executing, exactly as G's comment says. The citation
table is right on all five rows; I opened each file at each line number. The toolchain block matches
this host on every line, including that BSD `cmp` rejects `--version` and accepts `-s`.

One thing still blocks, and it is one clause of writing.

**The spec never says what "the resolved base" means.** Part 5 is the fix for route 5 — "a figure
copied into a document carries no record of what produced it" — and it is described as the part that
makes the harness auditable without archaeology. It tells the implementer to print "the resolved
base". It never says that means the commit SHA. Worse, it points at a model to copy: the sibling
falsifier, which prints `base=$BASE` — the rev string exactly as typed. Copy that behaviour into
replay, whose default base stays `main`, and the harness's most common invocation (a feature branch
against `main`) prints `base=main`. Which `main`? Nothing says. That is route 5, still open, and
every scenario in the spec still passes, because no scenario ever runs the default base and checks
what the output actually names. Adding "the 40-character SHA `git rev-parse` resolves it to" closes
it in one clause.

**Is it genuinely blocking?** Yes in the sense that the wrong reading silently defeats one of the six
fix parts and no test in the spec catches it; no in the sense that it is a wording fix, not a design
change — nothing else in the spec moves. A reviewer who reads part 5 aloud and decides "resolved
obviously means the SHA" is not wrong; the spec just does not say it, and the model it names does
the other thing.

### What I re-measured (nothing taken on trust)

| Claim | Method | Result |
|---|---|---|
| Scenario C: `b17a666` → 358 / 20 / 0 | full 378-pair matrix, probe in `/tmp`, absolute `WT` | ✅ **358 identical, 20 stricter, 0 relaxed** |
| Scenario G "today reports 378 identical" | same probe, `WT="."`, base `b17a666` | ✅ **378 / 0 / 0** — candidate never ran |
| Scenario G post-fix = Scenario C | the two rows above are the same run modulo path resolution | ✅ assertion follows from measurement |
| `grep -cE 'BASE_REV\|getopts\|\$\{3'` → 0 | re-ran | ✅ `0` |
| Line refs 6, 7, 13-15, 20-22, 35, 125-131, 134 | read source | ✅ all eight correct; 134 is the `printf ... main BLOCKS` header, 125-131 the if/elif/else tally |
| Scenario B premise: `f5c5689` blobs = HEAD's | `git rev-parse <rev>:<path>` ×3 | ✅ `2b74507c` / `2f8af693` / `b8fed461`, all identical |
| `bc7da76` vs `c461e4c`: only `shell_segments.py` moved | same | ✅ `7197eb08` → `b8fed461`, other two unchanged |
| `b17a666` all three differ; `e3b09ba` libs absent; `286fd5a` all three absent | same | ✅ all three as stated |
| Worktree clean for the three files | `git hash-object` vs `git rev-parse HEAD:` | ✅ disk == HEAD, so B's and C's premises hold today |
| Pinned toolchain | read off this host | ✅ bash `3.2.57(1)-release`, git `2.50.1 (Apple Git-155)`, python3 `3.9.6`, jq `jq-1.7.1-apple`, shasum `6.02`; `cmp --version` rejected, `cmp -s` accepted |
| Five citation sites | opened each file at each cited line | ✅ `git-guard-empty-index.md:311` + table `:314-318` (215/326/346 identical, 162/52/32 relaxed); `shell-segments-redirects.md:118`, `:140`; `falsifier-base-pin.md:145`; `0015:110` |
| ADR 0016 is the next free number | `ls docs/decisions/` | ✅ 0015 is the tip |
| Sibling prints its base | `shell-segments-falsifier.sh:100` | ⚠️ `echo "base=$BASE"` — the **literal rev string**, and its default is a pinned SHA (`:25`), not a branch |

### Round-2 violations — both closed

| id | status | evidence |
|---|---|---|
| `writing-specs/scenario-g-vacuity-conflict` | **fixed** | G now names `b17a666`, asserts 358 / 20 / 0, and carries a comment stating why the base must be non-vacuous. I measured both the asserted value and the "today" value it contrasts against. |
| `writing-specs/citing-documents-ambiguity` | **fixed** | Part 6 carries a five-row table naming file, site and base; row 5 marks ADR 0015 **NOT edited**. Every line number checked against the file. Task 9 says "the four sites", consistent with the table. |

The uncited round-2 note is also acted on: part 2 now covers **all six** `git show` calls
(`replay.sh:13-15` base, `20-22` candidate) and states the opposite failure directions.

### Violations

| # | id | rule source | where | why |
|---|---|---|---|---|
| 1 | `writing-specs/resolved-base-format` | `skills/writing-specs/SKILL.md:28` | The fix, part 5 (L130-134); Scenario A (L190); Error and refusal contract (L244); Task 6 (L255) | "The resolved base" is never defined as the commit SHA the rev resolves to, and the model part 5 names for parity (`shell-segments-falsifier.sh:100`) prints the literal rev string — so with the retained `main` default the harness's primary branch-vs-`main` invocation prints `base=main`, reproducing route 5's archaeology problem while satisfying every scenario, none of which asserts the output of a default-base run. |

### Notes (non-blocking)

- **The `else → same` tally still swallows every non-`{0,2}` exit.** The spec names this mechanism
  itself (L63-64: `a=2,b=127` "falls to the `else` branch and is tallied `same`") but part 4 closes
  only the relative-path *cause*, not the swallow. Measured directly: a worktree candidate whose
  `hooks/lib/*.py` are absent exits **2** for every command (fail-closed), which yields roughly
  118 stricter / 260 identical / **0 relaxed**, exit 0 — a false pass on the load-bearing metric,
  dressed as legitimate hardening. **Deliberately not cited:** the tally is pre-existing code the
  spec does not modify, and `core-conduct.md:21` ("fix the root cause, and only the root cause — a
  drive-by cleanup is its own task") supports the author's scope decision, which the non-goals
  already use for `git-guard.sh` itself. Flagged because part 6's ADR text ("must prove **each side
  actually loaded**") promises a rule that parts 1-5 enforce only for the causes measured.
- **Part 6 prose over-quantifies by one.** "Five citation sites exist across four files... Each gets
  a one-line provenance note" sits directly above a table whose fifth row reads **NOT edited**, and
  above a paragraph restating that. Task 9 says "the four sites". Resolved by everything around it;
  a wording wrinkle, not the round-2 defect returning.
- **The harness exits 0 even when `relaxed > 0`** (measured table row 4: 62 relaxed, exit 0). Not
  listed in the non-goals, so an implementer may read it as in scope. One line either way would
  settle it.
- **Scenario G still does not state the working directory.** `git -C "." show` only resolves from the
  repo root. L70 supplies the invocation (`bash hooks/git-guard.replay.sh .`), so the context is in
  the document; unchanged from round 2 and still non-blocking.
- **Spec path remains correct for this repo.** `writing-specs:54` defers to `docs/superpowers/specs/`,
  but `rules/gates.md` one-canonical-file discipline mandates `docs/features/<name>.md` and the repo
  layer takes precedence. Unchanged from rounds 1-2.
- **No Mermaid diagram.** `writing-specs:26` asks for visual aids; for a ~40-line shell change carried
  fully by prose this reads as KISS. Unchanged from rounds 1-2.
- **Security skill read, still out of territory.** `BASE_REV` and `WT` are local developer-supplied
  values passed as quoted argv to `git`, never through `eval`; no external input, secrets, data store
  or model call. Part 4's directory validation is the boundary check `core-conduct.md:13` asks for.

### Waiver record

None. No violation ids were waived by the user for round 3. No round-1 or round-2 violation
recurred, so nothing carries a persistence flag; the single finding is new this round.

---

## Round 4 — 2026-08-05 · revision 4 (post-escalation) · **FAIL** (1 violation, copy-edit grade)

`repo=.claude` · `branch=main` · `head_sha=a25f72a551e514c6c4d90fb382e1e20e35da0e10` ·
`spec_blob_sha=2873a88dbc36ceb40ccd4b69d07c4b670b79860f` · confidence **high** (everything below
re-measured on this host, not carried over from round 3).

### Layman summary

The design is sound and I would build from it. Round 3's finding is genuinely closed: part 5 now
says "resolved base" means the 40-character SHA from `git rev-parse "$BASE_REV^{commit}"`, warns
against copying the sibling falsifier's literal-`$BASE` format and says why, and Scenario A pins
the assertion on the one run — the default-base run — that no other scenario can check. Verified
the sibling's format claim at `hooks/shell-segments-falsifier.sh:100` (`echo "base=$BASE ..."`);
the spec's description of it is accurate.

The uncited round-3 note was also acted on, and the ADR text was correctly weakened rather than
left over-claiming. But the sentence written to replace it states the wrong cause. It says the
`else → same` tally "counts any exit code outside `{0,2}` as agreement, **which is the shared
mechanism behind** route 3 and at least one further route: a candidate missing `hooks/lib/*.py`".
I re-measured that candidate today: it exits **2** on every command — *inside* `{0,2}`, so the
`else` branch is not what produces it. What produces it is the definition of `relaxed` itself
(`base=2 && candidate=0`): a candidate that blocks everything can never register a relaxation, so
`0 relaxed` is guaranteed regardless of the tally. Fixing the tally would not close that route.

Why it matters rather than being pedantry: lines 152-157 direct this exact sentence into ADR 0016,
which this repo treats as permanent and amends only by writing a new ADR — and rounds 1-3 of this
spec existed precisely to stop a wrong statement becoming permanent. It also mis-scopes the queued
follow-up: an engineer who fixes "the `else → same` tally" would reasonably believe the
missing-libs route closed with it. It does not.

**Blocking or a note?** It does not block tasks 1-8 — every buildable part of this spec is correct,
measured, and testable, and I reproduced its premises at today's HEAD. It blocks **task 9 as
written**, and the remedy is one sentence, not a redesign. This is copy-edit grade.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/spec-code-accuracy` | `skills/writing-specs/SKILL.md:14` | "Drift causes hallucination: when the spec and the code fall out of sync, the agent starts describing and extending behavior that no longer exists. Keeping them aligned is not tidiness; it is correctness." | Deliberate non-goals, the `else → same` bullet (spec:196-200), which part 6 (spec:152-157) routes into permanent ADR 0016 | The bullet attributes the measured missing-`hooks/lib/*.py` false pass to the "exit code outside `{0,2}`" branch, but that candidate exits **2** on every command (re-measured today, `git-guard.sh:44,56` fail-closed) — the route is caused by `relaxed` being defined as `base=2 && candidate=0`, so fixing the tally would not close it, and the spec directs the wrong cause into an immutable ADR. |

Suggested one-sentence replacement (evaluation only — not applied):

> It counts any exit code outside `{0,2}` as agreement — the mechanism behind route 3. A *second*
> and distinct limit shares this non-goal: `relaxed` is defined as (base blocks, candidate allows),
> so a candidate that blocks everything — e.g. one missing `hooks/lib/*.py`, which fails closed with
> exit 2 on every command — can never register a relaxation and reports `0 relaxed` alongside a
> large `stricter` count (measured, round-3 compliance judge). Fixing the tally would not close it;
> both are queued separately.

### Round-3 violation: closed

`writing-specs/resolved-base-format` — closed. Part 5 (spec:135-143) defines the resolved base as
the 40-char SHA from `git rev-parse "$BASE_REV^{commit}"`, permits the rev string only as a
companion, and names the falsifier's format as the trap to avoid with its reason. Scenario A
(spec:214, 218-219) asserts the SHA on the default-base run. No round-1 or round-2 id recurred.

### What I re-measured (not inherited)

- Three files at `HEAD` (`a25f72a`) are byte-identical to `c461e4c`: `2b74507c…`, `b8fed461…`,
  `2f8af693…` — so every count in the measured table and Scenarios C/D/G is still reproducible today.
- `f5c5689`'s three blobs match HEAD's exactly → Scenario B's "verified" premise holds.
- `b17a666` differs in all three blobs → Scenario C and the round-3 fix to Scenario G hold.
- Toolchain pins all exact on this host: bash `3.2.57(1)-release`, git `2.50.1 (Apple Git-155)`,
  python3 `3.9.6`, jq `jq-1.7.1-apple`, shasum `6.02`, `cmp` BSD (rejects `--version`).
- Line references check out: base extraction at `:13-15`, candidate at `:20-22`, `jq` at `:35`,
  tally at `:125-131`, literal-`main` header at `:134`; `grep -cE 'BASE_REV|getopts|\$\{3'` → `0`.
- Candidate with `hooks/lib/` absent: exit **2** on `git status`, `git push --force`,
  `git commit -m x`, with `git-guard: cannot run …/lib/classify-git-command.py; failing closed.`

### Notes (non-blocking — carry into the branch)

- **The harness exits 0 unconditionally.** It is 137 lines and ends on a `printf`; there is no
  exit-code logic, which is why the measured table shows row 4 at **62 relaxed, exit 0**. So the
  "exit 0" in the non-goal sentence carries no signal at all. After parts 2-4 land, a refusal will
  exit non-zero while a run that finds 62 relaxations still exits 0. Consider queueing "exit
  non-zero when `relaxed > 0`" beside the tally item. Repeated from round 3, still uncited: out of
  the spec's stated scope, and `core-conduct.md:21` supports the author's scope discipline.
- **Refusal contract vs. Scenario A wording.** The contract (spec:269-272) requires a refusal to
  name "which rev it concerned"; Scenario A additionally requires a 40-character SHA on the refusal
  path. Compatible, and Scenario A governs — but an implementer reading only the contract could
  satisfy its letter with `base main` and fail Scenario A. "the resolved base SHA" would close it.
- **Ordering is derivable, not stated.** Scenario A requires the resolved SHA in refusal output, so
  rev-parse must run before the part-3 vacuity check. Testable via Scenario A; no citation.
- **`git rev-parse` failure path.** Part 5 introduces a new command without stating its error
  handling, but Scenario F pins the outcome (named error, non-zero) and part 2's `git show`
  validation catches the same input independently, so no boundary is left unspecified.
- **Spec path, Mermaid, security skill** — unchanged from rounds 1-3: `docs/features/` wins on repo
  precedence; no diagram is KISS for a ~40-line shell change; `writing-secure-code` read again and
  still out of territory (`BASE_REV`/`WT` are local values passed as quoted argv to `git`, no
  `eval`, no external input, secrets, data store, or model call).

### Waiver record

None. The user chose to fix rather than waive after the round-3 escalation; no violation id has
been waived on this spec in any round. The single round-4 finding is new — no prior id recurred, so
nothing carries a persistence flag.

---

## Round 5 — 2026-08-05 · revision 4 + round-4 fix (`9774fd6`) · **FAIL** (2 violations)

`repo=.claude` · `branch=main` · `head_sha=ea088b55d5871ef1632911cc44a342ee68752aac` ·
`spec_blob_sha=30c8c3ec70b772b2ba30ddda37e0038f0fe9b59a` · confidence **high** (every figure,
SHA, blob hash, timestamp and line reference below was re-run on this host this round; the replay
harness itself was executed once, end to end).

### Layman summary

The spec is in good shape and the round-4 fix did what it set out to do: the two comparison-logic
limits are now correctly separated, and the "resolved base" is unambiguously the 40-character SHA.
Two things are still wrong, both small, both introduced by the last edit.

First, the sentence explaining *why* a broken candidate can never register a relaxation points at
the wrong line of code. It says `git-guard.sh:56` fails closed "when it cannot resolve its
classifier". Line 56 is a different guard — it is the one that fires when **python3 is missing from
the PATH**. The classifier guard is at lines 74-77. The *behaviour* the spec describes is real (I
reproduced it: a copy of the guard with `hooks/lib/` absent exits 2 on `ls -la`, `git commit -m msg`
and `git push` alike, printing `git-guard: cannot run …/lib/classify-git-command.py; failing
closed.`) — only the pointer is wrong. That matters here more than usual, because this exact
sentence is the one part 6 routes verbatim into permanent ADR 0016, and because it is the third
consecutive revision in which this one bullet has been subtly wrong.

Second, the refusal contract and Scenario F now contradict each other. Round 4 tightened the
contract to say every refusal and every named error must state "**the resolved base SHA** it
concerned (not the rev string)". But Scenario F is the case where the rev *cannot be resolved at
all* — base `0000000` — so there is no SHA in existence to print, and the scenario itself demands
the output "names the unreadable base", which can only be the string as typed. An implementer has
to break one of the two. The fix is one clause: exempt the unresolvable-rev case, e.g. "…the
resolved base SHA it concerned — or, where the rev could not be resolved at all, the rev string as
typed, which is then the only identifier that exists."

Everything else I checked held up exactly, including several claims that would have been easy to get
wrong (see *What I re-measured*).

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/spec-code-accuracy` | `skills/writing-specs/SKILL.md:14` | "Drift causes hallucination: when the spec and the code fall out of sync, the agent starts describing and extending behavior that no longer exists. Keeping them aligned is not tidiness; it is correctness." | Deliberate non-goals, limit 2 of the comparison-logic bullet (spec:202-206), routed verbatim into permanent ADR 0016 by part 6 (spec:145-157) | The bullet cites `git-guard.sh:56` as the branch that "fails closed when it cannot resolve its classifier", but line 56 is the **python3-not-on-PATH** guard; the classifier guard is `if ! facts=…` at `:74` with its `exit 2` at `:77` (`CLASSIFIER` is set at `:44`) — identical at `c461e4c`, so a reader verifying the distinction between limit 1 and limit 2 lands on an unrelated branch and re-opens the argument rounds 3 and 4 already spent. **Recurrence: same id as round 4, same bullet.** |
| `writing-specs/refusal-contract-vs-scenario-f` | `skills/writing-specs/SKILL.md:20` | "Ambiguity surfaces early: a requirement you cannot phrase as Given/When/Then is usually a requirement you have not actually decided yet." (with `:28` — enumerate the edge cases explicitly) | "Error and refusal contract" (spec:283-287) against Scenario F (spec:262-265) | The contract binds **every** named error to print "the resolved base SHA it concerned (**not** the rev string)", but Scenario F's error is precisely the case where `git rev-parse "$BASE_REV^{commit}"` cannot produce a SHA and the scenario requires the output to name the unreadable base — the typed string; as written the two cannot both be satisfied, so the implementer must guess which one governs. |

Suggested replacements (evaluation only — not applied):

> …because `git-guard.sh` fails closed at `:74-77` when it cannot run its classifier (resolved at
> `:44`) — distinct from the python3-absent guard at `:53-57`.

> …and state in one plain sentence what was wrong, **the resolved base SHA** it concerned — or,
> where the rev could not be resolved to a commit at all (Scenario F), the rev string as typed,
> which is then the only identifier that exists — and the corrected invocation.

### Round-4 violation: partially closed

`writing-specs/spec-code-accuracy` — the *cause* is now right. Limit 2 is correctly stated as
`relaxed` requiring `base=2 && candidate=0` (harness `:125`, verified), and the "exit 2 is inside
`{0,2}`, so limit 2 is not an instance of limit 1" note is sound. Only the code pointer inside that
same sentence is wrong, which is why the id is reused rather than retired. No round-1, round-2 or
round-3 id recurred.

### What I re-measured (nothing inherited)

- **Ran the harness itself**, `bash hooks/git-guard.replay.sh /Users/marksuyat/.claude` (absolute
  path, per the caller's warning): `378 pairs: 378 identical, 0 stricter, 0 relaxed`, exit **0**,
  header printing the literal `main`. Row 1 of the spec's table reproduces exactly, and routes 1
  and 5 are confirmed live at `ea088b5`.
- **Blob table** — `git-guard.sh` / `classify-git-command.py` / `shell_segments.py`:
  `HEAD` = `c461e4c` = `f5c5689` = `2b74507c` / `2f8af693` / `b8fed461`; `bc7da76` shares the first
  two and differs only in `shell_segments.py` (`7197eb08`) — exactly the two short hashes the spec
  names at `:121`; `b17a666` differs in all three; `e3b09ba` has a different guard (`e8082d3c`, 112
  lines, **zero** references to either lib → "self-contained" confirmed) with both libs absent;
  `286fd5a` has all three absent. Every row of the measured table and Scenarios B/C/D/G hold.
- **Timestamps**: `64ba2fa` = 2026-08-04 15:45:33, `cc035d2` (PR #38 merge) = 16:53:55 → the
  spec's "68 minutes later" is exact.
- **All five citation sites**: `git-guard-empty-index.md:311` (378 *pairs* — the matrix size) and
  its table at `:314-318` (215/326/346 identical, 162/52/32 allowed-where-main-blocks — matches the
  spec verbatim); `shell-segments-redirects.md:118` and `:140`; `falsifier-base-pin.md:145` (states
  the tautology, as the spec says); ADR `0015:110`. The "annotation, not retraction" correction is
  therefore correct on the evidence.
- **ADR amend-by-new-ADR convention** verified at `0009:105`, `0011:4-6`, `0013:5`.
- **`hooks/shell-segments-falsifier.sh:100`** prints `base=$BASE` with a pinned default of
  `bc7da76` — the spec's "do not copy the sibling's format" note is accurate.
- **Toolchain pins** all exact on this host: bash `3.2.57(1)-release`, git `2.50.1 (Apple Git-155)`,
  python3 `3.9.6`, `jq-1.7.1-apple`, shasum `6.02`, `cmp` BSD (rejects `--version`).
- **Harness line references**: `WT` `:6`, `UNDER_TEST` `:7`, base extraction `:13-15`, candidate
  extraction `:20-22`, jq `:35`, `cd "$REPO"` in `run()` `:36`, tally `:125-131` with `relaxed`
  defined at `:125`, literal-`main` header `:134`; `grep -cE 'BASE_REV|getopts|\$\{3'` → `0`.
- **Missing-libs candidate**: exits **2** on `ls -la`, `git commit -m msg`, `git push` — mechanism
  confirmed, line citation not (see violation 1).

### Notes (non-blocking — carry into the branch)

- **Scenario B's premise is stated against the wrong side.** It says `f5c5689`'s blobs are
  "identical to HEAD's", but part 3 mandates comparing the **on-disk** candidate bytes. They
  coincide today (`git status` clean, verified), so the scenario is executable as written; phrasing
  the Given against the worktree would make it robust to a dirty tree.
- **Part 2 vs. the contract.** Part 2 (spec:100-103) says a failed extraction should "name the rev
  and the path that could not be read", while the contract forbids the rev string. Fixing violation
  2 should align both sentences in the same edit.
- **Scenarios F and H omit `Given`/`When`.** Acceptable shorthand and both are testable; noted only
  because `writing-specs:19` asks for full State → Action → Outcome.
- **`shasum: 6.02` is pinned but unused** — the plan's only comparator is `cmp -s`. Harmless as a
  host record; drop it if the pin block is meant to be the *used* toolchain.
- **The harness exits 0 unconditionally** — repeated from rounds 3 and 4, still uncited: the spec
  now states this explicitly as a queued non-goal (spec:214-217), which is the correct disposition.
- **Spec path, Mermaid, security skill** — unchanged from rounds 1-4: `docs/features/` wins on repo
  precedence over `writing-specs:54`; no diagram is KISS for a ~40-line shell change;
  `writing-secure-code` read again and still out of territory (`BASE_REV`/`WT` are local values
  passed as quoted argv to `git`, no `eval`, no external input, secrets, data store, or model call).

### Waiver record

None. No violation id has been waived on this spec in any round. **Persistence flag:**
`writing-specs/spec-code-accuracy` now recurs across rounds 4 → 5 (same bullet, same rule, different
error each time) — the first recurrence on this spec, and grounds for escalating that single bullet
to the user rather than looping again.

---

## Round 6 — 2026-08-05

`spec_blob_sha` `52c605fe92d9b1a91207069bd5ad35756d835845` · repo `.claude` · branch `main` ·
HEAD `e6bdc21ee75215476aac7cdd5c7fc747c704b3dd` · **verdict: fail** (3 violations) · confidence high

### In plain English

Revision 6's three edits were checked line by line, and two of the three landed cleanly. The
classifier pointer is now correct — `git-guard.sh:74-77` really is the fail-closed branch, `:44`
really is where `CLASSIFIER` is resolved, and `:53-57` really is the separate python3 guard whose
`exit 2` sits at `:56`. **The caller's audit is independently confirmed:** all 13 code pointers in
the spec and all five citation-site pointers resolve correctly at HEAD. And every number in the
"What was measured" table was re-run from scratch on this host today — all six rows reproduce to
the digit, as do the 0-byte-base, exit-127-candidate and exit-0 mechanisms behind them. This spec's
measurements are honest.

What is still wrong is smaller but real, and one piece of it was created by revision 6's own fix.

Making the two `lib/*.py` helpers *optional* (so the `e3b09ba` baseline stays runnable) quietly
punched a hole in the vacuity refusal. Part 3 still says "compare the three files… if all three
match, refuse", but a self-contained baseline only *has* one file. With the spec's own mandated
tool, `cmp -s` on two absent files returns 2 — an error, not a match — so "all three match" is
false and the run proceeds. Measured: `base=e3b09ba, candidate=e3b09ba` — a program compared with
itself — reports **378 identical, 0 relaxed, exit 0**. That is route 1, the exact defect this spec
exists to close, still open in the configuration part 2 was just widened to admit.

Second, the refusal contract's "print the resolved SHA, not the rev string" clause was reconciled
with Scenario F but not with the two other places that say "name the rev" — part 2's failure clause
and Scenario E. Round 5 flagged this and said to align both sentences in the same edit; only one
half was done, so the same clause is unreconciled for a second round running.

Third, the pinned-toolchain block advertises "Measured on this host, not recalled", but three of its
four tool-capability claims are false on this host: `cmp --quiet`, `diff -q --no-dereference` and
`readlink -f` all work here. The *directive* (use `cmp -s` and `cd … && pwd -P`) is still the right
portable choice — it is the stated justification that was recalled rather than measured, in the one
section that claims otherwise, in a spec whose whole thesis is that an unprovenanced number cannot
be trusted.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/vacuity-check-vs-optional-helpers` | `skills/writing-specs/SKILL.md` | No requirement readable two ways; enumerate good, bad and edge cases | "The fix", parts 2 and 3 (spec:100-137) + Scenarios | Part 2 now permits a side whose `lib/*.py` helpers are legitimately absent, but part 3 still says "compare the three files… if **all three** match" and never states how absent-vs-absent compares — under the spec's own `cmp -s` that is exit 2 (not a match), so a byte-identical self-contained pair escapes the refusal. |
| 2 | `writing-specs/refusal-contract-vs-scenario-f` | `skills/writing-specs/SKILL.md` | No requirement readable two ways | "Error and refusal contract" (spec:298-309) vs part 2 (spec:104) and Scenario E (spec:272) | The contract demands the resolved 40-char SHA and forbids the rev string for every named error after a successful `rev-parse`, yet part 2's failure clause and Scenario E both say only "name the rev" — satisfiable by printing `286fd5a`, which the contract rejects. |
| 3 | `writing-specs/toolchain-claims-unmeasured` | `skills/writing-specs/SKILL.md` | Pin exact versions — verify what the agent proposes rather than what it remembers | "Pinned toolchain" (spec:187-201) | The section states "Measured on this host, not recalled", but `cmp --quiet` (exit 1, silent), `diff -q --no-dereference` (exit 1) and `readlink -f` (`/private/tmp`) all work on this host, so the YAML comment `NO --quiet` and the "GNU-only spellings" label are false. |

**Recurrence:** violation 2 reuses round 5's id. Round 5 raised the same clause as a note with an
explicit "align both sentences in the same edit" recommendation; revision 6 fixed the Scenario F
half only. Second consecutive round on this clause — escalation grounds under the two-round rule.

**Cleared this round:** `writing-specs/spec-code-accuracy` (rounds 4-5) is **closed**. The limit-2
bullet's pointers are correct at HEAD, verified against `hooks/git-guard.sh` directly.

### Evidence re-executed (not taken from the spec)

| claim | spec says | measured today |
|---|---|---|
| base `main` (default), abs WT | 378 / 0 / 0 | 378 / 0 / 0 ✅ |
| base `bc7da76` | 378 / 0 / 0 | 378 / 0 / 0 ✅ |
| base `b17a666` | 358 / 20 / 0 | 358 / 20 / 0 ✅ |
| base `e3b09ba` | 234 / 82 / 62 | 234 / 82 / 62 ✅ |
| base `286fd5a` | 118 / 260 / 0 | 118 / 260 / 0 ✅ |
| `WT` given as `.` | 378 / 0 / 0 | 378 / 0 / 0 ✅ |
| failed `git show` → 0-byte base | 0 bytes, `bash` exits 0 | exit 128, 0 bytes; `bash <empty>` → 0 ✅ |
| relative-path candidate | exits 127, tallied `same` | 127 ✅ (`else` arm at :129-131) |
| harness exit on degenerate row | 0 | 0 ✅ |
| `e3b09ba` guard `lib/` refs | 0 | 0 ✅ |
| `bc7da76`↔`c461e4c` shared blobs | `2b74507c`, `2f8af693` | exact ✅ |
| `f5c5689` blobs = HEAD's | identical | identical ✅ |
| `64ba2fa` → `cc035d2` | 68 min | 68.37 min ✅ |
| matrix size | 63 × 6 = 378 | 63 commands, 6 states ✅ |
| pinned versions | bash 3.2.57(1), git 2.50.1, py 3.9.6, jq 1.7.1-apple, shasum 6.02 | all exact ✅ |
| "neither harness has a test sibling" | true | true ✅ |

**New, reachable failure demonstrated:** `probe.sh <abs-wt> e3b09ba e3b09ba` → `378 identical, 0
stricter, 0 relaxed`, exit 0 — both sides self-contained, byte-identical, not refused.

### Notes (non-blocking)

- Scenario E's `Then` also omits the "corrected invocation" the contract requires; the contract
  governs, but the scenario is a subset of it.
- Part 2 does not state *how* "references `lib/`" is determined. The spec's own evidence uses an
  occurrence count of the string `lib/`; a builder will infer a grep, which is probably right.
- Scenario H still omits `Given`/`When` (`writing-specs:19`), unchanged from rounds 1-5 and still
  acceptable as a deliberate cross-cutting assertion.
- `## Verification — <Appended during review.>` is the only occurrence of that marker in
  `docs/features/`. Not cited: it is a records section that task 7 fully specifies, not an
  undecided requirement.
- `hooks/shell-segments-falsifier.sh:25` is `BASE="${1:-bc7da76}"` — pinned *by default*, but
  overridable, so "a pinned SHA by construction" (spec:156) holds for the default only. Does not
  weaken the spec's conclusion that replay must not copy that format.
- Spec path, Mermaid and `writing-secure-code` — unchanged from rounds 1-5. `docs/features/` wins
  on repo precedence; no diagram is KISS here; the security skill was read again and remains out of
  territory (`BASE_REV`/`WT` reach `git` as quoted argv, no `eval`, no secrets, data store or model
  call, and parts 2-4 add fail-closed boundary validation).
- The three queued comparison-logic limits and the four queued architecting recommendations were
  treated as out of scope per the dispatch and are described accurately where the spec mentions them.

### Waiver record

None. No violation id has been waived on this spec in any round.

---

## Round 7 — 2026-08-05 — verdict: PASS

Spec blob `56cc36934c6c2dc8b20763982844151fc96a0fe2` at HEAD `2d865fd` (revision 7, the
consolidation commit). Judged on `main`, waived: none.

### Layman summary

Rounds 3–6 each caught a mistake that the previous round's fix had created, so this revision
stopped patching one sentence at a time and instead hunted down *every* place the spec states its
two most-broken promises — "output must name the base by its full commit id" and "don't assume a
side always has three files" — and made them all agree at once. This round's job was to check
whether that hunt missed a spot, and whether the rewrite itself broke something new, as four
rewrites in a row had. It didn't, on both counts. Every place the two promises appear now says the
same thing; the three new test scenarios (I, J, K) are internally consistent and their numbers
reproduce exactly when re-run from scratch on this machine; the corrected toolchain claims are now
true as measured; and the deferred recommendations are recorded as decisions, not gaps. First pass
in seven rounds.

### Verification performed (all on this host, this round — not carried from prior rounds)

**Consolidation sweep — invariant 1 (base identified in output).** Every site enumerated: route-5
description (describes the defect), part 2's failure clause (resolved SHA — correct, extraction
post-`rev-parse`), part 5 + the resolved-base definition, the sibling-format warning, the
error/refusal contract with Scenario F as sole exemption, Scenarios A, E, I, J (resolved SHA), F
(rev-string, labelled unresolved). No contradicting site remains. Scenarios C/D say "naming
b17a666/bc7da76 as the base" — weaker than the contract but not contrary to it (see notes).

**Consolidation sweep — invariant 2 (file count per side).** Part 3 is now set-first-then-bytes
with absent-on-both never reaching `cmp`; part 2 splits mandatory guard from conditional helpers;
tasks 3–4 match. Remaining "all three" occurrences describe specific commits (row 5, Scenario E's
`286fd5a` — verified all three genuinely absent there) or quote superseded phrasing inside the
revision history. No live requirement assumes three files.

**Revision-7 new prose, measured:**

| claim | measured | result |
|---|---|---|
| `cmp -s` on two absent paths exits 2 | exit 2 | ✅ |
| `cmp --quiet`, `diff -q --no-dereference`, `readlink -f` all *work* here | exits 0/0/0, `/private/tmp` | ✅ (portability framing now honest) |
| Scenario I counts 234/82/62 for `e3b09ba` | probe rebuilt, full 378-pair run: 234/82/62 exact | ✅ |
| Scenario C/G counts 358/20/0 for `b17a666` | probe run: 358/20/0 exact | ✅ |
| Scenario J: no commit has guard referencing `lib/` with helpers absent | scanned **all 630** commits: 0 matches | ✅ (spec says 629 — count at measurement time, pre-revision-7 commit; property holds at 630) |
| Scenario K attribution: figure from a probe with rev-6 phrasing, not the live harness | live harness has no base param or vacuity check (`grep -cE 'BASE_REV|getopts|\$\{3'` → 0), so it *cannot* have produced the row; mechanism (`cmp -s` → 2 on absent) verified; 378 = 63×6 all-`same` self-comparison arithmetic | ✅ attribution accurate |
| Scenario B: `f5c5689` blobs identical to HEAD's | all three blob ids equal HEAD's and worktree's | ✅ |
| Scenario F: `0000000` unresolvable | `rev-parse --verify -q "0000000^{commit}"` fails | ✅ |
| blob citations `2b74507c` / `2f8af693` stable `bc7da76`→`c461e4c`, only `shell_segments` moved | exact | ✅ |
| `e3b09ba` self-contained, 0 `lib/` occurrences; `286fd5a` all three absent | exact | ✅ |
| limit-2 pointers: classifier guard `:74-77` resolving `:44`; python3 guard `:53-57` | exact | ✅ |
| guard without `lib/` exits 2 on `ls -la` | exit 2 | ✅ |
| `lib/` at HEAD: 3 matches, 2 comments (`:21`, `:29`) | exact | ✅ |
| `64ba2fa` 15:45:33 → `cc035d2` 16:53:55 = 68 min | exact | ✅ |
| five citation sites (`git-guard-empty-index.md:311,:314-318`; `shell-segments-redirects.md:118,:140`; `falsifier-base-pin.md:145`; ADR `0015:110`) | all as described, table candidates/figures exact | ✅ |
| amend-by-new-ADR at `0009:105`, `0011:4-6`, `0013:5`; next ADR is 0016 | exact; 0015 is latest | ✅ |
| falsifier prints literal `$BASE` (`:25` default `bc7da76`, `:100` `base=$BASE`) | exact | ✅ |
| toolchain pins (bash 3.2.57(1), git 2.50.1, py 3.9.6, jq 1.7.1-apple, shasum 6.02, BSD cmp no `--version`) | all exact | ✅ |
| replay.sh line refs (6, 7, 13-15, 20-22, 35, 36 `cd "$REPO"`, 125, 125-131, 134 literal `main`, unconditional exit 0, 63 commands) | all exact | ✅ |

### Violations

None. The violations table is empty for the first time on this spec.

### Notes (non-blocking)

- Scenarios C and D assert "naming `b17a666`/`bc7da76` as the base" — literally satisfiable by a
  bare abbreviated rev string, which the contract forbids. Not a conflict: the full 40-char SHA
  contains each as a prefix, so the contract-conforming output satisfies both scenarios, and
  Scenario A + the contract make the weak reading unable to pass the spec as a whole.
- Scenario J's "629 checked" is now 630 with revision 7's own commit; re-scanned at 630, still zero
  matches. Accurate as measured, still true.
- Scenario G's `.` resolves to a directory containing `hooks/git-guard.sh` only when invoked from
  the repo root — an unstated cwd assumption, unchanged since revision 3 and never load-bearing.
- Out-of-scope items honored per dispatch: the three queued comparison-logic defects and the five
  deferred architecting recommendations are described accurately where the spec mentions them
  (deferral text cross-checked; no mis-description found).

### Waiver record

None. No violation id has been waived on this spec in any round.

---

## Round 1 (new cycle — revision 8) — 2026-08-05 — **FAIL** (1 violation)

**Repo:** `.claude` · **branch:** `main` · **head:** `5bc39b917832d209ff4e2dca873d666c2fc9d402`
**Spec blob:** `5577a48e5d0de742c5aebbf2bd214549b2322626` · **Confidence:** high
**Waived coming in:** none. **Prior-round violations supplied:** none — revision 7 passed at round 7
(blob `56cc3693`), revision 8 changed the blob and re-entered the loop at round 1 by user decision.

### Layman summary

Revision 8's actual change is correct, and it closes a real hole. Revision 7 said the two sides must
have "the same paths present" without saying what makes a path count, and the two readings — files
on disk versus files the guard actually loads — both passed all eleven scenarios. Under the disk
reading a base carrying unreferenced helpers against a candidate without them looks "different",
runs the matrix, and compares a program against itself while printing a valid 40-character SHA
beside the result. Revision 8 defines membership as part 2's required set, reads it from the bytes
that will execute, and adds Scenario L as the falsifier. That is the right fix in the right shape.

I re-measured every checkable claim on this host rather than trusting any of it, because that is the
failure this spec keeps having. **Everything checked out.** All eighteen line pointers into
`git-guard.replay.sh` and `git-guard.sh` are exact. All six pinned toolchain versions are exact.
`cmp -s` on two absent paths really does exit 2; `cmp --quiet`, `diff -q --no-dereference` and
`readlink -f` really do all work here, so the "portability choice, not capability limit" framing is
honest. 63 commands x 6 states = 378. Every blob identity holds — and usefully, HEAD's three blobs
are still identical to `c461e4c`'s, so every row of the measurement table would reproduce today.
The 68-minute pre-merge window is exact to the second. All five citation-site line numbers are
exact, as are the three amend-by-new-ADR pointers, and 0016 is genuinely the next free number.

**One thing blocks it, and it is a one-character fix.** Revision 8 added Scenario L and updated
Scenario H and task 4 to match — but task 7, the verification step, still says "Verify scenarios
**A-K** by execution". The checklist an implementer actually works from omits the single scenario
revision 8 exists to add. That matters more here than it would elsewhere: once the phase gate flips
to `implementation`, editing the spec or checklist is forbidden, so an omission left in now hardens
into "Scenario L never gets verified" — and a build that skips L is byte-for-byte revision 7's
coverage, the exact state this revision was written to leave behind.

I deliberately did **not** re-cite Scenarios C/D naming their bases as abbreviated rev strings. The
round-7 judge examined that and reasoned it non-blocking (the 40-char SHA contains each as a prefix,
and Scenario A plus Scenario I make the weak reading unable to pass the spec as a whole). I reached
the same conclusion independently, and revision 8 did not touch either scenario. It stays a note.

### What was re-measured this round

| claim | measured on this host | result |
|---|---|---|
| replay line refs 6, 7, 13-15, 20-22, 35, 125-131, 134 (literal `main`), no `set -e`, 63 commands | all exact; `set -u` only | OK |
| `grep -cE 'BASE_REV\|getopts\|\$\{3'` -> 0 | 0 | OK |
| `git-guard.sh` pointers `:44` classifier resolve, `:53-57` python3 guard, `:74-77` classifier guard | all exact, both exit 2 | OK |
| toolchain: bash 3.2.57(1), git 2.50.1 (Apple Git-155), py 3.9.6, jq 1.7.1-apple, shasum 6.02, BSD `cmp` no `--version` | all exact | OK |
| `cmp -s` on two absent paths exits 2 | 2 | OK |
| `cmp --quiet` / `diff -q --no-dereference` / `readlink -f /tmp` all work here | 0 / 0 / `/private/tmp` | OK |
| `e3b09ba`: 0 occurrences of `lib/`, both helpers absent | exact | OK |
| `286fd5a`: all three paths absent | exact | OK |
| `bc7da76` vs `c461e4c`: guard `2b74507c` and classifier `2f8af693` unchanged, only `shell_segments` moved | exact | OK |
| `f5c5689` three blobs identical to HEAD's | exact (and still true at `5bc39b9`) | OK |
| `b17a666`: all three differ | exact | OK |
| `lib/` at HEAD: 3 matches, 2 of them comments (`:21`, `:29`) | exact | OK |
| Scenario J shape absent from history (guard references `lib/`, helpers missing) | **0 matches across all 632 commits** | OK |
| Scenario L shape absent from history (self-contained guard carrying helpers) | **0 matches across all 632 commits** | OK |
| history counts "631 commits / 65" | now **632 / 66** — drifted by exactly one, the spec's own commit; substance unchanged | see notes |
| `64ba2fa` 15:45:33 -> `cc035d2` 16:53:55 = 68 min | exact | OK |
| citation sites `git-guard-empty-index.md:311`,`:314-318` (215/326/346, 162/52/32); `shell-segments-redirects.md:118`,`:140`; `falsifier-base-pin.md:145`; ADR `0015:110` | all exact | OK |
| amend-by-new-ADR at `0009:105`, `0011:4-6`, `0013:5`; next ADR is 0016 | exact | OK |
| neither harness in `hooks/` has a `.test.sh` sibling; falsifier prints literal `$BASE` (`:100`) with pinned default (`:25`) | exact | OK |
| no absolute paths, no secrets anywhere in the spec | none | OK |

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/task-list-scenario-drift` | `~/.claude/skills/writing-specs/SKILL.md` | Good/bad/edge scenarios must be enumerated and the spec maintained with production rigor — it must not drift out of sync with itself | Tasks item 7 (`:441`), against Scenarios A-L (`:307-409`) | The verification checklist says "Verify scenarios A-K", omitting Scenario L — the sole falsifier revision 8 was written to add — so a builder working the checklist reproduces revision 7's coverage exactly and never runs the test that pins the new membership rule. |

### Notes (non-blocking)

- **`631` / `65` are stale by one at the current HEAD (632 / 66)** — the spec's own commit landed
  after the measurement. The substantive claim re-verified exactly: **zero** commits in the whole
  history hold either mixed shape, in either direction, so Scenario J's and Scenario L's bases
  genuinely must be synthesized. Anchoring the counts to a commit ("as of `c461e4c`") the way the
  measurement table already does would end this churn permanently rather than one revision at a time.
- **No scenario asserts the successful-run *header*.** Part 5 and task 6 both name line 134 — the
  fourth hard-coded `main`, called out in the root cause — but Scenarios C, D and I only assert the
  *pair-count* line. An implementation that fixes only the summary line passes every scenario with
  `main` still hard-coded in the header. Not ambiguous (the contract and task 6 both state it), so
  not cited; adding "And the header names the same resolved base" to Scenario C would close it.
- **Part 2's "part 3 reuses this rule" sentence slightly over-claims for the default mode.** Part 3's
  `cmp`-safety argument rests on "part 2 has already proved every member of each side's set extracted
  non-empty" — true for a rev candidate, but part 2 is not applied to the worktree candidate at all
  (non-goal deferral 2). The failure direction is the loud one (a missing candidate helper makes
  `cmp` return 2, so the run proceeds rather than falsely refusing) and both the gap and its
  consequence are already recorded as deferral 2 and limit 2, so this is prose precision, not a hole.
- **Scenarios C/D name abbreviated rev strings** rather than the resolved 40-char SHA. Carried
  forward from round 7 as a note for the same reason the round-7 judge gave, independently
  re-derived: Scenario A (default base) and Scenario I ("the resolved SHA of `e3b09ba`") make the
  weak reading unable to pass the spec as a whole. Revision 8 did not touch either scenario.
- **Scenario L does not say how its candidate is supplied.** `e3b09ba` as a rev candidate satisfies
  its Given exactly and needs only the base synthesized, which is what task 4 already assumes.
  Naming it removes the last piece of guesswork.
- **Part 6's "Each gets a one-line provenance note"** is contradicted one line later by the table's
  "NOT edited" row and by task 9's "four sites". The table and the following ADR-0015 paragraph
  resolve it unambiguously, so not cited.
- **Spec path.** `docs/features/` rather than writing-specs' `docs/superpowers/specs/`: the repo
  layer (`CLAUDE.md` -> `rules/gates.md`, one-canonical-file discipline) mandates
  `docs/features/<name>.md` for feature-scale work and takes precedence. Not cited.
- **Part B is clean.** Every one of the six parts traces to a measured false-pass route (YAGNI);
  error handling is explicit at every boundary the design introduces, with exit codes, output
  suppression and message content all stated; the two unclosed comparison limits and the five
  deferred architecting recommendations are recorded with the deciding user and date, so no deferral
  is invisible; architecture trade-offs are attributed to user decisions rather than decided in the
  spec; versions are pinned and measured; no secrets or absolute paths; and the ~40-line change
  leaves a 137-line file far inside the file-size convention. No security rule's territory is
  touched beyond shell execution, where every one of the three external inputs (`WT`, `UNDER_TEST`,
  `BASE_REV`) is validated at its boundary and fails closed.

### Waiver record

None. No violation id has been waived on this spec in any round of either cycle.

---

## Round 2 (new cycle — revision 9) — 2026-08-05 — **PASS** (0 violations)

**Repo:** `.claude` · **branch:** `main` · **head:** `8634fba446edbcb5d853df392488569134f59d5e`
**Spec blob:** `ea2b820ce2ba54827f1392fbb8d56e30b3ec1b7f` · **Confidence:** high
**Waived coming in:** none. **Prior-round violations supplied:** one —
`writing-specs/task-list-scenario-drift`.

### Layman summary

Revision 9 closes the one thing that blocked it, and closes it properly. Task 7 — the checklist step
an implementer actually works from — now says "Verify scenarios **A-L** by execution — all twelve, L
included", and adds why L matters: it is the falsifier for the membership rule revision 8 was written
to add, and a run that skips it has exactly revision 7's coverage. That is the fix plus the reason
for the fix, which is what stops the same drift recurring. There are twelve scenarios (A-L, H being
the meta cross-check), so "all twelve" is also arithmetically right.

The three non-blocking items were taken in the same pass, and all three landed:

1. **The over-claim is gone.** Revision 8's `cmp` bullet said part 2 "has already proved every member
   of each side's set extracted non-empty". It now claims only that a non-member is never an
   operand, and states the residual out loud: in default `worktree` mode a member can be absent from
   disk, `cmp` reports "not identical", the run proceeds, and limit 2 governs the outcome (candidate
   exits 2 on every command, `relaxed` 0, silent pass). Recorded, not closed, and tied to deferral 2.
   A spec that names its own soft spot is worth more than one that quietly asserts it away.
2. **The disk-reading rule is stated exactly once.** I checked every occurrence: the only live
   statement of "read the bytes that will actually execute — from disk, not `git show HEAD:`" is the
   bullet at `:174-182`, covering membership *and* byte comparison; the membership paragraph at
   `:141-143` points at it rather than restating it; every other hit is the revision log or a
   deferral referring back to it. No third drifted pair was created.
3. **Part 5's header half is now falsifiable.** Scenario D asserts that a *successful* run's header
   names the same resolved base as the summary line. I confirmed this bites: line 134 really is a
   separate `printf` carrying the literal string `main`, so an implementation that fixed only the
   summary line now fails a scenario instead of passing the whole file.

And the volatile history counts are pinned to `5bc39b9`. I re-ran that measurement across all 632
commits myself, in both directions: **66 / 66 / zero mixed shapes**, exactly as written. That was
the whole point of pinning — a number that carries its baseline can be re-checked a year from now,
which is the same rule the spec is asking the harness to obey.

Nothing I checked was wrong. Every line pointer, every blob identity, every toolchain version and
every citation-site line number reproduces exactly on this host at this HEAD. Six notes below, all
minor; none of them makes a requirement readable two ways, and none blocks the build.

### What I re-measured this round (nothing taken on trust from round 1)

| claim | measured at `8634fba` on this host | result |
|---|---|---|
| history pinned at `5bc39b9`: 632 commits; 66 with guard + ≥1 helper, all 66 reference `lib/`; 66 guards reference `lib/`, all 66 carry both helpers; zero mixed either way | full walk of all 632 commits: `total=632 · 66/66 mixedA=0 · 66/66 mixedB=0` | **exact** |
| task 7 now reads A-L / "all twelve"; no live `A-K` remains (3 hits, all revision-log) | exact | OK |
| exactly one live statement of the disk-reading rule (`:174-182`); membership paragraph points at it | exact | OK |
| Scenario D asserts the successful-run header; line 134 is a distinct site printing literal `main` | `134:printf 'DISTINCT COMMANDS main BLOCKS and %s ALLOWS:\n'` | OK |
| replay refs 6 (`WT`), 7 (`UNDER_TEST`), 13-15 (`git show main:` ×3), 20-22 (candidate), 35 (`/usr/bin/jq`), 125-131 (compare/else), 134; `set -u` only, no `set -e`; 137 lines | all exact | OK |
| `grep -cE 'BASE_REV\|getopts\|\$\{3'` → 0 | 0 | OK |
| guard `:44` classifier resolve, `:53-57` python3 guard (`exit 2` at `:56`), `:74-77` classifier guard (`exit 2`) | all exact | OK |
| toolchain: bash 3.2.57(1), git 2.50.1 (Apple Git-155), python3 3.9.6, jq 1.7.1-apple, shasum 6.02, BSD `cmp` (no `--version`) | all exact | OK |
| `cmp -s` on two absent paths exits 2 | 2 | OK |
| `e3b09ba`: 0 occurrences of `lib/`; `286fd5a`: all three paths absent | exact | OK |
| `b17a666`: all three blobs differ from HEAD; `bc7da76`: guard `2b74507c` and classifier `2f8af693` identical to HEAD, only `shell_segments.py` moved | exact | OK |
| `f5c5689` and `c461e4c` three blobs identical to HEAD's (so the measurement table still reproduces) | exact | OK |
| deferral 3: `lib/` at HEAD = 3 matches, 2 comments (`:21`, `:29`), 1 code (`:44`) | exact | OK |
| citation sites `git-guard-empty-index.md:311` + `:314-318` (215/326/346, 162/52/32), `shell-segments-redirects.md:118`, `:140`, `falsifier-base-pin.md:145`, `0015:110`; queue pointer `falsifier-base-pin.md:140-152`; next free ADR is 0016 | all exact | OK |
| no absolute paths, no secrets, no TBD/placeholder outside the house `Verification` stub | none | OK |

### Round-1 violation: closed

`writing-specs/task-list-scenario-drift` — task 7 (`:460-462`) now reads "Verify scenarios A-L by
execution — **all twelve, L included**", with the falsifier's purpose stated inline. Task 4 already
carried L's synthesized base; Scenario H already covered L. The checklist, the scenarios and the
rule they pin now agree at every site. Not recurring.

### Violations

None.

### Notes (non-blocking)

- **One word left of the over-claim.** Part 2 (`:123-124`) still says "the set part 3 compares is
  exactly the set part 2 **validated** here", while part 3 (`:138`) says "part 2's **required**
  set" — the accurate phrasing, since part 2 validates the base and a *rev* candidate but not the
  default `worktree` candidate. Not cited: both sites define the *same* membership rule, so no
  implementation forks on it, and part 3's ⚠️ paragraph states the residual explicitly two
  paragraphs later. Changing "validated" to "required" would retire this pair permanently.
- **The refusal scenarios assert "no pair-count line" but never "no `DISTINCT COMMANDS` header"** —
  the contract (`:432-433`) requires both. This is the mirror of the gap revision 9 just closed for
  successful runs: an implementation that prints the header and then refuses passes A, E, J, K and
  L. Not cited (the contract and part 5 both state it unambiguously, the same reasoning round 1 used
  for the successful-run header); adding one `And` line to Scenario A would close it.
- **No scenario covers a *candidate*-side extraction failure**, though part 2 (`:107-108`) and task
  3 both require `git-guard.sh` to be mandatory "on both sides". The failure direction is the loud
  one (an empty candidate turns every base block into a reported relaxation), and the requirement is
  explicit rather than inferred, so this is coverage rather than ambiguity. Carried from earlier
  rounds.
- **Deferral 3 is the last unpinned volatile figure.** "At HEAD, 2 of its 3 matches are comment
  lines" (`:281-282`) is exact today, but it is HEAD-relative — the same shape revision 9 just fixed
  for `632`/`66`. Pinning it to a SHA would finish the job.
- **Scenarios C/D still name abbreviated rev strings** as "the base". Carried forward for the third
  time on the same reasoning, independently re-derived: Scenario A (default base), E and I demand
  the 40-character SHA, so the weak reading cannot pass the spec as a whole.
- **Scenario L still does not say how its candidate is supplied** — `e3b09ba` as a rev candidate
  satisfies its Given and needs only the base synthesized, which task 4 already assumes.
- **Part 6's "Each gets a one-line provenance note"** (`:222-223`) still reads loosely against the
  table's `NOT edited` row, the following ADR-0015 paragraph and task 9's "four sites". Three
  unambiguous statements against one loose word; not readable two ways in practice.
- **Spec path** `docs/features/` rather than writing-specs' `docs/superpowers/specs/`: the repo layer
  (`CLAUDE.md` → `rules/gates.md`, one-canonical-file discipline) mandates
  `docs/features/<name>.md` for feature-scale work and takes precedence. Not cited.
- **Part B remains clean.** Every one of the six parts traces to a measured false-pass route (YAGNI);
  error handling is explicit at each boundary the design introduces, with exit code, output
  suppression and message content stated; the two comparison limits, the exit-code gap and the five
  deferred architecting recommendations are all recorded with the deciding user and date, so no
  deferral is invisible; architecture trade-offs are attributed to user decisions rather than
  decided in the spec; versions are pinned and measured on this host; no secrets, no absolute paths;
  a ~40-line change to a 137-line script stays far inside the file-size convention. Security
  territory touched is shell execution only, where all three external inputs (`WT`, `UNDER_TEST`,
  `BASE_REV`) are validated at the boundary and fail closed.

### Waiver record

None. No violation id has been waived on this spec in any round of either cycle.

---

## Round 1 (new cycle #3 — revision 10) — 2026-08-05 — **FAIL** (2 violations)

**Repo:** `.claude` · **branch:** `fix/replay-harness-base-pin` · **head:** `7bed4d0aa3493f91866105068976ac036662eea3`
**Spec blob:** `915e331c06bd9c0de7fa23a8d3f6c3c6adc199bc` · **Confidence:** high
**Waived coming in:** none — no violation has ever been waived on this spec in any of the three cycles.

### Layman summary

Revision 10 does the hard thing well. It takes a gap it had previously written down as "deferred",
and it does not paper over the awkward parts: it re-measured the observability judge's number,
disagreed with it, and then *refused to invent a story for the difference*. I checked that refusal
carefully, because "declined to explain" can be a dodge — here it isn't. The new figure
(`260 identical, 118 stricter, 0 relaxed`) is the exact arithmetic mirror of the spec's own row 5
(`118 identical, 260 stricter`): in one run the base allows everything, in the other the candidate
blocks everything, and both independently put the real guard at 118 allows / 260 blocks of 378
pairs. The judge's `292/86` would require the broken candidate to allow 32 commands, and the direct
probe shows it allows none. I also confirmed the spec quotes the judge accurately — the judge record
really does say `292 identical, 86 stricter, 0 relaxed` at its line 196. Preferring the re-measured
number and stopping there is exactly right; inventing a mechanism would have been the failure this
spec exists to describe.

I hunted specifically for the failure this spec has now committed six times — a rule written in two
places that later drift apart — and on the *rules* it is clean. The on-disk-vs-`git show` rule is
stated once (part 3) and referenced, not restated, by part 2 and task 11. The side-membership rule
has one definition (part 2's required set) and part 3 says it reuses it. The error-identity rule
agrees across part 2, the refusal contract, task 11, and Scenarios E, F, J and M. The scenario set,
Scenario H's enumeration, and the task list all agree on A–M: H lists A, B, E, F, J, K, L, M as
refuse/error and C, D, G, I as report — twelve scenarios, all accounted for — and the full A–M sweep
is assigned to task 11. Task 7 was correctly left at A–L because it is a completed record with
results; rewriting it would have falsified it. I also read every revision-history section: they are
genuinely append-only, older claims carry inline supersession notes (`629 → 631 → 632`, revision 6
superseding revision 3), and nothing live is hiding behind them.

Two things block it, and both are the same shape: a statement about the repository that the
repository does not support.

**1. A code pointer that points at the wrong lines.** The spec twice cites `replay.sh:64-68` as the
place where the default `worktree` candidate is exempted from validation, quoting the comment
"Deliberately not validated here". That comment is at **line 74**, and the worktree branch it sits in
runs **73–77**. Lines 64–68 are the closing brace of `extract_helpers_if_referenced`, a blank line,
the base-hook comment, and the two `BASE_SHA` / `BASE` assignments — the *base* extraction, not the
candidate exemption. This is not a pre-fix line number carried over from the root-cause section: the
neighbouring `replay.sh:61` pointer (the destructive `rm -f`) is correct against the *current* file,
and the comment being quoted only exists after task 3, so both pointers are post-fix notation and one
of them is wrong. Verified at HEAD and again at `cdaa1c3`. This matters because `64-68` is the
address of the exact code task 11 must change, and because this spec's own history records a wrong
pointer (`:56` → `:74-77`) that survived three consecutive rounds and was on its way into a permanent
ADR.

**2. Task 11's blast-radius check is already false, and prescribes the wrong conclusion.** It says
the branch's final diff "should **stay at 6 files**", and that "a 7th file means the change widened,
which is the exact failure the last two branches in this class shipped". At the HEAD this spec was
written on, `git diff --name-only main...HEAD` returns **8** files — the two observability-judge
records under `coding-memory/observability-judge/` landed at `cdaa1c3`, the commit immediately before
revision 10. Running task 10's judge and this compliance round adds more. So an implementer executing
task 11's last step measures 8 (soon 10), compares against 6, and is instructed to conclude the
change widened. Either the check produces a false alarm on a spec whose entire thesis is that a check
which fires for the wrong reason is worthless, or it gets quietly fudged. The fix is one clause —
scope the figure ("6 files outside `coding-memory/`") or re-measure it — but as written the criterion
cannot be satisfied.

Everything in Part B (what it commits to build) is clean, including the best thing in this revision:
part 2 and task 11 both name, in advance, that reusing `extract_helpers_if_referenced` for the
worktree side would run its `rm -f` branch against the user's real repository. Naming a destructive
action before writing it is precisely the zero-trust invariant, and it is stated twice on purpose.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/spec-code-accuracy` | `skills/writing-specs/SKILL.md` | The spec is the source of truth and is maintained with production rigor; drift between spec and code makes the agent describe behavior that does not exist | "The fix" part 2 (`:136`) and "Revision 10 — deferred non-goal 2 taken" (`:727`) | `replay.sh:64-68` is cited twice as the site of the worktree-candidate exemption, but that comment is at line 74 and its branch spans 73–77; lines 64–68 hold the base extraction, so the pointer sends task 11's implementer to the wrong code. |
| 2 | `writing-specs/blast-radius-figure-stale` | `skills/writing-specs/SKILL.md` | Requirements must be checkable and must not be readable two ways; a spec figure is maintained in the change that makes it wrong | Tasks, task 11, final bullet (`:716-719`) | Task 11 requires the branch diff to "stay at 6 files" and calls a 7th evidence the change widened, but the diff was already 8 files at the commit revision 10 was written on, so the check cannot pass as stated. |

### Notes (non-blocking)

- **The `292/86` vs `260/118` handling is exemplary, not evasive.** Re-derived independently: with
  the base allowing everything (row 5) the healthy guard measures 118 allows / 260 blocks; with the
  candidate blocking everything the same guard must produce `260 identical, 118 stricter, 0 relaxed`.
  Exact mirror, no free parameters. The judge quote was verified verbatim against
  `coding-memory/observability-judge/2026-08-05-fix-replay-harness-base-pin.md:196`. Declining to
  reconcile is the correct call under the repo's own "measure the explanation, not just the number"
  discipline.
- **The root cause still says "five distinct ways to print a pass that could not have failed".**
  Revision 10 closes a sixth (the default worktree candidate that cannot execute), which the spec
  catalogues under non-goal limit 2 rather than as a numbered route. Not cited: the partition between
  "routes this change closes" and "limits it does not" is explicit, cross-referenced from part 6, and
  limit 2's ⚠️ bullet states precisely what revision 10 closed and what it did not. A one-line note in
  the root cause would retire the ambiguity permanently.
- **"Identity of the side" is defined for errors but not for the two-sided vacuity refusal.** The
  contract binds "every refusal and every named error" to name "the identity of the side it
  concerned", then defines identity per side — but a vacuity refusal concerns both. Scenario A pins
  the base SHA and the shipped message names only that, so both readings are harmless and no scenario
  forks on behaviour; still, this is the "both readings pass every scenario" signature that revision 8
  was written for, and one clause ("a vacuity refusal names the base side") would close it.
- **Part 6 still calls part 2's coverage "a failed extraction" (`:261`)** — the exact conflation
  revision 10 retitled part 2 to kill, in the sentence that sources the permanent ADR text. Not cited:
  part 6's own later paragraph (`:287-290`) and task 11 both say "three sides, not two" explicitly, so
  the ADR amendment is unambiguously specified.
- **Task 5's record says `model_tier: low` was set; the frontmatter now reads `high`.** Explicable —
  revision 10 re-entered planning at `cdaa1c3` — but the two sit in one document without a connecting
  word. Record-vs-repo territory; flagged for the observability judge rather than cited here.
- **No diagram.** writing-specs asks for visual aids alongside the pinned toolchain. Revision 10
  introduces a hard *ordering* requirement across three parts (part 4 path resolution → part 2 side
  validation → part 3 vacuity refusal → matrix) that Scenario M exists solely to pin; a five-node
  Mermaid flowchart would carry it better than the prose does. Not cited — nine prior rounds did not,
  and the ordering is stated unambiguously in Scenario M and task 11.
- **Re-verified from the repo this round:** `lib/` occurs 3 times in `git-guard.sh`, 2 of them
  comments (deferral 3, exact); `git-guard.sh:44` / `:53-57` / `:74-77` all correct; `replay.sh:61` is
  the `rm -f` (correct); `5bc39b9` is 632 commits (exact); ADR 0016 exists, was authored on this
  branch at `e86ddb5`, is **not** on `main`, and its `:37-56` really is the "what this change proves"
  section quoted; `cdaa1c3` resolves. The amend-by-new-record convention holds at `0011:4-6` and
  `0013:5`; `0009:105` is about a *locked spec* rather than an ADR amending an ADR — the weakest of
  the three citations, though the principle is the same. Editing an unmerged ADR 0016 rather than
  superseding it is correctly reasoned and correctly scoped to unpublished records.
- **Part B is clean.** YAGNI: revision 10 is a user decision (session 14) triggered by a *reproduced*
  defect, and deferrals 1, 3, 4 and 5 stay deferred with the deciding user and date recorded. Error
  handling: every new boundary states exit code, output suppression and message content, and the three
  residual limits are recorded rather than swallowed. Destructive-action discipline: the `rm -f`
  against `$WT` trap is named before it is written, twice. Versions pinned and measured on this host;
  no new dependencies; no secrets, no absolute paths; `replay.sh` at 239 lines stays far inside the
  file-size convention. Security territory is shell execution only, and all three inputs (`WT`,
  `UNDER_TEST`, `BASE_REV`) are validated at the boundary and fail closed.
- **Spec path** `docs/features/` rather than writing-specs' `docs/superpowers/specs/`: the repo layer
  (`CLAUDE.md` → `rules/gates.md`, one-canonical-file discipline) mandates `docs/features/<name>.md`
  for feature-scale work and takes precedence. Not cited, consistent with all prior rounds.

### Waiver record

None. No violation id has been waived on this spec in any round of any cycle.

---

## Round 2 (new cycle #3 — revision 10) — 2026-08-05 — **FAIL** (1 violation, recurring id)

**Repo:** `.claude` · **branch:** `fix/replay-harness-base-pin` · **head:** `e5b6f0b036d1f63701d6441d1906f23f7c3ea4cf`
**Spec blob:** `5a7739fd822470b8659e5e8df313f20ee6f2eb5c` · **Confidence:** high
**Waived coming in:** none. **Round-1 violations:** both fixed and re-verified (`:73-77`/`:74` is
genuinely the worktree-exemption branch and its comment; task 11's blast radius is now a named set).

### Layman summary

The spec's headline claim is true, and I did not take it on report — I cloned the repo, deleted
`hooks/lib/`, and ran the DEFAULT invocation myself. It printed **`260 identical, 118 stricter,
0 relaxed`, exit 0**, under `base=56f1dfdf…(main)`: a clean pass from a candidate that cannot
execute. That matches the spec to the digit, matches the arithmetic mirror of its own row 5, and does
**not** match the round-2 observability judge's `292/86`. Preferring the measured figure and refusing
to invent a mechanism for the other one is the right call, not a dodge — the spec says plainly that
none was measured, and the number it carries is the one that reproduces.

The three rules I was asked to attack all hold. The on-disk-vs-`git show` rule, the side-membership
rule and the error-identity rule agree at every site I could find, including the new ones revision 10
added. The scenario set is A–O and Scenario H, part 2, part 3 and task 11 all agree on it — no
scenario/task drift this round, which is this spec's most-cited historical class. The revision
history really is append-only: every superseded figure carries a forward pointer to the revision that
corrected it, and nothing in the older sections is doing hidden work.

What fails is smaller and duller, and it is the *other* half of the class this spec keeps tripping
on. The spec's own thesis is that a number without its baseline cannot be audited without
archaeology. Its **line numbers** are exactly that. Roughly a dozen live pointers still index
`hooks/git-guard.replay.sh` as it stood on `main`, before tasks 2–6 changed the file — so "the
`else → same` tally (lines 125-131)" now lands on the vacuity block *this branch added* (the tally is
at `:227-233`), "line 134" lands in fixture setup (the header printf is `:236`), and the pinned
toolchain's "`/usr/bin/jq`, hard-coded at line 35" lands in the middle of the command array (`:137`).
Meanwhile revision 10's own pointers — `replay.sh:73-77`, `:61`, `:57-58` — index HEAD and are
correct. One document, one notation, two different files, and nothing tells the reader which is
which. The same drift has quietly broken the Red-probe regeneration recipe (it `sed`s a `show main:`
string that no longer exists in the repo file) and left the part-6 citation table pointing two lines
short of the figure it names, because task 9's own annotation pushed that figure from `:140` to
`:142`. Cheap to fix, but the fix is an **enumeration**, not another point patch — round 1 corrected
the single pointer it was handed and the class survived, which is why the id recurs.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/spec-code-accuracy` | `skills/writing-specs/SKILL.md` | The spec is the source of truth and is maintained with production rigor; drift between spec and code makes the agent describe behavior that no longer exists | Part 2 (`:109`, `:116`), part 5 (`:244`), part 6 (`:268` and the citation table `:279`), Pinned toolchain (`:305`), Deliberate non-goals limits 1–2 (`:397`, `:400`), Scenario D's comment (`:462`), Verification probe recipe (`:1101-1112`) | All of these index `hooks/git-guard.replay.sh` as it stood pre-fix on `main`, not at HEAD where tasks 2–6 already landed — `line 125`/`lines 125-131` now point at this branch's own vacuity refusal instead of the `else → same` tally (`:227-233`), `line 134` at fixture setup instead of the header printf (`:236`), `line 35` at the command array instead of `/usr/bin/jq` (`:137`) — while revision 10's pointers in the same document (`:73-77`, `:74`, `:61`, `:57-58`) index HEAD, so a reader cannot tell which file version any pointer means; the same drift makes the Red-probe regeneration recipe unrunnable against today's repo file and leaves the part-6 table's `shell-segments-redirects.md:140` two lines short of the figure it names after task 9's annotation moved it to `:142`. |

**Verified, not assumed:** I read `git show main:hooks/git-guard.replay.sh` and the worktree copy
side by side. `125-131` and `134` are *correct* against `main`'s copy — the pointers were true when
written and went stale when the fix landed, which is why nine rounds did not catch them. That is the
same mechanism as round 1's task-8 "6 files", and the same remedy applies: state the baseline the
pointers index (or re-index them at HEAD), in one pass over all of them.

### Notes (non-blocking)

- **Reproduced independently this round:** clone with `--no-hardlinks`, local `main` from
  `origin/main`, `rm -rf hooks/lib`, then `bash hooks/git-guard.replay.sh <clone>` → `260 identical,
  118 stricter, 0 relaxed`, `EXIT=0`, header and summary both `base=56f1dfdf6f4a…(main)`. The spec's
  figure is exact; `292/86` did not reproduce; the arithmetic mirror against row 5 (`118/260`) is
  forced, not fitted. Declining to explain the judge's split is honest under this repo's own
  "measure the explanation, not just the number" discipline.
- **The three audited rules agree everywhere.** On-disk-vs-`git show`: part 2 (`:147`), part 3
  (`:222-232`), task 4, task 11 and the shipped `side_members "$NEW"` all read the executing bytes.
  Side membership: part 2, part 3 (`:184-189`), task 4, task 11, Scenarios I/J/L all say "helpers iff
  that side's guard references `lib/`". Error identity: part 2 (`:119-124`, `:161`), the refusal
  contract (`:603-618`), Scenarios E/J/N (SHA) and M/O (worktree path), task 11 — no drift.
- **No scenario/task drift.** Scenario H's enumeration (A, B, E, F, J, K, L, M, N, O refuse; C, D, G,
  I report) is exactly A–O with H itself; task 11 sweeps A–O; task 7's A–L is a completed record of
  what existed then. Clean.
- **Revision history is genuinely append-only and not hiding anything.** Revision 8's `631/65` and
  revision 7's `629` each carry the forward correction inline; revision 6 flags what it supersedes in
  revision 3; revision 9's now-obsolete "part 2 never validates the worktree candidate" is corrected
  by the revision-10 section above it *and* by part 3's ✅ bullet. Older sections describe what was
  true then.
- **Scenario O's rationale is unnecessary and mildly at odds with Scenario M's ordering rule.** O says
  its base must be non-vacuous "so part 3 cannot refuse first" — but M *requires* candidate validation
  to fire before the vacuity comparison, and O's truncated helper makes the bytes differ anyway, so
  part 3 could never refuse first here. Not cited: unlike the Scenario G finding it inherits the
  phrasing from, a bad base choice in O produces a false *failure* (the error would name the base
  side, failing O's first assertion), never a false pass. Deleting the clause would retire it.
- **Scenario O names no specific base**, where G names `b17a666` and M names the default. Same
  reasoning — it cannot pass for the wrong reason — so noted, not cited. N and O are otherwise
  concretely buildable: both name their fixture construction, the discriminating assertion, and why M
  does not cover them.
- **Part 3's "One rule, two uses, stated in exactly one place"** sits three lines above its own
  "⚠️ Three rules now depend on this one", and part 2 restates the substance while flagging itself as
  a reuse. Reconcilable as written (the third dependent is named and attributed), so not cited — but
  it is the exact drift signature this spec keeps paying for.
- **`sed` and `perl` in the probe recipe are unpinned**, and the `7a\` insert form is BSD-specific
  while the pinned block covers neither. Task 1 is complete, so nothing currently depends on it.
- **Recording-but-not-taking is handled honestly.** Deferrals 3 and 5 each state the *new* evidence
  that weakened them (a third silent dependent on `grep 'lib/'`; a false pass that survives revision
  10), state that un-deferring is the user's call and not the implementer's, and say to raise it at
  the gate. That is core-conduct's "architecture trade-offs stay human-owned" held correctly, and the
  TAKEN marker on item 2 keeps a closed decision as visible as an open one.
- **Part B is clean, re-verified.** YAGNI: revision 10 closes a defect a judge *reproduced*, on a
  recorded user decision. Error handling: every new boundary states exit code, output suppression and
  message content; the three residual limits are recorded, not swallowed, and limit 2's
  closes-the-example-not-the-limit distinction is correct. Destructive action: `replay.sh:61`'s
  `rm -f` is verified dead (its `else` branch runs only when no `lib/` is referenced, the sole writer
  is `extract_required` at `:57-58` in the other branch, `$TMP` is a fresh `mktemp -d`) and deleted
  rather than fenced — the right call for a line that would one day be handed `$WT`. Fail-closed on
  every validation failure; no new dependencies; versions measured on this host; no secrets or
  absolute paths; `replay.sh` at 239 lines is well inside the file-size convention.
- **Spec path** `docs/features/` over writing-specs' `docs/superpowers/specs/`: the repo layer
  (`CLAUDE.md` → `rules/gates.md` one-canonical-file discipline) mandates it and takes precedence.
  Not cited, consistent with all prior rounds.
- **Size**: 1113 lines / ~82K for a 239-line harness fix. Not cited — the history is deliberate and
  demonstrably load-bearing — but it is the largest standing cost to a first-time reader.

### Waiver record

None. No violation id has been waived on this spec in any round of any cycle.

**Security pass (`skills/writing-secure-code/SKILL.md`, territory: shell execution).** Read and
applied after the violations table was written, so recording it explicitly rather than leaving the
`rule_sources_read` entry to stand on its own. Findings: none. All three CLI inputs are validated at
the boundary and fail closed (`cd … && pwd -P` plus an existence check for `$WT`; `rev-parse --verify
--quiet "<rev>^{commit}"` for both revs), every expansion is quoted, there is no `eval` and no
string-built command. §3 (secrets) and §5 (prompt sanitization) have no territory here. §4's
automated-guardrail clause is met as far as it can be for a test harness: no `*.test.sh` sibling is a
reasoned non-goal that both harnesses in `hooks/` share, verification is by recorded execution, and
the dependent suite (`git-guard.test.sh`, 77/0) is re-run. Revision 10 is net *positive* on this axis
— it deletes the only destructive primitive in the file (`replay.sh:61`'s `rm -f`) rather than
pointing it at `$WT`.

## Round 3 (new cycle #3 — revision 10) — 2026-08-05 — **FAIL** (2 violations, both recurring ids)

**Repo:** `.claude` · **branch:** `fix/replay-harness-base-pin` · **head:** `6741e410dbb666afadf20252529c33db4d436b84`
**Spec blob:** `b09e2ac04cd06a29b395cf2f6493517678e82994` · **Confidence:** high
**Waived coming in:** none. **Round-2 violation:** the pointer *convention* is now stated and almost
every pointer obeys it — but two instances of the exact pointer round 2 named (`line 134`) were
missed, so the id recurs a third time.

### Layman summary

The escalated decision — label every line number with which version of the file it belongs to — was
implemented well, and I checked it the hard way rather than reading the claim. I pulled up both
versions of the harness (`c461e4c` and HEAD) side by side and resolved **every** line-number pointer
in the document myself: the pre-fix ones (`6`, `7`, `13-15`, `20-22`, `125-131`, `134`) all land
exactly where the spec says, the HEAD ones (`:57-58`, `:61`, `:73-77`, `:74`, `:137`, `:227`,
`:227-233`, `:236`) all land exactly where the spec says, and every pointer into another document
(`falsifier-base-pin.md:140-152`/`:145`, `git-guard-empty-index.md:311`/`:314-318`,
`shell-segments-redirects.md:118`/`:142`, `0015:110`, `0011:4-6`, `0013:5`, ADR `0016:37-56`,
`git-guard.sh:44`/`:53-57`/`:56`/`:74-77`) is correct too. I also re-ran the Red-probe recipe from
scratch: it regenerates from `c461e4c`, the prefix hashes to `124a85e8`, the diff is exactly the four
edits the spec predicts (`7a8` and `13,15c14,16`), and the same probe against today's repo file
differs by 131 lines — the spec's number, reproduced to the digit. That is a genuinely thorough
enumeration and the convention itself is clear.

**What it missed is two of them, and they are the same line number round 2 called out by name.** In
the Root cause section, false-pass route 5 says "Line 134 prints the literal string `main`" with no
`(pre-fix)` label; the Revision 9 history section says "left line 134's hard-coded `main` alone" the
same way. Everywhere else in the document a bare prose line number carries its label — "line 6,
pre-fix", "lines 13-15 (pre-fix)", "line 134 (pre-fix)" — so these two read as HEAD, where line 134
creates a fixture test file. The convention as written binds the `` `replay.sh:N` `` form and never
mentions the bare "line N" form the document actually uses most, which is why an otherwise careful
sweep could walk past them. Revision 10's own record claims the Root cause section was swept; it was
not, quite.

The second finding is the blast-radius criterion again, in its new clothes. Round 1 cited it as a
stale count; revision 10 replaced the count with a named set, which was the right move — but the set
lists **six** paths while the same bullet's own measurement of `git diff --name-only main HEAD` is
**eight**. The two it drops are `docs/features/git-guard-empty-index.md` and
`docs/features/shell-segments-redirects.md`, the provenance annotations task 9 legitimately made. So
the sentence "Any *other* path in the diff means the change widened — the exact failure the last two
branches in this class shipped" fires falsely the day it is read. Separately, "the two judge-verdict
paths under `coding-memory/`" is defined one sentence earlier as the *observability* judge's md and
jsonl; this cycle's compliance-judge trail is two more paths under the same tree and is outside the
set as written.

Everything else I attacked held. The three audited rules (on-disk-is-truth, side membership, error
identity) agree at every site including the new ones. Scenario set is A–O with H as the meta-scenario
and no gaps; task 11 sweeps A–O; task 7's A–L is a completed record. The measured claims I could
re-run all reproduced: `git-guard.sh` has exactly 3 `lib/` occurrences at HEAD with 2 in comments,
`e3b09ba`'s guard has 0, `286fd5a` has no guard at all, every cited rev resolves, and the diff really
was 8 files at both `cdaa1c3` and `7bed4d0`.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/spec-code-accuracy` | `skills/writing-specs/SKILL.md` | The spec is the source of truth, maintained with production rigor; drift between spec and code makes the agent describe behavior that no longer exists | Root cause, false-pass route 5 (`:95`); Revision 9 section, "Part 5's header half is now falsifiable" bullet (`:953`) | Both write a bare `line 134` with no `(pre-fix)` label, so under the document's own convention they resolve at HEAD, where `:134` is fixture test-file creation rather than the header printf that hard-codes `main` (pre-fix `:134`; HEAD `:236`) — the identical instance round 2 cited by name, inside the Root cause section revision 10's record claims to have swept; the convention's own wording binds only the `` `replay.sh:N` `` form and never the bare "line N" form used throughout. |
| 2 | `writing-specs/blast-radius-figure-stale` | `skills/writing-specs/SKILL.md` | Requirements must be concrete and checkable, and must not be readable two ways — an acceptance criterion has to agree with the measurement it names | Task 11, final bullet: "Blast radius re-check, stated as a **set and not a count**" (`:802-813`) | The permitted set names six paths while the same bullet's measurement of `git diff --name-only main HEAD` is eight — `docs/features/git-guard-empty-index.md` and `docs/features/shell-segments-redirects.md` (task 9's provenance edits, named elsewhere in this spec) are in the diff and outside the set, so "any other path in the diff means the change widened" produces a false widening alarm as written; and "the two judge-verdict paths under `coding-memory/`", defined one sentence earlier as the observability pair, does not cover this cycle's `coding-memory/compliance-judge/` trail. |

**Verified, not assumed (violation 1):** `git show c461e4c:hooks/git-guard.replay.sh | awk` and
`git show HEAD:… | awk` printed with real line numbers. Pre-fix `:134` is
`printf 'DISTINCT COMMANDS main BLOCKS and %s ALLOWS:\n'`; HEAD `:134` is
`printf 'v1\n' > "$REPO/src/tracked.sh"; printf 'v1\n' > "$REPO/docs/tracked.md"`. Blob hashes match
the convention exactly: `c461e4c` = `main` = `124a85e8`, HEAD = `adbbf0a7`, `git-guard.sh` =
`2b74507c` at both.

**Verified, not assumed (violation 2):** `git diff --name-only main HEAD` → `CODING_MEMORY.md`,
`coding-memory/observability-judge/2026-08-05-fix-replay-harness-base-pin.md`,
`coding-memory/observability-judge/verdicts.jsonl`, `docs/decisions/0016-…`,
`docs/features/git-guard-empty-index.md`, `docs/features/replay-harness-base-pin.md`,
`docs/features/shell-segments-redirects.md`, `hooks/git-guard.replay.sh` — 8 paths, 2 of them outside
task 11's set. `coding-memory/compliance-judge/*` is tracked and currently modified in the working
tree, so this cycle's verdict trail is a further two paths under the same tree.

### The pointer class, enumerated (what I checked, so the next round need not redo it)

| pointer | baseline claimed | resolves to | ✓ |
|---|---|---|---|
| `WT` line 6, `UNDER_TEST` line 7 | pre-fix | `WT="$1"`, `UNDER_TEST="${2:-worktree}"` | ✓ |
| lines 13-15 (×3 sites) | pre-fix | the three `git show main:hooks/…` | ✓ |
| lines 20-22 | pre-fix | the three rev-candidate `git show` | ✓ |
| lines 125-131 | pre-fix | the `if/elif/else` comparison block | ✓ |
| line 134 (`:54`, `:263`, `:483`, `:701`) | pre-fix | the `DISTINCT COMMANDS main …` printf | ✓ |
| **`Line 134` (`:95`), `line 134` (`:953`)** | **unlabelled** | **HEAD `:134` = fixture setup** | ✗ |
| `replay.sh:57-58` | HEAD | `extract_required` helper calls | ✓ |
| `replay.sh:61` | HEAD | the `rm -f` in the `else` branch | ✓ |
| `replay.sh:73-77`, comment `:74` | HEAD | worktree branch + "Deliberately not validated here" | ✓ |
| `replay.sh:137` | HEAD | `payload() { /usr/bin/jq …` | ✓ |
| `replay.sh:227`, `:227-233` | HEAD | `relaxed` test; the tally block | ✓ |
| `replay.sh:236` | HEAD | the header printf with `base=%s (%s)` | ✓ |
| `git-guard.sh:44`, `:53-57`, `:56`, `:74-77` | (no qualifier needed) | `CLASSIFIER=`, python3 guard, its `exit 2`, classifier fail-closed | ✓ |
| `falsifier-base-pin.md:140-152`, `:145` | — | the queuing section; the tautology sentence | ✓ |
| `git-guard-empty-index.md:311`, `:314-318` | — | the 378-pairs claim; the candidate table | ✓ |
| `shell-segments-redirects.md:118`, `:142` | — | correction 2; task 5's replay line | ✓ |
| `0015:110`, `0011:4-6`, `0013:5`, `0016:37-56` | — | replay-blindness note; both Amends headers; "what this change proves" | ✓ |
| Red-probe recipe (`7a8`, `13,15c14,16`) | pre-fix | re-run: prefix `124a85e8`, exactly 4 edits, 131 lines vs today's file | ✓ |

### Notes (non-blocking)

- **The convention would be airtight with one more clause.** It defines `(pre-fix)` and an unqualified
  `` `replay.sh:N` ``, but the document's dominant form is bare prose ("line 6, pre-fix"). Saying that
  *any* line number, in prose or in backticks, is pre-fix only when labelled and HEAD otherwise would
  make violation 1 structurally impossible instead of fixed one instance at a time — which is exactly
  the enumerate-the-class remedy this spec applied everywhere else.
- **`0009:105` is the weakest of the three amend-by-new-record citations** — it records a deviation
  because a *spec* was blob-locked, not because an ADR was published. `0011:4-6` and `0013:5` carry
  the claim cleanly; the convention holds either way.
- **`sed`, `perl`, `grep`, `sort` remain unpinned** (probe recipe and harness internals), and the
  `7a\` insert form is BSD-specific. Carried over from round 2, still not cited: the pinned block
  covers the harness's load-bearing runtime, task 1 is complete, and the recipe now reproduces
  verbatim on this host.
- **Everything measurable in the spec that I could re-run, reproduced.** 3 `lib/` occurrences in
  `git-guard.sh` at HEAD with 2 in comments (deferral 3's claim, exact); 0 in `e3b09ba`'s guard;
  `286fd5a` has no `hooks/git-guard.sh`; all eleven cited revs resolve; `git diff --name-only main
  <rev>` is 8 at both `cdaa1c3` and `7bed4d0`, matching the spec; the 260/118 ↔ 118/260 mirror is
  arithmetically forced, not fitted.
- **No scenario/task drift.** A–O plus H; H's enumeration (A, B, E, F, J, K, L, M, N, O refuse; C, D,
  G, I report) is exactly the 14 defined scenarios; task 11 sweeps A–O and names the accepting-
  direction corner (A, C, D, G, I) as the one most likely to be cut. Task 7's A–L is a completed
  record of what existed then, correctly left alone.
- **Part B is clean, re-verified.** YAGNI: task 11 closes a gap a judge *reproduced live*, on a
  recorded user decision, and the four remaining deferrals stay deferred with their strengthened
  evidence stated. Error handling: every new boundary states exit code, output suppression and
  message content; three residual limits are recorded rather than swallowed, with limit 2's
  closes-the-example-not-the-limit distinction correct. Destructive action: `replay.sh:61`'s `rm -f`
  is verified dead and deleted rather than fenced — net security-positive. Fail-closed everywhere; no
  new dependencies; no secrets, no absolute user paths; `replay.sh` at 239 lines is well inside the
  file-size convention; architecture trade-offs (deferrals 1, 3, 5) explicitly left to the user at
  the gate.
- **Security pass (`skills/writing-secure-code/SKILL.md`, territory: shell execution).** Findings:
  none. `BASE_REV`, `UNDER_TEST` and `WT` are all validated at the boundary and fail closed
  (`rev-parse --verify -q "<rev>^{commit}"`, `cd … && pwd -P` plus an existence check); every
  expansion is quoted; no `eval`, no string-built command. §2/§3/§5 have no territory here.
- **Spec path** `docs/features/` over writing-specs' `docs/superpowers/specs/`: the repo layer
  (`CLAUDE.md` → `rules/gates.md` one-canonical-file discipline) mandates it and takes precedence.
  Not cited, consistent with all prior rounds. No `.claude/project-standards.md` exists in this repo.
- **Size**: 1172 lines (was 1113 at round 2) for a 239-line harness fix. Still not cited — the
  history is load-bearing and demonstrably prevents repeat errors — but it grows every round.

### Waiver record

None. No violation id has been waived on this spec in any round of any cycle.

---

## Round 4 (revision 10 cycle) — 2026-08-05 — **PASS** (0 violations)

**Repo:** `.claude` · **branch:** `fix/replay-harness-base-pin` · **head:** `8c53c67457f9563f0048c2c8a36fb84964e531f3`
**Spec blob:** `4423a45172b263e1855699b79c691c1efe4fd649` · **Confidence:** high
**Waived coming in:** none.

### Layman summary

Both of round 3's findings are closed, and I checked them the hard way rather than reading the
changelog. The pointer problem — a line number that means one thing in the old file and another in
the new one, cited three rounds running — is finally gone as a *class*: I pulled both versions of
`hooks/git-guard.replay.sh` out of git (the 137-line pre-fix one and the 239-line current one) and
resolved **every** line number in the document against them, including the ones buried in the
append-only history sections that earlier sweeps skipped. All of them land where the spec says they
land. The blast-radius list — which paths this change is allowed to touch — now names all eight
instead of six, and every file in today's ten-file diff falls inside it, so the "anything else means
the change grew" alarm can no longer fire on the judges' own paperwork.

The interesting part was the retraction. An advisory read had told this spec that an *empty* helper
file breaks the guard in the opposite direction from a *missing* one, and Scenario O's justification
was written on that claim. It was false, the spec now says so, and I confirmed the correction myself
by building all four broken shapes and running the real hook against them: a missing helper and an
empty `shell_segments.py` both make the guard block everything (the silent, dangerous failure), while
an empty `classify-git-command.py` or an empty `git-guard.sh` make it allow everything (the loud,
obvious one). The spec's four measured rows are exactly right, and it says plainly that Scenario O
happens to pin the dangerous shape *by luck* rather than by design — which is the honest version.
Scenario O still earns its slot for a different reason it now states correctly: it is the only test of
the "file must not be empty" check on the newest side.

Nothing blocking remains. The residual items below are polish, not defects, and none of them changes
what gets built.

### Violations

None.

| id | rule source | where | why |
|---|---|---|---|
| — | — | — | — |

### What I verified independently (not taken on report)

- **Pointer class — enumerated in full, both blobs in hand.** Pre-fix (`c461e4c`, blob `124a85e8`):
  `6`=`WT`, `7`=`UNDER_TEST`, `13-15`=the three `git show main:` calls, `20-22`=the candidate's three,
  `125-131`=the tally `if/elif/else`, `134`=the header printf hard-coding `main`. HEAD (blob
  `adbbf0a7`): `:35`=`rev-parse`, `:57-58`=`extract_required` helper calls, `:61`=the dead `rm -f`,
  `:73-77`=the worktree branch with its "Deliberately not validated here" comment at `:74`,
  `:137`=`/usr/bin/jq`, `:227`=`relaxed`'s definition, `:227-233`=the tally, `:236`=the header printf.
  Every one resolves as labelled. The two round-3 stragglers (route 5, revision-9 bullet) now carry
  `(pre-fix)`. The round-2 changelog's `lines 125-131` / `line 134` / `line 35` are *correct as bare
  HEAD pointers* — at HEAD those are fixture setup, test-file creation and `rev-parse`, which is
  exactly what the sentence claims. `git-guard.sh` `:44` / `:53-57` / `:56` / `:74-77` all correct
  (blob `2b74507c` at `main` and HEAD, so no qualifier needed, as stated).
- **Cross-document pointers.** `git-guard-empty-index.md:311` + table `:314-318` (215/326/346 and
  162/52/32), `shell-segments-redirects.md:118` and `:142`, `falsifier-base-pin.md:140-152`/`:145`,
  ADR `0016:37-56` ("What this change proves, and what it does not" — the section part 6 says must be
  amended). All resolve.
- **Blast radius.** `git diff --name-only main HEAD` is **10 files today** (8 at `cdaa1c3` and
  `7bed4d0`, as the spec states). Every one of the ten is a member of the eight-row set; rows 7 and 8
  are globs over the two judge trails, which is why the count moves and the set does not. The
  criterion is now satisfiable and cannot fire falsely.
- **The retraction, reproduced directly.** Built all four broken shapes and ran `hooks/git-guard.sh`
  against `ls -la` and `git push` in a fixture repo: helpers missing → **2** (blocks), empty
  `shell_segments.py` → **2** (blocks, *identical* to missing), empty `classify-git-command.py` → **0**
  (allows), empty `git-guard.sh` → **0** (allows). That is precisely the spec's 260/118/0 ×2 and
  118/0/260 ×2 table, and the mechanism is forced: `classify-git-command.py:68` does
  `from shell_segments import segments`, so an empty or missing `shell_segments.py` makes the
  classifier exit non-zero and `git-guard.sh:74-77` fails closed, while an empty classifier exits 0
  with no facts and the guard allows.
- **Red-probe recipe.** Re-run from scratch: `$PREFIX` hashes to `124a85e8`, the diff is exactly
  `7a8` + `13,15c14,16` (7 `<`/`>` lines), and the same probe against today's repo file differs by
  **131** lines. Reproduces to the digit.
- **Everything else re-runnable.** All 17 cited revs/blobs resolve; `f5c5689`'s three blobs are
  identical to HEAD's (Scenario B's premise); `e3b09ba`'s guard has 0 occurrences of `lib/`;
  `286fd5a` has no `hooks/git-guard.sh`; `git-guard.sh` at HEAD has 3 `lib/` matches with 2 in
  comments (deferral 3, exact); `git rev-list --count 5bc39b9` = **632**; `replay.sh` is 239 lines
  (137 pre-fix, so "tasks 2-6 added ~100 lines" is +102).
- **Scenario/task coherence.** 14 scenarios A–O plus meta-scenario H; H's split (A,B,E,F,J,K,L,M,N,O
  refuse or error; C,D,G,I report) covers all 14. Task 11 sweeps A–O and names the accepting-direction
  corner. Task 7's A–L is a completed historical record, correctly untouched.
- **Part B.** YAGNI: revision 10 takes one gap a judge reproduced live, on a recorded user decision;
  four deferrals stay deferred and are explicitly routed to the user at the gate. Error handling: every
  boundary (unresolvable rev, missing file, empty file, unresolvable worktree path, vacuous run) states
  exit code, output suppression and message content, and fails closed. The dead `rm -f` at
  `replay.sh:61` is verified dead (its `else` branch runs only when no `lib/` is referenced; the sole
  writer is `extract_required` at `:57-58` in the other branch; `$TMP` is a fresh `mktemp -d`) and is
  deleted rather than fenced — net security-positive. No new dependencies, no secrets, no absolute user
  paths, 239 lines well inside the file-size convention.
- **Security pass** (`skills/writing-secure-code/SKILL.md`, territory: shell execution). No findings.
  All three CLI inputs validated at the boundary and fail closed; every expansion quoted; no `eval`,
  no string-built command; the one destructive call in the design is removed rather than reused.

### Notes (non-blocking)

- **Two bare `line 7` mentions survive, and I deliberately did not cite them** (`:933`, `:1208`). Both
  describe the Red-probe recipe's `sed '7a\'` anchor, which operates on `$PREFIX` — the pre-fix file —
  and both sentences name `c461e4c` in the same breath ("Regenerate from `c461e4c`, NOT from the
  repo's working file"). Under the convention's literal token rule a bare number is HEAD, where line 7
  is `WT_INPUT`; under the convention's *purpose* (state the baseline) they are compliant, and the
  recipe's own first line builds `$PREFIX` from `c461e4c`, so misdirection is impossible. **The
  convention is workable** — this is the only residue after a full enumeration, and tagging the two
  costs four words if the author wants it airtight.
- **Same class, non-line-number form:** the Root-cause section's `grep -cE 'BASE_REV|getopts|\$\{3'
  hooks/git-guard.replay.sh` → `0` and "per its own header: run `main`'s `git-guard.sh`" are both true
  of the pre-fix file only (HEAD has `BASE_REV` at `:9` and a rewritten header). They sit inside a
  paragraph carrying three explicit `(pre-fix)` labels, and neither is a line number, so the convention
  does not reach them. Not cited; flagged so the class is on the record in full.
- **The round-3 advisory record still contains the retracted premise** ("empty helpers … fail in the
  *opposite* direction", `:959`). The round-4 paragraph six lines above retracts it by name, and the
  conclusion it supported (`292/86` cannot come from any helper-breakage shape) survives the correction
  — all four measured shapes are 260/118/0 or 118/0/260, neither of which is 292/86. An inline
  "(retracted above)" marker would close it; not cited because reading order puts the retraction first.
- **Scenario O's "nothing falsified (b) on any side"** reads present-tense while Scenario N, defined
  immediately above it, falsifies the non-empty check on the base side. The intended meaning (before N
  and O existed) is clear from the revision-10 record and from task 11's note that N is a regression
  lock; harmless, but "nothing *previously* falsified (b)" would be exact.
- **8 rows ≠ 8 files, and that coincidence is fragile.** The blast-radius bullet quotes "8 files at
  `cdaa1c3` and at `7bed4d0`" beside an 8-row set; today the same set spans 10 files. The set is the
  criterion and it holds — which is precisely the point the bullet makes about counts — but a reader
  could take the two eights as the same eight.
- **Carried forward, still not cited:** `sed`, `perl`, `grep`, `sort`, `diff` unpinned (the `7a\`
  insert form is BSD-specific) — the pinned block covers the harness's runtime and the recipe
  reproduces verbatim here; spec path `docs/features/` over writing-specs' `docs/superpowers/specs/`,
  mandated by the repo layer (`CLAUDE.md` → `rules/gates.md`), which takes precedence; no
  `.claude/project-standards.md` exists in this repo.
- **No diagram.** `writing-specs` asks for visual aids; the one place a small Mermaid flowchart would
  earn its tokens is the ordering constraint (part 2 validation → part 3 vacuity → matrix), which is
  currently prose plus Scenario M's comment. Observation only — the constraint is unambiguous as
  written, and this document does not need more words.
- **Size**: 1226 lines (1172 at round 3) for a 239-line harness fix. Still not cited — the history is
  load-bearing and has demonstrably prevented repeat errors — but four rounds have added ~54 lines each
  and the growth is now the largest standing cost of this process.

### Waiver record

None. No violation id has been waived on this spec in any round of any cycle.
