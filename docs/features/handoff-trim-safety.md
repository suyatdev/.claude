---
phase: planning
model_tier: high
branch: none
---

# Handoff trim safety — stop the session notepad losing facts

## Problem

`.claude/session-state.md` is the machine-local notepad the next session reads after a
`/clear`. It has a hard line ceiling, and the only mechanism for staying under that ceiling
is asking the model to delete text. Nothing decides what is safe to delete, nothing records
what was deleted, and nothing keeps a copy. A trim is silent and one-way.

Reported by the user 2026-09-08 as drift in `vibe-scape` after a pre-clear handoff.

### Measured evidence (2026-09-08)

Two independent limits, set by different hooks that do not know about each other:

| Limit | Location | Value | Behaviour past it |
|---|---|---|---|
| Write | `hooks/handoff/live-handoff.sh:47` | 80 lines (no task/bug marker file) | Directive flips from append to `Rewrite… Be ruthless`, target 60 (`:90`, `:96`) |
| Read | `hooks/handoff/slim-session-start.sh:18` | 8192 bytes | Prints header, **omits the entire body** (`:84-88`) |

Write ceilings vary by marker file (`live-handoff.sh:39-49`): none → 80/60,
`current-task.md` → 100/80, `current-bug.md` → 120/100.

Byte-per-line rate across all 12 `session-state.md` files on this machine: **57–78 b/line**
(median ~61). Therefore 150 lines is 8,550–11,700 bytes — over the 8192 read cap at every
rate in the measured range. Raising the write cap alone would move repos from partial loss
to total loss.

Population survey, 12 files across 6 repos. Two already in failure:

- `~/Other Docs/mtg-wizard/.claude/session-state.md` — **235 lines / 13,455 bytes, mtime
  2026-09-08 10:42 (active)**. 3x over the write cap, so every turn has been issuing the
  ruthless-trim directive and it is demonstrably not being obeyed; 64% over the read cap,
  so its handoff body is already being dropped whole at session start.
- `~/Other Docs/AI/AI_Projx/vibe-scape/.claude/session-state.md` — 75 lines / 5,165 bytes.
  Five lines from a forced 25% cut.

### Contributing causes

1. **No overflow destination.** Past the ceiling, deletion is the only way back under it.
2. **Deletion is by judgment, not rule.** Criteria are `obvious from code, already
   committed, no longer relevant, or low-importance` — all judgment calls, no protected list.
   Measured facts that look derivable (e.g. vibe-scape's `WL draft $0.18 / bills 230 credits,
   not the 150 list`) are exactly the class that reads as cuttable and is not.
3. **No backup on that path.** `proactive-handoff.sh save` writes the only `.bak`, and
   `settings.json` registers it on **PreCompact only** — never before a trim. vibe-scape has
   no `.bak` at all. The file is gitignored (`vibe-scape/.gitignore:7`), so git never
   versioned it either.
4. **The directive re-fires every turn** while over the limit, so one overrun can drive
   several successive cutting passes over an already-cut file.
5. **Trim timing is adversarial.** The file grows because the session is long; a long session
   is a full context window. The "which facts matter" judgement is made when it is weakest.

### Adjacent defects found in the same sweep

- **`pre-compact.sh` re-injects the wrong files.** It sends `context.md`, `current-task.md`,
  `current-bug.md` and **not** `session-state.md` — the only one kept current. In vibe-scape
  `context.md` is from 2026-07-25 while the notepad is from 2026-09-08.
- **`slim-session-start.sh:85-86` comment contradicts its code.** It states the cap
  `must not degrade backwards by withholding the handoff exactly when work overran it`,
  which is precisely what dropping the body does.
- **vibe-scape has no `docs/features/`** (only `decisions`, `design`, `plans`, `specs`), so
  the durable half of the memory system is absent there and everything rides on the volatile
  notepad. User declined to add it in this feature — recorded as a known gap, not a task.

## Decisions taken (user, 2026-09-08)

| # | Decision | Chosen |
|---|---|---|
| D1 | Snapshot before every trim | Yes |
| D2 | Cut text goes to an archive, never deleted | Yes |
| D3 | Sections markable as never-cut | Yes |
| D4 | Give vibe-scape a `docs/features/` record | **No** — declined; known gap |
| D5 | Write limit | Raise to ~150 lines |
| D6 | Read limit + oversize behaviour | Raise to match (~12,000 bytes) **and** make the reader print what fits and name what was cut, never blank |
| D7 | `pre-compact.sh` file list | Fix — inject the live notepad |
| D8 | Who performs the save | **Hook copies mechanically, AND directive asks for tidy filing.** The mechanical copy is the floor and needs no model cooperation |
| D9 | Marker enforcement | **Verify after the fact** — compare post-write against the pre-trim copy and require restoration of any protected block that vanished |

Triage (`triaging-new-instructions`, 2026-09-08): every item classifies as **hook** (tier 1,
script-decidable from observable facts). No new `core-conduct.md` rule, no new `gates.md`
stub. One documentation edit to `managing-session-memory` to teach the marker convention.

Model-switch checkpoint 1 (entering planning): **Opus 5 / xhigh**, confirmed by user.

## Open design questions

- **Q1 — archive location and name.** Sibling `.claude/session-state.archive.md`?
- **Q2 — archive growth.** Append-only forever, or rotate at a size? It must never itself be
  trimmed, and must never be read at session start.
- **Q3 — gitignore.** Archive gitignored like the notepad, or tracked so it survives a
  machine loss? Note the notepad being untracked is what made the 2026-09-04 truncation of
  `~/.claude/session-state.md` unrecoverable (memory:
  `feedback_the_running_log_is_untracked_and_unbacked`).
- **Q4 — marker syntax.** Precedent exists: `/handoff` already exempts `bug-test-log.md` from
  trimming in prose. Needs a machine-detectable form.
- **Q5 — blast radius.** These hooks are global; the change lands on all 12 notepads across
  6 repos at once. Staged rollout or not?
- **Q6 — where the post-write check hooks in.** `PostToolUse` on `Edit|Write` filtered to
  `session-state.md`, comparing against the pre-trim copy.

## Spec

<Not yet written — design sections still to be presented and approved. Blocked on Q1–Q6.>

## Tasks

<Not yet built — the gate has not opened. Draft ordering only, to be firmed after the spec:>

- [ ] Mechanical pre-trim snapshot in `live-handoff.sh`
- [ ] Archive append + directive rewrite (delete → file into archive)
- [ ] Marker convention + verbatim re-injection into the directive
- [ ] Post-write marker survival check
- [ ] Raise write cap; raise read cap; replace oversize blanking with truncate-and-say
- [ ] Fix `pre-compact.sh` file list
- [ ] Document the marker convention in `managing-session-memory`
- [ ] Tests for each of the above

## Verification

<Appended during review.>
