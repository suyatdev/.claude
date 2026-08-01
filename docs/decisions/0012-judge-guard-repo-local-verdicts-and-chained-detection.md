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
  JSON payload parser — which carries the identical apostrophe trap. It stays inline: it is short
  and has never been the thing under edit when the trap fired, whereas the classifier was edited in
  nearly every round. Moving it too would be a drive-by change, which is its own task. Anyone
  editing that block still needs `shellcheck -x` first.
  **"Stable" was withdrawn from that justification.** An earlier revision of this paragraph called
  the parser *short, stable, and* untouched, and the middle word was doing work it had not earned:
  the parser had never been tested at all, and the next review round found it fail-open (below).
  Untested is not stable, and reasoning from "we never edit it" to "it is correct" is how the one
  component nobody was looking at became the one that was broken.

- **The payload parser failed OPEN, and that is the FOURTH fail-open found on a branch about
  failing closed.** Every test entered through a well-formed payload, so the parser producing
  `command_line` was itself unexercised — zero coverage, which is why three review rounds passed
  over it. Its `except ValueError: sys.exit(0)`, with `2>/dev/null` on the call, collapsed four
  distinct outcomes into one silent allow, all measured against a store holding a *fresh* verdict so
  a working hook would have exited 0: truncated JSON → 0, non-JSON text → 0, valid JSON of the wrong
  top-level shape (`.get` on a list raises) → 0, and an interpreter on `PATH` that fails → 0.

  **The defect was that a parse failure and a call with nothing to guard were indistinguishable.**
  So the parser now emits a sentinel: a verdict on line 1 once it has decided, command from line 2,
  guarded by `case "$parse_rc:$parse_ok"`. Status *and* shape, the same pair the classifier check
  settled on one round earlier — the third time in this branch that a check had to stop accepting
  the appearance of a working component. A top-level array or scalar is refused as malformed input
  rather than treated as a call with nothing to guard.

  **Superseded 2026-07-31 — the first version of this bullet justified itself with a false premise,
  and the premise had chosen the behaviour.** It read: *"valid JSON carrying no `command` string is
  a non-Bash tool call, and every Edit, Read and Write in the session arrives that way."* They do
  not. Enumerating every settings file on the machine found **one** registration —
  `~/.claude/settings.json`, `PreToolUse`, matcher **`Bash`** — so editor traffic goes to
  `phase-guard.sh` and never reaches this hook at all. Four tests were pinning `pass` for callers
  that do not exist, and they were pinning it *against* this branch's own fail-closed doctrine: if
  only Bash payloads arrive, then "valid JSON, no `command`" means "a Bash call I could not read."
  This is the same overclaim class the header carried one round earlier, this time inside the
  commentary of the fix for it — which is the argument for `docs/verify-before-claiming`
  (verification precedes the write-down, not just the claim), not merely for a correction here.

  **Decision (user, 2026-07-31): a Bash payload with no runnable command BLOCKS.** Reasoning given:
  this session is the only sender, so it always has a reason to issue a command and never a reason
  to issue an empty one. Implemented **keyed on `tool_name`, deliberately not on the registration**:

  | payload | outcome |
  |---|---|
  | any runnable command, **whatever `tool_name` says** | classify it |
  | `tool_name` = `Bash`, nothing runnable (absent / empty / all-space / **all-control** / non-string) | **block** (exit 4 → 2) |
  | any other named tool, nothing runnable | pass — no shell command to guard |
  | bad top-level type, or missing/non-string `tool_name` | **block** (exit 3 → 2) |

  **Corrected 2026-07-31 after observability-judge RUN 6, which measured the first version of this
  table as a regression.** That version keyed the SKIP on `tool_name`, and the code returned on it
  *before reading the command* — so a live `gh pr create` under any name but `Bash` passed
  unexamined (measured: `Shell`, lowercase `bash`, `BashOutput`, `mcp__shell__exec` all exit 0 with
  no verdict on file, where the pre-change hook exited 2). It was therefore **weaker than the
  version it replaced**, and weaker in exactly the wider-matcher future that keying on the payload
  was introduced to survive. The three pass-through tests could not catch it because all three
  carried no `command` field at all.

  The rule is now: **the command decides; `tool_name` only settles what an absent command means.**
  That keeps the property this decision wanted — correctness resting on the payload rather than on
  a setting in a different file that no test covers — without the coverage loss. `tool_name` is a
  required `PreToolUse` field and the one the matcher itself filters on (verified against the hook
  documentation before being relied on, rather than assumed — assuming is what produced this
  bullet's first version). The non-Bash rows are tested even though they cannot arrive today, so a
  future matcher change becomes a settings edit, not a machine-wide outage.

  Two smaller consequences. The post-parse `[ -n "$command_line" ] || exit 0` is now unreachable and
  has been **inverted into a fail-closed assertion** — if an edit upstream ever breaks the
  invariant, the result should be a block, not the fifth silent allow. And the test harness itself
  was wrong: five payload builders omitted `tool_name` entirely, so for five review rounds no test
  could tell a Bash call from an editor call. That gap is why the false premise survived so long —
  the tests agreed with it by construction.

- **The header's fail-closed claim was an overclaim and has been narrowed.** It read *"any inability
  to verify blocks"*, which states a coverage guarantee this hook has never made: the backtick and
  heredoc shapes are deliberately undetected, an empty payload passes, and a hanging classifier has
  no timeout. It now scopes the promise to the machinery — missing python, unreadable payload,
  unusable classifier, unreadable verdict store — and points here for the accepted exceptions. The
  claim was accurate about *intent* and false about *fact*, which is the more dangerous kind of
  documentation error: a reader audits the gate against the comment and stops looking.

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

  **Status is checked alongside shape**, after a second review round: a classifier can answer and
  *still* have failed. One that prints a well-formed `NO` and then exits non-zero or raises leaves
  `kind` holding a legal value, and a shape-only check passes it — gate silently disarmed again.
  Against today's classifier that is unreachable, but only because it happens to print its answer
  last: the classifier's shape protecting the hook rather than the hook protecting itself, which
  stops holding the moment the classifier is refactored. The guard is therefore
  `case "$classify_rc:$kind" in 0:PR|0:NO)`. Recorded because it is the second time in this branch
  that a check accepted the *appearance* of a working classifier.

  **Three failure modes are knowingly deferred, not closed:**
  - **A classifier that always answers `NO` and exits 0** — a stub, or a subtly wrong rewrite — is
    indistinguishable from a healthy one at this interface, and silently allows every
    `gh pr create`. No check on the *call* can catch it: the hook would need a canary, classifying
    a known-`PR` string and refusing to proceed if the answer came back `NO`. Enumerated here
    because it was briefly dropped from this list while its two siblings were closed, and an
    enumeration that quietly sheds its hardest member is worse than no enumeration.
  - **A classifier that hangs** blocks every Bash command indefinitely and silently. This ADR
    promises a "loud, self-describing halt"; that promise does not hold for this one shape. Closing
    it needs a timeout around the call, which is a larger change than the branch's remaining scope.
  - **First arming is untested under the real harness.** The installed hook at `~/.claude/hooks/`
    predates the extraction and has no `lib/` alongside it. Mitigating but not conclusive: `main`
    already carries the classifier, git swaps files atomically, and only the agent's Bash tool is
    gated — an operator's own terminal is unaffected.

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
    `rtk`) and therefore incomplete by construction. Measured 2026-07-31, all reaching the
    classifier on stdin as the hook feeds it: `sudo gh pr create` → `NO`, `xargs gh pr create` →
    `NO`, `env gh pr create` → `NO`, `timeout 60 gh pr create` → `NO`. `rtk` and `command` are on
    the list and correctly → `PR`.
  - **a path-qualified `gh`** — `/usr/bin/gh pr create` → `NO` (measured, same date). The command
    position holds `/usr/bin/gh`, not the bare token `gh`. This one is not a wrapper gap but a
    naming gap, and it is the cheapest of these to close (compare the path's basename) — left open
    only because closing one naming gap while `sudo`, `env` and `timeout` stay open buys no real
    coverage, and each closure widens the false-positive surface that quoting currently protects.

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
- **The gate checks that a verdict EXISTS, not what it SAYS.** Verified by reading the matcher (the
  `PYEOF` block in `judge-guard.sh`): it compares `stage == "implementation"`, `repo`, `branch` and
  `head_sha`, and reads no other field. A verdict recording `risk=high` with `execution=fail`
  therefore opens the gate exactly as a clean one does. Combined with the store being
  **agent-writable** — the judge writes it, and so can any session — this bounds what the hook can
  honestly claim: it enforces *that the judge ran at this exact HEAD*, and nothing about the
  judgment. Deliberate rather than an oversight: gating on verdict content would put a
  machine-blocking decision behind a rubric score an agent produces and can rewrite, and a
  wrongly-blocking gate is a worse failure than a guardrail that merely insists the judge ran. It is
  recorded because the *name* "judge-guard" implies the stronger property and nothing disclaims it.
- **A `python3` that pollutes stdout blocks every Bash command on the machine.** The parser's
  verdict is read positionally — line 1 — so a banner from `sitecustomize`, `PYTHONSTARTUP`, or a
  warning routed to stdout rather than stderr displaces the sentinel and the parse is refused.
  Refusing is correct (output that cannot be trusted must not be acted on), and the trigger is now
  pinned in the suite as `python that pollutes stdout -> block`. Named here because the cause sits
  entirely outside this repo while the effect is machine-wide, and because the message points at the
  payload — which is where a reader would look, and where nothing is wrong. Recovery is the route
  the other machine-wide blocks already name: unregister the hook in `settings.json`.
- **"Nothing runnable" meant whitespace only, so control characters were a fail-open.** The rule was
  implemented as `.strip()`, which removes whitespace and nothing else — NBSP and VT count, NUL, SOH
  and DEL do not. So a `Bash` payload whose command was pure control characters read as *runnable*,
  was classified, matched nothing, and was **allowed**: the same fail-open the row above exists to
  close, reached through the back door. The asymmetry was absurd once seen — a lone NUL blocked
  (it reached the parser-OK assertion, having been dropped by command substitution) while a NUL
  followed by two spaces passed. Found by the **second** RUN 6 judge, reproduced against HEAD before
  being accepted, and fixed by defining runnable as *at least one character that is neither
  whitespace nor a control character*. `isprintable()` draws exactly that line and keeps em-dash and
  CJK commands runnable; narrowing to ASCII would blind the guard to commands it must classify.
- **RETIRED 2026-07-31 — the CWD was on `sys.path`, so a file lying on the floor blocked the
  machine.** `python3 -c` and `python3 -` both prepend the caller's directory, so an ordinary
  `json.py` — a python project, a scratch dir, anywhere you happen to be standing — shadowed the
  stdlib module the parser imports and failed this hook closed on *every* Bash command, with a
  message blaming the payload. Found by observability-judge RUN 6 and reproduced before being
  believed: from such a directory, a bare `git status` exited 2. All three call sites now run under
  `-I` (parser, verdict matcher, classifier), which drops that directory and ignores `PYTHON*` in
  one token — so the `PYTHONIOENCODING=ascii` trigger recorded alongside it is retired by the same
  change. `-I` is probed once and dropped on interpreters older than 3.4 rather than assumed: the
  shadowing is a bad day, a hook that refuses to run at all is a worse one. The stdout-noise trigger
  above is **not** retired by this — it needs no `sys.path` entry and remains live.
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
- **Isolation costs ~2.8× on every Bash call: 52 ms → 147 ms.** Written down because it is a *global*
  cost paid by every command on the machine, not just by `gh pr create`, and a cost that is only
  visible with a stopwatch is one nobody will attribute to this hook six months from now. Found by
  observability-judge RUN 8 and re-measured independently before being recorded (judge: 51 → 145;
  re-measure: 52 → 147; 20–30 calls per arm). Two causes, measured separately rather than inferred:
  the `-I` probe at line 66 is an **extra Python process on every call** (`python3 -I -c ''`, ~30 ms),
  and `-I` roughly **doubles interpreter startup** here (`python3 -c pass` 15.4 ms → 29.8 ms; the
  classifier 21.0 ms → 48.6 ms). At roughly 300 Bash calls in a session that is about +30 seconds.
  **Accepted, not dismissed.** The alternative is giving up `-I`, and `-I` is what retired the
  `sys.path`-shadowing defect two bullets up — a defect that blocked *every* Bash command machine-wide.
  A slower hook is a worse day than a hook that wedges the machine is a worse day still; correctness
  wins. The obvious relief is deferred rather than taken here: the probe asks "does this interpreter
  accept `-I`", whose answer is **machine-static**, so it can be cached and the extra process dropped.
  Not done in this change because it introduces a cache-invalidation question (interpreter upgrades)
  that deserves its own decision, and this branch was already closing a fail-open.
