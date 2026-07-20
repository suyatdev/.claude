# ADR 0005 — Serialise the statusline token counter with a mkdir lock, and store its state as plain text

**Status:** Accepted (2026-07-19)

## Context
The statusline's Σ segment keeps a per-session running token total in
`~/.claude/statusline-state/`. Each render reads the total, adds the current
call, and writes it back. That read-modify-write was unguarded, so two renders
that overlap both read the same starting value and the later write erases the
earlier one — a lost update.

The observability judge flagged this (risk=high) with a two-writer repro:
seed 200, concurrent +1000/+1400, stored 1200 rather than 2600. Reproducing it
at 20 writers showed it is much worse than that framing suggests: against a
seeded 200 the file stored **1213**, the seed plus exactly one writer. Under
real concurrency the counter reported roughly a single call regardless of how
many calls occurred.

The existing atomic-`mv` write did not and could not help. It guards a torn
*read*; this is a lost *update*. The in-script comment conflated the two, which
is why the gap survived review.

## Decision
Serialise the read-modify-write with a `mkdir`-based lock, re-reading the total
*inside* the lock, and store the state as two lines of plain text instead of
JSON.

`mkdir` is the primitive because it is atomic on every POSIX filesystem and
needs no `flock`, which macOS does not ship. The holder's PID is recorded inside
the lock so an orphaned lock can be cleared rather than wedging the counter.

The plain-text format is not cosmetic — it is what makes the lock viable. JSON
required two `jq` forks (~8ms measured) inside the critical section, and a
section that long cannot serialise several waiting renders inside any delay a
prompt can absorb. Plain text is read with the `read` builtin, leaving one `mv`
as the only fork under the lock.

## Options weighed
- **Lockfile (chosen):** correct totals. Costs a bounded wait and a stale-lock
  recovery path. Selected by the user over the alternatives below.
- **Document the undercount honestly:** zero new failure modes, but leaves a
  number that is wrong by an order of magnitude under concurrency — which is
  not an "approximate" total, it is a misleading one.
- **Lock with fallback to an unlocked write on timeout:** keeps the common case
  correct without ever waiting long, but retains the corruption path it was
  meant to close, and still needs the undercount documented.

```mermaid
flowchart TD
    A[render has new usage] --> B{acquire lock?}
    B -->|yes| C[re-read total INSIDE lock]
    C --> D{signature already recorded?}
    D -->|yes| E[skip: another render counted it]
    D -->|no| F[add, write via temp + rename]
    F --> G[release lock]
    E --> G
    B -->|timeout ~390ms| H[skip update, leave signature unstored]
    H --> I[next render retries the same usage]
```

## Breaking a stale lock (added after review)

The first implementation cleared a stale lock with `rm -rf`. That is itself a
lost-update bug: several renders each judge the same lock stale, and a removal
landing after another render has legitimately acquired the lock deletes a *live*
lock. The observability judge found and reproduced this — the mechanism built to
prevent lost updates was causing them.

Two changes fix it, and the first alone was measured insufficient:

1. **Break by renaming, never by removing in place.** `rename()` is atomic, so
   one breaker wins and the losers see `ENOENT`. The winner only ever deletes the
   directory it captured, never the live path, and verifies the capture is the
   lock it judged before deleting — restoring it on a mismatch.
2. **Serialise the breakers.** Renaming alone still failed 4 runs in 10, because
   twenty renders each acted on a judgement already out of date by the time they
   acted. A second `mkdir` lock means only one render ever attempts a break, and
   it re-reads the holder *inside* that lock so its judgement is current.

Releasing is ownership-checked for the same reason: a render whose lock was
broken and re-taken must not remove the new holder's lock on its way out.

**Residual window, accepted deliberately:** if the single breaker captures a
lock a fresh holder took between its judgement and its rename, it restores the
directory; should that restore lose to a newer lock, the captured directory is
dropped. This needs an interleaving within two syscalls, costs one wrong
cosmetic total, and self-heals on the next render. Closing it properly requires
a compare-and-swap the filesystem does not offer.

## Consequences
- Totals are exact under normal concurrency: 20 concurrent renders against a
  seeded 100 store the full 510, verified over repeated suite runs, and the
  stale-lock-breaking path is clean over 20 consecutive runs. **Not
  unconditionally exact** — the residual window above remains, as does the
  skip-on-timeout behaviour below. An earlier draft of this ADR claimed
  exactness outright; that was an overclaim and the judge was right to flag it.
- **Failing to acquire is not an error.** The update is skipped, and because the
  signature is not stored either, the next render retries the same usage — so a
  timeout is usually deferral, not loss. It is only a real loss when usage moves
  on before any retry wins the lock, which needs sustained contention.
- **Worst-case added latency is ~390ms**, paid only by a render that never
  acquires. This is sized above the ~314ms measured for 20 concurrent renders to
  drain: a budget below the drain time does not degrade gracefully, it
  structurally guarantees the last waiters give up. A 10-attempt (~190ms) budget
  was tried first and failed the concurrency test every run at 387–495 of 510.
  The dominant cost is the fork of `/bin/sleep` (~9ms), not the sleep interval —
  so tune `LOCK_ATTEMPTS`, never `LOCK_SLEEP`.
- Legacy `session-*.json` state files are inert leftovers; the new reader
  rejects them on charset validation, so affected counters restart from the
  current call once. Cosmetic and one-time.
- Stale locks are cleared by PID liveness (`kill -0`), falling back to age for a
  lock whose holder died before writing its PID. A *young* pid-less lock is
  deliberately left alone — that is the normal microseconds-long window of a
  healthy holder, and breaking it would reintroduce the lost update.
- A PID that *looks* alive is not trusted indefinitely: PIDs are reused after
  wraparound, and `kill -0` cannot tell a reused PID from the original holder,
  so without a backstop such a lock would wedge a session's counter permanently
  and silently. The age backstop runs only after the spin is exhausted, keeping
  its `find` fork off the contended path; the counter recovers on the next
  render. A breaker lock orphaned by a killed render is cleared the same way.
- **Revisit trigger:** if the statusline ever renders from more than a handful
  of concurrent processes per session, or if the ~390ms ceiling becomes visible
  in practice, the fork-dominated spin is the thing to replace — a real `flock`
  (via a helper) removes both the spin and its ceiling.
