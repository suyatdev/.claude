# ADR 0012 — judge-guard reads the judged repo's verdict store, and guards chained invocations

**Status:** Accepted (2026-07-25)

## Context

`judge-guard.sh` (Tier 1, added by ADR-0001) blocks `gh pr create` until a fresh
implementation-stage observability-judge verdict matches the current repo+branch+HEAD. Two
defects meant it had never actually enforced that outside the `~/.claude` repo itself.

**1. Verdict-store path mismatch.** `agents/observability-judge.md` instructs the judge to
"Write ONLY under `coding-memory/observability-judge/`" — a *repo-relative* path, so verdicts
land in the judged repo's own tree. The guard read a hardcoded
`$HOME/.claude/coding-memory/observability-judge/verdicts.jsonl`. Those two paths coincide only
when the judged repo *is* `~/.claude`, which is why 39 of the 40 stored verdicts were `.claude`
entries and the gate appeared to work. In any other repo the gate was **unsatisfiable**: no
verdict could ever match, no matter how many the judge correctly recorded. vibe-scape had 13
verdicts in its own store and zero in the store the guard consulted.

**2. Chained invocations bypassed the gate.** Classification stripped a leading `rtk` wrapper and
leading `NAME=VALUE` assignments, then matched `gh pr create` at position 0 only. A chained
`git push -u origin br && gh pr create` classified as "not a gh pr create" and required no
verdict at all. This was a *documented and asserted* gap, not an oversight — the script's comment
called it "a momentum guardrail, not a security boundary, the same tradeoff git-guard makes", and
`hooks/judge-guard.test.sh` pinned it with `run_case "chained && (documented gap) -> ignore" 0`.

The two defects masked each other, producing a confusing signal that was escalated to the user
twice as a suspected settings-shadowing problem. vibe-scape PR #23 ran `gh pr create` standalone
and was blocked (defect 1 biting), so it needed a logged `JUDGE_EXEMPT`. PR #25 chained push and
create in one Bash call and sailed through (defect 2), so defect 1 never even came into play. The
inconsistency looked like `.claude/settings.json`'s `PreToolUse` array shadowing the global one.
It was not: both hooks were wired correctly the whole time.

## Options weighed

**Defect 1 — where to read verdicts from:**

1. **Repo-local store only (chosen)** — resolve `<repo-root>/coding-memory/observability-judge/verdicts.jsonl`.
   Single source of truth, matching the judge's own mandate.
2. **Dual-check repo-local then `$HOME/.claude`** — tolerant of a judge that writes to the wrong
   place, and preserves the one stray `Snatch-Bracket` entry in the home store. Rejected: a
   fail-closed safety gate with two places a verdict may live is harder to reason about, and it
   would silently paper over a mis-dispatched judge rather than surfacing it. The stray entry is
   stale anyway (old HEAD), so nothing enforceable is lost.
3. **Change the judge to write to `$HOME`** — rejected: verdicts are project history and belong in
   the project's tree, where they are committed and reviewable alongside the code they judge.

**Defect 2 — whether to close the chained gap:**

1. **Close it (chosen)** — segment the command line on shell control operators and test every
   segment.
2. **Leave it documented** — rejected by the user once PR #25 demonstrated the gap is load-bearing
   in practice, not theoretical: push-then-create as one chained call is the *normal* shape of the
   command this gate exists to catch, so the gate was off in the common case rather than the
   exotic one.

## Decision

The verdict store is resolved from `git rev-parse --show-toplevel` (repo root, not `$PWD`, so the
gate behaves identically from any subdirectory), with `JUDGE_VERDICTS_FILE` retained as a test
override. When the store is absent the error names the exact path expected, so a
mis-dispatched judge is diagnosable at a glance instead of silently unsatisfiable.

Classification tokenizes with `shlex.shlex(posix=True, punctuation_chars=True)` and splits on
control-operator tokens, then applies the existing per-command logic (strip `rtk`, strip leading
env-assignments, match `gh pr create`) to each segment. `punctuation_chars=True` is what makes
unspaced operators visible — `push&&gh` lexes as `push`, `&&`, `gh`, which a whitespace split
cannot see. `JUDGE_EXEMPT` is captured from the *matching* segment, mirroring bash, where such a
prefix binds only to its own command.

A **newline is also a command separator** in bash, exactly as `;` is, but `shlex` counts it as
ordinary whitespace — so `git push` and `gh pr create` on two lines of a single Bash call lexed into
one segment and no command ever reached a segment's position 0. This was missed by the first pass at
this ADR and caught by the observability judge; it is the *same* defect class as the `&&` gap, and a
multi-line command string is a routine shape rather than an exotic one, so the gate was still off in
a common case. Newlines are therefore translated to `;` **before** lexing. Translating first, rather
than splitting the raw input per line, is the deliberate choice: `shlex`'s quoting rules then keep the
substituted character inside a quoted string as part of that token, whereas a per-line split would
raise on any quote spanning lines and **fail open** — strictly worse than the bug it fixed.

The false-positive protection is unchanged and still verified: quoted text survives as a single
token, so `gh pr create` inside a commit message or an `echo` argument can never occupy a
segment's command position — including a commit message whose quoted body spans several lines.

## Consequences

- **The gate starts enforcing for the first time in every repo except `~/.claude`.** Expect
  `gh pr create` to begin blocking where it previously did not. That is the intended behavior, but
  it is a real workflow change: a PR now genuinely requires a fresh implementation-stage verdict
  at the exact HEAD being shipped, or a logged `JUDGE_EXEMPT`.
- **A behavioral assertion was inverted, not merely added.** `hooks/judge-guard.test.sh` previously
  asserted the chained case passes; it now asserts it blocks. Anyone reading that test's history
  should understand the reversal was deliberate and user-authorized.
- **`$HOME/.claude`'s 40 accumulated verdicts remain valid for the `.claude` repo only**, since for
  that repo the repo-local path and the old hardcoded path are the same file. The single
  `Snatch-Bracket` entry there becomes unreachable; it was already stale.
- **Comments inside the classifier must not contain apostrophes.** The python program is embedded in
  a single-quoted shell string, so one apostrophe terminates it and turns the whole hook into a
  syntax error. This was hit while writing the newline fix; `shellcheck -x` catches it (SC1011)
  where the test suite alone would only show a wall of unrelated failures. A note now sits in the
  block.
- **Segment matching has a long tail, and this gate is a momentum guardrail — not a boundary.**
  Round 1 of review found the plain-newline shape; round 2 found four more. All measured against
  this ADR's HEAD, not assumed:

  | shape | gate |
  |---|---|
  | `git push && \`⏎`gh pr create` | **passes — bypass** (the `\`+newline survives the newline→`;` rewrite as `;gh`) |
  | `gh -R owner/repo pr create` | **passes — bypass** (a valid, documented `gh` form; `pr` is no longer token 1) |
  | `` `gh pr create` `` | **passes — bypass** (legacy substitution; `$(...)` blocks) |
  | `time gh pr create`, `eval gh pr create` | **passes — bypass** (keyword/builtin prefix) |
  | `$(gh pr create)`, `{ git push; gh pr create; }` | blocks |

  Each round finding another shape is evidence about the *approach*, not about any one patch:
  matching shell command shapes by token position cannot be made exhaustive without reimplementing
  bash's grammar. These are recorded rather than patched so nobody mistakes the gate for a security
  boundary — a determined bypass is always one keystroke away, and `JUDGE_EXEMPT=<reason>` is the
  honest, logged escape hatch. Closing the `\`+newline shape is the most defensible follow-up: it is
  a line *continuation*, so semantically it should join the lines and hit the already-handled `&&`
  path.
- **`JUDGE_VERDICTS_FILE` cannot clear the gate for a real `gh pr create`, only for tests.** The hook
  runs as its own process and is handed the command *string*; a `VAR=x gh pr create` prefix is part
  of that string and never reaches the hook's own environment. `JUDGE_EXEMPT` works because the hook
  parses it *out of the command line*; `JUDGE_VERDICTS_FILE` is read from `$HOME`-inherited env and
  so is only settable by the test harness. Prior PR notes claiming a worktree PR was "cleared via
  `JUDGE_VERDICTS_FILE`" are inaccurate — verify before reusing that recipe.
- **This fix could not satisfy the gate it fixes.** The installed hook is the *primary* checkout's
  copy, which predates this change and reads only `$HOME/.claude`'s store, so the round-2 verdict
  sitting in this worktree's ledger was invisible to it. PR #32 was therefore opened under a logged
  `JUDGE_EXEMPT` naming exactly that bootstrap. The general rule this exposes: **a hook fix cannot
  be gated by the hook it fixes until the primary checkout pulls it.**
- **The same chained-command gap remains open in `git-guard.sh` and `merge-guard.sh`**, which make
  the identical tradeoff. Deliberately left as a separate task rather than a drive-by fix —
  `merge-guard.sh` in particular gates `gh pr merge`, so changing it needs its own reproduction and
  its own decision.
- **The suspected `PreToolUse` settings-shadowing problem is closed as a non-issue.** Both the
  project and global hook arrays were wired correctly; the symptom was entirely these two defects.
  vibe-scape's `CODING_MEMORY.md` carried this as an ESCALATED unresolved infra finding and is
  updated to record the real root cause.
