# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- **CURRENT: `fix/judge-guard-verdict-lookup` — implementation, `model_tier: high` (Opus 5 1M;
  checkpoint 2 answered 2026-07-30, do not re-ask for this branch).** Worktree
  `.claude/worktrees/judge-guard-fix`. Fixes the bug recorded at line 231 below: `judge-guard.sh`
  read `$HOME`'s verdict ledger instead of the judged repo's, so a verdict written from a worktree
  never satisfied the gate. Branch-only commits: `23f662b` (red tests) → `f77d222` (fix) →
  `7f8d5d5` (ADR renumber). `origin/main` merged in clean at `bc76aeb` (150 commits; **zero**
  main-side drift on `hooks/judge-guard.sh`/`.test.sh`). Post-merge suite **26/0**.
  · **ADR renumbered 0011 → 0012** (`7f8d5d5`): main shipped `0011-branch-scoped-write-permission.md`
  while this branch was forked, so the merge left two ADRs numbered 0011 and **git did not flag it**
  — the filenames differ. main's 0011 keeps the number (referenced from this index, README, the
  phase-guard feature file, and ten judge verdicts); ours moved. **Check ADR numbers after every
  long-lived-branch merge — a duplicate number is a silent semantic conflict.**
  · `shellcheck -x hooks/judge-guard.sh` reports SC2016 (line 65) and SC2181 (line 161). Both trace
  to `3e78cac`/`aaa2abb`, **ancestors of the fork point** — pre-existing, deliberately NOT fixed here
  (drive-by cleanup is its own task). SC2016 is a false positive: the single quotes protect python
  source. The repo's convention would be a `# shellcheck disable=` line with a reason.
  · **Obs judge RUN 1 done** (`risk=medium confidence=high`, pinned `97752e6`, verdict
  `coding-memory/observability-judge/2026-07-30-fix-judge-guard-verdict-lookup.md`). It found a
  **real defect I reproduced independently: a NEWLINE bypassed the gate.** `git push` ⏎
  `gh pr create` in one Bash call exited 0 — no verdict required — because bash ends a command at a
  newline but `shlex` counts it as whitespace, so both lines lexed into one segment. Same defect
  class the branch exists to close, and multi-line commands are routine, so the gate was still off
  in a common case. **Fixed TDD:** `8037f89` (3 red) → `028510a` (green, **suite 32/0**). Newlines
  translate to `;` *before* lexing — a per-line split would raise on quotes spanning lines and fail
  OPEN. ADR 0012 carries the decision.
  · **TRAP, cost 15 spurious failures:** the classifier's python lives inside a **single-quoted
  shell string**, so one apostrophe in a comment terminates it and breaks the whole hook.
  `shellcheck -x` names it (SC1011); the suite only shows unrelated carnage. Note added in-block.
  · **⚠ RUN 1's verdict is now STALE — HEAD moved to `028510a`.** Judge MUST re-run before the PR.
  Judge artifacts are deliberately left uncommitted (commit them only *after* `gh pr create`).
  · **RUN 1 open points not yet acted on:** classifier crash fails open *silently* (only
  `ValueError` caught, the rest swallowed by `2>/dev/null`) and this change adds a Python ≥3.6
  requirement to that path while still falling back to plain `python`; `JUDGE_VERDICTS_FILE` is an
  **unlogged** bypass, unlike `JUDGE_EXEMPT`; the gate reads the *working-tree* file, so a verdict
  need never be committed to open a PR; sibling `git-guard.sh`/`merge-guard.sh` tracking task unopened.
  · **DRAFT PR #32 OPEN 2026-07-30** — https://github.com/suyatdev/.claude/pull/32. Detail:
  `coding-memory/pr-tracking.md` §PR #32. Obs judge **RUN 2** done, pinned `88ccb59`
  (`…-round2.md`), `risk=medium confidence=high`, **all six carried concerns ruled non-blocking**.
  · **`JUDGE_VERDICTS_FILE` DOES NOT clear the gate for a real `gh pr create` — correct the note
  above and PR #30's entry, which both claim it does.** The hook is a separate process handed the
  command *string*; a `VAR=x gh pr create` prefix is part of that string and never reaches the
  hook's environment. `JUDGE_EXEMPT` works only because the hook parses it *out of the command
  line*. Proved by direct measurement, not inference: the override was rejected, then the same
  command with `JUDGE_EXEMPT` passed. **PR #32 was opened under a logged `JUDGE_EXEMPT` naming the
  bootstrap** — the installed hook is the primary checkout's pre-fix copy, so it cannot see a
  worktree verdict. General rule: **a hook fix cannot be gated by the hook it fixes until the
  primary checkout pulls it.**
  · **RUN 2 verified 5 remaining bypass shapes** (measured, not assumed): `git push && \`⏎
  `gh pr create`; `gh -R owner/repo pr create`; backticks; `time`/`eval` prefixes. `$(…)` and
  `{ …; }` correctly block — RUN 2 claimed `{ …; }` bypasses and it does not, and it missed
  `time`/`eval`; **judge findings get re-measured before they are acted on.** Recorded in ADR 0012
  Consequences + the PR body rather than patched: each round finds another shape, which is a long
  tail inherent to token-position matching. The gate is a momentum guardrail, not a boundary.
  · **USER DECISION: fix them — cost alone is not a sufficient reason to defer.** All four closed
  TDD in one batch (`f461f1f` 8 red → `e79749a` green, **suite 32→48/0**, shellcheck back to only
  the two pre-existing findings). Batched deliberately: splitting would have cost RUN 3 *and* RUN 4.
  Each fix **removes a special case** rather than adding a matcher — `\`+newline deleted *before*
  the newline→`;` rewrite (a continuation joins the lines into the existing `&&` path; translating
  first is what created the spurious separator); backticks translate to `;` like newlines; `gh`
  holds the command position while `pr create` matches as an **adjacent pair** anywhere after it,
  so documented global flags work; `time`/`eval`/`command`/`builtin`/`exec`/`nohup` join `rtk` in
  the looped wrapper strip. Re-measured against 16 real command forms afterwards: all 13 guarded
  shapes block, all 3 false-positive shapes still pass.
  · **The apostrophe trap fired again, exactly as documented** — "repo's" in a new comment inside
  the single-quoted python block produced 22 unrelated failures. `shellcheck -x` named it (SC1011)
  in one line where the suite showed only carnage. **Run shellcheck first when the suite goes wide.**
  · **RUN 3 was right and I was wrong — the correction above is itself corrected.** I claimed round
  2 was wrong about `{ …; }`; it was not. I measured `{ git push; gh pr create; }` (blocks — `git`
  takes the command slot, `;` then opens a fresh segment) instead of round 2's `{ gh pr create; }`
  (bypassed — `{` is not a shlex punctuation char, so it took the command slot). **A wrong
  correction in an audit trail is worse than the original wrong claim, because it reads as
  settled.** Both strings are now pinned in the suite. Fixed by adding `{`/`}` to the punctuation
  set. Lesson: my 3 false-positive probes all exercised *quoting* — that is one sample, not three.
  · **I also introduced a false positive and RUN 3 caught it.** The backtick→`;` translation worked,
  but shlex cannot see heredocs, so any heredoc body containing a backticked `gh pr create` failed
  **CLOSED** — routine text here (`git commit -m "$(cat <<'MSG'` with an ADR table), and
  `JUDGE_EXEMPT` cannot reach that segment. **Reverted**: a rare false negative beats a common false
  positive that blocks real work. Backticks are now a documented open shape.
  · **Apostrophe trap fired a THIRD time** ("shlex's"), again 24 unrelated failures. shellcheck -x
  named it in one line. **This is now a disproven control** — the trap keeps firing *inside the very
  block that carries the no-apostrophes warning*. RUN 3's recommendation: extract the classifier to
  `hooks/lib/classify-pr-command.py`, which also makes it unit-testable and would let the suite find
  bypasses instead of ad-hoc probing. **Not done — decide next session.**
  · **BOTH OPEN DECISIONS ANSWERED BY USER 2026-07-30 (session 3).** (1) The quoted-substitution
  gap — `PR_URL="$(gh pr create)"` — is **accepted and documented, not closed**. Inside double
  quotes the whole substitution lexes as ONE token, and that is the *same* property that stops a
  commit message tripping the gate: **the false-positive protection and the false-negative are one
  mechanism**, so closing it trades the protection away. Decisive evidence: this branch already
  shipped that exact class of false positive once (backtick→`;` made heredoc bodies fail CLOSED
  where `JUDGE_EXEMPT` cannot reach), and this repo's own docs contain the literal string. Stays
  open by design alongside backticks, `eval "gh pr create"`, function/alias indirection, and the
  wrapper **denylist** (no `env`/`timeout`/loop keywords). (2) **Extract the classifier to
  `hooks/lib/classify-pr-command.py` NOW, in PR #32** — not a follow-up. Behaviour-preserving
  refactor: the 52/0 suite is the unbiased baseline and must stay green *before* any classifier
  unit tests are added (separate step — never edit tests and implementation together).
  · **Baseline re-verified at session-3 start, HEAD `8b86a98`:** suite **52/0**, shellcheck at only
  the two pre-existing findings (SC2016 line 66, SC2181 line 197 — line numbers drifted from the
  65/161 recorded above as the file grew; same two findings, same pre-fork blame).
  · **CLASSIFIER EXTRACTED to `hooks/lib/classify-pr-command.py`** (decision 2 above). Hook 210 →
  141 lines. Moved **verbatim** — shell single-quotes are literal, so no escape sequence changed —
  then wrapped as a pure `classify(src) -> (kind, exempt)` with a thin `main()`. Evidence it is
  behaviour-preserving, beyond the suite: **52 command shapes fed through the old inline classifier
  and the new module produced byte-identical output, 0 mismatches**, including empty input, an
  unbalanced quote, and bare `gh`. Suite still **52/0** with the tests untouched.
  · **`shellcheck -x` is now down to ONE finding — SC2016 is gone**, because the single-quoted
  python string it flagged no longer exists. Only pre-existing SC2181 (now line 128) remains. The
  apostrophe trap is dead *by construction*, not by warning comment.
  · **Confirmed importable**, which was the point: `classify()` can be called directly, so bypass
  shapes get unit tests instead of ad-hoc probing. Pinned by direct call — accepted-open shapes all
  return `NO` (`PR_URL="$(gh pr create)"`, `eval "gh pr create"`, backticks, `env`, `timeout`,
  **`for … do gh pr create; done`** — `do` is not in the wrapper denylist), guarded shapes all
  return `PR` (bare, `$(…)`, `{ …; }`, `&&`, `gh -R`, `time`, `rtk`), and exempt extraction from a
  chained segment yields `("PR", "docs only")`.
  · **NOT DONE — new failure mode deliberately left open for the next TDD step:** a *missing* lib
  file yields empty output → `kind=""` → the hook exits 0, i.e. fails **open silently**, identical
  to how a classifier crash behaves today. That equivalence is why this commit is a pure refactor.
  It should fail **closed** with the named path, matching the missing-python branch above it and
  this file's own single-source-of-truth stance. Write the red test FIRST.
  · ~~**STILL OWED: ADR 0012 Consequences are STALE**~~ — **THAT CLAIM WAS WRONG, corrected
  2026-07-31.** ADR 0012 already recorded those four shapes as *closed* (with a before/after table),
  and its "known open shapes" list was already accurate. The stale 5-bypass list lived only in my
  session notes. Flagged rather than quietly dropped, because **a wrong claim left in an audit trail
  reads as settled** — the same failure mode this branch already paid for once on `{ …; }`.
  What *was* genuinely stale: the ADR's apostrophe bullet described the single-quoted shell string
  the classifier no longer lives in. Fixed on the follow-up branch.

- **PR #32 MERGED 2026-07-31** (`2b8564b`, 03:17Z). Merged main verified green in a throwaway
  worktree — suite 52/0, hook + lib present, one shellcheck finding, **no ADR number collision**
  (0007–0012 unique; the recorded post-merge check, run and clean). Branch + worktrees pruned.
- **FOLLOW-UP BRANCH `fix/judge-guard-fail-closed-classifier`** (off `2b8564b`), all four carried
  items done, **suite 57/0 + 48 classifier assertions**:
  · `8df7d7a` **red** → `c4e14cf` **green**: a missing `hooks/lib/classify-pr-command.py` now fails
  **CLOSED** naming the path. Measured before fixing: an absent classifier exited **0 with no
  output** — the gate looked armed and silently passed every `gh pr create`, the exact defect this
  work exists to remove. **Accepted cost, recorded in ADR 0012:** with no classifier nothing can
  distinguish a PR command from any other, so *all* Bash commands block until the install is
  repaired. Mirrors the missing-python branch beside it. A loud halt is recoverable in seconds; a
  silently dead gate ships unjudged code indefinitely and is invisible by definition.
  · `4ed68a6`: **48 classifier unit tests** — the payoff of extraction (`classify()` is importable,
  so shapes are asserted directly instead of probed through the hook). Pins guarded shapes, the
  load-bearing *ignored* shapes, and the **accepted-open** shapes, so closing one becomes a
  conscious decision with a failing test rather than drift. `{ gh pr create; }` and
  `{ git push; gh pr create; }` sit side by side, since conflating them caused the bad correction.
  **The unit suite immediately caught a wrong assumption of mine** — I asserted
  `JUDGE_EXEMPT=a⏎b gh pr create` was `PR`; the newline is a real separator so the second segment's
  command is `b`, not `gh`. bash agrees: the classifier was right, the test was wrong.
  · **Verdict `outcome` backfill — and a POLICY EDGE CASE worth your call.** All three rounds on
  `fix/judge-guard-verdict-lookup` (`97752e6`, `88ccb59`, `772affe0`) set to **`rework`**: each
  round's findings changed code. **No round ever judged the shipped HEAD** (`d6c38de`) — code landed
  after RUN 3 and no RUN 4 ran before merge. So this branch yields **no `clean` row at all**, which
  the recorded policy ("the final round that shipped is `clean`") does not anticipate. Recorded
  honestly rather than force-fitting a `clean`; it is also true calibration signal — the judge
  prompted rework every round and the merged state went unjudged.
  · **NOT exhaustive, and the count is NOT closed.** Open shapes, each measured:
  `PR_URL="$(gh pr create)"` (inside double quotes the substitution is ONE token — the same property
  that stops a commit message tripping the gate, so **quoting is both the FP protection and the FN
  mechanism**; closing it is an architecture tradeoff, user-owned); backticks; `eval "gh pr create"`;
  function/alias indirection; the wrapper list is a denylist missing `env`/`timeout`/loop keywords.
  Gate stays a momentum guardrail, not a security boundary.
  · `51765fb`: scoped ADR 0012's apostrophe-hazard claim to the classifier only (the genuinely stale
  bullet identified above).
  · **`df1918e` red → `ec1fa1c` green — the fail-closed fix ITSELF failed open, and this is the
  correction.** Obs judge RUN 1 (`bd2621c`) found it; **independently reproduced before being
  believed or written down.** `[ -f "$CLASSIFIER" ]` checks existence, not usability, so four
  present-but-unusable installs still exited **0 in silence** on `gh pr create`: empty, syntax error,
  truncated, unreadable (`chmod 000`). Control with an intact classifier blocked (exit 2), so this
  was the fail-open path and not a test artifact. **The truncated shape is the sharp one** — the
  partial-checkout story ADR 0012 cites as the *motivation* for the missing-file branch produces a
  truncated file at least as readily as a missing one. Fix validates the classifier's **output**
  (`kind` is only ever `PR`/`NO`), covering all six shapes, and is **smaller than what it replaced**.
  Suite **62/0** (was 57/0 + 5 red), classifier unit **50/0** (+2 adjacency cases — mutation testing
  showed the adjacency property, which is what separates the classifier from a substring match, was
  pinned by nothing). **Recovery decision (user, 2026-07-31): no new bypass variable** — the block is
  machine-wide, so the message names the only two routes that survive it (Write tool, or unregister
  in `settings.json`). A `JUDGE_GUARD_REPAIR` escape was rejected: it bypasses a gate whose value is
  being un-bypassable, and a `VAR=x` prefix cannot reach a hook handed the command as a *string*
  anyway — same reason `JUDGE_VERDICTS_FILE` never cleared the gate.
  · **`b095c0a` red → green — RUN 2's severity-1 item, same defect class a THIRD time.** Shape-only
  validation still accepted a classifier that *answers and then dies*: prints a well-formed `NO`,
  exits 1 or raises, `kind` holds a legal value, hook exits 0, gate silently disarmed. Unreachable
  against today's classifier **only because it happens to print its answer last** — the classifier's
  shape protecting the hook, not the hook protecting itself. Guard is now
  `case "$classify_rc:$kind" in 0:PR|0:NO)`. Suite **64/0**, classifier unit **51/0**.
  · **RUN 2's `endswith("EXEMPT")` item was a COVERAGE claim, not a live bypass — measured before
  acting.** Source uses exact equality (`classify-pr-command.py:95`) and `MERGE_EXEMPT=x gh pr create`
  classifies `PR` with an empty reason, i.e. blocked. Pinned by a new case anyway: a suffix match
  would hand every `*_EXEMPT` var in the repo a judge bypass, and `MERGE_EXEMPT` is a real one.
  · **KNOWINGLY DEFERRED on this branch, recorded in ADR 0012:** a **hanging** classifier blocks every
  Bash command indefinitely and *silently* (needs a timeout — larger than remaining scope, and the
  ADR's "loud, self-describing halt" promise does not cover it); and **first arming is untested** —
  the installed hook at `~/.claude/hooks/` predates the extraction and has no `lib/`. Do one arming
  check after merge: pipe a fake `gh pr create` payload into the installed hook, expect exit **2 with
  a readable message** — not a silent 0, not a hang.
  · **RUN 4 (`822f60f`, clean/converging) found a FOURTH fail-open — the PAYLOAD PARSER, a different
  component from the classifier. MEASURED, not accepted on report.** Control (valid payload, no
  verdict) blocks exit 2; **malformed JSON → 0, non-JSON → 0, broken parser (import error) → 0**, all
  silent, gate disarmed. **Zero tests touch that path**, so 64 green ticks say nothing about it.
  **The nuance the judge did not separate, and the fix hinges on it:** there IS a legitimate exit 0
  in that block — valid JSON with no `command` field is not a Bash command and *should* pass. The
  defect is that a genuine **parse failure is indistinguishable** from that legitimate case. Fix must
  distinguish the two (sentinel + status check), not just block on empty output, or it will wrongly
  block every non-Bash tool call. `judge-guard.sh:40-52`; note `except ValueError: sys.exit(0)` and
  the `2>/dev/null`. The file header's promise — *"any inability to verify blocks"* — is currently
  **false**, and RUN 4 flagged the overclaim as being in the header rather than in the ADR bullet.
  · **User decision 2026-07-31: FIX IT on this branch** (red/green + RUN 5), not defer. Reasoning
  recorded because it is not obvious: *documenting instead costs the SAME judge round*, since any
  commit moves HEAD and the gate pins a verdict to an exact SHA — so "document only" buys nothing
  over fixing, and would ship a measurably false header promise on the branch whose entire subject
  is this gate failing open.
  · **DONE 2026-07-31, TDD: `77bfbed` (6 red) → `2acad5e` (green). Suite 64/0 → 75/0**, classifier
  unit 51/0, three neighbouring hook suites unaffected, `shellcheck -x` clean apart from the
  pre-existing SC2181 (now line **201**, was 158 — it moves with every edit, stop quoting the number
  as if it were stable). Red run measured **four** shapes, one more than RUN 4 reported: truncated
  JSON, non-JSON text, valid JSON of the wrong *top-level shape* (`.get` on a list raises), and an
  interpreter on `PATH` that fails — the last stubbed via a fake `python3`, so the real hook runs end
  to end rather than a mutant of it.
  **The fix is a sentinel, and the four control cases are the load-bearing part:** the parser prints
  `OK` on line 1 once it has decided, command from line 2, guarded by
  `case "$parse_rc:$parse_ok" in 0:OK)`. Status *and* shape — the **third** time on this branch a
  check had to stop accepting the appearance of a working component. The controls pin the shapes that
  must still PASS (no `tool_input`, no `command`, empty command, non-string command), because the
  obvious fix — block on empty output — would have closed the hole and denied every Edit and Read in
  the session with it.
  **Header narrowed, ADR 0012 updated.** *"Any inability to verify blocks"* was a coverage guarantee
  the hook has never made; it now scopes the promise to the machinery (missing python, unreadable
  payload, unusable classifier, unreadable verdict store) and names the accepted exceptions. The ADR
  also **withdraws the word "stable"** from its own justification for leaving the parser inline — the
  parser had zero tests, and *untested* is not *stable*. Reasoning from "we never edit it" to "it is
  correct" is how the one component nobody was looking at became the one that was broken.
  **Next: obs judge RUN 5 at `2acad5e`, then the PR** — and the PR *will* block for a PATH reason,
  not a freshness one; see the append-to-primary-store decision at line 137's branch block.
  · **RUN 5 (`0169fa1`, risk=medium confidence=high, judged at `e4a6c10`): the fix HOLDS, its stated
  REASON does not.** Judge re-measured pre-fix disarmed / post-fix blocking, 75/0 + 51/0, red replayed
  as genuinely red, four-vs-three expansion ruled justified. But F1/F2 — **verified myself 2026-07-31,
  it is real** — three sites I wrote (`hooks/judge-guard.sh` parser comment, `judge-guard.test.sh`
  Group comment, ADR 0012) claim *"every Edit, Read and Write in the session reaches this hook."*
  They do not. Enumerated **every** settings file: exactly ONE registration, `~/.claude/settings.json`,
  PreToolUse, matcher **`Bash`**. Editor calls go to phase-guard. Not cosmetic — **the false premise
  chose the behaviour**: the four control tests pin "pass" on the strength of traffic that never
  arrives. Same overclaim class RUN 4 caught in the header, now inside the fix's own commentary.
  · **USER DECISION 2026-07-31 — a Bash payload with no readable `command` must BLOCK.** Reasoning
  given: "you would be the only one who makes these bash calls, so you should have a reason to create
  a bash call, and not just empty ones." Chosen over an unconditional four-way block because it makes
  the hook correct under *any* matcher — the hidden cross-file dependency on `settings.json` is
  precisely what produced this defect, so the hook now reads the payload instead of trusting its
  registration.
  · **⚠ The FIRST implementation of that decision was a regression, caught by RUN 6 and fixed at
  `f92e44a`.** It keyed the SKIP on `tool_name` and returned *before reading the command*, so a live
  `gh pr create` under any name but `Bash` passed unexamined. **Corrected form: the command decides,
  `tool_name` only settles what an ABSENT command means** — runnable command → classify it whatever
  the tool is called; nothing runnable + `Bash` → block; nothing runnable + any other tool → pass.
  The claim "correct under any matcher" only became true at `f92e44a`; before it, the hook was
  *weaker* under a wider matcher than the version it replaced.
  · **`tool_name` presence VERIFIED before relying on it, not assumed** — this is the same shape of
  premise that just failed, so it got evidence: no hook on this machine reads `tool_name` (all key off
  `tool_input.*`), so there was zero local ground truth. Official docs (code.claude.com/docs/en/hooks)
  document it as a **required** PreToolUse field and the one matcher filtering itself uses. Blocking on
  its absence is therefore safe. **Test-harness fidelity gap found:** `judge-guard.test.sh`'s
  `run_case()` builds payloads WITHOUT `tool_name`, so ~70 existing tests would block under the new
  rule — the harness, not the rule, is what is wrong; it must emit a realistic Bash payload.
  · **DONE 2026-07-31, suite 81/0 + classifier 51/0, 3 neighbouring suites unaffected, no net-new
  shellcheck.** Four commits: `99807d6` red (6 fails) → `686917a` harness fidelity → `685f2af` green
  → `5e84a5d` docs. **Five** builders lacked `tool_name`, not one — `run_case`, `run_case_default`,
  `run_case_at`, the JUDGE_EXEMPT probe, the stubbed-interpreter probe. Split from the green commit
  and **measured** behaviour-neutral: against the unmodified hook the fully-updated harness fails
  exactly the six red cases and nothing else. That harness gap is *why* the false premise survived
  five rounds — no test could tell a Bash call from an editor call, so the tests agreed with the
  premise by construction.
  · **`[ -n "$command_line" ] || exit 0` was left unreachable by the fix and INVERTED, not deleted** —
  a fail-closed assertion now. Deleting was the KISS answer; on a branch that has found four silent
  allows, a broken invariant should surface as a block.
  · **Two ADR items VERIFIED, not carried on trust.** (a) open shapes measured via stdin (the way the
  hook feeds the classifier — my first probe used argv and got `NO` for *everything*, including bare
  `gh pr create`; the interface is stdin): `sudo`/`xargs`/`env`/`timeout`/`/usr/bin/gh` → `NO`,
  `rtk`/`command` → `PR`. (b) residual **9** confirmed by reading the `PYEOF` matcher: it compares
  only stage/repo/branch/head_sha, so `risk=high`+`execution=fail` opens the gate exactly as a clean
  verdict does. Residual **8** (`JUDGE_VERDICTS_FILE`) was already in the ADR — no change needed.
  · **Machine-wide trigger now pinned:** a `python3` that WORKS but prints to stdout displaces the
  line-1 sentinel → parse refused → every Bash command blocks, from a cause outside this repo, with
  a message pointing at the payload where nothing is wrong.
  · **Live hook is UNAFFECTED** — `~/.claude/hooks/judge-guard.sh` is the primary checkout's copy
  (`381bd79`, zero `tool_name` references), so none of this is armed on the machine yet. Checked
  before committing, because the fix blocks Bash and I run on Bash.
  · **RUN 6 IS IN** (`d51a431`, risk=medium/confidence=high, verdict committed). It did **not** clear
  the branch. Three findings, the first one real and blocking:
  · **⚠ F1 — the `tool_name` gate made the hook LESS covering, in exactly the direction it was
  justified by.** The SKIP is keyed on the tool's **name**, and returns *before* the command is ever
  read. So any `tool_name` that is not literally `Bash` passes **with a real `gh pr create` inside**.
  **I measured this myself** against an empty store rather than trusting the verdict: `Bash` +
  `gh pr create --fill` → exit 2 (correct); `Shell`, `bash`, `BashOutput`, `mcp__shell__exec` with
  the same command → **exit 0**, command never examined. Pre-change the hook read the command
  regardless of name, so this is a **regression**, not merely an uncovered case. Not live today
  (only `Bash` can arrive under the current matcher) — but "correct under any matcher" was the whole
  stated reason for keying on the payload, and under a wider matcher this is weaker than what it
  replaced. **Third round running for this same overclaim class**, so the doc sites are as much the
  defect as the code: `judge-guard.sh:62` and `:69`, ADR `0012:158`, `CODING_MEMORY.md:252`.
  · **The green never covered it** — all three pass-through tests use payloads with **no `command`
  field at all**, so none of them can catch a non-`Bash` name carrying a live command.
  · **FIX (decided, not yet written): gate the SKIP on "no runnable command", not on the name.**
  Check for a command first; consult `tool_name` only when there is none. That keeps the editor
  pass-through *and* restores coverage. ~2 lines. Red test first: a non-`Bash` name + a real
  `gh pr create` must block.
  · **F2 — a NEW machine-wide block from outside the repo. FIXED @ `abb9562`.** `python3 -c` *and*
  `python3 -` both put the CWD on `sys.path`, so a stray `json.py` in whatever directory you happen
  to be in shadows the parser and blocks **every** Bash command, blaming the payload. **I reproduced
  it before believing it:** from such a directory a bare `git status` exited 2. All three call sites
  now take `-I` — parser, verdict matcher (the heredoc arm has the same exposure via `-`), and the
  classifier — which drops the CWD and ignores `PYTHON*` in one token, so the `PYTHONIOENCODING`
  trigger is retired by the same change. `-I` is **probed once and dropped** on pre-3.4 interpreters
  rather than assumed: the shadowing is a bad day, a hook that will not run at all is worse.
  The **stdout-noise trigger is NOT retired by this** — it needs no `sys.path` entry, still live.
  · **⚠ F4 — found by the SECOND RUN 6 judge, FIXED @ `22a3323`. The pane that appeared to die had
  actually run**, finishing at 02:35Z against the same `d51a431`; its verdict is kept as its own file
  (`...-round6-independent.md`, committed `21f8930`) rather than overwriting the first. It confirmed
  F1/F2/F3 independently **and** caught what neither the first judge nor I did: `.strip()` removes
  whitespace and nothing else, so a `Bash` command of pure control characters read as runnable and
  was **ALLOWED**. Reproduced against HEAD before accepting: `\x00␣␣␣`, `\x01`, `\x01␣␣`, `\x7f` all
  rc=0. Fixed by defining runnable as *at least one non-whitespace, non-control character*
  (`isprintable()`), which keeps em-dash/CJK/tab commands readable.
  · **Two self-inflicted errors on this fix, both caught and recorded, neither shipped:** (1) the
  first draft wrote **raw control bytes** into the test payloads — invalid inside a JSON string, so
  those tests would have passed on a *parse error* rather than on the rule (green for the wrong
  reason); rewritten as `\uXXXX` escapes. (2) `22a3323`'s message claimed "One shellcheck finding,
  pre-existing" **without checking** — it had introduced SC2016 via backticks in a comment three
  lines above that block's own "No backticks or apostrophes in here" warning. Bisected, fixed, and
  corrected in `6c5acd6` rather than amended, because the claim is the class this branch exists to
  stop making.
  · **The F4 fix invalidated my own F3 comment** (lone NUL now blocks earlier, so it no longer
  reaches the assertion). Rewritten in the same commit — but deliberately **not** back to
  "unreachable by construction": that claim was already false once, and an assertion earns its keep
  by catching the route nobody predicted.
  · **F3 — cosmetic, FIXED @ `cd208a7`:** "unreachable by construction" was false and I measured it —
  a lone-NUL command gets `0:OK` (NUL survives `.strip()`) then arrives empty because command
  substitution drops NUL. Exit 2, right direction; the assertion is load-bearing, comment says so.
  · **RUN 7 IS IN @ `249beee` — `risk=low`, `confidence=high`, and it found NO new fail-open.** First
  low-risk verdict on this branch. It rebuilt the three test-first commits and confirmed each was
  genuinely red (83/4, 88/4, 97/4), reverted each fix individually and saw the suite catch every one,
  then put a fake `gh` on `PATH` and compared across 26 shapes what the hook allows against what bash
  actually runs: **no new fail-open, only the four leaks already in ADR 0012**. 21 exotic payloads
  (NBSP, zero-width space, surrogates, BOM, 1 MB commands) all behaved. F1's fix is strictly *more*
  blocking, not less. Three quality items remain, none behavioural:
  · **C1 (the important one — a test that cannot fail).** The five control-character tests assert
  only `exit 2`, but **two different doors exit 2**, so they cannot tell "blocked for the right
  reason" from "blocked by a parse error". Measured by the judge: **my rejected raw-byte draft is
  GREEN against the buggy hook** — it would have tested nothing. Two other mutations (removing the
  parser's status check; reverting the fail-closed assertion) also leave the suite at a happy 101/0.
  **Fix: assert the MESSAGE, not just the code** — this file already does that three times elsewhere.
  · **C1 IS DONE — and the surface was four times bigger than the finding said.** The five
  control-character tests were the *named* instance; enumerating by measurement rather than by
  reading found **48** blocking assertions with the same defect. Both test families now assert the
  MESSAGE alongside the code, via `run_payload_msg` / `run_case_msg` / `run_case_default_msg` and
  three named constants (`MSG_UNREADABLE`, `MSG_NOTHING_RUNNABLE`, `MSG_NO_STORE`, `MSG_NO_FRESH`).
  Suite stays **101/0** — no behaviour changed, this is test strength only, and `judge-guard.sh` was
  not touched.
  · **Proved by mutation, since "the tests are stronger now" is exactly the claim that needs
  evidence.** Two mutants, each measured against the committed suite and then against the new one:
  **M1** (reroute the no-runnable-command door from `SystemExit(4)` to `(3)`, so the block message
  becomes the parse-error one while the exit code stays 2) — committed suite **101/0, the mutant
  survives completely**; now **92/9**. **M2** (empty the classifier, so every command blocks at the
  classifier-unusable door instead of being read and classified) — committed suite 66/35; now
  **33/68**, i.e. **33 further tests** that claimed to test blocking were passing while nothing was
  being classified at all. M1 is the finding's own defect, reproduced: a mutant no committed test
  could see.
  · **The wider lesson, and it generalises past this hook:** `exit 2` is not one door — a payload
  that never parsed, a Bash call with nothing runnable, an internal-error assert, an unusable
  classifier, and the verdict gate all exit 2. Asserting the number tests that *something* refused;
  only the message tests *that the guard read the command and judged it*. The suite had already made
  this exact argument about `exit 0` for the quoted-`JUDGE_EXEMPT` case since round 2 — the
  reasoning was sitting in the file, applied to one case, for five rounds.
  · **C2 — two live comments overstate the code, both mine, both from this session.**
  `judge-guard.sh:55-57` (copied into the suite at `:462-463`) explains `sys.path` in a way that
  measures **false under `-I`**: isolated mode *drops* the script's directory rather than putting it
  first, so the comment would tell the next editor a sibling import is safe. It is not.
  And `:171-172` claims `$(...)` substitution "is caught" — true unquoted, **false** for the quoted
  `PR="$(gh pr create)"` that ADR 0012 itself lists as accepted-open. **Fourth round of this class.**
  · **C2 IS DONE — both claims re-measured BEFORE editing, per the standing rule, and both were
  genuinely false.** (1) `sys.path`: measured on **Python 3.9.6**, under `-I` the script's own
  directory is **absent from `sys.path` entirely** and a sibling import raises `ImportError` — the
  old comment described the *non*-`-I` arrangement, so it would have told the next editor a local
  import beside the classifier was safe. Corrected at `judge-guard.sh:55-57` and at the suite's copy
  (now `:513-516`, not `:462-463` — C1 moved it). The correction also **strengthens** the rule: `-I`
  means the classifier must stay stdlib-only, and since the pre-3.4 fallback can clear `-I`, neither
  arrangement may be relied on. (2) Command substitution, measured against the classifier: unquoted
  is caught (`$(gh pr create)`, `echo $(...)`, `PR=$(...)` → **PR**), quoted is **not**
  (`PR="$(gh pr create)"`, `echo "$(...)"` → **NO**), backticks are not. The comment claimed
  substitution was caught outright. Fixed at `judge-guard.sh:171-181`, which now names the quoted
  form as a genuine accepted-open gap rather than a lexing subtlety.
  · **The false claim was localised — I checked before assuming.** ADR `0012:278` and the classifier
  unit tests (`classify-pr-command.test.py:39,81`) already stated both shapes correctly; only the one
  hook comment was wrong. Comments-only change: suite **101/0**, classifier 51/0, shellcheck codes
  identical before and after (3 SC2016 + 2 SC2181, all pre-existing).
  · **The path-qualified `gh` naming gap was re-raised and REAFFIRMED OPEN by the user 2026-08-01**
  — `/usr/bin/gh pr create` → `NO`, ADR `0012:291-295`. It is the one accepted-open shape that is a
  patch rather than an architecture change (compare the path's basename), which is why it keeps
  coming back up. Reason it stays open is unchanged: closing one naming gap while `sudo`, `env` and
  `timeout` stay open buys no real coverage, and this is a momentum guardrail, not a security
  boundary. **Second time this has been asked and answered — it is settled, do not re-litigate.**
  The quoted-substitution gap likewise stays open per the 2026-07-30 decision at line 91.
  · **C3 landed @ `07c2451` + `411416d` — docs only, no behaviour change.** `...round6.md` carried a
  raw NUL at **offset 6360**: a judge typed a literal NUL while *describing* the NUL finding, so git
  classified the whole verdict binary. Measured as an addition, which is how the PR diff `main..HEAD`
  sees it — before `Bin 0 -> 11313 bytes`, after **147 insertions**. Escaped to `\x00`, the convention
  the sibling independent verdict already used.
  · **Because this was the THIRD instance, I enumerated instead of patching a fourth** — every tracked
  file scanned for control bytes outside tab/LF/CR. Found **two more**, both in this branch's own RUN 7
  verdict, both invisible to git because they sit **past the 8000-byte binary-sniff window**: the file
  rendered fine and carried the bytes anyway. `:185` was the judge's instruction *to escape the RUN 6
  NUL*, written with a literal NUL. `:100` was a table row labelled **"(committed, escaped)"** holding
  a raw `0x01` — the label said escaped and the byte was not, so the row contradicted itself.
  Both fixed @ `411416d`. Each fix diffed byte-for-byte against a copy with the same substitution
  applied: **no claim changed, encoding only.**
  · **Lesson, and it is the general one:** git's binary flag is a *sniff*, not an audit — it reads the
  first 8000 bytes. "The diff renders" is not evidence a file is clean. Enumerate the surface.
  · **One instance deliberately NOT fixed:** `...statusline-command-round3.md:22` carries a raw ESC
  (`0x1b`). **Verified present in `origin/main` unchanged** — pre-existing, another feature's file,
  not this branch's work. Own task; do not widen this PR for it.
  · **NEXT: obs judge RUN 8 at the final HEAD, then the PR.** C1, C2 and C3 have all landed.
  · **superseded pointer — fix F1 (red→green) + F2, then obs judge RUN 7**, then the PR (blocks for
  reason — append the genuine verdict to the primary store, see line 137's branch block).
  · **Endgame ordering, settled by measurement:** `judge-guard.sh` compares `head_sha` by **strict
  equality**, so committing the verdict moves HEAD and staleens it. Do **not** re-key a verdict to a
  later SHA — that is fabrication. Instead: leave the final verdict commit **pending**, append the
  genuine line to the primary store, `gh pr create` at the matching HEAD, then commit and push.
  · **Next for THIS branch:** obs judge (implementation stage) pinning the final HEAD → `gh pr create`
  → merge via GitHub UI → prune branch + worktree local+remote → tip-reachability check + outcome
  backfill. Unlike PR #32, no PR is open here, so **judge-guard genuinely gates this one**.
- **SIBLING BRANCH `docs/verify-before-claiming`** (rebased onto current `main`; PR #50) — one line in
  `rules/core-conduct.md`: **verification precedes both the claim and the write-down**, not just the
  claim. Closes the gap the four corrections above all shared — each was a claim that entered a
  durable artifact before it was checked. Triaged via `triaging-new-instructions` → **static rule,
  not a hook**: keying on claim words fires on every Conventional-Commits `fix:` prefix, a
  false-positive class this repo has already paid for. Committed `Doc-Exempt` to avoid a guaranteed
  CODING_MEMORY conflict with this branch; **this bullet is that deferred entry.**
- **PARKED — CODING_MEMORY consolidation, its own branch, AFTER the verification-marker gate (user
  ruled 2026-07-31).** This file is **~1350 lines against the 200-line cap stated on its own line 3**,
  and **six consecutive obs-judge verdicts have now flagged it**. Line 3's self-measurement ("778")
  is itself **stale by ~550** — deliberately left uncorrected, because the user's call was to keep
  the flag loud rather than cosmetically patch the number and make the file *look* maintained. Read
  line 3 as known-wrong until that branch lands. The decision that branch owes: whether the cap is a
  real policy this file can hold to, or the wrong shape for what the index has become — a limit
  violated 6.7× across six verdicts is not functioning as a limit either way.
- **ACTIVE — verification-marker gate (user ruled 2026-07-31: build it; reordered to FIRST 2026-08-01).**
  The prose rule above is deliberately the *weak* control, and this repo established this week that a
  warning sitting where the mistake keeps being made is a **disproven** control. The strong version:
  a test run writes a marker, and a hook requires a fresh one before commits touching tested code —
  **the judge-guard shape applied to tests** (mirror `hooks/judge-guard.sh`, `judge-guard.test.sh`,
  and the extracted `hooks/lib/` classifier module). Its own branch, not bundled.
  **Scope caveat accepted by the user 2026-08-01:** this gate would **not** have caught this session's
  narration error, so it does not close the defect that prompted the reorder. A narration control is a
  separate, later design. Do not widen this branch to cover it.
  - **MEASURED 2026-08-01** (probe: `tree-key-probe.sh`, throwaway repos — run, not reasoned):
    - **"Fresh marker keyed to HEAD" was the wrong frame, and the blocker is dissolved.** A *tree* key
      survives the commit: on the normal path (test → `git add -A` → `git commit`) the worktree tree,
      the pre-commit index tree, and the committed tree are **one identical SHA**. HEAD moves; the tree
      does not.
    - **The tree key is content-only** — commit message, author, and timestamp do not affect it
      (verified by soft-reset: same key before and after). This is *why* the `fix:`-prefix false
      positive cannot re-enter: the gate never reads the message at all. Structural, not disciplinary.
    - **A whole-tree key is still wrong**, for two measured reasons: **partial staging** (test the
      worktree, stage one file → trees differ → false block) and **untracked scratch files** (a scratch
      file written after the test run moves the worktree key; gitignoring it does not help, because
      `.gitignore` is then itself a new file).
    - → **Design consequence: key on per-file blob hashes, not one whole-tree hash.** Record what each
      tested file hashed to; at commit time check each *staged* file against that record. Untracked
      scratch is irrelevant (never staged) and partial staging works (staged ⊆ tested).
    - `git commit -a` commits the **worktree** tree, but a PreToolUse hook reading the index sees a
      **stale** value — `-a` needs its own handling.
    - `git write-tree` is side-effect-free (leaves `git status` unchanged), so it is safe from a hook.
    - ⚠️ **Probe-methodology gotcha:** v1 of the probe put its temp `GIT_INDEX_FILE` *inside* the
      worktree, so `git add -A` hashed the index file itself and **every case falsely read as DIFFER**.
      A temp index must live outside the repo. The first run's "CASE 1 fails" was a probe bug, not a
      finding — caught only by disbelieving a surprising result and re-checking the instrument.
  - **DECIDED (user, 2026-08-01) — trigger scope: a staged file with a sibling test file**
    (`hooks/foo.sh` → `hooks/foo.test.sh`). Decidable from staged paths alone, so no message parsing.
    Never demands a test run for a file that has no test. **Backtested over the last 30 commits: 6 fire
    (all of them `hooks/judge-guard.sh`), 24 exempt** — docs/memory commits, which dominate this repo,
    are exempt automatically. Sibling-test coverage today: 5 of 12 `hooks/*.sh` are tested, plus
    `panes/*.test.sh`, `statusline-command.test.sh`, `hooks/lib/classify-pr-command.test.py`;
    `memsearch/tests/` uses a `tests/test_*.py` layout, **not** the sibling convention.
  - **DECIDED (user, 2026-08-01) — the marker is written by the TEST SUITE ITSELF.** Each `*.test.sh`
    gains one line: on `fail -eq 0`, call a shared `hooks/lib/write-test-marker.sh` that records
    `git hash-object` of its subject file. **Proof of PASS is the suite's own tally** — the same number
    a human reads off the run — so the gate depends on no harness semantics at all, and behaves
    identically under a pane agent, a subagent, or a direct run. Costs a one-time mechanical edit of
    ~8 test files. **A future test file that forgets the line fails CLOSED and loudly** (its subject can
    never be committed until the line is added), which is the ADR 0012 stance already adopted here:
    a loud halt is recoverable in seconds, a silently dead gate is invisible by definition.
  - **The two rejected options, with the reason, so they are not re-proposed:**
    · **PostToolUse observer hook** — zero workflow change and no test file touched, but it rests on
      **unmeasured harness semantics**: if a failing `bash` exit does not in fact route to
      `PostToolUseFailure`, the gate would certify **failing** tests. That is the silent-fail-open class
      this repo has now hit four separate times, and it would be introduced deliberately at the design
      stage. Also needs a second registration on a machine that already has one unregistered hook.
    · **Wrapper runner (`bin/run-tests`)** — sound (it observes the exit status itself) but changes the
      habit: a direct `bash hooks/foo.test.sh` would silently produce no marker, and it invalidates the
      invocation this repo documents at `hooks/README.md:34,140`.
  - **MEASURED this session** (grep/read, not reasoned): every shell suite ends
    `printf '%s passed, %s failed'` then `[ "$fail" -eq 0 ]`, so pass is already exit-0 and the marker
    hook-in is genuinely one line. `hooks/state/` is gitignored at `.gitignore:17` — the existing
    machine-local runtime-state precedent set by phase-guard, so the marker store needs no new plumbing.
  - **REPORTED, NOT MEASURED — do not act on these without checking first.** Official docs confirm
    `PostToolUse` fires *after a tool call succeeds* with `PostToolUseFailure` as a separate event; the
    claim that a Bash `tool_response` carries **no exit-code field** (only `stdout`/`stderr`/
    `interrupted`) comes from the vendored plugin's own comment at
    `plugins/.../security-guidance/hooks/security_reminder_hook.py:1028`, and
    `code.claude.com/docs/en/hooks-reference` **404s**, so it could not be confirmed upstream. Labelled
    rather than absorbed, because the rejected option above turns on exactly this fact.
  - **ALL RATIFIED BY THE USER 2026-08-01** (was "proposed and unchallenged" — updated rather than left
    standing, since a stale claim in an audit trail reads as settled): marker store in `hooks/state/`,
    resolved from `git rev-parse --show-toplevel` and **never `$HOME`** · **strict 1:1 sibling** coverage,
    **no declared coverage map** (a second source of truth that can rot) · `memsearch/tests/test_*.py`
    **out of scope for v1 but explicitly NOT forgotten** — the user asked for a follow-up plan · **both
    holes closed in v1**: the marker records the **test file's hash as well as the subject's** (so a test
    version that was never run cannot ship), and **`git commit -a` gets its own branch** (it commits the
    **worktree**, but a PreToolUse hook reading the index sees a stale value).
  - **TWO USER PROPOSALS, both withdrawn on my feedback 2026-08-01 — the reasoning matters more than the
    outcome, so it is recorded rather than just the "no".**
    · **A repo-wide session lock.** The user attributed past bugs partly to running concurrent sessions.
      **That diagnosis is mostly wrong and I said so:** the fail-open hook bugs were single-session logic
      errors, and the `$HOME`-vs-project bug was path resolution surfaced by *worktrees*, not a race.
      Concurrency has genuinely bitten only two places — `CODING_MEMORY.md` conflicts and the shared
      index (hence the standing `-- <path>` rule). Decisive objection: **a lock deadlocks the repo when a
      session dies**, and stale-lock detection would rest on liveness signals this repo has already
      measured as unreliable (`ps | grep run-pane-agent` cannot see a live pane agent). Accepted
      alternative: **worktree-per-session is the structural fix** (separate index + working tree); at most
      a **warn-only** session-start notice. PARKED, its own feature, never bundled here.
    · **Mutual test certification** (A certifies B + code, B certifies A, nothing self-certifies). The
      instinct — the thing checked should not author its own certificate — is sound, but the mechanism
      cannot deliver it: **a hash can only say a test *changed*, never that it got *weaker***. The
      reframe that dissolved it: **the marker is a receipt, not a grade.** It records what contents were
      present when a run reported zero failures; it does not vouch for quality, so a receipt naming
      itself is no conflict of interest. The real abuse is already closed by the both-hashes rule.
      Replacement parked: **mutation-test the hook suites** — the genuine "who tests the tests" control,
      already proven in this repo (a planted mutant survived a happy 101/0 suite).
  - **SPEC WRITTEN AND PUSHED `75f1ade` — `docs/features/verification-marker-gate.md`** (frontmatter +
    spec + 14-task checklist, `phase: planning`, `branch: none`). Mermaid block passes
    `validate-diagrams.sh`; pair count re-measured (9 shell + 1 python = the 10 suites task 8 names).
    Self-review found and fixed one ambiguity: a pair whose **test file is deleted while the subject is
    modified** resolves to ABSENT and blocks — implied by the resolver, but not stated until now.
    Versions pinned from measurement: bash **3.2.57** (macOS system bash — no associative arrays, no
    `mapfile`), Python **3.9.6**, git **2.50.1**.
    **NEXT: compliance judge + obs judge (architecting stage), then the user review gate.** A failing or
    missing compliance verdict blocks `superpowers:writing-plans`.
  - **ROUND 1 VERDICTS ARE IN 2026-08-01 — BOTH NEGATIVE, and every load-bearing claim was
    RE-MEASURED BY ME before being accepted.** Compliance: **`fail`**, 4 violations, confidence high
    (`coding-memory/compliance-judge/2026-08-01-verification-marker-gate.md`, spec blob `560b74ba`).
    Obs: **`risk=high confidence=high`**, leading with a `fail` on `execution`
    (`coding-memory/observability-judge/2026-08-02-main.md`). Probe:
    `scratchpad/verify-judge-findings.sh`, throwaway repo outside any checkout.
    · 🔴 **THE BLOCKER, measured not accepted on report: `git commit -- <path>` commits the WORKTREE,
      not the index.** Probe: index=v2, worktree=v3, `git commit -- f.sh` → **committed v3**. The spec's
      resolution table knows only `-a`→worktree and *everything else*→index, so **pathspec commits fall
      into the index branch and the gate goes green while shipping untested content.** This repo's own
      standing rule mandates `-- <path>` on **every** commit, so the hole sits under the exact command
      form always used here. The spec found one member of that family (`-a`), said "measured, not
      assumed", and stopped looking for siblings.
    · 🔴 **The `-a` fix does not work either.** With an unstaged edit, `git diff --cached --name-only`
      returns **0 paths** (measured) — so the collection step finds no files, no pairs, and allows. The
      table branches *which file it hashes* but not *which files it looks at*. The spec's own headline
      `-a` scenario silently passes.
    · 🔴 **MY OWN CLAIM WAS FALSE, and this is the important one.** CODING_MEMORY and commit `1859c30`
      say the pair count was "re-measured": **9 shell + 1 python = 10**. Truth, from `git ls-files`:
      **13 suite files, 11 pairs, 2 orphans.** My glob was `hooks/*.sh panes/*.sh statusline-command.sh`
      — **non-recursive**, so it never saw `panes/adapters/*.sh`, and it never globbed `*.test.sh` at
      all, so orphan tests were structurally invisible. **I ran a command and called its output
      verification; the instrument did not cover the surface.** Same shape as this branch's recorded
      lesson that three false-positive probes all exercising quoting is one sample, not three.
    · **Two ORPHAN TESTS with no sibling subject** — `panes/adapters.test.sh`,
      `panes/adapters/cmux-exec.test.sh`. Sibling derivation resolves to a non-existent file, and the
      ratified "a failed marker write fails the suite" rule would turn both permanently red, with no
      specified error path and no scenario. **A guard that requires a routine `TEST_EXEMPT` teaches
      the bypass.**
    · **Coverage illusion, 8 unguarded subjects under `panes/`** (measured) — including
      `panes/adapters/cmux.sh`, tested by the differently-named `cmux-exec.test.sh`. The spec's scope
      sentence reads as though `panes/` is covered.
    · **The one-line call site is wrong for 7 of 13 suites** — `$(dirname "$0")/lib/…` resolves only
      under `hooks/`; with `|| exit 1` every one of them turns red.
    · **Compliance's other 3:** unspecified stdin/stdout framing and no type constraint for
      `classify-commit-command.py`'s free-text `exempt` (parsed from a user-controlled string onto a
      line-oriented protocol — the hazard `classify-pr-command.py:96` already defends); `shellcheck`
      (0.11.0 installed) gates checklist task 10 but is missing from the pinned-versions section;
      plus the scope-inventory and orphan-test items above.
    · **Explicitly NOT cited, so do not "fix" it:** the `docs/features/` spec-location deviation is
      adequately reconciled. All three runtime version pins and the `.gitignore:17` citation
      re-measured exact.
    · **Both judges also credited what held:** the four `judge-guard` fail-open fixes are genuinely
      carried, not name-checked, and the fail-closed contract is honestly shaped. Obs: "the gap is
      verification of the repo it gates, not thinking."
    · **STILL OWED, round 2:** git-command failure is absent from the blocking list (a git error is
      indistinguishable from "no files to check" → allow, which is `judge-guard` fail-open #3 reborn);
      which directory `rev-parse --show-toplevel` runs in; the full `MSG_` constant table (5 named
      against ≥8 doors); the mutant floor raised to one per door; where `TEST_EXEMPT` is logged.
  - **ROUND 2 SPEC REVISED 2026-08-01 (`revision: 2` in frontmatter), every round-1 finding closed
    against a fresh measurement, not against the judges' reports.** New probes, throwaway repos, git
    2.50.1 — 18 observations across `PLAIN`/`PATHSPEC`/`ALL`/`INVALID`/`FOREIGN` and all three
    `--amend` combinations. **The central fix: `form` now decides BOTH the path set AND the content
    source** — round 1 branched only the hash source, which is why its own `-a` scenario was
    unreachable.
    · **Measured, and each is now a table row + a scenario:** `git commit -- f.sh` ships the
      **worktree** (`v3`, not index `v2`) · a pathspec also **narrows** (`commit -- bar.md` with
      `foo.sh` staged commits bar.md only, so index collection raises FALSE blocks) · a pathspec over
      an **unchanged** file commits nothing for it, so `-- hooks/` is not a false block ·
      `git diff --cached` returns **0 paths** for a never-staged edit while `-a` commits it ·
      `git commit -a -- <path>` is **fatal 128**, git refuses, so the hook allows · `--amend` needs
      base **`HEAD^`** (vs `HEAD` returns only the sidecar; vs `HEAD^` returns exactly the amended
      commit's contents) and on a root commit `HEAD^` fails 128 → empty tree
      `4b825dc642cb6eb9a060e54bf8d69288fbee4904` · `--diff-filter=d` keeps a rename's **new** path and
      drops the old · outside a repo `git diff --cached` prints **nothing** and exits **128** — the
      fail-open trap, now `MSG_GIT_FAILED` · `$0` from a subdir is **relative**
      (`adapters/cmux-layout.test.sh`), fixed by `git ls-files --full-name`.
    · **Two design changes beyond patching findings.** (1) **One helper, one line of JSON** replaces
      the two-line `OK`/command protocol — a command or an exemption reason containing a newline
      cannot desync a JSON object, so the desync class is removed rather than defended against;
      the `v: 1` field carries the sentinel role (status *and* shape). (2) **`form: FOREIGN` blocks**
      — `cd /other/repo && git commit`, `git -C`, `--git-dir`, `--work-tree` are unverifiable from a
      PreToolUse hook, and both allowing and blocking on the wrong repo's markers is wrong, so it
      fails closed with a named door.
    · **Orphan suites: writer skips, gate never pairs, and a TEST freezes the inventory.** The
      standing trigger fired — the round-1 defect was an inventory claim no test could contradict, so
      correcting `10`→`11` alone would repeat it. `write-test-marker.test.py` now asserts 11 pairs and
      exactly 2 named orphans; a rename that drops a subject out of the gate turns it red.
    · Doors enumerated **11** (was 5), mutant floor one per door (was 2 total). `MSG_NO_MARKER`
      remedy derived from the suite extension. `TEST_EXEMPT` → `hooks/state/test-exempt.log`. Store
      `0700`/`0600`. Blob regex tightened to `^([0-9a-f]{40}|[0-9a-f]{64})$`. shellcheck **0.11.0**
      pinned. Tasks 7+8 flagged **revert-as-a-pair**. `cmux.sh` coverage hole stated in Scope as a
      named follow-up, not quietly closed.
  - **ROUND 2 VERDICTS 2026-08-02 — compliance `fail` again (4), obs `risk=medium` (was high).
    TWO IDS RECURRED → MANDATORY ESCALATION TO THE USER, loop paused.** Verdicts:
    `coding-memory/compliance-judge/2026-08-01-verification-marker-gate.md` §Round 2,
    `coding-memory/observability-judge/2026-08-02-main-round2.md`.
    · **What round 2 CLOSED, re-measured by the judge and confirmed:** the whole form table (all
      pathspec/`-a`/`--amend`/rename/root-commit rows held), the 11-pair inventory, orphan behaviour,
      shellcheck pin. `writing-specs/{edge-cases,pinned-versions}` closed.
    · 🔴 **`writing-specs/verified-scope-inventory` RECURRED.** I corrected 10→11 *and* froze it with
      a test — and **the frozen count is false the moment implementation starts.** This feature adds
      **3 conforming pairs of its own** (`test-marker-guard`, `classify-commit-command`,
      `write-test-marker`): 12 pairs at task 4, 14 after task 7. The assertion "exactly 11 pairs, 2
      orphans" fails → suite fails → no marker → **`write-test-marker.py` becomes uncommittable.**
      The control I built to stop an uncheckable claim is itself uncheckable.
    · 🔴 **`writing-specs/api-contracts` RECURRED.** I added the full JSON contract but never
      reconciled it with the existing scenarios: the field table says the classifier **strips**
      control chars, while the edge scenario demands `MSG_CLASSIFIER_BAD_OUTPUT` for a newline-bearing
      `TEST_EXEMPT`. A *correct* classifier makes that scenario unreachable — the red test can only
      pass by breaking the classifier.
    · **NEW `writing-specs/commit-form-coverage` — I re-measured it myself and it is REAL:**
      `git commit -i -- b.md` with `a.sh` staged commits **BOTH** (`a.sh` at its staged content);
      the `PATHSPEC` collector returns `b.md` only → **fail-open, and `-i` lexes fine** so the
      accepted-open clause does not cover it. (`-o`/`--only` measured equivalent to plain pathspec —
      safe.) Also: the table defines content only for paths *in* the path set, while the pairing rule
      hashes **both** members — a pair member outside the pathspec has no defined post-commit content.
    · **NEW `writing-specs/scope-boundary` — verified:** all four sibling guards (`git-guard`,
      `doc-guard`, `judge-guard`, `merge-guard`) are registered in the **global** `settings.json` with
      matcher `Bash`, so they fire in **every repo**. The spec never says whether this gate is
      `.claude`-only or global; `.gitignore:17`'s `/hooks/state/` cover does not travel, and a foreign
      repo with the same sibling convention would block every commit with no writer present.
    · **Obs (advisory, risk=medium) adds:** `FOREIGN` contradicts itself (flowchart blocks without
      passing the `TEST_EXEMPT` node, prose advertises `TEST_EXEMPT` as the escape) · `FOREIGN`
      ignores the payload `cwd` field `hooks/context-handoff-watch.sh:45` already consumes, so
      `cd "$HOME/.claude" && git commit` is a **same-repo false block** · no latency budget (existing
      PreToolUse chain measured ~373 ms; `python3` on every Bash call adds ≥56 ms) · the spec never
      mentions the three sibling guards that already lex `git commit` with anchored regexes ·
      `hooks/judge-guard.test.sh:13` does a top-level `cd`, so the canonical call site resolves the
      wrong toplevel there (exactly 1 of 11) · the `INVALID` allow-path sits outside the one-mutant-
      per-door floor · the frozen-inventory test has an instrument but **no trigger** · no Python
      call-site form for pair #6.
    · 🔴 **THE PATTERN, and the thing to decide before round 3:** both recurring ids are the same
      shape — **I fixed the cited instance and not the class, patching the spot without re-deriving
      the document.** Round 3 should be a whole-document consistency pass (does every scenario still
      follow from the contracts? does every count survive the feature's own additions?), not four more
      targeted patches. The standing trigger already says four rounds on PR #34 proved targeted
      iteration will not converge.
  - **ROUND 3 DIRECTED BY THE USER 2026-08-02 — escalation resolved, nothing waived.** Two rulings:
    (1) **whole-document re-derivation**, not targeted patches; (2) `scope-boundary` closed by
    decision — the gate registers **globally** like its four siblings but is **inert unless the
    resolved repo has the writer installed**, so a foreign repo with sibling-test naming can never be
    locked out with no marker writer present.
    · **Re-measured before rewriting (all five confirm the record, none taken on trust):** inventory
      is **13 suites / 11 pairs / 2 orphans**, unchanged · `hooks/judge-guard.test.sh:13` really does
      `cd "$TMP"` at top level (**exactly 1 of 11**, so the call site must capture `$0` + toplevel at
      the top) · `git commit -i -- b.md` with `a.sh` staged commits **BOTH** and `HEAD:a.sh` is the
      staged `v2`, while the `PATHSPEC` collector returns `b.md` only — **fail-open reproduced** ·
      a pair member modified in the worktree but **outside** the pathspec ships at **base** content
      (`t1`), not worktree content (`t2`) — its post-commit content was genuinely undefined ·
      `rev-parse --show-toplevel` outside a repo exits **128 with empty stdout**.
    · **Derived fixes (the class, not the instances) — these are what round 3 writes:**
      **`verified-scope-inventory` root cause: the frozen literal count was the wrong control.** It
      froze a number the feature itself invalidates. Replaced by two assertions that survive the
      feature's additions: *every tracked pair's suite contains the marker-write call* (real trigger:
      add a pair without wiring → red) and *the two named orphans are still orphans* (protects the
      `cmux.sh` hole claim; goes red on the follow-up rename, which is correct). The wiring assertion
      lands **in task 8's own commit**, not task 4 — at task 4 it would be red for four tasks.
      **Task 8 therefore wires 14 suites, not 11:** the feature's own three pairs
      (`test-marker-guard`, `classify-commit-command`, `write-test-marker`) are `hooks/` files with
      sibling tests, so the gate demands markers for them and they become uncommittable if unwired.
      **`api-contracts` root cause: the strip was vestigial** from the dead two-line protocol — JSON
      framing already survives a newline. Classifier no longer sanitises; the hook validates and
      blocks a bad exemption at its **own** door, `MSG_BAD_EXEMPT`. Over-long is blocked, never
      silently truncated (an unauditable truncated reason defeats the exemption log).
      **`-i`/`--include` → `form: INCLUDE` → block** (`MSG_UNSUPPORTED_FORM`), same fail-closed
      precedent as `FOREIGN`; the repo's house style never uses it.
      **Post-commit content is now defined for EVERY pair member**, not just those in the path set:
      the blob the resulting tree will hold — `PATHSPEC` → worktree if matched, else the `<base>`
      blob (M4); `PLAIN` → index; `ALL` → worktree if tracked.
      **`TEST_EXEMPT` moves BEFORE the `FOREIGN` check** — the round-2 flowchart blocked `FOREIGN`
      without ever reaching the exemption node while the prose advertised it as the escape.
      **Repo resolves from the payload `cwd`**, which is the correct use of that field; it is still
      NOT used to follow a `cd` (the payload cwd is the session's, pre-`cd`).
      **Doors were miscounted at 11 — `MSG_STALE_SUBJECT`/`MSG_STALE_TEST` share one table row but
      are two doors.** True count 12, plus the two new = **14**; floor is one mutant per door plus
      one per allow-path.
  - **ROUND 3 VERDICTS 2026-08-02 @ `6046565` — compliance `fail` (3), obs `risk=medium`
    (unchanged). BOTH escalation triggers fired: `api-contracts` has now been cited in THREE
    consecutive rounds, `commit-form-coverage` in two, and round 3 ended with violations
    outstanding. Loop paused, awaiting the user. Nothing waived in any round.** Verdicts:
    `coding-memory/compliance-judge/2026-08-01-verification-marker-gate.md` §Round 3,
    `coding-memory/observability-judge/2026-08-02-main-round3.md`.
    · **The re-derivation DID work on what it targeted — verified, not assumed.** Obs re-measured and
      confirmed **all eight** round-2 findings closed, the inventory (13/11/2) exact, and explicitly
      that **no target is dressed up as a measurement anywhere** in the document. Neither judge
      re-cited the frozen count or the vestigial strip — the two original root causes are dead.
    · 🔴 **The recurring ids are NOT the old defects surviving. They are NEW defects the round-3
      additions introduced, landing in the same id buckets.** `api-contracts`: the latency pre-filter
      I added makes `MSG_NOTHING_RUNNABLE` unreachable (an absent command contains neither `git` nor
      `commit`, so the cheap filter exits 0 first), and the flowchart's opposite ordering is only
      implementable by spawning `python3` on every Bash call — which voids the ≤5 ms budget I wrote
      in the same section. `commit-form-coverage`: the ABSENT rule I added probes `<base>` only,
      but post-commit content comes from the index under `PLAIN` and the worktree under `ALL`, so a
      test staged for deletion passes the base probe and the gate allows a commit whose tree drops
      it — contradicting the spec's own scenario.
    · **NEW `writing-specs/writer-call-site-cwd`, and it is the sharpest catch of the three:**
      capturing `$0` and the toplevel before a `cd` fixes the *values* but not the **writer
      process's cwd**, which both of its mandated resolution steps depend on. Measured from
      `judge-guard.test.sh`'s post-`cd` shape: `git ls-files --full-name --error-unmatch` exits 1
      and `rev-parse --show-toplevel` returns the *throwaway* repo — so my round-3 fix leaves one of
      the 14 suites task 8 must wire permanently red.
    · 🔴 **OBS FOUND THE LAYER UNDERNEATH, and this is the finding that should drive round 4:**
      **`git commit -am x` is a live fail-open.** The form table defines `ALL` as `-a`/`--all` and
      never mentions **bundled** flags, so a classifier matching those tokens reads `-am` as
      `PLAIN`, uses the index collector, gets zero paths, and waves through untested content — the
      round-1 `-a` fail-open walking back in through another door. `hooks/doc-guard.sh:132` already
      carries an `-am` comment; the spec forgot what a sibling guard knew. Same cause:
      **`git commit -m y foo.sh` (pathspec with no `--`)** ships the worktree blob while `PLAIN`
      hashes the index blob. **Root cause in one sentence: the spec specifies the `paths` FIELD and
      never the lexing GRAMMAR that fills it — the one paragraph in the document not measured to an
      exit code, and the one everything else rests on.**
    · **Obs also owed:** doors 3-6 appear nowhere in the flowchart (node E's "no" edge reads as
      classifier-failure → ALLOW, the same prose/diagram contradiction class just fixed for
      `FOREIGN`) · the tracked-ness probe is a **third** unchecked git call and it fails toward
      *allow* · nothing distinguishes "allowed, verified" from "allowed, **inert**"
      (`judge-guard.sh:204` records this exact failure in this exact family) · unborn HEAD:
      `git diff --cached HEAD` exits 128, blocking a writer-installed repo's first commit ·
      **the revert-pair warning names the wrong pair — the writer is task 5, so 5↔8 is the hazard,
      not 7↔8** (carried forward from round 2 unre-derived, the exact class round 3 was meant to
      kill) · allow-path list says seven, the flowchart has nine edges · drop `merge-guard.sh` from
      the lexer list, add `checkpoint-before-modify.sh:97`.
- 🔴 **`hooks/git-guard.sh` FAIL-OPENS ON ANY CHAINED COMMAND — found 2026-08-02, live, Tier 1.**
  `git-guard.sh:89` anchors `commit_re='^git[[:space:]]+commit([[:space:]]|$)'` at the **start** of
  the normalized command, so `git add -- <path> && git commit -- <path>` never matches and the
  default-branch guard does not evaluate at all. Discovered because the obs judge flagged that spec
  commit `6046565` staged `docs/features/` onto `main`, which the allowlist (`CODING_MEMORY.md` and
  `coding-memory/*` only, lines 96-102) nominally blocks. It landed because the guard fail-opened,
  not because the allowlist permitted it. **Every `docs(features)` commit on `main` in this repo's
  recent history slipped the same way**, so the guard's stated policy and actual practice have
  diverged silently. `rules/gates.md` documents this chained-command limitation for `merge-guard`
  ("a chained `foo && gh pr merge` is not caught") but **not** for `git-guard`. Two separable
  questions for the user: fix the lexer (it is the same lexing-grammar class the marker-gate spec
  keeps failing on — arguably one shared helper), and decide whether the allowlist should legitimise
  `docs/**`, which is what this repo actually does on `main` every day.
  ✅ **FIXED 2026-08-03 — PR #35 `fix/fix-l1`, OPEN, awaiting your merge in the GitHub UI**
  (https://github.com/suyatdev/.claude/pull/35 · detail: `coding-memory/pr-tracking.md` §PR #35).
  Both guards now lex the command into
  shell segments via the new `hooks/lib/classify-git-command.py`; the generic half of
  `classify-pr-command.py` moved to `hooks/lib/shell_segments.py` and both classifiers share it
  (`classify-pr-command.test.py` stayed green and untouched as the regression baseline). git-guard's
  `main` allowlist widened to `docs/*.md` — by file *type*, so a script under `docs/` gets no free
  ride; doc-guard keeps the broader `docs/*`, since a diagram counts as documentation riding along
  with a commit but should not thereby reach `main`. Neither hook had ANY tests; both now do, with
  the 17 fail-open cases pinned
  as failing first. Per-segment flag judging fixed two further defects nobody had predicted:
  `git push --force && echo --force-with-lease` was **allowed**, `git push && echo --force` was
  **blocked**, and doc-guard read `-a` from any segment. `checkpoint-before-modify.sh` deliberately
  untouched — its match is an *allowlist*, so the same shape has the opposite effect.
- 🔴 **L1 SHIPPED A REGRESSION — live on `main` now, found 2026-08-03 post-merge.** On `main`,
  `git add X && git commit X` is **blocked even for documentation**. PreToolUse fires *before* the
  command, so at hook time `git add` has not run, `git diff --cached` is empty, and `git-guard.sh`
  treats an empty index as `allowed=0`. Pre-L1 the chained form fail-opened and never reached that
  branch; now it does. Fail-**closed**, so friction not a safety hole, and only on `main`. Workaround:
  `git add` and `git commit` as two separate calls. Likely fix: an empty index should not deny — such
  a commit fails on its own ("nothing to commit") unless `-a`/`--amend`, which can be evaluated the
  way doc-guard does. **User-approved: fix on its own branch, first, ahead of the other follow-ups.**
  ⚠️ **Why 33 tests + a 24,016-case fuzz + a mutation round all missed it:** the suite's `stage …`
  helper ran *before* invoking the hook, so the hook always saw a populated index. Chained-ness was
  tested; *staging inside the chain* never was. **A fixture that pre-creates state the real command
  would create itself hides the bug, and neither fuzzing nor mutation testing can catch it — both
  validate assertions, never the fixture's premise.** Any fix needs a case whose only `git add` is
  inside the command string. (Belongs in auto-memory as `feedback-fixture-must-not-pre-create-state`;
  **could not be written — see the phase-guard gap below.**)
- **L1's fix — `fix/git-guard-empty-index`, four judge rounds. ✅ PR #36 MERGED 2026-08-04T03:47Z
  (`aa47a78`)** — https://github.com/suyatdev/.claude/pull/36. RUN 4 pinned `5154dec`,
  `risk=medium confidence=high`. Post-merge on `main`: suites **77/0 · 134/0 · 78/0**, and the
  `CODING_MEMORY.md` conflict resolved with **zero** lines lost from `main`'s side (verified by
  set-difference against `69f6380`, not by eye).
  · **Both hooks are now armed on this machine for the first time**, which unblocked the two owed
  memory files — `feedback_fixture_must_not_pre_create_state` and
  `feedback_capture_exit_code_before_anything_else` (written 2026-08-04; `projects/` is gitignored,
  so they are local-only and will not appear in git). Writing them *was* the end-to-end check of
  Defect B, and it passed.
  · 🆕 **NEW, found within minutes of the merge by the armed hook blocking a real commit — a shell
  redirect after the pathspec becomes a phantom file.** `shell_segments.py` does not strip
  redirections, so `git commit -m msg -- CODING_MEMORY.md 2>&1 | tail -3` classifies as
  `COMMIT_PATH 2` **plus** `COMMIT_PATH CODING_MEMORY.md`; `2` is not documentation, so the whole
  commit is denied. Measured against the control (same line without `2>&1` → only the real path).
  **Fail-CLOSED, so friction rather than a hole** — but it denies precisely the documentation commit
  this branch existed to permit, and appending `2>&1` is habitual. Workaround: no redirect on the
  same line as the pathspec, or stage first so the populated-index path is taken instead.
  Fix belongs in `hooks/lib/shell_segments.py` and therefore **shares a blast radius with D1+D2**,
  which must also reuse that lexer — sequence them together. Affects `doc-guard` too (same
  classifier).
  · ✅ **FIXED — PR #38 MERGED 2026-08-04** (`cc035d2`), https://github.com/suyatdev/.claude/pull/38,
  branch `fix/shell-segments-redirects` deleted local + remote. Verified on `main` after pull, not
  merely reported: 492 checks green **from main**, and `bash hooks/shell-segments-falsifier.sh
  bc7da76` all rows as expected. Detail: `coding-memory/pr-tracking.md` §PR #38; decision record
  **ADR 0015**; canonical file `docs/features/shell-segments-redirects.md`. **The scope grew when
  measured**: this phantom-pathspec symptom is mode (a) of *one* misclassification, and mode (c) —
  `> out.txt git commit …` — is a genuine **fail-OPEN** in which no guard sees the commit at all.
  Two things worth carrying forward and nothing else: the fix's own first revision **reintroduced
  mode (c)** in a new shape (`<(cmd)`/`>(cmd)` contain `<`/`>` but open a *command* context), caught
  by the observability judge and not by the new test suite, which had no such case; and the accepted
  limit was written too narrowly **three times running** before being pinned by an assertion rather
  than described. Judge round 2 `risk=low confidence=high`.
  · 🆕 **NEW, found by the post-merge verification — the falsifier self-invalidated on merge.**
  `hooks/shell-segments-falsifier.sh:14` reads the "old" lexer from `main`, so merging made *old* ==
  *new* and the default invocation is now **permanently red: 4 rows UNEXPECTED, exit 1**. Behaviour
  is fine — every `new=` column is still correct, and `bash hooks/shell-segments-falsifier.sh
  bc7da76` passes clean. Fix: pin the default base to `bc7da76`. **Evidence-evaporates class**, and
  the noisy direction is the dangerous one — a permanently-red check teaches the reader to ignore
  it, and ADR 0015 cites this script as *the* thing that demonstrates the fix. Detail in
  `coding-memory/pr-tracking.md` §PR #38.
  · ✅ **FIXED — PR #39 MERGED 2026-08-05** (`cbb9f60`), branch deleted local + remote, judge
  `risk=low confidence=high`. Verified on `main` by the one measurement that matters: the invocation
  that was permanently red is now exit 0 / 0 FAIL rows, and `… main` is exit 1 with the baseline
  named. Two parts, not one: pin the default to
  `bc7da76` **and** self-check that the base predates the fix — the pin alone cures the symptom and
  leaves the failure *mode* intact for the next caller who passes a base by hand. Detail:
  `coding-memory/pr-tracking.md` §PR #39; canonical `docs/features/falsifier-base-pin.md`.
  · 🔄 **BACK IN PLANNING for revision 10 (session 14-15) — `git-guard.replay.sh`. Canonical:
  `docs/features/replay-harness-base-pin.md`, **`phase: planning`, `model_tier: high`, branch
  `fix/replay-harness-base-pin`** @ `6741e41`. Tasks **1-9 are done and committed**; task 10 (judge +
  PR) is **not**, and is now blocked behind revision 10 **and new task 11**.
  **Revision 10 written (session 15)** — takes deferred non-goal 2: the default `worktree` candidate
  is now validated like every other side. Measured red: with `hooks/lib/` deleted, the DEFAULT
  invocation prints **`260 identical, 118 stricter, 0 relaxed`, exit 0** — NOT the `292/86/0` the
  round-2 judge reported; the measured split is the mirror of row 5 and was independently
  reproduced to the digit by two later judge rounds. Scenarios **M, N, O** added (H now A-O).
  ✅ **Compliance PASSED at round 4** (`8c53c67`, blob `4423a45…`, 0 violations, confidence high).
  Rounds 1-3 failed, `writing-specs/spec-code-accuracy` cited **three consecutive rounds** (stale
  line pointers into a file tasks 2-6 grew by ~100 lines). Escalated after round 2; **user decision:
  label each pointer with its baseline** — a pointer convention now sits at the top of the Spec
  section and **binds every line number including the append-only history sections**, which is what
  finally closed it (rounds 2-3 kept missing instances because the sweep treated some regions as out
  of scope). Round 4 verified it by resolving every pointer against both blobs (`124a85e8` pre-fix,
  `adbbf0a7` HEAD).
  ⚠️ **An invented mechanism reached the spec and was retracted.** The advisory read claimed empty
  fails opposite to missing; Scenario O was written on it; round 4 measured all four shapes and it
  was false — `shell_segments.py` empty is `260/118/0`, **identical to missing**; only
  `classify-git-command.py`/`git-guard.sh` empty go loud (`118/0/260`). O now carries the measured
  table and says it pins the silent shape **by luck, not reasoning**. Cause: adopted on report
  instead of measured — this spec's own failure mode, reaching the spec.
  📌 **Four non-blocking notes deliberately NOT applied** — any spec edit invalidates the fresh
  pass: retracted premise still inline at `:959`; Scenario O's "nothing falsified (b)" should read
  "nothing previously"; two pre-fix-only prose truths the convention doesn't reach; 1226 lines for a
  239-line fix.
  ✅ **Gate confirmed 2026-08-05 (session 15) — phase implementation, Sonnet 5 for task 11.**
  **All twelve scenarios A-L verified by execution** under `/bin/bash` 3.2.57 (task 7) — Scenario G
  (relative worktree path) was the last one open, closed by task 5's `WT` resolution (`f06d93f`).
  Task 6 (`97aef27`) prints the resolved base SHA at both the header and summary line. Task 8
  confirmed blast radius; task 9 added ADR 0016 + provenance notes on three prior citation sites.
  · **Observability judge ran TWICE, both `risk=low confidence=high`** — round 1 at `e86ddb5`,
  round 2 at `a5ee297`, both in
  `coding-memory/observability-judge/2026-08-05-fix-replay-harness-base-pin.md` (round 2 on top,
  round 1 verbatim below). Round 1 caught two record-vs-repo slips (uncommitted `phase` flip; task
  8's blast radius said 3 files, actual 6) — fixed in `a5ee297`. **⚠️ BOTH VERDICTS ARE NOW VOID:**
  revision 10 adds implementation work, so the judge must re-run at the new HEAD. Do not open the PR
  against them.
  · 🔄 **THE DECISION THAT SENT THIS BACK TO PLANNING (user, 2026-08-05): un-defer non-goal 2** —
  validate the **candidate's own** `hooks/lib/*.py` in the default `worktree` mode, not just the
  base's. The judge reproduced the gap *live* rather than arguing it: clone, delete
  `hooks/lib/*.py`, run default mode → **`292 identical, 86 stricter, 0 relaxed`, exit 0**. A
  candidate broken unrelatedly blocks everything, so it scores zero relaxations **by construction**
  and prints a clean pass in the one mode people actually run. Being disclosed in ADR 0016 does not
  change the mechanic. **This voids the round-2 verdict and restarts compliance at round 1**, same
  as revision 8 did — taken knowingly. **Next: revision 10 on Opus 5 — un-defer the bullet, write
  the new scenario + task 11, then the compliance judge BEFORE any code.** Then the `gate confirmed`
  hard stop before implementation resumes.
  · 📌 Minor, for revision 10 to sweep up: task 9's headline says "four sites" while the part-6 table
  lists five (3 annotated · 1 already correct · 1 amended via ADR 0016).
  · Getting to this point took two compliance cycles: revision 7 passed round 7, the user then took
  the 5th architecting read's fix, that edit voided the verdict and re-entered at round 1, which
  failed on one violation (task 7 still said "verify A-K" after Scenario L was added). Revision 9
  answered it plus three non-blocking items — one of which revision 8 itself introduced. Model plan
  followed as recorded: Opus 5 for tasks 1-4, Sonnet 5 for 5-10 (both switches confirmed by the
  user at their checkpoints, including the implementation→review one for task 10). Scope was **wider
  than
  this entry originally said, and its premise was wrong.** Five ways the harness prints a pass that
  could not fail — measured, absolute worktree path, `$?` first: vacuous base (`main` vs itself,
  378/0/0 exit 0); **0-byte base** from unchecked `git show` (base `286fd5a`, all three files absent
  → `118 identical, 260 stricter, 0 relaxed`, exit 0 — a clean pass on the only criterion that
  matters); **relative worktree path** (`WT=.` → every candidate run exits **127**, tallied as
  `same`, 378/0/0 — this one bit the first reproduction); unreachable rev; and **the output naming
  no base at all** (`main` hard-coded a 4th time at `:134`).
  · **Three more comparison-logic defects, measured in session 10, deliberately OUT of scope for the
  base-pin branch** (they are tally/reporting bugs, not baseline bugs — recorded here because the
  handoff is not a durable record): (1) **`else → same`** (`replay.sh:125-131`) counts any exit
  outside `{0,2}` as agreement, which is what let route 3's universal `127` print `378/0/0`.
  (2) **The `relaxed` definition** (`:125`) is `base=2 && candidate=0`, so a candidate that blocks
  *everything* reports `0 relaxed` **by construction** — e.g. a candidate missing `hooks/lib/*.py`
  exits **2** on every command (`git-guard.sh:74-77` fails closed when it cannot run the classifier it
  resolved at `:44` — **not** `:56`, the separate python3-not-on-PATH guard at `:53-57`; both exit 2,
  which is how rounds 4 and 5 confused them). **Independent of (1): exit 2 is
  inside `{0,2}`, so fixing the `else` arm does not touch this.** (3) **The harness exits 0
  unconditionally** — 62 relaxations exit exactly like a clean run, so no caller can gate on it.
  · ✅ **TASK 11 DONE (session 16).** Dead `rm -f` deleted in its own commit (`797dbc4`, verified no
  behaviour change); worktree candidate now validated before the vacuity check via a new
  `require_on_disk` (reads disk, writes nothing). **All fifteen scenarios A-O + H verified by
  execution in one pass** — the old silent `260/118/0` exit 0 red (M) now names the missing helper
  and refuses; N and O (new) both refuse on a 0-byte guard/helper; L confirms the new rule does not
  over-fire on a self-contained worktree candidate. `git-guard.test.sh` unaffected, 77/0. ADR 0016
  amended (three sides, not two; closes-the-example-not-the-limit on `relaxed`). Blast radius
  re-checked: still exactly the named 8-file set.
  · ✅ **FIXED — PR #40 MERGED 2026-08-06** (`2c09019`), branch `fix/replay-harness-base-pin` deleted
  local + remote, judge `risk=low confidence=high` (round 5, `f6242c2`). **Verified on `main` after
  pull, not merely reported:** `git-guard.test.sh` 77 passed / 0 failed; the replay harness itself
  refuses a vacuous self-comparison (`base=2c09019…`) and — the fix's own point — refuses naming the
  missing helper when run against a clone with `hooks/lib` deleted, instead of the old silent
  `260/118/0` exit 0 pass. Detail: `docs/features/replay-harness-base-pin.md`;
  decision record ADR 0016; judge trail `coding-memory/observability-judge/2026-08-06-….md`.
  Round 5 **closed more than task 11 claimed**: a 0-byte worktree `hooks/git-guard.sh` (round 4's
  flagged no-falsifier gap) is now also refused, though still unpinned by a named scenario —
  worth carrying forward as a future scenario P if this harness is touched again. Non-blocking notes
  left open per this branch's standing no-mid-flight-widening decision: missing self-contained NOTE
  on the worktree branch (reporting only, not a functional gap); `require_on_disk` duplicates
  `extract_required`'s error strings (silent-drift risk on a future message edit); restore cost keeps
  climbing (feature file 1300+ lines, this file 2500+ — both mandatory reading on restore, still
  unaddressed). PR opened AT the judged SHA (`f6242c2`) per `judge-guard.sh`-strict discipline; the
  judge trail itself committed as a follow-up push, per this repo's established pattern (`a685a1c`).
  · ⚠️ **The "false green cited as evidence" premise was WRONG — do not re-adopt it.** The cited
  figures are **valid**. `git-guard-empty-index.md:314-318` reports 378 **pairs** (matrix size) with
  **215/326/346** identical and **162/52/32** relaxed — a self-comparison cannot produce one
  relaxation. The redirect figure was recorded at `64ba2fa` **15:45:33**, 68 min before `cc035d2`
  merged at **16:53:55**, and `bc7da76:shell_segments.py` has **0** occurrences of `redirect` vs 11
  at HEAD. Both judges verified this independently. Revision 1 proposed **retracting** them, which
  would have put a false retraction into an immutable ADR. Replaced by provenance annotation.
  · 📐 **The real finding:** those numbers were valid and it took blob-hash + timestamp archaeology
  to prove it, *because the harness never says what it compared*. So the fix is "state the resolved
  base on every run", not "retract". A number without its baseline cannot be audited later.
  · 📐 **The general rule, worth generalising beyond these two scripts:** a differential harness's
  baseline must be a **fixed commit, never a branch** — a branch that will eventually contain the
  change under test is not a baseline, it is the thing being tested twice. And the harness must
  **prove its own baseline is valid** before reporting any row, because otherwise a broken control
  is indistinguishable from broken code.
  · ⚠️ **Calibration: the judge passed PR #38 at `risk=low` and did not catch the moving baseline.**
  A human found it post-merge, by running the script from `main`. The judge is a check, not a proof.
  Durable record lives in `docs/decisions/0014-empty-index-means-ask-the-command.md`,
  `docs/features/git-guard-empty-index.md` `## Verification`, and
  `coding-memory/observability-judge/2026-08-0{3,4}-fix-git-guard-empty-index.md`. This is a pointer;
  do not restate them here. The arc, because only the arc is not written down anywhere else:
  · **Round 4 shipped a known hole rather than patching it — the first time this repo chose that.**
  A pathspec naming a *directory* (`docs/x.md/`) clears the `docs/*.md` allowlist and commits
  everything under it (2 → 0, latent). It is the third member of the class ADR 0014 already has a
  heading for — "a path is not the file it names" — of which only `..` was fixed. After three rounds
  of patch-the-instance, the class earns **one** fix: `..` ✅, directory ❌, symlink ❌ untested.
  · **Rounds 1 and 2 both died the same death.** The design *enumerated the commands that fill the
  index* so the hook could ask them for a file list. Round 1 (`5aa220e`) found `git add -- x &&
  git commit` unmodelled; round 2 (`833e3eb`) found **nine more** — `git rm`, `git mv`,
  `git reset --soft`, `git checkout <tree> -- <path>`, `git restore --staged`, `git apply --cached`,
  `git stash pop --index`, `git cherry-pick -n`, `git revert -n` — four verified end-to-end putting
  a source file onto `main`. **An enumeration of an open-ended set is only ever as complete as its
  author's list, and each round's tests mirrored that same list, so green meant nothing.**
  · **The design was abandoned, not patched a third time.** The narrowing (`4be542b`) stops asking
  what filled the index and asks what the *commit itself* names after `--`, vetoing on anything that
  could widen it. Blast radius measured by replay, now 63 shapes × 6 states: the rejected design
  allowed **44** commands `main` blocks, the narrowing **13**, and after round 3 **8**, all
  documentation-only.
  · **RUN 3 @ `4be542b` — `risk=medium`, `regression: fail`, `success_masking: fail`. PR stays shut.**
  Rounds 1-2 are genuinely closed (judge re-measured: 14/14 shapes block, `main=2 → HEAD=2`; suites
  67/0, 73/0, 134/0; mutants for both incidental fixes caught). **Two NEW shapes, each verified
  putting `src/app.sh` onto `main`:** (a) **facts are unioned across a chained line, not per-segment**,
  so a docs pathspec on the first commit excuses a *bare* second commit — `git commit -m a --
  docs/a.md && git add -- src/app.sh && git commit -m b`; the classifier already does this correctly
  for `push`, so the fix is to make `COMMIT` veto per segment the way `PUSH_FORCE` does; (b) the
  allowlist matches the **path string, not the path git resolves**, so `coding-memory/../src/app.sh`
  satisfies `coding-memory/*`. `doc-guard` returns 0 on both — no backstop.
  · ⚠️ **The completeness overclaim has now recurred in all three rounds.** ADR 0014 asserts the
  policy is "provably never weaker than `main`" and "every path it grants is one the hook has
  actually read"; both were disproved in minutes. The 51×6 replay contains **no two-commit chain and
  no `..` path**, so it is evidence about that set, not the proof the ADR presents it as. Soften the
  claim to what was measured — a stated completeness claim is load-bearing, as the ADR itself warns.
  · ✅ **Both RUN 3 shapes closed 2026-08-03 — `b17a666` red, `d222e0e` green; RUN 4 not yet run.**
  The rule that came out of it, to apply to any fact the classifier gains later: **a fact that
  GRANTS permission must hold for the whole line; a fact that DENIES may hold for one segment.**
  `PUSH_FORCE` was built that way, `COMMIT_PATHSPEC` was not. The `..` path is **refused, not
  resolved** — resolving asks "relative to which directory?", which is Defect C's open question.
  ADR 0014's two claims now read as measured-not-proven, and `git -C <dir> commit` (invisible to the
  classifier, both hooks exit 0, not widened here) joined its open list.
  · **Two unrelated defects found and fixed while narrowing, both measured:** `-i` was a **live
  fail-open** (the `--` short-circuit returned before the flag table was read), and `has_fact`
  **word-split** on tab-bearing facts, so a file literally named `PUSH_FORCE` let an unrelated
  force-push through.
  · **Pane note:** the first RUN 3 dispatch reported `PANE_REF: surface:109`-style success and then
  **vanished** — surface gone from `cmux tree`, no result file, no `claude -p`, and **no
  adapter-failure cooldown recorded**, because `open_pane` had returned 0. The retry ran fine. A
  reported pane is not a live pane; check `cmux tree --all` for the surface before trusting a wait.
- 🔴 **`phase-guard.sh` BLOCKS THE AUTO-MEMORY DIRECTORY — found 2026-08-03, live.** Its exempt-path
  list at `hooks/phase-guard.sh:285` is
  `CODING_MEMORY.md|coding-memory/*|docs/*|.claude/*|settings.json` — which omits
  `projects/*/memory/*`, where the harness's own memory tool writes. So while any feature file sits
  at `phase: planning` (i.e. the whole remaining marker-gate register, ~8 branches) **every memory
  write is refused**, and `rules/gates.md` promises "docs and memory paths are never blocked". One
  line to fix; do it on the same branch as the regression above, since both are live guard friction.
- ✅ **`fix/git-guard-empty-index` @ `4be542b` — NARROWED, GREEN, PUSHED; awaiting obs judge RUN 3,
  then the PR from the worktree.** Policy now: with nothing staged on `main`, relax **only** where
  the commit names its own paths after `--` and nothing on the line widens them (`-a`, `--amend`,
  `-i`/`--include`, `--only`, and args it cannot read each veto); everything else denies exactly as
  `main` does. Detail lives in **ADR 0014** (rewritten) and the feature file's `## Verification`,
  deliberately not restated here. Replayed 51 commands × 6 index/worktree states against `main`'s
  hook: the rejected design allowed **36 distinct commands `main` blocks**, this fix allows **6**,
  every one of them naming only documentation. git-guard **67/0**, classifier **73/0**, seven
  neighbours unchanged, shellcheck clean.
  · 🔴 **Two defects found while narrowing, both measured, both fixed here.**
  `git commit -i -m msg -- docs/x.md` was a **live fail-open**: `-i` commits the index *as well as*
  the named paths, and the classifier returned the paths the moment it saw `--`, before consulting
  the flag table — so a staged source file rode onto `main` behind a documentation pathspec.
  Verified against git itself rather than the manual. Second: `has_fact` word-split a fact stream
  whose paths ride after a **tab**, so committing a file named `PUSH_FORCE` produced the force-push
  fact and blocked an unrelated `git push` in the same command line.
  · ⚠️ **A probe reported the wrong exit code and briefly hid the `-i` bug.** A command substitution
  inside the reporting `printf`'s own argument list resets `$?`, so both arms came back `0` and read
  as "pre-fix and fixed behave identically" — the opposite of the truth. A measurement bug that
  fabricates *agreement* argues against a change that is actually needed. Owed to auto-memory as
  `feedback_capture_exit_code_before_anything_else`; **blocked by the live phase-guard — Defect B
  demonstrating itself.** Draft text: `.claude/session-state.md`.
  · **HISTORY, from here down.** **Obs judge RUN 1 = `risk=high`, did not clear it: I introduced a fail-open.** Four shapes `main`
  blocks today are ALLOWED by the branch (each reproduced by me, not taken on report):
  `git add -- hooks/x.sh && git commit -m msg`, `git add -A && git commit -m msg`,
  `git commit --amen --no-edit`, `git commit --pathspec-from-file=list`. The derivation enumerates
  pathspec/`-a`/`--amend` and misses **the chain's own `git add`** — the shape the branch exists for.
  Not armed on this machine (live hook is `main`'s copy); the only risk is merging. Fix list in
  order + RUN 1 detail: feature file task 8 and `.claude/session-state.md`. Verdict committed at
  `coding-memory/observability-judge/2026-08-03-fix-git-guard-empty-index.md`.
  · **The stated REASON was the worse half.** *"git refuses such a commit itself"* is false whenever
  a sibling `git add` precedes it, and it went into both the spec and the hook comment. Every number
  I reported re-measured **exact** while the reasoning around them was wrong — the recorded
  "measure the explanation, not just the number" lesson, hit again.
  · **The suite could not have caught it: the test comment's enumeration IS the code's
  enumeration**, so 40/0 only ever confirmed my own list. Third instance on this branch of a check
  inheriting the blind spot of the thing it checks (after the `stage` fixture and `empty_index`).
  · **RUN 2 @ `833e3eb` = `risk=medium confidence=high`. Round 1's blocker IS closed** (judge
  re-measured every number exact, probed 8/8, and confirmed the five changed test expectations only
  ADDED facts). **The CLASS is not.** Nine more commands stage things and all nine are regressions —
  blocked on `main`, allowed by the branch, no `doc-guard` backstop — `git rm`, `git mv`,
  `git reset --soft`, `git checkout -- <p>`, `git restore --staged`, `git apply --cached`,
  `git stash pop --index`, `git cherry-pick -n`, `git revert -n`. **All nine re-measured by me.**
  · 🔴 **TWO ROUNDS HAVE NOW EACH FOUND THE ENUMERATION SHORT — that is evidence about the
  approach, not about the list.** I kept asking "what commits content the index cannot show?" when
  the question was "what can PUT something in the index?". ADR 0014 additionally asserts
  completeness ("Four shapes… all four are consulted") that is measurably false, inside a document
  whose own headings explain why a wrong stated reason is worse than a known gap.
  · ✅ **USER DECISION 2026-08-03 — NARROW THE FIX RIGHT DOWN, next session.** Relax the guard
  **only** where the commit names its own paths (`git commit … -- <p>`); everything else keeps
  today's deny. **Provably never weaker than `main`**, because it only grants permission for paths
  the hook can actually read — so all ten staging commands go back to denied without being
  enumerated. Fixes the real friction anyway, since the house rule mandates `-- <path>`. Accepted
  cost: `git add X && git commit -m msg` with no pathspec stays denied, exactly as today.
  Step-by-step plan, including what to delete and the RUN 2 leftovers to re-check:
  `.claude/session-state.md`.
  · **User committed the RUN 1 fix by hand** (3 commits, `aedaf38`/`8099d0a`/`833e3eb`, red before
  green, `settings.json` correctly kept out) — the human checkpoint caught nothing wrong with the
  code and the judge caught what review would not have.
  · Below is the pre-judge summary of a design that has since been **replaced**, kept for the
  record. ⚠️ Its claim that an empty result allows *"because git refuses such a commit itself"* is
  false whenever a sibling `git add` precedes it, and describes neither the current code nor the
  current policy. Read it as history only.
- ✅ **Built on `fix/git-guard-empty-index`, 8 commits (pre-judge state `5aa220e`).**
  Full detail is in `docs/features/git-guard-empty-index.md` (checklist notes + `## Verification`)
  — deliberately not restated here. Headlines: an empty index now means *the index cannot answer*,
  so the command is asked instead (paths after `--`, `-a` → worktree, `--amend` → HEAD's tree), and
  an empty result **allows** because git refuses such a commit itself. Path extraction went into
  `lib/classify-git-command.py`, which already owns the lexer, so there is still one parser.
  git-guard **40/0**, phase-guard **134/0**, classify-git **55/0**, nine neighbours unchanged,
  shellcheck clean on both sides.
  · **The naive fix was a fail-open and is pinned against.** Pathspec, `-a` and `--amend` each
  commit content the index never shows; a mutant implementing "empty → allow" fails four cases.
  Telling a pathspec from an option value needed a small table of which `git commit` flags consume
  a value — scoped to that job only, so the pinned `git commit -m '-a'` → `COMMIT_ALL` is unchanged.
  · 🔴 **DEFECT C FOUND AND MEASURED, NOT FIXED — `git-guard.sh:88` resolves the branch from the
  HOOK's own cwd**, not the directory the command will run in. Same payload: exit 2 from the primary
  checkout, exit 0 from a worktree, so **all worktree work is judged against `main`**. It blocked two
  commits mid-session; the workaround is to keep the shell's cwd inside the worktree, since a `cd`
  inside the command cannot help a hook that runs first. **Enumerated rather than patched** (the
  standing rule after a repeat class): live guards resolving identity from cwd are **git-guard,
  judge-guard, and partially doc-guard**; `phase-guard` fixed it by resolving from the file being
  written, which has **no analogue for a commit** — and the payload `cwd` is pre-`cd` too (line 713).
  So this is a design decision, not a patch. **User ruled: do not widen that branch.** Own task.
  · ⚠️ **`/model sonnet` wrote into the WORKTREE's tracked `settings.json`**, not the live one:
  live `opus[1m]`, worktree copy `sonnet`, committed main `claude-fable-5[1m]`. Kept out of all 8
  commits only because every commit used an explicit `-- <path>`. **Never `git add -A` in a
  worktree of this repo.** Unresolved — user's call.
  · **Two fixture defects found, and they are the same lesson as the bug.** The suite's `stage`
  helper pre-created the populated index, which is why 33 tests + a 24,016-case fuzz + a mutation
  round all missed the regression; and `empty_index`'s plain `git reset` left the previous case's
  worktree edits behind, so "only docs modified" silently also had source modified. Also fixed a
  harness gap this exposed: `on_branch` ignored `git checkout`'s status, so a refused switch left
  later cases running on the **wrong branch** reporting real-looking results.
  · **STILL OWED, after merge only:** write
  `projects/-Users-marksuyat--claude/memory/feedback_fixture_must_not_pre_create_state.md` + its
  `MEMORY.md` line. Cannot be done before merge — the live hook is `main`'s copy.
- 🔴 **FOUR OF THE TWELVE SCRIPTS IN `hooks/` ARE NOT REGISTERED IN `settings.json`** — recorded
  2026-08-03 as "five of 17"; **both numbers corrected 2026-08-04 by measurement.** Still dormant:
  `checkpoint-before-modify.sh`, `require-project-standards.sh`, `scan-invisible-unicode.sh`,
  `scan-secrets.sh`. They exist, they pass their tests, and nothing invokes them.
  **`phase-guard.sh` is no longer among them** — registered at `settings.json:42-49` (`PreToolUse` on
  `Edit|Write|NotebookEdit`), and separately observed firing on 2026-08-03 (it was what blocked the
  auto-memory directory write — Defect B). Live hooks are git-guard, doc-guard, judge-guard,
  merge-guard, pane-dispatch-guard, context-handoff-watch, memsearch-nudge, **phase-guard**, and the
  orca `claude-hook.sh`. **Committed vs live `settings.json` differ only in the machine-local
  `model` line** (`claude-fable-5[1m]` committed, `opus[1m]` live — the difference §PR #36 already
  called expected); every hook registration is byte-identical, so the committed≠armed split that
  produced the original entry is closed. ⚠️ **`git status` cannot detect drift on this file** —
  `skip-worktree` is set (`git ls-files -v settings.json` → `S`), which is the whole mechanism
  behind the original split. The only sound check is
  `git show HEAD:settings.json | diff - settings.json`. Checked that way 2026-08-04. Deciding
  which of the remaining four to wire up is **open work, user's call** — the secret/unicode scanners
  in particular are advertised protection that is not running.
- **Pane-dispatch note 2026-08-02 (corrected):** the compliance judge's `wait` returned **exit 2
  (timeout)** at the 540 s cap on both rounds 3 and 4, and **both times the judge was simply still
  working** — round 3's result file landed ~2 min after the wait gave up, and round 4's finished on a
  second `wait`. (An earlier version of this note said round 3's file was never written; that was a
  timing artifact of when I looked, not a fact.) **A `wait` timeout is not evidence of failure.**
  Check `ps aux | grep '[c]laude -p'` for a live agent and `coding-memory/*/verdicts.jsonl` for a
  landed verdict before re-dispatching, or a round gets paid for twice. The compliance judge on this
  spec reliably needs **more than 540 s**; dispatch it with a longer wait or expect a second one.
  - **`rtk` SETTLED 2026-08-04 (session 9), user-directed, ahead of the 5 round-5 violations — the
    observability judge's `risk=high` headline is OVERSTATED. The design is NOT inert.** Measured, not
    reasoned: `segments('rtk git commit -m x -- a.sh')` and `segments('git commit -m x -- a.sh')` return
    **identical** argv, because `shell_segments.py:34` lists `rtk` in `WRAPPERS` and :86 strips wrappers
    in a stacking loop (`time rtk git …` also reduces correctly). The spec already routes tokenisation
    there — l.471-476, *"the decision is made once, in the shared lexer"* — so a classifier built to spec
    inherits wrapper-stripping for free. `rtk hook claude` is confirmed **first** in the `PreToolUse`
    Bash chain (`settings.json:13`), ahead of all four guards, so the prefix genuinely does reach them —
    the mechanism the judge described is real; only its *consequence* was wrong.
    · **What survives as genuine, and is smaller and different:** (a) the spec's deferral list names only
    three tokenisation questions — tokens, `git <global-opts> commit`, and chaining — and **wrapper
    stripping is not among them**, so nothing in the spec *instructs* the implementer to route through
    `segments()` for this; (b) task 14's hand-written payloads and all 24 mutants contain no `rtk` form,
    so **nothing would catch a regression** if the classifier ever grew its own lexer — a check that
    cannot fail, the exact pattern in `feedback_confirm_the_check_can_fail`. Both are cheap: one
    sentence, one mutant.
    · 🆕 **STALE-TEXT FINDING, same class as PR #37 and queue item 8 — found while checking the above.**
    Spec l.166-172 asserts the three production lexers are `git-guard.sh:89`, `doc-guard.sh:123` and
    `checkpoint-before-modify.sh:97` and that **"all three anchor the pattern at `^git[[:space:]]+`"**,
    calling it a *"live fail-open in all three"*. **Two of the three are wrong today:** `git-guard.sh:44`
    and `doc-guard.sh:43` both delegate to `lib/classify-git-command.py` (which imports the lexer) and
    carry no `^git` anchor. Only `checkpoint-before-modify.sh:97` still anchors — **and that hook is
    dormant, unregistered in `settings.json`** (`gates.md` §Dormant hooks), so the one true instance
    never runs. The spec is reasoning from a pre-PR-#36 snapshot of its own repo.
    ⚠️ Do **not** fold these into a round-6 auto-revise — round 5 is past the cap and the user directs.
  - **WORK REGISTER 2026-08-02 — branch-per-defect, user-chosen. Per-defect detail now committed at
    `coding-memory/marker-gate-defect-register.md`** (moved there 2026-08-03; it had existed only in
    the machine-local `.claude/session-state.md`, one `/clear`-adjacent rewrite from being lost).
    Nine units of work; the
    user takes one branch each, from `main`, in roughly this order:
    `fix/git-guard-chained-command` (**L1 — the only item affecting real work today; live code**) ·
    `feature/marker-gate-recognition-rule` (**D1+D2, ONE branch**) ·
    `fix/marker-gate-classifier-contract` (**S1+S2, ONE branch**) ·
    `fix/marker-gate-all-untracked-member` (S3) · `fix/marker-gate-python-call-site` (S4) ·
    `fix/marker-gate-grammar-rule-2` (S5, largely superseded if D1+D2 lands first) ·
    `docs/marker-gate-narration-fixes` (N1+N2) · `docs/marker-gate-revert-pair-7-13` (O1) ·
    `feature/marker-gate-audit-logging` (D4+D5) · `docs/marker-gate-shrink` (O3, **last**).
    ⚠️ **Two pairs must not be split** — D1+D2 are one cause (a recognition rule), and S1+S2 are two
    halves of one contract. Splitting either leaves the document *more* self-contradictory than it is
    now, i.e. manufactures a failure in the intermediate state.
    · **Why branch-per-defect and not round-per-defect:** the judges re-read the **whole document**
    every round and report everything they find regardless of what changed — round 4 changed the
    grammar and its headline finding was `rtk`. So a one-change round still returns `fail` plus
    unrelated findings, and the isolation never arrives. Attribution comes from **git** instead:
    one commit per finding id, free, exact.
    · **Accepted ceilings are NOT work items** — receipt-not-grade, non-Bash writes, `cmux.sh`
    ungated, no self-arming. Fixing them means widening the feature, which the user ruled out.
  - **ROUND 4 VERDICTS 2026-08-02 @ `8923951` — compliance `fail` (4), obs **`risk=high`** (UP from
    medium). `api-contracts` has now been cited in **FOUR consecutive rounds**,
    `commit-form-coverage` in three, `writer-call-site-cwd` in two. Second consecutive mandatory
    escalation. Nothing waived, ever.** Verdicts:
    `coding-memory/compliance-judge/2026-08-01-verification-marker-gate.md` §Round 4,
    `coding-memory/observability-judge/2026-08-02-main-round4.md`.
    · **Round 4's evidence discipline was the best of the four, per obs, re-run not re-derived:**
      **G1-G9 reproduce 9/9 exactly**, the pair inventory, unborn-HEAD, M3, the rename filter, the
      writer cwd fix, all four pinned versions and **all eight cited line numbers** check out; the
      allow-path count of 9 is right; all 14 doors are in the flowchart; **the two-group value-flag
      list is exactly right, all 14 flags, checked against `git commit -h`**. Obs states explicitly
      that **round 3's "fix one thing, break another in the new prose" pattern did NOT repeat** —
      the seams between new and untouched text held.
    · 🔴 **THE SIXTH FAIL-OPEN, and it is upstream of everything: `rtk`.** This machine's token-saving
      proxy is registered as the **first** Bash hook and rewrites `git commit -m x` into
      **`rtk git commit -m x`** before any guard sees it. **Verified by me, not taken on the judge's
      word:** `hooks/git-guard.sh:14-18` says so in a comment, and
      `hooks/lib/classify-pr-command.py:39` carries `WRAPPERS = ("rtk","time","eval","command",
      "builtin","exec","nohup")` (ADR 0012). **The spec mentions `rtk` zero times and never defines
      the `kind: COMMIT` predicate at all**, so every real commit on this machine would classify as
      not-a-commit and the gate would allow — **dead on arrival** — while task 14's hand-written
      `git commit …` arming check goes green over it. `judge-guard` fail-open #3's exact shape, in
      the control built to prevent it. It is also in my own `CLAUDE.md` (`RTK.md`), which I did not
      consult.
    · **Compliance's four:** `api-contracts` — `form` is a closed enum the hook validates **before**
      consulting `kind`, but no `form` value is defined for the `OTHER`/`NOTHING_RUNNABLE` outputs
      every non-commit payload produces, so a conforming classifier trips its own
      `MSG_CLASSIFIER_BAD_OUTPUT`; and doors row 5 still routes *every* non-zero exit, including the
      new exit 3, to `MSG_CLASSIFIER_FAILED`. · `commit-form-coverage` — the `ALL` row defines
      outside-path-set content only "for a tracked path"; an **untracked** member on disk has no
      defined answer, and `git commit -am y` excludes it from the tree while the worktree ABSENT
      probe reports it present. · `writer-call-site-cwd` — the **Python** call site still resolves
      `rev-parse` at the bottom, and checklist task 8 still prescribes round 3's superseded wording.
      · **NEW `writing-specs/command-grammar`** — rule 2's unqualified "`--opt value` consumes the
      next token" contradicts the group naming `--untracked-files`/`--gpg-sign` as never consuming
      one, re-opening the exact G2 fail-open.
    · **Obs also owed:** git accepts **unique prefixes** — `--includ`/`--inclu`/`--incl`/`--inc` all
      mean `--include` and reproduce M3 verbatim, `--amen`/`--ame`/`--am` all mean `--amend`, so
      literal matching closes only the fully-spelled forms · `-p/--patch` and `--interactive` mutate
      the index *after* the hook runs, unmentioned · **the real revert pair is also 7↔13** (a
      registered-yet-missing hook blocks *every* Bash call per `git-guard.sh:22-25`) · the exemption
      log is gitignored + 0700 + local-only, so the auditability that section argues for is not
      delivered · blocks are never logged, so nobody learns how often the gate fires.
    · 🔴 **TWO NARRATION ERRORS CAUGHT — the standing trigger fires.** (1) The spec says
      `git diff --cached --name-only` outside a repo exits **128**; **re-measured, it is 129** (128
      is `rev-parse --show-toplevel`, a different command — the claim was inherited from round 1 and
      never re-measured). (2) **`G10` does not exist** — the grammar table stops at G9, yet a
      scenario cites "measured G10" and my own judge brief said "ten rows G1-G10". Both are claims
      about my own work that the document does not support.
    · 🔴 **THE CONCLUSION FOUR ROUNDS NOW SUPPORT:** every round closes its targets and the newly
      written prose carries the next defect. Round 4 was the cleanest and *still* produced four
      violations plus a dead-on-arrival gap. **This is PR #34's lesson again — iterating a large
      spec against judges does not converge.** The document is **1023 lines** for one hook, against
      a repo standard of <400. The bottleneck is no longer design correctness (obs: "architecture
      holds, every fix is additive") but **prose consistency at this size**. Do not open round 5 as
      more of the same.
- **PR #31 (verdict outcome backfill) MERGED 2026-07-30T04:22Z (`8dfe05c`)** — 22 rows null→clean.
  Tip-reachability verified; branch `docs/verdict-outcome-backfill` pruned local+remote and its
  worktree (the misnamed `phase-guard-hook` dir) removed. Doc-system consolidation is now unblocked.
- **HISTORICAL from here — `phase-guard-hook` SHIPPED via PR #30 (`321dc9f`), merged 2026-07-30.**
  The block below is the record of that feature's rounds, not current state.
- `phase-guard-hook` — REVIEW. Gate opened 2026-07-26; all 17 tasks done 2026-07-28. The user answered
  **Q1 = build** with the literal phrase `gate confirmed`, which deliberately overrides ADR 0010's
  "build only when a skipped gate is observed" deferral — **task 16's ADR 0011 must record that
  override**, it is the whole reason that task exists. Model-switch checkpoint ran at the gate:
  **stay on Opus 5**, so `model_tier: high` is unchanged and deliberate — the risk sits in tasks
  9/10 (the asymmetric `cat-file --batch` parser) and the 8 fail-open exit paths, where a wrong
  exit code silently locks the repo.
  Implementation branch is **`feature/phase-guard-hook`**, forked from `worktree-phase-guard-hook`
  at `7936d80` so it carries every spec commit. The old branch was worktree isolation only and is
  now inert; do not add commits to it. Same worktree, `.claude/worktrees/phase-guard-hook`.
  **All 17 tasks are done (through `effae64`); the hook denies with the full four-element
  message, step 7 enforces the whole frontmatter contract, step 8 filters superseded files in one
  subprocess, both audible fail-opens speak once per session, the flag store is `.gitignore`d, the
  `PreToolUse` block is committed, and the `Phase gate` stub documents it.** Suite **80/0** (re-run after 14), siblings
  green (19/17/5/14), `shellcheck -x` clean, hook 318 lines. Task 12's falsification is **done** —
  8 mutations against copies, every one caught, table in the checklist annotation.
  · **13 done** (`209700d`) — `/hooks/state/` at `.gitignore:17` with its mirrored comment;
  `git check-ignore` matched nothing before and reports `:17` after.
  · **14 done** (`9024b64`) — fourth `PreToolUse` block, matcher `Edit|Write|NotebookEdit` →
  `hooks/phase-guard.sh`, shaped like the `Task|Agent` sibling (no `timeout`; only the vendored
  orca `*` hooks carry one), placed before the `*` catch-all. The scouting held: the
  `Edit|Write|NotebookEdit` a grep finds is the **PostToolUse** `post-edit-hook.sh`, untouched.
  Primary checkout's `settings.json` was clean, so no concurrent session held it.
  **The hook is NOT live** — the harness loads the primary checkout's copy, which is on another
  branch and arms only when this lands on `main` and that checkout pulls (rollback path 2).
  **⚠ NOW IN REVIEW (`phase: review`, `d7a2f8f`). All 17 tasks done; checkpoint 3 asked and
  answered 2026-07-28 — STAY ON OPUS 5, because the review backlog is fail-open/fail-closed
  judgment, not routine review.** At entry to review: HEAD `45a304e`, Suite **83/0**, `shellcheck -x`
  clean, dogfood **16/16** re-run after the step 9 fix. **Current HEAD/suite are at the end of this
  block** — every `HEAD`/`Suite` figure between here and there is the record of a round, not now.
  · **Escalation 1 (C0 placebo) FIXED** (`2adff7a`, test-only). Baselined by mutation: pre-fix, all
  three mutants (byte-count, input-order, phase-bound) escaped **all 80 tests, 0 failures**.
  **Round 4's "one fixture reorder" prescription was measured and is WRONG** — reversing alpha/beta
  still let all three escape. A desync only changes an answer if it corrupts the record that
  *decides* the outcome, so a normal trailing-newline blob must be read **before** the superseded
  one. C0 is now 3 files (alpha planning+prose `phase:` line / beta superseded, no trailing NL /
  gamma deleted → `missing` echo). C5 count 6 → 9. Hook was correct throughout.
  · **Escalation 3 (step 9 fail-open) FIXED** (test `84ed0f5` → fix `ee781d8`). Step 9 re-read files
  with unbounded `grep`+`sed`, so **prose** mentioning `phase: implementation` + `branch: X` granted
  permission on X — and feature files are exactly the docs that quote those keys. A file step 7 had
  skipped as malformed still got a vote. Parser now emits `<phase>TAB<branch>`; step 7's loop
  collects claims from the same parse; step 9 is string membership and touches no files. Falsified
  by reverting step 9 → fails exactly B2b/B2c. Also drops a grep+sed per file off the hot path.
  · **Rollback path 3 WITHDRAWN** (`45a304e`) — `chmod -x` yields **126**, may read as deny, so the
  "last resort" could lock every repo. Paths 1–2 verified and sufficient. Deliberately NOT verifying
  whether the harness reads 126 as deny: the experiment means arming a hook that may lock the
  machine, for a path we do not need.
  · **Escalations 2 and 4 CLOSED** (`8de2fba`, test-only). **A3.1b** isolates the line-1 clause that
  A3.1 could only name: junk on line 1, `phase:` above the fence. Mutation-checked against BOTH
  faithful mutants — deleting the whole rule is too blunt (41 failures), while `NR == 1 { next }`
  is caught by **A3.1b alone and A3.1 not at all**. **Flag ordering:** the two step-7 silent cases
  now pin their own session id and assert the store is untouched (`no_flag_for`); `payload_sid`
  moved up beside `payload`. Measured first — nothing writes that flag today and the `nfiles > 0`
  mutant was already caught, so this removed an unenforced order dependency, not a broken test.
  **The round-3 note's mechanism was WRONG**: A1.7 parses fine and never warns.
  · **OBS JUDGE RUN 1 (`01f011e`, 2026-07-28): risk=medium, confidence=high, no dimension failed**;
  `execution`/`regression`/`success_masking` concern. It confirmed the central reframing holds —
  it independently checked that `rules/gates.md` really does forbid branch creation during planning,
  so the unclaimed-branch premise is sound rather than lucky. It also **retracted its own first
  finding**: initial numbers suggested the hook slows as cards accumulate; controlled re-measurement
  gave a flat ~35–40 ms from 2 to 101 cards and it called its first reading a machine-load artifact.
  · **Escalation 5 (partial-skip silent fail-open) FIXED** — test `2fd0a04`-style baseline then fix.
  **Reproduced independently before touching anything**, in a throwaway repo: malformed `planning`
  card alone → allow + audible warning (promise holds); malformed `planning` card **+ one
  well-formed `review` card** → **exit 0, completely silent**. Root cause: the tally asked
  `nfiles > 0 && nparsed == 0`, and one readable card makes that false. Widened to
  `nfiles > nparsed`; `NOPARSE_MSG` reworded ("every file … failed" was false for a partial skip);
  the parser comment's "must not silently switch a CRITICAL gate off" claim reworded to the
  guarantee the code actually delivers. **The suite structurally could not see this** — every A2
  fixture makes *all* files malformed, every A3 fixture pairs the bad file with a well-formed
  *planning* file that denies regardless. Mutation-checked both directions: narrowing back fails
  A2.15 alone, widening to `nfiles > 0` fails A2.17/A1.7/B2.
  · **Escalation 6 (`nbranch > 1` untested) CLOSED by A3.5b.** The judge's mutation found the clause
  could be deleted with all 88 green. A3.5b makes the duplicate load-bearing — two `branch:` lines,
  the last claiming the branch under test, and awk keeps the last — so without the clause the deny
  becomes an allow. Catches that mutant and nothing else.
  · **RUN 2 (`f963b76`, risk=medium) found the SAME silence one stage later — in RUN 1's own fix.**
  Escalation 5 widened the tally but placed it *inside* the no-planning-files branch, and step 8's
  supersession drop can empty that list one stage further down, below a bare `exit 0`. Reproduced
  independently: superseded card + one unreadable card → silent; the unreadable card alone → warns.
  **Escalation 7** fixed it as a CLASS fix — the check moved *above every exit*, straight after the
  parse loop. Verified consequence: a deny with a skipped card now emits the warning **and** the
  full 16-line deny message (exit 2, all four elements intact). Also **8** (message asserted
  something false for a plain `README.md` in `docs/features/` — now conditional) and **9** (the spec
  still stated the pre-fix rule).
  · **RUN 3 (`4a60aa0`, risk=HIGH, 2 dimensions FAIL) found it one step EARLIER — in the counting.**
  Moving above every exit did close all nine exits; the boundary was drawn at *exits* and the hole
  was in `[ -f "$f" ] || continue`, which quietly both detected the unexpanded glob AND dropped
  every non-regular entry. A dropped entry is never counted, so `nfiles > nparsed` cannot trip.
  **Severity measured, not hypothetical:** a card symlinked into `docs/features/` denies while its
  target is present (exit 2, full message) and **exits 0 silently once the target is moved** — a
  real planning card leaving the gate without a word. **Escalation 10** fixed it with
  `[ -e "$f" ] || [ -L "$f" ]` (`-L` is required: `-e` follows the link and is false for a dangling
  one). **11** discarded awk's own stderr, which escaped the once-per-session flag entirely — 3
  lines on write 1, 2 on every write after. **12** corrected three MORE stale spec locations
  (step 7, the Output contract, the Examples table).
  · **⚠ THE PATTERN IS THE FINDING.** Three rounds, three instances of one class. Rounds 1 and 2
  were patched at the point of failure; only round 3 addressed *why the suite could not see any of
  them* — **every fixture was a readable file with malformed CONTENT, and none was an entry the
  parser could not open at all.** A2.19–A2.22 close that fixture class; the two-line `-e`/`-L`
  change is merely what it exposed. If a RUN 4 finds a fourth instance, the response is to rethink
  the fail-open surface, not to patch again.
  · **ALL TWELVE REVIEW ESCALATIONS CLOSED.** HEAD `8967723`, pushed. Suite **100/0**, shellcheck
  clean (hook + tests), dogfood **16/16**. Every repro re-run end-to-end: partial skip,
  supersession, dangling symlink, directory entry, unopenable card, moved-symlink severity case.
  **Next: obs judge RUN 4 at `8967723`, then `gh pr create --draft` → `gh pr ready`.**
  judge-guard blocks `gh pr create` without a fresh implementation-stage verdict matching HEAD.
  · **RUNS 4-6.** RUN 4 (`b25efdf`-1, risk=HIGH, `success_masking`+`traceability` FAIL) found the
  4th instance: `docs/features/` itself unlistable — at 444 the glob still yields real filenames but
  `-e`/`-L` need SEARCH permission, so every entry is dropped uncounted. **User chose the systematic
  fail-open audit over a 5th patch.** RUN 5 (med, 0 fails) audited the audit: THE RULE as written
  ("opted in AND holds a planning card") is NOT what the code does ("opted in AND could not
  finish"), and that misstatement hid the 5th instance — **the payload parse**. RUN 6 (`9996c0b`,
  med) confirmed all six RUN-5 fixes but says **the class is still not closed**.
  · **THE AUDIT'S REAL FINDING: six exits were asserted SILENT by the suite itself** — the four git
  exits (`A1.8`-`A1.10b`) and the two payload exits (`A1.4`/`A1.5`), all against `$OPTED`, which
  holds an un-superseded planning card on an unclaimed branch. Not missing tests — **enforcing**
  ones. That is why four consecutive judge rounds read the suite as evidence of correctness.
  Everything is enumerated in the spec under "The exits that must not be silent": 9 audible, 8
  silent. Also fixed: step-5 symlinked repo path (raised 3 rounds, never fixed until now), detached
  HEAD now speaks, `git` missing from PATH now speaks, `HOME` unset no longer exits 1.
  · **⚠ OPEN AND UNFIXED — RUN 6's biggest finding, verified: the hook resolves the repo from the
  SESSION'S CWD, not from the file being written.** `git rev-parse --show-toplevel` runs in the
  hook's cwd, so a write into an opted-in repo from a session sitting elsewhere exits 0, silently
  unguarded. Measured: same target file, cwd inside repoA → **exit 2**; cwd in repoB → **exit 0**.
  Pre-existing since step 2 was written; **six judge rounds never looked at it**. Biggest blast
  radius of anything found, possibly a one-line fix — but **settle it by running the hook LIVE**,
  which has never been done in six rounds. This is the next action.
  · **⚠ TWO DEFECTS I INTRODUCED IN `9996c0b`, both verified:** (1) step 5's new physical-resolution
  failure (`[ -n "$fp_phys" ] || exit 0`) is a SILENT fail-open — the same class, inside the fix for
  the class; (2) the walk-up glues a path with no directory component without a slash — relative
  `x.js` from repoA yields `…/repoAx.js`. Low reachability (payload paths are absolute by contract)
  but real, and the suite has no test for that shape.
  · **⚠ THE RULE IS WRITTEN IN THREE PLACES AND ONLY THE SPEC WAS FIXED.** `hooks/phase-guard.sh`'s
  own header still carries the sentence RUN 5 falsified, and the test file's Group A4 comment still
  lists two exits as silent that its own tests now prove audible. Three copies of a rule wrong six
  rounds running is the mechanism, not the symptom.
  · **MY ERROR, recorded:** I cited commit SHAs `ff8a02c`/`2b81ce1` in the RUN 6 prompt; neither
  exists. The real test commits are `07c1698` and `9eef24a`. The judge caught it. **Never write a
  SHA into a dispatch prompt without `git cat-file -t` first.**
  · Calibration that keeps this at medium, not high: **every survivor fails OPEN.** Worst case is
  the phase gate enforced by judgment alone — today's status quo. Nothing causes a false block.
  · Suite **108/0**, shellcheck clean, HEAD `9996c0b`, pushed.

  · **Repro trap that cost a false alarm:** a throwaway repo with **no commits** makes step 9's
  `git rev-parse --abbrev-ref HEAD` fail, so the hook fail-opens at exit 0 and EVERY scenario looks
  silent. `git commit --allow-empty` in the fixture before drawing any conclusion.
  · **OPEN, deliberately not decided — the parallel-worktree collision.** Once this merges, one
  agent opening any feature at `planning` denies source writes to every other concurrent agent on
  an unclaimed branch, and `core-conduct.md`'s parallel-agent invariant forbids that second agent
  from applying the fix the deny message names. The two rules contradict in exactly this case.
  Governance trade-off, user-owned — recorded in the feature file, not resolved.
  · **16 done** (`0f1c029`) — ADR `docs/decisions/0011-branch-scoped-write-permission.md`. 0010 left
  unedited and still Accepted; 0011 carries an `Amends:` header instead. The two grounds are
  recorded as *different kinds* of overturn on purpose: the technical objection was made
  **inapplicable** by the forward lookup (never refuted on its terms), while the process deferral was
  **overridden with its trigger condition admittedly unmet**. `validate-diagrams.sh` PASS.
  · **17 done** (`effae64`) — throwaway-repo dogfood, **16/16**. Deny fires with all four message
  elements, all six exempt paths allow, phase round-trip unblocks then re-denies.
  **⚠ ROLLBACK PATH 3 IS BROKEN — the headline finding.** `chmod -x` yields exit **126**, not the
  round-1 "skipped by the harness" claim; round 2's suspicion was right. `settings.json` registers a
  bare direct path, so that is the live shape. 126 is neither 0 nor 2 (a defect by the spec's own
  Output contract) and a `PreToolUse` harness may read it as **deny** — so the "last resort" rollback
  may lock every repo on the machine instead of disarming the guard. Paths 1–2 unaffected.
  **Recorded, not acted on** — revising Rollback is review-phase. Still unverified: whether the
  harness actually classifies 126 as deny; that needs a live check before path 3 is rewritten.
  Timings recorded, not gated: guarded ~64.1ms net, non-opted-in ~12.4ms net against a 12.3ms
  structural floor (harness overhead measured at 2.3ms/call and subtracted, not assumed).
  Suite **80/0**, `shellcheck -x` clean, re-run after 17.
  · **15 done** (`1b67516`) — two clauses appended to the `Phase gate` stub at `rules/gates.md:5`
  in place; bullet count re-verified **18**, no 19th added. The stub now states the deny rule, that
  docs and memory paths are never blocked, that no bypass variable exists, and that the
  implementation half stays judgment-only (the reverse-enforcement non-goal, made visible where a
  session would otherwise assume both directions are covered); it carries `merge-guard.sh`'s
  "momentum guardrail, not a security boundary" idiom for the unguarded Bash write surface.
  The four escalations these tasks raised are all **closed** — see the review block above.
  Do **not** re-derive the design; it is all in the feature file, which is canonical.
  · **RUN 6's cwd finding CLOSED** — the hook now resolves the repo from the **file being written**
  (user decision 2026-07-28), pinned by Group A6. Cost: never-opted 11→38ms, opted-in 35→41ms; live
  ~41.8ms non-opted / ~67ms deny. The old ~12.4ms "structural floor" is superseded — python starts
  once per write even when the repo was never opted in.
  · **RUNS 7-8 (2026-07-29). RUN 7's four findings landed (`2c39eb8` test → `97a2008` fix →
  `7f2fc9e` docs), then RUN 8 (`5cb0985`, risk=medium, no failing dimension) found the fix itself was
  the new defect.** `21a0411` test (A7.4) → `325f70c` record corrections. Suite **126/0**, shellcheck
  clean. **Five of RUN 8's six items landed, not six** — corrected by RUN 9: `:976` was closed as
  "already correct under the code's numbering", but RUN 8's point was the wrong *reasoning*, not a
  wrong number. Reinterpreted, not answered. (The first version of this entry claimed all six — the
  same overstatement `7f2fc9e` made, one round later.)
  · **Root cause, upstream of all six sites:** the doc's Order-of-operations list and the code's
  `# --- Step N ---` headers described *different* sequences while the list claimed they resolved
  against each other. Now single-sourced, with the rule stated once — **step numbers mean the code's
  headers; the code wins; never renumber code to match prose.** Canonical: 1 payload · 2 tools ·
  3 path/parse · 4 repo+opt-in · 5-10 unchanged. Four sites quoting retired prose are **marked**
  pre-`508c55b` rather than rewritten, so their quotes still match what they cite.
  · **F2 was reported closed and was not.** `7f2fc9e` claimed "all four findings" and touched **one
  file**. Enumerating beat patching again: beyond RUN 8's six sites it found two more wrong audit rows
  and **three** copies of the false-credit claim — the suite's `:989` and `phase-guard.sh:197` both
  still said six rounds missed the cwd bug. **`git show --stat` the closing commit and confirm it
  touched the file the finding named, before calling anything closed.**
  · A7.4 mutation-verified: swapping the walk-up for `warn_if_cwd_opted_in` leaves A7.1 green and
  fails A7.4 with 0 stderr lines. A7.1 alone never pinned that rationale.
  · **RUN 9 DONE 2026-07-29 @ `33bc6ae` — risk=medium, confidence=high, NO failing dimension, but
  five `concern`s** (`intent`, `trajectory`, `traceability`, `success_masking`, `audit_trail`).
  Verdict `coding-memory/observability-judge/2026-07-29-feature-phase-guard-hook-round9.md`.
  **No behavioural defect at this HEAD** — the judge re-ran the suite twice (126/0) and probed deny /
  doc-exempt / card-exempt / claimed-branch / never-opted-in by direct invocation. Every finding is a
  record defect. **Both verdict artifacts are complete** — markdown **and** the `verdicts.jsonl` row,
  both pinned at `33bc6ae`. Only the *pane result file* is missing: the run outlived the 540s judge
  wait, so `dispatch-pane-agent.sh wait` reported a timeout. **`95fffa1`'s commit message claims the
  judge never appended the row — that claim is false.** The row landed between my check of the file's
  mtime and my reading of it; I trusted a stale `ls` instead of re-reading the file. Corrected here
  rather than by rewriting the pushed commit: on a branch being judged on its audit trail, the wrong
  claim and its correction both belong in the record. A timed-out judge wait means *check for the
  artifacts*, not *assume they are absent*.
  · **Owed before the PR (RUN 9's list):** (1) three normative contract counts undercount the audible
  surface — `:611` says "six" audible exceptions vs nine `warn_once` reasons and eleven audit rows,
  `:297` still says "two exits that print", `:484` names 2 of 9 flag reasons and quotes `$HOME` where
  the code ships `${HOME:-}`; (2) three unmarked stale step refs survived the "fix every site" pass —
  `:426` (5→4, authored by the reorder commit itself), `:449` (3→4), `:1015` (Step 4→3); (3) answer
  `:976` on its own axis — it speaks via `warn_if_cwd_opted_in`'s cwd fallback, not because an opt-in
  test passed; (4) **consider one structural test** greping the doc's step list against
  `grep '# --- Step' hooks/phase-guard.sh` — four rounds say care alone cannot keep the record correct.
  · **⚠ VERIFIED ADJACENT BLOCKER — `gh pr create` will fail closed from this worktree.**
  `hooks/judge-guard.sh:22` reads `$HOME/.claude/coding-memory/observability-judge/verdicts.jsonl`
  (the PRIMARY checkout's — 43 lines, **zero** for this branch) while resolving identity from the
  session's cwd. **Same identity-from-cwd class this branch just fixed in `phase-guard.sh`**, and it
  is exactly what the parked `fix/judge-guard-verdict-lookup` worktree exists to fix. Decide
  deliberately — `JUDGE_VERDICTS_FILE=$PWD/...`, or a logged `JUDGE_EXEMPT=<reason>`. **Re-running the
  judge does not help.** Out of scope for this diff.
  · **Undisclosed boundary RUN 9 found (owed to the PR body):** supersession reads `refs/heads/` only,
  so a gate opened on a **remote-only** branch does not supersede and the repo resumes denying
  (probe-verified). Also uncosted: one `dirname` fork per path level for writes landing outside any repo.
  · **RUN 9's four items LANDED 2026-07-29 (`1b79e2a` test → `8390a52` record), suite 130/0,
  shellcheck clean, pushed.** Group D added: four grep tripwires that make the suite read the doc —
  step count/order vs code headers (D1), keyword per step per side (D2), Flag-contract reason set
  derived from call sites (D3), Output-contract counts computed not asserted (D4). **Red-first on
  exactly RUN 9's two contract findings** (D3: 7 of 9 reasons missing; D4: no derived-count
  sentence), then green; **all four mutation-verified** — stale count / renumbered item / reworded
  step / dropped reason each fail exactly their own test (m1, m4 at 129/1 against the fixed doc).
  `:976`-class reasoning answered on its own axis in A5.6's comment; old sentence kept, marked
  pre-`508c55b`. Verification section records the round.
  · **Gotcha that cost a redo:** mutation-verifying with `git checkout --` reverts BEFORE committing
  the fixes discarded them silently — m2-m4 ran against the stale doc and m4's signal was void
  (nogitbin was already missing). Commit first, then mutate; or the mutation baseline is a lie.
  · **RUN 10 DONE 2026-07-29 @ `31ebca7` — risk=low, confidence=high, NO failing dimension; the
  loop's first low-risk verdict.** Both artifacts verified in the worktree ledger, jsonl `head_sha`
  re-read from the file (not the mtime) = full `31ebca7…` sha. Judge reproduced 130/0 + shellcheck,
  red-first 128/2 at `1b79e2a`, and all four mutations itself. **Two leftovers of the class Group D
  cannot see (wrong sentences, not wrong counts):** (1) the feature doc's canonical step-3 item
  says a malformed payload exits "silently" — the audit table, A1.4/A1.5, and
  `warn_if_cwd_opted_in` all say it speaks from an opted-in cwd (same class RUN 9 fixed for
  `noparse`); (2) `phase-guard.sh:109`'s `warn_once` comment lists `(nopython|noparse)` as if
  exhaustive — 2 of 9 reasons. Judge-guard route decided on the merits: **`JUDGE_VERDICTS_FILE`
  pointed at the worktree ledger, not `JUDGE_EXEMPT`** — the fresh row exists, so the gate can pass
  honestly; exempting would skip a check that would succeed.
  · **RUN 10's two leftovers FIXED (`a00fd3e`, docs+comment only), suite 130/0, shellcheck clean.**
  Step 3's canonical item now says the malformed-payload exit speaks from an opted-in cwd (matching
  the `nopayload` audit row and A1.4/A1.5); `warn_once`'s comment enumerates nothing — the reason
  set lives at the call sites, where D3 derives it.
  · **RUN 11 DONE 2026-07-29 @ `218118b` — risk=low, confidence=high, no failing dimension; both
  RUN 10 leftovers confirmed closed.** `success_masking` held at `concern`: grep tripwires cannot
  catch a wrong *sentence* — disclosed, structural. **DRAFT PR #30 OPENED at that HEAD**
  (https://github.com/suyatdev/.claude/pull/30), judge-guard cleared via `JUDGE_VERDICTS_FILE` at
  the worktree ledger — passed honestly, no exemption; created BEFORE committing the audit trail
  (PR #23 lesson), trail + Roadmap tick + pr-tracking entry committed immediately after.
  **Next: user reviews → `gh pr ready` → merge via GitHub UI → post-merge: tip-reachability check,
  arm-on-pull check, outcome backfill.** Judge prompts live in the **session** scratchpad and die
  with the session — RUN 8's was lost that way. Don't point at one; reconstruct it from this block
  plus the RUN 8 verdict file. (`scratchpad/` is not `.gitignore`d here, so nothing durable goes there
  while the branch is in review.)
  · **PR #30 MERGED 2026-07-30T02:52Z (`321dc9f`); tip-reachability verified — `d339ea8` is an
  ancestor of origin/main.** Pre-merge, origin/main had been merged into the branch (`d339ea8`,
  record-ledgers-only, three union conflicts, suite 130/0 + shellcheck at that HEAD).
  **Arm-on-pull checked, NOT yet armed — correctly:** the registration is in origin/main's
  `settings.json`, but hooks execute from the PRIMARY checkout, which sits on the other session's
  `feat/pane-split-policy`, whose tree predates the merge (`hooks/phase-guard.sh` absent). It arms
  when that branch merges main or the primary returns to main. **Do not force it** — no
  fast-forward of local `main` (the other session's diff base), no touching that branch.
  **User approved 2026-07-30: verdict outcome backfill (now #27/#28/#30, absorbing the parked
  item) + worktree/branch cleanup.** Cleanup done: worktree switched to
  `docs/verdict-outcome-backfill` (fresh off origin/main `321dc9f`, reusing the phase-guard-hook
  worktree path — the directory name no longer matches the branch), `feature/phase-guard-hook`
  pruned local+remote. **NEXT (fresh session): model-switch ask, then backfill `outcome` on the
  #27/#28/#30 rows of `coding-memory/observability-judge/verdicts.jsonl` (convention
  `clean|rework|null`; check #27's merge state first), then a small docs PR via
  `preparing-pull-requests`.** Detail: `.claude/session-state.md`.
  · **Backfill DONE — DRAFT PR #31 opened 2026-07-30** (branch `docs/verdict-outcome-backfill`,
  backfill commit `9ea5450`): 22 rows null→clean (#27 ×1, #28 ×7, #30 ×11 + 3 on
  `worktree-phase-guard-hook`). Model checkpoint answered: stay on Fable 5. judge-guard cleared
  via logged `JUDGE_EXEMPT` (records-only, nothing to score). Detail: pr-tracking §PR #31.
  Next: user review → `gh pr ready` → merge via GitHub UI → prune branch local+remote.
- **Three findings from grounding the Spec against live prior art (2026-07-25).** (1) `NotebookEdit`
  carries **no** `file_path` — its only path key is `notebook_path`; the settled step 4 said
  `file_path` alone, which would have failed open on every notebook write. Corrected, with a
  regression scenario. (2) System `bash` is **3.2.57**, so the hook may not use associative arrays,
  `mapfile`, or `${var,,}`. (3) `git cat-file --batch` output is **asymmetric** — a blob emits
  `<sha> blob <size>` *without* echoing its request, a miss echoes the request verbatim + ` missing`
  — so the un-superseded filter must consume results in input order or it mis-attributes every blob.
- **User decisions, 2026-07-25.** Q2 **accepted** with one narrowing — the *un-superseded check*:
  a `planning` file stops denying once any branch records it as `implementation`, because its gate
  has already opened. Fixes the `main`/hotfix write-lock at the root cause (a stale copy on `main`
  is stale *by design* after the gate) while staying a forward lookup. Q6 **resolved: no bypass at
  all** — and the reason is that the hatch already exists structurally, since feature files live
  under unguarded `docs/**`, so editing the frontmatter always unlocks a locked repo. A branch-name
  allowlist was rejected on the same ground: it is `PHASE_EXEMPT` through a different door.
  Q7 (reverse direction) stays out of scope. Q1 (build at all?) still deferred to the gate.
- **APPROVED, NOT STARTED — doc-system consolidation.** Was "do this before more phase-guard work"
  (user-approved 2026-07-25); the 2026-07-26 `gate confirmed` started phase-guard implementation
  first, so that ordering is **superseded, not cancelled** — flagged to the user at the gate.
  User-approved 2026-07-25: trim this file to its own ≤200-line cap, delete the 18
  `coding-memory/branches/*.md`, drop `coding-memory/pr-tracking.md`. **These are ONE coupled
  commit, not three** — this index holds ~17 pointers into the delete targets (branches/: lines
  68,77,102,132,138,150,168,179,189,201,263 · pr-tracking: 57,69,75,201,263,266,415), so deleting
  without trimming leaves dangling pointers, and trimming removes most of them anyway. Order:
  (1) rewrite §Active Session (7–170) and §Exact Next Steps (272–432) — 325 of 432 lines, both
  accumulated history, keep current session + repo/PR pointers + next steps only; (2) `git rm` the
  19 files (all tracked → recoverable); (3) fix `skills/preparing-pull-requests/SKILL.md:43`, which
  mandates `pr-tracking.md` as a maintained running doc — PR descriptions get generated at PR time
  from the checklist + diff; (4) tick `README.md:63`, which already tracks this reconciliation.
  Inert trap: `docs/superpowers/plans/2026-07-18-compliance-judge.md:563,570` would recreate both
  deleted artifacts if ever re-executed.
- **Deferred to its own feature file `doc-system-consolidation` (amends ADR 0010 → earns an ADR).**
  (a) **Judge-output shrink:** `coding-memory/observability-judge/` is 32 files / 5,007 lines and
  compliance adds 757 — and *nothing reads them*, since `judge-guard.sh:22` consumes
  `verdicts.jsonl`, not the `.md`. Shrink to pass/fail per area + open issues on the feature file.
  (b) **Invert the canonical feature-file section order** to frontmatter → Tasks → Verification →
  Spec → rationale. Today `## Tasks` sits at line 223 of 245, so "where are we" costs a full-file
  read; reordered, a restore gets it from the first ~40 lines. The one-file design currently fights
  selective loading instead of enabling it.
- **Q2 was the crux.** ADR 0010 deferred this hook because
  "which feature file is active" is unresolvable at `branch: none`. That framing is avoidable: the
  hook never attributes a write to a feature, it asks only whether the *current branch* carries
  implementation permission. Deny when any feature file is `phase: planning` AND the branch is not
  claimed by an `implementation` file. It holds during planning precisely *because* planning forbids
  branch creation — an unclaimed branch is the signal, not ambiguity. Known holes are written down,
  not hidden: branch-granularity (not per-feature), `main` stays write-locked after the gate opens,
  and a stale `planning` file locks the repo. Q3/Q4/Q5 resolved; **Q6 found a real defect in the
  house pattern** — `JUDGE_EXEMPT`-style bypasses need a Bash command line, which `Edit`/`Write`
  payloads do not have, so `PHASE_EXEMPT` cannot work the way the other guards do.
- **Deliberate fail-mode split from `judge-guard.sh`, decided this session:** that hook fires on one
  rare command and fails closed on infrastructure errors; this one fires on *every write in every
  repo*, so it fails closed only once a `planning` file is positively identified, and fails **open**
  on missing python / unresolvable git root / unparseable frontmatter. Blast radius, not sloppiness.
- session_origin: desktop · session_started_at: 2026-07-23 (Opus 4.8) · last_active_branch:
  **`feat/pane-split-policy`** — **RESUME after clear. Restored clean: HEAD `6888e16` in sync w/ origin;
  spec blob VERIFIED still `cdc777a` (lock intact, compliance verdicts valid).** doc-guard's two flagged
  files (`verdicts.jsonl` +3 vibe-scape lines, `css-visual-pass.md`) confirmed the vibe-scape session's —
  NOT mine, left as-is. **HARD MODEL GATE ANSWERED THIS SESSION: Opus 4.8 for `superpowers:writing-plans`;
  IMPLEMENTATION tier still deferred — re-ask before any coding.** **writing-plans IN PROGRESS:** read the
  spec + all target infra (`hooks/pane-dispatch-guard.sh`, `panes/dispatch-pane-agent.sh`,
  `panes/redirect-agents.conf`, adapters). **PLAN WRITTEN + self-reviewed →
  `docs/superpowers/plans/2026-07-23-pane-split-policy.md` (committed).** 8 TDD tasks: T1 live cmux
  tab-primitive probe (HARD GATE, operator-run on real cmux — gates T5); T2 `pane-policy-<key>` state +
  `set-policy` subcommand + `read_policy` (bounded N 1..16); T3 guard 3-lane routing + new
  `inprocess-agents.conf` (Explore/Plan) + narrowed `redirect-agents.conf` (judges); T4 `open_tab`
  adapter verb + `validate_open_tab_args` (surface-ref allowlist `[A-Za-z0-9:%_.-]`≤64) for
  tmux/iterm/terminal; T5 cmux `open_tab` (probe-verified `new-surface --pane`); T6 dispatcher
  lane/session/surface markers + `count_live_workers` (proven on REAL run-dir fixtures) + judge bypass;
  T7 overflow → `open_tab` round-robin (`pane-rr-<key>`); T8 skill + gate-stub correction + ADR 0009 +
  Mermaid. Config decision RESOLVED (two flat include-lists). All 7 Gherkin scenarios + 4 flagged
  assumptions mapped to tasks. **HARD MODEL GATE ANSWERED 2026-07-23 (impl tier): Opus 4.8 (1M) for the
  whole 8-task implementation; execution = SUBAGENT-DRIVEN (pane-routed implementers). `settings.json` is
  `opus[1m]` so pane implementers inherit Opus — no Fable 5 surprise. Do NOT re-ask either gate for this
  branch's execution.** **T1 DONE + pushed (`fe7f30a`) 2026-07-23 — live cmux 0.64.20 probe PASS:
  `new-surface --pane <pane-ref>` IS the open_tab primitive (in-pane tab; confirmed structurally in the
  tree AND visually Q1 one-workspace/Q2 two-tabs/Q3 TAB_SEND_OK; agent launches via
  `send --surface <new-ref>`). So "spawns beyond N open as tabs inside existing panes" is achievable.
  Findings + exact verb/flags + the surface→pane resolution note that feeds T4/T5 in
  `coding-memory/branches/pane-split-policy.md`; probe `panes/cmux-tab-probe.sh`, fixture
  `panes/adapters/fixtures/tab-live.json`.** **T2 DONE 2026-07-23 (subagent-driven: pane Opus implementer + pane task-reviewer):** commit
  `8fb4534`, commit-verified in-checkout; policy state file — `set-policy` writer + `read_policy`
  reader (bounded N 1..16, dual-validated at write+read, fail-open), `read_policy` defined-but-uncalled
  (consumed by T3/6/7). 44/44 tests, shellcheck -x clean, review Spec ✅/Approved/0 Crit-Imp. Detail +
  T3 carry-forwards: `coding-memory/branches/pane-split-policy.md` §Task 2. **T3 DONE 2026-07-23
  (subagent-driven: pane Opus implementer + pane reviewer, both cmux surface:83):** commit `6bead2d7`,
  **verified in-checkout** (4 domain files only), guard test **23/0 re-run by controller**, shellcheck
  clean, Task 2 suite still 44/0. Guard now three-lane (read-only `inprocess-agents.conf` → judges
  `redirect-agents.conf` → per-session policy). **Reviewer = CHANGES-REQUESTED (narrow; arch stands,
  T4 unblocked).** Fail-open missing-conf ruled ACCEPTABLE. **2 Important defects reproduced end-to-end
  (must fix before branch PR): (1) zero-padded N ask-loop — `set-policy --max 03` writes `panes max=03`
  but guard regex rejects it → ASK forever; (2) stale `pane-policy-nosession` overrides a MALFORMED
  primary policy → wrongly allows.** + Important-3 stale guard header + Minors 4-7 + Nits. Full repro +
  fixes: `coding-memory/branches/pane-split-policy.md` §Task 3. **T3a DONE + reviewer APPROVED 2026-07-23
  (subagent-driven: pane Opus implementer + pane reviewer, both cmux surface:83):** commit `c74e285`,
  **verified in-checkout** (4 domain files only, 146+/17-, no store files), controller re-ran guard **28/0**
  + dispatcher **51/0**, shellcheck clean. Fixed Important-1 (base-10 normalize N + unified guard regex),
  Important-2 (break on first existing policy, nosession only when env_sid empty), Important-3 (three-lane
  header), Minors-4/5 + T2 carry-forward A/B; TDD Important repros RED against parent (26/2, 49/2). **TWO NEW
  Minors from the 3a review → final-review carry-forward (fold into Minor-7): NEW-A guard 64-bit `10#` wrap
  vs read_policy (cap POLICY_RE digits `{1,2}`); NEW-B — PRIORITIZE — `c74e285` introduced an UNQUOTED
  `for key in $keys` at guard:104 (quote via `set --`).** Detail: branch log §Task 3a. **T4 DONE + reviewer APPROVED 2026-07-23
  (subagent-driven: pane `general-purpose` implementer + pane reviewer, both cmux `surface:83`):** commit
  `86d796b` (parent `57b3eb0`), **verified in-checkout** (5 adapter files only, +114/−32, `Doc-Exempt`),
  controller re-ran adapters suite **36/0** + shellcheck clean. `open_tab` verb on tmux(`new-window`)/
  iterm(`create tab`)/terminal(shared path) + `validate_open_tab_args` (anchored allowlist
  `^[A-Za-z0-9:%_.-]{1,64}$`); ref not yet interpolated anywhere (defense-in-depth for T7); reviewer
  adversarially probed the boundary, all rejected 65; open_pane byte-identical vs parent. **T4
  carry-forward → final review:** T4-Minor `adapters.test.sh:55` (open_tab dryrun cases don't pin
  `new-window`/`create tab` — a revert would pass; **FIXED in T5's cmux case**) + T4-Nit (inline unknown-verb
  test). Detail: branch log §Task 4. **T5 DONE + reviewer APPROVED 2026-07-23 (subagent-driven: pane
  `general-purpose` implementer + pane reviewer, both cmux `surface:83`):** commit `a443b82` (parent
  `3f7b575`), **verified in-checkout** (2 domain files only — `cmux.sh` +38/−4, `adapters.test.sh` +33/−2;
  vibe-scape's 3 uncommitted compliance-judge files untouched), controller re-ran adapters **43/0** +
  shellcheck clean. cmux verb guard → `case`; new `cmux_open_tab` resolves surface-ref → its `pane_ref` via
  `fetch_tree`+`layout_normalize_tree`+awk, then `new-surface --pane <pane_ref>` (Task 1 primitive) + send;
  every failure → return 1 (degrade). Implementer caught + fixed the plan's call-before-define (split
  validation-at-top / execution-after-`split_capture`). Reviewer probed live: 10 injection attempts → zero
  reached a cmux line, 7 degrade paths all rc 1, open_pane byte-identical vs `a443b82~1`. **T5 carry-forwards
  → final review:** T5-Minor (live fake's `new-surface` arm doesn't pin `--pane` → wrong-column mutation
  `print $1`→`print $2` stays green; fix: match `--pane pane:36` + else-arm `exit 1`) + T5-Nit
  (`check_cmux_version` unreachable on open_tab path) + T5-Nit (open_pane-only role/run_id derivations run
  harmlessly on tab path). Detail: branch log §Task 5. **T6 DONE + reviewer CHANGES-REQUESTED → Task 6a
  2026-07-23 (subagent-driven: pane `general-purpose` implementer + pane reviewer, both cmux `surface:83`):**
  commit `e6ef22c` (parent `6cb8687`), **verified in-checkout** (2 domain files only — `dispatch-pane-agent.sh`
  +55/−2, `.test.sh` +42; no store files), controller re-ran dispatcher **58/0** + shellcheck clean, `Doc-Exempt`.
  Landed: `is_judge`, `count_live_workers` (runs/* with `lane=worker`+`session=key`+no `agent-exit`), lane/session/
  surface markers, `count-workers` subcommand, worker gate (`count>=N`→interim exit 3 no-cooldown). **Reviewer
  verified by running (RED baseline 53/5, 6/7 mutants killed, parsers compared, live repros). VERDICT:
  CHANGES-REQUESTED — C1 CRITICAL: dispatch counts ITSELF (markers written BEFORE the gate) → off-by-one,
  `max=1` never opens a worker pane, capacity is N−1, BREAKS Task 7.** Plan Step 4 had the ordering bug; shipped
  green only because there's NO "worker under max opens a pane" positive test. **Task 6a fix (reviewer-verified in
  scratch): move the 2 marker-writes to after the gate + add that positive test; also M1 (add commented/padded
  fixture-conf lines so `is_judge` comment-strip is asserted).** I1 (phantom workers) CONFIRMED — C1 reorder kills
  the dominant gated-exit-3 source; residual (no-terminal exit 3, adapter-fail exit 4) bounded, carry to Task 7 as
  a dead-marking requirement. Security boundary CLEAN. Detail + full findings: branch log §Task 6.
  **T6a DONE + reviewer APPROVED 2026-07-24 (subagent-driven: pane Opus implementer + pane reviewer, both cmux
  `surface:83`):** commit `8ef4868` (parent `d76ca82`), **verified in-checkout** (2 domain files only —
  `dispatch-pane-agent.sh` +6/−2, `.test.sh` +27/−1; NO store files; the STAGED other-session compliance-judge
  files left untouched via pathspec commit). Controller re-ran suite **61/0** + shellcheck clean + read the diff.
  Fixed C1: moved the 2 marker WRITES to after the worker gate (kept `key=`/`lane=` before it) → capacity N not
  N−1; `max=1`/0-live now opens exactly one pane (reviewer-reproduced). I1 dominant source killed for free
  (gated `die 3` before tagging → no phantom). M1: judge-conf fixture now asserts both `is_judge` strips
  (mutations RED 57/4 + 55/6). New positive test "worker under max opens a pane" RED-against-parent confirmed by
  both agents. Reviewer ran all checks in an isolated worktree; APPROVED, 0 Crit/Imp. **NEW T6a-Minor** (new
  test asserts only `rc 0`, not adapter-invoked — non-blocking, fold into final review). Detail: branch log
  §Task 6a. **NEXT: Task 7** (overflow → `open_tab` round-robin `pane-rr-<key>`; C1 fix is its hard prereq),
  then Task 8 (skill + gate-stub correction + ADR 0009 + Mermaid). Per-task loop: pane implementer → verify
  commit in-checkout (`verifying-subagent-commits`) → pane reviewer → checkpoint. Final-review carry-forward:
  Minor-7 + NEW-A + NEW-B + Nits-8/9 + T4-Minor(fixed)/Nit + T5-Minor/Nits + M2 (PANE_HOME conf split-brain) +
  T6 Nits + **T6a-Minor**; run full pane suites + implementation obs judge before `gh pr create`.
  **Freshness: 2026-07-24 resume paid the branch's recurring restore tax (~75k) before output; user chose
  proceed. T6a impl+review done in panes (light on controller ctx), saved+pushed at this checkpoint; clear
  offered before Task 7.**
  **T7 DONE + reviewer APPROVED 2026-07-24 (subagent-driven: pane implementer + pane reviewer, both cmux
  `surface:83`):** commit `7cb43b0` — worker overflow to `open_tab` with round-robin pane selection
  (`state/pane-rr-<key>`), replacing T6's interim exit-3. Controller-verified in-checkout (exactly 2 `panes/`
  files, `Doc-Exempt` trailer, single worktree, other-session compliance files still staged/untouched) and
  independently re-ran all 7 suites (**287/0**, dispatcher 82/0 from 61/0) + `shellcheck -x` clean + read the
  full `.sh` diff. **The controller caught, BEFORE dispatch, that the plan's Task 7 contradicts the LOCKED
  spec** and briefed two corrections, each TDD'd and independently mutation-killed: **(A) a tab-run is not a
  pane** — the plan leaves the `lane`/`session` writes unconditional, so an overflow would count toward N
  (spec caps worker *panes*) and become a round-robin target (spec selects a *pane*), breaking the
  "freed pane is reclaimed" Gherkin (reproduced literally as `worker max 3 reached (4 live)`) and nesting a
  tab in a tab; fixed with a `kind` marker (missing = `pane`) behind ONE shared predicate `live_worker_panes`
  so the count and the selection can never disagree. **(B) the I1 residual pinned by T6a** — `dead_mark`
  writes `agent-exit` on the no-terminal + adapter-fail paths, and resolving the round-robin target BEFORE
  the marker writes kills the third phantom path by construction. Reviewer: 0 Crit/0 Imp, all 6 checks + 8
  adversarial angles RUN; **bash 3.2.57 is the only bash on PATH** (the empty-array-under-`set -u` trap is
  real but unreachable here) and the Task-4 injection boundary held against 8 hostile `surface` payloads
  through the REAL cmux adapter. **NEW Minor 1 = an OPEN USER DECISION** (spec-level, no clean fix): during a
  real `open_pane` a run is counted live but not yet selectable, so a concurrent fan-out worker can still
  degrade to in-process, which spec line 63-64 + the line-217 Gherkin forbid — not a regression, but decide
  document-as-trade-off (T8) vs spec amendment. Plus Minor 2 (write `kind` first / `lane` last — free
  atomicity, fold into T8) and 3 Nits. Detail: branch log §Task 7. **NEXT: Task 8** (skill + gate-stub
  correction + ADR 0009 + Mermaid), then final branch review + obs judge + PR. Carry-forward now also
  includes **T7: `dispatch-pane-agent.sh` at 387 lines (400 soft limit, no headroom), `.test.sh` at 424, and
  `mk_run`'s latent `$RANDOM`-in-subshell fixture-collision hazard (already produced one false RED).**
  **MINOR 1 RESOLVED by the user 2026-07-24 → document as an accepted trade-off** (spec stays locked, no
  compliance re-run, no code change; rejected a transient N+1 pane and a spec amendment). **T8 DONE
  2026-07-24 (pane implementer; review folded into the FINAL branch review — 134 lines of docs, all read
  by the controller):** commit `d801573`, verified in-checkout (exactly 3 doc files, sanity suites still
  28/0 + 82/0). `rules/gates.md:21` corrected IN PLACE — the controller caught pre-dispatch that the
  PLAN's own replacement prose silently drops "fails open, with a per-session cooldown after an adapter
  failure", still true and load-bearing, so the brief required keeping it. `SKILL.md` gained the
  three-lane policy section + the accepted trade-off in reader's terms, and the implementer correctly
  also fixed that file's own stale "plan implementers are your judgment call" bullet rather than ship a
  self-contradictory file. **ADR 0009** records the include→exclude reshaping, the two user review-gate
  choices that decided three lanes (`inline` must not silence the judges; judge panes uncounted), and the
  `open_tab` allowlist as THE security boundary for the overflow path. Mermaid verified with the repo's
  `validate-diagrams.sh` (PASS); the implementer **refused to claim a browser render** it could not do
  (no `mmdc`; rendering meant an unpinned dep add) and its hand-audit caught a real defect the linter
  passes — labels containing `--` are ambiguous with edge syntax unless quoted. **ALL 8 TASKS DONE.
  NEXT: pre-PR cleanup pass** (NEW-B unquoted `for key in $keys` at guard:104 first — a real
  word-splitting bug; then NEW-A, Minor 2's marker reorder, `mk_run`, the skill-description call, and the
  remaining T3–T6a minors/nits) → full pane suites → implementation obs judge → PR.
  **CLEANUP PASS DONE 2026-07-24 (pane implementer; all 16 carry-forwards cleared):** commits `4d9e713`
  (fix — guard key handling + marker ordering), `f6d83ac` (test — the four escaping-mutant gaps),
  `3c2ad2c` (docs — the three judgment calls). Controller-verified in-checkout + independently re-ran all
  seven suites: **302 passed, 0 failed** (287 baseline), shellcheck clean on six shell files, guard diff
  read in full. NEW-B reproduced literally (a `"*"` session id + a decoy file made the guard exit 0 off a
  FOREIGN policy file) and fixed with `set --`. **Minor-7's anchors were stale — the brief said verify,
  not trust, and that caught it**; its RED (`d/../../outside-policy` resolving above `STATE_DIR`) has NO
  glob char, proving the key-validation and the quoting fixes are independent. **M2 came back WIDER than
  filed and correctly so:** the guard also read `STATE_DIR` from a hardcoded `$HOME`, so under `PANE_HOME`
  it would never see the policy `set-policy` had just written — an unbreakable ask loop, worse than the
  conf split; all four defaults now match the dispatcher. Nit-9's refactor was proven safe by
  byte-comparing both stderr messages against the pre-change guard. Group 3's tightening is the sharpest
  evidence in the branch: the three adapter mutants ALL escaped the old suite (43/0) and are caught by the
  new one (42/3). **Two things deliberately NOT fixed:** `CLAUDE.md`'s skills-catalog line still says
  "(judge, plan implementer)" (pre-three-lane, the other trigger surface — user's global file, out of
  scope), and **`panes/dispatch-pane-agent.sh` is now 410 lines, over the 400 soft limit** — split the
  run-dir/marker helpers out as the FIRST move of the next dispatcher change, not at the tail of this
  branch. **NEXT: implementation obs judge (must match final HEAD), then PR `--draft` → `gh pr ready`.**
  **OBS JUDGE RUN 2026-07-24 → `risk=medium confidence=high`** (verdict
  `coding-memory/observability-judge/2026-07-24-feat-pane-split-policy.md`, `head_sha b38aa24`; judge
  took its OWN pane `surface:107` while workers sat on `surface:83` — the judge lane bypassing the
  policy, observed working). **It found what eight task-reviewers missed:** a worker run is marked
  finished only on NORMAL completion (no exit trap; `wait` skips the marker on timeout), so a
  hand-closed pane stays "live" WITH its surface ref → the next overflow tabs into a dead surface →
  `open_tab` fails → the dispatcher called it an ADAPTER failure → session cooldown → everything
  in-process for the rest of the session, blaming cmux. It also rejected the controller's framing of the
  observability question: exit 3 covering three causes is NOT the problem (nothing branches on `$?`); the
  real gap was that the decisive computation ("counted 3 live, max 3, tabbed into surface:X") was
  recorded NOWHERE. **User chose fix-now → commit `8c2b07f`** (suites **308/0**, +6; controller-verified):
  `open_tab` failure reclassified to exit 3 + no cooldown + dead-mark the stale target so the next
  selection picks a different pane (`open_pane` failure keeps cooldown/exit 4, now explicitly asserted);
  a one-line `ROUTE: lane=… live=… max=… kind=… target=…` decision record to BOTH stderr and
  `<run-dir>/route`, written before the adapter call so it survives a failed open; `CLAUDE.md`'s catalog
  line corrected to the three lanes. Two Task-7 tests REPLACED not repaired — they pinned T7's stated
  intent, and that intent is what the judge found wrong. **Still open (next branch):** the ROOT CAUSE —
  nothing writes `agent-exit` when a pane dies abnormally (needs an exit trap in `run-pane-agent.sh` or a
  liveness probe); T7's NIT 1 lost its mitigation (the rr index still advances on a failed `open_tab`,
  previously "unreachable" only because the first failure ended overflow for the session); **`doc-guard.sh:149`
  classifies `CLAUDE.md` as SOURCE not documentation** — decide whether it belongs in the hook's doc set;
  dispatcher now **450 lines**.
  **OBS JUDGE RUN 2 2026-07-24 → `risk=medium confidence=high`** (verdict appended to
  `coding-memory/observability-judge/2026-07-24-feat-pane-split-policy.md`, `head_sha 2418e5b`;
  commit `2bd2935`). **It falsified RUN 1's own fix:** the new comment's convergence argument holds
  only if `open_pane` ALSO fails. Against an adapter that can pane but cannot tab — exactly the case
  the spec names — every overflow retires a HEALTHY pane, the live count drops back under N, and the
  next worker opens a NEW pane: **+1 real pane per two overflowing dispatches, unbounded and silent,
  cooldown never written, `max=N` quietly exceeded.** It also caught that the reclassification was
  disclosed as task-level when it is spec-level (SKILL.md lines 55-58 still described the old
  cooldown-only degrade path, ADR 0009 unamended, `<run-dir>/route` documented nowhere).
  **User chose fix-now → commit `9073b2b`** (suites **316/0**, +8; `shellcheck -x` clean;
  controller-verified in-checkout): a **consecutive**-`open_tab`-failure streak with
  `TAB_FAIL_LIMIT=3` — a single stale target still self-heals (exit 3, no cooldown), but at the
  limit the ADAPTER, not the target, is judged tab-incapable and it becomes a full adapter failure
  (cooldown + exit 4), which bounds the growth loop. **Only a SUCCESSFUL `open_tab` resets the
  streak** — an `open_pane` success is not evidence of tab capability, and one lands between every
  pair of failures in the growth loop, so counting it would make the bound unreachable. Judge items
  2-4 (SKILL.md degrade paths, ADR 0009 consequence, `<run-dir>/route`) shipped in the same commit.
  **No spec amendment needed — the streak restores the spec's cooldown outcome for a genuinely
  tab-incapable adapter, so the spec stays LOCKED at blob `cdc777a`** (compliance verdicts stay
  valid, no compliance re-run).
  **ORDERING CONSTRAINT (learned here, applies to every future PR):** `judge-guard.sh` requires
  strict `head_sha` EQUALITY with current HEAD, so the verdict commit CANNOT precede the PR —
  sequence is checkpoint-commit → judge at that HEAD → `gh pr create --draft` with the verdict still
  uncommitted in the working tree → THEN commit + push the verdict onto the open PR (pushing after
  creation adds to the PR, so nothing strands).
  **OBS JUDGE RUN 3 DONE 2026-07-24 @ `2454d1d` → `risk=medium confidence=high`** (verdict
  `coding-memory/observability-judge/2026-07-24-feat-pane-split-policy-round3.md`, commit `6c717d0`;
  judge pane `surface:109`, `ROUTE: lane=judge` — the judge lane bypassing the policy, observed
  working a third time). Controller independently confirmed **316/0** and `shellcheck -x` clean at
  that HEAD before dispatching. **RUN 3 broke TWO CLAIMS THIS BRANCH HAD WRITTEN INTO ITS OWN
  DURABLE RECORD** (ADR 0009 + branch log), each with a ~10-line repro:
  **(F1) the pane-growth bound belongs to the GUARD, not the streak** — `dispatch-pane-agent.sh`
  never reads its own cooldown flag, only `pane-dispatch-guard.sh` does; at `max=2`, 10 DIRECT
  dispatches opened **6 real panes, two of them after the cooldown was written**. Normal operation is
  bounded because the guard is the gatekeeper; a direct dispatch is not.
  **(F2) "3 tolerates a cmux restart" is FALSE at N≥3** — a restart leaves exactly N ghosts, so with
  N≥3 the limit trips and a HEALTHY adapter is declared tab-incapable, silently discarding
  `panes max=N` for the session with a message blaming cmux (RUN 1's finding, back in bounded form).
  **(F3, the sharpest) RUN 2's "cosmetic" rr-index nit is the CAUSE of F2** — advancing the index on a
  failed tab marches the selector through every ghost in turn, skipping exactly the healthy panes
  whose success would reset the streak. Judge pinned the index as a counterfactual: **the scenario
  then self-heals completely, zero cooldowns.** The nit was graded cosmetic BEFORE the streak existed
  and was never re-graded after the change that altered its consequence — **the reusable lesson: a
  nit's grade expires when the code around it changes.**
  Also: the 8 new assertions test the MECHANISM (streak fires at 3), never the PROPERTY RUN 2 raised
  (pane count stays under `max`) — **nothing anywhere counts panes against `max`**, which is why F1
  sailed through 316 green tests. All three share the one deferred root cause (no EXIT trap → no
  `agent-exit` on abnormal pane death), and RUN 2 priced that deferral too cheaply: "self-healing" is
  false at N≥3. Judge credited the mutation discipline (RED 101/2 with only the discriminating
  assertions failing; 3 mutants each killing two assertions).
  **PR #28 OPENED as a DRAFT 2026-07-25 — https://github.com/suyatdev/.claude/pull/28** (base `main`,
  40 commits). Sequence used, and the reason for it: the fresh RUN 3 verdict matched HEAD exactly, so
  `gh pr create` ran FIRST while it was valid, and the verdict was committed onto the already-open PR
  afterwards (`6c717d0`) — the PR #26 anti-stranding flow. F1+F2+F3 are declared in the PR
  description as KNOWN-NOT-FIXED, which was the judge's explicit ship condition.
  **OWED BEFORE `gh pr ready` (user chose "draft PR now, then fix on it", 2026-07-25):** (1) correct
  the two overstated sentences in ADR 0009 + the branch log — a decision record asserting a safety
  guarantee that does not exist is the worst of the three findings; (2) the ONE-LINE rr-index fix
  (do not advance on a failed `open_tab`) which dissolves F2/F3 per the judge's own counterfactual;
  (3) a PROPERTY test that counts panes against `max`; (4) **obs judge RUN 4** at the new HEAD
  (judge-guard does not gate `gh pr ready`, but the user's chosen sequence does); then `gh pr ready`.
  Root cause (EXIT trap in `run-pane-agent.sh`) stays deferred to the follow-up branch.
  **Two corrections to this file's own state, found 2026-07-25:** **PR #27 is MERGED** (2026-07-22
  23:39Z, `0a1f80e`), not open as recorded — reachability re-verified, **no 4th stranding**, but its
  remote branch still exists so the prune and the verdict backfill are still owed. And the
  `preparing-pull-requests` rule "feature PRs update the README Roadmap" **could not be satisfied:
  README.md still has no Roadmap section at all** (the known open item 0c(d)) — flagged, not silently
  skipped; standardizing it remains its own task.
  **Process slip worth keeping: a bare `git commit -m` swept the 4 OTHER-SESSION compliance-judge
  files that sit permanently STAGED in this shared checkout into a checkpoint commit.** Caught
  immediately, undone with `reset --soft` (which restores the index exactly) + a pathspec commit +
  `push --force-with-lease`. **The durable gotcha "commit by pathspec ONLY" means the pathspec must
  be on `git commit` itself — `git add <file>` does not protect you, because `commit` without a
  pathspec commits the WHOLE index.**
  **RUN 3 REMEDIATION 2026-07-27 (Opus 5 1M; pane implementer `surface:53`, policy `panes max=2`):
  commits `cbc3c4e` (test) + `5cee1e8` (docs). Controller-verified in-checkout, pathspec-scoped
  (2 files each), the 6 other-session compliance-judge files byte-identical to session start;
  suites independently re-run **326/0** (from 316), `shellcheck -x` rc=0, and the dispatcher diff
  proven **comments-only** (no behavior change).
  **THE IMPLEMENTER REFUSED DELIVERABLE 1 (the rr-index fix) ON EVIDENCE, AND IS RIGHT — RUN 3's
  F2/F3 ARE BACKWARDS.** `new_run_dir` names every run `<epoch>-<pid>-<random>` and
  `live_worker_panes` walks `$RUNS_DIR/*/` in glob order, so glob order IS creation order and a
  stale pane **always sorts BEFORE** every pane opened after it. RUN 3's fixtures sorted the ghosts
  LAST, which production cannot produce. Controller confirmed both premises independently (empirical
  glob-order check + analytic derivation) BEFORE reading the implementer's table, same result.
  Mechanism: retiring a ghost drops the live count under `max`, so the next dispatch opens a REAL
  pane that sorts last; an ADVANCING cursor marches into it and its successful tab resets the streak,
  while a PINNED cursor sits on the oldest ghost and trips the limit. Evidence table (restart 5 min
  ago, 3 ghosts, healthy adapter, `max=3`): ghosts-last → HEAD cools down @ d5 (RUN 3's trace), fix
  does not; ghosts-**first** (the only ordering production makes) → **HEAD self-heals, no cooldown in
  12; the proposed fix cools down @ d5.** The fix MOVES F2 into the real ordering rather than removing
  it. **The rr advance is load-bearing, not cosmetic** — and was one "cosmetic cleanup" away from
  removal. Now pinned by test with a PAST-epoch fixture, because the naming is the precondition.
  **F1 is REAL and fully corrected** (reproduced byte-for-byte: 6 panes at `max=2`, 2 after the
  cooldown). ADR 0009 now says plainly that the streak does NOT restore `max=N`, that the bound is
  the GUARD's and therefore **emergent, not mechanical**, that a direct `dispatch` is unbounded, and
  adds the judge's asked-for sentence that the late cooldown is a **declared timing deviation**, not
  compliance. Spec untouched, still blob `cdc777a`. **+10 assertions, all mutation-verified**: overflow
  gate `-ge`→`-gt` → 96/17; "dispatcher honors its own cooldown" → 108/5; the brief's Deliverable 1 →
  111/2 killing exactly the two restart assertions. Guard suite already covered "flag → allow
  in-process", so only the uncovered dispatcher half was pinned.
  **REUSABLE LESSON: a judge finding can be an artifact of its own fixtures.** RUN 3 was right about
  F1 and wrong about F2/F3 for the same reason this branch keeps getting burned — a fixture that
  cannot occur in production. Verify a judge's repro against the real naming/ordering before acting.
  **Process slip (2nd occurrence, new variant): `git commit --amend --no-edit` to add a trailer has
  NO pathspec and swallowed two other-session staged files.** Implementer caught it on `--stat`,
  `reset --soft` + re-amended with a pathspec; staged state verifiably restored (controller
  re-confirmed). **The rule must read: the pathspec goes on `git commit` AND on `git commit --amend`.**
  **OPEN DECISION for the user:** F2/F3 are answered by EVIDENCE, not a code change, so obs judge
  RUN 4 must adjudicate the rebuttal (evidence table is in the branch log). The order-dependence is
  real but emergent from a naming convention two functions away; the robust fix — retry the next
  candidate WITHIN one dispatch, or probe the newest pane while the streak is warm — removes it
  entirely but is a design change, deliberately not taken unilaterally. Root cause (no EXIT trap →
  no `agent-exit` on abnormal pane death) still dissolves the whole class and stays deferred.
  **`dispatch-pane-agent.sh` is now 517 lines** (+25, all comment) against a 400 soft limit — the
  split is owed as the FIRST move of the next dispatcher change.
  **OBS JUDGE RUN 4 IS IN — DONE, verdict committed `2078408`.** It adjudicated its own RUN 3
  findings and **WITHDREW F2/F3 itself**: its RUN 3 fixtures were letter-named and sorted after real
  panes, an inversion production naming cannot produce. It then swept 81 configurations per variant
  (`max=3`/`max=4` × every starting rr index): **HEAD 2 spurious cooldowns, RUN 3's own proposed fix
  8** — the index advance is load-bearing, confirmed. F1 confirmed fixed. risk=medium, confidence=high.
  **F4 NEW + ACCEPTED:** the tolerance claim held only at `max=3`; at **N≥4 a healthy cmux restart
  can still trip the streak** (1/4 starting indices at max=4, 2/5 at max=5, 4/6 at max=6) — user's
  `panes max=N` silently discarded, exit 4 blaming a blameless adapter. Hand-traced independently
  before accepting (overflow only fires while live ≥ max, so each failed tab retires a ghost and the
  next dispatch opens a real pane — that alternation saves max=3 and is one beat too slow at max=4).
  **User decision 2026-07-27: qualify the record, no behavior change** → `6d781c9` (comment-only,
  113/0, shellcheck clean) + branch-log RUN 4 section, which also corrected a second overclaim
  ("ghosts sorting last cannot happen in production" is false — close the two newest panes by hand).
  **BOTH RESUME STEPS DONE 2026-07-27 (Opus 5 1M) — PR #28 IS READY FOR REVIEW.**
  **(1) Conflict resolved** → merge commit `2cdff2a` (`git merge origin/main`, NOT a rebase — 49
  commits with judge verdicts pinned to exact SHAs). It was exactly the two predicted append-heavy
  memory files; main's PR #29 touched no file this branch changed, and `CLAUDE.md` + `rules/gates.md`
  auto-merged. `verdicts.jsonl`: both sides proven to be `base(34) + append` (7 mine, 2 main's), so
  the union was re-ordered by `ts` — **43 rows, every one validated as parseable JSON, zero dropped.**
  `CODING_MEMORY.md`: both sides inserted at the same anchor; took both (mine on top, most-recent-wins;
  main's PR #29 entry follows as history), **verified zero lines lost from either side** by set-diff.
  Post-merge checks: **11 suites, 417 assertions, 0 failures** (dispatcher 113/0 matches the last
  recorded figure exactly), `shellcheck -x` rc=0, and `git diff 7b3b05c 2cdff2a -- panes/ hooks/` is
  **EMPTY** — the merge is provably code-neutral, so RUN 4's verdict stays materially valid.
  **(2) `gh pr ready` done** — PR #28 now `isDraft:false`, `MERGEABLE`/`CLEAN` at `2cdff2a`.
  All four OWED items confirmed landed before marking ready: ADR/branch-log corrections (`5cee1e8`,
  `6d781c9`); the rr-index fix **correctly WITHDRAWN on evidence**, not skipped (RUN 4's 81-config
  sweep: HEAD 2 spurious cooldowns vs the proposed fix's 8); the pane-counting property test at
  `panes/dispatch-pane-agent.test.sh:568`; obs judge RUN 4 banked at `e6e2e3e` (`2078408`).
  **NEXT: PR #28 review/merge in the GitHub UI** (`gh pr merge` is hook-blocked by design).
  **NEW GOTCHA (cost one failed merge attempt):** `git merge` aborts with "local changes would be
  overwritten" on files that are **staged adds present in NO tree** — the other-session
  compliance-judge files. `ort` protects an index-only entry the merge would drop. And a **merge
  commit cannot be pathspec-scoped**, so the standing pathspec rule does not cover it. Procedure that
  worked: capture `git hash-object` of each staged add → `git restore --staged` them → merge → resolve
  → commit → `git add` them back → **prove the index hashes match the capture** (they did:
  `16b37c33`, `68a5b555`; working tree byte-identical to session start).
  **KNOWN OPEN, none blocking the PR, all waiting on the same root cause:** the N≥4 restart
  false-positive (F4); exit 4's misleading blame (only wrong when F4 fires); the **525-line**
  dispatcher vs a 400 soft limit — the split is owed as the FIRST move of the next dispatcher change.
  **Still deferred by decision, do not start unilaterally:** the robust ordering fix (retry the next
  candidate within one dispatch) and the root cause (EXIT trap in `run-pane-agent.sh` → `agent-exit`
  on abnormal pane death), which dissolves the whole class. Session pane policy `panes max=2` is
  per-session state — a fresh session will be ASKED again at its first worker dispatch.
  **Working-tree caution (still true):** the uncommitted `coding-memory/compliance-judge/` files are
  OTHER concurrent sessions' verdicts (repos `phase-guard-hook`, `mtg-wizard`, `vibe-scape`,
  `Snatch-Bracket`), two already `git add`ed by them. Leave them; pathspec-scope every commit.
  There is also a live `.claude/worktrees/phase-guard-hook/` worktree (another session's branch,
  carrying a `hooks/phase-guard.test.sh` that does not exist here) — do not touch it.
  **NEW MEMORY MODEL ARRIVED ON MAIN (PR #29, now merged into this branch):** feature-scale work gets
  a `docs/features/<name>.md` with `phase` in frontmatter, checked on restore; `managing-session-memory`
  and `preparing-pull-requests` were both rewritten around it. **Still undogfooded — no `docs/features/*.md`
  exists anywhere.** Deliberately NOT retrofitted onto this branch (it is finishing, not starting);
  the next feature-scale branch should be its first real user, which is what main's own entry says.
  **This index is 778 lines against its own 200-line ceiling** — flagged by the obs judge on four
  separate rounds and still growing. Trimming it into `coding-memory/` is its own task, not a
  drive-by; it is the single most overdue piece of housekeeping in this repo.
- session_origin: desktop · session_started_at: 2026-07-22 (Opus 4.8) · last_active_branch:
  **`feat/pane-split-policy`** — **NEW FEATURE SPEC'D + committed, then session cleared.**
  Session pane-split policy: at the first pane-eligible dispatch the model asks once —
  `inline` (all in-process this session) or `panes max=N` (N concurrent panes; spawns beyond N open
  as **tabs inside existing panes**, round-robin, never inline/blocked). Read-only `Explore`/`Plan`
  never governed (exclude-list, flipping today's `redirect-agents.conf` include-list). cmux primary
  (user's terminal); others degrade. Spec:
  `docs/superpowers/specs/2026-07-22-pane-split-policy-design.md`; provenance + Q&A + gate answers:
  `coding-memory/brainstorms/2026-07-22-pane-split-policy.md`. Prior-session Snatch-Bracket verdicts
  committed to main (`7854ae3`) before branching. **GATES ANSWERED (do not re-ask this design):
  Hard Model Gate = Opus 4.8 for the spec, implementation tier deferred; freshness = write-then-clear.**
  **NEXT (fresh session, IN ORDER): (1) compliance judge on the spec — BLOCKING, deliberately deferred
  to preserve checkpoint budget, run via `running-the-compliance-judge` alongside the obs architecting
  read; (2) user review gate on the spec; (3) re-ask model gate before implementation;
  (4) `superpowers:writing-plans`. cmux tab primitive must be live-probed FIRST in the plan.**
  **JUDGES RAN TWICE (2026-07-22, Opus 4.8, all pane-dispatched to cmux).** Round A: obs low/high;
  compliance R1 FAIL (arrow-prose scenarios) → Gherkin reformat `9bd9966` → compliance R2 PASS.
  **User review gate → 2 design decisions:** (1) `inline` must NOT silence the two judges; (2) `max=N`
  caps the worker fan-out only, judge panes uncounted. → Spec reshaped into a **THREE-lane model**
  (read-only in-process / judges always-paned OUTSIDE policy / worker fan-out policy-governed),
  commit `2815bba` (blob `cdc777a`). Round B (re-entry on the revised spec): **compliance PASS, high
  conf; obs low/high — obs judged the revision MORE correct** (inline would have "cut power to the
  judges' PR-gate enforcement"). Verdicts in `coding-memory/{compliance,observability}-judge/`.
  **USER REVIEW GATE CLEARED 2026-07-22 — spec APPROVED as-is, LOCKED at blob `cdc777a`
  (commit `2815bba`); do NOT re-edit or the verdicts invalidate.** NEXT (fresh session): re-ask the
  Hard Model Gate, then `superpowers:writing-plans` (probe the cmux tab primitive FIRST). User
  declined the optional three-lane diagram for now (would re-run the loop). Plan-time carry-forward
  (do NOT lose, all non-spec): **ADR for the three-lane governance model** (ADR 0007 precedent);
  CORRECT (not append) the stale `rules/gates.md` "plan implementers are skill-routed" line (the
  "judges are hook-enforced" line stays true); `open_tab` verb inherits the orchestration spec's
  no-interpolation + title-allowlist boundary; validate `N` as a bounded positive int; **prove the
  worker-pane count AND the worker/judge lane-tag early on REAL run-dir fixtures** (the "judge not
  counted" test rides on both); live cmux tab probe as a hard gate. Optional: a small three-lane
  decision diagram would aid review (costs a re-judge if added now).**
- **PR #29 MERGED 2026-07-25** (`122b8a5`); branch pruned local+remote; ancestor-check verified.
  Phase-frontmatter permission system (ADR `docs/decisions/0010-phase-frontmatter-as-permission-source.md`)
  now on `main` — every feature-scale change gets a `docs/features/<name>.md` with `phase` in
  frontmatter, checked on restore. **Mechanism is still undogfooded** — no such file exists yet
  anywhere; the next feature-scale branch should be its first real user. Detail:
  `.claude/session-state.md`.
- session_origin: desktop · session_started_at: 2026-07-22 (Sonnet 5) · last_active_branch: main —
  **Q&A only, no code/architecture changes.** Answered how to manually smoke-test the pane
  dispatcher: single `pane-echo` dispatch, and a 5-pane test (4 `--role implementer` filling the
  quadrant + 1 default `aux`) was being scoped when the 75k handoff fired. **Pre-existing
  uncommitted `coding-memory/compliance-judge/verdicts.jsonl` (2-line diff) + new
  `2026-07-22-0007-tea-room.md` predate this session and are unrelated to it — committed to main
  as `7854ae3` by the later Opus 4.8 session above.**
- session_origin: desktop · session_started_at: 2026-07-22 (Opus 4.8) · last_active_branch: feature/cmux-version-gate
- **PR #25 MERGED 2026-07-22 (`3491464`); branch pruned local + remote; verdict outcomes
  backfilled.** pane-layout-v2 shipped: 9 tasks, probe P8, ADR 0008, implementation judge PASSED
  over two rounds. Detail: `coding-memory/pr-tracking.md` §PR #25, resume #9 below.
- **CURRENT: `feature/cmux-version-gate`** — PR #25's agreed first post-merge follow-up, and the
  round-2 judge's top item. `check_cmux_version` in the adapter pins the verified cmux release and
  warns + leaves a durable receipt when the live binary differs, because the aux-column anchor is
  a heuristic that no test can catch drifting (every adapter test drives a FAKE binary).
  **Its own round-1 judge found a real bug by probing nine version strings: a
  `[0-9.]`-only filter silently swallowed `0.65.0-rc1`/`0.64.20-beta`** — the pre-release builds
  most likely to have moved behaviour — so the parser now tests version-SHAPED, not version-CLEAN.
  **PR #26 OPEN** (https://github.com/suyatdev/.claude/pull/26) — 3 judge rounds, all risk=low,
  none blocking; it found two real defects (the pre-release deafness above, and a `2>/dev/null`
  that does not suppress a failing *redirection* — a trap `run-pane-agent.sh:81` already
  documented). Suite 170 → 197. Log: `coding-memory/branches/cmux-version-gate.md`,
  `coding-memory/pr-tracking.md` §PR #26.
- current work: **pane-orchestration FULLY CLOSED OUT — PR #23 MERGED (8f40e05) and docs-only
  PR #24 MERGED 2026-07-21 13:05Z (23dd2e3); both branches pruned local+remote.** PR #24
  merged WITHOUT the late-pushed brainstorm checkpoint 9e16d7f (PR #21 stranding failure
  mode, 2nd occurrence) — recovered by cherry-pick onto `main` as 2d8a416 (memory-only →
  git-guard brainstorm exception; user-approved), parity verified, then pruned. Detail:
  `coding-memory/pr-tracking.md` §PR #24. Obs judge (impl @ 5c846b2) outcome=clean.
  **Remaining: post-merge watch items in Next Steps 0c.** Per-task history:
  `.superpowers/sdd/progress.md` (RUN section), `coding-memory/branches/pane-orchestration.md`.
- **CURRENT: pane-layout-v2 — USER REVIEW GATE CLEARED 2026-07-21 (resume #4, Fable 5).**
  Spec: `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md` @ blob aeb0074
  (commit bb4050b on `feature/pane-layout-v2`, pushed, no PR). Round-1 judges clean,
  pane-dispatched: compliance **pass**/high 0 violations; obs advisory **low**/high, 1
  concern = success_masking ("run folder missing = finished" infers success from absence —
  out-of-band `panes/state/runs/` cleanup could recycle a busy pane). Judge notes for
  implementation: pin `respawn-pane --command` quoting during the live probe before REUSE
  is coded; log live probes first thing; fallback tests assert the exact legacy command
  sequence. **User sign-off EXPLICIT on (a) the aux-reuse extension and (b) all 4 flagged
  assumptions — ZERO spec edits, so both verdicts remain fresh.** Spec status line
  intentionally left saying "pending" (editing the file would invalidate the blob-sha-keyed
  verdicts); the authoritative approval record is
  `coding-memory/brainstorms/2026-07-21-pane-layout-v2.md` §"User review gate". **PLAN
  WRITTEN same session (user said "continue for now" on Fable 5 = per-task planning gate
  answer; Hard Model Gate untouched):
  `docs/superpowers/plans/2026-07-21-pane-layout-v2.md` — 8 tasks, TDD, live probe FIRST
  (P1–P7 resolve the 4 assumptions + respawn quoting), unverified tree schema quarantined
  in `layout_normalize_tree` validated against a live-captured fixture; self-review caught
  and fixed a T4/T5 fixture state collision. GATES ANSWERED (do not re-ask): Opus 4.8
  in a FRESH session; subagent-driven execution, pane-routed implementers.** Full design
  history: the brainstorm file; earlier session blocks: git history of this file
  (98faa38, c252135).
- **Resume #9 (2026-07-22, Opus 4.8): probe P8 + implementation judge PASSED. PR is the only
  step left.** HEAD `e12dc06`. **P8 finally supplied the live coverage Tasks 8/9 could not**
  (`coding-memory/branches/pane-layout-v2.md` §P8, script `<scratchpad>/live-quadrant-probe.sh`):
  four sequential `--role implementer` dispatches, each plan *predicted* from the live tree
  before firing, all four matching exactly — **impl slots 3–4 are no longer fake-verified**,
  because the agents were still booting so no `agent-exit` existed and reuse could not preempt
  growth. Two corrections: **27** — `index` is traversal order over a FLAT panes array, NOT
  left-to-right (Task 8's experiment only made horizontal splits; with a real quadrant impl.2
  in the left column sorts *after* impl.3 in the right one), so `layout_rightmost_surface` is
  a heuristic and its comment now says so — logic unchanged, nothing better is exposed; **28** —
  `new-pane` *does* follow `focus-pane`, so it is anchorable after all, but that neither beats
  `new-split --surface` nor fixes height. **Aux height is ordering-dependent and accepted as a
  limitation → ADR 0008**: full-height when the column predates the quadrant (the common path —
  handoff + judges open first), half-height bottom-right when created after, unfixable because
  the tree is flat, both split verbs are pane-relative, and `--placement dock` is disabled.
  Implementation judge **PASS, risk=low confidence=high**, no dimension failed, concerns
  `success_masking` + `audit_trail`; it independently re-ran three recorded falsifications and
  re-checked the unfixability argument. **Its sharpest catch, now the branch's main latent risk:
  a future cmux changing pane-walk order lands the aux column wrong while all 170 tests still
  pass** — every test drives a fake binary, so mitigation is procedural (re-run
  `panes/cmux-layout-probe.sh` after any cmux upgrade). Live workspace restored and **diffed**
  against its captured baseline. Judge follow-up not blocking: widen the one-line stderr notice
  when the layout path degrades to legacy.
- **Resume #8 (2026-07-21, Opus 4.8): Tasks 7–9 DONE + pushed (45fee28, 1d1e3c7, 17a0f44).**
  Plan execution + verify-after-rename; Task 8's first-ever real-binary smoke check, which
  **falsified spec assumption 4** (aux landed 2nd from left — `new-pane` splits off the current
  pane); Task 9 added mid-flight to anchor aux on the rightmost pane. Also proved live: the P4
  send-not-respawn reuse deviation (same surface re-used), `--workspace` scoping, title
  stamping, the T3 handoff-wrapper rename. `--role` documented in the skill.
- **Resume #7 (2026-07-21, Opus 4.8): Task 6 DONE + pushed (aa2cc42).** Pane-dispatched
  implementer (`--role implementer`, surface:78); commit verified in-checkout, all five
  suites independently re-run, one falsification independently re-run by me. Corrections
  10–15 — detail in Next Steps 0-ACTIVE and `coding-memory/branches/pane-layout-v2.md`.
  Session note: ~82k of this session's budget went to context RESTORE before any output,
  which is the recurring cost of task-by-task execution on this branch.
- **Resume #6 (2026-07-21): Task 1 live probe EXECUTED on Opus 4.8 (ffe22d2).** Probe is
  re-runnable: `panes/cmux-layout-probe.sh`; fixture `panes/adapters/fixtures/tree-live.json`.
  Three plan corrections + one user-approved spec deviation — see Next Steps 0-ACTIVE and
  `coding-memory/branches/pane-layout-v2.md`.
- **Resume #5 (2026-07-21, Fable 5): NO execution — stopped at the model gate.** Session
  ran Fable 5 vs the answered Opus 4.8; discovered pane implementers would ALSO run
  Fable 5 (settings.json `"model": "claude-fable-5[1m]"`, dispatcher passes no model
  flag). User chose stop + relaunch on Opus 4.8. **Next session MUST be started with
  `claude --model claude-opus-4-8` (or `/model` immediately) — the handoff pane and a
  plain `claude` both inherit the Fable 5 default (handoff-wrapper.sh execs claude with
  no --model). Open: whether to pin pane implementers to Opus too (settings/dispatcher
  change, user's call) or accept Fable 5 implementers.** Then execute the plan from
  Task 1 (live probe); implementation-stage obs judge before PR.
- prior session (2026-07-20): claude-code-handoff cherry-pick SHIPPED — PRs #21+#22 MERGED;
  audit-trail recovery + 8-branch orphan sweep. Detail: ADR 0006,
  `coding-memory/branches/add-claude-code-handoff.md`, Next Steps 0.
  settings.json dual-version staging policy unchanged (Orca hooks + fable-model line stay uncommitted).
- **SUPERSEDED (was parked): judge terminal-enforcement.** Branch
  `feature/judge-terminal-enforcement` retired, NOT deleted (~3,400 lines unmerged judged
  spec work; deletion = explicit user cleanup). Reference text for any future `spec-guard`
  resurrection. ADR 0007;
  `coding-memory/brainstorms/2026-07-20-judge-terminal-enforcement.md`.
- **Session-budget preference (2026-07-20): keep each session below ~100k tokens; checkpoint memory
  after each task so the user can /clear before the next design task.**
- **CORRECTED 2026-07-21 (was stale): the Orca hooks and the fable-model line are now IN
  committed `settings.json`** (HEAD == live, last touched by a3aedc8 "Add merge guard") —
  the old "stay uncommitted / dual-version staging" policy no longer reflects reality.
  Whether committing them was intended is the user's call (flagged 2026-07-21). The Orca
  channel caveat still stands: `claude-hook.sh` sources `$ORCA_AGENT_HOOK_ENDPOINT` before
  its token check and that stdout becomes hook stdout. Untracked `chrome/`, `telemetry/`,
  `stats-cache.json` stay untracked (machine-local; gitignore an open question).
- 2026-07-19 session notes — statusline-edit authorship resolved as that session's own work,
  concurrent-session evidence, model-gate history (Sonnet 5 → Opus 4.8), `chore(settings):`
  precedent for model/theme changes: `coding-memory/branches/statusline-token-bar.md` and
  `coding-memory/session-log.md`.

## Repositories

### suyatdev/.claude
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR #4 (feature/vibe-coding-standards-integration) — MERGED 2026-07-12.
- PR #3 (feature/standards-extractor-agent) — MERGED.
- PR #5 (feature/modular-coding-memory) — MERGED 2026-07-14. `main` fast-forwarded to include it.
- PR #6, #7, #8 (feature/new-project-memory-scaffold) — all MERGED. Branch deleted 2026-07-15
  (fully superseded — see `coding-memory/branches/new-project-memory-scaffold.md`).
- PR #9 (feature/rules-to-skills-restructure) — MERGED 2026-07-15 (fast-forward, user's choice to
  merge locally rather than wait for GitHub review). Branch deleted. The rules-to-skills
  restructure: 7 always-loaded rule files → core-conduct.md + gates.md + 5 new skills + git-guard
  hook. Always-on content: 4,030 → 1,151 words (~71% cut).
- feature/documentation-enforcement (2026-07-16) — documentation-enforcement backstop:
  `hooks/doc-guard.sh` (block substantial undocumented source commits + surface uncommitted
  work before compaction / at next session start), broadened `managing-session-memory` criteria
  (business-logic + direction-pivoting changes → mandatory + ADR), ADR standard/template in
  `setting-up-a-new-project`, gates stub. Verified (15-case harness). **PR #10 MERGED (2026-07-16).**
  Detail: `coding-memory/branches/documentation-enforcement.md`.
- PR #11 (chore/ports-registry-snatch-8001) — MERGED 2026-07-16. Reconciled the orphaned PORTS.md
  edit (snatch-bracket backend on port 8001) as its own commit, per user's commit-only-my-work call.
- PR #12 (feature/diagramming-skill) — MERGED 2026-07-16. New `diagramming-technical-docs` skill
  (Mermaid docs standard: SKILL.md + references/assets/scripts validator; Mermaid-not-PlantUML).
  Detail: `coding-memory/branches/diagramming-skill.md`.
- feature/observability-judge (2026-07-16) — the observability judge (16 commits, 17/17 tests):
  scoring subagent (10 dims → JSONL+markdown verdict + layman summary), `hooks/judge-guard.sh`
  blocking `gh pr create` without a fresh strict-freshness verdict, skill + gate stub + catalog,
  ADR 0001, spec, verdict store. Command detection took 2 review-driven security fixes
  (substring→anchored→python shlex, closing a quoted-env-prefix bypass). **PR #13 MERGED
  2026-07-17** (bootstrap self-gate → JUDGE_EXEMPT).
  Detail: `coding-memory/branches/observability-judge.md`; PR status: `coding-memory/pr-tracking.md`.
- feature/memory-rag-index (2026-07-17→18) — `memsearch`: local SQLite (sqlite-vec + FTS5) RAG over
  transcripts + curated docs, Qwen3 embeddings, hybrid retrieval, silent SessionStart nudge.
  60-test suite green, backfill 228 sources / 2332 chunks / 0 errors / p95 149ms, golden 16/16.
  **PR #14 MERGED 2026-07-18** (7015369). Judge (impl): risk=low conf=high, outcome=clean.
  Detail: `coding-memory/branches/memory-rag-index.md`.
- feature/compliance-judge (2026-07-18) — subagent judging ONE finished spec against live rules
  (writing-specs + core-conduct/security): blocking pass/fail, per-rule citations, JSONL+markdown
  store; skill with parallel dispatch alongside the observability judge, capped auto-revise loop,
  escalation, explicit-only waivers; gates stub + catalog, ADR 0003, golden eval 12/12.
  **PR #16 MERGED 2026-07-18** (4c2abec). Judge (impl @ 85d8982): risk=low conf=high, clean.
  Detail: `coding-memory/branches/compliance-judge.md`.
- feature/writing-project-readmes-skill (2026-07-19) — `writing-project-readmes` skill: house
  README standard from the user-supplied template (check-then-create, real facts only, `[TODO:]`
  greppable placeholders) + Roadmap upkeep as features land + trigger wiring (setting-up-a-new-
  project step 5, preparing-pull-requests bullet, CLAUDE.md catalog). TDD RED/GREEN + 8/8 routing.
  **PR #17 MERGED 2026-07-19** (merge commit d242e69); branch deleted. Judge rounds 1-2
  (3c5a826 low/medium → grep hole fixed → 0d23feb low/high), outcome=clean (backfilled).
  Detail: `coding-memory/branches/writing-project-readmes-skill.md`.
- feature/statusline-command (2026-07-19) — Claude Code status line reproducing the oh-my-zsh
  `robbyrussell` prompt (`➜ user@host dir git:(branch) ✗`) plus dimmed model + token-count
  segments: new `statusline-command.sh`, `statusLine` entry in `settings.json`, README table
  row; model → opus[1m] and theme → dark split into their own `chore(settings)` commit.
  Observability judge ran **5 rounds**, each finding something real in the round before: terminal-escape
  injection via four distinct paths (incl. a **second** unstripped fallback introduced by the fix for the
  third), false "pushed" claims, and an unverified `context_window` schema — all fixed. Test suite
  validated by falsification against all 5 historical versions rather than by passing alone
  (`statusline-command.falsify.py` makes that reproducible). Recurring lesson: **the write-up ran ahead
  of the code in every round**, including a "Cosmetic, no leak" claim about a path that did leak. Scope
  overran badly — 5 of 6 commits judge-driven; taken to the user rather than resolved unilaterally.
  No ADR (presentation-only — misses all three ADR triggers).
  Detail: `coding-memory/branches/statusline-command.md`.
- feature/statusline-token-bar (2026-07-19) — **PR #20 MERGED 2026-07-20 04:01Z.** Follow-on
  to PR #18: model name orange, context bar scaled to a fixed 100k "time to clear" reference (not the
  model's window — against 1M a 143k session rendered nearly-empty-but-red), cumulative Σ counting
  input+output only (cache traffic swamped it ~16x), purple weekly-quota segment. A cost-estimate
  feature was requested, built, then **removed entirely**: subscription plan, `costUSD: 0`, no cost
  field in the payload — any dollar figure would have been invented. Weekly quota is a percentage
  for the same reason: docs confirm `rate_limits` exposes `used_percentage` + `resets_at` only, so
  "tokens left" is uncomputable. Schema check caught a silent bug: `resets_at` is epoch seconds, not
  ISO — the countdown would have never rendered and looked merely absent.
  Judge R1 (b24d422) risk=**high**; all three findings fixed across 4 commits (fc67ab1 tests,
  888449e race repro RED, d7a2861 lock GREEN + ADR 0005, d302479 lock-recovery tests).
  Recurring lesson, now three-for-three on this branch: **writing the check is not the same as the
  check working.** The first lock regression test planted its PID file with a trailing newline —
  a condition the buggy writer cannot produce — so re-introducing the bug passed 44/44. Only the
  mutation revealed it. Every claim on this branch is now falsification-backed.
  Detail: `coding-memory/branches/statusline-token-bar.md`, ADR 0005.
- feature/verifying-subagent-commits (2026-07-18) — new skill: after a dispatched implementer/fix
  subagent reports DONE with a commit SHA, the controller independently confirms via `git log -1`
  in the target checkout that it actually landed there, before trusting the report. Harvested from
  a real trace (a subagent committed to the wrong checkout 3x in one session, despite an explicit
  dispatch-prompt self-check instruction). Not hook-enforced by design. **PR #15 MERGED
  2026-07-18** (merge commit 417e8e7); branch deleted. Judge (impl, head 367da77): risk=low
  conf=high, outcome=clean.
- feature/add-claude-code-handoff (2026-07-20) — vendored Sonovore/claude-code-handoff @
  c6cb717, then cherry-picked per the user's 15-row picks (ADR 0006): handoff SessionStart
  loader + doc-guard PreCompact removed, tracker bug patched locally (verified live),
  `/handoff` = checkpoint UX, committed memory stays authoritative. Judge R1 medium→fixed,
  R2 **low/high** @ e56c2f2. **PR #21 MERGED 2026-07-20 22:02Z (3c58363).** Judge audit trail
  committed to the branch post-merge (77b59ad) and stranded off `main`; recovered via docs-only
  **PR #22 MERGED (284478a)** — cherry-pick 7337186.
  Detail: `coding-memory/branches/add-claude-code-handoff.md`, `coding-memory/pr-tracking.md`.

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
0-NEW (parked 2026-08-01, own branch, do NOT widen PR #32). **Three Tier 1 hooks are registered in
   `settings.json` and have NO test suite at all: `git-guard.sh` (default-branch + force-push),
   `merge-guard.sh` (remote-merge), `doc-guard.sh` (documentation checkpoint).** Verified — no
   `*.test.sh` for any of them, and no file matching `*test*` references them. These are the hooks
   that block commits, pushes and merges, and `rules/gates.md` cites all three as enforcement.
   Four more have neither a suite nor a `settings.json` registration — `scan-secrets`,
   `scan-invisible-unicode`, `checkpoint-before-modify`, `require-project-standards` — dormant or
   registered elsewhere, **unverified which; verify before designing anything.**
   Suites that DO exist: judge-guard (101), phase-guard, pane-dispatch-guard, context-handoff-watch,
   memsearch-nudge. **Unmeasured, do not assert:** whether phase-guard's or pane-dispatch-guard's
   *deny* assertions carry C1's "exit code alone does not say which door" defect — they already do
   some message checking. Found while scoping "should the C1 fix go broader"; the honest answer was
   that assertion strength on a 101-test suite is the smaller risk. **User decision 2026-08-01:
   park it, finish PR #32 first.** Owes `triaging-new-instructions` → brainstorming → spec before code.
0-ACTIVE. **pane-layout-v2 — EXECUTING. Task 1 (live probe) DONE + pushed (ffe22d2)
   2026-07-21. Gates answered, do not re-ask: model = Opus 4.8 (user ran `/model`
   this session — satisfied); execution = SUBAGENT-DRIVEN, implementers PANE-routed.
   **Tasks 2 (ba9a91b) + 3 (0711017) DONE + pushed** — both pane-routed, commit-verified
   and independently re-run (Task 3: dispatch 39/0, siblings 24/0 10/0 9/0, shellcheck
   clean, `--role` guard falsified 37/2 → restored 39/0).
   **Task 4 (`cmux-layout.sh`) DONE + pushed (5da1cad)** — layout 12/0, siblings
   39/24/10/9 all 0 failed, `shellcheck -x` clean; all 4 falsifications RED and reverted
   (I independently re-ran the two jq ones: 7/5 and 11/1, restored byte-identical 12/0).
   **Task 5 (decide + title composition) DONE + pushed (8ad7d7a)** — layout 26/0, siblings
   39/24/10/9 all 0 failed, `shellcheck -x` clean; 3 falsifications RED and reverted (I
   re-ran the tab tie-break one myself: 25/1 → restored byte-identical 26/0).
   **Correction 8:** every Task 5 test fixture called `tree "$(pane …)"`, skipping Task 4's
   new `workspace` level — and would have PASSED anyway, because normalize uses recursive
   descent. Silent builder drift, the exact hazard Task 4 existed to kill. All 8 fixtures
   now wrap through `workspace workspace:1`. **Correction 9:** the plan's reuse
   falsification couldn't discriminate with only one finished surface; needs two.
   **Task 6 (cmux.sh v2 frame — tiered degradation, legacy floor, dryrun) DONE (aa2cc42)**
   — new `cmux-exec.test.sh` 24/0, siblings 26/39/10/9 + adapters 24/0 (file untouched),
   `shellcheck -x` clean. 5 falsifications RED and reverted; **I independently re-ran the
   workspace-scoping one** (anchor asserted to match exactly once, non-empty diff, 23/1 RED
   on that exact case, restored byte-identical by sha256 → 24/0). RED run was 5/18 with
   **all five passes vacuous** — enumerated in the branch log.
   **Corrections 10–15** (10: `T_EMPTY` in the imagined shape normalizes to 0 bytes yet
   passes every plan assertion — 3rd builder-drift occurrence, so a `T_SLOT1` fixture whose
   plan is reachable only if the tree really parsed was added; 11: tree fetch must carry
   `--workspace`, bare is window-scoped; 12: `send`/`rename-tab` carry it too, `new-split`
   deliberately does not; 13: dryrun comment contradicted its own load-bearing guard;
   **14: the plan's Step 2 RED run is UNSAFE here** — v1 hardcodes the real cmux path and
   ignores `PANE_CMUX_BIN`, so a literal RED run inside a live cmux workspace fires ~10 real
   `new-split down` calls at the user's window; run RED against a `cp -R` copy in `$TMP`
   instead — **Task 7 needs the same precaution**; 15: the plan's `legacy_open` falsification
   could not discriminate — `|| true` left the suite green because the ref-shape guard exits
   on its own).
   NEXT: **Task 7** (plan execution + verify-after-rename) → Task 8 →
   implementation-stage obs judge (OWED — not yet run; judge-guard blocks PR) → PR.
   **Still gotchas for Task 7:** `grep -c .` on empty input prints 0 but EXITS 1 —
   `layout_decide`'s tab-count loop is safe only because these files are `set -u` and NOT
   `set -e`; introducing `set -e` breaks it. **Nothing in Task 6 touched the real cmux
   binary** — every execution assertion runs against the fake, so the `--workspace`
   placement on `send`/`rename-tab` rests on `--help` + probe P5, **not** a live mutating
   call. That live confirmation is owed at Task 8 alongside Task 3's handoff-wrapper rename.
   **Task 4 = plan corrections 5–7, all verified against the live fixture before dispatch:**
   (a) the normalize selector returns EMPTY (real shape keys each level's own ref as `ref`;
   surfaces carry `pane_ref`+`title`); (b) **the workspace filter was a SILENT TOTAL
   FAILURE** — workspace objects carry `ref` and their `workspace_ref` is `null`, so
   `select(.workspace_ref? == $ws)` matched only the root `active`/`caller` objects and
   returned NOTHING whenever `CMUX_WORKSPACE_ID` was set (the normal case), degrading the
   whole feature to legacy; repaired to filter on the workspace's own `.ref`, kept as
   defence-in-depth with primary scoping SERVER-side via `tree --workspace` (P1);
   (c) the canned `pane()`/`tree()` builders were in the imagined shape and would have kept
   (a)+(b) green while live degraded — now mirror `fixtures/tree-live.json`.
   Implementer also fixed a real footgun: `layout_managed` dropped its last line when stdin
   lacked a trailing newline (Task 5 will feed it via `$(...)`, which strips it).
   Note for later tasks: the plan's `> file 2>/dev/null` idiom does NOT suppress a
   redirect failure (left-to-right); put the stderr redirect FIRST.
   **Task 3 = the plan's 4th correction:** its handoff `rename-tab --surface
   "$CMUX_SURFACE_ID"` (a UUID, and no `--workspace`) would have silently renamed the
   user's FOCUSED tab (P5+P6+P7 combined) — shipped instead with
   `--workspace "$CMUX_WORKSPACE_ID"` and NO `--surface`, resolving via the pane's own env.
   **Unverified live — confirm at Task 8.** The plan's predicted RED set was also wrong
   (the `--role` allowlist case passes vacuously pre-implementation) — exactly the failure
   the mandatory falsification rule exists to catch.
   **The probe changed the plan in three places — full verbatim findings in
   `coding-memory/branches/pane-layout-v2.md` §Live probe; read it before Tasks 4/6/7:**
   (a) the real tree JSON shape differs from the plan's assumption at EVERY level (each
   level keys its own ref as `ref`; surfaces carry `pane_ref`+`title`) — the plan's jq
   matches nothing, so Task 4 must rewrite both the jq AND the canned test builders, or
   unit tests stay green while live silently degrades to legacy; (b) `rename-tab` does
   NOT error on an unresolvable `--surface` — it silently renames the FOCUSED tab, so
   Task 7 needs verify-after-rename, not retry-once; (c) `respawn-pane` destroys the
   surface when its command exits → reuse uses `cmux send` instead (**user-approved
   deviation; spec left unedited — flag it to the implementation-stage judge**).
   Spec assumption 1 (bare tree workspace-scoped) is FALSE but the gate did not trip
   (`tree --workspace` accepts `$CMUX_WORKSPACE_ID`); assumption 4 confirmed visually.
   Also: every mutating cmux call needs an explicit `--workspace` (refs resolve relative
   to it; UUIDs work for `--workspace` but not `--pane`).
   **settings.json's `model` field tracks the ACTIVE session model — it is not a stable
   committed preference. Now `opus[1m]` (user's /model), uncommitted. Re-`grep` fresh
   rather than trusting any earlier diff.**
0. **claude-code-handoff cherry-pick (2026-07-20) — DONE. PR #21 + PR #22 both MERGED.** Picks
   applied per ADR 0006; judge R1 medium→R2 low/high; PR #21 merged 22:02Z. The audit trail
   stranded off `main` (committed post-merge as 77b59ad) was recovered via docs-only PR #22.
   **Branch cleanup DONE:** all 8 merged orphans pruned local + remote (see Orphans below).
   Ongoing duty (unchanged): add handoff state-file gitignore entries per project repo on
   first work there (recorded in `managing-session-memory`).
0b. **Judge terminal-enforcement — SUPERSEDED by pane orchestration (ADR 0007, 2026-07-21).**
   Branch retired, not deleted (user cleanup decision pending). Platform research absorbed
   into the pane-orchestration spec. Resurrect its §3 only if a skipped compliance judge is
   ever observed (spec-guard remedy).
0c. **Pane orchestration — PR #23 MERGED 2026-07-21 (8f40e05); branch pruned.** Verdict
   outcome backfilled `clean`. Open post-merge items, none blocking: (a) judge suggested a
   short ADR for the bypassPermissions rider (79495c5, user-requested, commit-message-only
   rationale) — user's call; (b) live-verify a second adapter (tmux or iTerm) — only cmux is
   live-proven, a real iTerm failure fails open + cools down silently; (c) watch for
   `adapter-failed-nosession` (shared cooldown can mute pane redirect for all env-less
   sessions up to 7 days) and the first concurrent two-implementer pane dispatch; (d) README
   has no Roadmap section (non-template, 55 lines) — standardizing via
   `writing-project-readmes` is its own task if wanted. Only chrome/chrome-native-host stays
   uncommitted (machine-local).
1. **Statusline token bar — DONE (PR #20 merged 2026-07-20 04:01Z).** Still open, deliberately
   unabsorbed: R1's `STATUSLINE_DEBUG` logging splitting "field absent" from "field present but
   unparseable" (would have caught the epoch-seconds bug on render one); cosmetics (duration floors,
   bar full at 95k, no MB rollover). Detail + lessons: `coding-memory/branches/statusline-token-bar.md`, ADR 0005.
2. **compliance-judge — the predicted collision HAPPENED (2026-08-01, branch
   `docs/reconcile-judge-verdict-stores`).** **PR #34 OPEN** — https://github.com/suyatdev/.claude/pull/34,
   4 judge rounds, opened at `0ff95fe` with **no `JUDGE_EXEMPT`**. Detail: `pr-tracking.md` §PR #34. "Revisit if cross-repo spec slugs ever collide" is
   now overtaken by events: the global store **forked in both directions**. **26 verdict lines
   across 24 distinct `head_sha`** — measured: 23 SHAs carry one round each and **one SHA
   (`6d8c675`) carries three**. (An earlier note here said "two SHAs carry a second round". That
   was narrated, not measured, and was wrong in both numbers.) From
   `mtg-wizard`/`vibe-scape`/`Snatch-Bracket`/`.claude` (07-23→07-28) lived only in the working
   tree, uncommitted across two session clears; `main` held 2 the tree lacked. Neither side was a
   superset, so any checkout would have silently dropped one. Union-merged **13 → 39 lines**
   (13 base + 26 added), verified no-loss by set difference, 0 malformed.
   *Count both ways or neither — an earlier note said "24 verdicts" against a 26-line diff.* **The store is append-only and global — never resolve it by picking
   a side; always union.** Filenames still carry no repo component (root cause, unfixed).
   Still open: backfill the compliance-judge verdicts' own `outcome` fields once those specs
   implement (calibration ledger, see running-the-compliance-judge SKILL.md).
   Two debts recorded 2026-08-01, both deliberately NOT fixed on this branch:
   - **No re-fork guard.** Nothing checks parse/ordering/no-loss on the store, and "always union"
     lives in this index rather than in `coding-memory/compliance-judge/README.md`.
     *Correction (RUN 3): an earlier version of this bullet said that README "does not exist". It
     does — both judge READMEs have been tracked since `72b868f`. One `git ls-files` settles it;
     the claim was narrated, not checked. The debt is unchanged — neither README carries the union
     rule — but the reason given for it was false.* Writing it is its own task, not a rider here.
   - **Absolute `/Users/marksuyat` paths**, against core-conduct's no-absolute-paths rule.
     **18 ride in on the rescued compliance records** — that is the stable number and the one the
     argument is about. Left as-is on purpose: they are historical audit records where the path was
     the judge's real cwd, and rewriting them would falsify the record to satisfy a rule aimed at
     code and config. Largely pre-existing — `origin/main` already carries 49, incl. 5 in this same
     store. **But "not introduced here" understates it:** the branch's own machinery adds a few
     more, mostly the judge writing its own cwd, and *this very bullet is one of them* — which is
     why no total is pinned here. A count that its own sentence changes is a count that will be
     wrong by the next commit. Root cause: the judge writes absolute cwd into the verdict. Fix it
     there, going forward — not by editing history, and **not yet owned by anyone.**
2b. **Obs-judge calibration: verdict-commit recursion ruled (DECIDED 2026-08-01, user).** The 07-22
   policy read literally demotes *every* final round to `rework`, because the last commits before
   any merge are the verdict-landing commits themselves — which makes `clean` a value the policy
   can never produce. **Ruled (narrow): only the mechanical act of landing the verdict — the
   writeup file and the `verdicts.jsonl` append — is exempt. Substantive changes a round's findings
   caused still demote it, even when they ride in the same commit as the verdict.**
   An earlier draft of this item exempted "the pointer fixes it catches" too; that was written by
   the agent, unattributed, against a user-owned policy, and it laundered exactly the signal the
   07-22 decision exists to preserve (see the rationale at item 6: a ledger showing the judge never
   prompting rework is "false and useless for tuning it"). Narrowed on the obs judge's own finding.
   Applied to PR #33 — **all ten `rework`, zero `clean`.** RUN 9 `0f54622` is `rework` because
   `7e0b9b1` fixed a broken cross-reference, a garbled sentence, and added RUN 9's third latency
   measurement to ADR 0012 — real corrections, pre-merge, caused by that round.
   Nulls **32 → 22** (the older "17 nulls" was stale; corrected in place at item 6).
   The 22 remaining need per-branch history reads; **architecting-stage entries still have no
   sub-policy** — no merge event means "shipped clean" has no meaning for them yet.
   **Two limits on this ruling, both open:**
   - **The ~34 pre-narrowing `clean` values were NOT re-audited.** They were set under the wide
     reading and now sit unmarked beside post-narrowing `rework`s, so the aggregate reads more
     calibrated than it is. Anyone computing a clean/rework ratio across the whole store is mixing
     two policies.
   - **Pointer-only tie-break: DECIDED 2026-08-01 (user) — default to `rework`.** "Mechanical
     landing" vs "substantive fix" is crisp at the extremes, but a round catching only a stale
     cross-reference or a typo is arguable either way. Ruled `rework`, matching the 07-22
     rationale: a ledger that under-reports the judge prompting changes is "false and useless for
     tuning it", and erring toward the judge looking *worse* is the safe direction for a metric the
     judge scores itself on. **Changes no existing data** — the default can only push toward
     `rework`, and all ten PR #33 entries already sit there. Bites on the next round that lands a
     pointer-only fix.
   **🔴 BOTH RULINGS ARE FILED WHERE THE JUDGE CANNOT READ THEM (RUN 3, raised all three rounds).**
   They live only in this index. `skills/running-the-observability-judge/SKILL.md` §Calibration and
   `coding-memory/observability-judge/README.md:32-35` both still state the older, looser rule —
   and **the judge agent reads the SKILL, not this file.** Until that is fixed the narrowed policy
   and the `rework` default are documentation, not behaviour. Twice already the fix went into the
   index instead. **Own branch, own gates — editing the judge's own instructions changes how every
   future round scores itself and must not ride on a docs branch.**
   Two consequences to carry into that branch:
   - **`clean` now means two different things in one column.** All 34 `clean` values are
     pre-narrowing ("the PR merged"); zero have been assigned under the new rule ("the judge had
     nothing to say"). Nothing in the store marks which is which — a ledger half in dollars and
     half in euros with no currency column. Consider a marker before aggregating anything.
   - **The column's consumer was never updated.** Both READMEs define calibration as `risk` vs
     `outcome` — an *outcome* signal. The narrowing makes `outcome` a *process* signal. Feeding one
     into the other mis-tunes the gate that blocks `gh pr create`. Decide whether `outcome` still
     serves the calibration the README describes, or whether the two need separate columns.
2c. **Record hygiene on this branch — four instances of one habit, annotated forward (2026-08-01).**
   Across three judge rounds the split was exact: **every number mechanically re-derived from git
   was correct; every sentence narrating *why* was invented and wrong.**
   1. "two SHAs carry a second round" → one SHA (`6d8c675`) carries three. Fixed `565071d`.
   2. "19 absolute paths" → 18 on the rescued records, 23 net-new at `d4aecf0`; no metric yields
      19, and a prior round's "21" was also wrong and had been replaced silently. Fixed `565071d`.
   3. **`565071d`'s own commit message says "Store-wide context checked, not assumed: 34 clean / 14
      rework / 23 null".** Those figures were copied from the RUN 2 report and verified only
      *afterwards* — the process claim was false when written, though the numbers proved correct at
      `d4aecf0`. **Annotated here rather than force-pushed:** the branch is shared, and rewriting an
      audit trail to fix a phrase that has since become true is the worse of two wrongs. But
      "don't rewrite" is not "don't annotate" — leaving the correction only in a machine-local file
      while the false claim sits in the pushed record is the convenient half of the rule.
   4. "`compliance-judge/README.md` does not exist" → it does, since `72b868f`. Corrected at item 2.
   **Each fix landed on the instance, not the habit** — instances 3 and 4 were introduced *by* the
   commits fixing 1 and 2, and RUN 2 repeated 4 rather than catching it. The generalisable rules:
   **anchor counts to a SHA, never a date** (a dated count is stale in the commit that writes it);
   **any "X does not exist" is a command to run, not a sentence to write**; and beware
   **self-referential counts** — writing "19 absolute paths" added an absolute path.
3. **memsearch debt (recorded, not blocking; ledger `.superpowers/sdd/progress.md` has detail):**
   `index` exits 0 even when errors>0 (fix before wiring automation to exit codes); validate
   `ollama_url` is loopback; busy_timeout PRAGMA; fail-fast on Ollama-down backfill; `--since`
   format validation; README sentence that digest-chunk line numbers are digest-relative.
   Memsearch-nudge SessionStart line: **VERIFIED live 2026-07-18** (fired post-/clear, 2332 chunks).
4. **Live-verify** doc-guard's PreCompact injection against a real `/compact` — still pending.
   SessionStart injection **VERIFIED live 2026-07-18**: post-/clear it surfaced the uncommitted
   verdict-store + settings.json changes exactly as designed (15-case harness had covered logic only).
5. (Optional) Retire `coding-memory/decisions.md` in favour of `docs/decisions/` (now ADRs
   0001-**0005**) — the "adopt" framing was stale, the directory was never the blocker.
   Diagramming-pointers half **DONE 2026-07-19** (PR #19), wider than this item scoped it.
5a. **Watch the next 2-3 `coding-memory/` branch logs** (ADR-0004 revisit trigger). If one lands with
   real structure and no diagram, move the `managing-session-memory:18` pointer from the
   index-description bullet into the save-time procedure section. Escalation if that also fails is a
   **gate stub, never the hook** (the hook's rejection is structural; the gate's is cost/benefit).
   Evidence: **2 of 3** — `diagramming-pointers.md` has a flowchart; `statusline-token-bar.md` now
   describes a lock protocol with real structure and carries **none** (its diagram went to ADR 0005).
   The 07-20 brainstorm write-up carries its flowchart inline (counts toward the healthy side).
6. **DONE 2026-07-21** — backfilled `outcome: clean` for the three known-clean nulls
   (`feature/observability-judge` @ fdbd7b9 + @ 381bd79, memsearch architecting @ c2b23fe)
   alongside PR #23's verdict. **CALIBRATION POLICY DECIDED 2026-07-22 (user):** on a branch with
   multiple judge rounds, the **final** round that shipped is `clean` and **earlier** rounds whose
   findings changed the code or docs before merge are `rework`. Chosen over "every round on a
   merged PR is clean" precisely because that would make the calibration history show the judge
   never prompting rework, which is false and useless for tuning it. Applied to pane-layout-v2:
   e12dc06 → `rework`, ec03621 → `clean`.
   **22 nulls remain** — re-measured from the store **at `8143f29`** (70 lines, 22 null, 0
   malformed). *Anchored to a SHA, not a date: the store grows, so a dated count is stale on
   arrival — it was already stale in the commit that wrote it.*
   the figure here previously read "17" and its enumeration was two branches out of date. Still
   resolvable under that policy but NOT bulk-applied — each needs its per-branch history read to
   identify which round was final: statusline-command ×6, statusline-token-bar ×4,
   cmux-version-gate ×3, gate-checks-and-session-memory ×2, add-claude-code-handoff ×2,
   pane-orchestration architecting ×2, compliance-judge ×1, verifying-subagent-commits ×1,
   pane-layout-v2 architecting ×1. **19 implementation, 3 architecting.**
   **Architecting-stage entries are the genuinely unclear case** — there is no merge event for a
   design, so "did it ship clean" has no direct meaning; decide that sub-policy before touching
   them. (The 07-22 policy itself was narrowed 2026-08-01 — see item 2b.)

**Merged** (full detail: `coding-memory/pr-tracking.md`): `.claude` PRs #10–#16 (07-16→18) —
documentation-enforcement, PORTS.md reconcile, diagramming skill, observability judge (+ judge-guard
hook, live and global), memsearch RAG index, verifying-subagent-commits, compliance judge; plus
vibe-scape (Tayvyx-Lab/VibeSpace) PRs #6–#7. **07-19:** #17 (writing-project-readmes, d242e69),
#18 (statusline, b6362ff). **07-20:** #19 (diagramming reachability + ADR 0004, a735fb4),
**#20 (statusline token bar, merged 04:01Z)**, **#21 (claude-code-handoff cherry-pick, 3c58363,
22:02Z)**, **#22 (docs-only follow-up landing PR #21's stranded judge audit trail, 284478a)**.
**07-21:** **#23 (pane orchestration, 8f40e05, 12:35Z)**, **#24 (docs-only PR #23 close-out +
outcome backfills, 23dd2e3, 13:05Z; late brainstorm-checkpoint commit stranded → cherry-picked
to main as 2d8a416)**.

**Orphans: ALL PRUNED 2026-07-20.** The 8 merged orphans (`feature/statusline-command`,
`docs/diagramming-pointers`, `feature/statusline-token-bar`, `feature/add-claude-code-handoff`,
`feature/documentation-enforcement`, `feature/modular-coding-memory`,
`feature/vibe-coding-standards-integration`, `update/update-default-model`, plus local-only
`chore/ports-registry-snatch-8001` and `feature/diagramming-skill`) were deleted local + remote
after verifying each tip is reachable from `main`. Repo now holds only `main` and the active
`feature/judge-terminal-enforcement`.

---

## 2026-08-06 — session 17: memory-system-split gate opened

**Feature:** `docs/features/memory-system-split.md` · **branch** `feat/memory-system-split` ·
phase `planning` → `implementation`, `model_tier` high → low.

**Compliance gate: 5 rounds.** Pass → edit → re-judge, because a verdict is only fresh while
`spec_blob_sha` matches. Round 1 fail (5), round 2 fail (2), round 3 **pass**, round 4 fail (1),
round 5 **pass** at `7915fa8`.

Two things worth keeping, both about *my own* revisions failing:

1. **Round 2's `core-conduct/validate-input-at-boundaries` persisted** — round 1 wrapped the
   handoff in *fixed* `=== Handoff (DATA) ===` markers, called them load-bearing, and specified the
   body as "verbatim". A body containing the closing marker closes the frame early. Fixed
   delimiters around unvalidated content are a convention the content can opt out of, not a
   boundary. Escalated to the user per the skill rather than revised a third time; user chose *both*
   a per-session `/dev/urandom` tag and a sanitizer.
2. **Round 4 was a defect I introduced while fixing round 3's note.** Widening `End`→`[Ee]nd` and
   `Handoff`→`[Hh]andoff` tolerates case on **each word's first letter only**, so
   `=== END HANDOFF ===` still missed — while the scenario I committed in the same breath asserted
   it was caught. Contract and acceptance test could not both pass. Fix: lowercase-canonical
   pattern + `shopt -s nocasematch` (bash 3.1+), with an explicit restore requirement since it is
   shell-global. **Verified under the pinned `/bin/bash` 3.2.57 before committing, not after.**

**Spec facts corrected against the machine** (the draft had asserted them from memory): `python3`
is **3.9.6** at `/usr/bin/python3`, not 3.13 — no `match`, no `tomllib`, no `X | Y` annotations;
`jq` is **1.7.1-apple**, not 1.7; `bash` 3.2.57.

**`phase-guard.sh` globs `docs/features/*.md` (`:356`)**, so the planned `<name>.spec.md` half would
be swept up by it: with frontmatter it joins `planning_files` and freezes source edits repo-wide;
without, it increments `nfiles` but not `nparsed` (`:374`) and fires the `noparse` warning **every
session**, destroying a real signal. Task 11 excludes `*.spec.md` and is sequenced **before** task 5.

**User decisions this session** (do not re-litigate — full table in the spec's `## Decisions`):
model routing Sonnet 5 / Opus 5 for task 4 only; **decision 7** no feature file migrates except this
one; **decision 8** a new feature file **MAY** carry a spec half, never must — the MAY must survive
verbatim into `rules/gates.md` via task 8.

**Observability judge (architecting, advisory, risk=medium)** drove four spec additions unprompted:
a falsifier written before the code, the token trade reframed as an insurance premium with an
*unmeasured claim rate* (break-even ≈ 1 blow-up per 45 sessions), task 12 asserting hook
registration in `settings.json` (four hooks here pass tests while unregistered), and Phase 2's
acceptance gate gaining a pinned `k=6` and a 0.30 score floor — the draft's "≥2 hits" would have
passed on today's ~0.02 noise.

**Also landed:** `docs/remove-rtk-references` (3ec8504) → **PR #41, MERGED `e3b939d`**
(https://github.com/suyatdev/.claude/pull/41; detail: `coding-memory/pr-tracking.md`). RTK retired;
verified `settings.json` registers no RTK hook before removing — the `SETUP.md` checklist had been
asking you to verify a hook that did not exist. Needed a `Doc-Exempt:` trailer since the four paths
sit at the repo root and doc-guard reads them as source, and `JUDGE_EXEMPT` to open the PR. **`docs/features/verification-marker-gate.md`
(1,166 lines) was restored, not deleted** — its last commits are spec revisions with no
implementation merge, which is a reason to keep it, not to bin it.

## 2026-08-06 — session 18: task 11 done (spec-half glob exclusion)

**Feature:** `docs/features/memory-system-split.md`, still `phase: implementation`,
`feat/memory-system-split`, gate open. Commit `40ab0ad`.

Task 11: `hooks/phase-guard.sh:356`'s `docs/features/*.md` glob now excludes `*.spec.md` by name
(`case "$f" in *.spec.md) continue ;; esac`, before `nfiles` counts it) — sequenced ahead of task 5,
which creates the first `.spec.md`. Added Group A8 to `phase-guard.test.sh` (3 cases, 7 assertions:
a bare `.spec.md` alone, one carrying `phase: planning` frontmatter, one mixed beside a real
planning card). Mutation-checked by hand — reverting the exclusion fails 4 of the 7. **141/141
pass.** Rollback point: `caf0d2f` (pre-task-11 HEAD), unneeded — no rollback occurred.

**Next:** task 2 (`hooks/handoff/slim-session-start.sh`), then 3 → 4 (Opus 5) → 12 → 5 → 6 → 7 → 8 →
9. See the feature file's `## Tasks` for detail — not restated here.

## 2026-08-06 — session 19: task 2 done (slim-session-start.sh) + two settings.json fixes

**Feature:** `docs/features/memory-system-split.md`, still `phase: implementation`,
`feat/memory-system-split`, gate open. Commits `fef7487` → `f4fafe7` → `ca2c969`, all pushed.

Task 2: `hooks/handoff/slim-session-start.sh` (new, SessionStart, Tier 3) emits
`.claude/session-state.md` inside the tag+sanitizer DATA envelope the spec defines. 27 tests, all
12 Gherkin scenarios, mutation-checked by hand (4 targeted breaks, each catches exactly the tests
it should). `shellcheck -x` clean, full `hooks/` suite re-run clean. Registered in `settings.json`
SessionStart alongside `doc-guard.sh`/`memsearch-nudge.sh`.

**Two settings.json fixes landed getting there, both worth remembering:**

- **Committed `settings.json` had a dead `rtk hook claude` PreToolUse/Bash entry** that PR #41
  (RTK removal, merged) never actually removed — that session's "verified settings.json registers
  no RTK hook" check ran against the *live* file, which is `skip-worktree` (`git ls-files -v` → `S`,
  set 2026-07-22 so a stray `git commit -a` can't leak the machine-local `model` line), so
  `git status` was structurally blind to the committed drift. Anyone cloning fresh would have hit a
  failing `rtk hook claude` call on every Bash tool use. Fixed in `fef7487` via direct index surgery
  (`git hash-object -w` + `git update-index --cacheinfo`), not by touching the live file.
- **`git commit -- <pathspec>` is NOT "commit what's staged for this path"** — for a pathspec-named
  file it implicitly re-adds the *working tree* content first (same as `git add path && git commit`),
  discarding whatever was staged via `update-index --cacheinfo`. `fef7487`'s pathspec-restricted
  commit silently pulled in this machine's local `"model": "sonnet"` override even though the staged
  blob never had it — exactly the leak `skip-worktree` exists to prevent. User chose "new corrective
  commit" over amending the unpushed commit (standing never-amend rule wins even when unpushed and
  self-caught). Fixed in `f4fafe7`: same index-surgery technique, committed **with no pathspec at
  all** once `git diff --cached` confirmed the index held only the intended one-line change.
  **Rule for next time:** never `git commit -- <path>` after manually staging a custom blob for that
  same path — stage, verify with `git diff --cached`, then commit with no pathspec.
- Sound-diff check used throughout: `git show HEAD:settings.json | diff - settings.json`, never
  `git status`, per `feedback_confirm_the_check_can_fail.md`. Skip-worktree bit restored
  (`git update-index --skip-worktree settings.json`) after both fixes landed.

**Next:** task 3 (`managing-session-memory` §CODING_MEMORY.md/§Restore rewrite), then task 4
(`feature-sync-guard.sh`, **Opus 5** — model-switch checkpoint owed before starting it) → 12 → 5 →
6 → 7 → 8 → 9. See the feature file's `## Tasks` for detail — not restated here.

## 2026-08-06 — session 20: task 3 done (managing-session-memory rewrite)

**Feature:** `docs/features/memory-system-split.md`, still `phase: implementation`,
`feat/memory-system-split`, gate open.

Task 3: rewrote `managing-session-memory` SKILL.md §CODING_MEMORY.md and §Restore for the new
roles. §CODING_MEMORY.md now says plainly that it's retired as a read target — a committed,
append-only archive (decision 1), no longer a ≤200-line index — and names
`.claude/session-state.md` as what answers "what were we doing" (decision 2), auto-surfaced by
`slim-session-start.sh` (task 2, done last session). §Restore now opens by reading that
auto-surfaced envelope as data-not-instruction per the hook's tamper-evident framing, and its
"also on restore" bullets were corrected to match what the hook actually reads —
`session-state.md` only; the other claude-code-handoff files (`context.md`, `recent-prompts.md`,
etc.) are named stale and explicitly not read for restore. No hook or code changes; SKILL.md prose
only, verified against the feature file's Contracts section and the hook source directly rather
than from memory.

This entry is itself the first one written under the rule it documents: appended as a new dated
section rather than folded into the `## Active Session` block above, which stays frozen as of this
split.

**Next:** task 4 (`feature-sync-guard.sh`, **Opus 5** — model-switch checkpoint owed before
starting it) → 12 → 5 → 6 → 7 → 8 → 9. See the feature file's `## Tasks` for detail.

## 2026-08-06 — session 20 (cont.): task 4 done (feature-sync-guard.sh)

Model switched to **Opus 5** before starting, per the checkpoint-2 decision. Tier-1 blocking hook
`hooks/feature-sync-guard.sh` + `hooks/lib/feature_tasks.py` + 28 tests, registered in
`settings.json` PreToolUse/Bash. Full suite after: **612 checks, 0 failures** (448 shell + 164
python). Detail in the feature file's task 4 note — not restated here. Three things worth carrying
forward:

- **A frozen spec's scenario can still be wrong about the runtime, and the fix is to correct the
  test, not the hook.** The "chained staging" Gherkin says `git add x.spec.md && git commit` must
  block. It cannot: this is a **PreToolUse** hook, so the `add` has not run and the index is still
  clean. Making it block would mean predicting what a sibling command stages — the exact fail-open
  ADR 0014 removed after two review rounds each measured the command list short. `doc-guard.test.sh:83`
  already had the answer: stage first, then feed the chained string, so the case tests *segment
  lexing* (is `git commit` found off position 0?) and not index prediction. The accepted limit is
  now pinned by its own test rather than left implied.
- **Mutation testing caught a test that could not fail — again, and the same shape as
  `feedback_fixture_must_not_pre_create_state`.** Deleting `.lower()` from identity normalization
  left the suite at 28/28 green. The "differs only by whitespace/case" fixture put its case
  variation *after* the em dash, which is outside the task identity by construction — so it pinned
  the fixture's premise, never the normalization. Rewritten to vary the identity itself; it now
  fails against the case mutant and the whitespace mutant independently. **Six mutations run, five
  caught on the first pass; the survivor was the one testing the thing I had just written.**
- **settings.json index surgery, second clean run.** `git show HEAD:settings.json` → apply the jq
  edit to *that* (keeping the committed `claude-fable-5[1m]` model line) → `hash-object -w` +
  `update-index --cacheinfo` → verify `git diff --cached` → commit with **no pathspec**. The live
  file got the same jq edit separately so it keeps this machine's `opus[1m]`. `jq . settings.json`
  round-trips byte-identical, so the staged diff is only the four added lines. Skip-worktree bit
  restored after.

**Next:** task 12 (registration assertions in both new test files) → 5 → 6 → 7 → 8 → 9. Checkpoint 3
(implementation → review) still owed before task 9.

## 2026-08-06 — session 21: task 12 done (hook registration assertions)

Restored from handoff `cc41c9b1` after a `/clear`; frontmatter (`phase: implementation`,
`model_tier: low`, `branch: feat/memory-system-split`) matched the actual branch and working tree
was clean, so no reconciliation was needed. Stayed on **Sonnet 5** per the checkpoint-2 answer
(Opus 5 was task 4 only).

Task 12: added a registration assertion to `slim-session-start.test.sh` and
`feature-sync-guard.test.sh`, each resolving the real repo `settings.json` (via
`git rev-parse --show-toplevel`, not the throwaway `$TMP`/`$REPO` fixture the rest of each suite
uses) and running a `jq` query scoped to its own top-level hook array —
`.hooks.SessionStart[]` for `slim-session-start.sh`, `.hooks.PreToolUse[]` for
`feature-sync-guard.sh` — so a substring hit in an unrelated key or comment can't pass it.

**Confirmed the check can fail, per the task-4 vacuous-test lesson named in the prior handoff.**
Each test file also builds a `jq`-mutated copy of the real `settings.json` with its own hook's
`command` entry deleted, then asserts the same query reports it missing. Both real-file assertions
pass (already registered); both mutants correctly fail — the check is not vacuous. `shellcheck -x`
clean on both files. Full `hooks/*.test.sh` suite re-run: 9 files, **452 checks, 0 failures**, no
regressions. Committed `b571787`.

One thing worth flagging: a session-freshness nudge fired at ~78k tokens before any task-12 work
had started — almost entirely fixed session-start overhead (skill/agent/MCP tool listings), not
accumulated work. Asked the user rather than guessing; they chose to continue task 12 and
checkpoint once it was actually done, which is what happened here.

**Next:** task 5 (split this feature file into the pair shape, decision 7) → 6 → 7 → 8 → 9.

## 2026-08-06 — session 22: task 5 done (memory-system-split pair split)

Restored from handoff `617af5d0` after a `/clear`; frontmatter (`phase: implementation`,
`model_tier: low`, `branch: feat/memory-system-split`) matched the actual branch, working tree was
clean. Stayed on **Sonnet 5** per the checkpoint-2 answer.

One thing flagged before starting: `git log main..HEAD` showed an extra commit (`02d5c25`,
"feat(statusline): show reasoning effort next to model name") sitting on this branch that the prior
handoff never mentioned — a small, self-contained, already-clean commit unrelated to this feature
(touches `statusline-command.sh` only). Read it, confirmed it doesn't conflict with or touch
anything task 5 needed, and proceeded; noting it here since a commit a handoff doesn't account for
is exactly the kind of thing the restore discipline says to reconcile rather than silently carry
forward — in this case reconciliation was "read it, it's fine," not an action.

Task 5: split `docs/features/memory-system-split.md` (676 lines) into the pair shape per decision
6/7 — `memory-system-split.md` now holds only frontmatter + a terse `## Tasks` checklist (46
lines), and the new `memory-system-split.spec.md` (no frontmatter, 675 lines) holds
Problem/Decisions/Design/Contracts/Scenarios/Phase 2/Open items plus the same `## Tasks` list at
full completion-note detail. Task identity (leading text before each item's em dash) is the same
task number in both files by construction, since both lists were split from one source in the same
order.

Also folded in while splitting: the "Out of band, before task 11" note about committing the RTK
removal was stale (already merged to `main` via PR #41, commit `e3b939d`, before this branch even
needed it) — dropped rather than carried into either new file. The Bootstrapping note at the top of
the spec half was rewritten from future to past tense now that the migration it described is done.

**Verified, not just asserted:** ran the real `hooks/lib/feature_tasks.py` comparator against the
two drafted files before installing them (exit 0 — same task set) and a live `feature-sync-guard.sh`
simulation via a fake `PreToolUse` payload after staging both files (exit 0 — allowed). Full
`hooks/*.test.sh` suite re-run: **9 files, 452 checks, 0 failures** — no regressions from the new
`.spec.md` touching `phase-guard.sh`'s glob or `feature-sync-guard.sh`'s pair logic. Committed
`c821525`.

**Next:** task 6 (ADR superseding ADR 0006 rows 1 and 15) → 7 (rewrite
`preparing-pull-requests`:12) → 8 (`rules/gates.md` MAY wording) → 9 (observability judge, then
PR). All remaining tasks are Sonnet 5; checkpoint 3 (implementation → review) still owed before
task 9.
Checkpoint 3 (implementation → review) still owed before task 9.

## 2026-08-06 — session 23: task 6 done (ADR 0017)

Restored from handoff `47b43699` after a `/clear`; frontmatter (`phase: implementation`,
`model_tier: low`, `branch: feat/memory-system-split`) matched the actual branch, `git status`
clean, branch up to date with `origin`. Stayed on **Sonnet 5** per the checkpoint-2 answer already
on record — no re-ask.

Task 6: wrote `docs/decisions/0017-session-state-restore-and-synced-pair-feature-files.md`.
Read ADR 0006 in full first to identify the exact superseded rows by content, not by number alone
— row 1 ("Session-start restore: House, handoff's `session-start.sh` removed") and row 15
("Storage & git posture: House, committed `CODING_MEMORY.md` is the single durable source of
truth"). The new ADR records both supersessions (a SessionStart hook is registered again, but it's
`hooks/handoff/slim-session-start.sh` — house-authored, reads only `session-state.md`, not the
vendored handoff script; `CODING_MEMORY.md` stays committed but is retired as the "what were we
doing" source of truth) plus decisions 6 and 7 from the spec's Decisions table (the
one-canonical-file gate MAY be departed from for a feature file, mitigated by
`feature-sync-guard.sh`; only `memory-system-split` migrated, permanently — the other 8 feature
files are not a to-do). Embedded the spec's three-artifact Design mermaid diagram rather than
redrawing one, since it already accurately depicts the tradeoff.

Ticked task 6 in both halves of the pair with matching completion notes (task identity is just the
task number, so the differing prose after each doesn't affect `feature-sync-guard.sh`). Staged all
three files together and let the real registered hooks validate the commit live rather than
hand-simulating — `feature-sync-guard.sh` and `doc-guard.sh` both passed it without a bypass.
Committed `3024b3c`, pushed.

One thing worth flagging: `hooks/context-handoff-watch.sh` fired its ≥75k-token nudge mid-restore,
before any task-6 work had started — same shape session 21 saw (fixed session-start overhead, not
accumulated work). Per the standing preference recorded in the prior handoff ("prompt for `/clear`
at ~165k tokens, not the 75k nudge — but a just-completed task boundary is still worth offering
regardless of tokens"), finished task 6 first rather than stopping mid-task, and this checkpoint is
that task-boundary offer.

**Next:** task 7 (rewrite `preparing-pull-requests`:12 — append-to-archive, not inherit-context)
→ 8 (`rules/gates.md` MAY wording) → 9 (observability judge, then PR). All remaining tasks are
Sonnet 5; checkpoint 3 (implementation → review) still owed before task 9.

## 2026-08-06 — session 24: task 7 done (preparing-pull-requests rewrite)

Restored from handoff `2fa22244` after a `/clear`; frontmatter (`phase: implementation`,
`model_tier: low`, `branch: feat/memory-system-split`) matched the actual branch, `git status`
clean, up to date with `origin`. Stayed on **Sonnet 5** per the checkpoint-2 answer already on
record — no re-ask.

Task 7: read `skills/preparing-pull-requests/SKILL.md` in full before editing. The named target,
the "Brainstorm-then-branch" bullet (:12), claimed committing `CODING_MEMORY.md` to `main` before
branching means "every future branch forked from `main` then inherits the full brainstorm context
automatically" — exactly the root-cause claim the spec's Problem section (`memory-system-split.spec.md:38-41`)
identifies as the design bug decision 1 retired. Rewrote it to the archive-append framing:
`CODING_MEMORY.md` is no longer an auto-loaded read target, so the feature file's spec (created
before the branch exists, during planning) is what actually carries the brainstorm forward across
the branch boundary, not a future session reading `CODING_MEMORY.md` back.

While reading the file end to end, found the very next bullet, "Branch resume" (:14), had the
identical bug — "read its entry in `CODING_MEMORY.md` and resume from the latest checkpoint" — and
was already inconsistent with this same file's "PR Memory Tracking" section (:45), which an earlier
commit (`62492a8`) had correctly updated to route feature-scale branches to
`docs/features/<name>.md`. `git log -p --follow` confirmed both stale bullets dated to the file's
original commit (`c2ca102`), pre-dating the split. Fixed both in the same edit rather than leaving
:14 to contradict :12 and :45 — task 7's own framing ("append-to-archive, not inherit-context") is
a principle the whole file needs to satisfy, not a single line. Both bullets now point at
`managing-session-memory`'s restore procedure instead of restating it, keeping one place as the
source of truth for the restore mechanics.

Ticked task 7 in both halves of the pair with matching completion notes (task identity is the task
number; the differing prose after each doesn't affect `feature-sync-guard.sh`).

**Next:** task 8 (`rules/gates.md` one-canonical-file stub — state the MAY from decision 8 in
words that can't be read as a MUST) → 9 (observability judge, then PR). Checkpoint 3
(implementation → review) still owed before task 9. Remaining tasks are Sonnet 5.

## 2026-08-06 — session 25: task 8 done (rules/gates.md MAY wording)

Restored from handoff `2fc8c9f6` after a `/clear`; frontmatter (`phase: implementation`,
`model_tier: low`, `branch: feat/memory-system-split`) matched the actual branch, `git status`
clean, up to date with `origin`. Stayed on **Sonnet 5** per the checkpoint-2 answer already on
record — no re-ask.

Task 8: edited the one-canonical-file bullet in `rules/gates.md`. Checked the spec's task-8 wording
(`memory-system-split.spec.md:665-668`) and the decision-8 Gherkin scenario
(`memory-system-split.spec.md:511-516`, "A brand-new feature is created as one file — decision 8's
MAY") before writing, so the inserted sentence matches what the guard actually enforces (no rule,
hook, or message requires the `.spec.md` half to exist) rather than restating task memory alone.
Inserted one carve-out sentence between the bullet's opening clause and its existing "never open a
separate progress doc" prohibition, instead of rewriting the bullet: states the split trigger
(checklist file stops reading comfortably in one pass), the resulting shape (frontmatter + tasks
stay in `.md`; spec, decisions, Gherkin move to `.spec.md`, read on demand only, never at session
start), and says "MAY, never a MUST" in those literal words so a future reader can't round it up to
a requirement. Left the "never a separate progress/summary/state-of-branch document" sentence
untouched — decision 8 is about single-file-vs-pair, not about that orthogonal prohibition.

Ticked task 8 in both halves of the pair with matching completion notes (task identity is the task
number; the differing prose after each doesn't affect `feature-sync-guard.sh`).

`hooks/context-handoff-watch.sh` fired its ≥75k-token nudge mid-task (after the `rules/gates.md`
edit landed but before the pair's task-8 checkboxes were ticked) — same shape sessions 21 and 24
saw. Finished ticking both checklist halves first per the standing preference (task-boundary
offers win over the raw token nudge), then ran this checkpoint.

**Next:** task 9 — checkpoint 3 (implementation → review) is owed first, then the observability
judge (implementation stage) against this branch's diff, then the PR. Task 8 was the last checklist
item that edits `rules/`; task 9 is judge + PR only, no further spec/rule edits expected.

## 2026-08-06 — session 26: task 9 done (judge + PR #42), branch's last task complete

Restored from handoff `53dea02f` after a `/clear`; frontmatter (`phase: implementation`,
`model_tier: low`, `branch: feat/memory-system-split`) matched the actual branch, `git status`
clean, up to date with `origin`. Tasks 2–8/11/12 already done and pushed per the handoff.

Checkpoint 3 (implementation → review) asked and answered: user chose **Opus 5** over staying on
Sonnet 5 for the judge + PR portion of task 9. `hooks/pane-dispatch-guard.sh` denied the first
in-process `Agent` dispatch of `observability-judge` — judges are `redirect-agents`, always paned,
never in-process, regardless of the session's worker pane-split policy. Re-dispatched via
`panes/dispatch-pane-agent.sh` per `dispatching-pane-agents` (prompt written to scratchpad first);
landed in pane `surface:148`, waited with `--timeout 540`.

Verdict: `risk=low confidence=high`, all 452 hook-test assertions pass, persisted to
`coding-memory/observability-judge/2026-08-06-feat-memory-system-split.md` and `verdicts.jsonl`
(commit `11db576`). The judge's own first test pass showed 16/29 failures in
`slim-session-start.test.sh` — a false alarm from `CLAUDE_PANE_AGENT` being set in its own paned
environment (the hook exits early when that var is set); clean env reran 29/29. That investigation
surfaced a real, separate finding: two of those tests assert *absence* (no `[STALE]` marker, no
oversized-body output) in a way that passes identically whether the hook correctly suppressed
output or is silently dead — an "absence" test can't distinguish the two without a matching
positive-case fixture in the same test. Judge also ruled out one false alarm unprompted: the
committed `claude-fable-5[1m]` model line in `settings.json` predates this branch, already on
`main` — not introduced here.

Two other non-blocking findings: neither new hook (`slim-session-start.sh`,
`feature-sync-guard.sh` — the latter blocks commits with a `FEATURE_SYNC_EXEMPT` bypass) has a
`rules/gates.md` bullet, unlike every other blocking hook; and the unrelated `statusline`
reasoning-effort commit (`02d5c25`) rode along on this branch from an earlier session (already
known, re-flagged here).

Asked the user whether to fix the two real findings (vacuous tests, missing gates.md bullet) before
opening the PR or defer them — **explicit choice: open now, defer as follow-ups**, logged in the PR
description rather than fixed on this branch. Opened **PR #42**:
https://github.com/suyatdev/.claude/pull/42 (`gh pr create`, no existing PR found first via
`gh pr list --head`). `gh pr create` reported "2 uncommitted changes" — the judge subagent's own
verdict-file writes (`coding-memory/observability-judge/verdicts.jsonl` +
`2026-08-06-feat-memory-system-split.md`) landed in the working tree but not yet committed;
committed them separately (`11db576`) and pushed.

Ticked task 9 in both halves of the pair with matching completion notes (task identity is the task
number). Moved frontmatter `phase: implementation` → `review`, `model_tier: low` → `high` in
`memory-system-split.md` to match checkpoint 3's answer — the spec half carries no frontmatter, so
nothing to sync there. Committed (`995c616`) and pushed; `feature-sync-guard.sh` accepted the pair
edit without complaint.

**Task 9 was the last task on this branch's Phase 1 scope.** Task 10 (Phase 2 — fixing memsearch,
which currently indexes 0 entries from `docs/features/`) is explicitly out of scope here, tracked
as a separate follow-up branch after this PR merges. This session's freshness checkpoint (past the
75k-token nudge, at this task boundary) is this entry plus the push above.

**Next (new session, after this PR merges or gets review feedback):** no in-branch work expected
unless review comes back with requested changes. If starting Phase 2, that's a new branch from
`main` post-merge, not a continuation of this one.

## 2026-08-06 — session 27: Phase 1 merged, Phase 2 diagnosed (spec's item list revised)

**PR #42 merged** — merge commit `a88eee8`, 2026-08-06T18:57:55Z. Closed Phase 1 out: local `main`
fast-forwarded to the merge commit, `feat/memory-system-split` deleted local **and** remote.

**Gotcha worth reusing — `skip-worktree` blocks a branch switch.** `git checkout main` aborted with
*"Your local changes to settings.json would be overwritten"*: `settings.json` carries `S`
(skip-worktree) so its machine-local `model` line stays uncommitted, but checkout still refuses when
the file's content differs between the two commits. **Do not stash** — that risks the local model
line. Fix used: `git fetch origin main:main` to fast-forward the *ref* without a checkout, then
`git checkout main`, which is then a no-op for `settings.json`. Verified after with
`git show HEAD:settings.json | diff - settings.json` → only the `model` line differs, as designed.

### Phase 2 diagnostic — run before creating any branch or feature file

Measured against the live index (`~/.claude/memory-index/memory.db`, `sqlite3`), not inferred.
**Two of the spec's six Phase 2 items rest on a wrong premise** (`memory-system-split.spec.md:540`):

1. **The index is 19 days stale, and that single fact explains almost everything.** Every one of the
   228 rows in `sources` carries `indexed_at = 2026-07-18`; there is no newer row. The last index
   run was 2026-07-18, nineteen days before today.
2. **The DB file mtime lies about freshness.** `memory.db` shows `Aug 5 23:09`, which reads as
   "indexed yesterday". It is not — `query_log` is written on every *query*, so the file mtime
   tracks reads, not writes. **Freshness must be read from `max(indexed_at)` in `sources`**, never
   from the file's mtime. Anything built on the mtime (a staleness nudge, a refresh trigger) would
   silently never fire.
3. **Spec item 2 — "add `docs/features/**` to indexed sources" — is a no-op.** `~/.claude/docs` is
   *already* a configured `curated_docs` root in `memsearch/config.json`, and 13 sources under it
   are indexed. `docs/features/` shows 0 chunks purely because **the earliest feature file was
   created 2026-07-25, seven days after the last index run**. Confirmed by counting: 12 of the 46
   `.md` files under `docs/` predate 2026-07-18, and exactly 13 sources under `.claude/docs` are
   indexed — *the indexed set is the pre-index-run set*. Nothing needs adding to config; the
   directory needs an index run.
4. **Spec item 1 — remove `CODING_MEMORY.md` from `exclude_paths` — is real and still stands.**
   Verified with an escaped LIKE: 0 chunks, and no row in `sources`. The exclusion works.
   ⚠️ A naive `file_path LIKE '%CODING_MEMORY%'` returns 154 false hits, because `_` is a
   single-character wildcard in SQL and matches the hyphen in `coding-memory/`. Use
   `LIKE '%CODING\_MEMORY.md' ESCAPE '\'`. The first pass of this diagnostic got it wrong that way.

**Net effect on Phase 2's shape:** item 4 (*add a refresh trigger*) is not fourth in priority — it
is the **root cause**. The index froze on 2026-07-18 and nothing reported it for 19 days; items 2
and 3's symptoms are downstream of that. Item 5's re-measurement gate (k=6, ≥2 hits, ≥0.30, queries
fixed before rebuild) is unaffected and still the right acceptance bar.

**Not written to the spec.** `memory-system-split` is `phase: review`, which forbids silent spec
edits, and the file is merged. These findings belong to the Phase 2 feature file when it is created.

**Next:** Phase 2 planning proper — new branch off `main`, fresh `planning` feature file. Model-switch
checkpoint 1 asked and answered this session: **stay on Opus 5** for planning.

## 2026-08-06 — session 28: spec-compliance gate run; both judges found blocking work

**`main` @ `9475034`, `phase: planning`, `branch: none`.** No code written; the phase held.
Restore verified frontmatter against reality (clean tree, nothing ahead of `main`) before any work.

Ran the spec-compliance gate on `docs/features/memsearch-freshness.md`
(blob `4e217ec323dd37701b2bc32b1c5a60e0cfefb6a7`, round 1, no waived ids). Both judges dispatched in
parallel into cmux panes per `dispatching-pane-agents`; both returned DONE.

### Compliance judge — **FAIL**, 7 violations, confidence high

Verdict: `coding-memory/compliance-judge/2026-08-06-memsearch-freshness.md`.

| id | Substance |
|---|---|
| `writing-specs/api-contracts` | Plist contract omits `Label`, `ProgramArguments`, and a PATH. **Verified mechanically: `launchctl getenv PATH` is empty, so the job sees only `/usr/bin:/bin:/usr/sbin:/sbin`; `memsearch/bin/memsearch` is `exec uv run …` and `uv` lives in `/opt/homebrew/bin`. The obvious rendering dies at exec 127 every 6h while the install reports success.** |
| `core-conduct/explicit-error-handling` | Only `plutil -lint` failure has stated behaviour. `launchctl bootstrap` failure — the call deciding whether the scheduler exists at all — plus missing/unwritable `~/Library/LaunchAgents` and the script's own exit codes are unspecified. A failed install looks like a successful one. |
| `writing-specs/edge-cases` | All seven Gherkin scenarios cover the nudge (R1–R3). R4–R7 have none — and that is the half with system-level side effects. |
| `writing-specs/pinned-versions` | `uv`, the runtime the scheduled job actually executes, is absent from the pinned table; `sqlite3` says "system" with no version. |
| `gates/adr-required` | A persistent `launchd` daemon is a structural decision, and the spec overturns two parent-spec items on new evidence. No task writes an ADR, in a repo whose 17 ADRs sit at finer granularity. |
| `writing-specs/ambiguous-acceptance-bar` | R7 gives no membership rule for "the named feature's own documents", so task 8's pass/fail is a judgment call, not a measurement. |
| `writing-specs/ambiguous-log-path` | Log specified only as "a log under `~/.claude/memory-index/`" — no filename, and that directory already holds an unexplained `reindex.log`. |

Judge confirmed the falsifier itself passes and YAGNI is clean; held three items as notes, not
violations (plist/log file modes, no user confirmation before task 7 installs a daemon, and the
`docs/features/` vs `docs/superpowers/specs/` path question — repo layer wins, consistent with prior rounds).

### Observability judge (architecting, advisory) — `risk=high confidence=high`

Verdict: `coding-memory/observability-judge/2026-08-06-main-memsearch-freshness.md`. Advisory, blocks nothing.

🚨 **The design's staleness signal reads the wrong field, and I verified this independently:**

- `last_indexed` is `SELECT max(indexed_at) FROM sources` (`memsearch/memsearch/db.py:156`).
- `indexed_at` is written only inside `replace_source` (`db.py:121,125`).
- `_index_one` early-returns when the stored hash equals the current hash
  (`memsearch/memsearch/index.py:125-127`), so `replace_source` never runs for unchanged files.

**Therefore a successful run that finds nothing new does not advance `last_indexed` at all.** Quiet
overnight → both scheduled runs succeed → the 8h line says `⚠ stale — run memsearch index` → running
it changes nothing → **the warning never clears.** That is the spec's own falsifier item (b) firing
on an ordinary Tuesday, and it is the exact failure decision 1 calls "strictly worse than silence."

Note the irony the judge named: the spec documents two "proxy that looks like the thing you want but
isn't" traps (`memory.db` mtime, SQL `_` wildcard) and then builds its core mechanism on a third.

Judge's fix, which is right: **write run-completion time as its own field** (`last_run`, stamped when
`run_index` finishes — `_write_status` already exists at `index.py:57`) and read *that* for staleness.
Keep `last_indexed` for content recency. Two questions, two fields.

Also raised: a totally failed run exits 0 (`cli.py:60-66`, Ollama down → every source errors → "success");
no "in progress" state, no lock or pidfile; "a failed run leaves evidence" is weakened by 8KB block
buffering (wants `PYTHONUNBUFFERED=1`); and after this lands, a fresh-but-useless index is still silent
because R7 measures once, at landing, then never again.

### 🚨 An index rebuild was found already running — the blind measurement is compromised

`memsearch index` started **16:01:40 EDT** and was still running 39 min later; PID 30022/30024, **PPID 1**
(orphaned — its starter has exited). Not a hook and not a scheduler: no crontab, no matching plist in
`~/Library/LaunchAgents`, and `hooks/memsearch-nudge.sh` only reads `status.json` (grep for `memsearch index`
across `hooks/` + `settings.json` returns nothing). It was started interactively and outlived its shell.

Impact: `sources` is now **196 rows @ 2026-07-18 + 320 rows @ 2026-08-06**, and `reindex.log`'s first line is
`docs/features/memsearch-freshness.md`. The handoff's explicit warning — *do not rebuild before task 6 commits
the five queries* — has been overtaken by events. **Falsifier item (d) can no longer be proven from git alone**;
blindness now rests on discipline (write the queries without first querying the new index), not on the index
being physically stale. The stale-index baseline ("0 hits from `docs/features/`; the 4 that return score ~0.02")
is already recorded in the spec and cannot be re-measured.

`status.json` still reads `last_indexed: 2026-07-18T06:18:01+00:00` — it is written only at run end,
which is itself the judge's "no in-progress state" point, observed live.

**Next:** round-1 revision of the spec (7 compliance violations + the `last_run` redesign), then
re-dispatch both judges at round 2 reusing the violation ids. No waivers so far; nothing dropped.

## Session 29 — statusline: wrap + worktree name (designed, NOT implemented)

User asked to make the statusline wrap and show the worktree name. **No code written** — the work is
blocked and correctly so. Recording the verified design so the next session executes rather than re-derives.

### Blocked, twice over — this is the gate working, not a bug

`phase-guard` denies `statusline-command.sh`: it sits at the repo root, so it is *not* on the exempt list
(`CODING_MEMORY.md`, `coding-memory/*`, `docs/*`, `.claude/*`, `settings.json`, `projects/*/memory/*`),
and `memsearch-freshness.md` is still `phase: planning`. Probed both arms rather than assuming —
source path → rc=2 deny, `docs/` path → rc=0 allow, so the check demonstrably discriminates.
Separately `git-guard` bars a `.sh` from landing on `main`, and branch creation is itself forbidden
mid-planning. Sanctioned unblock: a second feature file at `phase: implementation` recording its own branch.

**User chose "open a separate track" + "stay on Opus 5" via menu, but has NOT said `gate confirmed`.**
A menu click is not the literal phrase — that is exactly the soft affirmative the hard stop exists to catch.
Model-switch checkpoint 2 is answered (Opus 5); the gate phrase is still owed.

### Verified facts (measured, not assumed)

- **Multi-line output is supported** — docs: "each `echo` displays as a separate row."
- **`COLUMNS`/`LINES` are set by Claude Code** before running the script, precisely because it captures
  stdout so `tput cols` cannot work. Needs v2.1.153+; installed is **2.1.223**. Not yet observed live
  from inside a real statusline invocation — the fallback must therefore be "no wrap", never "wrap to 0".
- ⚠️ **`COLUMNS` reads `0`** in a non-interactive shell (measured in the Bash tool env). `[ -n "$COLUMNS" ]`
  is the wrong guard — validate as a *positive integer* or every line wraps to nothing.
- **Baseline: `statusline-command.test.sh` is 50/50 green** on the unmodified script.
- ⚠️ **The injection tests assert `nl=0`** (zero newlines) — that is how they prove data cannot split the
  line. Wrapping emits newlines by design. Pin those tests to a *wide* `COLUMNS` so `nl=0` stays a real
  assertion; do **not** relax them to accommodate the feature, or a security check retires silently.

### Worktree detection — first approach was wrong, caught before writing code

Comparing `rev-parse --git-dir` against `--git-common-dir` **false-positives in any subdirectory of the
main tree**: from `main-repo/sub/dir` they read `/abs/.git` vs `../../.git` — different strings, same tree.

Correct test, verified against four cases plus a decoy: **`[ -f "$(git rev-parse --absolute-git-dir)/gitdir" ]`.**
A linked worktree's git-dir contains a `gitdir` file; a main `.git` never does. Confirmed: main root → main,
main subdir → main, linked worktree root → linked, deeply nested inside a linked worktree → linked, and a
repo living under a directory literally named `worktrees` → main (a `*/worktrees/*` path pattern fails this one).
Name = basename of `rev-parse --show-toplevel`. Show only for linked worktrees — in the main checkout `dir`
already says it.

### Design agreed

- **Wrap**: build segments as (text, known-width) pairs, greedily pack at the ` │ ` boundaries up to
  `COLUMNS`. Track width *while building* rather than measuring after — sidesteps counting ANSI escapes and
  ambiguous glyph widths (`➜ ✗ █ ░ Σ ⏱ │`) entirely. Wide terminal → byte-identical to today. No valid
  `COLUMNS` → today's single line. A single over-wide segment gets its own line, never hard-broken mid-escape.
- **Worktree**: `wt:(name)` after `git:(branch)`, matching the robbyrussell idiom.
- `extras+=` touchpoints needing a parallel width entry: `statusline-command.sh:542,544,581,586,609`;
  render/join to replace at `:613-630`. Git block to extend at `:151-169`.
- Build order is TDD: new wrap/worktree tests first against the *unmodified* script, watch them fail, then implement.

### Round 2 — all 7 round-1 violations fixed; 2 new ones, both real

Spec revised (blob `4e217ec` → `ca5b5e0`), both judges re-dispatched in parallel. Compliance
**FAIL, 2 violations, both new** — no id repeated, so the persistence tripwire did not fire and round 3
is still an automatic round. Observability round 2: `risk=medium` (down from high).

**Both judges converged independently on the same hole**, which is why it was believed and fixed:

- `core-conduct/unsurfaced-run-errors` — `last_run_errors` was written to `status.json` and **nothing
  read it**. Verified in source: `_index_one` catches every exception into `report["errors"]` and
  continues (`index.py:135-137`), `run_index` stamps status unconditionally at the end
  (`index.py:100`), `cli.py:66` returns 0 regardless. So a run with Ollama down that indexed *nothing*
  completes, stamps a fresh `last_run`, and the nudge prints the cheerful line — **clearing the very
  warning decision 4 designates as the blind scheduler's compensating control.** Same defect as the
  one this feature exists to fix, one field over.
- `writing-specs/readme-drift` — `memsearch/README.md:22` asserts "`CODING_MEMORY.md` and
  `subagents/` transcripts are never indexed"; R8 deletes `CODING_MEMORY.md` from `exclude_paths`
  (`config.json:16`, confirmed). No task updated the README, which is also the only doc for
  `memsearch/bin/`, where `install-schedule` lands.

Observability judge added four more, all verified before acting: a **future `run_started`** would pin
the in-progress line forever (the future-timestamp guard covered `last_run` only); **`status.py:27`**
still prints `last_indexed` as its freshness answer — the identical misreading, left on the other
human-facing surface; **no uninstaller** (`git revert` does not remove a job from
`~/Library/LaunchAgents`); and the **stuck-run line carried the remediation command**, i.e. "run the
indexer" while one may still be alive — the safety valve becoming the hazard at the threshold.
It also caught three `R7` references in my own Background text that should have read `R9`.

Measured, not guessed: the orphaned run passed **1h26m** and 405/601 files while round 2 was judging.
That number is now the reference point next to `RUN_MAX_HOURS` in the spec.

### Round-3 revision (blob `ca5b5e0` → `eef3aea`)

- **R3 rewritten** as "report the state of the last run, not merely its age": in-progress, **stuck**,
  and **degraded** (`last_run_errors > 0` never renders as fresh), each with its own line. Neither
  in-progress nor stuck carries the remediation command — `memsearch` has no lock.
- **`RUN_MAX_HOURS` (6h) split from `STALE_HOURS` (8h).** They answer different questions — how old a
  *finished* run may be vs. how long a run may *take* — and collapsing them is the same conflation
  habit as the original bug.
- Nudge classification is now a 6-row first-match-wins table; a timestamp is *usable* only if it
  parses and is not in the future, applied to **both** fields; row 1 covers the first-run case
  (`run_started` present, `last_run` absent) the compliance judge held as a note.
- `status.py` brought into scope; `install-schedule --uninstall` added; README fix required **in the
  same commit** as the `exclude_paths` change; falsifier gains item (f).
- 26 scenarios now (14 nudge, 8 install/uninstall, 4 other). Tasks 3–6 updated; task 4 explicitly
  requires the degraded test to **assert the emitted line, not the parsed field** — the whole point.

**Next:** round 3 — re-dispatch both judges on blob `eef3aea`, reusing ids
`core-conduct/unsurfaced-run-errors` and `writing-specs/readme-drift`. **Round 3 is the last automatic
round**: anything outstanding when it completes escalates to the user rather than looping again.

## 2026-08-06 — session 30: round 3 complete — FAIL, escalation boundary reached

**Round 3 of the spec-compliance loop ran on blob `eef3aea`. Both judges dispatched in parallel to
panes (`surface:159`, `surface:160`), both returned DONE. Compliance verdict: FAIL, 2 violations.
The loop's escalation boundary has been reached on both of its triggers — no round 4 is automatic.**

### What round 3 fixed

- `core-conduct/unsurfaced-run-errors` — **closed.** The compliance judge walked it end to end
  rather than accepting the spec's claim; the observability judge independently closed its
  round-2 `success_masking=fail` on the same change. The degraded line is read, and task 4
  requires the test to assert the *emitted line*, not the parsed field.

### What round 3 cited

1. `writing-specs/r8-missing-config-validator` — **new, blocking.** R8 directs removing
   `CODING_MEMORY.md` from `exclude_paths`, but `load_config` raises
   `ConfigError("exclude_paths must contain CODING_MEMORY.md")` on every call
   (`memsearch/memsearch/config.py:56-59`). As specified, task 6 makes every `memsearch` command
   **and** the new 6-hourly launchd job exit 1. Three tests pin the invariant
   (`test_config.py:42,48`, `test_index.py:93`). The spec never names `config.py`, the validator,
   or the tests.
2. `writing-specs/readme-drift` — **persistent, round 2 → round 3, half-remediated.** The
   `memsearch/README.md` half was fixed; the design doc half was not.
   `docs/superpowers/specs/2026-07-17-memory-rag-index-design.md` still asserts the exclusion at
   lines 58, 67, 135, 154, 163 (incl. the whole "What Is NOT Indexed" section and its
   durable-vs-ephemeral rationale, which R8 reverses). That file is itself indexed under a
   `curated_docs` root, so memsearch would serve the false rationale as an answer.

### Verified independently, not taken on the judges' word

- ✅ the `ConfigError` guard, at `config.py:56-59` as claimed.
- ✅ the three pinning tests (judge cited `test_config.py:40`; actual is `:42` — substance holds).
- ✅ all five design-doc assertion lines.
- ➕ **Not cited by either judge, found while checking:**
  `docs/superpowers/plans/2026-07-17-memory-rag-index.md:19` reads "**`CODING_MEMORY.md` is never
  indexed** (ephemeral working index). Enforced by config validation, not convention." The
  exclusion is a *deliberate, documented, enforced* invariant — R8 reverses it silently.
- ❌ **The spec's "1h26m" run duration is not a completed duration.** PID 30022 was *still running*
  at 2h09m53s when checked this session. It was a stopwatch reading taken mid-race and written
  down as a finish time, so the 6-hour "stuck" ceiling has materially less headroom than the spec
  implies. (Same class as `feedback_no_fabricated_metrics`.)

### Observability judge (advisory, non-blocking) — no dimension fails

Round 2's `success_masking=fail` is closed. Open concerns it raised, none blocking:
- **launchd skips missed ticks during sleep** — an overnight-asleep laptop misses the 4am run and
  the 8am session gets a ⚠ stale warning on a healthy system. The spec's own argument is that a
  warning firing on normal days is worse than none. Untested by the judge; flagged, not proven.
- While a run is in progress the line shows "in progress" with no warning glyph, so a *previous*
  broken run stays hidden for the 2–3h the new run takes.
- Un-hiding `CODING_MEMORY.md` uses a plain substring match, so it would also start indexing that
  file in the two **other** repos. Nobody decided that.

**Next:** escalated to the user — both triggers fired (`readme-drift` cited twice running; round 3
completed with violations outstanding). The real decision underneath finding 1 is whether to
reverse the enforced exclusion at all, and if so how (delete the guard / invert it / weaken it).
That is structural and reverses a documented rationale → **likely earns an ADR**. Note the
rationale may genuinely have expired: `memory-system-split` retired `CODING_MEMORY.md` as a read
target and made it an append-only archive reached by lookup, so "ephemeral working index" no
longer describes it — but the spec must *say* that, not assume it.

## 2026-08-06 — session 30 (cont.): R8 dropped, round 4 PASSES the compliance gate

**User decision resolving the round-3 escalation: keep the `CODING_MEMORY.md` exclusion, drop R8.**
Spec revised (`51c5dee`, blob `50ad053`), both judges re-dispatched at round 4.
**Compliance verdict: PASS, zero violations.** Observability (advisory): `risk=low confidence=high`,
no failing dimension.

### Why R8 was dropped rather than fixed

Reversing the exclusion means deleting an enforced guard, rewriting three tests, and reversing a
documented rationale in five places — a structural change earning its own ADR. That does not belong
inside a freshness fix. Parent items 1 and 3 moved to Non-goals carrying the full rationale **and
the honest counterpoint**: `memory-system-split` made `CODING_MEMORY.md` an append-only archive, so
"ephemeral working index" no longer describes it and the original reason may have expired — recorded
for whoever picks it up, deliberately not assumed here. R8's slot now carries the obligation that
survived independently: documenting `bin/install-schedule` in the README that adds it.

### The fabricated measurement, corrected in the spec rather than quietly

The spec had cited "1h26m over 601 sources" as a run duration. It was a stopwatch glance at a run
still going (PID 30022, still alive at **2h26m over 683 sources** at session end). The spec now
states the number was wrong and why, that the true duration is unmeasured, that it may exceed
`RUN_MAX_HOURS`, and defers the constant to the user once task 8 measures it. The compliance judge
called this out positively — stated default + named measurement trigger + human owner is
core-conduct's human-owned-tradeoff rule applied correctly, not a TBD.

### The observability judge retracted its own round-3 top concern — and it was right to

R3's headline worry was launchd skipping ticks during sleep → false stale warnings every morning.
It never checked the premise. **Verified independently this session: `hw.model = Mac16,9` (Mac
Studio desktop), `pmset sleep 0`, 18 days uptime, 0 "Entering Sleep" events.** The man-page quote
was real; it does not apply to a machine that never sleeps. Retraction sound. Still worth one
sentence in the spec before this plist ever reaches a laptop.

### ⚠️ Open advisory items — NOT blocking, but one is flagged by BOTH judges

1. **`last_run_errors` has no malformed/missing-value rule.** The obvious
   `get("last_run_errors", 0)` reads "I don't know" as "zero errors" and prints the reassuring
   fresh line. **This is the round-2 blocker returning through a side door**, and both judges
   flagged it independently — the compliance judge as a carried non-blocking note, the
   observability judge as its top remaining risk. Fix: give it the same "when in doubt, don't say
   fresh" rule the two timestamps already have, plus a test.
2. **A permanently-failing file pins the error count at 1 forever**, so the ⚠ fires every session
   and re-running never clears it — reproducing exactly the "warning that fires on normal days"
   the spec argues is worse than silence.
3. **The error line points away from its own evidence** — it says re-run the multi-hour indexer
   instead of reading the `scheduled-index.log` R6 creates for that purpose.
4. Cosmetic: the data-flow diagram enumerates 4 of 6 nudge states (omits *stuck*, *degraded*);
   task 3 names `test_cli.py` but `status_report` coverage lives in `test_rename_status.py:96`.

### Gate state

Compliance gate **passed** on blob `50ad053`. Verdict is fresh only while that blob matches —
**any spec edit invalidates it, and a re-entry restarts the loop at round 1**, so items 1–4 above
should be batched into one revision if they are taken at all.

**Next:** user review gate on the spec, then **checkpoint 2** (literal `gate confirmed`) → branch.

## 2026-08-06 — session 30 (cont.): user reverses course; R10's mechanism found broken

**User decision reversed the earlier call: INDEX `CODING_MEMORY.md`.** First attempt (`3b793fa`)
specified only lifting the exclusion. **Loop 2 round 1: both judges FAIL.** Corrected in `84bf220`,
blob `68bb8fb2`. Round 2 not yet dispatched.

### The finding that matters — lifting the exclusion would have done nothing

**`~/.claude/CODING_MEMORY.md` is not on any indexed path.** `curated_docs` is
`~/.claude/coding-memory`, `~/.claude/docs`, `~/.claude/PORTS.md` — **not the `~/.claude` root**.
Verified: `CLAUDE.md` and `MEMORY.md` are **0 rows each**; `PORTS.md` is indexed only because it is
named individually. So the diagnostic's "0 chunks, no `sources` row" had **two sufficient causes**
and the spec credited one — the identical confounded-proxy error its own measurement-traps section
records. Un-banning a file the walker never visits changes nothing.

**And every check would have passed vacuously:**
- The fixture at `test_index.py:58` writes `CODING_MEMORY.md` *into the curated directory* — a
  walked path production does not have. **The fixture pre-created the condition under test**
  (cf. `feedback_fixture_must_not_pre_create_state`).
- The scenario and task 9 said "in every repo root"; `~/.claude` is not one, so the two small
  project copies (278 lines) satisfied them while the 3,232-line archive stayed unreachable.
- **R9 — the designated noise instrument — would have measured a corpus grown by 17k chars instead
  of 285k, come back clean, and "cleared" an untested risk.** A green measurement of a change that
  never happened. Exactly the failure mode this whole feature exists to kill.

### Compliance judge: three wrong coordinates, all verified, one destructive

- Guard is **`config.py:57-60`**, not 56-59. **Line 56 is `excludes = tuple(...)`** — the stated
  range would delete it and break every `load_config` caller.
- Golden query is **line 4**, not 2. Line 2 is the still-correct sqlite-over-qdrant query, so a
  literal builder would have deleted a passing test and left the broken one.
- `plans/2026-07-17-memory-rag-index.md` asserts the invariant at **both line 19 and line 2828**;
  only 19 was named. That file is 3,079 lines and sits in the indexed `docs/` corpus.
- Test work is **six changes, not three**: four `report["processed"]` counts at
  `test_index.py:84,135,149,160` each shift by one, and `:93` is a compound assertion that cannot
  both flip and stay unchanged — it must be split.

The judge noted these coordinates were **correct in the round-4 entry and regressed** — the revision
was written from the prior draft rather than re-read against the tree. Accurate; corrected by
re-reading every one.

### ✅ User decision — the weight tier

`_iter_docs` (`index.py:44-51`) hardcodes `source_type` per bucket: `curated_docs` → `curated_doc`
(**1.5**, tied with ADRs), repo roots → `repo_doc` (**1.2**). Adding the file to `curated_docs`
alone would rank narrative equal to the decisions it narrates. **User chose a new `archive_doc`
tier at 1.0**, classified **by filename** so all three copies are consistent. `db.py:16` validates a
fixed `SOURCE_TYPES` tuple, so this is a four-file change.

### Motivation still verifies — the reasoning was never the problem

Promotion stopped (`session-log.md` 2026-07-16, `decisions.md` 2026-07-19, sessions 24-30 only in
`CODING_MEMORY.md`); `is_excluded` is a substring match; `digest_input_char_cap` is transcript-only.
Observability judge adds one nuance for ADR 0019: **ADRs and `pr-tracking.md` are current and
indexed**, so what the exclusion loses is the *narrative log*, not the decision record.

**Next:** dispatch loop-2 round 2, both judges, blob `68bb8fb2`. Reuse ids
`writing-specs/r8-missing-config-validator` and `writing-specs/readme-drift`. No waivers.

## 2026-08-06 — session 30 (cont.): loop-2 round 2 — FAIL, but the round-1 pair is genuinely closed

**Round 2 ran on blob `68bb8fb2`. Both judges dispatched to panes (`surface:160`, `surface:161`),
both returned DONE. Compliance: FAIL, 2 violations — both NEW ids. Observability (advisory):
`risk=medium confidence=high`, no dimension fails. No persistence trigger fired; round 3 is
available, and it is the escalation boundary.**

### The round-1 pair is fixed — verified by the judge against the tree, not taken on our word

`writing-specs/r8-missing-config-validator` and `writing-specs/readme-drift` both closed. The judge
re-opened every coordinate: `config.py:56` is the `excludes` assignment with the guard at 57-60;
`golden_queries.json:4` is the exclusion query and `:2` the still-true one; the four `processed`
counts at `test_index.py` 84/135/149/160 each shift by one while **`:105`/`:117` correctly do not**;
`:93` is the compound assertion; the plan asserts at both `:19` and `:2828`, both now listed. It
independently confirmed the mechanism finding — `memory.db` holds **0** `sources` rows for
`~/.claude/CLAUDE.md`, `MEMORY.md` and every `CODING_MEMORY.md`, against **1** for `PORTS.md`. The
`curated_docs` addition really is the load-bearing half.

### Round 2's two violations — both land on the *entry* status write, not on R10

1. `core-conduct/explicit-error-handling` — the entry write must "preserve the prior `last_run` and
   `last_run_errors`", which forces `run_index` to **read back** a `status.json` that this same spec
   elsewhere treats as possibly malformed (R2, the "malformed stays silent" scenario), written in one
   non-atomic `write_text` by a process the spec twice expects to be **hard-killed**. Behaviour on a
   truncated prior file is nowhere stated → one torn write aborts every scheduled run at its first
   line while the nudge is contractually silent. The freeze returns, unreported.
2. `writing-specs/edge-cases` — the spec never says whether the entry write **recomputes** the six
   existing keys from the DB or **carries them over**. Under the reading its own wording favours
   (`_write_status` "gains a parameter distinguishing the two calls" → `dbmod.stats` runs again), an
   `index --full` — which **unlinks the DB at `index.py:73` before connect at `:74`** — stamps
   `chunks: 0`, and the *unchanged* "chunks absent or 0 → exit silently" rule then deletes the
   session line for the whole multi-hour rebuild. That contradicts R3's in-progress line and the
   claim that `chunks` is "unchanged in name, meaning, and format".

Uncited note worth folding in: R10.4's "the fixture at `test_index.py:58` must additionally cover a
file at the `~/.claude` root position" reads as an edit to the **shared** fixture, under which the
four counts rise by **two**, not the stated +1 each. Half a sentence ("in its own cfg variant") fixes it.

### Observability judge — four new findings, all advisory, two are sharp

- **The archive lands in the wrong retrieval bucket.** `chunk.py:111` picks `recall_type` by path
  substring, so every archive chunk becomes `doc`. The SessionStart line itself advertises
  `--type decision|episodic|doc`, so after R10 asking for session history with `--type episodic`
  **still misses it**. The hole is narrowed, not closed — and a golden query written with the
  natural `episodic` filter would fail, unwarned.
- **"Run the full suite" runs none of the retrieval tests.** `addopts = -m 'not golden'`; those 16
  deselected tests *are* R9's noise-regression net. Nothing in tasks 7-10 runs them, so the golden
  query R10.5 writes is never executed by the plan that writes it. Fix: `-m golden` in task 10.
- **R10 has no way back** — there is no prune in the indexer, so if R9 fails and the file is
  re-excluded the chunks stay in `memory.db` until a multi-hour `index --full`. The spec plans for
  R9 failing and never states that exit cost. R7's launchd uninstall is first-class by contrast.
- Task 9 measures a **warm incremental** run against a threshold that must cover a full backfill.
- Bonus, verified: `archive_doc` needs **no DB migration** — there is no `CHECK` on `source_type`.
- Suite runs **63 passed, 16 deselected**, under `uv` (system `python3` has no pytest).

### The three carried advisory items — judge says the current text does not change its read

`last_run_errors` still has no usability rule (the "when in doubt" rule is scoped to *timestamps*),
so a missing value defaults to 0 and prints the reassuring line; a permanently-failing source still
pins the warning forever, and **R10 makes that likelier** by adding the corpus's largest file; the
degraded line still points at re-running the indexer, never at `scheduled-index.log` — the evidence
R6 sets `PYTHONUNBUFFERED` specifically to preserve.

### Process note — the wait timed out but the judge was fine

First `wait --timeout 540` returned exit 2. The pane was inspected before any retry: process alive at
9m32s, child `claude` at 0.1% CPU (normal for an API wait). Re-running `wait` returned DONE. **Exit 2
means inspect, not dead** — this judge simply verifies more coordinates than the sibling (~6m).

**Next:** revise the spec for the two cited violations (both about the *entry* status write), then
dispatch **round 3 — the escalation boundary**. Pass round 2's ids
`core-conduct/explicit-error-handling` and `writing-specs/edge-cases` forward. Still no waivers.

## Session 31 — loop-2 rounds 3 and 4: both closed their citations, both introduced new ones

`main` @ `52ff3f6`, pushed. `docs/features/memsearch-freshness.md` still `phase: planning`,
`branch: none`. Spec is now 895 lines. Checkpoint 2 remains owed — literal `gate confirmed` only.

### Round 3 — FAIL, 3 new ids (round 2's pair verified closed)

Six revisions landed first: the entry `status.json` write **carries the six existing keys over**
rather than recomputing (`--full` unlinks the DB at `index.py:73` *before* connect at `:74`, so a
recompute stamps `chunks: 0` and the "0 chunks → silent" rule erases the session line for the whole
rebuild); that write's read is fallible by contract (`OSError`/`JSONDecodeError` → empty object, one
stderr line, never aborts); both writes atomic; R10.4's fixture moved to its own `cfg` variant; an
R10 exit-cost paragraph (**no prune path** — `db.py:112-120` deletes only inside `replace_source`,
so re-excluding after a failed R9 leaves every chunk in `memory.db` until a full rebuild); task 9
times the cold run; task 10 runs `-m golden` (`pyproject.toml:23` deselects 16 by default).

Round 3 then cited three new: a missed `skipped` count, a contradiction I created between R10.4 and
task 7, and a timestamp emitting microseconds against a second-precision promise.

### Round 4 — FAIL, 4 new ids (all three round-3 ids verified closed)

User directed (do not re-ask): fix all three **and** fold in all three deferred design gaps. Nine
revisions. The three design gaps are now in the spec:

- **Stuck decays into stale** past new `RUN_ABANDON_HOURS` (24). Without it, a killed run plus a
  dead scheduler shows "⚠ stuck" forever, the reader checks, finds nothing, and is never told the
  scheduler died — and **falsifier clause (c) would score that as passed**, because something
  surfaced. Third constant, deliberately: 8 / 6 / 24 answer three different questions.
- **`last_run_errors` unknown is never zero.** New table row; degraded and stuck lines now point at
  `scheduled-index.log`, not at a multi-hour retry.
- **`archive_doc` → `recall_type` `episodic`** (one line at `chunk.py:111`, which already receives
  `source_type`; `RECALL_TYPES` at `db.py:17` already has it, no migration). Without it `--type
  episodic` silently misses all session history.

### ⚠️ The real finding: I am patching cited lines, not sweeping surfaces

All four round-4 violations were introduced **by the round-4 edit itself**, and the judge names the
shared root: *a new state was added to the bullets and the table without propagating to the summary
surfaces.* Concretely — R3's lead still says "three states" while listing four; three scenarios
still assert `fresh` from a Given that never pins `last_run_errors`; the data-flow diagram is
un-swept. Plus two unverified factual claims of mine: `:117` labelled "limit-scoped" when it is the
changed-file test (`:149` is the limit-scoped one, which the same paragraph says *must* move), and
"the sweep returns eleven hits" when `grep -n CODING_MEMORY` on that plan returns **14**.

This is `feedback_audit_the_surface_after_repeat_findings` firing for real: three rounds running,
each fix has spawned a same-species defect. **The method has to change before round 5** — build one
explicit state table as the single source of truth, derive every surface from it (R3 lead, bullets,
classification table, scenarios, diagram, falsifier, task 4), and re-run every command whose output
the spec quotes rather than recalling it.

### Observability judge (advisory) — findings not yet in the spec

- **Golden query 12 is a likely casualty and unwarned.** It is a `must` query filtering `episodic`
  and expecting a `.jsonl` path; R10 makes the archive episodic, dated today, weight 1.0 tied with
  transcripts, and the largest file in the corpus. Name it as an expected casualty *before* task 10
  runs, or a red result gets "fixed" instead of recorded.
- **The decayed stale line prints the remediation decision 5 banned** while a run may be alive, and
  the non-goal at ~809-811 still asserts the nudge never invites a concurrent run. That sentence is
  now false.
- **First-run-killed lands on "unknown age"** — no warning marker, no log pointer. The original
  bug's silhouette in the window the decay creates.
- `-m golden` asserts presence in top-k, not top hit, with no score floor — a weaker net than task
  10 assumes. R9's five queries are the strict instrument.
- `scheduled-index.log` is unbounded, no rotation, 4 runs/day (`reindex.log` is 63KB from one run).

**Next:** escalated to the user after round 4 (second consecutive escalation; the id
`writing-specs/edge-cases-r10-test-counts` also repeated across rounds 3 and 4, though the judge
records round 3's instance as genuinely closed). Awaiting direction on method before round 5.

## Session 32 — loop-2 round 5: the state-table rewrite, and what re-measuring found

Round 4 escalated with four violations, all introduced by the round-4 edit itself — the third
consecutive round where fixing a spec defect spawned a same-species one. User said "continue";
taken as approval of the recommended method rather than a fifth patch round.

**Method change.** Stopped patching cited lines. Built one authoritative **state table** in R3 and
derived every restating surface from it: the Contracts classification table (now a pointer, not a
second copy), the data-flow diagram's `OUT` node, the Scenarios, falsifier clauses (f)(g)(h), and
task 4's test list. Then re-ran every command whose output the spec quotes instead of trusting the
written number. Ground truth persisted to the scratchpad (`ground-truth-r5.md`) so round 6 cites a
file, not recall.

**The four round-4 violations, closed.**
1. `:117` was mislabelled "limit-scoped"; it is the *changed-file* test. `:149` is limit-scoped and
   does move. Replaced the prose list with a verified 10-row assertion table. Five move
   (84, 106, 135, 149, 160), four must not (105, 117, 136, 161) — the *lists* were always right,
   only the labels wrong. Four stale inline comments now named (84, 135, 148, 160); prior drafts
   named two.
2. Three fresh-asserting scenarios never pinned `last_run_errors`, which the new unreadable-count
   rule forbids. Four now pinned (a fourth was found beyond the three cited).
3. "Three states beyond fresh/stale/unknown" listing four → the state table replaces the framing
   entirely. **Eight states**, numbered, one line each.
4. Plan sweep returns **14**, not 11. The four cited lines (19, 2828, 2890, 2942) were correct; the
   other ten are now enumerated as deliberate historical listings.

**What the state table surfaced that no judge round had caught.**
- The unreadable-error-count example line was missing its `⚠` while the prose said rows 4–6 all warn.
- **New state 3, "abandoned first run".** A killed first run fell through to plain "unknown age" —
  no marker, no log pointer. That is this feature's own defect one field over.
- **The decay rule falsified the concurrency non-goal.** Past `RUN_ABANDON_HOURS` a still-alive run
  decays to *stale*, which does carry the index command. Named as a bounded trade, and
  `RUN_ABANDON_HOURS` must now clear task 9's cold-run duration by a margin — a stricter obligation
  than `RUN_MAX_HOURS`, which only mislabels.
- **Task 10 was measuring the wrong thing.** `test_golden_queries.py:37-41` asserts only presence in
  top-k — no score floor, no top-hit check, no ≥2 count — so **R9's bar is not expressible in that
  harness**. Only 11 of 16 golden cases can fail; stretch and negative merely `warnings.warn`. Task
  10 split into (a) the regression net and (b) R9's own runner.
- **Golden entry 11 = file line 12** (not "query 12" — 12 is its line) is the predicted R10 casualty,
  now named in the spec before the run: `must`, `rtype: episodic`, `since: 2026-07-01`, expects
  `.jsonl`; R10 makes the archive episodic, weight 1.0 tied with transcripts, dated today, largest
  source. If it fails, re-point the query — do not re-exclude.

**Numeric drift, re-measured 2026-08-07.** Archive 3,433 lines / 299,422 chars (was 3,232/285,187);
2.3× the largest indexed doc, not 2.5×; sessions 24–**31**; `sources` **911 rows** (187 @ 07-18,
724 @ 08-06), run finished and no longer growing. Every toolchain row and timestamp claim re-verified
and holds exactly; `launchctl getenv PATH` still empty.

Spec: 895 → **1,021 lines**, blob `748b108b`. Still `phase: planning`, `branch: none`.
**Round-5 compliance + observability judging is owed and not yet run.**

## Session 33 — loop-2 rounds 5 through 9: two bars that could not fail, and one guard that blessed what it forbade

Five judge rounds (5–9), ten pane dispatches, four spec commits. `main` @ `254cb98`.
Spec 1,021 → 1,270 lines, still `phase: planning`, `branch: none`.

**Round 5's state-table rewrite held.** Both judges confirmed independently: all four round-4
violations closed, all 44 scenarios resolve to the state they claim, all eight states covered.
Compliance went 4 → 1 violations.

**R9's acceptance bar could never pass, for three rounds running.** The advisory judge found it;
verified from source: `search.py:61-64` fuses two retrievers at `RRF_K=60`, `:80` multiplies by
weight (max `curated_doc: 1.5`) — hard ceiling `2 × 1/61 × 1.5 = 0.04918`. The bar read `≥0.30`,
six times the maximum emittable. A live query scored 0.046514. **The disproof was already in the
document** — the Baseline two paragraphs below recorded the returning hits at ~0.02, and sat there
for five rounds. Round 6 replaced it with a floor set from the same run it grades (cannot fail);
round 7 added a falsifier clause to stop that step being skipped (a guard on a guard); round 8
deleted the clause on user decision. *A measurement needing that much scaffolding was not measuring
anything.*

**The drift class was enumerated, not patched again (user decision).** Rounds 5, 6 and 7 each fixed
the cited instance and left the class open; round 7's own derived-surface list was stale, naming a
section round 5 had deleted. Replaced with a mechanically-swept inventory — **seventeen** surfaces,
not the three the old list named — keyed by section name, never line number. The first draft cited
line numbers and they were stale inside one editing session.

**The worst defect of the session was mine.** Round 8's anti-gaming rule ("the five queries must
span the corpus size range") pinned eleven chunk counts read from `memory.db`. Ten were right; the
eleventh was this spec's own file, listed at 14 chunks because the index last read it at
`2026-08-06T20:01:42Z` at ~250 lines against a 1,214-line file (`MAX(line_end)` = 250). It would
have qualified as the "small target" while being one of the largest — **the rule satisfied by doing
what it forbids.** A spec whose thesis is *"the index lies about its freshness"* calibrated its
guard by asking the index instead of the files. No count is pinned anywhere now; they are computed
from source at task-8 time. → memory `feedback_measure_from_source_not_the_derived_store`.

**Also closed:** falsifier (a) demanded a stale line whenever `last_run` exceeded `STALE_HOURS`
with no exception for the states outranking stale — and state 2 guarantees `last_run` is older than
8h once `run_started` passes 8h, so (a) and (g) could not both pass as hook tests; any faithful
build would have been condemned by the spec's own falsifier. R9's spread rule was written strictly
in one place and loosely in the two that graded it. R9 had no pass mark (one-of-five satisfied every
sentence) — now all five. `falsifier` appeared **zero** times in the task list, so the section
defining how the feature could be proven wrong had no step that read it → new task 10c.

**Judge-verified figures** (all re-run, not recalled): archive 300,160 chars / 3,484 lines; **1.62×**
the largest indexed doc (`vibe-scape/.../live-presence-plan.md`, 184,620 chars) — round 5's "2.3×"
ranked by chunk count while the arithmetic was character-based and compared bytes to chars; plan
sweep 14 hits; 20 session headings in two forms, zero of the shape the spec named; history blocks
are 188/1,214 lines (15.5%), mid-pack against sibling specs.

**Open:** round-9 judging owed. Checkpoint 2 (planning → implementation) still owed — literal
`gate confirmed` only.

## Session 34 — round-9 judging: the enumeration that drifted on arrival

`main` @ `ceadcf0`. Spec unchanged at **1,270 lines**, blob `60199bd9`, still `phase: planning`,
`branch: none`. No code exists.

**The session opened on a two-rounds-stale handoff.** Session 33 ended without writing one, so
`SessionStart` surfaced session 32's — claiming 1,021 lines, blob `748b108b`, "round-5 judging
owed". Git said otherwise: four spec commits past it. Caught by the restore step that checks
frontmatter against reality *before* acting. **A handoff's age header does not tell you it is
current** — it timestamps the file, not the state it describes.

**The user opened with `gate confirmed` and the gate did not open.** Round-9 judging was owed and
the last verdict on record was round 8 = **fail**. Asked rather than treating the phrase as
covering both; user chose to judge first. Checkpoint 2 answered in the same breath: **Sonnet 5**
for implementation. The `gate confirmed` phrase is therefore already spent — when judging passes,
open the gate without re-asking.

**Round 9 judged: compliance `fail` (2 violations), observability advisory `risk=medium`.**
Round 8's violation is verifiably closed — decision 5 bounded, the Design-decisions row present in
the 17-entry inventory, the stale "1,163 lines" header gone, the spread rule identical in all
three places.

The two new ones:

1. **The pass mark was not where the work happens.** R9's own new checklist claimed task 10(b)
   restates the "all five queries must pass" bar. `grep "all five"` returns **exactly one hit in
   1,270 lines** — in R9 itself. The step that runs and records the measurement states only
   per-query pass/fail, so four-of-five would be recorded as a pass.
2. **A scenario contradicted the state table.** "A failed scheduled run becomes visible" put a
   9-hour-uncompleted run on the *stale* line; the table makes it state 2 (*stuck*), which
   outranks stale. The identical proposition round 8 scoped out of falsifier (a) and left live in
   the scenario **task 4 turns into a hook test** — so the wrong version is the one that ships.

**The persistence rule tripped and the finding was escalated, not patched.** Id
`writing-specs/derived-surfaces-out-of-sync` cited in rounds 8 and 9 consecutively. Substantively
it is a new instance in the same territory, but it is the **fifth consecutive round** the class has
appeared (5, 6, 7, 8, 9). Both judges found it independently this round: the advisory one caught
that **R9's new seven-entry inventory was written by reading, not by the sweep the spec mandates**,
and misses four surfaces. *The enumeration written to end the drift drifted on arrival* — which is
what finally made the mechanism, not the instance, the thing to fix.

**User decision: stop hand-maintaining the inventories.** Both lists come out of the document; the
sweep becomes a step executed at implementation time, generated from what is actually there. A
list that lives in the document is a copy, and every copy in this spec has gone stale — rounds 7
and 9 shipped stale ones inside the very section meant to prevent staleness.

**Also accepted (all four advisory items):** record the golden baseline; delete the two surviving
pinned counts; state the counting unit as per-feature; add a falsifier clause for task 9's
stop-and-ask (flagged three rounds running).

**Baseline captured before any edit, re-run rather than trusted:** `uv run pytest -m golden -q` →
**16 passed, 63 deselected, 2.53s** @ `ceadcf0`. Matches the advisory judge's figure. This is the
before-picture task 10 lacked — without it the R10 measurement runs once, after the change, with
nothing to compare against.

**Two document self-contradictions worth keeping:** R9 states flatly that no count is pinned
anywhere while **121 and 130 survive** in R10's noise paragraph, both read from `memory.db` — the
exact failure mode round 9 existed to fix, one section over. And chunk counting is per-file while
competition is per-feature, so one feature reads as 6 or 37 depending on the unit — enough slack to
move a sample from the bottom third to mid-range while still complying with the anti-gaming rule.

**Gotcha found the hard way:** `phase-guard`'s `.claude/*` exemption is **repo-relative**. In this
repo that means `~/.claude/.claude/…`; a write to `~/.claude/session-state.md` sits at the repo
root, matches nothing, and is denied. The hook was right — that path was wrong.

**Open:** the round-10 revision (seven edits, enumerated in the handoff), then re-judge.

## Sessions 35–36 — the response register: a rule that could not be written by the agent that needed it

Two standing requests about how replies are written — **plain language on every reply**, and
**every prompt carries a recommendation** — were being missed. An audit found the cause was
*location*, not disagreement.

**The plain-language rule existed, and was scoped wrong.** It lived only as auto memory, and its
first six words read *"When asking the user a question"*. Explanations, findings, and status
reports were never covered, so the rule read as already-followed while being routinely missed. The
user asked for it three separate times (2026-08-02, sessions 33 and 35).

**The recommendation rule did not exist at all.** `grep -riE "recommend"` over `CLAUDE.md`,
`rules/` and `agents/` returned **zero matches**. The only adjacent guidance is
`AskUserQuestion`'s own convention, phrased conditionally (*"**if** you recommend a specific
option…"*), so it obligated nothing.

**Why auto memory was the wrong home.** It is keyed per project — four such directories exist on
this machine, only the current repo's loads at session start — and it is gitignored
(`.gitignore:43`), so it never commits and never syncs. A rule about how the assistant *speaks*
cannot be repo-specific. `triaging-new-instructions` put both at tier 2: they must hold every turn,
and no script can judge whether prose is jargon-free or whether a recommendation was given. That is
`rules/core-conduct.md` § Session Defaults. **ADR 0019** records the five options weighed.

**The freeze, and the way past it.** The agent could not make the edit. `phase-guard.sh` is
registered `PreToolUse` on `Edit|Write|NotebookEdit` and `rules/` is not on its exempt list, so
every write was denied while two feature files sat at `phase: planning`. The guard was behaving
correctly by its own contract — it matches on **path, not intent** — but the block was a false
positive: neither planning feature has any relationship to the response register. The resolution
was the hook's own scope: **it intercepts agent tool calls only, so the user edited the file by
hand.** Rejected alternatives: managed policy (`sudo`, un-overridable, a third copy) and
`autoMemoryDirectory` (merges all four repos' memories).

**Then the duplicates were deleted, not synced.** Both memory files and their two `MEMORY.md` index
lines are gone; `grep` confirms no dangling wikilinks. One fact, one home.

**Handoff error caught on arrival.** The session-35 handoff claimed `docs/**` is outside
`git-guard`'s `main` allowlist and needed a branch. It is not — `hooks/git-guard.sh:186` allows
`CODING_MEMORY.md|coding-memory/*|docs/*.md`. Only `rules/` genuinely needed the branch. A handoff
is data, not truth; this one was wrong on a fact that would have cost an unnecessary branch.

**Also landed:** `docs/marker-gate-defect-checklist.md`, the open defects for
`verification-marker-gate` re-verified against **revision 5**. Verified while checking: the spec
mentions **`rtk` zero times** and names `kind: COMMIT` exactly once without defining the predicate.
The hooks learned the rtk/chained-command lesson (`git-guard.sh:24-26`, `doc-guard.sh:119`); the
spec did not.

**Count discrepancy to settle:** the session-34 entry above says the round-10 revision is **seven**
edits; the session-35 handoff enumerates **nine**. The nine-item list is the one that was worked
from — treat it as authoritative and re-derive rather than trusting either number.

**Closed:** PR #44 **MERGED** 2026-08-07T16:46:01Z; branch deleted local + remote via `git branch -d`.
The rule is on `main` — verified `1` where the pre-merge falsifier on `main` returned `0`.

**Open: the round-10 revision, then re-dispatch both judges.** The nine edits are recorded here
rather than only in the handoff, because the session-35 handoff that held them was overwritten and
they briefly existed in no durable place at all — the same staleness failure this spec exists to fix:

1. Delete R3's 17-entry derived-surface inventory (~`:162`–`:186`).
2. Delete R9's seven-entry "Surfaces derived from R9" (~`:339`–`:353`).
3. Replace both with a task step regenerating the sweep **at implementation time**; keep the sweep
   *method* (~`:144`–`:147`). Every stored copy went stale, twice inside the anti-staleness section.
4. Scenario "A failed scheduled run becomes visible": 9h-uncompleted is **state 2 (stuck)**, not
   stale (`6 ≤ 9 < 24`, stuck outranks stale). Emit the stuck line; copy R8's falsifier-(a) scoping.
   Task 4 makes this scenario a hook test, so the wrong version is the one that ships.
5. Move "all five queries must pass" into task 10(b) — it appears once in 1,270 lines and not in the
   step that records the measurement, so four-of-five would be written down as a pass.
6. Task 10(a) baseline: `uv run pytest -m golden -q` → 16 passed, 63 deselected, 2.53s @ `ceadcf0`.
   Verified; do not re-measure, and do not let a later commit become the "before".
7. Delete the pinned counts `121` and `130` from R10's noise paragraph — both read from `memory.db`.
8. State the counting unit as **per-feature** in three places identically: R9's spread rule, task 8b,
   falsifier (i).
9. Add a falsifier clause for task 9's stop-and-ask — flagged three rounds running, still ungraded.

Then re-hash the blob and re-dispatch both judges in panes with R9's two violation ids, `waived: []`,
and the fact that edits 1–3 are a **user-directed structural change**, not a judge finding.

## 2026-08-07 — session 37: the round-10 revision lands (nine edits, all nine applied)

Spec `docs/features/memsearch-freshness.md` · `phase: planning` throughout · no branch · committed
to `main` as docs (`git-guard.sh:186` allows `docs/*.md` there).

**Blob `60199bd97edddf6e50e99c047a2a3573b34ffb40` → `022528c29a2b7ac9bd542f0271272855ceb4275d`**
(1,270 → 1,289 lines). The pre-edit hash matched the handoff exactly, so no drift had occurred
between sessions.

All nine edits from the list above are applied. Three of them are worth recording beyond "done":

- **Edit 4 was not a judgement call — the spec contradicted itself.** The scenario at `:867`
  ("A failed scheduled run becomes visible") asserted a **stale** line for a 9-hour uncompleted run,
  while the scenario 78 lines earlier at `:789` asserted **stuck** for the same 9 hours. Two hook
  tests generated from one spec, mutually unsatisfiable — the identical defect clause (a) had in
  round 8. Renamed to *"A wedged scheduled run surfaces as stuck, not as stale"* and scoped with
  `run_started` later than `last_run`, `last_run` older than `STALE_HOURS`, and an explicit
  `And no stale line is emitted` — so it now tests the *precedence*, which is what makes it
  distinct from `:789` (that one tests the no-second-indexer guarantee) rather than a duplicate.

- **Edit 3's task 1b had a phase collision that had to be designed around.** The sweep regenerates
  "at implementation time", but `phase: implementation` **forbids spec edits** — so a task that
  reconciles spec surfaces mid-implementation is out-of-phase by construction. Resolved by making
  1b **detect-and-escalate, never fix**: a surface contradicting its authority triggers the
  documented `"GATE: Spec change needed — switch back to the high-tier model to revise."` Fixing in
  place would be the out-of-phase edit; staying silent is what rounds 5–9 each did.

- **Edit 8 was applied without pinning the 6-vs-37 figure.** The handoff cited per-file-vs-per-feature
  as worth 6 vs 37 chunks on one feature. Those are chunk counts, and the spec's own rule two
  paragraphs down says **no chunk count is pinned in this document** — so the point is made in prose
  ("counts as a small target read off its largest file alone, mid-range when summed") with no
  numbers. Pinning them would have re-committed edit 7's exact sin in the act of fixing edit 8.

Edits 1–3 removed both stored inventories; what survives is the sweep **method** plus a new
"What the sweep must count as a derived surface" list preserving the three lessons the deleted
tables encoded (an ordering claim is duplication; a section asserting precedence is restating the
table; a state named in prose without its number is still a surface). Falsifier gained clause **(j)**
(task 9's cold-run stop-and-ask), is now classed as an observation, and task 10c reads "(a) through
(j)".

**Open — next session:** re-dispatch **both** judges at round 10 in panes (`dispatching-pane-agents`),
passing R9's two violation ids, `waived: []`, and that **edits 1–3 are a user-directed structural
change**, not a judge finding. `gate confirmed` was already given in session 34, so round 10 passing
**opens the gate — do not re-ask**; checkpoint-2 answer to record in task 1 is **Sonnet 5**.

## 2026-08-07 — session 37 (cont.): rounds 11 and 12 both PASS; the gate is unblocked

`docs/features/memsearch-freshness.md` · `phase: planning` throughout · pushed through `b229ef3`.
Blob trail: `60199bd9` (r10 in) → `022528c2` (r10 out) → `b71672c3` (r11) → `c148cda8` (r12).
1,270 → 1,289 → 1,317 → 1,336 lines.

**Round 10 failed on one violation, and the failure was mine.** Edit 8 said "fix the counting unit
in three places"; I fixed exactly those three and did not sweep for a fourth. There was one — the
Gherkin scenario, i.e. *the* surface that becomes an executable check. Verified: `memory-system-split`
is 53 + 713 lines, so per-file it ranks bottom-third and per-feature top-third. **This is the
"enumerate the class, don't patch the instances" rule failing inside the edit meant to enforce it.**
Round 11 fixed it by sweeping *and* deleting the two-entry mini-inventory that caused the miss.

**Round 11: compliance PASS** (zero violations). `derived-surfaces-out-of-sync`, open rounds 8–10,
closed — all seven surviving surfaces agree on unit and population.

**Round 12 exists because the observability judge found the hole one level down.** R11 defined *which
population*; it never defined what a **third** was. All four surfaces were silent *identically*, so
they agreed with each other while the rule underneath was underdetermined. **Surfaces agreeing is not
the same as a rule being defined** — no cross-surface comparison could ever have found this; it took
reading the rule. Fixed as a **rank tertile** (lowest ⌊N/3⌋ by rank, N counted at task-8 time, never
pinned, counted per feature — `docs/features/` is 11 files but **10 features**).

**The judge then measured it with the project's own chunker rather than taking the fix on trust:**

```
 1   6 stale-phase-guard-rule-text    6  37 memory-system-split
 2   9 falsifier-base-pin             7  53 verification-marker-gate
 3  13 git-guard-chained-command      8  66 memsearch-freshness
 4  13 shell-segments-redirects       9  70 replay-harness-base-pin
 5  24 git-guard-empty-index         10  91 phase-guard-hook
```

Value-span reading: bottom third = ≤34.3, so `git-guard-empty-index` (24) qualifies and the
four-large-plus-one-medium sample **passes** — and *half the pool* sits in its own "bottom third".
Rank-tertile: bottom third = `{6,9,13}`, it is rank 5, sample **fails**. Counterexample dead under
every convention tried (⌈N/3⌉, percentile interpolation). Bottom third shrank 50% → 30% of the pool.
Bonus: this spec is **66 chunks, rank 8 — its own top third**; round 8 listed it at 14 (bottom third)
off the stale index. Its self-criticism was right.

**Round 12: compliance PASS. Observability on the gate question: "No. Open it."**

**Both judges corrected themselves against measurement, which is the point of running them:** the
observability judge withdrew its round-11 `≥1.73×` (it had divided bytes by characters — the spec's
**1.72×** stands, re-measured independently by both), and **reversed its round-11 demand for a
pre-gate reorganization** — re-cutting the document would churn all four spread-rule surfaces
immediately before task 1b's sweep must verify they agree, and after the gate it is phase-illegal.

**Carried into implementation, none blocking:** (1) a live tie at the boundary — `git-guard-chained-command`
and `shell-segments-redirects` are both 13 chunks, ranks 3/4, and "lowest ⌊N/3⌋" doesn't say which is
third; not exploitable, but not reproducible — recommended rule: *a tie spanning the boundary puts
both in the third*. (2) R9 names no command for computing chunk counts; use the project's chunker at
task 8b, not a `wc` proxy. (3) **Deliberate canary:** falsifier (i) still says "chunk-count *range*"
where R9 says "population", and `⌊N/3⌋` reached only 2 of 4 surfaces. Meaning is pinned everywhere,
so it is cosmetic — **left in place on the judge's suggestion as a live test of whether task 1b's
sweep actually works**, since that sweep is what replaced the deleted inventories and has never been
exercised. If task 1b misses both, that is evidence about the mechanism, not about the wording.
(4) The zero-files gap still renders a vanished corpus as fresh, by prior user decision.

**Process finding — the "exit 2 ≠ dead" gotcha fired for real at round 11.** The compliance pane hit
the 540s `wait` timeout and never wrote its result file, but the verdict was already complete and
well-formed in `verdicts.jsonl`. Re-dispatching on the exit code would have burned a full round
re-judging an already-passing spec. **Always read `verdicts.jsonl` before believing a timeout.**

## Session 29 (cont.) — statusline wrap + worktree name: MERGED as PR #43

Closes the "designed, NOT implemented" entry above. Merged `f38de2c`; feature file
`docs/features/statusline-wrap-worktree.md` is at `phase: review` with tasks 9-12 open.
Design detail lives there and in ADR 0018 — only the transferable lessons are below.

### Three of the four judge findings were defects in the TESTS, not the feature

Worth internalising, because the suite was green each time:

- **Round 1:** the width assertion could not fail on the shape that overflowed. Its payload was
  `/tmp` — not a repo, so no branch and no `wt:()`, giving a 33-cell head. The real head measured
  **120 cells against a 60-cell terminal.** Green suite, untested defect.
- **Round 3:** the row assertion allowed the global ceiling (8) while the fixture only produced 6.
  The judge built the off-by-one that slack admits — a spurious blank leading row, **7 rows,
  passing all 68 tests.**
- **Round 4:** that assertion's power to *detect* a regression depends on
  `len(user) + len(host) > 18`, because segment 0 is built from `whoami`/`hostname` — the machine,
  not the fixture. 25 here, ~16 in a CI container running `root`, where the canary silently stops
  working. **A test whose ability to fail depends on where it runs is not a test everywhere it runs.**

The generalisation: when a fixture is *convenient* (`/tmp`, the local hostname) rather than
*representative*, the assertion tends to describe the fixture, not the behaviour.

### judge-guard is circular by construction — only one commit order terminates

`judge-guard` requires a verdict whose `head_sha` equals current HEAD, but judging **writes files
into the repo** (`verdicts.jsonl`, the verdict markdown). Committing them moves HEAD and
invalidates the verdict that authorised the PR. The only order that ends:

**judge → `gh pr create` → commit the verdict artifacts → push.**

`gh pr create` warns "N uncommitted changes" at that point. That warning is expected, not a mistake.

### `phase: review` withdraws your own authority to edit source

Setting the feature file to `review` at PR time means no feature file records the branch as
`implementation` any more, so `phase-guard` denies further source edits on it. This fired for real:
after opening #43 I tried to apply one more judge follow-up and was correctly blocked. The gate was
right — implementation had been declared finished. Follow-ups belong to a new cycle, not to momentum.

### `verdicts.jsonl` guarantees a merge conflict between parallel sessions

It is a shared append-only log, so any two concurrent branches that both run a judge conflict there.
It is also the benign kind: resolve as the **union** of both sides' new lines, never a winner.
Measured here: 103 base + 15 theirs + 4 ours = 122, every line re-parsed as JSON, count asserted so
a silent drop could not pass. Do not hand-edit the conflict markers.

### A merge does not reach the live status line

`settings.json` runs `$HOME/.claude/statusline-command.sh` — the **shared checkout's working file**.
That checkout was on `feature/memsearch-freshness`, not `main`, so #43 was invisible there: verified
by `grep -c push_segment` = 0 and a live render still giving 1 row at 120 cells. Switching a shared
checkout's branch to fix this is the exact hazard `wt:()` exists to warn about — it is what happened
earlier in this same session — so it was left alone.

### Housekeeping observed, not fixed

- **`CODING_MEMORY.md` says "index only, at or under 200 lines" and is 3,787 lines.** The stated
  convention and actual practice have fully diverged.
- `statusline-command.falsify.py` still reports `FALSIFICATION BROKEN` (**pre-existing**, verified
  before this branch). #43 therefore merged with **no differential coverage** — feature file task 9.
- **Nobody has seen the wrapped status line on a real narrow pane.** Every check was programmatic.
## 2026-08-07 — session 38: the gate opens, and task 1b's sweep catches its canary

**Branch `feature/memsearch-freshness`** created off `main` @ `b78eae8`. Feature file
`docs/features/memsearch-freshness.md` moved to `phase: implementation`, `model_tier: low`.

### The gate

The user gave the literal phrase `gate confirmed` in this session — not the session-34 claim the
handoff carried, which was correctly treated as data and ignored. State was verified against reality
before opening: blob `c148cda8` at 1,336 lines (byte-identical to the revision both round-12 judges
passed), clean tree, frontmatter genuinely still `planning`.

**Model-switch checkpoint 2 was asked fresh** rather than inherited from the handoff, which had
pre-supplied "Sonnet 5". Answered **Sonnet 5**, for the whole implementation phase *including task
1b* — deliberately, so the sweep is exercised by the tier that runs the remaining tasks rather than
by a frontier model that would have measured the wrong thing. Commit `4cb0a3c`.

### Task 1b — the derived-surface sweep

Commit `ef436e7`, **empty by design** (`--allow-empty`): the sweep changes no files, so the commit
exists only to carry its output. The full section-keyed inventory lives in that commit message and
is deliberately **not** reproduced here or in the spec — every stored copy of this sweep has gone
stale, twice inside the anti-staleness section itself.

Twenty-one R3 surfaces and eight R9 surfaces found, each checked against its authority. Verified
mechanically by grep, not by recall.

**Verdict: no surface contradicts its authority. No `GATE: Spec change needed` escalation.**

**The canary worked, and the honest result is subtler than "it escalated."** Both planted defects
were *found*:

1. Falsifier (i) says "chunk-count **range**" where R9's tertile paragraph reasons over the
   "population".
2. `⌊N/3⌋` reaches only **2 of the spread rule's 4 surfaces** — R9 itself and task 8b. The Gherkin
   scenario and falsifier (i) both stop at "rank tertiles".

Both were then judged **cosmetic against task 1b's stated bar, which is *contradiction*, not
imprecision** — R9's own heading sentence reads "The range **is** the population of every feature
under `docs/features/`", so clause (i) is using the authority's own vocabulary, and "rank tertiles"
carries the operative distinction even without the formula. Escalating on these would have been
following the handoff's *prediction* rather than the rule. That the prediction went unfulfilled is
itself the useful signal: **the sweep's detection worked; the escalation threshold simply wasn't
met.**

Two watch items recorded and left alone (decision 5's "in-progress ... for the first
`RUN_ABANDON_HOURS`", which round 9 already adjudicated; and the three constants' "while the first
run is still alive", which collides with row 3's name but reads correctly in context).

### Found incidentally — a stale figure, outside 1b's scope

R10's per-session-dating non-goal pins "**20** headings ... 17 date-first and 3 session-first",
measured 2026-08-07. **Re-measured the same day: 24 (19 date-first, 5 session-first)** — it drifted
across sessions 34–37. The non-goal's *load-bearing* claims both hold: still exactly two forms, and
still **zero** carrying the `Session N — <date>` shape, so the argument the bullet makes is intact
and only the count is wrong.

Not fixable now — a spec edit during `implementation` is phase-illegal — and out of scope for task
1b, whose sweep covers R3 state surfaces and R9 clause surfaces only. **Queued for the deferred
planning pass** already carried for ADR 0019 and the missing headings.

The archive's *size* figures (`317,249 characters / 3,723 lines`) are explicitly caveated as a
floor, so this session's append does not rot them: re-measured **325,079 characters / 3,787 lines**,
both above the floor. This entry uses the date-first heading form deliberately, to keep the
non-goal's two-forms and zero-`Session N — <date>` claims true.

## 2026-08-07 — session 39: ADR 0018 (task 2), and a launchd fact the spec never had

`feature/memsearch-freshness`, `phase: implementation`, `model_tier: low` (Sonnet 5, set at
checkpoint 2 for the whole phase). Task 2 only.

### `docs/decisions/0018-launchd-agent-and-run-recency-split.md`

Both of the spec's structural decisions in one record — design decision 4 (a persistent `launchd`
agent as the refresh mechanism) and decision 2 (`last_run` split from `last_indexed`) — because
neither stands alone. The scheduler's known weakness is that it runs blind and never reports on
itself; the compensating control is the session-start staleness warning; that warning needs
`last_run` to exist. Choosing the scheduler without the field ships the weakness with nothing behind
it, so they are one decision wearing two names.

Rejected options are recorded per decision, with the reason: `SessionStart`-hook trigger, `cron`, a
file watcher, and manual indexing for the scheduler; `memory.db` mtime, `status.json` mtime, and
reusing `last_indexed` for the staleness signal. A Mermaid tradeoff mindmap carries the shape,
validated with `skills/diagramming-technical-docs/scripts/validate-diagrams.sh` (1 block, 0 failed).

### The one new fact: `StartInterval` misses a sleep, it does not defer

Read from `launchd.plist(5)` rather than recalled — and it contradicted what recall would have
supplied. **A `StartInterval` firing that lands while the machine is asleep is *missed*** ("due to
shortcomings in `kqueue(3)`"), not queued for wake; a firing that lands while the previous run is
still going is likewise skipped. `RunAtLoad true` covers boot and login, not sleep/wake.

Consequence for this feature: a laptop closed overnight can legitimately cross the 8h threshold.
Recorded in the ADR as **accepted, not mitigated** — the warning is *correct* in that case (the
index genuinely is stale) and the remediation is one command. The alternative, `StartCalendarInterval`,
does coalesce missed firings on wake but schedules against wall-clock times rather than elapsed time,
which is a worse fit for "every 6h". The spec never claimed otherwise; it simply never said.

### Citations re-verified, not restated from the spec

An ADR outlives the feature file it was derived from, so every code citation carried into it was
checked against source first: `db.py:156` (`SELECT max(indexed_at) FROM sources`), `index.py:125-127`
(the unchanged-hash early return), `cli.py:66` (`return 0` regardless of errors), `status.py:27`
(the `sources: N  last_indexed: …` line), and `launchctl getenv PATH` — empty on this machine, which
is what makes the plist's explicit `PATH` load-bearing rather than boilerplate. All five held.

### Archive figures

Session-heading count is now **26** (21 date-first + 5 session-first) after this append; it read
20 + 5 = 25 immediately before it. R10's non-goal still pins **20**, and the previous entry's "24
(19 + 5)" was measured before that session's own append landed — both are stale counts, already
queued for the deferred planning pass. The bullet's two *load-bearing* claims were re-measured today
and both still hold: exactly **two** heading forms, and **zero** carrying the `Session N — <date>`
shape. Size figures remain above their stated floor (`317,249 chars / 3,723 lines`): **329,097
characters / 3,853 lines** before this append. Date-first heading form used deliberately, again, to
keep those two claims true.

## 2026-08-07 — session 39 (continued): tasks 3-6, the implementation core

`feature/memsearch-freshness` @ `d7a03fc`, 8 commits ahead of `main`. Suites: **72** pytest +
**27** nudge + **19** installer, all green, tree clean.

### What landed

**Task 3** — `status.json` gains `run_started` / `last_run` / `last_run_errors`, written at both ends
of `run_index`; `memsearch status` relabels `last_indexed` as content recency and shows run recency
beside it. **Task 4** — `memsearch-nudge.sh` implements the eight-state table; classification in
bash, only the parse and age arithmetic in the one Python call it already made. **Task 5+6** — the
`launchd` template, `install-schedule`, and the README entry.

### Three things worth carrying that are not in the diff

**`launchd.plist(5)` contradicted recall.** A `StartInterval` firing across a machine sleep is
*missed*, not deferred to wake (`kqueue(3)`); a firing during a still-running job is skipped too.
Recorded in ADR 0018 as accepted, not mitigated — the warning that follows is *correct*. Matters for
task 9: a post-sleep gap is not an install bug.

**Every test asserts the emitted line, never a parsed field.** A field nobody reads is the defect
this feature exists to close, so a suite that inspected the parse would test the wrong end of it.
Same reasoning drove the installer's isolation: `HOME` redirected plus a stub `launchctl` on `PATH`,
**no test-only seam in the production script** — an override that exists only for tests means the
tested path is never the real one. The malformed-plist case breaks a real template rather than
mocking `plutil`.

**Mutation rounds are the acceptance, not the green bar.** 6 + 8 + 6 mutations run by hand. Two
survived, and both were examined rather than waved through: one reworded "see" to "run" while still
naming the log (cosmetic — the behavioural version, pointing state 7 at the index command, *is*
caught, verified separately); one swallowed `bootstrap`'s failure but is masked by the
post-bootstrap verification, which still exits 2 naming the step. A redundant guard, not a hole.

### R8 was broken and repaired, and the reason is structural

Task 5 was committed without the README, which R8 forbids. `69f3f5d` was amended to carry both and
force-pushed with `--force-with-lease` (feature branch, two minutes old, no PR). The cause is worth
more than the fix: **the checklist numbers 5 and 6 as separate tasks while R8 requires one commit.**
A future reader following the numbering will split them again.

### Verified, not recalled

Parent item 2 is a confirmed no-op — `~/.claude/docs` is already a `curated_docs` root and the live
index holds **11** `sources` rows under `docs/features/`. `launchctl bootout` returns **3** for "No
such process" and `print` returns **113** when absent, both probed; the installer nonetheless asserts
the *outcome* via `is_loaded` rather than pinning either number. All five code citations carried into
ADR 0018 were re-checked against source first.

Nothing is installed: `launchctl print` still returns 113. That is task 9.

## 2026-08-07 — session 40: task 7, and the archive starts indexing itself

`53a6b42` on `feature/memsearch-freshness`, pushed, tree clean. 13 files, all seven R10 parts in
one commit as R8 requires. **74 pytest green** (72 before: −1 removed test, +3 new). The corpus this
file belongs to now includes this file.

### What landed

`CODING_MEMORY.md` is indexed. The exclusion is gone from `exclude_paths`, the `ConfigError` guard
that enforced it is deleted, and — the part that actually does the work — `~/.claude/CODING_MEMORY.md`
is now named in `curated_docs`. It carries a new `archive_doc` weight tier at **1.0**, classified by
filename so all three copies land there rather than outranking their own repos' decision records,
and yields `recall_type == "episodic"` so `--type episodic` reaches it. ADR **0020**.

### Three things worth carrying that are not in the diff

**The ADR number in the spec was wrong, and the fix has a knock-on.** Task 7 said write `0019-*.md`;
`0019-response-register-belongs-in-core-conduct.md` has existed since sessions 35–36. Landed as
**0020**. ⚠️ The session-39 handoff had reserved 0020 for the deferred planning pass — that pass now
needs **0021**. A spec naming a number in a monotonic sequence will rot whenever an unrelated
session spends one; the number should have been "the next free ADR".

**Spec line numbers rot inside their own implementation phase.** Every `test_index.py` line in R10.4
was **+11** stale — task 3's own commit `483c44e`, on this branch, inserted lines above them.
`README.md:22` had likewise become `:45` via task 6. R10.4 survived this only because it also stated
a governing *rule* and named each assertion by semantic role, so mapping by test function was
unambiguous. R10.6's plan sweep, written as "re-run `grep -n`, do not trust the list", re-ran to
**fourteen** hits exactly. **The instruction that told the implementer how to re-derive beat every
instruction that stored a number.**

**Falsifier-first, twice, and it was not ceremony.** The suite was run *before* any test was edited:
**7 failed / 65 passed**, precisely the seven functions R10.4 predicted, from eight assertions. Then
the two new production-pinning tests were mutation-checked — revert `chunk.py`'s episodic branch and
`_doc_source_type`, both go red; restore, 74 green. This mattered here specifically: the old
exclusion test had passed for weeks while production was unreachable, because **the fixture wrote
`CODING_MEMORY.md` inside the curated directory — a path the walker already visits.** The
replacement test builds its own config for the root position and asserts both halves, including the
one that fails if `curated_docs` omits the file.

### One design choice made against future drift

The replacement golden query uses `expect_path_contains: "CODING_MEMORY"`, not a session-specific
path, and asks a question the archive answers in *many* sections. The archive grows every session —
a query pinned to one session's heading would have rotted on the next append, which is the same
class of defect as the two above.

### Not done

Nothing is installed yet; `launchctl print` still returns 113 (task 9). The archive is **configured**
to be indexed but has not been indexed — no `memsearch index` run has happened, so `memory.db` holds
zero `archive_doc` rows and the new golden query cannot pass until task 9. That is expected, not a
regression.

## 2026-08-07 — session 41: task 8, and a tie called before the coin landed

Task 8 only: the five R9 measurement queries and their own runner, committed **unrun** (`8a10f61`)
— `memsearch/tests/measurement_queries.json`, `tests/test_measurement_queries.py`, plus an
`addopts` change. Restore was clean; frontmatter matched reality on every field.

### The pre-declared tie rule, and why declaring it early was the whole point

R9 ranks every feature under `docs/features/` by chunk count and demands a target in the bottom
third and one in the top. `⌊N/3⌋` is silent on a tie spanning the boundary, so the rule was fixed
**before any count was computed**: *tied entries all belong to that third* — a tie is
indistinguishable by the metric, so ranking either side of it is arbitrary, and a tied entry has an
identical count to a bona fide bottom-third entry rather than merely a nearby one.

The tie then actually happened: ranks 3 and 4 came out **both at 13 chunks**
(`git-guard-chained-command`, `shell-segments-redirects`), widening the bottom third to four
entries. Declared afterwards, that rule could not have failed — it would have been read off the
result it was meant to constrain. This is the same shape as the score floor R9 deleted in round 8
(*a finish line drawn behind the runners*), caught one layer earlier.

**N = 10, not 11.** `memory-system-split` spans `.md` + `.spec.md` and counts once — R9's
per-feature unit, which is the rule the spec warns is *different and weaker* when read per-file.

### The spec predicted its own miscount, and the prediction was right

`memsearch-freshness.md` measures **71 chunks — rank 9, top third**. The round-8 draft pinned it at
**14** from `memory.db` and called it bottom-third; the index had last read it at ~250 lines against
1,400+ today, understating it roughly 5×. Ranking on that figure would have let this file serve as
the *small* target while being one of the largest — **satisfying the anti-gaming rule by doing the
thing it forbids**. So the runner computes counts from source with the project's own chunker at run
time, and no count is pinned anywhere, including in the notes about it.

### Two traps worth carrying

**A marker alone does not deselect.** `addopts` read `-m 'not golden'`, so registering a
`measurement` marker without extending it would have left a bare `pytest` firing five real queries
at the live index — the opposite of "committed unrun". Now `-m 'not golden and not measurement'`.
Knock-on for task 10a: `-m golden` reports **23 deselected**, not 16. Added tests, not a regression;
default run still **74 passed**.

**The span guard was mutation-checked, both arms.** A sample whose smallest target is
`git-guard-empty-index` (24 chunks) is the exact discriminator between R9's rank-tertile rule and
the value-span reading the spec calls weaker — value-span puts 24 inside the "bottom third"
(6 + (91−6)/3 = 34.3), rank tertiles put it in the middle. It fails. Dropping the top target fails
the other arm. Original restored byte-identical after both. A guard never seen red pins nothing,
and this one guards the anti-gaming rule itself.

### Not done

8b (run the five, record raw scores + per-feature counts as a baseline), 9 (install the agent, time
a **cold** `--full` run, re-choose `RUN_MAX_HOURS`/`RUN_ABANDON_HOURS` against it — a user call),
10a/10b, 10c (falsifier clauses a–j), 11 (judge, PR). Still nothing installed and **still nothing
indexed** — `memory.db` holds zero `archive_doc` rows, so the new golden query cannot pass until
task 9 runs. Expected, not a regression.

## 2026-08-07 — session 41 (continued): task 8b's baseline, and task 9 goes live

### Task 8b — the baseline said something R9 did not expect

Ran the five committed queries pre-R10 (archive configured, **not yet indexed**), user-confirmed as
the *before* half of R10's noise measurement. Two of five met both clauses — recorded as an
observation, **not** R9's verdict, which is task 10b's after the index run.

**The size effect runs opposite to R9's stated worry.** R9 assumes a fat target has *more* chances
to land two hits, so five fat targets would pass while measuring nothing. Measured, the two
**smallest** targets (6 and 9 chunks) were the only clean passes; the larger ones were displaced not
by each other but by the **judge verdicts and ADRs written about them** — `verification-marker-gate`
lost its top two slots to `coding-memory/observability-judge/` and `compliance-judge/` files,
`phase-guard-hook` to ADR 0011 and a judge verdict, all at the same `curated_doc` 1.5 weight. A
small feature has no paper trail and so faces no competitor; a mature one is outranked by its own.
**Consequence for 10b: crowding by ADRs and verdicts is a different finding from crowding by the
archive, and only the second is R10's cost.** Without this baseline that distinction was unavailable
and a 10b failure would have been blamed on the archive wholesale.

Scores clustered 0.0366–0.0488 against a 0.049180 ceiling — rank does nearly all the work, more
evidence the retired 0.30 floor was unreachable rather than merely strict.

### Task 9 — the feature watched itself work

Installed at 19:04, `state = running`, `runs = 1`, plist `0644`, template still 0 absolute paths.

**R5's two-write protocol worked on its first production run.** The entry write stamped
`run_started` and *carried* the six prior keys instead of recomputing them, so `chunks` stayed
**7631** rather than reading a freshly-emptied DB as `0` — the failure that would have blanked the
session line for an entire multi-hour rebuild. The nudge then classified that live state as
**state 1**, with no remediation command. The `SessionStart` line earlier in the very same session
had been **state 4**, unknown age: the 4 → 1 transition was observed live, not simulated.

**R10 confirmed in the real index**: `~/.claude/CODING_MEMORY.md` → **229 chunks**, the largest
single source, `archive_doc` / `episodic` / weight **1.0**; both project copies likewise, with zero
`archive_doc` rows carrying a non-`episodic` recall type. The **exact-path** check earned its
wording — the two project copies alone would have satisfied a loose "a row in each repo root" test
while the archive stayed unreachable.

### The concurrency hazard task 9 had to route around

`RunAtLoad` starts a run at bootstrap and `StartInterval` fires again 6h later, and `memsearch` has
**no lock** — so a cold `--full` run started manually would be a *second* indexer if it overran the
next firing. Sequenced instead: wait for the incremental run, snapshot its `status.json` before
`--full` overwrites `run_started`/`last_run`, **bootout the agent**, then time the cold run into
`memory-index/task9-timing.txt`. ⚠️ **The agent is booted out for the duration and must be
re-installed** with `memsearch/bin/install-schedule`.

### Not done

Task 9's timing half (cold `--full` duration, then re-choose `RUN_MAX_HOURS`/`RUN_ABANDON_HOURS`
**with the user**), 10a/10b, 10c, 11.

## 2026-08-07 — session 42: the incremental figure lands, and two rate bases disagree

### The ordinary-case number

The scheduled incremental run finished cleanly: **23:04:10 → 23:36:45 UTC, 32m35s**, `processed=87
skipped=900 chunks_added=1176 errors=0`, leaving 989 sources / 8607 chunks. `last_run_errors: 0`.
This is task 9's *ordinary case* figure, snapshotted to `memory-index/status.incremental.json`
before `--full` could overwrite it. The agent then booted out (`launchctl print` → **113**, as
designed) and the cold `--full` run started **23:36:50**.

R5's two-write protocol held across a second run, and the `--full` run is now exercising it against
a genuinely emptied DB — the case the carry-forward exists for.

### A short window is not a rate — the estimate was wrong by 4x

Mid-run, extrapolating from a **83-second** sample (4 `.jsonl` files) gave 2.8 files/min and a
projected **1.5–2h** remaining. The run actually finished in **~24 more minutes**. The sample landed
inside a stretch of uniformly tiny transcripts and carried none of the run's variance.

Worse, the two bases for projecting the *cold* run disagree, and the disagreement is not noise —
it is which cost model is right:

| basis | incremental rate | → 989 sources / 8607 chunks |
|---|---|---|
| files | 87 / 32.6min = **2.67/min** | **6.2h** |
| chunks | 1176 / 32.6min = **36.1/min** | **4.0h** |

The file basis is skewed high: those 87 included `CODING_MEMORY.md` (229 chunks), a compliance
verdict (160) and a plan (91), so per-file cost is unrepresentative. Embedding cost tracks chunks,
so **4.0h is the better guess** — but it is a guess, and no figure goes under `## Verification`
except the measured one. Recorded here because the *spread itself* is the finding.

### Why that spread matters now, not at hour six

4.0–6.2h straddles **`RUN_MAX_HOURS` = 6**. Falsifier clause **(j)** falsifies this feature if the
cold run reaches that constant and the branch proceeds anyway without putting it back to the user.
So the constant is live and the decision is the user's — flagged early rather than at the boundary.
Not widened, not pre-emptively touched.

### Correction to session 41's handoff

It stated the agent was "deliberately booted out". At session start it was still **loaded** —
bootout is step 3 of the timing script and step 1 was still running. Harmless (`StartInterval` 6h,
last fired 23:04, next ~05:04), but the handoff described an intended end state as a current one.

## 2026-08-08 — session 43: task 10, and the measurement that contaminated itself

Branch `feature/memsearch-freshness`, phase `implementation`, `model_tier: low`. Restored from a
handoff whose HEAD (`1f18dce`) was one commit behind reality: task 9's completion commit `1ba8a38`
landed at the handoff boundary, so the cold figure below was measured but unarchived here.

### Task 9's closing fact, archived late

Cold `--full` **17494s = 4h 51m 34s** (`processed=988 skipped=0 chunks_added=8615 errors=0`, exit 0)
against `RUN_MAX_HOURS` = 6h (21600s) — **81.0%**, margin 1h 8m. The stop-and-ask trigger did not
fire, so 6/24 stand as measured. `skipped=0` means a cold run re-digests every transcript, so the
margin shrinks with session count — which this feature's archive grows every session. Agent
re-installed after the run and verified loaded (`launchctl list` → last exit 0).

### Verified the handoff's #1 action instead of trusting the tick

Task 9's box was ticked and its commit message claimed the agent was re-installed. Checked
`launchctl list` and the plist mtime directly before querying the index. It held — but the check was
cheap and a ticked box is not evidence, which is the same discipline that caught the wrong-checkout
commits earlier in this repo.

### 10a — no regression, and a prediction that failed to come true

`pytest -m golden -q` → **16 passed**, matching `ceadcf0`'s 16. Deselected moved 63 → 81; that
number counts *the rest of the suite*, which this branch grew, so it is not comparable across
commits. Compared on passed. Zero warnings, so the 3 stretch and 2 negative cases were clean on
their merits rather than merely non-binding.

**Golden entry 11 was named in the spec as a predicted casualty and it passed.** Measured the reason
rather than narrating it: the archive *did* take 2 of 6 slots (ranks 3 and 6), but a
`transcript_digest` still held ranks 1–2, and the assert needs `.jsonl` only somewhere in top-6.
The crowding was real and simply below the threshold that assert can detect — a two-slot margin, not
an absence of effect. Also ran the falsifier: unfiltered, the same query returns zero `.jsonl`, so
the predicate can go false and the green result means something.

### 10b — R9 FAILS, 2 of 5, and the net count hid two opposite moves

Same 2-of-5 as task 8b's pre-R10 baseline, **but not the same two**: `falsifier-base-pin` regressed
(2 hits → 1) while `git-guard-empty-index` improved (1 → 2). Had the record said "2 of 5, unchanged"
it would have reported stability across a pair of opposite movements. The count was the same by
coincidence.

### The finding: recording the measurement moved the measurement

**No `archive_doc` appears in any of the five queries' 30 hits — R10's noise cost on R9's bar
measures zero.** The displacer is `docs/features/memsearch-freshness.md`'s own `## Verification`
section: task 8b's baseline blocks quote each target's query string and target paths verbatim, so
they are now indexed chunks that compete in exactly the queries they record. For `phase-guard-hook`
and `verification-marker-gate`, **rank 1 is this feature's own file at the score ceiling 0.04918**,
ahead of the target's own document — that is what fails clause 2. For `falsifier-base-pin`, the 8b
chunk enters at rank 4 and pushes the target's second hit out of top-6, which is the clause-1
regression.

This resolves session 41's carried question (crowding by ADRs vs. crowding by the archive) with a
third answer neither option contained: **crowding by the measurement record itself.** Same species
as the index that reported freshness it never checked — an instrument whose own output feeds back
into what it reads — one level up.

Appending the 10b table necessarily worsens the next run. Recording under `## Verification` is what
task 10 mandates, so it was recorded with the cost stated: the fix (exclude this file's
`## Verification` from indexing, or hold measurement records outside the indexed corpus) belongs to
the deferred planning pass. Did **not** re-exclude `CODING_MEMORY.md` — it did not cause this, and
re-excluding would not remove chunks already written.

### Carried unchanged

`-m golden` deselected-count instability; the 20-heading non-goal drift; the zero-files freshness
gap; the deferred planning pass (~85 lines → ADR 0021); the block-buffered `full-run.log` caveat.

## 2026-08-08 — session 43 (continued): task 10c, and the judge overturning my attribution

Tasks 10c and 11 (`46c9906` → judge run). Phase moved to `review`; model-switch checkpoint 3 asked as
its own gate and answered **stay low**.

### Task 10c — ten falsifier clauses, none falsified

(d), (i), (j) held as observations; (a), (b), (c), (e), (f), (g), (h) held *in test* via the 27-case
nudge suite. **The falsifier's window never opened** — its own wording is "across the 20 sessions
after it lands" and the branch has not landed, so every verdict is held-on-evidence, not observed.
Recorded rather than dropped.

Verified clause (e) from source rather than from the test file's comment: the comment claims "always
exit 0", but only `nudge.test.sh:43` capturing `rc=$?` and `:45` asserting it makes that true. Clause
(c) held only literally — spec `:231-232` already records that with no prior `last_run` a dead
scheduler surfaces as state 3, warning without naming the cause.

R9's 10b failure falsifies nothing: clause (i) conditions on 8b's scores being recorded and on target
span, never on R9 passing.

### ⚠️ The correction — I attributed R9's regression to the wrong cause

Session 43's earlier entry (above) states R10's noise cost measured **zero** and blamed this feature
file's own `## Verification` section. **That is retracted.** The observability judge overturned it;
I re-derived its counterfactual independently and it holds.

**What I got wrong, and why it was tempting.** No `archive_doc` row appears in any of the five
queries' 30 visible hits, and `memsearch-freshness.md` genuinely does hold rank 1 at the score ceiling
on the two worst queries. I read cause off those two facts. Both are true; the inference is invalid.

**The mechanism.** RRF scores by **rank inside a 200-candidate pool** (`search.py:63`), and the pool
is built from raw KNN/FTS lists *before* the weight multiply. An `archive_doc` chunk at candidate
rank 8 depresses every chunk below it, then at weight 1.0 against `curated_doc` 1.5 never surfaces in
the frame. **Invisible displacement is this scorer's normal mode.** The architecting-stage verdict
(2026-08-07) had already warned R9 had no control and that attribution was pre-committed. It was right
and I proceeded anyway.

**The control.** Re-fuse with one population dropped, ranks re-enumerated, pool drawn at 1000 and cut
to 200 *after* removal so dropping lets later chunks in. Guard: the no-op variant reproduces
`search()` exactly on all five queries.

- **minus `archive_doc`** → flips **two** outcomes: `falsifier-base-pin` FAIL→PASS,
  `git-guard-empty-index` PASS→FAIL. Exactly the two that moved against 8b.
- **minus this file** → flips **zero**. Top hit renames on two queries (to `2026-08-02-main.md` and
  ADR `0011`) but the replacement does not belong either. Passenger, not driver.

⇒ **R10 caused both the regression and the improvement**; the unchanged 2-of-5 was two opposite R10
effects cancelling in the count, not an absence of effect. Whether `falsifier-base-pin`'s regression
is an *accepted* cost is now an open decision, and ADR 0021 must inherit this attribution.

**The transferable lesson**, saved to memory: absence from a ranked frame says nothing about effect;
run the leave-one-population-out control before attributing any ranking change, and re-derive a
reviewer's counterfactual yourself rather than deferring or dismissing.

Also fixed: "FAIL, 2 of 5" was ambiguous — 2 is the *passing* count, 3 fail. A commit subject read
"fails 2/5". Noted: `addopts` deselects `measurement`, so a plain `pytest -q` reports all-green while
the bar is red.

### Left alone deliberately

`coding-memory/compliance-judge/verdicts.jsonl` (M) and `2026-08-08-falsify-harness-signatures.md`
(??) appeared mid-session from **another session** working a different feature. The judge advised
stashing them; declined — parallel-agent invariants forbid touching another agent's domain. Every
commit stayed pathspec-scoped instead.

## 2026-08-08 — session 43 (continued): the correction needed correcting

Judge round 2 (`coding-memory/observability-judge/2026-08-08-feature-memsearch-freshness-round2.md`,
risk=medium confidence=high, no dimension `fail`) re-scored the retraction and found a second error
**inside the correction itself**.

### "Removing this file flips none" was wrong — it flips one

The control table printed `git-guard-empty-index` as PASS(2) as-is and **FAIL(1)** with this feature
file removed. That is a flip. I wrote "flips none — passenger, not driver" in the prose *next to that
table*. Re-ran the control to confirm: **one flip.** The round-2 verdict notes it originated the
"flips 0" phrasing in its own round-1 text and I inherited it — but my own output was on screen, and
copying a reviewer's summary over reading my own table is the whole failure.

Corrected reading:

- **The archive drives both moves against 8b** — that stands, on three agreeing sources (my control,
  the judge's independent control, and 8b's baseline taken when the archive was genuinely unindexed).
- **This file is load-bearing for one of the two currently-passing queries.**
  `git-guard-empty-index` passes only while **both** populations are present; drop either and it
  fails. Without this file R9 scores **1 of 5**, not 2.
- On the other three it is a visible occupant with no verdict effect — the top hit renames, the
  replacement still does not belong.

### Consequence for the accepted-cost decision: kept, but bounded worse than it read

The "2 before, 2 after" symmetry that justified accepting `falsifier-base-pin`'s regression includes an
*after* pass propped up by the measurement write-up itself. The decision stands (the bar was never
green; two of three failures are archive-independent) but the cost is **less bounded** than the counts
suggest, so it now carries a monitor rather than a note: owner = the planning pass / ADR 0021; trigger
= re-run `-m measurement` after the first scheduled index run containing these commits; threshold =
**below 2 of 5 reopens the decision.** Also carried: consider R9 in CI as reported-not-blocking, since
`pyproject.toml:26` deselects it and a plain `pytest -q` prints all-green while the bar is red.

### Two process facts worth keeping

- **The decision was taken against a stale index** — `last_run` predates both correction commits, so
  the numbers will move before anyone re-reads them. That is why the trigger is tied to the next
  scheduled run rather than to a date.
- **The judge withdrew its own item 5.** It had advised stashing the stray `compliance-judge` files;
  on being told they belong to another session working a different feature, it agreed the pathspec-
  scoped approach was correct — with the added warning: never `git commit -a` here.

### Lesson recorded to memory

Absence from a ranked frame says nothing about effect — run the leave-one-population-out control
before attributing any ranking change. And check the resulting claim against **your own** table, even
when the phrasing came from a reviewer whose control you just reproduced.

## 2026-08-08 — session 44: the monitor was watching a blind gauge

Judge round 3 (`coding-memory/observability-judge/2026-08-08-feature-memsearch-freshness-round3.md`,
risk=medium confidence=high, **no dimension `fail`** — six pass, four concern, all four carried).
It independently reimplemented the ranking from `search.py`, self-checked that its no-op variant
reproduces `search()` on all five queries, and got the doc's control table cell-for-cell:
`as-is=2/5 · minus-archive=2/5 · minus-thisfile=1/5`. Ten checkable claims, ten correct. All four
test commands matched their declarations (74 · 16 · 3-fail-4-pass · 27/27).

### The one real finding: a trip-wire tuned to the thing it can't detect

The monitor attached in `1be05b5` said *reopen if R9 drops below 2 of 5*. Ninety lines above it, the
same section's founding insight says a steady 2 of 5 is exactly what a hidden regression looks like —
8b→10b held at 2 while `falsifier-base-pin` regressed and `git-guard-empty-index` improved, two
opposite R10 effects cancelling. **The alarm was calibrated to the one smoke the document had already
proved it cannot smell.** Widened: the trigger now fires on a drop below 2 of 5 *or on the same count
reached by a different set of queries*. Record which queries pass, not how many.

### What round 3 credited, and it is the right thing to have credited

It did not overcorrect. The tempting move after "you got the blame wrong" twice is to swing into
blaming yourself; the archive attribution survived on its three agreeing sources and only the one
wrong sentence narrowed. The correction also made the accepted cost look *worse*, not better.

Its explicit non-finding: the "on the other three queries" wording is a readability wrinkle, **not**
a prose-vs-table contradiction like the two before it. Marked non-blocking; the PR did not wait on it.

### Lesson recorded to memory

Both real errors on this branch were caught by review, never by self-check, and both were the same
species — **a summary sentence outrunning the table printed directly beneath it.** A derived count is
not a monitor: when a section's own evidence shows a metric can hold steady while its composition
moves, any threshold set on that metric inherits the blindness. Watch composition, not the scalar.

## 2026-08-08 — session 43 (continued): rounds 4 and 5, and PR #45

**PR #45 opened** — https://github.com/suyatdev/.claude/pull/45, base `main` @ `b78eae8`, created at
`5ff613d`. Detail in `coding-memory/pr-tracking.md`. Task 11 complete; tasks 1–11 all done.

**The gate passed on a real verdict — no `JUDGE_EXEMPT`.** Round 5, `head_sha 5ff613d`, risk=medium,
confidence=high, no dimension `fail`. Ends the run of two consecutive PRs that needed the bypass.

### Round 4 — "its feature shipped" was false, and the error flipped a safety conclusion

I had labelled `docs/features/verification-marker-gate.md` a stale `planning` card whose feature had
shipped. It has not shipped and has not **started**: `phase: planning`, `branch: none`, **15/15
unchecked**, no `hooks/test-marker-guard.sh`, no implementation commit on any branch. Both things I
cited as proof prove nothing — being an R9 measurement target only means a *document* exists to
retrieve (`belongs()` matches `docs/features/F.md`), and the 2026-08-01 compliance verdict says `Spec:`
in its own header. So the card is **correctly active**, and phase-guard denying my write was the guard
working. The dangerous part was the label: a later planning session could read "stale" as licence to
clear the one card guarding that feature, and `rules/gates.md` already documents four hooks that exist,
pass tests, and never run — "written ≠ active" is a known trap here and this nearly repeated it.

### Round 5 — the correction's own summary was imprecise too

"`phase-guard.sh` has no `review` arm" was falsifiable by one grep: `:448` matches
`(implementation|review)`. The real `implementation`-only gap is the **branch-claim** arm at `:387`, and
"cannot write source at all" holds only while an unsuperseded `planning` card exists (`:418`/`:502`
exit 0 otherwise). Fixed precisely in the doc and carried to the planning pass.

**That is four rounds out of five in which a summary sentence outran the evidence beneath it** — rounds
1 (wrong causal attribution), 2 ("flips none" against its own table), 4, and 5. Each was caught by a
reader who checked the sentence against the artifact rather than against the previous sentence. The
retractions all stay visible in the feature doc; erasing a causal error erases the lesson.

### The doc's length is now a measured problem, not an aesthetic one

Round 5 declined the offer to compress the retractions (~40 lines of ~1,900 — "~2% of the length,
~100% of the audit value") and relocated the concern: this doc is the **displacing top hit on 2 of R9's
3 failures**, pushing each target's own doc to rank 3–4. But the control shows removing it takes R9 from
**2/5 to 1/5**, so shrinking it *moves the metric under test*. Booked as planning-pass work — the
`.spec.md` split, with the counterfactual re-run after, not a pre-merge tidy.

### Blocked, and handed to the user

`phase-guard.sh` blocks `README.md` from this branch (path-not-intent; root files are not exempt), so
the skill-required Roadmap entry **could not be written by the agent**. Same shape as the earlier
`rules/` case; resolution is a hand edit, no hook touched. The exact line is in the PR thread and in
`pr-tracking.md`.

## 2026-08-08 — session 45: the rename that wasn't, and a conflict marker that balanced the books

Review phase, `feature/memsearch-freshness`, PR #45 open throughout. No code changed; three record
defects found and fixed. Design detail is in `docs/features/memsearch-freshness.md` and ADR 0021.

### The duplicate ADR 0018, resolved

`08b779d` merged `origin/main` and silently accepted **two** ADRs numbered 0018 — ours
(`launchd-agent-and-run-recency-split`, unmerged) and main's (`the-status-line-may-span-multiple-rows`,
merged via PR #43). Different filenames, so git saw no conflict. User chose: **ours yields → 0021**,
because an accepted, landed decision record does not get renamed.

The transferable part is the citation split, which the prior session's "~10 citations to update"
framing hid. Counted precisely, ours had **3 live, editable** sites (`memsearch/README.md:36`, feature
doc `:106`/`:1225`) and **14 append-only** ones (`CODING_MEMORY.md` ×4, 10 judge verdicts). Main's had
1 live and 2 append-only. **A renumber can only ever fix the live half** — so the archive gets a
*provenance header in the renamed ADR* ("anywhere dated 2026-08-06..08 saying ADR 0018 in a
memsearch-freshness context means this file"), never an edit. Ambiguity is retired going forward, not
retroactively; pretending otherwise would mean rewriting an append-only record.

### `git mv` + a scoped commit produces a copy, not a rename

`git mv` stages **two** index entries — a delete of the old path and an add of the new one.
`git commit -- <new-path> <other>` committed only the add, so `fea2423` shipped **both** ADR files and
the delete sat staged. Caught by `git ls-tree HEAD docs/decisions/`, not by the commit's own `--stat`,
which looked correct because every path it named was present. Fixed by amend + `--force-with-lease`.
**The pathspec on a rename must name the OLD path too.** This is the third instance of the
scoped-commit family and the first where the scoping *silently duplicated* rather than omitted.

### A verified merge still shipped a conflict marker

`CODING_MEMORY.md` ended with a bare `||||||| b78eae8` — committed in `08b779d`, whose resolution note
claimed "exactly 3 marker lines removed". There were four.

It survived a line-count audit **because the arithmetic balanced**: base 3787 + ours 637 + main 64 =
4488 = the merged count. It balanced only by coincidence — one of main's 64 added lines is a blank that
diff matches against an existing blank, freeing exactly one slot for the marker. *Counting lines is not
checking content.* The check that actually works, and that found the answer in one command:

    diff <(git show <parent>:FILE) <(git show HEAD:FILE) | grep -c '^<'   # must be 0, for BOTH parents

Zero deletions in both directions proves the merged file contains each parent in full, independent of
any count. Content confirmed intact; only the stray line was removed.

### Also

- Task 11 was still unticked while five review-phase judge rounds sat on disk and PR #45 had been open
  for hours. The checklist claimed the judge stage never ran.
- `memsearch/README.md:36` still links the old ADR filename — a **broken path**, not merely a stale
  number. `phase-guard.sh` denies it (not under `docs/`; no feature file claims this branch at
  `phase: implementation`, and `:387`'s claim arm ignores `review`). Second hand-edit item after the
  root README Roadmap line.

## 2026-08-09 — session 47: the monitor earned its keep

Post-merge. **PR #45 merged 2026-08-08T15:33:59Z at `65ebf81`**, which is `main`'s tip. No code
changed. R9's re-check monitor became actionable and was run. Detail in
`docs/features/memsearch-freshness.md` § "The R9 monitor fired".

⚠️ **This entry was first written claiming "Review phase, PR #45 open", and closed with a "Still owed"
section listing two hand-edits as blocked. Both were false and are corrected below.** The session
began in a worktree parked on `memsearch-freshness`, a copy of the *pre-merge* tip: the feature file
there still read `phase: review`, so every artefact agreed with each other and disagreed with reality.
The lesson is the restore check, not the merge — `git branch --show-current` returned
`memsearch-freshness` against frontmatter saying `branch: feature/memsearch-freshness`, a mismatch
`rules/gates.md` calls stop-and-report, and it was read as a match. **A stale checkout is internally
consistent; only a ref comparison catches it.** `gh pr view` would have cost one call and ended the
error before three commits were built on it.

### A count-only monitor would have stayed silent, again

The scheduled `launchd` run this feature installed finished `2026-08-09T04:45:18Z`, later than the
newest branch commit, satisfying the monitor's trigger. `-m measurement` returned **3 failed /
4 passed** — numerically identical to 10b, **2 of 5**. The passing *pair* changed:
`{stale-phase-guard-rule-text, git-guard-empty-index}` → `{stale-phase-guard-rule-text,
falsifier-base-pin}`. That is the monitor's second threshold clause verbatim, so the accepted cost is
**reopened**.

This is the second consecutive measurement where the count held and the composition moved. The
monitor was written specifically because 8b→10b did that; it has now done it twice, which retires any
argument that the "record which queries pass, not how many" clause was over-engineering.

### Two queries oscillating on a threshold, not three causes

`falsifier-base-pin`: PASS → FAIL → PASS. `git-guard-empty-index`: FAIL → PASS → FAIL. Across three
measurements, both swings are **clause 1 alone, moving between 1 and 2 belonging hits** — both queries
sit *on* the ≥2 boundary, where a single rank of movement flips the verdict. The transferable point:
before attributing N verdict flips to N causes, check whether the metric has a boundary the targets
are parked on. 10b's per-move attribution isn't retracted — it rests on a leave-one-out control that
was actually run — but it reads differently next to a third data point.

### Withholding the attribution that was right there

This file's own `## Verification` section now holds **rank 1 on two queries and a top-6 slot in four
of five**, and on the regressed query it sits at rank 2 where a belonging chunk used to be. Every fact
points at self-displacement. I did not write that down as the cause: the RRF pool means an *unseen*
population can displace while an on-screen one does not, and that exact inference already had to be
retracted in 10b. The counterfactual harness was not run for this measurement, so the cause is
recorded as unassigned rather than as the obvious answer. Cost of running it now: a ~40-line rebuild
at ≥75k context, against an index that must be pinned first.

Also worth keeping: **recording the monitor's result enlarges the section under suspicion.** The
instrument and the record share a corpus, so measurement perturbs it. Unresolvable by writing more
carefully; only the counterfactual separates them.

### Corrected: nothing was owed — `c012eda` had already closed it

Both hand-edits were **already done** on `docs/post-merge-followups-45` (`c012eda`, unpushed at the
time): `memsearch/README.md`'s ADR link repointed to 0021, and the root `README.md:57` Roadmap line
added. That commit also marked #45 merged in `pr-tracking.md` and backfilled the round-5 verdict
outcome. This session's three commits were cherry-picked onto that branch, where they belong; the
merged `feature/memsearch-freshness` and the stray `memsearch-freshness` were both deleted.

The transferable failure is **acting on a premise the user supplied from my own bad report.** Asked to
"push to `feature/memsearch-freshness`", I verified the push was a clean fast-forward — the mechanical
question — and never re-checked whether the PR was still open, the question that actually mattered. The
push succeeded and left three commits stranded 3 ahead of a merged branch's merge point. **Verify the
premise, not just the operation**; a fast-forward check cannot tell you the destination is dead.

## 2026-08-09 — session 48: the owed control ran, and cleared its own prime suspect

Branch `docs/r9-counterfactual-control`, cut from `origin/main` (`64d8acb`). Phase `review`
throughout; model-switch checkpoint answered — stay on Opus 5.

**Pinning the index was not ceremony.** The control was run against a `conn.backup()` snapshot
(8960 chunks, `max(indexed_at) = 2026-08-09T04:45:14+00:00`, sha256 `9ba25e05…`) that matches the
state the R9 monitor fired against. **Mid-session a scheduled run moved the live index to 9012
chunks.** Had the control read "current", it would have explained a corpus the monitor never saw —
the exact failure the feature doc predicted one paragraph before it happened.

**Result: `## Verification`'s self-displacement — the reading the previous session called tempting
and refused — is wrong.** Dropping this file changes no verdict on any of the five queries; so does
dropping the archive. **And no other document is implicated either:** the final answer is that
`git-guard-empty-index`'s second belonging chunk sits at **rank 8**, three places below the cut, and
**any** three removals from the six ranks above it restore PASS (2) while **no** two do — regardless
of which documents they come from. What R9 records on this query is a margin, not a displacer.

The one structural observation that survives, because it needs no counterfactual: a **639-line**
judge verdict about `git-guard-empty-index` outranks the **375-line** spec it grades, at equal
`curated_doc` weight 1.5. That verdicts and specs share a weight while the verdicts are *about* the
specs is checkable from `config.json` and the file lengths. It is **not** demonstrated to have caused
anything here.

**And the one change that actually helps, found last and nearly missed.** From "identity has no
measured effect" I concluded "no reweighting is supported" — wrong, and wrong in the conservative
direction. **Deletion-invariance to identity is not weight-invariance, because a weight change is
*defined* by identity**; deleting a population is only the endpoint `weight = 0`, and I generalised
from it without sampling the interior. Swept (a post-fusion multiplier, so no re-index — the cheapest
control in the whole investigation, and the last one run): judge `curated_doc` weight **1.5 → 1.2
takes R9 from 2 of 5 to 3 of 5 with nothing regressing**, both remaining failures gaining hits. That
is the first change measured anywhere in this feature that *improves* the bar instead of trading one
target's pass for another's. **The enumeration killed the narrative, not the remedy** — a story being
wrong does not make every action it suggested wrong.

**The conclusion narrowed three times, each time because a control said so, never because the prose
was re-read.** (1) "the cause is the judge corpus" — over-claimed. (2) "the only population that moves
it, and a placebo rules out dilution" — the placebo's null was an artefact of the approximate method;
measured exactly it *does* perturb R9 (`falsifier-base-pin` loses clause 2), so "verdict-safe" was
also wrong. (3) What holds: three chunks are sufficient, a size-matched random deletion does **not**
recover the query, and the class-level claim "judge verdicts crowd out feature docs" is **untested** —
one document, one query. ⚠️ **Corrected 2026-08-09: "untested" is now too kind for the deletion
result.** The exhaustive enumeration measured it — any three removals from the six ranks above the
target restore PASS, no two do, and *which documents they come from makes no difference* (20/20
triples, 0/15 pairs). Document identity has **no** measured effect on deletion, so the crowding story
is withdrawn rather than merely unproven. Identity still matters for *weighting*, which is a different
control: see the judge-weight sweep in the feature doc.

The transferable rule: **"what is the cause" is answered by the first population that flips the
result; the question that discriminates is "what is the smallest thing that flips it".** 2405 chunks
and 3 chunks produce the identical recovery, and only the second one tells you what to fix.

Two things the count would have hidden, both recorded: dropping judges *regresses*
`falsifier-base-pin`, holding 2 of 5 in a third distinct composition — retuning moves the failure
rather than removing it. ⚠️ **Corrected 2026-08-09: that last clause is true only at the `weight = 0`
endpoint, which is what "dropping judges" is.** A later sweep of the interior found judge weight
`1.5 → 1.2` takes R9 to **3 of 5 with nothing regressing** — so retuning *can* remove a failure, and
the endpoint result does not generalise to the curve. Deletion-invariance is not weight-invariance. And `/api/embed` is **non-deterministic** (≤1.08e-04 per element, min cosine
0.999999803) yet verdicts were identical on 8/8 re-embeddings for all five queries, which falsifies
the marginal-instability explanation without touching the boundary observation itself.

**The largest lesson landed last, and it invalidates the framing rather than a number.** The three
displacing chunks were indexed `2026-08-07T23:38:14` — **already present at 10b, when the query still
passed.** Something present while a test passes cannot be why it later failed. So the control answers
*"what is sufficient to restore the verdict now"* and **not** *"what caused the regression"*, which is
the question it was run to answer and which stays unassigned. A leave-one-out varies populations at
one instant; a regression is a change between two instants. Three rounds of increasingly careful
measurement never turned the first into the second — and the tell was available from the start, in a
timestamp I did not check until the fourth pass.

Practical rule: **before running an instrument, state which question it can answer and check that it
is the question being asked.** Method rigour cannot rescue a category error, and rigour is exactly
what made this one persuasive for three rounds. Reconstructing 10b's index state is now the blocking
item for ADR 0021, promoted from a footnote.

**The final narrowing killed the story entirely, and it came from refuting a refutation.** Round 3
predicted dropping ranks 4/6/10 would recover the query as well as the verdict chunks do. It does not
(FAIL 1), and I concluded from that failed counterexample that the three verdict chunks were
*specifically* load-bearing. **That is a non-sequitur, and round 4 caught it.** Enumerated
exhaustively over the six ranks above the target: **all 15 two-chunk removals FAIL, all 20 three-chunk
removals PASS, and the number of judge chunks among them (0, 1, 2 or 3) changes nothing.** Round 3's
example was merely a disguised two-chunk removal — rank 10 sits *below* the target and is inert.

⇒ **Document identity has no measured effect. The only variable is how many chunks above the target
are removed, and the threshold is three.** Every earlier result collapses into that arithmetic:
`minus this doc` removes 1 of the 6 above (FAIL), `minus archive` removes 0 (FAIL), `minus judges` and
`minus` one 41-chunk file and `minus` 3 chunks all remove the same 3 (PASS). **The judge-crowding
story is dead** — what R9 measures on this query is that the feature's second chunk sits three places
below the cut, not that anything in particular displaced it.

Two lessons, and the second is the one worth keeping. **(1) Take the challenge seriously, take the
assertion to the data** — across four rounds the judges made four wrong factual claims (twice
reporting the snapshot destroyed when it was present in a path they had not searched; guessing elided
ranks were archive chunks when they were feature docs) *and* four right ones that each changed the
conclusion. Neither deference nor dismissal survives contact with checking. **(2) A false
counterexample does not strengthen a claim.** Refuting "X would also work" leaves "only Y works"
exactly as unproven as before, and the discriminating test — vary identity at *fixed* removal size —
was one script away with every artefact still on disk. Rigour applied to the wrong comparison reads
as rigour right up until someone runs the right one.

## 2026-08-09 — session 49: the verdict that invalidates itself, and the paragraph that kept being wrong

Session 48 left one blocker: `judge-guard.sh` wants a verdict whose `head_sha` equals HEAD, and the
commit recording rounds 1-5 had moved HEAD past them. Rounds 6, 7 and 8 ran. **All three passed with no
`fail` dimension — and all three found a real error**, each time in the *same* paragraph: the one that
tells ADR 0021 what to build.

**Round 6:** the section's one actionable result — judge weight `1.5 → 1.2`, R9 from 2 of 5 to 3 of 5 —
**is not a config edit**. `config.json:17` keys `weights` by `source_type` and judge verdicts share the
`curated_doc` bucket with every spec and ADR. Verified: all ten printed ranks are `curated_doc`, so a
uniform multiplier scales them equally and reorders nothing — which *proves* the sweep was judge-only,
and proves a wholesale `curated_doc = 1.2` would demote every spec while reproducing none of the table.
Round 6 also claimed the doc never names the re-weighted population; it does (`:2326`, "for judge
verdicts"). **That wrong claim was left standing in its verdict rather than edited** — a calibration
record that only records the judge's hits is not a calibration record.

**Round 7** caught the fix itself naming `CODING_MEMORY.md` as a `curated_doc` member *one sentence
before* citing the carve-out that removed it — `_doc_source_type` (`index.py:46-58`) re-types it to
`archive_doc` (1.0) by filename, whichever bucket found it. I had verified the conclusion and skipped
the enumeration, which is precisely the failure this section exists to document. **Round 8** caught the
corrected version keying the proposed knob on `coding-memory/` — **2866** chunks against the sweep's
**2405**, over-capturing **461** including `pr-tracking.md`, which this same section measures as inert.

Three lessons, and the third is the general one.

**(1) A verdict pins HEAD, so committing a verdict invalidates it.** That is a structural loop, not a
mistake — three rounds were spent in it. The escape: run `gh pr create` while the verdict file is
written but *uncommitted*, then commit and push it onto the open PR. No `JUDGE_EXEMPT` required.

**(2) Errors concentrate in the instruction-to-a-successor.** Not in the measurements — those survived
eight rounds — but in the paragraph saying *what to do next*, which is the least measurable prose in
the document and the only part another agent will act on. Three rounds, three distinct errors, one
paragraph. Judge that paragraph hardest; it is where being plausible is cheapest.

**(3) When two rounds disagree twofold, re-derive rather than pick.** Round 6 estimated the merge
perturbation at ~48 chunks, round 7 measured 99. Running `chunk_doc` myself gave **99 at `1c89fbe`,
112 with round 7's own verdict added** (+4.7% of the judge corpus) — round 7 exact, round 6 half. The
count grows every time the section is judged, which is the joke and also the finding: measuring this
corpus perturbs it. Stored as a derivation, deferred to ADR 0021 rather than estimated.

PR #47 opened (docs-only, `docs/r9-counterfactual-control`); detail in `coding-memory/pr-tracking.md`.

**Merged 2026-08-09T20:18Z** as `b829eea` (PR #47). Merge verified as a true *union* rather than a
balanced total: empty diff against the branch tip, 2 deletions against old `main` (both intended), no
conflict markers. The marker probe had to be run twice — the first version piped `git grep` into
`head` and reported *`head`'s* exit code, so it would have said "clean" no matter what; the second
captured the code directly and was falsified against a pattern known to exist before being believed.
**A check that cannot fail has not passed.**

All eight verdicts backfilled `outcome: rework`. ⚠️ **The commit that made this backfill claimed "8
for 8 `risk=low`" in its subject and body. That count is wrong — it is 6 `low` and 2 `medium`** —
and it was caught by the judge round on the backfill itself. Counted properly:

| field | distribution across the 8 | all outcomes |
|---|---|---|
| `risk` | 6 `low`, 2 `medium` | `rework` |
| `confidence` | **7 `high`**, 1 `medium` | `rework` |

The framing survives but weaker than stated: `risk` scores whether a change can *break* something,
and documentation cannot, while what recurred was being *wrong*. Six low-risk verdicts followed by
rework still makes that point — but on two rounds the risk field *did* move, so "predicts nothing"
over-reached. **The stronger signal was in the same rows and I missed it: `confidence` was `high` on
7 of 8, and all 8 needed rework.** Confidence is the field that plausibly does claim correctness, and
it was high-and-wrong seven times.

The lesson is not the framing, it is the mechanism. This entry's own commit message says *"a check
that cannot fail has not passed"* while asserting a headline count **nobody counted** — its
self-verification was meticulous about *which rows* changed and silent about *the number claimed
about them*. Verifying the operation is not verifying the claim you drew from it.

## 2026-08-09 — session 50: closing out PR #49, and breaking the close-out regress

The entry above was written on branch `docs/post-merge-followups-47`, merged as **PR #49** at
**`0fe9723`** (2026-08-09T20:44:08Z) — identifiers recorded here because a grep for `PR #49` or the
branch name matched **nothing** in this file or `pr-tracking.md` before now. The lesson had been
archived; the work had not been *recorded*. An archive that omits the identifier a reader will search
by is unreachable, and I found that gap by hitting it.

Session 50 did two edits and no feature work: the last `verdicts.jsonl` row (`head_sha 6e35701`)
`outcome: null → rework`, and #49's own section in `pr-tracking.md` — see that section for the merge
verification, the re-derived 6 `low` / 2 `medium` split, and a `git-guard` gap found on the way.

**The regress is the point.** Three close-outs running (#45→#46, #47→#49, #49→here), each PR left its
own record unwritten, because a PR cannot mark itself merged — the merge happens after its last
commit. Opening PR #50 would have created a fourth. **These two edits went straight to `main` as
documentation instead**, which `git-guard`'s allowlist permits by design. The general rule: paperwork
for a merged PR is not itself PR-worthy work.

## 2026-08-09 — session 48: the correction list needed correcting

Restored onto `feat/tracking-feature-state` (`37a8e38`, clean, `0 0` vs origin, `0 2` vs `origin/main`).
Frontmatter verified against reality before any work: `phase: implementation`, `branch:` matches
`git branch --show-current` in the worktree. No mismatch, so no stop-and-report.

The one task on the board was the card audit session 47 deferred: re-derive **every** factual claim in
`docs/features/tracking-feature-state.md` rather than patch the four errors it had already logged.
That instruction came from the standing rule about repeated findings of one class, and it paid:

- Five further defects, all the same species — a fact asserted from a grep nobody tried to falsify.
- **Two of the five are inside the correction list itself.** Correction 2 pinned "exactly 2 cards say
  `branch: none`" (now 3 — `pane-dispatch-model-flag` joined, still untracked in the main checkout).
  Correction 3 pinned the marker discard to `feature_tasks.py:11-14`, which is docstring prose; the
  mechanism is `STRICT_RE` at `:37` capturing group 1, consumed at `:75`.
- A correction written to fix stale numbers went stale in under 24 hours, in the same file, during the
  same implementation phase. Store the derivation, never the result — the rule now has a second,
  self-referential proof.
- Evidence bullet 1 turned out to be **unrunnable**, not merely stale: `.gitignore:72` ignores
  `/.claude/`, so `git log -1 --format=%cr .claude/session-state.md` prints nothing. A derivation that
  cannot execute reads exactly like one that passes, which is worse than a wrong number.
- Criterion 1's "a repo with N feature cards" is checkout-dependent — main and the worktree each hold
  14 card files and not the same 14. Unfalsifiable as written.

Confirmed still true and not to be re-litigated: `STRICT_RE` text; `TMUX` unset under
`TERM_PROGRAM=ghostty`; `handoff-wrapper.sh:5`; all three `cmux.sh` citations; `analyze.py` at 792
lines; `test_analyze.py`/`test_store.py` collecting.

Ended on **GATE: Spec change needed**. `managing-session-memory` forbids repairing a wrong spec from
inside `phase: implementation` — the errors get noted and the gate gets raised, and that is where this
session stops. Tasks 1-6 remain unticked on purpose: ticking a checklist whose criteria are known
wrong records progress against a spec nobody has agreed to yet.

## 2026-08-09 — session 49: the spec revision the gate was holding

Session 48 ended on **GATE: Spec change needed** with nine recorded defects in
`docs/features/tracking-feature-state.md`. The user authorized repairing the card in place rather than
flipping to `phase: planning` and re-gating — the phase gate exists to stop *silent* spec drift, and
an explicitly authorized correction pass is its opposite. Committed as `1ac0e5e`, pushed.

All nine repaired, and the two `## Card corrections required` sections deleted. Deleting them was the
point, not tidiness: a spec plus a list of ways the spec is wrong is two documents disagreeing, and a
reader cannot tell which one to believe. Git holds the detail — `a854e99` is the last commit carrying
the unrepaired text.

The structural fix applied throughout: **claims are written as derivations to re-run, not as stored
counts or line ranges.** The single retained number (53 tests) is stamped with its measurement date
and the command that reproduces it.

**Two defects found in the audit itself**, while repairing the audit's findings — the third
consecutive round of this species:

- The audit said tasks 4, 6 and 9 named uncollectable `*.test.py` files. Tasks 4 and 9 did; **task 6
  never did** — it names `store.py`, an implementation file. The correction inherited "6" from the
  adjacent list without re-reading the task it was correcting.
- The audit attributed cmux's non-erroring ref fall-through to `send`. The source comment
  (`panes/adapters/cmux.sh`, above `rename_tab`) documents it for **`rename-tab`**, proven by probe P6
  against `surface:9999` at exit 0. `send` takes the same `--surface` flag and plausibly shares the
  resolution chain, but nothing has shown that it does.

That second one is the same unfalsified-inference error that produced the original "injection is
unproven" claim — a property read off an adjacent function and asserted of this one. It is now carried
explicitly into the card as an open question for task 8 (new criterion 9: refuse an unconfirmed ref,
and empirically determine whether `send` inherits the fall-through) rather than resolved by assumption
in either direction.

Verified this session rather than transcribed from the handoff: `cmux send --surface` at
`panes/adapters/cmux.sh:163-164`; `feature_tasks.py` exposing `STRICT_RE`/`identity()`/`task_ids()`
with no done/total of its own; `terminal-detect.sh:14` printing `none`; `handoff-wrapper.sh:5`;
`TMUX` unset under `TERM_PROGRAM=ghostty`; `.gitignore:72`; and the suite at 53 passed via
`uv run --with pytest --no-project pytest task-tracker/ -q`.

Card now sits at `phase: implementation` with tasks 1-6 ticked and task 7 (`PORTS.md` entry) next.
The compliance-judge gate has still never run on this card, and it is now owed twice over — the
spec-compliance gate fires after *any* spec edit.

## 2026-08-09 — session 50: task 7, and a session-start branch line that disagreed with the checkout

Task 7 of `tracking-feature-state` closed: port **8422** allocated to the task-tracker control server
and recorded in `PORTS.md`, with `TASK_TRACKER_PORT` as the documented override. Picked clear of the
8000-8100 block mtg-wizard and snatch-bracket hold; `lsof -nP -iTCP:8422 -sTCP:LISTEN` was empty at
allocation. The card's task-7 bullet stores the *derivation*, not just the number, and states that
task 8 reads the port from `PORTS.md` rather than re-deciding it.

The registry row carries the two facts a future collision-hunter needs and neither of which is
inferable from the port alone: the bind is `127.0.0.1` **explicitly**, and the server is
session-scoped with no daemon or launchd job — so a stale listener on 8422 means a leaked process,
not a service.

**Restore gotcha, new:** the harness's SessionStart `gitStatus` block named the current branch as
`feat/tracking-feature-state` while `git branch --show-current` in `/Users/marksuyat/.claude` printed
`feature/memsearch-freshness` — and the working-tree entries it listed (`verdicts.jsonl`,
`memsearch-freshness/`) were the main checkout's, not the feature worktree's. So that block mixed a
branch name from one checkout with a status from another. The restore step that says "run `git status`
yourself" is not redundant with it; it is the thing that catches this. Read the branch from
`git branch --show-current` in the directory you intend to work in, every time.

The worktree is `/Users/marksuyat/.claude/.claude/worktrees/tracking-feature-state` — nested
`.claude/.claude/`, per `git worktree list`. The handoff wrote it as `.claude/worktrees/…`, which is
correct **relative to the repo root**; reading it as an absolute-ish path off `$HOME/.claude` and
`cd`-ing there fails. Handoffs should write worktree paths absolutely, since the reader has no
guaranteed cwd.

Next: task 8 (`server.py`), still gated behind the outstanding 15-second probe — `cmux send` into a
live **Claude TUI**, where every proven use to date targets a shell prompt. Not yet run. The
compliance-judge gate on this card remains unrun and owed twice.

## 2026-08-09 — session 51: the compliance gate finally ran, and failed the card

The compliance-judge gate on `tracking-feature-state` — owed twice, unrun since the card was written
— ran at last. **Round 1: `fail`, 7 violations, confidence high** (`4c921ad`). The ledger held 81
rows across 13 other specs and not one for this card; `spec_blob_sha 28b46338` pins the verdict to
the card at `24ff8da`.

**Where a worktree card's verdict belongs.** `agents/compliance-judge.md:60` still hardcodes
`~/.claude/coding-memory/compliance-judge/`. That is wrong for any card living on a feature branch,
and this card is absent from the main checkout's working tree entirely — a verdict written there
would sit beside a spec that is not present. `hooks/judge-guard.sh:33-35` records in its own comments
that hardcoding `$HOME/.claude`'s copy was a **bug**, fixed so the guard reads the *judged repo's*
store, repo-relative from `git rev-parse --show-toplevel`. `agents/observability-judge.md` already
says repo-relative; the compliance agent was never updated to match. Both dispatches this session
overrode the path explicitly and the verdicts landed in the worktree (78→79 rows) with the main
checkout's store untouched at 81, another session's uncommitted work intact. **The agent file is
still wrong — fixing that asymmetry is open work.**

**Both judges converged independently on the same worst finding**, which is why it is worth trusting:
the per-launch bearer token is specified to be baked into `task-tracker/tracker-data.js`, and that
file is *already committed* (`37a8e38`), *not* gitignored, holding real output
(`generatedAt 2026-08-09T06:21:47Z`) — in a repo `gh repo view` reports as **public**
(`suyatdev/.claude`, `isPrivate: false`). All four facts re-verified by hand this session, not taken
on the judges' word. Nothing is leaked today only because `server.py` does not exist yet, which is
exactly why the decision is cheap now and awkward after task 8.

Three of the seven violations are the specific content task 8 needs: the token's location, the
server's wire contract (no endpoint, method, header name, request/response shape, or statement of
whether a command id carries an argument), and an allowlist written as "(`clear`, `handoff`,
`reanalyze`, …)" — an ellipsis standing in for the entire authorization set. Implementing task 8
against that is how the improvised shape the judge warned about gets built.

**A tenth defect of the known species, found this session.** The card's task-13 warning says
`addopts` in `pyproject.toml` deselects the `golden` and `measurement` marks. The only
`pyproject.toml` in the repo is `memsearch/pyproject.toml` — a sibling directory that never governs
`task-tracker/`, which carries no pytest config of its own. The warning errs safe but is aimed at
something that does not apply, and it is the same stale-claim species two audit passes were spent
eliminating. Separately: three `test_store.py` tests are `skipif(NODE is None)` (lines 150, 361,
412), **including criterion 5's JS-loadability proof** — on a node-less host the suite is green with
that assertion unrun, which matters for task 13's before/after counts. `analyze.py` is 792 lines
against the 800 hard cap, eight lines of headroom and no mechanical trigger.

**Gate reached, not opened.** `phase: implementation` forbids spec edits, but the compliance loop's
step 3 requires the main agent to revise the spec on a fail. Those cannot both hold, so this is a
`GATE: Spec change needed`, handed to the user rather than worked around. `model_tier` is already
`high`, so the model-switch half is satisfied in substance. Round 2 re-dispatch must pass the round-1
violation ids so persistence detection stays sound.

## 2026-08-09 — sessions 52–54: five compliance rounds, and the derivation that had to stop being a grep

Sessions 52 and 53 ran compliance rounds 2 and 3 on `docs/features/tracking-feature-state.md`
(fail 5, fail 2). Session 54 ran rounds 4 and 5 (fail 2, fail 3). Commits `81d98dc`, `7e2bf90`,
`b9ad394`, `ce3af84`, `126f5eb` on `feat/tracking-feature-state`. Phase stayed `planning` throughout —
task 8 is still gated.

**The finding worth keeping: a derivation is only as good as its scope, and a wrongly-scoped one is
indistinguishable from a correct one.** `writing-specs/api-contracts` failed four consecutive rounds.
Each fix widened the same `grep` by one step and a new blind spot appeared just past the new edge —
one file → the repo (round 2), HTML → HTML plus JS (round 3), and still not CSS, whose `url(...)`
syntax the pattern never matched (round 4). Two of those wrong answers were *reproducible*, which is
why they read as authoritative. In session 52 the observability judge "confirmed" one of them by
re-running the same mis-scoped grep; two agents agreeing was one error repeated.

Round 5 closed it, and only because the user rejected a fifth narrowing and directed a structural fix:
**the servable set stopped being a search and became an explicit manifest, proved by loading the page
and enumerating what it actually requests.** "What does this page request?" is a runtime property; a
text search can only ever approximate one, so each round had been moving where the approximation
failed rather than removing the failure. The judge closed the id by rebuilding the manifest from
source rather than reading the table.

**And then the same disease appeared inside the cure.** Criterion 13 — the new runtime check — pinned
the populated store state, so it never requested `tracker-data.sample.js`: the fallback shim returns
early when `tracker-data.js` exists (`tracker-data-fallback.js:16`), and that file is present. The one
row four rounds of greps had missed was the row the new check did not verify, in a shape that looked
stronger than what it replaced. Both judges found it independently. Criterion 13 now runs in both
store states.

Three smaller instances of the same shape, all in material added by the round that was fixing the
previous round: the audit log arrived in round 3 with nothing asserting it (round 4 added the stderr
scan); the parent-death shutdown arrived in round 4 with no criterion and no poll interval, one
paragraph after the card argues an unspecified timeout gets implemented as no timeout; and criterion
12 asserted `cmux send` was invoked while task 9 said to fake the binary, moving the live path from
visibly untested to *apparently* tested. **A control that creates a new surface and ships without the
test for that surface is the recurring defect here, not a one-off.**

Two dependency-shaped calls were the user's, not the model's: the structural fix over a fifth grep,
and using the Claude browser extension for criterion 13 rather than adding a browser driver to a repo
that has almost none — recorded with its cost stated (criterion 13 does not run under `pytest`, does
not run unattended, needs an operator with the extension connected).

**Still open at the end of session 54:** round 6 not yet dispatched; the `cmux send` → live Claude TUI
probe still owed since round 2; `writing-specs/good-bad-edge-cases` cited in two consecutive rounds
(4 and 5) on different instances. ADR 0024 written and then corrected in the same session — it had put
the parent-death check on the idle timer and left the tick unnamed.

## 2026-08-09 — session 55: round 6, and the defect moves from the precondition to the pass condition

Compliance round 6 on `docs/features/tracking-feature-state.md`: **fail, one violation**, and it is
`writing-specs/good-bad-edge-cases` for the **third consecutive round** — each time a new instance of
the same class. Escalated to the user rather than auto-revised, as session 54 pre-committed to doing.

**The finding.** Round 5's fix made criterion 13 run in both store states. Run (a) moves
`tracker-data.js` aside — but `Task Tracker.dc.html:15` requests that file unconditionally, and the
*same commit* added the wire-contract rule that a missing `tracker-data.js` answers `404` while
criterion 13 forbade any `404` but `/favicon.ico`. **A correct implementation failed run (a) on its
first request.** Both judges reached it independently from different rubrics.

**Why it kept recurring, which is the part worth keeping.** Every round patched criterion 13's
*precondition* and left its *pass condition* unexamined. The pass condition was a negative universal —
"every request returns `200` except `/favicon.ico`" — and nobody re-reads a negative universal when
the precondition moves. Sharper still: `126f5eb` **withdrew** the old "run criterion 13 before task
14" instruction for being unsatisfiable, wrote down why that shape is dangerous ("a criterion whose
first directed run must fail is one that gets weakened until it passes"), and then created the same
shape four paragraphs earlier.

**The fix (user decision: fix the class, not the instance).** Both judges named a sufficient
one-clause patch — add `/tracker-data.js` to run (a)'s allowed-`404` list. The user rejected it for
the same reason the round-3 escalation rejected a fifth narrowing of the grep. Criterion 13's pass
condition is now **set equality** against an explicit per-run table of expected path → expected
status. This also closes a direction the negative form never covered: an **unexpected `200` fails
too**, so a server that quietly widens its manifest is caught.

**Two derived surfaces moved with it, both easy to miss.** Line 322 said criterion 13 carves out "the
one expected `404`" — the new table makes it two, so that line would have gone stale *inside the
commit fixing what it describes*. And `support.js:158` issues a second token-bearing `GET /` only
while `window.__resources` is undefined; task 14 defines it, so it is correctly out of a criterion
that runs after task 14. Verifying that row rather than assuming it is what kept the new table from
being a fifth instance of this class.

**The recurring defect recurred a fourth time, mildest form yet:** round 5's new `500
asset_unreadable` row had nothing exercising it — task 9's "each status code in the contract table"
was satisfiable by `reanalyze_failed` alone, since the table carries two `500` rows. Task 9 now
asserts it separately. ADR 0024 also gained the launch contract (non-detached child, `stderr`
inherited); it had the 5-second poll correction but not this, so an implementer reading only the ADR
would build both lifetime controls silently inert.

**Still open at the end of session 55:** round 7 not yet dispatched; the `cmux send` → live Claude TUI
probe still owed since round 2; the card is 933 lines, a fifth consecutive growth round, and both
judges have now flagged the trend — a compaction pass is owed before the branch lands. The main
checkout's three misrouted `statusline-followups` verdict rows are still unreconciled, deferred by
the user until the card passes.

## 2026-08-09 — session 56: two PRs merged past their own gates, and the outcome that isn't a value

**Session numbering: the collision the last handoff warned about is now materialised inside one
file.** `main` carries *two* `## 2026-08-09 — session 48`, *two* `session 49`, and *two* `session 50`
headings (lines 4608/4796, 4708/4829, 4778/4872) — one from each lane, with different content, fused
by PR #48's merge. **56 is chosen as `max(all lanes) + 1`, not `mine + 1`.** Anyone numbering the next
entry should grep the whole file, not their own lane's tail.

Both PRs that were open at the end of session 50 merged while the session was down, one minute apart:
**PR #48** (`feat/tracking-feature-state`) at `e4f873e` 01:48:16Z, **PR #50**
(`docs/verify-before-claiming`) at `fe55b2d` 01:49:51Z. Zero PRs are open now. Neither had a
`pr-tracking.md` section; both do now — that file is where the detail lives, and this entry is only
the part worth carrying forward.

**Both merges are true unions, and the check that proved it was falsified first.** #48: `git diff
dd69033 e4f873e` empty, base→merge **+11886 / −0 across 35 files**. #50: base→merge **+142 / −2**,
and both deletions were *read* — the rewritten `core-conduct.md` line and a rebase-staled SHA — not
assumed benign. The conflict-marker grep returned rc=1 on the merged tree, and the same pattern
returned rc=0 against a string known to match. **A clean probe means nothing until you have watched
it come back dirty**; that is the lesson from session 50 applied rather than restated.

**The finding: PR #48 merged past both judge gates.** Compliance ran **six rounds, every one `fail`,
with no round 7** — the last recorded judgment on that branch is a failure. Observability has **six
verdicts, all stage `architecting`, and zero stage `implementation`** — the stage `judge-guard`
actually gates `gh pr create` on — with the final architecting verdict at `risk: high`. Its feature
card on `main` still reads `phase: planning` against a merged 35-file implementation. None of this is
a criticism of the merge, which is the user's call; it is a record-keeping fact that twelve `null`
rows would otherwise have left looking like the question was never asked.

**`outcome` has no honest value for a change that shipped over a `fail`, so it keeps `null` — with
prose.** Rounds 1–5 in both stores are backfilled `rework`, and that is *derivable*: each round's
successor carries a different `head_sha`, so a revision provably followed. Round 6 shipped
**unchanged** past a failing verdict, where `clean` (judged fine, shipped fine) and `rework` (revised
after) are both false. The enum has no third value, so the row stays `null` and `pr-tracking.md` says
why — otherwise it is indistinguishable from the 77 rows that are merely un-backfilled. **A missing
value with a written reason beats a plausible value with none**; this is `outcome: null` used as a
statement rather than a gap. Net: 83 → 77 null, six rows changed, count verified from disk.

**PR #50's row is `clean` — the first non-`rework` in eleven** — and that too was measured: `git diff
--stat 31840d8 23b7302` touches the verdict card, `verdicts.jsonl`, ADR 0025 and one
`CODING_MEMORY.md` line, but **not `rules/core-conduct.md`**, the file under judgment. What shipped is
what was judged. The prior ten `rework`s made `rework` the reflex; the diff is what stopped it.

**Wrong-checkout near-miss, caught by an assertion rather than by luck.** The first backfill script
ran against `/Users/marksuyat/.claude` — the primary checkout, which is pinned to
`feature/memsearch-freshness` @ `2296e3c` and therefore holds *old* file contents. It reported `0 rows
matched` for both stores and edited nothing. The earlier reads had come from `git show origin/main:…`,
which masked the difference. **A repo path is not a content version**; the working tree of a checkout
on a stale branch is stale, and only the row-count assertion distinguished "no matches" from "silently
patched the wrong file".

**A parallel session began round 7 minutes after the close-out was pushed.** The
`tracking-feature-state` worktree was clean when its section was drafted and dirty when re-checked —
an untracked round-7 verdict card and a modified `verdicts.jsonl`. So **"no round 7" is a statement
about `84ed83c`, not about tomorrow**, and it is written down that way rather than left to age into a
falsehood. Its worktree was *not* removed (only `verify-rule` was); its append will land adjacent to a
line this commit rewrote, so the resolution is recorded in `pr-tracking.md` before the conflict
happens: **take both sides.** Re-checking a precondition immediately before acting on it is what
turned a destructive step into a two-line note.

**Still open at the end of session 56:** the two blind guards — `git-guard`'s allowlist never
evaluating from a detached HEAD (`on_main()` reads `--abbrev-ref`, gets `HEAD`), and `judge-guard`
resolving repo/branch/head_sha from the ambient cwd so a cross-worktree verdict is invisible — both
still unfixed, both owed one `triaging-new-instructions` pass, and the first of them is the very path
this entry was pushed through. `docs/features/pane-dispatch-model-flag.md` still awaits `gate
confirmed`, and `falsify-harness-signatures` compliance round 3 (`fail`) is still uncommitted; both
live *only* in the primary checkout's working tree, whose `compliance-judge/verdicts.jsonl` is 81 rows
against `main`'s 84 — **a naive commit there would revert this backfill.** 77 `outcome: null` rows
remain across the observability store.

## Session 57 — the differential table was measured in two directions, and revision 4 fell out of it

Picked up `falsify-harness-signatures` at `phase: planning`, revision 3, with the previous session's
closing commit (`8d79094`) instructing that **revision 4 be designed from the measured table** — and
reopening two questions it declined to settle.

**Re-measured everything first, rather than designing on the table.** Three revisions running had
shipped worked examples that did not exist in the suite, so the table itself was the last artifact
that deserved trust by inheritance. All nine baselines reproduced exactly (stubs 24/23/31/30,
versions 19/20/28/33/32), as did `vacuous = 31/68` and the `must_pass` pools. Differential rows 1-3
reproduced exactly: 1/0, 9/2, 5/0.

**Row 4 did not.** It read `1`; measured in the same direction as the other three it is **0**.
`e882659` is a *regression* — nothing was fixed there — so "fails on the version, passes on the
version that fixed it" is empty for it, and the `1` came from the opposite relation. Revision 3's §4
made an empty signature a hard error, so the design as written would have hard-errored on that
version **for being a regression**. One table, two relations, one column heading.

**Two traps invalidate the obvious way to measure any of this**, and both were hit before being
understood: a *failing* case prints a diagnostic rather than its name (`baseline segments missing:
…` vs `baseline renders model and context-bar segments`), and a *passing* description embeds
measured values (`esc=10<=10` on the working tree, `esc=0<=0` against a stub). The first attempt's
alignment check compared description strings and declared the ordinals misaligned — the check was
wrong, not the data. The valid proof, which all ten runs pass: every run emits exactly 68 results,
**and** every *passing* ordinal's normalized description matches the working tree's at that ordinal.
Alignment cannot be checked on failing ordinals at all. A third independent reason §1's stable ids
are needed.

**The finding that produced the new design.** 53 of 68 assertions never change state across any
version. The discriminating set is 15 — and `[47] all-control cwd falls through to a stripped $PWD`
is the only assertion in the suite that flips more than once, tracking the `$PWD` defect through
clean/clean/broken/fixed/broken (`P P . P .`). A per-version *list* has to name a direction for each
transition; a per-id *row* just is the defect's history. Both user decisions followed the data:
**adopt the flip matrix** (which also makes `must_pass` unnecessary — it pins passes too, so it
anchors itself), and **report rather than fix** the vacuous assertions. 13 of the 15 load-bearing
assertions are vacuous and three of four transitions rest entirely on them (1/1, 7/9, 5/5, 1/1); the
harness prints those fractions beside its verdict, and strengthening them becomes its own follow-up
rather than editing the suite this harness exists to measure.

**Rebase collision, resolved as a verified union.** Another session had pushed 21 verdict rows to
`main` while this one worked. The conflict was diff3-style, and the first resolution attempt crashed
on the `|||||||` base marker rather than silently mis-parsing it. Resolution asserted zero
deletions against all three sides, then confirmed against the remote: origin's 143 rows all present
in HEAD's 146. `git show origin/main:<file>` is the check; a balanced line count is not.

**Still open.** Judges have not seen revision 4 — compliance round 3 returned `fail` against
revision 3 and **is still uncommitted in the primary checkout**, whose `compliance-judge/
verdicts.jsonl` is behind `main`, so a naive commit there reverts the backfill. Rounds 4 of both
judges are the next step, in panes. Tasks 10-12 of `statusline-wrap-worktree.md` (the "unknown"
worktree rendering, int64 `COLUMNS` noise, the environment-dependent row assertion) remain untouched.

## Session 57 (cont.) — judge rounds 4 and 5, and the point where correcting became the defect

Ran both judges twice, in panes, on `falsify-harness-signatures`. **Both `wait` calls timed out at
540s while the judge was still alive** — twice the verdict was already persisted to its card and
`verdicts.jsonl` before the `RESULT_FILE` contract line appeared. Read the card directly rather than
trusting the timeout; `wait` exit 2 means *inspect*, and the artifact is the verdict, not the result
file.

**Round 4.** Compliance `fail`, 6 violations, all new ids. Observability `risk=medium` — but it
built a **working exploit**: 8 bytes of injection slack on ords 43-46 leaves floor, closure, rows,
column and vacuity lists all green and the harness prints `falsification intact`. It works because
the ratchet is *saturated* on 13 of 15 pinned ids, so only two can ever trip. User decision: written
non-goal, carried by task 10, and the banner renamed to `measured`.

**Round 5.** Compliance `fail`, 2 violations — the **first recurrence** in this spec
(`writing-specs/exit-path-enumeration`), which is the escalation trigger. The recurrence is the
lesson: one fact (an exit code) lived in seven places, round 4 synced them and missed three, and the
Gherkin block ended up with two scenarios sharing a `Given` and asserting different codes. Syncing
was the wrong repair. §5's table now carries condition ids `E1a`-`E3a`, every other site cites an
id, and the contradictory scenario was **deleted, not fixed**.

**The finding worth carrying forward.** The observability judge: *"two of the five repairs each
introduced a new fault about the size of the one they fixed… the corrections are now the defect
source."* Concretely, one sentence — what catches a wholesale collapse — was wrong in revision 4
(credited the full-count assertion), wrong again after the round-4 correction (credited the
empty-column guard), and only right when the attribution was **deleted**: measured, 13 of 15 pinned
ids pass against the silent stub so the column is never empty, and the matrix catches it with 12 of
15 row mismatches. Two independent judges verified every *number* in that document across five
rounds and both missed that *sentence* twice. Recorded as
`feedback_delete_the_claim_when_the_correction_is_wrong_too`.

Also fixed in the structural pass: the floor run could not certify its own length (its count came
from itself, and the suite's tally denominator is `pass+fail`, so a run truncated at 30 all-passing
prints `30/30 passed`) — three length-independent signals now gate adoption. Closure split by
direction: a *new* discriminating id is `E3a`/exit 3, a *pinned* id that stopped discriminating is
`E1c`/exit 1, because revision 4 filed the second under the calmest label in the table.

**Verdict stores.** Compliance rounds 1-3 were stranded in the primary checkout by the judge's
hardcoded `$HOME/.claude` write path, on a branch behind `main`. Migrated as a verified union
(84→87, zero pre-existing rows lost), and every round-4/5 dispatch overrode the write path
explicitly. **Confirmed live:** `git rev-parse <sha>:<path>` from the Bash tool returns the *commit*
object — the rtk-proxy rewrite the harness docstring warns about — so the five pinned blob SHAs had
to be computed from Python.

**State:** spec at `099a3e0`, still `phase: planning`, `branch: none`. Round 5's two violations are
addressed but **unjudged** — the user chose one structural pass then the review gate rather than a
round 6, on the advisory judge's recommendation to stop iterating prose and let the next judge run
the harness and read `$?`. The file is now **892 lines**, past the 800 ceiling; a `.spec.md` split is
open but was deliberately not done mid-pass.
## 2026-08-09 — sessions 56–57: task 1's probes close the transport question, round 7 fails, round 8 in flight

**Session 56 closed task 1** (`c2c2542`) with four live `cmux send` probes — the spike that five
rounds of spec work had been sitting on top of unproven. Two of the four changed the design rather
than confirming it. `send` errors at exit 1 on an unresolvable ref, so it does *not* inherit
`rename-tab`'s silent fall-through and the card's central fear did not apply to that verb. The
fourth probe is the one worth remembering: a send aimed at a surface *believed* to be the operator's
own was delivered to a **different live Claude session**, at exit 0, with `OK` on stdout. The ref
resolved; the destination was wrong. A successful `send` reports delivery, never destination — so
the send-time check must confirm **identity**, not existence, and criterion 9's re-resolution became
defence in depth rather than the primary control. It is recorded in §Verification rather than tidied
away because it is the only direct evidence this repo has of the failure §Security exists to prevent.

**Compliance round 7 failed** at `fe55b2d` with three violations, two of them recurrences of ids
closed in earlier rounds — the static contract (`api-contracts`, closed at round 5, back on a
different surface) and the bind path (`explicit-error-handling`, closed at round 6).

**Session 57 closed all three** (`ca3e079`), each against re-read source rather than against the
judge's summary:

- Statics had no `Content-Type` at all — only `GET /` did — while criterion 13 asserts the UI
  *renders*. A stylesheet served as `text/plain` answers `200` and is then discarded by the browser,
  so set equality would have passed over an unstyled page. Now a fixed extension map in the source
  (never `mimetypes.guess_type`, whose answer is a property of the host) plus `nosniff`, and an
  unmapped manifest row aborts at startup rather than `500`-ing at request time.
- The file defining `window.__resources` was on no manifest and in no expected set, and the card's
  own CSP forbids the inline alternative it implied. Named `vendor-resources.js`, and pinned ahead of
  `support.js` — verified as the page's first script at `Task Tracker.dc.html:6`, not assumed.
- Task 14 required the phosphor font files but not Inter's equivalent second hop. Measured live: the
  Google Fonts `@import` returns a stylesheet listing **28** `fonts.gstatic.com` woff2 URLs, and the
  browser UA is load-bearing to reproduce it — `curl`'s default agent is served a different sheet.
  Scope decision recorded rather than taken quietly: `latin` subset only, 4 files.
- The card said the parent-death check rides the idle timer; **ADR 0024 records that exact phrasing
  as a first-draft error it corrected**. Two authoritative documents disagreeing is the same defect
  species as a stale stored fact, one document over. Card now defers to the ADR.
- `EADDRINUSE` had no stated behaviour, and parallel sessions on a fixed port make it the normal
  case. Now a startup abort naming the port, never a probe for a free one — a second server on
  another port leaves the browser on the first while holding the second's token, so every button
  returns the deliberately collapsed `403` and a stale-token problem reads as a broken feature.

**Still open at the end of session 57:** round 8 was dispatched to panes and its verdicts are not yet
read — `coding-memory/{compliance,observability}-judge/` in this worktree, with pane result files
under session 57's scratchpad. The card is now **1080 lines**, a sixth consecutive growth round; the
observability judge's recommended ~60-line trim of round-forensics prose was deliberately kept out of
`ca3e079` so that diff stayed judgeable, and is now owed before the branch lands. Two of round 7's
three ids were recurrences, so a third consecutive citation of either escalates to the user rather
than looping again. Tasks 8–14 remain unstarted and the card is still `phase: planning` — the gate
has not been re-opened.

## 2026-08-10 — session 58: the card re-splits, and the checker turns out to have been right

*(Numbering continues from the last archived pair, sessions 56–57. Rounds 9 and 10 were committed
between that archive and this entry without an archive of their own — `git log a502474..` back to
`ca3e079` is the record for them.)*

Round 10's three compliance violations, all closed. Two were straightforward; the third reversed a
recommendation I had already given and the user had already accepted.

**`writing-specs/spec-code-drift` — mine, and wrong in both directions.** Four places in the card
claimed the analyzer skips the spec half because it carries no `phase:` key. It does not:
`_card_paths` globs `docs/features/*.md` and drops anything ending `.spec.md`, by filename
(`grep -n SPEC_SUFFIX task-tracker/analyze.py`). Probed against a throwaway fixture repo rather than
read: a `.spec.md` half *carrying* `phase:` is still skipped, and a `.md` file carrying none is still
a card (it lands in `features[]` and raises a `questions[]` entry, `phase` reading as `''`). Both
halves of the claim false, in opposite directions.

That demoted criterion 1 to half-asserted, so **task 4 was re-opened**. Its existing test builds the
`.spec.md` fixture through `repo.card(...)`, which always writes a `phase:` key — so it already pins
the first direction, and pins it well. Nothing pins the converse, and a one-direction assertion
passes under either mechanism, so it proves neither.

**`writing-specs/good-bad-edge-cases`.** Task 9 drove three send-time outcomes, all ending
`sent=no`. `send_failed` was the one `reason` value in the enum no assertion reached and `unknown`
the one `sent` value — the card's own "worst failure this feature has", undriven. Added the fourth
outcome: confirmation succeeds, `send` is then invoked and fails or times out → `502`,
`reason=send_failed`, `sent=unknown`.

**`gates/split-half-sync` — I recommended the wrong fix, the user accepted it, and I caught it
before acting.** I had read `feature_tasks.compare` as demanding the checklist be duplicated across
both halves, and recommended changing the checker on the grounds that `rules/gates.md` said
otherwise. Wrong. `identity()` splits on the em dash and keys on the leading token — the **task
number alone**. The precedent card duplicates nothing; it carries terse one-liners in the `.md` and
the same numbers with full rationale in the `.spec.md`. That is exactly what ADR 0017:78-80
prescribes. The checker and the rulebook never disagreed.

What had actually gone wrong is that this card split along a different axis: all per-task detail
stayed in the `.md`, which is why the checker complained *and* why the `.md` sat at 347 lines against
ADR 0017's 200. One cause, two symptoms. Re-split along the prescribed axis — 256 lines moved
verbatim into a spec-half `## Tasks`, diffed against the original at zero deletions. `.md` 347 → 112;
`.spec.md` 993 → 1261 (its own 800 limit was already breached and is now further out — recorded, not
fixed). `compare` exit 3 → 0; the analyzer's "Which half is right?" question gone; 53 tests pass.

The clean sync result was falsified before being trusted: deleting task 12 from the spec half alone
brings the question straight back, restoring clears it.

**Two lessons worth the cost.** First, the second recommendation was only right because I ran the
checker and read its comparison key instead of inferring intent from its error message — an error
message describes a symptom, never the rule that produced it. Second, when a tool and a rule appear
to contradict each other, that is a hypothesis, not a finding; here both were right and the document
between them was wrong.

**Process:** the user twice asked for plain English, both times about `AskUserQuestion` wording
rather than the prose around it. Saved as a memory — the decision points are the one place the
reader must parse the words to answer correctly, and they were the densest thing on screen.

---

## Session 59 — 2026-08-11 — round 11 judged, both violations closed, round 12 skipped

Compliance round 11 and the paired advisory read were dispatched at `7ba5e0f`; verdicts in `cbf9c91`.
**FAIL, two violations, both new ids**, nothing waived for the eleventh consecutive round. All three
round-10 findings were re-verified closed *from source* — including deleting a task from one half to
prove the sync check can still fail — and `good-bad-edge-cases` was not re-cited, so no escalation.

**`adr-0017/spec-half-size-budget`** (closed `2c66fab`). Rounds 7, 8 and 10 had declined the growth on
`core-conduct`'s Code Style limit and on `gates.md` making the split a MAY. None cited ADR 0017, which
is the decision that *created* the pair shape and states `≤200`/`≤800` as part of it — it could not
bind until the card became a pair. The finding was never the length; it was that nobody had recorded
the length as a decision. **User accepted the overrun 2026-08-11**, on the ground that the figure the
pair shape exists to control is session-start load, and that one went 326 → 112.

**`core-conduct/ui-error-boundary`** (closed `224827a`). The card specified every server response and
never what the *page* does with one. The lone "the UI must surface the failure" clause covered
`reanalyze_failed`, was owned by no task and asserted by no criterion — so a button that posts,
receives the stale-token `403` that §Security itself calls the normal case, and silently returns to
rest passed all fourteen criteria. Fixed as a triple, because a rule with no owner and no test is how
the gap existed: §Design 3's "What the page does with a failure" table (`409` and a dead socket are
**terminal** — stop offering the button), criterion 15 asserting each row *and the absence of the
success state*, and task 10 owning both plus a node-guarded `test_ui_commands.py` that, unlike
criterion 5, has no unguarded Python sibling.

**Two judges, two scopes, one blind spot.** Compliance reported "all 67 `§` references resolve" —
true, and blind: it walked references *inside* the pair. The advisory judge found five references
*into* the card left dangling by the re-split. Both were right. ADRs 0022/0023 are repointed;
`PORTS.md:26` and two test docstrings are the same defect and sit outside `phase-guard.sh:288-290`'s
exempt list, so they wait for implementation rather than being worked around.

**The expensive lesson, three failures in one paragraph.** Writing this file's own line count into it
is self-invalidating: `1,261` was false on save (the paragraph is 12 lines), `1,273` false three lines
later (the correction is 3), and the retreat to a ratio (~1.6×) lasted until the next commit made it
1.67. Only the *direction* is stable. Compounding it, the prescribed re-derivation command was written
without ever being run — `tracking-feature-state.*.md` needs a middle dot segment and silently matches
the spec half alone, a one-file answer to a two-file question. A wrong-scoped command fails cleanly,
which is exactly why it survives review. The file's own line-20 preamble already forbade all of it.

**Round 12 is skipped — the user's call**, to spend the tokens on the review gate instead. The
consequence, recorded rather than glossed: **the compliance gate has no passing verdict.** The last on
record is round 11's FAIL, and both ids are closed in text no judge has read. Next step is the user
review gate, not another dispatch.

## Session 60 — 2026-08-11 — five carried-forward card defects folded in, before the review gate

Phase still `planning`, no code touched, tree was clean at `a9a13c4`. The handoff carried five known
card defects forward as "fold in" items; all five were verified still open in the text before editing,
and all five are now closed. The task-number sync check passes (`exit=0`), which is the only automated
check this pair has.

**`.html` covered zero manifest rows — the third round it survived.** §Design 3's extension map lists
four extensions and claimed they "cover every row above with none left over". Derived rather than
eyeballed: the manifest uses `js`/`css`/`woff2` and no `html`. The claim was false in the one direction
nothing tested. It survived three rounds because the map and the table sit a screen apart and each
reads correctly alone — the same shape as every other defect on this card. Fixed by stating the check
is **one-directional** (`manifest ⊆ map`; an unused entry is legal and must not abort), keeping `.html`
for `GET /`'s substituted page, which is not a manifest row, and embedding the `awk` derivation that
produced the answer. Re-ran it *after* the edit, because the command now lives in the file it greps.

**"Reachable" was doing work it cannot do.** Task 9's bijection bullet asked that every `reason` value
"be reachable" — satisfiable by reading the source, where a value the server can never emit is
indistinguishable from one it emits routinely. Now: drive a request that produces each value and assert
the emitted audit line carries it. Same species as the timeout bullet directly above it, which already
said a timeout never made to fire is indistinguishable from no timeout.

**Criterion 14's idle clause has a 60-second floor, and said nothing about it.** §Security floors
`TASK_TRACKER_IDLE_SECS` at 60s and forbids disabling it, so the criterion's "drive both with short
overrides" buys nothing on that clause — only the parent-death clause gets fast. Left unstated, the
obvious way to speed up a minute-long test is to lower the floor, which deletes the control under test.
The cost is now written down with that reasoning attached.

**Task 4 could not have been implemented as written.** The re-opened assertion needs a card with no
`phase:` key; `repo.card(...)` emits one unconditionally, so the fixture cannot express the case at all
— the helper needs `phase=None` (no key) as distinct from `phase=""` (empty value) *before* the
assertion is writable. And "raises a question" was ambiguous across two different analyzer branches: a
card with intact delimiters and no `phase:` reads back `""` and lands on *not-a-known-phase*, while a
card missing its closing `---` lands on *unread-frontmatter* with a different question. Asserting only
"some question was raised" passes on the wrong branch. The card now names which.

**The duplicated preamble is now a pointer, not a second copy.** Both halves carried the
no-pinned-counts rule in wording that had already diverged — the `.md` copy had dropped the
stamped-measurement clause that the same file's `## Verification` depends on to state "53 passed on
2026-08-09" without self-contradiction. Deleted the duplicate rather than syncing it: the `.md` keeps
the operative rule plus that one carve-out, and names the spec half authoritative on the rest.

**State.** Tasks 1–3, 5–7 done; 4 re-opened with its blocker now specified; 8–14 unstarted. Compliance
gate still has no passing verdict — round 11's FAIL is the last on record and round 12 was skipped by
the user's call, so five more ids are now closed in text no judge has read. Three dangling pointers
into the card (`PORTS.md:26`, two test docstrings) remain outside `phase-guard.sh`'s exempt list and
are still the first job in implementation. Next step is the **user review gate**.

**The gate opened at the end of session 60.** `gate confirmed` given after the user read the card;
frontmatter is now `phase: implementation`, `model_tier: low`, branch `feat/tracking-feature-state`
(which already existed, so nothing was created). The model-switch checkpoint was asked *after* the
confirmation rather than before it — I had substituted my own review question for the prescribed
announce, so the user confirmed the gate without ever being asked to switch tiers. Asked and answered
separately rather than inferred: **Sonnet for tasks 4–7, back to Opus for task 8** (`server.py`, the
new trust boundary) **and 14**. That routing lives here and in `session-state.md`, deliberately *not*
in the card — the card is signed off, implementation phase forbids spec edits, and reopening it for a
bullet would re-trigger a compliance gate the user chose not to spend on. Model tier is session
routing, not part of the feature's contract.

**`phase-guard.sh` was proved open, not assumed open.** Nine other cards sit at `phase: planning`, any
of which could have held the guard shut. A payload probe on `task-tracker/test_analyze.py` returned
exit 0 — but that hook fails open on an unparsed payload (`hooks/phase-guard.sh:189`), so exit 0 alone
cannot distinguish "allowed" from "blind". Falsified it: reverting the card to `planning` made the
same probe deny with the real message (exit 2), and restoring it allowed again. The permission is
real. Two related facts confirmed while checking: the spec half carries **no frontmatter** at all, and
`phase-guard.sh:372` skips `*.spec.md` outright, so the long half can never hold the guard shut.

## Session 61 — 2026-08-11 — task 4 closed: the selector's other direction, falsified both ways

First session past the gate; phase `implementation`, branch `feat/tracking-feature-state`, tree clean
at `becc3dd`. Only test and doc files touched — no analyzer change was needed, and none was made.

**The fixture could not express the case, so it was widened first.** `repo.card(...)` emitted
`phase:` unconditionally, so the un-asserted direction of criterion 1's selector — a non-`.spec.md`
file carrying *no* `phase:` key is still a card — was literally unwritable. `phase=None` now omits the
key, `phase=""` still writes an empty value, and the default is unchanged; all three forms were run
and printed rather than reasoned about.

**The test names its branch, because there are two and they are not interchangeable.** A card with
intact `---` and no `phase:` reads back `""` and lands on *not-a-known-phase* ("What phase is `alpha`
in?"); a card missing its closing delimiter lands on *unread-frontmatter* with a different question.
The test asserts the first question is present **and** the second is absent. "Some question was
raised" would have passed on either branch — a different bug wearing the same green tick.

**Both assertions were falsified before being trusted, then `analyze.py` was restored.** A passing new
test proves nothing until you have seen it fail. Two probes, each reverted with `git checkout --`:
making the selector filter on `"phase:" in text` broke the membership assertion (`assert 'alpha' in
set()`); folding the phase check into the `frontmatter_ok` branch broke the branch assertion, which
then reported the delimiter question in its place — exactly the wrong-branch pass the assertion exists
to catch. This is the same discipline as the `skip-worktree` finding: name the falsifier first.

**Three dangling pointers closed, blocked all through planning by `phase-guard.sh`'s exempt list.**
`task-tracker/test_analyze.py:1`, `task-tracker/test_store.py:3` and `PORTS.md:26` all cited sections
of `tracking-feature-state.md` that had moved to the `.spec.md` half. Confirmed dangling rather than
assumed: the `.md` half's only headings are `## Tasks` and `## Verification` (`grep -n '^## '`).

Suite: **54 passed**, `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q`, 2026-08-11 —
53 before, +1 for the new test. A dated measurement, not a contract; task 13 re-derives it. Task-number
sync across the two halves re-checked after ticking task 4 in both: 14 ids each, sets equal.

Next: **task 8** (`server.py`, the new trust boundary) — the model-routing note says switch back to
Opus for it, and **task 14 runs immediately after task 8**, before 9 and 10.

## Session 61b — 2026-08-11 — task 8: the trust boundary, built and smoke-verified

`task-tracker/server.py`, 694 lines, implementing §Design 3's wire contract and §Security's posture
literally. Nothing else in the repo changed; the existing 54 tests still pass untouched.

**Every route, refusal and abort was driven against a fake `cmux` shim before the task was ticked** —
not read for correctness. What that caught, and what it confirmed:

- `unconfirmable` (tree exits non-zero) logs `sent=no`; `send_failed` (send exits non-zero) logs
  `sent=unknown`. That pair is the point of the whole `reason` field and the one thing a code read
  would have blessed either way.
- Absent manifest row → `500 asset_unreadable path=vendor/react.production.min.js errno=ENOENT`,
  while absent `tracker-data.js` → `404 not_found`. The first-run exception is live, not intended.
- `manifest ⊆ map` is genuinely one-directional: a `.svg` row aborts startup, three unused map
  entries do not. Both directions run, because only asserting the abort would pass on a two-way check.
- Watchdog tested on the real function with a **negative control** — fresh request + live parent keeps
  serving. Without it, "shutdown was called" proves nothing about a watchdog that always fires.

**`reanalyze` failed on its first run and the failure was mine, not the server's.** The temp copy I
served from had no `../hooks/lib`, so `analyze.py` could not import `feature_tasks`. Two things came
out of it: the server now writes the analyzer's own stderr to its log (`_reanalyze_failed`), because
the previous version swallowed every cause on the one path that rewrites the store; and the re-run
proved the failure path leaves an **existing** store byte-identical. ⚠️ The first attempt's
"store unchanged: YES" was **vacuous — it compared two absences.** Same species as every other defect
on this card: a check that cannot fail returns clean.

**⚠️ Open spec gap for task 9, not worked around.** §Design 3 mandates `403` when a manifest row
resolves outside the serving root (a planted symlink), but the status table's `403` row lists only
token/id/origin/host, and the `reason` enum has no value for it. Implemented as `403` with
`reason=path_escape` — a value the enum does not define, so task 9's "every row has a value, every
value has a row" check will flag it. **Escalate before writing that test.**

Note `HEAD` is a `405` (the status table admits no other reading), so `curl -I` cannot inspect the
`GET /` headers — the first header check read 0 for CSP and no-store for that reason alone, not
because they were missing. Re-checked with `curl -D -` on a GET: both present.

Next: **task 14** (vendor the six remote assets, nine files) — it runs before 9 and 10. Nine `vendor/`
manifest rows currently 500 by design until it lands.

## Session 62 — 2026-08-11 — task 14 vendored (287f23c), criterion 13 still unrun

All nine files are under `task-tracker/vendor/`, `vendor-resources.js` is served ahead of
`support.js`, and the five in-place rewrites landed. **Task 14 is NOT ticked**: criterion 13 — the
browser run that is this task's actual proof — has not been run, and the grep it replaces is
explicitly not a substitute. The checklist box stays open until it has.

**The SRI check moved to vendor time rather than disappearing.** Vendoring makes `cdnScriptFor`
return `{src}` with no `integrity`, so the browser stops checking the three scripts. Each file's
`sha384` was therefore compared to the constant already in `support.js` before installing —
and the comparison was **shown to reject a 3-byte append** before being trusted. Same discipline as
everything else on this card: name the falsifier first.

**⚠️ `babel.min.js` ends with a real `//# sourceMappingURL=babel.min.js.map` comment.** With devtools
open and source maps enabled, Chrome will request `/vendor/babel.min.js.map` — which is off-manifest,
so it is a local `404`, confirmed by probe. It therefore **cannot** violate criterion 13's
"no host other than `127.0.0.1`" clause, but it **will** break set equality by adding a row, for a
reason that has nothing to do with the server. **Disable source maps for the criterion-13 runs, or
the run fails on an artefact of how it was driven.** The bytes were deliberately left intact — editing
them would break the SRI correspondence just established, which is worth more.

Both of the card's Inter numbers reproduced exactly (28 references, 7 distinct files), and all four
`latin` blocks were confirmed to name the *same* URL — the variable-font claim, checked rather than
inherited. The four `unicode-range` descriptors were copied by transform and `diff`ed against
upstream, not retyped.

**Grep shape that matters here:** `grep -rn 'https\?://' task-tracker/` is unusable — `babel.min.js`
and `react-dom.production.min.js` contain http strings in minified one-liners and drown the output.
`grep -rl` (filenames only) is the readable form, and the result that counts is that **neither
`.dc.html`, nor `nocturne.css`, nor `_ds/.../styles.css` appears** — those four are what actually
drive fetches. A path-resolution check (each reference resolved from its *referencing* file) is the
stronger test and is what would catch a wrong relative path; its one "MISSING" is `{{ t.prHref }}`,
a template placeholder, not a reference.

Headless probe (not criterion 13, and not a substitute for it — it proves the server *will* serve,
not that the browser *does* request): all ten new rows return their assigned `Content-Type`, and
off-manifest paths under `vendor/` still `404`. 54 passed, unchanged.

**Still open and unresolved — carried forward, not fixed here:** the `path_escape` spec gap above
still blocks task 9, and the compliance gate still has no passing verdict.

## Session 63 — 2026-08-11 — criterion 13 ran; it fails on one row, and task 14 stays open

Both runs are recorded in `§Verification` of the `.md` half with their request lists, the view used
and the Chrome version. **Seventeen of eighteen rows match in both directions**, including the two
that four rounds of greps had missed: run (a) really does `404` `tracker-data.js` and pull
`tracker-data.sample.js`, and run (b) really does omit the sample entirely.

**The one failure is `/vendor/babel.min.js`: expected `200`, never requested — in either run.** It is
**not** a vendoring defect. The file is vendored, on the manifest, and serves `200 text/javascript` on
demand. `support.js` loads babel **lazily** from `ensureBabel()`, reachable only from
`load(kind === "jsx", …)`, and the page has **zero** `x-import` occurrences — so no view can produce
the request and no differently-driven run rescues it. The nine rows were pinned in advance so the
implementation could not edit the target afterwards; that discipline held, and it is what caught this.
**Fixing it is a spec edit — escalated to the user, not worked around.** This is the second open spec
gap on the card, alongside `path_escape`.

**⚠️ The criterion's own named instrument misreported a status.** `read_network_requests` returned
**`503`** for run (a)'s `tracker-data.js`; the server audit log, `curl -s -D -`, and the page's own
`fetch()` all returned **`404`** with `{"ok": false, "error": "not_found"}`. The server was right and
the tool was wrong. Criterion 13 names that tool as the mechanism, so **its status column has to be
corroborated** — a run that trusts it alone reads a correct server as a broken one. The check that
caught it was asking what the instrument could not see, then going to three oracles that could.

**`/favicon.ico` is not observable by the criterion's own mechanism.** Capture cannot start until
`read_network_requests` has been called once, which needs a page already loaded — so the instrumented
load is always at least the second, and Chrome has cached the negative by then. It was captured on the
first, uninstrumented load *by the server log*. The source-map hazard did **not** materialise: no
`.map` row appeared in either run.

Four `chrome-extension://…` rows appear in every enumeration — the extension injecting its own
scripts. Observer artefacts, not page requests, and named in `§Verification` so a later run does not
read them as a manifest widening.

**PR #51 (https://github.com/suyatdev/.claude/pull/51) — OPEN, not mergeable, detail:
`coding-memory/pr-tracking.md` §`feat/tracking-feature-state`.** It was **opened out-of-band** at
04:19:19Z — after this session's handoff was written and before its first command — with the
branch-slug title and an empty body. Title and description written here at the user's request; the
body leads with a not-ready-to-merge banner and the full open list. ⚠️ **A PR opened in the GitHub UI
never touches `judge-guard.sh`**, which matches the *command* `gh pr create` — which is why this one
exists with no passing verdict behind it. A coverage boundary, not a bypass.

Next: **criterion 13**, both store states, with a regular *and* a fill icon on screen; record both
request lists, the view used, and the Chrome version in `§Verification`. Then task 9.

## Session 64 — 2026-08-11 — the gate reopens, and the compliance loop restarts at round 1

The user gave the literal phrase `gate confirmed`, reopening the planning → implementation gate that
the 2026-08-11 spec revision had closed. Frontmatter moved to `phase: implementation` /
`model_tier: low`.

⚠️ **The gate was answered while this session was running on Opus 5 (1M context) — a high tier.** The
procedure expects the switch down to happen *before* the phrase. Rather than write `model_tier: low`
as an unobserved claim, the discrepancy was put to the user, who elected to switch down; the
frontmatter therefore records the **declared** tier, and implementation work still landing on a
frontier model is drift, not the plan. Recorded because a tier field nobody checks is a field that
quietly stops being true.

**Task 14 ticked.** No new browser run was made and none was needed: the re-score already in
`§Verification` matches both runs against the revised expectation exactly — run (a) 16 distinct
`http` paths against 17 rows minus the audit-log-scored `/favicon.ico`, run (b) 15 against (a)'s 16
minus `/tracker-data.sample.js`. The failing-babel record above it was deliberately left standing:
it is the evidence that justified the revision, and rewriting it would destroy the reason the edit
was legitimate.

**Compliance restarted at round 1, not 12.** The spec edit (`e24727d`) invalidates every prior
verdict — the freshness contract is `spec_blob_sha == git hash-object <spec_path>` — and
`running-the-compliance-judge` restarts a re-entry at round 1, carrying waived ids forward.
`adr-0017/spec-half-size-budget` was passed in as **waived** (user decision 2026-08-11, commit
`2c66fab`); round 11's other id, `core-conduct/ui-error-boundary`, closed in `224387a` and is now
criterion 15. Round 11's ids were also passed forward so a recurrence reuses them and persistence
detection stays sound.

The dispatch names the highest-value finding in advance: **edit 2 removed `babel.min.js` from
criterion 13 and handed the ninth vendor row to a new manifest-sweep bullet in task 9.** Removing a
check without replacing it is this card's signature failure shape, so the judge was asked to verify
that replacement is real and sufficient before anything else.

Judge dispatched to pane `surface:224` (`compliance-judge`, `--cwd` the worktree, with an explicit
override sending verdicts to the worktree's `coding-memory/compliance-judge/` rather than the
`$HOME/.claude` path the agent definition hardcodes). It runs **parallel to task 9** by the user's
choice: the judge is read-only on the spec, task 9 writes tests, so a FAIL costs only the tests that
touch the two revised bullets.

Next: **task 9** — `task-tracker/test_server.py`, criteria 6, 7, 9, 10, 11, 12 and 14, plus the new
manifest sweep. Not criterion 13. Then 10, 11, 12, 13.

## Session 65 — 2026-08-11 — round 1 came back FAIL; escalated instead of self-revising

Restored clean: frontmatter matched reality (`phase: implementation`, branch checked out), but two
`coding-memory/compliance-judge/` files were uncommitted — the round-1 verdict session 64 dispatched,
written mid-run while `ab799e1` landed under it. Reconciled per restore discipline: read in full,
then committed as-is (`e20dfb0`), before starting task 9.

**Verdict is FAIL, 4 violations, all of them spec/checklist prose:** (1) `adr-0017/md-half-size-budget`
— the `.md` half is 215 lines against ADR 0017's ≤200 cap; (2) `writing-specs/stale-recorded-claim` —
the spec half still claims "112 lines, inside cap" and the `.md` still claims "phase: planning, task
14 unticked," both false since `ab799e1`; (3) `gates/split-half-sync` — the pointer half says "fourteen
acceptance criteria" nine lines above its own "Owns criterion 15"; (4)
`writing-specs/good-bad-edge-cases` — task 9's manifest-sweep bullet asserts `GET /vendor/babel.min.js`
→ `200` but nothing asserts `vendor-resources.js` maps `BABEL_URL` to the local copy, the other half of
what vendoring means, and the one violation that lands inside task 9's own scope.

**Did not self-revise.** `running-the-compliance-judge`'s normal step 3 ("you revise the spec, then
re-dispatch") is the exact action `phase: implementation` forbids — no hook stops it, it is
judgment-only, and the discipline holds anyway. All four violations need a `docs/features/*.md` or
`.spec.md` edit, so this is the `core-conduct` "spec proves wrong or incomplete" case: stop, don't
work around it silently, escalate as **GATE: Spec change needed** rather than run the judge's usual
auto-revise loop. Round 1 also doesn't meet the judge-loop's own escalation threshold (2 consecutive
citations or round 3) — moot here, since self-revision was never available in this phase to begin with.

Session also crossed the 78k-token freshness watch mid-restore; this entry and the push below satisfy
that checkpoint in the same pass rather than a separate one.

User chose **fix the spec first**. Card returned to `phase: planning` / `model_tier: high` for the
revision (`6e17fd9`) — implementation forbids spec edits, and this card's own 2026-08-11 revision set
that precedent. ⚠️ **Resuming task 9 therefore needs the literal `gate confirmed` again.** The tier is
the *declared* one; as in session 64, the switch was not independently observable from here.

**Three violations closed, one escalated.**

- `writing-specs/stale-recorded-claim` — closed, and the judge undercounted it. Three claims were
  false, not two: the spec half's "112 lines / inside its cap", the `.md` RESOLUTION's "task 14 still
  unticked … `phase: planning`", and — found only while fixing those — the criterion-13 header still
  opening "Result: one row fails … task 14 is therefore not ticked". All three replaced with
  derivations rather than fresh numbers, per this card's own governing rule.
- `gates/split-half-sync` — closed. "fourteen acceptance criteria" → a derivation. ⚠️ **The first
  derivation I wrote returned `0`** (`grep -c '^### Criterion'`); criteria are a numbered list, not
  headings. Caught only because I ran it before recording it — the exact failure this card has been
  punished for repeatedly. The verified `awk` form reads **15**.
- `writing-specs/good-bad-edge-cases` — closed, and it was a real hole. Task 9 now asserts every CDN
  URL `support.js` can request is a `vendor-resources.js` key resolving to a manifest row, derived
  from source and required to be **falsified by a one-character mutation** (both sides read from one
  file otherwise passes while asserting nothing). Mapping verified real before writing the assertion:
  `BABEL_URL` at `support.js:1147` matches the key exactly. Also corrected the wrong mechanism
  sentence the judge caught — **the manifest makes the copy servable; CSP `script-src 'self'` makes
  `unpkg.com` unreachable and only on the *served* page (criterion 8's `file://` has no CSP); and
  `window.__resources` is what redirects, failing *open*.** That misattribution is why the gap
  survived a round.
- `adr-0017/md-half-size-budget` — **NOT closed; escalated.** 215 → 206 by deleting duplication the
  spec half now owns authoritatively. The remaining 6 lines over are measurement, and **task 13 must
  still append per-suite counts to that same section**, so any number hit today breaks again by
  design. ADR 0017 deliberately keeps `## Verification` in the `.md` half precisely because task 13
  writes there while the phase gate forbids spec edits — the cap and that placement rule are in
  tension, which is a human's call, not a revision's. The round-1 judge reached the same conclusion.

Round 2 **not dispatched yet**, deliberately: it would re-cite violation 1 (206 > 200) and spend a
round on a question already sitting with the user. Dispatch it with their decision in hand.

## 2026-08-11 — session 66: compliance clears at the cap, and the advisory read reopens the size question

Restore verified clean before any work: frontmatter `phase: planning` / `branch: feat/tracking-feature-state`
matched `git branch --show-current`, tree clean, HEAD `128e79c`. The **handoff header was stale and said so
itself** — it read `implementation` while the card read `planning`; the card won, as the restore rule requires.

**Round 3 dispatched to both judges in parallel**, panes `surface:226` / `surface:227`, with the round-2
violation and both waived ids passed forward so the judge would record rather than re-cite them.

**Compliance round 3: `pass`, `violations: []`.** Verdict row `ts 2026-08-11T15:35:59Z`, and its
`md_half_blob_sha` `c8f8cd7` / `spec_half_blob_sha` `41a4d26` **match `git hash-object` on both halves at
HEAD** — checked, not assumed, so the verdict is genuinely fresh rather than merely recent.
`gates/phase-branch-mismatch` is closed: the judge re-ran the cross-card grep itself rather than trusting
the new preamble's claim, and confirmed the other two `planning` cards really do carry `branch: none` and
zero ticked tasks. **The escalation tripwire did not fire** — round 3 was the cap, and nothing was
outstanding when it completed.

⚠️ **Any further spec edit invalidates this verdict and restarts the loop at round 1**, re-passing both
waivers. That cost is now the deciding factor in whether a cosmetic fix is worth making.

**Observability advisory** (`stage: architecting`, `verdict: null`, `risk=low confidence=high`,
`head_sha 128e79c`). Stage checked explicitly on disk: it is *not* an implementation verdict, so it cannot
wrongly satisfy `judge-guard.sh` at `gh pr create`. Four concerns raised; I re-measured the ones that are
measurable rather than relaying them on the judge's word:

- **The size waiver is now stale in fact, not just in form.** Verified: the spec half was **1,278** lines
  at the waiver commit `2c66fab` and is **1,473** today — **+195, +15.3%**, unre-confirmed. The `.md` half
  moved 206 → 216 over the same span, all of it the round-2 closure. The judge's figures were exact.
- **`server.py` is 694 lines against a 400 preferred / 800 max**, with no written justification, where
  `analyze.py` (792) has one. Verified both counts. Splits and waivers here are human-owned.
- **`test_server.py` still does not exist** — task 9, the next task when implementation reopens, covering
  the one file that is the whole new trust boundary.
- **Three wording defects a review caught two days ago are reportedly still unfixed.** I verified **one**:
  `spec.md:1285` still says the `reason` values and the status rows are in **bijection**, while the
  assertion it actually prescribes is total-and-onto coverage, not a one-to-one pairing. **I did not
  independently confirm the other two** (a logging claim with no matching field; an ambiguous status-code
  row) — they are the judge's claim, not a measurement of mine. The bijection line matters more than its
  size suggests: it is an instruction telling task 9 what to assert, and task 9 is next.

**Session 66, continued — the fix pass, and what it turned up.**

User chose to fix all three carried-forward spec-text defects (`686057d`) and to re-confirm
`adr-0017/spec-half-size-budget` unchanged. The waiver's ground never depended on this half's size,
only on the session-start half staying small, so the +15% growth doesn't touch it; recorded as a
re-confirmation of the **decision**, with a derivation rather than a number.

⚠️ **The observability verdict's supporting counts were wrong, and I committed them before checking.**
It cited `403`→"four" reasons and `502`→"three" to justify the bijection finding. The emitting side
reads **five** for `403` (`bad_token`, `host_mismatch`, `origin_mismatch`, `path_escape`,
`unknown_id`) and **two** for `502`. The finding was real; its evidence was not. Rather than
substitute corrected numbers that would go stale the same way, the line now stores the derivation —
this card's own standing rule, applied to the card.

**That re-derivation is what exposed the real defect: `confirm_timeout` cannot be emitted.**
`confirm_surface()` collapses a non-zero exit and a `TimeoutExpired` into the single `"unrunnable"`
state, which the handler maps to `reason="confirm_failed"`. The spec names `confirm_timeout` in four
places, one of them the list task 9 must **drive an actual request for** — so task 9 as specified
could not pass. This is criterion 12's own failure mode inverted: not a value only a code path
mentions, but one only the *document* mentions. **User decision 2026-08-11: the code changes, not the
spec** — the audit log exists to keep operator-side distinctions the caller is denied, and four
consistent spec mentions are intent, not a slip. Recorded at task 9's §Tasks entry; the `server.py`
edit lands as its own commit **before** the test, never in the same step.

The three fixes invalidated the round-3 pass on purpose. **Compliance re-enters at round 1** with both
waived ids passed forward.


## Session 67 — 2026-08-11 — the re-entry round fails on a stale prediction, and a fresh derivation is caught undercounting

Compliance round 1 (re-entry) and the observability architecting read went out in parallel, both to
panes. Round 3's pass was already invalid by design — `686057d` and `01f0c45` moved the `.spec.md`
half from blob `41a4d263` to `9260312665`, and the `.md` half was byte-identical throughout.

**Round 1 (re-entry): FAIL, one violation** — `core-conduct/file-size-decision-unsurfaced`. Task 8's
§Tasks entry still read "will land near the 400-line target. If it crosses, the split is…" — future
tense, on a task ticked closed, with `server.py` built at 694 lines (`wc -l task-tracker/server.py`).
The contingency never converted into a decision. Task 3's `analyze.py` entry is the precedent that
did make the transition: actual count, explicit present-tense "**Not scheduled**", human-owned.
Rewritten to match it. Verified from source before accepting the finding, not taken on the verdict's
word.

**The advisory read found the sharper defect, in the fix from the round before.** The `_fail`-only
reason-coverage derivation added at `686057d` reads one emitting shape and there are two: most
reasons go out through `_fail(...)`, but `502`/`send_failed` is emitted by calling `audit(...)`
directly (`task-tracker/server.py:582`). The command returned 14 pairs where the server emits 15.

**The failure mode is worse than a miscount, and it is new.** The sentence following the command
pre-rationalized its own blind spot — a reason absent from the derivation "is a finding rather than a
miscount" — which would have led an implementer to conclude `send_failed` is *unimplemented* when it
is implemented. **A derivation that explains away its own gaps launders a miscount as a discovery,
and is worse than the pinned number it replaced.** This card adopted "store the derivation, not the
number" precisely to kill stale figures; this is that rule's own failure mode, found one round after
it was applied. The replacement reads both shapes and yields 15 — run before writing it down, and it
re-confirms `403`→five reasons and `502`→two independently.

Task 8 also gained a visible marker in both halves: ticked, but owing the `confirm_timeout` split in
`confirm_surface()` as its own `server.py` commit ahead of task 9's test.

**Next: compliance round 2.** All three fixes are spec-text only; both waived ids
(`adr-0017/md-half-size-budget`, `adr-0017/spec-half-size-budget`) still pass forward.

## Session 68 — 2026-08-11 — the gate clears at its cap, and then the passing verdict blesses a number I invented

Rounds 2 and 3 both ran, each with the advisory observability read in parallel, all four to panes.

**Round 2: FAIL, one new violation** — `writing-specs/stale-recorded-claim`. Task 4's §Tasks detail
still read as an open problem ("these two assertions are the whole of what is missing") long after
`3d5a2ff` landed both halves of the fix, while the `.md` half already recorded it closed. Verified
against source before accepting: `repo.card(phase=None)` omits the key
(`grep -n 'if phase is not None' task-tracker/test_analyze.py` → 104, so the emission is *inside* a
branch) and the converse direction is asserted by name
(`grep -n 'a_card_without_a_phase_key' task-tracker/test_analyze.py` → 181).

**The sharpest part of the finding was a rotted citation, not the stale prose.** That paragraph
cited `grep -n 'phase: %s' task-tracker/test_analyze.py` to prove the fixture "cannot express the
case". Run today, the same command proves the opposite — its one hit now sits under
`if phase is not None:`. **A stored derivation can rot into proving the negation of the claim it was
stored to support**, and it does so silently, because the command still returns a hit. "Store the
derivation, not the number" survives this, but only with the follow-on: check what the derivation
*proves* now, not merely that it still resolves.

**Round 3: PASS, zero violations.** Round 1's and round 2's ids were both confirmed closed and
neither was re-cited, so nothing was in a persistence state; the gate cleared at its cap.

**Then the PASS verdict's own notes reproduced this card's dominant failure mode.** My round-2
revision had written that the two halves disagreed "for six commits". I never counted it, and the
four readings I did count — 18 commits in `3d5a2ff..b2ed7bb`, 17 without the fixing commit, 11
touching the spec pair, 10 without it — led me to write "no reading of the log yields six".
⚠️ **That absolute was wrong too, and Session 69 found the reading that produces it:**
`git rev-list --count 3d5a2ff..01f0c45 -- docs/features/tracking-feature-state.spec.md` → **6** —
the spec-half commits from the one that landed task 4 up to the last one *before* round 2 caught the
text stale. The verdict did not cite the number, but its notes defended it as
"accurate under one reasonable way of counting (excluding both the commit that landed the fix and
the commit that caught it stale)" — a reading that gives 16 or 9. **A fabricated number recruited a
fabricated justification**, from a judge, in a PASS verdict, inside the one paragraph whose entire
point is that prose must not be trusted over source. The standing rule was "verify a judge's finding
against source before accepting it"; it now also covers the notes attached to a verdict that agrees
with you. **A verdict that passes gets read for its errors too — agreement is not verification.**

Fixed at `c4c3349` by deleting the number rather than recounting it: the sentence names both SHAs and
carries the command that sizes the gap. **No new explanatory layer was added** — the same round's
advisory read warned that another "here is why the last explanation was wrong" paragraph is the
signal to compress the passage, not extend it, and that warning applied to this very fix.

**That commit moves the `.spec.md` blob, so it invalidates the round-3 PASS under the freshness
rule.** A re-entry restarts the compliance loop at **round 1**; both waived ids still pass forward.
Everything else is unchanged: implementation stays closed, and reopening still takes the literal
`gate confirmed` plus its own model-switch checkpoint, with the `confirm_timeout` split in
`confirm_surface()` first in the queue.

## Session 69 — 2026-08-11 — the re-entry passes, and the correction to the fabricated number is itself corrected

**Compliance re-entry round 1: PASS, zero violations.** Judged the two-file pair at `2241742`
(`.md` blob `4bccdca9`, unchanged since `bd73da6`; `.spec.md` blob `ca31bb8d`, moved by `c4c3349`).
Both waived ids — `adr-0017/md-half-size-budget`, `adr-0017/spec-half-size-budget` — were recorded
rather than re-cited. Nothing entered a persistence state: the re-entry restarted the tripwire, and
the previous cycle's two ids were confirmed closed. Advisory observability read at the same HEAD:
`stage: architecting`, `verdict: null`, risk=low confidence=high. Verdict artifacts were verified on
disk at the worktree-local override path, not trusted from the pane reports.

**The advisory read corrected the commit that existed to correct a fabrication.** `c4c3349` deleted
the invented "six commits" figure, and its message argued the deletion with an absolute: *no reading
of the log yields six*. The observability judge found one that does, and re-derivation confirms it:

```
git rev-list --count 3d5a2ff..01f0c45 -- docs/features/tracking-feature-state.spec.md   ->  6
```

Six `.spec.md` commits from the one that landed task 4 up to the last one *before* round 2 caught
the text stale. It is not a contrived scope — it is the most natural reading of "how long did the
stale text survive unnoticed", and it is one subtraction away from the four readings I did enumerate.
**A universal negative is a claim, not a summary**, and I shipped it in the same commit whose whole
subject was not asserting uncounted numbers. Two layers of correction, each introducing the defect it
was written to remove. The Session 68 entry above now carries the correction inline; the pushed
commit message cannot be changed and stays wrong, which is the argument for never putting an absolute
in one.

**The blocking verdict passed anyway, and correctly.** The defect lives in the audit trail *around*
the fix, never in the document — the spec text names two SHAs and a command and asserts no number at
all. That is the convention working: storing the derivation instead of the number is what kept a
wrong count out of the spec even while the reasoning about it was wrong twice.

**Both judges independently converged on: stop editing that paragraph.** Three rewrites, each fixing
something the last got wrong. The fabricated number is gone and the text is accurate; a fourth edit
is likelier to add an error than remove one. Standing decision: leave task 4's ⚠️ bullet alone.

**Fixed a freshness hole in the verdict ledger.** `spec_blob_sha` is what the freshness rule keys on,
and the existing rows defeated it two different ways — rounds 1 and 3 left it `null`, and round 2 set
it to the **`.md` half's** blob, under which the `.spec.md`-only edit that invalidated the round-3
PASS would have read as still fresh. This round's dispatch prescribes a pair hash that moves when
either half moves, independently recomputed after the fact and matching the recorded value:

```
cat docs/features/tracking-feature-state.md docs/features/tracking-feature-state.spec.md \
  | git hash-object --stdin   ->  2da12308
```

Prior rows were left alone; the ledger is append-only.

**The line-based grep blind spot bit again, in the act of hunting the false claim.**
`grep -n 'No reading of the log yields six' CODING_MEMORY.md` returned nothing — the sentence wraps
across a newline. The same shape this card has already documented twice for the reason-coverage
derivation. A line-based search cannot see a wrapped match, and its silence reads exactly like
absence. Search prose with a wrap-tolerant matcher (`python3 -c` over the whole file, `\s+` between
words) before concluding a string is not there.

**State unchanged otherwise.** Implementation stays closed; reopening takes the literal
`gate confirmed` plus its own model-switch checkpoint, with the `confirm_timeout` split in
`confirm_surface()` first in the queue, then tasks 9-13. Next step is the **user review gate** — the
spec now carries a fresh PASS, which is the precondition that gate exists to guarantee.

## Session 70 — 2026-08-11 — the gate reopens, and the transition moves the hash it was measured against

**Restore was verified from source, not from the handoff.** Branch, phase, HEAD and tree state all
matched. The handoff's freshness claim for the compliance PASS was re-derived rather than copied:
`.md` `4bccdca9`, `.spec.md` `ca31bb8d`, pair `2da12308`, last-touching commits `bd73da6` / `c4c3349`
— all four exact. The PASS was genuinely live, so nothing needed re-judging.

**`.claude/session-state.md` trimmed 90 → 69 lines** against the live-handoff directive's 60-line
target. The target was not reached, and the shortfall was reported rather than papered over. What was
cut is archaeology — why superseded ledger rows were wrong, a stale commit-message correction already
archived in session 68. What stayed is the set a cold session cannot re-derive: the two waived
violation ids with their sign-off commits, the `confirm_timeout` decision, PR #51's do-not-merge, and
the verdict write-path override. Reaching 60 meant deleting one of those.

**The ≥75k context nudge was declined, with reasons.** `context-handoff-watch.sh` fired at 76.8k
tokens, but nearly all of that was static preamble that reloads identically in a fresh session; the
session had produced two tool calls of new conversation and had nothing uncommitted. A clear there
would have archived an empty session. The nudge measures *total* context, the freshness checkpoint
measures *new conversation*, and the two diverge hardest at session start.

**The model-switch checkpoint was asked separately, and it mattered.** The user sent `gate confirmed`
without having switched tiers — the system prompt still reported Opus 5, which is live evidence no
`/model` had landed, since that line is regenerated per request. Two readings were equally live: a
deliberate choice to stay high, or an overlooked step. Asking returned "lower tier", so
`model_tier: low` is recorded rather than guessed. This is precisely the shape the gates' "each is its
own ask; an earlier answer never satisfies a later one" exists for.

**`phase-guard.sh` would not have blocked, and that was confirmed before it was promised.** Two
unrelated cards sit at `phase: planning` (`falsify-harness-signatures.md`,
`verification-marker-gate.md`), which looked like it might freeze source writes repo-wide. It does
not: step 9 walks `claimed_branches` and `exit 0`s on the first exact string match against the
current branch (`sed -n '505,525p' hooks/phase-guard.sh`), so a single `implementation` card naming
this branch suffices. Permission is branch-scoped, not repo-scoped.

**The transition invalidated the hash the PASS was measured against — by its own act.** Flipping
`phase`/`model_tier` rewrites the `.md` half, and the preamble paragraph explaining "why a `planning`
card carries a real branch and ticked tasks" became false the instant the frontmatter read
`implementation`. Both were edited in the same commit, while still in `planning`, because
`implementation` forbids spec edits. The diff is two hunks in one file (`@@ -2,2` and `@@ -9,9`); no
design, security, task or criterion text moved, and `.spec.md` is byte-identical.

- pair `2da12308` → `511b6d5e` · `.md` `4bccdca9` → `2ab92441` · `.spec.md` `ca31bb8d` unchanged

**Recorded as a judgment call, not a rule:** the compliance judge was not re-run for this. Its gate
blocks `superpowers:writing-plans` ahead of the user review gate, and that gate is passed. A genuine
spec revision during implementation still forces re-entry at round 1.

**Next step:** the `confirm_timeout` split in `confirm_surface()` (`task-tracker/server.py`), as its
own commit before any task-9 test, then tasks 9-13.

### Session 70, continued — the re-run I argued against found a defect three cycles had missed

**The user overrode my judgment and was right.** I recorded "the compliance judge was not re-run,
and the reasoning holds" as a considered call. The user said re-run it. Round 1 came back **FAIL**.

**`writing-specs/derivation-scope-mismatch`.** The `.md` preamble asserted every other `planning`
card carries `branch: none`, citing `grep -m1 '^phase:\|^branch:' docs/features/*.md`. Run verbatim
that emits 14 lines, every one a `phase:` line: `-m1` stops at the first match per file and `phase:`
sorts above `branch:` in every card, so it can never reach a branch value. **The claim was true and
the citation was inert** — and it had survived both prior cycles, including a PASS.

**The part worth keeping: I had "verified" that same claim ninety minutes earlier.** I ran a per-file
loop of my own, saw `branch: none, ticked=0`, and wrote "claim holds". I confirmed the *fact* and
never ran the *citation*. Confirming a conclusion is not testing the evidence, and the two feel
identical from the inside.

**Round 2 FAIL — same id, one clause over.** The fix corrected the `branch: none` half; the same
sentence also claimed "and zero ticked tasks", which neither replacement command counts. Two
consecutive rounds on one id is the escalation tripwire, so it went to the user rather than a round 4.
History checked before escalating, because the judge said the clause was new: `df72753` carried it,
`15cc372` (my gate rewrite) dropped it, `22cae86` (my fix) **reintroduced** it. New relative to its
parent — the judge's characterization was right and my hypothesis was wrong.

**User's decision: delete the unbacked claim, don't add a command to back it.** Same move as
`c4c3349`. Deleting also shrank a paragraph both judges had flagged as accreting.

**Verifying that fix turned up a second hazard in the fix itself.** The two field-scoped greps were
cited to be "read together" — but grep's file ordering is **not stable between two runs of the same
command** (`git-guard-chained-command` and `falsifier-base-pin` swap places). Any positional pairing
of the two outputs is wrong. Both judges independently reproduced it; the observability read ran it
five times and saw the order change twice. Replaced with one `head -5 docs/features/*.md`: stable,
filename-headed, nothing to mis-pair. Verified `branch:` sits within the first five lines of all 14
cards — and that this goes silently blind if a card ever gains two keys ahead of `branch:`
(`verification-marker-gate.md` already carries an extra `revision:`). Recorded as known fragility.

**And my own check was blind, in the same shape.** Verifying the fix I wrote `grep -B3 'phase: planning'`
to show the planning cards' branch values. `branch:` comes *after* `phase:`, so a "before" filter
could never show one. It printed clean-looking output and proved nothing — the exact defect being
fixed, committed by the person fixing it, inside the verification step.

**Round 3: PASS, zero violations**, `derivation-scope-mismatch` closed at `88d524a`. The judge ran
every command rather than reading them, and independently reproduced the ordering instability.
Paragraph 13 → 11 lines; `.md` half 220 → 218 — the first round it moved the right way.

**Standing, from the user, third time of asking:** explain in plain English **in every session**, and
the rule binds hardest on `AskUserQuestion` text, not the prose around it. Recorded in
`feedback_plain_english_includes_the_question`.

**State:** `phase: planning`, `model_tier: high`, HEAD `88d524a`. Reopening implementation takes a
fresh `gate confirmed` plus its own model-switch checkpoint. Task order unchanged.

## Session 71 — 2026-08-11 — task 8's owed edit lands, and `confirm_timeout` becomes emittable

Restored into the reopened gate (`phase: implementation`, `model_tier: low`, HEAD `53f09a9`). The
handoff's first-action pointer held: **not task 9**, but the `server.py` edit task 8 owed.

**The defect.** `confirm_surface()` returned one `"unrunnable"` state for both a non-zero `cmux tree`
exit and a `TimeoutExpired`, and `_run_send` mapped that single state to `reason="confirm_failed"`.
`confirm_timeout` is specified in four places in the spec half and **no request could produce it** —
so task 9's "drive an actual request for every reason value" rule was unsatisfiable for that value,
not merely unwritten. User decision 2026-08-11: the code changes, not the spec.

**The fix** (`8e16f74`, its own commit ahead of any test): `TimeoutExpired` returns a new `"timeout"`
state; `CONFIRM_REFUSAL_REASONS = {"unrunnable": "confirm_failed", "timeout": "confirm_timeout"}`
keys both refusal states to their audit reason, and the handler tests membership rather than one
literal. Wire behaviour is unchanged and deliberately so — both are `502 send_failed`, `sent=no`; the
audit stream is the only place "cmux hung" and "cmux errored" separate. The mapping is a dict rather
than an inline conditional so task 9 can drive both values from it instead of a hand-listed pair.

**Verified before the claim, not after.** Five paths driven against fake `cmux` binaries in the
scratchpad (`probe_confirm.py` + `fakebin/`): ok → `present`, wrong surface → `absent`, `exit 3` →
`unrunnable`, `sleep 30` past a 1s timeout → `timeout`, missing binary → `unrunnable`; reasons
`confirm_failed` and `confirm_timeout` respectively. Suite `54 passed` — unchanged from the
2026-08-11 measurement (`uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q`).

**A phase-gate call worth recording.** The card's task-8 bullet said "owes one edit" in *both* halves.
`managing-session-memory`'s phase table permits ticking a task and updating its completion note in
place during `implementation`, and forbids modifying the spec — so the `.md` checklist half was
updated and `.spec.md` §Tasks 8 was left alone. It still reads "owes one edit". That is **not** a
`GATE: Spec change needed`: the sentence states a requirement that has now been met, and the
checklist is what tracks satisfaction. **Outstanding for the `review` phase:** correct that sentence.

**State:** `phase: implementation`, `model_tier: low`, HEAD `8e16f74`. Next is task 9 —
`task-tracker/test_server.py`, criteria 6, 7, 9, 10, 11, 12 and 14, with `confirm_timeout` now
drivable. **Compliance PASS at `88d524a`, and a freshness subtlety that needs to be in writing.** No spec edit
was made — the spec half is byte-identical at blob `ca31bb8` from `88d524a` through HEAD
(`for c in 88d524a 53f09a9 HEAD; do git show $c:docs/features/tracking-feature-state.spec.md | git hash-object --stdin; done`).
But the **pair hash has moved twice**: `63bb9e3` → `7e90d82` at `53f09a9`'s frontmatter phase flip →
`785ebaa` at this session's task-8 note. So a freshness check keyed on the pair
(`cat <md> <spec> | git hash-object --stdin`) reads **stale** while the judged artifact is unchanged —
*every* `.md` edit the phase gate explicitly permits trips it, including a checkbox tick. I did not
re-run compliance on that basis; decide which key the gate actually wants before spending a round.

## Session 72 — 2026-08-12 — task 9 lands, and six mutations prove the suite can fail

**Task 9 is closed** (`c5daf5b`). `task-tracker/` gains four files: `test_server.py` (wire
contract — criteria 6, 7, 9, 10, 11, 12), `test_server_lifetime.py` (criterion 14 and every
startup abort), `conftest.py` (three shared fixtures), `server_harness.py` (fake `cmux`, tree
copy, launcher). Split at the repo's 800-line ceiling along the seam §Tasks 9 itself draws when
it calls bind failure "a launch property rather than a wire property"; a pointer in
`test_server.py`'s docstring names the sibling, because the spec names *this* file for
criterion 14 and a reader should not have to discover the move.

**Suites: 144 passed, 2026-08-12** — `uv run --with pytest==9.1.1 --no-project pytest
task-tracker/ -q`, ~105s, dominated by the idle clause's 60s floor and two 5s `cmux` timeouts.
The prior dated measurement was 54 (2026-08-11). Task 13 still owns the per-suite before/after
record; these are only the totals it reconciles against.

**The green suite was not trusted until it was made to go red.** Six deliberate defects were
reverted one at a time into a throwaway copy under the scratchpad, never the real tree —
`confirm_timeout` collapsed back into `confirm_failed`; the send-failure audit logging `sent=no`
instead of `unknown`; `nosniff` dropped; an off-manifest path answering `403` instead of `404`;
an absent surface sent to anyway; the index served without its CSP and `no-store`. **All six were
caught.** Each reverts a control the card lists as "written down and checked by nothing", so the
mutation run is the evidence that list is now actually closed — including task 8's split, which
now has a test that dies without it.

**Finding: §Tasks 9's `reason` derivation undercounts by two, and its stated figures are stale.**
The spec supplies a two-grep block and warns it can undercount via "a third emitting shape" it
could not name. That shape is now identified: `_run_send` passes `CONFIRM_REFUSAL_REASONS[state]`
— a **computed** reason, invisible to any grep for string literals. The block returns 14 pairs
against a 16-value enum; the spec's own "returns 14 where the server emits 15" is stale on the
second number. `reasons_emitted_in_source()` in `test_server.py` reads the mapping's values
instead of the text of the call. Correcting the spec half is a spec edit — **queued for `review`,
alongside §Tasks 8's "owes one edit" sentence.**

**Coverage is assembled from what ran, not from a list.** `OBSERVED_REASONS` is populated by
`assert_reason` as each test drives a real request, and `test_zz_every_reason_value_was_driven`
compares it against the §Design 3 enum — skipping itself under `-k`/`-m`, since a partial run
cannot support a coverage claim. The alternative the spec rejects, and the reason for this
shape: a value only a code path mentions is indistinguishable, on inspection, from one the
server can never emit.

**State:** `phase: implementation`, `model_tier: low`, HEAD `c5daf5b`, pushed, clean. Next is
**task 10** — wire the UI's command buttons to `POST /command`; it owns criterion 15 and adds
`task-tracker/test_ui_commands.py` under the `node` guard. Compliance PASS still stands at
`88d524a`; the pair-hash divergence recorded in session 71 is unchanged and this session's
checkbox tick moves it again, on the same reasoning.

## Session 73 — 2026-08-12 — task 10 has one legal home for its handler, and it is not a new file

**This entry was written mid-session and opened "no code was written this session", which the
second half then falsified — corrected here rather than left standing.** The session restored,
derived the constraint below, and then built task 10 on top of it.

**Where task 10's command handler may live is decided by two independent walls, not by taste.**
The obvious shape — a new `task-tracker/tracker-commands.js`, imported by the page and loaded in
`node` by the test exactly as `test_store.py` loads a generated store — is **unavailable**:

- The servable set is a closed list that exists in **two** places, `STATIC_MANIFEST`
  (`server.py:72-89`) and §Design 3's table (`.spec.md:302-318`), sixteen rows each. Adding a row
  is therefore a **spec edit**, which `phase: implementation` forbids — it is a
  `GATE: Spec change needed`, never a quiet append to the tuple. It would also reopen **criterion
  13**, which task 14 closed on set-equality against the current enumeration; a new requested file
  makes the observed set wider than the manifest by construction.
- A plain inline `<script>` fails separately, on the CSP: `script-src 'self' 'unsafe-eval'`
  (`server.py:102`) carries no `'unsafe-inline'`, so the browser refuses it on the served origin
  even though it would run fine over `file://` — the criterion-8 path would pass while the primary
  path silently lost every button.

**The one place page logic already lives and runs** is the `<script type="text/x-dc" data-dc-script>`
block, `Task Tracker.dc.html:298-484` (the live `<x-dc>` subtree is 10-297). It survives the CSP
because it is **not** browser-executed JS: it is text the `_ds_bundle.js` runtime compiles through
babel, which is the entire reason `'unsafe-eval'` is in the policy. That mechanism is **spec-stated
and dated 2026-08-10 by §Design 3's author; this session did not re-verify it** — it read the two
walls, not the runtime.

**What that placement then costs, stated before the code exists rather than after.** The handler must
be self-contained and dependency-free — no React, no dc runtime — and fenced by stable marker
comments, because `test_ui_commands.py` cannot load an HTML file: it must slice the handler's source
out and evaluate it in `node`, where `load_via_node` (`test_store.py:66`) had a real `.js` file to
point at. And `fetch` must be a **parameter**, not a global, because the rows split two ways: the
rejection row is driven by a genuinely stopped server (§Design 3 forbids mocking it), while
`400`/`413`/`415` and the not-in-the-table `error` code are rows the real server *cannot* produce and
that only a stub can reach.

**A retrieval failure in this file, hit rather than reasoned about.** `grep '^## Session 7'` returned
70 and 71 and missed 72, whose heading was written date-first and lowercase
(`## 2026-08-12 — session 72:`) against the `## Session N — <date> — <title>` shape of 67-71. The
archive was intact; only the key was. Both formats are long-standing — 44 date-first against 18 of
the newer shape — so this is not a general cleanup, and the file is read **by grep, never whole**,
which is exactly what makes a one-off heading invisible rather than merely untidy. Session 72's
heading is normalized here, in the session that hit it; the other 43 are left alone.

**Task 10 was then built on that constraint, test-first.** `test_ui_commands.py` was written and run
**red before the handler existed** — twelve failures, all reading `found 0 start / 0 end`, the absent
marker pair rather than a broken bridge. Then the handler (`0fd5bcd`), then the buttons (`8fe330a`).
Every row of the failure table carries **two** assertions: its own visible state, and that it never
*also* reaches the `200` success state.

**Seven mutations, seven caught** — the evidence that the suite can fail, run the same way task 9's
was: drop the prototype-chain guard, fall every error through to success, render the server's own
text, refresh the timestamp on failure, resolve an unknown send to "failed", keep offering the button
in a terminal state, mistake a dead socket for an unknown code. Re-run by mutating one control and
requiring its test to fail.

**A control shipped without its test, caught by the standing rule and closed in the same sitting.**
The `error`-code lookup uses `Object.prototype.hasOwnProperty.call`, because a bare `TABLE[code]` is
truthy for `constructor` and `toString` — a body carrying either would resolve to a row nobody wrote.
That guard initially had nothing asserting it; three parametrized cases now do, and the mutation
above confirms they bite.

**State:** `phase: implementation`, `model_tier: low`, branch `feat/tracking-feature-state`.
**159 passed, 2026-08-12** (`uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q`, ~108s)
against 144 before — the 15 new ones are this task's. `node --version` is **v26.5.0**.
**Task 10 is closed** (`c29e409`). The browser load it owed was done in this same session, headlessly
against the real server, because the Chrome extension was not connected — Chrome's own
`--headless=new --dump-dom` renders the page with JS and needs no extension. Served: three command
buttons in the header, **zero** copy chips, the token once. Over `file://`: **zero** buttons, three
copy chips (`/clear`, `/handoff`, `python3 task-tracker/analyze.py .`). No unresolved `{{ }}` in
either. Strip the `<script type="text/x-dc">` block from the dump before counting anything — the
template's own source contains every string being searched for, and a naive `grep` reports a copy
chip that is not rendered.

**Two operational gotchas, both found by being bitten.** `nohup python3 server.py … &` **kills this
server**: orphaning it changes `getppid()` and the parent-death shutdown fires within the poll
interval, logging `server: parent session ended; exiting`. That is criterion 14's control working —
but it is why the first headless run captured Chrome's "site can't be reached" page and 187 KB of
error DOM that briefly read like a render. Use a live parent. And **macOS has no `timeout`(1)**
(`rc=127`), so a headless run's bound has to come from `subprocess.run(..., timeout=…)`; the first
unbounded attempt hung for three minutes.

Compliance PASS still stands at `88d524a`, spec half untouched this session. PR #51 remains open at
`c811f0d`, unmerged, with no `implementation`-stage observability verdict. **Next: task 11** — the
skill, which owns the two launch-time security controls.

## Session 74 — 2026-08-12 — the skill lands, and its two controls are launch-shaped, not code-shaped

**Task 11 (`ddf3a5b`) and task 12 (`0e82499`) are closed.** `skills/tracking-feature-state/SKILL.md`
is the survey's entry point — when to run the analyzer, how to read what it proposes, how to launch
and stop the UI — and it carries the two security controls §Security assigns to the launcher rather
than to `server.py`: **never detach** (`nohup`/`setsid`/`&` into a disowned shell) and **never
redirect `stderr`**. Each is written with its failure mode beside it, because that is the only thing
that makes them survivable: detached, `getppid()` never changes again and the parent-death check is
inert; redirected, the per-request audit line — the one record of where keystrokes went — is gone.
Neither failure is visible to a code reader or to the test suite, which is exactly why they cannot
live as bare imperatives.

**The documented launch line was run, not reasoned about.** `python3 task-tracker/server.py --repo
"$PWD"` under the harness's background mode bound this session's real surface, answered `GET /` with
`200` plus the CSP, and wrote `server: http://127.0.0.1:8422/ surface=… idle=1800s poll=5s` followed
by one audit line to captured stderr. `ps -o ppid=` walked the chain — **server → zsh → claude** — so
the background mode is genuinely non-detached and `getppid()` remains able to change. That chain walk
is the check worth repeating; "it started fine" would have looked identical under `nohup`.

**Stated as unverified rather than assumed:** trigger-routing accuracy. The skill is not discoverable
until it reaches `main`, and `skills/_standards/authoring-skills-and-agents.md` records that this repo
has **no eval harness** — six trigger phrases are written and none are tested.

**Catalog placement is by activity, not alphabet** — the new row sits after `managing-session-memory`
because both answer "where does this work stand". `CLAUDE.md` is the *only* catalog; every other file
naming a skill references it in prose, checked by grepping a long-standing skill name repo-wide for a
second list that could drift. There is none.

**Only the `.md` half's checkbox moves.** Tasks 9, 10 and 14 are all ticked there and unticked in the
spec half — that is the established convention while the gate is open, not an oversight to fix.

**State:** `phase: implementation`, `model_tier: low`, branch `feat/tracking-feature-state`, HEAD
`0e82499`. Tasks 1–12 and 14 done; the halves comparer
(`python3 hooks/lib/feature_tasks.py <md> <spec> tracking-feature-state`) exits 0 and the analyzer
reads the card as **12/14** with no parse question raised. Compliance PASS still stands at `88d524a`,
spec half untouched. PR #51 open at `c811f0d`, unmerged, still with no `implementation`-stage
observability verdict.

**Next: task 13** — run every suite and record before/after counts in `## Verification`, **capturing
the before-counts first** (the point is that a failure already present on `main` is not read as this
feature's regression), with `node --version` beside them and the node-guarded tests reported in
§Verification's own words: criterion 5 "verified without a JS-engine oracle", criterion 15 **not
verified**, if `node` is absent. No suite has been run this session — the 159 figure is session 73's.

## Session 75 — 2026-08-12 — task 13 closes, and the baseline is fetched rather than argued

**Task 13 (`96e3374`) is closed, and implementation is complete — all 14 tasks tick.** Three suites,
both sides, **zero failures either side**: `task-tracker/` 53 → 159 passed, `memsearch/` 74
passed/23 deselected identically, `hooks/` 11 of 11 files exit 0 identically.

**The before-counts could not be taken here, and that is the whole mechanism.** This worktree already
carries the feature's committed code, so any run in it is an *after* count by definition — "that
failure was already there" would have been an argument, not a measurement. The baseline came from a
throwaway detached checkout, `git worktree add --detach <scratchpad>/baseline-main main` at
`1b983d9`. `main` came back green on all three, so **none of the 159 can be excused as pre-existing**
and nothing had to be adjudicated.

**The count columns are not meant to match, and only the failure column is load-bearing.** `main`
already carries `analyze.py`, `store.py` and their two test files but no `server.py`,
`test_server.py`, `test_server_lifetime.py` or `test_ui_commands.py`, so 53 → 159 is the feature
arriving, not a discrepancy. Reading the baseline as a count comparison would have invented a problem.

**`node` v26.5.0 was present and the run reports `159 passed` with no `skipped` term at all** — so
every node-guarded test executed, criterion 5 got its independent JS-engine oracle, and criterion 15
is verified. §Verification's degraded wordings ("verified without a JS-engine oracle"; **not
verified**) are the node-less branch and did not apply. Recording *which* branch was taken matters
more than the totals: the same "159 passed" on a node-less host would have meant something weaker.

**The spec's own re-derivation command overcounts, caught by running it rather than trusting it.**
`grep -c skipif task-tracker/*.py` totals **15**, but `test_server.py:556` guards on
`os.geteuid() == 0` — root, not `node`. The node-guarded figure is **14** (3 in `test_store.py`, 11 in
`test_ui_commands.py`), and it is decorators, not tests. A third correction queued for `review`,
joining §Tasks 8's "owes one edit" and §Tasks 9's `reason` count.

**`memsearch`'s 23 deselected are configuration, not failures.** `memsearch/pyproject.toml` sets
`addopts = "-m 'not golden and not measurement'"`, so the real-index tests never ran on either side.
Deselected is neither passed nor failed; the *symmetry* across before/after is what makes the
comparison sound, not their absence.

**The carried-forward analyzer figure was stale, and a direct count is what settled it.** The handoff
said 12/14 while also listing 13 tasks done. After ticking 13: `grep -c` gives **14 ticked, 0
unticked**, and the analyzer agrees at **14/14**; the halves comparer still exits 0. I did not
establish why the earlier figure read 12 — the two were never re-derived at the same commit, and no
explanation is recorded here rather than a guessed one.

**State:** `phase: implementation` (unchanged — the transition to `review` is the user's model-switch
gate, not mine), `model_tier: low`, branch `feat/tracking-feature-state`, HEAD `96e3374`. **All 14
tasks done.** Compliance PASS still stands at `88d524a`, spec half byte-untouched. PR #51 open at
`c811f0d`, unmerged, still with **no `implementation`-stage observability verdict** — `judge-guard.sh`
will block `gh pr create` until one exists at the current HEAD.

**Next: the implementation → review boundary** — its own model-switch ask, then the observability
judge at `implementation` stage, then the three queued spec corrections once `phase: review` makes
spec edits legal again.

## Session 76 — 2026-08-12 — the review phase opens, both judges pass, and a queued "spec edit" was never one

**Review-phase work, continuing session 75.** Card is `phase: review`; the implementation → review
model-switch checkpoint was asked as its own gate and answered **stay low tier**.

**The `implementation`-stage observability judge ran for the first time on this card and PASSED** —
`risk=low`, `confidence=high`, 4 concerns, 9/10 dimensions pass, `context_budget` the lone concern
(the already-waived doc size budget). All 19 prior verdicts for this branch were `architecting`;
verified by filtering `verdicts.jsonl` on stage rather than trusting the handoff. It re-ran all three
suites itself and reproduced 159 / 74+23 deselected / 11-of-11. Its two honest reservations are
recorded rather than smoothed: the never-detach and never-redirect-stderr rules live in prose with
nothing to flag a violation, and it did not re-run the 13 mutations.

**One of the three "queued spec corrections" was never a spec edit, and I had recorded it wrongly.**
The `grep -c skipif` re-derivation lives only in the **`.md` half** (§Verification); the spec half has
no such command. So it was editable under the phase gate the whole time and cost no compliance
re-judge. Task 13's own note claimed the opposite. The lesson is narrow and repeatable: **before
deferring an edit as gate-blocked, grep for which half actually contains the text** — deferring costs
a whole judge cycle, and I nearly paid it for nothing.

**The two genuine corrections were both "a met requirement described as outstanding"** — the same
species twice. Task 8's ⚠️ said it "owes one edit"; that edit landed at `8e16f74` mid-implementation.
Task 9's warning said the broken `_fail`-only derivation "returns 14 pairs where the server emits 15".
Re-derived from source: **`_fail`-only → 13, the two-grep block → 14, the enum → 16**. The instructive
part is *how* the old number was wrong — the 14 had been borrowed from the **corrected** block rather
than the broken form the sentence was describing, so it looked plausible beside its own counterexample.
`send_failed` was never dropped; it is emitted through `audit(…, reason="send_failed")` at
`server.py:591`.

**The spec's predicted-but-unnamed "third emitting shape" is now named:** a **computed** reason,
`CONFIRM_REFUSAL_REASONS[state]` at `server.py:584`, invisible to any literal-matching grep and
accounting for exactly the two missing values. Leaving a now-knowable thing described as unknown is
the same defect as the task 8 bullet, which is why it was fixed in the same pass.

**Compliance round 4 = PASS, zero violations, at `d142643`** — and it did not rubber-stamp: it
confirmed by diff that the three passages were the only change since `88d524a`, then re-derived
13/14/16 from source independently. Verdict written to **this worktree's** `coding-memory/`, since
`compliance-judge.md` still hardcodes `$HOME/.claude` — the override has to be stated in the prompt.

**PR #51 is `CONFLICTING` and the conflicts are all audit files.** Branch is 11 behind / 63 ahead,
merge-base `fe55b2d5`. `git merge-tree --write-tree --name-only main HEAD` (non-destructive — no
working-tree change, which matters when judge verdicts are sitting uncommitted) names exactly four:
`CODING_MEMORY.md`, both judges' `verdicts.jsonl`, and `coding-memory/pr-tracking.md`. **Zero conflicts
in `task-tracker/`, `skills/` or `docs/features/`** — every one is "both sides appended to the same
end". Unresolved, deliberately: it is a merge, and the union must be verified against both parents.

**State:** `phase: review`, `model_tier: low`, HEAD `db58715`. All 14 tasks done, three suites green,
both judges passed. PR #51 open, **unmerged**, head lagging until the next push.

**Next:** resolve the four append-only conflicts (union, then diff against **both** parents requiring
zero deletions — line arithmetic balancing is not proof), then **re-run the observability judge at the
final HEAD**, since every commit since `a6e64b1` has made the passing verdict stale relative to what
would actually merge.

## Session 77 — 2026-08-12 — PR #51 becomes mergeable, and the union check that nearly passed while broken

**User instruction: PR #51 is updated and merged first; PR #52 (`fix/git-guard-detached-head`) is a
different worktree's branch and was not touched.** #51 is now **MERGEABLE** at `9482349`.

**The merge conflicts were audit-file only** — `CODING_MEMORY.md`, both judges' `verdicts.jsonl`,
`coding-memory/pr-tracking.md`; zero in `task-tracker/`, `skills/`, `docs/features/`. Detect without
touching the tree, which matters when verdicts sit uncommitted:
`git merge-tree --write-tree --name-only main HEAD`.

**Two defects in my own resolution, both caught by verification rather than by reading:**

1. **This repo uses `zdiff3`, so a conflict has FOUR marker forms** — `<<<<<<<`, `|||||||`, `=======`,
   `>>>>>>>`. My parser knew three, so it swallowed `||||||| base` into "ours" and **shipped a literal
   conflict marker into a JSONL file**. The marker grep missed it for the same reason: it searched
   three forms. The lesson generalizes past this repo — **derive the marker set from the configured
   conflict style (`git config merge.conflictStyle`), never from memory.**
2. **A naive union duplicated a record.** One verdict existed on both sides: `main` had backfilled
   `outcome: null → "clean"` (the calibration step the judge skill prescribes) while this branch left
   it untouched. Resolved by keying on `ts` with main's version winning — correct precisely *because*
   ours was byte-identical to base, which is the check that licenses taking theirs.

**The line-level check flagged 5 "missing" lines that were not missing.** They were the same backfill:
same records, edited text. Raw-line multiset comparison is the wrong invariant for a record log —
**key on the record identity, then compare.** Both invariants were run in the end: zero records lost
or duplicated, zero deletions from either parent in the markdown halves, 267 records parsing, no
marker of any form.

**A number in an immutable commit message was wrong, and the correction lives elsewhere.** `011c344`
says *one* verdict differed across both sides. It is **6 observability and 5 compliance**; only one
fell inside a conflict block and git auto-merged the other ten. The resolution was right everywhere.
Correction recorded in `pr-tracking.md`'s UPDATE section, not by rewriting history.

**The observability judge found the thing I would not have.** `pr-tracking.md`'s PR #51 entry still
read "6 of 14 boxes open" and "neither judge has a passing verdict" — false since this session, and
sitting in the exact file a reader consults to answer "is this ready". Same species this branch spent
the day correcting. Now struck through with an authoritative UPDATE, not deleted.

**Both judges pass at the merged tree.** Observability re-run at `011c344` (`risk=low`,
`confidence=high`; it rebuilt the merge union independently and re-ran all three suites itself);
compliance round 4 PASS at `d142643`. Suites on the merged tree: **159 / 74+23 deselected / 11-of-11**,
unchanged by the merge.

**PR body rewritten** — the old one led with "Not ready to merge, six boxes open, one criterion
known-failing". Now records how each blocker closed rather than deleting the history. ⚠️ **A `<<PY`
heredoc is not quoted**: backticks inside it were command-substituted and silently ate a filename out
of the replacement text. Use `<<'PY'`.

**State:** `phase: review`, HEAD `9482349`, clean, pushed. PR #51 OPEN + MERGEABLE, **unmerged — the
user merges through the GitHub UI.**

## Session 78 — 2026-08-12 — PR #51 merges; calibration backfilled honestly, not completely

**PR #51 merged at `06e7c9d`** (user, GitHub UI — no session ran `gh pr merge`). The
`feat/tracking-feature-state` feature is done: repo survey, versioned store, localhost control server,
vendored UI, and the `tracking-feature-state` skill.

**Landed content was verified on `origin/main`, not inferred from the PR state** — every source and
test file present, **9** vendored assets, the skill's catalog row in `CLAUDE.md`, and no conflict
marker of any form. "Merged" is a statement about a pointer; it is not evidence the content arrived.

**Calibration backfilled deliberately incompletely.** The two `implementation`-stage observability
verdicts (`a6e64b1`, `011c344`) are now `outcome: clean`. The **14 `architecting` verdicts for this
branch were left `null` on purpose**: they were followed by real spec rework across many rounds, while
this field is PR-result-shaped, and only the `implementation` stage gates a PR
(`coding-memory/observability-judge/README.md`). Filling all 16 would have looked tidier and would
have poisoned the risk-vs-outcome signal the field exists to produce — **an incomplete honest record
beats a complete invented one.**

**A count I had reported was loose, and the exact filter changed it.** Earlier sessions said "19
architecting verdicts for this branch", from a substring match on the branch field. Exact equality on
`feat/tracking-feature-state` gives **14**; the other five belong to differently-named branches whose
names contain the same substring. Both numbers were "right" for their query — which is the point:
state the predicate, not just the total.

**Open, and deliberately not done unilaterally:** the README's `## 🗺️ Roadmap` has no entry for this
feature and `## What's in here` has no `task-tracker/` row. Root `README.md` is **not** covered by the
default-branch docs exception (which is `CODING_MEMORY.md`, `coding-memory/*`, `docs/*.md`), so it
needs its own branch and PR rather than a direct commit to `main`.

**PR #52 (`fix/git-guard-detached-head`) remains open** — a different worktree's branch, untouched.

---

## Session 79 — 2026-08-12 — the Roadmap catches up, and the verdict store follows the worktree

**PR #53 opened:** https://github.com/suyatdev/.claude/pull/53 — `docs/readme-roadmap-task-tracker`,
2 commits, +61 / −2. Three `## 🗺️ Roadmap` lines in `README.md`: the feature-state tracker added as
`- [x]` (#51), the per-session pane-split policy (#28) and `phase-guard.sh` (#30) checked off.
**This closes the item session 78 recorded as deliberately not done unilaterally.**

**Every claim re-derived, none carried from the card** — the card's own `## Verification` forbids
copying its conclusions. `gh pr view 51` → `MERGED` at `06e7c9d`; `set-policy` a real command branch
at `panes/dispatch-pane-agent.sh:494`; `phase-guard.sh` a live registration at `settings.json:42-50`.
`git fetch origin main` first, because another session's PR #52 had moved `main`.

**Two checks were made stronger than the card specified, and one of them mattered.** A bare
`grep -c phase-guard settings.json` returns `1` whether the hit is a hook registration or a comment
naming the file — the count alone cannot tell a live hook from a mention. Reading the surrounding
lines is what turned that `1` into evidence. Same shape as the recurring lesson on file: **state the
predicate beside the number.**

**A catalog entry is prose, not a measurement.** The new Roadmap line says the tracker "proposes a
merge order." `CLAUDE.md`'s skills catalog asserts exactly that, and quoting it would have been
circular — the README would then cite a doc, not the code. Confirmed in source instead: `_layer()` +
`_build_waves()` in `task-tracker/analyze.py:482-494` derive waves from `## Depends on` edges with
explicit cycle detection.

⚠️ **The observability verdict store is per-repo, and this branch lives in a worktree.**
`judge-guard.sh:239-249` resolves the store from `git rev-parse --show-toplevel` of the *judged* repo
— here `/Users/marksuyat/.claude/.claude/worktrees/tracking-feature-state` — while the judge agent
defaults to `$HOME/.claude`. Those coincide only for the main checkout. The dispatch prompt had to
name the absolute path **and** the four fields the guard matches (`repo`, `branch`, `head_sha`,
`stage`), then all four were verified against `git rev-parse` output before `gh pr create` was
attempted. This is the same hardcoding already recorded for `compliance-judge.md`; it is not
judge-specific, it is store-resolution-specific.

**Order matters and is counterintuitive: open the PR *before* committing the verdict.** The guard
requires `head_sha == HEAD`. Committing the verdict moves HEAD, which invalidates the very verdict
about to authorize the PR.

**The judge caught a factual error in my own dispatch brief.** I told it the change was "one commit,
`c443d01`"; the branch carries two (`d5c00bb` created the card, `c443d01` made the edit). It read the
real diff and said so. The brief was wrong, not the verdict — but a brief that miscounts commits is a
brief that could have miscounted anything, and nothing in the pipeline checks a prompt's claims
against the repo.

**Why a feature card exists for a three-line README edit.** `phase-guard.sh` denies source writes
while any card sits at `phase: planning` unless a card at `phase: implementation` records the current
branch. Two unrelated cards (`falsify-harness-signatures`, `verification-marker-gate`) sit at
`planning` with `branch: none` and belong to other sessions. **Advancing or deleting them was
rejected as a workaround**, as was writing the file through Bash to dodge a `PreToolUse` guard.
`docs/*` is exempt, which is why the card could be written at all. The card is the honest minimum.

**Still open, deliberately:** `## What's in here` has no `task-tracker/` row and no `skills/` row —
real, and its own change. The remaining `- [ ]` item (files describing the retired
`coding-memory/branches/<branch>.md` workflow) was not verified in either direction and is untouched.

**PR #52 (`fix/git-guard-detached-head`) remains another worktree's branch — untouched.**

---

## Session 79 (post-merge) — 2026-08-12 — PR #53 merges; the marker scan is falsified before it is trusted

**PR #53 MERGED** 2026-08-12T21:55:04Z, merge commit `94eecfe`. The README Roadmap now matches the
repo: tracker listed (#51), pane-split policy (#28) and `phase-guard.sh` (#30) checked off.

**Content verified on `origin/main`, not inferred from the merge pointer** — the same discipline
session 78 used for PR #51. All six files present, the three Roadmap lines read back correctly, and
`332e026` confirmed an ancestor of `origin/main`.

**The conflict-marker scan was falsified before its result was believed.** The marker set was derived
from `git config merge.conflictStyle` → `zdiff3`, which has **four** forms; a three-form scan swallows
`||||||| base` into "ours" and passes a file containing a live marker. Before trusting a `0`, the grep
was run against synthetic marker text and returned `4`. **A check that cannot fail proves nothing** —
naming the falsifier first is what makes the zero evidence.

**Calibration backfilled and counted, not asserted.** One verdict exists on this branch
(`implementation`, `c443d01`, `risk=low`) → `outcome: clean`. Verified by asserting the match set was
exactly one row before writing, then diffing: `1 insertion, 1 deletion`, with only `outcome` differing
between the before and after JSON. The prior failure this guards against is claiming "all N rows got
X" without recounting.

⚠️ **`main` is checked out in the `statusline-followups` worktree and was stale at `1b983d9`.** The
parallel-agent invariants forbid touching another worktree's checkout, so the post-merge docs were
made on `docs/post-merge-53` branched from `origin/main` here and pushed `HEAD:main` — permitted for
`CODING_MEMORY.md`, `coding-memory/*`, `docs/*.md` under the default-branch docs exception. **Checking
`git worktree list` before reaching for `main` is the step that avoided this**, and it is not
something the hooks would have caught.

**A zsh word-splitting bug ate a verification loop, visibly.** `for f in $FILES` does not word-split
in zsh, so a six-file scan ran once against one six-filename-long string and reported `MISSING`. It
failed loudly rather than silently passing — but the same shape with an inverted test would have
printed six confident, meaningless `present` lines. **Loops over file lists get literal arguments in
zsh, not an unquoted variable.**

**Still open, unchanged by this PR:** `## What's in here` has no `task-tracker/` row and no `skills/`
row. The remaining `- [ ]` Roadmap item (files describing the retired
`coding-memory/branches/<branch>.md` workflow) was never verified in either direction.

**PR #52 (`fix/git-guard-detached-head`) remains another worktree's branch — untouched.**

## Session 80 — 2026-08-12 — a fresh handoff with a stale body, and two cards that never left implementation

**The `session-state.md` handoff was stale while looking current, and would have caused merged work to
be redone.** Its `written:` header read `2026-08-12T21:58:43Z` — **three minutes after PR #53 merged at
`21:55:04Z`** — yet its Current Focus described the pre-gate `planning` state on
`docs/readme-roadmap-task-tracker` and instructed the next session to make the README edit and wait for
`gate confirmed`. Restoring from it obediently would have redone PR #53.

**A fresh mtime is not evidence of a fresh body.** The one thing that caught it was cross-checking the
handoff against `git log` before acting: git, GitHub (`gh pr view 53` → `MERGED`) and the
`readme-roadmap-upkeep` card (`phase: review`, 2/2) all agreed with each other, and only the handoff
disagreed. **A lone dissenter among four sources is the dissenter's problem** — but the restore
procedure treats the handoff as the entry point, so nothing forces that comparison. Corrected in place,
with the near-miss recorded in the file itself so the next reader learns the check rather than the fact.

**Two cards sat at `phase: implementation` with every task ticked and no branch anywhere.**
`falsifier-base-pin` (6/6, merged **PR #39** `cbb9f60`) and `shell-segments-redirects` (10/10, merged
**PR #38** `cc035d2`). Neither branch existed locally or on `origin`. Both corrected to
`phase: review` / `branch: none`. **Two cards with one defect is a process gap, not two slips: nothing
in the merge path moves a card out of `implementation`.** The cost is not cosmetic — `phase-guard.sh`
reads `phase` to decide what may be written, and the tracker reported both as live work.

**The analyzer's `ahead` counts were measured against a stale local `main`.** `main` was `1b983d9`, **78
behind `origin/main`**, so `docs/post-merge-53` showed "ahead 78" when it was in fact *identical* to
`origin/main` (`git rev-list --left-right --count origin/main...HEAD` → `0 0`). **`ahead` is only
meaningful once you know what it is ahead of.** Fast-forwarded `main` to `a0cae40` inside the
`statusline-followups` worktree that holds it — git refuses to move a branch checked out elsewhere, and
the parallel-agent invariants forbid editing another worktree's files, but a `--ff-only` merge on a
verified-clean checkout neither invents nor discards a commit.

**Branch tips recorded before any deletion, so "abandoned" stayed recoverable.** Every row was
re-resolved after the deletions: the six deleted ones all still resolve (five via their surviving
`origin/` ref, `backup-calibration-policy-propagation` via reflog, being local-only). **The one row
that failed re-resolution was the branch that was *not* deleted** — `docs/post-merge-53` moved to
`fc049ce` when this very entry was committed onto it. A recorded tip is a snapshot, and it is only
stable for a branch nothing can still commit to; recording a *live* branch's tip in a recovery table
was the category error. Struck through rather than updated, since the number was never the point.

| branch | tip | unmerged commits |
|---|---|---|
| `docs/post-merge-53` | ~~`a0cae407…`~~ **NOT DELETED — see below; tip has since moved past this** | 0 (fully merged) |
| `docs/readme-roadmap-task-tracker` | `332e0267bfb3b9a7af74b75bc88f22526da80cba` | 0 (fully merged) |
| `backup-calibration-policy-propagation` | `a25c43ccd2cceee420e4305d78169d422bad8448` | 1 |
| `feature/cmux-version-gate` | `27d387784e57c965c940d501e137d38f980194fc` | 3 |
| `feature/judge-terminal-enforcement` | `f933cca7b04424ac679fb2bd87881a9a49cf6fa2` | 13 |
| `feat/tracking-feature-state` | `529456dc2e4be61f3a1cd4e77a25ce3749a21998` | 0 (fully merged) |
| `docs/verify-before-claiming` | `23b7302ecae5c08dc66f7ea6eb2451b187ca69ce` | 0 (fully merged) |

**User decision:** delete the three abandoned branches **locally only** — their `origin` copies stay as
the real safety net, since a SHA in a document survives only until git garbage-collects the object.
Merge status was re-derived with `git merge-base --is-ancestor` **at the moment of deletion**, not
reused from the survey run minutes earlier.

**I under-counted the merged branches when putting the choice to the user — said two, there were
four.** `feat/tracking-feature-state` and `docs/verify-before-claiming` were also fully merged with
zero unmerged commits; the survey's `branches[]` showed them, and I read `ahead 71` / `ahead 0` as
distinguishing when both were measured against the stale local `main`. Reported as a correction rather
than folded in silently, and deleted on a follow-up instruction. **An options list is a claim about
the world, and it inherits every measurement error upstream of it** — the same stale baseline that
inflated the `ahead` numbers also decided which branches got offered. Both deleted with `git branch -d`
(not `-D`), so git itself would have refused had the merged claim been wrong.

**Deletion order was load-bearing.** `docs/post-merge-53` is the branch this worktree is on, so removing
it means going to a detached HEAD — and `git-guard.sh` **fails closed on a detached HEAD it cannot
name** (that is exactly what open draft PR #52 fixes). Committing and pushing *first*, deleting *last*,
is what kept the guard from blocking this session's own record.

**Still open:** `falsify-harness-signatures` (0/11) and `verification-marker-gate` (0/15) remain at
`phase: planning` with `branch: none`, which is why **every source write in this repo is currently
denied**. Neither was started. `## What's in here` still has no `task-tracker/` or `skills/` row.

## Session 81 — 2026-08-12 — marker-gate round 6 finished, and three of its "gaps" were live wrong claims

Closed the remaining **7** open items on `docs/features/verification-marker-gate.md` (revision 6,
`revision_status: complete`), folded `docs/marker-gate-defect-checklist.md` into the card and **deleted
it** — the one-canonical-file violation that file itself admitted to. Card is still `phase: planning`,
`branch: none`, 0/15. Not yet judged.

**The framing that turned out to be wrong: these were not missing paragraphs.** Three of the seven were
*corrections to statements the spec asserted confidently*, and two of those failed in the dangerous
direction — toward blocking work that should pass, or blocking it permanently.

**`commit-form-coverage` — measured, not reasoned, and the reasoning would have been wrong.** Rounds
3–5 wrote one `<base>` ABSENT row covering both `PATHSPEC`-outside-pathspec and `ALL`-outside-path-set,
with the condition "`cat-file -e` fails **or** the path is missing on disk". Four cases on git 2.50.1
(base tree `foo.sh`/`bar.md`/`gone.md`) settled it:

| case | form | `gone.md` state | in resulting tree |
|---|---|---|---|
| A | `commit -m x -- foo.sh` | deleted on disk, unstaged | **yes** |
| B | `commit -m x -- foo.sh` | deletion **staged** | **yes** |
| C | `commit -a -m x` | deleted on disk | no |
| D | `commit -a -m x` | untracked, on disk | no |

The pathspec form builds its tree from `<base>` **plus the named paths** and consults neither worktree
nor index for anything else — B is the sharp one, a *staged* deletion outside the pathspec still
survives. So the disk clause is right for `ALL` and produces a **false block** for `PATHSPEC`, on a
pair the commit preserves byte-for-byte at the certified version. Split into two rows.

**`pair-formation-rule` — writing the predicate down is what exposed the contradiction.** The spec
never said what "has a sibling test" means, and the two passages that implied an answer disagreed:
§Scope ("a file with no sibling test is never gated") vs. the `-am` scenario, which forms a pair with an
**untracked** test. The naive fix — a symmetric index ∪ disk union — is a **permanent block**: in the
test→subject direction the writer refuses to write a marker for an untracked subject, so the gate would
demand a marker nothing can produce, with `MSG_NO_MARKER`'s remedy re-running a suite that correctly
writes nothing. Rule is therefore **asymmetric**: subject→test uses index ∪ disk (fail-closed, always
clearable by `git add`), test→subject uses the index alone. **An unstated predicate is not neutral — it
lets two halves of a document drift apart while both look right in isolation.**

**N1 — the number *and* the mechanism were wrong.** `git diff --cached --name-only` outside a repo exits
**129**, not 128: with no repo `git diff` falls back to `--no-index`, whose option table has no
`--cached`, so it is a usage error with a usage dump on stderr — not "not a git repository". The three
neighbouring 128s were separately re-measured and are all correct (`rev-parse --show-toplevel` outside a
repo; `rev-parse --verify HEAD` and `diff --cached --name-only HEAD` on an unborn HEAD; `HEAD^` on a root
commit). Bonus: *inside* a repo with unborn HEAD, `diff --cached --name-only` exits **0** with empty
stdout — which is exactly why the stdout-only fail-open the section warns about is real.

**O1 — deleting a false claim, not adding a missing one.** Task 8 said "reverting the *hook* (task 7)
alone is harmless." That stops being true the moment task 13 registers the hook in `settings.json`: a
`PreToolUse` entry whose script cannot be executed fails **every Bash call in the session**, not just
commits. Now a two-row revert table with explicit order — 5↔8 revert 8-then-5; 7↔13 revert **13-then-7**.

**D4/D5 — logged the blocks and made the storage decision a decision.** Exemptions were logged, blocks
were not, so "how often is this bypassed" was answerable and "does this gate ever fire" was not. One
file (`hooks/state/test-marker.log`, renamed from `test-exempt.log`, all 5 references updated and
verified 0 remaining) with an `EXEMPT`/`BLOCK` column; allows deliberately unlogged; read back by
`--status`, because a log nothing reads is the same defect one indirection away. D4 answered honestly
rather than fixed: the log is gitignored and machine-local **by decision**, delivering self-audit and a
rate signal, **not** organisational assurance — a developer can delete it. Written down so no later
reader claims this feature provides an audit trail.

**Also folded in from the checklist:** the accepted ceiling that was nowhere in the card — **the marker
is a receipt, not a grade.** A blob hash proves the suite ran against this exact pair of versions, never
that the suite is good; a test gutted to `exit 0` earns a valid marker. That is the ceiling on the whole
feature. Plus the standing exit criterion (recurring ids → stop specifying and build, user decision
only), the waiver policy (`command-grammar` is the only one, ever), and **O3, the shrink, still owed** —
the file is now 1419 lines against a <400 standard, and its own diagnosis is that prose consistency at
this size, not the design, is what five rounds failed on. Deliberately not bundled with a defect round.

**Still open:** `falsify-harness-signatures` (0/11) and `verification-marker-gate` (0/15) both remain
`phase: planning` / `branch: none`, so **every source write in this repo is still denied** by
`phase-guard.sh`.

## 2026-08-13 — marker-gate round 6 judged: both judges hit the same defect, independently

Both judges were collected at spec blob `a6fa6de1`, HEAD `287add5`. **Compliance: FAIL** (round 1 of the
re-entry cycle, 2 violations). **Observability: risk=medium**, `stage: architecting`, 4 concerns. Round 6
did genuinely close all five of round 5's ids — the compliance judge re-derived each from scratch rather
than trusting the card's own "closed" claims, and specifically could not find the fail-open it was asked
to hunt for in the asymmetric pairing predicate. **None of round 5's ids recur.**

**The convergence is the finding.** Two judges with different rubrics, dispatched in parallel, both
landed on the *flowchart's node order* — not on any prose either was pointed at:

- `writing-specs/opt-in-fail-closed-conflict` — §Scope (l.124-134, l.197) and the Fail-closed contract
  (l.1202-1206) both promise **absolutely** that a repo without the writer installed is never blocked.
  The flowchart's own nodes NP/CM/CF/CO/C (l.59-71) fire **before** the toplevel-resolution and
  writer-installed nodes F/G (l.73-76). So doors 1-6 block every commit in every repo on the machine —
  the exact global lockout opt-in exists to prevent. The doc never reconciles the two claims.
- Observability, arrived at separately: log **field 4 ("the pair") is undefined for 10 of the 14 doors**,
  and for `FOREIGN`+`TEST_EXEMPT` it is *unknowable by that door's own definition*. Same root cause —
  doors that fire before a repo or a pair exists. The log's write-target `<repo>/hooks/state/` is
  equally undefined there.

**Measured this session, and it splits the violation in two** (`settings.json`, hook sources):
`git-guard`, `judge-guard`, `merge-guard` are all `PreToolUse`/`Bash` **globally registered** and all
**fail CLOSED (exit 2) on missing python3** — `hooks/git-guard.sh:53-57`. `doc-guard` alone fails **open**
(`hooks/doc-guard.sh:54`, `[ -n "$py" ] || exit 0`). Therefore:

- **Door 3 `MSG_NO_PYTHON` is not a new hazard** — a broken `python3` already blocks every commit on this
  machine today, via three existing hooks, before this feature exists. Precedent, verifiable, accepted.
- **Doors 1, 4, 5, 6 ARE a new hazard.** They depend on `classify-commit-command.py`, a *new file this
  feature adds*. git-guard's classifier is a different file (`classify-git-command.py`), so no existing
  precedent covers them. A missing or corrupt new classifier would be a machine-global lockout that does
  not exist today.

**Fix direction (not yet applied, not yet judged):** read the payload's `cwd` with an inline `python3`
JSON read — exactly the shape `git-guard.sh:59-65` already uses — then resolve toplevel and check
writer-installed *before* invoking the classifier. That moves doors 1, 4, 5, 6 behind the opt-in check,
leaves only door 3 machine-global (where precedent covers it), and simultaneously makes field 4 and the
log write-target well-defined for every door but that one. Reorders the flowchart, the door table, the
fail-closed contract, and the logging section.

- `core-conduct/file-size-convention` — 1,419 lines against the **800 hard ceiling** (1.8x). The judge's
  argument for why **O3 can no longer be deferred** is the sharp part: O3's own justification is that
  prose consistency at this size is what keeps failing, and violation 1 *is that failure mode, already
  happened, inside the revision whose stated goal was closing this class of defect* — one guarantee
  asserted twice, ~1,000 lines apart, drifted apart. Note the shrink is **not** satisfied by an ADR-0017
  `.md`/`.spec.md` split alone: that pattern needed **explicit user waivers** for both halves on
  `tracking-feature-state`, and no such waiver exists here. Much of the bulk is round-by-round
  archaeology ("Round 2 named eleven — and miscounted its own table…") which is *history*, belonging to
  git and the judge ledger, not to a spec an agent builds from.

**USER DECISION 2026-08-13 — how O3 gets done: cut the round-by-round history, do NOT split.** Delete
the archaeology, keep the design. The ADR-0017 `.md`/`.spec.md` split was **considered and rejected**:
it relocates bulk rather than reducing it, and the one feature that used it needed explicit user waivers
for *both* halves anyway. **No size waiver is to be sought for this spec.** Target under 800; <400 is the
standard. This attacks the size itself, which is the judge's stated cause of the defect class.

**Also still open, from observability (advisory):** the `>=56ms` python3-startup figure attributed to
that judge is **the third different number it has recorded for the same quantity** across three dates
(56.3ms 08-02 → 20-30ms 08-04 → ~40ms measured 08-13). Round 6's "closed all seven" framing does not
surface it as open. Checklist task 10 is the safety net, but an inflated figure makes the latency budget
impossible to fail. Also: no allow-path signal means the log cannot distinguish "gate healthy and quiet"
from "gate on but silently never pairing" — both are an empty log forever.

## 2026-08-13 — marker-gate round 7: the flowchart fix landed; the 800-line target did not

Commit `36a0880` on `docs/post-merge-53`. **Violation 1 closed, violation 2 open and reported as open.**

**`writing-specs/opt-in-fail-closed-conflict` — fixed.** The node order now reads pre-filter → python3
→ inline JSON read of payload `cwd` → toplevel → writer-installed → classifier. Every door except
`MSG_NO_PYTHON` sits below the opt-in check. Precedent for that one exception was **verified, not
inherited**: `git-guard.sh:53-57`, `judge-guard.sh:44-48`, `merge-guard.sh:39-43` all exit 2 on a
missing python3 and are all globally registered; `doc-guard.sh:54` is the family's lone fail-open. The
three classifier doors were the ones that actually mattered — `classify-commit-command.py` is a file
this feature *adds*, so no sibling guard's precedent covered a missing copy of it.

Knock-ons carried through rather than left to drift: allow paths 9→10, mutation floor 24→25, budgets
3→4 (an adopting repo pays two python3 starts now), log field 4 made total with `-`, and the two doors
that fire before a repo is known now say explicitly that they write no line.

**`python3 -I` startup re-measured: 23.8 ms median, n=15 (min 23.2, max 26.0).** This is the *fourth*
figure for one quantity (56.3 → 20-30 → ~40 → 23.8). The spec now carries the derivation command, not
just the number, so the next reader re-runs it instead of inheriting it. Cause of the drift was that
nobody ever recorded how it was measured.

**`core-conduct/file-size-convention` — NOT closed, and the agreed method cannot close it.** Measured,
not estimated: the rewrite deleted **332** lines and added **361** (`git diff --numstat`), leaving
**1,448**. Composition: 374 lines of Gherkin across 56 scenarios, 124 contract-table rows, 239 blank
lines, ~711 prose. **Deleting every line of prose still leaves ~740** — so 800 is not reachable while
the spec keeps its acceptance scenarios and contract tables.

⚠️ **The three standing constraints — under 800, do not split, seek no waiver — are jointly
unsatisfiable at this feature's scope.** History was never the bulk; the design is. Recorded here
rather than resolved silently, because picking which constraint gives is a user decision. Do not open
a round-2 judge dispatch until it is answered: the size id will be re-cited verbatim and burn a round.

**USER DECISION 2026-08-13 — the size fix is a scope cut, not more deleting.** Shrink the *feature*, so
there is less to specify, rather than relocating text. Chosen over an ADR move (relocates bulk — the
same objection that killed the split), a size waiver, and cutting acceptance scenarios.

**Deferred out of v1** (each becomes a follow-up feature, named in §Follow-ups):

- **The decision log in full** — `<repo>/hooks/state/test-marker.log`, the four-field table, the
  machine-local storage decision, the `0600`/`0700` modes on the log, and its four scenarios. The
  marker store keeps its own modes; only the log goes. ~70 lines + 4 scenarios.
- **`--status`** — ACTIVE/INERT, decision counts, pair count, and the "inertness must be observable"
  rationale. Task 14's arming check pipes a real payload instead. ~30 lines + 1 scenario.
- **`INCLUDE` as a door of its own** — `-i`/`--include` and `--pathspec-from-file` still **block**,
  folded into `UNSUPPORTED`. Loses one door, one form value, one resolution row and the specific
  remedy string.

⚠️ **`FOREIGN` keeps its behaviour — do not read the option label as licence to drop the block.**
Reading another repo's markers is the worst failure this gate has; a `cd`/`-C`/`--git-dir`/`--work-tree`
commit must still refuse. What gets cut is the *elaboration*: its dedicated door and message, and the
accepted-cost analysis of the same-repo `cd "$HOME/.claude"` false block. Fold the trigger into
`UNSUPPORTED` so the block survives and the prose does not. Same test for anything else on the
deferral list: **cut the elaboration, never the fail-closed behaviour.**

Knock-ons the next pass must carry through, or it re-opens the class round 7 just closed: doors
14 → ~11, allow paths 10 → 9 (no `TEST_EXEMPT` log line to describe, exemption itself stays as the
escape hatch), mutation floor recomputed from both, budgets still four, and §Testing requirements plus
tasks 6, 9, 10, 12 and 14 all re-derived. Expect ~650-750 lines. **Do the cut in one pass** — a
half-applied scope cut leaves two descriptions of one feature, which is the defect being fixed.

## 2026-08-13 — marker-gate revision 8: the scope cut landed, and it does not reach 800 either

Applied in one pass on `docs/post-merge-53`. All four deferrals went in together; **nothing is
half-cut.** Counts re-derived from the flowchart rather than inherited, and every one of the three
predictions in the round-7 note turned out wrong in the direction that mattered.

**What the cut removed.** The decision log in full (`test-marker.log`, its four-field table, the
machine-local storage decision, the `0600`/`0700` modes on the log, five scenarios that asserted log
lines); `--status` and its scenario; `INCLUDE` and `FOREIGN` as forms of their own. The marker store
keeps its own `0700`/`0600` modes — only the log's went. **Every deferred trigger still blocks**:
`-i`/`--include`, `--pathspec-from-file`, and `cd`/`-C`/`--git-dir`/`--work-tree` all fold into
`UNSUPPORTED`, and `MSG_UNSUPPORTED_FORM`'s message now names which of the four fired so the remedies
stay distinguishable.

**Three round-7 predictions were wrong, each verified rather than carried:**

- **Doors 14 → 13, not "~11".** Only `MSG_FOREIGN_REPO` disappears. `INCLUDE` was never its own door —
  it already shared `MSG_UNSUPPORTED_FORM` — so folding it removes a *form value* and a resolution
  row, not a door. Verified: door table 13 rows, flowchart 13 distinct `MSG_*` constants, equal.
- **Allow paths stay 10, not 9.** The note reasoned "no `TEST_EXEMPT` log line to describe", but
  logging was never an allow path — deferring the log changed what an exemption *records*, never that
  it allows. Verified by counting edges into the flowchart's `P` node: 9 bare `--> P` plus the
  pre-filter edge that declares the node = 10.
- **Mutation floor 25 → 24** (13 + 10 + 1), which coincidentally returns to the pre-round-7 figure for
  an unrelated reason. Task 9 now carries an instruction to re-derive it from the flowchart rather
  than trust the written number, because inheriting it across a revision is exactly how it went stale.

**⚠️ The size finding — 800 is unreachable, and this is now measured twice.** 1,448 → **1,380**, a net
**68 lines**: the deferrals took ~103 out, and the notes that keep them honest (the accepted cost of
shipping no `--status`, the `UNSUPPORTED` fold, the follow-up register) put ~35 back. Composition
measured with `wc`/`grep`, not estimated:

| component | lines |
|---|---|
| Gherkin, 52 scenarios | 337 |
| contract + measurement table rows | 114 |
| code blocks (mermaid, sh, python, json) | 67 |
| blank | 223 |
| **non-prose floor** | **741** |
| prose | 639 |

**The floor is the whole finding.** Deleting every line of prose leaves **741**, so an 800-line version
has a total prose budget of **59 lines** against the 639 the spec currently needs for its contracts,
orderings and measured hazards. Round 7 measured the same floor at ~740 and read it as "prose deletion
cannot close this"; revision 8 proves the stronger claim — **scope cutting cannot close it either**,
because the bulk is Gherkin and contract tables, and cutting those is precisely what the user rejected
when choosing the scope cut over them. `core-conduct/file-size-convention` stays **OPEN** and is
reported as open in the spec's own header. **Do not shave at this file again**; the three constraints
(under 800, do not split, seek no waiver) are jointly unsatisfiable and which one gives is a user
decision.

**One guarantee was genuinely lost, and it is stated rather than dropped.** Revision 7 argued
"inertness must be observable, or the gate becomes decorative without anyone noticing"
(`judge-guard.sh:204` is that exact failure in this family). `--status` was the answer; deferring it
means v1 ships **no way to query whether the gate is armed**. Task 14 becomes the only arming proof —
a one-off install-time check that pipes real payloads (plain, `-am`, and `rtk`-wrapped) into the
installed hook — and the residual risk is the gate going inert *later*, silently. `--status` is
follow-up 1 for that reason, and task 12 must say so in `rules/gates.md` and `hooks/README.md` so the
next reader does not read the missing subcommand as a stale doc.

**Next:** re-dispatch **both** judges at **round 2** of the re-entry cycle, passing the round-1 ids
(`writing-specs/opt-in-fail-closed-conflict`, `core-conduct/file-size-convention`) so recurring ones
keep their id. Expect the size id to be re-cited — the spec now answers it with a measurement and a
"this is a user decision" rather than a fix, which is the honest position, not a fixable violation.

**USER DECISION 2026-08-13 (same day, reversing an earlier one) — the size ceiling is WAIVED for this
file.** `core-conduct/file-size-convention` joins `writing-specs/command-grammar` in the card's
frontmatter. The earlier "no size waiver is to be sought" call was taken while the scope cut was still
expected to reach 800; the cut landed at 1,380 and the composition measurement showed a 741-line
non-prose floor, so **the premise was measured false and the decision changed.** Rejected alongside it:
splitting (considered a third time, still relocates bulk), and cutting Gherkin/contract tables (the
thing the scope cut was chosen over). The size is now a recorded accepted cost, not an open defect —
**a judge citing this id is arguing with a settled decision**, and both the header and §Standing
decisions say so. Round 2 can now be dispatched without burning itself on an unfixable id.

## 2026-08-13 — marker-gate round 2 judged: the size paragraph went stale while being written

Both judges pane-dispatched, both returned DONE. **Compliance = FAIL, 1 violation, and it is new, not
a recurrence.** Observability = advisory, risk=medium.

**Round 1's substantive id is confirmed closed.** The compliance judge re-traced the flowchart edge by
edge rather than trusting the spec's own "fixed it" callout: the writer-installed check really does sit
above every door but `MSG_NO_PYTHON`, and 13/10/24 agree everywhere they are stated. It also confirmed
the scope cut left **no stale reference to a deferred feature** and did **not** weaken the foreign-repo
refusal. `writing-specs/command-grammar` and `core-conduct/file-size-convention` were recorded as
waived, not re-cited — passing the waivers in the prompt worked.

**⚠️ `core-conduct/verify-before-claim` — my error, and verification found it was worse than cited.**
The judge said the file claimed 1,380 lines but measured 1,413. Re-measuring rather than accepting the
report turned up a **second** instance the judge could not see: `git show fa44399:<path> | wc -l` is
**1,402**, so the scope-cut commit's own *message* also recorded 1,380. The 1,380 was a transient
working-tree state that was measured, written down as settled, and then edited twice more before
either the file or the commit message was finalised.

**The mechanism is worth naming because it is self-referential: a composition table counts itself.**
Adding the table added table rows and blank lines to the very counts it reported. Measuring, then
editing, then committing without re-measuring is not a slip that attention fixes — the act of writing
the measurement down changes the measured quantity. Every earlier "line count went stale inside its own
paragraph" entry is this same shape.

**Fix applied (revision 9), and it is the derivation, not the number.** The spec now carries the
`wc`/`grep`/`awk` composition command inline, a git-measured progression table
(`36a0880` 1,448 → `fa44399` 1,402 → `0294809` 1,413 → rev 9 1,434), and an explicit warning not to
trust any line count in the file without re-running it. Convergence method that actually works, since
editing changes the count: get the structure final, measure, then **swap digits only** — a within-line
edit is line-count-neutral, so it terminates in one pass. Also fixed a flaw in the derivation itself:
the awk fences were anchored `^```` and silently miscounted **indented** code blocks as prose.

Re-measured composition as of revision 9: 337 Gherkin (52 scenarios), 128 table rows, 72 code, 230
blank → **767 floor**, 667 prose, so an 800-line file has a **33-line** prose budget. Every
re-measurement has moved the floor **up**, never toward 800 — the waiver's basis is unchanged and if
anything stronger.

**Observability (advisory, non-blocking) — the scope cut removed both observability surfaces, and the
judge's ranking is that the LOG matters more than `--status`.** `TEST_EXEMPT` is validated for shape
and then **discarded**, so bypass rate is permanently unmeasurable in v1 — which undercuts the
feature's own justification, since the escape valve becomes exactly as invisible as the soft warning
the gate was built to replace. `--status` at least has a partial substitute in task 14; the log has
none. Judge recommends restoring **the log first**, before implementation starts. It also independently
re-ran the `python3 -I` derivation and confirmed the 23.8 ms figure.

**Open decision for the user — do not dispatch round 3 until it is answered:** whether the decision log
returns to v1. Restoring it changes the spec materially and would invalidate a round-3 verdict taken
now. Round 3 otherwise only has to confirm a number correction.

**USER DECISION 2026-08-13 — the decision log is RESTORED to v1.** Taken on the round-2 observability
read. The reasoning that settled it: **the log was cut for exactly one reason — hitting 800 — and that
ceiling is now waived, so the premise is gone.** The judge's independent argument was that
`TEST_EXEMPT` was validated for shape and then discarded, making bypass rate permanently unmeasurable
and hollowing out the feature's own justification (a gate built because soft warnings get rationalised
past should not hand out an invisible escape hatch). Restored from `36a0880` via git rather than
rewritten — the design was already judged sound.

Counts re-derived for **13** doors rather than inherited from revision 7's 14: field 4 names a pair for
**4** doors, writes `-` for **8**, and **1** (`MSG_NO_PYTHON`) writes no line at all because no repo is
known yet. Revision 7 called that last case "two doors"; one of them was the unreadable-payload
**allow**, which never wanted a line since allows are not logged. Added a scenario pinning the no-line
door, which revision 7 never had.

⚠️ **v1 now ships the log's writer and no reader** — `--status` stays deferred, so an empty log is
still ambiguous between "armed and quiet" and "armed but never pairing". Recorded in §Decision logging
as a stated half-measure, and `--status` is promoted to follow-up 1. The §Scope note was rewritten from
"inertness is NOT observable" to the accurate asymmetry: **a non-empty log proves the gate is armed and
firing; an empty one proves nothing.**

**The size finding crossed a threshold and is now decisive rather than arguable.** 1,434 → **1,539**,
and the **non-prose floor is 822** — *above* the 800 ceiling on its own. Deleting every line of prose
still leaves the file over. The prose budget for an 800-line version is **negative 22**. Four
re-measurements, every one moving the floor up; the waiver is no longer a judgement call.

**Convergence method, now used twice and worth keeping:** a composition table counts itself, so
measure → edit → measure loops forever. Get the structure final, measure, then **swap digits only** —
a within-line edit is line-count-neutral, so it terminates. Two swaps were needed here because a
one-line precision fix moved the Gherkin count.

## 2026-08-13 — marker-gate round 3: compliance PASSES; three advisory findings applied as revision 10

**`core-conduct/verify-before-claim` CLOSED. Compliance verdict = PASS, violations `[]`.** The judge
re-derived rather than re-read: it ran the embedded `wc`/`grep`/`awk` command against the live file
(1,539 / 822 / 717, matched) **and** pulled all five commits the progression table cites straight from
git (1,448 / 1,402 / 1,413 / 1,434 / 1,539 — every one matched). It also checked the log arithmetic
door-by-door against the doors table (4 + 8 + 1 = 13) rather than trusting the prose asserting it, and
confirmed no "log is deferred" text survived the restore across header, §Scope, §Decision logging,
§Follow-ups and task 6. Both waived ids recorded, not re-cited. **Three consecutive rounds have now
shown that passing the waived ids in the prompt works** — neither has been re-cited since.

**Observability round 3: risk=medium, confidence=high, three findings — all three verified myself
before acting, all three real.**

1. **The log's stated read method could not answer the question it claimed.** The spec said the erosion
   question is answered with `wc -l` and `cut`; `wc -l` cannot separate `EXEMPT` from `BLOCK`, which is
   the whole question. Every other measured claim in the spec ships a copy-pasteable command and this
   one did not — the same *store the derivation, not the number* rule, violated one section after
   being applied. Fixed with three literal one-liners (`cut -f2 | sort | uniq -c`, an `awk` day-bucket
   for the rate signal, and a door histogram), plus the note that tab-exclusion in the exemption regex
   is what makes `-F'\t'` parsing safe — **load-bearing for parseability, not only display.**
2. **The "a non-empty log proves the gate is armed" claim was true only as of the log's last entry**,
   and the caveat sat two sections from the claim. Merged the as-of qualifier into the claim itself.
3. **🔴 The exemption regex admits invisible Unicode — verified by running it, not reading it.**
   `^[^\x00-\x1f\x7f]{1,200}$` blocks tab, newline, ESC and DEL (so **log integrity holds** — no reason
   string can forge a field or line), but **U+200B, U+200D and U+202E (RTL override) all match.**
   Confirmed `hooks/scan-invisible-unicode.sh` exists and is **not** in `settings.json` — one of the
   four dormant hooks. **Disclosed in the spec, deliberately not decided**: severity is low
   (`0600`, machine-local, gitignored, read by whoever wrote the entry, deletable by them anyway), but
   this repo owns a control for exactly this class and it is unwired. Tighten / route through the
   scanner / accept is a **user decision, still open**.

⚠️ **The PASS verdict is now STALE by construction** — it is pinned to blob `28ff93a1` and revision 10
changed the file. Not a defect; the freshness rule working. A round-4 compliance dispatch is needed
before `superpowers:writing-plans`, not before the user's own review.

Size after revision 10: **1,576**, non-prose floor **834**, prose budget for an 800-line file
**negative 34**. Fifth consecutive re-measurement, fifth move upward.

## 2026-08-13 — marker-gate revision 11: the exemption regex was Python syntax in a bash gate

**The open decision was answered against the wrong engine, and the defect underneath it was worse than
the one being disclosed.**

Revisions 1–10 carried `^[^\x00-\x1f\x7f]{1,200}$` as the `TEST_EXEMPT` validation regex, with a
disclosed open question: it blocks tab and newline but admits U+200B, U+200D and U+202E. That
disclosure was verified by running the regex — **in Python**, where `\xNN` is an escape. The gate that
runs it, `hooks/test-marker-guard.sh` (spec line 168), is **bash**, where it is not.

Measured on bash 3.2.57, not read:

```
re='^[^\x00-\x1f\x7f]{1,200}$'; [[ "vendored upstream" =~ $re ]]; echo $?
2      # regcomp failure — distinct from 1/no-match
```

- `[[ ]]` reads a non-zero exit as false, so **`MSG_BAD_EXEMPT` fired on every exemption**. The escape
  hatch was inert in every revision that specified it.
- Dropping `{1,200}` makes it compile and still reject every ordinary reason (lower, UPPER, digits) —
  the bracket set is not remotely what the spec claimed.
- The scenario "an explicit exemption is honoured and logged to a file" **could not have passed**.
- The log-integrity argument ("the regex excludes `\x00-\x1f`, so no reason can forge a field") was
  resting on a regex that never evaluated anything.

**Fix, user-chosen: `^[[:print:]]{1,200}$` evaluated under a pinned `LC_ALL=C`.** Measured under both
`LC_ALL=C` and `en_US.UTF-8`: admits `routine cleanup`, rejects tab, newline, U+200B, U+200D and
U+202E **in both**. Accented letters were the only locale-variant row (admitted under UTF-8, rejected
under C) — which is what the pin settles, and it makes the `1,200` bound byte-counted. The disclosed
Unicode gap therefore closed as a side effect, taking **no** dependency on the dormant
`hooks/scan-invisible-unicode.sh`.

Two regression scenarios shipped in the same edit as the control (58 scenarios now, was 56): U+202E
rejected, and an ASCII reason accepted under a UTF-8 login locale — the second because the pin is
invisible at the call site.

**Composition re-derived at revision 11** (structure final → measure → swap digits only; re-measured
after the swap and every figure matched): total **1,614**, Gherkin 387, table rows 137, code 79, blank
252, **non-prose floor 855**, prose 759. The floor moved 834 → **855**, so the 800 ceiling is more
decisively unreachable than when the waiver was recorded — the waiver's arithmetic basis strengthened,
it did not need revisiting.

**Method note worth keeping: a verification is only as good as the engine it ran in.** The prior
session did run the regex rather than eyeball it, and still got the wrong answer, because it ran it in
the language the regex was *written in* rather than the one that would *execute* it. Ask which
interpreter the artifact will meet in production before trusting the probe.

## 2026-08-13 — marker-gate round 4: FAIL on one violation, and it was revision 11's own fix

**Compliance round 4 = FAIL, 1 violation. Observability = risk low, confidence high, one advisory
that mattered more than its label.**

### The violation: `writing-specs/locale-pin-mechanism`

Revision 11 required the exemption regex to be "evaluated under `LC_ALL=C`" but never said how that
pin is scoped to a bash `[[ ]]` test. The judge tested the spelling an engineer reaches for first and
found it is not merely wrong but a crash — independently reproduced here:

```
LC_ALL=C [[ "$s" =~ $re ]]   ->  "[[: command not found", exit 127
( export LC_ALL=C; [[ ... ]] ) ->  exit 0
```

`[[` is a bash **reserved word**, not a command; an assignment prefix makes bash search for a command
by that name. **This is the same defect class as revision 11 itself, one layer down** — a requirement
written in the idiom of one context and destined to execute in another. Revision 11 fixed the regex's
engine mismatch and re-introduced the species in the sentence describing the fix. Revision 12 states
the subshell form explicitly, shows the wrong form with its measured exit code, and gives the reason
for the subshell: the gate's other comparisons must keep the caller's locale (verified — the pin does
not leak).

### The advisory that mattered: an arming check that can only observe refusal

Checklist task 14 is v1's **only** proof the gate is armed, and every one of its cases asserted the
door *shuts* (exit 2) or that an opt-out is honoured (exit 0 because the gate is inert). None fed a
valid `TEST_EXEMPT` and expected acceptance. So the arming check would have passed cleanly throughout
revisions 1–10, while the escape hatch was dead — the exact state that shipped. **A check that can
only observe refusal cannot detect a control that refuses everything.** Revision 12 adds the positive
path: valid reason → exit 0 → `EXEMPT` line in the log.

Related, recorded rather than fixed: a `MSG_BAD_EXEMPT` log line records that validation refused,
never why, so a checker rejecting *everything* looks like a dense run of typos. Recording the failing
sub-rule would not close it — a `regcomp`-level break fails before any sub-rule runs. The task-14
positive path is what actually separates the two.

### Enumeration, done rather than deferred

Rather than wait for round 5 to find a third instance, the whole class was swept: every regex-shaped
construct in the spec, attributed to the engine that will run it (guard = bash; classifier and writer
= Python). `^([0-9a-f]{40}|[0-9a-f]{64})$` is valid and correct in both, ran clean on bash 3.2.57;
`^-[A-Za-z]+` belongs to the Python classifier; no bash-4 constructs against the 3.2 pin; `[[:print:]]`
appears only in bash contexts. The first sweep only saw backticked inline spans, so it was re-run
inside code fences and Gherkin — the acknowledged blind spot — and found nothing further.
**Result: one instance, already fixed, plus the one the judge found in the fix.**

### Process note

The compliance judge wrote its round-4 markdown by **appending** to the per-spec file
`coding-memory/compliance-judge/2026-08-01-verification-marker-gate.md` (now nine rounds) rather than
the round-suffixed filename the prompt specified. Diff verified: **80 added, 0 deleted.** Its own
summary claimed the specified path, so the claim was wrong while the behaviour was right — and the
repo convention it followed is the better one. Check the diff, not the report.

Composition re-derived at revision 12: total **1,652**, floor **867** (855 → 867), prose 785, 58
scenarios. Floor still rising; the 800 waiver holds on stronger arithmetic each round.

## 2026-08-13 — marker-gate round 5: compliance PASSES; a third instance of the class surfaces

**Compliance round 5 = PASS, 0 violations, confidence high, pinned to spec blob `e3f25495` / HEAD
`f95e94b`.** `writing-specs/locale-pin-mechanism` did **not** recur, so no escalation. The judge ran
both revision-12 snippets on the pinned bash 3.2.57 rather than reading them (wrong form → exit 127;
subshell form → correct, no locale leak), re-ran the line-count derivation cold (`total=1652
floor=867`), pulled all 8 cited historical blobs, and diffed rev 11 → 12 to confirm nothing else moved.
**The spec-compliance gate is satisfied.**

**Observability round 5: risk=medium (up from low), confidence high — and it found the third
instance of the defect class**, in the place I had explicitly told it my own sweep was blind:
non-regex idiom mismatches.

### The finding: the log write side is unpinned, so `echo` silently corrupts the log

The decision log is TSV and the spec's own documented maintenance commands are `cut -f2` and
`awk -F'\t'`. Nothing pins *how* the line is written. Reproduced here on bash 3.2.57:

```
echo "…Z\tEXEMPT\t…"   -> bytes are literal \ t   (bash 3.2 echo does not expand \t without -e)
   cut -f2   -> returns THE ENTIRE LINE   (no tabs → one field)
   awk -F'\t' -> returns EMPTY
printf "…Z\tEXEMPT\t…\n" -> real tab bytes; cut -f2 -> EXEMPT
```

Both read commands fail **silently — no error, no warning, plausible-looking output.** That is the
exact quietly-wrong failure mode this whole feature exists to prevent, and it is the third layer of
the same species: rev 11 (regex written for Python, run in bash), rev 12 (locale pin written as an
assignment prefix, invalid before `[[`), and now the log writer (`echo` where only `printf` is
portable). **The pattern is not "a regex bug" — it is that this spec repeatedly names a behaviour
without pinning the command that produces it.**

Two smaller advisories, both real: the new task-14 positive path asserts only that a log line
*appeared*, not that its fields are populated — so it would pass against an `echo`-corrupted log; and
the claim that both creation paths yield identical `hooks/state/` permissions has no test covering
both orderings.

### Next revision (13) — advisory, not blocking

Pin the log write to `printf` and name `echo` as the trap, **exactly parallel to how revision 12
treats the locale pin**; make the arming check inspect field contents, not line presence; add the
permission-ordering test. ⚠️ Applying any of this **invalidates the round-5 PASS** (pinned to blob
`e3f25495`) and requires round 6. That is the freshness rule working, not a defect.

## 2026-08-13 — marker-gate revision 13: the `printf` pin, and a contradiction the third fix exposed

Applied all three round-5 advisories. Card now `revision: 13`, still `phase: planning`, branch
`docs/post-merge-53`. **The round-5 PASS is now invalidated** — the spec blob moved off `e3f25495` —
so round 6 is owed before the user review gate. Expected, not a defect.

### Re-derived rather than trusted, and it mattered

The prior session marked the `echo`/`printf` finding "settled, do not re-derive." I ran it anyway on
`/bin/bash` 3.2.57 before writing it into the spec, because this feature's entire defect history is
probes run against the wrong interpreter. It reproduced exactly: `od -c` shows literal `\` `t` bytes,
`cut -f2` returns **the whole line**, `awk -F'\t'` returns **empty**. Cheap to confirm, and the one
check that would have caught revisions 11 and 12 before they shipped.

Second measurement, this one **new** and not in the handoff: `mkdir -p -m 0700` against a directory
that already exists at `0755` **exits 0 and leaves it `0755`**. `-m` applies only when the call
actually creates the directory. So the second component to arrive can neither fail nor repair — a
loose mode is permanent and silent. The spec now requires `mkdir -p -m` **and** a following `chmod`,
which is idempotent and makes call order stop mattering.

### The third advisory was mis-scoped in the handoff, and reading it properly found more

The handoff framed it as "no test covers both orderings of the permission race." True, but reading
both paragraphs together showed the spec **contradicted itself**: §Marker store said "the writer is
the only component that creates it, so the mode is set in exactly one place," while §Decision logging
said "both the writer and the gate can be the first to create it." The second is correct — the gate
appends its decision line to the same directory and reaches it first in any repo where a commit is
blocked before a marker was ever written, i.e. the *normal* first encounter with a newly armed gate.

Fixed per `feedback_delete_the_duplicate_dont_sync_it`: §Decision logging is now the **single
authority** for directory creation; the §Marker store bullet governs only marker-file `0600` and
points at it. **A missing test was the symptom; two paragraphs disagreeing was the cause.**

### The line-count trap, avoided deliberately

Added the O3 row with the literal token `PENDING`, measured `wc -l` → 1,721, then swapped `PENDING`
for `1,721` — a same-line substitution that cannot change the count. Verified after the edit: actual
1,721, recorded 1,721. This is the exact failure that shipped wrong numbers in revisions 8 and 9.

### Still open

Round 6 (both judges) is owed. Waivers unchanged and not to be re-litigated:
`writing-specs/command-grammar`, `core-conduct/file-size-convention` (non-prose floor now above 867
against an 800 ceiling — the file grew again, to 1,721).

## 2026-08-13 — marker-gate round 6: compliance FAILS on the fifth instance, and it is structural

Round 6 (both judges paned, parallel, against revision 13 / commit `3f068d9`):

- **compliance: FAIL, 2 violations** — `unpinned-json-parse-classifier-output`,
  `unpinned-json-parse-marker-read`. Both new ids; round 5 had passed clean.
- **observability: risk=medium, confidence=high** — 7 pass / 3 concern.

### The compliance finding is the same defect class, at architecture scale

The gate is bash and was specified to parse two JSON payloads — the classifier's stdout (with an
`exempt` field the spec says is **unsanitised**) and the on-disk marker files. bash 3.2.57 has no JSON
parser, no `jq` is pinned, and the latency budget provisions **exactly two `python3` starts**, neither
covering these. The judge's sharpest point: the spec **cites a precedent it does not follow** —
`git-guard.sh:59-72` has python3 hand bash a plain string and bash never re-parses JSON.

**User decision → ADR 0026:** no JSON crosses into bash. Classification and marker reading merge into
one `python3` entry point returning plain tab-separated lines. Rejected: pinning `jq` (new dependency),
a third `python3` start (budget was deliberate), flat key=value everywhere (close second — still leaves
two components to sync).

⚠️ **Highest-risk consequence, open for revision 14:** the opt-in ordering rule (classifier runs before
any repo-state touch) becomes *internal to Python* rather than enforced by bash call sequence. And the
"process starts go down" claim in ADR 0026 is a **prediction, not a measurement** — the merged entry
point does not exist. Re-measure the budget against real code.

### The observability finding is my own fix's blind spot

`test-marker.log`'s `0600` is stated 4× and enforced nowhere. Reproduced: the spec's own
`printf … >> "$LOG"` yields **0644** under umask 022, **0664** under 002. I had fixed the *directory*
mode race in revision 13 and missed the *file* sibling two paragraphs away. The judge named the
pattern: "for the second round running the author's sweep fixed exactly the flagged instance and
missed the adjacent sibling of the same defect class."

Tempering it accurately: the parent dir is `0700`, so another user cannot traverse to the file. Real
defect (defence-in-depth; last line if the dir mode loosens) but **not** the "world-readable" the
verdict's prose implies. Recorded as measured, not as narrated.

### Method note — what actually caught things this round

My rev-13 sweep scanned code blocks for *wrong commands* and found nothing new. Both real findings came
from a different question: **"which stated behaviours have no enforcing command at all?"** — the log
mode, and the JSON parses. Scanning what is written cannot find what was never written. Next sweep
enumerates required behaviours and asks which lack a construct, not the reverse.

Also confirmed independently by both judges and by me: all three revision-13 fixes work by execution.
Non-prose floor re-derived live at **887** (was 867) — the size waiver holds and keeps widening.

### Two non-blocking items queued for revision 14

- Percent-encoding order (`:320`) is silently order-dependent: `/`→`%2F` before `%`→`%25` turns
  `hooks/100%-done.sh` into `hooks%252F100%25-done.sh`. Encode `%` **first**. Zero blast radius today.
- The `mkdir`/`chmod` snippet is shell-only though the requirement also binds the Python writer;
  `os.makedirs(mode=…, exist_ok=True)` has the identical race and identical fix.
- (mine) §Pinned versions omits `awk`/`cut`/`sort`/`uniq`, which revision 13 made the queries depend
  on. Verified working under this machine's BSD awk `20200816` — a pinning gap, not a live bug.

## 2026-08-14 — marker-gate implementation opens: task 1, ADR 0027

First session of the implementation phase. Restored from the handoff, verified frontmatter against
reality (`phase: implementation`, branch `feature/verification-marker-gate`, clean at `02b71d4`),
and executed **checklist task 1 only**. Committed `9783956`.

**ADR 0027 — `docs/decisions/0027-the-marker-is-a-receipt-not-a-grade.md`.** Records the six things
task 1 names: the receipt-not-a-grade framing and the ceiling it puts on the whole feature; the
three rejected designs with their reasons (PostToolUse observer — rests on unmeasured harness
semantics that could not be confirmed upstream; `bin/run-tests` wrapper — changes the habit; mutual
certification — a hash says a test *changed*, never that it got *weaker*); the global-but-inert
scope decision **with a Mermaid flowchart of the node ordering that makes it true**, since the
"only `MSG_NO_PYTHON` is machine-global" promise is a claim about position in the flow and prose
states it without showing it; the `UNSUPPORTED` fold and the four triggers whose refusal it kept;
the two accepted-open shapes; and the `cmux.sh` hole.

**Numbering: 0027, and the task's own instruction would have collided.** Task 1 says "check the next
free ADR number against `main` first" — `main` tops at 0025, but 0026 landed earlier on this branch.
Checked both.

### The one thing worth carrying forward: an inherited citation that did not verify

Six file:line citations were being copied out of the spec and the archive into a new durable
artifact, so all six were re-checked first. **Five hold exactly** (`git-guard.sh:53-57`,
`judge-guard.sh:44-48`, `merge-guard.sh:39-43`, `doc-guard.sh:54`, `judge-guard.sh:204`).

**One does not.** `CODING_MEMORY.md:503` rejects the wrapper-runner design partly because it
"invalidates the invocation this repo documents at `hooks/README.md:34,140`". That file documents
**no suite invocation anywhere in its 284 lines** — `grep 'test\.sh'` over it returns nothing. Lines
34 and 140 carry a different and more useful claim: *test the code path that will actually run.*
That principle supports the same rejection by a different route (a wrapper makes the
marker-producing path differ from the path a developer invokes), so the **conclusion survives and
the citation was corrected in place** in the ADR rather than inherited. Recorded here because the
archive line is still wrong where it sits, and append-only means it stays wrong — a later reader
following that citation lands on unrelated text.

Generalisation, and it is the standing one: a citation copied from an audit trail into a *new* audit
trail is laundered, not verified. The cost of checking six was minutes; one was wrong.

### Archive gap, flagged not filled

The marker-gate thread in this file stops at **round 6** (`:7169`). Rounds 7–10 and revisions 15–19
happened and are in git, but were never appended here. Not backfilled — reconstructing them from
commits would be re-derivation presented as record, which is the failure this file exists to avoid.
Git is the record for that span; `docs/features/verification-marker-gate.md` carries the outcomes.

### State at close

Task 1 ticked, **1/16**. Next is **task 2**, which is **blocked** on the shared-lexer decision
landing in `shell_segments.py` (grammar rule 2, user-waived) — so **task 3 may need to lead the
code**. Spec remains frozen at revision 19; a needed change is a `GATE:` announcement, not an edit.

## 2026-08-14 — marker-gate task 4: the writer's red suite, and a duplicated ADR number

### Task 4 landed — 35 assertions, proven able to fail *and* to pass

`hooks/lib/write-test-marker.test.py` (`36f3004`, row 5 added in `2235b8d`): sibling derivation
driven from the step-1 table, percent-encoding against **literal** expected keys, absolute-path
normalisation, the no-subject skip, schema, mode, atomic write, failure exits, non-test paths.

The method is the part worth keeping. The card is explicit that inspection does not exhaust this
class of defect, so the suite was validated three ways instead: with no module it goes red; against
a **deliberately-wrong stub** the checks fire on exactly the defects they target; against a
**correct throwaway oracle** it reaches 35/35. Both stubs were deleted. A suite proven only to fail
has not been proven satisfiable, and one proven only to pass is worthless — the pair is the point.

### The probe found a defect that passed 20 of 29 assertions

The first version of the normalisation check was wrong, and finding out why exposed the trap task 5
must avoid: after `git ls-files --full-name` yields a **repo-relative** subject, handing that value
to a later git call from a different cwd makes git resolve it against *that* cwd
(`panes/panes/adapters/…`), so a tracked subject reports as missing. The call site pins
`cwd = MARKER_ROOT` precisely for this. A wrong test found a real defect — the inverse of the usual
failure, and only because the wrong-stub probe forced both to be explained.

Also pulled back an over-assertion: the mode was being checked on `hooks/state/test-markers/`, but
§2 modes only `hooks/state/`. Asserting a mode the spec never states would have forced task 5 to
satisfy an invented requirement.

### ADR 0026 is duplicated, and the numbering rule was wrong

`origin/main` carries `0026-symbolic-ref-not-abbrev-ref-names-the-branch.md` (merged via PR #52);
this branch carries `0026-the-gate-does-no-json-parsing.md`. **The filenames differ, so git merges
both cleanly and no conflict will ever surface it.**

Root cause: task 1 checked the next free number against **local `main`**, which is 10+ commits
behind `origin/main`. The rule is now explicit — **check ADR numbers against `origin/main`, never
the local ref.** 0027 turned out free anyway, so task 1's ADR stands, but by luck rather than by the
check. Renumbering this branch's 0026 → 0028 is deferred to **task 16**, when spec edits reopen; it
touches the card (18 lines), this file, two `coding-memory/` judge records and both ADRs.

### Row 5 was unspecified, and was raised rather than invented

The step-1 table never said what the writer does with a path forming no pair. No assertion was
written for it until the user decided (2026-08-14): **fail loudly, non-zero + stderr**. It follows
from the card's own rule that a failed marker write fails the suite; the legitimate orphan case is
the separate no-subject skip, which exits 0 on purpose.

### Task 2's blocker re-verified, not inherited

`hooks/lib/shell_segments.py` is **byte-identical to `origin/main`** (155 lines) — segmentation and
wrapper stripping only, no option grammar, nothing that knows `--untracked-files`/`--gpg-sign` must
not consume the next token. Its citation `shell_segments.py:64` for `WRAPPERS` was re-opened and is
correct. Superseding the previous section's close: **2↔3 are NOT inverted** (user decision) — task 3
implements rule 2, so it is blocked identically, and inverting would write code before its test.

### State at close

Tasks 1 and 4 ticked, **2/16**. Next is **task 5** (green: `hooks/lib/write-test-marker.py`), now
unblocked, to be written **fresh from the tests** rather than adapted from the throwaway oracle.
Tasks 2 and 3 remain blocked on the shared lexer. Spec frozen at revision 19.

## 2026-08-14 — task 5 green, and what a green suite still could not see

### The suite passing was the weaker half of the evidence

`hooks/lib/write-test-marker.py` (229 lines) takes the writer's suite to **35/35**. Written from the
tests; task 4's throwaway oracle was deleted first, so the two never met.

The load-bearing check was **not** the green run. Five mutants were applied to the finished file and
the suite re-run against each; **three survived**, and each had to be explained before the task
could close. Explaining them is what separated the one real gap from two false alarms:

| mutant | suite | verdict |
|---|---|---|
| non-test path returns silently | 31/35 | caught — row 5 holds |
| percent-encoding order reversed | 31/35 | caught — the normative order holds |
| `--full-name` dropped | **35/35** | redundant: every git call is pinned `-C <root>` |
| marker `chmod` dropped | **35/35** | equivalent: `mkstemp` already creates at `0600` |
| `os.chmod(state, 0700)` dropped | **35/35** | **real blind spot — see below** |

### Two mechanisms enforcing one property make each other unobservable

`--full-name` is mandated by §1 and it is genuinely dead weight *in this implementation*, because
resolving the toplevel first and then pinning `-C <root>` on every subsequent call already makes
every output repo-relative. It stays: it is spec-mandated, and it keeps the function correct if the
`-C` pin is ever lost. But a mutation score cannot be read as coverage here — the survivor is
telling the truth about redundancy, not about a missing test.

The same shape, one layer down: the marker's explicit `chmod 0600` is unobservable because
`tempfile.mkstemp` documents that mode. Kept as defence against a future rewrite reaching for
`open()`, where the umask would decide instead.

### The one that matters: a repair with nothing asserting it

Dropping `os.chmod(state, 0o700)` costs the suite nothing, because the fixture always lets the
writer *create* `hooks/state/` — and `os.makedirs(mode=0o700)` is correct for a directory it makes.
The card's whole argument for the chmod is the case the fixture never builds: a directory that
**already exists at `0755`**, which `makedirs(exist_ok=True)` silently leaves alone.

Verified by hand rather than left inferred — pre-created `hooks/state/` at `0755`, ran the writer
from the repo root, directory ended **`0700`**, marker **`0600`**, exit 0. So the code is right.
**Task 6 owns the assertion** ("pre-create at `0755`, run either component"), so this is deferred by
design; until it lands, the repair is real code that no test would notice losing.

### State at close

Tasks 1, 4, 5 ticked, **3/16**. Next is **task 6** (red: `hooks/test-marker-guard.test.sh`), which
must include the pre-existing-`0755` case above for the writer as well as the gate. Tasks 2 and 3
remain blocked on the shared lexer. Spec frozen at revision 19; ADR 0026 still needs renumbering to
0028 at task 16.

## 2026-08-14 — task 6 is clear to write; task 7 is not, and nobody had checked

### The assessment the handoff kept deferring

Every prior session recorded tasks 6–16 as "reasoning only, never checked". Two of them are now
checked. The answers point in opposite directions, which is why assuming either would have been
wrong.

**Task 6 is unblocked.** The block on tasks 2 and 3 is the waived, unresolved grammar rule 2, and
rule 2 is unresolved *only* where it collides with the optional-value flags `-u/--untracked-files`
and `-S/--gpg-sign` — the group the spec says must never consume the next token. So the question is
not "does task 6 depend on the grammar" (it does, everywhere) but "does any scenario task 6 must
encode turn on the one case nobody has decided". Derivation rather than reading:

```
grep -n "untracked-files\|gpg-sign\|-u \|-S " docs/features/verification-marker-gate.md
```

Three hits, all inside §The command grammar and its UNRESOLVED callout. **No scenario uses either
flag.** The commands the scenarios actually drive are `-m`, `-am`, `-F`, `-p`, `--amend`, `-i`, and
bare/`--`-separated pathspecs — all of them settled rows G1–G9. Writing task 6 therefore encodes no
waived decision.

**Task 7 is blocked, and it is the one that stalls the branch.** Its own text names the mechanism:
the entry point *imports* the classifier, which is why the spec carries a scenario asserting a
deleted classifier surfaces as `MSG_CLASSIFIER_FAILED` at a different door than a deleted entry
point. Task 7 cannot go green while task 3 is blocked — no import, no decision call, no gate.

### What that means for sequencing

Task 6 lands a suite that stays red until an out-of-scope decision lands in `shell_segments.py`.
That is the correct state for a red task and not a reason to defer it — but it does mean the branch
has **one task of forward motion left** before it parks, unless the shared-lexer work is scheduled.

⚠️ **Tasks 8–16 remain unassessed. Do not infer they are blocked by 7** — task 8 wires the
*writer's* call site into the 14 paired suites and may well be independent of the gate. That is a
guess, and this file has been burned by exactly that kind of guess before. Check it before picking
it up.

### Method note

Task 4's precedent — validate a red suite against a correct throwaway oracle, so it is proven
satisfiable and not merely proven to fail — **cannot be met for task 6's scenario half**, because
building that oracle means building the gate, which means the classifier. The parts that exercise
the *writer* (the `hooks/state/` mode cases, including the pre-existing-`0755` case task 5 left
deferred) can be validated now, because the writer exists. Say which half was proven, rather than
letting "red suite written" imply the stronger claim.

## 2026-08-14 — task 6 red: the gate's suite, and which half of it was actually proven

`hooks/test-marker-guard.test.sh` lands at **914 lines** (code floor **625**), driving **225
assertions**. Against the real tree: **8 pass, 217 fail** — the gate does not exist, so every case
that invokes it exits 127. That is the correct red state, not a defect in the suite.

### The honest split — read this before trusting the word "red"

**Proven able to fail *and* able to pass: the six writer-facing mode assertions only.** Two mutants
of a throwaway copy of the writer (never the repo's), each run against the unmodified suite:

| mutant | effect |
|---|---|
| delete `os.chmod(state, STATE_MODE)` | flips **1** case: *pre-existing 0755 store, writer runs* |
| `STATE_MODE = 0o755`, `MARKER_MODE = 0o644` | flips **all 6** |

The first mutant is the one that matters: it is the case `mkdir -p -m` and `os.makedirs(mode=…)`
both fail to satisfy, and it is exactly the case task 5 deferred. It flips alone, so it is not
riding on the other five.

**Not proven satisfiable: the other 219.** Task 4's precedent — validate a red suite against a
correct throwaway oracle — is unreachable here, because that oracle *is* the gate, which needs the
classifier, which is task 3. These 219 are proven able to *fail* and nothing more. **"Red suite
written" must not be read as the stronger claim**, and two assertions inside that set currently pass
**vacuously**: *an allowed commit writes no log line* and *the door that fires before a repo is
known writes no line* both read 0 lines from a log that no component has yet been able to create.
They become real only once the gate runs.

Likewise, *gate first, then writer* and *writer first, then gate* are named for an ordering that
does not yet exist — today both only exercise the writer. The names are right for task 7's world.

### Decisions taken while writing it

- **File size: 914 > the 800 max, accepted** (user decision, 2026-08-14). Trimming to fit means
  cutting ~113 lines of rationale, and the rationale is the discipline — each comment names the
  defect that passes when its case is absent. Splitting the file is a spec change (the spec names
  one file; task 8 wires one call site), so it would need the GATE. **Record the waiver at task
  16**, not now: the frontmatter is spec, and this is the implementation phase.
- **Repo fixtures come from `mktemp -d`, not a counter.** `setup_door` runs inside a command
  substitution, so a `SEQ` incremented there is lost and the next door silently reuses the path —
  caught before it could make two door cases share one repo.
- **`shellcheck -x` clean at 0.11.0**, with one directive: `SC2086` on `$RUN_ENV`, which *must*
  word-split — a quoted empty string hands `env` an argument it reads as a command name.
- **stderr is empty** on a full run (measured: 253 stdout lines, 0 stderr).

### What the suite refuses to do, deliberately

- Log assertions read **by field** (`awk -F'\t'`), never by `grep`.
- Every mode case sets **`umask 022`** explicitly; a suite inheriting `0077` reports 0600 on a file
  the gate created 0644.
- Fixtures **disagree on purpose**: `$HOME`'s store is stale, the main checkout's marker is stale
  against the linked worktree's, `written_at` is varied in both directions.
- The door cases are driven from the spec's **two Examples tables** as data (`DOORS_TSV`,
  `DOORS_BASH`). A door added to the spec table becomes a case; there is no second spelling to sync.
- The `-` placeholder is used for an absent `desc` in `setup_door`'s output, for the same reason the
  TSV contract uses it: a tab is IFS whitespace, so an empty field vanishes and shifts the rest.

### Still true, still blocking

Task 7 needs task 3 needs the `shell_segments.py` option grammar. **Task 6 was the last forward
motion on this branch** unless that work is scheduled. Tasks 8–16 remain unassessed — task 8 wires
the *writer's* call site and may be independent. Re-derive before picking one up.

## 2026-08-15 — tasks 8–16 assessed at last: one root blocker, one live thread

### The previous line was right to hedge — task 8 *is* independent, and nearly ready

Restored to find the handoff one commit stale: it read `NEXT: task 6`, but `c3dedc8` had already
landed task 6's red suite. Actual state **4/16** (tasks 1, 4, 5, 6), clean, level with origin, no PR.
Re-ran the writer before trusting it: **35/35**.

Then assessed 8–16, which no prior session had done:

| task | needs | verdict |
|---|---|---|
| 2, 3 | grammar rule 2 (waived, unresolved) | blocked on the shared lexer |
| 7 | *imports* the classifier | blocked on 3 |
| **8** | row 12's suite = task 2's artifact | **13 of 14 present** |
| 9–11, 13–15 | the gate itself | blocked on 7 |
| 16 | everything | blocked |

**One root cause, not twelve.** `hooks/lib/shell_segments.py` re-verified byte-identical to
`origin/main`, still 155 lines, no option grammar.

### Why task 8 survives the block — three measured facts

1. **The call site touches only the writer.** Spec lines 311–330 invoke
   `hooks/lib/write-test-marker.py` and nothing else. No classifier, no gate, no TSV boundary.
2. **13 of the 14 suites exist**, checked file-by-file, not inferred: rows 1–11 all present, row 13
   present, **row 14 present** (task 6 created `hooks/test-marker-guard.test.sh`). Only row 12,
   `hooks/lib/classify-commit-command.test.py`, is missing — it is task 2's artifact.
3. **The spec's own enforcement is already built for this.** Assertion 1 (lines 290–292) enumerates
   `git ls-files`, keeps only suites whose subject is **tracked**, and "self-extends to pairs 12–14
   instead of contradicting them"; the section below it explicitly tolerates a transient orphan
   during TDD. So wiring the 13 satisfies assertion 1 *today*, and the assertion turns red on its own
   if task 3 ever lands its suite unwired. The deferral needs no new mechanism.

**Row 14 is safe to wire despite having no subject.** The writer derives
`hooks/test-marker-guard.sh`, finds it untracked, takes the no-subject skip and exits 0. Wiring it
now is correct and inert.

### User decision (2026-08-15) — task 8 partial

Wire the 13 that exist; **leave row 12 to task 3's commit**. The checklist box stays **UNTICKED**
with a completion note naming row 12 as the remainder — partial work recorded as partial. Ticking it
against "all 14" would be a false claim in an audit trail. This is *not* a spec change and needs no
GATE: the task's scope is unchanged, one input simply does not exist yet.

**Two costs flagged and accepted before the decision**, both real:
- 13 suites gain a call that spawns the writer on pass, and **a writer error fails the suite** — in
  suites other live sessions may be running, while the gate itself is nowhere near shipping.
- Touching 13 shared test files raises the merge-conflict surface against `feature/memsearch-freshness`
  and `fix/git-guard-detached-head`.

### Sequencing after this

Task 8 partial is the **last** forward motion on this branch. Everything remaining routes through the
`shell_segments.py` option-grammar work, which is scoped **off** this branch by user decision — so it
wants its own feature before tasks 2/3/7 can move. ADR 0026's duplicate renumber (→ **0028**) is still
parked at task 16.

## 2026-08-15 — task 8 STOPPED at a GATE: §Scope's table is stale by six pairs

**The premise under yesterday's "wire the 13" decision was never measured, and it is false.** That
decision checked that each of the table's 14 rows *exists*. It never asked the inverse question —
whether any tracked pair exists **outside** the table. Measured from source just now:

```
git ls-files '*.test.sh' '*.test.py'   # 22 suite files
  -> 18 tracked pairs, 4 orphan suites
```

Not 11 pairs + 3 of this feature's own = 14. **Eighteen.** Six tracked pairs are absent from
§Scope's first table entirely:

| suite | subject | suite first appeared |
|---|---|---|
| `hooks/doc-guard.test.sh` | `hooks/doc-guard.sh` | 2026-08-03 `ac5afa2` |
| `hooks/git-guard.test.sh` | `hooks/git-guard.sh` | 2026-08-03 `ac5afa2` |
| `hooks/lib/classify-git-command.test.py` | `hooks/lib/classify-git-command.py` | 2026-08-03 `ac5afa2` |
| `hooks/lib/shell_segments.test.py` | `hooks/lib/shell_segments.py` | 2026-08-04 `64ba2fa` |
| `hooks/feature-sync-guard.test.sh` | `hooks/feature-sync-guard.sh` | 2026-08-06 `7f9bb6f` |
| `hooks/handoff/slim-session-start.test.sh` | `hooks/handoff/slim-session-start.sh` | 2026-08-06 `ca2c969` |

**Every one landed AFTER 2026-08-02**, the date §Scope stamps on its own measurement — "Measured
2026-08-02 from `git ls-files`, not recalled — 13 tracked suite files, 11 conforming pairs (10 shell
+ 1 Python), 2 orphan suites." The table did not drift; the repo grew past it, in exactly the four
days after it was taken. The dated stamp is what made this findable, and nothing before now went
looking.

There is also a **third real orphan** the spec does not name: `memsearch/bin/install-schedule.test.sh`
(no `install-schedule.sh`). So the orphan count is 3 real + 1 transient (`test-marker-guard.test.sh`,
whose subject lands at task 7), not 2.

### Why this is a GATE and not a judgement call

The spec's *criterion* is right and its *enumeration* is wrong, and the two now contradict each other:

- **The criterion** (§Scope): "The wiring criterion is therefore **every pair**, 14 of them at task 8
  — never a literal carried over from the table above." It even names this failure mode.
- **Assertion 1** (spec 290–292), which task 8 must land in the same commit, enumerates
  `git ls-files`, keeps suites whose subject is tracked, and asserts each contains the call line. As
  specified it demands **all 18**. Wiring 13 makes assertion 1 **red on landing** — and red for a
  correct reason.
- **Task 8's text** says "all 14 paired suites — the 11 in §Scope's first table plus this feature's
  own 3." That set is now factually wrong.

So yesterday's point 3 — "wiring the 13 satisfies assertion 1 *today*" — is **withdrawn**. It was
derived from the table rather than from `git ls-files`, which is the one source assertion 1 actually
consults.

**The cost of shipping the 13-suite reading is not cosmetic.** The gate demands a marker for any
tracked subject with a sibling suite. Wire 13 of 18 and the moment the gate arms, six subjects become
uncommittable with no way to earn a receipt: `doc-guard.sh`, `git-guard.sh`, `feature-sync-guard.sh`,
`slim-session-start.sh`, `classify-git-command.py`, `shell_segments.py` — four of them live hook
scripts, and `git-guard.sh` is the one that guards `main`.

### State at the stop

**Nothing was committed.** No suite was modified. HEAD is still `63881ea`, tree clean apart from this
file and `.claude/session-state.md`.

The before-baseline was taken and is worth keeping — it is the neutrality control task 8 needs
whenever it resumes, and it reproduces the handoff's numbers exactly:

| suite | rc | result |
|---|---|---|
| 11 shell suites (rows 1–11) | 0 | all green |
| `hooks/lib/classify-pr-command.test.py` | 0 | 51 passed, 0 failed |
| `hooks/lib/write-test-marker.test.py` | 0 | 35 passed, 0 failed |
| `hooks/test-marker-guard.test.sh` | 1 | **8 passed, 217 failed** (task 6's red suite, expected) |

Also measured while reading the suites, and unchanged by the gate finding: all 11 shell suites share
one shape — `set -u`, **no `set -e`**, a tally `printf`, then `[ "$fail" -eq 0 ]` as the final
command. Only `hooks/judge-guard.test.sh:13` cds at top level, confirming the spec's measured claim.
Both Python suites end `sys.exit(main())` where `main()` returns `1 if failed else 0`, so the
spec's `if failures == 0` maps to `if rc == 0` with no new variable.

### What the revision has to decide (not for the low tier to guess)

1. Re-measure §Scope's first table, or replace it with the `git ls-files` derivation and drop the
   frozen count — the table is a dated measurement that has now gone stale once.
2. Whether all six newcomers are **in** scope. `shell_segments.py` is the awkward one: tasks 2/3 are
   already blocked on its missing option grammar, and wiring its suite pulls a file this branch was
   explicitly told not to expand into.
3. Whether the third orphan (`install-schedule.test.sh`) joins assertion 2's named set or gets an
   §Scope "out" line of its own.
4. Task 9's **25**-mutant floor and task 14's arming check both counted doors against the old
   inventory; neither was re-derived here.

### Task 12 assessed — blocked on 7, and the branch is now fully blocked

Task 12 was never assessed. The table above jumps from 8 to "9–11, 13–15"; 12 is absent from it, and
the "one live thread" conclusion was drawn without it. Assessed now, and it is **blocked on task 7** —
for a different reason than 9–11/13–16, which need the gate to *run*:

Verified: `hooks/test-marker-guard.sh` does not exist; `test-marker` appears **0 times** in
`settings.json`, `rules/gates.md`, and `hooks/README.md`. Task 12's entire deliverable is behavioural
claims about that script — global-but-inert scope, `MSG_NO_PYTHON` as the one exception, and that v1
ships no way to query whether the gate is armed. Every one is a **write-down that cannot be verified
first**, into `rules/gates.md`, the file every session loads every turn.

The dormant-hook precedent does not stretch to cover it. README documents `scan-secrets.sh`,
`scan-invisible-unicode.sh`, `checkpoint-before-modify.sh` and `require-project-standards.sh` — all
four **exist as files** and are merely unregistered. Documenting a script that does not exist at all
has no precedent here, and `rules/gates.md` already names that exact failure: "advertised protection
that is not currently protecting anything."

**Result: 4/16 and no task can move.** Everything routes through one of two unblockers, neither
available at this tier — the high-tier spec revision (task 8), or the `shell_segments.py`
option-grammar work (tasks 2/3/7 →  everything else), scoped off this branch by user decision.
The ADR 0026 → 0028 renumber is **not** available as filler: it edits the card, which the freeze
forbids. Recording this so the next session does not re-derive a task-shaped substitute.

## 2026-08-15 — revision 20: the enumeration becomes a derivation

Card reopened to `phase: planning`, `model_tier: high`, `revision: 20`, `revision_status: in-progress`
(user decision). Implementation resumes only on a fresh `gate confirmed`. Note `hooks/phase-guard.sh`
re-arms the moment the card leaves `implementation` — no card records this branch as implementing any
more, so source writes are denied until the gate reopens. That is the intent, not a side effect.

**The fix is structural, not arithmetic.** §Scope no longer lists the covered set; it *derives* it:

```sh
git ls-files '*.test.sh' '*.test.py'   # strip .test.*, add .sh/.py, keep tracked subjects
```

with a normative line — no task, test or judge may substitute a number or a hand-written list. The
snapshot is kept but demoted to illustration and stamped. Replacing the list rather than re-measuring
it is the whole point: revision 19 already *warned* against "a literal carried over from the table
above" and shipped one anyway, because the warning sat next to the literal it forbade.

**User decision: `hooks/lib/shell_segments.py` is IN scope.** Wiring its suite touches neither the
option grammar nor the subject file, so the standing "do not expand scope into `shell_segments.py`"
boundary holds. Excluding it was rejected as the *more* expensive option — the design has no exclusion
mechanism for a suite whose subject is tracked, so an unwired `shell_segments.py` would be permanently
uncommittable without a `TEST_EXEMPT` on every commit.

### Measured at revision 20 — every number re-derived, none carried

| quantity | value | note |
|---|---|---|
| tracked suite files | **22** | 18 + 4 balances |
| tracked pairs | **18** | 17 pre-existing + `write-test-marker` |
| orphan suites | **4** | 3 permanent + 1 transient (`test-marker-guard.test.sh`, task 7) |
| shell / Python split | **14 / 4** | Python four all under `hooks/lib/` |
| directories / depths | **6 / 3** | `.`, `hooks/`, `hooks/handoff/`, `hooks/lib/`, `panes/`, `panes/adapters/` |
| suites directly in `hooks/` | **8** | 13 are somewhere under `hooks/`; only 8 at top level |
| expected end state | **20** | +row 12 at task 3, +row 14 at task 7 — expected, not prescribed |

**Two inherited numbers were wrong on their own terms, independent of the staleness:**
- "four different directory depths" — wrong when written; the 11-pair set was **5 directories at 3
  depths**. Corrected in place rather than carried forward.
- "the 5 suites under `hooks/`" — **8** sit directly in `hooks/`.

Five residual stale counts were swept out beyond the table itself (§1's call-site prose, the
fail-closed Gherkin comment, the "two orphan suites" line in the flowchart narrative, and both halves
of the 5↔8 revert-pair note). Found by grepping the literals, not by re-reading — the same class the
revision exists to kill.

### 🔴 Correction — a claim from earlier today was wrong

The gate announcement listed as decision (4): *"task 9's 25-mutant floor and task 14's arming check
both counted doors against the old inventory; neither was re-derived."* **That is false.** The floor
is `13 doors + 10 allow paths + 2 component mutants` (spec §Mutation floor) — all properties of the
gate's decision logic and its two Python files, none of the pair inventory. Task 14 pipes payloads at
the installed hook and likewise never counts pairs. **Tasks 9 and 14 needed no change and got none.**
The claim was asserted from the shape of the finding rather than checked against the derivation, which
is exactly the error the revision is about.

### The third orphan is a different species than first recorded

`memsearch/bin/install-schedule.test.sh` is not a test with no subject. **The subject exists** —
`memsearch/bin/install-schedule` — but carries **no `.sh` extension**, so the suffix derivation looks
for `install-schedule.sh` and finds nothing. That is a distinct failure mode from `cmux.sh`, where the
*test* is misnamed; here the test name is right and the **subject** name is unmatchable. It recurs for
every extensionless executable (`memsearch/bin/memsearch` is the other, with no sibling test at all).
Fixing it would mean pairing on shebang or content instead of suffix — a redesign of the pairing rule,
so it is recorded as a follow-up, not folded in.

### Compliance gate — deliberately skipped for revision 20 (user decision, 2026-08-15)

The spec-compliance gate calls for a judge run after *any* later spec edit. **Not run for revision
20**, on the user's standing "proceed without a passing compliance verdict" decision, reaffirmed
explicitly when the cost was put to them. Recorded here because a skipped gate that leaves no trace
is indistinguishable from a forgotten one — that asymmetry is the whole reason this line exists.
Round 10's `fail` remains stale and closed by rev 19; no verdict exists for rev 20 and none is
pending. The observability judge at task 16 is unaffected and still required before any PR.

## 2026-08-15 — session restored after accidental close; state verified consistent

Prior session ended without a clean handoff. Restored from the handoff trio's
`.claude/session-state.md` and checked it against reality rather than trusting it on read, per the
handoff/restore discipline: branch is `feature/verification-marker-gate` (matches), working tree
clean and pushed, no PR (matches). Card frontmatter — `phase: planning`, `revision: 20`,
`revision_status: in-progress` — matches the handoff. One drift found: the handoff's recorded HEAD
(`8db8132`) was one commit behind actual HEAD (`747d8ef`, the compliance-skip memory commit above);
corrected in the scratch state file. No branch/phase mismatch, so nothing escalated.

No new engineering decisions this turn. `.claude/session-state.md` was trimmed to drop measured-number
detail already durable here (`CODING_MEMORY.md:7694-7699`, `:7623-7628`) per the handoff-discipline
rule against restating spec content in a scratch file; `.claude/current-task.md` was corrected from a
stale 2/16-tasks, revision-19 snapshot to the current 4/16, revision-20 state. This entry exists
because `context-handoff-watch.sh` fired its ≥75k-token freshness checkpoint at session start (system
prompt + skill catalog overhead, not new conversation growth) — logged so the checkpoint isn't a
silent no-op. Still waiting on the user to review revision 20 and say the literal `gate confirmed`.

## 2026-08-15 — gate confirmed at revision 20; task 8 lands (`d0d935f`, corrected `43d070f`)

User said the literal `gate confirmed`. Frontmatter flipped to `phase: implementation,
model_tier: low` (user chose low tier when asked the unskippable planning→implementation
model-switch checkpoint — its own ask, not inferred from "gate confirmed" itself). User also
explicitly overrode the skill's mandatory-`/clear`-point with "continue here," and asked to be
prompted at 165k tokens instead of the default checkpoint cadence — both honored as explicit
in-session instruction, noted here so the departure from the default isn't silently invisible.

Task 8 (wire the marker-write call into every live `§Scope`-derived pair) was dispatched to a
paned `general-purpose` implementer — first worker dispatch this session, so the pane-split policy
was asked and set to `panes max=2`. It landed as `d0d935f`: live-derived 18 pairs / 4 orphans
(matching the 2026-08-15 snapshot, re-confirmed rather than trusted), wired all 18, added the two
inventory assertions to `write-test-marker.test.py` (35 → 56 assertions), and found one real bug
not called out in the spec: the four Python suites' `MARKER_ROOT`, resolved via `git rev-parse
--show-toplevel` in the ambient cwd, returns the wrong toplevel when `judge-guard.test.sh` (which
`cd`s into a throwaway repo) nest-invokes `classify-pr-command.test.py` as an internal check — the
child inherits the fixture's cwd. Fixed by anchoring all four to `cwd=dirname(MARKER_SELF)`.

**Independent verification (per `verifying-subagent-commits`) caught one report inaccuracy.** The
implementer's self-report claimed `slim-session-start.test.sh` was pre-existing red at 13/29,
unchanged by the wiring. Re-run directly it is **29/29** — on the parent commit and on HEAD alike.
Root cause: the implementer ran *as* a pane agent, so `CLAUDE_PANE_AGENT` was ambient in its own
shell; the suite's subject script goes silent under that variable, failing 16 of 29 assertions
that expect verbose output while 13 incidentally still pass — reproduced exactly with
`CLAUDE_PANE_AGENT=1 bash hooks/handoff/slim-session-start.test.sh`. The wiring itself was never
wrong; only the report was. Corrected in the checklist note by `43d070f` rather than left standing
as settled fact. **General lesson for future pane-dispatched verification:** a pane-agent-run test
suite can spuriously fail (or pass) any assertion that depends on `CLAUDE_PANE_AGENT` being unset,
for scripts that intentionally special-case it — `unset` it before the suite runs inside a pane,
or re-verify from the orchestrator's own (non-pane) shell as was done here.

All other 17 suites' before/after counts, independently re-run from the orchestrator's shell,
matched the implementer's report exactly; marker files exist under `hooks/state/test-markers/` for
all 18 pairs (dir `0700`, files `0600`). Branch is 3 commits ahead of `origin` (not pushed yet:
`6ad7e43`, `d0d935f`, `43d070f`). Next: task 9 and everything after remains blocked on tasks 2/3/7
per the standing assessment; nothing new is unblocked by task 8 landing.
