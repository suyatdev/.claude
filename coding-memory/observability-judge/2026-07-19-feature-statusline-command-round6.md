# Observability Judge — feature/statusline-command (round 6, final)

- **repo:** .claude
- **branch:** feature/statusline-command
- **head_sha:** ae34fc78cc0dea5a8a55517b6b0f0fa4dfed2273
- **base:** main (merge-base 54b9b265f91c7b259e29f8193c9c589005e3eec5)
- **stage:** implementation
- **ts:** 2026-07-19T19:34:39Z
- **risk:** low — **confidence:** high
- **round 1:** `2026-07-19-feature-statusline-command.md` @ f0902ed (low/medium)
- **round 2:** `2026-07-19-feature-statusline-command-round2.md` @ c06737b (low/high)
- **round 3:** `2026-07-19-feature-statusline-command-round3.md` @ 29d6131 (low/high)
- **round 4:** `2026-07-19-feature-statusline-command-round4.md` @ 4d63b09 (low/high)
- **round 5:** `2026-07-19-feature-statusline-command-round5.md` @ e882659 (medium/high)

> Filename note: continues the `-roundN` suffix precedent so rounds 1-5 survive in the working
> tree rather than only in git history.

## Headline — no blocker. Open the PR.

**The leak is closed, the fix is a genuine root-cause fix rather than a third patch, and for the
first time in six rounds every security claim in the documentation is true.** What remains is
stale arithmetic in comments. I say plainly: that is not a reason to withhold the PR.

## What was changed

One commit (`ae34fc7`). Both orderings of a single strip around the `$PWD` fallback had been tried
and both leaked — strip-first lets the fallback reintroduce a raw value (round 3, `29d6131`),
strip-last lets an emptied value fall through to a second raw assignment (round 5, `e882659`).
The new version strips each source **at its source**:

```bash
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
cwd="${cwd//[[:cntrl:]]/}"
[ -z "$cwd" ] && cwd="${PWD//[[:cntrl:]]/}"
```

Plus a 20th assertion for the fallthrough, the falsify map extended to all five historical
versions, and doc corrections.

## Confirmed: the leak is closed and no new one is open

**Regression probe, all six revisions.** Payload `{"cwd": "<CR><SOH><ESC><BEL>"}` — a cwd of
nothing but control bytes — executed from a directory named `x<ESC>]0;HIJACK<BEL>evil`:

| Revision | esc | bel | OSC intact |
|---|---|---|---|
| `f0902ed` | 7 | 1 | false |
| `925c310` | 7 | 1 | false |
| `29d6131` | 7 | 1 | **true** |
| `4d63b09` | 6 | 0 | false |
| `e882659` | 7 | 1 | **true** |
| `ae34fc7` (HEAD) | 6 | 0 | false |
| worktree | 6 | 0 | false |

This independently confirms the caller's own verification (`4d63b09` clean, `e882659` leaked) and
confirms `ae34fc7` restores the clean state. Worktree blob `a27c99aa` is byte-identical to
`HEAD:statusline-command.sh`, so this is the committed script.

**Exhaustive stdout trace — all eight values, attacked at their sources.** Attack string was
`<ESC>]0;PWNED<BEL><ESC>[5m<CR><NL><DEL>tail`:

| # | Value | Source | Strip site | Result |
|---|---|---|---|---|
| 1 | `cwd` | `.workspace.current_dir` | line 42 | clean |
| 2 | `cwd` | `.cwd` | line 42 | clean |
| 3 | `cwd` | `$PWD` fallback (5 stdin shapes) | line 43 | clean |
| 4 | `dir` | `basename "$cwd"` | inherited | clean |
| 5 | `user` | `whoami` | line 66 | clean (PATH shim) |
| 6 | `host` | `hostname -s` | line 68 | clean (PATH shim) |
| 7 | `branch` | `git symbolic-ref` | line 79 | clean; git also rejects the ref |
| 8 | `model_name` / `tokens_fmt` | JSON | lines 92, 94 | clean |

After removing the script's own known colour SGRs from the output, **zero stray control bytes
remain** on every probe. My first pass flagged the model and token paths as leaks; that was my
own baseline error — the extras segment legitimately adds `DIM`+`RESET`. Raw-byte inspection
confirms `]0;PWNED[5mtail` renders as inert literal text with the ESC and BEL already gone.

**Only three assignments to `cwd` exist** (lines 41, 42, 43) and every one is stripped. There is
no later assignment that can reintroduce a raw value. The caller's root-cause claim holds.

**The load-bearing `$PWD` claim — I tried hard to break it and could not.** The reasoning is that
`$PWD` is always absolute, so it always keeps a `/` and can never strip to empty, which is what
keeps `git -C "$cwd"` from resolving to the process directory. Bash re-derives `PWD` from
`getcwd()` whenever the inherited value is not a valid absolute path naming the real cwd:

| Hostile condition | Resulting `$PWD` | Strips to empty? |
|---|---|---|
| `PWD` unset | `/private/tmp` | no |
| `PWD=""` | `/private/tmp` | no |
| `PWD` exported as all-control bytes | `/private/tmp` | no |
| `PWD` exported as a relative path | `/private/tmp` | no |
| cwd deleted underneath the process | `/tmp` (inherited) | no |

The guarantee is real and robust. Reasoning confirmed, not accepted.

## The 20th assertion is sound and falsifiable

It fails against exactly the versions that leak and passes against exactly those that do not:

| Revision | Assertion 20 |
|---|---|
| `29d6131` | **FAILS** (bel=1) |
| `4d63b09` | passes (bel=0) |
| `e882659` | **FAILS** (bel=1) |
| `ae34fc7` | passes (bel=0) |

This resolves round 5's central complaint directly: `e882659` now scores 19/20 against HEAD's
20/20, so the suite *can* distinguish the commit under review from its predecessor.

**Mutation test — I broke the fix six ways and watched:**

| Mutant | Result |
|---|---|
| M1 unstrip the `$PWD` fallback | 15/20 **CAUGHT** (incl. assertion 20) |
| M2 unstrip the jq `cwd` result | 18/20 **CAUGHT** |
| M3 unstrip `model_name` | 16/20 **CAUGHT** |
| M4 unstrip `user` | 20/20 *survived* |
| M5 unstrip `host` | 20/20 *survived* |
| M6 revert render to `printf %b` | 19/20 **CAUGHT** |

Assertion 20 is load-bearing, not decorative. The two survivors are a real but named coverage gap
on the lowest-severity values — reaching them needs `PATH` or hostname control, which is already
game over.

**The BEL-only choice is correct, and I verified the rejected draft's failure mode.** I rebuilt
the escape-baseline variant the caller discarded and ran it:

| Revision | BEL only (committed) | With escape baseline (rejected draft) |
|---|---|---|
| `29d6131` | FAIL bel=1 | FAIL bel=1 |
| `4d63b09` | **ok** bel=0 | **FAIL bel=0** ← spurious |
| `e882659` | FAIL bel=1 | FAIL bel=1 |
| `ae34fc7` | ok bel=0 | ok bel=0 |

The rejected draft flags a "leak" on `4d63b09` while `bel=0` — no leak byte present. Worse, it
would have scored `4d63b09` and `e882659` both at 19, reproducing round 5's exact
indistinguishability complaint. The caller's diagnosis and correction are both right.

## The five falsification counts — independently derived, not fitted

I did not reuse the committed harness. Mine drives `/usr/bin/git cat-file blob` from Python,
asserts each blob starts with `#!`, and recomputes `sha1("blob <len>\0" + content)` locally to
compare against `git rev-parse <rev>:<path>`. (Worth noting: my first attempt to extract blobs
from the Bash tool hit the documented rtk trap head-on — `fatal: Not a valid object name
usline-command.she34fc7`. The harness's warning is accurate and earned.)

Seven distinct hash-verified blobs. My counts and the harness's `EXPECTED` map agree exactly:

| Revision | Blob | Mechanism (derived from code) | Expected | Mine |
|---|---|---|---|---|
| `f0902ed` | `ce854930` | no stripping at all, so an all-control cwd never empties, never reaches the fallthrough → assertion 20 passes for the right reason | 9 | **9** |
| `925c310` | `d28a0895` | same, route-1 fix only | 10 | **10** |
| `c06737b` | `d28a0895` | shares blob (settings-only commit) | — | 10 |
| `29d6131` | `e30dcd0a` | strip-then-fallback: empties, then takes a raw `$PWD` → fails 20 | 15 | **15** |
| `4d63b09` | `b5a07163` | fallback-then-strip: empties and stays empty, no leak, flaw purely cosmetic → passes 20 | 20 | **20** |
| `e882659` | `4b6be5a9` | second unstripped fallback below the strip → fails 20 | 19 | **19** |
| `ae34fc7` | `a27c99aa` | strip at source | — | **20** |

All five derivations are correct. I confirmed each version's actual strip ordering by extracting
and reading its `cwd` block, so the stated *mechanism* — not just the number — checks out. I also
compared the failing assertion **lists**, not merely the tallies, so a compensating pair of
failures would have been visible to me. It was not. **The harness is not certifying fitted
numbers.**

## Docs vs. code — the check that has failed all five prior rounds

**It fails a sixth time, but the character of the failure has changed completely, and that
distinction is the whole verdict.**

Fixed this round, verified: `CODING_MEMORY.md` is now fully correct (20 assertions, 5 rounds,
9/20 10/20 15/20 20/20 19/20 — matching my independent numbers, four injection paths); the phantom
`scratchpad/falsify.py` reference is gone; "all three versions" is gone; "Four commits" → "Six
commits"; "three rounds" → "five rounds" with a matching five-row table; commits 1-5 all carry
SHAs; `falsify.py`'s `Run:` line says `.py`; the "Cosmetic, no leak" correction of record is
present and honest at branch log lines 169-174.

**Most importantly — `statusline-command.sh` line 15 ("Every value below originates outside this
script, so each is stripped") is now TRUE.** I verified all eight values. That absolute claim has
been false in every round since round 1. It is true today.

What is still wrong — all stale arithmetic, no false security claims:

1. **`statusline-command.falsify.py` lines 11-15 contradict the `EXPECTED` dict 30 lines below in
   the same file**, under a heading that reads "Expected, and asserted below". Docstring says
   `8/20, 9/20, 15/20, 19/20, 19/20`; the code asserts `9, 10, 15, 20, 19`. Three of five
   numerators are wrong — the denominators were updated to `/20` and the numerators were left at
   round-5 values. New this round, and ironic given the file's purpose. Zero behavioural effect;
   the assertions themselves are right.
2. Branch log lines 51 and 132: "19 assertions" → 20.
3. Branch log lines 138-143: the falsification table is entirely stale (`8/19, 9/19, 15/19,
   19/19`) and omits `4d63b09` and `e882659` rows, even though the narrative below it discusses
   both at length.
4. `falsify.py` docstring lines 6-7 and branch log line 145 still over-claim that each version
   "fails exactly the assertions covering the defect it still carries". It compares counts and
   prints the fail list; it does not assert on *which* assertions failed. Round 5 finding, unfixed.
5. README has no row for `statusline-command.falsify.py`, now a tracked top-level file. Round 5
   finding, unfixed.
6. Branch log line 211 lists commit 6 without its SHA — inherent chicken-and-egg, defensible.

Every one of these is a number in a comment. None of them misdescribes what the code does to
untrusted input. That is a categorical improvement over rounds 1-5, where the recurring defect was
the record asserting a security property the code did not honour.

## Commits, staging, and the history-rewrite call

**Six commits partition cleanly.** `settings.json` is touched in exactly two commits — `925c310`
(the `statusLine` block) and `c06737b` (model + theme, 2 lines) — and nowhere else. The remaining
four are script + test + harness + their own round's docs. Each is independently revertible.

**`settings.json` contains no Orca lines.** Committed file at HEAD: **0** occurrences of `orca`;
all four guard hooks (`git-guard.sh`, `doc-guard.sh`, `judge-guard.sh`, `memsearch-nudge.sh`) still
registered; parses as valid JSON. The 112-line Orca block sits entirely in the unstaged working
tree (10 `orca` matches). Drift resisted, not absorbed. Confirmed.

**On not rewriting `e882659`'s message: that was the right call.** The branch is pushed
(`refs/heads/feature/statusline-command` at `ae34fc7` exists on origin), so a correction would mean
force-pushing rewritten history to fix a commit message that is already superseded and explicitly
corrected in the branch log. The repo's own force-push safety gate exists precisely to make that
trade-off deliberate. A forward-only correction of record is more honest and more traceable than a
silently rewritten history. Agreed, without reservation.

## Verification I ran myself

Nothing below is taken from the report on faith.

- **Leak regression probe:** all-control `cwd` from a hostile OSC-named directory, six revisions
  plus worktree. `e882659` bel=1 with intact OSC; `ae34fc7` bel=0 clean. Reproduces the caller's
  own finding and confirms the fix.
- **Exhaustive stdout trace:** eight values, each attacked at its source, including a `PATH` shim
  for `whoami`/`hostname`. Zero stray control bytes after removing known colour SGRs.
- **`$PWD` invariant:** five hostile conditions (unset, empty, all-control export, relative
  export, deleted cwd). Bash re-derives an absolute path every time; never strips to empty.
- **Independent falsification:** own Python harness, `git cat-file blob`, `#!` prefix check,
  `git rev-parse` object-id match, locally recomputed blob SHA. Seven hash-verified blobs. Counts
  9/10/15/20/19 match `EXPECTED` exactly; fail *lists* compared, not just tallies.
- **Mutation test:** six mutants against HEAD; four caught, two survivors (`user`/`host`) named.
- **Rejected-draft reconstruction:** escape-baseline variant of assertion 20 reproduces the
  spurious `4d63b09` failure at bel=0, confirming the BEL-only choice.
- **Committed harness re-run:** `python3 statusline-command.falsify.py` → all rows `ok`,
  `falsification intact`, exit 0. Suite direct → 20/20.
- **Commit partition, per file:** six commits, `settings.json` in exactly two, no conflict.
- **Orca:** 0 matches in committed `settings.json`; 10 in the unstaged working tree; four guard
  hooks intact; valid JSON.
- **Regression:** `hooks/memsearch-nudge.test.sh` PASS, `hooks/judge-guard.test.sh` PASS.
  `bash -n` clean on both shell files, `py_compile` clean on the harness, all three mode 100755.
- **Byte hygiene:** zero non-newline control bytes in the script, harness, branch log, and
  `CODING_MEMORY.md`.
- **State:** branch pushed at `ae34fc7`; no PR open.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Every item asked for landed and is correct: root-cause fix (not a third patch), a falsifiable 20th assertion, the falsify map extended to all five historical versions with derived rather than fitted counts, and the docs substantially corrected including the "Cosmetic, no leak" correction of record. `statusline-command.sh` line 15's absolute claim is true for the first time in six rounds. |
| execution | pass | Leak independently reproduced at `e882659` and independently confirmed closed at `ae34fc7`. All eight stdout values traced and clean. The `$PWD` non-empty invariant survived five hostile conditions. 20/20 on a hash-verified committed blob; mutation test catches 4 of 6 mutants including the one under review; both sibling suites pass. |
| trajectory | pass | Strongest round of the six. Verified the judge's finding independently before acting rather than accepting it; diagnosed the shared root cause behind two failed orderings instead of patching a third time; caught and corrected its own spurious assertion draft, and I reproduced that failure mode to confirm the correction; explicitly flagged the risk of fitting counts to observed output, and I verified they are genuinely derived. Reasoning, not luck. |
| regression | pass | The round-5 regression is closed against its own parent's measured baseline. Six-commit partition verified per file; `settings.json` touched in exactly two commits; all four guard hooks intact; sibling suites, syntax, modes and byte hygiene all clean. |
| context_budget | pass | No always-on rule or prompt growth. Script, test, harness and branch log are all on-demand. |
| traceability | concern | Upgraded from `fail`. No false security claim survives anywhere — the correction of record is present and honest, and line 15 is now true. But stale arithmetic persists a sixth round: `falsify.py`'s docstring contradicts the `EXPECTED` dict in the same file on three of five counts, the branch log still says "19 assertions" twice and carries a fully stale falsification table missing two rows, and two round-5 items (the "fails exactly which assertions" over-claim, the missing README row) are unfixed. Comments only, zero behavioural effect. |
| success_masking | pass | Upgraded from `fail`. Round 5's exact complaint is resolved: assertion 20 discriminates `e882659` (19) from HEAD (20), and mutation M1 confirms it is load-bearing rather than decorative. The green is honest for the defect class under review. The `user`/`host` mutation survivors are a disclosed residual, not a masked one. |
| intent_drift | concern | No new dependencies; Orca block correctly left uncommitted and verified absent from the committed file; `chrome/` drive-by still declined. But the brief was "document and push an existing script" and 5 of 6 commits are judge-driven against a 113-line deliverable. Recorded honestly in a scope section and taken to the user rather than resolved unilaterally, which is the right handling — surfaced, not penalised further. |
| checkpoint | pass | Six coherent commits, each independently revertible and standalone-meaningful; partition verified per file; pushed state consistent with HEAD; `4d63b09` remains a clean fallback target. |
| audit_trail | pass | Attributable; rounds 1-5 preserved via `-roundN`; `ae34fc7`'s commit message is exemplary — defect, root cause, both failed orderings, the assertion rationale, the self-caught spurious draft, and the deliberate decision not to rewrite pushed history. The no-ADR call remains correct (presentation-only). |

## Concerns

- `statusline-command.falsify.py` lines 11-15 contradict the `EXPECTED` dict in the same file on three of five counts (docstring 8/9/15/19 vs asserted 9/10/15/20) under a heading reading "Expected, and asserted below" — new this round, comment-only, zero behavioural effect
- Branch log lines 51 and 132 say "19 assertions"; the suite has 20
- Branch log falsification table (lines 138-143) is stale (8/19, 9/19, 15/19, 19/19) and omits the `4d63b09` and `e882659` rows its own narrative discusses
- `falsify.py` docstring and branch log line 145 still over-claim that each version "fails exactly the assertions covering the defect" — only counts are compared, not which assertions failed (round 5 finding, unfixed)
- README has no row for `statusline-command.falsify.py`, now a tracked top-level file (round 5 finding, unfixed)
- Coverage gap: mutation test shows unstripping `user` or `host` still scores 20/20 — those two strips are untested, though reaching them needs `PATH` or hostname control
- Branch log line 211 lists commit 6 without its SHA (inherent chicken-and-egg, defensible)
- Scope: 5 of 6 commits judge-driven for a 113-line deliverable — documented honestly in a scope section and taken to the user
- Cosmetic, unchanged: `1e400` renders `infk tokens`, `not-a-number` renders `0.0k tokens`, no bound on rendered line length
- `✗` dirty marker still permanently lit because `chrome/` stays untracked, compounded by the uncommitted Orca `settings.json` block
- Committing this verdict moves HEAD and re-stales judge-guard's strict check — see note below

## Note on the judge-guard loop

Five rounds have each been forced by the same mechanism: committing the verdict moves HEAD, which
re-stales judge-guard's strict freshness check. The user has declared this the last round. If
committing this verdict re-stales the gate again, that is the hook working as designed on a
docs-only commit, not new evidence about the code — `JUDGE_EXEMPT=verdict-commit-only` is the
appropriate bypass for that specific commit, and I would not treat it as a waiver of anything
substantive.

## Advisory — Orca `settings.json` write (NOT part of this diff, not judged)

Unchanged from rounds 4-5 and still correctly uncommitted; re-verified this round that the
committed `settings.json` contains zero `orca` references and all four guard hooks remain
registered. The standing advisory: `claude-hook.sh` line 10 sources `$ORCA_AGENT_HOOK_ENDPOINT`
*before* the `ORCA_*` gate on line 12, and only stderr is redirected — so the sourced file's stdout
becomes a `PreToolUse` hook's stdout, which can block or alter a tool call. Worth raising with the
user independently of this branch, and it does not gate this PR.
