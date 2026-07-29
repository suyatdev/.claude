---
phase: review
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

**Order of operations** (fail-open exits are marked ⊘).

> **Step numbers mean the `# --- Step N: … ---` section headers in `hooks/phase-guard.sh`, and
> nothing else.** The code is the single source of truth; this list, the audit table's Step column,
> and the suite's step labels all resolve against it. Written down because they once did not: the
> pre-`508c55b` order ran `git rev-parse` second, the `docs/features` early exit third and the
> interpreter fourth, and the fix that reordered them left the doc describing the old sequence while
> the code described the new one. **Rounds 1–6 of the observability verdicts predate the reorder and
> use the old numbering; rounds 7 onward use this one.** When the two disagree, the code wins — do
> not renumber the code to match prose.

1. Read stdin payload; empty → ⊘.
2. **The tools this hook cannot run without.** `command -v git` → **⊘ *and* print one line, once
   per session** (`NOGITBIN_MSG`); then the interpreter, resolved as the siblings do —
   `py=$(command -v python3 || command -v python)` (`judge-guard.sh:28`, `doc-guard.sh:49`) — →
   **⊘ *and* print one line, once per session** (`NOPYTHON_MSG`). Both messages are machine-wide
   and unconditional: neither is a statement about *this* repo, so neither needs to know whether it
   opted in. *This step is what makes `python3` a cost of the common case rather than of the guarded
   one — see the correction in* Cost.
3. **The path out of the payload.** Parse → `tool_name`, and the path: `tool_input.file_path`
   (`Edit`/`Write`), falling back to `tool_input.notebook_path` (`NotebookEdit`). Neither key → ⊘.
   **Malformed-but-non-empty stdin → ⊘, silently** (enumerated round 4). Step 1 catches only *empty*
   stdin; a truncated or non-JSON payload reaches the parser and raises, and an unhandled traceback
   would exit nonzero — which the Output contract calls a defect and a `PreToolUse` harness may read
   as deny. The parse is wrapped, and any failure to produce a usable path takes the same ⊘ as
   "neither key". It stays **silent**, unlike step 2's exits: a malformed payload is a harness-level
   anomaly, not evidence this repo opted in and the guard went blind.
   *(Corrected 2026-07-25 against the live tool schema: `NotebookEdit` has **no** `file_path` — its
   only path key is `notebook_path`. Reading `file_path` alone, as this step originally said, would
   have failed open on every notebook write.)*
4. **The repository that owns that path, and whether it opted in.** Walk up from the write target to
   its deepest existing ancestor and take its physical form (`cd … && pwd -P`); unsearchable → ⊘
   **and speak** (`NORESOLVE_MSG`). Then `git -C "<target's dir>" rev-parse --show-toplevel` —
   **the target's repo, never the session's.** Non-zero splits two ways: no `.git` found walking up
   → ⊘ silently, genuinely out of scope; a `.git` that exists but cannot be read → ⊘ **and speak**
   (`NOREPOREAD_MSG`, Group A7). Then `[ -d "<root>/docs/features" ]`; absent → ⊘, the opt-in test
   and the common-case exit. **A bash builtin, not `stat`** (round 4): `[ -d ]` answers the same
   question without a subprocess. Rounds 1–3 wrote `stat` and it was never load-bearing. It can no
   longer be the *first* test — there is no repo to ask about until the payload has been parsed —
   and that reordering is what the cwd fix cost.
5. Relativize `file_path` against the root (payload paths are absolute); outside the root → ⊘.
6. Classify the path — **reuse `doc-guard.sh:149` verbatim**, plus `.claude/*` and `settings.json`:
   `CODING_MEMORY.md`, `coding-memory/*`, `docs/*`, `.claude/*`, `settings.json` → unguarded → ⊘.
   Else guarded. *(`settings.json` is exempt because it is this hook's own off switch — see
   "Rollback".)*
7. Parse frontmatter of `docs/features/*.md` in the working tree per the **Frontmatter contract**
   below. Every glob entry that **exists in any form** is counted, including a dangling symlink or
   a directory — only a glob that matched nothing is passed over. An entry the parser cannot read,
   or whose content violates the contract, is skipped (⊘ for that file only). **If ANY entry was
   skipped, print one line, once per session** — checked immediately here, before any exit below,
   because a skipped card is unreadable whichever path the hook then takes. Collect
   `planning_files`; empty → ⊘.
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
opted in is the "cannot evaluate" case, so it is one of the exits that must speak — the `noparse`
row of the fail-open audit below.

### The exits that must not be silent — the fail-open audit

Added round 2 (observability round 1) as "two exits"; **replaced in review by an audit of every
exit**, after four judge rounds each found one more exit that went silent, every one a step earlier
than the last: the tally, then the supersession exit, then the entry counting, then the directory
listing. Each fix was locally correct and each was followed by a new instance, because the surface
was being explored reactively, one judge finding at a time. Enumerating it is what stopped that.

**THE RULE.** Once the hook knows **this repo opted in**, any inability to complete the evaluation
is the guard being switched off while it was on its way to do its job — and a working guard and a
dead one are byte-identical, since every ⊘ emits nothing. Those exits **speak**. Everything upstream
of that knowledge stays **silent**, because there the hook genuinely has nothing to say. Two
exceptions sit outside the rule in each direction: a missing `git` or `python` speaks even though it
is upstream of the opt-in test, because it is not a statement about *this* repo but about *every*
repo on the machine; and a detached HEAD speaks while still allowing, because it is a deliberate
policy exception rather than an evaluation failure, and an unannounced one was a one-command bypass.

> **The rule was first written as "opted in *and* holds an un-superseded planning card"** — which is
> not what the code does, and the round-5 judge caught the gap. All three non-git warnings fire in a
> repo with no planning card at all. Under the stated-but-wrong rule one exit stayed misclassified
> and hid a further instance at the payload parse. The rule above is the one the code follows.

**Justifiably silent** — the hook has nothing to say:

| Exit | Step | Why silence is right |
|---|---|---|
| Empty payload | 1 | Nothing was sent; not yet known to concern an opted-in repo |
| No `.git` found walking up from the target | 4 | Out of scope entirely |
| No `docs/features/` | 4 | This repo never opted in |
| Path outside the root, after physical resolution | 5 | Genuinely not ours to judge |
| Exempt path (`docs/*`, `.claude/*`, `settings.json`, memory) | 6 | Guarded-by-design exclusion |
| Nothing at `planning` | 7 | The ordinary quiet case |
| Every `planning` card superseded | 8 | Their gates already opened |
| Branch is claimed | 9 | A legitimate, positive allow |

**Must be audible** — the guard is off where it would otherwise have been enforcing:

| Exit | Step | Why it must speak | Pinned by |
|---|---|---|---|
| No `git` on PATH | 2 | Guard off in *every* repo until PATH is fixed | A4.5 |
| No python interpreter | 2 | Same, and the reason this asymmetry was removed | A2.1 |
| Payload unreadable / no usable path | 3 | Opted-in repo, guard switched off by a malformed message | A1.4, A1.5 |
| Write target unresolvable to a physical path | 4 | Opted in, and "is this path ours?" is unanswerable | A5.6 |
| **`.git` exists but cannot be read** | 4 | A repo that may have opted in, and the gate cannot be evaluated there at all | **A7.1** |
| Any `docs/features/*.md` entry skipped | 7 | Cannot read part of its own input | A2.4, A2.15, A2.18–A2.22 |
| `docs/features/` cannot be listed | 7 | Opted in, yet *every* card vanishes at once | A4.1, A4.2 |
| `git for-each-ref` fails | 8 | Supersession unresolvable while a card is active | A1.8 |
| `git cat-file --batch` pipeline fails | 8 | Same | A1.9 |
| `git rev-parse --abbrev-ref HEAD` fails or is empty | 9 | Branch unresolvable while a card is active | A1.10a/b |
| Detached HEAD | 9 | Still allows, but the gate is off and that must not be invisible | A4.6 |

**Six of these were asserted SILENT by the suite itself** — the four git exits (`A1.8`–`A1.10b`)
and the two payload exits (`A1.4`, `A1.5`), all against a repo holding an un-superseded planning
card on an unclaimed branch. They pinned the guard being switched off at the exact moment it was
about to deny. That is what the bug class looked like from the inside: **not missing tests, enforcing
ones** — which is why four consecutive judge rounds read this suite as evidence of correctness.

**And the enumeration itself then hid a seventh** (`A7.1`, added in review). The *Justifiably
silent* table's second row used to read "Not a git repo / no root", which is two conditions wearing
one name: `rev-parse` fails both when there is no repo and when there is one it cannot read, and
only the first is out of scope. Rounds 5 and 6 each reported the unreadable case; it survived both,
because anyone checking the audit against the code found a row that appeared to cover it. The row is
now split — the silent half above, the audible half in the table below. The lesson is narrower than
"enumerate the surface": **an enumeration entry naming a `git` failure mode is one row per
*condition*, not one per *exit*,** because a single non-zero status is not a single cause.
Converted in review.

Each still exits 0 and each still speaks **at most once per session**, so a flapping git costs one
line per session, not one per write.

**Not an exit, but the same class — step 5's symlinked repo path.** `git rev-parse --show-toplevel`
always reports the *physical* path, while a payload can legitimately reach the same file through a
symlinked ancestor (`/tmp` and `/var` are symlinks on macOS; so is any symlinked checkout). The
prefix match then failed, the write read as outside the repository, and the guard was off for the
**whole repo**, permanently and silently. Raised as a fixture gotcha in round 1 and as a real route
by two judge rounds before being fixed here: a failed match is now retried against the payload's
physical form — walking up to the deepest existing ancestor first, since a `Write` target need not
exist yet. Pinned by A4.4a/A4.4b.

> **That fix shipped with two defects of its own, found reviewing it and fixed in review.** The
> `cd`-failure branch was written as a bare `|| exit 0` — the silent-fail-open class, inside the fix
> for the class; it now warns (the `A5.6` row above). And the walk-up reattached the remainder with
> no separator whenever *no* ancestor existed, which is every relative path: `dirname` bottoms out
> at `.`, so `x.sh` glued into `…/repox.sh` and a dotfile lost its leading dot, both escaping the
> gate in silence. A relative target now anchors at the cwd that `cd "$fp_dir"` already resolved —
> which is what that branch means — so it is judged rather than skipped. Reachability was low
> (payload paths are absolute by contract) and neither was reachable as a *false deny*; pinned by
> A5.1–A5.5, controls in both directions.

**`HOME` unset** made `STATE_DIR` an unbound variable under `set -u`, so the hook exited **1** on
every write — the one code the Output contract calls illegitimate. Now `${HOME:-}`. Pinned by A4.7.

### The repo is the file's, not the session's — and what that cost

Step 2 *as it then was* — the repo step, before the reorder renumbered it to 4 — resolved the root
by running `git rev-parse --show-toplevel` in whatever directory the **session** happened to be
standing in. The same target file was therefore denied or allowed
according to the cwd, and the allow was silent — the fail-open class one step upstream of every
exit the audit enumerated.

**Credit, corrected in review.** This paragraph read "Six judge rounds read that line without seeing
it; it was found by asking what step 2 actually resolves." (That "step 2" is the pre-`508c55b`
numbering's `rev-parse`, step 4 as shipped.) That is false, and it was repeated into
the session's own state file and then handed to the round-7 judge as fact — where the judge checked
it and rejected it. **The round-6 verdict found this bug and prescribed the fix.** It states the
defect ("the repo root is derived from the hook's CWD, not from the payload"), reports the probe
("with CWD outside the target repo … **exit 0, silent**, while the same write with CWD inside
denies"), gives the one-line remedy — `git -C "$(dirname "$file_path")" rev-parse …`, which is what
shipped — and flags it as "the item I would most want confirmed before merge"
(`coding-memory/observability-judge/2026-07-28-feature-phase-guard-hook-round6.md`, line 108). Five
rounds missed it; the sixth caught it, and the record credited self-review instead. Worth keeping
visible, because a record that quietly reassigns credit away from the review process is a reason to
trust that process less than the evidence says you should.

A linked worktree has its own toplevel, so this was not an edge case: a session in the primary
checkout writing into its worktree — the parallel-agent workflow `core-conduct.md` prescribes and
this gate exists to protect — resolved the wrong repo every time. Pinned by A6.3/A6.4.

**The fix reorders the hook**, because the payload must be parsed before there is a repo to ask
about: steps are now payload → tools (git, python) → path → **repo that owns that path, and its
opt-in** → relativize, with steps 5–10 unchanged. `for-each-ref`, `cat-file --batch` and
`rev-parse --abbrev-ref HEAD` all take `-C "$root"` now; run bare, they answered for the session's
repo while the cards came from the file's.

**The cost is real and was accepted deliberately** (user decision, 2026-07-28). Measured on this
machine, 30 writes per case: a repo that never opted in goes **11 ms → 38 ms** per write — it now
pays a python startup before discovering it is not guarded — and an opted-in repo **35 ms → 41 ms**.
That directly contradicts step 4's own "bash builtin, not a `stat` subprocess" reasoning, which is
why it was a decision to take rather than an optimization to make. It buys back the only failure
mode the audit could not reach, and a PreToolUse hook already sits inside a tool round-trip
measured in hundreds of milliseconds.

**Two warnings changed meaning.** The unreadable-payload and unresolvable-path exits now fire
*before* the target's repo is known — the payload is how it would have been known — so neither can
claim "this repo opted in" any more. They fall back to the only signal left, the session's cwd:
audible when the session is standing in an opted-in repo (A1.4/A1.5), silent otherwise (A6.7), so
the reorder cannot put a line into every repo on the machine that never opted in.

**Any skipped file, not every skipped file** — revised in review after the shipped code was found
to warn only when *all* files were unreadable. One readable card made that test false, so a repo
holding one good card plus one unreadable `planning` card allowed writes in silence. The condition
is `nfiles > nparsed`.

**The check runs immediately after the parse loop, before any exit**, not inside one. A skipped card
is unreadable whichever path the hook then takes, and the first fix — placed inside the
no-planning-files branch — left step 8's supersession exit silent in exactly the same way. Guarding
exits one at a time produced the same defect twice.

**An empty `docs/features/` is not this case.** Zero files makes `nfiles > nparsed` false on its
own, so the `noparse` line cannot fire in a repo that created the directory and nothing else; that
takes the silent A1 path (step 4's "not applicable" reasoning, one directory later).

**Open contract question, deliberately unsettled.** The glob takes every `*.md`, so an ordinary
`README.md` in `docs/features/` is skipped too and warns once per session forever. The message is
phrased conditionally ("if it is one") so it states nothing false in that case, but *what a non-card
file in `docs/features/` should mean* is a contract decision, not a wording one, and is left to the
user.

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
| Store | `STATE_DIR="${PHASE_GUARD_STATE_DIR:-${HOME:-}/.claude/hooks/state}"`, mirroring `context-handoff-watch.sh:14`'s `${PANE_STATE_DIR:-...}` shape (`${HOME:-}` not `$HOME`: under `set -u` an unset `HOME` must fail open, not exit 1). The env var **is** the test-time override. |
| Path | `$STATE_DIR/phase-guard-<reason>-<sid>`, one flag per reason — `<reason>` ∈ {`nogitbin`, `nopython`, `nopayload`, `noresolve`, `noreporead`, `nolist`, `noparse`, `nogit`, `detached`}, every audible exit in the audit — independent flags, so one reason firing never suppresses another. (Authored for `nopython`/`noparse` alone; the audit grew and this row lagged it until round 9. Group D now derives the set from the call sites.) |
| Key, pre-parse exits (`nogitbin`, `nopython`) | `$CLAUDE_CODE_SESSION_ID` **only** — at step 2 no interpreter has parsed the payload, by construction |
| Key, every exit from step 3 on | payload `session_id`, falling back to `$CLAUDE_CODE_SESSION_ID` |
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
3. ~~**Last resort, `chmod -x hooks/phase-guard.sh`.**~~ **WITHDRAWN — this is not a rollback.**
   Round 1 claimed a non-executable hook is "skipped by the harness"; round 2 flagged that as
   asserted-but-unverified and predicted 126. **Task 17 measured it: exit 126, both as a direct
   path and under `sh -c`**, and `settings.json` registers a bare direct path, so that is the live
   shape. 126 is neither 0 nor 2 — a defect by this spec's own Output contract — and a `PreToolUse`
   harness may classify it as *deny*. The "last resort" would then **lock every repo on the machine
   against `Edit`/`Write`/`NotebookEdit`**, which is the opposite of a rollback and strictly worse
   than the misbehaviour it was meant to escape. Revised in the review phase, per the task-17 rule
   that findings are recorded during implementation and acted on only after the phase advances.
   → **Use paths 1–2.** Both are verified and sufficient: path 1 is an ordinary file edit under
   `docs/**`, path 2 deletes the `settings.json` block the guard deliberately exempts.
   → **Still unverified, and deliberately left so:** whether the harness *does* read 126 as deny.
   Establishing it means arming a hook that may lock the machine, so the honest move is to keep
   the path withdrawn rather than to run that experiment for a path we have no need of.

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

An allow emits nothing on stdout or stderr, with exactly the exceptions enumerated in "The exits
that must not be silent" — 11 audible rows across 9 once-per-session flag reasons, each reason
printing one stderr line at most once per session and still exiting 0. (Both counts are derived by
Group D, which fails the suite if either drifts — this sentence undercounted the surface by nearly
half for three rounds.) stdout is empty on every path without exception. A **deny** that also has a skipped
entry emits both: the warning line, then the full deny message — the skip check sits above every
exit, so it is not confined to allows.

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
  | 2 | any docs/features/*.md entry cannot be read or violates the contract | 7 |
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

Scenario 3 must be reached **only after** the repo root is resolved (step 4 as shipped; step 2 in
the pre-`508c55b` ordering this sentence was written against). A bare
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
feature is being planned. It largely does not: the repo step (4 as shipped, 2 when this was written) resolves the root with `git rev-parse
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

⚠️ **Superseded by `508c55b` — retained as the round-4 record, not as current fact.** The
floor described here was the *pre-reorder* one, when only a bash spawn and `git rev-parse` preceded
the early exit. As shipped the interpreter runs first, so `python3` startup is part of the floor
too and the non-opted-in path is ~41.8 ms, not ~12 ms — see *Live run*. Original text: **it was
below its own floor**; the non-opted-in figure had no headroom by construction, two operations being
mandatory before the early exit could fire. Measured twice, independently:

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

⚠️ **The paragraph that stood here was false, and it is the reason this correction exists.** It read:
*"It does not burden the common case: step 4 runs after step 3's early exit, so a repo that never
opted in never starts python. That is the early-exit design working as intended, and it is the one
performance claim here that rests on structure rather than on a stopwatch."* — quoted verbatim; its
"step 4"/"step 3" are the **pre-`508c55b` numbering**, where 4 was the interpreter and 3 the
`docs/features` early exit. Under the shipped numbering that sentence reads "step 2 runs after step
4's early exit", which is precisely the ordering the reorder inverted.

That was true of the pre-`508c55b` ordering and is **the exact opposite of what ships**. Resolving
the repo from the write target requires the path, the path comes out of the payload, and parsing the
payload is what starts `python3` — so the interpreter now runs **before** the opt-in test, and a repo
that never opted in starts `python3` once on **every write**. The claim was stated as structural,
which is worse than a stale stopwatch figure: a number goes out of date on its own, but this asserted
a property of the design that the design no longer has. Falsified with a counting shim by the round-7
judge, and consistent with the ~41.8 ms measured live (see *Live run*).

The `python3` startup is therefore no longer a cost paid only by guarded repos. It is the floor for
every write in every repo on this machine, and it remains the single largest lever on both paths.

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
      - `tool_name` is not extracted. Step 3 lists it, but nothing downstream consumes it and the
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
- [x] 6. Implement the deny message to contract. **Green for task 5.** Every later test may now
      assert on stderr.
      - Done: 25/25 green (was 17/8); the four sibling hook suites still pass and `shellcheck -x`
        is clean.
      - **Task 5's one vacuous assertion is now falsified.** `err_lacks` could not fail against an
        empty stderr, so it was proven here instead: each of its four alternatives (`no way
        around`, `cannot be bypassed`, `impossible to bypass`, `there is no bypass.`) was injected
        into the no-bypass line in turn, and each produced exactly **one** failure — that
        assertion, naming itself. Run against a *copy* of the hook, so the committed file was
        never modified (sha256 verified identical before and after).
      - The phase is printed as the constant `planning`, not echoed back from the file: step 7's
        match is what *makes* a file offending, and echoing its raw line would leak whitespace
        variants (`phase:   planning`) into a message the contract wants uniform.
      - `shellcheck` flagged SC2016 on the backticks around the gate phrase — a false positive
        (they are meant literally). Resolved by dropping the backticks for plain quotes rather
        than adding a `disable=` directive, which also removed the `'\''` escaping that made the
        line hard to read. No suppression directives in this file.
      - The message names the blocked path and adds that feature files live under `docs/`, which
        the guard never blocks. Neither is a contract element; both exist so the reader is not
        left wondering whether the fix is itself blocked.
- [x] 7. Test: Group A3 — the eight frontmatter-contract scenarios (six malformed shapes, optional
      `branch:` **with its second `planning` file**, forward-compatible unknown keys), including the
      `names good.md` / `does not name bad.md` assertions. Red where the minimal parser is too
      permissive.
      - Done: 44 pass, 3 fail. **The red set was predicted before the run and matched exactly** —
        examples 1, 2 and 5, the three where the minimal parser matches a `phase:` line without
        caring about fences or duplicates. Each fails only on `does not name bad.md`; its
        `still denies` and `names good.md` halves are green, so the failure is isolated to the
        one behaviour task 8 changes.
      - **Examples 3, 4 and 6 are already green — but not for the contract's reason, and that
        distinction matters when reading task 8's diff.** Today they pass because the value simply
        is not the literal `planning` (`plannning`, `Planning`) or there is no `phase:` line at
        all, so the minimal grep misses them by luck. After task 8 they pass because the file is
        *malformed and skipped*. Same observable outcome, different cause: their green is a
        regression guard, never evidence the contract is implemented.
      - Example 5 uses two **identical** `phase: planning` lines. The contract counts lines, so a
        parser that deduplicated values would wrongly accept this; a contradictory pair would also
        drag step 9's claim lookup into a scenario about step 7.
      - Every case pairs the malformed `bad.md` with a well-formed `good.md` at `phase: planning`.
        Without it a skipped `bad.md` leaves nothing to deny on, and all six would pass by exiting
        0 — the round-4 defect that the A3.7 `b.md` note already records, reappearing in a
        different place.
- [x] 8. Implement step 7 to the full **Frontmatter contract**. **Green for task 7.**
      - Done: 47/47 green, siblings green, `shellcheck -x` clean. One awk pass per file, matching
        the per-file grep step 9 already does; a single pass over all files was rejected because
        `ENDFILE` is gawk-only and this machine's awk is the one-true-awk.
      - **Falsification found two clauses the frozen tests cannot see.** Knocking out each contract
        clause in turn against a *copy* (committed hook sha-verified unchanged): the closing-fence
        clause turns A3.2 red and the one-`phase:`-line clause turns A3.5 red, so both are
        load-bearing. The other two are not, and neither gap is fixable here — task 7's tests are
        committed and the checklist is frozen:
        - **Clause 1 (line 1 is exactly `---`) is unfalsifiable by A3.1.** Probed directly: the
          fixture emits nothing with *or* without the clause, because without it line 2's `---`
          is read as the *closing* fence, leaving zero `phase:` lines — so the file is skipped by
          clause 3 instead. A3.1 proves the file is skipped, not *why*.
        - **The legal-value clause is invisible to A3.3/A3.4.** Removing it makes awk emit
          `plannning` and `garbage`, but step 7's shell-side `= "planning"` comparison rejects
          those anyway. Its real effect is the distinction between *malformed → cannot evaluate*
          (must become audible) and *well-formed but not planning* (silently fine) — which no test
          can observe until the flag contract lands at task 12. Kept deliberately: it is what the
          contract specifies, and task 12 is where it starts paying.
      - The "all files skipped" exit stays **silent** here, exactly as step 2's no-interpreter exit
        does, for the same reason: its once-per-session line is inseparable from the flag contract.
        No `skipped` variable is tracked yet — under `set -u` it would be assigned-but-unread, which
        `shellcheck` flags (SC2034). Task 12 introduces it with its reader.
      - **Recorded, not acted on: step 9 still reads claims with its own `grep IMPL_RE` + `sed`,
        not this parser.** A malformed file carrying `phase: implementation` and a `branch:` can
        therefore still claim a branch, which *allows* — consistent with fail-open, and no scenario
        covers it. Unifying the two readers is a review-phase decision; task 8's scope is step 7.
      - One `# shellcheck disable=SC2016` was added — awk's `$0` must not expand, and unlike task
        6's backticks it cannot simply be dropped. The `$2`-with-`FS=":"` alternative would break
        the contract's legal no-space form `phase:planning`. **This supersedes the closing line of
        task 6's note** ("No suppression directives in this file"), true when written.
- [x] 9. Test: Group B's remaining four rows (claimed branch; one feature planning must not revoke
      another; `implementation`-supersession; `review`-supersession), the NotebookEdit regression,
      Group A1 examples 8–11 (both git failures, empty/failed `rev-parse`, detached `HEAD`), the
      no-local-branches scenario, and **Group C** — the counting-`git` shim with its stdin tee,
      asserting one `cat-file --batch` / one `for-each-ref` / zero `git show`, plus the input-order
      parser against `blob`, `missing`, **and the trailing `LF`**.
      - Done: 55 pass, 11 fail. **The red set was predicted before the run and matched exactly** —
        B4, B5 (both supersession rows), A1.8, A1.9, A1.10a, A1.10b, A1.11 (the five git
        fail-opens), C0's *does not name alpha*, and C2/C3/C5 (the subprocess counts). Every one
        needs step 8, which task 10 owns.
      - **Two greens are vacuous today and must not be read as coverage.** A1.12 (no local branches
        still denies) passes only because there is no filter at all yet, and C4 (zero `git show`)
        passes because no git call is made on that path. Both start discriminating at task 10 —
        A1.12 in particular is there to stop an implementer conflating "no branches" with
        "git broke", which is a mistake only reachable once the filter exists.
      - **The shims were verified independently, because nothing in the suite exercises them yet.**
        The hook never calls `for-each-ref` or `cat-file` today, so a shim that silently failed to
        intercept would leave A1.8/A1.9 red for the wrong reason and go green at task 10 for
        another. Probed directly: the fail-shim returns 1 for `for-each-ref` while `rev-parse
        --show-toplevel` still passes through (0) — without that passthrough the case would exit at
        step 4 and pass for the wrong reason — and the counting shim logs argv *and* tees stdin.
      - That probe also re-confirmed the `cat-file --batch` asymmetry empirically, first-hand
        rather than from the round-3 note: `main:f.txt` in, `<sha> blob 3` + `hi` out, the request
        never echoed.
      - C0 asserts **which** file the message names, not merely that a deny happened: alpha is
        superseded on `feat/a` (blob) and beta does not exist there (missing), so a one-entry
        attribution slip names alpha instead of beta. `feat/a`'s alpha.md is committed with **no
        trailing newline**, so a parser reading content line-wise instead of by byte count drifts
        exactly onto the `missing` entry that follows it.
      - A1.11 uses a **real** detached HEAD rather than a shim — it is reachable in any rebase or
        bisect, and the real thing is the stronger fixture.
      - Two `# shellcheck disable=SC2016` directives, same cause as task 8's: the shim scripts must
        receive `$@`/`$*`/`$GIT_SHIM_REAL` unexpanded, since the shim resolves them at run time.
- [x] 10. Implement step 8: un-superseded filter accepting **`implementation` or `review`**, the
      single-subprocess `for-each-ref | cat-file --batch` pipeline, ⊘ on either git call failing,
      detached-HEAD ⊘. **Green for task 9.**
      - Done: 66/66 green, siblings green, `shellcheck -x` clean. All eleven of task 9's reds
        closed.
      - **⚠ ESCALATION — task 9's C0 test is a placebo for the two properties it was written to
        prove.** Falsification found only *one* of four load-bearing claims is caught by the suite:
        | mutation | really load-bearing? | caught by the suite? |
        |---|---|---|
        | `set -o pipefail` removed | yes | **yes** — A1.9 |
        | byte-count accounting (`skipnext`) removed | yes | no |
        | input-order attribution (`R[i]` → `R[1]`) | yes | no |
        | phase match unbounded from the frontmatter | yes, severely | no |
        **Root cause: C0's fixture makes the superseded file the FIRST request.** Any attribution
        drift or collapse still lands on that same file, so the outcome is identical and the test
        passes either way. Proven, not assumed — a probe fixture with the superseded file placed
        **second** discriminates every one of them: the real hook names `alpha`, each mutant names
        `beta`. The implementation is correct; the test cannot see it.
      - **The frontmatter bound is the sharpest of the three.** Unbounded, a fenced `phase: review`
        example inside a spec's own prose — committed on any branch — marks that feature superseded
        and the hook **exits 0**. Measured: bounded denies, unbounded allows. A guard that silently
        switches itself off because a spec quoted a phase value is the exact failure this feature
        exists to prevent, and nothing in the suite would catch its removal.
      - Not fixable here: task 9's tests are committed, the checklist is frozen, and tests must not
        be edited alongside implementation. **This is a review-phase item and it is the strongest
        candidate on the list** — a better C0 costs one fixture reorder.
      - Fail-open is implemented via `set -o pipefail` around the pipeline, restored immediately
        after. Without it the pipeline reports awk's status, so a broken `cat-file` reads as an
        empty result set — indistinguishable from "nothing is superseded", which **denies** on a
        git error and inverts Q3 in the step most likely to fail on a large repo.
      - `IFS` is set to newline for the request/filter loops: a branch name cannot contain a space
        but a feature-file path can, and the default `IFS` would split one into two bogus requests.
      - Empty `for-each-ref` skips the `cat-file` call entirely rather than feeding it nothing, so
        a repo with no local branches keeps every candidate and still denies (A1.12).
- [x] 11. Test: Group A2 — the two audible fail-opens, asserting exactly one stderr line, that a
      second invocation in the same session adds none, that the two reasons flag independently, and
      that an unwritable `$PHASE_GUARD_STATE_DIR` still prints and still exits 0.
      - Done: 80 total, **70 pass / 10 fail**. The split is exactly the one the task wanted — all
        ten audible assertions red, all four silence assertions green. *(The pre-run prediction
        named the right cases but tallied them "9 red / 5 green"; the miscount was arithmetic in
        the enumeration, not a surprise in behaviour.)*
      - **The reds were proven red for the right reason, not merely red.** Exit 0 with empty stderr
        is what *every* ⊘ produces, so a fixture that died early would look identical to one that
        reached the interpreter. Probed on an instrumented **copy** whose eight fail-open exits each
        name themselves — its labels carry the **pre-`508c55b` numbering** the probe ran under, so
        `STEP4-NOPYTHON` is what the shipped code reaches at step 2; kept verbatim because a
        renamed label cannot be matched against the probe log it came from. The no-interpreter
        fixture lands on `STEP4-NOPYTHON`, the all-malformed
        fixture on `STEP7-ALLSKIPPED`. A control run of the *same* no-interpreter repo on a normal
        PATH still reaches the deny (exit 2), which is what shows python is the only difference.
        `hooks/phase-guard.sh` was sha256-verified identical before and after.
      - **`NOPYBIN` is built by symlinking the needed utilities, not by filtering the real PATH.**
        A filter has to guess which directories hold a python, and one missed pyenv/conda shim
        leaves the hook working while the case goes green. `awk`/`sed`/`head` are symlinked in
        even though step 2 exits before them, so a later failure can never read as "no python"
        when it was really "no awk".
      - **A2.8–A2.10 separate the payload key from the environment key.** Two invocations and
        "the second is quiet" cannot tell them apart, so A2.9 changes the environment while holding
        the payload `session_id`, and A2.10 holds the environment while changing the payload's — an
        implementation reading `$CLAUDE_CODE_SESSION_ID` first fails both, in opposite directions.
        Written this way deliberately after task 10's escalation: a test that cannot discriminate
        is a placebo, and that is cheaper to prevent here than to find later.
      - **A2.3 is what makes the flag a *session* flag.** Without it, a permanent flag with no
        session in its key satisfies "a second invocation adds none" and measures nothing.
      - A2.6/A2.7 reuse the sessions A2.1 and A2.4 already flagged, so independence is asserted
        against real accumulated flag state rather than a simulation of it. A single shared
        "already warned" bit would let whichever reason fired first silence the other — telling
        the session the guard is dead for a reason that is not the live one.
      - A2.13 blocks the store with a **regular file standing where the directory would go**
        (`mkdir -p` exits 1) rather than with a `chmod` — the chmod version silently passes when
        the suite runs as root. A2.14 pins the accepted cost of the divergence from
        `context-handoff-watch.sh:42`: with no flag persistable, every write speaks.
      - **Honest limit — the four silence assertions (A2.2, A2.5, A2.9, A2.12) pass vacuously**
        against a hook that is silent everywhere today. Same class as task 3's two trivial allows
        and task 5's `err_lacks`: they only begin carrying weight at task 12, when there is a line
        for them to demand the absence of. Task 12 should falsify them the way task 6 falsified
        task 5's — by injecting a per-write print and confirming each one fails, naming itself.
      - The empty-`docs/features/` boundary is **not** re-asserted here; step 7's silent case
        already pins it. Two assertions of one property let a later change satisfy one and break
        the other.
      - Suite total 66 → 80. Siblings green (19/17/5/14), `shellcheck -x` clean.
- [x] 12. Implement the once-per-session flag to the **Flag contract**. **Green for task 11.**
      - Done: **80/80** (was 70/10) — all ten of task 11's reds closed. Siblings green
        (19/17/5/14), `shellcheck -x` clean, hook 249 → 318 lines (under the 400 soft limit).
        `git diff` for this task touches **`hooks/phase-guard.sh` only**: the test file is the
        unbiased baseline and was not reopened to meet the implementation.
      - **Step 7's exit had to be split before it could speak.** The existing
        `[ -n "$planning_files" ] || exit 0` conflates three states — no files, files that parsed
        but none at planning, and files none of which could be parsed — and only the third is the
        audible one. Replaced with two counters (`nfiles`, `nparsed`) so the warning is gated on
        *files present AND none parsed*, which is the spec's wording made computational.
      - **The `session_id` rides in the SAME python subprocess as the path**, not a second one:
        this is the hot path, and a repo in the noparse state hits that branch on every write.
        Encoded `<session_id>\n<file_path>` — an id can never contain a newline, so the first LF
        separates unambiguously while a path (which can contain one) keeps everything after it.
        Verified on bash **3.2.57** for all three shapes: both present, no LF at all (the
        no-usable-path case, which fails open and needs no id), and an empty id with a path.
      - **The falsification task 11 owed is discharged.** Eight mutations, each removing one
        load-bearing property, run against **copies** — the committed hook was byte-verified
        unchanged after every one:
        | mutation | caught by |
        |---|---|
        | flag check removed (prints per write) | **A2.2, A2.5, A2.9, A2.12** — the four that passed vacuously |
        | one shared flag instead of one per reason | A2.6, A2.7 |
        | environment id preferred over the payload's | A2.9, A2.10 |
        | flag name carries no session id | A2.3, A2.10 (+A2.6/7/8/11) |
        | bail silently when the store is unwritable | A2.13, A2.14 |
        | `nfiles > 0` half dropped | the empty-`docs/features/` assertion, alone |
        | `nparsed == 0` half dropped | A1.7, alone |
        The first row is the one task 11 named: those four could not fail against a hook that was
        silent everywhere, and now each fails on its own, naming itself.
      - **Finding, review-phase, not a defect.** Dropping *both* halves of the tally guard at once
        shows only A1.7, because A1.7 runs first, warns, and its flag suppresses the
        empty-`docs/features/` case that would otherwise fail too — the two share a session key
        (neither payload carries a `session_id`). Coverage is intact, since each half is caught by
        its own assertion above; but the once-per-session flag makes same-key silent assertions
        **order-dependent**, so reordering them, or inserting a warning case ahead of them, would
        move which assertion carries the property. Worth pinning an explicit session id per case
        when tests may next be edited.
      - `PHASE_GUARD_STATE_DIR` held for the whole run: `$HOME/.claude/hooks/state` contains zero
        `phase-guard-*` flags after the suite, confirmed directly rather than assumed.
- [x] 13. Add `/hooks/state/` to `.gitignore`, mirroring `:13`'s `/panes/state/` entry and its
      "machine-local, never committed" comment. One line; without it the flag store accumulates
      untracked inside this repo (see *Artifacts*).
      - Done: entry at `.gitignore:17`, with the two-line comment the task asked be mirrored, placed
        directly under the `/panes/state/` block so the two runtime stores read as one group.
      - Verified the way *Artifacts* framed the gap, by running the same probe: before,
        `git check-ignore -v hooks/state/phase-guard-x` matched nothing; after, it reports
        `.gitignore:17`. The anchoring `/` is load-bearing and deliberate — an unanchored
        `hooks/state/` would also shadow a same-named directory anywhere in the tree, which is the
        trap `:45-46` already documents for `/daemon/`.
- [x] 14. Register the `PreToolUse` / `Edit|Write|NotebookEdit` block in `settings.json`. It is a
      **fourth** matcher block (existing: `Bash`, `Task|Agent`, `*`), not an edit to one — verified
      2026-07-25. Commit it on this branch; making it *live* in the primary checkout is the separate,
      manual half described in **Registration and its revert**. A concurrent session may hold that
      file on another branch — check before writing.
      - Done: the scouting held. `PreToolUse` had exactly three blocks and now has four; the
        `Edit|Write|NotebookEdit` string a grep finds elsewhere is the **`PostToolUse`**
        `handoff/post-edit-hook.sh` block, re-confirmed here and not touched.
      - Shape mirrors the `Task|Agent` sibling exactly — one `type: command` entry, `$HOME`-relative
        path, **no `timeout` key**. None of the five house guards carry one; the only timeouts in the
        file belong to the vendored orca `*` hooks. Placed between `Task|Agent` and `*` so the house
        guards stay contiguous and the vendor catch-all stays last.
      - Verified: `settings.json` still parses (`json.load`), the block resolves to
        `hooks/phase-guard.sh`, which exists and is mode 755 — a non-executable hook is rollback
        path 3, still open until task 17 measures it.
      - The concurrent-session check the task asked for: the primary checkout's `settings.json` was
        clean at session start, so no other session held an edit to it.
      - **Committed ≠ live**, per *Registration and its revert*: this commit does not arm the hook.
        The primary checkout sits on another branch and picks the block up when this lands on `main`
        and it pulls. Arming it sooner means hand-editing that working copy, which this PR's revert
        does not reach — rollback path 2, deliberately manual.
- [x] 15. **Amend the existing `Phase gate` stub at `rules/gates.md:5`** — not a new bullet. That
      file is always-on context in every session, and a **19th** bullet costs every future session
      tokens to say what the existing stub can say in a clause. *(Count verified 2026-07-26: 18
      bullets today. Round 2 and 3 both said "26th"; it was decorative and wrong twice.)*
      - Done: two clauses appended in place, `1 insertion(+), 1 deletion(-)`; bullet count
        re-verified **18** after the edit.
      - The stub says "docs and memory paths are never blocked" rather than enumerating — step 6's
        real list is `doc-guard.sh:149`'s verbatim plus `.claude/*` and `settings.json`, and
        spelling all five out in always-on context buys nothing a session acts on differently.
      - It carries `merge-guard.sh`'s existing "momentum guardrail, not a security boundary"
        idiom for the Bash hole, so the two honest-limitation stubs read alike, and states the
        implementation half is judgment-only — the reverse-enforcement non-goal, made visible
        where a session would otherwise assume the hook covers both directions.
- [x] 16. ADR `docs/decisions/0011-*.md` — amends ADR 0010: records that its stated objection was
      dismissed by reframing (branch-scoped permission), that its "build only when the gate is
      observed being skipped" deferral was deliberately overridden at the gate decision (Q1), and
      that the Bash-tool write surface and sticky supersession are disclosed non-goals rather than
      oversights.
      - Done: `docs/decisions/0011-branch-scoped-write-permission.md`. All four required elements
        present. ADR 0010 left **unedited** and still Accepted — 0011 carries an `Amends:` header
        instead, since an ADR is immutable and the amendment record is the newer file's job.
      - The two grounds are recorded as **different kinds** of overturn, deliberately: the technical
        objection was never refuted on its own terms, it was made *inapplicable* by the forward
        lookup; the process deferral was met head-on and overridden with the trigger condition
        admittedly **unmet**. Conflating them would let the process override read as a technical
        finding, which is exactly the reading this ADR exists to prevent — the `spec-guard`
        deferral it borrowed from is still live.
      - Diagram is one `flowchart TD` on the reframing alone (the two lookup directions), not the
        whole 7-row verdict table — one idea per diagram. `validate-diagrams.sh`: **PASS**, 1 block.
      - Numbering re-verified at write time: `0009` is still held by `feat/pane-split-policy`
        (PR #28, open) and absent here, so `0011` collides with nothing on either branch.
- [x] 17. Dogfood, in a **throwaway repo**, not this one. By task 17 this feature's own gate has
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

### Task 17 — throwaway-repo dogfood (2026-07-28)

`git init`'d temp repo, one `docs/features/x.md` at `phase: planning`, `PHASE_GUARD_STATE_DIR`
pointed at the temp tree. **16 assertions, 16 passed, 0 failed.**

- **(a) Source write denies.** Exit **2**, stdout empty, and all four message elements present:
  offending file + its phase, `current branch: main`, both legitimate fixes, and the no-bypass
  clause. Also asserted the *narrowness* of element 4 — the message says "no bypass environment
  variable" and never "no way around this", which the Bash hole would make false.
- **(b) Exempt paths allow.** All six of step 6's list pass: `docs/features/x.md`, `docs/notes.md`,
  `.claude/session-state.md`, `settings.json`, `CODING_MEMORY.md`, `coding-memory/log.md`.
- **(c) Advancing `phase:` unblocks**, and reverting to `planning` re-denies — the round trip, so a
  pass cannot come from the guard having simply gone dead after the first write.

**Rollback path 3 is resolved, and it does not work.** Round 1 claimed a non-executable hook is
"skipped by the harness"; round 2 flagged that as asserted-but-unverified and suspected 126.
**Round 2 was right.** `chmod -x` then invoking yields exit **126** (`Permission denied`) both as a
direct path and under `sh -c` — and the registration in `settings.json` is a bare direct path, so
that is the live shape. 126 is neither 0 nor 2, which this spec's own Output contract calls a defect
regardless of how the harness classifies it, and a `PreToolUse` harness may well read it as *deny* —
i.e. the "last resort" rollback may **lock every repo on the machine** instead of disarming the
guard. Paths 1 and 2 are unaffected and remain the real exits.
→ **Recorded, not acted on.** Revising the Rollback section is a review-phase edit; `implementation`
forbids it.
*Limit of this test:* it establishes the exit code, not the harness's classification of it. Whether
126 reads as deny is still unverified and needs a live check before path 3 is rewritten.

### Review-phase escalations — resolved

**1. Task 9's C0 test was a placebo — fixed, and the round-4 diagnosis was wrong.** Baselined by
mutation against the pre-fix suite: all three mutants below escaped **all 80 tests, 0 failures**.

| Mutant | Claim it breaks |
|---|---|
| drop the trailing-LF skip | byte-count accounting |
| collapse input-order attribution (`i++` → `i=1`) | input-order matching |
| unbind the phase match from the fences | frontmatter bound |

Round 4 prescribed "one fixture reorder" — put the superseded file second. **That was tried first
and measured: all three still escaped.** The reorder cannot work, because a desync only changes an
answer if it corrupts the record that *decides* the outcome, and with the superseded file at
request 1 or 2 its mark is already set before any drift begins. The requirement is that a normal
trailing-newline blob be read **before** the superseded one. C0 is now three files — `alpha`
(planning, trailing newline, carrying a literal `phase: implementation` line in prose below the
fence), `beta` (superseded, no trailing newline), `gamma` (deleted on the branch, so its record is
the asymmetric `missing` echo). Each mutant now flips a different assertion; all three are caught.
C5's request count moved 6 → 9. The hook was correct throughout — this was test-only.

**3. Step 9's raw-text branch claim was a fail-open — fixed.** Step 9 re-read every feature file
with an unbounded `grep -Eq` + `sed`, so any text anywhere in a file resembling
`phase: implementation` plus `branch: <name>` granted permission on that branch — and feature files
are precisely the documents that quote those keys in prose. A file step 7 had already skipped as
malformed still got a vote. Reproduced first as failing tests **B2b** (prose describing a claim) and
**B2c** (a malformed file claiming), then fixed: the parser now emits `<phase>TAB<branch>`, step 7's
existing loop collects claims from the same parse that decides planning membership, and step 9 is a
string-membership test that touches no files. Falsified by reverting step 9 to its old form — fails
exactly B2b and B2c and nothing else. Incidentally drops one `grep` and one `sed` per feature file
off the guarded path.

**2. A3.1 could not isolate the line-1 clause — closed by A3.1b.** The clause does two jobs: reject
a file whose line 1 is not `---`, and `next` past line 1 so an opening fence never trips the
closing-fence rule. A3.1's shape (leading blank line) survives removal of the *rejection*, because
its first `---` then lands on line 2 and trips the closing rule with `nphase` still 0 — the file
fails the contract by a different route and the verdict never moves. A3.1b puts junk on line 1 with
`phase:` between it and the fence, so removing the rejection makes the parser print `planning` and
the deny name `bad.md`. Both are kept; A3.1 is a real-world shape, A3.1b is the discriminating one.
Checked against both faithful mutants — deleting the whole rule is too blunt to mean anything
(41 failures, since line 1's own `---` then closes the frontmatter immediately), while
`NR == 1 { next }` is caught by **A3.1b alone and by A3.1 not at all**.

**4. Same-key silent assertions were order-dependent — closed.** `allow_silent` only checks that
stderr was empty, and the audible fail-opens are suppressed after their first firing under a given
key. Every case shared the `nosession` fallback, so any earlier case that warned would make the two
step-7 silent assertions pass for the wrong reason. Both now pin their own session id and assert
the flag store is untouched (new `no_flag_for` helper). Measured before changing anything: no
earlier case writes that flag today, and mutating away the `nfiles > 0` guard was already caught —
so this removed a dependency on test order that nothing was enforcing, rather than repairing a
broken assertion. *The round-3 note's stated mechanism was wrong*: it claimed "A1.7 warns first and
suppresses the empty case behind it", but A1.7 parses its file fine and never warns at all. The
exposure was real; the explanation was not.

**5. The audible fail-open was only audible when EVERY card was unreadable — fixed.** Raised by
the implementation-stage observability judge and independently reproduced before any change. The
tally below step 7's loop asked `nfiles > 0 && nparsed == 0`, so **one** readable card was enough to
make it false. A repo holding one well-formed card at a non-planning phase plus one unreadable card
— which was the repo's only `planning` card — therefore skipped the unreadable one, found nothing at
planning, and **allowed the write with no output at all**. That is exactly the death Group A2 exists
to prevent, reached by the likeliest route in practice: a one-character frontmatter slip in the card
being actively worked on, while the finished cards beside it stay valid. It also got *more* likely as
a repo accumulated features, so the guarantee weakened precisely as there was more to guard.

Why the suite could not see it: every Group A2 fixture makes **all** files malformed, and every
Group A3 fixture pairs the malformed file with a well-formed **planning** file that denies
regardless. Neither shape can produce a partial skip that ends in an allow.

Reproduced first as **A2.15** (fails against the pre-fix hook), then fixed by widening the tally to
`nfiles > nparsed` — "was any file skipped", not "were they all". Zero files still makes the
comparison false on its own, so the empty-`docs/features/` case stays silent without a second guard.
`NOPARSE_MSG` was reworded from "every file … failed" to "a file … failed … and was skipped", which
was false for the partial case. **A2.17** pins the opposite direction so the widened test cannot be
mutated to an unconditional warn. Mutation-checked both ways: narrowing back to the all-skipped form
fails A2.15 alone; widening to `nfiles > 0` fails A2.17, A1.7 and B2.

The comment above the parser also over-claimed — it said a typo'd phase "must not silently switch a
CRITICAL gate off", which is what the code did. Reworded to state the honest guarantee: a skip costs
the gate that file's opinion, and what the design promises is that it cannot cost it *silently*.

**6. `nbranch > 1` was untested — closed by A3.5b.** Found by the same judge via mutation: deleting
the duplicate-`branch:` clause left all 88 assertions green. Counting `branch:` lines only matters if
a second one can change the answer, so A3.5b makes the duplicate load-bearing — `bad.md` claims
`implementation` and lists two branches, the last being the branch under test. awk keeps the last
assignment, so without the clause `bad.md` parses, claims the branch, and the deny becomes an
**allow**. Mutation-checked: deleting the clause fails A3.5b and nothing else.

**7. The same silence one stage later — the fix for 5 was an instance fix, not a class fix.** Raised
by the observability judge on RUN 2, against the RUN 1 remediation itself, and again reproduced
independently before any change. Escalation 5's widened tally was placed *inside* the
no-planning-files branch. But step 8 can empty that same list one stage further down: a card that
reads `planning` in the working tree while its own branch has already advanced is dropped as
superseded, and the exit below that drop was a bare `exit 0`. Measured side by side: superseded card
+ one unreadable card → **exit 0, silent**; the same unreadable card alone → warns correctly. A
stale card on `main` is precisely what supersession exists for, so this is the ordinary shape.

Reproduced as **A2.18** (red against the escalation-5 fix), then fixed by **moving the check
upstream of every exit** — immediately after the parse loop — rather than adding a second guarded
exit. A skipped card is unreadable whichever path the hook then takes; guarding exits one at a time
is what produced the same defect twice. Consequence, verified deliberately: a deny that also has an
unreadable card now emits the warning line *and* the full 16-line deny message (exit 2, all four
required elements intact), which is the correct reading of both facts rather than a regression.

**8. The `noparse` message asserted something false for a non-card file.** The glob takes every
`*.md`, so an ordinary `README.md` in `docs/features/` is skipped too — and the message told the
session "the gate cannot be fully evaluated" when the only unreadable file was never a card, on the
one hook that fires on every write. Reworded to "could not be read as a feature card … **if it is
one**, the gate is not seeing it", true in both cases. **What a non-card file in `docs/features/`
should mean is left open** — that is a contract decision, not a wording one.

**9. The spec's normative section still stated the pre-fix rule.** Escalation 5 was written into the
narrative but the Exits table and the paragraph under it still read "**at least one file present and
all present files skipped**" — the bug, recorded as the specification, which a maintainer trusting it
would have restored. Corrected in place.

**10. The counting hole — the same silence one step EARLIER, before any exit.** Raised by the
observability judge on RUN 3, against the RUN 2 remediation, and reproduced independently. Moving
the check above every exit was correct and did close all nine exits — but the boundary was drawn at
*exits*, and the hole was in the *counting*. `[ -f "$f" ] || continue` quietly did two jobs: detect
the unexpanded glob in an empty directory (its real job) and drop every entry that is not a regular
file. A dropped entry is never counted, so `nfiles > nparsed` cannot trip on it.

**Severity is not hypothetical.** Measured: a card symlinked into `docs/features/` denies correctly
while its target is present (**exit 2**, full message) and, once the target is moved or renamed,
**exit 0 with no output** — a real `planning` card silently leaves the gate. A dangling symlink and
a directory named `*.md` reproduce the same silence; a mode-000 file was the control, warning
correctly because it passes `-f`.

Fixed by testing that an entry **exists in any form** — `[ -e "$f" ] || [ -L "$f" ] || continue`.
`-L` is required beside `-e` because `-e` follows the link and is false for a dangling one, which is
exactly the entry that must still count. Verified the empty-directory case still passes over the
unexpanded glob.

**11. `awk`'s own stderr escaped the once-per-session suppression.** An entry awk cannot open made
it write a diagnostic *per invocation* — three lines on the first write, two on every write after —
straight past the flag the warning is careful to respect, on the one hook that fires on every write.
Silenced with `2>/dev/null`; the failure is not lost, because an unopenable entry produces no output
and that is already the skip signal. **A2.21/A2.22** pin it (`allow_audible` requires *exactly one*
stderr line, so awk noise fails rather than passing as cosmetic).

**12. The spec still stated the pre-fix rule in three more places.** Escalation 9 corrected the two
locations RUN 2 named and left the numbered algorithm (step 7), the Output contract, and the Examples
table untouched — including the first thing a maintainer reads. All three now state the any-entry
rule and the before-every-exit placement; the Output contract additionally records that a deny with a
skipped entry emits both lines. Historical narrative quoting the old wording is left as-is, because
it describes what *was*.

**A note on the pattern, recorded deliberately.** Three judge rounds found three instances of one
class — the guard going silent. Rounds 1 and 2 were patched at the point of failure; only round 3's
fix addressed the reason the suite could not see any of them: **every fixture in the suite was a
readable file with malformed *content*, and none was an entry the parser could not open at all.**
A2.19–A2.22 close that fixture class, which is the durable fix; the two-line `-e`/`-L` change is
merely what it exposed.

**13. `docs/features/` itself being unlistable — the fourth instance, and the end of patching.**
RUN 4 found it and it reproduced exactly: with a real `planning` card present, `755` → deny,
`444` → **exit 0 silent**, `755` → deny, `000` → **exit 0 silent**, `755` → deny. The `444` case is
the sharper one — the shell still expands the glob to the real filename, so the entry is *known to
exist*, and `-e`/`-L` both need search permission on the directory, so it is dropped uncounted.
`nfiles` stays 0, the skip tally has nothing to compare, and the repo reads as opted-in and
unguarded simultaneously. Worse than escalation 10 when it happens: that dropped one card, this
drops every card at once.

**This was not patched as a fifth instance.** Four rounds had found four instances, each a step
earlier than the last, and each fix had been *described* as a class fix. The response was to
enumerate the whole fail-open surface instead — see "The exits that must not be silent", now an
audit of all sixteen exits rather than a list of two.

**THE RULE that fell out, and the audit's real finding:** once the hook knows the repo is opted in
and holds an un-superseded `planning` card, it was on its way to deny; any later inability to finish
must be audible. Everything upstream of that knowledge stays silent. Applying it uniformly closed
the directory-listing hole **and four exits nobody had reported** — `git for-each-ref` failing,
the `cat-file --batch` pipeline failing, and `git rev-parse --abbrev-ref HEAD` failing or returning
empty. Each turns a deny into an allow while a planning card is active.

**Those four were asserted SILENT by the suite itself** (`A1.8`–`A1.10b`, against `$OPTED` — an
un-superseded planning card on an unclaimed branch). The suite was not missing the class; it was
*enforcing* it. That is the most useful single thing the audit surfaced, and no amount of further
instance-hunting would have found it, because every judge round was reading the same suite as
evidence of correctness.

Two new audible reasons (`nolist`, `nogit`), both once-per-session like the existing two, so a
flapping git costs one line per session rather than one per write. Verified in both directions
end-to-end: the three must-speak cases speak, and all six justifiably-silent exits — exempt paths,
outside-root, detached HEAD, not-opted-in, claimed branch — stayed silent, so the audit added no
noise.

**14. The audit's own rule was misstated, and the misstatement hid a fifth instance.** RUN 5's
assignment was to audit the audit, and it found the rule printed at the top of the hook — "opted in
**and** holds an un-superseded planning card" — is not the rule the code follows. All three non-git
warnings fire in a repo with no planning card at all; the real rule is "opted in **and** could not
finish", which is weaker and better. Under the misstated version one row stayed misclassified, and
that row hid the fifth instance: **the payload parse**. Verified — against an opted-in repo with a
real planning card, a valid payload denies, while a truncated payload, a non-JSON one, or one whose
path key is renamed all exit 0 in silence. `A1.4`/`A1.5` asserted that silence, a few lines above
the four git cases the first audit pass had just converted.

**15. The step-5 symlink route — raised three times, fixed here.** Round 1 recorded it as a *test
fixture* gotcha; two later rounds re-raised it as a live route; the first audit pass enumerated
"every exit" and skipped it because it is not an exit. Verified: physical path → deny, the same file
via a symlinked repo path → **silent**, whole repo, permanently. Fixed by retrying a failed prefix
match against the payload's physical form.

**16. Three more asymmetries closed.** `git` missing from PATH was silent while `python` missing
speaks, for no reason anyone chose — both are machine-wide and permanent. A **detached HEAD** was
silent on a justification that argued from the very problem `warn_once` solves ("a rebase issues
many writes"), and unannounced it was a one-command bypass of a guard whose deny message says there
is no bypass variable; it still allows, but now says so. **`HOME` unset** made `STATE_DIR` an
unbound variable under `set -u` — exit **1** on every write, the one code the Output contract calls
illegitimate.

`A1.11` was **removed** rather than kept beside `A4.6`: the two stated opposite requirements about
one exit, and a suite asserting both can only ever half-pass.

**All sixteen review-phase escalations are now closed.** Suite **108/0**, `shellcheck -x` clean on
hook and tests, dogfood **16/16**, and every repro re-run end-to-end: partial skip, supersession,
dangling symlink, directory entry, unopenable card, moved-symlink severity case, unlistable
directory at 444 and 000, each git-failure exit, all three payload shapes, the symlinked repo path,
detached HEAD, and `HOME` unset — with the justifiably-silent exits re-checked in the same pass to
confirm the audit added no noise.

**Open, and NOT decided here — the parallel-worktree collision.** Also raised by the judge. Once
this merges, one agent opening any feature at `phase: planning` denies source writes to every other
concurrent agent on an unclaimed branch — and `rules/core-conduct.md`'s parallel-agent invariant
("never touch files outside your assigned feature domain") forbids that second agent from applying
the fix the deny message names. The two rules contradict each other in exactly this case. This is a
governance trade-off, not an implementation defect, so it is recorded rather than resolved.

**Timings — recorded, not a gate** (no threshold exists; round 4 withdrew the budget). 40 iterations
each, quiet machine. The measured figures include this harness's own per-call subshell, which was
measured separately at **2.3 ms/call** (`cat` in place of the hook) and is shown subtracted rather
than assumed:

| Path | Measured | Net of harness | Round-4 baseline |
|---|---|---|---|
| Guarded (deny) | 66.4 ms | **~64.1 ms** | withdrawn ≤60 ms budget |
| Non-opted-in | 14.7 ms | **~12.4 ms** | floor: 2.3 bash + 10.0 `git rev-parse` = 12.3 ms |

⚠️ **The non-opted-in row above is superseded — it predates the cwd fix (`508c55b`).** It is kept
because the reasoning built on it is cited elsewhere and a deleted number cannot be audited. See
*Live run* below for the current figures. The paragraph that stood here claimed the non-opted-in
path "lands on its structural floor almost exactly — step 3's early exit is working" (the
pre-`508c55b` step 3, the `docs/features` early exit). That claim is
now **false**: resolving the repo from the write target moved the parse and the `git` resolution
*upstream* of the opt-in test, so a repo that never opted in now pays for both. The guarded path is
unaffected, and the ~22 ms `python3` startup remains the only lever worth attacking.

### Live run — 2026-07-28, first execution against real repos

Every figure and behaviour above, in seven judge rounds, came from throwaway fixtures. This is the
first run of the hook at its real path, with real `PreToolUse` payloads, against real repos on this
machine. Probe artifacts were untracked and removed; the primary checkout's `git status` was
verified byte-identical afterwards.

Harness overhead was measured separately at **1.0 ms/call** and is subtracted below. 30 iterations,
payload built once and piped (building it per call adds a `python3` startup and inflates every
figure by ~15 ms — the first pass made that mistake and is not reported here):

| Path | Repo | Measured | Net |
|---|---|---|---|
| Non-opted-in, silent allow | `Other Docs/mtg-wizard` (real project) | 42.8 ms | **~41.8 ms** |
| Opted-in, deny | `.claude` on an unclaimed branch | 68.2 ms | **~67.2 ms** |

The deny path reproduces the fixture figure (~64 ms) within noise. **The non-opted-in path is
~3.4× the superseded 12.4 ms** — the cost of the cwd fix, and consistent with the 11→38 ms measured
when that fix landed. It is the number to quote: it is what every repo on this machine pays on
every write, forever, and only this branch's repo has opted in.

Behaviour observed live, all of it as designed:

- Never-opted repos (`mtg-wizard`, `.claude` as it stands today) — **exit 0, stdout empty, silent.**
- Opted-in worktree with its card at `phase: review` — allow, silent. Doc writes and writes to the
  feature card itself — allow, silent, even while the repo is enforcing.
- Opted-in repo on a branch no card claims — **exit 2** with the full deny message, stdout empty.
- **The cwd divergence, live:** with the session standing in the worktree (card at `review`) and the
  write targeting the guarded primary checkout, the hook denied — it judged the *target's* repo, not
  the session's. Under the pre-`508c55b` behaviour this exact shape allowed, silently. This is the
  bug class the fix was for, and it is now confirmed outside the fixtures that found it.

**What the live run did not cover:** the harness's own classification of exit 126 (rollback path 3,
deliberately not verified — the experiment risks the machine), and enforcement under a real
`/clear`-and-restore cycle. The hook remains registered but not armed; the harness reads the primary
checkout's working copy, which sits on another branch.

### Review round 9 — the record pinned to the code (2026-07-29)

RUN 9 found no behavioural defect (suite run twice by the judge, plus direct-invocation probes);
every finding was a record defect, and it was the fourth consecutive round in which green tests
coexisted with a stale record. Response: **Group D**, four grep tripwires that make the suite read
this document — step-list count/order vs the code's headers, a keyword per step per side, the Flag
contract's reason set derived from the call sites, and the Output contract's counts computed rather
than asserted. Red-first on exactly RUN 9's two contract findings; all four mutation-verified.
The three stale step references, the three undercounting contract statements, and A5.6's
pre-`508c55b` rationale were corrected in the same round. Still open and undisclosed until now:
supersession reads `refs/heads/` only, so a gate opened on a remote-only branch does not supersede
(owed to the PR body, with the per-level `dirname` cost on out-of-repo writes).

### Review round 10 — first low-risk verdict (2026-07-29)

RUN 10 at `31ebca7`: **risk=low, confidence=high, no failing dimension** — the loop's first
low-risk verdict. The judge reproduced this round's claims independently rather than trusting the
record: suite 130/0 and `shellcheck -x` clean at HEAD, red-first reproduced at `1b79e2a` (128/2,
exactly D3+D4), and all four Group D mutations re-run (each 129/1, failing only its own test). Two
residual record defects of the class a grep tripwire cannot see — a wrong *sentence*, not a wrong
count: the canonical step-3 entry (this doc, the "silently" claim in the malformed-payload item)
contradicts the audit table, A1.4/A1.5, and `warn_if_cwd_opted_in`; and `phase-guard.sh`'s
`warn_once` signature comment enumerates `(nopython|noparse)` as if exhaustive (2 of 9 reasons).
Both left un-fixed at this HEAD so the verdict stays pinned; they are the next commit's scope.
Verdict: `coding-memory/observability-judge/2026-07-29-feature-phase-guard-hook-round10.md`.

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
