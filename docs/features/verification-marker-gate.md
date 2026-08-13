---
phase: planning
model_tier: high
branch: none
revision: 9
revision_status: complete  # round-2 compliance fix: line counts re-measured, derivation stored
waived: [writing-specs/command-grammar, core-conduct/file-size-convention]
---

# verification-marker gate

A PreToolUse hook that blocks a `git commit` when a file with a sibling test is being committed at a
version its test suite has never passed against.

> **Revision 8 is a scope cut, not a rewrite of the design** (user decision 2026-08-13). Revision 7
> had closed the opt-in ordering defect but measured 1,448 lines against an 800 ceiling, and showed
> that deleting every line of prose still left ~740 — so the size fix had to shrink the *feature*, not
> relocate its text. Three things left v1: the decision log, `--status`, and `INCLUDE`/`FOREIGN` as
> forms of their own. **Every one of those still blocks; only the elaboration went.** Each is named
> under §Follow-ups.
>
> ⚠️ **The cut worked and was not nearly enough: 1,448 → 1,402 lines, a net 46.**
> `core-conduct/file-size-convention` is therefore **WAIVED for this file** (user decision,
> 2026-08-13, recorded in the frontmatter) — not met, and not silently ignored either. The measurement
> in §Standing decisions → O3 is the whole basis for the waiver: it shows the ceiling is unreachable
> at this feature's scope without deleting the acceptance scenarios and contract tables the spec
> exists to supply. **A judge citing this id is arguing with a settled decision.**

```mermaid
flowchart TD
    A[Bash tool call] --> PF{Raw payload contains<br/>the substring "commit"?}
    PF -- no --> P[ALLOW]
    PF -- yes --> NP{python3 usable?}
    NP -- no --> D3[BLOCK: MSG_NO_PYTHON]
    NP -- yes --> RC{Payload parses,<br/>and carries a cwd?}
    RC -- no --> P
    RC -- yes --> F{Toplevel resolves<br/>from that cwd?}
    F -- no --> P
    F -- yes --> G{Writer installed<br/>in that repo?}
    G -- "no, gate not adopted" --> P
    G -- yes --> CM{Classifier present<br/>and readable?}
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
    E -- yes --> H{TEST_EXEMPT non-empty?}
    H -- "yes, invalid" --> BE[BLOCK: MSG_BAD_EXEMPT]
    H -- "yes, valid" --> P
    H -- no --> I{form}
    I -- UNSUPPORTED --> UF[BLOCK: MSG_UNSUPPORTED_FORM]
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

**The opt-in check sits above the classifier, and that ordering is the contract, not an optimisation.**
Every door except `MSG_NO_PYTHON` is downstream of node `G`, so a repo that has not installed the
writer cannot be blocked by this hook — including by a missing or corrupt `classify-commit-command.py`,
a file this feature introduces. See §Fail-closed contract → "Which doors are machine-global".

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
The gate rule wins; there is no second spec location. *Judged adequate — do not "fix" it.*

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

**Inertness has exactly one exception, and it is stated here rather than left to the flowchart.** A
non-adopting repo is never blocked by any door **except `MSG_NO_PYTHON`**, which fires before the
payload can be read at all. That single exception is not a new hazard: `git-guard.sh:53-57`,
`judge-guard.sh:44-48` and `merge-guard.sh:39-43` are all globally registered today and all `exit 2`
with a message when `python3` is missing, so a broken interpreter already blocks every commit on this
machine before this feature exists. (`doc-guard.sh:54` is the family's one fail-open.) Every other
door — including the three that depend on this feature's own new classifier file — is downstream of
the writer-installed check and therefore cannot reach a repo that has not opted in.

> ⚠️ **Accepted cost of the v1 scope cut: inertness is NOT observable in v1, and that is a known
> weakness rather than an oversight.** A hook that allows is silent, so nothing distinguishes
> "allowed, verified" from "allowed, inert" — `judge-guard.sh:204` records exactly this failure in
> exactly this family. Revision 7 answered it with a `--status` subcommand; revision 8 defers that to
> a follow-up. What replaces it in v1 is **task 14**, which pipes a real payload into the *installed*
> hook and requires a readable `exit 2` — a one-off arming proof at install time instead of a
> queryable one. The residual risk is that the gate goes inert *later*, silently. Restoring `--status`
> is the first follow-up for that reason.

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

**This table is a dated measurement of the pre-feature repo, and it is not the completion criterion**,
because **this feature adds three conforming pairs of its own:**

| # | subject | suite | lands at |
|---|---|---|---|
| 12 | `hooks/lib/classify-commit-command.py` | `hooks/lib/classify-commit-command.test.py` | task 3 |
| 13 | `hooks/lib/write-test-marker.py` | `hooks/lib/write-test-marker.test.py` | task 5 |
| 14 | `hooks/test-marker-guard.sh` | `hooks/test-marker-guard.test.sh` | task 7 |

All three are `hooks/` files with sibling tests, so **the gate demands markers for them too**. A
suite of this feature's own that does not write a marker makes its subject uncommittable the moment
the gate arms. The wiring criterion is therefore **every pair, 14 of them at task 8** — never a
literal carried over from the table above. Freezing the number 11 in a test would make that assertion
false from task 4 onward by this feature's own construction. The suite files live under four different
directory depths, which is why the call site cannot use a `$0`-relative path (see §1).

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

**Relationship to the existing guards — measured.** The three production lexers of `git commit` are
**`git-guard.sh:89`, `doc-guard.sh:123` and `checkpoint-before-modify.sh:97`**, and all three anchor
the pattern at `^git[[:space:]]+`. (`merge-guard.sh` does not lex `git commit` at all.)

**That anchoring is a live fail-open in all three**: a chained `git add -- <path> && git commit --
<path>` never matches, so the guard does not evaluate. `gates.md` records this chained-command
limitation for `merge-guard` but not for these. `doc-guard.sh:135` even carries `(-a|--all|-am)`, so it
knew about one bundle — but not `-ams` or `-amHELLO` (G4).

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

**Path normalisation is mandatory.** The suite passes `$0`, which is relative to the suite's cwd —
measured: running `bash adapters/cmux-layout.test.sh` from inside `panes/` yields
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

#### What the inventory test asserts, and why not a count

The invariant that survives the feature's own additions is not a count but a **property**, asserted in
two parts:

1. **Every tracked pair's suite contains the marker-write call.** Enumerate
   `git ls-files '*.test.sh' '*.test.py'`, derive each subject, keep the ones whose subject is tracked,
   and assert each of those suite files contains the call line. This has a real trigger — adding a
   paired suite without wiring it turns the suite red — and it self-extends to pairs 12–14 instead of
   contradicting them.
2. **The two named orphans are still orphans.** Assert `panes/adapters.test.sh` and
   `panes/adapters/cmux-exec.test.sh` each derive a subject that is **not** tracked. This freezes the
   `cmux.sh` coverage-hole claim in §Scope; the follow-up rename will turn it red, which is correct —
   the rename must update §Scope in the same commit.

Deliberately *not* asserted: that the orphan set is exactly those two. During TDD each red step commits
a suite whose subject does not exist yet, a transient third orphan; an equality assertion would make
the red steps unlandable.

**Assertion 1 lands in task 8's commit, not task 4.** Written at task 4 it would be red for four tasks,
since the 11 pre-existing suites are not wired until task 8. Task 8 wires all 14 and adds the assertion
that keeps them wired, together, in one commit.

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

**Capture at the top, use at the bottom, and give the writer the right cwd — all three.** Resolved from
the **repo root**, never `$(dirname "$0")/lib`, which resolves only for the 5 suites under `hooks/`.
Both `$0` and `rev-parse` depend on the suite's cwd, and **measured: `hooks/judge-guard.test.sh:13`
runs `cd "$TMP" || exit 1` at top level** — 1 of the 11 existing suites already invalidates a
bottom-of-file `rev-parse`. The writer is a *separate process*, and both of its resolution steps
(`git ls-files --full-name --error-unmatch` and `rev-parse --show-toplevel`) run in **its** cwd, not in
the values it was handed: launched from a suite sitting in `$TMP`, `ls-files` exits 1 and `rev-parse`
returns the throwaway repo, so the mandated `|| exit 1` would leave that suite permanently red.

**The rule binds both forms identically.** `os.path.abspath(__file__)` is equally cwd-dependent, since
`__file__` may be relative on Python 3.9.6, and §Testing requirements obliges pairs 12 and 13 to build
throwaway repos. The two forms are written as mirrors: **capture `MARKER_SELF` and `MARKER_ROOT` at
module level before any chdir, both absolute; pass `MARKER_SELF`; run the writer with `MARKER_ROOT` as
its cwd** — `cd` in a subshell for shell, `cwd=` for Python. A reviewer should be able to diff the two
blocks and find no behavioural difference. Task 8 must not paste the call blindly into any suite.

A failed marker write **fails the suite**. A silent no-marker would surface later as a confusing block.

### 2. `<repo>/hooks/state/test-markers/` — the store

- **One file per subject**, so two concurrent sessions never read-modify-write the same file.
- Filename is the repo-relative subject path, percent-encoded (`/`→`%2F`, `%`→`%25`).
- Resolved from `git rev-parse --show-toplevel`, **never `$HOME`**. Reading `$HOME`'s copy instead of
  the target repo's was literally the bug `fix/judge-guard-verdict-lookup` existed to fix; a marker
  written inside a worktree must be read back inside that worktree.
- **`<repo>/hooks/state/` is `0700` and each marker file is `0600`** — core-conduct's default-deny for
  a generated store. The real defence is read-side validation, but the store is the sole authority for
  letting a commit through and there is no reason for it to be world-readable. **This feature creates
  `hooks/state/`; it does not exist in this repo today**, and the writer is the only component that
  creates it, so the mode is set in exactly one place.
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

**Which repo, and it is settled before the classifier runs.** The hook buffers the payload from stdin
once, then extracts **one field, `cwd`**, with an inline `python3` JSON read — the shape
`git-guard.sh:59-72` already uses. It makes no attempt to parse the command; the classifier remains
the sole command parser. Three outcomes:

1. **The payload does not parse, or carries no string `cwd`** → the target repo is unknowable → **allow**,
   exactly as `git-guard.sh:72` allows on an empty extraction. Stated as accepted-open below.
2. **`git -C <payload.cwd> rev-parse --show-toplevel` fails** → **measured: outside a repo this exits
   128 with empty stdout**; that is the answer "there is no repo here", not an error, and the gate
   allows because git itself will refuse the commit. This is the one status-checked git call that does
   *not* route to `MSG_GIT_FAILED`.
3. **A toplevel resolves** → `test -r <toplevel>/hooks/lib/write-test-marker.py` decides adoption. Not
   readable → allow, gate not adopted.

Only after (3) says *adopted* does the hook invoke `classify-commit-command.py`. The payload `cwd` is
the session's cwd, which is the cwd the command *starts* in; it is deliberately **not** used to follow
a `cd` inside the command — see the foreign-repo trigger under §The command grammar.

**Wire contract — one helper, one line of JSON.** One helper reading the payload and emitting one JSON
object removes a desync class instead of defending against it, and is *more* unit-testable, not less.

- **stdin:** the buffered PreToolUse payload, decoded UTF-8 with `errors="replace"`.
- **stdout:** exactly one line, a JSON object.
- **exit:** `0` whenever it produced a line; **`3` — and only `3` — for an unreadable payload**; any
  other non-zero, or exit 0 with no output, is a broken component. The dedicated code is what makes
  `MSG_BAD_PAYLOAD` and `MSG_CLASSIFIER_FAILED` two distinguishable doors instead of one door with two
  names. Since the hook has already parsed the same bytes at step 1, exit 3 now means **two reads of
  one payload disagreed** — a component-liveness failure, which is the same class the `v` sentinel
  guards and is asserted by stubbing the classifier to exit 3.

```json
{ "v": 1, "tool": "Bash", "kind": "COMMIT",
  "form": "PLAIN", "amend": false, "paths": [], "exempt": "" }
```

| field | domain | meaning |
|---|---|---|
| `v` | `1` | schema sentinel — status *and* shape, because three rounds on `judge-guard` showed a status check alone accepts a component that answers and then dies |
| `tool` | string | `tool_name` from the payload; only ever used to settle what an **absent** command means |
| `kind` | `COMMIT` \| `OTHER` \| `NOTHING_RUNNABLE` | `NOTHING_RUNNABLE` = command absent, empty, or only whitespace/control characters |
| `form` | `PLAIN` \| `PATHSPEC` \| `ALL` \| `UNSUPPORTED` \| `INVALID` \| `NONE` | see the **ordered** resolution table under §The command grammar rule 4 — first match wins; `NONE` is the value whenever `kind` is not `COMMIT` |
| `amend` | bool | `--amend` present |
| `paths` | list of strings | the pathspec operands; empty unless `form` is `PATHSPEC` |
| `exempt` | the **raw** `TEST_EXEMPT` value, JSON-escaped, or `""` when unset or empty | parsed from the command **string** — a `VAR=x` prefix never reaches a hook's environment. **The classifier does not sanitise it** |

**The contract is total over `kind`.** The hook validates **every field against its domain before it
ever consults `kind`** — the flowchart's `CO` node precedes `E` — so a conforming classifier answering
a payload like `ls` must have a legal value for every field or it trips `MSG_CLASSIFIER_BAD_OUTPUT` on
the commonest input it will ever see. Every cell is defined:

| field | `kind: COMMIT` | `kind: OTHER` | `kind: NOTHING_RUNNABLE` |
|---|---|---|---|
| `v` | `1` | `1` | `1` |
| `tool` | `tool_name`, verbatim | `tool_name`, verbatim | `tool_name`, verbatim |
| `form` | one of the five commit forms | **`NONE`** | **`NONE`** |
| `amend` | `--amend` present | **`false`** | **`false`** |
| `paths` | operands; `[]` unless `PATHSPEC` | **`[]`** | **`[]`** |
| `exempt` | raw `TEST_EXEMPT`, or `""` | raw `TEST_EXEMPT`, or `""` | **`""`** |

`NONE` is a **value** of `form`, not an absence. No field is ever optional and no field is ever null,
so the hook's domain check needs no per-kind special case. `exempt` is still reported under `OTHER`
because `TEST_EXEMPT=x ls` lexes perfectly well and the hook, not the classifier, decides what an
exemption is worth; under `NOTHING_RUNNABLE` there is no command string to parse one out of, so `""` is
the only honest answer.

**Validation order.** The hook applies exactly two checks, in this order, and this is the only place
read-side validation of the classifier's output is specified:

1. **Shape and domain, at node `CO`, for every payload regardless of `kind`:** output parses as one
   JSON object, `v == 1`, every field present, each inside the domain above, `paths` a list of
   strings, `exempt` a string. Anything else → `MSG_CLASSIFIER_BAD_OUTPUT` → block. This check never
   inspects the *content* of `exempt`.
2. **Exemption validity, at node `H`, only once `kind == COMMIT`:** a non-empty `exempt` must match
   `^[^\x00-\x1f\x7f]{1,200}$`, else **`MSG_BAD_EXEMPT`** — its own door, because a malformed
   exemption reason is a user error, not a broken component. Over-length is rejected, never silently
   truncated: a truncated reason is an unauditable exemption.

Putting the regex at step 1 would let `TEST_EXEMPT=$'a\nb' ls` — a non-commit — block the session,
which is why the order is load-bearing rather than incidental.

**The classifier does not strip control characters.** A JSON string survives a newline intact, so
sanitising buys nothing and makes the hook's re-validation unreachable. The contract is single-sourced:
**the classifier reports, the hook decides.**

**`python3 -I`** at every call site, so a stray `json.py` in the working directory cannot shadow the
helper and block every Bash command.

**The command decides; `tool_name` only settles what an ABSENT command means.** Runnable command →
classify it whatever the tool is called; `NOTHING_RUNNABLE` + `Bash` → block; `NOTHING_RUNNABLE` + any
other tool → allow. Keying the skip on the name instead was a measured regression on that branch.

#### The command grammar

Measured on git 2.50.1, one throwaway repo per case, all on the fixture *`foo.sh` committed `v1`,
staged `v2`, worktree `v3`; `bar.md` modified in the worktree only*:

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
   dead on arrival, and task 14's arming check would report a pass over the top of it.** The set is
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
4. **Form — a total function of the command, resolved in this order, first match wins.** **The order is
   the contract; ties are not resolved by reading order elsewhere.**

   | # | form | trigger | outcome | why it sits here |
   |---|---|---|---|---|
   | 1 | `INVALID` | `-a`/`--all` together with any pathspec operand (G8, G9) | **allow** | **Git itself refuses the command — exit 128, nothing is committed.** Nothing downstream can matter, so this resolves before every block. |
   | 2 | `UNSUPPORTED` | **any** of: a `cd`, `git -C`, `--git-dir` or `--work-tree` anywhere before the commit; `-i`/`--include` or `--pathspec-from-file`; `-p`/`--patch` or `--interactive`; **any option not in the whitelist** | block, `MSG_UNSUPPORTED_FORM` | Each trigger makes the commit's contents, or the repo they belong to, unknowable before the hook returns. See "What `UNSUPPORTED` absorbs" below. |
   | 3 | `ALL` | `-a`/`--all` with **no** operand | proceed, worktree content | |
   | 4 | `PATHSPEC` | any operand, with or without `--`, including via `-o`/`--only` | proceed, index content | |
   | 5 | `PLAIN` | none of the above | proceed, index content | The default, reached only by exhausting the list. |

   `NONE` is the value whenever `kind` is not `COMMIT`, and is not part of this resolution.

**Value-taking flags must be known by name**, because mis-lexing one turns its value into a phantom
pathspec (G5). Two groups, and the distinction is load-bearing:

- **Consume the next token** (or the bundle remainder): `-m/--message`, `-F/--file`,
  `-c/--reedit-message`, `-C/--reuse-message`, `-t/--template`, `--author`, `--date`, `--cleanup`,
  `--fixup`, `--squash`, `--trailer`, `--pathspec-from-file`.
- **Optional value, attached only** — these must **never** consume the next token, or they would eat
  a pathspec: `-u/--untracked-files`, `-S/--gpg-sign`.

> ⚠️ **UNRESOLVED — user-waived (`writing-specs/command-grammar`), decided elsewhere.
> Do not implement rule 2 as written.** Rule 2's unqualified "`--opt value` consumes the next token"
> contradicts the group immediately above it, which names `--untracked-files` and `--gpg-sign` as long
> options that must never consume one. Measured on git 2.50.1:
> `git commit -m msg --untracked-files foo.sh` ships the **worktree** blob, because `foo.sh` is a
> pathspec — so a classifier applying rule 2 literally reports `PLAIN`, hashes the index, and re-opens
> G2, the exact fail-open this section exists to close. The section also does not state how the command
> string becomes tokens, how `git <global-opts> commit` is told from `git commit <opts>` (which the
> `-C` trigger depends on), or how a `git add … && git commit …` chain is segmented.
>
> **Deferred, not dismissed.** This is the same tokenisation question `hooks/lib/shell_segments.py`
> already answers for `git-guard`, `doc-guard` and `classify-pr-command.py`, and the open defect where
> a redirection after a pathspec becomes a phantom operand is a defect in *that* file. Writing a
> second, independent grammar here is precisely how the two would drift apart. **The decision is made
> once, in the shared lexer, and this section then cites it rather than restating it.** Implementation
> of this feature is blocked on that decision landing; the rest of the spec is not.

##### What `UNSUPPORTED` absorbs, and why each trigger blocks rather than guesses

Revision 8 folded two forms that previously had rows of their own into `UNSUPPORTED`. **The blocking
behaviour is unchanged for every one of them** — what was cut is the separate form value, the separate
door, and the tailored remedy string, not the refusal. The single message names which trigger fired so
the remedy is still actionable.

- **Foreign repo — `cd`, `git -C`, `--git-dir`, `--work-tree`.** A PreToolUse hook sees
  `cd /other/repo && git commit -m x` as one command string and cannot follow the `cd`; resolving
  `--show-toplevel` from the payload `cwd` would read a different repo's index and a different repo's
  markers, and both allowing and blocking on that basis would be wrong. ⚠️ **This trigger must keep
  blocking. Reading another repo's markers is the worst failure this gate has** — the folding is a
  prose change, never a licence to allow. Accepted cost: `cd "$HOME/.claude" && git commit …` is the
  *same* repo and still blocks. The remedy — run the commit as its own command, or set `TEST_EXEMPT` —
  genuinely reaches it. Following the `cd` is deliberately rejected: it re-introduces the "follow the
  shell" reasoning this design refuses, and fails on any non-literal target.
- **`-i`/`--include` and `--pathspec-from-file`.** `-i` commits the staged contents *plus* the named
  paths. **Measured (M3):** with `a.sh` staged at `v2`, `git commit -m x -i -- b.md` commits **both**
  files and `git show HEAD:a.sh` is `v2`, while a `PATHSPEC` collector returns `b.md` alone — the gate
  would miss `a.sh` entirely. `-i` also lexes cleanly, so the accepted-open clause never covered it.
  Supporting it means a union of two collectors with a different content source on each side: real
  complexity for a flag this repo's house style never uses. `--pathspec-from-file` sources operands
  from a file the hook would have to read and re-resolve, and is refused on the same ground.
- **`-p`/`--patch` and `--interactive`.** Both select their content *interactively, after* the
  `PreToolUse` hook has already returned, so there is no moment at which the hook could inspect what
  the commit will contain. Refused on that ground, not a lexing one; no grammar work changes it.
- **Any option outside the whitelist** — see immediately below.

##### Recognition is a closed whitelist, and the default for a recognised commit is refuse

An option grammar cannot be enumerated by exact spelling — **measured on git 2.50.1, git accepts any
*unique* abbreviation of a long option**:

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

Every row below was reproduced on git 2.50.1 in a throwaway repo; checklist task 6 turns each into a
test that commits for real rather than simulating.

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
| `UNSUPPORTED` | — | — — block, see §What `UNSUPPORTED` absorbs |
| `INVALID` (`-a` **and** an operand — G8, G9) | — | — — git itself exits 128 and commits nothing, so the hook allows and lets git refuse |

**Every row's trigger is the decomposed flag set from §"The command grammar", never a raw token
match.** `-am` reaching the `ALL` row rather than the `PLAIN` row is the whole point of that section.

**`NONE` has no row here, and that is not a gap.** It cannot reach this table: the hook consults `form`
only after `kind == COMMIT` (the flowchart's `E` precedes `I`), and `NONE` is by definition the value
for every non-`COMMIT` output. The table is total over the forms that reach it — five of the six
domain values — and the sixth is unreachable by construction rather than undefined by omission.

**Post-commit content of a pair member that is NOT in the path set.** The pairing rule hashes **both**
members, so this is the commonest real case. The rule is uniform: **the blob the resulting commit's
tree will hold.**

| `form` | member outside the path set | why |
|---|---|---|
| `PLAIN` | index blob | the new tree *is* the index |
| `PATHSPEC` | the `<base>` blob | the commit does not touch it |
| `ALL` | the `<base>` blob | outside this path set means *unmodified against `<base>`* — the path set is every tracked worktree difference — so the base and worktree blobs are identical here and `-a` changes nothing |

**Why the `ALL` row is stated against `<base>` and not the worktree.** The two blobs are equal for
every path this row can reach, so the choice looks cosmetic and is not: naming the worktree invites a
`hash-object` on any path that happens to be on disk, and **an untracked file is on disk without ever
entering the commit.** Measured on git 2.50.1: with `note.txt` untracked, `git commit -am y` produces a
tree with no entry at `note.txt`. Naming `<base>` makes the untracked case fall out of the rule rather
than needing a clause.

**Measured (M4):** with `foo.sh` and `foo.test.sh` both modified in the worktree,
`git commit -m x -- foo.sh` yields `HEAD:foo.test.sh` = the **old** content, while the worktree holds
the new one, and the two blobs differ. So a pair whose test was edited but not committed is compared
against the base blob and **blocks with `MSG_STALE_TEST`** — correct and fail-closed: the shipped
combination of new subject and old test is one no suite run ever certified.

**ABSENT is a defined result, not a git failure.** There is **one** definition:

> A pair member is **ABSENT** iff **the resulting commit's tree will have no entry at its path.**

The probes below are *implementations* of that sentence for each content source, and a probe that ever
disagrees with it is a defect in the probe. Stating the semantics separately from the mechanics is what
makes the next case derivable:

| content source | ABSENT iff | covers |
|---|---|---|
| index blob (`PLAIN`, any member) | `git ls-files --stage -- <path>` prints nothing | untracked (no index entry) and staged-for-deletion (entry removed) |
| worktree blob (`PATHSPEC`, member *in* the pathspec) | the path does not exist on disk | a pathspec naming a deleted file commits the deletion |
| `<base>` blob (`PATHSPEC`, member *outside* the pathspec) | `git cat-file -e <base>:<path>` exits non-zero — **and nothing else** | untracked → no base entry → ABSENT. Disk and index are irrelevant here (M5) |
| `<base>` blob (`ALL`, member *outside* the path set) | `git cat-file -e <base>:<path>` exits non-zero **or** the path does not exist on disk | untracked → no base entry → ABSENT; tracked but deleted in the worktree → `--diff-filter=d` keeps it out of the path set while `-a` still stages the deletion → ABSENT |

The `ALL`-outside row is the only two-condition cell, and it is two conditions because two different
states produce an empty tree entry there.

**Measured (M5) — why the two `<base>` rows cannot share a condition.** Written as one row carrying the
disk clause it is right for `ALL` and **wrong for `PATHSPEC`**, where it produces a false *block*. Four
cases on git 2.50.1, base tree `foo.sh`, `bar.md`, `gone.md`:

| # | form | state of `gone.md` | in the resulting tree? | correct verdict |
|---|---|---|---|---|
| A | `git commit -m x -- foo.sh` | deleted on disk, **not** staged | **yes** | not ABSENT |
| B | `git commit -m x -- foo.sh` | deletion **staged** (`git rm --cached`) | **yes** | not ABSENT |
| C | `git commit -a -m x` | deleted on disk, not staged | no | ABSENT (base present, disk missing) |
| D | `git commit -a -m x` | *untracked* file present on disk | no | ABSENT (base missing, disk present) |

A and B: the pathspec form builds its tree from `<base>` **plus the named paths**, consulting neither
the worktree nor the index for anything else — so a member outside the pathspec survives into the
commit even when its deletion is already staged. Under a merged row the gate would call `gone.md`
ABSENT and block with `MSG_STALE_TEST` on a pair whose test the commit preserves byte-for-byte at the
version the marker certifies. C and D are why `ALL` keeps both conditions: each disjunct is the only
one that catches its case.

Under `ALL`, a member **in** the path set needs no ABSENT case at all: `--diff-filter=d` has already
removed deletions, so every path the collector returns exists on disk.

ABSENT means the pair cannot be certified: the door is `MSG_STALE_SUBJECT` / `MSG_STALE_TEST`, *not*
`MSG_GIT_FAILED`. The gate never calls `hash-object` on a path it has already found ABSENT. Only an
unexpected failure of a collection or hashing command is infrastructure.

What each row is defending, with the measurement:

- **`PATHSPEC` content.** Index `v2`, worktree `v3`, then `git commit -m x -- foo.sh` → `git show
  HEAD:foo.sh` is **`v3`**. Hashing `v2` would match the marker and allow a version no test ever saw —
  a silent fail-open in the repo's own house style.
- **`PATHSPEC` path set.** A pathspec also *narrows*: with `foo.sh` staged, `git commit -m x -- bar.md`
  commits **`bar.md` only**, while an index collector returns `foo.sh` and would raise a false block on
  a file not being committed. `git diff <base> -- <paths>` returns exactly `bar.md`.
- **`PATHSPEC` on an unchanged file.** `git commit -m x -- foo.sh bar.md` with `foo.sh` identical to
  HEAD commits `bar.md` only, and the collector returns `bar.md` only. No false block from a broad
  pathspec such as `-- hooks/`.
- **`ALL` path set.** With a never-staged worktree edit, `git diff --cached --name-only` returns
  **zero paths** while the commit contains the file — so an index collector finds no pairs and allows.
- **`amend` base.** Staging a sidecar and amending: `git diff --cached <base=HEAD>` returns the
  sidecar alone, `<base=HEAD^>` returns the sidecar **and** the file from the amended commit, which
  is exactly the amended commit's contents. All three collecting forms combine with `--amend`
  unchanged; `--amend` alters only the base.

**Pairing rule.** The unit is the `(subject, test)` pair, not the single file. If **either** member is
in the path set, that pair needs a valid marker whose two blobs equal the post-commit content of both
members. Pairing on the file alone would let a test file ship at a version that was never run.

**Pair formation — the predicate, in three steps, and asymmetric by direction.**

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
**satisfiability**, not fastidiousness. This is what reconciles §Scope ("a file with no sibling test is
never gated") with the `-am` scenario below, which forms a pair with an **untracked** test:

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

**Every git invocation is status-checked**, apart from the four below, whose non-zero or empty result is
a **defined answer** rather than a failure. The set is enumerated so the next count does not have to be
guessed:

1. `rev-parse --show-toplevel` from the payload cwd — non-zero means "no repo here" → allow.
2. `rev-parse --verify HEAD` / `HEAD^` — non-zero means unborn or root → `<base>` is the empty tree.
3. `ls-files --stage -- <path>` — empty output means ABSENT under an index source.
4. `cat-file -e <base>:<path>` — non-zero means ABSENT under a base source.

The worktree ABSENT test is a plain file-existence check and runs no git at all.

**A measured hazard the collectors must not walk into.** Outside a repo, `git diff --cached
--name-only` prints **nothing on stdout** and exits **129**, not 128: with no repo, `git diff` falls
back to `--no-index`, whose option table has no `--cached`, so the failure is `error: unknown option
'cached'` plus a usage dump **on stderr**. 128 is the code the other three probes above return, so
recording this as 128 collapses two different failures into one. What matters is the hazard: stdout is
empty either way, so any caller reading only stdout cannot tell this apart from "no files to check"
and will allow — `judge-guard` fail-open #3 reborn in the one subsystem this hook adds. A non-zero exit
from any other collection or hashing command → `MSG_GIT_FAILED` → block. Never pipe one of these into
another command: the pipeline's status is the last stage's.

#### Latency

Every Bash tool call pays this hook. The observability judge measured the existing PreToolUse chain at
**~373 ms**, and `python3 -I` startup on this machine is **~24 ms** — re-measured 2026-08-13, median
23.8 ms over 15 runs (min 23.2, max 26.0), superseding three earlier figures (56.3 ms, 20–30 ms,
~40 ms) that were never derived the same way twice. Derivation, so the next reader re-runs it rather
than inheriting it:

```sh
python3 -c "import subprocess,time; ts=[]
for _ in range(15):
    t=time.perf_counter(); subprocess.run(['python3','-I','-c','pass']); ts.append((time.perf_counter()-t)*1000)
ts.sort(); print('min=%.1f median=%.1f max=%.1f' % (ts[0], ts[7], ts[-1]))"
```

A **cheap bash pre-filter runs before any `python3`**: if the **raw payload text** does not contain
the substring `commit`, the hook exits 0 immediately.

**It filters the raw payload, not the parsed command.** The classifier is the sole command parser, so a
pre-filter working on "the command" would have to parse the payload to find one — the thing it exists
to avoid — and placing it after the runnable check would make `MSG_NOTHING_RUNNABLE` unreachable, since
an absent or empty command contains no `commit` substring. Filtering the raw payload keeps that door
reachable and honest: it fires exactly when the payload mentions `commit` **and** the parsed command is
absent, empty, or only whitespace. A payload with nothing runnable and no `commit` anywhere is allowed,
correctly — nothing in it can commit.

The filter skips only commands that could not classify as `COMMIT`, except for shapes already on the
accepted-open list (alias and variable indirection).

**Budgets — targets, not measurements; checklist task 10 measures and records all four.** The opt-in
reorder is what makes this four rows rather than three: an adopting repo pays **two** `python3` starts,
the inline `cwd` read and the classifier, and that cost is the price of the opt-in check sitting above
the classifier.

| payload | budget | what it pays for |
|---|---|---|
| no `commit` substring anywhere | **≤5 ms** | pure bash, no subprocess — the pre-filter exits 0 |
| mentions `commit`, repo has **not** opted in | **≤50 ms** | one `python3 -I` start (the inline `cwd` read) plus `rev-parse` and one `test -r`; the classifier never runs |
| mentions `commit` but is not one, in an adopting repo (`kind: OTHER` or `NOTHING_RUNNABLE`) | **≤110 ms** | the above plus a second `python3 -I` start and classification; no further git calls |
| an actual `git commit` in an adopting repo | **≤200 ms** | the above plus the collection and hashing calls |

If a measured figure exceeds its budget, the number gets recorded and the budget revised; it does not
get quietly dropped.

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

Scenario: a missing classifier cannot block a repo that has not opted in
  Given hooks/lib/classify-commit-command.py has been deleted or corrupted
    And the payload cwd is a repo with no hooks/lib/write-test-marker.py
   When "git commit -m msg" runs there
   Then the hook exits 0
   # the writer-installed check precedes the classifier, so a broken new file this
   # feature adds cannot become a machine-global lockout

Scenario: an unreadable payload is not a machine-global block
  Given a PreToolUse payload that is not valid JSON, or carries no cwd
   When the hook runs
   Then it exits 0
   # the target repo is unknowable, so the gate allows -- the same shape git-guard.sh:72 uses

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

Scenario: an abbreviated but valid option blocks rather than falling through to PLAIN
  Given hooks/foo.sh is staged with no marker
   When "git commit --am -m msg" runs
   Then the hook exits 2 with MSG_UNSUPPORTED_FORM
   # measured: git 2.50.1 accepts --am as --amend; a whitelist keyed to full spellings must
   # refuse it, not treat an unrecognised option as absent

Scenario: git commit -i does not sweep an untested staged file past the gate
  Given hooks/foo.sh is staged with no marker
    And docs/notes.md is modified and has no sibling test
   When "git commit -m msg -i -- docs/notes.md" runs
   Then the hook exits 2 with MSG_UNSUPPORTED_FORM naming the -i trigger
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
   Then the hook exits 2 with MSG_UNSUPPORTED_FORM naming the foreign-repo trigger
   # folding this trigger into UNSUPPORTED changed the message, never the refusal; reading
   # another repo's markers is the worst failure this gate has

Scenario: a missing classifier blocks in a repo that HAS opted in
  Given the repo has hooks/lib/write-test-marker.py installed
    And hooks/lib/classify-commit-command.py has been deleted
   When "git commit -m msg" runs
   Then the hook exits 2 with MSG_CLASSIFIER_MISSING
   # the same broken file that is harmless in a non-adopting repo must still fail closed here
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
   # precisely because the classifier does not strip

Scenario: an over-long exemption reason is rejected, not truncated
  Given the command sets TEST_EXEMPT to a 201-character value
   When the hook runs
   Then it exits 2 with MSG_BAD_EXEMPT

Scenario: an empty exemption is not an exemption
  Given hooks/foo.sh is staged with no marker
   When "TEST_EXEMPT= git commit -m msg" runs
   Then the hook exits 2 with MSG_NO_MARKER

Scenario: an explicit exemption is honoured
  Given hooks/foo.sh is staged with no marker
   When "TEST_EXEMPT=vendored upstream git commit -m msg" runs
   Then the hook exits 0
   # parsed out of the command STRING — a VAR=x prefix never reaches a hook's environment

Scenario: an exemption rescues a commit aimed at another repo
  Given the command targets another repo
   When "TEST_EXEMPT=other repo cd /other/repo && git commit -m msg" runs
   Then the hook exits 0
   # the exemption check precedes the form decision; the reverse order would make this
   # unreachable while MSG_UNSUPPORTED_FORM's own message recommends it

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

Scenario: a Bash payload that mentions commit but has nothing runnable blocks
  Given a repo that has opted in
    And a Bash payload that contains the substring "commit" somewhere
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
   # the hook already parsed the same bytes for cwd, so exit 3 here means two reads of one
   # payload disagreed — a liveness failure, and the dedicated code keeps it diagnosable

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
   # entry for it; a disk probe would report it present and hash a blob the commit never contains

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

**These block:** missing or unusable `python3`; a missing, empty, truncated, unreadable, or
wrong-output classifier; a classifier that cannot read a payload the hook already parsed; a malformed
or over-long `TEST_EXEMPT` value; **every `UNSUPPORTED` trigger — a `cd`/`-C`/`--git-dir`/`--work-tree`
commit, `-i`/`--include`, `--pathspec-from-file`, `-p`/`--patch`, `--interactive`, and any option
outside the whitelist**; **a non-zero exit from any git command the gate runs except the four whose
result is a defined answer**; an unreadable or malformed marker; a stale subject or test blob; a Bash
payload with nothing runnable.

**These do not, and are accepted:** command shapes the classifier cannot lex (quoted substitution
`X="$(git commit …)"`, backticks, `eval`, function/alias indirection, path-qualified `/usr/bin/git`,
and the `sudo`/`env`/`timeout` wrapper denylist gap); **a payload that does not parse as JSON or
carries no `cwd`**, where the target repo is unknowable and the gate allows exactly as
`git-guard.sh:72` does; a **hanging** helper, which needs a timeout and is deferred; any write that
does not arrive as a Bash `git commit`; any repo without the writer installed;
`panes/adapters/cmux.sh`, which no naming-conforming suite claims.

### Which doors are machine-global, and which are not

The gate is registered globally, so "fail closed" has to say *where*. **Exactly one door can block a
repo that has not opted in: `MSG_NO_PYTHON`.** It fires before the payload can be read, so there is no
cwd to resolve a toplevel from and no toplevel to check the writer against.

That single exception is **not a new hazard**, and the precedent is checkable rather than asserted:
`git-guard.sh:53-57`, `judge-guard.sh:44-48` and `merge-guard.sh:39-43` are all `PreToolUse`/`Bash`
registered today and all print a message and `exit 2` when `python3` is absent. A broken interpreter
already blocks every commit on this machine. (`doc-guard.sh:54` is the one that fails open, on the
stated ground that a documentation reminder is not worth blocking a commit over.)

**Every other door — all twelve — is downstream of node `G`.** This matters most for
`MSG_CLASSIFIER_MISSING`, `MSG_CLASSIFIER_FAILED` and `MSG_CLASSIFIER_BAD_OUTPUT`, because
`classify-commit-command.py` is a file *this feature introduces*: no sibling guard's precedent covers
it, and a missing or corrupt copy of it firing before the opt-in check would be a machine-global
lockout that does not exist today. Ordering the flowchart this way is what keeps §Scope's promise
literally true instead of approximately true.

### The doors

`exit 2` is not one door; it is **thirteen** — counted off the flowchart, one per `MSG_*` constant.

| # | constant | fires when |
|---|---|---|
| 1 | `MSG_BAD_PAYLOAD` | the classifier exits **3** — it cannot read a payload the hook already parsed |
| 2 | `MSG_NOTHING_RUNNABLE` | `Bash` payload with no runnable command |
| 3 | `MSG_NO_PYTHON` | `python3` missing or not executable — **the only machine-global door** |
| 4 | `MSG_CLASSIFIER_MISSING` | the classifier file is absent or unreadable |
| 5 | `MSG_CLASSIFIER_FAILED` | the classifier exits non-zero **other than 3**, or exits 0 printing nothing |
| 6 | `MSG_CLASSIFIER_BAD_OUTPUT` | output is not one JSON object passing every field check |
| 7 | `MSG_BAD_EXEMPT` | a non-empty `TEST_EXEMPT` fails `^[^\x00-\x1f\x7f]{1,200}$` |
| 8 | `MSG_UNSUPPORTED_FORM` | `form: UNSUPPORTED`. **The message names which trigger fired** — foreign repo, `-i`/`--pathspec-from-file`, `-p`/`--interactive`, or an off-whitelist option — because the remedies differ even though the refusal does not |
| 9 | `MSG_GIT_FAILED` | an unexpected non-zero exit from a collection or hashing command |
| 10 | `MSG_NO_MARKER` | a pair is in the path set with no marker file |
| 11 | `MSG_BAD_MARKER` | the marker exists but fails schema or path validation |
| 12 | `MSG_STALE_SUBJECT` | the marker is valid but the subject blob does not match |
| 13 | `MSG_STALE_TEST` | the marker is valid but the test blob does not match, or the test is ABSENT |

**Each row names its trigger, and no row restates a rule specified elsewhere.** Rows 1 and 5 partition
the classifier's exit codes and are the *only* place that mapping appears. Row 8's trigger is
`form: UNSUPPORTED`, so adding a trigger to that door is a change to the resolution table, not to this
one. **Anything a reviewer would otherwise have to keep in sync by hand lives in exactly one table,
with the others pointing at it.**

The suite asserts **the message, not just the code** — mutation testing on `judge-guard` showed 48
assertions that could not tell one door from another, and a mutant survived a happy 101/0 suite. Row 8
now carries four distinguishable triggers behind one constant, so its assertions must check the
**trigger named in the message**, not merely the constant.

**The allow paths need mutants too** — a gate that wrongly *allows* is this control's whole failure
mode. Counted off the flowchart, the **ten** are: the pre-filter finding no `commit`; a payload that
does not parse or carries no `cwd`; no repository; a repo without the writer; a non-Bash tool with no
command; a non-`COMMIT` command; a valid `TEST_EXEMPT`; `INVALID`; a path set containing no pairs; and
the happy path where every blob matches. **The scope cut removed no allow path**: deferring the log
changed what an exemption *records*, never that it allows.

**Mutation floor: 24** — one per door (13), one per allow path (10), plus emptying the classifier. A
two-mutant minimum against thirteen doors establishes nothing about the other eleven.

`MSG_NO_MARKER`'s remedy string is derived from the suite path and its extension — `bash <path>` for
`.sh`, `python3 <path>` for `.py` — never hardcoded to `bash`.

## Pinned versions

Measured on this machine, not recalled: **bash 3.2.57** (macOS system bash — no associative arrays, no
`mapfile`, no `${var,,}`), **Python 3.9.6** (stdlib only; `-I` drops the script directory from
`sys.path`, so no sibling imports), **git 2.50.1**, **shellcheck 0.11.0** (`/opt/homebrew/bin/shellcheck`
— check sets differ across releases and it gates checklist task 11).

## Testing requirements

- `hooks/test-marker-guard.test.sh` — throwaway git repo, payload on **stdin**, which is the production
  path. A hook tested only through its CLI path is a bug that has already shipped in this repo. Covers
  every `form` row against a real commit, not a simulated one, the inert-repo allow, **each of the four
  `UNSUPPORTED` triggers asserted by the trigger its message names**, **and the ordering itself: a repo
  with no writer must allow with the classifier deleted, while the same deletion in an adopting repo
  must block.** An ordering asserted only by reading the flowchart is not asserted.
- `hooks/lib/write-test-marker.test.py` — sibling derivation, `--full-name` normalisation from a
  subdirectory, the no-subject skip, atomic write, schema, file mode, failure exits. **The two
  repo-level inventory assertions are added at task 8**, not here at task 4, because until the 11
  pre-existing suites are wired the wiring assertion is legitimately red.
- `hooks/lib/classify-commit-command.test.py` — direct unit assertions on the JSON contract: **one
  case per grammar row G1-G9**, bundle decomposition with both attached and detached values, every
  value-taking flag in both groups, `--opt=value`, a `--` inside a value, every `form` including
  `NONE`, **every `UNSUPPORTED` trigger separately** (foreign-repo, `-i`, `--pathspec-from-file`,
  `-p`, `--interactive`, off-whitelist), `--amend`, the **unsanitised** `exempt` passthrough,
  exit 3 for an unreadable payload, and the accepted-open shapes, so closing one later is a conscious
  decision with a failing test rather than drift. **Every cell of the `kind` × field totality matrix
  gets its own assertion** — 18 cells, not just the `COMMIT` column. **This suite is where the two
  measured fail-opens are pinned; if any single file in this feature deserves over-testing, it is
  this one.**
- **Mutation check before the PR:** the 24 above.

## Checklist

- [ ] 1. ADR under `docs/decisions/` — record the marker-as-receipt framing, the three rejected
      designs (PostToolUse observer, `bin/run-tests` wrapper, mutual certification), the
      global-but-inert scope decision **and the node ordering that makes it true**, the
      `UNSUPPORTED` fold and what it deliberately kept blocking, the accepted-open shapes, and the
      `cmux.sh` coverage hole. Check the next free ADR number against `main` first.
- [ ] 2. Red: `classify-commit-command.test.py` — **the grammar first** (G1-G9, bundles, value-taking
      flags in both groups, `--opt=value`, `--` inside a value), **plus rule 0's wrapper stripping for
      every member of `WRAPPERS` — `rtk git commit …` must classify exactly as `git commit …`, and that
      case is the difference between an armed gate and a dead one** — and the closed whitelist:
      an abbreviated-but-valid option (`--am`, measured accepted by git 2.50.1) must resolve to
      `UNSUPPORTED` and **block**, not fall through to `PLAIN`. Then every `form` **in the order rule 4
      fixes**, including a command firing two triggers at once, `--amend`, raw `exempt` passthrough,
      **each `UNSUPPORTED` trigger asserted separately so the fold cannot silently drop one**, exit 3,
      ignored and genuinely accepted-open shapes (alias and variable indirection only),
      **and all 18 cells of the `kind` × field totality matrix**. ⚠️ The grammar's rule 2 is
      user-waived and unresolved — see the callout in §"The command grammar". Do not encode rule 2
      literally; this task is blocked on the shared-lexer decision landing in `shell_segments.py`.
- [ ] 3. Green: `hooks/lib/classify-commit-command.py`.
- [ ] 4. Red: `write-test-marker.test.py` — derivation, normalisation, no-subject skip, atomic write,
      schema, mode, failure exits. **No inventory assertion yet** — see task 8.
- [ ] 5. Green: `hooks/lib/write-test-marker.py`.
- [ ] 6. Red: `hooks/test-marker-guard.test.sh` — every scenario above, asserting message **and** code,
      plus the two opt-in-ordering scenarios, plus the four `UNSUPPORTED` triggers each asserted by the
      trigger its message names rather than by the shared constant alone.
- [ ] 7. Green: `hooks/test-marker-guard.sh`.
- [ ] 8. Wire the one-line call into **all 14 paired suites** — the 11 in §Scope's first table plus
      this feature's own 3 — using the call site exactly as §1 specifies it: **`MARKER_SELF` and
      `MARKER_ROOT` captured at the top, before any chdir, both absolute; the writer run with
      `MARKER_ROOT` as its cwd** (`cd` in a subshell for shell suites, `cwd=` for the three Python
      ones). `judge-guard.test.sh` cds at line 13 and pairs 12–13 build throwaway repos, so a
      bottom-of-file resolution is wrong in both languages. Add the two inventory assertions to
      `write-test-marker.test.py` in this same
      commit. **Own commit**, measured behaviour-neutral against the unmodified hook — never bundled
      with a green step. ⚠️ **Tasks 5 and 8 revert as a pair.** The **writer** is task 5, so reverting
      5 without 8 leaves 14 suites calling a deleted file. Reverting 8 alone is safe; it only disarms
      the wiring. See the revert-pair table under task 13 — **task 7 is half of the second pair**, and
      reverting it alone stops being harmless the moment task 13 lands.
- [ ] 9. Mutation check — the **24**-mutant floor (13 doors, 10 allow paths, emptied classifier);
      record the result in the checklist annotation. Re-derive the count from the flowchart before
      running it rather than trusting this number: revision 8 changed it, and a floor inherited from a
      superseded revision is the failure this line exists to prevent.
- [ ] 10. Measure the latency budgets and record **all four** numbers here — the fourth exists because
      the opt-in reorder splits the "mentions commit" case into adopting and non-adopting repos, which
      pay one `python3` start and two respectively. Revise a budget if a figure exceeds it rather than
      dropping it. Re-measure `python3 -I` startup with the derivation in §Latency rather than citing
      a remembered figure; three different numbers were recorded for it across three dates before the
      derivation was written down.
- [ ] 11. `shellcheck -x` (0.11.0) clean apart from pre-existing findings; confirm which are
      pre-existing by blame **before** claiming it, not after.
- [ ] 12. Gate stub in `rules/gates.md`; `hooks/README.md` entry. Both must state the global-but-inert
      scope **and name `MSG_NO_PYTHON` as its one exception**, or the next reader assumes either
      `.claude`-only or unconditional inertness. **Both must also say that v1 ships no way to query
      whether the gate is armed** — see the accepted cost in §Scope — so a reader looking for a
      `--status` does not conclude the entry is stale.
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
- [ ] 14. **First-arming check — the only proof v1 has that the gate is armed.** With `--status`
      deferred there is no query path, so this runs against the *installed* hook: pipe a real
      `git commit` payload in and expect a readable exit 2, not a silent 0 and not a hang; pipe a
      `git commit -am msg` payload and expect the same, since that spelling is the one the grammar
      exists for; pipe a `rtk git commit -m msg` payload and expect the same, since rule 0's wrapper
      stripping is the difference between an armed gate and a dead one. Then repeat from a repo
      **without** the writer and expect exit 0 — **and repeat that last case once more with the
      classifier temporarily renamed**, which is the check that the opt-in ordering actually holds in
      the installed copy. `judge-guard` shipped with this untested and the installed copy had no
      `lib/` at all.
- [ ] 15. Obs judge (implementation stage) pinning the final HEAD → PR.

**Standing decisions.**

- **Exit criterion.** If a judge round fails again with ids that have already recurred, **stop
  specifying and build**: the remaining items become test cases in task 6, not another round of prose.
  Invoking this needs an explicit decision from the user, never a silent one.
- **Waivers — two, both recorded in the frontmatter, both user decisions.** A judge citing either is
  arguing with a settled decision.
  1. `writing-specs/command-grammar` — rule 2 is unresolved and deferred to the shared lexer; see the
     callout in §The command grammar.
  2. `core-conduct/file-size-convention` — granted 2026-08-13 **after** the scope cut failed to reach
     800 and the composition measurement below showed why nothing else would. This reverses the
     earlier "no size waiver is to be sought" decision of the same date, which was taken while the
     scope cut was still expected to close the gap; **the premise was measured false, so the decision
     changed.** A third waiver is a user decision, not a drafting one.
- **O3 — the size question is now answered by measurement, and the answer is that 800 is unreachable.**
  Revision 7 cut the round-by-round narrative (deletion, not splitting; an ADR-0017 `.md`/`.spec.md`
  split was considered and rejected because it relocates bulk rather than reducing it). Revision 8 cut
  **feature scope** on the user's decision. Measured from git with
  `git show <commit>:<path> | wc -l`, not from memory:

  | commit | what it did | lines |
  |---|---|---|
  | `36a0880` | revision 7 — history cut | 1,448 |
  | `fa44399` | revision 8 — scope cut | 1,402 |
  | `0294809` | size waiver recorded | 1,413 |
  | revision 9 | this round-2 correction | 1,434 |

  ⚠️ **Do not trust a line count in this file without re-running the derivation; a composition table
  counts itself.** Round 2 caught two instances of exactly that. The figures here were measured at a
  transient **1,380**, then two more edits landed before the commit, so `fa44399` shipped **1,402** —
  and both this table and that commit's own message recorded 1,380 as a settled, "measured rather
  than estimated" fact. **The file grew while the paragraph describing its size was being written.**
  The derivation is therefore the durable artifact and every number is a dated snapshot of it:

  ```sh
  f=docs/features/verification-marker-gate.md
  tot=$(wc -l < "$f"); blank=$(grep -c '^$' "$f"); tbl=$(grep -c '^ *|' "$f")
  gherkin=$(awk '/^ *```gherkin/{g=1;next} /^ *```$/{g=0} g' "$f" | wc -l)
  code=$(awk '/^ *```(sh|python|json|mermaid)/{c=1;next} /^ *```$/{c=0} c' "$f" | wc -l)
  echo "total=$tot floor=$((blank+gherkin+tbl+code)) prose=$((tot-blank-gherkin-tbl-code))"
  ```

  Composition **as of revision 9**, from that command:

  | component | lines |
  |---|---|
  | Gherkin, 52 scenarios | 337 |
  | contract and measurement table rows | 128 |
  | code blocks (mermaid, sh, python, json) | 72 |
  | blank | 230 |
  | **non-prose floor** | **767** |
  | prose | 667 |

  **The floor is the finding, and it is robust to the drift above** — every re-measurement has moved
  the floor *up*, never toward 800. Deleting every line of prose in this file leaves 767, so an
  800-line version has a total prose budget of **33 lines** — for a spec that needs 667 to state its
  contracts, orderings and measured hazards. No amount of editing closes that gap. Reaching 800
  requires cutting Gherkin scenarios or contract tables, **both of which the user explicitly rejected**
  when choosing the scope cut over them.

  **Resolved 2026-08-13: the constraint that gives is the ceiling.** Three constraints — under 800, do
  not split, seek no waiver — were jointly unsatisfiable at this feature's scope, measured twice rather
  than argued, so the user waived the ceiling for this file (see §Standing decisions → Waivers). **Do
  not shave at this file further, and do not re-open the split**: both were considered against this
  measurement and rejected. The size is a recorded, accepted cost, not an open defect.

**Follow-ups this feature deliberately does not do.** The first three are **deferrals made by the
revision-8 scope cut** and are the first candidates for v2:

1. **The decision log.** `<repo>/hooks/state/test-marker.log`, one tab-separated line per non-trivial
   decision, answering "how often is this gate bypassed" and "does it ever fire at all". Revision 7
   specified it in full — four fields, machine-local storage, `0700`/`0600` modes, and the honest note
   that it is instrumentation rather than organisational evidence, since nobody else can read it and a
   developer who wants to hide a bypass can delete it. **v1 ships no log**, so `TEST_EXEMPT` erosion is
   currently unmeasurable. Recover the design from git history at revision 7 rather than rewriting it.
2. **`--status`.** `ACTIVE`/`INERT`, the resolved toplevel, the reason, decision counts, and a pair
   count — the last of which is what tells "armed and quiet" apart from "armed but silently never
   pairing". See the accepted cost under §Scope; task 14 is the one-off substitute.
3. **`-i`/`--include` and `--pathspec-from-file` supported properly** rather than refused, which needs
   a union of two collectors with a different content source on each side.

The rest are pre-existing and unchanged by the scope cut: rename `panes/adapters/cmux-exec.test.sh` to
match `cmux.sh` and close that coverage hole; bring `memsearch/tests/` under a sibling layout; give the
helper invocations a timeout; unify the four `git commit` lexers behind this classifier — **and,
separately and sooner, fix the `^git`-anchored fail-open now confirmed live in `git-guard.sh:89`,
`doc-guard.sh:123` and `checkpoint-before-modify.sh:97`**, which is its own piece of work and not
gated on this feature.

**Bootstrap note.** This gate covers `hooks/*.sh`, which includes its own files. It is not armed during
development because the harness loads the primary checkout's copy — the same reason a `judge-guard` fix
could not be gated by `judge-guard` until the primary checkout pulled it. Expect it to arm only after
merge, and treat task 14 as the first real test of that.
