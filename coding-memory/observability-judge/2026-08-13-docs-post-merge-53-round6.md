# Observability judge verdict — verification-marker-gate, round 6 (architecting, advisory)

- repo: `tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `3f068d9fba35f6dcee46007c27dcf3bdd37be2b2`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`)
- ts: `2026-08-13T19:51:59Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 13, 1,721 lines, `wc -l` confirmed;
  waived past the 800-line ceiling by explicit user decision)
- prior verdict: `2026-08-13-docs-post-merge-53-round5.md` (head `f95e94b`, architecting, risk=medium)

## What was changed

Revision 13 answers all three round-5 advisories: (1) the decision log's write side is now pinned to
`printf`, with `echo` named and shown as the trap; (2) a self-contradiction between §Marker store and
§Decision logging over who creates `hooks/state/` is resolved — §Decision logging is now the sole
authority — and a new measured fact (`mkdir -p -m 0700` against an existing `0755` directory exits 0
and leaves it `0755`) drives a `mkdir -m` **+** `chmod` requirement; (3) tasks 6 and 14 now assert log
lines by field (`awk -F'\t' 'END{print NF}'` / `cut -f2`), never by `grep` or line presence.

## Does it do what you wanted?

Yes for all three, and I did not take the document's word for any of them — I reproduced each
independently on the pinned bash 3.2.57 before scoring it:

```
$ bash -c 'echo "$ts\t$verdict\t$reason\t$pair" > /tmp/echo_log.txt'
$ awk -F'\t' 'END{print NF}' /tmp/echo_log.txt   → 1
$ cut -f2 /tmp/echo_log.txt                       → the whole line, literal backslash-t

$ bash -c "printf '%s\t%s\t%s\t%s\n' ... > /tmp/printf_log.txt"
$ awk -F'\t' 'END{print NF}' /tmp/printf_log.txt  → 4
$ cut -f2 /tmp/printf_log.txt                     → EXEMPT
```

Task 6/14's new by-field assertions genuinely distinguish these two cases — a line-presence check
would not have. I also reproduced the `mkdir -m` claim directly:

```
$ mkdir -m 0755 /tmp/d && mkdir -p -m 0700 /tmp/d; echo exit=$?; ls -ld /tmp/d
exit=0
drwxr-xr-x  ...  /tmp/d          # stayed 0755 — matches the spec's claim exactly
```

and confirmed the fix pattern actually closes it: `mkdir -p -m 0700` on a *fresh* path is immune to
umask on this machine (`umask 022; mkdir -p -m 0700 new` → `drwx------`), and the unconditional
trailing `chmod 0700` closes the pre-existing-directory case regardless of who arrives first — the
pairing is sound, and I verified `git diff f95e94b..3f068d9` touches only the doc and
`CODING_MEMORY.md`, with the changelog entry matching the diff exactly (no drive-by edits).

Point by point against this round's three questions:

**1. Does revision 13 change the view of the "writer with no reader" gap?** Only partially, and the
document is honest about the part that doesn't move. The log is now reliably *parseable* — that closes
a real risk (a corrupted, unreadable log masquerading as a working one). It does not add a reader:
`--status` is still deferred, and an empty `test-marker.log` still cannot be told apart from "armed and
nothing has gone wrong" versus "armed but pairing silently never fires." That is unchanged from round
5 and the document says so in the same paragraph it did last round (§Decision logging, the ⚠️ callout).
Not a new finding — carried forward as still-open.

**2. Is task 14 now sufficient as the sole arming proof?** For the specific failure mode it was
tightened against — a checker that reports "armed" while silently refusing every exemption — yes, the
field-level assertion closes it, and I verified the assertion actually discriminates (above). But task
14 is still what the document itself calls it: a one-shot, manually-run check against the *installed*
copy at PR time, not a continuously-running regression guard. It cannot detect the gate going inert
later in a repo where nothing has yet tripped it — again, the document's own stated residual risk, not
new information this round.

**3. Are revision 13's own failure modes observable — specifically, does anything catch a skipped
`chmod`?** For `hooks/state/` itself: yes. Task 6 (line 1554-1559) explicitly requires three cases —
gate-first, writer-first, and pre-create-at-`0755` — each asserting `0700` afterward; the third case is
exactly the one `mkdir -p -m` alone cannot satisfy, so an implementer who drops the `chmod` fails that
test directly, before any code reaches Green.

But I found a fourth case the sweep missed, and it sits one paragraph below the fix that was just
written. **`test-marker.log` has the identical race and the identical stated `0600` requirement as
`hooks/state/`, and unlike the directory it has *no* mkdir/chmod-style code sample, no checklist test,
and no Gherkin scenario at all.** I verified the exposure directly:

```
$ rm -f /tmp/log.txt
$ bash -c 'umask 022; printf "%s\n" hello >> /tmp/log.txt'
$ ls -l /tmp/log.txt
-rw-r--r--  ...  /tmp/log.txt        # 0644, not the spec's stated 0600
```

The append idiom the spec itself prescribes for writing log lines (`printf ... >> "$LOG"`, shown as the
CORRECT sample two paragraphs above) is exactly the idiom that creates the file at umask-derived
permissions when it doesn't yet exist — no different, structurally, from the directory bug just fixed.
The document states the threat model for this specific file by name — "On a permissive umask the
alternative publishes a trail naming every commit someone chose to bypass the gate for" — but the fix
that would close it (an idempotent `touch`/`chmod 0600` pair, mirroring the directory's `mkdir -m` +
`chmod` pair, run by whichever of writer/gate arrives first) is not specified anywhere, and task 6's new
dual-creator-race cases assert `0700` on the *directory* only, never `0600` on the *file*.

## What could go wrong / what I'm unsure about

- **`test-marker.log`'s own mode is stated four times as `0600` and enforced nowhere.** Same dual-writer
  race the directory just got fixed for, same stated core-conduct rationale, no code sample, no test.
  Verified directly: the spec's own prescribed append idiom yields `0644` under a stock `022` umask.
  This is the same defect species revision 13 just fixed twice (for the directory and for the log
  format) — found this round in the one place the sweep didn't reach.
- The writer-with-no-reader gap is unchanged from round 5: `--status` remains deferred, and the log's
  now-guaranteed parseability doesn't add a way to distinguish silence from healthy operation. Carried
  forward, not new.
- Task 14 remains a manual, point-in-time check, not a regression gate — disclosed by the document
  itself as the reason `--status` is a real, not cosmetic, follow-up.
- Everything above is still a property of the plan. Checklist is 0/15; nothing has run.
- File continues to grow under the existing waiver (1,652 → 1,721 lines, +69) — not a new violation,
  still worth a glance if the rate keeps climbing.

## What I'd double-check before merging

- Add the same `touch`/`chmod 0600` (or equivalent idempotent, order-independent) pattern for
  `test-marker.log` that §Decision logging now specifies for `hooks/state/`, and extend task 6's
  dual-creator-race cases (both orderings + pre-existing-wrong-mode) to cover the log file's own mode,
  not only the directory's.
- Confirm the eventual `write-test-marker.test.py` (task 4) actually asserts marker-file mode via
  `stat`, not just existence — flagged in round 5, not re-verified this round, still open for the
  implementation stage.
- When `--status` is scheduled, re-check whether it should also report "log file mode as observed"
  (`stat`) as a cheap way to surface exactly the gap found this round without waiting for a security
  review to notice it.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | pass | All three round-5 advisories addressed directly, each independently reproduced on the pinned bash rather than taken on faith. |
| execution | concern | No code exists yet (expected at this stage); the newly-fixed directory-mode race left an identical, unfixed sibling race on `test-marker.log` itself, verified exploitable under a stock umask. |
| trajectory | concern | The fixes applied are sound and evidence-driven, but for the second round running the author's sweep fixed exactly the flagged instance and missed the adjacent sibling of the same defect class, written two paragraphs away in the same subsection. |
| regression | pass | No code exists; the prose change is scoped to the three flagged sections plus the required changelog. |
| context_budget | pass | `docs/features/`, read on demand; +69 lines this revision, under the already-granted waiver — not a new violation. |
| traceability | pass | Every claim (printf/echo, mkdir/umask) is stated as a runnable command with the exact bash version; I reproduced all of them independently and they matched exactly. |
| success_masking | concern | `test-marker.log`'s stated `0600` is enforced by nothing — no code sample, no chmod, no test — so a green task-6 suite (which only checks the directory) could ship a world-readable log naming every bypass reason and the local paths involved, on any repo with a standard umask. |
| intent_drift | pass | Diff is scoped to exactly the three flagged items plus changelog; verified via `git diff` that only the doc and `CODING_MEMORY.md` moved, matching the commit message line for line. |
| checkpoint | pass | Single isolated commit `3f068d9` on a clean chain; working tree clean; trivially revertible. |
| audit_trail | pass | Commit message and in-doc revision-13 annotations both name the round-5 finding they answer; `CODING_MEMORY.md` entries are dated and attributed. |

## Concerns

- `test-marker.log`'s own `0600` mode has no enforcement mechanism (no `touch`/`chmod` pair, unlike the
  directory) and no test — verified directly that the spec's own prescribed `printf ... >> "$LOG"`
  append idiom yields `0644` under a standard `022` umask, exposing bypass reasons and local paths.
  Same defect species revision 13 fixed twice already (directory race, log format), found this round in
  the adjacent spot the sweep didn't reach.
- The writer-with-no-reader instrumentation gap is unchanged from round 5 (`--status` still deferred);
  the log is now reliably parseable but still cannot distinguish silent health from silent failure.
  Carried forward, not new — the document discloses this itself.
- Task 14 remains a one-shot manual check, not an automated regression gate, once `--status` stays
  deferred — the reason risk stays medium rather than low, same as round 5.
- Still 0/15 implemented; every finding here is a property of the plan, verified against the pinned
  toolchain, not of running code.

risk=medium confidence=high
