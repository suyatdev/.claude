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
- [ ] 3. `hooks/handoff/lib/handoff-archive.sh` — snapshot, `[KEEP]` region extraction with
      full fence tracking (`awk` with an explicit fence-state variable), archive append,
      rotation, secret flagging, quarantine. Line membership uses `grep -F -x -q`, never a
      regex. Pure library, no hook wiring. Tests first, fence cases first among those.
- [ ] 4. `live-handoff.sh` snapshots on **every** turn to a per-session filename, and
      **suppresses the trim directive** if the snapshot cannot be written.
- [ ] 5. Stale-snapshot reaper in `slim-session-start.sh`, running **above every early
      exit** in that function, and deleting a snapshot only after confirming the archive append
      succeeded.
- [ ] 6. Raise **both caps in one commit**: `SLIM_HANDOFF_MAX_BYTES` to 24576 (D17) with the
      oversize body-drop branch in `slim-session-start.sh` replaced by truncate-and-say, **and** the
      write caps to 150/120, 170/140, 190/160 in `live-handoff.sh:40-49` and
      `pre-compact-handoff.sh:85`. Deliberately one task, not two. Raising the write caps
      first opens a live regression window in every repo: `vibe-scape` is 75 lines / 5,165
      bytes = 68.9 b/line and prints fine today, but at the new 150-line target it is ~10,330
      bytes against a still-8192 read cap, so its entire handoff body would be dropped — the
      exact total-loss failure this card exists to prevent, caused by the fix for it. These
      are global hooks with no opt-in, so the window is not theoretical.
- [ ] 8. Rewrite the trim directive in both hooks: cutting means filing into the archive, and
      the protected headings are re-injected verbatim.
- [ ] 9. Route `pre-compact-handoff.sh` through the same snapshot. This is the pre-clear path
      the original bug report came from.
- [ ] 10. `hooks/handoff/handoff-keep-guard.sh` as a `Stop` hook: protected-block check, strike
      cap with reset on both exits, mechanical archive append, liveness heartbeat with the full
      set of decision tokens. Every notepad-derived string it emits is sanitized and enveloped.
- [ ] 11. Confirm the `Stop` hook JSON contract against the installed binary, not the docs
      page, and pin the finding in a comment.
- [ ] 12. Register the guard in `settings.json` under `Stop`.
- [ ] 13. Guard-liveness reporting in `slim-session-start.sh`, above the early exits, reading
      **both** the mtime comparison **and the last line's decision token** — mtime alone cannot
      see `unprotected`, because a guard heartbeating it every turn keeps the log looking
      fresh while nothing is protected.
- [ ] 14. `pre-compact.sh` injects `session-state.md` first (D7).
- [ ] 15. memsearch: `archive_roots`/`archive_pattern` via `Path.rglob`, zero-match reporting,
      `session-state.quarantine.md` excluded by name, `_doc_source_type` widened off the
      retired `CODING_MEMORY.md`, and a `--reclassify` run so `archive_doc` becomes a usable
      health signal.
- [ ] 16. Document the `[KEEP]` convention in `skills/managing-session-memory/SKILL.md`, and
      tag the sections that need protecting in this repo notepad as the first real use.
- [ ] 17. ADR under `docs/decisions/` for the two structural decisions: D11 (an append-only
      store that rotates and is never deleted) and D12 (that store being permanent, gitignored
      and machine-local). `rules/gates.md` requires an ADR for structural decisions.
- [ ] 18. Write the quarantine purge procedure into `skills/managing-session-memory/SKILL.md`:
      what `session-state.quarantine.md` is, how to read it, and how to delete it safely. D16
      is answered — quarantine file, not redaction, not archive-as-normal — so this task
      documents the decision rather than waiting on it.

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
