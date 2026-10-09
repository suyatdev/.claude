# 0045 — Cut text is never deleted, and the record that proves it never leaves this machine

- **Status:** Accepted (2026-09-10).
- **Context:** `hooks/handoff/lib/handoff-archive.sh` — `archive_rotate_if_needed()`,
  `archive_append()`, `quarantine_block()`, `file_removed_block()`, the
  `ARCHIVE_ROTATE_AT_BYTES` constant — and `.gitignore` (`/session-state.md`,
  `/session-state.archive*.md`, `/.claude/`). Full design, the user decisions (D1-D17), the
  measured evidence and the task list: `docs/features/handoff-trim-safety.spec.md` and
  `docs/features/handoff-trim-safety.md`. Standalone — does not amend a prior ADR.
- **Note:** ADR number **0045** confirmed free 2026-09-10, after fetching `origin`, by two
  independent checks: `origin/main` — the deciding ref — tops out at `0044`
  (`0044-a-split-test-suite-keeps-a-runner-at-the-paired-name.md`), and a history-wide
  `git log --all -- 'docs/decisions/0045*'` returns nothing, so no reachable commit on any ref
  has ever added a `0045`. A deliberate non-claim: no count of branches is stated here, because
  a branch count goes stale the moment anyone pushes and a stale count reads as audited.

## Decision

The text a trim cuts from `.claude/session-state.md` goes into a store with two properties,
and both are permanent commitments, not defaults that happened to be convenient:

1. **The store only grows.** Nothing is ever deleted from it — not by the model, not by a
   hook, not on a schedule. The one thing that changes over time is which *file* holds a given
   block, because the live file rotates once it gets large.
2. **The store never leaves this machine.** It is excluded from git on every repo that has
   one, so it is never pushed, never reviewable in a PR diff, and never visible to anyone who
   can only see the repo on GitHub.

A reader should care about both halves for the same reason: past this card, a trim of the
session notepad can no longer silently destroy a fact — but the guarantee is conditional.
"Never deleted" means never deleted *by this system*; it says nothing about disk failure or a
missing backup, and "never leaves this machine" is precisely what makes that limitation matter
(see Consequences).

### D11 — append-only, and it rotates instead of growing as one file

The mechanism is `archive_append()`: it calls `archive_rotate_if_needed()` before every write,
which renames the live archive to `<prefix>.<N>.md` (N one above the highest existing rotation
number) whenever the pending write would push it past `ARCHIVE_ROTATE_AT_BYTES` (1,048,576 —
1 MiB). A rotated file is never opened for append again.

**Rejected: let the archive grow as one unbounded file.** This was the design's own earlier
in-session recommendation, and it was reversed once the memsearch indexer was checked rather
than assumed: `_index_one()` in `memsearch/memsearch/index.py` skips a source outright when its
content hash is unchanged, and otherwise re-chunks and re-embeds it **in full** before calling
`replace_source()` (defined in `memsearch/memsearch/db.py`). So an ever-growing single file
would be re-embedded from byte zero, forever, on every index run — every 21600 seconds, six
hours, per `memsearch/launchd/local.memsearch-index.plist.template` — cost that scales with
total history rather than with what actually changed. A rotated file's content never changes again once sealed, so
it is hash-skipped for the rest of its existence; only the current live file pays the
re-embed cost, and that cost is capped at ~1 MiB regardless of how much history exists
behind it.

**Rejected: let old content be deleted (pruned, expired, or summarized away).** This is not a
separate alternative so much as the exact failure the whole card exists to close — D2 already
settled that cut text is never deleted; D11 only answers *how the store stays append-only
without becoming one unbounded file*, and rotation is a filing detail, not a re-opening of D2.

### D12 — permanent, but never tracked in git, and machine-local

Verified directly (`gh repo view suyatdev/.claude --json isPrivate` → `false`, re-checked this
session): `suyatdev/.claude` is a public GitHub repository. Session narrative — the material
this archive exists to preserve — routinely contains half-formed notes, credentials mentioned
in passing, and other material nobody reviewed for publication. `.gitignore` excludes it by
name: `/session-state.md`, `/session-state.archive*.md` for this repo's own hand-kept notepad
(`.gitignore:78-80`), and `/.claude/` wholesale for the hook-managed notepad every other repo
writes under its own `.claude/` directory (`.gitignore:87`) — both re-verified this session
with `git check-ignore -v` against a synthetic rotated-archive path and a synthetic
`.claude/session-state.quarantine.md` path, each reporting the expected rule.

**Rejected: track the archive in git**, the direct alternative named by the spec's own framing
of this decision ("Gitignore or track"). Rejected on the same fact above — tracking it would
publish raw session narrative from a repo confirmed public, which is the leak D12 exists to
prevent.

### The one deletable exception (D16), and why it does not weaken D11

`file_removed_block()` runs every cut block through `block_has_secret()` before it reaches the
archive at all. A block that scans clean goes to `archive_append()` as usual. A block that
looks like credential material is instead written verbatim by `quarantine_block()` to a
separate `session-state.quarantine.md`, and the archive gets only a heading-only stub — the
flagged content itself never enters the append-only store. `session-state.quarantine.md` is
gitignored under the same `/.claude/`-wholesale or named-pattern rules as the archive, but
unlike the archive it is meant to be opened and deleted by hand once its contents are dealt
with. This is the one place "never deleted" does not hold, and it holds there on purpose: D11's
promise is only safe to make unconditionally for everything else *because* the one category
that would make "never deleted, forever, on disk" actually dangerous has a manual exit.

## Consequences

- **The store has no size ceiling and no automated pruning, by design.** Rotation bounds each
  individual file at ~1 MiB; nothing bounds how many rotated files accumulate over the life of
  a repo. This is the direct, accepted cost of "never deleted" — it is not a gap to be closed
  later, it is what the decision means.
- **"Permanent" is not the same claim as "durable."** Because the store is gitignored and
  machine-local, its only copy is whatever is on that one machine's disk. The spec records that
  a Time Machine destination exists but that its currentness could not be confirmed in this
  environment (`tmutil latestbackup` requires Full Disk Access this shell does not have) — so
  this ADR does not claim the archive is backed up. A lost or failed disk loses the archive
  along with everything else on it, and nothing in this design detects or alarms on that.
- **The re-embed cost is not eliminated, only bounded.** The live (not-yet-rotated) file is
  still re-embedded in full on every indexing pass until it rotates; D11 caps that cost at
  ~1 MiB rather than removing it. Indexing the archive at all is separately still open work
  (`docs/features/handoff-trim-safety.md` task 15, unchecked as of this ADR) — nothing above
  should be read as claiming the archive is indexed today, only that D11's rotation shape is
  what makes indexing it affordable once that task lands.
- **The quarantine carve-out is manual and unenforced beyond the initial routing.** Nothing
  audits whether a human ever revisits `session-state.quarantine.md`; it can sit un-purged
  indefinitely, in which case it inherits the same no-backup exposure as the archive without
  even the append-only guarantee to show for it.
