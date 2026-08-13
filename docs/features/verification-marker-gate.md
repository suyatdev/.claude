---
phase: planning
model_tier: high
branch: none
revision: 6
revision_status: complete  # round 6 closed all 7 open items; ready for the compliance judge
waived: [writing-specs/command-grammar]
---

> ## Round 6 status — COMPLETE, ready for the compliance judge
>
> Revision 5 was judged **`fail`** on 2026-08-04 (`00583c2`, 5 violations) and the spec then sat
> untouched until 2026-08-12, so that failing verdict described the live document for eight days.
> Round 6 closed **all seven** open items across two sittings. The standing exit criterion and the
> waiver policy now live at the bottom of this file, next to the checklist, and
> `docs/marker-gate-defect-checklist.md` has been folded in here and deleted — one document, not two.
>
> **Closed in round 6:**
> - **D1 (fatal) — wrapper recognition.** `rtk` rewrites `git commit …` → `rtk git commit …` before any
>   guard runs, and this spec had mentioned it **zero times**; the gate would have been dead on arrival
>   with task 14's arming check green over it. Now rule 0, importing `WRAPPERS` from
>   `hooks/lib/shell_segments.py:64` rather than re-spelling it.
> - **D2/D3 — fail-closed recognition.** Round 3's "anything it cannot lex allows" is replaced by a
>   closed whitelist of fully-spelled forms; `-p`/`--patch` and `--interactive` are refused on the
>   ground that they select content *after* the hook returns.
> - **`writing-specs/api-contracts`** — `form` is now a total, **ordered** function of the command
>   (rule 4's table), with `FOREIGN` and the new `UNSUPPORTED` given explicit positions.
> - **`writing-specs/latency-budget-count`** — task 10 now says all three budgets.
> - **`core-conduct/default-deny-store`** — `hooks/state/` `0700` and the log `0600` stated.
> - **N2** — the stray `G10` citation dropped; it labelled a repo-state measurement, not a grammar case.
> - **`writing-specs/commit-form-coverage`** — the merged `<base>` row is split in two. Re-measured on
>   git 2.50.1 (M5, four cases): the disk clause is right for `ALL` and **produces a false block** for
>   `PATHSPEC`, where a member outside the pathspec survives into the commit *even when its deletion is
>   already staged*. Measured, not reasoned, as the round-5 note demanded.
> - **`writing-specs/pair-formation-rule`** — the predicate is now stated in three steps, and stating
>   it exposed a contradiction: §Scope said a file with no sibling test is never gated while the `-am`
>   scenario forms a pair with an *untracked* test. The rule is **asymmetric** — subject→test tests
>   index ∪ disk (fail-closed, always clearable), test→subject tests the index alone. A symmetric
>   union would demand a marker the writer refuses to write and block that commit **forever**.
> - **N1** — `git diff --cached` outside a repo is **129**, not 128, and for a different reason than
>   recorded: git falls back to `--no-index`, which has no `--cached`. The fail-open hazard stands.
> - **O1** — the 7↔13 revert pair is named, with its order (**13 then 7**). This corrected a live false
>   claim: "reverting task 7 alone is harmless" stops being true once 13 lands.
> - **D4/D5** — blocks are logged now, not just exemptions, in one file with a decision column, read
>   back by `--status`; and the machine-local storage decision is stated as a decision, with what it
>   does and does not deliver.
>
> **Not in round 6, deliberately: O3, the shrink** — see "Standing decisions" at the bottom.

# verification-marker gate

A PreToolUse hook that blocks a `git commit` when a file with a sibling test is being committed at a
version its test suite has never passed against.

```mermaid
flowchart TD
    A[Bash tool call] --> PF{Raw payload contains<br/>the substring "commit"?}
    PF -- no --> P[ALLOW]
    PF -- yes --> NP{python3 usable?}
    NP -- no --> D3[BLOCK: MSG_NO_PYTHON]
    NP -- yes --> CM{Classifier present<br/>and readable?}
    CM -- no --> D4[BLOCK: MSG_CLASSIFIER_MISSING]
    CM -- yes --> CF{Classifier exit}
    CF -- "3 = unreadable payload" --> X[BLOCK: MSG_BAD_PAYLOAD]
    CF -- "other non-zero, or no output" --> D5[BLOCK: MSG_CLASSIFIER_FAILED]
    CF -- "0 with one line" --> CO{Output valid on<br/>every field?}
    CO -- no --> D6[BLOCK: MSG_CLASSIFIER_BAD_OUTPUT]
    CO -- yes --> C{Runnable command?}
    C -- "no, tool_name=Bash" --> Y[BLOCK: MSG_NOTHING_RUNNABLE]
    C -- "no, other tool" --> P
    C -- yes --> E{kind = COMMIT?}
    E -- no --> P
    E -- yes --> F{Toplevel resolves<br/>from payload cwd?}
    F -- no --> P
    F -- yes --> G{Writer installed<br/>in that repo?}
    G -- "no, gate not adopted" --> P
    G -- yes --> H{TEST_EXEMPT non-empty?}
    H -- "yes, invalid" --> BE[BLOCK: MSG_BAD_EXEMPT]
    H -- "yes, valid" --> Q[ALLOW, logged to file]
    H -- no --> I{form}
    I -- FOREIGN --> V[BLOCK: MSG_FOREIGN_REPO]
    I -- "UNSUPPORTED (patch/interactive/whitelist miss) or INCLUDE" --> UF[BLOCK: MSG_UNSUPPORTED_FORM]
    I -- "INVALID, git refuses it" --> P
    I -- "PLAIN / PATHSPEC / ALL" --> J[Collect path set]
    J -- git error --> U[BLOCK: MSG_GIT_FAILED]
    J -- ok --> K[Pair each path with its sibling test]
    K --> L{Any pairs?}
    L -- no --> P
    L -- yes --> M{Marker readable and valid?}
    M -- no --> Z[BLOCK: MSG_NO_MARKER / MSG_BAD_MARKER]
    M -- yes --> N{Both blobs match<br/>post-commit content?}
    N -- no --> W[BLOCK: MSG_STALE_SUBJECT / MSG_STALE_TEST]
    N -- yes --> P
```

## Background — why this exists

`rules/core-conduct.md` already says to reproduce before fixing and to verify before claiming. That is
the weak form of this control, and this repo established over four judge rounds on PR #34 that **a
warning placed where the mistake keeps being made is a disproven control** — the apostrophe trap fired
three times *inside the block carrying the warning against it*.

The strong form is computational: a passing test run leaves a machine-readable record of exactly which
file contents it certified, and a hook refuses a commit whose contents do not match. It cannot be
rationalised past, and it reads content rather than intent.

**Deliberately narrow.** This gate would **not** have caught the narration defect that prompted its
reordering, and the user accepted that explicitly. A narration control is a separate, later design.
Do not widen this feature to cover it.

**Spec location deviates from `writing-specs`** (which defers to `docs/superpowers/specs/`) because
`rules/gates.md` one-canonical-file discipline puts feature-scale work in `docs/features/<name>.md`.
The gate rule wins; there is no second spec location. *Round 1 compliance judged this adequate — do
not "fix" it.*

## Scope

### Where the gate is active

Registered **globally** in `settings.json` with matcher `Bash`, exactly like its four sibling guards
(`git-guard`, `doc-guard`, `judge-guard`, `merge-guard`), which are all global today — so it fires on
a `git commit` in **any** repo this account works in.

Global registration alone would be a lockout: another repo using the same `X.sh`↔`X.test.sh`
convention would have every commit blocked with no writer present to satisfy the demand, and
`.gitignore:17`'s `/hooks/state/` cover does not travel. So the gate is **inert until a repo opts in**,
and the opt-in signal is the writer itself:

> The gate is active in a repo **iff `<toplevel>/hooks/lib/write-test-marker.py` exists and is
> readable.** No writer, no gate — a repo cannot be held to a receipt it has no way to issue.

The check is one `test -r` against a path derived from the resolved toplevel. It is deliberately a
file rather than a config key: it is greppable, it cannot drift out of sync with the thing that makes
compliance possible, and it arrives and departs with the feature itself.

**Inertness must be observable, or the gate becomes decorative without anyone noticing.** A hook that
allows is silent, so nothing in a normal commit distinguishes "allowed, verified" from "allowed,
inert" — `judge-guard.sh:204` records exactly this failure in exactly this family. The gate therefore
supports `hooks/test-marker-guard.sh --status`, which prints `ACTIVE` or `INERT`, the resolved
toplevel, and the reason, then exits 0 without reading any payload. It is the first thing task 14
runs, and the answer `hooks/README.md` points at. Per-commit stderr chatter is deliberately rejected:
a notice on every allowed commit is a notice nobody reads.

### Which files the gate covers

Any repo path with a sibling test under the `X.sh`↔`X.test.sh` / `X.py`↔`X.test.py` convention.
**Measured 2026-08-02 from `git ls-files`, not recalled — 13 tracked suite files, 11 conforming pairs
(10 shell + 1 Python), 2 orphan suites.**

| # | subject | suite |
|---|---|---|
| 1 | `hooks/context-handoff-watch.sh` | `hooks/context-handoff-watch.test.sh` |
| 2 | `hooks/judge-guard.sh` | `hooks/judge-guard.test.sh` |
| 3 | `hooks/memsearch-nudge.sh` | `hooks/memsearch-nudge.test.sh` |
| 4 | `hooks/pane-dispatch-guard.sh` | `hooks/pane-dispatch-guard.test.sh` |
| 5 | `hooks/phase-guard.sh` | `hooks/phase-guard.test.sh` |
| 6 | `hooks/lib/classify-pr-command.py` | `hooks/lib/classify-pr-command.test.py` |
| 7 | `panes/adapters/cmux-layout.sh` | `panes/adapters/cmux-layout.test.sh` |
| 8 | `panes/dispatch-pane-agent.sh` | `panes/dispatch-pane-agent.test.sh` |
| 9 | `panes/run-pane-agent.sh` | `panes/run-pane-agent.test.sh` |
| 10 | `panes/terminal-detect.sh` | `panes/terminal-detect.test.sh` |
| 11 | `statusline-command.sh` | `statusline-command.test.sh` |

**This table is a dated measurement of the pre-feature repo, and it is not the completion criterion.**
Round 2 froze the number 11 in a test and that assertion was false from task 4 onward, because **this
feature adds three conforming pairs of its own:**

| # | subject | suite | lands at |
|---|---|---|---|
| 12 | `hooks/lib/classify-commit-command.py` | `hooks/lib/classify-commit-command.test.py` | task 3 |
| 13 | `hooks/lib/write-test-marker.py` | `hooks/lib/write-test-marker.test.py` | task 5 |
| 14 | `hooks/test-marker-guard.sh` | `hooks/test-marker-guard.test.sh` | task 7 |

All three are `hooks/` files with sibling tests, so **the gate demands markers for them too**. A
suite of this feature's own that does not write a marker makes its subject uncommittable the moment
the gate arms. The wiring criterion is therefore **every pair, 14 of them at task 8** — never a
literal carried over from the table above. The suite files live under four different directory
depths, which is why the call site cannot use a `$0`-relative path (see §1).

**Out, and stated so nobody later assumes coverage:**

- **Two orphan suites — tests with no sibling subject.** `panes/adapters.test.sh` exercises the whole
  `panes/adapters/` directory, and `panes/adapters/cmux-exec.test.sh` exercises
  `panes/adapters/cmux.sh`. Neither `panes/adapters.sh` nor `panes/adapters/cmux-exec.sh` exists.
  Behaviour is defined below (§"Test with no subject"), not left to inference: they write no marker
  and are never gated.
- 🔴 **`panes/adapters/cmux.sh` is gated by nothing.** It is the largest adapter in the repo and it
  *does* have a test — but that test is named `cmux-exec.test.sh`, so the strict 1:1 rule cannot see
  the relationship. `panes/` is therefore **partially** covered, and this file is the hole. Renaming
  the suite would close it and is deliberately **not** in this feature; it is a follow-up task.
- `memsearch/tests/test_*.py` uses a non-sibling layout, so the gate never fires there. Its own
  follow-up task — not forgotten, just not v1.
- Files with no sibling test. The gate never demands a test that does not exist.
- Deletions: every collector uses `--diff-filter=d`, so removing a file needs no test run. Measured:
  on a rename this keeps the **new** path and drops the old one, which is correct — the new path is
  what will exist after the commit.
- Every repo that has not installed the writer, per the opt-in rule above.
- Every write path that is not a Bash `git commit` — `sed -i`, the Edit/Write tools, an editor outside
  the session. **This is a momentum guardrail, not a security boundary**, exactly like `judge-guard.sh`.
- 🔴 **Test quality. The marker is a receipt, not a grade.** A blob hash proves the suite *ran against
  this exact pair of versions* — never that the suite is any good. A test gutted to `exit 0`, or one
  whose only assertion was commented out, earns a perfectly valid marker and sails through. This is the
  ceiling on the entire feature and it is not fixable within it: certifying test *strength* is mutation
  testing's job, which is why task 9 exists as a one-off floor rather than a gate. Anyone reading a
  green marker as "this code is tested" has read it wrong; it says "this code was run past its suite".

## Architecture

Three components, mirroring the `judge-guard.sh` / `judge-guard.test.sh` / `hooks/lib/` trio the repo
already knows how to build and test.

**Relationship to the existing guards — corrected by measurement.** Round 3 named `merge-guard.sh`
here; it does not lex `git commit` at all. The three production lexers are **`git-guard.sh:89`,
`doc-guard.sh:123` and `checkpoint-before-modify.sh:97`**, and all three anchor the pattern at
`^git[[:space:]]+`.

**That anchoring is a live fail-open in all three**, discovered while writing this round: a chained
`git add -- <path> && git commit -- <path>` never matches, so the guard does not evaluate. It is the
same defect class as G1/G2 above — a lexer that handles the shape its author had in mind. `gates.md`
records this chained-command limitation for `merge-guard` but not for these. `doc-guard.sh:135` even
carries `(-a|--all|-am)`, so it knew about one bundle — but not `-ams` or `-amHELLO` (G4).

This feature does **not** reuse or refactor them: they are bash answering a yes/no question, while
this classifier is Python and must return a form, a path list and an exemption. The duplication is
deliberate and its cost is stated here rather than discovered later — **four** call sites must stay in
step. Unifying them behind this classifier, and fixing the three anchors, is tracked as a follow-up
and as its own piece of work; it is not in this feature's scope.

### 1. `hooks/lib/write-test-marker.py` — the writer

Python because `hooks/lib/` is Python by convention, and because extracting `classify-pr-command.py`
already proved the payoff: an importable module gets asserted directly instead of probed through a hook.

**Contract:** `python3 -I hooks/lib/write-test-marker.py <test-file-path>` → exit 0 on success,
non-zero with a message on stderr otherwise. Pure function `write_marker(test_path) -> Path | None`
plus a thin `main()`.

**Path normalisation is mandatory and was the round-1 gap.** The suite passes `$0`, which is relative
to the suite's cwd — measured: running `bash adapters/cmux-layout.test.sh` from inside `panes/` yields
`$0 = adapters/cmux-layout.test.sh`, while the store key must be `panes/adapters/cmux-layout.test.sh`.
The writer therefore resolves every path through `git ls-files --full-name -- <path>` before using it.
Measured: from a subdirectory this returns the repo-relative path, and for an untracked path
`--error-unmatch` exits 1 with a message.

**Test with no subject.** After deriving the sibling subject, the writer checks it with
`git ls-files --error-unmatch`. If the subject is not a tracked file, the writer prints a one-line
notice to stderr, **writes no marker, and exits 0** — a green suite must not be turned red by the
absence of a file it never claimed to own. This is not a coverage map and does not re-open the
ratified strict-1:1 rule; it is the defined behaviour for the non-conforming case the repo actually
contains. The gate's mirror of the same rule (below) means those two suites are simply never gated.

Otherwise: hashes both files with `git hash-object`, and writes the marker atomically (temp file in
the same directory + `os.replace`).

#### What the inventory test actually asserts, and why not a count

Round 1 failed on an inventory claim no test could contradict. Round 2 corrected the number **and**
froze it — and froze the wrong thing: `pairs == 11` is false from task 3 onward by this feature's own
construction, which would have turned the writer's suite red and made `write-test-marker.py`
uncommittable under its own gate. **A control whose assertion the feature invalidates is not a
control.**

The invariant that survives the feature's additions is not a count but a **property**, and it is
asserted in two parts:

1. **Every tracked pair's suite contains the marker-write call.** Enumerate
   `git ls-files '*.test.sh' '*.test.py'`, derive each subject, keep the ones whose subject is tracked,
   and assert each of those suite files contains the call line. This has a real trigger — adding a
   paired suite without wiring it turns the suite red — and it self-extends to pairs 12–14 instead of
   contradicting them.
2. **The two named orphans are still orphans.** Assert `panes/adapters.test.sh` and
   `panes/adapters/cmux-exec.test.sh` each derive a subject that is **not** tracked. This freezes the
   `cmux.sh` coverage-hole claim in §Scope; the follow-up rename will turn it red, which is correct —
   the rename must update §Scope in the same commit.

Note what is deliberately *not* asserted: that the orphan set is exactly those two. During TDD each
red step commits a suite whose subject does not exist yet, which is a transient third orphan; an
equality assertion would make the red steps unlandable.

**Assertion 1 lands in task 8's commit, not task 4.** Written at task 4 it would be red for four
tasks, since the 11 pre-existing suites are not wired until task 8. Task 8 wires all 14 and adds the
assertion that keeps them wired, together, in one commit.

**Call site — one line per suite, after the tally.** Shell form:

```sh
# at the TOP of the suite, before any cd — both values ABSOLUTE:
MARKER_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER_ROOT="$(git rev-parse --show-toplevel)" || exit 1
# after the tally — run the writer WITH THE REPO ROOT AS ITS CWD, in a subshell
# so the suite's own cwd is untouched:
[ "$fail" -eq 0 ] && { ( cd "$MARKER_ROOT" && python3 -I hooks/lib/write-test-marker.py \
  "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }; }
```

Python form, for pairs 6, 12 and 13:

```python
# at module level, at the TOP of the suite, before any os.chdir — both values ABSOLUTE:
MARKER_SELF = os.path.abspath(__file__)
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True).stdout.strip()

# after the tally, in the suite's __main__:
if failures == 0:
    subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                   cwd=MARKER_ROOT, check=True)
```

Resolved from the **repo root**, not `$(dirname "$0")/lib` — that round-1 form resolves only for the
5 suites under `hooks/`, and with the mandated `|| exit 1` it would have turned the other 8 red.

**Capture at the top, use at the bottom, and give the writer the right cwd — all three, not two.**
Both `$0` and `rev-parse` depend on the suite's cwd, and **measured: `hooks/judge-guard.test.sh:13`
runs `cd "$TMP" || exit 1` at top level** — 1 of the 11 existing suites already invalidates a
bottom-of-file `rev-parse`.

Round 3 captured the two **values** at the top and stopped there, which was still broken: the writer
is a *separate process*, and both of its mandated resolution steps
(`git ls-files --full-name --error-unmatch` and `rev-parse --show-toplevel`) run in **its** cwd, not
in the values it was handed. Launched from a suite sitting in `$TMP`, `ls-files` exits 1 and
`rev-parse` returns the throwaway repo — so the mandated `|| exit 1` would have left that suite
permanently red. Hence: **absolute `MARKER_SELF`, and the writer invoked with `cd "$MARKER_ROOT"` in
a subshell.** Task 8 must not paste the call blindly into any suite.

**The rule binds both forms identically, and round 4's Python form broke it.** That form resolved
`--show-toplevel` inside `__main__`, at the bottom — and `os.path.abspath(__file__)` there is equally
cwd-dependent, since `__file__` may be relative on Python 3.9.6. §Testing requirements obliges pairs
12 and 13 to build throwaway repos, so a Python suite that `os.chdir`s into one would hand the writer
that repo as its root. The two forms are therefore written as mirrors: **capture `MARKER_SELF` and
`MARKER_ROOT` at module level before any chdir, both absolute; pass `MARKER_SELF`; run the writer with
`MARKER_ROOT` as its cwd** — `cd` in a subshell for shell, `cwd=` for Python. A reviewer should be able
to diff the two blocks and find no behavioural difference.

A failed marker write **fails the suite**. A silent no-marker would surface later as a confusing block.

### 2. `<repo>/hooks/state/test-markers/` — the store

- **One file per subject**, so two concurrent sessions never read-modify-write the same file.
- Filename is the repo-relative subject path, percent-encoded (`/`→`%2F`, `%`→`%25`).
- Resolved from `git rev-parse --show-toplevel`, **never `$HOME`**. Reading `$HOME`'s copy instead of
  the target repo's was literally the bug `fix/judge-guard-verdict-lookup` existed to fix; a marker
  written inside a worktree must be read back inside that worktree.
- Directory mode `0700`, marker files `0600` — core-conduct's default-deny for a generated store. The
  real defence is read-side validation, but the store is the sole authority for letting a commit
  through and there is no reason for it to be world-readable.
- Already gitignored by `/hooks/state/` at `.gitignore:17` — no new ignore rule needed.

**Marker schema** (JSON; two levels deep, so YAML buys nothing here):

```json
{
  "version": 1,
  "subject": { "path": "hooks/judge-guard.sh",      "blob": "<hex>" },
  "test":    { "path": "hooks/judge-guard.test.sh", "blob": "<hex>" },
  "written_at": "2026-08-01T00:00:00Z"
}
```

`written_at` is **informational only and MUST NOT influence any decision.** Freshness is decided by
content hashes alone — a timestamp rule would re-admit the staleness problem the blob key dissolves.

Read-side validation: `version == 1`, both `blob` values match `^([0-9a-f]{40}|[0-9a-f]{64})$` (40
today, 64 leaves room for a SHA-256 repo), both `path` values equal the expected pair. Anything else →
**INVALID → block**.

### 3. `hooks/test-marker-guard.sh` — the gate

PreToolUse, matcher `Bash`. Classification lives in `hooks/lib/classify-commit-command.py`, importable
and unit-tested.

**Which repo.** The toplevel is resolved with `git -C <payload.cwd> rev-parse --show-toplevel`, using
the `cwd` field of the PreToolUse payload — the same field `hooks/context-handoff-watch.sh:45` already
consumes — never the hook process's own cwd. **Measured: outside a repo this exits 128 with empty
stdout**; that is not an error condition but the answer "there is no repo here", and the gate allows,
because git itself will refuse the commit. This is the one status-checked git call that does *not*
route to `MSG_GIT_FAILED`.

The payload `cwd` is the session's cwd, which is the cwd the command *starts* in. It is deliberately
**not** used to follow a `cd` inside the command — see `FOREIGN` below.

**Wire contract — one helper, one line of JSON.** Round 1 split payload parsing from classification
across a two-line `OK`/command protocol. That protocol cannot carry a multi-line bash command or a
free-text exemption reason without a sanitising step at every boundary. One helper reading the payload
and emitting one JSON object removes the desync class instead of defending against it, and is *more*
unit-testable, not less. The four reused fail-open defences survive intact; only the framing changes.

- **stdin:** the raw PreToolUse payload, decoded UTF-8 with `errors="replace"`.
- **stdout:** exactly one line, a JSON object.
- **exit:** `0` whenever it produced a line; **`3` — and only `3` — for an unreadable payload**; any
  other non-zero, or exit 0 with no output, is a broken component. The dedicated code is what makes
  `MSG_BAD_PAYLOAD` and `MSG_CLASSIFIER_FAILED` two distinguishable doors instead of one door with
  two names; round 3 collapsed them by specifying only "non-zero on an unreadable payload".

```json
{ "v": 1, "tool": "Bash", "kind": "COMMIT",
  "form": "PLAIN", "amend": false, "paths": [], "exempt": "" }
```

| field | domain | meaning |
|---|---|---|
| `v` | `1` | schema sentinel — status *and* shape, because three rounds on `judge-guard` showed a status check alone accepts a component that answers and then dies |
| `tool` | string | `tool_name` from the payload; only ever used to settle what an **absent** command means |
| `kind` | `COMMIT` \| `OTHER` \| `NOTHING_RUNNABLE` | `NOTHING_RUNNABLE` = command absent, empty, or only whitespace/control characters |
| `form` | `PLAIN` \| `PATHSPEC` \| `ALL` \| `INCLUDE` \| `UNSUPPORTED` \| `INVALID` \| `FOREIGN` \| `NONE` | see the **ordered** resolution table under §The command grammar rule 4 — first match wins; `NONE` is the value whenever `kind` is not `COMMIT` |
| `amend` | bool | `--amend` present |
| `paths` | list of strings | the pathspec operands; empty unless `form` is `PATHSPEC` or `INCLUDE` |
| `exempt` | the **raw** `TEST_EXEMPT` value, JSON-escaped, or `""` when unset or empty | parsed from the command **string** — a `VAR=x` prefix never reaches a hook's environment. **The classifier does not sanitise it** |

**The contract is total over `kind`, and that totality is the round-5 `api-contracts` fix.** Rounds
1–4 specified the fields for a `COMMIT` and left every other output undefined, while the hook validates
**every field against its domain before it ever consults `kind`** — the flowchart's `CO` node precedes
`E`. A conforming classifier answering a payload like `ls` therefore had no legal value to put in
`form`, and whatever it chose tripped `MSG_CLASSIFIER_BAD_OUTPUT`: the component failing its own
contract on the commonest input it will ever see. Rounds 1–4 each fixed the cell the judge named and
left the rest of the grid undefined, which is why this violation recurred in four different places.
Every cell is now defined:

| field | `kind: COMMIT` | `kind: OTHER` | `kind: NOTHING_RUNNABLE` |
|---|---|---|---|
| `v` | `1` | `1` | `1` |
| `tool` | `tool_name`, verbatim | `tool_name`, verbatim | `tool_name`, verbatim |
| `form` | one of the six commit forms | **`NONE`** | **`NONE`** |
| `amend` | `--amend` present | **`false`** | **`false`** |
| `paths` | operands; `[]` unless `PATHSPEC`/`INCLUDE` | **`[]`** | **`[]`** |
| `exempt` | raw `TEST_EXEMPT`, or `""` | raw `TEST_EXEMPT`, or `""` | **`""`** |

`NONE` is a **value** of `form`, not an absence. No field is ever optional and no field is ever null,
so the hook's domain check needs no per-kind special case — which is what kept re-introducing this
defect. `exempt` is still reported under `OTHER` because `TEST_EXEMPT=x ls` lexes perfectly well and
the hook, not the classifier, decides what an exemption is worth; under `NOTHING_RUNNABLE` there is no
command string to parse one out of, so `""` is the only honest answer.

**Validation order — stated, because the flowchart and the prose disagreed about it.** The hook
applies exactly two checks, in this order:

1. **Shape and domain, at node `CO`, for every payload regardless of `kind`:** output parses as one
   JSON object, `v == 1`, every field present, each inside the domain above, `paths` a list of
   strings, `exempt` a string. Anything else → `MSG_CLASSIFIER_BAD_OUTPUT` → block. This check never
   inspects the *content* of `exempt`.
2. **Exemption validity, at node `H`, only once `kind == COMMIT`:** a non-empty `exempt` must match
   `^[^\x00-\x1f\x7f]{1,200}$`, else **`MSG_BAD_EXEMPT`** — its own door, because a malformed
   exemption reason is a user error, not a broken component. Over-length is rejected, never silently
   truncated: a truncated reason in the exemption log is an unauditable exemption.

Putting the regex at step 1 would let `TEST_EXEMPT=$'a\nb' ls` — a non-commit — block the session,
which is why the order is load-bearing rather than incidental.

**The classifier no longer strips control characters, and this is the round-2 `api-contracts` fix.**
The strip was a leftover from the dead two-line protocol; a JSON string survives a newline intact, so
sanitising bought nothing and made the hook's re-validation unreachable — the edge scenario asserting
a block for a newline-bearing `TEST_EXEMPT` could only pass by breaking the classifier. The contract
is now single-sourced: **the classifier reports, the hook decides.**

Existence is not usability. The two numbered checks above are the **whole** of read-side validation and
are specified once, there — this paragraph deliberately does not restate them. Round 4 carried a second
copy of the validation rules here, and the two copies is how the `exempt` ordering came to be specified
one way in the prose and another way in the flowchart.

**`python3 -I`** at every call site, so a stray `json.py` in the working directory cannot shadow the
helper and block every Bash command.

**The command decides; `tool_name` only settles what an ABSENT command means.** Runnable command →
classify it whatever the tool is called; `NOTHING_RUNNABLE` + `Bash` → block; `NOTHING_RUNNABLE` + any
other tool → allow. Keying the skip on the name instead was a measured regression on that branch.

#### The command grammar — the paragraph rounds 1-3 left unmeasured

Every other claim in this document is measured to an exit code. This one was not, and it is the one
the rest rests on: rounds 1-3 specified the `paths` **field** and never the grammar that fills it.
That omission hid two fail-opens. Measured on git 2.50.1, one throwaway repo per case, all on the
fixture *`foo.sh` committed `v1`, staged `v2`, worktree `v3`; `bar.md` modified in the worktree only*:

| # | command | exit | committed | `HEAD:foo.sh` | what it establishes |
|---|---|---|---|---|---|
| G1 | `git commit -am msg` | 0 | `foo.sh`, `bar.md` | **`v3`** | **Bundles decompose.** `-am` is `-a -m msg` → `ALL`, worktree content. A classifier matching only the tokens `-a`/`--all` calls this `PLAIN`, hashes the index (`v2`), and allows a commit shipping `v3`. |
| G2 | `git commit -m msg foo.sh` | 0 | `foo.sh` | **`v3`** | **A bare operand is a pathspec** — no `--` needed. `PLAIN` would hash `v2` against a commit shipping `v3`. |
| G3 | `git commit --message=msg` | 0 | `foo.sh` | `v2` | `--opt=value` is **one token**, not an operand. `PLAIN`. |
| G4 | `git commit -amHELLO` | 0 | `foo.sh`, `bar.md` | `v3` | A value **attaches to the last flag of a bundle** (subject was `HELLO`). |
| G5 | `git commit -F msg.txt` | 0 | `foo.sh` | `v2` | A value-taking flag **consumes the next token**, which must not be read as a pathspec. `PLAIN`. |
| G6 | `git commit -m 'fix -- thing' foo.sh` | 0 | `foo.sh` | `v3` | A `--` **inside a value is not a separator**. The lexer must never scan for `--` textually. |
| G7 | `git commit -o -m msg -- foo.sh` | 0 | `foo.sh` | `v3` | `-o`/`--only` is `PATHSPEC`-equivalent. |
| G8 | `git commit -a -m msg -- foo.sh` | **128** | none | `v1` | `INVALID`; git commits nothing. |
| G9 | `git commit -am msg -- foo.sh` | **128** | none | `v1` | **`INVALID` too**, so the bundle must be decomposed **before** the `-a`+operand check, not after. |

**The rules the classifier implements, in order:**

0. **Strip wrappers before anything else, and do not invent the list.** The command string reaching a
   `PreToolUse` hook in this environment may already carry a wrapper prefix — RTK rewrites
   `git commit …` into `rtk git commit …` **before** any guard runs. A classifier that matches on a
   leading literal `git` sees `rtk`, calls the payload `kind: OTHER`, and allows: **the gate would be
   dead on arrival, and task 14's arming check would report `ACTIVE` over the top of it.** The set is
   `WRAPPERS` at **`hooks/lib/shell_segments.py:64`** — `("rtk", "time", "eval", "command", "builtin",
   "exec", "nohup")` — imported, never re-spelled here. Three sibling hooks already depend on it:
   `git-guard.sh:31-33`, `doc-guard.sh:119`, and the regression at `judge-guard.test.sh:111-112`.
   Segmentation of a `git add … && git commit …` chain comes from the same module, for the same
   reason: **a second grammar in this file is how the two drift apart.**
1. **Decompose bundles first.** A token matching `^-[A-Za-z]+` is a sequence of short flags. Walk it
   left to right; the first flag that takes a value consumes **the rest of that token** if any
   remains (G4), otherwise **the next token** (G5).
2. **Long options:** `--opt=value` is self-contained (G3); `--opt value` consumes the next token.
3. **Operands:** any token not consumed as a flag or a flag's value is a **pathspec operand**,
   whether or not a `--` preceded it (G2). A literal `--` token ends option parsing; a `--` inside a
   value is not one (G6).
4. **Form — a total function of the command, resolved in this order, first match wins.** Round 5 left
   this as an unordered list holding five of the seven values, with `FOREIGN` defined 160 lines later
   and no position at all, so a command firing two triggers had two legal answers with opposite
   outcomes. **The order is the contract; ties are not resolved by reading order elsewhere.**

   | # | form | trigger | outcome | why it sits here |
   |---|---|---|---|---|
   | 1 | `INVALID` | `-a`/`--all` together with any pathspec operand (G8, G9) | **allow** | **Git itself refuses the command — exit 128, nothing is committed.** Nothing downstream can matter, so this resolves before every block. |
   | 2 | `FOREIGN` | a `cd`, `git -C`, `--git-dir` or `--work-tree` anywhere before the commit | block, `MSG_FOREIGN_REPO` | The target repo is unknowable, so *which* markers to read is unknowable. Telling someone to drop a flag is useless while the gate is reading the wrong repo. |
   | 3 | `UNSUPPORTED` | `-p`/`--patch`, `--interactive`, or **any option not in the whitelist** | block, `MSG_UNSUPPORTED_FORM` | The content is unknowable — see the whitelist rule below. |
   | 4 | `INCLUDE` | `-i`/`--include` or `--pathspec-from-file` | block, `MSG_UNSUPPORTED_FORM` | Kept distinct from `UNSUPPORTED` only so its message can name the specific remedy (drop `-i`). |
   | 5 | `ALL` | `-a`/`--all` with **no** operand | proceed, worktree content | |
   | 6 | `PATHSPEC` | any operand, with or without `--`, including via `-o`/`--only` | proceed, index content | |
   | 7 | `PLAIN` | none of the above | proceed, index content | The default, reached only by exhausting the list. |

   `NONE` is the value whenever `kind` is not `COMMIT`, and is not part of this resolution.

**Value-taking flags must be known by name**, because mis-lexing one turns its value into a phantom
pathspec (G5). Two groups, and the distinction is load-bearing:

- **Consume the next token** (or the bundle remainder): `-m/--message`, `-F/--file`,
  `-c/--reedit-message`, `-C/--reuse-message`, `-t/--template`, `--author`, `--date`, `--cleanup`,
  `--fixup`, `--squash`, `--trailer`, `--pathspec-from-file`.
- **Optional value, attached only** — these must **never** consume the next token, or they would eat
  a pathspec: `-u/--untracked-files`, `-S/--gpg-sign`.

> ⚠️ **UNRESOLVED — user-waived at round 5 (`writing-specs/command-grammar`), decided elsewhere.
> Do not implement rule 2 as written.** Rule 2's unqualified "`--opt value` consumes the next token"
> contradicts the group immediately above it, which names `--untracked-files` and `--gpg-sign` as long
> options that must never consume one. Measured on git 2.50.1:
> `git commit -m msg --untracked-files foo.sh` ships the **worktree** blob, because `foo.sh` is a
> pathspec — so a classifier applying rule 2 literally reports `PLAIN`, hashes the index, and re-opens
> G2, the exact fail-open this section exists to close. The section also does not state how the command
> string becomes tokens, how `git <global-opts> commit` is told from `git commit <opts>` (which
> `FOREIGN`'s `-C` test depends on), or how a `git add … && git commit …` chain is segmented.
>
> **Deferred, not dismissed.** This is the same tokenisation question `hooks/lib/shell_segments.py`
> already answers for `git-guard`, `doc-guard` and `classify-pr-command.py`, and the open defect where
> a redirection after a pathspec becomes a phantom operand is a defect in *that* file. Writing a
> second, independent grammar here is precisely how the two would drift apart — the outcome this
> document's own follow-up list warns about. **The decision is made once, in the shared lexer, and
> this section then cites it rather than restating it.** Implementation of this feature is blocked on
> that decision landing; the rest of the spec is not.

`--pathspec-from-file` is **refused**, not half-supported: it sources operands from a file the hook
would have to read and re-resolve. It joins `INCLUDE` under `MSG_UNSUPPORTED_FORM`.

##### Recognition is a closed whitelist, and the default for a recognised commit is refuse

**Round 6 replaces round 3's "anything it cannot lex allows".** That clause assumed the option grammar
could be enumerated. It cannot — **measured on git 2.50.1, git accepts any *unique* abbreviation of a
long option**:

| spelling | result | what it establishes |
|---|---|---|
| `git commit --amend` | accepted | the full spelling |
| `git commit --amen` / `--ame` / `--am` | **all accepted, and all genuinely amend** (commit count stayed at 2, subject became the new one) | **an exact-spelling table can never be complete.** A classifier keyed to `--amend` sees `--am` as an unknown option. |
| `git commit --allow-em` | **rejected, exit 129** | ambiguous between `--allow-empty` and `--allow-empty-message` — so the rule is *unique* prefix, not *any* prefix. |

The second row is why enumeration fails today; the third is why it also fails *tomorrow*. **Uniqueness
is a property of git's option table, not of the spelling** — an abbreviation that is unique in 2.50.1
becomes ambiguous the moment git adds an option sharing its prefix, so a parser pinned to exact
spellings silently changes meaning across git releases without a line of it being edited.

**Therefore the classifier recognises a closed whitelist of fully-spelled forms and refuses the rest
with `MSG_UNSUPPORTED_FORM`.** Not "parses best-effort and allows on doubt" — every flag in the two
value-taking groups above, in its full spelling, plus the forms named in rule 4; anything else in a
command already recognised as a commit is **unsupported, and unsupported blocks**.

**This also closes `-p`/`--patch` and `--interactive`, which parsing could never have fixed.** Both
select their content *interactively, after* the `PreToolUse` hook has already returned — so there is no
moment at which the hook could inspect what the commit will contain. They are refused on that ground,
not on a lexing one, and no amount of grammar work changes it.

> **Exactly what changed, because "fail-closed" is doing real work here.** The inversion applies **only
> once a commit has been recognised** — a `kind: COMMIT` payload whose options do not lex against the
> whitelist. The genuinely-accepted-open shapes are untouched and stay on their enumerated list: alias
> and variable indirection (§Latency), and anything where no commit is recognised at all. **The gate
> cannot block what it cannot see, and pretending otherwise is the failure mode this note exists to
> prevent.**
>
> **The cost is real and belongs on the record:** a developer using `git commit --am -m msg` gets
> blocked on a valid command. That is the intended trade — a false block is visible and one keystroke
> from resolution via `TEST_EXEMPT`, whereas the fail-open it replaces is invisible by construction and
> ships an unverified commit. **A gate that guesses is worse than one that refuses**, and this feature
> exists because a silent pass is the expensive direction.

#### Which paths, and which content — measured, not assumed

Round 1 had one column here and it was wrong in both directions: it branched *which file it hashed*
without branching *which paths it looked at*, and it routed `git commit -- <path>` — the form this
repo mandates on every commit — down the index branch, where the gate reads content git will not
commit. Every row below was reproduced on git 2.50.1 in a throwaway repo; checklist task 6 turns each
into a test that commits for real rather than simulating.

`<base>` is `HEAD`, with two measured exceptions, both resolving to the empty-tree oid
`4b825dc642cb6eb9a060e54bf8d69288fbee4904`:

- **`HEAD` is unborn** — a repo's first commit. Measured: `git rev-parse --verify HEAD` exits 128 and
  `git diff --cached --name-only HEAD` exits 128 with empty stdout. Without this case the gate would
  turn `MSG_GIT_FAILED` on the very first commit of any repo that installs the writer.
- **`amend: true` and `HEAD^` does not resolve** — amending a root commit; measured: exit 128.
  Otherwise `amend: true` makes `<base>` `HEAD^`.

The base is resolved with `rev-parse --verify`, whose non-zero exit is a **defined answer** here, not
an infrastructure failure.

| `form` | path set | content of a path IN the path set |
|---|---|---|
| `PLAIN` | `git diff --cached --name-only --diff-filter=d <base>` | index blob: `git ls-files --stage -- <path>` |
| `PATHSPEC` (any operand, with or without `--`, incl. `-o`/`--only`) | `git diff --name-only --diff-filter=d <base> -- <paths>` | worktree blob: `git hash-object -- <path>` |
| `ALL` (`-a`/`--all`, **after bundle decomposition**) | `git diff --name-only --diff-filter=d <base>` | worktree blob |
| `INCLUDE` (`-i`/`--include`, `--pathspec-from-file`) | — | — — block, see below |
| `INVALID` (`-a` **and** an operand — G8, G9) | — | — — git itself exits 128 and commits nothing, so the hook allows and lets git refuse |
| `FOREIGN` | — | — — block, see below |

**Every row's trigger is the decomposed flag set from §"The command grammar", never a raw token
match.** `-am` reaching the `ALL` row rather than the `PLAIN` row is the whole point of that section.

**`NONE` has no row here, and that is not a gap.** It cannot reach this table: the hook consults `form`
only after `kind == COMMIT` (the flowchart's `E` precedes `I`), and `NONE` is by definition the value
for every non-`COMMIT` output. The table is total over the forms that reach it — six of the seven
domain values — and the seventh is unreachable by construction rather than undefined by omission.

**Post-commit content of a pair member that is NOT in the path set.** Round 2 defined content only for
paths *in* the path set, while the pairing rule hashes **both** members — so the commonest real case
had no defined answer. The rule is uniform: **the blob the resulting commit's tree will hold.**

| `form` | member outside the path set | why |
|---|---|---|
| `PLAIN` | index blob | the new tree *is* the index |
| `PATHSPEC` | the `<base>` blob | the commit does not touch it |
| `ALL` | the `<base>` blob | **corrected in round 5.** Outside this path set means *unmodified against `<base>`* — the path set is every tracked worktree difference — so the base and worktree blobs are identical here and `-a` changes nothing. Round 4 said "worktree blob for a tracked path" and left the untracked case undefined |

**Why the `ALL` row is stated against `<base>` and not the worktree.** The two blobs are equal for
every path this row can reach, so the choice looks cosmetic and is not: naming the worktree invites a
`hash-object` on any path that happens to be on disk, and **an untracked file is on disk without ever
entering the commit.** Measured on git 2.50.1: with `note.txt` untracked, `git commit -am y` produces a
tree with no entry at `note.txt`. Naming `<base>` makes the untracked case fall out of the rule rather
than needing a clause — which is exactly the difference between a total table and one with a guard on
its last row.

**Measured (M4):** with `foo.sh` and `foo.test.sh` both modified in the worktree,
`git commit -m x -- foo.sh` yields `HEAD:foo.test.sh` = the **old** content, while the worktree holds
the new one, and the two blobs differ. So a pair whose test was edited but not committed is compared
against the base blob and **blocks with `MSG_STALE_TEST`** — correct and fail-closed: the shipped
combination of new subject and old test is one no suite run ever certified.

**ABSENT is a defined result, not a git failure.** Rounds 3 and 4 each wrote a probe table and each
had a cell that disagreed with the principle the table was supposed to implement — round 3 probed
`<base>` unconditionally, round 4 probed the *disk* under `ALL` and so reported an untracked file
present. The round-5 fix is to stop treating the probes as the rule. There is **one** definition:

> A pair member is **ABSENT** iff **the resulting commit's tree will have no entry at its path.**

The probes below are *implementations* of that sentence for each content source, and a probe that ever
disagrees with it is a defect in the probe. Stating the semantics separately from the mechanics is what
makes the next case derivable instead of needing another round:

| content source | ABSENT iff | covers |
|---|---|---|
| index blob (`PLAIN`, any member) | `git ls-files --stage -- <path>` prints nothing | untracked (no index entry) and staged-for-deletion (entry removed) |
| worktree blob (`PATHSPEC`, member *in* the pathspec) | the path does not exist on disk | a pathspec naming a deleted file commits the deletion |
| `<base>` blob (`PATHSPEC`, member *outside* the pathspec) | `git cat-file -e <base>:<path>` exits non-zero — **and nothing else** | untracked → no base entry → ABSENT. Disk and index are irrelevant here (M5) |
| `<base>` blob (`ALL`, member *outside* the path set) | `git cat-file -e <base>:<path>` exits non-zero **or** the path does not exist on disk | untracked → no base entry → ABSENT; tracked but deleted in the worktree → `--diff-filter=d` keeps it out of the path set while `-a` still stages the deletion → ABSENT |

The `ALL`-outside row is the only two-condition cell, and it is two conditions because two different
states produce an empty tree entry there. Round 4's single disk check got the first wrong; round 3's
single base check got the second wrong. Enumerating both is what closes the pair.

**Measured (M5) — why the two `<base>` rows cannot share a condition.** Rounds 3–5 wrote them as one
row carrying the disk clause, which is right for `ALL` and **wrong for `PATHSPEC`**, where it produces
a false *block*. Four cases on git 2.50.1, base tree `foo.sh`, `bar.md`, `gone.md`:

| # | form | state of `gone.md` | in the resulting tree? | correct verdict |
|---|---|---|---|---|
| A | `git commit -m x -- foo.sh` | deleted on disk, **not** staged | **yes** | not ABSENT |
| B | `git commit -m x -- foo.sh` | deletion **staged** (`git rm --cached`) | **yes** | not ABSENT |
| C | `git commit -a -m x` | deleted on disk, not staged | no | ABSENT (base present, disk missing) |
| D | `git commit -a -m x` | *untracked* file present on disk | no | ABSENT (base missing, disk present) |

A and B are the correction: the pathspec form builds its tree from `<base>` **plus the named paths**,
consulting neither the worktree nor the index for anything else — so a member outside the pathspec
survives into the commit even when its deletion is already staged. Under the merged row the gate would
have called `gone.md` ABSENT and blocked with `MSG_STALE_TEST` on a pair whose test the commit
preserves byte-for-byte at the version the marker certifies. C and D are why `ALL` keeps both
conditions: each disjunct is the only one that catches its case.

Under `ALL`, a member **in** the path set needs no ABSENT case at all: `--diff-filter=d` has already
removed deletions, so every path the collector returns exists on disk.

ABSENT means the pair cannot be certified: the door is `MSG_STALE_SUBJECT` / `MSG_STALE_TEST`, *not*
`MSG_GIT_FAILED`. The gate never calls `hash-object` on a path it has already found ABSENT, which is
what kept the `ALL` case out of the wrong door. Only an unexpected failure of a collection or hashing
command is infrastructure.

What each row is defending, with the measurement:

- **`PATHSPEC` content.** Index `v2`, worktree `v3`, then `git commit -m x -- foo.sh` → `git show
  HEAD:foo.sh` is **`v3`**. Round 1 would have hashed `v2`, matched the marker, and allowed a version
  no test ever saw — a silent fail-open in the repo's own house style.
- **`PATHSPEC` path set.** A pathspec also *narrows*: with `foo.sh` staged, `git commit -m x -- bar.md`
  commits **`bar.md` only**, while the index collector returns `foo.sh` and would have raised a false
  block on a file not being committed. `git diff <base> -- <paths>` returns exactly `bar.md`.
- **`PATHSPEC` on an unchanged file.** `git commit -m x -- foo.sh bar.md` with `foo.sh` identical to
  HEAD commits `bar.md` only, and the collector returns `bar.md` only. No false block from a broad
  pathspec such as `-- hooks/`.
- **`ALL` path set.** With a never-staged worktree edit, `git diff --cached --name-only` returns
  **zero paths** while the commit contains the file. Round 1's collection would have found no pairs
  and allowed — the `-a` scenario it wrote was unreachable against its own collector.
- **`amend` base.** Staging a sidecar and amending: `git diff --cached <base=HEAD>` returns the
  sidecar alone, `<base=HEAD^>` returns the sidecar **and** the file from the amended commit, which
  is exactly the amended commit's contents. All three collecting forms combine with `--amend`
  unchanged; `--amend` alters only the base.

**`INCLUDE` (`-i`/`--include`) — a fail-open found by re-measurement, now closed.** `-i` commits the
staged contents *plus* the named paths. **Measured (M3):** with `a.sh` staged at `v2`,
`git commit -m x -i -- b.md` commits **both** files and `git show HEAD:a.sh` is `v2`, while the
`PATHSPEC` collector returns `b.md` alone — the gate would have missed `a.sh` entirely. `-i` also lexes
cleanly, so the accepted-open clause never covered it.

The path set for `-i` is a union of two collectors with a different content source on each side. That
is real complexity for a flag this repo's house style never uses, and the wrong trade for a momentum
guardrail — so `form: INCLUDE` **blocks** with `MSG_UNSUPPORTED_FORM`, whose message says to drop `-i`
or set `TEST_EXEMPT`. Same fail-closed precedent as `FOREIGN`: when the gate cannot cheaply and
certainly say what a commit contains, it refuses rather than guesses.

**`FOREIGN` — which repo is this commit for?** A PreToolUse hook sees `cd /other/repo && git commit
-m x` as one command string and cannot follow the `cd`; resolving `--show-toplevel` from the payload
`cwd` would read a different repo's index and a different repo's markers, and both allowing and
blocking on that basis would be wrong. The classifier reports `form: FOREIGN` when the command
contains a `cd`, a `git -C`, `--git-dir`, or `--work-tree` anywhere before the commit, and the hook
**blocks** with `MSG_FOREIGN_REPO`, whose message says to run the commit as its own command from the
target repo or to set `TEST_EXEMPT`.

**`TEST_EXEMPT` is checked before `FOREIGN`, and that ordering is load-bearing.** Round 2's flowchart
blocked `FOREIGN` without ever reaching the exemption node while the prose advertised `TEST_EXEMPT` as
the escape — the message told the user to do something the control flow made impossible. The
exemption now sits ahead of every form decision, so it is a true universal escape.

**Accepted cost, stated rather than discovered:** `cd "$HOME/.claude" && git commit …` is the *same*
repo but still classifies `FOREIGN`, so it false-blocks. The remedy is in the message (run the commit
as its own command) and `TEST_EXEMPT` now genuinely reaches it. Following the `cd` — resolving its
literal argument and comparing toplevels — is deliberately rejected: it re-introduces exactly the
"follow the shell" reasoning this design refuses, and it fails on any non-literal target.

**Pairing rule.** The unit is the `(subject, test)` pair, not the single file. If **either** member is
in the path set, that pair needs a valid marker whose two blobs equal the post-commit content of both
members. Pairing on the file alone would let a test file ship at a version that was never run.

**Pair formation — the predicate, stated.** Rounds 1–5 asserted "any path with a sibling test" and
never said what *has a sibling test* means, which left two passages in this document disagreeing:
§Scope says a file with no sibling test is never gated, while the `-am` scenario below forms a pair
with a test that is **untracked**. Both are right; the rule that makes them consistent is in two steps
and is **asymmetric by direction**.

*Step 1 — classify the path.* Ordered, first match wins, against the basename of the repo-relative
path. The order is what stops `foo.test.sh` falling through to the `.sh` arm:

| # | basename ends | role | derived sibling |
|---|---|---|---|
| 1 | `.test.sh` | test | strip `.test.sh`, append `.sh` |
| 2 | `.test.py` | test | strip `.test.py`, append `.py` |
| 3 | `.sh` | subject | strip `.sh`, append `.test.sh` |
| 4 | `.py` | subject | strip `.py`, append `.test.py` |
| 5 | anything else | — | **forms no pair** |

Every path gets exactly one role, so a path is never both a subject and a test.

*Step 2 — does the derived sibling exist?* The source differs by direction, and the difference is
**satisfiability**, not fastidiousness:

- **Subject in the path set → its test.** Exists iff the test is in the index (`git ls-files
  --error-unmatch -- <test>` exits 0) **or** present on disk. The union is fail-closed: an untracked
  test on disk resolves to ABSENT and blocks, because the tree will not contain the file the marker
  was written against. The remedy is `git add <test>`, so the block is always clearable — and the
  writer will have written a marker, since a subject in the path set is by construction in the index.
- **Test in the path set → its subject.** Exists iff the subject is **in the index**. Index only,
  mirroring the writer's `--error-unmatch` check exactly. Widening this half to the union would be a
  live defect: the writer refuses to write a marker for an untracked subject, so the gate would demand
  a marker nothing can produce and block that commit forever, with `MSG_NO_MARKER`'s remedy re-running
  a suite that correctly writes nothing. The two orphan suites are never gated for this reason, and
  they must stay ungated even if someone drops an untracked `panes/adapters.sh` into the tree.

*Step 3 — the pair set is a set.* When both members are in the path set the pair is formed once, not
twice, and its marker is checked once.

**Every git invocation is status-checked**, apart from the calls below, whose non-zero or empty
result is a **defined answer** rather than a failure. Round 3 said "apart from the two" and was
already off by one; the set is enumerated here so the next count does not have to be guessed:

1. `rev-parse --show-toplevel` from the payload cwd — non-zero means "no repo here" → allow.
2. `rev-parse --verify HEAD` / `HEAD^` — non-zero means unborn or root → `<base>` is the empty tree.
3. `ls-files --stage -- <path>` — empty output means ABSENT under an index source.
4. `cat-file -e <base>:<path>` — non-zero means ABSENT under a base source.

The worktree ABSENT test is a plain file-existence check and runs no git at all. Measured on git
2.50.1: outside a repo, `git diff --cached --name-only` prints **nothing on stdout** and exits
**129** — not the 128 rounds 1–5 recorded, and not for the reason they gave. With no repo, `git diff`
falls back to `--no-index`, whose option table has no `--cached`, so the failure is `error: unknown
option 'cached'` plus a usage dump **on stderr** — a usage error, not "not a git repository". The
distinction matters twice: 128 is the code the *other* three probes in this list return, so recording
129 as 128 collapses two different failures into one; and the usage dump means a caller that logs
stderr sees a wall of text rather than a diagnosable line. What survives the correction is the hazard
itself — stdout is empty either way, so any caller reading only stdout cannot tell this apart from
"no files to check" and will allow. That is `judge-guard` fail-open #3 reborn in the one subsystem
this hook adds. A non-zero exit from any other
collection or hashing command → `MSG_GIT_FAILED` → block. Never pipe one of these into another
command: the pipeline's status is the last stage's.

#### Latency

Every Bash tool call pays this hook. The observability judge measured the existing PreToolUse chain at
**~373 ms** and `python3` startup at **≥56 ms**, so spawning the classifier unconditionally would tax
every `ls` in the session.

A **cheap bash pre-filter runs before any `python3`**: if the **raw payload text** does not contain
the substring `commit`, the hook exits 0 immediately.

**It filters the raw payload, not the parsed command, and that distinction is the round-3 fix.** The
classifier is the sole payload parser, so a pre-filter working on "the command" would have to parse
the payload to find one — the thing it exists to avoid. Round 3 wrote the filter over the command and
placed it after the runnable check, which made `MSG_NOTHING_RUNNABLE` unreachable: an absent or empty
command contains no `commit` substring, so the filter would have allowed before the door could fire.

Filtering the raw payload keeps that door reachable and honest. `MSG_NOTHING_RUNNABLE` now fires
exactly when the payload mentions `commit` **and** the parsed command is absent, empty, or only
whitespace — which is precisely the mis-parse case the door exists for. A payload with nothing
runnable and no `commit` anywhere is allowed, correctly: nothing in it can commit.

The filter skips only commands that could not classify as `COMMIT`, except for shapes already on the
accepted-open list (alias and variable indirection).

**Budgets — targets, not measurements; checklist task 10 measures and records all three:**

| payload | budget | what it pays for |
|---|---|---|
| no `commit` substring anywhere | **≤5 ms** | pure bash, no subprocess — the pre-filter exits 0 |
| mentions `commit` but is not one (`kind: OTHER` or `NOTHING_RUNNABLE`) | **≤80 ms** | one `python3 -I` start (measured ≥56 ms) plus classification; no git calls |
| an actual `git commit` | **≤150 ms** | the above plus the collection and hashing calls |

**The middle row is new in round 5**, and it exists *because* the contract became total: `kind: OTHER`
is now a defined and plainly reachable output — `echo "commit this"` and `git log --grep commit` both
land there — and an output with no budget is a cost nobody measures. If a measured figure exceeds its
budget, the number gets recorded and the budget revised; it does not get quietly dropped.

## Scenarios

### Correct behaviour

```gherkin
Scenario: fresh marker allows the commit
  Given hooks/foo.sh has a sibling hooks/foo.test.sh
    And the suite passed against the current content of both
   When "git commit -m msg" is staged with hooks/foo.sh
   Then the hook exits 0

Scenario: a repo that has not installed the writer is never gated
  Given a repo with hooks/bar.sh and hooks/bar.test.sh and no marker
    And that repo has no hooks/lib/write-test-marker.py
   When "git commit -m msg" runs there
   Then the hook exits 0
   # global registration without this check would lock out every such repo

Scenario: a file with no sibling test is never gated
  Given docs/notes.md is staged and has no sibling test
   When "git commit -m msg" runs
   Then the hook exits 0

Scenario: partial staging is not a false block
  Given the suite passed against hooks/foo.sh
    And hooks/foo.sh is staged while other files are modified but unstaged
   When "git commit -m msg" runs
   Then the hook exits 0
   # staged ⊆ tested; this is why the key is per-file blobs, not a whole-tree hash

Scenario: untracked scratch files are irrelevant
  Given the suite passed against hooks/foo.sh and a scratch file was written afterwards
   When "git commit -m msg" runs with hooks/foo.sh staged
   Then the hook exits 0

Scenario: a pathspec narrows the gate to what is actually being committed
  Given hooks/foo.sh is staged with no marker
    And docs/notes.md is modified and has no sibling test
   When "git commit -m msg -- docs/notes.md" runs
   Then the hook exits 0
   # index-based collection would have demanded a marker for a file this commit does not touch

Scenario: a pathspec covering an unchanged sibling-tested file does not block
  Given hooks/foo.sh is identical to HEAD and has no marker
    And hooks/bar.md is modified
   When "git commit -m msg -- hooks/" runs
   Then the hook exits 0

Scenario: an orphan suite is never gated
  Given panes/adapters.test.sh is staged and panes/adapters.sh does not exist
   When "git commit -m msg" runs
   Then the hook exits 0
   # no derivable subject means no pair; the writer likewise skips it and leaves the suite green

Scenario: a commit outside any repository is left to git
  Given the payload cwd is not inside a git repository
   When "git commit -m msg" runs
   Then the hook exits 0
   # measured: rev-parse --show-toplevel exits 128 with empty stdout; git will refuse the commit

Scenario: the first commit in a writer-installed repo is not a git failure
  Given a repo with the writer installed, HEAD unborn, and hooks/foo.sh staged with a marker
   When "git commit -m msg" runs
   Then the hook exits 0
   # measured: rev-parse --verify HEAD and git diff --cached HEAD both exit 128 on an
   # unborn HEAD; without the empty-tree base this would block every repo's first commit
```

### Incorrect behaviour the gate must catch

```gherkin
Scenario: no marker at all
  Given hooks/foo.sh is staged and its suite has never been run
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_NO_MARKER naming hooks/foo.sh and "bash hooks/foo.test.sh"

Scenario: the remedy names the right interpreter for a Python pair
  Given hooks/lib/classify-pr-command.py is staged with no marker
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_NO_MARKER naming "python3 hooks/lib/classify-pr-command.test.py"
   # the remedy is derived from the suite's extension, never hardcoded to bash

Scenario: the subject changed after the run
  Given the suite passed, then hooks/foo.sh was edited and staged
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_STALE_SUBJECT

Scenario: a test version that was never run is being shipped
  Given the suite passed against hooks/foo.test.sh v1
    And hooks/foo.test.sh was then edited to v2 and staged without re-running
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_STALE_TEST

Scenario: a pathspec commit is gated on worktree content, not the index
  Given the suite passed against hooks/foo.sh v1
    And hooks/foo.sh v1 is staged, then edited to v2 in the worktree without staging
   When "git commit -m msg -- hooks/foo.sh" runs
   Then the hook exits 2 with MSG_STALE_SUBJECT
   # measured: this commit ships v2; reading the index would compare v1 and wrongly allow

Scenario: a pair member left outside the pathspec is compared against base, not the worktree
  Given the suite passed against hooks/foo.sh v2 and hooks/foo.test.sh v2
    And both are modified in the worktree and neither is staged
   When "git commit -m msg -- hooks/foo.sh" runs
   Then the hook exits 2 with MSG_STALE_TEST
   # measured (M4): the commit ships foo.sh v2 alongside the OLD foo.test.sh, a combination
   # no suite run certified; the marker's test blob is compared against the base blob

Scenario: git commit -a does not escape the gate
  Given the suite passed, then hooks/foo.sh was edited but never staged
   When "git commit -a -m msg" runs
   Then the hook exits 2 with MSG_STALE_SUBJECT
   # measured: "git diff --cached" returns zero paths here, so the path set must come from
   # "git diff HEAD" or the gate finds no pairs and allows

Scenario: a bundled -am is decomposed and does not escape the gate
  Given the suite passed, then hooks/foo.sh was edited but never staged
   When "git commit -am msg" runs
   Then the hook exits 2 with MSG_STALE_SUBJECT
   # measured G1: -am is -a -m msg and ships the WORKTREE blob; a classifier matching only the
   # literal tokens -a/--all reads this as PLAIN, hashes the index, and allows

Scenario: a pathspec with no -- separator is still a pathspec
  Given the suite passed against hooks/foo.sh v1
    And hooks/foo.sh v1 is staged, then edited to v2 in the worktree without staging
   When "git commit -m msg hooks/foo.sh" runs
   Then the hook exits 2 with MSG_STALE_SUBJECT
   # measured G2: this ships the worktree blob; PLAIN would hash the index and allow

Scenario: a flag value is never mistaken for a pathspec
  Given hooks/foo.sh is staged with a valid marker
    And a file msg.txt exists in the worktree
   When "git commit -F msg.txt" runs
   Then the hook exits 0 and the path set does not contain msg.txt
   # measured G5: -F consumes msg.txt as the message file; treating it as an operand would
   # switch the form to PATHSPEC and hash the wrong source

Scenario: a -- inside a message value is not an operand separator
  Given the suite passed against hooks/foo.sh and its sibling
   When "git commit -m 'fix -- thing' hooks/foo.sh" runs
   Then the hook exits 0 and the path set is exactly hooks/foo.sh
   # measured G6: textual scanning for -- would split the command in the wrong place

Scenario: a bundled -a with a pathspec is left to git
  Given any staged state
   When "git commit -am msg -- hooks/foo.sh" runs
   Then the hook exits 0
   # measured G9: git exits 128 and commits nothing, exactly as for the unbundled form, so
   # the bundle must be decomposed BEFORE the -a-plus-operand check

Scenario: git commit -i does not sweep an untested staged file past the gate
  Given hooks/foo.sh is staged with no marker
    And docs/notes.md is modified and has no sibling test
   When "git commit -m msg -i -- docs/notes.md" runs
   Then the hook exits 2 with MSG_UNSUPPORTED_FORM
   # measured (M3): -i commits the staged hooks/foo.sh too, while a pathspec collector
   # returns docs/notes.md alone — a fail-open that lexes cleanly

Scenario: an amend re-commits a file from the amended commit at an untested version
  Given hooks/foo.sh was committed, then edited and staged
    And the suite has not been re-run
   When "git commit --amend --no-edit" runs
   Then the hook exits 2 with MSG_STALE_SUBJECT
   # measured: the amended commit's contents are "git diff --cached HEAD^", not HEAD

Scenario: a commit aimed at another repo cannot be verified, so it blocks
  Given hooks/foo.sh has a valid marker in this repo
   When "cd /other/repo && git commit -m msg" runs
   Then the hook exits 2 with MSG_FOREIGN_REPO
```

### Edges

```gherkin
Scenario: a corrupt marker fails closed
  Given the marker for hooks/foo.sh is truncated, empty, or wrong-shaped
   When "git commit -m msg" runs with hooks/foo.sh staged
   Then the hook exits 2 with MSG_BAD_MARKER
   # existence is not usability — the lesson from four fail-opens on judge-guard

Scenario: a git failure is never read as "nothing to check"
  Given a collection command exits non-zero with empty stdout
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_GIT_FAILED

Scenario: a classifier that answers with the wrong shape fails closed
  Given classify-commit-command.py prints valid JSON whose "v" is not 1
   When the hook runs
   Then it exits 2 with MSG_CLASSIFIER_BAD_OUTPUT

Scenario: an exemption reason carrying control characters is rejected
  Given the command sets TEST_EXEMPT to a value containing a newline
   When the hook runs
   Then it exits 2 with MSG_BAD_EXEMPT
   # the classifier reports the value raw and the hook decides; this door is reachable
   # precisely because the classifier no longer strips

Scenario: an over-long exemption reason is rejected, not truncated
  Given the command sets TEST_EXEMPT to a 201-character value
   When the hook runs
   Then it exits 2 with MSG_BAD_EXEMPT
   # a truncated reason in the exemption log is an unauditable exemption

Scenario: an empty exemption is not an exemption
  Given hooks/foo.sh is staged with no marker
   When "TEST_EXEMPT= git commit -m msg" runs
   Then the hook exits 2 with MSG_NO_MARKER

Scenario: a deletion needs no test run
  Given hooks/foo.sh and hooks/foo.test.sh are both staged as deletions
   When "git commit -m msg" runs
   Then the hook exits 0

Scenario: a rename is gated at its new path only
  Given hooks/foo.sh is staged as a rename to hooks/foo2.sh
   When "git commit -m msg" runs
   Then the path set contains hooks/foo2.sh and not hooks/foo.sh
   # measured: --diff-filter=d drops the D half of the rename and keeps the A half

Scenario: half a pair is deleted while the other half changes
  Given hooks/foo.sh is staged as a modification
    And hooks/foo.test.sh is staged as a deletion
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_STALE_TEST
   # the test resolves to ABSENT, so the pair cannot be certified; deleting BOTH passes instead

Scenario: an absent base blob is a stale door, not a git-failure door
  Given hooks/foo.sh is staged as a new file with a sibling test that is not in the pathspec
    And that test does not exist in <base>
   When "git commit -m msg -- hooks/foo.sh" runs
   Then the hook exits 2 with MSG_STALE_TEST and not MSG_GIT_FAILED
   # cat-file -e answering "no" is a defined result; only unexpected git failures are infrastructure

Scenario: -a combined with a pathspec is left to git
  Given any staged state
   When "git commit -a -m msg -- hooks/foo.sh" runs
   Then the hook exits 0
   # measured: git itself exits 128 with "paths ... with -a does not make sense" and commits nothing

Scenario: an explicit exemption is honoured and logged to a file
  Given hooks/foo.sh is staged with no marker
   When "TEST_EXEMPT=vendored upstream git commit -m msg" runs
   Then the hook exits 0
    And one EXEMPT line is appended to <repo>/hooks/state/test-marker.log
   # parsed out of the command STRING — a VAR=x prefix never reaches a hook's environment

Scenario: an exemption rescues a foreign-repo commit
  Given the command targets another repo
   When "TEST_EXEMPT=other repo cd /other/repo && git commit -m msg" runs
   Then the hook exits 0
    And one EXEMPT line is appended to <repo>/hooks/state/test-marker.log
   # the exemption check precedes the form decision; round 2's order made this unreachable
   # while MSG_FOREIGN_REPO's own message recommended it

Scenario: a block is logged with the message constant that fired
  Given hooks/foo.sh is staged with no marker
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_NO_MARKER
    And one BLOCK line naming MSG_NO_MARKER is appended to <repo>/hooks/state/test-marker.log
   # rounds 1-5 logged exemptions only, so "does this gate ever fire" had no answer at all

Scenario: an allowed commit writes no log line
  Given docs/notes.md is staged and has no sibling test
   When "git commit -m msg" runs
   Then the hook exits 0
    And <repo>/hooks/state/test-marker.log is unchanged
   # logging every allow would bury the two rates the log exists to expose

Scenario: a Bash payload that mentions commit but has nothing runnable blocks
  Given a Bash payload that contains the substring "commit" somewhere
    And whose command field is absent, empty, or only whitespace/control characters
   When the hook runs
   Then it exits 2 with MSG_NOTHING_RUNNABLE
   # the pre-filter reads the RAW PAYLOAD, so this door stays reachable; filtering on the
   # parsed command would allow here and make the door, its scenario and its mutant dead

Scenario: a Bash payload with nothing runnable and no commit anywhere is allowed
  Given a Bash payload with an empty command and no "commit" substring
   When the hook runs
   Then it exits 0
   # nothing in it can commit; paying python3 to confirm that would tax every Bash call

Scenario: a classifier that cannot read the payload is not confused with a broken one
  Given classify-commit-command.py exits 3
   When the hook runs
   Then it exits 2 with MSG_BAD_PAYLOAD and not MSG_CLASSIFIER_FAILED
   # the dedicated exit code is what keeps these two doors distinguishable

Scenario: a member staged for deletion is ABSENT under an index source
  Given hooks/foo.sh is staged as a modification with a valid marker
    And hooks/foo.test.sh is staged as a deletion
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_STALE_TEST
   # PLAIN's content source is the index, so the ABSENT probe is "ls-files --stage prints
   # nothing"; probing <base> instead would pass and allow a commit whose tree drops the test

Scenario: an untracked pair member is ABSENT under -a, never hashed from disk
  Given hooks/foo.sh is tracked, modified, and covered by a valid marker
    And hooks/foo.test.sh is UNTRACKED and present on disk
   When "git commit -am msg" runs
   Then the hook exits 2 with MSG_STALE_TEST
   # measured on git 2.50.1: -a does not add an untracked file, so the resulting tree holds no
   # entry for it. Round 4's disk probe reported it present and hashed a blob the commit will
   # never contain — the gap that made ABSENT a semantic definition rather than three probes

Scenario: a payload that mentions commit without being one is fully classified and allowed
  Given a Bash payload whose command is: echo "commit this"
   When the hook runs
   Then the classifier reports kind OTHER with form NONE, and the hook exits 0
   # the substring pre-filter cannot rule this out, so the contract must define every field for
   # a non-commit; form NONE is a value, and a classifier emitting null here would trip
   # MSG_CLASSIFIER_BAD_OUTPUT on the commonest input the gate sees

Scenario: a malformed TEST_EXEMPT on a non-commit does not block
  Given a Bash payload that sets TEST_EXEMPT to a value containing a newline
    And whose command is not a commit
   When the hook runs
   Then it exits 0
   # the exempt regex is checked at node H, only once kind is COMMIT; folding it into shape
   # validation would let any non-commit carrying a stray TEST_EXEMPT block the session

Scenario: a non-Bash tool with no command passes
  Given an Edit payload with no command field
   When the hook runs
   Then it exits 0

Scenario: a suite run from a subdirectory writes a key the gate can find
  Given "bash adapters/cmux-layout.test.sh" is run from inside panes/
   When the suite passes and writes its marker
   Then the marker key is panes%2Fadapters%2Fcmux-layout.sh
   # measured: $0 is "adapters/cmux-layout.test.sh" there; without git ls-files --full-name
   # normalisation the marker lands under a key the gate never looks up

Scenario: a suite that cds still writes a findable marker
  Given a suite that runs "cd $TMP" at top level before its tally
   When it passes and writes its marker
   Then the key is derived from the values captured before the cd
   # measured: hooks/judge-guard.test.sh:13 does exactly this — 1 of the 11 existing suites
```

## Fail-closed contract

Scoped honestly, because RUN 4 and RUN 5 both caught this hook family overclaiming coverage in its own
header.

**These block:** missing or unusable `python3`; an unreadable payload; a missing, empty, truncated,
unreadable, or wrong-output classifier; a malformed or over-long `TEST_EXEMPT` value; an
`-i`/`--include` or `--pathspec-from-file` commit; **a non-zero exit from any git command the gate runs
except the four whose result is a defined answer**; an unreadable or malformed marker; a stale subject or test blob; a commit whose target
repository cannot be determined; a Bash payload with nothing runnable.

**These do not, and are accepted:** command shapes the classifier cannot lex (quoted substitution
`X="$(git commit …)"`, backticks, `eval`, function/alias indirection, path-qualified `/usr/bin/git`,
and the `sudo`/`env`/`timeout` wrapper denylist gap); a **hanging** helper, which needs a timeout and is
deferred; any write that does not arrive as a Bash `git commit`; any repo without the writer installed;
`panes/adapters/cmux.sh`, which no naming-conforming suite claims.

### The doors

`exit 2` is not one door. Round 1 stated that rule and then named five constants against at least
eight implied doors. Round 2 named eleven — **and miscounted its own table: `MSG_STALE_SUBJECT` and
`MSG_STALE_TEST` shared one row but are two distinct doors with two distinct scenarios.** The true
figure was twelve; with the two this round adds it is **fourteen**.

| # | constant | fires when |
|---|---|---|
| 1 | `MSG_BAD_PAYLOAD` | the classifier exits **3** — the PreToolUse payload does not parse |
| 2 | `MSG_NOTHING_RUNNABLE` | `Bash` payload with no runnable command |
| 3 | `MSG_NO_PYTHON` | `python3` missing or not executable |
| 4 | `MSG_CLASSIFIER_MISSING` | the classifier file is absent or unreadable |
| 5 | `MSG_CLASSIFIER_FAILED` | the classifier exits non-zero **other than 3**, or exits 0 printing nothing |
| 6 | `MSG_CLASSIFIER_BAD_OUTPUT` | output is not one JSON object passing every field check |
| 7 | `MSG_BAD_EXEMPT` | a non-empty `TEST_EXEMPT` fails `^[^\x00-\x1f\x7f]{1,200}$` |
| 8 | `MSG_UNSUPPORTED_FORM` | `form: INCLUDE` — `-i`/`--include` **or `--pathspec-from-file`** — **or `form: UNSUPPORTED`: `-p`/`--patch`, `--interactive`, or any option outside the whitelist.** The gate will not guess at contents it cannot see. The message names which of the two applies, since the remedies differ |
| 9 | `MSG_FOREIGN_REPO` | the commit's target repository cannot be determined |
| 10 | `MSG_GIT_FAILED` | an unexpected non-zero exit from a collection or hashing command |
| 11 | `MSG_NO_MARKER` | a pair is in the path set with no marker file |
| 12 | `MSG_BAD_MARKER` | the marker exists but fails schema or path validation |
| 13 | `MSG_STALE_SUBJECT` | the marker is valid but the subject blob does not match |
| 14 | `MSG_STALE_TEST` | the marker is valid but the test blob does not match, or the test is ABSENT |

**Each row names its trigger, and no row restates a rule specified elsewhere — the round-5 structural
fix.** Rows 1 and 5 partition the classifier's exit codes and are now the *only* place that mapping
appears; round 4 kept a second copy in §3's prose, the two disagreed about exit 3, and the table held
the stale one. Row 8's trigger is `form: INCLUDE`, so adding a form to that door is a change to the
resolution table, not to this one. **Anything a reviewer would otherwise have to keep in sync by hand
lives in exactly one table, with the others pointing at it.** Four rounds of this violation were all
the same shape: two copies of one rule, edited singly.

The suite asserts **the message, not just the code** — mutation testing on `judge-guard` showed 48
assertions that could not tell one door from another, and a mutant survived a happy 101/0 suite.

**The allow paths need mutants too**, and round 2's floor covered only doors — a gate that wrongly
*allows* is this control's whole failure mode. Round 3 said seven while its own flowchart had nine
edges; counted off the diagram, the **nine** are: the pre-filter finding no `commit`; a non-Bash tool
with no command; a non-`COMMIT` command; no repository; a repo without the writer; a valid
`TEST_EXEMPT`; `INVALID`; a path set containing no pairs; and the happy path where every blob matches.

**Mutation floor: 24** — one per door (14), one per allow path (9), plus emptying the classifier. A
two-mutant minimum against fourteen doors establishes nothing about the other twelve.

`MSG_NO_MARKER`'s remedy string is derived from the suite path and its extension — `bash <path>` for
`.sh`, `python3 <path>` for `.py` — never hardcoded to `bash`.

**Decision logging — exemptions *and* blocks.** Rounds 1–5 logged only exemptions, which answers "how
often is this gate bypassed" and leaves "does this gate ever fire at all" unanswerable. Those are the
same question about the same control, so they share one file: `<repo>/hooks/state/test-marker.log`,
one tab-separated line per non-trivial decision.

| field | value |
|---|---|
| 1 | ISO-8601 UTC timestamp |
| 2 | `EXEMPT` or `BLOCK` |
| 3 | the validated `TEST_EXEMPT` reason, or the `MSG_*` constant that fired |
| 4 | the pairs skipped (`EXEMPT`) or the pair that failed (`BLOCK`) |

Allowed commits are **not** logged: every `git commit` in a covered repo would append a line, the
signal would drown, and the questions above are both about the non-allow cases. A single file with a
decision column rather than two parallel logs — the two records carry the same four fields, and the
rate that matters is exemptions *as a fraction of* blocks.

`hooks/test-marker-guard.sh --status` prints the count of each decision alongside `ACTIVE`/`INERT`. A
log nothing reads is the same defect as no log, one indirection further away, and `--status` is
already the command task 14 runs and `hooks/README.md` points at.

**What this log is, and is not — the storage decision, made explicitly.** It is **machine-local**:
`/hooks/state/` is gitignored at `.gitignore:17`, so the log is never committed, never shared, and
never survives a fresh clone. That is deliberate, not an oversight to be fixed later:

- Committing it would make every developer's bypass history a merge-conflict generator on a file with
  no merge semantics, and would publish local paths and free-text reasons into repo history.
- What it therefore delivers is **self-audit and a rate signal** — enough to answer "am I leaning on
  `TEST_EXEMPT` weekly or hourly", which is the erosion path the control exists to catch.
- What it does **not** deliver is organisational assurance. Nobody else can read it, and a developer
  who wants to hide a bypass can delete it. It is instrumentation, not evidence, and any later claim
  that this feature provides an audit trail should be read against this paragraph.

**Both the log and its parent directory carry explicit modes: `<repo>/hooks/state/` is `0700` and
`test-marker.log` is `0600`** — identical to the marker store two sections up, and for the same
core-conduct default-deny reason. Round 5 gave the marker store its modes on those grounds and left
this pair to the ambient umask, which on a permissive one publishes a trail naming every commit
someone chose to bypass the gate for. **This feature creates `hooks/state/` — it does not exist in this
repo today — so whichever component runs first sets the mode for both**, and stating it in only one of
the two places is how it ends up depending on call order.

## Pinned versions

Measured on this machine, not recalled: **bash 3.2.57** (macOS system bash — no associative arrays, no
`mapfile`, no `${var,,}`), **Python 3.9.6** (stdlib only; `-I` drops the script directory from
`sys.path`, so no sibling imports), **git 2.50.1**, **shellcheck 0.11.0** (`/opt/homebrew/bin/shellcheck`
— check sets differ across releases and it gates checklist task 11).

## Testing requirements

- `hooks/test-marker-guard.test.sh` — throwaway git repo, payload on **stdin**, which is the production
  path. A hook tested only through its CLI path is a bug that has already shipped in this repo. Covers
  every `form` row against a real commit, not a simulated one, plus the inert-repo allow.
- `hooks/lib/write-test-marker.test.py` — sibling derivation, `--full-name` normalisation from a
  subdirectory, the no-subject skip, atomic write, schema, file mode, failure exits. **The two
  repo-level inventory assertions are added at task 8**, not here at task 4, because until the 11
  pre-existing suites are wired the wiring assertion is legitimately red.
- `hooks/lib/classify-commit-command.test.py` — direct unit assertions on the JSON contract: **one
  case per grammar row G1-G9**, bundle decomposition with both attached and detached values, every
  value-taking flag in both groups, `--opt=value`, a `--` inside a value, every `form` including
  `INCLUDE` and `NONE`, `--amend`, the **unsanitised** `exempt` passthrough, the `FOREIGN` triggers,
  exit 3 for an unreadable payload, and the accepted-open shapes, so closing one later is a conscious
  decision with a failing test rather than drift. **Every cell of the `kind` × field totality matrix
  gets its own assertion** — 18 cells, not just the `COMMIT` column — because four rounds of
  `api-contracts` were four different undefined cells, and a column nobody asserts is a column that
  goes undefined again. **This suite is where the two measured fail-opens are pinned;
  if any single file in this feature deserves over-testing, it is this one.**
- **Mutation check before the PR:** the 24 above.

## Checklist

- [ ] 1. ADR under `docs/decisions/` — record the marker-as-receipt framing, the three rejected
      designs (PostToolUse observer, `bin/run-tests` wrapper, mutual certification), the
      global-but-inert scope decision, the `INCLUDE` refusal, the accepted-open shapes, and the
      `cmux.sh` coverage hole. Check the next free ADR number against `main` first.
- [ ] 2. Red: `classify-commit-command.test.py` — **the grammar first** (G1-G9, bundles, value-taking
      flags in both groups, `--opt=value`, `--` inside a value), **plus rule 0's wrapper stripping for
      every member of `WRAPPERS` — `rtk git commit …` must classify exactly as `git commit …`, and that
      case is the difference between an armed gate and a dead one** — and the closed whitelist:
      an abbreviated-but-valid option (`--am`, measured accepted by git 2.50.1) must resolve to
      `UNSUPPORTED` and **block**, not fall through to `PLAIN`. Then every `form` **in the order rule 4
      fixes**, including a command firing two triggers at once, `--amend`, raw
      `exempt` passthrough, `FOREIGN` triggers, `INCLUDE`, `-p`/`--interactive`, exit 3, ignored and
      genuinely accepted-open shapes (alias and variable indirection only),
      **and all 18 cells of the `kind` × field totality matrix**. ⚠️ The grammar's rule 2 is
      user-waived and unresolved — see the callout in §"The command grammar". Do not encode rule 2
      literally; this task is blocked on the shared-lexer decision landing in `shell_segments.py`.
- [ ] 3. Green: `hooks/lib/classify-commit-command.py`.
- [ ] 4. Red: `write-test-marker.test.py` — derivation, normalisation, no-subject skip, atomic write,
      schema, mode, failure exits. **No inventory assertion yet** — see task 8.
- [ ] 5. Green: `hooks/lib/write-test-marker.py`.
- [ ] 6. Red: `hooks/test-marker-guard.test.sh` — every scenario above, asserting message **and** code,
      plus the `test-marker.log` line where a scenario names one (including the two that assert **no**
      line is written — a logger that appends on every path passes every positive assertion).
- [ ] 7. Green: `hooks/test-marker-guard.sh`.
- [ ] 8. Wire the one-line call into **all 14 paired suites** — the 11 in §Scope's first table plus
      this feature's own 3 — using the call site exactly as §1 specifies it: **`MARKER_SELF` and
      `MARKER_ROOT` captured at the top, before any chdir, both absolute; the writer run with
      `MARKER_ROOT` as its cwd** (`cd` in a subshell for shell suites, `cwd=` for the three Python
      ones). `judge-guard.test.sh` cds at line 13 and pairs 12–13 build throwaway repos, so a
      bottom-of-file resolution is wrong in both languages. Add the two inventory assertions to
      `write-test-marker.test.py` in this same
      commit. **Own commit**, measured behaviour-neutral against the unmodified hook — never bundled
      with a green step. ⚠️ **Tasks 5 and 8 revert as a pair** — round 3 said 7 and 8 and had the
      wrong hazard. The **writer** is task 5, so reverting 5 without 8 leaves 14 suites calling a
      deleted file. Reverting 8 alone is safe; it only disarms the wiring. See the revert-pair table
      under task 13 — **task 7 is half of the second pair**, and the claim earlier rounds made that
      reverting it alone is harmless stops being true the moment task 13 lands.
- [ ] 9. Mutation check — the 24-mutant floor (14 doors, 9 allow paths, emptied classifier); record
      the result in the checklist annotation.
- [ ] 10. Measure the latency budgets and record **all three** numbers here — round 5 added the
      `kind: OTHER` budget and updated the prose to "measures and records all three" but left this task
      reading "the two numbers", so the new budget would have gone unmeasured by anyone working the
      checklist. Revise a budget if a figure exceeds it rather than dropping it.
- [ ] 11. `shellcheck -x` (0.11.0) clean apart from pre-existing findings; confirm which are
      pre-existing by blame **before** claiming it, not after.
- [ ] 12. Gate stub in `rules/gates.md`; `hooks/README.md` entry. Both must state the global-but-inert
      scope, or the next reader assumes `.claude`-only.
- [ ] 13. Register in `settings.json` via `update-config`, preserving `"model": "opus[1m]"`.
      ⚠️ **Tasks 7 and 13 revert as a pair, and this is the worse of the two pairs.** Registration
      names `hooks/test-marker-guard.sh` to the harness; reverting **7 without 13** leaves a
      registered-yet-missing hook, and a `PreToolUse` entry whose script cannot be executed fails
      **every Bash tool call in the session**, not just commits — the blast radius is the whole
      session, against 5↔8's fourteen suites. Revert **13 first, then 7**, never the reverse, and
      never 7 alone. Reverting 13 alone is safe: it disarms the gate and leaves an inert script.

      | pair | revert order | leaving one half behind costs |
      |---|---|---|
      | 5 ↔ 8 | 8 then 5 | 14 suites call a deleted writer |
      | 7 ↔ 13 | **13 then 7** | **every Bash call in the session is blocked** |
- [ ] 14. **First-arming check** — run `hooks/test-marker-guard.sh --status` and expect `ACTIVE` with
      the right toplevel; pipe a real `git commit` payload into the *installed* hook and expect a
      readable exit 2, not a silent 0 and not a hang; pipe a `git commit -am msg` payload and expect
      the same, since that spelling is the one the grammar exists for. Then repeat from a repo
      **without** the writer and expect `INERT` and exit 0. `judge-guard` shipped with this untested
      and the installed copy had no `lib/` at all.
- [ ] 15. Obs judge (implementation stage) pinning the final HEAD → PR.

**Standing decisions — carried in from the defect checklist that this file replaces.**

- **Exit criterion.** If a judge round fails again with ids that have already recurred, **stop
  specifying and build**: the remaining items become test cases in task 6, not another round of prose.
  Rounds 1–5 failed on `api-contracts` and `commit-form-coverage` repeatedly, which is what this
  criterion was written for — invoking it needs an explicit decision from the user, never a silent one.
- **Waivers.** `writing-specs/command-grammar` is the only waiver this spec has ever carried, and it is
  recorded in the frontmatter. A judge citing it is arguing with a settled decision. Nothing else is
  waived; a second waiver is a user decision, not a drafting one.
- **O3 — the shrink, still owed.** This file is well over the repo's <400-line standard. The diagnosis
  that survived five rounds is that *prose consistency at this size*, not the design, is what keeps
  failing: measurement narrative and round-by-round rationale should move to an ADR, leaving contracts,
  the grammar outcome, scenarios, doors, and this checklist. Deliberately **not** bundled with a defect
  round — rewriting and fixing in one pass makes the result unreviewable.

**Follow-ups this feature deliberately does not do:** rename `panes/adapters/cmux-exec.test.sh` to
match `cmux.sh` and close that coverage hole; bring `memsearch/tests/` under a sibling layout; give the
helper invocations a timeout; support `-i`/`--include` and `--pathspec-from-file` properly rather than
refusing them; unify the four `git commit` lexers behind this classifier — **and, separately and
sooner, fix the `^git`-anchored fail-open now confirmed live in `git-guard.sh:89`,
`doc-guard.sh:123` and `checkpoint-before-modify.sh:97`**, which is its own piece of work and not
gated on this feature.

**Bootstrap note.** This gate covers `hooks/*.sh`, which includes its own files. It is not armed during
development because the harness loads the primary checkout's copy — the same reason a `judge-guard` fix
could not be gated by `judge-guard` until the primary checkout pulled it. Expect it to arm only after
merge, and treat task 14 as the first real test of that.
