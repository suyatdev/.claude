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
