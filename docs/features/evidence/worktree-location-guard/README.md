# Criterion-3 evidence — `worktree-location-guard`, task 10

Committed extracts of the two guard logs, taken so the per-row review that reads them survives
the session that ran it. The previous review (2026-09-07/08) wrote its verdicts to a session
scratchpad; that scratchpad is gone, and only a prose summary in the card remains. Task 10 records
that lesson as an instruction: commit the artifacts before relying on them.

Both source logs live under `hooks/state/`, which is **gitignored** — they exist only in the
primary checkout and never travel with a branch. These extracts are the copies that do.

## Provenance

Extracted 2026-09-16 from `/Users/marksuyat/.claude/hooks/state/`, whose contents at that moment
hashed to:

| source log | sha256 at extraction |
|---|---|
| `reference-transaction.log` | `291c9c100cdcc2b7c75974b64e8d9e92d7ecb76d4bf5baae97cd59881b7fb527` |
| `worktree-guard.log` | `b86eddbf4acf68155fb4703d48ce3046a81e3428943a479052b430a3f0bc266d` |

Both logs are append-only and were still being written to by live sessions during extraction, so a
later hash will differ. The hash pins *which prefix* these extracts came from, not the file forever.

## `layer2-would-deny.tsv` — 1226 lines

Every `WOULD-DENY` line in `reference-transaction.log`, the whole log, unfiltered by date.

The window is the whole log because **layer 2's code has not changed since it was armed**:
`~/.config/git/hooks/reference-transaction` is dated 2026-09-01 16:06, the arming run recorded in
the card. Every line was therefore written by the code that is live now, and layer 2 has never had
its per-row review.

Six tab-separated fields: timestamp, session id (always empty in this log), arm (always `D-L2`),
mode (always `log`), decision-and-reason, target path.

## `layer1-post-fix-would-deny.tsv` — 76 lines

Every line in `worktree-guard.log` with a timestamp at or after `2026-09-14T20:41`.

That cut is deliberate and is **not** the whole log. Layer 1's tilde defect was fixed and merged as
PR #103 (`270a0b9`, 2026-09-14 16:40:31 -0400); the primary checkout's `hooks/worktree-guard.sh`
carries the fix with mtime 16:41 the same day. Hooks run from the primary, so lines written before
that instant came from the **old, defective** guard — the very lines the 2026-09-07/08 review read
when it found four wrong refusals. Criterion 3 has to be re-run against lines the fixed guard wrote,
and this file is those lines.

Seven tab-separated fields: timestamp, session id, arm, mode, decision, cwd, target-or-command.

## What these files can and cannot establish

Both logs record only what the guard **turned away**. A command the guard failed to recognise leaves
no line at all, so a guard blind to an entire shape produces a log that reads flawless. These
extracts measure **precision** — of the refusals recorded, were they right — and never coverage.
Coverage is what `hooks/worktree-guard.test.sh` asserts, against shapes chosen deliberately rather
than shapes that happened to be typed.

Layer 1 also runs in `log` mode, where a failed append loses a line silently. The log is best-effort
and its completeness is not guaranteed.

Full statement of the criteria, and what each one does and does not establish:
[`../../worktree-location-guard.md`](../../worktree-location-guard.md), task 10.
