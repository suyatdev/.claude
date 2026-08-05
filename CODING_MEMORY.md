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
- **SIBLING BRANCH `docs/verify-before-claiming`** (`1721a3c`, off `2b8564b`, pushed) — one line in
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
  · **IN PLANNING (session 10) — `git-guard.replay.sh`. Canonical:
  `docs/features/replay-harness-base-pin.md`, `phase: planning`, revision 5.** Scope is **wider than
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
  exits **2** on every command (`git-guard.sh:56` fails closed). **Independent of (1): exit 2 is
  inside `{0,2}`, so fixing the `else` arm does not touch this.** (3) **The harness exits 0
  unconditionally** — 62 relaxations exit exactly like a clean run, so no caller can gate on it.
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
