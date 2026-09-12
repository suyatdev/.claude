---
phase: implementation
model_tier: high
branch: feat/handoff-trim-safety
worktree: ~/.worktrees/.claude/handoff-trim-safety
gate_confirmed: 2026-09-08
---

# Handoff trim safety — stop the session notepad losing facts

`.claude/session-state.md` is the notepad the next session reads after a `/clear`. Past its
line cap the only mechanism is a directive telling the model to delete text: no copy is kept,
nothing is marked un-cuttable, and separately the session-start reader drops the entire body
past 8192 bytes. Facts vanish silently, twice over.

Live proof, not theory: `mtg-wizard` was 235 lines at 10:42 on 2026-09-08 and 64 lines at
13:56 the same day — roughly 171 lines cut with no snapshot and no record, while this card
sat waiting to be judged.

**Measured evidence, the fifteen user decisions D1-D15, and the full spec live in
[`handoff-trim-safety.spec.md`](handoff-trim-safety.spec.md).** Read it before implementing;
do not read it at session start.

Status: **implementation** — the gate opened 2026-09-08 on the literal phrase; the
frontmatter `phase` is the authority and this line must agree with it. Both judges PASSED
on the spec and must run again after implementation, before any PR.

Compliance: FAILED seven times (9, 8, 7, 4, 1, 5, 1 violations across rounds 1 to 7), then
**PASSED with zero violations in round 8**. Observability: failed `success_masking` in rounds
2, 3 and 4, then **passed in round 5**, where it also stated the design is ready to hand to a
human reviewer. Counts come from `coding-memory/compliance-judge/verdicts.jsonl`; read them
there rather than trusting this sentence, which has been stale twice.

Every finding across all rounds was independently re-measured before being acted on, and every
one held — including one this session first reported as not reproducing, which did reproduce
and had been missed by a line-based search of line-wrapped prose. Two round-2 findings were
defects the design would otherwise have shipped: the replacement memsearch globs matched
**zero** files, and the evidence table carried a byte-per-line range that re-measurement
falsified. From round 5 onward the findings were predominantly **introduced by the previous
round's own edit** rather than surviving from the original design — a review loop feeding on
itself, whose correct exit is a pass.

**D16 answered** (2026-09-08): a secret-looking cut block goes to
`session-state.quarantine.md` — never the archive, never indexed, deletable by hand.
**D17 answered**: the read cap is 24,576, confirmed against the arithmetic and the context
cost, superseding the ~12,000 in D6.

The gate **opened 2026-09-08** on the literal phrase, and the frontmatter `phase` records it.
An earlier revision of this line said the opposite and survived six commits past the event; if it
and the frontmatter ever disagree again, the frontmatter is the authority.

## Tasks

Ordered so every step is independently useful and nothing depends on a later step. **The list
skips 7 on purpose** — the read-cap step was folded into the write-cap step so both caps rise in
one commit, and the numbers were deliberately not re-flowed, because re-flowing them is what made
cross-references stale before. Steps are referred to by what they do, never by number. The ignore
rules come **first**, before anything writes a file they are meant to cover — an earlier
ordering created per-turn byte-identical copies of the notepad seventeen tasks before the rule
that ignores them, in two repos measured as not covering them today.

- [x] 1. Ignore rules, everywhere, before any new file exists. In every repo holding a
      notepad, confirm with `git check-ignore` — never assume — that
      `session-state.archive*`, `session-state.pretrim.*`, `session-state.keepguard-strikes.*`,
      `session-state.keepguard.log` and `session-state.quarantine.md` are all ignored.
      **Re-measured 2026-09-08** by walking every notepad on disk and resolving each to its
      repo, which corrected two errors in the original wording. The notepads live in **four**
      git repos, not six — `~/.claude`, `Snatch-Bracket`, `vibe-scape`, `mtg-wizard` — plus
      `~/Other Docs/AI/AI_Projx/.claude`, which is not a repository at all, and worktrees of
      the first two. **Three** repos covered none of the five names, not two: `Snatch-Bracket`
      lists `.claude/` paths one by one exactly as `vibe-scape` and `mtg-wizard` do, and the
      original wording did not name it. `~/.claude` needs **no** new sidecar rule: the hooks
      write to `$REPO_ROOT/.claude/` (`hooks/handoff/live-handoff.sh:25`) and this repo already
      ignores `/.claude/` wholesale (`.gitignore:87`); the root-level rule for the hand-kept
      `session-state.md` is a separate file, committed at `1476a46` **on this branch only** —
      it is absent from `main`, and the primary checkout is protected today merely by an
      uncommitted `.gitignore` edit, so a clean checkout of `main` still loses that file
      until this branch merges. Measured 2026-09-09. Landed in
      the other three as branch `chore/ignore-notepad-sidecars`, each cut from its own
      worktree off `origin/main` so that no in-flight branch was disturbed — `Snatch-Bracket`
      `4c39519`, `vibe-scape` `2245b8e`, `mtg-wizard` `99286e0`, one `.gitignore` and eleven
      inserted lines each, verified by reading each commit back. Left unpushed by design.
      Verified by `check-ignore` on all five names plus a rotated archive, and falsified by
      deleting one rule and confirming the check reports not-ignored. **Known gap:** the
      `Snatch-Bracket` worktree on `chore/close-mutation-seed-chain` carries its own copy of
      `.gitignore` and stays uncovered until that branch takes main.
- [x] 2. Extract `gen_tag`, `sanitize_line` and the three module-level values they read
      (`MARKER_PATTERN`, `TAG_BYTES`, `URANDOM_SRC`) from `slim-session-start.sh` into
      `hooks/handoff/lib/handoff-archive.sh`, with tests, leaving both call sites behaving
      identically. Moving a working function out of a hook that passes its tests is the
      riskiest edit here, so it goes early and alone. **Done 2026-09-09.** The five items
      moved byte-verbatim, bodies and comments together; `slim-session-start.sh` now resolves
      the library from `${BASH_SOURCE[0]}` rather than `$PWD` or `git rev-parse`, because the
      existing suite sources the hook from a throwaway repo elsewhere on disk. Measured
      before and after: the untouched `slim-session-start.test.sh` reads **29/29** on both
      sides of the move, which is the whole evidence for *behaving identically*; the new
      `hooks/handoff/lib/handoff-archive.test.sh` reads **28/28** and carries a falsifier that
      strips `shopt -s nocasematch` from a **copy** of the library and confirms the uppercase
      marker then goes unsanitized, so the case-insensitivity assertions are shown able to
      fail rather than assumed to be. Three library states are now pinned, not two: missing
      and unreadable both give exit 0 with nothing on stdout **or** stderr, while a third —
      present, readable, and not parseable — gives exit 0 and empty stdout but is
      **deliberately not silenced**, since a library that fails to load is a real defect and
      swallowing it would rebuild the silent-death shape this card exists to prevent. The
      false citation at `slim-session-start.sh:14` is fixed as the spec instructs: `git-guard.sh`
      was opened and confirmed to contain **zero** `[[ ]]` constructs, so the anchor was dropped
      rather than repointed, and the replacement states a mechanism verified by running it —
      a bare `(` or `;` inline in `[[ =~ ]]` is a bash parse error, exit 2, measured for both
      characters. **Known and out of scope:** the identical false citation survives at
      `phase-guard.sh:22`, and `judge-guard.sh:24`, `feature-sync-guard.sh:49` and
      `doc-guard.sh:31` each attribute the same rule to `git-guard.sh` with no line number;
      none were touched.
- [x] 3. `hooks/handoff/lib/handoff-archive.sh` — snapshot, `[KEEP]` region extraction with
      full fence tracking (`awk` with an explicit fence-state variable), archive append,
      rotation, secret flagging, quarantine. Line membership uses `grep -F -x -q`, never a
      regex. Pure library, no hook wiring. Tests first, fence cases first among those.
      **Done 2026-09-09** at `716a816`: nine functions and two constants, written test-first
      with the fence cases first. Measured rather than reported — the new suite reads
      **79/79** and the untouched sibling `slim-session-start.test.sh` still reads **29/29**,
      which is the whole evidence that the existing consumer was not disturbed; both were
      re-run independently against the committed bytes under `/bin/bash` 3.2.57. Four
      falsifiers mutate a **copy** of the library and each is confirmed to flip its paired
      assertion red: fence tracking removed, `grep -F` swapped for a regex, the rotation
      threshold made to ignore the pending size, and the secret check made fail-open. Two
      properties of `/usr/bin/awk` were measured against the real binary rather than assumed —
      it **does** support `{n,m}` interval expressions, and it does **not** treat `--` as an
      end-of-options marker, which surfaced as a live bug (every extraction returned empty)
      before it was found. Verified end to end against the **real** `scan-secrets.sh` and not
      a stub: a clean block lands in the archive, a block carrying a fake AWS key lands in the
      quarantine file leaving only a heading-only stub in the archive, and the archive is
      confirmed not to contain the credential.
      ⚠️ **Two gaps the later steps must not build on.** `missing_protected_lines` returns
      rc 0 when the *snapshot* is missing or unreadable, so "nothing was protected" is
      indistinguishable from "nothing is missing" — the keep-guard step must test for the
      snapshot itself before reading that rc, or the no-snapshot case silently becomes
      `allow` where the spec requires `unprotected`. And `secret_labels` fails **open** where
      `block_has_secret` fails **closed**: an unavailable scanner still quarantines the
      block, which is the safe direction, but records an empty reason in the stub — the one
      case where the reason matters most says nothing. The file is now **398 lines** against
      the 400-line house guideline, so the next step to touch it should split rather than grow.
- [x] 4. `live-handoff.sh` snapshots on **every** turn to a per-session filename, and
      **suppresses the trim directive** if the snapshot cannot be written.
      **Done 2026-09-10.** The hook reads `session_id` off the stdin payload, falls back to
      `$CLAUDE_CODE_SESSION_ID` and then to the same `nosession` literal
      `secret-command-guard.sh` uses, and sanitizes it to the portable-filename set before it
      reaches a path. Measured rather than reported: the new
      `hooks/handoff/live-handoff.test.sh` reads **31/31**, and both untouched siblings still
      read what they read before — `handoff-archive.test.sh` **79/79** and
      `slim-session-start.test.sh` **29/29**, which is the whole evidence that the extracted
      library and the session-start reader were not disturbed. The suppression carries a
      falsifier that strips the `SNAPSHOT_OK` conjunct from a **copy** of the hook and
      confirms the trim directive then fires with no snapshot behind it, so the no-trim
      assertion is shown able to fail; that falsifier also asserts its own `sed` changed
      something, because a mutation that silently matched nothing would have proved nothing.
      The traversal check plants a decoy stray file and confirms the search counts it, after
      a first version scoped that search so narrowly that six other fixture repos' correct
      snapshots read as escapes.
      **One behaviour beyond the literal task wording, recorded because it is load-bearing:**
      a snapshot is *not* refreshed while a keep-guard strike file sits beside it. Snapshot
      on every turn plus keep-the-snapshot-on-block would otherwise have the next turn
      overwrite the pre-damage copy with the damaged notepad — destroying the recovery source
      at the moment it is needed, and making the scenario "the guard has already blocked
      twice on the same PT" unreachable. A strike file with **no** snapshot beside it still
      snapshots normally, so a deleted copy plus a stale strike file cannot leave a session
      permanently unprotected.
      ⚠️ **Two stated limits.** The strike filename is a contract with the keep-guard step,
      which does not exist yet: nothing writes that file today, so the retention branch is
      tested but not yet exercised in real use. And if `/usr/bin/jq` is absent the id falls
      back to the environment variable and then to `nosession`, so every session in one repo
      would share one snapshot — the exact C2 blinding the per-session filename exists to
      prevent. Degraded rather than silent: one shared snapshot still beats none.
- [x] 5. Stale-snapshot reaper in `slim-session-start.sh`, running **above every early
      exit** in that function, and deleting a snapshot only after confirming the archive append
      succeeded.
      **Done 2026-09-10.** `reap_stale_snapshots` takes `REPO_ROOT` directly and never reads
      `state_file`, so it still reaches the orphaned-snapshot case — notepad gone, snapshot the
      only surviving copy — that every early exit below it would otherwise skip (finding C6).
      Measured rather than reported: `slim-session-start.test.sh` reads **48/48**, which is the
      29 assertions standing when task 4 closed plus 19 new ones (fourteen scenario, five
      falsifier); both untouched siblings still read what they read before —
      `handoff-archive.test.sh` **79/79** and `live-handoff.test.sh` **31/31**, the whole
      evidence that the library and the per-turn snapshotter were not disturbed.
      Two falsifiers, each built from a **copy** of the real hook and each asserting its own
      mutation changed something first. **A** moves the reaper call below the `session-state.md`
      early exit and confirms the orphaned snapshot then goes unarchived — the whole evidence
      that the ordering assertion tests ordering rather than mere presence; it also asserts the
      mutant still holds exactly one call, so a mutation that deleted the call instead would be
      caught rather than counted as proof. **B** makes the delete unconditional and confirms the
      snapshot is then destroyed by the same append failure the real hook survives. B needed its
      own fixture: the read-only-`.claude` scenario above blocks the mutant's `rm` too, since
      removing a file needs write permission on the *directory*, so B leaves `.claude` writable
      and makes only the archive file unwritable.
      ⚠️ **Two stated limits.** The reaper reads mtime with BSD `stat -f %m`, the same call the
      hook's existing staleness check already uses (`slim-session-start.sh:104`) rather than a
      new portability debt; where that call fails, both go blind together and the reaper's
      digit check skips the file, so the failure direction is "nothing is reaped", never
      "something is deleted unarchived". And the append-failure line is this hook's **one**
      exception to its silent-on-every-failure contract, now recorded in the file header:
      staying silent there would delete the last copy of removed text with no record anywhere,
      this card's own headline disaster reproduced by its own fix.
- [x] 6. Raise **both caps in one commit**: `SLIM_HANDOFF_MAX_BYTES` to 24576 (D17) with the
      oversize body-drop branch in `slim-session-start.sh` replaced by truncate-and-say, **and** the
      write caps to 150/120, 170/140, 190/160 in the `MAX_LINES` block of `live-handoff.sh`
      (the three assignments and the 60-80 / 80-100 / 100-120 comment directly above them)
      and on the line beginning `Line targets:` inside the directive heredoc of
      `pre-compact-handoff.sh`. Both are named by content, not by line: the earlier
      `live-handoff.sh:40-49` citation was measured wrong on 2026-09-10 — the snapshot task
      had grown the file and 40-49 is now the session-identity block, while the caps had
      moved to 88-98. The `pre-compact-handoff.sh:85` citation was re-measured at the same
      time and was exactly right, so this is a de-numbering, not a correction of both.
      Deliberately one task, not two. Raising the write caps
      first opens a live regression window in every repo: `vibe-scape` is 75 lines / 5,165
      bytes = 68.9 b/line and prints fine today, but at the new 150-line target it is ~10,330
      bytes against a still-8192 read cap, so its entire handoff body would be dropped — the
      exact total-loss failure this card exists to prevent, caused by the fix for it. These
      are global hooks with no opt-in, so the window is not theoretical.
      **Done 2026-09-12**, across two commits (tests first, deliberately red, then the
      implementation) because a single commit cannot hold both an inverted assertion and the
      behavior that inverts it. Verified by re-running each suite directly:
      `slim-session-start` **67/67**, `live-handoff` **31/31**, `pre-compact` **20/20**,
      `handoff-archive` **79/79** with `handoff-archive.sh` still **399** lines — the evidence
      the shared `extract_keep_lines` was called and not grown.
      Withheld-line contract, copied from real runs rather than paraphrased:
      `[truncated: 319 lines (3509 bytes) withheld — read .claude/session-state.md directly]`
      and `[truncated: 351 lines (4568 bytes) withheld — 3 inside [KEEP] regions — read
      .claude/session-state.md directly]`. On the 500-line / 5,500-byte fixture at a 2,000-byte
      cap the arithmetic closes both ways: 181 emitted + 319 withheld = 500 lines,
      1,991 + 3,509 = 5,500 bytes.
      The positional KEEP check rests on a property **re-measured here, not inherited** — the
      prior session's probe was lost with its scratchpad. `extract_keep_lines(head -n K f)` is
      the leading portion of `extract_keep_lines(f)` at **43/43** cut points of a fixture with
      front matter, two regions and fences, and at **28/28** of a second fixture whose trap
      fence (carrying a fake `[KEEP]` heading) sits in an *unprotected* region — the over-count
      case the first fixture missed, where the count stayed flat across all 8 mid-fence cuts.
      Count is monotone non-decreasing, so `prefix < whole` ⟺ a KEEP line was cut. Control: a
      tail-instead-of-head mutant of the same probe reports **27/43** mismatches, so the green
      discriminates.
      Four mutations were run against the implementation to confirm the new assertions bite.
      The first three were measured against the **63**-assertion suite, before the
      byte-semantics scenario existed: always-claim-KEEP fails B2 (62/63); never-claim-KEEP
      fails B1 (62/63); removing the budget check fails four, including the byte ceiling at
      `emitted=5500 cap=2000` (59/63). The fourth found a real gap — deleting `local LC_ALL=C`,
      so `${#line}` counts characters instead of bytes, left the suite **63/63 green**. Every
      fixture was pure ASCII, where the two are identical, so byte accounting was correct but
      entirely unpinned. The missing control was added (one 11-byte ASCII line then 8 em dashes
      = 25 bytes but 9 characters, at the exact 20-byte cap where character accounting just
      admits it) and it bites: **67/67 → 65/67** under that mutation.
      Re-pointing the write-cap fixtures was **not** listed in this task and is the part that
      would have rotted silently. Five `live-handoff.test.sh` fixtures used 140 lines to mean
      over-the-cap against the old general cap of 80; four fail outright at the new 150. The
      quiet one was `repo-task` at 90 lines, whose whole purpose is proving the task cap is
      consulted: at the new caps 90 is under both 150 and 170, so it would have kept passing
      while proving nothing. All six re-pointed to 160, which is over the new general cap and
      under the new task cap.
- [ ] 8. Rewrite the trim directive in both hooks: cutting means filing into the archive, and
      the protected headings are re-injected verbatim.
- [ ] 9. Route `pre-compact-handoff.sh` through the same snapshot. This is the pre-clear path
      the original bug report came from.
- [x] 10. `hooks/handoff/handoff-keep-guard.sh` as a `Stop` hook: protected-block check, strike
      cap with reset on both exits, mechanical archive append, liveness heartbeat with the full
      set of decision tokens. Every notepad-derived string it emits is sanitized and enveloped.
      **Done 2026-09-10.** 371 lines of hook, 385 of suite, **47/47 passing**, and
      `handoff-archive.test.sh` still **79/79** — the evidence the shared library was called
      and not grown. The six liveness decision tokens (`allow`, `block`, `unprotected`,
      `failopen`, `archive_failed`, and the log-write-failure escalation) are each asserted.
      `MAX_STRIKES=2`, taken from spec Constants, not chosen.
      The library gap the spec warns about is handled rather than inherited: because
      `missing_protected_lines` returns rc 0 both when nothing is missing *and* when the
      snapshot is absent or unreadable, the hook tests for the snapshot **first** and emits
      `unprotected` — never `allow` — when there is nothing to compare against. For the secret
      check it goes through `file_removed_block`, which uses the **fail-CLOSED**
      `block_has_secret`: an unreadable scanner quarantines rather than publishing into a
      permanent, indexed archive. `secret_labels`, which fails open, is deliberately unused.
      ⚠️ **Process deviation, recorded rather than hidden.** The implementer wrote the hook and
      its suite together instead of test-first, which `rules/core-conduct.md` forbids precisely
      because a co-written test can be shaped to fit the code. It disclosed this rather than
      claiming TDD. The suite was therefore **re-validated independently by two mutations the
      implementer did not run**: forcing the survival check to always pass turns **16 of 47**
      red, and raising `MAX_STRIKES` to 99 turns **6** red — distinct, narrow sets, not a
      blanket failure. The suite discriminates. That is evidence the tests are real; it is not
      a substitute for the ordering rule, and the next task should not repeat the shortcut.
      Two genuine defects surfaced during that work and are fixed: `awk -v` silently mangles
      `\[KEEP\]` through C-style escape processing, so the regex is inlined in the awk program
      text as the library itself does; and the ATX `#` prefix must be stripped before
      `sanitize_line`, whose `MARKER_PATTERN` is anchored and would otherwise never fire on a
      heading.
      One judgment call flagged: the heartbeat log rotates on a local timestamp scheme rather
      than reusing `archive_rotate_if_needed`, which hardcodes a `.md` suffix and would misname
      `session-state.keepguard.log`. No scenario pins the rotated name, so nothing is violated.
- [x] 11. Confirm the `Stop` hook JSON contract against the installed binary, not the docs
      page, and pin the finding in a comment.
      **Done 2026-09-10**, pinned at the top of `handoff-keep-guard.sh`, attributed to
      `/Users/marksuyat/.local/bin/claude` **2.1.267** and dated, so a later reader can tell
      when it was true. Four findings, each read out of the binary rather than the docs site:
      `decision` accepts **only** `approve` or `block` (the validator string is
      `Unknown hook decision type: … Valid types are: approve, block`); the four-value
      `allow/deny/ask/defer` set belongs to `hookSpecificOutput.permissionDecision` and is
      **PreToolUse-only**; `hookSpecificOutput` for Stop is
      `{hookEventName, additionalContext}`, and the consumer routes `case "Stop"` through the
      **same** generic handler as `PostToolUse`, so injected context genuinely reaches the
      model; and the binary advises returning success while `stop_hook_active` is true.
      ⚠️ **The load-bearing find:** the runtime **already caps consecutive Stop-hook blocks at
      8** — `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP ?? 8` — and past that it warns and ends the turn
      whatever the hook says. This is what makes `keep_guard.max_strikes: 2` a real control
      rather than dead code, and it means any future proposal to raise that cap to 8 or beyond
      would silently hand the decision to the runtime. Checked *before* building on it, not
      after.
- [ ] 12. Register the guard in `settings.json` under `Stop`.
- [ ] 13. Guard-liveness reporting in `slim-session-start.sh`, above the early exits, reading
      **both** the mtime comparison **and the last line's decision token** — mtime alone cannot
      see `unprotected`, because a guard heartbeating it every turn keeps the log looking
      fresh while nothing is protected.
- [x] 14. `pre-compact.sh` injects `session-state.md` first (D7).
      **Done 2026-09-10.** New suite `hooks/handoff/pre-compact.test.sh`, **20/20**, written
      before the hook changed and confirmed RED at **12/20** first — the eight failures were
      exactly the notepad assertions, while the pre-existing three-file behaviour and all
      three falsifiers stayed green throughout, so the suite was measured against both
      states rather than only the one it was written for.
      Two things beyond the one-line task, both deliberate. The notepad is read by `cat`
      itself rather than behind a `-r` probe, and an unreadable notepad is **named** in the
      output instead of skipped. Measured on a mutant with that guard removed: a bare `cat`
      under `set -euo pipefail` exits 1 and takes `context.md` and the other two files down
      with it, so the vendored pattern would have turned one unreadable notepad into total
      loss of all four files — this card's own headline failure, reproduced by the fix for
      it. That mutation is also the receipt that the two unreadable-notepad assertions
      discriminate at all: **both of them pass while the suite is red**, because a notepad
      that is never read is never unreadable, and a green run alone would not have shown it.
      Not done, and recorded rather than silently decided: this hook emits all four files
      **unsanitized**, exactly as the vendored original did. `slim-session-start.sh`
      sanitizes the notepad it reads, so the two read paths now disagree. Nothing in D7 or
      in any scenario asks this path to sanitize, and sanitizing one file of the four would
      be incoherent, so it is left as an open question for a later card — not a gap this
      task closed, and not a decision this task was scoped to make.
- [x] 15. memsearch: `archive_roots`/`archive_pattern` via `Path.rglob`, zero-match reporting,
      `session-state.quarantine.md` excluded by name, `_doc_source_type` widened off the
      retired `CODING_MEMORY.md`, and a `--reclassify` run so `archive_doc` becomes a usable
      health signal.
      **Done 2026-09-10, with one half of the intent explicitly NOT delivered — see below.**
      `_iter_archive_docs` walks the three roots with `Path.rglob`, dedupes against the files
      the `curated_docs` and `repo_roots` walks already yielded, and reports a zero-matching
      root on stderr instead of indexing as though nothing changed. `_doc_source_type` gained
      an optional third argument so a file matching `archive_pattern` types as `archive_doc`
      whichever bucket found it; the existing two-argument call sites are untouched, which is
      why the pre-existing suite needed no edit.
      **Measured: 110 passed, 23 deselected.** The 23 are the `golden` and `measurement`
      marks that `pyproject.toml` deselects by default, and this card has been bitten by that
      exact line before, so it was checked rather than assumed: neither deselected file
      mentions archives at all, and all three files that do are in the selected set.
      **Falsified, not just green.** Swapping `root.rglob` for a non-recursive `root.glob`
      turns exactly two tests red, one of them
      `test_archive_roots_are_walked_with_rglob_into_dot_directories`. A suite that stayed
      green under that mutation would have been measuring nothing.
      ⚠️ **`archive_doc` is NOT yet a usable health signal, and the checkbox does not claim it
      is.** The real `--reclassify` run reported `retyped=0`, with the `archive_doc` chunk
      count at 514 before and 514 after, because **zero `session-state.archive*.md` files
      exist anywhere on disk** — the hook that writes them has not shipped. The plumbing is
      wired and proven; the signal turns on by itself once tasks 8 to 12 land. Re-run
      `--reclassify` then, and only then record what the count did.
      ⚠️ **A wrong number was caught in this task's own code comment before it committed.**
      The comment justified `Path.rglob` with "0 matches vs Path.rglob's 7 on the live tree",
      which is false for the pattern it sits beside: for `session-state.archive*.md` both
      return **0**. Re-measured on 2026-09-10, the real evidence is two separate facts —
      `glob.glob` never expands `~` (0 matches for all three roots, any pattern), and with `~`
      expanded its `**` still will not enter dot-directories (**6** vs `Path.rglob`'s **29**
      for `session-state*.md`). The comment now states those, and states that the shipped
      pattern cannot demonstrate the difference today.
      Unrelated drift seen while measuring, recorded so a later reader does not chase it: the
      reclassify run printed `vanished_sources=682`, and `repo_doc`/`judge_doc` counts moved
      between snapshots because the scheduled `launchd` indexer was running against the same
      live database. `retyped=0` is what shows this change caused none of it.
- [x] 16. Document the `[KEEP]` convention in `skills/managing-session-memory/SKILL.md`, and
      tag the sections that need protecting in this repo notepad as the first real use.
      **Done 2026-09-10.** The convention is written up under the skill's
      *Protecting Notepad Sections* heading — anchored by heading, not line number, because
      eleven anchors in this card went stale inside their own implementation phase. It states
      the ATX-only heading form, the setext exclusion, the region boundary, set-membership
      survival, and the both-directions fence rule, then names
      `hooks/handoff/lib/handoff-archive.sh` as authoritative over the summary so the two can
      never silently disagree.
      The **first real use** was an audit, not an edit: all eight tagged headings in
      `.claude/session-state.md` already conform, verified byte-for-byte rather than by eye —
      ATX form, `[KEEP]` the last non-whitespace on the line, no fenced block anywhere in the
      file to create a false region boundary. Only the H1 title and its three-line intro are
      untagged, and they are pointer text with nothing to lose. No corrections were needed, so
      none were invented.
      One claim in the first draft of that section was **wrong and was corrected before the
      commit**: it said the guard holds the turn open until the block is restored. It does not
      — `keep_guard.max_strikes` is 2, after which it fails open with a loud warning. The
      corrected text says so, because a doc that overstates a protection is worse than one that
      omits it.
- [x] 17. ADR under `docs/decisions/` for the two structural decisions: D11 (an append-only
      store that rotates and is never deleted) and D12 (that store being permanent, gitignored
      and machine-local). `rules/gates.md` requires an ADR for structural decisions.
- [x] 18. Write the quarantine purge procedure into `skills/managing-session-memory/SKILL.md`:
      what `session-state.quarantine.md` is, how to read it, and how to delete it safely. D16
      is answered — quarantine file, not redaction, not archive-as-normal — so this task
      documents the decision rather than waiting on it.
      **Done 2026-09-10.** Written up under the skill's *The Quarantine File* heading. It says
      what the file is (a flagged block diverted out of the permanent archive, which gets only
      a stub), that it is never indexed, how to read it (plain Markdown, but treat the contents
      as live credential material), and how to delete it — and it explains *why* this is the
      one archive-family file that is safe to delete by hand, which is the part a reader needs
      to act without asking: routing a suspected secret through a permanent, indexed,
      never-deleted store would make a false positive searchable forever.
      **Two gaps were flagged rather than filled.** The design specifies no retention period
      before deletion, and no migration path for blocks flagged before this file existed. Both
      are named in the skill as deliberately unspecified. Writing a plausible rule for either
      would have read as settled design in a document a later session trusts, which is exactly
      the failure mode this card exists to prevent.

Split into `handoff-trim-safety.spec.md`, exercising the MAY in `rules/gates.md`
(one-canonical-file discipline). The card keeps frontmatter, tasks and verification — what a
restore needs; the companion keeps evidence, decisions and the spec — what an implementer
needs. There is no third progress document, and there will not be one.

⚠️ `hooks/feature-sync-guard.sh` compares task identity only up to the first em dash, so it
cannot see a divergence in the text after it. That is measured, not assumed: a D16 divergence
between the two halves survived it with exit 0. Sync the halves by copying the whole section,
never by editing one side.

## Verification

**The measurement that decides whether this works.** Not "the archive file exists" and not
"the tests pass" — both are true of a design that archives nothing.

1. Seed the notepad with N unique, greppable tokens, at least one inside a `[KEEP]` region
   and at least one outside it.
2. Drive a real trim through the real hook, not a simulation.
3. Assert every token that left `session-state.md` is **byte-present** in
   `session-state.archive.md`, and that every `[KEEP]` token is still in the notepad.
4. **Then stub out the archive append and re-run.** The test must go red. A check that cannot
   fail has measured nothing (memory: `feedback_confirm_the_check_can_fail`).

**Falsifiers, each paired to the scenario *and the assertion* that must go red.** Naming only
the mutation was not enough: three rounds running, a row pointed at a scenario that did not
exist or did not assert the thing. Every row below names a scenario by its exact title and the
clause inside it that fails. A row whose scenario title cannot be found by search is a defect
in this table, not a missing test.

| Mutation | Scenario | Clause that must go red |
|---|---|---|
| Archive append deleted | A normal trim archives what it cut | `And the guard appends the 47 removed lines to AR under an Auto-captured heading` |
| `[KEEP]` heading regex matches nothing | A protected line is deleted | `Then the guard blocks the turn` |
| Fence tracking removed (region end) | A heading inside a fenced code block does not end a region | `Then the inner line is body` |
| Fence tracking removed (region open) | A [KEEP] heading inside a fenced code block does not open a region | `Then no region opens` |
| Fence char/length matching removed | A tilde fence does not close a backtick fence | `Then the fence is still open` |
| Strike reset removed | The guard must not wedge the session | `And it deletes the strike file` |
| Snapshot-failure suppression removed | The snapshot cannot be written | `Then no trim directive is emitted` |
| Archive-append failure handling removed | The archive append fails | `And the snapshot is NOT deleted` |
| Log-write failure silenced | The liveness log cannot be written | `Then it reports the failure in its Stop output` |
| `unprotected` collapsed into `allow` | The guard runs with no snapshot present | `Then the liveness line records decision=unprotected` |
| Session-start reader consults only mtime | The session-start report reads the last decision token | `And a reader that consults only mtime fails this scenario` |
| Quarantine reverted to per-file skip | A block that looks like a secret is quarantined, not archived | `And the rest of AR indexes normally` |
| Sanitizer removed from a notepad-derived string | A notepad heading that mimics an envelope marker is defanged | `Then the heading is prefixed by the sanitizer` |
| Envelope removed from a notepad-derived string | A notepad heading that mimics an envelope marker is defanged | `And the model sees one well-formed DATA envelope, not two` |
| Reaper moved below the early exits | An orphaned snapshot is reaped even when the notepad is gone | `Then the reaper runs before any early exit` |
| Reaper deletes before confirming the append | The reaper cannot append | `Then the snapshot is left in place` |
| Matcher reverted to `glob.glob` without `include_hidden` | The archive matcher finds the live population | `Then it returns a non-zero count for every root that holds an archive` |
| Zero-match reporting removed | A root that matches nothing is reported | `Then the run report names that root` |

**How to check this table, since reading it is not checking it.** Extract every scenario title
from the spec, extract every scenario name from this table, and diff the two sets. Every row
must resolve. That mechanical check is what caught the last three failures; the prose claiming
coverage never did.

**R1 is measured at runtime, not asserted between constants.** The test walks the live notepad
population, computes bytes per non-blank line for each, and reports the maximum against the
configured read cap. It is allowed to report a shortfall — that is the point. A shortfall is
degraded-but-safe, because the reader truncates rather than blanks; a *blank* is a failure.

**Rollout evidence to collect once live (D14 chose full immediate enforcement).**

- Every repo has a `session-state.keepguard.log` with at least one line. A repo without one
  means the registration did not take there.
- At least one real trim has produced an `Auto-captured` block whose line count matches the
  drop in the notepad line count.
- `mtg-wizard` specifically: it lost roughly 171 lines unrecorded on 2026-09-08 while this
  card was being judged. The first trim after rollout must leave a record.
- memsearch reports zero-match on no configured root.

**Explicitly not proven by any of the above:** that a secret is never archived (gap 7), that a
subagent edit is caught (gap 1), or that a determined model cannot delete the snapshot first
(gap 2). Those are stated limits, not test targets.
