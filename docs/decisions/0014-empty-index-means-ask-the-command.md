# 0014 — An empty index means "ask the commit", and trust only what it names

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

**An empty index means "the index cannot answer", so ask the commit instead — and ask it exactly
one question: which paths does it name after a `--`?**

| Shape, with nothing staged | Answer | vs. `main` before this ADR |
|---|---|---|
| the commit names paths after `--`, and nothing on the line can widen them | check those paths against the documentation allowlist | **relaxed — this is the whole change** |
| anything else: bare commit, `-a`, `--amend`, `-i`, `--only`, an unseparated path, any chain | **block** | unchanged |

Four things veto the pathspec, because each commits more than the paths given:
`-a`/`--all` (tracked worktree edits), `--amend` (HEAD's tree), `-i`/`--include` (the index as
well), and `COMMIT_BARE_ARGS` (a token the flag table cannot account for, an unrecognised option, or
`--pathspec-from-file`, whose paths live in a file the hook cannot read). `-o`/`--only` is not
recognised at all, so it lands in `COMMIT_BARE_ARGS` and blocks with the rest.

Extraction lives in `hooks/lib/classify-git-command.py`, which already owns the lexer, so there
remains exactly one parser.

### Why the guard does not work out what the command will have staged

That was this ADR's first decision, and it is now rejected. It derived the commit's file set from
the whole command line — the chain's own `git add` included — and was **wrong in kind, not in
detail**: it required a complete list of the ways an index gets filled, and no such list can be
shown to be complete. Two independent review rounds each measured it short:

- **Round 1** missed the chain's own `git add`, the shape the fix existed for. Four commands `main`
  blocks were allowed.
- **Round 2**, after `git add` was added, found nine more: `git rm`, `git mv`, `git reset --soft`,
  `git checkout HEAD~1 -- <p>`, `git restore --staged`, `git apply --cached`,
  `git stash pop --index`, `git cherry-pick -n`, `git revert -n`.

Replayed against `main` across 51 commands × 6 index/worktree states, that design allowed **36
distinct commands** `main` blocks. The narrow policy allows **6**, and all six name only
documentation (`docs/*.md`, `CODING_MEMORY.md`, `coding-memory/*`) after a `--`.

The asymmetry is the point: a list of staging commands that is short **grants** permission it should
not, while reading the commit's own pathspec can only ever grant paths the hook has actually read.
The narrow policy is therefore *provably* never weaker than `main` — a property that can be checked
by replay, where "is this enumeration complete?" cannot be checked at all.

## Consequences

### A stated completeness claim is a load-bearing claim

The first version of this ADR asserted *"Four shapes commit content an empty index does not show.
All four are consulted."* That was measurably false — there were at least ten — and it appeared in
the same document that diagnoses enumeration-shortness one level down. A reader would have trusted
the table and stopped looking. Completeness is now claimed nowhere; the policy is stated as *what
the hook reads*, which is checkable.

The predecessor mistake is kept on the record deliberately: an earlier version justified
allow-on-empty as *"git refuses such a commit itself — nothing to commit"*, which is false the
moment a sibling `git add` precedes it, and it had been written into both the spec and the hook
comment. **A wrong stated reason is worse than a known gap**, because it teaches the next reader.

### A pathspec is exclusive — verified, not assumed

The relaxation rests on `git commit -m msg -- <paths>` committing exactly those paths and leaving
anything else staged in the index. Measured directly rather than taken from the manual: with
`src/a.sh` staged, `git commit -m msg -- docs/b.md` produced a commit containing `docs/b.md` alone,
and left `src/a.sh` staged afterwards.

The same probe found a **live fail-open** in the rejected design: `git commit -i -m msg -- docs/b.md`
produced a commit containing `docs/b.md` **and** the staged `src/a.sh`. `-i` was read as an ordinary
pathspec commit and allowed, because the classifier returned the paths as soon as it saw a `--`,
before consulting the flag table. Flags before the separator are now scanned too.

### The tests could not have caught the original hole, and that is structural

The test comment's enumeration *was* the code's enumeration — written by the same author in the same
sitting. A suite built that way can only confirm the cases its author thought of; it was at 40/0
while the hole was open, and neither a 24,016-case fuzz run nor a mutation round could help, because
both validate assertions against the fixture's premise and never the premise. This was the third
instance on this branch of a check inheriting the blind spot of the thing it checks.

The suite now pins all nine staging commands as blocked. They pass **without the hook knowing any of
them** — they block for the same reason every unreadable shape blocks. That is the test the previous
design could not have: it fails if a future change starts inferring what a sibling command stages.

### Accepted costs

- **`git add X && git commit -m msg`, with no pathspec, stays blocked on `main`.** This is `main`'s
  behaviour today and the house rule already mandates `-- <path>` on every commit, so the friction
  the ADR set out to remove is removed; this residue is deliberate.
- **A flag table**, to tell a pathspec from an option value and to spot the widening flags.
  Deliberately scoped to that job: `-a` detection still ignores option values, so
  `git commit -m '-a'` still reports `COMMIT_ALL`.
- **Abbreviations fail closed rather than being resolved.** git honours any unambiguous prefix of a
  long option, so `--amen` amends. Rather than reimplement git's prefix matching, an unrecognised
  option blocks. `-Skeyid` (inline value on `-S`) blocks for the same reason.
- **A commit that names both documentation and source after `--` blocks**, as it does today.

### Known open, deliberately

- **Identity-from-cwd (`git-guard.sh`, `current_branch`).** It resolves from the hook's own working
  directory, not the directory the command will run in, so **work in a git worktree is judged
  against `main`**. Measured: identical payload, exit 2 from the primary checkout, exit 0 from a
  worktree. Not closed here because the payload `cwd` field is also recorded pre-`cd`, and
  `phase-guard`'s fix — resolve from the file being written — has no analogue for a commit. Shared
  with `judge-guard` and partially `doc-guard`. Needs a design decision, not a patch.
  Its blast radius **shrank** with this change: deriving the file set no longer runs `git status` or
  `git diff` in the hook's cwd, so cwd now affects only the branch name and the index read.
- **`--amend` with a *populated* index** still evaluates only the staged files, not HEAD's tree as
  well. Pre-existing, unchanged by this ADR, and not widened into it.
- The accepted-open lexing shapes from ADR 0013 are unchanged.

This guard remains a **momentum guardrail, not a security boundary**.
