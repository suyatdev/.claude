---
phase: review
model_tier: high
branch: fix/fix-l1
---

# git-guard / doc-guard fail open on any chained command

## Spec

### Problem

`hooks/git-guard.sh` and `hooks/doc-guard.sh` decide whether a Bash command is a `git commit` (or a
`git push`) by matching a regex **anchored to the start of the command string**:

```bash
commit_re='^git[[:space:]]+commit([[:space:]]|$)'
```

A command whose first word is anything else — `git add -- x && git commit -- y`, the shape this repo
uses constantly — never matches, so the guard body **does not execute at all**. This is a fail-open:
the guard reports success without having evaluated anything.

Consequence, observed on `main`: commit `6046565` staged `docs/features/` onto `main`, which
git-guard's allowlist (`CODING_MEMORY.md` and `coding-memory/*` only) nominally forbids. It landed
because the guard fail-opened, not because the allowlist permitted it. Recent `docs(*)` commits on
`main` slipped the same way, so the guard's stated policy and its actual behaviour have diverged
silently.

`hooks/judge-guard.sh` already solved this exact class by lexing the command into shell segments via
`hooks/lib/classify-pr-command.py`. Its test suite pins the shape at
`hooks/lib/classify-pr-command.test.py:31` — *"chained && — the shape that let a PR ship unjudged"*.
The remedy is therefore known-good and already in the repo; L1 extends it to the other two guards
rather than inventing a third parser.

### Scope ruling (user, 2026-08-03)

Fix the **two live** guards. **Document** the third (`checkpoint-before-modify.sh`) rather than
change it — see Non-goals.

### Behaviour required

Given a raw Bash command string, each guard must reach its decision if **any shell segment** runs the
command it guards, not merely the first.

```gherkin
Scenario: chained commit on main is blocked
  Given the current branch is main
  And a source file is staged
  When the Bash command is "git add -- src/x.sh && git commit -m msg"
  Then git-guard exits 2

Scenario: chained force push is blocked
  When the Bash command is "git fetch && git push --force"
  Then git-guard exits 2

Scenario: a force flag in a different segment does not trip the push guard
  When the Bash command is "git push && echo --force"
  Then git-guard exits 0

Scenario: a commit mentioned inside a quoted message is not a commit
  When the Bash command is "echo 'run git commit next'"
  Then git-guard exits 0

Scenario: the wrapper form still counts
  When the Bash command is "rtk git commit -m msg"
  Then git-guard evaluates the commit guard
```

### Contract — `hooks/lib/classify-git-command.py`

Reads the raw command on stdin. Writes zero or more fact tokens, one per line, to stdout; exit 0.

| Token | Emitted when some segment… |
|---|---|
| `COMMIT` | runs `git commit` |
| `PUSH` | runs `git push` |
| `PUSH_FORCE` | runs `git push` carrying bare `--force` / `-f` **in that same segment** |
| `PUSH_LEASE` | runs `git push` carrying `--force-with-lease` **in that same segment** |

Segmentation, wrapper stripping (`rtk`, `time`, `eval`, `command`, `builtin`, `exec`, `nohup`) and
env-assignment skipping are shared with the PR classifier via `hooks/lib/shell_segments.py`, so both
classifiers inherit one lexer and one set of accepted limits.

### Allowlist widening

git-guard's `main` allowlist becomes `CODING_MEMORY.md`, `coding-memory/*`, **and `docs/**`**. Without
this, correctly evaluating the guard would start blocking the documentation workflow this repo runs
on `main` every day — the fix would read as a regression. `doc-guard.sh:11` already treats `docs/` as
documentation, so this aligns the two guards.

### Accepted limits (inherited from ADR 0012, unchanged)

`eval "quoted string"`, `env`/`timeout` wrappers, backticked substitutions, heredoc bodies and
variable indirection remain invisible to lexing. These are momentum guardrails, not security
boundaries; closing them belongs to the permission system.

### Non-goals

- **`hooks/checkpoint-before-modify.sh` is not modified.** Its leading-command match is an
  *allowlist*, so the same shape has the opposite effect — widening it would make it more permissive,
  not less. `checkpoint-before-modify.sh:34-36` already records the limit as deliberate. It is also
  **not registered in `settings.json`**, so it currently runs never; that, not the quirk, is the
  finding worth writing down.
- The five unregistered hooks are a separate branch. L1 only corrects the one false claim in
  `rules/gates.md` that it touches.

## Tasks

- [x] Task 1 — Add `hooks/git-guard.test.sh` and `hooks/doc-guard.test.sh` pinning the chained-command
      fail-open as FAILING tests (no suites exist for either hook today).
  - Reproduced before any fix: 11 failing cases in git-guard, 6 in doc-guard.
  - Two defects the spec had not predicted, both found by writing the cases out:
    `git push --force && echo --force-with-lease` was **allowed** (the lease check was a substring
    search over the whole command, so a lease anywhere excused a bare force anywhere), and
    `git push && echo --force` was **blocked** for the mirror-image reason.
- [x] Task 2 — Extract the segment lexer from `classify-pr-command.py` into `hooks/lib/shell_segments.py`;
      `classify-pr-command.test.py` must stay green unchanged as the regression baseline.
  - Baseline held: 51/51 green with the test file untouched.
  - Wrapper-stripping runs *before* env-assignment skipping, which is the pre-existing order and is
    pinned by `classify-pr-command.test.py:95`. Preserved exactly rather than "corrected", so
    `FOO=bar rtk gh …` stays unrecognised — changing it is a separate decision with its own test.
- [x] Task 3 — Add `hooks/lib/classify-git-command.py` + its unit test, implementing the contract above.
  - **Spec addition made during implementation:** a fifth fact token, `COMMIT_ALL`, was required.
    doc-guard's `-a`/`--all`/`-am` detection had the same whole-string defect as the commit match,
    so leaving it out would have fixed one half of that hook and left the other broken. Flagged to
    the user rather than folded in silently.
  - Accepted, pinned at `classify-git-command.test.py`: a commit whose message is literally `-a` is
    read as `--all`. Option values are not tracked, because git accepts any unambiguous prefix of a
    long option (`--amen` == `--amend`) and modelling that grammar is unbounded. The error direction
    is safe — doc-guard inspects more, never less.
- [x] Task 4 — Route `git-guard.sh` (commit guard and push guard) through the classifier.
  - `PUSH_FORCE` is emitted only when a segment force-pushes *and that same segment has no lease*,
    so the fact is self-contained and a lease elsewhere cannot excuse it.
  - Fails closed if the classifier will not run, matching the hook's existing no-python3 behaviour.
- [x] Task 5 — Route `doc-guard.sh` through the classifier.
  - Fails **open** on the same condition — this hook's stated philosophy, unchanged.
  - The `Doc-Exempt:` bypass now scans the raw command rather than the rtk-stripped copy; the
    trailer is deliberately matched anywhere in the string, so behaviour is unchanged.
- [x] Task 6 — Widen the git-guard `main` allowlist to `docs/**`.
- [x] Task 7 — Update `rules/gates.md`: record the chained-command limit for git-guard/doc-guard as now
      closed, note `checkpoint-before-modify.sh` and its dormancy, and correct the false
      "Enforced by `hooks/phase-guard.sh` (Tier 1)" claim at line 5.
  - The correction is larger than a wording fix: **five of the 17 scripts in `hooks/` are not
    registered in `settings.json` at all** — `phase-guard.sh`, `checkpoint-before-modify.sh`,
    `require-project-standards.sh`, `scan-invisible-unicode.sh`, `scan-secrets.sh`. Wiring them up
    is out of scope here and is recorded as open work.
- [x] Task 8 — Run every hook test suite; confirm all green.

## Verification

All nine suites green — 436 assertions, 0 failures:

| Suite | Result |
|---|---|
| `hooks/git-guard.test.sh` | 33 passed (**new**; 11 of these failed before the fix) |
| `hooks/doc-guard.test.sh` | 16 passed (**new**; 6 failed before the fix) |
| `hooks/lib/classify-git-command.test.py` | 47 passed (**new**) |
| `hooks/lib/classify-pr-command.test.py` | 51 passed — unchanged file, the extraction's regression baseline |
| `hooks/judge-guard.test.sh` | 101 passed — the direct consumer of the refactored classifier |
| `hooks/phase-guard.test.sh` | 130 passed |
| `hooks/pane-dispatch-guard.test.sh` | 34 passed |
| `hooks/context-handoff-watch.test.sh` | 19 passed |
| `hooks/memsearch-nudge.test.sh` | 5 passed |

Dogfooded live: both commits on this branch were made with a chained
`git add -- … && git commit …`, which the fixed guards evaluated (rather than skipped) and allowed —
feature branch, documentation staged. The pre-fix code would not have evaluated either one.

### Observability judge, round 1 — `risk=low confidence=high` at `4335eb6`

Verdict: `coding-memory/observability-judge/2026-08-03-fix-fix-l1.md`. It re-derived the claims
independently rather than reading the summary: ran both hook versions side by side against the
merge-base, re-ran all nine suites, and fuzzed 24,016 command strings through the old and new
`classify-pr-command.classify()` with zero divergences. Four findings, all acted on:

1. **The fail-closed cliff was untested.** `git-guard` runs on every Bash call and now refuses
   everything if the classifier will not load — correct direction, but the two hooks' *opposite*
   fail directions lived only in comments. Both are now pinned, git-guard's with an `ls -la` case
   proving the blast radius, doc-guard's with a control proving the pass is the fail-open path and
   not an empty fixture.
2. **A dangling pointer this change introduced** — `gates.md` cited ADR 0012 for the lexer's limits
   while the lexer had moved. Resolved by ADR 0013, which amends 0012 rather than editing it.
3. **`docs/*` trusted a directory, not a file type.** Narrowed to `docs/*.md`. `*` spans `/` in a
   case pattern, so any depth is still covered while `docs/tool.sh` — and `docs/notes.md.sh` — are
   not. Free today: all 34 files under `docs/` are markdown.
4. **`gates.md` had grown 21%** for a bug fix, in a file that loads every turn. Trimmed to +10%
   over `main` (7,922 → 8,725 bytes), keeping the two genuinely new facts and dropping the history
   already in `CODING_MEMORY.md`.

Its fifth point — that the dormant-hooks finding must not evaporate — was already satisfied by
`1da6ac9`.

Open issues: none blocking. Out of scope and recorded for a later branch — five hook scripts are not
registered in `settings.json` and never run, `scan-secrets.sh` among them.
