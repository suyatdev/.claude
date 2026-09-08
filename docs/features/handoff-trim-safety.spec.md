# Handoff trim safety — spec and evidence

Companion to `handoff-trim-safety.md`. Read on demand only, never at session start.
The card holds frontmatter, the task list and verification; this file holds the measured
evidence, the user decisions and the full spec.

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

### memsearch survey (measured 2026-09-08)

The RAG the archive will feed is `memsearch`. Scheduled by **launchd, not cron** —
`~/Library/LaunchAgents/local.memsearch-index.plist`, `StartInterval` 21600 (6h).
Index today: 156 MB, 21,656 chunks (`~/.claude/memory-index/memory.db`).

- A suitable source tier **already exists**: `archive_doc` (`memsearch/memsearch/index.py:66`),
  weighted 1.0 — below `curated_doc` 1.5 and `repo_doc` 1.2 — and routed to
  `recall_type == "episodic"` (`memsearch/memsearch/chunk.py:114`). Correct home for
  session narrative: retrievable, never outranking a decision record.
- It is keyed to the wrong file. `ARCHIVE_FILENAME = "CODING_MEMORY.md"`
  (`memsearch/memsearch/index.py:46`) — a tree `rules/gates.md` records as retired.
  `config.json` `curated_docs` still names `~/.claude/coding-memory` and
  `~/.claude/CODING_MEMORY.md` for the same reason.
- **Notepads are not indexed at all.** `session-state` / `session_state` appears nowhere
  in the memsearch source.
- `config.json` `repo_roots` covers **only** `vibe-scape` and `Snatch-Bracket`.
  `mtg-wizard` — the repo already losing its whole handoff body — is not indexed.
- **Re-index cost is per-file, not per-append.** On a content-hash change the indexer
  drops and re-embeds the entire file (`memsearch/memsearch/index.py:220-226`,
  `replace_source`). An append-only archive that grows without bound is therefore
  re-embedded in full every 6 hours, forever. A rotated file never changes again and is
  hash-skipped for free. This is the reason for D11 and it reverses an earlier
  in-session recommendation to let the archive grow unbounded.
- `/memory-index/` is gitignored (`.gitignore:75`) and has no backup, so the index must
  never become the only copy of cut text. Hence "nothing is ever deleted" in D11.

### Repo visibility (measured 2026-09-08)

`suyatdev/.claude` is a **public** GitHub repo (`gh repo view --json isPrivate` -> false).
Any decision to track the archive in git publishes raw session narrative. A Time Machine
destination is configured (WD Passport, local disk); whether backups are current could not
be confirmed — `tmutil latestbackup` requires Full Disk Access, which this shell lacks.

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
| D10 | Archive location | Sibling file `.claude/session-state.archive.md`, one per repo |
| D11 | Archive growth | Rotate the live archive at ~1 MB to `session-state.archive.N.md`; **nothing is ever deleted**; memsearch indexes the live file and every rotation |
| D12 | Archive in git | **No** — archive and rotations gitignored, like the notepad. `suyatdev/.claude` is public; session narrative must not be published |
| D13 | Marker syntax | `[KEEP]` suffix on a markdown heading. Protected region = that heading through to the next heading of any level |
| D14 | Rollout | **Everything on, everywhere, immediately** — including the protected-block check enforcing from day one. User chose this over a warn-only first week, having been shown that risk |
| D15 | Check timing | `Stop` hook — runs once per turn after all edits settle, and holds the turn open until a vanished protected block is restored. Rejected: `PostToolUse` per-edit (false alarms on intermediate states of a multi-edit rewrite) and next-turn `UserPromptSubmit` (never runs if the session is cleared first, which is the case that matters) |

Triage (`triaging-new-instructions`, 2026-09-08): every item classifies as **hook** (tier 1,
script-decidable from observable facts). No new `core-conduct.md` rule, no new `gates.md`
stub. One documentation edit to `managing-session-memory` to teach the marker convention.

Model-switch checkpoint 1 (entering planning): **Opus 5 / xhigh**, confirmed by user.

## Open design questions — all resolved 2026-09-08

| Q | Question | Resolved by |
|---|---|---|
| Q1 | Archive location and name | D10 |
| Q2 | Archive growth | D11 |
| Q3 | Gitignore or track | D12 |
| Q4 | Marker syntax | D13 |
| Q5 | Blast radius across 6 repos | D14 |
| Q6 | Where the post-write check hooks in | D15 |

## Spec

Revised 2026-09-08 after compliance round 1 (FAIL, 9 violations) and the observability
architecting read (risk=medium). Every change below is traceable to a numbered finding; the
`## Judge findings` table at the end maps them.

### Scope

In scope: the trim cycle for `.claude/session-state.md` in every repo on this machine —
snapshot, archive, rotation, protected sections, both size caps, **both** compaction hooks,
and indexing the archive into memsearch.

Out of scope: giving vibe-scape a `docs/features/` tree (D4, declined — known gap);
migrating existing oversize notepads by hand; changing what the model chooses to write.

**Explicitly not covered, stated because it is easy to assume otherwise:** the root-level
`~/.claude/session-state.md` (95,456 bytes, hand-kept) is a different file, read by no hook,
and this card does not protect it. It was untracked *and* un-gitignored in a public repo when
the compliance judge found it; that was fixed separately in `.gitignore:74-80`.

### Pinned toolchain

| Tool | Version | Constraint it imposes |
|---|---|---|
| bash | **3.2.57(1)** (`/bin/bash`, macOS system) | No associative arrays, no `${var^^}`, no `mapfile`, no array `+=`. Every hook must run under it. |
| jq | **1.7.1-apple** | Already the parser used by `post-edit-hook.sh:23`. |
| python | **3.12** (`memsearch/.python-version`) | memsearch changes only. |
| ollama embed model | `qwen3-embedding:0.6b`, dim 1024 (`memsearch/config.json`) | Unchanged. |

No new runtime dependencies. No network access in any hook.

### Files

**New**

| Path | Role |
|---|---|
| `hooks/handoff/lib/handoff-archive.sh` | Sourced library: snapshot, `[KEEP]` region extraction with fence tracking, archive append, rotation, secret flagging. |
| `hooks/handoff/handoff-keep-guard.sh` | `Stop` hook. Verifies protected regions survived; performs the mechanical archive append; writes the liveness heartbeat. |
| `hooks/handoff/lib/handoff-archive.test.sh` | Library unit tests. |
| `hooks/handoff/handoff-keep-guard.test.sh` | Hook behaviour tests, including strike cap and reset. |

**Changed**

| Path | Change |
|---|---|
| `hooks/handoff/live-handoff.sh` | Raise caps (`:40-49`); snapshot on **every** turn, not only over the cap; suppress the trim directive if the snapshot cannot be written; rewrite the directive (`:86-99`); re-inject protected headings verbatim. |
| `hooks/handoff/pre-compact-handoff.sh` | **Added after the observability read.** Its own directive (`:78`, `:85`) says `REWRITE it completely` with targets `60-80 / 80-100 / 100-120` — an independent trim path with no snapshot and no `[KEEP]` enforcement. Raise its targets to match, and route it through the same snapshot. This is the pre-clear handoff path the original bug report came from. |
| `hooks/handoff/slim-session-start.sh` | Raise `MAX_BYTES` (`:18`); replace body-drop (`:84-88`) with truncate-and-say; report guard liveness; reap stale snapshots. |
| `hooks/handoff/pre-compact.sh` | Inject `.claude/session-state.md` first (D7). |
| `.gitignore` | Confirm archive coverage per repo with `git check-ignore`, never assumed. |
| `memsearch/config.json` | New `archive_globs` key (recursive). |
| `memsearch/memsearch/index.py` | Consume `archive_globs`; widen `_doc_source_type` beyond the retired `CODING_MEMORY.md`; warn on a zero-match glob. |
| `skills/managing-session-memory/SKILL.md` | Document the `[KEEP]` convention. |

### On-disk contract

All paths relative to `<repo>/.claude/`.

| File | Written by | Read by | Lifetime |
|---|---|---|---|
| `session-state.md` | model | `slim-session-start.sh` | live |
| `session-state.pretrim.<session-id>.md` | `live-handoff.sh`, `pre-compact-handoff.sh` | `handoff-keep-guard.sh` | one turn; reaped at session start if older than 24h |
| `session-state.archive.md` | `handoff-keep-guard.sh` (auto) and model (curated) | humans, memsearch | until rotation |
| `session-state.archive.<N>.md` | rotation | humans, memsearch | forever, never modified again |
| `session-state.keepguard-strikes.<session-id>` | `handoff-keep-guard.sh` | itself | cleared on success **and** on fail-open |
| `session-state.keepguard.log` | `handoff-keep-guard.sh` | `slim-session-start.sh`, humans | append-only, rotates with the archive |

**The snapshot is per-session** (finding C2). A shared snapshot let the first session delete
it on success, after which a second session in the same repo found none, archived nothing, and
skipped the protected-block check entirely. That is why the old "no data is lost" claim in
known gap 5 was false.

### Constants

```yaml
write_caps:                  # live-handoff.sh and pre-compact-handoff.sh, same table
  none:         {max: 150, target: 120}
  current_task: {max: 170, target: 140}
  current_bug:  {max: 190, target: 160}
read_cap:
  slim_handoff_max_bytes: 24576    # 24 KiB; env override SLIM_HANDOFF_MAX_BYTES
archive:
  rotate_at_bytes: 1048576         # 1 MiB
keep_guard:
  max_strikes: 2                   # blocks before failing open with a loud warning
  liveness_stale_turns: 20         # session start complains past this
snapshot:
  reap_after_hours: 24
```

**R1 — headroom, not a guarantee (finding C1).** The earlier version asserted
`read_cap >= max(write_caps) * 78` and called it an invariant. Two things were wrong. First,
78 bytes per line was the maximum of a 12-file sample, not a bound: measured against
**non-blank** lines — which is what survives a ruthless trim — the same population reaches
**87.2** (`.claude/.claude/card-d-non-text-contrast/session-state.md`, 2026-09-08). At that
density `190 x 87.2 = 16,568`, which the proposed 16,384 cap would have truncated. Second, and
more fundamental: **the write cap is a directive, not a ceiling.** `mtg-wizard` reached 235
lines against an 80-line cap — 2.9x over — so no read cap can be proven sufficient.

So the load-bearing safety property is not the cap. It is that **the reader never blanks**:
past the cap it prints what fits and names what it withheld. The cap is a headroom target
only. 24,576 gives 1.48x over the worst measured density at the largest write cap.

The test for this is a **runtime measurement over the real notepad population**, not a
comparison of three constants — a constants test passes by construction and can never fail
(finding O4).

### The `[KEEP]` marker (D13) — full grammar

The earlier version gave one regex for the heading and nothing for anything else, which left
the implementer to guess (finding C4).

**Heading form.** ATX only:

```
^#{1,6}[[:space:]].*\[KEEP\][[:space:]]*$
```

**Setext headings** (a title underlined with `===` or `---`) **are not supported.** They
cannot carry a trailing tag on the text line without it reading as body text. A setext heading
is treated as ordinary body, so it neither opens nor closes a region. Documented, not silently
unhandled.

**Fence tracking.** The parser tracks fenced code state before testing any line as a heading:

- An opening fence is three or more backticks or three or more tildes, indented at most three
  spaces.
- The closing fence must use the **same character** and be **at least as long**. A tilde fence
  does not close a backtick fence. This is what makes nested fences work.
- YAML front matter (`---` on line 1 through the next `---`) is skipped before parsing begins.
- An indented code block (four spaces or a tab, following a blank line) is body, not a heading.

**Two consequences the earlier version missed.** A heading inside a fence does not *end* a
region — the earlier spec covered that — and a `[KEEP]` heading inside a fence must not
*open* one either. The revised scenarios cover both directions.

**Region.** The heading line through the line before the next ATX heading of any level
outside any fence, or end of file.

**Survival rule.** Every non-blank line of a protected region in the snapshot, trailing
whitespace stripped, must appear as some line of the post-write file. Membership, not
position — reordering, re-nesting and moving a block between sections all pass; only deletion
fails. The heading line is part of the region, so stripping the tag fails.

### The trim cycle

```mermaid
sequenceDiagram
    participant U as You
    participant LH as live-handoff.sh<br/>(UserPromptSubmit)
    participant M as Model
    participant KG as handoff-keep-guard.sh<br/>(Stop)
    participant A as archive + log

    U->>LH: sends a prompt
    LH->>LH: snapshot to session-state.pretrim.SESSION.md
    alt snapshot failed
        LH->>M: append-mode directive ONLY, plus a loud warning
    else snapshot written
        LH->>LH: count lines
        alt over the write cap
            LH->>M: trim directive + verbatim KEEP headings
        else under the cap
            LH->>M: append directive
        end
    end
    M->>M: edits session-state.md
    M->>KG: turn ends
    KG->>KG: diff snapshot vs current
    alt unchanged
        KG->>A: heartbeat only, delete snapshot
    else a protected line vanished
        KG-->>M: block, naming headings and counts only
        KG->>KG: strike +1, keep snapshot
    else survived and text was removed
        KG->>A: append removed lines, rotate at 1 MiB, heartbeat
        KG->>KG: delete snapshot and strike file
    end
```

**Snapshot on every turn, not only over the cap (finding C3).** The earlier design snapshotted
only when the trim directive fired, so on the great majority of turns nothing was protected at
all, and a voluntary rewrite below the cap could delete a `[KEEP]` line with no copy and no
check. That was a silent narrowing of D1. A snapshot is a copy of a file capped in the low
tens of kilobytes; taking it every turn costs less than the loss it prevents.

**Snapshot failure fails closed (finding O-C).** If the snapshot cannot be written, the hook
must not emit the trim directive. Asking for a trim while unable to back it up is exactly the
promise the card exists to stop making. Trimming pauses and says why.

### Archive entry format

One block per verified removal. Both writers append; the duplication is deliberate and costs
only disk, since the archive is never read at session start and never trimmed (D8).

```markdown
## Auto-captured 2026-09-08T16:38:44Z (session 631d9bd8, 42 lines, secrets: none)
<verbatim removed lines, in original order>
```

A note the model files itself uses `## Filed by session <iso>` instead, so the two are
distinguishable on sight and by grep.

**Secret handling (finding C9).** The archive makes notepad text permanent and search-indexed,
on a path that never passes through `scan-secrets.sh` — that hook is `PreToolUse` on
`Edit|Write`, and a hook appending through bash bypasses it entirely. So the library runs the
same detection over each block before appending. On a hit the block is **still archived** —
losing text is the failure this card exists to prevent — but the heading records
`secrets: flagged`, the guard says so out loud, and **memsearch skips any file containing a
flagged block**, so a possible secret is never embedded into a searchable index.

### Guard liveness (finding O2)

The `Stop` guard is the only hook here that speaks, and it is also the only writer of the
mechanical archive. If it is unregistered, missing, or crashes, it exits 0 and the turn ends
normally — indistinguishable from "nothing needed protecting". That is the same shape as the
recorded `worktree-guard.sh` log-mode lesson in `rules/gates.md`, but worse, because one
silent death costs both the protection and the backup.

So the guard emits a **positive** signal, not merely the absence of an objection. Every run
appends one line to `session-state.keepguard.log`:

```
2026-09-08T16:38:44Z session=631d9bd8 decision=allow protected_regions=2 removed_lines=0
```

`slim-session-start.sh` reads the last line and says, in the handoff header, when the guard
last ran. Past `liveness_stale_turns` with a notepad that has been changing, it says so
plainly. Absence of the log file at all is reported as "guard has never run here", which is
the state a broken registration produces.

### Behaviour scenarios

`SS` = `session-state.md`, `PT` = the per-session snapshot, `AR` = `session-state.archive.md`.

**Good path**

```gherkin
Scenario: A normal trim archives what it cut
  Given SS is 165 lines with no marker file present
  When live-handoff.sh runs and the model rewrites SS down to 118 lines and the turn ends
  Then PT was created as a byte-identical copy of SS before the rewrite
  And the guard appends the 47 removed lines to AR under an Auto-captured heading
  And PT is deleted
  And one allow line is appended to the liveness log

Scenario: A protected section survives a rewrite that moves it
  Given PT contains a region under "## Standing rules [KEEP]" with 4 non-blank lines
  When the model rewrites SS so all 4 lines sit under a different parent heading
  And the turn ends
  Then the guard allows the turn to end and the removal is archived normally

Scenario: Under the cap, the notepad is still protected
  Given SS is 90 lines, well under the 150-line cap
  When live-handoff.sh runs
  Then PT is still created
  And the append-mode directive is emitted
  When the model deletes a [KEEP] line anyway and the turn ends
  Then the guard blocks, because protection does not depend on the cap
```

**Bad path**

```gherkin
Scenario: A protected line is deleted
  Given PT contains "- Always work in a worktree." inside a [KEEP] region
  When the model rewrites SS without that line and the turn ends
  Then the guard blocks the turn
  And the reason names the heading and the count of missing lines and the path to PT
  And the reason contains no notepad body lines
  And PT is NOT deleted and nothing is appended to AR
  And the strike count becomes 1

Scenario: The model strips the [KEEP] tag itself
  Given PT contains the heading "## Standing rules [KEEP]"
  When the model rewrites SS with that heading as "## Standing rules" and the turn ends
  Then the guard blocks, because the heading line is itself a protected line

Scenario: The guard must not wedge the session
  Given the guard has already blocked twice on the same PT
  When the turn ends a third time with a protected line still missing
  Then the guard allows the turn to end
  And it emits a loud warning naming the unrecovered headings and the PT path
  And it appends the full PT content to AR before deleting PT
  And it deletes the strike file, so the next cycle starts at zero

Scenario: The snapshot cannot be written
  Given the .claude directory is read-only
  When live-handoff.sh runs with SS at 165 lines
  Then no trim directive is emitted, whatever the line count
  And the append-mode directive is emitted with a warning naming the failure
```

**Edge cases**

```gherkin
Scenario: A heading inside a fenced code block does not end a region
  Given a [KEEP] region whose body contains a fenced example with a "## " line in it
  When the region parser runs
  Then the inner line is body, and the region ends only at a heading outside any fence

Scenario: A [KEEP] heading inside a fenced code block does not open a region
  Given a fenced example containing the line "## Standing rules [KEEP]"
  When the region parser runs
  Then no region opens, and that text is not protected

Scenario: A tilde fence does not close a backtick fence
  Given a region body opening a fence with three backticks and later three tildes
  When the region parser runs
  Then the fence is still open, and the tilde line is body

Scenario: The notepad is deleted while a snapshot is pending
  Given PT exists and SS has been removed
  When the turn ends
  Then the guard treats every protected line as missing and blocks
  And the reason points at PT as the recovery source

Scenario: Two sessions in one repo do not blind each other
  Given sessions A and B are both live in the same repo
  When A finishes a turn and deletes its own snapshot
  Then B still has its own snapshot, and the next turn of B is checked and archived normally

Scenario: A stale snapshot is reaped
  Given a snapshot file whose mtime is 30 hours old and whose session is gone
  When slim-session-start.sh runs
  Then the snapshot is appended to AR before deletion, never discarded

Scenario: The archive crosses the rotation threshold
  Given AR is 1,040,000 bytes and the pending append is 20,000 bytes
  When the guard appends
  Then AR is renamed to session-state.archive.1.md and a fresh AR holds the new block
  And no bytes are deleted

Scenario: Rotation numbering with gaps
  Given session-state.archive.1.md and session-state.archive.4.md exist
  When rotation runs
  Then the new name is session-state.archive.5.md, one above the highest existing number

Scenario: A block that looks like a secret is archived but not indexed
  Given a removed block matching the scan-secrets detection
  When the guard appends it
  Then the block is written verbatim and its heading records secrets: flagged
  And memsearch skips the whole file, so nothing is embedded

Scenario: A pane agent must not touch handoff state
  Given CLAUDE_PANE_AGENT is set
  When any of the four hooks runs
  Then it exits 0 immediately, matching live-handoff.sh:22 and post-edit-hook.sh:15

Scenario: Outside a repo, each hook keeps its existing behaviour
  Given git rev-parse --show-toplevel fails
  When live-handoff.sh runs
  Then it falls back to the working directory, unchanged from live-handoff.sh:24
  When slim-session-start.sh runs
  Then it exits 0 and emits nothing, unchanged from slim-session-start.sh:58
  When handoff-keep-guard.sh runs
  Then it exits 0 without blocking

Scenario: The reader truncates instead of blanking
  Given SS is 30,000 bytes, above the 24,576 read cap
  When slim-session-start.sh runs
  Then it prints whole lines in order until the budget is spent
  And then a line naming how many lines and bytes were withheld and the path to read
  And it never prints a partial line
  And if any withheld line was inside a [KEEP] region it says so explicitly

Scenario: The reader is unchanged below the cap
  Given SS is 9,000 bytes
  When slim-session-start.sh runs
  Then the whole body is emitted, sanitized exactly as today

Scenario: The guard has not run
  Given no session-state.keepguard.log exists in a repo whose notepad has changed
  When slim-session-start.sh runs
  Then the header says the guard has never run here

Scenario: PreCompact injects the live notepad
  Given .claude/session-state.md and a 2026-07-25 .claude/context.md both exist
  When pre-compact.sh runs
  Then session-state.md is emitted first, before context.md

Scenario: The pre-compact rewrite is protected too
  Given SS is 165 lines and compaction is about to run
  When pre-compact-handoff.sh emits its rewrite directive
  Then a snapshot was taken first
  And the directive names the raised targets, not 60-80
  And the [KEEP] headings are re-injected verbatim

Scenario: Archive files are never read at session start
  Given AR and three rotations exist
  When slim-session-start.sh runs
  Then it reads only session-state.md, and no archive bytes enter the context

Scenario: memsearch types the archive correctly
  Given AR exists and matches an entry in archive_globs
  When memsearch index runs
  Then its chunks carry source_type archive_doc and recall_type episodic, weight 1.0
  And a rotated file already indexed is hash-skipped on the next run

Scenario: A glob that matches nothing is reported
  Given an archive_globs entry matching no file on disk
  When memsearch index runs
  Then the run report names that glob as zero-match
  And the run does not silently read as nothing changed
```

### memsearch changes

The earlier version listed six hardcoded paths. Measured against the live population of **12**
notepads, those six covered only part of it — `~/.claude/.claude/card-d-non-text-contrast/`
and `~/.claude/.claude/worktrees/*/` were both missed — and a glob that matches nothing is
indistinguishable from "nothing changed" in the index report (finding O5).

```yaml
archive_globs:                       # glob.glob(..., recursive=True)
  - "~/.claude/**/session-state.archive*.md"
  - "~/Other Docs/**/session-state.archive*.md"
  - "~/.worktrees/**/session-state.archive*.md"
zero_match_globs_are_reported: true
```

Recursive globs anchored at the three roots that actually hold repos, so a new worktree or a
new project is covered without a config edit. Globs rather than `repo_roots` entries, so the
change does not sweep two entire unindexed repos into the index as a side effect.

Files matched this way are typed `archive_doc` regardless of which bucket found them,
preserving the reasoning at `index.py:50-58`. A file containing a `secrets: flagged` block is
skipped entirely.

The live `session-state.md` is deliberately **not** indexed: it changes every turn, and
`replace_source` (`index.py:220-226`) re-embeds a whole file on any content change.

**`archive_doc` is pre-poisoned as a health signal.** The existing `archive_doc` chunks are
the retired `CODING_MEMORY.md`, so "the archive_doc count went up" proves nothing until a
`--reclassify` run separates them. Task 10 covers that. The current count must be measured at
implementation time, not carried from this sentence.

### Non-functional requirements

- **Silent on failure, with two deliberate exceptions.** Hooks follow the house pattern
  (`slim-session-start.sh:10-12`): a failure never delays or breaks a session start. The
  exceptions are the `Stop` guard, whose purpose is to speak, and the snapshot-write failure
  in `live-handoff.sh`, which must be loud because it silently disarms the whole feature.
- **No secrets.** Archive files are gitignored (D12), confirmed per repo with
  `git check-ignore`, and scanned before append.
- **Idempotent.** Running any hook twice on unchanged state produces no second archive entry.
- **Bounded work.** The guard reads at most the snapshot and the current notepad.

### Known gaps, stated rather than hidden

1. The guard cannot see a notepad edit made by a subagent or a pane session — both exit early
   on `CLAUDE_PANE_AGENT`.
2. Enforcement is a momentum guardrail, not a security boundary. A model that wants to delete
   a protected line can delete the snapshot first.
3. The strike cap means a genuinely unrecoverable trim eventually proceeds. The full snapshot
   is archived in that case, so the text survives even though the notepad does not.
4. Existing oversize notepads are not migrated. This is not theoretical: `mtg-wizard` was
   measured at 235 lines / 13,455 bytes at 10:42 on 2026-09-08 and at **64 lines / 3,383
   bytes at 13:56 the same day** — roughly 171 lines cut, with no snapshot and no record,
   while this card sat waiting to be judged.
5. A `[KEEP]` region is protected only against deletion, not against being rewritten into
   something misleading. Membership matching cannot detect a line that was edited rather than
   removed; the archive is the only recourse there.
6. The exact `Stop` hook JSON contract is unverified. The published hooks documentation has
   been measured wrong before on decision values (memory:
   `reference_hook_permission_decision_values`). Task 7 must confirm the accepted shape
   against the installed binary, not the docs page, and pin the finding in a comment.
7. Secret detection reuses `scan-secrets.sh` logic and inherits every gap that hook already
   has. Flagging is best-effort; the guarantee is that a flagged block is not indexed, not
   that every secret is caught.

### Judge findings and where each was addressed

| Finding | Where |
|---|---|
| C1 unsourced metric (78 bytes per line) | R1 rewritten; cap 24,576; runtime test |
| C2 unverified "no data is lost" | Per-session snapshot; gap 5 replaced |
| C3 no snapshot below the cap | Snapshot every turn |
| C4 incomplete `[KEEP]` grammar | Full grammar section; 3 new scenarios |
| C5 strike counter never reset | Reset on success and on fail-open |
| C6 scenario contradicts `slim-session-start.sh:58` | Per-hook scenario, all three arms |
| C7 two scenarios with no `When` | Both rewritten |
| C8 raw notepad text in the block message | Headings and counts only, no body lines |
| C9 archive bypasses `scan-secrets.sh` | Scan before append; flagged blocks not indexed |
| O1 `pre-compact-handoff.sh` unmentioned | Added to changed files; own scenario |
| O2 guard silence reads as success | Liveness log + session-start report |
| O3 empty Verification section | Written, below |
| O4 R1 test cannot fail | Replaced with seeded-token test plus mutation |
| O5 hardcoded globs, zero-match invisible | Recursive globs; zero-match reported |
| O6 `archive_doc` pre-poisoned | Stated; `--reclassify` in task 10 |
| O7 root running log exposed | Fixed separately in `.gitignore:74-80` |

## Tasks

Ordered so every step is independently useful and nothing depends on a later step. Tasks 1-4
are the safety floor; 5-8 remove the loss; 9-11 are enforcement; 12-15 are reach.

- [ ] 1. `hooks/handoff/lib/handoff-archive.sh` — snapshot, `[KEEP]` region extraction with
      full fence tracking, archive append, rotation, secret flagging. Pure library, no hook
      wiring. Tests first, and the fence cases are the ones to write first.
- [ ] 2. `live-handoff.sh` snapshots on **every** turn to a per-session filename, and
      **suppresses the trim directive** if the snapshot cannot be written.
- [ ] 3. `.gitignore` coverage confirmed in all six repos holding a notepad — measured with
      `git check-ignore`, never assumed. Covers `session-state.archive*`, `.pretrim.*`,
      `.keepguard-strikes.*`, `.keepguard.log`.
- [ ] 4. Stale-snapshot reaper in `slim-session-start.sh`: append to the archive, then delete.
- [ ] 5. Raise the write caps to 150/120, 170/140, 190/160 in **both** `live-handoff.sh:40-49`
      and `pre-compact-handoff.sh:85`.
- [ ] 6. Raise `SLIM_HANDOFF_MAX_BYTES` to 24576 and replace the body-drop
      (`slim-session-start.sh:84-88`) with truncate-and-say.
- [ ] 7. Rewrite the trim directive in both hooks: cutting means filing into the archive, and
      the protected headings are re-injected verbatim.
- [ ] 8. Route `pre-compact-handoff.sh` through the same snapshot. This is the pre-clear path
      the original bug report came from.
- [ ] 9. `hooks/handoff/handoff-keep-guard.sh` as a `Stop` hook: protected-block check, strike
      cap with reset on both exits, mechanical archive append, liveness heartbeat. Block
      messages carry headings and counts only — never notepad body lines.
- [ ] 10. Confirm the `Stop` hook JSON contract against the installed binary, not the docs
      page, and pin the finding in a comment.
- [ ] 11. Register the guard in `settings.json` under `Stop`.
- [ ] 12. Guard-liveness reporting in `slim-session-start.sh`.
- [ ] 13. `pre-compact.sh` injects `session-state.md` first (D7).
- [ ] 14. memsearch: recursive `archive_globs`, zero-match reporting, `_doc_source_type`
      widened off the retired `CODING_MEMORY.md`, and a `--reclassify` run so `archive_doc`
      becomes a usable health signal.
- [ ] 15. Document the `[KEEP]` convention in `skills/managing-session-memory/SKILL.md`, and
      tag the sections that need protecting in this repo notepad as the first real use.

Split into `handoff-trim-safety.spec.md` at 719 lines, exercising the MAY in
`rules/gates.md` (one-canonical-file discipline). The card keeps frontmatter, tasks and
verification — what a restore needs; the companion keeps evidence, decisions and the spec —
what an implementer needs. There is no third progress document, and there will not be one.

The task list above is duplicated from `handoff-trim-safety.md` because
`hooks/feature-sync-guard.sh` requires both halves of a split pair to list the same
tasks (decision 6 of `docs/features/memory-system-split.md`). Ticking a box needs no
matching edit; adding or removing a task does.
