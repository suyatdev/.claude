# 0014 — An empty index means "ask the command", not "deny"

- **Status:** accepted
- **Date:** 2026-08-03
- **Context:** `hooks/git-guard.sh` Guard 1 (default-branch commit guard), amending ADR 0013

## Context

Guard 1 blocks non-documentation commits to `main`. It decided by reading
`git diff --cached --name-only` and treated an **empty** result as "nothing is allowed".

A `PreToolUse` hook runs *before* the command it inspects. So `git add -- X && git commit -m m -- X`
— the form this repo mandates on every commit — reaches the guard with nothing staged, and was
refused even when `X` is documentation. The workaround in use was to split every commit into two
separate tool calls.

This became reachable only with ADR 0013's segment lexer: before it, a chained command matched
nothing and the guard body never ran, so the empty-index branch was dead code.

## Decision

**An empty index means "the index cannot answer", so ask the command instead.** The guard derives
the file set from the command line and evaluates *that* against the documentation allowlist.

**Four shapes commit content an empty index does not show. All four are consulted:**

| Shape | Where the files come from |
|---|---|
| the chain's own `git add` | the paths that `add` names, or `git status --porcelain` when it names an unbounded set (`-A`, `-u`, `.`) |
| `--` pathspec on the commit | the paths named, **exclusively** — git commits these and leaves the rest of the index alone |
| `-a` / `--all` | `git diff --name-only` (tracked worktree edits) |
| `--amend` | `git diff-tree` on HEAD (the tree being re-written) |

**When no shape names a file, allow.** Nothing is staged and nothing is named, so there is genuinely
nothing to commit.

**When the command cannot be understood, block** (`COMMIT_BARE_ARGS`). That covers a bare token the
flag table cannot account for, an unrecognised option, and `--pathspec-from-file`, whose paths live
in a file the hook cannot read.

Extraction lives in `hooks/lib/classify-git-command.py`, which already owns the lexer, so there
remains exactly one parser.

## Consequences

### The rejected option, and why it is a fail-open

"Empty index → allow" is the obvious simplification and it is **wrong**. Every one of the four
shapes above commits content the index does not show, and `-a` was previously blocked on `main`
only *by accident* of the empty-index deny. A mutant implementing it fails four pinned cases.

**The first implementation of this ADR made exactly that mistake in a narrower form:** it
enumerated three shapes and missed the chain's own `git add`. Four commands `main` blocked were
allowed — caught by an observability-judge round, reproduced before being accepted, and closed
before merge. The lesson generalises past this hook: the missed shape was the one that is *not
part of the `commit`*, so enumerating a command's own options felt complete while being short by
the most common case in the repo.

### A wrong stated reason is worse than a known gap

The first version justified allow-on-empty as *"git refuses such a commit itself — nothing to
commit"*. That is false the moment a sibling `git add` precedes it, and it was written into both
the spec and the hook comment, where it would have taught the next reader the same mistake. The
sentence is corrected in both places; **the enumeration is now stated as four, with the `git add`
case named first precisely because it is the one that hides.**

### The tests could not have caught it, and that is structural

The test comment's enumeration *was* the code's enumeration — written by the same author in the
same sitting. A suite built that way can only confirm the cases its author thought of. The suite
was at 40/0 while the hole was open. Mutation testing does not help either: it validates the
assertions against the fixture's premise, never the premise. This is the third instance on this
branch of a check inheriting the blind spot of the thing it checks.

### Accepted costs

- **A flag table.** Telling a pathspec from an option value with no `--` needs to know which
  `git commit` options consume the next token. Deliberately scoped to that job: `-a` detection
  still ignores option values, so `git commit -m '-a'` still reports `COMMIT_ALL`.
- **Abbreviations fail closed rather than being resolved.** git honours any unambiguous prefix of a
  long option, so `--amen` amends. Rather than reimplement git's prefix matching, an unrecognised
  option blocks. `-Skeyid` (inline value on `-S`) blocks for the same reason.
- **Renames from `git status --porcelain`** read as `old -> new`, match no allowlist entry, and
  therefore block. Intended direction for a shape this cannot parse.
- **`git status --porcelain` and the `git diff` calls run in the hook's own working directory**, so
  they inherit the open defect below — the derived file list is wrong in a worktree, not just the
  branch name.

### Known open, deliberately

- **Identity-from-cwd (`git-guard.sh:88`).** `current_branch` resolves from the hook's own working
  directory, not the directory the command will run in, so **work in a git worktree is judged
  against `main`**. Measured: identical payload, exit 2 from the primary checkout, exit 0 from a
  worktree. Not closed here because the payload `cwd` field is also recorded pre-`cd`, and
  `phase-guard`'s fix — resolve from the file being written — has no analogue for a commit. Shared
  with `judge-guard` and partially `doc-guard`. Needs a design decision, not a patch.
- **`--amend` with a *populated* index** still evaluates only the staged files, not HEAD's tree as
  well. Pre-existing, unchanged by this ADR, and not widened into it.
- The accepted-open lexing shapes from ADR 0013 are unchanged.

This guard remains a **momentum guardrail, not a security boundary**.
