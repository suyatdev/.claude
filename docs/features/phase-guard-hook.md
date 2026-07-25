---
phase: planning
model_tier: high
branch: none
---

# phase-guard.sh — computational enforcement of the phase gate

> First feature to run under the `docs/features/` workflow introduced by ADR 0010 (PR #29).
> Friction in the create → gate → restore cycle is itself a finding worth recording here.

## Problem

ADR 0010 moved permission for a class of work out of the conversation and into a file's `phase`
frontmatter, so it survives a `/clear`. It stopped there deliberately: **the permission is
recorded, not enforced.** Nothing prevents a session from writing implementation code while
`phase: planning`. Both observability-judge rounds on PR #29 flagged this, and the ADR discloses
it as a consequence rather than hiding it.

This feature asks whether to close that gap with a `PreToolUse` hook, and if so, how.

## The objection this design must answer

ADR 0010 rejected the hook on one specific ground, quoted verbatim:

> Resolving "which feature file is active" is ambiguous during planning (`branch: none`), so the
> hook would have to fail open in exactly the phase it most needs to hold.

That is the crux. A design that cannot answer it should not be built — "we'll fail open when
unsure" reduces to a hook that is silent precisely when `phase: planning` is being violated, which
is worse than no hook because it *looks* like enforcement.

## Proposed design — branch-scoped permission (answers Q2, the crux)

ADR 0010's objection assumes the hook must first resolve *which* feature file is active, then read
that file's `phase`. Under that framing the objection is correct and fatal: at `branch: none` there
is no key to look the file up by.

**The framing is avoidable.** The hook never needs to attribute a write to a feature. It needs one
bit, and it is a different bit: *does the current branch carry implementation permission?* That
question has a definite answer on every branch, including during planning.

> **Deny a guarded write when the repo has at least one feature file with `phase: planning`, AND
> the current branch is not recorded as `branch:` by any feature file with `phase: implementation`.**

Why this holds in the phase the ADR says it cannot: the workflow **forbids branch creation during
planning**, and the gate transition is what creates the branch and records it. So a planning session
is *by construction* sitting on a branch no feature file claims — `main`, or a worktree-isolation
branch like this one. The absence of a claim is not ambiguity; it is the signal. The lookup runs
forward (branch → is it claimed?), never backward (write → which feature?).

| Repo state | Current branch | Verdict |
|---|---|---|
| No `docs/features/` at all | any | **allow**, silently — answers Q5 |
| All files `review`, or `implementation` on other branches | any | **allow** |
| A file is `implementation` with `branch: B` | `B` | **allow** |
| A file is `planning` *and un-superseded* | branch unclaimed (`main`, worktree, hotfix) | **deny** |
| Feature A `implementation` on `bA`; feature B `planning` | `bA` | **allow** — B's planning must not revoke A's permission |
| File reads `planning` here, but some branch has it at `implementation` **or `review`** | any | **allow** — superseded; its gate already opened (the narrowing) |
| Any of the above | **detached HEAD** (rebase, bisect, `git checkout <sha>`) | **allow**, silently — see below |

**Detached HEAD (added round 2, compliance `writing-specs/edge-cases`).** `git rev-parse
--abbrev-ref HEAD` returns the literal string `HEAD` when detached — verified on git 2.50.1. No
feature file can ever record `branch: HEAD`, so the naive reading denies *every* source write
throughout a rebase or bisect and advises the session to record a branch name that is not one.
This file's own Notes record a concurrent session mid-rebase, so the state is not hypothetical.
→ **Allow, silently.** A detached HEAD is a transient mechanical git state, not a statement about
phase; the hook cannot infer permission from it either way, and Q3's blast-radius argument governs.
Silent rather than warned because a rebase issues many writes and a per-write line would be noise.

**Residual weakness, stated plainly:** the hook enforces permission at *branch* granularity, not
per-feature attribution. While on a claimed implementation branch `bA`, a session could write source
belonging to a different, still-planning feature and the hook would allow it. That is a real hole —
but it is far narrower than "fails open during the entire planning phase", and it is the honest
boundary of what a `PreToolUse` hook can know.

**Second-order cost:** after the gate opens, `main` still carries the feature file at
`phase: planning`, so source writes on `main` stay denied until the PR merges and `phase` advances.
Consistent with `git-guard.sh` already blocking app-code commits to `main`, but it also catches an
unrelated hotfix branch cut from `main`. A stale, abandoned `planning` file locks the repo the same
way — the deny message must therefore name the offending file(s) so the fix is obvious.

## Open questions — resolutions

1. **Has the trigger condition actually been met?** ADR 0010 says build this "when the gate is
   observed being skipped, not before" (the `spec-guard` precedent). No skipped phase gate has been
   observed to date. Building now overrides the ADR's own stated deferral rule — a legitimate
   choice, but it must be a deliberate one, and it amends ADR 0010 rather than merely extending it.
   → **Deliberately deferred to the gate decision** (user, this session). Planning proceeds so the
   build/defer call is made against a real design rather than against an unknown.
2. **How does the hook identify the active feature file?** → **Resolved: it does not.** See the
   design above. The four candidates previously listed (`branch:` reverse-lookup, machine-local
   pointer, "exactly one non-`review` file", most-recently-modified) all inherit the wrong framing;
   each tries to name the active feature. Branch-scoped permission sidesteps all four.
   → **Accepted by the user (2026-07-25), with one narrowing: the un-superseded check.** See
   "Narrowing accepted" below. Q2 is now settled; the remaining work is spec form, not design.
3. **Fail open or fail closed on ambiguity?** → **Resolved: fail closed *within scope*, and the
   scope is delimited by the existence of `docs/features/`.** A repo with no feature files is out of
   scope and allowed silently, which is what makes Q5 answerable at all.
   **But the fail-mode on *infrastructure* failure must diverge from `judge-guard.sh`, deliberately.**
   `judge-guard` fails closed when python is missing or the repo can't be resolved; it guards one
   rare command, so a false block costs a single retry. This hook fires on **every write in every
   repo** — a false block costs the whole session, in repos that never opted in. Blast radius, not
   inconsistency, drives the split: **fail closed only once a `planning` file is positively
   identified; fail open on inability to resolve git root, python, or frontmatter.**
4. **What exactly is a guarded write?** `Edit`/`Write`/`NotebookEdit` whose `file_path` is a source
   path, excluding `docs/**`, the feature file itself, and machine-local `.claude/**`. The
   source/doc split already exists at `hooks/doc-guard.sh:149` (`CODING_MEMORY.md`,
   `coding-memory/*`, `docs/*`) and should be reused, not re-invented. → **Carried as specified.**
   One addition the spec must handle: the payload's `file_path` is absolute, so it needs
   relativizing against `git rev-parse --show-toplevel` before that classification applies.
5. **Multi-repo behavior.** These hooks are global (`~/.claude/hooks/`) and fire in every repo.
   Most repos have no `docs/features/` at all. Absence must be unambiguously "not applicable",
   never "blocked". → **Resolved by row 1 of the table**, and it must be the hook's *first* check:
   one `stat` on `docs/features/`, exit 0, before any parsing. This path runs on every write.
6. **Does it supersede or complement the escape hatch pattern?** Both existing guards carry a
   logged env-var bypass (`JUDGE_EXEMPT`, `MERGE_EXEMPT`). Consistency argues for `PHASE_EXEMPT`.
   → **The pattern does not transfer, and this is a genuine finding.** `JUDGE_EXEMPT` works because
   it is an inline env-assignment on a *Bash command line* the hook parses out of the payload. An
   `Edit`/`Write` payload has no command-line surface to carry one. The remaining options are a
   session-wide exported `PHASE_EXEMPT` (far blunter — no per-write reason to log), a sentinel file,
   or **no bypass at all**, on the grounds that the honest way to earn write permission is to open
   the gate. → **Resolved (user, 2026-07-25): no bypass at all — no `PHASE_EXEMPT`, no sentinel
   file.** The justification is stronger than "be strict": **the escape hatch already exists
   structurally.** Feature files live under `docs/**`, which this hook does not guard, so a locked
   repo is *always* unlocked by editing the offending `phase:` frontmatter — precisely the fix the
   deny message names. A second bypass would add only one capability: letting a session skip the
   gate the hook exists to hold. A branch-name allowlist was also considered and rejected for the
   same reason — "name your branch `hotfix/` to write freely" is `PHASE_EXEMPT` through a
   different door, and shipping a bypass implicitly is worse than shipping one honestly.
   → **Qualified in round 2:** "no bypass at all" is true of *deliberate* bypasses, but the
   `Edit|Write|NotebookEdit` matcher leaves the whole **Bash-tool write surface** unguarded (see
   Non-goals). That is an unclosed hole, not a designed escape hatch — but the deny message must
   not claim otherwise, so it asserts that no bypass *environment variable* exists rather than that
   no route exists. Shipping a bypass implicitly is worse than shipping one honestly, and the same
   applies to a safety message that overclaims.

### New question raised by this design

7. **Does the hook enforce the reverse direction too?** The phase rules say implementation forbids
   spec and checklist edits. Enforcing that means denying edits to a feature file's Spec/Tasks
   sections while on a claimed implementation branch — which requires reasoning about *which section*
   of a markdown file an `Edit` touches, from `old_string`/`new_string`. Fragile. Recommend
   **out of scope**; the forward direction is where the value is. → **Carried as out of scope**
   (recommendation stated to the user 2026-07-25, not contested). Reopen only if a real
   implementation-phase spec edit is observed causing harm.

## Prior art in this repo (read before designing — do not re-derive)

| File | Why it matters |
|---|---|
| `hooks/judge-guard.sh` | Fail-closed safety gate; `PreToolUse`, python payload parsing, strict-equality freshness check, logged env bypass. The closest structural sibling. |
| `hooks/doc-guard.sh` | Fail-open momentum guardrail; owns the source-vs-docs path classification this hook should reuse (`:149`). |
| `hooks/git-guard.sh` | The inline-regex parser trap documented in both files — regexes live in variables, never inline in `[[ ]]`. |
| `docs/decisions/0010-*.md` | The deferral being revisited, and its four rejected alternatives. |

## Narrowing accepted — the un-superseded check

Both disclosed second-order costs share one root cause: **the hook treats "a `planning` file exists
in this checkout" as "this checkout is in planning."** Once the gate opens on branch `B`, `main`'s
copy of that file is stale *by design* — the frontmatter advanced on `B`, not on `main` — and every
branch cut from `main` inherits the staleness. So:

> Before denying on a `planning` file `F`, check whether any branch records `F` as
> `phase: implementation`. If one does, `F`'s gate has already opened and `F` stops denying anywhere.

Still a forward lookup — "has this file's gate opened?" has a definite answer and needs no
attribution. Unlocks hotfix branches after the gate without a naming convention.

**What it widens:** while on `main`, source for an already-gated feature becomes writable. Accepted
because `git-guard.sh` independently blocks app-code commits to `main`, so the write cannot land —
the same layering argument the base design already used for this cost.

**What it does not fix:** the stale-abandoned-`planning`-file case. Nothing branch-based can — that
file's gate never opened anywhere. The deny message naming the offending file stays the only fix.

## Design detail settled during planning

The Spec formalizes this into Gherkin; it is recorded here so it is not re-derived.

**Registration.** `PreToolUse`, new matcher block `Edit|Write|NotebookEdit` in `settings.json`
(the existing `PreToolUse` blocks are `Bash`, `Task|Agent`, `*` — this is a fourth, not an edit to
an existing one). Exit 0 = allow silently; exit 2 = deny with reason on stderr.

**Order of operations** (fail-open exits are marked ⊘):

1. Read stdin payload; empty → ⊘.
2. `git rev-parse --show-toplevel`; not a repo / fails → ⊘.
3. `stat` `<root>/docs/features`; absent → ⊘. *(Q5's cheap early exit — the common case in every
   repo that never opted in. Deliberately **after** step 2, not before: a bare `stat ./docs/features`
   assumes the hook's CWD is the repo root and would silently stop working from a subdirectory.)*
4. Resolve the interpreter as the siblings do — `py=$(command -v python3 || command -v python)`
   (`judge-guard.sh:28`, `doc-guard.sh:49`) — and parse the payload → `tool_name`, and the path:
   `tool_input.file_path` (`Edit`/`Write`), falling back to `tool_input.notebook_path`
   (`NotebookEdit`). Neither key → ⊘. **No interpreter → ⊘ *and* print one line, once per session**
   (see "Two exits that must not be silent").
   *(Corrected 2026-07-25 against the live tool schema: `NotebookEdit` has **no** `file_path` — its
   only path key is `notebook_path`. Reading `file_path` alone, as this step originally said, would
   have failed open on every notebook write.)*
5. Relativize `file_path` against the root (payload paths are absolute); outside the root → ⊘.
6. Classify the path — **reuse `doc-guard.sh:149` verbatim**, plus `.claude/*` and `settings.json`:
   `CODING_MEMORY.md`, `coding-memory/*`, `docs/*`, `.claude/*`, `settings.json` → unguarded → ⊘.
   Else guarded. *(`settings.json` is exempt because it is this hook's own off switch — see
   "Rollback".)*
7. Parse frontmatter of `docs/features/*.md` in the working tree per the **Frontmatter contract**
   below; a file that violates it is skipped (⊘ for that file only). Collect `planning_files`;
   empty → ⊘. If **every** file was skipped, ⊘ *and* print one line, once per session.
8. **Un-superseded filter.** Drop any `F` that reads `implementation` **or `review`** on some
   branch — `review` included because a *finished* feature whose `main` copy still reads `planning`
   would otherwise block forever (observability round 1). Read every branch's copy in **one**
   subprocess — `git for-each-ref --format='%(refname:short)' refs/heads/` piped into
   `git cat-file --batch` as `<branch>:<path>` lines — never one `git show` per branch, which is
   O(branches) processes on a hook that fires on every write. Empty after filtering → ⊘.
   **Either git call failing (nonzero exit) → ⊘.** An empty `for-each-ref` (a repo with no local
   branches) is not a failure: nothing supersedes, so every candidate survives to step 9.
9. Read the current branch: `git rev-parse --abbrev-ref HEAD`. **Nonzero exit or empty output → ⊘.**
   Output is the literal `HEAD` (detached) → ⊘. Otherwise `claimed` = any working-tree feature file
   with `phase: implementation` **and** `branch:` equal to that value. Claimed → ⊘.
10. Otherwise **deny (exit 2)**.

**Fail-closed only at step 10** — after a `planning` file is positively identified, confirmed
un-superseded, and the branch confirmed unclaimed *and not detached*. Everything upstream fails open
(Q3): this hook fires on every write in every repo, so a false block costs the whole session, in
repos that never opted in. That is the deliberate divergence from `judge-guard.sh`, which fails
closed because it guards one rare command where a false block costs a single retry.

**The two git subprocesses in steps 8–9 are covered by that rule explicitly** (added round 2,
compliance `core-conduct/explicit-error-handling`). Steps 1–7 each named a ⊘ exit; steps 8–9
originally named none, and the only path onward from them is *deny* — so a transient `git` failure
would have flipped the hook from fail-open to fail-everything, inverting Q3's own principle in the
two steps most likely to fail on a large repo.

### Frontmatter contract

Added round 2 (compliance `writing-specs/ambiguity`). Without this, "fails frontmatter parsing" is
undefined, Task 1's test cannot be written without inventing the rule, and a typo like
`phase: plannning` silently disables a CRITICAL gate.

A feature file is **well-formed** iff all of:

1. its first line is exactly `---`, and a closing `---` appears on a later line;
2. between them, a line matching `^phase:[[:space:]]*(planning|implementation|review)[[:space:]]*$`;
3. between them, at most one `phase:` line and at most one `branch:` line.

`branch:` is **optional** — its absence means unclaimed, which is the `branch: none` case and needs
no special value. Any other content between the fences is ignored, so `model_tier` and future keys
are forward-compatible.

A file failing any of the three — including a `phase:` value outside the three legal ones — is
**skipped**, never guessed at. Skipping fails open, per Q3. But a skipped file in a repo that *has*
opted in is the "cannot evaluate" case, so it is one of the two exits that print.

### Two exits that must not be silent

Added round 2 (observability round 1). A working guard and a dead one are otherwise byte-identical:
every ⊘ exit emits nothing, and the Group A tests assert exactly that. Six of the eight are
correctly silent — they mean "not applicable here". Two are different in kind, because they mean
**this repo opted in and the guard could not evaluate it**:

| Exit | Why it is different |
|---|---|
| No python interpreter (step 4) | The guard is off in *every* repo, permanently, until PATH is fixed |
| Every `docs/features/*.md` skipped (step 7) | This repo opted in and the guard cannot read its own input |

Both print one line to stderr and **still exit 0**. Once per session, keyed off the payload's
`session_id` with `$CLAUDE_CODE_SESSION_ID` as fallback — the pattern `pane-dispatch-guard.sh:43-50`
already establishes, including surfacing a divergence between the two rather than silently missing
the flag. Per-write printing is not acceptable on this hot path.

### Rollback

Added round 2 (observability round 1). Registered globally in `settings.json`, so a misbehaving
build affects every repo on the machine. Three exits, cheapest first:

1. **Edit the offending feature file** — the ordinary fix, and the one the deny message names.
   Feature files live under `docs/**`, which is unguarded.
2. **Delete the `PreToolUse` block from `settings.json`** — the hook exempts `settings.json`
   (step 6) precisely so it can never block edits to its own off switch. Without that exemption a
   misfiring guard would be reachable only through the Bash-tool hole, which the deny message would
   have to advertise — telling every session where the bypass is.
3. **`chmod -x hooks/phase-guard.sh`** — a non-executable hook is skipped by the harness.

**Deny message must contain** — the offending file path(s) and their `phase:`, the current branch,
both legitimate fixes (open the gate: `gate confirmed` → advance `phase:` and record `branch:`; or,
if the file is stale, advance or delete it), and an explicit statement that **no bypass env var
exists**, so a session does not go hunting for one. That last clause must say *env var*, not "no
way around this": the Bash-tool write surface is unguarded (see Non-goals), and a safety message
that overclaims is worse than one that is narrow and true.

**Toolchain.** `bash` + `python3` (JSON payload only — frontmatter is `awk`/`sed`, no second
parser) + `git`. Regexes in variables, never inline in `[[ ]]` — the trap documented at
`git-guard.sh:22`. Tests follow the established `hooks/<name>.test.sh` convention (siblings:
`judge-guard.test.sh`, `pane-dispatch-guard.test.sh`, `context-handoff-watch.test.sh`).

### Process finding — `writing-specs` and ADR 0010 disagree on where specs live

`writing-specs` says "Defer to `docs/superpowers/specs/` … do not open a competing `specs/`
convention." ADR 0010's one-canonical-file discipline says feature-scale work lives entirely in
`docs/features/<name>.md`, spec section included. Both are live rules and they now contradict.
Resolved here in favor of ADR 0010 (project-level, and newer), which is why this Spec is inline.
**This is exactly the dogfooding friction this file was opened to catch.** It needs a real fix —
amend `writing-specs` to carve out feature-scale work — but that is its own task, not this feature's.

## Spec

### Artifacts

| Path | Kind |
|---|---|
| `hooks/phase-guard.sh` | new, executable (755) |
| `hooks/phase-guard.test.sh` | new, 644 — matches the sibling convention |
| `settings.json` | one added `PreToolUse` block, matcher `Edit|Write|NotebookEdit` |
| `rules/gates.md` | **amendment to the existing `Phase gate` stub at `:5`** — not a new bullet |
| `docs/decisions/0011-*.md` | ADR — this **amends** ADR 0010, which deferred the hook |

### Pinned toolchain

Verified on this machine 2026-07-25; the hook must run under exactly these.

| Tool | Version | Constraint it imposes |
|---|---|---|
| `bash` | 3.2.57 (system, `arm64-apple-darwin25`) | **No bash-4 features** — no associative arrays, no `mapfile`/`readarray`, no `${var,,}`. `#!/usr/bin/env bash` resolves here. |
| `python3` | 3.9.6 | JSON payload parse **only**. No third-party imports, no PyYAML. |
| `python` (fallback) | whatever `command -v python` resolves to, **or absent** | Resolved as `command -v python3 \|\| command -v python`, the sibling convention (`judge-guard.sh:28`, `doc-guard.sh:49`). The hook must therefore use only syntax valid in **both** py2 and py3 — `json.load(sys.stdin)`, `print(...)` as a single-arg call, no f-strings. Absent on this machine; the fallback exists for parity with the siblings, not because it is exercised here. |
| `awk` | BWK awk 20200816 (system) | **Not** GNU awk: no `gensub`, no `IGNORECASE`, no `\|` alternation in ERE without `--re-interval` caveats. |
| `sed` | BSD sed (macOS; no `--version`) | **Not** GNU sed: no `-r` (use `-E`), no `\+`/`\?`, and **never a bare `sed -i`** — BSD requires an extension argument (`sed -i ''`). The same dialect trap `bash 3.2.57` is pinned against. |

Regexes live in variables, never inline in `[[ ]]` (`git-guard.sh:22`).

### Contracts

**Input** — `PreToolUse` JSON on stdin:

```yaml
hook_event_name: PreToolUse
tool_name: Edit | Write | NotebookEdit
tool_input:
  file_path: /absolute/path      # Edit, Write
  notebook_path: /absolute/path  # NotebookEdit — the ONLY path key it carries
```

**Output** — exit `0` = allow. Exit `2` = deny, reason on stderr. No other exit code is legitimate:
under `set -u` an unbound variable exits 1, and a fail-open path that leaks a nonzero code is a
defect regardless of how the harness classifies it. Every ⊘ path therefore exits 0 **explicitly**.

An allow emits nothing on stdout or stderr, with exactly two exceptions — the no-interpreter and
all-files-skipped exits of "Two exits that must not be silent", which print one stderr line at most
once per session and still exit 0. stdout is empty on every path without exception.

**Deny message** — must contain all four, or the block is unactionable:

1. every offending feature-file path, and its `phase:`;
2. the current branch name;
3. both legitimate fixes — open the gate (`gate confirmed` → advance `phase:`, record `branch:`),
   or, if the file is stale/abandoned, advance or delete it;
4. the literal statement that **no bypass environment variable exists** (Q6), so the session does
   not go hunting for a `PHASE_EXEMPT` that was deliberately never built.

### Scenarios

```gherkin
Background:
  Given the global PreToolUse hook phase-guard.sh is registered for Edit|Write|NotebookEdit
  And a guarded write is one whose path is NOT CODING_MEMORY.md, coding-memory/*, docs/*, or .claude/*
```

**Group A — out of scope: allow (exit 0).** Each is a ⊘ exit from the order-of-operations, in order.
The shared assertion is `exit 0 AND stdout is empty`; stderr differs by subgroup.

**A1 — silent fail-open.** Assertion: `exit 0 AND stderr is empty`. These mean *not applicable
here*, and this is the common case in every repo that never opted in.

```gherkin
Scenario Outline: fail open silently rather than block a session that never opted in
  Given <precondition>
  When any Edit/Write/NotebookEdit is attempted
  Then the hook exits 0 and writes nothing on stdout or stderr

Examples:
  | #  | precondition                                                           | step |
  | 1  | stdin is empty                                                         | 1  |
  | 2  | the working directory is not inside a git repository                   | 2  |
  | 3  | <root>/docs/features/ does not exist                                   | 3  |
  | 4  | tool_input carries neither file_path nor notebook_path                 | 4  |
  | 5  | the resolved path lies outside the repository root                     | 5  |
  | 6  | no docs/features/*.md has phase: planning                              | 7  |
  | 7  | git for-each-ref exits nonzero                                         | 8  |
  | 8  | git cat-file --batch exits nonzero                                     | 8  |
  | 9  | git rev-parse --abbrev-ref HEAD exits nonzero or prints nothing        | 9  |
  | 10 | git rev-parse --abbrev-ref HEAD prints the literal HEAD (detached)     | 9  |
```

Examples 7–9 are the round-2 fix for `core-conduct/explicit-error-handling`: without them the only
path onward from steps 8–9 is *deny*, so a transient `git` failure blocks every write. Example 10 is
the detached-HEAD fix (`writing-specs/edge-cases`) — reachable during any rebase or bisect.

```gherkin
Scenario: a repo with no local branches supersedes nothing but does not fail
  Given docs/features/a.md has phase: planning
  And git for-each-ref refs/heads/ succeeds but returns no lines
  And the current branch is claimed by no feature file
  When a guarded write is attempted
  Then the hook exits 2
```

Empty output from `for-each-ref` is **not** a failure — nothing supersedes, so every candidate
survives to step 9. This scenario exists to stop an implementer conflating "no branches" with
"git broke" and fail-opening a real deny.

**A2 — fail-open, but audible.** Assertion: `exit 0 AND stderr contains one line AND a second
invocation in the same session adds none`. These mean *this repo opted in and the guard could not
evaluate it*, which a green test suite would otherwise render byte-identical to a dead hook.

```gherkin
Scenario Outline: say so when the repo opted in but the guard cannot evaluate it
  Given <root>/docs/features/ exists
  And <precondition>
  When a guarded write is attempted twice in one session
  Then the hook exits 0 both times
  And stderr carries exactly one line in total, naming the reason

Examples:
  | # | precondition                                            | step |
  | 1 | python3 and python are both absent from PATH            | 4  |
  | 2 | every docs/features/*.md violates the frontmatter contract | 7 |
```

**A3 — the frontmatter contract is testable.** One scenario per clause, because "fails parsing" was
undefined until round 2 and Task 1 could not otherwise be written.

```gherkin
Scenario Outline: a malformed feature file is skipped, never guessed at
  Given docs/features/bad.md <defect>
  And docs/features/good.md has phase: planning
  And the current branch is claimed by no feature file
  When a guarded write is attempted
  Then the hook exits 2
  And stderr names docs/features/good.md
  And stderr does not name docs/features/bad.md

Examples:
  | # | defect                                                        |
  | 1 | has no opening --- on line 1                                  |
  | 2 | has an opening --- but no closing ---                         |
  | 3 | has phase: plannning          (typo — not one of the three)   |
  | 4 | has phase: Planning           (wrong case)                    |
  | 5 | has two phase: lines                                          |
  | 6 | has no phase: line at all                                     |

Scenario: a missing branch: key means unclaimed, not malformed
  Given docs/features/a.md has phase: implementation and no branch: key
  And the current branch is feat/a
  When a guarded write is attempted
  Then the hook exits 2

Scenario: unknown frontmatter keys are forward-compatible
  Given docs/features/a.md has phase: planning, model_tier: high, and a future key
  And the current branch is claimed by no feature file
  When a guarded write is attempted
  Then the hook exits 2
  And stderr names docs/features/a.md
```

Example 3 is the one that matters most: before the contract existed, a one-character typo silently
switched a CRITICAL gate off with no complaint.

Scenario 3 must be reached **only after** the repo root is resolved (step 2). A bare
`stat ./docs/features` assumes the hook's CWD is the repo root and silently stops guarding from any
subdirectory — the failure mode is invisible, which is what makes it worth pinning here.

```gherkin
Scenario: an unguarded path is never blocked, even mid-planning
  Given docs/features/a.md has phase: planning
  And the current branch is claimed by no feature file
  When a write targets docs/features/a.md, docs/decisions/0011.md, CODING_MEMORY.md,
       coding-memory/x.md, .claude/session-state.md, or settings.json
  Then the hook exits 0 and writes nothing
```

This scenario *is* the escape hatch (Q6). A repo locked by a stale `planning` file is always
unlocked by editing that file's frontmatter, because feature files live under `docs/**`.
`settings.json` joins the list in round 2: it holds this hook's own registration, and a guard that
can block edits to its own off switch is a footgun — see "Rollback".

**Group B — permission decisions.** One scenario per row of the design table.

```gherkin
Scenario: planning file, unclaimed branch -> DENY            # the core case
  Given docs/features/a.md has phase: planning
  And no branch records docs/features/a.md at phase: implementation
  And the current branch is main
  When a guarded write is attempted
  Then the hook exits 2
  And stderr names docs/features/a.md, names branch main, gives both fixes,
      and states that no bypass env var exists

Scenario: the branch is claimed -> ALLOW
  Given docs/features/a.md has phase: implementation and branch: feat/a
  And the current branch is feat/a
  When a guarded write is attempted
  Then the hook exits 0

Scenario: one feature planning must not revoke another's open gate -> ALLOW
  Given docs/features/a.md has phase: implementation and branch: feat/a
  And docs/features/b.md has phase: planning
  And the current branch is feat/a
  When a guarded write is attempted
  Then the hook exits 0

Scenario: superseded planning file stops denying everywhere -> ALLOW    # the narrowing
  Given docs/features/a.md reads phase: planning in the working tree
  And branch feat/a's copy of docs/features/a.md reads phase: implementation
  And the current branch is hotfix/x, claimed by no feature file
  When a guarded write is attempted
  Then the hook exits 0

Scenario: a finished feature stops denying too -> ALLOW              # review, not just implementation
  Given docs/features/a.md reads phase: planning in the working tree
  And branch feat/a's copy of docs/features/a.md reads phase: review
  And the current branch is main, claimed by no feature file
  When a guarded write is attempted
  Then the hook exits 0

Scenario: a NotebookEdit is guarded like any other write
  Given docs/features/a.md has phase: planning and the branch is unclaimed
  When NotebookEdit is attempted with tool_input.notebook_path = <root>/analysis.ipynb
  Then the hook exits 2
```

The last scenario is the regression test for the `file_path`-only bug corrected above; without it,
the guard silently exempts an entire tool.

**Group C — the un-superseded lookup.** Behavioral contract, because a naive implementation is
O(branches) subprocesses on a hook that fires on every write.

**Mechanism, pinned (round 2, observability round 1).** No sibling test counts processes, so left
unspecified the test an implementer writes will assert *answers* — which the O(branches)
implementation also produces, passing either way and measuring nothing. The assertion is therefore
made structural, not behavioural:

> The test prepends a temp dir to `PATH` containing an executable `git` shim. The shim appends its
> own argv to a counter file, then `exec`s the real `git` (resolved by absolute path, captured
> before the shim is installed, so it cannot recurse). The assertion reads the counter file.

Chosen over a wall-clock or bytes budget: a timing threshold is flaky on a loaded machine and would
be the kind of test that gets deleted the first time CI goes red for an unrelated reason.

```gherkin
Scenario: every branch's copy is read in exactly one subprocess
  Given N local branches and M candidate planning files
  And a counting git shim is first on PATH
  When the un-superseded filter runs
  Then the counter file records exactly one `cat-file --batch` invocation
  And exactly one `for-each-ref` invocation
  And zero `git show` invocations
  And the cat-file process is fed N*M lines of the form <branch>:<path>
```

**Subprocess count is not the whole cost.** One `cat-file --batch` still streams every matching
file *in full* — measured ~26KB / ~26ms with only one branch holding a feature file — and that grows
linearly as this workflow succeeds and feature files accumulate. Recorded, not fixed: the fix is
`--batch-check` plus a second pass for only the blobs whose size warrants reading, which is
premature until a repo actually has enough feature files to feel it. Revisit if the hook is measured
above ~50ms on a real repo.

Parser contract, verified against git 2.50.1 — the two output forms are **not** symmetric:

| Input line resolves to | `cat-file --batch` emits |
|---|---|
| a blob | `<sha> blob <size>` then the content — **the request is not echoed** |
| nothing (path or branch absent) | the request line verbatim, then ` missing` |

Because present objects do not echo their request, results **must** be consumed in input order; a
parser that keys off the echoed line only will mis-attribute every blob. Ref names cannot contain
`:` or whitespace, so splitting a request line on its first colon is safe.

### Non-goals

- **Reverse enforcement** (blocking spec/checklist edits during implementation) — Q7, out of scope.
- **Per-feature attribution.** The hook enforces at *branch* granularity; on a claimed branch a
  session can still write source for a different, still-planning feature. Stated as a known hole,
  not a defect to fix — it is the honest boundary of what `PreToolUse` can know.
- **Any bypass mechanism** — no env var, no sentinel file, no branch-name allowlist (Q6).
- **Source writes issued through the Bash tool.** Added round 2
  (compliance `writing-specs/coverage-gap`). The matcher is `Edit|Write|NotebookEdit`, so
  `sed -i`, `cat > file`, `tee`, `python -c`, `git checkout -- <path>`, and every other shell route
  to writing a file are **unguarded** — and none of the hooks already on the `Bash` matcher
  (`git-guard.sh`, `merge-guard.sh`, `judge-guard.sh`) inspects file writes either. Out of scope
  because closing it means classifying arbitrary shell as write-or-not, which is the parsing problem
  `judge-guard.sh` needed `shlex` for and still only solves for a fixed command set; a guard that
  catches 60% of shell writes invites more trust than one that honestly catches none.
  **This is the hole that makes rollback path 2 reachable** if `settings.json` were ever guarded —
  and the reason the deny message says "no bypass *environment variable* exists" rather than the
  false "there is no way around this".

**Why the Bash hole does not sink the design.** It is a momentum guardrail, not a security boundary
— the same framing `merge-guard.sh` already carries in `rules/gates.md` ("a chained
`foo && gh pr merge` is not caught"). The threat model is a session with genuine intent drifting
into implementation while the card still reads *planning*, not an adversary routing around a hook it
knows about. A session that reaches for `sed -i` to defeat the guard has made a deliberate choice
the hook was never meant to prevent, and `git-guard.sh` and `doc-guard.sh` still stand between that
write and a commit.

## Tasks

Frozen at the gate; adding tasks after the gate opens is forbidden by the phase rules. Tests precede
implementation in every pair — the test is the unbiased baseline.

- [ ] 1. `hooks/phase-guard.test.sh` — Group A1 (the 10 silent ⊘ exits, asserting exit 0 **and
      empty stderr**), the no-local-branches scenario, and the unguarded-path scenario incl.
      `settings.json`. Red against a nonexistent hook.
- [ ] 2. `hooks/phase-guard.sh` — steps 1–6 (payload, git root, `docs/features` stat, interpreter
      resolution via `command -v python3 || command -v python`, parse incl. `notebook_path`,
      relativize, path classification reusing `doc-guard.sh:149` plus `.claude/*` and
      `settings.json`). Green for Group A1's steps 1–5 examples.
- [ ] 3. Extend the test with Group A3 — the eight frontmatter-contract scenarios (six malformed
      shapes, optional `branch:`, forward-compatible unknown keys).
- [ ] 4. Implement step 7 to the Frontmatter contract. Green for A3.
- [ ] 5. Extend the test with Group B: the five permission rows (incl. the `review`-supersession
      scenario) + the NotebookEdit regression, and Group A1 examples 7–10 (both git failures,
      empty/failed `rev-parse`, detached `HEAD`).
- [ ] 6. Implement steps 8–10: un-superseded filter accepting **`implementation` or `review`**,
      explicit ⊘ on either git call failing, detached-HEAD ⊘, claimed-branch check, deny.
- [ ] 7. Extend the test with Group C: install the counting-`git` PATH shim, assert exactly one
      `cat-file --batch` / one `for-each-ref` / zero `git show`, and assert the input-order parser
      against both `blob` and `missing` output forms.
- [ ] 8. Extend the test with Group A2 — the two audible fail-opens, asserting one stderr line and
      that a second invocation in the same session adds none. Then implement the once-per-session
      flag, keyed off `session_id` with `$CLAUDE_CODE_SESSION_ID` fallback
      (`pane-dispatch-guard.sh:43-50`).
- [ ] 9. Deny-message contract test — assert all four required elements, and that the no-bypass
      clause says *environment variable* rather than overclaiming that no route exists.
- [ ] 10. Register the `PreToolUse` / `Edit|Write|NotebookEdit` block in `settings.json`. It is a
      **fourth** matcher block (existing: `Bash`, `Task|Agent`, `*`), not an edit to one — verified
      2026-07-25.
- [ ] 11. **Amend the existing `Phase gate` stub at `rules/gates.md:5`** — not a new bullet. That
      file is always-on context in every session, and a 26th bullet costs every future session
      tokens to say what the existing stub can say in a clause.
- [ ] 12. ADR `docs/decisions/0011-*.md` — amends ADR 0010: records that its stated objection was
      dismissed by reframing (branch-scoped permission), that its "build only when the gate is
      observed being skipped" deferral was deliberately overridden at the gate decision (Q1), and
      that the Bash-tool write surface is a disclosed non-goal rather than an oversight.
- [ ] 13. Dogfood check: run the full test suite, then confirm the hook denies a real source write
      in this worktree while `phase: planning` still holds — and that it allows one to
      `settings.json` and to this file.

## Verification

<Appended during review.>

## Judge round 1 — 2026-07-25 (spec blob `d972b9b`)

Both judges dispatched in parallel per `running-the-compliance-judge`. Full verdicts persisted:
`coding-memory/compliance-judge/2026-07-25-phase-guard-hook.md` and
`coding-memory/observability-judge/2026-07-25-worktree-phase-guard-hook.md`.

**Compliance: `fail`** (blocking, confidence high). **Observability (advisory, `architecting`):**
no `fail` — 5 concerns, `risk=medium confidence=high`.

Both independently verified the claims most likely to be wrong, and all held: `doc-guard.sh:149`
and `git-guard.sh:22` are exact; `settings.json` really has three `PreToolUse` matchers so this is
a fourth; bash 3.2.57 / python3 3.9.6 / git 2.50.1 match this machine; the Group C
`cat-file --batch` asymmetry is empirically correct; no task pairs tests with implementation.

### Round-2 revision list — blocking (compliance)

- [x] **`writing-specs/coverage-gap`** — the matcher is `Edit|Write|NotebookEdit`, so a source
      write through the **Bash tool** (`sed -i`, `cat >`, `python -c`) is unguarded, and no hook on
      the existing `Bash` matcher inspects file writes. Add it as a fourth Non-goal, and reconcile
      it with the deny message's "no bypass exists" line (L267–268), which currently overclaims.
- [x] **`core-conduct/explicit-error-handling`** — steps 1–7 each name a ⊘ exit; steps 8–9 name
      none, so a failing/empty `for-each-ref`, `cat-file --batch`, or `rev-parse --abbrev-ref`
      falls through to **deny**, inverting Q3's own fail-open-on-infrastructure rule. Specify ⊘ for
      each, plus the matching Group A example.
- [x] **`writing-specs/edge-cases`** — detached HEAD: `rev-parse --abbrev-ref HEAD` returns the
      literal `HEAD` (verified, git 2.50.1), which no feature file can claim, so every source write
      during a rebase or bisect is denied and the message advises recording `branch: HEAD`. This
      file's own Notes record a concurrent mid-rebase session. Add a design-table row and a
      scenario; decide allow-vs-deny explicitly.
- [x] **`writing-specs/ambiguity`** — "fails frontmatter parsing" (step 7, Group A ex. 7) is never
      defined, so Task 1's test cannot be written without inventing the contract, and a typo'd
      `phase: plannning` would silently disable a CRITICAL gate. Specify the frontmatter contract:
      required fence, required keys, the three legal `phase:` values, and what an unrecognized
      value does.
- [x] **`writing-specs/pinned-versions`** — the toolchain table's `frontmatter` row holds tool
      *names* in the version column. Pin `awk` 20200816 and BSD `sed` with an explicit no-GNU-flags
      / no-bare-`sed -i` constraint — the same dialect trap `bash 3.2.57` is pinned against. Also
      Scenario A4's fallback `python` interpreter appears nowhere else, unpinned: pin it per the
      sibling `command -v python3 || command -v python` convention, or delete it.

### Round-2 revision list — advisory (observability), by value

- [x] **Accept `review`, not only `implementation`, in the supersession check.** A *finished*
      feature whose `main` copy still reads `planning` blocks forever. One word; the judge rates it
      best value-per-character on its list. This is a real design bug, not a doc gap.
- [x] **Rollback + lockout.** `settings.json` is on the *guarded* side by this design's own rules,
      so the hook can block edits to the file that disables it. A recovery path exists (the Bash
      tool is outside the matcher — the same hole compliance cites) but nothing says so. Add a
      rollback paragraph and put the escape route in the deny message; consider exempting
      `settings.json` outright.
- [x] **Two of the eight silent exits deserve a line.** A working guard and a dead one are
      byte-identical today. Six ⊘ exits are correctly silent; *python missing* (guard off
      everywhere, permanently) and *all feature files unparseable* (repo opted in, guard can't
      read it) are different in kind. `pane-dispatch-guard.sh` already sets the house precedent —
      silent on boring fail-opens, prints for its two interesting ones, once per session.
- [x] **Group C asserts the wrong thing.** No sibling test counts processes and no mechanism is
      specified, so the test as written will assert *answers* — which the O(branches)
      implementation also produces. Decide: a counting-`git` PATH shim, or a wall-clock/bytes
      budget. Note subprocess count is not the whole cost — one `cat-file --batch` still streams
      every matching file (~26KB/~26ms with a single branch holding one), and it grows precisely
      as the workflow succeeds.
- [x] **Task 8** — amend the existing `Phase gate` stub at `rules/gates.md:5` rather than adding a
      26th bullet; that file is always-on context in every session.

Not cited, considered and dismissed by one or both judges: spec location (the ADR 0010 /
`writing-specs` contradiction is disclosed and resolved), the absent Mermaid diagram, the
templated `## Verification` placeholder, and the copied path classification.

## Notes for the next session

- Created in an isolated worktree (`.claude/worktrees/phase-guard-hook`, branch
  `worktree-phase-guard-hook`) because a **concurrent Claude session** was mid-rebase on
  `feat/pane-split-policy` in the primary checkout. That branch exists for parallel-session
  isolation only — it is **not** this feature's implementation branch, and `branch:` stays `none`
  until the gate opens.
- Unrelated loose end in the primary checkout: four `coding-memory/compliance-judge/*` files
  (other sessions' shared-store writes) were dropped from the working tree by that session's
  branch switch. Backups were kept in the originating session's scratchpad — **that scratchpad is
  now empty and the backups are gone** (verified 2026-07-25). `main` and `origin/main` still carry a
  committed compliance-judge store (6 dated verdicts + `README.md` + `verdicts.jsonl`, last touched
  2026-07-22, commit `7854ae3`); whether the four were among it can no longer be established. Judge
  verdicts are regenerable and this is outside the feature's domain — recorded, not chased.
