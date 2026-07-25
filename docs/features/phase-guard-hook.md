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
| File reads `planning` here, but some branch has it at `implementation` | any | **allow** — superseded; its gate already opened (the narrowing) |

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
4. `python3` parse payload → `tool_name`, and the path: `tool_input.file_path` (`Edit`/`Write`),
   falling back to `tool_input.notebook_path` (`NotebookEdit`). No python / neither key → ⊘.
   *(Corrected 2026-07-25 against the live tool schema: `NotebookEdit` has **no** `file_path` — its
   only path key is `notebook_path`. Reading `file_path` alone, as this step originally said, would
   have failed open on every notebook write.)*
5. Relativize `file_path` against the root (payload paths are absolute); outside the root → ⊘.
6. Classify the path — **reuse `doc-guard.sh:149` verbatim**, plus `.claude/*`:
   `CODING_MEMORY.md`, `coding-memory/*`, `docs/*`, `.claude/*` → unguarded → ⊘. Else guarded.
7. Parse `phase:`/`branch:` frontmatter of `docs/features/*.md` in the working tree; a file that
   fails to parse is skipped (⊘ for that file only). Collect `planning_files`; empty → ⊘.
8. **Un-superseded filter.** Drop any `F` that reads `implementation` on some branch. Read every
   branch's copy in **one** subprocess — `git for-each-ref --format='%(refname:short)' refs/heads/`
   piped into `git cat-file --batch` as `<branch>:<path>` lines — never one `git show` per branch,
   which is O(branches) processes on a hook that fires on every write. Empty after filtering → ⊘.
9. `claimed` = any working-tree feature file with `phase: implementation` **and** `branch:` equal to
   `git rev-parse --abbrev-ref HEAD`. Claimed → ⊘.
10. Otherwise **deny (exit 2)**.

**Fail-closed only at step 10** — after a `planning` file is positively identified, confirmed
un-superseded, and the branch confirmed unclaimed. Everything upstream fails open (Q3): this hook
fires on every write in every repo, so a false block costs the whole session, in repos that never
opted in. That is the deliberate divergence from `judge-guard.sh`, which fails closed because it
guards one rare command where a false block costs a single retry.

**Deny message must contain** — the offending file path(s), the current branch, both legitimate
fixes (open the gate: `gate confirmed` → advance `phase:` and record `branch:`; or, if the file is
stale, advance or delete it), and an explicit statement that **no bypass env var exists**, so a
session does not go hunting for one.

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
| `rules/gates.md` | one gate stub, alongside the other Tier-1 hook stubs |
| `docs/decisions/0011-*.md` | ADR — this **amends** ADR 0010, which deferred the hook |

### Pinned toolchain

Verified on this machine 2026-07-25; the hook must run under exactly these.

| Tool | Version | Constraint it imposes |
|---|---|---|
| `bash` | 3.2.57 (system, `arm64-apple-darwin25`) | **No bash-4 features** — no associative arrays, no `mapfile`/`readarray`, no `${var,,}`. `#!/usr/bin/env bash` resolves here. |
| `python3` | 3.9.6 | JSON payload parse **only**. No third-party imports, no PyYAML. |
| `git` | 2.50.1 (Apple Git-155) | `rev-parse`, `for-each-ref`, `cat-file --batch`. |
| frontmatter | `awk`/`sed` | Deliberately not a second parser — see "Toolchain" under *Design detail settled during planning*. |

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

**Output** — exit `0` = allow, emitting nothing on stdout or stderr. Exit `2` = deny, reason on
stderr. No other exit code is legitimate: under `set -u` an unbound variable exits 1, and a fail-open
path that leaks a nonzero code is a defect regardless of how the harness classifies it. Every ⊘ path
therefore exits 0 **explicitly**.

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

**Group A — out of scope: allow silently (exit 0, no output).** Each is a ⊘ exit from the
order-of-operations, in order. The shared assertion is `exit 0 AND stderr is empty`.

```gherkin
Scenario Outline: fail open rather than block a session that never opted in
  Given <precondition>
  When any Edit/Write/NotebookEdit is attempted
  Then the hook exits 0 and writes nothing

Examples:
  | # | precondition                                                          |
  | 1 | stdin is empty                                                        |
  | 2 | the working directory is not inside a git repository                  |
  | 3 | <root>/docs/features/ does not exist                                  |
  | 4 | python3 and python are both absent from PATH                          |
  | 5 | tool_input carries neither file_path nor notebook_path                |
  | 6 | the resolved path lies outside the repository root                    |
  | 7 | every docs/features/*.md fails frontmatter parsing                    |
  | 8 | no docs/features/*.md has phase: planning                             |
```

Scenario 3 must be reached **only after** the repo root is resolved (step 2). A bare
`stat ./docs/features` assumes the hook's CWD is the repo root and silently stops guarding from any
subdirectory — the failure mode is invisible, which is what makes it worth pinning here.

```gherkin
Scenario: an unguarded path is never blocked, even mid-planning
  Given docs/features/a.md has phase: planning
  And the current branch is claimed by no feature file
  When a write targets docs/features/a.md, docs/decisions/0011.md, CODING_MEMORY.md,
       coding-memory/x.md, or .claude/session-state.md
  Then the hook exits 0 and writes nothing
```

This scenario *is* the escape hatch (Q6). A repo locked by a stale `planning` file is always
unlocked by editing that file's frontmatter, because feature files live under `docs/**`.

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

Scenario: a NotebookEdit is guarded like any other write
  Given docs/features/a.md has phase: planning and the branch is unclaimed
  When NotebookEdit is attempted with tool_input.notebook_path = <root>/analysis.ipynb
  Then the hook exits 2
```

The last scenario is the regression test for the `file_path`-only bug corrected above; without it,
the guard silently exempts an entire tool.

**Group C — the un-superseded lookup.** Behavioral contract, because a naive implementation is
O(branches) subprocesses on a hook that fires on every write.

```gherkin
Scenario: every branch's copy is read in exactly one subprocess
  Given N local branches and M candidate planning files
  When the un-superseded filter runs
  Then exactly one `git cat-file --batch` process is spawned
  And it is fed N*M lines of the form <branch>:<path>
```

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

## Tasks

Frozen at the gate; adding tasks after the gate opens is forbidden by the phase rules. Tests precede
implementation in every pair — the test is the unbiased baseline.

- [ ] 1. `hooks/phase-guard.test.sh` — Group A scenarios (all 8 ⊘ exits + the unguarded-path
      scenario), asserting exit 0 **and empty stderr**. Red against a nonexistent hook.
- [ ] 2. `hooks/phase-guard.sh` — steps 1–6 of the order of operations (payload, git root,
      `docs/features` stat, python parse incl. `notebook_path`, relativize, path classification
      reusing `doc-guard.sh:149`). Green for Group A.
- [ ] 3. Extend the test with Group B: the four permission rows + the NotebookEdit regression.
- [ ] 4. Implement steps 7–10: frontmatter scan, un-superseded filter, claimed-branch check, deny.
- [ ] 5. Extend the test with Group C: assert the single-subprocess contract and the
      input-order parser against both `blob` and `missing` output forms.
- [ ] 6. Deny-message contract test — assert all four required elements are present in stderr.
- [ ] 7. Register the `PreToolUse` / `Edit|Write|NotebookEdit` block in `settings.json`. It is a
      **fourth** matcher block (existing: `Bash`, `Task|Agent`, `*`), not an edit to one — verified
      2026-07-25.
- [ ] 8. Add the gate stub to `rules/gates.md`.
- [ ] 9. ADR `docs/decisions/0011-*.md` — amends ADR 0010: records that its stated objection was
      dismissed by reframing (branch-scoped permission), and that its "build only when the gate is
      observed being skipped" deferral was deliberately overridden at the gate decision (Q1).
- [ ] 10. Dogfood check: run the full test suite, then confirm the hook denies a real source write
      in this worktree while `phase: planning` still holds.

## Verification

<Appended during review.>

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
