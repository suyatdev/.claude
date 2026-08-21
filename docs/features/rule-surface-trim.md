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

- [ ] 0. Create branch `chore/rule-surface-trim` and its worktree under `.claude/worktrees/`;
      record it in this card's `branch:` frontmatter. All later tasks run inside that worktree —
      confirm with `git branch --show-current` in the directory you are actually editing, since
      SessionStart's `gitStatus` has been observed reporting the wrong branch.
- [ ] 1. Re-run the evidence. `git log -1 --format=%ad` per artifact, `git ls-files coding-memory
      | wc -l`, and the `grep -n` over `hooks/*.sh`. Paste results. Every number in this card was
      measured 2026-08-20 and must be re-derived before anything is removed, not copied forward.
- [ ] 2. Confirm nothing is still needed from the four dead artifacts and `pr-tracking.md` — read
      them, report what would be lost, and get explicit sign-off before untracking.
- [ ] 3. Red: extend `hooks/git-guard.test.sh` with cases asserting `coding-memory/*` and
      `CODING_MEMORY.md` are **blocked** on `main` and `docs/*.md` still passes. Prove they fail
      against the current hook first — a green test here proves nothing.
- [ ] 4. Green: narrow the `git-guard.sh:385` allowlist to `docs/*.md`; update the `:390` message.
- [ ] 5. Update `hooks/git-guard.replay.sh` expected values for the three diverging cases, in the
      same commit as task 4, with a comment naming this card as the reason.
- [ ] 6. Red then green: `doc-guard.sh` `has_doc` narrows to `docs/*`; both messages reworded to
      name `docs/features/` and `docs/decisions/`. Update `doc-guard.test.sh`.
- [ ] 7. Reword `context-handoff-watch.sh:61`. Fix the stale comments in `feature-sync-guard.sh:118`
      and `slim-session-start.sh:10`.
- [ ] 8. `.gitignore` + `git rm --cached` for `CODING_MEMORY.md` and `coding-memory/**` **except**
      the two `verdicts.jsonl` files. Verify with `git ls-files coding-memory` — expect exactly 2.
- [ ] 9. Verify `judge-guard.sh` still passes from a **fresh worktree** after task 8. This is the
      carve-out's whole justification; asserting it without running it is not verification.
- [ ] 10. Update `rules/gates.md`, `rules/core-conduct.md`, `CLAUDE.md`, `README.md`, and the
      `## CODING_MEMORY.md` section of `skills/managing-session-memory/SKILL.md`. Freeze
      `CODING_MEMORY.md` with a header note: retired, not trimmed, cited by line number.
- [ ] 11. Decide the `phase-guard.sh` exemption open question above; if yes, red test + change +
      `phase-guard.test.sh` update.
- [ ] 12. Full hook suite green — `git-guard`, `doc-guard`, `merge-guard`, `judge-guard`,
      `phase-guard`, `slim-session-start`, plus the replay harness. Paste counts.
- [ ] 13. ADR under `docs/decisions/` — retiring a documentation tree and tightening two Tier 1
      guards is structural. Check the next free number against `origin/main`, not stale local main.
- [ ] 14. Observability judge, then PR.

## Verification

<Appended during review.>
