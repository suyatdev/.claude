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

Replayed against `main` across 63 commands × 6 index/worktree states, that design allowed **44
distinct commands** `main` blocks. The narrow policy allows **8**, and all eight name only
documentation (`docs/*.md`, `CODING_MEMORY.md`, `coding-memory/*`) after a `--`.

The asymmetry is the point: a list of staging commands that is short **grants** permission it should
not, while reading the commit's own pathspec is a question the hook can answer from the text in
front of it.

**How far that carries, stated honestly.** The narrow policy is *measured* never weaker than `main`
across that replay matrix — not proven. Round 3 found two ways it was weaker that the matrix of the
day did not contain, and both were shipped as passing:

- The **whole line** was judged by **one segment's** paths, so a second commit naming nothing rode
  in behind the first one's documentation pathspec (`git commit -m a -- docs/a.md && git add --
  src/b.sh && git commit -m b`, where the second commit really carries `src/b.sh`).
- A path was matched **as a string**, so `coding-memory/../src/app.sh` satisfied `coding-memory/*`
  and `docs/../notes.md` satisfied `docs/*.md`. "Read off the command line" was doing work the
  reading could not support: the hook had read a token, not the file git would resolve it to.

Both are fixed, and the replay matrix now contains them. The claim a reader may rely on is the
measured one, over a matrix that has twice been found incomplete — replay checks what it is given,
which is still a strictly better position than "is this enumeration complete?", a question with no
check at all.

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

### A fact that grants permission must hold for the whole line

The classifier hands the hook a flat **set** of facts with no segment identity. `PUSH_FORCE` was
already built for that — it means "this segment force-pushes without a lease of its own", so a lease
elsewhere cannot excuse it. `COMMIT_PATHSPEC` was not, and it is the only fact that *grants*
anything: emitted from a single segment, it let one commit's paths answer for a line containing
another commit that named none.

The rule now stated in that file, and the one to apply to any fact added later: **a granting fact
must be true of every segment; a denying fact may be true of any one.** `COMMIT_PATHSPEC` and its
`COMMIT_PATH` entries are therefore withheld unless *every* commit on the line names its own paths
and none of them is widened by `-a`, `--amend`, `-i` or an unreadable token.

**"Every segment" means every segment the lexer can see.** The rule is only as wide as
`shell_segments.py`, so a commit hidden inside `bash -c "git commit -m b"` is not a segment it
withholds against — measured 2 → 0. That is the accepted-open lexing shape from ADR 0013, unchanged
here; it is restated because this rule's guarantee is stated in terms of segments and would otherwise
read as stronger than it is.

### A path is not the file it names

The allowlist is a `case` over the literal token, and a `..` component makes the string matched and
the file committed two different things. It now refuses any path with a `..` **component** (`..`,
`../*`, `*/../*`, `*/..`) before the allowlist is consulted, rather than resolving it — resolving
would mean answering "relative to which directory?", which is the identity-from-cwd question left
open below. A `..` inside a file *name* (`docs/v1..v2.md`) traverses nothing and stays allowed.

⚠️ **This section fixes only the `..` half of the class it names.** A path can also fail to be the
file it names by being a **directory** — see the first entry under *Known open* below. Recorded here
rather than only there, because a reader who takes this heading at face value will believe the class
is closed.

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

- **A pathspec can name a directory.** The allowlist matches the literal token by file *type*, on the
  premise that `docs/*.md` is a markdown file — but a **directory** named `docs/anything.md` matches
  the same pattern, and git commits everything beneath it. Measured end-to-end by the RUN 4
  observability judge: `git commit -m m -- docs/sneaky.md` exits **2** on `main` and **0** here, and
  the resulting commit carried a shell script. **Latent rather than live**: no directory under
  `docs/` ends in `.md` and there are no symlinks, so it takes a deliberately misleading name to
  reach. Not closed here because it is the third member of the "a path is not the file it names"
  class (`..`, directory, symlink) and the two rounds before this one showed that patching the
  instance found is what keeps the class open — it earns one fix that enumerates the family, with the
  test that a directory whose *name* ends in `.md` is refused.
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
- **`git -C <dir> commit` is invisible to the classifier**, which reads `argv[1]` as the subcommand
  and sees `-C`. Measured, both directly and across all six replay states: `main` and this branch
  both exit **0** and yield no facts at all, so the shape
  is pre-existing and **not widened here** — but it means a commit can name a directory the guard
  never looks at. The same class as identity-from-cwd above, and it belongs with that decision.
- The accepted-open lexing shapes from ADR 0013 are unchanged.

This guard remains a **momentum guardrail, not a security boundary**.
