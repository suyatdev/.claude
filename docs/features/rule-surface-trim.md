---
phase: implementation
model_tier: high
branch: chore/rule-surface-trim
---

# Rule-surface trim — retire the coding-memory duplication and the hooks that enforce it

Planned 2026-08-20 on `main` @ `7fcfd95`.

The written record currently lives in two parallel trees. `docs/` (features, decisions,
superpowers plans) is the one that gets read. `CODING_MEMORY.md` + `coding-memory/` is the one
that gets *written* — 215 tracked files, appended at every freshness checkpoint, and reached by
targeted lookup only. This card removes the second tree, stops pushing it to GitHub, and updates
every hook and rule that currently enforces its existence.

## Evidence — measured 2026-08-20, re-run before acting

Four artifacts under `coding-memory/` are already dead. They were abandoned in place while the
rules kept demanding them:

| Artifact | Last commit | Duplicates |
|---|---|---|
| `coding-memory/session-log.md` | 2026-07-18 | `CODING_MEMORY.md` |
| `coding-memory/decisions.md` | 2026-07-19 | `docs/decisions/` (27 ADRs) |
| `coding-memory/brainstorms/` (5 files) | 2026-07-22 | `docs/superpowers/specs/` |
| `coding-memory/branches/` (19 files) | 2026-07-27 | `docs/features/` cards |

`decisions.md` is the sharpest signal: it directs readers to `rules/pr-requests.md` and
`rules/session-state-management.md`. **Neither file exists.** It has been pointing at deleted rules
for a month and nothing surfaced it, because nothing reads it.

Still actively written:

- `CODING_MEMORY.md` — **7,247 lines / 578KB.** Its own line 3 reads *"This is an index only, kept
  at or under 200 lines."* It is 36× its stated cap. `managing-session-memory` already retired it
  as a read target, so it costs no read tokens; the cost is composing a ~40-line narrative entry
  per checkpoint. Those entries retell the feature card. The `global-option-blindness` entry says
  so in its own text — *"per-task reasoning, measurements, and verification detail live in the
  feature file's own `## Verification` section … not duplicated here"* — and then spends 30 lines
  re-narrating tasks 0c–9, which the card carries as ticked boxes with the same detail.
- `coding-memory/pr-tracking.md` — 1,226 lines duplicating GitHub PR state.
- Judge stores — 163 observability `.md` + 25 compliance `.md`. **`judge-guard.sh` reads only the
  JSONL** (`hooks/judge-guard.sh:39`). The prose markdown is write-only.

The one-canonical-file gate in `rules/gates.md` already forbids exactly this shape: *"two documents
describing the same work means a reader cannot tell which one is wrong."* `CODING_MEMORY.md` is the
second document, sitting next to the rule that prohibits it.

## Decision: `coding-memory/` becomes local-only, not deleted

**User decision, 2026-08-20:** stop pushing coding memory to GitHub. The original reason for
committing it — reading local changes from a browser or another machine — is obsolete now that
remote control covers that case.

Consequence, stated plainly: **this assumes a single machine.** A fresh clone will not carry the
history. That is accepted, not overlooked. The files stay on disk and stay readable by grep and
memsearch; they simply stop being tracked.

`CODING_MEMORY.md` is **not deleted and not trimmed** — other documents cite it by line number, so
renumbering would silently break those citations. It is untracked and frozen: no new appends.

### The one carve-out — `verdicts.jsonl` stays tracked

`hooks/judge-guard.sh:39` reads `coding-memory/observability-judge/verdicts.jsonl` **from the judged
repo's working tree**, deliberately, so a verdict written from a worktree satisfies the gate. If
that file is gitignored, a newly created worktree starts with no verdicts and `judge-guard` blocks
every `gh pr create` from it.

So: untrack all of `coding-memory/` **except** `observability-judge/verdicts.jsonl` and
`compliance-judge/verdicts.jsonl` (993KB combined). This keeps the gate working across worktrees and
still drops 213 of 215 tracked files. Re-pointing `VERDICTS_REL` at a machine-local path outside the
repo was considered and rejected — repo-local verdicts were a deliberate fix, not an accident, and
reversing it is a separate decision.

## Hook coupling — what breaks if the rules change and the hooks don't

Every site below was located by grep on 2026-08-20. Line numbers are derivations, not pins — re-run
`grep -n 'CODING_MEMORY\|coding-memory' hooks/*.sh` before editing; they move.

- **`hooks/doc-guard.sh`** — the `has_doc` allowlist (`:170`) accepts
  `CODING_MEMORY.md|coding-memory/*|docs/*`. Once those two are untracked they can never be staged,
  so the patterns become unreachable and the effective rule silently narrows to `docs/*`. Make that
  explicit rather than leaving dead patterns. Its two user-facing messages (`:81-85` SessionStart
  nag, `:184-185` block text) both instruct the reader to save `CODING_MEMORY.md` — they must name
  `docs/features/` and `docs/decisions/` instead, or the hook is telling every future session to
  maintain a file this card retires.
- **`hooks/git-guard.sh`** — the main-branch commit allowlist (`:385`) and its refusal message
  (`:390`) list `CODING_MEMORY.md|coding-memory/*|docs/*.md`. Narrows to `docs/*.md`. This
  **tightens** what may be committed to `main`; that is intended, but it is a behaviour change to a
  Tier 1 guard and needs its own red test, not just an edit.
- **`hooks/judge-guard.sh:39`** — unchanged, per the carve-out above.
- **`hooks/context-handoff-watch.sh:61`** — its nudge text says *"update CODING_MEMORY.md, commit,
  push."* Reword to the feature card, or the automated arm of the freshness checkpoint keeps
  prescribing the retired ritual.
- **`hooks/phase-guard.sh:288`** — exempt list includes `CODING_MEMORY.md|coding-memory/*`. Harmless
  once untracked (it governs write permission, not git), but see the open question below.
- **Comments only, low priority** — `hooks/feature-sync-guard.sh:118`,
  `hooks/handoff/slim-session-start.sh:10`.
- **Test suites that assert the current behaviour and will go red:**
  `hooks/doc-guard.test.sh:31,96`; `hooks/git-guard.test.sh:27-28,280-283,478-485`;
  `hooks/git-guard.replay.sh:149,185-186,226`; `hooks/phase-guard.test.sh:212`.
  `hooks/handoff/slim-session-start.test.sh:261-266` asserts `CODING_MEMORY.md` is *ignored* at
  session start — that assertion stays correct and must not be removed.

The replay harness is the trap here. `git-guard.replay.sh` compares old behaviour against new; three
of its cases exist specifically to prove `coding-memory/*` commits are allowed. Removing the
allowlist entry makes those cases diverge **by design**, which is indistinguishable from a
regression unless the expected values are updated in the same change.

## Rule and doc text to update

`rules/gates.md` (default-branch safety, documentation-checkpoint safety, one-canonical-file
discipline), `rules/core-conduct.md` (verification write-down examples), `CLAUDE.md` (Skills
Catalog line for `managing-session-memory`), `skills/managing-session-memory/SKILL.md` (the whole
`## CODING_MEMORY.md` section and the update-discipline paragraph), and `README.md`.

**`rules/` and `skills/` are currently write-blocked** — see the gate note at the bottom.

## Non-goals — explicitly kept

- The **phase gate**, `git-guard.sh`, `doc-guard.sh`, `merge-guard.sh`, `judge-guard.sh` as
  mechanisms. They are shell hooks with no context cost and they catch real defects.
- Both **judges**. Only their prose output stops being tracked.
- `docs/features/`, `docs/decisions/`, `.claude/session-state.md`.
- **Deleting any file from disk.** Every removal in this card is `git rm --cached` plus a
  `.gitignore` entry. Nothing is lost locally, and git history retains what was already pushed —
  untracking is not redaction, and this card does not attempt to rewrite history.

## Deferred, pending a separate decision

- **Consolidating `docs/superpowers/plans|specs`** (19 tracked files) into `docs/features/`. Same
  duplication class, but those files are cross-referenced from ADRs and feature cards, so the move
  needs its own citation audit. Not in this card.
- **`coding-memory/pr-tracking.md`** — retiring it is in scope; migrating anything out of it first
  is not. Confirm nothing is needed from it before untracking.

## Open question for the user — not decided

`phase-guard.sh` exempts `docs/*`, `.claude/*`, `coding-memory/*`, `settings.json` — but **not
`rules/` or `skills/`.** That is why routine rule maintenance is blocked right now by two unrelated
parked planning cards. Adding `rules/*` and `skills/*` to the exemption would fix that class
permanently; leaving it means every future rule edit needs a gate. This is a real loosening of a
Tier 1 guard, so it is the user's call, not a default. Recommendation: **add them** — the guard
exists to stop *implementation code* landing during planning, and a rule file is not that.

## Where this work happens — branch and worktree, never `main`

**User decision, 2026-08-20:** this lands on a dedicated branch in its own worktree. No part of it
is done from the primary checkout on `main`.

Two independent reasons, both hard:

1. `git-guard.sh` refuses application code on `main` anyway, and tasks 3–7 edit five Tier 1 hook
   scripts. Attempting it from `main` is a guaranteed block.
2. `phase-guard.sh` unblocks only when a feature file records **the current branch** at
   `phase: implementation`. Recording `branch: main` would open rule/skill writes on the primary
   checkout — the opposite of what is wanted here.

Worktrees for this repo live under `.claude/worktrees/` (the nested `.claude/.claude/` path is
real and expected). Planned: branch `chore/rule-surface-trim`, worktree
`.claude/worktrees/rule-surface-trim`.

**Worktree-specific trap for task 9.** The hook scripts that run during this session are the ones
installed in the *primary* checkout, not the edited copies in the worktree. A hook fix cannot be
gated by the hook it fixes until the primary checkout pulls it. Test the edited hooks by invoking
them directly with a synthetic JSON payload — that is how the current block was confirmed — rather
than inferring their behaviour from whether a live command succeeded.

## Tasks

- [x] 0. Create branch `chore/rule-surface-trim` and its worktree under `.claude/worktrees/`;
      record it in this card's `branch:` frontmatter. All later tasks run inside that worktree —
      confirm with `git branch --show-current` in the directory you are actually editing, since
      SessionStart's `gitStatus` has been observed reporting the wrong branch.
- [x] 1. Re-run the evidence. `git log -1 --format=%ad` per artifact, `git ls-files coding-memory
      | wc -l`, and the `grep -n` over `hooks/*.sh`. Paste results. Every number in this card was
      measured 2026-08-20 and must be re-derived before anything is removed, not copied forward.
- [x] 2. Confirm nothing is still needed from the four dead artifacts and `pr-tracking.md` — read
      them, report what would be lost, and get explicit sign-off before untracking.
- [x] 3. Red: extend `hooks/git-guard.test.sh` with cases asserting `coding-memory/*` and
      `CODING_MEMORY.md` are **blocked** on `main` and `docs/*.md` still passes. Prove they fail
      against the current hook first — a green test here proves nothing.
- [x] 4. Green: narrow the `git-guard.sh:385` allowlist to `docs/*.md`; update the `:390` message.
- [x] 5. Update `hooks/git-guard.replay.sh` expected values for the three diverging cases, in the
      same commit as task 4, with a comment naming this card as the reason.
  - ⚠️ **Spec was wrong: only TWO cases diverge, not three.** The `..`-escape case
    (`coding-memory/../src/tracked.sh`) was already blocked on both sides, so it never diverged.
    Measured, not inferred: 378 pairs, 370 identical, 8 stricter (2 commands × 4 states),
    0 unexpected, 0 relaxed. The implementer refused to add it to the expected-divergence list
    rather than encode a wrong expectation. Recorded here per `managing-session-memory` — the spec
    is not edited mid-implementation, the error is noted under its task.
  - Went beyond brief, deliberately: the divergence list is now machine-checked
    (`EXPECTED_STRICTER` + an `(UNEXPECTED -- inspect this)` label), and the check was proven able
    to fail.
- [x] 6. Red then green: `doc-guard.sh` `has_doc` narrows to `docs/*`; both messages reworded to
      name `docs/features/` and `docs/decisions/`. Update `doc-guard.test.sh`.
- [x] 7. Reword `context-handoff-watch.sh:61`. Fix the stale comments in `feature-sync-guard.sh:118`
      and `slim-session-start.sh:10`.
- [x] 8. `.gitignore` + `git rm --cached` for `CODING_MEMORY.md` and `coding-memory/**` **except**
      the two `verdicts.jsonl` files. Verify with `git ls-files coding-memory` — expect exactly 2.
- [x] 9. Verify `judge-guard.sh` still passes from a **fresh worktree** after task 8. This is the
      carve-out's whole justification; asserting it without running it is not verification.
  - ⚠️ **The stated justification was FALSE, and running it is what proved that.** In a fresh
    detached worktree `judge-guard` exits **2 either way** — with or without the ledger — differing
    only in message ("no verdict store" vs "no fresh verdict"). A missing ledger does not block PRs.
  - The real reason to keep both `verdicts.jsonl` tracked: the accumulated judge record — 179
    observability rows (**69** non-null outcomes: 38 clean, 31 rework, 110 null) and 123 compliance
    rows — which untracking would fragment per worktree.
  - The wrong figure **169** was propagated into `.gitignore` and a commit message before being
    caught; it came from `grep -c '"outcome":[^n]'`, which matches the space in `"outcome": null`.
    A real JSON parse gives 69. Both artifacts corrected.
- [x] 10. Update `rules/gates.md`, `rules/core-conduct.md`, `CLAUDE.md`, `README.md`, and the
      `## CODING_MEMORY.md` section of `skills/managing-session-memory/SKILL.md`. Freeze
      `CODING_MEMORY.md` with a header note: retired, not trimmed, cited by line number.
- [x] 11. Decide the `phase-guard.sh` exemption open question above; if yes, red test + change +
      `phase-guard.test.sh` update.
- [x] 12. Full hook suite green — `git-guard`, `doc-guard`, `merge-guard`, `judge-guard`,
      `phase-guard`, `slim-session-start`, plus the replay harness. Paste counts.
- [x] 13. ADR under `docs/decisions/` — retiring a documentation tree and tightening two Tier 1
      guards is structural. Check the next free number against `origin/main`, not stale local main.
  - ⚠️ **This instruction was itself insufficient and produced a near-miss.** 0030 *is* free on
    `origin/main` — and already taken on the pushed branch
    `origin/worktree-fix+memsearch-r9-retrieval-quality` as
    `0030-judge-verdict-tier-and-query-time-weight.md`. Verified independently. Landed as **ADR
    0031**. The check must sweep **every local and remote ref**, not one branch.
  - Pre-existing defect surfaced, not caused by this card: `origin/main` already carries **two**
    ADRs numbered `0026` (`…-symbolic-ref-not-abbrev-ref-names-the-branch.md` and
    `…-the-gate-does-no-json-parsing.md`, the latter via PR #58). A duplicate number merges cleanly
    because filenames differ, so nothing ever surfaces it. Not fixed here — out of scope.
  - `0028` is a genuine gap on every ref; left alone rather than backfilled out of order.
- [x] 14. Observability judge, then PR.

## Verification

Suites re-run by the controller in the merged tree, not taken from worker reports —
**737 cases, 0 failures**: git-guard 152, doc-guard 20, merge-guard 10, judge-guard 101,
phase-guard 147, feature-sync-guard 30, test-marker-guard 248 (new, arrived via PR #58),
slim-session-start 29.

Replay harness vs base `7fcfd95`: **378 pairs — 370 identical, 8 stricter, 0 unexpected,
0 relaxed.** "Never weaker than main" holds.

Falsifiers actually run, not asserted:

- doc-guard: restoring the pre-fix hook makes exactly the new case fail (20/0 → 19/1).
- phase-guard: the new hook returns **exit 0** for `rules/gates.md` on `main` and **exit 2** for
  `hooks/git-guard.sh` — the same command that was blocked at the start of this work.
- judge-guard: `gh pr create --draft` exits 2 identically to a bare `gh pr create`; `gh pr view`
  exits 0. This is what makes the migrated draft-PR flow's "identical freshness gate" claim true
  rather than inherited.
- `context-handoff-watch.sh`: re-probed with a correct payload → valid JSON, new text, no stale
  string.
- Untracking: `git ls-files coding-memory` → exactly **2**; 228 files and the 8,759-line
  `CODING_MEMORY.md` all still on disk. `git log --follow` on the moved memsearch report reaches
  its original commit `a0f9a8e` (the move was split into a 100%-similarity rename because a
  combined move+edit scored 41% and would have broken `--follow`).

### Controller errors worth recording

Four of my own, each caught only by checking a result rather than an exit code:

1. **`git commit -- <pathspec>` silently re-added every file** — with a pathspec, git commits
   working-tree content and ignores staged deletions. The first untracking commit did nothing;
   `git ls-files` still showed 214.
2. **The first fresh-worktree test was invalid** — `git worktree add` failed on "branch already
   used", the `cd` failed, and every command ran in the main checkout, which still had all the
   files. It looked like a pass.
3. **`head -2` in a pipeline overwrote `$?`**, so both judge-guard probes reported `exit=0`.
4. **`grep -c '"outcome":[^n]'` returned 169** because it matched the space in `"outcome": null`.
   A JSON parse gives 69. The wrong figure reached `.gitignore` and a commit message before a
   worker caught it.

### Post-judge round (risk=medium, confidence=high) — three fixes

The observability judge found a defect the card's own task list had missed, and it is the silent
kind. `skills/preparing-pull-requests/SKILL.md` still routed PR state into the retired tree — in
the very skill the migration worker had edited. Line 12 fails **loudly** (it instructed committing
`CODING_MEMORY.md` to `main`, which this branch's own `git-guard` tightening now blocks); lines
25/30/46 fail **silently** — the write lands in a gitignored file and never leaves the machine.
Task 10's file list omitted the skill. Rewritten: GitHub is the record of PR *state*,
`docs/features/` carries the *reasoning* GitHub cannot hold.

**This was the third instruction file found still prescribing the retired tree** (after
`context-handoff-watch.sh` and `setting-up-a-new-project`).

> ⚠️ **The completeness claim originally written here was false and is retracted.** It said the
> remaining hits were "either historical prose or the hook's own retired-path comment." Round 2
> disproved it with a grep. See the enumeration below — that is what should have been done at the
> third instance instead of asserting the sweep was clean.

### Round 3 — the enumeration that should have happened at instance three

Round 2 found a **fourth** instance (`hooks/README.md`, three places, one of them a rationale
paragraph arguing *against* this branch's own change). Four instances of one class means the class
is the finding, so the surface was enumerated rather than patched again:
`grep -rln "CODING_MEMORY\|coding-memory"` over `*.md`/`*.sh`/`*.py`/`*.json`, excluding the retired
tree itself — **569 hits across 65 files.** Classified:

| File | Verdict |
|---|---|
| `hooks/README.md:76,81,291` | **FALSE** — described the pre-change allowlist as live. Fixed. |
| `agents/compliance-judge.md:60` | **FALSE** — hardcoded `~/.claude/…`, so every verdict from a worktree or another repo landed in the wrong store. Pre-existing; the retirement made it worse. Fixed: resolve relative to the judged repo. |
| `skills/preparing-pull-requests/SKILL.md:29` | Dangling pointer left by round 1's own fix — `:25` said "no local copy", `:29` said "consult the saved PR metadata". Fixed. |
| `skills/writing-project-readmes/SKILL.md:64` | Stale trigger phrasing. Fixed. |
| `agents/observability-judge.md:42,44` | **CORRECT** — repo-relative, and the ledger it names is still tracked. Left. |
| `skills/running-the-{observability,compliance}-judge/SKILL.md` | **CORRECT** — point at the tracked `verdicts.jsonl`. Left. |
| `memsearch/config.json:11`, `memsearch/**` | **CORRECT** — corpus paths; files remain on disk. Left. |
| `docs/decisions/*`, `docs/features/*` (other cards), `docs/superpowers/*` | **HISTORICAL** — dated records of what was true then. Left deliberately. |
| `hooks/*.test.sh`, `hooks/lib/*.test.py` | **FIXTURES** — they assert the retired paths are now *blocked* or *ignored*. Left; changing them would delete the coverage. |
| `hooks/git-guard.sh:8`, `hooks/phase-guard.sh` case arm | **HISTORICAL COMMENT / defensive** — deliberate. Left. |

The lesson, recorded because it recurred four times: **when a second instance of one class appears,
enumerate the surface; do not patch the instance and assert the rest is clean.** Each of rounds
1–2 fixed the instance in front of it and stated a completeness the evidence did not support.

### A trap for future paned agents — `CLAUDE_PANE_AGENT`

`hooks/handoff/slim-session-start.test.sh` reports **13/29, exit 1** when run inside a pane agent,
and **29/29** under `env -u CLAUDE_PANE_AGENT`. Cause: `slim-session-start.sh:53` short-circuits on
that variable by design. Pre-existing (from `ca2c969`), undocumented until now, and precisely the
kind of thing a future agent "fixes" while chasing 16 phantom failures.

Also fixed:

- **`.gitignore` cited exact ledger row counts, and they went stale inside this session** — the
  judge's own verdict appended a row, moving 179/123 to 194/133. Replaced with the derivation plus
  the warning that grepping `outcome` overcounts by matching the space in `"outcome": null`.
- **`git-guard.replay.sh` reported `N unexpected` and still exited 0** — a report, not a gate. It
  now exits 1 on any `relaxed` or `unexpected`. Both halves proven: the clean run is
  `8 stricter (0 unexpected)` → exit 0; a mutant with one `EXPECTED_STRICTER` entry removed is
  `8 stricter (4 unexpected)` → exit 1, **still reporting 63 commands**, which is what proves the
  mutant tested the case instead of dropping it from the matrix.
  - Controller error worth recording: the first mutant `sed` deleted the entry from **both**
    `CMDS` and `EXPECTED_STRICTER` — the exact invalid falsifier the git-guard implementer had
    already documented in its own report. Rebuilt scoped to the array line.

### Judge concerns recorded but NOT acted on — user's call

- **`rules/*|skills/*` globs span `/`**, so `skills/**/*.sh` executables are exempt from the phase
  gate too (one file today). The exemption was argued as "a rule file is not implementation code";
  a shell script under `skills/` arguably is. Narrowing it would change what was approved, so it is
  left as-is and flagged rather than quietly scoped down.
- The judge verified 460 of the 737 cases; it did not run `test-marker-guard` (248) or
  `slim-session-start` (29). Both were run by the controller in the merged tree — this is the
  judge's coverage limit, not an unverified claim.

### Known gaps, stated rather than closed

- `docs/superpowers/plans/2026-07-17-memory-rag-index.md:2202,2301,2329` still embed the old
  `eval.py` source and its `coding-memory/` path. Left deliberately — a dated plan is a record of
  what was specified, not a live pointer — but the listing now disagrees with the live `eval.py`.
- `hooks/feature-sync-guard.sh:118`'s `classify-git-command.py` apostrophe-trap citation has **no
  replacement**; ADR 0012 documents `classify-pr-command.py`, a different classifier. The comment
  now flags the gap instead of inventing a pointer.
- `hooks/git-guard.sh:8` deliberately still contains the literal strings, as a historical note.
- The handoff pane was not exercised live; `panes/handoff-wrapper.sh` was verified by `bash -n`
  and by reading the seed prompt.
- `DEFAULT_REPORT_DIR` was verified by path resolution, not by a real audit run (needs a live
  Ollama model). No test covers the constant.
