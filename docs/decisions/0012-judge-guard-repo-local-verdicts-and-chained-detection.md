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
- **The classifier now lives in `hooks/lib/classify-pr-command.py`, and the apostrophe hazard is
  gone by construction.** While the python was embedded in a single-quoted shell string, one
  apostrophe anywhere in it — including in a comment — terminated the quote and turned the whole
  hook into a syntax error. That fired **three times**, twice inside the very comment block warning
  against it, costing roughly 24 spurious test failures each time. The warning comment was a
  *disproven control*: it sat exactly where the mistake kept being made and did not prevent it.
  Extraction removes the failure mode rather than documenting it. The related operational lesson
  stands regardless: **run `shellcheck -x` first whenever the suite goes wide**, since it names the
  cause in one line (SC1011) where the suite shows only a wall of unrelated failures.
  The move was behaviour-preserving and verified as such: the python transferred verbatim (shell
  single-quotes are literal, so no escape sequence changed), and 52 command shapes fed through the
  old inline classifier and the new module produced byte-identical output, 0 mismatches. A
  side-benefit was the actual goal — `classify()` is importable, so bypass shapes get unit tests
  instead of ad-hoc probing through the hook.
  **Scope caveat, so this is not read as more than it is:** the hazard is gone from the *classifier*,
  not from the hook. `judge-guard.sh` still embeds one inline single-quoted python program — the
  ~11-line JSON payload parser — which carries the identical apostrophe trap. It was left alone
  deliberately: it is short, stable, and has never been the thing under edit when the trap fired,
  whereas the classifier was edited in nearly every round. Moving it too would be a drive-by change,
  which is its own task. Anyone editing that block still needs `shellcheck -x` first.

- **An UNUSABLE classifier fails CLOSED, and that blocks every Bash command.** Extraction created a
  failure mode that could not exist for an inline string: the file can be absent, via a partial
  checkout or a hook copied on its own — which has happened in this repo. Measured, not assumed: an
  absent classifier produced empty output, leaving `kind` empty, and the hook exited 0. The gate
  looked armed and silently passed every `gh pr create`, which is precisely the defect this ADR
  exists to remove. It now blocks and names the path, matching the missing-python branch beside it
  and the same single-source-of-truth stance taken for the verdict store.

  **Corrected after review, and worth recording as a correction rather than a clean result:** the
  first fix checked `[ -f "$CLASSIFIER" ]` — the file's *existence*, not whether it worked. Four
  present-but-unusable installs still exited 0 in silence, each re-measured before being believed:
  an empty file, a syntax error, a truncated file, and an unreadable one (`chmod 000`). So the
  branch whose whole subject is failing closed shipped a check that failed open on four of six
  shapes. The truncated case is the sharpest, because a partial checkout — the story cited two
  paragraphs above as the motivation — produces a truncated file at least as readily as a missing
  one. `2>/dev/null` on the classifier call swallows every interpreter error, so all four routes
  converge on the same empty `kind` the missing-file branch was added to catch.
  The hook now validates the classifier's **output** instead: `kind` is only ever `PR` or `NO`, so
  anything else means it did not run, whatever the reason. That covers all six shapes including the
  missing file, and it is *smaller* than the existence check it replaced — the complete fix removed
  a special case rather than adding one, which is the same principle applied to the bypass shapes
  below.

  The cost is deliberate: with no usable classifier, nothing can distinguish a PR command from any
  other, so *all* Bash commands block until the install is repaired. That is the correct trade here
  — a loud, self-describing halt is recoverable in seconds, whereas a silently dead gate ships
  unjudged code indefinitely and is invisible by definition. It also mirrors the precedent already
  set one branch above it, where a missing `python3` blocks everything for the same reason.
  **The blast radius is machine-wide**, since the hook is registered globally: one unusable file
  freezes every Bash call in every repo, for every concurrent agent. That makes the error message
  load-bearing rather than cosmetic — the operator cannot run `git checkout` or any other shell
  command to recover, so the message names the two routes that survive the block: repair via the
  Write tool, or unregister the hook in `settings.json`. A `JUDGE_GUARD_REPAIR`-style env escape was
  considered and rejected: it adds a bypass to a gate whose value is being un-bypassable, and the
  hook receives the command as a *string* in a separate process, so a `VAR=x` prefix would not
  reach its environment anyway — the same reason `JUDGE_VERDICTS_FILE` cannot clear the gate for a
  real `gh pr create`.
- **Four further bypass shapes were found by measurement and closed.** Round 1 of review found the
  plain-newline shape; round 2 surfaced four more, and re-measuring the hook directly corrected two
  of round 2's claims (`{ …; }` already blocked; `time`/`eval` were missed). All now block, and the
  fixes were chosen to *remove* special cases rather than add matchers:

  | shape | before | how it is handled |
  |---|---|---|
  | `git push && \`⏎`gh pr create` | bypass | the `\`+newline pair is deleted **before** the newline→`;` rewrite — it is a line *continuation*, so joining the lines routes it into the existing `&&` path |
  | `gh -R owner/repo pr create`, `--repo` | bypass | `gh` must hold the command position, but `pr create` is matched as an **adjacent pair** anywhere after it, so global flags are legal |
  | `time`/`eval`/`command`/`builtin`/`exec`/`nohup` prefix | bypass | added to the wrapper list already stripping `rtk`, in a loop so they stack |
  | `{ gh pr create; }` | bypass | `{`/`}` added to the punctuation set — a brace group opens a command context as a subshell does, but `{` lexed as an ordinary token and took the command slot |
  | `$(gh pr create)`, `( gh pr create )` | blocked | unchanged |

- **Backticks are deliberately left open, after being closed and reverted.** Translating `` ` `` to
  `;` did catch `` `gh pr create` ``. But `shlex` cannot see heredocs, so the same translation made
  any heredoc body containing a backticked `gh pr create` fail **closed** — and writing exactly that
  text is routine here (`git commit -m "$(cat <<'MSG'` with an ADR table in the body). That trades a
  rare false negative for a common false positive which blocks legitimate work, and `JUDGE_EXEMPT`
  cannot reach the offending segment. Wrong direction for a momentum guardrail, so it was reverted
  and the shape is documented instead.

- **The gate is NOT exhaustive, and the count of known gaps is not closed.** Matching shell command
  shapes by token position cannot be made complete without reimplementing bash's grammar. Known open
  shapes, each measured:
  - `PR_URL="$(gh pr create)"` — **inside double quotes the whole substitution is one token.** This
    is the same property that stops a commit message from tripping the gate: quoting is
    simultaneously the false-positive *protection* and the false-negative *mechanism*. Closing it
    means reading inside quoted tokens, which trades away that protection — an architecture-level
    tradeoff, not a patch.
  - `` `gh pr create` `` — see the backtick entry above.
  - `eval "gh pr create"` — one quoted token, so it cannot reach a command position.
  - a shell function or alias that reaches `gh` — invisible here.
  - the wrapper list is a **denylist** (`time`, `eval`, `command`, `builtin`, `exec`, `nohup`,
    `rtk`) and therefore incomplete by construction; `env`, `timeout`, and loop keywords are not in
    it.

  **This gate stays a momentum guardrail, not a security boundary** — a determined bypass is always
  one keystroke away, and `JUDGE_EXEMPT=<reason>` is the honest, logged escape hatch.

- **Every shape here was found by *running* the hook, never by reading it — including the ones that
  corrected a reviewer.** Review round 2 reported `{ gh pr create; }` as a bypass; a later
  re-measurement wrongly overturned it by testing `{ git push; gh pr create; }`, a different string
  that blocks for an unrelated reason (`git` takes the command slot, then `;` opens a fresh
  segment). Round 3 caught the bad overturn. **A wrong correction in an audit trail is worse than
  the original wrong claim, because it reads as settled** — both strings are now pinned in the suite
  so the distinction cannot be lost again. The deeper lesson: three false-positive probes that all
  exercise *quoting* are one sample, not three.
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
