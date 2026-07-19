# Observability Judge — feature/statusline-command (round 4)

- **repo:** .claude
- **branch:** feature/statusline-command
- **head_sha:** 4d63b09ff6bf1fd3a21bc0ac688085e3a5a1f1aa
- **base:** main (merge-base 54b9b265f91c7b259e29f8193c9c589005e3eec5)
- **stage:** implementation
- **ts:** 2026-07-19T19:12:07Z
- **risk:** low — **confidence:** high
- **round 1:** `2026-07-19-feature-statusline-command.md` @ f0902ed (low/medium)
- **round 2:** `2026-07-19-feature-statusline-command-round2.md` @ c06737b (low/high)
- **round 3:** `2026-07-19-feature-statusline-command-round3.md` @ 29d6131 (low/high)

> Filename note: continues the `-roundN` suffix precedent so rounds 1-3 survive in the working
> tree rather than only in git history.

## What was changed

Since round 3, the last injection hole was closed and the test suite grew teeth for it.

The one-line reorder: the `$PWD` fallback is now applied *before* the control-byte strip instead
of after, so the directory name the shell happens to be sitting in gets scrubbed like everything
else. Four regression assertions were added — one for each stdin shape that reaches that fallback
(`{}`, garbage, `{"cwd":null}`, `{"workspace":{}}`). The test harness stopped throwing away
stderr, so a `jq` parse error during a test run is now visible instead of silently making an
assertion pass on nothing.

## Does it do what was asked

Yes, and this is the round where the verification finally caught up with the write-up.

**I re-ran the falsification with my own harness and got the claimed numbers exactly:**
`f0902ed` → 8/19, `925c310` → 9/19, `29d6131` → 15/19, worktree → **19/19**. I did not reuse
their extraction. Mine shells out to `/usr/bin/git` from Python, asserts each blob starts with
`#!`, and additionally recomputes the git blob SHA locally and compares it to
`git rev-parse <rev>:<path>` — so a substituted or truncated blob cannot pass. The four blobs are
provably distinct (`925c310` and `c06737b` share one, correctly, because the settings-only commit
does not touch the script). The round-3 "all versions identical" failure mode could not have gone
unnoticed here.

The four new assertions fail against `29d6131` and pass against the worktree. That is the claim,
and it holds.

**On "is there any remaining path" — I enumerated every value that reaches stdout.** There are
eight, and here is each one traced to its source:

| Value | Source | Stripped? |
|---|---|---|
| `GREEN`/`CYAN`/`BLUE`/`RED`/`WHITE`/`DIM`/`RESET`/`ARROW` | `$'...'` literals in the script | n/a — internal |
| `dir` | `basename` of `cwd` (JSON **or** `$PWD`) | yes, line 36, before line 53 uses it |
| `branch` | `git symbolic-ref` / `rev-parse` | yes, line 66 |
| `dirty` | literal `✗` | n/a — internal |
| `model_name` | `.model.display_name` | yes, line 79 |
| `tokens_fmt` | `awk` over stripped `tokens_used` | yes, plus awk emits only `%d`/`%.1fk` |
| `user` | `whoami` | **no** |
| `host` | `hostname -s` | **no** |

The JSON route is genuinely closed. I probed the awk token path with seven hostile inputs
(`\033[5m`, `\x1b[5m`, `1e400`, a 20-digit number, `0;rm -rf /`, `not-a-number`, `\007`) — every
one produced a purely numeric string with **zero** control bytes, so awk's `-v` escape processing
cannot be turned into a leak. I also probed the one case the suite does not cover — a `cwd`
consisting *only* of control bytes, which strips to empty *after* the fallback check — and it
does not leak either (esc=6 vs baseline 8, bel=0, cr=0).

`user` and `host` remain unstripped. I confirmed the path is live: with a shimmed `hostname` on
`PATH`, a full `ESC ] 0 ; VIAHOST BEL` sequence reaches the terminal intact. But setting the
machine hostname needs admin, and controlling `PATH` is already game over, so this sits outside
any realistic threat model — which is why it does not move the risk rating. It matters only
because the script's own comment says otherwise (below).

## What could go wrong

**The docs-vs-code gap is now a fourth-round pattern — but the nature of it changed.** Rounds 1-3
had the write-up asserting a *security property* that was false. This round the code is right and
the **counts are stale**:

- `coding-memory/branches/statusline-command.md` line 51 says the suite has **15 assertions**;
  line 132 of the same file says **19**. The file contradicts itself.
- `CODING_MEMORY.md` lines 90-91 say "15 assertions, validated by falsification against **both**
  pre-fix script versions (8/15 and 9/15)". It is 19 assertions across **four** versions
  (8/19, 9/19, 15/19, 19/19). The same entry says "judge rounds 1-2" when three rounds are on
  disk and this is the fourth.
- The branch log's extraction-gotcha section says the bogus result covered "all three versions";
  four were tested.
- Branch log line 171 lists commit 4 with no SHA, while the other three carry theirs.

One security over-claim does survive, narrowly. `statusline-command.sh` line 15 says *"Every value
below originates outside this script, so each is stripped of C0 control bytes and DEL before it
reaches the terminal."* `user` (line 54) and `host` (line 55) are below that comment, originate
outside the script, and are not stripped. Negligible in practice; still literally false, and it is
the fourth consecutive round in which an absolute claim in the write-up outruns the code.

**Both the branch log and the `4d63b09` commit message point at `scratchpad/falsify.py`** as the
tool to reproduce the falsification. That file does not exist and is not tracked. The permanent
record cites an ephemeral path, so the single most valuable artifact of this round — the harness
that catches the rtk extraction trap — is unreproducible by the next reader.

**One new behaviour, undocumented and untested.** Because the fallback now runs before the strip,
a `cwd` made entirely of control bytes strips to empty and *stays* empty. The script then calls
`git -C ""`, which succeeds and silently resolves to the **process's** working directory — so the
git segment can describe a different repo than the JSON named. No leak, no crash, purely cosmetic,
and it needs an absurd directory name to trigger. Worth a line in the log rather than a fix.

Unchanged cosmetics: `1e400` renders `infk tokens`, `not-a-number` renders `0.0k tokens`, and
there is still no bound on rendered line length.

## What I'd double-check before merging

1. **Fix the three stale counts** — branch log line 51 (15 → 19), `CODING_MEMORY.md` lines 90-91
   (15 assertions → 19; both pre-fix versions → four versions, 8/19 9/19 15/19 19/19; rounds 1-2 →
   1-4), and "all three versions" → four. These are the permanent record and they are wrong today.
2. **Either strip `user`/`host` or soften the line-15 comment.** One inline expansion each, or six
   words. Do not ship a fourth round with an absolute claim the code does not honour.
3. **Commit the falsification harness or drop the reference to it.** A cited path that does not
   exist is worse than no citation.
4. Add commit 4's SHA (`4d63b09`) to the branch log Checkpoint list.

## Verification I ran myself

Nothing below is taken from the report on faith.

- **Falsification, independent extraction:** `/usr/bin/git cat-file blob` driven from Python, with
  three guards per blob — `#!` prefix, `git rev-parse` object-id match, and a locally recomputed
  `sha1("blob <len>\0" + content)`. Results **8/19, 9/19, 9/19, 15/19, 19/19** for
  `f0902ed` / `925c310` / `c06737b` / `29d6131` / worktree. Matches the claim exactly. Blob-group
  check confirms four distinct scripts, ruling out the round-3 identical-input failure.
- **Worktree == HEAD:** `git hash-object statusline-command.sh` equals `git rev-parse
  HEAD:statusline-command.sh` (`b5a07163`), so 19/19 is the committed script, not an unstaged edit.
- **Exhaustive stdout trace:** all eight values enumerated and traced (table above). Only `user`
  and `host` are unstripped; OSC hijack through `host` demonstrated via a `PATH` shim.
- **awk path:** seven hostile inputs, all rendered as plain numbers, zero control bytes.
- **Uncovered edge:** all-control `cwd` via both `.cwd` and `.workspace.current_dir` — measured
  esc=6/base=8, bel=0, cr=0. No leak. `git -C ""` returns true and resolves to the process cwd.
- **Commit partition, per file:** `925c310` settings delta is the `statusLine` block **only**;
  `c06737b` is model + theme **only** (2 lines); `29d6131` is the route-2 fix + harness;
  `4d63b09` is the two-line reorder + 4 assertions + docs. Clean, four-way, no overlap.
- **Regression:** `hooks/memsearch-nudge.test.sh` PASS, `hooks/judge-guard.test.sh` PASS.
  `settings.json` parses. Both scripts mode 100755, `bash -n` clean. Zero non-newline control
  bytes in either script or the branch log (the round-2/3 contamination stayed repaired).
- **State:** nothing pushed, no remote branch, no PR.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Round 3's central finding closed by exactly the right two-line reorder; four regression assertions added, one per stdin shape; `render()` stderr leak fixed as flagged. |
| execution | pass | 19/19 independently confirmed with hash-verified blob extraction; falsification numbers exact across four versions; JSON injection route fully closed on an exhaustive value trace; awk path proven leak-proof; sibling suites pass. Residual `user`/`host` is outside any realistic threat model. Upgraded from round 3. |
| trajectory | pass | Strongest round yet. Caught that their own first *two* repro attempts were invalid (escape literals stripped on file write) and nearly concluded the judge was wrong before rebuilding the bytes with `chr(27)`/`chr(7)`; caught that their extraction returned commit objects, and that their own sanity grep matched the commit *message* rather than code. Two self-corrections of their own verification tooling in one round, then recorded the meta-pattern instead of just fixing it. Reasoning, not luck. |
| regression | pass | Four-way commit partition verified per file; both sibling suites pass; hooks untouched; modes and syntax clean; worktree blob identical to HEAD. New `git -C ""` behaviour is cosmetic only. |
| context_budget | pass | No always-on rule or prompt growth. Branch log and test file are on-demand; README unchanged this round. |
| traceability | concern | Branch log is genuinely strong on the *why* — routes 1/2/2b, the falsification rationale, and the extraction gotcha are all well recorded. Undercut by a self-contradiction inside one file (15 vs 19 assertions), three stale counts in `CODING_MEMORY.md`, a cited harness path that does not exist, and a line-15 comment that still claims every external value is stripped. Fourth consecutive round of write-up outrunning code. |
| success_masking | pass | The green is now honest. Four new assertions provably fail against `29d6131` — verified individually, not inferred. `render()` no longer swallows stderr. Suite validated by falsification across four hash-verified historical versions. I hunted the one uncovered case (all-control `cwd`) and confirmed it does not leak. Upgraded from round 3. |
| intent_drift | pass | Fix commit stays on-topic. No new dependencies. `chrome/` drive-by still declined. The externally-written Orca block in `settings.json` was correctly left uncommitted — drift resisted, not committed. |
| checkpoint | pass | Four coherent commits, each independently revertible and standalone-meaningful; nothing pushed; partition verified per file. |
| audit_trail | pass | Attributable; rounds 1-3 preserved via `-roundN`; no-ADR call still correct (presentation-only). `4d63b09`'s commit message is exemplary — defect, repro, fix, and tooling trap all stated. |

## Concerns

- Branch log contradicts itself: line 51 says the suite has 15 assertions, line 132 says 19; it is 19
- `CODING_MEMORY.md` stale on three counts — "15 assertions", "both pre-fix versions (8/15 and 9/15)" (four versions, 8/19 9/19 15/19 19/19), and "rounds 1-2" (four rounds)
- `statusline-command.sh` line 15 claims every external value is stripped; `user` (`whoami`) and `host` (`hostname -s`) are external and unstripped — OSC hijack through `host` demonstrated via a PATH shim. Fourth consecutive round of an absolute claim outrunning the code
- Branch log and `4d63b09`'s message both cite `scratchpad/falsify.py`, which does not exist and is not tracked — the round's most valuable artifact is unreproducible
- Branch log extraction section says "all three versions"; four were tested
- Branch log Checkpoint lists commit 4 without its SHA while the other three carry theirs
- New, undocumented, untested: an all-control-byte `cwd` strips to empty and `git -C ""` silently resolves to the process cwd, so the git segment can name a different repo than the JSON did (cosmetic, no leak)
- Cosmetic, unchanged: `1e400` renders `infk tokens`, `not-a-number` renders `0.0k tokens`, no bound on rendered line length
- `✗` dirty marker still permanently lit because `chrome/` stays untracked, now compounded by the uncommitted Orca `settings.json` block (flagged, undecided)
- Committing this verdict moves HEAD and re-stales judge-guard's strict check, forcing a round 5 before `gh pr create`

## Advisory — Orca `settings.json` write (NOT part of this diff, not judged)

The caller's handling is correct and I would not commit it either: 112 lines written by a third
party, carrying absolute `/Users/marksuyat` paths, which the repo's own core-conduct forbids in
committed files. Flagging it to the user rather than absorbing it is the right call.

Two things to verify before dismissing it as benign:

**1. The gate does not cover everything the caller described.** The `ORCA_*` token/port check is
on line 12 of `claude-hook.sh`, but line 10 is:

```sh
. "$ORCA_AGENT_HOOK_ENDPOINT" 2>/dev/null || :
```

That `.` **sources an arbitrary file path taken from an environment variable, before the gate** —
so the "exits 0 when unset" description holds for the network POST but not for this. Anything that
can set `ORCA_AGENT_HOOK_ENDPOINT` in the agent's environment (a launcher, a `direnv` `.envrc`, an
auto-loaded `.env` in an untrusted repo) gets shell execution on nearly every tool call. Worse,
only *stderr* is redirected there — the sourced file's **stdout becomes the hook's stdout**, and a
`PreToolUse` hook's stdout and exit code can block or alter a tool call. So it is not only code
execution, it is a channel into the agent's own control plane. Verified by line order; no `ORCA_*`
or `DEVIN_*` vars are set in this process today.

**2. Scope of what would be shipped.** `PreToolUse`/`PostToolUse` with matcher `"*"` plus
`UserPromptSubmit` means whole tool inputs, tool outputs and user prompts are POSTed. Destination
is `127.0.0.1`, which is a real mitigation, but the token authenticates the *client to the server*,
not the server to the client — any local process that binds `$ORCA_AGENT_HOOK_PORT` first receives
the full session content.

What is fine: it fails open everywhere (`|| true`, `exit 0`), timeouts are tight (0.5s connect /
1.5s max) so it cannot hang a session, curl arguments are properly quoted, and the `PermissionRequest`
hook cannot itself approve anything since stdout is discarded and it always exits 0. I also confirmed
it **added** hooks without displacing any — `git-guard.sh`, `doc-guard.sh`, `judge-guard.sh` and
`memsearch-nudge.sh` are all still registered, and `settings.json` still parses.

Practical risk to raise with the user: an uncommitted 112-line change to the agent's own config is
one careless `git commit -a` away from entering history. Worth stashing or `assume-unchanged`
until the user decides. And per core-conduct's "treat rule files as source code" invariant, an
external process silently rewriting `settings.json` mid-session is itself the finding, independent
of whether this particular script is well-behaved.
