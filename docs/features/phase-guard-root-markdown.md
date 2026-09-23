---
phase: implementation
model_tier: low
branch: fix/phase-guard-root-markdown
---

# `phase-guard` treats top-level markdown as source

> **Phase: implementation.** Gate confirmed by Mark 2026-09-21 after the compliance judge passed
> the card (blob `9639155e`; rounds: fail → pass → pass, then re-entered pass → pass after two
> wording fixes from the architecting judge, whose two reads scored risk low / confidence high).
> Branch `fix/phase-guard-root-markdown`, worktree `~/.worktrees/.claude/phase-guard-root-markdown`.
> Task 1 was done in planning; tasks 2–5 are the build. The spec below is frozen from here.

Filed 2026-09-21 from the Snatch-Bracket repo, where the gap was hit twice: session 8 could not
edit `README.md` to add a Roadmap line for a merged feature (`0db2c6f`, the process note in its
commit message), and the next housekeeping item — refreshing the status paragraph in `CLAUDE.md`
after PR #59 merged — hits the same wall. Both times the only sanctioned route was flipping a
card's phase on disk with the user's explicit OK written into the commit. That is a workaround
being reused, which is the signal to fix the cause.

Decision (Mark, 2026-09-21, three widths offered): **any `*.md` in the repository's top-level
directory is not implementation code and is unguarded.** Markdown in a subdirectory and a
non-markdown file at the top level are judged exactly as today.

## What is happening, plainly

`hooks/phase-guard.sh` refuses a write to source while any feature card in the repo sits at
`phase: planning` and no card at `phase: implementation` claims the current branch. Its step 6
(`hooks/phase-guard.sh:279-298`) is the list of paths it never judges: `CODING_MEMORY.md`,
`coding-memory/*`, `docs/*`, `.claude/*`, `settings.json`, `projects/*/memory/*`, and since
`f99b975` (user decision 2026-08-20) `rules/*` and `skills/*`. A repo's front-page documents —
`CLAUDE.md`, `README.md`, `AGENTS.md`, `PORTS.md`, `initial-brainstorm.md` — sit at the root,
match nothing on that list, and are therefore treated as source. Read with the hook's own
frontmatter parser (the `FRONTMATTER_AWK` contract, step 7) on 2026-09-21, three cards parse as
`phase: planning` in Snatch-Bracket at `0db2c6f` (same tree as its `origin/main`, `460133e`) and seven
in this repo at `6a1bcea` — one is enough — so in
both the front-page files are unwritable on every branch that no implementation card claims,
that is, on every fresh branch. (A first count of "five" here came from eyeballing line 2 of a
listing that was cut off at 40 lines; the compliance judge caught it.)

## Measured

At this repo's HEAD `6a1bcea`, through `hooks/phase-guard.sh` with a real `PreToolUse` payload
(`hook_event_name`, `tool_name: Write`, `tool_input.file_path`, `session_id`), against a throwaway
git repo holding one commit, one card at `phase: planning` with `branch: none`, on a branch no
card claims. Nothing was executed but the hook; rc 0 is allow, rc 2 is deny.

| path | rc today | after the fix |
|---|---|---|
| `README.md` | **2** | 0 |
| `CLAUDE.md` | **2** | 0 |
| `AGENTS.md` | **2** | 0 |
| `PORTS.md` | **2** | 0 |
| `docs/notes.md` | 0 (control, exempt list) | 0 |
| `rules/x.md` | 0 (control, exempt list) | 0 |
| `frontend/README.md` | 2 | 2 — nested markdown stays guarded |
| `agents/judge.md` | 2 | 2 — nested markdown stays guarded |
| `src/x.sh` | 2 (control, the B1 deny) | 2 |
| `setup.py` | 2 | 2 — a top-level non-markdown file stays guarded |

Every control behaves, so the four rc-2 rows are measured rather than assumed. A first attempt
at this table returned rc 0 on every row, `src/x.sh` included: the fixture had no commit, the
hook could not name a branch, and it fails open with a once-per-session warning (step 9,
`NOGIT_MSG`). The fixture used for the table above has a commit.

**Pre-existing, not a regression.** Every one of the 20 commits touching `hooks/phase-guard.sh`
was checked out and its `exit 0 ;;` exempt arms listed; deduplicated, the list has had exactly
three versions — `2a82691` (the original five entries), `f5c8862` (adds `projects/*/memory/*`),
`f99b975` (adds `rules/*|skills/*`) — and no version names a root-level file other than
`CODING_MEMORY.md` and `settings.json`. (The first draft here cited a `git log -S` on one string
as proof that `f99b975` was the *only* change; a `-S` search finds edits to that string, not to
the list, and the compliance judge caught it.)

## The rule

The guard exists to stop **implementation code** landing during planning (its own header, and the
step-6 comment written for `f99b975`). A markdown file in the repository's top-level directory is
never that: it is the project's front page, agent instructions, a port registry, a brainstorm.
The exemption is therefore stated as a rule about a kind of file, not a list of names.

Concretely, in step 6, before the existing `case` at `hooks/phase-guard.sh:294`:

```bash
case "$rel" in
  */*) ;;            # nested: judged by the directory rules below
  *.md) exit 0 ;;    # top-level markdown: documentation, never implementation code
esac
```

`$rel` is already relative to the repo root (step 5), so "no `/` in it" is exactly "sits in the
top-level directory". Two arms rather than one glob because in a `case` pattern `*` matches `/`
too, so a single `[!/]*.md` would also match `a/b.md`. Case-sensitive on the extension, like the
`*.spec.md` test in step 7.

### Considered and rejected

- **Name the two files (`CLAUDE.md`, `README.md`).** Narrowest, and a closed list: `AGENTS.md`
  (the standards-literature name for `CLAUDE.md`), `PORTS.md`, `initial-brainstorm.md` hit the
  same wall on their first edit, and the fix is filed a third time.
- **Any `*.md` anywhere.** Simplest to state, but wider than the rule it enforces: in this repo
  `agents/*.md` are the deliverable of some features (the two judges are agent files), and a
  planning card would no longer hold them back. Scoped narrow, the way `projects/*/memory/*`,
  `rules/*` and `skills/*` were.
- **Let a `phase: review` card claim its branch** (the fix `0db2c6f`'s note first suggested). It
  would have covered the README edit on a review branch, but it does nothing for a fresh
  housekeeping branch, and it would let review-phase source fixes skip the deliberate flip to
  implementation that Snatch-Bracket's `docs/features/profile-dressing-room.md` (spec 0013 there;
  its header, `:9-13`) records for exactly that case. Different rule, not this gap.
- **A bypass variable.** Rejected for this hook on 2026-07-25 and not reopened
  (`docs/features/phase-guard-hook.md`, Q at `:121-127`).

## Spec

```gherkin
Feature: top-level markdown is documentation, not source

  Background:
    Given a repository that opted in (docs/features/ exists)
    And one card sits at phase: planning
    And the current branch is claimed by no card at phase: implementation

  Scenario: a top-level markdown file is never judged
    When the session writes CLAUDE.md, README.md or AGENTS.md at the repository root
    Then the hook exits 0 and prints nothing

  Scenario: markdown in a subdirectory is judged as before
    When the session writes frontend/README.md or agents/judge.md
    Then the hook exits 2 with the step-10 deny message

  Scenario: a top-level file that is not markdown is judged as before
    When the session writes setup.py at the repository root
    Then the hook exits 2 with the step-10 deny message

  Scenario: nothing else moves
    Then every case in hooks/phase-guard.test.sh that passed before still passes
    And no fail-closed exit (no interpreter, unreadable docs/features/) is touched
```

No new fail-open path: the arm sits past step 5, so it can only ever fire on a path already
known to be inside an opted-in repo, and `exit 0` there is the same silent ⊘ every step-6 entry
already returns.

## Tasks

- [x] 1. **Measure** — the table above, at HEAD `6a1bcea`. *(planning, done 2026-09-21)*
- [x] 2. **Red tests** — `hooks/phase-guard.test.sh`: add `CLAUDE.md README.md AGENTS.md` to the
  unguarded-path loop (`:214-219`; these fail today, which is the receipt that the assertions are
  real), and after the `rules.sh`/`skills.sh` pair (`:232-233`) three deny controls:
  `frontend/README.md`, `agents/judge.md`, `setup.py`. Expected run: 150 passed, 3 failed
  (baseline 147/0, 11 s). Commit tests alone — never with the fix (`rules/core-conduct.md`,
  Testing). **That commit needs `TEST_EXEMPT='<reason>'`, stated plainly:** the marker gate is
  armed here, a staged test file whose script is tracked forms a gated pair
  (`hooks/lib/decide-commit-gate.py:183-187`), and the marker is written only by a green run
  (`hooks/phase-guard.test.sh:1240`) — a red suite by design has no marker. Reason to log: red
  tests only, no source staged, suite 150/3 by design. Precedent `80e0318` is the same shape.
  - Gotcha: `~/.claude/hooks/state/test-marker.log` holds 24 `EXEMPT` rows, and 14 of them
    (counted 2026-09-21 by `grep -ciE 'FOREIGN_REPO|worktree|git -C|cwd'` over the reason
    column) are commits made from a worktree that the gate read as `FOREIGN_REPO` — it resolves
    git from the session cwd, which here is another repo. If the green commit in task 3 trips
    that, the exemption reason names it; the suite must still have run green on the staged
    bytes first.
- [x] 3. **Green** — the two-arm `case` above plus a comment in the file's own voice (what the
  rule is, why it is scoped to the top level, the `*` matches `/` point), placed just before
  `:294`. Run the suite: 153 passed, 0 failed. Then the deletion receipt: remove the arm, run
  again, exactly the three new allows fail, restore. The suite run on the final bytes writes the
  test marker the commit gate reads.
  - Done 2026-09-22, `78e2dab` (tests) then `5a632a5` (the fix). Orchestrator-run receipt:
    153/0 with the arm, 150/3 with it deleted (exactly the three new allows; all three deny
    controls still pass), 153/0 restored at the same checksum.
  - The commit gate did not read that marker here: `hooks/test-marker-guard.sh` resolves its
    opt-in from the session's cwd (another repo, not opted in) and exits 0 before judging, so
    `78e2dab`'s `TEST_EXEMPT` was never consumed and neither repo log holds a row. Measured
    2026-09-22 by running the guard on the real payload (rc 0, no row). That commit's message
    reads as though the gate honoured the exemption; it is true as the reason the flag was set —
    though what the helper actually returns for this command is FOREIGN_REPO, so the pairing
    reason itself was never exercised — and wrong as an account of what happened. Left unamended
    by Mark's call (2026-09-22) — corrected here and in the PR body rather than by rewriting a
    pushed commit. The gate gap gets its own card.
- [x] 4. **Docs** — `rules/gates.md:5`, the Phase gate stub's exemption clause, gains "and any
  `*.md` at the repository root". The deny message's claim ("feature files live under docs/,
  which this guard never blocks") stays true and is not edited. Every `<file>:N` citation on this
  card is as of the pre-fix tree `6a1bcea`: task 2 inserts lines in the test file and task 3
  inserts lines above `phase-guard.sh:294`, so after them the citations describe the tree that
  had the gap, not the one after — and they are not rewritten, because the spec is frozen once
  the gate opens.
  Nothing in `docs/features/phase-guard-hook.md` changes — it is a merged card; `f99b975` set
  that precedent and documented on its own card instead. Its step-6 list (`:114-115`,
  `:248-249`) already lags the hook by the two entries `f5c8862` and `f99b975` added, so this
  card makes it three; `rules/gates.md:5` is the living statement (architecting judge, round 1).
  - Done 2026-09-22: the clause now reads "plus the retired
    `CODING_MEMORY.md`/`coding-memory/*`, and any `*.md` at the repository root". Nothing
    else on that line moved; `docs/features/phase-guard-hook.md` and the deny message are
    untouched, and no citation on this card was rewritten.
  - Known sibling gap, out of scope: `hooks/worktree-guard.sh:676-678` carries the identical
    exempt list, so once that guard leaves `log` mode a top-level markdown edit in a primary
    checkout will be refused there too. Its own card owns that decision; nothing here closes it.
- [ ] 5. **Judge, PR, handover** — model-switch checkpoint 3 asked; observability judge (Opus,
  high) on the implementation; `gh pr create`; after the GitHub merge, the primary checkout at
  `~/.claude` is on `main` and must pull before any session benefits (`git -C ~/.claude pull
  --ff-only` — another session owns that checkout, so the command is handed to Mark, not run).

## Verification

<Appended during review: pass/fail per area and open issues only.>
