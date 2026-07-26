---
phase: implementation
model_tier: high
branch: feature/phase-guard-hook
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
   → **Amended round 2: `settings.json` joins the unguarded list**, because it holds this hook's
   own registration and a guard that can block edits to its own off switch is a footgun (see
   "Rollback"). The full unguarded list is therefore `CODING_MEMORY.md`, `coding-memory/*`,
   `docs/*`, `.claude/*`, `settings.json` — as stated in step 6 and the Gherkin `Background`.
5. **Multi-repo behavior.** These hooks are global (`~/.claude/hooks/`) and fire in every repo.
   Most repos have no `docs/features/` at all. Absence must be unambiguously "not applicable",
   never "blocked". → **Resolved by row 1 of the table**, and it must be the hook's *first* check:
   one `[ -d ]` test on `docs/features/`, exit 0, before any parsing. This path runs on every write.
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
| `hooks/handoff/post-edit-hook.sh` | **Added round 4 — the closest living relative.** Already registered on `PostToolUse` with the **identical `Edit\|Write\|NotebookEdit` matcher** (`settings.json:171-175`) this design adds on the Pre side. Read it for how that matcher behaves in practice before writing the Pre twin; two rounds missed it. |
| `hooks/context-handoff-watch.sh` | **Added round 4.** The session-flag writer this spec's *Flag contract* follows and deliberately diverges from (`:14`, `:42-43`; registered `settings.json:184`). |
| `hooks/checkpoint-before-modify.sh` | **Added round 4.** Executable (755, 6.9K) but **registered nowhere** — verified. Read before naming this hook's registration block, as a live example of a hook that exists without being wired up. |
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

**Supersession is sticky — disclosed round 3.** The check is "does *any* branch record `F` at
`implementation` or `review`?", and branches are never re-examined for regression. So a single
stale branch — an abandoned experiment, a merged branch never deleted — permanently disarms `F`
everywhere, including a later, legitimate re-planning of the same feature. Round 1's `review`
widening made this strictly stickier, since `review` is the terminal state a branch is most likely
to be left sitting in. Accepted, not fixed: the alternative is defining which branch's copy is
authoritative, which is the attribution problem the whole design exists to avoid. The honest
summary is that this hook is **hard to fool and easy to disarm**, and that asymmetry is deliberate
— it is a momentum guardrail whose failure mode must be "stops guarding", never "blocks the user".

## Design detail settled during planning

The Spec formalizes this into Gherkin; it is recorded here so it is not re-derived.

**Registration.** `PreToolUse`, new matcher block `Edit|Write|NotebookEdit` in `settings.json`
(the existing `PreToolUse` blocks are `Bash`, `Task|Agent`, `*` — this is a fourth, not an edit to
an existing one). Exit 0 = allow silently; exit 2 = deny with reason on stderr.

**Order of operations** (fail-open exits are marked ⊘):

1. Read stdin payload; empty → ⊘.
2. `git rev-parse --show-toplevel`; not a repo / fails → ⊘.
3. `[ -d "<root>/docs/features" ]`; absent → ⊘. *(Q5's cheap early exit — the common case in every
   repo that never opted in. Deliberately **after** step 2, not before: a bare `./docs/features`
   test assumes the hook's CWD is the repo root and would silently stop working from a
   subdirectory.)* **A bash builtin, not `stat`** (round 4): this is the hottest path in the design
   — it runs on every write in every repo on the machine — and `[ -d ]` answers the same question
   without a subprocess. Rounds 1–3 wrote `stat` and it was never load-bearing.
4. Resolve the interpreter as the siblings do — `py=$(command -v python3 || command -v python)`
   (`judge-guard.sh:28`, `doc-guard.sh:49`) — and parse the payload → `tool_name`, and the path:
   `tool_input.file_path` (`Edit`/`Write`), falling back to `tool_input.notebook_path`
   (`NotebookEdit`). Neither key → ⊘. **No interpreter → ⊘ *and* print one line, once per session**
   (see "Two exits that must not be silent").
   **Malformed-but-non-empty stdin → ⊘, silently** (enumerated round 4). Step 1 catches only *empty*
   stdin; a truncated or non-JSON payload reaches the parser and raises, and an unhandled traceback
   would exit nonzero — which the Output contract calls a defect and a `PreToolUse` harness may read
   as deny. The parse is wrapped, and any failure to produce a usable path takes the same ⊘ as
   "neither key". It stays **silent**, unlike the two audible exits: a malformed payload is a
   harness-level anomaly, not evidence this repo opted in and the guard went blind.
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
undefined, task 7's test cannot be written without inventing the rule, and a typo like
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

**An empty `docs/features/` is not this case.** Zero files makes "every file was skipped" vacuously
true, which would fire the `noparse` line in any repo that created the directory and nothing else.
The `noparse` exit therefore requires **at least one file present and all present files skipped**;
zero files takes the silent A1 path (step 3's "not applicable" reasoning, one directory later).

Both print one line to stderr and **still exit 0**. Per-write printing is not acceptable on this hot
path, so each fires at most once per session.

**Flag contract** (round 3 — compliance `writing-specs/underspecified-session-flag`). The round-2
text keyed the flag off the payload's `session_id`, which is unreadable in the very no-interpreter
branch it serves — the JSON parse *is* the thing that failed.

**The precedent is `hooks/context-handoff-watch.sh`** — a registered `PreToolUse` hook
(`settings.json:184`) that writes exactly this kind of session flag. Verified directly: `STATE_DIR`
at `:14`, `mkdir -p "$STATE_DIR" 2>/dev/null || exit 0` then `: > "$flag"` at `:42-43`. This
contract **follows** it on three points — the `${VAR:-$HOME/.claude/...}` `$STATE_DIR` shape, the
`session_id`-keyed flag path, and the fallback when no session id is available — and **deliberately
diverges on one**:

> The sibling **bails silently** when the store is unwritable (`|| exit 0`, before its flag is ever
> written). This hook **prints its line and continues.** The sibling's flag gates a *nudge*, so
> losing it costs a repeated reminder. This hook's flag gates the warning that the guard is **dead**
> — and a fix for silent failure that itself fails silently is round 1's problem one level up.

*(Round 3 of this paragraph asserted "no hook in this repo writes session state today, so this is
new ground." That was false, and is withdrawn. The contract's content below needed no change — only
its justification was wrong. Origin: propagated from a judge's round-2 output without checking.
Judge output is data, not fact; this document's own rule, applied to itself one round late.)*

| Aspect | Contract |
|---|---|
| Store | `STATE_DIR="${PHASE_GUARD_STATE_DIR:-$HOME/.claude/hooks/state}"`, mirroring `context-handoff-watch.sh:14`'s `${PANE_STATE_DIR:-...}` shape. The env var **is** the test-time override. |
| Path | `$STATE_DIR/phase-guard-<reason>-<sid>`, `<reason>` ∈ {`nopython`, `noparse`} — two independent flags, so one firing never suppresses the other |
| Key, `noparse` exit | payload `session_id`, falling back to `$CLAUDE_CODE_SESSION_ID` |
| Key, `nopython` exit | `$CLAUDE_CODE_SESSION_ID` **only** — the payload cannot be parsed by construction |
| Both empty | the literal `nosession` — written by `panes/dispatch-pane-agent.sh:70`, read by `pane-dispatch-guard.sh:55`. Degrades to once-per-machine-until-cleaned, not once-per-write |
| Store unwritable | **print the line and continue** — `mkdir -p`/`touch` failures are swallowed, and the exit still returns 0. This is the deliberate divergence from `context-handoff-watch.sh:42` above |
| Cleanup | none. Flags are empty files keyed by session id; they accumulate in the low tens of bytes and are safe to delete at any time. **`/hooks/state/` is `.gitignore`d** (task 13) — this repo *is* `~/.claude`, so the store lands beside the tracked hook scripts |

### Rollback

Added round 2 (observability round 1). Registered globally in `settings.json`, so a misbehaving
build affects every repo on the machine. Three exits, cheapest first:

1. **Edit the offending feature file** — the ordinary fix, and the one the deny message names.
   Feature files live under `docs/**`, which is unguarded.
2. **Delete the `PreToolUse` block from `settings.json`** — the hook exempts `settings.json`
   (step 6) precisely so it can never block edits to its own off switch. Without that exemption a
   misfiring guard would be reachable only through the Bash-tool hole, which the deny message would
   have to advertise — telling every session where the bypass is.
3. **Last resort, `chmod -x hooks/phase-guard.sh`.** Round-2 review flagged the round-1 claim
   ("skipped by the harness") as asserted-but-unverified: hooks register as direct paths, so a
   non-executable file more likely yields exit 126 — which this spec's own Output contract calls a
   defect, and which a `PreToolUse` harness may treat as *deny*. **Treat path 3 as unverified until
   Task 17 tests it**, and prefer paths 1–2. If it does yield 126, that finding is **recorded under
   `## Verification`** and this path is revised in the review phase — not deleted mid-implementation,
   which the phase gate forbids.

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
| `settings.json` | one added `PreToolUse` block, matcher `Edit|Write|NotebookEdit`. Tracked — see *Registration and its revert* |
| `.gitignore` | one added line, `/hooks/state/`, mirroring `:13`'s `/panes/state/` |
| `rules/gates.md` | **amendment to the existing `Phase gate` stub at `:5`** — not a new bullet |
| `docs/decisions/0011-*.md` | ADR — this **amends** ADR 0010, which deferred the hook |
| `$HOME/.claude/hooks/state/phase-guard-<reason>-<sid>` | runtime, untracked — empty once-per-session flag files (see *Flag contract*); overridable via `$PHASE_GUARD_STATE_DIR` |

**The `.gitignore` line is not housekeeping** (added round 4). This repo *is* `~/.claude`, so
`$HOME/.claude/hooks/state/` resolves to `<repo>/hooks/state/` — beside the tracked hook scripts.
Verified: `git check-ignore -v panes/state/foo` matches `.gitignore:13`; `hooks/state/phase-guard-x`
matches nothing. Combined with the deliberate `Cleanup: none`, the flags would accumulate forever
inside a directory people `git add` wholesale. The Artifacts table called them "untracked" while
nothing made them so.

### Registration and its revert

Answers the round-3 gap: task 14 edits a file outside this branch, and nothing said how that unwinds.

`settings.json` is **tracked in this repo** (verified: `git ls-files --error-unmatch settings.json`,
last touched `e47f38f`). That makes the story simpler than round 3 assumed, but it has two halves
that must not be confused:

| | What it is | How it reverts |
|---|---|---|
| **Committed** | the `PreToolUse` block, committed on this feature branch like any other artifact | `git revert` on this PR — it reaches the change, because the file is tracked here |
| **Live** | the primary checkout's *working copy* of `settings.json`, which is what the harness actually loads | not reached by reverting this PR. Delete the block by hand — rollback path 2 |

The gap between them is real and worth stating plainly: **committing here does not make the hook
live**, and making it live does not put the change under this PR's revert. The primary checkout sits
on another branch, so it picks the block up when it lands on `main` and that checkout pulls. Until
then, a session that wants the hook live edits the primary checkout's copy directly and accepts that
this is a manual, manually-reverted change. That is a genuine cost of a repo whose own configuration
is its product; it is not fixable inside this feature, so it is disclosed rather than papered over.

### Pinned toolchain

Verified on this machine 2026-07-25; the hook must run under exactly these.

| Tool | Version | Constraint it imposes |
|---|---|---|
| `bash` | 3.2.57 (system, `arm64-apple-darwin25`) | **No bash-4 features** — no associative arrays, no `mapfile`/`readarray`, no `${var,,}`. `#!/usr/bin/env bash` resolves here. |
| `python3` | 3.9.6 | JSON payload parse **only**. No third-party imports, no PyYAML. |
| `python` (fallback) | whatever `command -v python` resolves to, **or absent** | Resolved as `command -v python3 \|\| command -v python`, the sibling convention (`judge-guard.sh:28`, `doc-guard.sh:49`). The hook must therefore use only syntax valid in **both** py2 and py3 — `json.load(sys.stdin)`, `print(...)` as a single-arg call, no f-strings. Absent on this machine; the fallback exists for parity with the siblings, not because it is exercised here. |
| `git` | 2.50.1 (Apple Git-155) | `rev-parse`, `for-each-ref`, `cat-file --batch`. Invoked by **bare name**, so `PATH` order decides which binary runs — that is what makes the Group C shim possible, and it is a supply-chain surface worth naming. *(Row restored round 3: dropped by the round-2 edit that added the awk/sed rows, leaving the tool the design structurally depends on pinned only in prose.)* |
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
  And a guarded write is one whose path is NOT CODING_MEMORY.md, coding-memory/*, docs/*,
      .claude/*, or settings.json
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
  | 4  | stdin is non-empty but is not valid JSON                               | 4  |
  | 5  | tool_input carries neither file_path nor notebook_path                 | 4  |
  | 6  | the resolved path lies outside the repository root                     | 5  |
  | 7  | no docs/features/*.md has phase: planning                              | 7  |
  | 8  | git for-each-ref exits nonzero                                         | 8  |
  | 9  | git cat-file --batch exits nonzero                                     | 8  |
  | 10 | git rev-parse --abbrev-ref HEAD exits nonzero or prints nothing        | 9  |
  | 11 | git rev-parse --abbrev-ref HEAD prints the literal HEAD (detached)     | 9  |
```

Example 4 was added round 4: step 1 catches only *empty* stdin, so a truncated payload reaches the
parser, and an unhandled traceback exits nonzero — a code the Output contract calls a defect and a
`PreToolUse` harness may read as **deny**.

Examples 8–10 are the round-2 fix for `core-conduct/explicit-error-handling`: without them the only
path onward from steps 8–9 is *deny*, so a transient `git` failure blocks every write. Example 11 is
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
undefined until round 2 and task 7 could not otherwise be written.

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
  And docs/features/b.md has phase: planning, superseded by no branch
  And the current branch is feat/a
  When a guarded write is attempted
  Then the hook exits 2
  And stderr names docs/features/b.md

Scenario: unknown frontmatter keys are forward-compatible
  Given docs/features/a.md has phase: planning, model_tier: high, and a future key
  And the current branch is claimed by no feature file
  When a guarded write is attempted
  Then the hook exits 2
  And stderr names docs/features/a.md
```

Example 3 is the one that matters most: before the contract existed, a one-character typo silently
switched a CRITICAL gate off with no complaint.

**The `b.md` in the missing-`branch:` scenario is load-bearing, not scenery** (fixed round 4). Until
this pass it read `a.md` at `implementation` as the *only* file and asserted exit 2 — which step 7
cannot produce: `planning_files` would be empty and the hook allows. It asserted the exact opposite
of the algorithm, survived three judge rounds and both judges, and sat in a task list that freezes at
the gate, where the cheap "fix" is to loosen the test rather than notice the `Given` is incomplete.
A deny needs *some* planning file; `b.md` supplies it, so the assertion isolates the one thing the
scenario is actually about — that `a.md`'s absent `branch:` reads as **unclaimed** rather than as
malformed, leaving `feat/a` unclaimed and `b.md` free to deny.

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

**`.claude/*` does not swallow this repo's worktrees** (narrowed round 4). Round 2 warned that the
unguarded `.claude/*` entry exempts everything under `.claude/worktrees/`, which is where this very
feature is being planned. It largely does not: step 2 resolves the root with `git rev-parse
--show-toplevel`, which returns the **worktree's** root from inside a worktree — confirmed from this
checkout — so a session working there relativizes its files to `hooks/x.sh` and is **guarded**
normally. The hole opens only for a path reaching *into* a worktree from the primary checkout, which
is not the normal working pattern. Worth one line, not the redesign round 2 implied.

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
> own argv to a counter file. **When argv contains `cat-file`, it also tees stdin** — `tee -a
> "$STDIN_LOG" | "$REAL_GIT" "$@"` — otherwise it `exec`s the real `git` directly. `$REAL_GIT` is an
> absolute path captured before the shim is installed, so it cannot recurse. The assertions read
> the two log files.

The tee is not optional (round 3 — compliance `writing-specs/unverifiable-group-c-assertion`): an
argv-only shim cannot observe stdin, so the "fed N*M lines" assertion would have been unverifiable
against the very mechanism pinned to make it verifiable. Note the tee'd form cannot `exec` — it
needs a pipeline — so only the `cat-file` branch pays the extra process, and that process is the
shim's, not the hook's, so it does not perturb the count being asserted.

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

### Cost — a recorded observation, deliberately not a budget

**Revised round 4. The previous `≤60ms guarded / ≤15ms non-opted-in` budget is withdrawn**, for two
reasons that compound.

**It was below its own floor.** The non-opted-in figure has no headroom by construction: two
operations are mandatory *before* step 3's early exit can fire. Measured twice, independently:

| Measurement | bash spawn | `+ git rev-parse --show-toplevel` | `python3` startup + `json` import |
|---|---|---|---|
| Round-3 judge, machine under concurrent-session load | 5.2ms | **15.2ms** | 22.7ms |
| This pass, quiet machine (40 iterations each) | 2.3ms | **10.0ms** | 22.4ms |

The judge also measured 18.1ms end-to-end non-opted-in, against a 15ms budget set without
re-measuring. **The floor alone was over budget on a loaded machine and comfortably under it on a
quiet one** — and that ~80% spread between two honest measurements of the same two commands is the
second reason.

**A wall-clock threshold cannot be an acceptance criterion in this document.** Group C rejects
exactly that, in as many words: *"a timing threshold is flaky on a loaded machine and would be the
kind of test that gets deleted the first time CI goes red for an unrelated reason."* Making one a
gate on the whole feature argued both sides of one question a page apart. The measurements above are
that prediction coming true.

So: **no threshold, no pass/fail.** The dogfood task records the numbers; a regression is a judgment
call made against these baselines, not a red test.

**The lever, named correctly.** The prescribed fix — `cat-file --batch-check`, reading only blobs
whose size warrants it — **recovers almost nothing.** Scaling the request set against the real 55KB
feature file:

| Feature files per branch | Request lines | `cat-file` stage |
|---|---|---|
| 1 | 7 | 23.4ms |
| 10 | 70 | 23.5ms |
| 20 | 140 | **27.0ms** |

Twenty times the streaming volume — 7.7MB — costs **3.6ms**. The cost is process startup, not bytes.
That also retires a worry rounds 1–3 carried prominently — that the `cat-file` stage "grows linearly
as this workflow succeeds and feature files accumulate." It is **empirically false at any realistic
scale**, and it was the stated justification for the `--batch-check` fix, which is why both go
together. The real lever is the **~22ms `python3` startup**, the
single largest cost on the guarded path and larger than the entire non-opted-in path. It buys one
thing: parsing two keys out of the JSON payload. If the guarded path ever needs to get faster, that
is what to attack — not `--batch-check`.

It does **not** burden the common case: step 4 runs after step 3's early exit, so a repo that never
opted in never starts python. That is the early-exit design working as intended, and it is the one
performance claim here that rests on structure rather than on a stopwatch.

Parser contract, verified against git 2.50.1 — the two output forms are **not** symmetric:

| Input line resolves to | `cat-file --batch` emits |
|---|---|
| a blob | `<sha> blob <size>` then `<size>` bytes of content, **then a trailing `LF`** — the request is not echoed |
| nothing (path or branch absent) | the request line verbatim, then ` missing` |

**The trailing `LF` is part of the framing, not part of the blob.** A parser that reads exactly
`<size>` bytes and then expects the next record desynchronises on record two and mis-attributes
every result after the first — the same class of failure as keying off the echoed line. Read
`<size>` bytes, then consume one byte.

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
the hook was never meant to prevent.

**Correction (round 3).** Round 2 of this paragraph claimed `git-guard.sh` and `doc-guard.sh`
"still stand between that write and a commit." Review showed that is **false on precisely the case
this feature is being built under**: `git-guard.sh` guards `main`/`master` only, so on a
worktree-isolation branch — like this one — nothing stands behind the Bash hole at all. The
non-goal survives on the momentum-guardrail argument alone; the layering claim is withdrawn rather
than repaired, because a design document's credibility is its main asset before any code exists.

## Tasks

Frozen at the gate; adding tasks after the gate opens is forbidden by the phase rules. Tests precede
implementation in every pair — the test is the unbiased baseline.

**Re-sequenced round 3, corrected round 4.** Round 3 fixed three unbuildable points but introduced
another of the same kind: task 3 asserted the **full four-element deny message**, while task 4 was
scoped to produce a *bare* exit 2 and claimed "green for task 3". A minimal deny cannot satisfy four
message elements, so the implementer's only outs were to build the whole message at task 4 — making
task 12 a no-op and putting task 11's test *after* its implementation, inverting the test-first rule
this preamble insists on — or to quietly loosen task 3. Tasks 5/6 had the same defect via A3's
`stderr names good.md` assertions.

**The fix is ordering, not loosening: the deny message moves up to tasks 5–6**, immediately after the
bare deny exists and before any test that reads stderr. Every test task below is now green-able by
the implementation task directly after it, no task writes tests and implementation together, and no
assertion depends on behaviour a later task introduces.

- [x] 1. `hooks/phase-guard.test.sh` — Group A1 examples 1–6 (steps 1–5 ⊘, incl. malformed JSON) and
      the unguarded-path scenario incl. `settings.json`. All assert exit 0 + empty stderr. Red
      against a nonexistent hook.
      - Done: 12 cases, red at exit 127. The A1 cases other than 2 and 3 run inside a repo that
        *is* opted in (planning file present, branch unclaimed), so each isolates the step it
        names rather than passing because some later step would have allowed anyway.
      - `PHASE_GUARD_STATE_DIR` is exported to the temp dir from the start, so no run of this
        suite can ever touch the real `$HOME/.claude/hooks/state`.
      - Fixture gotcha, found at task 2 and fixed test-only first: `mktemp -d` returns the macOS
        `/var` symlink form while `git rev-parse --show-toplevel` resolves to `/private/var`, so
        payload paths built from it never relativize against the root — every guarded case would
        have fail-opened at step 5 and passed for the wrong reason. `TMP` is now `pwd -P`.
- [x] 2. `hooks/phase-guard.sh` — steps 1–6 (payload, git root, `docs/features` stat, interpreter
      via `command -v python3 || command -v python`, parse incl. `notebook_path`, relativize, path
      classification reusing `doc-guard.sh:149` plus `.claude/*` and `settings.json`). A stub step 7
      that always ⊘s keeps the hook allow-only. **Green for task 1.**
      - Done: 12/12 green. Because the stub makes the hook allow-only, green alone cannot show the
        steps run, so classification was verified separately against a *copy* whose stub denies:
        source/nested-source/`notebook_path` reach step 7; all six exempt paths stop at step 6;
        an outside path stops at step 5. The committed hook was never modified for that probe.
      - `tool_name` is not extracted. Step 4 lists it, but nothing downstream consumes it and the
        matcher already restricts the tool set, so binding it would be an unused variable under
        `set -u`. No scenario observes it — this changes no behaviour.
      - The no-interpreter exit is silent here. It is one of the two exits that must not stay
        silent, and its once-per-session line is inseparable from the flag contract, so both land
        together at task 12 rather than shipping a print-on-every-write half of it now.
      - The py2 fallback is unexercised: `python` is absent on this machine, so the parser's
        py2/py3-compatible syntax is reviewed, not tested.
- [x] 3. Test: the core deny (Group B row 1) asserting **exit 2 only**, Group A1 example 7 (no
      `planning` file), and the empty-`docs/features/` silent case. Red — nothing denies yet.
      *No stderr assertions here: the message is tasks 5–6.*
      - Done: 14 pass, 1 fails — the core deny, the only case the stub cannot satisfy.
      - The `deny` runner asserts exit 2 **and empty stdout** (the Output contract holds on every
        path) but says nothing about stderr, so task 4's bare deny can make it green.
      - The two new allow cases pass trivially against the allow-only stub; they only start
        carrying weight at task 4, when a deny exists for them to be distinguished from.
- [x] 4. Implement minimal steps 7/9/10: find `phase: planning`, read the branch, deny with a bare
      exit 2. **Green for task 3.** First task that can produce exit 2, which is why every
      deny-asserting test lands at or after task 3.
      - Done: 15/15 green. The unguarded-path cases only became meaningful here — a deny now
        exists for them to be distinguished from.
      - Step 9 compares the `branch:` value to the current branch **as a string**, via `sed -n -E`
        extraction, rather than interpolating the branch name into a regex. A branch name is user
        input; interpolated, one carrying a metacharacter matches wrongly. Probed both ways:
        `feat/a.b` claimed allows, and `feat/axb` is correctly not matched by it.
      - Step 9's own fail-opens (nonzero/empty `rev-parse`, detached `HEAD`) are **not** here —
        task 10 owns them. Until it lands, a failing `rev-parse` yields an empty branch, no claim
        matches, and the hook denies. That inverts the fail-open principle for two tasks; it is
        the checklist's chosen ordering, and task 9's tests are the red that closes it.
- [x] 5. Test: the deny-message contract — all four required elements (offending path(s) + their
      `phase:`, current branch, both fixes, the no-bypass clause), and that the clause says
      *environment variable* rather than overclaiming that no route exists. Red — task 4's deny is
      bare.
      - Done: 17 pass, 8 fail — the deny itself is green (exit 2, empty stdout, unchanged from
        task 4) and every element assertion is red, which is the split this task wanted.
      - Each of the four elements is asserted separately rather than as one match, so a message
        that ships three of four fails on the one it dropped and names it.
      - The fixture carries **two** planning files, because the contract says *every* offending
        path — a single-file fixture is green against a message that names only the first. Its
        branch is `wip/unclaimed-xyz`, not the scenario's `main`: "stderr names the current
        branch" is not falsifiable against a string the message could contain for other reasons.
      - `err_has`/`err_lacks` read the `$err` file that `deny` already captured, so all eight
        elements are checked against one and the same deny rather than eight separate runs.
      - Honest limit: the overclaim check (`err_lacks`) passes **vacuously** against today's
        empty stderr. It only starts carrying weight at task 6, when there is prose to overclaim
        in — it is the one assertion here whose red/green today means nothing.
- [ ] 6. Implement the deny message to contract. **Green for task 5.** Every later test may now
      assert on stderr.
- [ ] 7. Test: Group A3 — the eight frontmatter-contract scenarios (six malformed shapes, optional
      `branch:` **with its second `planning` file**, forward-compatible unknown keys), including the
      `names good.md` / `does not name bad.md` assertions. Red where the minimal parser is too
      permissive.
- [ ] 8. Implement step 7 to the full **Frontmatter contract**. **Green for task 7.**
- [ ] 9. Test: Group B's remaining four rows (claimed branch; one feature planning must not revoke
      another; `implementation`-supersession; `review`-supersession), the NotebookEdit regression,
      Group A1 examples 8–11 (both git failures, empty/failed `rev-parse`, detached `HEAD`), the
      no-local-branches scenario, and **Group C** — the counting-`git` shim with its stdin tee,
      asserting one `cat-file --batch` / one `for-each-ref` / zero `git show`, plus the input-order
      parser against `blob`, `missing`, **and the trailing `LF`**.
- [ ] 10. Implement step 8: un-superseded filter accepting **`implementation` or `review`**, the
      single-subprocess `for-each-ref | cat-file --batch` pipeline, ⊘ on either git call failing,
      detached-HEAD ⊘. **Green for task 9.**
- [ ] 11. Test: Group A2 — the two audible fail-opens, asserting exactly one stderr line, that a
      second invocation in the same session adds none, that the two reasons flag independently, and
      that an unwritable `$PHASE_GUARD_STATE_DIR` still prints and still exits 0.
- [ ] 12. Implement the once-per-session flag to the **Flag contract**. **Green for task 11.**
- [ ] 13. Add `/hooks/state/` to `.gitignore`, mirroring `:13`'s `/panes/state/` entry and its
      "machine-local, never committed" comment. One line; without it the flag store accumulates
      untracked inside this repo (see *Artifacts*).
- [ ] 14. Register the `PreToolUse` / `Edit|Write|NotebookEdit` block in `settings.json`. It is a
      **fourth** matcher block (existing: `Bash`, `Task|Agent`, `*`), not an edit to one — verified
      2026-07-25. Commit it on this branch; making it *live* in the primary checkout is the separate,
      manual half described in **Registration and its revert**. A concurrent session may hold that
      file on another branch — check before writing.
- [ ] 15. **Amend the existing `Phase gate` stub at `rules/gates.md:5`** — not a new bullet. That
      file is always-on context in every session, and a **19th** bullet costs every future session
      tokens to say what the existing stub can say in a clause. *(Count verified 2026-07-26: 18
      bullets today. Round 2 and 3 both said "26th"; it was decorative and wrong twice.)*
- [ ] 16. ADR `docs/decisions/0011-*.md` — amends ADR 0010: records that its stated objection was
      dismissed by reframing (branch-scoped permission), that its "build only when the gate is
      observed being skipped" deferral was deliberately overridden at the gate decision (Q1), and
      that the Bash-tool write surface and sticky supersession are disclosed non-goals rather than
      oversights.
- [ ] 17. Dogfood, in a **throwaway repo**, not this one. By task 17 this feature's own gate has
      opened, so this branch is claimed and the guard correctly allows everything — "confirm it
      denies here" was unsatisfiable as round 2 wrote it. Instead: `git init` a temp repo, add one
      `docs/features/x.md` at `phase: planning`, and assert (a) a source write denies with all four
      message elements, (b) a write to `docs/`, `.claude/`, and `settings.json` allows, (c) advancing
      `phase:` unblocks it. Then **record** — not gate on — the two timings against the baselines in
      *Cost*, and **resolve Rollback path 3** by testing what a non-executable hook actually does
      (allow, or exit 126 → deny).

**Findings from task 17 are recorded, not acted on.** If path 3 blocks, or a timing has moved, the
task's output is a note appended to `## Verification` — a section that exists for exactly this. It
does **not** edit the Design or Spec sections, and it does not add a task.

Round 3 wrote this task the other way, twice: *"delete the path if it blocks"* and *"switch step 8 to
`cat-file --batch-check`."* Both are spec edits, and by task 17 the phase is `implementation`, which
`rules/gates.md:5` states **forbids spec and checklist edits**. The first feature to run under this
workflow prescribed breaking it — the precise dogfooding friction this file was opened to catch,
caught one round late. Acting on a finding is a **review-phase** decision, made after the phase
advances and the gate permits it.

## Verification

<Appended during review.>

## Judge history

Four rounds, all `fail` on compliance, all resolved. **No violation id ever recurred** — each round
resolved everything cited and surfaced new items introduced by those fixes. Full verdicts, with the
per-rule citations and the round-by-round revision lists, are persisted and are the record:

| Round | Date | Compliance | Observability (advisory) | Verdict files |
|---|---|---|---|---|
| 1 | 2026-07-25 | `fail`, confidence high | no `fail`, 5 concerns, risk=medium | `coding-memory/{compliance,observability}-judge/2026-07-25-*phase-guard-hook.md` |
| 2 | 2026-07-25 | `fail` | concerns only | `…-round2.md` |
| 3 | 2026-07-25 | `fail`, 1 blocking | concerns only | `…-round3.md` |
| 4 | 2026-07-26 | surgical pass — **no round run** (user decision) | — | see below |

**Round 4 was a directed pass, not a judge round.** After round 3 hit the escalation cap with one
blocking violation, the user decided (2026-07-25) to fix the named items in a fresh session and go
to review directly. Both judges had agreed the design's reasoning was sound and every residual risk
disclosed; the observability judge's readiness verdict was that it needed *"one surgical pass over
the task list and the budget, not another full round."*

What round 4 changed, all of it recorded inline above at the point of change: the false prior-art
claim in the *Flag contract*; the unbuildable task 3/4 and 5/6 pairings (deny message moved to tasks
5–6); the A3 scenario that asserted the opposite of step 7; the performance budget (withdrawn,
replaced by *Cost*); the missing `.gitignore` task; the registration revert story; task 17's
instruction to edit the spec mid-`implementation`; plus the `[ -d ]` hot path, malformed-JSON
enumeration, three prior-art omissions, the `.claude/*` worktree narrowing, and the "26th bullet"
count (18).

**Claims both judges independently verified and found to hold:** `doc-guard.sh:149` and
`git-guard.sh:22` are exact; `settings.json` really has three `PreToolUse` matchers, so this is a
fourth; bash 3.2.57 / python3 3.9.6 / git 2.50.1 match this machine; the Group C `cat-file --batch`
output asymmetry is empirically correct; no task pairs tests with implementation.

**Raised and dismissed** by one or both judges: spec location (the ADR 0010 / `writing-specs`
contradiction is disclosed and resolved above), the absent Mermaid diagram, the templated
`## Verification` placeholder, and the copied path classification.

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
